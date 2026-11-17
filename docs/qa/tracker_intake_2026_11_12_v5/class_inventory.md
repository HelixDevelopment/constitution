# Tracker-intake vehicle, round 5: class inventory

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-11-13 |
| Last modified | 2026-11-14T05:38:21Z |
| Status | active |
| Status summary | The classes behind the round-4 findings R4-1 to R4-9, enumerated before the round-5 fix was written (section 11.4.276(C)). Each member names the rule that closes it, its test, or the evidence-backed reason it stays open. |
| Author | round-5 structural fixer, Claude Opus 5.5 (subagent of the conductor) |
| Evidence class | gate-logic only (section 11.4.289) |

## Table of contents

- [How the inventory was built](#how-the-inventory-was-built)
- [M. Merge: every unit a landing can write for a base item both sides changed (R4-1)](#m-merge-every-unit-a-landing-can-write-for-a-base-item-both-sides-changed-r4-1)
- [R. Ranges: every way two ids can be written as a range (R4-4)](#r-ranges-every-way-two-ids-can-be-written-as-a-range-r4-4)
- [D. Digits: every place an id is read (R4-5)](#d-digits-every-place-an-id-is-read-r4-5)
- [L. Lint coverage (R4-3, R4-6)](#l-lint-coverage-r4-3-r4-6)
- [S. Database openers (R4-9)](#s-database-openers-r4-9)
- [E. Recorded commands (R4-7, R4-8)](#e-recorded-commands-r4-7-r4-8)
- [T. Test coverage of the planner, replay and oracle (R4-2)](#t-test-coverage-of-the-planner-replay-and-oracle-r4-2)
- [K. Values the replay passes as written (found by the branch sweep)](#k-values-the-replay-passes-as-written-found-by-the-branch-sweep)
- [B. Defects the branch sweep found](#b-defects-the-branch-sweep-found)

## How the inventory was built

- Merge units: read from `make_plan` and `cmd_verify` in `scripts/workable-items/remint_ids.py`
  at b48091ea, and from the `items` columns (`pragma table_info(items)`, 38 columns, the same on base
  02c10935, the vehicle and fix227 round 11). The round-5 `verify` refuses (BLIND, exit 3) when its
  own unit list (`V_UNITS`) does not partition the 38 columns, so a new column cannot go uncompared.
- Ranges: every connector a writer can put between two ids, collected from the review's probe p04,
  the Unicode dash punctuation block (U+2010..U+2015), the minus sign, the two-em and three-em dashes,
  the small and fullwidth hyphen-minus forms, the wave dash, and the English range words.
- Digits: every regular expression in `remint_ids.py` and `intake_lint.py` that reads an id, found
  with `grep -n '\\d' scripts/workable-items/remint_ids.py scripts/workable-items/intake_lint.py`
  (control needle: the same command finds the `uni` pattern, which keeps `\d` on purpose).
- Lint: the review's probes p06 and p11, the Unicode category Cf (format characters), and the
  credential shapes of `SECRET_PATTERNS`.
- Openers: every `sqlite3.connect` in the files this vehicle adds or changes
  (`grep -rn 'sqlite3.connect' scripts/workable-items/*.py docs/qa/tracker_intake_2026_11_12_v5`).
- Branches: `tests/workable_items/remint_branch_sweep.py --list` (the ast of `remint_ids.py`).

## M. Merge: every unit a landing can write for a base item both sides changed (R4-1)

A unit is one update column (title, description, type, severity, created_by, assigned_to), one state
block (its columns together with its `_updated_at` and `_updated_by` stamps), or the lifecycle
(status, current_location, obsolete_details). "V", "B", "T", "R" = the vehicle, base, target and
landed databases.

| # | Member | Round-4 behaviour | Round-5 rule | Test |
|---|---|---|---|---|
| M1 | A column only V changed | V's value, text through the map | unchanged | `R4-1a: the vehicle's title (rewritten) and severity are passed` |
| M2 | A text column only T changed | re-pointed through the vehicle's map (R4-1a, p02) | T's text, never through the map; when an update step is needed, `--description` carries T's text verbatim | `R4-1a: the target's description is passed verbatim`, `R4-1a: landed values`, `R4-1a: verify FAIL when the target's text is re-pointed through the map` (the p02 shape) |
| M3 | A column both changed to the same landed value | conflict | converged, T's value kept, no write | `a title both sides changed the same way (after the map) converges`, `the converged title is not written, the severity is` |
| M4 | A column both changed differently | conflict | conflict (unchanged) | `conflict: both sides changed one column` |
| M5 | A block only V changed | V's block | unchanged | the round-4 landing cases (`landed: ...`) |
| M6 | A block only T changed, a column or a stamp | V's whole block written over T's (R4-1b, p03) | T's block kept; a stamp-only T change counts as a change of the block | `a target stamp-only change on another block merges`, `verify of the stamp-only merge keeps the target's stamp` |
| M7 | A block both changed, differently | merged silently (R4-1b) | conflict | `R4-1b: both sides changed one state block (other columns) is a CONFLICT` (the p03 shape), `R4-1b: a target stamp change on a block the vehicle changed is a CONFLICT`, `a block both changed to the same content with other stamps is a CONFLICT` |
| M8 | A block both changed to the same content and stamps | merged | converged, T's block kept | `R4-1b: the same block change on both sides converges (nothing to write)` |
| M9 | A block both changed to the same content, other stamps, `--resolve vehicle` | not reached | refused, names `=target` (the engine stamps a block only when its content changes, so V's stamps cannot land; found by `verify` in round 5) | `--resolve vehicle of a same-content block with other stamps is refused`, `verify: the target's block and stamps stay` |
| M10 | A lifecycle change on one side, any change on the other | conflict, but untested (RV7a) | conflict | `RV7a: a vehicle lifecycle change and a target change is a CONFLICT` (the p12 shape), `conflict: a lifecycle change on one side and a change on the other` |
| M11 | `obsolete_details` changed on both sides | conflict | conflict in both cases: a lifecycle unit changed on one side and anything changed on the other is a conflict (M10's rule), even when both rows are equal; the CONFLICT line says `both changed obsolete_details` when the rows differ and `a lifecycle change on one side and a change on the other` when they are equal. (Revision 1 of this inventory said "converged when equal"; the branch sweep showed the equal case had no case, and the case written for it showed the conflict.) | `plan against a target that changed the same obsolete_details row`, `plan against a target that made the vehicle's obsolete_details change`, `verify FAIL: an obsolete_details row the vehicle did not write` |
| M12 | `--resolve ID=target` | the whole target item | unchanged | `--resolve target`, `R4-1b: --resolve target`, their replay and verify cases |
| M13 | `--resolve ID=vehicle` | V's whole item | V's value for the conflicting units, T's for the units only T changed | `--resolve vehicle`, `R4-1b: --resolve vehicle lands the vehicle's whole block and stamps`, `verify of --resolve vehicle on a lifecycle conflict`; `--resolve vehicle keeps the unit only the target changed (M13)`, `verify FAIL: a unit only the target changed, landed wrong under --resolve vehicle (M13)` (added after the branch sweep; revision 1 said this unit had no case of its own) |
| M14 | `verify` reading of each unit | one comparison for the columns V did not change (RV1 removed it silently) | each unit is checked against the side it must land from; an unresolved conflict is a mismatch; the unit list must partition the columns | `verify FAIL: a column conflict whose --resolve vehicle is stripped` and the three other stripped-plan cases, `verify FAIL: a vehicle-side column landed wrong`, the RV1/RV5/RV6 needles; RV1 adopted as a mutant |

Not a merge member: `body_md`, `created_at` and `last_modified` are derived or not carried; `verify`
reports them as KNOWN (section "NOT CARRIED" of the tool's docstring).

## R. Ranges: every way two ids can be written as a range (R4-4)

| # | Form | Round-4 behaviour | Round-5 rule |
|---|---|---|---|
| R1 | `P-a..P-b`, tight en dash `P-a–P-b` | one token, rules checked | unchanged |
| R2 | spaced en dash, em dash, the other dashes U+2010..U+2015, U+2212, U+2E3A, U+2E3B, U+FE58, U+FE63, U+FF0D, tight or spaced | the second id rewritten alone (spaced en dash: `replaced=1`, p04) | the range rules are checked; the ids are rewritten one by one only when the range is wholly moved |
| R3 | `...`, `…`, `~`, wave dash U+301C | not seen | as R2 |
| R4 | spaced hyphen `P-a - P-b`, `P-a -- P-b` | not seen | as R2 |
| R5 | tight hyphen `P-a-P-b` | the first id left, the second rewritten | refused when it holds a moved id (it is never rewritten; write `..`) |
| R6 | `to`, `through`, `thru`, `till`, `until` (any case) | rewritten per id (documented as B11 in round 4) | as R2 |
| R7 | `between P-a and P-b` | rewritten per id | as R2 |
| R8 | `P-a and P-b` without `between` | a list | a list (unchanged); tested as the false-positive guard |
| R9 | A chain `P-a to P-b to P-c` | not seen | each adjacent pair is checked |
| R10 | A short-form or reverse loose range of moved ids | not seen | refused, as for R1 |
| R11 | A chain of tight ranges `P-a..P-b..P-c` or `P-a–P-b–P-c` | the second pair never checked: the chain was rewritten even when that pair was partly moved | each adjacent pair is checked, as R9 (found by the branch sweep in round 5, after the first version of this inventory: the round-5 `_checks` still skipped tight pairs; RED `red/remint_suite_on_pre_chainfix.txt`, three cases; `verify` already read every pair) |

`verify` checks the same rules with its own pattern (`v_text_rules`, written apart from the
Rewriter), so a planner that let a loose range through is caught. Open: the planner reads text line
by line, so a range written across a line break is not read as a range, and neither is an open-ended
form ("up to P-n", "P-n onwards") or a connector outside the read set; such ids are rewritten one by
one. A live scan (`tools/range_scan.py`, its own patterns and control needles; output
`runs/range_scan.txt`) over the tracked files and the four databases (base, vehicle, fix227 round 11,
main) found, for the moved ids CON-299..CON-342:
- in the four databases (the text a replay rewrites): no cross-line form, no open-ended form and no
  pair joined by an unread connector that names a moved id (the 158 open-ended hits per database are
  "main owns up to CON-145"-style notes about ids that do not move);
- in the tracked files: two cross-line hits naming a moved id, both a truncated id followed by an
  ellipsis in a round-2 inventory table (`CON-29...` then `CON-330` on the next row), not a range;
  378 pair hits naming a moved id, joined by table bars, list literals, escaped commas, arrows and
  prose ("changed to", "closed onto"), counted by connector in the scan. 201 of them are in this
  directory's own files (its records, plans and tools); the other tracked files hold 177
  (both counts measured by running the same scan on the two file lists separately).
The scan cannot tell a range from prose; reading these hits as "not a range" is this author's
reading, UNCONFIRMED by an independent reader.

## D. Digits: every place an id is read (R4-5)

| # | Reader | Round-4 | Round-5 |
|---|---|---|---|
| D1 | planner own-id set | `\d` (fullwidth own id mapped) | `[0-9]`; a non-ASCII own id is refused by name |
| D2 | map file, `--resolve`, `--foreign-ids`, Foreign ids lines | `\d` | `[0-9]` |
| D3 | Rewriter tokens and ranges | `\d` | `[0-9]`; a moved id written in non-ASCII digits is refused |
| D4 | `verify` (own set, split, expectations, foreign reading) | `\d` | `[0-9]`; `v_text_rules` reports a moved id in non-ASCII digits |
| D5 | lint id references | `\d` | `[0-9]`; an id in non-ASCII digits is XREF-DANGLING `(non-ASCII digits)` |
| D6 | An id split by a format character (`P-29​9`) | not seen | NOT rewritten (it is not an id to any reader); lint reports CONTROL-CHAR and XREF-DANGLING `P-29`. Documented limit. |
| D7 | The engine accepts non-ASCII ids | engine debt | out of scope (review R4-5); unchanged |

## L. Lint coverage (R4-3, R4-6)

| # | Member | Round-4 | Round-5 |
|---|---|---|---|
| L1 | quoted password assignment | SECRET | unchanged |
| L2 | unquoted `PASSWORD=`, `secret=`, `api_key=`, `token=` (any case, any name ending so) | missed | SECRET |
| L3 | `Authorization: Basic <base64>` | missed | SECRET |
| L4 | C0/C1 controls, U+2028, U+2029, NUL | CONTROL-CHAR | unchanged |
| L5 | bidi embeddings, overrides and isolates (U+202A..U+202E, U+2066..U+2069), U+200E, U+200F | missed | CONTROL-CHAR (Unicode category Cf) |
| L6 | BOM U+FEFF, soft hyphen U+00AD, zero-width U+200B..U+200D, word joiner U+2060 | missed (U+200B caught indirectly) | CONTROL-CHAR (category Cf; the finding names the first one) |
| L7 | lines after a non-item `## ` heading (LV4) | attributed to none, untested | tested: a home path under "## Reviewer notes" is not reported against the item above |
| L8 | an item with two location rows (LV6) | only the first row linted | every row linted; findings of an extra row carry `[<location> row]` |
| L9 | WAL sidecar | not checked | BLIND, exit 3 |

## S. Database openers (R4-9)

| # | Opener | Round-5 |
|---|---|---|
| S1 | `remint_ids.py` `ro()` (plan, verify, rewrite, refs) | quoted absolute path; a non-empty `-wal` is refused |
| S2 | `remint_ids.py` replay's target copy | refuses a non-empty `-wal` (unchanged) |
| S3 | `intake_lint.py` | quoted absolute path; a non-empty `-wal` is BLIND |
| S4 | `tools/landing_facts.py`, `tools/tdiff3.py` (this directory) | quoted absolute path |
| S5 | `apply_v5.py` (this directory) | quoted absolute path; a non-empty `-wal` is refused |
| S6 | round-4 evidence scripts (`docs/qa/tracker_intake_2026_11_12_v4/apply_v4.py`, its tools) | unchanged: captured history, not run again |

## E. Recorded commands (R4-7, R4-8)

| # | Member | Round-5 |
|---|---|---|
| E1 | `final_lint.txt` header | each command is printed with `printf %q` from the argv that runs (`show_run` in `make_evidence.sh`) |
| E2 | red command preconditions | `engine_repro.sh` checks `HELIX_RELEASE_PREFIX` against the id prefix, the Type Task of `<open>` and `<probe>`, and the Obsolete state of `<obsolete>`, and exits 3 when one fails; `engine_repro_check.sh` tests each refusal and the full run (RED on the round-4 script: 6 of 10 cases fail) |
| E3 | the six items' records | red command, evidence and env name the round-5 script, the prefix and the Types (`apply_v5.py`, log `apply_v5.log`) |

## T. Test coverage of the planner, replay and oracle (R4-2)

| # | Member | Round-5 |
|---|---|---|
| T1 | the reviewer's mutants RV1..RV7b | adopted in `test_remint_ids_mutations.sh` |
| T2 | the author's round-4 mutants | kept, re-run |
| T3 | every branch point of the planner, replay and oracle | `remint_branch_sweep.py`: each condition forced True and False; a survivor is accepted only with a written reason in `remint_branch_equivalents.tsv`. Run on the final inputs (`runs/branch_sweep.tsv`): 426 mutants after the control passed, 418 killed, 8 registered equivalent, 0 survived, 2 `while True` loops skipped by design; the six earlier runs and what their survivors became are in the README's "Branch sweep". |
| T4 | `verify`'s own control needles | extended with the loose-range, digit and hyphen cases (`verify_needles`) |

## K. Values the replay passes as written (found by the branch sweep)

The branch sweep showed that `block_steps` passed a block's evidence columns to the engine without
reading them (forcing `c in TEXT_REWRITE` to False survived, and so did forcing it to True). The
class is every vehicle value the replay hands to the engine without rewriting it. Each member now
goes through `Rewriter.keep`, which refuses the value when it names an id the map moves (in a path
or not) and keeps it when the id is declared foreign for the item. Members found by reading every
argv the planner builds in `scripts/workable-items/remint_ids.py` (control needle: the same reading
finds the rewritten `--title`, `--description` and block text columns, which go through
`Rewriter.text` instead).

| # | Member | Before round 5 | Round 5 | Test |
|---|---|---|---|---|
| K1 | a block's non-text columns (state, surface, evidence paths, env) | passed as written; a moved id in an evidence path passed the plan and only verify failed | `keep` | `an evidence path naming a moved id`, `an evidence value that is a moved id` |
| K2 | a block's author and time stamp | passed as written; an empty time stamp was dropped (`if at:`), so the landed block carried the replay's time | `keep`; the time stamp is always passed, an empty one stays empty (the engine stores it as NULL) | `a block author naming a moved id`, `plan of a block with an empty stamp`, `landed: the empty stamp`, `verify of the empty-stamp block` |
| K3 | a closure's evidence | passed as written | `keep` | `a closure evidence path naming a moved id` |
| K4 | a Reopened row's reason, author, date and incident | passed as written | `keep` | `a reopen incident path naming a moved id` |
| K5 | `obsolete_details` since, reason and evidence (`superseding` is mapped) | passed as written | `keep` | `an obsolete_details evidence path naming a moved id` |
| K6 | a status word (`update --status`) | passed as written | `keep`; unreachable in practice: the engine accepts only its status vocabulary, which names no id | none (honest gap: no engine command writes an id into a status) |
| K7 | a base item's type, severity, author and assignee | passed as written | `keep` | `a base assignee naming a moved id` |
| K8 | an own item's type, severity, author and assignee | passed as written | `keep` | `an own assignee naming a moved id` |
| K9 | an id the item declares foreign | kept | kept (unchanged) | `plan of an evidence path naming an id the item declares foreign`, `landed: the foreign evidence path as written`, `verify of the foreign evidence path` |

## B. Defects the branch sweep found

The sweep (`tests/workable_items/remint_branch_sweep.py`) forces each branch of the planner, the
replay and verify True and False and runs the suite on each mutant. A survivor is either a branch no
case reads (a case was written), a branch whose two values give the same result (registered in
`remint_branch_equivalents.tsv` with the reason), or a defect. The defects:

| # | Defect | Fix | RED | GREEN |
|---|---|---|---|---|
| B1 | a tight chain `P-1..P-2..P-3` was rewritten while its second pair was partly moved (`rng.finditer` does not overlap, so the pair `P-2..P-3` was never checked) | `_checks` reads the tight `..` and en dash forms too, pair by pair with overlap | `red/remint_suite_on_pre_chainfix.txt` (the suite on `red/remint_ids_pre_chainfix.py.txt`) | `runs/remint_suite.txt` |
| B2 | a value passed as written (section K) that names a moved id passed the plan; only verify failed | `Rewriter.keep` at every site of section K | `red/remint_suite_on_pre_keep.txt` (the suite on the source before `keep`) | `runs/remint_suite.txt` |
| B3 | a block whose time stamp the vehicle left empty landed with the replay's time | the stamp is always passed | `red/remint_suite_on_pre_keep.txt` | `runs/remint_suite.txt` |
| B4 | the sweep itself reported every mutant KILLED when the suite failed on every input, and its setup errors (a missing source or suite, a bad register line, a span that does not parse back) exited 1 or crashed instead of exiting 2 | a control run on the unmutated source before any mutant; a failed control and every setup error exit 2 as `setup: ...` | `red/branch_sweep_suite_on_pre_fix.txt` (the sweep's suite on `red/remint_branch_sweep_pre_fix.py.txt`: 7 of 42 fail) | `runs/branch_sweep_suite.txt` (42 of 42); mutants SW1, SW14 |
| B5 | the sweep took the parser's byte offsets as character offsets, so a condition after a non-ASCII character on its line was cut at the wrong place (the mutant did not compile and was reported SETUP) | the offsets converted to characters; the span must parse back to the very condition, or the sweep stops (the span control needle) | the two SETUP verdicts of `runs/branch_sweep_partial_bytebug.txt` (its inputs were not recorded) | the sweep suite's cases `list: a condition after a non-ASCII character on its line keeps its exact key` and `needle: a span taken from byte offsets as characters is a setup error`; mutants SW9, SW13 |
| B6 | a moved range inside a path (`docs/qa/CON-5..CON-7/x.txt`, `CON-5–CON-7.md`) was rewritten: the path rule was checked for single ids only, so the range pattern rewrote it (the reviewer's mutant RV3, which drops the en dash from the range pattern, survived the earlier suite because that form made a difference only inside a path, where the mutant refused what the tool rewrote) | one `in_path()` rule for ids and ranges; a moved range in a path is refused, a range of ids that do not move is left as written | `red/remint_suite_on_pre_finalsweep.txt` (the final suite on `red/remint_ids_pre_finalsweep.py.txt`) | `runs/remint_suite.txt`; mutants N48, X42, RV3 |
| B7 | `verify` certified a plan that lists conflicts or refusals (the planner never called it landable) | `verify` refuses such a plan before it reads a database | as B6 | `runs/remint_suite.txt`; mutant N49 |
| B8 | `verify` let a new vehicle id outside the prefix pass when a plan's refusals were removed (it read the own set through the prefix pattern and dropped the id silently) | each new vehicle id that is not the prefix and ASCII digits is a mismatch of its own | as B6 | `runs/remint_suite.txt`; mutants N50, N51 |
| B9 | a defect of the suite: its engine-fact case compared `item_history.created_at`, a wall-clock stamp, so it failed when two engine runs fell in different seconds (seven KILLED verdicts of sweep run 5 came from this case alone; with the case fixed, run 6 found four of those mutants surviving, one registered equivalent, and two killed by other cases) | the case leaves every wall-clock column out (history `occurred_at`, `created_at`, `on_date`) | `red/engine_fact_flake.txt` (two adds 1.5 s apart: the old comparison reports `created_at`, the new one `same`) | the same file; `runs/remint_suite.txt` twice, byte-identical |
| B10 | a vehicle that removed a base item's `obsolete_details` row got no step (no engine command removes one; only a raw edit of the vehicle can do it), so the landing kept the row and only verify noticed | the planner refuses it: `REFUSED <id>: the vehicle removed the obsolete_details row; no engine command removes one` | `red/remint_suite_on_pre_finalsweep.txt` (case `plan refusal: the vehicle removed a base item's obsolete_details row`) | `runs/remint_suite.txt`; mutant N78 |

The fifth sweep run (`runs/branch_sweep_run5.txt`: the complete run on the source before B6 to B8
and B10, 35 survivors; B6 to B8 came from it) also found branches no case read (no defect behind
them): verify's referent check,
a plan map entry that is not a pair, replay's stop at a failing step, verify's two self-checks, its
text rules on ranges, and each branch of its shared-item loop (an item nobody changed with two rows,
an item whose only change is a time stamp, a replayed item that landed as two rows, a column outside
the rewrite set equal only under the map, the target's obsolete_details change, a base or untouched
item's obsolete_details row, an own item's created_at). Each has a case now and a mutant (N52..N71).
The same run found these, each with a case now and a mutant (N72..N88): verify's segment
check (read only with `--require-segments`), its untouched-item control (BLIND when the landing
replayed every target item), `check_od`'s side naming and its case of no row on either side,
`check_history`'s closure evidence, its last Reopened row, its missing closure row and its lifecycle
counts, the inner test of the referent check (title, type and author of the item an id names), and
the plan file a refused plan never writes. One of them led to
B10 (N78), and one survivor was registered as equivalent
(`v_compare|if|len(tk_w) != len(tk_g)#1=False`, with its reason in the register).

The sixth sweep run (`runs/branch_sweep_run6.txt`: complete, on the final source, with the suite and the register before the cases and the entry for its survivors) found
four survivors, all four mutants that run 5 had counted killed only through the flaky engine-fact
case (B9): FAST-FORWARD verify's id-set check and its table check, the CON-339 note a created_at
MISMATCH must not carry, and verify's guard before `check_od` for an own item. The first three have
cases now and mutants (N89..N91); the last is registered as equivalent (`check_od` returns at once
when neither side has a row), and a suite case checks that fact on every run.

An engine defect was found on the way and is not a defect of this vehicle: `update --severity`
changes the column but leaves the `**Severity:**` line of `body_md`. It is pinned by the
characterization case `verify FAIL: the engine's stale Severity line in the vehicle body is not
certified` and is owed to the conductor (not registered in the tracker by this round).
