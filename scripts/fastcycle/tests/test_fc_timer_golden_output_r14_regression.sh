#!/bin/bash
# T048 round-14 independent review finding R14-I2 regression guard for
# test_fc_timer_golden_output.sh (round-15 remediation).
#
# R14-I2 (Important, pre-existing, surfaced by this review): VERDICT_RE
# never matched the ~640-per-real-run "<GATE-ID>: ... OK" / "... FAIL[:]"
# direct-ERRORS-increment lines, nor the real "WARNING:" text log_warn()
# prints (the old pattern's "WARN:" literal never occurs in the shipped
# script). FR-002/T-A01's "verdict set is IDENTICAL" claim silently excluded
# both shapes from the comparison. Fix (round 15): VERDICT_RE now also
# matches the real OK/FAIL-style shape (word-bounded, "... " + OK/FAIL) and
# "WARNING:" -- a mechanism that is NOT part of the S11.4.250 heuristic
# tower T048 round 21 removes (VERDICT_RE is the base verdict-line
# EXTRACTION regex, used by every check in the golden test, not an
# explain-away layer) -- so this coverage remains load-bearing and is kept.
#
# T048 ROUND 21 (R20-I1, S11.4.124): R14-I1's own finding -- the
# "registered gate's recorded line genuinely differs" exit-code elif and
# its exact-accounting Failed:-N-delta fix -- is REMOVED along with the
# rest of the registry-accounting cascade it belongs to (see the ROUND-21
# ARCHITECTURE note in test_fc_timer_golden_output.sh). This file's own
# ADV1/ADV1-ctl/ADV2/M-I1-delta cases, which tested ONLY that removed
# mechanism, are removed with it, in this same commit, citing this note
# (git history: `git log -- scripts/fastcycle/tests/
# test_fc_timer_golden_output_r14_regression.sh` shows their original
# round-14/15 landing for anyone auditing the removal). What remains below
# (ADV3/ADV4/M-I2-verdictre) is R14-I2's own, independent, still-relevant
# coverage of VERDICT_RE's extraction correctness.
#
# HOW THIS FILE TESTS: every case runs the REAL harness (with a stand-in
# pre-build, lib/golden_triplet_fixture.sh) and the REAL golden test end to
# end, exactly like the r5/r7/r8/r10 regression files. Mutations are
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
has() { grep -qF -- "$2" "$1"; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
gt_init "$TMP/work"

for f in "$GT_HARNESS" "$REAL_GOLDEN"; do
  # intentional ok/bad control-needle idiom; ok()/bad() are print-only reporters that always return 0, so the || branch never spuriously fires
  # shellcheck disable=SC2015
  [ -f "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done

# triplet NAME SEQ FC0a-text FC0b-text FC1-text -- real harness capture +
# promotion. SEQ is a small distinguishing digit so each case's run_id is
# unique (YYYYMMDDTHHMMSSZ format the manifest format requires).
triplet() {
  local name="$1" fix="$TMP/fix_$1" out="$TMP/ev_$1" runid
  runid="202614$(printf '%02d' "$2")T000000Z"
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

# A CLEAN baseline (no pre-existing failure) -- deliberately NOT the older
# regression files' BASE const (which always carries one failing CM-TWO
# line) so each fixture's own "  Failed:       N" value is simple to
# compute by inspection.
CBASE='  ✓ CM-ONE: clean baseline gate'
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
# NOT apply the override -- this was originally explained at length in
# r12_regression.sh's own mrun() comment, removed T048 round 21 along with
# the rest of that file, S11.4.124) is what actually works.
# intentional word-splitting -- $envassigns is a caller-supplied multi-assignment prefix string (e.g. 'A=1 B=2') that MUST split into separate env assignments, quoting it would break that
# shellcheck disable=SC2086
mrun() { local name="$1" envassigns="$2" outfile="$3"; GT_GOLDEN="$TMP/golden_$name.sh" gt_golden "$outfile" $envassigns; }


echo "=== (ADV3) R14-I2 exact repro: an OK/FAIL-style gate flips OK->FAIL in FC1 only, exit codes held EQUAL (isolating the verdict-SET check from the exit-code check) -- check [verdict-set] must FAIL, not silently PASS ==="
triplet ADV3 4 "$CBASE
$OKSTYLE_OK" "$CBASE
$OKSTYLE_OK" "$CBASE
$OKSTYLE_BAD" "0 0 0"
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
$WARNSTYLE_FC1_ONLY" "0 0 0"
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
if [ "$fail" = 0 ]; then echo "=== T048 ROUND-14 FINDINGS REGRESSION GUARD (R14-I2): ALL CHECKS PASS ==="; else echo "=== T048 ROUND-14 FINDINGS REGRESSION GUARD (R14-I2): FAILURES ABOVE ==="; fi
exit "$fail"
