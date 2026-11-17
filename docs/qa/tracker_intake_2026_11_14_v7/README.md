# Tracker-intake vehicle, round 7: answer to the round-6 review

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-14 |
| Last modified | 2026-11-15T00:40:00Z |
| Status | active |
| Status summary | Round-7 answer to the round-6 independent review (NO-GO: F1 and F2 important; F3 to F6 minor or nit). The secret-shape class is enumerated by a census (282718 members; round-6 lint: 67230 gaps, 2040 false positives; round-7 lint: 0 and 0) and closed in the lint and the leak scan (28 patterns, NFKC form); the flaky re-mint case is root-caused and its fixture made deterministic; RM1 to RM8 are in the mutation suite and all killed; F4 and F5 done; F6 a follow-up. PROVISIONAL: awaits the round-7 independent review. |
| Round | 7, under the operator decision of 2026-11-13 ("rounds until GO") |
| Base | vehicle head 0212612352e5 (round 6), on main 02c10935 |
| Author | round-7 fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289): the real workable-items engine and the real lint on scratch copies and fixture databases; nothing here proves a product defect fixed |
| Issues | the round-7 independent review is owed (section 11.4.142); no landing onto the live tracker has been run; the landing precondition of round 6 (CON-046's evidence directory first) stands |
| Continuation | after a GO: land fix227 first, then the CON-046 vehicle, then this vehicle by the landing sequence of docs/guides/remint_ids_guide.md |

## Table of contents

- [Finding by finding](#finding-by-finding)
- [Tests and mutants](#tests-and-mutants)
- [Leak scan](#leak-scan)
- [Landing simulations and final lint](#landing-simulations-and-final-lint)
- [Follow-ups](#follow-ups)
- [How to re-run](#how-to-re-run)
- [UNCONFIRMED and UNKNOWN](#unconfirmed-and-unknown)
- [Files in this directory](#files-in-this-directory)

## Finding by finding

| Finding | Fix | RED (before) | GREEN (after) |
|---|---|---|---|
| F1 secret-shape class not exhaustive | Class enumerated first by `tools/secret_class_census.py` (labels only). `intake_lint.py`: keys joined to a prefix by nothing, short keys (pwd, pass, auth), backtick and escaped quotes, quoted values with a space, `--flag` values, `set -x KEY V`, netrc, XML elements, URL user-info with `/` or an empty user (digits before `/` read as a port), `api.key`, `oauth_token`, `credentials`, the NFKC form of every surface; `=>` followed by a short value no longer reported. 28 patterns, one built-in needle each. `secret_hits()` is the one read path; `tools/leak_scan.py` reads NFKC too. Members and boundary: `class_inventory.md` sections L and B | census on the round-6 lint: gap=67230 fp=2040 (`red/census_on_r6.txt`); lint suite on the round-6 lint: 329 pass, 30 fail (`red/lint_suite_on_r6.txt`) | census gap=0 fp=0 (`runs/census.txt`); 23 new `shapes`, 12 new `nshapes` and 6 new needle cases; lint suite 359 pass, 0 fail |
| F2 flaky re-mint case | Root cause (reproduced first, `tools/created_at_repro.sh`): an engine `close` writes created_at to the current second (CON-339), so the CON-339 note on base item 3 appeared only when the vehicle's close fell in a later second than the base `add`. The suite now gives the base items a fixed past created_at before the vehicle and target copies are made | `runs/created_at_repro.txt`: same-second closes 10 of 10 unchanged, next-second closes 0 of 10 unchanged | `runs/remint_suite.txt`: 458 pass, 0 fail; three runs byte-identical (sha256 83c61726...8382) |
| F3 RM2, RM3, RM8 survive | Cases in section (11) of `test_remint_ids.sh`: an altered template meta line under no re-render (RM8); an Obsolete-Details rewrite on an item the target renamed (RM3); a reopen over a legacy bulleted Reopened-Details block, Evidence bullet included (RM2); also a re-render over a target edit of a template meta line, a CONFLICT (RM6, which survived the first RM run) | the reviewer's run; `runs/remint_mutations_rm_first.txt` (RM6 survived) | `runs/remint_mutations.txt`: 171 mutants, all killed |
| F4 bare `rm -rf` in two tools | `tools/simulate_landing.sh` and `tools/make_final_lint.sh` delete through `safe_rm_rf` | the round-6 tools | `grep 'rm -rf'` finds none in either |
| F5 final-lint set difference not like for like | `tools/make_final_lint.sh` adds run 5 (vehicle, `--no-rendered`) and diffs 5 minus 4; the rendered-only findings of run 3 are listed apart | the round-6 diff (run 3 minus run 4) | `final_lint.txt`: new=11, rendered_only=0 |
| F6 table-representation items | not changed; see [Follow-ups](#follow-ups) | — | — |

The F3 cases change only the suite, so the round-7 suite also passes on the round-6 tool
(`red/remint_suite_on_r6.txt`: 458 pass, 0 fail): their RED is the mutation run, not the tool.

## Tests and mutants

All runs used an `env -i` environment with a scratch HOME and TMPDIR, under `systemd-run --user --scope -p TasksMax=2000` at `nice -n 10`. Every run file starts with the command that produced it.

| Run | Result | File |
|---|---|---|
| intake lint suite | 359 pass, 0 fail; 3 runs byte-identical (sha256 d0ac73ec...5156) | `runs/lint_suite.txt` |
| re-mint suite | 458 pass, 0 fail; 3 runs byte-identical (sha256 83c61726...8382) | `runs/remint_suite.txt` |
| intake lint mutants (full run) | 141, all killed as declared; O17, LV5, LN5, LS1, LS2, LS4, LS6, LS7, LS9, LS11, LS12 remapped onto the round-7 text; LR1 to LR19 new, one per round-7 rule | `runs/lint_mutations.txt` |
| re-mint mutants (full run) | 171, all killed, RM1 to RM8 included (verbatim) | `runs/remint_mutations.txt` |
| RM1 to RM8, first run | RM6 survived; the RM6 case was added after it | `runs/remint_mutations_rm_first.txt` |
| leak-scan mutants | 16, all killed (`nfkc_dropped` new) | `runs/leak_scan_mutations.txt` |
| secret-shape census | members=282718 hit=88992 miss_negative=187810 miss_boundary=5916 gap=0 fp=0 | `runs/census.txt` |
| created_at toggle | see F2 | `runs/created_at_repro.txt` |

Not re-run this round: `tools/ref_integrity.py` and `tools/engine_field_repro.sh` (unchanged since round 6; their round-6 runs are in the round-6 pack); the round-5 branch sweep.

## Leak scan

`runs/leak_scan_dbs.txt` (vehicle database against the base database, and the main database),
`runs/leak_scan_diff_r7.txt` (the lines this round adds over 02126123) and `runs/leak_scan_diff.txt`
(the whole vehicle over 02c10935). Each run's control needles passed first (37 secret kinds, 3 identity
kinds, a plain line not reported).

- Round-7 diff: 18 secret-class hits, 0 identity hits. `runs/leak_scan_diff_r7_masked.txt` (made by
  `tools/mask_hits.py`, alphanumerics masked) shows each line: all 18 are prose rule descriptions,
  comments, regex source, `<placeholder>` examples or a needle built from fragments.
- Whole vehicle: 79 secret-class and 133 identity hits, most in the source and log copies of rounds 1
  to 6 (reviewed in those rounds, not re-reviewed one by one here).

- Databases: 2 secret hits, both in CON-330 (description and body): the round-6 placeholder example
  `https://<user>:<password>@<host>/<path>`. Masked shape: user `<user>`, password a 10-character
  `<...>` placeholder. The leak scan's own url-cred kind does not exclude a `<...>` reference (the
  lint's pattern does); a lead, not a credential. 220 pre-existing hits in the base database are
  identity strings (user name and home path, CON-344), 0 secrets.
- The 37 secret kinds of the leak scan's control needles include the round-7 shapes; no separate
  planted-row run on a database copy was made (UNCONFIRMED beyond the needle run).

## Landing simulations and final lint

| Target | Mode | Result |
|---|---|---|
| `fix227` (`fed933c0`) | REPLAY | 46 own items to CON-312..CON-357, 72 steps; verify PASS over 49 items, 0 mismatches, 48 known; engine validate 321 items OK; landing facts 5 pass |
| `main` (`bd0036bd`) | FAST-FORWARD | verify PASS over 309 items, 0 mismatches, 0 known; validate 309 items OK |
| `main` without fast-forward | REPLAY | verify PASS over 49 items, 0 mismatches, 48 known; validate OK |

`final_lint.txt`: own items CON-299..CON-344 PASS, 0 findings (by id and by Origin line). The three base
items the vehicle changed, no skip list: 42 findings (vehicle, renders read), 42 (vehicle, renders not
read), 36 (base). Like for like, the vehicle brings 11: 8 PATH-MISSING on CON-046 (the con046_review
directory, landing precondition) and 3 SHARED-PATH on CON-262; 0 findings come from the rendered
documents only.

## Follow-ups

- F6: engine `update --description` does not re-render a table-representation item, while the planner
  and `check_body` treat it as a re-render. No table rows exist in any reviewed database, and own items
  with a non-section representation are refused, so no landing is affected. Owed: a table-row fixture
  and a planner rule, as a tracked item.
- The leak scan's own url-cred kind could exclude a `<...>` reference, as the lint's pattern does.
- The boundary rows B1 to B11 of `class_inventory.md` are class extensions for a later round.

## How to re-run

From the repository root, with an `env -i` environment (scratch HOME and TMPDIR):

- Suites: `bash tests/workable_items/test_remint_ids.sh`, `bash tests/workable_items/test_intake_lint.sh`.
- Mutants: `REMINT_IDS_MUT_JOBS=2 bash tests/workable_items/test_remint_ids_mutations.sh`,
  `INTAKE_LINT_MUT_JOBS=2 bash tests/workable_items/test_intake_lint_mutations.sh`.
- RED: the suites with `REMINT_IDS=` / `INTAKE_LINT=` a copy of the round-6 file (`git show 02126123:scripts/workable-items/<name>`).
- `python3 -I docs/qa/tracker_intake_2026_11_14_v7/tools/secret_class_census.py <intake_lint.py>`
- `bash docs/qa/tracker_intake_2026_11_14_v7/tools/created_at_repro.sh scripts/workable-items/bin/workable-items <db copy> 10`
- `bash docs/qa/tracker_intake_2026_11_14_v7/tools/make_final_lint.sh <base 02c10935 db> > docs/qa/tracker_intake_2026_11_14_v7/final_lint.txt`
- `bash docs/qa/tracker_intake_2026_11_14_v7/tools/simulate_landing.sh scripts/workable-items/bin/workable-items 02c10935 fix227=fed933c0 main=bd0036bd main-replay=bd0036bd:no-ff` (fed933c0 comes from the fix227 bundle chain)
- `python3 -I docs/qa/tracker_intake_2026_11_14_v7/tools/leak_scan.py` and `tools/leak_scan_mutations.py` (arguments in the first line of each run file).

## UNCONFIRMED and UNKNOWN

- The class closed is the enumerated class of `class_inventory.md`; members outside it (section B) are
  stated, not covered. The census's expected verdicts are the rule written in section L; it measures the
  lint against that rule, not against every possible credential.
- The F2 fix removes the timing dependence of the base items' created_at; any other wall-clock
  dependence in the suite is not known to exist, and three identical runs do not prove there is none.
- F6 is not fixed.
- Effort of the fixer: UNKNOWN.

## Files in this directory

| Path | What |
|---|---|
| `README.md` | this file |
| `class_inventory.md` | the classes behind F1 to F3, the boundary with reasons |
| `final_lint.txt` | intake lint runs and the like-for-like difference (`tools/make_final_lint.sh`) |
| `red/` | the census and the round-7 suites on the round-6 tools |
| `runs/` | suite runs, mutation runs, the census, the created_at toggle, the leak scans |
| `remint/<target>/` | the landing simulations (`tools/simulate_landing.sh`) |
| `tools/` | `mask_hits.py`, `secret_class_census.py`, `created_at_repro.sh`, `make_final_lint.sh`, `simulate_landing.sh`, `engine_field_repro.sh`, `ref_integrity.py` (+ `_mutations.py`), `leak_scan.py` (+ `_mutations.py`) |
| `SHA256SUMS` | checksums of every file above |
