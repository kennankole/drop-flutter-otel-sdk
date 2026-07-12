import 'span.dart';

/// Package-owned tracing facade — no OTEL SDK type appears in this
/// interface (design principle 1).
abstract class DropTracing {
  DropSpan startSpan(
    String name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  });
}

/// This file is the OTEL SDK import boundary (design principle 1: "the
/// ONLY file importing SDK trace types"). At L1 no SDK is wired in yet —
/// every span is created locally and discarded, never exported, matching
/// "no-op by default" (design principle 2). L2 replaces this class's
/// internals with the chosen SDK (see README.md's L0 decision) without
/// changing [DropTracing]'s shape.
class NoopDropTracing implements DropTracing {
  const NoopDropTracing();

  @override
  DropSpan startSpan(
    String name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  }) {
    return DropSpan(name, parentContext: parentContext, attributes: attributes);
  }
}
