# shellcheck shell=bash disable=SC2034   # sourced; the variables are read by the suites that source it
# tests/release/env_allow.sh — sourced by the release suites (round 7): the names a child of a release script may
# have in its environment, as the test's own copy of the specification (never read from the library under test,
# so a mutant that widens the library's list is seen). ENV_ALLOW holds the allow-list of rc_env_clean (paths,
# sockets, locale; round 8, N1: the thirteen locale category names exactly, never a prefix: ssh sends LC_* to
# the remote server), the names rc_git_env and the scripts set themselves (LC_ALL, GIT_TRACE_REDACT,
# GIT_TERMINAL_PROMPT, GIT_TRACE2*, TAG for awk), and the three names bash adds to every child it starts (PWD, SHLVL,
# _; OLDPWD after a cd). A suite adds the names of its own RELEASE_ENV_KEEP.
ENV_ALLOW="PATH HOME USER LOGNAME SHELL PWD LANG LANGUAGE LC_ALL LC_CTYPE LC_COLLATE LC_MESSAGES LC_MONETARY LC_NUMERIC LC_TIME LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION TZ TMPDIR TERM XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK GIT_SSH GIT_SSH_COMMAND GIT_SSH_VARIANT GIT_ASKPASS SSH_ASKPASS GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GNUPGHOME GH_CONFIG_DIR GH_HOST GLAB_CONFIG_DIR GITLAB_HOST GIT_TRACE_REDACT GIT_TERMINAL_PROMPT GIT_TRACE2 GIT_TRACE2_EVENT GIT_TRACE2_PERF TAG SHLVL _ OLDPWD"
# NET_ALLOW (round 11): the test's own copy of the environment of a NETWORK child (git, ssh, curl, gh, glab and the
# badge computer, started through rc_net): the paths and sockets of the network allow-list, the constants rc_net
# sets, and nothing of the caller's locale, account, terminal or RELEASE_ENV_KEEP (ssh sends LANG, LC_* and every
# SendEnv name it finds; a network child that has none of them cannot send them). bash adds no _ to the child of
# rc_net (measured, see the K11 cases of test_redact_cut.sh); PWD, SHLVL and OLDPWD are un-exported by rc_net.
NET_ALLOW="PATH HOME TMPDIR SSH_AUTH_SOCK GIT_SSH GIT_SSH_COMMAND GIT_SSH_VARIANT GIT_ASKPASS SSH_ASKPASS GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GNUPGHOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS GH_CONFIG_DIR GH_HOST GLAB_CONFIG_DIR GITLAB_HOST LC_ALL GIT_TRACE_REDACT GIT_TERMINAL_PROMPT GIT_TRACE2 GIT_TRACE2_EVENT GIT_TRACE2_PERF"
# the dirty caller environment of the L1/L2 cases: entries whose names are not shell identifiers (bash cannot
# un-export them), a plain variable, and an inherited allexport; the values are markers. Round 8 (N1): a name with
# the LC_ prefix that is no locale category (LC_ZZTOKEN: a prefix allow-list passes it, and ssh sends LC_* to the
# remote server) and an allow-listed locale name whose value is not locale-shaped (LC_MESSAGES holding a URL with
# a user name and password: the value check of rc_env_lockdown must drop it); LANG and LANGUAGE are left to the
# caller (a broken LANG makes some children warn)
ENV_DIRTY=('BAD-NAME=ZZNONID7' 'A.TOKEN=ZZDOT7' 'npm_config_//h.invalid/:_authToken=ZZNPM7' 'ZZPLAIN7=ZZPLAINV7' 'LC_ZZTOKEN=ZZLCTOK8' 'LC_MESSAGES=https://u:ZZLCV8@h.invalid/')
ENV_MARKERS="ZZNONID7 ZZDOT7 ZZNPM7 ZZPLAINV7 ZZLCTOK8 ZZLCV8"
# hup_ignored: status 0 when SIGHUP is ignored in this process (for example under nohup). Bash cannot trap a
# signal that was ignored when it started, so a HUP case would test the caller's signal state, not the script:
# such a case is SKIPPED with this reason (round 7, L4).
hup_ignored() { local m; m="$(awk '/^SigIgn:/{print $2}' "/proc/$$/status" 2>/dev/null)"; [ -n "$m" ] && (( (16#$m) & 1 )); }
# hup_control: the control needles of hup_ignored. "ok": an ignored SIGHUP is seen in a child that ignores it, and a
# child that does not ignore it reads clean; "ok-positive-only": this process ignores SIGHUP itself, so no child can
# be made to not ignore it (a signal ignored at start cannot be reset) and only the positive needle ran;
# "blind-positive" / "blind-negative": the detector is broken.
hup_control() {
  local f="${BASH_SOURCE[0]}"
  bash -c 'trap "" HUP; exec bash -c ". \"\$1\"; hup_ignored" _ "$1"' _ "$f" || { echo blind-positive; return; }
  if hup_ignored; then echo ok-positive-only; return; fi
  bash -c '. "$1"; hup_ignored' _ "$f" && { echo blind-negative; return; }
  echo ok
}
# suite_exit FAIL SKIPPED (round 8, N6): the exit status of a suite. 1 when a case failed; 77 (the SKIP status of
# scripts/run_full_suite.sh) when a case was SKIPPED, unless the caller expects skips (RELEASE_TESTS_ALLOW_SKIP=1: the
# mutation harness sets it, it judges a skipped case itself); else 0. So a standalone run under an ignored SIGHUP no
# longer reads as a full PASS.
suite_exit() {
  [ "$1" -eq 0 ] || return 1
  [ "$2" -eq 0 ] || [ "${RELEASE_TESTS_ALLOW_SKIP:-}" = 1 ] || return 77
  return 0
}
# nofile_room (round 9, F1 and F2 of the round-8 review): raise this shell's soft open-files limit to the hard limit
# and return 0 when descriptor 100000 can be opened, so a suite can pass descriptors of 3, 5 and 6 digits (300,
# 12345, 100000) to a release script; 1 otherwise (the suite then SKIPs those cases with this reason, never passes
# them). Call it in the suite's own shell (not in $(...)): the raised limit must hold for the redirections.
NOFILE_WHY="the open-files limit (ulimit -Hn) is below 100001: descriptors of 5 and 6 digits cannot be opened here"
nofile_room() {
  local s
  ulimit -n "$(ulimit -Hn)" 2>/dev/null
  s="$(ulimit -n)"
  [ "$s" = unlimited ] || [ "$s" -gt 100000 ] 2>/dev/null
}
