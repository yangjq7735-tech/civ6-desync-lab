# Tech Civic Progress Plus – Multiplayer Safety Patch

Experimental compatibility patch for **Tech Civic Progress Plus**. The original mod is required and remains credited to Firstborn and DeepLogic.

This patch contains no upstream code or assets. It loads after the original and replaces its technology/civic overflow callbacks with read-only callbacks. The original overflow estimate temporarily rewrites live research state to calculate a tooltip value; this patch reports zero overflow instead. Other tooltip features remain provided by the original.

## Requirements

- Subscribe to and enable Tech Civic Progress Plus.
- Enable this patch on every computer in the multiplayer match.
- Do not enable the separate local full-fork build at the same time.

## Testing status

Statically audited. Experimental multiplayer runtime validation is still required. Back up important saves and begin with a disposable match.

Source and technical notes: https://github.com/yangjq7735-tech/civ6-desync-lab
