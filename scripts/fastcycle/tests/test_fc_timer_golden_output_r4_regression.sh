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
#       changed=1 noise_explained=1 not_explained=0 -- T048 round 8 (R8-B1):
#       fully noise-explained (not_explained=0) is now an honest SKIP
#       (rc=0), never a FAIL; see expect_skip() below.
#  (C3) a REMOVED line that FC0b also lacks -> noise; a removed line FC0b
#       keeps -> not explained: changed=2 noise_explained=1 not_explained=1.
#  (C4) a line removed in FC1 but ADDED in FC0b is not the same direction ->
#       not explained (direction matters).
#  (C5) the classifier never changes the strict verdict for a case with any
#       UNEXPLAINED line: C1/C3/C4 still exit 1 (FAIL); C2 (fully explained,
#       not_explained=0) exits 0 (SKIP, round 8 R8-B1 -- see expect_skip()).
# Mutations (each applied to a copy of the real golden test, case re-run):
#  (M5)  the round-5 reviewer's own M5, verbatim intent: invert the
#        classifier's `grep -qxF` test -> (C1) and (C2) flip.
#  (M-R5I3) drop the added-line classification call (the pre-R5-I3 shape) ->
#        (C1) reports not_explained=0.
#  (M-dir) compare against the WRONG-direction noise file -> (C4) flips.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/golden_triplet_fixture.sh
# (not a shellcheck directive -- plain comment) precheck's shellcheck invocation runs
# without -x; this harness sources its sibling lib file via a runtime-computed $HERE
# path shellcheck cannot statically follow without -x regardless of the source= line
# shellcheck disable=SC1091
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
# expect_skip NAME OUTFILE WANT -- T048 round 8 (R8-B1): a mismatch FULLY
# explained by this run's own FC0a-vs-FC0b noise floor (not_explained=0) is
# now an honest SKIP (rc=0), never the unconditional FAIL (rc=1) every case
# here asserted before round 8 -- see test_fc_timer_golden_output.sh's own
# R8-B1 comment for the full rationale (a flaky, fc_timer-unrelated
# parent-repo gate flipping in exactly one timers-OFF member made the
# verifier FAIL a real fraction of genuinely-GREEN runs; a FAIL on a
# deviation proven, by this SAME run's own noise floor, to occur even with
# timers OFF was testing something other than FR-002/T-A01's own claim).
expect_skip() {  # NAME OUTFILE WANT(e.g. "changed=1 noise_explained=1 not_explained=0") [PRECOMPUTED_RC]
  # T048 round 12 (R12-M1): an OPTIONAL 4th argument lets a caller holding
  # an ALREADY-PRODUCED (rc, outfile) pair it did NOT just obtain from
  # classify() -- e.g. the M-SKIP2PASS mutant's own already-captured run,
  # below -- feed it through this SAME check without classify() launching
  # a SECOND, fresh golden-test run (classify() always re-runs $GT_GOLDEN
  # against $TMP/ev_$1, so pointing it at an unrelated NAME with no such
  # evidence dir -- the bug this very parameter replaces -- produces a
  # DIFFERENT run's result, not the fed-in one, and silently mismatches via
  # the catch-all `*)` branch below for a reason having nothing to do with
  # the fed-in content's own kind marker). With no 4th argument the
  # behaviour is BYTE-IDENTICAL to before this round (classify() still
  # does the one real run); existing callers (C2) are unaffected.
  local got kind
  if [ $# -ge 4 ]; then
    got="rc=$4 $(grep -m1 '^NOISE-FLOOR:' "$2" | sed 's/ (noise floor.*//') "
  else
    got="$(classify "$1" "$2" | tr '\n' ' ')"
  fi
  # T048 round 11 (R10-I2, verbatim finding): rc=0 plus a matching
  # NOISE-FLOOR line does NOT distinguish a genuine SKIP from a mutant that
  # silently turns the SKIP branch into an unconditional `chk ... "1"`
  # (false PASS) -- both give rc=0 AND print the IDENTICAL NOISE-FLOOR
  # line, since that line is computed and echoed BEFORE the pass/skip/fail
  # decision. The reviewer's own mutant (M-SKIP2PASS below) survived every
  # round-4/5/7/8 suite under the OLD version of this function, which
  # checked only those two things. The FR-002/T-A01 verdict line's own
  # PASS[.../SKIP[.../FAIL[... marker is the only thing that tells a real
  # SKIP apart from a false PASS, so it is now checked explicitly.
  kind="$(grep -oE '^(PASS|FAIL|SKIP)\[[0-9]+\]: FR-002/T-A01' "$2" | sed -E 's/^(PASS|FAIL|SKIP)\[.*/\1/' | head -n1)"
  case "$got" in
    "rc=0 NOISE-FLOOR: $3 ")
      if [ "$kind" = SKIP ]; then
        ok "($1) $3, fully noise-explained -> SKIP not FAIL (rc=0, R8-B1), FR-002/T-A01 line's own marker is genuinely SKIP[ (R10-I2)"
      else
        bad "($1) rc=0 and NOISE-FLOOR matches, but the FR-002/T-A01 line's own marker is '$kind', not SKIP -- a PASS here would silently overclaim fc_timer causes zero change from one noisy sample (R10-I2)"
      fi
      ;;
    *) bad "($1) want 'rc=0 NOISE-FLOOR: $3', got '$got'" ;;
  esac
}

for f in "$GT_HARNESS" "$REAL_GOLDEN"; do
  # intentional ok/bad control-needle idiom; ok()/bad() are print-only reporters that always return 0, so the || branch never spuriously fires
  # shellcheck disable=SC2015
  [ -f "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done

ADDED='WARN: CM-NEW: only with timers'
echo "=== (C1) R5-I3 reviewer repro: one appended WARN line on the with-timers side only ==="
triplet C1 "$BASE" "$BASE" "$BASE
$ADDED" && expect C1 "$TMP/c1.out" "changed=1 noise_explained=0 not_explained=1"

echo "=== (C2) the same added line also appears between the two timer-free members -> noise ==="
triplet C2 "$BASE" "$BASE
$ADDED" "$BASE
$ADDED" && expect_skip C2 "$TMP/c2.out" "changed=1 noise_explained=1 not_explained=0"

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
# (anchor updated in round 7: R6-M4 replaced the per-line grep -qxF set
# match with a multiset awk match; the mutation still inverts the match test.)
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
if mutate M5 '{ if (n[$0] > 0) { n[$0]--; e++ } else u++ }' '{ if (!(n[$0] > 0)) { e++ } else u++ }'; then
  expect_flip M5 C1 "changed=1 noise_explained=0 not_explained=1"
  expect_flip M5 C2 "changed=1 noise_explained=1 not_explained=0"
fi

echo "=== (M-R5I3) pre-R5-I3 shape: added lines never classified ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
if mutate R5I3 '    _fc_classify_against "$TMP/real_added.txt" "$TMP/noise_added.txt"' '    :'; then
  expect_flip R5I3 C1 "changed=1 noise_explained=0 not_explained=1"
fi

echo "=== (M-dir) classify removed lines against the ADDED noise side ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
if mutate DIR '    _fc_classify_against "$TMP/real_removed.txt" "$TMP/noise_removed.txt"' '    _fc_classify_against "$TMP/real_removed.txt" "$TMP/noise_added.txt"'; then
  expect_flip DIR C4 "changed=1 noise_explained=0 not_explained=1"
fi

echo "=== (M-SKIP2PASS) R10-I2: the reviewer's own mutant -- force the C2 SKIP branch into an unconditional PASS ==="
# Extracted at RUN TIME from the real file (never hand-transcribed) so this
# anchor cannot silently desynchronise from the real source's exact wording.
SKIP2PASS_ANCHOR="$(grep -F 'skip "FR-002/T-A01: with-timers verdict set differs from the without-timers verdict set' "$REAL_GOLDEN")"
if [ -n "$SKIP2PASS_ANCHOR" ] \
   && mutate SKIP2PASS "$SKIP2PASS_ANCHOR" '      chk "FR-002/T-A01: MUTANT forced PASS instead of honest SKIP" "1"'; then
  MUT_OUT="$TMP/mut_skip2pass_c2.out"
  GT_GOLDEN="$TMP/golden_SKIP2PASS.sh" gt_golden "$MUT_OUT" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_C2"
  MUT_RC=$?
  MUT_KIND="$(grep -oE '^(PASS|FAIL|SKIP)\[[0-9]+\]: FR-002/T-A01' "$MUT_OUT" | sed -E 's/^(PASS|FAIL|SKIP)\[.*/\1/' | head -n1)"
  if [ "$MUT_RC" = 0 ] && [ "$MUT_KIND" = PASS ]; then
    ok "(M-SKIP2PASS) mutant reports rc=0 with the FR-002/T-A01 marker=PASS, not SKIP -- the SAME rc and the SAME NOISE-FLOOR line as a genuine SKIP, which is exactly why the OLD (rc+NOISE-FLOOR-only) expect_skip() could not have caught this: the kind-check strengthening above is genuinely load-bearing"
  else
    bad "(M-SKIP2PASS) BLIND: mutant rc=$MUT_RC kind=$MUT_KIND (expected rc=0 kind=PASS to prove the pre-round-11 check was blind to this mutation)"
  fi
  # T048 round 12 (R12-M1): the two checks above only assert the MUTANT's
  # own raw rc+marker shape -- neither of them actually FEEDS that output
  # through THIS FILE's own expect_skip() (the round-11, R10-I2 kind-check
  # strengthening this whole case exists to protect), so a LATER regression
  # of expect_skip()'s kind-check back to its pre-round-11 (rc+NOISE-FLOOR-
  # only) form would leave every OTHER call in this file green (every other
  # call's genuine kind really IS SKIP) and go completely undetected here --
  # measured, not assumed: before the 4th-argument fix above, neutering
  # expect_skip()'s own kind check back to its pre-round-11 form left THIS
  # exact call still reporting "ok" (it never reached the real check at
  # all -- classify() silently re-ran the golden test against a
  # nonexistent evidence dir instead of reading $MUT_OUT, a SEPARATE bug
  # this fix's 4th-argument parameter also closes). Run in a SUBSHELL so a
  # correctly-detected (expected) "NOT ok" from expect_skip() itself never
  # pollutes this file's own $fail -- what this meta-assertion requires is
  # that expect_skip() itself flags the mutant, not that nothing flags it.
  SELFGUARD_OUT="$( expect_skip SKIP2PASS_SELFGUARD "$MUT_OUT" "changed=1 noise_explained=1 not_explained=0" "$MUT_RC" )"
  if printf '%s\n' "$SELFGUARD_OUT" | grep -q '^NOT ok'; then
    ok "(M-SKIP2PASS self-guard, R12-M1) expect_skip() itself, fed the SAME mutant output, genuinely reports NOT ok -- the kind-check strengthening is exercised against exactly the mutation it was added to catch, closing the round-12 tautology finding (the two checks above alone never called expect_skip() at all)"
  else
    bad "(M-SKIP2PASS self-guard, R12-M1) BLIND: expect_skip() itself was fooled by the mutant (reported '$SELFGUARD_OUT' instead of NOT ok) -- the kind-check it should be exercising is not load-bearing here"
  fi
else
  bad "(M-SKIP2PASS) could not construct the mutation (anchor not found)"
fi

echo
if [ "$fail" = 0 ]; then echo "=== R4-I4/R5-I3 CLASSIFIER REGRESSION GUARD: ALL CHECKS PASS ==="; else echo "=== R4-I4/R5-I3 CLASSIFIER REGRESSION GUARD: FAILURES ABOVE ==="; fi
exit "$fail"
