# Release checklist

Use this checklist before publishing a release.

- [ ] No personal Windows paths remain in tracked files.
- [ ] No project-specific filenames or proprietary data remain.
- [ ] `README.md` matches current behavior.
- [ ] `SKILL.md` frontmatter contains only `name` and `description`.
- [ ] `agents/openai.yaml` still matches the skill purpose.
- [ ] `Test-ExtensionArgumentRegression.ps1` passes on Windows PowerShell 5.1.
- [ ] `Test-EverythingIpcDiagnostic.ps1` passes, including synthetic Error 8 retry cases.
- [ ] `Test-SearchSmoke.ps1` passes.
- [ ] CLI resolution, native transport and Unicode CSV/JSON regressions pass on Windows PowerShell 5.1 and an available PowerShell 7 host.
- [ ] Launch errors 5/623 retain structured evidence and request approval-only host verification; other launch errors are not mislabeled.
- [ ] Read-only searches never start a client; startup authority and both one-shot 750 ms retries are covered synthetically without terminating any real process.
- [ ] `CHANGELOG.md` contains the release entry.
- [ ] Version tag follows semantic versioning.
