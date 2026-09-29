#!/usr/bin/env bash
# Toy gate slated for REMOVAL in the transfer-proof scenarios. Detects
# BANNED_PATTERN_X. Its removal is legal ONLY when a surviving gate is
# proven (by a recorded run) to also FAIL on the exact mutation that used
# to make THIS gate fail — DEC-32.
set -euo pipefail
TARGET="${1:?usage: gate_removed.sh <target-file>}"
if grep -q "BANNED_PATTERN_X" "$TARGET" 2>/dev/null; then
    echo "gate_removed: FAIL — BANNED_PATTERN_X present in $TARGET" >&2
    exit 1
fi
echo "gate_removed: PASS"
exit 0
