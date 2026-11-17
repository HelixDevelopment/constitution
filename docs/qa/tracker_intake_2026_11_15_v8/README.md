# Tracker-intake vehicle, round 8: evidence pack

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15T15:30:00Z |
| Status | active |
| Status summary | Round-8 answer to the round-8 review (NO-GO, findings N1 to N6). The secret check of the intake lint is rebuilt in three stages (front end, keyed extractors, one value classifier); the class is enumerated and every member outside the rule has a reasoned section-B row. PROVISIONAL (section 11.4.290): gate-logic evidence only (section 11.4.289), the independent review of this round is still owed. |
| Author | round-8 fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289): the suites run the real lint and the real re-mint tool on copies of the real database; nothing here is a live run of a deployed product |
| Base | vehicle head `b3e3142b` (round 7), landing target `origin/main` `763726e0` |

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
| N1 backslash values not reported (round-7 regression) | `red/probe_bs_on_v6_v7.txt`: the reviewer's probe, 6 of 6 backslash values reported by the round-6 lint, 0 of 6 by the round-7 lint | `_QVAL` reads an escape sequence as part of a quoted value; the front end adds a view with escapes decoded; the census now generates backslash values | `runs/probe_bs_on_v8.txt`: 6 of 6 reported; fixture rows `rv-bs-*` (6) and `own-bs-*` (7); mutant R8-7 |
| N2 class not exhaustive | `red/probe_r8_on_v7.txt`: 30 of the reviewer's 51 credential shapes missed, 16 of the 52 lookalikes reported; `red/shapes_on_v7.txt`: 76 failures on the round-7 lint; `red/census_on_v7.txt.gz`: gap 24733, fp 23078 | structural rebuild in `scripts/workable-items/intake_lint.py` (section 11.4.276(E), replace, do not layer): stage 1 `secret_views` (NFKC, removal of format characters, a Cyrillic and Greek lookalike fold, an escape-decoded view, a percent-decoded view of each view), stage 2 `KEYED_EXTRACTORS` (one per syntax: assignment, argument pair, setter, `--flag`, short tool flag, identifier and whitespace, netrc, XML element, XML attribute pair, YAML block scalar, pgpass, URL user-info in any scheme case), stage 3 `credential_value` (length, letter and digit where the key tier needs it, never a reference, mask, placeholder, path or code) | `runs/probe_r8_on_v8.txt`: 7 of 51 missed, 0 of 52 reported; the 7 are exactly the section-B rows B1, B4, B9 (three), B10, B12 of `class_inventory.md`; `runs/census_*.txt`: 317674 members, gap 0, fp 0 |
| N2 leak scan used the lint's own patterns | `class_inventory.md` D3: the round-7 leak scan imported the lint patterns as its only oracle | `tools/leak_scan.py` is a second implementation (it imports nothing from the lint); `tools/leak_scan_test.py` runs the shared fixture list through it | `runs/leak_scan_test_*.txt`: 94 hit rows, 0 missed |
| N3 surviving reviewer mutants | the review's own runs (RL5, RR3, RR4, RR5 alive; RL3, RL4, RL6, RL7, RL8, RL10 alive without negative cases) | fixture rows `own-rl3-*` to `own-rl10-*` (exact rule lists and negatives); three `tf` cases in `tests/workable_items/test_remint_ids.sh` (a close as a re-render, the Evidence meta line as a template line, the `## ID. title` heading as a slot), each with a control | `runs/lint_mutations_first_run.txt`: RL1 to RL10 killed; `runs/remint_mutations_first_run.txt` and `runs/remint_mutations_rr1_rerun.txt`: RR1 to RR9 killed |
| N4 false positives | the 16 lookalikes of the reviewer probe reported by the round-7 lint (N2 RED) | the value classifier's path, placeholder and code exclusions; `credentials` keyed with the same path exclusion; the URL rule no longer reads a port or an IPv6 literal | all 52 lookalikes not reported (`runs/probe_r8_on_v8.txt`, the `rv-neg-*` rows of `runs/shapes_*.txt`) |
| N5 url-cred lead on the CON-330 placeholder | | classified again below (a `<placeholder>`, no credential) | [Leak scan](#leak-scan) |
| N6 bare recursive deletes, printed fragments | `class_inventory.md` D1, D2 | `safe_rm_rf` in the v4, v5 and v6 pack scripts; the v5, v6 and v7 leak scans print kind and length only; 127 `prefix=` fields in their run files redacted; the older packs' `SHA256SUMS` refreshed | a recursive-delete search over the packs finds none (the same search finds the one in `scripts/lib/safe_rm.sh`, the positive control); `sha256sum -c` passes in v4, v5, v6, v7 |

The round-7 fixes F2 (deterministic re-mint with a fixed past created_at), F3, F4 and F5 are kept: the re-mint
suite passes (464 checks) and the landing simulation passes against `763726e0`.

## Tests and mutants

| Suite | Result |
|---|---|
| `tests/workable_items/test_intake_lint.sh` | pass=372 fail=0 |
| `tests/workable_items/test_secret_shapes.py` (195 fixture rows) | pass=213 fail=0 |
| `tests/workable_items/test_remint_ids.sh` | pass=464 fail=0 |
| `tests/workable_items/test_remint_branch_sweep.sh` | pass=42 fail=0 |
| `tools/leak_scan_test.py` | hit_rows=94 missed=0 (22 broader leads on miss rows, not judged) |
| `tools/leak_scan_mutations.py` | mutants=31 bad=0 |
| `tools/secret_class_census.py` | members=317674 gap=0 fp=0 |

Mutation harnesses:

- `tests/workable_items/test_intake_lint_mutations.sh`: 185 mutants (the remapped older secret mutants, the
  reviewer's RL1 to RL10, the fixer's R8-1 to R8-34 for every part of the round-8 engine). First run
  (`runs/lint_mutations_first_run.txt`): 181 killed, 4 of the fixer's own survived (LR3, LR5, R8-18, R8-34).
  None was equivalent: each changed the lint's answer on a surface the fixtures did not hold (a `>` shell
  redirect, a JSON string inside a JSON string, an upper-case `-P` port flag, percent decoding of the
  escape view). Six fixture rows were added and the four re-run: all killed
  (`runs/lint_mutations_survivors_rerun.txt`).
- `tests/workable_items/test_remint_ids_mutations.sh`: 180 mutants including the reviewer's RR1 to RR9.
  First run (`runs/remint_mutations_first_run.txt`): 179 killed, RR1 reported stale (its text did not
  match: the transcription carried the line continuation `\` and the newline, which the harness format
  cannot express). The match was shortened to stop before the continuation; the edit is the reviewer's
  edit. Re-run: killed (`runs/remint_mutations_rr1_rerun.txt`).

## Three identical runs

`runs/<suite>_1.txt` to `_3.txt`: lint suite, re-mint suite, branch-sweep suite, shapes, leak-scan test,
leak-scan mutations, census. Each suite's three outputs have the same sha256 (one distinct value per
suite); every run exited 0.

## Leak scan

- `runs/leak_scan_diff.txt`: the staged change against `02c10935`. control needles PASS; secret_hits=235,
  identity_hits=133, pre_existing=0. The identity hits are the user name and home paths in the run logs
  of the round-1 to round-4 packs, the same count as in round 7; round 8 adds none. The secret hits in
  files round 8 changed were classified by masked shape only (letters as `a`/`A`, digits as `9`): fixture
  and test shapes built for the lint, escaped keys (`p…`), shell expansions (`"$…/$(…`), placeholders
  (`<password>`) and the docstring mask `XXXXXXXX`. No real credential was found.
- `runs/leak_scan_dbs.txt`: the vehicle database with the base `02c10935` database as its base, and the
  `763726e0` database. 4 hits, 233 pre-existing. rowid 939 (CON-302): a two-letter upper-case prefix, a
  slash and a dictionary word, prose. rowid 967 (CON-330): a URL user-info `<placeholder>` (N5). No real
  credential.

## Landing simulation and final lint

- `runs/simulate_landing_main763.txt` and `remint/main763/`: the vehicle's 46 items re-minted onto
  `763726e0` as CON-312 to CON-357. verify: PASS mode=REPLAY items=49 mismatches=0 known=48 (the known
  differences are the created_at replay time and history rows, as in round 7). facts: PASS facts=5.
- `final_lint.txt`: the vehicle's own items PASS (46 selected, 0 findings); the three base items the
  vehicle changed show 42 findings, 36 of them already in the base database; the 11 new ones are
  PATH-MISSING on CON-046 and SHARED-PATH on CON-262, as in round 7.

## Follow-ups

Drafts for tracked items, not filed by this round:

- B9: keys outside the lists (`key`, `pin`, `sid`, `cookie`), each a common word; a class extension.
- B18: lookalike letters outside the Cyrillic and Greek fold (for example Armenian).
- The 22 broader leads of the independent leak scan on miss rows: a scan is meant to be broader; a
  review of whether any of them should become a lint rule.

## How to re-run

- `bash tests/workable_items/test_intake_lint.sh`, `bash tests/workable_items/test_remint_ids.sh`,
  `bash tests/workable_items/test_remint_branch_sweep.sh`
- `python3 -I tests/workable_items/test_secret_shapes.py scripts/workable-items/intake_lint.py`
- `python3 -I docs/qa/tracker_intake_2026_11_15_v8/tools/leak_scan_test.py`,
  `tools/leak_scan_mutations.py`, `tools/secret_class_census.py scripts/workable-items/intake_lint.py`
- `bash tests/workable_items/test_intake_lint_mutations.sh` (`INTAKE_LINT_MUT_ONLY=<ids>` for a subset),
  `bash tests/workable_items/test_remint_ids_mutations.sh` (`REMINT_IDS_MUT_ONLY=<ids>`)
- `bash docs/qa/tracker_intake_2026_11_15_v8/tools/simulate_landing.sh`, `tools/make_final_lint.sh`
- the leak scans: arguments in the first line of each run file

## UNCONFIRMED and UNKNOWN

- The census enumerates the product of the declared dimensions; members outside it (other syntaxes,
  other languages' setters) are not claimed covered. Section B lists the known boundary.
- `fp=0` holds for the census, the 52 lookalikes and the fixtures; the false-positive rate on other
  corpora is UNKNOWN.
- The independent review of round 8 is owed; this pack is PROVISIONAL.
- Effort of the fixer: UNKNOWN.

## Files

| Path | What |
|---|---|
| `class_inventory.md` | the class (L1 to L16), the boundary with reasons (B1 to B20), the reviewer mutants (V), the delete and fragment fixes (D) |
| `red/` | RED runs on the round-7 (and round-6) lint |
| `runs/` | suites three times, mutation runs, census, reviewer probes on round 8, leak scans, landing simulation |
| `remint/main763/` | the re-mint plan, map, verify, facts and validate onto `763726e0` |
| `final_lint.txt` | the final lint runs |
| `tools/` | `leak_scan.py` (+ `_test.py`, `_mutations.py`), `secret_class_census.py`, `make_final_lint.sh`, `simulate_landing.sh` |
| `SHA256SUMS` | sums of every file in this pack |
