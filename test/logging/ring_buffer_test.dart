import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogRingBuffer', () {
    test('keeps lines in insertion order', () {
      final buffer = LogRingBuffer(capacity: 10);
      buffer.add('one');
      buffer.add('two');
      expect(buffer.lines, ['one', 'two']);
    });

    test('drops the oldest line once capacity is exceeded', () {
      final buffer = LogRingBuffer(capacity: 3);
      buffer
        ..add('1')
        ..add('2')
        ..add('3')
        ..add('4');

      expect(buffer.lines, ['2', '3', '4']);
      expect(buffer.lines.length, 3);
    });

    test('clear() empties the buffer', () {
      final buffer = LogRingBuffer()..add('one');
      buffer.clear();
      expect(buffer.lines, isEmpty);
    });

    test('lines is unmodifiable', () {
      final buffer = LogRingBuffer()..add('one');
      expect(() => buffer.lines.add('two'), throwsUnsupportedError);
    });

    test('defaults to a 200-line capacity per OBSERVABILITY_STRATEGY.md', () {
      final buffer = LogRingBuffer();
      for (var i = 0; i < 250; i++) {
        buffer.add('line $i');
      }
      expect(buffer.lines.length, 200);
      expect(buffer.lines.first, 'line 50');
    });
  });
}
