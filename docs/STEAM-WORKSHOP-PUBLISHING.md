# Steam Workshop publishing plan

The publishable artifacts are the three small compatibility patches in `workshop-patches`. They contain only project-authored Lua and manifests. Each declares its upstream Workshop mod as a dependency and does not redistribute upstream code or assets.

Do not publish the generated full forks from the user's Civ VI `Mods` directory. Those contain copied upstream files whose authors have not supplied a redistribution license.

## Before upload

1. Runtime-test each compatibility patch with its original dependency and without the corresponding local full fork.
2. Confirm the dependency loads first and the patch emits its initialization messages in `Lua.log`.
3. For Multiplayer Helper, confirm all six detach messages appear and no unsafe callback runs afterward.
4. Run the static synchronization-risk scanner against the three patch directories.
5. Generate the project-owned preview images with `tools/New-WorkshopPreviewImages.ps1`.
6. Build the three `.civ6mod` packages with `tools/Build-WorkshopPatches.ps1`.

## Upload

Civilization VI Development Tools (Steam app `404350`) includes `Firaxis.SteamWorkshop.exe`. Create three separate Workshop entries and initially use friends-only visibility. Copy each `WORKSHOP-DESCRIPTION.md` into its entry and link the source repository.

Publishing is an external representational action. Review the title, description, dependency, visibility, and selected directory immediately before submitting each entry.
