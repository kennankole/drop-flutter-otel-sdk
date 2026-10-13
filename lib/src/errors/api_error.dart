import 'package:dio/dio.dart';

import '../network/dio_interceptor.dart';

/// A failed API request as [CrashReporter.recordApiError] reports it.
///
/// Built from a [DioException] so the reported event carries the request's
/// own trace ID — the failing request's span has ended by the time anything
/// reports, so the reporter's usual "active span" lookup finds nothing.
/// Holds the templated route, not the path, so one broken endpoint is one
/// issue rather than one per ID. Never holds a body: error payloads echo
/// user data.
class ApiRequestFailure implements Exception {
  ApiRequestFailure.fromDio(DioException error)
    : method = error.requestOptions.method,
      route = templatePath(error.requestOptions.path.split('?').first),
      statusCode = error.response?.statusCode,
      type = error.type,
      traceId = traceIdOfRequest(error.requestOptions, error.response);

  final String method;
  final String route;
  final int? statusCode;
  final DioExceptionType type;
  final String? traceId;

  /// Groups events by endpoint and outcome rather than by stack trace, which
  /// for a Dio failure is the same interceptor chain every time.
  List<String> get fingerprint => [
    'api-request-failure',
    method,
    route,
    '${statusCode ?? type.name}',
  ];

  @override
  String toString() =>
      'ApiRequestFailure: $method $route -> ${statusCode ?? type.name}';
}
