import 'package:drop_observability/src/export/otlp_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('BearerAuthHttpClient', () {
    test(
      'injects a Bearer header from tokenProvider on every request',
      () async {
        final captured = <http.BaseRequest>[];
        final client = BearerAuthHttpClient(
          () async => 'fresh-token',
          inner: MockClient((request) async {
            captured.add(request);
            return http.Response('', 200);
          }),
        );

        await client.get(Uri.parse('https://example.test/v1/traces'));
        await client.get(Uri.parse('https://example.test/v1/traces'));

        expect(captured, hasLength(2));
        for (final request in captured) {
          expect(request.headers['Authorization'], 'Bearer fresh-token');
        }
      },
    );

    // L5 acceptance criterion: "token refresh mid-flight doesn't wedge the
    // exporter" — each request calls tokenProvider fresh, never a cached
    // value, so a changed token is picked up on the very next request.
    test('fetches a fresh token per request rather than caching it', () async {
      var callCount = 0;
      final captured = <String?>[];
      final client = BearerAuthHttpClient(
        () async => 'token-${callCount++}',
        inner: MockClient((request) async {
          captured.add(request.headers['Authorization']);
          return http.Response('', 200);
        }),
      );

      await client.get(Uri.parse('https://example.test'));
      await client.get(Uri.parse('https://example.test'));
      await client.get(Uri.parse('https://example.test'));

      expect(captured, ['Bearer token-0', 'Bearer token-1', 'Bearer token-2']);
    });

    test(
      'sends unauthenticated (no header) when tokenProvider is null',
      () async {
        http.BaseRequest? captured;
        final client = BearerAuthHttpClient(
          null,
          inner: MockClient((request) async {
            captured = request;
            return http.Response('', 200);
          }),
        );

        await client.get(Uri.parse('https://example.test'));

        expect(captured!.headers.containsKey('Authorization'), isFalse);
      },
    );

    // L5 acceptance criterion: "token refresh mid-flight doesn't wedge the
    // exporter" — a throwing provider must not block or crash the request.
    test(
      'sends unauthenticated rather than throwing when tokenProvider throws',
      () async {
        http.BaseRequest? captured;
        final client = BearerAuthHttpClient(
          () async => throw Exception('token refresh failed'),
          inner: MockClient((request) async {
            captured = request;
            return http.Response('', 200);
          }),
        );

        await expectLater(
          client.get(Uri.parse('https://example.test')),
          completes,
        );
        expect(captured!.headers.containsKey('Authorization'), isFalse);
      },
    );

    test(
      'omits the header when tokenProvider resolves to an empty string',
      () async {
        http.BaseRequest? captured;
        final client = BearerAuthHttpClient(
          () async => '',
          inner: MockClient((request) async {
            captured = request;
            return http.Response('', 200);
          }),
        );

        await client.get(Uri.parse('https://example.test'));

        expect(captured!.headers.containsKey('Authorization'), isFalse);
      },
    );
  });

  group('buildOtlpSpanExporter', () {
    test('returns a real SpanExporter wired to the given endpoint', () {
      final exporter = buildOtlpSpanExporter(
        endpoint: Uri.parse('http://127.0.0.1:1/v1/traces'),
        tokenProvider: () async => 'token',
      );
      expect(exporter, isNotNull);
      // Construction alone must not touch the network.
      expect(exporter.shutdown, returnsNormally);
    });
  });
}
