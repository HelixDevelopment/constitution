# Round 10 mutants

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15T17:19:38Z |
| Status | evidence (PROVISIONAL) |
| Evidence class | gate-logic only (stub llmctl, a flock gate, an advancing test clock, a test monotonic clock; §11.4.289(C)(2)). Nothing here is live evidence; no local model was started, no hosted endpoint was called, `llmctl enable` was never run. PROVISIONAL. |
| Round | 10 (structural, §11.4.276(E): a fresh fixer under the standing operator decision "review rounds until GO, fresh fixer and reviewer each round") |

| Mutant | Change | Verdict | Killed by | First failing row |
|---|---|---|---|---|
| CTRL | CONTROL: frozen base, no change | survived (control) | - | - |
| R9-01 | leases_save ACQ_REFRESH stamps heartbeat with the process-start clocks | killed | r9 | FAIL - P112 A refreshed its lease when it recorded the start; an observer at once keeps it (expected [0 1 1700 |
| R9-02 | reap_locked: the holder of a CLEARED mark also suspends lease TTLs | killed | r10 | FAIL - P117 the mark older than MARK_TTL is cleared and the expired lease of the holder it named is reaped in  |
| R9-03 | set_view: ownership by pid only (pid_start ignored) [re-anchored: finish_stop now uses set_view] | equivalent (reviewer verdict: a live pid is unique) | - | - |
| R9-04 | arm_stop_locked: no reap before the re-judgement | killed | r10 | FAIL - P118 decide-b's stop runs at its turn: the stop of decide-b never began |
| R9-05 | age_of: a record from another boot is judged on wall time [re-anchored] | killed | r9 | FAIL - P111 a mark from another boot is expired (expected [null] got [{ |
| R9-06 | MARK_TTL without the record waits | killed | r8 | FAIL - P93a a live starter's mark is kept at MARK_TTL of its own age (process age MARK_TTL + 100 s) (expected  |
| R9-07 | finish_stop_locked rc 0: deleted with another stopper's mark [re-anchored: finish_stop's rule_sole ignores the other mark] | killed | r10 (P123, second pass) | P123 the set is kept with the other process's starting mark (expected [10120 true] got [null false]) |
| R9-08 | mark_start_locked: a stopping mark elsewhere no longer refuses a start mark | killed | r7 | FAIL - P87 decide-b is not started while decide-c is stopping (expected [0 decide-a 0] got [0 decide-a 1]) |
| R9-09 | arm_stop_locked: the stopping mark mono is the process-start monotonic clock | killed | r9 | FAIL - P110 the producer's own stopping mark: pid, pid_start (its start time), mono, holder (expected [16 1060 |
| R9-10 | reap_locked: ANY live mark suspends EVERY lease TTL | killed | r10 | FAIL - P116 the expired lease of hO is reaped; hM, named by the live mark, is kept (expected [hM true] got [hO |
| R9-11 | finish_stop_locked kept set: health not set pending (stays routable) | killed | r10 | FAIL - P119 the kept set has health pending and no llmctl-local entry is derived for it (not routed until obse |
| R9-12 | lease_json: pid_start not recorded | killed | pl | FAIL - P24 the lease records the holder's process start time (expected [number] got [null]) |
| R9-13 | holder_alive: a heartbeat exactly TTL old is expired (-lt) | killed | r8 | FAIL - P98 a pid-less lease is alive at its TTL (900 s) (expected [1] got [0]) |
| M10-01 | rule_sole ignores other holders | killed | r10 | FAIL - P115a A's failed start keeps B's lease, writes no stopping mark and stops nothing under B (the unit sti |
| M10-02 | rule_sole ignores a foreign mark | killed | r10 | FAIL - P115e the other process's stopping mark is kept and A runs no stop of its own (A's own starting mark is |
| M10-03 | rule_sole: a cleared mark (claim gone) is never sole | killed | r10 | FAIL - P115f the set is SOLE (claim gone, no other lease): the failed start's cleanup stop runs and the set is |
| M10-04 | finish_start: placed without checking this acquire still holds a lease | killed | r10 | FAIL - P115c A's start returns rc 0 after its own lease was released: not placed for A (no profile printed, ex |
| M10-05 | adoption guard removed: a profile this acquire tried to start can be adopted | killed | r10 | FAIL - P115g A does not adopt decide-a as operator-started after its own start of it was refused (expected [5  |
| M10-06 | age_of: a monotonic time ahead of the reader gives a negative age (pre-round-10) | killed | r10 | FAIL - P120 the same mark at wall age 400 s: cleared (before round 10 it was never cleared) (expected [null] g |
| M10-07 | age_of: a future wall time gives a negative age | killed | r10 | FAIL - P120 a mark with no mono stamped 1000 s in the future: a negative age is expired, not fresh for ever (e |
| M10-08 | plan_locked: the gateway write before the reap (pre-round-10 order) | killed | r10 | FAIL - P121 the expired lease of the acquiring holder is reaped before the plan's gateway write (no [reaped de |
| M10-09 | not-sole start result: no health pending (kept set stays routable) | killed | r10 | FAIL - P115a the result is recorded (start_kept, claim gone) and the kept set is not routed until an observati |
| M10-10 | not-sole start result: every lease dropped (pre-round-10 leases:[]) | killed | r10 | FAIL - P115a A's failed start keeps B's lease, writes no stopping mark and stops nothing under B (the unit sti |
| M10-11 | not-sole start result: a foreign mark is cleared too | killed | r10 | FAIL - P115e the other process's stopping mark is kept and A runs no stop of its own (A's own starting mark is |
| M10-12 | not-sole rc 0 reported placed (handed -> placed) | killed | r10 | FAIL - P115c A's start returns rc 0 after its own lease was released: not placed for A (no profile printed, ex |
| M10-13 | not-sole failure reported failed: the caller runs a cleanup stop under the other holders | killed | r10 | FAIL - P115a A's failed start keeps B's lease, writes no stopping mark and stops nothing under B (the unit sti |
| M10-14 | not-sole start result: constitution_started not forced true | killed | r10 | FAIL - P115a A's failed start keeps B's lease, writes no stopping mark and stops nothing under B (the unit sti |

Full per-suite verdicts: `mutants_verdicts.tsv`; mutant sources hash: `mutants_index.tsv`; generator `tools/mkmut10.py`, runner `tools/runmut10.sh`.
