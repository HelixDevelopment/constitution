#!/bin/sh
if grep -qE 'TODO|XXX' "$1"; then
    echo "FAIL: TODO marker found"
    exit 1
fi
echo "PASS: no TODO markers"
exit 0
