#!/bin/sh
# UNIT-TEST STUB ONLY (§11.4.27): stands in for fk_index_patch.py.
# STUB_PATCH_RC: 0 ready (prints $STUB_RUNNER_BIN with --print-bin), 2 REFUSED, 3 NOT_NEEDED.
[ -n "${STUB_CALL_LOG:-}" ] && echo "patch_tool $*" >> "$STUB_CALL_LOG"
rc="${STUB_PATCH_RC:-0}"
case "$rc" in
  0) echo "${STUB_RUNNER_BIN:?}";;
  2) echo '{"status": "REFUSED", "reason": "stub shape mismatch"}' >&2;;
  3) echo '{"status": "NOT_NEEDED", "reason": "stub"}';;
esac
exit "$rc"
