#!/usr/bin/env bash
# Toy EXECUTING gate: a real, genuinely-failable check. Used to prove
# gate_audit.py's classifier correctly labels a normal, live gate
# "executing" (never mis-flags it "vacuous" or "named-only").
set -euo pipefail
TARGET="${1:?usage: gate_executing.sh <target-file>}"
if grep -q "FORBIDDEN_MARKER" "$TARGET" 2>/dev/null; then
    echo "gate_executing: FAIL — FORBIDDEN_MARKER present in $TARGET" >&2
    exit 1
fi
echo "gate_executing: PASS"
exit 0
