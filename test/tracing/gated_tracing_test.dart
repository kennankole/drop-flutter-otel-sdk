import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';

class _MutableGates implements ObservabilityGates {
  @override
  bool otelEnabled = false;

  @override
  double traceSampleRate = 1.0;

  @override
  bool get logsEnabled => false;
}

/// Counts builds and hands out spans it can recognise.
class _FakeRealTracing implements DropTracing {
  final started = <String>[];
  var flushes = 0;

  @override
  DropSpan startSpan(
    String name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  }) {
    started.add(name);
    return DropSpan(name, parentContext: parentContext, attributes: attributes);
  }

  @override
  void forceFlush() => flushes++;

  @override
  DropSpanContext? get activeContext => null;
}

void main() {
  group('GatedDropTracing', () {
    late _MutableGates gates;
    late int builds;
    late _FakeRealTracing real;
    late GatedDropTracing tracing;

    setUp(() {
      gates = _MutableGates();
      builds = 0;
      real = _FakeRealTracing();
      tracing = GatedDropTracing(
        gates: gates,
        buildReal: () {
          builds++;
          return real;
        },
      );
    });

    test('never builds the real tracer while the gate stays off', () {
      tracing.startSpan('a').end();
      tracing.forceFlush();

      expect(builds, 0);
      expect(tracing.isRealTracingStarted, isFalse);
    });

    // L3: a remote-config fetch that lands after init() must apply in the
    // same session, not the next one.
    test('a gate turned on mid-session applies to the next span', () {
      tracing.startSpan('before');
      gates.otelEnabled = true;
      tracing.startSpan('after');

      expect(real.started, ['after']);
      expect(builds, 1);
    });

    test('builds the real tracer once and reuses it', () {
      gates.otelEnabled = true;
      tracing.startSpan('a');
      tracing.startSpan('b');

      expect(builds, 1);
      expect(real.started, ['a', 'b']);
    });

    test('a gate turned off stops new real spans but still flushes', () {
      gates.otelEnabled = true;
      tracing.startSpan('a');
      gates.otelEnabled = false;
      tracing.startSpan('b');
      tracing.forceFlush();

      expect(real.started, ['a']);
      expect(real.flushes, 1);
    });
  });
}
