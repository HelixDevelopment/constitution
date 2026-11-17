# Round-11 mutants

Evidence class: gate-logic / PROVISIONAL. Generator `tools/mkmut_r11.py` (the round-10 reviewer generator
`mkmut_r10rev.py` with its substitutions re-anchored on the round-11 file, plus the fixer mutants W01 to W09).
Each mutant is a full copy of `scripts/jev` with one exact-once substitution on the T_START-frozen base. Each runs
suite by suite (r11, r10, r9, r8, r7, r6, pl) against a frozen snapshot of the round-11 tree and stops at the first
suite that kills it (`tools/runmut11.sh`). The control RCTRL must survive every suite.

| Mutant | What it changes | sha256 (first 12) | Result | First failing row |
|---|---|---|---|---|
| RCTRL | control, no change | 165f84a7b63b | survived 8 suite(s) |  |
| V01 | finish_start placed: a FOREIGN starting mark is cleared too | 4f58a2d1c6a0 | killed at r11 | FAIL - R11-4 A is placed and the other process's starting mark is kept (only A's own mark is ever cleared) (expected [0 83778 sA] got [0 nul |
| V02 | set_view: own holder counted among the others | 77c6f4256073 | killed at r10 | FAIL - P115a the result is recorded (start_kept, claim gone) and the kept set is not routed until an observation newer than it (expected [go |
| V03 | obs_locked: endpoint_gone also on a set carrying start_failed | a8d056f1ba06 | survived 7 suite(s) |  |
| V04 | finish_start not-sole: start_kept not recorded | 466b0d4b0905 | killed at r11 | FAIL - R11-1 A keeps the set constitution-started, records the stopping mark it saw and an owed stop; A runs no stop of its own (expected [5 |
| V05 | arm_stop_locked: a starting mark no longer refuses the stop | b29553e3fdba | killed at r11 | FAIL - R11-5 the arm step refuses the set another process is starting (no [another process is starting it] in /mnt/DATA1TB/claude-work/scrat |
| V06 | derive_cache: a set with stop_owed is routed | 829a22d22892 | killed at r11 | FAIL - R11-6 a set carrying stop_owed is observed ok but never routed (expected [ok no] got [ok yes]) |
| V07 | release_locked: a set with a starting mark is a stop candidate | 06b79f6ba602 | killed at r11 | FAIL - R11-7 the set being started is not a stop candidate of the release (found [stop of decide-b (release) not run at its turn] in /mnt/DA |
| V08 | holder_alive: the recorded pid start time is ignored (pid reuse kept alive) | 12d79c23935f | killed at pl | FAIL - P24 a reused pid (start time differs) is reaped (expected [0] got [1]) |
| V09 | mark_start_locked: the release check (held set) is skipped | 17e1faa48a84 | killed at r7 | FAIL - P88 decide-b is never started for the released sA; sA holds no lease (expected [0 0] got [1 1]) |
| V10 | hosted_key_var: any non-empty key counts (placeholder not refused) | 144fa5d1603a | killed at r11 | FAIL - R11-8 a placeholder key (length 8) gives route none, no key variable (expected [none null] got [cloud TYPESAFE_API_KEY]) |
| V11 | finish_start noset rc!=0/75: start_failed not recorded | 7fc9e2c4414a | killed at r11 | FAIL - R11-9 the failed start found no set: it is recorded with start_failed and the failed cleanup stop with stop_failed; the unit runs (ex |
| V12 | finish_stop kept set: a foreign stopping mark is cleared too | d55139a429a4 | killed at r9 | FAIL - P102b the set is kept and the other stopper's mark is not cleared by A (expected [4161] got [null]) |
| V13 | reap_locked: a mark with a dead pid is kept (only age clears) | 7df73391317b | killed at r11 | FAIL - R11-3 the next acquire runs the owed stop (the dead stopper's mark is reaped first) (no [retried the cleanup stop of decide-a] in /mn |
| W01 | finish_stop: a start recorded after the arm is ignored (the R10-1 delete) | 439242f13a25 | killed at r11 | FAIL - R11-1 B sees A's start record and does not delete the set (no [a start of decide-a was recorded after this stop was armed] in /mnt/DA |
| W02 | finish_start not-sole, 0 leases: no stop_owed recorded | 89e3849c999b | killed at r11 | FAIL - R11-1 A keeps the set constitution-started, records the stopping mark it saw and an owed stop; A runs no stop of its own (expected [5 |
| W03 | plan (D): a profile this acquire stopped or disposed may be adopted | fdb836c745ee | killed at r11 | FAIL - R11-2 rc 0 order starA: end state running=[decide-a ] rest=[{"decide-a":{"constitution_started":true,"stopping":null,"starting":null, |
| W04 | finish_start rc 75 not-sole: constitution_started forced true (R10-3 reverted) | 467c25216847 | killed at r10 | FAIL - P115b A's refused start (75) keeps B's lease; the re-plan joins the running set B holds; the set is not constitution-started (rc 75 s |
| W05 | do_stop: no owed retry after a kept set | da25c80465f4 | killed at r11 | FAIL - R11-1 B retries the owed stop: the unit is stopped and the set is gone (never orphaned) (expected [2 1  {}] got [1 1 decide-a  {"deci |
| W06 | finish_stop: the start record is not answered (seen_stopping kept) | c9938841fa18 | killed at r11 | FAIL - R11-1 B retries the owed stop: the unit is stopped and the set is gone (never orphaned) (expected [2 1  {}] got [2 1  {"decide-a":{"c |
| W07 | finish_stop: rc 75 start records count as a start after the arm | 1f36706171b9 | killed at r11 | FAIL - R11-11 B's stop result never treats the refused start as a start (found [was recorded after this stop was armed] in /mnt/DATA1TB/clau |
| W08 | finish_start: the stopping mark seen is not recorded | 5a68672d3392 | killed at r11 | FAIL - R11-1 A keeps the set constitution-started, records the stopping mark it saw and an owed stop; A runs no stop of its own (expected [5 |
| W09 | finish_stop: started-after also applies with leases held (stopped_while_held skipped) | 0ef632903348 | killed at r11 | FAIL - R11-10 the set is kept for hX (stopped_while_held), the unit hX holds is not stopped again (expected [1 decide-a  hX 1] got [1 decide |

Summary: 21 killed, 1 survived (control excluded). The one survivor is V03, equivalent at this head (proof below). Verdicts: `mutants_verdicts_snap1.tsv` for every mutant except RCTRL, W07 and W09, which are taken from `mutants_verdicts_snap2.tsv` (head snapshot, final test file); the sha256 column is the head-snapshot mutant (`mutants_index.tsv`).

## W07: the refused start is never a start (killed by R11-11)

In R11-2 (rc 75) the refusing process A runs on to its next plan as soon as its record is released, and that plan's
observation forgets the set (not constitution-started, no lease: `obs_locked` keeps only sets with a lease or
constitution-started). The stopper B then records against no set, so the mutated condition in `finish_stop_locked`
is never evaluated there (debug trace: the set is `{}` after A's event). R11-11 holds A at its next lock call after the
record, so B's result meets the set that still carries A's rc 75 record with B's mark; under W07 B keeps the set
constitution-started and stops a second time (2 stops), and the head stops once.

## V03 is equivalent (proof by census of the writes)

V03 drops `start_failed == null` from the endpoint_gone condition in `obs_locked`
(`leases > 0 and start_failed == null and stop_owed == null`). The mutant changes behaviour only on a set with
BOTH `start_failed` and at least one lease. No reachable state has both:

1. `start_failed` is written at exactly two places, both in `finish_start_locked` (census `census_r11.txt`, function
   `finish_start_locked`; source lines 1135 and 1147 at head d3e9c47c):
   - the `noset` branch writes the whole set with `leases:[]`;
   - the SOLE branch keeps `leases` minus this acquire's own holder, and SOLE requires `others == 0`, where `others`
     (`set_view`) counts EVERY lease of another holder, live or expired. So the result is `[]`.
2. Every write that adds a lease excludes a set carrying `start_failed`:
   - the (B) join (line 994) only takes sets selected with `start_failed == null` (line 978);
   - (D) adoption (line 1051) and `mark_start_locked` (line 1102) write a NEW set (`.sets[$p] = {...}`), only where
     no set exists, and the new set carries no `start_failed`.
   No other write adds a lease: `hb_locked` and the line-507 heartbeat refresh only update leases that exist;
   `reap_locked`, `obs_locked` and `release_locked` only remove leases.
3. The two `start_failed` writes run under the lease lock, and so do the lease additions. So no interleaving
   produces a set with both.

So a set with `start_failed` has 0 leases, and the condition V03 removes is always true where the rest of the
condition holds. V03 is equivalent at this head. If a future change adds a lease-adding write that does not
exclude `start_failed`, this proof no longer holds; the census (`write_census.py`) lists every `add_lease` site so
that a reviewer can check it again.

