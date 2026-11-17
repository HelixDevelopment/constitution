# Sync-all-upstreams — round-6 evidence (CON-PENDING-SYNC-UPSTREAMS)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-14 |
| Last modified | 2026-11-14 |
| Status | PROVISIONAL (pending the round-6 independent review); not VERIFIED-DONE |
| Status summary | Round-6 structural fix of the round-5 review (NO-GO, RV5-1 to RV5-10). Evidence class: gate-logic / unit class per §11.4.289(C)(2) (local `file://` bare repositories, smudge-filter fixtures, a git shim that plays the user; no forge, no network). |
| Issues | open items listed below |
| Fixed | RV5-1 to RV5-10 (table below) |

## Contents

| Path | What it is |
|---|---|
| `class_inventory.md` | The two classes enumerated in full: (1) a write unit is interrupted, killed or limited (W1 to W15); (2) a mutation of this batch's guards survives. Each member names the test or mutant that holds it. |
| `ground_truth/` | `git_signal_lock_experiment.py`, run twice (`run1.txt`, `run2.txt`, identical lock fields): with git 2.53.0 a checkout ended by SIGTERM exits -15 and leaves no `index.lock`; ended by SIGKILL it exits -9 and leaves `index.lock`. Both leave untracked leftovers. This is why a write's own limit sends SIGTERM first. |
| `red/robustness_r6_checks_on_r5_engine.txt` | RED: the round-6 robustness suite against the ROUND-5 engine: PASS 39 FAIL 35. |
| `green/robustness_r6_checks_green.txt` | GREEN of the same checks on the round-6 engine: PASS 76 FAIL 0 (the new checks, run alone). |
| `green/run1/`, `run2/`, `run3/` | Every sync suite, the gate and the gate meta-test, three times on the final tree (`summary.txt` per run, with times and load). |
| `green/compare_normalised_summary.txt` | The verdict lines of the three runs with times and load removed; the three are byte-identical. |
| `green/mutants_new_first_pass.txt`, `green/mut_new2.txt` | The new and re-anchored mutants, first pass (34 of 37 killed; Q06, Q09, Q17 survived) and re-runs after the fixes (Q06, Q09, Q12, Q17, Q18, Q19 killed). |
| `green/mut_full.txt` | The full mutation table on the final tree. |
| `green/m70_hardening.txt` | M70 is killed by assertion (the symlink cases fail), not only by a timeout. |
| `green/gate_mut2.txt` | Gate meta-test: PASS, 91 cases. |
| `green/mut_full_times.txt` | Start and end time of the full mutation table. |
| `SHA256SUMS` | sha256 of every file in this directory. |

## Results on the final tree (runs 1 to 3, identical verdicts)

| Suite | Result |
|---|---|
| unit | PASS 101 FAIL 0 |
| integration | PASS 149 FAIL 0 |
| e2e | PASS 24 FAIL 0 |
| full automation | PASS 34 FAIL 0 |
| security | PASS 83 FAIL 0 |
| determinism | PASS 15 FAIL 0 |
| ui | PASS 26 FAIL 0 |
| hardening | PASS 119 FAIL 0 |
| chaos | PASS 58 FAIL 0 |
| perf | PASS 13 FAIL 0 |
| faults | PASS 21 FAIL 0 |
| robustness | PASS 196 FAIL 0 |
| gate CM-SYNC-UPSTREAMS-FF-ONLY | PASS |
| gate meta-test | PASS (91 cases) |
| mutation table | 223 mutants: 222 killed, 1 equivalent (M37), 0 survived, 0 harness errors (`green/mut_full.txt`, 18:18 to 22:24 UTC) |

## Findings of review round 5 and their status

| Finding | Status | Where |
|---|---|---|
| RV5-1 a write is killed half-way | Fixed. A write (level 0) is never ended by `--timeout`, `--deadline` or a stop signal. It has its own limit, `--write-timeout` (default 3600 s). When that limit is reached the write's process group gets SIGTERM, then SIGKILL only after `WRITE_KILL_GRACE` (30 s); reads keep `KILL_GRACE` (5 s). Such a write is `write-killed:<op>` (FAILED, exit 1), with the lock files left recorded and recovery steps printed (never run automatically). A write-in-progress marker is written before each write and cleared after; if the engine itself dies the next run says `write-interrupted-earlier` and never blames the user. If the marker cannot be written, the write does not start. The docs that said "a write is never killed" are corrected. | class 1 W1 to W15; unit `RoundSix` and `Integrate`; robustness `write_deadline`, `write_timeout`, `write_kill` (live smudge-filter fixtures), `marker_*`, `stale_marker`; mutants Q01 to Q19 |
| RV5-2 lock open failure reported as "another run holds" | Fixed: an open error is FAILED (exit 1) with the OS error, not exit 7. | robustness `lock_open`; mutant Q11 |
| RV5-3 staged gitlink on the root fast-forward gives FAILED | Fixed: checked before the merge; attention (exit 4), the stage is kept. | robustness `staged_root`; mutant Q10 |
| RV5-4 six reviewer mutants survive | Fixed: R01, R14, R21, R29, R36, R37 carried into the table as RR01 to RR37 with the reviewer's discriminators; all killed. | `tests/sync/test_mutations.py` RR rows |
| RV5-5 Ctrl-C at the interactive prompt waits for Enter | Fixed: the wait polls the stop flag; Ctrl-C ends it (exit 8, nothing moved). | unit `test_prompt_ends_on_a_stop_signal` (bounded by a thread join); robustness `ctrl_c`; mutant Q12 |
| RV5-6 refused fetches labelled as unreachable | Fixed: `not-fetched-interrupted`, no remote named. | robustness `interrupted_labels`; mutant Q14 |
| RV5-7 `update=none` child followed with no reason | Fixed: not followed, reason `not-followed:update-none` (and the same for other non-checkout strategies). | robustness `update_none`; mutant Q13 |
| RV5-8 R39, R40 survive | Fixed by killing, not by marking EQUIVALENT: new unit tests `test_no_process_starts_after_a_second_signal` and `test_a_stop_starts_no_write`. | mutants RR39, RR40 |
| RV5-9 ssh workaround only in the manual | Fixed: FAQ question 17 (`~/.ssh/config` or `core.sshCommand`). | `docs/faq/sync_upstreams_faq.md` |
| RV5-10 / OPEN-5 harness host-safety | Fixed: `timeout -k 10 30` at the FIFO step of `test_hardening.sh`; M70 now dies by assertion. | `green/m70_hardening.txt` |

## Open items, stated honestly

- FAQ question 18 was reworded after the three suite runs and the mutation table had finished. No suite, gate or
  mutant reads the FAQ (the engine wrapper names it in a comment only), so the results above still apply.

- W13: if the engine itself is SIGKILLed (or OOM-killed) outside its own control, git may leave `index.lock`. No
  user-space process can act after its own SIGKILL. The marker reports an interrupted write; the repair is manual and
  documented in the manual.
- RR35 is killed after about 600 s: the mutant makes the lock a blocking `flock`, so the engine waits for ever, and the
  check fails when its bounded `subprocess.run(timeout=600)` raises. The kill is real, but slow. Lowering that one
  call's timeout would make it fast; this is a test-speed improvement, not done in this round.
- Defaults: the code on this revision keeps `off` (`scripts/setup.sh`) and `offline` (post-update hook), so nothing is
  fetched unless the user opts in. An operator decision of 2026-11-14 (relayed, not verbatim) moves them to on,
  online and bounded; that change is separate work and is NOT made here.
- Real forges (ssh keys, rate limits, large repositories) remain UNCONFIRMED until run by the operator.
- Effort of the agent that made this round: UNKNOWN (not settable or readable on the dispatch path).
