import 'package:flutter/widgets.dart';

import '../tracing/tracer.dart';

/// Forces buffered spans out when the app is about to stop running in the
/// foreground — OBSERVABILITY_STRATEGY.md Phase 3.4's "flush on app
/// pause". A no-op call on [NoopDropTracing], so registering this
/// unconditionally is safe (design principle 2).
class FlushOnPauseObserver extends WidgetsBindingObserver {
  FlushOnPauseObserver(this.tracing);

  final DropTracing tracing;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        tracing.forceFlush();
      case AppLifecycleState.resumed:
        break;
    }
  }
}
