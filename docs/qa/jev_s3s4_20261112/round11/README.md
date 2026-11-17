# Jev S3/S4 round 11: fixes for the independent review of `aaa2b3b0` (NO-GO: R10-1 to R10-4, N-1 to N-3)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15T22:34:35Z |
| Status | evidence (In progress; no GO claimed; PROVISIONAL) |
| Evidence class | gate-logic only (stub llmctl with start and stop gates, a flock gate, a test wall clock, a test monotonic clock; §11.4.289(C)(2)). Nothing here is live evidence; no local model was started, no hosted endpoint was called, no credential was used. |
| Round | 11 (fresh fixer under the standing operator decision "review rounds until GO, fresh fixer and reviewer each round") |
| Fixer | model Opus 5.5 (claude-opus-5-5); reasoning effort UNKNOWN (not settable or readable on this dispatch path, §11.4.231(F.2)) |
| Head tested | `d3e9c47c` (scripts/jev code); the round-11 test file as committed in the docs commit that follows it |

## Findings

| Finding | Severity | Disposition | Row(s) |
|---|---|---|---|
| R10-1 a start result recorded while another process holds a `stopping` mark and no lease, then that stopper's SOLE delete, leaves a running unit with no set; the stopper then adopts it as operator-started | important (host safety) | FIXED for the class of result-writing sites (census `census_r11.txt`, made by `tests/jev/fixtures/write_census.py`): the start result records the mark it saw (`start_kept.seen_stopping`) and, with 0 other leases and rc not 75, an owed stop; the stop result compares it with the mark it armed (`ARMED_MARK`), keeps the set constitution-started with `stop_owed`, answers the record and retries the stop once; plan step (D) never adopts a profile this acquire stopped or disposed | R11-1 (the reviewer's probe, deterministic), R11-2 (model check, 10 orders x rc 0/1/75, with a control), R11-3, R11-10 |
| R10-2 the five items minted on a vehicle database; Issues docs not regenerated | important (tracker integrity) | FIXED: three merges of `main`; minted through the engine on `main`'s database as CON-412 to CON-416, `export` and `diff` in sync (381 items); mapping note | `landing/` |
| R10-3 a rc 75 refusal on the not-sole path forced `constitution_started=true` | minor (operator decision) | FIXED per the operator decision (relayed by the coordinator): a refused start never marks the unit constitution-started; the constitution never stops it | P115b (RED first on `aaa2b3b0`), R11-2 rc 75 check, R11-11 |
| R10-4 reviewer mutants V01, V05, V06, V10 survive (and V03, V07, V11 examined) | important | V01, V05, V06, V07, V10, V11 KILLED (R11-4 to R11-9); V03 EQUIVALENT by a census of the writes (proof in `mutants.md`) | R11-4 to R11-9 |
| N-1 the round-10 census line count | nit | FIXED (`round10/census.md`): 15 call sites, 1 definition, 3 comments; the reviewer counted 17 call sites; the head count is in `census_r11.txt` | - |
| N-2 round-4 CHANGELOG pointer "(below)" | nit | FIXED in `45c3769a` | - |
| N-3 the three loopback tests' failure cause | nit | FIXED: the review guard refuses `curl` (rc 126); with `curl` allowed they pass 31/0, 39/0 and 40/0 | `loopback_*.txt`, `guard_refuses_curl*` |

## RED then GREEN

| Run | Producer | Result | File |
|---|---|---|---|
| `test_s4_round11.sh` | `aaa2b3b0` (round-10 head) | RED: 17 fail, 46 pass (R11-1, R11-2, R11-3, R11-10 among them) | `runs/final_red_r11b_on_aaa2b3b0.txt` |
| `test_s4_round10.sh` (P115b, P115c) | `aaa2b3b0` | RED: 3 fail (P115b x2, P115c) | `runs/final_red_r10_on_aaa2b3b0.txt` |
| r11, r10, r9, r8, r7, r6, pl | head | GREEN: 59/0, 52/0, 70/0, 47/0, 157/0, 183/0, 266/0 | `runs/` |

The RED producer is `aaa2b3b0`'s `scripts/jev/jev-place.sh` placed in a copy of the head `scripts/jev` (the mutant
layout). Runs are hermetic (`tools/hrun.sh.txt`: bwrap, no network, real home hidden, refusal guards on PATH), at most
two at a time (`tools/runsuite.sh.txt`).

## Mutants

See `mutants.md` (made by `tools/mk_mutants_md.py.txt` from `mutants_index.tsv` and the verdict files).
`mutants_verdicts_snap1.tsv` is the full run against the first frozen snapshot (round-11 fix commit, test file before
R11-10 and R11-11); `mutants_verdicts_snap2.tsv` re-runs RCTRL, W07 and W09 against the head snapshot with the final test
file. W09 is killed by R11-10 and W07 by R11-11 (in R11-2 the refusing process forgets the set before the stopper records,
so the mutated branch was unreachable there; R11-11 holds A after its record).

## Other gates on the merged tree

git-env census PASS (members 639, unscrubbed 0); `tests/test_git_env_class.sh` 142/0 (1 skip); `--verify-manifest`
MANIFEST-OK; `cm_gate_ledger_ratchet.sh` PASS (394 = baseline); `cm_constitution_index_fresh.sh` and the §11.4.279 to
§11.4.286 and §11.4.291 propagation gates PASS.

## Honest limits

The fix is checked by the stub harness only. The model check covers the five events of one start and one stop of one
profile; the census covers the write sites it lists (`leases_save`, set delete, set replace, lease add). Interleavings
with three or more processes, and live llmctl behaviour, are not covered.
