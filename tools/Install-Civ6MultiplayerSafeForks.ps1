[CmdletBinding()]
param(
    [ValidateSet('All', 'QuickDeals', 'MultiplayerHelper', 'TechCivicProgressPlus')]
    [string[]]$Target = @('All'),

    [string]$WorkshopRoot,

    [string]$DestinationRoot,

    [switch]$Replace
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required source file does not exist: '$Path'."
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -cne $Expected) {
        throw "Source hash mismatch for '$Path'. Expected '$Expected'; found '$actual'. The Workshop mod may have updated, so this patch must be reviewed before use."
    }
}

function Assert-DirectoryHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $root = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $rows = @(Get-ChildItem -LiteralPath $root -File -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relative`t$hash`n"
    } | Sort-Object)
    $inventory = $rows -join ''
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($inventory)
        $actual = ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }

    if ($actual -cne $Expected) {
        throw "Source tree hash mismatch for '$Path'. Expected '$Expected'; found '$actual'. The Workshop mod may have updated, so the complete source must be re-audited before use."
    }
}

function Update-ForkManifest {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$OriginalModID,
        [Parameter(Mandatory = $true)][string]$ForkModID,
        [Parameter(Mandatory = $true)][string]$ForkName,
        [Parameter(Mandatory = $true)][string]$ForkDescription
    )

    [xml]$document = Get-Content -LiteralPath $ManifestPath -Raw
    $root = $document.DocumentElement
    if ($null -eq $root -or $root.LocalName -ne 'Mod') {
        throw "Manifest '$ManifestPath' does not have a Mod document element."
    }

    $properties = $root.SelectSingleNode('./Properties')
    if ($null -eq $properties) {
        throw "Manifest '$ManifestPath' is missing root Properties."
    }
    $nameNode = $properties.SelectSingleNode('./Name')
    $descriptionNode = $properties.SelectSingleNode('./Description')
    if ($null -eq $nameNode -or $null -eq $descriptionNode) {
        throw "Manifest '$ManifestPath' is missing root Name or Description."
    }

    $root.SetAttribute('id', $ForkModID)
    $nameNode.InnerText = $ForkName
    $descriptionNode.InnerText = $ForkDescription

    $blocks = $root.SelectSingleNode('./Blocks')
    if ($null -eq $blocks) {
        $blocks = $document.CreateElement('Blocks')
        [void]$root.InsertAfter($blocks, $properties)
    }

    $existingBlock = $blocks.SelectSingleNode("./Mod[@id='$OriginalModID']")
    if ($null -eq $existingBlock) {
        $originalBlock = $document.CreateElement('Mod')
        $originalBlock.SetAttribute('id', $OriginalModID)
        $originalBlock.SetAttribute('title', 'Original incompatible mod')
        [void]$blocks.AppendChild($originalBlock)
    }

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $settings.NewLineChars = [Environment]::NewLine
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace

    $writer = [System.Xml.XmlWriter]::Create($ManifestPath, $settings)
    try {
        $document.Save($writer)
    }
    finally {
        $writer.Dispose()
    }
}

function New-ForkDestination {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ExpectedForkID
    )

    $destination = [System.IO.Path]::GetFullPath((Join-Path $script:ResolvedDestinationRoot $Name))
    $destinationPrefix = $script:ResolvedDestinationRoot.TrimEnd('\') + '\'
    if (-not $destination.StartsWith($destinationPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Fork destination escapes the configured Mods directory: '$destination'."
    }
    if (Test-Path -LiteralPath $destination) {
        $existingManifests = @(Get-ChildItem -LiteralPath $destination -Filter '*.modinfo' -File)
        $recognized = $false
        foreach ($manifest in $existingManifests) {
            [xml]$existing = Get-Content -LiteralPath $manifest.FullName -Raw
            if ([string]$existing.Mod.id -ceq $ExpectedForkID) {
                $recognized = $true
                break
            }
        }
        if (-not $recognized) {
            throw "Refusing to replace unrecognized destination '$destination'."
        }
        if (-not $Replace) {
            throw "Fork already exists at '$destination'. Pass -Replace to update the recognized fork."
        }
        Remove-Item -LiteralPath $destination -Recurse -Force
    }

    Copy-Item -LiteralPath $Source -Destination $destination -Recurse
    return $destination
}

function Rename-Manifest {
    param(
        [Parameter(Mandatory = $true)][string]$OriginalPath,
        [Parameter(Mandatory = $true)][string]$NewName
    )

    $newPath = Join-Path (Split-Path -Parent $OriginalPath) $NewName
    Move-Item -LiteralPath $OriginalPath -Destination $newPath
    return $newPath
}

if ([string]::IsNullOrWhiteSpace($WorkshopRoot)) {
    $workshopCandidates = New-Object System.Collections.Generic.List[string]
    try {
        $steamRegistryPath = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath
        if (-not [string]::IsNullOrWhiteSpace($steamRegistryPath)) {
            $workshopCandidates.Add((Join-Path $steamRegistryPath 'steamapps\workshop\content\289070'))
        }
    }
    catch {
        # Steam's per-user registry entry is optional.
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $workshopCandidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\workshop\content\289070'))
    }
    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem)) {
        $workshopCandidates.Add((Join-Path $drive.Root 'SteamLibrary\steamapps\workshop\content\289070'))
        $workshopCandidates.Add((Join-Path $drive.Root 'Steam\steamapps\workshop\content\289070'))
    }
    $workshopMatches = @($workshopCandidates | Select-Object -Unique | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_ '2460661464') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $_ '2604740398') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $_ '2357532056') -PathType Container)
    } | Select-Object -First 1)
    if ($workshopMatches.Count -eq 0) {
        throw 'Could not auto-detect a Steam Workshop root containing all three source mods. Pass -WorkshopRoot with the ...\steamapps\workshop\content\289070 directory.'
    }
    $WorkshopRoot = [string]$workshopMatches[0]
}

$resolvedWorkshopRoot = [System.IO.Path]::GetFullPath($WorkshopRoot)
if (-not (Test-Path -LiteralPath $resolvedWorkshopRoot -PathType Container)) {
    throw "Workshop root does not exist: '$resolvedWorkshopRoot'."
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

$script:ResolvedDestinationRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
New-Item -ItemType Directory -Path $script:ResolvedDestinationRoot -Force | Out-Null

$selectedTargets = if ($Target -contains 'All') {
    @('QuickDeals', 'MultiplayerHelper', 'TechCivicProgressPlus')
}
else {
    @($Target | Select-Object -Unique)
}

$installed = New-Object System.Collections.Generic.List[object]

if ($selectedTargets -contains 'QuickDeals') {
    $source = Join-Path $resolvedWorkshopRoot '2460661464'
    $sourceManifest = Join-Path $source 'QuickDeals.modinfo'
    $sourceGameplay = Join-Path $source 'gameplay\qd_cachemanager.lua'
    Assert-FileHash $sourceManifest '5CFAE93147317B566885B044E015D6976C6E16A80E37F326A2E5FEA3992748F8'
    Assert-FileHash $sourceGameplay '6AEB120EB3FE98644D370390C49BEF35823E8EB9CBBB763F83BBD622E68B7629'
    Assert-DirectoryHash $source 'B9DD64B6CC7901C3C8DB5727469D660A943B7DF60F29C04CF286513618E97D7C'

    $forkID = '7e3bce14-956e-4223-ae08-b1788ae7d257'
    $destination = New-ForkDestination $source 'QuickDealsMultiplayerSafe' $forkID
    $manifest = Rename-Manifest (Join-Path $destination 'QuickDeals.modinfo') 'QuickDealsMultiplayerSafe.modinfo'
    Update-ForkManifest $manifest '5aceed03-8639-4a81-8cbf-03f54d543502' $forkID `
        'Quick Deals - Multiplayer Safe' `
        'Quick Deals with its presentation cache kept in process-local Lua memory instead of synchronized Player properties.'

    $safeCache = @'
-- Multiplayer-safe Quick Deals cache.
-- Presentation data stays process-local and never enters serialized GameCore.
CacheManager = {};

local m_SellableDeals = {};
local m_BuyableDeals = {};

CacheManager.GetCachedDeals = function(isSell:boolean)
    if isSell then
        return m_SellableDeals;
    end
    return m_BuyableDeals;
end

CacheManager.SetCachedDeals = function(deals:table, isSell:boolean)
    if isSell then
        m_SellableDeals = deals or {};
    else
        m_BuyableDeals = deals or {};
    end
end

ExposedMembers.QD = ExposedMembers.QD or {};
ExposedMembers.QD.CacheManager = CacheManager;
'@
    Write-Utf8NoBom (Join-Path $destination 'gameplay\qd_cachemanager.lua') $safeCache

    $verified = Get-Content -LiteralPath (Join-Path $destination 'gameplay\qd_cachemanager.lua') -Raw
    if ($verified -match 'SetProperty|GetProperty|Game\.GetLocalPlayer') {
        throw 'Quick Deals safe fork still contains synchronized cache access.'
    }
    $installed.Add([pscustomobject]@{ Target = 'QuickDeals'; ModID = $forkID; Path = $destination })
}

if ($selectedTargets -contains 'TechCivicProgressPlus') {
    $source = Join-Path $resolvedWorkshopRoot '2604740398'
    $sourceManifest = Join-Path $source 'TechCivicProgressPlus.modinfo'
    $sourceGameplay = Join-Path $source 'CheckOverflow.lua'
    Assert-FileHash $sourceManifest '70B768D711F9F0BAB6B0EA211C76D3BB200A7DDBB50D96059FDEFA9C02B0CEC7'
    Assert-FileHash $sourceGameplay '677C6EC5BF493C028EA6EFB8E472518D6B084ABBFEFA8492280C0C4AF4C0A1FA'
    Assert-DirectoryHash $source '390808EF187DC71326FCA724E7CA54C33A7628E32DCA5F2DF1FA1260A9BA8F89'

    $forkID = '1317e07f-bc75-4321-ac90-4b76f43d8bec'
    $destination = New-ForkDestination $source 'TechCivicProgressPlusMultiplayerSafe' $forkID
    $manifest = Rename-Manifest (Join-Path $destination 'TechCivicProgressPlus.modinfo') 'TechCivicProgressPlusMultiplayerSafe.modinfo'
    Update-ForkManifest $manifest '8446e6e9-7703-434d-ba10-0bd70a291d28' $forkID `
        'Tech Civic Progress Plus - Multiplayer Safe' `
        'Tech and civic progress UI with mutation-based overflow probing disabled. It never rewrites live research or civic state.'

    $safeOverflow = @'
-- Multiplayer-safe compatibility surface for Tech Civic Progress Plus.
-- The original overflow estimate temporarily rewrote synchronized research
-- state. A read-only exact equivalent is unavailable, so the estimate is
-- deliberately disabled while the remaining tooltip UI stays loaded.
print('loading multiplayer-safe tech overflow compatibility layer')

ExposedMembers.TechCivicProgress = ExposedMembers.TechCivicProgress or {}
ExposedMembers.TechCivicProgress.overflow_tech = 0
ExposedMembers.TechCivicProgress.overflow_civic = 0

function GetTechOverflow()
    ExposedMembers.TechCivicProgress.overflow_tech = 0
end

function GetCivicOverflow()
    ExposedMembers.TechCivicProgress.overflow_civic = 0
end


ExposedMembers.TechCivicProgress.GetTechOverflow = GetTechOverflow
ExposedMembers.TechCivicProgress.GetCivicOverflow = GetCivicOverflow
ExposedMembers.TechCivicProgress.GetCivicProgress = nil
'@
    Write-Utf8NoBom (Join-Path $destination 'CheckOverflow.lua') $safeOverflow

    $verified = Get-Content -LiteralPath (Join-Path $destination 'CheckOverflow.lua') -Raw
    if ($verified -match 'SetResearchProgress|SetCultureProgress|SetProgressingCivic|Game\.GetLocalPlayer') {
        throw 'Tech Civic Progress Plus safe fork still contains mutation-based overflow probing.'
    }
    $installed.Add([pscustomobject]@{ Target = 'TechCivicProgressPlus'; ModID = $forkID; Path = $destination })
}

if ($selectedTargets -contains 'MultiplayerHelper') {
    $source = Join-Path $resolvedWorkshopRoot '2357532056'
    $sourceManifest = Join-Path $source 'MPH Core v1xx.modinfo'
    $sourceGameplay = Join-Path $source 'data\MP_helper.lua'
    Assert-FileHash $sourceManifest '62EDE6DF657E3FDF25BC321D77087BCB49B6F8BE5047C7B76710D7C7A845FAFE'
    Assert-FileHash $sourceGameplay 'DFCDC6A642FCA9BBE569FDFDF1AAA029B717CD0603715A6B30F888ADD11361F8'
    Assert-DirectoryHash $source 'F74C19972F53A7C0CD56528CC4B62D0E5A568E60C59075A9F9B9CB80EBF0D79E'

    $forkID = '947f97ba-d2e8-49fe-af14-dd0432737259'
    $destination = New-ForkDestination $source 'MultiplayerHelperMultiplayerSafe' $forkID
    $manifest = Rename-Manifest (Join-Path $destination 'MPH Core v1xx.modinfo') 'MultiplayerHelperMultiplayerSafe.modinfo'
    Update-ForkManifest $manifest '619ac86e-d99d-4bf3-b8f0-8c5b8c402176' $forkID `
        'Multiplayer Helper 1.6.7 - Multiplayer Safe' `
        'Multiplayer Helper with client-local GameCore mutations disabled. Drop freeze/restore, sudden-death destruction/property writes, automatic research/civic selection, and diagnostic RNG consumption are disabled.'

    $gameplayPath = Join-Path $destination 'data\MP_helper.lua'
    $gameplay = Get-Content -LiteralPath $gameplayPath -Raw
    $safeTurnBlock = @'
function OnGameTurnStarted(turn)
    -- Wall-clock text is retained for diagnostics; synchronized RNG is not consumed.
    g_turn_start_time = os.date('%Y-%m-%d %H:%M:%S')
    b_clean = false
    b_debuff = false
    print("OnGameTurnStarted: Turn", turn, g_turn_start_time)
end

function NoMoreStack()
    -- Disabled: this UI/tournament helper must not select technologies or civics
    -- by directly mutating GameCore on each client.
end


'@
    $turnPattern = '(?ms)^function OnGameTurnStarted\(turn\).*?^-- ===========================================================================\s*\r?\n--\s*REMOTE EVENTS \(UI -> SCRIPT\)\s*\r?\n-- ===========================================================================\s*'
    $updated = [regex]::Replace(
        $gameplay,
        $turnPattern,
        ($safeTurnBlock + "-- ===========================================================================`r`n-- REMOTE EVENTS (UI -> SCRIPT)`r`n-- ===========================================================================`r`n"),
        1
    )
    if ($updated -ceq $gameplay) {
        throw 'Could not replace Multiplayer Helper turn mutation block.'
    }

    $safeRemoteBlock = @'
function OnDrop(playerID:number)
    print("MPH multiplayer-safe: drop freeze disabled for player", playerID)
end
LuaEvents.UICPLPlayerDrop.Add(OnDrop)

function OnConnect(playerID:number)
    print("MPH multiplayer-safe: reconnect restore disabled for player", playerID)
end
LuaEvents.UICPLPlayerConnect.Add(OnConnect)

function OnTimerExpires(playerID:number)
    print("MPH multiplayer-safe: sudden-death destruction disabled for player", playerID)
end
LuaEvents.UISuddenDeathTimeExpireAI.Add(OnTimerExpires)

function OnTimeSaved(timeleft:number)
    print("MPH multiplayer-safe: synchronized timer property write disabled", timeleft)
end
LuaEvents.UISuddenDeathSavetime.Add(OnTimeSaved)


'@
    $remotePattern = '(?ms)^function OnDrop\(playerID:number\).*?^-- ===========================================================================\s*\r?\n--\s*Utils\s*\r?\n-- ===========================================================================\s*'
    $updatedRemote = [regex]::Replace(
        $updated,
        $remotePattern,
        ($safeRemoteBlock + "-- ===========================================================================`r`n-- Utils`r`n-- ===========================================================================`r`n"),
        1
    )
    if ($updatedRemote -ceq $updated) {
        throw 'Could not replace Multiplayer Helper UI-event mutation block.'
    }
    Write-Utf8NoBom $gameplayPath $updatedRemote

    $verified = Get-Content -LiteralPath $gameplayPath -Raw
    foreach ($forbidden in @(
        'Game.GetRandNum'
        'SetProgressingCivic'
        'SetResearchingTech'
        'UnitManager.ChangeMovesRemaining'
        'CityManager.DestroyCity'
        'pPlayerUnits:Destroy'
        'Game:SetProperty'
    )) {
        if ($verified -match [regex]::Escape($forbidden)) {
            throw "Multiplayer Helper safe fork still contains forbidden gameplay mutation '$forbidden'."
        }
    }
    $installed.Add([pscustomobject]@{ Target = 'MultiplayerHelper'; ModID = $forkID; Path = $destination })
}

foreach ($fork in $installed) {
    $manifest = @(Get-ChildItem -LiteralPath $fork.Path -Filter '*.modinfo' -File)
    if ($manifest.Count -ne 1) {
        throw "Expected one manifest in '$($fork.Path)'; found $($manifest.Count)."
    }
    [xml]$xml = Get-Content -LiteralPath $manifest[0].FullName -Raw
    if ($xml.Mod.id -cne $fork.ModID) {
        throw "Generated manifest ID mismatch for '$($fork.Target)'."
    }
}

Write-Host "Installed $($installed.Count) multiplayer-safe fork(s) into '$script:ResolvedDestinationRoot'."
$installed | Format-Table Target, ModID, Path -AutoSize
$installed
