# Round 9 mutants of `scripts/jev/jev-place.sh`

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Status | evidence (gate-logic only, §11.4.289(C)(2); PROVISIONAL) |
| Producer | snapshot s3, byte-equal in s4 (`frozen_s3.sha256`, `frozen_s4.sha256`) |
| Generator | `tools/mkmut9.py.txt` (sha256 fce9a4d4ac7514fc…); runner `tools/runmut9.sh.txt` (95a116c6c0045567…); table `tools/mkmutmd.py.txt` |

Every mutant is a FULL copy of `scripts/jev` with one change (every substitution asserted to match exactly once). Each
runs the suites r9, r8, r7, r6, placement in that order against a frozen snapshot and stops at the first suite that
kills it. Raw records: `mutants_index.tsv` (key, change, sha256 of the mutated file), `mutants_verdicts.tsv`. The table
below is generated from those two files by `mkmutmd.py` (the last run of each key).

Snapshots: every mutant ran on s3 except O9-13, CTRL and the two composites, which ran on s4 (P112 strengthened; the
producer is unchanged, so the mutants are the same files).

| Mutant | Change | Verdict | Suites run | Killing row (first FAIL line, truncated) |
|---|---|---|---|---|
| CTRL | CONTROL: the T_START-frozen base, no change (must survive every suite) | survived | r9 r8 r7 r6 pl | - |
| RV01 | lease_json: heartbeat_at / heartbeat_mono stamped with the process-start clocks | survived | r9 r8 r7 r6 pl | - |
| RV02 | obs_locked: health.at stamped with the process-start clock | killed | r9 r8 | FAIL - P93a health.at and the record's evaluated_at are the time of the post-start observation (expected [ok 1700000538 1700000538] got [ok 1700000000 |
| RV03 | obs_locked: gone.at stamped with the process-start clock | killed | r9 | FAIL - P105 gone.at is the time of the observation that found the unit gone (after its 100 s read) (expected [1700000100 0] got [1700000000 0]) |
| RV04 | write_placement: evaluated_at stamped with the process-start clock | killed | r9 r8 | FAIL - P93a health.at and the record's evaluated_at are the time of the post-start observation (expected [ok 1700000538 1700000538] got [ok 1700000538 |
| RV05 | finish_stop_locked (dispose): stop_owed.at / stop_failed.at stamped with the process-start clock | killed | r9 | FAIL - P106 the failed disposal stop (read +100 s, stop +25 s) records stop_owed.at and stop_failed.at at T0+125; A's mark is cleared (expected [5 1 1 |
| RV06 | reap_locked: mark_cleared / health stamped with the process-start clocks | killed | r9 | FAIL - P103 after a 100 s capacity read the mark is 400 s old at the judging lock: cleared; mark_cleared and health carry that time (expected [null 17 |
| RV07 | hb_locked: heartbeat refreshed with the process-start clocks | killed | r9 | FAIL - P108 the heartbeat stamps heartbeat_at and heartbeat_mono after its 100 s read (expected [0 1700000100 test:1700000100] got [0 1700000000 test: |
| RV08 | reap_locked: a mark's age is judged with the process-start clocks | killed | r9 | FAIL - P103 after a 100 s capacity read the mark is 400 s old at the judging lock: cleared; mark_cleared and health carry that time (expected [null 17 |
| RV09 | holder_alive: a lease heartbeat's age is judged with the process-start clocks | killed | r9 | FAIL - P104 after a 100 s capacity read it is 950 s old at the judging lock: reaped (expected [0] got [1]) |
| RV10 | finish_start_locked (released): started_at stamped with the process-start clock | killed | r9 | FAIL - P109 started_at and stop_failed.at are the time the result was recorded (read +100, start +50); the failed release stop keeps A's mark (expecte |
| RV11 | finish_start_locked (failed): started_at / start_failed.at stamped with the process-start clock | killed | r9 r8 | FAIL - P93b start_failed.at and stop_failed.at carry the time each was recorded (expected [5 1700000150 1700000175] got [5 1700000000 1700000175]) |
| RV12 | me_mark: pid_start not recorded | killed | r9 | FAIL - P110 the producer's own stopping mark: pid, pid_start (its start time), mono, holder (expected [16 9099573 test:1700000044 sA] got [16 null tes |
| O9-01 | finish_stop_locked rc 0: the set is deleted even when it holds a lease (R8-2 removed) | killed | r9 | FAIL - P102a the set is KEPT when its stop returns with a lease in it (the anomaly recorded), then the lease is released as endpoint_gone; A's mark is |
| O9-02 | arm_stop_locked stamps the mark with the PLAN's clock (the round-8 defect: a mark written for a later call) | killed | r9 | FAIL - P99 decide-b's mark carries the time of ITS turn (after the first stop), not the plan's (expected [1700000044] got [1700000000]) |
| O9-03 | arm_stop_locked does not judge the set again at its turn | killed | r9 | FAIL - P100 A does not stop decide-b again: one stop of each set (expected [5 1 1] got [5 1 2]) |
| O9-04 | finish_stop_locked treats every mark as its own | killed | r9 | FAIL - P102b the set is kept and the other stopper's mark is not cleared by A (expected [4205] got [null]) |
| O9-05 | age_of ignores the monotonic clock (wall time only) | killed | r9 | FAIL - P111 the wall clock stepped +10000 s, monotonic +10 s: the live mark is kept (expected [true] got [false]) |
| O9-06 | reap_locked: no lease-TTL suspension while a live mark names the holder | killed | r9 | FAIL - P112 an observer keeps the lease while A's live starting mark names its holder (expected [1] got [0]) |
| O9-07 | plan_locked: the join is taken in a plan that also stops a set | killed | r9 | FAIL - P113 A runs the owed stop, reads a fresh answer and joins decide-a (expected [0 decide-a 1 2] got [0 decide-a 1 1]) |
| O9-08 | leases_save: no heartbeat refresh of the acquire's holder | killed | r9 | FAIL - P112 A refreshed its lease when it recorded the start; an observer at once keeps it (expected [0 1 1700000100] got [0 0 null]) |
| O9-09 | me_mark: holder not recorded | killed | r9 | FAIL - P110 the producer's own stopping mark: pid, pid_start (its start time), mono, holder (expected [16 9175156 test:1700000044 sA] got [16 9175156  |
| O9-10 | me_mark: mono not recorded | killed | r9 | FAIL - P110 the producer's own stopping mark: pid, pid_start (its start time), mono, holder (expected [16 9179120 test:1700000044 sA] got [16 9179120  |
| O9-11 | age_of: a record from another boot is fresh (age 0) | killed | r9 | FAIL - P111 a mark from another boot is expired (expected [null] got [{ |
| O9-12 | clock_refresh: an unreadable monotonic clock is not a config error | killed | r9 | FAIL - P111 an empty JEV_MONO_FILE: exit 2 (expected [2] got [0]) |
| O9-13 | pid_dead: a recorded pid is never dead (a dead holder is kept by a live mark naming it) | killed | r9 | FAIL - P112 a lease whose pid is dead is reaped although a live mark names its holder (expected [0 true] got [1 true]) |
| O9-14 | release_locked marks every stop candidate at release time (the round-8 rule) | killed | r9 | FAIL - P101 the release of sA stops decide-a first: the stop of decide-a never began |
| O9-15 | hb_locked: heartbeat_mono not refreshed | killed | r9 | FAIL - P108 the heartbeat stamps heartbeat_at and heartbeat_mono after its 100 s read (expected [0 1700000100 test:1700000100] got [0 1700000100 null] |
| O9-16 | lease_json: heartbeat_mono not recorded | survived | r9 r8 r7 r6 pl | - |
| O9-17 | arm_stop_locked (dispose): the recorded-health check is removed | killed | r9 | FAIL - P114 decide-b is not stopped: at its turn it is recorded ok (expected [1 0 decide-b ] got [1 1 ]) |
| O9-18 | arm_stop_locked: the "holds a lease now" check is removed | killed | r9 | FAIL - P101 the release stops decide-a only (expected [0 1 0] got [0 1 1]) |
| O9-19 | finish_stop_locked rc 0 with a lease or a foreign mark: the mark is cleared even when it is another stopper's | killed | r9 | FAIL - P102b the set is kept and the other stopper's mark is not cleared by A (expected [4196] got [null]) |
| C-RV01+O9-08 | RV01 with the ACQ_REFRESH of leases_save removed (proves RV01 is masked only by that refresh) | killed | r9 | FAIL - P112 A refreshed its lease when it recorded the start; an observer at once keeps it (expected [0 1 1700000100] got [0 0 null]) |
| C-O9-16+O9-08 | O9-16 with the ACQ_REFRESH of leases_save removed (proves O9-16 is masked only by that refresh) | killed | r9 | FAIL - P111 with no seam the mark and the lease carry mono = <boot id>:<uptime seconds> (expected [0 yes yes] got [0 yes no]) |

## Totals

34 mutants: CTRL survives every suite (required: proves the harness passes an unchanged producer); 31 killed; RV01 and
O9-16 survive and are EQUIVALENT by construction, shown below.

## The two equivalent mutants

RV01 stamps a new lease's `heartbeat_at` / `heartbeat_mono` with the process-start clocks; O9-16 stamps no
`heartbeat_mono`. Both change only what `lease_json` returns. Read in the s4 source:

- `lease_json` is called at three places: `plan_locked` (twice) and `mark_start_locked`; both run only from
  `cmd_acquire`, and `cmd_acquire` is called only by the `acquire` command, which first sets `HOLDER="$holder";
  ACQ_REFRESH=1` for the same holder that `lease_json` is given.
- Every one of those writes goes through `leases_save`, which with `ACQ_REFRESH=1` rewrites `heartbeat_at = NOW` and
  `heartbeat_mono = MONO_TOK` (the clock of the current locked section) for every lease of `HOLDER` in the SAME write.

So the values the two mutants change never reach the registry. Removing that rewrite (O9-08) exposes them: the
composites C-RV01+O9-08 and C-O9-16+O9-08 are killed. Honest limit: C-RV01+O9-08 is killed by P112, the same row that
kills O9-08 alone, so that composite shows only that the pair is not equivalent; the equivalence of RV01 rests on the
source reading above. C-O9-16+O9-08 is killed by a different row (P111, the lease carries no `mono`), which O9-08 alone
does not trip.

## Incident: O9-13 survived on s3 (a test defect, fixed)

O9-13 makes `pid_dead` never report a pid dead, so a dead holder named by a live mark would be kept. It survived every
suite on s3. Cause (debug run `runs/dbg_o913.txt`): row P112's dead-pid case crafted a set whose unit the stub reported
gone, so the status released the lease as `endpoint_gone` and the row's assertion (0 leases) held for the wrong reason;
the log shows the mutant KEPT the lease first. s4 reports the unit up and asserts the reap's own log line, no
`endpoint_gone`, and no "kept" line. O9-13 is killed on s4 by P112. The r9 suite on s4: 70 pass, 0 fail, ×3 identical.

## Incident: the first mutant run was invalid

The first run copied only `jev-place.sh`; the producer sources `lib_decide.sh` from its own directory, so every
mutant failed for that reason and read as killed. That run was deleted and redone with full copies and the CTRL control.
