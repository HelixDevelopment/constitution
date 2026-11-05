# Review: manifest-triage vehicle, round 1 of 5 (§11.4.209 / §11.4.142 / §11.4.276(G))

| Field | Value |
|---|---|
| Range | `main..vehicle/manifest-triage`, main `ecfe4325`, head `0313ffd3dbeea09b917218045880ee882c6db1a9` (14 commits) |
| Bundle | `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/manifest_triage.bundle` |
| Reviewer clone | `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rvmt1.TmLMNC/constitution` (sandbox HOME and TMPDIR under `rvmt1.TmLMNC`) |
| Substrate | Opus (claude-opus-5-5); reasoning effort is not reported to the agent on this dispatch path, so no effort is claimed (§11.4.231(F.2)) |
| Not touched | the real checkout and the author's clone `~/.cache/claude-tmp/mt.b8Df3W` (r8 left running, not read) |
| Landed | nothing |

## Verdict

**NO-GO.** Five `source-defect` findings of severity `important` block (F1, F2, F6, F7, F8). They are not minor-class under §11.4.276(G.2), so `GO-with-follow-ups` is not available. Round 2 is needed. It can be small: six fixes, listed at the end.

## What I confirmed (positive evidence, this session)

- **MANIFEST-OK.** I ran `bash scripts/run_full_suite.sh --verify-manifest` in the reviewer clone. It gave rc 0, `MANIFEST-OK`, census total 844: go/entry 5, js/entry 1, js/fixture 4, py/entry 9, py/excluded 21, py/fixture 14, py/member 27, runall/entry 9, sh/entry 326, sh/excluded 23, sh/fixture 112, sh/member 293. Output is in `rvmt1.TmLMNC/verify.out`.
- **Guide census.** `docs/guides/full_suite_runner_guide.md` says total=844, so it is in sync. The merge commit 0313ffd says "843"; see F10.
- **Runner not edited.** `scripts/full_suite/run_full_suite.py` and the wrapper have no diff in the range, as claimed.
- **Node helpers are not dropped.** The four js helpers moved to `fixture` are run by entries that are in the default plan:
  - `test_resolve1_drive.js`: `test_resolve1.sh:57` and `test_resolve2.sh:51`
  - `test_resolve1_probe.js`: `test_resolve1.sh:68`
  - `test_resolve2_probe.js`: `test_resolve2.sh:56`
  - `test_resolve1_equiv_real.js`: `test_resolve2.sh:78`

  `--list --allow-topology-gaps` gives 593 units, 328 run and 265 skipped as heavy. Both entries are in the run set (`rvmt1.TmLMNC/list.out`).
- **The four defect fixes show RED before and GREEN after** (same test, main code against vehicle code):
  - `tests/install/test_detection.sh`: main gives `FAIL native aliases (expected [] got [ ])`, 40 pass and 1 fail. Vehicle: 41 pass, 0 fail. The accounts-present branch was not exercised live, because my probe produced only `-` aliases. It is UNCONFIRMED; the change is symmetric.
  - `test_batch_bisect_r3_regression.sh`: main gives `NOT ok C3`, 7 pass and 1 fail. Vehicle: 8 of 8 at TMPDIR depth 10.
  - `test_link_check.py`: under a long TMPDIR, main gives rc 1 and the vehicle gives rc 0. I also ran an oracle mutant: the new assertion rejects `:10`, `:11` and `:600`.
  - `tests/install/lib.sh` main creation: in the `clone -b` layout, main's lib gives rc 1 with `src refspec main does not match`. The vehicle lib gives rc 0. A second defect stays in the other layout; see F8.
- **Baseline of the 24 converted fastcycle tests, run alone on canon before the change:** every one ended rc 1 or 2. None passed, so the conversion turned no PASS into a SKIP. They did execute about 400 passing assertions (see F3).

## Findings

`finding_layer` follows §11.4.235(D) and `severity` follows §11.4.276(G.2). "Blocks" means the finding is not minor-class.

| Id | Slice | finding_layer | Severity | Blocks | Finding | Evidence | Fix |
|---|---|---|---|---|---|---|---|
| F1 | S2 | source-defect | important | yes | `scripts/fastcycle/tests/lib/consumer_required.sh` finds the root with `${BASH_SOURCE[1]}`. dash has no `BASH_SOURCE`, so the six `#!/bin/sh` tests get the root `/`. They SKIP even when the consumer data IS present, which is a false SKIP (§11.4.289(E), §11.4.201(1)). The full-suite runner runs these under `sh`: `shebang_runner` returns `sh` for `#!/bin/sh` (run_full_suite.py:1676-1680), and default members of a runall-members `run_all.sh` run alone through it (2273-2274). `run_all.sh` uses `sh` as well. The helper has no test of its own (§11.4.224). | Reviewer mutant: I placed the consumer files under the test root. `consumer_audit` and `render_keys` under `sh` gave rc 77 "consumer-project files absent under /:". Under `bash`, the same tests gave rc 1 with real results: 71 ok and 5 NOT ok, and 6 ok and 4 NOT ok. All six sh tests print "Bad substitution". The six are churn_rank, consumer_audit, consumer_enumerate, io_trace, render_keys and render_keys_wiring. | Find the root from `$0`, which works in POSIX sh, or pass the root in. Add a test of the helper that runs it under both bash and dash, with the data present and with it absent. |
| F2 | S2, S7 | source-defect | important | yes | The guard checks the default consumer path, not the path the run will actually read. Two cases: (a) documented env overrides that point a test at its input are ignored: `FC_TIMER_RED_PREBUILD`, `FC_COMMIT_STAGE_COMMIT_ALL`, `PREBUILD_SRC` and `METATEST_SRC`. (b) `monday_dryrun` SKIPs when the mock is absent, but its default `RED_MODE=1` does not use the mock. A SKIP must fire only when the dependency the run needs is absent. | `FC_TIMER_RED_PREBUILD=<stub>` still gives rc 77. `monday_dryrun` with a broken mock present gives PASS=10 FAIL=0 SKIP=1, so the default mode never needed the mock. | Resolve the effective input path first (after the env override), then check it. In `monday_dryrun`, check the mock only when `RED_MODE=0`. |
| F3 | S2 | test-instrumentation | important | no (minor-class by layer) | The whole-test SKIP hides about 400 assertions that run on canon alone, and it hides their failures too. Examples of ok counts before the change: consumer_audit 66, catchset 67, plan_struct_causes 56, plan_struct_full 36, capture_triplet 25, escape_classify 23, limit_class 18, host_limits 17, alias_spread 15. | Pre-change runs in `rvmt1.TmLMNC` (R2 baseline): every test ran rc 1 or 2 with these counts. | Skip per assertion or per section: skip only the consumer-dependent sections, and keep the canon-runnable ones running and visible. Follow-up item. |
| F4 | S1 | test-instrumentation | important | no (minor-class by layer) | Five rows use `fixture` plus an `override:` note outside a `fixtures/` directory: the four node helpers and `consumer_required.sh`. main has no such row. Every sourced helper on main is `excluded` with `reason: helper: sourced by <path>`. Two checks are skipped this way. The excluded set is pinned by `config/full_suite_excluded.lock`, which the operator accepts, and the `helper: sourced by` reason is checked against the shell model. The fixture route avoids both: an agent classifies a file without operator acceptance (§11.4.240) and without the shell-model check. For the shell helper this matters, because a working check exists for it. For the node helpers it may be that no better class exists. That is UNCONFIRMED; it is the operator's call. | `git show ecfe4325:config/full_suite_manifest.tsv` has 0 fixture+override rows. The vehicle has 5. | Make `consumer_required.sh` an `excluded` row with `reason: helper: sourced by …`. The four node helpers get either the same treatment, if the runner can model `node <path>` invocation, or a recorded operator decision. Lock acceptance stays the operator's act. |
| F5 | S1 | test-instrumentation | important | no (minor-class by layer) | `test_resolve1_count_hook.js` is the fifth helper of the same class, and the batch left it as `entry default node`. Run alone, the runner judges it `('PASS','','exit-code-only')`, which is a vacuous PASS. The batch named the class "node helper of the resolve tests" and closed four of its five members (§11.4.276(C)). The row predates the batch (commit f81f41d5). | Plan line 39 of `list.out` runs it standalone. The judge returns exit-code-only PASS. | Classify it with its four siblings. |
| F6 | S1 | source-defect | important | yes | Commit bb0c856e (in the range) adds `scripts/fastcycle/tests/lib/foreign_uid_cause.sh` as a `member` of `test_fc_safepath_v4r12.sh`. Its covering suite discards the member's status, so the runner also runs the member alone. It is not a test: it is a probe that always exits 0 and prints the measured cause, run with `bash` by five tests: `test_fc_safepath_v4r12.sh:51`, `v4r13`, `v4r14`, `v4r15` (line 68) and `test_fc_supervisor_unit.sh:74`. On this host it prints "Operation not permitted", which the judge reads as a fail word, so it returns `('ERROR','unparsed_fail_signal')`. This is the r8 FAIL the author reported. MANIFEST-OK is true, but the row makes the run report an ERROR that is not a test result. | `list.out` line 58: `RUN scripts/fastcycle/tests/lib/foreign_uid_cause.sh`. The runner's judge on its output gives ERROR `unparsed_fail_signal`. | Change it to `excluded` with `reason: tool: probe run by test_fc_safepath_v4r12..v4r15 and test_fc_supervisor_unit`. Lock acceptance is the operator's. |
| F7 | S8 | source-defect | important | yes | `covenant_propagation_superspec_exclusion_test.sh` now runs its control needle only when `submodules/claude_toolkit/CLAUDE.md` exists. When it does not, the test prints `skip - control needle ...` and still exits 0. Assertion (a) then reports a zero with no needle to prove the instrument can see (§11.4.201(7)(b), §11.4.273). Before the change it was an honest FAIL; now it is a vacuous PASS. | Run with no submodule checkout: 2 of 2 pass, and the runner judges it PASS `{'p':2}`. | When the needle cannot run, exit 77 with `reason=topology_unsupported`. Or use a needle that exists in canon itself, so (a) is always proven. |
| F8 | S5 | source-defect | important | yes | `make_upstream` points the bare upstream's HEAD at `main` (b5b36788), and creates `main` only when it is missing (0b31e433). In the normal layout a local `main` exists. The install tests then run against main's tree plus a fixture commit, not against the commit under review. Only `install_constitution.sh` and `update_constitution.sh` are overlaid from the worktree. So the evidence for the batch's install changes, including `tests/install/lib.sh` itself, is produced from a different artifact (§11.4.108, §11.4.200). | With local main at ecfe4325: the upstream main is ecfe4325 plus fixture commit 7fe56753, not 0313ffd3. The upstream copy of `tests/install/lib.sh` differs from the worktree copy. | Always point `refs/heads/main` in the bare upstream at the bare HEAD, the commit under test (`update-ref` unconditionally). Add a test that asserts the upstream main equals the worktree HEAD in both layouts. |
| F9 | S2, S7 | test-instrumentation | minor | no | The SKIP line says `SKIP topology_unsupported: …`. The judge parses `reason[= ]X`, so it records `suite_reported_skip`, not `topology_unsupported` (§11.4.69). | The runner record for a converted test shows reason `suite_reported_skip`. | Print `reason=topology_unsupported` on the last line. |
| F10 | S1, S2, S9 | process-doc | nit | no | Commit 1f65b061 and the author report say 26 tests; 24 tests source the helper. Merge 0313ffd says census 843; it is 844. The two appended manifest rows (`consumer_required.sh`, `test_precheck_shellcheck_red.sh`) are out of sort order. | `grep -l consumer_required.sh` finds 24 tests. verify-manifest gives total 844. | Correct the numbers in the next commit message and the report; sort the rows. |
| F11 | S3 | test-instrumentation | minor | no | The bisect escape probe hard-codes a chain of 40 `../`, and its victim file is a shared name under `/tmp`. A deeper TMPDIR would break the probe, and concurrent runs share the victim file. | `test_batch_bisect_r3_regression.sh`: 40-level chain ending in `/tmp/m1_escape_probe*.txt`. | Compute the depth from `$TMPDIR`, and put the victim in a per-run `mktemp` name outside the sandbox root. Follow-up item. |
| F13 | S2 | test-instrumentation | minor | no | The consumer-layout class was not closed (§11.4.276(C)). Nine more tests fail on canon alone for the same reason and were not converted: three need `specs/`, four read the tracker DB at the consumer root, and two have consumer inputs missing. See inventory class A. | My individual runs (`unconf_results.tsv`). For `test_reopen_rate_red.sh` the source reads `DB="$ROOT/docs/workable_items.db"` with `ROOT` 4 levels up. | Fold these into the F1/F2/F3 rework (per-section skips that check the path actually read), not into another whole-test SKIP. Follow-up item. |
| F12 | S7 | test-instrumentation | minor | no | When their dependency is present, `sessions_pid_status` gives rc 94 and `supervisor_wiring` fails `RED(A) headhit=3`. These are RED tests pinned to history, and on canon the SKIP hides them. This is the same class as `orchestrator_reconcile`. The other two cases are correct: `balance_autoselect` with a broken mock fails 9, and with the project root present but the mock absent, pid_status and balance give FATAL 91. | Runs with the dependency present but broken (reviewer mutant). | Inventory; track the two RED tests as items. No change to the SKIP is needed for them. |

## Per-slice verdicts

| Slice | Content | Findings | Verdict |
|---|---|---|---|
| S1 | manifest rows (bb0c856e, c1ac3a10, bd7e0257, 0313ffd) | F4, F5, F6, F10 | NO-GO (F6) |
| S2 | fastcycle consumer-data SKIP (1f65b061, helper) | F1, F2, F3, F9, F10, F13 | NO-GO (F1, F2) |
| S3 | batch_bisect_r3 escape depth (7cab8328) | F11 | GO-with-follow-ups |
| S4 | install/test_detection oracle (220cd2a1) | none | GO |
| S5 | install lib.sh main creation (b5b36788, 0b31e433) | F8 | NO-GO (F8) |
| S6 | anchors test_link_check (1a390385) | none | GO |
| S7 | multitrack FATAL to SKIP (32bc0d94) | F2 (monday_dryrun), F9, F12 | NO-GO (F2) |
| S8 | superspec-exclusion needle (ce1fb76b) | F7 | NO-GO (F7) |
| S9 | main merges and the shellcheck member row (beab658c, cae930ac, 0313ffd) | F10 | GO-with-follow-ups |

The `test_precheck_shellcheck_red.sh` member row of `run_all.sh` is correct: it is a real test, and it is run by its suite.

## Minimal round 2

1. F1: find the helper's root in a POSIX way, from `$0` or passed in. Add a helper test run under both bash and dash, with the data present and absent.
2. F2: check the path the run actually reads, after env overrides resolve. In `monday_dryrun`, check the mock only when `RED_MODE=0`.
3. F7: superspec test exits 77 with `reason=topology_unsupported` when the needle cannot run, or uses a needle from canon.
4. F8: `update-ref refs/heads/main` to the bare HEAD unconditionally. Add a test for both layouts.
5. F6, plus F5 and F4 because they are the same edit: `foreign_uid_cause.sh` becomes an excluded `tool:` row (it is a probe run by five tests). `consumer_required.sh` becomes an excluded `helper: sourced by` row. `count_hook.js` joins its four siblings. Excluded-lock acceptance is the operator's act, so hand the lock diff over; do not self-accept it.
6. F9: print `reason=topology_unsupported`.

Follow-up items to register (§11.4.276(G.2)): F3 (per-section skips), F13 (nine more consumer-layout tests), F11, F12 (two pinned RED tests), F10 (wording, row order).

## Inventory: what is still unexplained (classified)

Under §11.4.292 these are leads to reproduce, not findings. Results from my own runs are labelled as mine; the rest come from the author and are UNCONFIRMED.

I ran each of the author's 33 UNCONFIRMED fastcycle tests alone, in the reviewer clone, with its own shebang interpreter, a 240 s timeout and `nice -n 10`. Host load was about 40. Results: 11 rc 0, 19 rc 1, 2 rc 2, 1 rc 124 (timeout). One row per test, with rc, time and the first failing line, is in `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rvmt1.TmLMNC/unconf_results.tsv`; full logs are in `rvmt1.TmLMNC/tmp/unc_<test>.log`. The 33 fall into the classes below (11 + 9 + 11 + 1 + 1). Each class is my reading of the first failing line, and only the cause marked "verified" was checked in the test source.

**A. Consumer-layout dependence, not converted (9 tests).** These are the same class as the 24 converted tests, but they were left out of the conversion.
- The control needle needs `specs/004-fast-dev-cycles/contracts/`, and canon has no `specs/`: `test_backstop_red.sh`, `test_flake_ledger_red.sh`, `test_mutation_reuse_red.sh`.
- "control needle #2 SKIPPED: sqlite3 or the tracker DB is unavailable": `test_evidence_ref_red.sh`, `test_governance_subset_red.sh`, `test_reopen_rate_red.sh`, `test_resume_revalidate_red.sh`. sqlite3 and `docs/workable_items.db` are both present in canon. Verified for `test_reopen_rate_red.sh`: `repo_root` goes 4 levels up (to the consumer root), and it reads `DB="$ROOT/docs/workable_items.db"`, which does not exist there. The other three print the same message; their cause is UNCONFIRMED.
- rc 2, inputs not found: `test_fc_commit_stage_timer_mutations.sh` (`FATAL: commit_all.sh / test not found`) and `test_fc_timer_prebuild_mutations.sh` (`FATAL: inputs missing`).
- Wider pattern: 62 of the 160 fastcycle tests hard-code `$ROOT/constitution/...`, so they work only when the canon directory is named `constitution`.

**B. Pass alone, fail in the batch (11 tests).** Each gives rc 0 when run alone:
- `test_backstop_compare_exit_codes_r2_regression.sh`, `test_backstop_compare_r3_regression.sh`
- `test_io_trace_build_map_device_safety_r2_regression.sh`, `test_io_trace_build_map_r3_regression.sh`, `test_io_trace_build_map_r5_regression.sh`, `test_io_trace_build_map_setsid_r5_regression.sh`, `test_io_trace_fork_cwd_and_faccessat_r2_regression.sh`
- `test_precheck_pack_build_red.sh` (105 s), `test_precheck_pack_multi_slice_sibling_search_r5_regression.sh`, `test_precheck_sibling_blast_radius_honest_verdict_red.sh`, `test_precheck_sibling_search_unmeasured_literal_r6_regression.sh`

Their batch failure is from load, ordering, shared state or the batch timeout; which one is UNCONFIRMED. A reproduction in the batch is needed before any fix (§11.4.199).

**C. Behaviour mismatches that need a root cause (11 tests).** Each needs a §11.4.292 reproduction first.
- The custody-sweep family. `r11`, `r13` and `r15` REFUSE a plain stash that should be ALLOWED: the sha256 of the backup patch does not match the freshly re-derived live content. A suspected cause, UNCONFIRMED: the diff output depends on git config or the git version in a sandbox HOME. `r6` hits a Python traceback in guard-viability. `r9` gets rc 2 from `custody_sweep.py --repo-root` on the long sandbox path.
- `test_escape_classify_malformed_red.sh`: `non_mapping_entry` exits 2, where a named refusal (exit 1) is expected.
- `test_fc_entry_r10_regression.sh`: B1 (inventory with `--out`) gets rc 2.
- `test_gate_shard_r3_regression.sh`: a Python traceback.
- `test_io_trace_build_map_r6_regression.sh`: "the OLD mechanism did not reproduce the umount-succeeds bypass". The mutation precondition was not reached on this host. Per §11.4.199 this proves nothing either way.
- `test_precheck_slicer_red.sh`: "B1 self-check FAILED: 'sh -n' against broken_syntax_gate.sh did ...". The parse check under dash did not reject the fixture as the test expects.
- `test_host_guard_red.sh`: `got rc=0 N=1 reason=unreadable_ulimit`, where `thread_headroom` was expected. It runs under `sh`. A suspected cause, UNCONFIRMED: dash's `ulimit` builtin has no `-u`.

**D. Host capability (1 test):** `test_host_attribute_red.sh` gets `btrfs_binary_unavailable`, because the exclusive-bytes instrument needs a btrfs tool that this host lacks. It should be an honest SKIP if the tool is truly absent; that is not checked.

**D2. Timeout (1 test):** `test_precheck_shellcheck_red.sh` gets rc 124 after 240 s, with `NOT ok: M11 mutation-flip ... Traceback` before the timeout. This is the test whose `member` row the vehicle added. The row is correct; the test itself fails and is slow under load, and that predates the vehicle.

**E. Environment classes reported by the author** (UNCONFIRMED by me): nine fastcycle tests TIMEOUT under host load; persistent_launch, lumen and real_agents; codegraph under load and under node v26; `test_fastcycle_real_db` TIMEOUT.

**F. The author's r7 unexplained list** (UNCONFIRMED): test_render, skill_activation, scanner_gate, gate_env_census_closure, gate_env_overrides_guarded, oracle_ratchet_and_consumer_skips, install rounds.

**G. Before this vehicle:** the excluded set was accepted by an id that is not on the roster (exit 11). This is the operator's to resolve.

**H. Not done:** r8 is unfinished and I did not read it. No workable items have been registered for anything above. The inventory needs items (§11.4.202) before it counts as tracked.
