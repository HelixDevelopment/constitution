#!/usr/bin/env bash
# run_all.sh — run every mechanical-tools test suite and aggregate the counts.
#
# Prints one line per suite, then a combined summary in the same shape the tools
# parse. Exit 0 only when every suite reported zero failures; exit 1 if any suite
# failed; exit 2 if a suite could not be measured at all.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/../lib/mech_common.sh"

TOTAL_P=0 TOTAL_F=0 UNMEASURED=0
LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/mech-runall.XXXXXX")"

for t in "$TESTS_DIR"/test_*.sh; do
  name="$(basename "$t")"
  log="$LOGDIR/$name.log"
  bash "$t" > "$log" 2>&1
  rc=$?
  if counts="$(mech_parse_summary "$log")"; then
    p="${counts% *}"; f="${counts#* }"
    TOTAL_P=$((TOTAL_P + p)); TOTAL_F=$((TOTAL_F + f))
    printf '%-32s rc=%-3s %4s passed %4s failed\n' "$name" "$rc" "$p" "$f"
    [ "$f" -gt 0 ] && sed -n '/^Failures:/,$p' "$log"
  else
    printf '%-32s rc=%-3s UNMEASURED (log: %s)\n' "$name" "$rc" "$log"
    UNMEASURED=1
  fi
done

echo
if [ "$UNMEASURED" -eq 1 ]; then
  printf 'INSTRUMENT FAILURE: a suite produced no parseable summary (logs: %s)\n' "$LOGDIR"
  exit "$MECH_EXIT_CANNOT_RUN"
fi
rm -rf "$LOGDIR"
if [ "$TOTAL_F" -eq 0 ]; then
  printf 'ALL SUITES: %d passed, 0 failed\n' "$TOTAL_P"
  exit "$MECH_EXIT_OK"
fi
printf 'ALL SUITES: %d failed, %d passed\n' "$TOTAL_F" "$TOTAL_P"
exit "$MECH_EXIT_FINDING"
