# Civilization VI Two-PC Desync Lab

A development project for diagnosing and solving Civilization VI multiplayer desynchronization.

This starter kit turns two Windows PCs on the same LAN into a repeatable Civilization VI multiplayer test bench. Its purpose is to determine whether the recurring all-player loading screen is caused by:

1. mismatched installations or content;
2. a host or network problem;
3. a particular mod or mod combination; or
4. deterministic simulation-state divergence.

The first phase is deliberately conservative: establish a clean vanilla baseline, capture the logs Civ VI already produces, and change only one variable per experiment. A deliberately divergent diagnostic mod comes later, after paired capture and comparison have been proven reliable.

## Included files

- `tools/Test-Civ6Environment.ps1` — checks Civ VI's diagnostic folder and writes a non-sensitive preflight report.
- `tools/Test-Civ6Remote.ps1` — verifies PC B's advertised SSH host fingerprint before testing key authentication.
- `tools/Capture-Civ6Snapshot.ps1` — copies the current Civ VI logs, including files that the running game has open, and generates SHA-256 manifests.
- `tools/Compare-Civ6Snapshots.ps1` — compares paired manifests and isolates explicit state/desync marker lines when present.
- `tools/Test-Kit.ps1` — parses every included PowerShell file and runs the comparator against synthetic paired snapshots.
- `ACTION-SCRIPT.md` — the fixed baseline procedure and escalation ladder.
- `experiments/TEMPLATE.md` — copy this for every experiment.
- `HANDOFF.md` — concise engineering state for future Codex/ChatGPT work.

The scripts do not edit Civ VI, enable FireTuner, inject code, or delete anything.

## Assumptions

- Both PCs run Windows and the same Civ VI storefront/build.
- PC A hosts initially; PC B joins.
- Both use the same DLC and mod configuration.
- Both are on the same wired LAN if possible.
- Windows PowerShell 5.1 or PowerShell 7 is available.
- Civ VI's current diagnostic root is:

  `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VI`

2K/Firaxis documents that location for `Logs` and `AppOptions.txt`: [Civilization VI: File Locations](https://support.civilization.com/hc/en-us/articles/37657122743699-Civilization-VI-File-Locations).

If your installation uses another location, pass `-CivRoot` to the scripts.

## One-time setup on both PCs

1. Copy this entire kit to both PCs. Use a local copy on each PC during a test.
2. Start Civ VI once, reach the main menu, and exit so its diagnostic folders exist.
3. Open PowerShell in this kit's directory.
4. Allow these unsigned local scripts only for the current PowerShell process:

   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

5. Test the kit itself on at least one PC:

   ```powershell
   .\tools\Test-Kit.ps1
   ```

   The expected final line is `PASS: kit syntax and synthetic comparison test succeeded.`

6. Run a preflight on each machine:

   ```powershell
   # PC A
   .\tools\Test-Civ6Environment.ps1 -Pc A

   # PC B
   .\tools\Test-Civ6Environment.ps1 -Pc B
   ```

7. Compare both reports. Resolve differences in game build, DLC, storefront, enabled mods, and configuration before starting `V000`.

The preflight hashes `AppOptions.txt` without copying its contents. Different hashes are a prompt to inspect configuration, not proof of a multiplayer problem.

## Verify PC B's SSH identity

On PC B, open an elevated PowerShell in this repository and run the idempotent bootstrap once:

```powershell
.\tools\Enable-Civ6RemoteSsh.ps1
```

It installs PC A's dedicated public key in Windows OpenSSH's administrator key file, repairs the file ACL, starts `sshd`, enables a Private-network/LocalSubnet firewall rule, and prints PC B's username, IPv4 addresses, and ED25519 host-key fingerprint. The private key never leaves PC A. A direct Ethernet cable can improve reachability but does not replace this authentication setup.

After PC B reports its LAN address, Windows username, and ED25519 host-key fingerprint, verify all three before running any remote command:

```powershell
.\tools\Test-Civ6Remote.ps1 `
  -ComputerName 192.168.50.36 `
  -UserName pc-b-user `
  -ExpectedHostFingerprint 'SHA256:replace-with-pc-b-fingerprint'
```

The verifier uses a temporary `known_hosts` file, refuses mismatched host keys, requires the dedicated Civ VI lab identity key, and performs a read-only PowerShell probe with password prompts disabled. A successful run ends with `PASS: PC B SSH host identity and key authentication verified.`

## Run the vanilla baseline

Follow `ACTION-SCRIPT.md` and use run ID `V000`. Disable every mod, including UI-only mods. Use two humans, no AI, a tiny map, fixed seeds, standard turns, and a new game.

At the agreed checkpoint, run this on both machines:

```powershell
# PC A
.\tools\Capture-Civ6Snapshot.ps1 `
  -Pc A `
  -RunId V000 `
  -Checkpoint turn-005-end `
  -Notes "No reload observed"

# PC B: use -Pc B with the same RunId and Checkpoint
```

The command prints the new snapshot directory. Move both snapshot directories onto one PC and compare them:

```powershell
.\tools\Compare-Civ6Snapshots.ps1 `
  -SnapshotA .\captures\V000\turn-005-end-PCA-20260820T010203123Z `
  -SnapshotB .\captures\V000\turn-005-end-PCB-20260820T010205456Z `
  -ReportPath .\reports\V000-turn-005-end.json
```

Raw log hashes commonly differ because timestamps, machine paths, rendering details, and client-specific networking messages differ. A raw mismatch is an evidence index—not proof that gameplay state diverged. Future instrumentation will print canonical `CIV6_SYNC_PROBE` markers; the comparator already isolates and compares those lines.

## Capture a reload/desync

When the loading screen appears:

1. Say and record the turn and immediately preceding action.
2. Record local wall-clock time on both PCs.
3. Let Civ VI finish recovering.
4. Do not close or relaunch the game.
5. Immediately capture the same checkpoint on both PCs:

   ```powershell
   .\tools\Capture-Civ6Snapshot.ps1 `
     -Pc A `
     -RunId M003 `
     -Checkpoint first-reload `
     -Notes "Reload followed host purchase of custom building"
   ```

6. Stop the run unless the experiment explicitly studies repeated reloads.

## Escalation order

Change only one variable between runs:

1. `V000`: two humans, tiny map, no AI, no mods; pass twice.
2. `V001`: same setup plus the target AI count.
3. `V002`: rotate the host while holding everything else fixed.
4. `M000+`: introduce one suspect mod or a controlled half of the mod set.
5. `F000+`: introduce the real map/options and finally the problematic save.
6. `K000+`: only after paired captures work, introduce a deliberately divergent diagnostic mod to establish Civ VI's known-desync signature.

If the full mod set fails, bisect it. Keep the starting save, seeds, host, action sequence, and game options fixed while reducing the failing set.

## What makes a run useful

A useful experiment records:

- Civ VI build and storefront on both PCs;
- DLC and ordered mod set;
- map/game seeds and starting save;
- host and network type;
- exact action sequence;
- first visible reload time and preceding action;
- paired snapshots from the same checkpoint; and
- whether the result reproduced on a rerun.

One failure is a lead. Two failures at the same checkpoint with the same setup are a reproduction.

## Privacy and safety

- Captures remain local unless you copy or upload them.
- Generated `captures`, `preflight`, and `reports` directories are ignored by Git so diagnostic data is not published accidentally.
- `AppOptions.txt` is excluded from snapshots by default. Use `-IncludeAppOptions` only intentionally and inspect it before sharing.
- `-ExtraPath` can copy saves or supporting files; inspect those before sharing too.
- The tools never delete, edit, or truncate Civ VI files.
- Do not enable FireTuner for the vanilla baseline.
