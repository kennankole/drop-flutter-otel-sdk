import 'package:dio/dio.dart';

import '../tracing/span.dart';
import '../tracing/tracer.dart';

/// Dio interceptor facade — safe to add to `dio.interceptors` unconditionally
/// (design principle 2: apps never guard call sites). Backed by whatever
/// [DropTracing] [DropObservability] wired up: [NoopDropTracing] at L1/when
/// disabled (this class still runs, just produces spans nothing exports),
/// or [RealDropTracing] once L2 is enabled.
///
/// Every outbound request gets a client span named `METHOD route-template`
/// and a `traceparent` header carrying that span's (SDK-authoritative, see
/// tracer.dart) trace/span IDs — so distributed tracing keeps working even
/// when nothing is actually exported.
class DropDioInterceptor extends Interceptor {
  DropDioInterceptor(this._tracing);

  final DropTracing _tracing;

  static const _spanExtraKey = 'drop_observability.span';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final routeTemplate = templatePath(options.path);
    final span = _tracing.startSpan(
      '${options.method} $routeTemplate',
      attributes: {'http.method': options.method, 'http.route': routeTemplate},
    );

    options.extra[_spanExtraKey] = span;
    options.headers['traceparent'] = span.context.toTraceparent(sampled: true);

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final span = response.requestOptions.extra[_spanExtraKey] as DropSpan?;
    if (span != null && !span.isEnded) {
      if (response.statusCode != null) {
        span.setAttribute('http.status_code', response.statusCode);
      }
      span.end(status: DropSpanStatus.ok);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final span = err.requestOptions.extra[_spanExtraKey] as DropSpan?;
    if (span != null && !span.isEnded) {
      final statusCode = err.response?.statusCode;
      if (statusCode != null) {
        span.setAttribute('http.status_code', statusCode);
      }
      span.end(status: DropSpanStatus.error);
    }
    handler.next(err);
  }
}

final _idSegmentPattern = RegExp(
  r'^(\d+|'
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|'
  r'[0-9a-fA-F]{24}'
  r')$',
);

/// Strips per-request identifiers from a URL path so span names/attributes
/// stay low-cardinality (OTEL_LIBRARY_PLAN.md L2: "route templates — not
/// full URL with IDs"). Recognizes purely-numeric segments, UUIDs, and
/// 24-hex-char IDs (Mongo-style ObjectIds); everything else is left as-is
/// rather than guessed at.
///
/// `/orders/12345/items/6f1c...` → `/orders/{id}/items/{id}`
String templatePath(String path) {
  final segments = path.split('/');
  return segments
      .map((segment) => _idSegmentPattern.hasMatch(segment) ? '{id}' : segment)
      .join('/');
}
