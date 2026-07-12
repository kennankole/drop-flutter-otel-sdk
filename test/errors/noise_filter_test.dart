import 'package:dio/dio.dart';
import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

SentryEvent _eventFor(DioExceptionType type) {
  final requestOptions = RequestOptions(path: '/orders');
  return SentryEvent(
    throwable: DioException(requestOptions: requestOptions, type: type),
  );
}

void main() {
  group('dioNoiseFilter', () {
    // L3 acceptance criterion: "Filter unit-tested per dropped category".
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
      DioExceptionType.cancel,
    ]) {
      test('drops DioExceptionType.$type', () {
        expect(dioNoiseFilter(_eventFor(type)), isNull);
      });
    }

    for (final type in [
      DioExceptionType.badResponse,
      DioExceptionType.badCertificate,
      DioExceptionType.unknown,
    ]) {
      test('keeps DioExceptionType.$type', () {
        expect(dioNoiseFilter(_eventFor(type)), isNotNull);
      });
    }

    test('keeps non-Dio exceptions untouched', () {
      final event = SentryEvent(throwable: Exception('not dio'));
      expect(dioNoiseFilter(event), same(event));
    });
  });
}
