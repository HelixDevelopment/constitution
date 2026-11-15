# Installer follow-ups, round 2 (2026-11-14): evidence

| Field | Value |
|---|---|
| Status | PROVISIONAL (independent review pending; no review claim is made here) |
| Roadmap item | CON-PENDING-installer-followups-r2 |
| Base | `e1bf1bad` (bundle of round 1, sha256 `78f516a4…` checked before work) |
| Commits | `86fdc766` (the timeout class, the derived census, the pty driver), `b60cda35` (lib_decide keeps the command text the jev tests anchor on), this evidence commit |
| Review answered | `review_installer_followups.md` of head `e1bf1bad` (sha256 `d88a7d08…` checked): F-1 important, F-2 and F-3 minor, F-4 and F-5 nits, F-6 nit (follow-up only) |
| Host | Linux 7.0.0-43, bash 5.3.9, git 2.53.0, Python 3.14.4, GNU timeout as `/usr/bin/gnutimeout`, uutils coreutils 0.10.0 as `/usr/bin/timeout`; load average 27 to 53 during the runs |

All heavy runs: `systemd-run --user --scope -p TasksMax=2000 nice -n 10`, at most two at a time. Effort of the
agent that did the work: UNKNOWN (§11.4.231(F.2)).

## 1. F-1: every timeout the four entry scripts can reach (the class, not the one site)

**Defect.** `scripts/post_update_hook.sh` `install_jev_bootstrap` ran `timeout "$JEV_HOOK_TIMEOUT" bash bootstrap.sh`
with no `trap '' TTIN TTOU`. Under uutils timeout a bootstrap that touches the terminal stops timeout and itself,
and the hook never returns (the CON-112 mechanism of round 1).

**RED on the old sources** (`runs/timeout_tty_RED_before_fix_r2.txt`, the new test run against the round-1 scripts):
`T8 post_update_hook install_jev_bootstrap ... [uutils]: rc=CAPPED secs=30.2 left=0` (the driver gave up at its 30 s
cap; the hook budget was 2 s), GNU leg ok; the census FAILs because sites outside the six install scripts were not
classified; `timeout_tty: PASS 22 FAIL 3`.

**Census, derived, not listed by hand.** `tools/census_new.py.txt` builds the file set as the closure of the four
entry scripts (`install_constitution.sh`, `update_constitution.sh`, `post_update_hook.sh`, `jev/bootstrap.sh`):
every file named by a file name or a `scripts/...` path, plus `scripts/x/$v.sh` resolved from `for v in ...` lists
(this found `scripts/gates/cm_jev_detection.sh`, run by bootstrap as `scripts/gates/$g.sh`). Excluded: `tests/`
(fixtures), `.git`, `submodules/`, `node_modules`. Comment lines are skipped. Each site is classified `yes` (the
ignore is set earlier in the same subshell, substitution or group, on the same line or in the enclosing scope),
`fg` (`--foreground`) or `no`. An ignore placed after the timeout is not credited (F-3, below). The same census runs
inside `tests/install/test_timeout_tty.sh`, with control needles on a mini tree
(`a.sh|fa|yes a.sh|fb|no lib/b.sh|fc|yes|no|no|fg|no scripts/x/c.sh|-|no`: reachability through a path, through a
file name and through a `for` list, and ignored / bare / --foreground / ignore-after-timeout told apart).

Result on `b60cda35` (`census/timeout_site_census_r2.tsv`): 19 sites, 15 `yes`, 4 `no`, 0 `fg`.

| Site | Fix |
|---|---|
| `post_update_hook.sh` `install_jev_bootstrap`, the run and the `--defer` retry | subshell: `cd`, `trap '' TTIN TTOU`, `exec timeout` (one runner, no array) |
| `jev/bootstrap.sh` `run_bounded`, `run_gate` | `(trap '' TTIN TTOU; exec timeout --kill-after=2 ...)` |
| `jev/lib_decide.sh` `jev_effective_mode` (`require-validated`) | `(trap '' TTIN TTOU; LLMCTL_VALIDATE_STRICT=1 timeout 60 ...)`, no `exec` so the jev r3/r4 test anchors still match (`b60cda35`) |
| `jev/lib_keys.sh` `_jev_key_value` | ignore inside the command substitution |
| `gates/cm_jev_detection.sh` `_run` | `(trap '' TTIN TTOU; exec timeout ...)` |
| `label-sync/hooks/label-sync-lib.sh` `ls_ctl` | `(trap '' TTIN TTOU; exec timeout ...)` |
| `label-sync/render/statusline.sh` | ignore in the `{ }` group before `timeout 1 bash "$labeler"` |
| `multitrack/multitrack_balance.sh` `mt_provider_operability_probe` | ignore in the substitution that runs the `$_to curl` word list |
| `multitrack/multitrack_cwd_hook.sh` `_cwh_owner_busy` | ignore inside the command substitution |
| `install_constitution.sh` / `update_constitution.sh` `hi_gx`, `hi_version_of`, `hi_detect_agents` (x2) | unchanged from round 1 (`yes`) except the `hi_gx` comment (F-4) and `hi_version_of` (F-5) |

The four `no` lines, each checked by an exact test assertion:

- `hi_run_agent`: the line is the array definition `local -a cmd=(timeout ...)`; the job that runs the array
  ignores the two signals (`hi_run_agent: the job that runs the timeout array ignores SIGTTIN/SIGTTOU`, and T6).
- `multitrack_balance.sh`: the line is the string `_to="timeout ..."`; the substitution that runs it ignores them.
- `hi_lock_pid`, `up_lock_pid`: `timeout 5 head -c 20 -- "$f"` after `[ -f "$f" ] && [ ! -L "$f" ]`; head reads a
  regular file, so it does not touch the terminal in normal operation. The check-then-open race of review F-6 stays
  (follow-up FU-1).

**Live run of the hook site.** T8 (new) extracts `install_jev_bootstrap` from `post_update_hook.sh` with awk,
sources it with stubbed `header`/`info`/`warn`, sets `CONSTITUTION_JEV_HOOK=on`, `JEV_HOOK_TIMEOUT=2` and a
bootstrap stub that changes the terminal mode and sits, and runs it in a pty under both implementations (budget 4 s
for the run plus the retry, margin 5 s, cap 30 s). Not live-tested: `multitrack_balance.sh` (its two tests exit 77,
`topology_unsupported`, on this host), the opt-in `ls_ctl` branch; both are covered by the census and the mutants
only.

## 2. F-2: pty driver session race

`pty.fork` makes the child a session leader, so the session id is the child's pid; the old driver polled
`/proc/<pid>/stat` for the sid and could read it before `setsid` had run. RED (`tools/f2_red.sh.txt`, original
driver, 60 runs of the driver needle that leaves one process behind): `left=0` in 8 of 60 (`runs/f2_red_orig.tsv`).
GREEN (driver with `sid = pid` and an unconditional cleanup): `left=1` in 60 of 60 (`runs/f2_green_new.tsv`).

## 3. F-3: an ignore after the timeout is not credited

The census credits an ignore only when it precedes the timeout in the same scope; the RV-M2 shape
(`{ timeout 20 claude-list-accounts ...; trap '' TTIN TTOU; }`) is a control needle (`lib/b.sh` third site `no`) and
the mutant HK-M3 applies the same shape to the hook.

## 4. F-4, F-5 (nits)

- F-4: the `hi_gx` comment (both files) now reads: GNU and uutils timeout reset the signals for git (measured);
  busybox timeout passes the ignore on to git, but it makes no new process group, so none is sent.
- F-5: `hi_version_of` runs the probe in a `{ trap '' TTIN TTOU; timeout 5 ...; }` group inside `cd /`.

## 5. Results (this session)

| Run | Result |
|---|---|
| `tests/install/test_timeout_tty.sh` on `b60cda35`, 3 runs | `timeout_tty: PASS 25 FAIL 0`, `rc=0` in each (`runs/timeout_tty_GREEN_run{1,2,3}.txt`); T8 ok for GNU and uutils in each |
| `test_python_isolation` | 12 / 0 |
| `test_shell_state_patsub` | 14 / 0 |
| `test_unit` | 222 / 0 |
| `test_sigpipe` | 67 / 0 |
| `cm_installer_no_push_no_force` + mutation test | PASS, meta 222 |
| `cm_installer_script_modes`, `cm_installer_snippets_consistent`, `cm_installer_truncation_safe` + their mutation tests | PASS |
| `verify-manifest` | `MANIFEST-MISMATCH`, `rc=3`: the same three `scripts/sonarqube/tests/test_registry_login*` rows as on the base; no new row (only an existing test changed) |
| `tests/jev/test_review_fixes_r3.sh`, `_r4.sh` on `b60cda35` | rc 0 (they failed on `86fdc766`, where `lib_decide` used `exec`; fixed in `b60cda35`) |

`regress/required/rc.tsv` lists the required set. All per-run logs are under `runs/` and `regress/`.

**Regression set** (46 tests whose files touch a changed script, `regress/head_86fdc766/rc.tsv`, then the two jev
tests again on `b60cda35`). Non-zero results and their causes:

| Test | Head | Base `e1bf1bad` | Cause |
|---|---|---|---|
| `multitrack/test_multitrack_sessions_balance_autoselect.sh`, `test_multitrack_supervisor_wiring.sh` | 77 | not run | honest SKIP, `topology_unsupported` |
| `gates/cm_gate_env_reads_allowlisted_mutation_test.sh` | 124 (cut at 3600 s after 32 ok and the same two FAILs) | 1, the same two FAILs (`golden real tree`, `baseline closure test unmutated`) | pre-existing: the gate itself gives an identical output on base and head (`regress/envreads_gate_red.txt`, `regress/envreads_gate_repo.txt`: 2 stale allowlist lines for `cm_installer_no_push_no_force.sh`, `uncovered=0`) |
| `hooks/test_label_sync_hooks.sh` | 1 | 0 once, then 1 and 1 in paired runs | load-dependent: `latency prompt` CPU median 153 to 155 ms against a 150 ms bound, the same on base and head (`regress/ls_pair{1,2}_{base,head}.log`); the changed `ls_ctl` branch is opt-in and is not run by the test |

## 6. Mutants

Runner `tools/r2_mutants.py.txt` on `b60cda35`: each mutant is a detached worktree with exact replacements, the
named test run there, KILLED when it exits non-zero; a control run of the unmutated tree must pass first. Results
`mutants/mutants_r2.tsv`, one log per mutant in `mutants/`. Control: PASS rc=0 (137 s). 26 of 26 mutants KILLED.

| Mutant | Change | Killed by |
|---|---|---|
| TT-M1 | `hi_gx` ignore removed (both files) | census + T1, T2, T7 [uutils] CAPPED |
| TT-M2b | `hi_version_of` ignore removed (group form) | census + T3 [uutils] CAPPED |
| TT-M3, TT-M4 | `hi_detect_agents` ignore removed (each probe) | census + T4 / T5 [uutils] CAPPED |
| TT-M5 | `hi_run_agent` ignore removed | exact assertion + T6 [uutils] CAPPED |
| RV-M1 | `hi_gx` ignores TTIN only | census + T1 [uutils] CAPPED |
| RV-M2 | ignore moved after the timeout (claude-list-accounts) | census (F-3) + T4 [uutils] CAPPED |
| RV-M3 | stale PROGS entry in the no-push gate | the gate (rc 1) |
| RV-M4 | `install_action_prefix` `python3 -P` instead of `-I` | `test_python_isolation` |
| RV-M5 | `hi_run_agent` restores TTOU | exact assertion + T6 [uutils] CAPPED |
| HK-M1, HK-M2 | hook: ignore removed from the run / the `--defer` retry | census + T8 [uutils] CAPPED |
| HK-M3 | hook: ignore placed after the timeout (RV-M2 shape) | census + T8 [uutils] CAPPED |
| BS-M1, BS-M2, LD-M1, LK-M1, LS-M1, SL-M1, MC-M1, JD-M1 | the ignore removed at bootstrap `run_bounded`, `run_gate`, `lib_decide`, `lib_keys`, `ls_ctl`, statusline, `multitrack_cwd_hook`, `cm_jev_detection` | census only (no live case for these sites) |
| MB-M1 | `multitrack_balance` ignore removed | exact assertion only |
| CS-M1 | census credits an ignore anywhere on the line (F-3 undone) | control needles, BLIND rc 2 |
| CS-M2 | closure stops resolving `scripts/x/$v.sh` | control needles, BLIND rc 2 |
| CS-M3 | census back to the six fixed files | control needles, BLIND rc 2 |

Honest limit: nine of the fixed sites are guarded by the static census and its exact assertions, not by a live
terminal run; only the hook (T8) and the round-1 install sites have live pty cases.

## 7. Corrections to the round-1 evidence (`docs/qa/installer_followups_2026_11_14/README.md`, left unchanged because its SHA256SUMS covers it)

- Scope: "The six install scripts have 8 `timeout` sites" was true of the six scripts, but the install and update
  path reaches more files (the post-update hook, the Jev bootstrap and their libraries). On the base the derived
  census finds 18 sites (`census/timeout_site_census_base_e1bf1bad.tsv`): the 8 of round 1 and 10 more, all 10
  without the ignore (the hook, `run_bounded`, `run_gate`, `jev_effective_mode`, `_jev_key_value`, `blind_or_note`,
  `ls_ctl`, the statusline, the multitrack balance probe, `_cwh_owner_busy`). After the fix it finds 19 (the hook
  now has two runs). Section 1 above replaces that census.
- `hi_lock_pid` / `up_lock_pid` "reads a regular, non-symlink file (checked before)": true in normal operation only;
  the check and the open are separate steps (review F-6, follow-up FU-1).
- Section 1 "Both reset the two signals to the default for the program they run": GNU and uutils only; busybox
  passes the ignore on (it makes no new process group, so no signal is sent) (review F-4).

## 8. Census boundary (§11.4.6)

The closure follows file names and `scripts/...` paths and resolves `$v.sh` only from literal `for` lists. It does
not see a timeout inside a binary or a submodule installer that is not checked out here (llmctl, claude_toolkit,
labelctl), a file named only at run time, or a timeout called through `eval`. Recorded as follow-up FU-4.

## 9. Follow-up drafts (not filed)

`followup_drafts.md`: FU-1 lock_pid check-then-open race (F-6), FU-2 `python3` without `-I` (1972 sites,
repository-wide), FU-3 no-push gate reports SOURCE-FAILED on a relative `--file` path, FU-4 census boundary.

## 10. Files

`runs/` (RED, GREEN x3, F-2 tables, verify-manifest), `census/`, `regress/`, `mutants/`, `tools/` (the census, the
mutant runner, the regression runner and the F-2 drivers, as `.txt`), `followup_drafts.md`, `SHA256SUMS`
(`sha256sum -c SHA256SUMS` from this directory).
