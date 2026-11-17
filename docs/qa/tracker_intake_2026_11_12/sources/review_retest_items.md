# Independent review: retest-failure-items vehicle (NEW-1..NEW-4)

| Field | Value |
|---|---|
| Artifact | rtfix_bundle.aUWK/retest_new1-4.bundle, sha256 4fc7f43c...b6da6fd (checked, matches) |
| HEAD | a3b8564efea9e51e5fc5ed69e78628b1d8baba08, one commit on 02c109350ca2 |
| Reviewer | Opus 5.5 subagent; effort not settable or readable on this dispatch path (§11.4.231(F.2)), so no effort is claimed |
| Fixer evidence | evidence.sha256: all 14 files check out |
| Verdict | **GO-with-follow-ups** (§11.4.276(G)): every open finding is `test-instrumentation`, `process-doc` or a `minor`/`nit` source finding. No `source-defect` in what the commit ships. |
| My logs | scratchpad/review_retest_items_logs/ (SHA256SUMS inside) |

## What I ran (sequential, nice 10, short TMPDIR, stdin /dev/null; load 25-30)
Clone setup: a `--shared` clone of idg3.Yabv/constitution, then a fetch of the bundle. The live checkout was not touched.

| Run | Result |
|---|---|
| shellcheck -S warning on the 11 changed .sh files | 0 warnings, the same as base for every file; `bash -n` passes on all of them, `dash -n` passes on the anchor test (#!/bin/sh) |
| `run_full_suite.sh --verify-manifest` | census total=902, `RESULT: MANIFEST-OK` |
| new regression test (its leg A runs the 7 edited units once, canon alone) | rc 0, 17/0 |
| test_repo_verify_red under an empty HOME (`env HOME=<empty dir>` on the child only) | rc 0, 101 ok / 0 NOT ok; the empty HOME was untouched; the clone's local git config was unchanged (sha256 before = after) |
| sigwin_check.sh harness / deps | rc 0, only `SKIP zsh_unavailable` (21 s and 24 s) |
| runner `--only` over the 8 units + the regression test + run_all on the CLEAN commit | `PARTIAL-TOPOLOGY`, SKIP=6. repo_verify PASS (96 s; it FAILed in the fixer's dirty-tree runner run before the identity fix), regression test PASS, fc_timer_selftest PASS, the six units `SKIP (topology_unsupported)`. run_all.sh is heavy-excluded, so it was not run |
| **consumer layout** (my own superproject with the vehicle clone as submodule `constitution`, one commit, no consumer data) | token_stability rc 1 (5 FAIL), tool_deferral rc 1 (2 FAIL), custody_sweep rc 1 (golden-good NOT ok), verdict_cache rc 1 (WS10 needle FAIL), fc_timer_golden_output rc 2 (FATAL), anchor_citations rc 77 "another consumer" (no ATM commits, by design), fc_timer_selftest rc 0 |

So in both directions of §11.4.201, today: a consumer that is missing the data still FAILs (no silent widening of SKIP), and canon alone SKIPs with rc 77 and `reason=topology_unsupported`. The runner maps rc 77 to SKIP, and SKIP gives PARTIAL-*, never PASS-FULL.

## Reviewer-authored mutants (none of these were written by the author)
| id | mutation | result |
|---|---|---|
| X1 | tool_deferral final `exit 77` -> `exit 0` (a SKIP reported as PASS) | **SURVIVES** the regression test (leg A accepts rc 0) |
| X3 | verdict_cache probe forced to 0 (consumer FAIL hidden) | **SURVIVES** (leg A is canon-alone only) |
| X4 | custody synthetic pair: no tamper | killed (NOT ok synthetic golden-good) |
| X4b | custody synthetic hash wrong | killed |
| X6 | anchor_citations: shallow-repository condition removed | **SURVIVES** (no shallow fixture) |
| X10 | fc_timer.sh fallback `UNKNOWN` -> `deadbeef` (library) | killed by selftest #44 |
| Xrv | repo_verify: the GIT_COMMITTER export removed, run under an empty HOME | RED: 3 NOT ok (DIRTY_TREE), so the export does the work |
| Xsw | sigwin_rig calibration picks the FIRST reaping wait4, not the last | killed (postwait and postcanary fired=0) |

## Findings
| # | layer / severity | finding | fix direction |
|---|---|---|---|
| F1 | test-instrumentation / important | Leg A of test_consumer_layout_probe_retest_regression.sh accepts rc 0 OR 77 for every unit. A unit that skips the consumer checks but exits 0 (a SKIP counted as PASS, §11.4.1/§11.4.3) is not caught. X1 shows this for tool_deferral. Only token_stability has rc 77 pinned (B3). | Pin the expected rc for each unit in leg A (77 for the six skipping units, 0 for fc_timer_selftest), and add an X1-style paired mutant. |
| F2 | test-instrumentation / important | The consumer-layout path (probe=1, data absent, so FAIL) is guarded only for the token_stability copy. The probe is pasted byte-identically into 6 files. A miswired or forced-0 probe in any other unit survives (X3; custody passes `$FC/tests`, golden_output inlines the probe in a compound condition). The consumer layout behaves correctly today; I checked it by hand, see above. | Add a consumer-layout leg for every unit (superproject fixture without data: rc not 0 and not 77, no SKIP), or put the probe in one shared library (F4) and test it there. |
| F3 | test-instrumentation / minor | The two §11.4.201 guards of the anchor "another consumer" SKIP (`--is-shallow-repository = false`, and a HEAD exists) are not tested. X6 survives. A shallow clone of the real consumer whose visible history has no ATM commit would SKIP instead of FAIL if the guard regressed. | Add a C3 leg: a shallow superproject with no visible ATM commit must keep rc 1. |
| F4 | source (maintainability) / minor | The probe is a 6x copy-paste. An existing helper library for this exact class is already there: scripts/fastcycle/tests/lib/consumer_required.sh (`fc_require_consumer`, `fc_require_items`, with its own bash+dash test suite). There are now two different SKIP policies: data-presence (lib) and layout (new). §11.4.74 / §11.4.251. | Move `fc_layout_is_consumer` into consumer_required.sh, source it from the 6 units, cover it in test_consumer_required_helper.sh, and record which policy each class of test uses. |
| F5 | process-doc / minor | anchor_citations: after the new early SKIP, the old `if [ -z "$REPO_ROOT" ]` fallback block cannot be reached (an empty override equals no override, which already exited 77). The comment "kept for an explicit override only" is wrong. | Correct the comment, or remove the dead block after the §11.4.124 history check. |
| F6 | test-instrumentation / minor | In canon, token_stability skips Sections 3/4 (GOLDEN / GOLDEN-BAD) as a whole, although fixture thresholds already exist in the test. Canon therefore loses that discrimination coverage. Same class as lander item C-3. | Run GOLDEN / GOLDEN-BAD against a fixture tolerance when the consumer layout is absent. |
| F7 | process-doc / nit | The commit message says test_triple_harness_red "PASS in the runner". The fixer's runner shows `PASS [exit-code-only]`, and that run was on a dirty tree. | Say "exit-code-only PASS (dirty-tree runner run)". |
| F8 | test-instrumentation / nit | The repo_verify identity fix is guarded only by the runner's empty HOME. No suite test runs it under an empty HOME. The runner reports `leaked=2` for repo_verify (seen before this change as well). | Optional: an empty-HOME leg in a regression test; file the leak with C-6. |

Checked and NOT a finding: the test-local git identity is env-only and scoped to the test process. No `git config --global` is written, and every commit goes to a mktemp fixture. The manifest diff is a regeneration by `--generate-manifest --write` (three pre-existing rows moved into C sort order plus the new row), and `--verify-manifest` passes. In sigwin_check, `rrc=$?` straight after the plain assignment from a command substitution correctly holds the rig's exit status. The `kill -0 "$sp_h" || break` bound turns an empty result into fired=0, which is still a FAIL. fc_timer_selftest's UNKNOWN branch is tight: it also asserts that the root is not a repository, so a real repository with an empty HEAD read still FAILs. The custody synthetic root is removed with `rm -rf "${SYNROOT:?}"`. The trailer CON-PENDING-RETEST is known, as the brief says.

## Verdict
GO-with-follow-ups. The shipped behaviour is correct in both §11.4.201 directions. I checked it at runtime, canon alone and in a real consumer layout. The runner handles rc 77 as SKIP. The repo_verify fix and the sigwin rig fix are each shown with RED and GREEN. F1 and F2 are cheap and close the "SKIP counted as PASS" and "consumer FAIL hidden" mutation holes. I recommend folding them in before landing; if not, file them as follow-up items together with F3 to F8.
Scratch cleaned: the review clone, the consumer fixture and the temp dirs were removed with a guarded rm; only the logs under review_retest_items_logs/ are kept.
