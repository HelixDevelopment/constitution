#!/bin/sh
# toy gate v2: checks a widget file has no FIXME markers (different rule)
if grep -q FIXME "$1"; then
    echo "FAIL: FIXME marker found"
    exit 1
fi
echo "PASS: no FIXME markers"
exit 0
