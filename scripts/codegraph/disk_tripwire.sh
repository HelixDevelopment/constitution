#!/usr/bin/env bash
# ============================================================================
# disk_tripwire.sh — pause a running CodeGraph indexer before it fills its volume
# ============================================================================
# Purpose      A bulk index grows its DB without bound; on a nearly-full volume
#              that exhausts the disk (host safety §12, target safety §11.4.133).
#              This watcher samples free space on the DB volume and, the moment
#              it drops below --min-gib, sends SIGSTOP (reversible: resume with
#              `kill -CONT <pid>`, never SIGKILL) to the indexer.
# Usage        disk_tripwire.sh --pid <pid> --dir <db dir> --min-gib <5..500>
#                               [--interval <s>] --log <file>
# Inputs       --pid     the indexer: MUST be an int > 1 (§11.4.263) AND a live
#                        `node … /lib/dist/bin/codegraph.js` process by its REAL
#                        /proc argv (§11.4.174); a shell that merely mentions
#                        codegraph.js is refused
#              --dir     a path on the DB volume (df target)
#              --min-gib threshold, bounded to [5,500] GiB
#              --interval seconds between samples (default 30)
#              --log     append-only log; "<log>.TRIPPED" marker on trip
#              CG_SAFE_TEST_FREE_BYTES  TEST-ONLY: can only LOWER the measured
#                        free bytes (min(measured, override)) — never fake space
# Outputs      log lines "HH:MM:SS <message>"; marker file on trip
# Exit codes   0  indexer ended, no trip
#              2  usage / refused to arm (bad pid, out-of-range threshold,
#                 target is not a codegraph indexer)
#              3  the pid changed identity while watched (pid reuse) — no signal
#              10 TRIPPED: free < threshold, indexer SIGSTOPped
# Side effects SIGSTOP to the validated indexer on trip; log + marker files
# Dependencies bash, df, python3 (codegraph_safe_helper.py identity)
# Cross-refs   codegraph_safe.sh (starts this watcher), tests/test_tripwire.sh,
#              docs/scripts/disk_tripwire.md, §11.4.263, §11.4.174, §11.4.201
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$HERE/codegraph_safe_helper.py"
PID="" DIR="" MIN_GIB="" INT=30 LOG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --pid) PID="${2-}"; shift 2 ;;
        --dir) DIR="${2-}"; shift 2 ;;
        --min-gib) MIN_GIB="${2-}"; shift 2 ;;
        --interval) INT="${2-}"; shift 2 ;;
        --log) LOG="${2-}"; shift 2 ;;
        *) echo "disk_tripwire: unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -n "$LOG" ] || { echo "disk_tripwire: --log required" >&2; exit 2; }
say() { printf '%s %s\n' "$(date +%T)" "$*" >> "$LOG"; }

case "$PID" in ''|*[!0-9]*) say "REFUSED bad pid '$PID'"; echo "disk_tripwire: pid must be an integer > 1" >&2; exit 2 ;; esac
[ "$PID" -gt 1 ] || { say "REFUSED pid<=1"; echo "disk_tripwire: pid must be > 1 (§11.4.263)" >&2; exit 2; }
case "$MIN_GIB" in ''|*[!0-9]*) say "REFUSED threshold '$MIN_GIB'"; echo "disk_tripwire: --min-gib must be an integer" >&2; exit 2 ;; esac
if [ "$MIN_GIB" -lt 5 ] || [ "$MIN_GIB" -gt 500 ]; then
    say "REFUSED threshold ${MIN_GIB}GiB outside [5,500]"
    echo "disk_tripwire: --min-gib outside documented bound [5,500]" >&2; exit 2
fi
case "$INT" in ''|*[!0-9]*|0) echo "disk_tripwire: --interval must be a positive integer" >&2; exit 2 ;; esac
[ -d "$DIR" ] || { say "REFUSED dir '$DIR' missing"; echo "disk_tripwire: --dir must exist" >&2; exit 2; }

pid_state() {
    local s
    s="$(cat "/proc/$1/stat" 2>/dev/null)" || { echo "-"; return; }
    s="${s##*) }"
    echo "${s%% *}"
}
identity() { python3 "$HELPER" identity "$1" 2>/dev/null; }

ID0="$(identity "$PID")"
case "$ID0" in
    OK\ *) ;;
    *) say "REFUSED pid=$PID is not a codegraph indexer (identity: ${ID0:-unknown})"
       echo "disk_tripwire: pid $PID is not a live codegraph indexer — refusing to arm" >&2; exit 2 ;;
esac
say "ARMED pid=$PID ($ID0) min=${MIN_GIB}GiB dir=$DIR interval=${INT}s"

min_bytes=$((MIN_GIB * 1073741824))
while :; do
    st="$(pid_state "$PID")"
    if [ "$st" = "-" ] || [ "$st" = "Z" ] || [ "$st" = "X" ]; then
        say "indexer pid=$PID gone (state=$st); tripwire exiting"
        exit 0
    fi
    avail="$(df -B1 --output=avail "$DIR" 2>/dev/null | tail -1 | tr -d ' ')"
    case "$avail" in ''|*[!0-9]*) say "WARN df unreadable for $DIR"; sleep "$INT"; continue ;; esac
    ov="${CG_SAFE_TEST_FREE_BYTES:-}"
    case "$ov" in ''|*[!0-9]*) ;; *) [ "$ov" -lt "$avail" ] && avail="$ov" ;; esac
    say "avail_bytes=$avail min_bytes=$min_bytes"
    if [ "$avail" -lt "$min_bytes" ]; then
        idn="$(identity "$PID")"
        if [ "$idn" != "$ID0" ]; then
            say "IDENTITY CHANGED pid=$PID was '$ID0' now '${idn:-gone}' — refusing to signal"
            exit 3
        fi
        if kill -STOP "$PID" 2>/dev/null; then
            say "TRIPPED avail_bytes=$avail < min_bytes=$min_bytes -> SIGSTOP pid=$PID (resume: kill -CONT $PID)"
            : > "$LOG.TRIPPED"
            exit 10
        fi
        say "TRIP signal failed for pid=$PID"
        exit 3
    fi
    sleep "$INT"
done
