#!/usr/bin/env bash
# ============================================================================
# test_codegraph_mcp_preflight.sh — tests for codegraph_mcp_preflight.sh
# ============================================================================
# Purpose      Prove the preflight PASSes a correct wiring and FAILs each wiring defect with the specific reason:
#                F1 correct .mcp.json => exit 0, P1/P2/P4/P5/P6 PASS   F2 stock `codegraph` command => P1 FAIL   F3 no codegraph server => P1 FAIL
#                F4 writer subcommand in args => P1 FAIL               F5 stock-codegraph settings hook => P3 FAIL (clean settings PASS)
#                F6 non-mcpro1 runner => P4 FAIL                       F7 live writer => exit 0 with P6 WARN (by design, not FAIL)
#                F8 fixture cannot be built => P5 FAIL                 F9 second server launching stock codegraph => P2 FAIL
#                F10 runner passes the receipt but the session fails => P4 PASS + P5 FAIL
#                F11 receipt-valid runner dir whose launcher execs the STOCK (writer) server => P4 PASS + P5 FAIL (fd modes read from /proc)
#                F12 wrapper copy that is not a genuine copy of the tooling => P1 FAIL
#                F13 user-scope configs (HOME / CLAUDE_CONFIG_DIR .claude.json) with a non-wrapper codegraph => P7 FAIL, secrets redacted
#                F14 other entries resolved by launch target (node .js / bash -c / npx / env / shim script) => P2 FAIL
# Usage        bash test_codegraph_mcp_preflight.sh ; ONLY=F2,F4 bash test_codegraph_mcp_preflight.sh
# Inputs       CG_DIR (code under test; mutation harness uses a COPY), STOCK_SRC, TMPDIR     Outputs RESULT lines + SUMMARY; exit 1 on failure
# Side effects fixtures + runner cache + helper processes under $TMPDIR/cg_safe_tests (killed on exit)
# Cross-refs   ../codegraph_mcp_preflight.sh, test_mcp_readonly.sh (mkfx reused), constitution §11.4.201/.273/.224
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="${CG_DIR:-$(cd "$HERE/.." && pwd)}"
. "$HERE/lib_test.sh"
export CODEGRAPH_NO_UPDATE_CHECK=1 DO_NOT_TRACK=1 CODEGRAPH_TELEMETRY=0
unset CODEGRAPH_NO_DAEMON CODEGRAPH_NO_WATCH CODEGRAPH_MCP_TOOLS CODEGRAPH_QUERY_POOL_SIZE CODEGRAPH_MCP_READONLY CODEGRAPH_MCP_PROJECT HELIX_CODEGRAPH_MCP_RUNNER HELIX_CODEGRAPH_FIXTURE_BIN
PF="$CG_DIR/codegraph_mcp_preflight.sh"; WRAP="$CG_DIR/codegraph_mcp.sh"
W="$(t_workdir cgpf)"; echo "workdir $W"
STOCK_SRC="${STOCK_SRC:-$(cd "$CG_DIR" && python3 -c 'import fk_index_patch as m; print(m.default_src())' 2>/dev/null)}"
[ -d "$STOCK_SRC/lib/dist" ] || { echo "BLIND: cannot resolve stock package source (STOCK_SRC=$STOCK_SRC)"; exit 2; }
STOCK_BIN="$STOCK_SRC/bin/codegraph"; STOCK_RUNNER="$STOCK_BIN"
eval "$(sed -n '/^mkfx() {/,/^}/p' "$HERE/test_mcp_readonly.sh")"
export HELIX_CODEGRAPH_RUNNER_DIR="$W/runners" HELIX_CODEGRAPH_SRC="$STOCK_SRC"
HELPERS=""; trap 'for p in $HELPERS; do kill "$p" 2>/dev/null; done' EXIT

mkproj() {   # mkproj <dir> <mcp.json-body> — fixture project + .mcp.json
    mkfx "$1"; printf '%s\n' "$2" > "$1/.mcp.json"
}
GOODJSON() { printf '{"mcpServers":{"codegraph":{"command":"%s","args":["serve","--mcp","--project","%s"]}}}' "$WRAP" "$1"; }
# Every preflight run sees FIXTURE user-scope configs only (UHOME/UCFG), never the operator's real ~/.claude.json (B1: P7 reads it).
UHOME="$W/uhome_clean"; UCFG="$W/ucfg_clean"; mkdir -p "$UHOME" "$UCFG"
run_pf() { OUT="$(HOME="$UHOME" CLAUDE_CONFIG_DIR="$UCFG" "$PF" --project "$1" "${@:2}" 2>&1)"; RC=$?; }
has() { printf '%s\n' "$OUT" | grep -qE "^PREFLIGHT $1 $2"; }
hasmsg() { printf '%s\n' "$OUT" | grep -E "^PREFLIGHT $1 $2" | grep -qF -- "$3"; }

if t_want F1; then
    P="$W/f1/p"; mkproj "$P" "$(GOODJSON "$P")"; run_pf "$P"
    [ "$RC" -eq 0 ] && has P1 PASS && has P2 PASS && has P4 PASS && has P5 PASS && has P6 PASS
    t_check F1 "correct wiring => exit 0 with P1,P2,P4,P5,P6 PASS" $? "rc=$RC out=$(printf '%s' "$OUT" | cut -c1-90 | tr '\n' '|' | cut -c1-400)"
fi
if t_want F2; then
    P="$W/f2/p"; mkproj "$P" '{"mcpServers":{"codegraph":{"command":"codegraph","args":["serve","--mcp"]}}}'; run_pf "$P"
    [ "$RC" -eq 1 ] && hasmsg P1 FAIL 'not codegraph_mcp.sh'
    t_check F2 "stock codegraph command is refused (P1 FAIL names codegraph_mcp.sh)" $? "rc=$RC p1=$(printf '%s' "$OUT" | grep '^PREFLIGHT P1' | cut -c1-160)"
fi
if t_want F3; then
    P="$W/f3/p"; mkproj "$P" '{"mcpServers":{}}'; run_pf "$P"
    [ "$RC" -eq 1 ] && hasmsg P1 FAIL 'not declared'
    t_check F3 "no codegraph server declared (the measured gap) => P1 FAIL 'not declared'" $? "rc=$RC p1=$(printf '%s' "$OUT" | grep '^PREFLIGHT P1' | cut -c1-160)"
fi
if t_want F4; then
    P="$W/f4/p"; mkproj "$P" "$(printf '{"mcpServers":{"codegraph":{"command":"%s","args":["serve","--mcp","index"]}}}' "$WRAP")"; run_pf "$P"
    [ "$RC" -eq 1 ] && hasmsg P1 FAIL "argument 'index'"
    t_check F4 "writer subcommand in args => P1 FAIL" $? "rc=$RC p1=$(printf '%s' "$OUT" | grep '^PREFLIGHT P1' | cut -c1-160)"
fi
if t_want F5; then
    P="$W/f5/p"; mkproj "$P" "$(GOODJSON "$P")"
    printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"codegraph prompt-hook"}]}]}}' > "$W/f5/bad_settings.json"
    printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}' > "$W/f5/ok_settings.json"
    run_pf "$P" --settings "$W/f5/bad_settings.json"; B_RC=$RC; hasmsg P3 FAIL 'stock codegraph'; B3=$?
    run_pf "$P" --settings "$W/f5/ok_settings.json"; has P3 PASS; G3=$?
    [ "$B_RC" -eq 1 ] && [ "$B3" -eq 0 ] && [ "$G3" -eq 0 ]
    t_check F5 "stock-codegraph settings hook => P3 FAIL; clean settings => P3 PASS" $? "bad_rc=$B_RC bad_p3=$B3 good_p3=$G3"
fi
if t_want F6; then
    P="$W/f6/p"; mkproj "$P" "$(GOODJSON "$P")"
    python3 "$CG_DIR/fk_index_patch.py" --patches resolve1 --src "$STOCK_SRC" --dst "$W/f6/writer" >/dev/null 2>&1
    HELIX_CODEGRAPH_MCP_RUNNER="$W/f6/writer/bin/codegraph" run_pf "$P"
    [ "$RC" -eq 1 ] && has P4 FAIL
    t_check F6 "a non-mcpro1 (writer) runner => P4 FAIL" $? "rc=$RC p4=$(printf '%s' "$OUT" | grep '^PREFLIGHT P4' | cut -c1-160)"
fi
if t_want F7; then
    P="$W/f7/p"; mkproj "$P" "$(GOODJSON "$P")"
    python3 -c 'import sqlite3,sys,time; c=sqlite3.connect(sys.argv[1]); c.execute("BEGIN IMMEDIATE"); time.sleep(120)' "$P/.codegraph/codegraph.db" & HP=$!; HELPERS="$HELPERS $HP"; sleep 1
    run_pf "$P"; kill "$HP" 2>/dev/null; wait "$HP" 2>/dev/null
    [ "$RC" -eq 0 ] && has P6 WARN && hasmsg P6 WARN 'live writer'
    t_check F7 "live writer on the project index => exit 0 with P6 WARN (by design), never FAIL" $? "rc=$RC p6=$(printf '%s' "$OUT" | grep '^PREFLIGHT P6' | cut -c1-140)"
fi
if t_want F8; then
    P="$W/f8/p"; mkproj "$P" "$(GOODJSON "$P")"
    HELIX_CODEGRAPH_FIXTURE_BIN=/bin/false run_pf "$P"
    [ "$RC" -eq 1 ] && has P5 FAIL && hasmsg P5 FAIL 'fixture could not be created'
    t_check F8 "fixture cannot be built => P5 FAIL (a query is never claimed answered)" $? "rc=$RC p5=$(printf '%s' "$OUT" | grep '^PREFLIGHT P5' | cut -c1-140)"
fi
if t_want F9; then
    P="$W/f9/p"; mkproj "$P" "$(printf '{"mcpServers":{"codegraph":{"command":"%s","args":["serve","--mcp"]},"cg2":{"command":"codegraph","args":["serve","--mcp"]}}}' "$WRAP")"; run_pf "$P"
    [ "$RC" -eq 1 ] && has P1 PASS && hasmsg P2 FAIL 'cg2'
    t_check F9 "a second server entry launching the stock codegraph => P2 FAIL naming it" $? "rc=$RC p2=$(printf '%s' "$OUT" | grep '^PREFLIGHT P2' | cut -c1-140)"
fi
if t_want F10; then
    P="$W/f10/p"; mkproj "$P" "$(GOODJSON "$P")"
    python3 "$CG_DIR/fk_index_patch.py" --patches mcpro1 --src "$STOCK_SRC" --print-bin >"$W/f10.bin" 2>/dev/null; GOODBIN="$(cat "$W/f10.bin")"
    cp -a "$(dirname "$GOODBIN")/.." "$W/f10/brokenrunner"; printf '#!/bin/sh\nexit 1\n' > "$W/f10/brokenrunner/bin/codegraph"
    HELIX_CODEGRAPH_MCP_RUNNER="$W/f10/brokenrunner/bin/codegraph" run_pf "$P"
    [ "$RC" -eq 1 ] && has P4 PASS && has P5 FAIL
    t_check F10 "runner passes the receipt but its session fails => P4 PASS + P5 FAIL (receipt is not proof of working)" $? "rc=$RC out=$(printf '%s' "$OUT" | grep -E '^PREFLIGHT P[45]' | cut -c1-70 | tr '\n' '|')"
fi
if t_want F11; then
    P="$W/f11/p"; mkproj "$P" "$(GOODJSON "$P")"
    python3 "$CG_DIR/fk_index_patch.py" --patches mcpro1 --src "$STOCK_SRC" --print-bin >"$W/f11.bin" 2>/dev/null; GOODBIN="$(cat "$W/f11.bin")"
    cp -a "$(dirname "$GOODBIN")/.." "$W/f11/wolfrunner"; printf '#!/bin/sh\nexec "%s" "$@"\n' "$STOCK_SRC/bin/codegraph" > "$W/f11/wolfrunner/bin/codegraph"
    HELIX_CODEGRAPH_MCP_RUNNER="$W/f11/wolfrunner/bin/codegraph" run_pf "$P"
    [ "$RC" -eq 1 ] && has P4 PASS && hasmsg P5 FAIL 'read-only'
    t_check F11 "receipt-valid runner dir launching the STOCK writer server => P4 PASS but P5 FAIL on the fd modes (the check that catches a wolf in receipt clothing)" $? "rc=$RC out=$(printf '%s' "$OUT" | grep -E '^PREFLIGHT P[45]' | cut -c1-110 | tr '\n' '|')"
fi
if t_want F12; then
    # I5/Z5: a codegraph_mcp.sh that is NOT a genuine copy of the tooling (no fk_index_patch.py beside it) must be refused.
    P="$W/f12/p"; mkdir -p "$W/f12/fake"; cp -a "$WRAP" "$W/f12/fake/codegraph_mcp.sh"
    [ -f "$W/f12/fake/fk_index_patch.py" ] && { t_check F12 "fixture sanity" 1 "fk_index_patch.py unexpectedly beside the fake"; }
    mkproj "$P" "$(printf '{"mcpServers":{"codegraph":{"command":"%s","args":["serve","--mcp"]}}}' "$W/f12/fake/codegraph_mcp.sh")"; run_pf "$P"
    [ "$RC" -eq 1 ] && hasmsg P1 FAIL 'not a genuine copy'
    t_check F12 "codegraph_mcp.sh copy without the tooling beside it => P1 FAIL 'not a genuine copy'" $? "rc=$RC p1=$(printf '%s' "$OUT" | grep '^PREFLIGHT P1' | cut -c1-160)"
fi
if t_want F13; then
    # B1: user-scope configs (~/.claude.json and $CLAUDE_CONFIG_DIR/.claude.json; keys mcpServers + projects.*.mcpServers) are read
    # automatically; a non-wrapper codegraph server there => P7 FAIL. Secrets in env/headers/args never reach the output.
    P="$W/f13/p"; mkproj "$P" "$(GOODJSON "$P")"
    H1="$W/f13/h1"; C1="$W/f13/c1"; H2="$W/f13/h2"; C2="$W/f13/c2"; H3="$W/f13/h3"; C3="$W/f13/c3"; H4="$W/f13/h4"; C4="$W/f13/c4"; mkdir -p "$H1" "$C1" "$H2" "$C2" "$H3" "$C3" "$H4" "$C4"
    printf '{"mcpServers":{"codegraph":{"type":"stdio","command":"codegraph","args":["serve","--mcp","--api-key","SECRETNEEDLE_ARG_789"],"env":{"CG_TOKEN":"SECRETNEEDLE_ENV_123"},"headers":{"Authorization":"Bearer SECRETNEEDLE_HDR_456"}}}}' > "$H1/.claude.json"
    printf '{"projects":{"/some/where":{"mcpServers":{"cgx":{"command":"node","args":["%s/lib/dist/bin/codegraph.js","serve","--mcp"]}}}}}' "$STOCK_SRC" > "$C2/.claude.json"
    printf '{"mcpServers":{"codegraph":{"command":"%s","args":["serve","--mcp"]},"other":{"command":"echo","args":["hi"]}}}' "$WRAP" > "$H3/.claude.json"
    printf '{"mcpServers": {' > "$C4/.claude.json"
    grep -qF SECRETNEEDLE_ENV_123 "$H1/.claude.json"; NEEDLE_PRESENT=$?     # control needle: the fixture really carries the secret
    OUT_A="$(HOME="$H1" CLAUDE_CONFIG_DIR="$C1" "$PF" --project "$P" 2>&1)"; A_RC=$?
    OUT="$OUT_A"; hasmsg P7 FAIL "'codegraph'"; A7=$?; printf '%s' "$OUT_A" | grep -q SECRETNEEDLE; A_LEAK=$?
    OUT="$(HOME="$H2" CLAUDE_CONFIG_DIR="$C2" "$PF" --project "$P" 2>&1)"; B_RC=$?; hasmsg P7 FAIL 'projects'; B7=$?
    OUT="$(HOME="$H3" CLAUDE_CONFIG_DIR="$C3" "$PF" --project "$P" 2>&1)"; G_RC=$?; has P7 PASS; G7=$?
    OUT="$(HOME="$H4" CLAUDE_CONFIG_DIR="$C4" "$PF" --project "$P" 2>&1)"; E_RC=$?; hasmsg P7 FAIL 'not valid JSON'; E7=$?
    [ "$NEEDLE_PRESENT" -eq 0 ] && [ "$A_RC" -eq 1 ] && [ "$A7" -eq 0 ] && [ "$A_LEAK" -ne 0 ] && [ "$B_RC" -eq 1 ] && [ "$B7" -eq 0 ] \
        && [ "$G_RC" -eq 0 ] && [ "$G7" -eq 0 ] && [ "$E_RC" -eq 1 ] && [ "$E7" -eq 0 ]
    t_check F13 "user-scope stock codegraph (~/.claude.json mcpServers / \$CLAUDE_CONFIG_DIR projects.*) => P7 FAIL, secrets redacted; wrapper-only => P7 PASS; invalid JSON => P7 FAIL" $? \
        "needle=$NEEDLE_PRESENT a=$A_RC/$A7/leak$A_LEAK b=$B_RC/$B7 g=$G_RC/$G7 e=$E_RC/$E7 p7a=$(printf '%s' "$OUT_A" | grep '^PREFLIGHT P7' | cut -c1-120)"
fi
if t_want F14; then
    # I4: P2 classifies other entries by the RESOLVED launch target, not the command basename.
    P="$W/f14/p"; mkdir -p "$W/f14"
    printf '#!/bin/sh\nexec codegraph serve --mcp "$@"\n' > "$W/f14/mycg"; chmod +x "$W/f14/mycg"
    RES=""
    for body in \
        "{\"command\":\"node\",\"args\":[\"$STOCK_SRC/lib/dist/bin/codegraph.js\",\"serve\",\"--mcp\"]}" \
        '{"command":"bash","args":["-c","codegraph serve --mcp"]}' \
        '{"command":"npx","args":["-y","@colbymchenry/codegraph","serve","--mcp"]}' \
        '{"command":"env","args":["X=1","codegraph","serve","--mcp"]}' \
        "{\"command\":\"$W/f14/mycg\",\"args\":[]}"; do
        rm -rf "$P"; mkproj "$P" "$(printf '{"mcpServers":{"codegraph":{"command":"%s","args":["serve","--mcp"]},"sneaky":%s}}' "$WRAP" "$body")"; run_pf "$P"
        if [ "$RC" -eq 1 ] && hasmsg P2 FAIL 'sneaky'; then RES="${RES}F"; else RES="${RES}p"; fi
    done
    rm -rf "$P"; mkproj "$P" "$(printf '{"mcpServers":{"codegraph":{"command":"%s","args":["serve","--mcp"]},"plain":{"command":"node","args":["/opt/other/server.js"]}}}' "$WRAP")"; run_pf "$P"
    has P2 PASS; CTRL=$?
    [ "$RES" = "FFFFF" ] && [ "$CTRL" -eq 0 ]
    t_check F14 "node dist/bin/codegraph.js | bash -c | npx @colbymchenry/codegraph | env | shim script => P2 FAIL each; unrelated node server => P2 PASS" $? "res=$RES ctrl=$CTRL"
fi
t_finish
