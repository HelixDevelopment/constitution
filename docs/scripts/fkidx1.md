# fkidx1 (runner patch) — guide

**Revision:** 1
**Last modified:** 2026-09-26T13:40:00Z

Source: `constitution/scripts/codegraph/runner_patches/fkidx1.py` (107 lines). It is a **module driven by
`fk_index_patch.py`**, not a command: nothing in it is run directly. Citations are `fkidx1.py:<line>` unless
another file is named. Machinery guide: [fk_index_patch](fk_index_patch.md).

## Overview

Stock CodeGraph 1.6.0 speeds up bulk indexing by **dropping secondary indexes** before a bulk window (three lists in
`lib/dist/db/index.js`: `BULK_PARSE_INDEX_NAMES`, `BULK_REF_INDEX_NAMES`, `BULK_EDGE_INDEX_NAMES`) and recreating them
afterwards. It also runs `INSERT OR REPLACE INTO nodes` with `foreign_keys=ON`. A REPLACE of an existing node id
deletes the old row, which fires `ON DELETE CASCADE` on every child table with a foreign key to `nodes(id)`; if the
child's key column has no index, each cascade is a **full table scan** (module docstring, lines 1-8).

`fkidx1` edits `lib/dist/db/index.js` in the private runner copy so that the FK child-key indexes are **removed from
the drop lists** (they stay in place through the bulk windows). It never edits the shared install (that is the
machinery's job, see the parent guide).

The keep-set is not hard-coded: it is **derived from the target's own `schema.sql`** (lines 26-37, 51-71), so it adapts
to upstream schema changes and reports NOT_NEEDED when the hazard is not there.

## Prerequisites

- Files read from the package (lines 16-18): `lib/dist/db/index.js`, `lib/dist/db/schema.sql`,
  `lib/dist/db/queries.js`.
- Python 3 standard library only (`re`), plus `runner_patches/common.py` (`NotNeeded`, `Refuse`, `PatchPlan`).
- Loaded by `runner_patches.load()`; registered first (`runner_patches/__init__.py:17`), default set member
  (not opt-in).

## Usage

Only through `fk_index_patch.py`:

```sh
python3 scripts/codegraph/fk_index_patch.py --patches fkidx1 --dst <scratch dir> [--src <package dir>]
```

`NOT RUN` in this form (it copies the ~282 MB package; see the parent guide for the tiny-fixture build that was run).
What **was** run (read-only planning, no copy, no write):

- `VERIFIED (ran: python3 with sys.path at scripts/codegraph; FileView over a scratch dir holding stock 1.6.0
  db/index.js + schema.sql + queries.js; fkidx1.plan(view); saw: kept_indexes = [idx_edges_target_kind,
  idx_unresolved_from_node]; list sizes BULK_PARSE 15 -> 14, BULK_REF 5 -> 4, BULK_EDGE 4 -> 3)`. So on stock 1.6.0
  the patch keeps exactly two indexes and touches all three lists (a kept index can appear in more than one list).
- The planned `db/index.js` passes `node --check` with the package's bundled node (part of the parent guide's
  verification, with a broken-file control that exits 1).

## Behaviour (source-traced)

`plan(view)` (lines 97-107):

1. `compute_patch` (lines 51-71):
   - NOT_NEEDED if `queries.js` no longer contains `INSERT OR REPLACE INTO nodes` (line 52-53);
   - NOT_NEEDED if `db/index.js` no longer contains `foreign_keys = ON` (regex `foreign_keys\s*=\s*ON`, lines 54-55);
   - `derive_keep_set` (lines 26-37): walks `CREATE TABLE IF NOT EXISTS ... );` blocks in `schema.sql`, collects
     `FOREIGN KEY (col) REFERENCES nodes(id)` columns, and every `CREATE [UNIQUE] INDEX IF NOT EXISTS` with its
     leading column; NOT_NEEDED if there is no FK to `nodes(id)` at all (line 31-32);
   - `parse_lists` (lines 40-48): parses the three `static BULK_*_NAMES = [...]` lists; **Refuse** if any of the three
     is missing or empty ("upstream shape changed");
   - for every FK child column, if some index led by that column is **never dropped** in any list, nothing to do
     (lines 60-62); else it must have an index candidate in `schema.sql` (else **Refuse**, line 64-65) and the
     candidate with the fewest columns (ties by name) is added to the keep set (lines 66-67);
   - NOT_NEEDED if the keep set ends up empty (lines 69-70).
2. `patch_text` (lines 74-95): for each kept index, removes its quoted name from every list that holds it; **Refuse**
   if the name is in no list (line 79-80), does not appear exactly once in a list (lines 86-88), or if a list would
   become empty (lines 92-94).
3. The plan records the edited file, one anchor per touched list, and `detail = {kept_indexes, lists_before,
   lists_after}` (lines 100-106); `fk_index_patch.py` copies those into the legacy top-level receipt fields.

Outputs: an edited text for `lib/dist/db/index.js` only. Side effects: none in this module (pure function of the three
files' text).

## Edge cases

All `VERIFIED (ran: planning against copies of the stock 1.6.0 files in a scratch directory)`:

| Condition | Result |
|---|---|
| Stock 1.6.0 | APPLIED, keep = `idx_edges_target_kind`, `idx_unresolved_from_node` |
| Plan again on the already-patched text | NOT_NEEDED: `every FK child column is already served by a never-dropped index` (not an error, unlike the other patches) |
| `INSERT OR REPLACE INTO nodes` replaced by `INSERT INTO nodes` in `queries.js` | NOT_NEEDED: `queries.js no longer uses INSERT OR REPLACE INTO nodes` |
| `foreign_keys = ON` changed to `OFF` in `db/index.js` | NOT_NEEDED: `db/index.js no longer enables foreign_keys` |
| `REFERENCES nodes` renamed in `schema.sql` | NOT_NEEDED: `schema.sql has no FOREIGN KEY ... REFERENCES nodes(id)` |
| `BULK_EDGE_INDEX_NAMES` renamed in `db/index.js` | **Refuse**: `db/index.js: BULK_EDGE_INDEX_NAMES not found/empty — upstream shape changed` |

Known limitation (from `tests/test_patch_machinery.py`, run 2026-09-26): the list parser does not assert that each
`static BULK_*_NAMES` declaration is unique, so a commented-out duplicate or a duplicated declaration is not refused
(cases P1b/P1c FAIL today; this is the tool's own RED test). See the parent guide, "Known discrepancies".

## Internal behaviour / oracle

The external oracle for this patch is `fk_cascade_probe.py` (module header lines 6-7): it demonstrates the cascade
full-scan hazard on a stock database and that the patched runner removes it. It is a separate tool with its own guide
([fk_cascade_probe](fk_cascade_probe.md)); `codegraph_safe.sh` runs it to prove stock safe when the machinery exits 3
(NOT_NEEDED for every patch), per the parent guide.

## Tests

`fkidx1` has no dedicated test file. It is exercised by `tests/test_patch_machinery.py` (fkidx1 build cases, P1-P4)
and referenced by `tests/test_bulk_classify_mutate.py`, `tests/test_mcp_readonly_mutate.py`, `tests/test_unit_safe.sh`
(those name the id in registry/selection arguments). `owed_report.py` counts it as tested for that reason.
FINDING: there is no behavioural test of the *derivation* logic (keep-set for other schemas) in the tree; the checks in
the Edge cases table above were run ad hoc for this guide.

## Related scripts

[fk_index_patch](fk_index_patch.md) (the machinery), [fk_cascade_probe](fk_cascade_probe.md) (oracle),
[codegraph_safe](codegraph_safe.md) (consumer; default patch set `fkidx1,resolve1`), siblings
[lockfix1](lockfix1.md), [datafrag1](datafrag1.md), [resolve1](resolve1.md), [resolve2](resolve2.md),
[mcpro1](mcpro1.md).

## Last verified

2026-09-26, against stock CodeGraph 1.6.0 files copied to a scratch directory; no writes to the real runner cache or to
any `.codegraph` index.
