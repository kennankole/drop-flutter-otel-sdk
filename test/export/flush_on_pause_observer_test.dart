import 'package:drop_observability/drop_observability.dart';
import 'package:drop_observability/src/export/flush_on_pause_observer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FlushCountingTracing implements DropTracing {
  int flushCount = 0;

  @override
  void forceFlush() => flushCount++;

  @override
  DropSpanContext? get activeContext => null;

  @override
  DropSpan startSpan(
    String name, {
    DropSpanContext? parentContext,
    Map<String, Object?>? attributes,
  }) => throw UnimplementedError('not used by these tests');
}

void main() {
  group('FlushOnPauseObserver', () {
    for (final state in [
      AppLifecycleState.paused,
      AppLifecycleState.inactive,
      AppLifecycleState.detached,
      AppLifecycleState.hidden,
    ]) {
      test('flushes on transition to $state', () {
        final tracing = _FlushCountingTracing();
        FlushOnPauseObserver(tracing).didChangeAppLifecycleState(state);
        expect(tracing.flushCount, 1);
      });
    }

    test('does not flush on transition to resumed', () {
      final tracing = _FlushCountingTracing();
      FlushOnPauseObserver(
        tracing,
      ).didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(tracing.flushCount, 0);
    });
  });
}
