/// Whether a trace with [traceId] (32 hex chars) falls inside [rate]
/// (0.0–1.0).
///
/// Deterministic on the trace ID, with the same rule as the Go SDK's
/// `TraceIDRatioBased` — the lower 8 bytes, shifted right one bit, compared
/// against `rate * 2^63` — so the backend reaches the same verdict for the
/// same trace at the same rate. Pure Dart, so it sits outside the OTEL SDK
/// import boundary and the decision can be tested on its own.
bool isTraceIdSampled(String traceId, double rate) {
  if (rate.isNaN || rate <= 0) return false;
  if (rate >= 1) return true;
  if (traceId.length != 32) return false;

  final high = int.tryParse(traceId.substring(16, 24), radix: 16);
  final low = int.tryParse(traceId.substring(24, 32), radix: 16);
  if (high == null || low == null) return false;

  // `>>>` keeps the 63-bit value non-negative even when bit 63 was set.
  final value = ((high << 32) | low) >>> 1;
  final bound = (rate * 9223372036854775808.0).toInt(); // rate * 2^63
  return value < bound;
}
