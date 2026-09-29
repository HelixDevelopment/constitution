#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
ran=0
for t in "$here"/test_*.py "$here"/test_*.sh; do
  [ -e "$t" ] || continue
  ran=$((ran + 1))
  echo "=== $(basename "$t") ==="
  case "$t" in
    *.py) runner=(python3 "$t") ;;
    *.sh) runner=(bash "$t") ;;
  esac
  if ! "${runner[@]}"; then
    echo "FAIL: $(basename "$t")"
    fail=1
  fi
done
if [ "$ran" -eq 0 ]; then
  echo "FATAL: zero test files matched — the harness is blind, this is NOT a pass" >&2
  exit 2
fi
echo "ran $ran test file(s)"
exit "$fail"
