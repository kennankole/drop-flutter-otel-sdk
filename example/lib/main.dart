import 'package:dio/dio.dart';
import 'package:drop_observability/drop_observability.dart';
import 'package:flutter/material.dart';

/// Off by default (design principle 2). To verify spans actually reach a
/// local collector (L2 acceptance criterion), run:
///   docker compose up -d          # from example/, starts otelcol on :4318
///   flutter run -d linux --dart-define=OTEL_ENABLED=true
class _ExampleGates implements ObservabilityGates {
  const _ExampleGates();

  @override
  bool get otelEnabled => const bool.fromEnvironment('OTEL_ENABLED');

  @override
  double get traceSampleRate => 1.0;

  @override
  bool get logsEnabled => false;
}

Future<void> main() async {
  final obs = await DropObservability.init(
    const ObservabilityConfig(
      serviceName: 'drop_observability_example',
      environment: 'development',
      serviceVersion: '0.0.1',
      otlpEndpoint: 'http://localhost:4318/v1/traces',
      gates: _ExampleGates(),
      // sentryDsn omitted: crash reporting stays no-op until L3.
    ),
  );

  final dio = Dio()..interceptors.add(obs.dioInterceptor);

  runApp(ExampleApp(obs: obs, dio: dio));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.obs, required this.dio});

  final DropObservability obs;
  final Dio dio;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'drop_observability example',
      home: ExampleHomePage(obs: obs, dio: dio),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key, required this.obs, required this.dio});

  final DropObservability obs;
  final Dio dio;

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  String _status = 'Ready';

  Future<void> _runTracedRequest() async {
    // Tracing: create a span, do the work, end it — exactly the
    // OTEL_LIBRARY_PLAN.md §3 usage pattern. At L1 this span is created
    // and discarded locally; nothing is exported yet.
    final span = widget.obs.tracing.startSpan(
      'example.fetch',
      attributes: {'example.trigger': 'button_press'},
    );

    try {
      await widget.dio.get<void>('https://example.com');
      widget.obs.logger.i('fetch completed');
      span.end(status: DropSpanStatus.ok);
      setState(() => _status = 'Fetch OK (trace: ${span.context.traceId})');
    } catch (error, stackTrace) {
      widget.obs.logger.e('fetch failed', fields: {'error': '$error'});
      await widget.obs.crashReporter.recordError(error, stackTrace);
      span.end(status: DropSpanStatus.error);
      setState(() => _status = 'Fetch failed (see crashReporter)');
    } finally {
      // L5 wires this into a pause hook; forced here so manual collector
      // verification doesn't have to wait out the batch timer.
      widget.obs.tracing.forceFlush();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('drop_observability example')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _runTracedRequest,
              child: const Text('Run traced Dio call'),
            ),
          ],
        ),
      ),
    );
  }
}
