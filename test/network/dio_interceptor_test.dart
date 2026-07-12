import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake transport so the interceptor can be exercised through a
/// real Dio request/response cycle without a network call.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.statusCode = 200, this.throwError = false});

  final int statusCode;
  final bool throwError;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throwError) {
      throw DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: statusCode),
      );
    }
    return ResponseBody.fromString(
      '{}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('templatePath', () {
    test('replaces purely-numeric segments with {id}', () {
      expect(templatePath('/orders/12345'), '/orders/{id}');
      expect(
        templatePath('/orders/12345/items/6789'),
        '/orders/{id}/items/{id}',
      );
    });

    test('replaces UUID segments with {id}', () {
      expect(
        templatePath('/users/f47ac10b-58cc-4372-a567-0e02b2c3d479'),
        '/users/{id}',
      );
    });

    test('replaces 24-hex-char (ObjectId-style) segments with {id}', () {
      expect(templatePath('/carts/507f1f77bcf86cd799439011'), '/carts/{id}');
    });

    test('leaves non-ID segments untouched', () {
      expect(templatePath('/orders/active'), '/orders/active');
      expect(templatePath('/'), '/');
    });
  });

  group('DropDioInterceptor', () {
    test('is a real Dio Interceptor and can be wired into interceptors', () {
      final dio = Dio();
      final interceptor = DropDioInterceptor(const NoopDropTracing());

      expect(interceptor, isA<Interceptor>());
      expect(() => dio.interceptors.add(interceptor), returnsNormally);
    });

    test('injects a well-formed traceparent header on every request', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _FakeAdapter()
        ..interceptors.add(DropDioInterceptor(const NoopDropTracing()));

      final response = await dio.get<Map<String, dynamic>>('/orders/12345');

      expect(response.statusCode, 200);
      final traceparent =
          response.requestOptions.headers['traceparent'] as String?;
      expect(traceparent, isNotNull);
      expect(
        traceparent,
        matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$')),
      );
    });

    test('span name/route use the templated path, not the raw URL', () async {
      DropSpan? capturedSpan;

      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _FakeAdapter()
        ..interceptors.add(
          DropDioInterceptor(_CapturingTracing((span) => capturedSpan = span)),
        );

      await dio.get<void>('/orders/12345');

      expect(capturedSpan, isNotNull);
      expect(capturedSpan!.name, 'GET /orders/{id}');
      expect(capturedSpan!.attributes['http.route'], '/orders/{id}');
      expect(capturedSpan!.attributes['http.method'], 'GET');
    });

    test('ends the span with status ok on a successful response', () async {
      DropSpan? capturedSpan;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _FakeAdapter(statusCode: 200)
        ..interceptors.add(
          DropDioInterceptor(_CapturingTracing((span) => capturedSpan = span)),
        );

      await dio.get<void>('/orders');

      expect(capturedSpan!.isEnded, isTrue);
      expect(capturedSpan!.status, DropSpanStatus.ok);
      expect(capturedSpan!.attributes['http.status_code'], 200);
    });

    test('ends the span with status error when the request fails', () async {
      DropSpan? capturedSpan;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _FakeAdapter(statusCode: 500, throwError: true)
        ..interceptors.add(
          DropDioInterceptor(_CapturingTracing((span) => capturedSpan = span)),
        );

      await expectLater(dio.get<void>('/orders'), throwsA(isA<DioException>()));

      expect(capturedSpan!.isEnded, isTrue);
      expect(capturedSpan!.status, DropSpanStatus.error);
    });
  });
}

/// A [DropTracing] that behaves like [NoopDropTracing] but reports the
/// span it creates back to the caller, so tests can assert on it after
/// the request completes.
class _CapturingTracing implements DropTracing {
  _CapturingTracing(this._onSpanStarted);
  final void Function(DropSpan) _onSpanStarted;

  @override
  DropSpan startSpan(
    String name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  }) {
    final span = DropSpan(
      name,
      parentContext: parentContext,
      attributes: attributes,
    );
    _onSpanStarted(span);
    return span;
  }

  @override
  void forceFlush() {}

  @override
  DropSpanContext? get activeContext => null;
}
