# QDP001 — Controlled Quick Deals divergence

## Purpose

Validate the code-level theory that Quick Deals can introduce client-local data into Civ VI's synchronized `Player` properties.

This experiment uses a normal UI mod and Quick Deals' own `ExposedMembers.QD.CacheManager` API. It does not use FireTuner, a debugger, DLL injection, memory modification, or native hooks.

## Trigger

After `Events.LoadGameViewStateDone` in multiplayer, each client writes one marker through Quick Deals:

```text
QD_SELLABLE_DEALS = {
  Probe = "QD_DESYNC_PROBE",
  Version = 1,
  LocalPlayer = Game.GetLocalPlayer(),
  MarkerValue = 100000 + Game.GetLocalPlayer()
}
```

Quick Deals itself selects the destination using `Players[Game.GetLocalPlayer()]`. With two human clients, both the destination player and marker value differ.

## Preconditions

- Identical Civ VI build and official content on both PCs.
- Identical Quick Deals Workshop files on both PCs.
- Identical probe files on both PCs.
- Quick Deals and Quick Deals Desync Probe enabled.
- FireTuner and debugger instrumentation disabled.
- Normal Internet multiplayer game with two human players.

## Evidence

In each client's `Lua.log`, require:

```text
QD_DESYNC_PROBE ... status=ARMED ...
QD_DESYNC_PROBE ... status=WRITE localPlayer=N markerValue=10000N ...
```

The two clients must report different `localPlayer` and `markerValue` values, and each readback must match its local write.

Then inspect `net_message_debug.log` and related logs for `AutoArchive out of sync`, `NetGameSync`, `NetSyncSnapshot`, snapshot request/processing, or the visible resync load.

## Interpretation

- Different successful probe readbacks prove Quick Deals accepted different local-client data into its property bridge.
- A native AutoArchive mismatch or resync immediately following the writes validates the complete theory.
- No visible reload does not invalidate the divergent-write finding; Civ VI may localize the delta, compare later, or exclude/normalize the particular property representation. Record the native log behavior rather than inferring from the UI alone.
