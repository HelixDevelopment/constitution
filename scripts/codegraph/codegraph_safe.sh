#!/usr/bin/env bash
# ============================================================================
# codegraph_safe.sh — the ONLY sanctioned entry for CodeGraph init / index / sync
# ============================================================================
# Purpose
#   Make the 2026-09-23 CodeGraph failure modes impossible by construction:
#   (1) stock init/index on a fresh DB drops the FK child-key indexes in the
#       bulk window -> INSERT OR REPLACE cascades scan 24M-row tables (full-scan hazard):
#       bulk ops ONLY run through the patched runner from fk_index_patch.py, or
#       through stock AFTER fk_cascade_probe.py proves stock safe; a REFUSED
#       runner is NEVER silently replaced by stock;
#   (2) `codegraph … || true` masking: every failure is a non-zero exit here;
#   (3) a stall that looks alive: index_watch.py proves progress, a STALL is
#       exit 7;
#   (4) unbounded growth filling the volume: disk_tripwire.sh SIGSTOPs the
#       indexer below --tripwire-min-gib (exit 8) + a host preflight;
#   (5) the fix vanishing after an upgrade: the runner is re-derived per stock
#       version and its receipt/version are checked on every bulk run;
#   (6) the v1.6.0 stale-lock bug (a lock older than 2 min is deleted regardless
#       of PID liveness): this wrapper checks the lock holder's REAL /proc argv
#       and refuses while it lives, whatever the lock's age; a lock whose holder
#       is provably dead is reaped ONLY with --reap-dead-lock, and logged;
#   (7) the 2026-09-24 misclassification: `sync` on ANY populated DB used to run
#       STOCK + FOREGROUND (no fkidx1/resolve1 patches, no watcher, no tripwire) even
#       with ~40M pending unresolved refs, and died on the caller's timeout. `sync`
#       is now BULK (patched runner, detached supervisor, watcher, tripwire) when the
#       DB is missing/empty/unreadable, when --bulk is given, when the number of
#       status='pending' unresolved_refs is >= the threshold (default 150000, the
#       resolver-pool.js default), or when that number cannot be evaluated cheaply
#       (UNKNOWN is never read as "small"). The count is a BOUNDED probe (an index
#       range read of at most threshold+1 entries, never COUNT(*) on a 47M-row table)
#       and every sync prints `sync classification: BULK|INCREMENTAL (reason=...)`.
# Usage
#   codegraph_safe.sh [options] <op>
#   ops (writers): init | index | sync      ops (readers): status | verify
#   ops (other):   preflight | unlock
#   options:
#     --project DIR          project root (default: git toplevel of $PWD, else $PWD)
#     --bulk                 force the supervised bulk path for `sync` (writers only;
#                            init/index are always bulk; exit 2 with a read op)
#     --pending-threshold N  sync is BULK when pending unresolved refs >= N, N >= 1
#                            (default $CG_SAFE_PENDING_BULK_MIN, else 150000)
#     --patches IDS          comma list of runner patches to apply (default
#                            $CG_SAFE_PATCHES, else fkidx1,resolve1 — the VALIDATED subset,
#                            see below); `all` = every registered patch. fkidx1 must be
#                            in the set (the receipt gate requires it, else exit 5)
#     --wait                 block until a detached bulk run finishes (poll)
#     --poll-s N             --wait poll period, seconds (default 10)
#     --watch-interval N     index_watch.py sample period, seconds (default 60)
#     --stall-min M          minutes without progress that count as a STALL (default 10)
#     --tripwire-min-gib N   pause the indexer below N GiB free, N in [5,500] (default 20)
#     --tripwire-interval N  tripwire sample period, seconds (default 30)
#     --reap-dead-lock       remove a lock whose holder is provably not a live
#                            codegraph process (decision logged); never a live one
#     --expected-count N --tolerance-pct P   verify files count within P% of N
#     --status-doc FILE      ledger file (default <project>/docs/codegraph/Status.md;
#                            absent -> SKIP-with-reason, run not failed)
#     --scope-baseline FILE  scope classes (default scope_baseline.txt beside this script)
#     --scope-exceptions FILE  narrow per-exact-path exceptions for the secret_named/
#                            secrets_dir heuristic classes ONLY (default
#                            scope_exceptions.txt beside this script; absent file ->
#                            no exceptions, the strictest posture — never an error)
# Patch set: only fkidx1 (oracle fk_cascade_probe.py + test_unit_safe.sh) and resolve1
#   (tests/test_resolve1*.sh + mutations) have tests. lockfix1 and datafrag1 have ZERO
#   tests, so a multi-hour bulk job must not silently run them: they are opt-in via
#   --patches / CG_SAFE_PATCHES. (lockfix1 is also redundant here: this wrapper already
#   refuses to start while a live codegraph holds the lock.) The default runner key is
#   <version>-fkidx1-resolve1.
# Inputs (environment)
#   CODEGRAPH_BIN            stock CLI (default: `codegraph` on PATH)
#   CG_SAFE_PENDING_BULK_MIN default sync BULK threshold, pending refs (default 150000)
#   CG_SAFE_PATCHES          default --patches value (default fkidx1,resolve1)
#   CG_SAFE_PENDING_PROBE_BUDGET_S  wall-clock budget of the pending probe (default 30)
#   CG_SAFE_PATCH_TOOL       default fk_index_patch.py beside this script
#   CG_SAFE_PROBE_TOOL       default fk_cascade_probe.py beside this script
#   CG_SAFE_MIN_THREAD_HEADROOM  default 1024 free thread slots (§12.12)
#   TEST-ONLY overrides (they can only make a resource look SCARCER, never richer):
#   CG_SAFE_TEST_FREE_BYTES     free = min(measured, value)
#   CG_SAFE_TEST_MEMAVAIL_KB    MemAvailable = min(measured, value)
#   CG_SAFE_TEST_THREADS_USED   threads used = max(measured, value)
# Outputs
#   stdout/stderr report; <project>/.codegraph/index_runs/:
#     index_<UTC>.log (verbose indexer log), run_<id>.pids, run_<id>.result,
#     watch_<id>.log, tripwire_<id>.log, supervisor_<id>.log, lock_reap.log
#   ledger entry appended to the Status doc when it exists
# Exit codes
#   0 success / verified            1 indexer failed or verification FAILED
#                                     (verification includes pending_zero: no
#                                     status='pending' refs may remain; and index_state
#                                     complete — see VERIFY_NOTE version_stamp in the
#                                     helper for the known interrupted-then-synced gap)
#   2 usage error / unknown op      3 live writer (lock holder, /proc scan) or
#                                     wrapper flock held by another launcher
#   4 stale lock present, not reaped (re-run with --reap-dead-lock)
#   5 safe runner unavailable (patch REFUSED / probe not SAFE / receipt or
#     version mismatch) — stock is NEVER used as a fallback
#   6 host preflight failed (disk / memory / thread headroom)
#   7 STALL detected by index_watch.py (indexer left running for inspection)
#   8 disk tripwire tripped (indexer SIGSTOPped, resume with kill -CONT <pid>)
# Side effects
#   creates <project>/.codegraph/{index_runs/,.helix_index.flock}; runs the
#   indexer detached (own session) with watcher + tripwire; may remove a
#   provably-dead lock (--reap-dead-lock); appends to the ledger. An INCREMENTAL
#   sync (small backlog only) runs stock in the foreground under the flock.
# Dependencies
#   bash, flock, setsid, nohup, df, python3, codegraph_safe_helper.py,
#   index_watch.py, disk_tripwire.sh, fk_index_patch.py, fk_cascade_probe.py
# Cross-references
#   docs/scripts/codegraph_safe.md, tests/run_all.sh, codegraph_guard.sh,
#   the 2026-09-23 bulk-window incident; tests/test_unit_safe.sh U31-U43 + tests/test_bulk_classify_mutations.sh; constitution §11.4.78 / §11.4.80 / §11.4.174 / §11.4.180 /
#   §11.4.201 / §11.4.232 / §11.4.263 / §11.4.273 / §12.6 / §12.12
# ============================================================================
set -u
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
HERE="$(dirname "$SELF")"
HELPER="$HERE/codegraph_safe_helper.py"
WATCH="$HERE/index_watch.py"
TRIPWIRE="$HERE/disk_tripwire.sh"
PATCH_TOOL="${CG_SAFE_PATCH_TOOL:-$HERE/fk_index_patch.py}"
PROBE_TOOL="${CG_SAFE_PROBE_TOOL:-$HERE/fk_cascade_probe.py}"
STOCK="${CODEGRAPH_BIN:-codegraph}"
GIB=1073741824

say() { printf 'codegraph_safe: %s\n' "$*"; }
die() { local c="$1"; shift; printf 'codegraph_safe: %s\n' "$*" >&2; exit "$c"; }

run_tool() {
    # run_tool <file> <args...> — execute directly when executable, else via its interpreter
    local f="$1"; shift
    if [ -x "$f" ]; then "$f" "$@"; else
        case "$f" in *.py) python3 "$f" "$@" ;; *) bash "$f" "$@" ;; esac
    fi
}

# ============================================================ supervisor mode ==
# Invoked detached by the launcher (own session) with its state in CG_SV_* env.
# Holds the inherited wrapper flock (fd 9) for the whole bulk op.
supervise() {
    local P="$CG_SV_PROJECT" RUNS="$CG_SV_RUNS" ID="$CG_SV_ID" LOG="$CG_SV_LOG"
    local PIDS="$RUNS/run_$ID.pids" RES="$RUNS/run_$ID.result"
    local WLOG="$RUNS/watch_$ID.log" TWLOG="$RUNS/tripwire_$ID.log"
    local t0 t1 IDX holder i st rc code summary
    t0=$(date +%s)
    echo "supervisor=$$" >> "$PIDS"
    # shellcheck disable=SC2086
    "$CG_SV_RUNNER" $CG_SV_ARGS >> "$LOG" 2>&1 9>&- &
    IDX=$!
    echo "indexer_launch=$IDX" >> "$PIDS"
    holder=""
    i=0
    while [ "$i" -lt 300 ]; do
        local lp
        lp="$(head -c 32 "$P/.codegraph/codegraph.lock" 2>/dev/null | tr -d ' \n\r')"
        case "$lp" in ''|*[!0-9]*) ;; *)
            if [ "$lp" -gt 1 ] && python3 "$HELPER" identity "$lp" >/dev/null 2>&1; then holder="$lp"; break; fi ;;
        esac
        st="$(pstate "$IDX")"; [ "$st" = "-" ] || [ "$st" = "Z" ] && break
        sleep 0.1; i=$((i + 1))
    done
    if [ -z "$holder" ] && python3 "$HELPER" identity "$IDX" >/dev/null 2>&1; then holder="$IDX"; fi
    echo "indexer=${holder:-none}" >> "$PIDS"
    if [ -n "$holder" ]; then
        python3 "$WATCH" --project "$P" --interval "$CG_SV_WATCH_INT" --stall-min "$CG_SV_STALL_MIN" >> "$WLOG" 2>&1 9>&- &
        echo "watcher=$!" >> "$PIDS"
        bash "$TRIPWIRE" --pid "$holder" --dir "$P/.codegraph" --min-gib "$CG_SV_TW_GIB" \
            --interval "$CG_SV_TW_INT" --log "$TWLOG" >/dev/null 2>&1 9>&- &
        echo "tripwire=$!" >> "$PIDS"
    else
        echo "WARN: no live indexer identity observed; watcher/tripwire not armed" >> "$LOG"
    fi
    while :; do
        st="$(pstate "$IDX")"
        { [ "$st" = "-" ] || [ "$st" = "Z" ]; } && break
        if [ -f "$TWLOG.TRIPPED" ]; then
            write_result "$RES" 8 "TRIPPED: free disk below ${CG_SV_TW_GIB} GiB — indexer pid=${holder} SIGSTOPped (resume: kill -CONT ${holder}); see $TWLOG"
            return 0
        fi
        if tail -n 1 "$WLOG" 2>/dev/null | grep -q ' STALL_'; then
            write_result "$RES" 7 "STALL: index_watch.py reports no progress for ${CG_SV_STALL_MIN} min — indexer pid=${holder} left running for inspection: $(tail -n 1 "$WLOG")"
            return 0
        fi
        sleep 1
    done
    wait "$IDX"; rc=$?
    t1=$(date +%s)
    local vout code_v scope_out code_s rep sf
    rep="$(grep -aoE 'Indexed [0-9,]+ files' "$LOG" | tail -n 1 | tr -dc '0-9')"
    sf="$(stock_status_files "$P")"
    vout="$(python3 "$HELPER" verify "$P" --reported "$rep" --status-files "$sf" $CG_SV_EXPECT_ARGS 2>&1)"; code_v=$?
    scope_out="$(python3 "$HELPER" scope "$P" "$CG_SV_BASELINE" "$CG_SV_SCOPE_EXCEPTIONS" 2>&1)"; code_s=$?
    code=0
    [ "$rc" -eq 0 ] || code=1
    [ "$code_v" -eq 0 ] || code=1
    [ "$code_s" -eq 0 ] || code=1
    local verdict=PASS; [ "$code" -eq 0 ] || verdict=FAIL
    local files; files="$(printf '%s\n' "$vout" | sed -n 's/^VERIFY_FILES //p')"
    local ledger
    ledger="$(ledger_append "$CG_SV_STATUS_DOC" "$ID" "$CG_SV_OP" "$CG_SV_VERSION" "$CG_SV_RUNNER" "$verdict" \
        "files=${files:-?} reported=${rep:-?} status_files=${sf:-?} indexer_rc=$rc" "index_s=$((t1 - t0))")"
    summary="$(printf 'RUN %s op=%s runner=%s indexer_rc=%s duration_s=%s\n%s\n%s\n%s\nVERDICT %s' \
        "$ID" "$CG_SV_OP" "$CG_SV_RUNNER" "$rc" "$((t1 - t0))" "$vout" "$scope_out" "$ledger" "$verdict")"
    write_result "$RES" "$code" "$summary"
}

write_result() {
    local f="$1" c="$2" msg="$3"
    printf 'EXIT=%s\n%s\n' "$c" "$msg" > "$f.tmp" && mv -f "$f.tmp" "$f"
}

pstate() {
    local s
    case "$1" in ''|*[!0-9]*) echo "-"; return ;; esac
    s="$(cat "/proc/$1/stat" 2>/dev/null)" || { echo "-"; return; }
    s="${s##*) }"
    echo "${s%% *}"
}

stock_status_files() {
    "$STOCK" status "$1" 2>/dev/null 9>&- | sed -n 's/^[[:space:]]*Files:[[:space:]]*\([0-9,]*\).*/\1/p' | head -n 1 | tr -d ','
}

ledger_append() {
    # ledger_append <doc> <id> <op> <version> <runner> <verdict> <counts> <durations>
    local doc="$1"
    if [ -z "$doc" ] || [ ! -f "$doc" ]; then
        echo "LEDGER: SKIP (no ledger file at '${doc:-<unset>}'; pass --status-doc to record runs)"
        return 0
    fi
    {
        printf '\n## %s — codegraph_safe.sh run %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2"
        printf -- '- op: %s\n- codegraph version: %s\n- runner: %s\n- verdict: %s\n- counts: %s\n- durations: %s\n' \
            "$3" "$4" "$5" "$6" "$7" "$8"
    } >> "$doc"
    echo "LEDGER: appended to $doc"
}

if [ "${1:-}" = "__supervise" ]; then
    supervise
    exit 0
fi

# ================================================================ arg parsing ==
PROJECT="" WAIT=0 POLL=10 WATCH_INT=60 STALL_MIN=10 TW_GIB=20 TW_INT=30 REAP=0
FORCE_BULK=0 PEND_MIN="${CG_SAFE_PENDING_BULK_MIN:-150000}" PATCHES="${CG_SAFE_PATCHES:-fkidx1,resolve1}"
EXPECTED="" TOL="" STATUS_DOC="" BASELINE="$HERE/scope_baseline.txt" SCOPE_EXCEPTIONS="$HERE/scope_exceptions.txt" OP=""
need() { [ $# -ge 2 ] && [ -n "$2" ] || die 2 "option $1 needs a value"; }
while [ $# -gt 0 ]; do
    case "$1" in
        --project) need "$@"; PROJECT="$2"; shift 2 ;;
        --wait) WAIT=1; shift ;;
        --bulk) FORCE_BULK=1; shift ;;
        --pending-threshold) need "$@"; PEND_MIN="$2"; shift 2 ;;
        --patches) [ $# -ge 2 ] || die 2 "option --patches needs a value"; PATCHES="$2"; shift 2 ;;
        --poll-s) need "$@"; POLL="$2"; shift 2 ;;
        --watch-interval) need "$@"; WATCH_INT="$2"; shift 2 ;;
        --stall-min) need "$@"; STALL_MIN="$2"; shift 2 ;;
        --tripwire-min-gib) need "$@"; TW_GIB="$2"; shift 2 ;;
        --tripwire-interval) need "$@"; TW_INT="$2"; shift 2 ;;
        --reap-dead-lock) REAP=1; shift ;;
        --expected-count) need "$@"; EXPECTED="$2"; shift 2 ;;
        --tolerance-pct) need "$@"; TOL="$2"; shift 2 ;;
        --status-doc) need "$@"; STATUS_DOC="$2"; shift 2 ;;
        --scope-baseline) need "$@"; BASELINE="$2"; shift 2 ;;
        --scope-exceptions) need "$@"; SCOPE_EXCEPTIONS="$2"; shift 2 ;;
        -h|--help) sed -n '2,/^set -u$/p' "$SELF" | sed '$d'; exit 0 ;;
        -*) die 2 "unknown option: $1" ;;
        *) [ -z "$OP" ] || die 2 "only one op allowed (got '$OP' and '$1')"; OP="$1"; shift ;;
    esac
done
[ -n "$OP" ] || die 2 "no op given (init|index|sync|status|verify|preflight|unlock)"
case "$OP" in init|index|sync|status|verify|preflight|unlock) ;; *) die 2 "unknown op: $OP" ;; esac
for v in "$POLL" "$WATCH_INT" "$TW_GIB" "$TW_INT"; do
    case "$v" in ''|*[!0-9]*) die 2 "numeric option expected, got '$v'" ;; esac
done
case "$STALL_MIN" in ''|*[!0-9.]*) die 2 "--stall-min must be a number" ;; esac
case "$PEND_MIN" in ''|*[!0-9]*) die 2 "pending threshold must be an integer >= 1, got '$PEND_MIN'" ;; esac
[ "$PEND_MIN" -ge 1 ] 2>/dev/null || die 2 "pending threshold must be an integer >= 1, got '$PEND_MIN'"
case "$PATCHES" in
    all) ;;
    ''|*[!a-z0-9,]*|,*|*,|*,,*) die 2 "--patches / CG_SAFE_PATCHES must be 'all' or a comma list of patch ids [a-z0-9], got '$PATCHES'" ;;
esac
if [ "$FORCE_BULK" -eq 1 ]; then
    case "$OP" in status|verify|preflight|unlock) die 2 "--bulk only applies to writer ops (init|index|sync), not '$OP'" ;; esac
fi
if [ "$TW_GIB" -lt 5 ] || [ "$TW_GIB" -gt 500 ]; then die 2 "--tripwire-min-gib must be in [5,500]"; fi
if [ -n "$EXPECTED" ]; then case "$EXPECTED" in *[!0-9]*) die 2 "--expected-count must be an integer" ;; esac; fi
if [ -n "$TOL" ]; then case "$TOL" in *[!0-9.]*) die 2 "--tolerance-pct must be a number" ;; esac; fi

if [ -z "$PROJECT" ]; then
    PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -d "$PROJECT" ] || die 2 "project dir does not exist: $PROJECT"
P="$(cd "$PROJECT" && pwd -P)"
CGD="$P/.codegraph"
RUNS="$CGD/index_runs"
LOCK="$CGD/codegraph.lock"
[ -n "$STATUS_DOC" ] || STATUS_DOC="$P/docs/codegraph/Status.md"
EXPECT_ARGS=""
[ -n "$EXPECTED" ] && EXPECT_ARGS="--expected $EXPECTED --tolerance-pct ${TOL:-0}"

# ================================================================ preflight ==
preflight() {
    # prints measurements; returns 0 PASS / 1 FAIL
    local target="$CGD" free db_bytes min_free mem ov tl used head minh ok=0
    [ -d "$target" ] || target="$P"
    free="$(df -B1 --output=avail "$target" 2>/dev/null | tail -n 1 | tr -d ' ')"
    case "$free" in ''|*[!0-9]*) echo "free_bytes=unreadable"; return 1 ;; esac
    ov="${CG_SAFE_TEST_FREE_BYTES:-}"
    case "$ov" in ''|*[!0-9]*) ;; *) [ "$ov" -lt "$free" ] && free="$ov" ;; esac
    db_bytes=0
    for f in "$CGD/codegraph.db" "$CGD/codegraph.db-wal"; do
        [ -f "$f" ] && db_bytes=$((db_bytes + $(stat -c %s "$f")))
    done
    min_free=$((60 * GIB)); [ $((2 * db_bytes)) -gt "$min_free" ] && min_free=$((2 * db_bytes))
    echo "free_bytes=$free"; echo "db_bytes=$db_bytes"; echo "min_free_bytes=$min_free"
    [ "$free" -ge "$min_free" ] || { echo "PREFLIGHT FAIL disk: free $free < required $min_free"; ok=1; }
    mem="$(sed -n 's/^MemAvailable:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo)"
    case "$mem" in ''|*[!0-9]*) echo "mem_avail_kb=unreadable"; return 1 ;; esac
    ov="${CG_SAFE_TEST_MEMAVAIL_KB:-}"
    case "$ov" in ''|*[!0-9]*) ;; *) [ "$ov" -lt "$mem" ] && mem="$ov" ;; esac
    echo "mem_avail_kb=$mem"; echo "min_mem_avail_kb=$((32 * 1048576))"
    [ "$mem" -ge $((32 * 1048576)) ] || { echo "PREFLIGHT FAIL memory: MemAvailable ${mem} kB < 32 GiB"; ok=1; }
    tl="$(ulimit -u)"
    used="$(ps -L --no-headers -u "$(id -u)" 2>/dev/null | wc -l)"
    ov="${CG_SAFE_TEST_THREADS_USED:-}"
    case "$ov" in ''|*[!0-9]*) ;; *) [ "$ov" -gt "$used" ] && used="$ov" ;; esac
    minh="${CG_SAFE_MIN_THREAD_HEADROOM:-1024}"
    echo "thread_limit=$tl"; echo "threads_used=$used"; echo "min_thread_headroom=$minh"
    if [ "$tl" != "unlimited" ]; then
        head=$((tl - used))
        [ "$head" -ge "$minh" ] || { echo "PREFLIGHT FAIL threads: headroom $head < $minh (ulimit -u $tl, used $used) — §12.12"; ok=1; }
    fi
    # Host-adaptive V8 heap budget (2026-09-25, BOB-XXX): a stock-launched
    # indexer inherits Node's DEFAULT old-space limit (~4 GiB regardless of
    # host RAM) — the resolve phase on a 584K-file/49M-edge repo needs far
    # more than that and OOM-aborts (rc=134) after finishing file parsing,
    # discarding the whole bulk run. Never hardcode (§12.11): half of
    # currently-MemAvailable, floored at 8 GiB so it is always meaningfully
    # above the stock default, capped at 64 GiB so one process never alone
    # threatens the §12.6 60%-of-TOTAL-RAM ceiling.
    CG_SAFE_HEAP_MB=$(( mem / 1024 / 2 ))
    [ "$CG_SAFE_HEAP_MB" -lt 8192 ] && CG_SAFE_HEAP_MB=8192
    [ "$CG_SAFE_HEAP_MB" -gt 65536 ] && CG_SAFE_HEAP_MB=65536
    echo "heap_mb=$CG_SAFE_HEAP_MB"
    return "$ok"
}

# ============================================================ lock handling ==
lock_check() {
    # lock_check writer|reader|unlock — exits 3/4 as documented, or returns 0
    local mode="$1" content pid idn reason
    [ -f "$LOCK" ] || return 0
    content="$(head -c 64 "$LOCK" 2>/dev/null | tr -d ' \n\r')"
    reason=""
    case "$content" in
        ''|*[!0-9]*) reason="non-numeric lock content" ;;
        *) pid="$content"
           if [ "$pid" -le 1 ]; then reason="lock pid <= 1"
           else
               idn="$(python3 "$HELPER" identity "$pid" 2>/dev/null)"
               case "$idn" in
                   OK\ *)
                       local lop; lop="$(printf '%s' "$idn" | awk '{print $2}')"
                       if [ "$mode" = reader ]; then
                           case "$lop" in init|index|sync) die 3 "REFUSED: live codegraph $lop (pid=$pid) holds $LOCK — the DB is being rewritten" ;; esac
                           return 0
                       fi
                       die 3 "REFUSED: live codegraph process pid=$pid ($idn) holds $LOCK — whatever the lock's age, it is NOT stale (v1.6.0 stale-lock bug guard)"
                       ;;
                   gone) reason="holder pid=$pid is dead" ;;
                   *) reason="holder pid=$pid alive but not a codegraph process (${idn:-unknown})" ;;
               esac
           fi ;;
    esac
    if [ "$mode" = reader ]; then
        say "WARN: stale lock at $LOCK ($reason) — read op continues"
        return 0
    fi
    if [ "$REAP" -ne 1 ]; then
        die 4 "stale lock at $LOCK ($reason); re-run with --reap-dead-lock to remove it (the decision is logged)"
    fi
    # re-verify immediately before removal: never remove a lock a live codegraph now holds
    content="$(head -c 64 "$LOCK" 2>/dev/null | tr -d ' \n\r')"
    case "$content" in ''|*[!0-9]*) ;; *)
        if [ "$content" -gt 1 ] && python3 "$HELPER" identity "$content" >/dev/null 2>&1; then
            die 3 "REFUSED: lock re-check found live codegraph pid=$content"
        fi ;;
    esac
    mkdir -p "$RUNS"
    rm -f "$LOCK"
    printf '%s REAPED pid=%s reason="%s" lock=%s by=codegraph_safe.sh(pid=%s)\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${content:-?}" "$reason" "$LOCK" "$$" >> "$RUNS/lock_reap.log"
    say "reaped stale lock (pid=${content:-?}: $reason); logged to $RUNS/lock_reap.log"
    return 0
}

scan_or_refuse() {
    # scan_or_refuse writer|reader — /proc scan for live codegraph writers on this root
    local mode="$1" out tries=1
    [ "$mode" = reader ] && tries=3
    while :; do
        out="$(python3 "$HELPER" scan "$P" "$mode" 2>&1)" && return 0
        tries=$((tries - 1))
        [ "$tries" -gt 0 ] || die 3 "REFUSED: live codegraph writer on $P: $(printf '%s' "$out" | tr '\n' ' ')"
        sleep 0.5
    done
}

take_flock() {
    mkdir -p "$RUNS"
    { exec 9>>"$CGD/.helix_index.flock"; } 2>/dev/null || die 2 "cannot open $CGD/.helix_index.flock"
    flock -n 9 || die 3 "REFUSED: another codegraph_safe.sh holds $CGD/.helix_index.flock"
}

verify_now() {
    local rep="" lastlog sf rc1 rc2
    lastlog="$(ls -t "$RUNS"/index_*.log 2>/dev/null | head -n 1)"
    [ -n "$lastlog" ] && rep="$(grep -aoE 'Indexed [0-9,]+ files' "$lastlog" | tail -n 1 | tr -dc '0-9')"
    sf="$(stock_status_files "$P")"
    # shellcheck disable=SC2086
    python3 "$HELPER" verify "$P" --reported "$rep" --status-files "$sf" $EXPECT_ARGS; rc1=$?
    python3 "$HELPER" scope "$P" "$BASELINE" "$SCOPE_EXCEPTIONS"; rc2=$?
    [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]
}

stock_version() { "$STOCK" --version 2>/dev/null 9>&- | head -n 1 | tr -d ' \r'; }

resolve_runner() {
    # sets RUNNER or exits 5 — stock is never used unless the probe PROVES it safe
    local out rc sv rv rdir
    sv="$(stock_version)"
    [ -n "$sv" ] || die 5 "cannot read stock codegraph version via '$STOCK --version'"
    VERSION="$sv"
    local pargs="--print-bin"
    [ "$PATCHES" = all ] || pargs="--patches $PATCHES --print-bin"
    # shellcheck disable=SC2086
    out="$(run_tool "$PATCH_TOOL" $pargs 2>&1 9>&-)"; rc=$?
    case "$rc" in
        0)  RUNNER="$(printf '%s\n' "$out" | tail -n 1)"
            [ -x "$RUNNER" ] || die 5 "REFUSED: runner path from patch tool is not executable: $RUNNER"
            rdir="$(cd "$(dirname "$RUNNER")/.." && pwd)"
            python3 "$HELPER" receipt "$rdir" "$sv" >/dev/null 2>&1 \
                || die 5 "REFUSED: runner $RUNNER has no valid RUNNER_RECEIPT.json for stock version $sv"
            rv="$("$RUNNER" --version 2>/dev/null 9>&- | head -n 1 | tr -d ' \r')"
            [ "$rv" = "$sv" ] || die 5 "REFUSED: runner version '$rv' != stock version '$sv' — re-derive the runner (fk_index_patch.py)"
            ;;
        2)  die 5 "REFUSED: fk_index_patch.py could not derive a safe runner (exit 2): $(printf '%s' "$out" | tail -n 2 | tr '\n' ' ') — bulk indexing with stock is FORBIDDEN (2026-09-23 incident); a human must re-evaluate the upstream build" ;;
        3)  local pout prc
            pout="$(run_tool "$PROBE_TOOL" --work-dir "$RUNS/probe" --json-out "$RUNS/probe_verdict.json" 2>&1 9>&-)"; prc=$?
            [ "$prc" -eq 0 ] || die 5 "REFUSED: patch tool says NOT_NEEDED but fk_cascade_probe.py did not prove stock safe (exit $prc): $(printf '%s' "$pout" | tail -n 1)"
            RUNNER="$STOCK"
            ;;
        *)  die 5 "REFUSED: patch tool exited $rc: $(printf '%s' "$out" | tail -n 2 | tr '\n' ' ')" ;;
    esac
}

# ======================================================================= ops ==
case "$OP" in
    preflight)
        preflight && { echo "PREFLIGHT PASS"; exit 0; }
        exit 6 ;;
    unlock)
        take_flock
        lock_check unlock
        say "no stale lock remains at $LOCK"; exit 0 ;;
    status)
        lock_check reader
        scan_or_refuse reader
        "$STOCK" status "$P"; rc=$?
        [ "$rc" -eq 0 ] || exit 1
        exit 0 ;;
    verify)
        lock_check reader
        scan_or_refuse reader
        verify_now && { echo "VERDICT PASS"; exit 0; }
        echo "VERDICT FAIL"; exit 1 ;;
esac

# --------------------------------------------------------------- writers ------
take_flock
lock_check writer
scan_or_refuse writer

# sync classification (2026-09-24 defect: a populated DB was ALWAYS "incremental", even with ~40M
# pending refs). INCREMENTAL only when the DB is populated AND the pending-refs backlog is provably
# below the threshold; everything else (forced, empty/unreadable DB, big backlog, backlog UNKNOWN)
# takes the supervised, patched, detached BULK path.
BULK=1
if [ "$OP" = sync ]; then
    if [ "$FORCE_BULK" -eq 1 ]; then
        say "sync classification: BULK (reason=--bulk requested)"
    else
        dbj="$(python3 "$HELPER" dbinfo "$P")"
        if printf '%s' "$dbj" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["exists"] and d["nodes_present"] and not d["error"] else 1)'; then
            pout="$(python3 "$HELPER" pending "$P" --threshold "$PEND_MIN" 2>&1)"; prc=$?
            case "$prc" in
                0) BULK=0; say "sync classification: INCREMENTAL (reason=pending<threshold; $pout)" ;;
                1) say "sync classification: BULK (reason=pending>=threshold; $pout)" ;;
                *) say "sync classification: BULK (reason=pending-probe UNKNOWN — the backlog cannot be proven small, taking the supervised path; $pout)" ;;
            esac
        else
            say "sync classification: BULK (reason=database missing, empty or unreadable: $dbj)"
        fi
    fi
fi

if [ "$BULK" -eq 0 ]; then
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    slog="$RUNS/sync_$ts.log"
    say "incremental sync on a populated DB (stock, foreground, flock held): log $slog"
    "$STOCK" sync "$P" > "$slog" 2>&1 9>&-; rc=$?
    tail -n 5 "$slog"
    [ "$rc" -eq 0 ] || die 1 "codegraph sync exited $rc — see $slog"
    if python3 "$HELPER" verify "$P" && python3 "$HELPER" scope "$P" "$BASELINE" "$SCOPE_EXCEPTIONS"; then
        ledger_append "$STATUS_DOC" "sync_$ts" sync "$(stock_version)" "$STOCK" PASS "incremental" "-"
        echo "VERDICT PASS"; exit 0
    fi
    ledger_append "$STATUS_DOC" "sync_$ts" sync "$(stock_version)" "$STOCK" FAIL "incremental" "-"
    echo "VERDICT FAIL"; exit 1
fi

pf="$(preflight)"; prc=$?
printf '%s\n' "$pf"
[ "$prc" -eq 0 ] || die 6 "host preflight FAILED — bulk $OP refused (§12.6 / §12.12)"
HEAP_MB="$(printf '%s\n' "$pf" | sed -n 's/^heap_mb=\([0-9]*\)$/\1/p')"
case "$HEAP_MB" in ''|*[!0-9]*) die 6 "host preflight did not report a usable heap_mb — refusing rather than launching with an unmeasured/stock heap limit" ;; esac
say "V8 heap budget: --max-old-space-size=$HEAP_MB (host-adaptive, §12.11)"

VERSION=""
RUNNER=""
resolve_runner
say "runner: $RUNNER (stock version $VERSION)"

case "$OP" in
    init) ARGS="init -y -v $P" ;;
    index) ARGS="index -v $P" ;;
    sync) ARGS="sync $P" ;;
esac
case "$P" in *[[:space:]]*) die 2 "project path with whitespace is not supported: $P" ;; esac

ID="$(date -u +%Y%m%dT%H%M%SZ)_$$"
LOGF="$RUNS/index_$(date -u +%Y%m%dT%H%M%SZ).log"
rm -f "$RUNS/watch_state.json"
: > "$RUNS/run_$ID.pids"
# Propagate the host-adaptive heap budget to the indexer child (inherited by
# the detached supervisor -> "$CG_SV_RUNNER" launch below). Additive to any
# NODE_OPTIONS the caller already set, never clobbers it.
export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--max-old-space-size=$HEAP_MB"
export CG_SV_PROJECT="$P" CG_SV_RUNS="$RUNS" CG_SV_ID="$ID" CG_SV_LOG="$LOGF" CG_SV_RUNNER="$RUNNER" \
       CG_SV_ARGS="$ARGS" CG_SV_WATCH_INT="$WATCH_INT" CG_SV_STALL_MIN="$STALL_MIN" CG_SV_TW_GIB="$TW_GIB" \
       CG_SV_TW_INT="$TW_INT" CG_SV_EXPECT_ARGS="$EXPECT_ARGS" CG_SV_BASELINE="$BASELINE" \
       CG_SV_SCOPE_EXCEPTIONS="$SCOPE_EXCEPTIONS" \
       CG_SV_STATUS_DOC="$STATUS_DOC" CG_SV_OP="$OP" CG_SV_VERSION="$VERSION" CG_SV_HEAP_MB="$HEAP_MB"
setsid nohup bash "$SELF" __supervise < /dev/null >> "$RUNS/supervisor_$ID.log" 2>&1 &
SVPID=$!
say "run $ID started detached: log $LOGF"
say "pids: $RUNS/run_$ID.pids  result: $RUNS/run_$ID.result"
# return only once the indexer is observed (lock holder identified) or the run already ended,
# so a caller never races a not-yet-started indexer
i=0
while [ "$i" -lt 600 ]; do
    grep -q '^indexer=' "$RUNS/run_$ID.pids" 2>/dev/null && break
    [ -f "$RUNS/run_$ID.result" ] && break
    st="$(pstate "$SVPID")"; { [ "$st" = "-" ] || [ "$st" = "Z" ]; } && break
    sleep 0.1; i=$((i + 1))
done
say "indexer: $(sed -n 's/^indexer=//p' "$RUNS/run_$ID.pids" | head -n 1)"
if [ "$WAIT" -ne 1 ]; then
    say "not waiting (use --wait, or later: $SELF --project $P verify)"
    exit 0
fi
RES="$RUNS/run_$ID.result"
while [ ! -f "$RES" ]; do
    sv="$(sed -n 's/^supervisor=//p' "$RUNS/run_$ID.pids" | head -n 1)"
    [ -n "$sv" ] || sv="$SVPID"
    st="$(pstate "$sv")"
    if { [ "$st" = "-" ] || [ "$st" = "Z" ]; } && [ ! -f "$RES" ]; then
        sleep 1
        [ -f "$RES" ] || die 1 "supervisor $sv ended without a result — see $RUNS/supervisor_$ID.log"
    fi
    sleep "$POLL"
done
code="$(sed -n '1s/^EXIT=//p' "$RES")"
sed -n '2,200p' "$RES"
case "$code" in ''|*[!0-9]*) die 1 "unreadable result file $RES" ;; esac
exit "$code"
