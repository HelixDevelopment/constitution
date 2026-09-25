#!/usr/bin/env bash
# ============================================================================
# test_unit_safe.sh — UNIT tests for codegraph_safe.sh (stub binaries only)
# ============================================================================
# Purpose      Prove every refusal / routing / verification branch of the
#              launcher with STUB codegraph binaries (stubs are allowed ONLY in
#              unit tests, constitution §11.4.27). Written BEFORE the launcher
#              (§11.4.224 / §11.4.115 test-first): the RED run is recorded in
#              ../TEST_EVIDENCE.txt.
# Usage        bash test_unit_safe.sh            (all cases)
#              ONLY=U01,U10 bash test_unit_safe.sh (subset — mutation harness)
#              CG_DIR=<dir> selects the code under test (default: ..)
# Inputs       tests/fixtures/stub_cg (node stub carrying the real process
#              identity: argv0=node, script=*/lib/dist/bin/codegraph.js),
#              tests/fixtures/stub_{patch,probe}_tool.sh
# Outputs      RESULT lines (lib_test.sh); exit 1 when any case fails
# Side effects creates/removes work dirs under $TMPDIR/cg_safe_tests; starts and
#              reaps short-lived stub processes (identity-checked before signals)
# Dependencies bash, node (node:sqlite), python3
# Cross-refs   ../codegraph_safe.sh, run_all.sh, test_mutation.sh
# U31-U43     BULK-vs-incremental classification of `sync` (pending-refs volume, --bulk,
#             --pending-threshold, --patches, verify pending_zero); paired mutations in
#             test_bulk_classify_mutations.sh. Written RED-first.
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="${CG_DIR:-$(cd "$HERE/.." && pwd)}"
# shellcheck source=lib_test.sh
. "$HERE/lib_test.sh"
FIX="$HERE/fixtures"
SAFE="$CG_DIR/codegraph_safe.sh"
SPAWNED=""

cleanup() {
    local p
    for p in $SPAWNED; do
        t_kill_codegraph_pid "$p"
        # carrier processes (bash/sleep) started by this file only: verify the
        # recorded pid is still OUR child-shaped carrier before signalling
        case "$p" in ''|*[!0-9]*) continue ;; esac
        [ "$p" -gt 1 ] || continue
        if tr '\0' ' ' 2>/dev/null < "/proc/$p/cmdline" | grep -q '^bash -c sleep 300; : '; then
            kill -TERM "$p" 2>/dev/null
        fi
    done
}
trap cleanup EXIT

# ---------------------------------------------------------------- env setup --
setup() {
    # setup <name> → sets W (work dir) and P (project dir) and exports stub env
    W="$(t_workdir "$1")"
    P="$W/proj"
    mkdir -p "$P/src"
    echo 'int a(void){return 1;}' > "$P/src/a.c"
    cp -a "$FIX/stub_cg" "$W/stub"
    python3 - "$W/stub" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
sha = hashlib.sha256(open(os.path.join(d, "lib/dist/db/index.js"), "rb").read()).hexdigest()
json.dump({"patch_id": "fkidx1", "codegraph_version": "1.6.0", "patched_dbjs_sha256": sha},
          open(os.path.join(d, "RUNNER_RECEIPT.json"), "w"))
PY
    export CODEGRAPH_BIN="$W/stub/bin/codegraph_stock"
    export CG_SAFE_PATCH_TOOL="$FIX/stub_patch_tool.sh"
    export CG_SAFE_PROBE_TOOL="$FIX/stub_probe_tool.sh"
    export STUB_RUNNER_BIN="$W/stub/bin/codegraph"
    export STUB_CALL_LOG="$W/calls.log"
    : > "$STUB_CALL_LOG"
    unset STUB_PATCH_RC STUB_PROBE_RC STUB_FILES STUB_STATE STUB_REPORTED STUB_ACCOUNTED \
          STUB_SLEEP_MS STUB_EXIT STUB_RUNNER_VERSION STUB_STATUS_FILES \
          STUB_SYNC_HOLD STUB_RESOLVE_PENDING CG_SAFE_PENDING_BULK_MIN CG_SAFE_PATCHES \
          CG_SAFE_TEST_FREE_BYTES CG_SAFE_TEST_MEMAVAIL_KB CG_SAFE_TEST_THREADS_USED
    export STUB_SLEEP_MS=1500
}

run_safe() {
    # run_safe <args...> → OUT, RC
    OUT="$(bash "$SAFE" --project "$P" --poll-s 1 --watch-interval 1 --tripwire-interval 1 "$@" 2>&1)"
    RC=$?
}

calls_has() { grep -q -- "$1" "$STUB_CALL_LOG"; }
no_bulk_calls() { ! grep -Eq '^(stock|runner) (init|index|sync)' "$STUB_CALL_LOG"; }

spawn_cg_identity() {
    # a live process carrying the real codegraph identity (node … /lib/dist/bin/codegraph.js)
    STUB_SLEEP_MS=60000 node "$W/stub/lib/dist/bin/codegraph.js" sleep >/dev/null 2>&1 &
    LIVE=$!
    SPAWNED="$SPAWNED $LIVE"
    sleep 0.3
}

# ------------------------------------------------------------------- cases --
if t_want U01; then setup u01; export STUB_PATCH_RC=2
    run_safe --wait init
    [ "$RC" -eq 5 ] && no_bulk_calls && printf '%s' "$OUT" | grep -q REFUSED
    t_check U01 "runner REFUSED (patch exit 2) -> exit 5, stock NEVER used" $? "rc=$RC calls=$(tr '\n' ';' < "$STUB_CALL_LOG") out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
fi

if t_want U02; then setup u02; export STUB_PATCH_RC=3 STUB_PROBE_RC=0
    run_safe --wait init
    [ "$RC" -eq 0 ] && calls_has '^stock init' && calls_has '^probe_tool' && ! calls_has '^runner init'
    t_check U02 "NOT_NEEDED + probe SAFE -> stock init allowed" $? "rc=$RC calls=$(tr '\n' ';' < "$STUB_CALL_LOG") out=$(printf '%s' "$OUT" | tail -4 | tr '\n' ' ')"
fi

if t_want U03; then setup u03; export STUB_PATCH_RC=3 STUB_PROBE_RC=1
    run_safe --wait init
    [ "$RC" -eq 5 ] && no_bulk_calls
    t_check U03 "NOT_NEEDED + probe HAZARD -> exit 5, nothing run" $? "rc=$RC calls=$(tr '\n' ';' < "$STUB_CALL_LOG")"
fi

if t_want U04; then setup u04; export STUB_PATCH_RC=3 STUB_PROBE_RC=2
    run_safe --wait index
    [ "$RC" -eq 5 ] && no_bulk_calls
    t_check U04 "NOT_NEEDED + probe CANNOT_EVALUATE -> exit 5 (fail closed)" $? "rc=$RC calls=$(tr '\n' ';' < "$STUB_CALL_LOG")"
fi

if t_want U05; then setup u05; export STUB_PATCH_RC=0
    run_safe --wait init
    [ "$RC" -eq 0 ] && calls_has '^runner init' && ! calls_has '^stock init'
    t_check U05 "runner READY -> patched runner used for init, not stock" $? "rc=$RC calls=$(tr '\n' ';' < "$STUB_CALL_LOG") out=$(printf '%s' "$OUT" | tail -4 | tr '\n' ' ')"
fi

if t_want U06; then setup u06; export STUB_PATCH_RC=0 STUB_RUNNER_VERSION=9.9.9
    run_safe --wait init
    [ "$RC" -eq 5 ] && no_bulk_calls
    t_check U06 "runner version != stock version -> exit 5" $? "rc=$RC calls=$(tr '\n' ';' < "$STUB_CALL_LOG")"
fi

if t_want U07; then setup u07; export STUB_PATCH_RC=0; rm -f "$W/stub/RUNNER_RECEIPT.json"
    run_safe --wait init
    [ "$RC" -eq 5 ] && no_bulk_calls
    t_check U07 "runner without valid RUNNER_RECEIPT.json -> exit 5 (stock-as-runner impossible)" $? "rc=$RC calls=$(tr '\n' ';' < "$STUB_CALL_LOG")"
fi

if t_want U08; then setup u08; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null; : > "$STUB_CALL_LOG"
    run_safe status
    [ "$RC" -eq 0 ] && calls_has '^stock status' && ! calls_has '^patch_tool'
    t_check U08 "status on populated DB -> stock, runner tool not consulted" $? "rc=$RC calls=$(tr '\n' ';' < "$STUB_CALL_LOG")"
fi

if t_want U09; then setup u09; export STUB_PATCH_RC=0
    run_safe --wait sync; r1=$RC
    a=0; calls_has '^runner sync' || a=1
    : > "$STUB_CALL_LOG"
    run_safe --wait sync; r2=$RC
    b=0; calls_has '^stock sync' || b=1; calls_has '^patch_tool' && b=1
    [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$a" -eq 0 ] && [ "$b" -eq 0 ]
    t_check U09 "sync: missing DB -> bulk via runner; populated DB -> stock" $? "r1=$r1 r2=$r2 a=$a b=$b calls=$(tr '\n' ';' < "$STUB_CALL_LOG") out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
fi

if t_want U10; then setup u10; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    spawn_cg_identity; echo "$LIVE" > "$P/.codegraph/codegraph.lock"; : > "$STUB_CALL_LOG"
    run_safe --wait index; r1=$RC
    run_safe --wait sync; r2=$RC
    [ "$r1" -eq 3 ] && [ "$r2" -eq 3 ] && no_bulk_calls && [ -f "$P/.codegraph/codegraph.lock" ]
    t_check U10 "live codegraph lock holder -> index AND sync refused (exit 3), lock untouched" $? "r1=$r1 r2=$r2 calls=$(tr '\n' ';' < "$STUB_CALL_LOG")"
    t_kill_codegraph_pid "$LIVE"
fi

if t_want U11; then setup u11; export STUB_PATCH_RC=0
    mkdir -p "$P/.codegraph"; bash -c 'exit 0' & dead=$!; wait "$dead"
    echo "$dead" > "$P/.codegraph/codegraph.lock"
    run_safe --wait init; r1=$RC
    run_safe --wait --reap-dead-lock init; r2=$RC
    grep -q "REAPED pid=$dead" "$P/.codegraph/index_runs/lock_reap.log" 2>/dev/null; g=$?
    [ "$r1" -eq 4 ] && [ "$r2" -eq 0 ] && [ "$g" -eq 0 ]
    t_check U11 "dead-pid lock: refused w/o flag (4); reaped+logged with --reap-dead-lock" $? "r1=$r1 r2=$r2 g=$g out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
fi

if t_want U12; then setup u12; export STUB_PATCH_RC=0
    mkdir -p "$P/.codegraph"
    bash -c 'sleep 300; :' /x/lib/dist/bin/codegraph.js & car=$!; SPAWNED="$SPAWNED $car"; sleep 0.2
    echo "$car" > "$P/.codegraph/codegraph.lock"
    run_safe --wait init; r1=$RC
    run_safe --wait --reap-dead-lock init; r2=$RC
    st="$(t_pid_state "$car")"
    [ "$r1" -eq 4 ] && [ "$r2" -eq 0 ] && [ "$st" = "S" ]
    t_check U12 "carrier (alive, argv mentions codegraph.js, not node) is NOT a live indexer; reap never signals it" $? "r1=$r1 r2=$r2 carrier_state=$st"
fi

if t_want U13; then setup u13; export STUB_PATCH_RC=0
    mkdir -p "$P/.codegraph"; echo 1 > "$P/.codegraph/codegraph.lock"
    run_safe --wait init; r1=$RC
    echo garbage > "$P/.codegraph/codegraph.lock"
    run_safe --wait init; r2=$RC
    [ "$r1" -eq 4 ] && [ "$r2" -eq 4 ] && no_bulk_calls
    t_check U13 "lock pid<=1 / non-numeric -> stale, refused w/o flag (4)" $? "r1=$r1 r2=$r2"
fi

if t_want U14; then setup u14; export STUB_PATCH_RC=0
    CG_SAFE_TEST_FREE_BYTES=1 run_safe --wait init; r1=$RC
    CG_SAFE_TEST_MEMAVAIL_KB=1 run_safe --wait init; r2=$RC
    CG_SAFE_TEST_THREADS_USED=999999999 run_safe --wait init; r3=$RC
    ok=0; no_bulk_calls || ok=1
    CG_SAFE_TEST_FREE_BYTES=1 run_safe status; r4=$RC
    [ "$r1" -eq 6 ] && [ "$r2" -eq 6 ] && [ "$r3" -eq 6 ] && [ "$ok" -eq 0 ] && [ "$r4" -eq 0 ]
    t_check U14 "preflight: low disk / mem / thread headroom -> exit 6 for bulk; non-bulk unaffected" $? "r1=$r1 r2=$r2 r3=$r3 ok=$ok r4=$r4"
fi

if t_want U15; then setup u15
    OUT="$(CG_SAFE_TEST_FREE_BYTES=999999999999999999 bash "$SAFE" --project "$P" preflight 2>&1)"; RC=$?
    fb="$(printf '%s\n' "$OUT" | sed -n 's/^free_bytes=//p')"
    [ -n "$fb" ] && [ "$fb" != "999999999999999999" ]
    t_check U15 "test override can only LOWER a measurement (cannot fake free disk)" $? "rc=$RC free_bytes=$fb"
fi

if t_want U16; then setup u16; export STUB_PATCH_RC=0 STUB_SLEEP_MS=40000
    run_safe --wait --stall-min 0.05 init
    lp="$(cat "$P/.codegraph/codegraph.lock" 2>/dev/null)"
    [ "$RC" -eq 7 ] && printf '%s' "$OUT" | grep -q STALL
    t_check U16 "no progress -> watcher STALL surfaces as exit 7 (stall never looks healthy)" $? "rc=$RC out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
    t_kill_codegraph_pid "$lp"
fi

if t_want U17; then setup u17; export STUB_PATCH_RC=0 STUB_SLEEP_MS=40000
    run_safe --wait --tripwire-min-gib 400 init
    lp="$(cat "$P/.codegraph/codegraph.lock" 2>/dev/null)"
    st="$(t_pid_state "${lp:-0}")"
    [ "$RC" -eq 8 ] && [ "$st" = "T" ]
    t_check U17 "free disk below tripwire -> indexer SIGSTOPped (not killed), exit 8" $? "rc=$RC state=$st out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
    t_kill_codegraph_pid "$lp"
fi

if t_want U18; then setup u18; export STUB_PATCH_RC=0 STUB_STATE=partial
    run_safe --wait init
    [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'index_state'
    t_check U18 "index_state != complete -> exit 1" $? "rc=$RC out=$(printf '%s' "$OUT" | tail -4 | tr '\n' ' ')"
fi

if t_want U19; then setup u19; export STUB_PATCH_RC=0 STUB_REPORTED=5
    run_safe --wait init; r1=$RC
    setup u19b; export STUB_PATCH_RC=0 STUB_ACCOUNTED=9
    run_safe --wait init; r2=$RC
    setup u19c; export STUB_PATCH_RC=0; run_safe --wait init >/dev/null
    STUB_STATUS_FILES=77 run_safe verify; r3=$RC
    [ "$r1" -eq 1 ] && [ "$r2" -eq 1 ] && [ "$r3" -eq 1 ]
    t_check U19 "files count != reported (log / metadata / status) -> exit 1" $? "r1=$r1 r2=$r2 r3=$r3"
fi

if t_want U20; then setup u20; export STUB_PATCH_RC=0 STUB_FILES="src/a.c,secrets/creds.py"
    run_safe --wait init; r1=$RC; o1="$OUT"
    setup u20b; export STUB_PATCH_RC=0 STUB_FILES="src/a.c,config/.env.prod"
    run_safe --wait init; r2=$RC
    setup u20c; export STUB_PATCH_RC=0 STUB_FILES="src/a.c,src/dotenv_loader.py,src/environment.py,lib/build_rules.py"
    run_safe --wait init; r3=$RC
    [ "$r1" -eq 1 ] && printf '%s' "$o1" | grep -q 'SCOPE' && [ "$r2" -eq 1 ] && [ "$r3" -eq 0 ]
    t_check U20 "secret-class path indexed -> exit 1; carrier names (dotenv_loader, environment) -> PASS" $? "r1=$r1 r2=$r2 r3=$r3 out=$(printf '%s' "$OUT" | tail -4 | tr '\n' ' ')"
fi

if t_want U21; then setup u21; export STUB_PATCH_RC=0 STUB_FILES="/abs/root/src/a.c,/abs/root/lib/b.py"
    run_safe --wait init
    [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q BLIND
    t_check U21 "instrument blind (absolute paths defeat anchored globs) -> control needle FAILs it" $? "rc=$RC out=$(printf '%s' "$OUT" | tail -4 | tr '\n' ' ')"
fi

if t_want U22; then setup u22; export STUB_PATCH_RC=0
    mkdir -p "$P/docs/codegraph"; printf '# Status\n' > "$P/docs/codegraph/Status.md"
    run_safe --wait init; r1=$RC
    grep -q 'verdict: PASS' "$P/docs/codegraph/Status.md"; g=$?
    setup u22b; export STUB_PATCH_RC=0
    run_safe --wait init; r2=$RC; o2="$OUT"
    [ "$r1" -eq 0 ] && [ "$g" -eq 0 ] && [ "$r2" -eq 0 ] && printf '%s' "$o2" | grep -q 'LEDGER: SKIP'
    t_check U22 "ledger appended when Status.md exists; SKIP-with-reason when absent (run not failed)" $? "r1=$r1 g=$g r2=$r2"
fi

if t_want U23; then setup u23; export STUB_PATCH_RC=0 STUB_SLEEP_MS=4000
    t0=$(date +%s); run_safe init; r1=$RC; dt=$(( $(date +%s) - t0 ))
    pidf="$(ls "$P"/.codegraph/index_runs/run_*.pids 2>/dev/null | head -1)"
    i=0; while [ -f "$P/.codegraph/codegraph.lock" ] && [ "$i" -lt 20 ]; do sleep 1; i=$((i + 1)); done
    run_safe verify; r2=$RC
    [ "$r1" -eq 0 ] && [ "$dt" -lt 4 ] && [ -n "$pidf" ] && [ "$r2" -eq 0 ]
    t_check U23 "detached launch returns at once with a pids record; later 'verify' PASSes" $? "r1=$r1 dt=$dt pidf=$pidf r2=$r2 out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
fi

if t_want U24; then setup u24; export STUB_PATCH_RC=0 STUB_EXIT=3
    run_safe --wait init
    [ "$RC" -eq 1 ]
    t_check U24 "indexer exits non-zero -> exit 1 (never masked)" $? "rc=$RC"
fi

if t_want U25; then setup u25
    run_safe bogus-op
    [ "$RC" -eq 2 ]
    t_check U25 "unknown op -> exit 2" $? "rc=$RC"
fi

if t_want U26; then setup u26; export STUB_PATCH_RC=0
    mkdir -p "$P/.codegraph"; spawn_cg_identity; echo "$LIVE" > "$P/.codegraph/codegraph.lock"
    run_safe --reap-dead-lock unlock
    [ "$RC" -eq 3 ] && [ "$(cat "$P/.codegraph/codegraph.lock")" = "$LIVE" ] && [ "$(t_pid_state "$LIVE")" != "-" ]
    t_check U26 "'unlock' never removes a LIVE indexer lock, even with --reap-dead-lock" $? "rc=$RC"
    t_kill_codegraph_pid "$LIVE"
fi

spawn_park() {
    # spawn_park <cwd> <argv...> — live process with the real codegraph identity and the
    # given argv, holding NO lock (proves the /proc root scan, independent of the lock file)
    local cwd="$1"; shift
    ( cd "$cwd" && STUB_PARK=1 STUB_SLEEP_MS=60000 exec node "$W/stub/lib/dist/bin/codegraph.js" "$@" ) >/dev/null 2>&1 &
    PARK=$!
    SPAWNED="$SPAWNED $PARK"
    sleep 0.3
}

if t_want U27; then setup u27; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null; : > "$STUB_CALL_LOG"
    spawn_park "$W" sync "$P"
    run_safe --wait init; r1=$RC; t_kill_codegraph_pid "$PARK"
    mkdir -p "$P/src/deep"; spawn_park "$P/src/deep" serve --mcp
    run_safe --wait index; r2=$RC
    run_safe status; r3=$RC; t_kill_codegraph_pid "$PARK"
    [ "$r1" -eq 3 ] && [ "$r2" -eq 3 ] && [ "$r3" -eq 0 ] && no_bulk_calls
    t_check U27 "/proc scan: live 'sync <root>' or 'serve' (cwd below root) w/o lock -> writers refused (3); read op still allowed next to serve" $? "r1=$r1 r2=$r2 r3=$r3 calls=$(tr '\n' ';' < "$STUB_CALL_LOG")"
fi

if t_want U28; then setup u28; export STUB_PATCH_RC=0
    run_safe --wait --expected-count 3 --tolerance-pct 2 init; r1=$RC
    run_safe --expected-count 100 --tolerance-pct 2 verify; r2=$RC
    run_safe --expected-count 3 --tolerance-pct 2 verify; r3=$RC
    [ "$r1" -eq 0 ] && [ "$r2" -eq 1 ] && [ "$r3" -eq 0 ]
    t_check U28 "--expected-count N --tolerance-pct P enforced on the files table" $? "r1=$r1 r2=$r2 r3=$r3"
fi

if t_want U29; then setup u29; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    spawn_park "$W" index "$P"
    run_safe status; r1=$RC; t_kill_codegraph_pid "$PARK"
    [ "$r1" -eq 3 ]
    t_check U29 "read op refused while a live bulk writer (index) targets the root (DB mid-rewrite)" $? "r1=$r1"
fi

if t_want U30; then setup u30; export STUB_PATCH_RC=0
    mkdir -p "$P/.codegraph"
    flock -n "$P/.codegraph/.helix_index.flock" sleep 30 & fl=$!
    sleep 0.3
    run_safe --wait init; r1=$RC
    # the flock holder is `flock`/`sleep` we started; validate before signalling
    case "$fl" in ''|*[!0-9]*) ;; *) [ "$fl" -gt 1 ] && tr '\0' ' ' 2>/dev/null < "/proc/$fl/cmdline" | grep -q '^flock -n ' && kill -TERM "$fl" 2>/dev/null ;; esac
    [ "$r1" -eq 3 ] && no_bulk_calls
    t_check U30 "wrapper flock .codegraph/.helix_index.flock held by another launcher -> exit 3" $? "r1=$r1"
fi

# =========================================================================== #
# U31-U43 — BULK classification of `sync` by pending-reference volume          #
# Defect (2026-09-24): ANY sync on a DB with nodes>0 ran STOCK + FOREGROUND     #
# even with ~40M pending unresolved refs (no fkidx1/resolve1, no watcher, no    #
# tripwire) and died on the caller's timeout.                                   #
# =========================================================================== #
seed_pending() {
    # seed_pending <N> [status] — real unresolved_refs table + idx_unresolved_status (schema.sql subset)
    python3 - "$P/.codegraph/codegraph.db" "$1" "${2:-pending}" <<'PYSEED'
import sqlite3, sys
db, n, status = sys.argv[1], int(sys.argv[2]), sys.argv[3]
c = sqlite3.connect(db)
c.execute("create table if not exists unresolved_refs(id integer primary key autoincrement, from_node_id text not null, "
          "reference_name text not null, reference_kind text not null, line integer not null, col integer not null, "
          "candidates text, file_path text not null default '', language text not null default 'unknown', "
          "status text not null default 'pending', name_tail text not null default '')")
c.execute("create index if not exists idx_unresolved_status on unresolved_refs(status)")
c.executemany("insert into unresolved_refs(from_node_id, reference_name, reference_kind, line, col, status) "
              "values ('n1', ?, 'calls', 1, 1, ?)", ((f"r{i}", status) for i in range(n)))
c.commit()
PYSEED
}

db_exec() {
    # db_exec <sql> — one statement against the fixture project's DB
    python3 - "$P/.codegraph/codegraph.db" "$1" <<'PYEXEC'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute(sys.argv[2]); c.commit()
PYEXEC
}

pids_files() { ls "$P/.codegraph/index_runs"/run_*.pids 2>/dev/null | sort; }

newest_new_pids() {
    # newest_new_pids <listing-before> — a run_*.pids file created after that listing was taken
    local f
    for f in $(pids_files); do printf '%s\n' "$1" | grep -qxF "$f" || { printf '%s\n' "$f"; return 0; }; done
    return 1
}

is_supervised_bulk() {
    # is_supervised_bulk <listing-before> — the op ran through the DETACHED supervisor with watcher + tripwire armed
    local np; np="$(newest_new_pids "$1")" || return 1
    grep -q '^watcher=' "$np" && grep -q '^tripwire=' "$np"
}

if t_want U31; then setup u31; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    seed_pending 150000
    before="$(pids_files)"; : > "$STUB_CALL_LOG"
    export STUB_SYNC_HOLD=1 STUB_RESOLVE_PENDING=1
    run_safe --wait sync
    sup=1; is_supervised_bulk "$before" && sup=0
    [ "$RC" -eq 0 ] && calls_has '^runner sync' && ! calls_has '^stock sync' && [ "$sup" -eq 0 ] \
        && printf '%s' "$OUT" | grep -q 'sync classification: BULK' && printf '%s' "$OUT" | grep -q 'VERDICT PASS'
    t_check U31 "sync with pending refs >= 150000 -> BULK: patched runner, detached supervisor, watcher+tripwire armed; not stock/foreground" $? "rc=$RC supervised=$((1-sup)) calls=$(tr '\n' ';' < "$STUB_CALL_LOG") out=$(printf '%s' "$OUT" | grep -E 'classification|VERDICT|incremental' | tr '\n' ' ' | cut -c1-200)"
fi

if t_want U32; then setup u32; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    seed_pending 149999
    before="$(pids_files)"; : > "$STUB_CALL_LOG"
    export STUB_RESOLVE_PENDING=1
    run_safe --wait sync
    newp=0; newest_new_pids "$before" >/dev/null && newp=1
    [ "$RC" -eq 0 ] && calls_has '^stock sync' && ! calls_has '^runner sync' && ! calls_has '^patch_tool' && [ "$newp" -eq 0 ] \
        && printf '%s' "$OUT" | grep -q 'sync classification: INCREMENTAL'
    t_check U32 "golden-false: 149999 pending (< threshold) stays INCREMENTAL (stock, foreground, patch tool untouched)" $? "rc=$RC new_supervisor=$newp calls=$(tr '\n' ';' < "$STUB_CALL_LOG") out=$(printf '%s' "$OUT" | grep -E 'classification|VERDICT' | tr '\n' ' ' | cut -c1-200)"
fi

if t_want U33; then setup u33; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    seed_pending 10
    export STUB_SYNC_HOLD=1 STUB_RESOLVE_PENDING=1
    : > "$STUB_CALL_LOG"; run_safe --wait sync; ra=$RC; a=0; calls_has '^stock sync' || a=1; calls_has '^runner sync' && a=1
    seed_pending 10; : > "$STUB_CALL_LOG"; run_safe --wait --pending-threshold 10 sync; rb=$RC; b=0; calls_has '^runner sync' || b=1; calls_has '^stock sync' && b=1
    seed_pending 10; : > "$STUB_CALL_LOG"; CG_SAFE_PENDING_BULK_MIN=10 run_safe --wait sync; rc_=$RC; c=0; calls_has '^runner sync' || c=1
    seed_pending 10; : > "$STUB_CALL_LOG"; CG_SAFE_PENDING_BULK_MIN=999999 run_safe --wait --pending-threshold 10 sync; rd=$RC; d=0; calls_has '^runner sync' || d=1
    run_safe --pending-threshold 0 sync; e1=$RC
    run_safe --pending-threshold abc sync; e2=$RC
    [ "$ra" -eq 0 ] && [ "$rb" -eq 0 ] && [ "$rc_" -eq 0 ] && [ "$rd" -eq 0 ] && [ "$a$b$c$d" = "0000" ] && [ "$e1" -eq 2 ] && [ "$e2" -eq 2 ]
    t_check U33 "threshold: default keeps 10 pending incremental; --pending-threshold 10 and CG_SAFE_PENDING_BULK_MIN=10 -> BULK; flag beats env; 0/abc -> exit 2" $? "rc=$ra,$rb,$rc_,$rd a=$a b=$b c=$c d=$d e=$e1,$e2"
fi

if t_want U34; then setup u34; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    before="$(pids_files)"; : > "$STUB_CALL_LOG"
    export STUB_SYNC_HOLD=1
    run_safe --wait --bulk sync; r1=$RC
    sup=1; is_supervised_bulk "$before" && sup=0
    run_safe --bulk status; r2=$RC
    run_safe --bulk verify; r3=$RC
    [ "$r1" -eq 0 ] && calls_has '^runner sync' && ! calls_has '^stock sync' && [ "$sup" -eq 0 ] \
        && [ "$r2" -eq 2 ] && [ "$r3" -eq 2 ]
    t_check U34 "--bulk forces the supervised patched path for sync on a healthy DB (0 pending); rejected (2) on read ops" $? "r1=$r1 r2=$r2 r3=$r3 supervised=$((1-sup)) calls=$(tr '\n' ';' < "$STUB_CALL_LOG")"
fi

if t_want U35; then setup u35; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    seed_pending 200000 failed
    : > "$STUB_CALL_LOG"
    run_safe --wait sync
    [ "$RC" -eq 0 ] && calls_has '^stock sync' && ! calls_has '^runner sync' && printf '%s' "$OUT" | grep -q 'sync classification: INCREMENTAL'
    t_check U35 "golden-false: 200000 status='failed' rows (retry tail) + 0 pending stays INCREMENTAL — only status='pending' counts" $? "rc=$RC calls=$(tr '\n' ';' < "$STUB_CALL_LOG") out=$(printf '%s' "$OUT" | grep -E 'classification|VERDICT' | tr '\n' ' ' | cut -c1-200)"
fi

if t_want U36; then setup u36; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    export STUB_SYNC_HOLD=1 STUB_RESOLVE_PENDING=1
    db_exec "drop index idx_unresolved_status"
    : > "$STUB_CALL_LOG"; run_safe --wait sync; ra=$RC
    a=0; calls_has '^runner sync' || a=1; calls_has '^stock sync' && a=1
    printf '%s' "$OUT" | grep -q 'UNKNOWN' || a=1
    db_exec "drop table unresolved_refs"
    : > "$STUB_CALL_LOG"; run_safe --wait sync; rb=$RC
    b=0; calls_has '^runner sync' || b=1; calls_has '^stock sync' && b=1
    printf '%s' "$OUT" | grep -q 'UNKNOWN' || b=1
    [ "$a" -eq 0 ] && [ "$b" -eq 0 ] && [ "$ra" -eq 0 ] && [ "$rb" -eq 1 ]
    t_check U36 "pending probe cannot evaluate (index missing / table missing) -> UNKNOWN -> BULK (conservative), stated in output; a table-less DB then fails verify (1)" $? "ra=$ra rb=$rb a=$a b=$b"
fi

if t_want U37; then setup u37; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    seed_pending 400000
    o1="$(python3 "$CG_DIR/codegraph_safe_helper.py" pending "$P" --threshold 150000 2>&1)"; c1=$?
    db_exec "delete from unresolved_refs where id > 5"
    o2="$(python3 "$CG_DIR/codegraph_safe_helper.py" pending "$P" --threshold 150000 2>&1)"; c2=$?
    [ "$c1" -eq 1 ] && printf '%s' "$o1" | grep -q 'counted=150001' && printf '%s' "$o1" | grep -q 'verdict=AT_OR_ABOVE' \
        && [ "$c2" -eq 0 ] && printf '%s' "$o2" | grep -q 'counted=5' && printf '%s' "$o2" | grep -q 'verdict=BELOW'
    t_check U37 "probe is BOUNDED: 400000 pending rows are counted only up to threshold+1 (150001), never a full COUNT(*); exact below threshold" $? "c1=$c1 o1=$o1 | c2=$c2 o2=$o2"
fi

if t_want U38; then setup u38; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null;                                d1="$(grep '^patch_tool' "$STUB_CALL_LOG" | tail -n 1)"
    : > "$STUB_CALL_LOG"; run_safe --wait --patches fkidx1,lockfix1,resolve1 index >/dev/null; d2="$(grep '^patch_tool' "$STUB_CALL_LOG" | tail -n 1)"
    : > "$STUB_CALL_LOG"; CG_SAFE_PATCHES=fkidx1 run_safe --wait index >/dev/null;              d3="$(grep '^patch_tool' "$STUB_CALL_LOG" | tail -n 1)"
    : > "$STUB_CALL_LOG"; run_safe --wait --patches all index >/dev/null;                       d4="$(grep '^patch_tool' "$STUB_CALL_LOG" | tail -n 1)"
    : > "$STUB_CALL_LOG"; run_safe --patches 'x;y' index; e1=$RC; n1="$(grep -c '^patch_tool' "$STUB_CALL_LOG")"
    run_safe --patches '' index; e2=$RC
    run_safe --patches 'Fkidx1' index; e3=$RC
    [ "$d1" = "patch_tool --patches fkidx1,resolve1 --print-bin" ] && [ "$d2" = "patch_tool --patches fkidx1,lockfix1,resolve1 --print-bin" ] \
        && [ "$d3" = "patch_tool --patches fkidx1 --print-bin" ] && [ "$d4" = "patch_tool --print-bin" ] \
        && [ "$e1" -eq 2 ] && [ "$e2" -eq 2 ] && [ "$e3" -eq 2 ] && [ "$n1" -eq 0 ]
    t_check U38 "patch set: default = validated subset fkidx1,resolve1 (untested lockfix1/datafrag1 NOT default); --patches / CG_SAFE_PATCHES pass through; 'all' = registry default; malformed -> exit 2" $? "d1=[$d1] d2=[$d2] d3=[$d3] d4=[$d4] e=$e1,$e2,$e3 n1=$n1"
fi

if t_want U39; then setup u39; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    seed_pending 5
    run_safe verify; r1=$RC; o1="$OUT"
    db_exec "delete from unresolved_refs"; seed_pending 300 failed
    run_safe verify; r2=$RC; o2="$OUT"
    # end-to-end: a BULK sync that leaves pending refs behind must FAIL its verdict
    db_exec "delete from unresolved_refs"; seed_pending 150000
    export STUB_SYNC_HOLD=1
    run_safe --wait sync; r3=$RC; o3="$OUT"
    [ "$r1" -eq 1 ] && printf '%s' "$o1" | grep -q 'VERIFY pending_zero FAIL' \
        && [ "$r2" -eq 0 ] && printf '%s' "$o2" | grep -q 'VERIFY pending_zero PASS' \
        && [ "$r3" -eq 1 ] && printf '%s' "$o3" | grep -q 'VERIFY pending_zero FAIL'
    t_check U39 "verify asserts pending==0 (failed-tail rows OK, pending rows FAIL) — also on the post-BULK verdict" $? "r=$r1,$r2,$r3 o1=$(printf '%s' "$o1" | grep pending_zero | cut -c1-90) o3=$(printf '%s' "$o3" | grep -E 'pending_zero|VERDICT' | tr '\n' ' ' | cut -c1-160)"
fi

if t_want U40; then setup u40; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    run_safe verify; r1=$RC; o1="$OUT"
    db_exec "insert into project_metadata values ('indexed_with_version','1.6.0',0)"
    db_exec "insert into project_metadata values ('indexed_with_extraction_version','7',0)"
    run_safe verify; r2=$RC; o2="$OUT"
    [ "$r1" -eq 0 ] && printf '%s' "$o1" | grep -q 'VERIFY_NOTE version_stamp ABSENT' && printf '%s' "$o1" | grep -q 'stale' \
        && [ "$r2" -eq 0 ] && printf '%s' "$o2" | grep -q 'VERIFY_NOTE version_stamp PRESENT'
    t_check U40 "known gap made explicit: missing indexed_with_version stamp -> VERIFY_NOTE ABSENT (status will say stale), NOT a FAIL; present -> PRESENT" $? "r=$r1,$r2 o1=$(printf '%s' "$o1" | grep NOTE | cut -c1-160) o2=$(printf '%s' "$o2" | grep NOTE | cut -c1-90)"
fi

if t_want U41; then setup u41; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    H="$CG_DIR/codegraph_safe_helper.py"
    seed_pending 3
    python3 "$H" pending "$P" --threshold 3 >/dev/null 2>&1; a1=$?      # exactly at threshold -> AT_OR_ABOVE
    python3 "$H" pending "$P" --threshold 4 >/dev/null 2>&1; a2=$?      # below
    db_exec "drop index idx_unresolved_status"
    python3 "$H" pending "$P" --threshold 3 >/dev/null 2>&1; a3=$?      # cannot evaluate
    python3 "$H" pending "$W/no_such_project" --threshold 3 >/dev/null 2>&1; a4=$?   # no DB
    python3 "$H" pending >/dev/null 2>&1; a5=$?                         # usage
    python3 "$H" pending "$P" --threshold 0 >/dev/null 2>&1; a6=$?      # usage
    python3 "$H" pending "$P" --threshold x >/dev/null 2>&1; a7=$?      # usage
    [ "$a1" -eq 1 ] && [ "$a2" -eq 0 ] && [ "$a3" -eq 3 ] && [ "$a4" -eq 3 ] && [ "$a5" -eq 2 ] && [ "$a6" -eq 2 ] && [ "$a7" -eq 2 ]
    t_check U41 "helper 'pending' exit contract: >=threshold 1 (inclusive), below 0, UNKNOWN 3 (missing index / no DB), usage 2" $? "codes=$a1,$a2,$a3,$a4,$a5,$a6,$a7"
fi

if t_want U42; then setup u42; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    j="$(python3 "$CG_DIR/codegraph_safe_helper.py" dbinfo "$P")"
    printf '%s' "$j" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("nodes_present") is True and "nodes" not in d else 1)'; a=$?
    # bound proof: `nodes` becomes a VIEW over 300M generated rows — a COUNT(*) would run for tens of seconds, a LIMIT-1 probe is instant
    db_exec "drop table nodes"
    db_exec "create view nodes as with recursive c(x) as (select 1 union all select x+1 from c where x < 300000000) select x as id from c"
    j2="$(timeout 10 python3 "$CG_DIR/codegraph_safe_helper.py" dbinfo "$P")"; b=$?
    c=1; printf '%s' "$j2" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("nodes_present") is True else 1)' && c=0
    [ "$a" -eq 0 ] && [ "$b" -eq 0 ] && [ "$c" -eq 0 ]
    t_check U42 "dbinfo never COUNTs the nodes table (14.9M rows): nodes_present via a LIMIT-1 probe, instant even over a 300M-row view" $? "a=$a b=$b(124=timeout: full COUNT) c=$c dbinfo=$j"
fi

if t_want U43; then setup u43; export STUB_PATCH_RC=0
    run_safe --wait init >/dev/null
    seed_pending 150000
    export STUB_SYNC_HOLD=1 STUB_RESOLVE_PENDING=1
    run_safe --wait sync >/dev/null
    resf="$(ls -t "$P/.codegraph/index_runs"/run_*.result 2>/dev/null | head -n 1)"
    [ -f "$resf" ] && [ "$(sed -n '1p' "$resf")" = "EXIT=0" ] && grep -q 'op=sync' "$resf" && grep -q 'VERIFY pending_zero PASS' "$resf"
    t_check U43 "BULK sync result file carries op=sync, pending_zero PASS and EXIT=0 (auditable evidence)" $? "resf=$resf head=$(sed -n '1,3p' "$resf" 2>/dev/null | tr '\n' ' ' | cut -c1-160)"
fi

# U44/U45 (2026-09-25, BOB-XXX): host-adaptive V8 heap budget. A stock-launched
# indexer inherits Node's DEFAULT old-space limit (~4 GiB regardless of host
# RAM); on a 584K-file/49M-edge repo the resolve phase OOM-aborts (rc=134)
# after finishing file parsing, discarding the whole bulk run (reproduced
# live 2026-09-25, see docs/codegraph/Status.md). preflight() now computes
# and reports a heap_mb budget (half of MemAvailable, floored 8 GiB so it is
# always meaningfully above stock, capped 64 GiB per §12.6), and the caller
# propagates it via NODE_OPTIONS=--max-old-space-size=$heap_mb before
# launching the detached supervisor.
# NOTE: heap_mb is asserted independently of the overall PREFLIGHT PASS/FAIL
# verdict (exit 0 vs exit 6) — disk-free-space is a SEPARATE gate whose real
# value depends on the test host's filesystem and is not what these two
# cases exercise; conflating them would make the test flaky across hosts/CI.
if t_want U44; then setup u44
    OUT="$(CG_SAFE_TEST_MEMAVAIL_KB=$((32 * 1048576)) bash "$SAFE" --project "$P" preflight 2>&1)"
    hm="$(printf '%s\n' "$OUT" | sed -n 's/^heap_mb=\([0-9]*\)$/\1/p')"
    [ "$hm" = "16384" ]
    t_check U44 "heap_mb = half of MemAvailable (32 GiB avail -> 16384 MiB, above floor/below cap, exact formula)" $? "heap_mb=$hm out=$(printf '%s' "$OUT" | tr '\n' ' ')"
fi

if t_want U45; then setup u45
    OUT="$(CG_SAFE_TEST_MEMAVAIL_KB=$((10 * 1048576)) bash "$SAFE" --project "$P" preflight 2>&1)"
    hm="$(printf '%s\n' "$OUT" | sed -n 's/^heap_mb=\([0-9]*\)$/\1/p')"
    # 10 GiB avail also fails the separate 32 GiB preflight memory floor —
    # heap_mb is still computed+printed unconditionally, floored at 8192.
    [ "$hm" = "8192" ]
    t_check U45 "heap_mb floors at 8192 MiB when half-of-available would go lower (never below stock-plus-headroom)" $? "heap_mb=$hm out=$(printf '%s' "$OUT" | tr '\n' ' ')"
fi

t_finish
