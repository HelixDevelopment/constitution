# Tracker-intake vehicle, round 11: evidence pack

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-11-16 |
| Last modified | 2026-11-17T08:50:00Z |
| Status | active |
| Status summary | Round-11 structural answer to the round-10 review (NO-GO). PROVISIONAL: gate-logic evidence only, waiting for an independent review |
| Author | round-11 structural fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289): the suites run the real lint, the real leak scan and the real re-mint tool on copies of the real database; nothing here is a live run of a deployed product |
| Base | vehicle head `bd2ce259` (round 10); landing target `origin/main` `ebd8818c` (planned on `cb7008c4`, then `3e5e7e7d`, re-planned each time main moved; the vehicle now carries main up to `ebd8818c` by merge `b570e746`) |

## Table of contents

- [Findings, one by one](#findings-one-by-one)
- [Tests and mutants](#tests-and-mutants)
- [Two identical runs](#two-identical-runs)
- [Merge onto ebd8818c](#merge-onto-ebd8818c)
- [Older pack files](#older-pack-files)
- [Leak scan of the change](#leak-scan-of-the-change)
- [Operator questions](#operator-questions)
- [UNCONFIRMED and UNKNOWN](#unconfirmed-and-unknown)
- [Files](#files)

## Findings, one by one

The class inventory (`class_inventory.md`) was written before the fixes were closed (section 11.4.276(C)).

| Finding | RED (on the broken artifact) | Fix | GREEN |
|---|---|---|---|
| 1 secret shapes closed one at a time, in two readers | `red/r10review_probe_r10_reviewer.txt`: the reviewer's 51 positives and 25 negatives against round 10 (lint missed 25, scan missed 23, scan reported 2 negatives: `bypass=...`, `secretary=...`) | ONE shared primitive, `scripts/workable-items/secret_canon.py` (decode to a fixpoint, fold, words and joins, layout, value shape), read by the lint and by the leak scan; each keeps its own value-shape detectors | `runs/probe_r10_reviewer_on_v11.txt`: pos=51 lint_miss=0 scan_miss=0 neg=25 lint_fp=0 scan_fp=0; `runs/probe_r10_extra_on_v11.txt`: 15 of 15 read by both; `runs/census_r11.txt`: 319,279 members, gap=0 fp=0 |
| 2 surviving reviewer mutants | `red/r10review_rev_mutants_lint.txt`, `red/r10review_rev_mutants_scan.txt`, `red/r10review_rev_mutants_remint.txt` | adopted verbatim where their target text exists; a mutant whose target the rewrite removed is STALE and its intent is ported to the shared module (inventory rows M1, M2) | reviewer mutants of `red/r10review_rev_mutants_{lint,scan,remint}.txt` (round 10: lint 12 of 18 survived, scan 10 of 16, remint 5 of 13): M1 adopted verbatim, M2 ported, all killed in the merged-tree runs `runs/merged/lint_mut.{1,2}.txt` (296 mutants, 5 recorded equivalent: `runs/equiv_{RV2,LR2,XL12,LM2,LM15}.txt`, each 0 view and 0 hit differences over 2,743,655 corpus strings, 200,000 fuzz strings and every code point), `runs/merged/scan_mut.{1,2}.txt` (41 mutants, 33 of them canon mutants, bad=0) and `runs/merged/remint_mut.{1,2}.txt` (244 mutants, 3 recorded equivalent: RW2, G1, G2) |
| 3 the supersede backing checked by plan and verify separately | `red/r10review_rma_witness.txt` (VID=VID with SAME-DEFECT: plan accepts, verify refuses) | one check inside `dup_rule_errors()`, used by both, the same text (REFUSED / MISMATCH); guide `remint_ids_guide.md` revision 7 | `tests/workable_items/test_remint_ids.sh` case R11 (REV-SELF) plans, replays and verifies the witness; RM-e, RM-f, RM-g, RM-j each have a failing test (`runs/remint_mutations_r11_new.txt`: 18 mutants, all killed) |
| 4 the plan was made against an old main | `red/r10review_sim_bbdf4ac1.txt` | re-planned first against `3e5e7e7d` (max id CON-485): 56 new dup verdicts for CON-315..CON-328 against main's CON-416, CON-418, CON-419, CON-422 and CON-434, one for CON-307 against main's CON-451 (section 11.4.214: no SAME-DEFECT found, so nothing is linked as a duplicate; DISTINCT-but-similar pairs keep both); `--target-own` for main's CON-446 (names its own lander CON-299) and CON-478 (names its own CON-334 to CON-341) | `remint/main_3e5e7e7d/`: plan PLAN own=46 refusals=0 CON-486..CON-530, replay APPLIED 72 steps, verify PASS 0 mismatches, facts 5/5, validate OK 495 items, vehicle lint PASS 0 findings; landed lint FAIL 1 finding DUP-HEAD (see operator question 4). `remint/main_cb7008c4/` (CON-443..CON-487) and `remint/main_3e5e7e7d/` are earlier plans, superseded by `remint/main_ebd8818c/` (see [Merge onto ebd8818c](#merge-onto-ebd8818c)) |

Found while closing finding 1, each fixed at its cause and pinned by a contract of
`tests/workable_items/test_secret_canon.py` and a C mutant in both harnesses:

| Member | Cause | Contract | Mutant |
|---|---|---|---|
| `gcp-api-key 24, private-key 12` (a count list on the landed tracker) read as a key | a number joined to a key across a space | K3-number-gap | C25 |
| `https://<user>:<password>@<host>` read as a value | the URL reader skipped the placeholder rule (the scan's own URL detector too) | K6-url-placeholder | C26, C27, `r11_url_placeholder_read` |
| `PASS: case_one_a1b2` (a lint fixture negative) read as a value | the identifier shape allowed only letters-then-digits parts; a short key with a colon and an unquoted value is a census boundary | K6-ident-label, K5-short-colon-label | C28, C32 |
| `byPass=`, `oAuth=`, `bypwd=` read as keys (census) | the round-10 lint's join-negative words were lost in the rewrite | K4-join-negative | C29, C33 |
| `x bypwd=` read as the key `xbypwd` (census) | the suffix rules read forms joined across parts | K3-suffix-single | C30 |
| `password: kms:DB_PASSWORD` read as a value (census) | the reference rule listed schemes | K6-ref-name | C31 |

## Tests and mutants

| Suite or harness | Result |
|---|---|
| `tests/workable_items/test_secret_canon.py` (shared primitive contracts) | 43 / 0 |
| `tests/workable_items/test_secret_shapes_r11.py` (reviewer rows) | 91 / 0 |
| `tests/workable_items/test_secret_shapes.py` | 435 / 0 |
| `tests/workable_items/test_secret_frontend.py` | 50 / 0 |
| `tests/workable_items/secret_shape_fixtures.py` self-check | 413 rows, problems=0 |
| `tools/leak_scan_test.py` (round 11) | hit_rows=264 missed=0 own_spec_wrong=0 r11_wrong=0 |
| v10 `tools/leak_scan_test.py` on round-11 fixtures | hit_rows=264 missed=0 |
| `tools/secret_class_census.py` | 319,279 members, gap=0 fp=0 |
| `probes/probe_r10_reviewer.py` | pos=51 lint_miss=0 scan_miss=0 neg=25 lint_fp=0 scan_fp=0 |
| `probes/probe_r10_extra.py` | 15 of 15 read by both readers |
| `tests/workable_items/test_intake_lint.sh` | 375 / 0 |
| `tests/workable_items/test_intake_lint_mutations.sh` | 296 mutants, 5 equivalent, all killed as declared |
| `tools/leak_scan_mutations.py` | 41 mutants (33 canon), bad=0 |
| `tests/workable_items/test_remint_ids.sh` | 585 / 0 |
| `tests/workable_items/test_remint_branch_sweep.sh` | 42 / 0 |
| `tests/workable_items/test_remint_ids_mutations.sh` | 244 mutants, 3 equivalent, all killed |
| git-env census (`scripts/validation/git_env_class_census.py`) | PASS members=715 unscrubbed=0 (`runs/gitenv_census_merged.txt`) |
| gate-ledger ratchet | PASS at 394 (`runs/gate_ledger_ratchet.txt`) |
| constitution index fresh | PASS (`runs/index_fresh.txt`) |
| engine `validate` / `diff` (vehicle database) | OK 309 items; DB and Markdown in sync (`runs/engine_validate.txt`, `runs/engine_diff.txt`) |
| `run_full_suite.sh --verify-manifest` | MANIFEST-MISMATCH, 1 problem: the excluded-set change (see [Older pack files](#older-pack-files)); nothing else (`runs/manifest_on_merge.txt`) |

Every row was run on the merged tree (after `b570e746`), twice; logs in `runs/merged/<step>.{1,2}.txt`.

## Two identical runs

`tools/determinism.py` compares each pair after removing clock times, dates, mktemp suffixes and
durations, and falls back to a verdict projection (the first two words of every line and every RESULT
line) when the text still differs. Result `runs/merged/determinism.txt`: 16 pairs, 15 byte-identical after
normalisation, 1 (`remint_mut`) differs only in run clocks and mktemp names that the harness cuts at a fixed
width (same verdicts on every line), verdict_differ=0.

Two pairs were re-run after late fixes, and the older runs are kept as RED: `remint_suite` (581/2 on the
merged tree before the fixture change, `red/remint_suite_created_at_engine_fixed_red.txt`) and
`remint_mut` (its control failed for the same reason).

## Merge onto ebd8818c

Main moved twice during the round. `b570e746` merges `origin/main` `ebd8818c` into the vehicle (README
link list and manifest rows unioned with `work`-side tools, the guide regenerated with `--sync-guide`; the
tracker database and its Markdown are the vehicle side, so the replay starts from the vehicle `V`).
`eab6d0f1` re-plans against `ebd8818c`:

- `remint/dup_resolution_ebd8818c.tsv`: 197 verdicts (154 DISTINCT, 30 DISTINCT-but-similar, 13
  UNDECIDED; no SAME-DEFECT, so nothing is linked as a duplicate, section 11.4.214). New against main's
  CON-443, CON-491, CON-492, CON-493, CON-515, CON-516, CON-517, CON-520 and CON-521; CON-311 against
  main's CON-098 is UNDECIDED.
- `remint/main_ebd8818c_args.txt`: `--target-own CON-486=CON-299,CON-312,CON-313,CON-314`,
  `--target-own CON-516=CON-310`, `--resolve CON-243=vehicle`, `--resolve CON-262=vehicle`; CON-262's
  description in the vehicle database is main's text plus the vehicle's added paragraphs (one engine
  `update`), so `=vehicle` keeps both.
- Result `remint/main_ebd8818c/`: plan PLAN own=46 base_changes=3 steps=72 conflicts=0 refusals=0,
  CON-527..CON-571 (umbrella CON-299 lands as CON-527); replay APPLIED 72 steps; verify PASS 49 items 0
  mismatches (46 KNOWN); facts 5/5; validate OK 536 items; vehicle lint PASS 0 findings; landed lint FAIL
  1 finding DUP-HEAD CON-536 (operator question 4); landed-touched lint NEW=0 REMOVED=4.

Merged-tree fixes found by running everything after the merge (`ffda6a9b`, `ff10e15d`):

- the git-env census failed (unscrubbed=5): `intake_lint.py`'s scrub line was not directly after its
  imports; four files that run no git got `no-git-execution` rows;
- one manifest note used the category `data module:` instead of `data:`;
- the leak scan's `--diff` crashed on main's non-UTF-8 content (RED/GREEN pair and a paired mutant);
- main's CON-313 engine fix (keeps `created_at` on close) made two remint cases fail; the fixture now
  models a vehicle made by the older engine, and a new case pins the fixed-engine path.

## Older pack files

- The round-10 tools (`docs/qa/tracker_intake_2026_11_16_v10/tools/leak_scan_test.py`) still pass on
  the round-11 fixtures: hit_rows=264 missed=0.
- The v6 and v7 `leak_scan_mutations.py` and the v8 `leak_scan_test.py` stay excluded with their
  recorded reason (operator decision: accept after the review GO).
- `historical_hardening` of round 10 unchanged (51 of 51).

## Leak scan of the change

`runs/leak_scan_diff.txt` (masked: file, line, kind and length only; control needles PASS on every run).

- Against `ebd8818c` (what landing adds): secret_hits=695 identity_hits=134. By file, the secret hits
  are in the shape fixtures, tests, census, probes, scan tools and mutation logs of rounds 2 to 11, all of
  which carry FAKE values by design; they were grouped by file and kind, not read line by line
  (UNCONFIRMED that every one is fake). The identity hits: 133 in the packs of rounds 1, 3 and 4
  (`tracker_intake_2026_11_12`, `_v3`, `_v4`: the operator's home path and user name in captured logs)
  and 1 in `docs/Issues.md` (CON-229's waiver authoriser, already on main at that line's old position).
  None is in a round-11 file. The 133 older-pack hits land on main with the vehicle: operator question 5.
- Against the round-10 head `bd2ce259`: 1016 / 3620; this diff includes main's own content brought in by
  the merge (the largest files are main's older QA packs), so it is not the landing view.
- The staged round-11 fix commit alone: secret_hits=13 identity_hits=0 (fake values in the lint mutation
  logs, the same lines as the reviewed `runs/lint_mutations_1.txt`, and the fake Latin-1 test row).

## Operator questions

Not decided here:

1. Main's CON-416 says the landed fix already pins `--hostname`, prints no server text raw and updated
   the census rows. The vehicle items CON-315, CON-324, CON-325, CON-326 and CON-327 are review
   findings on that change; they are DISTINCT-but-similar to CON-416 in the dup TSV (not the same
   defect), but some may already be addressed on main. The lander or the operator decides whether to
   re-check them after landing.
2. The 20 DISTINCT-but-similar verdicts and the remaining questions of round 10 (CON-387 `created_at`,
   CON-397 history rows, the CON-383 UNDECIDED pairs, the per-item `--target-own` and
   `--annotate-foreign` choices in `remint/main_cb7008c4_args.txt`).
3. Acceptance of the excluded-set change, after the review GO: 12 files (the v5, v6 and v7 `leak_scan_mutations.py` and `ref_integrity_mutations.py`, the v8 and v9 `leak_scan_mutations.py` and `leak_scan_test.py`, the v10 `rev_mutants_v9_reviewer.py`, and `tests/workable_items/secret_shape_fixtures_r11.py`); the fixer does not run `--accept-excluded-change`.
4. Main's open CON-445 (codegraph suite: a SKIP invisible in SUMMARY, an unexpected SKIP exits 0) names
   CON-262 as an UNDECIDED candidate duplicate. The vehicle closes its CON-308 (lands as CON-536) as
   SAME-DEFECT of CON-262 by the operator decision of 2026-11-13, so the landed lint reports DUP-HEAD
   (CON-262 may have a second open head). Not decided here: whether CON-445 is the same defect as CON-262
   (link and close), distinct (record DISTINCT), or stays UNDECIDED with the finding accepted at landing.
5. The packs of rounds 1, 3 and 4 hold 133 identity hits (home path and user name in captured logs). Land
   them as they are, mask them first, or drop those logs (section 11.4.122: not removed without a decision).
6. `--resolve CON-243=vehicle` lands the vehicle's CON-243 over main's state (main has it In progress).
   Confirm, or re-plan with `=target`.
7. CON-311 against main's CON-098 is UNDECIDED in the dup TSV.
8. The remint KNOWN text still says "KNOWN engine defect: close rewrites it". With main's fixed engine
   that path only fires for vehicles made with the older engine; reword it, or keep it as the historical
   name.

## UNCONFIRMED and UNKNOWN

- The `Roadmap-Item: CON-527` trailer names the vehicle umbrella CON-299 under its re-minted id in plan
  `main_ebd8818c`, a PLANNED id; if main moves before landing, the lander re-mints it with the rest of the
  plan. The round-11 commit `0776fff6` names CON-486, which is now main's own item; `eab6d0f1` records
  the correction (history is not rewritten, section 11.4.113).
- The equivalence runs (`runs/equiv_*.txt`) were made before the merge, on the round-11 tree; the merged
  tree's mutation runs re-check the same declared equivalents only by their recorded run.
- 16 canon mutants are killed only through the shared contract suite, not by the scan's own fixtures
  (inventory row M4).
- The equivalence evidence is gate-logic: views and rule names compared on every census member, every
  fixture row, 200000 seeded strings and every code point; it does not prove equivalence on every input.
- Effort of the dispatch: UNKNOWN.

## Files

`SHA256SUMS` covers every file of this pack.
