# Tracker-intake vehicle, round 5: structural fix for the round-4 review

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-14T05:49:39Z |
| Status | active |
| Status summary | Round-5 answer to the round-4 independent review (NO-GO: R4-1 and R4-2 important; R4-3 security-surface minor; R4-4, R4-5, R4-6, R4-8 minor; R4-7, R4-9 nits). A merge passes only the units the vehicle changed and never rewrites target text; a state block or a lifecycle change on both sides is a conflict; every branch of the planner, replay and verify is forced True and False by an automated sweep, and every survivor has a case or a written equivalence. PROVISIONAL: awaits the round-5 independent review. |
| Round | 5, past R_max under the operator decision of 2026-11-11 (section 11.4.276(E)(3)): a structural round with a fresh fixer |
| Base | vehicle head b48091ea (round 4), on main 02c10935. Landing simulated onto fix227 round 11 (fed933c0) and onto bare main (bd0036bd), on scratch copies only |
| Author | round-5 structural fixer, Claude Opus 5.5 (subagent of the conductor); effort not reported by the dispatch path |
| Evidence class | gate-logic only (section 11.4.289): the real workable-items engine on scratch copies and fixture databases; nothing here proves a product defect fixed |
| Issues | the round-5 independent review is owed (section 11.4.142); no landing onto the live tracker has been run; an engine defect found on the way (`update --severity` leaves the body's Severity line) is owed to the conductor and not registered here |
| Continuation | after a GO: land fix227 first, then follow the landing sequence of docs/guides/remint_ids_guide.md (the fix227 simulation below is that sequence on copies) |

## Table of contents

- [What round 5 changes](#what-round-5-changes)
- [Finding by finding](#finding-by-finding)
- [Class inventory](#class-inventory)
- [RED and GREEN](#red-and-green)
- [Mutants](#mutants)
- [Branch sweep](#branch-sweep)
- [Landing simulations](#landing-simulations)
- [Decisions with evidence](#decisions-with-evidence)
- [Checks run](#checks-run)
- [How to re-run](#how-to-re-run)
- [Out of scope](#out-of-scope)
- [UNCONFIRMED and UNKNOWN](#unconfirmed-and-unknown)
- [Files in this directory](#files-in-this-directory)

## What round 5 changes

| Area | Round 4 | Round 5 |
|---|---|---|
| Merge of a base item both sides changed (`scripts/workable-items/remint_ids.py`) | the vehicle's whole state block written over the target's; target text re-pointed through the map | per-unit three-way merge: a column, a state block (its columns and both stamps) or the lifecycle; only a unit the vehicle changed relative to base is passed; target text is never rewritten; the same unit changed on both sides is a conflict unless both landed the same value (a block also needs the same stamps); a lifecycle change on one side and any change on the other is a conflict; `--resolve ID=vehicle` lands the vehicle's conflicting units and the target's own units |
| Values passed as written | not read | every vehicle value the replay hands to the engine without rewriting it (evidence paths, states, stamps, closure evidence, Reopened rows, `obsolete_details` fields, type, severity, authors, assignees, status words) is refused when it names a moved id, unless the item declares that id foreign (found by the branch sweep) |
| Ranges | the dotted and tight en dash forms | every connector (inventory R): the spaced dashes, the other dash code points, ellipses, tildes, worded `to` / `through` / `between ... and`; chains pair by pair, tight chains included |
| Digits | `\d` | `[0-9]` in every reader; an id written in non-ASCII digits is refused or reported |
| `verify` | one comparison for the columns the vehicle did not change | each unit checked against the side it must land from; an unresolved conflict is a mismatch; the unit list must partition the 38 columns or verify is BLIND |
| Intake lint (`scripts/workable-items/intake_lint.py`) | missed unquoted `PASSWORD=`, `Authorization: Basic`, format characters; linted the first row of an item | SECRET for both shapes; CONTROL-CHAR for every Unicode format character (bidi, BOM, soft hyphen, zero-width); every row of an item linted; ASCII digits |
| Database openers | `mode=ro` URIs, path unquoted in some tools | every opener quotes the path; a non-empty `-wal` sidecar is refused (BLIND in the lint) |
| Recorded commands (`engine_repro.sh`, `final_lint.txt`) | the header showed a command that did not run; red commands omitted their preconditions | the header prints each argv as it runs; `engine_repro.sh` checks the prefix, the Types and the Obsolete state it needs and exits 3 otherwise; the six items' records updated through the engine (`apply_v5.py`, `apply_v5.log`) |
| Tests | lint 256 cases, 92 mutants; re-mint 138 cases, 53 mutants | lint 283 cases, 110 mutants; re-mint 402 cases, 152 mutants; a branch sweep of 426 mutants with its own suite |
| Guides | intake lint revision 3, re-mint revision 2 | `docs/guides/intake_lint_guide.md` revision 4, `docs/guides/remint_ids_guide.md` revision 3 |

## Finding by finding

| Finding | Fix | RED | GREEN | Mutants |
|---|---|---|---|---|
| R4-1 a MERGE writes columns the vehicle did not change | per-unit merge (inventory M1..M14); target text never rewritten; block or lifecycle on both sides is a conflict | the review's probes p02 and p03 (`runs/probe_replay.txt`): round 4 re-pointed the target's text and merged a block both sides changed; the round-5 suite on the round-4 tool (`red/remint_suite_on_r4.txt`) | p02 lands the target's text verbatim, p03 is a CONFLICT; suite cases `R4-1a: ...`, `R4-1b: ...` | RV1, RV2, RV7a, RV7b; N1..N13 |
| R4-2 7 of 8 reviewer mutants survive; untested branches | the 8 reviewer mutants adopted; the branch sweep forces every branch of the planner, replay and verify True and False; every survivor has a case or a written equivalence | the reviewer's mutant table (`sources/review_r4_rvmut.tsv`): 7 survivors; the sweep's earlier runs on round-5 states found survivors (46 in the 221 mutants of run 4, 35 in the 420 of the complete run 5, 4 in the 426 of the complete run 6) and ten defects (inventory B: B1..B3, B6..B8 and B10 in the tool, B4 and B5 in the sweep itself, B9 in the suite); the final suite on the tool before the run-5 fixes (`red/remint_suite_on_pre_finalsweep.txt`) | every RV mutant killed; the final sweep ran 426 mutants after its control passed: 418 killed, 8 registered equivalent, 0 survived, 0 timeouts (`runs/branch_sweep.tsv`) | RV1..RV7b; the sweep; N38..N91 |
| R4-3 lint pattern gaps | SECRET for unquoted assignments and `Authorization: Basic`; CONTROL-CHAR for category Cf | `red/lint_suite_on_r4.txt` (the round-5 lint suite on the round-4 lint: 16 cases fail); probe p06 | p06: every shape found; suite cases | LN1..LN6 |
| R4-4 spaced en dash and worded partly-moved ranges | every connector of inventory R read as a range; chains pair by pair | probe p04 (round 4: `replaced=1` for the spaced en dash); `red/remint_suite_on_pre_chainfix.txt` for the tight chain | p04 a..e as wanted; suite cases | N16..N36 (range forms) |
| R4-5 non-ASCII digits | `[0-9]` in every reader; a moved id in non-ASCII digits refused | probes p04g and p08 | refused by name; suite cases | LN7 and the digit N-mutants |
| R4-6 LV4 and LV6 survive; only the first row linted | every row of an item linted; a non-item heading ends the item section | `sources/review_r4_rvmut.tsv` (LV4, LV6 survived); probe p11 | LV1..LV6 all killed | LV1..LV6, LN8..LN10 |
| R4-7 `final_lint.txt` header | each argv printed with `printf %q` before it runs | the round-4 header (a range and a placeholder the script never passed) | `final_lint.txt` | — |
| R4-8 red commands omit preconditions | `engine_repro.sh` checks `HELIX_RELEASE_PREFIX`, the Types and the Obsolete state; the records name them | `red/engine_repro_check_on_v4.txt` (6 of 10 fail) | `red/engine_repro_check_green.txt` (10 of 10); `apply_v5.log` | — |
| R4-9 sidecar and URI hygiene | quoted read-only URIs; a non-empty `-wal` refused everywhere (inventory S) | suite cases: the round-4 lint read past a non-empty `-wal` and read a path with `?` and `#` as URI syntax (`red/lint_suite_on_r4.txt`); the round-4 re-mint read a path holding `?` and `#` as URI syntax, and its `plan` and `verify` read past a non-empty `-wal` (only `replay` refused one) (`red/remint_suite_on_r4.txt`) | suite cases in both suites | LN11, LN12 and the -wal and URI N-mutants |

## Class inventory

`class_inventory.md` enumerates, before the fix was written (section 11.4.276(C)), the classes behind
each finding: merge units (M), range forms (R), id readers (D), lint surfaces (L), database openers
(S), recorded commands (E), test coverage (T), and, added after the branch sweep, the values the replay
passes as written (K) and the defects the sweep found (B).

## RED and GREEN

Every RED below is the final round-5 suite (or check) run on code from before the fix; every GREEN is
the same suite on the final tree. The engine is `scripts/workable-items/bin/workable-items` (sha256 in
`runs/inputs.sha256`); every run used fixture databases and scratch copies only.

| Run | Code under test | Result | Record |
|---|---|---|---|
| RED: re-mint suite on the round-4 tool | `git show b48091ea:scripts/workable-items/remint_ids.py` | pass 325, fail 77 | `red/remint_suite_on_r4.txt` |
| RED: re-mint suite with the chain fix taken out (B1) | `red/remint_ids_pre_chainfix.py.txt` (the final tool with the two removed lines put back) | pass 399, fail 3 (the three range-chain cases) | `red/remint_suite_on_pre_chainfix.txt` |
| RED: re-mint suite before `keep` and the always-passed stamp (B2, B3) | `red/remint_ids_pre_keep.py.txt` (a historical copy of the round-5 work tree) | pass 383, fail 19 (the nine refusals of a value passed as written that names a moved id and the plan file one of them then writes, the two empty-stamp cases, and the seven cases of B6, B7, B8 and B10, which this copy predates too) | `red/remint_suite_on_pre_keep.txt` |
| RED: re-mint suite before the fixes the fifth branch-sweep run led to (B6, B7, B8, B10) | `red/remint_ids_pre_finalsweep.py.txt` (the round-5 work tree that sweep run 5 ran on) | pass 395, fail 7 (B6: the two moved ranges in a path; B7: verify of a plan the planner refused; B8: the two cases of a new id outside the prefix; B10: the two removed `obsolete_details` rows) | `red/remint_suite_on_pre_finalsweep.txt` |
| RED: lint suite on the round-4 lint (R4-3, R4-5, R4-6, R4-9) | `git show b48091ea:scripts/workable-items/intake_lint.py` | pass 267, fail 16 | `red/lint_suite_on_r4.txt` |
| RED: `engine_repro_check.sh` on the round-4 script and capture (R4-8) | `docs/qa/tracker_intake_2026_11_12_v4/engine_repro.sh` and its `engine_repro.txt` | pass 4, fail 6 | `red/engine_repro_check_on_v4.txt` |
| RED: the branch sweep's own suite on the sweep before its control and setup exits (B4) | `red/remint_branch_sweep_pre_fix.py.txt` | pass 35, fail 7 | `red/branch_sweep_suite_on_pre_fix.txt` |
| RED: the reviewer's probes on round 4 | the round-4 tool | p02 re-pointed the target text, p03 merged a block both sides changed, p04 rewrote a spaced en dash range (`replaced=1`), p12 lost the lifecycle conflict (RV7a) | `sources/review_tracker_intake_r4.md` |
| GREEN: re-mint suite | `scripts/workable-items/remint_ids.py` | pass 402, fail 0 | `runs/remint_suite.txt` |
| GREEN: lint suite | `scripts/workable-items/intake_lint.py` | pass 283, fail 0 | `runs/lint_suite.txt` |
| GREEN: the branch sweep's own suite | `tests/workable_items/remint_branch_sweep.py` | pass 42, fail 0 | `runs/branch_sweep_suite.txt` |
| GREEN: `engine_repro_check.sh` | `engine_repro.sh` and the committed `engine_repro.txt` | pass 10, fail 0 | `engine_repro_check.txt` (and `red/engine_repro_check_green.txt`) |
| GREEN: the reviewer's probes p02, p03, p04, p06, p08, p11, p12 replayed on the final tree | the final tool and lint | 7 answered, 0 open; a re-run on the final tree gave a byte-identical record | `runs/probe_replay.txt` |

The other probes of the round-4 review are answered by other records: p00 (head integrity) by
`remint/*/validate.txt` and `remint/*/facts.txt`; p07 (referential integrity) by `runs/ref_integrity.txt`
(the probe's checks as a tool with control needles, run on the base, the vehicle, both targets and the
three landed copies: all CLEAN); p01 (lint of the head) by `final_lint.txt`; p05 (leak scan) by
`runs/leak_scan.txt`; p09 (the survivors' evidence) by the RV mutants; p10 (the engine_repro re-run)
by `engine_repro_check.txt`.

Both suites and the sweep's own suite ran twice on the final tree; each pair of outputs is
byte-identical (`runs/*.txt` show run 1 and say so in their first line).

The suite's in-process cases (the needle and column checks of `verify`, the `v_split` fact, the text
rules) load the tool with `importlib.util.spec_from_file_location`, which has no loader for a file name
ending in `.txt`. The first RED runs of the three committed copies (`red/*.py.txt`) therefore failed
those four cases with a traceback whatever the code did: false failures of the instrument, not RED.
The RED runs were repeated from a byte copy of each committed file named `*.py` (the record's header
gives its sha256, equal to the committed file's), and the RED counts above are from those runs.

## Mutants

Each mutant is one exact text replacement in a copy of the tool or of the suite; a replacement that
does not occur exactly once is a stale mutant and fails the run. A mutant is killed when the suite
fails on it; for a lint mutant declared `yes`, the lint's built-in control needles must also stop it.

| Harness | Mutants | In round 4 | Added in round 5 | Result on the final tree | Record |
|---|---|---|---|---|---|
| `tests/workable_items/test_intake_lint_mutations.sh` | 110 | 92 | LV1..LV6 (the round-4 reviewer's lint mutants, verbatim or mapped), LN1..LN12 (12 own: the unquoted assignment and `Authorization: Basic` SECRET shapes, the reference-value exemption, CONTROL-CHAR for format characters, every row of an item, ASCII digits, the `-wal` refusal and the quoted URI); M1 mapped onto the round-5 code | all 110 killed as declared (`RESULT: mutants=110 all killed as declared`, rc 0) | `runs/lint_mutations.txt` |
| `tests/workable_items/test_remint_ids_mutations.sh` | 152 | 53 | RV1..RV7b (8, the round-4 reviewer's), N1..N91 (own; N38..N47 for the defects the branch sweep found, N48..N88 for the survivors of its fifth run and the refusal they led to, B10, N89..N91 for three survivors of its sixth run); RC5, RC6, X2, X9, X39 and X41 mapped onto the round-5 code | all 152 killed after the control passed (`RESULT: mutants=152 all killed`, rc 0) | `runs/remint_mutations.txt` |
| `tests/workable_items/remint_branch_sweep_mutations.py` | 18 | — | the sweep's own mutation driver (new) | all 18 killed after the control passed (`RESULT: mutants=18 killed=18 survived=0 PASS`, rc 0) | `runs/branch_sweep_mutations.txt` |
| `tools/ref_integrity_mutations.py` | 12 | — | the referential census (new, the round-4 probe p07) | 11 killed by its control needles; 1 KNOWN (the integrity_check verdict has no corrupt fixture) | `runs/ref_integrity.txt` |
| `tests/workable_items/remint_branch_sweep.py` | 426 | — | every branch point of the planner, replay and verify, forced True and False | see "Branch sweep" | `runs/branch_sweep.tsv` |

The 14 reviewer mutants of the round-4 review (RV1..RV7b, LV1..LV6) are all in the harnesses and all
killed. Round 5 adds 103 own mutants to the two harnesses (N1..N91 and LN1..LN12), beside the sweep's
generated ones.

## Branch sweep

`tests/workable_items/remint_branch_sweep.py` lists every branch point of the planner, replay and
`verify` (213 branch points, 426 mutants; the two `while True` loops are listed as skipped) and runs the remint suite on each mutant (the condition forced True, then
False), after a control run of the unmutated source. A survivor fails the sweep unless the
equivalence register holds its key with a written reason.

| Run | Source | Mutants run | Killed | Timeout | Setup | Survived | Registered equivalent | Record |
|---|---|---|---|---|---|---|---|---|
| 1, stopped part-way | the round-5 work tree of that time; inputs not recorded | 49 | 38 | 0 | 2 | 9 | 0 | `runs/branch_sweep_partial_bytebug.txt` |
| 2, `--only` re-run of run 1's survivors | inputs not recorded | 9 | 8 | 0 | 0 | 0 | 1 | `runs/branch_sweep_only_rerun.txt` |
| 3, stopped part-way | the work tree before the chain fix; inputs not recorded | 53 | 49 | 0 | 0 | 3 | 1 | `runs/branch_sweep_partial_prechainfix.txt` |
| 4, stopped part-way | the source before `keep` (`red/remint_ids_pre_keep.py.txt`); inputs recorded | 221 of 422 | 174 | 0 | 0 | 46 | 1 | `runs/branch_sweep_prekeep_partial.txt` |
| 5, complete | the source before B6..B8 and B10 (`red/remint_ids_pre_finalsweep.py.txt`); inputs recorded | 420 | 380 | 0 | 0 | 35 | 5 | `runs/branch_sweep_run5.txt` |
| 6, complete | the final source; the suite and the register before the 19 cases and the register entry for its survivors; inputs recorded | 426 | 415 | 0 | 0 | 4 | 7 | `runs/branch_sweep_run6.txt` |
| final | the final source, suite and register; inputs recorded in the record's header | 426 | 418 | 0 | 0 | 0 | 8 | `runs/branch_sweep.tsv` |

What the survivors and setup verdicts of the earlier runs became:

| Run | Verdicts | Became |
|---|---|---|
| 1 | 2 SETUP (a condition after a non-ASCII character did not compile) | the sweep's own defect B5: offsets converted to characters, and the span control needle |
| 1 | 9 survived | cases for 8 (killed in run 2); 1 registered equivalent (`Rewriter\|if\|not text#1=False`) |
| 3 | 3 survived | 1 the skip of tight pairs in `Rewriter._checks`, defect B1 (the branch was removed by the fix); 2 `lifecycle_steps` branches, survivors again in run 4 and killed in the final run |
| 4 | 46 survived | 39 killed by cases written for them; 3 registered as they were (`lifecycle_steps\|ifexp\|cl#1=True`, `lifecycle_steps\|if\|word not in CLOSE_STATUS#1=False`, `make_plan\|if\|new in T#1=False`); 2 registered under the keys the restructure gave them (`make_plan\|if\|kv["created_by"]#1=True`, `make_plan\|if\|kv["assigned_to"]#1=True`); 2 branches removed by the restructure |
| 5 | 35 survived | 34 killed by cases written for them (the cases for some of them showed defects B6..B8, and those for `check_od` showed B10; each was fixed); 1 registered equivalent (`v_compare\|if\|len(tk_w) != len(tk_g)#1=False`) |
| 6 | 4 survived | 3 killed by the 19 cases written for them (FAST-FORWARD verify's id-set check and its table check, the CON-339 note on a created_at MISMATCH; mutants N89..N91); 1 registered equivalent (`cmd_verify\|if\|OV.get(old) is not None or OR.get(new) is not None#1=True`, its fact checked by a suite case on every run). Run 5 had counted all four KILLED, each only through the suite's flaky engine-fact case (B9) |
| final | 418 killed, 8 registered equivalent, none survived | nothing left to triage |

The register (`tests/workable_items/remint_branch_equivalents.tsv`) holds 8 entries; each
line's reason is checked by a reader, the two that rest on an engine fact are checked by a suite
case on every run, and so are the two that rest on a fact of the tool itself (`v_split`, `check_od`). The sweep's own suite (`tests/workable_items/test_remint_branch_sweep.sh`, a fake
tool and a stand-in suite) and its mutation driver (`tests/workable_items/remint_branch_sweep_mutations.py`)
ran with these results: the suite passed 42 of 42, run twice with byte-identical output (`runs/branch_sweep_suite.txt`); on the sweep before its fix it failed 7 of 42 (`red/branch_sweep_suite_on_pre_fix.txt`); the driver killed all 18 mutants SW1..SW18 after its control passed (`runs/branch_sweep_mutations.txt`).

## Landing simulations

`make_evidence.sh` ran on the final tree, every database a scratch copy (`remint/<name>/`). The base
is 02c10935; the vehicle is the working-tree `docs/workable_items.db`.

| Target | Plan | Replay | `verify` | Engine `validate` | Landing facts | Referential census |
|---|---|---|---|---|---|---|
| fix227 round 11 (fed933c0, 275 items) | REPLAY, own 44 re-minted CON-299..CON-342 → CON-312..CON-355, 3 base changes, 68 steps, 0 conflicts, 0 refusals | APPLIED, 68 steps, 44 items | PASS, 47 items, 0 mismatches, 46 KNOWN (45 `created_at`, 1 lifecycle history rows) | OK, 319 items | 5 of 5 hold | CLEAN |
| main (bd0036bd) | FAST-FORWARD, own 44 keep CON-299..CON-342, 3 base changes, 0 steps | (the landed copy is the vehicle) | PASS, 307 items, 0 mismatches, 0 KNOWN | OK, 307 items | 5 of 5 hold | CLEAN |
| main, replay forced (`:no-ff`) | REPLAY, own 44 at CON-299..CON-342, 3 base changes, 68 steps, 0 conflicts | APPLIED, 68 steps, 44 items | PASS, 47 items, 0 mismatches, 46 KNOWN (as for fix227) | OK, 307 items | 5 of 5 hold | CLEAN |

The three base changes (CON-046, CON-243, CON-262) are vehicle-only on both targets (`target=-`), so
neither landing exercises a MERGE; the merge rules of R4-1 are exercised by the suite and by the
reviewer's probes p02 and p03 (`runs/probe_replay.txt`). The KNOWN `created_at` lines are the replay
time of a new item (the engine has no command that sets `created_at`) and CON-243's close (engine
defect CON-339); the one lifecycle KNOWN is the history rows of the item the vehicle numbered CON-308 (CON-321
after the fix227 re-mint, CON-308 in the forced replay onto main), which the replay does not carry
(M-14 of round 3). `tdiff3.md` in each directory is the full-table diff B/V/T/L, and
`runs/ref_integrity.txt` the census of the round-4 probe p07 over the base, the vehicle, both
targets and the three landed copies (rebuilt from the committed plans).

## Decisions with evidence

- **A merge passes only the units the vehicle changed.** The conductor's design for R4-1: never
  rewrite target text; pass a unit only when the vehicle changed it relative to base; the same unit
  changed on both sides is a conflict unless both landed the same value (after the map); anything not
  provably independent is a conflict or a refusal. A unit is a column, a state block (its columns
  and both stamps) or the lifecycle (status, location, `obsolete_details`). `verify` checks each unit
  against the side it must land from (inventory M1..M14).
- **A lifecycle change on one side and any change on the other is a conflict, even when the
  `obsolete_details` rows are equal** (M10, M11). The engine has no command that moves an item's
  lifecycle while keeping a target's change on another unit in a provable order, so equal rows do
  not make the two changes independent. Revision 1 of the inventory said "converged when equal";
  the branch sweep's case x33 pins the conflict and revision 2 corrects the row.
- **`--resolve ID=vehicle` of a block both sides changed to the same content with other stamps is
  refused.** Replaying the same content changes nothing and the engine stamps a block only when its
  content changes, so the vehicle's stamps cannot land; `--resolve ID=target` lands it.
- **A value passed as written that names a moved id is refused, in a path or not** (inventory K,
  defect B2). Nothing rewrites such a value, so a moved id in it would land pointing at another item.
  An id the item declares foreign is kept. A status word is in the class but unreachable: the engine
  accepts only its status vocabulary (honest gap K6).
- **An empty block time stamp is passed empty** (defect B3). The engine stores `--states-updated-at=`
  as NULL, as the vehicle has it; before round 5 an omitted stamp landed as the time of the replay.
- **A vehicle that removed a base item's `obsolete_details` row is refused** (defect B10). No engine
  command removes such a row, so the replay had no step for the removal and the landing kept the
  row; only `verify` noticed. A vehicle can reach that state only by a raw edit, so the plan refuses
  it with the reason, never guesses a step. Found while writing cases for `check_od`'s survivors of
  sweep run 5.
- **Eight equivalent branch mutants, with their reasons in `tests/workable_items/remint_branch_equivalents.tsv`.**
  Six are proofs from the code (a guard no input reaches; for `v_compare`'s length test, the
  skeleton comparison before it already implies equal lengths; for `verify`'s guard before
  `check_od`, `check_od` returns at once when neither side has a row; a suite case checks each of
  these two facts of the tool on every run). Two (`kv["created_by"]` and
  `kv["assigned_to"]` forced True) rest on an engine fact: `add --created-by=` and `--assigned-to=`
  with an empty value store the same item, history row and segment as omitting them, because both
  flags default to `''`. The remint suite checks that fact on every run (case "engine fact: an empty
  --created-by= and --assigned-to= equal omitting them"), so an engine change would turn the
  register entry into a failing case, never into a silent pass.
- **FAST-FORWARD: an own item is not replayed, so a column `add` cannot carry is not refused.** The
  vehicle database is the landed database. The refusals that guard a base item (a column with no
  replay rule, another table, a non-item segment, a rewritten history row) still apply in
  FAST-FORWARD although the copy would carry those changes; this is conservative and unchanged this
  round (listed under UNCONFIRMED).
- **CON-339, `created_at`.** Unchanged from round 4: the engine's `close` rewrites `created_at`, no
  engine command sets it, so the plan prints a NOTE for the item whose close rewrote it and `verify`
  reports it as KNOWN, never as a pass. Round 5 adds a case that the NOTE is printed for that item
  only (the branch sweep found the NOTE untested).
- **The engine's `update --severity` leaves the body's `**Severity:**` line.** Found while writing
  the M-cases; not a defect of this vehicle. The suite pins it as a characterization case
  (`verify FAIL: the engine's stale Severity line in the vehicle body is not certified`): such a
  landing is refused, never certified. Owed to the conductor for registration; not registered here.
- **The sweep ran first on earlier states of the source.** Six earlier runs are kept (see "Branch
  sweep"); the first three did not record their inputs, so they show what was found, not on which
  source. They found the survivors that led to defects B1..B3 and B5 and to the cases; the run on
  the source before `keep` was stopped after 221 of its 422 mutants (174 killed, 46 survived, 1
  registered equivalent) once the source and the suite had changed, and its output is kept
  (`runs/branch_sweep_prekeep_partial.txt`; its inputs' sha256 in the same file's header). Run 5 was
  complete (420 mutants: 380 killed, 35 survived, 5 registered equivalent; `runs/branch_sweep_run5.txt`,
  inputs recorded); its survivors led to B6..B8 and B10, to cases and to one register entry. Run 6 was complete on
  the final source, with the suite and the register before its survivors' cases and entry (426 mutants: 415 killed, 4 survived, 7 registered equivalent;
  `runs/branch_sweep_run6.txt`, inputs recorded); its four survivors were mutants run 5 had counted
  killed only through the suite's flaky engine-fact case (B9), and they led to 19 cases and one
  register entry. The final sweep ran on the final source and the final suite, with the sha256 of its inputs recorded.

## Checks run

| Check | Command (record) | Result |
|---|---|---|
| Shell lint | `shellcheck -S warning` on the eight shell files of this change (`runs/checks.txt`) | rc 0 at `-S warning`; at every level the eight files give info and style notes only (SC1091 5, SC2015 41, SC2016 9, SC2018 1, SC2019 1, SC2329 1) |
| Python types | `pyright` on the Python files of this change (`runs/checks.txt`) | 0 errors, 0 warnings, 0 informations |
| Suite manifest | `scripts/run_full_suite.sh --sync-guide`, then `--verify-manifest` (`runs/checks.txt`) | the guide census was already in sync (no diff); `RESULT: MANIFEST-OK` (the two new `tools/*_mutations.py` entries have manifest rows, tier `heavy`) |
| Gate ledger | `scripts/gates/cm_gate_ledger_ratchet.sh` (`runs/checks.txt`) | PASS: `LEDGER: unimplemented=394 baseline=394 fails=0` (no gate name added or removed) |
| Whitespace | `git diff --cached --check` against round 4, outside this directory's captured records (`runs/checks.txt`) | rc 0. The captured records of this directory keep the trailing blanks of the output they captured; the record counts the flagged lines per file |
| Secrets and identity | `tools/leak_scan.py` on the staged diff and on the vehicle database against round 4 and against the base, on the base alone, with its mutation check (`runs/leak_scan.txt`) | control needles PASS before every scan; rc 0 everywhere. The staged diff: 9 secret-shaped hits and 0 identity hits; 7 are the word `SECRET` followed by a colon in mutant descriptions (`runs/lint_mutations.txt` x4, `sources/review_r4_rvmut.tsv`, `tests/workable_items/test_intake_lint_mutations.sh` x2), not values; 2 are the `url-cred` shape of one vehicle item, copied into the two REPLAY plans (see UNCONFIRMED). The vehicle database: 0 new hits against round 4 (156 pre-existing), 2 new `url-cred` hits against the base (the same item; 154 pre-existing, all identity hits of the base itself: 38 home paths, 38 home-path fragments, 78 user-name hits). Mutation check: 13 mutants, 0 bad |
| Intake lint | `final_lint.txt` | the 44 vehicle items: PASS, 0 findings; the three base items the vehicle changed (CON-046, CON-243, CON-262), intake-format codes skipped: PASS, 0 findings |

The three base items with no skip list give 42 findings on the vehicle and 36 on the base
(`final_lint.txt`). The vehicle adds 11: eight PATH-MISSING on CON-046, whose restored description
names `docs/qa/con046_review/...` paths that no commit of this clone holds, and three SHARED-PATH on
CON-262, whose `run_all.sh` is also named by the vehicle's open items CON-299, CON-339 and CON-340.
It removes 5 the base shows: two BODY-SYNC (CON-046, CON-243), two EPHEMERAL on CON-243 and CON-046's
missing "Affected scope" section.

## How to re-run

From the repository root, with the engine binary `WI=scripts/workable-items/bin/workable-items`:

```
bash tests/workable_items/test_intake_lint.sh
bash tests/workable_items/test_remint_ids.sh
bash tests/workable_items/test_intake_lint_mutations.sh
bash tests/workable_items/test_remint_ids_mutations.sh
bash tests/workable_items/test_remint_branch_sweep.sh
python3 -I tests/workable_items/remint_branch_sweep.py --jobs 3 --out sweep.tsv
bash docs/qa/tracker_intake_2026_11_12_v5/make_evidence.sh "$WI" 02c10935 fix227=fed933c0 main=bd0036bd main-replay=bd0036bd:no-ff
```

The RED runs use earlier code from git or from `red/`: `git show b48091ea:scripts/workable-items/remint_ids.py`
(set `REMINT_IDS=` to it), `git show b48091ea:scripts/workable-items/intake_lint.py` (set
`INTAKE_LINT=` to it), and the three RED copies kept in `red/` (`remint_ids_pre_chainfix.py.txt`,
`remint_ids_pre_keep.py.txt`, `remint_ids_pre_finalsweep.py.txt`). `fed933c0` and `bd0036bd` must be present in the clone.

## Out of scope

- No landing onto the live tracker: the fix227 vehicle has not landed, and a landing needs the GO.
- The HTML, PDF and DOCX exports are not scanned.
- The engine defects the landing exposes are not fixed here: CON-339 (`close` rewrites `created_at`),
  the others the batch records, and the `update --severity` body defect found this round (owed to the
  conductor for registration).
- A range written across a line break, an open-ended form ("up to P-n") and a connector outside the
  read set are not read as ranges (inventory R, with a live scan of the tracked files and databases).

## UNCONFIRMED and UNKNOWN

- UNCONFIRMED: that the per-unit merge is complete for every state a real tracker can reach. The
  units are the 38 `items` columns partitioned by `verify` (BLIND if a column is not in a unit),
  plus `obsolete_details` and the history rows; a column added to the schema later makes `verify`
  BLIND until a unit is named for it. No landing onto the live tracker was run.
- UNCONFIRMED: that the branch sweep reaches every decision. It forces each `if`, `elif`, `while`,
  conditional expression and comprehension filter of the planner, replay and `verify` True and
  False (two `while True` loops are skipped by design); it does not mutate the boolean operators
  inside a condition one by one, the arithmetic, the string literals or the regular expressions, and
  it does not reach `Rewriter` paths that only the `rewrite` subcommand drives except through the
  suite cases that call it.
- UNCONFIRMED: the equivalence of the two register entries that rest on the engine's flag defaults
  holds only for the engine binary the suite runs; the suite's engine-fact case checks it on each run.
- A KILLED verdict of the sweep is the first failing case of a fail-fast suite run; the sweep does
  not re-run a mutant to confirm that the case fails for the mutant and not for another reason. Sweep
  run 5 counted seven mutants KILLED through the suite's flaky engine-fact case alone (B9); with that
  case fixed, run 6 found four of them surviving. The final suite ran twice with byte-identical
  output, but no case was checked for flakiness beyond those two runs and the sweep's own control.
- UNKNOWN: whether FAST-FORWARD should also skip the refusals that guard a base item's change (a
  column with no replay rule, another table, a non-item segment, a rewritten history row). The copy
  would carry those changes, so the refusals are conservative there; behaviour unchanged this round,
  pinned only for own items (case "plan: FAST-FORWARD of a vehicle whose own item holds a column add
  cannot carry").
- UNKNOWN: whether the engine's `update --severity` body defect has other siblings among the update
  flags (only `--severity` was measured: the column changes, the `**Severity:**` line of `body_md`
  does not). Owed to the conductor for registration.
- UNCONFIRMED: the HTML, PDF and DOCX exports were not scanned by the intake lint (unchanged from
  round 4).
- The review effort of this round's fixer is not reported by the dispatch path (section
  11.4.231(F.2)); the model is Claude Opus 5.5.
- UNCONFIRMED: where the `docs/qa/con046_review/...` files named by CON-046's restored description
  live. No commit of this clone holds them (the eight PATH-MISSING findings of `final_lint.txt`); the
  description is the base's, restored, not text this round wrote.
- The base tracker database already holds 154 identity strings (home-directory paths and
  the user name) in item text; `runs/leak_scan.txt` counts them as pre-existing and reports only what
  the vehicle adds. Removing them is owed to the conductor, not done here.
- UNCONFIRMED: that the referential census (`tools/ref_integrity.py`) reports a corrupt database. Its
  `integrity_check` verdict has no corrupt fixture; the mutation check records that mutant as KNOWN.
- The leak scan's mutation check does not mutate the call of its control needles away: on a correct
  scan that changes no output, so it is visible only together with a second defect.
- UNCONFIRMED: whether the `url-cred` hit the leak scan reports in one vehicle item (a `https:` URL
  of the `user:password@` shape in the item's description and body, and the same text in the two
  REPLAY plans) is a real credential. The match is 12 characters long; with `https://` that leaves
  a one-character user and a one-character password, which suggests a placeholder but is not proof. Its parts were not read: a safety classifier
  stopped that read, and it was not retried. The scan prints no matched text. Owed to the conductor:
  read the item and decide whether the value is a placeholder or must be removed.
- The removed `obsolete_details` row of defect B10 is reachable only by a raw edit of the vehicle
  database (no engine command removes the row); the suite builds it with `fx_sql` on a scratch copy.
  A plan with that refusal stripped by hand still fails `verify` (the vehicle's closure row of the
  item has no step), which the suite pins; the refusal is the guard, not the only one.
- The final suite was run in full for the first time after the copy into the work tree; that run
  stopped at a case of the draft that asked the engine to write an `obsolete_details` row on a
  Reopened item (the engine refuses: exit 2). The case now edits the item the vehicle left Obsolete.
  The earlier runs of the new cases used a smaller suite built from the setup and those cases.
- The first RED runs of the three committed copies (`red/*.py.txt`) failed four in-process cases with
  a traceback that came from the file name, not from the code: the suite loads the tool with
  `importlib.util.spec_from_file_location`, which has no loader for a name ending in `.txt`. The RED
  runs were repeated from `.py` byte copies (see "RED and GREEN"). The suite still needs a tool path
  ending in `.py` and gives no message of its own for another name; an explicit loader is owed (not
  changed this round, because the suite is an input of the final branch sweep).

## Files in this directory

| Path | What it is |
|---|---|
| `README.md` | this record |
| `SHA256SUMS` | sha256 of every other file in this directory |
| `class_inventory.md` | the class enumeration (section 11.4.276(C)) behind every finding, with the sections K and B added after the branch sweep |
| `apply_v5.py`, `apply_v5.log` | the one-shot engine-only update of the six items' Reproduction lines (R4-8) and its log |
| `engine_repro.sh`, `engine_repro.txt` | the engine reproduction of the defects the vehicle files, with its preconditions checked (R4-8) |
| `engine_repro_check.sh`, `engine_repro_check.txt` | the tests of `engine_repro.sh`: each missing precondition is refused, the full run reproduces |
| `final_lint.txt` | the intake lint on the vehicle's items, the header printing each argv as it runs (R4-7) |
| `decision_record_facts.txt` | facts read from the databases for the decisions below |
| `make_evidence.sh` | regenerates `remint/`, `final_lint.txt` and `engine_repro*.txt` from the current tree |
| `remint/<name>/` | one landing simulation each (`fix227`, `main`, `main-replay`): plan (`plan.txt`, `plan.json`, `map.tsv`), the target before (`target.txt`), the replay, `verify`, the engine's `validate`, the round-3 landing facts (`facts.txt`) and the full-table diff (`tdiff3.md`) |
| `red/` | RED records: the round-5 suites on the round-4 tools, on three earlier round-5 states of the re-mint (before the chain fix, before `keep`, before the run-5 fixes B6..B8 and B10) and on the sweep before its control (their sources kept as `*.py.txt`); `red/engine_fact_flake.txt` shows the suite's wall-clock flake (B9), and the `engine_repro.sh` check on round 4 |
| `runs/lint_suite.txt`, `runs/remint_suite.txt`, `runs/branch_sweep_suite.txt` | the three suites on the final tree, each run twice, run 2 byte-identical |
| `runs/lint_mutations.txt`, `runs/remint_mutations.txt` | the two mutation harnesses on the final tree |
| `runs/branch_sweep.tsv`, `runs/branch_sweep_mutations.txt` | the final branch sweep (one row per mutant) and the sweep driver's own mutation check |
| `runs/branch_sweep_partial_bytebug.txt`, `runs/branch_sweep_only_rerun.txt`, `runs/branch_sweep_partial_prechainfix.txt`, `runs/branch_sweep_prekeep_partial.txt`, `runs/branch_sweep_run5.txt`, `runs/branch_sweep_run6.txt` | the earlier sweep runs, in order: a partial run, an `--only` re-run of its survivors, a second partial run, the partial run before `keep`, the complete run 5 on the source before B6..B8 and B10, and the complete run 6 on the final source with the suite and the register before the cases and the entry for its survivors; each partial run was stopped once it had found defects of inventory B (the first three files did not record their inputs) |
| `runs/probe_replay.txt` | the round-4 reviewer's probes p02, p03, p04, p06, p08, p11 and p12 re-run on the final tools, twice (run 2 byte-identical) |
| `runs/range_scan.txt` | the live scan for range forms the re-mint does not read (inventory R, "Open") |
| `runs/ref_integrity.txt` | the referential census of the source databases and the three landed copies (probe p07), with its mutation check |
| `runs/leak_scan.txt` | the secret and identity scan of this change, with its mutation check |
| `runs/checks.txt` | the static and repository checks: `shellcheck`, `pyright`, the suite manifest, the gate ledger, the whitespace check |
| `runs/inputs.sha256` | sha256 of the tools, suites, mutation harnesses, evidence tools and engine the runs used |
| `sources/` | the round-4 review (one host path replaced by `<scratch>`) and its mutant table |
| `tools/` | the evidence tools: `scrub_paths.py`, `tdiff3.py`, `landing_facts.py`, `probe_replay.py`, `range_scan.py`, `ref_integrity.py` (+ `_mutations.py`), `leak_scan.py` (+ `_mutations.py`) |
