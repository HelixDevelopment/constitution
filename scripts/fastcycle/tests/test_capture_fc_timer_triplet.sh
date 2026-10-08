#!/bin/bash
# Tests for capture_fc_timer_triplet.sh (T048 round 6): the harness that
# produces the only evidence test_fc_timer_golden_output.sh compares.
#
# Runs the REAL harness against a stand-in pre-build (lib/golden_triplet_fixture.sh)
# and asserts what it wrote, then feeds its output to the REAL golden test.
#
#  (H1) one run-id shared by all three logs + the manifest; manifest written
#  (H2) each member really ran with its labelled FC_TIMING (the stand-in
#       echoes the value it saw) and its own exact TSV path
#  (H3) manifest log sha256 values match the files on disk
#  (H4) default concurrency: all three members started before any finished
#  (H5) --sequential: each member starts after the previous one finished
#  (H6) a stand-in run is recorded mode=stand-in (never "real")
#  (H7) refuses to overwrite an existing manifest; rejects a prefix with "_"
#  (H8) end to end: harness output (promoted) is accepted by the golden test
#  (M-timing) mutant harness gives FC0b timers ON -> the golden test refuses
#       the triplet (proves (H2)+(H8) together catch a mislabelled member)
#  (H9) round 7 (R6-B1): each member gets its own private TMPDIR, recorded in
#       the manifest as tmpdir_isolation=per-member
#  (H10) the R6-B1 MECHANISM reproduced in the stand-in (a fixed ${TMPDIR}/<name>
#       evidence dir rm -rf'd at start): no member's evidence is clobbered
#  (M-tmpdir) mutant harness without per-member TMPDIR -> (H10)'s collision appears
#  (M-concurrent) mutant harness that silently serialises the members while
#       still labelling the run "concurrent" -> the (H4) overlap check catches it
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/golden_triplet_fixture.sh
# the sourced fixture lib exists (see the source= hint above); the precheck runs shellcheck without -x so it cannot follow it
# shellcheck disable=SC1091
. "$HERE/lib/golden_triplet_fixture.sh"
REAL_HARNESS="$GT_HARNESS"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "NOT ok $1"; fail=1; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
gt_init "$TMP/work"
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ -f "$REAL_HARNESS" ] && ok "control needle: $REAL_HARNESS resolves" || bad "control needle: harness missing"

FIX="$TMP/fix"
for m in FC0a FC0b FC1; do printf '  ✓ CM-ONE: %s\n' same | gt_member_text "$FIX" "$m"; done
RID=20261001T130000Z
mf_get() { sed -n "s/^$1=//p" "$2"; }

echo "=== (H1)-(H4),(H6) default concurrent capture ==="
GT_FIX_SLEEP=2 gt_capture "$FIX" "$TMP/a" t "$RID"; rc=$?
MF="$TMP/a/t_${RID}.triplet"
if [ "$rc" = 0 ] && [ -f "$MF" ] && [ -f "$TMP/a/t_FC0a_${RID}.log" ] && [ -f "$TMP/a/t_FC0b_${RID}.log" ] && [ -f "$TMP/a/t_FC1_${RID}.log" ] \
   && [ "$(mf_get run_id "$MF")" = "$RID" ]; then
  ok "(H1) 3 logs + manifest share run-id $RID"
else
  bad "(H1) rc=$rc; $(cat "$TMP/a/.capture.log" | tail -n 3)"
fi
h2=1
for m in FC0a FC0b FC1; do
  want=0; [ "$m" = FC1 ] && want=1
  grep -qxF "stand-in member=$m FC_TIMING=$want" "$TMP/a/t_${m}_${RID}.log" || h2=0
  [ "$(mf_get "member.$m.fc_timing" "$MF")" = "$want" ] || h2=0
  [ "$(mf_get "member.$m.tsv" "$MF")" = "$TMP/a/tsv/${RID}_t_${m}/prebuild_sections.tsv" ] || h2=0
done
[ "$(mf_get member.FC1.tsv_rows "$MF")" = 2 ] && [ "$(mf_get member.FC0a.tsv_rows "$MF")" = 0 ] || h2=0
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$h2" = 1 ] && ok "(H2) each member ran with its labelled FC_TIMING and its own exact TSV path (FC1 2 rows, FC0a 0)" || bad "(H2) per-member provenance wrong: $(grep -E 'fc_timing|tsv' "$MF")"
h3=1
for m in FC0a FC0b FC1; do
  [ "$(sha256sum "$TMP/a/t_${m}_${RID}.log" | awk '{print $1}')" = "$(mf_get "member.$m.log_sha256" "$MF")" ] || h3=0
done
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$h3" = 1 ] && ok "(H3) manifest sha256 values match the logs" || bad "(H3) sha mismatch"
# concurrency: latest start <= earliest finish (each member sleeps 2s)
starts="$(for m in FC0a FC0b FC1; do mf_get "member.$m.started_epoch" "$MF"; done | sort -n)"
fins="$(for m in FC0a FC0b FC1; do mf_get "member.$m.finished_epoch" "$MF"; done | sort -n)"
if [ "$(echo "$starts" | tail -n1)" -lt "$(echo "$fins" | head -n1)" ] && [ "$(mf_get concurrency "$MF")" = concurrent ]; then
  ok "(H4) concurrent: every member started before any member finished"
else
  # unquoted on purpose: word-splitting joins the newline-separated list onto one line for this diagnostic message
  # echo $x deliberately collapses newlines/runs of whitespace into one line for this diagnostic message
  # shellcheck disable=SC2086,SC2116
  bad "(H4) not concurrent: starts=$(echo $starts) finishes=$(echo $fins)"
fi
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$(mf_get mode "$MF")" = stand-in ] && ok "(H6) stand-in run recorded mode=stand-in" || bad "(H6) mode=$(mf_get mode "$MF")"

echo "=== (H5) --sequential ==="
GT_FIX_SLEEP=1 gt_capture "$FIX" "$TMP/b" t "$RID" --sequential; rc=$?
MFB="$TMP/b/t_${RID}.triplet"
if [ "$rc" = 0 ] && [ "$(mf_get concurrency "$MFB")" = sequential ] \
   && [ "$(mf_get member.FC0b.started_epoch "$MFB")" -ge "$(mf_get member.FC0a.finished_epoch "$MFB")" ] \
   && [ "$(mf_get member.FC1.started_epoch "$MFB")" -ge "$(mf_get member.FC0b.finished_epoch "$MFB")" ]; then
  ok "(H5) sequential members run one after another"
else
  bad "(H5) rc=$rc; $(grep -E 'epoch|concurrency' "$MFB" 2>/dev/null | tr '\n' ' ')"
fi

echo "=== (H9) round 7 (R6-B1): every member runs with its OWN private TMPDIR ==="
h9=1; seen=""
for m in FC0a FC0b FC1; do
  t="$(sed -n "s/^stand-in member=$m TMPDIR=//p" "$TMP/a/t_${m}_${RID}.log")"
  case "$t" in ""|unset|"$TMP/work/inherited_tmp") h9=0 ;; esac
  case " $seen " in *" $t "*) h9=0 ;; esac
  seen="$seen $t"
done
[ "$(mf_get tmpdir_isolation "$MF")" = per-member ] || h9=0
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$h9" = 1 ] && ok "(H9) three distinct private TMPDIRs (none the inherited one) + manifest tmpdir_isolation=per-member" \
  || bad "(H9) TMPDIRs not isolated:$seen; isolation=$(mf_get tmpdir_isolation "$MF")"
echo "=== (H10) R6-B1 mechanism: a fixed \${TMPDIR}/<name> evidence dir does NOT collide across concurrent members ==="
GT_FIX_COLLIDE=2 gt_capture "$FIX" "$TMP/col" t "$RID"; rc=$?
if [ "$rc" = 0 ] && ! grep -q "clobbered" "$TMP"/col/t_FC*_"$RID".log && [ "$(grep -l "own evidence intact" "$TMP"/col/t_FC*_"$RID".log | wc -l)" = 3 ]; then
  ok "(H10) all 3 concurrent members kept their own evidence dir intact"
else
  bad "(H10) rc=$rc; $(grep -h SHARED-EVID "$TMP"/col/*.log | tr '\n' ' ')"
fi

echo "=== (H7) refusals ==="
gt_capture "$FIX" "$TMP/a" t "$RID"; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 2 ] && grep -q "already exists" "$TMP/a/.capture.log" && ok "(H7a) existing manifest is never overwritten (exit 2)" || bad "(H7a) rc=$rc"
gt_capture "$FIX" "$TMP/c" bad_prefix "$RID"; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 2 ] && grep -q "must match" "$TMP/c/.capture.log" && ok "(H7b) prefix containing '_' rejected (exit 2)" || bad "(H7b) rc=$rc"

echo "=== (H8) end to end: the golden test accepts the harness's own output ==="
gt_promote "$MF"
gt_golden "$TMP/h8.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/a"; rc=$?
# ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
# shellcheck disable=SC2015
[ "$rc" = 0 ] && grep -q "FR-002/T-A01: with-timers verdict set is IDENTICAL" "$TMP/h8.out" \
  && ok "(H8) golden test validated + compared the harness triplet (FR-002 PASS)" \
  || bad "(H8) rc=$rc; $(grep -E 'FAIL|SKIP' "$TMP/h8.out" | head -3)"

# mutate NAME ANCHOR REPLACEMENT -- copy of the real harness
mutate() {
  local hits; hits="$(grep -cF -- "$2" "$REAL_HARNESS" || true)"
  if [ "$hits" != 1 ]; then bad "($1) control needle: anchor found $hits times (want 1): $2"; return 1; fi
  ANCHOR="$2" REPL="$3" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); s=s.replace(os.environ["ANCHOR"],os.environ["REPL"],1); open(sys.argv[2],"w").write(s)
' "$REAL_HARNESS" "$TMP/harness_$1.sh"
}

echo "=== (M-timing) mutant harness runs FC0b WITH timers ==="
# single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
# shellcheck disable=SC2016
if mutate timing '_timing_of() { case "$1" in FC1) echo 1 ;; *) echo 0 ;; esac; }' \
                 '_timing_of() { case "$1" in FC1|FC0b) echo 1 ;; *) echo 0 ;; esac; }'; then
  GT_HARNESS="$TMP/harness_timing.sh" gt_capture "$FIX" "$TMP/d" t "$RID"
  gt_promote "$TMP/d/t_${RID}.triplet"
  gt_golden "$TMP/mt.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/d"; rc=$?
  # ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
  # shellcheck disable=SC2015
  [ "$rc" = 1 ] && grep -q "member FC0b recorded fc_timing='1'" "$TMP/mt.out" \
    && ok "(M-timing) mislabelled member caught by the golden test (rc=1)" || bad "(M-timing) BLIND: rc=$rc"
fi

echo "=== (M-concurrent) mutant harness serialises members but still says concurrent ==="
# single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
# shellcheck disable=SC2016
if mutate conc '  if [ "$CONCURRENCY" = concurrent ]; then' '  if false; then'; then
  GT_FIX_SLEEP=2 GT_HARNESS="$TMP/harness_conc.sh" gt_capture "$FIX" "$TMP/e" t "$RID"
  MFE="$TMP/e/t_${RID}.triplet"
  s_last="$(for m in FC0a FC0b FC1; do mf_get "member.$m.started_epoch" "$MFE"; done | sort -n | tail -n1)"
  f_first="$(for m in FC0a FC0b FC1; do mf_get "member.$m.finished_epoch" "$MFE"; done | sort -n | head -n1)"
  # ok() is a bare echo (always rc 0), so `A && ok || bad` behaves as if/else: bad runs only when the condition fails
  # shellcheck disable=SC2015
  [ "$(mf_get concurrency "$MFE")" = concurrent ] && [ "$s_last" -ge "$f_first" ] && ok "(M-concurrent) serialised mutant fails the (H4) overlap condition" || bad "(M-concurrent) BLIND"
fi

echo "=== (M-tmpdir) mutant harness drops the per-member TMPDIR (round-6 behaviour) ==="
# single-quoted text here is a literal source snippet (matched/patched verbatim or written out as-is), never meant to expand
# shellcheck disable=SC2016
if mutate tmpdir '  TMPDIR="$WORK/tmp.$m" FC_TIMING=' '  FC_TIMING='; then
  GT_FIX_COLLIDE=2 GT_HARNESS="$TMP/harness_tmpdir.sh" gt_capture "$FIX" "$TMP/f" t "$RID"
  if grep -q "clobbered" "$TMP"/f/t_FC*_"$RID".log; then
    ok "(M-tmpdir) without isolation concurrent members clobber the shared evidence dir -- (H10) is load-bearing ($(grep -l clobbered "$TMP"/f/*.log | wc -l) member(s) hit)"
  else
    bad "(M-tmpdir) BLIND: the shared-TMPDIR mutant showed no collision"
  fi
fi

echo
if [ "$fail" = 0 ]; then echo "=== CAPTURE HARNESS TESTS: ALL CHECKS PASS ==="; else echo "=== CAPTURE HARNESS TESTS: FAILURES ABOVE ==="; fi
exit "$fail"
