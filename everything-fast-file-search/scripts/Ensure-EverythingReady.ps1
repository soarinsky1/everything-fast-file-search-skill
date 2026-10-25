[CmdletBinding()]
param(
    [ValidateRange(1,10)]
    [int]$RetryCount = 3,

    [ValidateRange(1,30)]
    [int]$RetryDelaySeconds = 2,

    [switch]$AsJson,
    [switch]$Quiet,
    [switch]$PassThru,

    [string]$EverythingCliPath,

    # Opt-in only: permits bounded recovery that may start Everything.exe.
    [switch]$AllowStart,

    # Test-only: provide probe outcomes without invoking es.exe.
    [int[]]$SyntheticProbeExitCodes,

    # Test-only: simulate a process-launch failure without starting es.exe.
    [ValidateRange(-1, 65535)]
    [int]$SyntheticLaunchErrorCode = -1,

    # Test-only: use after two synthetic Error 8 probes.
    [ValidateSet('', 'IPC_ELEVATION_MISMATCH', 'INTERACTIVE_CLIENT_NOT_RUNNING', 'IPC_ERROR8_UNCLASSIFIED')]
    [string]$SyntheticDiagnosisRootCause = '',

    # Test-only: avoid starting or depending on a live Everything process.
    [ValidateSet('', 'Running', 'NotRunning')]
    [string]$SyntheticEverythingProcessState = '',

    # Test-only: verify unavailable Session/elevation metadata is non-fatal.
    [switch]$SyntheticContextMetadataUnavailable,

    # Test-only: provide deterministic failure-context metadata without User32/token access.
    [ValidateSet('', 'Found', 'NotFound', 'Unavailable')]
    [string]$SyntheticIpcWindowState = '',

    [long]$SyntheticIpcWindowHwnd = 0,

    [int]$SyntheticIpcWindowPid = 0,

    [ValidateRange(-1,1)]
    [int]$SyntheticEverythingElevation = -1
)

$ErrorActionPreference = 'Stop'

function Write-Result([System.Collections.IDictionary]$Result) {
    $data = [ordered]@{}
    foreach ($key in $Result.Keys) { $data[$key] = $Result[$key] }
    # Keep v1.1.0 machine-readable properties while adding structured diagnostics.
    $data.RootCause = if ($Result.Contains('ROOT_CAUSE')) { $Result['ROOT_CAUSE'] } else { $Result['STATUS'] }
    $data.TransientRetryUsed = if ($Result.Contains('TRANSIENT_RETRY_USED')) { $Result['TRANSIENT_RETRY_USED'] } else { 'NO' }
    $data.EsExe = $Result['ES_EXE']
    $data.IpcInitial = $Result['EVERYTHING_IPC_INITIAL']
    $data.IpcFinal = $Result['EVERYTHING_IPC_FINAL']
    $data.UserActionRequired = ($Result['USER_ACTION_REQUIRED'] -eq 'YES')
    if ($AsJson) { $data | ConvertTo-Json -Depth 4 }
    elseif (-not $Quiet) { $Result.GetEnumerator() | ForEach-Object { Write-Host ("{0} = {1}" -f $_.Key, $_.Value) } }
    if ($PassThru) { [pscustomobject]$data }
}

function Resolve-EsExe {
    $resolveScript = Join-Path $PSScriptRoot 'Resolve-EverythingCli.ps1'
    try { return (& $resolveScript -EverythingCliPath $EverythingCliPath | Select-Object -First 1) } catch { }
    return $null
}

function Resolve-EverythingExe {

    $proc = Get-Process `
        -Name Everything `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($proc) {
        try {
            if ($proc.Path -and (Test-Path -LiteralPath $proc.Path)) {
                return $proc.Path
            }
        }
        catch {
        }
    }

    $cmd = Get-Command `
        Everything.exe `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return $cmd.Source
    }

    $registryPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\Everything.exe',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\Everything.exe',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\Everything.exe'
    )

    foreach ($regPath in $registryPaths) {

        try {

            if (Test-Path $regPath) {

                $value = (
                    Get-Item `
                        -Path $regPath `
                        -ErrorAction Stop
                ).GetValue('')

                if ($value -and (Test-Path -LiteralPath $value)) {
                    return $value
                }
            }
        }
        catch {
        }
    }

    $directCandidates = @(
        (Join-Path $env:ProgramFiles 'Everything\Everything.exe'),
        (Join-Path $env:LOCALAPPDATA 'Everything\Everything.exe')
    )

    if (${env:ProgramFiles(x86)}) {
        $directCandidates += (
            Join-Path ${env:ProgramFiles(x86)} 'Everything\Everything.exe'
        )
    }

    foreach ($candidate in $directCandidates) {

        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $wingetRoot = Join-Path `
        $env:LOCALAPPDATA `
        'Microsoft\WinGet\Packages'

    if (Test-Path -LiteralPath $wingetRoot) {

        $candidate = Get-ChildItem `
            -LiteralPath $wingetRoot `
            -Directory `
            -Filter 'voidtools.Everything*' `
            -ErrorAction SilentlyContinue |
            ForEach-Object {
                Get-ChildItem `
                    -LiteralPath $_.FullName `
                    -Filter 'Everything.exe' `
                    -File `
                    -Recurse `
                    -ErrorAction SilentlyContinue
            } |
            Select-Object -First 1

        if ($candidate) {
            return $candidate.FullName
        }
    }

    return $null
}

function Test-EverythingIpc {

    param(
        [Parameter(Mandatory)]
        [string]$EsExe
    )

    if ($SyntheticLaunchErrorCode -ge 0) {
        return [pscustomobject]@{ ExitCode=1; LaunchFailed=$true; Win32ErrorCode=$SyntheticLaunchErrorCode; Output='Synthetic process launch failure' }
    }
    if ($script:SyntheticProbeExitCodes.Count -gt 0) {
        $index = [Math]::Min($script:SyntheticProbeIndex, $script:SyntheticProbeExitCodes.Count - 1)
        $script:SyntheticProbeIndex++
        return [pscustomobject]@{ ExitCode = $script:SyntheticProbeExitCodes[$index]; Output = '' }
    }

    & (Join-Path $PSScriptRoot 'Invoke-EverythingCli.ps1') -EsExe $EsExe -NativeArguments @('-get-everything-version')
}

function Initialize-EverythingFailureContextNative {
    if ('EverythingFailureContextNativeV1' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public sealed class EverythingIpcWindowRecordV1
{
    public long Hwnd { get; set; }
    public int ProcessId { get; set; }
}

public static class EverythingFailureContextNativeV1
{
    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hwnd, StringBuilder className, int maxCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, uint processId);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetTokenInformation(IntPtr tokenHandle, int tokenInformationClass,
        out TokenElevation tokenInformation, int tokenInformationLength, out int returnLength);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenElevation { public int TokenIsElevated; }

    public static EverythingIpcWindowRecordV1[] FindEverythingIpcWindows()
    {
        List<EverythingIpcWindowRecordV1> matches = new List<EverythingIpcWindowRecordV1>();
        EnumWindows(delegate(IntPtr hwnd, IntPtr lParam)
        {
            StringBuilder className = new StringBuilder(256);
            if (GetClassName(hwnd, className, className.Capacity) > 0 &&
                className.ToString().StartsWith("EVERYTHING_TASKBAR_NOTIFICATION", StringComparison.OrdinalIgnoreCase))
            {
                uint processId;
                GetWindowThreadProcessId(hwnd, out processId);
                matches.Add(new EverythingIpcWindowRecordV1 { Hwnd = hwnd.ToInt64(), ProcessId = unchecked((int)processId) });
            }
            return true;
        }, IntPtr.Zero);
        return matches.ToArray();
    }

    // Returns 1 for elevated, 0 for non-elevated, and -1 when unavailable.
    public static int GetProcessElevation(int processId)
    {
        const uint ProcessQueryLimitedInformation = 0x1000;
        const uint TokenQuery = 0x0008;
        const int TokenElevationClass = 20;
        IntPtr processHandle = OpenProcess(ProcessQueryLimitedInformation, false, unchecked((uint)processId));
        if (processHandle == IntPtr.Zero) { return -1; }
        try
        {
            IntPtr tokenHandle;
            if (!OpenProcessToken(processHandle, TokenQuery, out tokenHandle)) { return -1; }
            try
            {
                TokenElevation elevation;
                int returnLength;
                if (!GetTokenInformation(tokenHandle, TokenElevationClass, out elevation,
                    Marshal.SizeOf(typeof(TokenElevation)), out returnLength)) { return -1; }
                return elevation.TokenIsElevated == 0 ? 0 : 1;
            }
            finally { CloseHandle(tokenHandle); }
        }
        finally { CloseHandle(processHandle); }
    }
}
'@
}

function Get-ReadinessError8Context {
    param([string]$FinalAction)

    $currentProcessId = 'UNKNOWN'
    $currentSessionId = 'UNKNOWN'
    $currentElevated = 'UNKNOWN'

    try {
        $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
        $currentProcessId = $currentProcess.Id
        if (-not $SyntheticContextMetadataUnavailable) {
            $currentSessionId = $currentProcess.SessionId
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            $currentElevated = if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { 'TRUE' } else { 'FALSE' }
        }
    }
    catch {}

    $everythingProcesses = @()
    if ($SyntheticEverythingProcessState -eq 'Running') {
        $everythingProcesses = @([pscustomobject]@{ Id = 0; SessionId = $null })
    }
    elseif ($SyntheticEverythingProcessState -ne 'NotRunning') {
        try { $everythingProcesses = @(Get-Process -Name Everything -ErrorAction SilentlyContinue) } catch {}
    }

    $everythingProcess = $null
    if ($everythingProcesses.Count -gt 0) {
        if (-not $SyntheticContextMetadataUnavailable -and $currentSessionId -ne 'UNKNOWN') {
            try { $everythingProcess = @($everythingProcesses | Where-Object { $_.SessionId -eq $currentSessionId } | Select-Object -First 1)[0] } catch {}
        }
        if (-not $everythingProcess) { $everythingProcess = $everythingProcesses[0] }
    }

    $everythingPid = $null
    $everythingSessionId = 'UNKNOWN'
    if ($everythingProcess) {
        try { $everythingPid = $everythingProcess.Id } catch {}
        if (-not $SyntheticContextMetadataUnavailable) {
            try { $everythingSessionId = $everythingProcess.SessionId } catch {}
        }
    }

    $everythingElevated = 'UNKNOWN'
    $ipcWindowFound = 'UNKNOWN'
    $ipcWindowHwnd = $null
    $ipcWindowOwningPid = $null
    $ipcWindowProcessMatch = 'UNKNOWN'

    if (-not $SyntheticContextMetadataUnavailable) {
        if ($SyntheticEverythingElevation -ge 0) {
            $everythingElevated = if ($SyntheticEverythingElevation -eq 1) { 'TRUE' } else { 'FALSE' }
        }
        elseif ($everythingPid -ne $null) {
            try {
                Initialize-EverythingFailureContextNative
                $elevationValue = [EverythingFailureContextNativeV1]::GetProcessElevation([int]$everythingPid)
                if ($elevationValue -eq 1) { $everythingElevated = 'TRUE' }
                elseif ($elevationValue -eq 0) { $everythingElevated = 'FALSE' }
            }
            catch {}
        }

        if ($SyntheticIpcWindowState -eq 'Found') {
            $ipcWindowFound = 'YES'
            $ipcWindowHwnd = $SyntheticIpcWindowHwnd
            $ipcWindowOwningPid = $SyntheticIpcWindowPid
        }
        elseif ($SyntheticIpcWindowState -eq 'NotFound') {
            $ipcWindowFound = 'NO'
        }
        elseif ($SyntheticIpcWindowState -ne 'Unavailable') {
            try {
                Initialize-EverythingFailureContextNative
                $ipcWindows = @([EverythingFailureContextNativeV1]::FindEverythingIpcWindows())
                $ipcWindow = $null
                if ($everythingPid -ne $null) {
                    $ipcWindow = $ipcWindows | Where-Object { $_.ProcessId -eq [int]$everythingPid } | Select-Object -First 1
                }
                if (-not $ipcWindow) { $ipcWindow = $ipcWindows | Select-Object -First 1 }
                if ($ipcWindow) {
                    $ipcWindowFound = 'YES'
                    $ipcWindowHwnd = $ipcWindow.Hwnd
                    $ipcWindowOwningPid = $ipcWindow.ProcessId
                }
                else { $ipcWindowFound = 'NO' }
            }
            catch {}
        }

        if ($ipcWindowFound -eq 'YES' -and $everythingPid -ne $null -and $ipcWindowOwningPid -ne $null) {
            $ipcWindowProcessMatch = if ([int]$ipcWindowOwningPid -eq [int]$everythingPid) { 'YES' } else { 'NO' }
        }
    }

    [ordered]@{
        EVENT = 'READINESS_ERROR8_CONTEXT'
        TIMESTAMP = (Get-Date).ToUniversalTime().ToString('o')
        EVERYTHING_PROCESS_PRESENT = if ($everythingProcess) { 'YES' } else { 'NO' }
        EVERYTHING_PID = $everythingPid
        EVERYTHING_SESSION_ID = $everythingSessionId
        EVERYTHING_ELEVATED = $everythingElevated
        IPC_WINDOW_FOUND = $ipcWindowFound
        IPC_WINDOW_HWND = $ipcWindowHwnd
        IPC_WINDOW_OWNING_PID = $ipcWindowOwningPid
        IPC_WINDOW_PROCESS_MATCH = $ipcWindowProcessMatch
        CURRENT_PROCESS_ID = $currentProcessId
        CURRENT_SESSION_ID = $currentSessionId
        CURRENT_ELEVATED = $currentElevated
        ES_EXE = $esExe
        INITIAL_IPC = 'ERROR_8'
        TRANSIENT_RETRY_USED = 'YES'
        RETRY_IPC = 'ERROR_8'
        ALLOW_START = if ($AllowStart) { 'TRUE' } else { 'FALSE' }
        AUTO_START_ATTEMPTED = 'NO'
        FINAL_ACTION = $FinalAction
    }
}

$esExe = Resolve-EsExe

if (-not $esExe) {

    $result = [ordered]@{
        STATUS                  = 'ES_NOT_FOUND'
        ES_EXE                  = $null
        EVERYTHING_EXE          = $null
        EVERYTHING_PROCESS      = 'UNKNOWN'
        EVERYTHING_IPC_INITIAL  = 'NOT_TESTED'
        AUTO_START_ATTEMPTED    = 'NO'
        EVERYTHING_IPC_FINAL    = 'FAILED'
        USER_ACTION_REQUIRED    = 'YES'
    }

    Write-Result $result

    exit 2
}

$script:SyntheticProbeExitCodes = @($SyntheticProbeExitCodes | Where-Object { $null -ne $_ })
$script:SyntheticProbeIndex = 0

$initial = Test-EverythingIpc -EsExe $esExe

if ($initial.LaunchFailed) {
    $result = [ordered]@{
        STATUS='ES_LAUNCH_FAILED'; ROOT_CAUSE='ES_LAUNCH_FAILED'; ES_EXE=$esExe
        ES_OUTPUT=$initial.Output; TRANSIENT_RETRY_USED='NO'
        EVERYTHING_IPC_INITIAL='NOT_TESTED'; EVERYTHING_IPC_FINAL='FAILED'
        AUTO_START_ATTEMPTED='NO'; USER_ACTION_REQUIRED='YES'
        WIN32_ERROR_CODE=$initial.Win32ErrorCode
        WIN32_ERROR_NAME=$(switch ($initial.Win32ErrorCode) { 5 { 'ERROR_ACCESS_DENIED' } 623 { 'ERROR_ILLEGAL_DLL_RELOCATION' } default { 'OTHER_LAUNCH_ERROR' } })
        NEXT_ACTION=$(if ($initial.Win32ErrorCode -in @(5, 623)) { 'REQUEST_HOST_EXECUTION_APPROVAL_IF_SANDBOXED' } else { 'INSPECT_LAUNCH_ERROR' })
    }
    Write-Result $result
    if (-not $AsJson) {
        Write-Output (([ordered]@{ EVENT='ES_LAUNCH_FAILURE_CONTEXT'; ES_EXE=$esExe; WIN32_ERROR_CODE=$result.WIN32_ERROR_CODE; WIN32_ERROR_NAME=$result.WIN32_ERROR_NAME; NEXT_ACTION=$result.NEXT_ACTION; AUTOMATIC_HOST_EXECUTION='NO' }) | ConvertTo-Json -Compress)
    }
    exit 1
}

$diagnosis = $null
if ($initial.ExitCode -eq 8) {
    Start-Sleep -Milliseconds 750
    $transientRetry = Test-EverythingIpc -EsExe $esExe

    if ($transientRetry.ExitCode -eq 0) {
        $result = [ordered]@{
            STATUS                  = 'READY'
            ROOT_CAUSE              = 'IPC_READY_AFTER_TRANSIENT_RETRY'
            TRANSIENT_RETRY_USED    = 'YES'
            ES_EXE                  = $esExe
            EVERYTHING_EXE          = Resolve-EverythingExe
            EVERYTHING_PROCESS      = 'UNKNOWN'
            EVERYTHING_IPC_INITIAL  = 'ERROR_8'
            AUTO_START_ATTEMPTED    = 'NO'
            EVERYTHING_IPC_FINAL    = 'READY'
            USER_ACTION_REQUIRED    = 'NO'
        }

        Write-Result $result
        exit 0
    }

    $initial = $transientRetry
    if ($transientRetry.ExitCode -eq 8) {
        $contextFinalAction = if ($AllowStart) { 'CONTINUE_ALLOWSTART_RECOVERY' } else { 'FAIL_CLOSED' }
        $readinessError8Context = Get-ReadinessError8Context -FinalAction $contextFinalAction
        Write-Output ($readinessError8Context | ConvertTo-Json -Compress -Depth 3)
    }

    if (-not $AllowStart) {
        $result = [ordered]@{
            STATUS                  = 'UNAVAILABLE'
            ROOT_CAUSE              = 'IPC_UNAVAILABLE'
            TRANSIENT_RETRY_USED    = 'YES'
            ES_EXE                  = $esExe
            EVERYTHING_EXE          = $null
            EVERYTHING_PROCESS      = 'NOT_CHECKED'
            EVERYTHING_IPC_INITIAL  = 'ERROR_8'
            AUTO_START_ATTEMPTED    = 'NO'
            EVERYTHING_IPC_FINAL    = 'FAILED'
            USER_ACTION_REQUIRED    = 'YES'
        }

        Write-Result $result
        exit 8
    }

    $diagnoseScript = Join-Path $PSScriptRoot 'Diagnose-EverythingIpc.ps1'
    if ($SyntheticDiagnosisRootCause) {
        $diagnosis = [pscustomobject]@{
            ROOT_CAUSE = $SyntheticDiagnosisRootCause
            EVERYTHING_EXE = (Join-Path $env:ProgramFiles 'Everything\Everything.exe')
        }
    }
    elseif (Test-Path -LiteralPath $diagnoseScript -PathType Leaf) {
        try {
            $diagnosis = @(& $diagnoseScript -AsJson -EverythingCliPath $esExe | ConvertFrom-Json)[0]
        }
        catch {
            $diagnosis = $null
        }
    }

    if ($diagnosis -and $diagnosis.ROOT_CAUSE -eq 'IPC_ELEVATION_MISMATCH') {
        $result = [ordered]@{
            STATUS                  = 'NEED_USER_ACTION'
            ROOT_CAUSE              = 'IPC_ELEVATION_MISMATCH'
            TRANSIENT_RETRY_USED    = 'YES'
            ES_EXE                  = $esExe
            EVERYTHING_EXE          = $diagnosis.EVERYTHING_EXE
            EVERYTHING_PROCESS      = 'RUNNING'
            EVERYTHING_IPC_INITIAL  = 'ERROR_8'
            AUTO_START_ATTEMPTED    = 'NO'
            EVERYTHING_IPC_FINAL    = 'FAILED'
            USER_ACTION_REQUIRED    = 'YES'
        }

        Write-Result $result
        exit 8
    }
}

$initialState = if ($initial.ExitCode -eq 0) {
    'READY'
}
elseif ($initial.ExitCode -eq 8) {
    'ERROR_8'
}
else {
    "ERROR_$($initial.ExitCode)"
}

$everythingProcess = Get-Process `
    -Name Everything `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if ($SyntheticEverythingProcessState -eq 'Running') {
    $everythingProcess = [pscustomobject]@{ Id = 0 }
}
elseif ($SyntheticEverythingProcessState -eq 'NotRunning') {
    $everythingProcess = $null
}

if ($diagnosis -and $diagnosis.ROOT_CAUSE -eq 'INTERACTIVE_CLIENT_NOT_RUNNING') {
    $everythingProcess = $null
}

$everythingExe = Resolve-EverythingExe

$autoStartAttempted = 'NO'

if ($initial.ExitCode -eq 0) {

    $result = [ordered]@{
        STATUS                  = 'READY'
        ROOT_CAUSE              = 'IPC_READY'
        TRANSIENT_RETRY_USED    = 'NO'
        ES_EXE                  = $esExe
        EVERYTHING_EXE          = $everythingExe
        EVERYTHING_PROCESS      = if ($everythingProcess) {'RUNNING'} else {'UNKNOWN'}
        EVERYTHING_IPC_INITIAL  = 'READY'
        AUTO_START_ATTEMPTED    = 'NO'
        EVERYTHING_IPC_FINAL    = 'READY'
        USER_ACTION_REQUIRED    = 'NO'
    }

    Write-Result $result

    exit 0
}

if ($initial.ExitCode -eq 8) {

    if (-not $everythingProcess) {

        if (-not $everythingExe) {

            $result = [ordered]@{
                STATUS                  = 'EVERYTHING_EXE_NOT_FOUND'
                ES_EXE                  = $esExe
                EVERYTHING_EXE          = $null
                EVERYTHING_PROCESS      = 'NOT_RUNNING'
                EVERYTHING_IPC_INITIAL  = 'ERROR_8'
                AUTO_START_ATTEMPTED    = 'NO'
                EVERYTHING_IPC_FINAL    = 'FAILED'
                USER_ACTION_REQUIRED    = 'YES'
            }

            Write-Result $result

            exit 3
        }

        Write-Host "Everything IPC unavailable; starting Everything:"
        Write-Host $everythingExe

        Start-Process `
            -FilePath $everythingExe `
            -WindowStyle Minimized

        $autoStartAttempted = 'YES'
    }
    else {
        Write-Host "Everything process already running; IPC not ready."
        Write-Host "Process will NOT be terminated or restarted."
    }

    $final = $null

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {

        Start-Sleep -Seconds $RetryDelaySeconds

        $final = Test-EverythingIpc -EsExe $esExe

        if ($final.ExitCode -eq 0) {
            break
        }

        Write-Host (
            "IPC retry {0}/{1}: exit code {2}" -f
            $attempt,
            $RetryCount,
            $final.ExitCode
        )
    }

    if ($final -and $final.ExitCode -eq 0) {

            $result = [ordered]@{
                STATUS                  = 'READY'
                ROOT_CAUSE              = 'IPC_READY'
                TRANSIENT_RETRY_USED    = 'YES'
                ES_EXE                  = $esExe
            EVERYTHING_EXE          = $everythingExe
            EVERYTHING_PROCESS      = 'RUNNING'
            EVERYTHING_IPC_INITIAL  = 'ERROR_8'
            AUTO_START_ATTEMPTED    = $autoStartAttempted
            EVERYTHING_IPC_FINAL    = 'READY'
            USER_ACTION_REQUIRED    = 'NO'
        }

        Write-Result $result

        exit 0
    }

    $result = [ordered]@{
        STATUS                  = 'NEED_USER_ACTION'
        ROOT_CAUSE              = if ($diagnosis) { $diagnosis.ROOT_CAUSE } else { 'IPC_ERROR8_UNCLASSIFIED' }
        TRANSIENT_RETRY_USED    = 'YES'
        ES_EXE                  = $esExe
        EVERYTHING_EXE          = $everythingExe
        EVERYTHING_PROCESS      = if (
            Get-Process `
                -Name Everything `
                -ErrorAction SilentlyContinue
        ) {'RUNNING'} else {'NOT_RUNNING'}
        EVERYTHING_IPC_INITIAL  = 'ERROR_8'
        AUTO_START_ATTEMPTED    = $autoStartAttempted
        EVERYTHING_IPC_FINAL    = 'FAILED'
        USER_ACTION_REQUIRED    = 'YES'
    }

    Write-Result $result

    exit 8
}

$result = [ordered]@{
    STATUS                  = 'ES_IPC_ERROR'
    ROOT_CAUSE              = 'IPC_ERROR8_UNCLASSIFIED'
    TRANSIENT_RETRY_USED    = 'NO'
    ES_EXE                  = $esExe
    EVERYTHING_EXE          = $everythingExe
    EVERYTHING_PROCESS      = if ($everythingProcess) {'RUNNING'} else {'UNKNOWN'}
    EVERYTHING_IPC_INITIAL  = $initialState
    AUTO_START_ATTEMPTED    = 'NO'
    EVERYTHING_IPC_FINAL    = 'FAILED'
    USER_ACTION_REQUIRED    = 'YES'
}

Write-Result $result
if (-not $AsJson -and -not $Quiet) {
    if ($initial.Output) {
        Write-Host ""
        Write-Host "ES output:"
        Write-Host $initial.Output
    }
}

exit 4
