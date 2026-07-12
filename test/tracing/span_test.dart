import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DropSpanContext', () {
    test('generates a valid W3C traceparent', () {
      final context = DropSpanContext();
      final header = context.toTraceparent();
      expect(
        header,
        matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$')),
      );
    });

    test('sampled flag is reflected in the traceparent flags byte', () {
      final context = DropSpanContext();
      expect(context.toTraceparent(sampled: false), endsWith('-00'));
      expect(context.toTraceparent(sampled: true), endsWith('-01'));
    });

    test('fromTraceparent round-trips trace and span IDs', () {
      final original = DropSpanContext();
      final header = original.toTraceparent();

      final parsed = DropSpanContext.fromTraceparent(header);

      expect(parsed, isNotNull);
      expect(parsed!.traceId, original.traceId);
      expect(parsed.spanId, original.spanId);
    });

    test('fromTraceparent returns null for malformed input', () {
      expect(DropSpanContext.fromTraceparent(null), isNull);
      expect(DropSpanContext.fromTraceparent(''), isNull);
      expect(DropSpanContext.fromTraceparent('not-a-traceparent'), isNull);
      expect(DropSpanContext.fromTraceparent('01-deadbeef-cafe-01'), isNull);
    });

    test('two contexts never collide (128-bit trace ID space)', () {
      final ids = List.generate(1000, (_) => DropSpanContext().traceId);
      expect(ids.toSet().length, 1000);
    });
  });

  group('DropSpan', () {
    test('a fresh span starts its own trace', () {
      final span = DropSpan('checkout');
      expect(span.context.traceId, isNotEmpty);
      expect(span.status, DropSpanStatus.unset);
      expect(span.isEnded, isFalse);
    });

    test(
      'a child span inherits the parent trace ID but gets a new span ID',
      () {
        final parent = DropSpan('checkout');
        final child = DropSpan('charge', parentContext: parent.context);

        expect(child.context.traceId, parent.context.traceId);
        expect(child.context.spanId, isNot(parent.context.spanId));
      },
    );

    test('end() sets status and isEnded, and is idempotent', () {
      final span = DropSpan('checkout');
      span.end(status: DropSpanStatus.error);

      expect(span.status, DropSpanStatus.error);
      expect(span.isEnded, isTrue);

      // Calling end() again must not change the already-recorded status.
      span.end();
      expect(span.status, DropSpanStatus.error);
    });

    test('setAttribute records allowed attributes', () {
      final span = DropSpan('checkout');
      span.setAttribute('order.items', 3);
      expect(span.attributes, {'order.items': 3});
    });

    test('setAttribute rejects forbidden keys (design principle 4)', () {
      final span = DropSpan('checkout');
      expect(
        () => span.setAttribute('userId', 'abc'),
        throwsA(isA<ForbiddenAttributeException>()),
      );
      expect(span.attributes, isEmpty);
    });

    test('attributes passed to the constructor are also scrubbed', () {
      expect(
        () => DropSpan('checkout', attributes: {'storeId': 'xyz'}),
        throwsA(isA<ForbiddenAttributeException>()),
      );
    });

    test('setAttribute is a no-op after end()', () {
      final span = DropSpan('checkout')..end();
      span.setAttribute('order.items', 3);
      expect(span.attributes, isEmpty);
    });
  });
}
