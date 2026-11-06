# CON-031 excluded-list vehicle: independent review, round 1 of at most 5

> Archived 2026-11-05 at the landing of vehicle/con031-excluded on main, copied unchanged from the session scratchpad except for bracketed corrections marked "corrected at landing". Local scratch paths in the text are not part of the repository. Item ids in this file are the vehicle ids; on main they are: CON-064/CON-070 -> CON-083, CON-065/CON-071 -> CON-084, CON-066/CON-072 -> CON-085, CON-067/CON-073 -> CON-086; follow-ups FU-1 -> CON-087, FU-2 -> CON-088, FU-3 -> CON-089, FU-4 -> CON-090, X2 -> CON-091.

| Field | Value |
|---|---|
| Date | 2026-11-05 |
| Reviewer | Claude Opus 5.5 (subagent). Reasoning effort could not be set or read on this dispatch path (§11.4.231(F.2)); no effort level is claimed |
| Anchors | §11.4.209 substrate, §11.4.142 universal review, §11.4.276(G) round budget, §11.4.235(D) finding layers |
| Vehicle | `vehicle/con031-excluded` from `excluded_vehicle.bundle`, head `cd1e55ee` (bundle sha256 prefix `9511904c21d9833e`, checked) |
| Base in the bundle | main `ecfe4325` |
| Real main now | `efe2cc6c` (7 commits past `ecfe4325`) |
| Work area | throwaway clones under `scratchpad/rvx031.WqZ6dt/` (`c` = vehicle, `m` = main `efe2cc6c`), sandbox `HOME` and `TMPDIR` in the same directory. The real checkout was not touched. `--accept-excluded-change` was not run. Nothing was landed or pushed |
| Verdict | **GO-with-follow-ups** for the source and data changes. Landing needs the five integration steps L1 to L5 below. Every open finding is minor-class under §11.4.276(G.2): process-doc or test-instrumentation, no source-defect |

## 1. Verdict per slice

| Slice | Commits | Verdict | Open findings |
|---|---|---|---|
| S1 new test `test_parse_mutation.sh` | 4db86ed6 | GO-with-follow-ups | F5 (7 of my 10 mutants survive), F6 |
| S2 manifest rows and notes | 485c341d, cd1e55ee | GO-with-follow-ups. Fix F1 before the operator accepts the lock (O1) | F1, F7, F12 |
| S3 triplet refusal order | 322c25ef | GO | none |
| S4 tracker items and evidence | e581a312, 35e8d53f | GO for the content. The ids cannot land as they are: re-mint at landing (L1 to L4) | F2, F3, F4, F8, F9, F11, F13 |
| S5 merge of main `ecfe432` | 2595f06e | GO. No change of either side is lost | none |
| S6 merge of main `efe2cc6c` (not yet done) | to do at landing | 5 conflicts, all resolvable without loss by the recipe in section 4 | F2, F3, F4 |

## 2. Findings

Severity uses the §11.4.276(G.2) set {critical, important, minor, nit}. "Layer" is the §11.4.235(D) `finding_layer`.

| Id | Slice | Layer | Severity | Finding and evidence | Action |
|---|---|---|---|---|---|
| F1 | S2 | process-doc | important | The changed note of row 17 says `render_keys_ref.py` is "used as an oracle by test_render_keys_red.sh". Nothing executes it. The test assigns `REFKEY="$HERE/lib/render_keys_ref.py"` (line 75) and only runs `[ ! -f "$REFKEY" ]` (lines 323 to 326). `"$REFKEY"` appears once in the file. Control: the eight other oracle rows are each run by their tests (`python3 ... "$VAR"` appears 2 to 10 times per test). The oracle was run once, by hand, to make the `fixtures/render_keys/*/key_*.json` files (fixtures README line 115). This is the same class cd1e55ee fixed for three notes (a weak reference counted as use); the author's sweep did not catch this member | Before O1, change the note to say what is true, for example: "oracle: generated the key fixtures under fixtures/render_keys/; test_render_keys_red.sh only checks that it exists; no unit runs it". Register a follow-up: have a test run the oracle against the fixtures, so the fixture keys stay grounded in a live computation (FU-2) |
| F2 | S4, S6 | process-doc | important (landing step) | The vehicle ids CON-070 to CON-073 collide. On main `efe2cc6c`, CON-071 and CON-072 are the landed redpin items (dash `shift`, vendored RB-05 mock), CON-073 to CON-082 are landed, and CON-070 is reserved by the CON-030 vehicle (it is absent on main). The engine's `nextID` (crud.go:444) returns max+1 and never fills gaps, so on main today the next free ids are CON-083 to CON-086 | Re-mint at landing through the engine on the merged database (L1). Do not take either side of the binary database |
| F3 | S6 | process-doc | important (landing step) | add/add conflict on `docs/qa/con071_reproduction_2026_11_05.txt`. Main's file is the redpin CON-071 evidence (`multitrack_sessions.sh`, dash). The vehicle's file is the triplet evidence. Taking one side deletes the other's reproduction evidence (§9.2, §11.4.292) | Keep main's file unchanged. Rename the vehicle's three files to the re-minted ids (L2) |
| F4 | S6 | process-doc | minor | `docs/workable_items.db` is a binary conflict; `docs/Issues.md` and `docs/Issues_Summary.md` conflict because both sides add items | Resolve by re-registering the four items with the engine on main's database, then regenerate the two Markdown files from the database (L1) |
| F5 | S1 | test-instrumentation | minor | My own mutants (§11.4.194(6)(d)): 3 of 10 killed (`rv_emdash_optional`, `rv_greedy`, `rv_physical_true`), 7 survive: `rv_atm_on_line` (ATM id searched on the whole line instead of the description), `rv_hdr_last_wins` (last gate header wins instead of the first), `rv_strict_utf8` (`errors="replace"` changed to `"strict"`), `rv_expect_no_b` (trailing `\b` dropped from the expect pattern), `rv_require_close` (end-of-line no longer ends a description), `rv_hdr_one_dash` (`-{2,}` changed to `-{1,}` in the header pattern), `rv_type_hardcode` (`type_root` ignored). The last one is not equivalent: `scan.py` passes `spec.get("type", "on_device")`, and the test always passes `"meta-test-mutation"`, the only value that hides it. The author's 9 mutants were all killed again (10/10, 5.0 s) | Adopt the 7 mutants and add the cases that kill them: an ATM id outside the description, two headers for one gate, a non-UTF-8 byte, `expect_prebuild_failX`, a banner without closing em-dash, a one-dash header, a second `type_root` value. `rv_require_close` belongs with the CON-072 fix (FU-1) |
| F6 | S1 | test-instrumentation | nit | A mutant that fails to import is reported as "killed (LOAD-FAILED)". That is a fair kill for `crash_missing`, but the same label would hide a mutant builder that produces broken Python by accident | Report LOAD-FAILED separately from killed, or assert that only the named mutant may fail to load |
| F7 | S2 (analysis) | process-doc | nit | The analysis says 11 rows are covered only by heavy units. The table has 10 `H` rows (7, 14, 20, 22, 23, 26, 27, 28, 30, 32), and my tier map of their users agrees (all users heavy, none default; controls: `dec15_flake_ref.py` default=1, a fabricated name 0). Row 26 says 107 heavy users; I count 109 test files that load the engine: 106 `cm_*_mutation_test.sh` and 3 engine-level mutation tests, all heavy | Correct the two counts in the analysis. No manifest change |
| F8 | S4 | process-doc | nit | The CON-071 evidence gives the GREEN file hash `9fc4ba1b...` "at vehicle 322c25e". The file at head is `770c41c9...`, because 35e8d53f changed the id in a comment. My own GREEN run was on the head file, so the GREEN holds, but the recorded identity is not the shipped one, and the re-mint will change the comment again | After the re-mint, record the GREEN hash of the file that lands (or both hashes) |
| F9 | S4 | process-doc | minor | CON-070 (Task, the test exists) and CON-071 (Bug, fixed, RED and GREEN recorded on the same command and target) are both `Queued` | At landing, set their status from the evidence (§11.4.290, §11.4.292(E), §11.4.294(D)). CON-071's surface is `host-only`, so `reproduced-host-fixture` counts as REPRODUCED and VERIFIED-DONE is reachable |
| F10 | S4 | process-doc | nit | The four code commits name Claude Sonnet 5.5 as co-author; the evidence files and the state records name Claude Opus 5.5 (written in the Opus commit 35e8d53f). Both can be true, but the evidence header says the investigation "captured" a fix that a Sonnet commit made | State in the re-minted items which model wrote the fix and which recorded the evidence |
| F11 | S3, S4 | process-doc | nit | §11.4.293(A): 322c25ef changes `capture_fc_timer_triplet.sh`, which is outside the CON-031 scope, without an `Out-of-scope:` trailer. 35e8d53f carries one for the con071 file only, not for the con072 and con073 files | In the landing merge message, add `Out-of-scope:` trailers for the triplet tool and the other two evidence files (reason `fix-gate-or-test`). Old messages are not rewritten (§11.4.113) |
| F12 | S2 | process-doc | nit | 485c341d says it adds 27 rows. It does; one of them (`tests/gates/test_gate_env_census_jq_regions.sh`) also landed on main with census-safe, so the net change against `ecfe432` is 26 rows. No duplicate row exists in the vehicle or in the merged tree | None needed; mention it in the landing message |
| F13 | S4 | process-doc | nit | The CON-073 title says main lacks rows for 26 census files. That was main `7f72395`; on `ecfe432` and on `efe2cc6c` it is 25 (the evidence file says this correctly) | Name the base in the title, or say 25 |

Findings outside the vehicle's diff (not counted against it; recommended as tracked items):

| Id | Layer | Severity | Finding | Action |
|---|---|---|---|---|
| X1 | test-instrumentation | important | `scripts/lumen/tests/test_gen_lumenignore.sh` FAILs in every full-suite run on every host. Its fallback looks for the binary under `$HOME/.claude-shared/...`, and the runner gives each unit a sandbox `HOME`; `LUMEN_BIN` is not in the runner's environment base. It then prints "SKIP: lumen binary not found" but exits 2, which `judge()` records as FAIL `rc_2`. Measured: sandbox `HOME` without `LUMEN_BIN`: rc 2 in 0 s; with `LUMEN_BIN` set: rc 0, 4 checks PASS. So the default coverage that row 31 (`fake_ollama.py`) claims exists only with `--env-extra LUMEN_BIN`. No tracker item covers this today | Register an item: the test must print what it does (FAIL naming the prerequisite, per O3), and the runner must pass `LUMEN_BIN` or resolve it in a preflight (FU-3) |
| X2 | process-doc | minor | The two orphan copies under `scripts/fastcycle/lib/` (see O2) are not only reworded: `dec23_key_ref.py` there computes a different key. For `mr_good_killed_reuse/put_envelope.json` the used copy (`tests/lib`) prints `dc6819b0...`, the orphan prints `4b6e4fc0...` (canonical JSON instead of U+001F-joined fields). The product `gates/mutation_reuse.py` uses U+001F-joined fields, like the used copy. The commit that added the orphans (a925a8da) says the libraries "were genuinely absent from disk despite an earlier evidence log claiming them shipped -- authored from scratch"; they were present in `tests/lib/` since e41f3b27, and the test reads only `$HERE/lib` | Operator decision O2 |
| X3 | process-doc | minor | The author's note on the engine: `workable-items update` records an evidence path but no sha256, while §11.4.294(C) asks for both. I found no tracker item for it on main | Register an item (FU-4) |
| X4 | process-doc | nit | `test_gen_lumenignore.sh` deletes `rm -rf "$W"` without `${W:?}` (§11.4.287(C)(1)). `W` comes from `mktemp`, and an empty `W` deletes nothing, so the risk is low | Fix together with X1 |

## 3. The six verification points

### (1) Classification of the 44 locked rows, the 2 new rows and the wave-2 row

- **All 13 changed notes** checked against the source: 12 are correct. Row 17 is wrong (F1). The three corrections in cd1e55ee (rows 6, 11, 19) are correct: the references they remove are comments.
- **Oracle rows (10 to 14, 16, 17, 19, 20)**: each test's assignment of the oracle path and its uses of that variable counted. Rows 10 to 14, 16, 19 and 20 are run with `python3 ... "$VAR"` (2 to 10 calls per test); row 17 only has an existence check (F1).
- **Heavy-only rows**: 10 rows, not 11 (F7). For each, every user is a heavy manifest row and no default row uses it. Instrument controls: a known default oracle gave default=1; a fabricated name gave 0.
- **Helper and library rows** (2, 15, 18, 21, 33 to 44): each has users in its directory (reference counts 1 to 23 with a fabricated-name control of 0). Rows 2 (`_paths.py`, imported by `test_cwd_independence.py`) and 35 (`repo_guard.sh`, sourced at `tests/decisions/run_all.sh:16`) were read in full. These counts show a reference, not an execution.
- **The 2 new excluded rows**: `check_safepath_census.py` is run by `test_fc_safepath_v4r12.sh` to `v4r15.sh` (`CENSUS=${FC_CENSUS_UNDER_TEST:-$HERE/check_safepath_census.py}`) and copied by `test_fastcycle_r6_mutations.sh`. `foreign_uid_cause.sh` is run by v4r12 to v4r15 and by `test_fc_supervisor_unit.sh`. All five users are default members of `scripts/fastcycle/tests/run_all.sh`, which runs every `test_*.sh` in the directory. The classification is correct.
- **Codegraph rows 4, 5, 6**: dynamic evidence now exists (see point 6). With the operator's PATH, `test_codegraph_mcp.sh` (9 of 9 cases, 79 s), `test_mcp_readonly.sh` (14 of 14, 119 s) and `run_scope_tests.sh` (cases plus 18 mutations, determinism PASS, 361 s) all exit 0 under a sandbox `HOME`. The analysis's "exit 2 BLIND" and "exit 3" hold only with a reduced PATH. The rows' D classification is therefore real on this host.
- **Wave-2 row** `tests/layout/hermetic_lint.py`: not re-checked. The wave-2 vehicle is not part of this bundle. It needs its own acceptance (O1).

In total about 30 of the 47 rows were checked against source, and the rest by reference count. Only the static evidence was available for most of the rows. See point 6 for whether that is sufficient.

### (2) `test_parse_mutation.sh`

Re-run in a sandbox: 10 of 10 checks PASS, all 9 paired mutants killed, 5.0 s wall (the author measured 4.7 s). Every mutant changes the source; the builder refuses a mutant that changes nothing. My 10 mutants: 3 killed, 7 survive (F5). The test is a real improvement over no test at all, which was the state before (row 3). Its fault model leaves the 7 gaps listed in F5.

### (3) `capture_fc_timer_triplet.sh` fix

Same test file on both sides (sha256 `17161f03...`).

- Main `efe2cc6c` (tool sha256 `17ca1cc0...`, the same pre-fix file the evidence names): rc 1, 25 checks ok, one fails. `NOT ok (H15) rc=2: FATAL: pre-build script not found: .../device/rockchip/rk3588/tests/pre_build_verification.sh`. 71 s.
- Vehicle `cd1e55ee` (tool sha256 `770c41c9...`): rc 0, 26 checks ok. `ok (H15) rc=2 before anything ran`. 100 s.

The fix moves the existence check after the mode decision. The mode decision only compares strings and reads no file. In a consumer tree the result does not change; only the order of two refusals changes. No other check moved. GO.

### (4) Manifest

- `--verify-manifest` on the vehicle: exactly one problem, the excluded-lock difference (2 rows added, 13 notes changed). Census total 844.
- The same on the trial merge with `efe2cc6c`, after `--sync-guide`: exactly one problem, the lock difference. Census total 847: main's three new entries already have rows.
- Main `efe2cc6c` today: 25 problems ("census file without manifest row"), and the runner refuses to run anything. CON-073 still reproduces on current main.
- The rows added against `ecfe432` number 26 (F12). No duplicate paths.
- No `test_*` file is excluded. The two new excluded rows are a census tool and a probe, run by default tests (point 1). No real test is excluded to hide a failure (§11.4.27, §11.4.289).

### (5) Tracker items

Content: the reproduction records are complete and honest. CON-071 has a RED and a GREEN on the same command, target and signature (§11.4.292(E)). CON-072 records a toggle experiment and says it is evidence, not a fix. CON-073 says `root-cause-unconfirmed`. The ids must be re-minted (F2, F3). Re-mint plan:

| Vehicle id | Type | Proposed id on main (if nothing else lands first) | Evidence file after rename |
|---|---|---|---|
| CON-070 | Task | CON-083 | none |
| CON-071 | Bug | CON-084 | `docs/qa/con084_reproduction_2026_11_05.txt` |
| CON-072 | Bug | CON-085 | `docs/qa/con085_reproduction_2026_11_05.txt` |
| CON-073 | Bug | CON-086 | `docs/qa/con086_reproduction_2026_11_05.txt` |

Always take the ids from the engine at the moment of landing. If the CON-030 vehicle or another vehicle lands first, they move. In-tree references to update with the new ids:

- `config/full_suite_manifest.tsv`, row 51 note (CON-070). This row is an entry, not excluded, so the lock is not affected.
- `scripts/catalog-engine/tests/test_parse_mutation.sh`, line 2 (CON-070).
- `scripts/fastcycle/tests/capture_fc_timer_triplet.sh`, line 135 (CON-071, a comment).
- `docs/scripts/catalog_engine_parse_gate.md`, lines 68 and 70.
- The three evidence files: name, header line, and `con072` line 36.
- The item rows themselves; then regenerate `docs/Issues.md` and `docs/Issues_Summary.md`.

In each item, record "first minted in the vehicle as CON-064..067, then CON-070..073", because commit messages 4db86ed6, 485c341d and 322c25ef name the first ids and are not rewritten (§11.4.113, §11.4.214).

### (6) Open facts, and static against dynamic evidence

- **Orphan copies**: see X2 and O2. They were not deleted.
- **Missing tool counted as FAIL**: see O3. The runner's `judge()` maps 77 to SKIP and every other non-zero exit to FAIL.
- **Codegraph and lumen exit codes**, measured in this review with the operator's PATH and a sandbox `HOME`:

| Unit | rc | Time | Result |
|---|---|---|---|
| `scripts/codegraph/tests/test_codegraph_mcp.sh` | 0 | 79 s | 9 of 9 cases pass |
| `scripts/codegraph/tests/test_mcp_readonly.sh` | 0 | 119 s | 14 of 14 pass |
| `scripts/codegraph/tests/run_scope_tests.sh` | 0 | 361 s | cases and 18 mutations pass, determinism PASS; `CODEGRAPH_RUNNER_DIST` was not set, it was resolved through `--resolve-dist` |
| `scripts/lumen/tests/test_gen_lumenignore.sh` | 2 | 0 s | prints "SKIP: lumen binary not found" (X1) |
| the same with `LUMEN_BIN` set | 0 | 4 s | 4 checks pass |

- **Dynamic evidence this review produced**: the parser test and my mutants; the triplet RED and GREEN; `--verify-manifest` on vehicle, merge and main; the four codegraph and lumen runs; the hashes of both oracle copies on one fixture; `git merge-tree` for the conflicts.
- **What rests on static evidence only**: the D classification of most helper, library and oracle rows (the author traced 13 of 44 files as opened; 31 are not traced). Static evidence is enough to keep a row excluded when two things hold. First, the reference must be one that runs the file (`source`, `import`, `python3 "$VAR"`, `bash "$X"`), not a comment and not an existence check; F1 shows what happens when this is not checked. Second, the covering default unit must itself pass where the suite runs. Three default fastcycle RED tests (`test_flake_ledger_red.sh`, `test_backstop_red.sh`, `test_render_keys_red.sh`) FAIL in every standalone clone (CON-006), so the default coverage of oracles 12, 13, 16 and 17 exists only in a consumer tree. The FAIL is visible, so nothing is hidden. Static evidence does not prove that the coverage is live, and the vehicle does not claim that. The traces that are not finished (`test_check_deps.sh` without strace, the units of `tests/decisions`, `extensions`, `install`, `jev`, `layout`, `prompts`, and every heavy unit) remain owed work. They do not block this vehicle, because it changes no runnable unit except the one new test and the one triplet fix, both measured.

## 4. Merge with main `efe2cc6c`

`git merge-tree` of `cd1e55ee` and `efe2cc6c` (merge base `ecfe4325`) gives 5 conflicts. The manifest merges cleanly.

| File | Kind | Resolution without loss |
|---|---|---|
| `docs/workable_items.db` | binary | take main's database and re-register the four items with the engine (L1) |
| `docs/Issues.md`, `docs/Issues_Summary.md` | content | regenerate from the database after L1 |
| `docs/qa/con071_reproduction_2026_11_05.txt` | add/add | keep main's file unchanged; the vehicle's three files are renamed (L2) |
| `docs/guides/full_suite_runner_guide.md` | content (generated census line) | run `bash scripts/run_full_suite.sh --sync-guide` |

## 5. Landing steps (conductor)

- **L1**: Merge main into the vehicle (merge, never rebase). Take main's database and register the four items through the engine; the ids are the next free ones (CON-083 to CON-086 today). Copy the state fields and the evidence references from the vehicle rows. Set the statuses from the evidence (F9). Regenerate the Issues files.
- **L2**: Rename the vehicle's three evidence files to the new ids and update the in-tree references listed in point 5. Record the old ids in each item.
- **L3**: Fix the row 17 note (F1) in the same merge, before O1.
- **L4**: Run `--sync-guide`. Then `--verify-manifest` must report exactly one problem, the lock difference, with the same 2 added rows and 13 changed notes as before. Run `test_parse_mutation.sh` and `test_capture_fc_timer_triplet.sh` once more on the merged tree, and record the GREEN hash of the landed triplet tool (F8).
- **L5**: Fast-forward main to the merged vehicle and push to every upstream; then retire the vehicle (§11.4.288). Add the `Out-of-scope:` trailers to the merge message (F11).

Follow-up items to register:

- **FU-1**: adopt the 7 surviving mutants (F5); `rv_require_close` goes with the CON-072 fix.
- **FU-2**: have a test run `render_keys_ref.py` against the key fixtures (F1).
- **FU-3**: make the lumen test and the runner honest about the lumen binary (X1, X4).
- **FU-4**: record the sha256 of evidence files in the engine (X3).
- CON-073's seam (the commit-time check) is already tracked.

## 6. Decision brief for the operator (O1 to O4)

**O1. Accept the excluded-lock changes?** Recommendation: yes, after L1 to L4. The change adds 2 rows (a census tool and a probe, both run by default tests) and accepts 13 changed notes; 12 are correct now and the 13th is fixed in L3. Until you accept, the full-suite runner refuses to run on main. It already refuses today, with 25 problems. The wave-2 row `tests/layout/hermetic_lint.py` needs a separate acceptance when that vehicle lands.

**O2. The two orphan copies under `scripts/fastcycle/lib/`.** Recommendation: retire both as obsolete duplicates (§11.4.90), with your approval (§11.4.122, §11.4.124). Do not point the test at them; the plan's option (b) suggested that, and the evidence is against it. They were written on 2026-09-30 by a commit that believed the libraries were missing; in fact the libraries were in `tests/lib/`, the only place the test reads. Nothing has ever loaded them. The `dec23_key_ref.py` orphan computes a different key from the copy in use, and the copy in use follows the same field-joining rule as the product (`mutation_reuse.py`). Retiring them loses nothing, because git keeps them.

**O3. A test whose host tool is missing: FAIL or SKIP?** Recommendation: keep FAIL, but report it as a missing host prerequisite with the tool named, never as a product failure, so it is not a FAIL-bluff (§11.4.1). Concretely: list the codegraph package and the lumen binary as full-suite prerequisites in the runner guide; check them in a runner preflight by running them; and fix the lumen test, which prints SKIP and exits 2, and which also cannot find the binary under the runner's sandbox `HOME` (X1). The codegraph tests pass on this host when the runner is started from your normal shell: all three exit 0. Note that §11.4.289(E) prefers a SKIP with a closed reason code for an absent real dependency. The §11.4.69 set has no "tool not installed" code. If you prefer a SKIP, that means choosing or adding a code, which is your decision.

**O4. Default-tier override for fast tests with heavy-looking names.** Recommendation: allow it only when the wall time is measured under 60 s on this host and recorded in the row's note, as row 51 does (4.7 s; re-measured here at 5.0 s). Keep real mutation sweeps heavy. The candidates have not been measured yet; that is owed work, not part of this vehicle.
