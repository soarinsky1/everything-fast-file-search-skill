# Everything Fast File Search Skill

**Token-efficient Windows file discovery for AI coding agents using voidtools Everything and `es.exe`.**

This repository packages a reusable Agent Skill that lets Codex and other skill-aware agents locate local Windows files through the Everything index instead of repeatedly walking large directory trees.

> **Unofficial community integration.** This project is not affiliated with or endorsed by voidtools or OpenAI. Everything is developed by voidtools; Codex is developed by OpenAI.

## Why this exists

AI coding agents often need to answer simple local questions such as:

- Where is this file?
- Which run directory contains this job name?
- Find all `.csv` or `.json` files matching this basename.
- Locate a known artifact after folders were reorganized.

On large Windows workspaces, a broad recursive scan can produce thousands of paths that the agent must then parse. If Everything is already indexing the machine, that work is redundant.

This skill uses the official Everything command-line interface (`es.exe`) to:

1. query the existing Everything index;
2. keep result sets deliberately small;
3. return only the candidate paths and metadata the agent needs;
4. optionally export CSV/JSON for downstream automation;
5. optionally hash only a small final candidate set;
6. optionally start a missing Everything client when explicitly authorized.

The design goal is **bounded context**, not just fast search.

## Features

- Windows-first local file discovery through `es.exe`
- Root-scoped searches with `-path`
- Bounded result counts
- Extension filters passed as independent Everything search terms
- File/folder filtering
- CSV and JSON export
- Optional SHA-256 for small candidate sets
- Automatic Everything IPC readiness check
- Explicitly authorized client startup through `-AllowStart`; read-only discovery by default
- Error 8 diagnosis, including known elevation mismatch detection
- One bounded 750 ms transient retry for readiness and actual searches
- PowerShell 5.1 compatible scripts
- Regression coverage for the PowerShell 5.1 + `es.exe` argument-construction pitfall
- Shared CLI resolution, including WinGet fallback when PATH is unavailable
- UTF-8 native capture for Chinese and other Unicode filenames
- Failure-only JSON evidence for IPC and process-launch errors, including Win32 5/623
- Fail-closed guidance: search results locate candidates; they do not establish semantic authority

## Requirements

> **Important Prerequisite:**
> This skill requires **Everything Search Client (`Everything.exe`)** to be downloaded, installed, and running in the background on your Windows machine.
> This skill provides an agent interface to your local Everything index via `es.exe`; it does **not** install Everything for you.

- Windows OS
- Everything 1.4+ installed (Desktop client running in background)
- Everything command-line interface (`es.exe`)
- Windows PowerShell 5.1 or newer

Official Everything Download: https://www.voidtools.com/
Official Everything CLI documentation: https://www.voidtools.com/support/everything/command_line_interface/

## Repository layout

```text
everything-fast-file-search-skill/
├─ README.md
├─ LICENSE
├─ CHANGELOG.md
├─ CONTRIBUTING.md
├─ SECURITY.md
└─ everything-fast-file-search/
   ├─ SKILL.md
   ├─ agents/
   │  └─ openai.yaml
   ├─ scripts/
   │  ├─ Resolve-EverythingCli.ps1
   │  ├─ Ensure-EverythingReady.ps1
   │  ├─ Diagnose-EverythingIpc.ps1
   │  ├─ Invoke-EverythingCli.ps1
   │  ├─ Search-Everything.ps1
   │  ├─ Search-Everything.Core.R1.ps1
   │  └─ Get-FileIdentity.ps1
   ├─ references/
   │  ├─ everything-cli-notes.md
   │  └─ token-efficient-workflow.md
   └─ tests/
      ├─ Test-ExtensionArgumentRegression.ps1
      ├─ Test-EverythingIpcDiagnostic.ps1
      ├─ Test-NativeErrorTransport.ps1
      ├─ Test-CliResolution.ps1
      ├─ Test-CliTransport.ps1
      ├─ Test-SearchSmoke.ps1
      ├─ STATIC_TEST_PLAN.md
      └─ fixtures/
```

## Installation

### Option A — copy the skill folder

Copy:

```text
everything-fast-file-search
```

into your Codex user skills directory. A commonly used Windows location is:

```text
%USERPROFILE%\.agents\skills\everything-fast-file-search
```

Restart Codex after installation so the skill can be rediscovered.

### Option B — install from the repository with your agent tooling

If your Codex build supports installing a skill from a GitHub directory, point the installer at:

```text
everything-fast-file-search/
```

inside this repository, then restart Codex.

## Quick start

### Check Everything IPC readiness

```powershell
$skill = "$env:USERPROFILE\.agents\skills\everything-fast-file-search"
& "$skill\scripts\Ensure-EverythingReady.ps1"
```

For normal runtime discovery, invoke `Search-Everything.ps1` directly; it performs the readiness check. Readiness and actual search each permit one identical 750 ms retry for Error 8, independently of `-AllowStart`. Other errors do not trigger that transient retry. Omit `-AllowStart` for read-only discovery; include it only when the user authorizes starting a missing client. Running clients are never terminated or restarted.

Readiness and search use the same resolved `es.exe`. Native output is captured with explicit redirection and UTF-8 search decoding. Final failures preserve compact JSON evidence on stdout. A process-launch failure is `ES_LAUNCH_FAILED` (wrapper exit 1), with its separate `WIN32_ERROR_CODE`; error 623 is not an ES search exit code.

Sandbox restrictions can prevent launching the CLI or reaching IPC. For final sandbox Error 8 or launch errors 5/623, the agent can request one identical bounded host-context call through its execution tool's approval mechanism. The script does not bypass the sandbox or grant approval. If approval is unavailable/denied, or the host call fails too, use only the fallback allowed by the task. These diagnostics do not guarantee that every environment failure can be recovered automatically.

### Search by basename

```powershell
& "$skill\scripts\Search-Everything.ps1" `
  -Query "report_2026" `
  -Root "D:\Research" `
  -MaxResults 20
```

### Search by extension

```powershell
& "$skill\scripts\Search-Everything.ps1" `
  -Query "report_2026" `
  -Root "D:\Research" `
  -Extensions pdf,docx `
  -MaxResults 20
```

### Export a small candidate set to CSV

```powershell
& "$skill\scripts\Search-Everything.ps1" `
  -Query "dataset" `
  -Root "D:\Research" `
  -Extensions csv,json `
  -MaxResults 20 `
  -OutputCsv ".\file_candidates.csv"
```

### Add SHA-256 only after narrowing the set

```powershell
& "$skill\scripts\Search-Everything.ps1" `
  -Query "final_model" `
  -Root "D:\Research" `
  -Extensions json,csv `
  -MaxResults 5 `
  -IncludeSha256 `
  -HashLimit 5
```

## Important PowerShell 5.1 rule

When calling `es.exe`, independent Everything search terms must stay independent native command-line arguments.

Correct:

```powershell
$terms = @(
  "report_2026",
  "ext:pdf;docx"
)
& $es @options @terms
```

Do **not** collapse them into one quoted argument:

```powershell
& $es @options "report_2026 ext:pdf;docx"
```

The latter can return zero results even though the Everything GUI finds matching files.

This repository includes a permanent regression test for that behavior.

## Search results are locators, not authority

Finding a path does not prove that the file is the authoritative, final, newest, correct, or semantically relevant file.

For high-stakes workflows, follow discovery with whatever identity checks the domain requires, such as:

- expected directory or lineage;
- file size;
- SHA-256;
- manifest membership;
- embedded metadata;
- application-specific validation.

The skill deliberately stops at **candidate discovery and lightweight file identity**.

## Tests

Run the extension regression test:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\everything-fast-file-search\tests\Test-ExtensionArgumentRegression.ps1"
```

Run the IPC and search-retry regression:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\everything-fast-file-search\tests\Test-EverythingIpcDiagnostic.ps1"
```

Run the smoke test:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\everything-fast-file-search\tests\Test-SearchSmoke.ps1"
```

The fixture-based tests contain no project-specific paths or proprietary files.

Additional synthetic regressions (no running Everything required):

```powershell
powershell.exe -NoProfile -File ".\everything-fast-file-search\tests\Test-CliResolution.ps1"
powershell.exe -NoProfile -File ".\everything-fast-file-search\tests\Test-CliTransport.ps1"
powershell.exe -NoProfile -File ".\everything-fast-file-search\tests\Test-NativeErrorTransport.ps1"
```

These three drivers compile temporary fake console programs using Windows PowerShell
5.1. To also exercise a PowerShell 7 search host, add `-SearchPowerShellExe`
with the full path to `pwsh.exe`. Fixtures and exports are temporary and cleaned up.
The extension regression and optional search smoke test use the real Everything index.

## Versioning

This repository uses semantic versioning:

- patch: bug fixes;
- minor: backward-compatible features;
- major: breaking behavior or interface changes.

Current release: **v1.2.0**.

## License

MIT. See [LICENSE](LICENSE).
