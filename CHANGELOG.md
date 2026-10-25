# Changelog

All notable changes to this project are documented here.

## [1.2.0] - 2026-10-25

### Added

- Shared native CLI transport with explicit stdout/stderr redirection and Process exit-code capture.
- Failure-only JSON context for readiness, actual searches and process-launch failures.
- Read-only Session, elevation and IPC-window evidence after two readiness Error 8 results.
- Win32 launch error 5/623 classification and an approval-based host-context verification path for sandbox failures.
- Synthetic native-process, CLI-resolution, launch-failure and Unicode CSV/JSON regressions.

### Fixed

- Passive readiness and actual-search retries no longer depend on `-AllowStart`; each remains limited to one 750 ms retry for Error 8.
- Readiness, diagnosis and searches share one resolved CLI path, including WinGet discovery when PATH is unavailable.
- Launch failures cannot reuse a stale success exit code or report READY.
- Explicit UTF-8 output prevents Chinese paths being corrupted and discarded as nonexistent files.
- Independent native arguments and ES-compatible quoting preserve extension filters and filenames containing spaces.
- Preserved the public `Folder` parameter value, readiness `Quiet`/`PassThru` options, legacy readiness properties and candidate export fields, including index-only/stale candidates.

### Changed

- Normal discovery is read-only by default. Starting Everything requires explicit `-AllowStart` authorization.
- Sandbox launch failures and IPC errors retain evidence before any authorized narrow fallback; scripts never grant host approval, change permissions or restart a client.
- Public functionality remains domain-neutral candidate discovery. Environment-specific failures can still occur and are not claimed to be eliminated.

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
