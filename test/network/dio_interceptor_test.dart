import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake transport so the interceptor can be exercised through a
/// real Dio request/response cycle without a network call.
class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('DropDioInterceptor', () {
    test('is a real Dio Interceptor and can be wired into interceptors', () {
      final dio = Dio();
      final interceptor = DropDioInterceptor();

      expect(interceptor, isA<Interceptor>());
      expect(() => dio.interceptors.add(interceptor), returnsNormally);
    });

    test('L1: passes the request through unchanged end-to-end', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _FakeAdapter()
        ..interceptors.add(DropDioInterceptor());

      final response = await dio.get<Map<String, dynamic>>('/orders');

      expect(response.statusCode, 200);
      // No traceparent injection yet (L1 is a pure passthrough) — real
      // injection needs the chosen SDK's ambient Context, wired in L2.
      expect(
        response.requestOptions.headers.containsKey('traceparent'),
        isFalse,
      );
    });
  });
}
