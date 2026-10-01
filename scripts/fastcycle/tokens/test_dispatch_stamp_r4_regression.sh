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
# so placing an extracted copy of the relevant functions at the SAME
# relative depth under a scratch root that deliberately has NO
# release_prefix.sh at that ancestor level makes the lookup genuinely,
# structurally fail -- the exact "a scratch copy of the relevant
# script/PATH setup without it present" scenario the task's own
# instructions name.
#
# Extraction discipline (§11.4.6/§11.4.115(F)): the payload is pulled LIVE
# out of dispatch_stamp.sh via a content-anchored `awk` line range
# (`_fc_derive_key_prefix()`'s own preceding "F13 fix" comment line through
# the unique MODE-2 header comment immediately after `extract_item()`'s own
# closing brace) -- never hand-simulated/copy-pasted logic. A control
# needle fails loudly if a future structural edit removes either anchor.
#
# The assertion runs the extracted logic end-to-end through the REAL
# `extract_item()` function (the same function dispatch_stamp.sh's own
# GUARD and --extract-item-id modes both call), proving the fallback
# genuinely produces a usable `WIT-<n>`-prefixed id match in this specific
# unreachable-release-prefix scenario -- not merely that the 3-letter
# prefix string itself is "WIT".
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
DS="$FC/tokens/dispatch_stamp.sh"

fail=0
failx() { fail=1; }

TMP="$(mktemp -d)" || { echo "  FAIL  mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# T048 round-5 minor m5: this file's own fixture depends on
# _fc_default_item_prefix()'s WIT fallback actually running, but if the
# CALLER's real shell environment happens to export either of the two vars
# extract_item() consults FIRST (FC_DISPATCH_ITEM_ID_RE / its companion
# FC_DISPATCH_EXTRA_ITEM_PREFIXES), those take precedence over the fallback
# and this test can false-FAIL (reproduced: exporting
# FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' before running this file gives rc=1).
# Never let an ambient copy leak into a fixture that does not intend to set
# it -- this file's own scenarios below export neither.
unset FC_DISPATCH_ITEM_ID_RE FC_DISPATCH_EXTRA_ITEM_PREFIXES 2>/dev/null || true

echo "=== control needle: source file resolves ==="
if [ -f "$DS" ]; then
  echo "  ok    $DS resolves"
else
  echo "  FAIL  $DS not found"
  failx
fi

# --- control needle: confirm the un-forced, real host environment DOES ---
#     resolve release_prefix.sh today (this is exactly what makes the WIT
#     branch otherwise unreachable, per R4-I2's own finding) -- so this
#     test's later "genuinely unreachable" claim is contrasted against a
#     verified "genuinely reachable" baseline, not an assumption.
RP_REAL="$FC/../release_prefix.sh"
RP_REAL_RESOLVED="$(cd "$(dirname "$RP_REAL")" 2>/dev/null && pwd)/$(basename "$RP_REAL")"
echo
echo "=== control needle: real release_prefix.sh resolves under a normal PATH (baseline the WIT fallback is unreachable against) ==="
if [ -f "$RP_REAL_RESOLVED" ]; then
  REAL_BASE="$(bash "$RP_REAL_RESOLVED" 2>/dev/null || true)"
  if [ -n "$REAL_BASE" ]; then
    echo "  ok    $RP_REAL_RESOLVED resolves and prints a non-empty base ('$REAL_BASE') --"
    echo "        confirming the WIT fallback branch is genuinely unreachable in normal"
    echo "        use today, exactly as R4-I2 found"
  else
    echo "  FAIL  $RP_REAL_RESOLVED resolved but printed nothing -- cannot confirm the"
    echo "        baseline this test's own scratch scenario is contrasted against"
    failx
  fi
else
  echo "  FAIL  $RP_REAL_RESOLVED not found -- cannot confirm the baseline this test's"
  echo "        own scratch scenario is contrasted against"
  failx
fi

# --- extract the fallback-relevant logic, content-anchored ---
EXTRACT_START='# F13 fix (T048 round-2 review, §11.4.28/§11.4.177): the accepted ticket-id'
EXTRACT_END="# MODE 2: --extract-item-id (ALWAYS exit 0; stdout is the id / '?' / empty,"
PAYLOAD="$TMP/payload.sh"

echo
echo "=== control needle: extraction anchors found + unique in $DS ==="
START_HITS="$(grep -cxF "$EXTRACT_START" "$DS" 2>/dev/null || true)"; : "${START_HITS:=0}"
END_HITS="$(grep -cxF "$EXTRACT_END" "$DS" 2>/dev/null || true)"; : "${END_HITS:=0}"
if [ "$START_HITS" != 1 ] || [ "$END_HITS" != 1 ]; then
  echo "  FAIL  extraction anchors not exactly-once (start=$START_HITS, end=$END_HITS) --"
  echo "        $DS's structure changed; this file's anchors need updating"
  failx
  PAYLOAD=""
else
  awk -v s="$EXTRACT_START" -v e="$EXTRACT_END" '$0==s,$0==e' "$DS" > "$PAYLOAD" 2>/dev/null
  if [ -s "$PAYLOAD" ] \
     && grep -qF '_fc_derive_key_prefix() {' "$PAYLOAD" \
     && grep -qF '_fc_default_item_prefix() {' "$PAYLOAD" \
     && grep -qF 'extract_item() {' "$PAYLOAD"; then
    echo "  ok    extraction produced $(wc -l < "$PAYLOAD" | tr -d ' ') lines containing all 3"
    echo "        expected functions (_fc_derive_key_prefix, _fc_default_item_prefix,"
    echo "        extract_item)"
  else
    echo "  FAIL  extraction from $DS is incomplete -- the file's structure changed;"
    echo "        this file's anchors need updating"
    failx
    PAYLOAD=""
  fi
fi

if [ -z "${PAYLOAD:-}" ]; then
  echo
  echo "=== R4-I2 REGRESSION GUARD: SKIPPED -- extraction control needle failed above ==="
  exit 1
fi

# --- build the scratch layout: a nested tree mirroring this real repo's ---
#     constitution/scripts/fastcycle/tokens/ (dispatch_stamp.sh's own
#     containing dir) depth under constitution/scripts/ (where
#     release_prefix.sh normally lives), WITH NO release_prefix.sh
#     anywhere in it -- a real, on-disk absence, never a mock/env
#     override.
SCRATCH_TOKENS_DIR="$TMP/unreachable_scenario/constitution/scripts/fastcycle/tokens"
mkdir -p "$SCRATCH_TOKENS_DIR"
SCRATCH_SCRIPT="$SCRATCH_TOKENS_DIR/dispatch_stamp_extract.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set -u'
  cat "$PAYLOAD"
  # NOTE: the extracted payload's own top-level `if [ -n
  # "${FC_DISPATCH_ITEM_ID_RE:-}" ]; then ... else ... fi` block (verbatim
  # from the real source, included in this extraction range) already
  # calls _fc_default_item_prefix() and sets ITEM_ALL_PREFIXES/
  # ITEM_VALUE_RE/ITEM_RE as global vars AT PAYLOAD-LOAD TIME, exactly as
  # the real dispatch_stamp.sh does at its own top level -- so
  # extract_item() below is called with ITEM_RE already correctly
  # reflecting this scratch scenario's own resolved fallback, never
  # hand-recomputed here.
  echo 'printf "PREFIX=%s\n" "$(_fc_default_item_prefix)"'
  echo 'printf "EXTRACTED=%s\n" "$(extract_item "some dispatch text item=WIT-42 trailing")"'
} > "$SCRATCH_SCRIPT"
chmod +x "$SCRATCH_SCRIPT"

echo
echo "=== control needle: the scratch scenario's own release_prefix.sh ancestor path is genuinely absent ==="
SCRATCH_RP_EXPECT="$TMP/unreachable_scenario/constitution/scripts/release_prefix.sh"
if [ ! -e "$SCRATCH_RP_EXPECT" ]; then
  echo "  ok    $SCRATCH_RP_EXPECT genuinely does not exist on disk -- this is a real"
  echo "        filesystem absence, not a mocked/overridden lookup"
else
  echo "  FAIL  $SCRATCH_RP_EXPECT unexpectedly exists -- this scratch fixture's own"
  echo "        setup is broken (the control needle this whole file depends on)"
  failx
fi

echo
echo "=== (R4-I2) real (fixed) _fc_default_item_prefix(): forced-unreachable release_prefix.sh correctly produces the neutral WIT fallback ==="
SCRATCH_OUT="$TMP/scratch.out"
SCRATCH_ERR="$TMP/scratch.err"
"$SCRATCH_SCRIPT" >"$SCRATCH_OUT" 2>"$SCRATCH_ERR"
SCRATCH_RC=$?
GOT_PREFIX="$(sed -n 's/^PREFIX=//p' "$SCRATCH_OUT")"
GOT_EXTRACTED="$(sed -n 's/^EXTRACTED=//p' "$SCRATCH_OUT")"
if [ "$SCRATCH_RC" != 0 ]; then
  echo "  FAIL  scratch script exited $SCRATCH_RC (wanted 0) -- $(cat "$SCRATCH_ERR" 2>/dev/null)"
  failx
elif [ "$GOT_PREFIX" != "WIT" ]; then
  echo "  FAIL  _fc_default_item_prefix() returned '$GOT_PREFIX' (wanted 'WIT') when"
  echo "        release_prefix.sh was genuinely unreachable -- $(cat "$SCRATCH_ERR" 2>/dev/null)"
  failx
else
  echo "  ok    _fc_default_item_prefix() correctly returned the neutral 'WIT' prefix"
  echo "        (never the removed project-specific 'ATM' literal, never a crash/empty"
  echo "        value) when release_prefix.sh was genuinely, structurally unreachable"
fi
if [ "$GOT_EXTRACTED" = "WIT-42" ]; then
  echo "  ok    the SAME fallback, driven end-to-end through the REAL extract_item()"
  echo "        function dispatch_stamp.sh's own GUARD and --extract-item-id modes both"
  echo "        call, correctly extracts a genuine 'WIT-42'-prefixed id from"
  echo "        'item=WIT-42' -- the fallback is not merely a 3-letter string, it is a"
  echo "        genuinely usable item-id prefix in this specific scenario"
else
  echo "  FAIL  extract_item() returned '$GOT_EXTRACTED' (wanted 'WIT-42') -- the WIT"
  echo "        fallback prefix did not produce a usable item-id match"
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R4-I2 REGRESSION GUARD: ALL CHECKS PASS -- with release_prefix.sh forced"
  echo "    genuinely, structurally unreachable, the real (fixed) _fc_default_item_prefix()"
  echo "    correctly falls back to the neutral 'WIT' prefix and that fallback produces a"
  echo "    genuinely usable 'WIT-<n>' item-id match through the real extract_item()"
  echo "    logic -- this test genuinely distinguishes the R3-M1 fix from its absence,"
  echo "    unlike Section G's by-design bypass. ==="
else
  echo "=== R4-I2 REGRESSION GUARD: FAILURES ABOVE -- see FAIL lines. ==="
fi

exit "$fail"
