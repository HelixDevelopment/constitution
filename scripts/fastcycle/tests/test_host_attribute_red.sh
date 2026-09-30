#!/bin/bash
# T142 RED test (SpecKit-004 "fast-dev-cycles", User Story 6, plan task T-F02,
# contract host-resource-attribution.md HR-001/HR-002) for
# `host/host_report.py attribute`'s full per-consumer report shape.
#
# Three assertions, per tasks.md T142's own line:
#   (1) golden-bad: a hand-entered figure is rejected by the schema -- a
#       measured numeric value with no evidence object (or a malformed one)
#       is refused by the tool's own `validate_attribution_doc()` validator
#       (imported directly, a real structural check per C-004: "Every
#       numeric or classifying value cites an EvidencePath ... or is
#       UNMEASURED with missing_instrument").
#   (2) empty consumer -> reported zero with its path (never UNMEASURED,
#       never silently omitted -- a root that genuinely holds nothing is a
#       real zero, HR-001).
#   (3) negative control: a measured (non-empty) consumer passes the same
#       validator cleanly.
#
# Producer != Verifier (§11.4.240): validate_attribution_doc() is exercised
# here via direct import (a pure function on an in-memory dict this test
# constructs itself) -- this test never depends on host_report.py's own
# `attribute` measurement pipeline to build the golden-bad/negative-control
# fixtures, only assertion (2) below drives a real `attribute` invocation.

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

# --- (1) + (3): validate_attribution_doc() golden-bad + negative-control ---
python3 - "$FC_ROOT/host" <<'PYEOF'
import sys, importlib.util
host_dir = sys.argv[1]
spec = importlib.util.spec_from_file_location("host_report", host_dir + "/host_report.py")
if spec is None or spec.loader is None:
    print("FAIL: cannot import host_report.py")
    print("SUMMARY pass=0 fail=1")
    sys.exit(1)
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception as exc:
    print("FAIL: host_report.py raised on import: %s: %s" % (type(exc).__name__, exc))
    print("SUMMARY pass=0 fail=1")
    sys.exit(1)

if not hasattr(mod, "validate_attribution_doc"):
    print("FAIL: host_report.validate_attribution_doc is not defined")
    print("SUMMARY pass=0 fail=1")
    sys.exit(1)

fail = 0
def bad(m):
    global fail
    print("FAIL:", m); fail = 1
def ok(m):
    print("PASS:", m)

# golden-bad: a hand-entered figure -- a numeric value with NO evidence object.
hand_entered = {
    "schema": "host-attribute/v1",
    "needle": {
        "unshared_file": {"expected_bytes": 100, "total_bytes": 100, "exclusive_bytes": 100,
                           "evidence": {"cmd": ["btrfs"], "output_path": "x", "sha256": "a" * 64}},
        "reflinked_copy": {"expected_bytes": 100, "total_bytes": 100, "exclusive_bytes": 0,
                            "evidence": {"cmd": ["btrfs"], "output_path": "y", "sha256": "b" * 64}},
    },
    "consumers": [
        {"path": "some/path", "consumer_type": "cache",
         "apparent_bytes": {"value": 12345},  # <-- hand-entered: no "evidence" key at all
         "exclusive_bytes": {"value": "UNMEASURED", "missing_instrument": "btrfs_unavailable"},
         "time_attributed_ms": {"value": "UNMEASURED", "missing_instrument": "no_timing_rows_for_consumer"}},
    ],
}
res = mod.validate_attribution_doc(hand_entered)
valid = res[0] if isinstance(res, tuple) else res
if valid:
    bad("validate_attribution_doc() ACCEPTED a numeric value with no evidence object "
        "(hand-entered figure) -- the schema must reject this")
else:
    ok("validate_attribution_doc() rejects a hand-entered (evidence-less) numeric figure")

# negative control: the SAME shape but with a real evidence object -- must pass.
measured = {
    "schema": "host-attribute/v1",
    "needle": hand_entered["needle"],
    "consumers": [
        {"path": "some/path", "consumer_type": "cache",
         "apparent_bytes": {"value": 12345,
                             "evidence": {"cmd": ["du", "--apparent-size", "-sb", "some/path"],
                                          "output_path": "qa-results/fastcycle/x/du.log",
                                          "sha256": "c" * 64}},
         "exclusive_bytes": {"value": "UNMEASURED", "missing_instrument": "btrfs_unavailable"},
         "time_attributed_ms": {"value": "UNMEASURED", "missing_instrument": "no_timing_rows_for_consumer"}},
    ],
}
res2 = mod.validate_attribution_doc(measured)
valid2 = res2[0] if isinstance(res2, tuple) else res2
if valid2:
    ok("validate_attribution_doc() accepts a genuinely measured value with a real evidence object "
       "(negative control)")
else:
    bad("validate_attribution_doc() REJECTED a well-formed, evidence-backed measured doc "
        "(false positive) -- got: %r" % (res2,))

# UNMEASURED without missing_instrument must also be rejected (never coerced silently).
bad_unmeasured = {
    "schema": "host-attribute/v1",
    "needle": hand_entered["needle"],
    "consumers": [
        {"path": "p", "consumer_type": "cache",
         "apparent_bytes": {"value": "UNMEASURED"},  # no missing_instrument
         "exclusive_bytes": {"value": "UNMEASURED", "missing_instrument": "x"},
         "time_attributed_ms": {"value": "UNMEASURED", "missing_instrument": "x"}},
    ],
}
res3 = mod.validate_attribution_doc(bad_unmeasured)
valid3 = res3[0] if isinstance(res3, tuple) else res3
if valid3:
    bad("validate_attribution_doc() accepted UNMEASURED with no missing_instrument reason")
else:
    ok("validate_attribution_doc() rejects UNMEASURED with no missing_instrument reason")

print("SUMMARY pass=%d fail=%d" % (0 if fail else 1, fail))
sys.exit(1 if fail else 0)
PYEOF
py1_rc=$?
if [ "$py1_rc" -eq 0 ]; then ok "validate_attribution_doc golden-bad/negative-control/UNMEASURED-reason checks"; else bad "validate_attribution_doc checks"; fi

# --- (2): empty consumer -> reported zero with its path, via a real run ---
CFG="$WORK/fastcycle.yaml"
EMPTY_ROOT_REL="qa-results/fastcycle/_t142_empty_root.$$"
mkdir -p "$REPO_ROOT/$EMPTY_ROOT_REL"
NEEDLE_DIR_REL="qa-results/fastcycle/_t142_needle.$$"
cat > "$CFG" <<YAML
schema: fastcycle-config/v1
paths:
  evidence_root: qa-results/fastcycle
host:
  attribution_roots:
    - {path: "$EMPTY_ROOT_REL", consumer_type: cache}
  worktree_prefix: ".claude/worktrees-does-not-exist-t142"
  session_scratch_roots: []
  hardlink_mirror_roots: []
  agent_registry_status: "docs/requests/agent_registry.status.tsv"
  disk_floor:
    volume_path: "."
    floors_gib: {codegraph_launcher_floor: 20}
    codegraph_safe_script: "constitution/scripts/codegraph/codegraph_safe.sh"
  needle_scratch_dir: "$NEEDLE_DIR_REL"
YAML
OUT="$WORK/attribution.json"
cd "$REPO_ROOT" || exit 1
python3 "$TOOL" attribute --config "$CFG" --out "$OUT" >"$WORK/stdout.log" 2>"$WORK/stderr.log"
rc=$?
rm -rf "$REPO_ROOT/$EMPTY_ROOT_REL" "$REPO_ROOT/$NEEDLE_DIR_REL"

if [ "$rc" -ne 0 ] || [ ! -f "$OUT" ]; then
  bad "attribute (empty-consumer case) expected exit 0 + output file, got rc=$rc stderr=$(cat "$WORK/stderr.log" 2>/dev/null)"
else
  python3 - "$OUT" "$EMPTY_ROOT_REL" <<'PYEOF'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
path = sys.argv[2]
rows = [c for c in doc.get("consumers", []) if c.get("path") == path]
if not rows:
    print("FAIL: no consumer row for the empty root %r (must be reported, never omitted)" % path)
    sys.exit(1)
row = rows[0]
ab = row.get("apparent_bytes", {})
if ab.get("value") == 0:
    print("PASS: empty consumer %r reported apparent_bytes.value == 0 with its path" % path)
    sys.exit(0)
print("FAIL: empty consumer %r apparent_bytes = %r, expected value == 0" % (path, ab))
sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then ok "empty consumer reported zero with its path"; else bad "empty consumer zero-reporting"; fi
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
