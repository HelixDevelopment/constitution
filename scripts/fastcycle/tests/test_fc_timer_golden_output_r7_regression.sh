#!/bin/bash
# File-wide: this harness uses the standard `cond && ok "..." || bad "..."`
# control-needle idiom throughout (ok/bad are print-only reporters that
# always return 0, so the || branch never spuriously fires) plus a handful
# of literal sed/grep anchor strings inside single quotes (intentionally
# non-expanding). Each instance reviewed; all genuinely intentional.
# shellcheck disable=SC2015,SC2016,SC1091
# T048 round-7 regression guard for test_fc_timer_golden_output.sh: the
# round-6 independent review's R6-I1, R6-I3, R6-M1..M3 and the R6-B1 isolation
# refusal. (spec 004-fast-dev-cycles T015/T048.)
#
# T048 ROUND 21 (R20-I1, S11.4.124): R6-M4 (the noise-floor multiset
# classifier, _fc_classify_against()) is REMOVED along with the rest of the
# noise-floor/registry-accounting cascade it belongs to -- see the
# ROUND-21 ARCHITECTURE note in test_fc_timer_golden_output.sh. This file's
# own (R9)/(M-M4) cases, which tested ONLY that removed mechanism, are
# removed with it, in this same commit. (M-M2a)/(M-M2a2) are similarly
# trimmed: the round-19 member-internal-consistency rule they tested as a
# SECOND independent catch is also removed; (M-M2a) is rewritten to prove
# validate_triplet()'s own exit-integer check is now the SOLE defense.
#
# HOW THIS FILE TESTS: like the round-5 guard, every case runs the REAL harness
# (capture_fc_timer_triplet.sh, stand-in pre-build from
# lib/golden_triplet_fixture.sh) and the REAL golden test end to end; fixture
# edits are made to the harness's own output. Each fix is then proven
# load-bearing by re-running its case against a MUTATED COPY of the golden
# test that restores the round-6 behaviour -- the case's verdict must flip.
#
# Cases:
#  (R1) R6-I1 reviewer repro A1: an older SAME triplet plus a NEWER triplet
#       with a real FC1 verdict flip whose manifest carries `mode=real` twice
#       -> FAIL naming the newest; the older one is NOT compared instead.
#  (R2) R6-I1 reviewer repro A2: newest manifest truncated to 3 lines -> FAIL.
#  (R3) R6-I1: a manifest with no readable run_id anywhere -> FAIL.
#  (R4) R6-I1: two manifests share the newest run_id -> FAIL (ambiguous).
#  (R5) R6-I3: no triplet; the fallback log is a WITH-timers run -> it is NOT
#       labelled "without timers".
#  (R6) R6-M1: span exactly 3600 s (the default maximum) is accepted and
#       compared; 3601 s is refused.
#  (R7) R6-M2: a MISSING member exit -> FAIL; FC1 exit != FC0a exit with
#       identical verdicts -> FAIL (commit result); a member epoch outside the
#       manifest window -> FAIL.
#  (R8) R6-M3: all three TSV paths identical / not bound to run+member -> FAIL;
#       a TSV deleted after capture -> PASS that says it was NOT re-counted.
#  (R10) R6-B1: a CONCURRENT triplet without tmpdir_isolation=per-member is
#       refused (SKIP); a SEQUENTIAL one without the key is still compared.
#  (R10c) T048 round 8, R8-M1: a CONCURRENT triplet whose tmpdir_isolation
#       key is PRESENT but wrong-valued (e.g. "none") is ALSO refused -- the
#       check reads the VALUE, not merely whether the key exists.
#  (M-*) one mutation per fix, each restoring the round-6 (or round-8)
#       pre-fix behaviour.
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
for m in FC0a FC0b FC1; do
  printf '  ✓ CM-ONE: first\n  ✗ CM-TWO: second\nWARN: CM-THREE: third\n' | gt_member_text "$SAME" "$m"
done
DIFF_FIX="$TMP/fix_diff"
mkdir -p "$DIFF_FIX"
for m in FC0a FC0b; do cp "$SAME/$m.txt" "$DIFF_FIX/$m.txt"; done
printf '  ✓ CM-ONE: first\n  ✓ CM-TWO: second\nWARN: CM-THREE: third\n' | gt_member_text "$DIFF_FIX" FC1

capture() {  # OUT FIX RUNID [PREFIX] [harness args...]
  local out="$1" fix="$2" runid="$3" prefix="${4:-t}"; shift 3; [ $# -gt 0 ] && shift
  if ! gt_capture "$fix" "$out" "$prefix" "$runid" "$@"; then
    bad "harness failed for $out: $(tail -n 3 "$out/.capture.log")"; return 1
  fi
  gt_promote "$out/${prefix}_${runid}.triplet"
}
has() { grep -qF -- "$2" "$1"; }
set_key() { sed -i "s|^$2=.*|$2=$3|" "$1"; }   # MANIFEST KEY VALUE
set_span() { local s; s="$(sed -n 's/^started_epoch=//p' "$1")"; set_key "$1" finished_epoch "$((s + $2))"; }

# ---------------------------------------------------------------------------
echo "=== (R1) R6-I1 repro A1: a malformed NEWEST manifest is never skipped in favour of an older one ==="
capture "$TMP/r1" "$SAME" 20261001T060000Z
capture "$TMP/r1" "$DIFF_FIX" 20261001T070000Z
echo "mode=real" >> "$TMP/r1/t_20261001T070000Z.triplet"
gt_golden "$TMP/r1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r1"; rc=$?
if [ "$rc" = 1 ] && has "$TMP/r1.out" "t_20261001T070000Z.triplet" && has "$TMP/r1.out" "malformed manifest" \
   && ! has "$TMP/r1.out" "same-run triplet 20261001T060000Z"; then
  ok "(R1) duplicated-key newest manifest is a FAIL; the older SAME triplet is not substituted"
else
  bad "(R1) rc=$rc; $(grep -E 'FAIL|INFO' "$TMP/r1.out" | head -3)"
fi

echo "=== (R2) R6-I1 repro A2: newest manifest truncated to 3 lines ==="
capture "$TMP/r2" "$SAME" 20261001T060000Z
capture "$TMP/r2" "$DIFF_FIX" 20261001T070000Z
head -n 3 "$TMP/r2/t_20261001T070000Z.triplet" > "$TMP/r2/x" && mv "$TMP/r2/x" "$TMP/r2/t_20261001T070000Z.triplet"
gt_golden "$TMP/r2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r2"; rc=$?
[ "$rc" = 1 ] && has "$TMP/r2.out" "t_20261001T070000Z.triplet" && ! has "$TMP/r2.out" "same-run triplet 20261001T060000Z" \
  && ok "(R2) truncated newest manifest is a FAIL, never silently replaced" || bad "(R2) rc=$rc; $(grep -E 'FAIL|INFO' "$TMP/r2.out" | head -3)"

echo "=== (R3) R6-I1: a manifest with no readable run_id anywhere ==="
capture "$TMP/r3" "$SAME" 20261001T060000Z
printf 'format=fc_timer_triplet/v1\nmode=real\n' > "$TMP/r3/junk.triplet"
gt_golden "$TMP/r3.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r3"; rc=$?
[ "$rc" = 1 ] && has "$TMP/r3.out" "junk.triplet has no readable run_id" \
  && ok "(R3) unrankable manifest is a FAIL (it cannot be ruled out as the newest)" || bad "(R3) rc=$rc; $(grep -E 'FAIL|INFO' "$TMP/r3.out" | head -3)"

echo "=== (R4) R6-I1: two manifests share the newest run_id ==="
capture "$TMP/r4" "$SAME" 20261001T060000Z t
capture "$TMP/r4" "$SAME" 20261001T060000Z u
gt_golden "$TMP/r4.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r4"; rc=$?
[ "$rc" = 1 ] && has "$TMP/r4.out" "share the newest run-id 20261001T060000Z" \
  && ok "(R4) ambiguous newest run-id is a FAIL" || bad "(R4) rc=$rc; $(grep -E 'FAIL|INFO' "$TMP/r4.out" | head -3)"

echo "=== (R5) R6-I3: the no-triplet fallback never calls a WITH-timers log 'without timers' ==="
R5="$TMP/r5"; mkdir -p "$R5"
# the fallback picks the newest prebuild_full_run_*.log by mtime; this one is a
# with-timers run (its run's own TSV would have rows) -- the label must not lie.
cp "$DIFF_FIX/FC1.txt" "$R5/prebuild_full_run_t029_t029_full_20260928T124322Z.log"
gt_golden "$TMP/r5.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$R5"; rc=$?
if [ "$rc" = 0 ] && ! grep -q "without timers" "$TMP/r5.out" && has "$TMP/r5.out" "timer state NOT verified"; then
  ok "(R5) fallback baseline labelled 'timer state NOT verified', never 'without timers'"
else
  bad "(R5) rc=$rc; $(grep -E "without timers|PASS\[1\]" "$TMP/r5.out" | head -3)"
fi

echo "=== (R6) R6-M1: window boundary -- exactly 3600s accepted, 3601s refused ==="
capture "$TMP/r6a" "$SAME" 20261001T080000Z
set_span "$TMP/r6a/t_20261001T080000Z.triplet" 3600
for m in FC0a FC0b FC1; do set_key "$TMP/r6a/t_20261001T080000Z.triplet" "member.$m.finished_epoch" "$(sed -n 's/^finished_epoch=//p' "$TMP/r6a/t_20261001T080000Z.triplet")"; done
gt_golden "$TMP/r6a.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r6a"; rc=$?
[ "$rc" = 0 ] && has "$TMP/r6a.out" "3600s span (<= 3600s)" && has "$TMP/r6a.out" "IDENTICAL" \
  && ok "(R6a) span == 3600s is inside the inclusive window and is compared" || bad "(R6a) rc=$rc; $(grep -E 'FAIL|SKIP|INFO' "$TMP/r6a.out" | head -3)"
capture "$TMP/r6b" "$SAME" 20261001T090000Z
set_span "$TMP/r6b/t_20261001T090000Z.triplet" 3601
gt_golden "$TMP/r6b.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r6b"; rc=$?
[ "$rc" = 0 ] && has "$TMP/r6b.out" "spans 3601s, more than the 3600s maximum" && ! has "$TMP/r6b.out" "IDENTICAL" \
  && ok "(R6b) span == 3601s is refused" || bad "(R6b) rc=$rc"

echo "=== (R7) R6-M2: member exit codes and epochs are validated and compared ==="
capture "$TMP/r7a" "$SAME" 20261001T100000Z
set_key "$TMP/r7a/t_20261001T100000Z.triplet" member.FC0b.exit MISSING
gt_golden "$TMP/r7a.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r7a"; rc=$?
[ "$rc" = 1 ] && has "$TMP/r7a.out" "member FC0b recorded exit='MISSING'" \
  && ok "(R7a) a killed member (exit=MISSING) is a FAIL" || bad "(R7a) rc=$rc; $(grep -E 'FAIL' "$TMP/r7a.out" | head -2)"
# T048 round 19 (R18-I1): the member exit codes below are the stand-in's
# REAL exit codes (gt_member_exit, written into a private copy of the
# shared fixture BEFORE capture), no longer post-capture manifest edits --
# the stand-in now prints a realistic "Failed: N" summary line consistent
# with its own exit code, which a manifest-only exit edit would contradict.
cp -r "$SAME" "$TMP/fix_r7b"; gt_member_exit "$TMP/fix_r7b" FC1 0
capture "$TMP/r7b" "$TMP/fix_r7b" 20261001T110000Z
gt_golden "$TMP/r7b.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r7b"; rc=$?
[ "$rc" = 1 ] && has "$TMP/r7b.out" "FAIL" && has "$TMP/r7b.out" "commit result: with-timers exit status (0) equals without-timers exit status (1)" \
  && ok "(R7b) FC1 exit 0 vs FC0a exit 1 with identical verdicts is a FAIL (commit result differs)" || bad "(R7b) rc=$rc; $(grep -E 'commit result' "$TMP/r7b.out" | head -2)"
capture "$TMP/r7c" "$SAME" 20261001T120000Z
set_key "$TMP/r7c/t_20261001T120000Z.triplet" member.FC1.finished_epoch 9999999999
gt_golden "$TMP/r7c.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r7c"; rc=$?
[ "$rc" = 1 ] && has "$TMP/r7c.out" "member FC1 finished_epoch='9999999999' is not an integer inside the manifest window" \
  && ok "(R7c) a member epoch outside the manifest window is a FAIL" || bad "(R7c) rc=$rc; $(grep -E 'FAIL' "$TMP/r7c.out" | head -2)"

echo "=== (R8) R6-M3: TSV paths are bound to run+member; absent TSVs are not claimed re-counted ==="
capture "$TMP/r8a" "$SAME" 20261001T130000Z
for m in FC0a FC0b FC1; do set_key "$TMP/r8a/t_20261001T130000Z.triplet" "member.$m.tsv" /nonexistent/x.tsv; done
gt_golden "$TMP/r8a.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r8a"; rc=$?
[ "$rc" = 1 ] && has "$TMP/r8a.out" "TSV path '/nonexistent/x.tsv' is not" \
  && ok "(R8a) three members pointing at one unbound TSV path is a FAIL" || bad "(R8a) rc=$rc; $(grep -E 'FAIL|PASS\[2\]' "$TMP/r8a.out" | head -2)"
capture "$TMP/r8b" "$SAME" 20261001T140000Z
rm -f "$TMP/r8b/tsv/20261001T140000Z_t_FC1/prebuild_sections.tsv"
gt_golden "$TMP/r8b.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r8b"; rc=$?
[ "$rc" = 0 ] && has "$TMP/r8b.out" "no longer on disk, NOT re-counted" && ! has "$TMP/r8b.out" "re-counted on disk" \
  && ok "(R8b) a deleted TSV is reported manifest-recorded, NOT re-counted" || bad "(R8b) rc=$rc; $(grep -E 'provenance' "$TMP/r8b.out" | head -2)"

echo "=== (R10) R6-B1: concurrent triplets need per-member TMPDIR isolation ==="
capture "$TMP/r10a" "$SAME" 20261001T160000Z
sed -i '/^tmpdir_isolation=/d' "$TMP/r10a/t_20261001T160000Z.triplet"
gt_golden "$TMP/r10a.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r10a"; rc=$?
[ "$rc" = 0 ] && has "$TMP/r10a.out" "WITHOUT per-member TMPDIR isolation" && ! has "$TMP/r10a.out" "IDENTICAL" \
  && ok "(R10a) a concurrent triplet without tmpdir_isolation=per-member is refused, never compared" || bad "(R10a) rc=$rc"
capture "$TMP/r10b" "$SAME" 20261001T170000Z t --sequential
sed -i '/^tmpdir_isolation=/d' "$TMP/r10b/t_20261001T170000Z.triplet"
gt_golden "$TMP/r10b.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r10b"; rc=$?
[ "$rc" = 0 ] && has "$TMP/r10b.out" "IDENTICAL" \
  && ok "(R10b) a sequential triplet (members never overlap) is compared without the key (golden-FALSE)" || bad "(R10b) rc=$rc; $(grep -E 'SKIP|INFO' "$TMP/r10b.out" | head -2)"

echo "=== (R10c) T048 round 8 (R8-M1): a WRONG-VALUED tmpdir_isolation key (present, value != per-member) is STILL refused -- the check reads the VALUE, not merely presence ==="
capture "$TMP/r10c" "$SAME" 20261001T180000Z
set_key "$TMP/r10c/t_20261001T180000Z.triplet" tmpdir_isolation none
gt_golden "$TMP/r10c.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/r10c"; rc=$?
[ "$rc" = 0 ] && has "$TMP/r10c.out" "WITHOUT per-member TMPDIR isolation" && ! has "$TMP/r10c.out" "IDENTICAL" \
  && ok "(R10c) a concurrent triplet whose tmpdir_isolation=none (present, wrong value) is refused exactly like a missing key" || bad "(R10c) rc=$rc"

# ---------------------------------------------------------------------------
# Mutations (each restores round-6 behaviour in a COPY of the golden test).
# ---------------------------------------------------------------------------
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

echo "=== (M-I1) round-6 silent skip of a manifest whose mode key is unreadable ==="
if mutate I1 '_mode="$(_mf_get mode "$_mf")" || _mode=""' '_mode="$(_mf_get mode "$_mf")" || continue'; then
  mrun I1 "$TMP/mI1.out" "$TMP/r1"; rc=$?
  [ "$rc" = 0 ] && has "$TMP/mI1.out" "same-run triplet 20261001T060000Z" \
    && ok "(M-I1) the mutant silently compares the OLDER triplet and PASSes (rc=0) -- (R1) is load-bearing" || bad "(M-I1) BLIND: rc=$rc"
fi

echo "=== (M-I3) round-6 'without timers' label restored on the fallback path ==="
if mutate I3 'BASELINE_LABEL="real pre_build_verification.sh log, timer state NOT verified"' "BASELINE_LABEL=\"real 'without timers'\""; then
  mrun I3 "$TMP/mI3.out" "$R5"
  grep -q "without timers" "$TMP/mI3.out" && ok "(M-I3) the mutant prints the false 'without timers' label -- (R5) is load-bearing" || bad "(M-I3) BLIND"
fi

echo "=== (M-M1) window comparison -gt -> -ge ==="
if mutate M1 'if [ "$span" -gt "$MAX_WINDOW_S" ]; then' 'if [ "$span" -ge "$MAX_WINDOW_S" ]; then'; then
  mrun M1 "$TMP/mM1.out" "$TMP/r6a"
  has "$TMP/mM1.out" "spans 3600s" && ! has "$TMP/mM1.out" "IDENTICAL" \
    && ok "(M-M1) the mutant refuses the exactly-3600s triplet -- (R6a) is load-bearing" || bad "(M-M1) BLIND"
fi

echo "=== (M-M2a) member exit integer check removed ==="
# T048 round 21 (R20-I1/S11.4.124): the round-19 member-internal
# consistency rule this mutation used to prove as a SECOND, independent
# catch (_fc_check_member_consistency(), section (d)) is REMOVED along
# with the rest of the registry-accounting/consistency cascade -- see the
# ROUND-21 ARCHITECTURE note in test_fc_timer_golden_output.sh. The
# validate_triplet() exit-integer check this mutation targets is NOT
# removed (it is part of triplet VALIDATION, not the removed FR-002
# comparison cascade), but it is now the SOLE defense against a killed
# member (exit=MISSING) reaching the comparison at all -- so removing it
# must now flip (R7a)'s overall result to PASS (rc=0), not merely drop its
# own named refusal line while a backstop catches it.
if mutate M2a "if ! printf '%s' \"\$ex\" | grep -qE '^[0-9]+\$'; then" 'if false; then'; then
  mrun M2a "$TMP/mM2a.out" "$TMP/r7a"; rc=$?
  if [ "$rc" = 0 ] && ! has "$TMP/mM2a.out" "member FC0b recorded exit='MISSING'"; then
    ok "(M-M2a) without the integer check, the killed member (exit=MISSING) WRONGLY passes (rc=0) -- validate_triplet()'s exit-integer check is the SOLE, genuinely load-bearing defense for (R7a) in the round-21 architecture"
  else
    bad "(M-M2a) BLIND: rc=$rc; $(grep -E 'MISSING|FAIL' "$TMP/mM2a.out" | head -3)"
  fi
fi

echo "=== (M-M2b) commit-result comparison neutralised ==="
# T048 round 11 (R10-I1) rewrote the unconditional "$([ "$_ex0" = "$_ex1" ]
# && echo 1 || echo 0)" chk-argument expression into an if/elif/else block
# with its own noise-floor treatment. The EQUIVALENT neutralisation of the
# SAME comparison is now forcing the if-condition itself to always be true
# (always take the "exit codes match" branch), regardless of the real
# exit codes -- same intent as the original mutation: without the real
# commit-result comparison, an exit mismatch passes (rc=0).
if mutate M2b 'if [ "$_ex0" = "$_ex1" ]; then' 'if true; then'; then
  mrun M2b "$TMP/mM2b.out" "$TMP/r7b"; rc=$?
  [ "$rc" = 0 ] && ok "(M-M2b) without it the exit mismatch passes (rc=0) -- (R7b) is load-bearing" || bad "(M-M2b) BLIND: rc=$rc"
fi

echo "=== (M-M2c) member epoch window check removed ==="
if mutate M2c "if ! printf '%s' \"\$ms\" | grep -qE '^[0-9]+\$' || [ \"\$ms\" -lt \"\$s\" ] || [ \"\$ms\" -gt \"\$f\" ]; then" 'if false; then'; then
  mrun M2c "$TMP/mM2c.out" "$TMP/r7c"; rc=$?
  [ "$rc" = 0 ] && ok "(M-M2c) without it the out-of-window epoch passes (rc=0) -- (R7c) is load-bearing" || bad "(M-M2c) BLIND: rc=$rc"
fi

echo "=== (M-M3) TSV path binding removed ==="
if mutate M3 '      */"${run_id}_${prefix}_${m}"/prebuild_sections.tsv) : ;;' '      *) : ;;'; then
  mrun M3 "$TMP/mM3.out" "$TMP/r8a"; rc=$?
  [ "$rc" = 0 ] && ok "(M-M3) without the binding the shared /nonexistent path passes (rc=0) -- (R8a) is load-bearing" || bad "(M-M3) BLIND: rc=$rc"
fi

echo "=== (M-iso) isolation refusal removed ==="
# T048 round 11 (R10-M4) renamed the raw "$(_mf_get concurrency "$mf")" read
# on this line to the already-validated "$concurrency_mode" variable (read
# and closed-set-checked once, earlier in the function) -- same condition,
# same intent, updated anchor.
if mutate iso '  if [ "$concurrency_mode" != sequential ] && [ "$(_mf_get tmpdir_isolation "$mf")" != per-member ]; then' '  if false; then'; then
  mrun iso "$TMP/miso.out" "$TMP/r10a"
  has "$TMP/miso.out" "IDENTICAL" && ok "(M-iso) the mutant compares the non-isolated concurrent triplet -- (R10a) is load-bearing" || bad "(M-iso) BLIND"
fi

echo "=== (M-presence) T048 round 8 (R8-M1): degrade the isolation check to presence-only (ignores the VALUE) ==="
if mutate presence '[ "$(_mf_get tmpdir_isolation "$mf")" != per-member ]' '! grep -q "^tmpdir_isolation=" "$mf"'; then
  mrun presence "$TMP/mpresence.out" "$TMP/r10c"
  if has "$TMP/mpresence.out" "IDENTICAL" && ! has "$TMP/mpresence.out" "WITHOUT per-member TMPDIR isolation"; then
    ok "(M-presence) the presence-only mutant WRONGLY compares (R10c)'s wrong-valued-key triplet -- (R10c) is genuinely load-bearing, closing the gap a presence-only check left open"
  else
    bad "(M-presence) BLIND: $(grep -E 'INFO:|SKIP' "$TMP/mpresence.out" | head -3)"
  fi
fi

echo
if [ "$fail" = 0 ]; then echo "=== T048 ROUND-7 GOLDEN REGRESSION GUARD: ALL CHECKS PASS ==="; else echo "=== T048 ROUND-7 GOLDEN REGRESSION GUARD: FAILURES ABOVE ==="; fi
exit "$fail"
