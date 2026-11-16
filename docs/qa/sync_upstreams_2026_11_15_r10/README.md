# Sync-all-upstreams, review round 10 fixes (RV9-1 to RV9-6) — evidence

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15 |
| Status | PROVISIONAL (§11.4.290): fixes made, own runs below; independent review of round 10 still owed |
| Roadmap item | CON-PENDING-sync-r8 (placeholder; the lander re-mints it with the engine; main ids ran to CON-400 when this round began and to CON-411 after the merge; corrected in round 11, RV10-8) |
| Evidence class | gate-logic / unit class (§11.4.289(C)(2)): local `file://` bare repositories, real git 2.53, the race shim and the in-process fault driver. Forge behaviour is UNCONFIRMED |
| Fixer | fresh structural fixer (round 10), model Opus 5.5, effort UNKNOWN (not settable or readable on this dispatch path) |

## Table of contents

- [What the findings were](#what-the-findings-were)
- [What changed](#what-changed)
- [RED and GREEN](#red-and-green)
- [Mutants](#mutants)
- [Suite runs](#suite-runs)
- [Integration with main](#integration-with-main)
- [Honest limits](#honest-limits)

## What the findings were

Round 9 found no engine defect. All four open findings were missing tests: reviewer mutants Z01, Z04, Z07 and Z11
survived the whole suite. RV9-5 was the trailer placeholder, and RV9-6 asked us to try to close a stated limit.

## What changed

- RV9-1 (Z04, and the class: every parameter put into a lock or marker path). New live robustness checks
  `branch_lock`, `wt_param`, `run_lock` and `write_race` (`scripts/sync/robustness_checks.py`) cover a plain clone and a
  linked worktree on the branches `main`, `dev` and `feature/x`. A planted lock for the checked-out branch must give
  attention with the reason `in-progress:<label>`, no write and a clean tree. Locks of other branches must not block
  (golden-FALSE). They also cover the worktree's own git dir against the common dir (HEAD.lock, MERGE_HEAD, marker
  FIFO, packed-refs), the run lock in the common dir, and a lock planted while the run is under way. New unit class
  `RoundTen` in `tests/sync/test_unit.py`. The race shim gained a `plant` action (`SXR_PLANT`).
- RV9-2 (Z11): the `marker_read` check plants too-large, unreadable and invalid-JSON markers. With `--check` they give
  exit 3 and the note `write-marker-present:unknown-left-nothing`; with `--apply` they give exit 0, the note
  `write-marker-cleared:unknown-left-nothing` and a fast-forward. A unit test covers each read status.
- RV9-3 (Z01): a unit test feeds `write_settled` a stage-pin with exit 128 and a changed gitlink (not settled) and an
  unchanged one (settled).
- RV9-4 (Z07): `write_race` asserts the reason label: `blocked:tree-changed-before-write` for a lock planted at fetch,
  `blocked:in-progress:<label>` for a lock planted at the last call before the write.
- RV9-5: the placeholder `CON-PENDING-sync-r8` is kept. Main ids ran to CON-400 when this round began and to CON-411 after the merge (corrected in round 11, RV10-8).
- RV9-6: tried and withdrawn. Adding a `git status must be empty` test to `write_settled` broke
  `autostash.no_marker_after_answered_failure`: a user's edit between step 1 and the write was then blamed on the write
  (a false positive). The limit stays as stated, now pinned live by `wt_only` (the work-tree-only case is read as
  settled, the run fails with exit 1, the file is kept, and the next run reports the tree dirty) and by a unit test.
  Telling the two apart needs file content compared with the target tree, which is a tracked follow-up (filed in round 11 as CON-423; corrected in round 11, RV10-4).
- Permanent mutants: the reviewer's Z01, Z04, Z07, Z11 and Z12 (Z12 recorded as equivalent, with proof), plus the
  fixer's own Y01 to Y09, Y12 and Y13 in `tests/sync/test_mutations.py`.
- Docs: manual revision 10, FAQ revision 7 (Q20: non-main branches and worktrees).
- Unchanged: `scripts/setup.sh` and `scripts/post_update_hook.sh`.

## RED and GREEN

- `red/red_r9_reviewer_mutants.txt`: the reviewer's own harness run against a clean r9 checkout (8b45965d). Z01, Z04,
  Z07 and Z11 all SURVIVED (4 of 4).
- `red/red_r9eng_new_checks_final.txt` and `red/red_r9eng_unit_final.txt`: the new checks run with the r9 engine both
  PASS (260 robustness checks and 126 unit tests). This is expected: the r9 engine was correct, and the RED is the
  mutants surviving, not the engine failing.
- `green/green_r10_new_checks_final.txt`: robustness PASS 260 FAIL 0 on r10.
- `mutants/mut_zy_table.txt`: the Z and Y rows on r10 give 18 mutants, 17 killed and 1 equivalent (Z12). That run
  included Y10 and Y11, which were later removed together with the withdrawn RV9-6 test. See the full run for the
  final table.

## Mutants

`mutants/mut_zy_live_only.txt` ran the same rows with the live robustness checks only (no unit tests). Z01, Y11 and
Y13 survive there. Each path is reachable only from a unit test: git 2.53 does not reproduce a failed `add` that
changed the gitlink (Z01); Y11 needs an unanswered `git status` (and was later removed); Y13 needs a missing branch
name. Unit tests kill all three in the real table.

## Suite runs

- `runs/r10_quick_{1,2,3}.txt`: `tests/sync/run_all.sh --quick`, three runs, each `RUN_ALL: PASS`. The verdict-line
  hash (the `sync-*`, `CM-*` and `RUN_ALL` lines with durations removed) was the same in all three runs:
  `b538ebf8d7b236f51a4ee308bf4bac8088a51777b36ad7a57042a72faaeb5cbe`.
- `runs/r10_run_all_full.txt`: `tests/sync/run_all.sh` with no options, `RUN_ALL: PASS`: unit 126, integration 149,
  e2e 24, full-automation 34, security 83, determinism 15, ui 26, hardening 119, chaos 58, perf 13, faults 21,
  robustness 963 (all FAIL 0); gate PASS; gate meta-test PASS (93 cases); mutations: 317 mutants, 315 killed,
  2 equivalent, 0 survived, 0 harness errors.
- `runs/sync_guide.txt` and `runs/verify_manifest.txt`: `scripts/run_full_suite.sh --sync-guide` and
  `--verify-manifest`.

## Integration with main

Main moved to `f67d926c` (CON-401, CON-402, tracker ids up to CON-411) while this round ran. Main was merged into the
vehicle (commit `2170f21c`). There were four additive conflicts, and each was resolved by keeping both sides: the
README docs row, `config/full_suite_manifest.tsv`, step 5b/5c of `scripts/post_update_hook.sh`, and the census in
`docs/guides/full_suite_runner_guide.md` (regenerated with `--sync-guide`). The conflicts were resolved on Opus,
effort UNKNOWN (§11.4.211). After the merge, in `merge/`: `run_all.sh --quick` gave `RUN_ALL: PASS` with the same
verdict hash `b538ebf8…5cbe`, `test_post_update_hub_gates.sh`, `test_run_full_suite.sh` and
`test_full_suite_manifest_gate_git_env.sh` passed, and `--verify-manifest` gave MANIFEST-OK (census total 951).
`sh -n` of the hook fails identically on main; it is a bash script (`bash -n` passes). The full mutation run
predates the merge. The merge changed no file under `scripts/sync/` or `tests/sync/`.

## Honest limits

- The work-tree-only failed write (RV9-6) is still read as settled (see above).
- Only gate-logic evidence exists: no forge was contacted and no live upstream was synced. The independent review of
  round 10 is owed.
