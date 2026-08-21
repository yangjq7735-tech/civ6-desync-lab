[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkshopRoot,

    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$resolvedWorkshopRoot = [System.IO.Path]::GetFullPath($WorkshopRoot)
if (-not (Test-Path -LiteralPath $resolvedWorkshopRoot -PathType Container)) {
    throw "Workshop root does not exist: '$resolvedWorkshopRoot'."
}

function Get-ModName {
    param(
        [xml]$Manifest,
        [System.IO.FileInfo]$ManifestFile
    )

    $nameNode = $Manifest.SelectSingleNode("//*[local-name()='Properties']/*[local-name()='Name']")
    if ($null -ne $nameNode -and -not [string]::IsNullOrWhiteSpace($nameNode.InnerText)) {
        $name = $nameNode.InnerText.Trim()
        if ($name -like 'LOC_*') {
            $localizedNode = $Manifest.SelectSingleNode(
                "//*[local-name()='LocalizedText']/*[local-name()='Text' and @id='$name']/*[local-name()='en_US']"
            )
            if ($null -ne $localizedNode -and -not [string]::IsNullOrWhiteSpace($localizedNode.InnerText)) {
                return $localizedNode.InnerText.Trim()
            }
        }
        return $name
    }

    return $ManifestFile.BaseName
}

$findings = New-Object System.Collections.Generic.List[object]
$manifestFiles = @(Get-ChildItem -LiteralPath $resolvedWorkshopRoot -Filter '*.modinfo' -File -Recurse | Sort-Object FullName)

foreach ($manifestFile in $manifestFiles) {
    try {
        [xml]$manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw
    }
    catch {
        $findings.Add([pscustomobject][ordered]@{
            severity       = 'warning'
            modName        = $manifestFile.BaseName
            manifest       = $manifestFile.FullName
            script         = $null
            propertyWrites = 0
            directMutations = 0
            localIdentity  = $false
            uiEventBridge  = $false
            unorderedPairs = $false
            reason         = "Manifest could not be parsed: $($_.Exception.Message)"
        })
        continue
    }

    $modName = Get-ModName -Manifest $manifest -ManifestFile $manifestFile
    $gameplayFileNodes = @($manifest.SelectNodes(
        "//*[local-name()='AddGameplayScripts' or local-name()='GameplayScripts']/*[local-name()='File']"
    ))

    foreach ($fileNode in $gameplayFileNodes) {
        $relativeScript = $fileNode.InnerText.Trim()
        if ([string]::IsNullOrWhiteSpace($relativeScript) -or $relativeScript -notmatch '(?i)\.lua$') {
            continue
        }

        $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $manifestFile.DirectoryName $relativeScript))
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            $findings.Add([pscustomobject][ordered]@{
                severity       = 'warning'
                modName        = $modName
                manifest       = $manifestFile.FullName
                script         = $scriptPath
                propertyWrites = 0
                directMutations = 0
                localIdentity  = $false
                uiEventBridge  = $false
                unorderedPairs = $false
                reason         = 'Gameplay script declared by manifest was not found.'
            })
            continue
        }

        $source = Get-Content -LiteralPath $scriptPath -Raw
        $propertyWriteMatches = @([regex]::Matches($source, '(?im)(?:\:|\.)SetProperty\s*\('))
        $directMutationMatches = @([regex]::Matches(
            $source,
            '(?im)(?:\:|\.)Set(?:Property|ResearchProgress|CulturalProgress|ProgressingCivic|ResearchingTech)\s*\(|UnitManager\.ChangeMovesRemaining\s*\(|CityManager\.DestroyCity\s*\(|(?:\:|\.)Destroy\s*\('
        ))
        if ($directMutationMatches.Count -eq 0) {
            continue
        }

        $usesLocalIdentity = $source -match '(?i)Game\.GetLocalPlayer\s*\('
        $usesUiEventBridge = $source -match '(?im)\b(?:LuaEvents|UIEvents|SDEvents)\.[A-Za-z0-9_]+\.Add\s*\('
        $usesUnorderedPairs = $source -match '(?m)\bpairs\s*\('
        $severity = if ($usesLocalIdentity -or $usesUiEventBridge) { 'critical' } else { 'review' }
        $reason = if ($usesLocalIdentity) {
            'Gameplay script combines client-local player identity with direct GameCore mutation; clients can mutate different simulation state.'
        }
        elseif ($usesUiEventBridge) {
            'Gameplay script lets client-local UI/Lua events invoke direct GameCore mutations without a synchronized player operation.'
        }
        else {
            'Gameplay script directly mutates GameCore; verify every mutation is triggered deterministically with identical values on every client.'
        }

        if ($usesUnorderedPairs) {
            $reason += ' It also uses pairs(), so table construction/serialization order deserves review.'
        }

        $findings.Add([pscustomobject][ordered]@{
            severity       = $severity
            modName        = $modName
            manifest       = $manifestFile.FullName
            script         = $scriptPath
            propertyWrites = $propertyWriteMatches.Count
            directMutations = $directMutationMatches.Count
            localIdentity  = $usesLocalIdentity
            uiEventBridge  = $usesUiEventBridge
            unorderedPairs = $usesUnorderedPairs
            reason         = $reason
        })
    }
}

$severityOrder = @{ critical = 0; review = 1; warning = 2 }
$orderedFindings = @($findings | Sort-Object @{ Expression = { $severityOrder[$_.severity] } }, modName, script)
$summary = [ordered]@{
    workshopRoot     = $resolvedWorkshopRoot
    scannedManifests = $manifestFiles.Count
    findings         = $orderedFindings.Count
    critical         = @($orderedFindings | Where-Object { $_.severity -eq 'critical' }).Count
    review           = @($orderedFindings | Where-Object { $_.severity -eq 'review' }).Count
    warning          = @($orderedFindings | Where-Object { $_.severity -eq 'warning' }).Count
}

Write-Host ("Scanned {0} mod manifests; {1} critical, {2} review, {3} warning." -f `
    $summary.scannedManifests, $summary.critical, $summary.review, $summary.warning)

foreach ($finding in $orderedFindings) {
    Write-Host ("[{0}] {1}: {2}" -f $finding.severity.ToUpperInvariant(), $finding.modName, $finding.script)
    Write-Host ("  {0}" -f $finding.reason)
}

$result = [ordered]@{
    schemaVersion = 2
    generatedUtc  = [DateTime]::UtcNow.ToString('o')
    summary       = $summary
    findings      = $orderedFindings
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $resolvedReportPath = [System.IO.Path]::GetFullPath($ReportPath)
    $reportDirectory = Split-Path -Parent $resolvedReportPath
    if (-not [string]::IsNullOrWhiteSpace($reportDirectory)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedReportPath -Encoding UTF8
    Write-Host "Report: $resolvedReportPath"
}

$result
