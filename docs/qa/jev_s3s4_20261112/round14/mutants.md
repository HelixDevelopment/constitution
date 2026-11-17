# Round 14 mutants

One exact substitution per mutant (`tools/mkmut.py.txt`, `tools/mut14.txt`), generated from the final producer and
census; each mutant runs its suites in order and stops at the first suite with a failure (`tools/mutrun.sh.txt`,
`tools/cmutrun.sh.txt`, `tools/chain14.sh.txt`). Raw summary: `runs/mut_summary.txt`; every run: `runs/mut_*.txt`
and `runs/cmut_*.txt`.

The chain was cut by a session interruption on 2026-11-17 (about 09:23 CET) while census mutant W33 ran; every
mutant before W33 had its summary line. `tools/chain14_resume.sh.txt` ran the remaining steps of the chain unchanged
(W33 from the start, W35, W36, RCTRL); the partial W33 output is kept as
`runs/cmut_W33_mention_ascii_interrupted_partial.txt` and the RESUME line in `runs/mut_summary.txt` marks the cut.

The control RCTRL then ran into the runner's 2400 s timeout in the sweep (`runs/mut_RCTRL_sweep_s4_round14.txt`:
636 cells passed, 0 failures, rc 124) while other work held the host load near 49, and mutrun.sh recorded that as a
kill. That was a defect of mutrun.sh, fixed test-first (`tools/test_mutrun.sh.txt`; `runs/test_mutrun_RED.txt`
before the fix, `runs/test_mutrun_GREEN.txt` after, `runs/test_mutrun_mutant.txt` with the fix removed). The
control was re-run as RCTRL2 on the three heavy sweep parts, which together run every cell of the sweep.

| Mutant | What it changes | Result |
|---|---|---|
| M1_intent_resolved_regardless | fixer: a dead starter's intent judged whatever its start process does (the round-13 rule) | KILLED-by test_s4_round14 fails=19 |
| M2_group_ignored | fixer: child_running ignores the start process group (a zombie leader with live members reads gone) | KILLED-by test_s4_round14 fails=1 |
| M3_child_reuse_ignored | fixer: child_running ignores a changed start time (a reused pid reads running) | KILLED-by test_s4_round14 fails=1 |
| M4_ungated_start | fixer: the start process runs llmctl on any line or end-of-file, not only on `go` | KILLED-by test_s4_round14 fails=16 |
| M5_child_judged_at_resolve_time | fixer: the start process judged when the intent is resolved, not at the observation ticket | KILLED-by test_s4_round14 fails=5 |
| M6_intent_without_child | fixer: the intent written without its start process | KILLED-by test_s4_round14 fails=8 |
| M7a_legacy_always_gone | fixer: a legacy intent (no start process) judged at once | KILLED-by test_s4_round14 fails=1 |
| M7b_legacy_never_gone | fixer: a legacy intent never judged | KILLED-by test_s4_round14 fails=1 |
| M8_no_went_check | fixer: a start process that ran no llmctl recorded with its own exit code, not as rc 75 | KILLED-by test_s4_round14 fails=2 |
| M9_mark_without_gate | fixer: the mark written without a gated start process | KILLED-by test_s4_round14 fails=2 |
| M10_gate_open_ignores_proc | fixer: gate_open does not refuse without /proc/self/fd | SURVIVED r14 r13 sw14 |
| M11_no_child_start_is_gone | fixer: a start process with no recorded start time reads gone (not fail-safe running) | KILLED-by test_s4_round14 fails=3 |
| R01_arm_no_retry | round-12 reviewer: the release's arm lock wait is not retried | KILLED-by r13 fails=2 |
| R02_markttl_no_recordwaits | round-12 reviewer: MARK_TTL without the record waits | KILLED-by r8 fails=2 |
| R03_adopt_after_own_start | round-12 reviewer: a unit this acquire tried to start can be adopted | KILLED-by r10 fails=2 |
| R04_adopt_degraded | round-12 reviewer: a degraded unit can be adopted | KILLED-by pl fails=3 |
| R05_rc75_counts_after_arm | round-12 reviewer: rc 75 counted as a start after the arm | KILLED-by r11 fails=3 |
| R06_stopowed_for_rc75 | round-12 reviewer: an owed stop for a refused start | KILLED-by r13 fails=1 |
| R07_noset_rc75_released | round-12 reviewer: a refused start with no set recorded as started | KILLED-by r11 fails=5 |
| R08_owed_retry_fail_is_success | round-12 reviewer: a failing owed retry reads as success | KILLED-by r13 fails=2 |
| V01_intent_reuse_blind | round-13 reviewer (WV01): the starter's start time ignored (a reused starter pid reads alive) | KILLED-by test_s4_round14 fails=2 |
| V02_degraded_intent_kept | round-13 reviewer (WV02): a degraded unit under a dead intent gets no set | KILLED-by test_s4_round14 fails=2 |
| V08_mark_intent_refusal_is_stale | round-13 reviewer: the intent refusal returns the stale code (2) instead of 1 | KILLED-by test_s4_round14 fails=3 |
| V03_intent_state_always_unknown | round-13 reviewer: the unit state under a dead intent always unknown | KILLED-by test_s4_round14 fails=16 |
| V04_setexists_keeps_intent | round-13 reviewer: an existing set made constitution-started keeps the intent | KILLED-by r13 fails=1 |
| V05a_finish_leaves_empty_map | round-13 reviewer: the record leaves an empty start_intents map | KILLED-by test_s4_round14 fails=12 |
| V05b_recover_leaves_empty_map | round-13 reviewer: the recovery leaves an empty start_intents map | KILLED-by test_s4_round14 fails=1 |
| V06_intent_is_lease | round-13 reviewer: the intent is written as a lease | KILLED-by test_s4_round14 fails=18 |
| V07_adopt_checks_other_profile | round-13 reviewer: adoption checks another profile's intent | KILLED-by test_s4_round14 fails=3 |
| V14_finish_removes_only_on_rc0 | round-13 reviewer: the record removes the intent only on rc 0 | KILLED-by test_s4_round14 fails=2 |
| V10_recover_after_observe | round-13 reviewer: the intent recovery runs after the observation, not in it | SURVIVED r14 r13 sw14 |
| V15_adopt_skips_only_live_intent | round-13 reviewer: adoption skips only a LIVE starter's intent | KILLED-by test_s4_round14 fails=3 |
| V20_finish_drops_start_half | round-13 reviewer: the record matches the intent by pid only | SURVIVED r14 r13 sw14 |
| W22_mention_lookbehind_digit | census: git after a digit not a mention | SURVIVED rc=0 fails=0 passes=125 |
| W23_mention_case_sensitive_both | census: mention case-sensitive | KILLED rc=1 fails=123 passes=2 |
| W24_ls_perm_any | census: any 9 characters as ls permissions | SURVIVED rc=0 fails=0 passes=125 |
| W25_rc_max_999 | census: exit codes up to 999 | KILLED rc=1 fails=123 passes=2 |
| W26_no_trailing_pop | census: the trailing empty line kept | KILLED rc=1 fails=123 passes=2 |
| W27_scope_no_slash | census: scope prefix `docs/qa` without the slash (round-13 reviewer F7) | KILLED rc=1 fails=1 passes=124 |
| W28_exec_ignored | census: the executable bit ignored | KILLED rc=1 fails=123 passes=2 |
| W33_mention_ascii | census: mention matching ASCII-only | SURVIVED rc=0 fails=0 passes=125 |
| W35_shape_mention_first_4k | census: mention searched in the first 4096 characters only (round-13 reviewer F6) | KILLED rc=1 fails=1 passes=124 |
| W36_splitlines | census: splitlines instead of split on newline | SURVIVED rc=0 fails=0 passes=125 |
| RCTRL | control: no change, run from a mutant directory | NO-RESULT sweep_s4_round14 (timeout rc=124, no FAIL line; recorded as `KILLED-by sweep_s4_round14 rc=124 (no FAIL line)` by mutrun.sh before its timeout fix, reclassified by the fixed rule: a run cut by the clock decided nothing) |
| RCTRL2 | control: no change, run from a copy of the RCTRL directory; r14 and the three heavy sweep parts (re-run of RCTRL) | SURVIVED r14 tests/jev/s4_round14_sweep_x_chaos_test.sh tests/jev/s4_round14_sweep_y_chaos_test.sh tests/jev/s4_round14_sweep_zd_chaos_test.sh |

## Survivors and the argument for each

### M10: the second fail-closed check refuses its case

The rule "no /proc, no start" has two independent checks: `gate_open` refuses without `/proc/self/fd` (the check M10
removes), and `mark_start_locked` refuses when the start process has no pid or no start time (the check M9 removes).
The start time is `proc_start` of the start process, read from `/proc/<pid>/stat`, so without /proc it is empty. With
M10 the no-/proc case therefore still gets no mark and no start: the second check refuses it. Row R14-7 shows that
second check on an injected empty start time (a copy of the producer whose `gate_open` cannot read it): the head and
M10 refuse the mark, M9 starts the unit (`runs/r14rowcheck_M9_mark_without_gate.txt`: 1 start, 1 stop;
`runs/r14rowcheck_M10_gate_open_ignores_proc.txt`: 55 passes). M10 itself is not killable by a row of this runner:
it needs a run without /proc, and the producer then cannot read any process start time (its marks and intents carry
them), which is outside the gate-logic runner (its bwrap sandbox mounts /proc). No run of this round had no /proc; the
no-/proc path is UNCONFIRMED by a run and stated as an argument.

### V20: equivalent (the round-13 reviewer's argument, unchanged by round 14)

V20 removes the start-time half of the record's match (`finish`: the intent is removed when its pid equals this
process's pid, whatever its `pid_start`). The mark refuses while any start intent of the profile exists, so the intent
of the profile at record time is the one this process wrote at its mark: no other process can write one while it
exists, and `intents_locked` never removes it, because it judges only an intent whose starter is gone and this process
is alive (it is recording). An intent with this pid and another start time therefore cannot be present at the record,
and the two matches remove the same intent. Round 14 adds the start process to the intent; it changes neither the
mark's refusal nor the judging of a live starter. Ran: r14 (55 passes), r13 (76), the sweep (703).

### V10: outcome-equivalent by argument, UNCONFIRMED (the round-13 reviewer's verdict)

V10 moves `intents_locked` from before the observation loop of `obs_locked` to after its save. A set made from a dead
starter's intent is written with a pending health whose sequence number is the observation counter at that moment,
which is not below the observation ticket, so the observation loop of the head skips it; in the mutant the loop runs
before the set exists. Both orders end with the same set (constitution-started, an owed stop, pending health) or with
the intent removed (no unit) or kept (state unknown). Round 14 does not change this: the dead-starter judgement reads
`OBS_GONE`, taken with the ticket, so it does not depend on where in `obs_locked` it runs. The intermediate registry
state between the two writes differs and no row pins it; the argument is not proven by a run. Ran: r14 (55), r13
(76), the sweep (703).

### Census survivors W22, W24, W33, W36: no difference on this tree (measured), harmless by the reviewer's verdict

The round-13 reviewer judged W22, W24, W33 and W36 harmless; round 14 did not touch the parts they change. The census
output of each mutant on the vehicle head was compared line by line with the head census
(`tools/census_survivor_diff.sh.txt`, `runs/census_survivor_diff.txt`): see that file for the counts and its two
controls (head against head identical; the killed mutant W23 differs). Result: 0 differing lines for each of the four
survivors on 675 output lines (members=672, unscrubbed=0). The positive control is coarse: W23 makes the census exit 2,
so its whole output differs (676 lines); it shows that the comparison sees a difference, while a one-line difference is
seen by `diff` by construction, not by this needle. Identical output proves only that the mutant
changes nothing the census reports on this tree, not that it can never matter: W22 (no mention after a digit), W24
(any nine characters as `ls` permissions), W33 (ASCII-only case folding) and W36 (`splitlines`, which also splits on
`\r`, form feed and other separators) each differ on inputs this tree does not contain.

### RCTRL and RCTRL2: the control (no change)

RCTRL runs the unchanged producer from a mutant directory; it must survive, or the harness itself fails runs. Its r14
run passed (55); its sweep run of the whole body was cut by the runner's 2400 s timeout at 636 cells with 0 failures
while other work held the host load near 49 (`runs/mut_RCTRL_sweep_s4_round14.txt`, rc 124). The mutrun.sh of the
chain recorded that as a kill; it is not one (see above: fixed test-first, the line reclassified as NO-RESULT).
RCTRL2, an identical copy of the RCTRL directory, re-ran r14 and the three heavy sweep parts, which together run every
cell of the sweep: 55, 263, 263 and 189 passes, 0 failures (`runs/mut_RCTRL2_*`). The control survives.
