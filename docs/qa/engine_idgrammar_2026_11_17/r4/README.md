# CON-456 round 4: evidence

| Field | Value |
|---|---|
| Item | CON-456 (workable-items engine id grammar and whole-item round trip) |
| Round | 4 (fixer), after the round-3 independent review NO-GO |
| Base | `c27b123db0543e23fa4b7b3d0c3918657f0338e7` (round-3 head) |
| Evidence class | gate-logic and host-only (real engine binary, real SQLite files, real tracker COPIES); PROVISIONAL (§11.4.290) until an independent review returns GO |
| Date | 2026-11-17 |

Every number below was measured in this round on the fixer's scratch clone. No
engine run touched a live tracker: every tracker run used a copy in scratch.

## 1. Findings of the round-3 review and what this round did

| Finding | What changed | Proof |
|---|---|---|
| 1 (important): `update --description` dropped the engine-written detail lines; on a blocked item the next `md-to-db` deleted the block record | New `detailcarry.go`. Every body writer names the detail kinds it replaces (`block`: Operator-Block-Details and Unblock-Choices; `close`: Evidence, Operator-Block-Details and Unblock-Choices; `update`: none). `carryDetailBlocks` carries every other engine-written detail block of the old body, and `detailLossProblems` refuses a write that still loses one, or that changes the block-record source without replacing it. Fenced lines and lines that are part of the description are never carried. | reviewer RED tests adopted verbatim (`idgrammar_r4_rev456r3_red_test.go`): FAIL on c27b, PASS now (`red/red_rev456r3_on_c27b.txt`, `gotest/`); `idgrammar_r4_cli_test.go`; class sweep (section 5) |
| Class closure (same class, found by the sweep) | `close` of a formerly blocked item left its `operator_block_details` row, which the next `md-to-db` deleted (pre-existing on main and r3). `close` now removes the row in the same transaction when the closed body has no block record. | `TestCON456R4_CloseOfBlockedItemRemovesBlockRow`: FAIL before the fix (`red/red_close_block_row.txt`), PASS after; sweep RT_SIDE 6 to 0 |
| 2: RR6 survived every gate (the gates read the dry-run preview string) | `cm_state_fields_anchor_wired` and `cm_repro_first_anchor_wired` check the operative `set -- --reproduction-state …` line and the `"$@"` forwarding; each mutation test has an RR6 mutant (the line deleted). New behavioural test `tests/reporting/test_report_item_bug_states.sh` runs `report_item.sh` through its fallback path and reads the minted states. | gate mutation tests (section 8); `report_item_bug_states.txt` (3 passed, 0 failed) |
| 3: RR2 and RR3b survived | `TestCON456R4_ObsoleteDetailsEvidenceLineBreakRefused` (an `--evidence` line break) and `TestCON456R4_UnblockChoicesOnlyEditRederived` (a choices-only edit) | both KILLED (section 4) |
| 4: RR5 had no separating test | `TestCON456R4_GateItemWriteInputCheckPinned` pins the gate input check directly. RR5 itself stays SURVIVED: recorded equivalent, see section 4. | section 4 |
| 5: adoption edges | Legacy-state adoption only for Type Bug, and fenced lines are never adopted | `TestCON456R4_LegacyAdoptionBugOnlyAndNotFenced` (M10, M11 KILLED) |
| 7: hygiene | `gofmt` on `db.go`; CHANGELOG entry; the real-tracker script runs from the repository root (validate resolves evidence paths against the working directory) | diff |

Not done in this round (follow-ups, section 9): the stored description after
adoption (5), reconciling a hand-edited block row (6), validate's path
resolution against the working directory (7).

## 2. Tests

`go test -count=1 ./...` in `scripts/workable-items`, final tree, run twice,
go1.26.4: rc 0 both times; 1000 pass, 0 fail, 6 skip (467 top-level pass, 6
skip). The two sorted verdict lists are identical, sha256
`65f4a6d4e2736f7b49b3d6e09805645373fd9d5382a412a5813129bd417b85c8`
(`gotest/gotest_final_run1_verdicts.txt`, `gotest/gotest_final_run2_verdicts.txt`).

RED on the round-3 head: the new round-4 tests run on c27b give 5 FAIL
(UpdateDescriptionKeepsEveryDetailKind, UpdateDescriptionKeepsObsoleteDetails,
BlockKeepsOtherDetailLines, CloseKeepsReopenedDetailsAndReplacesEvidence,
LegacyAdoptionBugOnlyAndNotFenced) and 3 PASS by design (they kill mutants of
new code) (`red/r4tests_on_r3.txt`). The reviewer RED tests FAIL on c27b
(`red/red_rev456r3_on_c27b.txt`).

## 3. report_item.sh fallback states

`tests/reporting/test_report_item_bug_states.sh` mints a Bug through the
fallback path of `report_item.sh` (an intake-match shim forces it) on a scratch
tracker and reads `reproduction_state` / `investigation_state` from the
database: `UNREPRODUCED` / `not-started`; a Task stays `UNSET`. Its built-in
control applies RR6 (the operative flag line deleted) to a copy of the script
and requires the Bug to be minted `UNSET`; when the control does not separate,
the test exits 2 (BLIND), never PASS. Result: 3 passed, 0 failed
(`report_item_bug_states.txt`).

## 4. Mutants

Runner: a scratch script outside the repository (sha256 in
`mutants/mutrun_sha256.txt`, pass 2 and 3 runner in
`mutants/mutrun_pass2_sha256.txt`). A mutant is KILLED when a test that passes
in CONTROL fails. The runs predate the close fix (section 1); the close fix is
proven by its own RED to GREEN test, whose revert is the pre-fix state.

Reviewer mutants (RR*, rebuilt on this tree):

| Mutant | Verdict | Killing test |
|---|---|---|
| RR1 line-break set reduced | KILLED | ObsoleteDetailsInputsJudged/superseding_U+2028, ObsoleteDetailsEvidenceLineBreakRefused |
| RR2 `--evidence` out of the line-break loop | KILLED | TestCON456R4_ObsoleteDetailsEvidenceLineBreakRefused |
| RR3b choices ignored by `operatorBlockSource` | KILLED | TestCON456R4_UnblockChoicesOnlyEditRederived |
| RR5 no gate inputs in obsolete-details | SURVIVED (recorded equivalent) | — |
| RR1+RR5 | KILLED | as RR1 |
| RR6 state flags removed from `report_item.sh` | KILLED | both gate mutation tests and `test_report_item_bug_states.sh` |

RR5 equivalence argument: in obsolete-details the four values are written
verbatim onto the one `**Obsolete-Details:**` line, which no renderer rewrites,
and the line-break pre-check refuses first every value that could split that
line. The gate input check is still live as defence in depth: RR0 (pre-check
removed) is KILLED with 6 failures, RR0+RR5 with 8 (the extra two include
`superseding_Severity_line`, which only the gate input check catches), and M13
(the gate input check removed everywhere) with 10.

Own mutants:

| Mutant | Verdict | Killing test |
|---|---|---|
| M1 update: carry removed | KILLED | UpdateDescriptionKeepsEveryDetailKind, KeepsObsoleteDetails, both reviewer RED tests |
| M2 update: loss gate removed | SURVIVED (recorded equivalent: the carry restores what the gate checks; the gate is defence in depth, covered by M3 and the DetailLossGate unit test) | — |
| M3 update: carry and gate removed | KILLED | 4 tests |
| M4 block: carry removed | KILLED | BlockKeepsOtherDetailLines |
| M5 close: carry removed | KILLED | CloseKeepsReopenedDetailsAndReplacesEvidence |
| M6 close: Evidence not replaced | KILLED | CloseKeepsReopenedDetailsAndReplacesEvidence |
| M7 fenced lines not skipped | KILLED | DetailLossGate |
| M8 description-owned lines not skipped | KILLED | DescriptionOwnedAndFencedLinesNotCarried, DetailLossGate |
| M9 OBD source comparison removed | KILLED (after a forged-marker case was added; first SURVIVED) | DetailLossGate |
| M10 adoption not Bug-only | KILLED | LegacyAdoptionBugOnlyAndNotFenced/task |
| M11 adoption fence mask removed | KILLED | LegacyAdoptionBugOnlyAndNotFenced/fenced_bug |
| M12 OBD marker not recognised | KILLED | 3 tests |
| M13 gateItemWrite input check removed | KILLED | 10 tests |
| RR0, RR0+RR5 | KILLED | see above |

Tables: `mutants/mut_table_r4_pass2.tsv`, `mutants/mut_table_r4_pass3.tsv`,
`mutants/mutrun_pass1.log`.

## 5. Class sweep

`class_enum.py` (579 cases: every writer × every detail kind × hostile text,
each on its own copy of the real tracker; new oracles `OP_DETAIL_LOSS` and
`RT_SIDE` read the detail lines and the side tables; controls OK):

| Engine | REFUSED | RT_OK | OP_DETAIL_LOSS | RT_SIDE |
|---|---|---|---|---|
| r3 (c27b) | 191 | 352 | 33 | 3 |
| r4 before the close fix | 194 | 379 | 0 | 6 |
| r4 final (`a792788d…`) | 194 | 385 | 0 | 0 |

Tables: `class/`.

## 6. Real tracker copy

`realtracker_check.sh` on a copy of the 491-item tracker (db sha256
`1ca8399e…f8d0`), engine `a792788d…` (the final binary): FAILS=0. validate and
diff OK, the export equals the committed Issues.md and Fixed.md, two md-to-db
cycles, side tables equal db0 to db1 and db0 to db2, exports byte-identical,
279 descriptions change on the first cycle only (CON-396). The same check on the
main binary (`e048a077…`) gives FAILS=2 (the known CON-263 block-row re-split),
which shows the side-table check can see a change (`realtracker/`). The
repository's own tracker database was never written.

## 7. Callers

Unchanged from round 3 except `report_item.sh`, which is now exercised by a
shipped test (section 3).

## 8. Gates

Full outputs in `gates/` (`gates.tsv`: name, exit code, time, last line), run on
the final working tree before the commit:

| Gate | Result |
|---|---|
| `run_full_suite.sh --verify-manifest` | MANIFEST-OK (census 966 with the new test) |
| `cm_full_suite_manifest_complete` | PASS before the commit (it reads HEAD: 965); after the commit `ec1d0bf5`: PASS, 966 census files (`gates/cm_full_suite_manifest_complete_postcommit.out`) |
| `cm_gate_ledger_ratchet` | PASS (baseline 394) |
| `cm_constitution_index_fresh` | PASS |
| `git_env_class_census.py` | PASS, members=664 hermetic=510 exempt=154 unscrubbed=0 |
| `cm_helix_deps_manifest_present` | BLIND (exit 2): own-org submodules are not checked out in the scratch clone; not a PASS (same as round 3) |
| `cm_state_fields_anchor_wired` | PASS 245/245; mutation test PASS (270 RED/BLIND + 8 GREEN) |
| `cm_repro_first_anchor_wired` | PASS 175/175; mutation test PASS (189 RED/BLIND + 5 GREEN) |
| `cm_reporting_directives` and its mutation test | PASS, PASS |
| `cm_feature_directive` and its mutation test | PASS, PASS |
| `tests/reporting/test_report_item_bug_states.sh` | 3 passed, 0 failed |
| US3 shipped engine (`test_shipped_workable_items_us3_red.sh`) | all hold |
| `tests/constitution_cmd/test_constitution_cmd.sh` | PASS=292 FAIL=0 |

## 9. Build

`bin/workable-items` and `bin/workable-items-linux`: sha256
`a792788df5f07ac951553d63107aa5ebf82fbbf77c89fe00bd9e4e1bdf0fd1a7`, built twice
(go1.26.4, `-trimpath -buildvcs=false -ldflags=-buildid=`, `GOEXPERIMENT=nodwarf5`),
equal outputs. `bin/.source.sha256` =
`e5f6315fb5c30bfc6204b5b1062c3241a0ab7f247616b161e02e1f452d4d72f1`.

## 10. Limits and follow-ups

- After legacy-state adoption the stored description keeps the record text
  until the next md-to-db (finding 5).
- A block row hand-edited in the database so that it no longer matches the
  body is kept (finding 6); a reconciliation path is owed.
- validate resolves evidence paths against the working directory (finding 7).
- `**Candidate-Duplicate-Of:**` is not in the carried set and is lost on
  `update --description`.
- `close` regenerates the body and drops rich authored content outside the
  description (the SPK-481 class).
- Legacy text with CRLF line endings is refused (fail-closed).
- M2 and RR5 are recorded equivalents (section 4), not killed.
- `sh -n` on `cm_repro_first_anchor_wired.sh` fails (pre-existing: the same
  syntax error at line 172 on c27b, line 177 now; the gate runs under bash).
- `gofmt -l` still lists `mutate.go` and other files for their doc-comment
  indentation (pre-existing on c27b).
