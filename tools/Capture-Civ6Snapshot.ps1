[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('A', 'B')]
    [string]$Pc,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Checkpoint,

    [string]$Notes = '',

    [string]$CivRoot = (Join-Path $env:LOCALAPPDATA "Firaxis Games\Sid Meier's Civilization VI"),

    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\captures'),

    [switch]$IncludeAppOptions,

    [string[]]$ExtraPath = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Copy-ReadableFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $destinationParent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null

    $sourceStream = $null
    $destinationStream = $null
    try {
        $sourceStream = [System.IO.File]::Open(
            $Source,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        $destinationStream = [System.IO.File]::Open(
            $Destination,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $sourceStream.CopyTo($destinationStream)
    }
    finally {
        if ($null -ne $destinationStream) {
            $destinationStream.Dispose()
        }
        if ($null -ne $sourceStream) {
            $sourceStream.Dispose()
        }
    }
}

function Copy-TreeSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $sourceItem = Get-Item -LiteralPath $SourceRoot -ErrorAction Stop
    if (-not $sourceItem.PSIsContainer) {
        Copy-ReadableFile `
            -Source $sourceItem.FullName `
            -Destination (Join-Path $DestinationRoot $sourceItem.Name)
        return
    }

    foreach ($file in Get-ChildItem -LiteralPath $sourceItem.FullName -File -Recurse -ErrorAction Stop) {
        $relativePath = $file.FullName.Substring($sourceItem.FullName.Length).TrimStart('\')
        Copy-ReadableFile `
            -Source $file.FullName `
            -Destination (Join-Path $DestinationRoot $relativePath)
    }
}

$civRootFull = [System.IO.Path]::GetFullPath($CivRoot)
$logsPath = Join-Path $civRootFull 'Logs'
if (-not (Test-Path -LiteralPath $logsPath -PathType Container)) {
    throw "Civ VI Logs folder not found at '$logsPath'. Start the game once or pass -CivRoot."
}

$outputRootFull = [System.IO.Path]::GetFullPath($OutputRoot)
$copyStartedAtUtc = [DateTime]::UtcNow.ToString('o')
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$snapshotName = "{0}-PC{1}-{2}" -f $Checkpoint, $Pc, $stamp
$snapshotRoot = Join-Path (Join-Path $outputRootFull $RunId) $snapshotName
if (Test-Path -LiteralPath $snapshotRoot) {
    throw "Snapshot destination already exists: '$snapshotRoot'."
}

New-Item -ItemType Directory -Path $snapshotRoot -Force | Out-Null
Copy-TreeSnapshot -SourceRoot $logsPath -DestinationRoot (Join-Path $snapshotRoot 'logs')

if ($IncludeAppOptions) {
    $appOptionsPath = Join-Path $civRootFull 'AppOptions.txt'
    if (Test-Path -LiteralPath $appOptionsPath -PathType Leaf) {
        Copy-ReadableFile `
            -Source $appOptionsPath `
            -Destination (Join-Path $snapshotRoot 'config\AppOptions.txt')
    }
    else {
        Write-Warning '-IncludeAppOptions was specified, but AppOptions.txt was not found.'
    }
}

$extraIndex = 0
foreach ($path in $ExtraPath) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Warning "Extra path not found and was skipped: '$path'."
        continue
    }

    $extraIndex++
    $item = Get-Item -LiteralPath $path -ErrorAction Stop
    $safeName = $item.Name -replace '[^A-Za-z0-9._-]', '_'
    $destination = Join-Path $snapshotRoot ("extra\{0:D2}-{1}" -f $extraIndex, $safeName)

    if ($item.PSIsContainer) {
        Copy-TreeSnapshot -SourceRoot $item.FullName -DestinationRoot $destination
    }
    else {
        Copy-ReadableFile -Source $item.FullName -Destination $destination
    }
}

$manifestFiles = @(
    Get-ChildItem -LiteralPath $snapshotRoot -File -Recurse |
        Where-Object { $_.Name -ne 'manifest.json' } |
        Sort-Object FullName |
        ForEach-Object {
            [ordered]@{
                relativePath = $_.FullName.Substring($snapshotRoot.Length).TrimStart('\')
                lengthBytes  = $_.Length
                sha256       = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        }
)

$manifest = [ordered]@{
    schemaVersion       = 1
    runId               = $RunId
    checkpoint          = $Checkpoint
    pcLabel             = $Pc
    computerName        = $env:COMPUTERNAME
    copyStartedAtUtc    = $copyStartedAtUtc
    copyCompletedAtUtc  = [DateTime]::UtcNow.ToString('o')
    civRoot             = $civRootFull
    notes               = $Notes
    appOptionsIncluded  = [bool]$IncludeAppOptions
    files               = $manifestFiles
}

$manifestPath = Join-Path $snapshotRoot 'manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Captured $($manifestFiles.Count) files."
Write-Host "Snapshot: $snapshotRoot"
