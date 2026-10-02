#!/bin/sh
# =============================================================================
# T085 US2 Round 5 remediation regression (Minor finding 6, 2026-10-02).
# =============================================================================
#
# T085 Round 4's independent review, Minor finding 6: "render_keys
# window: R3-I3's snapshot-restore still overwrites any other track's
# edit made between the snapshot and the restore."
#
# test_render_keys_red.sh's own cleanup() now refuses to restore (and
# loudly warns instead) a twin file in rk_stale_key_caught/ or
# rk_touched_identical/ -- the two fixture directories that file's own
# Sections C3/C4 NEVER render a twin into (only a read-only
# `render_keys.py check`) -- when that file's content changed during the
# test's own run window, since any such change can ONLY be a concurrent,
# external edit.
#
# This file extracts and exercises `_rk_restore_or_warn()`'s own logic
# directly (sourcing it would require a full run of the parent RED
# test's heavy setup; this proves the FUNCTION's logic in isolation,
# matching this test's own narrow scope -- the parent file's full run is
# its own already-passing regression coverage).
#
# Usage: sh test_render_keys_concurrent_edit_r5_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
PARENT="$HERE/test_render_keys_red.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 5 Minor-6 regression: test_render_keys_red.sh cleanup() never clobbers a concurrent edit =="

if [ ! -f "$PARENT" ]; then
    bad "control needle: $PARENT does not exist -- cannot regression-test it"
    exit 1
fi

if grep -q "_rk_restore_or_warn" "$PARENT"; then
    ok "control needle: $PARENT defines _rk_restore_or_warn() -- the T085 Round 5 fix is present"
else
    bad "control needle FAILED: $PARENT does not define _rk_restore_or_warn() -- the fix is absent, nothing below can be meaningfully tested"
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# Extract the exact function body + its allowlist variable from the real
# parent file (never re-implemented/duplicated here -- producer != this
# test's own copy would risk testing a drifted shadow of the real logic).
# Line-range extraction (never a brace-counting awk heuristic that can
# double-print the closing line when a rule matches it twice): find the
# allowlist assignment's own line number, and the function definition's
# own closing "}" line number (the FIRST bare "}" line at or after the
# function's opening "_rk_restore_or_warn() {" line), then sed that
# exact, unambiguous range.
TWINS_LINE=$(grep -n "^_RK_TEST_OWNED_TWINS=" "$PARENT" | head -1 | cut -d: -f1)
FUNC_OPEN_LINE=$(grep -n "^_rk_restore_or_warn() {" "$PARENT" | head -1 | cut -d: -f1)
if [ -z "$TWINS_LINE" ] || [ -z "$FUNC_OPEN_LINE" ]; then
    bad "could not locate _RK_TEST_OWNED_TWINS= or _rk_restore_or_warn()'s opening line in $PARENT -- its exact shape must have changed; this guard needs updating to match"
    echo ""
    echo "== Summary: ok $PASS / NOT ok $FAIL =="
    exit 1
fi
FUNC_CLOSE_LINE=$(tail -n "+$FUNC_OPEN_LINE" "$PARENT" | grep -n "^}" | head -1 | cut -d: -f1)
FUNC_CLOSE_LINE=$((FUNC_OPEN_LINE + FUNC_CLOSE_LINE - 1))
FUNC_SRC=$(sed -n "${TWINS_LINE},${FUNC_CLOSE_LINE}p" "$PARENT")
if [ -z "$FUNC_SRC" ]; then
    bad "could not extract _rk_restore_or_warn()'s source from $PARENT (empty extraction) -- its exact shape must have changed; this guard needs updating to match"
    echo ""
    echo "== Summary: ok $PASS / NOT ok $FAIL =="
    exit 1
fi

# -----------------------------------------------------------------------
# Check 1: a file OUTSIDE the owned-twins allowlist whose content
# changed since the snapshot is LEFT AS-IS (the concurrent-edit case).
# -----------------------------------------------------------------------
FIXDIR="$WORK"
mkdir -p "$FIXDIR/rk_stale_key_caught"
f1="$FIXDIR/rk_stale_key_caught/source.html"
snap1="$WORK/snap1.html"
echo "pre-test snapshot content" > "$snap1"
echo "CONCURRENT edit by another track" > "$f1"

OUT1=$(FIXDIR="$FIXDIR" sh -c "
$FUNC_SRC
_rk_restore_or_warn '$f1' '$snap1'
cat '$f1'
" 2>&1)

if echo "$OUT1" | grep -q "^CONCURRENT edit by another track$" && echo "$OUT1" | grep -qi "WARNING"; then
    ok "1: a file OUTSIDE the owned-twins allowlist (rk_stale_key_caught/) whose content changed is LEFT AS-IS with a loud warning, never silently overwritten"
else
    bad "1 FAILED: expected the concurrent edit preserved + a warning, got: $OUT1"
fi

# -----------------------------------------------------------------------
# Check 2: a file OUTSIDE the allowlist whose content is UNCHANGED since
# the snapshot is a harmless no-op (no warning, content stays as-is,
# which already equals the snapshot).
# -----------------------------------------------------------------------
f2="$FIXDIR/rk_stale_key_caught/source2.html"
snap2="$WORK/snap2.html"
echo "identical content" > "$snap2"
echo "identical content" > "$f2"

OUT2=$(FIXDIR="$FIXDIR" sh -c "
$FUNC_SRC
_rk_restore_or_warn '$f2' '$snap2'
cat '$f2'
" 2>&1)

if echo "$OUT2" | grep -q "^identical content$" && ! echo "$OUT2" | grep -qi "WARNING"; then
    ok "2: a file OUTSIDE the allowlist whose content is UNCHANGED since the snapshot is a silent no-op (no false-positive warning)"
else
    bad "2 FAILED: expected an unchanged file to be a silent no-op, got: $OUT2"
fi

# -----------------------------------------------------------------------
# Check 3 (negative control): a file INSIDE the owned-twins allowlist
# still restores unconditionally -- the fix does not over-protect this
# test's own legitimate render targets.
# -----------------------------------------------------------------------
mkdir -p "$FIXDIR/rk_changed_all_four"
f3="$FIXDIR/rk_changed_all_four/source.html"
snap3="$WORK/snap3.html"
echo "original pre-test content" > "$snap3"
echo "this test's own freshly-rendered content" > "$f3"

OUT3=$(FIXDIR="$FIXDIR" sh -c "
$FUNC_SRC
_rk_restore_or_warn '$f3' '$snap3'
cat '$f3'
" 2>&1)

if echo "$OUT3" | grep -q "^original pre-test content$"; then
    ok "3 (negative control): a file INSIDE the owned-twins allowlist (rk_changed_all_four/source.html, this test's own real render target) is STILL restored unconditionally -- the fix does not over-protect legitimate self-renders"
else
    bad "3 (negative control) FAILED: expected the owned twin to be restored to its snapshot, got: $OUT3"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
