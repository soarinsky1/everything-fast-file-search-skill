[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = Split-Path -Parent $testsDir
$searchScript = Join-Path $skillRoot 'scripts\Search-Everything.ps1'

$rows = @(
    & $searchScript `
        -Query 'SKILL.md' `
        -Root $skillRoot `
        -ItemType File `
        -MaxResults 5 `
        -Quiet `
        -PassThru
)

if ($rows.Count -lt 1) {
    Write-Error 'SEARCH_SMOKE=FAIL; SKILL.md was not found inside the skill root.'
    exit 1
}

if ($rows.Count -gt 5) {
    Write-Error "SEARCH_SMOKE=FAIL; result count exceeded MaxResults: $($rows.Count)"
    exit 1
}

Write-Host "SEARCH_SMOKE=PASS; RESULTS=$($rows.Count)"
