[CmdletBinding()]
param(
    [ValidateRange(1, 10)] [int]$RetryCount = 3,
    [ValidateRange(1, 30)] [int]$RetryDelaySeconds = 2,
    [switch]$Quiet,
    [switch]$PassThru,
    [switch]$AsJson,
    [int[]]$SyntheticProbeExitCodes,
    [ValidateSet('', 'IPC_ELEVATION_MISMATCH', 'INTERACTIVE_CLIENT_NOT_RUNNING', 'IPC_ERROR8_UNCLASSIFIED')] [string]$SyntheticDiagnosisRootCause = ''
)

$ErrorActionPreference = 'Stop'
$resolveCli = Join-Path $PSScriptRoot 'Resolve-EverythingCli.ps1'
$script:probeIndex = 0

function Test-Ipc([string]$EsExe) {
    if ($SyntheticProbeExitCodes) {
        $index = [Math]::Min($script:probeIndex, $SyntheticProbeExitCodes.Count - 1)
        $script:probeIndex++
        return [pscustomobject]@{ ExitCode=$SyntheticProbeExitCodes[$index]; Output='' }
    }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @(& $EsExe -get-everything-version 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    [pscustomobject]@{ ExitCode=$exitCode; Output=(($output | ForEach-Object { [string]$_ }) -join "`n").Trim() }
}

function Resolve-EverythingApp {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Everything\Everything.exe'),
        (Join-Path $env:LOCALAPPDATA 'Everything\Everything.exe')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function Write-Result([object]$Result, [int]$ExitCode) {
    if ($AsJson) { $Result | ConvertTo-Json -Depth 4 }
    elseif (-not $Quiet) { $Result.GetEnumerator() | ForEach-Object { Write-Host ("{0} = {1}" -f $_.Key, $_.Value) } }
    if ($PassThru) { [pscustomobject]$Result }
    exit $ExitCode
}

$esExe = if ($SyntheticProbeExitCodes) { '<synthetic-es.exe>' } else { & $resolveCli | Select-Object -First 1 }
if (-not $esExe) { Write-Result ([ordered]@{ Status='ES_NOT_FOUND'; RootCause='ES_NOT_FOUND'; EsExe=$null; IpcFinal='FAILED'; UserActionRequired=$true }) 2 }

$initial = Test-Ipc $esExe
if ($initial.ExitCode -eq 0) {
    Write-Result ([ordered]@{ Status='READY'; RootCause='IPC_READY'; TransientRetryUsed='NO'; EsExe=$esExe; IpcInitial='READY'; IpcFinal='READY'; UserActionRequired=$false }) 0
}

if ($initial.ExitCode -eq 8) {
    Start-Sleep -Milliseconds 750
    $second = Test-Ipc $esExe
    if ($second.ExitCode -eq 0) {
        Write-Result ([ordered]@{ Status='READY'; RootCause='IPC_READY_AFTER_TRANSIENT_RETRY'; TransientRetryUsed='YES'; EsExe=$esExe; IpcInitial='ERROR_8'; IpcFinal='READY'; UserActionRequired=$false }) 0
    }
    if ($second.ExitCode -eq 8) {
        $diagnoseScript = Join-Path $PSScriptRoot 'Diagnose-EverythingIpc.ps1'
        $diagnosis = if ($SyntheticDiagnosisRootCause) { [pscustomobject]@{ ROOT_CAUSE=$SyntheticDiagnosisRootCause } } else { @(& $diagnoseScript -AsJson | ConvertFrom-Json)[0] }
        $cause = $diagnosis.ROOT_CAUSE
        if ($cause -eq 'INTERACTIVE_CLIENT_NOT_RUNNING' -and -not $SyntheticProbeExitCodes) {
            $everythingExe = Resolve-EverythingApp
            if ($everythingExe) {
                Start-Process -FilePath $everythingExe -WindowStyle Minimized
                for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
                    Start-Sleep -Seconds $RetryDelaySeconds
                    $final = Test-Ipc $esExe
                    if ($final.ExitCode -eq 0) {
                        Write-Result ([ordered]@{ Status='READY'; RootCause='IPC_READY'; TransientRetryUsed='YES'; EsExe=$esExe; IpcInitial='ERROR_8'; IpcFinal='READY'; UserActionRequired=$false }) 0
                    }
                }
            }
        }
        Write-Result ([ordered]@{ Status='NEED_USER_ACTION'; RootCause=$cause; TransientRetryUsed='YES'; EsExe=$esExe; IpcInitial='ERROR_8'; IpcFinal='FAILED'; UserActionRequired=$true }) 8
    }
    Write-Result ([ordered]@{ Status='ES_IPC_ERROR'; RootCause='IPC_ERROR8_UNCLASSIFIED'; TransientRetryUsed='YES'; EsExe=$esExe; IpcInitial='ERROR_8'; IpcFinal=("ERROR_" + $second.ExitCode); UserActionRequired=$true }) $second.ExitCode
}

Write-Result ([ordered]@{ Status='ES_IPC_ERROR'; RootCause='IPC_ERROR8_UNCLASSIFIED'; TransientRetryUsed='NO'; EsExe=$esExe; IpcInitial=("ERROR_" + $initial.ExitCode); IpcFinal=("ERROR_" + $initial.ExitCode); UserActionRequired=$true }) $initial.ExitCode
