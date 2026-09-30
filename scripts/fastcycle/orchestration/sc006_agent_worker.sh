#!/bin/bash
# sc006_agent_worker.sh -- SpecKit-004 "fast-dev-cycles" US5 T138 (SC-006
# exercise) PRIVATE helper process. Spawned by sc006_exercise.sh (its own
# header explains why) as a REAL, independent OS process via `bash <this
# file> ... &` -- never a Task-tool Agent dispatch. T138's own task text
# names "process table"/"process kill" as the oracle, which is only
# observable against a real PID; this file's whole purpose is to BE that
# real PID, with a genuinely distinguishing /proc/<pid>/cmdline (each
# invocation carries its own unique `--key <k>` argv pair, which
# sc006_exercise.sh records as the `--pid-cmdline-pattern` for the
# `cycle`-mode agent it means to crash-kill, so `agent_registry_writer.sh
# --reap`'s real cmdline cross-check -- never a bare pgrep/substring match,
# section 11.4.196(D)/section 12.12 -- has a genuine identity to verify).
#
# Not a general-purpose tool; lives alongside sc006_exercise.sh purely
# because that is where its one caller is (mirrors this directory's own
# heartbeat.sh / completion_probe.sh precedent of small single-purpose
# siblings invoked by subprocess, never re-implemented inline, section
# 11.4.227). Contract: NONE (same "no contract in this directory" house
# convention heartbeat.sh's own header already documents) -- every wire
# decision below is DEFINED here, binding-if-adopted, and consumed only by
# sc006_exercise.sh.
#
# Modes:
#   --mode cycle
#     dispatched -> in-flight (carrying --pid "$$" and a --pid-cmdline-
#     pattern of "--key <k>" -- a literal, genuinely-distinguishing
#     substring of this exact process's own /proc/<pid>/cmdline, since
#     argv always contains the two consecutive tokens "--key" "<k>") ->
#     STEPS x (one heartbeat.sh beat + one marker-file JSONL line) -> a
#     final `<key>.done` marker -> complete (--completion-source
#     real-completion-event). The caller (sc006_exercise.sh) may `kill -9`
#     this process at ANY point before it reaches its own `complete`
#     write -- that interruption, with ZERO further write from this
#     process, is exactly how the exercise's "crash-killed" agent is
#     produced (the honest "no graceful registry update from the crashed
#     process itself" case T138's own task text names).
#   --mode capsignal
#     dispatched ONLY -- deliberately never transitions to in-flight,
#     because agent_registry_writer.sh's V-AR-2 ordering guard accepts a
#     manual `refused` write ONLY when the key's prior history is `[]` or
#     `["dispatched"]`; a `refused` after `in-flight` would be REJECTED.
#     This process then loops writing marker-file lines only (no registry
#     or heartbeat activity of its own) until the CALLER writes `refused`
#     (mirroring a simulated rate-limit/cap kill's real reason-class
#     signature, section 11.4.196(B)) and kills this process from the
#     outside.
#
# This process's own exit code is never read by sc006_exercise.sh's
# oracle -- it is either killed by its caller, or (in `cycle` mode) reaches
# its own natural end. The oracle is built ENTIRELY from marker files this
# process writes plus the real process table (ps/kill -0/wait), per
# T138's own explicit instruction ("oracle = marker files + process table,
# never the registry itself").
#
# Usage:
#   sc006_agent_worker.sh --mode cycle|capsignal --key <16-hex>
#       --marker-dir <dir> --heartbeat-dir <dir> --steps <n>
#       --sleep-seconds <n> --writer <path to agent_registry_writer.sh>
#       --heartbeat-sh <path to heartbeat.sh> --registry-file <path>
#       --call-log <path>
#
#   `--call-log <path>`: every writer-CLI invocation this process attempts
#   appends exactly one line `<epoch>\tattempt\t<event>\t<key>` to this
#   file BEFORE the writer is invoked (matching agent_registry_writer.sh's
#   own documented single-write-line O_APPEND convention, section
#   11.4.116) -- sc006_exercise.sh's mechanical "zero manual edits" proof
#   sums these attempt-lines (from every spawned worker plus its own
#   direct calls) and asserts the total equals the real registry file's
#   final line count (plus `--reap`'s own separately-reported internal
#   write count) -- a mismatch would mean some line was added to, or
#   removed from, the registry by something OTHER than a counted writer
#   invocation.
#
# Exit codes: 0 on a `cycle` run that reaches its own natural completion,
#   or a `capsignal` run that reaches the end of its own loop unkilled
#   (both honest "the caller never killed me in time" outcomes the
#   exercise's own timing margin is designed to avoid, but which are
#   PID-observable, not silently hidden); 2 on a usage error (missing
#   required flag or unknown --mode).
set -u

MODE=""
KEY=""
MARKER_DIR=""
HB_DIR=""
STEPS="6"
SLEEP_S="1"
WRITER=""
HEARTBEAT_SH=""
REG_FILE=""
CALL_LOG=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)          MODE="${2:-}";          shift 2 || break ;;
        --key)           KEY="${2:-}";           shift 2 || break ;;
        --marker-dir)    MARKER_DIR="${2:-}";    shift 2 || break ;;
        --heartbeat-dir) HB_DIR="${2:-}";        shift 2 || break ;;
        --steps)         STEPS="${2:-}";         shift 2 || break ;;
        --sleep-seconds) SLEEP_S="${2:-}";       shift 2 || break ;;
        --writer)        WRITER="${2:-}";        shift 2 || break ;;
        --heartbeat-sh)  HEARTBEAT_SH="${2:-}";  shift 2 || break ;;
        --registry-file) REG_FILE="${2:-}";      shift 2 || break ;;
        --call-log)      CALL_LOG="${2:-}";      shift 2 || break ;;
        *) shift ;;
    esac
done

if [ -z "$MODE" ] || [ -z "$KEY" ] || [ -z "$MARKER_DIR" ] || [ -z "$WRITER" ] || [ -z "$REG_FILE" ]; then
    echo "sc006_agent_worker.sh: missing one of required --mode/--key/--marker-dir/--writer/--registry-file" >&2
    exit 2
fi

mkdir -p "$MARKER_DIR" >/dev/null 2>&1
[ -n "$HB_DIR" ] && mkdir -p "$HB_DIR" >/dev/null 2>&1

write_event() {
    # $1 = event name, remaining args = extra flags forwarded verbatim to
    # agent_registry_writer.sh's manual mode.
    local ev="$1"
    shift
    if [ -n "$CALL_LOG" ]; then
        printf '%s\tattempt\t%s\t%s\n' "$(date -u +%s)" "$ev" "$KEY" >>"$CALL_LOG" 2>/dev/null
    fi
    HELIX_AGENT_REGISTRY_FILE="$REG_FILE" bash "$WRITER" --event "$ev" --key "$KEY" "$@" >/dev/null 2>&1
}

MARKER_FILE="$MARKER_DIR/${KEY}.markers.jsonl"
DONE_FILE="$MARKER_DIR/${KEY}.done"

write_event dispatched --note "sc006 fixture agent (mode=$MODE)"

case "$MODE" in
    cycle)
        # --pid-cmdline-pattern "--key $KEY" is a genuine, literal
        # substring of THIS process's own /proc/$$/cmdline (argv always
        # carries the consecutive tokens "--key" "<KEY>") -- never a bare
        # pgrep-style guess, matching agent_registry_writer.sh's own
        # documented C2 PID-reuse-guard idiom exactly.
        write_event in-flight --pid "$$" --pid-cmdline-pattern "--key $KEY"
        step=1
        while [ "$step" -le "$STEPS" ]; do
            if [ -n "$HEARTBEAT_SH" ] && [ -f "$HEARTBEAT_SH" ]; then
                bash "$HEARTBEAT_SH" beat --key "$KEY" --heartbeat-dir "$HB_DIR" >/dev/null 2>&1
            fi
            printf '{"step":%d,"ts":%s,"pid":%d}\n' "$step" "$(date -u +%s)" "$$" >>"$MARKER_FILE"
            sleep "$SLEEP_S"
            step=$((step + 1))
        done
        printf '{"key":"%s","completed_steps":%d,"pid":%d,"ts":%s}\n' "$KEY" "$STEPS" "$$" "$(date -u +%s)" >"$DONE_FILE"
        write_event complete --completion-source real-completion-event --note "sc006 natural completion (mode=cycle)"
        ;;
    capsignal)
        # Deliberately NEVER writes in-flight -- see header. Loops writing
        # marker lines only, until the caller writes `refused` + kills
        # this process from the outside.
        step=1
        while [ "$step" -le "$STEPS" ]; do
            printf '{"step":%d,"ts":%s,"pid":%d}\n' "$step" "$(date -u +%s)" "$$" >>"$MARKER_FILE"
            sleep "$SLEEP_S"
            step=$((step + 1))
        done
        printf '{"key":"%s","completed_steps":%d,"pid":%d,"ts":%s}\n' "$KEY" "$STEPS" "$$" "$(date -u +%s)" >"$DONE_FILE"
        ;;
    *)
        echo "sc006_agent_worker.sh: unknown --mode '$MODE' (must be cycle|capsignal)" >&2
        exit 2
        ;;
esac

exit 0
