# CON-456 round 3: evidence

| Field | Value |
|---|---|
| Item | CON-456 (workable-items engine id grammar and whole-item round trip) |
| Round | 3 (fixer), after the round-2 independent review NO-GO (`review_con456_r2.md`) |
| Base | `e44b74d143c006ba090e706169e1cd9b55eedb8a` (round-2 head; `main` `ebd8818c` is an ancestor) |
| Evidence class | gate-logic and host-only (real engine binary, real SQLite files, real tracker COPIES); PROVISIONAL (§11.4.290) until an independent review returns GO |
| Date | 2026-11-17 |

Every number below was measured in this round on the fixer's scratch clone. No
engine run touched a live tracker: every tracker run used a copy in scratch.

## 1. Findings of the round-2 review and what this round did

| Finding | What changed | Proof |
|---|---|---|
| F-A: the engine's own Bug template did not round-trip | `report_item.sh` passes the state as flags (`--reproduction-state UNREPRODUCED --investigation-state not-started --states-updated-by --states-updated-at`) instead of writing record lines into the description; the engine adopts the two exact legacy template lines into the state columns (`adoptLegacyTemplateStates`, crud.go) | reviewer RED `TestRev456R2_RED_BugTemplateMintsAndRoundTrips` FAIL on e44b, PASS on r3; `TestCON456R3_ReportItemStateFlagsMintAndRoundTrip`, `TestCON456R3_LegacyTemplateAdoptionIsExact` (8 subcases); end-to-end run of `report_item.sh` on every path (section 3) |
| F-B: md-to-db re-split `operator_block_details` | db.go keeps the stored block row while its Markdown source is unchanged (`takeOBDSnapshot`, `obdSnapshot.keep`; parse.go `operatorBlockSource`) | `TestCON456R3_OperatorBlockDetailsSurviveCycle` FAIL on e44b, PASS on r3; real-tracker copy: main changes CON-263 (UNBLOCK 220 to 695 bytes), r3 changes 0 rows (section 6) |
| F-C: point to CON-396 | engine README and the round-2 QA README name CON-396 for the first-cycle effects | text |
| F-D: `obsolete-details` did not check its inputs | obsolete.go refuses line breaks (`\r \n U+0085 U+2028 U+2029`) in `--since`, `--reason`, `--superseding`, `--evidence`, and the whole-item gate sees those values | `TestCON456R3_ObsoleteDetailsInputsJudged` (5 subcases FAIL on e44b), reviewer RED `TestRev456R2_RED_ObsoleteSupersedingSurvivesOrIsRefused` |
| F-E: nextID overflow | `nextID` works in int64 (`idNumber`) and refuses to allocate past the maximum, before any write, with "allocate with an explicit --id instead" | `TestCON456R3_NextIDOverflowRefusedBeforeAllocation` (the 20-digit case FAIL on e44b); mutant M15R (section 4) |
| F-F: docs said a legacy table row could be reopened | engine README behaviour-change list states that no engine path reopens a legacy table row | text |
| F-G: regression tests for RV01, RV02, RV04, RV09, RV16; class-sweep reopen leg | reviewer kill tests copied (`idgrammar_r3_rev456r2_kill_test.go`), own tests for block who/unblock, reopen incident, update assigned-to, close evidence, add description status line; `class_enum.py` reopen leg passes the hostile text through `--incident` (a real file named with the text) | all five reviewer mutants KILLED (section 4); class sweep (section 5) |
| F-H: stale "two transactions" text | db.go comment and the engine README CON-339 section now say "inside its one transaction, before the delete" | text |

## 2. Tests

`go test -count=1 -json ./...` in `scripts/workable-items`, run twice: rc 0 both
times; 454 top-level tests pass, 6 skip, 0 fail (985 pass with subtests).
The two verdict lists are identical: sha256
`a93ae89304a64ed96489be81474166c179e15c86d3e11ed9b7b3578072c983ed`
(`gotest_r3_run1_verdicts.txt`, `gotest_r3_run2_verdicts.txt`).

RED on e44b (`red_on_e44b.txt`, new tests compiled against the round-2 code):
FAIL `TestCON456R3_LegacyTemplateAdoptionIsExact`,
`TestCON456R3_NextIDOverflowRefusedBeforeAllocation`,
`TestCON456R3_ObsoleteDetailsInputsJudged`,
`TestCON456R3_OperatorBlockDetailsSurviveCycle`,
`TestRev456R2_RED_BugTemplateMintsAndRoundTrips`,
`TestRev456R2_RED_ObsoleteSupersedingSurvivesOrIsRefused`. The other new tests
pass on e44b by design: they guard the mutants of section 4.

Reviewer test files were copied with an attribution header; original sha256:
kill `67af60b7…`, red `25e9e56b…` (full values in the review bundle).

## 3. report_item.sh end to end (copies of the 491-item tracker)

`report_item_e2e.sh` (in this directory); output `e2e/summary.txt`.
Engine sha256 `61bbab0e…a8755`, script sha256 `70b29d9a…ccda65`, source DB sha256
`1ca8399e…5f8d0`.

| Path | Result |
|---|---|
| Bug, intake-match unavailable (shim exits 1) | CON-527 minted UNREPRODUCED / not-started by `Operator`; the two record lines are in the body, 0 in the description; the INTAKE-MATCH UNAVAILABLE notice printed; validate 0; two md-to-db cycles byte-identical; validate 0 |
| Bug, matcher answers DISTINCT | minted with UNSET states and no records; body hash equal to main's (pre-existing gap, not changed here) |
| Task, issue `--autonomous` | OK, two cycles byte-identical |
| Dry run | DB unchanged; the two preview lines printed |
| round-2 script with the r3 engine | the legacy template lines are adopted into the state columns |
| main engine, same paths | same results as r3 on the paths main supports |

`report_item.sh` stays POSIX: `sh -n` and `bash -n` pass (the state flags ride in
the positional parameters, not a bash array).

Legacy Bug minted by main (`probe_legacy_bug_on_main.sh`, `probe_legacy_main/`):
r3 validate exits 1 (malformed record) and r3 md-to-db refuses the unchanged
export with the DB unchanged; e44b refuses the same way; main sets UNREPRODUCED
silently. `update` cannot repair it; deleting ` (§11.4.292)` from the one line
makes md-to-db and validate exit 0. The real tracker holds 0 such items; other
consumer trackers are UNCONFIRMED.

## 4. Mutants

Runner `r3_mutants.py` (a copy of the reviewer's runner, kept in scratch; sha256 in `mutant_runner_sha256.txt`:
`c5cf92c61eeece43f3af77157efcc9c32bb68624830158527b2c6861f29f40fa`). The
pristine control on the copied tree has 111 environmental failures, as in the
reviewer's run; KILLED means a test that passes on the control fails on the
mutant. Tables: `mut_table_run1.tsv`, `mut_table_run2.tsv`, `mut_table_run3.tsv`.

| Mutant | Verdict |
|---|---|
| RV01, RV02, RV04, RV09, RV16 (reviewer) | KILLED |
| FX01 to FX10 (own) | KILLED (FX02 and FX05 after the two tests added in run 2) |
| M15R (reviewer: add does not judge the allocated id) | SURVIVED, equivalent on r3 |
| M15R + FX05 (both layers removed) | KILLED by `TestCON456R3_NextIDOverflowRefusedBeforeAllocation` and `TestRev456R2_AllocatedIDAfterInt64MaxIsRefused` |

M15R argument: `nextID` now never yields a malformed id (it refuses before
allocation), so the post-allocation gate M15R removes cannot be reached by any
input; it stays as defence in depth. The double mutant shows the tests do catch
the overflow when both layers are gone.

## 5. Class sweep

`class_enum.py` (in this directory), 516 cases, controls OK: r3 REFUSED 182,
RT_OK 334, per-case verdicts identical to e44b. The hostile reopen and block
cases are refused by the whole-item gate. Tables `class_r3_table.tsv`,
`class_e44b_table.tsv`, `class_r3_summary.json`.

## 6. Real tracker copy

Source DB sha256 `1ca8399e…5f8d0`, 491 items. r3: validate 0, diff 0, export equal
to the committed Markdown, two md-to-db cycles, no lost keys, second export
byte-identical. Cycle 1 changes 279 descriptions, every `last_modified` and 17
`parent_atm_id` values (CON-249 to CON-265), on r3 and on main alike (the hashes
of the changed description and parent values are equal); cycle 2 changes
nothing. These are the scoped-out first-cycle effects, tracked as CON-396, and
they are unchanged against main. `operator_block_details`: r3 0 rows changed,
main 1 (CON-263). Files: `realtracker_r3_summary.txt`,
`realtracker_allcolumns_r3_vs_main.txt`,
`realtracker_db1_desc_parent_r3_vs_main.txt`.

## 7. Callers

`caller_scan.txt`: lines where an engine reference is followed by a mutating
verb (add, update, move, block, reopen, close, obsolete-details). Control needle
(`scripts/reporting/report_item.sh` add) found; negative control (`frobnicate`)
0 hits; 11 code hits, 35 doc hits. Live callers and the run against a copy:

| Caller | Run |
|---|---|
| `scripts/reporting/report_item.sh` (add, two places) | section 3; `cm_reporting_directives` PASS and its mutation test PASS; `cm_feature_directive` PASS and its mutation test PASS |
| `scripts/reporting/schedule_feature_research.sh`, `scripts/constitution_cmd.sh` (through report_item) | `tests/constitution_cmd/test_constitution_cmd.sh` PASS=292 FAIL=0 |
| `tests/lib/make_fixture_tracker.sh` (add, close) | fixture built and validated by the r3 engine; `tests/gates/test_fastcycle_real_db.sh`: see section 8 |
| `scripts/fastcycle/tests/test_shipped_workable_items_us3_red.sh` (close, report_item) | SUMMARY: all hold |

The remaining code hits are historical evidence scripts under `docs/qa/`, two
comments in `select_sample.py`, and `git add` in `tests/test_run_full_suite.sh`.

## 8. Gates

| Gate | Result |
|---|---|
| `cm_state_fields_anchor_wired` | PASS 244/244; mutation test PASS (268 RED/BLIND + 8 GREEN) |
| `cm_repro_first_anchor_wired` | PASS 174/174; mutation test PASS |
| `run_full_suite.sh --verify-manifest` | MANIFEST-OK |
| `cm_full_suite_manifest_complete` | PASS (census on the committed tree) |
| `cm_gate_ledger_ratchet` | PASS, unimplemented=394 baseline=394 |
| `cm_constitution_index_fresh` | PASS |
| `run_full_suite.sh --sync-guide` | rc 0 |
| `git_env_class_census.py` | PASS, members=664 hermetic=510 exempt=154 unscrubbed=0 |
| `cm_helix_deps_manifest_present` | BLIND (exit 2): own-org submodules not checked out in the scratch clone; the reviewer's e44b run gives the same BLIND; not a PASS |
| engine validate and diff on the tracker copy | 0 and 0 |

`tests/gates/test_fastcycle_real_db.sh` (the caller of `make_fixture_tracker.sh`)
hit the 1500 s timeout (rc 124) on r3 under host load. Its own lines up to the
timeout: the fixture DB is built by the r3 engine (17 items, 35 history rows,
validate OK), the reopen_rate suite and every "genuinely exercised" line pass,
mutation `empty` is killed; `select_sample suite rc=1`. To find out why, the
select_sample suite was re-run alone on a fixture built by each engine
(`fastcycle/`): r3 rc 1 in 698 s, e44b rc 1 in 772 s, the same 66 verdict lines
on both (`select_sample_r3_verdicts.txt`, `select_sample_e44b_verdicts.txt`, ids
and timings removed before the comparison). The only NOT ok line on both is S13: its two
controls ("reopened window keyed on created_at", "retroactive before bulk")
change no pair on the fixture, because the fixture's one Reopened row
(`make_fixture_tracker.sh`, ATM-954) carries a `created_at` on its `on_date`
day. This failure is pre-existing on e44b and is not caused by this round; it
is a follow-up for the fastcycle area. The whole `test_fastcycle_real_db.sh`
was not re-run to completion in this round (UNCONFIRMED beyond the parts
above).

## 9. Build

`bin/workable-items` and `bin/workable-items-linux`: sha256
`61bbab0ec80e3e9430f43b66cc18cda6f98c980be19a73fc4f918a5400c8a755`, built twice
with the round-2 method (go1.26.4, `-trimpath`, equal outputs).
`bin/.source.sha256` = `f82b6961501f3f627e6da6b653760d12acb86b48011d1014a1a249bb13182113`
(108 files, tests included).

## 10. Limits and follow-ups (not filed this round)

- The matcher path of `report_item.sh` mints a Bug without state records
  (pre-existing; unchanged here).
- No engine path reopens a legacy table row; a reopen path for table rows is
  owed.
- A Bug minted by an older engine with the old template blocks md-to-db until a
  one-line Markdown edit; an engine repair path is owed. Other consumer trackers:
  UNCONFIRMED.
- The diff title/severity blind spot named in the round-2 review is not
  addressed here.
- fastcycle S13 controls are inert on the fixture tracker (pre-existing on
  e44b, section 8).
- The CON-456 tracker item itself was not updated in this round.
