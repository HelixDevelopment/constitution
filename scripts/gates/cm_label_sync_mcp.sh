#!/usr/bin/env bash
# cm_label_sync_mcp.sh — CM-LABEL-SYNC-MCP gate for the §11.4.182 label-sync MCP
# server (scripts/label-sync/mcp/label-mcp/).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Asserts the MCP server is present, documented and genuinely speaks the protocol:
#   (1) STRUCTURAL (always; fixture-mutation-tested):
#       (a) server.go, main.go, server_test.go present under mcp/label-mcp/
#       (b) launcher scripts/label-sync/mcp/label-mcp.sh executable + §11.4.18 header
#       (c) mcp/label-sync-mcp.json is valid JSON, declares mcpServers.label-sync with a
#           `command` that exists, and its autoApprove list contains NO mutating tool
#           (label_switch_alias / label_register / label_heartbeat / label_done)
#       (d) server.go implements all 7 tools and docs/label-sync/MCP.md names each
#       (e) server.go pins protocol 2024-11-05 and answers -32601/-32700
#       (f) prove_mcp_mutations.sh present
#   (2) RUNTIME (skipped with --structural-only; honest SKIP when go/jq absent):
#       (g) `go test -race ./mcp/...` exits 0
#       (h) stdio smoke through the launcher against a TEMP state dir:
#           initialize -> protocolVersion 2024-11-05; tools/list -> 7 tools; unknown
#           method -> -32601; malformed line -> -32700; label_register +
#           label_switch_alias + label_get -> the follower's label shows the NEW
#           alias; stdin EOF -> exit 0
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_label_sync_mcp.sh [--root <constitution-root>] [--structural-only] [--quiet]
# ── Inputs ───────────────────────────────────────────────────────────────────
#   CONSTITUTION_ROOT env override for --root (arg wins).
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check PASS/FAIL/SKIP lines and a summary.
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Runtime checks use a temp state dir and a temp binary dir (removed on exit).
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep; jq + go for the runtime checks.
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.182, §11.4.228(D)(3), §11.4.18, §1.1 (paired mutation), §11.4.201, §11.4.3.
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 all checks PASS (runtime may SKIP) | 1 a check FAILed | 2 environment error.
# Classification: universal (§11.4.17).
set -uo pipefail

GATE="CM-LABEL-SYNC-MCP"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
root="${CONSTITUTION_ROOT:-${SCRIPT_DIR}/../..}"
quiet=""; structural=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --quiet) quiet=1; shift ;;
    --structural-only) structural=1; shift ;;
    -h|--help) sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$root" ] || { echo "${GATE}: root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"
ls_dir="$root/scripts/label-sync"
srv="$ls_dir/mcp/label-mcp"
cfg="$root/mcp/label-sync-mcp.json"
doc="$root/docs/label-sync/MCP.md"
fail=0
say()  { [ -n "$quiet" ] || echo "$@"; }
warn() { echo "$@"; }
need() { local d="$1"; shift; if "$@"; then say "✅ PASS     $d"; else warn "❌ FAIL     $d"; fail=1; fi; }

for f in server.go main.go server_test.go; do need "mcp/label-mcp/$f present" test -s "$srv/$f"; done
need "launcher label-mcp.sh executable" test -x "$ls_dir/mcp/label-mcp.sh"
need "launcher §11.4.18 header (Purpose/Usage/Exit)" bash -c "[ -f '$ls_dir/mcp/label-mcp.sh' ] && grep -q '^# Purpose' '$ls_dir/mcp/label-mcp.sh' && grep -q '^# Usage' '$ls_dir/mcp/label-mcp.sh' && grep -q '^# Exit' '$ls_dir/mcp/label-mcp.sh'"
need "mcp/label-sync-mcp.json is valid JSON" bash -c "python3 -c 'import json,sys;json.load(open(sys.argv[1]))' '$cfg' 2>/dev/null"
need "mcp config declares mcpServers.label-sync with an existing command" bash -c "
  c=\$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[\"mcpServers\"][\"label-sync\"][\"command\"])' '$cfg' 2>/dev/null) && [ -n \"\$c\" ] && [ -f '$root'/\"\$c\" ]"
need "mcp autoApprove holds NO mutating tool" bash -c "
  ! python3 -c 'import json,sys;print(\" \".join(json.load(open(sys.argv[1]))[\"mcpServers\"][\"label-sync\"].get(\"autoApprove\",[])))' '$cfg' 2>/dev/null | grep -qE 'label_(switch_alias|register|heartbeat|done)'"
for t in label_get label_list label_switch_alias label_register label_heartbeat label_done label_active; do
  need "server.go implements $t" grep -q "\"$t\"" "$srv/server.go"
  need "MCP.md documents $t" grep -qF "\`$t\`" "$doc"
done
need "server.go pins protocol 2024-11-05" grep -q '2024-11-05' "$srv/server.go"
need "server.go answers -32601 and -32700" bash -c "grep -q -- '-32601' '$srv/server.go' && grep -q -- '-32700' '$srv/server.go'"
need "prove_mcp_mutations.sh present" test -f "$ls_dir/mcp/prove_mcp_mutations.sh"
need "MCP.md present and states honest limits" bash -c "[ -f '$doc' ] && grep -q 'Honest limits' '$doc'"

if [ -n "$structural" ]; then
  warn "⚠️  SKIP     runtime checks (--structural-only — honest skip, §11.4.3)"
elif ! command -v go >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  warn "⚠️  SKIP     runtime checks (go/jq absent — honest skip, §11.4.3)"
else
  TMPD="$(mktemp -d "${TMPDIR:-/tmp}/cm_label_sync_mcp.XXXXXX")"
  trap 'rm -rf "$TMPD"' EXIT
  if ( cd "$ls_dir" && GOPROXY=off GOFLAGS=-buildvcs=false nice -n 10 go test -race -p 2 -count=1 ./mcp/... ) >"$TMPD/gotest.log" 2>&1; then
    say "✅ PASS     go test -race ./mcp/... (race-clean)"
  else
    warn "❌ FAIL     go test -race ./mcp/... — tail:"; tail -15 "$TMPD/gotest.log"; fail=1
  fi
  export LABEL_SYNC_DIR="$TMPD/state" LABEL_SYNC_BIN="$TMPD/bin"
  L="$ls_dir/mcp/label-mcp.sh"
  reqs='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"nope/nothing"}
this is not json
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"label_register","arguments":{"id":"gate-f","kind":"agent","track":"1","branch":"gate","follow_active":true}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"label_switch_alias","arguments":{"alias":"claude2","model":"sonnet","effort":"xhigh"}}}
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"label_get","arguments":{"id":"gate-f"}}}'
  out="$(printf '%s\n' "$reqs" | bash "$L" 2>"$TMPD/stderr.log")"; rc=$?
  chk() { printf '%s\n' "$out" | jq -e "$1" >/dev/null 2>&1; }
  if [ "$rc" = 0 ] \
     && chk 'select(.id==1) | .result.protocolVersion=="2024-11-05"' \
     && chk 'select(.id==2) | (.result.tools|length)==7' \
     && chk 'select(.id==3) | .error.code==-32601' \
     && chk 'select(.id==null) | .error.code==-32700' \
     && chk 'select(.id==6) | .result.content[0].text | fromjson | .label=="(T1/gate - claude2 - sonnet - xhigh)"'; then
    say "✅ PASS     stdio smoke: handshake, 7 tools, -32601, -32700, switch relabelled follower, EOF exit 0"
  else
    warn "❌ FAIL     stdio smoke (rc=$rc); stderr tail: $(tail -3 "$TMPD/stderr.log" | tr '\n' ' ')"; printf '%s\n' "$out" | head -8; fail=1
  fi
fi

echo "----------------------------------------------------------------------"
if [ "$fail" -ne 0 ]; then echo "❌ ${GATE}: FAIL"; exit 1; fi
echo "✅ ${GATE}: PASS — label-sync MCP server present, documented and speaking the protocol"
exit 0
