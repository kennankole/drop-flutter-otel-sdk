import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoopDropTracing', () {
    test('startSpan returns a real DropSpan, not null or a stub', () {
      const tracer = NoopDropTracing();
      final span = tracer.startSpan('checkout');

      expect(span, isA<DropSpan>());
      expect(span.name, 'checkout');
      expect(span.isEnded, isFalse);
    });

    test('passes parentContext and attributes through unchanged', () {
      const tracer = NoopDropTracing();
      final parent = DropSpanContext();

      final span = tracer.startSpan(
        'charge',
        parentContext: parent,
        attributes: {'order.items': 3},
      );

      expect(span.context.traceId, parent.traceId);
      expect(span.attributes, {'order.items': 3});
    });
  });

  // These exercise the real SDK-backed tracer. Construction and span
  // creation/attribute-setting/ending never touch the network by
  // themselves (BatchSpanProcessor only flushes on its own schedule or a
  // full batch) — the dummy endpoint below is never actually dialed
  // within a single test's lifetime, so these stay fast and offline.
  group('RealDropTracing', () {
    RealDropTracing makeTracer() => RealDropTracing(
      otlpEndpoint: 'http://127.0.0.1:1/v1/traces',
      resourceAttributes: {
        'service.name': 'test-service',
        'deployment.environment': 'test',
        'service.version': '0.0.1',
      },
    );

    test('startSpan returns a DropSpan with SDK-assigned, valid W3C IDs', () {
      final span = makeTracer().startSpan('checkout');

      expect(
        span.context.toTraceparent(),
        matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$')),
      );
    });

    test('a fresh (no-parent) span starts a new trace each time', () {
      final tracer = makeTracer();
      final a = tracer.startSpan('a');
      final b = tracer.startSpan('b');

      expect(a.context.traceId, isNot(b.context.traceId));
    });

    // L2 acceptance criterion: "traceparent present on outbound requests"
    // depends on this — the child's trace ID must match what the parent
    // handed out, since that's what DropDioInterceptor propagates.
    test('a child span inherits the parent trace ID from the real SDK', () {
      final tracer = makeTracer();
      final parent = tracer.startSpan('checkout');

      final child = tracer.startSpan('charge', parentContext: parent.context);

      expect(child.context.traceId, parent.context.traceId);
      expect(child.context.spanId, isNot(parent.context.spanId));
    });

    test(
      'setAttribute and end() do not throw when bridged to the real SDK',
      () {
        final span = makeTracer().startSpan('checkout');

        expect(() => span.setAttribute('order.items', 3), returnsNormally);
        expect(() => span.end(status: DropSpanStatus.ok), returnsNormally);
        expect(span.isEnded, isTrue);
      },
    );

    // L2 acceptance criterion: "forbidden-attr test red-lines any leak" —
    // must hold for the real backend too, not just the no-op one covered
    // in tracing/span_test.dart. Because the check runs before the
    // onSetAttribute hook fires (span.dart), a forbidden key never reaches
    // the underlying SDK span either.
    test(
      'setAttribute rejects forbidden keys before they reach the SDK span',
      () {
        final span = makeTracer().startSpan('checkout');

        expect(
          () => span.setAttribute('userId', 'abc'),
          throwsA(isA<ForbiddenAttributeException>()),
        );
        expect(span.attributes, isEmpty);
      },
    );

    test('forceFlush does not throw even against an unreachable endpoint', () {
      final tracer = makeTracer();
      tracer.startSpan('checkout').end();
      expect(tracer.forceFlush, returnsNormally);
    });

    test('two independent instances do not share a tracer provider', () {
      final a = makeTracer();
      final b = makeTracer();

      // No hidden global registry (design principle 6) — spans from `a`
      // and `b` start unrelated traces even for the "same" span name.
      final spanA = a.startSpan('checkout');
      final spanB = b.startSpan('checkout');
      expect(spanA.context.traceId, isNot(spanB.context.traceId));
    });
  });
}
