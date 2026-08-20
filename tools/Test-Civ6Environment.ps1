[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('A', 'B')]
    [string]$Pc,

    [string]$CivRoot = (Join-Path $env:LOCALAPPDATA "Firaxis Games\Sid Meier's Civilization VI"),

    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\preflight')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-OptionalFileHash {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$civRootFull = [System.IO.Path]::GetFullPath($CivRoot)
$logsPath = Join-Path $civRootFull 'Logs'
$appOptionsPath = Join-Path $civRootFull 'AppOptions.txt'
$outputRootFull = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $outputRootFull -Force | Out-Null

$logFiles = @()
if (Test-Path -LiteralPath $logsPath -PathType Container) {
    $logFiles = @(Get-ChildItem -LiteralPath $logsPath -File -Recurse -ErrorAction Stop)
}

$latestLogWriteUtc = $null
if ($logFiles.Count -gt 0) {
    $latestLog = $logFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    $latestLogWriteUtc = $latestLog.LastWriteTimeUtc.ToString('o')
}

$report = [ordered]@{
    schemaVersion      = 1
    pcLabel            = $Pc
    computerName       = $env:COMPUTERNAME
    capturedAtUtc      = [DateTime]::UtcNow.ToString('o')
    windowsVersion     = [Environment]::OSVersion.VersionString
    powershellVersion  = $PSVersionTable.PSVersion.ToString()
    civRoot            = $civRootFull
    civRootExists      = (Test-Path -LiteralPath $civRootFull -PathType Container)
    logsPath           = $logsPath
    logsPathExists     = (Test-Path -LiteralPath $logsPath -PathType Container)
    logFileCount       = $logFiles.Count
    latestLogWriteUtc  = $latestLogWriteUtc
    appOptionsExists   = (Test-Path -LiteralPath $appOptionsPath -PathType Leaf)
    appOptionsSha256   = (Get-OptionalFileHash -Path $appOptionsPath)
    note               = 'AppOptions content is not copied. Its hash is recorded only to flag configuration differences.'
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$outputPath = Join-Path $outputRootFull ("environment-PC{0}-{1}.json" -f $Pc, $stamp)
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outputPath -Encoding UTF8

[pscustomobject]$report | Format-List
Write-Host "Preflight report: $outputPath"

if (-not $report.civRootExists) {
    Write-Warning "Civ VI diagnostic root was not found. Start the game once or pass -CivRoot."
}
elseif (-not $report.logsPathExists) {
    Write-Warning "The Logs folder was not found. Start Civ VI, reach the main menu, and rerun this check."
}
