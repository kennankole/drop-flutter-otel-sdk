# Engineering Decisions

Background and rationale for the non-obvious choices in this package. See the main
[README](../README.md) for what the package does and how to use it.

## OTEL SDK selection: `opentelemetry` (Workiva), not `dartastic_opentelemetry`

There is no official OpenTelemetry SDK for Dart. Two community packages were evaluated
empirically — against a real local OTEL collector, not just their documentation —
before choosing one to build the tracing facade on.

| Criterion | `opentelemetry` (Workiva) 0.18.11 | `dartastic_opentelemetry` 0.9.5 |
|---|---|---|
| **Compiles out of the box** (`pub get` + build, no overrides) | ✅ Yes | ❌ **No.** Its declared constraint `dartastic_opentelemetry_api: ^1.0.0-beta.2` resolves by default to `1.0.0-beta.9`, which doesn't implement `APITracer.timeProvider`/`APITracerProvider.timeProvider` — a compile error. Fixed only by manually pinning `dependency_overrides: dartastic_opentelemetry_api: 1.0.0-beta.2`. This is what any new consumer gets today running `flutter pub add dartastic_opentelemetry`. |
| **OTLP/HTTP export** (spans reach a real `otelcol-contrib`) | ✅ 15/15 spans delivered | ✅ 10/15 delivered (see reliability row) |
| **Batching** (`BatchSpanProcessor`, custom size/delay respected) | ✅ Correct | ✅ Correct (when it doesn't silently drop the tail — see below) |
| **W3C propagation** (inject → carrier → extract, trace ID preserved) | ✅ Verified round-trip | ✅ Verified round-trip, but: `TextMapSetter`/`TextMapGetter` are **not re-exported** from the main `dartastic_opentelemetry` barrel despite the published quickstart only importing that barrel — must import `dartastic_opentelemetry_api` directly. Their `set(key, value)`/`get(key)` shape (carrier bound at construction) also diverges from Workiva's spec-shaped `set(carrier, key, value)`. |
| **Reliability under `forceFlush()`/`shutdown()`** | ✅ All 15 spans arrived. Two transient `ClientException` warnings were logged but recovered — no data loss. | ❌ **Silently dropped 5 of 15 spans** (the tail batch) even though `forceFlush()` and `shutdown()` both returned normally with no error. This is the single most disqualifying result — the export policy depends on flush-on-pause being reliable. |
| **Error visibility** | Failures surface via `package:logging`, but **silent unless a listener is attached** (no default sink) — the facade attaches one. | Failures in the dropped-batch case produced **no log output at all** — worse, since there's nothing to attach a listener to. |
| **Binary size delta** (release APK, baseline 42,561,322 bytes) | **+17,688 bytes** (~17 KB) | **+2,658,410 bytes** (~2.6 MB) — **~150x larger**, because it transitively pulls in `google_cloud`, `googleapis_auth`, and `google_identity_services_web`. |
| **Dependency tree / vendor coupling** | Pure OTLP client: `http`, `protobuf`, `grpc`-free. No cloud-vendor deps. | Pulls Google Cloud auth/identity packages transitively, and `OTel.initialize()` accepts `dartasticApiKey`/`tenantId` params — the package is oriented around the author's commercial Dartastic.io SaaS backend, not a neutral OTLP client. |
| **Maintainer / bus factor** | Workiva (established company, verified pub.dev publisher). GitHub: 87 stars, 26 open issues, actively updated. | Solo-maintained by Michael Bushe (Mindful Software). Still mid-donation to CNCF, donation proposal open but not accepted. |
| **API surface stability** | Pre-1.0, breaking changes possible, but the package works and its docs/examples are accurate. | Pre-1.0 with a separate pre-1.0-beta API package — two independently-versioned pre-1.0 packages that can (and did) drift into an incompatible combination. |

**Why this is decisive, not close:** the reliability and compile-integrity findings are
load-bearing — a telemetry library that silently drops the flush-on-pause batch defeats
the purpose of the export policy ("bounded queue... token refresh mid-flight doesn't
wedge the exporter"), and a package that doesn't compile against its own declared
dependency range by default isn't something to build a facade on top of today, however
active its CNCF donation process. The binary-size and dependency-tree findings
independently rule it out even if the reliability issue were fixed.

**Escape hatch:** the OTEL SDK is imported only inside `lib/src/tracing/tracer.dart`
(plus `lib/src/export/export_policy.dart` and `lib/src/export/otlp_client.dart`, which
implement SDK-required interfaces for the same facade — see "Export policy" below). If
`opentelemetry` (Workiva) stalls or regresses, or `dartastic_opentelemetry` resolves its
issues, swapping SDKs is a change confined to those files plus a package version bump —
no changes required in consuming apps.

Reproduction scripts: `spike/opentelemetry_probe/`, `spike/dartastic_probe/`.

## Log export: not implemented

Real OTEL log export was investigated and deliberately not built. `RingBufferLogger` —
the in-memory warning+ tail attached to Sentry error events — remains the only logging
backend.

`opentelemetry` (Workiva) — the SDK selected above — has no log-export implementation at
all: its SDK has `trace/`, `metrics/`, `resource/` but no `logs/`; the logs API is an
abstract interface plus a no-op stub, and neither is re-exported from the package's
public barrels.

A follow-up spike confirmed `dartastic_opentelemetry` — disqualified above — has a
genuinely reliable **logs** pipeline: two clean runs delivered 15/15 and 16/16 records
(vs. its trace pipeline's 33% silent loss), using an entirely different exporter than
the one that failed. Cross-SDK trace/span correlation was verified too: a span context
built purely from externally-supplied hex strings (as this package's Workiva-based
tracer would supply) produced a log record in the collector carrying those exact IDs.

The blocker isn't reliability — it's that using `dartastic_opentelemetry` at all, even
logs-only, reintroduces everything it was disqualified for above: the ~2.6 MB transitive
Google Cloud dependency bloat, solo-maintainer risk, and the compile-break requiring a
`dependency_overrides` pin, on top of running two OTEL SDKs side by side. Weighed against
logs being the lowest-priority, off-by-default telemetry signal for this project, that
cost isn't worth it right now.

**Escape hatch:** if OTEL logs become a priority later, two options are live: adopt
`dartastic_opentelemetry` logs-only (proven to work, cost is the dependency weight), or
hand-roll a minimal OTLP/HTTP JSON exporter (OTLP/HTTP supports JSON alongside protobuf,
avoiding both the GCP bloat and a second SDK's maintenance risk, at the cost of owning
more code). Neither is blocked technically — this was a scope/cost call.

Reproduction script: `spike/dartastic_logs_probe/`.

## Export policy: a custom queue and authenticated client

`RealDropTracing` does not use the SDK's own `BatchSpanProcessor`/`CollectorExporter`
directly. Reading `BatchSpanProcessor`'s source
(`lib/src/sdk/trace/span_processors/batch_processor.dart` inside the `opentelemetry`
package) turned up two undocumented behaviors that conflict with this project's
telemetry policy of a bounded, drop-oldest queue:

- Its queue size is a hardcoded `2048`, not configurable via the constructor.
- On overflow it drops the **newest** span (rejects the incoming one), not the oldest.

`lib/src/export/export_policy.dart`'s `DropSpanProcessor` is this package's own
`SpanProcessor` implementing the correct drop-oldest, configurable-size policy (default
queue size 500, 60-second flush interval). A byte-size-based flush trigger was
considered and not implemented, since the SDK has no concept of payload byte size, only
span count.

`lib/src/export/otlp_client.dart`'s `BearerAuthHttpClient` wraps the SDK's
`CollectorExporter` with a custom `http.Client` that re-fetches the auth token on every
single request rather than caching it at construction, so a token refresh mid-flight is
picked up on the very next export. A 401 response isn't in the SDK's own retry list
(`429/502/503/504`), so it's already logged and dropped rather than retried in a loop.

The facade's OTEL-SDK-import boundary therefore covers three files —
`lib/src/tracing/tracer.dart`, `lib/src/export/export_policy.dart`,
`lib/src/export/otlp_client.dart` (enforced by `scripts/check_facade_imports.sh`) — not
just one. All three implement SDK-required interfaces for the same facade; the
guarantee that actually matters — no OTEL SDK type appears in this package's public
API — is unchanged and still enforced by the curated exports in
`lib/drop_observability.dart`.

## Versioning starts at 1.0.0

This package's first release is `v1.0.0`, not `0.x`. The facade — not the underlying
OTEL SDK — is the public contract consuming apps depend on, and it was exercised
through the package's full initial build (configuration, tracing, error reporting,
export policy) without a single breaking change to `DropObservability`,
`ObservabilityConfig`, `CrashReporter`, or `DropSpan`. This package's whole premise is
that an OTEL SDK swap should be a patch/minor bump to consuming apps, not a breaking
one — that only means what it says under strict semver once past 1.0.0. A future
facade-breaking change is a `v2.0.0`, the same as any other library.

## Reproducing the spikes

```
cd spike/otelcol && docker compose up -d      # local otelcol-contrib on :14318/:14317
cd spike/opentelemetry_probe && dart pub get && dart run bin/probe.dart
cd spike/dartastic_probe && dart pub get && dart run bin/probe.dart
docker compose -f spike/otelcol/docker-compose.yml logs otelcol

# logs re-spike (dartastic_opentelemetry only, not adopted — see above)
cd spike/dartastic_logs_probe && dart pub get && OTLP_ENDPOINT=http://127.0.0.1:24318 timeout 30 dart run bin/probe.dart
```
