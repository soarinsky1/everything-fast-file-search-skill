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
    $folder = Join-Path $fixtureRoot ($query + '_folder')
    New-Item -ItemType Directory -Path $folder | Out-Null
    $folderRows = @()
    for ($attempt=1; $attempt -le $IndexRetryCount; $attempt++) {
        $folderRows = @(& $search -Query $query -Root $fixtureRoot -ItemType Folder -MaxResults 5 -Quiet -PassThru 6>$null)
        if ($folderRows.Count -ge 1) { break }
        Start-Sleep -Seconds 1
    }
    if ($folderRows.Count -ne 1 -or $folderRows[0].ItemType -ne 'Folder' -or $folderRows[0].DiskStatus -ne 'PRESENT') { throw 'Legacy Folder interface failed.' }
    Write-Host 'LEGACY_FOLDER_INTERFACE=PASS'
    Write-Host 'EXTENSION_ARGUMENT_REGRESSION=PASS'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -like 'efs_extension_fixture_*' -and (Test-Path -LiteralPath $resolved)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
