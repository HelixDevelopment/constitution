#!/bin/sh
# Stub tool: exits with the rc=N found in the input file; prints the say=TEXT line to stdout.
sed -n 's/^say=//p' "$1"
n=$(sed -n 's/^rc=//p' "$1"); exit "${n:-2}"
