[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Query,
    [string]$Root,
    [string[]]$Extensions,
    [ValidateSet('Any', 'File', 'Folder')] [string]$ItemType = 'Any',
    [ValidateRange(1, 200)] [int]$MaxResults = 20,
    [string]$OutputCsv,
    [string]$OutputJson,
    [switch]$IncludeSha256,
    [ValidateRange(1, 50)] [int]$HashLimit = 10,
    [switch]$Quiet,
    [switch]$PassThru,
    [string]$EverythingCliPath,
    [ValidateRange(500, 30000)] [int]$TimeoutMs = 5000,
    [ValidateRange(-1, 255)] [int]$SyntheticEsExitCode = -1,
    [switch]$ReportNativeExitCode
)

$ErrorActionPreference = 'Stop'
$resolveCli = Join-Path $PSScriptRoot 'Resolve-EverythingCli.ps1'
$es = if ($SyntheticEsExitCode -ge 0) { '<synthetic-es.exe>' } elseif ($EverythingCliPath) { $EverythingCliPath } else { & $resolveCli | Select-Object -First 1 }
if (-not $es) { throw 'es.exe was not found.' }
if ($Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Root directory does not exist: $Root" }
    $Root = (Resolve-Path -LiteralPath $Root).Path
}

$searchTerms = New-Object 'System.Collections.Generic.List[string]'
$searchTerms.Add($Query.Trim())
if ($Extensions) {
    $cleanExtensions = @($Extensions | ForEach-Object { $_.Trim().TrimStart('.') } | Where-Object { $_ })
    if ($cleanExtensions.Count -gt 0) { $searchTerms.Add('ext:' + ($cleanExtensions -join ';')) }
}

$options = New-Object 'System.Collections.Generic.List[string]'
$options.Add('-n'); $options.Add([string]$MaxResults); $options.Add('-full-path-and-name'); $options.Add('-timeout'); $options.Add([string]$TimeoutMs); $options.Add('-no-result-error')
if ($Root) { $options.Add('-path'); $options.Add($Root) }
switch ($ItemType) { 'File' { $options.Add('/a-d') } 'Folder' { $options.Add('/ad') } }

$started = Get-Date
if ($SyntheticEsExitCode -ge 0) { $output = @(); $exitCode = $SyntheticEsExitCode }
else {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @(& $es @options @searchTerms 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
}
$elapsedMs = [math]::Round(((Get-Date) - $started).TotalMilliseconds, 3)
if ($ReportNativeExitCode) { $global:EverythingSearchCoreNativeExitCode = $exitCode }
if ($exitCode -eq 9) { $output = @() }
elseif ($exitCode -ne 0) {
    if ($ReportNativeExitCode) { return }
    throw "es.exe failed with exit code $exitCode."
}

$paths = @($output | ForEach-Object { [string]$_ } | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ } | Select-Object -Unique -First $MaxResults)
$rows = foreach ($path in $paths) {
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        [pscustomobject]@{ FullPath=$item.FullName; Name=$item.Name; ItemType=if($item.PSIsContainer){'Folder'}else{'File'}; Extension=if($item.PSIsContainer){''}else{$item.Extension.TrimStart('.')}; SizeBytes=if($item.PSIsContainer){$null}else{$item.Length}; LastWriteTimeUtc=$item.LastWriteTimeUtc.ToString('o'); SHA256=$null; DiskStatus='PRESENT' }
    } else {
        [pscustomobject]@{ FullPath=$path; Name=[IO.Path]::GetFileName($path); ItemType='Unknown'; Extension=[IO.Path]::GetExtension($path).TrimStart('.'); SizeBytes=$null; LastWriteTimeUtc=$null; SHA256=$null; DiskStatus='INDEX_ONLY_OR_STALE' }
    }
}
$rows = @($rows)
if ($IncludeSha256 -and $rows.Count -le $HashLimit) { foreach ($row in $rows) { if ($row.ItemType -eq 'File' -and $row.DiskStatus -eq 'PRESENT') { $row.SHA256 = (Get-FileHash -LiteralPath $row.FullPath -Algorithm SHA256).Hash } } }
if ($OutputCsv) { $rows | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8 }
if ($OutputJson) { @($rows) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputJson -Encoding UTF8 }
if (-not $Quiet) {
    Write-Host ("STATUS={0} RESULTS={1} ES_SEARCH_MS={2}" -f $(if($rows.Count){'FOUND'}else{'NO_RESULTS'}), $rows.Count, $elapsedMs)
    Write-Host ("QUERY={0}" -f ($searchTerms -join ' '))
    if ($Root) { Write-Host ("ROOT={0}" -f $Root) }
}
if ($PassThru) { $rows }
