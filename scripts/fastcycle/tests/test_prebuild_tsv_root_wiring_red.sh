#!/bin/bash
# Purpose: T048 Round 8 independent review finding R8-I1 regression guard.
#
# R8-I1 (verbatim finding, 2026-10-02): "CAPTURE_TRIPLET_TSV_ROOT is
# documented by the harness but ignored by the real pre_build. ...
# capture_fc_timer_triplet.sh:62/97/172 documents the variable and passes it
# to the member. The real pre_build_verification.sh:135 hard-codes
# export FC_TIMER_TSV=... . grep CAPTURE_TRIPLET_TSV_ROOT in pre_build and
# fc_timer.sh returns 0 hits. So any real capture with a non-default TSV
# root records FC1.tsv_rows=0 and is rejected. ... The stand-in fixture
# *does* honor the variable, so all 15 harness tests pass while the real
# producer violates the contract they exercise (the stand-in != real
# divergence class, S11.4.27)."
#
# The fix (same round): pre_build_verification.sh's FC_TIMER_TSV export now
# reads "${CAPTURE_TRIPLET_TSV_ROOT:-${ANDROID_ROOT}/qa-results/fastcycle}"
# instead of the hard-coded root, preserving every existing caller's
# default behaviour exactly while finally honouring the variable
# capture_fc_timer_triplet.sh has always documented and passed.
#
# EXTRACTION DISCIPLINE (S11.4.6/S11.4.115(F)): this test exercises the REAL,
# UNMODIFIED fc_timer-wiring block of the real producer
# (device/rockchip/rk3588/tests/pre_build_verification.sh) via a
# content-anchored `awk` line-range extraction -- the SAME discipline this
# directory's other round-8 regression guards use -- rather than hand-
# simulating the logic (which is exactly the real-vs-stand-in divergence
# class R8-I1 reports). A control needle fails loudly if a future structural
# edit to pre_build_verification.sh removes either anchor, rather than
# silently testing stale logic that no longer matches what ships. The
# extracted block is driven against the REAL fc_timer.sh (sourced from its
# real, unmoved location in this submodule) with a fixed FC_TIMER_RUN_ID and
# a scratch ANDROID_ROOT, so nothing is written to the live checkout.
#
# Producer != Verifier (S11.4.240): this file is authored as an independent
# regression guard; it does not touch pre_build_verification.sh's own
# implementation.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
PREBUILD="${PREBUILD_SRC:-$ROOT/device/rockchip/rk3588/tests/pre_build_verification.sh}"
REAL_TESTS_DIR="$ROOT/device/rockchip/rk3588/tests"
FC_TIMER_LIB="$ROOT/constitution/scripts/fastcycle/timing/fc_timer.sh"

fail=0
failx() { fail=1; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

echo "=== control needle: source files resolve ==="
if [ -f "$PREBUILD" ]; then
  echo "ok control needle: $PREBUILD resolves"
else
  echo "NOT ok control needle FAILED: $PREBUILD not found"
  failx
fi
if [ -f "$FC_TIMER_LIB" ]; then
  echo "ok control needle: $FC_TIMER_LIB resolves"
else
  echo "NOT ok control needle FAILED: $FC_TIMER_LIB not found"
  failx
fi

# =============================================================================
# Extraction: pre_build_verification.sh's own fc_timer-wiring block -- the
# exact-text anchors below are the start of the `_FC_TIMER_LIB=` declaration
# through the closing `fi` of that `if [ -f "$_FC_TIMER_LIB" ]; then ... fi`
# block (verified unique in the file by the control needle below).
# =============================================================================
FC_START='_FC_TIMER_LIB="${SCRIPT_DIR}/../../../../constitution/scripts/fastcycle/timing/fc_timer.sh"'
FC_END='fi'
PAYLOAD="$TMP/fc_wiring_payload.sh"
awk -v s="$FC_START" -v e="$FC_END" '$0==s,$0==e' "$PREBUILD" > "$PAYLOAD" 2>/dev/null

echo
echo "=== control needle: fc_timer-wiring extraction anchors found + unique ==="
START_HITS="$(grep -cxF "$FC_START" "$PREBUILD" 2>/dev/null || true)"; : "${START_HITS:=0}"
if [ "$START_HITS" != 1 ]; then
  echo "NOT ok control needle FAILED: anchor '$FC_START' appears $START_HITS"
  echo "     time(s) in $PREBUILD (expected exactly 1) -- extraction is no"
  echo "     longer reliably anchored; this file's anchors need updating"
  failx
  PAYLOAD=""
elif [ ! -s "$PAYLOAD" ] || ! grep -qF 'export FC_TIMER_TSV=' "$PAYLOAD"; then
  echo "NOT ok control needle FAILED: extraction from $PREBUILD produced no"
  echo "     content (or content missing the expected FC_TIMER_TSV export) --"
  echo "     the file's structure changed; this assertion's anchors need"
  echo "     updating"
  failx
  PAYLOAD=""
else
  echo "ok control needle: fc_timer-wiring payload extracted ($(wc -l < "$PAYLOAD" | tr -d ' ') lines)"
fi

# _run_wiring ANDROID_ROOT_DIR RUN_ID [CAPTURE_TRIPLET_TSV_ROOT_VALUE] --
# drives the extracted payload (real, unless overridden) and prints
# FC_TIMER_TSV=<value>. Never writes anything (the wiring block itself only
# computes + exports a variable; nothing in it does mkdir/write).
_run_wiring() {
  local payload="$1" aroot="$2" runid="$3" tsvroot="${4:-}"
  local driver="$TMP/driver_$$_$RANDOM.sh"
  {
    echo 'set -u'
    printf 'SCRIPT_DIR=%q\n' "$REAL_TESTS_DIR"
    printf 'ANDROID_ROOT=%q\n' "$aroot"
    printf 'FC_TIMER_RUN_ID=%q\n' "$runid"
    if [ -n "$tsvroot" ]; then
      printf 'CAPTURE_TRIPLET_TSV_ROOT=%q\n' "$tsvroot"
    fi
    echo 'TESTS_PASSED=0; ERRORS=0; WARNINGS=0'
    cat "$payload"
    echo 'printf "FC_TIMER_TSV=%s\n" "${FC_TIMER_TSV:-UNSET}"'
  } > "$driver"
  bash "$driver" 2>"$TMP/driver.err"
}

ARoot="$TMP/android_root"
RunID="r8i1_test_run_id"

echo
echo "=== (1) real (fixed) wiring: default -- no CAPTURE_TRIPLET_TSV_ROOT set -- preserves the exact prior default root ==="
if [ -n "$PAYLOAD" ]; then
  OUT1="$(_run_wiring "$PAYLOAD" "$ARoot" "$RunID")"
  TSV1="$(printf '%s\n' "$OUT1" | sed -n 's/^FC_TIMER_TSV=//p')"
  WANT1="$ARoot/qa-results/fastcycle/$RunID/prebuild_sections.tsv"
  if [ "$TSV1" = "$WANT1" ]; then
    echo "ok (1) default (no CAPTURE_TRIPLET_TSV_ROOT): FC_TIMER_TSV=$TSV1 --"
    echo "   the exact prior default is preserved for every caller that does"
    echo "   not set the variable"
  else
    echo "NOT ok (1) got FC_TIMER_TSV='$TSV1' (wanted '$WANT1') --"
    echo "     $(cat "$TMP/driver.err" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok (1) SKIPPED: extraction control needle above already failed"
  failx
fi

echo
echo "=== (2) real (fixed) wiring: CAPTURE_TRIPLET_TSV_ROOT set -- the TSV lands under the caller-chosen root, not the hard-coded default ==="
TsvRoot="$TMP/custom_tsv_root"
if [ -n "$PAYLOAD" ]; then
  OUT2="$(_run_wiring "$PAYLOAD" "$ARoot" "$RunID" "$TsvRoot")"
  TSV2="$(printf '%s\n' "$OUT2" | sed -n 's/^FC_TIMER_TSV=//p')"
  WANT2="$TsvRoot/$RunID/prebuild_sections.tsv"
  if [ "$TSV2" = "$WANT2" ]; then
    echo "ok (2) CAPTURE_TRIPLET_TSV_ROOT=$TsvRoot honoured: FC_TIMER_TSV=$TSV2"
  else
    echo "NOT ok (2) got FC_TIMER_TSV='$TSV2' (wanted '$WANT2') -- the real"
    echo "     producer still ignores CAPTURE_TRIPLET_TSV_ROOT --"
    echo "     $(cat "$TMP/driver.err" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok (2) SKIPPED: extraction control needle above already failed"
  failx
fi

# =============================================================================
# Guard-viability: revert the extracted payload to the pre-fix, hard-coded
# form (R8-I1's own reported line, reproduced verbatim) and confirm the SAME
# test (2) above WRONGLY ignores CAPTURE_TRIPLET_TSV_ROOT on it -- proving
# this fixture genuinely distinguishes the fixed wiring from the reported
# defect, not merely something that happens to print the right path.
# =============================================================================
echo
echo "=== (3) guard-viability: the pre-fix hard-coded form WRONGLY ignores CAPTURE_TRIPLET_TSV_ROOT on the SAME fixture ==="
FIXED_EXPORT_LINE='    export FC_TIMER_TSV="${CAPTURE_TRIPLET_TSV_ROOT:-${ANDROID_ROOT}/qa-results/fastcycle}/$(fc_timer_run_id)/prebuild_sections.tsv"'
OLD_EXPORT_LINE='    export FC_TIMER_TSV="${ANDROID_ROOT}/qa-results/fastcycle/$(fc_timer_run_id)/prebuild_sections.tsv"'
PAYLOAD_MUT=""
if [ -n "$PAYLOAD" ]; then
  FIXED_HITS="$(grep -cxF "$FIXED_EXPORT_LINE" "$PAYLOAD" 2>/dev/null || true)"; : "${FIXED_HITS:=0}"
  if [ "$FIXED_HITS" != 1 ]; then
    echo "NOT ok (3) control needle FAILED: anchor '$FIXED_EXPORT_LINE' appears"
    echo "     $FIXED_HITS time(s) in the extracted payload (expected exactly 1) --"
    echo "     the fixed export line's own exact form changed; this assertion's"
    echo "     anchor needs updating"
    failx
  else
    PAYLOAD_MUT="$TMP/fc_wiring_payload_prefix_mutated.sh"
    awk -v f="$FIXED_EXPORT_LINE" -v o="$OLD_EXPORT_LINE" '{ if ($0==f) print o; else print }' "$PAYLOAD" > "$PAYLOAD_MUT"
    echo "ok (3) control needle: located + reverted the fixed export line to"
    echo "   R8-I1's own exact pre-fix hard-coded form"
  fi
fi
if [ -n "$PAYLOAD_MUT" ]; then
  OUT3="$(_run_wiring "$PAYLOAD_MUT" "$ARoot" "$RunID" "$TsvRoot")"
  TSV3="$(printf '%s\n' "$OUT3" | sed -n 's/^FC_TIMER_TSV=//p')"
  WANT3_BAD="$ARoot/qa-results/fastcycle/$RunID/prebuild_sections.tsv"
  if [ "$TSV3" = "$WANT3_BAD" ]; then
    echo "ok (3) the reverted (pre-fix) wiring WRONGLY produced the hard-coded"
    echo "   default root ($TSV3) even with CAPTURE_TRIPLET_TSV_ROOT set to"
    echo "   '$TsvRoot' -- reproducing R8-I1's exact reported defect end-to-end"
    echo "   on this fixture, proving the fix this test exercises is genuinely"
    echo "   load-bearing"
  else
    echo "NOT ok (3) BLIND: reverted wiring produced '$TSV3' (wanted the"
    echo "     hard-coded default '$WANT3_BAD', proving the mutation's own wrong"
    echo "     effect) -- $(cat "$TMP/driver.err" 2>/dev/null); either the"
    echo "     mutation is malformed or this fixture does not genuinely"
    echo "     distinguish the fixed and pre-fix forms"
    failx
  fi
else
  echo "NOT ok (3) SKIPPED: could not construct the pre-fix mutation above"
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R8-I1 REGRESSION GUARD: ALL CHECKS PASS -- the real (fixed)"
  echo "    pre_build_verification.sh fc_timer-wiring block preserves its"
  echo "    exact prior default when CAPTURE_TRIPLET_TSV_ROOT is unset, and"
  echo "    genuinely honours it when set, closing the real-vs-stand-in"
  echo "    divergence R8-I1 reported; the pre-fix hard-coded form is proven"
  echo "    load-bearing-distinguishable via a reviewer-style revert mutation. ==="
else
  echo "=== R8-I1 REGRESSION GUARD: FAILURES ABOVE -- see NOT ok lines. ==="
fi

exit "$fail"
