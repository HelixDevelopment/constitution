# Jev S3/S4 round 9 (CON-PENDING-JEV): structural fixes for the independent review of `3bd53782` (NO-GO: R8-1 to R8-8)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15 |
| Status | evidence (In progress; no GO claimed; PROVISIONAL) |
| Evidence class | gate-logic only (stub llmctl, a flock gate, an advancing test clock, a test monotonic clock; §11.4.289(C)(2)). Nothing here is live evidence; no local model was started, no hosted endpoint was called, `llmctl enable` was never run. |
| Round | 9 (structural, §11.4.276(E): a fresh fixer; under the standing operator decision "review rounds until GO, fresh fixer and reviewer each round") |

## What was wrong (R8-1, the class) and the structural change

Round 8 wrote ONE stopping mark per set when the stops were PLANNED, then ran the stops one after another. The mark of
a later set aged through the earlier stops, so an observer could clear a LIVE stopper's mark (the reviewer's multi-stop
probe; reproduced as RED here). This is the same class as round 7's R7-A (a time read before a wait), in a second
place. Round 9 removes the shape instead of tuning a TTL:

1. One mark, one bounded call. `plan_locked` and `release_locked` only LIST the stops. Each stop is taken by
   `stop_turn`, which takes the lock, reaps, judges the set AGAIN (`arm_stop_locked`: still ours, still owed, no
   lease now, no foreign mark, health still degraded or absent for a disposal) and writes the mark immediately before
   its one bounded `llmctl stop`. A stop that is no longer owed at its turn is not run and the reason is logged
   (`not run at its turn: <reason>`); that is not a failure (release exits 0 for it).
2. A stop never deletes a leased set (R8-2). `finish_stop_locked` checks ownership by pid and pid start time; a set that
   holds a lease, or carries another process's mark, is KEPT with `stopped_while_held` and health `pending`.
3. A lease is not aged out while its own acquire runs a bounded call: a live mark naming the holder suspends the
   lease TTL (the mark's own `MARK_TTL` bounds it), and every registry write during the acquire refreshes the holder's
   heartbeat. A dead pid is never kept this way (row P112, strengthened this round; see the O9-13 incident below).
4. Ages on a monotonic clock (R8-6): `mono` = `<boot_id>:<uptime>`, judged by `age_of`; a record from another boot is
   expired; a record with no `mono` falls back to wall time; an unreadable monotonic source is a config error (exit 2).
   Limit: a host without `/proc` has no monotonic source and judges ages on wall time; draft follow-up
   `item_draft_mono_fallback.md` (CON-PENDING-MONO-FALLBACK, minted at landing).

The class census, static and dynamic, with its control needle, is `census.md`.

## RED then GREEN

| Producer | Suite `tests/jev/test_s4_round9.sh` | File |
|---|---|---|
| round 8 (`3bd53782`) | rc 1, 39 fail, 28 pass | `red_r9_on_r8.txt` |
| round 9, snapshot s3 | rc 0, 67 pass, 0 fail (×3, identical verdict sets) | `runs/final{1,2,3}_r9.txt` |
| round 9, final snapshot s4 (P112 strengthened, producer byte-equal to s3) | rc 0, 70 pass, 0 fail (×3, identical verdict sets) | `runs/s4_r9_x{1,2,3}.txt` |

The earlier suites on s3 (×3 each, rc 0, 0 fail): r8 47, r7 157, r6 183, placement 266 (`verdict_sets_x3.txt`). They
are unchanged in s4 (the s4 change is in `test_s4_round9.sh` only; `frozen_s4.sha256`).

## Findings, one by one

| Finding | Status |
|---|---|
| R8-1 one mark per stop, at its own turn | fixed structurally (above); census + control needle in `census.md` |
| R8-2 never delete a leased set | fixed; rows P102a, P102b |
| R8-3 kill RV08, RV09 with an advancing clock | killed (P103, P104) |
| R8-4/5 kill RV03, RV05, RV06, RV07, RV10, RV12 | killed (P105, P106, P103, P108, P109, P110) |
| R8-6 monotonic clock | implemented; no-`/proc` limit documented, draft follow-up |
| R8-7 README shellcheck note | corrected below |
| R8-8 Revision header | `Constitution.md` Revision 97, Last modified 2026-11-15T11:43:50Z |
| canon note | reworded in `Constitution.md` and `groups/host-and-resource-safety.md` (byte-equal): it names round 9 and says the census covers only the classes it enumerates, not that the class is closed |

## R8-7 correction

The round-8 README said four shell files changed and that shellcheck was clean on them. Round 8 changed FIVE shell
files. The `lib_assert.sh` SC2034 warning (`HOOK_RC` assigned but unused in that file) is pre-existing at `c811d0cd`;
the variable is read by the suites that source the file. It is now disabled at that line with that reason. Round 9:
0 warnings or errors in the five shell files it touches (`checks/shellcheck_warning_counts.txt`).

## Mutants

`mutants.md`: 34 mutants (CTRL, RV01 to RV12, O9-01 to O9-19, two composites). CTRL survives, as it must. Every other
mutant is killed (31) or, for RV01 and O9-16, equivalent by construction: masked by the acquire-time heartbeat refresh, and both composites with that refresh removed are killed (limits in `mutants.md`).

## Instrument incidents (recorded, §11.4.273)

1. Mutant copies (first run invalid). The first mutant run copied only `jev-place.sh` into each mutant directory; the
   producer sources `lib_decide.sh` from its own directory, so every acquire exited 1 and every mutant read as killed for
   the wrong reason. Fixed: each mutant is a full copy of `scripts/jev`, and a CTRL mutant (no change) must survive.
   The invalid run was deleted and redone.
2. O9-13 survived on s3, and the surviving was a TEST defect. Row P112's dead-pid case crafted a set whose unit the stub
   reported gone, so the status released the lease as `endpoint_gone` and the row passed even when the producer KEPT the
   dead holder (debug run `runs/dbg_o913.txt`: the log shows "kept while a live mark names the holder" and then
   "endpoint_gone"). Fixed in s4: the unit is reported up, and the row asserts the reap's own log line, no
   `endpoint_gone`, and no "kept" line. O9-13 is now killed by P112.
3. A regular-expression key. The mutant runner looked up result lines with `grep -P "^K_..."`; the composite keys hold
   `+`. Replaced by an exact `awk` field match before the composites ran.
4. Snapshots. Editing a suite while bash is running it corrupts bash's incremental read (seen in round 8, P78); every
   counted run here uses a frozen snapshot copied from the tree (`snaps/s3`, `snaps/s4`).
5. Normalised verdict hashes. Two r8 and placement runs differed only by real-clock seconds printed in parentheses;
   with those stripped the verdict sets are identical (`verdict_sets_x3.txt`).

## Blocker: CON-299 id collision (§11.4.54)

`main` (`f4881591`, "feat(release): land_vehicle lander") minted CON-299 for a different item (`docs/Issues.md`,
`docs/Issues_Summary.md`). This vehicle's rounds 4 to 7 commits and CHANGELOG entries use CON-299 for Jev S3/S4.
`main` is 10 commits ahead of the merge base `02c10935`, the vehicle 26. The merge of `main` into the vehicle was NOT
done here: resolving which item keeps CON-299 and re-minting the other is a §11.4.54 / §11.4.214 decision for the
lander. The vehicle's own work since round 8 uses `CON-PENDING-JEV`.

## Drafts minted at landing

CON-PENDING-O6-1, DEPS-LLMCTL-REF, CLOCK-BOOTSTRAP (round 8), CON-PENDING-MONO-FALLBACK (this round).

## Static gates

`checks/static_summary.txt`: `cm_constitution_index_fresh`, `cm_covenant_114_282_propagation`,
`cm_covenant_114_291_propagation`, `cm_gate_ledger_ratchet` all exit 0; `--verify-manifest` MANIFEST-OK (total 916);
the index regeneration check (`gen_check_before.txt` drift, `gen_check_after.txt` no drift).
