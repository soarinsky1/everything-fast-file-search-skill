[CmdletBinding()]
param(
    [switch]$AsJson,

    [string]$EverythingCliPath,

    [ValidateRange(-1, 255)]
    [int]$SyntheticEsExitCode = -1,

    [ValidateSet('Auto', 'Running', 'NotRunning')]
    [string]$SyntheticInteractiveClientState = 'Auto',

    [ValidateRange(-1, 1)]
    [int]$SyntheticRunAsAdmin = -1,

    [AllowEmptyString()]
    [string]$SyntheticInstanceName
)

$ErrorActionPreference = 'Stop'

function Resolve-EsExe {
    $resolveScript = Join-Path $PSScriptRoot 'Resolve-EverythingCli.ps1'
    if (Test-Path -LiteralPath $resolveScript -PathType Leaf) {
        try { return (& $resolveScript -EverythingCliPath $EverythingCliPath | Select-Object -First 1) } catch { }
    }
    return $null
}

function Get-IniSetting([string]$Name) {
    $candidates = @(
        (Join-Path $env:APPDATA 'Everything\Everything.ini'),
        (Join-Path $env:ProgramFiles 'Everything\Everything.ini')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $match = Select-String -LiteralPath $path -Pattern ("(?m)^" + [regex]::Escape($Name) + "=(.*)$") | Select-Object -First 1
            if ($match) { return $match.Matches[0].Groups[1].Value.Trim() }
        }
    }
    return $null
}

function Write-Result([object]$Result) {
    if ($AsJson) { $Result | ConvertTo-Json -Depth 4 }
    else { $Result.GetEnumerator() | ForEach-Object { Write-Host ("{0} = {1}" -f $_.Key, $_.Value) } }
}

$esExe = Resolve-EsExe
$esOutput = ''
$exitCode = $SyntheticEsExitCode

if ($exitCode -lt 0) {
    if (-not $esExe) {
        Write-Result ([ordered]@{ ROOT_CAUSE='ES_NOT_FOUND'; RETRY_RECOMMENDED='NO'; USER_ACTION_REQUIRED='YES'; ES_EXIT_CODE=$null; ES_EXE=$null })
        exit 2
    }
    $nativeResult = & (Join-Path $PSScriptRoot 'Invoke-EverythingCli.ps1') -EsExe $esExe -NativeArguments @('-get-everything-version')
    if ($nativeResult.LaunchFailed) {
        Write-Result ([ordered]@{ ROOT_CAUSE='ES_LAUNCH_FAILED'; RETRY_RECOMMENDED='NO'; USER_ACTION_REQUIRED='YES'; ES_EXIT_CODE=$null; ES_EXE=$esExe; ES_OUTPUT=$nativeResult.Output })
        exit 1
    }
    $exitCode = $nativeResult.ExitCode
    $esOutput = $nativeResult.Output.Trim()
}

if ($exitCode -eq 0) {
    Write-Result ([ordered]@{ ROOT_CAUSE='IPC_READY'; RETRY_RECOMMENDED='NO'; USER_ACTION_REQUIRED='NO'; ES_EXIT_CODE=0; ES_EXE=$esExe; ES_OUTPUT=$esOutput })
    exit 0
}

if ($exitCode -ne 8) {
    Write-Result ([ordered]@{ ROOT_CAUSE='IPC_ERROR8_UNCLASSIFIED'; RETRY_RECOMMENDED='YES'; USER_ACTION_REQUIRED='YES'; ES_EXIT_CODE=$exitCode; ES_EXE=$esExe; ES_OUTPUT=$esOutput })
    exit $exitCode
}

$currentSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
$processes = @()
if ($SyntheticInteractiveClientState -eq 'Auto') {
    $processes = @(Get-Process -Name Everything -ErrorAction SilentlyContinue)
    $interactiveClientPresent = @($processes | Where-Object { $_.SessionId -eq $currentSession }).Count -gt 0
}
else {
    $interactiveClientPresent = $SyntheticInteractiveClientState -eq 'Running'
}

$runAsAdmin = if ($SyntheticRunAsAdmin -ge 0) { [string]$SyntheticRunAsAdmin } else { Get-IniSetting 'run_as_admin' }
$instanceName = if ($PSBoundParameters.ContainsKey('SyntheticInstanceName')) { $SyntheticInstanceName } else { Get-IniSetting 'instance_name' }
$everythingExe = Join-Path $env:ProgramFiles 'Everything\Everything.exe'

if ($interactiveClientPresent -and $runAsAdmin -eq '1' -and [string]::IsNullOrWhiteSpace($instanceName)) {
    $rootCause = 'IPC_ELEVATION_MISMATCH'; $retry = 'NO'; $action = 'YES'
}
elseif (-not $interactiveClientPresent) {
    $rootCause = 'INTERACTIVE_CLIENT_NOT_RUNNING'; $retry = 'YES'; $action = 'NO'
}
else {
    $rootCause = 'IPC_ERROR8_UNCLASSIFIED'; $retry = 'YES'; $action = 'YES'
}

Write-Result ([ordered]@{
    ROOT_CAUSE = $rootCause
    RETRY_RECOMMENDED = $retry
    USER_ACTION_REQUIRED = $action
    ES_EXIT_CODE = 8
    ES_EXE = $esExe
    ES_OUTPUT = $esOutput
    CURRENT_SESSION_ID = $currentSession
    INTERACTIVE_CLIENT_PRESENT = if ($interactiveClientPresent) {'YES'} else {'NO'}
    EVERYTHING_PROCESS_COUNT = $processes.Count
    EVERYTHING_EXE = $everythingExe
    RUN_AS_ADMIN = $runAsAdmin
    INSTANCE_NAME = $instanceName
})

exit 8
