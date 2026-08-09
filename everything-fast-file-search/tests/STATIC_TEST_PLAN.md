# Static and local test plan

## T1 — Required structure

Confirm that the skill contains:

- `SKILL.md`
- `agents/openai.yaml`
- `scripts/Resolve-EverythingCli.ps1`
- `scripts/Ensure-EverythingReady.ps1`
- `scripts/Search-Everything.ps1`
- `scripts/Get-FileIdentity.ps1`

## T2 — Everything readiness

Run `Ensure-EverythingReady.ps1` and confirm:

```text
Status = READY
IpcFinal = READY
UserActionRequired = False
```

## T3 — Bounded basename search

Search a known local basename with `MaxResults=5` and confirm no more than five paths are returned.

## T4 — Root scope

Search inside a narrow test root and confirm every returned path is inside that root.

## T5 — CSV export

Export up to five candidates and confirm the CSV parses with `Import-Csv`.

## T6 — SHA gating

Use `IncludeSha256` with a small result set and confirm hashes are produced only for files.

## T7 — PowerShell 5.1 extension argument regression

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\tests\Test-ExtensionArgumentRegression.ps1"
```

Expected:

```text
EXTENSION_ARGUMENT_REGRESSION=PASS
```

This test protects the rule that the basename and `ext:...` expression must be passed to `es.exe` as independent native arguments.
