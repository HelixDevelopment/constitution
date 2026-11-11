# Independent §11.4.142 / §11.4.209 review: fu_a bundle (follow-ups CON-159, CON-160, CON-161, CON-162)

| Field | Value |
|---|---|
| Bundle | `fu_a.bundle`, sha256 `cf9c8ebbab32d43e8ea476419dfe6c451a911681a42e7375a183ee9114bc11c8` (measured, matches). Head `bdf7a135`, 5 commits on `fc57ad0c`. Prerequisite `fc57ad0c` fetched from `github_helixdevelopment` (`git@github.com:HelixDevelopment/constitution.git`); `git bundle verify` then OK. The bundle's only ref is `HEAD` (not a `vehicle/fu-a` branch name); I fetched it as local branch `fu_a`. |
| Reviewer | Claude Opus 5.5, dispatched as a subagent. Reasoning effort cannot be set or read from inside a subagent, so no `xhigh` claim is made (§11.4.231(F.2) gap). |
| Clone | `.../74ce2b36-.../scratchpad/rev_fu_a/constitution` (fresh clone of the local repo + bundle). Each own mutant ran in a throwaway `git archive` copy under `.../rev_fu_a/mut/w.*/constitution`, deleted afterwards (`rm -rf "${W:?}"`). Mutant driver `.../rev_fu_a/mut/run.sh`, outputs `.../rev_fu_a/mut/*.out`. Live checkout not touched; nothing pushed. |
| Host | busy; every heavy command under `nice -n 10` and `timeout`, at most one heavy run at a time. |

## Verdict: GO-with-follow-ups. 0 critical, 0 important, 3 minor, 4 nit

All four items close what the parent review asked for in their core; two narrowings (CON-161's ps-failure path, and the integration/refusal paths of CON-162) leave real survivors of my own mutants. Every open finding is `test-instrumentation` or `process-doc` at severity `minor` or `nit`; none is a `source-defect` (the source of all four items is correct as shipped; I re-derived this). Under §11.4.276(G.2) each minor finding below becomes a tracked follow-up. This is not a zero-finding GO.

## What I ran (all in the clone, this session)

| Check | Result |
|---|---|
| `test_custody_sweep_stash_index_unpatched_r23_regression.sh` (bash, and `sh`) | rc 0, `pass=5 fail=0` (5 axes; Y12/Y14/Y15/Y16 killed), 1.5 s |
| `test_host_report_probe_thread_headroom_r2_regression.sh` (bash, and `sh`) | rc 0, `pass=6 fail=0` (Y4/Y5/**Y6**/Y9/Y10 killed), 1.8 s. **Y6 independently verified killed**: no hang; the THREADS_UNREADABLE case catches the TypeError as `EXC` and fails the case. |
| `test_enumerate_decision_mutants_r2_regression.sh` | rc 0, `pass=4 fail=0` (n1 leftover check, 4 n2 classifier checks, M1/M2/M3 killed) |
| `test_decision_mutant_census_wording_r1_regression.sh` | rc 0, `pass=4 fail=0` (M1/M2/M3 killed) |
| `enumerate_decision_mutants.py --selftest` | `pass=24 fail=0` |
| `test_enumerate_decision_mutants.sh` | `pass=13 fail=0` |
| `run_full_suite.sh --verify-manifest` | `RESULT: MANIFEST-OK`, census total=883; 4 new manifest rows present (two `member` under `run_all.sh`, two `entry`) |
| `workable-items validate` (DB copy) | `OK — 191 items` (reproduction closure gate not armed, as before) |
| `workable-items diff --issues --fixed` | in sync, 191 vs 191 |
| Tracker | CON-159..162 all `Ready for testing`, `**Verification:** provisional (section 11.4.290)`, reproduction `reproduced-host-fixture` (surface host-only), investigation `root-cause-found-with-evidence`. Every `docs/qa/` path cited in the four items resolves. No new ids. |

I did not run the full census, r22, or the full suite.

## Source re-derivation ("source unchanged, already correct")

- **CON-160** `stash_index_unpatched` (custody_sweep.py:872): patch None or non-empty -> False; `git diff --quiet ^1 ^2` rc 0 -> False, rc 1 -> True, else None; caller line 2099 refuses unless the value `is not False`. Matches the docstring and the parent review's description; fail-closed on None. Correct; this is test-instrumentation only, as claimed.
- **CON-161** `probe_thread_headroom` (host_report.py:1140) and `_read_ulimit_threads` (1089): unlimited -> unlimited_ulimit; any None -> unmeasured; headroom = ulim - thr; per_job = headroom + 1 if > 0 else 1. Correct as shipped; the parent's Y4-Y6 were test gaps.

## Per-item verdicts

### CON-160: GO
The test drives the REAL function on REAL git repos (index-only stash `idx`, worktree stash `wt`) and a PATH shim that makes only `git diff --quiet` exit 128 (a real fault-injection of a dependency, unit scope of §11.4.289(C)). It pins True / False / None, kills Y12 and Y14 (the parent's survivors) plus Y15/Y16. The parent's first fix suggestion (assert `index_unpatched=True` inside EP2V's refusal message) was met at the function level instead; since the message prints `live.get("index_unpatched")` verbatim (line 2104-2106), pinning the function value covers it. Acceptable. Own mutants RA and RB killed (below).

### CON-161: GO-with-follow-up (m1)
Y4/Y5/Y6 killed; Y6 measured by me (killed, fast). But the parent asked for a fixture "when `FC_GUARD_THREADS` is unset and `ps` fails"; every case sets `FC_GUARD_THREADS` (the unreadable case uses `"xyz"`), so the `ps` path of `_read_ulimit_threads` is still untested. My mutant RD survives all three canon tests (finding m1).

### CON-159: GO (n1)
Docstring, meta-test header and CON-158 text reworded to "matched by the closed operator list"; no remaining overstatement found (`git grep -i "every decision point"` / `"closes the class"`: only accurate or historical hits). The commit message of `02e681a6` cannot be changed and is not required. Optional operators not added (stated honestly). The wording guard is phrase-exact (nit n1).

### CON-162: GO-with-follow-ups (m2, m3, n2, n3)
- n1: `kill_session(sid)` scans `/proc/*/stat`, matches field `session` (rest[3], correct offset after the comm parenthesis), skips zombies and pid <= 1, `os.kill(pid, SIGKILL)` per process, 5 passes; refuses non-int or `sid <= 1` with ValueError before any signal (§11.4.263(A)/(B) satisfied: no `killpg`/`kill(-pid)` anywhere in the changed code). `sid` is `p.pid` of a child started with `start_new_session=True`, so it is a session we own; a session id is not reused while members live. Host-safe. The test's own EXIT cleanup kills only pids whose stat field 6 equals the recorded sid, after `case` rejects empty/non-numeric/0/1. Real artifact: real `run_bounded` on a real `timeout 100 sleep 97` with a 3 s bound; RED reproduced by the author (left=[timeout, sleep]) and my mutant RE (match pgrp instead of session) brings it back (killed). Not pinned: the refusal guard itself (m2).
- n2: `is_stale_killed` correct for `KILLED`; but its wiring in `main()` is untested (m3), and `KILLED-TIMEOUT` of a ledger key is not flagged (n2).
- n3: not reproduced, no change: honest, but the open nit now lives only inside a Ready-for-testing item (n3 below).
- n4: not acted, reasoned (ownership by the vehicles). Accepted.

## Reviewer-authored mutants (§11.4.194(6)(d)): 8 run, 4 killed, 4 survived

| # | Item | Mutation | Test | Result |
|---|---|---|---|---|
| RA | CON-160 | `git diff --quiet ^1 ^2` -> `^1 <stash>` (compare base with the worktree tree) | r23 | KILLED (4/1) |
| RB | CON-160 | pass `env=None` to `_run` (ignore the caller's env) | r23 | KILLED (4/1, GITF axis) |
| RC | CON-161 | `if returned_n is None:` -> `if returned_n == 0:` (a real "0" read as probe_failed) | r2 | KILLED (5/1, EXHAUSTED and ZERO) |
| RD | CON-161 | `_read_ulimit_threads`: failed `ps` -> `thr = "0"` instead of None (a ps failure reads as zero threads, headroom = full ulimit) | r2; also r1 and host_guard_red | **SURVIVED** r2 6/0, r1 45/0, host_guard_red 140/0 (control leg r1 on an unmutated archive copy 45/0) |
| RE | CON-162 | `kill_session`: match `rest[2]` (pgrp) instead of `rest[3]` (session) | r2 | KILLED (n1 check: left=[timeout, sleep]) |
| RG | CON-162 | drop the `sid <= 1` refusal (`if not isinstance(sid, int):`) | r2 | **SURVIVED** (4/0). Static only: no test calls `kill_session` with a bad sid, so running it was safe. |
| RI | CON-162 | call site `if is_stale_killed(...)` -> `if False and ...` (the new STALE path never fires in `main()`) | r2 | **SURVIVED** (4/0) |
| RH | CON-159 | docstring "enumerates the decision points" -> "enumerates all decision points" | wording r1 | **SURVIVED** (4/0) |

## Findings

### m1: minor, test-instrumentation (CON-161). The ps-failure path the parent asked for is still unpinned (RD survives)
Parent m3 asked for a canon fixture pinning `reason=unmeasured` "when `FC_GUARD_THREADS` is unset and `ps` fails". The new test only sets `FC_GUARD_THREADS="xyz"`, which reaches `thr_i = None` by the `int()` path, not by the `rc != 0` / `out is None` path. RD (a ps failure counted as 0 threads, which overstates headroom to the whole soft limit) survives r2, r1 and host_guard_red. Fix: a case with `FC_GUARD_THREADS` unset and a PATH shim `ps` (or `sh`) that exits non-zero, asserting `reason=unmeasured`; RD as its paired mutant.

### m2: minor, test-instrumentation (CON-162 n1). The §11.4.263 refusal of `kill_session` is not pinned (RG survives)
The guard exists and is correct, but no test asserts that `kill_session(1)`, `kill_session(0)`, `kill_session(-5)` and `kill_session("7")` raise ValueError. Fix: add those calls in the r2 driver with `os.kill` patched to record-and-refuse (unit scope, so a mutated guard can never signal anything), asserting ValueError and zero recorded kills. Under §11.4.263(C) the test, not only the code, must carry the guard.

### m3: minor, test-instrumentation (CON-162 n2). The STALE-on-KILLED wiring in `main()` is untested (RI survives)
The r2 test calls `is_stale_killed` directly; the call site that bumps `res["STALE"]` (and so the exit code) has only the author's one-off end-to-end evidence (con162 evidence file). Fix: drive `main()` on a scratch target whose single mutant is killed and planted in a temp ledger (or factor the classification loop), asserting the `STALE` line and exit 1; RI as the paired mutant.

### n1: nit (CON-159). The wording guard is phrase-exact (RH survives)
It rejects only the three historical phrasings. A re-overstatement in other words passes. Acceptable for a wording guard; could also require the "not that every decision point is covered" scope sentence to be present.

### n2: nit (CON-162 n2). A ledger key whose mutant is `KILLED-TIMEOUT` is not flagged STALE
`is_stale_killed` tests `verdict == "KILLED"` only; the census counts KILLED-TIMEOUT as a kill elsewhere, so the same false equivalence proof passes silently when the mutant hangs. Either flag it too or record why a timeout is not a refutation (load-induced timeouts).

### n3: nit, process-doc (CON-162). n3 stays open inside an item set to Ready for testing
n3 (porcelain `git diff --quiet` vs plumbing) is recorded as not reproduced and UNCONFIRMED, which is honest, but once CON-162 closes the open question has no tracked home. Register it as its own Queued item (or keep CON-162 open for it) per §11.4.197.

### n4: nit, process-doc (all four). Stale description sentence
Each description still ends "Status Queued: no fix is claimed; ..." while the status is `Ready for testing` with a provisional fix claimed. Update the sentence.

## RED baseline for Y6 (the author's record says "no verdict, r1 hung")
I applied Y6 to an archive copy and ran the pre-existing r1 test: `Y6_r1 rc=0 === host_report thread limit regression guard (CON-147 F2-1): pass=45 fail=0 ===`, wall time 50 s, no hang. So Y6 SURVIVES r1 (RED reproduced) and is KILLED by the new r2 test (GREEN). The author's hang is not reproduced here (UNKNOWN cause; possibly host load in place). The CON-161 investigation line ("Y6 not measured by me") can now cite this measurement.

## Not re-verified
- Full census, r22 with Y14, full suite; n3 (I did not build a submodule fixture either).
