#!/usr/bin/env bash
# Recording bootstrap stub for post_update_hook trigger tests.
# Appends argv to $BOOTSTRAP_STUB_LOG. Fails (rc 1) on any run when
# BOOTSTRAP_STUB_FAIL=1 — EXCEPT succeeds for --defer unless
# BOOTSTRAP_STUB_DEFER_FAIL=1.
set -u
: "${BOOTSTRAP_STUB_LOG:=/dev/null}"
printf 'bootstrap %s\n' "$*" >> "$BOOTSTRAP_STUB_LOG"
for a in "$@"; do
  if [ "$a" = "--defer" ]; then
    [ "${BOOTSTRAP_STUB_DEFER_FAIL:-0}" = "1" ] && exit 1
    mkdir -p "${JEV_STATE_DIR:-/tmp/jev-test-state}" 2>/dev/null || true
    : > "${JEV_STATE_DIR:-/tmp/jev-test-state}/bootstrap.pending" 2>/dev/null || true
    exit 0
  fi
done
[ -n "${BOOTSTRAP_STUB_RC:-}" ] && exit "$BOOTSTRAP_STUB_RC"
[ "${BOOTSTRAP_STUB_FAIL:-0}" = "1" ] && exit 1
exit 0
