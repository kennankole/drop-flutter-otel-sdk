import 'dart:async';

import 'package:opentelemetry/api.dart' as api;
import 'package:opentelemetry/sdk.dart' as sdk;

/// Batch/queue policy for span export (OBSERVABILITY_STRATEGY.md Phase
/// 3.4). Flushes on a timer ([scheduledDelay], default 60s — matching the
/// strategy's "batch ≥60s") or when [forceFlush]/[shutdown] is called
/// (L5's `WidgetsBindingObserver` pause hook uses this).
///
/// The "512KB" byte-size trigger from the original strategy doc is *not*
/// implemented: the SDK has no concept of payload byte size, only span
/// count, and measuring real serialized size would mean protobuf-encoding
/// every span just to check its weight. [maxQueueSize] is a count-based
/// approximation instead — documented here rather than silently dropped.
class ExportPolicyConfig {
  const ExportPolicyConfig({
    this.maxQueueSize = 500,
    this.scheduledDelay = const Duration(seconds: 60),
  });

  /// Bounded queue size. On overflow, the *oldest* buffered span is
  /// dropped to make room for the newest (design principle 5). This is
  /// the opposite of [sdk.BatchSpanProcessor]'s own queue, which drops
  /// the *newest* span on overflow and has a fixed, non-configurable size
  /// of 2048 — confirmed by reading its source, not documented anywhere.
  /// That's why this package owns its own [sdk.SpanProcessor] instead of
  /// using the SDK's.
  final int maxQueueSize;

  /// How often the queue flushes on its own, absent a forced flush.
  final Duration scheduledDelay;
}

/// Own [sdk.SpanProcessor] implementation — see [ExportPolicyConfig] for
/// why [sdk.BatchSpanProcessor] doesn't fit. Export itself still goes
/// through an [sdk.SpanExporter] (see otlp_client.dart); this class only
/// owns the queue and batching decision, same division of labor as the
/// SDK's own processor/exporter split.
class DropSpanProcessor implements sdk.SpanProcessor {
  DropSpanProcessor(this._exporter, [ExportPolicyConfig? config])
    : _config = config ?? const ExportPolicyConfig() {
    _timer = Timer.periodic(_config.scheduledDelay, (_) => _exportAll());
  }

  final sdk.SpanExporter _exporter;
  final ExportPolicyConfig _config;
  final _buffer = <sdk.ReadOnlySpan>[];
  late final Timer _timer;
  bool _isShutdown = false;

  int get queueLength => _buffer.length;

  @override
  void onStart(sdk.ReadWriteSpan span, api.Context parentContext) {}

  @override
  void onEnd(sdk.ReadOnlySpan span) {
    if (_isShutdown) return;
    if (_buffer.length >= _config.maxQueueSize) {
      _buffer.removeAt(0);
    }
    _buffer.add(span);
  }

  @override
  void forceFlush() {
    if (_isShutdown) return;
    _exportAll();
  }

  @override
  void shutdown() {
    forceFlush();
    _isShutdown = true;
    _timer.cancel();
    _exporter.shutdown();
  }

  void _exportAll() {
    if (_buffer.isEmpty) return;
    final batch = List<sdk.ReadOnlySpan>.of(_buffer);
    _buffer.clear();
    _exporter.export(batch);
  }
}
