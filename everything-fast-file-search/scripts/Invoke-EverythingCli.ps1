[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$EsExe,
    [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$NativeArguments,
    [switch]$Utf8Output
)

$ErrorActionPreference = 'Stop'

# Windows CRT quoting, one quoted native argument per input array element.
# ProcessStartInfo.ArgumentList is unavailable in Windows PowerShell 5.1.
function Quote-NativeArgument([AllowEmptyString()][string]$Value) {
    # ES also parses search syntax from the command line: leave simple tokens
    # (especially ext: filters and switches) unquoted, as native PowerShell does.
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', { param($m) $m.Groups[1].Value + $m.Groups[1].Value + '\"' })
    $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Value + $m.Value })
    return '"' + $escaped + '"'
}

$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $EsExe
$info.WorkingDirectory = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path
$info.Arguments = (@($NativeArguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' ')
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
if ($Utf8Output) {
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
}
$process = New-Object Diagnostics.Process
$process.StartInfo = $info
try {
    try {
        if (-not $process.Start()) { throw 'Process.Start returned false.' }
    }
    catch {
        # No native exit exists. Use a non-8 failure, never a stale LASTEXITCODE.
        $nativeErrorCode = $null
        $exception = $_.Exception
        while ($null -ne $exception) {
            if ($exception -is [ComponentModel.Win32Exception]) { $nativeErrorCode = $exception.NativeErrorCode; break }
            $exception = $exception.InnerException
        }
        return [pscustomobject]@{ ExitCode=1; LaunchFailed=$true; Win32ErrorCode=$nativeErrorCode; StdOut=''; StdErr=$_.Exception.Message; Output=('ES_LAUNCH_FAILED: ' + $_.Exception.Message) }
    }
    # Drain both pipes concurrently to avoid stdout/stderr buffer deadlocks.
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        LaunchFailed = $false
        StdOut = $stdout
        StdErr = $stderr
        Output = (@($stdout.TrimEnd(), $stderr.TrimEnd()) | Where-Object { $_ }) -join "`n"
    }
}
finally { $process.Dispose() }
