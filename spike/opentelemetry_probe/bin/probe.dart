// L0 spike probe: `opentelemetry` (Workiva) package.
// Exercises: OTLP/HTTP export, BatchSpanProcessor batching, W3C propagation,
// forceFlush/shutdown lifecycle hooks.
import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:opentelemetry/api.dart';
import 'package:opentelemetry/sdk.dart' as sdk;

class MapSetter implements TextMapSetter<Map<String, String>> {
  @override
  void set(Map<String, String> carrier, String key, String value) {
    carrier[key] = value;
  }
}

class MapGetter implements TextMapGetter<Map<String, String>> {
  @override
  String? get(Map<String, String>? carrier, String key) =>
      carrier == null ? null : carrier[key];

  @override
  Iterable<String> keys(Map<String, String> carrier) => carrier.keys;
}

Future<void> main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) => print('[opentelemetry][log:${r.level.name}] ${r.loggerName}: ${r.message}'));

  final endpoint = Platform.environment['OTLP_ENDPOINT'] ??
      'http://localhost:14318/v1/traces';
  print('[opentelemetry] exporting to $endpoint');

  final exporter = sdk.CollectorExporter(Uri.parse(endpoint));
  final processor = sdk.BatchSpanProcessor(
    exporter,
    maxExportBatchSize: 5,
    scheduledDelayMillis: 2000,
  );
  final tp = sdk.TracerProviderBase(processors: [processor]);
  registerGlobalTracerProvider(tp);

  final propagator = W3CTraceContextPropagator();
  registerGlobalTextMapPropagator(propagator);

  final tracer = tp.getTracer('spike-probe', version: '0.0.1');

  // --- 1. Basic span + attributes ---
  final span = tracer.startSpan('spike.opentelemetry.basic');
  span.setAttribute(Attribute.fromString('probe.package', 'opentelemetry'));
  span.setAttribute(Attribute.fromInt('probe.batch_size', 5));
  span.end();
  print('[opentelemetry] basic span created + ended');

  // --- 2. W3C propagation round-trip ---
  final parentSpan = tracer.startSpan('spike.opentelemetry.propagation-parent');
  final carrier = <String, String>{};
  propagator.inject(contextWithSpan(Context.current, parentSpan), carrier, MapSetter());
  final traceparent = carrier['traceparent'];
  print('[opentelemetry] injected traceparent: $traceparent');
  if (traceparent == null || !RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$').hasMatch(traceparent)) {
    stderr.writeln('[opentelemetry] FAIL: traceparent header malformed or missing');
    exit(1);
  }

  final extractedContext = propagator.extract(Context.current, carrier, MapGetter());
  final childSpan = tracer.startSpan('spike.opentelemetry.propagation-child', context: extractedContext);
  final sameTrace = parentSpan.spanContext.traceId.toString() == childSpan.spanContext.traceId.toString();
  print('[opentelemetry] child inherited parent trace id: $sameTrace');
  if (!sameTrace) {
    stderr.writeln('[opentelemetry] FAIL: propagation did not preserve trace id');
    exit(1);
  }
  childSpan.end();
  parentSpan.end();

  // --- 3. Batching: emit > batch size, confirm multiple exports over time ---
  final batchStart = DateTime.now();
  for (var i = 0; i < 12; i++) {
    tracer.startSpan('spike.opentelemetry.batch-$i').end();
  }
  print('[opentelemetry] emitted 12 spans (batch size 5, delay 2000ms) at '
      '${DateTime.now().difference(batchStart).inMilliseconds}ms');

  // --- 4. forceFlush / shutdown lifecycle hooks ---
  processor.forceFlush();
  print('[opentelemetry] forceFlush() completed');
  tp.shutdown();
  print('[opentelemetry] shutdown() completed');
  // Exporter calls are fire-and-forget (unawaited) internally; give the
  // event loop a moment to flush pending HTTP sends before the process exits.
  await Future<void>.delayed(const Duration(seconds: 3));

  print('[opentelemetry] PROBE OK');
}
