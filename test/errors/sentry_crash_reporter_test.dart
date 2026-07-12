import 'package:drop_observability/drop_observability.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// A [DropTracing] fake exposing a fixed [activeContext] — isolates these
/// tests from [RealDropTracing]/[NoopDropTracing], which have their own
/// coverage in tracing/tracer_test.dart.
class _FakeTracing implements DropTracing {
  _FakeTracing([this.activeContext]);

  @override
  final DropSpanContext? activeContext;

  @override
  DropSpan startSpan(
    String name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  }) => throw UnimplementedError('not used by these tests');

  @override
  void forceFlush() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SentryCrashReporter', () {
    SentryEvent? captured;

    setUp(() async {
      captured = null;
      // beforeSend is the seam: it sees the fully scope-enriched event and
      // can cancel the send (return null), so no real network I/O happens
      // in these tests and we can assert on exactly what would have shipped.
      await SentryFlutter.init((options) {
        options.dsn = 'https://public@o1.ingest.sentry.io/1';
        options.beforeSend = (event, {hint}) {
          captured = event;
          return null;
        };
      });
    });

    tearDown(() async {
      await Sentry.close();
    });

    test(
      'recordError tags otel.trace_id/otel.span_id when a span is active',
      () async {
        final context = DropSpanContext();
        final reporter = SentryCrashReporter(
          ringBuffer: LogRingBuffer(),
          tracing: _FakeTracing(context),
        );

        await reporter.recordError(Exception('boom'), StackTrace.current);

        expect(captured, isNotNull);
        expect(captured!.tags?['otel.trace_id'], context.traceId);
        expect(captured!.tags?['otel.span_id'], context.spanId);
      },
    );

    test('recordError omits trace tags when no span is active', () async {
      final reporter = SentryCrashReporter(
        ringBuffer: LogRingBuffer(),
        tracing: _FakeTracing(), // activeContext == null
      );

      await reporter.recordError(Exception('boom'), StackTrace.current);

      expect(captured, isNotNull);
      expect(captured!.tags?['otel.trace_id'], isNull);
    });

    // L3 acceptance criterion: "error event carries log tail".
    test('recordError attaches the ring buffer as a log_tail extra', () async {
      final ringBuffer = LogRingBuffer()
        ..add('[warning] poll degraded')
        ..add('[error] boom');
      final reporter = SentryCrashReporter(
        ringBuffer: ringBuffer,
        tracing: _FakeTracing(),
      );

      await reporter.recordError(Exception('boom'), StackTrace.current);

      final tail = (captured!.contexts['log_tail'] as Map?)?['text'] as String?;
      expect(tail, isNotNull);
      expect(tail, contains('poll degraded'));
      expect(tail, contains('boom'));
    });

    test('recordError omits log_tail when the ring buffer is empty', () async {
      final reporter = SentryCrashReporter(
        ringBuffer: LogRingBuffer(),
        tracing: _FakeTracing(),
      );

      await reporter.recordError(Exception('boom'), StackTrace.current);

      expect(captured!.contexts.containsKey('log_tail'), isFalse);
    });

    test('recordError does not tag fatal', () async {
      final reporter = SentryCrashReporter(
        ringBuffer: LogRingBuffer(),
        tracing: _FakeTracing(),
      );

      await reporter.recordError(Exception('boom'), StackTrace.current);

      expect(captured!.tags?['fatal'], isNull);
    });

    test('recordFlutterError always tags fatal', () async {
      final reporter = SentryCrashReporter(
        ringBuffer: LogRingBuffer(),
        tracing: _FakeTracing(),
      );

      await reporter.recordFlutterError(
        FlutterErrorDetails(exception: Exception('boom')),
      );

      expect(captured!.tags?['fatal'], 'true');
    });

    test('setUserId and log complete without throwing', () async {
      final reporter = SentryCrashReporter(
        ringBuffer: LogRingBuffer(),
        tracing: _FakeTracing(),
      );

      await expectLater(reporter.setUserId('user-123'), completes);
      await expectLater(reporter.log('hello'), completes);
    });
  });
}
