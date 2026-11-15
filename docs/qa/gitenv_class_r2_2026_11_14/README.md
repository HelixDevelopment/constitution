# Ambient git variables, round 2: keep the caller's discovery limit; census sees heredocs, wrappers and no-op scrubs (2026-11-14)

| Field | Value |
|---|---|
| Item | CON-402 round 2 (minted at the landing on main) |
| Base | `e0373341` (round 1 evidence), which sits on main `bd0036bd` |
| Commits | `aee1ef04` (fix), `4a2a915f` (census needles and fixtures), this evidence commit |
| Status | PROVISIONAL (host checks only; independent review pending) |
| Producer | Claude Opus 5.5 (fresh fixer subagent); effort not settable on this dispatch path, not claimed |
| Review answered | NO-GO of round 1, findings F1 to F5 |

Scratch paths in these files are shown as `<scratch>`, temp dirs as `<tmp>`, the home directory as `<home>`.

## F1: `GIT_CEILING_DIRECTORIES` is a limit the caller sets, never a variable to clear

`classify_vars.txt` (git 2.53.0; `man_git_excerpts.txt` quotes git's own manual) runs each of the 16 git
environment names with and without the variable set, against a target repository and a decoy:

- REDIRECT (10 names): the variable sends reads or writes somewhere else. They stay in the scrub.
- FOREIGN (`GIT_PREFIX`, `GIT_INTERNAL_SUPER_PREFIX`), TRANSFER (`GIT_NAMESPACE`), VIEW
  (`GIT_NO_REPLACE_OBJECTS`): set by git or a wrapper for its own child; they stay in the scrub.
- LIMIT (`GIT_CEILING_DIRECTORIES`): with it set, discovery stops at the ceiling (`fatal: not a git
  repository`). Clearing it lets a script under a sandbox ceiling discover the enclosing repository and
  write there: the opposite of what the scrub is for.
- WIDEN (`GIT_DISCOVERY_ACROSS_FILESYSTEM`): only widens discovery when the caller asks; never scrubbed.

The canonical list `CL_GIT_SCRUB_VARS` (`scripts/lib/constitution_layout.sh`) is now 14 names; every
canonical line and every lone copy was regenerated from it (`regen_run.txt`, tool
`tools/regen_scrub_lists.py.txt`), the manifest gate and its mutation test go from 30 to 29 names.

RED first: `red_test_on_e0373341.txt` is the round-2 `tests/test_git_env_class.sh` run against the
round-1 tree: passed=27 failed=17 skipped=1 (K4: 103 members cleared the ceiling; K5: the install test
sandbox lost its ceiling). GREEN on the final tree, below.

## F2, F3: the census now sees what round 1 missed

The census (`scripts/validation/git_env_class_census.py`) now:

- strips comments and docstrings before matching, and requires the shell canonical line at column 0 in
  the file's preamble; the Python scrub is checked on the syntax tree;
- finds wrapper functions that call git (`g() { git "$@"; }`, and wrappers of wrappers) and Python
  heredocs inside shell files;
- counts an `env -i ... git` wrapper as scrubbed, and a legacy scrub only when it really clears;
- FAILs a scrub that clears nothing, or that comes after the first git write (the M8/M9 shapes);
- is BLIND (exit 2) when the canonical list holds a discovery limit (`census/census_r2_on_e0373341.stderr.txt`:
  on the round-1 tree it reports exactly that).

It found 15 more unscrubbed members, including the Python heredoc in `test_anchor_citations_red.sh` and
the wrapper `g` in the custody r15 test (`insert_run.txt`, tool `tools/insert_scrub.py.txt`). Final census:
`census/census_final.tsv`, members=133 hermetic=130 exempt=3 unscrubbed=0, 39 control-needle samples seen.

## F4: mutants

- Census mutants (`census_mutants.txt`, `mutants/census/`, tool `tools/mk_r2_mutants.py.txt`): 15 mutants
  of the census, each also with its needles turned off: killed=30 survived=0. The first run left 8 alive
  (no-op legacy scrub, limit in the canonical list, scrub order, docstring carrier); they are killed by the
  new needles and fixtures C2u, C2v, C2w, C3b of commit `4a2a915f`.
- Behaviour mutants (`behaviour_mutants.txt`, `mutants/behaviour/`): the reviewer's M1 to M9 (applied with
  the reviewer's own `mkmut.py`) and N1 to N5 (`tools/mk_r2_behaviour_mutants.py.txt`): 14 of 14 killed.
  M6 is killed by `--fast` (B2b), M7 by the census, N5 (the manifest gate clears the ceiling again) by the
  new manifest check L3.

## Required checks on the final tree (`final/`)

| Check | Result |
|---|---|
| `tests/test_git_env_class.sh --fast`, three runs | passed=51 failed=0 skipped=1, each run |
| `tests/test_git_env_class.sh` (full) | passed=55 failed=0 skipped=0 |
| `tests/test_full_suite_manifest_gate_git_env.sh` | passed=14 failed=0 |
| `scripts/gates/cm_full_suite_manifest_complete_mutation_test.sh` | passed=64 failed=0 |
| `tests/layout/test_round8_git_env.sh` | PASS=133 FAIL=0 |
| `scripts/run_full_suite.sh --verify-manifest` | MANIFEST-OK (run after this pack was committed; see the vehicle report) |

`aee1ef04_run/` holds the same checks run on the fix commit before the needle commit.

## Regression sample (`regress/`, tool `tools/regress.sh.txt`, list `tools/regress_list.txt.txt`)

29 suites (the reviewer's 14; the 15 newly scrubbed files, of which custody r13 was already in the
reviewer's list; `test_round8_git_env.sh`), run on `e0373341`
(`regress/base/`) and on `aee1ef04` (`regress/head/`), no ambient git variables. 28 exits are identical
(the pre-existing failures, such as `cm_gitlink_on_remote_mutation_test.sh` case 13 and custody r13
"M-2/M-3 docstring", fail the same way on both). One differed:
`test_meta_test_verification_r1_regression.sh`, 0 on base and 1 on head, G-TERM `tmpdir-left` at a 2 %
delay. The TERM'd target is byte-identical on both trees; `gterm_rerun/` reran the suite three times per
tree: base 2 of 3 PASS (base.3 failed the same way, delay 0.035), head 2 of 3 PASS. It is a pre-existing
race in `meta_test_verification.sh` (scratch root made before its traps), filed as FU-5, not a regression.

## F5: follow-ups (`FOLLOW_UPS.md`)

FU-1 run the census at the pull seam (needs its own CM gate; the name is proposed, not minted), FU-2
`group.go` with a reviewed binary rebuild, FU-3 the latent staged-gitlink readers (`GIT_INDEX_FILE` at a
pre-commit seam), FU-4 widen the census to `tests/` (a probe found 85 members, 82 unscrubbed:
`census/tests_dir_probe.tsv`), FU-5 the TERM race above.

## Honest boundary

Host checks only; no independent review of round 2 has run. The census covers `scripts/` only (FU-4). It
proves a scrub is present, effective and placed before the first git write; it does not prove every git
call of a member is reached under every input.

`SHA256SUMS` lists every file of this pack.
