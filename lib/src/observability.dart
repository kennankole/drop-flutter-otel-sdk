import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'config.dart';
import 'errors/crash_reporter.dart';
import 'errors/noise_filter.dart';
import 'errors/sentry_crash_reporter.dart';
import 'export/flush_on_pause_observer.dart';
import 'logging/logger.dart';
import 'logging/ring_buffer.dart';
import 'network/dio_interceptor.dart';
import 'tracing/resource.dart';
import 'tracing/tracer.dart';

/// Entry point — the only per-app wiring call (design principle 6:
/// DI-friendly, static-free; this is an instance, not a static singleton
/// like today's `AppTracing`).
class DropObservability {
  DropObservability._({
    required this.config,
    required this.tracing,
    required this.logger,
    required this.dioInterceptor,
    required this.crashReporter,
  });

  final ObservabilityConfig config;
  final DropTracing tracing;
  final DropLogger logger;
  final DropDioInterceptor dioInterceptor;
  final CrashReporter crashReporter;

  /// Builds a fully-wired instance.
  ///
  /// Tracing goes real (L2) only when `gates.otelEnabled` is true *and* an
  /// `otlpEndpoint` is configured — otherwise it stays [NoopDropTracing].
  /// Crash reporting goes real (L3) only when `sentryDsn` is non-empty —
  /// otherwise it stays [NoopCrashReporter] and `SentryFlutter.init()` is
  /// never even called. Both match design principle 2. A
  /// [FlushOnPauseObserver] is always registered (harmless no-op when
  /// tracing is a [NoopDropTracing]) so telemetry survives the app being
  /// backgrounded (L5). Logging stays local-only — L4 (real OTEL log
  /// export) was investigated and descoped; see README.md.
  static Future<DropObservability> init(ObservabilityConfig config) async {
    WidgetsFlutterBinding.ensureInitialized();

    final tracing = _buildTracing(config);
    final ringBuffer = LogRingBuffer();

    WidgetsBinding.instance.addObserver(FlushOnPauseObserver(tracing));

    return DropObservability._(
      config: config,
      tracing: tracing,
      logger: RingBufferLogger(ringBuffer: ringBuffer),
      dioInterceptor: DropDioInterceptor(tracing),
      crashReporter: await _buildCrashReporter(config, tracing, ringBuffer),
    );
  }

  static DropTracing _buildTracing(ObservabilityConfig config) {
    final endpoint = config.otlpEndpoint;
    if (!config.gates.otelEnabled || endpoint == null || endpoint.isEmpty) {
      return const NoopDropTracing();
    }
    return RealDropTracing(
      otlpEndpoint: endpoint,
      resourceAttributes: buildResourceAttributes(
        serviceName: config.serviceName,
        environment: config.environment,
        serviceVersion: config.serviceVersion,
      ),
      tokenProvider: config.tokenProvider,
    );
  }

  static Future<CrashReporter> _buildCrashReporter(
    ObservabilityConfig config,
    DropTracing tracing,
    LogRingBuffer ringBuffer,
  ) async {
    final dsn = config.sentryDsn;
    if (dsn == null || dsn.isEmpty) {
      return const NoopCrashReporter();
    }

    await SentryFlutter.init((options) {
      options.dsn = dsn;
      options.environment = config.environment;
      options.release = config.serviceVersion;
      // Sentry's own performance tracing stays off — OTEL/Tempo owns
      // tracing (OBSERVABILITY_STRATEGY.md Phase 1.3).
      options.tracesSampleRate = 0;
      // ignore: experimental_member_use
      options.profilesSampleRate = 0;
      // Never PII by default (Phase 1.5) — apps opt a user in explicitly
      // via crashReporter.setUserId().
      options.sendDefaultPii = false;
      options.beforeSend = dioNoiseFilter;
    });

    return SentryCrashReporter(ringBuffer: ringBuffer, tracing: tracing);
  }
}
