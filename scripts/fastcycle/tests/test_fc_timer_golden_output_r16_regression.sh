#!/bin/bash
# T048 round-16 independent review findings regression guard for
# test_fc_timer_golden_output.sh (round-17 remediation).
#
# R16-I1 (Important, a reproduced false PASS): round 15's exact-accounting
# exit-code elif (see test_fc_timer_golden_output_r14_regression.sh for
# R14-I1/I2) answers "does the Failed:-count delta between FC0a and FC1
# EXACTLY equal the registered gate(s)' own net delta" -- but it NEVER
# checked that EACH member's own exit code is actually explained by that
# SAME member's own "Failed: N" count. The real pre_build_verification.sh
# exits 0 iff Failed==0, nonzero otherwise; a nounset bug inside
# fc_timer_end() itself, called strictly AFTER the Failed: line and the
# terminal banner, can escape an `|| true` guard and leave a member's own
# exit code genuinely INCONSISTENT with its own printed Failed: count
# (MEASURED, not assumed, S11.4.6: `set -euo pipefail; f(){ echo "$nope"; };
# f || true` exits 1). Reproduced end to end (X1/X2 below, round-16
# reviewer's own fixtures): a registered flake's exit-code divergence in ONE
# member, correctly exact-accounting-explained, silently masked a SECOND,
# genuinely unexplained inconsistency in ANOTHER member whose own Failed:/
# exit pair was never cross-checked -- the overall result was a false PASS
# (rc=0).
#
# R16-I2 (Important, a reviewer-authored mutation that survived every
# suite): the exact-accounting elif's own `[ "$_FC_N_DELTA" != 0 ]`
# requirement (added round 14, R14-I1) had NO fixture/mutation of its own;
# a mutation dropping ONLY that clause survived every existing suite
# (r4/r5/r7/r8/r10/r12/r14) unchanged. Fixed this round by isolating the
# whole exact-accounting decision into its own directly-callable function,
# _fc_exit_explained() (defined near _fc_registry_failcount_delta() in the
# golden script) -- see the DEDICATED, ISOLATED unit-level checks below
# (M-I2-unit / M-I2-mutant) for WHY this had to be tested in isolation
# rather than through a three-member golden-triplet fixture: once R16-I1's
# member-internal-consistency precondition holds for both members whose
# Failed count is resolvable, a differing-exit-but-delta==0 scenario (the
# ONLY shape that could ever exploit this clause's removal) becomes
# PROVABLY UNREACHABLE through the full harness (consistency forces
# exit = (Failed != 0), so N0 == N1 forces _ex0 == _ex1, which never even
# reaches this elif) -- X3 below demonstrates that directly: it remains a
# valid R16-I1 fixture (an internally-inconsistent member), but it can no
# longer distinguish the `!= 0` clause's own presence or absence, because
# R16-I1's hard FAIL fires first and unconditionally either way.
#
# R16-M1 (Minor): round 14's m3 (ISO-date validation) and m4 (header-less-
# registry handling) fixes shipped with NO test/mutation guard anywhere;
# four reverting mutants (date round-trip -> true, the TODAY FATAL check
# disabled, the tail-RE WARN check disabled, the unconditional-skip-row-1
# behaviour restored) all survived every existing suite. Fixed this round
# with dedicated fixtures below (M3/M3T/M3W/M4).
#
# R16-M2 (Minor): _fc_failed_count()'s number-extraction accepted a
# leading-zero count (e.g. "08"), and bash's own $((...)) treats "08" as an
# (invalid) octal literal. Fixed this round by stripping leading zeros at
# the source. See the M2 fixtures below for the PRECISE, measured
# consequence (never overstated, S11.4.6): the failing expansion does NOT
# abort the whole script -- it silently abandons the rest of the ENTIRE
# enclosing `if`/compound block it sits inside and resumes at the first
# statement after that block's closing `fi`, which for the real golden
# script means the whole FR-002/T-A01 comparison section is silently
# skipped and the run reports a FALSE PASS with a TRUNCATED assertion
# count -- confirmed live with `bash -x`, not assumed.
#
# R16-M3 (Minor): FAIL_CLASS_RE classified a line as failing by matching
# '\xe2\x9c\x97'/'ERROR:'/'FAIL' ANYWHERE in the line (a substring match),
# so a registered gate's own PASSING message whose detail text happened to
# CONTAIN one of those tokens (e.g. "...  ok (no ERROR: found, previously a
# \xe2\x9c\x97 issue)") would be misclassified as failing -- a carrier
# false-match (S11.4.201(7)(a)). Fixed this round by anchoring the match to
# the verdict-token position (immediately after the "... " check-
# description-prompt prefix every real check line uses, mirroring
# VERDICT_RE's own OK/FAIL anchor).
#
# HOW THIS FILE TESTS: every triplet case runs the REAL harness (with a
# stand-in pre-build, lib/golden_triplet_fixture.sh) and the REAL golden
# test end to end, exactly like the r4/r7/r8/r10/r12/r14 regression files.
# The isolated R16-I2/R16-M2/R16-M3 unit-level checks instead SOURCE the
# golden script (or a mutated copy of it) directly and call its own
# functions, which is the only way to exercise a clause the full harness
# can no longer reach once R16-I1 lands (see R16-I2 above) -- `source`ing
# the script is safe here because its own last top-level statement is a
# bare `[ "$FAIL" = 0 ]` test, never an `exit` call, so a run with zero
# recorded FAILs returns normally to the sourcing shell instead of
# terminating it (verified live: appending further commands after the
# `source` in the SAME shell executes them). Mutations are applied to a
# COPY of the real golden test (never the live file) via the SAME content-
# anchored mutate()/mrun() pattern the other regression files use, with the
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
KNOWN_FLAKY_TSV_REAL="$HERE/known_flaky_gates.tsv"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "NOT ok $1"; fail=1; }
has() { grep -qF -- "$2" "$1"; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
gt_init "$TMP/work"

for f in "$GT_HARNESS" "$REAL_GOLDEN" "$KNOWN_FLAKY_TSV_REAL"; do
  # intentional ok/bad control-needle idiom; ok()/bad() are print-only reporters that always return 0, so the || branch never spuriously fires
  # shellcheck disable=SC2015
  [ -e "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done

set_key() { sed -i "s|^$2=.*|$2=$3|" "$1"; }

# triplet NAME SEQ FC0a-text FC0b-text FC1-text -- real harness capture +
# promotion. SEQ is a small distinguishing digit so each case's run_id is
# unique (YYYYMMDDTHHMMSSZ format the manifest format requires).
triplet() {
  local name="$1" fix="$TMP/fix_$1" out="$TMP/ev_$1" runid
  runid="202616$(printf '%02d' "$2")T000000Z"
  printf '%s\n' "$3" | gt_member_text "$fix" FC0a
  printf '%s\n' "$4" | gt_member_text "$fix" FC0b
  printf '%s\n' "$5" | gt_member_text "$fix" FC1
  gt_capture "$fix" "$out" t "$runid" || { bad "($name) harness failed: $(tail -n 3 "$out/.capture.log")"; return 1; }
  gt_promote "$out/t_${runid}.triplet"
  MF="$out/t_${runid}.triplet"
}

CBASE='  ✓ CM-ONE: clean baseline gate'
SPK_OK='  CM-SPK512-BRIDGE-SECLABEL-SHELL: SPK-512 toggle text...   ✓ ok'
SPK_BAD='  CM-SPK512-BRIDGE-SECLABEL-SHELL: SPK-512 toggle text...   ✗ ERROR: broken'
GOK='  ✓ ALL MANDATORY CHECKS PASSED'
GFAIL='  ✗ PRE-BUILD VERIFICATION FAILED'
FAILED0='  Failed:       0'
FAILED1='  Failed:       1'

# =============================================================================
# R16-I1: member-internal exit/Failed consistency.
# =============================================================================
echo "=== (X1) R16-I1 exact repro (reviewer's own fixture): FC0a carries a registered flake (Failed:1, exit 1, exactly explained), FC1 has clean verdicts + Failed:0 + the success banner but a SECOND, unrelated, genuinely inconsistent exit code (2) -- overall FAIL required, not the pre-round-16 false PASS ==="
triplet X1 1 "$CBASE
$SPK_BAD
$FAILED1
$GFAIL" "$CBASE
$SPK_OK
$FAILED0
$GOK" "$CBASE
$SPK_OK
$FAILED0
$GOK"
set_key "$MF" member.FC0a.exit 1; set_key "$MF" member.FC0b.exit 0; set_key "$MF" member.FC1.exit 2
gt_golden "$TMP/x1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_X1"; X1_RC=$?
if [ "$X1_RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: T048 round-16 member-internal consistency \(FC1\): exit code \(2\) is neither 0 nor 1' "$TMP/x1.out"; then
  ok "(X1) overall FAIL (rc=1): FC1's own exit code (2) is neither 0 nor 1 and is correctly hard-FAILed by name, BEFORE the exact-accounting elif ever gets a chance to (wrongly) explain away the registered flake's own, separate, genuinely-explained divergence"
else
  bad "(X1) BLIND: rc=$X1_RC; $(grep -E 'member-internal|commit result' "$TMP/x1.out" | head -5)"
fi

echo "=== (X2) R16-I1 exact repro, variant: same as (X1) but FC1 exits 1 (the SAME value FC0a recorded) instead of 2 -- the pre-round-16 'trivially equal exits' branch used to accept this unchecked; overall FAIL still required ==="
triplet X2 2 "$CBASE
$SPK_BAD
$FAILED1
$GFAIL" "$CBASE
$SPK_OK
$FAILED0
$GOK" "$CBASE
$SPK_OK
$FAILED0
$GOK"
set_key "$MF" member.FC0a.exit 1; set_key "$MF" member.FC0b.exit 0; set_key "$MF" member.FC1.exit 1
gt_golden "$TMP/x2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_X2"; X2_RC=$?
if [ "$X2_RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: T048 round-16 member-internal consistency \(FC1\): exit code \(1\) with Failed: 0' "$TMP/x2.out"; then
  ok "(X2) overall FAIL (rc=1): FC1 reports Failed:0 but exits 1 -- internally inconsistent regardless of what FC0a's exit code happens to equal; the pre-round-16 'exit (1) equals (1), trivially PASS' branch never got the chance to hide it"
else
  bad "(X2) BLIND: rc=$X2_RC; $(grep -E 'member-internal|commit result' "$TMP/x2.out" | head -5)"
fi

echo "=== (X3) R16-I1 control (round-16 reviewer's own fixture, already correctly handled pre-round-16 via the OLD cascade's final else -- this fixture now ALSO demonstrates the member-consistency check firing first, and documents the R16-I2 unreachability it creates; see the dedicated R16-I2 unit-level checks below for the clause this fixture can no longer isolate) ==="
triplet X3 3 "$CBASE
$SPK_OK
$FAILED0
$GOK" "$CBASE
$SPK_OK
$FAILED0
$GOK" "$CBASE
$SPK_OK
$FAILED0
$GOK"
set_key "$MF" member.FC0a.exit 0; set_key "$MF" member.FC0b.exit 0; set_key "$MF" member.FC1.exit 1
gt_golden "$TMP/x3.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_X3"; X3_RC=$?
if [ "$X3_RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: T048 round-16 member-internal consistency \(FC1\): exit code \(1\) with Failed: 0' "$TMP/x3.out"; then
  ok "(X3) overall FAIL (rc=1): FC1's Failed:0/exit:1 inconsistency is hard-FAILed by the NEW member-consistency check -- correct, and consistent with the pre-round-16 behaviour (which also correctly FAILed this exact fixture via the OLD cascade's own final else, now redundantly)"
else
  bad "(X3) BLIND: rc=$X3_RC; $(grep -E 'member-internal|commit result' "$TMP/x3.out" | head -5)"
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
# mrun NAME ENVASSIGNS OUTFILE -- see r14_regression.sh's own mrun() comment
# for why this routes through the library's gt_golden() function rather than
# a bare `GT_GOLDEN=... env ... bash "$GT_GOLDEN"` one-liner.
# intentional word-splitting -- $envassigns is a caller-supplied multi-assignment prefix string (e.g. 'A=1 B=2') that MUST split into separate env assignments, quoting it would break that
# shellcheck disable=SC2086
mrun() { local name="$1" envassigns="$2" outfile="$3"; GT_GOLDEN="$TMP/golden_$name.sh" gt_golden "$outfile" $envassigns; }

echo "=== (M-I1) guard-viability: disable the new member-internal-consistency check entirely -- (X1)/(X2) must reproduce the pre-round-16 false PASS ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
ANCHOR_I1='    [ -n "$failed" ] || return 0'
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
REPL_I1='    return 0  # MUTANT: R16-I1 member-consistency check disabled entirely
    [ -n "$failed" ] || return 0'
if mutate I1 "$ANCHOR_I1" "$REPL_I1"; then
  mrun I1 "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_X1 FC_TIMER_GOLDEN_ROOT=$ROOT FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=$KNOWN_FLAKY_TSV_REAL" "$TMP/mi1_x1.out"
  MI1_X1_RC=$?
  mrun I1 "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_X2 FC_TIMER_GOLDEN_ROOT=$ROOT FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=$KNOWN_FLAKY_TSV_REAL" "$TMP/mi1_x2.out"
  MI1_X2_RC=$?
  if [ "$MI1_X1_RC" = 0 ] && grep -qE '^SKIP\[[0-9]+\]: FR-002 commit result \(registry-explained' "$TMP/mi1_x1.out" \
     && [ "$MI1_X2_RC" = 0 ] && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result: .*exit status \(1\) equals' "$TMP/mi1_x2.out"; then
    ok "(M-I1) without the member-consistency check, BOTH (X1) (via the registry-explained SKIP) AND (X2) (via the trivially-equal PASS) WRONGLY flip to overall PASS (rc=0) -- the new check is genuinely load-bearing, reproducing exactly the round-16 reviewer's own finding"
  else
    bad "(M-I1) BLIND: x1_rc=$MI1_X1_RC x2_rc=$MI1_X2_RC; $(grep -E 'commit result' "$TMP/mi1_x1.out" "$TMP/mi1_x2.out" | head -5)"
  fi
else
  bad "(M-I1) could not construct the mutation (anchor not found)"
fi

# =============================================================================
# R16-I2: the exact-accounting elif's own "!= 0" requirement, tested in
# ISOLATION via _fc_exit_explained() -- see the file header for why an
# end-to-end triplet can no longer isolate this clause once (M-I1) above
# shows the member-consistency check is in place and load-bearing.
# =============================================================================
DUMMY_LOG="$TMP/dummy_for_source.log"
printf 'dummy, never a real pre_build evidence log -- only used so sourcing the golden script does not hit its own "no evidence log found" FATAL before reaching the function definitions this section calls directly\n' > "$DUMMY_LOG"
cat > "$TMP/driver.sh" <<'EOF'
#!/bin/bash
set -u
SCRIPT="$1"; shift
FUNC="$1"; shift
FC_TIMER_GOLDEN_LOG="$DUMMY_LOG" . "$SCRIPT" > /dev/null 2>&1
"$FUNC" "$@"
EOF

echo "=== (M-I2-unit) R16-I2 exact repro, isolated: _fc_exit_explained(0, 0, 0) -- a genuine delta=0 (nothing to explain) must NEVER be reported as explained ==="
UNIT1="$(DUMMY_LOG="$DUMMY_LOG" bash "$TMP/driver.sh" "$REAL_GOLDEN" _fc_exit_explained 0 0 0)"
if [ "$UNIT1" = 0 ]; then
  ok "(M-I2-unit) _fc_exit_explained(0, 0, 0) correctly prints 0 (not explained) -- the delta-must-be-nonzero requirement holds"
else
  bad "(M-I2-unit) BLIND: _fc_exit_explained(0, 0, 0) printed '$UNIT1', expected 0"
fi

echo "=== (M-I2-unit-ctl) non-loophole control: a genuine, nonzero, exactly-matching delta IS correctly reported as explained ==="
UNIT2="$(DUMMY_LOG="$DUMMY_LOG" bash "$TMP/driver.sh" "$REAL_GOLDEN" _fc_exit_explained 1 0 -1)"
if [ "$UNIT2" = 1 ]; then
  ok "(M-I2-unit-ctl) _fc_exit_explained(1, 0, -1) correctly prints 1 (explained) -- the S11.4.201(1) false-positive guard: the function is not simply hard-coded to always say 0"
else
  bad "(M-I2-unit-ctl) BLIND: _fc_exit_explained(1, 0, -1) printed '$UNIT2', expected 1"
fi

echo "=== (M-I2-mutant) guard-viability: drop ONLY the '!= 0' clause from _fc_exit_explained() -- the SAME (0, 0, 0) call must now WRONGLY report 'explained' ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
ANCHOR_I2='  if [ "$delta" != 0 ] && [ "$delta" = "$reg" ]; then printf 1; else printf 0; fi'
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
REPL_I2='  if [ "$delta" = "$reg" ]; then printf 1; else printf 0; fi  # MUTANT: R16-I2 nonzero-delta requirement dropped'
if mutate I2 "$ANCHOR_I2" "$REPL_I2"; then
  MUT1="$(DUMMY_LOG="$DUMMY_LOG" bash "$TMP/driver.sh" "$TMP/golden_I2.sh" _fc_exit_explained 0 0 0)"
  if [ "$MUT1" = 1 ]; then
    ok "(M-I2-mutant) without the '!= 0' clause, _fc_exit_explained(0, 0, 0) WRONGLY prints 1 (explained) -- the SAME basic FR-002 counter-example (round-16 reviewer's golden_mutNZ.sh) this clause exists to catch; the clause is genuinely load-bearing when tested in the isolation this file's header explains is now required"
  else
    bad "(M-I2-mutant) BLIND: mutant _fc_exit_explained(0, 0, 0) printed '$MUT1', expected 1"
  fi
else
  bad "(M-I2-mutant) could not construct the mutation (anchor not found)"
fi

# =============================================================================
# R16-M1: round-14's m3 (ISO-date validation) and m4 (header-less-registry
# handling) fixes, each tested end to end with a TEST-LOCAL registry
# (never the shipped known_flaky_gates.tsv) so these cases are decoupled
# from its content -- mirroring r10_regression.sh's own established R10-B1
# convention.
# =============================================================================
R16GATE_OK='  CM-R16TESTGATE: synthetic test gate...   ✓ ok'
R16GATE_BAD='  CM-R16TESTGATE: synthetic test gate...   ✗ ERROR: broken'

echo "=== (M4) R16-M1 exact repro: a known-flaky registry with NO header row at all (row 1 is real data) -- the registered gate's own self-heal must still be excluded, overall PASS ==="
REG_M4="$TMP/reg_m4.tsv"
printf 'CM-R16TESTGATE\tsynthetic test row with no header row at all (T048 round 16, R16-M1/M4 fixture)\tdocs/requests/t048_round4_defect1_spk512_bridge_report.md\t2099-01-01\n' > "$REG_M4"
triplet M4 4 "$CBASE
$R16GATE_BAD
$FAILED1
$GFAIL" "$CBASE
$R16GATE_BAD
$FAILED1
$GFAIL" "$CBASE
$R16GATE_OK
$FAILED0
$GOK"
set_key "$MF" member.FC0a.exit 1; set_key "$MF" member.FC0b.exit 1; set_key "$MF" member.FC1.exit 0
gt_golden "$TMP/m4.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_M4" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$REG_M4"; M4_RC=$?
if [ "$M4_RC" = 0 ] && has "$TMP/m4.out" "CM-R16TESTGATE" && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01.*excluding known-flaky' "$TMP/m4.out"; then
  ok "(M4) overall PASS (rc=0): the header-less registry's ONLY row is correctly resolved (NOT mistaken for a header) and correctly excludes the self-healed gate"
else
  bad "(M4) BLIND: rc=$M4_RC; $(grep -E 'commit result|FR-002/T-A01' "$TMP/m4.out" | head -5)"
fi

echo "=== (M3) R16-M1 exact repro: a known-flaky registry row whose expires date is SHAPE-valid but calendrically impossible (2099-02-30, Feb has no 30th), chosen to be LEXICOGRAPHICALLY in the future so the separate elapsed-expiry check alone could never mask this -- the row must be refused, overall FAIL (never silently excluded) ==="
REG_M3="$TMP/reg_m3.tsv"
printf 'gate_id\treason\tdefect_doc\texpires\nCM-R16TESTGATE\tsynthetic test row with a shape-valid but calendrically impossible expiry, lexicographically in the future so an elapsed-expiry false-positive cannot mask this (T048 round 16, R16-M1/M3 fixture)\tdocs/requests/t048_round4_defect1_spk512_bridge_report.md\t2099-02-30\n' > "$REG_M3"
triplet M3 5 "$CBASE
$R16GATE_BAD
$FAILED1
$GFAIL" "$CBASE
$R16GATE_BAD
$FAILED1
$GFAIL" "$CBASE
$R16GATE_OK
$FAILED0
$GOK"
set_key "$MF" member.FC0a.exit 1; set_key "$MF" member.FC0b.exit 1; set_key "$MF" member.FC1.exit 0
gt_golden "$TMP/m3.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_M3" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$REG_M3"; M3_RC=$?
if [ "$M3_RC" = 1 ] && grep -qE "^WARN: known_flaky_gates\.tsv row 'CM-R16TESTGATE' has expires='2099-02-30', not a YYYY-MM-DD date" "$TMP/m3.out"; then
  ok "(M3) overall FAIL (rc=1): the calendrically-impossible expiry is refused (not merely shape-checked), so the row is treated as unregistered and the real divergence surfaces -- never silently masked"
else
  bad "(M3) BLIND: rc=$M3_RC; $(grep -E 'WARN:|commit result' "$TMP/m3.out" | head -5)"
fi

echo "=== (M3T) R16-M1 exact repro: an explicit FC_TIMER_GOLDEN_TODAY override that is shape-valid but not a real calendar date must FATAL, never silently disable expiry-checking for every registered row ==="
FC_TIMER_GOLDEN_TODAY='0000-00-00' bash "$REAL_GOLDEN" > "$TMP/m3t.out" 2>&1; M3T_RC=$?
if [ "$M3T_RC" = 2 ] && has "$TMP/m3t.out" "FATAL: FC_TIMER_GOLDEN_TODAY='0000-00-00' is not a real YYYY-MM-DD calendar date"; then
  ok "(M3T) FATAL (rc=2) with the exact, named reason -- a calendrically-impossible TODAY override is refused loudly, before it ever reaches a single known_flaky_gates.tsv row"
else
  bad "(M3T) BLIND: rc=$M3T_RC; $(grep -E 'FATAL' "$TMP/m3t.out" | head -5)"
fi

echo "=== (M3W) R16-M1 exact repro: a syntactically invalid FC_TIMER_GOLDEN_SUMMARY_TAIL_RE override must WARN loudly (summary-tail truncation disabled, never a silent corruption) ==="
FC_TIMER_GOLDEN_ROOT="$ROOT" FC_TIMER_GOLDEN_SUMMARY_TAIL_RE='(unbalanced' bash "$REAL_GOLDEN" > "$TMP/m3w.out" 2>&1; M3W_RC=$?
if has "$TMP/m3w.out" "WARN: FC_TIMER_GOLDEN_SUMMARY_TAIL_RE='(unbalanced' is not a syntactically valid extended regular expression"; then
  ok "(M3W) the invalid override is WARNed about loudly and by name (rc=$M3W_RC)"
else
  bad "(M3W) BLIND: rc=$M3W_RC; $(grep -E 'WARN:' "$TMP/m3w.out" | head -5)"
fi

echo "=== (M-M4) guard-viability: restore the unconditional 'always skip row 1' behaviour -- (M4)'s header-less row is WRONGLY dropped, the self-heal is no longer excluded, overall FAIL ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
ANCHOR_M4="done < <(awk -F'\t' 'BEGIN { OFS=\"\x1f\" } NR == 1 && \$1 == \"gate_id\" { next } { print \$1, \$2, \$3, \$4 }' \"\$KNOWN_FLAKY_TSV\")"
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
REPL_M4="done < <(awk -F'\t' 'BEGIN { OFS=\"\x1f\" } NR > 1 { print \$1, \$2, \$3, \$4 }' \"\$KNOWN_FLAKY_TSV\")  # MUTANT: R16-M1/M4 unconditional-skip-row-1 restored"
if mutate M4 "$ANCHOR_M4" "$REPL_M4"; then
  mrun M4 "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_M4 FC_TIMER_GOLDEN_ROOT=$ROOT FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=$REG_M4" "$TMP/mm4.out"
  MM4_RC=$?
  if [ "$MM4_RC" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/mm4.out" && ! has "$TMP/mm4.out" "INFO: excluded known-flaky"; then
    ok "(M-M4) without the fix, the header-less row's ONLY data row is WRONGLY treated as a header and dropped (rc=1, no exclusion INFO line at all) -- the fix is genuinely load-bearing"
  else
    bad "(M-M4) BLIND: rc=$MM4_RC; $(grep -E 'FR-002/T-A01|INFO: excluded' "$TMP/mm4.out" | head -5)"
  fi
else
  bad "(M-M4) could not construct the mutation (anchor not found)"
fi

echo "=== (M-M3) guard-viability: replace the date round-trip validation with 'true' -- (M3)'s calendrically-impossible-but-lexicographically-future expiry is WRONGLY accepted, overall PASS ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
ANCHOR_M3='  [ "$(date -u -d "$1" +%F 2>/dev/null)" = "$1" ]'
REPL_M3='  true  # MUTANT: R16-M1/M3 date round-trip validation dropped'
if mutate M3 "$ANCHOR_M3" "$REPL_M3"; then
  mrun M3 "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_M3 FC_TIMER_GOLDEN_ROOT=$ROOT FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=$REG_M3" "$TMP/mm3.out"
  MM3_RC=$?
  if [ "$MM3_RC" = 0 ] && ! has "$TMP/mm3.out" "WARN:" && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01.*excluding known-flaky' "$TMP/mm3.out"; then
    ok "(M-M3) without the real-calendar round-trip, the shape-only-valid '2099-02-30' is WRONGLY accepted (no WARN at all, rc=0) and masks the real divergence -- the fix is genuinely load-bearing"
  else
    bad "(M-M3) BLIND: rc=$MM3_RC; $(grep -E 'WARN:|FR-002/T-A01' "$TMP/mm3.out" | head -5)"
  fi
else
  bad "(M-M3) could not construct the mutation (anchor not found)"
fi

echo "=== (M-M3T) guard-viability: disable the FC_TIMER_GOLDEN_TODAY FATAL check -- the SAME impossible override now falls through silently (no longer refused by name) ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
ANCHOR_M3T='if [ -n "${FC_TIMER_GOLDEN_TODAY:-}" ] && ! _fc_valid_iso_date "$FC_TIMER_GOLDEN_TODAY"; then'
REPL_M3T='if false; then  # MUTANT: R16-M1/M3T TODAY FATAL check disabled'
if mutate M3T "$ANCHOR_M3T" "$REPL_M3T"; then
  GT_GOLDEN="$TMP/golden_M3T.sh" FC_TIMER_GOLDEN_TODAY='0000-00-00' bash "$TMP/golden_M3T.sh" > "$TMP/mm3t.out" 2>&1
  MM3T_RC=$?
  if ! has "$TMP/mm3t.out" "FATAL: FC_TIMER_GOLDEN_TODAY='0000-00-00' is not a real YYYY-MM-DD calendar date"; then
    ok "(M-M3T) without the fix, the SAME impossible TODAY override no longer FATALs by its own name (rc=$MM3T_RC, the specific message is absent) -- the fix is genuinely load-bearing"
  else
    bad "(M-M3T) BLIND: the mutant still printed the FATAL message unchanged"
  fi
else
  bad "(M-M3T) could not construct the mutation (anchor not found)"
fi

echo "=== (M-M3W) guard-viability: disable the SUMMARY_TAIL_RE syntax-validity WARN -- the SAME invalid override no longer WARNs by its own name ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
ANCHOR_M3W='if [ "$_fc_summary_tail_re_rc" -gt 1 ]; then'
REPL_M3W='if false; then  # MUTANT: R16-M1/M3W tail-RE WARN disabled'
if mutate M3W "$ANCHOR_M3W" "$REPL_M3W"; then
  GT_GOLDEN="$TMP/golden_M3W.sh" FC_TIMER_GOLDEN_ROOT="$ROOT" FC_TIMER_GOLDEN_SUMMARY_TAIL_RE='(unbalanced' bash "$TMP/golden_M3W.sh" > "$TMP/mm3w.out" 2>&1
  if ! has "$TMP/mm3w.out" "WARN: FC_TIMER_GOLDEN_SUMMARY_TAIL_RE='(unbalanced' is not a syntactically valid extended regular expression"; then
    ok "(M-M3W) without the fix, the SAME invalid override no longer WARNs by its own name at all -- the fix is genuinely load-bearing"
  else
    bad "(M-M3W) BLIND: the mutant still printed the WARN message unchanged"
  fi
else
  bad "(M-M3W) could not construct the mutation (anchor not found)"
fi

# =============================================================================
# R16-M2: _fc_failed_count() leading-zero handling.
# =============================================================================
echo "=== (M2-unit) R16-M2 exact repro, isolated: _fc_failed_count() on a log whose real summary line reads 'Failed:       08' must print the decimal-safe '8', never the raw, bash-arithmetic-unsafe '08' ==="
LZ_LOG="$TMP/leading_zero.log"
printf '%s\n' "$CBASE
  Failed:       08
$GOK" > "$LZ_LOG"
UNIT_LZ="$(DUMMY_LOG="$DUMMY_LOG" bash "$TMP/driver.sh" "$REAL_GOLDEN" _fc_failed_count "$LZ_LOG")"
if [ "$UNIT_LZ" = 8 ]; then
  ok "(M2-unit) _fc_failed_count() on a 'Failed:       08' log correctly prints '8' (decimal-safe), not the raw '08'"
else
  bad "(M2-unit) BLIND: _fc_failed_count() printed '$UNIT_LZ', expected 8"
fi

echo "=== (M2) R16-M2 exact repro, end to end: a real triplet whose FC0a/FC0b both print 'Failed:       08' (and FC1 'Failed:       01') must be processed without any loss of downstream checks (every check this fixture would otherwise exercise still runs, not silently truncated) ==="
triplet M2 6 "$CBASE
  Failed:       08
$GOK" "$CBASE
  Failed:       08
$GOK" "$CBASE
  Failed:       01
$GFAIL"
set_key "$MF" member.FC0a.exit 1; set_key "$MF" member.FC0b.exit 1; set_key "$MF" member.FC1.exit 1
gt_golden "$TMP/m2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_M2"; M2_RC=$?
M2_N="$(sed -nE 's/^SUMMARY: [0-9]+ pass \/ [0-9]+ fail \/ [0-9]+ skip of ([0-9]+) assertions.*/\1/p' "$TMP/m2.out")"
if [ "$M2_RC" = 0 ] && grep -qE '^PASS\[[0-9]+\]: FR-002 commit result:' "$TMP/m2.out" \
   && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01:' "$TMP/m2.out" && ! has "$TMP/m2.out" "value too great for base"; then
  ok "(M2) overall PASS (rc=0, $M2_N assertions, no arithmetic-error line anywhere): both the exit-code check AND the verdict-set check run and record a verdict -- nothing is silently skipped"
else
  bad "(M2) BLIND: rc=$M2_RC assertions=$M2_N; $(grep -E 'commit result|FR-002/T-A01|value too great' "$TMP/m2.out" | head -5)"
fi

echo "=== (M-M2) guard-viability: drop the leading-zero strip -- the SAME (M2) triplet must reproduce the measured, PRECISE consequence: the arithmetic error fires, the ENTIRE rest of the FR-002/T-A01 comparison section is silently abandoned (never reached), and the run reports a FALSE PASS with FEWER assertions than (M2)'s own clean run recorded ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
ANCHOR_M2='  printf '"'"'%s'"'"' "$raw" | sed -E '"'"'s/^0+([0-9])/\1/'"'"''
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
REPL_M2='  printf '"'"'%s'"'"' "$raw"  # MUTANT: R16-M2 leading-zero strip dropped'
if mutate M2 "$ANCHOR_M2" "$REPL_M2"; then
  mrun M2 "FC_TIMER_GOLDEN_EVIDENCE_DIR=$TMP/ev_M2" "$TMP/mm2.out"
  MM2_RC=$?
  MM2_N="$(sed -nE 's/^SUMMARY: [0-9]+ pass \/ [0-9]+ fail \/ [0-9]+ skip of ([0-9]+) assertions.*/\1/p' "$TMP/mm2.out")"
  if [ "$MM2_RC" = 0 ] && has "$TMP/mm2.out" "value too great for base" \
     && ! grep -qE '^(PASS|FAIL|SKIP)\[[0-9]+\]: FR-002 commit result:' "$TMP/mm2.out" \
     && [ -n "$MM2_N" ] && [ "$MM2_N" -lt "$M2_N" ]; then
    ok "(M-M2) without the fix, the arithmetic error fires (the exact message appears) and the exit-code check [FR-002 commit result] never even gets a verdict recorded at all ($MM2_N assertions vs this file's own (M2) clean run's $M2_N) -- a false PASS (rc=0) caused by silently abandoned verification, exactly as this file's header describes; the fix is genuinely load-bearing"
  else
    bad "(M-M2) BLIND: rc=$MM2_RC assertions=$MM2_N (clean was $M2_N); $(grep -E 'commit result|value too great' "$TMP/mm2.out" | head -5)"
  fi
else
  bad "(M-M2) could not construct the mutation (anchor not found)"
fi

# =============================================================================
# R16-M3: FAIL_CLASS_RE verdict-token-position anchoring.
# =============================================================================
echo "=== (M3FC-unit) R16-M3 exact repro, isolated: a registered-id-shaped line whose REAL verdict token is a PASS ('...   ✓ ok'), but whose OWN trailing detail text happens to mention the substrings 'ERROR:' and '✗' AFTER that real verdict, must NOT be classified as failing ==="
CARRIER_PASS='  CM-R16TESTGATE: synthetic test gate...   ✓ ok (no ERROR: found, previously had a ✗ issue, now fixed)'
UNIT_FC1="$(DUMMY_LOG="$DUMMY_LOG" bash -c 'set -u; FC_TIMER_GOLDEN_LOG="$DUMMY_LOG" . "$1" > /dev/null 2>&1; printf "%s" "$2" | grep -qE "$FAIL_CLASS_RE" && echo MATCHED || echo no-match' _ "$REAL_GOLDEN" "$CARRIER_PASS")"
if [ "$UNIT_FC1" = no-match ]; then
  ok "(M3FC-unit) the carrier PASS line is correctly NOT classified as failing (no-match)"
else
  bad "(M3FC-unit) BLIND: carrier PASS line reported '$UNIT_FC1', expected no-match"
fi

echo "=== (M3FC-unit-ctl) non-loophole control: a GENUINE failing line ('...   ✗ ERROR: broken') IS still correctly classified as failing ==="
UNIT_FC2="$(DUMMY_LOG="$DUMMY_LOG" bash -c 'set -u; FC_TIMER_GOLDEN_LOG="$DUMMY_LOG" . "$1" > /dev/null 2>&1; printf "%s" "$2" | grep -qE "$FAIL_CLASS_RE" && echo MATCHED || echo no-match' _ "$REAL_GOLDEN" "$R16GATE_BAD")"
if [ "$UNIT_FC2" = MATCHED ]; then
  ok "(M3FC-unit-ctl) a genuine failing line is still correctly classified as failing -- the S11.4.201(1) false-positive guard: the anchoring did not simply stop matching anything real"
else
  bad "(M3FC-unit-ctl) BLIND: genuine failing line reported '$UNIT_FC2', expected MATCHED"
fi

echo "=== (M-M3FC) guard-viability: revert FAIL_CLASS_RE to the pre-round-16 unanchored (substring-anywhere) form -- the SAME carrier PASS line must now WRONGLY be classified as failing ==="
ANCHOR_M3FC='FAIL_CLASS_RE='"'"'\.\.\.[[:space:]]+(✗|ERROR:|FAIL([^A-Za-z0-9]|$))'"'"
REPL_M3FC='FAIL_CLASS_RE='"'"'(✗|ERROR:|FAIL([^A-Za-z0-9]|$))'"'"'  # MUTANT: R16-M3 verdict-token-position anchor dropped'
if mutate M3FC "$ANCHOR_M3FC" "$REPL_M3FC"; then
  MUT_FC="$(DUMMY_LOG="$DUMMY_LOG" bash -c 'set -u; FC_TIMER_GOLDEN_LOG="$DUMMY_LOG" . "$1" > /dev/null 2>&1; printf "%s" "$2" | grep -qE "$FAIL_CLASS_RE" && echo MATCHED || echo no-match' _ "$TMP/golden_M3FC.sh" "$CARRIER_PASS")"
  if [ "$MUT_FC" = MATCHED ]; then
    ok "(M-M3FC) without the anchor, the SAME carrier PASS line is WRONGLY classified as failing (MATCHED) -- the anchoring fix is genuinely load-bearing"
  else
    bad "(M-M3FC) BLIND: mutant carrier classification reported '$MUT_FC', expected MATCHED"
  fi
else
  bad "(M-M3FC) could not construct the mutation (anchor not found)"
fi

echo
if [ "$fail" = 0 ]; then echo "=== T048 ROUND-16 FINDINGS REGRESSION GUARD (R16-I1/I2/M1/M2/M3): ALL CHECKS PASS ==="; else echo "=== T048 ROUND-16 FINDINGS REGRESSION GUARD (R16-I1/I2/M1/M2/M3): FAILURES ABOVE ==="; fi
exit "$fail"
