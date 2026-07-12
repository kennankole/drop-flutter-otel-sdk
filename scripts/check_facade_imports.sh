#!/usr/bin/env bash
# Enforces OTEL_LIBRARY_PLAN.md design principle 1 (the facade rule): the
# OTEL SDK is imported *only* inside lib/src/tracing/tracer.dart, and no SDK
# type is allowed to leak into the rest of the package. This check is a
# no-op today (lib/ has no SDK imports yet) and starts enforcing for real
# once L2 wires the chosen SDK into the tracer facade.
set -euo pipefail

cd "$(dirname "$0")/.."

ALLOWED_FILE="lib/src/tracing/tracer.dart"
SDK_PACKAGES=("opentelemetry" "dartastic_opentelemetry")

violations=0
while IFS= read -r -d '' file; do
  if [[ "$file" == "$ALLOWED_FILE" ]]; then
    continue
  fi
  for pkg in "${SDK_PACKAGES[@]}"; do
    if grep -qE "^import[[:space:]]+['\"]package:${pkg}/" "$file"; then
      echo "FACADE VIOLATION: $file imports package:${pkg} directly (only $ALLOWED_FILE may)"
      violations=$((violations + 1))
    fi
  done
done < <(find lib -name "*.dart" -print0 2>/dev/null)

if [[ $violations -gt 0 ]]; then
  echo "$violations facade-rule violation(s) found."
  exit 1
fi

echo "OK: no OTEL SDK imports outside $ALLOWED_FILE"
