# drop_observability

A shared Flutter instrumentation package for Drop's mobile apps — traces via
OpenTelemetry, error reporting via Sentry, and Dio HTTP instrumentation, behind a single
facade so no app code depends on the underlying SDKs directly.

Built for `drop-mobile`, `drop-rider`, and `drop-admin-mobile`, consumed as a pinned git
dependency. The repository is named `drop-flutter-otel-sdk`; the Dart package inside it
is `drop_observability`.

## Features

- **Tracing** — spans backed by the OpenTelemetry SDK, exported over OTLP/HTTP, with
  W3C `traceparent` propagation.
- **HTTP instrumentation** — a Dio interceptor that creates a span per request, injects
  trace context into outbound headers, and names spans from a templated route
  (`/orders/{id}`, never the raw URL) to keep cardinality low.
- **Error reporting** — a Sentry-backed crash reporter that automatically tags events
  with the active trace/span ID and attaches the recent log tail, plus a filter that
  drops network-noise exceptions (timeouts, cancellations) before they cost quota.
- **Structured logging** — leveled logging with an in-memory ring buffer (last ~200
  warning-and-above lines), attached to error events for context.
- **Off by default** — with no configuration, every call is a safe no-op: no network
  calls, no crash reporter initialized, nothing exported. Each capability turns on only
  when its config is supplied, so apps never need to guard call sites.
- **Bounded, non-blocking export** — a fixed-size queue that drops the oldest buffered
  span under sustained load rather than growing unbounded or blocking the app, flushed
  automatically when the app is backgrounded.

## Installation

Add as a git dependency, pinned to a released tag:

```yaml
dependencies:
  drop_observability:
    git:
      url: https://github.com/kennankole/drop-flutter-otel-sdk.git
      ref: v1.0.0
```

## Quick start

```dart
import 'package:dio/dio.dart';
import 'package:drop_observability/drop_observability.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  final obs = await DropObservability.init(
    ObservabilityConfig(
      serviceName: 'drop-mobile',
      environment: 'production',
      serviceVersion: packageInfo.version,
      otlpEndpoint: '${AppConfig.apiUrl}/otlp/v1/traces',
      sentryDsn: AppConfig.sentryDsn,
      gates: FirebaseObservabilityGates(remoteConfig),
      tokenProvider: () => secureStorage.readAccessToken(),
    ),
  );

  final dio = Dio()..interceptors.add(obs.dioInterceptor);

  runApp(MyApp(obs: obs, dio: dio));
}
```

Any field left out keeps that capability disabled — see [Configuration](#configuration).

## Usage

### Tracing

```dart
final span = obs.tracing.startSpan('checkout', attributes: {'order.items': 3});
try {
  await placeOrder();
  span.end(status: DropSpanStatus.ok);
} catch (e) {
  span.end(status: DropSpanStatus.error);
  rethrow;
}
```

Pass `parentContext: someSpan.context` to `startSpan` to nest a child span under a
parent — trace ID is inherited, a new span ID is assigned.

Certain attribute keys (`userId`, `storeId`, `deviceId`) are rejected at
`setAttribute()` time — they're high-cardinality identifiers that must never become a
resource attribute or metric label. Put them in the log/error body instead if they need
to be recorded.

### HTTP instrumentation

```dart
dio.interceptors.add(obs.dioInterceptor);
```

Every request gets a span named `METHOD /templated/route`, a `traceparent` header, and
is closed with the response status or marked as an error automatically.

### Error reporting

```dart
try {
  await riskyOperation();
} catch (error, stackTrace) {
  await obs.crashReporter.recordError(error, stackTrace);
}

obs.crashReporter.setUserId(currentUser.id);
```

Wire `FlutterError.onError` and `PlatformDispatcher.instance.onError` to
`obs.crashReporter.recordFlutterError`/`recordError` for global error capture. Events
are automatically tagged with the active span's trace/span ID (when there is one) and
carry the recent log tail as context, so a Sentry issue links straight to its trace in
Grafana and to what was logged right before it happened.

### Logging

```dart
obs.logger.w('poll degraded', fields: {'storeId': id});
obs.logger.e('checkout failed', fields: {'orderId': orderId});
```

Fields are folded into the log body, never treated as labels. Logs stay device-local
(no remote export yet — see [docs/DECISIONS.md](docs/DECISIONS.md)); the last ~200
warning-and-above lines are attached to error events automatically.

## Configuration

`ObservabilityConfig` is the only per-app configuration surface:

| Field | Required | Effect |
|---|---|---|
| `serviceName` | ✅ | Identifies the app in Grafana, e.g. `drop-mobile`, `drop-rider`. |
| `environment` | ✅ | e.g. `production`, `staging`. |
| `serviceVersion` | ✅ | App version string (the package never fetches this itself). |
| `otlpEndpoint` | — | OTLP ingest URL. Omitted or empty ⇒ tracing stays a no-op regardless of `gates`. |
| `sentryDsn` | — | Omitted or empty ⇒ error reporting stays fully disabled; Sentry is never initialized. |
| `gates` | — | App-supplied volume/kill-switch controls (see below). Defaults to everything off. |
| `tokenProvider` | — | Supplies a bearer token for the authenticated OTLP ingest route, called fresh on every export so token refresh is transparent. |

`gates` implements `ObservabilityGates` — the app owns how this is backed (typically
remote config), so the package has no dependency on any particular config provider:

```dart
abstract class ObservabilityGates {
  bool get otelEnabled;       // master kill switch
  double get traceSampleRate; // 0.0–1.0, only consulted when otelEnabled is true
  bool get logsEnabled;       // independent of traceSampleRate
}
```

When `gates` is omitted, it defaults to an implementation with everything off.

## Development

```bash
make lint           # flutter analyze + dart format check
make test            # flutter test
make facade-check    # verifies the OTEL SDK is only imported where it's meant to be
```

`example/` is a minimal runnable app exercising the full public API. To see spans
actually reach a collector:

```bash
cd example
docker compose up -d                                    # local otelcol on :4318
flutter run -d linux --dart-define=OTEL_ENABLED=true
```

### Releasing

```bash
make release VERSION=x.y.z          # add DRY_RUN=1 to preview without writing anything
```

Runs the full test/lint/facade-check gate, drafts a changelog entry from commit
history, bumps the package version, and tags the release that consuming apps pin to.

## Further reading

- [`docs/DECISIONS.md`](docs/DECISIONS.md) — why this OTEL SDK, why log export isn't
  implemented, and why the export queue is custom-built instead of using the SDK's own.
- `CHANGELOG.md` — released versions.
