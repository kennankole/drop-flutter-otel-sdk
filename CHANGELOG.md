# Changelog

All notable changes to `drop_observability` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries below are added by `scripts/release.sh` — see that script or
`make release` to cut a release.

## [1.0.0] — 2026-07-12

### Features

- bootstrap drop-flutter-otel library
- implement — export policy, Bearer auth, and flush-on-pause
- implement instrumentation library surface
- implement — real SDK-backed tracing via opentelemetry
- implement — Sentry crash reporting with OTEL correlation

### Chores

- update docs