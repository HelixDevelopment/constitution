# CON-456 round 5: evidence

| Field | Value |
|---|---|
| Item | CON-456 (workable-items engine id grammar and whole-item round trip) |
| Round | 5 (fixer, STRUCTURAL round per §11.4.276(E)(2)), after the round-4 independent review NO-GO |
| Base | `94c95d83` (round-4 head) |
| Head of the fix | `1e90804c` (engine source equal to `a81f3f13`; later commits add tests only) |
| Evidence class | gate-logic and host-only (real engine binary, real SQLite files, real tracker COPIES); PROVISIONAL (§11.4.290) until an independent review returns GO |
| Date | 2026-11-17 |

Every number below was measured in this round on the fixer's scratch clone. No
engine run touched a live tracker: every tracker run used a copy in scratch.
"Main control" means the same instrument run with the engine of origin main
`ebd8818c` (`bin/workable-items`, sha256 `e048a077…`), to show that the
instrument sees the loss it is meant to measure.

## 1. Findings of the round-4 review and what this round did

| Finding | What changed | Proof |
|---|---|---|
| 1 (important): `block`, `update --description` and `close` regenerated the whole body from the columns and dropped every authored line of an item read by `md-to-db` (its description column is derived) | Structural change, new `bodypatch.go`: one invariant for every body writer. A writer patches the stored body in place and may change only the lines it owns (heading, its own Status line, the state records, the description region, and the records of the metadata block it writes or ends). `ownedLinesProblems` removes the owned lines from the old and new body and refuses the write when the rest differs. `detailcarry.go` (the round-4 carry list) is deleted. | reviewer RED `TestRev456R4_RED_BlockKeepsAuthoredBody` FAIL on 94c9, PASS now; `TestCON456R5_EveryWriterKeepsAuthoredBodyOfMdReadItem`; proseloss sweep on the real tracker copy: 0 bytes lost (main control 314,118 bytes on 207 items), section 5 |
| 2 (important): the description-owned skip let two description edits drop the block record | A record counts as engine-owned only inside the metadata block; a line in the description region is the operator's text. `update --description` additionally refuses a write that would drop the block record of a blocked item (`blockRecordKept`). | reviewer RED `TestRev456R4_RED_DescriptionOwnedSkipKeepsBlockRecord` FAIL on 94c9, PASS now; `TestCON456R5_DescriptionQuoteThenDropKeepsEvidence`; `TestBodyPatch_UpdateRefusesDroppingBlockRecordFromDescription` |
| 3 (minor): leaving Operator-blocked through `update --status`, `reopen` or `move` left the `operator_block_details` row | Every status writer that moves an item off Operator-blocked ends the record in the body and deletes the row in the same transaction, with a history event. Writers swept: update, reopen, move, close, obsolete. | `TestCON456R5_UnblockingWritersRemoveBlockRow` FAIL on 94c9, PASS now; mdsweep `row_ok` failures 0 (main control 6) |
| 4 (minor): RM1, RM3, RM4, RM6 survived | Tests for the metadata-block boundary, indented record lines, tilde fences and the owned-line gate | all four KILLED, section 4 |
| 5 (nit): M2 not equivalent | The reviewer's input for M2 is now accepted (`TestCON456R5_DescriptionChoicesLineIsDescriptionText`), and a new test kills M2 | M23 KILLED, section 4 |
| 6 (nit): `block --location Fixed` minted Operator-blocked at Fixed | `block` refuses an item at Fixed | `TestCON456R5_BlockAtFixedRefused` FAIL on 94c9, PASS now |
| 7 (nit): `gofmt -l mutate.go`; `sh -n` on the anchor-wired gates | `mutate.go` and every changed Go file are `gofmt` clean. `sh -n` still fails on `cm_state_fields_anchor_wired.sh` and `cm_repro_first_anchor_wired.sh` (bash arrays; `bash -n` passes); not changed here, recorded in `gates/sh_n.txt` | `gates/sh_n.txt` |

The reviewer RED test file is adopted verbatim
(`idgrammar_r5_rev456r4_red_test.go`, byte-identical to the review's
`out/rev456r4_red_test.go`).

## 2. Tests

`go test -count=1 -json ./...` in `scripts/workable-items`, final tree
(`1e90804c`), run twice, go1.26.8: rc 0 both times; 1038 pass, 0 fail, 6 skip
(the same six pre-existing SKIPs as round 4). The two sorted verdict lists are
identical, sha256
`f624ba35c82118105d916fca4c6e355426e8542c07a1416af5b7f32a1efcd31a`
(`gotest/`).

RED on the round-4 head (`red/red_base_94c9.txt`): the nine round-5 CLI and
reviewer tests run on 94c9 give 7 FAIL (EveryWriterKeepsAuthoredBodyOfMdReadItem,
UnblockingWritersRemoveBlockRow, DescriptionChoicesLineIsDescriptionText,
BlockAtFixedRefused, DescriptionQuoteThenDropKeepsEvidence and the two reviewer
RED tests) and 2 PASS (BlockedNoSeverityUpdateDescription and
LegacyAdoptionMixedFencedRefused, regression guards for behaviour 94c9 already
had). The `bodypatch_test.go` unit tests test the new file and cannot compile on
94c9; they are proven by the mutants of section 4.

## 3. A change made and reverted in this round

Commit `60b87d73` also patched the Type, Severity, Created-By and Assigned-To
lines of the stored body on a field-only `update`. It broke the existing
contract test `TestUpdateCmd_PreservesRichBodyOnSeverityOnlyUpdate` (a
field-only update keeps `body_md` byte-identical; `sync db-to-md` aligns those
lines at render through `alignMetaLines`). It was reverted in `1e90804c`. The
mutation pass run on it (`mutants/plan2.*`) is superseded and kept only as a
record. Class (a) in section 5 is that by-design behaviour.

## 4. Mutants

Runner `mutants/mutrun.sh`: one git worktree per mutant at the named revision,
the full `cmd/workable-items` test package. KILLED = at least one test fails;
`rc=1 fails=0` = the mutant did not compile. Table with the failing tests:
`mutants/mutants_table.tsv`.

| Pass | Revision | Mutants | Result |
|---|---|---|---|
| 1 (`plan.sh`) | `a81f3f13` (same engine as the final head) | CONTROL; reviewer RM1, RM1b, RM3, RM4, RM5, RM6, RM7, RM9, M2; own OM1 to OM15 | CONTROL rc 0. KILLED: RM1, RM3, RM4, RM5, RM6, RM7, RM9, OM1, OM2, OM3, OM6, OM9, OM10, OM12, OM13, OM14, OM15. SURVIVED: M2, OM5, OM7, OM8, OM11. Did not compile: RM1b, OM4 |
| 2 (`plan2.sh`) | `60b87d73` | superseded (reverted change, section 3) | record only |
| 3 (`plan3.sh`) | `1e90804c` (final) | NOOP3 (identity control); RM1b3 and OM43 (compiling re-authorings of RM1b and OM4); OM53, OM113, M23 (OM5, OM11, M2 against the new tests) | NOOP3 rc 0. KILLED: RM1b3 (34 tests), OM43, OM53, OM113, M23 |

Recorded equivalents (survivors with no behavioural difference reachable
through the CLI): OM7 (the post-write read-back of the block record in
`block` is defence in depth: the owned-line gate already refuses every body
that would lose it) and OM8 (with the `loc == "Fixed"` refusal removed, the
`loc != "Issues"` fallback that follows refuses Fixed as well).

## 5. Class sweep

All runs from the repository root (validate resolves evidence paths against
the working directory), on scratch copies of the tracker database at 94c9
(`docs/workable_items.db`, sha256 `1ca8399e…`), with `ev/build1` (sha256
`5257247d…`, byte-equal to the final binaries).

- **proseloss** (`class/proseloss_*.json`), 479 Issues items, one writer per
  copy, authored bytes lost: `block` 0 (main control 314,118 bytes on 207
  items), `update --description` same text 0 (main control 314,118 on 207),
  `close` 0 with 153 refused (Type/Status rules), negative control
  `update --title` same title 0 in both.
- **closebytype** (`class/closebytype_*.json`), 481 items: accepted 432,
  refused 49, 0 bytes lost, validate 0 (main control 292,462 bytes lost).
- **mdsweep** (`class/mdsweep_*.json`), 61 state × writer cases with a body
  that carries every record kind in every position (metadata block, prose,
  quote, indented, fenced), then a `db-to-md` / `md-to-db` cycle: round 5 has
  0 cases with dropped lines (main control 6) and 0 cases with a block row
  left behind (main control 6). The 19 remaining flags fall in three classes,
  none a loss:
  - (a) field-only update (`upd_sev`, `upd_type`, `upd_assign`): the stored
    body keeps the old Type/Severity/Assigned-To line until the next
    `md-to-db`; the export carries the new value (by design, section 3);
  - (b) a blocked item whose body quotes an `**Unblock-Choices:**` line in
    prose or a fence: the parser (`operatorBlockParts`) reads the last such
    line anywhere in the body, so the side row differs after one cycle. Same
    on main; pre-existing, follow-up;
  - (c) `update --type` on a Fixed item creates a Type/Status mismatch that
    validate reports (exit 1): the Type↔Status guard runs only with
    `--status`. Same on main; pre-existing, follow-up.
- **id grammar round trip** (`idsweep/`), 32 ids and prefixes: round 5
  accepts 21, refuses 11, LOSS 0; main control accepts 32, LOSS 13.

## 6. Real tracker copy

`tools/realtracker_check.sh` with the final binary on the 491-item tracker
copy (`realtracker/realtracker_r5_summary.txt`): validate, diff against the
committed Markdown, three exports and two `md-to-db` cycles all OK; side tables
equal after both cycles; FAILS=0. Main control: FAILS=2 (side tables differ
after each cycle). Both report 279 descriptions re-derived on the first cycle
and 0 on the second (the derived description column, unchanged since round 2).

## 7. Gates

From the repository root (`gates/gates.tsv`, run at `60b87d73`, which differs
from the final head only in Go code under `scripts/workable-items`):
verify-manifest MANIFEST-OK; full-suite manifest census PASS (966);
gate-ledger ratchet PASS; constitution index fresh PASS; git-env census PASS
(664 members, 510 hermetic, 154 exempt, 0 unscrubbed); state-fields anchor PASS
245/245 and its mutation test PASS (270 RED/BLIND, 8 GREEN); repro-first
anchor PASS 175/175 and its mutation test PASS (189 RED/BLIND, 5 GREEN);
reporting directives PASS; feature directive PASS; report_item bug states 3
passed; us3 shipped engine all hold; constitution command PASS 292, FAIL 0.
`cm_helix_deps_manifest_present` is BLIND (exit 2): the own-org submodules are
not checked out in the scratch clone (same as round 4); not a PASS.

## 8. Build

`build/build_facts.txt`. go1.26.8, `GOEXPERIMENT=nodwarf5 GOPROXY=off go build
-trimpath -buildvcs=false -ldflags=-buildid=`. Two separate builds and the
two committed binaries are byte-equal, sha256
`5257247d7974e7ce24dca43fe7e9687d50220a0d85f1674e502bdb4da459297e`;
`bin/.source.sha256` recomputed at the head is equal to the committed value.
The base 94c9 rebuilt with go1.26.8 gives `cc8ab720…`, not its committed
`a792788d…` (built with an earlier go1.26 patch release), so binary identity
is only comparable within one toolchain.

## 9. Limits and follow-ups

- Parser: `Unblock-Choices` is read from the last matching line anywhere in
  the body, prose and fences included (class (b)); pre-existing.
- `update --type` on a closed item is not checked against the Type↔Status
  rule (class (c)); pre-existing.
- `cm_helix_deps_manifest_present` BLIND in the scratch clone.
- `sh -n` fails on the two anchor-wired gates (bash arrays; `bash -n` clean);
  pre-existing.
- Round-4 follow-ups not touched: stored description after adoption, a block
  row edited by hand in the database, validate's evidence-path resolution
  against the working directory.
- Evidence is gate-logic and host-only; nothing ran on a live tracker.

## 10. Tools

`tools/` holds the sweep scripts used (sha256 in `SHA256SUMS`); `mutants/`
holds the mutation runner and plans.
