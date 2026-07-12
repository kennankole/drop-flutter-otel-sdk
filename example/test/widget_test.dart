import 'package:dio/dio.dart';
import 'package:drop_observability/drop_observability.dart';
import 'package:drop_observability_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'example app runs: init() + wiring the interceptor into Dio, no crash',
    (tester) async {
      final obs = await DropObservability.init(
        const ObservabilityConfig(
          serviceName: 'drop_observability_example',
          environment: 'test',
          serviceVersion: '0.0.1',
        ),
      );
      final dio = Dio()..interceptors.add(obs.dioInterceptor);

      await tester.pumpWidget(ExampleApp(obs: obs, dio: dio));

      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Run traced Dio call'), findsOneWidget);
    },
  );
}
