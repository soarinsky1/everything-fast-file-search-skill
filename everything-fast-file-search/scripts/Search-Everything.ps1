[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Query,

    [string]$Root,

    [string[]]$Extensions,

    [ValidateSet('Any', 'File', 'Folder')]
    [string]$ItemType = 'Any',

    [ValidateRange(1, 200)]
    [int]$MaxResults = 20,

    [string]$OutputCsv,
    [string]$OutputJson,

    [switch]$IncludeSha256,

    [ValidateRange(1, 50)]
    [int]$HashLimit = 10,

    [switch]$Quiet,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ensureScript = Join-Path $scriptDir 'Ensure-EverythingReady.ps1'

$ready = & $ensureScript -Quiet -PassThru
if (-not $ready -or $ready.IpcFinal -ne 'READY') {
    throw 'Everything IPC is not ready. Run Ensure-EverythingReady.ps1 for diagnostics.'
}

$es = $ready.EsExe
$options = @()

if ($Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Root directory does not exist: $Root"
    }
    $options += @('-path', $Root)
}

$options += @('-n', [string]$MaxResults, '-full-path-and-name')

switch ($ItemType) {
    'File'   { $options += '/a-d' }
    'Folder' { $options += '/ad' }
}

# IMPORTANT: keep independent Everything search terms as independent native
# arguments. On Windows PowerShell 5.1, combining the basename and ext: filter
# into one quoted argument can incorrectly return zero results.
$searchTerms = @($Query)

if ($Extensions) {
    $cleanExtensions = @(
        $Extensions |
        ForEach-Object { $_.Trim().TrimStart('.') } |
        Where-Object { $_ }
    )

    if ($cleanExtensions.Count -gt 0) {
        $searchTerms += ('ext:' + ($cleanExtensions -join ';'))
    }
}

$started = Get-Date
$output = & $es @options @searchTerms 2>&1
$exitCode = $LASTEXITCODE
$elapsedMs = [math]::Round(((Get-Date) - $started).TotalMilliseconds, 3)

if ($exitCode -ne 0) {
    $text = (($output | ForEach-Object { "$_" }) -join "`n").Trim()
    throw "es.exe failed with exit code $exitCode. $text"
}

$paths = @(
    $output |
    ForEach-Object { "$_".Trim() } |
    Where-Object { $_ } |
    Select-Object -First $MaxResults
)

$rows = foreach ($path in $paths) {
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        [pscustomobject]@{
            FullPath         = $item.FullName
            Name             = $item.Name
            ItemType         = if ($item.PSIsContainer) { 'Folder' } else { 'File' }
            Extension        = if ($item.PSIsContainer) { '' } else { $item.Extension.TrimStart('.') }
            SizeBytes        = if ($item.PSIsContainer) { $null } else { $item.Length }
            LastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
            SHA256           = $null
            DiskStatus       = 'PRESENT'
        }
    }
    else {
        [pscustomobject]@{
            FullPath         = $path
            Name             = [IO.Path]::GetFileName($path)
            ItemType         = 'Unknown'
            Extension        = [IO.Path]::GetExtension($path).TrimStart('.')
            SizeBytes        = $null
            LastWriteTimeUtc = $null
            SHA256           = $null
            DiskStatus       = 'INDEX_ONLY_OR_STALE'
        }
    }
}

$rows = @($rows)

if ($IncludeSha256 -and $rows.Count -le $HashLimit) {
    foreach ($row in $rows) {
        if ($row.ItemType -eq 'File' -and $row.DiskStatus -eq 'PRESENT') {
            $row.SHA256 = (Get-FileHash -LiteralPath $row.FullPath -Algorithm SHA256).Hash
        }
    }
}

if ($OutputCsv) {
    $parent = Split-Path -Parent $OutputCsv
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $rows | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
}

if ($OutputJson) {
    $parent = Split-Path -Parent $OutputJson
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputJson -Encoding UTF8
}

if (-not $Quiet) {
    Write-Host ("STATUS={0} RESULTS={1} ES_SEARCH_MS={2}" -f $(if ($rows.Count) { 'FOUND' } else { 'NO_RESULTS' }), $rows.Count, $elapsedMs)
    Write-Host ("QUERY={0}" -f $Query)
    if ($Extensions) { Write-Host ("EXTENSIONS={0}" -f (($Extensions | ForEach-Object { $_.Trim().TrimStart('.') }) -join ',')) }
    if ($Root) { Write-Host ("ROOT={0}" -f $Root) }
    if ($OutputCsv) { Write-Host ("CSV={0}" -f $OutputCsv) }
    if ($OutputJson) { Write-Host ("JSON={0}" -f $OutputJson) }
    if ($IncludeSha256 -and $rows.Count -gt $HashLimit) {
        Write-Host ("SHA256=SKIPPED candidate_count_exceeds_hash_limit({0})" -f $HashLimit)
    }
    foreach ($row in $rows) { Write-Host $row.FullPath }
}

if ($PassThru) {
    $rows
}
