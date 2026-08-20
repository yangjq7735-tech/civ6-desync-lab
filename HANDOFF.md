# Civ VI Desync Investigation Handoff

## Current objective

Produce a repeatable two-PC reproduction of Civilization VI's global multiplayer reload/desync behavior, then isolate the smallest mod/action combination that triggers it.

## Current phase

Phase 0: establish a clean Windows/LAN baseline and prove paired log capture.

## Working hypothesis

The all-player loading screen is Civ VI resynchronizing after simulations diverge. A mod, mod interaction, or content mismatch becomes the leading hypothesis if a fixed action reproduces the event on the same LAN.

## What exists

- A fixed experiment ladder and turn/action script.
- Read-only PowerShell preflight, snapshot, and comparison tools.
- An experiment-record template.
- Marker-aware comparison support for future `CIV6_SYNC_PROBE` instrumentation.

## Important limitation

Raw Civ VI logs are client-specific. Different file hashes do not prove simulation divergence. The first instrumented mod must serialize selected gameplay state canonically and print stable markers on every client.

## Next actions

1. Copy the kit to both PCs.
2. Run preflight and resolve environment mismatches.
3. Complete `V000` twice with no mods.
4. Compare paired captures and confirm the required logs are retained.
5. Add AI, rotate host, and then bisect the mod set.
6. Once a minimal failing action exists, implement a state-probe mod around that subsystem.
7. Only after the probe is proven, implement a deliberately divergent diagnostic mod.

## Questions for the first session

- Do both PCs use Steam, Epic, or a mix?
- Does `V000` pass twice?
- Which logs are populated during multiplayer?
- Is the reload tied to a repeatable turn/action?
- Does the failure follow the host when rotated?
- What is the smallest enabled mod subset that fails?
