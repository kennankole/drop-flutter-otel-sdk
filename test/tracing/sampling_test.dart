import 'dart:math';

import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isTraceIdSampled', () {
    final random = Random(42);
    String randomTraceId() =>
        List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();

    test('rate 0 keeps nothing and rate 1 keeps everything', () {
      final id = randomTraceId();
      expect(isTraceIdSampled(id, 0), isFalse);
      expect(isTraceIdSampled(id, 1), isTrue);
      expect(isTraceIdSampled(id, -1), isFalse);
      expect(isTraceIdSampled(id, 2), isTrue);
      expect(isTraceIdSampled(id, double.nan), isFalse);
    });

    test('is deterministic for a given trace ID', () {
      final id = randomTraceId();
      final first = isTraceIdSampled(id, 0.5);
      for (var i = 0; i < 10; i++) {
        expect(isTraceIdSampled(id, 0.5), first);
      }
    });

    // Go's TraceIDRatioBased: lower 8 bytes >> 1 < rate * 2^63. The
    // extremes pin the byte order and the shift, so client and backend
    // agree on the same trace.
    test('follows the Go SDK rule on the lower 8 bytes', () {
      const lowestLowerBytes = 'ffffffffffffffff0000000000000000';
      const highestLowerBytes = '0000000000000000ffffffffffffffff';
      expect(isTraceIdSampled(lowestLowerBytes, 0.0001), isTrue);
      expect(isTraceIdSampled(highestLowerBytes, 0.9999), isFalse);
      // Exactly half of the range: 0x7fff... >> 1 sits just under 2^62.
      expect(isTraceIdSampled('00000000000000007fffffffffffffff', 0.5), isTrue);
      expect(
        isTraceIdSampled('00000000000000008000000000000000', 0.5),
        isFalse,
      );
    });

    test('keeps roughly the configured share of random traces', () {
      const n = 20000;
      var kept = 0;
      for (var i = 0; i < n; i++) {
        if (isTraceIdSampled(randomTraceId(), 0.25)) kept++;
      }
      expect(kept / n, closeTo(0.25, 0.02));
    });

    test('a malformed trace ID is not sampled', () {
      expect(isTraceIdSampled('xyz', 0.5), isFalse);
      expect(isTraceIdSampled('g' * 32, 0.5), isFalse);
    });
  });
}
