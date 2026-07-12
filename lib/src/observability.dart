import 'config.dart';
import 'errors/crash_reporter.dart';
import 'logging/logger.dart';
import 'network/dio_interceptor.dart';
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

  /// Builds a fully-wired instance. At L1 every backend is a no-op —
  /// `config.gates.otelEnabled` isn't consulted yet because there's
  /// nothing real to gate. L2 onward replace the no-op backends in place,
  /// at which point this method starts actually branching on the gates.
  static Future<DropObservability> init(ObservabilityConfig config) async {
    return DropObservability._(
      config: config,
      tracing: const NoopDropTracing(),
      logger: RingBufferLogger(),
      dioInterceptor: DropDioInterceptor(),
      crashReporter: const NoopCrashReporter(),
    );
  }
}
