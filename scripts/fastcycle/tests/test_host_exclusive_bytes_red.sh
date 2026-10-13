#!/bin/bash
# T141 RED test (SpecKit-004 "fast-dev-cycles", User Story 6, plan task T-F01,
# contract host-resource-attribution.md HR-001) for `host/host_report.py attribute`'s
# btrfs exclusive-bytes measurement primitive.
#
# Purpose: prove, before host_report.py exists, that its `attribute` subcommand's
# self-validating control needle (C-004/§11.4.273/§11.4.201(7)(b)) genuinely
# distinguishes an UNSHARED file (exclusive bytes == its full size) from a
# freshly REFLINKED copy of that same file (exclusive bytes ~0, the bytes are
# SHARED with the original) -- the exact needle the contract's own "Protecting
# tests" line names: "a freshly reflinked copy of a known file shows ~0
# exclusive bytes; a fresh unshared file shows its full size".
#
# MEASUREMENT-INSTRUMENT TRAP found and closed while authoring this fixture
# (§11.4.201(7), a genuine finding, not decoration): `btrfs filesystem du -s`
# invoked IMMEDIATELY after `dd`-writing a file, with no `sync`, reports
# Total=Exclusive=0 for a genuinely UNSHARED file (delayed-allocation extents
# not yet committed to the btrfs extent tree) -- indistinguishable from the
# reflinked-copy case this needle exists to detect. Reproduced live on this
# host (/mnt/track1, btrfs) 2026-09-30: `dd ... ; btrfs filesystem du -s -raw
# f` -> 0/0/0 for an unshared file; the SAME file after an interposed `sync`
# -> correctly reports its full size. The implementation under test (T147)
# MUST `sync` (or fsync the specific file) before every `btrfs filesystem du
# -s` measurement; this test's assertions are written tight enough (exact
# equality on the unshared file, not merely "nonzero") that skipping the sync
# would fail this test, not merely the reflink half.
#
# Scope: this test exercises ONLY the `needle` object `attribute` emits
# (proving the exclusive-bytes measurement primitive itself is trustworthy).
# The full attribute report schema (consumer rows, evidence objects, empty
# consumer -> value 0) is T142's job, not duplicated here.
#
# Producer != Verifier (§11.4.240): this RED test is authored before
# host/host_report.py's `attribute` subcommand (T147) exists; the needle
# byte-count arithmetic below is computed independently in this test file
# (a derived oracle, §11.4.245), never imported from the tool under test.
#
# Requires: btrfs (this project's tree lives on btrfs -- confirmed live,
# `findmnt -T . -o FSTYPE` = btrfs); `cp --reflink=always` support. If either
# is genuinely absent on the executing host, that is itself a real, honestly
# reported SKIP (§11.4.3), never a silently-passing no-op.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC_ROOT=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$FC_ROOT/../../.." && pwd)
TOOL="$FC_ROOT/host/host_report.py"
FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
skip(){ echo "SKIP: $1"; }

# Control needle on the CONTROL NEEDLE (§11.4.201(7)(b)): prove btrfs + reflink
# are genuinely usable on THIS host before trusting a non-btrfs/no-reflink
# result as a real finding rather than an environment gap.
PROBE_DIR="$REPO_ROOT/qa-results/fastcycle/_t141_env_probe.$$"
mkdir -p "$PROBE_DIR" || { echo "RED: cannot create probe dir under repo (needs the repo's own btrfs volume)"; bad "environment probe dir creatable"; echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1; }
: > "$PROBE_DIR/p.bin"
sync
if ! command -v btrfs >/dev/null 2>&1 || ! btrfs filesystem du -s --raw "$PROBE_DIR/p.bin" >/dev/null 2>&1; then
  rm -rf "$PROBE_DIR"
  skip "btrfs filesystem du unavailable on this host/path -- T141 needs a btrfs volume, honest SKIP"
  echo "SUMMARY pass=$PASS fail=0 (SKIPPED, environment gap)"; exit 0
fi
if ! cp --reflink=always "$PROBE_DIR/p.bin" "$PROBE_DIR/p2.bin" 2>/dev/null; then
  rm -rf "$PROBE_DIR"
  skip "cp --reflink=always unavailable on this host/path -- T141 needs reflink support, honest SKIP"
  echo "SUMMARY pass=$PASS fail=0 (SKIPPED, environment gap)"; exit 0
fi
rm -rf "$PROBE_DIR"

if [ ! -f "$TOOL" ]; then
  echo "RED: host_report.py absent at $TOOL"
  bad "host_report.py exists"
  echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

CFG="$WORK/fastcycle.yaml"
NEEDLE_DIR_REL="qa-results/fastcycle/_t141_needle.$$"
cat > "$CFG" <<YAML
schema: fastcycle-config/v1
paths:
  evidence_root: qa-results/fastcycle
host:
  attribution_roots: []
  worktree_prefix: ".claude/worktrees-does-not-exist-t141"
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
cd "$REPO_ROOT" || { bad "cd to repo root"; echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1; }
python3 "$TOOL" attribute --config "$CFG" --out "$OUT" >"$WORK/stdout.log" 2>"$WORK/stderr.log"
rc=$?
rm -rf "$REPO_ROOT/$NEEDLE_DIR_REL"

if [ ! -f "$TOOL" ]; then
  bad "host_report.py did not exist at invocation time"
  echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1
fi

if [ "$rc" -ne 0 ]; then
  bad "attribute exit code expected 0, got $rc (stderr: $(cat "$WORK/stderr.log"))"
  echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1
fi
if [ ! -f "$OUT" ]; then
  bad "attribute wrote no --out file on exit 0"
  echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1
fi

python3 - "$OUT" <<'PYEOF'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
fail = 0
def bad(msg):
    global fail
    print("FAIL:", msg)
    fail = 1
def ok(msg):
    print("PASS:", msg)

needle = doc.get("needle")
if not isinstance(needle, dict):
    bad("attribute doc has no top-level 'needle' object")
    print("SUMMARY pass=0 fail=1")
    sys.exit(1)

u = needle.get("unshared_file")
r = needle.get("reflinked_copy")
if not isinstance(u, dict) or not isinstance(r, dict):
    bad("needle.unshared_file / needle.reflinked_copy missing or not objects")
    print("SUMMARY pass=0 fail=1")
    sys.exit(1)

exp = u.get("expected_bytes")
if not isinstance(exp, int) or exp <= 0:
    bad("needle.unshared_file.expected_bytes must be a positive int, got %r" % (exp,))
else:
    ok("needle.unshared_file.expected_bytes is a positive int (%r)" % exp)

# The unshared file: total AND exclusive must equal its own real size exactly
# (this is the assertion that would fail if the implementation skipped
# `sync` before measuring, per this file's header finding).
if u.get("total_bytes") == exp and u.get("exclusive_bytes") == exp:
    ok("unshared file: total_bytes == exclusive_bytes == expected_bytes (%r)" % exp)
else:
    bad("unshared file: expected total_bytes==exclusive_bytes==%r, got total=%r exclusive=%r"
        % (exp, u.get("total_bytes"), u.get("exclusive_bytes")))

if r.get("expected_bytes") != exp:
    bad("reflinked_copy.expected_bytes (%r) must equal the source file's size (%r)"
        % (r.get("expected_bytes"), exp))
else:
    ok("reflinked_copy.expected_bytes matches the source file's size")

if r.get("total_bytes") != exp:
    bad("reflinked_copy.total_bytes must equal expected_bytes (%r), got %r" % (exp, r.get("total_bytes")))
else:
    ok("reflinked_copy.total_bytes == expected_bytes")

rex = r.get("exclusive_bytes")
TOL = 4096
if isinstance(rex, int) and 0 <= rex <= TOL:
    ok("reflinked_copy.exclusive_bytes is near-zero (%r <= %r)" % (rex, TOL))
else:
    bad("reflinked_copy.exclusive_bytes expected near-zero (<= %r), got %r" % (TOL, rex))

if isinstance(rex, int) and isinstance(u.get("exclusive_bytes"), int) and rex >= u["exclusive_bytes"]:
    bad("reflinked copy's exclusive_bytes (%r) is NOT strictly less than the unshared file's (%r) -- "
        "the needle does not distinguish shared from unshared data" % (rex, u["exclusive_bytes"]))
else:
    ok("reflinked copy's exclusive_bytes is strictly less than the unshared file's")

print("SUMMARY pass=%d fail=%d" % (0 if fail else 1, fail))
sys.exit(1 if fail else 0)
PYEOF
py_rc=$?
if [ "$py_rc" -eq 0 ]; then ok "needle object shape and values correct"; else bad "needle object shape/values"; fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
