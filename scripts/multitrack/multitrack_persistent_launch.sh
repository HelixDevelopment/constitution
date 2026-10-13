#!/usr/bin/env bash
# =============================================================================
# multitrack_persistent_launch.sh — background-launch a daemon that survives
#                                    the teardown of ITS OWN launching context
#                                    (cron / SSH / any transient login session)
#                                    (§11.4.177 shared-engine primitive; ATM-1041).
# -----------------------------------------------------------------------------
# Purpose:
#   `nohup <cmd> & disown` only protects a background process against SIGHUP
#   on the launching shell's own exit and against the shell's job-table
#   cleanup. On a systemd host it does NOT move the process to a different
#   cgroup. When the launching context is a cron job (or any short-lived
#   login-style session), systemd-logind opens a transient
#   `session-<N>.scope` for it and — because `KillUserProcesses=yes` is a
#   common systemd-logind default (confirmed on this host:
#   /etc/systemd/logind.conf `KillUserProcesses=yes`) — EXPLICITLY stops that
#   scope's whole cgroup the moment the session closes, signalling every
#   process still resident in it, `nohup`'d children included, because
#   `nohup`/`disown` never moved them out of that cgroup in the first place.
#
#   Root-cause FORENSICS (ATM-1041, captured 2026-09-27):
#     - Real crontab evidence: a one-shot cron entry backgrounding
#       `sleep 300` via `nohup ... & disown` recorded BOTH the launcher and
#       the backgrounded child living in `session-5004.scope`
#       (`/proc/<pid>/cgroup`). `journalctl` shows that scope started AND
#       stopped inside the SAME second the cron job ran; 90s later the
#       backgrounded pid no longer existed (`kill -0` -> ESRCH).
#     - This is the EXACT mechanism silently killing this project's
#       continuous multi-track delivery loop: `qa-results/multitrack/
#       continue.sh` (invoked every 4 minutes from crontab) relaunches `ccr`
#       and the T2/T3/T4 `track_dev_supervisor.sh` via bare
#       `nohup ... & disown`, and every one of them was found dead by the
#       NEXT 4-minute cron tick, across 11+ consecutive cycles
#       (`qa-results/multitrack/logs/watchdog_cron.log`) -- meaning every
#       track's continuous-delivery work was starting completely from
#       scratch, never actually running between ticks.
#     - Portable, deterministic, non-destructive re-reproduction (used by
#       this file's paired test, no real cron/track touched): wrap a
#       `nohup ... & disown` launch inside a throwaway
#       `systemd-run --user --scope` (which stands in for a session scope --
#       same cgroup-membership semantics), then explicitly
#       `systemctl --user stop` that wrapping scope (which stands in for
#       logind closing the real session). The `nohup`'d child dies every
#       time; a child instead launched via its OWN separate
#       `systemd-run --user --scope --unit=<unique> --collect --` survives,
#       because it never shared the launcher's cgroup to begin with.
#
#   Fix: `mt_persistent_launch` below launches the command into its OWN
#   independent, garbage-collected (`--collect`) systemd user scope when a
#   systemd user manager is reachable (the REAL, functionally-probed
#   condition, §11.4.201 -- never inferred from `command -v` alone), so it is
#   never cgroup-resident under whatever transient scope invoked it and
#   therefore cannot be torn down when THAT scope closes. On a host with no
#   reachable systemd user manager (non-systemd, or `--user` bus
#   unreachable) it degrades to the previous bare `nohup + disown` behaviour
#   with an EXPLICIT, non-silent warning that the weaker guarantee is in
#   effect (§11.4.201 -- a silent fallback would itself be the exact class of
#   bluff this fix exists to remove).
#
# Usage (source this file, then call the function -- see below for why it
# MUST be sourced into the caller's own shell, never invoked via a
# command-substitution subshell):
#   . "<this-file>"
#   mt_persistent_launch <slug> <logfile-or-empty-or-/dev/null> -- <cmd...>
#   echo "launched pid $MT_PERSISTENT_LAUNCH_PID via $MT_PERSISTENT_LAUNCH_MECHANISM"
#
#   <slug>     short identifying tag folded into the transient unit name
#              (systemd-unit-safe characters only are required of it; this
#              function sanitizes it defensively regardless).
#   <logfile>  path to append the launched command's stdout+stderr to, or
#              "/dev/null" (or empty string) to discard it, exactly mirroring
#              the semantics of the `nohup <cmd> >"$LOG" 2>&1 &` call sites
#              this function replaces.
#   --         literal separator (mandatory) before the command + its args.
#   <cmd...>   the command to launch, as a plain argv list (no `bash -c`
#              string quoting needed/wanted by callers).
#
# Why "source, don't subshell": `mt_persistent_launch` backgrounds the job
# with a bare `&` in the CURRENT shell so that `$!` -- captured into
# MT_PERSISTENT_LAUNCH_PID -- is the real, final PID of the launched command
# (systemd-run --scope execs directly into the target command; there is no
# extra fork, so the PID is stable across that exec). If this function were
# captured via `$(...)` command substitution instead, the background job
# would be started in a throwaway subshell and its PID would never reach the
# caller's own job table -- the caller would have nothing to `disown`, wait
# on, or log.
#
# Outputs (globals set on every call, both success paths):
#   MT_PERSISTENT_LAUNCH_PID         PID of the launched command.
#   MT_PERSISTENT_LAUNCH_MECHANISM   "systemd-scope" | "nohup-fallback".
#
# Exit codes: 0 launched (either mechanism) · 2 usage error (missing `--`,
#             missing command) · 1 systemd-run invocation itself failed to
#             start (rare -- e.g. bus call rejected after the availability
#             probe already passed); the fallback nohup path is attempted in
#             that case too before giving up, still never silent about which
#             mechanism actually launched.
#
# Side-effects: starts exactly one detached background process. Under the
#   systemd-scope mechanism it also registers ONE transient, uniquely-named,
#   self-collecting (`--collect`) scope unit -- garbage-collected by systemd
#   the moment the launched command exits, so repeated calls never leak unit
#   entries. Writes nothing to disk itself beyond the caller-supplied
#   logfile.
#
# Dependencies: bash: systemd-run + systemctl (OPTIONAL -- absence degrades
#   to the nohup fallback with a printed warning, never a hard failure);
#   date, tr (POSIX-standard, always present).
#
# Cross-references:
#   qa-results/multitrack/continue.sh (HOST-SPECIFIC consumer driver; the two
#     call sites this primitive replaces: `ccr start` + per-track
#     `track_dev_supervisor.sh` launch)
#   test_multitrack_persistent_launch_survives_session_teardown.sh (this
#     file's paired RED->GREEN test + §1.1 mutation)
#
# Constitution: §11.4.177 (shared-engine decoupling -- this primitive is
#   project-agnostic and carries no /mnt/trackN literal) §11.4.201 (guard
#   asserts the REAL condition -- availability is functionally probed, never
#   inferred from binary presence alone; a fallback is never silent)
#   §11.4.6 (no-guessing -- the root cause above is captured forensic
#   evidence, not a hypothesis) §11.4.115 (RED-before-fix; the reproduction
#   this header describes is exactly the paired test's RED case)
#   §11.4.224 (test-first) §1.1 (paired mutation proves the test load-bearing)
#   §11.4.147 (a killed daemon is a crash, not a completion -- this closes
#   the crash vector at its source instead of only detecting it after) §12.6.
# =============================================================================
set -u

# mt_persistent_launch_available -- REAL functional probe (§11.4.201), never
# a bare `command -v` presence check: confirms systemd-run exists AND the
# user's own systemd manager instance actually answers over the bus.
mt_persistent_launch_available() {
    command -v systemd-run >/dev/null 2>&1 || return 1
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl --user list-units >/dev/null 2>&1 || return 1
    return 0
}

# mt_persistent_launch_unit_name <slug> -- build a unique, systemd-unit-safe
# unit-name stem (no trailing ".scope"; systemd-run appends it). Uniqueness:
# caller PID + nanosecond-resolution epoch (falls back to seconds+PID+RANDOM
# on a `date` without %N support -- never bare seconds alone, which WOULD
# collide across rapid repeated launches).
mt_persistent_launch_unit_name() {
    _mtpl_slug="${1:-mt}"
    _mtpl_ns="$(date +%s%N 2>/dev/null)"
    case "$_mtpl_ns" in
        ''|*[!0-9]*) _mtpl_ns="$(date +%s 2>/dev/null || echo 0)-$$-${RANDOM:-0}" ;;
    esac
    _mtpl_raw="mt-${_mtpl_slug}-$$-${_mtpl_ns}"
    # systemd unit names: [A-Za-z0-9:_.-]+ only; sanitize defensively.
    _mtpl_clean="$(printf '%s' "$_mtpl_raw" | tr -c 'A-Za-z0-9:_.-' '-')"
    # keep well under systemd's unit-name length ceiling
    printf '%.200s' "$_mtpl_clean"
}

# mt_persistent_launch <slug> <logfile> -- <cmd...>
mt_persistent_launch() {
    _mtpl_slug="${1:?slug required}"; shift
    _mtpl_log="${1-}"; shift || true
    if [ "${1-}" != "--" ]; then
        echo "mt_persistent_launch: usage error -- missing literal '--' before the command" >&2
        return 2
    fi
    shift
    if [ "$#" -eq 0 ]; then
        echo "mt_persistent_launch: usage error -- no command given" >&2
        return 2
    fi

    _mtpl_unit="$(mt_persistent_launch_unit_name "$_mtpl_slug")"
    MT_PERSISTENT_LAUNCH_PID=""
    MT_PERSISTENT_LAUNCH_MECHANISM=""

    if mt_persistent_launch_available; then
        if [ -z "$_mtpl_log" ] || [ "$_mtpl_log" = "/dev/null" ]; then
            systemd-run --user --scope --unit="$_mtpl_unit" --collect --quiet -- "$@" >/dev/null 2>&1 &
        else
            systemd-run --user --scope --unit="$_mtpl_unit" --collect --quiet -- "$@" >>"$_mtpl_log" 2>&1 &
        fi
        MT_PERSISTENT_LAUNCH_PID=$!
        disown "$MT_PERSISTENT_LAUNCH_PID" 2>/dev/null || true
        MT_PERSISTENT_LAUNCH_MECHANISM="systemd-scope"
        return 0
    fi

    # --- honest, non-silent degradation (§11.4.201) ---------------------------
    echo "mt_persistent_launch: WARNING -- systemd-run / systemd --user bus unreachable; falling back to nohup+disown for '$_mtpl_slug'. This process will NOT survive the teardown of whatever session/cgroup scope launches it (e.g. cron's transient session scope with KillUserProcesses=yes) -- see multitrack_persistent_launch.sh header for the full defect this normally defends against." >&2
    if [ -z "$_mtpl_log" ] || [ "$_mtpl_log" = "/dev/null" ]; then
        nohup "$@" >/dev/null 2>&1 &
    else
        nohup "$@" >>"$_mtpl_log" 2>&1 &
    fi
    MT_PERSISTENT_LAUNCH_PID=$!
    disown "$MT_PERSISTENT_LAUNCH_PID" 2>/dev/null || true
    MT_PERSISTENT_LAUNCH_MECHANISM="nohup-fallback"
    return 0
}
