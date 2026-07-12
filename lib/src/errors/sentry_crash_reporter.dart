import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../logging/ring_buffer.dart';
import '../tracing/tracer.dart';
import 'crash_reporter.dart';

/// Real backend for [CrashReporter]. Constructed only when
/// `ObservabilityConfig.sentryDsn` is non-empty (DSN-empty ⇒
/// [NoopCrashReporter], per design principle 2) — this class assumes
/// `SentryFlutter.init()` has already run.
///
/// Every event is tagged with `otel.trace_id`/`otel.span_id` from
/// [tracing]'s [DropTracing.activeContext] when one is open (mirrors the
/// backend's `SentryEnrich`, OBSERVABILITY_STRATEGY.md), and carries the
/// last ~200 warning+ log lines from [ringBuffer] as a `log_tail` context
/// — it works at 0% log-export sampling and fully offline, since it never
/// leaves the device until an error actually occurs.
class SentryCrashReporter implements CrashReporter {
  SentryCrashReporter({required this.ringBuffer, required this.tracing});

  final LogRingBuffer ringBuffer;
  final DropTracing tracing;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    await Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (scope) => _enrich(scope, fatal: fatal),
    );
  }

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    await Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
      withScope: (scope) => _enrich(scope, fatal: true),
    );
  }

  @override
  Future<void> setUserId(String userId) async {
    await Sentry.configureScope(
      (scope) => scope.setUser(SentryUser(id: userId)),
    );
  }

  @override
  Future<void> log(String message) async {
    await Sentry.addBreadcrumb(Breadcrumb(message: message));
  }

  Future<void> _enrich(Scope scope, {required bool fatal}) async {
    final context = tracing.activeContext;
    if (context != null) {
      await scope.setTag('otel.trace_id', context.traceId);
      await scope.setTag('otel.span_id', context.spanId);
    }
    if (ringBuffer.lines.isNotEmpty) {
      await scope.setContexts('log_tail', {
        'text': ringBuffer.lines.join('\n'),
      });
    }
    if (fatal) {
      await scope.setTag('fatal', 'true');
    }
  }
}
