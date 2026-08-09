# Changelog

All notable changes to this project are documented here.

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
