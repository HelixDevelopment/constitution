# Ambient git variables, round 3: a closed-world census over scripts/ and tests/ (2026-11-15)

| Field | Value |
|---|---|
| Item | CON-402 round 3 (minted at the landing on main) |
| Base | `005bcfd1` (round 2 evidence), which sits on main `bd0036bd` |
| Commits | `4da0fa1b` (code, rows, fixtures) and the following commit carrying this pack |
| Status | PROVISIONAL, gate-logic class (host checks only; independent review pending) |
| Producer | Claude Opus 5.5 (fresh structural fixer subagent, §11.4.276(E)); effort not settable on this dispatch path, not claimed |
| Review answered | NO-GO of round 2 (`review_gitenv_r2.md`), findings R3-1 to R3-4 |

Scratch paths in these files are shown as `<scratch>`, temp dirs as `<tmp>`, the home directory as `<home>`; a path cut short
in a table cell shows its prefix as `<work>`. The synthetic credential-shaped tokens that `tests/extensions/lib.sh`
(`fake_token`) builds at run time are shown as `<fake_token:gh>`, `<fake_token:sk>` and so on (10 replaced).

## R3-1: membership is now closed-world, not a list of call shapes

Round 2 made a file a member only when its write detector saw a git write in it. The reviewer found git
called through `$GIT`, `"${G[@]}"`, `$GITBIN`, a Python helper `g("init")` and `_git(repo, ["worktree"...])`:
each shape the detector did not know was a member that was never checked. Adding shapes one at a time would
leave the next shape open, so round 3 replaces the membership rule (the structural change, §11.4.276(E)(3)):

- **Universe.** Every tracked code file under `scripts/` and `tests/`: shell, Python and JavaScript (by
  extension or shebang), any other shebang language, and Go.
- **Member.** A universe file whose raw text contains `git` in any form (`(?<![A-Za-z])git`,
  case-insensitive: comments, strings and names such as `GITBIN` or `GIT_DIR` count). A file that runs git
  has to name it somewhere. Over-inclusion is deliberate; `digit` is not a member.
- **Rule.** Every member carries an effective file-level scrub (HERMETIC), or a row in
  `config/git_env_class_exemptions.tsv` with a reason from a closed set that the census checks against the
  file (EXEMPT). Anything else is UNSCRUBBED, and a row that covers no member, or covers a HERMETIC file, is a
  stale row (FAIL).
- **Write detector.** Kept only as a second check on rows: a `no-git-execution` row FAILs when a write is
  detected, a `sourced-library` row FAILs when a detected write is outside a scrubbing wrapper, and a write
  under a `fixture-tree` prefix needs its own row. It now also knows the five shapes of the review.

Inventory on the fixed tree (`census/census_final.txt`): tracked=2691, universe=1627 (sh 1254, py 185,
go 177, js 11), members=513, hermetic=449, exempt=64 (31 rows), unscrubbed=0, 80 control-needle samples seen.

RED first, on the unchanged tree `005bcfd1`:

- `red/census_v3_on_005bcfd1.txt`: the round-3 census reports members=513, hermetic=129, exempt=4,
  unscrubbed=380; all seven files the review named are flagged: `scripts/gates/cm_rule_binds_to_seam.sh` and its mutation test (`$GIT`), `cm_gitlink_on_remote_mutation_test.sh` and `cm_helix_deps_ref_matches_gitlink_mutation_test.sh` (`"${G[@]}"`), the v4r8 and v4r9 fastcycle tests (`g("init")`) and `scripts/fastcycle/fc_supervisor.py` (`_git(repo, [...])`).
- `red/sent_gates_red.txt`: under `GIT_DIR` aimed at a sentinel repository, the sentinel CHANGED for
  `cm_rule_binds_to_seam.sh --selftest` (exit 0: a false PASS that committed into the sentinel), its mutation
  test, `cm_gitlink_on_remote_mutation_test.sh` and `cm_helix_deps_ref_matches_gitlink_mutation_test.sh`.
- `red/sent_fastcycle_red.txt`: v4r8 under `GIT_DIR`: exit 124 and the sentinel CHANGED (objects 3 to 9); v4r8 with no variable: exit 0, pass=235 fail=0 skip=95, sentinel UNCHANGED. v4r9 under `GIT_DIR`: exit 1, sentinel CHANGED; v4r9 with no variable: exit 124 (the 1200 s timeout under host load; not a defect claim).

The fix inserted the canonical line into 312 entry files and 8 test libraries (`insert_run*.txt`, tool
`tools/insert_scrub3.py.txt`; each insertion was parse-checked and re-judged by the census, else restored),
added the JavaScript form to `scripts/codegraph/scope_enumerate.js`, and gave 31 rows to the rest:
12 sourced-library (a top-level scrub would clear the caller's own variables; one is sourced into the
operator's interactive shell), 9 no-git-execution, 6 fixture-tree prefixes, 2 pinned-fixture, 1
entry-function-scrub, 1 go-binary-owed.

GREEN on the fixed tree:

- `sent_gates_green.txt`: every gate file leaves the sentinel UNCHANGED with no variable and under `GIT_DIR`, with the same exit as the no-variable run (`cm_gitlink_on_remote_mutation_test.sh` exits 1 in both: 18 passed, 1 failed, pre-existing, FU-6).
- `sent_fastcycle_green.txt`: timeout 2700 s. v4r8: `GIT_DIR` exit 0, pass=235 fail=0 skip=95, UNCHANGED (663 s); no variable exit 0 (674 s). v4r9: `GIT_DIR` exit 0, pass=320 fail=0, UNCHANGED (2168 s); no variable exit 0, pass=320 fail=0 (2199 s).

## R3-2: a legacy scrub counts only when its clear operates on the list

`list_clear()` now requires an `unset` that names every variable of the list, or a `for V in ...` loop whose
body runs `unset "$V"`. The reviewer's RM1 shape (the loop body replaced by `: "$_v"`, an unrelated `unset`
elsewhere) is fixture C2ac (UNSCRUBBED) with its positive twin C2ac2, plus a control needle.

## R3-3: the pass counts depend on a checked-out `submodules/continuum`

`tests/test_git_env_class.sh` runs the anchor-record gate, which needs `submodules/continuum`. In a plain
clone that path is empty and the case is an honest SKIP, so the counts differ:

| Run | `submodules/continuum` | passed | failed | skipped |
|---|---|---|---|---|
| `--fast` (`final/fast_nocontinuum.txt`) | empty | 89 | 0 | 2 |
| `--fast` x3 (`final/fast_continuum_{1,2,3}.txt`, byte-identical, sha256 `32ffa0934cd1fc50...`) | `213ad07b` | 97 | 0 | 1 |
| full (`final/full_continuum.txt`) | `213ad07b` | 101 | 0 | 0 |

The skip without continuum is case B1 (`cm_anchor_record_complete.sh`).

To reproduce the full counts, check out the continuum pin recorded in the parent's gitlink first.

## R3-4: what the class does not cover

The class is the 14 repository-locating names of `CL_GIT_SCRUB_VARS`. Other git variables change git's
behaviour and are out of scope: `GIT_CONFIG_*` / `GIT_CONFIG_PARAMETERS`, identity, transport and template
variables; the pathspec variables (`GIT_LITERAL_PATHSPECS`, `GIT_GLOB_PATHSPECS`, `GIT_NOGLOB_PATHSPECS`,
`GIT_ICASE_PATHSPECS`; the reviewer measured that `GIT_LITERAL_PATHSPECS=1` makes `git add 'g*'` fail, a
possible false null for a gate that globs with git, and found no gate doing so); `GIT_ATTR_SOURCE`
(attributes from a tree); and `GIT_EXEC_PATH` (no effect on builtins measured). The same text is in the
census docstring. `GIT_CEILING_DIRECTORIES` and `GIT_DISCOVERY_ACROSS_FILESYSTEM` stay unscrubbed (round 2).

## Mutants (`mutants/`, tools `tools/mk_mut3.py.txt`, `tools/run_mutants3.sh.txt`)

Each mutant is applied to a fresh worktree of `005bcfd1` plus this round's change; it is KILLED when the
census or `tests/test_git_env_class.sh --only-census` exits non-zero. A `_nn` twin also turns off the census's
own control needles, so that only the test fixtures can kill it. `NONE` and `NONE_nn` are the controls.

| Mutant | Result | Mutant | Result |
|---|---|---|---|
| NONE (control) | SURVIVED | NONE_nn (control) | SURVIVED |
| RM1 | KILLED | RM1_nn | KILLED |
| RM2 | KILLED | RM2b | KILLED |
| RM3 | KILLED | RM4 | KILLED |
| RM5 | KILLED | M1 / M1_nn | KILLED / KILLED |
| M2 / M2_nn | KILLED / KILLED | M3 / M3_nn | KILLED / KILLED |
| M4 / M4_nn | KILLED / KILLED | M5 | KILLED |
| M6 / M6_nn | KILLED / KILLED | M7 / M7_nn | KILLED / KILLED |
| M8 | KILLED | M9 / M9_nn | KILLED / KILLED |

23 killed, 2 controls survived (`mutants/mutants_final.tsv`). M6_nn and M7_nn survived a first run; fixtures C2ah
(a canonical line inside a multi-line string), C2ai and C2ai2 (a JavaScript scrub after a statement or after the
git call) were added, and both are KILLED now. RM1, RM2b and RM2 to RM5 are applied as the review describes them
(`tools/mk_mut3.py.txt`); the reviewer's own tool was not run.

## Required checks on the final tree

| Check | Result |
|---|---|
| census (`final/census_final.txt`) | PASS, exit 0 |
| `tests/test_full_suite_manifest_gate_git_env.sh` | passed=14 failed=0 |
| `scripts/gates/cm_full_suite_manifest_complete_mutation_test.sh` | MUTATION PAIR VALID |
| `tests/test_round8_git_env.sh` | PASS=133 FAIL=0 |
| `scripts/run_full_suite.sh --verify-manifest` | MANIFEST-OK |
| `scripts/fastcycle/tokens/test_dispatch_stamp.sh` (`final/test_dispatch_stamp_final.txt`) | PASS=295 FAIL=0 |

One more defect was found while testing: the scrub had been placed before the xtrace-silencing line of
`scripts/fastcycle/tokens/dispatch_stamp.sh`, so under the caller's `SHELLOPTS=xtrace` the extract mode wrote the
trace on stderr (the RV11-2 case of its test failed). The scrub now follows that line; the census preamble accepts
`{ set +o xtrace ...; } 2>/dev/null` before the scrub, with two new needles; the test passes 295/0 on both trees.

## Regression (`regress/`, tool `tools/regress3.sh.txt`)

Every test the round touches (193, from `tools/regress_list2.txt.txt` and its tail list; the v4r8 and v4r9
fastcycle tests are covered by the sentinel runs above) ran on the unchanged tree `005bcfd1` and on the fixed tree,
with no git variable set, one test at a time per job (`regress/regress.tsv`, logs in `regress/logs_head/` and
`regress/logs_tail/`). Two jobs ran at once: rows 1 to 140 (`tools/regress3.sh.txt`) and rows 141 to 193
(`tools/regress3_tail.sh.txt`, with its own temp files and log directory). 191 of 193 rows exit the same on both
trees. The two others:

- `scripts/fastcycle/tokens/test_dispatch_stamp.sh`: 0 on the unchanged tree, 1 on the first fixed tree. That was
  the defect described under "Required checks"; after the fix the test passes 295/0 on the fixed tree
  (`final/test_dispatch_stamp_final.txt`).
- `tests/decisions/test_own_mutants.sh`, row 92: the stored row is not a measurement. An earlier version of the
  tail job shared the temp file of the head job, so its start emptied the base result of this row (the base field
  is empty) while the fixed tree's run hit the 900 s timeout. The rerun (`regress/regress_row92_rerun.tsv`,
  `tools/regress3_row92.sh.txt`, logs in `regress/logs_row92/`) used its own files and a 2400 s timeout: both trees
  exit 124, both at the same mutant (`R6S10_gitmodules_strict_utf8`, test_round6 pass=90 fail=4 at that point).
  The two trees behave the same up to the timeout. The test did not finish on either tree, so this row is not a
  pass.

For a short time while the first mutant run started, three jobs ran at once instead of at most two (the mutant
job was light). A `jev_server.py` fixture leaked once per tree during `tests/jev/test_detection_matrix.sh`; it is the
same on both trees (FU-9), and both processes were stopped by PID.

## Follow-ups

`FOLLOW_UPS.md`: FU-1, FU-2, FU-3 and FU-5 carried from round 2; FU-4 closed by this round; new FU-6,
FU-7 and FU-9 (pre-existing defects seen while testing) and FU-8 (keeping the rows honest).

## Honest boundary

Host checks only; no independent review of round 3 has run. The census proves that every member under
`scripts/` and `tests/` has an effective scrub placed before its first write, or a checked row; it does not
prove that every git call of a member is reached under every input. A file that runs git without the letters
`git` in its text is not a member. The rows of reasons `sourced-library` and `entry-function-scrub` rest on a
reviewed reading plus the write detector, not on a decidable property.

`SHA256SUMS` lists every file of this pack.
