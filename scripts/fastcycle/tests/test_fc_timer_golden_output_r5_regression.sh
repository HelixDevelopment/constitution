#!/bin/bash
# T048 round-5 findings R5-I2 + m3 regression guard for
# test_fc_timer_golden_output.sh (rewritten in round 6).
#
# R5-I2 (round-5 review): the golden test's auto-discovery paired a without-
# timers log and a with-timers log 182,792 s (~2.1 days) apart, called the
# noise floor "SAME-WINDOW" without measuring anything, and reported a false
# "genuine candidate". The reviewer's S11.4.250 assessment: stop adding pairing
# heuristics; REQUIRE a same-run triplet. Round 6 did exactly that -- the
# golden test now pairs nothing and compares only a validated triplet produced
# by capture_fc_timer_triplet.sh.
#
# m3 (round-5 review): nothing verified that a log was really captured with
# the timer setting its filename claims. Round 6 fixes it at the source: each
# triplet member's own section TSV sits at an exact, member-unique path, and
# the golden test re-counts it.
#
# HOW THIS FILE TESTS: every case runs the REAL harness (with a stand-in
# pre-build, lib/golden_triplet_fixture.sh) and the REAL golden test end to
# end. No code is extracted from either file. Each load-bearing check is then
# proven by running the SAME case against a MUTATED COPY of the golden test,
# including the round-5 reviewer's own named fix target for R5-I2 ("enforce a
# declared maximum ... window"): deleting the window refusal must turn the
# out-of-window case from an honest SKIP into a comparison.
#
# Cases:
#  (S1) reviewer's R5-I2 repro shape: old without-timers + new with-timers logs
#       182,792 s apart, differing, no triplet -> honest SKIP, exit 0, no
#       comparison, no "SAME-WINDOW", no mismatch.
#  (S2) valid identical triplet -> FR-002 PASS.
#  (S3) triplet spanning 3601 s > 3600 s default -> refused (SKIP), even though
#       its logs differ; FC_TIMER_GOLDEN_MAX_WINDOW_S=7200 accepts the same
#       triplet; a non-integer window is a FATAL usage error (exit 2).
#  (S4) m3: FC1 claims timers ON but wrote no TSV rows -> FAIL.
#  (S5) m3: FC0b claims timers OFF but wrote TSV rows -> FAIL.
#  (S6) m3: a member's TSV changed after capture (re-count != manifest) -> FAIL.
#  (S7) integrity: a member log edited after capture -> FAIL.
#  (S8) newest manifest invalid, an older valid one exists -> FAIL naming the
#       newest; the older one is NOT silently used instead.
#  (S9) auto-discovery ignores stand-in manifests; a pinned stand-in is
#       refused (SKIP).
#  (S10) a duplicated manifest key is malformed -> FAIL.
#  (M*) mutations of the golden test copy -- each must flip its case.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/golden_triplet_fixture.sh
# the sourced fixture lib exists (see the source= hint above); the precheck runs shellcheck without -x so it cannot follow it
# shellcheck disable=SC1091
. "$HERE/lib/golden_triplet_fixture.sh"
REAL_GOLDEN="$GT_GOLDEN"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "NOT ok $1"; fail=1; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
gt_init "$TMP/work"

# control needle: both real files resolve
for f in "$GT_HARNESS" "$REAL_GOLDEN"; do
  # ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
  # shellcheck disable=SC2015
  [ -f "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done

# Verdict text every fixture starts from.
SAME="$TMP/fix_same"
for m in FC0a FC0b FC1; do
  printf '  ✓ CM-ONE: first\n  ✗ CM-TWO: second\nWARN: CM-THREE: third\n' | gt_member_text "$SAME" "$m"
done
DIFF_FIX="$TMP/fix_diff"
mkdir -p "$DIFF_FIX"
for m in FC0a FC0b; do cp "$SAME/$m.txt" "$DIFF_FIX/$m.txt"; done
printf '  ✓ CM-ONE: first\n  ✓ CM-TWO: second\nWARN: CM-THREE: third\n' | gt_member_text "$DIFF_FIX" FC1

# capture ID OUT FIX RUNID [promote=1] -- real harness + optional promotion
capture() {
  local out="$1" fix="$2" runid="$3" promote="${4:-1}"
  if ! gt_capture "$fix" "$out" t "$runid"; then
    bad "harness failed for $out: $(tail -n 3 "$out/.capture.log")"
    return 1
  fi
  [ "$promote" = 1 ] && gt_promote "$out/t_${runid}.triplet"
  return 0
}
has()    { grep -qF -- "$2" "$1"; }
# set_span MANIFEST SECONDS -- fixture edit: rewrite finished_epoch
set_span() {
  local s; s="$(sed -n 's/^started_epoch=//p' "$1")"
  sed -i "s/^finished_epoch=.*/finished_epoch=$((s + $2))/" "$1"
}

echo "=== (S1) R5-I2 repro: two unrelated captures 182792s apart are never compared ==="
S1="$TMP/s1"; mkdir -p "$S1"
cp "$SAME/FC0a.txt" "$S1/prebuild_full_run_t029_t029_full_20260928T124322Z.log"
cp "$SAME/FC0a.txt" "$S1/prebuild_full_run_20260928T050150Z.log"
cp "$DIFF_FIX/FC1.txt" "$S1/prebuild_with_timers_full_run_20260930T152954Z.log"
gt_golden "$TMP/s1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$S1"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/s1.out" "SKIP[" && has "$TMP/s1.out" "no valid same-run triplet" \
   && ! has "$TMP/s1.out" "MISMATCH" && ! has "$TMP/s1.out" "SAME-WINDOW" && ! has "$TMP/s1.out" "NOISE-FLOOR"; then
  ok "(S1) no triplet -> honest SKIP, exit 0, no comparison, no SAME-WINDOW claim"
else
  bad "(S1) rc=$rc; output: $(grep -E 'FAIL|SKIP|MISMATCH|SAME-WINDOW' "$TMP/s1.out" | head -5)"
fi

echo "=== (S2) a valid identical triplet -> FR-002 PASS ==="
capture "$TMP/s2" "$SAME" 20261001T000000Z
gt_golden "$TMP/s2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s2"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/s2.out" "PASS[" && has "$TMP/s2.out" "FR-002/T-A01: with-timers verdict set is IDENTICAL" \
   && has "$TMP/s2.out" "same-run triplet 20261001T000000Z" && has "$TMP/s2.out" "provenance (m3)"; then
  ok "(S2) valid triplet compared, FR-002 PASS, provenance asserted"
else
  bad "(S2) rc=$rc; $(grep -E 'FAIL|SKIP|INFO' "$TMP/s2.out" | head -5)"
fi

echo "=== (S3) R5-I2: a triplet outside the declared window is refused, never compared ==="
capture "$TMP/s3" "$DIFF_FIX" 20261001T010000Z
set_span "$TMP/s3/t_20261001T010000Z.triplet" 3601
gt_golden "$TMP/s3.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s3"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/s3.out" "spans 3601s, more than the 3600s maximum" && ! has "$TMP/s3.out" "MISMATCH"; then
  ok "(S3) 3601s triplet refused with an honest SKIP (its differing logs were NOT compared)"
else
  bad "(S3) rc=$rc; $(grep -E 'FAIL|SKIP|INFO' "$TMP/s3.out" | head -5)"
fi
gt_golden "$TMP/s3b.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s3" FC_TIMER_GOLDEN_MAX_WINDOW_S=7200; rc=$?
if [ "$rc" = 1 ] && has "$TMP/s3b.out" "MISMATCH" && has "$TMP/s3b.out" "3601s span (<= 7200s)"; then
  ok "(S3b) the declared window is honoured: 7200s accepts the same triplet, whose real mismatch then FAILs"
else
  bad "(S3b) rc=$rc; $(grep -E 'FAIL|SKIP|INFO' "$TMP/s3b.out" | head -5)"
fi
gt_golden "$TMP/s3c.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s3" FC_TIMER_GOLDEN_MAX_WINDOW_S=abc; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 2 ] && has "$TMP/s3c.out" "not a positive integer" \
  && ok "(S3c) a non-integer window is a FATAL usage error (exit 2), never silently defaulted" \
  || bad "(S3c) rc=$rc"

echo "=== (S4) m3: FC1 claims timers ON but its own TSV has no rows ==="
S4F="$TMP/fix_s4"; cp -r "$SAME" "$S4F"; echo 0 > "$S4F/FC1.rows"
capture "$TMP/s4" "$S4F" 20261001T020000Z
gt_golden "$TMP/s4.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s4"; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 1 ] && has "$TMP/s4.out" "claims timers ON but its own TSV" \
  && ok "(S4) timers-ON claim without TSV rows is a FAIL" || bad "(S4) rc=$rc; $(grep -E 'FAIL|SKIP' "$TMP/s4.out" | head -3)"

echo "=== (S5) m3: FC0b claims timers OFF but its own TSV has rows ==="
S5F="$TMP/fix_s5"; cp -r "$SAME" "$S5F"; echo 3 > "$S5F/FC0b.rows"
capture "$TMP/s5" "$S5F" 20261001T030000Z
gt_golden "$TMP/s5.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s5"; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 1 ] && has "$TMP/s5.out" "member FC0b claims timers OFF" \
  && ok "(S5) timers-OFF claim with TSV rows is a FAIL" || bad "(S5) rc=$rc; $(grep -E 'FAIL|SKIP' "$TMP/s5.out" | head -3)"

echo "=== (S6) m3: a member TSV re-counted on disk disagrees with the manifest ==="
capture "$TMP/s6" "$SAME" 20261001T040000Z
printf 'EXTRA\t1\n' >> "$TMP/s6/tsv/20261001T040000Z_t_FC1/prebuild_sections.tsv"
gt_golden "$TMP/s6.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s6"; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 1 ] && has "$TMP/s6.out" "has 3 data rows now, the manifest recorded 2" \
  && ok "(S6) TSV re-count mismatch is a FAIL" || bad "(S6) rc=$rc; $(grep -E 'FAIL|SKIP' "$TMP/s6.out" | head -3)"

echo "=== (S7) integrity: a member log edited after capture ==="
capture "$TMP/s7" "$SAME" 20261001T050000Z
echo "  ✓ CM-INJECTED: added later" >> "$TMP/s7/t_FC1_20261001T050000Z.log"
gt_golden "$TMP/s7.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s7"; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 1 ] && has "$TMP/s7.out" "does not match the manifest's" \
  && ok "(S7) edited member log is a FAIL" || bad "(S7) rc=$rc; $(grep -E 'FAIL|SKIP' "$TMP/s7.out" | head -3)"

echo "=== (S8) newest manifest invalid: no silent fall-back to an older valid one ==="
capture "$TMP/s8" "$SAME" 20261001T060000Z
capture "$TMP/s8" "$S4F" 20261001T070000Z
gt_golden "$TMP/s8.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s8"; rc=$?
if [ "$rc" = 1 ] && has "$TMP/s8.out" "t_20261001T070000Z.triplet" && ! has "$TMP/s8.out" "same-run triplet 20261001T060000Z"; then
  ok "(S8) the invalid NEWEST triplet is reported; the older one is not quietly substituted"
else
  bad "(S8) rc=$rc; $(grep -E 'FAIL|SKIP|INFO' "$TMP/s8.out" | head -4)"
fi

echo "=== (S9) stand-in manifests are never FR-002 evidence ==="
capture "$TMP/s9" "$SAME" 20261001T080000Z 0
cp "$SAME/FC0a.txt" "$TMP/s9/prebuild_full_run_20261001T075900Z.log"   # single-log baseline so the run reaches its verdict
gt_golden "$TMP/s9.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s9"; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 0 ] && has "$TMP/s9.out" "no triplet manifest in" \
  && ok "(S9a) auto-discovery ignores a stand-in manifest" || bad "(S9a) rc=$rc; $(grep -E 'FAIL|SKIP|INFO' "$TMP/s9.out" | head -3)"
gt_golden "$TMP/s9b.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s9" FC_TIMER_GOLDEN_TRIPLET="$TMP/s9/t_20261001T080000Z.triplet"; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 0 ] && has "$TMP/s9b.out" "stand-in capture (mode=stand-in)" && ! has "$TMP/s9b.out" "IDENTICAL" \
  && ok "(S9b) a pinned stand-in is validated but its comparison is refused" || bad "(S9b) rc=$rc; $(grep -E 'FAIL|SKIP|INFO' "$TMP/s9b.out" | head -3)"

echo "=== (S10) a duplicated manifest key is malformed, never resolved by picking one ==="
capture "$TMP/s10" "$SAME" 20261001T090000Z
echo "format=fc_timer_triplet/v1" >> "$TMP/s10/t_20261001T090000Z.triplet"
gt_golden "$TMP/s10.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s10"; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 1 ] && has "$TMP/s10.out" "malformed manifest" \
  && ok "(S10) duplicate key -> malformed -> FAIL" || bad "(S10) rc=$rc; $(grep -E 'FAIL|SKIP' "$TMP/s10.out" | head -3)"

# ---------------------------------------------------------------------------
# Mutations: each is applied to a COPY of the real golden test and the SAME
# case re-run; the case's verdict must flip. A mutation whose anchor is not
# found exactly once is itself a failure (control needle).
# ---------------------------------------------------------------------------
# mutate NAME ANCHOR REPLACEMENT -- writes $TMP/golden_NAME.sh
mutate() {
  local name="$1" anchor="$2" repl="$3" hits
  hits="$(grep -cF -- "$anchor" "$REAL_GOLDEN" || true)"
  if [ "$hits" != 1 ]; then
    bad "($name) control needle: anchor found $hits times (want 1): $anchor"; return 1
  fi
  ANCHOR="$anchor" REPL="$repl" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); s=s.replace(os.environ["ANCHOR"],os.environ["REPL"],1); open(sys.argv[2],"w").write(s)
' "$REAL_GOLDEN" "$TMP/golden_$name.sh"
}

echo "=== (M-R5I2) reviewer's R5-I2 fix target removed: no window enforcement ==="
# single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
# shellcheck disable=SC2016
if mutate window 'if [ "$span" -gt "$MAX_WINDOW_S" ]; then' 'if false; then'; then
  GT_GOLDEN="$TMP/golden_window.sh" gt_golden "$TMP/m1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s3"; rc=$?
  # ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
  # shellcheck disable=SC2015
  [ "$rc" = 1 ] && has "$TMP/m1.out" "MISMATCH" \
    && ok "(M-R5I2) without the window check the out-of-window triplet IS compared (rc=1) -- (S3) is load-bearing" \
    || bad "(M-R5I2) BLIND: rc=$rc"
fi

echo "=== (M-m3a) timers-ON-without-rows refusal removed ==="
# single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
# shellcheck disable=SC2016
if mutate m3a 'if [ "$want_timing" = 1 ] && [ "$rows" -eq 0 ]; then' 'if false; then'; then
  GT_GOLDEN="$TMP/golden_m3a.sh" gt_golden "$TMP/m2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s4"; rc=$?
  # ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
  # shellcheck disable=SC2015
  [ "$rc" = 0 ] && ok "(M-m3a) without the check (S4) passes -- (S4) is load-bearing" || bad "(M-m3a) BLIND: rc=$rc"
fi

echo "=== (M-m3b) timers-OFF-with-rows refusal removed ==="
# single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
# shellcheck disable=SC2016
if mutate m3b 'if [ "$want_timing" = 0 ] && [ "$rows" -ne 0 ]; then' 'if false; then'; then
  GT_GOLDEN="$TMP/golden_m3b.sh" gt_golden "$TMP/m3.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s5"; rc=$?
  # ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
  # shellcheck disable=SC2015
  [ "$rc" = 0 ] && ok "(M-m3b) without the check (S5) passes -- (S5) is load-bearing" || bad "(M-m3b) BLIND: rc=$rc"
fi

echo "=== (M-m3c) TSV re-count removed ==="
# single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
# shellcheck disable=SC2016
if mutate m3c 'if [ "$recount" != "$rows" ]; then' 'if false; then'; then
  GT_GOLDEN="$TMP/golden_m3c.sh" gt_golden "$TMP/m4.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s6"; rc=$?
  # ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
  # shellcheck disable=SC2015
  [ "$rc" = 0 ] && ok "(M-m3c) without the re-count (S6) passes -- (S6) is load-bearing" || bad "(M-m3c) BLIND: rc=$rc"
fi

echo "=== (M-sha) log integrity check removed ==="
# single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
# shellcheck disable=SC2016
if mutate sha 'if [ "$sha" != "$want_sha" ]; then' 'if false; then'; then
  GT_GOLDEN="$TMP/golden_sha.sh" gt_golden "$TMP/m5.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s7"; rc=$?
  # ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
  # shellcheck disable=SC2015
  has "$TMP/m5.out" "MISMATCH" && ! has "$TMP/m5.out" "does not match the manifest's" \
    && ok "(M-sha) without the sha check (S7)'s tamper goes unreported -- (S7) is load-bearing" || bad "(M-sha) BLIND: rc=$rc"
fi

echo "=== (M-standin) auto-discovery accepts stand-in manifests ==="
# (anchor updated in round 7: R6-I1 rewrote discovery so that only a
# well-formed stand-in is skipped; the mutation still deletes that skip.)
# single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
# shellcheck disable=SC2016
if mutate standin '[ "$_mode" = stand-in ] && continue' ':'; then
  GT_GOLDEN="$TMP/golden_standin.sh" gt_golden "$TMP/m6.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s9"; rc=$?
  # ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
  # shellcheck disable=SC2015
  ! has "$TMP/m6.out" "no triplet manifest in" \
    && ok "(M-standin) the mutant consumes the stand-in manifest -- (S9a) is load-bearing" || bad "(M-standin) BLIND: rc=$rc"
fi

echo "=== (M-dupkey) duplicate keys silently resolved to the first value ==="
# single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
# shellcheck disable=SC2016
if mutate dupkey '[ "${n:-0}" = 1 ] || return 1' '[ "${n:-0}" -ge 1 ] || return 1'; then
  # single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
  # shellcheck disable=SC2016
  sed -i 's/sed -n "s\/^$1=\/\/p" "$2"/sed -n "s\/^$1=\/\/p" "$2" | head -n1/' "$TMP/golden_dupkey.sh"
  GT_GOLDEN="$TMP/golden_dupkey.sh" gt_golden "$TMP/m7.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/s10"; rc=$?
  # ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
  # shellcheck disable=SC2015
  [ "$rc" = 0 ] && ok "(M-dupkey) without the exactly-once rule (S10) passes -- (S10) is load-bearing" || bad "(M-dupkey) BLIND: rc=$rc"
fi

echo
if [ "$fail" = 0 ]; then echo "=== R5-I2/m3 REGRESSION GUARD: ALL CHECKS PASS ==="; else echo "=== R5-I2/m3 REGRESSION GUARD: FAILURES ABOVE ==="; fi
exit "$fail"
