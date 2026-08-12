[CmdletBinding()]
param(
    [switch]$AsJson,
    [ValidateRange(-1, 255)] [int]$SyntheticEsExitCode = -1,
    [ValidateSet('Auto', 'Running', 'NotRunning')] [string]$SyntheticInteractiveClientState = 'Auto',
    [ValidateRange(-1, 1)] [int]$SyntheticRunAsAdmin = -1,
    [AllowEmptyString()] [string]$SyntheticInstanceName
)

$ErrorActionPreference = 'Stop'

function Get-IniSetting([string]$Name) {
    foreach ($path in @((Join-Path $env:APPDATA 'Everything\Everything.ini'), (Join-Path $env:ProgramFiles 'Everything\Everything.ini'))) {
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

$resolveCli = Join-Path $PSScriptRoot 'Resolve-EverythingCli.ps1'
$esExe = if ($SyntheticEsExitCode -ge 0) { '<synthetic-es.exe>' } else { & $resolveCli | Select-Object -First 1 }
if (-not $esExe) {
    Write-Result ([ordered]@{ ROOT_CAUSE='ES_NOT_FOUND'; RETRY_RECOMMENDED='NO'; USER_ACTION_REQUIRED='YES'; ES_EXIT_CODE=$null; ES_EXE=$null })
    exit 2
}

$esOutput = ''
$exitCode = $SyntheticEsExitCode
if ($exitCode -lt 0) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @(& $esExe -get-everything-version 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    $esOutput = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
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
if ($SyntheticInteractiveClientState -eq 'Auto') {
    $processes = @(Get-Process -Name Everything -ErrorAction SilentlyContinue)
    $interactivePresent = @($processes | Where-Object { $_.SessionId -eq $currentSession }).Count -gt 0
} else {
    $processes = @()
    $interactivePresent = $SyntheticInteractiveClientState -eq 'Running'
}

$runAsAdmin = if ($SyntheticRunAsAdmin -ge 0) { [string]$SyntheticRunAsAdmin } else { Get-IniSetting 'run_as_admin' }
$instanceName = if ($PSBoundParameters.ContainsKey('SyntheticInstanceName')) { $SyntheticInstanceName } else { Get-IniSetting 'instance_name' }
if ($interactivePresent -and $runAsAdmin -eq '1' -and [string]::IsNullOrWhiteSpace($instanceName)) {
    $cause = 'IPC_ELEVATION_MISMATCH'; $retry = 'NO'; $action = 'YES'
} elseif (-not $interactivePresent) {
    $cause = 'INTERACTIVE_CLIENT_NOT_RUNNING'; $retry = 'YES'; $action = 'NO'
} else {
    $cause = 'IPC_ERROR8_UNCLASSIFIED'; $retry = 'YES'; $action = 'YES'
}

Write-Result ([ordered]@{
    ROOT_CAUSE=$cause; RETRY_RECOMMENDED=$retry; USER_ACTION_REQUIRED=$action; ES_EXIT_CODE=8; ES_EXE=$esExe; ES_OUTPUT=$esOutput
    CURRENT_SESSION_ID=$currentSession; INTERACTIVE_CLIENT_PRESENT=if($interactivePresent){'YES'}else{'NO'}; EVERYTHING_PROCESS_COUNT=$processes.Count
    RUN_AS_ADMIN=$runAsAdmin; INSTANCE_NAME=$instanceName
})
exit 8
