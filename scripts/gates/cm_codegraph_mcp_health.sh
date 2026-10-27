#!/usr/bin/env bash
# cm_codegraph_mcp_health.sh — CM-CODEGRAPH-MCP-HEALTH gate (§11.4.80(4), §11.4.201, §11.4.273; closes the class behind OWED-GATE-102's
# "no upgrade-compatibility-probe harness" blocker for the MCP surface).
#
# ── Purpose ─────────────────────────────────────────────────────────────
# Assert, from a REAL round trip and never from config-reading, that the project's declared `codegraph` MCP server answers
# initialize -> tools/list -> codegraph_status (and, when --probe-symbol is given, a known-symbol search with a fabricated-symbol
# negative control) RIGHT NOW. Delegates every measurement to scripts/codegraph/codegraph_mcp_health.py (H1..H9: declared server,
# version pin + duplicate installs, runner-patch applicability for the INSTALLED version, stale state files, WAL growth, watchdog /
# OOM evidence, user-scope stock servers, the round trip, index schema/state) and maps its verdict onto the gate exit codes.
# The incident this closes (2026-10-27, `/mcp` "Failed to reconnect to codegraph: -32000"): an upstream version bump changed the code
# shape the read-only runner patch anchors on, the sanctioned wrapper exited 5 with an EMPTY stdout, and nothing noticed.
# The gate is itself a guard (§11.4.201): a PASS requires BOTH tool exit 0 AND explicit `HEALTH H1 PASS` + `HEALTH H8 PASS` lines
# (a tool that exits 0 without having round-tripped is BLIND, not healthy); a live writer on the index is BUSY -> SKIP (a legitimate
# `sync` is never a false-positive FAIL, §11.4.201(1)); nothing declared and nothing indexed -> SKIP, never PASS.
#
# ── Usage ─────────────────────────────────────────────────────────────
#   cm_codegraph_mcp_health.sh [--project DIR] [--probe-symbol NAME] [--expect-version V | --pin FILE] [--mcp-json FILE]
#                              [--timeout-init S] [--timeout-list S] [--timeout-call S] [--wal-warn-mb N] [--wal-fail-gib N]
#   (default project: $PWD). `--no-roundtrip` and `--heal` are REFUSED here (exit 2): a gate must measure, never repair or skip.
#   CG_HEALTH_TOOL overrides the tool path (the paired mutation test points it at a mutated COPY).
#
# ── Side-effects ──────────────────────────────────────────────────────────
#   Spawns the project's declared codegraph MCP server for one read-only round trip (a sanctioned wrapper writes nothing).
#
# ── Dependencies ──────────────────────────────────────────────────────────
#   bash, python3, scripts/codegraph/codegraph_mcp_health.py (+ the sanctioned wrapper and fk_index_patch.py for H3).
#
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL · 2 BLIND (usage / cannot determine / tool exited 0 without round-trip evidence)
#   · 3 SKIP (nothing declared + nothing indexed, or a live writer made the round trip impossible — not a PASS).
#
# Classification: universal (§11.4.17). Paired mutation test: cm_codegraph_mcp_health_mutation_test.sh.
set -uo pipefail
GATE="CM-CODEGRAPH-MCP-HEALTH"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
tool="${CG_HEALTH_TOOL:-$here/../codegraph/codegraph_mcp_health.py}"
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-roundtrip|--heal) echo "$GATE: $1 is refused — a gate measures the real round trip and never repairs" >&2; exit 2 ;;
    --project|--probe-symbol|--expect-version|--pin|--mcp-json|--timeout-init|--timeout-list|--timeout-call|--wal-warn-mb|--wal-fail-gib)
      [ $# -ge 2 ] || { echo "$GATE: $1 needs a value" >&2; exit 2; }; args+=("$1" "$2"); shift 2 ;;
    -h|--help) sed -n 2,34p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -r "$tool" ] || { echo "$GATE: BLIND — health tool not readable: $tool" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "$GATE: BLIND — python3 not found" >&2; exit 2; }
out="$(python3 "$tool" "${args[@]}" 2>&1)"; rc=$?
printf '%s\n' "$out"
case "$rc" in
  0)
    # here-strings, not `printf | grep -q`: under pipefail a producer pipe into an early-exiting grep -q can SIGPIPE (CM-SIGPIPE-PIPEFAIL-CLASS)
    if grep -q '^HEALTH H1 PASS ' <<<"$out" && grep -q '^HEALTH H8 PASS ' <<<"$out"; then
      echo "✅ $GATE: PASS"; exit 0
    fi
    echo "⚠ $GATE: BLIND (exit 2) — the tool exited 0 without an explicit H1 PASS and H8 PASS (round-trip) line; a missing round trip is never healthy" >&2
    exit 2 ;;
  1) echo "❌ $GATE: FAIL"; exit 1 ;;
  3) echo "⚠ $GATE: SKIP (exit 3) — no codegraph MCP server declared and no index; nothing was inspected (not a PASS)"; exit 3 ;;
  4) echo "⚠ $GATE: SKIP (exit 3) — a live writer holds the index (BUSY); the round trip could not run (not a PASS, not a FAIL)"; exit 3 ;;
  *) echo "⚠ $GATE: BLIND (exit 2) — health tool exited $rc" >&2; exit 2 ;;
esac
