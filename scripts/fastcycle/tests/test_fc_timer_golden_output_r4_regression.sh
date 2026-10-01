#!/bin/bash
# T048 round-4 finding R4-I4 + round-5 finding R5-I3 regression guard for
# test_fc_timer_golden_output.sh's noise-floor classifier (rewritten in
# round 6; the round-4/5 version of this file extracted only the PAIRING block
# up to the "# verdict-line shape" anchor, so nothing it ran ever reached the
# classifier -- which is exactly why the round-5 reviewer's mutation M5
# survived it).
#
# R4-I4: the golden test compared two unrelated captures days apart. Round 6
#   removed pairing altogether (see test_fc_timer_golden_output_r5_regression.sh
#   for the "never compared" cases). What remains of R4-I4 here is its noise-
#   floor half: a mismatch is classified against the SAME triplet's own
#   FC0a-vs-FC0b diff.
# R5-I3: the classifier only read removed lines ('^< '). A verdict line that
#   exists ONLY in the with-timers log ('^> ') was never counted -- the strict
#   verdict FAILed but the classifier said "0 ... and 0", a S11.4.201(6)
#   false-null on exactly the timer-induced-addition case.
#
# Every case runs the REAL harness + REAL golden test end to end
# (lib/golden_triplet_fixture.sh), parsing the golden test's machine-readable
# line:  NOISE-FLOOR: changed=N noise_explained=N not_explained=N
#
# Cases:
#  (C1) reviewer's own R5-I3 repro: FC1 = FC0a + one appended WARN line, FC0b
#       identical to FC0a -> changed=1 noise_explained=0 not_explained=1.
#  (C2) the same added line also appears in FC0b -> it is noise:
#       changed=1 noise_explained=1 not_explained=0.
#  (C3) a REMOVED line that FC0b also lacks -> noise; a removed line FC0b
#       keeps -> not explained: changed=2 noise_explained=1 not_explained=1.
#  (C4) a line removed in FC1 but ADDED in FC0b is not the same direction ->
#       not explained (direction matters).
#  (C5) the classifier never changes the strict verdict: every case exits 1.
# Mutations (each applied to a copy of the real golden test, case re-run):
#  (M5)  the round-5 reviewer's own M5, verbatim intent: invert the
#        classifier's `grep -qxF` test -> (C1) and (C2) flip.
#  (M-R5I3) drop the added-line classification call (the pre-R5-I3 shape) ->
#        (C1) reports not_explained=0.
#  (M-dir) compare against the WRONG-direction noise file -> (C4) flips.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/golden_triplet_fixture.sh
. "$HERE/lib/golden_triplet_fixture.sh"
REAL_GOLDEN="$GT_GOLDEN"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "NOT ok $1"; fail=1; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
gt_init "$TMP/work"

BASE='  ✓ CM-ONE: first
  ✗ CM-TWO: second
WARN: CM-THREE: third'

# triplet NAME FC0a-text FC0b-text FC1-text -- real harness capture + promotion
triplet() {
  local fix="$TMP/fix_$1" out="$TMP/ev_$1"
  printf '%s\n' "$2" | gt_member_text "$fix" FC0a
  printf '%s\n' "$3" | gt_member_text "$fix" FC0b
  printf '%s\n' "$4" | gt_member_text "$fix" FC1
  gt_capture "$fix" "$out" t 20261001T120000Z || { bad "($1) harness failed: $(tail -n 3 "$out/.capture.log")"; return 1; }
  gt_promote "$out/t_20261001T120000Z.triplet"
}
# classify NAME OUTFILE -- runs the golden test, prints its NOISE-FLOOR line
classify() {
  gt_golden "$2" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_$1"
  echo "rc=$?"
  grep -m1 '^NOISE-FLOOR:' "$2" | sed 's/ (noise floor.*//'
}
expect() {  # NAME OUTFILE WANT(e.g. "changed=1 noise_explained=0 not_explained=1")
  local got; got="$(classify "$1" "$2" | tr '\n' ' ')"
  case "$got" in
    "rc=1 NOISE-FLOOR: $3 ") ok "($1) $3, strict verdict still FAIL (rc=1)" ;;
    *) bad "($1) want 'rc=1 NOISE-FLOOR: $3', got '$got'" ;;
  esac
}

for f in "$GT_HARNESS" "$REAL_GOLDEN"; do
  [ -f "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done

ADDED='WARN: CM-NEW: only with timers'
echo "=== (C1) R5-I3 reviewer repro: one appended WARN line on the with-timers side only ==="
triplet C1 "$BASE" "$BASE" "$BASE
$ADDED" && expect C1 "$TMP/c1.out" "changed=1 noise_explained=0 not_explained=1"

echo "=== (C2) the same added line also appears between the two timer-free members -> noise ==="
triplet C2 "$BASE" "$BASE
$ADDED" "$BASE
$ADDED" && expect C2 "$TMP/c2.out" "changed=1 noise_explained=1 not_explained=0"

echo "=== (C3) removed lines: one also missing from FC0b (noise), one present in FC0b (not explained) ==="
triplet C3 "$BASE" '  ✓ CM-ONE: first
WARN: CM-THREE: third' 'WARN: CM-THREE: third' && expect C3 "$TMP/c3.out" "changed=2 noise_explained=1 not_explained=1"

echo "=== (C4) direction matters: removed in FC1, added in FC0b, is NOT noise ==="
triplet C4 "$BASE" "$BASE
  ✓ CM-ONE: first" '  ✗ CM-TWO: second
WARN: CM-THREE: third' && expect C4 "$TMP/c4.out" "changed=1 noise_explained=0 not_explained=1"

# mutate NAME ANCHOR REPLACEMENT -- copy of the real golden test, anchor exactly once
mutate() {
  local hits; hits="$(grep -cF -- "$2" "$REAL_GOLDEN" || true)"
  if [ "$hits" != 1 ]; then bad "($1) control needle: anchor found $hits times (want 1): $2"; return 1; fi
  ANCHOR="$2" REPL="$3" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); s=s.replace(os.environ["ANCHOR"],os.environ["REPL"],1); open(sys.argv[2],"w").write(s)
' "$REAL_GOLDEN" "$TMP/golden_$1.sh"
}
# expect_flip MUT CASE WANT-UNDER-REAL -- the mutant must NOT reproduce WANT
expect_flip() {
  local got; got="$(GT_GOLDEN="$TMP/golden_$1.sh" classify "$2" "$TMP/$1_$2.out" | tr '\n' ' ')"
  if [ "$got" != "rc=1 NOISE-FLOOR: $3 " ]; then
    ok "($1) mutant flips ($2): got '$got' instead of '$3' -- ($2) is load-bearing"
  else
    bad "($1) BLIND: mutant still reports '$3' on ($2)"
  fi
}

echo "=== (M5) round-5 reviewer's M5: invert the classifier's grep -qxF test ==="
if mutate M5 'if grep -qxF -- "$_fc_line" "$2" 2>/dev/null; then' 'if ! grep -qxF -- "$_fc_line" "$2" 2>/dev/null; then'; then
  expect_flip M5 C1 "changed=1 noise_explained=0 not_explained=1"
  expect_flip M5 C2 "changed=1 noise_explained=1 not_explained=0"
fi

echo "=== (M-R5I3) pre-R5-I3 shape: added lines never classified ==="
if mutate R5I3 '    _fc_classify_against "$TMP/real_added.txt" "$TMP/noise_added.txt"' '    :'; then
  expect_flip R5I3 C1 "changed=1 noise_explained=0 not_explained=1"
fi

echo "=== (M-dir) classify removed lines against the ADDED noise side ==="
if mutate DIR '    _fc_classify_against "$TMP/real_removed.txt" "$TMP/noise_removed.txt"' '    _fc_classify_against "$TMP/real_removed.txt" "$TMP/noise_added.txt"'; then
  expect_flip DIR C4 "changed=1 noise_explained=0 not_explained=1"
fi

echo
if [ "$fail" = 0 ]; then echo "=== R4-I4/R5-I3 CLASSIFIER REGRESSION GUARD: ALL CHECKS PASS ==="; else echo "=== R4-I4/R5-I3 CLASSIFIER REGRESSION GUARD: FAILURES ABOVE ==="; fi
exit "$fail"
