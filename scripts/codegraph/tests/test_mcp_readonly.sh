#!/usr/bin/env bash
# ============================================================================
# test_mcp_readonly.sh — tests for the read-only CodeGraph MCP runner (patch mcpro1)
# ============================================================================
# Purpose      Prove, on FIXTURES only (never a real project), that the runner built by
#              fk_index_patch.py --patches mcpro1 (runner_patches/mcpro1.py) serves MCP tool calls
#              while being incapable of mutating the project's .codegraph/ — and that
#              the SAME checks DO see mutation on the stock runner (control needle,
#              §11.4.273: a green "nothing changed" is worthless unless the instrument
#              is shown able to see a change).
#                R1 builder: exit 0, runner bin present, receipt lists the patch anchors
#                R2 the RO runner ANSWERS tools/call on a drifted fixture (read path works)
#                R3 fd proof: every descriptor on codegraph.db is O_RDONLY  (control: stock=rw)
#                R4 no mutation: logical DB hash + main file identical after a session on a
#                   DRIFTED tree                                            (control: stock changes)
#                R5 no heal-on-open: a dropped bulk index stays dropped     (control: stock recreates)
#                R6 no watcher/auto-sync even without CODEGRAPH_NO_WATCH    (control: stock says active)
#                R7 planted stale lock file untouched (no sync gate/FileLock) (control: stock removes)
#                R8 builder fail-closed: shape mismatch => exit 2 and NO runner dir
#                R9 the RO runner REFUSES `codegraph sync` (CLI allowlist, exit 78; DB + planted lock untouched)      (control: stock syncs)
#                R10 the RO runner REFUSES `codegraph index` (measured hazard: without the allowlist it DELETED the DB) (control: stock re-indexes)
#                R11 no detached daemon even with CODEGRAPH_NO_DAEMON=0                                               (control: stock leaves daemon.log)
#                R12 node-level unit: FileLock.acquire throws + never unlinks a stale lock (second-line guard)        (control: stock unlinks it)
#                R13 registry: mcpro1 registered + selectable, NOT in the default patch set, exclusive with writer patches
#              Every "unchanged" verdict additionally requires that the RO session ANSWERED (a session that never started changes nothing).
#              Fingerprints read the DB with mode=ro (sees -wal); the earlier immutable=1 reader was WAL-blind (mutant M3 survived).
# Usage        bash test_mcp_readonly.sh ; ONLY=R3,R5 bash test_mcp_readonly.sh
# Inputs       STOCK_SRC (default: resolved from the installed codegraph), TMPDIR,
#              CG_DIR (code under test; default parent of tests/ — the mutation harness
#              points it at a mutated COPY)
# Outputs      RESULT lines + SUMMARY; exit 1 on any failure
# Side effects fixtures + runner under $TMPDIR/cg_safe_tests; nothing outside it
# Dependencies bash, python3, a stock codegraph 1.6.x install
# Cross-refs   ../fk_index_patch.py, ../runner_patches/mcpro1.py, cg_fp.py,
#              test_mcp_readonly_mutations.sh, constitution §11.4.201/.273/.115/.224
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="${CG_DIR:-$(cd "$HERE/.." && pwd)}"
# shellcheck source=lib_test.sh
. "$HERE/lib_test.sh"
export CODEGRAPH_NO_UPDATE_CHECK=1 DO_NOT_TRACK=1 CODEGRAPH_TELEMETRY=0
unset CODEGRAPH_NO_DAEMON CODEGRAPH_NO_WATCH CODEGRAPH_MCP_TOOLS CODEGRAPH_QUERY_POOL_SIZE CODEGRAPH_MCP_READONLY   # hermetic: ambient CodeGraph env must not steer the instrument

BUILDER="$CG_DIR/fk_index_patch.py"
PROBE="$CG_DIR/codegraph_mcp_probe.py"
FP="$HERE/cg_fp.py"
W="$(t_workdir mcp_ro)"
echo "workdir $W"

resolve_stock_bin() {
    # STOCK_BIN: the installed launcher (independent of the patch under test).
    if [ -n "${STOCK_BIN:-}" ]; then printf '%s\n' "$STOCK_BIN"; return; fi
    command -v codegraph
}
STOCK_BIN="$(resolve_stock_bin)"
STOCK_SRC="${STOCK_SRC:-$(cd "$CG_DIR" && python3 -c 'import fk_index_patch as m; print(m.default_src())' 2>/dev/null)}"
[ -d "$STOCK_SRC/lib/dist" ] || { echo "BLIND: cannot resolve stock package source (STOCK_SRC=$STOCK_SRC)"; exit 2; }
[ -n "$STOCK_BIN" ] || { echo "BLIND: no stock codegraph on PATH — cannot run (exit 2)"; exit 2; }

mkfx() {
    # mkfx <dir> — small git project, indexed by the STOCK writer, then drifted:
    # an appended function (changed file) + a brand-new file (added file).
    local d="$1"
    mkdir -p "$d/src" "$d/lib"
    ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t
      cat > src/alpha.py <<'EOF'
def compute_total(items):
    return sum(price_of(i) for i in items)

def price_of(item):
    return item.get("price", 0)
EOF
      cat > src/beta.js <<'EOF'
function renderCart(cart) { return formatTotal(cart.total()); }
function formatTotal(n) { return "$" + n.toFixed(2); }
EOF
      cat > lib/gamma.go <<'EOF'
package lib

func Checkout(c int) int { return applyDiscount(c) }
func applyDiscount(n int) int { return n - 1 }
EOF
      git add -A && git commit -qm fixture ) >/dev/null 2>&1
    "$STOCK_BIN" init -y "$d" >"$d/../init.$$.log" 2>&1 || { echo "fixture init failed"; return 1; }
    printf '\ndef brand_new_fn(x):\n    return price_of(x)\n' >> "$d/src/alpha.py"
    printf 'def only_new(a):\n    return a\n' > "$d/src/delta.py"
}

# control runner = the PRISTINE package launcher (the PATH shim spawns a child, so its PID holds no db fd: measured stock=[])
STOCK_RUNNER="$STOCK_BIN"; [ -x "$STOCK_SRC/bin/codegraph" ] && STOCK_RUNNER="$STOCK_SRC/bin/codegraph"
RO_RUNNER=""
build_ro() {
    RO_DIR="$W/ro_runner"
    if [ ! -x "$RO_DIR/bin/codegraph" ]; then
        BOUT="$(python3 "$BUILDER" --patches mcpro1 --src "$STOCK_SRC" --dst "$RO_DIR" 2>&1)"; BRC=$?
    else BRC=0; BOUT=reused; fi
    RO_RUNNER="$RO_DIR/bin/codegraph"
}

probe() {
    # probe <bin> <proj> [extra probe args...] — sets PJ (json) PRC
    local bin="$1" proj="$2"; shift 2
    PERR="${PERR:-$W/probe_err.last}"
    PJ="$(python3 "$PROBE" --bin "$bin" --project "$proj" --stderr-file "$PERR" "$@" 2>/dev/null)"; PRC=$?
}
walsz() { stat -c %s "$1/.codegraph/codegraph.db-wal" 2>/dev/null || echo 0; }   # uncheckpointed WAL bytes (absent = 0)
jget() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d.get(sys.argv[2]))' "$PJ" "$1" 2>/dev/null; }

RO_ENV=(--env CODEGRAPH_NO_DAEMON=1 --env CODEGRAPH_NO_WATCH=1)   # no READONLY env: the mcpro1 runner is unconditionally read-only
ST_ENV=(--env CODEGRAPH_NO_DAEMON=1 --env CODEGRAPH_NO_WATCH=1)

if t_want R1; then
    build_ro
    [ "$BRC" -eq 0 ] && [ -x "$RO_RUNNER" ] && python3 - "$RO_DIR/RUNNER_RECEIPT.json" <<'PY'
import json, sys
rc = json.load(open(sys.argv[1]))
p = rc["patches"]["mcpro1"]
assert p["status"] == "APPLIED", p
assert len(p["anchors"]) >= 3, p["anchors"]
PY
    t_check R1 "builder produces an executable runner + receipt with >=3 mcpro1 anchors" $? "brc=$BRC out=$(printf '%s' "$BOUT" | tail -3 | tr '\n' ' ')"
fi

if t_want R2; then build_ro
    FX="$W/r2/proj"; mkfx "$FX"
    probe "$RO_RUNNER" "$FX" "${RO_ENV[@]}" --calls 2
    [ "$PRC" -eq 0 ] && [ "$(jget calls_ok)" = "2" ]
    t_check R2 "RO runner answers tools/call on a drifted fixture (read path works)" $? "prc=$PRC json=$PJ"
fi

if t_want R3; then build_ro
    FX="$W/r3/proj"; mkfx "$FX"
    probe "$STOCK_RUNNER" "$FX" "${ST_ENV[@]}"
    STOCK_MODES="$(jget db_fd_modes)"
    FX2="$W/r3/proj2"; mkfx "$FX2"
    probe "$RO_RUNNER" "$FX2" "${RO_ENV[@]}"
    RO_MODES="$(jget db_fd_modes)"
    # control: the stock server must show a writable db fd (proves the instrument sees 'rw');
    # subject: the RO server must show ONLY read-only descriptors and at least one.
    case "$STOCK_MODES" in *rw*) CTRL=0 ;; *) CTRL=1 ;; esac
    case "$RO_MODES" in *"'r'"*) ROK=0 ;; *) ROK=1 ;; esac
    case "$RO_MODES" in *rw*) ROK=1 ;; esac
    t_check R3 "fd proof: RO runner holds codegraph.db O_RDONLY only (control: stock has rw)" $((CTRL + ROK)) "stock=$STOCK_MODES ro=$RO_MODES"
fi

if t_want R4; then build_ro
    FXS="$W/r4/stock"; mkfx "$FXS"; python3 "$FP" fp "$FXS" > "$W/r4/stock.before"
    probe "$STOCK_RUNNER" "$FXS" "${ST_ENV[@]}"; python3 "$FP" fp "$FXS" > "$W/r4/stock.after"
    FXR="$W/r4/ro"; mkfx "$FXR"; python3 "$FP" fp "$FXR" > "$W/r4/ro.before"; WALB="$(walsz "$FXR")"
    probe "$RO_RUNNER" "$FXR" "${RO_ENV[@]}"; PR4="$PRC"; WALA="$(walsz "$FXR")"; python3 "$FP" fp "$FXR" > "$W/r4/ro.after"
    # -shm/-wal sidecars are WAL bookkeeping, not DB content: compare content lines only
    grep -E '^(logical|indexes) ' "$W/r4/stock.before" > "$W/r4/sb"; grep -E '^(logical|indexes) ' "$W/r4/stock.after" > "$W/r4/sa"
    grep -E '^(logical|indexes) ' "$W/r4/ro.before" > "$W/r4/rb"; grep -E '^(logical|indexes) ' "$W/r4/ro.after" > "$W/r4/ra"
    grep '^file codegraph.db ' "$W/r4/ro.before" > "$W/r4/rmb"; grep '^file codegraph.db ' "$W/r4/ro.after" > "$W/r4/rma"
    [ -s "$W/r4/sb" ] && [ -s "$W/r4/rb" ]          # instrument produced data (not BLIND)
    B1=$?
    ! cmp -s "$W/r4/sb" "$W/r4/sa"                  # control: stock DID change the logical DB
    C1=$?
    cmp -s "$W/r4/rb" "$W/r4/ra" && cmp -s "$W/r4/rmb" "$W/r4/rma" && [ "$PR4" -eq 0 ] && [ "$WALB" = "$WALA" ]   # WAL must not grow either
    S1=$?
    t_check R4 "RO session on a drifted tree leaves logical DB + main file identical (control: stock changes it)" $((B1 + C1 + S1)) "blind=$B1 control_changed=$C1 subject_unchanged=$S1 pr4=$PR4"
fi

if t_want R5; then build_ro
    FXS="$W/r5/stock"; mkfx "$FXS"; python3 "$FP" dropidx "$FXS" idx_nodes_kind idx_edges_kind
    probe "$STOCK_RUNNER" "$FXS" "${ST_ENV[@]}"; ISTOCK="$(python3 "$FP" indexes "$FXS")"
    FXR="$W/r5/ro"; mkfx "$FXR"; python3 "$FP" dropidx "$FXR" idx_nodes_kind idx_edges_kind
    IBEFORE="$(python3 "$FP" indexes "$FXR")"
    probe "$RO_RUNNER" "$FXR" "${RO_ENV[@]}"; R5PRC="$PRC"; IAFTER="$(python3 "$FP" indexes "$FXR")"
    case "$IBEFORE" in *idx_nodes_kind*) DROPPED=1 ;; *) DROPPED=0 ;; esac        # instrument: the drop took
    case "$ISTOCK" in *idx_nodes_kind*idx_edges_kind*|*idx_edges_kind*idx_nodes_kind*) HEALED=0 ;; *) HEALED=1 ;; esac   # control: stock heals
    [ "$IAFTER" = "$IBEFORE" ] && [ "$R5PRC" -eq 0 ]; SAME=$?   # session must have ANSWERED, else "unchanged" is a false-null
    t_check R5 "dropped bulk indexes are NOT recreated by an RO session (control: stock recreates them)" $((DROPPED + HEALED + SAME)) "drop_took=$((1-DROPPED)) stock_healed=$((1-HEALED)) ro_unchanged=$((1-SAME))"
fi

if t_want R6; then build_ro
    # no CODEGRAPH_NO_WATCH here: the RO runner itself must refuse to watch.
    FXR="$W/r6/ro"; mkfx "$FXR"
    PERR="$W/r6/err.ro"; mkdir -p "$W/r6"
    probe "$RO_RUNNER" "$FXR" --env CODEGRAPH_NO_DAEMON=1; R6PRC="$PRC"
    FXS="$W/r6/stock"; mkfx "$FXS"
    PERR="$W/r6/err.stock"
    probe "$STOCK_RUNNER" "$FXS" --env CODEGRAPH_NO_DAEMON=1
    PERR=""
    grep -q 'File watcher active' "$W/r6/err.stock"; CTRL=$?          # control: instrument can see 'active'
    ! grep -q 'File watcher active' "$W/r6/err.ro" && [ "$R6PRC" -eq 0 ]; NOWATCH=$?
    grep -q 'read-only' "$W/r6/err.ro"; NOTICE=$?
    t_check R6 "RO runner never starts the watcher (control: stock logs 'File watcher active')" $((CTRL + NOWATCH + NOTICE)) "control_active=$CTRL ro_no_watch=$NOWATCH ro_notice=$NOTICE"
fi

if t_want R7; then build_ro
    lockpid=999999   # PID that cannot exist (> pid_max)
    FXS="$W/r7/stock"; mkfx "$FXS"; printf '%s' "$lockpid" > "$FXS/.codegraph/codegraph.lock"; touch -d '2020-01-01' "$FXS/.codegraph/codegraph.lock"
    probe "$STOCK_RUNNER" "$FXS" "${ST_ENV[@]}"
    [ -e "$FXS/.codegraph/codegraph.lock" ] && [ "$(stat -c %Y "$FXS/.codegraph/codegraph.lock")" -lt 1600000000 ]; STOCK_KEPT=$?   # 0 = kept
    FXR="$W/r7/ro"; mkfx "$FXR"; printf '%s' "$lockpid" > "$FXR/.codegraph/codegraph.lock"; touch -d '2020-01-01' "$FXR/.codegraph/codegraph.lock"
    probe "$RO_RUNNER" "$FXR" "${RO_ENV[@]}"; R7PRC="$PRC"
    [ "$R7PRC" -eq 0 ] && [ -e "$FXR/.codegraph/codegraph.lock" ] && [ "$(stat -c %Y "$FXR/.codegraph/codegraph.lock")" -lt 1600000000 ] && [ "$(cat "$FXR/.codegraph/codegraph.lock")" = "$lockpid" ]; RO_KEPT=$?
    CTRL=0; [ "$STOCK_KEPT" -ne 0 ] || CTRL=1      # control: stock DID disturb the lock
    t_check R7 "planted lock file untouched by an RO session (control: stock disturbs it)" $((CTRL + RO_KEPT)) "stock_disturbed=$((1-CTRL)) ro_kept=$((1-RO_KEPT))"
fi

if t_want R8; then
    build_ro   # control: the SAME builder on the pristine package must succeed
    BAD="$W/r8/src"; mkdir -p "$W/r8"
    cp -a "$STOCK_SRC" "$BAD" 2>/dev/null
    python3 - "$BAD/lib/dist/mcp/engine.js" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
# duplicate the catchUpSync definition line so the anchor occurs 2x
t = t.replace("    catchUpSync() {\n", "    catchUpSync() {\n    catchUpSync() {\n", 1)
open(p, "w", encoding="utf-8").write(t)
PY
    python3 "$BUILDER" --patches mcpro1 --src "$BAD" --dst "$W/r8/out_runner" >"$W/r8/out.log" 2>&1; RC=$?
    [ "$BRC" -eq 0 ] && [ "$RC" -eq 2 ] && [ ! -e "$W/r8/out_runner" ] && grep -q "occurs 2x" "$W/r8/out.log"
    t_check R8 "control build ok AND shape mismatch (anchor 2x) => exit 2, names the anchor, no runner dir" $? "ctrl_brc=$BRC rc=$RC out=$(tail -2 "$W/r8/out.log" | tr '\n' ' ' | cut -c1-140)"
fi

fxfp() { python3 "$FP" fp "$1" | grep -E '^(logical|indexes|file codegraph.db )'; }
r9run() {
    # r9run <kind> <bin> <cli-command> — planted stale lock + drifted fixture, run the CLI writer command in the project
    local kind="$1" bin="$2" cmd="$3" d lb la
    d="$W/$cmd/$kind"; mkfx "$d"; mkdir -p "$W/$cmd"
    printf '%s' 999999 > "$d/.codegraph/codegraph.lock"; touch -d '2020-01-01' "$d/.codegraph/codegraph.lock"
    fxfp "$d" > "$W/$cmd.$kind.before"; lb="$(stat -c '%Y %s' "$d/.codegraph/codegraph.lock")"
    ( cd "$d" && CODEGRAPH_NO_UPDATE_CHECK=1 DO_NOT_TRACK=1 timeout 240 "$bin" "$cmd" > "$W/$cmd.$kind.out" 2>&1 ); echo $? > "$W/$cmd.$kind.rc"
    fxfp "$d" > "$W/$cmd.$kind.after"
    la="$([ -e "$d/.codegraph/codegraph.lock" ] && stat -c '%Y %s' "$d/.codegraph/codegraph.lock" || echo GONE)"
    [ "$lb" = "$la" ] && echo same > "$W/$cmd.$kind.lock" || echo changed > "$W/$cmd.$kind.lock"
}
misuse_check() {
    # misuse_check <id> <cli-command> — the RO runner must REFUSE a writer command (control: stock performs it)
    local id="$1" cmd="$2"
    build_ro; r9run stock "$STOCK_RUNNER" "$cmd"; r9run ro "$RO_RUNNER" "$cmd"
    ! cmp -s "$W/$cmd.stock.before" "$W/$cmd.stock.after"; local C1=$?                  # control: stock changed the logical DB
    [ "$(cat "$W/$cmd.stock.lock")" = changed ] || [ "$cmd" != sync ]; local C2=$?        # control (sync): stock disturbed the planted lock
    [ -s "$W/$cmd.ro.before" ] && cmp -s "$W/$cmd.ro.before" "$W/$cmd.ro.after" && [ "$(cat "$W/$cmd.ro.lock")" = same ]; local S1=$?
    [ "$(cat "$W/$cmd.ro.rc")" -ne 0 ] && grep -q 'helix-mcpro1' "$W/$cmd.ro.out"; local S2=$?   # refused, and says why
    t_check "$id" "RO runner REFUSES 'codegraph $cmd' (DB + planted lock untouched, non-zero exit naming helix-mcpro1; control: stock performs it)" $((C1 + C2 + S1 + S2)) "ctrl_db=$C1 ctrl_lock=$C2 ro_untouched=$S1 ro_refused=$S2 ro_rc=$(cat "$W/$cmd.ro.rc") ro_out=$(head -c 160 "$W/$cmd.ro.out" | tr '\n' ' ')"
}
kill_daemon() {
    local pf="$1/.codegraph/daemon.pid" dp
    [ -f "$pf" ] || return 0
    dp="$(tr -dc 0-9 < "$pf")"
    [ -n "$dp" ] && [ -r "/proc/$dp/cmdline" ] && tr '\0' ' ' < "/proc/$dp/cmdline" | grep -q -- '--mcp' && kill "$dp" 2>/dev/null
    return 0
}

if t_want R9; then misuse_check R9 sync; fi
if t_want R10; then misuse_check R10 index; fi

if t_want R11; then build_ro
    # NO env at all: stock defaults to a shared DETACHED DAEMON (daemon.pid/log/sock + worker pool); the RO runner must stay direct.
    FXS="$W/r11/stock"; mkfx "$FXS"; probe "$STOCK_RUNNER" "$FXS" --env CODEGRAPH_NO_DAEMON=0; kill_daemon "$FXS"; [ -e "$FXS/.codegraph/daemon.pid" ] || [ -e "$FXS/.codegraph/daemon.log" ]; CTRL=$?   # MEASURED: stock leaves daemon.log (pid file is gone once the daemon exits)
    FXR="$W/r11/ro"; mkfx "$FXR"; probe "$RO_RUNNER" "$FXR" --env CODEGRAPH_NO_DAEMON=0; R11PRC="$PRC"; kill_daemon "$FXR"
    [ "$R11PRC" -eq 0 ] && [ ! -e "$FXR/.codegraph/daemon.pid" ] && [ ! -e "$FXR/.codegraph/daemon.log" ]; NOD=$?
    t_check R11 "RO runner never starts a detached daemon even with no CODEGRAPH_NO_DAEMON (control: stock leaves daemon.log)" $((CTRL + NOD)) "control_daemon=$CTRL ro_direct=$NOD prc=$R11PRC"
fi

if t_want R12; then build_ro
    # node-level unit of the SECOND-LINE guards (paths that bypass the CLI): FileLock.acquire must throw and never unlink a
    # stale lock; release must not unlink. Control: the pristine package's acquire DOES unlink the stale lock and take it.
    cat > "$W/r12.js" <<'JS'
const fs = require('fs'), path = require('path');
const [root, lockdir] = process.argv.slice(2);
const { FileLock } = require(path.join(root, 'lib/dist/utils.js'));
const lp = path.join(lockdir, 'codegraph.lock');
fs.mkdirSync(lockdir, { recursive: true });
fs.writeFileSync(lp, '999999'); fs.utimesSync(lp, new Date('2020-01-01'), new Date('2020-01-01'));
const before = fs.statSync(lp).mtimeMs;
let threw = false, ret = null;
try { ret = new FileLock(lp).acquire(); } catch (e) { threw = String(e.message).includes('helix-mcpro1'); }
const kept = fs.existsSync(lp) && fs.statSync(lp).mtimeMs === before && fs.readFileSync(lp, 'utf8') === '999999';
console.log(JSON.stringify({ threw, ret, kept }));
JS
    NODE_BIN="$(command -v node)"
    if [ -z "$NODE_BIN" ]; then t_check R12 "node-level FileLock guards" 1 "BLIND: no node on PATH"; else
    S="$("$NODE_BIN" "$W/r12.js" "$RO_DIR" "$W/r12/ro" 2>&1 | tail -1)"
    C="$("$NODE_BIN" "$W/r12.js" "$STOCK_SRC" "$W/r12/stock" 2>&1 | tail -1)"
    python3 - "$S" "$C" <<'PY'
import json, sys
s, c = json.loads(sys.argv[1]), json.loads(sys.argv[2])
assert c["threw"] is False and c["kept"] is False, ("control must acquire+unlink the stale lock", c)   # instrument sees the stock writer
assert s["threw"] is True and s["kept"] is True, ("RO acquire must throw naming helix-mcpro1 and leave the lock", s)
PY
    t_check R12 "FileLock.acquire throws + stale lock untouched on the RO runner (control: stock unlinks it)" $? "ro=$S stock=$C"
    fi
fi

if t_want R13; then
    # registry semantics: mcpro1 is registered + selectable but NOT in the default (bulk writer) set, and exclusive.
    DEF="$(cd "$CG_DIR" && python3 -c 'import sys; sys.path.insert(0, "."); import runner_patches as r; print(",".join(m.PATCH_ID for m in r.load()))' 2>&1)"
    ALL="$(cd "$CG_DIR" && python3 -c 'import sys; sys.path.insert(0, "."); import runner_patches as r; print(",".join(r.REGISTRY))' 2>&1)"
    case ",$DEF," in *,mcpro1,*) NOTDEF=1 ;; *) NOTDEF=0 ;; esac
    case ",$ALL," in *,mcpro1,*) REGD=0 ;; *) REGD=1 ;; esac
    python3 "$BUILDER" --patches mcpro1,resolve1 --src "$STOCK_SRC" --dst "$W/r13/x" > "$W/r13.out" 2>&1; XRC=$?
    [ "$XRC" -eq 2 ] && grep -q 'exclusive' "$W/r13.out" && [ ! -e "$W/r13/x" ]; EXCL=$?
    t_check R13 "mcpro1 registered + selectable, NOT in the default patch set, exclusive with writer patches" $((NOTDEF + REGD + EXCL)) "default=[$DEF] registry=[$ALL] exclusive_rc=$XRC"
fi

t_finish
