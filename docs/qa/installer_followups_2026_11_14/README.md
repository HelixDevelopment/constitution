# Installer follow-ups (2026-11-14): evidence

| Field | Value |
|---|---|
| Status | PROVISIONAL (independent review pending) |
| Roadmap item | CON-PENDING-installer-followups |
| Base | bundle `installer_sigpipe_r2.bundle`, sha256 `1030dba6485c440cd57a9d3373a7c532d2f066726080d965ffdabce937a8f95b`, head `2e397cba` (`refs/heads/vehicle/installer-sigpipe-r2`), requires `bd0036bd` |
| Commits | `bf77ff69` (the fixes and three new tests), `43509191` and `d9dfb884` (two defects in the new timeout test, found by its own runs) |
| Host | bash 5.3.9, git 2.53.0, GNU timeout as `/usr/bin/gnutimeout`, uutils coreutils 0.10.0 as `/usr/bin/timeout`, procps-ng 4.0.4; load average 27 to 51 during the runs |

All runs: `systemd-run --user --scope -p TasksMax=2000 nice -n 10`, at most two at a time. Effort of the agent that
did the work: UNKNOWN.

## 1. uutils `timeout` hangs when the command touches the terminal

**Root cause (measured).** Without `--foreground`, `timeout` puts itself and its command in a new process group,
which is a background group of the terminal. When the command touches the terminal (`tcsetattr`, a read, a write
with `tostop`), the kernel sends SIGTTOU or SIGTTIN to the whole group. GNU timeout ignores both signals for itself,
so its timer still fires. uutils timeout 0.10.0 does not ignore them, so it is stopped together with the command
(`ps` state `T` for timeout, sh and stty) and the limit never fires, also with `--kill-after`
(`timeout_matrix_run1.tsv`). This is the same mechanism as CON-112.

Ignoring the two signals before `timeout` starts (SIG_IGN is inherited across exec) bounds both implementations.
Both reset the two signals to the default for the program they run (`timeout_child_sigign_reset.txt`, with a control
that shows the bits without timeout in between), so git and the agents behave as before: a program that touches the
terminal still stops and is killed at the limit. `--foreground` would also bound uutils, but it changes which
processes the signal reaches, so it was not used.

**Census.** The six install scripts have 8 `timeout` sites (`census/timeout_site_census_six_after.tsv`, and the
census inside `tests/install/test_timeout_tty.sh`, which fails when a new site is not classified):

| Site | Change |
|---|---|
| `hi_gx` (installer and updater, identical block) | ignore on the timeout branch only |
| `hi_version_of` | ignore in the command substitution |
| `hi_detect_agents`, `claude-list-accounts` and `claude-providers list` | ignore in a `{ }` group before `timeout` |
| `hi_run_agent` | ignore in the background job that runs the `timeout` array |
| `hi_lock_pid`, `up_lock_pid` | unchanged: `timeout 5 head` reads a regular, non-symlink file (checked before) |

**Test.** `tests/install/test_timeout_tty.sh` runs each case in a new pseudo-terminal session (a Python driver that
never signals its own session), with stubs that change the terminal mode (or read it) and then sit. A case passes
only with the expected status, after the full limit (the stub really sat), within the limit plus a margin, and with
no process left in the session. Control needles: a direct uutils `timeout` of the stub must hang (else BLIND); the
driver must count a process left in the session; the census must tell an ignored site from a bare one.

| Run | Result |
|---|---|
| before the fix (`runs/timeout_tty_RED_before_fix.txt`) | GNU 7 of 7 ok; uutils T1 to T7 all CAPPED: FAIL 7 |
| after the fix, three runs (`runs/final_timeout_tty_run1..3.txt`, on `d9dfb884`) | PASS 22 FAIL 0, three times |

Mutants (`mutants/`, on `d9dfb884`; the control run on the unmutated tree passes first): the ignore removed from
`hi_gx` (both files), `hi_version_of`, each `hi_detect_agents` site and `hi_run_agent`. All five are killed, each by
the census AND by the uutils behaviour case of that site.

Two defects of the new test, found by its own runs and fixed in their own commits:

- `43509191`: one of three runs on `bf77ff69` failed T3 [gnu] with `left=1`, status and time correct
  (`runs/final_bf77ff69_timeout_tty_run2_FAIL_T3_left1.txt`). The driver counted the session's members the moment
  the shell returned. UNREPRODUCED in 12 targeted runs; the likely mechanism (the stub's `stty`, orphaned when its
  `sh` is reaped first, still exiting) is UNCONFIRMED. The driver now waits up to 3 s for the session to empty.
  Also, mutant TT-M4 was killed only by its behaviour case: the census credited an ignore inside the previous
  `{ }` group of the same function. Only a standalone `trap '' TTIN TTOU` now covers later lines (new needle).
- `d9dfb884`: the new leftover needle went BLIND on its first run (`invalid/fu_mutants_tt_43509191.log`). Its
  background `sleep` got SIGHUP when the session leader exited, and the driver read the terminal until EOF, so a
  leftover holding the terminal open delayed the case instead of being counted. The read is now bounded (2 s),
  and the needle ignores SIGHUP.

## 2. `python3 -c` without `-I`

`python3 -c PROGRAM` puts the current directory first on `sys.path` and honours `PYTHONPATH`, so a `json.py` in
the directory the operator runs the script from would run on `import json`. In the six install scripts, the only
site without `-I` was the merge in `install_action_prefix.sh`; it now runs with `-I`. Repository-wide there are 1972
`python3` invocations without `-I` (`census/py_isolation_census_repo.tsv`); they are out of scope here and only counted.

`tests/install/test_python_isolation.sh`: the static census of the six scripts (control needles), and the real
script run with `jq` hidden from `PATH` and a `json.py` planted in the current directory and on `PYTHONPATH`
(controls: the plant is imported by a plain `python3 -c`, and `jq` is really absent). Before: PASS 5 FAIL 7
(`runs/python_isolation_RED_before_fix.txt`); after: PASS 12 FAIL 0 (`runs/final_test_python_isolation.txt`). Mutant
PY-M1 (`-I` removed) is killed (`mutants/fu_mutants.log`).

## 3. `patsub_replacement` comment

The comments said `hi_reset_shell_state` returns every option to bash's defaults. It turns `patsub_replacement`
off, which is not bash 5.2's default (on), so `&` in a `${var//pat/rep}` replacement stays literal. The code is
unchanged; the comments in the installer, the updater and the no-push gate now name the exception.
`tests/install/test_shell_state_patsub.sh` checks the behaviour in all four copies of the function and that every
comment about the reset and defaults names the exception. Before: PASS 13 FAIL 1 (only the comment check failed);
after: PASS 14 FAIL 0. Mutants PS-M1 (comment back) and PS-M2 (`patsub_replacement` dropped from the reset) are
killed.

## 4. Stale entries in the no-push gate's allow lists

The gate already reported an `EXEMPT` entry that no scanned line uses. Census of the other lists: `PROGS`,
`EXT_EXACT` (it includes the pinned shopt lines), `GX_EXACT` and `SANCTIONED_FILE_CMDS` were checked by membership
only, so an entry could outlive its use. `SANCTIONED_WRITES`, `SANCTIONED_REDIRS`, `SWITCH_TOKENS` and `VAR_PINS` are
compared as exact counts, so a missing use already fails. The four membership lists now get the same stale check; the
real pair still passes (no stale entry exists today). Mutants ST-1 to ST-4 remove the only use of one entry each:
they passed the gate before (`runs/st_red_before_fix.txt`, `runs/st4_red_before_fix.txt`) and fail it after; they are
part of `cm_installer_no_push_no_force_mutation_test.sh` (`runs/gate_mutation_test_after.txt`: 222 cases, every mutant
killed). Removing each of the four stale lines from the gate is caught by its ST case (ST-M1 to ST-M4).

## 5. test_round8 hardening (a5ee2ab4): review

Checked by measurement:

- **The process group.** Both GNU and uutils `timeout` create a process group of their own inside the killed
  session (`r8/timeout_own_group_gnu_vs_uutils.txt`). The commit text says uutils makes one; GNU does too.
  `drain_session` waits on the session, so it covers both. The SIGTTIN/SIGTTOU ignore added here does not change
  this.
- **The git window.** git 2.53.0 opens `index.lock` (`O_CREAT|O_EXCL`) before its first `rt_sigaction` for SIGINT
  and SIGTERM (`r8/git_index_lock_window_strace.txt`), so a signal in that window leaves a lock no process holds,
  as the commit says.
- **Needles and runs.** `tr8_needles.sh` passes 5 of 5, three times (`r8/tr8_needles_run1..3.txt`).
  `tests/install/test_round8.sh` passes 91 of 91, three times, in 539 to 625 s (`r8/test_round8_run1..3.txt`).
  The 12 own mutants of the round-2 evidence were not run again.
- **Open points (not changed).** The stale-lock branch looks at every `index.lock` under `.git`, including
  `.git/modules/*`; whether the re-run then always fails with `index.lock` in its output is UNCONFIRMED. The
  `-lname` match takes the sandbox path as a glob pattern; a temporary directory with `[`, `*` or `?` in its path
  would make a held lock read as stale. Neither was seen.
- **Signals.** A signal to the installer's group does not reach a `timeout`'d fetch (both implementations make a
  new group); this is unchanged by the fix.

## 6. Other checks

| Check | Result |
|---|---|
| `test_unit.sh` (blocks identical in installer and updater) | PASS 222 FAIL 0 (`runs/final_test_unit.txt`) |
| `test_sigpipe.sh` | PASS 67 FAIL 0 (`runs/final_test_sigpipe.txt`) |
| `cm_installer_no_push_no_force.sh`, `_script_modes`, `_snippets_consistent`, `_truncation_safe` | PASS |
| `run_full_suite.sh --verify-manifest` | the same 3 problems as the base (three `scripts/sonarqube/tests` files with no manifest row, from the base commits); the new tests have rows (`runs/verify_manifest_base_2e397cba.txt`, `runs/verify_manifest_after_sync.txt`) |

The four final test runs and the gate checks ran on `bf77ff69`; the two later commits change only
`tests/install/test_timeout_tty.sh`.

## 7. Notes

- On this host `grep` is ugrep 7.8.4, which treats `$` in the middle of a pattern as an anchor. The censuses use
  Python or `grep -F`.
- The no-push gate fails with SOURCE-FAILED when it is given relative `--file` paths. Seen, not fixed.
- One probe (`invalid/timeout_matrix_probe_v1_INVALID_own_session_kill.tsv`) read the child's session before the
  child had called `setsid` and signalled the probe's own session. It killed the probe itself; afterwards the shell
  worked and no stray process was found. The probes now require `getsid(pid) == pid` and refuse their own session.
- The first test run (`invalid/timeout_tty_probe_v1_INVALID_bodies_never_ran.txt`) passed falsely: the case bodies
  never ran. The cases now require the expected status and the full wait.
- The full per-mutant logs of the first mutant run (on `bf77ff69`) were deleted with its work directory; its summary
  is kept (`mutants/fu_mutants.log`), and the timeout mutants were run again on `d9dfb884` with full logs.
- `tools/` holds the probes and runners (stored as `.txt`).
