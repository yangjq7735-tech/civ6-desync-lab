# Multiplayer-safe forks

## Purpose

`tools/Install-Civ6MultiplayerSafeForks.ps1` creates three separate, project-owned local patch candidates from the user's installed Steam Workshop sources. It does not edit or redistribute the Workshop directories.

Each generated fork has a distinct mod ID and a `Blocks` relationship against its unsafe original. Do not enable an original and its safe fork together.

## Install all three

Close Civilization VI, then run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tools\Install-Civ6MultiplayerSafeForks.ps1
```

Update recognized generated forks after changing this project:

```powershell
.\tools\Install-Civ6MultiplayerSafeForks.ps1 -Replace
```

Install an individual fork:

```powershell
.\tools\Install-Civ6MultiplayerSafeForks.ps1 -Target QuickDeals
.\tools\Install-Civ6MultiplayerSafeForks.ps1 -Target MultiplayerHelper
.\tools\Install-Civ6MultiplayerSafeForks.ps1 -Target TechCivicProgressPlus
```

The installer refuses unknown source-file or complete-source-tree hashes. A refusal after a Workshop update is intentional: the new upstream version must be re-audited before the patch is applied. This also makes independently generated copies byte-consistent when every player's Workshop sources match.

The installer auto-detects common Steam library locations. If a friend's library uses another layout, pass its Civ VI Workshop content folder explicitly:

```powershell
.\tools\Install-Civ6MultiplayerSafeForks.ps1 -WorkshopRoot 'D:\SteamLibrary\steamapps\workshop\content\289070'
```

## Quick Deals - Multiplayer Safe

- Fork ID: `7e3bce14-956e-4223-ae08-b1788ae7d257`
- Blocks original ID: `5aceed03-8639-4a81-8cbf-03f54d543502`
- Replaces the serialized `Player:SetProperty` cache with process-local Lua tables.
- Preserves the Quick Deals UI and in-session cache behavior.
- Cache state resets on load, which is appropriate for presentation data.

## Tech Civic Progress Plus - Multiplayer Safe

- Fork ID: `1317e07f-bc75-4321-ac90-4b76f43d8bec`
- Blocks original ID: `8446e6e9-7703-434d-ba10-0bd70a291d28`
- Replaces mutation-based overflow probing with a read-only compatibility surface reporting zero overflow.
- Retains the remaining technology/civic tooltip UI.
- Exact overflow estimation is intentionally unavailable because the original derives it by rewriting live research state.

## Multiplayer Helper 1.6.7 - Multiplayer Safe

- Fork ID: `947f97ba-d2e8-49fe-af14-dd0432737259`
- Blocks original ID: `619ac86e-d99d-4bf3-b8f0-8c5b8c402176`
- Retains non-mutating lobby and UI features.
- Disables drop/reconnect unit freeze and restoration.
- Disables sudden-death direct unit/city destruction and timer property writes.
- Disables automatic missing technology/civic selection.
- Removes diagnostic consumption of synchronized game RNG.

These disabled features cannot be made reliably synchronized using the mod's current client-local Lua event bridge. They require an authoritative, ordered command design rather than a local direct mutation.

## Limitations

These are source-derived safety patches, not proof that every remaining line in the upstream mods is defect-free or that a desync can no longer occur. Back up important saves and begin with a disposable test match. All friends in a match must install byte-identical generated forks and use the same ordered mod set. The generated directories contain upstream assets copied from each user's own Workshop installation and should not be committed to this repository.
