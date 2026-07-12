import 'package:drop_observability/src/export/export_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentelemetry/sdk.dart' as sdk;

/// Captures every batch handed to [export] so tests can assert on what
/// [DropSpanProcessor] actually sent, without a real network call.
class _CapturingExporter implements sdk.SpanExporter {
  final batches = <List<sdk.ReadOnlySpan>>[];

  @override
  void export(List<sdk.ReadOnlySpan> spans) => batches.add(spans);

  @override
  void forceFlush() {}

  @override
  void shutdown() {}

  List<String> get exportedNames =>
      batches.expand((b) => b).map((s) => s.name).toList();
}

/// Builds real, valid [sdk.ReadOnlySpan]s without attaching any real
/// exporter — a bare [sdk.TracerProviderBase] with no processors is a
/// pure span factory for these tests.
sdk.ReadOnlySpan _span(String name) {
  final provider = sdk.TracerProviderBase();
  final span = provider.getTracer('test').startSpan(name);
  span.end();
  return span as sdk.ReadOnlySpan;
}

void main() {
  group('DropSpanProcessor', () {
    // L5 acceptance criterion: "Queue overflow drops oldest without error".
    test('drops the oldest span on overflow, not the newest', () {
      final exporter = _CapturingExporter();
      final processor = DropSpanProcessor(
        exporter,
        const ExportPolicyConfig(
          maxQueueSize: 3,
          scheduledDelay: Duration(days: 1), // never fires during the test
        ),
      );

      for (var i = 0; i < 5; i++) {
        processor.onEnd(_span('span-$i'));
      }
      expect(processor.queueLength, 3);

      processor.forceFlush();

      // span-0 and span-1 were evicted to make room; span-2..4 survive.
      expect(exporter.exportedNames, ['span-2', 'span-3', 'span-4']);
    });

    test('overflow never throws', () {
      final processor = DropSpanProcessor(
        _CapturingExporter(),
        const ExportPolicyConfig(
          maxQueueSize: 1,
          scheduledDelay: Duration(days: 1),
        ),
      );
      expect(() {
        for (var i = 0; i < 20; i++) {
          processor.onEnd(_span('span-$i'));
        }
      }, returnsNormally);
    });

    // L5 acceptance criterion: "batch timing test".
    test('does not export before scheduledDelay elapses', () async {
      final exporter = _CapturingExporter();
      DropSpanProcessor(
        exporter,
        const ExportPolicyConfig(scheduledDelay: Duration(seconds: 10)),
      ).onEnd(_span('span-0'));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(exporter.batches, isEmpty);
    });

    test('exports automatically once scheduledDelay elapses', () async {
      final exporter = _CapturingExporter();
      DropSpanProcessor(
        exporter,
        const ExportPolicyConfig(scheduledDelay: Duration(milliseconds: 50)),
      ).onEnd(_span('span-0'));

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(exporter.exportedNames, ['span-0']);
    });

    test('forceFlush exports immediately without waiting for the timer', () {
      final exporter = _CapturingExporter();
      final processor = DropSpanProcessor(
        exporter,
        const ExportPolicyConfig(scheduledDelay: Duration(days: 1)),
      );
      processor.onEnd(_span('span-0'));

      processor.forceFlush();

      expect(exporter.exportedNames, ['span-0']);
    });

    test('forceFlush on an empty queue does not export an empty batch', () {
      final exporter = _CapturingExporter();
      DropSpanProcessor(exporter).forceFlush();
      expect(exporter.batches, isEmpty);
    });

    test('shutdown flushes remaining spans then stops accepting new ones', () {
      final exporter = _CapturingExporter();
      final processor = DropSpanProcessor(
        exporter,
        const ExportPolicyConfig(scheduledDelay: Duration(days: 1)),
      );
      processor.onEnd(_span('span-0'));

      processor.shutdown();
      expect(exporter.exportedNames, ['span-0']);

      processor.onEnd(_span('span-1')); // must be ignored, not queued
      expect(processor.queueLength, 0);
    });
  });
}
