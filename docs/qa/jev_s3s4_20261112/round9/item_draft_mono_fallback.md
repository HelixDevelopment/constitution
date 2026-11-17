# Draft tracked item: ages on wall time where no monotonic source exists (round 9, R8-6 residue)

| Field | Value |
|---|---|
| Type | Task |
| Status | Queued (draft, minted at landing) |
| Id | CON-PENDING-MONO-FALLBACK (draft id; the lander mints the real id, §11.4.54) |
| Source | review of 3bd53782, finding R8-6 (minor); round-9 fix and its honest limit |
| Reproduction | `UNSET` (a Task, not a defect report) |

## What round 9 does

Marks and lease heartbeats carry `mono` = `<boot id>:<uptime seconds>` from `/proc/sys/kernel/random/boot_id` and
`/proc/uptime`. `age_of` judges an age on the monotonic difference when the record and the reader are on the same
boot, treats a record from another boot as expired, and falls back to wall time for a record without `mono`.

## What is left

- A host without readable `/proc` (or a container that hides it) has no monotonic source: `MONO_TOK` is empty and
  every age is judged on wall time, as in round 8. A wall-clock step there can expire a live mark or lease early, or
  keep a dead one late.
- Records written by an older producer (no `mono`) are judged on wall time until they are rewritten.

## Acceptance

- Decide (operator, §11.4.66) whether such a host should refuse local placement (fail closed, route to the fallback)
  or keep the wall-time rule with a visible warning in `status`.
- Either way, `status --json` names the clock source in use (`monotonic` / `wall`), and a test pins it.

Gate-logic evidence only for the round-9 part (`test_s4_round9.sh` row P111). Nothing live.
