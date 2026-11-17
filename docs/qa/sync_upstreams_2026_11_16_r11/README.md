# Sync-all-upstreams — review round 11 evidence

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-11-16 |
| Last modified | 2026-11-16 |
| Status | PROVISIONAL (§11.4.290); pending independent review |
| Evidence class | gate-logic / unit-class (§11.4.289): real git against real bare repositories in scratch directories; no forge, no network remote |
| Roadmap item | CON-PENDINGsync3 (re-minted in this round from the placeholder `CON-PENDING-sync-r8`; commit trailers keep the placeholder spelling) |
| Follow-ups filed | CON-PENDINGsync1 (work-tree-only failed write, RV10-4), CON-PENDINGsync2 (defaults per the 2026-11-14 decision, RV10-6) |
| Prior review | round 10, `review_sync_r10.md` sha256 `7d98dbd4…` (NO-GO, findings RV10-1..RV10-8) |
| Base | `origin/main` 09d3ad2f (merged into the vehicle: `merge/merge_record.txt`) |
| Producer | fresh structural fixer (not the round-10 author, not the reviewer), Opus; effort UNKNOWN |

## Table of contents

- [Findings and fixes](#findings-and-fixes)
- [RED before, GREEN after](#red-before-green-after)
- [Mutants](#mutants)
- [Runs](#runs)
- [Tracker](#tracker)
- [Limits stated](#limits-stated)
- [Files](#files)

## Findings and fixes

| Finding | Fix (class-wide, §11.4.276(C)) |
|---|---|
| RV10-1 | `read_branch` reads the full ref (`git symbolic-ref -q HEAD`) and strips `refs/heads/` by string (`branch_of_ref`); `--short` is refused by the allow-list. `valid_branch_name` applies git's ref-name rules to a name read from git and to `--branch` (invalid `--branch` = usage error, exit 2, before any fetch). Census of every branch, ref or remote name used in a path, lock, marker or comparison: `class_inventory_names.py` (closed-world AST inventory, 58 sites, control needles, semantic checks; PASS on r11; on the r10 engine FAIL with 2 semantic failures and 2 unclassified sites). |
| RV10-2 | Case kept everywhere (`Dev` is not `dev`); mixed-case branches in the unit lock-path test and in the live `branch_lock` / `branch_shape` checks (kills AA01). |
| RV10-3 | Canonical git-env scrub in 21 vehicle files; engine `_SCRUB` holds all of `CL_GIT_SCRUB_VARS` (`GIT_GRAFT_FILE`, `GIT_NO_REPLACE_OBJECTS` were missing). 9 exemption rows (8 `pinned-fixture` evidence scripts whose sha256 is in their pack's `SHA256SUMS`; `scripts/sync/sync_step_lib.sh` `sourced-library`), each checked by `verify_exemption_rows.py`, which does not reuse the census. The ff-only gate accepts the scrub only in its exact two-statement form (4 paired meta-test cases). Go: the census covers Go members; the vehicle changes no `.go` file. |
| RV10-4 | The work-tree-only limit filed through the engine as CON-PENDINGsync1 after a dedupe search (§11.4.214; control needles: a present term 1, a fabricated term 0); cited in the manual, the `write_settled` docstring and the r10 README. |
| RV10-5 | README `docs/` row: `[upstream-sync guide](…)` bracket restored. |
| RV10-6 | Not implemented (held out by the brief). Docs state the current defaults (`setup --sync-upstreams` = `off`; hook step 5c = `offline`, `--check --no-fetch`); the 2026-11-14 decision (on, online, bounded; fetch-only default; ff merges only on explicit consent; hook on every pull) is filed as CON-PENDINGsync2. |
| RV10-7 | Live check `marker_foreign`: a marker whose op is outside the closed set (tab, newline, fake report line) is reported `unknown-left-nothing`, and the planted text is absent from the notes (kills AA10). |
| RV10-8 | r10 README wording corrected (ids ran to CON-400 when round 10 began, CON-411 after its merge); its checksum line updated; the r10 pack verifies (`sha256sum -c`, 0 failures). |

Measured beyond the review (red/): on the r10 engine, an upstream branch named `heads/dev` next to branch `dev`
with no lock held was fast-forwarded INTO branch `dev` (a wrong-branch merge, rc 0); with the branch lock held
the r10 engine left a half write (`write-left-changes`). On r11 both are blocked (`root-not-on-heads/dev`).
A same-named remote does not make `--short` ambiguous (measured; the `remote` shape stays a golden-FALSE).

## RED before, GREEN after

| Check | r10 engine (red/) | r11 (green/) |
|---|---|---|
| live `branch_shape,branch_param,marker_foreign,branch_lock,wt_param` | PASS 338 FAIL 49 | PASS 387 FAIL 0 |
| unit suite (`SYNC_ENGINE_PY`) | PASS 126 FAIL 7 | PASS 133 FAIL 0 |
| name inventory | FAIL (2 SEMANTIC-FAIL, 2 unclassified) | PASS sites=58 unclassified=0 |
| git-env census (merged tree) | FAIL unscrubbed=30 | PASS members=674 hermetic=515 exempt=159 unscrubbed=0 |
| `tests/test_git_env_class.sh` | — | passed=142 failed=0 skipped=1 |
| `tests/test_full_suite_manifest_gate_git_env.sh` | — | passed=14 failed=0 |
| ff-only gate | FAIL (scrub import not on the allow-list; fixed by the narrow rule) | PASS; meta-test PASS (97 cases) |
| exemption rows | — | `verify_exemption_rows.py` PASS 9 rows |

## Mutants

Reviewer mutants AA01–AA12 adopted verbatim; own mutants AB01–AB14 (RV10-1, RV10-2, RV10-3). Targeted table
(`mutants/mut_r11_new_table.txt`): 26 mutants, 23 killed, 2 EQUIVALENT (AA07, AA11, proofs in
`tests/sync/test_mutations.py`), 1 survived: AB08 (`read_branch` without its newline check). AB08 exposed a
missing test case (a two-line answer whose first line is outside `refs/heads/` was read as `other`); two cases
were added and AB08 is killed by unit (`mutants/mut_r11_AB08_after.txt`, RED with the mutant:
`red/red_AB08_unit.txt`). Before round 11, AA01 and AA10 survived the r10 suites
(`red/red_r10_reviewer_mutants_AA.txt`). The full table runs inside `run_all.sh` (see Runs).

The first full run on e1e4d10c showed earlier mutant P32 SURVIVED (`red/red_P32_full_run_aborted.txt`, 187 of 343
done when it was stopped). The new full-ref check made P32's target, the separate empty-name test in
`read_branch`, redundant: an empty name also fails `startswith("refs/")`. That test was removed, and P32 now
removes the `refs/` test that carries the RV4-1 guard. On eda97c9e, P32 and AB08 are killed by unit
(`mutants/mut_r11_P32_after.txt`) and unit is 133/0. The full run started again on the final tree.

## Runs

All runs are on the final source tree eda97c9e, with this pack staged so the census covers its three tools.

| Run | Result | File |
|---|---|---|
| full `tests/sync/run_all.sh` (2026-11-16T13:10:33Z to 19:36:37Z) | RUN_ALL PASS rc 0. unit 133/0, integration 149/0, e2e 24/0, full-automation 34/0, security 83/0, determinism 15/0, ui 26/0, hardening 119/0, chaos 58/0, perf 13/0, faults 21/0, robustness 1217/0. ff-only gate PASS, its meta-test PASS (97 cases). Mutants: 343 total, 339 killed, 4 EQUIVALENT with recorded proofs (M37, Z12, AA07, AA11), 0 survived, 0 harness errors. | `runs/r11_run_all_full.txt` |
| quick suite, 3 runs | RUN_ALL PASS each time. Verdict hash identical all 3 times: `713e95b3de0415eaeca080c3d25a9543b2d8a9b4548478eb0b8ad2db5ab93d82` (20 lines, durations stripped, `verdict_hash.py`). | `runs/r11_quick_{1,2,3}.txt` |
| git-env census | PASS. members=676, hermetic=517, exempt=159, unscrubbed=0. | `runs/final_git_env_census.txt` |
| `tests/test_git_env_class.sh` / `tests/test_full_suite_manifest_gate_git_env.sh` | 142/0 (1 skipped) and 14/0. | `runs/final_test_*` |
| exemption rows (independent instrument) | PASS, 9 rows. | `runs/final_verify_exemption_rows.txt` |
| name inventory | PASS. sites=58, unclassified=0, stale=0. | `runs/final_inventory_names.txt` |
| `--verify-manifest` / `--sync-guide` | MANIFEST-OK. Guide census total=961, no tracked file changed. | `runs/final_verify_manifest.txt`, `runs/final_sync_guide.txt` |
| gate-ledger ratchet | PASS, 394/394. | `runs/final_ratchet.txt` |
| index fresh | PASS. | `runs/final_index_fresh.txt` |
| engine `validate` / `diff` / `diff --db-only` | OK (390 items), in sync (390/390), DB-internal checks passed. | `runs/final_engine_validate_diff.txt` |

The first light-gate pass caught a defect in this pack: the census failed on the new `verify_exemption_rows.py`,
which mentions git but had no scrub. The canonical two-line scrub was added and the census was run again.
Stale outputs of earlier runs (before the final tree): `runs/r11_quick_*` were overwritten by the final-tree runs;
`runs/r11_ratchet.txt`, `r11_sync_guide.txt`, `r11_verify_manifest.txt`, `r11_index_fresh.txt` are from e1e4d10c
and kept as history; the `final_*` files are the current results.

## Tracker

Every tracker change went through the engine (`scripts/workable-items/bin/workable-items`): `add` CON-PENDINGsync1,
CON-PENDINGsync2, CON-PENDINGsync3 (the vehicle item, then `update --status "In progress"`); `sync db-to-md`; `export` (Markdown
only; `Issues_Summary.md` regenerated). `validate`: OK, 390 items. `diff --issues --fixed`: in sync (390/390);
`diff --db-only`: passed. `created_at` set by the engine on each add (no restore needed).

## Limits stated

- Case-insensitive file systems: `refs/heads/Dev.lock` and `refs/heads/dev.lock` are one file there; branches that
  differ only in case cannot be told apart (git's own limit). Tests run on case-sensitive Linux only.
- `--branch` is ASCII (`[A-Za-z0-9._/-]`, 1–128 characters); a root branch with other letters is compared exactly.
- A failed write that changed only the work tree is read as settled (CON-PENDINGsync1).
- Defaults unchanged this round (CON-PENDINGsync2).

## Files

`red/`, `green/`, `mutants/`, `runs/`, `merge/`; tools: `class_inventory_names.py`, `verify_exemption_rows.py`,
`verdict_hash.py`. Checksums: `SHA256SUMS`.
