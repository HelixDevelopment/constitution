#!/bin/sh
# toy gate: checks a widget file has no TODO markers
if grep -q TODO "$1"; then
    echo "FAIL: TODO marker found"
    exit 1
fi
echo "PASS: no TODO markers"
exit 0
