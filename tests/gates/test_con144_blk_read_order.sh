#!/usr/bin/env bash
# tests/gates/test_con144_blk_read_order.sh -- CON-144 regression guard for CM-GATE-ENV-READS-ALLOWLISTED.
# The helper names_cm_gate_in_block() of cm_pr_delivery_anchor_wired.sh and cm_release_gate_anchor_wired.sh read $BLK in a
# function body that is defined (text order) before the top-level `BLK=` assignment, so the static env census reported
# `BLK (read-before-assign)` and the env gate FAILed on main (uncovered=2). At run time the read was safe (the only call follows
# the assignment); the fix passes the block file to the helper as an argument, so no function body reads $BLK.
# REAL census, REAL gates, mktemp copies only (no doubles).
#   N0/N1  control needles: the census + filter see the defect shape and do not flag the fixed shape
#   C1/C2  the real census reports no BLK row for either gate
#   C3     the real env gate PASSes on the real tree (it FAILed with uncovered=2 before the fix)
#   C4/C5  the real anchor-wired gates PASS on the real tree (the helper still works)
#   M1     paired mutant: restore the old body (reads "$BLK") in a copy -> the census reports BLK read-before-assign again
#   M2     paired mutant: the call site passes /dev/null instead of "$BLK" -> the PR-delivery gate FAILs (the argument is load-bearing)
#   M3     same as M2 for the release-gate gate
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; src="$(cd "$here/../.." && pwd)"
sb="$(mktemp -d)"; : "${sb:?}"; trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
chk() { if [ "$1" = 0 ]; then pass=$((pass+1)); echo "PASS $2"; else fail=$((fail+1)); echo "FAIL $2"; fi; }
CENSUS="$src/scripts/gates/lib/gate_env_census.py"
PRD=scripts/gates/cm_pr_delivery_anchor_wired.sh; RLG=scripts/gates/cm_release_gate_anchor_wired.sh
census() { (cd / && python3 -I "$CENSUS" --root "$1" --closure "$1/$2"); }
blkrow() { census "$1" "$2" | grep -P '\tBLK\tread-before-assign\t' ; }
# control needles for the BLK filter, through the same census and the same grep: a planted file with the CON-144 shape (a
# function body reads $BLK, defined before BLK=) must give a row (positive); the same file with the body taking "$2" must not
mkdir -p "$sb/n/scripts/gates"
printf '%s\n' '#!/usr/bin/env bash' 'f() { grep -q -- "$1" "$BLK"; }' 'BLK=/dev/null' 'f x' >"$sb/n/scripts/gates/cm_needle.sh"
out="$(blkrow "$sb/n" scripts/gates/cm_needle.sh)"; [ -n "$out" ]; chk $? "N0 positive needle: a planted \$BLK body read before BLK= is reported"
printf '%s\n' '#!/usr/bin/env bash' 'f() { grep -q -- "$1" "$2"; }' 'BLK=/dev/null' 'f x "$BLK"' >"$sb/n/scripts/gates/cm_needle.sh"
out="$(blkrow "$sb/n" scripts/gates/cm_needle.sh)"; [ -z "$out" ]; chk $? "N1 negative needle: the argument form is not reported${out:+: $out}"
out="$(blkrow "$src" "$PRD")"; [ -z "$out" ]; chk $? "C1 no BLK read-before-assign row for $PRD${out:+: $out}"
out="$(blkrow "$src" "$RLG")"; [ -z "$out" ]; chk $? "C2 no BLK read-before-assign row for $RLG${out:+: $out}"
OUT="$(cd / && bash "$src/scripts/gates/cm_gate_env_reads_allowlisted.sh" --root "$src" 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q '^VERDICT: PASS .*uncovered=0 stale=0 needle=ok' <<<"$OUT"; chk $? "C3 env gate PASSes on the real tree (rc=$rc: $(tail -n 1 <<<"$OUT"))"
for g in "$PRD" "$RLG"; do
  o="$(cd / && bash "$src/$g" 2>&1)"; r=$?; [ "$r" = 0 ]; chk $? "C4/C5 $g PASSes on the real tree (rc=$r: $(tail -n 1 <<<"$o"))"
done
# mutants: each gate is self-contained (no sourced library), so a mutated copy runs with --root on the real tree, and the
# census reads a copy of the single file under a scratch root
mk() { local d="$sb/$1"; mkdir -p "$d/scripts/gates"; cp -- "$src/$2" "$d/$2"; printf '%s' "$d"; }
for g in "$PRD" "$RLG"; do
  d="$(mk "m1$(basename "$g" .sh)" "$g")"
  sed -i 's|^names_cm_gate_in_block() { case "\$1" in CM-?\*) grep -F -q -- "\$1" "\$2" ;;|names_cm_gate_in_block() { case "$1" in CM-?*) grep -F -q -- "$1" "$BLK" ;;|' "$d/$g"
  grep -q '^names_cm_gate_in_block() .*grep -F -q -- "\$1" "\$BLK"' "$d/$g"; chk $? "M1 setup: old body (reads \$BLK) restored in a copy of $g"
  out="$(blkrow "$d" "$g")"; [ -n "$out" ]; chk $? "M1 mutant (old \$BLK read) in $g is seen by the census"
done
for pair in "M2 $PRD" "M3 $RLG"; do
  set -- $pair; d="$(mk "$1" "$2")"; g="$2"
  sed -i 's|names_cm_gate_in_block "\$DG" "\$BLK"|names_cm_gate_in_block "$DG" /dev/null|' "$d/$g"
  grep -q 'names_cm_gate_in_block "\$DG" /dev/null' "$d/$g"; chk $? "$1 setup: call site of $g passes /dev/null"
  o="$(cd / && bash "$d/$g" --root "$src" 2>&1)"; r=$?
  [ "$r" != 0 ] && grep -q '^FAIL .*deferral names a CM-\* gate that the' <<<"$o"; chk $? "$1 mutant: $g FAILs on its seam check (rc=$r)"
done
echo "== $pass passed, $fail failed =="
[ "$fail" = 0 ]
