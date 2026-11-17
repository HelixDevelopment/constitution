#!/bin/sh
# Purpose: paired section 1.1 mutations for fc_consumer_section / fc_consumer_exit (lib/consumer_section.sh).
#          test_consumer_section_con092_red.sh must PASS on the real library and FAIL on every mutant; an edit
#          that does not apply is a FAIL (no vacuous kill). Recorded equivalent mutant (not in the set): dropping
#          the non-integer check of fc_consumer_exit still exits 2, because `exit abc` is itself a shell error.
# Usage:   sh test_consumer_section_con092_mutations.sh    Exit 0 = real passes, every mutant killed.
here=$(cd "$(dirname "$0")" && pwd)
real="$here/lib/consumer_section.sh"; red="$here/test_consumer_section_con092_red.sh"
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0
FC_CONSUMER_LIB_UNDER_TEST=$real sh "$red" >"$tmp/real.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && echo "ok real library passes the RED test" || { echo "NOT ok real library rc=$rc"; fail=1; }
cat >"$tmp/mutants" <<'EOM'
H1 missing-section-still-runs|    unset _fcs_label _fcs_root _fcs_missing _fcs_p _fcs_abs
    return 1=>    unset _fcs_label _fcs_root _fcs_missing _fcs_p _fcs_abs
    return 0
H2 skipped-exits-0|    exit 77
  fi
  exit 0=>    exit 0
  fi
  exit 0
H3 fail-turned-into-skip|  [ "$1" -eq 0 ] || exit "$1"
  if [ "${FC_CONSUMER_SECTIONS_SKIPPED:-0}" -gt 0 ]; then=>  if [ "${FC_CONSUMER_SECTIONS_SKIPPED:-0}" -gt 0 ]; then
H4 skip-not-counted|    FC_CONSUMER_SECTIONS_SKIPPED=$(( ${FC_CONSUMER_SECTIONS_SKIPPED:-0} + 1 ))=>    :
H5 no-reason-code|$_fcs_missing reason=topology_unsupported"=>$_fcs_missing"
H6 dir-counts-as-absent|    [ -e "$_fcs_abs" ] || _fcs_missing=>    [ -f "$_fcs_abs" ] || _fcs_missing
H7 absolute-under-root|    case $_fcs_p in /*) _fcs_abs=$_fcs_p ;;=>    case $_fcs_p in /*) _fcs_abs=$_fcs_root$_fcs_p ;;
H8 always-skip|  if [ "${FC_CONSUMER_SECTIONS_SKIPPED:-0}" -gt 0 ]; then=>  if [ "${FC_CONSUMER_SECTIONS_SKIPPED:-0}" -ge 0 ]; then
EOM
python3 - "$tmp/mutants" "$tmp" <<'PY'
import sys,re
txt=open(sys.argv[1]).read()
# a mutant starts with an id line "Hn name|"; old=>new may span lines
parts=re.split(r'(?m)^(H\d+ [^|]+)\|',txt)[1:]
for i in range(0,len(parts),2):
    open('%s/mut_%d'%(sys.argv[2],i//2),'w').write(parts[i]+'\n'+parts[i+1].rstrip('\n'))
PY
for m in "$tmp"/mut_*; do
  id=$(head -n 1 "$m"); mkdir "$tmp/m"; cp "$real" "$tmp/m/lib.sh"
  if ! python3 -c 'import sys
L=open(sys.argv[1]).read().split("\n",1)[1]; o,n=L.split("=>",1); p=sys.argv[2]; s=open(p).read()
if s.count(o)!=1: sys.exit(3)
open(p,"w").write(s.replace(o,n))' "$m" "$tmp/m/lib.sh"; then
    echo "NOT ok mutant $id: edit did not apply"; fail=1
  else
    FC_CONSUMER_LIB_UNDER_TEST=$tmp/m/lib.sh FC_TEST_FAILFAST=1 sh "$red" >"$tmp/m.out" 2>&1; rc=$?
    [ "$rc" -ne 0 ] && echo "ok mutant $id killed (rc=$rc)" || { echo "NOT ok mutant $id SURVIVED"; fail=1; }
  fi
  rm -rf "${tmp:?}/m"
done
[ "$fail" -eq 0 ] && { echo "test_consumer_section_con092_mutations: all ok"; exit 0; }
echo "test_consumer_section_con092_mutations: FAILED"; exit 1
