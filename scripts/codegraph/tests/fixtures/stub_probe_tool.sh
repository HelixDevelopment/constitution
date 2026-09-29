#!/bin/sh
# UNIT-TEST STUB ONLY (§11.4.27): stands in for fk_cascade_probe.py. STUB_PROBE_RC 0 SAFE / 1 HAZARD / 2 CANNOT_EVALUATE.
[ -n "${STUB_CALL_LOG:-}" ] && echo "probe_tool $*" >> "$STUB_CALL_LOG"
rc="${STUB_PROBE_RC:-0}"
case "$rc" in 0) v=SAFE;; 1) v=HAZARD;; *) v=CANNOT_EVALUATE;; esac
echo "{\"verdict\": \"$v\"}"
exit "$rc"
