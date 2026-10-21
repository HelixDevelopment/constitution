#!/usr/bin/env bash
# cm_label_sync_mcp_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-LABEL-SYNC-MCP.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Builds a CLEAN disposable fixture root that MUST PASS (--structural-only), then
# applies independent mutations on fresh copies, each of which MUST make the gate
# FAIL:
#   (1) server.go missing   (2) server_test.go missing   (3) launcher not executable
#   (4) mcp config is not valid JSON   (5) mcp config command points at nothing
#   (6) autoApprove contains a MUTATING tool (label_switch_alias)
#   (7) server.go no longer implements label_switch_alias
#   (8) MCP.md no longer documents label_done   (9) protocol version not pinned
#  (10) -32601 no longer answered   (11) MCP.md missing
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_label_sync_mcp_mutation_test.sh
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Temp fixture under $TMPDIR, removed on EXIT. No network, no real-tree edit.
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3 + the sibling gate script.
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 gate FAILs on every mutation AND PASSes on the clean fixture | 1 an
#   expectation was violated | 2 gate script missing.
# Cross-refs: §1.1, §11.4.182, §11.4.201. Classification: universal (§11.4.17).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$SCRIPT_DIR/cm_label_sync_mcp.sh"
[ -f "$GATE" ] || { echo "META: gate missing: $GATE" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_label_sync_mcp_mut.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
rc=0
TOOLS="label_get label_list label_switch_alias label_register label_heartbeat label_done label_active"
build() { # $1 root
  local r="$1" s="$1/scripts/label-sync/mcp" d="$1/docs/label-sync" t
  mkdir -p "$s/label-mcp" "$d" "$r/mcp"
  { echo 'package main'; for t in $TOOLS; do echo "// \"$t\""; done; echo '// 2024-11-05 -32601 -32700'; } >"$s/label-mcp/server.go"
  echo 'package main' >"$s/label-mcp/main.go"; echo 'package main' >"$s/label-mcp/server_test.go"
  printf '#!/usr/bin/env bash\n# Purpose : x\n# Usage   : x\n# Exit    : x\n' >"$s/label-mcp.sh"; chmod +x "$s/label-mcp.sh"
  echo '#!/usr/bin/env bash' >"$s/prove_mcp_mutations.sh"
  { echo '# MCP'; for t in $TOOLS; do echo "| \`$t\` | x |"; done; echo '## Honest limits'; } >"$d/MCP.md"
  cat >"$r/mcp/label-sync-mcp.json" <<'J'
{"mcpServers":{"label-sync":{"command":"scripts/label-sync/mcp/label-mcp.sh","args":[],"autoApprove":["label_get","label_list","label_active"]}}}
J
}
expect() { # want(pass|fail) desc root
  if bash "$GATE" --root "$3" --structural-only --quiet >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$1" ]; then echo "✅ META OK:   $2 — gate ${got}ed as required"
  else echo "❌ META FAIL: $2 — gate ${got}ed, wanted $1"; rc=1; fi
}
S() { echo "$1/scripts/label-sync/mcp"; }
build "$TMP/clean"; expect pass "clean fixture" "$TMP/clean"
r="$TMP/m1"; build "$r"; rm "$(S "$r")/label-mcp/server.go"; expect fail "server.go missing" "$r"
r="$TMP/m2"; build "$r"; rm "$(S "$r")/label-mcp/server_test.go"; expect fail "server_test.go missing" "$r"
r="$TMP/m3"; build "$r"; chmod -x "$(S "$r")/label-mcp.sh"; expect fail "launcher not executable" "$r"
r="$TMP/m4"; build "$r"; echo '{ not json' >"$r/mcp/label-sync-mcp.json"; expect fail "mcp config invalid JSON" "$r"
r="$TMP/m5"; build "$r"; sed -i 's#scripts/label-sync/mcp/label-mcp.sh#scripts/nowhere.sh#' "$r/mcp/label-sync-mcp.json"; expect fail "mcp config command missing on disk" "$r"
r="$TMP/m6"; build "$r"; sed -i 's/"label_active"\]/"label_active","label_switch_alias"]/' "$r/mcp/label-sync-mcp.json"; expect fail "autoApprove holds a mutating tool" "$r"
r="$TMP/m7"; build "$r"; sed -i '/label_switch_alias/d' "$(S "$r")/label-mcp/server.go"; expect fail "server lacks label_switch_alias" "$r"
r="$TMP/m8"; build "$r"; sed -i '/`label_done`/d' "$r/docs/label-sync/MCP.md"; expect fail "MCP.md lacks label_done" "$r"
r="$TMP/m9"; build "$r"; sed -i 's/2024-11-05//' "$(S "$r")/label-mcp/server.go"; expect fail "protocol version not pinned" "$r"
r="$TMP/m10"; build "$r"; sed -i 's/-32601//' "$(S "$r")/label-mcp/server.go"; expect fail "-32601 not answered" "$r"
r="$TMP/m11"; build "$r"; rm "$r/docs/label-sync/MCP.md"; expect fail "MCP.md missing" "$r"
[ "$rc" -eq 0 ] && echo "✅ META: all expectations held" || echo "❌ META: violations above"
exit "$rc"
