# Jev S3/S4 round 10: fixes for the independent review of `911c5b9a` (NO-GO: R9-1 to R9-9)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15T17:19:38Z |
| Status | evidence (In progress; no GO claimed; PROVISIONAL) |
| Evidence class | gate-logic only (stub llmctl, a flock gate, an advancing test clock, a test monotonic clock; §11.4.289(C)(2)). Nothing here is live evidence; no local model was started, no hosted endpoint was called, `llmctl enable` was never run. PROVISIONAL. |
| Round | 10 (structural, §11.4.276(E): a fresh fixer under the standing operator decision "review rounds until GO, fresh fixer and reviewer each round") |

## Findings

| Finding | Severity | Disposition | Row(s) |
|---|---|---|---|
| R9-1 `finish_start_locked` writes a lease set from a start result without an ownership check | important (host safety) | FIXED: one rule, one reader (`set_view` + `rule_sole`), used by `finish_start_locked` and `finish_stop_locked`; a result deletes or replaces a set, or writes a mark on it, only when the claim is ours (pid AND pid_start) or gone and no other lease and no other mark exist; otherwise only this acquire's own lease is dropped and the set is kept, `pending`, for its holders. New results `handed` (rc 0 after our lease was released) and `failed_kept`. An acquire never re-adopts a set it tried to start. Census of every result-writing site: `census.md` | P115a to P115g, P123 |
| R9-2 surviving mutant R9-10 | important | KILLED | P116 |
| R9-3 surviving mutant R9-11 | important | KILLED | P119 |
| R9-4 surviving mutant R9-04 (reap before the re-judgement) | minor | KILLED | P118 |
| R9-5 surviving mutant R9-02 (a cleared mark's holder suspends TTLs) | minor | KILLED | P117 |
| R9-6 `age_of`: a monotonic time ahead of the reader, or a future wall `at`, gave a negative age (fresh for ever) | minor | FIXED: a monotonic time ahead falls through to wall time; a future wall `at` is expired | P120 |
| R9-7 `plan_locked` wrote the gateway before the reap, refreshing an expired holder | minor | FIXED: reap first | P121 |
| R9-8 CHANGELOG advised re-committing a pushed-ready commit (history rewrite) | minor | FIXED: advice removed in the round-3 and round-4 entries and the two QA READMEs; replaced by the mapping note (below) | - |
| R9-9 `Constitution.md` Last modified did not equal the commit time | minor | FIXED: set to the round-10 commit time (and, at landing, to the merge commit time) | - |
| canon sentence "a stop never deletes a set that holds a lease" | - | REWORDED in `Constitution.md` and `groups/host-and-resource-safety.md` (byte-equal; index regenerated, `check` reports no drift): it now names the result of a start or a stop and the round-9 and round-10 censuses' limits | - |

## RED then GREEN (`tests/jev/test_s4_round10.sh`, P115 to P123)

| Producer | Result | File |
|---|---|---|
| round 9 (`911c5b9a`, sha256 `ec9fd999…e913`) | rc 1, 18 fail, 32 pass (before P123 existed) | `runs/r10_red_on_r9.txt` |
| round 10 | rc 0, 50 / 0 three times, identical normalised verdict set `0ec5b191f8b3c6d2` | `runs/r10_green1..3.txt` |
| round 10 with P123 | rc 0, 52 / 0 (one run) | `runs/r10_green4.txt` |

Regression suites on the round-10 producer, all rc 0: round 9 70 / 0, round 8 47 / 0, round 7 157 / 0, round 6 183 / 0,
placement (`test_s4_placement.sh`) 266 / 0 (`runs/reg_*.txt`). Runs are hermetic (`tools/hrun.sh`, bwrap), one at a time
or two in parallel, under `systemd-run --user --scope -p TasksMax=2000` and `nice -n 10`.

## Mutants

`mutants.md`: 28 (CTRL, the reviewer's R9-01 to R9-13 re-anchored, M10-01 to M10-14). CTRL survives (expected). R9-03
is equivalent (the reviewer's own verdict: a live process's pid is unique, so pid-only ownership cannot be told apart
without a pid reuse the stub cannot make). Every other mutant is killed. The reviewer survivors R9-02, R9-04, R9-10 and
R9-11 are now permanent mutants killed by round-10 rows. R9-07 survived the first pass and is killed by P123 (one run,
`runs/mut_R9-07_r10b.txt`).

## Id mapping note (no history rewrite)

The vehicle's commits carry the trailers `Roadmap-Item: CON-PENDING-JEV-CONSTITUTION` (`dc654757`), `CON-299` (rounds 4
to 7) and `CON-PENDING-JEV` (rounds 8 to 10). On `main`, CON-299 is a different item. At landing, the Jev S3/S4 item is
minted through the workable-items engine and every one of these three trailers on this vehicle maps to that minted id
(recorded in the item's description and in the landing CHANGELOG entry). The trailers are not rewritten.

## Follow-ups (drafts minted at landing, not here)

O6-1 (intermittent `test_review_fixes_r2.sh` P2, root cause UNKNOWN), CLOCK-BOOTSTRAP, MONO-FALLBACK (a host without
`/proc` judges ages on wall time), DEPS-LLMCTL-REF (`helix-deps.yaml` names llmctl ref `3877467` while the gitlink is
`391d8177`).

## Honest boundary (§11.4.6)

All of this is gate-logic evidence on stubs. It does not show that a real llmctl start or stop behaves as the stub
does, and the census covers only the class it names. No GO is claimed: the round needs its independent review.
