[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Query,
    [string]$Root,
    [string[]]$Extensions,
    [ValidateSet('Any', 'File', 'Folder')] [string]$ItemType = 'Any',
    [ValidateRange(1, 200)] [int]$MaxResults = 20,
    [string]$OutputCsv,
    [string]$OutputJson,
    [switch]$IncludeSha256,
    [ValidateRange(1, 50)] [int]$HashLimit = 10,
    [switch]$Quiet,
    [switch]$PassThru,
    [string]$EverythingCliPath,
    [ValidateRange(500, 30000)] [int]$TimeoutMs = 5000,
    [int[]]$SyntheticEnsureProbeExitCodes,
    [string]$SyntheticCoreExitCodes
)

$ErrorActionPreference = 'Stop'
$ensureScript = Join-Path $PSScriptRoot 'Ensure-EverythingReady.ps1'
$coreScript = Join-Path $PSScriptRoot 'Search-Everything.Core.R1.ps1'

$ensureParameters = @{ Quiet=$true; PassThru=$true }
if ($SyntheticEnsureProbeExitCodes) { $ensureParameters.SyntheticProbeExitCodes = $SyntheticEnsureProbeExitCodes }
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$ready = @(& $ensureScript @ensureParameters)[-1]
$ensureExit = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
if ($ensureExit -ne 0 -or -not $ready -or $ready.IpcFinal -ne 'READY') {
    [Console]::Error.WriteLine('Everything readiness gate failed.')
    exit $ensureExit
}

$coreParameters = @{}
foreach ($parameterName in @('Query','Root','Extensions','ItemType','MaxResults','OutputCsv','OutputJson','IncludeSha256','HashLimit','Quiet','PassThru','EverythingCliPath','TimeoutMs')) {
    if ($PSBoundParameters.ContainsKey($parameterName)) { $coreParameters[$parameterName] = $PSBoundParameters[$parameterName] }
}
[int[]]$syntheticSequence = @()
if ($SyntheticCoreExitCodes) { $syntheticSequence = [int[]]@($SyntheticCoreExitCodes.Split(',') | ForEach-Object { [int]::Parse($_.Trim()) }) }

function Invoke-Core([int]$Attempt) {
    $invoke = @{} + $coreParameters
    if ($syntheticSequence.Count -gt 0) { $invoke.SyntheticEsExitCode = $syntheticSequence[[Math]::Min($Attempt, $syntheticSequence.Count - 1)] }
    $invoke.ReportNativeExitCode = $true
    $global:EverythingSearchCoreNativeExitCode = $null
    & $coreScript @invoke
    $script:CoreExitCode = [int]$global:EverythingSearchCoreNativeExitCode
}

$script:CoreExitCode = $null
Invoke-Core 0
$coreExit = $script:CoreExitCode
$retryUsed = 'NO'; $retryCount = 0
if ($coreExit -eq 9) { $coreExit = 0 }
if ($coreExit -eq 8) {
    Start-Sleep -Milliseconds 750
    $retryUsed = 'YES'; $retryCount = 1
    Invoke-Core 1
    $coreExit = $script:CoreExitCode
    if ($coreExit -eq 9) { $coreExit = 0 }
}
if ($coreExit -ne 0) {
    Write-Host "SEARCH_TRANSIENT_RETRY_USED=$retryUsed"
    Write-Host "SEARCH_RETRY_COUNT=$retryCount"
    [Console]::Error.WriteLine("Everything search core failed with exit code $coreExit")
    exit $coreExit
}
if ($retryUsed -eq 'YES') { Write-Host 'SEARCH_ROOT_CAUSE=IPC_READY_AFTER_SEARCH_RETRY' }
Write-Host "SEARCH_TRANSIENT_RETRY_USED=$retryUsed"
Write-Host "SEARCH_RETRY_COUNT=$retryCount"
exit 0
