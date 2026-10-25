[CmdletBinding()]
param([string]$SearchPowerShellExe)

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
# Keep the nested official package fixture below Windows PowerShell's path limit,
# including when a sandbox supplies an unusually long TEMP directory.
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('efs-cli-' + [guid]::NewGuid().ToString('N').Substring(0,12))
$null = New-Item -ItemType Directory -Path $fixture
$shellExe = if ($SearchPowerShellExe) { $SearchPowerShellExe } else { Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe' }
try {
    $localApp = Join-Path $fixture 'local'
    $package = Join-Path $localApp 'Microsoft\WinGet\Packages\voidtools.Everything.Cli_fixture'
    $null = New-Item -ItemType Directory -Path $package -Force
    $fakeEs = Join-Path $package 'es.exe'
    $overrideEs = Join-Path $fixture 'override.exe'
    $resultFile = Join-Path $fixture 'resolution_fixture.txt'
    $null = New-Item -ItemType File -Path $resultFile
    Add-Type -OutputAssembly $fakeEs -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;
public static class ResolutionFixture {
    public static int Main(string[] args) {
        File.AppendAllText(Environment.GetEnvironmentVariable("CLI_TEST_LOG"),
            Assembly.GetExecutingAssembly().Location + "|" + string.Join("\t", args) + Environment.NewLine);
        Console.WriteLine(Array.IndexOf(args, "-get-everything-version") >= 0 ? "1.4.1.1032" : Environment.GetEnvironmentVariable("CLI_TEST_RESULT"));
        return 0;
    }
}
'@
    Copy-Item -LiteralPath $fakeEs -Destination $overrideEs
    $officialLocal = Join-Path $fixture 'official-local'
    $officialPackage = Join-Path $officialLocal 'Microsoft\WinGet\Packages\voidtools.Everything.Cli_Microsoft.Winget.Source_8wekyb3d8bbwe'
    $null = New-Item -ItemType Directory -Path $officialPackage -Force
    $officialEs = Join-Path $officialPackage 'es.exe'
    Copy-Item -LiteralPath $fakeEs -Destination $officialEs

    function Invoke-Isolated([string]$Code, [string]$LocalRoot, [string]$PathValue = '') {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $shellExe
        $info.Arguments = '-NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.EnvironmentVariables['PATH'] = $PathValue
        $info.EnvironmentVariables['LOCALAPPDATA'] = $LocalRoot
        $info.EnvironmentVariables['ProgramFiles'] = $fixture
        $info.EnvironmentVariables['ProgramFiles(x86)'] = $fixture
        $info.EnvironmentVariables['CLI_TEST_LOG'] = (Join-Path $fixture 'calls.txt')
        $info.EnvironmentVariables['CLI_TEST_RESULT'] = $resultFile
        $process = [Diagnostics.Process]::Start($info)
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $outTask.Result; Error = $errTask.Result }
        $process.Dispose()
        return $result
    }
    function Quote([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
    $resolver = Quote (Join-Path $skillRoot 'scripts\Resolve-EverythingCli.ps1')
    $search = Quote (Join-Path $skillRoot 'scripts\Search-Everything.ps1')
    $diagnose = Quote (Join-Path $skillRoot 'scripts\Diagnose-EverythingIpc.ps1')
    $ensure = Quote (Join-Path $skillRoot 'scripts\Ensure-EverythingReady.ps1')
    foreach ($case in @(
        @{ Name='EMPTY_PATH_WINGET'; Path=''; Local=$localApp; Expected=$fakeEs; Extra='' },
        @{ Name='EMPTY_PATH_OFFICIAL_PACKAGE'; Path=''; Local=$officialLocal; Expected=$officialEs; Extra='' },
        @{ Name='EXPLICIT_PATH_PRIORITY'; Path=$package; Local=$localApp; Expected=$overrideEs; Extra=(' -EverythingCliPath ' + (Quote $overrideEs)) },
        @{ Name='PATH_ONLY'; Path=$package; Local=$fixture; Expected=$fakeEs; Extra='' }
    )) {
        $code = '& ' + $resolver + $case.Extra
        $result = Invoke-Isolated $code $case.Local $case.Path
        if ($result.ExitCode -ne 0 -or $result.Output.Trim() -cne $case.Expected) { throw "$($case.Name): $($result.Output) $($result.Error)" }
        Write-Output ($case.Name + '=PASS')
    }
    $missing = Invoke-Isolated ('try { & ' + $resolver + '; exit 0 } catch { exit 2 }') $fixture
    if ($missing.ExitCode -ne 2) { throw 'Missing CLI must fail without invoking a search.' }
    Write-Output 'MISSING_CLI_FAIL_CLOSED=PASS'

    foreach ($expected in @($fakeEs, $overrideEs)) {
        $extra = if ($expected -eq $overrideEs) { ' -EverythingCliPath ' + (Quote $expected) } else { '' }
        $log = Join-Path $fixture 'calls.txt'
        if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log }
        # Actual native calls go to the fake executable, never the live Everything CLI.
        $code = '$ProgressPreference="SilentlyContinue"; & ' + $search + ' -Query resolution_fixture -Root ' + (Quote $fixture) + ' -Extensions txt -ItemType File -MaxResults 1' + $extra + '; exit $LASTEXITCODE'
        $result = Invoke-Isolated $code $localApp
        if ($result.ExitCode -ne 0 -or $result.Output -notmatch 'STATUS=FOUND RESULTS=1' -or $result.Output -notmatch 'SEARCH_RETRY_COUNT=0') { throw "Wrapper failed: $($result.Output) $($result.Error)" }
        $calls = @(Get-Content -LiteralPath $log)
        if ($calls.Count -ne 2 -or $calls[0] -notlike '*|-get-everything-version' -or $calls[1] -notlike '*resolution_fixture*ext:txt*') { throw ('Expected exactly one readiness probe and one search: ' + ($calls -join ' ; ')) }
        foreach ($call in $calls) { if (($call -split '\|',2)[0] -cne $expected) { throw 'Readiness and search used different CLI paths.' } }
        foreach ($entry in @($ensure, $diagnose)) {
            $result = Invoke-Isolated ('& ' + $entry + ' -AsJson' + $extra + '; exit $LASTEXITCODE') $localApp
            if ($result.ExitCode -ne 0) { throw "Standalone entry failed: $($result.Error)" }
            $json = $result.Output | ConvertFrom-Json
            if ($json.ES_EXE -cne $expected) { throw 'Standalone entry resolved a different CLI.' }
        }
        Write-Output ('SAME_CLI_WRAPPER_AND_STANDALONE_' + $(if ($extra) { 'EXPLICIT' } else { 'WINGET' }) + '=PASS')
    }
    Write-Output 'CLI_RESOLUTION_REGRESSION=PASS'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -like 'efs-cli-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
