[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullPath')]
    [string[]]$Path,

    [switch]$IncludeSha256
)

begin {
    $ErrorActionPreference = 'Stop'
}

process {
    foreach ($p in $Path) {
        if (-not (Test-Path -LiteralPath $p)) {
            [pscustomobject]@{
                FullPath         = $p
                Exists           = $false
                ItemType         = $null
                SizeBytes        = $null
                LastWriteTimeUtc = $null
                SHA256           = $null
            }
            continue
        }

        $item = Get-Item -LiteralPath $p -Force
        $hash = $null
        if ($IncludeSha256 -and -not $item.PSIsContainer) {
            $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        }

        [pscustomobject]@{
            FullPath         = $item.FullName
            Exists           = $true
            ItemType         = if ($item.PSIsContainer) { 'Folder' } else { 'File' }
            SizeBytes        = if ($item.PSIsContainer) { $null } else { $item.Length }
            LastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
            SHA256           = $hash
        }
    }
}
