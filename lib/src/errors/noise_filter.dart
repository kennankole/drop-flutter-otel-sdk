import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// [DioExceptionType]s that burn paid Sentry quota without being an actual
/// bug — connection/timeout/cancel noise (OBSERVABILITY_STRATEGY.md Phase
/// 1.4). Left out on purpose: [DioExceptionType.badResponse] (a real HTTP
/// error status), [DioExceptionType.badCertificate] (security-relevant),
/// [DioExceptionType.unknown] (might be a real bug) — those still reach
/// Sentry.
const _droppedDioExceptionTypes = <DioExceptionType>{
  DioExceptionType.connectionTimeout,
  DioExceptionType.sendTimeout,
  DioExceptionType.receiveTimeout,
  DioExceptionType.connectionError,
  DioExceptionType.cancel,
};

/// A `beforeSend` filter for `SentryFlutterOptions.beforeSend`. Drops
/// network noise before it's ever transmitted, rather than filtering
/// client-side after transmission — matches the strategy's cost-control
/// intent, not just a UI declutter.
SentryEvent? dioNoiseFilter(SentryEvent event, {Hint? hint}) {
  final throwable = event.throwable;
  if (throwable is DioException &&
      _droppedDioExceptionTypes.contains(throwable.type)) {
    return null;
  }
  return event;
}
