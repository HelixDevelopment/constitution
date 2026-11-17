# Tracker-intake vehicle, round 9: evidence pack

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15T21:35:00Z |
| Status | active |
| Status summary | Round-9 answer to the round-9 review (NO-GO, findings F1 to F5). The key half of the lint's secret check is replaced by one key classifier, the front end reads marks, fillers and up to three decoding layers, the landing gains supersede, foreign-id and duplicate-resolution inputs and a lint of the landed result. PROVISIONAL (section 11.4.290): gate-logic evidence only (section 11.4.289), the independent review of this round is still owed. |
| Author | round-9 fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289): the suites run the real lint and the real re-mint tool on copies of the real database; nothing here is a live run of a deployed product |
| Base | vehicle head `de89a604` (round 8), vehicle base `02c10935`; landing targets `origin/main` `584c287e`, `2031bc05` and `bcac0882` (the tip at the time of writing) |

## Table of contents

- [Findings, one by one](#findings-one-by-one)
- [Tests and mutants](#tests-and-mutants)
- [Three identical runs](#three-identical-runs)
- [Leak scan](#leak-scan)
- [Landing simulation and final lint](#landing-simulation-and-final-lint)
- [Follow-ups](#follow-ups)
- [How to re-run](#how-to-re-run)
- [UNCONFIRMED and UNKNOWN](#unconfirmed-and-unknown)
- [Files](#files)

## Findings, one by one

| Finding | RED (on the broken artifact) | Fix | GREEN |
|---|---|---|---|
| F1 secret class not closed (lint) | `red/probe_r9_on_v8.txt`: 36 of the reviewer's 50 shapes missed, 4 of 20 lookalikes reported; `red/census_r9_on_v8.txt`: the round-9 census on the round-8 lint | structural (section 11.4.276(E)): extractors yield a key token, one classifier `key_tier()` decides its tier from its words; marks, invisible fillers, a Latin-by-name fold and up to three decoding layers (escapes, octal, percent, HTML entities, joined literals) in the front end; the class is enumerated in `class_inventory.md` (L17 to L35) | `runs/probe_r9_on_v9.txt`: 0 of 50 missed, 0 of 20 reported; census and shapes below |
| F1 secret class not closed (independent scan) | `red/probe_scan_r9_on_v8.txt`: 22 of 50 missed; `red/leak_scan_test_before_glued.txt`, `red/leak_scan_test_before_onelfix.txt`: shared rows the scan missed; `red/leak_scan_mutations_stale.txt`: 10 scan mutants stale | the scan reads the widened class again in its own way (it imports nothing from the lint); its mutation harness is remapped and extended (`class_inventory.md` L35) | `runs/probe_scan_r9_on_v9.txt`: 0 of 50 missed; `runs/leak_scan_test_*.txt`, `runs/leak_scan_mutations_*.txt` |
| F2 CON-339 minted again, CON-313's text rebound | the review's landing: vehicle CON-339 landed as an open duplicate of CON-313; CON-313 kept "CON-339" | `remint_ids.py plan --supersede CON-339=CON-313` (no row minted, references rewritten), `--annotate-foreign CON-313` (a Foreign ids line), refusals XREF-REBOUND and XREF-SUPERSEDED | `remint/main_*/plan.txt`, `verify.txt`; `landed_touched_lint.txt`: the CON-339 cross-reference finding is REMOVED, nothing NEW |
| F3 landed items fail the lint | the review's `final_lint_584.txt`: FAIL, 49 SHARED-PATH findings on the landed database | `--dup-resolution FILE` (one verdict per shared-path pair, `remint/dup_resolution_*.tsv`); `simulate_landing.sh` lints the landed result: the landed own items, and the target items the landing writes compared with the unlanded target | `remint/main_*/landed_lint.txt` PASS 45 items, 0 findings, on all three targets; `landed_touched_lint.txt` NEW=0 |
| F4 surviving mutants | RV2, RV12, RW3 alive (and RW2, RW6 called equivalent) | RV12 killed by fixture rows, RW3 and RW6 by re-mint cases; RV2 and RW2 proven equivalent (section E of the inventory, checked by the harness on every run) | `runs/lint_mutations_full.txt`, `runs/remint_mutations_full.txt`, `runs/remint_mutations_or_rerun.txt` |
| F5 false positives | 4 of the reviewer's 20 lookalikes reported | references and identifier values are not values (`credential_value`) | 0 of 20 reported |

## Tests and mutants

| Suite or harness | Result |
|---|---|
| `tests/workable_items/test_intake_lint.sh` | pass=372 fail=0 |
| `tests/workable_items/test_remint_ids.sh` | pass=518 fail=0 (5 cases added for OR1, OR11, OR12, OR14) |
| `tests/workable_items/test_remint_branch_sweep.sh` | pass=42 fail=0 |
| `tests/workable_items/test_secret_shapes.py` | pass=308 fail=0 rows=288 |
| `tests/workable_items/secret_shape_fixtures.py` (self-check) | rows=288 hit=168 problems=0 |
| `tools/selfcheck_red.py` (the self-check fails when it should) | controls=4 bad=0 |
| `tools/secret_class_census.py` on the round-9 lint | members=318458 gap=0 fp=0 (round-8 lint: gap=601 fp=22, `red/census_r9_on_v8.txt`) |
| `tools/leak_scan_test.py` | hit_rows=168 missed=0 (31 broader leads on miss rows, not judged) |
| `tools/leak_scan_mutations.py` | mutants=50 bad=0 |
| reviewer probes (`probes/`) | lint: 50 of 50 found, 0 of 20 lookalikes reported; scan: 50 of 50 found |
| `tests/workable_items/test_intake_lint_mutations.sh` | mutants=219, all killed, 2 declared equivalent (RV2, LR2) and checked on the run (`runs/lint_mutations_full.txt`) |
| `tests/workable_items/test_remint_ids_mutations.sh` | first full run: 204 mutants, 4 own mutants alive (OR1, OR11, OR12, OR14; `red/remint_mutations_or_survivors.txt`); after five new suite cases the four are killed (`runs/remint_mutations_or_rerun.txt`); RW2 equivalent (200000 cases, 0 collisions) |
| equivalence of RV2 and LR2 (`runs/equiv_RV2.txt`, `runs/equiv_LR2.txt`) | re-run on the final fixtures: 2742618 strings, view and hit differences 0, control needle found |

The full re-mint harness was not run a second time after the five cases were added; the 200 other
verdicts are those of the first run, and added cases can only kill more mutants.

## Three identical runs

`runs/<suite>_1.txt` to `_3.txt` for the lint suite, re-mint suite, branch-sweep suite, census, shapes,
fixture self-check, leak-scan test and leak-scan mutations, made by one script that runs two suites at a
time. Each suite's three outputs have the same sha256 (one distinct value per suite) and every run exited
0. The mutation harnesses ran once each.

## Leak scan

- `runs/leak_scan_diff.txt`: the staged change against `02c10935` (rounds 8 and 9 together). Control
  needles PASS; secret_hits=785, identity_hits=133, pre_existing=0, binary_skipped=2. The identity hits
  are the user name and home paths in the run logs of the round-1 to round-4 packs, the same 133 as in
  round 8; round 9 adds none. The secret hits in files round 9 changed were classified by masked shape
  (letters `a`/`A`, digits `9`, key words kept): fixture and test values built from split fragments for the
  lint, regular expressions and docstrings of the lint and the scan, shell command flags such as `mkdir -p` (short-flag),
  fixture labels and rule names in run outputs, and item prose in the landing plans. No real credential
  was found.
- `runs/leak_scan_dbs.txt`: the vehicle database (base: the `02c10935` database) and the `bcac0882`
  database. secret_hits=88, identity_hits=0, pre_existing=246. Vehicle: rowid 939 (CON-302, prose) and
  rowid 967 (CON-330, a URL user-info `<placeholder>`), the same two as round 8. Main: 84 hits in main's
  own items, read with the scan's own window function on 11 sampled rows: 12 of the 13 windows are the word "session" before an
  8-character hex id (an agent session id) and one is the word "token" before a lower-case word (prose).
  No real credential; main's items are not changed by this vehicle.

## Landing simulation and final lint

Each target: `runs/simulate_landing_main_<rev>.txt` and `remint/main_<rev>/`. Inputs on every target:
`--supersede CON-339=CON-313 --annotate-foreign CON-313 --dup-resolution remint/dup_resolution_<rev>.tsv`.

| Target | Plan | Replay | Verify | Facts | Validate | Landed own items | Target items the landing writes |
|---|---|---|---|---|---|---|---|
| `584c287e` | REPLAY own=46 steps=70 conflicts=0 refusals=0, CON-315 to CON-359 | APPLIED 70 | PASS items=49 mismatches=0 known=46 | PASS 5 | OK 324 items | PASS selected=45 findings=0 | CON-313: landed=11 target=12 NEW=0 REMOVED=1 |
| `2031bc05` | the same, CON-388 to CON-432 | APPLIED 70 | PASS items=49 mismatches=0 known=46 | PASS 5 | OK 397 items | PASS selected=45 findings=0 | CON-313: landed=12 target=13 NEW=0 REMOVED=1 |
| `bcac0882` | the same, CON-401 to CON-445 | APPLIED 70 | PASS items=49 mismatches=0 known=46 | PASS 5 | OK 410 items | PASS selected=45 findings=0 | CON-313: landed=18 target=19 NEW=0 REMOVED=1 |

The vehicle's own lint (`vehicle_lint.txt`) is PASS selected=46 findings=0 on every target. The ids are
the re-mint tool's output for each target; the lander re-mints against the `main` tip of the landing day
(above CON-400 on `bcac0882`), never with the ids of this table. The `known=46` differences are the
replay time of `created_at` and the history rows, as in rounds 7 and 8.

The 45 landed own items are the vehicle's 46 minus CON-339, which lands on CON-313. The touched target
item CON-313 keeps its own findings on main (sections, a review-file name, state evidence; they are main's
text and are not changed here); the landing removes one (the CON-339 cross-reference) and adds none.

`final_lint.txt`: the vehicle database itself. The vehicle's own items PASS (46 selected, 0 findings); the
three base items the vehicle changed show 42 findings, 36 of them already in the base database, as in
round 8.

## Follow-ups

Drafts for tracked items, not filed by this round:

- CON-387 (on main): restore CON-308's created_at when the vehicle lands; a lander duty.
- CON-397 (on main): the vehicle's pairs of Obsolete history rows (592/593, 614/615, 616/617). Explained
  from the engine source: `workable-items update --status obsolete` writes an Obsolete row with no reason
  (`cmd/workable-items/crud.go`, line 422) and `workable-items obsolete-details` writes a second one with
  the reason (`obsolete.go`, line 152); the base database holds the same pair for CON-172 (433/434). The
  history is append-only (section 11.4.34), so the rows are not removed here; the decision is the
  lander's.
- The UNDECIDED pairs against CON-383 (`remint/dup_resolution_2031bc05.tsv`): for the operator.
- The superseded CON-339 text is not carried onto CON-313; an audit copy is in `plan.json`.
- Interior ids of a declared foreign range are not checked for rebinding (only the ends are tested).
- The lint is about 7 times slower than round 8 on a long repeated key line, still linear
  (`runs/scale_long_lines.txt`).
- Old pack tools in the manifest (`runs/old_pack_tools.txt`): the v6 and v7 `leak_scan_mutations.py`
  fail their control (rc=3, they load the live lint's SECRET patterns, which round 8 rebuilt; they fail on
  `de89a604` too), and the v8 `leak_scan_test.py` misses 35 rows added in round 9 (the v8 scan does not
  cover those classes; it passes on `de89a604`). The v6/v7 `ref_integrity_mutations.py` pass. The rows stay
  `entry`; the fix is an operator decision: exclude them as `reason: tool: historical pack tool bound to the
  tree of its round` (an acceptance on `config/full_suite_excluded.lock`, which only a rostered operator
  makes), or pin each tool to its round's inputs.

## How to re-run

- `bash tests/workable_items/test_intake_lint.sh`, `bash tests/workable_items/test_remint_ids.sh`,
  `bash tests/workable_items/test_remint_branch_sweep.sh`
- `python3 -I tests/workable_items/test_secret_shapes.py scripts/workable-items/intake_lint.py`,
  `python3 -I tests/workable_items/secret_shape_fixtures.py` (self-check),
  `python3 -I docs/qa/tracker_intake_2026_11_15_v9/tools/selfcheck_red.py tests/workable_items/secret_shape_fixtures.py`
- `python3 -I docs/qa/tracker_intake_2026_11_15_v9/tools/leak_scan_test.py`, `tools/leak_scan_mutations.py`,
  `tools/secret_class_census.py scripts/workable-items/intake_lint.py`
- `bash tests/workable_items/test_intake_lint_mutations.sh` (`INTAKE_LINT_MUT_ONLY=<ids>`),
  `bash tests/workable_items/test_remint_ids_mutations.sh` (`REMINT_IDS_MUT_ONLY=<ids>`)
- `bash docs/qa/tracker_intake_2026_11_15_v9/tools/simulate_landing.sh <engine> 02c10935 --supersede CON-339=CON-313 --annotate-foreign CON-313 --dup-resolution <file> main_<rev>=<rev>`
- the leak scans: arguments in the first line of each run file

## UNCONFIRMED and UNKNOWN

- The census enumerates the product of its declared dimensions; members outside it are not claimed
  covered. Section B of the inventory lists the known boundary.
- `fp=0` holds for the census, the reviewer's lookalikes and the fixtures; the false-positive rate on
  other corpora is UNKNOWN.
- An equivalence on a finite corpus is evidence, not proof (inventory section E).
- The independent review of round 9 is owed; this pack is PROVISIONAL.
- Effort of the fixer: UNKNOWN.

## Files

| Path | What |
|---|---|
| `class_inventory.md` | the class (L17 to L35), the boundary, the mutants (V), the equivalent mutants (E), the landing reconciliation (R) |
| `red/` | RED runs on the round-8 lint and on the scan before its fixes |
| `runs/` | suites three times, mutation runs, equivalence evidence, probes, census, leak scans, landing simulations, long-line timing |
| `remint/` | the duplicate-resolution files and, per target, the plan, map, replay, verify, facts, validate and lints |
| `probes/` | the round-9 reviewer's probes and mutant file, copied verbatim |
| `final_lint.txt` | the final lint runs on the vehicle database |
| `tools/` | `leak_scan.py` (+ `_test.py`, `_mutations.py`), `secret_class_census.py`, `equiv_check.py`, `equiv_rw2.py`, `selfcheck_red.py`, `scale_long_lines.py`, `make_final_lint.sh`, `simulate_landing.sh` |
| `SHA256SUMS` | sums of every file in this pack |
