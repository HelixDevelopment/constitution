# Round 12 mutants, jev-place.sh

| Field | Value |
|---|---|
| Builder | `tools/mkmut12.py.txt`: the reviewer's `mkmut_rev.py` (X mutants, unchanged) plus my own Y mutants. Each mutant is a full copy of the tree with one exact substitution, and every substitution matched exactly once |
| Runner | `tools/runmut12.sh.txt` / `tools/runsuite.sh.txt` / `tools/hrun.sh.txt`, with `S4_PLACE_UNDER_TEST` pointing at the mutant; hermetic bwrap; at most 2 suites at a time |
| Results | `runs/results.tsv` (one line per run: name, suite, rc, fails, passes, seconds, normalised verdict hash) |
| Evidence class | gate-logic (§11.4.289(C)(2)); PROVISIONAL |

"Killed" means that a suite's rc is 1 and that the failing rows are named. Each kill below is RED on the mutant and GREEN
on the head, because the head runs the same suite at 0 failures (`runs/results.tsv`, lines `final_*`).

## Reviewer mutants (review_jev_r11.md section 5)

| Mutant | Change | Round-12 result | Killing rows |
|---|---|---|---|
| XCTRL | control | survives r12 58/0 | (control: the runner applies no change) |
| X01 | pid-only match in the no-armed-mark after-check | survives; **equivalent** (proof below) | — |
| X02 | finish_start does not record ARMED_MARK | survives; **equivalent with a stated limit** (proof below) | — |
| X03 | arm_stop does not record ARMED_MARK | survives; **equivalent with a stated limit** (proof below) | — |
| X04 | owed-after-start clears a foreign stopping mark | **KILLED** r12 (2 rows) | R12-8 |
| X05 | stop_owed only for rc 0 | **KILLED** r12 | R12-6 |
| X06 | record-step lock timeout returns 0, not 4 | **KILLED** r12 (2 rows) | R12-1 (release exits 0, not 6), R12-2 (the acquire no longer says "no further candidate is started") |
| X07 | plan step D skips only STOP_TRIED | survives; **equivalent** (the reviewer's proof, repeated below) | — |
| X08 | arm no longer refuses another process's stopping mark | **KILLED** r12 (4 rows) | R12-8, R12-9 |
| X09 | stop_owed with n<=1 | survives r12; killed at r10 (P115a, the reviewer's run) | P115a |
| X10 | owed branch does not record stop_failed | **KILLED** r12 | R12-7 |
| X11 | owed-retry bound removed | survives; **not equivalent with three processes, not killed** (below) | — |
| X12 | rc 1 start not counted as after the arm | **KILLED** r12 | R12-6 (and R11-2 at r11, the reviewer's run) |

## Own mutants (13)

| Mutant | Change | Result | Killing rows |
|---|---|---|---|
| Y01 | release: a stop result that was not recorded (4) counts as success | KILLED r12 | R12-1, R12-3 |
| Y02 | acquire: the cleanup stop's result is ignored | KILLED r12 | R12-2 |
| Y03 | stop_turn: a stopping mark that cannot be written reads as stopped | KILLED r12 | R12-3 |
| Y04 | do_stop: no retry of the record step | KILLED r12 | R12-4 |
| Y05 | heartbeat: a lock timeout exits 0 | KILLED r12 | R12-5 |
| Y06 | release: a lock timeout at the observation exits 0 | KILLED r12 | R12-5 |
| Y07 | acquire: a lock timeout at the observation returns 5 | KILLED r12 | R12-5 |
| Y08 | with_lock: a lock timeout returns 0 | KILLED r12 (11 rows) | R12-1 to R12-5 |
| Y09 | finish_stop owed-after-start: constitution_started not set | survives r12, r11, r10, pl, r6; **equivalent** (below) | — |
| Y10 | release: a failed stop (1) counts as success | KILLED pl (P21, P22); new row R12-12 | P21, P22, R12-12 |
| Y12 | finish_stop owed-after-start: stop_owed not recorded | survives r12, r11, r10, pl, r6; **not equivalent, not killed** (below) | — |
| Y13 | acquire: no `break` after a failed cleanup stop | KILLED r11 (R11-9), pl (P27, P40), r6 (P65); new row R12-13 | R11-9, P27, P40, P65, R12-13 |
| Y14 | acquire: a lock timeout is recorded as undetermined, not lease_lock_timeout | KILLED r12 | R12-5 |

## Equivalence arguments and honest survivors

**X01, equivalent.** X01 changes only the `elif` branch of the after-check, which runs when `ARMED_MARK[$p]` is empty
(line 800). Every call of `do_stop` has that mark set first:

- line 894: `stop_turn` calls `do_stop` only after `with_lock arm_stop_locked` returned 0, and arm sets
  `ARMED_MARK[$p]` at line 879;
- lines 1312 (`released`) and 1332 (`failed`): the case arms are reached only with `START_RES` released or failed, and
  line 1176 sets `ARMED_MARK[$p]` for exactly those two results;
- the owed retry (lines 918 to 923) runs inside `do_stop`, so the mark is unchanged.

`with_lock` runs its function in the current shell (line 637, no subshell), so the assignments are visible to the
caller. The `elif` branch is therefore unreachable on the head, and X01 cannot change behaviour. Limit: this holds while
`me_mark` prints a mark. If jq failed there, `am` would become `null`. That is not a reachable state in these suites.

**X02 and X03, equivalent with a stated limit.** These mutants drop the assignment at line 1176 (X02) or at line 879
(X03), so the after-check falls back to the pid and pid-start-time comparison. Both branches answer "yes" for a
`seen_stopping` mark written by this process. They differ only for an older mark of this same process on the same
profile that is still unanswered. An answered mark moves to `answered_stop` (line 811), so within one run the only
marks of this process for the profile are the one just armed and marks already answered. Limit: a process that wrote a
mark, crashed, and was reused by pid and start time cannot occur, because pid plus start time identifies a process.
The suites do not construct the case.

**X07, equivalent** (the reviewer's proof). At line 1227, `DISPOSED+=` runs only after `STOP_TRIED+=`. So DISPOSED is
a subset of STOP_TRIED, and skipping STOP_TRIED already skips every disposed profile.

**X11, NOT equivalent with three processes, not killed.** Without the bound, the owed retry can run more than once in
one process. The reviewer argued equivalence because `answered_stop` blocks a second "yes". That holds for two
processes. With three, a third process can record a new start (a new `seen_stopping`) between two retries, which makes
the next after-check answer "yes" again. That gives another stop, each one bounded, armed and recorded. No unit is left
unleased; the cost is one extra stop per such interleaving. No row constructs it. Recorded as a follow-up.

**Y09, equivalent.** The owed-after-start branch runs only when `start_kept.rc` is not 75 (line 802). The only writer
of `start_kept` is `finish_start_locked` (line 1171). That same jq write sets `constitution_started = true` for every
`src` other than 75 (lines 1168 and 1169). No other write sets `constitution_started` false: the census of the file
finds only line 1168. A whole-set replace drops `start_kept`. So when the branch runs, `constitution_started` is
already true, and the dropped assignment changes nothing.

**Y12, NOT equivalent, not killed.** In every interleaving the suites build, `finish_start_locked` has already written
`stop_owed` (it does that when no other lease holds the set), so the dropped write in `finish_stop_locked` is masked.
The write matters only when the start was recorded while another lease held the set, and that lease was released
before the stopper recorded. After that, the owed retry would also have to fail for the missing record to leave a
unit with no owed stop. That is a three-process case with a failing retry, and no row builds it. Recorded as a
follow-up, together with finding R12-F1.

## Census mutants (git_env_class_census.py, R11-C)

| Mutant | Result |
|---|---|
| CM1 (reviewer): non-executable `.rc` with git writes | RED on the round-11 census, GREEN at the head (row C2rc1) |
| CM2 (reviewer): the same file, executable | killed (row C2rc2) |
| CM3 (reviewer): non-executable `.ls` with git writes | RED on the round-11 census, GREEN at the head (row C2rc3) |
| CM4 to CM8 (own: the docs/qa scope check, the length bound, the exec check, the per-line ls check, the git guard) | each KILLED by the census's own shape control needles: the census reports BLIND (exit 2, for example "control needle: shape rule on tests/x.rc ... got True"), so `tests/test_git_env_class.sh --only-census` gives passed=2 failed=108 on each mutant and 110/0 on the control (`runs/census_mut12.tsv`, `runs/census_CM*.txt`). The rows C2rc1 to C2rc15 test the same rules again, one input at a time |

RED and GREEN of the census rows: `runs/census_rows_RED_on_a1eeb0d7_census.txt` (99/8) and
`runs/census_rows_GREEN_head.txt`.
