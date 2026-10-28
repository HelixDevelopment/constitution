#!/usr/bin/env bash
# cm_codegraph_mcp_health_mutation_test.sh — §1.1 paired-mutation meta-test for CM-CODEGRAPH-MCP-HEALTH (+ its health tool).
# Hermetic: a real, tiny CodeGraph fixture index (built by the STOCK writer exactly as tests/test_mcp_readonly.sh does) in a scratch
# directory; the real project, its index and the operator's ~/.claude.json are never touched (HOME / CLAUDE_CONFIG_DIR are scratch).
# Part 1 — fixture classification with the REAL gate / tool (every verdict asserted):
#   gate rc 0 PASS    HEALTHY (real wrapper + probe symbol with controls) · STALE-LOCK-DEAD (dead holder is WARN only — golden-FALSE)
#                     · LOCK-LIVE-NON-CODEGRAPH (a live NON-codegraph pid in the lock is stale, not a holder)
#   gate rc 1 FAIL    ANCHOR-DRIFT (the runner patch no longer matches -> wrapper exit 5 + empty stdout: THE incident)
#                     · MISSING-WRAPPER · VERSION-PIN-MISMATCH · SERVER-EXITS-EARLY (EOF before initialize)
#                     · SERVER-HANGS-AFTER-INIT · SERVER-EMPTY-TOOLS · SEARCH-MATCHES-ANYTHING (negative control fails)
#                     · WRAPPER-WRITES-DAEMON-FILE (a "read-only" server that leaves daemon.pid behind)
#   gate rc 2 BLIND   TOOL-EXITS-0-WITHOUT-ROUNDTRIP (stub tool, no H8 line) · gate refuses --heal / --no-roundtrip
#   gate rc 3 SKIP    NOTHING-DECLARED (no .mcp.json, no index) · BUSY (tool rc 4: a live writer, never PASS/FAIL)
#   tool-level        WAL-OVERSIZE (H5 FAIL, healthy copy H5 PASS) · HEAL-REAPS-DEAD-LOCK · HEAL-REAPS-PID-REUSE
#                     · HEAL-KEEPS-LIVE-CODEGRAPH-HOLDER · HEAL-CHECKPOINT (WAL truncated) · HEAL-CHECKPOINT-SKIPPED-WITH-HOLDER
#                     · HEAL-NEVER-FAKES (anchor drift + --heal stays FAIL and reports NEEDS-PATCH-UPDATE)
# Part 2 — mutants: the tool/gate is copied, ONE defect is injected per mutant, and the cases that mutant targets are re-classified;
#   each mutant MUST flip at least one verdict (be KILLED); a survivor means a defect class is invisible to the fixtures.
# Usage: cm_codegraph_mcp_health_mutation_test.sh   Exit: 0 proof holds · 1 misclassified / survivor · 2 environment error (BLIND).
# Side-effects: temp dir under $TMPDIR (trap-cleaned; stray fixture processes are killed). Dependencies: bash, python3, git, sed, cmp,
#   a stock codegraph 1.6.x install. Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CGD="$(cd "$here/../codegraph" && pwd)"
GATE="$here/cm_codegraph_mcp_health.sh"; TOOL="$CGD/codegraph_mcp_health.py"
for f in "$GATE" "$TOOL" "$CGD/codegraph_mcp.sh" "$CGD/tests/test_mcp_readonly.sh"; do [ -r "$f" ] || { echo "META BLIND: missing $f" >&2; exit 2; }; done
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cg_health_meta.XXXXXX")"
PIDS=""; trap 'for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$tmp"' EXIT
export CODEGRAPH_NO_UPDATE_CHECK=1 DO_NOT_TRACK=1 CODEGRAPH_TELEMETRY=0
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/cfg"; mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
unset CODEGRAPH_NO_DAEMON CODEGRAPH_NO_WATCH CODEGRAPH_MCP_TOOLS CODEGRAPH_QUERY_POOL_SIZE CODEGRAPH_MCP_READONLY CODEGRAPH_MCP_PROJECT HELIX_CODEGRAPH_MCP_RUNNER
STOCK_BIN="$(PATH="$PATH" command -v codegraph)" || { echo "META BLIND: no stock codegraph on PATH" >&2; exit 2; }
STOCK_SRC="${STOCK_SRC:-$(cd "$CGD" && python3 -c 'import fk_index_patch as m; print(m.default_src())' 2>/dev/null)}"
[ -d "$STOCK_SRC/lib/dist" ] || { echo "META BLIND: cannot resolve the stock package source" >&2; exit 2; }
eval "$(sed -n '/^mkfx() {/,/^}/p' "$CGD/tests/test_mcp_readonly.sh")"      # mkfx: tiny git project indexed by the stock writer
export HELIX_CODEGRAPH_SRC="$STOCK_SRC" HELIX_CODEGRAPH_RUNNER_DIR="$tmp/runners"
bad=0
fail() { echo "BAD  $*"; bad=1; }
ok() { echo "ok   $*"; }

# ── tooling copies: a good one and one whose runner patch anchor is mutated (simulated upstream drift) ──────────────────────
mkdir -p "$tmp/t_ok" "$tmp/t_drift"
cp -a "$CGD" "$tmp/t_ok/codegraph"; cp -a "$CGD" "$tmp/t_drift/codegraph"; rm -rf "$tmp/t_ok/codegraph/tests" "$tmp/t_drift/codegraph/tests"
sed -i 's/^OPEN_ANCHOR_B = "    static open(dbPath, options = {}) {"/OPEN_ANCHOR_B = "    static NOPE_open(dbPath, options = {}) {"/' "$tmp/t_drift/codegraph/runner_patches/mcpro1.py"
cmp -s "$CGD/runner_patches/mcpro1.py" "$tmp/t_drift/codegraph/runner_patches/mcpro1.py" && { echo "META BLIND: drift mutation did not apply (mcpro1 anchor literal changed upstream?)" >&2; exit 2; }
W_OK="$tmp/t_ok/codegraph/codegraph_mcp.sh"; W_DRIFT="$tmp/t_drift/codegraph/codegraph_mcp.sh"

# ── stub MCP server (python) — modes: ok | hang | empty | search_any ───────────────────────────────────────────────────────
cat > "$tmp/stub_mcp.py" <<'PY'
import json, sys, time
mode = sys.argv[1]
def out(o): sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    try: m = json.loads(line)
    except ValueError: continue
    mid, meth = m.get("id"), m.get("method")
    if meth == "initialize":
        out({"jsonrpc": "2.0", "id": mid, "result": {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "stub", "version": "0"}}})
    elif meth == "tools/list":
        if mode == "hang": time.sleep(600)
        tools = [] if mode == "empty" else [{"name": "codegraph_status"}, {"name": "codegraph_search"}]
        out({"jsonrpc": "2.0", "id": mid, "result": {"tools": tools}})
    elif meth == "tools/call":
        p = m.get("params", {}); name, q = p.get("name"), (p.get("arguments") or {}).get("query", "")
        if name == "codegraph_status": txt = "files: 3 nodes: 9"
        elif mode == "search_any": txt = "**Search Results (1 found)**\n\n**%s** (function)" % q
        else: txt = "No results found for \"%s\"" % q
        out({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": txt}]}})
PY
# wrapper-named stub that behaves like a server but leaves a daemon.pid behind (a "read-only" server that writes)
mkdir -p "$tmp/wstub"
cat > "$tmp/wstub/codegraph_mcp.sh" <<EOF
#!/usr/bin/env bash
[ "\${1:-}" = "--dry-run" ] && { echo '{"ok": true}'; exit 0; }
mkdir -p "\$PWD/.codegraph"; echo '{"pid": 1}' > "\$PWD/.codegraph/daemon.pid"
exec python3 "$tmp/stub_mcp.py" ok
EOF
chmod +x "$tmp/wstub/codegraph_mcp.sh"
cat > "$tmp/stub_exit.sh" <<'EOF'
#!/usr/bin/env bash
echo "stub: cannot provide the runner" >&2; exit 5
EOF
chmod +x "$tmp/stub_exit.sh"
printf 'print("HEALTH H1 PASS stub")\nprint("SUMMARY fail=0 warn=0")\n' > "$tmp/tool_noroundtrip.py"
printf 'print("HEALTH H8 SKIP busy")\nraise SystemExit(4)\n' > "$tmp/tool_busy.py"
printf 'print("HEALTH H1 SKIP nothing")\nraise SystemExit(3)\n' > "$tmp/tool_nothing.py"

echo "── building the fixture index with the stock writer"
mkfx "$tmp/base/proj" || { echo "META BLIND: fixture build failed" >&2; exit 2; }
SYMBOL="compute_total"
mcpjson() { printf '{"mcpServers":{"codegraph":{"type":"stdio","command":"%s","args":%s}}}\n' "$2" "$3" > "$1/.mcp.json"; }
newproj() { local d="$tmp/cases/$1"; mkdir -p "$tmp/cases"; cp -a "$tmp/base/proj" "$d"; printf '%s\n' "$d"; }
wrap_json() { mcpjson "$1" bash "[\"$2\"]"; }

# live "codegraph-looking" holder and a live non-codegraph holder
mkdir -p "$tmp/fake"; cp "$(command -v sleep)" "$tmp/fake/codegraph"
"$tmp/fake/codegraph" 600 & CGPID=$!; PIDS="$PIDS $CGPID"
sleep 600 & OTHERPID=$!; PIDS="$PIDS $OTHERPID"

g() { # g <proj> [gate-args...]  -> sets GRC and GOUT (gate + stub tool via env as already exported)
  local p="$1"; shift
  GOUT="$(cd "$p" && timeout 400 bash "${GATE_UNDER_TEST:-$GATE}" --project "$p" "$@" 2>&1)"; GRC=$?
}
expect_gate() { # <label> <expected-rc> <proj> [args...]
  local lab="$1" want="$2" p="$3"; shift 3; g "$p" "$@"
  if [ "$GRC" = "$want" ]; then ok "$lab -> gate rc $GRC"; else fail "$lab expected gate rc $want, got $GRC"; printf '%s\n' "$GOUT" | sed 's/^/       /' | cut -c1-260 | tail -12; fi
}
export CG_HEALTH_TOOL="$TOOL"

echo "── Part 1: fixture classification with the real gate"
P="$(newproj HEALTHY)"; wrap_json "$P" "$W_OK"
expect_gate HEALTHY 0 "$P" --probe-symbol "$SYMBOL"
grep -q "known symbol '$SYMBOL' found; fabricated symbol not found" <<<"$GOUT" && ok "HEALTHY carries both controls (positive + negative)" || fail "HEALTHY did not report both controls"
P="$(newproj STALE-LOCK-DEAD)"; wrap_json "$P" "$W_OK"; printf '999999' > "$P/.codegraph/codegraph.lock"
expect_gate STALE-LOCK-DEAD 0 "$P" --probe-symbol "$SYMBOL"
grep -q '^HEALTH H4 WARN stale' <<<"$GOUT" && ok "STALE-LOCK-DEAD is reported (WARN) but is not a FAIL" || fail "STALE-LOCK-DEAD not reported as a WARN"
P="$(newproj LOCK-LIVE-NON-CODEGRAPH)"; wrap_json "$P" "$W_OK"; printf '%s' "$OTHERPID" > "$P/.codegraph/codegraph.lock"
expect_gate LOCK-LIVE-NON-CODEGRAPH 0 "$P" --probe-symbol "$SYMBOL"
P="$(newproj ANCHOR-DRIFT)"; wrap_json "$P" "$W_DRIFT"
HELIX_CODEGRAPH_RUNNER_DIR="$tmp/runners_drift" expect_gate ANCHOR-DRIFT 1 "$P"
grep -q "^HEALTH H3 FAIL .*REFUSED" <<<"$GOUT" && grep -q "^HEALTH H8 FAIL .*before answering initialize" <<<"$GOUT" \
  && ok "ANCHOR-DRIFT names the REFUSED patch (H3) AND the client-visible EOF (H8)" || fail "ANCHOR-DRIFT did not report both H3 REFUSED and the H8 EOF"
P="$(newproj MISSING-WRAPPER)"; wrap_json "$P" "$tmp/nowhere/codegraph_mcp.sh"; expect_gate MISSING-WRAPPER 1 "$P"
P="$(newproj VERSION-PIN-MISMATCH)"; wrap_json "$P" "$W_OK"; expect_gate VERSION-PIN-MISMATCH 1 "$P" --expect-version 0.0.1
P="$(newproj SERVER-EXITS-EARLY)"; mcpjson "$P" bash "[\"$tmp/stub_exit.sh\"]"; expect_gate SERVER-EXITS-EARLY 1 "$P"
P="$(newproj SERVER-HANGS-AFTER-INIT)"; mcpjson "$P" python3 "[\"$tmp/stub_mcp.py\",\"hang\"]"; expect_gate SERVER-HANGS-AFTER-INIT 1 "$P" --timeout-list 3
P="$(newproj SERVER-EMPTY-TOOLS)"; mcpjson "$P" python3 "[\"$tmp/stub_mcp.py\",\"empty\"]"; expect_gate SERVER-EMPTY-TOOLS 1 "$P"
P="$(newproj SEARCH-MATCHES-ANYTHING)"; mcpjson "$P" python3 "[\"$tmp/stub_mcp.py\",\"search_any\"]"; expect_gate SEARCH-MATCHES-ANYTHING 1 "$P" --probe-symbol "$SYMBOL"
P="$(newproj WRAPPER-WRITES-DAEMON-FILE)"; wrap_json "$P" "$tmp/wstub/codegraph_mcp.sh"; rm -f "$P/.codegraph/daemon.pid"; expect_gate WRAPPER-WRITES-DAEMON-FILE 1 "$P"
grep -q "created \['daemon.pid'\]" <<<"$GOUT" && ok "WRAPPER-WRITES-DAEMON-FILE names the created file" || fail "WRAPPER-WRITES-DAEMON-FILE did not name the created file"
P="$(newproj TOOL-EXITS-0-WITHOUT-ROUNDTRIP)"; wrap_json "$P" "$W_OK"
CG_HEALTH_TOOL="$tmp/tool_noroundtrip.py" expect_gate TOOL-EXITS-0-WITHOUT-ROUNDTRIP 2 "$P"
P="$(newproj BUSY)"; wrap_json "$P" "$W_OK"; CG_HEALTH_TOOL="$tmp/tool_busy.py" expect_gate BUSY 3 "$P"
P="$(newproj NOTHING-DECLARED)"; rm -rf "$P/.codegraph" "$P/.mcp.json"; expect_gate NOTHING-DECLARED 3 "$P"
# R2-F6: a `.codegraph` directory holding only a tracked .gitignore (every constitution checkout) is NOT an index: SKIP, never FAIL
P="$(newproj NOTHING-DECLARED-GITIGNORE-ONLY)"; rm -rf "$P/.codegraph" "$P/.mcp.json"; mkdir -p "$P/.codegraph"; printf '*\n' > "$P/.codegraph/.gitignore"; expect_gate NOTHING-DECLARED-GITIGNORE-ONLY 3 "$P"
# control needle for the case above: the same project WITH the index database and no declared server must NOT skip
P="$(newproj INDEXED-NOT-DECLARED)"; rm -f "$P/.mcp.json"; expect_gate INDEXED-NOT-DECLARED 1 "$P"
P="$(newproj GATE-REFUSES-HEAL)"; wrap_json "$P" "$W_OK"; expect_gate GATE-REFUSES-HEAL 2 "$P" --heal
expect_gate GATE-REFUSES-NO-ROUNDTRIP 2 "$P" --no-roundtrip

echo "── Part 1b: tool-level cases (WAL thresholds + self-heal safety)"
tool() { (cd "$1" && timeout 400 python3 "${TOOL_UNDER_TEST:-$TOOL}" --project "$1" "${@:2}" 2>&1); }
P="$(newproj WAL-OVERSIZE)"; wrap_json "$P" "$W_OK"; truncate -s 2G "$P/.codegraph/codegraph.db-wal"
OUT="$(tool "$P" --no-roundtrip --wal-fail-gib 1)"; RC=$?
{ [ "$RC" = 1 ] && grep -q '^HEALTH H5 FAIL ' <<<"$OUT"; } && ok "WAL-OVERSIZE (2 GiB WAL, fail >= 1 GiB) -> H5 FAIL, rc 1" || { fail "WAL-OVERSIZE expected H5 FAIL rc 1 (rc=$RC)"; sed 's/^/       /' <<<"$OUT" | grep H5; }
P="$(newproj WAL-SMALL)"; wrap_json "$P" "$W_OK"
OUT="$(tool "$P" --no-roundtrip --wal-fail-gib 1)"; RC=$?
grep -q '^HEALTH H5 PASS ' <<<"$OUT" && ok "WAL-SMALL healthy copy -> H5 PASS (golden-FALSE for the WAL check)" || fail "WAL-SMALL expected H5 PASS"

P="$(newproj HEAL-REAPS-DEAD-LOCK)"; wrap_json "$P" "$W_OK"
printf '999999' > "$P/.codegraph/codegraph.lock"; printf '{"pid":999998,"mode":"daemon","startedAt":1,"ready":false}' > "$P/.codegraph/writer.pid"
OUT="$(tool "$P" --heal --no-roundtrip)"
{ grep -q '^HEAL A1 DONE moved codegraph.lock' <<<"$OUT" && grep -q '^HEAL A1 DONE moved writer.pid' <<<"$OUT" && [ ! -e "$P/.codegraph/codegraph.lock" ] && [ ! -e "$P/.codegraph/writer.pid" ] \
  && [ -n "$(ls "$P"/.codegraph/index_runs/health_reaped_*/codegraph.lock 2>/dev/null)" ]; } \
  && ok "HEAL-REAPS-DEAD-LOCK moves dead-holder files aside (reversible), nothing deleted" || { fail "HEAL-REAPS-DEAD-LOCK"; sed 's/^/       /' <<<"$OUT" | grep -E "H4|HEAL"; }
P="$(newproj HEAL-REAPS-PID-REUSE)"; wrap_json "$P" "$W_OK"; printf '%s' "$OTHERPID" > "$P/.codegraph/codegraph.lock"
OUT="$(tool "$P" --heal --no-roundtrip)"
{ grep -q '^HEAL A1 DONE moved codegraph.lock' <<<"$OUT" && [ ! -e "$P/.codegraph/codegraph.lock" ]; } \
  && ok "HEAL-REAPS-PID-REUSE: a live NON-codegraph pid does not make a lock live" || { fail "HEAL-REAPS-PID-REUSE"; sed 's/^/       /' <<<"$OUT" | grep -E "H4|HEAL"; }
P="$(newproj HEAL-KEEPS-LIVE-CODEGRAPH-HOLDER)"; wrap_json "$P" "$W_OK"; printf '%s' "$CGPID" > "$P/.codegraph/codegraph.lock"
OUT="$(tool "$P" --heal --no-roundtrip)"
{ [ -e "$P/.codegraph/codegraph.lock" ] && ! grep -q '^HEAL A1 DONE moved codegraph.lock' <<<"$OUT" && kill -0 "$CGPID" 2>/dev/null; } \
  && ok "HEAL-KEEPS-LIVE-CODEGRAPH-HOLDER: a live codegraph holder's lock is never touched and the holder is not killed" || { fail "HEAL-KEEPS-LIVE-CODEGRAPH-HOLDER"; sed 's/^/       /' <<<"$OUT" | grep -E "H4|HEAL"; }

mk_wal() { # <proj>: leave an uncheckpointed WAL behind (writer killed with SIGKILL, no clean close)
  python3 - "$1/.codegraph/codegraph.db" <<'PY'
import os, sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("PRAGMA journal_mode=WAL"); c.execute("PRAGMA wal_autocheckpoint=0")
c.execute("CREATE TABLE IF NOT EXISTS hm_scratch(x TEXT)")
c.executemany("INSERT INTO hm_scratch VALUES (?)", [("x" * 1000,) for _ in range(3000)]); c.commit()
os.kill(os.getpid(), 9)
PY
}
P="$(newproj HEAL-CHECKPOINT)"; wrap_json "$P" "$W_OK"; mk_wal "$P" 2>/dev/null; B="$(stat -c %s "$P/.codegraph/codegraph.db-wal" 2>/dev/null || echo 0)"
OUT="$(tool "$P" --heal --no-roundtrip --wal-warn-mb 1)"; A="$(stat -c %s "$P/.codegraph/codegraph.db-wal" 2>/dev/null || echo 0)"
{ [ "$B" -gt 1048576 ] && grep -q '^HEAL A2 DONE wal_checkpoint(TRUNCATE)' <<<"$OUT" && [ "$A" -lt "$B" ]; } \
  && ok "HEAL-CHECKPOINT: WAL $B -> $A bytes via wal_checkpoint(TRUNCATE) with no live holder" || { fail "HEAL-CHECKPOINT (before=$B after=$A)"; sed 's/^/       /' <<<"$OUT" | grep -E "H5|HEAL"; }
P="$(newproj HEAL-CHECKPOINT-SKIPPED-WITH-HOLDER)"; wrap_json "$P" "$W_OK"; mk_wal "$P" 2>/dev/null; B="$(stat -c %s "$P/.codegraph/codegraph.db-wal" 2>/dev/null || echo 0)"
python3 -c 'import sqlite3,sys,time; c=sqlite3.connect(sys.argv[1]); c.execute("select 1 from sqlite_master limit 1").fetchall(); time.sleep(300)' "$P/.codegraph/codegraph.db" & HOLD=$!; PIDS="$PIDS $HOLD"; sleep 1
OUT="$(tool "$P" --heal --no-roundtrip --wal-warn-mb 1)"; kill "$HOLD" 2>/dev/null
grep -q '^HEAL A2 SKIP live holder' <<<"$OUT" && ok "HEAL-CHECKPOINT-SKIPPED-WITH-HOLDER: no checkpoint while a process holds the database open" || { fail "HEAL-CHECKPOINT-SKIPPED-WITH-HOLDER"; sed 's/^/       /' <<<"$OUT" | grep -E "H5|HEAL"; }
P="$(newproj HEAL-NEVER-FAKES)"; wrap_json "$P" "$W_DRIFT"
OUT="$(HELIX_CODEGRAPH_RUNNER_DIR="$tmp/runners_drift2" tool "$P" --heal)"; RC=$?
{ [ "$RC" = 1 ] && grep -q '^HEAL A3 REFUSED NEEDS-PATCH-UPDATE' <<<"$OUT"; } \
  && ok "HEAL-NEVER-FAKES: under anchor drift --heal reports NEEDS-PATCH-UPDATE and the verdict stays FAIL (stock never substituted)" || { fail "HEAL-NEVER-FAKES (rc=$RC)"; sed 's/^/       /' <<<"$OUT" | grep -E "H3|HEAL|SUMMARY"; }

echo "── Part 2: mutants (each MUST be killed)"
mkdir -p "$tmp/mut"
# mutant <label> <target: tool|gate> <sed-expression> <case-spec>...   case-spec = kind:fixture:expected-rc[:extra-args]
#   kind gate = run the (mutated) gate/tool on the fixture and compare rc; kind tool = run the mutated tool and compare rc
mut_tool() { local m="$tmp/mut/$1"; mkdir -p "$m"; cp "$TOOL" "$m/codegraph_mcp_health.py"; sed -i "$2" "$m/codegraph_mcp_health.py"
  cmp -s "$m/codegraph_mcp_health.py" "$TOOL" && { fail "mutant $1 did not apply"; return 1; }; return 0; }
killed_if_any_flip() { local label="$1"; shift; local flipped=0 spec; for spec in "$@"; do
    local kind rest case_ rest2 want extra p got
    kind="${spec%%|*}"; rest="${spec#*|}"; case_="${rest%%|*}"; rest2="${rest#*|}"; want="${rest2%%|*}"; extra=""
    [ "$rest2" != "$want" ] && extra="${rest2#*|}"
    p="$tmp/cases/$case_"
    # shellcheck disable=SC2086
    if [ "$kind" = gate ]; then g "$p" $extra; got="$GRC"; else tool "$p" $extra >/dev/null; got=$?; fi
    [ "$got" != "$want" ] && flipped=1
  done
  [ "$flipped" = 1 ] && ok "mutant $label killed" || fail "mutant $label SURVIVED"; }

mut_tool M1-empty-tools-accepted 's/    if not tools:/    if False:/' && { export CG_HEALTH_TOOL="$tmp/mut/M1-empty-tools-accepted/codegraph_mcp_health.py"; killed_if_any_flip M1-empty-tools-accepted "gate|SERVER-EMPTY-TOOLS|1"; }
mut_tool M2-init-failure-not-fail 's/        say("H8", "FAIL", "%s; stderr: %s" % (why,/        say("H8", "WARN", "%s; stderr: %s" % (why,/' && { export CG_HEALTH_TOOL="$tmp/mut/M2-init-failure-not-fail/codegraph_mcp_health.py"; killed_if_any_flip M2-init-failure-not-fail "gate|SERVER-EXITS-EARLY|1"; }
mut_tool M3-version-pin-ignored 's/    if expect and eff != expect:/    if False:/' && { export CG_HEALTH_TOOL="$tmp/mut/M3-version-pin-ignored/codegraph_mcp_health.py"; killed_if_any_flip M3-version-pin-ignored "gate|VERSION-PIN-MISMATCH|1|--expect-version 0.0.1"; }
mut_tool M4-liveness-by-pid-only 's/    return "codegraph" if is_codegraph_process(argv) else "other"/    return "codegraph"/' && { TOOL_UNDER_TEST="$tmp/mut/M4-liveness-by-pid-only/codegraph_mcp_health.py"; P="$(newproj M4-case)"; wrap_json "$P" "$W_OK"; printf '%s' "$OTHERPID" > "$P/.codegraph/codegraph.lock"
  OUT="$(TOOL_UNDER_TEST="$TOOL_UNDER_TEST" tool "$P" --heal --no-roundtrip)"; grep -q '^HEAL A1 DONE moved codegraph.lock' <<<"$OUT" && fail "mutant M4-liveness-by-pid-only SURVIVED" || ok "mutant M4-liveness-by-pid-only killed"; unset TOOL_UNDER_TEST; }
mut_tool M5-reap-without-liveness '/^def holder_state/,/^def /s/^    argv = proc_argv(pid)$/    argv = None/' && { TOOL_UNDER_TEST="$tmp/mut/M5-reap-without-liveness/codegraph_mcp_health.py"; P="$(newproj M5-case)"; wrap_json "$P" "$W_OK"; printf '%s' "$CGPID" > "$P/.codegraph/codegraph.lock"
  OUT="$(TOOL_UNDER_TEST="$TOOL_UNDER_TEST" tool "$P" --heal --no-roundtrip)"; grep -q '^HEAL A1 DONE moved codegraph.lock' <<<"$OUT" && ok "mutant M5-reap-without-liveness killed" || fail "mutant M5-reap-without-liveness SURVIVED"; unset TOOL_UNDER_TEST; }
mut_tool M6-wal-never-fails 's/    if sz >= fail_gib \* 1073741824:/    if False:/' && { TOOL_UNDER_TEST="$tmp/mut/M6-wal-never-fails/codegraph_mcp_health.py"; killed_if_any_flip M6-wal-never-fails "tool|WAL-OVERSIZE|1|--no-roundtrip --wal-fail-gib 1"; unset TOOL_UNDER_TEST; }
mut_tool M7-checkpoint-despite-holder 's/        elif h:$/        elif False:/' && { TOOL_UNDER_TEST="$tmp/mut/M7-checkpoint-despite-holder/codegraph_mcp_health.py"; P="$(newproj M7-case)"; wrap_json "$P" "$W_OK"; mk_wal "$P" 2>/dev/null
  python3 -c 'import sqlite3,sys,time; c=sqlite3.connect(sys.argv[1]); c.execute("select 1 from sqlite_master limit 1").fetchall(); time.sleep(300)' "$P/.codegraph/codegraph.db" & HOLD=$!; PIDS="$PIDS $HOLD"; sleep 1
  OUT="$(TOOL_UNDER_TEST="$TOOL_UNDER_TEST" tool "$P" --heal --no-roundtrip --wal-warn-mb 1)"; kill "$HOLD" 2>/dev/null
  grep -q '^HEAL A2 SKIP live holder' <<<"$OUT" && fail "mutant M7-checkpoint-despite-holder SURVIVED" || ok "mutant M7-checkpoint-despite-holder killed"; unset TOOL_UNDER_TEST; }
mut_tool M8-created-files-unchecked 's/    if status == "PASS" and created and wrapper_of(cmd, project):/    if False:/' && { export CG_HEALTH_TOOL="$tmp/mut/M8-created-files-unchecked/codegraph_mcp_health.py"; killed_if_any_flip M8-created-files-unchecked "gate|WRAPPER-WRITES-DAEMON-FILE|1"; }
mut_tool M9-negative-control-dropped 's/        elif ok3 is None or (m3 and int(m3.group(1)) > 0):/        elif False:/' && { export CG_HEALTH_TOOL="$tmp/mut/M9-negative-control-dropped/codegraph_mcp_health.py"; killed_if_any_flip M9-negative-control-dropped "gate|SEARCH-MATCHES-ANYTHING|1|--probe-symbol $SYMBOL"; }
mut_tool M10-drift-not-reported 's/    if heal and drift:/    if False:/' && { TOOL_UNDER_TEST="$tmp/mut/M10-drift-not-reported/codegraph_mcp_health.py"; P="$tmp/cases/HEAL-NEVER-FAKES"
  OUT="$(HELIX_CODEGRAPH_RUNNER_DIR="$tmp/runners_drift3" TOOL_UNDER_TEST="$TOOL_UNDER_TEST" tool "$P" --heal)"; grep -q '^HEAL A3 REFUSED NEEDS-PATCH-UPDATE' <<<"$OUT" && fail "mutant M10-drift-not-reported SURVIVED" || ok "mutant M10-drift-not-reported killed"; unset TOOL_UNDER_TEST; }
export CG_HEALTH_TOOL="$TOOL"
# gate mutants
mut_gate() { local m="$tmp/mut/$1"; mkdir -p "$m"; cp "$GATE" "$m/g.sh"; sed -i "$2" "$m/g.sh"; cmp -s "$m/g.sh" "$GATE" && { fail "gate mutant $1 did not apply"; return 1; }; GATE_UNDER_TEST="$m/g.sh"; return 0; }
mut_gate G1-no-roundtrip-evidence-required 's/if grep -q .^HEALTH H1 PASS . <<<"$out" \&\& grep -q .^HEALTH H8 PASS . <<<"$out"; then/if true; then/' \
  && { P="$tmp/cases/TOOL-EXITS-0-WITHOUT-ROUNDTRIP"; CG_HEALTH_TOOL="$tmp/tool_noroundtrip.py" g "$P"; [ "$GRC" = 2 ] && fail "gate mutant G1-no-roundtrip-evidence-required SURVIVED" || ok "gate mutant G1-no-roundtrip-evidence-required killed"; }
mut_gate G2-busy-reads-as-pass 's/^  4) echo .*$/  4) echo "PASS"; exit 0 ;;/' \
  && { P="$tmp/cases/BUSY"; CG_HEALTH_TOOL="$tmp/tool_busy.py" g "$P"; [ "$GRC" = 3 ] && fail "gate mutant G2-busy-reads-as-pass SURVIVED" || ok "gate mutant G2-busy-reads-as-pass killed"; }
mut_gate G3-heal-allowed 's/^    --no-roundtrip|--heal) .*$/    --no-roundtrip|--heal) args+=("$1"); shift ;;/' \
  && { P="$tmp/cases/GATE-REFUSES-HEAL"; g "$P" --heal; [ "$GRC" = 2 ] && fail "gate mutant G3-heal-allowed SURVIVED" || ok "gate mutant G3-heal-allowed killed"; }
unset GATE_UNDER_TEST
for p in $PIDS; do kill "$p" 2>/dev/null; done
[ "$bad" = 0 ] && echo "META PASS — CM-CODEGRAPH-MCP-HEALTH classifies every fixture and kills every mutant" || { echo "META FAIL"; exit 1; }
