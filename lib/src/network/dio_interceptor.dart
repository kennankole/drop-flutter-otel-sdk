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
///
/// The header's `sampled` flag is the span's own decision. While client
/// tracing is on that is the sampler's verdict, so the backend — which
/// follows the client's flag — records the same share of mobile traces the
/// app does, instead of every one. While tracing is off the flag stays
/// `01`, as before 1.1: the client has made no decision, and an app with no
/// gates wired (rate 0) must not switch off backend tracing for its
/// requests.
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
    options.headers[traceparentHeader] = span.context.toTraceparent();

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

const traceparentHeader = 'traceparent';

/// The trace ID of the request behind [options] / [response].
///
/// Prefers the `traceparent` the backend echoes on the response —
/// authoritative even if the server started its own trace — and falls back
/// to the one [DropDioInterceptor] sent, which still names the trace when no
/// response arrived at all. Null when neither is a well-formed header.
String? traceIdOfRequest(
  RequestOptions options, [
  Response<dynamic>? response,
]) {
  final echoed = DropSpanContext.fromTraceparent(
    response?.headers.value(traceparentHeader),
  );
  final sentHeader = options.headers[traceparentHeader];
  final sent = DropSpanContext.fromTraceparent(
    sentHeader is String ? sentHeader : null,
  );
  return (echoed ?? sent)?.traceId;
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
