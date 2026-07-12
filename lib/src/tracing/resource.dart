import '../scrub/attribute_rules.dart';

/// Builds the low-cardinality resource attributes shared by every span
/// this package exports. Only OBSERVABILITY_STRATEGY.md-approved keys are
/// allowed — userId/storeId/deviceId are enforced-forbidden here too, on
/// top of the per-span scrubbing in [DropSpan.setAttribute] (defense in
/// depth, mirrors the collector-side `transform/filter` processor).
///
/// Deliberately SDK-agnostic (design principle 1) — returns a plain map;
/// tracer.dart (the sole SDK import boundary) converts it into whatever
/// Resource type the chosen SDK needs.
Map<String, String> buildResourceAttributes({
  required String serviceName,
  required String environment,
  required String serviceVersion,
  String? osName,
}) {
  final attrs = <String, String>{
    'service.name': serviceName,
    'deployment.environment': environment,
    'service.version': serviceVersion,
    'os.name': ?osName,
  };
  assertNoForbiddenAttributes(attrs);
  return attrs;
}
