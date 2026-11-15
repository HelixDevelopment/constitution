# Re-mint guide — `remint_ids.py`: land a vehicle's tracker changes, three-way

| Field | Value |
|---|---|
| Revision | 5 |
| Created | 2026-11-13 |
| Last modified | 2026-11-15T17:00:00Z |
| Status | active |
| Status summary | User guide and manual for landing a vehicle's tracker changes onto a target tracker: a three-way plan (base, vehicle, target), ids the vehicle minted moved to the target's next free numbers, every change replayed through the workable-items engine, conflicts reported, never guessed. |
| Authority | Constitution §11.4.54 (ids never renumbered once landed), §11.4.93 (the engine is the only writer of the database), §11.4.249 (the verifier is not the producer), §11.4.288 (landing on `main`) — the canonical text wins where this guide and the constitution disagree. |
| Scope | Universal (§11.4.17); the prefix, the database paths and the file list are consumer DATA (§11.4.35). |
| Issues | not wired into a seam: a lander runs it by hand |
| Issues summary | The vehicle's history rows, `created_at` and `last_modified` are not carried (see the honest boundary); verify reports them as KNOWN. |
| Fixed | revision 5: tracker-intake round 9 (review F2, F3): `--supersede`, `--annotate-foreign`, `--dup-resolution`; XREF-REBOUND and XREF-SUPERSEDED refusals; verify checks the superseded audit copy, the annotations and the landing checks; revision 4: tracker-intake round 6 (review R5-1, R5-2, R5-4, R5-6): an update step passes `--description` only when the vehicle changed it, so a field-only change keeps the target's body; a re-render (a close, or an update with `--description`) over a body the target changed outside the engine slots is a CONFLICT; verify compares body_md (kept text, heading, Status line) instead of a KNOWN line; a path naming an id that does not move is not refused, and a refused plan is still written (mode REFUSED); revision 3: tracker-intake round 5 (review R4-1, R4-2, R4-4, R4-5, R4-9): a merge never rewrites target text and passes only the units the vehicle changed; a state block both sides changed is a conflict; every range form is checked, a chain of tight ranges pair by pair; ASCII digits only; read-only URIs quoted and `-wal` sidecars refused everywhere; an automated branch sweep of the planner and verify, and the defects it found (a value passed as written that names a moved id, an empty block stamp, a reopen kept in Fixed.md); revision 2: tracker-intake round 4 (review findings R3-1, R3-2 and the minors): three-way plan, base-item changes, conflicts, FAST-FORWARD, a separate verify oracle; revision 1: tracker-intake round 3 (review R2-7) |
| Fixed summary | Round 4 merged an item the target also changed by replaying the vehicle's whole state block and its text re-pointed through the map, so a target change was lost or its reference re-pointed at a re-minted item (R4-1). Round 3 replayed only the items the vehicle minted, so a landing lost the vehicle's changes to base items (R3-1) and verify re-ran the producer's own logic (R3-2). |
| Continuation | — |

## Table of contents

- [Why it exists](#why-it-exists)
- [The landing sequence](#the-landing-sequence)
- [Commands](#commands)
- [How a plan is built](#how-a-plan-is-built)
- [Round 9: duplicates and cross-references](#round-9-duplicates-and-cross-references)
- [Rewrite rules](#rewrite-rules)
- [Which text files to rewrite](#which-text-files-to-rewrite)
- [Exit codes](#exit-codes)
- [Tests](#tests)
- [Branch sweep](#branch-sweep)
- [Honest boundary](#honest-boundary)

## Why it exists

Two vehicles that start from one base both mint ids from the base's maximum. The tracker-intake
vehicle minted CON-299..CON-344 (CON-343 and CON-344 in its round 6); the fix227 vehicle, from the same base, minted CON-300..CON-311.
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
`docs/qa/tracker_intake_2026_11_12_v5/remint/` (`fix227/`: onto the fix227 round-11 database;
`main/`: onto bare `main`, FAST-FORWARD; `main-replay/`: the same with `--no-fast-forward`); the
results are summarised in `docs/qa/tracker_intake_2026_11_12_v5/README.md`. Each `target.txt` names
the commit whose database was the target; a plan is bound to that database by its sha256.

## Commands

| Command | Writes | What it does |
|---|---|---|
| `plan --vehicle-db V --base-db B --target-db T --out PLAN.json [--map-out MAP.tsv] [--prefix CON] [--resolve ID=target\|vehicle ...] [--foreign IDS ...] [--repo-root DIR] [--no-fast-forward]` | the plan and the map only | the three-way plan: the sha256 of the three databases, the id map, every base-item change, every conflict, every refusal, the engine steps |
| `replay --plan PLAN.json` | nothing | prints the steps, one JSON argv per line, `{DB}` for the database |
| `replay --plan PLAN.json --apply --engine BIN --db COPY` | COPY, through the engine | refuses a plan with a conflict or a refusal, a plan of another schema (a round-4 plan carried re-pointed target text), and a COPY whose sha256 is not the plan's target sha256; stops at the first failing step and says the copy must be discarded |
| `verify --plan PLAN.json --vehicle-db V --base-db B --target-db T --db R [--require-segments]` | nothing | the separate oracle (below) |
| `rewrite --map MAP.tsv [--write --target-db T] [--foreign IDS] [--own IDS] FILE...` | the files, with `--write` | rewrites moved ids in text files; dry run by default; every file is checked before the first is written |
| `plan ... [--supersede VID=TID ...] [--annotate-foreign TID ...] [--dup-resolution TSV]` | the plan and the map only | round 9: land a vehicle item on a target item that is the same defect; declare the provisional ids a target item names foreign; record the duplicate check of every vehicle and target item pair (see "Round 9: duplicates and cross-references" below) |
| `refs --map MAP.tsv --repo-root DIR` | nothing | every tracked text file that names a moved id, with its class: LIVE (rewrite it), EVIDENCE (under `docs/qa/`, never rewritten), DATABASE (never rewritten; the plan replays it) |

Every subcommand opens its databases read-only with the path URI-quoted (`?` and `#` are file-name
characters, never URI syntax) and refuses, as BLIND, a database with a non-empty `-wal` sidecar:
sqlite would read rows the main file does not hold, so the sha256 the plan records would not describe
the data (checkpoint it first; the engine checkpoints when it closes a database).

`verify` reads only the plan's map and resolutions. It recomputes the own set and the base-item
changes itself and compares every id token of the landed text with its own expectation (item-wide
foreign ids, map, referent title). It checks every replayed column, the untouched target rows, the
history (an Opened row for each own item, a closure or Reopened row for each lifecycle change) and
the tables the plan does not replay. Its control needles run before it reads a database; a needle
that fails is BLIND. Because it shares no code path with the planner's decisions, a planner defect
is not repeated by the check (§11.4.249).

Rules of `verify` that the fifth branch-sweep run of round 5 showed no case had exercised, each now
pinned by a case:

- `doc_segments` is checked only with `--require-segments` (every replayed and own id must have a
  row there; without the flag the table is not read: run the export first, then pass the flag).
- A landing that replayed every target item leaves nothing untouched to compare, so the control
  comparison would see nothing: `verify` exits 3 (BLIND, "no untouched target item to compare").
- An `obsolete_details` row present on one side only names that side ("present in the vehicle only"
  or "present in the landed database only"); no row on either side is nothing to compare.
- History: every landed closure row must cite evidence that a vehicle closure row of the item cites;
  when the vehicle's last lifecycle row is a Reopened row, the last landed Reopened row (never the
  last row of any kind) must match it in author, date, reason and evidence; when it is a closure, the
  landed history must hold a closure row. The vehicle's history rows are not carried (M-14), so when
  the vehicle wrote more closure and Reopened rows than the landing did (an item closed, reopened and
  closed again lands with one closure), `verify` prints a `KNOWN` line with both counts, not a
  mismatch.

## How a plan is built

- **Own items**: ids in V that are not in B. In ascending order they get max(T)+1, max(T)+2, ...
  A new id that already exists in T, or that is an item of V that is not moved, is refused.
- **Base-item changes**: for an item in B and V, the columns V changed against B. The engine-writable
  groups are replayed with `update`: type, severity, title, description, created_by, assigned_to;
  the reproduction block and the investigation block (with their `updated_by` / `updated_at`; an
  empty `updated_at` is passed empty, which the engine stores as NULL, as V has it: round 5, found
  by the branch sweep, where an omitted stamp landed as the time of the replay);
  status and location through `close` and `reopen` (with the evidence of the vehicle's new closure
  or Reopened history row); the `obsolete_details` row through `obsolete-details`.
  Only the columns V changed are passed; `--description` only when V changed the description,
  because `update --description` (and `close`) render `body_md` again from the engine template,
  while a field-only update keeps the body and edits only its engine slots (the heading for
  `--title`, the Status line). Round 6 (R5-1): before, every update passed `--description` and a base
  item's authored body text was lost.
- **Body (round 6, R5-1)**: the engine slots of `body_md` are the heading, the template lines
  (Status, Type, Severity, Created-By, Assigned-To, Evidence), the Reproduction and Investigation
  lines, Reopened-Details and its bullets, and Obsolete-Details. When the plan would re-render an
  item whose body the target changed outside those slots, the item is a CONFLICT (`--resolve
  vehicle` lands the re-render, `--resolve target` keeps the target). verify compares the body: the
  text outside the slots must be kept (exactly, when the target left the item alone), the heading
  must name the landed title and a Status line the landed status.
- **The `obsolete_details` row** is replayed on every lifecycle path that ends on, or passes
  through, an Obsolete status (close, close then reopen, a changed row on an item left Obsolete),
  because the engine writes it only on an Obsolete item. A row on an item left open is refused.
- **Merge per unit** (round 5, R4-1): when V and T both changed one base item, the plan merges it
  unit by unit. A unit is one update column, one state block (the reproduction or investigation
  columns together with their `updated_by` / `updated_at` stamps) or the lifecycle (status, location,
  `obsolete_details`). A unit only V changed is replayed from V (its text through the map); a unit
  only T changed is left as T has it: its text is never run through the map (round 4 re-pointed a
  T reference `CON-305` to the re-minted `CON-318`) and it is never passed to the engine (round 4
  passed V's whole block and overwrote T's change to one column of it). A unit both changed the same
  way is left as T has it. The `MERGE` line names V's units, T's units, and either "disjoint
  columns" or "the same change on both sides: ...".
- **Conflicts**: a unit both V and T changed to different values (for a state block: any column or
  stamp differs), a lifecycle change on one side with any change on the other, or an item T deleted
  that V changed. The plan never chooses a side; `--resolve ID=target` keeps T's whole item,
  `--resolve ID=vehicle` replays V's value for the conflicting units and keeps T's other changes. A
  state block whose content both sides changed to the same values, with other stamps, is refused for
  `=vehicle` (the engine stamps a block only when its content changes, so V's stamps cannot land);
  the refusal names `=target`.
- **Refusals** (the plan is written, `replay` refuses it): a column with no replay rule
  (forensic_anchor, closure_criteria, composes_with, destination, logic_group, parent_atm_id,
  session_ref, closure_date, round, commit_ref, representation); a changed table with no rule
  (operator_block_details, firebase_metadata, logic_groups, test_diary, repro_gate_exemptions); a
  base history row V rewrote or deleted; a base item V deleted; only a block's stamp changed; only
  `body_md` changed (the engine renders it from the columns); a non-item doc segment; a base text
  that already names an id V minted later (ambiguous); a lifecycle move with no engine path; a red
  or green command whose script names a moved id (with `--repo-root`); an item with more than one row
  in V, B or T (the schema allows one row per location and representation; the plan never picks one);
  a base item whose `obsolete_details` row V removed (no engine command removes one, so the replay
  had no step for it and the landing kept the row: round 5, B10, found by the fifth branch-sweep
  run; V can only have done this by a raw edit, and the plan says so).
- **A value passed as written** (round 5, found by the branch sweep): every V value the replay hands to
  the engine without rewriting it (a block's evidence path, state, surface and stamps; a closure's
  evidence; a Reopened row's reason, author, date and incident; the `obsolete_details` fields other
  than `superseding`; a type, severity, author, assignee or status word) is refused when it names an
  id the map moves, whether in a path or not, because nothing rewrites it. An id the item declares
  foreign is kept. Before round 5 an evidence path naming a moved own id passed the plan and only
  verify failed. This refusal, like a rewrite refusal, stops the plan at once (exit 1, a `REFUSED <reason>`
  line). Round 6 (R5-2): only an id the map actually moves is refused (a FAST-FORWARD or an identity map
  refuses nothing), and the refused plan is still written (mode `REFUSED`, its refusals, no steps), so
  the reason is on disk; replay refuses such a plan.
- **Foreign ids in scripts** (`--repo-root`): an id named by a script is not a moved id when it is
  declared foreign by the item's own `Foreign ids` line, by `plan --foreign`, or, inside the script,
  by a comment line `# Foreign ids (...): ...` (also `//` and `--`). A `Foreign ids` text that is
  not a comment line of the script declares nothing.
- **FAST-FORWARD**: T equals B in every table; no steps.

## Round 9: duplicates and cross-references

Round 9 (review F2, F3) found two landing defects the plan did not see: a vehicle item that the target
already held as the same defect was minted again under a new number, and a target item that named a
vehicle's provisional id (written before the vehicle landed) was silently re-bound to the item that
holds that number after the landing.

- **`--supersede VID=TID`** (§11.4.214, recurrence links, never mints): VID is an item the vehicle
  minted and TID an item the target added after the base, the same defect. No row is minted for VID;
  the map sends VID to TID, every reference is rewritten to TID, and the vehicle row is kept in the
  plan (`superseded`) for audit only; its text is not carried. Refused on a FAST-FORWARD landing, for
  a TID the base already held, and for two vehicle ids onto one TID.
- **XREF-REBOUND**: a target item whose text names an id the target does not hold and the landing mints
  for another item is refused, because after the landing the reader would take the reference for the
  new item. **XREF-SUPERSEDED**: the item a `--supersede` lands on names the superseded vehicle id
  (its own provisional id); it is refused the same way. Both refusals name what the id is after the
  landing.
- **`--annotate-foreign TID`** answers either refusal: the landing appends to TID's description the
  line `Foreign ids (provisional ids of an unlanded vehicle, ...): <ids>`, so the ids are declared
  foreign and are never rewritten. An item that already declares the ids foreign needs no annotation;
  annotating an item that names no provisional id, or one the landing also replays a vehicle change
  for, is refused.
- **`--dup-resolution TSV`**: header `vehicle_id<TAB>target_id<TAB>verdict<TAB>reason`, one row per
  pair the intake lint reports as SHARED-PATH between a vehicle item and a target item; verdict
  `DISTINCT`, `DISTINCT-but-similar` or `UNDECIDED` (`SAME-DEFECT` goes through `--supersede`); the
  reason names no id and holds no `;`. The landing appends `Landing check (section 11.4.214) against
  target <sha12>: ...` to the vehicle item's `Duplicate check` line, which the lint reads as naming the
  target item, so the landed tracker passes `--require-dup-check`. An `UNDECIDED` row is an honest
  record that an operator must decide, never a hidden merge.
- **verify** checks, from its own copy of the annotation text: that no superseded id was minted, that
  the audit copy equals the vehicle row, that every annotation names exactly the ids the item names,
  that every landing check is appended and names the target sha, and that no landed item re-binds a
  reference (XREF-REBOUND or XREF-SUPERSEDED in the landed text). A plan whose annotations or landing
  checks differ from the ones verify recomputes is a MISMATCH.

The evidence-pack tool `docs/qa/tracker_intake_2026_11_15_v9/tools/simulate_landing.sh` runs plan,
replay, validate, verify and the intake lint of the LANDED result (the minted items, the supersede
targets and the annotated items, with `--require-dup-check`) against a named commit of `main`.

## Rewrite rules

- A token `P-n` is replaced when it is in the map. One pass: `CON-1 -> CON-2` and `CON-2 -> CON-3`
  turn `CON-1 CON-2` into `CON-2 CON-3`, never `CON-3 CON-3`.
- `CON-12` is not `CON-1`; `CON-1-x` and `xCON-1` are not ids; an id inside a path (`/CON-1/`,
  `CON-1.md`) is refused, not rewritten. A value the replay passes as written is refused when it
  names a moved id anywhere (see "A value passed as written" above).
- A line that starts with `Foreign ids` is left alone, and the ids it declares are not rewritten
  anywhere in that file or description. `--foreign` adds ids by hand.
- With `--target-db`, an id the map moves that T also holds is refused as ambiguous unless `--own` or
  `--foreign` declares it.
- A range `P-a..P-b` (also a tight en dash `P-a–P-b`) is rewritten only when every id in it is
  moved, none is foreign, and the new ids are again ascending and contiguous. A reverse range, a
  short form `P-a..b`, a partly moved or mixed range is refused: the tool never guesses how to split
  it. Ranges are checked by counting, never expanded.
- Every other way of writing two ids as a range obeys the same rules (round 5, R4-4): a spaced en
  or em dash, a tight em dash, `...`, `…`, `~`, a spaced hyphen or double hyphen, the words `to`,
  `through`, `thru`, `till`, `until`, and `between P-a and P-b`. A range that passes is rewritten
  id by id (the contiguous mapping keeps it a range). Two ids joined by a tight hyphen (`P-5-P-6`)
  that hold a moved id are refused: the token rule never rewrites them. A plain `P-a and P-b` is a
  list, not a range. A chain `P-1 to P-2 to P-6` is checked link by link, and so is a chain of
  tight ranges `P-1..P-2..P-3` or `P-1–P-2–P-3` (round 5: found by the branch sweep, which showed the
  second pair of a tight chain was never checked; the chain was rewritten while that pair was partly
  moved).
- Ids are ASCII digits. A moved id written with other digits (fullwidth `CON-５`, Arabic-Indic) is
  refused, never left as is; the plan refuses a new vehicle id written that way. An id split by a
  format character (`CON-29` + U+200B + `9`) is not recognised as the moved id it shows; the intake
  lint reports the character as CONTROL-CHAR (see the honest boundary).
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
  `scripts/workable-items/bin/workable-items`; 402 cases): the rewrite rules and refusals; `refs`;
  a three-way fixture built through the engine (own items, base items changed by V and by T, a close
  with an `obsolete_details` row, a row rewrite, a reopen after a close) planned, replayed and
  verified; 15 verify needles; FAST-FORWARD and `--no-fast-forward`; conflicts and `--resolve`; 13
  plan refusals, including the script cases; BLIND and usage; the second replay refused; the real
  database untouched; round 5 adds the per-unit merge (target text kept verbatim, one block changed on
  both sides, the same change on both sides, disjoint columns of one block, the stamp refusal), every
  range form, the non-ASCII digits, the round-4 plan refused as another schema, the sidecar and URI
  cases, the verify needles of each new rule, and the 92 cases written for branches the sweep found
  untested (the tight chains, the close kind, the last Reopened row, a reopen kept in Fixed, a block
  reset to UNSET, the empty stamp, a value passed as written, two rows for one item, the notes of an
  unchanged item and of a close that rewrote created_at, the next free number among ids of another
  prefix, the order of base changes, a reopen that leaves the obsolete_details row alone, an own item
  in FAST-FORWARD, the own items' history rows), and 66 cases added for the survivors of the
  sweep's fifth run (the shared-item loop of verify, its obsolete_details and history checks, its
  segment check and untouched-item control, the referent check, the plan file a refused plan never
  writes, the removed obsolete_details row), and 19 cases for the survivors of its sixth run
  (FAST-FORWARD verify: a landing with an item the vehicle does not hold, one missing a vehicle item,
  and each of the seven other tables differing on its own, with exactly that one mismatch; a
  created_at MISMATCH without the engine-defect note; `check_od` with no row on either side, the fact behind
  a register entry). Fixtures that no engine command can produce are
  made by `fx_sql` on scratch copies only; it refuses the real database and stops the run on a
  failing or empty edit. `REMINT_IDS` names the tool under test; four in-process cases load that
  file with `importlib.util.spec_from_file_location`, so its name must end in `.py`: a copy named
  `*.py.txt` fails those four cases with a traceback whatever its code does (measured in round 5;
  the RED runs therefore use a `.py` byte copy of each committed `red/*.py.txt`).
- `tests/workable_items/test_remint_ids_mutations.sh`: 152 mutants — the round-3 reviewer's RC1..RC8,
  the round-4 reviewer's RV1..RV7b, 42 round-4 mutants of the tool (X1..X42), 91 round-5 mutants
  (N1..N91; N38..N47 for the defects the branch sweep found, N48..N88 for the survivors of its fifth
  run and the refusal they led to, B10, N89..N91 for three survivors of its sixth run) and 3 of the suite's fixture instrument (S1..S3). Each must make the suite fail; the
  unmutated copy must pass. `REMINT_IDS_MUT_JOBS` sets the parallelism (default 3).
- `tests/workable_items/test_remint_branch_sweep.sh`: the branch sweep's own logic (the inventory,
  every verdict, the register, `--only` and `--only-file`, the unmutated control, the setup exits and
  the span control needle), run on a fake `remint_ids.py` and a stand-in suite; it proves the sweep
  decides correctly, nothing about `remint_ids.py`.
- `tests/workable_items/remint_branch_sweep_mutations.py`: 18 mutants of the sweep itself (SW1..SW18:
  the control removed, the verdict rules, the register, the setup exits, the span needle, the walked
  node kinds and targets), each run against `test_remint_branch_sweep.sh`; each must make that test
  fail, and the unmutated copy must pass first. `--jobs N` sets the parallelism (default 3); it takes
  about 5 minutes.

## Branch sweep

`tests/workable_items/remint_branch_sweep.py` mutates every branch point of the planner, the replay
and the verify oracle automatically (round 5, R4-2: hand-written mutants had left 7 of 8 reviewer
mutants alive). It reads `remint_ids.py` with the `ast` module, lists each `if`, `elif` and `while`
test, conditional expression and comprehension filter in `make_plan`, `block_steps`,
`lifecycle_steps`, the `Rewriter`, `cmd_replay`, `cmd_verify` (with its nested functions),
`v_text_rules`, `v_compare`, `check_od` and `check_history`, and makes two mutants of each: the
condition forced to `True` and to `False` (the exact source span is replaced, so a condition written
twice is never confused; the span is converted from the parser's byte offsets to character offsets
and must parse back to the very condition it came from, or the sweep stops as a setup error). Each
mutant runs the suite with `REMINT_IDS_FAILFAST=1`, so a killed mutant stops at its first failing
case and a survivor runs every case. `--list` prints the inventory; `--only KEY` (repeatable; keys can
hold commas, so they are never split) and `--only-file FILE` (one key per line, first TAB field) run a
subset. Before any mutant runs, the suite runs once on an unmutated copy and must pass (the
`CONTROL:` line); otherwise the sweep stops: a suite that fails on every input would report every
mutant KILLED. A setup error (a missing or unparsable source, a missing suite, a register line
without a TAB and a reason, a span that does not parse back, a failed control) prints `setup: ...`
and exits 2. The sweep's own logic is tested by `tests/workable_items/test_remint_branch_sweep.sh`
(a fake tool and a stand-in suite in a scratch tree).

```
WORKABLE_ITEMS=<engine> python3 -I tests/workable_items/remint_branch_sweep.py --jobs 3 --out sweep.tsv
```

A mutant is KILLED (the suite fails), TIMEOUT (the suite did not finish: an endless loop, counted as
killed), SURVIVED or SETUP. A survivor passes only when the equivalence register
`tests/workable_items/remint_branch_equivalents.tsv` holds its key with a written reason (the
mutant cannot change any output the tool is specified to give); every other survivor fails the
sweep, and so does a register key that no longer names a branch. `while True` loops are listed as
skipped. The sweep takes hours (one suite run per mutant); it is run before a round is handed to
review, not on every change. In `scripts/run_full_suite.sh` the sweep and its mutation harness are
heavy entries, run only with `--include-heavy`; the sweep needs a `--timeout` longer than its run (the
default of 900 seconds stops it).

## Honest boundary

Evidence class gate-logic (§11.4.289): the tests drive the real engine on scratch copies; no landing
onto the live database has been run. The branch sweep proves each branch is decided by a test; it
does not prove the specification complete. An id split by a Unicode format character is not
recognised by `rewrite` (it sees two tokens); the intake lint is the guard for that shape. An engine
defect found in round 5 (owed to the conductor as its own item): a field-only `update --severity`
changes the column but leaves the `**Severity:**` line of `body_md` as it was. Alone it does not make a
landing fail (round 6 passes no `--description` on a field-only change, so the vehicle and the landing
keep the same line); together with a replay order that differs from the vehicle's (the vehicle closed,
reopened, then changed the severity; the replay updates first and closes after, so the close renders the
body again), the two bodies differ in that line, and verify refuses to certify it (the suite pins this as
a characterization case). Not carried: the vehicle's history rows (the engine writes new
ones on replay; the old rows stay in the vehicle bundle), `created_at` (the replay time for own
items; for a base item it closes, the engine's close rewrites it, a known engine defect) and
`last_modified`. `verify` reports these as KNOWN, never as a pass. The engine's own defects reproduce
on replay. A plan is valid only for the target whose sha256 it records; plan once, replay once.
