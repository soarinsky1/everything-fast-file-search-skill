[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = Split-Path -Parent $testsDir
$diagnose = Join-Path $skillRoot 'scripts\Diagnose-EverythingIpc.ps1'
$ensure = Join-Path $skillRoot 'scripts\Ensure-EverythingReady.ps1'
$search = Join-Path $skillRoot 'scripts\Search-Everything.ps1'

function Assert-Value([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "$Name failed." }
    Write-Host "$Name = PASS"
}

function Invoke-SyntheticSearch([string]$Sequence) {
    $hostExe = Join-Path $PSHOME 'powershell.exe'
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @(& $hostExe -NoProfile -File $search -Query 'EFS_SYNTHETIC_QUERY' -Root $env:TEMP -MaxResults 1 -SyntheticEnsureProbeExitCodes 0 -SyntheticCoreExitCodes $Sequence 2>&1)
    $result = [pscustomobject]@{ ExitCode=$LASTEXITCODE; Text=(($output | ForEach-Object { [string]$_ }) -join "`n") }
    $ErrorActionPreference = $previousPreference
    return $result
}

$ready = & $diagnose -AsJson -SyntheticEsExitCode 0 | ConvertFrom-Json
Assert-Value 'CASE_READY' ($ready.ROOT_CAUSE -eq 'IPC_READY')

$ensureTransient = & $ensure -AsJson -SyntheticProbeExitCodes 8,0 | ConvertFrom-Json
Assert-Value 'CASE_ERROR8_THEN_READY' ($ensureTransient.RootCause -eq 'IPC_READY_AFTER_TRANSIENT_RETRY' -and $ensureTransient.TransientRetryUsed -eq 'YES')

$elevation = & $diagnose -AsJson -SyntheticEsExitCode 8 -SyntheticInteractiveClientState Running -SyntheticRunAsAdmin 1 -SyntheticInstanceName '' | ConvertFrom-Json
Assert-Value 'CASE_ELEVATION_MISMATCH' ($elevation.ROOT_CAUSE -eq 'IPC_ELEVATION_MISMATCH')

$missing = & $diagnose -AsJson -SyntheticEsExitCode 8 -SyntheticInteractiveClientState NotRunning | ConvertFrom-Json
Assert-Value 'CASE_CLIENT_NOT_RUNNING' ($missing.ROOT_CAUSE -eq 'INTERACTIVE_CLIENT_NOT_RUNNING')

$searchReady = Invoke-SyntheticSearch '0'
Assert-Value 'CASE_SEARCH_READY' ($searchReady.ExitCode -eq 0 -and $searchReady.Text -match 'SEARCH_RETRY_COUNT=0')

$searchTransient = Invoke-SyntheticSearch '8,0'
Assert-Value 'CASE_SEARCH_ERROR8_THEN_READY' ($searchTransient.ExitCode -eq 0 -and $searchTransient.Text -match 'SEARCH_TRANSIENT_RETRY_USED=YES' -and $searchTransient.Text -match 'SEARCH_RETRY_COUNT=1' -and $searchTransient.Text -match 'SEARCH_ROOT_CAUSE=IPC_READY_AFTER_SEARCH_RETRY')

$searchTwice = Invoke-SyntheticSearch '8,8'
Assert-Value 'CASE_SEARCH_ERROR8_TWICE' ($searchTwice.ExitCode -eq 8 -and $searchTwice.Text -match 'SEARCH_TRANSIENT_RETRY_USED=YES' -and $searchTwice.Text -match 'SEARCH_RETRY_COUNT=1')

$searchNon8 = Invoke-SyntheticSearch '7'
Assert-Value 'CASE_SEARCH_NON8_ERROR' ($searchNon8.ExitCode -eq 7 -and $searchNon8.Text -match 'SEARCH_TRANSIENT_RETRY_USED=NO' -and $searchNon8.Text -match 'SEARCH_RETRY_COUNT=0')

$global:LASTEXITCODE = 0
