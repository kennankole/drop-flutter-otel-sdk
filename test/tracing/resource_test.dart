import 'package:drop_observability/src/tracing/resource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildResourceAttributes', () {
    test('includes the required identity attributes', () {
      final attrs = buildResourceAttributes(
        serviceName: 'drop-mobile',
        environment: 'production',
        serviceVersion: '1.0.0',
      );

      expect(attrs, {
        'service.name': 'drop-mobile',
        'deployment.environment': 'production',
        'service.version': '1.0.0',
      });
    });

    test('includes os.name only when provided', () {
      final attrs = buildResourceAttributes(
        serviceName: 'drop-mobile',
        environment: 'production',
        serviceVersion: '1.0.0',
        osName: 'android',
      );

      expect(attrs['os.name'], 'android');
    });

    test('omits os.name when not provided', () {
      final attrs = buildResourceAttributes(
        serviceName: 'drop-mobile',
        environment: 'production',
        serviceVersion: '1.0.0',
      );

      expect(attrs.containsKey('os.name'), isFalse);
    });

    // The forbidden-key check here (assertNoForbiddenAttributes) is
    // currently unreachable through this function's fixed signature — its
    // keys are hardcoded literals ('service.name' etc.), never caller
    // input. It's a regression guard (design principle 4) for if/when this
    // signature grows to accept extra resource attributes; the enforcement
    // logic itself is exercised directly in scrub/attribute_rules_test.dart.
  });
}
