#!/usr/bin/env bash
# Enforces OTEL_LIBRARY_PLAN.md design principle 1 (the facade rule): the
# OTEL SDK is imported *only* inside a small, fixed set of files — the
# facade's SDK-import boundary — and no SDK type is allowed to leak into
# the rest of the package (checked separately by the public barrel's
# curated `export` list in lib/drop_observability.dart, not by this script).
set -euo pipefail

cd "$(dirname "$0")/.."

# tracer.dart backs DropTracing with the real SDK; export_policy.dart and
# otlp_client.dart implement SDK-required interfaces (SpanProcessor,
# SpanExporter) for the same facade — batching/auth policy the SDK's own
# BatchSpanProcessor/CollectorExporter don't support (see those files'
# doc comments). All three exist only to be imported by tracer.dart's
# RealDropTracing; nothing outside lib/src/tracing/ and lib/src/export/
# may import the SDK.
ALLOWED_FILES=(
  "lib/src/tracing/tracer.dart"
  "lib/src/export/export_policy.dart"
  "lib/src/export/otlp_client.dart"
)
SDK_PACKAGES=("opentelemetry" "dartastic_opentelemetry")

is_allowed() {
  local file="$1"
  for allowed in "${ALLOWED_FILES[@]}"; do
    [[ "$file" == "$allowed" ]] && return 0
  done
  return 1
}

violations=0
while IFS= read -r -d '' file; do
  if is_allowed "$file"; then
    continue
  fi
  for pkg in "${SDK_PACKAGES[@]}"; do
    if grep -qE "^import[[:space:]]+['\"]package:${pkg}/" "$file"; then
      echo "FACADE VIOLATION: $file imports package:${pkg} directly (only ${ALLOWED_FILES[*]} may)"
      violations=$((violations + 1))
    fi
  done
done < <(find lib -name "*.dart" -print0 2>/dev/null)

if [[ $violations -gt 0 ]]; then
  echo "$violations facade-rule violation(s) found."
  exit 1
fi

echo "OK: no OTEL SDK imports outside ${ALLOWED_FILES[*]}"
