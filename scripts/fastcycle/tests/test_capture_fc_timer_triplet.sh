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
# ok()/bad() always return 0 (so `c && ok || bad` never mis-fires), and mutation anchors are
# LITERAL source text (never expanded here).
# shellcheck disable=SC2015,SC2016
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

echo "=== (H11) T048 restart R1-I6/R1-m1: tree drift DURING a capture is recorded (real git tree) ==="
# A scratch work tree the harness fingerprints (CAPTURE_TRIPLET_TREE_ROOT, stand-in only),
# with a nested git repo at constitution/ (the real layout: a submodule holding fc_timer.sh).
TREE="$TMP/tree"
mkdir -p "$TREE/constitution"
git -C "$TREE" init -q && echo t > "$TREE/t.txt" && git -C "$TREE" add t.txt \
  && git -C "$TREE" -c user.email=t@t -c user.name=t commit -qm t
git -C "$TREE/constitution" init -q && echo c > "$TREE/constitution/c.txt" && git -C "$TREE/constitution" add c.txt \
  && git -C "$TREE/constitution" -c user.email=t@t -c user.name=t commit -qm c
h11() {  # <name> <touch path or ""> [harness args...] -> echoes "<start>|<end>"
  local n="$1" touch="$2" mf; shift 2
  GT_FIX_SLEEP=1 GT_FIX_TOUCH="$touch" CAPTURE_TRIPLET_TREE_ROOT="$TREE" gt_capture "$FIX" "$TMP/$n" t "$RID" "$@"
  mf="$TMP/$n/t_${RID}.triplet"
  echo "$(mf_get tree_status_sha256_start "$mf")|$(mf_get tree_status_sha256_end "$mf")"
}
se="$(h11 dq "")"
[ -n "${se%%|*}" ] && [ "${se%%|*}" = "${se##*|}" ] && ok "(H11a) control: no drift -> tree_status_sha256 start == end" || bad "(H11a) control: $se"
se="$(h11 dt "$TREE/t.txt")"
[ -n "${se%%|*}" ] && [ "${se%%|*}" != "${se##*|}" ] && ok "(H11b) a tracked file modified mid-capture -> start != end" || bad "(H11b) drift NOT recorded: $se"
se="$(h11 dc "$TREE/constitution/new_untracked.txt")"
[ -n "${se%%|*}" ] && [ "${se%%|*}" != "${se##*|}" ] && ok "(H11c) R1-m1: an untracked file created inside constitution/ mid-capture -> start != end" || bad "(H11c) constitution drift invisible: $se"
git -C "$TREE" checkout -q -- t.txt; rm -f "$TREE/constitution/new_untracked.txt"
se="$(h11 ds "$TREE/t.txt" --sequential)"
gt_promote "$TMP/ds/t_${RID}.triplet"
gt_golden "$TMP/h11.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ds"
grep -q "is sequential and the tree CHANGED during the capture" "$TMP/h11.out" \
  && ok "(H11d) the golden test refuses the drifted SEQUENTIAL triplet the harness recorded" \
  || bad "(H11d) golden did not refuse the drifted sequential triplet: $(grep -E 'INFO|FAIL' "$TMP/h11.out" | head -3)"
git -C "$TREE" checkout -q -- t.txt

echo "=== (H13) R1-m2: a member TSV left by a killed run at the same run-id is refused, never appended ==="
mkdir -p "$TMP/st/tsv/${RID}_t_FC1"
printf 'h\nleftover\n' > "$TMP/st/tsv/${RID}_t_FC1/prebuild_sections.tsv"
gt_capture "$FIX" "$TMP/st" t "$RID"; rc=$?
[ "$rc" = 2 ] && grep -q "already exists" "$TMP/st/.capture.log" && [ "$(wc -l < "$TMP/st/tsv/${RID}_t_FC1/prebuild_sections.tsv")" = 2 ] \
  && [ ! -e "$TMP/st/t_${RID}.triplet" ] && [ ! -e "$TMP/st/t_${RID}.triplet.reserve" ] \
  && ok "(H13) rc=2, stale TSV untouched, no manifest, no leftover reservation" \
  || bad "(H13) rc=$rc; stale tsv lines=$(wc -l < "$TMP/st/tsv/${RID}_t_FC1/prebuild_sections.tsv"); $(tail -n1 "$TMP/st/.capture.log")"

echo "=== (H14) R1-m3: two concurrent same-run-id captures -> exactly one publishes, the other refuses ==="
cap_direct() {  # <capture log> -- the harness invoked exactly like gt_capture, private log
  TMPDIR="$GT_WORK/inherited_tmp" GT_FIX="$FIX" GT_FIX_SLEEP=2 CAPTURE_TRIPLET_PREBUILD="$GT_WORK/fake_prebuild.sh" \
    CAPTURE_TRIPLET_OUT_DIR="$TMP/race" CAPTURE_TRIPLET_TSV_ROOT="$TMP/race/tsv_$2" CAPTURE_TRIPLET_RUN_ID="$RID" \
    bash "$GT_HARNESS" --prefix t > "$1" 2>&1
}
mkdir -p "$TMP/race"
cap_direct "$TMP/race1.log" a & p1=$!
cap_direct "$TMP/race2.log" b & p2=$!
wait "$p1"; r1=$?; wait "$p2"; r2=$?
if { [ "$r1" = 0 ] && [ "$r2" = 2 ]; } || { [ "$r1" = 2 ] && [ "$r2" = 0 ]; }; then
  winner="$TMP/race1.log"; loser="$TMP/race2.log"; [ "$r2" = 0 ] && { winner="$TMP/race2.log"; loser="$TMP/race1.log"; }
  [ "$(sha256sum < "$TMP/race/t_${RID}.triplet")" = "$(sed -n '/^format=/,/^member\.FC1\.tsv_rows=/p' "$winner" | sha256sum)" ] \
    && ! grep -q "^INFO: run-id" "$loser" \
    && ok "(H14) rc=$r1/$r2: the manifest is the winner's own and the refused capture never started a member" \
    || bad "(H14) the published manifest is not the winner's, or the refused capture ran members anyway: $(head -n2 "$loser")"
else
  bad "(H14) concurrent same-id captures rc=$r1/$r2 (want exactly one 0 and one 2)"
fi

echo "=== (H15) a REAL-mode capture refuses the stand-in-only tree-root override ==="
timeout -k 2 20 env CAPTURE_TRIPLET_TREE_ROOT="$TREE" CAPTURE_TRIPLET_OUT_DIR="$TMP/real" CAPTURE_TRIPLET_TSV_ROOT="$TMP/real/tsv" \
  CAPTURE_TRIPLET_RUN_ID="$RID" bash "$GT_HARNESS" --prefix t > "$TMP/h15.log" 2>&1; rc=$?
[ "$rc" = 2 ] && grep -q "stand-in-only override" "$TMP/h15.log" && ok "(H15) rc=2 before anything ran" || bad "(H15) rc=$rc: $(tail -n2 "$TMP/h15.log")"

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
if mutate tmpdir '  ( cd "$ROOT" && TMPDIR="$WORK/tmp.$m" FC_TIMING=' '  ( cd "$ROOT" && FC_TIMING='; then
  GT_FIX_COLLIDE=2 GT_HARNESS="$TMP/harness_tmpdir.sh" gt_capture "$FIX" "$TMP/f" t "$RID"
  if grep -q "clobbered" "$TMP"/f/t_FC*_"$RID".log; then
    ok "(M-tmpdir) without isolation concurrent members clobber the shared evidence dir -- (H10) is load-bearing ($(grep -l clobbered "$TMP"/f/*.log | wc -l) member(s) hit)"
  else
    bad "(M-tmpdir) BLIND: the shared-TMPDIR mutant showed no collision"
  fi
fi

echo "=== (M-CM3) reviewer mutation: tree_status_sha256_end := start (drift hidden) ==="
if mutate cm3 'TREE_STATUS_END="$(_tree_status_sha)"' 'TREE_STATUS_END="$TREE_STATUS_START"'; then
  se="$(GT_HARNESS="$TMP/harness_cm3.sh" h11 mcm3 "$TREE/t.txt")"; git -C "$TREE" checkout -q -- t.txt
  [ -n "${se%%|*}" ] && [ "${se%%|*}" = "${se##*|}" ] && ok "(M-CM3) the mutant hides real drift -- the (H11b) start!=end check is load-bearing" || bad "(M-CM3) BLIND: $se"
fi
echo "=== (M-m1) mutant harness drops the constitution/ status from the fingerprint ==="
if mutate m1 '      git -C "$TREE_ROOT/constitution" status --porcelain=v1 -unormal' '      :'; then
  se="$(GT_HARNESS="$TMP/harness_m1.sh" h11 mm1 "$TREE/constitution/new_untracked2.txt")"; rm -f "$TREE/constitution/new_untracked2.txt"
  [ -n "${se%%|*}" ] && [ "${se%%|*}" = "${se##*|}" ] && ok "(M-m1) constitution drift becomes invisible -- (H11c) is load-bearing" || bad "(M-m1) BLIND: $se"
fi
echo "=== (M-m2) mutant harness appends to a stale member TSV ==="
if mutate m2 '  if [ -e "$_pre" ]; then' '  if false; then'; then
  mkdir -p "$TMP/m2/tsv/${RID}_t_FC1"; printf 'h\nleftover\n' > "$TMP/m2/tsv/${RID}_t_FC1/prebuild_sections.tsv"
  GT_HARNESS="$TMP/harness_m2.sh" gt_capture "$FIX" "$TMP/m2" t "$RID"; rc=$?
  [ "$rc" != 2 ] && [ "$(wc -l < "$TMP/m2/tsv/${RID}_t_FC1/prebuild_sections.tsv")" != 2 ] && ok "(M-m2) the mutant appends to the stale TSV -- (H13) is load-bearing" || bad "(M-m2) BLIND: rc=$rc"
fi
echo "=== (M-m3) mutant harness without the atomic reservation ==="
if mutate m3 'if ! ( set -o noclobber; echo "$$" > "$RESERVE" ) 2>/dev/null; then' 'if ! ( echo "$$" > "$RESERVE" ) 2>/dev/null; then'; then
  rm -rf "$TMP/race"; mkdir -p "$TMP/race"
  GT_HARNESS="$TMP/harness_m3.sh" cap_direct "$TMP/mrace1.log" a & p1=$!
  GT_HARNESS="$TMP/harness_m3.sh" cap_direct "$TMP/mrace2.log" b & p2=$!
  wait "$p1"; wait "$p2"
  grep -q "^INFO: run-id" "$TMP/mrace1.log" && grep -q "^INFO: run-id" "$TMP/mrace2.log" \
    && ok "(M-m3) without the reservation BOTH captures start members -- (H14) is load-bearing" || bad "(M-m3) BLIND"
fi

echo
if [ "$fail" = 0 ]; then echo "=== CAPTURE HARNESS TESTS: ALL CHECKS PASS ==="; else echo "=== CAPTURE HARNESS TESTS: FAILURES ABOVE ==="; fi
exit "$fail"
