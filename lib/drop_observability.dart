/// `drop_observability` — shared Flutter OTEL instrumentation package.
///
/// This is the package's sole public export surface (design principle 1,
/// the facade rule, in `OTEL_LIBRARY_PLAN.md`): no OTEL SDK type may appear
/// here or be re-exported from here.
///
/// Real API surface (`DropObservability`, `ObservabilityConfig`, tracing,
/// logging, Dio interceptor, crash reporting) lands in L1 onward — see
/// `OTEL_LIBRARY_PLAN.md` in `drop-mobile` and this repo's README.
library;
