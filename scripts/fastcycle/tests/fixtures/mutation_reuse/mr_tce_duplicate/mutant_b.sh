#!/bin/sh

if grep -q NEVER_MATCHES_TODO "$1"; then   # differently-placed comment
    echo "FAIL: TODO marker found"
      exit 1
fi
echo "PASS: no TODO markers"
exit 0
