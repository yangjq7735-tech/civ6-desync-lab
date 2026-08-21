# Quick Deals – Multiplayer Safety Patch

Experimental compatibility patch for **Quick Deals**. The original mod is required and remains credited to its creator, wltk.

This patch contains no Quick Deals code or assets. It loads after Quick Deals and replaces only the exposed presentation-cache object. Cached deal lists remain process-local instead of being written to synchronized `Player` properties using a client-local player ID.

## Requirements

- Subscribe to and enable Quick Deals.
- Enable this patch on every computer in the multiplayer match.
- Do not enable the separate local full-fork build at the same time.

## Testing status

Statically audited. Experimental multiplayer runtime validation is still required. Back up important saves and begin with a disposable match.

Source and technical notes: https://github.com/yangjq7735-tech/civ6-desync-lab
