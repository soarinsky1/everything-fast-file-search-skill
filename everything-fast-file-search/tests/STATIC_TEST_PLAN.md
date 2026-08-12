# Static test plan

Run on Windows PowerShell 5.1 or newer.

```powershell
.\tests\Test-EverythingIpcDiagnostic.ps1
.\tests\Test-ExtensionArgumentRegression.ps1
.\tests\Test-SearchSmoke.ps1
```

`Test-EverythingIpcDiagnostic.ps1` is fully synthetic and verifies IPC ready, Error 8 then ready, elevation mismatch, client not running, actual-search Error 8 then ready, two Error 8 results, and a non-8 failure.

`Test-ExtensionArgumentRegression.ps1` creates a generic temporary fixture and verifies that the basename and `ext:<type>` remain separate native arguments.

`Test-SearchSmoke.ps1` is an optional live Everything smoke test. It uses only the installed skill directory and has no project-specific dependency.
