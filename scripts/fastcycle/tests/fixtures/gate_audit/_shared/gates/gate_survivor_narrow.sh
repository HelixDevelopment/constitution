#!/usr/bin/env bash
# Toy NARROW surviving gate: does NOT absorb gate_removed.sh's coverage
# (only catches BANNED_PATTERN_Y, never BANNED_PATTERN_X). Used for the
# golden-bad scenario — a removal claims this gate as the transfer target,
# but a real run against gate_removed.sh's planted mutation shows this
# gate PASSES (does not fail) on it, so the transfer claim is FALSE and
# gate_audit.py MUST refuse the removal.
set -euo pipefail
TARGET="${1:?usage: gate_survivor_narrow.sh <target-file>}"
if grep -q "BANNED_PATTERN_Y" "$TARGET" 2>/dev/null; then
    echo "gate_survivor_narrow: FAIL — BANNED_PATTERN_Y present in $TARGET" >&2
    exit 1
fi
echo "gate_survivor_narrow: PASS"
exit 0
