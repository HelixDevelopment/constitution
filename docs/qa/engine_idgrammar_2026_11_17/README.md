# Evidence: workable-items whole-item round trip (CON-456, round 2), 2026-11-17

| Field | Value |
|---|---|
| Item | CON-456 |
| Round | 2 (structural fix after the round-1 NO-GO review) |
| RED base | round-1 head `d3fa27ac` (engine sha256 `c9884871c111fc4edfd69f9eb371c6ab7ba8fd1252017a36fa00444aa2d283b7`) |
| GREEN | round-2 working tree (engine sha256 `83e93abaeaa5ef09bbb10437595f859bbbf78a03355c4e4204d56cbe79cb9080`, built with go1.26.4) |
| Real tracker | `docs/workable_items.db` of origin main `ebd8818c` (491 items), copies only |
| Evidence class | gate-logic and unit (§11.4.289(C)(2)): host tests and scratch copies of the tracker database; host-only |
| Status | PROVISIONAL (§11.4.290); not independently reviewed (§11.4.142) |

## What round 2 changes

The round-1 review found that the writers judged only the id of an item, so a
title or description the parser reads differently still round-tripped wrongly,
and that `sync md-to-db` wrote Issues before it judged Fixed. Round 2 makes
every command that writes an item (`add`, `update`, `move`, `block`, `reopen`,
`close`, `obsolete-details`, `states import`, `repair-bodies`) render the whole
item as `sync db-to-md` would, read it back through the parser of its tracker,
and refuse (nothing written) unless it reads back as the same one item: exact
id, representation, body bytes, carried fields and state records, with every
embedded operator text present. `add` does this before it opens the database.
`sync md-to-db` judges both documents first and writes both in one
transaction. `sync db-to-md` writes the item's own Type, Severity, Created-By
and Assigned-To lines from the columns.

## Files

- `build_facts_r2.txt`: the build command, the Go version, the sha256 of two
  builds of the round-2 tree (identical) and of the tracked binaries, and the
  `bin/.source.sha256` value with the command that computes it.

Scratch instruments (not part of the shipped engine; run with `python3 -I` or `bash`):

- `class_enum.py`: class enumeration over id shape x title shape x
  description shape x document x operation, each case on its own copy of a
  real tracker database with the real engine binary. Closed verdict set in its
  header. Command used for both tables, with `--bin` the d3fa engine for RED
  and the round-2 engine for GREEN:
  `python3 -I class_enum.py --bin <engine> --control-bin <d3fa engine> --db <db> --out <dir> --valcwd <d3fa tree>`,
  where `<db>` is `docs/workable_items.db` of `d3fa27ac` (486 items, sha256
  `0292c856ff879c58bb7b5640333caa21c6d5f45210c8311e10f067beae3d3e92`), copied
  per case, and `<d3fa tree>` is that commit extracted. The control rows always
  run with the d3fa engine, which is known to lose items.
- `real_tracker.sh`: `validate`, `diff`, `repair-bodies --dry-run`, export,
  two `md-to-db` cycles of the engine's own export, and a column comparison.
  Usage `real_tracker.sh <engine> <extracted tree> <out dir>`.
- `partial_write_planted.sh`: the reviewer's `partial_write.sh` (in the review
  scratch directory, sha256 in `reviewer_scripts_sha256.txt`) plus an SQL
  plant of the G77 three-space heading after the move, so round 2 meets the
  same input that d3fa met.

Class sweep (§11.4.276(C)):

- `class_red_d3fa_table.tsv`, `class_red_d3fa_summary.json`: RED, 489 cases
  on the d3fa engine: 318 `RT_OK`, 120 `RT_FIELD`, 21 `RT_PHANTOM`,
  15 `RT_REPLACED`, 9 `RT_STUCK`, 6 `RT_PARTIAL`.
- `class_green_r2_table.tsv`, `class_green_r2_summary.json`: GREEN, the same
  489 cases on round 2: 331 `RT_OK`, 158 `REFUSED` (database dump unchanged),
  0 of every violation verdict.
- `class_red_d3fa_controls.tsv`: the four control rows (positive
  `RT_REPLACED`, `RT_PHANTOM`, `RT_FIELD`; negative `RT_OK`), each
  `CONTROL-OK`, so the instrument can see each violation class (§11.4.273).
  `class_baseline.json`: the baseline row of the database copy.
- `class_transitions_d3fa_to_r2.txt`: verdict transitions per case.
- `newly_refused_README.txt` with
  `newly_refused_d3fa_heading_raw_body.txt` and
  `newly_refused_d3fa_heading_raw_after_move_Issues_lines_5836_5850.md`:
  why 29 cases the field-only oracle called `RT_OK` on d3fa are refused on
  round 2. They were silent rewrites on d3fa (a description heading line cut
  from the body and left as an orphan section, a user `**Status:**` line
  rewritten by the generator).

Review cases (scripts of the round-1 review, sha256 in `reviewer_scripts_sha256.txt`):

- `reviewer_cases_red_d3fa.tsv`, `reviewer_cases_green_r2.tsv`,
  `reviewer_cases_d3fa_vs_r2.txt`: the reviewer's 38 cases on the same base
  database (486 items). Seven change: `legacy_bracket_title`,
  `legacy_bracket_title2` (F1), `legacy_status_title` (O2),
  `canon_newline_title`, `canon_desc_heading`, `legacy_desc_heading` (O1) are
  refused by `add` before any write; `legacy_leading_space_title` (F3) is
  accepted with the title trimmed and round-trips with the same id and title.
  The column `rt_desc_same` is 0 for every accepted case on both engines: the
  description is re-derived by `md-to-db` (see Limits).
- `partial_write_d3fa_steps.log`, `partial_write_r2_steps.log`: the reviewer's
  partial-write probe (F2). On d3fa `md-to-db` exits 1 after it has committed
  Issues, and CON-001 is lost (486 items, `X=[]`). On round 2 the probe no
  longer reaches the refusal, because `add` trims the title.
- `partial_write_planted_d3fa_steps.log`, `partial_write_planted_r2_steps.log`:
  the same probe with the three-space heading planted by SQL. d3fa loses
  CON-001 (486 items). Round 2 refuses with exit 1 and writes nothing
  (487 items, CON-001 still in Issues).

Real tracker (origin main `ebd8818c`, 491 items):

- `real_tracker_r2_summary.txt`, `real_tracker_d3fa_summary.txt`,
  `real_tracker_r2_all_columns.txt` and `real_tracker_d3fa_all_columns.txt`: `validate` 0, `diff` 0, both `md-to-db` cycles
  keep all 491 items with the same keys, and the second export equals the
  first byte for byte. Round 2 writes the three Severity lines of CON-266,
  CON-267 and CON-268 from their columns
  (`real_tracker_r2_Issues_committed_vs_export1.diff`). On d3fa their bodies
  have no Severity line, so the first `md-to-db` cleared the column from `Low`
  to NULL (`real_tracker_d3fa_summary.txt`, "severity changed db0->db1: 3").

Go tests:

- `red_d3fa_gotest_con456r2.txt`: the round-2 tests run against the d3fa
  source (RED; 28 `--- FAIL` lines, top-level tests and subtests).
- `red_d3fa_four_new_tests.txt`: the four tests added after mutant run 1
  (below) run against the d3fa source: each FAILS for its own cause (the
  severity, the forged reproduction record, the dropped investigation line,
  and `update` accepting the `[ABC-9]` title).
- `green_r2_four_new_tests_first_run.txt`: their first GREEN run on round 2.
  `TestCON456R2_UpdateRefusalNamesTheTitle` failed there because its second
  case was wrong: a status suffix in the title of a canonical id (`CON-997`)
  round-trips, so `update` correctly accepts it. The case now uses a legacy id
  (`G76`), where the suffix is cut by the parser.
- `green_r2_con456_and_grammar_tests.txt`: the top-level verdicts of every
  `TestCON456R2_*` and `TestIDGrammar_*` test on round 2 after that change:
  31 PASS.
- `gotest_r2_summary.txt`, `gotest_r2_run1_verdicts.txt`,
  `gotest_r2_run2_verdicts.txt`: two full `go test -count=1 -json ./...` runs
  in `scripts/workable-items` (go1.26.4), both exit 0, 441 PASS, 6 SKIP and
  0 FAIL top-level (955 PASS including subtests); the sorted verdict lists are
  byte-identical (sha256
  `8b7803a85d5d4936dd1a13e7b2e41a2e8bd045e303e0d4f85501856e8d85b116`). The
  summary lists the printed reason of each pre-existing SKIP.

Probes of defects found while killing mutants:

- `probe_state_and_severity.txt`: on the d3fa engine, `add` accepts a
  description line that reads as a reproduction record and the next
  `md-to-db` turns the reproduction state from `UNSET` into `reproduced-live`
  with no evidence; a severity with a line break is stored and then shortened
  by `md-to-db`; a description line that reads as an investigation record is
  dropped from the stored body. Round 2 refuses all three and writes nothing.
- `probe_subtask_add_unreachable.txt`: `subtask-add` is not a command-line
  verb (the dispatch list of `main.go`, and the engine answers
  `unknown subcommand`), so `subtaskAddCmd` is not reachable and stays
  ungated.

Paired mutants (scratch runners, not committed, sha256 in
`mutant_runner_sha256.txt`; each mutant is one or more exact-count string
replacements in a fresh copy of `scripts/workable-items` without `bin/`,
judged against the full `cmd/workable-items` test package, with the pristine
copy as control: a mutant is KILLED only by a test that passes on the
pristine copy and does not pass on the mutant). Round 2 numbers its mutants
anew: its M18 is not the round-1 M18.

- `mutants_r2_run1.tsv`: 37 mutants on the round-2 tree before the four new
  tests: 29 KILLED, 7 SURVIVED (M05, M09, M10, M12, M15, M17, M18), 1 did not
  compile (M20: `declared and not used: reopenInputs`,
  `mutant_m20_build_error.txt`). The review's RM04 is M01, RM06 is M02,
  and the round-1 M13 is M03; all three are KILLED. The pristine control
  fails 111 tests that look for directories outside `scripts/workable-items`
  (the same set in all three runs).
- `mutants_r2_run2.tsv`: the seven survivors and M20b (M20 rebuilt so it
  compiles), with the four new tests: M09, M10, M12, M17, M18 and M20b
  KILLED; M05 and M15 survive.
- `mutants_r2_run3.tsv`: M38 (the round-1 M18: the id judged in Issues only)
  and M39 (the title judged in Issues only); both survive.

Equivalent mutants, each with its probe (probes, not proofs for every input):

- M05 (body bytes not compared): `m05_equivalence.txt`, from the scratch
  property test `m05_equivalence_test.go.txt` (never part of the package): of
  300 000 random texts parsed by both parsers, every parse that is exactly one
  item segment has a body equal to the whole text (33 619 cases). Its control
  shows a parser that drops trailing blank lines is seen (7 909 mismatches).
  Both parsers copy an item's block verbatim, so the body check cannot fire
  once the one-segment check has passed.
- M15 (the allocated id not judged again): `probe_m15_allocated_id.txt`. The
  allocated id differs from the `<prefix>-001` probe that `add` already
  judged only in its digits; 48 ids (8 prefixes x 6 digit forms, one title and
  description) all get the same verdict, and the control `CON-0-1` is
  refused.
- M38: the review's probe of 96 118 ids found no id on which the two
  parsers disagree, and `checkIDRoundTrips` is unchanged since d3fa.
- M39: `m39_equivalence.txt`, from `m39_equivalence_test.go.txt`: 60 000
  random titles under 8 ids get the same verdict in both trackers
  (33 724 accepted, 26 276 refused, 0 differing).

Limits (not changed by round 2):

- `md-to-db` re-derives the description column from the body: 279 of 491
  real items change on the first cycle, 0 on the second.
- `parent_atm_id`, `destination`, `logic_group` and `session_ref` are not
  carried by the Markdown; the first `md-to-db` clears `parent_atm_id` on 17
  items (the sub-tasks of CON-033), on both engines
  (`real_tracker_*_all_columns.txt`). Filing it as its own item is
  recommended.
- The sub-task child id `ATM-025-001` does not round-trip.
