[CmdletBinding()]
param([string]$SearchPowerShellExe, [switch]$RunCases, [string]$Fixture)
$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
if ($RunCases) {
    $invoke = Join-Path $skillRoot 'scripts\Invoke-EverythingCli.ps1'
    $fake = Join-Path $Fixture 'fake.exe'
    $invalid = Join-Path $Fixture 'invalid.exe'
    $encodingBefore = [Console]::OutputEncoding.CodePage
    $terms = @('space token', 'ext:txt;md', '', 'C:\path with space\', 'literal"quote', '\\server\path\', 'a\\"b', '.*[0-9]+$', ([string][char]0x4e2d + [char]0x6587))
    $result = & $invoke -EsExe $fake -NativeArguments $terms -Utf8Output
    $lines = @($result.StdOut.TrimEnd() -split '\r?\n')
    if ($result.LaunchFailed -or $result.ExitCode -ne 0 -or $lines.Count -ne $terms.Count) { throw 'Argument capture failed.' }
    for ($i=0; $i -lt $terms.Count; $i++) {
        $value = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($lines[$i].Substring(1)))
        if ($value -cne $terms[$i]) { throw "Argument $i changed: $value" }
    }
    if ([Console]::OutputEncoding.CodePage -ne $encodingBefore) { throw 'Caller encoding changed.' }
    Write-Output 'INDEPENDENT_NATIVE_ARGUMENTS_AND_UNICODE=PASS'
    $rawCommand = & $invoke -EsExe $fake -NativeArguments @('--raw','-n','5','ext:pdf','space token') -Utf8Output
    if ($rawCommand.StdOut -match '"ext:pdf"|"-n"' -or $rawCommand.StdOut -notmatch '"space token"') { throw 'ES simple tokens must stay unquoted; spaces must be quoted.' }
    Write-Output 'ES_SIMPLE_TOKEN_QUOTING=PASS'
    $result = & $invoke -EsExe $fake -NativeArguments @('--streams') -Utf8Output
    if ($result.ExitCode -ne 8 -or $result.StdOut.Length -ne 90000 -or $result.StdErr.Length -ne 90000) { throw 'Pipe capture or native exit code lost.' }
    Write-Output 'REDIRECTED_STDOUT_STDERR_AND_EXIT8=PASS'
    $global:LASTEXITCODE = 0
    $failed = & $invoke -EsExe $invalid -NativeArguments @('-get-everything-version')
    if (-not $failed.LaunchFailed -or $failed.ExitCode -eq 0 -or $failed.ExitCode -eq 8) { throw 'Launch failure reported as a native success/Error8.' }
    $global:LASTEXITCODE = 0
    $ready = & (Join-Path $skillRoot 'scripts\Ensure-EverythingReady.ps1') -EverythingCliPath $invalid -AsJson | ConvertFrom-Json
    if ($LASTEXITCODE -ne 1 -or $ready.STATUS -ne 'ES_LAUNCH_FAILED' -or $ready.TRANSIENT_RETRY_USED -ne 'NO' -or $ready.AUTO_START_ATTEMPTED -ne 'NO') { throw 'Readiness accepted stale exit code or retried startup failure.' }
    if ($ready.WIN32_ERROR_CODE -ne $failed.Win32ErrorCode -or $ready.NEXT_ACTION -ne 'INSPECT_LAUNCH_ERROR') { throw 'Non-permission launch failure must not request host approval.' }
    $wrapperLines = @(& (Join-Path $skillRoot 'scripts\Search-Everything.ps1') -EverythingCliPath $invalid -Query generic -Root $Fixture -ItemType File -MaxResults 1 6>$null)
    if ($LASTEXITCODE -ne 1) { throw 'Wrapper lost the readiness exit code.' }
    $event = @($wrapperLines | Where-Object { $_ -is [string] -and $_ -match '^\{"EVENT":"ES_LAUNCH_FAILURE_CONTEXT"' })
    if ($event.Count -ne 1) { throw 'Expected one stdout launch-failure event.' }
    $context = $event[0] | ConvertFrom-Json
    if ($context.NEXT_ACTION -ne 'INSPECT_LAUNCH_ERROR' -or $context.AUTOMATIC_HOST_EXECUTION -ne 'NO') { throw 'Unexpected launch-failure routing.' }
    Write-Output 'WRAPPER_LAUNCH_FAILURE_STDOUT_AND_EXIT_CODE=PASS'
    $diag = & (Join-Path $skillRoot 'scripts\Diagnose-EverythingIpc.ps1') -EverythingCliPath $invalid -AsJson | ConvertFrom-Json
    if ($LASTEXITCODE -ne 1 -or $diag.ROOT_CAUSE -ne 'ES_LAUNCH_FAILED' -or $diag.RETRY_RECOMMENDED -ne 'NO') { throw 'Diagnosis accepted a launch failure.' }
    & (Join-Path $skillRoot 'scripts\Search-Everything.Core.R1.ps1') -EverythingCliPath $invalid -Query generic -ReportNativeExitCode
    if ($global:EverythingSearchCoreNativeExitCode -ne 1 -or $global:EverythingSearchCoreNativeResult.Output -notmatch 'ES_LAUNCH_FAILED') { throw 'Search lost launch failure.' }
    Write-Output 'LAUNCH_FAILURE_NOT_READY_NO_RETRY=PASS'
    Write-Output 'CLI_TRANSPORT_REGRESSION=PASS'
    exit 0
}

$Fixture = Join-Path ([IO.Path]::GetTempPath()) ('everything-transport-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $Fixture
try {
    $null = New-Item -ItemType File -Path (Join-Path $Fixture 'invalid.exe')
    Add-Type -OutputType ConsoleApplication -OutputAssembly (Join-Path $Fixture 'fake.exe') -TypeDefinition @'
using System;
using System.Text;
public static class TransportFixture {
    public static int Main(string[] args) {
        if (args.Length > 0 && args[0] == "--raw") { Console.WriteLine(Environment.CommandLine); return 0; }
        if (args.Length == 1 && args[0] == "--streams") {
            Console.Out.Write(new string('O',90000));
            Console.Error.Write(new string('E',90000));
            return 8;
        }
        foreach (string arg in args) Console.WriteLine("=" + Convert.ToBase64String(Encoding.UTF8.GetBytes(arg)));
        return 0;
    }
}
'@
    $shell = if ($SearchPowerShellExe) { $SearchPowerShellExe } else { Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe' }
    & $shell -NoProfile -File $PSCommandPath -RunCases -Fixture $Fixture
    if ($LASTEXITCODE -ne 0) { throw 'Transport regression failed.' }
}
finally {
    $resolved = [IO.Path]::GetFullPath($Fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -like 'everything-transport-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
