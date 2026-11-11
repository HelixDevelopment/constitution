#!/usr/bin/env bash
# RED-first regression (CON-033 review R5-F2): the store-tier suite must give the
# same verdicts when TMPDIR is a NON-canonical path (a "." or ".." component), as the
# tier reason names the resolved path. Before the fix E2/E2b/L1/L2 FAILED there.
# Exit 0 pass, 1 fail, 77 skip (no usable temp base).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SUITE="$HERE/test_review_record_store_tier_all_entries_regression.sh"
base="${TMPDIR:-/tmp}"
[ -d "$base" ] && [ -w "$base" ] || { echo "SKIP reason=topology_unsupported (no writable TMPDIR)"; exit 77; }
W=$(mktemp -d "$base/rr_noncanon.XXXXXX") || exit 2
trap 'rm -rf -- "${W:?}"' EXIT
chmod 0700 "$W"; mkdir -m 0700 "$W/sub"
NC="$W/sub/../."          # resolves to $W, spelled with ".." and "."
out=$(TMPDIR="$NC" bash "$SUITE" 2>&1); rc=$?
echo "$out" | tail -3
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q '^FAIL'; then
  echo "PASS: store-tier suite is green under a non-canonical TMPDIR ($NC)"; exit 0
fi
echo "FAIL: store-tier suite rc=$rc under a non-canonical TMPDIR ($NC)"; exit 1
