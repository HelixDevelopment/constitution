#!/usr/bin/env bash
# ============================================================================
# test_codegraph_mcp.sh — tests for the sanctioned read-only MCP entry (codegraph_mcp.sh)
# ============================================================================
# Purpose      Prove on FIXTURES (never a real project) that codegraph_mcp.sh
#                W1 serves a real MCP session read-only (allowlist honoured: search+node+explore listed, a query answered, DB byte/logical hash unchanged, no daemon)
#                W2 refuses a project without an index (exit 3)          W6 refuses index/sync/uninit (exit 2)
#                W3 refuses while a process holds the DB open for WRITING (exit 4; control: proceeds once it exits)
#                W4 decides lock-holder liveness by /proc command line, not lock age (ancient lock + live codegraph pid => refuse;
#                   live NON-codegraph pid or dead pid => proceed)
#                W5 never falls back to the PATH `codegraph` (stub on PATH must not run; exit 5)
#                W7 pins the environment (all 8 variables in the --dry-run plan)
#                W8 accepts ONLY a receipt-valid mcpro1 runner (a writer runner is refused, exit 5)
#                W9 does not block concurrent READERS (a live RO MCP session does not make a second start refuse)
# Usage        bash test_codegraph_mcp.sh ; ONLY=W3,W4 bash test_codegraph_mcp.sh
# Inputs       CG_DIR (code under test; the mutation harness points it at a mutated COPY), STOCK_SRC, TMPDIR
# Outputs      RESULT lines + SUMMARY; exit 1 on any failure
# Side effects fixtures + runner cache + short-lived helper processes under $TMPDIR/cg_safe_tests (all killed on exit)
# Cross-refs   ../codegraph_mcp.sh, test_mcp_readonly.sh (mkfx is reused verbatim), constitution §11.4.201/.273/.224
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="${CG_DIR:-$(cd "$HERE/.." && pwd)}"
. "$HERE/lib_test.sh"
export CODEGRAPH_NO_UPDATE_CHECK=1 DO_NOT_TRACK=1 CODEGRAPH_TELEMETRY=0
unset CODEGRAPH_NO_DAEMON CODEGRAPH_NO_WATCH CODEGRAPH_MCP_TOOLS CODEGRAPH_QUERY_POOL_SIZE CODEGRAPH_MCP_READONLY CODEGRAPH_MCP_PROJECT HELIX_CODEGRAPH_MCP_RUNNER
WRAP="$CG_DIR/codegraph_mcp.sh"; PROBE="$CG_DIR/codegraph_mcp_probe.py"; FP="$HERE/cg_fp.py"
W="$(t_workdir cgmcp)"; echo "workdir $W"
STOCK_SRC="${STOCK_SRC:-$(cd "$CG_DIR" && python3 -c 'import fk_index_patch as m; print(m.default_src())' 2>/dev/null)}"
[ -d "$STOCK_SRC/lib/dist" ] || { echo "BLIND: cannot resolve stock package source (STOCK_SRC=$STOCK_SRC)"; exit 2; }
STOCK_BIN="$STOCK_SRC/bin/codegraph"; STOCK_RUNNER="$STOCK_BIN"
eval "$(sed -n '/^mkfx() {/,/^}/p' "$HERE/test_mcp_readonly.sh")"      # single source of truth for the fixture
export HELIX_CODEGRAPH_RUNNER_DIR="$W/runners" HELIX_CODEGRAPH_SRC="$STOCK_SRC"
HELPERS=""; trap 'for p in $HELPERS; do kill "$p" 2>/dev/null; done' EXIT

dry() { DOUT="$("$WRAP" --project "$1" --dry-run 2>"$W/dry.err")"; DRC=$?; DERR="$(head -c 500 "$W/dry.err" | tr '\n' ' ')"; }
holds_fd() { local i f; for i in $(seq 1 80); do for f in /proc/"$1"/fd/*; do case "$(readlink "$f" 2>/dev/null)" in *"$2"*) return 0 ;; esac; done; sleep 0.1; done; return 1; }
stopp() { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }
fxfp() { python3 "$FP" fp "$1" | grep -E '^(logical|indexes|file codegraph.db )'; }

if t_want W1; then
    FX="$W/w1/p"; mkfx "$FX"; fxfp "$FX" > "$W/w1.before"
    dry "$FX"; python3 -c 'import json,sys; d=json.loads(sys.argv[1].splitlines()[0]); assert d["ok"] is True and d["runner_key"].endswith("-mcpro1") and d["writers"]==[]' "$DOUT" 2>/dev/null; DOK=$?
    PJ="$(python3 "$PROBE" --bin "$WRAP" --project "$FX" --stderr-file "$W/w1.err" --query compute_total 2>/dev/null)"; PRC=$?
    python3 - "$PJ" <<'PY'
import json, sys
d = json.loads(sys.argv[1]); t = json.dumps(d.get("tools"))
assert d.get("init_ok") and d.get("calls_ok", 0) >= 1, d
for n in ("explore", "node", "search"):   # stock TINY-REPO gating lists only this trio on a 12-node fixture; unset CODEGRAPH_MCP_TOOLS would list only "explore" (so this still proves the pin)
    assert n in t, ("tool %s not listed" % n, t)
modes = json.dumps(d.get("db_fd_modes")); assert "rw" not in modes and "r" in modes, modes
PY
    TOK=$?
    fxfp "$FX" > "$W/w1.after"; cmp -s "$W/w1.before" "$W/w1.after" && [ ! -e "$FX/.codegraph/daemon.log" ] && [ -s "$W/w1.before" ]; UNCH=$?
    t_check W1 "wrapper serves a real read-only MCP session (pinned allowlist honoured, query answered, DB unchanged, no daemon)" $((DOK + PRC + TOK + UNCH)) "dry=$DOK probe_rc=$PRC tools_fd=$TOK unchanged=$UNCH err=$DERR"
fi

if t_want W2; then
    mkdir -p "$W/w2/empty"; dry "$W/w2/empty"
    [ "$DRC" -eq 3 ]; t_check W2 "project without an index is refused (exit 3), nothing is created" $(( $? + $([ -e "$W/w2/empty/.codegraph" ] && echo 1 || echo 0) )) "rc=$DRC err=$DERR"
fi

if t_want W3; then
    FX="$W/w3/p"; mkfx "$FX"; DB="$FX/.codegraph/codegraph.db"
    python3 -c 'import sqlite3,sys,time; c=sqlite3.connect(sys.argv[1]); c.execute("BEGIN IMMEDIATE"); time.sleep(120)' "$DB" & HP=$!; HELPERS="$HELPERS $HP"
    holds_fd "$HP" codegraph.db; HOLD=$?
    dry "$FX"; [ "$DRC" -eq 4 ] && printf '%s' "$DERR" | grep -qF "\"pid\": $HP," && printf '%s' "$DERR" | grep -q 'rw-fd'; REF=$?
    stopp "$HP"; sleep 0.3
    dry "$FX"; [ "$DRC" -eq 0 ]; CTRL=$?          # control: same fixture proceeds once the writer is gone
    t_check W3 "refuses while a process holds the DB open for writing (control: proceeds after it exits)" $((HOLD + REF + CTRL)) "holder_fd=$HOLD refused=$REF control_ok=$CTRL"
fi

if t_want W4; then
    FX="$W/w4/p"; mkfx "$FX"; LK="$FX/.codegraph/codegraph.lock"
    bash -c 'exec -a codegraph-fake-indexer sleep 120' & LP=$!; HELPERS="$HELPERS $LP"; sleep 0.3
    printf '%s' "$LP" > "$LK"; touch -d '2020-01-01' "$LK"; dry "$FX"
    [ "$DRC" -eq 4 ] && printf '%s' "$DERR" | grep -q 'lock-holder-alive'; A=$?      # ancient lock + live codegraph pid => refuse (age is not proof)
    stopp "$LP"
    sleep 120 & NP=$!; HELPERS="$HELPERS $NP"; printf '%s' "$NP" > "$LK"; touch -d '2020-01-01' "$LK"; dry "$FX"
    [ "$DRC" -eq 0 ]; B=$?                                                             # live but NOT codegraph => no false refusal
    stopp "$NP"
    printf '%s' 999999 > "$LK"; dry "$FX"; [ "$DRC" -eq 0 ]; C=$?                      # dead pid => proceed
    t_check W4 "lock holder judged by live /proc cmdline, not lock age (refuse ancient+live codegraph; allow live non-codegraph, dead)" $((A + B + C)) "refuse=$A allow_noncg=$B allow_dead=$C"
fi

if t_want W5; then
    FX="$W/w5/p"; mkfx "$FX"; mkdir -p "$W/w5/bin"
    printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$W/w5/STUB_RAN" > "$W/w5/bin/codegraph"; chmod +x "$W/w5/bin/codegraph"
    PATH="$W/w5/bin:$PATH" HELIX_CODEGRAPH_SRC=/nonexistent/pkg HELIX_CODEGRAPH_RUNNER_DIR="$W/w5/runners" "$WRAP" --project "$FX" --dry-run >/dev/null 2>"$W/w5.err1"; R1=$?
    ( cd "$FX" && PATH="$W/w5/bin:$PATH" HELIX_CODEGRAPH_SRC=/nonexistent/pkg HELIX_CODEGRAPH_RUNNER_DIR="$W/w5/runners" "$WRAP" serve --mcp </dev/null >/dev/null 2>"$W/w5.err2" ); R2=$?
    [ "$R1" -eq 5 ] && [ "$R2" -eq 5 ] && [ ! -e "$W/w5/STUB_RAN" ]; NEG=$?
    t_check W5 "no fallback to the PATH codegraph when the mcpro1 runner cannot be provided (stub never runs, exit 5)" $NEG "rc_dry=$R1 rc_exec=$R2 stub_ran=$([ -e "$W/w5/STUB_RAN" ] && echo yes || echo no) err=$(head -c 160 "$W/w5.err2" | tr '\n' ' ')"
fi

if t_want W6; then
    FX="$W/w6/p"; mkfx "$FX"; BAD=0
    for c in index sync uninit init; do "$WRAP" --project "$FX" "$c" >/dev/null 2>"$W/w6.$c.err"; rc=$?; { [ "$rc" -eq 2 ] && grep -q 'refusing' "$W/w6.$c.err"; } || BAD=$((BAD+1)); done
    t_check W6 "index/sync/uninit/init are refused (exit 2) before any runner is resolved" $BAD "bad=$BAD"
fi

if t_want W7; then
    FX="$W/w7/p"; mkfx "$FX"; dry "$FX"; MISS=""
    for kv in CODEGRAPH_NO_DAEMON=1 CODEGRAPH_NO_WATCH=1 CODEGRAPH_NO_UPDATE_CHECK=1 DO_NOT_TRACK=1 CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_PROMPT_HOOK=1 CODEGRAPH_QUERY_POOL_SIZE=0 CODEGRAPH_MCP_TOOLS=explore,node,search,callers,callees,impact,files,status; do
        printf '%s\n' "$DOUT" | grep -qxF "ENV $kv" || MISS="$MISS $kv"
    done
    [ "$DRC" -eq 0 ] && [ -z "$MISS" ]; t_check W7 "the dry-run plan pins all 8 environment variables" $? "missing=[$MISS]"
fi

if t_want W8; then
    FX="$W/w8/p"; mkfx "$FX"
    python3 "$CG_DIR/fk_index_patch.py" --patches resolve1 --src "$STOCK_SRC" --dst "$W/w8/writer" >"$W/w8.build" 2>&1; WB=$?
    HELIX_CODEGRAPH_MCP_RUNNER="$W/w8/writer/bin/codegraph" "$WRAP" --project "$FX" --dry-run >/dev/null 2>"$W/w8.err"; WRC=$?
    GOOD="$(ls -d "$W"/runners/*-mcpro1/bin/codegraph 2>/dev/null | head -1)"
    HELIX_CODEGRAPH_MCP_RUNNER="$GOOD" "$WRAP" --project "$FX" --dry-run >/dev/null 2>&1; GRC=$?      # control: a valid mcpro1 runner is accepted
    [ "$WB" -eq 0 ] && [ "$WRC" -eq 5 ] && [ "$GRC" -eq 0 ] && grep -q 'mcpro1' "$W/w8.err"
    t_check W8 "a writer runner is refused (exit 5, receipt says not mcpro1); a valid mcpro1 runner is accepted" $? "build=$WB writer_rc=$WRC good_rc=$GRC err=$(head -c 200 "$W/w8.err" | tr '\n' ' ')"
fi

if t_want W9; then
    FX="$W/w9/p"; mkfx "$FX"
    python3 "$PROBE" --bin "$WRAP" --project "$FX" --hold 7 --stderr-file "$W/w9.err" >"$W/w9.probe" 2>&1 & P1=$!; HELPERS="$HELPERS $P1"
    sleep 3.5; dry "$FX"; D2=$DRC; DE="$DERR"
    wait "$P1" 2>/dev/null
    [ "$D2" -eq 0 ]; t_check W9 "a live read-only MCP session does not make a second start refuse (readers never block readers)" $? "second_dry_rc=$D2 err=$DE"
fi

t_finish
