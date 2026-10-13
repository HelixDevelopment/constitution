#!/usr/bin/env bash
# =============================================================================
# test_multitrack_persistent_launch_survives_session_teardown.sh — RED/GREEN
#   proof for multitrack_persistent_launch.sh (ATM-1041).
# -----------------------------------------------------------------------------
# Purpose:
#   PROVE, hermetically and without touching any real cron job / real track /
#   real ccr process, that:
#     T1 (RED characterization) -- the OLD `nohup <cmd> & disown` pattern
#        dies the moment its LAUNCHING context's own session/cgroup scope is
#        torn down. This reproduces, portably and in seconds, the exact
#        mechanism that was killing this project's real cron-launched T2/T3/
#        T4 supervisors + ccr every 4-minute cycle (see
#        multitrack_persistent_launch.sh's header for the real crontab
#        forensics this stands in for).
#     T2 (GREEN)  -- `mt_persistent_launch` (the UUT) launched under the
#        IDENTICAL teardown survives it.
#     T3 (§1.1 mutation) -- a copy of the UUT with its availability probe
#        forced to always report "unavailable" (forcing the nohup-fallback
#        path on every call) reproduces T1's death under T2's exact
#        scenario -- proving the systemd-scope mechanism, not incidental
#        timing, is what keeps T2's process alive.
#
#   How a real session/cron-scope teardown is simulated WITHOUT cron: a
#   throwaway `systemd-run --user --scope --unit=<X> --collect` stands in for
#   the transient `session-<N>.scope` systemd-logind opens for a cron job
#   (identical cgroup-membership semantics -- confirmed directly against a
#   real crontab entry during this defect's investigation), and an explicit
#   `systemctl --user stop <X>.scope` stands in for logind closing that
#   session (which, with `KillUserProcesses=yes`, signals every process
#   still resident in the scope's cgroup -- exactly what a real session
#   close does).
#
# Usage:   test_multitrack_persistent_launch_survives_session_teardown.sh
# Inputs (env): none. Hermetic -- every launched process + transient unit is
#   started and reaped by this script; nothing outside its own temp dir is
#   touched.
# Outputs: per-case PASS/FAIL lines; exit 0 iff every case passed.
# Side-effects: starts + stops its own short-lived `systemd-run --user
#   --scope` units and their child processes only (never touches
#   /mnt/trackN, crontab, or any real ccr/supervisor process). SKIPs the
#   whole suite honestly (exit 2) on a host with no reachable systemd --user
#   bus, since the defect + fix are both systemd-specific by construction.
# Dependencies: bash, systemd-run, systemctl (both --user), date, tr,
#   mktemp, sleep, kill.
#
# Cross-references:
#   constitution/scripts/multitrack/multitrack_persistent_launch.sh (UUT)
#   qa-results/multitrack/continue.sh (the real consumer this defends)
#
# Constitution: §11.4.115 (RED-before-fix) §11.4.201 (guard asserts the REAL
#   condition; SKIP-with-reason on unresolvable topology, never a fake PASS)
#   §11.4.6 §11.4.224 (test-first) §1.1 (paired mutation) §11.4.3.
# =============================================================================
set -u

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
UUT="$SELF_DIR/multitrack_persistent_launch.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

TMP="$(mktemp -d)" || exit 1
UNITS_TO_STOP=""
cleanup() {
    for u in $UNITS_TO_STOP; do
        systemctl --user stop "$u" >/dev/null 2>&1 || true
    done
    rm -rf "$TMP" 2>/dev/null
    return 0
}
trap cleanup EXIT INT TERM

echo "=== persistent-launch survives-session-teardown (ATM-1041) — UUT: $UUT"

# --- host-topology gate (§11.4.3 honest SKIP, never a fake PASS) -----------
if ! command -v systemd-run >/dev/null 2>&1 || ! command -v systemctl >/dev/null 2>&1; then
    echo "SKIP: systemd-run/systemctl absent (reason: topology_unsupported)"
    exit 2
fi
if ! systemctl --user list-units >/dev/null 2>&1; then
    echo "SKIP: systemd --user bus unreachable (reason: topology_unsupported)"
    exit 2
fi
[ -r "$UUT" ] || { echo "SKIP: UUT absent (reason: tool_absent)"; exit 2; }

_uniq() {
    _n="$(date +%s%N 2>/dev/null)"
    case "$_n" in ''|*[!0-9]*) _n="$(date +%s)-$$-${RANDOM:-0}" ;; esac
    printf '%s' "$_n"
}

# run_teardown_case <label> <launcher-body-shell-snippet> <out-file>
#   Wraps <launcher-body-shell-snippet> in its own throwaway
#   `systemd-run --user --scope` (the session-scope stand-in), waits for it
#   to establish, explicitly stops that scope (the session-close stand-in),
#   then reports whether the pid the snippet wrote to <out-file> is still
#   alive.
run_teardown_case() {
    _label="$1"; _body="$2"; _out="$3"
    _lu="ATM1041-launcher-${_label}-$(_uniq)"
    _lu="$(printf '%s' "$_lu" | tr -c 'A-Za-z0-9:_.-' '-')"
    rm -f "$_out"
    systemd-run --user --scope --unit="$_lu" --collect --quiet -- bash -c "$_body" >/dev/null 2>&1 &
    _launcher_pid=$!
    UNITS_TO_STOP="$UNITS_TO_STOP ${_lu}.scope"
    sleep 1
    systemctl --user stop "${_lu}.scope" >/dev/null 2>&1
    wait "$_launcher_pid" 2>/dev/null
    sleep 1
    if [ ! -s "$_out" ]; then
        echo "no-pid-recorded"
        return
    fi
    _bgpid="$(cat "$_out")"
    if kill -0 "$_bgpid" 2>/dev/null; then
        kill "$_bgpid" 2>/dev/null
        echo "alive"
    else
        echo "dead"
    fi
}

# ---- T1 RED characterization: bare nohup+disown dies under teardown -------
T1_OUT="$TMP/t1_pid.txt"
T1_BODY="nohup sleep 60 >/dev/null 2>&1 & echo \$! > '$T1_OUT'; disown; sleep 2"
T1_RESULT="$(run_teardown_case "old" "$T1_BODY" "$T1_OUT")"
if [ "$T1_RESULT" = "dead" ]; then
    ok "T1 RED characterization: bare nohup+disown dies under session-scope teardown (reproduces the real defect)"
else
    bad "T1 RED characterization" "expected 'dead', got '$T1_RESULT' -- the reproduction mechanism itself is not reproducing the defect; every downstream conclusion below is unproven"
fi

# ---- T2 GREEN: mt_persistent_launch survives the identical teardown -------
T2_OUT="$TMP/t2_pid.txt"
T2_BODY=". '$UUT'; mt_persistent_launch atm1041t2 /dev/null -- sleep 60; echo \"\$MT_PERSISTENT_LAUNCH_PID\" > '$T2_OUT'; sleep 2"
T2_RESULT="$(run_teardown_case "new" "$T2_BODY" "$T2_OUT")"
if [ "$T2_RESULT" = "alive" ]; then
    ok "T2 GREEN: mt_persistent_launch survives session-scope teardown (fix holds)"
else
    bad "T2 GREEN" "expected 'alive', got '$T2_RESULT'"
fi

# ---- T3 §1.1 mutation: force the fallback path, T2's scenario must die again
MUT="$TMP/uut_mutated.sh"
sed 's/^mt_persistent_launch_available() {/mt_persistent_launch_available() {\n    return 1  # MUTATED for paired §1.1 -- force nohup-fallback always/' "$UUT" > "$MUT"
if grep -q 'MUTATED for paired' "$MUT" && bash -n "$MUT" 2>/dev/null; then
    T3_OUT="$TMP/t3_pid.txt"
    T3_BODY=". '$MUT'; mt_persistent_launch atm1041t3 /dev/null -- sleep 60 2>/dev/null; echo \"\$MT_PERSISTENT_LAUNCH_PID\" > '$T3_OUT'; sleep 2"
    T3_RESULT="$(run_teardown_case "mut" "$T3_BODY" "$T3_OUT")"
    if [ "$T3_RESULT" = "dead" ]; then
        ok "T3 MUT §1.1: forcing the nohup-fallback path reproduces the death under T2's exact scenario (the systemd-scope mechanism is load-bearing)"
    else
        bad "T3 MUT §1.1" "expected 'dead' on the mutated (fallback-forced) copy, got '$T3_RESULT' -- mutation did not break T2, so T2 is not proven load-bearing"
    fi
else
    bad "T3 MUT §1.1" "mutation harness defect (could not apply/parse)"
fi

echo "--- RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
