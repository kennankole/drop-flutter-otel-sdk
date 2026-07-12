import 'package:http/http.dart' as http;
import 'package:opentelemetry/sdk.dart' as sdk;

/// Wraps the SDK's [sdk.CollectorExporter] with a Bearer token sourced
/// fresh from [tokenProvider] on *every* HTTP request — not cached at
/// construction — so a token refresh mid-flight never leaves the exporter
/// holding a stale credential (OTEL_LIBRARY_PLAN.md L5 acceptance
/// criterion). A 401 from an expired/invalid token isn't in the SDK's own
/// retry list (`429/502/503/504` — confirmed by reading
/// `collector_exporter.dart`), so it's already logged and dropped rather
/// than retried in a loop; nothing extra is needed here for that part.
sdk.SpanExporter buildOtlpSpanExporter({
  required Uri endpoint,
  Future<String?> Function()? tokenProvider,
}) {
  return sdk.CollectorExporter(
    endpoint,
    httpClient: BearerAuthHttpClient(tokenProvider),
  );
}

/// Not exported from the public barrel — internal to how
/// [buildOtlpSpanExporter] authenticates, but non-private so tests can
/// inject a fake [inner] client and inspect outgoing requests directly.
class BearerAuthHttpClient extends http.BaseClient {
  BearerAuthHttpClient(this._tokenProvider, {http.Client? inner})
    : inner = inner ?? http.Client();

  final Future<String?> Function()? _tokenProvider;
  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    String? token;
    try {
      token = await _tokenProvider?.call();
    } catch (_) {
      // Best-effort (design principle 5): a broken token provider must
      // never block telemetry. Send unauthenticated; the proxy's own 401
      // handling (see class doc) takes it from there.
      token = null;
    }
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return inner.send(request);
  }
}
