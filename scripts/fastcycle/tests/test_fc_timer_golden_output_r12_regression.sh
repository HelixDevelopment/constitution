#!/bin/bash
# T048 round-12 independent review findings regression guard for
# test_fc_timer_golden_output.sh (round-13 remediation).
#
# R12-I1 (Important, verbatim finding): the round-11 (R10-B1) known-flaky
# registry excludes a registered gate's own VERDICT LINE, symmetric
# regardless of which member the flake lands in -- but a real flake failing
# in the real pre_build_verification.sh also moves TWO DERIVED surfaces the
# registry never touched: (1) that member's own EXIT CODE (0 on
# $ERRORS==0, else 1), and (2) the final summary-verdict BLOCK (the one-
# time success banner "  (checkmark) ALL MANDATORY CHECKS PASSED" followed
# by dozens of informational lines, wholesale REPLACED by "  (cross) PRE-
# BUILD VERIFICATION FAILED" + a short error count on failure --
# device/rockchip/rk3588/tests/pre_build_verification.sh:51121,:51477, each
# occurring exactly once). On the parent tree being red today (constant
# exit=1 + constant FAILED banner everywhere) neither surface ever moves
# and the gap is invisible; the first GREEN tree with a registered flake
# confined to exactly one member reproduces the R10-B1 FC1-side false FAIL
# on these two surfaces, unchanged by round 11's own fix.
#
# Fix (round 13): (a) the exit-code check gains a THIRD elif --
# _fc_registry_flip_ids() answers "does ANY registered gate's own recorded
# line genuinely differ between these two exact members"; when it does, an
# exit-code divergence neither trivially equal nor noise-floor-explained is
# SKIPped as registry-explained. (b) the verdict-set comparison TRUNCATES
# both sides at (and excluding) the first line matching SUMMARY_TAIL_RE --
# a full-line anchor against the real, unique banner text -- AFTER the
# known-flaky filter, BEFORE the strict/noise-floor comparison; the tail is
# a deterministic function of the SAME exit/commit-result bit already
# checked, so truncating it loses zero detection power as long as (a)
# remains strict for a genuinely-unexplained divergence. NOT a blanket
# loophole: every per-gate check line (registered or not) prints strictly
# BEFORE the banner in the real script and is therefore NEVER truncated, so
# an unregistered gate failing in the SAME member as a registered flake is
# still caught by the verdict-set comparison below (see A2mix).
#
# R12-M1 (Minor, verbatim finding): test_fc_timer_golden_output_r4_regression.sh's
# M-SKIP2PASS mutation only asserted the mutant's OWN raw rc+marker shape;
# it never fed that output through THIS SUITE's own expect_skip() (the
# round-11, R10-I2 kind-check strengthening the whole case exists to
# protect), so a later regression of expect_skip()'s kind-check would leave
# every OTHER call in that file green and go undetected. Fixed directly in
# that file (an additive, backward-compatible 4th PRECOMPUTED_RC parameter
# to expect_skip(), plus a self-guard call feeding it the mutant's own
# already-captured (rc, outfile) pair) -- not re-tested here; see that
# file's own M-SKIP2PASS section.
#
# R12-M2 (Minor, verbatim finding): the registry's "each entry tied to a
# tracked defect" claim was asserted in INFO text but never enforced -- a
# row with an empty reason and no defect_doc was honoured identically to a
# real, documented row, and there was no expiry/tracked-item mechanism at
# all (S11.4.271 / S11.4.248(A) both expect one for an allow-with-known-
# debt exclusion). Fix: KNOWN_FLAKY_TSV_VALID resolves ONLY rows with a
# non-empty reason, an EXISTING defect_doc (relative to $ROOT), and a
# well-formed, non-elapsed ISO `expires` date; a row failing ANY check is
# refused (treated as unregistered, never silently honoured) and the
# refusal is reported.
#
# R12-M3 (Minor): the SPK512 defect doc had no back-reference pointing at
# its own registry exclusion -- a pure documentation fix in the two parent-
# repo defect docs, no test surface here.
#
# HOW THIS FILE TESTS: every case runs the REAL harness (with a stand-in
# pre-build, lib/golden_triplet_fixture.sh) and the REAL golden test end to
# end, exactly like the r7/r8/r10 regression files. Mutations are applied
# to a COPY of the real golden test (never the live file) via the SAME
# content-anchored mutate()/mrun() pattern those files use, with the exact
# anchor text extracted at RUN TIME from the real file via `grep -F` (never
# hand-transcribed).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# T048 round 19 (R18-I2): ROOT MUST honour a caller-supplied
# FC_TIMER_GOLDEN_ROOT override, falling back to the test-file-relative
# parent-repo path ONLY when none is supplied. Before round 19 this line
# UNCONDITIONALLY recomputed ROOT from "$HERE/../../../..", and every mrun()
# below then passed FC_TIMER_GOLDEN_ROOT=$ROOT explicitly to the mutated
# golden copy -- silently OVERWRITING any caller override. Run outside the
# real parent tree (a `git archive` extraction / a bare constitution
# worktree), that derived ROOT has no docs/requests/ defect docs, so the
# known-flaky registry's own defect_doc validation refused EVERY row and
# every registry-dependent mutant reported "registry delta=0" -- a
# location-dependent false FAIL (S11.4.201(1)) that had nothing to do with
# the code under test. The non-mutant gt_golden() runs were never affected
# (they inherit the caller's environment unchanged), which is exactly why
# only the mrun()-based cases (M-I1b here in r12, M-I1-delta in r14,
# M-I1/M-M3 in r16) ever showed it.
ROOT="${FC_TIMER_GOLDEN_ROOT:-$(cd "$HERE/../../../.." && pwd)}"
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
has() { grep -qF -- "$2" "$1"; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
gt_init "$TMP/work"

for f in "$GT_HARNESS" "$REAL_GOLDEN"; do
  # intentional ok/bad control-needle idiom; ok()/bad() are print-only reporters that always return 0, so the || branch never spuriously fires
  # shellcheck disable=SC2015
  [ -f "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done

# T048 round 19 (R18-I2) control needle: every defect_doc the REAL known-
# flaky registry names MUST resolve under the ROOT this file will hand to
# the golden test. Without this, an unresolvable ROOT shows up only
# indirectly -- as a mysterious "registry delta=0" in some LATER mutant --
# instead of being named here, at its actual cause.
while IFS=$'\t' read -r _gid _reason _doc _exp; do
  [ "$_gid" = gate_id ] && continue
  [ -n "$_gid" ] || continue
  # shellcheck disable=SC2015
  [ -n "$_doc" ] && [ -f "$ROOT/$_doc" ] && ok "control needle: registry row $_gid defect_doc resolves under ROOT=$ROOT" \
    || bad "control needle: registry row $_gid defect_doc '$_doc' does NOT resolve under ROOT=$ROOT -- set FC_TIMER_GOLDEN_ROOT to a tree containing it (every registry-dependent case below would otherwise report a location artifact, not a real result)"
done < "$HERE/known_flaky_gates.tsv"


# triplet NAME SEQ FC0a-text FC0b-text FC1-text -- real harness capture +
# promotion. SEQ is a small distinguishing digit so each case's run_id is
# unique (YYYYMMDDTHHMMSSZ format the manifest format requires).
# fixture_selfcheck TEXT -- T048 round 19 (R18-M4): a member text that
# carries its OWN explicit "Failed: N" line must agree with itself: N must
# equal the number of failing-verdict (cross-mark) lines in that SAME text,
# excluding the failure banner (which the real script prints after the
# count, not as a gate). This removes, at the root, the drift risk of the
# hand-typed shared constants (BASE_GREEN / FAILED0/1/2) the A2 family
# composes: a constant edited out of step with the verdict lines it is
# paired with is now refused at fixture-construction time, by name, instead
# of surfacing later as an unexplained member-internal-consistency FAIL in
# the golden output. Prints the mismatch and returns 1; texts without
# exactly one explicit Failed: line are not checked (nothing to agree with).
fixture_selfcheck() {
  local n crosses
  [ "$(printf '%s\n' "$1" | grep -cE '^[[:space:]]*Failed:[[:space:]]+[0-9]+[[:space:]]*$' || true)" = 1 ] || return 0
  n="$(printf '%s\n' "$1" | sed -nE 's/^[[:space:]]*Failed:[[:space:]]+([0-9]+)[[:space:]]*$/\1/p')"
  crosses="$(printf '%s\n' "$1" | grep -F '✗' | grep -cvxF -- "$GFAIL" || true)"
  [ "$n" = "$crosses" ] && return 0
  echo "Failed: $n but $crosses failing-verdict line(s)"
  return 1
}

triplet() {
  local name="$1" fix="$TMP/fix_$1" out="$TMP/ev_$1" runid _m _txt _why
  for _m in 3 4 5; do
    eval "_txt=\${$_m}"
    if ! _why="$(fixture_selfcheck "$_txt")"; then
      bad "($name) fixture self-check: member text #$((_m - 2)) is internally inconsistent -- $_why"
    fi
  done
  runid="202612$(printf '%02d' "$2")T000000Z"
  printf '%s\n' "$3" | gt_member_text "$fix" FC0a
  printf '%s\n' "$4" | gt_member_text "$fix" FC0b
  printf '%s\n' "$5" | gt_member_text "$fix" FC1
  # T048 round 19 (R18-I1): optional 6th arg "E0a E0b E1" -- each member's
  # REAL stand-in exit code (lib/golden_triplet_fixture.sh gt_member_exit),
  # so the harness records it itself and the stand-in's automatic Failed: N
  # line agrees with it. Replaces the pre-round-19 post-capture
  # `set_key member.X.exit` manifest edits, which left a member's own log
  # contradicting its recorded exit once that log gained a summary line.
  if [ -n "${6:-}" ]; then
    # shellcheck disable=SC2086
    set -- "$1" "$2" "$3" "$4" "$5" $6
    gt_member_exit "$fix" FC0a "$6"; gt_member_exit "$fix" FC0b "$7"; gt_member_exit "$fix" FC1 "$8"
  fi
  gt_capture "$fix" "$out" t "$runid" || { bad "($name) harness failed: $(tail -n 3 "$out/.capture.log")"; return 1; }
  gt_promote "$out/t_${runid}.triplet"
}

BASE='  ✓ CM-ONE: first
  ✗ CM-TWO: second'
# Gate-id-FIRST shape, matching the REAL pre_build_verification.sh verdict
# line shape (the leading-token match _fc_filter_known_flaky() depends on).
SPK_OK='  CM-SPK512-BRIDGE-SECLABEL-SHELL: SPK-512 toggle text...   ✓ ok'
SPK_BAD='  CM-SPK512-BRIDGE-SECLABEL-SHELL: SPK-512 toggle text...   ✗ ERROR: broken'
UNREG_OK='  CM-UNREG: genuinely unrelated gate...   ✓ ok'
UNREG_BAD='  CM-UNREG: genuinely unrelated gate...   ✗ ERROR: real unregistered failure'
# REAL banner text, verified against
# device/rockchip/rk3588/tests/pre_build_verification.sh:51121 (success)
# and :51477 (failure) -- asymmetric by design, not a PASSED/FAILED pair,
# each occurring exactly once in that file at the time of this fix.
GOK='  ✓ ALL MANDATORY CHECKS PASSED'
GFAIL='  ✗ PRE-BUILD VERIFICATION FAILED'
# T048 round 14 (R14-I1): the real "  Failed:       N" summary line
# (pre_build_verification.sh:51115), prints strictly BEFORE either banner.
# Which fixtures read which constant (CORRECTED in round 19, R18-M2 -- the
# round-17 follow-up's comment here had it backwards, claiming FAILED1/
# FAILED2 were used "ONLY by A2negctrl/A2same" and "never read"):
#   * FAILED0 -- the GREEN members of A2, A2mirror, A2b and A2mix.
#   * FAILED1 -- the flaking member of A2 (FC1), A2mirror (FC0a) and A2b
#     (FC1); it IS read by the exact-accounting mechanism in all three.
#   * FAILED2 -- A2mix's FC1 (registered flake + genuine UNREG failure).
#   * A2negctrl and A2same use NONE of these: they carry no explicit
#     Failed: line, so the stand-in's automatic summary line (consistent
#     with each member's real exit code, see lib/golden_triplet_fixture.sh,
#     round 19) is what they print.
FAILED1='  Failed:       1'
FAILED2='  Failed:       2'
# T048 round 17 follow-up (member-internal consistency, R16-I1): A2/
# A2mirror/A2b/A2mix USED to pair $BASE (CM-TWO ALWAYS-FAILING, above) with
# a $FAILED1/2 line while ALSO giving their "GREEN" baseline members exit 0
# -- a self-contradictory input (a nonzero Failed count with an exit-0
# member) that went undetected from round 13 through round 16, because no
# check compared a member's own exit code against its own Failed count
# until round 17's _fc_check_member_consistency. That check is CORRECT
# (pre_build_verification.sh exits 0 iff Failed==0) and correctly
# hard-FAILed FC0a/FC0b in A2, A2mirror and A2b once it landed; what was
# stale was the FIXTURE DATA. BASE_GREEN below is $BASE with CM-TWO's
# verdict flipped to passing (used only by A2/A2mirror/A2b/A2mix) and
# FAILED0 is the matching "Failed: 0".
#
# CORRECTED in round 19 (R18-I2): the round-17 follow-up ALSO claimed that
# this same data fix "also resolved" M-I1b below, which it said had been
# failing since before round 17 with the same root cause. That causal claim
# was FALSE. M-I1b never failed in the real parent tree at any of those
# commits; it failed ONLY when this file ran OUTSIDE the parent tree,
# because ROOT (and therefore the FC_TIMER_GOLDEN_ROOT every mrun() passed
# to the mutated golden copy) was computed from "$HERE/../../../.." and
# silently overrode any caller-supplied FC_TIMER_GOLDEN_ROOT -- so the
# registry's defect_doc did not resolve, every registry row was refused,
# and the mutant's registry delta read 0. The follow-up's "16/1 before,
# 17/0 after" observation was an artifact of WHERE each run happened, not
# of the data fix. Round 19 makes ROOT honour FC_TIMER_GOLDEN_ROOT (see its
# definition near the top of this file) and adds a control needle that
# fails loudly when the registry's defect docs do not resolve under ROOT;
# M-I1b now passes in BOTH layouts for its real reason (registry delta 1 ==
# Failed delta 1, so check [12] SKIPs; the untruncated summary tail then
# FAILs check [13]).
BASE_GREEN='  ✓ CM-ONE: first
  ✓ CM-TWO: second'
FAILED0='  Failed:       0'

echo "=== (M4-selfcheck) T048 round 19 (R18-M4): the fixture self-check refuses a drifted constant and accepts a consistent one ==="
if _w="$(fixture_selfcheck "$BASE_GREEN
$SPK_BAD
$FAILED0
$GFAIL")"; then
  bad "(M4-selfcheck) BLIND: a 'Failed: 0' text with one failing verdict line was accepted"
else
  ok "(M4-selfcheck) a 'Failed: 0' text with one failing verdict line is refused ($_w)"
fi
if fixture_selfcheck "$BASE_GREEN
$SPK_BAD
$FAILED1
$GFAIL" > /dev/null; then
  ok "(M4-selfcheck-ctl) a consistent text (one failing verdict line, Failed: 1, banner excluded) is accepted -- the check is not hard-coded to refuse"
else
  bad "(M4-selfcheck-ctl) a consistent text was wrongly refused"
fi

# =============================================================================
# R12-I1: the real-registry, green-tree, exit+summary-tail cascade.
# =============================================================================
echo "=== (A2) R12-I1 exact repro: registered flake confined to FC1 on a GREEN tree, flipping FC1's exit 0->1 AND the real summary banner -- overall PASS expected, not the pre-fix FAIL ==="
triplet A2 1 "$BASE_GREEN
$SPK_OK
$FAILED0
$GOK" "$BASE_GREEN
$SPK_OK
$FAILED0
$GOK" "$BASE_GREEN
$SPK_BAD
$FAILED1
$GFAIL" "0 0 1"
gt_golden "$TMP/a2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_A2"; A2_RC=$?
if [ "$A2_RC" = 0 ] && grep -qE '^SKIP\[[0-9]+\]: FR-002 commit result \(registry-explained' "$TMP/a2.out" \
   && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01.*excluding known-flaky' "$TMP/a2.out" \
   && has "$TMP/a2.out" "excluded the post-summary-banner tail"; then
  ok "(A2) overall PASS (rc=0): the exit-code divergence is registry-explained AND the summary-tail is truncated away -- the pre-fix R10-B1-relocated false FAIL is gone"
else
  bad "(A2) rc=$A2_RC; $(grep -E 'FR-002|INFO: excluded' "$TMP/a2.out" | head -5)"
fi

echo "=== (A2mirror) R12-I1 mirror direction: registered flake confined to FC0a instead of FC1 -- still symmetric, overall PASS ==="
triplet A2mirror 2 "$BASE_GREEN
$SPK_BAD
$FAILED1
$GFAIL" "$BASE_GREEN
$SPK_OK
$FAILED0
$GOK" "$BASE_GREEN
$SPK_OK
$FAILED0
$GOK" "1 0 0"
gt_golden "$TMP/a2m.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_A2mirror"; A2M_RC=$?
# T048 round 19 (R18-M3): this fixture's exit divergence (FC0a 1 vs FC1 0)
# is resolved by the NOISE-FLOOR branch (FC0b also exits 0, matching FC1),
# NOT by the registry-explained branch -- the old ok-message implied the
# latter. The check now pins the branch that actually fires; the registry-
# explained branch in this NEGATIVE-delta direction is exercised end to end
# by (A2mirror-reg) below.
if [ "$A2M_RC" = 0 ] && grep -qE "^SKIP\[[0-9]+\]: FR-002 commit result: with-timers exit status \(0\) differs from without-timers exit status \(1\), but this SAME run's own noise-floor member FC0b ALSO exited 0" "$TMP/a2m.out" \
   && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01' "$TMP/a2m.out"; then
  ok "(A2mirror) overall PASS (rc=0): the SAME flake confined to FC0a instead of FC1 -- the exit divergence is resolved by the NOISE-FLOOR branch (FC0b also exited 0, matching FC1), and the verdict set PASSes once the registered line is excluded"
else
  bad "(A2mirror) rc=$A2M_RC; $(grep -E 'FR-002' "$TMP/a2m.out" | head -5)"
fi

echo "=== (A2mirror-reg) T048 round 19 (R18-M3): registered flake in FC0a AND FC0b, FC1 green -- the noise floor cannot explain it (FC0b matches FC0a), so ONLY the registry-explained branch, in the NEGATIVE-delta direction, can: overall PASS ==="
triplet A2mirrorreg 7 "$BASE_GREEN
$SPK_BAD
$FAILED1
$GFAIL" "$BASE_GREEN
$SPK_BAD
$FAILED1
$GFAIL" "$BASE_GREEN
$SPK_OK
$FAILED0
$GOK" "1 1 0"
gt_golden "$TMP/a2mr.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_A2mirrorreg"; A2MR_RC=$?
if [ "$A2MR_RC" = 0 ] && grep -qE '^SKIP\[[0-9]+\]: FR-002 commit result \(registry-explained.*delta=-1\)' "$TMP/a2mr.out" \
   && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01' "$TMP/a2mr.out"; then
  ok "(A2mirror-reg) overall PASS (rc=0): a registered flake recovering in FC1 (Failed 1 -> 0, registry delta -1) is registry-explained end to end in the negative direction"
else
  bad "(A2mirror-reg) rc=$A2MR_RC; $(grep -E 'FR-002' "$TMP/a2mr.out" | head -5)"
fi

echo "=== (A2b) exit-code-only effect: registered flake flips FC1's exit, but NEITHER log carries a summary banner at all (no truncation possible) -- still overall PASS via the exit-code elif alone ==="
triplet A2b 3 "$BASE_GREEN
$SPK_OK
$FAILED0" "$BASE_GREEN
$SPK_OK
$FAILED0" "$BASE_GREEN
$SPK_BAD
$FAILED1" "0 0 1"
gt_golden "$TMP/a2b.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_A2b"; A2B_RC=$?
if [ "$A2B_RC" = 0 ] && grep -qE '^SKIP\[[0-9]+\]: FR-002 commit result \(registry-explained' "$TMP/a2b.out" \
   && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01' "$TMP/a2b.out" && ! has "$TMP/a2b.out" "excluded the post-summary-banner tail"; then
  ok "(A2b) overall PASS (rc=0), with NO truncation INFO line printed (nothing to truncate) -- the exit-code elif alone explains it"
else
  bad "(A2b) rc=$A2B_RC; $(grep -E 'FR-002|INFO: excluded' "$TMP/a2b.out" | head -5)"
fi

echo "=== (A2mix) NON-LOOPHOLE control: registered flake in FC1 AND a GENUINE unregistered failure ALSO confined to FC1 -- overall FAIL still required (point 3 of the round-12 ruling) ==="
triplet A2mix 4 "$BASE_GREEN
$SPK_OK
$UNREG_OK
$FAILED0
$GOK" "$BASE_GREEN
$SPK_OK
$UNREG_OK
$FAILED0
$GOK" "$BASE_GREEN
$SPK_BAD
$UNREG_BAD
$FAILED2
$GFAIL" "0 0 1"
gt_golden "$TMP/a2mix.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_A2mix"; A2MIX_RC=$?
# T048 round 19 (R18-M3): the old ok-message said the exit divergence "is
# registry-explained"; it is NOT (delta 2 != registry delta 1), and the
# check below now pins the commit-result FAIL that actually fires.
if [ "$A2MIX_RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/a2mix.out" && has "$TMP/a2mix.out" "CM-UNREG" \
   && grep -qE '^FAIL\[[0-9]+\]: FR-002 commit result: .*MISMATCH.*Failed: 0 -> 2 \(delta=2\), registry delta=1' "$TMP/a2mix.out"; then
  ok "(A2mix) overall FAIL (rc=1): check [12] hard-FAILs because the Failed delta (0 -> 2) does NOT equal the registry delta (1) -- round-14 exact accounting refuses to explain it -- and the verdict-set check independently catches the GENUINE unregistered CM-UNREG failure; not a blanket loophole"
else
  bad "(A2mix) BLIND: rc=$A2MIX_RC; $(grep -E 'FR-002|NOISE-FLOOR' "$TMP/a2mix.out" | head -5)"
fi

echo "=== (A2negctrl) isolated probe of the exit-code elif alone: the registered gate's OWN line is IDENTICAL (passes) in FC0a and FC1, so _fc_registry_flip_ids() must report NONE -- an exit divergence for a totally UNRELATED, synthetic reason must still hard-FAIL check [12] ==="
triplet A2negctrl 5 "$BASE
$SPK_OK
$GOK" "$BASE
$SPK_OK
$GOK" "$BASE
$SPK_OK
$GFAIL" "0 0 1"
gt_golden "$TMP/a2nc.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_A2negctrl"; A2NC_RC=$?
if [ "$A2NC_RC" = 1 ] && grep -qE "^FAIL\[[0-9]+\]: FR-002 commit result: with-timers exit status \(1\) equals without-timers exit status \(0\).*MISMATCH, not explained" "$TMP/a2nc.out"; then
  ok "(A2negctrl) check [12] correctly hard-FAILs (rc=1): an identical registered-gate line between FC0a/FC1 is NOT treated as an explanation for an unrelated exit divergence -- the registry-explained elif is not a blanket exit-code exemption"
else
  bad "(A2negctrl) BLIND: rc=$A2NC_RC; $(grep -E 'commit result' "$TMP/a2nc.out" | head -5)"
fi

echo "=== (A2same) backward-compat control: identical exits (0/0/0), identical banners, NO registered gate involved at all -- must be completely unaffected (genuine PASS, unaffected by either new mechanism) ==="
triplet A2same 6 "$BASE
$GOK" "$BASE
$GOK" "$BASE
$GOK" "0 0 0"
gt_golden "$TMP/a2same.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_A2same"; A2S_RC=$?
if [ "$A2S_RC" = 0 ] && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result:' "$TMP/a2same.out" \
   && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01:' "$TMP/a2same.out" && ! has "$TMP/a2same.out" "registry-explained"; then
  ok "(A2same) overall PASS (rc=0) via the ordinary trivially-equal exit-code path -- the new mechanisms never engage when there is nothing for them to explain"
else
  bad "(A2same) rc=$A2S_RC; $(grep -E 'FR-002' "$TMP/a2same.out" | head -5)"
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
# MEASURED, not assumed (S11.4.6): `GT_GOLDEN=... env ... bash "$GT_GOLDEN"`
# does NOT work -- "$GT_GOLDEN" on that SAME command line is expanded by
# THIS shell using its CURRENT (unmutated) value before the prefix
# assignment ever takes effect (a prefix assignment only sets the ENVIRONMENT
# of the external `env`/`bash` processes it precedes, it does not change how
# the REST of that same simple command's own words are expanded) -- found by
# actually running (M-I1a)/(M-I1b) below and seeing the mutation silently
# not apply. Routing through the library's own gt_golden() FUNCTION, like
# every other mutate/mrun pattern in this suite, is what actually works: a
# prefix assignment before a FUNCTION call persists as a real (if
# call-scoped) variable for the function's OWN body, which reads
# "$GT_GOLDEN" dynamically when IT executes, after the assignment landed.
# intentional word-splitting -- $envassigns is a caller-supplied multi-assignment prefix string (e.g. 'A=1 B=2') that MUST split into separate env assignments, quoting it would break that
# shellcheck disable=SC2086
mrun() { local name="$1" envassigns="$2" outfile="$3"; GT_GOLDEN="$TMP/golden_$name.sh" gt_golden "$outfile" $envassigns; }

echo "=== (M-I1a) guard-viability: strip the NEW registry-explained exit-code elif -- (A2) must reproduce the pre-round-13 hard FAIL on check [12], flipping the OVERALL result to FAIL ==="
# T048 round 14: the round-13 elif anchor "_FC_EXIT_FLIP_IDS" was replaced by
# round 14's exact-accounting "_FC_EXIT_EXPLAINED" (see R14-I1 above) -- the
# mutation's INTENT (prove the gating elif is load-bearing for (A2)) is
# unchanged, only the anchor text tracking the code it targets.
if mutate I1a "  elif [ \"\$_FC_EXIT_EXPLAINED\" = 1 ]; then" "  elif false; then  # MUTANT: R14-I1 registry-explained elif disabled"; then
  mrun I1a "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_A2 FC_TIMER_GOLDEN_ROOT=$ROOT FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=$HERE/known_flaky_gates.tsv" "$TMP/mi1a.out"
  MI1A_RC=$?
  if [ "$MI1A_RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002 commit result:.*MISMATCH, not explained' "$TMP/mi1a.out"; then
    ok "(M-I1a) without the new elif, (A2)'s registered-flake exit divergence WRONGLY hard-FAILs again (rc=1) -- the elif is genuinely load-bearing for (A2)'s overall result"
  else
    bad "(M-I1a) BLIND: rc=$MI1A_RC; $(grep -E 'commit result|FR-002/T-A01' "$TMP/mi1a.out" | head -5)"
  fi
else
  bad "(M-I1a) could not construct the mutation (anchor not found)"
fi

echo "=== (M-I1b) guard-viability: strip the NEW summary-tail truncation for the with-timers side -- (A2) must reproduce the pre-round-13 hard FAIL on check [13], flipping the OVERALL result to FAIL even though check [12] independently SKIPs ==="
# T048 round 14 (m5): hoisted into their own narrowly-scoped assignments --
# a `# shellcheck disable` placed directly above an `if ...; then ... fi`
# compound command suppresses that code for the WHOLE if-block body, wider
# than the single literal line that actually needs it.
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
_I1B_ANCHOR='_fc_truncate_before_summary_tail "$TMP/with_timers_fcf_pretrunc.txt" "$TMP/with_timers_fcf.txt"'
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
_I1B_REPL='cp "$TMP/with_timers_fcf_pretrunc.txt" "$TMP/with_timers_fcf.txt"  # MUTANT: R12-I1 truncation disabled on this side'
if mutate I1b "$_I1B_ANCHOR" "$_I1B_REPL"; then
  mrun I1b "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_A2 FC_TIMER_GOLDEN_ROOT=$ROOT FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=$HERE/known_flaky_gates.tsv" "$TMP/mi1b.out"
  MI1B_RC=$?
  if [ "$MI1B_RC" = 1 ] && grep -qE '^SKIP\[[0-9]+\]: FR-002 commit result \(registry-explained' "$TMP/mi1b.out" \
     && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/mi1b.out"; then
    ok "(M-I1b) without the with-timers-side truncation, (A2)'s check [12] still SKIPs (registry-explained) but check [13] WRONGLY hard-FAILs again on the now-untruncated summary tail (rc=1) -- the truncation is genuinely, independently load-bearing, not merely coincidental with the exit-code fix"
  else
    bad "(M-I1b) BLIND: rc=$MI1B_RC; $(grep -E 'commit result|FR-002/T-A01' "$TMP/mi1b.out" | head -5)"
  fi
else
  bad "(M-I1b) could not construct the mutation (anchor not found)"
fi

echo "=== (M-A2mirror-reg) guard-viability (T048 round 19, R18-M3): drop the registry-explained elif -- (A2mirror-reg) must flip to an unexplained hard FAIL ==="
# shellcheck disable=SC2016
if mutate A2MR 'elif [ "$_FC_EXIT_EXPLAINED" = 1 ]; then' 'elif false; then  # MUTANT: registry-explained branch removed'; then
  mrun A2MR "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_A2mirrorreg FC_TIMER_GOLDEN_ROOT=$ROOT FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=$HERE/known_flaky_gates.tsv" "$TMP/ma2mr.out"; MA2MR_RC=$?
  if [ "$MA2MR_RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002 commit result: .*MISMATCH' "$TMP/ma2mr.out"; then
    ok "(M-A2mirror-reg) without the registry-explained branch, (A2mirror-reg) hard-FAILs (rc=1) -- that branch, not the noise floor, is what resolves the negative-delta direction end to end"
  else
    bad "(M-A2mirror-reg) BLIND: rc=$MA2MR_RC; $(grep -E 'commit result' "$TMP/ma2mr.out" | head -3)"
  fi
else
  bad "(M-A2mirror-reg) could not construct the mutation (anchor not found)"
fi

# =============================================================================
# R12-M2: registry row validation (non-empty reason, existing defect_doc,
# non-elapsed expiry). A TEST-LOCAL registry + a TEST-LOCAL, always-existing
# defect_doc file (never the shipped known_flaky_gates.tsv), so these cases
# are decoupled from its content and from wall-clock drift.
# =============================================================================
STUB_DOC_ABS="$TMP/stub_defect_doc.md"
: > "$STUB_DOC_ABS"
# A defect_doc path is resolved relative to $ROOT inside the golden test. T048
# round 14 (m2): this USED to copy the stub into the REAL $ROOT's live
# docs/requests/ tree (a concurrent commit_all.sh's `git add -A` could pick
# it up, and a SIGKILL of this test left it behind permanently) -- the
# golden test's own FC_TIMER_GOLDEN_ROOT override (added for a different
# purpose, R12-M2) makes that unnecessary: a FAKE root entirely under $TMP,
# cleaned up by the SAME trap that already removes $TMP, never touches the
# live tree at all. (The old comment calling this a "symlink" was also
# wrong -- it always `cp`'d, never symlinked; corrected here.)
FAKE_ROOT="$TMP/fake_root_m2"
STUB_DOC_REL="docs/requests/.t048_r12_regression_stub_defect_doc.md"
mkdir -p "$FAKE_ROOT/$(dirname "$STUB_DOC_REL")"
cp "$STUB_DOC_ABS" "$FAKE_ROOT/$STUB_DOC_REL"

B_BASE='  ✓ CM-ONE: first
  ✗ CM-TWO: second'
B_FLAKY_LINE='CM-FLAKY-TEST-GATE: registered flaky gate description...   ✓ ok text'

echo "=== (M2-good) a FULLY VALID row (non-empty reason, existing doc, future expiry) is honoured exactly like round 10/11's own B1 case ==="
GOOD_TSV="$TMP/good.tsv"
printf 'gate_id\treason\tdefect_doc\texpires\nCM-FLAKY-TEST-GATE\tsynthetic test-only flaky gate\t%s\t2099-01-01\n' "$STUB_DOC_REL" > "$GOOD_TSV"
triplet M2good 7 "$B_BASE" "$B_BASE" "$B_BASE
$B_FLAKY_LINE"
gt_golden "$TMP/m2good.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_M2good" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$GOOD_TSV" FC_TIMER_GOLDEN_ROOT="$FAKE_ROOT"; M2G_RC=$?
if [ "$M2G_RC" = 0 ] && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01.*excluding known-flaky' "$TMP/m2good.out" && ! has "$TMP/m2good.out" "WARN: known_flaky_gates.tsv row"; then
  ok "(M2-good) a fully valid row is honoured with no refusal WARNs"
else
  bad "(M2-good) rc=$M2G_RC; $(grep -E 'FR-002/T-A01|WARN:' "$TMP/m2good.out" | head -5)"
fi

echo "=== (M2-empty-reason) a row with an EMPTY reason is refused (treated as unregistered) ==="
BAD_REASON_TSV="$TMP/bad_reason.tsv"
printf 'gate_id\treason\tdefect_doc\texpires\nCM-FLAKY-TEST-GATE\t\t%s\t2099-01-01\n' "$STUB_DOC_REL" > "$BAD_REASON_TSV"
gt_golden "$TMP/m2er.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_M2good" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$BAD_REASON_TSV" FC_TIMER_GOLDEN_ROOT="$FAKE_ROOT"; M2ER_RC=$?
if [ "$M2ER_RC" = 1 ] && has "$TMP/m2er.out" "EMPTY reason" && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/m2er.out"; then
  ok "(M2-empty-reason) an empty-reason row is refused -- the gate's line is NOT excluded, so the unregistered-looking deviation still FAILs"
else
  bad "(M2-empty-reason) rc=$M2ER_RC; $(grep -E 'FR-002/T-A01|WARN:' "$TMP/m2er.out" | head -5)"
fi

echo "=== (M2-missing-doc) a row whose defect_doc does NOT exist is refused ==="
BAD_DOC_TSV="$TMP/bad_doc.tsv"
printf 'gate_id\treason\tdefect_doc\texpires\nCM-FLAKY-TEST-GATE\tsynthetic test-only flaky gate\tdocs/requests/does-not-exist-%s.md\t2099-01-01\n' "$$" > "$BAD_DOC_TSV"
gt_golden "$TMP/m2md.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_M2good" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$BAD_DOC_TSV" FC_TIMER_GOLDEN_ROOT="$FAKE_ROOT"; M2MD_RC=$?
if [ "$M2MD_RC" = 1 ] && has "$TMP/m2md.out" "does not exist" && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/m2md.out"; then
  ok "(M2-missing-doc) a row citing a nonexistent defect_doc is refused"
else
  bad "(M2-missing-doc) rc=$M2MD_RC; $(grep -E 'FR-002/T-A01|WARN:' "$TMP/m2md.out" | head -5)"
fi

echo "=== (M2-malformed-expiry) a row with a non-date expires value is refused ==="
BAD_EXP_TSV="$TMP/bad_exp.tsv"
printf 'gate_id\treason\tdefect_doc\texpires\nCM-FLAKY-TEST-GATE\tsynthetic test-only flaky gate\t%s\tnot-a-date\n' "$STUB_DOC_REL" > "$BAD_EXP_TSV"
gt_golden "$TMP/m2me.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_M2good" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$BAD_EXP_TSV" FC_TIMER_GOLDEN_ROOT="$FAKE_ROOT"; M2ME_RC=$?
if [ "$M2ME_RC" = 1 ] && has "$TMP/m2me.out" "not a YYYY-MM-DD date" && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/m2me.out"; then
  ok "(M2-malformed-expiry) a row with a non-ISO-date expires value is refused"
else
  bad "(M2-malformed-expiry) rc=$M2ME_RC; $(grep -E 'FR-002/T-A01|WARN:' "$TMP/m2me.out" | head -5)"
fi

echo "=== (M2-elapsed-expiry) a row whose expires date is in the PAST is refused ==="
ELAPSED_TSV="$TMP/elapsed.tsv"
printf 'gate_id\treason\tdefect_doc\texpires\nCM-FLAKY-TEST-GATE\tsynthetic test-only flaky gate\t%s\t2000-01-01\n' "$STUB_DOC_REL" > "$ELAPSED_TSV"
gt_golden "$TMP/m2ee.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_M2good" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$ELAPSED_TSV" FC_TIMER_GOLDEN_ROOT="$FAKE_ROOT"; M2EE_RC=$?
if [ "$M2EE_RC" = 1 ] && has "$TMP/m2ee.out" "expired on 2000-01-01" && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/m2ee.out"; then
  ok "(M2-elapsed-expiry) a row whose expires date has already elapsed is refused"
else
  bad "(M2-elapsed-expiry) rc=$M2EE_RC; $(grep -E 'FR-002/T-A01|WARN:' "$TMP/m2ee.out" | head -5)"
fi

echo "=== (M2-future-boundary) a row whose expires date is TODAY is still honoured (inclusive boundary, never off-by-one refused) ==="
TODAY_TSV="$TMP/today.tsv"
TODAY_ISO="$(date -u +%F)"
printf 'gate_id\treason\tdefect_doc\texpires\nCM-FLAKY-TEST-GATE\tsynthetic test-only flaky gate\t%s\t%s\n' "$STUB_DOC_REL" "$TODAY_ISO" > "$TODAY_TSV"
gt_golden "$TMP/m2tb.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_M2good" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$TODAY_TSV" FC_TIMER_GOLDEN_ROOT="$FAKE_ROOT"; M2TB_RC=$?
if [ "$M2TB_RC" = 0 ] && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01.*excluding known-flaky' "$TMP/m2tb.out"; then
  ok "(M2-future-boundary) an expires date equal to today is still honoured (inclusive)"
else
  bad "(M2-future-boundary) rc=$M2TB_RC; $(grep -E 'FR-002/T-A01|WARN:' "$TMP/m2tb.out" | head -5)"
fi

echo "=== (M-M2) guard-viability: disable the empty-reason refusal (single-line anchor; a multi-line anchor here was MEASURED to make grep -cF's control needle report 2 'hits' for a 2-line sequence that occurs only ONCE contiguously -- GNU grep -F with an embedded newline in its pattern argument matches each LINE of the pattern as a separate alternative, summing per-line match counts, rather than requiring the exact multi-line sequence; a genuine S11.4.201(7)(c) 'the path is part of the instrument' footgun, found by running this, not assumed -- so every mutate() anchor in this file stays single-line) -- (M2-empty-reason)'s fixture must reproduce the pre-round-13 false exclusion ==="
# T048 round 14 (m5): hoisted (only the anchor needs SC2016 -- the repl has
# no '$' at all).
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
_M2_ANCHOR='    if [ -z "$reason" ]; then'
if mutate M2 "$_M2_ANCHOR" '    if false; then  # MUTANT: R12-M2 empty-reason refusal disabled'; then
  mrun M2 "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_M2good FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=$BAD_REASON_TSV FC_TIMER_GOLDEN_ROOT=$FAKE_ROOT" "$TMP/mm2.out"
  MM2_RC=$?
  if [ "$MM2_RC" = 0 ] && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01.*excluding known-flaky' "$TMP/mm2.out"; then
    ok "(M-M2) without the empty-reason refusal, the empty-reason row is WRONGLY honoured again (rc=0, excluded) -- the validation is genuinely load-bearing"
  else
    bad "(M-M2) BLIND: rc=$MM2_RC; $(grep -E 'FR-002/T-A01|WARN:' "$TMP/mm2.out" | head -5)"
  fi
else
  bad "(M-M2) could not construct the mutation (anchor not found)"
fi

echo
if [ "$fail" = 0 ]; then echo "=== T048 ROUND-12 FINDINGS REGRESSION GUARD (R12-I1/M2): ALL CHECKS PASS ==="; else echo "=== T048 ROUND-12 FINDINGS REGRESSION GUARD (R12-I1/M2): FAILURES ABOVE ==="; fi
exit "$fail"
