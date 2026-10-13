#!/bin/sh
# tower_detector.sh -- git-history "patch-tower" detector (S11.4.250
# heuristic-tower pattern, research-derived shortlist item 4,
# docs/research/fast_dev_cycles_acceleration_2026-10/FINDINGS.md S6).
#
# This is a thin sh dispatcher (house pattern: review/precheck_pack.sh ->
# review/lib/precheck_pack_run.py, gates/io_trace.sh ->
# gates/lib/io_trace_parse.py) -- argument pass-through + a python3
# availability precondition only; the real detection logic lives in
# review/lib/tower_detector_run.py, see that file's own module docstring
# for the full design (symbol-boundary detection, the branch-adding AND-
# NOT classification rule, item-token grouping, honest limitations).
#
# CLI:
#   tower_detector.sh [--repo <path>] [--item <ID>] [--range <rev-range>]
#                      [--path <path>] [--min-branch-commits <N>]
#                      [--refractor-ratio <0.0-1.0>] --out <report.json>
#
# At least one of --item / --range / --path is required (enforced by the
# library's own argparse, this dispatcher does not duplicate that check --
# duplicating a validation rule in two places is exactly the kind of
# drift-prone layering S11.4.250 itself warns against).
#
# ADVISORY ONLY (S11.4.269): this tool's non-zero exit on a flagged
# finding is informational, matching this project's own house convention
# for precheck-style tools (review/precheck_pack.sh: "1 any check
# FAILs"). It is NOT wired into any build/review/dispatch gate by this
# commit, and per S11.4.269 a future wiring MUST remain advisory-only --
# never a hard block on this tool's own mechanical judgment alone.
#
# Exit codes (delegated verbatim from tower_detector_run.py -- see its
# own module docstring): 0 = ran cleanly, zero findings; 1 = ran cleanly,
# >= 1 finding (advisory); 2 = usage/argument error; 3 = git/repository
# resolution error. This dispatcher adds exit 4 for "no usable python3
# interpreter found" (the one precondition this shell layer itself
# checks, distinct from every other exit code the library owns).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/lib/tower_detector_run.py"

PY=""
for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1; then
        PY="$cand"
        break
    fi
done
if [ -z "$PY" ]; then
    echo "tower_detector.sh: no python3/python interpreter found on PATH" >&2
    exit 4
fi

exec "$PY" "$LIB" "$@"
