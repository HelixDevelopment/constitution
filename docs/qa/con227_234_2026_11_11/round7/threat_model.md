# CON-234 class, round 7 (structural): child environments built positively

| Field | Value |
|---|---|
| Item | CON-234 (credential text in external-command output and process state), with CON-227..233 touched; vehicle `vehicle/fix227` |
| Round | 7. Operator decision 2026-11-11: run review rounds until GO; every round past 5 is structural (§11.4.276(E)(3)), fresh fixer instance, class-exhaustive (§11.4.276(C)) |
| Review answered | `scratchpad/review_fix227_r6.md` (round-6 head `2765038f`, NO-GO): L1..L7 and the surviving mutants Z8, Z9 |
| Author | Claude Opus 5.5 subagent (fixer). The reasoning effort cannot be set or read on this dispatch path (§11.4.231(F.2)); none is claimed |
| RED / GREEN | `red_*.txt` (round-6 scripts, or the round-6 suite or harness, with the round-7 tests) and `green_*.txt` (round-7 head), beside this file |
| Earlier rounds | `../round6/threat_model.md` stays the record of the per-channel census; this file adds the environment channel design that replaces `rc_env_lockdown` as the only control |

## 1. What the round-6 review found

Round 6 turned the environment channel from "everything the caller exported" into an allow-list:
`rc_env_lockdown` un-exports every variable whose name is not on a fixed list. The review showed two
ways around it, both on the same channel:

* **L1, inherited allexport.** `SHELLOPTS=allexport` in the caller's environment (or `bash -a script`)
  makes bash export every variable the script ASSIGNS after the lockdown. The publisher assigns its token
  to `_rpg_tok`, so the token was exported to every later child (curl, jq, grep). Measured on the round-6
  tag script by case C48 (`red_tag_and_release.txt`): under `bash -a` git received the script's own
  shell variables `u`, `NOTES`, `FAILS`, `spec`.
* **L2, names that are not shell identifiers.** `env 'A.TOKEN=…' 'BAD-NAME=…' 'npm_config_//h/:_authToken=…'`
  puts entries in the process environment that bash keeps and passes to every child, but never lists in
  `compgen -e` and cannot `export -n`. A lockdown that works by NAME cannot remove them. Measured on all
  three round-6 scripts (C48, publisher case 29, derive L2): the entries reached grep, mktemp and git.

The class question (§11.4.276(C)) is therefore not "which names does the lockdown know" but "is a
child's environment ever built from the caller's environment at all". Any subtractive control (unset
what is known to be bad, un-export what is not allowed) fails on an entry it cannot name or on an
option that re-exports later. So round 7 builds it **positively**.

## 2. Design: rc_env_clean

Each release script calls `rc_env_clean READS "$@"` as its first action (after loading
`redact_cut.sh` with a parameter expansion only; the census lint refuses any external command before
it). On the first entry the function:

1. checks READS (the caller-named variables the script itself reads, e.g. the token variable of the
   publisher): each must be a shell identifier and not a name bash gives a meaning of its own
   (`BASH*`, `SHELLOPTS`, `ENV`, `IFS`, `PS0..4`, `POSIXLY_CORRECT`, `CDPATH`, `GLOBIGNORE`,
   `EXECIGNORE`, `FUNCNEST`, `TMOUT`, `HISTFILE`, `PROMPT_COMMAND`, `_RC_*`, `_rc_*`); else status 2
   (the publisher prints "bash gives a meaning of its own: refusing" and exits 2);
2. runs `rc_env_lockdown` (the round-6 allow-list), then
   `exec -c -a rc-clean-env "$BASH" "$0" "$@" 9< <(_rc_env_dump READS)`.
   `exec -c` starts bash with an EMPTY environment: no entry of the caller reaches the new process, also
   no non-identifier entry and no `SHELLOPTS`/`BASHOPTS`/`BASH_ENV`; the command line carries no option,
   so a `bash -a` or `bash -x` of the caller is gone too. The dump writes NUL-separated records on fd 9:
   `e NAME VALUE` for each allow-listed exported variable, `s NAME VALUE` for READS names (shell
   variables, never exported) and for `RELEASE_ENV_KEEP`;
3. in the new process (argv0 `rc-clean-env` AND an empty `/proc/$$/environ`: the marker alone is not
   trusted, a caller can set argv0), reads fd 9, sets each record whose name is an identifier and not
   reserved (`e` exported, `s` only for READS names), closes fd 9 and runs `rc_env_lockdown` again.

Status 3 is returned when `/proc/$$` cannot be read (the clean state cannot be shown: the scripts exit
3, never run on a guess, §11.4.201(4)); status 4 when there is no readable script file or the exec
failed. Which options are reset: every shell option and every `shopt` of the caller, because the new
bash starts from its defaults with no `SHELLOPTS`/`BASHOPTS` in its environment and no option on its
command line; only `execfail` is set by the function itself, before the exec, in the old process.

What it does not change: the values on the allow-list (PATH, HOME, GIT_SSH_COMMAND, ...) still come from
the caller, as in round 6; a caller who controls them controls the script anyway. A caller who can set
`BASH_ENV` before the FIRST start is out of scope as well (bash runs it before line 1 of a non-interactive
script; the release scripts are started by the operator).

## 3. L3..L7

* **L3 (Z8, Z9).** Case C49 of the tag suite runs the script with a git double that ignores TERM and
  `RELEASE_NET_TIMEOUT=2`: it must end in under 30 s, at least 10 s (the KILL after `-k 10`, control),
  report "git exit 137, reason class: timeout", and leave no process. Z8 (no `-k 10`) and Z9 (137 not in
  the timeout class) are killed by it; W10 (`-k 600`) as well.
* **L4 (ignored SIGHUP).** A signal ignored when bash starts cannot be trapped. The suites read bit 0 of
  `SigIgn` in `/proc/$$/status`; with HUP ignored each HUP case prints `SKIP <case> HUP: <reason>` and the
  suite prints a `SKIPPED` line; `hup_control` in `env_allow.sh` is the control (a child with HUP ignored
  must be detected, one without must not). The mutation harness treats a survivor whose suite skipped a
  HUP case as INCONCLUSIVE and exits 3, never as killed. RED: `red_l4_hup_ignored.txt` (round-6 derive
  suite under `trap '' HUP`: `FAIL X10 HUP: rc 0, want 129`).
* **L5 (trap handler returns).** `trap cleanup EXIT INT TERM` runs cleanup on TERM and returns, so the
  suite ran on. Every release suite now exits from its handler (`trap 'exit 143' TERM`, cleanup in the
  EXIT trap); the harness runs each suite in the background and `wait`s (bash runs a trap only after a
  FOREGROUND child ends), sends TERM to its own child, then KILL after 20 s. Census part 4 tests it. RED:
  `red_l5_harness_term.txt` (round-6 harness: still running 30 s after TERM, 8 processes left). The same
  shape is in 35 scripts outside `tests/release`: out of scope, tracked as **CON-311**.
* **L6.** The CHANGELOG round-3..5 bullets now name CON-300..CON-307 with the earlier ids in parentheses.
* **L7.** A remote URL with an ssh user name, or with a token in its query string, is not refused: tracked
  as **CON-310** (a decision per shape; no code change in this round).

## 4. Instruments and their needles

* `tests/release/env_census.py`: real recorder processes on PATH in front of each command the channel
  table names; each logs its own `/proc/$$/environ` (every entry, also non-identifier names; `env` and
  `compgen -e` cannot list those, which is why the round-6 recorders were blind to L2), its parent's
  command line, and whether fd 9 is open; `check` prints names only, never a value. Control needle: a
  minimum number of checked records per run (`--min`), and a dirty run of the recorder itself.
* `tests/release/net_probe.py` keys its samples by (pid, argv), so the re-executed process is a second
  sample; C43 checks that the `rc-clean-env` sample was taken and that its environment is empty.
* Publisher case 24 (xtrace) was blind: `SHELLOPTS=xtrace cmd` as a prefix assignment does not set the
  option (SHELLOPTS is read-only in bash), so the case never traced. It now uses `env SHELLOPTS=xtrace`
  and has a control (`env SHELLOPTS=xtrace bash -c 'true; true'` must trace).
* The channel-census lint knows `rc_env_clean` as the boundary (an external command before it is a
  finding) and the re-exec as an invocation (`redact_cut.sh bash`, env `empty`, stdin `state-pipe`).

## 5. Known limits (not claimed closed)

* The runtime census covers the commands the table names and the cases the suites drive; a command on a
  path no suite reaches is covered only by the static lint (CON-308 stays open).
* The fd-9 records of a re-executed process come from its own previous image; a caller that starts the
  script with the marker argv0, an empty environment and its own fd 9 can set allow-listed values and
  READS values. That caller controls the script's environment anyway; no name outside the allow-list
  can be exported this way (K6 tests).
* CON-309 (proxy variables), CON-310 (ssh user, URL query), CON-311 (trap handlers outside the release
  tooling) are open.
