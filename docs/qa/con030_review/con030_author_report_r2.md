# CON-030 fix round 2: author report

| Field | Value |
|---|---|
| Vehicle | vehicle/con030 head fc7e114f7f3441f9728c7daa2d25083623b3638f (clone /home/milosvasic/.cache/claude-tmp/con030v.xJXMAR/c) |
| Base | origin/main ecfe432 (census-safe landed), merged into the vehicle (11c3c3d); main is an ancestor, so the landing can be fast-forward |
| Bundle | /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/con030_r2.bundle, range origin/main..vehicle/con030 (7 commits), `git bundle verify` okay, sha256 2f4f0c2b8b5abc24864652b37d4958442db8498b37db8b4f98b3aacda9e16d71 |
| Author | subagent on Opus 5.5 (effort cannot be set or read on this dispatch path, so none is claimed, section 11.4.231(F.2)) |
| Pushed | no |
| Evidence root | /home/milosvasic/.cache/claude-tmp/c30r2.eVpCZG (fresh HOME and TMPDIR; logs under `logs/`) |
| Independent review | owed (section 11.4.142 / 11.4.209); this is round 2 of at most 5 |

## Commits (origin/main..vehicle)

| commit | what |
|---|---|
| 364f1c0 | merge of main 7f72395 (from round 1 setup) |
| 8dde551 | the fix: engine, tests, mutation file, runner header, guide (Roadmap-Item CON-030) |
| 805952e | registration of the F5 class item as CON-064 |
| 993fffb | revert of 805952e: census-safe took ids 064-069 on main, so 064 collided. The commit was never pushed; history is not rewritten (section 11.4.113) |
| 11c3c3d | merge of main ecfe432 (clean, no conflict) |
| fc7e114 | F5 class item registered again with the engine, as **CON-070** |

Trailer note: 8dde551 carries `Co-Authored-By: Claude Sonnet 5.5` as the brief asked. That is not accurate, because this work ran on Opus 5.5. The two tracker commits carry `Claude Opus 5.5`. I did not amend 8dde551 (no history rewrite). The conductor may record the correction in the landing merge message.

## What changed, finding by finding

- **F1 (important, regression), fixed structurally.** Class: parsing a human-oriented, unquoted `git submodule status` line. The paths no longer come from the status text at all. The new `known_sub_paths()` reads the gitlinks with `git ls-files -s -z` (NUL-separated, never quoted) for the root and, recursively, for every submodule whose working tree has a `.git`. The new `parse_sub_status(line, known)` takes only the flag and an exact 40- or 64-hex sha from the line. The rest of the line must be exactly one known path, or, on a ` `/`+` line, one known path plus ` (<describe>)`, where the describe is non-empty and has no space (it may contain `(` and `)`; only the last ` (` can start it). A line with zero or more than one candidate is the gap `unparseable git submodule status line (...)`: fail closed, nothing guessed. This also removes round 1's residual limit (1): an uninitialised `x (xyz)` is now named whole.
- **F2, fixed.** `status_lines()` splits on `"\n"` only. A path with a CR now reads whole (measured: on main the fixture counts 8 status lines for 7 submodules and gives 4 bogus gaps; round 2 counts 7 lines and gives 0 gaps).
- **F3, fixed.** The false claim "git cannot record a newline" is gone from the docstring and the commit message. A newline path made with a hand-written `.gitmodules` is now a real-git test: git prints it across two lines, and both fragments are gaps.
- **F4, fixed.** `submodule_paths()` reads `git config --null --get-regexp` and `ls-files -s -z`. It now returns the exact path set for spaced, CR, parenthesised, `?`, `=` and leading/trailing-space paths (tested). Round 1 returned values like `'(xyz).path x (xyz)'`.
- **F5, registered, not fixed here** (scope, section 11.4.293(A)): **CON-070** (Bug, Medium) lists every member. I measured the two the review left UNCONFIRMED:
  - `baseline_replay.sh:1049` loop shape gives name=[submodules/my], path=[engine.path submodules/my engine] for the spaced submodule; the plain submodule is read correctly.
  - The `cm_helix_deps_ref_matches_gitlink.sh:79` awk `$2==p` lookup gives key=[] for `submodules/my engine`, so line 79 reports a false DRIFT; the plain path's key is found.
  - The effect of each at the level of the whole tool stays UNCONFIRMED.
- **F6, fixed.** RA (SHA-256 width), RB (`-` filter in `sub_paths`) and RF (`.strip()`) are now mutants in the file, and each is killed (below). The kills come from a 64-hex table row, a fresh uninitialised clone, and real ` lead`/`trail ` paths.
- **F7, fixed.** The unparseable-line gap is documented in the `scripts/run_full_suite.sh` TOPOLOGY header and in the guide's Topology preflight section. The guide is now revision 7.
- **F8, fixed (cheap).**
  - `ident_fields()` reads each value after the last `=`.
  - `ident_unknown()` checks `?` per field value. Both `"?" in qid` call sites now use it, and the I1 anchor was updated.
  - Tested: a submodule `q?` no longer stops a run, and `ident_diff` names `k=v` when its HEAD moves.
- **F9.**
  - The unused third argument is removed.
  - A real-git fixture now covers the unparseable branch (the newline path). The shim test stays as a gate-logic test.
  - Mutant ids: M30a-M30d were NOT renamed. I kept them for traceability with the round-1 review and the brief. The header now says they, and M30e-M30n, are unrelated to the lock mutant M30.
- **F10.** This report gives the sha256 of every log. The CON-030 reproduction and investigation states are left to the conductor at landing, because the engine needs an evidence path that resolves in the repository. Suggested: `reproduction-state reproduced-host-fixture`, surface `host-only`, `investigation-state root-cause-found-with-evidence`. Root cause: the paths were cut out of an unquoted, human-oriented status line.
- **F11, fixed.** New case R2b: a suite writes an ignored file (`out.dat` listed in `.gitignore`). The test asserts rc 1, `RESULT: FAIL (repository tree changed during the run; ...)` and no identity-change message. The old reviewer mutant R2 is now killed (2 failing checks).

## Measured results (this session)

| check | result | log (under c30r2.eVpCZG/logs) | sha256 |
|---|---|---|---|
| RED: new tests on the round-1 engine (da9d425 + main merge) | passed=253 failed=10, rc 1. All 10 failures are CON-030 r2 checks; the 5 precondition checks (git really printed `heads/feat(x)`, `v1(beta)`, `v2)`, `x (xyz) (heads/`, `nest ed/in ner (heads/`) passed; R2b passed (it tests existing logic and is RED only against mutant R2) | red_r2_on_head.log | 0b68f67dfeedc0461b781a01d44da022249baaabd868b5ff7d8ccefea40c5486 |
| GREEN after the fix (before the header comment edit) | passed=263 failed=0, rc 0 | green_r2.log | f506edc17056e9d97081d81de866748345138c3521226061dde319b22c3dbca7 |
| GREEN on final head fc7e114 | passed=263 failed=0, rc 0 | green_final_fc7e114.log | 915dc367e0289cf342d59c827962cc420faf867a37d1175c2b121b83c4197eaf |
| Mutants M30a-M30e (shard t1) | 5/5 killed, baseline ok | mut_t1.log | 7a373b7de209333e2fd9f45026884d5f2b56d11eeb205b45cab5421620e15c10 |
| Mutants M30f-M30j (shard t2) | 5/5 killed | mut_t2.log | 1e54c972ba69b5652a6a11b6727791bbc4eb2359e9ae4a19f6cb2d3af9fb8c8b |
| Mutants M30k-M30n, RA (shard t3) | 5/5 killed | mut_t3.log | 03575113d6b50adaaf0877050e95f0c29a5d932107f0d837c32cc86f89b0f426 |
| Mutants RB, RF, R2, I1 (shard t4) | 4/4 killed (R2 was a survivor in round 1) | mut_t4.log | f3601f4586af26173931b9c53cbab1cee17ccd7cf8faf07e281f195a3d3aa758 |
| Anchor check over the whole mutation file (111 mutants) | every anchor occurs exactly once in the new engine; none is not-applicable | (inline check) | - |
| Differential on the real repository (32 submodules), main engine vs round 2: sub_paths, topology, submodule_paths, quick_ident fields | byte-identical | diff_real_main.txt / diff_real_r2.txt | 6314bf4a915ada188f7fe0fb7ff7c1ee12431d60c94a596ba6da485526cd11ee (both) |
| Differential on a fixture (branch feat(x), tags v1(beta) and v2), `x (xyz)`, ` lead`, `trail `, CR) | main: truncated paths, 4 bogus gaps, 8 lines counted. r1: describes swallowed, 5 gaps. r2: all paths whole, 0 gaps | diff_fixture.txt | 26e8f76d80aa4c5f4cff54a263a2cbdf76a654d1efd9857fe14fc4c37dfb74a2 |
| `--verify-manifest`, real repository at main ecfe432, main runner vs round-2 runner | both rc 3, 25 problems, stdout and stderr byte-identical | vm2_main_real.out/.err, vm2_r2_real.out/.err | out 086214c2...b8517d, err 4790be15...fcf |
| `--verify-manifest` on the merged vehicle clone | rc 3, the same 25-problem set (stdout and stderr identical to main's run on main) | vm2_r2_vehicle.out/.err | same hashes as above |
| Tracker after CON-070 | `validate`: OK, 69 items; `diff`: DB and Markdown in sync (69/69) | report_item2.log | - |

Mutation coverage: 19 mutants were run (M30a-M30n, RA, RB, RF, R2, I1), and all 19 were killed. The remaining 92 mutants of the file were not re-run in this round, because of host load (load average about 35 on 16 cores). Their anchors all apply. The engine code they target is unchanged, except the I1 site, which was run. The shard baselines, plus two full GREEN runs, show that the unmutated copy passes.

## Known limits (stated, not hidden)

- **Newline paths.** A path containing a newline is a gap (fail closed), never read whole.
- **Ambiguous ` `/`+` lines.** If such a line has no describe, and its text is both a known path and a known path plus a describe, it is a gap. Example: `x (y)` when both `x` and `x (y)` exist. git almost always prints a describe, because of `--all --always`.
- **Same code path, measured.** `known_sub_paths()` and the status output are decoded with the same `errors="replace"`, so a path that is not valid UTF-8 matches the same way. This was not tested with such a path.
- **Nested sha width.** A SHA-256 superproject with SHA-1 submodules is not handled specially: each line accepts either width and must still match a known path.
- **F5 members.** Not fixed; tracked as CON-070.

## Real repository

Only read-only commands ran against /home/milosvasic/Projects/constitution (submodule status, ls-files, config, `--verify-manifest`). Its porcelain count flickered between 0 and 1 during the session from another agent's activity. It was 0 at the last check. None of my commands write there.
