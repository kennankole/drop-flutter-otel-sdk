import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoopObservabilityGates', () {
    test('everything is off', () {
      const gates = NoopObservabilityGates();
      expect(gates.otelEnabled, isFalse);
      expect(gates.traceSampleRate, 0.0);
      expect(gates.logsEnabled, isFalse);
    });
  });

  group('ObservabilityConfig', () {
    test('defaults to NoopObservabilityGates when gates is omitted', () {
      const config = ObservabilityConfig(
        serviceName: 'drop-mobile',
        environment: 'production',
        serviceVersion: '1.0.0',
      );
      expect(config.gates, isA<NoopObservabilityGates>());
      expect(config.gates.otelEnabled, isFalse);
    });

    test('optional fields default to null', () {
      const config = ObservabilityConfig(
        serviceName: 'drop-mobile',
        environment: 'production',
        serviceVersion: '1.0.0',
      );
      expect(config.otlpEndpoint, isNull);
      expect(config.sentryDsn, isNull);
      expect(config.tokenProvider, isNull);
    });
  });
}
