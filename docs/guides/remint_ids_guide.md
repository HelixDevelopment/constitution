# Re-mint guide — `remint_ids.py`: land a vehicle's tracker changes, three-way

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13T19:30:00Z |
| Status | active |
| Status summary | User guide and manual for landing a vehicle's tracker changes onto a target tracker: a three-way plan (base, vehicle, target), ids the vehicle minted moved to the target's next free numbers, every change replayed through the workable-items engine, conflicts reported, never guessed. |
| Authority | Constitution §11.4.54 (ids never renumbered once landed), §11.4.93 (the engine is the only writer of the database), §11.4.249 (the verifier is not the producer), §11.4.288 (landing on `main`) — the canonical text wins where this guide and the constitution disagree. |
| Scope | Universal (§11.4.17); the prefix, the database paths and the file list are consumer DATA (§11.4.35). |
| Issues | not wired into a seam: a lander runs it by hand |
| Issues summary | The vehicle's history rows, `created_at` and `last_modified` are not carried (see the honest boundary); verify reports them as KNOWN. |
| Fixed | revision 2: tracker-intake round 4 (review findings R3-1, R3-2 and the minors): three-way plan, base-item changes, conflicts, FAST-FORWARD, a separate verify oracle; revision 1: tracker-intake round 3 (review R2-7) |
| Fixed summary | Round 3 replayed only the items the vehicle minted, so a landing lost the vehicle's changes to base items (R3-1) and verify re-ran the producer's own logic (R3-2). |
| Continuation | — |

## Table of contents

- [Why it exists](#why-it-exists)
- [The landing sequence](#the-landing-sequence)
- [Commands](#commands)
- [How a plan is built](#how-a-plan-is-built)
- [Rewrite rules](#rewrite-rules)
- [Which text files to rewrite](#which-text-files-to-rewrite)
- [Exit codes](#exit-codes)
- [Tests](#tests)
- [Honest boundary](#honest-boundary)

## Why it exists

Two vehicles that start from one base both mint ids from the base's maximum. The tracker-intake
vehicle minted CON-299..CON-342; the fix227 vehicle, from the same base, minted CON-300..CON-311.
Whichever lands second collides. A vehicle also changes items it did not mint: it closes base items,
edits their text and records their reproduction state. The engine has no rename command and the
binary `docs/workable_items.db` cannot be merged by git, so the second vehicle is replayed onto the
landed database. An id is renumbered only while it has never landed (§11.4.54 binds landed ids).

`remint_ids.py` compares three databases row by row (the common base B, the vehicle V, the target T),
moves the ids V minted to the next free numbers of T, replays every V change through the engine, and
reports a change that both V and T made as a conflict. It opens every database read-only; the only
writer is the engine (§11.4.93).

## The landing sequence

1. Land the first vehicle. Its database is the target.
2. In a checkout of the target, with this vehicle's tracked files merged in (evidence directories,
   scripts, docs; not its `docs/workable_items.db`):
   - `refs` to list the files that name a moved id;
   - `plan` against V, B and T with `--repo-root` (so a red or green command that runs a script
     naming a moved id is caught); read every conflict and refusal; decide each conflict with
     `--resolve ID=target` or `--resolve ID=vehicle` and plan again;
   - `rewrite --write --target-db T` the LIVE files `refs` listed;
   - copy the target database, `replay --plan PLAN.json --apply --engine BIN --db COPY` from the
     target repository root;
   - `workable-items validate`, `remint_ids.py verify` (with the same B, V and T), `workable-items
     export`, `verify --require-segments`, `workable-items diff`;
   - put the copy in place of `docs/workable_items.db` only after verify passes.
3. Commit the map file next to the evidence, so a reader can translate the old ids that the captured
   evidence still carries.

When T equals B table for table (nothing landed since the vehicle branched), the plan says
FAST-FORWARD: the vehicle database is the landed database and no replay is needed. `--no-fast-forward`
builds the replay anyway, as a self-test of the tool.

Worked runs on scratch copies, with their diff tables, are in
`docs/qa/tracker_intake_2026_11_12_v4/remint/` (`fix227/`: onto the fix227 round-11 database;
`main/`: onto bare `main`, FAST-FORWARD; `main-replay/`: the same with `--no-fast-forward`); the
results are summarised in `docs/qa/tracker_intake_2026_11_12_v4/README.md`.

## Commands

| Command | Writes | What it does |
|---|---|---|
| `plan --vehicle-db V --base-db B --target-db T --out PLAN.json [--map-out MAP.tsv] [--prefix CON] [--resolve ID=target\|vehicle ...] [--foreign IDS ...] [--repo-root DIR] [--no-fast-forward]` | the plan and the map only | the three-way plan: the sha256 of the three databases, the id map, every base-item change, every conflict, every refusal, the engine steps |
| `replay --plan PLAN.json` | nothing | prints the steps, one JSON argv per line, `{DB}` for the database |
| `replay --plan PLAN.json --apply --engine BIN --db COPY` | COPY, through the engine | refuses a plan with a conflict or a refusal, a COPY whose sha256 is not the plan's target sha256, and a COPY with a non-empty `-wal` sidecar (checkpoint it first); stops at the first failing step and says the copy must be discarded |
| `verify --plan PLAN.json --vehicle-db V --base-db B --target-db T --db R [--require-segments]` | nothing | the separate oracle (below) |
| `rewrite --map MAP.tsv [--write --target-db T] [--foreign IDS] [--own IDS] FILE...` | the files, with `--write` | rewrites moved ids in text files; dry run by default; every file is checked before the first is written |
| `refs --map MAP.tsv --repo-root DIR` | nothing | every tracked text file that names a moved id, with its class: LIVE (rewrite it), EVIDENCE (under `docs/qa/`, never rewritten), DATABASE (never rewritten; the plan replays it) |

`verify` reads only the plan's map and resolutions. It recomputes the own set and the base-item
changes itself and compares every id token of the landed text with its own expectation (item-wide
foreign ids, map, referent title). It checks every replayed column, the untouched target rows, the
history (an Opened row for each own item, a closure or Reopened row for each lifecycle change) and
the tables the plan does not replay. Its control needles run before it reads a database; a needle
that fails is BLIND. Because it shares no code path with the planner's decisions, a planner defect
is not repeated by the check (§11.4.249).

## How a plan is built

- **Own items**: ids in V that are not in B. In ascending order they get max(T)+1, max(T)+2, ...
  A new id that already exists in T, or that is an item of V that is not moved, is refused.
- **Base-item changes**: for an item in B and V, the columns V changed against B. The engine-writable
  groups are replayed with `update`: type, severity, title, description, created_by, assigned_to;
  the reproduction block and the investigation block (with their `updated_by` / `updated_at`);
  status and location through `close` and `reopen` (with the evidence of the vehicle's new closure
  or Reopened history row); the `obsolete_details` row through `obsolete-details`.
- **The `obsolete_details` row** is replayed on every lifecycle path that ends on, or passes
  through, an Obsolete status (close, close then reopen, a changed row on an item left Obsolete),
  because the engine writes it only on an Obsolete item. A row on an item left open is refused.
- **Conflicts**: a column both V and T changed to different values, or a lifecycle change on one side
  with any change on the other, or an item T deleted that V changed. The plan never chooses a side;
  `--resolve ID=target` keeps T, `--resolve ID=vehicle` replays V over T.
- **Refusals** (the plan is written, `replay` refuses it): a column with no replay rule
  (forensic_anchor, closure_criteria, composes_with, destination, logic_group, parent_atm_id,
  session_ref, closure_date, round, commit_ref, representation); a changed table with no rule
  (operator_block_details, firebase_metadata, logic_groups, test_diary, repro_gate_exemptions); a
  base history row V rewrote or deleted; a base item V deleted; only a block's stamp changed; only
  `body_md` changed (the engine renders it from the columns); a non-item doc segment; a base text
  that already names an id V minted later (ambiguous); a lifecycle move with no engine path; a red
  or green command whose script names a moved id (with `--repo-root`).
- **Foreign ids in scripts** (`--repo-root`): an id named by a script is not a moved id when it is
  declared foreign by the item's own `Foreign ids` line, by `plan --foreign`, or, inside the script,
  by a comment line `# Foreign ids (...): ...` (also `//` and `--`). A `Foreign ids` text that is
  not a comment line of the script declares nothing.
- **FAST-FORWARD**: T equals B in every table; no steps.

## Rewrite rules

- A token `P-n` is replaced when it is in the map. One pass: `CON-1 -> CON-2` and `CON-2 -> CON-3`
  turn `CON-1 CON-2` into `CON-2 CON-3`, never `CON-3 CON-3`.
- `CON-12` is not `CON-1`; `CON-1-x` and `xCON-1` are not ids; an id inside a path (`/CON-1/`,
  `CON-1.md`) is refused, not rewritten.
- A line that starts with `Foreign ids` is left alone, and the ids it declares are not rewritten
  anywhere in that file or description. `--foreign` adds ids by hand.
- With `--target-db`, an id the map moves that T also holds is refused as ambiguous unless `--own` or
  `--foreign` declares it.
- A range `P-a..P-b` (also an en dash) is rewritten only when every id in it is moved, none is
  foreign, and the new ids are again ascending and contiguous. A reverse range, a short form
  `P-a..b`, a partly moved or mixed range is refused: the tool never guesses how to split it. Ranges
  are checked by counting, never expanded.
- The word "to" is not a range separator ("moved P-5 to P-7" is not a range).
- `.db`, `.bundle`, binary and non-UTF-8 files are refused.

## Which text files to rewrite

`refs` lists them. Rewrite the LIVE references: scripts and docs that a reader follows. Do not
rewrite captured evidence (run logs, review copies, files listed in a `SHA256SUMS`): its hashes are
cited by items and by reports, and it records what was true when it was captured. The committed map
file is the key to its old ids. The item text is rewritten by the replay, not by `rewrite`.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | done |
| 1 | a refusal, a conflict, a second replay, or a verify mismatch |
| 2 | usage error |
| 3 | BLIND: a database, file or plan cannot be read or does not have the expected shape, a non-UTF-8 file, a failed control needle |

## Tests

- `tests/workable_items/test_remint_ids.sh` (engine: `WORKABLE_ITEMS`, default the tracked
  `scripts/workable-items/bin/workable-items`; 138 cases): the rewrite rules and refusals; `refs`;
  a three-way fixture built through the engine (own items, base items changed by V and by T, a close
  with an `obsolete_details` row, a row rewrite, a reopen after a close) planned, replayed and
  verified; 15 verify needles; FAST-FORWARD and `--no-fast-forward`; conflicts and `--resolve`; 13
  plan refusals, including the script cases; BLIND and usage; the second replay refused; the real
  database untouched. Fixtures that no engine command can produce are made by `fx_sql` on scratch
  copies only; it refuses the real database and stops the run on a failing or empty edit.
- `tests/workable_items/test_remint_ids_mutations.sh`: 53 mutants — the round-3 reviewer's RC1..RC8,
  42 own mutants of the tool (X1..X42) and 3 of the suite's fixture instrument (S1..S3). Each must
  make the suite fail; the unmutated copy must pass.

## Honest boundary

Evidence class gate-logic (§11.4.289): the tests drive the real engine on scratch copies; no landing
onto the live database has been run. Not carried: the vehicle's history rows (the engine writes new
ones on replay; the old rows stay in the vehicle bundle), `created_at` (the replay time for own
items; for a base item it closes, the engine's close rewrites it, engine defect CON-339) and
`last_modified`. `verify` reports these as KNOWN, never as a pass. The engine's own defects reproduce
on replay. A plan is valid only for the target whose sha256 it records; plan once, replay once.
