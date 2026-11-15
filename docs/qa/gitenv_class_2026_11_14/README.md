# Ambient git variables write into a foreign repository: the whole class (2026-11-14)

| Field | Value |
|---|---|
| Item | CON-402 (minted at the landing on main) |
| Base | main `bd0036bd`, stacked on the manifest round-2 head `42fd1288` |
| Status | PROVISIONAL (host checks only; independent review pending) |
| Producer | Claude Opus 5.5 (fixer subagent); effort not settable on this dispatch path, not claimed |
| Class | §11.4.276(C): enumerated with a control-needled census, never fixed one instance at a time |

Scratch paths in these files are shown as `<scratch>` and temp dirs as `<tmp>`.

## The defect

`GIT_DIR` beats `git -C <dir>` and `cd <dir>`; `GIT_INDEX_FILE` names the index every index-writing
command uses. A script that runs a writing git command under a caller that set them (a pre-commit hook
gets `GIT_INDEX_FILE`, wrappers set `GIT_DIR`) writes into the caller's repository.

RED on `42fd1288` (`tools/sentinel_run.sh.txt`: a fresh sentinel repository, fingerprint of every path and
file hash including `.git`, mtimes excluded):

| Run | Exit | Sentinel | Meaning |
|---|---|---|---|
| `red/atl_git_dir` (cm_agent_type_label.sh, GIT_DIR) | 1 | CHANGED, HEAD moved | false FAIL and a foreign commit |
| `red/atl_git_index_file` | 1 | unchanged | false FAIL (R6 probe `'0:0:0' want 0:1:0`) |
| `red2/atl_none` | 0 | unchanged | control |
| `red2/arc_git_dir` (cm_anchor_record_complete.sh, GIT_DIR) | 0 | CHANGED (branch renamed to main, commit added) | false GREEN |
| `red2/arc_both` | 0 | CHANGED | false GREEN |
| `red2/arc_git_index_file` | 4 | unchanged | REFUSE: `go build` VCS stamping reads the ambient index |
| `red2/arc_none` | 0 | unchanged | control |

The first `red/arc_*` runs were REFUSE (exit 4) only because `submodules/continuum` was not checked out;
they are superseded by `red2/`.

## The class census

`scripts/validation/git_env_class_census.py` lists every tracked file under `scripts/` that can run a
writing git command and marks it HERMETIC (the canonical scrub line of `CL_GIT_SCRUB_VARS`, 15 names,
before the first git call), EXEMPT (a row in `config/git_env_class_exemptions.tsv` with a closed reason)
or UNSCRUBBED. It runs 17 control needles first and is BLIND (exit 2) when they fail or the canonical list
is absent.

- Before: `census/census_before.tsv`, 114 members, 105 unscrubbed (`census/unscrubbed.txt`).
- After: `census/census_after.tsv` 113 members (110 hermetic, 3 exempt, 0 unscrubbed); with the census
  tracked, `census/census_now.tsv` 114 members (111 hermetic, 3 exempt, 0 unscrubbed): the census itself
  is a member and is hermetic. `helix_code_home.sh` left the class (its calls now go through `hc__git`).
- **Correction (round 2, 2026-11-14).** The "0 unscrubbed" result above is superseded. The independent
  review (NO-GO, F1 to F5) found that this census did not see Python heredocs inside shell files,
  wrapper functions such as `g() { git "$@"; }`, or scrubs that clear nothing, and that the 15-name list
  cleared `GIT_CEILING_DIRECTORIES`, a discovery limit the caller must keep. The round-2 census found 15
  more unscrubbed members, and the list is now 14 names. See `../gitenv_class_r2_2026_11_14/README.md`.
- `census/apply_scrub.out`: the 101 files the scrub was inserted into, each `bash -n` / `py_compile` clean.
- `census/sourced_scan.txt`: files that are sourced or imported (needle included). `helix_code_home.sh`
  is a sourced library, so its scrub runs in a subshell wrapper; `scope_render.py` and
  `t_scope_fixture.py` are imported by their own tool and test, where the module-level scrub is wanted.
- Exemptions: the two pinned pre-fix fixtures under `scripts/fastcycle/tests/fixtures/custody_sweep/_pinned/`
  (a test runs them to reproduce the pre-fix RED; their only git call is `git stash list`) and
  `scripts/workable-items/cmd/workable-items/group.go` (the committed binary needs a rebuild: owed).

## Tests and mutants

`tests/test_git_env_class.sh` (registered in `config/full_suite_manifest.tsv`):

- `class2/fast_run{1,2,3}.txt`: `--fast`, passed=23 failed=0 skipped=1 each (N=3).
- `class2/full_run1.txt`: full run, passed=27 failed=0, both named gates under none / GIT_DIR /
  GIT_INDEX_FILE / both: exit 0 and sentinel unchanged; the sentinel needle shows a bare commit under the
  same `GIT_DIR` does change the sentinel.
- `class/fast_run*.txt` and `class/full_run1.txt` are an earlier run whose B2 case was a test bug (the
  library sets `set -e`, so the probe's failing `rev-parse` outside a repository ended the shell); B2 now
  probes from a plain repository and must answer `.git`. `class/b2_probe_mutant.txt` shows the probe
  answers the sentinel when the library's scrub line is removed.
- Census mutants (`class/census_mutant_*.txt`), each KILLED (exit 1): cz1 scrub order, cz2 scrub list,
  cz3 stale exemption rows, cz4 and cz5 the same two with the internal needles disabled (killed by the
  fixture cases C2d and C2c), cz6 any reason accepted (killed by C2i).
- Gate mutants (`class/gate_mutants.txt`, `class/gate_mutants/`): the scrub line removed from each named
  gate in a copy of the fixed tree, run under `GIT_DIR`: gx1 anchor gate exit 0 with sentinel CHANGED,
  gx2 agent-label gate exit 1 with sentinel CHANGED: both KILLED.

## Manifest gate follow-ups N1 to N6

Recorded in `docs/qa/manifest_sonarqube_2026_11_13/README.md` ("Round-2 review follow-ups"). Evidence here:

- `manifest/red_mutation_test.txt`: the unfixed gate, 60 passed 4 failed (A1 to A4).
- `manifest/green_mutation_test_run{1,2,3}.txt`: 64 passed 0 failed, MUTATION PAIR VALID (N=3).
- Mutants: `mutant_mN1_xdg` and `mutant_mN1_penv_only` KILLED by A3; `mutant_rv01` KILLED by L1;
  `mutant_rv03` KILLED by L2; `mutant_rv04` KILLED by L3. `mutant_mN1_nosystem` SURVIVES: observing it
  needs a system attributes file (root), so the effect of `GIT_ATTR_NOSYSTEM=1` is UNCONFIRMED.
- `manifest/gitenv_test_run1.txt`: the sentinel test, 13 ok, all 31 names asserted.
- `manifest/self_gate.txt`: the manifest gate on the committed tree `7f893bef`: PASS, 907 census files.

## Regression sample

`regress/{before,after}/summary.tsv` (exit, seconds, test): ten tests run one at a time on `42fd1288`
(before) and on the fixed tree (after) with no ambient git variables (`tools/regress_list.txt`).

| Test | Before | After |
|---|---|---|
| tests/layout/test_round8_git_env.sh | 0 (PASS=127 FAIL=0) | 124 at the 900 s limit; rerun `regress/after_round8_rerun/`: 0 (PASS=127 FAIL=0, 1029 s) |
| scripts/badges/test_static_badges.sh | 1 | 1 (same case, `real README --check exits 0`: pre-existing on the base) |
| scripts/codegraph/tests/test_mcp_readonly.sh | 0 | 0 |
| scripts/extensions/install_speckit_superpowers_bridge_test.sh | 0 | 0 |
| scripts/fastcycle/tests/test_custody_sweep_red.sh | 1 | 1 (red by design) |
| scripts/fastcycle/tests/test_custody_sweep_r7_regression.sh | 1 | 1 (same on the base) |
| scripts/fastcycle/tests/test_churn_rank_red.sh | 77 | 77 (consumer-layout SKIP) |
| scripts/fastcycle/tests/test_repo_verify_red.sh | 0 | 0 |
| scripts/fastcycle/tests/test_baseline_replay_red.sh | 77 | 77 (consumer-layout SKIP) |
| scripts/fastcycle/tokens/test_dispatch_stamp_r5_regression.sh | 0 | 0 |

No exit changed. The round-8 case lists match line for line apart from temp paths. This is a sample of ten,
not the full suite; the full suite was not run.

## Honest boundary

- The census reads `scripts/` only; `tests/` is not scanned.
- It does not see git calls behind a wrapper name (`hc__git`) or inside a toolchain (`go build` VCS
  stamping reads `GIT_INDEX_FILE`; the anchor gate's scrub covers it because the scrub runs first).
- `config` is counted as a writing command even for `config --get` (over-counts, never under-counts).
- HERMETIC means the scrub line is present before the first git line, not that every path ran.
- `group.go` is unscrubbed until its binary is rebuilt (owed).
- Host checks only; nothing here was run on another host or under a real hook.
