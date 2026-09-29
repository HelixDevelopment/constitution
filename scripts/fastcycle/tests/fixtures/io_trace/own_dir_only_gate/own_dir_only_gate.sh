#!/bin/sh
# T052 fixture: negative control for test_io_trace_red.sh (the CT-5 addition
# named explicitly in tasks.md T052: "a gate reading only its own script
# directory yields exactly that read set and PASSes").
#
# Reads ONLY files that live inside this script's own directory: itself
# (the shell interpreter opens the script file to execute it) and its one
# sibling data file. io_trace.sh (T-C02) MUST report an observed-reads set
# equal to EXACTLY {own_dir_only_gate.sh, sibling_data.txt} -- no extras
# (e.g. no accidental inclusion of unrelated shared-library opens the
# real implementation must filter, no phantom entries) and no omissions.
# This is the false-positive guard (§11.4.201(1)) for the io-trace
# mechanism itself: a tracer that over-reports (picks up dynamic-linker
# noise) or under-reports (misses a real read) both fail this scenario.
#
# $1 = absolute path to this fixture's own directory.
set -eu
dir="$1"
cat "$dir/sibling_data.txt" >/dev/null
