# Static analysis: Civ VI synchronization and the Quick Deals risk

## Result

The strongest code-level desync candidate in the currently installed mod set is **Quick Deals** (Steam Workshop item `2460661464`). It contains a multiplayer-reachable path that writes client-local UI cache data into Civ VI's serialized gameplay state.

This is a confirmed defect in the mod's state-management design. It is not yet proof that Quick Deals caused the campaign's historical reloads: the paired lab captures do not contain a genuine `AutoArchive out of sync` event, and the two observed access violations were produced while instrumentation was attached. A clean A/B test remains necessary for causal attribution.

## What the native game reveals

Civ VI does not install its C++ source, but its native executables retain enough diagnostic strings and source-file paths to reconstruct the relevant recovery path. `CivilizationVI_DX12.exe` contains:

- `AutoArchive out of sync (data hash mismatch) Player=%i AutoArchive=%s HostDataHash=%u RemoteDataHash=%u`
- `NetSyncSnapshot : numDeltaArchives=%i, numCallstacks=%i, numDeleteArchives=%i, numCreateArchives=%i, numPriorities=%i, unitTest=%i, testSync=%i`
- `No desynced AutoVariables found in host delta data... Requesting full snapshot`
- `GAMECORE_UNSERIALIZE_GAMESTATE Begin`
- embedded paths including `CivTech\Libs\AutoVariable\FAutoArchive.cpp` and `Civ6\Src\App\GameCoreSupport\GameCore_Serializer.cpp`

The resulting model is:

1. GameCore state is divided into synchronized `FAutoArchive` containers.
2. The host compares archive hashes with each remote client.
3. A mismatch triggers a delta snapshot.
4. If a safe delta cannot be localized or applied, Civ VI requests and unserializes a full snapshot.
5. The UI identifies that operation as a resync load (`UI.IsResyncLoadInProgress()`), which is the all-player loading/reload behavior being investigated.

The shipped Lua reinforces that `Game:SetProperty`, `Player:SetProperty`, and related object properties are durable GameCore state. Official scenarios use those APIs for scenario state, read the properties back after load, and expose them to UI code. They are not an appropriate home for a per-client UI cache unless all clients are guaranteed to write identical values to identical objects in identical order.

## Quick Deals defect

Quick Deals declares `gameplay/qd_cachemanager.lua` through `AddGameplayScripts`. The script exposes this gameplay-context cache to the UI:

```lua
local player = Players[Game.GetLocalPlayer()]
player:SetProperty("QD_SELLABLE_DEALS", deals)
player:SetProperty("QD_BUYABLE_DEALS", deals)
```

Its UI script `ui/qd_launchbutton.lua` calls `CheckAvailableDeals()` from `OnLoadGameViewStateDone()` without a multiplayer guard. That function:

1. calculates deals from the local human's perspective;
2. reads cache properties from the local human player;
3. builds new Lua tables; and
4. always calls `SetCachedDeals()` twice.

`Game.GetLocalPlayer()` returns a different player ID on each human's machine. Consequently, during the same load:

- PC A can write `QD_*` properties to Player A;
- PC B can write `QD_*` properties to Player B; and
- neither write is guaranteed to be reproduced in the other client's simulation.

That is precisely the class of divergent state that Civ VI's AutoArchive hash comparison is designed to detect. Several of the cache-building paths also use `pairs()`. Lua does not promise stable traversal order for `pairs()`, which adds a secondary table-order risk if property serialization preserves insertion details.

The later `OnPlayerTurnActivated()` refresh does contain `not GameConfiguration.IsAnyMultiplayer()`, but that guard does not cover the initial `OnLoadGameViewStateDone()` call. Notification suppression in multiplayer also occurs only after the cache writes.

## Other installed property writer

Detailed Wonder Reminder (Workshop item `2794603014`) stores its reminder table in `Game:SetProperty('knm_reminder_wonders', ...)` after `Events.WonderCompleted`. It does not use `Game.GetLocalPlayer()` and the event should normally run deterministically on every client, so it is a lower-priority review item. It still puts UI metadata into synchronized state and should be included in a later A/B test if removing Quick Deals does not resolve the problem.

## Recommended validation

Use an existing problematic save if possible so the test reaches the known failure zone quickly.

1. Disable Quick Deals on both PCs; change nothing else.
2. Verify the ordered enabled-mod list is identical on both PCs.
3. Load through the normal Internet multiplayer path and play across at least the usual failure interval.
4. If the reload disappears in two independent runs, re-enable only Quick Deals and repeat from the same save/checkpoint.
5. Capture both PCs immediately if the reload returns, before closing Civ VI.

The strongest causal result is `fails with Quick Deals → passes without it → fails after re-enabling it`. A single pass without the mod is encouraging but not conclusive.

## Safe fix direction

Do not patch the Workshop directory in place; Steam can replace it at any time. The durable fix belongs upstream in Quick Deals or in a separately maintained replacement:

- keep `QD_SELLABLE_DEALS` and `QD_BUYABLE_DEALS` as UI-context local Lua tables;
- remove the `AddGameplayScripts` cache bridge; and
- never use `Game/Player/City/Unit/Plot:SetProperty` for purely local presentation caches.

Until that change is available and validated, disabling Quick Deals in multiplayer is safer than attempting to mask the write with another compatibility mod. A second mod cannot reliably unregister or override the original gameplay action.

## Re-run the static audit

```powershell
.\tools\Find-Civ6ModSyncRisks.ps1 `
  -WorkshopRoot 'F:\SteamLibrary\steamapps\workshop\content\289070' `
  -ReportPath '.\reports\mod-sync-risks.json'
```

The scanner is intentionally conservative. `critical` means a manifest-loaded gameplay script contains both a serialized property write and `Game.GetLocalPlayer()`. `review` means it writes properties but requires human inspection for deterministic triggers and values. The scanner identifies risk patterns; it does not prove a desync by itself.
