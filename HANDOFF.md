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
- Controlled validation mod `mod/QuickDealsDesyncProbe`, which calls Quick Deals' exact cache bridge with a client-specific marker after multiplayer game-view load.
- An installer and evidence contract for experiment `QDP001`; all static and synthetic kit tests pass.

## QDP001 deployment state

- PC A: fully prepared without launching Civ VI. Probe installed at `C:\Users\99709\OneDrive\Documents\My Games\Sid Meier's Civilization VI\Mods\QuickDealsDesyncProbe`; all three installed hashes match the repository; Quick Deals and Quick Deals Desync Probe are enabled in selected offline mod group 2; other community mods remain disabled; `EnableTuner 0`; Civ VI stopped.
- PC A rollback: pre-edit database backup is `C:\Users\99709\AppData\Local\Firaxis Games\Sid Meier's Civilization VI\Mods.sqlite.QDP001-20260821T010918413Z.bak`.
- PC A baseline: `captures/QDP001/pre-run-PCA-20260821T010918697Z` contains the local pre-run snapshot and is intentionally ignored by Git.
- PC B: not yet deployed because the previously verified SSH endpoint `192.168.50.36:22` is unreachable. Do not bypass host-key verification or scan unrelated LAN devices.
- The probe uses no FireTuner, debugger, native hook, or memory modification.
- Both PCs must have byte-identical probe files and Quick Deals enabled before the controlled run.

## Important limitation

The defect is proven, but historical causation is not. Existing paired captures contain no genuine `AutoArchive out of sync` marker. The observed access violations occurred with instrumentation attached and must not be presented as Quick Deals evidence.

## Next actions

1. Restore PC B reachability at its verified SSH endpoint or obtain its new IP and independently verify the same stored ED25519 host fingerprint.
2. Deploy and hash-compare `QuickDealsDesyncProbe` on PC B.
3. Enable Quick Deals and Quick Deals Desync Probe on both PCs.
4. Enter one normal Internet multiplayer game and capture both clients' `QD_DESYNC_PROBE` markers plus native snapshot/desync markers.
5. If the native mismatch follows the controlled write, implement the general deterministic-state guard and Quick Deals adapter; do not patch the Workshop directory in place.

## Questions for the first session

- Does the problematic save run cleanly twice with Quick Deals disabled?
- Does the reload return after Quick Deals is re-enabled?
- What exact action and turn immediately precede the first reload?
- Does a clean capture name the mismatched AutoArchive?
