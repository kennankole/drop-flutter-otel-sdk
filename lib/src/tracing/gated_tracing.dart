import '../config.dart';
import 'span.dart';
import 'tracer.dart';

/// A [DropTracing] that consults `gates.otelEnabled` on every span instead
/// of once at `init()`.
///
/// Apps back their gates with remote config, which is rarely fetched by the
/// time `init()` runs — the gate read at startup was usually the cached or
/// default value, so a cold install on a slow network kept tracing off for
/// the whole session. Here a late fetch that turns tracing on takes effect
/// on the next span, and turning it off stops new spans straight away.
///
/// The real tracer is built on first use, so an app that never enables
/// tracing never starts an exporter or its flush timer. Once built it is
/// kept: spans already open still end and flush through it.
class GatedDropTracing implements DropTracing {
  GatedDropTracing({
    required ObservabilityGates gates,
    required DropTracing Function() buildReal,
  }) : _gates = gates,
       _buildReal = buildReal;

  final ObservabilityGates _gates;
  final DropTracing Function() _buildReal;
  DropTracing? _real;

  static const _off = NoopDropTracing();

  /// Whether the real tracer has been built — i.e. tracing was on at least
  /// once this session.
  bool get isRealTracingStarted => _real != null;

  @override
  DropSpan startSpan(
    String name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  }) {
    final tracing = _gates.otelEnabled ? (_real ??= _buildReal()) : _off;
    return tracing.startSpan(
      name,
      parentContext: parentContext,
      attributes: attributes,
    );
  }

  @override
  void forceFlush() => _real?.forceFlush();

  @override
  DropSpanContext? get activeContext => _real?.activeContext;
}
