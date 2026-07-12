/// Attribute keys that must never appear as a resource attribute or a
/// low-cardinality label (they're fine as ordinary span attributes, where
/// higher cardinality is expected and each span is billed individually
/// rather than becoming a Mimir/Loki label). See
/// OBSERVABILITY_STRATEGY.md "Known Risks" and issue #9 — this is the
/// canonical anti-pattern the whole proxy/collector design exists to avoid.
const forbiddenResourceAttributeKeys = <String>{
  'userId',
  'storeId',
  'deviceId',
};

/// Thrown by [assertNoForbiddenAttributes]. Failing loudly — rather than
/// silently dropping the key — is deliberate: design principle 4 wants a
/// bypassable blocklist to fail a test, not degrade into a silent
/// cardinality bug discovered later in a Grafana Cloud bill.
class ForbiddenAttributeException implements Exception {
  ForbiddenAttributeException(this.key);
  final String key;

  @override
  String toString() =>
      "ForbiddenAttributeException: '$key' may not be a resource or span "
      'attribute (high-cardinality risk — see OBSERVABILITY_STRATEGY.md)';
}

/// Throws [ForbiddenAttributeException] on the first forbidden key found.
/// Used where setting a forbidden key is a programming error that should
/// fail fast (e.g. [DropSpan.setAttribute]).
void assertNoForbiddenAttributes(Map<String, Object?> attributes) {
  for (final key in attributes.keys) {
    if (forbiddenResourceAttributeKeys.contains(key)) {
      throw ForbiddenAttributeException(key);
    }
  }
}

/// Drops forbidden keys instead of throwing — used at export boundaries
/// (L5) as defense in depth, where a policy violation must be best-effort
/// (design principle 5), not fatal to the caller.
Map<String, Object?> scrubAttributes(Map<String, Object?> attributes) {
  return {
    for (final entry in attributes.entries)
      if (!forbiddenResourceAttributeKeys.contains(entry.key))
        entry.key: entry.value,
  };
}
