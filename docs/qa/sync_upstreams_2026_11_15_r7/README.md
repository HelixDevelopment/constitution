# Sync-all-upstreams, review round 7 fixes (RV6-1 to RV6-6) — evidence

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15 |
| Status | PROVISIONAL (§11.4.290): fixes made, own runs below; independent review of round 7 still owed |
| Roadmap item | CON-PENDING-sync-r7 |
| Evidence class | gate-logic / unit class (§11.4.289(C)(2)): local `file://` bare repositories, real git, an in-process fault driver for the environment (signal, clock, kernel). Forge behaviour (ssh, rate limits, server refusals, large repositories) is UNCONFIRMED |
| Fixer | structural fixer (round 7, §11.4.276(E)), model Opus 5.5, effort UNKNOWN (not settable or readable on this dispatch path) |

## Table of contents

- [What changed](#what-changed)
- [Class: marker lifecycle](#class-marker-lifecycle)
- [RED and GREEN](#red-and-green)
- [Mutants](#mutants)
- [Suite runs](#suite-runs)
- [Landing (RV6-6)](#landing-rv6-6)
- [Honest limits](#honest-limits)

## What changed

- RV6-1 (`scripts/sync/sync_all_upstreams.py`):
  - `Runner.write_refused_now(final)` repeats the run's own refusal rule. Both write sites ask it before they write
    the marker, so a write refused now gets no marker.
  - `GitResult.started` is False when no git process was started. This covers the interrupted, deadline and
    allow-list refusals and `not-runnable` (Popen raised OSError). Both write sites clear their marker when
    `started` is False.
  - `write_marker` removes a marker file it created itself but could not write or fsync. A marker from an earlier
    run is kept.
  - A refused stage-pin add now carries `why = unresolved:stage-pin:<why>`.
- RV6-2: the robustness check `marker_lock` covers a marker plus `index.lock` on a clean tree. This is the SIGKILL
  ground-truth case. The check asserts exit 4 with both `write-interrupted-earlier:<op>` and
  `in-progress-since-write-interrupted:index.lock`; its control run without a marker shows `in-progress:index.lock`.
  The unit test `test_lock_only_leftover_is_attributed` covers the same case.
- RV6-3: the robustness check `flock_error` covers both lock paths. A root flock ENOLCK ends with exit 1 and
  "cannot take the run lock". A per-repository flock ENOLCK ends with exit 1 and "cannot open the run lock". The
  control, EWOULDBLOCK on a repository lock, gives exit 7. The unit test `test_flock_error_is_not_another_run`
  covers the same branch.
- New test-only driver `scripts/sync/inproc_driver.py`. It loads the real engine module, injects one environment
  fault between two engine statements, and leaves every git call on the real binary.
- RV6-4: see [RED and GREEN](#red-and-green).
- RV6-5: the `robustness_checks.py` docstring now uses the same wording as this README (gate-logic / unit class).
- RV6-6: see [Landing](#landing-rv6-6).
- The manual (`docs/manuals/sync_upstreams_manual.md`, revision 7) describes the lock-only leftover and states that
  a refused write writes no marker.

## Class: marker lifecycle

The class is every exit path between the marker write and the end of the write (§11.4.276(C)). The instrument is
`class_inventory_marker_lifecycle.py`, an AST walk over the engine. It has a control needle: `def write_marker` must
be found once and a fake name must be found zero times. On both trees the result is `INSTRUMENT: SEES`. The r6
output is `class_inventory_marker_lifecycle_r6.txt` (6 marker calls). The r7 output is
`class_inventory_marker_lifecycle_r7.txt` (9 marker calls, 3 write calls, 7 `GitResult` returns, each with its
`started` value).

| Member | r6 | r7 | Proof |
|---|---|---|---|
| stop or deadline before the marker | marker written, never cleared | no marker | `refused_marker` (stop-before, deadline-before), unit `test_write_refused_now_is_runs_own_refusal` |
| stop or deadline between the marker and `r.run` | marker left (reproduced by the reviewer) | marker cleared (`started` False) | `refused_marker` (stop-after, deadline-after) |
| refused by the allow-list | marker left | cleared | unit `test_started_is_false_only_without_a_process` |
| git cannot be started (`not-runnable`) | marker left | cleared | `refused_marker` (spawn-fails-write) |
| git answered (success or declared failure) | cleared | cleared (unchanged) | round-6 checks `marker_success`, `write_*` |
| git started, then killed, signalled or undeclared rc | kept (correct: a write did not end normally) | kept | round-6 checks `write_kill`, `write_timeout`, `stale_marker` |
| marker file created but not written or fsynced | half-written marker left | removed if it was ours; an earlier marker is kept | unit `test_half_written_marker_is_removed` |
| stage-pin: second stop before the marker | marker written | no marker | `refused_stage` sub-case `before` |
| stage-pin: second stop after the marker, add refused | marker left | cleared, `why` set | `refused_stage` |
| stage-pin: add cannot be started | marker left | cleared | `refused_marker` (spawn-fails-write, pin case) |
| a Python exception escaping after the marker | kept | kept (deliberate, conservative: the engine cannot tell whether git ran) | not changed; documented here |

Each `refused_marker` case also runs a later `--check --no-fetch` after a user edit. That check must report
`dirty-tree` and must not report `write-interrupted`. This is the reviewer's probe turned into a check.

## RED and GREEN

- `red/robustness_r7_checks_on_r6_engine.txt`: the round-7 checks run against the r6 engine give PASS 42 FAIL 30.
  This is RED.
- `red/robustness_r6_checks_on_r5_engine_remeasured.txt` (RV6-4): this file re-measures the 15 round-6 checks
  `write_deadline` to `stale_marker` against the r5 engine. The result is PASS 42 FAIL 40. The old r6 RED (39/35)
  was captured before the round-6 check set was final. The reviewer's 39/37 used a different selection of checks.
  The three counts differ only because the check sets differ; every count shows the r5 engine failing the round-6
  checks.
- GREEN: see the robustness run in [Suite runs](#suite-runs).

## Mutants

- `mutants/r7_mutants_run1.txt` holds the round-6 reviewer mutants RV6A to RV6G, adopted verbatim, and 14 own
  mutants S01 to S14. On the first run 20 were killed and S04 survived. S04 removes the pre-check at the stage-pin
  site.
- After S04 survived, the `hardstop-before-stage-marker` fault and the `refused_stage` sub-case `before` were added.
  `mutants/r7_mutant_S04_after_check.txt` shows S04 KILLED by `robustness:refused_stage`.
- `mutants/robustness_only_RV6B_marker_lock.txt` and `mutants/robustness_only_RV6E_flock_error.txt` show that the
  robustness checks alone also kill RV6B (FAIL 2) and RV6E (FAIL 4). Neither depends on the unit suite alone.
- `runs/mutants_r7_final.txt` is the re-run of all 21 on the final, merged tree.
- The full mutation table (about 240 rows) was not re-run in this round, because of time. The rows that were re-run
  are listed in `runs/`.

## Suite runs

All runs are in `runs/`. Each file ends with `rc=<exit status>`.

- `run_all_quick_{1,2,3}.txt`: `tests/sync/run_all.sh --quick` (unit, integration, e2e, full_automation, security,
  determinism, ui, hardening, gate `CM-SYNC-UPSTREAMS-FF-ONLY`). It was run three times on the merged tree, and the
  verdict lines must match across the three runs.
- `gate_meta_{1,2,3}.txt`: `scripts/gates/cm_sync_upstreams_ff_only_mutation_test.sh`, run three times.
- `test_robustness_1.txt`, `test_chaos_1.txt`, `test_perf_1.txt`, `test_faults_1.txt`: each run once.

## Landing (RV6-6)

The round-6 base `bd0036bd` was behind main. This branch merges `origin/main` `763726e0` (commit `08e14d73`). The
only conflict was the generated census line in `docs/guides/full_suite_runner_guide.md`. The fix was to take main's
side, run `bash scripts/run_full_suite.sh --sync-guide` to regenerate it, and then run
`bash scripts/run_full_suite.sh --verify-manifest`, which printed `RESULT: MANIFEST-OK` (census total 931). If main
moves again before landing, the lander repeats those two commands.

## Honest limits

- Everything here is PROVISIONAL and gate-logic class. No forge was contacted, and nothing here proves behaviour
  against GitHub or GitLab.
- The in-process driver is a test double for the environment: it injects a signal, the clock or a kernel error.
  The engine and git are real. Exact signal timing on a real terminal is not reproduced.
- A Python exception escaping after the marker still leaves the marker, by design. A later run then reports that
  a write did not end normally. That is a conservative over-report, never a silent loss.
- The defaults change (setup and post-update hook defaults) is not part of this round, as instructed.
