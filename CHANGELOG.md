# Changelog

All notable changes to this project are documented here.

## [1.1.0] - 2026-08-12

### Added

- IPC Error 8 diagnostic with elevation-mismatch and missing interactive-client classifications.
- One bounded 750 ms transient retry for readiness probes.
- One bounded 750 ms transient retry for the actual search invocation.
- Synthetic regression coverage for readiness and search Error 8 paths.

### Changed

- Normal runtime invokes the search wrapper directly; integration tests remain maintenance-only checks.
- Known elevation mismatch fails fast instead of repeating ineffective retries.
- Core search exposes the native `es.exe` exit code to the wrapper without changing query construction or parsing.

## [1.0.0] - 2026-08-09

### Added

- Initial public release.
- Bounded Everything searches through `es.exe`.
- Root scoping, extension filtering, and file/folder filters.
- CSV and JSON export.
- Optional SHA-256 for narrowed candidate sets.
- Automatic Everything IPC readiness check.
- Automatic `Everything.exe` start on IPC Error 8 when the process is not already running.
- PowerShell 5.1-compatible independent search-term argument construction.
- Fixture-based regression tests without domain-specific or private project data.

### Design rule

Everything results are treated as locators only. Domain-specific authority and semantic identity checks remain outside this skill.
