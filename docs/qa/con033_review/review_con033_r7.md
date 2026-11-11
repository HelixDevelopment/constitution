# Independent review: vehicle/con033 (CON-033), review round 7 (structural round past R_max, operator decision 2026-11-11)

| Field | Value |
|---|---|
| Bundle | con033_r7.bundle, sha256 848dc279bcfa50995c35509aa8deb1a456344b2dfce2f1583c7e32f440e93727 (matches); ref `refs/heads/vehicle/con033` = f020d1ca (R6-N1 closed: the ref is named); prerequisites 2e8cfb90, 27dcf518, fc57ad0c present in my clone |
| Reviewer tree | /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/74ce2b36-bc1b-48fc-b31c-c523fed7b15e/scratchpad/rev_con033_r7/constitution (worktree at f020d1ca of my round-6 clone; live checkout not touched) |
| Logs | /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/74ce2b36-bc1b-48fc-b31c-c523fed7b15e/scratchpad/rev_con033_r7/logs/ (rv7.out, cap8.out, enum_sample.out, ss_head_consumer.log, mergetree.txt); runner rv7_runner.py beside it |
| Model / effort | Opus 5.5 (harness-reported); effort not verifiable on this dispatch path |
| Verdict | **GO, conditional on the kill-ledger regeneration** (below), with 3 minor/nit follow-ups (§11.4.276(G.2) minor class) |

Round range reviewed: b26bd542..f020d1ca (4351813e wip + f020d1ca), 5 test files, +195/-10. No change to review_record.py or to any tool; the round is test-only.

## Prior findings (round 6): closure check

| Prior | Status | Evidence (this session) |
|---|---|---|
| R6-F1 (RV6-E) | **CLOSED** | RV6-E (records passed as ledger) replayed: KILLED by tier_legs (spy leg). Also run against the r4 suite alone: head rc=0 (27/0, `PASS: R4-CAP8: through the real gate at release-tag, qa-deploy and manual-qa-handoff ... COVERED when the dispatch ledger is owner-owned, and REFUSED (instance, ledger named) when the ledger is not`); RV6-E mutant rc=1, `FAIL: R4-CAP8: [release-tag control 0\|capability\|False ... attack 0\|capability\|False]`. So the real-podman real-gate leg kills it independently of the spy. The spy test drives the real `cmd_gate` at `ordinary` + every `HIGH_BLAST_SEAMS` entry and pins the 4 positional args in order with distinct records/ledger paths. The `_store_tier` -> `_path_tier` forwarding spy pins runner_uid/ranges/getpw with three distinct sentinels. RV6-E is also in the gate_authority_mutations table. |
| R6-F2 (anchor drift) | **CLOSED** | Consumer layout (atmosphere DB via `sqlite3 .backup` into `cons/docs/`, canon worktree at f020d1ca as `cons/constitution`): rc=0, 66 ok / 0 NOT ok, 641 s; `ok mutation R4_retro_gap_le60 killed (3 failing check(s))`, `ok mutation R4_retro_gap_gt0 killed (3 failing check(s))`. Anchor `if 0 <= gap < 60 else` occurs once (select_sample.py:504). Failure message now carries the reason. |
| R6-F3 (SKIP) | **CLOSED** | Standalone checkout named `constitution` (ROOT has no docs/workable_items.db): exit 77, `SKIP: ... or the consumer tracker DB .../rev_con033_r7/docs/workable_items.db absent ... reason=topology_unsupported`. |
| R6-F4 (RV6-B) | **CLOSED** | RV6-B replayed: KILLED by tier_legs. The new case patches `open` for nsswitch/subuid/subgid and calls `_subid_ranges()` with defaults; it also pins the tuple constant. |
| R6-N1 | CLOSED | bundle ref named |

## Call-site class (mutate_tier_legs.py)

- Census: `# call-site census: 10 call(s) of 8 tier functions; control needles ok`, `# 312 mutants` (226 + 86 arg mutants). My independent grep of review_record.py for the 8 names (excluding defs/comments/docstrings) lists exactly the same 10 call lines (783, 816, 854, 861, 926, 930, 939, 943, 965, 2159). Census matches.
- Author's full run (r6/tier_all.log, finished 14:20 CET, after f020d1ca at 13:56): `mutants 312: killed 309, equivalent 3, survived 0`. Their earlier RED (tier_arg.log) shows the two `_store_tier>_path_tier#3` survivors that f020d1ca's forwarding spy then killed.
- My sample (`--keys`, jobs 1, 7 keys): `EQUIVALENT _subid_ranges|const|1|2|#1`; KILLED: `_path_tier>_owner_declaration_error#4 lookup->runner`, `_path_tier>_owner_only_error#1 owner_uid->None`, `_store_tier>_path_tier#3 runner_uid->producer_uid`, `_store_tier>_path_tier#4 ranges->getpw`, `cmd_gate>_store_tier#1 dispatch_ledger->records` (= RV6-E), `cmd_gate>_store_tier#2 producer_uid->evidence_owner_uid`. Control GREEN across 13 suites.
- Equivalence proofs (3), re-derived: `raw.split("#", 1)[0]` vs `split("#", 2)[0]` (review_record.py:696): index 0 identical for any maxsplit >= 1, holds. `_has_acl` tuple narrowed to either errno: measured `errno.ENOTSUP == errno.EOPNOTSUPP == 95` on this host, pinned by a tier_legs case; holds on Linux.

## Reviewer-authored mutants (§11.4.194(6)(d)): 7 of my own + 2 replays, every STAGE2 suite, control all rc 0

| Mutant | Class member | Result |
|---|---|---|
| RV7-A gate ctx `"tier": tier` -> `"capability"` | consumption of the tier result | KILLED (gate_authority_r4) |
| RV7-B `_load_ledger(a.dispatch_ledger)` -> `_load_ledger(a.records)` | gate call-site binding of a non-tier function | KILLED (subclause_cases) |
| RV7-C `_store_tier` roots `[records_dir, ledger_path]` -> `[records_dir]` | store-tier composition | KILLED (store_tier_all_entries) |
| RV7-D `_path_tier` loop `paths` -> `paths[:-1]` | path coverage | KILLED (resolution_ground_truth) |
| RV7-E gate ctx `"seam": a.seam` -> `"ordinary"` | seam binding | KILLED (gate_authority_r4) |
| RV7-F `tier, tier_reason = _store_tier(` -> `tier_reason, tier =` | return-value binding | KILLED (subclause_cases) |
| RV7-G walk adds only `filenames` (sub-directories dropped) | store-tier composition | KILLED (store_tier_all_entries) |
| RV6-B replay | default sub-id files | KILLED (tier_legs) |
| RV6-E replay | gate call site | KILLED (tier_legs; and by R4-CAP8 alone, see above) |

No survivor.

## --verify-manifest (not accepted, nothing run)

```
MANIFEST: excluded set differs from the accepted lock .../config/full_suite_excluded.lock (added ['scripts/fastcycle/tests/lib/review_record_guard_analyzer.py', 'scripts/fastcycle/tests/mutate_tier_legs.py', 'scripts/fastcycle/tests/sweep_review_record_subclauses.sh'], removed [], note changed []); review and run --verify-manifest --accept-excluded-change <reviewer>
census: go/entry=5 js/excluded=5 py/entry=10 py/excluded=27 py/fixture=14 py/member=24 runall/entry=9 sh/entry=351 sh/excluded=26 sh/fixture=111 sh/member=310 total=892
RESULT: MANIFEST-MISMATCH (1 problem(s); nothing was run)   rc=3
```
Exactly one problem, the expected one (same 3 rows I judged justified in round 6).

## Trial merge with origin/main b20736f8 (`git merge-tree --write-tree`, no working tree)

Merge base fc57ad0c. Conflicts only in: docs/Fixed.md (1 hunk), docs/Fixed_Summary.md (2), docs/Issues.md (8), docs/Issues_Summary.md (2), docs/workable_items.db (binary), docs/guides/full_suite_runner_guide.md (1 hunk: the generated `census:` line, 888 on main vs 892 here; regenerate with `--sync-guide`). The Issues.md hunks are main's CON-211+ items versus the vehicle's CON-194..210 items: the expected id/generated-file conflicts. config/full_suite_manifest.tsv auto-merged. Main's fastcycle changes (fc57ad0c..b20736f8) touch none of review_record.py, the guard analyzer, review_record_genuine.sh, or any of the 13 ledger suites, so the kill-ledger header hashes are not invalidated by the merge.

## Findings this round

| Id | Layer | Severity | Finding | Proposed fix |
|---|---|---|---|---|
| R7-M1 | test-instrumentation | minor | The mechanical enumerator covers tier-function bodies and tier-function call sites. Module constants the tier consumes (`_FOREIGN_WRITE`, `_SUBID_FILES`, `HIGH_BLAST_SEAMS`) and the gate-side consumption of the tier result (ctx `tier`/`seam`, return unpacking) are still covered only by hand-written mutants (RV6-A/B/D, RV7-A/E/F; all killed). The census is proven non-blind by fixed needles, not by an independent count (I did the count by grep: 10 = 10). No survivor, so not blocking. | Extend TARGETS with "names read by a tier function" (module constants) and the `cmd_gate` lines from the tier call to the ctx dict; cross-check the census against a token count. Follow-up item. |
| R7-M2 | test-instrumentation | minor | mutate_tier_legs.py still has no self-test RED (a planted survivor must make it exit 1; an arg-mutant generator that drops kinds must be noticed). Carried from round 6. | Small RED suite. Follow-up. |
| R7-N1 | test-instrumentation | nit | With `--keys`, every equivalence key outside the selected subset is printed `STALE` and the run exits 1 (seen in my 7-key sample: the two `_has_acl` keys). Only a full run gives a meaningful stale check. | Compute staleness against the full enumeration, not the filtered list. |

## Structural judgment (§11.4.276(E)(3))

The recurring class (a tier-path mutant no suite kills) has been attacked structurally: an AST enumerator over every tier function body plus every call of every tier function, census with needles, 312 mutants, 0 survivors, plus a real-gate podman leg at all three high-blast seams. This round I aimed 7 new mutants at the remaining edges of the class (constants are covered by replays; gate-side consumption, call-site binding of the ledger loader, store composition, path-loop coverage, return unpacking) and every one was killed. I find no remaining class-level defect that blocks; the residual is the hand-covered boundary named in R7-M1, which is a completeness improvement, not a live hole.

## Condition: what the lander MUST verify for the kill ledger before landing

The committed `scripts/fastcycle/tests/fixtures/review_record_subclause_kills.tsv` is stale on purpose (its `# suite test_review_record_tier_legs_regression.sh sha256=a7a4e242...` header differs from the head file b3bb7de2...; the r4 suite also changed). The regeneration sweep is running (pid 961521, `sweep_review_record_subclauses.sh -j 2 --out .../013b6b97.../scratchpad/r6/kills_new.tsv`, cwd = the author's clean checkout at f020d1ca; control `ok control GREEN: 460 passing checks across 13 suites`; 345 sub-clause mutants). The lander must:

1. Wait for the sweep to exit 0 and for kills_new.tsv to exist (the sweep log ends with its summary, no `SURVIVED`).
2. Confirm the generating tree was exactly f020d1ca with a clean working tree at sweep end (`git -C <author clone> rev-parse HEAD` and `git status --short` empty; I checked both at start: f020d1ca, clean).
3. Confirm the header of kills_new.tsv: `tool_sha256` = sha256 of scripts/fastcycle/review/review_record.py (f2c1ffbc8a2a75f77ce6268cfcb206c0342fbb73c27fc1eb5a8a923e45398ddf), `analyzer_sha256`, `genuine_sha256`, and every `# suite ... sha256=` line equal to the files at the tree being landed (all 13 suites, including tier_legs b3bb7de21cb3a1afa43a1bf01cf344bf61ea4bc3ab142ee33fc17fcfe729d7bb and the changed r4 suite), and `control_skipped_suites= none`.
4. Confirm 345 data rows, each KILLED or listed in review_record_equivalent_subclauses.tsv; zero SURVIVED.
5. Copy it over the fixture in a new commit on the vehicle (no rewrite), then run `bash scripts/fastcycle/tests/test_review_record_guard_table.sh` and see M4 pass (no `kill ledger is STALE`, no stale rows), and its golden-bad GB5 still fire.
6. After the main merge and the CON-194..210 re-mint, re-check step 3 on the merged tree (main does not touch these files today, so the hashes should still match; if any hashed file changed in the merge, re-run the sweep).
7. Only then run the acceptance (`--verify-manifest --accept-excluded-change <rostered operator id>`), which stays the operator's act, and regenerate the guide census line with `--sync-guide`.

If step 4 shows any SURVIVED row, this GO is void and the item returns to review.

## Not run by me

The full 312-mutant enumeration (sampled 7), the 345-mutant sweep (running, not mine), the full suite. The 309 killed is the author's figure, sample-checked.
