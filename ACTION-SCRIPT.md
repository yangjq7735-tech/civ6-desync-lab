# Fixed Action Script

Repeatability matters more than playing naturally. Use the same starting save or the same map/game seeds, then repeat the same actions in the same order.

## Before every run

- [ ] Civ VI was fully closed and relaunched on both PCs.
- [ ] The displayed Civ VI build/storefront matches.
- [ ] The enabled DLC list matches.
- [ ] The enabled mod list and load order match.
- [ ] Only the single variable named in the experiment record changed.
- [ ] PC A hosts unless host rotation is the tested variable.
- [ ] Network type is recorded: wired, Wi-Fi, or mixed.
- [ ] Run ID and checkpoint names are agreed before launch.
- [ ] Map seed, game seed, ruleset, speed, size, leaders, AI count, and turn mode are recorded.

If useful lobby logs already exist after both players join, capture checkpoint `lobby` before launching.

## Vanilla baseline `V000`

Recommended configuration:

- two human players only;
- tiny map;
- no AI;
- no mods, including UI-only mods;
- fixed map and game seeds;
- standard turns, not simultaneous turns;
- a new game rather than the problematic campaign save.

The precise actions may be adjusted once for terrain, but the resulting script must then remain unchanged for every rerun.

| Checkpoint | Actor | Required action | Capture? |
|---|---|---|---|
| `turn-001-start` | Both | Load into the game and do nothing else | Optional |
| `turn-001-end` | A, then B | Found in place when possible; select the recorded research/civic; end turn | Yes |
| `turn-002-end` | A, then B | Move the designated starting unit to the recorded adjacent tile; end turn | Yes |
| `turn-003-end` | A, then B | Perform no optional action; end turn | Yes |
| `turn-004-end` | A, then B | Make the single recorded city-production change; end turn | Yes |
| `turn-005-end` | A, then B | End turn without another optional action | Yes |

Run `V000` twice from the same start. Passing means both runs reach the final checkpoint without a reload/desync.

## Escalation ladder

1. `V001`: repeat `V000` with the target number of AI players.
2. `V002`: rotate the host with everything else fixed.
3. `M000`: enable one suspect mod or half of the full mod set.
4. `M001+`: bisect until the smallest failing mod set is found.
5. `F000`: introduce the real map size/options while keeping the minimal failing set.
6. `F001`: test the original campaign save.
7. `K000`: after capture and comparison are proven, add a known-divergence diagnostic mod.

## When a reload/desync begins

1. Say the current turn and action aloud; both operators record it.
2. Note local time on both PCs.
3. Let Civ VI finish recovery; do not close the game.
4. Capture on both PCs with the same run ID and checkpoint `first-reload`.
5. Save after recovery under a run-specific filename when possible.
6. Stop unless the experiment explicitly studies repeated reloads.

## Interpretation rules

- A raw log-file hash mismatch is normal and does not prove state divergence.
- The earliest repeatable failing action is more valuable than a noisy error at the end of a log.
- If both vanilla runs fail, do not bisect mods yet; rotate host, verify installations, compare DLC, and retest the LAN.
- If vanilla passes and a fixed mod subset fails at the same action, freeze that subset and instrument that subsystem.
- Do not create the intentional-desync mod until canonical markers can be captured and compared reliably.
