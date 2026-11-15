#!/usr/bin/env bash
# tr8_needles.sh TEST_ROUND8_FILE WORK_DIR — runs only the stale-lock probe, drain_session and their control needles of a
# test_round8.sh copy, fast, under the test library's own options (set -uo pipefail). The function text and the needle
# lines are taken from the file itself (from "drain_session() {" up to the "# I-1 chaos" echo), so a mutated copy is what
# runs. WORK_DIR must be an empty directory the caller made and removes; this script deletes nothing.
# Prints the needle results and "needles: PASS n FAIL m"; exit 0 when all pass, 1 when one fails, 2 when the
# snippet cannot be found in the file or WORK_DIR is not an empty directory.
set -uo pipefail
f="${1:?usage: tr8_needles.sh TEST_ROUND8_FILE WORK_DIR}"; SB="${2:?usage: tr8_needles.sh TEST_ROUND8_FILE WORK_DIR}"
[ -d "$SB" ] && [ -z "$(ls -A "$SB")" ] || { echo "needles: WORK_DIR is not an empty directory"; exit 2; }
snippet="$(awk '/^drain_session\(\) \{/ { on = 1 } /^echo "# I-1 chaos/ { on = 0 } on' "$f")"
case "$snippet" in
  *'stale_index_locks() {'*'stale-lock probe: the same lock, closed'*'drain_session: every member gone'*) ;;
  *) echo "needles: snippet not found in $f"; exit 2 ;;
esac
T_PASS=0; T_FAIL=0
ok()  { T_PASS=$((T_PASS+1)); printf '  ok   %s\n' "$*"; }
nok() { T_FAIL=$((T_FAIL+1)); printf '  FAIL %s\n' "$*"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1 (expected [$2] got [$3])"; fi; }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else nok "$d"; fi; }
eval "$snippet"
echo "needles: PASS $T_PASS FAIL $T_FAIL"
[ "$T_FAIL" = 0 ]
