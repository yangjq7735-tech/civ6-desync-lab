# Worker PC bootstrap

This procedure turns another Windows PC into a Civ VI desync-lab worker controlled from the primary PC. It records the PC B setup so the same process can be repeated for PC C or later machines.

## Control model

- The primary PC is the only orchestrator. It serializes gameplay-changing commands.
- Each worker exposes Windows OpenSSH on its Private LAN profile.
- Each worker runs Civ VI and `civ6-mcp` locally. The Tuner port remains bound to that worker's `127.0.0.1:4318`; it is not exposed to the LAN.
- The controller runs remote MCP calls through SSH and retrieves logs, saves, and reports with SSH/SCP.
- A worker Codex agent is optional. SSH plus the local MCP runtime is sufficient after a save is loaded.

## Prerequisites on every worker

1. Windows 11 with a Private LAN connection to the controller.
2. Steam signed in to an account that owns Civilization VI.
3. Civilization VI installed with the same build, DLC, and mod set as the controller.
4. Codex Desktop installed and signed in if a local GUI-capable fallback agent is desired.
5. An administrator account for the one-time OpenSSH and SDK setup.

## 1. Clone the lab repository

Use a normal project checkout for this repository. Do not clone the upstream `lmwilki/civ6-mcp` reference inside it.

```powershell
git clone https://github.com/yangjq7735-tech/civ6-desync-lab.git
cd civ6-desync-lab
```

## 2. Enable authenticated worker SSH

From elevated PowerShell on the worker:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tools\Enable-Civ6RemoteSsh.ps1
```

The script is idempotent. It:

- installs the controller's public automation key in `C:\ProgramData\ssh\administrators_authorized_keys`;
- removes inherited ACLs and grants access only to `SYSTEM` and the local Administrators group;
- starts `sshd` and sets it to Automatic;
- allows TCP 22 only on the Private profile from `LocalSubnet`; and
- prints the worker username, addresses, and ED25519 host-key fingerprint.

The private key never leaves the controller. A direct Ethernet cable can improve reachability, but it does not replace SSH authentication.

Report readiness in this form:

```text
WORKER_READY username="..." hostname="..." ip="..." port="22" host_fingerprint="SHA256:..." sshd="Running"
```

The controller must compare the reported fingerprint with `ssh-keyscan`/`ssh-keygen` output before pinning it. Never use `StrictHostKeyChecking=no` as the permanent configuration.

## 3. Install the worker runtime

From elevated or ordinary PowerShell in this repository:

```powershell
.\tools\Initialize-Civ6WorkerRuntime.ps1
```

This installs Git and `uv` through WinGet when missing, creates a separate upstream runtime at `%LOCALAPPDATA%\Civ6DesyncLab\civ6-mcp`, performs the Windows launcher dependency sync with `--frozen`, and runs the upstream unit tests in `tests/`. It never edits the upstream checkout.

The upstream lock file currently requires:

```powershell
uv sync --frozen --extra launcher-windows
```

Do not replace `--frozen` with `--locked`; the current upstream `uv.lock` is rejected as stale by `--locked` even though the frozen environment installs and its unit tests pass.

## 4. Install the Civ VI Development Tools

Install Steam app **404350**, `Sid Meier's Civilization VI Development Tools` (approximately 0.8 GB installed):

```powershell
Start-Process 'steam://install/404350'
```

Do not install app `597260` unless the large Development Assets package is explicitly needed. Do not open or leave `FireTuner2.exe` running; Civ VI accepts only one Tuner client at a time.

Verify the SDK exists in one Steam library:

```text
steamapps\common\Sid Meier's Civilization VI SDK\FireTuner\FireTuner2.exe
```

## 5. Initialize and configure Civ VI

Launch Civ VI once and reach the main menu so the local option files are created. Exit cleanly, then run:

```powershell
.\tools\Set-Civ6AutomationOptions.ps1 `
  -RenderWidth 1600 `
  -RenderHeight 900
```

The script creates timestamped backups and sets the following values:

`%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VI\AppOptions.txt`

```text
EnableTuner 1
FullScreen 0
RenderWidth 1600
RenderHeight 900
PlayIntroVideo 0
```

`%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VI\UserOptions.txt`

```text
AutoEndTurn 0
TutorialLevel -1
HasChosenTutorialLevel 1
```

`EnableTuner 1` disables Steam achievements while it remains enabled. Restore it before the strict vanilla baseline with `Set-Civ6AutomationOptions.ps1 -TunerEnabled 0`.

Windowed 1600×900 is preferred for reliable OCR loading without monopolizing the worker's desktop. Disabling the intro video prevents the lifecycle loader from timing out while it waits for the main menu. Disabling tutorials prevents first-run Advisor dialogs from blocking a turn transition while the MCP is active. The game may stay behind other windows after a match is loaded; avoid minimizing it when OCR or screenshots are required.

### Register controller-triggered GUI tasks

An SSH command runs in a non-interactive Windows session and cannot reliably launch or capture a game window on the signed-in desktop. While signed in locally to the worker, run this once:

```powershell
.\tools\Enable-Civ6WorkerGuiTasks.ps1
```

The script registers two on-demand tasks using the current user's interactive token:

- `Civ6DesyncLab-LaunchCiv6` starts Steam app 289070 and then exits, so the task does not remain stuck in `Running` while the game is open.
- `Civ6DesyncLab-CaptureDesktop` writes `C:\ProgramData\Civ6DesyncLab\worker-screen.png` for controller-side diagnosis.

The controller can then use:

```powershell
ssh <worker-alias> "powershell -NoProfile -Command Start-ScheduledTask -TaskName Civ6DesyncLab-LaunchCiv6"
ssh <worker-alias> "powershell -NoProfile -Command Start-ScheduledTask -TaskName Civ6DesyncLab-CaptureDesktop"
scp <worker-alias>:C:/ProgramData/Civ6DesyncLab/worker-screen.png .
```

These tasks require the worker user to be logged in and the desktop to remain unlocked. They do not expose the Tuner port to the network.

### Steam profile and license failures

If Steam shows **Who's playing?**, select a remembered profile that owns Civilization VI before retrying the launch. A profile chooser can appear again after Steam restarts even when `AutoLoginUser` is set.

Steam records the exact failure in `Steam\logs\console_log.txt`. This sequence means the selected profile has no Civ VI license:

```text
LaunchApp changed task to RequestingLicense
LaunchApp failed with AppError_5
```

Do not reinstall the game for `AppError_5`: verify the selected Steam profile first. The install can be completely healthy in a shared Steam library while the active profile lacks the license. After changing profiles, trigger `Civ6DesyncLab-LaunchCiv6` again and confirm the log reaches `GameAction ... Completed` followed by `Game process added`.

## 6. Install a known-good save correctly

Windows Documents may be redirected to OneDrive. Never assume `%USERPROFILE%\Documents`. Resolve it with:

```powershell
$documents = [Environment]::GetFolderPath('MyDocuments')
$singleSaves = Join-Path $documents "My Games\Sid Meier's Civilization VI\Saves\Single"
```

Copy `.Civ6Save` files to `$singleSaves`. If Civ VI displays `NO SAVED GAMES`, check this redirected Known Folder before debugging the save itself.

## 7. Readiness checks

With Civ VI running and the Tuner enabled:

```powershell
Get-NetTCPConnection -State Listen -LocalPort 4318
```

From the separate upstream runtime:

```powershell
uv run --frozen python scripts\test_connection.py
```

At the main menu the TCP port may accept a connection while `GameCore` and `InGame` Lua states are absent. Load a save and dismiss the leader `CONTINUE GAME` screen before expecting gameplay tools to work.

The final read-only proof is:

```powershell
uv run --frozen python <lab-repo>\scripts\civ6_mcp_call.py get_game_overview
```

Expected output contains a turn number, civilization, leader, difficulty, yields, city count, and unit count.

The helper serializes calls made on the same Windows PC. This is required because the current upstream MCP server starts its dashboard API on fixed port `8000`; overlapping server processes would otherwise race for that port. The default wait is 120 seconds and can be changed with `--lock-timeout`.

## 8. Multiplayer/desync discipline

- Use one run ID and one action script across every machine.
- Let the controller issue state-changing commands serially.
- Capture both sides at the same checkpoint before advancing.
- Do not use arbitrary local `run_lua` mutations during the vanilla baseline.
- Stop at the first divergence and preserve both saves and log directories.
- Disable the Tuner and all mods for `V000`; enable diagnostic components one variable at a time afterward.
