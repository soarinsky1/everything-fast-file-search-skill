# Static test plan

Run on Windows PowerShell 5.1 or newer.

```powershell
.\tests\Test-EverythingIpcDiagnostic.ps1
.\tests\Test-ExtensionArgumentRegression.ps1
.\tests\Test-SearchSmoke.ps1
.\tests\Test-CliResolution.ps1
.\tests\Test-CliTransport.ps1
.\tests\Test-NativeErrorTransport.ps1
```

`Test-EverythingIpcDiagnostic.ps1` is fully synthetic and verifies IPC ready, Error 8 then ready, elevation mismatch, client not running, actual-search Error 8 then ready, two Error 8 results, and a non-8 failure.

`Test-ExtensionArgumentRegression.ps1` creates a generic temporary fixture and verifies that the basename and `ext:<type>` remain separate native arguments.

`Test-SearchSmoke.ps1` is an optional live Everything smoke test. It uses only the installed skill directory and has no project-specific dependency.

`Test-CliResolution.ps1` uses isolated child environments and fake CLIs to cover
empty PATH, official and alternate WinGet package layouts, explicit-path priority,
missing dependencies and identical readiness/search/diagnostic executable paths.

`Test-CliTransport.ps1` covers independent native arguments (including spaces,
quotes, trailing backslashes, empty tokens and Unicode), ES-compatible quoting,
concurrent stdout/stderr capture, actual exit 8, and launch failures that must
never report READY or trigger retries. Its intentional failure case writes one
readiness-failure line to stderr; the suite still exits zero when assertions pass.

`Test-NativeErrorTransport.ps1` sends real native stderr from a temporary fake CLI
through the search wrapper. It covers 0, non-8 failure, 8→0 and 8→8 with both
AllowStart values; verifies identical native parameters; and checks Unicode
result paths plus CSV/JSON round trips and failure-only stdout JSON events.

Launch errors 5, 623 and 193 are synthesized in the IPC suite, with AllowStart
both false and true. No real configuration is changed to manufacture a failure.
No synthetic suite executes the real CLI or starts a real Everything client.

Run the three native fixture drivers with Windows PowerShell 5.1. Repeat them
with `-SearchPowerShellExe <absolute-pwsh-path>` to test a PowerShell 7 child.
The extension regression requires real indexing of its temporary fixture; the
smoke test requires the repository path to be indexed. A missing result is a
test failure, not permission to weaken its assertions.
