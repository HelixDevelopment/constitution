#!/bin/sh
# =============================================================================
# T085 US2 Round 2 remediation regression (I-R2-4 + I-R2-5, IMPORTANT,
# 2026-09-30).
# =============================================================================
#
# I-R2-4: a forked child process's cwd is seeded from its PARENT's tracked
#   cwd at fork time, never unconditionally from io_trace_parse.py's own
#   process start_cwd -- reproduced live before this fix: `cd sub; sh -c
#   'cat data.txt'` recorded a non-existent "<start>/data.txt", missing the
#   real "<start>/sub/data.txt".
# I-R2-5: `faccessat`/`faccessat2` (a permission-probe absence-branch, e.g.
#   `[ -r marker ]`) is now traced -- previously only existence checks
#   (stat/newfstatat, via `[ -e marker ]`) were covered.
#
# §11.4.199: every check is a REAL strace+parse invocation via the real
# io_trace.sh tool against scratch gate scripts this file constructs.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/io_trace.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 2 I-R2-4/I-R2-5 regression: io_trace fork-inherits-cwd + faccessat tracing =="

if ! command -v strace >/dev/null 2>&1; then
    echo "SKIP: strace not available on this host -- cannot exercise the real tracer (§11.4.3)"
    exit 0
fi

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

# -----------------------------------------------------------------------
# I-R2-4: forked child inherits parent's post-chdir cwd.
# -----------------------------------------------------------------------
mkdir -p "$SCRATCH/sub"
echo "sub-data" > "$SCRATCH/sub/data.txt"
echo "top-level-decoy-must-NOT-be-read" > "$SCRATCH/data.txt"

cat > "$SCRATCH/fork_cwd_gate.sh" <<'EOF'
#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/sub"
sh -c 'cat data.txt' >/dev/null
EOF
chmod +x "$SCRATCH/fork_cwd_gate.sh"

OUT1=$(sh "$TOOL" trace "$SCRATCH/fork_cwd_gate.sh" 2>&1)
RC1=$?
if [ "$RC1" -eq 0 ] && echo "$OUT1" | grep -qF "$SCRATCH/sub/data.txt"; then
    ok "R1 (I-R2-4): the forked child's read of 'data.txt' resolved to the REAL $SCRATCH/sub/data.txt (parent's post-chdir cwd correctly inherited)"
else
    bad "R1 (I-R2-4) FAILED: forked child's read did not resolve to $SCRATCH/sub/data.txt (rc=$RC1): $OUT1"
fi
R2_CHECK=$(printf '%s' "$OUT1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
bad_decoy = any(r.endswith("/data.txt") and not r.endswith("/sub/data.txt") for r in d.get("reads", []))
print("DECOY_PRESENT" if bad_decoy else "DECOY_ABSENT")
' 2>/dev/null)
if [ "$R2_CHECK" = "DECOY_ABSENT" ]; then
    ok "R2 (I-R2-4): the reads set does NOT contain the wrong top-level '$SCRATCH/data.txt' decoy path"
else
    bad "R2 (I-R2-4): the reads set ALSO contains the WRONG top-level decoy path (pre-fix bug signature), check='$R2_CHECK'"
fi

# -----------------------------------------------------------------------
# I-R2-5: faccessat/faccessat2 permission-probe absence-branch traced.
# -----------------------------------------------------------------------
cat > "$SCRATCH/access_gate.sh" <<'EOF'
#!/bin/sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
[ -r "$HERE/absent_marker.txt" ]
exit 0
EOF
chmod +x "$SCRATCH/access_gate.sh"

OUT2=$(sh "$TOOL" trace "$SCRATCH/access_gate.sh" 2>&1)
RC2=$?
if [ "$RC2" -eq 0 ] && echo "$OUT2" | grep -qF "$SCRATCH/absent_marker.txt"; then
    ok "R3 (I-R2-5): a '[ -r absent_marker.txt ]' permission-probe absence-branch is traced and recorded as a read"
else
    bad "R3 (I-R2-5) FAILED: the absent_marker.txt permission-probe was NOT recorded (rc=$RC2): $OUT2"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
