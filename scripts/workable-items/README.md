# workable-items — §11.4.93 SQLite-SSoT Go binary

**Revision:** 5
**Last modified:** 2026-11-04T00:00:00Z
**Description:** Authoritative source-of-truth registry for every workable item in every consuming project. Bidirectional regen between SQLite DB and Markdown trackers per Constitution §11.4.93.

## Overview

Per Constitution §11.4.93, every consuming project's workable-items
inventory (Issues.md / Fixed.md / Issues_Summary.md / Fixed_Summary.md /
Status.md fleet / CONTINUATION.md §3) is reconstructible from this
DB-backed registry. The DB is the **authoritative** source; all
Markdown / HTML / PDF surfaces are generator output.

Sync drift is mechanically impossible because every regeneration
starts from the DB.

## Layout

| Path | Purpose |
|---|---|
| `schema.sql` | DDL — 6 tables: items + item_history + obsolete_details + operator_block_details + firebase_metadata + meta |
| `cmd/workable-items/main.go` | Go binary entrypoint (Phase 2 scaffold) |
| `pkg/itemsdb/` | SQLite access layer (Phase 2 scaffold) |
| `pkg/mdparser/` | Markdown→DB parser (Phase 3 scaffold) |
| `pkg/mdrender/` | DB→Markdown renderer (Phase 4 scaffold) |
| `tests/` | Unit + integration + stress + chaos tests per §11.4.85 |

## Subcommands (implemented)

All subcommands below are implemented and tested against a real SQLite DB
(no mocks). `--db <path>` is required by every subcommand.

```
workable-items sync md-to-db --db <p> [--issues <p>] [--fixed <p>]
                                    # parse Issues.md+Fixed.md → upsert DB
workable-items sync db-to-md --db <p> [--out-issues <p>] [--out-fixed <p>]
                                    # regen MD docs from DB (byte-identical round-trip)
workable-items diff --db <p> [--issues <p>] [--fixed <p>] [--partial-scope] | --db-only
                                    # show DB vs MD divergence (CI gate).
                                    # REFUSES rather than emit a verdict it cannot
                                    # support: with NO Markdown path (BOB-155), and
                                    # when the supplied path(s) do not account for
                                    # every DB item's current_location (BOB-186) —
                                    # e.g. --issues alone while the DB holds Fixed
                                    # rows, which previously reported "in sync"
                                    # having compared none of them.
                                    # --db-only     : DB-internal checks only, reads
                                    #                 no Markdown (verdict says so).
                                    # --partial-scope: compare only the tracker(s)
                                    #                 supplied; the verdict names the
                                    #                 locations it did NOT cover and
                                    #                 never claims a full sync.
workable-items validate --db <p>    # invariant + schema sanity (pre-build gate)
workable-items add <type> <severity> --db <p> --title <T> --description <D> [--id <id>] [--prefix <P>]
                                    # create a new Queued item in Issues; --id
                                    # auto-generated as <PREFIX>-NNN when absent
                                    # (PREFIX defaults to WIT). §11.4.91 floor
                                    # enforced on --description at entry.
workable-items update --id <ID> --db <p> [--title|--severity|--description|--type|--status|--created-by|--assigned-to ...] [--location Issues|Fixed]
                                    # mutate ONLY the explicitly-set fields on an
                                    # existing item; regenerate body_md; append an
                                    # item_history 'Updated' row (§11.4.34). Rejects
                                    # unknown ids, no-field calls, §11.4.91-short desc.
workable-items reopen --id <ID> --db <p> --why <reason> --who <AI|User> --when <ISO> --incident <p> [--location Issues|Fixed]
                                    # set Status=Reopened with the four §11.4.34
                                    # attribution facts (By/On/Reason/Evidence). --why
                                    # drawn from the closed set: test-failed |
                                    # manual-testing-detected | captured-evidence-
                                    # contradicts | end-user-report | cycle-re-
                                    # discovered | design-reconsidered. ALL four
                                    # mandatory (a reopen is a §11.4.7 demotion).
workable-items block --id <ID> --db <p> --details <WHAT> [--why <T>] [--unblock <T>] [--who <T>] [--location Issues|Fixed]
                                    # set Status=Operator-blocked + an
                                    # operator_block_details row (§11.4.21). --details
                                    # (the WHAT) is mandatory and non-empty.
workable-items close <atm-id> --db <p> --status <fixed|implemented|completed|obsolete> --evidence <p>
                                    # atomic Issues→Fixed move (§11.4.19); --evidence
                                    # mandatory (§11.4.5/§11.4.90); records item_history.
workable-items report --db <p> [--by-type|--by-status|--by-severity|--by-assigned|--by-creator|--obsolete-audit]
                                    # read-only grouped tally; --obsolete-audit lists
                                    # Obsolete items + flags missing §11.4.90 details.
workable-items export --db <p> [--out-dir <d>] [--formats|--no-formats] [--out-issues <p>] [--out-fixed <p>]
                                    # regenerate Issues.md + Fixed.md (byte-identical
                                    # round-trip) + Issues_Summary.md (§11.4.12 open-
                                    # only Type×Status tally) + Fixed_Summary.md
                                    # (§11.4.53 closed-only) + §11.4.65 HTML/PDF/DOCX
                                    # siblings via pandoc (--pdf-engine=weasyprint)
                                    # ONLY when the constitution formats-export switch is ON
                                    # (DOCS_EXPORT=1 / docs/context/doc_export.policy
                                    # enabled=1 / --formats); default OFF = Markdown only
                                    # + an honest "formats export disabled" line. Same for
                                    # subtask-export.
                                    # Sibling steps are exec.LookPath-gated: when
                                    # pandoc/weasyprint is absent the .md is still
                                    # written + an honest message printed — NO fake
                                    # sibling is fabricated (§6.J/§11.4.6).
workable-items add|update ... [--reproduction-state S] [--investigation-state S]
                              [state detail flags] --states-updated-by <who>
                                    # §11.4.294 reproduction / investigation records
                                    # (see "Reproduction and investigation states").
workable-items states import --db <p> --tsv <file> --by <who> [--at <RFC3339Z>] [--dry-run]
                                    # apply a canonical states TSV in ONE transaction:
                                    # all-or-nothing, idempotent.
workable-items states freeze --db <p> --by <who> [--at <RFC3339Z>] [--dry-run]
                                    # arm the closure gate ONCE; a second freeze is refused.
```

Positional and flag arguments may be given in either order (e.g. both
`add Bug Critical --db x …` and `add --db x … Bug Critical` are accepted).

`add`, `update`, `reopen`, `block`, and `close` all mutate the DB *and*
keep the §11.4.93 byte-identical round-trip intact: they generate / regenerate
/ move the canonical `## <ID> — <title>` item block + its `doc_segments` entry
so a subsequent `sync db-to-md` regenerates a well-formed, re-parseable tracker
(add is a stable fixed point; close round-trips and re-validates; update/reopen/
block regenerate `body_md` with the new status + any §11.4.34/§11.4.21 detail
line embedded in the heading-adjacent meta block).

## Reproduction and investigation states (schema v8, §11.4.294)

Every item carries two closed-vocabulary state fields (§11.4.294(A)). The `items`
columns are authoritative; the item body carries one single-line record per field
(the human-readable mirror and the carrier of the details). Both default to
`UNSET`; a pre-v8 database is migrated losslessly the first time the binary opens
it (the columns and the `repro_gate_exemptions` table are added, nothing is
backfilled, so every existing item is `UNSET`).

| Column | Closed vocabulary (exactly these six values) |
|---|---|
| `reproduction_state` | `UNSET` · `UNREPRODUCED` · `reproduced-live` · `reproduced-host-fixture` · `not-reproducible-with-evidence` · `blocked-no-device-with-recorded-blocker` |
| `investigation_state` | `UNSET` · `not-started` · `in-progress` · `root-cause-found-with-evidence` · `root-cause-unconfirmed` · `closed-no-defect` |

`UNSET` means never assessed (permanent and correct for a non-defect item);
`UNREPRODUCED` means assessed and no capture of the symptom exists. The two are
different facts and no output merges them.

**One spelling of every state.** The sixth reproduction value is stored, rendered
(body line, `Issues_Summary` / `Fixed_Summary` cell), written into the `Updated`
history reason and printed by every message in its long form
`blocked-no-device-with-recorded-blocker`, which is the §11.4.292(B) spelling.
The short `blocked-no-device` is an INPUT ALIAS only: it is accepted as the value
of `--reproduction-state` and as a `reproduction_state` cell of a `states import`
TSV, and is normalised to the long form before anything is stored. It is never
stored and never rendered, and a `**Reproduction:**` body line that starts with it
is not a state: `validate`, `diff`, `update` and `states import` report it
(`head "blocked-no-device" is not a canonical Markdown result token`). Any other
spelling is refused with the closed set listed.

### Body records (database to Markdown and back, byte-identical)

```
**Reproduction:** <result> — <REPRODUCED|UNREPRODUCED> [— surface <live-target|host-only>] [— evidence `<path>`]
    [— red-command `<cmd>`] [— green-command `<cmd>`] [— env `<id>`] [— signature `<text>`]
    [— blocker `<text>`] [— updated <RFC3339Z>] [— by `<who>`]            (ONE physical line)
**Investigation:** <state> [— root-cause `<text>`] [— evidence `<path>`] [— updated <RFC3339Z>] [— by `<who>`]
```

`<result>` is the reproduction state, or `none` for `UNREPRODUCED` (§11.4.292(C));
`UNSET` writes no line. The label `REPRODUCED` / `UNREPRODUCED` is never stored: it
is computed from the record (a `reproduced-live` or `reproduced-host-fixture`
record is `REPRODUCED` only with surface, evidence, red-command, env and signature
present, and a host fixture only on a `host-only` surface) and a hand-edited label
that disagrees with the record is a parse problem. Free-text values are CommonMark
code spans; a line whose remainder does not start with a closed-set head is legacy
prose and is neither interpreted nor rewritten. `Issues_Summary.md` and
`Fixed_Summary.md` carry two trailing columns, Reproduction and Investigation.
`validate` and `diff` report a column that disagrees with its body record
(column-to-body desync), a malformed record and a pipe-table row that carries a
state (a table row cannot hold a record).

### Setting states

```
workable-items update --id WIT-123 --db tracker.db \
    --reproduction-state reproduced-live --reproduction-surface live-target \
    --reproduction-evidence qa-results/wit123/red.txt \
    --reproduction-red-cmd 'bash tests/red.sh --board D2' --reproduction-env 'D2 serial 998fd' \
    --reproduction-signature 'count=0' \
    --investigation-state in-progress --states-updated-by conductor
workable-items update --id WIT-124 --db tracker.db --reproduction-state blocked-no-device \
    --reproduction-blocker 'needs: D2 board; missing: HDMI capture rig' --states-updated-by conductor
    # the alias is accepted on input; the stored value, the body line and the
    # history reason read blocked-no-device-with-recorded-blocker
```

`add` takes the same flags. Any state flag needs `--states-updated-by` (attribution,
§11.4.34); `--states-updated-at` defaults to now. A block whose content changes is
stamped with `updated` / `by` and the change appends an `Updated` history event in
the same transaction (`reproduction <old> -> <new>` or `investigation <old> -> <new>`).
Setting a state to `UNSET` clears that block's details. Record invariants checked on
every write: `reproduced-live`, `reproduced-host-fixture` and
`not-reproducible-with-evidence` need an evidence path that exists;
`blocked-no-device-with-recorded-blocker` needs a blocker text;
`root-cause-found-with-evidence` needs a root-cause text and an evidence path that
exists; `closed-no-defect` needs an evidence path that exists; details need a state
other than `UNSET`.

### `states import` (bulk, all-or-nothing, idempotent)

```
workable-items states import --db tracker.db --tsv states.tsv --by conductor [--at 2026-11-04T10:00:00Z] [--dry-run]
```

The TSV header is exactly (tab separated, no quoting, one item per line)
`atm_id location reproduction_state reproduction_surface reproduction_evidence
reproduction_red_cmd reproduction_green_cmd reproduction_env reproduction_signature
reproduction_blocker investigation_state investigation_root_cause
investigation_evidence`; `location` is `Issues`, `Fixed` or empty (empty is
refused when the id exists in both). Per block, a non-empty state cell REPLACES that
record with exactly the row's values (write `UNSET` to clear it); an empty state cell
leaves the block as stored and its detail cells must then be empty too. Every row is
checked before anything is written (unknown or ambiguous item, pipe-table row,
closed sets and the alias, formats, evidence resolution, a malformed record already
in the body, the closure invariants below); one bad row writes nothing. A row equal
to the stored record is a no-op, so a re-run changes nothing and re-stamps nothing.
`--dry-run` checks every row and writes nothing.

### Closure gate (§11.4.294(D)), armed once by `states freeze`

| Check | Armed | Rule |
|---|---|---|
| C1 | always | an item closed `Fixed` / `Implemented` / `Completed` that carries a reproduction record must be labelled `REPRODUCED`; an `UNREPRODUCED` item (including `blocked-no-device-with-recorded-blocker` and `not-reproducible-with-evidence`) stays PROVISIONAL-DONE (`Ready for testing` / `In testing`) and is refused a VERIFIED closure by `close`, `move` and `update --status` |
| C2 | after `states freeze` | a `Bug` closed `Fixed` / `Implemented` / `Completed` must carry a reproduction record (`UNSET` is the never-reproduced case); refused up front by `close`, `move` and `update --status`, reported by `validate` |
| C3 | after `states freeze` | a defect item closed `Obsolete` must carry one of the four results, unless its §11.4.90 reason is a non-defect one (`duplicate-of`, `superseded-by-design-change`, `superseded-by-later-mandate`, `feature-removed`, `unsupported-topology`); reason `not-reproducible` requires `not-reproducible-with-evidence`; reported by `validate` (a close to `obsolete` is not refused up front: its §11.4.90 reason is recorded after the close) |

`states freeze --db <p> --by <who>` records the gate as armed (`meta`
`repro_gate_armed_at` / `repro_gate_armed_by`) and writes a `repro_gate_exemptions`
row for every item that was already closed and would fail C2 / C3 today, so only
later closures are checked. `--dry-run` prints how many items would be exempted and
how many unconditional (C1) problems stay reported. A second freeze is refused.
Until `states freeze` has run against a database, only C1 and the record invariants
are active.

### Honest boundaries

- The engine checks that an evidence path EXISTS when a state is written or
  validated; it does not record or re-verify a sha256 of the evidence file, and it
  does not demote a state whose evidence later disappears (clause (C) asks for both;
  `validate` reports the unresolved path, nothing is demoted automatically).
- The lifecycle transitions that need a commit or a status outside the tracker (a
  fix commit needing a reproduction, the regression reopen of clause (F), the
  external-tracker mirror of clause (I)) are consumer work (the deferred gates
  `OWED-GATE-177`, `OWED-GATE-178` and `OWED-GATE-179`), not engine features.
- A rehearsal of `states freeze --dry-run` on a copy of a consumer database exists
  (2026-11-03, 66 closed items would be exempted, 0 unconditional problems); the
  behaviour of this binary on a real consumer database is UNCONFIRMED until the
  consumer runs it.

## Anti-bluff coverage (mandatory per §11.4.93 + §11.4.85)

| Layer | Test |
|---|---|
| Unit | every CRUD operation + every schema invariant + closed-set validators |
| Integration | full MD→DB→MD round-trip byte-identical (modulo whitespace tolerance) |
| Stress per §11.4.85 | 1000-row insert; 10 concurrent writers; sustained read throughput |
| Chaos per §11.4.85 | mid-write SIGKILL; corrupt-DB recovery; disk-full; FD exhaustion |
| Paired §1.1 mutation | strip CRUD function → unit test FAILs |
| Paired mutation, states | `python3 -I mutation/states_mutation_runner.py` (run from this directory) applies 19 mutants to the state code (closed sets, round trip, desync detector, closure gate, import, migration) and requires every one to be killed by a named `^TestStates` / `^TestStatesCLI` test; the unmutated control must pass |
| HelixQA Challenge | `CME-WORKABLE-ITEMS-001` exercises end-to-end DB→MD→DB→MD |

## 6-phase migration per §11.4.93 (consuming-project work)

1. **Phase 1** — Issues entry `§LA` filed, scope-locked.
2. **Phase 2** — Go binary scaffold + DDL committed (this PWU).
3. **Phase 3** — `sync md-to-db` lands + captures initial migration.
4. **Phase 4** — `sync db-to-md` lands + byte-identical round-trip CI gate.
5. **Phase 5** — Existing bash generators (`generate_issues_summary.sh` etc.)
   become Go-binary shims.
6. **Phase 6** — Legacy text-direct edits prohibited (pre-commit hook).

## Composes with constitution anchors

§11.4 / §11.4.12 / §11.4.15 / §11.4.16 / §11.4.17 / §11.4.19 /
§11.4.21 / §11.4.27 / §11.4.30 / §11.4.33 / §11.4.34 / §11.4.42 /
§11.4.43 / §11.4.44 / §11.4.45 / §11.4.50 / §11.4.52 / §11.4.53 /
§11.4.54 / §11.4.55 / §11.4.56 / §11.4.57 / §11.4.58 / §11.4.60 /
§11.4.65 / §11.4.74 / §11.4.77 / §11.4.83 / §11.4.85 / §11.4.86 /
§11.4.87 / §11.4.89 / §11.4.90 / §11.4.91 / §11.4.92 /
§11.4.292 / §11.4.294.

## Canonical authority

[`../../Constitution.md`](../../Constitution.md) §11.4.93.
