# Class inventory, round 6 (CON-PENDING-SYNC-UPSTREAMS)

Two classes are named and enumerated in full (§11.4.276(C)). Each member names the test or mutant that holds it.
Evidence class: PROVISIONAL, gate-logic class (hermetic local repositories, no network, §11.4.289(C)(2)).

## Class 1: a write unit is interrupted, killed or limited

A write unit is a level-0 call of `proc_run_git` (`merge --ff-only`, `checkout`, the pin `add`). The engine has one
spawn point (`proc_run_git`) and one signal point (`proc_kill_group`), so the members below are every way a write can
end other than by finishing.

| Id  | Member | Behaviour now | Held by |
|-----|--------|---------------|---------|
| W1  | per-call limit `--timeout` reaches a write | not applied to writes; a write has its own `--write-timeout` | unit `test_write_has_its_own_limit_not_the_deadline`; mutant Q01 |
| W2  | run deadline `--deadline` passes while a write runs | the write finishes; the deadline is not its limit | robustness `write_deadline` (8 s smudge fixture); unit `test_second_half_of_a_write_and_final_reads_run_after_the_deadline` |
| W3  | first stop signal (SIGTERM/SIGINT) during a write | write finishes, exit 8 | robustness `sigterm_write`, `sigterm_pin`; unit `test_a_stop_signal_never_ends_a_write`, `test_stop_interrupts_a_read_never_a_write` |
| W4  | second stop signal during a write | write still finishes; final reads refused | unit `test_second_signal_is_a_hard_stop`, `test_no_process_starts_after_a_second_signal` (RR39) |
| W5  | the write's own limit expires | SIGTERM, wait `WRITE_KILL_GRACE` (30 s), then SIGKILL; why `write-killed` | unit `test_write_limit_ends_the_call_with_sigterm_first`, `test_real_child_that_ignores_sigterm_ends_with_sigkill_after_grace`, `test_write_gets_the_long_grace_a_read_the_short_one`; robustness `write_timeout` (smudge exits on TERM), `write_kill` (smudge ignores TERM); mutants Q02, Q03, Q16, Q17; gate cases KILLPG-SIGKILL-ONLY, KILLPG-ORDER-REVERSED, KILLPG-SIGINT, KILLPG-SIG-REBOUND, KILLPG-SIG9 |
| W6  | the second half of a pin write (the parent `add`) runs after the deadline | it runs | unit `test_second_half_of_a_write_and_final_reads_run_after_the_deadline` |
| W7  | a write would START after the deadline or after a stop | it is not started; reason stated | unit `test_write_never_starts_after_the_deadline`, `test_a_stop_starts_no_write` (RR40); robustness `no_new_call` |
| W8  | the engine is SIGKILLed or OOM-killed during a write | the next run finds the write-in-progress marker and says so (`write-interrupted-earlier`), never blames the user | unit `test_write_marker_round_trip`, `test_marker_attribution_reasons`; robustness `marker_inspect`, `stale_marker`; mutants Q04, Q05, Q06, Q18, RR37 |
| W9  | the marker cannot be written | no marker, no write; `write-blocked` | unit `test_marker_unwritable_blocks_the_write`; mutant Q18 |
| W10 | a write ends normally | the marker is cleared; a later `--apply` on a clean, current tree clears a stale marker | robustness `marker_success`, `stale_marker`; mutants Q05, Q09 |
| W11 | Ctrl-C at the `--interactive` prompt | the wait ends (exit 8, nothing moved); no blocking read | unit `test_prompt_ends_on_a_stop_signal`; robustness `ctrl_c`; mutant Q12 |
| W12 | a write ended by its limit is reported | FAILED (exit 1), why `write-killed`, recovery steps in the report and manual | unit `test_write_killed_by_its_limit_is_a_known_failure`; mutants Q08, Q16 |
| W13 | the engine itself is SIGKILLed outside a write | no handler can run; honest boundary: git may leave `index.lock`; the marker (W8) covers writes only | ground truth `ground_truth/run1.txt`, `run2.txt` (SIGKILL leaves `index.lock`, SIGTERM does not); documented in the manual |
| W14 | verify reads after a stop | final reads run once, capped; refused after a second signal | robustness `final_cap`; unit `test_no_process_starts_after_a_second_signal`; mutants Q15, RR39 |
| W15 | stage-pin (`add`) ended by its limit | why `write-killed:stage-pin`, FAILED | unit `test_stage_pin_ended_by_its_limit_is_write_killed`; mutant Q19 |

Honest boundary (§11.4.6): W13 is not closed by the engine; no user-space process can act after its own SIGKILL. The
marker shows that a write was in progress; it does not repair `index.lock` (recovery steps are in the manual).

## Class 2: a mutation of this batch's guards survives

Every guard this batch adds or changes has at least one mutant. All are KILLED in `green/mut_full.txt` (full table)
and in `green/mutants_new_first_pass.txt` plus `green/mut_new2.txt` (the first pass and re-runs).

- Q01 to Q19 (own mutants of the round-6 code): see `tests/sync/test_mutations.py` for the exact edits.
- RR01, RR10, RR12, RR14, RR16, RR17, RR21, RR27, RR29, RR35, RR36, RR37, RR38, RR39, RR40: the reviewer's round-5
  mutants R01 to R40 carried into the table (RV5-4, RV5-8). R39 and R40 are KILLED by new unit tests, not marked
  EQUIVALENT.
- M70 (FIFO/symlink report path): KILLED by assertion (`green/m70_hardening.txt`: the symlink cases fail), and the
  FIFO step is bounded by `timeout -k 10 30` (RV5-10, OPEN-5).
- M73: KILLED by `robustness:blind_failed`.
- Gate meta-test (`scripts/gates/cm_sync_upstreams_ff_only_mutation_test.sh`, 91 cases): new cases KILLPG-SIGKILL-ONLY,
  KILLPG-ORDER-REVERSED, KILLPG-SIGINT, KILLPG-SIG-REBOUND, SELECT-OUTSIDE, WAITID-OUTSIDE, UPDATE-STRATEGY-OK-128,
  CONFIG-WRITE-SHAPE. KILL-GROUP-NO-GRACE-ARG was removed: the gate PASSed on it because dropping the argument falls
  back to a safe default, so it was not a defect the gate must catch.
- EQUIVALENT: M37 only (unchanged from round 5).
