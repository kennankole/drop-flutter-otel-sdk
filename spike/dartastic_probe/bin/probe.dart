// L0 spike probe: `dartastic_opentelemetry` package.
// Exercises: OTLP/HTTP export, BatchSpanProcessor batching, W3C propagation,
// forceFlush/shutdown lifecycle hooks.
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
// NOTE (spike finding): TextMapSetter/TextMapGetter are NOT re-exported from
// the main `dartastic_opentelemetry` barrel file, despite the published
// quickstart only importing that barrel. They live in the separate
// `dartastic_opentelemetry_api` package and must be imported directly.
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

// NOTE (spike finding): unlike Workiva's TextMapSetter/Getter (which receive
// the carrier as a `set(carrier, key, value)` parameter), this package's
// setter/getter bind the carrier at construction and ignore the `carrier`
// argument `inject`/`extract` otherwise pass around — an inconsistent design
// vs. the OTel spec's own TextMapPropagator shape (and vs. Workiva's impl).
class MapSetter implements TextMapSetter<String> {
  MapSetter(this.carrier);
  final Map<String, String> carrier;

  @override
  void set(String key, String value) {
    carrier[key] = value;
  }
}

class MapGetter implements TextMapGetter<String> {
  MapGetter(this.carrier);
  final Map<String, String> carrier;

  @override
  String? get(String key) => carrier[key];

  @override
  Iterable<String> keys() => carrier.keys;
}

Future<void> main() async {
  final endpoint =
      Platform.environment['OTLP_ENDPOINT'] ?? 'http://127.0.0.1:14318';
  print('[dartastic] exporting to $endpoint');

  final processor = BatchSpanProcessor(
    OtlpHttpSpanExporter(OtlpHttpExporterConfig(endpoint: endpoint)),
    const BatchSpanProcessorConfig(
      maxExportBatchSize: 5,
      scheduleDelay: Duration(seconds: 2),
    ),
  );

  await OTel.initialize(
    serviceName: 'spike-probe',
    serviceVersion: '0.0.1',
    spanProcessor: processor,
    enableMetrics: false,
    enableLogs: false,
  );

  final tracer = OTel.tracer();

  // --- 1. Basic span + attributes ---
  final span = tracer.startSpan(
    'spike.dartastic.basic',
    attributes: OTel.attributesFromMap({
      'probe.package': 'dartastic_opentelemetry',
      'probe.batch_size': 5,
    }),
  );
  span.end();
  print('[dartastic] basic span created + ended');

  // --- 2. W3C propagation round-trip ---
  final parentSpan = tracer.startSpan('spike.dartastic.propagation-parent');
  final propagator = W3CTraceContextPropagator();
  final carrier = <String, String>{};
  propagator.inject(
    OTel.context(spanContext: parentSpan.spanContext),
    carrier,
    MapSetter(carrier),
  );
  final traceparent = carrier['traceparent'];
  print('[dartastic] injected traceparent: $traceparent');
  if (traceparent == null ||
      !RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$')
          .hasMatch(traceparent)) {
    stderr.writeln('[dartastic] FAIL: traceparent header malformed or missing');
    exit(1);
  }

  final extractedContext = propagator.extract(
    OTel.context(),
    carrier,
    MapGetter(carrier),
  );
  final childSpan = tracer.startSpan(
    'spike.dartastic.propagation-child',
    context: extractedContext,
  );
  final sameTrace =
      parentSpan.spanContext.traceId.toString() == childSpan.spanContext.traceId.toString();
  print('[dartastic] child inherited parent trace id: $sameTrace');
  if (!sameTrace) {
    stderr.writeln('[dartastic] FAIL: propagation did not preserve trace id');
    exit(1);
  }
  childSpan.end();
  parentSpan.end();

  // --- 3. Batching: emit > batch size, confirm multiple exports over time ---
  final batchStart = DateTime.now();
  for (var i = 0; i < 12; i++) {
    tracer.startSpan('spike.dartastic.batch-$i').end();
  }
  print('[dartastic] emitted 12 spans (batch size 5, delay 2000ms) at '
      '${DateTime.now().difference(batchStart).inMilliseconds}ms');

  // --- 4. forceFlush / shutdown lifecycle hooks ---
  await processor.forceFlush();
  print('[dartastic] forceFlush() completed');
  await OTel.shutdown();
  print('[dartastic] shutdown() completed');

  print('[dartastic] PROBE OK');
}
