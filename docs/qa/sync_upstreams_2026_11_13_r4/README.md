# Sync upstreams, review round 4: evidence

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13T20:26:13Z |
| Status | active |
| Status summary | Round-4 fixes for the round-3 review (NO-GO: F1–F9): RED on the round-3 engine, GREEN on the round-4 engine, every suite twice, the full mutant table (131 mutants) in the default mode (M67 and M70 survived it and were re-run on the final tree after hardening sections 14 and 15 were added), and the reviewer's and the fixer's mutants also with the gate only and without the gate. Gate-logic / unit-class evidence only (§11.4.289). Not reviewed yet. |
| Item | CON-PENDING-SYNC-UPSTREAMS |
| Issues | see [Open items](#open-items-and-unconfirmed) |
| Issues summary | `redact()` quadratic in line length and a blocked write classified `behind` (both older than round 4, not fixed); follow-blocked design question; installer SIGPIPE (other vehicle); `CM-KILLPG-PGID-GUARD` passes X04; `test_lock` harness proceeds without its pause |
| Fixed | F1, F2, F3, F4, F5, F6, F7, F8, F9, the `test_chaos.sh` nit; found while running the mutation table: M59 (no test held `moved`), M67 (no test changed the parent's index), M70 (no test left the file type as the only check on an `--out` file) |
| Fixed summary | see [Findings, fixes and RED/GREEN](#findings-fixes-and-redgreen) |
| Continuation | — |

## Table of contents

- [What was tested](#what-was-tested)
- [Files in this directory](#files-in-this-directory)
- [Findings, fixes and RED/GREEN](#findings-fixes-and-redgreen)
- [Suites, twice](#suites-twice)
- [Mutation table](#mutation-table)
- [Static checks, manifest, ratchet](#static-checks-manifest-ratchet)
- [The test_lock failure: root cause](#the-test_lock-failure-root-cause)
- [Notes for the lander](#notes-for-the-lander)
- [Open items and UNCONFIRMED](#open-items-and-unconfirmed)

## What was tested

- **Vehicle.** `vehicle/sync-upstreams-r4`, built on the round-3 head `bc1a03a5` (round-3 bundle sha256
  `f4ce6ac9adb75b8e314074392bf7201b818dd3660080db8fa27a01c05afb0a17`; vehicle base on `main` `02c10935`).
- **Round-3 engine ("r3").** `scripts/sync/sync_all_upstreams.py` at `bc1a03a5`, kept unmodified as the RED
  baseline. Every new test and probe was run against it first.
- **Environment.** Every run under `env -i HOME=<scratch>/home PATH=/usr/bin:/bin` with a private `TMPDIR`, in
  `systemd-run --user --scope -p TasksMax=3000`, at `nice -n 10`. Host: 16 CPUs, 30 GB RAM, load average 30 to
  40 from other work during every run. Real git against real bare repositories in scratch directories
  (`file://`, and one loopback port that refuses); no network, no forge. All of it is gate-logic / unit-class
  evidence (§11.4.289), not proof against a real forge.
- **Class inventory.** Written before the fixes: [class_inventory.md](class_inventory.md) (classes A to F, every
  member, the fix and the check that covers it). `<scratch>` in the evidence files stands for the session scratch
  directory and `~` for the home directory (paths only; nothing else was changed in the copies).

## Files in this directory

| File | Contents |
|---|---|
| [README.md](README.md) | this file |
| [SHA256SUMS](SHA256SUMS) | sha256 of every other file here (`sha256sum -c SHA256SUMS`) |
| [class_inventory.md](class_inventory.md) | the class inventory, written before the fixes (classes A to F) |
| [foreign_top.sh.txt](foreign_top.sh.txt) | the F1 foreign-top-level case (an empty `.git` directory), run against a given tree |
| [green_r4_advance_on_branch.txt](green_r4_advance_on_branch.txt) | F3 on r4: the branch is kept, attention |
| [green_r4_broken_gitfile.txt](green_r4_broken_gitfile.txt) | F1 on r4: the same is `blind`, exit 6 |
| [green_r4_control.txt](green_r4_control.txt) | control run on r4: the same sane tree |
| [green_r4_f4_f5_f8.txt](green_r4_f4_f5_f8.txt) | the same probe on r4 |
| [green_r4_foreign_toplevel.txt](green_r4_foreign_toplevel.txt) | F1 on r4: `blind`, `rev-parse:not-own-toplevel`, exit 6 |
| [green_r4_stale_head_after.txt](green_r4_stale_head_after.txt) | F2 on r4: `head_after` is the real head |
| [green_r4_unit_probes.txt](green_r4_unit_probes.txt) | the same probe on r4 |
| [green_r4_unknown_ext.txt](green_r4_unknown_ext.txt) | F1 on r4: the same submodule is `blind`, `pin-unreadable` |
| [green_record_check.txt](green_record_check.txt) | the same reduced run against the round-4 engine: the record check passes |
| [hardening_final_twice.txt](hardening_final_twice.txt) | the hardening suite twice on the final tree, compared; and once on the X06 mutant |
| [hardening_s14.txt](hardening_s14.txt) | hardening section 14 (M67) alone: GREEN on the round-4 engine, 4 of 8 checks fail on M67 |
| [hardening_s15.txt](hardening_s15.txt) | hardening section 15 (M70) alone: GREEN on the round-4 engine, 4 of 8 checks fail on M70 |
| [install_unit.txt](install_unit.txt) | `tests/install/test_unit.sh` on the r4 tree (the F4 `lib.sh` change) |
| [lock_repro.sh.txt](lock_repro.sh.txt) | the `test_lock` reclaim-race reproduction script |
| [lock_repro_delay_0.txt](lock_repro_delay_0.txt) | reproduction, run A delayed 0 s: PASS |
| [lock_repro_delay_25.txt](lock_repro_delay_25.txt) | reproduction, run A delayed 25 s: PASS |
| [lock_repro_delay_90.txt](lock_repro_delay_90.txt) | reproduction, run A delayed 90 s: FAIL with the round-3 signature |
| [m67_r3_suites.txt](m67_r3_suites.txt) | M67 on the round-3 tree: its round-3 suites all pass (survived in round 3 too), with the M66 control needle |
| [m70_r3_suites.txt](m70_r3_suites.txt) | M70 on the round-3 tree: its round-3 suites pass (survived in round 3 too) |
| [mutations_default.txt](mutations_default.txt) | mutation harness, default mode, all mutants, on the tree before hardening sections 14 and 15 |
| [mutations_default_composed.txt](mutations_default_composed.txt) | the default run with the M67 and M70 rows taken from the re-run (input of the tables) |
| [mutations_default_rerun.txt](mutations_default_rerun.txt) | the same harness, default mode, M67 and M70 only, on the final tree |
| [mutations_gate_only.txt](mutations_gate_only.txt) | mutation harness, gate only, reviewer (X) and own (N) mutants |
| [mutations_no_gate.txt](mutations_no_gate.txt) | mutation harness without the gate, X and N mutants (behavioural kills) |
| [mutations_tree_sha256.txt](mutations_tree_sha256.txt) | sha256 of the engine, tests and gate files when the default mutation run started |
| [mutations_tree_sha256_final.txt](mutations_tree_sha256_final.txt) | sha256 of the engine, tests and gate files of the final tree (only test_hardening.sh differs) |
| [red_m59_record_check.txt](red_m59_record_check.txt) | the fault suite's new `moved` record check, head reads only, against mutant M59: 4 runs FAIL |
| [red_r3_advance_on_branch.txt](red_r3_advance_on_branch.txt) | F3 on r3: `--advance-pins` detaches a submodule on a branch |
| [red_r3_broken_gitfile.txt](red_r3_broken_gitfile.txt) | F1 on r3: a broken `.git` pointer file reads as `pin-uninitialised` |
| [red_r3_control.txt](red_r3_control.txt) | control run on r3: a sane tree (the probes can see a normal result) |
| [red_r3_f4_f5_f8.txt](red_r3_f4_f5_f8.txt) | F4, F5, F8 shell probe output on r3 |
| [red_r3_foreign_toplevel.txt](red_r3_foreign_toplevel.txt) | F1 on r3: git walks up to the parent; the submodule reads as not initialised, CURRENT |
| [red_r3_integration.txt](red_r3_integration.txt) | the round-4 integration suite against the r3 engine (PASS 122 FAIL 25) |
| [red_r3_stale_head_after.txt](red_r3_stale_head_after.txt) | F2 on r3: `head_after` equals `head_before` after the head moved |
| [red_r3_unit_longsecrets.txt](red_r3_unit_longsecrets.txt) | the long-secret unit class alone against r3 (PASS 1 FAIL 8) |
| [red_r3_unit_newtests.txt](red_r3_unit_newtests.txt) | the round-4 unit suite run against the r3 engine (PASS 50 FAIL 19) |
| [red_r3_unit_probes.txt](red_r3_unit_probes.txt) | F5 behaviour, F7, F9 Python probe output on r3 |
| [red_r3_unit_probes_X04_X05.txt](red_r3_unit_probes_X04_X05.txt) | the Python probe on r3 with reviewer mutant X04, then X05, applied (the probes detect both) |
| [red_r3_unknown_ext.txt](red_r3_unknown_ext.txt) | F1 on r3: a submodule with an unknown repository extension reads as not initialised |
| [red_shell.sh.txt](red_shell.sh.txt) | the shell RED/GREEN probe (F4, F5, F8), run against a given tree |
| [red_unit.py.txt](red_unit.py.txt) | the Python RED/GREEN probe (F5 behaviour, F7, F9a to F9e), run against a given engine file |
| [redact_scaling.txt](redact_scaling.txt) | redact() time against token length on the round-3 and round-4 engines (quadratic; open finding) |
| [static_final_tree.txt](static_final_tree.txt) | `--verify-manifest`, the ledger ratchet and `--sync-guide` again on the final tree |
| [static_pyright.txt](static_pyright.txt) | pyright error counts, r4 and r3 trees |
| [static_ratchet.txt](static_ratchet.txt) | `CM-GATE-LEDGER-RATCHET` |
| [static_shellcheck_final.txt](static_shellcheck_final.txt) | `shellcheck -S warning`, the same 17 files, final tree |
| [static_shellcheck_r3.txt](static_shellcheck_r3.txt) | `shellcheck -S warning` of the changed and sync shell files, r3 tree |
| [static_shellcheck_r4.txt](static_shellcheck_r4.txt) | the same, r4 tree |
| [static_sync_guide.txt](static_sync_guide.txt) | `run_full_suite.sh --sync-guide` (no change) |
| [static_verify_manifest.txt](static_verify_manifest.txt) | `run_full_suite.sh --verify-manifest` |
| [suites_passB_summary.txt](suites_passB_summary.txt) | full pass B: one line per suite, the gate and its meta-test |
| [suites_passB_vs_passC.txt](suites_passB_vs_passC.txt) | pass B and pass C compared with durations removed |
| [suites_passC_summary.txt](suites_passC_summary.txt) | full pass C: the same |
| [unit_durations_real.txt](unit_durations_real.txt) | the six slowest unit tests on the round-4 engine (test_long_secrets about 10 s) |
| [x01_fault_suite_status_control.txt](x01_fault_suite_status_control.txt) | the same reduced run against the round-4 engine: only the by-design run-count checks fail |
| [x01_fault_suite_status_mutant.txt](x01_fault_suite_status_mutant.txt) | the fault suite reduced to the 7 status calls, reviewer mutant X01 applied: 3 runs FAIL (the repository moves) |
| [x05_m08_harness_unit_output.txt](x05_m08_harness_unit_output.txt) | X05 and M08 run as the harness runs them, with the unit suite's output kept (real assertion failures) |

## Findings, fixes and RED/GREEN

RED = the check run against the round-3 engine; GREEN = the same check against the round-4 engine.

| Finding | Fix (class) | RED on r3 | GREEN on r4 |
|---|---|---|---|
| F1: an unreadable submodule read as "not initialised" | `probe_child` replaces `is_repo_root`; `path_kind` (one `os.lstat`) for every filesystem read; exit 128 with a `.git` present at the start directory is BLIND; `--quiet` prints every non-current row (classes A, B) | `red_r3_unknown_ext.txt`: `libs/a not-initialised`, `libs/a/inner present in report: False`, `RESULT: CURRENT`; `red_r3_broken_gitfile.txt`: `pin-uninitialised`; `red_r3_foreign_toplevel.txt` (an empty `.git` directory, so git walks up to the parent): `vendor/t not-initialised`, `RESULT: CURRENT` | `green_r4_unknown_ext.txt`, `green_r4_broken_gitfile.txt`: `blind  pin-unreadable,unresolved:rev-parse:rc:128`; `green_r4_foreign_toplevel.txt`: `blind  pin-unreadable,unresolved:rev-parse:not-own-toplevel`, `RESULT: BLIND exit=6` |
| F2: `head_after` stale after a write | `head_after` read for every initialised repository after the whole pass; unread in `--apply` is a no-answer; moved-then-blocked is attention (class C) | `red_r3_stale_head_after.txt`: `head_after=097a9f38…` = `head_before` while the real head is `433c4926…` | `green_r4_stale_head_after.txt`: `head_after` = the real head |
| F3: `--advance-pins` detached a submodule on a branch | `advance-skipped:submodule-on-branch`, reason `kept-on-branch:advance-pin` | `red_r3_advance_on_branch.txt`: `branch before=feature after=DETACHED` | `green_r4_advance_on_branch.txt`: `after=feature`, attention |
| F4: the partial-clone guard failed open on SIGPIPE | pure-bash `_partial_refused` over a here-string; static early-exit-pipe scan as a test (class F) | `red_r3_f4_f5_f8.txt`: `RED F4-large-input guard: not-refused (fail-open)` | `green_r4_f4_f5_f8.txt`: `GREEN F4-large-input guard refuses` |
| F5: X04 passed the gate; no test ran `proc_kill_group` | the gate requires exactly the three guard terms and `pgid = os.getpgid(p.pid)`; unit class `KillGroup` (class E) | `RED F5-gate X04 passes the gate (rc 0)`; `RED F5-tests no unit test references proc_kill_group` | `GREEN F5-gate X04 refused (rc 1)`; `GREEN F5-tests 9 references` |
| F6: inventory credited the gate with a single-writer check it lacked | the gate refuses a `merge` / `checkout` / `add` outside `write_git` and compares every call site with an oracle table; `--print-sites`; dated correction in the round-3 inventory (class A) | the reviewer's X02b passed the round-3 gate | X02b, X02: gate FAIL (`git merge call … is outside write_git`) |
| F7: trace variables not scrubbed | every `GIT_TRACE*` by prefix, `GIT_CURL_VERBOSE` by name; `Authorization:` header values redacted (class D) | `red_r3_unit_probes.txt`: `RED F7-trace-env ['GIT_CURL_VERBOSE', 'GIT_TRACE2', 'GIT_TRACE2_EVENT', 'GIT_TRACE_PERFORMANCE']` | `green_r4_unit_probes.txt`: `GREEN F7-trace-env []` |
| F8: no fault mode returned git's real 128 | fault mode `rc128` at every call site, its expected outcome read from the gate's oracle; integration case 27 (follow blocked) | `red_r3_f4_f5_f8.txt`: `RED F8-X01 … rc=0 moved=yes APPLIED` (X01 on r3, real 128 at the status re-read) | X01: gate FAIL (mutation table); fault suite FAIL: a real 128 at each of the 3 writer status re-reads lets the mutant move the repository and report `updated` (`x01_fault_suite_status_mutant.txt`; the unmutated engine has no such failure, `x01_fault_suite_status_control.txt`); without the gate the hardening suite kills it first (mutation table); the probe line `F8-X01` in `green_r4_f4_f5_f8.txt` stays RED by design (it shows what the mutant does), and `F8-r3` (a real 128 at the status re-read, unmutated engine: `BLIND exit=6`) is GREEN on both trees as the control |
| F9: no long-userinfo test; X05 survived | cut to the end of the line; configured userinfo remembered and removed where git repeats it; `redact_url`; report keys, argparse errors and unexpected exceptions redacted (class D) | `red_r3_unit_probes.txt`: `RED F9a`, `F9b`, `F9d`, `F9e`; `red_r3_unit_longsecrets.txt`: `PASS 1 FAIL 8` | `green_r4_unit_probes.txt`: all GREEN except the stated boundary `F9b-free-text-unregistered` (below) |
| Nit: a pipe into `grep -q` in `test_chaos.sh` | rewritten; caught by the early-exit-pipe scan | — | the scan's own case |

Suite-level RED: the round-4 unit suite against r3 gave `PASS 50 FAIL 19` (`red_r3_unit_newtests.txt`), the
long-secret class alone `PASS 1 FAIL 8`, and the round-4 integration suite `PASS 122 FAIL 25`
(`red_r3_integration.txt`). Integration section 27 ("follow blocked") passes on r3 as well: it pins down
behaviour that was already right (a characterization test for the F8 class), not a fix.

Found while running the mutation table (class C, not a review finding): M59 (the `head_before is not None` term
of `moved` removed) had been listed as equivalent since round 2, with a proof that ended "`head_after` =
`head_before` (None)". The round-4 post-pass head read made that false: a repository whose first head read gives
no answer and whose second one answers is reported `moved: true` by the mutant although it never moved. No test
held the `moved` field against the disk. `tests/sync/test_faults.sh` now does (control run: the moved set equals
the set of repositories whose HEAD changed; every fault run: a repository reported as moved has a changed HEAD),
and M59 is removed from the equivalent list. On a reduced copy of the fault suite (head reads only, `rc77`), the
M59 mutant fails 4 runs with `moved-in-report-not-on-disk` (`red_m59_record_check.txt`) and the round-4 engine
passes (`green_record_check.txt`); its row in the full mutation table is below. The engine itself is unchanged by
this.

Found while running the mutation table (not a review finding, not one of the six classes): M67 (the writer's
re-read of the parent's index before it stages a pin removed) SURVIVED. No test changed the parent's index
between discovery and that re-read. It survived in round 3 too: the round-3 suites it lists (unit, hardening,
integration) all pass on the round-3 engine with M67 applied, while the same invocation fails the round-3
hardening suite for M66 (`m67_r3_suites.txt`); the round-3 inventory's claim that hardening killed it is
corrected there. `tests/sync/test_hardening.sh` section 14 now covers it: a git wrapper stages another gitlink
for libs/a in the root at libs/a's second status read (the writer's re-read, after discovery), and the case
checks that libs/a is not checked out, that the other gitlink stays staged and that the action names
`blocked:parent-index-changed`; a control run in a fresh tree, without the wrapper, advances and stages the pin.
On the round-4 engine the section passes; with M67 applied, 4 of its 8 checks fail (`hardening_s14.txt`). The
engine is unchanged by this. The case also showed that a write a guard blocks leaves the repository `behind`
(exit 3), not attention; it pins that current classification and the question is an open item below.

Found in the same way: M70 (the check that an `--out` report file is a regular file replaced by `if False:`)
SURVIVED. Section 7 and the unit test `test_only_our_files` both link the tsv path to a file whose CONTENT the
content check refuses anyway, so the file-type check was never the only thing between those cases and a pass.
It survived in round 3 too: the round-3 unit and hardening suites pass on the round-3 engine with M70 applied
(`m70_r3_suites.txt`, same invocation as the M67 run and its control needle). `tests/sync/test_hardening.sh`
section 15 now covers it: a link to a report this engine wrote, of the same kind, and a FIFO at the report path
must both be refused with exit 2 and stay as they are; a control run over the directory that holds the real report
is allowed. On the round-4 engine the section passes; with M70 applied, 4 of its 8 checks fail
(`hardening_s15.txt`): the link is replaced by a regular file (exit 0), and the engine blocks on the FIFO until
`timeout 120` stops it (exit 124). The engine is unchanged by this.

F9b boundary, stated as a fact (probe `F9b-free-text-unregistered`, BOUNDARY on both engines): the structural
cut works line by line, so a userinfo that holds a newline, in text from a URL that is NOT a configured remote
(and so was never remembered), keeps the part after the newline (`S3cr3tPw@example.org` survives). The same
value from a configured remote is removed (`GREEN F9b-registered-free-text`). A remembered secret shorter than 8
characters is removed only inside a URL, a token shape or an `Authorization:` header, never when git quotes it
alone: registering short values would also remove ordinary words (a user name such as `git`).

## Suites, twice

Two full passes, pass B and pass C (one after the other; each suite, the gate and its meta-test in its own
hermetic run), on the tree listed in `mutations_tree_sha256.txt`: the final tree except
`tests/sync/test_hardening.sh`, which gained sections 14 and 15 after the default mutation run had started
(the hardening suite on the final tree is below the table). The sha256 of every engine, test and gate file was checked before and after
each pass against the list taken when the default mutation run started (`mutations_tree_sha256.txt`): the same
at every check. "Check lines" counts the `ok` / `FAIL` lines of the suite's log (the unit suite prints dots, the
gate one line); "Same" compares the exit status, the last line and the sorted check lines of the two passes,
with scratch paths, process ids and measured wall-clock values masked. Before that masking the comparison
reported chaos and perf as different (one process id, two `wall … ms` values), which shows it can see a
difference. Result: IDENTICAL (`suites_passB_vs_passC.txt`).

The fault suite's 21 checks include: 26 call sites from the AST, equal to the gate's oracle; 301 fault runs over
the 88 calls of a full `--apply` run (a signal, an undeclared status, garbage output, and git's real exit 128 at
every call: 88 runs, 4 of them writer failures and 4 unreachable remotes, as the oracle names); every no-answer
made the run `BLIND` and moved nothing it should not; the report's `moved` set equals the repositories whose HEAD
changed on disk in the control run.

| Suite | Pass B result | Pass B time | Pass C result | Pass C time | Check lines (B / C) | Same |
|---|---|---|---|---|---|---|
| unit | rc 0, `sync-unit: PASS 69 FAIL 0 SKIP 0` | 10 s | rc 0, `sync-unit: PASS 69 FAIL 0 SKIP 0` | 10 s | 0 / 0 | yes |
| integration | rc 0, `sync-integration: PASS 147 FAIL 0` | 78 s | rc 0, `sync-integration: PASS 147 FAIL 0` | 94 s | 147 / 147 | yes |
| e2e | rc 0, `sync-e2e: PASS 24 FAIL 0` | 7 s | rc 0, `sync-e2e: PASS 24 FAIL 0` | 8 s | 24 / 24 | yes |
| full_automation | rc 0, `sync-full-automation: PASS 34 FAIL 0` | 14 s | rc 0, `sync-full-automation: PASS 34 FAIL 0` | 17 s | 34 / 34 | yes |
| security | rc 0, `sync-security: PASS 80 FAIL 0` | 18 s | rc 0, `sync-security: PASS 80 FAIL 0` | 20 s | 80 / 80 | yes |
| determinism | rc 0, `sync-determinism: PASS 15 FAIL 0` | 23 s | rc 0, `sync-determinism: PASS 15 FAIL 0` | 26 s | 15 / 15 | yes |
| ui | rc 0, `sync-ui: PASS 24 FAIL 0` | 12 s | rc 0, `sync-ui: PASS 24 FAIL 0` | 13 s | 24 / 24 | yes |
| hardening | rc 0, `sync-hardening: PASS 102 FAIL 0` | 53 s | rc 0, `sync-hardening: PASS 102 FAIL 0` | 66 s | 102 / 102 | yes |
| chaos | rc 0, `sync-chaos: PASS 58 FAIL 0` | 88 s | rc 0, `sync-chaos: PASS 58 FAIL 0` | 108 s | 58 / 58 | yes |
| perf | rc 0, `sync-perf: PASS 13 FAIL 0` | 39 s | rc 0, `sync-perf: PASS 13 FAIL 0` | 58 s | 13 / 13 | yes |
| faults | rc 0, `sync-faults: PASS 21 FAIL 0` | 1100 s | rc 0, `sync-faults: PASS 21 FAIL 0` | 1436 s | 21 / 21 | yes |
| gate | rc 0, `CM-SYNC-UPSTREAMS-FF-ONLY: PASS — … (full line in the summary file)` | 1 s | rc 0, `CM-SYNC-UPSTREAMS-FF-ONLY: PASS — … (full line in the summary file)` | 1 s | 0 / 0 | yes |
| gate_meta | rc 0, `CM-SYNC-UPSTREAMS-FF-ONLY mutation test: PASS (83 cases)` | 81 s | rc 0, `CM-SYNC-UPSTREAMS-FF-ONLY mutation test: PASS (83 cases)` | 92 s | 83 / 83 | yes |

Hardening on the final tree: after sections 14 and 15 were added, the hardening suite was run twice more
(`hardening_final_twice.txt`), on a copy of the working tree whose files have the same sha256 as the final tree
(listed in that file): rc 0 and `sync-hardening: PASS 118 FAIL 0` both times (81 s and 84 s), sorted check lines
IDENTICAL. Against pass C the only difference is the 16 checks of sections 14 and 15, all added; no check of
pass C is missing or changed (this also shows the comparison sees a difference). No other suite, the gate or its
meta-test reads `tests/sync/test_hardening.sh` (only `tests/sync/run_all.sh` and the mutation harness run it), so
the pass B and pass C results of the other suites stand for the final tree.

## Mutation table

`tests/sync/test_mutations.py` applies each mutant to a copy of the engine (its anchor must occur exactly once)
and runs the mutant's suites in order, stopping at the first that fails. Three runs:

- **Default** (`mutations_default.txt`): all 131 mutants, each with its own suite list (the gate first where the
  list names it), on the tree listed in `mutations_tree_sha256.txt` (the final tree before hardening sections
  14 and 15); the same files were checked again at its end. The table below is this run with the rows of
  M67 and M70 replaced by their re-run on the final tree (`mutations_default_composed.txt`, explained below).
- **Gate only** (`mutations_gate_only.txt`): the reviewer's (X) and the fixer's (N) mutants against the static
  gate alone. It was run before the default run, on the same engine (sha256 `a4b70934…`) and gate
  (`4b96513f…`) as the final tree; only the M59 row of the mutant table, the fault suite and the hardening
  suite (sections 14 and 15) changed after it, and none of them is read in this mode.
- **Without the gate** (`mutations_no_gate.txt`): the X and N mutants against their behavioural suites alone, so
  a kill here shows that a test (not only the static gate) catches the mutant.

A survivor in the gate-only run is expected for a mutant that changes behaviour the gate does not model (N01 to
N12, N17, N24, N25: classification, record and output changes); each is killed by a suite in the default run.

Kills that take well under a second (X05, M08 by the unit suite in about 0.3 s, where the suite takes about 10 s on
the real engine) were checked, because the harness counts any non-zero exit as a kill and keeps no output. Run as
the harness runs them, with the suite output kept (`x05_m08_harness_unit_output.txt`), both ran all 69 unit tests
and failed on assertions (X05: FAIL 2, M08: FAIL 9), not on a crash. The suite is fast for them because 9.9 of its
10.8 seconds (one measured run) are `LongSecrets.test_long_secrets` (`unit_durations_real.txt`), whose 65 536-character case is slow on
the real engine (see the open `redact()` finding) and is never reached by a mutant that fails at a short length.

The composed table. Hardening sections 14 and 15 were written while the default run was going (M67 and M70
survived it), and the run was not restarted. Adding a case only to the hardening suite can change a row only when
the row SURVIVED, or when the suite that killed it comes after hardening in the mutant's own suite list (then the
new case may fail first). Every other row is unchanged by construction: its suites before hardening are the same
files, and a suite that already failed still fails. In the default run those rows are M67 and M70 (both SURVIVED,
nothing else qualifies); they were run again on the final tree with the same harness in the default mode
(`--only M67,M70`, `mutations_default_rerun.txt`): both KILLED by hardening (M67 in 146 s, M70 in 267 s, most of it the FIFO case waiting for `timeout 120` on the mutant), and the run's own summary reads `mutants 2 killed 2`. In the run without the gate the only such row is
X06 (killed by faults, which comes after hardening); the final hardening suite passes on the X06 mutant
(`hardening_final_twice.txt`), so X06's first failing suite is still faults and that table stands for the final
tree. The gate-only run does not read the hardening suite.

| Mode | Mutants | Killed | Equivalent | Survived | Harness errors |
|---|---|---|---|---|---|
| default, composed (each mutant's own suites, gate first where listed; M67 and M70 from the re-run on the final tree) | 131 | 130 | 1 | 0 | 0 |
| `--gate-only`, X and N mutants | 33 | 18 | 0 | 15 | 0 |
| `--no-gate`, X and N mutants | 33 | 33 | 0 | 0 | 0 |

Default run, kills per first failing suite: unit 43, gate 31, integration 25, chaos 11, hardening 11, faults 3, security 3, ui 3.
Equivalent (proofs in `tests/sync/test_mutations.py`): M37. Survived: none.

Reviewer mutants (round 3, verbatim):

| Id | Mutation | Default | Gate only | Without the gate |
|---|---|---|---|---|
| X01 | writer status re-read accepts rc 128 as a clean answer (ok-set widened at a write guard) | killed by gate | killed by gate | killed by hardening |
| X02 | fast-forward bypasses the one guarded writer (direct merge call site in integrate) | killed by gate | killed by gate | killed by e2e |
| X02b | fast-forward bypasses write_git but still records the action (guards skipped, record intact) | killed by gate | killed by gate | killed by security |
| X03 | a second spawn site (git --version precheck) inside proc_run_git | killed by gate | killed by gate | killed by unit |
| X04 | tautological pgid guard: (pgid > 1 or True), pgid == p.pid dropped | killed by gate | killed by gate | killed by unit |
| X05 | userinfo cut looks only 48 chars past scheme:// (long password leaks) | killed by gate | killed by gate | killed by unit |
| X06 | a call site whose 'declared' ok set is every status 0..255 (ls-files -s, index gitlinks) | killed by gate | killed by gate | killed by faults |
| X07 | SAFE_CONFIG: a trailing core.hooksPath pair overrides /dev/null (presence-only argv check) | killed by gate | killed by gate | killed by security |

Own mutants (round 4):

| Id | Mutation | Default | Gate only | Without the gate |
|---|---|---|---|---|
| N01 | F1/B: a path lstat cannot read is "absent" | killed by unit | survived | killed by unit |
| N02 | F1/A: a submodule whose rev-parse exits 128 is "uninitialised" | killed by unit | survived | killed by unit |
| N03 | F1/A: a foreign top level (git walked up to the parent) is accepted as the submodule | killed by unit | survived | killed by unit |
| N04 | F1/A: a foreign top level is "uninitialised" with no no-answer recorded (the r3 shape) | killed by unit | survived | killed by unit |
| N05 | F1/B: an operation marker that cannot be read is not "in progress" | killed by unit | survived | killed by unit |
| N06 | F1/A start-dir: exit 128 with a .git present is "not a work tree" (usage), never BLIND | killed by unit | survived | killed by unit |
| N07 | F2: head_after is a copy of head_before, never re-read after the pass | killed by unit | survived | killed by unit |
| N08 | F2: a repository that moved and is blocked afterwards is "updated" | killed by integration | survived | killed by integration |
| N09 | F3: --advance-pins detaches a submodule checked out on a branch | killed by unit | survived | killed by unit |
| N10 | F3: kept-on-branch is never a reason (a kept submodule reads as current) | killed by unit | survived | killed by unit |
| N11 | F1: a path that is not a directory (a symbolic link) needs no attention | killed by integration | survived | killed by integration |
| N12 | F1: an unreadable submodule carries no pin-unreadable reason | killed by integration | survived | killed by integration |
| N13 | F9: userinfo cut at the FIRST "@" (a password holding "@" leaks its tail) | killed by gate | killed by gate | killed by unit |
| N14 | F9: the URL token ends at a space (a password holding a space leaks its tail) | killed by gate | killed by gate | killed by unit |
| N15 | F9: only secrets of 64 characters or more are remembered | killed by gate | killed by gate | killed by unit |
| N16 | F9: a remembered secret said without its URL is not removed | killed by gate | killed by gate | killed by unit |
| N17 | F9: the lines of a multi-line userinfo are not remembered one by one | killed by unit | survived | killed by unit |
| N18 | class D: report keys are written unredacted | killed by gate | killed by gate | killed by unit |
| N19 | class D: a usage error echoes its argument unredacted | killed by gate | killed by gate | killed by unit |
| N20 | F7: GIT_TRACE* variables are no longer dropped (prefix) | killed by gate | killed by gate | killed by unit |
| N21 | F7: GIT_CURL_VERBOSE is no longer dropped | killed by gate | killed by gate | killed by unit |
| N22 | F5: the group guard drops "pgid == p.pid" (a foreign group can be signalled) | killed by gate | killed by gate | killed by unit |
| N23 | F5: the group is assumed to be the pid, never read | killed by gate | killed by gate | killed by unit |
| N24 | F1: --quiet hides blind and not-initialised rows (the r3 shape) | killed by integration | survived | killed by integration |
| N25 | F8 class: a child that cannot fetch its new pin is not failed | killed by integration | survived | killed by integration |

## Static checks, manifest, ratchet

| Check | Round-3 tree | Round-4 tree | File |
|---|---|---|---|
| `shellcheck -S warning` (the changed and the sync shell files) | 18 warnings at 16 locations (14 SC2034, 2 SC2155, 1 SC2154, 1 SC2194) | the same 18 at the same 16 locations: no new warning | `static_shellcheck_r3.txt`, `static_shellcheck_r4.txt` |
| pyright, `scripts/sync/sync_all_upstreams.py` | 26 errors | 20 errors | `static_pyright.txt` |
| pyright, `tests/sync/test_unit.py` | 10 errors | 10 errors, the same classes and counts | `static_pyright.txt` |
| pyright, `tests/sync/test_mutations.py` | 0 | 0 | `static_pyright.txt` |
| `run_full_suite.sh --verify-manifest` | — | MANIFEST-OK, census total 915, twice | `static_verify_manifest.txt` |
| `CM-GATE-LEDGER-RATCHET` | — | PASS, unimplemented 394 = baseline 394, twice | `static_ratchet.txt` |
| `run_full_suite.sh --sync-guide` | — | no change to the guide's census block | `static_sync_guide.txt` |
| `tests/install/test_unit.sh` (the F4 change in `tests/install/lib.sh`) | — | PASS 226 FAIL 0, once | `install_unit.txt` |

The engine's 20 pyright errors fall in 5 classes (rule plus message with names removed); each class count is at
or below the round-3 tree's, and no class appears that the round-3 tree does not have (`static_pyright.txt`).
The install suite was run once, not twice: only `lib.sh`'s partial-clone guard changed there, and the rest of
that suite belongs to the installer vehicle.

On the final tree (after hardening sections 14 and 15 were added; no Python file changed, so the pyright rows
stand): `shellcheck -S warning` over the same 17 files gives 17 warnings at 15 locations (13 SC2034, 2 SC2155,
1 SC2154, 1 SC2194; `static_shellcheck_final.txt`): one fewer than the round-4 tree, because section 15 reads the
`out` variable that section 7 set and never read (the script that counts was run on the round-4 tree first and
gave its 18 at 16). `--verify-manifest` MANIFEST-OK (census total 915), the ledger ratchet PASS (394 = 394) and
`--sync-guide` with no change, once each (`static_final_tree.txt`).

## The test_lock failure: root cause

Round 3 reported one `tests/install/test_lock.sh` failure in four runs ("the paired mutant's reclaim race"),
cause UNCONFIRMED; the round-3 reviewer did not investigate it. The mechanism, now shown:

- `reclaim_race()` starts run A, then polls at most 400 times (`grep` plus `sleep 0.05`, nominally 20 s) for
  A's `TEST PAUSE reclaim` line, and then swaps the stale lock for a live one **whether or not A has paused**.
  If A has not yet judged the lock, it finds the live lock, refuses (`rc=3`), and the case fails.
- In the installer and updater loop a control check ("run A paused after it judged the lock stale") fails too
  and names the cause. The paired-mutant section has no such control check, so there the only failure printed
  is `mutant (no re-check): A took the lock (rc=0)`, which is the shape round 3 saw.
- Reproduction (`lock_repro_delay_{0,25,90}.txt`; the harness function and the mutant build copied verbatim,
  only run A's start delayed): delay 0 s: pause seen, PASS; delay 25 s: pause seen (under load the 400 polls
  took 25 s), PASS; delay 90 s: `pause_seen=no`, `A_rc_line=rc=3`, `FAIL mutant (no re-check): A took the lock
  (rc=0)`.
- What would fix it (not done here: outside this vehicle's scope, §11.4.293): never swap the lock before the
  pause line is seen; when it is not seen within a time bound, report the case as inconclusive (BLIND), not
  FAIL; and add the control check to the mutant section.

UNCONFIRMED: that the round-3 run failed for this reason. The mechanism is shown; the attribution rests on the
matching signature, because no timing of that run was kept.

## Notes for the lander

- **Dependency.** `scripts/install_constitution.sh` (`hi_push_changed`) has the same SIGPIPE defect as F4. It is
  not changed here; another vehicle (`vehicle/installer-sigpipe`) owns it. Until it lands, an install-suite run
  can still report a push that did not happen (a false FAIL, never a missed push).
- **Roadmap id.** `bc1a03a5` carries `Roadmap-Item: CON-PENDING-SYNC`; `b5a1815a`, `1752be71` and the round-4
  commit carry `CON-PENDING-SYNC-UPSTREAMS`, as does `CHANGELOG.md`. Use one id when landing (the one the tracker
  holds), in the landing merge message; never by rewriting history (§11.4.113).
- **Evidence class.** Every figure here is gate-logic / unit class (§11.4.289). Status stays PROVISIONAL until an
  independent review returns GO and a live run against a real forge exists.

## Open items and UNCONFIRMED

Open (not fixed in round 4, each to be tracked):

- **`redact()` takes time quadratic in the length of a line (found at the end of round 4, not fixed).** The
  scheme pattern `_SCHEME = [A-Za-z][A-Za-z0-9+.-]*://`, searched with `finditer` in `strip_secrets`, rescans a
  long run of scheme characters from every start position when no `://` follows. Measured (`redact_scaling.txt`):
  a line of 65 536 letters with no URL takes about 8 s on both the round-3 and the round-4 engine, and doubling
  the length about quadruples the time; so a 1 MiB line of git output would take over half an hour, with no
  timeout around it. It is older than round 4 (the same pattern at the same line in round 3). It was found after
  the evidence runs on this tree had started, so the engine was not changed here; the fix (a pattern that cannot
  rescan, for example matching the scheme only after a character that cannot be part of it, plus a test that
  times a long line) and the decision whether long lines need a cap belong to the next round.
- **A blocked write is `behind`, not attention.** When `write_git` refuses a requested write because the tree
  changed or the parent's index changed after discovery, the repository ends `behind` (exit 3,
  UPDATES-AVAILABLE) with no reason; the ignored-file guard instead adds `ignored-file-would-be-overwritten`
  (exit 4, ATTENTION). The action list names the block in both cases. Older than round 4 (the classification
  code is unchanged); `test_hardening.sh` section 14 pins the current outcome (`3 behind`). Whether a blocked
  write should be ATTENTION is a decision for the next round.
- **Follow blocked: hold the parent?** When a child cannot follow its parent's new pin (integration case 27,
  `follow-blocked:new-pin-unfetchable`), the parent has already moved and the run ends `failed` (exit 1) with one
  next step. Whether the parent should instead be held back until every child can follow is a design question
  for the operator; it is not implemented.
- **Installer SIGPIPE.** `scripts/install_constitution.sh` (`hi_push_changed`) keeps the F4 defect until
  `vehicle/installer-sigpipe` lands (see [Notes for the lander](#notes-for-the-lander)).
- **The general killpg gate passes X04.** `CM-KILLPG-PGID-GUARD` (§11.4.263) still PASSes on reviewer mutant X04
  (`pgid > 1 or True`); only this vehicle's gate refuses it. Making the general gate require the full guard is a
  separate item outside this vehicle.
- **`test_lock` harness.** The fix described above (never swap before the pause is seen; a missing pause is
  BLIND; a control check in the mutant section) belongs to the install-suite owner.
- **Clean/smudge filters.** A filter or diff driver the user configured still runs when git writes or compares
  files (the engine's stated boundary; disabling filters would break LFS-style repositories). No test runs a
  hostile filter.
- **Overlapping remote names.** Whether two remotes whose names overlap as a path prefix (`a` and `a/b`) can
  collide in `refs/remotes/<remote>/*` was not pursued (round-3 review, section 8).
- **`SYNC_STEP_EXTRA_ARGS`.** No mutant weakens the check of this variable in `scripts/sync/sync_step_lib.sh`
  (only `--out /absolute/dir` is honoured); it is covered by `test_hardening.sh` case 11 and `test_full_automation.sh`, not by a mutant.

UNCONFIRMED:

- **Real forge.** Every run here used local `file://` bare repositories and one refusing loopback port. Behaviour
  against a real forge (HTTPS with credentials, SSH, rate limits, partial clones served by a forge) is not shown.
- **`Authorization:` header redaction under a real forge.** Shown with synthetic header text only; whether a real
  forge's error output carries the header in this exact shape is not shown.
- **F9b boundary.** As stated above: an unregistered userinfo that holds a newline keeps its tail. Removing it
  would need an unbounded cut across lines, which would also remove ordinary output; not done.
- **F1 with dubious ownership (`safe.directory`)** was not run through the engine: it needs a change of file
  owner, which this host does not allow without privileges. From the code only (not shown): git refuses such a
  repository with exit 128, and `probe_child` reads exit 128 with a `.git` present as unreadable, as in the
  real-git cases shown (`unknown_ext`, `broken_gitfile`).
- **`test_lock` attribution** (see above).
- **Evidence retention.** The copies here are text with the scratch prefix replaced; the original logs are in a
  scratch directory that is not kept.
