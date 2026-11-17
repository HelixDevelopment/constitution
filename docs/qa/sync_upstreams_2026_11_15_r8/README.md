# Sync-all-upstreams, review round 8 fixes (RV7-1 to RV7-6) — evidence

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15 |
| Status | PROVISIONAL (§11.4.290): fixes made, own runs below; independent review of round 8 still owed |
| Roadmap item | CON-PENDING-sync-r8 |
| Evidence class | gate-logic / unit class (§11.4.289(C)(2)): local `file://` bare repositories, real git, an in-process fault driver for the environment (signal, clock, kernel, a foreign marker or lock). Forge behaviour is UNCONFIRMED |
| Fixer | structural fixer (round 8, §11.4.276(E), replace not layer), model Opus 5.5, effort UNKNOWN (not settable or readable on this dispatch path) |

## Table of contents

- [What changed](#what-changed)
- [Class inventory and its scope (RV7-4)](#class-inventory-and-its-scope-rv7-4)
- [RED and GREEN (RV7-5)](#red-and-green-rv7-5)
- [Mutants](#mutants)
- [Suite runs](#suite-runs)
- [Landing](#landing)
- [Honest limits](#honest-limits)

## What changed

RV7-1 was fixed by replacing the marker lifecycle at the two write sites with ONE state machine per git
directory (`scripts/sync/sync_all_upstreams.py`):

- States `none`, `write-in-progress`, `cleared`, `write-killed`, `write-interrupted`, `earlier-run-marker`, keyed
  by the git directory's real path, moved only by `Runner.gd_move` along the table `GD_MOVES`. `cleared` may go
  back to `write-in-progress`; the three unresolved end states (`write-killed`, `write-interrupted`,
  `earlier-run-marker`) have no exit in the run.
- `begin_write` is the only way a write gets a marker. It refuses (`blocked:...`) when the git directory is
  unknown, in an unresolved state, already holds anything at the marker path, or has an operation or lock in
  progress (`index.lock` included). The marker is created with `O_EXCL | O_NOFOLLOW`: a marker that is already
  there is never opened, overwritten or removed. Each marker carries a write id; the write gets a `WriteToken`.
- `Runner.run` is the single spawn choke point: a write git starts only when its token is the live one of its git
  directory AND the marker on disk, read at that moment, carries the token's write id
  (`no-write-token`, `write-token-stale`, `write-marker-not-ours` otherwise; no process is started).
- `end_write` ends every write: git answered (any declared status, 0 or not; this kills RV7E) or no git started:
  the marker is removed, `cleared`. The write's own limit: `write-killed`, marker kept. Any other end:
  `write-interrupted`, marker kept. A token refusal never touches the marker on disk.
- Advance-pin step 3a: the parent's git directory is checked with the same `gitdir_write_block` BEFORE the child
  is moved (`blocked:parent-<reason>`). This closes the reviewer's sibling case: a second sibling is never moved
  while the parent holds a killed stage-pin, and its marker is never overwritten.
- The stage-pin keeps `final=True` in its `begin_write` (RV7C) and holds its own token.
- RV7-6: an flock that is refused prints `cannot take the run lock`; an open that fails prints
  `cannot open the run lock`.

Tests (all drive the real engine):

- `tests/sync/test_unit.py` class `RoundEight`: the full transition table (36 pairs), every unresolved state
  blocking, the three token refusals, every `end_write` outcome, no overwrite and the unwritable case.
- `scripts/sync/inproc_driver.py` faults `kill-first-add`, `kill-first-add-then-wipe`, `plant-<site>`,
  `race-<site>`, `swap-<site>` (site = ff, pin, follow, stage), `plant-pinparent`, `lock-pinparent`,
  `stop-at-pin-checkout`, `none`; a spawn audit records, for every write git that really started, whether the
  marker in its git directory at that moment was its own.
- Robustness checks `sibling_kill` (with a control run), `sibling_wipe`, `marker_pre` (17 cases: "a marker already
  exists when a write starts" at every write site, at three moments), `stop_pin`, `parent_lock`, and
  `autostash.no_marker_after_answered_failure` (RV7E).

## Class inventory and its scope (RV7-4)

`class_inventory_write_paths.py` is path-wise, not call-site-wise. It reads the engine's AST and checks four rules:
R1 every `r.run(..., write=True)` passes a token assigned from `begin_write` in the same function; R2
`write_marker` is called only in `begin_write`; R3 `clear_marker` only in `write_marker`, `begin_write`,
`end_write` and `run()`'s earlier-marker loop; R4 `Runner.run` checks `token_refusal` inside `if write:` before
`proc_run_git`. Control needles: `def write_git` must be found once, the fake `write_markerX` zero times.

| Engine | Write paths | Violations | Verdict | File |
|---|---|---|---|---|
| r8 (this branch) | 3 | 0 | SEES, rc 0 | `inventory/r8_engine.txt` |
| r7 (`baa88df8`) | 3 | 10 | SEES, rc 1 | `inventory/r7_engine.txt` |
| r6 (`29f9c7b9`) | 3 | 8 | SEES, rc 1 | `inventory/r6_engine.txt` |

Scope statement: the static half sees every path on which a write git can START (there are exactly three write
calls, all in `write_git`) and whether each is gated by a live token. It does not see timing between two lines,
another process, or git's own behaviour. The dynamic half is the spawn audit above, which checks the same
invariant at run time for the faults listed; it covers the moments "before begin_write", "between its checks and
O_EXCL", "after creation, before git" and "while the write runs", and does not cover a marker change while git
itself runs (git does not read our marker). Calls of git outside `Runner.run` are the gate's job
(`CM-SYNC-UPSTREAMS-FF-ONLY`: `proc_run_git` is the only spawn).

## RED and GREEN (RV7-5)

- `red/sibling_kill.on_r7.txt`: the reviewer's sibling probe on the r7 engine. Run 1: the second sibling's write
  overwrote and cleared the killed write's marker, `index.lock` stayed; run 2 then reports `in-progress:index.lock`
  (blamed on the user). `red/sibling_control.on_r7.txt`: the same tree without a fault, rc 0.
- `red/r7_checks_on_r6_engine_remeasured.txt`: the round-7 checks (`refused_marker`, `refused_stage`,
  `marker_lock`, `flock_error`) on the r6 engine, re-run now: PASS 44 FAIL 32, 76 checks. It matches the
  reviewer's re-measure and replaces the r7 file's 42/30 (72 checks).
- `red/r8_checks_on_r7_engine.txt`: the round-8 checks (`sibling_kill`, `sibling_wipe`, `marker_pre`, `stop_pin`,
  `parent_lock`, `autostash`, `flock_error`) on the r7 engine: PASS 56 FAIL 82. Every new check fails on r7
  (control needle: the instrument sees the defect).
- `red/r8_checks_on_r8_engine_green.txt`: the same checks on this branch: PASS 138 FAIL 0.

`parent_lock` also found a second member of the class on r7: a user's `index.lock` appearing in the parent after
inspection let r7 move the child and then fail the stage-pin (child moved, pin not staged). On r8 the child is
not moved. Two cases are checked: the lock is there before the advance-pin starts (step 3a refuses, the child is
not moved), and the lock appears while the advance-pin checkout runs, after step 3a passed (fault
`lock-parent-at-pin-checkout`: the stage-pin's own `begin_write` refuses, exit 1, only the checkout ran, the child
is `failed`, the lock is kept and no marker is left).

## Mutants

`tests/sync/test_mutations.py` now holds 273 mutants. Every anchor must occur exactly once in the file it edits
(the harness refuses otherwise). Changes this round:

- Re-anchored to the new structure with the same meaning: RR14, RR38, Q04, Q05, Q09, Q18, RV6F, S01 to S04, S09,
  S10.
- Adopted from the review: RV7A to RV7L. RV7A, RV7B, RV7C, RV7E and RV7I needed new anchors because round 8
  replaced the code they edited; the meaning is kept and stated in each description (RV7I: `O_EXCL` replaced by
  `O_TRUNC`, the only way to overwrite a marker that is left). RV6A to RV6G stay adopted.
- Own mutants T01 to T17 (17), each a member of the RV7-1 class or of RV7-6.

| Run | Mutants | Killed | Survived | File |
|---|---|---|---|---|
| 1 (every mutant touched this round) | 56 | 52 | 4 (S08, RV7G, T15, T17) | `mutants/mutants_r8_run1.txt` |
| 2 (the four survivors, after the fixes below) | 4 | 4 | 0 | `mutants/mutants_r8_run2_survivors.txt` |

The four survivors were test gaps, not equivalent mutants:

- S08: the unit test for the allow-list refusal had no write token, so the token check refused it first and the
  allow-list was never reached. The test now passes a live token and asserts `("refused", False)`.
- RV7G (root run lock taken blocking): the reviewer's evidence kills it with `chaos`; its suite list now runs
  `chaos` too (killed in 436 s).
- T15 and T17: no check covered a lock that appears after step 3a passed. The late `parent_lock` case (above)
  kills both.

RV7I dies in `unit` (no chaos needed). Run 1 was made before the merge of `origin/main`; the merge changed no file
under `scripts/sync/` or `tests/sync/` (checked with `git diff 66591e5d HEAD -- scripts/sync tests/sync`, empty).
The full mutation run over all 273 mutants was not repeated this round.

## Suite runs

All runs were made under `systemd-run --user --scope -p TasksMax=2000 nice -n 10`, one at a time, host load
under 30.

| Run | When | Result | File |
|---|---|---|---|
| `tests/sync/run_all.sh --quick`, run 1 | after the merge | `RUN_ALL: PASS`, rc 0 | `runs/run_all_quick_1.txt` |
| same, run 2 | after the merge | `RUN_ALL: PASS`, rc 0 | `runs/run_all_quick_2.txt` |
| same, run 3 | after the merge | `RUN_ALL: PASS`, rc 0 | `runs/run_all_quick_3.txt` |
| `CM-SYNC-UPSTREAMS-FF-ONLY` | after the merge | PASS (29 call sites, 56/56 forbidden shapes refused, needle 25/25), rc 0 | `runs/gate_run.txt` |
| gate meta-test | after the merge | PASS (91 cases), rc 0 | `runs/gate_meta.txt` |
| `tests/sync/test_robustness.sh` | after the merge | PASS 395 FAIL 0, rc 0 | `runs/test_robustness_1.txt` |
| `tests/sync/test_chaos.sh` | before the merge | PASS 58 FAIL 0 | `runs/test_chaos_1.txt` |
| `tests/sync/test_perf.sh` | before the merge | PASS 13 FAIL 0 | `runs/test_perf_1.txt` |
| `tests/sync/test_faults.sh` | before the merge | PASS 21 FAIL 0 | `runs/test_faults_1.txt` |

Quick-suite counts (each run): unit 111, integration 149, e2e 24, full automation 34, security 83,
determinism 15, ui 26, hardening 119, all FAIL 0, plus the gate. The verdict lines of the three runs, with
durations removed, have the same sha256 (`e3165c41...`). The chaos, perf and faults runs were made on commit
`66591e5d`; the merge did not change any file under `scripts/sync/`, `tests/sync/` or the gate, so they were
not repeated.

## Landing

- Branch `sync-r8`: `66591e5d` (the round-8 fixes) on top of the round-7 head `baa88df8`, then `a2455f56`, a
  merge of `origin/main` `d0a6832f` (CON-312 installer SIGPIPE). Conflicts: `CHANGELOG.md` (both entries kept,
  main's first) and the generated census line of `docs/guides/full_suite_runner_guide.md`, regenerated with
  `bash scripts/run_full_suite.sh --sync-guide`; `--verify-manifest` then gives `RESULT: MANIFEST-OK`
  (total=932).
- `112fc6ec`: a second merge of `origin/main` `464cd498` (CON-313 workable-items `created_at`), which moved while
  this round ran. The same two files conflicted and were resolved the same way; `--verify-manifest` gives
  `RESULT: MANIFEST-OK` (total=935). Neither merge changed a file under `scripts/sync/`, `tests/sync/` or the gate
  and its meta-test (`git diff --name-only 66591e5d 112fc6ec` over those paths is empty), so the suite runs above
  hold for the final tree. The evidence commit follows.
- Nothing was pushed. Landing on `main` waits for the independent review of round 8 (§11.4.142, §11.4.288).

## Honest limits

- Everything here is PROVISIONAL and gate-logic class. No forge was contacted.
- The in-process driver is a test double for the environment (signal, clock, kernel error, a foreign marker or
  lock). The engine and git are real.
- A Python exception escaping after a marker was created still leaves the marker and the state
  `write-in-progress`, by design (a later run reports a write that did not end normally).
- A git directory left in an unresolved state blocks further writes into it for the rest of the run; a later run
  sees the marker and reports it. That can block more than strictly needed (for example after a refused token);
  it never writes over an unresolved write.
- The defaults change (setup and post-update hook defaults) is not part of this round, as instructed.
