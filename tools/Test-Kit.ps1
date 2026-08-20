[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$toolsRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$scriptFiles = @(Get-ChildItem -LiteralPath $toolsRoot -Filter '*.ps1' -File | Sort-Object Name)
if ($scriptFiles.Count -eq 0) {
    throw "No PowerShell scripts found in '$toolsRoot'."
}

foreach ($scriptFile in $scriptFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if (@($parseErrors).Count -gt 0) {
        $details = @($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "PowerShell parse failure in '$($scriptFile.Name)': $details"
    }

    Write-Host "PASS syntax: $($scriptFile.Name)"
}

$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testLeaf = 'civ6-desync-kit-test-{0}' -f ([guid]::NewGuid().ToString('N'))
$testRoot = Join-Path $temporaryBase $testLeaf

try {
    $snapshotA = Join-Path $testRoot 'snapshot-a'
    $snapshotB = Join-Path $testRoot 'snapshot-b'
    $reportPath = Join-Path $testRoot 'comparison.json'
    New-Item -ItemType Directory -Path (Join-Path $snapshotA 'logs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $snapshotB 'logs') -Force | Out-Null

    $logA = Join-Path $snapshotA 'logs\Lua.log'
    $logB = Join-Path $snapshotB 'logs\Lua.log'
    @(
        'Lua: CIV6_SYNC_PROBE turn=1 hash=aaaa'
        'Lua: CIV6_SYNC_PROBE turn=2 hash=bbbb'
    ) | Set-Content -LiteralPath $logA -Encoding UTF8
    @(
        'Lua: CIV6_SYNC_PROBE turn=1 hash=aaaa'
        'Lua: CIV6_SYNC_PROBE turn=2 hash=cccc'
    ) | Set-Content -LiteralPath $logB -Encoding UTF8

    $manifestA = [ordered]@{
        schemaVersion = 1
        runId         = 'TEST'
        checkpoint    = 'synthetic'
        pcLabel       = 'A'
        files         = @(
            [ordered]@{
                relativePath = 'logs\Lua.log'
                lengthBytes  = (Get-Item -LiteralPath $logA).Length
                sha256       = (Get-FileHash -LiteralPath $logA -Algorithm SHA256).Hash
            }
        )
    }
    $manifestB = [ordered]@{
        schemaVersion = 1
        runId         = 'TEST'
        checkpoint    = 'synthetic'
        pcLabel       = 'B'
        files         = @(
            [ordered]@{
                relativePath = 'logs\Lua.log'
                lengthBytes  = (Get-Item -LiteralPath $logB).Length
                sha256       = (Get-FileHash -LiteralPath $logB -Algorithm SHA256).Hash
            }
        )
    }

    $manifestA | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $snapshotA 'manifest.json') -Encoding UTF8
    $manifestB | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $snapshotB 'manifest.json') -Encoding UTF8

    $compareScript = Join-Path $toolsRoot 'Compare-Civ6Snapshots.ps1'
    & $compareScript `
        -SnapshotA $snapshotA `
        -SnapshotB $snapshotB `
        -ReportPath $reportPath

    $result = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($result.summary.different -ne 1) {
        throw "Expected one different file; found $($result.summary.different)."
    }
    if ($result.summary.markerFilesDifferent -ne 1) {
        throw "Expected one marker-bearing file to differ; found $($result.summary.markerFilesDifferent)."
    }
    if ($result.markerComparisons[0].firstDifference.markerIndex -ne 2) {
        throw 'Expected the first canonical marker difference at marker index 2.'
    }

    Write-Host 'PASS: kit syntax and synthetic comparison test succeeded.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        $isInsideTemp = $resolvedTestRoot.StartsWith(
            $temporaryBase,
            [System.StringComparison]::OrdinalIgnoreCase
        )
        $hasExpectedLeaf = (Split-Path -Leaf $resolvedTestRoot) -like 'civ6-desync-kit-test-*'

        if (-not $isInsideTemp -or -not $hasExpectedLeaf) {
            throw "Refusing to remove unexpected test path '$resolvedTestRoot'."
        }

        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
