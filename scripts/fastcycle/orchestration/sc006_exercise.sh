#!/bin/bash
# sc006_exercise.sh -- SpecKit-004 "fast-dev-cycles" User Story 5 / Phase B,
# plan T-B09, task T138: "SC-006 exercise ... launch >=6 agents on fixture
# items, kill >=2 mid-work (one simulated cap signal, one process kill),
# let the rest complete; oracle = marker files + process table, never the
# registry; zero manual edits and zero phantom owed entries; run twice;
# exclusive use of the dispatcher (not parallel)".
#
# INTERPRETATION OF "AGENTS" (deliberate, see below): the task's own oracle
# language ("process table", "process kill", "simulated cap signal") names
# things only observable against REAL OS-LEVEL PROCESSES with a real PID a
# real `kill -9`/`kill -0`/`ps -p`/`wait` can act on -- a Task-tool Agent
# dispatch inside this harness has no such PID (this project's own T124
# investigation already documented, in tasks.md, that "a nested/dispatched
# subagent cannot TaskStop a task it spawned in this harness"). This
# exercise therefore builds its "agents" as real background OS processes
# (this directory's own new sc006_agent_worker.sh, spawned via `bash
# <worker> ... &`), each one carrying out ONE fixture agent's lifecycle
# against the SAME real `scripts/hooks/agent_registry_writer.sh` and
# `heartbeat.sh` tools production dispatches use -- never a mock, never a
# harness-level Agent dispatch, matching the task's own literal wording.
#
# WHAT THIS EXERCISES (T131-T137, all landed + GREEN before this file was
# written -- pulled fresh, confirmed HEAD == e81de465078 or later before
# starting): the real registry lifecycle end to end --
#   scripts/hooks/agent_registry_writer.sh   (dispatched/in-flight/
#       complete/refused manual events, V-AR-1/V-AR-2 ordering guards,
#       and the T132 --reap stale-lock sweep)
#   constitution/scripts/fastcycle/orchestration/heartbeat.sh (beat)
#   constitution/scripts/fastcycle/orchestration/limit_class.py (--signal,
#       invoked ONLY as a non-load-bearing authenticity check on this
#       exercise's own synthetic cap-signal text, see run_once() below)
# custody_sweep.py and handoff.py are NOT exercised here -- T138's own
# task text scopes this exercise to the registry/heartbeat/reap lifecycle
# only (their own SC-00x exercises, if any, are separate tasks).
#
# RUN-SCOPING DECISION (documented per T138's own instruction to state
# which approach was taken and why): EACH of the two required runs gets
# its OWN fresh, run-id-scoped registry file, heartbeat directory, and
# marker directory (never the real production
# docs/requests/agent_registry.jsonl -- HELIX_AGENT_REGISTRY_FILE is used
# throughout, exactly as agent_registry_writer.sh's own header documents
# it exists for: "the ATM-858 self-validation test so it never touches
# the real registry"). This mirrors how a real test suite is expected to
# behave when run twice in a row -- two independent, isolated trials, not
# one run's leftover state silently bleeding into the next -- and sidesteps
# any question of whether the SAME key correctly re-transitions on a
# second invocation (a different, narrower question this exercise does
# not attempt to answer, since production dispatch keys are themselves
# freshly derived per dispatch, never intentionally reused across
# sessions).
#
# THE ORACLE (T138's own explicit instruction: "oracle = marker files +
# process table, never the registry itself"): every claim this script
# makes about what REALLY happened (did an agent really do mid-work,
# really complete naturally, really die) is established FIRST from
# independent evidence -- a marker-file line count, a `.done` marker's
# presence/absence, `kill -0` + `ps -p` + `wait`'s real exit status on the
# real PID -- and ONLY THEN cross-checked against what the registry
# separately claims. A registry claim with no matching independent
# evidence, or independent evidence with no matching registry claim, is
# reported as a genuine FAIL, never silently reconciled in the registry's
# favour. The registry's own event SEQUENCE per key is independently
# RECOMPUTED by this script's own small `registry_events_for_key()`
# python helper -- authored fresh from the raw JSONL wire format, never by
# calling into or importing agent_registry_writer.sh's own internal
# snapshot-derivation code (Producer != Verifier, section 11.4.240 --
# this script is a distinct oracle from the tool it is testing).
#
# ZERO-MANUAL-EDITS PROOF (mechanical, not a claim): every writer-CLI
# invocation this script or its spawned workers make (dispatched/
# in-flight/complete/refused) appends exactly one `attempt` line to a
# per-run `writer_invocations.log` BEFORE the writer call is made (see
# sc006_agent_worker.sh's own `write_event()` and this file's own
# equivalent below). `--reap`'s own SUMMARY line separately reports how
# many additional lines ITS internal recursive self-invocations wrote
# (`reap=<n>`). The proof: `wc -l` of `writer_invocations.log` (this
# script's own count of every attempted call) PLUS the reap's own
# reported `reap=<n>` MUST equal the real registry file's final line
# count -- a mismatch would mean a line was added to, or removed from,
# the registry by something other than a counted, accounted-for writer
# invocation (including this script itself never doing a raw `>>` into
# the registry file anywhere -- grep this file: it never does).
#
# ZERO-PHANTOM-OWED-ENTRIES PROOF: every one of this run's own generated
# keys must independently recompute to a TERMINAL registry status
# (complete | refused | suspected-dead) by the end of the run -- a key
# still reading dispatched or in-flight forever, with no live process and
# no reap having resolved it, is exactly the "phantom owed" leak this
# whole mechanism (T132's --reap) exists to prevent.
#
# Usage:
#   sc006_exercise.sh [--num-agents <n>] [--steps <n>] [--sleep-seconds <n>]
#       [--kill-after-lines <n>] [--poll-timeout <seconds>]
#       [--out-dir-base <dir>] [--runs <n>]
#
# Defaults: --num-agents 7 (>=6 enforced), --steps 6, --sleep-seconds 1,
#   --kill-after-lines 2, --poll-timeout 30, --runs 2 (T138's own
#   "run twice" requirement), --out-dir-base
#   <repo-root>/qa-results/fastcycle/sc006 (gitignored, section 11.4.11 --
#   exactly like this same directory's own T130 mutation-log precedent
#   under qa-results/fastcycle/us5/mutations/).
#
# Exit codes: 0 iff every check across every run passed; 1 iff ANY check
#   in ANY run failed (reported honestly, per T138's own dispatch
#   instruction, never silently papered over); 2 on a usage/preflight
#   error (missing dependency, --num-agents < 6, etc.).
#
# Cross-references: plan.md T-B09; spec.md SC-006, FR-015, FR-016;
#   scripts/hooks/agent_registry_writer.sh (T131/T132);
#   constitution/scripts/fastcycle/orchestration/heartbeat.sh (T132);
#   constitution/scripts/fastcycle/orchestration/limit_class.py (T135/
#   T136, cap-signal classification, non-load-bearing authenticity check
#   only); tasks.md T130 (the 7 US5 paired mutations this exercise does
#   NOT re-run -- that is a separate, already-DONE task).
#
# EXCLUSIVE-DISPATCHER NOTE: this file itself never dispatches a Task-tool
# Agent, and its own two required runs execute strictly SEQUENTIALLY
# (never backgrounded against each other) -- "exclusive use of the
# dispatcher (not parallel)" is satisfied structurally, by this script
# never touching the dispatcher at all, and by its own invocation being
# run solo (no concurrent subagent dispatch in flight) per the operator's
# own dispatch instructions for this task.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)"
FC="$(cd "$HERE/.." && pwd -P)"
ROOT="$(cd "$FC/../../.." && pwd -P)"

WRITER="$ROOT/scripts/hooks/agent_registry_writer.sh"
HEARTBEAT_SH="$HERE/heartbeat.sh"
WORKER="$HERE/sc006_agent_worker.sh"
LIMIT_CLASS_PY="$HERE/limit_class.py"

NUM_AGENTS=7
STEPS=6
SLEEP_SECONDS=1
KILL_AFTER_LINES=2
POLL_TIMEOUT=30
RUNS=2
OUT_DIR_BASE="$ROOT/qa-results/fastcycle/sc006"

print_help() {
    sed -n '2,/^set -u/p' "${BASH_SOURCE[0]:-$0}" | sed '$d' | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --num-agents)       NUM_AGENTS="${2:-}";       shift 2 || break ;;
        --steps)            STEPS="${2:-}";            shift 2 || break ;;
        --sleep-seconds)    SLEEP_SECONDS="${2:-}";     shift 2 || break ;;
        --kill-after-lines) KILL_AFTER_LINES="${2:-}"; shift 2 || break ;;
        --poll-timeout)     POLL_TIMEOUT="${2:-}";      shift 2 || break ;;
        --out-dir-base)     OUT_DIR_BASE="${2:-}";      shift 2 || break ;;
        --runs)             RUNS="${2:-}";              shift 2 || break ;;
        -h|--help)          print_help; exit 0 ;;
        *) echo "sc006_exercise.sh: unknown flag '$1'" >&2; exit 2 ;;
    esac
done

if [ "$NUM_AGENTS" -lt 6 ] 2>/dev/null; then
    echo "FATAL: --num-agents must be >= 6 (T138's own requirement); got '$NUM_AGENTS'" >&2
    exit 2
fi

command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 required" >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { echo "FATAL: sha256sum required" >&2; exit 2; }
[ -f "$WRITER" ] || { echo "FATAL: writer not found: $WRITER" >&2; exit 2; }
[ -f "$HEARTBEAT_SH" ] || { echo "FATAL: heartbeat.sh not found: $HEARTBEAT_SH" >&2; exit 2; }
[ -f "$WORKER" ] || { echo "FATAL: sc006_agent_worker.sh not found: $WORKER" >&2; exit 2; }

mkdir -p "$OUT_DIR_BASE" 2>/dev/null || { echo "FATAL: cannot create $OUT_DIR_BASE" >&2; exit 2; }

# =============================================================================
# Helpers
# =============================================================================

gen_key() {
    # Deterministic-from-seed 16-hex correlation key -- same format
    # (first 16 hex of a sha256) as production keys, but derived from a
    # fixture seed string, never a real dispatch's session_id/tool_name/
    # description/prompt (this is a fixture, not a real dispatch).
    printf '%s' "$1" | sha256sum | awk '{print substr($1,1,16)}'
}

pid_alive() {
    # $1 = pid. Real PROCESS-TABLE check via BOTH kill -0 AND ps -p --
    # never a bare pgrep/substring match anywhere in this file (the exact
    # footgun class section 11.4.196(D)/section 12.12/section 11.4.201(7)
    # name). Returns 0 (bash true) if alive, 1 if dead.
    local pid="$1"
    if kill -0 "$pid" 2>/dev/null; then
        if ps -p "$pid" -o pid= >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

wait_for() {
    # $1 = description (for the honest timeout message), $2 = timeout
    # seconds, $3.. = a command (function name + args) polled every 0.2s.
    # Returns 0 the moment the command succeeds, 1 on an honest timeout --
    # never a silent infinite loop (section 11.4.196/section 12.6
    # poll-with-timeout discipline).
    local desc="$1" timeout="$2"
    shift 2
    local deadline
    deadline=$(($(date +%s) + timeout))
    while :; do
        if "$@"; then
            return 0
        fi
        if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "  [TIMEOUT] waiting for: $desc (>${timeout}s)" >&2
            return 1
        fi
        sleep 0.2
    done
}

marker_has_at_least() {
    # $1 = marker file path, $2 = minimum line count.
    [ -f "$1" ] || return 1
    local n
    n="$(wc -l <"$1" 2>/dev/null || echo 0)"
    [ "${n:-0}" -ge "$2" ] 2>/dev/null
}

file_exists() { [ -f "$1" ]; }

registry_events_for_key() {
    # $1 = registry jsonl path, $2 = key. Prints one event name per line,
    # in the ORDER they appear in the raw append-only file -- an
    # INDEPENDENTLY authored recomputation (Producer != Verifier, section
    # 11.4.240): this helper never calls into, imports, or sources
    # agent_registry_writer.sh's own internal python; it reads the SAME
    # documented wire format fresh, from this file, so a bug shared
    # between the tool and this oracle cannot silently cancel out.
    local reg="$1" key="$2"
    python3 - "$reg" "$key" <<'PYEOF'
import json, sys
reg, key = sys.argv[1], sys.argv[2]
try:
    with open(reg, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if row.get("key", "") == key:
                print(row.get("event", ""))
except FileNotFoundError:
    pass
PYEOF
}

registry_key_has_event() {
    # $1 = reg file, $2 = key, $3 = expected LATEST (last) event for that
    # key, exact match.
    local last
    last="$(registry_events_for_key "$1" "$2" | tail -n1)"
    [ "$last" = "$3" ]
}

registry_field_for_event() {
    # $1 = reg file, $2 = key, $3 = event name to match, $4 = field name.
    # Prints the LAST matching row's field value (empty if none).
    python3 - "$1" "$2" "$3" "$4" <<'PYEOF'
import json, sys
reg, key, ev, field = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
val = ""
try:
    with open(reg, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if row.get("key", "") == key and row.get("event", "") == ev:
                val = row.get(field, "")
except FileNotFoundError:
    pass
print(val)
PYEOF
}

# =============================================================================
# One full trial (T138 requires exactly two, run strictly sequentially)
# =============================================================================
run_once() {
    local run_idx="$1"
    local run_id out_dir reg_file call_log
    run_id="$(date -u +%Y%m%dT%H%M%SZ)_run${run_idx}_$$"
    out_dir="$OUT_DIR_BASE/$run_id"
    reg_file="$out_dir/agent_registry.jsonl"
    call_log="$out_dir/writer_invocations.log"

    if ! mkdir -p "$out_dir/markers" "$out_dir/heartbeats" 2>/dev/null; then
        echo "FATAL: cannot create $out_dir" >&2
        return 1
    fi
    : >"$reg_file"
    : >"$call_log"

    local RUN_FAILED=0

    echo "  run_id=$run_id"
    echo "  out_dir=$out_dir"
    echo "  registry=$reg_file (fresh, run-scoped -- never docs/requests/agent_registry.jsonl)"

    # --- assign roles: agent1=capsignal-kill, agent2=crash-kill, rest=natural-complete ---
    local -a KEYS=()
    local -a MODES=()
    local -a PIDS=()
    local i
    for i in $(seq 1 "$NUM_AGENTS"); do
        KEYS[i]="$(gen_key "sc006|$run_id|agent$i|$RANDOM|$(date -u +%s%N 2>/dev/null || date -u +%s)")"
        if [ "$i" -eq 1 ]; then
            MODES[i]="capsignal"
        elif [ "$i" -eq 2 ]; then
            MODES[i]="crash"
        else
            MODES[i]="natural"
        fi
    done

    echo "  spawning $NUM_AGENTS fixture agents: 1 simulated-cap-signal-kill, 1 crash-kill (kill -9), $((NUM_AGENTS - 2)) natural-complete"

    for i in $(seq 1 "$NUM_AGENTS"); do
        local key="${KEYS[i]}" mode="${MODES[i]}" worker_mode="cycle"
        [ "$mode" = "capsignal" ] && worker_mode="capsignal"
        bash "$WORKER" --mode "$worker_mode" --key "$key" \
            --marker-dir "$out_dir/markers" --heartbeat-dir "$out_dir/heartbeats" \
            --steps "$STEPS" --sleep-seconds "$SLEEP_SECONDS" \
            --writer "$WRITER" --heartbeat-sh "$HEARTBEAT_SH" --registry-file "$reg_file" \
            --call-log "$call_log" &
        PIDS[i]=$!
        echo "    agent$i key=$key mode=$mode pid=${PIDS[i]}"
    done

    # --- wait for genuine mid-work progress on the two agents we will kill ---
    for i in 1 2; do
        local marker_file="$out_dir/markers/${KEYS[i]}.markers.jsonl"
        if ! wait_for "agent$i (${MODES[i]}) writes >=$KILL_AFTER_LINES marker lines" "$POLL_TIMEOUT" \
            marker_has_at_least "$marker_file" "$KILL_AFTER_LINES"; then
            RUN_FAILED=1
        fi
    done
    if ! wait_for "agent2 (crash) registry shows in-flight (real progress, before any kill)" "$POLL_TIMEOUT" \
        registry_key_has_event "$reg_file" "${KEYS[2]}" "in-flight"; then
        RUN_FAILED=1
    fi

    # --- kill #1: simulated CAP-SIGNAL (mirrors section 11.4.196(B)'s real
    #     reason-class signature -- an HTTP 429 naming a weekly reset,
    #     never a retry-after, matching limit_class.py's own "cap" class) ---
    echo "  --- simulated CAP-SIGNAL kill: agent1 key=${KEYS[1]} ---"
    local reset_at cap_raw cap_json
    reset_at="$(date -u -d '+1 day' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
    cap_raw="API weekly-limit 429 on alias sc006-fixture-run${run_idx} (resets ${reset_at}); agent killed mid-work; partial artifacts preserved in ${out_dir}/markers/; respawn by description per 11.4.147(e)."
    cap_json="$out_dir/cap_signal_${KEYS[1]}.json"
    python3 - "$cap_json" "$cap_raw" "$reset_at" <<'PYEOF'
import json, sys
out, raw, reset_at = sys.argv[1], sys.argv[2], sys.argv[3]
json.dump(
    {"http_status": 429, "error_code": "rate_limit_error", "retry_after_seconds": None,
     "reset_named": True, "resets_at": reset_at, "raw_signal": raw},
    open(out, "w"), indent=2,
)
PYEOF
    if [ -f "$LIMIT_CLASS_PY" ]; then
        local cap_class_json class_out
        cap_class_json="$out_dir/cap_signal_${KEYS[1]}.class.json"
        python3 "$LIMIT_CLASS_PY" --signal "$cap_raw" --out "$cap_class_json" >/dev/null 2>&1
        class_out="$(python3 -c "import json,sys
try:
    print(json.load(open(sys.argv[1])).get('class','?'))
except Exception:
    print('?')" "$cap_class_json" 2>/dev/null)"
        echo "    (bonus, non-load-bearing authenticity check) limit_class.py classifies our synthetic signal as: $class_out"
    fi
    printf '%s\tattempt\trefused\t%s\n' "$(date -u +%s)" "${KEYS[1]}" >>"$call_log"
    HELIX_AGENT_REGISTRY_FILE="$reg_file" bash "$WRITER" --event refused --key "${KEYS[1]}" \
        --note "sc006 simulated cap-signal kill: ${cap_raw}" >/dev/null 2>&1
    kill -9 "${PIDS[1]}" 2>/dev/null
    wait "${PIDS[1]}" 2>/dev/null

    # --- kill #2: real crash (kill -9, ZERO graceful registry write from
    #     the process itself -- this is the whole point) ---
    echo "  --- CRASH kill (kill -9, zero graceful registry write from the process itself): agent2 key=${KEYS[2]} ---"
    kill -9 "${PIDS[2]}" 2>/dev/null
    wait "${PIDS[2]}" 2>/dev/null

    # --- let the rest complete naturally ---
    for i in $(seq 3 "$NUM_AGENTS"); do
        local done_file="$out_dir/markers/${KEYS[i]}.done"
        if ! wait_for "agent$i natural completion (.done marker)" "$POLL_TIMEOUT" \
            file_exists "$done_file"; then
            RUN_FAILED=1
        fi
        wait "${PIDS[i]}" 2>/dev/null
        local wrc=$?
        if [ "$wrc" != "0" ]; then
            echo "  FAIL: agent$i worker exited non-zero ($wrc)"
            RUN_FAILED=1
        fi
        if ! wait_for "agent$i registry shows complete" "$POLL_TIMEOUT" \
            registry_key_has_event "$reg_file" "${KEYS[i]}" "complete"; then
            RUN_FAILED=1
        fi
    done
    echo "  all $((NUM_AGENTS - 2)) natural-completion agents finished + registered complete"

    # --- independent PROCESS-TABLE confirmation the two killed agents are
    #     genuinely dead (never trust the kill command's own exit status
    #     alone) ---
    sleep 1
    for i in 1 2; do
        if pid_alive "${PIDS[i]}"; then
            echo "  FAIL: agent$i pid=${PIDS[i]} STILL alive after kill -9 + 1s grace period"
            RUN_FAILED=1
        else
            echo "  OK: agent$i pid=${PIDS[i]} confirmed DEAD via kill -0 + ps -p (real process table)"
        fi
    done

    # --- marker files must stop growing after the kill (no zombie
    #     continued progress); and must NEVER have produced .done ---
    for i in 1 2; do
        local marker_file="$out_dir/markers/${KEYS[i]}.markers.jsonl"
        local size1 size2
        size1="$(wc -l <"$marker_file" 2>/dev/null || echo 0)"
        sleep 1
        size2="$(wc -l <"$marker_file" 2>/dev/null || echo 0)"
        if [ "$size1" != "$size2" ]; then
            echo "  FAIL: agent$i marker file grew after kill ($size1 -> $size2) -- process was NOT really terminated"
            RUN_FAILED=1
        else
            echo "  OK: agent$i marker file stable post-kill (${size1} lines, unchanged) -- genuine termination"
        fi
        if [ -f "$out_dir/markers/${KEYS[i]}.done" ]; then
            echo "  FAIL: agent$i (meant to be killed mid-work) unexpectedly produced a .done marker -- kill raced too late"
            RUN_FAILED=1
        else
            echo "  OK: agent$i never produced a .done marker (confirms a genuine mid-work kill, never a disguised natural completion)"
        fi
    done

    # --- independently recomputed registry SEQUENCE checks (never trust
    #     the tool's own derived snapshot) ---
    local seq1 seq2
    seq1="$(registry_events_for_key "$reg_file" "${KEYS[1]}" | tr '\n' ',')"
    seq2="$(registry_events_for_key "$reg_file" "${KEYS[2]}" | tr '\n' ',')"
    if [ "$seq1" = "dispatched,refused," ]; then
        echo "  OK: agent1 (capsignal) registry sequence == dispatched,refused (exact)"
    else
        echo "  FAIL: agent1 registry sequence unexpected: '$seq1'"
        RUN_FAILED=1
    fi
    if [ "$seq2" = "dispatched,in-flight," ]; then
        echo "  OK: agent2 (crash) pre-reap registry sequence == dispatched,in-flight (confirms ZERO graceful write from the crashed process)"
    else
        echo "  FAIL: agent2 pre-reap registry sequence unexpected: '$seq2'"
        RUN_FAILED=1
    fi

    for i in $(seq 3 "$NUM_AGENTS"); do
        local seqN
        seqN="$(registry_events_for_key "$reg_file" "${KEYS[i]}" | tr '\n' ',')"
        if [ "$seqN" != "dispatched,in-flight,complete," ]; then
            echo "  FAIL: agent$i registry sequence unexpected: '$seqN'"
            RUN_FAILED=1
        fi
        if [ ! -f "$out_dir/markers/${KEYS[i]}.done" ]; then
            echo "  FAIL: agent$i registry says complete but no .done marker exists (registry/reality mismatch)"
            RUN_FAILED=1
        fi
    done
    echo "  all natural-completion agents: registry sequence + independent .done marker agree"

    # --- run --reap (the T132 stale-lock reaping half under test) ---
    echo "  --- running agent_registry_writer.sh --reap ---"
    local reap_out reap_rc reap_count
    reap_out="$(HELIX_AGENT_REGISTRY_FILE="$reg_file" bash "$WRITER" --reap \
        --heartbeat-dir "$out_dir/heartbeats" --budget-seconds 5 2>&1)"
    reap_rc=$?
    printf '%s\n' "$reap_out" | sed 's/^/    /'
    if [ "$reap_rc" != "0" ]; then
        echo "  FAIL: --reap exited non-zero ($reap_rc)"
        RUN_FAILED=1
    fi
    reap_count="$(printf '%s\n' "$reap_out" | grep -o 'reap=[0-9]*' | head -n1 | cut -d= -f2)"
    reap_count="${reap_count:-0}"

    seq2="$(registry_events_for_key "$reg_file" "${KEYS[2]}" | tr '\n' ',')"
    if [ "$seq2" = "dispatched,in-flight,suspected-dead," ]; then
        echo "  OK: agent2 (crash) reaped to suspected-dead after --reap"
    else
        echo "  FAIL: agent2 post-reap registry sequence unexpected: '$seq2'"
        RUN_FAILED=1
    fi

    local reap_reason
    reap_reason="$(registry_field_for_event "$reg_file" "${KEYS[2]}" "suspected-dead" "note")"
    case "$reap_reason" in
        *pid-dead*) echo "  OK: reap reason references pid-dead evidence: $reap_reason" ;;
        *) echo "  FAIL: reap reason does not mention pid-dead: '$reap_reason'"; RUN_FAILED=1 ;;
    esac

    local refused_note
    refused_note="$(registry_field_for_event "$reg_file" "${KEYS[1]}" "refused" "note")"
    case "$refused_note" in
        *"cap-signal"*) echo "  OK: agent1 refused note references the simulated cap-signal" ;;
        *) echo "  FAIL: agent1 refused note missing cap-signal reference: '$refused_note'"; RUN_FAILED=1 ;;
    esac

    # --- ZERO-MANUAL-EDITS mechanical proof ---
    local attempts actual expected
    attempts="$(wc -l <"$call_log" 2>/dev/null || echo 0)"
    actual="$(wc -l <"$reg_file" 2>/dev/null || echo 0)"
    expected=$((attempts + reap_count))
    if [ "$actual" -eq "$expected" ]; then
        echo "  OK: zero-manual-edits proof -- writer_invocations.log attempts ($attempts) + reap's own reported reap=$reap_count == actual registry line count ($actual)"
    else
        echo "  FAIL: zero-manual-edits proof MISMATCH -- attempts($attempts) + reap($reap_count) = $expected != actual registry lines ($actual)"
        RUN_FAILED=1
    fi

    # --- ZERO-PHANTOM-OWED-ENTRIES proof ---
    local phantom=0
    for i in $(seq 1 "$NUM_AGENTS"); do
        local lastN
        lastN="$(registry_events_for_key "$reg_file" "${KEYS[i]}" | tail -n1)"
        case "$lastN" in
            complete | refused | suspected-dead) : ;;
            *)
                echo "  FAIL: agent$i final registry status is NON-TERMINAL: '$lastN' (phantom owed entry)"
                phantom=1
                RUN_FAILED=1
                ;;
        esac
    done
    if [ "$phantom" -eq 0 ]; then
        echo "  OK: zero phantom owed entries -- every one of the $NUM_AGENTS keys resolved to a terminal state (complete/refused/suspected-dead)"
    fi

    python3 - "$out_dir/summary.json" "$run_id" "$RUN_FAILED" "$NUM_AGENTS" "$attempts" "$reap_count" "$actual" <<'PYEOF' 2>/dev/null
import json, sys
out, run_id, failed, n, attempts, reap_count, actual = sys.argv[1:8]
json.dump(
    {
        "run_id": run_id, "failed": bool(int(failed)), "num_agents": int(n),
        "writer_attempts": int(attempts), "reap_internal_writes": int(reap_count),
        "final_registry_lines": int(actual),
    },
    open(out, "w"), indent=2,
)
PYEOF

    return "$RUN_FAILED"
}

# =============================================================================
# main
# =============================================================================
OVERALL_RC=0
for run_idx in $(seq 1 "$RUNS"); do
    echo "=== SC-006 exercise: RUN $run_idx of $RUNS (sequential, exclusive dispatcher use) ==="
    if run_once "$run_idx"; then
        echo "=== RUN $run_idx: PASS ==="
    else
        echo "=== RUN $run_idx: FAIL (see FAIL lines above) ==="
        OVERALL_RC=1
    fi
    echo
done

if [ "$OVERALL_RC" -eq 0 ]; then
    echo "SC006_EXERCISE: ALL $RUNS RUN(S) PASSED"
else
    echo "SC006_EXERCISE: AT LEAST ONE RUN FAILED"
fi
exit "$OVERALL_RC"
