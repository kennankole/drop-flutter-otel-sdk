import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DropObservability.init', () {
    test('succeeds with only the required config fields', () async {
      final obs = await DropObservability.init(
        const ObservabilityConfig(
          serviceName: 'drop-mobile',
          environment: 'production',
          serviceVersion: '1.0.0',
        ),
      );

      expect(obs.tracing, isA<DropTracing>());
      expect(obs.logger, isA<DropLogger>());
      expect(obs.dioInterceptor, isA<DropDioInterceptor>());
      expect(obs.crashReporter, isA<CrashReporter>());
    });

    // L1 acceptance criterion (OTEL_LIBRARY_PLAN.md): "init() with
    // otelEnabled=false ⇒ zero network calls". At L1 there is no export
    // mechanism wired in at all yet (that lands in L2-L5), so this holds
    // trivially by construction — nothing in the object graph below does
    // I/O. This test exists to be the regression guard once L2+ add a real,
    // injectable HTTP/exporter client: it should keep passing unchanged
    // when gates.otelEnabled is false, and that's the point at which it
    // stops being trivial.
    test(
      'otelEnabled=false: every call site is safe to use without guards',
      () async {
        final obs = await DropObservability.init(
          const ObservabilityConfig(
            serviceName: 'drop-mobile',
            environment: 'production',
            serviceVersion: '1.0.0',
            // gates defaults to NoopObservabilityGates: otelEnabled=false.
          ),
        );

        expect(obs.config.gates.otelEnabled, isFalse);

        // None of these should throw, block, or require network access.
        final span = obs.tracing.startSpan('checkout');
        span.setAttribute('order.items', 3);
        span.end(status: DropSpanStatus.ok);

        obs.logger.w('poll degraded', fields: {'storeId': 'abc123'});

        await obs.crashReporter.recordError(
          Exception('boom'),
          StackTrace.current,
        );
        await obs.crashReporter.setUserId('user-123');
      },
    );

    test(
      'each init() call produces an independent instance (no hidden statics)',
      () async {
        final a = await DropObservability.init(
          const ObservabilityConfig(
            serviceName: 'drop-mobile',
            environment: 'production',
            serviceVersion: '1.0.0',
          ),
        );
        final b = await DropObservability.init(
          const ObservabilityConfig(
            serviceName: 'drop-rider',
            environment: 'production',
            serviceVersion: '2.0.0',
          ),
        );

        expect(a.config.serviceName, 'drop-mobile');
        expect(b.config.serviceName, 'drop-rider');
        expect(identical(a.logger, b.logger), isFalse);
      },
    );

    // L3 acceptance criterion: "DSN-empty ⇒ fully disabled". Sentry must
    // never even be initialized, not just silently skip sending — checked
    // via Sentry.isEnabled rather than just the crashReporter's type.
    test(
      'sentryDsn omitted: crashReporter is Noop and Sentry stays uninitialized',
      () async {
        final obs = await DropObservability.init(
          const ObservabilityConfig(
            serviceName: 'drop-mobile',
            environment: 'production',
            serviceVersion: '1.0.0',
          ),
        );

        expect(obs.crashReporter, isA<NoopCrashReporter>());
        expect(Sentry.isEnabled, isFalse);
      },
    );

    test(
      'sentryDsn set: crashReporter is the real Sentry-backed one',
      () async {
        addTearDown(Sentry.close);

        final obs = await DropObservability.init(
          const ObservabilityConfig(
            serviceName: 'drop-mobile',
            environment: 'production',
            serviceVersion: '1.0.0',
            sentryDsn: 'https://public@o1.ingest.sentry.io/1',
          ),
        );

        expect(obs.crashReporter, isA<SentryCrashReporter>());
        expect(Sentry.isEnabled, isTrue);
      },
    );
  });
}
