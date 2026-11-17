# Sync-all-upstreams, review round 13 (structural fixer)

| Field | Value |
|---|---|
| Round | 13 (after the round-12 independent review, verdict NO-GO) |
| Tracker item | CON-519 (the branch keeps the placeholders CON-PENDINGsync1/2/3; the lander mints the ids) |
| Base | `e8a2df220e4c562bd0f922550c622ff17bd2894f` (round 12, branch `sync-r12`) |
| Review read | `review_sync_r12.md`, sha256 `a741e281…d65` (verified) |
| Evidence class | gate-logic / unit class plus local live runs of the real engine against local bare repositories (real git 2.53.0, no network, no hosted remote). PROVISIONAL (§11.4.290): no run against GitHub or GitLab, no independent review of this round yet. |
| git | 2.53.0 |

## What the round-12 review found, and what changed

The review asked for class-level fixes (§11.4.250, §11.4.276(C)). Each row names the class, the fix, the RED
run on the round-12 engine and the GREEN run on this one. All RED and GREEN files are in `red_green/`; the
reviewer's own probes were copied unchanged except `lib.py`, which now points at the two engines.

| Finding | Class | Fix | RED (r12) | GREEN (r13) |
|---|---|---|---|---|
| RV12-1 | a ref name git does not take literally: a SYMBOLIC ref at the exact name `refs/remotes/<r>/<b>` (its value is a local branch, a tag or another remote's ref) | both for-each-ref formats read `%(refname)%00%(symref)` first. `resolve_ref_exact()` gives no commit for a symbolic hit and records it, so the reasons are `symbolic-tracking-ref:<remote>` and `no-upstream-<branch>`. The new `contained_refs()` drops symbolic lines from the `--contains` answer, and a line of the wrong shape counts as no answer. | `p_symref_r12.txt`: `--apply --no-fetch` moved dev to the local commit (rc 0); `--check`/`--dry-run` said behind (rc 3). `p_pinsym_pushed_r12.txt`: a pin only on a local branch read `at-main`, CURRENT, rc 0. | `p_symref_r13.txt`: rc 4, nothing moved, in every mode. `p_pinsym_pushed_r13.txt`: `not-on-any-remote`, rc 4. |
| RV12-2 | a path git reads as a pattern: `add -- <path>` is a pathspec (globs, magic, `GIT_*_PATHSPECS`, `core.ignoreCase`) | `GIT_LITERAL_PATHSPECS=1` on every git call (`PATH_LITERAL_PIN`). The caller's four pathspec variables are scrubbed first, because git refuses LITERAL combined with GLOB or ICASE. After the add, `stage_pin_verified()` checks that exactly one index entry changed (the gitlink, now at the target); otherwise the action fails with `stage-pin-not-exact:<other-entries\|not-staged>`. | `p_pathspec_r12.txt`, `p_icase_wrap_r12.txt`, `p_magic_r12.txt`: B's local commit was staged in each shape (`lib[1]`/`lib1`, `lib*`/`libB`, `lib`/`LIB` with ICASE, `:!x`). | the same files for r13: only A is staged. |
| RV12-3 | a work-tree file named HEAD makes `rev-list --count HEAD` ambiguous | every rev-list shape ends with `--` (allow-list, `count_range`, `control_needle`) | `p_extra_r12.txt`: exit 6 BLIND (`unresolved:rev-list:rc:128`) | `p_extra_r13.txt`: exit 0 CURRENT |
| RV12-5 | open shapes | `ls-files` closed to `-s -z` and `-z --others --ignored --exclude-standard`. `status` closed to `STATUS_ARGS`, or bare `status` (it takes no path; the runner's unit tests use it). `config`: NOT closed in this round (see follow-ups). | unit `test_closed_shapes_refuse_each_position` fails on r12 | PASS |
| RV12-6 | the git-env census FAILed on the committed r12 head | added the canonical scrub line to `../sync_upstreams_2026_11_16_r12/class_inventory_refs.py`. Corrected the r12 README figures with a dated note and updated its SHA256SUMS. | census FAIL: 678 members, 1 unscrubbed | census PASS on the committed head, in a fresh clone (below) |
| RV12-7 | the surviving mutants RV12C, RV12D, RV12E | unit `test_closed_shapes_refuse_each_position` checks every position of every closed shape; the gate refuses the same shapes | — | the mutation table below |
| RV12-8 | `x in mains` survived the prefix mutant RV12F | unit `test_main_is_matched_exactly_never_by_prefix` (`main-x`, `main/y`, `feature/main`, `mainx`) | — | the mutation table below |
| RV12-4 | the inventory missed symrefs, pathspecs and indirect call shapes | `class_inventory_r13.py` adds class 3 (symbolic refs: formats and parsers fed recorded rows), class 4 (every pathspec subcommand, `--` placement, the literal pin, the post-add verification) and class 5 (call shapes: a vector that is not a list literal, a keyword vector, an alias of run or g_out, or a process call outside the Runner FAILs; named constants and built vectors such as `STATUS_ARGS` and `fetch_args` are resolved and checked) | `class_inventory_r13.py` on the r12 engine: FAIL (20) | PASS |

`checkout --detach <id>^{commit}` stays without `--`. It is measured to take no pathspec, even with a tracked
file of that exact name (`ground_truth/gt_checkout_detach.txt`). The raw git facts behind every fix are in
`ground_truth/gt_raw_git.txt`.

Three further gaps were found by this round's own mutation runs and fixed:

| Mutant | What survived | Fix | Evidence |
|---|---|---|---|
| AE12 | the pre-add index read failing was ignored (the stage-pin verified against nothing) | new robustness check `pre_index`: the race shim makes every `ls-files` after the child's checkout hang past the engine's 60 s local limit; the action must record `unresolved:stage-pin-pre-index` with no add run, the old gitlink kept, not APPLIED, non-zero exit; control without the shim stages the pin | `mutants/new_rows_first_run.txt` (SURVIVED), `mutants/new_rows_ae12_rerun.txt` (KILLED) |
| M01 | the `+` (forced refspec) rule: every non-fetch shape is closed now, so `rev-parse +x`, the old unit case, is refused by the closed shape first; the `+` rule is reachable only through the still-open `config --get/--get-regexp` | unit `test_forced_refspec_refused_where_a_shape_is_open` (`config --get +refs/heads/*:refs/heads/*`, `config --get-regexp +x`; golden-false `config --get x.y`) | SURVIVED (70.2 s, no suite killed it) in the first full run, which was stopped at that row and restarted after the fix; its log was overwritten by the restart, so the survival is stated, not attached. `mutants/m01_rerun.txt` (KILLED by unit) |
| S04 | RV6-1, the second write site's own pre-check (`write_refused_now` in `begin_write`). The RV12-2 fix put a final read (the parent's pre-add index) before the stage-pin marker, and a hard stop refuses that read first, so the old fixture `hardstop-before-stage-marker` no longer reached the marker site: a precondition the fix took away from the test (§11.4.199), not an engine defect | new driver fault `hardstop-after-pre-index` (the stop lands right after the pre-add read answered; the driver reports `fired`) and scenario `refused_stage.after_pre_index.*`: the stage-pin marker is never written, no parent marker, the pin not staged, the action `unresolved:` | SURVIVED in the full run (`mutants/full_part1.txt`), KILLED by `robustness:refused_stage` (`mutants/s04_rerun.txt`) |

## Results

### Mutation table (`tests/sync/test_mutations.py`, 393 rows: the round-12 table plus AE01-AE14, AD03 and AD13 re-anchored)

| Part | Rows | Killed | Equivalent | Survived | File |
|---|---|---|---|---|---|
| part 1 (rows up to AA08) | 325 | 321 | 3 (M37, Z12, AA07) | 1 (S04, fixed, see above) | `mutants/full_part1.txt` |
| part 2 (the remaining rows) | 68 | 65 | 3 (AA11, AC10, CX1) | 0 | `mutants/full_part2.txt` |
| S04 rerun after its fix | 1 | 1 | 0 | 0 | `mutants/s04_rerun.txt` |
| **Total after the fixes** | **393** | **387** | **6** | **0** | |

How the table was run, stated honestly: the full run was interrupted twice (once stopped at M01 to fix it, once by an
API rate-limit stop at row 325). Part 1 ran on the tree before the S04 test fix; part 2 and the S04 rerun ran on the
final tree. The test changes in between only added checks (`pre_index`, `refused_stage.after_pre_index`, the
config `+` unit test); no check was removed or weakened, so a row killed in part 1 stays killed. The six
equivalent rows are the same as in round 12 (each was re-checked by the harness's own equivalence probe).

### Suites, run twice on the committed engine (`suites/suites_run1.txt`, `suites/suites_run2.txt`)

| Suite | Run 1 | Run 2 |
|---|---|---|
| unit | 147/0 | 147/0 |
| integration | 149/0 | 149/0 |
| e2e | 24/0 | 24/0 |
| full automation | 34/0 | 34/0 |
| security | 83/0 | 83/0 |
| determinism | 15/0 | 15/0 |
| ui | 26/0 | 26/0 |
| hardening | 119/0 | 119/0 |
| chaos | 58/0 | 58/0 |
| perf | 13/0 | 13/0 |
| faults | 21/0 | 21/0 |
| robustness | 1383/0 | 1383/0 |
| gate `cm_sync_upstreams_ff_only.sh` | rc 0 | rc 0 |
| `class_inventory_r13.py` / names | PASS / PASS (58 sites, 0 unclassified) | same |
| git-env census | PASS, 678 members, 0 unscrubbed | same |
| `tests/test_git_env_class.sh` | 142 passed, 0 failed, 1 skipped | same |

The two runs give the same verdict for every one of the 1925 `ok` lines; the only differences are three elapsed-time
figures printed inside test names (for example "finished in 2s" against "3s"). An earlier run 1 was interrupted
after `test_faults` and restarted; its partial log is `suites/suites_run1_interrupted.txt`.

### Gates (`gates/`)

ratchet `unimplemented=394 baseline=394` (unchanged); INDEX-FRESH PASS; MANIFEST-OK; workable-items validate OK
(390 items) and diff in sync; the defaults are unchanged (setup `CONSTITUTION_SYNC_UPSTREAMS:-off`, hook
`CONSTITUTION_SYNC_CHECK:-offline`, no diff on `post_update_hook.sh` or `setup.sh`); gate meta-test PASS (110 cases).
The census and `tests/test_git_env_class.sh` were also run in a fresh clone of the committed head
(`gates/pristine_clone.txt`).

### Follow-ups (not fixed in this round)

- `config` shapes are still open (`--get`/`--get-regexp` take any key); the `+` rule guards them meanwhile.
- A remote ref that differs only in case from another on a case-insensitive file system is not modelled (residual).
- Bare `status` stays allowed because the runner's own unit tests use it; it takes no path.

### Evidence class

Gate-logic and unit class, plus local live runs of the real engine against local bare repositories (real git 2.53.0).
No hosted remote, no network. PROVISIONAL under §11.4.290 until the independent review of this round.
