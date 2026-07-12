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
  Future<void> log(String message) async {}
}
