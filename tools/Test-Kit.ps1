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
    # Exercise script-relative defaults from copied scripts so the test catches
    # Windows PowerShell 5.1 parameter-binding regressions without leaving
    # generated diagnostics in the repository.
    $integrationTools = Join-Path $testRoot 'tools'
    $fakeCivRoot = Join-Path $testRoot 'fake-civ-root'
    New-Item -ItemType Directory -Path $integrationTools -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fakeCivRoot 'Logs') -Force | Out-Null
    'Synthetic Civ VI log' | Set-Content -LiteralPath (Join-Path $fakeCivRoot 'Logs\Lua.log') -Encoding UTF8
    @(
        'RenderWidth 3840'
        'RenderHeight 2160'
        'FullScreen 1'
        'EnableTuner 0'
        'PlayIntroVideo 1'
    ) | Set-Content -LiteralPath (Join-Path $fakeCivRoot 'AppOptions.txt') -Encoding UTF8
    @(
        'AutoEndTurn 1'
        'TutorialLevel 1'
        'HasChosenTutorialLevel 0'
    ) | Set-Content -LiteralPath (Join-Path $fakeCivRoot 'UserOptions.txt') -Encoding UTF8

    $preflightScript = Join-Path $integrationTools 'Test-Civ6Environment.ps1'
    $captureScript = Join-Path $integrationTools 'Capture-Civ6Snapshot.ps1'
    $optionsScript = Join-Path $integrationTools 'Set-Civ6AutomationOptions.ps1'
    Copy-Item -LiteralPath (Join-Path $toolsRoot 'Test-Civ6Environment.ps1') -Destination $preflightScript
    Copy-Item -LiteralPath (Join-Path $toolsRoot 'Capture-Civ6Snapshot.ps1') -Destination $captureScript
    Copy-Item -LiteralPath (Join-Path $toolsRoot 'Set-Civ6AutomationOptions.ps1') -Destination $optionsScript

    & $optionsScript -CivRoot $fakeCivRoot -RenderWidth 1600 -RenderHeight 900 -WarningAction SilentlyContinue
    $configuredAppOptions = Get-Content -LiteralPath (Join-Path $fakeCivRoot 'AppOptions.txt') -Raw
    $configuredUserOptions = Get-Content -LiteralPath (Join-Path $fakeCivRoot 'UserOptions.txt') -Raw
    foreach ($expectedOption in @('RenderWidth 1600', 'RenderHeight 900', 'FullScreen 0', 'EnableTuner 1', 'PlayIntroVideo 0')) {
        if ($configuredAppOptions -notmatch ('(?m)^' + [regex]::Escape($expectedOption) + '\r?$')) {
            throw "Automation options test did not set '$expectedOption'."
        }
    }
    if ($configuredUserOptions -notmatch '(?m)^AutoEndTurn 0\r?$') {
        throw 'Automation options test did not disable AutoEndTurn.'
    }
    if ($configuredUserOptions -notmatch '(?m)^TutorialLevel -1\r?$') {
        throw 'Automation options test did not disable tutorial advisor prompts.'
    }
    if ($configuredUserOptions -notmatch '(?m)^HasChosenTutorialLevel 1\r?$') {
        throw 'Automation options test did not mark the tutorial choice as complete.'
    }
    $optionBackups = @(Get-ChildItem -LiteralPath $fakeCivRoot -Filter '*.bak' -File)
    if ($optionBackups.Count -ne 2) {
        throw "Expected two option backups; found $($optionBackups.Count)."
    }
    Write-Host 'PASS: Civ VI automation options and backups.'

    & $preflightScript -Pc A -CivRoot $fakeCivRoot
    $preflightFiles = @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'preflight') -Filter '*.json' -File)
    if ($preflightFiles.Count -ne 1) {
        throw "Expected one default-path preflight report; found $($preflightFiles.Count)."
    }

    & $captureScript -Pc A -RunId TESTDEFAULT -Checkpoint smoke -CivRoot $fakeCivRoot
    $captureManifests = @(
        Get-ChildItem -LiteralPath (Join-Path $testRoot 'captures\TESTDEFAULT') `
            -Filter 'manifest.json' -File -Recurse
    )
    if ($captureManifests.Count -ne 1) {
        throw "Expected one default-path capture manifest; found $($captureManifests.Count)."
    }

    Write-Host 'PASS: Windows PowerShell script-relative default output paths.'

    $fakeWorkshopRoot = Join-Path $testRoot 'fake-workshop\12345'
    New-Item -ItemType Directory -Path (Join-Path $fakeWorkshopRoot 'gameplay') -Force | Out-Null
    @'
<Mod id="synthetic-risk" version="1">
  <Properties><Name>Synthetic Risk</Name></Properties>
  <InGameActions>
    <AddGameplayScripts id="risk"><File>gameplay/risk.lua</File></AddGameplayScripts>
  </InGameActions>
</Mod>
'@ | Set-Content -LiteralPath (Join-Path $fakeWorkshopRoot 'Synthetic.modinfo') -Encoding UTF8
    @'
local player = Players[Game.GetLocalPlayer()]
player:SetProperty("LOCAL_UI_CACHE", {})
'@ | Set-Content -LiteralPath (Join-Path $fakeWorkshopRoot 'gameplay\risk.lua') -Encoding UTF8

    $auditScript = Join-Path $toolsRoot 'Find-Civ6ModSyncRisks.ps1'
    $auditReport = Join-Path $testRoot 'mod-audit.json'
    & $auditScript -WorkshopRoot (Split-Path -Parent $fakeWorkshopRoot) -ReportPath $auditReport | Out-Null
    $auditResult = Get-Content -LiteralPath $auditReport -Raw | ConvertFrom-Json
    if ($auditResult.summary.critical -ne 1) {
        throw "Expected one critical synthetic mod finding; found $($auditResult.summary.critical)."
    }
    if ($auditResult.findings[0].modName -ne 'Synthetic Risk') {
        throw 'Synthetic mod audit did not preserve the manifest mod name.'
    }
    Write-Host 'PASS: static mod synchronization-risk audit.'

    $probeSource = Join-Path $toolsRoot '..\mod\QuickDealsDesyncProbe'
    $probeManifest = Get-Content -LiteralPath (Join-Path $probeSource 'QuickDealsDesyncProbe.modinfo') -Raw
    $probeLua = Get-Content -LiteralPath (Join-Path $probeSource 'QuickDealsDesyncProbe.lua') -Raw
    if ($probeManifest -notmatch '5aceed03-8639-4a81-8cbf-03f54d543502') {
        throw 'Quick Deals probe does not declare the expected Quick Deals dependency.'
    }
    foreach ($expectedProbeSource in @(
        'GameConfiguration.IsAnyMultiplayer()'
        'Game.GetLocalPlayer()'
        'ExposedMembers.QD'
        'cacheManager.SetCachedDeals(marker, true)'
        'QD_DESYNC_PROBE'
    )) {
        if (-not $probeLua.Contains($expectedProbeSource)) {
            throw "Quick Deals probe is missing expected source: '$expectedProbeSource'."
        }
    }
    foreach ($forbiddenProbeSource in @('os.execute', 'io.open', 'DllImport', 'LoadLibrary')) {
        if ($probeLua -match [regex]::Escape($forbiddenProbeSource)) {
            throw "Quick Deals probe contains forbidden instrumentation source: '$forbiddenProbeSource'."
        }
    }

    $probeInstallRoot = Join-Path $testRoot 'probe-mods'
    $probeInstaller = Join-Path $toolsRoot 'Install-QuickDealsDesyncProbe.ps1'
    & $probeInstaller -DestinationRoot $probeInstallRoot | Out-Null
    $installedProbeFiles = @(Get-ChildItem -LiteralPath (Join-Path $probeInstallRoot 'QuickDealsDesyncProbe') -File)
    if ($installedProbeFiles.Count -ne 3) {
        throw "Expected three installed probe files; found $($installedProbeFiles.Count)."
    }
    Write-Host 'PASS: controlled Quick Deals divergence probe and installer.'

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
