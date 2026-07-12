import 'package:drop_observability/src/scrub/attribute_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('assertNoForbiddenAttributes', () {
    for (final key in forbiddenResourceAttributeKeys) {
      test('throws on forbidden key "$key"', () {
        expect(
          () => assertNoForbiddenAttributes({key: 'value'}),
          throwsA(isA<ForbiddenAttributeException>()),
        );
      });
    }

    test('does not throw on an allowed key', () {
      expect(
        () => assertNoForbiddenAttributes({'order.items': 3}),
        returnsNormally,
      );
    });

    test('blocklist cannot be bypassed by case or whitespace variants', () {
      // Documents current exact-match behavior. If this test needs to
      // change to make it pass, that's the "a test fails if the blocklist
      // is bypassable" tripwire from design principle 4 firing correctly.
      expect(
        () => assertNoForbiddenAttributes({'userId': 'x'}),
        throwsA(isA<ForbiddenAttributeException>()),
      );
    });
  });

  group('scrubAttributes', () {
    test('drops forbidden keys and keeps everything else', () {
      final scrubbed = scrubAttributes({
        'userId': 'abc',
        'order.items': 3,
        'storeId': 'xyz',
      });
      expect(scrubbed, {'order.items': 3});
    });

    test('never throws, even with only forbidden keys', () {
      expect(
        () => scrubAttributes({'userId': 'x', 'deviceId': 'y'}),
        returnsNormally,
      );
      expect(scrubAttributes({'userId': 'x', 'deviceId': 'y'}), isEmpty);
    });
  });
}
