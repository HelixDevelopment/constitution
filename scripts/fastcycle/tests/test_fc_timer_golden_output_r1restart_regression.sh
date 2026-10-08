#!/bin/bash
# Regression guard for test_fc_timer_golden_output.sh -- T048 RESTART round-1 findings
# R2-B1 (displaced verdicts + empty exit channel), R2-M2 (unescaped manifest key), R2-M3
# (log-path basename check unguarded). Built on lib/golden_triplet_fixture.sh: every fixture
# is captured by the REAL capture_fc_timer_triplet.sh driving the stand-in pre-build and
# judged by the REAL golden test end-to-end -- nothing here re-implements either.
#
# The defect (measured on the real 20261002T195009Z triplet): when a gate's stderr lands
# between its `echo -n "...: "` prompt and its verdict, the verdict is printed on the NEXT
# line as a bare `OK` / `OK (detail)` (3 gates in the real FC0a log). The verdict regex needs
# `... OK` on one line, so those verdicts were silently dropped -- and because every real
# member exits 1 (58 pre-existing failures) the exit-code channel cannot see one extra FAIL
# either. A displaced OK->FAIL flip in FC1 therefore PASSED (reviewer fixture: 14/0, rc=0).
#
#   D1  displaced bare `OK` -> `FAIL` in FC1 only, exits 1/1/1, equal Failed: counters
#       -> FAIL (caught by prompt/verdict pairing)
#   D1b displaced `OK (detail)` -> `FAIL (detail)` -> FAIL
#   D2  identical verdict lines, FC1 `Failed: 59` vs twins `58`, exits 1/1/1 -> FAIL
#       (caught by the line-independent summary-counter channel)
#   D3  golden-FALSE: displaced verdict + counters identical in all three -> PASS (rc 0)
#   D4  noise floor: FC0b's counters differ, verdicts identical -> SKIP (never an FR-002 PASS)
#   D5  FC1 has no readable summary counters (crash before summary) -> FAIL
#   D6  R2-M3: a member log path containing '/' -> triplet invalid (rc 1); and the mutant
#       without the basename check accepts it (the check is load-bearing)
#   D7  R2-M2: a decoy manifest key `memberXFC0aXlog=` (regex-metachar near miss) must not
#       collide with `member.FC0a.log` -> the triplet stays valid (rc 0)
#   M-pair    mutant golden without the pairing step -> D1 PASSES again (pairing load-bearing)
#   M-counter mutant golden without the counter comparison -> D2 PASSES again
# Usage: bash test_fc_timer_golden_output_r1restart_regression.sh   (exit 0 = all ok)
# ok()/bad() always return 0 and mutation anchors are literal source text.
# shellcheck disable=SC2015,SC2016,SC1003
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

# triplet <name> <n> <FC0a text> <FC0b text> <FC1 text> <"e0 e1 e2"> -> evidence in $TMP/ev_<name>
triplet() {
  local name="$1" fix="$TMP/fix_$1" out="$TMP/ev_$1" runid e0 e1 e2
  runid="202623$(printf '%02d' "$2")T000000Z"
  printf '%s\n' "$3" | gt_member_text "$fix" FC0a
  printf '%s\n' "$4" | gt_member_text "$fix" FC0b
  printf '%s\n' "$5" | gt_member_text "$fix" FC1
  read -r e0 e1 e2 <<<"$6"
  gt_member_exit "$fix" FC0a "$e0"; gt_member_exit "$fix" FC0b "$e1"; gt_member_exit "$fix" FC1 "$e2"
  gt_capture "$fix" "$out" t "$runid" || { bad "($name) harness failed: $(tail -n 3 "$out/.capture.log")"; return 1; }
  gt_promote "$out/t_${runid}.triplet"
  echo "$out/t_${runid}.triplet" > "$TMP/mf_$name"
}
judge() {  # <name> [golden] -> rc; output in $TMP/out_<name>
  if [ -n "${2:-}" ]; then
    GT_GOLDEN="$2" gt_golden "$TMP/out_$1" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_$1"
  else
    gt_golden "$TMP/out_$1" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_$1"
  fi
  echo "$?"
}
mutate() {  # <name> <anchor> <replacement> -> $TMP/golden_<name>.sh
  local n
  n="$(ANCHOR="$2" python3 -c 'import os,sys; print(open(sys.argv[1]).read().count(os.environ["ANCHOR"]))' "$REAL_GOLDEN")"
  [ "$n" = 1 ] || { bad "($1) control needle: anchor found $n times (want 1): $2"; return 1; }
  ANCHOR="$2" REPL="$3" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); open(sys.argv[2],"w").write(s.replace(os.environ["ANCHOR"],os.environ["REPL"],1))
' "$REAL_GOLDEN" "$TMP/golden_$1.sh"
}

G1='  ✓ CM-ONE: clean gate'
PROMPT='  CM-DISP: gate whose stderr displaces its verdict... grep: warning: stray \ before n'
F58='  Failed:       58'
F59='  Failed:       59'

triplet D1 1 "$G1
$PROMPT
OK" "$G1
$PROMPT
OK" "$G1
$PROMPT
FAIL" "1 1 1"
triplet D1b 2 "$G1
$PROMPT
grep: warning: stray \ before x
OK (4/4 invariants)" "$G1
$PROMPT
grep: warning: stray \ before x
OK (4/4 invariants)" "$G1
$PROMPT
grep: warning: stray \ before x
FAIL (3/4 invariants)" "1 1 1"
triplet D2 3 "$G1
$F58" "$G1
$F58" "$G1
$F59" "1 1 1"
triplet D3 4 "$G1
$PROMPT
OK
$F58" "$G1
$PROMPT
OK
$F58" "$G1
$PROMPT
OK
$F58" "1 1 1"
triplet D4 5 "$G1
$F58" "$G1
$F59" "$G1
$F58" "1 1 1"
gt_member_nosummary "$TMP/fix_D5" FC1
triplet D5 6 "$G1" "$G1" "$G1" "1 1 1"

echo "=== D1/D1b: a displaced OK->FAIL flip is a FAIL ==="
rc="$(judge D1)"
[ "$rc" = 1 ] && grep -q "MISMATCH" "$TMP/out_D1" && ok "(D1) displaced bare OK->FAIL flip -> FAIL (rc=1)" || bad "(D1) BLIND: rc=$rc $(grep -E '^(PASS|FAIL|SKIP)' "$TMP/out_D1" | tail -n 3 | tr '\n' ' ')"
rc="$(judge D1b)"
[ "$rc" = 1 ] && grep -q "MISMATCH" "$TMP/out_D1b" && ok "(D1b) displaced 'OK (detail)'->'FAIL (detail)' after 2 stderr lines -> FAIL" || bad "(D1b) BLIND: rc=$rc"
echo "=== D2: one extra failure visible only in the summary counters is a FAIL ==="
rc="$(judge D2)"
[ "$rc" = 1 ] && grep -q "summary counters" "$TMP/out_D2" && ok "(D2) FC1 Failed: 59 vs twins 58 -> FAIL" || bad "(D2) BLIND: rc=$rc $(grep -E '^(PASS|FAIL|SKIP)' "$TMP/out_D2" | tail -n 3 | tr '\n' ' ')"
echo "=== D3: golden-FALSE -- identical displaced verdicts + counters -> PASS ==="
rc="$(judge D3)"
[ "$rc" = 0 ] && grep -q "verdict set is IDENTICAL" "$TMP/out_D3" && grep -q "summary counters identical" "$TMP/out_D3" \
  && ok "(D3) no false refusal: rc=0 with both channels PASS" || bad "(D3) false refusal: rc=$rc $(grep -E '^FAIL' "$TMP/out_D3" | head -2)"
echo "=== D4: a counter disagreement between the twins is a noise-floor SKIP, never an FR-002 PASS ==="
rc="$(judge D4)"
[ "$rc" = 0 ] && grep -q "^SKIP.*disagree" "$TMP/out_D4" && ! grep -q "verdict set is IDENTICAL" "$TMP/out_D4" \
  && ok "(D4) twins disagree on counters -> SKIP" || bad "(D4) rc=$rc $(grep -E '^(PASS|SKIP|FAIL)' "$TMP/out_D4" | tail -n 2 | tr '\n' ' ')"
echo "=== D5: unreadable summary counters are a FAIL, never 'equal by absence' ==="
rc="$(judge D5)"
[ "$rc" = 1 ] && grep -q "no readable summary counters" "$TMP/out_D5" && ok "(D5) FC1 without a summary -> FAIL" || bad "(D5) BLIND: rc=$rc"

echo "=== D6 (R2-M3): member log path with '/' -> invalid; the basename check is load-bearing ==="
triplet D6 7 "$G1" "$G1" "$G1" "1 1 1"
MF6="$(cat "$TMP/mf_D6")"; d6="$(dirname "$MF6")"; l6="$(sed -n 's/^member\.FC0a\.log=//p' "$MF6")"
mkdir -p "$d6/sub" && cp -- "$d6/$l6" "$d6/sub/$l6" && sed -i "s|^member\.FC0a\.log=.*|member.FC0a.log=sub/$l6|" "$MF6"
rc="$(judge D6)"
[ "$rc" = 1 ] && grep -q "member FC0a log 'sub/" "$TMP/out_D6" && ok "(D6) 'sub/<log>' refused (rc=1)" || bad "(D6) rc=$rc"
if mutate basename '[ -z "$log" ] || [ "$(basename -- "$log")" != "$log" ] || [ ! -f "$dir/$log" ]' '[ -z "$log" ] || [ ! -f "$dir/$log" ]'; then
  rc="$(judge D6 "$TMP/golden_basename.sh")"
  [ "$rc" = 0 ] && ok "(M-basename) without the check the 'sub/' path is accepted -- (D6) is load-bearing" || bad "(M-basename) mutant still refuses (rc=$rc)"
fi

echo "=== D7 (R2-M2): a near-miss decoy key never collides with member.FC0a.log ==="
triplet D7 8 "$G1" "$G1" "$G1" "1 1 1"
echo "memberXFC0aXlog=decoy.log" >> "$(cat "$TMP/mf_D7")"
rc="$(judge D7)"
[ "$rc" = 0 ] && grep -q "verdict set is IDENTICAL" "$TMP/out_D7" && ok "(D7) decoy key ignored, triplet valid (rc=0)" || bad "(D7) decoy key broke parsing: rc=$rc $(grep -E '^FAIL' "$TMP/out_D7" | head -1)"

echo "=== M-pair / M-counter: each new channel is load-bearing ==="
if mutate pair '    | _pair_displaced_verdicts \' '    | cat \'; then
  rc="$(judge D1 "$TMP/golden_pair.sh")"
  # Without pairing the D1 flip is invisible to the verdict comparison again (its PASS line
  # returns), and the per-shape control needle is what still fails the run.
  grep -q "^PASS.*verdict set is IDENTICAL" "$TMP/out_D1" && grep -q "^FAIL.*every real verdict shape" "$TMP/out_D1" \
    && ok "(M-pair) without pairing the D1 flip is invisible to the comparison (PASS) and only the shape needle fails -- both are load-bearing" \
    || bad "(M-pair) unexpected mutant outcome (rc=$rc): $(grep -E '^(PASS|FAIL)' "$TMP/out_D1" | tail -n 4 | tr '\n' ' ')"
fi
if mutate counter '_COUNTERS_EQUAL_01=1; cmp -s "$TMP/counters_FC0a.txt" "$TMP/counters_FC1.txt" || _COUNTERS_EQUAL_01=0' '_COUNTERS_EQUAL_01=1'; then
  rc="$(judge D2 "$TMP/golden_counter.sh")"
  [ "$rc" = 0 ] && ok "(M-counter) without the counter comparison the D2 extra failure PASSES again -- the channel is load-bearing" || bad "(M-counter) mutant still catches D2 (rc=$rc)"
fi

echo
if [ "$fail" = 0 ]; then echo "=== R1-RESTART REGRESSION: ALL CHECKS PASS ==="; else echo "=== R1-RESTART REGRESSION: FAILURES ABOVE ==="; fi
exit "$fail"
