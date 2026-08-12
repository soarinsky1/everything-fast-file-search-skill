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
- [ ] Everything auto-start behavior is tested without terminating an existing Everything process.
- [ ] `CHANGELOG.md` contains the release entry.
- [ ] Version tag follows semantic versioning.
