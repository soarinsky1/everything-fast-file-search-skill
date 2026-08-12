[CmdletBinding()]
param(
    [ValidateRange(1, 15)] [int]$IndexRetryCount = 10
)

$ErrorActionPreference = 'Stop'
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = Split-Path -Parent $testsDir
$search = Join-Path $skillRoot 'scripts\Search-Everything.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("efs_extension_fixture_{0}" -f [guid]::NewGuid().ToString('N'))
$query = 'EFS_EXTENSION_ARGUMENT_FIXTURE'

try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    foreach ($extension in @('txt', 'json')) { New-Item -ItemType File -Path (Join-Path $fixtureRoot ("$query.$extension")) -Force | Out-Null }
    $counts = @{}
    foreach ($extension in @('txt', 'json')) {
        $rows = @()
        for ($attempt = 1; $attempt -le $IndexRetryCount; $attempt++) {
            $rows = @(& $search -Query $query -Root $fixtureRoot -Extensions $extension -MaxResults 5 -Quiet -PassThru 6>$null)
            if ($rows.Count -ge 1) { break }
            Start-Sleep -Seconds 1
        }
        $counts[$extension] = $rows.Count
    }
    if ($counts.txt -lt 1 -or $counts.json -lt 1) { throw "Generic extension fixture not found: txt=$($counts.txt), json=$($counts.json)" }
    Write-Host "REGRESSION_COUNTS: txt=$($counts.txt), json=$($counts.json)"
    Write-Host 'EXTENSION_ARGUMENT_REGRESSION=PASS'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
