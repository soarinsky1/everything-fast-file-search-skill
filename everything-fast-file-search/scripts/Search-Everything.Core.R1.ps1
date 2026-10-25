[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Query,

    [string]$Root,

    [ValidateRange(1, 200)]
    [int]$MaxResults = 20,

    [ValidateSet('Any', 'File', 'Folder', 'Directory')]
    [string]$ItemType = 'Any',

    [string[]]$Extensions,

    [ValidateSet('path', 'name', 'size', 'extension', 'date-created', 'date-modified', 'date-accessed')]
    [string]$SortBy = 'path',

    [switch]$Descending,
    [switch]$Regex,
    [switch]$CaseSensitive,
    [switch]$MatchPath,
    [switch]$IncludeSha256,

    [ValidateRange(1, 50)]
    [int]$HashLimit = 10,

    [string]$OutputCsv,
    [string]$OutputJson,
    [string]$EverythingCliPath,

    # Test-only: simulate one native es.exe exit code without invoking es.exe.
    [ValidateRange(-1, 255)]
    [int]$SyntheticEsExitCode = -1,

    # Used by Search-Everything.ps1 to receive the native es.exe exit code.
    [switch]$ReportNativeExitCode,

    [ValidateRange(500, 30000)]
    [int]$TimeoutMs = 5000,

    [switch]$Quiet,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolveScript = Join-Path $scriptRoot 'Resolve-EverythingCli.ps1'
$es = (& $resolveScript -EverythingCliPath $EverythingCliPath | Select-Object -First 1)

if ($Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Root path does not exist or is not a directory: $Root"
    }
    $Root = (Resolve-Path -LiteralPath $Root).Path
}

$effectiveQuery = $Query.Trim()
$searchTerms = New-Object 'System.Collections.Generic.List[string]'
$searchTerms.Add($effectiveQuery)
if ($Extensions -and $Extensions.Count -gt 0) {
    $cleanExt = @($Extensions | ForEach-Object { $_.Trim().TrimStart('.') } | Where-Object { $_ })
    if ($cleanExt.Count -gt 0) {
        $extensionTerm = "ext:$($cleanExt -join ';')"
        $effectiveQuery = "$effectiveQuery $extensionTerm"
        $searchTerms.Add($extensionTerm)
    }
}

$args = New-Object 'System.Collections.Generic.List[string]'
$args.Add('-n')
$args.Add([string]$MaxResults)
$args.Add('-full-path-and-name')
# ES defaults to the console INPUT code page, which can differ from the
# PowerShell decoder. Explicit UTF-8 prevents valid Unicode paths being lost.
$args.Add('-cp')
$args.Add('65001')
$args.Add('-timeout')
$args.Add([string]$TimeoutMs)
$args.Add('-no-result-error')

if ($Root) {
    $args.Add('-path')
    $args.Add($Root)
}

switch ($ItemType) {
    'File' { $args.Add('/a-d') }
    'Directory' { $args.Add('/ad') }
    'Folder' { $args.Add('/ad') }
}

if ($Regex) { $args.Add('-regex') }
if ($CaseSensitive) { $args.Add('-case') }
if ($MatchPath) { $args.Add('-match-path') }

$sortValue = if ($Descending) { "$SortBy-descending" } else { "$SortBy-ascending" }
$args.Add('-sort')
$args.Add($sortValue)
foreach ($searchTerm in $searchTerms) {
    $args.Add($searchTerm)
}

$started = Get-Date
if ($SyntheticEsExitCode -ge 0) {
    $raw = @()
    $exitCode = $SyntheticEsExitCode
}
else {
    $nativeResult = & (Join-Path $scriptRoot 'Invoke-EverythingCli.ps1') -EsExe $es -NativeArguments $args.ToArray() -Utf8Output
    $raw = @($nativeResult.Output -split '\r?\n')
    $exitCode = $nativeResult.ExitCode
}
$elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds

if ($ReportNativeExitCode) {
    $global:EverythingSearchCoreNativeExitCode = $exitCode
    $nativeOutput = if ($exitCode -ne 0 -and $exitCode -ne 9) {
        ($raw | ForEach-Object { [string]$_ }) -join "`n"
    } else { '' }
    $global:EverythingSearchCoreNativeResult = [pscustomobject]@{
        EsPath = $es
        ExitCode = $exitCode
        ElapsedMs = $elapsedMs
        Output = if ($nativeOutput.Length -gt 4096) { $nativeOutput.Substring(0, 4096) } else { $nativeOutput }
        OutputTruncated = ($nativeOutput.Length -gt 4096)
    }
}

if ($exitCode -eq 9) {
    $raw = @()
} elseif ($exitCode -ne 0) {
    if ($ReportNativeExitCode) {
        return
    }
    $message = ($raw | Out-String).Trim()
    throw "Everything search failed with exit code $exitCode. $message"
}

$paths = @(
    $raw |
    ForEach-Object { [string]$_ } |
    ForEach-Object { $_.Trim().Trim('"') } |
    Where-Object { $_ } |
    Select-Object -Unique |
    Select-Object -First $MaxResults
)

$shouldHash = $IncludeSha256 -and ($paths.Count -le $HashLimit)
$rows = foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path)) {
        [pscustomobject]@{
            FullPath=$path; Name=[IO.Path]::GetFileName($path); ItemType='Unknown'
            Extension=[IO.Path]::GetExtension($path).TrimStart('.'); SizeBytes=$null
            LastWriteTimeUtc=$null; LastWriteUtc=$null; SHA256=$null; DiskStatus='INDEX_ONLY_OR_STALE'
        }
        continue
    }
    $item = Get-Item -LiteralPath $path -Force
    $isDir = [bool]$item.PSIsContainer
    $hash = $null
    if ($shouldHash -and -not $isDir) {
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }

    [pscustomobject]@{
        FullPath = $item.FullName
        Name = $item.Name
        ItemType = if ($isDir) { 'Folder' } else { 'File' }
        Extension = if ($isDir) { '' } else { $item.Extension.TrimStart('.') }
        SizeBytes = if ($isDir) { $null } else { $item.Length }
        LastWriteUtc = $item.LastWriteTimeUtc.ToString('o')
        LastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        DiskStatus = 'PRESENT'
        SHA256 = $hash
    }
}

if ($OutputCsv) {
    $csvParent = Split-Path -Parent $OutputCsv
    if ($csvParent -and -not (Test-Path -LiteralPath $csvParent)) {
        New-Item -ItemType Directory -Path $csvParent -Force | Out-Null
    }
    $rows | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
}

if ($OutputJson) {
    $jsonParent = Split-Path -Parent $OutputJson
    if ($jsonParent -and -not (Test-Path -LiteralPath $jsonParent)) {
        New-Item -ItemType Directory -Path $jsonParent -Force | Out-Null
    }
    @($rows) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputJson -Encoding UTF8
}

$summary = [pscustomobject]@{
    Status = if (@($rows).Count -gt 0) { 'FOUND' } else { 'NO_RESULTS' }
    Query = $Query
    EffectiveQuery = $effectiveQuery
    Root = $Root
    ResultCount = @($rows).Count
    MaxResults = $MaxResults
    SearchElapsedMs = $elapsedMs
    Sha256Requested = [bool]$IncludeSha256
    Sha256Computed = [bool]$shouldHash
    OutputCsv = $OutputCsv
    OutputJson = $OutputJson
    EsPath = $es
}

if (-not $Quiet) {
    Write-Host ("STATUS={0} RESULTS={1} ELAPSED_MS={2}" -f $summary.Status, $summary.ResultCount, $summary.SearchElapsedMs)
    Write-Host ("QUERY={0}" -f $summary.EffectiveQuery)
    if ($summary.Root) { Write-Host ("ROOT={0}" -f $summary.Root) }
    if ($summary.OutputCsv) { Write-Host ("CSV={0}" -f $summary.OutputCsv) }
    if ($summary.OutputJson) { Write-Host ("JSON={0}" -f $summary.OutputJson) }
    if ($summary.Sha256Requested -and -not $summary.Sha256Computed) {
        Write-Host ("SHA256=SKIPPED candidate_count_exceeds_hash_limit({0})" -f $HashLimit)
    }
    foreach ($row in @($rows)) {
        Write-Host $row.FullPath
    }
}

if ($PassThru) {
    $rows
}
