# Experiment `V000`

## Question

Can two matched Windows PCs complete the fixed five-turn test twice on the same LAN without a global loading-screen reload when all mods are disabled?

## Outcome

- Status: `planned`
- Reproduced on rerun: `not yet`
- First visible reload/desync turn:
- First visible reload/desync local time:
- Immediately preceding action:

## Fixed environment

- Date/time and timezone:
- PC A computer name:
- PC B computer name:
- Host: `A`
- Network: `wired | Wi-Fi | mixed`
- Storefront: `Steam | Epic | other`
- Civ VI build shown by PC A:
- Civ VI build shown by PC B:
- Ruleset:
- DLC:
- Turn mode: `standard`
- Map type/size: `tiny`
- Map seed:
- Game seed:
- Game speed:
- Human leaders:
- AI count/leaders: `0`
- Starting save filename and SHA-256:

## Enabled mods

None, including UI-only mods.

## Single changed variable

Initial clean baseline; there is no prior run.

## Action trace

Use `ACTION-SCRIPT.md` and add exact coordinates or substitutions below.

| Sequence | Turn | Actor | Exact action | Result/observation |
|---:|---:|---|---|---|
| 1 | 1 | A | Found in place; select recorded research/civic |  |
| 2 | 1 | B | Found in place; select recorded research/civic |  |
| 3 | 2 | A | Move designated unit to recorded adjacent tile |  |
| 4 | 2 | B | Move designated unit to recorded adjacent tile |  |
| 5 | 3 | A, then B | No optional action; end turn |  |
| 6 | 4 | A, then B | Make the recorded production change; end turn |  |
| 7 | 5 | A, then B | No optional action; end turn |  |

## Captures

| Checkpoint | PC A snapshot | PC B snapshot | Comparison report |
|---|---|---|---|
| `turn-001-end` |  |  |  |
| `turn-002-end` |  |  |  |
| `turn-003-end` |  |  |  |
| `turn-004-end` |  |  |  |
| `turn-005-end` |  |  |  |

## Earliest evidence

- Earliest differing canonical marker: not instrumented in `V000`
- Relevant log file and line/context:
- Does the same evidence occur on rerun?

## Conclusion

Pending.

## Next experiment

Repeat `V000` from the same start. If both runs pass, proceed to `V001` with the target AI count. If either fails, first verify files, rotate host, and retest before introducing mods.
