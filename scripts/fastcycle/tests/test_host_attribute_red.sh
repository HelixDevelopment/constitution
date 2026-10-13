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

# --- (4) T153 Round-1 NO-GO finding B4: a root that is ABSENT (never
#     created at all, distinct from (2)'s EXISTING-but-EMPTY directory)
#     must still produce a real, evidence-backed zero -- the pre-fix code
#     wrote a bare `{"value": 0, "note": "root_absent"}` with NO evidence
#     object, which `validate_attribution_doc()`'s OWN schema check
#     correctly rejected as a hand-entered figure, so `attribute` printed
#     "internal error" and exited EXIT_BLIND(4) writing NOTHING --
#     self-contradictory: HR-001/fastcycle.yaml's own documented
#     convention says an absent root is "a real, legitimate zero", but
#     the tool could never actually produce that legitimate zero end to
#     end. This asserts the fixed tool exits 0, writes the output file,
#     and the absent root's row carries value==0 backed by a real
#     evidence object (proving `stat`, a real external command, was
#     genuinely run against it) for BOTH apparent_bytes and
#     exclusive_bytes.
CFG2="$WORK/fastcycle_absent.yaml"
ABSENT_ROOT_REL="qa-results/fastcycle/_t153_b4_absent_root_does_not_exist.$$"
if [ -e "$REPO_ROOT/$ABSENT_ROOT_REL" ]; then
  bad "T153 B4 fixture setup: $ABSENT_ROOT_REL unexpectedly already exists"
else
  NEEDLE_DIR_REL2="qa-results/fastcycle/_t153_b4_needle.$$"
  cat > "$CFG2" <<YAML
schema: fastcycle-config/v1
paths:
  evidence_root: qa-results/fastcycle
host:
  attribution_roots:
    - {path: "$ABSENT_ROOT_REL", consumer_type: cache}
  worktree_prefix: ".claude/worktrees-does-not-exist-t153-b4"
  session_scratch_roots: []
  hardlink_mirror_roots: []
  agent_registry_status: "docs/requests/agent_registry.status.tsv"
  disk_floor:
    volume_path: "."
    floors_gib: {codegraph_launcher_floor: 20}
    codegraph_safe_script: "constitution/scripts/codegraph/codegraph_safe.sh"
  needle_scratch_dir: "$NEEDLE_DIR_REL2"
YAML
  OUT2="$WORK/attribution_absent.json"
  cd "$REPO_ROOT" || exit 1
  python3 "$TOOL" attribute --config "$CFG2" --out "$OUT2" >"$WORK/stdout2.log" 2>"$WORK/stderr2.log"
  rc2=$?
  rm -rf "$REPO_ROOT/$NEEDLE_DIR_REL2"

  if [ "$rc2" -ne 0 ] || [ ! -f "$OUT2" ]; then
    bad "T153 B4: attribute (absent-root case) expected exit 0 + output file, got rc=$rc2 stderr=$(cat "$WORK/stderr2.log" 2>/dev/null)"
  else
    ok "T153 B4: attribute (absent-root case) exits 0 and writes its output file (was: EXIT_BLIND(4), nothing written)"
    python3 - "$OUT2" "$ABSENT_ROOT_REL" <<'PYEOF'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
path = sys.argv[2]
rows = [c for c in doc.get("consumers", []) if c.get("path") == path]
if not rows:
    print("FAIL: no consumer row for the absent root %r (must be reported, never omitted)" % path)
    sys.exit(1)
row = rows[0]
fail = 0
for field in ("apparent_bytes", "exclusive_bytes"):
    entry = row.get(field, {})
    if entry.get("value") != 0:
        print("FAIL: absent root %r %s.value = %r, expected exactly 0" % (path, field, entry.get("value")))
        fail = 1
        continue
    ev = entry.get("evidence")
    if not isinstance(ev, dict) or not ev.get("cmd") or not ev.get("output_path") or not ev.get("sha256"):
        print("FAIL: absent root %r %s has NO real evidence object (hand-entered figure) -- got %r" % (path, field, entry))
        fail = 1
        continue
    print("PASS: absent root %r %s.value == 0 backed by a real evidence object (cmd=%r)" % (path, field, ev.get("cmd")))
sys.exit(fail)
PYEOF
    py_rc=$?
    if [ "$py_rc" -eq 0 ]; then
      ok "T153 B4: absent root's apparent_bytes + exclusive_bytes are both evidence-backed zeros"
    else
      bad "T153 B4: absent root's apparent_bytes/exclusive_bytes shape/evidence"
    fi
  fi
fi

# --- (5) T153 Round-2 NO-GO finding B4: a root that IS accessible on this
#     host but a COMPONENT of its path has NO search/execute permission
#     (a genuine `chmod 000` parent, `EACCES` on `lstat`) must NEVER be
#     reported as a legitimate zero -- `os.path.exists()` internally
#     catches EVERY OSError (permission-denied included) and returns the
#     SAME False it returns for a genuinely absent path, so the pre-fix
#     code could not tell "cannot prove either way" from "genuinely gone".
#
#     Real reproduction performed live (throwaway scratch OUTSIDE this
#     repo, on a real btrfs volume so the needle instrument works, never
#     touching the real checkout) against a PINNED PRE-FIX copy of
#     host_report.py before this fixture was written: a genuine 4 MiB
#     directory under a `chmod 000` parent was reported
#     `{"value": 0, "evidence": {...}}` -- a CONFIDENT, evidence-labeled
#     zero -- while the real, independent `du` instrument run against the
#     SAME path (as the SAME user) reported "Permission denied", not zero.
#     Re-run against the fixed tool below: the root is reported honestly
#     UNMEASURED with reason `root_unreadable_permission_denied`, NEVER
#     coerced to a false 0, and `attribute` correctly signals BLIND
#     (rc=4) for this run rather than a false-clean 0.
#
#     Skipped (not a finding) when run as root: permission bits are inert
#     for uid 0, so this specific reproduction cannot be constructed --
#     an environment gap, honestly noted, never silently omitted.
if [ "$(id -u)" = "0" ]; then
  ok "T153 B4 permission-denied check: SKIPPED (running as root -- permission bits inert, not a finding)"
else
  # NOTE: must live under $REPO_ROOT (real btrfs volume), NEVER under $WORK
  # (mktemp -d resolves to tmpfs in this environment) -- the exclusive-
  # bytes needle instrument requires a real btrfs filesystem (module
  # docstring: "MEASUREMENT-INSTRUMENT TRAP"); a tmpfs root would fail the
  # needle for an entirely UNRELATED reason (EXIT_NEEDLE(3), "not a btrfs
  # filesystem") before ever reaching this assertion. Matches assertion
  # (2)/(4)'s own established convention of placing measured roots under
  # $REPO_ROOT/qa-results/fastcycle/ (gitignored, .gitignore:579).
  DENIED_PARENT_REL="qa-results/fastcycle/_t153_b4_denied_parent.$$"
  DENIED_ROOT_REL="$DENIED_PARENT_REL/subdir"
  mkdir -p "$REPO_ROOT/$DENIED_ROOT_REL"
  python3 -c "open('$REPO_ROOT/$DENIED_ROOT_REL/data.bin', 'wb').write(b'x' * 65536)"
  chmod 000 "$REPO_ROOT/$DENIED_PARENT_REL"

  CFG3="$WORK/fastcycle_denied.yaml"
  NEEDLE_DIR_REL3="qa-results/fastcycle/_t153_b4_needle_denied.$$"
  cat > "$CFG3" <<YAML
schema: fastcycle-config/v1
paths:
  evidence_root: qa-results/fastcycle
host:
  attribution_roots:
    - {path: "$DENIED_ROOT_REL", consumer_type: cache}
  worktree_prefix: ".claude/worktrees-does-not-exist-t153-b4-denied"
  session_scratch_roots: []
  hardlink_mirror_roots: []
  agent_registry_status: "docs/requests/agent_registry.status.tsv"
  disk_floor:
    volume_path: "."
    floors_gib: {codegraph_launcher_floor: 20}
    codegraph_safe_script: "constitution/scripts/codegraph/codegraph_safe.sh"
  needle_scratch_dir: "$NEEDLE_DIR_REL3"
YAML
  OUT3="$WORK/attribution_denied.json"
  cd "$REPO_ROOT" || exit 1
  python3 "$TOOL" attribute --config "$CFG3" --out "$OUT3" >"$WORK/stdout3.log" 2>"$WORK/stderr3.log"
  rc3=$?
  # restore perms BEFORE any rm -rf attempt (rm needs search permission on
  # the parent to remove its child).
  chmod 755 "$REPO_ROOT/$DENIED_PARENT_REL" 2>/dev/null || true
  rm -rf "$REPO_ROOT/$NEEDLE_DIR_REL3" "$REPO_ROOT/$DENIED_PARENT_REL"

  if [ "$rc3" -ne 4 ] || [ ! -f "$OUT3" ]; then
    bad "T153 B4: attribute (permission-denied case) expected exit 4 (BLIND) + output file, got rc=$rc3 stderr=$(cat "$WORK/stderr3.log" 2>/dev/null)"
  else
    ok "T153 B4: attribute (permission-denied case) exits 4 (BLIND) and writes its output file (was: exit 0, false zero)"
    python3 - "$OUT3" "$DENIED_ROOT_REL" <<'PYEOF'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
path = sys.argv[2]
rows = [c for c in doc.get("consumers", []) if c.get("path") == path]
if not rows:
    print("FAIL: no consumer row for the permission-denied root %r (must be reported, never omitted)" % path)
    sys.exit(1)
row = rows[0]
fail = 0
for field in ("apparent_bytes", "exclusive_bytes"):
    entry = row.get(field, {})
    if entry.get("value") == 0:
        print("FAIL: permission-denied root %r %s reported a FALSE zero (value=0) -- must be UNMEASURED, got %r"
              % (path, field, entry))
        fail = 1
        continue
    if entry.get("value") != "UNMEASURED":
        print("FAIL: permission-denied root %r %s.value = %r, expected 'UNMEASURED'" % (path, field, entry.get("value")))
        fail = 1
        continue
    mi = entry.get("missing_instrument", "")
    if "permission_denied" not in mi:
        print("FAIL: permission-denied root %r %s missing_instrument = %r, expected it to name permission_denied"
              % (path, field, mi))
        fail = 1
        continue
    print("PASS: permission-denied root %r %s honestly UNMEASURED (missing_instrument=%r), never a false zero"
          % (path, field, mi))
sys.exit(fail)
PYEOF
    py_rc=$?
    if [ "$py_rc" -eq 0 ]; then
      ok "T153 B4: permission-denied root's apparent_bytes + exclusive_bytes are both honestly UNMEASURED, never a false zero"
    else
      bad "T153 B4: permission-denied root's apparent_bytes/exclusive_bytes shape/reason"
    fi
  fi
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
