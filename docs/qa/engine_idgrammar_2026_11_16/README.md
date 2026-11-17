# Evidence: workable-items id grammar (CON-456), 2026-11-16

| Field | Value |
|---|---|
| Item | CON-456 |
| Base | RED on origin main `ce3dfaea`; landed on origin main `3e5e7e7d` (no engine source change between the two) |
| Evidence class | gate-logic and unit (§11.4.289): host tests and scratch copies of the committed tracker database |
| Status | PROVISIONAL (§11.4.290); not independently reviewed (§11.4.142) |

## Files

- `repro.sh`: class sweep over id shapes. Usage: `VALCWD=<repo root> repro.sh <engine binary> <copy of docs/workable_items.db> <out dir>`. It runs `add`, `sync db-to-md`, `sync md-to-db` into a fresh DB, `diff` and `validate`, and writes one `table.tsv` row per shape.
- `red_table_base_ce3dfaea.tsv`: RED, the engine built from the base source. `add` accepted 32 of 32 command-line shapes; 21 were lost by the round trip or came back under another id; `validate` exited 0 on all of them.
- `green_table_fixed.tsv`: GREEN, the same command with the fixed engine. 13 shapes are accepted and each round-trips with `diff` 0. 20 are refused before any write (`add` exit 1, no row). Three runs produced the same table sha256.
- `mutants_result.txt`: 22 paired mutants. 20 are KILLED. M13 and M18 survive and are recorded as equivalent (see below). The runner `mutants.py` (sha256 `c066cab1c1c93c470849a4df46aafaebcb93edd552c4c6eaf8c8a748a73377e7`) is not committed: its name puts it in the full-suite census, which then needs an `excluded` row accepted by a roster operator (`--accept-excluded-change`). It stays at `/mnt/DATA1TB/claude-work/scratch/idg_work/mutants.py`, outside the repository. Each mutant is one exact string replacement in a copy of `scripts/workable-items`, followed by `go test -count=1 -run 'TestIDGrammar|TestIsChildID|TestSubtask|TestShape2|TestNoStatusMutation|TestAdd' ./cmd/workable-items/`.
- `gotest_r1_verdicts.txt` and `gotest_r2_verdicts.txt`: top-level verdict lines of two full `go test -count=1 -v ./...` runs, 423 PASS and 0 FAIL each, with identical sorted-verdict sha256.
- `green_repeat_hashes.txt`: sha256 of the GREEN table for the three runs.
- `real_tracker_check.txt`: `validate`, `diff` and an `md-to-db` round trip, run by the fixed engine on a copy of the real tracker at `3e5e7e7d` (450 items).
- `fixture_suites_base_vs_fixed.txt`: `test_select_sample_r5_regression.sh`, `test_shipped_workable_items_us3_red.sh` and `test_2nd_display_triage_red.sh`, run through the fixture consumer layout of `tests/lib/make_fixture_tracker.sh` on the base tree and on the fixed tree.
- `suites.txt`: the repository shell suites that exercise the engine, run twice.

## Equivalent mutants

M13 (validate reads Fixed bodies with the Issues parser) and M18 (`add` checks only the Issues tracker) survive. A probe of 200 000 generated ids found no id on which the Issues and Fixed parsers disagree. While the two parsers read ids the same way, these mutants cannot be told apart from the fixed code. The checks are kept, so that a future divergence is caught.

## Corrections after the independent review (round 2, 2026-11-17)

The round-1 review returned NO-GO. These statements above are wrong or incomplete; the files they describe are kept unchanged as the round-1 record, except `repro.sh`.

- M13 is not equivalent (review F4). The two parsers read ids the same way, but not documents: `parseFixed` reads a pipe-table row as a table item and `parseIssues` does not. A Fixed section item whose body holds a pipe row with its own id reads back as a table item, which the Issues parser cannot see. The 200 000-id probe rendered headings only, so it could not reach that input. Round 2 compares the representation; see `../engine_idgrammar_2026_11_17/`.
- The two `go test` runs had 423 PASS, 6 SKIP and 0 FAIL each (review F6). The verdict files list the PASS lines only. The six SKIPs are pre-existing: `TestRoundTrip_RealDocs`, `TestValidate_OK_RealDocs` and `TestStatusDesyncAndDuplicateHistoryRows_StayZero` look for the trackers five directories above `cmd/workable-items` (a vendored layout), `TestParseFixed_Real_FullFile_Count` needs `/tmp/atm_fixed_real.md`, and `TestGapA_RenderRepresentationKeyIsLoadBearing` and `TestGapB_PipeRowSynthesisIsParseable` are GREEN-only guards that skip by design (reasons as printed, `../engine_idgrammar_2026_11_17/gotest_r2_summary.txt`).
- The `subtask_child` row of both tables tested nothing (review F7): it called `subtask-add`, which is not a command-line verb, so its `add_rc` 1 is the unknown-command exit. The row is removed from `repro.sh`. The two `.tsv` files still hold it as recorded.
- "13 shapes are accepted and each round-trips with `diff` 0" held for the id shapes in the sweep, but not for every title: a legacy id with a `[XX-N]` bracket or a leading space in its title was accepted and then lost or blocked on `sync md-to-db` (review F1, F3), and a Fixed-side refusal could follow a committed Issues write (review F2).

## Limits

- The child id of a sub-task under a canonical parent (`ATM-025-001`) does not round-trip. `subtaskAddCmd` is not reachable from the command line. `validate` now reports such a row, and a test pins the defect. The child id grammar is left for an operator decision.
- Intake duplicate-chain following now also follows legacy codes, not only canonical ids.
- The binaries were built with go1.26.4, the toolchain that reproduces the previous tracked hash from the base source.
