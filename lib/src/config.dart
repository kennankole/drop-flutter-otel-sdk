/// Fleet-wide volume/kill-switch controls, implemented by the app (e.g.
/// backed by remote config) so the package never depends on a specific
/// config provider — design principle 3, no Firebase dependency.
abstract class ObservabilityGates {
  /// Master kill switch.
  bool get otelEnabled;

  /// 0.0–1.0. Only consulted when [otelEnabled] is true.
  double get traceSampleRate;

  /// Independent of [traceSampleRate] — logs stay off by default even when
  /// traces are on, per OBSERVABILITY_STRATEGY.md's rollout order.
  bool get logsEnabled;
}

/// Default gates: everything off. Used when [ObservabilityConfig.gates] is
/// omitted, so `DropObservability.init()` is safe to call with minimal
/// configuration and never makes a network call (design principle 2).
class NoopObservabilityGates implements ObservabilityGates {
  const NoopObservabilityGates();

  @override
  bool get otelEnabled => false;

  @override
  double get traceSampleRate => 0.0;

  @override
  bool get logsEnabled => false;
}

/// The package's sole per-app configuration surface. No OTEL SDK type
/// appears here (design principle 1).
class ObservabilityConfig {
  const ObservabilityConfig({
    required this.serviceName,
    required this.environment,
    required this.serviceVersion,
    this.otlpEndpoint,
    this.sentryDsn,
    this.gates = const NoopObservabilityGates(),
    this.tokenProvider,
  });

  /// The only per-app identity knob, e.g. `drop-mobile`, `drop-rider`.
  final String serviceName;

  /// e.g. `production`, `staging`.
  final String environment;

  /// The app passes this in (from `package_info_plus`); the package never
  /// fetches it itself.
  final String serviceVersion;

  /// OTLP ingest endpoint (the authenticated proxy route). Null/empty and
  /// export stays disabled regardless of [gates]. Unused until L5.
  final String? otlpEndpoint;

  /// Empty or null ⇒ Sentry disabled. Unused until L3.
  final String? sentryDsn;

  /// Volume/kill-switch controls. Defaults to [NoopObservabilityGates]
  /// (everything off) so `init()` is safe with no gates wired up.
  final ObservabilityGates gates;

  /// Supplies the Bearer token for the OTLP proxy. Called lazily per
  /// export batch, not cached, so token refresh is transparent to callers.
  /// Unused until L5.
  final Future<String?> Function()? tokenProvider;
}
