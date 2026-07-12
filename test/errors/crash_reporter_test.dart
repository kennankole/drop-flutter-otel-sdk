import 'package:drop_observability/drop_observability.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoopCrashReporter', () {
    const reporter = NoopCrashReporter();

    test('recordError never throws and never surfaces to the caller', () async {
      await expectLater(
        reporter.recordError(Exception('boom'), StackTrace.current),
        completes,
      );
    });

    test('recordFlutterError never throws', () async {
      final details = FlutterErrorDetails(exception: Exception('boom'));
      await expectLater(reporter.recordFlutterError(details), completes);
    });

    test('setUserId and log never throw', () async {
      await expectLater(reporter.setUserId('user-123'), completes);
      await expectLater(reporter.log('hello'), completes);
    });
  });
}
