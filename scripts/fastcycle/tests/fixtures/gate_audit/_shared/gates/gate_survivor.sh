#!/usr/bin/env bash
# Toy SURVIVING gate: the candidate absorber for gate_removed.sh's coverage.
# Broadened (post-transfer) to also catch BANNED_PATTERN_X, so a recorded
# run against gate_removed.sh's own planted mutation genuinely FAILs here —
# the DEC-32 "recorded run showing the surviving gate FAILs on the removed
# gate's mutation" proof.
set -euo pipefail
TARGET="${1:?usage: gate_survivor.sh <target-file>}"
if grep -q "BANNED_PATTERN_X" "$TARGET" 2>/dev/null; then
    echo "gate_survivor: FAIL — BANNED_PATTERN_X present in $TARGET (absorbed from gate_removed)" >&2
    exit 1
fi
if grep -q "BANNED_PATTERN_Y" "$TARGET" 2>/dev/null; then
    echo "gate_survivor: FAIL — BANNED_PATTERN_Y present in $TARGET" >&2
    exit 1
fi
echo "gate_survivor: PASS"
exit 0
