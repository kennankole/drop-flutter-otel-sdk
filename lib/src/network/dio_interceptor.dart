import 'package:dio/dio.dart';

/// Dio interceptor facade — safe to add to `dio.interceptors` today
/// (design principle 2: apps never guard call sites). At L1 this is a
/// pure passthrough: real `traceparent` injection and a per-request
/// client span (OTEL_LIBRARY_PLAN.md L2) need the chosen SDK's ambient
/// Context propagation, which isn't wired in until L2 — injecting a
/// traceparent with no relationship to any real ambient span would be
/// actively misleading, so that logic is deferred rather than stubbed.
class DropDioInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.next(options);
  }
}
