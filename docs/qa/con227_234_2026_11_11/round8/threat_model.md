# CON-234 class, round 8 (structural): exact allow-list with value checks, closed descriptors, no re-exec loop

| Field | Value |
|---|---|
| Item | CON-234 (credential text in external-command output and process state), with CON-227..233 touched; vehicle `vehicle/fix227-r8` |
| Round | 8. Operator decision 2026-11-11: review rounds run until GO; every round past 5 is structural (§11.4.276(E)(3)), fresh fixer instance, class-exhaustive (§11.4.276(C)) |
| Review answered | `scratchpad/review_fix227_r7.md` (round-7 head `4dd5235e`, NO-GO): N1..N8 and the surviving mutant A5 |
| Author | Claude Opus 5.5 subagent (fixer). The reasoning effort cannot be set or read on this dispatch path (§11.4.231(F.2)); none is claimed |
| RED / GREEN | `red_*.txt` (round-7 scripts and library with the round-8 suites) and `green_*.txt` (round-8 head), beside this file |
| Earlier rounds | `../round7/threat_model.md` stays the record of the positive environment design (`rc_env_clean`); this file records what round 8 changes in it |

## 1. What the round-7 review found

| Id | Finding | Round-8 answer |
|---|---|---|
| N1 | `rc_env_lockdown` kept every `LC_*` name, so any caller variable named `LC_<anything>` reached every child, and ssh forwards `LC_*` off the host (`SendEnv LANG LC_* COLORTERM NO_COLOR`, `/etc/ssh/ssh_config:50`) | the 13 locale category names are listed exactly; every allow-listed value is checked against a shape for its class (`_rc_env_shape_ok`); the whole list is enumerated as a class by an instrument (section 2) |
| N2 | a marked process that is not clean re-executes again, without end | loop guard: argv[0] is read again after the state check; a process that already carries the marker returns status 4 |
| N3 | fd 63 (the process-substitution pipe of the exec) and every descriptor the caller passed reach every child | `_rc_env_closefds`: in the clean process every descriptor above 2 except fd 9 that has no close-on-exec flag is closed before the records are read; the recorders now list inherited descriptors |
| N4 | a script that is sourced by another one re-executes `$0`, the sourcing script | `BASH_SOURCE` check: the caller of `rc_env_clean` must be `$0` at the top of the source stack, otherwise status 4 |
| N5 | `--only <unknown>` in the harness ran nothing and exited 0 | exit 2 with `FAIL --only NAME: no mutant has that name` |
| N6 | a suite exited 0 when a case was skipped | `suite_exit` (`tests/release/env_allow.sh`): 77 on a skipped case unless `RELEASE_TESTS_ALLOW_SKIP=1`; the harness sets it and judges skips itself. The one expected skip (render suite, real facts) is commented as such |
| N7 | `bash -x` with a caller `PS4` naming a variable prints it on the first process's trace lines | documented limit (section 4) |
| N3 (class, found in round 8) | the new descriptor census found the same shape inside the scripts: a `while read ... done < <(cmd)` loop leaves the process-substitution pipe (fd 63, no close-on-exec) open in every command its body runs (derive: `grep`, `sed`, `git` in the two loops; tag: the remote-URL loop, whose `abort` runs the EXIT trap) | the three loops read from a here-string of the captured output instead (`done <<<"$rows"`); an empty line is skipped. First GREEN derive run before this fix: `FAIL L2 shellopts/dasha: grep: file descriptor 63 is inherited` (`green_derive_release_facts_pre_n3class.txt`) |
| N8 | `rc_url_has_userinfo '  https://u:p@h/r'` (leading blanks) returns 1 | CON-310 scope (section 5); no code change |

## 2. The allow-list as a class (N1)

Instrument: `python3 tests/release/env_census.py classes scripts/release/redact_cut.sh` (output in
`green_classes.txt`). It extracts the list from `rc_env_lockdown` itself (a name without a class in the
instrument is BLIND, a name prefix is a FINDING), asks ssh which names it sends, and runs the library's own
`_rc_env_shape_ok` on, for every name: a good value of its class (must be kept), a URL with user information,
a token-shaped value and a value with a newline (each must be dropped), and a value that passes those common
checks but not the class's own shape (must be dropped; not applicable to `PATH` and `GIT_SSH_COMMAND`, see
section 4). Control needles: ssh must show a `SendEnv` pattern given on its own command line (`ZZNEEDLE8`) and
must not match a fabricated name (`ZZNOTSENT8`); a name not on the list (`ZZUNLISTED8`) must be dropped (fail
closed). On the round-7 library the instrument reports `FINDING: the allow-list holds a name prefix` (rc 1).

| Class | Names | Shape kept | ssh sends it |
|---|---|---|---|
| locale | `LANG` and the 13 `LC_*` category names | `[A-Za-z0-9_.@-]`, at most 64 | yes (`LANG`, `LC_*`) |
| locale-list | `LANGUAGE` | `[A-Za-z0-9_.@:-]`, at most 256 | no |
| tz | `TZ` | `:` optional, then `[A-Za-z0-9/_.,:+<>-]`, at most 128 | no |
| term | `TERM` | `[A-Za-z0-9._+-]`, at most 64 | only with a pty request (not a `SendEnv` name) |
| account | `USER`, `LOGNAME` | `[A-Za-z0-9._@-]`, at most 64 | no |
| path | `HOME PWD SHELL TMPDIR XDG_*` (5) `GNUPGHOME GH_CONFIG_DIR GLAB_CONFIG_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM` | empty or absolute | no |
| program | `GIT_SSH GIT_ASKPASS SSH_ASKPASS` | empty, absolute, or one word | no |
| socket | `SSH_AUTH_SOCK` | empty, or an absolute path that is a socket now | no |
| dbus | `DBUS_SESSION_BUS_ADDRESS` | `[A-Za-z0-9/_.,=:;%-]`, at most 512 | no |
| enum / flag | `GIT_SSH_VARIANT` / `GIT_CONFIG_NOSYSTEM` | the git values / up to 8 alphanumerics | no |
| host | `GH_HOST`, `GITLAB_HOST` | a host name, optional `http(s)://`, port and `/`; no user information | no |
| path-list / command | `PATH` / `GIT_SSH_COMMAND` | common checks only | no |

Common checks for every name: at most 4096 bytes, no control character, no `scheme://...@`, no GitHub or
GitLab token shape (`gh[pousr]_`, `github_pat_`, `glpat-`). A value that fails is un-exported, so no child
receives it (the name is not exported with a different value).

Names that are NOT on the list, measured as read by the tools the release scripts call (string search in the
binaries, positive needles found, negative needle `ZZNOTANENV8` 0 hits): `gh` reads `GH_TOKEN`, `NO_COLOR`,
`COLORTERM`; `glab` (`/snap/glab/current/glab`; the `/snap/bin/glab` wrapper is blind to this search) reads
`GITLAB_TOKEN`, `NO_COLOR`; libcurl reads `http_proxy`, `HTTPS_PROXY`, `SSLKEYLOGFILE`; git reads `GIT_TRACE`.
None of them is kept, so the token variables, the proxy variables (CON-309) and the key-log file never reach a
child. `COLORTERM` and `NO_COLOR` are dropped too (they change colours only; dropping them is safe).

## 3. Tests that drive it

* `test_redact_cut.sh` K8: N3 (a descriptor 7 passed by the caller is not seen by a child; fd census with a
  control needle), N2 (a stubbed state that never becomes clean returns status 4 at once instead of looping
  under `timeout`), N4 (a wrapper that sources the script runs once and gets status 4; a direct run is the
  control), N1 (lockdown unit and the same through the re-execution: kept `LC_TIME`, `LANG`, `TZ`,
  `GITLAB_HOST`; dropped `LC_ZZTOKEN`, a URL in `LC_MESSAGES`, a blank-separated word in `LC_PAPER`, a user name
  in `GH_HOST`, a `SSH_AUTH_SOCK` that is not a socket; and the class table above with 0 findings).
* `ENV_DIRTY` (all release suites) carries `LC_ZZTOKEN` and a URL-shaped `LC_MESSAGES` with fabricated markers;
  the recorders' `check` no longer accepts a prefix (`--allow-prefix` is refused with exit 2) and reports any
  inherited descriptor not named with `--allow-fd` (the scripts' own fds 3 and 4).
* `test_channel_census.sh`: N5 (`--only ZZNOSUCH8` exits 2; `--only Z1` is the control) and the N6 `suite_exit`
  table.

## 4. Known limits (not claimed closed)

* N7: under `bash -x` the FIRST process traces with the caller's `PS4` until the exec; a `PS4` that names a
  variable prints it there. The caller chose both (same class as `BASH_ENV`); the re-executed process has
  xtrace off and no `PS4`.
* `PATH` and `GIT_SSH_COMMAND` have no shape beyond the common checks: a bare secret word placed in them by the
  caller is not recognised. A bare secret word in any value cannot be told from a locale or path value; the
  protection against it is the exact list of names.
* The class table checks the shapes the library applies; whether a remote ssh server accepts a forwarded
  `LANG`/`LC_*` value is UNCONFIRMED (the client sends it; the value is now locale-shaped).
* `_rc_env_closefds` reads `/proc/$$/fdinfo` (Linux); without it nothing is closed, but the state check already
  refuses to run without `/proc` (status 3).

## 5. CON-310 scope addition (N8) — for the lander

No tracker item was changed by this round (the database is not edited by hand). The lander should add to
CON-310 (ssh user, URL query) the shape found by the review: a remote URL with LEADING BLANKS,
`'  https://u:p@h/r'`, is not recognised by `rc_url_has_userinfo` (returns 1); git treats it as scp-like, so the
`u:p@h/r` part ends up in ssh's argv. Suggested engine command (run by the lander, not here):
`workable-items update CON-310` with the description amended by that sentence, and the acceptance criterion
"a URL with leading or trailing blanks is trimmed before the user-information check, or refused".

## 6. Equivalent mutants (justified one by one)

* **A10** (the first `rc_env_lockdown` before the exec removed): the dump then carries every exported caller
  variable on fd 9, but the clean process runs `rc_env_lockdown` after the restore (A11, which removes that
  one, is killed); every name off the list and every badly shaped value is un-exported there, so no child
  receives them. Defence in depth only.
* **A14** (`${!v+x}` to `${!v:-}` in the READS dump): an empty READS variable is not carried; the only READS
  values are the token variable and `RELEASE_NET_TIMEOUT`, and an empty token takes the same
  SKIPPED-NO-TOKEN path as an unset one, an empty timeout the same default as an unset one.
* X12 and Z6 stay as recorded in rounds 6 and 7.
