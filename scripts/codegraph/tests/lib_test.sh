# shellcheck shell=bash
# ============================================================================
# lib_test.sh — tiny assertion library shared by the codegraph_safe test suite
# ============================================================================
# Purpose      Uniform RESULT lines + exit status for every test file so that
#              run_all.sh can tabulate and hash them deterministically (§11.4.50).
# Usage        . "$(dirname "$0")/lib_test.sh"   (sourced; defines functions only)
# Inputs       ONLY=<comma list of case ids>  run a subset (used by the mutation
#              harness); CG_DIR=<dir> code under test (default: parent of tests/).
# Outputs      "RESULT <id> PASS|FAIL <desc>" lines on stdout; t_finish exits 1
#              when any case failed.
# Side effects none (no exec, no redirection of the caller's shell — §11.4.67(6)).
# Dependencies bash.
# Cross-refs   run_all.sh, constitution §11.4.224 / §11.4.50 / §11.4.273.
# ============================================================================

T_FAILS=0
T_COUNT=0

t_want() {
    # t_want <id> — true when the case is selected by $ONLY (or ONLY is empty)
    [ -z "${ONLY:-}" ] && return 0
    case ",${ONLY}," in *",$1,"*) return 0 ;; esac
    return 1
}

t_ok() {
    # t_ok <id> <desc>
    T_COUNT=$((T_COUNT + 1))
    printf 'RESULT %s PASS %s\n' "$1" "$2"
}

t_bad() {
    # t_bad <id> <desc> <detail>
    T_COUNT=$((T_COUNT + 1))
    T_FAILS=$((T_FAILS + 1))
    printf 'RESULT %s FAIL %s\n' "$1" "$2"
    printf '  detail[%s]: %s\n' "$1" "$3"
}

t_check() {
    # t_check <id> <desc> <condition-exit-status> <detail>
    if [ "$3" -eq 0 ]; then t_ok "$1" "$2"; else t_bad "$1" "$2" "$4"; fi
}

t_finish() {
    printf 'SUMMARY cases=%s failed=%s\n' "$T_COUNT" "$T_FAILS"
    [ "$T_FAILS" -eq 0 ]
}

t_workdir() {
    # t_workdir <name> — fresh private work dir under $TMPDIR (callers set TMPDIR
    # to their scratch area; the suite never assumes /tmp).
    local base="${TMPDIR:-/tmp}/cg_safe_tests"
    mkdir -p "$base"
    local d
    d="$(mktemp -d "$base/$1.XXXXXX")"
    printf '%s\n' "$d"
}

t_pid_state() {
    # t_pid_state <pid> — single-letter scheduler state from /proc (R/S/T/Z...), or "-"
    local s
    s="$(cat "/proc/$1/stat" 2>/dev/null)" || { echo "-"; return; }
    s="${s##*) }"
    printf '%s\n' "${s%% *}"
}

t_kill_codegraph_pid() {
    # t_kill_codegraph_pid <pid> — cleanup helper. Validates pid > 1 (§11.4.263) and
    # the real /proc cmdline identity (§11.4.174) before any signal.
    local pid="$1"
    case "$pid" in ''|*[!0-9]*) return 0 ;; esac
    [ "$pid" -gt 1 ] || return 0
    tr '\0' '\n' 2>/dev/null < "/proc/$pid/cmdline" | grep -q '/lib/dist/bin/codegraph\.js$' || return 0
    kill -CONT "$pid" 2>/dev/null
    kill -TERM "$pid" 2>/dev/null
    return 0
}
