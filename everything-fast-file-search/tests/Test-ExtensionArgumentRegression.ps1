[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = Split-Path -Parent $testsDir
$searchScript = Join-Path $skillRoot 'scripts\Search-Everything.ps1'
$fixtureRoot = Join-Path $testsDir 'fixtures'
$query = 'EFS_REGRESSION_TARGET'

$expected = @{
    inp = 1
    odb = 1
    sta = 1
    msg = 1
    dat = 1
}

$actual = @{}

foreach ($ext in $expected.Keys) {
    $rows = @()

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $rows = @(
            & $searchScript `
                -Query $query `
                -Root $fixtureRoot `
                -Extensions $ext `
                -MaxResults 10 `
                -Quiet `
                -PassThru
        )

        if ($rows.Count -ge $expected[$ext]) { break }
        Start-Sleep -Milliseconds 500
    }

    $actual[$ext] = $rows.Count
}

$failures = @()
foreach ($ext in $expected.Keys) {
    if ($actual[$ext] -ne $expected[$ext]) {
        $failures += "$ext expected=$($expected[$ext]) actual=$($actual[$ext])"
    }
}

$summary = ($expected.Keys | Sort-Object | ForEach-Object { "$_=$($actual[$_])" }) -join ', '
Write-Host "REGRESSION_COUNTS: $summary"

if ($failures.Count -gt 0) {
    Write-Error ("EXTENSION_ARGUMENT_REGRESSION=FAIL; " + ($failures -join '; '))
    exit 1
}

Write-Host 'EXTENSION_ARGUMENT_REGRESSION=PASS'
