[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Test-CandidatePath {
    param([string]$Path)
    return ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf))
}

$cmd = Get-Command es.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cmd -and (Test-CandidatePath $cmd.Source)) {
    $cmd.Source
    return
}

$candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\es.exe'),
    (Join-Path $env:ProgramFiles 'Everything\es.exe')
)

if (${env:ProgramFiles(x86)}) {
    $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Everything\es.exe')
}

foreach ($candidate in $candidates) {
    if (Test-CandidatePath $candidate) {
        $candidate
        return
    }
}

$wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
if (Test-Path -LiteralPath $wingetRoot -PathType Container) {
    $candidate = Get-ChildItem -LiteralPath $wingetRoot -Directory -Filter 'voidtools.Everything.Cli_*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            Get-ChildItem -LiteralPath $_.FullName -File -Filter 'es.exe' -Recurse -ErrorAction SilentlyContinue
        } |
        Select-Object -First 1

    if ($candidate) {
        $candidate.FullName
        return
    }
}

throw 'es.exe was not found. Install the Everything command-line interface or add it to PATH.'
