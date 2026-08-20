[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SnapshotA,

    [Parameter(Mandatory = $true)]
    [string]$SnapshotB,

    [string]$MarkerPattern = 'CIV6_SYNC_PROBE|DESYNC|OUT.?OF.?SYNC',

    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Read-Manifest {
    param([Parameter(Mandatory = $true)][string]$SnapshotPath)

    $resolved = (Resolve-Path -LiteralPath $SnapshotPath -ErrorAction Stop).Path
    $manifestPath = Join-Path $resolved 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "manifest.json not found in '$resolved'."
    }

    return [pscustomobject]@{
        Root     = $resolved
        Manifest = (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
    }
}

function New-FileMap {
    param([Parameter(Mandatory = $true)]$Manifest)

    $map = @{}
    foreach ($file in @($Manifest.files)) {
        $key = ([string]$file.relativePath).ToLowerInvariant()
        $map[$key] = $file
    }
    return $map
}

function Get-MarkerLines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -notin @('.log', '.txt', '.csv', '.json', '.xml')) {
        return @()
    }

    return @(
        Select-String -LiteralPath $Path -Pattern $Pattern -AllMatches -ErrorAction Stop |
            ForEach-Object {
                $line = $_.Line
                $match = [regex]::Match(
                    $line,
                    $Pattern,
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                )
                if ($match.Success) {
                    $line.Substring($match.Index).Trim()
                }
            }
    )
}

$left = Read-Manifest -SnapshotPath $SnapshotA
$right = Read-Manifest -SnapshotPath $SnapshotB
$mapA = New-FileMap -Manifest $left.Manifest
$mapB = New-FileMap -Manifest $right.Manifest

$allKeys = @($mapA.Keys + $mapB.Keys | Sort-Object -Unique)
$comparisons = @()
$markerComparisons = @()

foreach ($key in $allKeys) {
    $fileA = $mapA[$key]
    $fileB = $mapB[$key]

    if ($null -eq $fileA) {
        $status = 'onlyB'
        $relativePath = $fileB.relativePath
    }
    elseif ($null -eq $fileB) {
        $status = 'onlyA'
        $relativePath = $fileA.relativePath
    }
    elseif ($fileA.sha256 -ceq $fileB.sha256) {
        $status = 'same'
        $relativePath = $fileA.relativePath
    }
    else {
        $status = 'different'
        $relativePath = $fileA.relativePath
    }

    $comparisons += [pscustomobject][ordered]@{
        relativePath = $relativePath
        status       = $status
        lengthA      = if ($null -eq $fileA) { $null } else { $fileA.lengthBytes }
        lengthB      = if ($null -eq $fileB) { $null } else { $fileB.lengthBytes }
        sha256A      = if ($null -eq $fileA) { $null } else { $fileA.sha256 }
        sha256B      = if ($null -eq $fileB) { $null } else { $fileB.sha256 }
    }

    if (($null -ne $fileA) -and ($null -ne $fileB)) {
        $pathA = Join-Path $left.Root $fileA.relativePath
        $pathB = Join-Path $right.Root $fileB.relativePath
        $markersA = @(Get-MarkerLines -Path $pathA -Pattern $MarkerPattern)
        $markersB = @(Get-MarkerLines -Path $pathB -Pattern $MarkerPattern)

        if (($markersA.Count -gt 0) -or ($markersB.Count -gt 0)) {
            $firstDifference = $null
            $maximum = [Math]::Max($markersA.Count, $markersB.Count)

            for ($index = 0; $index -lt $maximum; $index++) {
                $lineA = if ($index -lt $markersA.Count) { $markersA[$index] } else { $null }
                $lineB = if ($index -lt $markersB.Count) { $markersB[$index] } else { $null }

                if ($lineA -cne $lineB) {
                    $firstDifference = [ordered]@{
                        markerIndex = $index + 1
                        lineA       = $lineA
                        lineB       = $lineB
                    }
                    break
                }
            }

            $markerComparisons += [pscustomobject][ordered]@{
                relativePath    = $relativePath
                countA          = $markersA.Count
                countB          = $markersB.Count
                identical       = ($null -eq $firstDifference)
                firstDifference = $firstDifference
            }
        }
    }
}

$summary = [ordered]@{
    same                 = @($comparisons | Where-Object status -eq 'same').Count
    different            = @($comparisons | Where-Object status -eq 'different').Count
    onlyA                = @($comparisons | Where-Object status -eq 'onlyA').Count
    onlyB                = @($comparisons | Where-Object status -eq 'onlyB').Count
    markerFilesCompared  = $markerComparisons.Count
    markerFilesDifferent = @($markerComparisons | Where-Object identical -eq $false).Count
}

$report = [ordered]@{
    schemaVersion     = 1
    comparedAtUtc     = [DateTime]::UtcNow.ToString('o')
    markerPattern     = $MarkerPattern
    snapshotA         = [ordered]@{
        root       = $left.Root
        runId      = $left.Manifest.runId
        checkpoint = $left.Manifest.checkpoint
        pcLabel    = $left.Manifest.pcLabel
    }
    snapshotB         = [ordered]@{
        root       = $right.Root
        runId      = $right.Manifest.runId
        checkpoint = $right.Manifest.checkpoint
        pcLabel    = $right.Manifest.pcLabel
    }
    summary           = $summary
    files             = $comparisons
    markerComparisons = $markerComparisons
}

[pscustomobject]$summary | Format-List
$comparisons |
    Where-Object status -ne 'same' |
    Select-Object relativePath, status, lengthA, lengthB |
    Format-Table -AutoSize

if ($markerComparisons.Count -gt 0) {
    Write-Host 'Marker comparison:'
    $markerComparisons |
        Select-Object relativePath, countA, countB, identical |
        Format-Table -AutoSize
}
else {
    Write-Host "No lines matched marker pattern '$MarkerPattern'."
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportPathFull = [System.IO.Path]::GetFullPath($ReportPath)
    $reportParent = Split-Path -Parent $reportPathFull
    New-Item -ItemType Directory -Path $reportParent -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPathFull -Encoding UTF8
    Write-Host "Report: $reportPathFull"
}
