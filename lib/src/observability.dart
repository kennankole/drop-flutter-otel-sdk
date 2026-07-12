import 'config.dart';
import 'errors/crash_reporter.dart';
import 'logging/logger.dart';
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

  /// Builds a fully-wired instance. Tracing goes real (L2) only when
  /// `gates.otelEnabled` is true *and* an `otlpEndpoint` is configured —
  /// otherwise it stays [NoopDropTracing], matching design principle 2.
  /// Logging, crash reporting, and export policy stay no-op until
  /// L3/L4/L5 wire in their own gates the same way.
  static Future<DropObservability> init(ObservabilityConfig config) async {
    final tracing = _buildTracing(config);
    return DropObservability._(
      config: config,
      tracing: tracing,
      logger: RingBufferLogger(),
      dioInterceptor: DropDioInterceptor(tracing),
      crashReporter: const NoopCrashReporter(),
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
    );
  }
}
