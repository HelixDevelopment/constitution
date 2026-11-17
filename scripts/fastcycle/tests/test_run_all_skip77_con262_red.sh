#!/bin/sh
# Purpose: CON-262 / CON-243 RED test: run_all.sh must report a member that exits 77 (the honest
#          SKIP of lib/consumer_required.sh, section 11.4.3 / 11.4.69) as SKIP, never as PASS and
#          never as FAIL, and must itself exit 77 when no member failed but at least one skipped
#          (a run with a skipped member is not a full PASS). Any other non-zero status stays FAIL.
# Usage:   sh test_run_all_skip77_con262_red.sh      Exit 0 = every assertion holds, 1 = a failure.
# Oracle:  SPECIFIED (section 11.4.245): exit 77 = SKIP is the contract of consumer_required.sh and
#          of the full-suite judge; the expected lines and exit codes below are written from it.
# Mutants: test_run_all_skip77_con262_mutations.sh (paired section 1.1 mutations of run_all.sh).
# shellcheck disable=SC2015 # the `<cond> && echo ok || { echo NOT ok; failx; }` assertion idiom
here=$(cd "$(dirname "$0")" && pwd)
runner=${FC_RUN_ALL_UNDER_TEST:-$here/run_all.sh}
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0
failx() { fail=1; [ -z "$FC_TEST_FAILFAST" ] || exit 1; }
[ -f "$runner" ] || { echo "NOT ok run_all.sh missing: $runner"; exit 1; }
mk() { mkdir -p "$tmp/$1"; printf '#!/bin/sh\nexit %s\n' "$3" >"$tmp/$1/$2"; }
run() { sh "$runner" "$tmp/$1" >"$tmp/$1.out" 2>&1; echo $?; }
# S1 one member exits 77: SKIP line, no PASS/FAIL line, runner exits 77, skip count line.
mk s1 test_s.sh 77; rc=$(run s1)
[ "$rc" -eq 77 ] && echo "ok S1 only-skip-runner-exits-77" || { echo "NOT ok S1 only-skip-runner-exits-77 rc=$rc"; failx; }
grep -qx "SKIP test_s.sh" "$tmp/s1.out" && echo "ok S1 skip-label-exact" || { echo "NOT ok S1 skip-label-exact"; failx; }
grep -q "^PASS test_s.sh\|^FAIL test_s.sh" "$tmp/s1.out" && { echo "NOT ok S1 skip-not-pass-not-fail"; failx; } || echo "ok S1 skip-not-pass-not-fail"
grep -qx "run_all: 1 run, 0 failed" "$tmp/s1.out" && echo "ok S1 summary-unchanged-form" || { echo "NOT ok S1 summary-unchanged-form"; failx; }
grep -qx "run_all: 1 skipped (exit 77, honest SKIP: not a PASS)" "$tmp/s1.out" && echo "ok S1 skip-count-line" || { echo "NOT ok S1 skip-count-line"; failx; }
# S2 pass + skip: runner exits 77 (not 0: a skipped member is not a PASS).
mk s2 test_a.sh 0; mk s2 test_s.sh 77; rc=$(run s2)
[ "$rc" -eq 77 ] && echo "ok S2 pass-plus-skip-exits-77" || { echo "NOT ok S2 pass-plus-skip-exits-77 rc=$rc"; failx; }
grep -qx "PASS test_a.sh" "$tmp/s2.out" && grep -qx "SKIP test_s.sh" "$tmp/s2.out" && echo "ok S2 labels" || { echo "NOT ok S2 labels"; failx; }
grep -qx "run_all: 2 run, 0 failed" "$tmp/s2.out" && echo "ok S2 summary" || { echo "NOT ok S2 summary"; failx; }
# S3 fail + skip: FAIL wins, runner exits exactly 1.
mk s3 test_b.sh 3; mk s3 test_s.sh 77; rc=$(run s3)
[ "$rc" -eq 1 ] && echo "ok S3 fail-plus-skip-exits-1" || { echo "NOT ok S3 fail-plus-skip-exits-1 rc=$rc"; failx; }
grep -qx "FAIL test_b.sh" "$tmp/s3.out" && grep -qx "SKIP test_s.sh" "$tmp/s3.out" && echo "ok S3 labels" || { echo "NOT ok S3 labels"; failx; }
grep -qx "run_all: 2 run, 1 failed" "$tmp/s3.out" && grep -qx "run_all: 1 skipped (exit 77, honest SKIP: not a PASS)" "$tmp/s3.out" && echo "ok S3 summary" || { echo "NOT ok S3 summary"; failx; }
# S4 the neighbours of 77 stay FAIL (negative controls: only exactly 77 is a SKIP).
for c in 76 78 1 177 255; do
  mk "n$c" test_n.sh "$c"; rc=$(run "n$c")
  [ "$rc" -eq 1 ] && grep -qx "FAIL test_n.sh" "$tmp/n$c.out" && ! grep -q "^SKIP" "$tmp/n$c.out" && echo "ok S4 exit-$c-is-FAIL" || { echo "NOT ok S4 exit-$c-is-FAIL rc=$rc"; failx; }
done
# S5 all pass: exit 0, and no skip-count line (positive control: the skip line is not printed always).
mk s5 test_a.sh 0; rc=$(run s5)
[ "$rc" -eq 0 ] && ! grep -q "skipped" "$tmp/s5.out" && echo "ok S5 all-pass-exit-0-no-skip-line" || { echo "NOT ok S5 all-pass-exit-0-no-skip-line rc=$rc"; failx; }
# S6 two skips counted, three members.
mk s6 test_a.sh 0; mk s6 test_s.sh 77; mk s6 test_t.sh 77; rc=$(run s6)
[ "$rc" -eq 77 ] && grep -qx "run_all: 2 skipped (exit 77, honest SKIP: not a PASS)" "$tmp/s6.out" && echo "ok S6 two-skips" || { echo "NOT ok S6 two-skips rc=$rc"; failx; }
# S7 a timeout is never a skip even when combined with a skip.
mkdir "$tmp/s7"; printf '#!/bin/sh\nsleep 30\n' >"$tmp/s7/test_h.sh"; printf '#!/bin/sh\nexit 77\n' >"$tmp/s7/test_s.sh"
FASTCYCLE_TEST_TIMEOUT=1 timeout 40 sh "$runner" "$tmp/s7" >"$tmp/s7.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -qx "TIMEOUT test_h.sh" "$tmp/s7.out" && grep -qx "FAIL test_h.sh" "$tmp/s7.out" && echo "ok S7 timeout-stays-fail" || { echo "NOT ok S7 timeout-stays-fail rc=$rc"; failx; }
[ "$fail" -eq 0 ] && { echo "test_run_all_skip77_con262_red: all ok"; exit 0; }
echo "test_run_all_skip77_con262_red: FAILED"; exit 1
