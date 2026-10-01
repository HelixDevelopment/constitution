#!/bin/bash
# T048 round-8 independent review findings R8-I3 + R8-M2 regression guard
# for test_fc_timer_golden_output.sh.
#
# R8-I3 (verbatim finding, 2026-10-02): "a sequential triplet is accepted
# across a mid-capture tree change, and the INFO line states something
# false. ... FC0a and FC1 therefore ran against different source trees...
# The golden test still PASSes 13/13 and prints 'tree CHANGED ... all three
# members ran concurrently against the same changing tree, so the FC0a/FC0b
# noise floor carries that drift too'. For a sequential triplet that
# statement is false (S11.4.6). In sequential mode the drift is not
# symmetric across members, so the noise floor cannot carry it."
#
# The fix (same round): a SEQUENTIAL triplet whose tree_head/tree_status
# changed between start and end is now REFUSED (TRIPLET_STATE=refused),
# exactly the way any other non-trustworthy triplet is refused -- never
# compared under a note that is false for the sequential case. A CONCURRENT
# triplet's tree-changed note is unaffected (and, since the sequential+
# changed case is now refused before reaching it, its "ran concurrently"
# claim is always accurate at that point).
#
# HOW THIS FILE TESTS: every case runs the REAL harness (with a stand-in
# pre-build, lib/golden_triplet_fixture.sh) and the REAL golden test end to
# end, with the manifest's tree_head_start/_end and
# tree_status_sha256_start/_end keys edited post-capture to simulate a
# mid-capture tree change (the harness's own brief test-fixture window is too
# short to force a REAL git-tree mutation deterministically; editing the
# manifest's own recorded fields is the same technique
# test_fc_timer_golden_output_r7_regression.sh's set_key() already uses for
# other manifest fields). Each fix is then proven load-bearing by re-running
# the SAME case against a MUTATED COPY of the golden test that restores the
# round-8 (pre-fix) behaviour -- the case's verdict must flip.
#
# Cases:
#  (Q1) a SEQUENTIAL triplet whose tree changed between start and end is
#       REFUSED, never compared, and the refusal reason never claims the
#       members ran concurrently.
#  (Q2) golden-FALSE (S11.4.201(1)): a SEQUENTIAL triplet whose tree did NOT
#       change is still accepted and compared normally (the fix must not
#       over-refuse every sequential triplet).
#  (Q3) golden-FALSE: a CONCURRENT triplet whose tree changed is still
#       accepted and compared, and its tree-changed note still (truthfully,
#       for this case) says "ran concurrently".
#  (Q4) R8-M2 (Minor, defense-in-depth): a manifest claiming
#       concurrency=sequential whose FORGED member epochs genuinely overlap
#       is refused, naming the contradiction.
#  (Q5) golden-FALSE: a sequential manifest whose member epochs only TOUCH
#       at a shared boundary second (one member's finished_epoch == the
#       next member's started_epoch, or all three share one second) is NOT
#       refused -- 1-second epoch granularity legitimately produces this on
#       a fast host/stand-in, measured + fixed this same round (R10b/Q1/Q2
#       in this file's own first run wrongly flagged exactly this before
#       the strict-inequality fix below landed).
# Mutations (applied to a copy of the real golden test, the matching case
# re-run):
#  (M-Q1) drop the round-8 sequential-and-changed refusal -> the mutant
#       WRONGLY compares the (Q1) triplet and prints the false "ran
#       concurrently" claim on a sequential capture.
#  (M-Q4) revert _fc_ranges_overlap()'s strict "-lt"/"-lt" boundary test to
#       the inclusive "-le"/"-le" form -> the mutant WRONGLY refuses (Q5)'s
#       genuinely-sequential touching-boundary triplet.
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

for f in "$GT_HARNESS" "$REAL_GOLDEN"; do
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

# _force_tree_change MANIFEST -- rewrites tree_head_end + tree_status_sha256_end
# to differ from their _start counterparts, simulating a real mid-capture
# commit + tree edit without needing one to genuinely occur inside this
# test's own brief capture window.
_force_tree_change() {
  local mf="$1"
  set_key "$mf" tree_head_end "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  set_key "$mf" tree_status_sha256_end "1111111111111111111111111111111111111111111111111111111111111111"
}

echo "=== (Q1) R8-I3: a SEQUENTIAL triplet whose tree changed during the capture is REFUSED, never compared, never claims 'ran concurrently' ==="
capture "$TMP/q1" "$SAME" 20261002T100000Z t --sequential
_force_tree_change "$TMP/q1/t_20261002T100000Z.triplet"
gt_golden "$TMP/q1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/q1"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/q1.out" "sequential and the tree CHANGED" \
   && has "$TMP/q1.out" "newest triplet refused" \
   && ! has "$TMP/q1.out" "ran concurrently" \
   && ! has "$TMP/q1.out" "IDENTICAL"; then
  ok "(Q1) sequential + tree-changed triplet is refused with an honest reason, never compared, never claims concurrency"
else
  bad "(Q1) rc=$rc; $(grep -E 'INFO:|SKIP|SUMMARY' "$TMP/q1.out" | head -5)"
fi

echo "=== (Q2) golden-FALSE: a SEQUENTIAL triplet whose tree did NOT change is still accepted and compared ==="
capture "$TMP/q2" "$SAME" 20261002T110000Z t --sequential
gt_golden "$TMP/q2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/q2"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/q2.out" "IDENTICAL" && has "$TMP/q2.out" "tree unchanged" \
   && ! has "$TMP/q2.out" "newest triplet refused"; then
  ok "(Q2) a sequential triplet with an unchanged tree is NOT over-refused by the (Q1) fix"
else
  bad "(Q2) rc=$rc; $(grep -E 'INFO:|SKIP|SUMMARY' "$TMP/q2.out" | head -5)"
fi

echo "=== (Q3) golden-FALSE: a CONCURRENT triplet whose tree changed is still accepted and compared, and its concurrency claim is still truthful ==="
capture "$TMP/q3" "$SAME" 20261002T120000Z t
_force_tree_change "$TMP/q3/t_20261002T120000Z.triplet"
gt_golden "$TMP/q3.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/q3"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/q3.out" "IDENTICAL" && has "$TMP/q3.out" "ran concurrently" \
   && ! has "$TMP/q3.out" "newest triplet refused"; then
  ok "(Q3) a concurrent triplet whose tree changed is still compared, and its 'ran concurrently' claim is still accurate for it"
else
  bad "(Q3) rc=$rc; $(grep -E 'INFO:|SKIP|SUMMARY' "$TMP/q3.out" | head -5)"
fi

echo "=== (Q4) R8-M2: a manifest claiming concurrency=sequential but FORGED overlapping member epochs is refused, naming the contradiction ==="
capture "$TMP/q4" "$SAME" 20261002T130000Z t --sequential
Q4MF="$TMP/q4/t_20261002T130000Z.triplet"
set_key "$Q4MF" member.FC0a.started_epoch 1000
set_key "$Q4MF" member.FC0a.finished_epoch 1010
set_key "$Q4MF" member.FC0b.started_epoch 1005
set_key "$Q4MF" member.FC0b.finished_epoch 1015
set_key "$Q4MF" member.FC1.started_epoch 1020
set_key "$Q4MF" member.FC1.finished_epoch 1030
set_key "$Q4MF" started_epoch 1000
set_key "$Q4MF" finished_epoch 1030
gt_golden "$TMP/q4.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/q4"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/q4.out" "contradicts its own recorded timing" \
   && ! has "$TMP/q4.out" "IDENTICAL"; then
  ok "(Q4) a sequential manifest with forged-overlapping member epochs (FC0a/FC0b genuinely overlap) is refused, naming the contradiction"
else
  bad "(Q4) rc=$rc; $(grep -E 'INFO:|SKIP' "$TMP/q4.out" | head -5)"
fi

echo "=== (Q5) golden-FALSE: a SEQUENTIAL manifest whose member epochs only TOUCH at a shared boundary second is NOT refused ==="
capture "$TMP/q5" "$SAME" 20261002T140000Z t --sequential
Q5MF="$TMP/q5/t_20261002T140000Z.triplet"
set_key "$Q5MF" member.FC0a.started_epoch 1000
set_key "$Q5MF" member.FC0a.finished_epoch 1005
set_key "$Q5MF" member.FC0b.started_epoch 1005
set_key "$Q5MF" member.FC0b.finished_epoch 1010
set_key "$Q5MF" member.FC1.started_epoch 1010
set_key "$Q5MF" member.FC1.finished_epoch 1015
set_key "$Q5MF" started_epoch 1000
set_key "$Q5MF" finished_epoch 1015
gt_golden "$TMP/q5.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/q5"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/q5.out" "IDENTICAL" && ! has "$TMP/q5.out" "newest triplet refused"; then
  ok "(Q5) touching-boundary sequential member epochs (finish of one == start of the next) are NOT a false-positive refusal"
else
  bad "(Q5) rc=$rc; $(grep -E 'INFO:|SKIP' "$TMP/q5.out" | head -5)"
fi

# mutate NAME ANCHOR REPLACEMENT -- copy of the real golden test, anchor exactly once
mutate() {
  local hits; hits="$(grep -cF -- "$2" "$REAL_GOLDEN" || true)"
  if [ "$hits" != 1 ]; then bad "($1) control needle: anchor found $hits times (want 1): $2"; return 1; fi
  ANCHOR="$2" REPL="$3" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); s=s.replace(os.environ["ANCHOR"],os.environ["REPL"],1); open(sys.argv[2],"w").write(s)
' "$REAL_GOLDEN" "$TMP/golden_$1.sh"
}
mrun() { GT_GOLDEN="$TMP/golden_$1.sh" gt_golden "$2" FC_TIMER_GOLDEN_EVIDENCE_DIR="$3"; }

echo "=== (M-Q1) drop the round-8 sequential-and-changed refusal ==="
if mutate Q1 '  if [ "$concurrency_mode" = sequential ] && { [ "$hs" != "$he" ] || [ "$ss" != "$se" ]; }; then' '  if false; then'; then
  mrun Q1 "$TMP/mq1.out" "$TMP/q1"
  if has "$TMP/mq1.out" "ran concurrently" && ! has "$TMP/mq1.out" "newest triplet refused"; then
    ok "(M-Q1) without the refusal, the mutant WRONGLY compares (Q1)'s sequential+tree-changed triplet and prints the false 'ran concurrently' claim -- the (Q1) fix is genuinely load-bearing"
  else
    bad "(M-Q1) BLIND: $(grep -E 'INFO:|SKIP' "$TMP/mq1.out" | head -5)"
  fi
fi

echo "=== (M-Q4) revert the strict boundary test to inclusive (the false-positive form measured + fixed this same round) ==="
if mutate Q4 '  [ "$1" -lt "$4" ] && [ "$3" -lt "$2" ]' '  [ "$1" -le "$4" ] && [ "$3" -le "$2" ]'; then
  mrun Q4 "$TMP/mq4.out" "$TMP/q5"
  if has "$TMP/mq4.out" "contradicts its own recorded timing"; then
    ok "(M-Q4) the inclusive-boundary mutant WRONGLY refuses (Q5)'s genuinely-sequential touching-boundary triplet -- the strict-inequality fix is genuinely load-bearing"
  else
    bad "(M-Q4) BLIND: $(grep -E 'INFO:|SKIP' "$TMP/mq4.out" | head -5)"
  fi
fi

echo
if [ "$fail" = 0 ]; then echo "=== T048 ROUND-8 GOLDEN REGRESSION GUARD (R8-I3): ALL CHECKS PASS ==="; else echo "=== T048 ROUND-8 GOLDEN REGRESSION GUARD (R8-I3): FAILURES ABOVE ==="; fi
exit "$fail"
