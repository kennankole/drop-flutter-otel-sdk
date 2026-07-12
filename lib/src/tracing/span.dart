import 'dart:math';

import '../scrub/attribute_rules.dart';

/// Mirrors OTEL's StatusCode without importing any OTEL SDK type — design
/// principle 1, the facade rule.
enum DropSpanStatus { unset, ok, error }

final _random = Random();

String _randomHex(int bytes) {
  final buffer = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// A W3C-shaped trace/span ID pair, independent of whether the span is
/// ever actually exported. Building this is free — decoupling ID
/// generation from export means `traceparent` propagation across an HTTP
/// call keeps working even when export is disabled or sampled out.
class DropSpanContext {
  DropSpanContext({String? traceId, String? spanId})
    : traceId = traceId ?? _randomHex(16), // 128-bit trace ID
      spanId = spanId ?? _randomHex(8); // 64-bit span ID

  final String traceId;
  final String spanId;

  /// W3C Trace Context `traceparent` header value.
  /// https://www.w3.org/TR/trace-context/
  String toTraceparent({bool sampled = false}) =>
      '00-$traceId-$spanId-${sampled ? '01' : '00'}';

  static final _traceparentPattern = RegExp(
    r'^00-([0-9a-f]{32})-([0-9a-f]{16})-[0-9a-f]{2}$',
  );

  /// Parses an incoming `traceparent` header. Returns null if it isn't
  /// well-formed — per spec, an invalid header means "start a new trace",
  /// not "throw".
  static DropSpanContext? fromTraceparent(String? header) {
    if (header == null) return null;
    final match = _traceparentPattern.firstMatch(header);
    if (match == null) return null;
    return DropSpanContext(traceId: match.group(1), spanId: match.group(2));
  }
}

/// Package-owned span wrapper — no OTEL SDK type appears here (design
/// principle 1). At L1 this only tracks local state and is never exported;
/// L2 wires it to the chosen SDK behind [DropTracing].
class DropSpan {
  DropSpan(
    this.name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  }) : context = DropSpanContext(traceId: parentContext?.traceId),
       attributes = {} {
    if (attributes != null) {
      attributes.forEach(setAttribute);
    }
  }

  final String name;
  final DropSpanContext context;
  final Map<String, Object?> attributes;
  DropSpanStatus status = DropSpanStatus.unset;
  bool _ended = false;

  bool get isEnded => _ended;

  /// Throws [ForbiddenAttributeException] for a forbidden key (design
  /// principle 4) — a span attribute typo like `userId` is a programming
  /// error worth catching immediately, not a runtime data issue to scrub
  /// silently.
  void setAttribute(String key, Object? value) {
    if (_ended) return;
    assertNoForbiddenAttributes({key: value});
    attributes[key] = value;
  }

  void end({DropSpanStatus status = DropSpanStatus.ok}) {
    if (_ended) return;
    this.status = status;
    _ended = true;
  }
}
