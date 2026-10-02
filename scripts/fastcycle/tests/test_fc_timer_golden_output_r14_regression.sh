#!/bin/bash
# T048 round-14 independent review findings regression guard for
# test_fc_timer_golden_output.sh (round-15 remediation).
#
# R14-I1 (Important, verbatim finding): round 13's exit-code elif
# (_fc_registry_flip_ids()) answered "does ANY registered gate's own
# recorded line genuinely differ between these two exact members" -- but
# never checked that the registered flip(s) actually ACCOUNT FOR the full
# $ERRORS delta, in magnitude OR direction. The round-14 reviewer's own
# ADV1 fixture (a member carrying BOTH the registered flake AND a genuine,
# unrelated OK/FAIL-style regression) produced a false overall PASS: ANY
# registered-line difference, of ANY magnitude in EITHER direction,
# unconditionally explained away the whole exit-code divergence.
#
# R14-I2 (Important, pre-existing, surfaced by this review): VERDICT_RE
# never matched the ~640-per-real-run "<GATE-ID>: ... OK" / "... FAIL[:]"
# direct-ERRORS-increment lines, nor the real "WARNING:" text log_warn()
# prints (the old pattern's "WARN:" literal never occurs in the shipped
# script). FR-002/T-A01's "verdict set is IDENTICAL" claim silently excluded
# both shapes from the comparison.
#
# Fix (round 15): (R14-I2) VERDICT_RE now also matches the real OK/FAIL-
# style shape (word-bounded, "... " + OK/FAIL) and "WARNING:". (R14-I1) the
# exit-code elif reads the real "  Failed:       N" summary line from BOTH
# raw members (_fc_failed_count()) and the registered gate(s)' own NET
# failing-class delta (_fc_registry_failcount_delta()), and SKIPs as
# registry-explained ONLY when the two are EXACTLY equal (same sign, same
# magnitude) AND nonzero -- an unresolvable "Failed:" line, or any mismatch,
# falls straight through to the existing hard FAIL.
#
# HOW THIS FILE TESTS: every case runs the REAL harness (with a stand-in
# pre-build, lib/golden_triplet_fixture.sh) and the REAL golden test end to
# end, exactly like the r4/r7/r8/r10/r12 regression files. Mutations are
# applied to a COPY of the real golden test (never the live file) via the
# SAME content-anchored mutate()/mrun() pattern those files use, with the
# exact anchor text extracted at RUN TIME from the real file via `grep -F`
# (never hand-transcribed).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
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
has() { grep -qF -- "$2" "$1"; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
gt_init "$TMP/work"

for f in "$GT_HARNESS" "$REAL_GOLDEN"; do
  # intentional ok/bad control-needle idiom; ok()/bad() are print-only reporters that always return 0, so the || branch never spuriously fires
  # shellcheck disable=SC2015
  [ -f "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done

set_key() { sed -i "s|^$2=.*|$2=$3|" "$1"; }

# triplet NAME SEQ FC0a-text FC0b-text FC1-text -- real harness capture +
# promotion. SEQ is a small distinguishing digit so each case's run_id is
# unique (YYYYMMDDTHHMMSSZ format the manifest format requires).
triplet() {
  local name="$1" fix="$TMP/fix_$1" out="$TMP/ev_$1" runid
  runid="202614$(printf '%02d' "$2")T000000Z"
  printf '%s\n' "$3" | gt_member_text "$fix" FC0a
  printf '%s\n' "$4" | gt_member_text "$fix" FC0b
  printf '%s\n' "$5" | gt_member_text "$fix" FC1
  gt_capture "$fix" "$out" t "$runid" || { bad "($name) harness failed: $(tail -n 3 "$out/.capture.log")"; return 1; }
  gt_promote "$out/t_${runid}.triplet"
  MF="$out/t_${runid}.triplet"
}

# A CLEAN baseline (no pre-existing failure) -- deliberately NOT the older
# regression files' BASE const (which always carries one failing CM-TWO
# line) so each fixture's own "  Failed:       N" value is simple to
# compute by inspection.
CBASE='  ✓ CM-ONE: clean baseline gate'
SPK_OK='  CM-SPK512-BRIDGE-SECLABEL-SHELL: SPK-512 toggle text...   ✓ ok'
SPK_BAD='  CM-SPK512-BRIDGE-SECLABEL-SHELL: SPK-512 toggle text...   ✗ ERROR: broken'
# Real OK/FAIL-style shape (R14-I2): every echo -n check-description prompt
# in the real script ends in "... "; the verdict echo that follows prints
# immediately after with no intervening output, so the captured line is
# "...  OK" / "...  FAIL[:]..." -- NEVER matched by the pre-round-14
# VERDICT_RE. Deliberately a genuinely UNRELATED, unregistered gate id.
OKSTYLE_OK='  CM-OKSTYLE: genuine unrelated OK/FAIL-style gate...   OK'
OKSTYLE_BAD='  CM-OKSTYLE: genuine unrelated OK/FAIL-style gate...   FAIL: genuine regression'
# Real "WARNING:" shape (R14-I2): log_warn() prints "WARNING:", never the
# pre-round-14 pattern's literal "WARN:".
# Gate id deliberately avoids containing the literal substring "WARN:"
# itself (a naming footgun this fixture's first draft fell into: "CM-ADV-
# WARN:" accidentally contained the OLD pattern's "WARN:" literal, making
# the mutation below falsely appear to leave this case unaffected).
WARNSTYLE_FC1_ONLY='  ⚠ WARNING: CM-ADV-FLAGGED: appears only in FC1, never in FC0a/FC0b'
# An unrelated, unregistered ✗ ERROR: gate for the direction-mismatch case.
UNREL_BAD='  CM-ADV2-UNREL: genuinely unrelated new failure...   ✗ ERROR: new regression'
GOK='  ✓ ALL MANDATORY CHECKS PASSED'
GFAIL='  ✗ PRE-BUILD VERIFICATION FAILED'
FAILED0='  Failed:       0'
FAILED1='  Failed:       1'
FAILED2='  Failed:       2'

# =============================================================================
# R14-I1: exact-accounting exit-code explanation.
# =============================================================================
echo "=== (ADV1) R14-I1 exact repro (reviewer's own fixture): a registered flake AND a genuine, unrelated OK/FAIL-style regression BOTH confined to FC1 -- overall FAIL required, not the pre-round-15 false PASS ==="
triplet ADV1 1 "$CBASE
$SPK_OK
$OKSTYLE_OK
$FAILED0
$GOK" "$CBASE
$SPK_OK
$OKSTYLE_OK
$FAILED0
$GOK" "$CBASE
$SPK_BAD
$OKSTYLE_BAD
$FAILED2
$GFAIL"
set_key "$MF" member.FC0a.exit 0; set_key "$MF" member.FC0b.exit 0; set_key "$MF" member.FC1.exit 1
gt_golden "$TMP/adv1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADV1"; ADV1_RC=$?
if [ "$ADV1_RC" = 1 ] \
   && grep -qE '^FAIL\[[0-9]+\]: FR-002 commit result:.*MISMATCH, not explained' "$TMP/adv1.out" \
   && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/adv1.out" \
   && has "$TMP/adv1.out" "CM-OKSTYLE"; then
  ok "(ADV1) overall FAIL (rc=1): the registered flake's delta (1) does NOT fully account for the real Failed:-delta (2), so the exit-code check correctly hard-FAILs, AND the now-visible OK/FAIL-style regression is independently caught by the verdict-set check -- the round-14 false PASS is closed"
else
  bad "(ADV1) BLIND: rc=$ADV1_RC; $(grep -E 'commit result|FR-002/T-A01' "$TMP/adv1.out" | head -5)"
fi

echo "=== (ADV1-ctl) non-regression control: the SAME genuine OK/FAIL-style regression with NO registered flake present at all -- must ALSO FAIL, unaffected by either new mechanism ==="
triplet ADV1ctl 2 "$CBASE
$SPK_OK
$OKSTYLE_OK
$FAILED0
$GOK" "$CBASE
$SPK_OK
$OKSTYLE_OK
$FAILED0
$GOK" "$CBASE
$SPK_OK
$OKSTYLE_BAD
$FAILED1
$GFAIL"
set_key "$MF" member.FC0a.exit 0; set_key "$MF" member.FC0b.exit 0; set_key "$MF" member.FC1.exit 1
gt_golden "$TMP/adv1ctl.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADV1ctl"; ADV1CTL_RC=$?
if [ "$ADV1CTL_RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/adv1ctl.out" && has "$TMP/adv1ctl.out" "CM-OKSTYLE"; then
  ok "(ADV1-ctl) overall FAIL (rc=1): a genuine regression with no registry involvement at all is caught exactly as before -- the S11.4.201(1) false-positive guard"
else
  bad "(ADV1-ctl) BLIND: rc=$ADV1CTL_RC; $(grep -E 'commit result|FR-002/T-A01' "$TMP/adv1ctl.out" | head -5)"
fi

echo "=== (ADV2) R14-I1 direction/magnitude probe (reviewer's own fixture, made internally coherent T048 round 16 R16-M1: FC0a/FC0b now exit 1 to match their own 'Failed: 1' line, never 0): the registered gate SELF-HEALS (FAIL->OK, delta=-1) while an UNRELATED new failure appears in the SAME member (delta=+1) -- net Failed: delta is 0, so NOTHING can explain a genuine exit divergence; must still be overall rejected ==="
triplet ADV2 3 "$CBASE
$SPK_BAD
$FAILED1" "$CBASE
$SPK_BAD
$FAILED1" "$CBASE
$SPK_OK
$UNREL_BAD
$FAILED1"
# T048 round 16 (R16-M1 live finding): the round-15 fixture set ALL THREE
# exits to 0/0/1 even though EVERY member's own "Failed: 1" line requires
# exit 1 (pre_build_verification.sh exits 0 iff Failed==0) -- FC0a and
# FC0b were internally INCONSISTENT. With consistent exits (1/1/1, since
# FC1's own self-heal+new-failure net Failed count is ALSO 1), _ex0 and
# _ex1 are now EQUAL (both 1): the exit-code check [12] correctly PASSES
# trivially (there is no genuine exit DIVERGENCE to explain -- consistent
# with this fixture's own point, since the net Failed: delta really is 0
# and nothing differs at the exit-code level either); the SEPARATE
# verdict-set check [13] is what still catches CM-ADV2-UNREL (the real,
# unrelated new failure) once the known-flaky filter removes the SPK
# lines from both sides, which is what keeps the OVERALL result correctly
# rejected -- re-verified below to still demonstrate this fixture's
# original point (a registered self-heal masking an unrelated new
# failure is correctly rejected), now via the check that actually sees it.
set_key "$MF" member.FC0a.exit 1; set_key "$MF" member.FC0b.exit 1; set_key "$MF" member.FC1.exit 1
gt_golden "$TMP/adv2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADV2"; ADV2_RC=$?
if [ "$ADV2_RC" = 1 ] \
   && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result: with-timers exit status \(1\) equals without-timers exit status \(1\)' "$TMP/adv2.out" \
   && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/adv2.out" \
   && has "$TMP/adv2.out" "CM-ADV2-UNREL"; then
  ok "(ADV2) overall rejected (rc=1): with internally-consistent inputs there is no genuine exit-code divergence left to explain (check [exit] correctly PASSes trivially, exit 1 == exit 1), but the SEPARATE verdict-set check still catches the unrelated new failure (CM-ADV2-UNREL) once the known-flaky filter removes the self-healed SPK lines -- a registered gate's self-heal masking an unrelated new failure is still never treated as making the run clean"
else
  bad "(ADV2) BLIND: rc=$ADV2_RC; $(grep -E 'commit result|FR-002/T-A01' "$TMP/adv2.out" | head -5)"
fi

mutate() {
  local name="$1" anchor="$2" repl="$3" hits
  hits="$(grep -cF -- "$anchor" "$REAL_GOLDEN" || true)"
  if [ "$hits" != 1 ]; then bad "($name) control needle: anchor found $hits times (want 1): $anchor"; return 1; fi
  ANCHOR="$anchor" REPL="$repl" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); s=s.replace(os.environ["ANCHOR"],os.environ["REPL"],1); open(sys.argv[2],"w").write(s)
' "$REAL_GOLDEN" "$TMP/golden_$name.sh"
}
# mrun NAME ENVASSIGNS OUTFILE -- ENVASSIGNS is a word-split (deliberately
# unquoted, internally-controlled, space-separated VAR=VAL ... list, never
# attacker-controlled) so more than one env var can be passed through.
# Routing through the library's own gt_golden() FUNCTION (never a bare
# `GT_GOLDEN=... env ... bash "$GT_GOLDEN"` one-liner, which measurably does
# NOT apply the override -- see r12_regression.sh's own mrun() comment for
# the full explanation) is what actually works.
# intentional word-splitting -- $envassigns is a caller-supplied multi-assignment prefix string (e.g. 'A=1 B=2') that MUST split into separate env assignments, quoting it would break that
# shellcheck disable=SC2086
mrun() { local name="$1" envassigns="$2" outfile="$3"; GT_GOLDEN="$TMP/golden_$name.sh" gt_golden "$outfile" $envassigns; }

echo "=== (M-I1-delta) guard-viability: drop the exact-accounting delta check, reverting to round-13's any-registered-line-differs heuristic -- (ADV1) must reproduce the round-14 false PASS ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
ANCHOR_I1='  elif [ "$_FC_EXIT_EXPLAINED" = 1 ]; then'
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
REPL_I1='  elif [ -n "$_FC_EXIT_FLIP_IDS" ]; then  # MUTANT: R14-I1 exact-accounting dropped, reverted to any-flip-suffices'
if mutate I1delta "$ANCHOR_I1" "$REPL_I1"; then
  mrun I1delta "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_ADV1 FC_TIMER_GOLDEN_ROOT=$ROOT FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=$HERE/known_flaky_gates.tsv" "$TMP/mi1delta.out"
  MI1D_RC=$?
  # (ADV1) ALSO carries a genuine, unrelated OK/FAIL-style regression that
  # the SEPARATE, I2-fixed verdict-set check (check [13]) catches
  # independently of this mutation -- exactly the round-12 "not a blanket
  # loophole" design (A2mix) this round's fix preserves. So the OVERALL rc
  # does NOT flip back to 0 even when the exit-code elif alone is reverted
  # to the vulnerable any-flip-suffices form; the mutation's load-bearing
  # effect is checked at the SPECIFIC check [12] level instead -- it must
  # WRONGLY become a SKIP (registry-"explained") rather than the correct
  # hard FAIL.
  if [ "$MI1D_RC" = 1 ] && grep -qE '^SKIP\[[0-9]+\]: FR-002 commit result' "$TMP/mi1delta.out"; then
    ok "(M-I1-delta) without the exact-accounting delta check, check [exit] on (ADV1) WRONGLY flips to SKIP (registry-'explained') even though the real Failed:-delta (2) does not match the registered gate's own delta (1) -- the delta check is genuinely load-bearing (overall rc stays 1 only because the SEPARATE, I2-fixed verdict-set check independently catches the same regression, confirming this is the SAME non-blanket-loophole design as A2mix, not a coincidence hiding a blind mutation)"
  else
    bad "(M-I1-delta) BLIND: rc=$MI1D_RC; $(grep -E 'commit result|FR-002/T-A01' "$TMP/mi1delta.out" | head -5)"
  fi
else
  bad "(M-I1-delta) could not construct the mutation (anchor not found)"
fi

# =============================================================================
# R14-I2: OK/FAIL-style + WARNING: verdict-set blind spot.
# =============================================================================
echo "=== (ADV3) R14-I2 exact repro: an OK/FAIL-style gate flips OK->FAIL in FC1 only, exit codes held EQUAL (isolating the verdict-SET check from the exit-code check) -- check [verdict-set] must FAIL, not silently PASS ==="
triplet ADV3 4 "$CBASE
$OKSTYLE_OK" "$CBASE
$OKSTYLE_OK" "$CBASE
$OKSTYLE_BAD"
set_key "$MF" member.FC0a.exit 0; set_key "$MF" member.FC0b.exit 0; set_key "$MF" member.FC1.exit 0
gt_golden "$TMP/adv3.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADV3"; ADV3_RC=$?
if [ "$ADV3_RC" = 1 ] \
   && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result:' "$TMP/adv3.out" \
   && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/adv3.out" \
   && has "$TMP/adv3.out" "CM-OKSTYLE"; then
  ok "(ADV3) overall FAIL (rc=1): with exit codes held equal, the exit-code check correctly PASSes trivially, but the verdict-set check now SEES the OK->FAIL flip and correctly hard-FAILs -- the pre-round-15 OK/FAIL blind spot is closed"
else
  bad "(ADV3) BLIND: rc=$ADV3_RC; $(grep -E 'commit result|FR-002/T-A01' "$TMP/adv3.out" | head -5)"
fi

echo "=== (ADV4) R14-I2 WARNING: shape: a log_warn()-style line appears ONLY in FC1, exit codes held EQUAL -- check [verdict-set] must FAIL, not silently PASS ==="
triplet ADV4 5 "$CBASE" "$CBASE" "$CBASE
$WARNSTYLE_FC1_ONLY"
set_key "$MF" member.FC0a.exit 0; set_key "$MF" member.FC0b.exit 0; set_key "$MF" member.FC1.exit 0
gt_golden "$TMP/adv4.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADV4"; ADV4_RC=$?
if [ "$ADV4_RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/adv4.out" && has "$TMP/adv4.out" "CM-ADV-FLAGGED"; then
  ok "(ADV4) overall FAIL (rc=1): a WARNING:-only difference (never matched by the pre-round-15 literal 'WARN:') is now genuinely caught by the verdict-set check"
else
  bad "(ADV4) BLIND: rc=$ADV4_RC; $(grep -E 'FR-002/T-A01' "$TMP/adv4.out" | head -5)"
fi

echo "=== (M-I2-verdictre) guard-viability: revert VERDICT_RE to the pre-round-15 pattern -- BOTH (ADV3) and (ADV4) must WRONGLY flip to overall PASS ==="
# Fetched at RUN TIME from the real file (never hand-transcribed, S11.4.6)
# -- the real line's own UTF-8 checkmark/cross bytes are fragile to
# hand-type correctly; grep -E '^VERDICT_RE=' isolates the exact,
# currently-shipped line regardless of how its regex body is spelled.
ANCHOR_I2="$(grep -E '^VERDICT_RE=' "$REAL_GOLDEN")"
REPL_I2="VERDICT_RE='(✓|✗|WARN:|ERROR:)'  # MUTANT: R14-I2 OK/FAIL-style + WARNING: coverage dropped"
if [ -n "$ANCHOR_I2" ] && mutate I2verdictre "$ANCHOR_I2" "$REPL_I2"; then
  mrun I2verdictre "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_ADV3" "$TMP/mi2v_adv3.out"
  MI2V3_RC=$?
  mrun I2verdictre "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_ADV4" "$TMP/mi2v_adv4.out"
  MI2V4_RC=$?
  if [ "$MI2V3_RC" = 0 ] && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01' "$TMP/mi2v_adv3.out" \
     && [ "$MI2V4_RC" = 0 ] && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01' "$TMP/mi2v_adv4.out"; then
    ok "(M-I2-verdictre) without the extended VERDICT_RE, BOTH (ADV3)'s OK/FAIL flip AND (ADV4)'s WARNING: line WRONGLY become invisible again (rc=0 PASS on both) -- the extension is genuinely load-bearing for both shapes"
  else
    bad "(M-I2-verdictre) BLIND: adv3_rc=$MI2V3_RC adv4_rc=$MI2V4_RC; $(grep -E 'FR-002/T-A01' "$TMP/mi2v_adv3.out" "$TMP/mi2v_adv4.out" | head -5)"
  fi
else
  bad "(M-I2-verdictre) could not construct the mutation (anchor not found)"
fi

echo
if [ "$fail" = 0 ]; then echo "=== T048 ROUND-14 FINDINGS REGRESSION GUARD (R14-I1/I2): ALL CHECKS PASS ==="; else echo "=== T048 ROUND-14 FINDINGS REGRESSION GUARD (R14-I1/I2): FAILURES ABOVE ==="; fi
exit "$fail"
