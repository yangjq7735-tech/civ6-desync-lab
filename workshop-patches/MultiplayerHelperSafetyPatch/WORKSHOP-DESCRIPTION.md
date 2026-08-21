# Multiplayer Helper – Multiplayer Safety Patch

Experimental compatibility patch for **Multiplayer Helper (MPH) 1.6.7**. The original mod is required and remains credited to its listed creators.

This patch contains no MPH code or assets. It loads after MPH and detaches these client-local gameplay callbacks:

- drop/reconnect unit freeze and restoration;
- sudden-death unit/city destruction and timer-property writes;
- automatic missing technology/civic selection;
- turn-start diagnostic synchronized-RNG consumption.

Lobby and other UI features remain provided by MPH. Features listed above are intentionally unavailable while this patch is enabled.

## Requirements

- Subscribe to and enable Multiplayer Helper (MPH).
- Enable this patch on every computer in the multiplayer match.
- Do not enable the separate local full-fork build at the same time.

## Testing status

Statically audited. Experimental multiplayer runtime validation is still required. Back up important saves and begin with a disposable match.

Source and technical notes: https://github.com/yangjq7735-tech/civ6-desync-lab
