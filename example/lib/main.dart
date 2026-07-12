import 'package:dio/dio.dart';
import 'package:drop_observability/drop_observability.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  final obs = await DropObservability.init(
    const ObservabilityConfig(
      serviceName: 'drop_observability_example',
      environment: 'development',
      serviceVersion: '0.0.1',
      // otlpEndpoint / sentryDsn / gates all omitted: everything no-ops
      // (design principle 2) until L2+ wire in real backends.
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
