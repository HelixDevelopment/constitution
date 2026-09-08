#!/usr/bin/env bash
# await_condition.sh — wait until a condition holds, with a hard ceiling, and
# report WHICH outcome the wait ended on.
#
# WHY THIS EXISTS (§11.4.274)
#   "Poll until the build process is gone / until the log shows the terminal
#   line, then continue" was written ad hoc three times in one session, each time
#   with the same shape and each time as a fresh chance to get the exit semantics
#   wrong. Poll loops are the canonical deterministic mechanism.
#
# THE ONE PROPERTY THAT MATTERS (§11.4.201)
#   A timeout MUST NOT be able to read as success. A wait that exits 0 both when
#   the condition held and when time ran out turns "the build never finished"
#   into "the build finished" — silently, at the exact moment a human stops
#   watching. So satisfaction and expiry have DIFFERENT exit codes and different
#   printed outcomes, and neither is inferred: the condition is re-evaluated one
#   final time after the ceiling before TIMEOUT is declared.
#
# WHAT IT DOES NOT DO (§11.4.274(d))
#   It does not decide whether the thing it waited for SUCCEEDED. A process
#   exiting is not a process exiting well; a log line appearing is not a log line
#   that says what you hoped. It reports that the condition became true.
#
# USAGE
#   await_condition.sh --until 'SHELL COMMAND' [--timeout SECS] [--interval SECS]
#                      [--label NAME] [--quiet]
#   await_condition.sh --pid-gone PID ...
#   await_condition.sh --log-contains FILE --pattern ERE ...
#
#   --until CMD        Condition: exit 0 means satisfied. Evaluated with `bash -c`.
#   --pid-gone PID     Condition: PID is no longer running. Observation only —
#                      this tool never signals a process (§11.4.174: a PID you
#                      did not launch may not be yours).
#   --log-contains F   Condition: file F matches --pattern.
#   --pattern ERE      Extended regex for --log-contains.
#   --timeout SECS     Ceiling. Default 300. 0 means "evaluate once, do not wait".
#   --interval SECS    Poll interval. Default 5.
#   --label NAME       Name used in the outcome line. Default "condition".
#   --quiet            Do not print per-poll progress.
#
# OUTPUT — exactly one outcome line
#   AWAIT <label>: SATISFIED after <n>s (polls=<k>)
#   AWAIT <label>: TIMEOUT after <n>s (polls=<k>) — condition never held
#
# EXIT CODES (§11.4.201)
#   0  SATISFIED — the condition held
#   3  TIMEOUT   — the ceiling expired with the condition still false. Distinct
#                  from 0 and from 1 precisely so it cannot be mistaken for
#                  either success or a substantive finding.
#   2  could not run: no condition given, conflicting conditions, bad numbers,
#      or a --log-contains file that does not exist and cannot be waited on
set -uo pipefail

MECH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mech_common.sh
source "$MECH_DIR/lib/mech_common.sh"

UNTIL="" PIDGONE="" LOGFILE="" PATTERN="" LABEL="condition"
TIMEOUT=300 INTERVAL=5 QUIET=0

usage() { sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --until)        UNTIL="${2:-}"; shift 2 ;;
    --pid-gone)     PIDGONE="${2:-}"; shift 2 ;;
    --log-contains) LOGFILE="${2:-}"; shift 2 ;;
    --pattern)      PATTERN="${2:-}"; shift 2 ;;
    --timeout)      TIMEOUT="${2:-}"; shift 2 ;;
    --interval)     INTERVAL="${2:-}"; shift 2 ;;
    --label)        LABEL="${2:-}"; shift 2 ;;
    --quiet)        QUIET=1; shift ;;
    -h|--help)      usage; exit "$MECH_EXIT_OK" ;;
    *)              mech_die "unknown argument: $1 (try --help)" ;;
  esac
done

n_conditions=0
[ -n "$UNTIL" ]   && n_conditions=$((n_conditions+1))
[ -n "$PIDGONE" ] && n_conditions=$((n_conditions+1))
[ -n "$LOGFILE" ] && n_conditions=$((n_conditions+1))
[ "$n_conditions" -eq 1 ] || mech_die "give exactly one of --until, --pid-gone, --log-contains (got $n_conditions)"

case "$TIMEOUT"  in ''|*[!0-9]*) mech_die "--timeout must be a whole number of seconds: $TIMEOUT" ;; esac
case "$INTERVAL" in ''|*[!0-9]*) mech_die "--interval must be a whole number of seconds: $INTERVAL" ;; esac
[ "$INTERVAL" -gt 0 ] || mech_die "--interval must be greater than 0"

if [ -n "$PIDGONE" ]; then
  case "$PIDGONE" in ''|*[!0-9]*) mech_die "--pid-gone must be a numeric pid: $PIDGONE" ;; esac
fi
if [ -n "$LOGFILE" ]; then
  [ -n "$PATTERN" ] || mech_die "--log-contains requires --pattern"
fi

check() {
  if [ -n "$UNTIL" ]; then
    bash -c "$UNTIL" >/dev/null 2>&1
    return $?
  elif [ -n "$PIDGONE" ]; then
    # Observation only: kill -0 tests existence, it does not signal.
    if kill -0 "$PIDGONE" 2>/dev/null; then return 1; else return 0; fi
  else
    [ -r "$LOGFILE" ] || return 1
    LC_ALL=C grep -Eq -- "$PATTERN" "$LOGFILE" 2>/dev/null
    return $?
  fi
}

START="$(date +%s)"
POLLS=0

while :; do
  POLLS=$((POLLS+1))
  if check; then
    ELAPSED=$(( $(date +%s) - START ))
    printf 'AWAIT %s: SATISFIED after %ss (polls=%s)\n' "$LABEL" "$ELAPSED" "$POLLS"
    exit "$MECH_EXIT_OK"
  fi
  ELAPSED=$(( $(date +%s) - START ))
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    # One final evaluation after the ceiling: the condition may have become true
    # during the last sleep, and reporting TIMEOUT for an already-satisfied
    # condition is as wrong as reporting success for an expired one.
    if check; then
      ELAPSED=$(( $(date +%s) - START ))
      POLLS=$((POLLS+1))
      printf 'AWAIT %s: SATISFIED after %ss (polls=%s)\n' "$LABEL" "$ELAPSED" "$POLLS"
      exit "$MECH_EXIT_OK"
    fi
    printf 'AWAIT %s: TIMEOUT after %ss (polls=%s) — condition never held\n' "$LABEL" "$ELAPSED" "$POLLS"
    exit "$MECH_EXIT_TIMEOUT"
  fi
  [ "$QUIET" -eq 1 ] || mech_log WAIT "$LABEL not yet satisfied (${ELAPSED}s/${TIMEOUT}s, poll $POLLS)"
  sleep "$INTERVAL"
done
