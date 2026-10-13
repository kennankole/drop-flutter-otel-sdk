import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Interface mirroring `drop-mobile`'s existing `CrashReporter`
/// (`lib/core/crash/crash_reporter.dart`) exactly, so L6 adoption there is
/// a swap, not a rewrite (OTEL_LIBRARY_PLAN.md L6: "app-side diff is
/// deletions + thin wiring"). `drop-rider`/`drop-admin-mobile` have no
/// such interface today — for them this *is* the new interface (L7).
/// `SentryCrashReporter` (L3) is the real backend; [NoopCrashReporter] is
/// what [DropObservability] wires up until then.
abstract class CrashReporter {
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  });

  Future<void> recordFlutterError(FlutterErrorDetails details);

  Future<void> setUserId(String userId);

  /// Detaches the user set by [setUserId], so later events — including a
  /// different person's after they sign in on the same device — are not
  /// attributed to the previous one. Call it on sign-out.
  Future<void> clearUser();

  /// Reports a failed API request as a non-fatal, tagged with that
  /// request's trace ID (`otel.trace_id`), templated route and status, so
  /// the event opens straight onto the backend trace.
  ///
  /// Reports unconditionally: deciding *which* failures matter (skip
  /// connectivity, expected statuses, 5xx the backend already reports) is
  /// the app's call, not the package's.
  Future<void> recordApiError(DioException error);

  Future<void> log(String message);
}

class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {}

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details) async {}

  @override
  Future<void> setUserId(String userId) async {}

  @override
  Future<void> clearUser() async {}

  @override
  Future<void> recordApiError(DioException error) async {}

  @override
  Future<void> log(String message) async {}
}
