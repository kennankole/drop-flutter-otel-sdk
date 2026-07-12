# drop-flutter-otel-sdk

The Shared Flutter OTEL Library — implements `drop_observability`, the shared instrumentation
package designed in `drop-mobile/OTEL_LIBRARY_PLAN.md` (itself derived from
`drop-mobile/OBSERVABILITY_STRATEGY.md` Appendix F). Consumed by `drop-mobile`, `drop-rider`,
and `drop-admin-mobile` as a pinned git dependency.

This repo is named `drop-flutter-otel-sdk`; the Dart package inside it is `drop_observability`
(same repo/package-name split as the `authentication-sdk` precedent).

## Status

L0 (SDK spike), L1 (scaffold + no-op core), and L2 (tracing + Dio) complete.
L3 (errors) not yet started.

## L0 — SDK Spike Decision

**Decision: `opentelemetry` (Workiva, pub.dev) — not `dartastic_opentelemetry`.**

Both packages were evaluated empirically (not just from docs) against a local OTEL collector,
per the spike criteria in `OTEL_LIBRARY_PLAN.md`. Reproduction scripts are in `spike/`.

| Criterion | `opentelemetry` (Workiva) 0.18.11 | `dartastic_opentelemetry` 0.9.5 |
|---|---|---|
| **Compiles out of the box** (`pub get` + build, no overrides) | ✅ Yes | ❌ **No.** Its declared constraint `dartastic_opentelemetry_api: ^1.0.0-beta.2` resolves by default to `1.0.0-beta.9`, which doesn't implement `APITracer.timeProvider`/`APITracerProvider.timeProvider` — a compile error. Fixed only by manually pinning `dependency_overrides: dartastic_opentelemetry_api: 1.0.0-beta.2`. This is what any new consumer gets today running `flutter pub add dartastic_opentelemetry`. |
| **OTLP/HTTP export** (spans reach a real `otelcol-contrib`) | ✅ 15/15 spans delivered | ✅ 10/15 delivered (see reliability row) |
| **Batching** (`BatchSpanProcessor`, custom size/delay respected) | ✅ Correct | ✅ Correct (when it doesn't silently drop the tail — see below) |
| **W3C propagation** (inject → carrier → extract, trace ID preserved) | ✅ Verified round-trip | ✅ Verified round-trip, but: `TextMapSetter`/`TextMapGetter` are **not re-exported** from the main `dartastic_opentelemetry` barrel despite the published quickstart only importing that barrel — must import `dartastic_opentelemetry_api` directly. Their `set(key, value)`/`get(key)` shape (carrier bound at construction) also diverges from Workiva's spec-shaped `set(carrier, key, value)`. |
| **Reliability under `forceFlush()`/`shutdown()`** | ✅ All 15 spans arrived. Two transient `ClientException` warnings were logged (see below) but recovered — no data loss. | ❌ **Silently dropped 5 of 15 spans** (the tail batch) even though `forceFlush()` and `shutdown()` both returned normally with no error. This is the single most disqualifying result: `OTEL_LIBRARY_PLAN.md`'s L5 export-policy phase explicitly depends on flush-on-pause being reliable. |
| **Error visibility** | Failures surface via `package:logging`, but **silent unless a listener is attached** (no default sink) — the facade must attach one. | Failures in the dropped-batch case produced **no log output at all** — worse, since there's nothing to attach a listener to. |
| **Binary size delta** (release APK, baseline 42,561,322 bytes) | **+17,688 bytes** (~17 KB) | **+2,658,410 bytes** (~2.6 MB) — **~150x larger**, because it transitively pulls in `google_cloud`, `googleapis_auth`, and `google_identity_services_web`. |
| **Dependency tree / vendor coupling** | Pure OTLP client: `http`, `protobuf`, `grpc`-free. No cloud-vendor deps. | Pulls Google Cloud auth/identity packages transitively, and `OTel.initialize()` accepts `dartasticApiKey`/`tenantId` params — the package is oriented around the author's commercial Dartastic.io SaaS backend, not a neutral OTLP client. Directly conflicts with `OTEL_LIBRARY_PLAN.md` design principle 3 ("keeps the package's dependency tree minimal"). |
| **Maintainer / bus factor** | Workiva (established company, verified pub.dev publisher). GitHub: 87 stars, 26 open issues, actively updated (last push June 2026). | Solo-maintained by Michael Bushe (Mindful Software). Still mid-donation to CNCF as of July 2026 (donation proposal open, not accepted) — same "in-progress" status as when `OBSERVABILITY_STRATEGY.md` was written. |
| **API surface stability** | `opentelemetry (pub.dev 0.9.x)` as named in the original plan is stale — actual latest is **0.18.11**. Still pre-1.0, breaking changes possible, but the package works and its docs/examples are accurate. | Pre-1.0 (`0.9.5`) with a separate pre-1.0-beta API package (`1.0.0-beta.9`) — two independently-versioned pre-1.0 packages that can (and did) drift into an incompatible combination. |

### Why this is decisive, not close

The reliability and compile-integrity findings are the load-bearing ones: a telemetry library
that silently drops the flush-on-pause batch defeats the entire purpose of `OTEL_LIBRARY_PLAN.md`
§5 L5 ("bounded queue... token refresh mid-flight doesn't wedge the exporter"), and a package
that doesn't compile against its own declared dependency range by default is not something to
build a facade on top of today, however active its CNCF donation process. The binary-size and
dependency-tree findings independently violate design principle 3 (no unnecessary vendor
coupling) hard enough to disqualify it even if the reliability issue were fixed.

### Escape hatch

Per the facade rule (`OTEL_LIBRARY_PLAN.md` design principle 1), the OTEL SDK is imported only
inside `lib/src/tracing/tracer.dart`. If `opentelemetry` (Workiva) stalls or regresses, or if
`dartastic_opentelemetry` resolves its compile/reliability issues and completes CNCF donation,
swapping SDKs is a change to that one file plus a package minor/patch bump — no consuming app
code changes, per design principle 1's whole justification.

### Known issues to carry into L1/L2

- Attach a `package:logging` `Logger.root.onRecord` listener inside the facade and route it
  through `AppLogger`/Sentry breadcrumbs — otherwise `CollectorExporter` failures are invisible
  by default (confirmed above).
- The transient `ClientException: Connection closed before full header was received` warnings
  seen under concurrent unawaited exports (multiple batches firing near-simultaneously) — the
  package's retry logic only covers specific HTTP status codes (429/502/503/504), not
  network-level exceptions, which are logged and dropped without retry. Worth a real-device/
  real-network retest in L2, since this was observed against a local Docker collector and may
  be an artifact of this environment's Docker proxy rather than the package itself; either way,
  L5's export policy (bounded queue, drop-oldest) should treat any export failure as expected
  and non-fatal by design, so this is a lower-severity note than the dartastic findings.

## Reproducing the spike

```
cd spike/otelcol && docker compose up -d      # local otelcol-contrib on :14318/:14317
cd spike/opentelemetry_probe && dart pub get && dart run bin/probe.dart
cd spike/dartastic_probe && dart pub get && dart run bin/probe.dart
docker compose -f spike/otelcol/docker-compose.yml logs otelcol
```

## Layout

See `drop-mobile/OTEL_LIBRARY_PLAN.md` §4 for the target package layout (not yet scaffolded —
that's L1).
