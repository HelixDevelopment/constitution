#!/bin/sh
# T052 fixture: control needle for test_io_trace_red.sh (plan T-C02; §11.4.273).
#
# A toy "gate" script whose ONLY declared job is to read the REAL project
# CLAUDE.md (never a copy or synthetic stand-in — §11.4.273 requires the
# needle to be a genuinely known-present value, and this project's own
# top-level CLAUDE.md IS that value for every checkout of this repo). The
# io_trace.sh tool (T-C02, not yet implemented) MUST list this file's path
# in its observed-reads output when traced against this script, per the
# task's control-needle requirement: "a gate known to read CLAUDE.md lists
# it".
#
# $1 = absolute path to the repo root (passed by the RED test, never
#      hardcoded here -- this fixture works from any checkout location).
set -eu
ROOT="$1"
cat "$ROOT/CLAUDE.md" >/dev/null
