# EVERYTHING_SKILL_R11_WRAPPER

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Query,
    [string]$Root,
    [ValidateRange(1, 200)] [int]$MaxResults = 20,
    [ValidateSet('Any', 'File', 'Folder', 'Directory')] [string]$ItemType = 'Any',
    [string[]]$Extensions,
    [ValidateSet('path', 'name', 'size', 'extension', 'date-created', 'date-modified', 'date-accessed')] [string]$SortBy = 'path',
    [switch]$Descending,
    [switch]$Regex,
    [switch]$CaseSensitive,
    [switch]$MatchPath,
    [switch]$IncludeSha256,
    [ValidateRange(1, 50)] [int]$HashLimit = 10,
    [string]$OutputCsv,
    [string]$OutputJson,
    [string]$EverythingCliPath,
    [ValidateRange(500, 30000)] [int]$TimeoutMs = 5000,
    [switch]$Quiet,
    [switch]$PassThru,
    [switch]$AllowStart,

    # Test-only: comma-separated native search exit codes for retry regression.
    [string]$SyntheticCoreExitCodes,

    # Test-only: readiness outcomes; production calls leave this unset.
    [int[]]$SyntheticEnsureProbeExitCodes
)

$ErrorActionPreference = 'Stop'
$ScriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnsureScript = Join-Path $ScriptsDir 'Ensure-EverythingReady.ps1'
$CoreScript = Join-Path $ScriptsDir 'Search-Everything.Core.R1.ps1'
$ResolveCliScript = Join-Path $ScriptsDir 'Resolve-EverythingCli.ps1'

if (-not (Test-Path -LiteralPath $EnsureScript)) {
    throw "Ensure-EverythingReady.ps1 missing: $EnsureScript"
}
if (-not (Test-Path -LiteralPath $CoreScript)) {
    throw "R1 core search script missing: $CoreScript"
}

function Get-SearchError8Context {
    param(
        [int]$ErrorExitCode,
        [int]$FinalExitCode,
        [int]$RetryCount,
        [object]$NativeResult
    )

    $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $currentSessionId = $null
    try { $currentSessionId = $currentProcess.SessionId } catch {}

    $isElevated = $null
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {}

    $everythingProcess = @(
        Get-Process -Name Everything -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $currentSessionId } |
        Select-Object -First 1
    )
    if ($everythingProcess.Count -eq 0) {
        $everythingProcess = @(Get-Process -Name Everything -ErrorAction SilentlyContinue | Select-Object -First 1)
    }

    $esPath = if ($NativeResult) { $NativeResult.EsPath } else { $EverythingCliPath }
    if (-not $esPath -and (Test-Path -LiteralPath $ResolveCliScript -PathType Leaf)) {
        try { $esPath = @(& $ResolveCliScript -EverythingCliPath $EverythingCliPath)[0] } catch {}
    }

    [ordered]@{
        EVENT = 'SEARCH_ERROR8_CONTEXT'
        TIMESTAMP = (Get-Date).ToUniversalTime().ToString('o')
        QUERY = $Query
        ROOT = $Root
        ES_EXE_PATH = $esPath
        ES_EXIT_CODE = $ErrorExitCode
        ES_OUTPUT = if ($NativeResult) { $NativeResult.Output } else { '' }
        ES_OUTPUT_TRUNCATED = if ($NativeResult) { $NativeResult.OutputTruncated } else { $false }
        SEARCH_ELAPSED_MS = if ($NativeResult) { $NativeResult.ElapsedMs } else { $null }
        IPC_TIMEOUT_MS = $TimeoutMs
        EXECUTION_CONTEXT_HINT = 'CHECK_HOST_IPC_VIA_TOOL_APPROVAL'
        EVERYTHING_EXISTS = if ($everythingProcess.Count -gt 0) { $true } else { $false }
        EVERYTHING_PID = if ($everythingProcess.Count -gt 0) { $everythingProcess[0].Id } else { $null }
        EVERYTHING_SESSION_ID = if ($everythingProcess.Count -gt 0) { $everythingProcess[0].SessionId } else { $null }
        CURRENT_SESSION_ID = $currentSessionId
        CURRENT_PROCESS_ELEVATED = $isElevated
        RETRY_COUNT = $RetryCount
        FINAL_ACTION = if ($FinalExitCode -eq 0 -and $RetryCount -gt 0) {
            'RETRY_RECOVERED'
        }
        elseif ($FinalExitCode -eq 0) {
            'SEARCH_SUCCEEDED'
        }
        else {
            'FALLBACK_HANDOFF'
        }
        FINAL_ES_EXIT_CODE = $FinalExitCode
    }
}

$coreParameters = @{}
foreach ($parameterName in $PSBoundParameters.Keys) {
    if ($parameterName -notin @('SyntheticCoreExitCodes', 'SyntheticEnsureProbeExitCodes', 'AllowStart')) {
        $coreParameters[$parameterName] = $PSBoundParameters[$parameterName]
    }
}
[int[]]$syntheticCoreExitSequence = @()
if ($SyntheticCoreExitCodes) {
    $parsedSyntheticExitCodes = @($SyntheticCoreExitCodes.Split(',') | ForEach-Object { [int]::Parse($_.Trim()) })
    $syntheticCoreExitSequence = [int[]]$parsedSyntheticExitCodes
}

# Resolve once and pin readiness, diagnosis and both search attempts to this CLI.
try {
    $resolvedCli = & $ResolveCliScript -EverythingCliPath $EverythingCliPath
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
$coreParameters.EverythingCliPath = $resolvedCli
$ensureParameters = @{ AllowStart = $AllowStart; EverythingCliPath = $resolvedCli }
if ($PSBoundParameters.ContainsKey('SyntheticEnsureProbeExitCodes')) {
    $ensureParameters.SyntheticProbeExitCodes = $SyntheticEnsureProbeExitCodes
}
& $EnsureScript @ensureParameters
$ensureExit = $LASTEXITCODE
if ($ensureExit -ne 0) {
    [Console]::Error.WriteLine("Everything readiness gate failed with exit code {0}" -f $ensureExit)
    exit $ensureExit
}

function Invoke-CoreSearch {
    param([int]$Attempt)

    $invokeParameters = @{} + $coreParameters
    if ($syntheticCoreExitSequence.Count -gt 0) {
        $index = [Math]::Min($Attempt, $syntheticCoreExitSequence.Count - 1)
        $invokeParameters.SyntheticEsExitCode = $syntheticCoreExitSequence[$index]
    }
    $invokeParameters.ReportNativeExitCode = $true

    $global:EverythingSearchCoreNativeExitCode = $null
    $global:EverythingSearchCoreNativeResult = $null
    & $CoreScript @invokeParameters
    $script:CoreExit = [int]$global:EverythingSearchCoreNativeExitCode
    $script:CoreNativeResult = $global:EverythingSearchCoreNativeResult
}

$script:CoreExit = $null
Invoke-CoreSearch -Attempt 0
$coreExit = $script:CoreExit
$searchRetryUsed = 'NO'
$searchRetryCount = 0
$error8Observed = ($coreExit -eq 8)

if ($coreExit -eq 8) {
    Start-Sleep -Milliseconds 750
    $searchRetryUsed = 'YES'
    $searchRetryCount = 1
    Invoke-CoreSearch -Attempt 1
    $coreExit = $script:CoreExit
}

if ($null -eq $coreExit) {
    $coreExit = 0
}

# Core maps ES exit code 9 to a normal NO_RESULTS result.
if ($coreExit -eq 9) {
    $coreExit = 0
}

if ($error8Observed -and $coreExit -eq 8) {
    $searchError8Context = Get-SearchError8Context -ErrorExitCode 8 -FinalExitCode $coreExit -RetryCount $searchRetryCount -NativeResult $script:CoreNativeResult
    Write-Output ($searchError8Context | ConvertTo-Json -Compress -Depth 3)
}

if ($coreExit -ne 0) {
    Write-Host ("SEARCH_TRANSIENT_RETRY_USED={0}" -f $searchRetryUsed)
    Write-Host ("SEARCH_RETRY_COUNT={0}" -f $searchRetryCount)
    [Console]::Error.WriteLine("Everything search core failed with exit code {0}" -f $coreExit)
    if ($script:CoreNativeResult -and $script:CoreNativeResult.Output) {
        [Console]::Error.WriteLine($script:CoreNativeResult.Output)
    }
    exit $coreExit
}

if ($searchRetryUsed -eq 'YES') {
    Write-Host 'SEARCH_ROOT_CAUSE=IPC_READY_AFTER_SEARCH_RETRY'
}
Write-Host ("SEARCH_TRANSIENT_RETRY_USED={0}" -f $searchRetryUsed)
Write-Host ("SEARCH_RETRY_COUNT={0}" -f $searchRetryCount)
exit $coreExit
