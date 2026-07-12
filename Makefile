.PHONY: help lint test facade-check release

help:
	@echo "Usage:"
	@echo "  make lint                            Run flutter analyze + dart format check"
	@echo "  make test                             Run flutter test"
	@echo "  make facade-check                     Verify only tracer.dart imports the OTEL SDK"
	@echo "  make release [VERSION=x.y.z] [DRY_RUN=1] [PR=1]   Cut a release (see scripts/release.sh)"

lint:
	flutter analyze
	dart format --output=none --set-exit-if-changed lib test

test:
	flutter test --coverage

facade-check:
	./scripts/check_facade_imports.sh

release:
	@bash scripts/release.sh $(if $(filter 1,$(DRY_RUN)),--dry-run) $(if $(filter 1,$(PR)),--pr) $(VERSION)
