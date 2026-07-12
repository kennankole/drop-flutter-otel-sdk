/// `drop_observability` — shared Flutter OTEL instrumentation package.
///
/// This is the package's sole public export surface (design principle 1,
/// the facade rule, in `OTEL_LIBRARY_PLAN.md`): no OTEL SDK type may
/// appear here or be re-exported from here.
library;

export 'src/config.dart';
export 'src/errors/crash_reporter.dart';
export 'src/errors/noise_filter.dart';
export 'src/errors/sentry_crash_reporter.dart';
export 'src/scrub/attribute_rules.dart' show ForbiddenAttributeException;
export 'src/logging/logger.dart';
export 'src/logging/ring_buffer.dart';
export 'src/network/dio_interceptor.dart';
export 'src/observability.dart';
export 'src/tracing/span.dart';
export 'src/tracing/tracer.dart';
