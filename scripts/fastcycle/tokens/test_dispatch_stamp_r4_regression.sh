#!/usr/bin/env bash
# test_dispatch_stamp_r4_regression.sh -- T048 Round 4 (independent
# Opus-xhigh review of SpecKit-004 "fast-dev-cycles" User Story 1's own
# round-3 remediation trail) finding R4-I2 regression guard.
#
# R4-I2 (verbatim finding, 2026-09-30): "R3-M1's fix (WIT fallback) has no
# regression test, and the fallback path is currently UNREACHABLE in
# normal use. The reviewer found: with a normal PATH, release_prefix.sh
# always resolves successfully, and Section G now skips prefix derivation
# entirely -- so putting the old ATM literal back gave IDENTICAL pass/fail
# counts before and after their test run, meaning the current test suite
# cannot tell the fix apart from its absence." (Independently re-confirmed
# live before authoring this file: `bash constitution/scripts/
# release_prefix.sh` on this host prints "atmosphere" unconditionally --
# the WIT branch in dispatch_stamp.sh's own `_fc_default_item_prefix()`
# genuinely never executes under a normal checkout + normal PATH, exactly
# as the reviewer found.)
#
# Background: R3-M1 fixed `_fc_default_item_prefix()`'s own fallback --
# which used to be a hardcoded, project-specific "ATM" literal landed
# inside this project-agnostic constitution submodule (a §11.4.28/§11.4.177
# decoupling violation, directly contradicting the function's OWN header
# comment) -- to instead reuse `_fc_derive_key_prefix("")`'s existing
# neutral "WIT" no-letters branch. `test_dispatch_stamp.sh`'s pre-existing
# Section G (jq-absent AWK-fallback coverage) bypasses this function
# entirely via `FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+'` (a full regex
# override dispatch_stamp.sh itself checks BEFORE ever calling
# `_fc_default_item_prefix()`) -- by design, per that section's own
# comment, since Section G's purpose is jq-absence coverage, not prefix-
# derivation coverage -- so it never exercised, and was never intended to
# exercise, the R3-M1 fix.
#
# THIS FILE closes that gap by genuinely, structurally forcing
# release_prefix.sh unreachable -- never an env-var bypass, never a mock --
# through a real, on-disk directory layout: `_fc_default_item_prefix()`
# derives release_prefix.sh's path PURELY from
# `${BASH_SOURCE[0]}/../../release_prefix.sh` (two levels up from
# dispatch_stamp.sh's own containing directory, mirroring this real repo's
# constitution/scripts/fastcycle/tokens/ -> constitution/scripts/ layout),
# so placing a copy of the tool at the SAME relative depth under a
# scratch root that deliberately has NO release_prefix.sh at that ancestor
# level makes the lookup genuinely, structurally fail.
#
# T048 RESTART ROUND-1 REWRITE (§11.4.276(D), review class "tests that never
# run the real artifact"): the earlier version of this file cut a line
# range out of dispatch_stamp.sh with awk and ran the cut-out functions in a
# generated wrapper. That is text extraction of the guarded logic, not the
# real tool. This version copies dispatch_stamp.sh BYTE-FOR-BYTE (checked
# with cmp) into a scratch tree at the same depth, with no
# release_prefix.sh two levels up, and runs the copy exactly as the hook
# does: JSON on stdin, GUARD mode and --extract-item-id mode. The fallback
# prefix is observed through behaviour only: an 'item=WIT-42' tag is
# accepted and extracted, and an 'item=ATM-42' tag (the removed hardcoded
# literal) is refused.
#
# Paths are resolved from this file's own location, never from a fixed
# number of levels above it, so the test also runs in a standalone
# constitution clone (T048 restart R4-I2 class: no project-layout literal).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DS="$HERE/dispatch_stamp.sh"
RP_REAL="$HERE/../../release_prefix.sh"

fail=0
failx() { fail=1; }
ok_line()  { echo "  ok    $1"; }
bad_line() { echo "  FAIL  $1"; failx; }

TMP="$(mktemp -d)" || { echo "  FAIL  mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# Ambient overrides would bypass the fallback this file exists to exercise
# (round-5 minor m5); HELIX_RELEASE_PREFIX is irrelevant once release_prefix.sh
# is absent, but is unset too so no environment value can reach the copy.
unset FC_DISPATCH_ITEM_ID_RE FC_DISPATCH_EXTRA_ITEM_PREFIXES HELIX_RELEASE_PREFIX HELIX_PROJECT_ROOT 2>/dev/null || true

echo "=== control needle: the real dispatch_stamp.sh and release_prefix.sh resolve ==="
if [ -f "$DS" ]; then ok_line "$DS resolves"; else bad_line "$DS not found"; exit 1; fi
if [ -f "$RP_REAL" ] && [ -n "$(bash "$RP_REAL" 2>/dev/null)" ]; then
  ok_line "$RP_REAL resolves and prints a non-empty base -- in normal use the WIT fallback is unreachable, which is why this file forces it"
else
  bad_line "$RP_REAL is missing or prints nothing -- the baseline this test contrasts against cannot be confirmed"
fi

SCRATCH_TOKENS="$TMP/unreachable/constitution/scripts/fastcycle/tokens"
mkdir -p "$SCRATCH_TOKENS"
cp "$DS" "$SCRATCH_TOKENS/dispatch_stamp.sh"
COPY="$SCRATCH_TOKENS/dispatch_stamp.sh"

echo
echo "=== control needles: byte-identical copy, release_prefix.sh genuinely absent ==="
if cmp -s "$DS" "$COPY"; then ok_line "the scratch copy is byte-identical to the real dispatch_stamp.sh"; else bad_line "the scratch copy differs from the real file"; fi
if [ ! -e "$TMP/unreachable/constitution/scripts/release_prefix.sh" ]; then
  ok_line "no release_prefix.sh exists at the path the copy resolves (self_dir/../../release_prefix.sh)"
else
  bad_line "a release_prefix.sh unexpectedly exists in the scratch tree"
fi

# run_copy <mode-arg-or-empty> <payload> -> prints "<stdout>|<exit>"
run_copy() {
  local mode="$1" payload="$2" out rc
  if [ -n "$mode" ]; then
    out="$(cd "$TMP" && printf '%s' "$payload" | bash "$COPY" "$mode" 2>/dev/null)"; rc=$?
  else
    out="$(cd "$TMP" && printf '%s' "$payload" | bash "$COPY" 2>/dev/null)"; rc=$?
  fi
  printf '%s|%s' "$out" "$rc"
}
WIT_PAYLOAD='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=WIT-42 fallback prefix"}}'
ATM_PAYLOAD='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-42 removed literal"}}'

echo
echo "=== (R4-I2) the real tool, release_prefix.sh unreachable: neutral WIT fallback ==="
GOT="$(run_copy --extract-item-id "$WIT_PAYLOAD")"
if [ "$GOT" = "WIT-42|0" ]; then ok_line "--extract-item-id on item=WIT-42 -> 'WIT-42', exit 0"; else bad_line "--extract-item-id on item=WIT-42 gave '$GOT' (want 'WIT-42|0')"; fi
GOT="$(run_copy "" "$WIT_PAYLOAD")"
if [ "$GOT" = "|0" ]; then ok_line "GUARD allows item=WIT-42 (exit 0)"; else bad_line "GUARD on item=WIT-42 gave '$GOT' (want '|0')"; fi
GOT="$(run_copy --extract-item-id "$ATM_PAYLOAD")"
if [ "$GOT" = "|0" ]; then ok_line "--extract-item-id on item=ATM-42 -> empty (the old hardcoded 'ATM' fallback is gone)"; else bad_line "--extract-item-id on item=ATM-42 gave '$GOT' (want '|0') -- a project literal fallback has returned"; fi
GOT="$(run_copy "" "$ATM_PAYLOAD")"
if [ "$GOT" = "|2" ]; then ok_line "GUARD blocks item=ATM-42 (exit 2)"; else bad_line "GUARD on item=ATM-42 gave '$GOT' (want '|2')"; fi

echo
echo "=== (V1-M3, T048 restart round 2) the fallback is announced in GUARD mode, silent in EXTRACTION mode ==="
# run_copy_err <copy> <mode-arg-or-empty> <payload> -> prints the stderr only
run_copy_err() {
  local copy="$1" mode="$2" payload="$3"
  if [ -n "$mode" ]; then
    (cd "$TMP" && { printf '%s' "$payload" | bash "$copy" "$mode" >/dev/null; } 2>&1)
  else
    (cd "$TMP" && { printf '%s' "$payload" | bash "$copy" >/dev/null; } 2>&1)
  fi
}
ERR="$(run_copy_err "$COPY" "" "$WIT_PAYLOAD")"
if printf '%s' "$ERR" | grep -q "NOTICE: release_prefix.sh not found" && printf '%s' "$ERR" | grep -Fq "prefix for this run is 'WIT'"; then
  ok_line "GUARD mode (allowed dispatch) prints the fallback notice naming the missing script and 'WIT'"
else
  bad_line "GUARD mode printed no fallback notice (stderr: '$ERR')"
fi
ERR="$(run_copy_err "$COPY" "" "$ATM_PAYLOAD")"
if printf '%s' "$ERR" | grep -q "NOTICE: release_prefix.sh not found" && printf '%s' "$ERR" | grep -Fq 'item=<WIT-nnnn>'; then
  ok_line "GUARD mode (blocked dispatch) prints the notice and a refusal naming the resolved item=<WIT-nnnn>"
else
  bad_line "GUARD-mode block: stderr '$ERR' lacks the notice or item=<WIT-nnnn>"
fi
ERR="$(run_copy_err "$COPY" --extract-item-id "$WIT_PAYLOAD")"
if [ -z "$ERR" ]; then ok_line "EXTRACTION mode stays silent on stderr (contract: stdout is the id, no other output)"; else bad_line "EXTRACTION mode wrote to stderr: '$ERR'"; fi
# A release_prefix.sh that exists but exits non-zero with no output.
FAILING="$TMP/failing/constitution/scripts"
mkdir -p "$FAILING/fastcycle/tokens"
cp "$DS" "$FAILING/fastcycle/tokens/dispatch_stamp.sh"
printf '#!/usr/bin/env bash\nexit 3\n' > "$FAILING/release_prefix.sh"
ERR="$(run_copy_err "$FAILING/fastcycle/tokens/dispatch_stamp.sh" "" "$WIT_PAYLOAD")"
if printf '%s' "$ERR" | grep -q "NOTICE: release_prefix.sh (.*) exited 3"; then
  ok_line "GUARD mode names a release_prefix.sh that exited 3"
else
  bad_line "GUARD mode with a failing release_prefix.sh printed '$ERR' (want a notice naming exit 3)"
fi
ERR="$(run_copy_err "$FAILING/fastcycle/tokens/dispatch_stamp.sh" --extract-item-id "$WIT_PAYLOAD")"
if [ -z "$ERR" ]; then ok_line "EXTRACTION mode stays silent with a failing release_prefix.sh"; else bad_line "EXTRACTION mode wrote to stderr: '$ERR'"; fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R4-I2 REGRESSION GUARD: ALL CHECKS PASS (real tool, byte-identical copy, release_prefix.sh unreachable) ==="
else
  echo "=== R4-I2 REGRESSION GUARD: FAILURES ABOVE -- see FAIL lines. ==="
fi
exit "$fail"
