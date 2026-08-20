# Civ VI Desync Investigation Handoff

## Current objective

Confirm whether Quick Deals causes the recurring Civilization VI multiplayer reload/desync, then isolate and fix any remaining trigger.

## Current phase

Static-analysis lead found; next phase is a clean Quick Deals A/B validation using the normal Internet multiplayer path.

## Working hypothesis

Quick Deals is the leading hypothesis. Its UI calls an `AddGameplayScripts` cache bridge on every game-view load. That bridge chooses `Players[Game.GetLocalPlayer()]` and writes local deal-cache tables through `Player:SetProperty`, so different clients can mutate different serialized simulation objects. Civ VI's native diagnostic strings show that mismatched AutoArchive hashes trigger delta/full snapshots and the visible resync load.

## What exists

- A fixed experiment ladder and turn/action script.
- Read-only PowerShell preflight, snapshot, and comparison tools.
- An experiment-record template.
- Marker-aware comparison support for future `CIV6_SYNC_PROBE` instrumentation.
- A static mod synchronization-risk scanner (`tools/Find-Civ6ModSyncRisks.ps1`).
- A code-level report (`docs/STATIC-ANALYSIS.md`) documenting Civ VI's resync pipeline and the Quick Deals defect.
- A scan of all 20 currently installed Workshop manifests: Quick Deals is the sole critical finding; Detailed Wonder Reminder is the sole lower-priority review item.

## Important limitation

The defect is proven, but historical causation is not. Existing paired captures contain no genuine `AutoArchive out of sync` marker. The observed access violations occurred with instrumentation attached and must not be presented as Quick Deals evidence.

## Next actions

1. Disable Quick Deals on both PCs while holding the save, host, network mode, DLC, other mods, and action sequence fixed.
2. Run through the normal Internet multiplayer path across the usual failure interval twice.
3. Re-enable only Quick Deals and repeat from the same save/checkpoint.
4. Capture paired logs immediately if a reload occurs; do not attach FireTuner.
5. If Quick Deals is causal, fix it upstream or replace its synchronized property cache with UI-local Lua tables. Do not patch the Steam Workshop directory in place.
6. If it is not causal, repeat the same A/B process with Detailed Wonder Reminder, then bisect the remaining mod set.

## Questions for the first session

- Does the problematic save run cleanly twice with Quick Deals disabled?
- Does the reload return after Quick Deals is re-enabled?
- What exact action and turn immediately precede the first reload?
- Does a clean capture name the mismatched AutoArchive?
