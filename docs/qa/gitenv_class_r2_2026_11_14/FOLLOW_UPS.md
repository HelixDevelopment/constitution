# gitenv-class round 2: follow-up drafts (F5)

| Field | Value |
|---|---|
| Created | 2026-11-14 |
| Status | DRAFT tracker text; no tracker row was written by this vehicle (no tracker access in the scratch copy) |
| Roadmap item | CON-402 round 2 |

These are drafts for the workable-items tracker. Each one keeps the §11.4.148 shape: what, scope, reproduction, acceptance. None of them is claimed done.

## FU-1 (Task): run the git-env class census at the pull seam

- **What.** The census runs only from `tests/test_git_env_class.sh` (the full suite). A new script can join the class between two full-suite runs and nobody notices.
- **Why not done in this vehicle.** The project's pull seam (`scripts/post_update_hook.sh` STEP 5b, `validate_hub_structure`) only runs `scripts/gates/cm_*.sh` gates that take `--root`, have a paired mutation test, and are listed in the gate ledger (§11.4.227(A)). Adding the census there means adding a new `CM-*` gate name, its wrapper, its mutation test and its ledger row, and keeping them in step with the manifest and the docs chain. That is its own reviewable change, so it is not folded into this fix.
- **Proposed change.**
  1. Add `scripts/gates/cm_git_env_class_census.sh --root <dir>`, a thin wrapper around `python3 -I scripts/validation/git_env_class_census.py --root <dir>`. Map its exits to 0 PASS, 1 FAIL and 2 BLIND, and add 3 SKIP when no member is inspected.
  2. Add its paired mutation test. It should delete one scrub line, add `GIT_CEILING_DIRECTORIES` to one canonical line, and turn one `pop` into `get`; each mutation must make the gate exit 1.
  3. List it in the STEP 5b loop with `groot="$CONST_DIR"`.
  4. Add the ledger row and the full-suite manifest row.
- **Acceptance.** A pull that brings an unscrubbed writer makes STEP 5b report `CM-GIT-ENV-CLASS-CENSUS: FAIL`, and the paired mutation test shows each mutation killed. The name `CM-GIT-ENV-CLASS-CENSUS` is a proposal: it is not minted by this draft and appears in no gate site.

## FU-2 (Task): scrub `scripts/workable-items/cmd/workable-items/group.go` together with a reviewed binary rebuild

- **What.** `group.go` runs `exec.Command("git", ...)` with writing subcommands and inherits the caller's `GIT_DIR` / `GIT_INDEX_FILE`. It is exempt (`go-binary-owed`) in `config/git_env_class_exemptions.tsv`.
- **Why owed.** The shipped binary `scripts/workable-items/bin/workable-items` is committed. A source-only edit would leave the source and the binary disagreeing.
- **Proposed change.**
  1. Build the child environment of every git call in `group.go` from `os.Environ()` minus the 14 names of `CL_GIT_SCRUB_VARS`. Keep `GIT_CEILING_DIRECTORIES` and `GIT_DISCOVERY_ACROSS_FILESYSTEM`.
  2. Add a Go test that sets `GIT_DIR` to a sentinel and asserts the sentinel is unchanged.
  3. Rebuild the committed binary in the same commit, reproducibly (§11.4.246), and record its sha256.
  4. Remove the exemption row.
- **Acceptance.** The census lists `group.go` as HERMETIC with no exemption row. The Go test was RED before the change and is GREEN after it, and the binary sha256 is recorded in the commit message.

## FU-4 (Task): widen the census from `scripts/` to `tests/`

- **What.** The census lists files under `scripts/` only (`git ls-files -- scripts`). A probe ran the same census code with the path set to `tests` (`census/tests_dir_probe.tsv`): members=85, hermetic=3, unscrubbed=82. Those are test files that write fixture repositories with git and have no top-level scrub. A test that runs under an ambient `GIT_DIR` (for example from a pre-commit hook) could write into another repository.
- **Why not done in this vehicle.** The class this vehicle fixes was declared as `scripts/`. Taking on 82 more test files is a separate, reviewable change.
- **Proposed change.**
  1. Extend the listing to `scripts tests`.
  2. Insert the canonical line with the same tool (`tools/insert_scrub.py` in this evidence pack).
  3. Re-run the full suite.
- **Acceptance.** The census over `scripts tests` reports `unscrubbed=0`, and the full suite exits are unchanged.

## FU-5 (Bug, pre-existing): `meta_test_verification.sh` leaves its scratch root when TERM lands before its traps

- **What.** `scripts/validation/meta_test_verification.sh` creates its scratch root with `mktemp -d` on line 46. It installs its EXIT/HUP/INT/TERM traps only on lines 54 to 57. A TERM that arrives between those lines kills the shell with no trap, and the scratch root stays behind.
- **Reproduction.** The G-TERM sweep of `scripts/validation/test_meta_test_verification_r1_regression.sh` sends TERM at 2 % of the run time (about 31 to 36 ms). Under host load (load average about 32 to 40) it failed with `0.035(tmpdir-left)` on the BASE tree `e0373341` in 1 of 3 reruns, and with `0.031` / `0.036` on the head tree in 2 of 4 runs (`regress/` and `gterm_rerun/`). The target file is byte-identical on both trees, so this vehicle did not cause it.
- **Proposed change.** Install the traps before the `mktemp`, with `W` empty at first (`cleanup` already checks `-n "${W:-}"`). Add a test that sends TERM right after the `mktemp` and expects no scratch root left.
- **Acceptance.** RED then GREEN on that test; the G-TERM sweep passes 10 of 10 runs under load.

## FU-3 (note, latent): staged-gitlink readers and `GIT_INDEX_FILE`

- **What.** `scripts/gates/cm_gitlink_on_remote.sh`, `scripts/gates/cm_helix_deps_ref_matches_gitlink.sh` and `scripts/gates/cm_hub_engine_no_ownorg_nesting.sh` read the STAGED gitlink on purpose. Their top-level scrub clears `GIT_INDEX_FILE`.
- **Risk.** They run today at the pull seam (post-merge, where git exports no `GIT_INDEX_FILE` and the hook is already scrubbed), so nothing is wrong now. If one of them were ever wired to a pre-commit seam, the scrub would make it read the real index rather than the temporary commit index git passes in `GIT_INDEX_FILE`. A partial or `--only` commit would then be judged against the wrong index.
- **Proposed handling.** Before wiring any of the three to a pre-commit seam, give it an explicit `--index <file>` input that the seam passes, never the ambient variable. Add a test that does a partial commit and expects the verdict to match the staged content.
- **Acceptance.** Not applicable until such wiring is proposed; this is a recorded constraint, not a defect today.
