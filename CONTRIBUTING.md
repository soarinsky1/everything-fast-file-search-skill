# Contributing

Contributions are welcome when they preserve the project's core design goals:

1. keep searches bounded;
2. prefer deterministic scripts over verbose agent reasoning;
3. preserve PowerShell 5.1 compatibility unless a breaking major version is justified;
4. do not add domain-specific assumptions to the core skill;
5. do not treat Everything search order as semantic authority;
6. include a regression test for bug fixes when practical.

## Before opening a pull request

- Test against a running Everything 1.4+ instance.
- Run `Test-EverythingIpcDiagnostic.ps1`.
- Run `Test-ExtensionArgumentRegression.ps1`.
- Run `Test-SearchSmoke.ps1`.
- Confirm no personal paths, project names, proprietary filenames, or private data are included.
- Keep public examples generic.
