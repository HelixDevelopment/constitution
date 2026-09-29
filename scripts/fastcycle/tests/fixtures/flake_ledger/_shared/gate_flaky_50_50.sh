#!/bin/sh
# T059 toy gate: genuinely alternates PASS/FAIL, driven by a run-counter
# file the CALLER controls -- so the RED test can reproduce a specific
# 10-run sequence deterministically (never real randomness, so the test
# itself stays deterministic per §11.4.50), while still representing a
# gate whose verdict is NOT a pure function of its (unchanged) real input.
#
# Usage: gate_flaky_50_50.sh <counter-file>
#   Reads an integer N from <counter-file> (0 if absent), exits 0 (PASS)
#   if N is even, 1 (FAIL) if N is odd, then increments the file.
set -u
COUNTER_FILE="${1:?usage: gate_flaky_50_50.sh <counter-file>}"
N=0
[ -f "$COUNTER_FILE" ] && N=$(cat "$COUNTER_FILE")
NEXT=$((N + 1))
echo "$NEXT" > "$COUNTER_FILE"
if [ $((N % 2)) -eq 0 ]; then
    echo "gate_flaky_50_50: run=$N verdict=PASS"
    exit 0
else
    echo "gate_flaky_50_50: run=$N verdict=FAIL"
    exit 1
fi
