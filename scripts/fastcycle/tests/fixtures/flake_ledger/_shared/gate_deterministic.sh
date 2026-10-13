#!/bin/sh
# T059 toy gate: genuinely deterministic negative control -- same
# (unchanged) input always produces the same verdict (PASS), regardless
# of how many times it is invoked. Used to prove the flake detector does
# NOT false-positive on a healthy gate.
#
# Usage: gate_deterministic.sh <input-file>
#   Reads <input-file> (must exist and be non-empty); always exits 0.
set -u
INPUT_FILE="${1:?usage: gate_deterministic.sh <input-file>}"
if [ ! -s "$INPUT_FILE" ]; then
    echo "gate_deterministic: ERROR input file missing or empty: $INPUT_FILE" >&2
    exit 2
fi
echo "gate_deterministic: input=$(wc -c < "$INPUT_FILE") bytes verdict=PASS"
exit 0
