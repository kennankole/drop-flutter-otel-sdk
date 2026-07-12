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
}
