import 'package:opentelemetry/api.dart' as api;
import 'package:opentelemetry/sdk.dart' as sdk;

import 'span.dart';

/// Package-owned tracing facade — no OTEL SDK type appears in this
/// interface (design principle 1).
abstract class DropTracing {
  DropSpan startSpan(
    String name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  });

  /// Forces any buffered spans out immediately. A no-op on [NoopDropTracing].
  /// L5 wires this into a `WidgetsBindingObserver` pause hook; exposed now
  /// because manual/CI-optional collector verification (see
  /// example/docker-compose.yml) needs it too.
  void forceFlush();

  /// The innermost still-open span started through this instance, or null.
  /// A best-effort approximation of "the current operation" — not proper
  /// ambient Context propagation (the chosen SDK requires explicitly
  /// running code inside a `runInContext` zone for that, which nothing in
  /// this package does yet) — used by L3's `SentryCrashReporter` to tag
  /// `otel.trace_id`/`otel.span_id` on error events. Always null on
  /// [NoopDropTracing]: an ID that was never exported has nothing to
  /// correlate to in Grafana.
  DropSpanContext? get activeContext;
}

/// This file is the OTEL SDK import boundary (design principle 1: "the
/// ONLY file importing SDK trace types"). L0's spike
/// (README.md) chose `opentelemetry` (Workiva) over `dartastic_opentelemetry`.
///
/// At L1 no SDK was wired in — every span was created locally and
/// discarded. L2 replaces that no-op with a real backend here, without
/// changing [DropTracing]'s shape or anything outside this file.
class NoopDropTracing implements DropTracing {
  const NoopDropTracing();

  @override
  DropSpan startSpan(
    String name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  }) {
    return DropSpan(name, parentContext: parentContext, attributes: attributes);
  }

  @override
  void forceFlush() {}

  @override
  DropSpanContext? get activeContext => null;
}

/// Real SDK-backed tracer. Deliberately never touches the SDK's *global*
/// registry (`registerGlobalTracerProvider` et al.) — every instance owns
/// its own [sdk.TracerProviderBase], so multiple [DropObservability]
/// instances (design principle 6: DI-friendly, static-free) stay fully
/// independent instead of silently overwriting each other's global state.
///
/// Sampling is `ParentBasedSampler(AlwaysOnSampler())` — the SDK's own
/// default — for every span at L2. The SDK ships no ratio-based sampler,
/// so honoring `gates.traceSampleRate` needs a custom [sdk.Sampler]
/// implementation; that's deferred to L5 (export/volume policy), where it
/// belongs alongside the rest of the remote-config volume controls.
///
/// Auth (`tokenProvider` → Bearer header) is deferred to L5's
/// `otlp_client.dart`; L2's exporter talks to the OTLP endpoint
/// unauthenticated, matching the phase boundary in OTEL_LIBRARY_PLAN.md.
class RealDropTracing implements DropTracing {
  RealDropTracing({
    required String otlpEndpoint,
    required Map<String, String> resourceAttributes,
  }) : _provider = sdk.TracerProviderBase(
         resource: sdk.Resource([
           for (final entry in resourceAttributes.entries)
             api.Attribute.fromString(entry.key, entry.value),
         ]),
         processors: [
           sdk.BatchSpanProcessor(
             sdk.CollectorExporter(Uri.parse(otlpEndpoint)),
           ),
         ],
       );

  final sdk.TracerProviderBase _provider;

  // LIFO stack of currently-open spans started through this instance, for
  // [activeContext]. Instance-scoped (design principle 6) — never shared
  // across [RealDropTracing] instances.
  final _openSpans = <DropSpan>[];

  @override
  DropSpanContext? get activeContext =>
      _openSpans.isEmpty ? null : _openSpans.last.context;

  @override
  DropSpan startSpan(
    String name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  }) {
    final tracer = _provider.getTracer('drop_observability');

    final sdkSpan = tracer.startSpan(
      name,
      context: parentContext == null
          ? api.Context.current
          : api.contextWithSpanContext(
              api.Context.current,
              api.SpanContext.remote(
                api.TraceId.fromString(parentContext.traceId),
                api.SpanId.fromString(parentContext.spanId),
                api.TraceFlags.sampled,
                api.TraceState.empty(),
              ),
            ),
    );

    // The SDK assigns the authoritative trace/span IDs — DropSpan must
    // carry those, not locally-generated ones, so the `traceparent` we
    // hand to Dio matches what's actually exported.
    final dropSpan = DropSpan.withContext(
      name,
      DropSpanContext(
        traceId: sdkSpan.spanContext.traceId.toString(),
        spanId: sdkSpan.spanContext.spanId.toString(),
      ),
      attributes: attributes,
    );

    dropSpan.onSetAttribute = (key, value) {
      sdkSpan.setAttribute(_toApiAttribute(key, value));
    };
    dropSpan.onEnd = (status) {
      sdkSpan
        ..setStatus(api.StatusCode.values.byName(status.name))
        ..end();
      _openSpans.remove(dropSpan);
    };

    _openSpans.add(dropSpan);
    return dropSpan;
  }

  @override
  void forceFlush() => _provider.forceFlush();
}

api.Attribute _toApiAttribute(String key, Object? value) {
  if (value is String) return api.Attribute.fromString(key, value);
  if (value is int) return api.Attribute.fromInt(key, value);
  if (value is double) return api.Attribute.fromDouble(key, value);
  if (value is bool) return api.Attribute.fromBoolean(key, value);
  return api.Attribute.fromString(key, '$value');
}
