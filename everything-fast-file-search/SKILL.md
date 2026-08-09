---
name: everything-fast-file-search
description: Fast, bounded local Windows file discovery using voidtools Everything and es.exe. Use when Codex needs to locate files or folders by basename, keyword, extension, or root path; recover moved paths after directory reorganization; export a small candidate list to CSV/JSON; or avoid expensive broad recursive filesystem scans. Treat results as locators only and perform domain-specific authority checks separately.
---

# Everything Fast File Search

Use Everything as the first-choice locator for local Windows file discovery when `es.exe` is available.

## Core workflow

1. Run `scripts/Ensure-EverythingReady.ps1` before searching.
2. If Everything IPC is ready, continue immediately.
3. If `es.exe` returns Error 8 and `Everything.exe` is not running, allow the readiness script to start Everything and retry IPC.
4. If Everything is already running but IPC is unavailable, do not terminate or restart it; retry briefly and fail closed if IPC does not recover.
5. Run `scripts/Search-Everything.ps1` with the narrowest useful `Root`, query, extension filters, and result cap.
6. Prefer `MaxResults <= 20` for ordinary discovery.
7. Export CSV/JSON when another step needs structured candidates instead of verbose console output.
8. Compute SHA-256 only after the candidate set is small.
9. Treat Everything results as locators only. Do not infer that the first, newest, largest, or similarly named result is authoritative.
10. If a high-stakes task requires identity confirmation, apply domain-specific checks outside this skill.

## PowerShell 5.1 argument rule

Keep independent Everything search terms as independent native arguments.

For example, pass a basename and `ext:...` separately. Do not concatenate them into one quoted string.

Use the implementation in `scripts/Search-Everything.ps1` and keep `tests/Test-ExtensionArgumentRegression.ps1` passing after changes.

## Fallback policy

If Everything or `es.exe` is unavailable:

- report the missing dependency or IPC failure;
- do not automatically replace the search with an unbounded drive-wide recursive scan;
- use a bounded local fallback only when the active task explicitly allows it.

## Supporting resources

Read only as needed:

- `references/everything-cli-notes.md` for CLI behavior and return codes;
- `references/token-efficient-workflow.md` for bounded-context guidance.
