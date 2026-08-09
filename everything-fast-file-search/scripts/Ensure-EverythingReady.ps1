[CmdletBinding()]
param(
    [ValidateRange(1, 10)]
    [int]$RetryCount = 3,

    [ValidateRange(1, 30)]
    [int]$RetryDelaySeconds = 2,

    [switch]$Quiet,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolveCli = Join-Path $scriptDir 'Resolve-EverythingCli.ps1'

function Resolve-EverythingApp {
    $proc = Get-Process -Name Everything -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        try {
            if ($proc.Path -and (Test-Path -LiteralPath $proc.Path -PathType Leaf)) {
                return $proc.Path
            }
        }
        catch {}
    }

    $cmd = Get-Command Everything.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) {
        return $cmd.Source
    }

    $registryPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\Everything.exe',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\Everything.exe',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\Everything.exe'
    )

    foreach ($regPath in $registryPaths) {
        try {
            if (Test-Path $regPath) {
                $value = (Get-Item -Path $regPath -ErrorAction Stop).GetValue('')
                if ($value -and (Test-Path -LiteralPath $value -PathType Leaf)) {
                    return $value
                }
            }
        }
        catch {}
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Everything\Everything.exe'),
        (Join-Path $env:LOCALAPPDATA 'Everything\Everything.exe')
    )

    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Everything\Everything.exe')
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $wingetRoot -PathType Container) {
        $candidate = Get-ChildItem -LiteralPath $wingetRoot -Directory -Filter 'voidtools.Everything*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -File -Filter 'Everything.exe' -Recurse -ErrorAction SilentlyContinue
            } |
            Select-Object -First 1

        if ($candidate) {
            return $candidate.FullName
        }
    }

    return $null
}

function Test-Ipc {
    param([Parameter(Mandatory)][string]$EsExe)

    $output = & $EsExe -get-everything-version 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = (($output | ForEach-Object { "$_" }) -join "`n").Trim()
    }
}

$esExe = & $resolveCli
$initial = Test-Ipc -EsExe $esExe
$initialState = if ($initial.ExitCode -eq 0) { 'READY' } elseif ($initial.ExitCode -eq 8) { 'ERROR_8' } else { "ERROR_$($initial.ExitCode)" }

$everythingProcess = Get-Process -Name Everything -ErrorAction SilentlyContinue | Select-Object -First 1
$everythingExe = Resolve-EverythingApp
$autoStartAttempted = $false
$final = $initial

if ($initial.ExitCode -eq 8) {
    if (-not $everythingProcess) {
        if ($everythingExe) {
            Start-Process -FilePath $everythingExe -WindowStyle Minimized
            $autoStartAttempted = $true
        }
    }

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        Start-Sleep -Seconds $RetryDelaySeconds
        $final = Test-Ipc -EsExe $esExe
        if ($final.ExitCode -eq 0) { break }
    }
}

$status = if ($final.ExitCode -eq 0) { 'READY' } else { 'NEED_USER_ACTION' }
$result = [pscustomobject]@{
    Status                 = $status
    EsExe                  = $esExe
    EverythingExe          = $everythingExe
    EverythingProcess      = if (Get-Process -Name Everything -ErrorAction SilentlyContinue) { 'RUNNING' } else { 'NOT_RUNNING' }
    IpcInitial             = $initialState
    AutoStartAttempted     = $autoStartAttempted
    IpcFinal               = if ($final.ExitCode -eq 0) { 'READY' } else { "ERROR_$($final.ExitCode)" }
    UserActionRequired     = ($final.ExitCode -ne 0)
    EverythingVersionText = $final.Output
}

if (-not $Quiet) {
    $result | Format-List
}

if ($PassThru) {
    $result
}
