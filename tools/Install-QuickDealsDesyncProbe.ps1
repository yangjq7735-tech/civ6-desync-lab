[CmdletBinding()]
param(
    [string]$DestinationRoot,
    [switch]$Replace
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mod\QuickDealsDesyncProbe'))
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Probe source directory does not exist: '$sourceRoot'."
}

if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $oneDriveRoot = Join-Path $env:USERPROFILE 'OneDrive\Documents\My Games\Sid Meier''s Civilization VI\Mods'
    $documentsRoot = Join-Path $env:USERPROFILE 'Documents\My Games\Sid Meier''s Civilization VI\Mods'
    if (Test-Path -LiteralPath (Split-Path -Parent $oneDriveRoot)) {
        $DestinationRoot = $oneDriveRoot
    }
    else {
        $DestinationRoot = $documentsRoot
    }
}

$resolvedDestinationRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
$destination = Join-Path $resolvedDestinationRoot 'QuickDealsDesyncProbe'
$expectedModID = 'c44f70af-b40d-4e23-b030-a5040d3dcd2e'

New-Item -ItemType Directory -Path $resolvedDestinationRoot -Force | Out-Null

if (Test-Path -LiteralPath $destination) {
    $existingManifest = Join-Path $destination 'QuickDealsDesyncProbe.modinfo'
    $isOurProbe = (Test-Path -LiteralPath $existingManifest) -and
        ((Get-Content -LiteralPath $existingManifest -Raw) -match [regex]::Escape($expectedModID))

    if (-not $isOurProbe) {
        throw "Refusing to replace unrecognized directory: '$destination'."
    }
    if (-not $Replace) {
        throw "Probe is already installed at '$destination'. Pass -Replace to update this recognized probe."
    }

    Remove-Item -LiteralPath $destination -Recurse -Force
}

Copy-Item -LiteralPath $sourceRoot -Destination $destination -Recurse

$installedFiles = @(Get-ChildItem -LiteralPath $destination -File -Recurse | Sort-Object FullName)
if ($installedFiles.Count -ne 3) {
    throw "Expected exactly three installed probe files; found $($installedFiles.Count)."
}

$hashes = @($installedFiles | Get-FileHash -Algorithm SHA256)
Write-Host "Installed Quick Deals Desync Probe: $destination"
$hashes | Format-Table Algorithm, Hash, Path -AutoSize

[pscustomobject][ordered]@{
    schemaVersion = 1
    modID         = $expectedModID
    destination   = $destination
    files         = @($hashes | ForEach-Object {
        [ordered]@{
            path   = $_.Path
            sha256 = $_.Hash
        }
    })
}
