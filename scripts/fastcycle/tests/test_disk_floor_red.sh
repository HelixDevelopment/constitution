#!/bin/bash
# T145 RED test (SpecKit-004 "fast-dev-cycles", User Story 6, plan task T-F05,
# contract host-resource-attribution.md, memory card 2026-09-24b) for
# `host/host_report.py floor`.
#
# Per tasks.md T145's own line: "golden: a simulated free-space drop below
# the largest floor raises the alert before a planned heavy task; negative
# control: ample space raises none."
#
# `floor` reads real free space via `df` by default; FC_FLOOR_FREE_KB
# (analogous to host_guard.sh's own FC_GUARD_* injectable-override
# convention) lets this test pin a deterministic, simulated free-space
# value without depending on the real, fluctuating host disk state.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC_ROOT=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$FC_ROOT/../../.." && pwd)
TOOL="$FC_ROOT/host/host_report.py"
FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

if [ ! -f "$TOOL" ]; then
  echo "RED: host_report.py absent at $TOOL"
  bad "host_report.py exists"
  echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

CFG="$WORK/fastcycle.yaml"
cat > "$CFG" <<'YAML'
schema: fastcycle-config/v1
paths:
  evidence_root: qa-results/fastcycle
host:
  attribution_roots: []
  worktree_prefix: ".claude/worktrees-does-not-exist-t145"
  session_scratch_roots: []
  hardlink_mirror_roots: []
  agent_registry_status: "docs/requests/agent_registry.status.tsv"
  disk_floor:
    volume_path: "."
    floors_gib:
      codegraph_launcher_floor: 20
      build_output_estimate: 30
    codegraph_safe_script: "constitution/scripts/codegraph/codegraph_safe.sh"
  needle_scratch_dir: "qa-results/fastcycle/_host_needle_t145"
YAML

cd "$REPO_ROOT" || exit 1

# --- golden: simulated free-space drop below the largest floor (30 GiB) raises the alert ---
OUT_BAD="$WORK/floor_bad.json"
FC_FLOOR_FREE_KB=$((10 * 1024 * 1024)) python3 "$TOOL" floor --config "$CFG" --out "$OUT_BAD" \
  >"$WORK/obad.log" 2>"$WORK/ebad.log"
rc=$?
if [ "$rc" -eq 1 ] && [ -f "$OUT_BAD" ]; then
  ok "golden: 10 GiB free (< 30 GiB largest floor) -> exit 1 (alert)"
else
  bad "golden: expected exit 1 + output for a below-floor simulation, got rc=$rc stderr=$(cat "$WORK/ebad.log")"
fi
if [ -f "$OUT_BAD" ]; then
  python3 -c "
import json, sys
doc = json.load(open('$OUT_BAD', encoding='utf-8'))
ok = doc.get('alert') is True and isinstance(doc.get('largest_floor_gib'), (int, float)) and doc.get('largest_floor_gib') == 30
sys.exit(0 if ok else 1)
" && ok "floor doc: alert: true, largest_floor_gib: 30" || bad "floor doc (below-floor case) shape/values wrong"
fi

# --- negative control: ample free space raises no alert ---
OUT_OK="$WORK/floor_ok.json"
FC_FLOOR_FREE_KB=$((500 * 1024 * 1024)) python3 "$TOOL" floor --config "$CFG" --out "$OUT_OK" \
  >"$WORK/ook.log" 2>"$WORK/eok.log"
rc2=$?
if [ "$rc2" -eq 0 ] && [ -f "$OUT_OK" ]; then
  ok "negative control: 500 GiB free (ample) -> exit 0 (no alert)"
else
  bad "negative control: expected exit 0 for ample free space, got rc=$rc2 stderr=$(cat "$WORK/eok.log")"
fi
if [ -f "$OUT_OK" ]; then
  python3 -c "
import json, sys
doc = json.load(open('$OUT_OK', encoding='utf-8'))
sys.exit(0 if doc.get('alert') is False else 1)
" && ok "floor doc (ample case): alert: false" || bad "floor doc (ample case): alert must be false"
fi

# --- WAL-checkpoint policy proposal is present, operator-confirmed only (never auto-applied) ---
if [ -f "$OUT_OK" ]; then
  python3 -c "
import json, sys
doc = json.load(open('$OUT_OK', encoding='utf-8'))
p = doc.get('wal_checkpoint_proposal')
ok = isinstance(p, dict) and p.get('operator_confirmed') is False and 'codegraph_safe.sh' in str(p.get('mechanism', ''))
sys.exit(0 if ok else 1)
" && ok "floor doc: wal_checkpoint_proposal present, operator_confirmed: false, reuses codegraph_safe.sh" \
  || bad "floor doc: wal_checkpoint_proposal missing/malformed"
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
