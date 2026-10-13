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
# T140 ROUND 1 FIX B1 (2026-09-30, blocking finding): the pre-fix version
# of this file modelled its "simulated cap signal" kill as a terminal
# `refused` write -- which the review correctly identified as a
# registry-vs-ground-truth contradiction (AR-004's `refused` means "never
# ran, not owed", but the pre-fix worker really wrote >=2 marker-file
# lines of genuine mid-work progress first) that also silently dropped a
# real limit-caused crash out of the owed set (the exact RC-01 work-loss
# class this whole registry mechanism exists to prevent). Fixed per the
# review's own three-part direction: (1) the cap-kill role now goes
# through a REAL dispatched -> in-flight -> crashed sequence, with the
# ORCHESTRATOR (never the worker) issuing the terminal
# `--event crashed --limit-class cap --limit-raw <signal>` write once
# genuine in-flight progress is confirmed (contract AR-005; needs I1's
# now-landed `--limit-class`/`--limit-raw` flags); (2) a genuinely
# BLOCKED agent (dispatched-only, refused before any real work starts)
# and a genuinely STILL-RUNNING agent (deliberately never waited for, so
# it is legitimately still `in-flight` -- and therefore still owed -- at
# the exercise's own final snapshot) were added, matching the contract's
# own `ar_six_agent_exercise` fixture composition exactly: 2 complete, 1
# quota-crashed, 1 process-killed (kill -9, reaped to suspected-dead), 1
# blocked/refused, 1 still-running == 6 agents, owed = the crashed-class
# 2 + the still-running 1 (data-model.md section 9.1: `crashed` AND
# `suspected-dead` are BOTH owed, `refused` and `complete` are NOT); (3)
# the old "zero phantom owed" check -- which wrongly treated `refused`
# AND `suspected-dead` as equally "terminal", conflating "reaped" with
# "not owed" -- is replaced below by a genuine cross-check: this script's
# own hand-derived GROUND-TRUTH owed set (built from the roles it itself
# assigned, never re-read from the registry) compared against the
# WRITER's own separately-derived owed classification, read fresh from
# `agent_registry.status.tsv` (AR-007, the writer's own atomically-
# rewritten per-key latest-status snapshot -- a genuinely SEPARATE
# artefact from the raw JSONL this script already independently
# recomputes sequences from) via a small INDEPENDENTLY-authored
# classifier applying data-model.md section 9.1's closed owed-vocabulary
# rule fresh from this file (never importing or calling into the
# writer's own python, Producer != Verifier, section 11.4.240).
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
# ZERO-PHANTOM-OWED-ENTRIES PROOF (T140 Round 1 fix B1 -- see the fix note
# above): every one of this run's own generated keys must independently
# resolve to its CORRECT registry status by the end of the run -- a key
# left reading raw `dispatched`/`in-flight` with no live process AND no
# reap having resolved it (the still-running role is the one deliberate,
# explicitly-carved-out exception: it IS legitimately still `in-flight`,
# and still genuinely alive, at the run's own final snapshot) is exactly
# the "phantom owed" leak T132's --reap exists to prevent. This is now
# proven by comparing TWO independently-derived owed sets rather than by
# eyeballing which raw event names "look terminal": (1) the GROUND-TRUTH
# owed set this script itself computes from the roles it assigned each
# key (never read back from the registry); (2) the WRITER's own derived
# owed set, read fresh from its own `agent_registry.status.tsv` snapshot
# (AR-007) and classified by data-model.md section 9.1's closed
# vocabulary (owed: dispatched|in-flight|progress|suspected-dead|crashed|
# respawned; NOT owed: complete|refused) -- authored fresh in this file,
# never by calling into the writer's own python (Producer != Verifier,
# section 11.4.240). A mismatch either way (a key the ground truth says
# is owed that the writer's snapshot does not, or vice versa) is reported
# as a genuine FAIL naming the key and the direction of the mismatch.
#
# Usage:
#   sc006_exercise.sh [--num-agents <n>] [--steps <n>] [--sleep-seconds <n>]
#       [--kill-after-lines <n>] [--poll-timeout <seconds>]
#       [--out-dir-base <dir>] [--runs <n>]
#
# Defaults: --num-agents 6 (>=6 enforced -- the contract's own
#   `ar_six_agent_exercise` fixture composition: agent1=quota-crashed,
#   agent2=process-killed [kill -9, reaped to suspected-dead],
#   agent3=blocked/refused, agent4=still-running, agents5-6=natural-
#   complete; a caller-supplied --num-agents > 6 keeps those same four
#   fixed special roles on agents1-4 and adds more natural-complete
#   agents from agent5 onward), --steps 6, --sleep-seconds 1,
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

NUM_AGENTS=6
STEPS=6
SLEEP_SECONDS=1
KILL_AFTER_LINES=2
POLL_TIMEOUT=30
RUNS=2
OUT_DIR_BASE="$ROOT/qa-results/fastcycle/sc006"
# T140 Round 1 fix (B1): the still-running role's own --steps, deliberately
# far larger than any realistic exercise runtime (with the default 1s
# --sleep-seconds this is >100000s of would-be run time) so it can NEVER
# naturally reach its own `.done`/`complete` before this exercise takes
# its final snapshot and cleans it up -- never a race, by construction.
STILL_RUNNING_STEPS=100000

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

registry_limit_signal_field_for_key() {
    # $1 = reg file, $2 = key, $3 = event name to match (typically
    # "crashed"), $4 = nested field name inside limit_signal ("class" or
    # "raw"). Prints the LAST matching row's limit_signal[$4] value
    # (empty if none/absent -- data-model.md section 9.1's limit_signal
    # object, AR-005). T140 Round 1 fix (B1): the cap-kill role now writes
    # a real `crashed` row carrying this nested object; this helper reads
    # it the SAME independent-recomputation-from-raw-JSONL way every
    # other reader in this file does (never via the writer's own code).
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
                sig = row.get("limit_signal", {})
                if isinstance(sig, dict):
                    val = sig.get(field, "")
except FileNotFoundError:
    pass
print(val)
PYEOF
}

writer_status_owed_keys() {
    # $1 = writer's own derived status.tsv snapshot path (AR-007 --
    # `docs/requests/agent_registry.status.tsv`'s per-run equivalent,
    # written by agent_registry_writer.sh itself, atomically, after every
    # append -- see writer's own SNAP_FILE derivation from
    # HELIX_AGENT_REGISTRY_FILE). Prints one OWED key per line, applying
    # data-model.md section 9.1's CLOSED owed-vocabulary rule fresh in
    # THIS file -- never by importing or calling into the writer's own
    # python (Producer != Verifier, section 11.4.240): owed statuses =
    # {dispatched, in-flight, progress, suspected-dead, crashed,
    # respawned}; NOT owed = {complete, refused}. A status outside BOTH
    # closed sets is reported to stderr and conservatively treated as
    # OWED (section 11.4.201's conservative-safe default on an
    # unresolvable signal -- silently dropping an unrecognized status
    # from the owed set would be the exact false-negative this whole
    # mechanism exists to prevent).
    python3 - "$1" <<'PYEOF'
import sys
snap = sys.argv[1]
OWED = {"dispatched", "in-flight", "progress", "suspected-dead", "crashed", "respawned"}
NOT_OWED = {"complete", "refused"}
try:
    with open(snap, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 2:
                continue
            key, status = fields[0], fields[1]
            if status in OWED:
                print(key)
            elif status in NOT_OWED:
                pass
            else:
                print(f"UNRECOGNIZED-STATUS-TREATED-AS-OWED: key={key} status={status}", file=sys.stderr)
                print(key)
except FileNotFoundError:
    pass
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

    # --- assign roles (T140 Round 1 fix B1; contract's own
    #     ar_six_agent_exercise fixture): agent1=quota-crashed (real
    #     429/cap kill, terminal `crashed`+limit_signal), agent2=process-
    #     killed (kill -9, zero graceful write, reaped to suspected-dead),
    #     agent3=blocked (dispatched-only, terminal `refused`, never
    #     in-flight), agent4=still-running (deliberately never waited for
    #     -- legitimately still `in-flight`, and still owed, at this
    #     run's own final snapshot), agents5..N=natural-complete ---
    local -a KEYS=()
    local -a MODES=()
    local -a PIDS=()
    local i
    for i in $(seq 1 "$NUM_AGENTS"); do
        KEYS[i]="$(gen_key "sc006|$run_id|agent$i|$RANDOM|$(date -u +%s%N 2>/dev/null || date -u +%s)")"
        case "$i" in
            1) MODES[i]="quota" ;;
            2) MODES[i]="crash" ;;
            3) MODES[i]="blocked" ;;
            4) MODES[i]="still-running" ;;
            *) MODES[i]="natural" ;;
        esac
    done

    echo "  spawning $NUM_AGENTS fixture agents: 1 quota-crashed (429/cap), 1 process-killed (kill -9), 1 blocked/refused, 1 still-running, $((NUM_AGENTS - 4)) natural-complete"

    for i in $(seq 1 "$NUM_AGENTS"); do
        local key="${KEYS[i]}" mode="${MODES[i]}" worker_mode="cycle" steps="$STEPS"
        [ "$mode" = "blocked" ] && worker_mode="blocked"
        [ "$mode" = "still-running" ] && steps="$STILL_RUNNING_STEPS"
        bash "$WORKER" --mode "$worker_mode" --key "$key" \
            --marker-dir "$out_dir/markers" --heartbeat-dir "$out_dir/heartbeats" \
            --steps "$steps" --sleep-seconds "$SLEEP_SECONDS" \
            --writer "$WRITER" --heartbeat-sh "$HEARTBEAT_SH" --registry-file "$reg_file" \
            --call-log "$call_log" &
        PIDS[i]=$!
        echo "    agent$i key=$key mode=$mode pid=${PIDS[i]}"
    done

    # --- wait for genuine mid-work progress on the two agents we will
    #     kill (1, 2) and the one we will deliberately never wait to
    #     complete (4) -- all three are `cycle`-mode real background
    #     work, so all three write real marker-file progress + a real
    #     registry `in-flight` before this exercise does anything else to
    #     them ---
    for i in 1 2 4; do
        local marker_file="$out_dir/markers/${KEYS[i]}.markers.jsonl"
        if ! wait_for "agent$i (${MODES[i]}) writes >=$KILL_AFTER_LINES marker lines" "$POLL_TIMEOUT" \
            marker_has_at_least "$marker_file" "$KILL_AFTER_LINES"; then
            RUN_FAILED=1
        fi
        if ! wait_for "agent$i (${MODES[i]}) registry shows in-flight (real progress, before any kill/observation)" "$POLL_TIMEOUT" \
            registry_key_has_event "$reg_file" "${KEYS[i]}" "in-flight"; then
            RUN_FAILED=1
        fi
    done

    # --- kill #1: real QUOTA/CAP-SIGNAL crash (T140 Round 1 fix B1: a
    #     genuine in-flight -> crashed transition, contract AR-005 -- the
    #     ORCHESTRATOR, never the worker, issues this write, mirroring
    #     exactly how every other role's terminal write below is always
    #     issued by the orchestrator) ---
    echo "  --- QUOTA/CAP-SIGNAL crash: agent1 key=${KEYS[1]} (real in-flight -> crashed, contract AR-005) ---"
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
    printf '%s\tattempt\tcrashed\t%s\n' "$(date -u +%s)" "${KEYS[1]}" >>"$call_log"
    HELIX_AGENT_REGISTRY_FILE="$reg_file" bash "$WRITER" --event crashed --key "${KEYS[1]}" \
        --limit-class cap --limit-raw "$cap_raw" \
        --note "sc006 real quota/cap-signal crash mid-work" >/dev/null 2>&1
    kill -9 "${PIDS[1]}" 2>/dev/null
    wait "${PIDS[1]}" 2>/dev/null

    # --- kill #2: real crash (kill -9, ZERO graceful registry write from
    #     the process itself -- this is the whole point) ---
    echo "  --- CRASH kill (kill -9, zero graceful registry write from the process itself): agent2 key=${KEYS[2]} ---"
    kill -9 "${PIDS[2]}" 2>/dev/null
    wait "${PIDS[2]}" 2>/dev/null

    # --- resolve #3: BLOCKED (T140 Round 1 fix B1: a genuinely
    #     blocked/refused-at-dispatch agent never starts real background
    #     work -- the worker itself already exited immediately after its
    #     one `dispatched` write, see sc006_agent_worker.sh's `blocked`
    #     mode; the orchestrator waits for that exit, confirms it was
    #     clean, then writes the terminal `refused`, satisfying V-AR-2's
    #     "[] or ['dispatched']" ordering precondition honestly) ---
    echo "  --- BLOCKED (refused-at-dispatch, no real work ever started): agent3 key=${KEYS[3]} ---"
    wait "${PIDS[3]}" 2>/dev/null
    local blocked_wrc=$?
    if [ "$blocked_wrc" != "0" ]; then
        echo "  FAIL: agent3 (blocked) worker exited non-zero ($blocked_wrc)"
        RUN_FAILED=1
    fi
    printf '%s\tattempt\trefused\t%s\n' "$(date -u +%s)" "${KEYS[3]}" >>"$call_log"
    HELIX_AGENT_REGISTRY_FILE="$reg_file" bash "$WRITER" --event refused --key "${KEYS[3]}" \
        --note "sc006 simulated blocked/refused-at-dispatch (e.g. permission-denied/prompt-too-long); no real work ever started" >/dev/null 2>&1

    # --- let the rest complete naturally (agent4/still-running is
    #     DELIBERATELY excluded from this loop -- see below) ---
    for i in $(seq 5 "$NUM_AGENTS"); do
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
    echo "  all $((NUM_AGENTS - 4)) natural-completion agents finished + registered complete"

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

    # --- independent PROCESS-TABLE confirmation agent4 (still-running) is
    #     genuinely STILL alive right now -- the positive-evidence
    #     counterpart to the pid_alive checks above, proving this role is
    #     a real, still-in-progress background process and not a
    #     disguised already-finished or already-dead one ---
    if pid_alive "${PIDS[4]}"; then
        echo "  OK: agent4 (still-running) pid=${PIDS[4]} confirmed genuinely ALIVE (kill -0 + ps -p, real process table)"
    else
        echo "  FAIL: agent4 (still-running) pid=${PIDS[4]} unexpectedly DEAD (should still be genuinely mid-work)"
        RUN_FAILED=1
    fi

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
    local seq1 seq2 seq3 seq4
    seq1="$(registry_events_for_key "$reg_file" "${KEYS[1]}" | tr '\n' ',')"
    seq2="$(registry_events_for_key "$reg_file" "${KEYS[2]}" | tr '\n' ',')"
    seq3="$(registry_events_for_key "$reg_file" "${KEYS[3]}" | tr '\n' ',')"
    seq4="$(registry_events_for_key "$reg_file" "${KEYS[4]}" | tr '\n' ',')"
    if [ "$seq1" = "dispatched,in-flight,crashed," ]; then
        echo "  OK: agent1 (quota-crashed) registry sequence == dispatched,in-flight,crashed (exact, contract AR-005)"
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
    if [ "$seq3" = "dispatched,refused," ]; then
        echo "  OK: agent3 (blocked) registry sequence == dispatched,refused (exact, contract AR-004; V-AR-2 ordering satisfied honestly -- no real work ever happened first)"
    else
        echo "  FAIL: agent3 registry sequence unexpected: '$seq3'"
        RUN_FAILED=1
    fi
    if [ "$seq4" = "dispatched,in-flight," ]; then
        echo "  OK: agent4 (still-running) pre-reap registry sequence == dispatched,in-flight (legitimately mid-work, never completed nor killed)"
    else
        echo "  FAIL: agent4 pre-reap registry sequence unexpected: '$seq4'"
        RUN_FAILED=1
    fi

    for i in $(seq 5 "$NUM_AGENTS"); do
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

    # --- agent4 (still-running) must be LEFT ALONE by --reap: it is
    #     genuinely alive with a fresh, advancing heartbeat well inside
    #     the 5s budget (T132's own reap discipline never reaps a
    #     genuinely-alive key, section 9.2), so its pre-reap sequence must
    #     be BYTE-IDENTICAL post-reap -- proving both that reap correctly
    #     distinguished it from agent2's genuinely-stale key, and that
    #     this role really is a real, still-progressing process ---
    seq4="$(registry_events_for_key "$reg_file" "${KEYS[4]}" | tr '\n' ',')"
    if [ "$seq4" = "dispatched,in-flight," ]; then
        echo "  OK: agent4 (still-running) post-reap registry sequence STILL == dispatched,in-flight (reap correctly left a genuinely-alive key untouched, section 9.2)"
    else
        echo "  FAIL: agent4 post-reap registry sequence unexpected: '$seq4' (reap should never touch a genuinely-alive key)"
        RUN_FAILED=1
    fi

    local reap_reason
    reap_reason="$(registry_field_for_event "$reg_file" "${KEYS[2]}" "suspected-dead" "note")"
    case "$reap_reason" in
        *pid-dead*) echo "  OK: reap reason references pid-dead evidence: $reap_reason" ;;
        *) echo "  FAIL: reap reason does not mention pid-dead: '$reap_reason'"; RUN_FAILED=1 ;;
    esac

    # --- agent1's real `crashed` row must carry the AR-005 limit_signal
    #     object honestly (class=cap, the verbatim raw signal text) ---
    local crashed_limit_class crashed_limit_raw
    crashed_limit_class="$(registry_limit_signal_field_for_key "$reg_file" "${KEYS[1]}" "crashed" "class")"
    crashed_limit_raw="$(registry_limit_signal_field_for_key "$reg_file" "${KEYS[1]}" "crashed" "raw")"
    if [ "$crashed_limit_class" = "cap" ]; then
        echo "  OK: agent1 crashed row's limit_signal.class == cap (contract AR-005)"
    else
        echo "  FAIL: agent1 crashed row's limit_signal.class unexpected: '$crashed_limit_class'"
        RUN_FAILED=1
    fi
    case "$crashed_limit_raw" in
        *"weekly-limit"*) echo "  OK: agent1 crashed row's limit_signal.raw carries the verbatim weekly-limit signal" ;;
        *) echo "  FAIL: agent1 crashed row's limit_signal.raw missing weekly-limit reference: '$crashed_limit_raw'"; RUN_FAILED=1 ;;
    esac

    # --- agent3's refused note must reference the blocked/refused-at-
    #     dispatch reason, never the (now agent1-owned) cap-signal one ---
    local blocked_note
    blocked_note="$(registry_field_for_event "$reg_file" "${KEYS[3]}" "refused" "note")"
    case "$blocked_note" in
        *"blocked"*) echo "  OK: agent3 refused note references the blocked/refused-at-dispatch reason" ;;
        *) echo "  FAIL: agent3 refused note missing blocked reference: '$blocked_note'"; RUN_FAILED=1 ;;
    esac

    # --- cleanup: agent4 (still-running) is killed ONLY NOW, strictly
    #     AFTER every assertion above about its genuinely-alive/
    #     legitimately-still-owed state has already been captured -- this
    #     kill changes nothing about the registry (the key's last event
    #     stays exactly `in-flight` forever in this run's own frozen
    #     record) and exists purely so this exercise never leaks a
    #     background process past its own run ---
    kill -9 "${PIDS[4]}" 2>/dev/null
    wait "${PIDS[4]}" 2>/dev/null
    sleep 1
    if pid_alive "${PIDS[4]}"; then
        echo "  FAIL: agent4 (still-running) pid=${PIDS[4]} STILL alive after cleanup kill -9 + 1s grace period"
        RUN_FAILED=1
    else
        echo "  OK: agent4 (still-running) pid=${PIDS[4]} confirmed DEAD after cleanup kill (no leaked background process)"
    fi

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

    # --- ZERO-PHANTOM-OWED-ENTRIES proof (T140 Round 1 fix B1): compare
    #     this script's own GROUND-TRUTH owed set (built from the roles
    #     it itself assigned above, never read back from the registry)
    #     against the WRITER's own independently-derived owed
    #     classification, read fresh from its own agent_registry.
    #     status.tsv snapshot (AR-007) -- never by re-deriving "terminal"
    #     from a loose case-statement over raw event names (the pre-fix
    #     bug: that approach could not tell "owed but reaped"
    #     (suspected-dead) apart from "never owed" (refused), and had no
    #     way to represent "still owed and legitimately still in-flight"
    #     (agent4) at all). ---
    local ground_truth_owed writer_derived_owed snap_file
    snap_file="${reg_file%.jsonl}.status.tsv"
    ground_truth_owed="$(printf '%s\n' "${KEYS[1]}" "${KEYS[2]}" "${KEYS[4]}" | sort)"
    writer_derived_owed="$(writer_status_owed_keys "$snap_file" | sort)"
    if [ "$ground_truth_owed" = "$writer_derived_owed" ]; then
        echo "  OK: ground-truth owed set == writer's own derived owed set (agent1 quota-crashed + agent2 suspected-dead + agent4 still-running; agent3 blocked and the $((NUM_AGENTS - 4)) natural-complete agents correctly excluded)"
    else
        echo "  FAIL: owed-set MISMATCH between ground truth and the writer's own derived snapshot ($snap_file)"
        local only_in_ground_truth only_in_writer
        only_in_ground_truth="$(comm -23 <(printf '%s\n' "$ground_truth_owed") <(printf '%s\n' "$writer_derived_owed"))"
        only_in_writer="$(comm -13 <(printf '%s\n' "$ground_truth_owed") <(printf '%s\n' "$writer_derived_owed"))"
        [ -n "$only_in_ground_truth" ] && echo "    MISSING from the writer's owed set (should be owed but isn't -- WORK-LOSS): $only_in_ground_truth"
        [ -n "$only_in_writer" ] && echo "    EXTRA in the writer's owed set (should NOT be owed but is): $only_in_writer"
        RUN_FAILED=1
    fi

    python3 - "$out_dir/summary.json" "$run_id" "$RUN_FAILED" "$NUM_AGENTS" "$attempts" "$reap_count" "$actual" <<'PYEOF' 2>/dev/null
import json, sys
out, run_id, failed, n, attempts, reap_count, actual = sys.argv[1:8]
json.dump(
    {
        "run_id": run_id, "failed": bool(int(failed)), "num_agents": int(n),
        "writer_attempts": int(attempts), "reap_internal_writes": int(reap_count),
        "final_registry_lines": int(actual),
        "roles": {"agent1": "quota-crashed", "agent2": "process-killed",
                   "agent3": "blocked", "agent4": "still-running",
                   "agent5..N": "natural-complete"},
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
