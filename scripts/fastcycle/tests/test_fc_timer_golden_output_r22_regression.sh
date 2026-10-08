#!/bin/bash
# T048 round-22 independent review finding R22-I1 regression guard for
# test_fc_timer_golden_output.sh section (d) -- the strict 3-rule
# FC0a/FC0b/FC1 comparison landed in round 21 (S11.4.250 heuristic-tower
# removal). Round 22's independent review found this rule had NO dedicated
# test or mutation guard: the reviewer wrote four mutations (MA: always
# treat the noise floor as clean; MB: drop the exit-code half of the twin
# comparison; MC: turn the twin-disagreement SKIP into a PASS; MD: drop the
# verdict-set half of the twin comparison), each making the golden test
# wrongly report PASS on a fixture the real file correctly SKIPs, and each
# survived the WHOLE existing battery (r5/r7/r8/r10/r14) with 0 NOT ok.
#
# This file closes that gap: six fixtures exercising every branch of the
# round-21 3-rule comparison -- identified by its ANCHOR TEXT,
# "if [ "$TRIPLET_STATE" = valid ]" through its closing "fi", never by a
# hand-maintained line-number range [T048 round-23 review N1 + round-24
# review M1: TWO successive hand-typed line-range citations in this SAME
# comment ("lines ~693-751", then "lines 708-757") each drifted the very
# next time an UNRELATED comment edit shifted lines earlier in the file
# (round-22's own edits, then round-23's OWN M2 fix four lines above this
# one) -- a hand-counted line number in a comment is exactly the kind of
# derived fact this project's own §11.4.6 no-guessing/never-hand-retyped
# discipline exists to replace with something that cannot silently go
# stale. This comment no longer cites a line range at all: the block's
# real boundaries are located the SAME way this file's own mutate()/
# mrun() pattern already locates every other anchor below -- via
# `grep -F` against the real file's content at RUN TIME, never a number
# typed here], each
# asserting the exact SKIP/PASS/FAIL marker on the FR-002 line, paired with
# MA-MD as PERMANENT mutations (guard-viability: each mutation must make the
# golden test wrongly flip to a different marker on its adversarial
# fixture). A fifth control mutation (ME) inverts the exit-equality check
# on a KNOWN-PASS fixture -- "flips the PASS branch to FAIL" -- to rule out
# a blind harness: if mutate()/mrun() were silently running the REAL
# (unmutated) file instead of the mutated copy, ME's fixture would still
# report the correct PASS, not the expected wrong FAIL.
#
# HOW THIS FILE TESTS: every case runs the REAL harness (with a stand-in
# pre-build, lib/golden_triplet_fixture.sh) and the REAL golden test end to
# end, exactly like the r5/r7/r8/r10/r14 regression files. Mutations are
# applied to a COPY of the real golden test (never the live file) via the
# SAME content-anchored mutate()/mrun() pattern those files use, with the
# exact anchor text extracted at RUN TIME from the real file via `grep -F`
# (never hand-transcribed).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# (not a shellcheck directive -- plain comment) precheck's shellcheck invocation runs
# without -x; this harness sources its sibling lib file via a runtime-computed $HERE
# path shellcheck cannot statically follow without -x regardless of the source= line
# shellcheck disable=SC1091
# shellcheck source=lib/golden_triplet_fixture.sh
. "$HERE/lib/golden_triplet_fixture.sh"
REAL_GOLDEN="$GT_GOLDEN"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "NOT ok $1"; fail=1; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
gt_init "$TMP/work"

for f in "$GT_HARNESS" "$REAL_GOLDEN"; do
  # intentional ok/bad control-needle idiom; ok()/bad() are print-only reporters that always return 0, so the || branch never spuriously fires
  # shellcheck disable=SC2015
  [ -f "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done

# triplet NAME SEQ FC0a-text FC0b-text FC1-text EXITS -- real harness capture
# + promotion. SEQ is a small distinguishing digit so each case's run_id is
# unique (YYYYMMDDTHHMMSSZ format the manifest format requires). EXITS is
# "E0a E0b E1", each member's REAL stand-in exit code (default 1 if omitted).
triplet() {
  local name="$1" fix="$TMP/fix_$1" out="$TMP/ev_$1" runid
  runid="202622$(printf '%02d' "$2")T000000Z"
  printf '%s\n' "$3" | gt_member_text "$fix" FC0a
  printf '%s\n' "$4" | gt_member_text "$fix" FC0b
  printf '%s\n' "$5" | gt_member_text "$fix" FC1
  if [ -n "${6:-}" ]; then
    # shellcheck disable=SC2086
    set -- "$1" "$2" "$3" "$4" "$5" $6
    gt_member_exit "$fix" FC0a "$6"; gt_member_exit "$fix" FC0b "$7"; gt_member_exit "$fix" FC1 "$8"
  fi
  gt_capture "$fix" "$out" t "$runid" || { bad "($name) harness failed: $(tail -n 3 "$out/.capture.log")"; return 1; }
  gt_promote "$out/t_${runid}.triplet"
}

mutate() {
  local name="$1" anchor="$2" repl="$3" hits
  hits="$(grep -cF -- "$anchor" "$REAL_GOLDEN" || true)"
  if [ "$hits" != 1 ]; then bad "($name) control needle: anchor found $hits times (want 1): $anchor"; return 1; fi
  ANCHOR="$anchor" REPL="$repl" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); s=s.replace(os.environ["ANCHOR"],os.environ["REPL"],1); open(sys.argv[2],"w").write(s)
' "$REAL_GOLDEN" "$TMP/golden_$name.sh"
}
# intentional word-splitting -- $envassigns is a caller-supplied multi-assignment prefix string (e.g. 'A=1 B=2') that MUST split into separate env assignments, quoting it would break that
# shellcheck disable=SC2086
mrun() { local name="$1" envassigns="$2" outfile="$3"; GT_GOLDEN="$TMP/golden_$name.sh" gt_golden "$outfile" $envassigns; }

# -----------------------------------------------------------------------
# Fixture dataset (all use the real VERDICT_RE's checkmark bullet, the
# same CBASE idiom r14_regression.sh established).
# -----------------------------------------------------------------------
CBASE='  ✓ CM-ONE: clean baseline gate'
CEXTRA='  ✓ CM-TWO: an extra passing gate only on one side'
C6A='  ✓ CM-SIX-A: baseline gate A'
C6B='  ✓ CM-SIX-B: baseline gate B'

echo "=== building the six fixtures (real harness capture + promotion, one per case) ==="
triplet CASE1 1 "$CBASE" "$CBASE
$CEXTRA" "$CBASE" "0 0 0"
# CASE2 isolates the EXIT channel: an explicit identical "Failed: 0" line in every member keeps
# the summary-counter channel (T048 restart R2-B1) equal while FC0b alone exits 1.
CF0='  Failed:       0'
triplet CASE2 2 "$CBASE
$CF0" "$CBASE
$CF0" "$CBASE
$CF0" "0 1 0"
triplet CASE3 3 "$CBASE" "$CBASE" "$CBASE" "0 0 0"
triplet CASE4 4 "$CBASE" "$CBASE" "$CBASE
$CEXTRA" "0 0 0"
triplet CASE5 5 "$CBASE" "$CBASE" "$CBASE" "0 0 1"
triplet CASE6 6 "$C6A
$C6B" "$C6A
$C6B" "$C6A
$C6B" "0 0 0"

# =========================================================================
# PART 1 -- the REAL (unmutated) golden test on each of the six fixtures.
# This IS the dedicated suite R22-I1 asked for: the SKIP/PASS/FAIL marker
# on the FR-002 line is asserted exactly, for every branch of the round-21
# 3-rule comparison.
# =========================================================================

echo "=== (CASE1) twins (FC0a/FC0b) differ in VERDICT SET, same exit codes; FC1 equals one twin (FC0a) -> must SKIP, never silently PASS because FC1 happens to match a twin ==="
gt_golden "$TMP/case1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_CASE1"; CASE1_RC=$?
if [ "$CASE1_RC" = 0 ] \
   && grep -qE '^SKIP\[[0-9]+\]: FR-002/T-A01: FC0a and FC0b' "$TMP/case1.out" \
   && ! grep -q 'FR-002 commit result' "$TMP/case1.out"; then
  ok "(CASE1) real golden test correctly SKIPs (rc=0, one SKIP marker on the FC0a/FC0b-disagree line, the commit-result/IDENTICAL checks never reached)"
else
  bad "(CASE1) rc=$CASE1_RC; $(grep -E 'FR-002' "$TMP/case1.out" | head -5)"
fi

echo "=== (CASE2) twins differ in EXIT CODE ONLY (verdict sets identical); FC1 equals both twins -> must SKIP ==="
gt_golden "$TMP/case2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_CASE2"; CASE2_RC=$?
if [ "$CASE2_RC" = 0 ] \
   && grep -qE '^SKIP\[[0-9]+\]: FR-002/T-A01: FC0a and FC0b' "$TMP/case2.out" \
   && ! grep -q 'FR-002 commit result' "$TMP/case2.out"; then
  ok "(CASE2) real golden test correctly SKIPs on an exit-code-only twin disagreement"
else
  bad "(CASE2) rc=$CASE2_RC; $(grep -E 'FR-002' "$TMP/case2.out" | head -5)"
fi

echo "=== (CASE3) all three (FC0a/FC0b/FC1) identical, same exit codes -> must PASS both the commit-result and verdict-identical checks ==="
gt_golden "$TMP/case3.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_CASE3"; CASE3_RC=$?
if [ "$CASE3_RC" = 0 ] \
   && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result' "$TMP/case3.out" \
   && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01: with-timers verdict set is IDENTICAL' "$TMP/case3.out"; then
  ok "(CASE3) real golden test correctly PASSes the clean all-identical baseline"
else
  bad "(CASE3) rc=$CASE3_RC; $(grep -E 'FR-002' "$TMP/case3.out" | head -5)"
fi

echo "=== (CASE4) twins agree (clean noise floor); FC1 differs in VERDICT SET only, same exit codes -> commit-result PASSes, verdict-identical must FAIL ==="
gt_golden "$TMP/case4.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_CASE4"; CASE4_RC=$?
if [ "$CASE4_RC" = 1 ] \
   && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result' "$TMP/case4.out" \
   && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01: with-timers verdict set is IDENTICAL' "$TMP/case4.out"; then
  ok "(CASE4) real golden test correctly FAILs the verdict-set check while the exit-code check PASSes trivially"
else
  bad "(CASE4) rc=$CASE4_RC; $(grep -E 'FR-002' "$TMP/case4.out" | head -5)"
fi

echo "=== (CASE5) twins agree; FC1 differs in EXIT CODE only, verdict sets all identical -> commit-result must FAIL, verdict-identical PASSes ==="
gt_golden "$TMP/case5.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_CASE5"; CASE5_RC=$?
if [ "$CASE5_RC" = 1 ] \
   && grep -qE '^FAIL\[[0-9]+\]: FR-002 commit result.*MISMATCH' "$TMP/case5.out" \
   && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01: with-timers verdict set is IDENTICAL' "$TMP/case5.out"; then
  ok "(CASE5) real golden test correctly FAILs the exit-code check while the verdict-set check PASSes trivially (isolating the two checks from each other)"
else
  bad "(CASE5) rc=$CASE5_RC; $(grep -E 'FR-002' "$TMP/case5.out" | head -5)"
fi

echo "=== (CASE6) baseline sanity on a SECOND, structurally distinct clean dataset: all three identical -> PASS, AND the twin-disagree SKIP text must never appear ==="
gt_golden "$TMP/case6.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_CASE6"; CASE6_RC=$?
if [ "$CASE6_RC" = 0 ] \
   && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result' "$TMP/case6.out" \
   && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01: with-timers verdict set is IDENTICAL' "$TMP/case6.out" \
   && ! grep -q 'disagree' "$TMP/case6.out"; then
  ok "(CASE6) real golden test PASSes on a second, independent clean dataset, with no spurious twin-disagree SKIP text -- the mechanism generalises beyond CASE3's single example"
else
  bad "(CASE6) rc=$CASE6_RC; $(grep -E 'FR-002|disagree' "$TMP/case6.out" | head -5)"
fi

# =========================================================================
# PART 2 -- guard-viability: MA/MB/MC/MD each wrongly flip a correctly-
# SKIPping fixture to a wrong PASS; ME (control) flips a correctly-PASSing
# fixture to a wrong FAIL, proving the harness is not blind.
# =========================================================================

# The grep -F patterns and replacement literals below are deliberately
# single-quoted so their embedded $TMP/$_ex0/$_exn/$_ex1 tokens stay
# UN-expanded here -- they are verbatim text to be matched against, or
# written into, the TARGET mutated copy of the golden test, never variables
# of THIS script. shellcheck's SC2016 ("expressions don't expand in single
# quotes") is an info-level false-positive for this intentional case.
# shellcheck disable=SC2016
# T048 restart R2-B1: the clean-noise-floor condition gained a third, line-independent half
# (identical summary counters); MB/MD below keep that half so each still isolates ONE half.
ANCHOR_CLEAN="$(grep -F -- 'if cmp -s "$TMP/baseline_1.txt" "$TMP/fc0b.txt" && [ "$_ex0" = "$_exn" ] && [ "$_COUNTERS_EQUAL_0B" = 1 ]; then' "$REAL_GOLDEN")"
ANCHOR_SKIPCALL="$(grep -F -- 'skip "FR-002/T-A01: FC0a and FC0b (both WITHOUT timers' "$REAL_GOLDEN")"
# shellcheck disable=SC2016
ANCHOR_EXITCOND="$(grep -F -- 'if [ "$_ex0" = "$_ex1" ]; then' "$REAL_GOLDEN")"

if [ -z "$ANCHOR_CLEAN" ] || [ -z "$ANCHOR_SKIPCALL" ] || [ -z "$ANCHOR_EXITCOND" ]; then
  bad "(mutation setup) one or more anchors could not be resolved from $REAL_GOLDEN -- ANCHOR_CLEAN='$ANCHOR_CLEAN' ANCHOR_SKIPCALL(len)=${#ANCHOR_SKIPCALL} ANCHOR_EXITCOND='$ANCHOR_EXITCOND'"
else
  REPL_MA='  if true; then  # MUTANT MA (T048 R22-I1): always treat the FC0a/FC0b noise floor as clean, bypassing the real cmp+exit comparison'
  # shellcheck disable=SC2016
  REPL_MB='  if cmp -s "$TMP/baseline_1.txt" "$TMP/fc0b.txt" && [ "$_COUNTERS_EQUAL_0B" = 1 ]; then  # MUTANT MB (T048 R22-I1): drop the exit-code half of the twin comparison'
  # shellcheck disable=SC2016
  REPL_MD='  if [ "$_ex0" = "$_exn" ] && [ "$_COUNTERS_EQUAL_0B" = 1 ]; then  # MUTANT MD (T048 R22-I1): drop the verdict-set half of the twin comparison'
  REPL_MC="$(printf '%s' "$ANCHOR_SKIPCALL" | sed 's/^\( *\)skip /\1chk /')"
  REPL_MC="${REPL_MC} \"1\"  # MUTANT MC (T048 R22-I1): turn the twin-disagreement SKIP into a PASS"
  REPL_ME="$(printf '%s' "$ANCHOR_EXITCOND" | sed 's/= /!= /')"
  REPL_ME="${REPL_ME}  # MUTANT ME (T048 R22-I1 control): invert exit-equality -- flips a genuine PASS into a FAIL to prove mutate()/mrun() genuinely reach the mutated file, never the live one"

  echo "=== (MA) always-clean mutant: CASE1's genuine twin-verdict-set disagreement must WRONGLY become an overall PASS (FC1 equals the stand-in baseline) ==="
  if mutate MA "$ANCHOR_CLEAN" "$REPL_MA"; then
    mrun MA "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_CASE1" "$TMP/ma.out"; MA_RC=$?
    if [ "$MA_RC" = 0 ] \
       && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result' "$TMP/ma.out" \
       && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01: with-timers verdict set is IDENTICAL' "$TMP/ma.out" \
       && ! grep -q 'disagree' "$TMP/ma.out"; then
      ok "(MA) the always-clean mutant wrongly reports overall PASS (rc=0) on CASE1's genuine twin disagreement, with the disagree-SKIP never printed -- MA is load-bearing, closing R22-I1's MA gap"
    else
      bad "(MA) BLIND: rc=$MA_RC; $(grep -E 'FR-002|disagree' "$TMP/ma.out" | head -5)"
    fi
  else
    bad "(MA) could not construct the mutation"
  fi

  echo "=== (MB) drop-exit-check mutant: CASE2's genuine exit-code-only twin disagreement must WRONGLY become an overall PASS ==="
  if mutate MB "$ANCHOR_CLEAN" "$REPL_MB"; then
    mrun MB "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_CASE2" "$TMP/mb.out"; MB_RC=$?
    if [ "$MB_RC" = 0 ] \
       && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result' "$TMP/mb.out" \
       && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01: with-timers verdict set is IDENTICAL' "$TMP/mb.out" \
       && ! grep -q 'disagree' "$TMP/mb.out"; then
      ok "(MB) the drop-exit-check mutant wrongly reports overall PASS (rc=0) on CASE2's genuine exit-code-only twin disagreement -- MB is load-bearing, closing R22-I1's MB gap"
    else
      bad "(MB) BLIND: rc=$MB_RC; $(grep -E 'FR-002|disagree' "$TMP/mb.out" | head -5)"
    fi
  else
    bad "(MB) could not construct the mutation"
  fi

  echo "=== (MC) skip-to-chk mutant: CASE1's genuine disagree-SKIP line itself must WRONGLY become a PASS line (no behavioural change to the clean-vs-dirty detection, only to what the dirty branch reports) ==="
  if mutate MC "$ANCHOR_SKIPCALL" "$REPL_MC"; then
    mrun MC "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_CASE1" "$TMP/mc.out"; MC_RC=$?
    if [ "$MC_RC" = 0 ] \
       && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01: FC0a and FC0b' "$TMP/mc.out" \
       && ! grep -qE '^SKIP\[' "$TMP/mc.out"; then
      ok "(MC) the skip-to-chk mutant wrongly reports the disagree line as PASS (rc=0), with zero SKIP markers anywhere in the run -- MC is load-bearing, closing R22-I1's MC gap"
    else
      bad "(MC) BLIND: rc=$MC_RC; $(grep -E 'FR-002|SKIP' "$TMP/mc.out" | head -5)"
    fi
  else
    bad "(MC) could not construct the mutation"
  fi

  echo "=== (MD) drop-verdict-check mutant: CASE1's genuine twin-verdict-set disagreement must WRONGLY become an overall PASS (exits alone are equal) ==="
  if mutate MD "$ANCHOR_CLEAN" "$REPL_MD"; then
    mrun MD "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_CASE1" "$TMP/md.out"; MD_RC=$?
    if [ "$MD_RC" = 0 ] \
       && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result' "$TMP/md.out" \
       && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01: with-timers verdict set is IDENTICAL' "$TMP/md.out" \
       && ! grep -q 'disagree' "$TMP/md.out"; then
      ok "(MD) the drop-verdict-check mutant wrongly reports overall PASS (rc=0) on CASE1's genuine verdict-set-only twin disagreement -- MD is load-bearing, closing R22-I1's MD gap"
    else
      bad "(MD) BLIND: rc=$MD_RC; $(grep -E 'FR-002|disagree' "$TMP/md.out" | head -5)"
    fi
  else
    bad "(MD) could not construct the mutation"
  fi

  echo "=== (ME) control: invert exit-equality on CASE3's genuinely-clean, genuinely-PASSing fixture -- the commit-result check must WRONGLY flip from PASS to FAIL, proving mutate()/mrun() reach the mutated copy, never the live file ==="
  if mutate ME "$ANCHOR_EXITCOND" "$REPL_ME"; then
    mrun ME "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_CASE3" "$TMP/me.out"; ME_RC=$?
    if [ "$ME_RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002 commit result.*MISMATCH' "$TMP/me.out"; then
      ok "(ME) control mutation genuinely reaches the mutated file: CASE3's real PASS (verified in PART 1 above) is wrongly flipped to FAIL by the inverted condition (rc=1) -- mutate()/mrun() are not blind"
    else
      bad "(ME) BLIND-CONTROL-FAILED: rc=$ME_RC (want 1); $(grep -E 'FR-002' "$TMP/me.out" | head -5) -- if this control does not flip, NEITHER MA-MD's PASS results above nor this file's own PART-1 real-run results can be trusted to have exercised the intended file"
    fi
  else
    bad "(ME) could not construct the control mutation"
  fi
fi

echo
if [ "$fail" = 0 ]; then echo "=== T048 ROUND-22 FINDINGS REGRESSION GUARD (R22-I1): ALL CHECKS PASS ==="; else echo "=== T048 ROUND-22 FINDINGS REGRESSION GUARD (R22-I1): FAILURES ABOVE ==="; fi
exit "$fail"
