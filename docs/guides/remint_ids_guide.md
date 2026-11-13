# Re-mint guide — `remint_ids.py` for a vehicle whose ids collide on landing

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13T15:00:00Z |
| Status | active |
| Status summary | User guide and manual for moving the items a vehicle minted to the next free id range of the database it lands on, through the workable-items engine. |
| Authority | Constitution §11.4.54 (ids never renumbered once landed), §11.4.93 (the engine is the only writer of the database), §11.4.288 (landing on `main`) — the canonical text wins where this guide and the constitution disagree. |
| Scope | Universal (§11.4.17); the prefix, the database paths and the file list are consumer DATA (§11.4.35). |
| Issues | not wired into a seam: a lander runs it by hand |
| Issues summary | The vehicle's own `item_history` rows are not carried (see the honest boundary). |
| Fixed | initial creation (tracker-intake round 3, answer to review R2-7) |
| Fixed summary | — |
| Continuation | — |

## Table of contents

- [Why it exists](#why-it-exists)
- [The landing sequence](#the-landing-sequence)
- [Commands](#commands)
- [Which text files to rewrite](#which-text-files-to-rewrite)
- [Exit codes](#exit-codes)
- [Tests](#tests)
- [Honest boundary](#honest-boundary)

## Why it exists

Two vehicles that start from one base both mint ids from the base's maximum. The tracker-intake
vehicle minted CON-299..CON-342; the fix227 vehicle, from the same base, minted CON-300..CON-311.
Whichever lands second collides. An id is renumbered only while it has never landed (§11.4.54 binds
landed ids). The engine has no rename command, and the binary `docs/workable_items.db` cannot be
merged, so the second vehicle is replayed onto the landed database under new ids. `remint_ids.py`
computes the mapping, rewrites the text that names the ids, and drives the engine for the replay. It
opens every database read-only itself; the only writer is the engine (§11.4.93).

## The landing sequence

1. Land the first vehicle. Its database is the target.
2. In a checkout of the target, with this vehicle's tracked files merged in (evidence directories,
   scripts, docs; not its `docs/workable_items.db`):
   - `plan` against this vehicle's database, the common base database and the target database,
     and keep the map file;
   - `rewrite --write` the live files that name own ids (see below);
   - `replay --apply --engine <bin> --db docs/workable_items.db` with the target repository root as
     the working directory;
   - `workable-items validate`, `remint_ids.py verify`, `workable-items export`, `verify
     --require-segments`, `workable-items diff`.
3. Commit the map file next to the evidence, so a reader can translate the old ids that the captured
   evidence still carries.

A worked run on a copy of the fix227 round-11 database is in
`docs/qa/tracker_intake_2026_11_12_v3/remint/demo.txt`.

## Commands

| Command | Writes | What it does |
|---|---|---|
| `plan --vehicle-db V --base-db B --target-db T [--prefix CON] [--out map.tsv]` | the map file only | own ids = ids in V not in B; in order they get max(T)+1, max(T)+2, ... Refuses when a new id is in T, or is an item of V that is not moved. |
| `rewrite --map M [--write] [--foreign IDS] FILE...` | the files, with `--write` | rewrites ids and ranges. Dry run by default. Every file is checked before the first is written. |
| `replay --map M --vehicle-db V` | nothing | prints the engine plan, one JSON argv per line, `{DB}` for the database |
| `replay ... --apply --engine BIN --db TARGET` | TARGET, through the engine | refuses before any step when TARGET already holds a new id; stops at the first failing step and says the copy must be discarded |
| `verify --map M --vehicle-db V --db R [--require-segments]` | nothing | every own item in R under its new id with the rewritten text, the same type, severity, status, location, handles, states, obsolete_details row and an Opened history row |

Rewrite rules:

- A token `P-n` is replaced when it is in the map. One pass: `CON-1 -> CON-2` and `CON-2 -> CON-3`
  turn `CON-1 CON-2` into `CON-2 CON-3`, never `CON-3 CON-3`.
- `CON-12` is not `CON-1`; `CON-1-x` and `xCON-1` are not ids.
- A line that starts with `Foreign ids` is left alone, and the ids it declares are not rewritten
  anywhere in that file or description. `--foreign` adds ids by hand.
- A range `P-a..P-b` is rewritten when every id in it is mapped and the new ids are contiguous. A
  partly mapped range, or one whose new ids are not contiguous, is refused: the tool never guesses
  how to split it.
- `.db`, `.bundle` and binary files are refused.

Replay rules: `add` with the type, severity, title, description, handles and every reproduction and
investigation field (and their `updated_by` / `updated_at`); then `close` (with the evidence of the
last closure history row) for a closed item or an item with an `obsolete_details` row;
`obsolete-details` with the superseding id rewritten; `reopen` with the reason, actor, date and
evidence of the last Reopened history row. Any other status (Operator-blocked, In progress) has no
rule and is refused.

## Which text files to rewrite

Rewrite the live references: the item text (done by the replay), scripts and docs that a reader
follows. Do not rewrite captured evidence (run logs, review copies, files listed in a `SHA256SUMS`):
its hashes are cited by items and by reports, and it records what was true when it was captured. The
committed map file is the key to its old ids. `engine_repro.sh` takes the item ids as arguments since
round 3, so it carries no id to rewrite.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | done |
| 1 | refused (collision, range, binary file, second replay, missing history row) or verify mismatch |
| 2 | usage error |
| 3 | BLIND: a database or a file cannot be read, nothing is own, the target holds no id of the prefix, the map does not parse |

## Tests

- `tests/workable_items/test_remint_ids.sh` (engine: `WORKABLE_ITEMS`, default the tracked
  `scripts/workable-items/bin/workable-items`): rewrite rules and refusals, plan order and collision
  refusal, and a replay through the real engine of a vehicle with a Queued item with states, an
  Obsolete duplicate-of item and a Reopened item onto a colliding target built from a scratch copy
  of `docs/workable_items.db`; verify PASS, validate adds no finding (with a control needle), the
  second replay refused before any write, verify FAIL on a changed description and on missing items.
- `tests/workable_items/test_remint_ids_mutations.sh`: 8 mutants of the tool (range refusals,
  chaining, the Foreign line, the held-id pre-check, the `.db` refusal, the id boundary, the
  collision refusal); each must make the suite fail, and the unmutated copy must pass.

## Honest boundary

Evidence class gate-logic (§11.4.289): the tests drive the real engine on scratch copies; the
landing itself has not been run (main `bd0036bd` is UNCONFIRMED and was not tested). Not carried:
the vehicle's `item_history` rows (the engine writes a fresh history; the old rows stay in the
vehicle bundle), `created_at` (the replay time), and the engine's own defects reproduce on replay
(for example the Opened row's `by` field, CON-336 before re-mint). The map is valid only for the
target it was planned against; plan once, replay once.
