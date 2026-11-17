# Round 13 mutants

Every mutant is built by `tools/mkmut13.py.txt` as a copy of `scripts/jev` (or of `scripts/validation`) with ONE exact
substitution, matched exactly once (the build refuses any other match count). The reviewer's mutants (R0x, RCTRL, CMR1
to CMR4) use the reviewer's substitution text. Producer mutants run through `tools/mutrun13.sh.txt` (suites in order,
stop at the first suite with a failure); census mutants through `tools/cmutrun.sh.txt` (`--only-census --census <mutant>`).
All results: `runs/mut_summary.txt` (the line `== census final` marks the census runs on the final test file).

## Producer (`scripts/jev/jev-place.sh`)

| Mutant | Origin | What it breaks | Result | Killed by |
|---|---|---|---|---|
| `R08_owed_retry_fail_is_success` | reviewer | an owed-stop retry failure counts as success | KILLED (2) | r13 |
| `R01_arm_no_retry` | reviewer | the arm path never retries the owed stop | KILLED (2) | r13 |
| `R06_stopowed_for_rc75` | reviewer | a refused start (rc 75) records an owed stop | KILLED (1), full chain | r13 (R13-5c) |
| `R02_markttl_no_recordwaits` | reviewer | the mark TTL ignores record waits | KILLED (2), full chain | r8 |
| `R03_adopt_after_own_start` | reviewer | adoption runs after this process's own start | KILLED (2), full chain | r10 |
| `R04_adopt_degraded` | reviewer | a degraded unit is adopted | KILLED (3), full chain | pl |
| `R05_rc75_counts_after_arm` | reviewer | an rc 75 is counted after the arm | KILLED (3), full chain | r11 |
| `R07_noset_rc75_released` | reviewer | rc 75 with no set releases the lease | KILLED (5), full chain | r11 |
| `RCTRL` | reviewer | control: the unchanged producer (no substitution) | SURVIVED, full chain (as a control must) | - |
| `F11_no_intent_write` | own | the start intent is never written | KILLED (9) | r13 |
| `F12_adopt_ignores_intent` | own | adoption ignores a live intent | KILLED (6) | r13 |
| `F13_mark_ignores_intent` | own | a second start ignores a live intent | KILLED (2) | r13 |
| `F14_recovery_no_stop_owed` | own | recovery of a dead intent owes no stop | KILLED (2) | r13 |
| `F15_finish_drops_any_intent` | own | the finish drops the pid half of the own-intent check | SURVIVED, full chain (every suite) | - (equivalent, below) |
| `F15b_finish_drops_every_intent` | own | the finish removes every intent | KILLED (1), full chain | r13 (R13-2h) |
| `F16_unknown_state_removes_intent` | own | an unknown starter state removes the intent | KILLED (2) | r13 |
| `F17_live_intent_treated_dead` | own | a live intent is treated as dead | KILLED (14) | r13 |
| `F18_recovery_operator_owned` | own | a recovered set is marked operator-owned | KILLED (6) | r13 |
| `F19_no_recovery_call` | own | intent recovery is never called | KILLED (11) | r13 |
| `F1A_dead_intent_set_stays_operator` | own | the set of a dead intent stays operator-started | KILLED (1) | r13 |
| `F1B_absent_keeps_intent` | own | an absent unit keeps the intent | KILLED (2) | r13 |

The rows without "full chain" ran on an earlier version of the round-13 test file; the final file only adds rows
(R13-5c, R13-2h) and corrects a comment, so those kills still hold, but they were not re-run on the final file.
The "full chain" rows ran every suite on the final test file (sha256 prefix d7612dbc8a2ef743).

### R06 (reviewer): the first run survived

`R06_stopowed_for_rc75` survived the first version of R13-5 (the line `MUT R06_stopowed_for_rc75 SURVIVED r13` in
`runs/mut_summary.txt`; that run's own output file was overwritten by the full-chain re-run, whose result is in the
table above, and is not kept). Measured cause
(`runs/probe5_R06.txt`): in R13-5 the set is made by this acquire's own mark, so after a refused start it is
constitution-started by nobody, and the next observation drops every set with no lease that is not
constitution-started, with or without a `stop_owed` field. The owed stop that R06 adds is dropped with the set and
cannot be seen. R13-5c (crafted: the set already constitution-started when the foreign stopping mark is written) is the
case where the rule is visible; R06 fails it (`runs/probe5c_R06.txt`: expected `false`, got `true`), the head passes it
(`runs/probe5c_head.txt`). The R13-5 row is kept, with its comment corrected (it had claimed the owed stop would keep
the set).

### F15: equivalent, measured

`F15_finish_drops_any_intent` removes the pid half of the "remove only my own intent" check and keeps the start-time
half. It survives every row. A state that tells it apart needs a LIVE foreign intent carrying this process's start time
and another pid. Crafting one fails: the observation compares the intent's start time with the real start time of its
pid, finds them different, reads the intent as a reused pid (a dead starter) and recovers it; the head then fails the
crafted row exactly like the mutant (measured during authoring: both reported `got [null null]`; that probe's output
files were overwritten by a later probe, so they are not in `runs/`, and the crafted row was not kept). A real such state needs
two processes started in the same clock tick AND a second start on the same profile, which `mark_start_locked` refuses
while an intent exists. Judged equivalent behind two independent guards. `F15b_finish_drops_every_intent` (the whole
condition removed) is killed by R13-2h (`runs/probe2h_F15b_finish_drops_every_intent.txt`; head:
`runs/probe2h_head.txt`).

## Census (`scripts/validation/git_env_class_census.py`)

The census runs its own built-in control needles (the shape samples in `needles()`) before it judges any tree; a mutant
that breaks the shape rule makes the census BLIND (exit 2) on every row, so every row fails. That is a real kill, but it
does not show that the test file's own rows kill the mutant. Each such mutant was therefore run a second time as
`<name>_noST`: the same mutant with the shape-needle loop iterating nothing (`tools/mk_nost.py.txt`), so only the test
rows can kill it.

| Mutant | Origin | With the census self-check | Self-check off (`_noST`) |
|---|---|---|---|
| `CR12_round12_census` | the round-12 census (RED baseline): the whole round-12 file | KILLED by C2rc16 C2rc17 C2rc18 C2rc21 C2rc22 C2rc24 C2rc25 C2rc26 | not needed (the self-check does not fire on it) |
| `CMR1_shape_rule_r12_case_sensitive` | reviewer: shape-rule exclusion back to case-sensitive `\bgit\b` | KILLED, BLIND on every row (120 failures) | KILLED by C2rc16 C2rc17 C2rc18 |
| `CMR1b_shape_rule_r12_exact` | reviewer: the exact round-12 exclusion `\bgit\b\|GIT_` | KILLED, BLIND on every row (120 failures) | KILLED by C2rc16 C2rc17 C2rc18 |
| `CMR2_scope_docs` | reviewer: shape scope widened from `docs/qa/` to `docs/` | KILLED by C2rc19 | not needed (the self-check does not fire on it) |
| `CMR3_no_total_header` | reviewer: no `total N` header required | KILLED, BLIND on every row (120 failures) | KILLED by C2rc20 C2rc25 |
| `CMR4_rc_ws_tolerant` | reviewer: `.rc` tolerates whitespace around the status | SURVIVED | not needed (the self-check does not fire on it) |
| `CF1_rc_unicode_digits` | fixer: `.rc` status without `re.ASCII` | KILLED, BLIND on every row (120 failures) | KILLED by C2rc21 |
| `CF2_ls_unicode` | fixer: listing line without `re.ASCII` | KILLED, BLIND on every row (120 failures) | KILLED by C2rc22 C2rc24 C2rc26 |
| `CF3_total_unicode` | fixer: `total N` without `re.ASCII` | KILLED, BLIND on every row (120 failures) | KILLED by C2rc25 |
| `CF4_shape_mention_case_sensitive` | fixer: the exclusion is MENTION without `re.I` | KILLED, BLIND on every row (120 failures) | KILLED by C2rc16 C2rc17 |
| `CF5_shape_mention_word_boundary` | fixer: the exclusion uses `\b` instead of the letter boundary | KILLED, BLIND on every row (120 failures) | KILLED by C2rc18 |
| `CCTRL` | control: none (must survive) | SURVIVED | SURVIVED |

### A test defect found by the `_noST` runs

The first `_noST` runs of CF1 and CF2 SURVIVED. Cause: rows C2rc21 and C2rc22 had been written with literal non-ASCII
characters, and the fixture helper `pyx` encodes its argument as ASCII, so it raised `UnicodeEncodeError`, wrote
nothing, and the two fixtures were EMPTY files that the census reported as `unclassified` for another reason. Both rows
passed on the head and on every mutant for the wrong reason (the error is in `runs/census_GREEN_try1.txt`). Fixed:
the rows use `\uXXXX` escapes, `pyx` now writes a marker on failure and the suite stops with a setup error after the
rows, and the remaining measured Unicode probes became rows (C2rc24 no-break space, C2rc25 Unicode-digit `total`,
C2rc26 Unicode-digit link count; C2rc27 golden-FALSE: an ASCII status is data). Every census mutant was then re-run on
the final test file (the table above).

### CMR4 (reviewer): survives, judged harmless

`CMR4_rc_ws_tolerant` lets an `.rc` file carry ASCII whitespace around its one-to-three-digit status
(`\s*(\d{1,3})\s*`, still under `re.ASCII`). The MENTION check runs before it, so no text naming git reaches it, and
ASCII whitespace plus digits cannot carry a command. A row that pins the stricter shape could kill it, but it would
guard no safety property; judged a nit, not killed.
