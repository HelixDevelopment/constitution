# Tracker-intake vehicle, round 6: answer to the round-5 review

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-14 |
| Last modified | 2026-11-14T19:30:00Z |
| Status | active |
| Status summary | Round-6 answer to the round-5 independent review (NO-GO: R5-1 and R5-3 important; R5-2, R5-4, R5-5, R5-6 minor). An update step passes `--description` only when the vehicle changed it, and verify compares `body_md`; a path refusal fires only when the id moves; the intake lint covers the keyed-credential class (22 patterns); the ten reviewer mutants and the fix's inverse are in the mutation suite and all killed; owed items 2, 4, 5, 7 and 8 are done or filed. PROVISIONAL: awaits the round-6 independent review. |
| Round | 6, under the operator decision of 2026-11-13 ("rounds until GO") |
| Base | vehicle head aee7489f (round 5), on main 02c10935 |
| Author | round-6 fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289): the real workable-items engine on scratch copies and fixture databases; nothing here proves a product defect fixed |
| Issues | the round-6 independent review is owed (section 11.4.142); no landing onto the live tracker has been run; landing precondition R5-5 below |
| Continuation | after a GO: land fix227 first, then the CON-046 vehicle (its evidence directory), then this vehicle by the landing sequence of docs/guides/remint_ids_guide.md |

## Table of contents

- [Headline, stated in full (R5-5)](#headline-stated-in-full-r5-5)
- [Finding by finding](#finding-by-finding)
- [Owed items](#owed-items)
- [Tests and mutants](#tests-and-mutants)
- [Landing simulations](#landing-simulations)
- [How to re-run](#how-to-re-run)
- [UNCONFIRMED and UNKNOWN](#unconfirmed-and-unknown)
- [Files in this directory](#files-in-this-directory)

## Headline, stated in full (R5-5)

`final_lint.txt` (written by `tools/make_final_lint.sh`):

- The vehicle's own items, CON-299..CON-344 (46 items; CON-343 and CON-344 were filed in this round):
  PASS, 0 findings, by id and by Origin line with the duplicate-check line required.
- The three base items the vehicle changed (CON-046, CON-243, CON-262), with NO skip list: FAIL,
  42 findings. The same items in the base database: 36 findings. The set difference is 11 findings the
  vehicle brings:
  - 8 PATH-MISSING on CON-046: `docs/qa/con046_review/` and seven paths under it. The vehicle restores
    CON-046's description from the CON-046 vehicle, whose evidence directory is not in any commit of
    base, main or this vehicle.
  - 3 SHARED-PATH on CON-262: `run_all.sh` is also named by the open CON-299, CON-339 and CON-340.
- Landing precondition (the review's first option for R5-5): land this vehicle only after the CON-046
  vehicle has landed `docs/qa/con046_review/`. Landing earlier writes 8 dangling evidence references
  into the tracker. The precondition is stated here and in the Continuation row; no tool enforces it.
  The 3 SHARED-PATH findings are references between open items, not defects of the intake format.

## Finding by finding

| Finding | Fix | RED (before) | GREEN (after) | Mutants |
|---|---|---|---|---|
| R5-1 an update step re-renders `body_md` | `remint_ids.py`: an update step passes `--description` only when the vehicle changed it, so a field-only change edits the engine slots and keeps the body; a re-render (a close, or an update with `--description`) over a body the target changed outside the slots is a CONFLICT, resolvable with `--resolve`; verify compares `body_md` (text outside the slots kept, heading names the landed title, Status line names the landed status) instead of a KNOWN line; an authored-body fixture (a base item whose body carries text outside the template, as 54 of the 263 real base items do); the round-4 case R4-1a, which expected the old behaviour, is inverted. Unit list in `class_inventory.md` section U | the round-6 suite on the round-5 tool (`red/remint_suite_on_r5.txt`) | suite cases named `R5-1: ...` | ROVFIX (the fix inverted), ROV1..ROV10 |
| R5-2 identity-map path refusal | a path that names an own id is refused only when the map moves that id; a refused plan is still written (mode REFUSED, no steps), and replay refuses it | `red/remint_suite_on_r5.txt` | `R5-2: ...` cases | — (covered by the cases) |
| R5-3 lint secret-shape gaps | `intake_lint.py`: the keyed credential class enumerated (key name x key quoting x prefix x separator x value quoting x value kind, headers, URL query, URL user-info); 22 patterns; two new (`password-colon-unquoted`, `secret-colon-unquoted`); references and masks excluded; false positives measured on the vehicle's 309-item database (0 for every widened pattern; the URL user-info form hit only CON-330, rewritten). Class in `class_inventory.md` section L. The leak scan of this pack loads the lint's patterns at run time, so the two read one class | `red/lint_suite_before_con330_rewrite.txt` (the real-DB case before CON-330 was rewritten); the round-6 lint suite on the round-5 lint (`red/lint_suite_on_r5.txt`) | `shapes` (16 positives) and `nshapes` (9 negatives) in `test_intake_lint.sh` | LN4, LN5 (remapped), LS1..LS12 |
| R5-4 seven reviewer mutants survive | ROV1..ROV10 and ROVFIX adopted into `test_remint_ids_mutations.sh` (ROV3 as the clause without its line continuation, the rest verbatim); a killing case for each survivor, marked `round 6 (R5-4)` in `test_remint_ids.sh` (ROV7 uses 4- and 5-digit ids) | the reviewer's run: 7 of 10 survived | `runs/mut_rov.txt`: 11 of 11 killed, control 448/0 | ROV1..ROV10, ROVFIX |
| R5-5 headline omits the no-skip count | the headline above; `tools/make_final_lint.sh` writes the no-skip runs and the set difference | the round-5 headline (PASS on 3 items by a skip list) | `final_lint.txt` | — |
| R5-6 owed item 2 named as the cause of the wrong failure | the guide's engine-defect paragraph and the suite comment say the stale Severity line fails verify together with the replay order (update before close and reopen), and that the body loss of R5-1 is not the engine's; the defect itself filed as CON-343 | the round-5 comment | `docs/guides/remint_ids_guide.md`, the comment above the case `verify FAIL: the engine's stale Severity line ...` | — |

## Owed items

| # | Item | Done |
|---|---|---|
| 2 | engine `update --severity` | reproduced on a scratch copy for all four field-only flags (`--severity`, `--type`, `--created-by`, `--assigned-to`: each leaves its body line STALE; the review had probed `--severity` only), `runs/engine_field_repro.txt`, script `tools/engine_field_repro.sh`; filed through the engine as CON-343 (Bug, reproduced-host-fixture, host-only) |
| 3 | FAST-FORWARD base refusal | R5-2 |
| 4 | corrupt-database fixture for the referential census | `tools/ref_integrity.py` builds a corrupt file (one key of a side-table index overwritten on disk, so `PRAGMA integrity_check` reports a row missing from the index while every count stays 0); the needle requires DIRTY from the integrity check alone. The round-5 KNOWN mutant `integrity_verdict` is now killed: `runs/ref_integrity.txt`, 13 mutants, 0 bad, 0 known |
| 5 | 154 identity strings in the base database | out of scope (section 11.4.293); filed through the engine as CON-344 (Task) |
| 6 | dangling con046_review paths | R5-5 (landing precondition) |
| 7 | CON-330 url-cred | CON-330's description rewritten through the engine with a placeholder-only example (`https://<user>:<password>@<host>/<path>`); the pre-edit copy is not committed. Issues.md and Issues_Summary.md re-exported |
| 8 | explicit suite loader | `test_remint_ids.sh` loads the tool with `importlib.machinery.SourceFileLoader`, so a tool path with any suffix loads (the round-5 false RED on `*.py.txt`). `test_remint_branch_sweep.sh` is unchanged: it always loads a `*.py` copy, and it is an input of the round-5 branch sweep, which was not re-run |

## Tests and mutants

All runs used an `env -i` environment with a scratch HOME and TMPDIR. Every run file starts with the command that produced it.

| Run | Result | File |
|---|---|---|
| intake lint suite | 312 pass, 0 fail; run twice, the two outputs are byte-identical | `runs/lint_suite.txt` |
| re-mint suite | 448 pass, 0 fail; run twice, the two outputs are byte-identical | `runs/remint_suite.txt` |
| intake lint mutants (full run) | 122, all killed as declared | `runs/lint_mutations.txt` |
| re-mint mutants (full run) | 163; RV2, RV6 and N7 were stale (their anchors moved with the round-6 code), the rest killed | `runs/remint_mutations.txt` |
| re-mint mutants RV2, RV6, N7 remapped | 3 killed; the unmutated control passes 448/0 | `runs/remint_mutations_remap.txt` |
| reviewer mutants ROV1 to ROV10 and ROVFIX (R5-4) | 11 killed | `runs/mut_rov.txt` |
| referential census with the corrupt fixture | 13 mutants, 0 bad, 0 known; base and vehicle databases CLEAN | `runs/ref_integrity.txt` |
| engine field-only update probe | all four flags leave the body line STALE (CON-343) | `runs/engine_field_repro.txt` |
| leak scan of the staged change and the databases | see the file | `runs/leak_scan.txt` |

RED runs: the round-6 suites run against the round-5 tools (`aee7489f`).

- `red/remint_suite_on_r5.txt`: 417 pass, 31 fail. 21 of the 31 are behavioural (the round-6 fixes; the failing case names are in the file). 10 are output format only: the round-5 tool printed `REFUSED: ...` from its exception path, the round-6 tool prints `REFUSED ...` plan lines.
- `red/lint_suite_on_r5.txt`: 294 pass, 18 fail. 17 are the R5-3 secret-shape cases and their needles. 1 is the real-database batch, where the round-5 lint flags the CON-330 placeholder `<password>` (a round-5 false positive).
- `red/lint_suite_before_con330_rewrite.txt`: the lint suite before CON-330 was rewritten.

Not done in this round (honest gaps):

- The round-5 branch sweep (426 cases) was not re-run.
- RV2, RV6 and N7 were confirmed killed by a targeted run, not by a fresh full mutation run.
- The cause of CON-343 in the engine is not investigated; the item is filed, not fixed.

## Landing simulations

Script `tools/simulate_landing.sh`. Each target directory under `remint/` holds the plan, the replay, the verify output, the engine validate output, the landing facts and a three-way diff.

| Target | Mode | Result |
|---|---|---|
| `fix227` (`fed933c0`) | REPLAY | 46 own items re-minted to CON-312..CON-357 in 72 steps; verify PASS over 49 items, 0 mismatches, 48 known (created_at, plus one M-14 history entry); engine validate 321 items OK; landing facts 5 pass, 0 fail |
| `main` (`bd0036bd`) | FAST-FORWARD | verify PASS over 309 items, 0 mismatches, 0 known; engine validate 309 items OK |
| `main` without fast-forward | REPLAY | verify PASS over 49 items, 0 mismatches, 48 known; engine validate OK |

The note on CON-243: its created_at changed in the vehicle and is not carried, because no engine command sets it (engine defect CON-339).

Landing precondition (R5-5, documented, not enforced by a gate): the 8 PATH-MISSING findings name `con046_review` paths that exist only on the branch that carries that review. They resolve once that branch lands first.

## How to re-run

From the repository root, with an `env -i` environment (scratch HOME and TMPDIR):

- Suites: `bash tests/workable_items/test_remint_ids.sh`, `bash tests/workable_items/test_intake_lint.sh`.
- Mutants: `REMINT_IDS_MUT_JOBS=2 bash tests/workable_items/test_remint_ids_mutations.sh`,
  `INTAKE_LINT_MUT_JOBS=2 bash tests/workable_items/test_intake_lint_mutations.sh` (one at a time).
- RED: the same suites with `REMINT_IDS=<copy of the round-5 remint_ids.py>` or
  `INTAKE_LINT=<copy of the round-5 intake_lint.py>` (`git show aee7489f:scripts/workable-items/<name>`).
- `bash docs/qa/tracker_intake_2026_11_14_v6/tools/make_final_lint.sh <base 02c10935 db> > docs/qa/tracker_intake_2026_11_14_v6/final_lint.txt`
- `bash docs/qa/tracker_intake_2026_11_14_v6/tools/simulate_landing.sh scripts/workable-items/bin/workable-items 02c10935 fix227=fed933c0 main=bd0036bd main-replay=bd0036bd:no-ff`
- `python3 -I docs/qa/tracker_intake_2026_11_14_v6/tools/ref_integrity.py base=<base db> vehicle=docs/workable_items.db`
- `HELIX_RELEASE_PREFIX=CON bash docs/qa/tracker_intake_2026_11_14_v6/tools/engine_field_repro.sh scripts/workable-items/bin/workable-items <db> <empty dir>`
- `python3 -I docs/qa/tracker_intake_2026_11_14_v6/tools/leak_scan.py ...` and `tools/leak_scan_mutations.py` (see `runs/leak_scan.txt` for the arguments).

## UNCONFIRMED and UNKNOWN

- The R5-3 class is the enumerated class of `class_inventory.md` section L. Outside it (stated, not
  covered): a letters-only value after a generic key and a colon (`token: abcdefgh`), a key name outside
  the lists, a value shorter than eight characters, a credential written without any key.
- The round-5 branch sweep (426 mutants) was not re-run on the round-6 tool. The round-6 changes to the
  planner and verify are covered by the suite cases and by ROV1..ROV10 and ROVFIX; whether the sweep's
  forced branches all still die on the round-6 tool is UNCONFIRMED.
- The R5-5 landing precondition is written here, not enforced by a tool.
- CON-343: the cause in the engine is not investigated (investigation state not-started).
- Effort of the fixer: UNKNOWN.

## Files in this directory

| Path | What |
|---|---|
| `README.md` | this file |
| `class_inventory.md` | the classes behind R5-1..R5-4, enumerated before the fix |
| `final_lint.txt` | intake lint runs and the no-skip headline (`tools/make_final_lint.sh`) |
| `red/` | RED runs: the round-6 suites on the round-5 tools, and the lint suite before the CON-330 rewrite |
| `runs/` | suite runs (twice, for determinism), mutation runs, the engine field probe, the referential census, the leak scan |
| `remint/<target>/` | the landing simulations (`tools/simulate_landing.sh`) |
| `tools/` | `make_final_lint.sh`, `simulate_landing.sh`, `engine_field_repro.sh`, `ref_integrity.py` (+ `_mutations.py`), `leak_scan.py` (+ `_mutations.py`) |
| `SHA256SUMS` | checksums of every file above |
