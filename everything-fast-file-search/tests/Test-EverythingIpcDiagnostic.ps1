[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$diagnoseScript = Join-Path $skillRoot 'scripts\Diagnose-EverythingIpc.ps1'
$ensureScript = Join-Path $skillRoot 'scripts\Ensure-EverythingReady.ps1'
$searchScript = Join-Path $skillRoot 'scripts\Search-Everything.ps1'

# Synthetic probes and searches never execute this readable placeholder.
# Pin it explicitly so the suite needs neither installed es.exe nor live IPC.
$syntheticCli = $PSCommandPath
$PSDefaultParameterValues = @{} + $PSDefaultParameterValues
$PSDefaultParameterValues['*:EverythingCliPath'] = $syntheticCli

function Assert-Case([string]$Name, [object]$Result, [string]$ExpectedCause) {
    if ($Result.ROOT_CAUSE -ne $ExpectedCause) {
        throw "$Name expected $ExpectedCause; got $($Result.ROOT_CAUSE)"
    }
    Write-Host "$Name = PASS"
}

function Invoke-SyntheticSearch([string]$ExitCodes, [switch]$AllowStart) {
    $powerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powerShellExe -PathType Leaf)) {
        $powerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
    }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $searchArguments = @('-NoProfile', '-File', $searchScript, '-Query', 'synthetic_everything_search', '-Root', $env:TEMP, '-MaxResults', '1', '-EverythingCliPath', $syntheticCli, '-SyntheticCoreExitCodes', $ExitCodes, '-SyntheticEnsureProbeExitCodes', '0')
    if ($AllowStart) { $searchArguments += '-AllowStart' }
    $output = @(& $powerShellExe @searchArguments 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = (($output | ForEach-Object { [string]$_ }) -join "`n")
    }
}

$ready = & $diagnoseScript -AsJson -SyntheticEsExitCode 0 | ConvertFrom-Json
Assert-Case 'CASE_READY' $ready 'IPC_READY'

$ensureReadyObjects = @(& $ensureScript -AsJson -SyntheticProbeExitCodes 0 | ConvertFrom-Json)
$ensureReady = $ensureReadyObjects | Where-Object { $_.STATUS } | Select-Object -Last 1
if ($ensureReady.STATUS -ne 'READY' -or $ensureReady.TRANSIENT_RETRY_USED -ne 'NO' -or $ensureReady.AUTO_START_ATTEMPTED -ne 'NO') {
    throw 'CASE_NORMAL_READY_NO_RETRY expected READY without a transient retry or automatic start.'
}
if (@($ensureReadyObjects | Where-Object { $_.EVENT -eq 'READINESS_ERROR8_CONTEXT' }).Count -ne 0) {
    throw 'CASE_NORMAL_READY_NO_RETRY must not emit READINESS_ERROR8_CONTEXT.'
}
Write-Host 'CASE_NORMAL_READY_NO_RETRY = PASS'
$legacy = & $ensureScript -Quiet -PassThru -SyntheticProbeExitCodes 0
if ($legacy.RootCause -ne 'IPC_READY' -or $legacy.TransientRetryUsed -ne 'NO' -or $legacy.EsExe -ne $syntheticCli -or
    $legacy.IpcInitial -ne 'READY' -or $legacy.IpcFinal -ne 'READY' -or $legacy.UserActionRequired -ne $false -or
    $ensureReady.RootCause -ne 'IPC_READY') { throw 'v1.1.0 readiness object/JSON compatibility failed.' }
Write-Output 'CASE_LEGACY_READINESS_INTERFACE = PASS'

$readOnlyRecoveredObjects = @(& $ensureScript -AsJson -SyntheticProbeExitCodes 8,0 | ConvertFrom-Json)
$readOnlyRecovered = $readOnlyRecoveredObjects | Where-Object { $_.STATUS } | Select-Object -Last 1
if ($readOnlyRecovered.STATUS -ne 'READY' -or $readOnlyRecovered.ROOT_CAUSE -ne 'IPC_READY_AFTER_TRANSIENT_RETRY' -or $readOnlyRecovered.TRANSIENT_RETRY_USED -ne 'YES' -or $readOnlyRecovered.AUTO_START_ATTEMPTED -ne 'NO') {
    throw 'CASE_READ_ONLY_ERROR8_THEN_READY expected one passive retry without an automatic start.'
}
if (@($readOnlyRecoveredObjects | Where-Object { $_.EVENT -eq 'READINESS_ERROR8_CONTEXT' }).Count -ne 0) {
    throw 'CASE_READ_ONLY_ERROR8_THEN_READY must not emit READINESS_ERROR8_CONTEXT.'
}
Write-Host 'CASE_ALLOWSTART_FALSE_ERROR8_THEN_READY = PASS'

$unavailableObjects = @(& $ensureScript -AsJson -SyntheticProbeExitCodes 8,8 -SyntheticEverythingProcessState Running -SyntheticIpcWindowState Found -SyntheticIpcWindowHwnd 12345 -SyntheticIpcWindowPid 0 -SyntheticEverythingElevation 0 | ConvertFrom-Json)
$unavailable = $unavailableObjects | Where-Object { $_.STATUS } | Select-Object -Last 1
$unavailableContext = $unavailableObjects | Where-Object { $_.EVENT -eq 'READINESS_ERROR8_CONTEXT' } | Select-Object -First 1
if ($unavailable.STATUS -ne 'UNAVAILABLE' -or $unavailable.TRANSIENT_RETRY_USED -ne 'YES' -or $unavailable.AUTO_START_ATTEMPTED -ne 'NO') {
    throw 'CASE_READ_ONLY_ERROR8_TWICE expected fail-closed after one passive retry without an automatic start.'
}
if (-not $unavailableContext -or $unavailableContext.INITIAL_IPC -ne 'ERROR_8' -or $unavailableContext.RETRY_IPC -ne 'ERROR_8' -or $unavailableContext.FINAL_ACTION -ne 'FAIL_CLOSED' -or $unavailableContext.IPC_WINDOW_FOUND -ne 'YES' -or $unavailableContext.IPC_WINDOW_HWND -ne 12345 -or $unavailableContext.IPC_WINDOW_OWNING_PID -ne 0 -or $unavailableContext.IPC_WINDOW_PROCESS_MATCH -ne 'YES' -or $unavailableContext.EVERYTHING_ELEVATED -ne 'FALSE') {
    throw 'CASE_READ_ONLY_ERROR8_TWICE expected READINESS_ERROR8_CONTEXT after two Error 8 probes.'
}
Write-Host 'CASE_ALLOWSTART_FALSE_ERROR8_TWICE = PASS'
Write-Host 'TEST_READINESS_ERROR8_CONTEXT_CAPTURE = PASS'

$unknownObjects = @(& $ensureScript -AsJson -SyntheticProbeExitCodes 8,8 -SyntheticEverythingProcessState Running -SyntheticContextMetadataUnavailable -SyntheticIpcWindowState Unavailable | ConvertFrom-Json)
$unknownContext = $unknownObjects | Where-Object { $_.EVENT -eq 'READINESS_ERROR8_CONTEXT' } | Select-Object -First 1
if (-not $unknownContext -or $unknownContext.EVERYTHING_PROCESS_PRESENT -ne 'YES' -or $unknownContext.EVERYTHING_SESSION_ID -ne 'UNKNOWN' -or $unknownContext.EVERYTHING_ELEVATED -ne 'UNKNOWN' -or $unknownContext.CURRENT_SESSION_ID -ne 'UNKNOWN' -or $unknownContext.CURRENT_ELEVATED -ne 'UNKNOWN' -or $unknownContext.IPC_WINDOW_FOUND -ne 'UNKNOWN' -or $unknownContext.IPC_WINDOW_PROCESS_MATCH -ne 'UNKNOWN') {
    throw 'CASE_READINESS_ERROR8_UNKNOWN_METADATA expected non-fatal UNKNOWN Session/elevation metadata.'
}
Write-Host 'CASE_READINESS_ERROR8_UNKNOWN_METADATA = PASS'

$retryNon8Objects = @(& $ensureScript -AsJson -SyntheticProbeExitCodes 8,7 | ConvertFrom-Json)
if (@($retryNon8Objects | Where-Object { $_.EVENT -eq 'READINESS_ERROR8_CONTEXT' }).Count -ne 0) {
    throw 'CASE_READINESS_RETRY_NON8_NO_CONTEXT must not emit READINESS_ERROR8_CONTEXT when the retry is not Error 8.'
}
Write-Host 'CASE_READINESS_RETRY_NON8_NO_CONTEXT = PASS'

$searchReady = Invoke-SyntheticSearch '0'
if ($searchReady.ExitCode -ne 0 -or $searchReady.Text -match '"EVENT"\s*:\s*"SEARCH_ERROR8_CONTEXT"' -or $searchReady.Text -notmatch 'SEARCH_RETRY_COUNT=0') {
    throw 'CASE_SEARCH_READY expected successful search without Error 8 context or retry.'
}
Write-Host 'CASE_SEARCH_READY = PASS'

$searchTransientReadOnly = Invoke-SyntheticSearch '8,0'
if ($searchTransientReadOnly.ExitCode -ne 0 -or $searchTransientReadOnly.Text -match '"EVENT"\s*:\s*"SEARCH_ERROR8_CONTEXT"' -or $searchTransientReadOnly.Text -notmatch 'SEARCH_TRANSIENT_RETRY_USED=YES' -or $searchTransientReadOnly.Text -notmatch 'SEARCH_RETRY_COUNT=1' -or $searchTransientReadOnly.Text -notmatch 'SEARCH_ROOT_CAUSE=IPC_READY_AFTER_SEARCH_RETRY') {
    throw 'CASE_SEARCH_ALLOWSTART_FALSE_ERROR8_THEN_READY expected one silent passive search retry.'
}
Write-Host 'CASE_SEARCH_ALLOWSTART_FALSE_ERROR8_THEN_READY = PASS'

$searchTwiceReadOnly = Invoke-SyntheticSearch '8,8'
if ($searchTwiceReadOnly.ExitCode -ne 8 -or $searchTwiceReadOnly.Text -notmatch '"EVENT"\s*:\s*"SEARCH_ERROR8_CONTEXT"' -or $searchTwiceReadOnly.Text -notmatch '"QUERY"\s*:\s*"synthetic_everything_search"' -or $searchTwiceReadOnly.Text -notmatch '"ES_EXIT_CODE"\s*:\s*8' -or $searchTwiceReadOnly.Text -notmatch '"RETRY_COUNT"\s*:\s*1' -or $searchTwiceReadOnly.Text -notmatch '"FINAL_ACTION"\s*:\s*"FALLBACK_HANDOFF"' -or $searchTwiceReadOnly.Text -notmatch 'SEARCH_TRANSIENT_RETRY_USED=YES' -or $searchTwiceReadOnly.Text -notmatch 'SEARCH_RETRY_COUNT=1') {
    throw 'CASE_SEARCH_ALLOWSTART_FALSE_ERROR8_TWICE expected one retry and fallback handoff.'
}
Write-Host 'CASE_SEARCH_ALLOWSTART_FALSE_ERROR8_TWICE = PASS'

$searchTransientAllowStart = Invoke-SyntheticSearch '8,0' -AllowStart
if ($searchTransientAllowStart.ExitCode -ne 0 -or $searchTransientAllowStart.Text -match '"EVENT"\s*:\s*"SEARCH_ERROR8_CONTEXT"' -or $searchTransientAllowStart.Text -notmatch 'SEARCH_TRANSIENT_RETRY_USED=YES' -or $searchTransientAllowStart.Text -notmatch 'SEARCH_RETRY_COUNT=1') {
    throw 'CASE_SEARCH_ALLOWSTART_TRUE_ERROR8_THEN_READY expected one silent passive search retry.'
}
Write-Host 'CASE_SEARCH_ALLOWSTART_TRUE_ERROR8_THEN_READY = PASS'

$searchTwiceAllowStart = Invoke-SyntheticSearch '8,8' -AllowStart
if ($searchTwiceAllowStart.ExitCode -ne 8 -or $searchTwiceAllowStart.Text -notmatch '"EVENT"\s*:\s*"SEARCH_ERROR8_CONTEXT"' -or $searchTwiceAllowStart.Text -notmatch '"RETRY_COUNT"\s*:\s*1' -or $searchTwiceAllowStart.Text -notmatch '"FINAL_ACTION"\s*:\s*"FALLBACK_HANDOFF"' -or $searchTwiceAllowStart.Text -notmatch 'SEARCH_TRANSIENT_RETRY_USED=YES' -or $searchTwiceAllowStart.Text -notmatch 'SEARCH_RETRY_COUNT=1') {
    throw 'CASE_SEARCH_ALLOWSTART_TRUE_ERROR8_TWICE expected one retry and fallback handoff.'
}
Write-Host 'CASE_SEARCH_ALLOWSTART_TRUE_ERROR8_TWICE = PASS'
Write-Host 'TEST_SEARCH_ERROR8_CONTEXT_CAPTURE = PASS'
Write-Host 'CASE_ERROR8_FALLBACK_HANDOFF = PASS'

$searchNon8 = Invoke-SyntheticSearch '7'
if ($searchNon8.ExitCode -ne 7 -or $searchNon8.Text -match '"EVENT"\s*:\s*"SEARCH_ERROR8_CONTEXT"' -or $searchNon8.Text -notmatch 'SEARCH_TRANSIENT_RETRY_USED=NO' -or $searchNon8.Text -notmatch 'SEARCH_RETRY_COUNT=0') {
    throw 'CASE_SEARCH_NON8_ERROR expected no Error 8 context and no transient retry.'
}
Write-Host 'CASE_SEARCH_NON8_ERROR = PASS'

$transient = & $ensureScript -AsJson -AllowStart -SyntheticProbeExitCodes 8,0 | ConvertFrom-Json
Assert-Case 'CASE_TRANSIENT_ERROR8_THEN_READY' $transient 'IPC_READY_AFTER_TRANSIENT_RETRY'
if ($transient.TRANSIENT_RETRY_USED -ne 'YES') {
    throw "CASE_TRANSIENT_ERROR8_THEN_READY expected TRANSIENT_RETRY_USED=YES; got $($transient.TRANSIENT_RETRY_USED)"
}

$allowStartExistingObjects = @(& $ensureScript -AsJson -AllowStart -RetryCount 1 -RetryDelaySeconds 1 -SyntheticProbeExitCodes 8,8,0 -SyntheticDiagnosisRootCause IPC_ERROR8_UNCLASSIFIED -SyntheticEverythingProcessState Running | ConvertFrom-Json)
$allowStartExisting = $allowStartExistingObjects | Where-Object { $_.STATUS } | Select-Object -Last 1
if ($allowStartExisting.STATUS -ne 'READY' -or $allowStartExisting.TRANSIENT_RETRY_USED -ne 'YES' -or $allowStartExisting.AUTO_START_ATTEMPTED -ne 'NO') {
    throw 'CASE_ALLOWSTART_TRUE_EXISTING_BEHAVIOR expected the existing recovery branch only after the transient retry.'
}
Write-Host 'CASE_ALLOWSTART_TRUE_EXISTING_BEHAVIOR = PASS'

$non8 = & $ensureScript -AsJson -SyntheticProbeExitCodes 7 | ConvertFrom-Json
if ($non8.STATUS -ne 'ES_IPC_ERROR' -or $non8.TRANSIENT_RETRY_USED -ne 'NO') {
    throw 'CASE_NON8_NO_TRANSIENT_RETRY expected no transient retry.'
}
Write-Host 'CASE_NON8_NO_TRANSIENT_RETRY = PASS'

$elevation = & $diagnoseScript -AsJson -SyntheticEsExitCode 8 -SyntheticInteractiveClientState Running -SyntheticRunAsAdmin 1 -SyntheticInstanceName '' | ConvertFrom-Json
Assert-Case 'CASE_ELEVATION_MISMATCH' $elevation 'IPC_ELEVATION_MISMATCH'

$ensureElevationObjects = @(& $ensureScript -AsJson -AllowStart -SyntheticProbeExitCodes 8,8 -SyntheticDiagnosisRootCause IPC_ELEVATION_MISMATCH | ConvertFrom-Json)
$ensureElevation = $ensureElevationObjects | Where-Object { $_.STATUS } | Select-Object -Last 1
Assert-Case 'CASE_ELEVATION_MISMATCH_AFTER_TWO_ERROR8' $ensureElevation 'IPC_ELEVATION_MISMATCH'

$missingClient = & $diagnoseScript -AsJson -SyntheticEsExitCode 8 -SyntheticInteractiveClientState NotRunning -SyntheticRunAsAdmin 0 -SyntheticInstanceName '' | ConvertFrom-Json
Assert-Case 'CASE_CLIENT_NOT_RUNNING' $missingClient 'INTERACTIVE_CLIENT_NOT_RUNNING'

foreach ($launchCode in @(5, 623, 193)) {
    foreach ($allow in @($false, $true)) {
        $launch = & $ensureScript -AsJson -AllowStart:$allow -SyntheticLaunchErrorCode $launchCode | ConvertFrom-Json
        if ($LASTEXITCODE -ne 1 -or $launch.STATUS -ne 'ES_LAUNCH_FAILED' -or $launch.WIN32_ERROR_CODE -ne $launchCode -or
            $launch.EVERYTHING_IPC_INITIAL -ne 'NOT_TESTED' -or $launch.TRANSIENT_RETRY_USED -ne 'NO' -or $launch.AUTO_START_ATTEMPTED -ne 'NO') {
            throw "Launch failure $launchCode must not probe, retry or start Everything."
        }
        $expected = if ($launchCode -in @(5,623)) { 'REQUEST_HOST_EXECUTION_APPROVAL_IF_SANDBOXED' } else { 'INSPECT_LAUNCH_ERROR' }
        if ($launch.NEXT_ACTION -ne $expected) { throw "Wrong launch routing for $launchCode" }
        if ($launchCode -eq 623 -and $launch.WIN32_ERROR_NAME -ne 'ERROR_ILLEGAL_DLL_RELOCATION') { throw 'Wrong Win32 623 identity' }
    }
    Write-Output "CASE_LAUNCH_${launchCode}_NO_RETRY_NO_START = PASS"
}
$launchEvent = @(& $ensureScript -SyntheticLaunchErrorCode 623 6>$null) | ConvertFrom-Json
if ($launchEvent.EVENT -ne 'ES_LAUNCH_FAILURE_CONTEXT' -or $launchEvent.WIN32_ERROR_CODE -ne 623 -or
    $launchEvent.NEXT_ACTION -ne 'REQUEST_HOST_EXECUTION_APPROVAL_IF_SANDBOXED' -or $launchEvent.AUTOMATIC_HOST_EXECUTION -ne 'NO') {
    throw 'Win32 623 stdout event must preserve approval-only routing.'
}
Write-Output 'CASE_LAUNCH_623_STDOUT_EVENT = PASS'
$global:LASTEXITCODE = 0
