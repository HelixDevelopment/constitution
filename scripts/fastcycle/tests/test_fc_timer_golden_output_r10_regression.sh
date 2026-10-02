#!/bin/bash
# T048 round-10 independent review findings R10-M3/R10-M4 regression guard
# for test_fc_timer_golden_output.sh (round-11 remediation).
#
# R10-M3 (Minor): only the FC0a-vs-FC0b overlap pairing (Q4 in
# test_fc_timer_golden_output_r8_regression.sh) had a forged-overlap
# fixture; the FC0a-vs-FC1 and FC0b-vs-FC1 pairs were logically covered
# (pairwise check, any genuine three-way overlap implies a pairwise one)
# but untested. This file parameterises Q4 over the other two pairs (Q6,
# Q7) with their own guard-viability mutations.
# R10-M4 (Minor): `concurrency` was never validated against its own closed
# set {concurrent, sequential} -- a missing/duplicated/garbled value made
# BOTH the per-member-isolation refusal AND the sequential-tree-changed
# refusal never fire (both compare against the literal string "sequential"),
# letting a tree-changed capture with an unresolvable concurrency value sail
# through to TRIPLET_STATE=valid printing the false "ran concurrently" claim.
# Fix: validate the closed set once, early, before anything downstream
# relies on the value.
#
# T048 ROUND 21 (R20-I1, S11.4.124): R10-B1 (the known-flaky-gate
# registry's verdict-line exclusion) and R10-I1 (the exit-code noise
# floor) are REMOVED along with the rest of the registry-accounting /
# noise-floor cascade (see the ROUND-21 ARCHITECTURE note in
# test_fc_timer_golden_output.sh) -- both registered flaky gates that
# mechanism existed to work around are now genuinely fixed at their own
# source. This file's own B1-B5 (R10-B1) and E1/E2/M-E/M-E1 (R10-I1)
# cases, which tested ONLY those removed mechanisms, are removed with it,
# in this same commit, citing this note (git history shows their original
# round-10/11 landing for anyone auditing the removal). What remains below
# (Q6/Q7/M-Q6/M-Q7, C1/C2/M-C1) is R10-M3's and R10-M4's own, independent,
# still-relevant validate_triplet() coverage.
#
# R10-I2 (Important): the round-9 SKIP-not-PASS commitment (R8-B1) was
# unguarded by test_fc_timer_golden_output_r4_regression.sh's own
# expect_skip() helper -- MOOT this round: r4_regression.sh itself is
# removed along with the noise-floor multiset classifier it tested (see
# that removal's own commit).
#
# R10-M1 (stale header comment) and R10-M5 (evidence owed, no code change)
# have no test surface of their own and are not covered here. R10-M2 (the
# allow-list evasion finding) is in a DIFFERENT file
# (test_metatest_per_mutant_r4_regression.sh) and is fixed + regression-
# guarded there, not in this file.
#
# HOW THIS FILE TESTS: every case runs the REAL harness (with a stand-in
# pre-build, lib/golden_triplet_fixture.sh) and the REAL golden test end to
# end, exactly like the r5/r7/r8 regression files. Mutations are applied to a
# COPY of the real golden test (never the live file) via the SAME
# content-anchored `mutate()`/`mrun()` pattern those files use, with the
# exact anchor text extracted at RUN TIME from the real file via `grep -F`
# (never hand-transcribed) so a future edit to the real file's wording
# cannot silently desynchronise this file's anchors from reality.
# cannot silently desynchronise this file's anchors from reality.
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

for f in "$GT_HARNESS" "$REAL_GOLDEN"; do
  # intentional ok/bad control-needle idiom; ok()/bad() are print-only reporters that always return 0, so the || branch never spuriously fires
  # shellcheck disable=SC2015
  [ -f "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done

SAME="$TMP/fix_same"
for m in FC0a FC0b FC1; do printf '  ✓ CM-ONE: same\n' | gt_member_text "$SAME" "$m"; done

capture() {  # OUT FIX RUNID PREFIX [harness args...]
  local out="$1" fix="$2" runid="$3" prefix="${4:-t}"; shift 4
  if ! gt_capture "$fix" "$out" "$prefix" "$runid" "$@"; then
    bad "harness failed for $out: $(tail -n 3 "$out/.capture.log")"; return 1
  fi
  gt_promote "$out/${prefix}_${runid}.triplet"
}
set_key() { sed -i "s|^$2=.*|$2=$3|" "$1"; }   # MANIFEST KEY VALUE
has() { grep -qF -- "$2" "$1"; }

_force_tree_change() {
  local mf="$1"
  set_key "$mf" tree_head_end "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  set_key "$mf" tree_status_sha256_end "1111111111111111111111111111111111111111111111111111111111111111"
}

# =============================================================================
# R10-M3 + R10-M4: validate_triplet() overlap-pair + closed-set coverage.
# =============================================================================
mutate() {
  local name="$1" anchor="$2" repl="$3" hits
  hits="$(grep -cF -- "$anchor" "$REAL_GOLDEN" || true)"
  if [ "$hits" != 1 ]; then bad "($name) control needle: anchor found $hits times (want 1): $anchor"; return 1; fi
  ANCHOR="$anchor" REPL="$repl" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); s=s.replace(os.environ["ANCHOR"],os.environ["REPL"],1); open(sys.argv[2],"w").write(s)
' "$REAL_GOLDEN" "$TMP/golden_$name.sh"
}
mrun() { GT_GOLDEN="$TMP/golden_$1.sh" gt_golden "$2" FC_TIMER_GOLDEN_EVIDENCE_DIR="$3"; }

echo "=== (Q6) R10-M3: a manifest claiming concurrency=sequential with a FORGED FC0b-vs-FC1 overlap (FC0a disjoint from both) is refused ==="
capture "$TMP/q6" "$SAME" 20261010T020000Z t --sequential
Q6MF="$TMP/q6/t_20261010T020000Z.triplet"
set_key "$Q6MF" member.FC0a.started_epoch 1000
set_key "$Q6MF" member.FC0a.finished_epoch 1005
set_key "$Q6MF" member.FC0b.started_epoch 1010
set_key "$Q6MF" member.FC0b.finished_epoch 1020
set_key "$Q6MF" member.FC1.started_epoch 1015
set_key "$Q6MF" member.FC1.finished_epoch 1025
set_key "$Q6MF" started_epoch 1000
set_key "$Q6MF" finished_epoch 1025
gt_golden "$TMP/q6.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/q6"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/q6.out" "contradicts its own recorded timing" && ! has "$TMP/q6.out" "IDENTICAL"; then
  ok "(Q6) a sequential manifest with a forged FC0b-vs-FC1 overlap (FC0a disjoint from both) is refused, naming the contradiction"
else
  bad "(Q6) rc=$rc; $(grep -E 'INFO:|SKIP' "$TMP/q6.out" | head -5)"
fi

echo "=== (Q7) R10-M3: a manifest claiming concurrency=sequential with a FORGED FC0a-vs-FC1 overlap (FC0b disjoint from both) is refused ==="
capture "$TMP/q7" "$SAME" 20261010T030000Z t --sequential
Q7MF="$TMP/q7/t_20261010T030000Z.triplet"
set_key "$Q7MF" member.FC0a.started_epoch 1000
set_key "$Q7MF" member.FC0a.finished_epoch 1020
set_key "$Q7MF" member.FC1.started_epoch 1010
set_key "$Q7MF" member.FC1.finished_epoch 1030
set_key "$Q7MF" member.FC0b.started_epoch 1040
set_key "$Q7MF" member.FC0b.finished_epoch 1050
set_key "$Q7MF" started_epoch 1000
set_key "$Q7MF" finished_epoch 1050
gt_golden "$TMP/q7.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/q7"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/q7.out" "contradicts its own recorded timing" && ! has "$TMP/q7.out" "IDENTICAL"; then
  ok "(Q7) a sequential manifest with a forged FC0a-vs-FC1 overlap (FC0b disjoint from both) is refused, naming the contradiction"
else
  bad "(Q7) rc=$rc; $(grep -E 'INFO:|SKIP' "$TMP/q7.out" | head -5)"
fi

echo "=== (M-Q6) guard-viability: drop the FC0b-vs-FC1 overlap term -- (Q6) must wrongly be accepted ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
Q6_ANCHOR="$(grep -F '_fc_ranges_overlap "$_ep_b_s" "$_ep_b_f" "$_ep_1_s" "$_ep_1_f"; then' "$REAL_GOLDEN")"
# T048 round 14 (m5): hoisted into its own narrowly-scoped assignment -- a
# `# shellcheck disable` placed directly above an `if ...; then ... fi`
# compound command suppresses that code for the WHOLE if-block body, wider
# than the single literal substitution that actually needs it.
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
Q6_REPL="$(printf '%s' "$Q6_ANCHOR" | sed -E 's/\|\| _fc_ranges_overlap.*\$_ep_1_f"/|| false/')"
if [ -n "$Q6_ANCHOR" ] && mutate Q6 "$Q6_ANCHOR" "$Q6_REPL"; then
  mrun Q6 "$TMP/mq6.out" "$TMP/q6"
  if has "$TMP/mq6.out" "IDENTICAL" && ! has "$TMP/mq6.out" "contradicts its own recorded timing"; then
    ok "(M-Q6) without the FC0b-vs-FC1 overlap term, the mutant WRONGLY accepts (Q6)'s forged-overlapping manifest -- that term is genuinely load-bearing"
  else
    bad "(M-Q6) BLIND: $(grep -E 'INFO:|SKIP' "$TMP/mq6.out" | head -5)"
  fi
else
  bad "(M-Q6) could not construct the mutation (anchor not found)"
fi

echo "=== (M-Q7) guard-viability: drop the FC0a-vs-FC1 overlap term -- (Q7) must wrongly be accepted ==="
# intentional literal grep -F / sed anchor pattern with an embedded escaped single quote -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC1003,SC2016
Q7_ANCHOR="$(grep -F '_fc_ranges_overlap "$_ep_a_s" "$_ep_a_f" "$_ep_1_s" "$_ep_1_f" \' "$REAL_GOLDEN")"
# T048 round 14 (m5): hoisted into its own narrowly-scoped assignment (see
# the Q6_REPL comment above for why).
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
Q7_REPL="$(printf '%s' "$Q7_ANCHOR" | sed -E 's/\|\| _fc_ranges_overlap.*\$_ep_1_f" \\/|| false \\/')"
if [ -n "$Q7_ANCHOR" ] && mutate Q7 "$Q7_ANCHOR" "$Q7_REPL"; then
  mrun Q7 "$TMP/mq7.out" "$TMP/q7"
  if has "$TMP/mq7.out" "IDENTICAL" && ! has "$TMP/mq7.out" "contradicts its own recorded timing"; then
    ok "(M-Q7) without the FC0a-vs-FC1 overlap term, the mutant WRONGLY accepts (Q7)'s forged-overlapping manifest -- that term is genuinely load-bearing"
  else
    bad "(M-Q7) BLIND: $(grep -E 'INFO:|SKIP' "$TMP/mq7.out" | head -5)"
  fi
else
  bad "(M-Q7) could not construct the mutation (anchor not found)"
fi

# =============================================================================
# R10-M4: concurrency closed-set validation.
# =============================================================================
echo "=== (C1) R10-M4: an INVALID concurrency value ('garbage') with a forced tree change is REFUSED, never silently treated as concurrent ==="
capture "$TMP/c1" "$SAME" 20261010T040000Z t --sequential
C1MF="$TMP/c1/t_20261010T040000Z.triplet"
_force_tree_change "$C1MF"
set_key "$C1MF" concurrency garbage
gt_golden "$TMP/c1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/c1"; rc=$?
if [ "$rc" = 1 ] && has "$TMP/c1.out" "not one of the closed set" && ! has "$TMP/c1.out" "ran concurrently" && ! has "$TMP/c1.out" "IDENTICAL"; then
  ok "(C1) a garbled concurrency value is refused (FAIL) naming the closed-set violation, never silently compared"
else
  bad "(C1) rc=$rc; $(grep -E 'FAIL|INFO:' "$TMP/c1.out" | head -5)"
fi

echo "=== (C2) R10-M4: a DUPLICATED concurrency key (so _mf_get returns empty) with a forced tree change is REFUSED the same way ==="
capture "$TMP/c2" "$SAME" 20261010T050000Z t --sequential
C2MF="$TMP/c2/t_20261010T050000Z.triplet"
_force_tree_change "$C2MF"
printf 'concurrency=sequential\n' >> "$C2MF"
gt_golden "$TMP/c2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/c2"; rc=$?
if [ "$rc" = 1 ] && has "$TMP/c2.out" "not one of the closed set" && ! has "$TMP/c2.out" "ran concurrently" && ! has "$TMP/c2.out" "IDENTICAL"; then
  ok "(C2) a duplicated concurrency key (ambiguous -> _mf_get returns empty) is refused the same way as a garbled value"
else
  bad "(C2) rc=$rc; $(grep -E 'FAIL|INFO:' "$TMP/c2.out" | head -5)"
fi

echo "=== (M-C1) guard-viability: bypass the new closed-set validation entirely -- (C1) must reproduce the pre-fix false 'ran concurrently' claim ==="
if mutate C1 '    concurrent|sequential) : ;;' '    concurrent|sequential|*) : ;;  # MUTANT: * now matches too, bypassing the refusal branch below'; then
  mrun C1 "$TMP/mc1.out" "$TMP/c1"
  if has "$TMP/mc1.out" "IDENTICAL" && ! has "$TMP/mc1.out" "not one of the closed set"; then
    ok "(M-C1) with the closed-set validation bypassed, the mutant reproduces the pre-fix behaviour -- it no longer refuses (C1)'s garbled-concurrency manifest and WRONGLY compares it, printing a false IDENTICAL verdict for a value that was never proven to be either concurrent or sequential; the validation is genuinely load-bearing"
  else
    bad "(M-C1) BLIND: $(grep -E 'FAIL|INFO:' "$TMP/mc1.out" | head -5)"
  fi
else
  bad "(M-C1) could not construct the mutation (anchor not found)"
fi

echo
if [ "$fail" = 0 ]; then echo "=== T048 ROUND-10 FINDINGS REGRESSION GUARD (R10-M3/M4): ALL CHECKS PASS ==="; else echo "=== T048 ROUND-10 FINDINGS REGRESSION GUARD (R10-M3/M4): FAILURES ABOVE ==="; fi
exit "$fail"
