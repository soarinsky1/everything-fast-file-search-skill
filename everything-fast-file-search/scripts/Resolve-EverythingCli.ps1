[CmdletBinding()]
param(
    [string]$EverythingCliPath
)

$ErrorActionPreference = 'Stop'

function Add-Candidate([System.Collections.Generic.List[string]]$List, [string]$Path) {
    if (-not [string]::IsNullOrWhiteSpace($Path) -and -not $List.Contains($Path)) {
        $List.Add($Path)
    }
}

$candidates = New-Object 'System.Collections.Generic.List[string]'

if ($EverythingCliPath) {
    Add-Candidate $candidates $EverythingCliPath
}

$cmd = Get-Command es.exe -ErrorAction SilentlyContinue
if ($cmd -and $cmd.Source) {
    Add-Candidate $candidates $cmd.Source
}

if ($env:LOCALAPPDATA) {
    Add-Candidate $candidates (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\es.exe')
}
if ($env:ProgramFiles) {
    Add-Candidate $candidates (Join-Path $env:ProgramFiles 'Everything\es.exe')
}
if (${env:ProgramFiles(x86)}) {
    Add-Candidate $candidates (Join-Path ${env:ProgramFiles(x86)} 'Everything\es.exe')
}
if ($env:LOCALAPPDATA) {
    # Exact official package location remains readable in some environments that
    # deny directory enumeration. Do not require listing it to locate the file.
    Add-Candidate $candidates (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\voidtools.Everything.Cli_Microsoft.Winget.Source_8wekyb3d8bbwe\es.exe')
}

foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        Write-Output $resolved
        exit 0
    }
}

# WinGet packages are not always visible through PATH in a fresh/sandboxed shell.
# Search only the official CLI package subtree, never a user/project drive.
if ($env:LOCALAPPDATA) {
    $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $wingetRoot -PathType Container) {
        $packages = @(Get-ChildItem -LiteralPath $wingetRoot -Directory -Filter 'voidtools.Everything.Cli_*' -ErrorAction SilentlyContinue | Sort-Object FullName)
        foreach ($package in $packages) {
            $candidate = Get-ChildItem -LiteralPath $package.FullName -Filter 'es.exe' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -First 1
            if ($candidate) {
                Write-Output $candidate.FullName
                exit 0
            }
        }
    }
}

Write-Error 'es.exe was not found. Install the official Everything CLI or provide -EverythingCliPath.'
exit 2
