# Tracker-intake vehicle, round 10: evidence pack

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-16 |
| Last modified | 2026-11-16T15:00:00Z |
| Status | active |
| Status summary | Round-10 answer to the round-9 review of `8f688bf1` (NO-GO, 7 blocking findings). PROVISIONAL: gate-logic evidence only, waiting for independent review |
| Author | round-10 structural fixer, Claude Opus 5.5 (subagent of the conductor), with one forked subagent for the re-mint half; effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289): the suites run the real lint, the real leak scan and the real re-mint tool on copies of the real database; nothing here is a live run of a deployed product |
| Base | vehicle head `8f688bf1` (round 9); landing target `origin/main` `f67d926c` |

## Table of contents

- [Findings, one by one](#findings-one-by-one)
- [Tests and mutants](#tests-and-mutants)
- [Three identical runs](#three-identical-runs)
- [Merge onto f67d926c](#merge-onto-f67d926c)
- [Older pack files](#older-pack-files)
- [Leak scan of the change](#leak-scan-of-the-change)
- [Operator questions](#operator-questions)
- [UNCONFIRMED and UNKNOWN](#unconfirmed-and-unknown)
- [Files](#files)

## Findings, one by one

| Finding | RED (on the broken artifact) | Fix | GREEN |
|---|---|---|---|
| 1 secret lookalikes (lint and scan) | `red/probe_v9_reviewer_on_v9.txt`: the reviewer's 40 positives against the round-9 lint and scan (18 and 12 missed) | the normalising front end of the lint (marks, fillers, confusables, escapes, base64, entities, a decoding fixpoint) and the line rules in `class_inventory.md` rows L36 to L52; the scan reads the same classes with its own code | `runs/probe_v9_reviewer_*.txt`: pos=40, lint_miss=0, scan_miss=0; `runs/census_*.txt`: 319,279 members, gap=0 fp=0 in all 17 classes |
| 2 surviving lint mutants XL2 to XL6, XL9, XL13 | the round-9 review's mutant run | fixture rows and the function contracts C1 to C9 of `tests/workable_items/test_secret_frontend.py` | `runs/lint_mutations_1.txt` to `_3.txt`: 247 mutants, all killed as declared; XL12 equivalent with evidence (`runs/equiv_XL12.txt`) |
| 3 rebound cross-references (CON-313/387/388 to CON-308), XR9 | `runs/remint_red_8f688bf1.txt` | cross-references classed by vehicle-id identity (SUPERSEDED, AMBIGUOUS, REBOUND), `--target-own` | `runs/remint_green_r10.txt`; XR9 killed (`runs/remint_mutations_r10.txt`) |
| 4 verify does not re-apply the dup rules | `runs/remint_red_suite_8f688bf1.txt` | one rule function shared by plan and verify; verify checks SHARED-PATH coverage and supersede backing | `runs/remint_suite_run1.txt` to `run3.txt`: pass=573 fail=0 |
| 5 annotation refusals untested, XR5 and XR8 | `runs/remint_red_suite_8f688bf1.txt` | the declaration refusals, each with a suite case | XR5, XR8 killed |
| 6 git-env census fails on the merged tree | `runs/gitenv_census_merged_red.txt`: 27 UNSCRUBBED, 24 UNCLASSIFIED | canonical scrubs in every round-10 file and in 27 older pack files; the v4 `.findings` files renamed `.findings.txt` (`historical_hardening.tsv`) | `runs/gitenv_census_merged_green.txt`: PASS, members=672, unscrubbed=0, unclassified=0 |
| 7 `remint_ids.py` reads ambient GIT_* | the sentinel case on the round-9 tool (`runs/remint_red_suite_8f688bf1.txt`) | every git call scrubbed; BLIND (rc 3) on a non-repository or a subdirectory under an ambient `GIT_DIR` | the sentinel is a suite case; G1 and G2 equivalent with evidence (`remint/equiv_git_scrub.txt`) |

The dup-resolution TSV (`remint/dup_resolution_f67d926c.tsv`) has three distinct rows for CON-407 and
CON-409 (CON-326/407, CON-328/409, CON-330/407) and a verdict for every SHARED-PATH pair.

## Tests and mutants

| Suite or harness | Result |
|---|---|
| `tests/workable_items/test_intake_lint.sh` | pass=373 fail=0 |
| `tests/workable_items/test_secret_shapes.py` | pass=435 fail=0, 413 rows |
| `tests/workable_items/test_secret_frontend.py` (new) | pass=39 fail=0 |
| `tests/workable_items/secret_shape_fixtures.py` self-check | rows=413 hit=264 problems=0 |
| `tools/leak_scan_test.py` | hit_rows=264 missed=0 own_spec_wrong=0 |
| `tools/secret_class_census.py` | gap=0 fp=0 in L36 to L52 |
| `tests/workable_items/test_intake_lint_mutations.sh` | 247 mutants, 3 equivalent (RV2, LR2, XL12), all killed |
| `tools/leak_scan_mutations.py` | mutants=61 bad=0 |
| `tests/workable_items/test_remint_ids.sh` | pass=573 fail=0 |
| `tests/workable_items/test_remint_branch_sweep.sh` | pass=42 fail=0 |
| `tests/workable_items/test_remint_ids_mutations.sh` | 229 mutants, 3 equivalent (RW2, G1, G2), all killed |

Own mutants: R10-1 to R10-20 (lint), the `r10_*` and `fix_*` scan mutants, T1 to T13 (re-mint).
The lint's 3-layer decoding closure is load-bearing: removing it changes 36 hit results
(`runs/equiv_CLOSURE0.txt`), and the scan's closure was removed because it was redundant (row B45).

Both secret suites now take the lint of the checkout when they get no argument, so the full-suite runner
can run them as entries (run alone before, `test_secret_shapes.py` exited 2 with a usage line).

## Three identical runs

`runs/determinism.txt` and `runs/determinism_heavy.txt`: every suite above ran three times on the same
tree; each has one distinct output hash. The re-mint suites are in `runs/remint_suite_run*.txt` and
`runs/remint_sweep_run*.txt` (hashes in the commit message of the re-mint half). The re-mint mutation harness ran
twice (`runs/remint_mutations_r10_first_4survivors.txt`, then the fix and the final `runs/remint_mutations_r10.txt`),
not three times on the final tree.

## Merge onto f67d926c

`runs/merge_sim.txt`: the round-10 tree merges onto `f67d926c` with six conflicts:

| File | Resolution for the lander |
|---|---|
| `docs/workable_items.db`, `docs/Issues.md`, `docs/Issues_Summary.md` | the re-mint replay (`remint/main_f67d926c/`: vehicle CON-299..CON-344 land as CON-412..CON-456, CON-339 on CON-313; verify 0 mismatches, validate OK for 421 items), then regenerate the documents |
| `config/full_suite_manifest.tsv` | the union of both sides (two adjacent pure insertions); `runs/manifest_on_merge.txt` |
| `docs/guides/full_suite_runner_guide.md` | `bash scripts/run_full_suite.sh --sync-guide` |
| `README.md` | the union of both link lists (the intake lint guide and main's SonarQube and hardening links) |

After the union, `--verify-manifest` has one remaining difference: the excluded set differs from
`config/full_suite_excluded.lock`. The new excluded rows are the ten older pack tools and the round-9
reviewer's mutant driver. **The fixer did not accept the lock change**; the lander accepts it after the
review GO with `bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change <reviewer>`.

## Older pack files

- The ten older pack tools that the manifest ran (v5 to v9 `leak_scan_mutations.py`,
  `ref_integrity_mutations.py`, v8 and v9 `leak_scan_test.py`) are excluded with a recorded reason: they
  read the shared fixtures or the live tree, which later rounds changed. Measured: v8 missed=98, v9
  missed=47, v10 missed=0 on the round-10 fixtures (`runs/old_pack_tools.txt`). The v5 to v7 tools were
  not run in this round.
- 27 older pack files got the canonical git-env scrub and 24 v4 `.findings` files were renamed
  `.findings.txt`; `historical_hardening.tsv` lists each with its sha256 before and after, and each pack's
  `SHA256SUMS` was updated (`sha256sum -c` passes for v2, v4 to v9).

## Leak scan of the change

`runs/leak_scan_diff.txt`: the added lines against `8f688bf1`; secret_hits=226, identity_hits=0. The hits
are the FAKE fixture values, the lint's own key lists, tool names and test output labels; each
non-fixture hit was read with its value masked. No real credential.

## Operator questions

Not decided here:

1. CON-387: restore CON-308's `created_at`?
2. CON-397: the Obsolete history rows.
3. The CON-383 UNDECIDED pairs.
4. The CON-328/CON-409 DISTINCT-but-similar verdict in the dup-resolution TSV.
5. The per-item `--target-own` and `--annotate-foreign` choices in `remint/main_f67d926c_args.txt`.
6. Acceptance of the excluded-set change (ten older pack tools and the reviewer driver), after review GO.

## UNCONFIRMED and UNKNOWN

- The round-9 review's speed note (about 7x slower than round 8 on a 40k-character line) is not
  reproduced; on the inputs measured here round 10 is within about 1.2x of round 9 (`runs/lint_cost.txt`).
- The false-positive count on the reviewer's 25 lookalikes is 4 for the lint (n04, n06, n18, n19, kept as
  hit rows B41 to B44 with a reason) and 11 for the scan, which is the broader second reader.
- Effort of the dispatches: UNKNOWN.

## Files

`SHA256SUMS` covers every file of this pack.
