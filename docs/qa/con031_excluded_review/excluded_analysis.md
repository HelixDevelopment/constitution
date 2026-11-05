# CON-031 full-suite excluded list: investigation (2026-11-05)

> Archived 2026-11-05 at the landing of vehicle/con031-excluded on main, copied unchanged from the session scratchpad except for bracketed corrections marked "corrected at landing". Local scratch paths in the text are not part of the repository. Item ids in this file are the vehicle ids; on main they are: CON-064/CON-070 -> CON-083, CON-065/CON-071 -> CON-084, CON-066/CON-072 -> CON-085, CON-067/CON-073 -> CON-086; follow-ups FU-1 -> CON-087, FU-2 -> CON-088, FU-3 -> CON-089, FU-4 -> CON-090, X2 -> CON-091.

Investigator: AI (Claude Opus 5.5), read-only on the real repository. Work clones under
`/home/milosvasic/.cache/claude-tmp/xa.snDMq2/` (`c` = clone of main 7f72395 for runs, `v` =
vehicle `vehicle/con031-excluded`, `w2` = copy of the wave-2 vehicle at 6eecc96). Evidence directory
`E` = `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/xa_ev/`.

## What was measured, and how

| Instrument | Output | Control |
|---|---|---|
| Static census of every excluded row: exists, size, added/last commit, references from all tracked text files, the manifest class/tier of each referrer, whether the user the note names really mentions the file (`xa_static.py`) | `E/static.tsv` | positive needle `gate_mutation_harness.sh` found; fabricated name 0 hits |
| Runnable coverage: for each row, the default-tier and heavy-tier manifest units that reach a referrer (directly or through a `run_all.sh`) (`xa_pick.py`) | `E/pick.tsv` | rows 33 and 38 read 0/0 and were checked by hand (see the table): two false nulls of the instrument (relative-dir filter; `cp` instead of `source`) |
| Dynamic proof: each covering default unit run once under `strace -f -e openat,execve` in a fresh HOME/TMPDIR, `nice 19`, `ionice -c3`, 600 s bound, one at a time, load-gated (`xa_dyn.sh`, `xa_dyn2.sh`); `xa_hits.py` maps each excluded path to the traces that open or execute it | `E/dyn/*.paths`, `E/dyn/index.tsv`, `E/hits.tsv` | each trace must contain its own unit's path (self-needle) |
| Manifest check on main and in the vehicle (`run_full_suite.sh --verify-manifest`) | `E/verify_manifest_main.txt`, `docs/qa/con073_reproduction_2026_11_05.txt` (vehicle) | census totals printed by the tool |

Host note: the 1-minute load stayed between 25 and 38 on 16 cores during the whole session (other agents),
so every run was serial and load-gated. One of my wait loops used `pgrep -f` on a pattern its own
parent shell carried and never ended (the §12.12 self-match footgun); I found it, stopped only that
wrapper after reading its `/proc` cmdline, and waited on the pid with `kill -0` instead.

## Root-cause classes used

The class list in the task (device, network, credentials, consumer layout, heavy runtime, broken test,
dead test) describes why a TEST cannot run. 40 of the 44 rows are not tests at all: they are libraries,
helpers, oracles, fakes, gates and tools that the census picks up by name (`test`, `mutant`, `mutation`,
`smoke`, `selftest`, or a path under a tests directory). I record those as class **NEP**
(not an entry point) with the sub-kind from the note, and use the task's classes where they apply.

Coverage column: **D** = run by a default-tier unit, **H** = run only by heavy-tier units (still part of
the §11.4.40 full retest, which is `--include-heavy` exit 0 only), **0** = nothing runnable reaches it.

## Table: the 44 rows of the accepted lock, plus 2 new rows and the wave-2 row

| # | Path | Class | Coverage (pick D/H) | Finding | Disposition | Evidence |
|---|---|---|---|---|---|---|
| 1 | scripts/amendment_log/tests/independent_lossless_rebuild.py | NEP oracle | D (1/0) | run by `test_status_summary_archive.sh` (traced rc 0, 43 s) | keep-excluded | static, pick, `E/dyn/index.tsv` |
| 2 | scripts/anchors/tests/_paths.py | NEP helper | D (1/0) | imported by `test_cwd_independence.py` via `run_all.sh` | keep-excluded | static, pick |
| 3 | scripts/catalog-engine/lib/parse_mutation.py | broken coverage | **0 (0/0)** | the note said "imported by parse_gate.py; tested by catalog-engine/tests". Measured: parse_gate.py names it only in a comment, `scan.py` imports it, and the only test covers parse_gate.py. Zero tests. While writing the first test, a real parser defect showed up (CON-072) | **make-runnable**: new default test `test_parse_mutation.sh` (10/10, 9/9 paired mutants killed, 4.7 s); note corrected | `E/test_parse_mutation_run1.txt`, vehicle 4db86ed6, 485c341d; CON-070, CON-072 |
| 4 | scripts/codegraph/tests/cg_fp.py | NEP library, **heavy runtime** in its users | D (2/0) | its two users `test_codegraph_mcp.sh` and `test_mcp_readonly.sh` exit 2 BLIND ("cannot resolve stock package source") without the npm-global codegraph package; the runner judges exit 2 as FAIL `rc_2` (only 77 is SKIP) | keep-excluded; the users' BLIND exit is an **operator decision** (plan item O3) | `E/dyn/*codegraph*.log`, `run_full_suite.py` `judge()` |
| 5 | scripts/codegraph/tests/t_scope_cases.py | NEP data, heavy runtime in its user | D (1/1) | `run_scope_tests.sh` exits 3 without `CODEGRAPH_RUNNER_DIST` | keep-excluded; O3 | `E/dyn/scripts_codegraph_tests_run_scope_tests.sh.log` |
| 6 | scripts/codegraph/tests/t_scope_fixture.py | NEP library | D via #5's users | the note named `run_scope_tests.sh`, which never mentions it; it is imported only by `t_scope_cases.py`, which `t_scope_mutations.py` runs against each mutant | keep-excluded, note corrected (cd1e55ee) | static (`NO-REF`), vehicle 485c341d |
| 7 | scripts/fastcycle/gates/mutation_reuse.py | NEP library | H (0/2) | only heavy members exercise it; the old note named `run_all.sh`, which does not reference it | keep-excluded; note now names the heavy members. Tier override for `test_mutation_reuse_red.sh` is plan item O4 | static, pick |
| 8 | scripts/fastcycle/tests/capture_fc_timer_triplet.sh | NEP tool; its test broken by **consumer layout** | D (7/0) | `test_capture_fc_timer_triplet.sh` fails check (H15) in a standalone clone: the tool looked for the consumer pre-build file before refusing the stand-in-only override | **make-runnable**: refusal moved first; RED on main, GREEN in the vehicle | `docs/qa/con071_reproduction_2026_11_05.txt` (vehicle); 322c25ef; CON-071 |
| 9 | scripts/fastcycle/tests/check_deps.sh | NEP tool | D (4/0) | run by `test_check_deps.sh` | keep-excluded | static, pick, trace (pending) |
| 10 | scripts/fastcycle/tests/lib/bb_ref_bisect.py | NEP oracle | D (1/0) | `test_batch_bisect_red.sh` | keep-excluded | static, pick |
| 11 | scripts/fastcycle/tests/lib/dec07_key_ref.py | NEP oracle | D (3/0) | old note "fastcycle RED tests" named no user. Its one real user is `test_verdict_cache_red.sh` (default); `test_batch_bisect_red.sh` and `test_gate_shard_red.sh` name it only in comments (the trace of `test_batch_bisect_red.sh`, rc 0, never opens it) | keep-excluded, user named (cd1e55ee corrects my first wording) | static, pick |
| 12 | scripts/fastcycle/tests/lib/dec15_flake_ref.py | NEP oracle | D (1/0) | `test_flake_ledger_red.sh` (old note named no user) | keep-excluded, user named | static, pick |
| 13 | scripts/fastcycle/tests/lib/dec17_drift_ref.py | NEP oracle | D (1/0) | `test_backstop_red.sh` (old note named no user) | keep-excluded, user named | static, pick |
| 14 | scripts/fastcycle/tests/lib/dec23_key_ref.py | NEP oracle | H (0/1) | only `test_mutation_reuse_red.sh` (heavy). A second, newer, **divergent** copy `scripts/fastcycle/lib/dec23_key_ref.py` (logic differs, not only the docstring) has never been wired since it landed in a925a8da (2026-09-30); its only mention is a hash in `progressive/EVIDENCE/PREFLIGHT_MANIFEST.json` | keep-excluded; the orphan copy is an **obsolete candidate**, operator decision O2 | AST-hash comparison, `git log -S` (see the plan) |
| 15 | scripts/fastcycle/tests/lib/golden_triplet_fixture.sh | NEP helper | D (8/0) | sourced by `test_capture_fc_timer_triplet.sh` (now passing standalone, #8) | keep-excluded | static, pick |
| 16 | scripts/fastcycle/tests/lib/guard_freshness_ref.py | NEP oracle | D (1/0) | `test_backstop_red.sh` (old note named no user) | keep-excluded, user named | static, pick |
| 17 | scripts/fastcycle/tests/lib/render_keys_ref.py | NEP oracle | D (1/0) | `test_render_keys_red.sh` (old note named no user) | keep-excluded, user named | static, pick |
| 18 | scripts/fastcycle/tests/lib/review_record_genuine.sh | NEP helper | D (6/1) | sourced as the note says | keep-excluded | static, pick |
| 19 | scripts/fastcycle/tests/lib/shard_ref.py | NEP oracle | D (2/0) | real user `test_gate_shard_red.sh` (default); `test_gate_shard_r1_regression.sh` names it only in a comment (its trace, rc 0, never opens it) | keep-excluded, user named (cd1e55ee) | static, pick |
| 20 | scripts/fastcycle/tests/lib/tce_normalize_ref.py | NEP oracle | H (0/1) | as #14, including the divergent orphan copy `scripts/fastcycle/lib/tce_normalize_ref.py` | keep-excluded; orphan → O2 | as #14 |
| 21 | scripts/fastcycle/tests/lib/triple_harness.sh | NEP library | D (6/1) | `test_build_deploy_qa_events_red.sh` and others | keep-excluded | static, pick |
| 22 | scripts/gates/cm_build_on_source_proven_not_test_side.sh | NEP gate | H (0/1) | a gate (run by the pre-build sweep); its paired mutation test is heavy | keep-excluded | static, pick |
| 23 | scripts/gates/cm_mutation_score_on_diff.sh | NEP gate | H (0/1) | as #22 | keep-excluded | static, pick |
| 24 | scripts/gates/cm_setup_prompt_latest_present.sh | NEP gate (census by the word "latest") | D (5/2) | the note now says why it is in the census | keep-excluded, note corrected | static, pick |
| 25 | scripts/gates/cm_test_mock_pid_explicit_int.sh | NEP gate | D (1/1) | `test_gate_env_overrides_guarded.sh` plus the paired heavy test | keep-excluded | static, pick |
| 26 | scripts/gates/lib/covenant_propagation_mutation_engine.sh | NEP library | H (0/107) | 107 heavy `cm_covenant_*_mutation_test.sh` users [corrected at landing, review F7: 109 test files load the engine, 106 `cm_*_mutation_test.sh` and 3 engine-level mutation tests, all heavy] | keep-excluded | static, pick |
| 27 | scripts/gates/lib/gate_mutation_harness.sh | NEP library | H (0/3) | heavy users | keep-excluded | static, pick |
| 28 | scripts/gates/lib/shell_mutation_engine.sh | NEP library | H (0/1) | used by #23 | keep-excluded | static, pick |
| 29 | scripts/label-sync/adapters/tests/fake_openai.py | NEP fake (unit class, §11.4.289(C)(2)) | D (1/1) | loopback stand-in used by `test_real_agents.sh`; its header says test-only | keep-excluded | header read, pick |
| 30 | scripts/label-sync/hook_mutants.py | NEP library | H (0/2) | heavy users | keep-excluded | static, pick |
| 31 | scripts/lumen/tests/fake_ollama.py | NEP fake (unit class) | D (1/0) | header: "Test-only (unit layer); never used to claim retrieval quality" | keep-excluded | header read, pick |
| 32 | scripts/mechanical/mutation_harness.sh | NEP tool | H (0/4) | its own test `test_mutation_harness.sh` is heavy; the note now names it | keep-excluded, note corrected | static, pick |
| 33 | scripts/mechanical/tests/lib/assert.sh | NEP helper | D (pick false null) | sourced by 6 default members and 1 heavy member of `scripts/mechanical/tests` | keep-excluded | `git grep` + manifest rows (by hand) |
| 34 | tests/decisions/lib.sh | NEP helper | D (12/2) | as the note says | keep-excluded | static, pick |
| 35 | tests/decisions/repo_guard.sh | NEP helper | D (1/1) | sourced by `run_all.sh` line 16 | keep-excluded | `git grep` |
| 36 | tests/extensions/lib.sh | NEP helper | D (13/4) | | keep-excluded | static, pick |
| 37 | tests/install/lib.sh | NEP helper | D (18/2) | | keep-excluded | static, pick |
| 38 | tests/jev/fixtures-shared/jev_scripts/bootstrap.sh | NEP fake (recording stub) | D (pick false null) | copied with `cp` by default member `test_mcp_register_hardening.sh` and by `lib_assert.sh` | keep-excluded | `git grep` (by hand) |
| 39 | tests/jev/lib_assert.sh | NEP helper | D (22/0) | | keep-excluded | static, pick |
| 40 | tests/layout/lib_layout_harness.sh | NEP helper | D (17/0) | | keep-excluded | static, pick |
| 41 | tests/lib/make_fixture_tracker.sh | NEP library | D (1/0) | `test_fastcycle_real_db.sh` | keep-excluded | static, pick |
| 42 | tests/prompts/allowlist_bypass_forms.py | NEP library | D (2/0) | | keep-excluded | static, pick |
| 43 | tests/prompts/git_allowlist.py | NEP library | D (2/2) | | keep-excluded | static, pick |
| 44 | tests/prompts/lib.sh | NEP helper | D (15/8) | | keep-excluded | static, pick |
| N1 | scripts/fastcycle/tests/check_safepath_census.py | NEP tool (new row) | D | on main it had no manifest row at all (one of the 26, CON-073); it is a census tool run by `test_fc_safepath_v4r12.sh`..`v4r15.sh` | keep-excluded (row added; needs lock acceptance) | vehicle 485c341d |
| N2 | scripts/fastcycle/tests/lib/foreign_uid_cause.sh | NEP tool (new row) | D | as N1; a probe that always exits 0 | keep-excluded (row added; needs lock acceptance) | vehicle 485c341d |
| W2 | tests/layout/hermetic_lint.py (wave-2 vehicle 6eecc96) | NEP library | D | run and mutation-checked by `tests/layout/test_hermetic_generator.sh` (default). The wave-2 lock has **no row** for it, so wave 2 cannot pass `--verify-manifest` until the operator accepts it | keep-excluded; lock acceptance when wave 2 lands (O1) | `w2/config/full_suite_manifest.tsv`, `grep -c` on the w2 lock = 0 |

Summary: of 44 rows, **2 had a real defect behind them** (#3, nothing tested it, and its note was wrong;
#8, its test failed in a standalone clone). **13 notes change** (the lock's "note changed" list): 3 were
wrong (#3, 6, 7: they named a user that does not reference the file), 8 oracle notes said only "fastcycle
RED tests" and now name their users (#11-14, 16, 17, 19, 20, the two heavy-only ones marked so), and 2 lacked
a fact (#24 why a gate is in the census, #32 its own test). **33 are correct exclusions**
covered by default units, and 10 of those [corrected at landing, review F7: the table has 10 H rows, 7, 14, 20, 22, 23, 26, 27, 28, 30, 32; first written as 11] are covered by heavy units only, which the §11.4.40 full
retest runs. **None is obsolete among the 44.** One obsolete candidate pair sits outside the list (the
orphan copies under `scripts/fastcycle/lib/`). The codegraph users (#4, 5, 6) depend on an npm package
that is not in the repository.

## Defects found on the way (registered through the engine, vehicle commit 35e8d53f)

| Id | Type | What | State |
|---|---|---|---|
| CON-070 | Task | parse_mutation.py untested, wrong note | fixed in the vehicle (4db86ed6, 485c341d) |
| CON-071 | Bug | triplet tool refusal order (H15 fails standalone) | reproduced-host-fixture, root-cause-found-with-evidence; fixed in the vehicle (322c25ef) |
| CON-072 | Bug | parse_mutation keeps the closing `"` when a banner has no closing em-dash | reproduced-host-fixture, root-cause-found-with-evidence (the toggled regex removes the signature); **not fixed** |
| CON-073 | Bug | main's manifest lacks census rows (25 on ecfe432), so `--accept-excluded-change` is refused on main | reproduced-host-fixture, root-cause-unconfirmed; rows added in the vehicle, the commit-time seam is not built |

Ids note: the first registration in the vehicle used CON-064..067, which main minted meanwhile for
other work. After merging main ecfe432 the items were re-minted as CON-070..073; commits 4db86ed6,
485c341d and 322c25ef still name the old ids in their messages (not rewritten, §11.4.113), and the
in-tree references were updated.

Engine gap observed (not registered, operator to decide): `workable-items update` records an
evidence PATH but no sha256, while §11.4.294(C) asks for path plus sha256 (UNCONFIRMED whether this is
already tracked).

## Trace evidence (partial: the batch was stopped at the coordinator's request)

Traced: 6 units in the first batch and 12 of 24 in the second (`E/dyn/index.tsv`, `E/dyn_rest.out`). Not traced: tests/decisions,
tests/extensions, tests/install, tests/jev, tests/layout, tests/prompts, tests/gates/test_fastcycle_real_db.sh, the codegraph
tests with the full PATH, and every heavy unit.

Instrument defect found and corrected (§11.4.273(d)): the raw map `E/hits.tsv` showed all 44 files as opened, including heavy-only
files no traced unit runs. Cause: `tests/gates/test_gate_env_overrides_guarded.sh` is a census that reads every script, and the
`test_cwd_independence.py` trace failed its self-needle. With those two removed (`E/hits_strict.tsv`), 13 files are proven opened
by a non-census unit and 31 are not proven by trace. For most of the 31 the covering unit was simply not traced; for 2 (rows 11
and 19) the covering unit ran and did not open the file, which exposed the two wrong notes above. A file that is only "opened"
is still not proven executed; the static and pick evidence stays the primary evidence for the 31.

Results that matter beyond the excluded list (my direct runs match the real sequence, because `scripts/fastcycle/tests/run_all.sh`
sets nothing but a depth counter):

| Unit | Traced result | Reading |
|---|---|---|
| test_flake_ledger_red.sh, test_backstop_red.sh | rc 1: "control needle FAILED: specs/004-fast-dev-cycles/contracts/ itself" | the test climbs `$FC/../../../specs/...` out of the constitution root into a consumer project; FAILs in every standalone clone. Instance of tracked CON-006 (default ROOT three levels up; its scope already names fastcycle), linked, not re-minted (§11.4.214). Oracles #12, 13, 16 have default coverage only through these tests |
| test_render_keys_red.sh | rc 1: `<parent>/scripts/testing/sync_all_markdown_exports.sh does not exist` | same class, CON-006; oracle #17 |
| test_check_deps.sh | rc 124 at the 600 s bound, twice; r6b signal cases FAIL | `strace -f` changes signal delivery to traced children, and the test header records 210 s serial without strace: this run proves nothing about the test (§11.4.199). Not re-run without strace (stopped) |
| test_real_agents.sh | rc 1: 4 opencode FAILs | the fresh HOME has no installed opencode plugin; a deviation of my sandbox, not evidence against the adapters (§11.4.199). Not re-run |
| test_gen_lumenignore.sh | rc 2: "SKIP: lumen binary not found" | the binary is looked up under `$HOME/.claude-shared/...` (it exists in the real home); the test PRINTS SKIP but EXITS 2, which `judge()` records as FAIL `rc_2`. Same tool-absent class as the codegraph tests (O3). Re-run with `LUMEN_BIN` set: not done |
| test_codegraph_mcp.sh, test_mcp_readonly.sh, run_scope_tests.sh | rc 2, 2, 3 with the minimal PATH | full-PATH rerun not reached |
| the other traced units | rc 0 | as expected |
