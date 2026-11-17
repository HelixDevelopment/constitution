# Class inventory, round 2 (CON-339, restore-created-at)

| Field | Value |
|---|---|
| Revision | 3 (round 4: status line updated; round 3 and round 4 described in `../round3/README.md` and `../round4/README.md`) |
| Created | 2026-11-14 |
| Status | PROVISIONAL. Independent round-3 review: NO-GO (F1, F2 important); round 4 remediation in `../round4/README.md`, its independent review not yet done |
| Roadmap-Item | CON-PENDING-ENGINE-CREATEDAT |

Written before the round-2 fixes, as the structural round requires (§11.4.276(C)): every member of each class is
listed, with how it is covered. Measured on the vehicle head with `git grep` over
`scripts/workable-items/cmd/workable-items/*.go` excluding `*_test.go`.

## Class 1: every writer of `items` rows

| Site | Kind | created_at | Coverage |
|---|---|---|---|
| `crud.go:164` `add` | INSERT, new item | column default `datetime('now')` (correct for a new item) | `TestCON339_CreatedAtPreservedByEveryMutatingCommand` |
| `subtask.go:174` | INSERT, new subtask | column default (correct) | same; `subtask add` is not dispatched by `main()` (pre-existing, register item D-04) |
| `crud.go:393` + `:420` `close` | DELETE then INSERT | value read before the DELETE and carried | `TestCON339_*`, `TestCON339R2_CloseDualRepCarriesTheClosedRowsValue` (RM05) |
| `db.go:926` + `:933` `replaceDocumentWithSnapshot` (`sync md-to-db`, `replaceDocument`) | DELETE of a document then INSERT | snapshot by `id|loc|rep`; inner snapshot wins; prior fills absent keys; new item: `datetime('now')` | `TestCON339R2_*` (RM01, RM02, RM03, RM06, RM07), `TestCON339_MDToDBMoveAcrossDocumentsKeepsCreatedAt` (RM04) |
| `db.go:413` v5 migration `INSERT INTO items_new ... SELECT` | table rebuild | copied column for column | migration tests (pre-existing) |
| `mutate.go:417, 567, 875, 991`, `crud.go:637`, `group.go:483`, `obsolete.go:147`, `repair_bodies.go:302`, `states_cli.go:519`, `version_tags.go:254` | UPDATE | never set (`statesUpdateSet`, `db.go:198`, names no created_at) | `TestCON339_CreatedAtPreservedByEveryMutatingCommand` |
| `restore_created_at.go` UPDATE | UPDATE, compare-and-set | the only writer that sets created_at | the restore tests below |
| triggers | none in the schema | | |

Outside the engine package: only tests, fixtures and documentation write `items` rows (`git grep`, round 1).

## Class 2: every path that can rewrite a stored timestamp

- `items.created_at`: the four paths of class 1 that delete and re-insert (close, md-to-db, the v5 migration) and the
  restore UPDATE. Close and md-to-db were the CON-339 defect; both now carry the value.
- `items.last_modified`: every UPDATE sets it to `datetime('now')` by design; md-to-db resets it (pre-existing,
  register item D-02).
- `item_history.created_at`: append-only in the engine (`recordHistory`); no UPDATE or DELETE of history rows.

Measured on the three committed tracker databases at the base: earliest history row `2026-11-04 22:00:31`, earliest
items row `2026-11-06 09:38:10`; 0 items created before the earliest history row; 0 items without history. At
`bd0036bd`, 226 of 263 items hold a created_at LATER than their own first history row (register item D-05).

## Class 3: every refusal code of `restore-created-at` (23)

Every code is reached by a test that asserts the code and that nothing was written (`r2Refused` or the round-1
`Refusals` table). Counted with `grep` over the two test files (number of mentions in parentheses).

| Code | Test file(s) |
|---|---|
| USAGE (9) | `restore_created_at_test.go` |
| VALUE-FORMAT (5) | both |
| EVIDENCE-SHA256 (4) | both |
| DB-MISSING (2) | `restore_created_at_test.go` |
| EVIDENCE-UNRESOLVED (1) | `restore_created_at_test.go` |
| EVIDENCE-NOT-FILE (1) | `restore_created_at_test.go` |
| EVIDENCE-IS-LIVE-DB (3) | both (hard link and symlink: round 2, MR18) |
| EVIDENCE-WAL (2) | both (journal sidecar and empty sidecars: round 2, RR06, MR19) |
| DB-UNREADABLE (2) | `created_at_r2_test.go` (round 2) |
| ITEM-NOT-FOUND (3) | both |
| ITEM-AMBIGUOUS (1) | `restore_created_at_test.go` |
| EVIDENCE-NOT-DB (2) | both |
| EVIDENCE-ITEM-MISSING (2) | `restore_created_at_test.go` |
| EVIDENCE-ITEM-MISMATCH (4) | both (type, title, every row: round 2, RR05, RR10) |
| EVIDENCE-DOES-NOT-ATTEST (2) | both (only Opened attests: RR04) |
| HISTORY-UNREADABLE (1) | `restore_created_at_test.go` |
| NO-HISTORY (1) | `restore_created_at_test.go` |
| VALUE-AFTER-FIRST-EVENT (3) | both (boundary: RR01) |
| VALUE-BEFORE-TRACKER (2) | `created_at_r2_test.go` (new in round 2) |
| CURRENT-UNREADABLE (1) | `restore_created_at_test.go` |
| VALUE-LATER-THAN-CURRENT (3) | both (boundary: RR02, RR15) |
| CONCURRENT-CHANGE (2) | `created_at_r2_test.go` (round 2, through the test seam: RR07) |
| WRITE (3) | `created_at_r2_test.go` (round 2, audit failure rolls back) |

## Class 4: the plan applier's refusals (`apply_restore_plan.sh`)

Usage (exit 2), BLIND (exit 3: missing engine, db or plan, `--root` not a directory, a row without an id for the
landing, an absolute or `..` evidence path, a symlinked path component, an evidence directory resolving outside
`--root`, `git show` failure, sha256 mismatch, empty plan), engine refusal counted (exit 1). Round 3 correction: the round-2 suite
runs 20 cases (A1 to A16 with A5b, A6b, A11b, A11c), not 19, and had no case for a missing engine, database or plan,
for `--root` not a directory, or for an evidence directory resolving outside `--root` (A5 reaches the walk, not that
check). Round 3 adds them: B1 (the evidence-path matrix), B2 (the `--root` forms), B3 (BLIND and usage inputs), B4 (a
racing mkdir reaching the resolved-directory check); 69 cases in all, and shell mutants MS01 to MS11, VS01 to VS03
and MU01 to MU05.
