// L4 spike probe: dartastic_opentelemetry logs export.
// L0 disqualified this package for TRACES (compile break, 33% silent span
// loss, ~2.6MB GCP dependency bloat). The chosen `opentelemetry` (Workiva)
// package has no log-export implementation at all, so this probe
// specifically re-tests whether dartastic's LOG pipeline is more reliable
// than its trace pipeline was — a different processor/exporter, so not
// necessarily the same bug.
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

Future<void> main() async {
  final endpoint =
      Platform.environment['OTLP_ENDPOINT'] ?? 'http://127.0.0.1:24318';
  print('[dartastic-logs] exporting to $endpoint/v1/logs');

  final processor = BatchLogRecordProcessor(
    OtlpHttpLogRecordExporter(
      OtlpHttpLogRecordExporterConfig(endpoint: '$endpoint/v1/logs'),
    ),
    const BatchLogRecordProcessorConfig(
      maxExportBatchSize: 5,
      scheduleDelay: Duration(seconds: 2),
    ),
  );

  await OTel.initialize(
    serviceName: 'spike-logs-probe',
    serviceVersion: '0.0.1',
    logRecordProcessor: processor,
    enableMetrics: false,
  );

  final logger = OTel.logger('spike-logs-probe');

  // Emit 15 records the same way the L0 trace probe emitted 15 spans, so
  // the reliability comparison is apples-to-apples.
  for (var i = 0; i < 15; i++) {
    logger.emit(
      severityNumber: Severity.WARN,
      body: 'spike.dartastic.log-$i',
      attributes: OTel.attributesFromMap({'log.index': i}),
    );
  }
  print('[dartastic-logs] emitted 15 log records (batch size 5, delay 2000ms)');

  // Cross-SDK correlation test: in the real package, spans come from the
  // *Workiva* tracer (L2), not dartastic's. Simulate that by building a
  // SpanContext purely from externally-supplied hex trace/span IDs (no
  // dartastic span involved), matching exactly what tracer.dart would hand
  // this bridge: DropSpanContext.traceId/.spanId as plain hex strings.
  const fakeTraceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fakeSpanId = 'bbbbbbbbbbbbbbbb';
  final externalSpanContext = OTel.spanContext(
    traceId: OTel.traceIdFrom(fakeTraceId),
    spanId: OTel.spanIdFrom(fakeSpanId),
  );
  logger.emit(
    severityNumber: Severity.ERROR,
    body: 'spike.dartastic.correlated-log',
    context: OTel.context(spanContext: externalSpanContext),
  );
  print('[dartastic-logs] emitted 1 log record correlated to trace=$fakeTraceId span=$fakeSpanId');

  await processor.forceFlush();
  print('[dartastic-logs] forceFlush() completed');
  await OTel.shutdown();
  print('[dartastic-logs] shutdown() completed');

  print('[dartastic-logs] PROBE OK');
}
