#!/bin/sh
# T052 fixture: golden-bad scenario for test_io_trace_red.sh (plan T-C02).
#
# Builds the target file's path DYNAMICALLY at runtime by string-concatenating
# two variables (never a single literal), then reads it. io_trace.sh (T-C02)
# MUST record the RESOLVED absolute path in its observed-reads output --
# never the literal unexpanded string "$dir/${name}${ext}" a naive
# static-analysis (grep-the-source) approach would produce. This is why
# T-C02 mandates strace-based OBSERVED tracing rather than source scanning:
# only the syscall layer sees the string after shell expansion.
#
# $1 = absolute path to this fixture's own directory (passed by the RED
#      test so this script never hardcodes its own location).
set -eu
dir="$1"
base="target"
ext=".txt"
name="${base}_data${ext}"
cat "$dir/$name" >/dev/null
