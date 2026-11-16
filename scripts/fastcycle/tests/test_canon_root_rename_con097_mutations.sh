#!/bin/sh
# Purpose: paired section 1.1 mutations for test_canon_root_rename_con097_red.sh (CON-097). Each mutant is a copy
#          of the RED test with one edit (run from this directory so its live half reaches this canon), or the
#          real RED test run against a mutated copy of the tests (data mutants). Every mutant must make it FAIL.
# Usage:   sh test_canon_root_rename_con097_mutations.sh     Exit 0 = real test passes, every mutant killed.
here=$(cd "$(dirname "$0")" && pwd)
red="$here/test_canon_root_rename_con097_red.sh"
tmp=$(mktemp -d) || exit 2
trap 'rm -f "$here/.con097_mut_$$.sh"; rm -rf "$tmp"' EXIT
fail=0
sh "$red" >"$tmp/real.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && echo "ok real RED test passes" || { echo "NOT ok real RED test rc=$rc"; fail=1; }
kill_check() { [ "$2" -ne 0 ] && echo "ok mutant $1 killed (rc=$2)" || { echo "NOT ok mutant $1 SURVIVED"; fail=1; }; }
# code mutants: old=>new on a copy placed beside the real test (so $here resolves identically)
cat >"$tmp/mutants" <<'EOM'
R1 pattern-misses-braced-form|\$\{?(ROOT|REPO_ROOT)\}?/constitution=>\$(ROOT|REPO_ROOT)/constitution
R2 pattern-too-broad|/constitution([^A-Za-z0-9_]|$)'=>/constitution'
R3 census-blind|grep -nE "$PAT" "$1"/test_*.sh=>grep -nE "$PAT" "$1"/nomatch_*.sh
R4 rename-precondition-lost|name="canon_renamed_$$"=>name="constitution"
R5 live-half-skipped|for t in ${FC_CON097_LIVE_TESTS:-test_tower_detector_red.sh test_reopen_rate_state_red.sh test_governance_subset_conservative.sh test_custody_sweep_r9_regression.sh test_fc_entry_r10_regression.sh}; do=>for t in ; do
R7 tool-default-case-dropped|for t in ${FC_CON097_LIVE_TESTS:-test_tower_detector_red.sh test_reopen_rate_state_red.sh test_governance_subset_conservative.sh test_custody_sweep_r9_regression.sh test_fc_entry_r10_regression.sh}; do=>for t in ${FC_CON097_LIVE_TESTS:-test_tower_detector_red.sh test_reopen_rate_state_red.sh test_custody_sweep_r9_regression.sh test_fc_entry_r10_regression.sh}; do
R8 git-checkout-cases-dropped|for t in ${FC_CON097_LIVE_TESTS:-test_tower_detector_red.sh test_reopen_rate_state_red.sh test_governance_subset_conservative.sh test_custody_sweep_r9_regression.sh test_fc_entry_r10_regression.sh}; do=>for t in ${FC_CON097_LIVE_TESTS:-test_tower_detector_red.sh test_reopen_rate_state_red.sh test_governance_subset_conservative.sh}; do
R6 self-exclusion-excludes-all|    case $b in test_canon_root_rename_con097_red.sh|test_canon_root_rename_con097_mutations.sh) continue ;; esac=>    continue
EOM
while IFS='|' read -r id edit; do
  [ -n "$id" ] || continue
  m="$here/.con097_mut_$$.sh"; cp "$red" "$m"
  if ! MEDIT=$edit python3 -c 'import os,sys
o,n=os.environ["MEDIT"].split("=>",1); p=sys.argv[1]; s=open(p).read()
if s.count(o)!=1: sys.exit(3)
open(p,"w").write(s.replace(o,n))' "$m"; then echo "NOT ok mutant $id: edit did not apply"; fail=1; rm -f "$m"; continue; fi
  case $id in R4*|R5*|R7*|R8*) scan=$here ;; *) scan=$tmp/rev ;; esac
  if [ ! -d "$tmp/rev" ]; then  # data for code mutants: the real tests with ONE converted test reverted
    mkdir "$tmp/rev"; cp "$here"/test_*.sh "$tmp/rev/"
    sed -i 's#FC="$FC_CANON_ROOT/scripts/fastcycle"#FC="$ROOT/constitution/scripts/fastcycle"#' "$tmp/rev/test_handoff_red.sh"
    grep -q 'FC="$ROOT/constitution/scripts/fastcycle"' "$tmp/rev/test_handoff_red.sh" || { echo "NOT ok cannot build the reverted copy"; fail=1; }
  fi
  case $id in R1*|R6*) FC_CON097_SCAN_DIR=$tmp/rev FC_TEST_FAILFAST=1 sh "$m" >"$tmp/m.out" 2>&1 ;;
              *) FC_CON097_SCAN_DIR=$scan FC_TEST_FAILFAST=1 sh "$m" >"$tmp/m.out" 2>&1 ;; esac
  kill_check "$id" $?
  rm -f "$m"
done <"$tmp/mutants"
# data mutants: the real RED test against (D1) a tests copy with one converted test reverted, (D2) an empty dir.
FC_CON097_SCAN_DIR=$tmp/rev sh "$red" >"$tmp/d1.out" 2>&1; kill_check "D1 one-test-reverted-to-ROOT/constitution" $?
grep -q "test_handoff_red.sh" "$tmp/d1.out" && echo "ok D1 names the reverted file" || { echo "NOT ok D1 does not name the reverted file"; fail=1; }
mkdir "$tmp/empty"; FC_CON097_SCAN_DIR=$tmp/empty sh "$red" >"$tmp/d2.out" 2>&1; kill_check "D2 empty-scan-dir-is-blind" $?
[ "$fail" -eq 0 ] && { echo "test_canon_root_rename_con097_mutations: all ok"; exit 0; }
echo "test_canon_root_rename_con097_mutations: FAILED"; exit 1
