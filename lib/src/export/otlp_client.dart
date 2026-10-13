import 'package:http/http.dart' as http;
import 'package:opentelemetry/sdk.dart' as sdk;

/// Wraps the SDK's [sdk.CollectorExporter] with a Bearer token sourced
/// fresh from [tokenProvider] on *every* HTTP request — not cached at
/// construction — so a token refresh mid-flight never leaves the exporter
/// holding a stale credential (OTEL_LIBRARY_PLAN.md L5 acceptance
/// criterion). A 401 isn't in the SDK's own retry list (`429/502/503/504`,
/// per `collector_exporter.dart`), so the SDK logs it and drops the batch —
/// which lost every span recorded while signed out or across an expired
/// token. [BearerAuthHttpClient] keeps those batches and replays them once a
/// different token turns up.
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
///
/// A batch the proxy rejects with 401 is held (at most [maxHeldBatches],
/// oldest dropped first) together with the token it was sent with. The next
/// export that has a *different*, non-empty token — the app refreshed, or
/// the user signed in — replays the held batches first. Each batch gets
/// [maxReplays] replays, so a token the proxy keeps refusing cannot pin
/// spans in memory forever.
class BearerAuthHttpClient extends http.BaseClient {
  BearerAuthHttpClient(
    this._tokenProvider, {
    http.Client? inner,
    this.maxHeldBatches = 10,
    this.maxReplays = 3,
  }) : inner = inner ?? http.Client();

  final Future<String?> Function()? _tokenProvider;
  final http.Client inner;
  final int maxHeldBatches;
  final int maxReplays;

  final _held = <_HeldBatch>[];

  /// Batches waiting for a usable token. Exposed for tests.
  int get heldBatchCount => _held.length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _currentToken();
    if (token != null && _held.isNotEmpty) await _replayHeld(token);
    return _sendWith(request, token, replays: 0);
  }

  Future<String?> _currentToken() async {
    try {
      final token = await _tokenProvider?.call();
      return token == null || token.isEmpty ? null : token;
    } catch (_) {
      // Best-effort (design principle 5): a broken token provider must
      // never block telemetry. Send unauthenticated; a 401 holds the batch.
      return null;
    }
  }

  Future<http.StreamedResponse> _sendWith(
    http.BaseRequest request,
    String? token, {
    required int replays,
  }) async {
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    final response = await inner.send(request);
    if (response.statusCode == 401 &&
        request is http.Request &&
        _tokenProvider != null &&
        replays < maxReplays) {
      _hold(_HeldBatch.of(request, token, replays));
    }
    return response;
  }

  void _hold(_HeldBatch batch) {
    if (_held.length >= maxHeldBatches) _held.removeAt(0);
    _held.add(batch);
  }

  /// Replays every held batch that failed under a token other than
  /// [token]. One that fails again is re-held by [_sendWith] with its
  /// replay count raised; one that fails for any other reason is dropped,
  /// as the SDK itself would have.
  Future<void> _replayHeld(String token) async {
    final ready = _held.where((batch) => batch.token != token).toList();
    _held.removeWhere(ready.contains);
    for (final batch in ready) {
      try {
        final response = await _sendWith(
          batch.toRequest(),
          token,
          replays: batch.replays + 1,
        );
        await response.stream.drain<void>();
      } catch (_) {
        // Best-effort: a replay must never fail the export that triggered it.
      }
    }
  }
}

/// A rejected export, kept as bytes so it can be rebuilt and resent.
class _HeldBatch {
  _HeldBatch.of(http.Request request, this.token, this.replays)
    : method = request.method,
      url = request.url,
      headers = Map.of(request.headers)..remove('Authorization'),
      body = request.bodyBytes;

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> body;
  final String? token;
  final int replays;

  http.Request toRequest() => http.Request(method, url)
    ..headers.addAll(headers)
    ..bodyBytes = body;
}
