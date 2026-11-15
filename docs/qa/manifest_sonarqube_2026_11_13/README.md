# Full-suite manifest: missing SonarQube test rows (2026-11-13)

| Field | Value |
|---|---|
| Item | CON-PENDING-MANIFEST-SONARQUBE (recurrence of CON-086, same class; §11.4.214 link, CON-086 still open) |
| Item note (round 2, F7) | The `Roadmap-Item:` trailer stays the placeholder `CON-PENDING-MANIFEST-SONARQUBE`; no tracker id is minted in this vehicle. The relation to CON-086 is a link only: CON-086 is open, so it is neither reopened nor closed here, and `docs/Issues.md` is not edited by this vehicle. |
| Base | main `bd0036bd` |
| Status | PROVISIONAL (host fixtures and host checks only). Round-1 independent review: NO-GO. Round-2 fix set: see "Round 2" below; its independent review is pending. |
| Producer | Claude Opus 5.5 (fixer subagent); effort not settable on this dispatch path, not claimed |

Scratch paths in these files are shown as `<scratch>` and temp dirs as `<tmp>`.

The sections from "Reproduction" to "Honest boundaries" record round 1. Where round 2 changed
the gate's behaviour, the round-1 statement is marked and the current behaviour is in "Round 2".

## Reproduction (RED on the broken artifact)

`bash scripts/run_full_suite.sh --verify-manifest` on a fresh full clone of `bd0036bd`: exit 3,
`RESULT: MANIFEST-MISMATCH (3 problem(s); nothing was run)`, the three problems being
`census file without manifest row` for `scripts/sonarqube/tests/test_registry_login.sh`,
`test_registry_login_mutation_test.sh` and `test_registry_login_wiring.sh`
(`red_verify_manifest_1.txt`, sha256 `8ac0a803...64df`).

## Root cause

- The three files were added by `ff539dc8` (2026-11-12) without `--generate-manifest --write`; `afa62fc9`,
  `ef64f573`, `2717153b`, `eef11df6`, `bd0036bd` edited them and never touched `config/full_suite_manifest.tsv`
  (`git log --diff-filter=A` and `--name-status`, recorded in the hand-back).
- The runner itself is correct: it fails closed (exit 3) on a full run. What was missing is a seam that runs
  `--verify-manifest` before or after a change lands; nothing in this repository ran it automatically
  (no commit hook in this repository; the pull seam `post_update_hook.sh` did not run it). CON-086 recorded
  the same gap on 2026-11-05 ("the recurrence seam ... is not built").
- The guide census line was consistent with the manifest (901 rows) and therefore not reported; it went
  stale only when the rows were added.
- Other drift on the base, checked: `progressive/generate_split.py --check` reproducible (311 artifacts),
  gate ledger `unimplemented=394 baseline=394`, env-reads allowlist PASS (`base_*.txt`).

## Fix

1. Rows regenerated with the official `--generate-manifest --write`, census line with `--sync-guide`.
   Row set difference against `bd0036bd`: exactly 4 added rows (the 3 SonarQube tests and the new mutation test),
   0 removed (`manifest_row_setdiff_final.txt`). The text diff is larger because the generator also moved three
   existing rows into sort order (`test_custody_sweep_stash_patch_r22_regression.sh`,
   `test_host_report_thread_limit_r1_regression.sh`, `test_decision_mutant_census_wording_r1_regression.sh`),
   a move with identical row text. A second regeneration at commit A gave byte-identical files
   (`generate_at_commit_A.txt`).
2. Class-wide seam: `scripts/gates/cm_full_suite_manifest_complete.sh` (CM-FULL-SUITE-MANIFEST-COMPLETE) runs the
   repository's own runner `--verify-manifest` (one detector, no second census), after a control needle that
   requires the same runner to report a tracked fixture file without a row. It is run by `post_update_hook.sh`
   step 5b against the hub on every pull. Verdicts: 0 PASS, 1 FAIL, 2 BLIND, 3 SKIP.

## RED then GREEN

| Check | RED | GREEN |
|---|---|---|
| gate on `bd0036bd` / on fixed tree | exit 1, 3 files named (`red_gate_on_bd0036bd.txt`) | exit 0, 905 census files, 17 s (`green_gate_on_fixed_tree.txt`) |
| gate at commit A (gate added, rows not yet) | exit 1, 4 files named (`red_gate_at_commit_A.txt`) | commit B: see `final_checks_worktree.txt` |
| paired mutation test | gate missing: exit 2; always-PASS gate: 11 of 12 cases fail (`red_mutation_*.txt`) | 13/13, `MUTATION PAIR VALID` (`green_mutation_2.txt`) |
| gate self-mutants (8) | — | all killed; gm5 (census total 0 accepted) survived the first 12-case test and is killed by case B5 (`gate_mutants_summary.txt`, `gate_mutant_gm5_zero_total_ok_v2.txt`, `gate_mutants.diff.txt`) |
| `tests/test_post_update_hub_gates.sh` extended to 13 gates | old hook: the 3 new cases BAD (`red_hub_gates_test_old_hook.txt`) | 36/36 ok (`green_hub_gates_test.txt`) |
| `--verify-manifest` | exit 3 (3 problems) | exit 0 `MANIFEST-OK` twice, total=905 |

The mutant files were cut from the gate before a shellcheck-only comment line was added
(`# shellcheck disable=SC2329`); the diff file therefore shows that line too. Semantics unchanged.

## Other checks on the fixed content (`final_checks_worktree.txt`, `shellcheck_delta_final.txt`)

- `generate_split.py --check`: reproducible (311 artifacts). Gate ledger: `unimplemented=394 baseline=394`, PASS.
- `cm_gate_env_reads_allowlisted.sh`: PASS, gates 194 to 195, `uncovered=0`.
- shellcheck 0.11.0: the two modified files keep their base findings (6 and 1, text-identical); the two new files 0.

## Honest boundaries (§11.4.6)

- The gate reports at the pull seam; it does not block a commit. This repository has no commit hook, and adding one
  needs the operator (§11.4.234: hooks must not block the commit mechanism). Run `--verify-manifest` before committing.
- UNCONFIRMED: that the consumer's `cm_unreferenced_gate_bound_or_retired.sh` classifies the new gate
  BOUND-SEAM-LITERAL. The rule (basename on a non-comment line of the declared seam `constitution/scripts/post_update_hook.sh`)
  is met in the text, but the sweep cannot run in this repository alone: it refuses on unreadable consumer seam
  files (base and new alike, `base_unreferenced_sweep.txt`), and in a fake consumer layout it refuses earlier on
  the covenant dispatcher (`unreferenced_sweep_fakeconsumer_*.txt`, base and new identical).
- Round 1 only (no longer true): an untracked census file in the working tree was BLIND, not FAIL. In round 2
  the gate judges HEAD through a clean export, so an untracked, staged or unstaged change does not change the
  verdict; it only prints a NOTE (see "Round 2").
- Runtime about 17 s per pull on this host (one measurement).

## Round 2 (2026-11-13/14)

The round-1 independent review returned NO-GO (F8 and F1 blocking, F2 to F7 minor). Round 2 is a new fixer on a
fresh clone, branch `vehicle/manifest-sonarqube-r2` from the round-1 head `6d47ab66`, commits added only.
Evidence is in `round2/`. Producer: Claude Opus 5.5 (fixer subagent); effort not settable on this dispatch path,
not claimed.

Commits: `f62b8b9b` tests first (sentinel test, new mutation-test cases, one manifest row, census line), `10e8a52d`
the gate fix, `752e822b` a definition move for `cm_gate_env_reads_allowlisted.sh`, then this documentation commit.

### Findings and what was done

| Id | Class | Round-2 change | RED (before) | GREEN (after) |
|---|---|---|---|---|
| F8 | important, source-defect, data safety | Gate and mutation test clear the same 31 repository-locating git variables (12 from the `git help git` section "The Git Repository", `git_help_git_env_names.txt`; the config, pathspec and internal variables that `git help git` does not list are named with their source in `tests/test_full_suite_manifest_gate_git_env.sh`); the gate reads the inspected repository only through `rev-parse`, `cat-file` and one `git status`; header corrected | sentinel test on the round-1 head: 5 passed, 8 failed (`red_git_env_test_on_r1.txt`) | 13/13 (`green_git_env_final.txt`) |
| F9 | found in this round's own draft, never shipped | `git --no-optional-locks diff --quiet` rewrote the inspected index of a stat-dirty repository (git 2.53.0, `f9_index_write_probe.txt`); replaced by `git status` | case RO2 on the draft: index rewritten (`red_f9_index_rewrite_on_draft.txt`) | RO2 ok in the mutation test |
| F1 | important, source-defect | A runner refusal of the committed manifest (duplicated row, wrong column count, unreadable line or lock) is FAIL with the runner's `RESULT` line relayed; an unknown refusal or a mismatch with no readable reason stays BLIND | D1 to D5 fail on the round-1 gate (`red_mutation_test_on_r1_gate.txt`) | D1 to D5 ok |
| F3 | minor, source-defect | HEAD is judged through a clean export (alternates, `read-tree`, `checkout-index`) with HEAD's own runner; a NOTE says when the work tree differs, the verdict does not change (P07a now FAIL) | M7, RO3, W1 to W7 fail on the round-1 gate | ok |
| F4 | minor, source-defect | No runner output reaches git as a pathspec; the pathspec variables are cleared | W2 (`test_[o]ne.sh`) fails on the round-1 gate | ok |
| F5 | minor, source-defect | The control needle covers a missing row, a stale row, an unaccepted excluded set, a stale guide block and a duplicated row (§11.4.273(f)) | N3 to N7 fail on the round-1 gate | ok |
| F2 | minor, test-instrumentation | Cases for a needle answer with exit 0, an exit-3 stub without the needle line, an rc-0 stub with no OK line, a temp-dir leak check, a missing git; fixtures carry `scripts/lib/safe_rm.sh` | N1, X4 fail on the round-1 gate | ok; no `could not remove` warning in the runs |
| F6 | minor, process-doc | Header: a runner is run with `bash`, so its executable bit does not matter; the gate runs HEAD's own runner; the side-effects text states the round-1 error | — | — |
| F7 | minor, process-doc | Placeholder id kept as instructed; CON-086 link-only note added to the table at the top | — | — |

Paired mutation test against the round-1 gate: 23 passed, 30 failed. Besides the cases in the table, B1, R5 to R7, X1,
X2 and SKIP fail there (the round-1 gate did not separate those BLIND and SKIP causes), and M1 and M6 fail on the
changed message wording only. Against the final gate: see the totals below.

### Mutants

39 gate mutants written by the round-2 fixer (`make_mutants_r2.py`; `gate_mutants.diff.txt`), including the
reviewer's round-1 mutants that still apply to the new code (rm01 to rm18 except rm09 and rm11, whose code no
longer exists): 36 killed, 3 survived and judged equivalent (`gate_mutants_summary.txt`):

- `n12_rgit_no_literal_pathspecs`: no pathspec argument is left in any `rgit` call, and the pathspec variables are
  cleared, so `--literal-pathspecs` changes nothing.
- `rm03_needle_unlisted_untracked`: the runner's census lists tracked and untracked files (`ls-files -co`), so a
  needle file left untracked is still reported; the round-1 reviewer judged it the same way.
- `rm15_total_head`: the runner prints exactly one `census:` line in `--verify-manifest`
  (`run_full_suite.py`, the single `out(cline)` call), so `head` and `tail` read the same line; the round-1
  reviewer judged it the same way. The reviewer's rm18 (judged likely equivalent in round 1) is killed by case X1.

The mutants were cut from the gate before the `note_uncommitted` move (`752e822b`). Moving each mutant the same way
gives, byte for byte, the mutant generated from the final gate, for all 39 (`mutant_equivalence_after_move.txt`).
As a spot check, three mutants regenerated from the final gate (`n14_staged_flag_lost`, `n22_status_diff_refresh`,
`rm13_no_cleanup_trap`) were run against the final paired mutation test: all 3 killed, by W5, RO2 and the leak
check (`spot_mutants_final.txt`).

Hook mutants (the reviewer's hm1 to hm3, rebuilt): all 3 killed by `tests/test_post_update_hub_gates.sh`
(`hook_mutant_*.txt`); the unchanged hook test is 36/36 ok (`green_hub_gates_test.txt`).

### Checks on the final code

| Check | Result |
|---|---|
| `--verify-manifest`, twice | exit 0, `RESULT: MANIFEST-OK`, total=906 (`verify_manifest_1.txt`, `verify_manifest_2.txt`; once more with this documentation and `round2/` in the tree, `verify_manifest_docs_tree.txt`) |
| gate on a fresh clone of `bd0036bd`, twice | exit 1, the 3 SonarQube files named (`gate_red_bd0036bd_1.txt`, `_2.txt`) |
| gate on the fixed tree, twice | exit 0, 906 census files, 17 to 18 s (`gate_green_1.txt`, `_2.txt`; the NOTE in them is the then-uncommitted documentation edit) |
| paired mutation test | 53 passed, 0 failed, `MUTATION PAIR VALID` (`green_mutation_final.txt`) |
| sentinel test | 13 passed, 0 failed (`green_git_env_final.txt`) |
| `generate_split.py --check` | reproducible, 311 artifacts (`generate_split_check.txt`; again on the tree with this documentation, `generate_split_check_docs_tree.txt`) |
| gate ledger ratchet | `unimplemented=394 baseline=394`, PASS (`gate_ledger_ratchet.txt`; again on the tree with this documentation, `gate_ledger_ratchet_docs_tree.txt`) |
| `cm_gate_env_reads_allowlisted.sh` | FAIL on `10e8a52d` (`TMP` read before assignment, line 180; `env_allowlist_before_move.txt`), PASS on `752e822b`, 195 gates, `uncovered=0` (`env_allowlist_final.txt`) |
| shellcheck 0.11.0 | the three new or rewritten files 0 findings; `post_update_hook.sh` 6 and `test_post_update_hub_gates.sh` 1, the same as on `bd0036bd` (`shellcheck_delta.txt`) |

### The same class elsewhere (reported, not changed here)

The review named two pre-existing scripts that may write git state through an inherited environment. They were run
against a sentinel repository (`class_*.txt`); neither file is changed in this vehicle.

- `scripts/gates/cm_agent_type_label.sh`: CONFIRMED. With `GIT_DIR` naming the sentinel, the sentinel's branch moved
  from `079c435` to `c3039cb` (5 empty commits "i") and the gate ended FAIL. With `GIT_INDEX_FILE` naming the
  sentinel's index, the sentinel was unchanged and the gate also ended FAIL. Without either variable the same clone
  gives PASS, 44 checks (`class_cm_agent_type_label_control_no_variables.txt`, `class_cm_agent_type_label_control_no_variables_on_bd0036bd.txt`), so both FAILs come from the
  variable (a false FAIL) and the `GIT_DIR` run also wrote into another repository.
- `scripts/gates/cm_anchor_record_complete.sh`: the full gate REFUSES at its precondition on this clone (no
  `submodules/continuum` checkout, no network), so a full-gate probe is UNCONFIRMED. Its seed block (lines 309 to 312,
  run verbatim with `GIT_DIR` naming the sentinel) renamed the sentinel's branch to `main`, added a commit `seed` on
  top of it, wrote `user.email`/`user.name` into its config and added `f` to its index
  (`class_cm_anchor_record_complete_seed_block_git_dir.txt`).

These should be one tracked item for the class (§11.4.276(C)); filing it is left to the conductor.

### Honest boundaries (round 2)

- PROVISIONAL: host fixtures and host checks only; the independent review of round 2 is pending.
- The gate still reports at the pull seam and does not stop a commit. Run `--verify-manifest` before committing.
- The scrub list is the 31 names in the gate; a git variable added by a later git version is not covered until the
  list is extended (`L2` asserts all 31 names; it does not read `git help git`, so a variable added by a later git needs a manual review of the list).
- Runtime on this host at load 55 to 95: 17 to 23 s for a PASS run (4 runs), 11 to 13 s for a FAIL run (4 runs).

## Round-2 review follow-ups N1 to N6 (CON-402, 2026-11-14)

Evidence for this section is in `docs/qa/gitenv_class_2026_11_14/manifest/`.

- N1 (source-defect): the export, the needle and HEAD's runner now get an empty private XDG config home,
  `GIT_ATTR_NOSYSTEM=1`, and `core.attributesFile` / `core.excludesFile` pointed at `/dev/null`. New cases A1 to A4 in
  the mutation test: on the round-2 gate A1 and A4 were BLIND (eol=crlf checked the runner out with CR line ends),
  A2 a false FAIL (working-tree-encoding), A3 BLIND (an XDG ignore file blinded the runner's own census needle); on
  the fixed gate all four hold. A system attributes file was not probed (it needs root); `GIT_ATTR_NOSYSTEM=1` is set
  but its effect is UNCONFIRMED on this host.
- N2 (test-instrumentation): cases L1 (committed dangling-symlink manifest), L2 (linked worktree, a gitfile root) and
  L3 (an fsmonitor hook in the inspected repository, with a needle that shows the same hook runs under plain
  `git status`) kill rv01, rv03 and rv04.
- N3: `L2` of the sentinel test asserts all 31 names (with a control needle) and the test's own scrub is the same 31.
- N4: the two citations above are corrected.
- N5: the gate header now says trace output the caller asks for is the one side effect outside the temp dir.
- N6: case F1 shows an ambient `FULL_SUITE_TMPDIR` changes nothing and leaves nothing behind. rv08 (the gate's
  self-check of its classifier on the duplicated-row needle) stays equivalent: the D cases exercise the classifier
  on real refusals. rv10 (runner started without the gate's private `TMPDIR`) stays equivalent in effect: the
  runner then uses the `TMPDIR` the gate was started with and removes its own temp dirs there, so nothing is left
  (the no-leak case, which watches that directory, would see a leftover).
