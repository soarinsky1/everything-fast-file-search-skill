---
name: everything-fast-file-search
description: Fast, bounded local Windows file discovery using voidtools Everything and es.exe. Use when Codex needs to locate files or folders by basename, keyword, extension, or root path; recover moved paths after directory reorganization; export a small candidate list to CSV/JSON; or avoid expensive broad recursive filesystem scans. Treat results as locators only and perform domain-specific authority checks separately.
---

# Everything Fast File Search

Use Everything as the first-choice locator for local Windows file discovery when `es.exe` is available.

## Core workflow

1. Invoke `scripts/Search-Everything.ps1` directly for normal runtime discovery; it invokes readiness automatically.
2. Let the wrapper complete its one 750 ms passive readiness retry on Error 8, regardless of `AllowStart`.
3. Read-only calls fail closed after that retry; explicitly authorized startup recovery can diagnose the failure. Known `IPC_ELEVATION_MISMATCH` stops recovery.
4. If readiness succeeds but the actual search returns Error 8, retry that identical search once after 750 ms.
5. Do not automatically retry non-8 search errors.
6. Run `scripts/Search-Everything.ps1` with the narrowest useful `Root`, query, extension filters, and result cap.
7. Prefer `MaxResults <= 20` for ordinary discovery.
8. Export CSV/JSON when another step needs structured candidates instead of verbose console output.
9. Compute SHA-256 only after the candidate set is small.
10. Treat Everything results as locators only. Do not infer that the first, newest, largest, or similarly named result is authoritative.
11. If a high-stakes task requires identity confirmation, apply domain-specific checks outside this skill.

## Execution context and startup authority

Normal discovery does not run `Test-EverythingIntegration.ps1` as a preflight.
`Search-Everything.ps1` invokes readiness and uses one resolved CLI path throughout
readiness, diagnosis and both search attempts. The resolver checks PATH, standard
install paths and official WinGet CLI packages. `-EverythingCliPath` takes priority.

Only pass `-AllowStart` when the user authorizes starting Everything. It controls
startup recovery; neither passive 750 ms retry depends on it. Never terminate,
restart or duplicate a running Everything process. The skill does not install
software, edit configuration or grant process privileges.

On final Error 8, preserve the `READINESS_ERROR8_CONTEXT` or
`SEARCH_ERROR8_CONTEXT` JSON evidence. Version-only readiness does not prove that
a subsequent search can complete. Search failure evidence includes the native
error output, capped at 4096 characters, actual CLI path, elapsed time and retry count.
Normal success and successful retries emit no final failure context.

A process that cannot start returns `ES_LAUNCH_FAILED`, wrapper exit 1 and a
structured `ES_LAUNCH_FAILURE_CONTEXT`; it must never report READY from a stale
exit code. Win32 errors 5 (access denied) and 623 (illegal system DLL relocation)
are launch errors, not ES search exit codes, and do not trigger Error 8 retries.

If a sandboxed call fails with final Error 8 or launch error 5/623, use the
execution tool's approval mechanism for one identical bounded host-context call
when available. Keep the query, Root, filters, output options and startup authority
unchanged. If this task already established that the sandbox fails while approved
host execution succeeds, request that permitted context for later authorized
queries instead of repeating a known failing preflight. The script cannot grant
approval itself. If approval is denied/unavailable or host execution also fails,
report the evidence and apply only an authorized narrow fallback. Do not use RunAs,
change ACLs, replace DLLs, copy the executable or add a launcher to evade controls.

Matching Sessions or error 623 alone do not establish a root cause. Successful
host comparison supports an execution-context difference; it does not prove that
system DLLs are damaged or that every historical failure had the same cause.

## PowerShell 5.1 argument rule

Keep independent Everything search terms as independent native arguments.

For example, pass a basename and `ext:...` separately. Do not concatenate them into one quoted string.

Use the implementation in `scripts/Search-Everything.ps1` and keep `tests/Test-ExtensionArgumentRegression.ps1` passing after changes.

Preserve `-cp 65001` with UTF-8 stdout decoding in `Invoke-EverythingCli.ps1`.
It explicitly redirects both output streams, reads the Process exit code and
does not change the caller's console encoding. Simple switches and `ext:` tokens
remain unquoted; quote each individual argument only when required.

## Fallback policy

If Everything or `es.exe` is unavailable:

- report the missing dependency or IPC failure;
- do not automatically replace the search with an unbounded drive-wide recursive scan;
- use a bounded local fallback only when the active task explicitly allows it.

## Supporting resources

Read only as needed:

- `references/everything-cli-notes.md` for CLI behavior and return codes;
- `references/token-efficient-workflow.md` for bounded-context guidance.

Maintenance regressions: `tests/Test-EverythingIpcDiagnostic.ps1`,
`tests/Test-NativeErrorTransport.ps1`, `tests/Test-CliResolution.ps1` and
`tests/Test-CliTransport.ps1`. These use synthetic inputs or temporary fake CLIs;
the extension and search smoke tests additionally use a running Everything index.
