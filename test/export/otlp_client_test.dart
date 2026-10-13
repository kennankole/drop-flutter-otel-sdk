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

  // L5: a 401 used to drop the batch — every span recorded while signed
  // out, or across an expired token, was lost.
  group('BearerAuthHttpClient 401 handling', () {
    final traces = Uri.parse('https://example.test/v1/traces');

    Future<void> export(http.Client client, String body) =>
        client.post(traces, body: body);

    test('holds a rejected batch and replays it under a new token', () async {
      var token = 'stale';
      final sent = <(String?, String)>[];
      final client = BearerAuthHttpClient(
        () async => token,
        inner: MockClient((request) async {
          final auth = request.headers['Authorization'];
          sent.add((auth, request.body));
          return http.Response('', auth == 'Bearer stale' ? 401 : 200);
        }),
      );

      await export(client, 'batch-1');
      expect(client.heldBatchCount, 1);

      token = 'fresh';
      await export(client, 'batch-2');

      expect(sent, [
        ('Bearer stale', 'batch-1'),
        ('Bearer fresh', 'batch-1'),
        ('Bearer fresh', 'batch-2'),
      ]);
      expect(client.heldBatchCount, 0);
    });

    test(
      'keeps a batch rejected while signed out until a token exists',
      () async {
        String? token;
        final sent = <(String?, String)>[];
        final client = BearerAuthHttpClient(
          () async => token,
          inner: MockClient((request) async {
            final auth = request.headers['Authorization'];
            sent.add((auth, request.body));
            return http.Response('', auth == null ? 401 : 200);
          }),
        );

        await export(client, 'signed-out');
        await export(client, 'still-signed-out');
        expect(client.heldBatchCount, 2);

        token = 'signed-in';
        await export(client, 'now');

        expect(sent.skip(2), [
          ('Bearer signed-in', 'signed-out'),
          ('Bearer signed-in', 'still-signed-out'),
          ('Bearer signed-in', 'now'),
        ]);
        expect(client.heldBatchCount, 0);
      },
    );

    test('does not replay under the same token that was refused', () async {
      var calls = 0;
      final client = BearerAuthHttpClient(
        () async => 'same',
        inner: MockClient((request) async {
          calls++;
          return http.Response('', 401);
        }),
      );

      await export(client, 'a');
      await export(client, 'b');

      expect(calls, 2);
      expect(client.heldBatchCount, 2);
    });

    test('drops the oldest held batch beyond the cap', () async {
      final client = BearerAuthHttpClient(
        () async => 'same',
        maxHeldBatches: 2,
        inner: MockClient((request) async => http.Response('', 401)),
      );

      for (final body in ['a', 'b', 'c']) {
        await export(client, body);
      }

      expect(client.heldBatchCount, 2);
    });

    test('gives up on a batch after maxReplays refusals', () async {
      var n = 0;
      final bodies = <String>[];
      final client = BearerAuthHttpClient(
        () async => 'token-${n++}',
        maxReplays: 2,
        inner: MockClient((request) async {
          bodies.add(request.body);
          return http.Response('', 401);
        }),
      );

      // Every export brings a new token, so each one replays what is held.
      await export(client, 'first');
      for (var i = 0; i < 4; i++) {
        await export(client, 'later-$i');
      }

      // Sent once, replayed twice, then dropped.
      expect(bodies.where((b) => b == 'first'), hasLength(3));
    });

    test('never holds anything without a tokenProvider', () async {
      final client = BearerAuthHttpClient(
        null,
        inner: MockClient((request) async => http.Response('', 401)),
      );

      await export(client, 'a');

      expect(client.heldBatchCount, 0);
    });
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
