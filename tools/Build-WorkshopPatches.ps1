[CmdletBinding()]
param(
    [string]$PatchRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'workshop-patches'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\workshop')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$specifications = @(
    [pscustomobject]@{
        Directory = 'QuickDealsMultiplayerPatch'
        Manifest = 'QuickDealsMultiplayerPatch.modinfo'
        Script = 'qd_multiplayer_safety_patch.lua'
    },
    [pscustomobject]@{
        Directory = 'TechCivicProgressMultiplayerPatch'
        Manifest = 'TechCivicProgressMultiplayerPatch.modinfo'
        Script = 'tcpp_multiplayer_safety_patch.lua'
    },
    [pscustomobject]@{
        Directory = 'MultiplayerHelperSafetyPatch'
        Manifest = 'MultiplayerHelperSafetyPatch.modinfo'
        Script = 'mph_multiplayer_safety_patch.lua'
    }
)

$resolvedPatchRoot = [System.IO.Path]::GetFullPath($PatchRoot)
$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null

foreach ($specification in $specifications) {
    $source = Join-Path $resolvedPatchRoot $specification.Directory
    $manifest = Join-Path $source $specification.Manifest
    $script = Join-Path $source $specification.Script
    foreach ($required in @($manifest, $script)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required Workshop package file does not exist: '$required'."
        }
    }

    [xml]$xml = Get-Content -LiteralPath $manifest -Raw
    if ($xml.DocumentElement.LocalName -ne 'Mod') {
        throw "Invalid mod manifest '$manifest'."
    }

    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('civ6-workshop-package-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        Copy-Item -LiteralPath $manifest, $script -Destination $temporaryRoot
        $zipPath = Join-Path $resolvedOutputRoot ($specification.Directory + '.zip')
        $packagePath = Join-Path $resolvedOutputRoot ($specification.Directory + '.civ6mod')
        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force
        }
        if (Test-Path -LiteralPath $packagePath) {
            Remove-Item -LiteralPath $packagePath -Force
        }
        Compress-Archive -Path (Join-Path $temporaryRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
        Move-Item -LiteralPath $zipPath -Destination $packagePath
        Write-Output $packagePath
    }
    finally {
        $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
        $temporaryPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if ($resolvedTemporaryRoot.StartsWith($temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedTemporaryRoot) -like 'civ6-workshop-package-*') {
            Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
        }
    }
}
