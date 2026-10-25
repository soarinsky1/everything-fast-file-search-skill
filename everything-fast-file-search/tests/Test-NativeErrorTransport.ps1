[CmdletBinding()]
param([string]$SearchPowerShellExe)

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$searchScript = Join-Path $skillRoot 'scripts\Search-Everything.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('everything-native-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$fakeEs = Join-Path $fixture 'fake-es.exe'
$attemptLog = Join-Path $fixture 'attempts.txt'
$unicodeDirectory = Join-Path $fixture ([string][char]0x4e2d + [char]0x6587)
$null = New-Item -ItemType Directory -Path $unicodeDirectory
$unicodeFile = Join-Path $unicodeDirectory ('Unicode document ' + [char]0x6d4b + [char]0x8bd5 + '.pdf')
$null = New-Item -ItemType File -Path $unicodeFile
$envNames = @('EVERYTHING_TEST_EXIT_SEQUENCE', 'EVERYTHING_TEST_ATTEMPT_LOG', 'EVERYTHING_TEST_RESULT')
$previousEnv = @{}
foreach ($name in $envNames) { $previousEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

try {
    # Real native stderr exercises the code path that SyntheticEsExitCode bypasses.
    Add-Type -OutputAssembly $fakeEs -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class FakeEverythingCli {
    public static int Main(string[] args) {
        string log = Environment.GetEnvironmentVariable("EVERYTHING_TEST_ATTEMPT_LOG");
        int attempt = File.Exists(log) ? File.ReadAllLines(log).Length : 0;
        File.AppendAllText(log, string.Join("\t", args) + Environment.NewLine, Encoding.UTF8);
        string[] codes = Environment.GetEnvironmentVariable("EVERYTHING_TEST_EXIT_SEQUENCE").Split(',');
        int code = int.Parse(codes[Math.Min(attempt, codes.Length - 1)]);
        if (code == 0) {
            int cpIndex = Array.IndexOf(args, "-cp");
            int cp = cpIndex >= 0 ? int.Parse(args[cpIndex + 1]) : 936;
            byte[] output = Encoding.GetEncoding(cp).GetBytes(Environment.GetEnvironmentVariable("EVERYTHING_TEST_RESULT") + "\r\n");
            using (Stream stream = Console.OpenStandardOutput()) { stream.Write(output, 0, output.Length); }
        } else {
            Console.Error.WriteLine("FAKE_NATIVE_ERROR_" + code + "_ATTEMPT_" + attempt);
        }
        return code;
    }
}
'@
    $env:EVERYTHING_TEST_ATTEMPT_LOG = $attemptLog
    $env:EVERYTHING_TEST_RESULT = $unicodeFile
    $powerShellExe = if ($SearchPowerShellExe) { $SearchPowerShellExe } else { Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe' }
    $cases = @(
        @{ Name = 'NORMAL'; Sequence = '0'; Allow = $false; Exit = 0; Attempts = 1 },
        @{ Name = 'STALE_INDEX_PATH'; Sequence = '0'; Allow = $false; Exit = 0; Attempts = 1 },
        @{ Name = 'NON8'; Sequence = '7'; Allow = $false; Exit = 7; Attempts = 1 },
        @{ Name = 'FALSE_8_TO_0'; Sequence = '8,0'; Allow = $false; Exit = 0; Attempts = 2 },
        @{ Name = 'FALSE_8_TO_8'; Sequence = '8,8'; Allow = $false; Exit = 8; Attempts = 2 },
        @{ Name = 'TRUE_8_TO_0'; Sequence = '8,0'; Allow = $true; Exit = 0; Attempts = 2 },
        @{ Name = 'TRUE_8_TO_8'; Sequence = '8,8'; Allow = $true; Exit = 8; Attempts = 2 }
    )
    foreach ($case in $cases) {
        if (Test-Path -LiteralPath $attemptLog) { Remove-Item -LiteralPath $attemptLog }
        $env:EVERYTHING_TEST_EXIT_SEQUENCE = $case.Sequence
        $env:EVERYTHING_TEST_RESULT = if ($case.Name -eq 'STALE_INDEX_PATH') { $unicodeFile + '.missing' } else { $unicodeFile }
        $command = "& '{0}' -Query 'reply token' -Root '{1}' -ItemType File -Extensions @('txt','md') -Regex -MatchPath -MaxResults 5 -EverythingCliPath '{2}' -SyntheticEnsureProbeExitCodes 0 -Quiet -PassThru" -f $searchScript.Replace("'", "''"), $fixture.Replace("'", "''"), $fakeEs.Replace("'", "''")
        if ($case.Allow) { $command += ' -AllowStart' }
        $command += " -OutputCsv '{0}' -OutputJson '{1}'" -f (Join-Path $fixture 'results.csv').Replace("'", "''"), (Join-Path $fixture 'results.json').Replace("'", "''")
        # Keep PowerShell host/progress records out of the native stderr assertion.
        $command = '$ProgressPreference = ''SilentlyContinue''; $encodingBefore=[Console]::OutputEncoding.CodePage; $items=@(' + $command + ' 6>&1); $code=$LASTEXITCODE; $items; if([Console]::OutputEncoding.CodePage -ne $encodingBefore){throw ''Console encoding was not restored''}; if($code -eq 0){ if(@($items | Where-Object {$_.FullPath -ceq $env:EVERYTHING_TEST_RESULT}).Count -ne 1){throw ''Unicode result was dropped''}; $csv=Import-Csv -LiteralPath ''' + (Join-Path $fixture 'results.csv').Replace("'", "''") + '''; $json=Get-Content -Encoding UTF8 -Raw -LiteralPath ''' + (Join-Path $fixture 'results.json').Replace("'", "''") + ''' | ConvertFrom-Json; if($csv.FullPath -cne $env:EVERYTHING_TEST_RESULT -or $json.FullPath -cne $env:EVERYTHING_TEST_RESULT){throw ''Unicode export mismatch''}; Write-Output ''UNICODE_RESULT_CSV_JSON=PASS'' }; exit $code'
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $powerShellExe
        $startInfo.Arguments = '-NoProfile -InputFormat Text -OutputFormat Text -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($startInfo)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $nativeExit = $process.ExitCode
        $process.Dispose()
        $attempts = @(Get-Content -LiteralPath $attemptLog)
        if ($nativeExit -ne $case.Exit -or $attempts.Count -ne $case.Attempts) {
            throw "$($case.Name): exit=$nativeExit attempts=$($attempts.Count) stdout=$stdout stderr=$stderr"
        }
        $expectedArgs = @('-n','5','-full-path-and-name','-cp','65001','-timeout','5000','-no-result-error','-path',$fixture,'/a-d','-regex','-match-path','-sort','path-ascending','reply token','ext:txt;md') -join "`t"
        foreach ($attempt in $attempts) {
            if ($attempt -cne $expectedArgs) { throw "$($case.Name): native search arguments changed: $attempt" }
        }
        $expectedRetry = $case.Attempts - 1
        if ($stdout -notmatch "SEARCH_RETRY_COUNT=$expectedRetry") { throw "$($case.Name): wrong retry count" }
        $eventLines = @($stdout -split '\r?\n' | Where-Object { $_ -match '^\{"EVENT":"SEARCH_ERROR8_CONTEXT"' })
        if ($case.Exit -eq 8) {
            if ($eventLines.Count -ne 1) { throw "$($case.Name): expected one JSON failure event" }
            $event = $eventLines[0] | ConvertFrom-Json
            if ($event.ES_OUTPUT -notmatch 'FAKE_NATIVE_ERROR_8_ATTEMPT_1' -or
                $event.ES_EXE_PATH -ne $fakeEs -or $event.RETRY_COUNT -ne 1 -or
                $event.FINAL_ACTION -ne 'FALLBACK_HANDOFF' -or
                $event.EXECUTION_CONTEXT_HINT -ne 'CHECK_HOST_IPC_VIA_TOOL_APPROVAL' -or
                $event.IPC_TIMEOUT_MS -ne 5000 -or
                $stderr -notmatch 'FAKE_NATIVE_ERROR_8_ATTEMPT_1') { throw "$($case.Name): native failure evidence lost" }
        } elseif ($eventLines.Count -ne 0) { throw "$($case.Name): unexpected Error8 event" }
        if ($case.Exit -eq 0 -and ($stdout -match 'FAKE_NATIVE_ERROR' -or $stderr.Length -ne 0)) {
            throw "$($case.Name): successful search leaked error output: $stderr"
        }
        if ($case.Exit -eq 0 -and $stdout -notmatch 'UNICODE_RESULT_CSV_JSON=PASS') { throw 'Unicode assertion did not execute' }
        if ($case.Exit -eq 0) {
            $exported = Import-Csv -LiteralPath (Join-Path $fixture 'results.csv')
            $expectedStatus = if ($case.Name -eq 'STALE_INDEX_PATH') { 'INDEX_ONLY_OR_STALE' } else { 'PRESENT' }
            if ($exported.DiskStatus -ne $expectedStatus -or -not $exported.PSObject.Properties['LastWriteTimeUtc'] -or
                $exported.Extension.StartsWith('.')) { throw 'v1.1.0 export fields or stale-index candidates changed.' }
        }
        if ($case.Exit -eq 7 -and $stderr -notmatch 'FAKE_NATIVE_ERROR_7_ATTEMPT_0') {
            throw 'Native non-8 error was lost'
        }
        Write-Output ('NATIVE_' + $case.Name + '=PASS')
    }
    Write-Output 'NATIVE_ARGUMENTS_AND_STDERR_REGRESSION=PASS'
}
finally {
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $previousEnv[$name], 'Process') }
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedFixture) -like 'everything-native-test-*') {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
