#!/bin/bash
# T048 round-18 independent review findings regression guard for
# test_fc_timer_golden_output.sh (round-19 remediation).
#
# R18-I1 (Important, reproduced false PASSes): round 17's member-internal
# consistency check opened with `[ -n "$failed" ] || return 0`, called "the
# conservative-safe default". It was the permissive choice: when a member's
# "Failed: N" line was missing or duplicated (unresolvable), the WHOLE check
# was skipped -- including its exit-in-{0,1} rule -- and the exits-equal
# PASS branch then accepted the member unchecked. The round-18 reviewer
# reproduced four end-to-end false PASSes (rc=0): ADVA (X2's shape with
# FC1's Failed: line removed), ADVB (FC1 prints Failed: 0 twice), ADVG (a
# realistic crash-before-summary: full verdict lines, no Failed: line, no
# banner, exit 1) and ADVC (all three members exit 2 with no Failed: line,
# reported as "exit (2) equals (2)" PASS). Round 19: rule 1 (exit MUST be 0
# or 1) now runs unconditionally, and a NONZERO exit with an unreadable
# Failed: count is its own hard FAIL. Each fixture below must FAIL, and the
# paired (M-I1-permissive) mutant -- which restores exactly the pre-round-19
# early return -- must reproduce each original false PASS.
#
# R18-M1 (Minor): round 17 called the `!= 0` clause of _fc_exit_explained()
# "provably unreachable" end to end. It was reachable: _fc_failed_count()
# accepted counts of any length and bash $((...)) wraps at 64 bits, so
# "Failed: 18446744073709551616" (2^64) is nonzero as a string but 0
# arithmetically (ADVE), and 2^64+1 becomes 1 (ADVF -- which even reached
# rc=0 on UNMUTATED code via a false registry explanation). Round 19 bounds
# the count to 9 significant digits. ADVE's mutants below show the digit
# bound and the `!= 0` clause are EACH independently sufficient end to end
# (and that dropping both reproduces the reviewer's bypass); ADVF's mutant
# shows the digit bound alone closes the unmutated-code false explanation.
#
# HOW THIS FILE TESTS: every case runs the REAL harness (with the stand-in
# pre-build of lib/golden_triplet_fixture.sh) and the REAL golden test end
# to end. Mutations are applied to a COPY of the real golden test, via
# anchors that must each occur exactly once (control needles).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# Honours a caller-supplied FC_TIMER_GOLDEN_ROOT (T048 round 19, R18-I2 --
# see test_fc_timer_golden_output_r12_regression.sh for the full story).
ROOT="${FC_TIMER_GOLDEN_ROOT:-$(cd "$HERE/../../../.." && pwd)}"
# shellcheck disable=SC1091
# shellcheck source=lib/golden_triplet_fixture.sh
. "$HERE/lib/golden_triplet_fixture.sh"
REAL_GOLDEN="$GT_GOLDEN"
KNOWN_FLAKY_TSV_REAL="$HERE/known_flaky_gates.tsv"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "NOT ok $1"; fail=1; }
has() { grep -qF -- "$2" "$1"; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
gt_init "$TMP/work"

for f in "$GT_HARNESS" "$REAL_GOLDEN" "$KNOWN_FLAKY_TSV_REAL"; do
  # shellcheck disable=SC2015
  [ -e "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done
while IFS=$'\t' read -r _gid _reason _doc _exp; do
  [ "$_gid" = gate_id ] && continue
  [ -n "$_gid" ] || continue
  # shellcheck disable=SC2015
  [ -n "$_doc" ] && [ -f "$ROOT/$_doc" ] && ok "control needle: registry row $_gid defect_doc resolves under ROOT=$ROOT" \
    || bad "control needle: registry row $_gid defect_doc '$_doc' does NOT resolve under ROOT=$ROOT -- set FC_TIMER_GOLDEN_ROOT to a tree containing it"
done < "$KNOWN_FLAKY_TSV_REAL"

# triplet NAME SEQ FC0a-text FC0b-text FC1-text "E0a E0b E1" [NOSUMMARY-MEMBERS]
# -- real harness capture + promotion. Exit codes are the stand-in's REAL
# exit codes; members listed in NOSUMMARY-MEMBERS print no automatic
# "Failed: N" line (a crash before the summary block).
triplet() {
  local name="$1" fix="$TMP/fix_$1" out="$TMP/ev_$1" runid m
  runid="202618$(printf '%02d' "$2")T000000Z"
  printf '%s\n' "$3" | gt_member_text "$fix" FC0a
  printf '%s\n' "$4" | gt_member_text "$fix" FC0b
  printf '%s\n' "$5" | gt_member_text "$fix" FC1
  # $6 is ONE word ("E0a E0b E1", deliberately split here); every argument
  # after it names a member with no automatic summary line.
  # shellcheck disable=SC2086
  set -- $6 "${@:7}"
  gt_member_exit "$fix" FC0a "$1"; gt_member_exit "$fix" FC0b "$2"; gt_member_exit "$fix" FC1 "$3"
  shift 3
  for m in "$@"; do gt_member_nosummary "$fix" "$m"; done
  gt_capture "$fix" "$out" t "$runid" || { bad "($name) harness failed: $(tail -n 3 "$out/.capture.log")"; return 1; }
  gt_promote "$out/t_${runid}.triplet"
}

CBASE='  ✓ CM-ONE: clean baseline gate'
SPK_OK='  CM-SPK512-BRIDGE-SECLABEL-SHELL: SPK-512 toggle text...   ✓ ok'
SPK_BAD='  CM-SPK512-BRIDGE-SECLABEL-SHELL: SPK-512 toggle text...   ✗ ERROR: broken'
GOK='  ✓ ALL MANDATORY CHECKS PASSED'
GFAIL='  ✗ PRE-BUILD VERIFICATION FAILED'
FAILED0='  Failed:       0'
FAILED1='  Failed:       1'
F2P64='  Failed:       18446744073709551616'
F2P64P1='  Failed:       18446744073709551617'

# expect_fail_rule NAME OUTFILE RC LABEL REGEX -- real code must hard-FAIL
# (rc=1) with the named consistency rule firing for LABEL.
expect_fail_rule() {
  if [ "$3" = 1 ] && grep -qE "$5" "$2"; then
    ok "($1) overall FAIL (rc=1): member-internal consistency correctly refuses $4"
  else
    bad "($1) BLIND: rc=$3; $(grep -E 'member-internal|commit result' "$2" | head -4)"
  fi
}

UNREAD_RE='^FAIL\[[0-9]+\]: T048 round-19 member-internal consistency \(FC1\): exit code \(1\) is nonzero but the .Failed: N. count is unreadable'

# =============================================================================
# R18-I1 fixtures.
# =============================================================================
echo "=== (ADVA) round-18 reviewer fixture: X2's shape with FC1's Failed: line removed (FC1 clean verdicts + success banner, exit 1; FC0a registered flake, Failed: 1, exit 1) -- overall FAIL required ==="
triplet ADVA 1 "$CBASE
$SPK_BAD
$FAILED1
$GFAIL" "$CBASE
$SPK_OK
$FAILED0
$GOK" "$CBASE
$SPK_OK
$GOK" "1 0 1" FC1
gt_golden "$TMP/adva.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADVA"; RC=$?
expect_fail_rule ADVA "$TMP/adva.out" "$RC" "FC1's nonzero exit with no Failed: line" "$UNREAD_RE"

echo "=== (ADVB) round-18 reviewer fixture: as ADVA, but FC1 prints 'Failed: 0' TWICE (ambiguous, hence unresolvable) -- overall FAIL required ==="
triplet ADVB 2 "$CBASE
$SPK_BAD
$FAILED1
$GFAIL" "$CBASE
$SPK_OK
$FAILED0
$GOK" "$CBASE
$SPK_OK
$FAILED0
$FAILED0
$GOK" "1 0 1"
gt_golden "$TMP/advb.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADVB"; RC=$?
expect_fail_rule ADVB "$TMP/advb.out" "$RC" "FC1's nonzero exit with an ambiguous (duplicated) Failed: line" "$UNREAD_RE"

echo "=== (ADVG) round-18 reviewer fixture: realistic crash-before-summary -- FC1 has its full verdict lines but NO Failed: line and NO banner, exit 1, against FC0a's registered flake (exit 1) -- overall FAIL required ==="
triplet ADVG 3 "$CBASE
$SPK_BAD
$FAILED1
$GFAIL" "$CBASE
$SPK_OK
$FAILED0
$GOK" "$CBASE
$SPK_OK" "1 0 1" FC1
gt_golden "$TMP/advg.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADVG"; RC=$?
expect_fail_rule ADVG "$TMP/advg.out" "$RC" "FC1's crash before the summary block" "$UNREAD_RE"

echo "=== (ADVC) round-18 reviewer fixture: ALL THREE members exit 2 with no Failed: line -- the exits-equal branch used to report 'exit (2) equals (2)' PASS; overall FAIL required ==="
triplet ADVC 4 "$CBASE" "$CBASE" "$CBASE" "2 2 2" FC0a FC0b FC1
gt_golden "$TMP/advc.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADVC"; RC=$?
ADVC_HITS="$(grep -cE '^FAIL\[[0-9]+\]: T048 round-16 member-internal consistency \((FC0a|FC0b|FC1)\): exit code \(2\) is neither 0 nor 1 .*\(Failed: unreadable\)' "$TMP/advc.out" || true)"
if [ "$RC" = 1 ] && [ "$ADVC_HITS" = 3 ]; then
  ok "(ADVC) overall FAIL (rc=1): exit 2 is refused for ALL THREE members by name even though none has a readable Failed: count -- rule 1 is now unconditional"
else
  bad "(ADVC) BLIND: rc=$RC hits=$ADVC_HITS; $(grep -E 'member-internal|commit result' "$TMP/advc.out" | head -4)"
fi

echo "=== (ADVctl) S11.4.201(1) false-positive control: an EXIT-0 member with no Failed: line is NOT failed by the new rule (all three exit 0, no summary at all, identical verdicts) -- overall PASS ==="
triplet ADVctl 5 "$CBASE" "$CBASE" "$CBASE" "0 0 0" FC0a FC0b FC1
gt_golden "$TMP/advctl.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADVctl"; RC=$?
if [ "$RC" = 0 ] && ! has "$TMP/advctl.out" "member-internal consistency"; then
  ok "(ADVctl) overall PASS (rc=0): an unreadable count on an EXIT-0 member is not by itself refused -- the new rule targets only an unexplained NONZERO exit"
else
  bad "(ADVctl) rc=$RC; $(grep -E 'member-internal|commit result' "$TMP/advctl.out" | head -4)"
fi

mutate() {
  local name="$1" anchor="$2" repl="$3" src="${4:-$REAL_GOLDEN}" hits
  hits="$(grep -cF -- "$anchor" "$src" || true)"
  if [ "$hits" != 1 ]; then bad "($name) control needle: anchor found $hits times (want 1): $anchor"; return 1; fi
  ANCHOR="$anchor" REPL="$repl" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); s=s.replace(os.environ["ANCHOR"],os.environ["REPL"],1); open(sys.argv[2],"w").write(s)
' "$src" "$TMP/golden_$name.sh"
}
# shellcheck disable=SC2086
mrun() { local name="$1" envassigns="$2" outfile="$3"; GT_GOLDEN="$TMP/golden_$name.sh" gt_golden "$outfile" $envassigns; }
envfor() { printf 'FC_TIMER_GOLDEN_EVIDENCE_DIR=%s FC_TIMER_GOLDEN_ROOT=%s FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=%s' "$TMP/ev_$1" "$ROOT" "$KNOWN_FLAKY_TSV_REAL"; }

echo "=== (M-I1-permissive) guard-viability: restore the pre-round-19 early return (skip the WHOLE check when Failed: is unresolvable) -- ADVA, ADVB, ADVG and ADVC must each reproduce the round-18 reviewer's false PASS ==="
# shellcheck disable=SC2016
CONS_ANCHOR='    local label="$1" ex="$2" failed="$3"'
# shellcheck disable=SC2016
CONS_PERMISSIVE='    local label="$1" ex="$2" failed="$3"
    [ -n "$failed" ] || return 0  # MUTANT: pre-round-19 permissive early return restored'
if mutate I1P "$CONS_ANCHOR" "$CONS_PERMISSIVE"; then
  for c in ADVA ADVB ADVG ADVC; do
    lc="$(printf '%s' "$c" | tr '[:upper:]' '[:lower:]')"
    mrun I1P "$(envfor "$c")" "$TMP/mi1p_$lc.out"; MRC=$?
    if [ "$MRC" = 0 ] && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result: with-timers exit status \(([12])\) equals without-timers exit status \(\1\)' "$TMP/mi1p_$lc.out"; then
      ok "(M-I1-permissive/$c) with the early return restored, $c WRONGLY passes again (rc=0, trivially-equal exits) -- the round-19 restructure is load-bearing for this fixture"
    else
      bad "(M-I1-permissive/$c) BLIND: rc=$MRC; $(grep -E 'member-internal|commit result' "$TMP/mi1p_$lc.out" | head -3)"
    fi
  done
fi

# =============================================================================
# R18-M1 fixtures: 64-bit wrap of an unbounded Failed: count.
# =============================================================================
echo "=== (ADVE) round-18 reviewer fixture: FC0a/FC0b print 'Failed: 2^64' (exit 1), FC1 'Failed: 0' (exit 0) -- overall FAIL required ==="
triplet ADVE 6 "$CBASE
$F2P64
$GFAIL" "$CBASE
$F2P64
$GFAIL" "$CBASE
$FAILED0
$GOK" "1 1 0"
gt_golden "$TMP/adve.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADVE"; RC=$?
if [ "$RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: T048 round-19 member-internal consistency \(FC0a\): exit code \(1\) is nonzero but the .Failed: N. count is unreadable' "$TMP/adve.out"; then
  ok "(ADVE) overall FAIL (rc=1): a 20-digit Failed: count is unreadable under the round-19 9-digit bound, so the nonzero-exit member is refused before any wrapped arithmetic can run"
else
  bad "(ADVE) BLIND: rc=$RC; $(grep -E 'member-internal|commit result' "$TMP/adve.out" | head -4)"
fi

echo "=== (ADVF) round-18 reviewer fixture: FC0a/FC0b print 'Failed: 2^64+1' with the registered flake FAILING (exit 1), FC1 green (exit 0) -- 2^64+1 wraps to 1, which used to produce a FALSE registry explanation on UNMUTATED code; overall FAIL required ==="
triplet ADVF 7 "$CBASE
$SPK_BAD
$F2P64P1
$GFAIL" "$CBASE
$SPK_BAD
$F2P64P1
$GFAIL" "$CBASE
$SPK_OK
$FAILED0
$GOK" "1 1 0"
gt_golden "$TMP/advf.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_ADVF"; RC=$?
if [ "$RC" = 1 ] && ! has "$TMP/advf.out" "registry-explained" \
   && grep -qE '^FAIL\[[0-9]+\]: T048 round-19 member-internal consistency \(FC0a\): exit code \(1\) is nonzero but the .Failed: N. count is unreadable' "$TMP/advf.out"; then
  ok "(ADVF) overall FAIL (rc=1): the wrapped count never reaches the registry accounting, so it can no longer be explained away"
else
  bad "(ADVF) BLIND: rc=$RC; $(grep -E 'member-internal|commit result' "$TMP/advf.out" | head -4)"
fi

# shellcheck disable=SC2016
CAP_ANCHOR="s/^[[:space:]]*Failed:[[:space:]]+(0*[0-9]{1,9})[[:space:]]*\$/\\1/p"
# shellcheck disable=SC2016
CAP_UNBOUNDED="s/^[[:space:]]*Failed:[[:space:]]+([0-9]+)[[:space:]]*\$/\\1/p"
# shellcheck disable=SC2016
NZ_ANCHOR='  if [ "$delta" != 0 ] && [ "$delta" = "$reg" ]; then printf 1; else printf 0; fi'
# shellcheck disable=SC2016
NZ_DROPPED='  if [ "$delta" = "$reg" ]; then printf 1; else printf 0; fi  # MUTANT: nonzero-delta requirement dropped'

echo "=== (M-M1-cap) guard-viability: remove ONLY the 9-digit bound -- ADVE must STILL FAIL, now via the '!= 0' clause (proving that clause is reachable and load-bearing end to end) ==="
if mutate CAP "$CAP_ANCHOR" "$CAP_UNBOUNDED"; then
  mrun CAP "$(envfor ADVE)" "$TMP/mcap_adve.out"; MRC=$?
  if [ "$MRC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002 commit result: .*MISMATCH.*\(delta=0\), registry delta=0' "$TMP/mcap_adve.out" \
     && ! has "$TMP/mcap_adve.out" "member-internal consistency"; then
    ok "(M-M1-cap) without the digit bound, ADVE's wrapped delta (0) reaches _fc_exit_explained end to end and the '!= 0' clause alone refuses it (rc=1)"
  else
    bad "(M-M1-cap) BLIND: rc=$MRC; $(grep -E 'member-internal|commit result' "$TMP/mcap_adve.out" | head -3)"
  fi
  mrun CAP "$(envfor ADVF)" "$TMP/mcap_advf.out"; MRC=$?
  if [ "$MRC" = 0 ] && grep -qE '^SKIP\[[0-9]+\]: FR-002 commit result \(registry-explained.*delta=-1\)' "$TMP/mcap_advf.out"; then
    ok "(M-M1-cap/ADVF) without the digit bound, ADVF's wrapped count (2^64+1 -> 1) is WRONGLY registry-explained and the run passes (rc=0) -- the reviewer's unmutated-code false explanation, reproduced; the bound is what closes it"
  else
    bad "(M-M1-cap/ADVF) BLIND: rc=$MRC; $(grep -E 'member-internal|commit result' "$TMP/mcap_advf.out" | head -3)"
  fi
fi

echo "=== (M-M1-nz) guard-viability: remove ONLY the '!= 0' clause (digit bound kept) -- ADVE must STILL FAIL, via the digit bound ==="
if mutate NZ "$NZ_ANCHOR" "$NZ_DROPPED"; then
  mrun NZ "$(envfor ADVE)" "$TMP/mnz_adve.out"; MRC=$?
  if [ "$MRC" = 1 ] && has "$TMP/mnz_adve.out" "count is unreadable"; then
    ok "(M-M1-nz) with only the '!= 0' clause dropped, the digit bound alone still refuses ADVE (rc=1) -- each defense is independently sufficient"
  else
    bad "(M-M1-nz) BLIND: rc=$MRC; $(grep -E 'member-internal|commit result' "$TMP/mnz_adve.out" | head -3)"
  fi
fi

echo "=== (M-M1-both) guard-viability: remove BOTH the digit bound and the '!= 0' clause -- ADVE must reproduce the round-18 reviewer's bypass (a false registry-explained SKIP, rc=0) ==="
if [ -f "$TMP/golden_CAP.sh" ] && mutate BOTH "$NZ_ANCHOR" "$NZ_DROPPED" "$TMP/golden_CAP.sh"; then
  mrun BOTH "$(envfor ADVE)" "$TMP/mboth_adve.out"; MRC=$?
  if [ "$MRC" = 0 ] && grep -qE '^SKIP\[[0-9]+\]: FR-002 commit result \(registry-explained.*delta=0' "$TMP/mboth_adve.out"; then
    ok "(M-M1-both) with both defenses removed, ADVE is WRONGLY registry-explained (delta 0 == registry delta 0) and passes (rc=0) -- exactly the reviewer's bypass, so the two defenses are the only things catching it"
  else
    bad "(M-M1-both) BLIND: rc=$MRC; $(grep -E 'member-internal|commit result' "$TMP/mboth_adve.out" | head -3)"
  fi
else
  bad "(M-M1-both) could not construct the double mutant"
fi

echo
if [ "$fail" = 0 ]; then echo "=== T048 ROUND-18 FINDINGS REGRESSION GUARD (R18-I1/M1): ALL CHECKS PASS ==="; else echo "=== T048 ROUND-18 FINDINGS REGRESSION GUARD (R18-I1/M1): FAILURES ABOVE ==="; fi
exit "$fail"
