#!/bin/sh
# Purpose: paired section 1.1 mutations for the CON-262 exit-77 handling of run_all.sh. Each mutant is a
#          copy of run_all.sh with one edit; test_run_all_skip77_con262_red.sh must FAIL on every mutant
#          and PASS on the real file. A mutant whose edit does not apply is a FAIL (no vacuous kill).
# Usage:   sh test_run_all_skip77_con262_mutations.sh     Exit 0 = real file passes and every mutant killed.
here=$(cd "$(dirname "$0")" && pwd)
real="$here/run_all.sh"; red="$here/test_run_all_skip77_con262_red.sh"
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0
FC_RUN_ALL_UNDER_TEST=$real sh "$red" >"$tmp/real.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && echo "ok real run_all passes the RED test" || { echo "NOT ok real run_all rc=$rc"; fail=1; }
# id|python replacement old=>new (exact substring, must occur once)
cat >"$tmp/mutants" <<'EOM'
K1 77-read-as-PASS|  if [ "$trc" -eq 0 ]; then echo "PASS $(basename "$t")"=>  if [ "$trc" -eq 0 ] || [ "$trc" -eq 77 ]; then echo "PASS $(basename "$t")"
K2 77-read-as-FAIL (pre-fix behaviour)|  elif [ "$trc" -eq 77 ]; then=>  elif [ "$trc" -eq 7777 ]; then
K3 skip-exits-0|[ "$skipped" -eq 0 ] || exit 77=>[ "$skipped" -eq 0 ] || exit 0
K4 no-skip-count-line|[ "$skipped" -eq 0 ] || echo "run_all:=>[ "$skipped" -eq 0 ] || : "run_all:
K5 range-ge-77-is-skip|  elif [ "$trc" -eq 77 ]; then=>  elif [ "$trc" -ge 77 ]; then
K6 skip-beats-fail|[ "$failed" -eq 0 ] || exit 1=>[ "$skipped" -eq 0 ] || exit 77; [ "$failed" -eq 0 ] || exit 1
K7 skip-not-counted|echo "SKIP $(basename "$t")"; skipped=$((skipped + 1))=>echo "SKIP $(basename "$t")"
K8 skip-label-wrong|echo "SKIP $(basename "$t")"=>echo "PASS $(basename "$t")"
EOM
while IFS='|' read -r id edit; do
  [ -n "$id" ] || continue
  mkdir "$tmp/m"; cp "$real" "$tmp/m/run_all.sh"
  if ! MEDIT=$edit python3 -c 'import os,sys
o,n=os.environ["MEDIT"].split("=>",1); p=sys.argv[1]; s=open(p).read()
if s.count(o)!=1: sys.exit(3)
open(p,"w").write(s.replace(o,n))' "$tmp/m/run_all.sh"; then
    echo "NOT ok mutant $id: edit did not apply (anchor text changed)"; fail=1
  else
    FC_RUN_ALL_UNDER_TEST=$tmp/m/run_all.sh FC_TEST_FAILFAST=1 sh "$red" >"$tmp/m.out" 2>&1; rc=$?
    [ "$rc" -ne 0 ] && echo "ok mutant $id killed (rc=$rc)" || { echo "NOT ok mutant $id SURVIVED"; fail=1; }
  fi
  rm -rf "${tmp:?}/m"
done <"$tmp/mutants"
[ "$fail" -eq 0 ] && { echo "test_run_all_skip77_con262_mutations: all ok"; exit 0; }
echo "test_run_all_skip77_con262_mutations: FAILED"; exit 1
