#!/usr/bin/env bash
# tests/test_run_full_suite_mutations_table.sh -- the mutation harness tests/test_run_full_suite_mutations.sh
# refuses a MUTANTS table with a duplicate mutant id before it runs anything (CON-236).
# Oracle strategy: SPECIFIED (CON-236 acceptance: a duplicate id is refused with a non-zero exit before
# any mutant, and before the baseline, runs). Each case copies the harness, the runner and the safe_rm
# helper into a mktemp tree and replaces tests/test_run_full_suite.sh there with a small self-test
# that passes on the unmutated engine and prints a `FAIL ` line on any other engine, so the case
# exercises only the harness's own control flow (gate-logic test, section 11.4.289(C)(2)); it says
# nothing about the real self-test. Paired mutation (section 1.1): the same cases are run against a
# copy of the harness with the duplicate-id check removed, and at least one case MUST fail there.
# Usage: bash tests/test_run_full_suite_mutations_table.sh   (exit 0 = all checks pass, mutant killed)
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/rfs_mtab.XXXXXX") || exit 2
: "${T:?}"
. "$HERE/scripts/lib/safe_rm.sh" || exit 2
trap 'TMPDIR="$(dirname "$T")" safe_rm_rf "${T:?}" >/dev/null 2>&1' EXIT
pass=0; fail=0

# The duplicate-id check of the harness, as one exact line; the paired mutant deletes it.
CHECK_LINE='if [ -n "$dup_ids" ]; then echo "FAIL mutant table: duplicate mutant id(s): $dup_ids (each id must occur once; nothing was run)"; exit 2; fi'

mk() { # $1 harness source file, $2 dest dir, $3 "dup" to append a row repeating M3
  local h=$1 d=$2 mode=${3:-} ref
  mkdir -p "$d/tests" "$d/scripts/full_suite" "$d/scripts/lib"
  cp "$h" "$d/tests/test_run_full_suite_mutations.sh"
  cp "$HERE/scripts/run_full_suite.sh" "$d/scripts/"
  cp "$HERE/scripts/full_suite/run_full_suite.py" "$d/scripts/full_suite/"
  cp "$HERE/scripts/lib/safe_rm.sh" "$HERE/scripts/lib/protected_paths.list" "$d/scripts/lib/"
  ref=$(sha256sum "$d/scripts/full_suite/run_full_suite.py" | cut -c1-64)
  {
    echo '#!/usr/bin/env bash'
    echo 'e="$(dirname "$FSR_RUNNER")/full_suite/run_full_suite.py"'
    echo "if [ \"\$(sha256sum \"\$e\" | cut -c1-64)\" = \"$ref\" ]; then echo 'ok   engine unmutated'; exit 0; fi"
    echo "echo 'FAIL engine mutated'; exit 1"
  } > "$d/tests/test_run_full_suite.sh"
  if [ "$mode" = dup ]; then
    python3 -I - "$d/tests/test_run_full_suite_mutations.sh" <<'PY' || return 1
import sys
p = sys.argv[1]; s = open(p).read()
row = [l for l in s.split("\n") if l.startswith("M3\t")]
end = "\nEOF\n)\n"
if len(row) != 1 or s.count(end) != 1:
    sys.exit("fixture: M3 row or table end not unique")
open(p, "w").write(s.replace(end, "\n" + row[0] + end, 1))
PY
  fi
}

cases() { # $1 harness file, $2 tag -> number of failed checks (stdout: check lines)
  local h=$1 tag=$2 f=0 d rc log
  ck() { if [ "$2" = "$3" ]; then echo "ok   [$tag] $1"; else echo "FAIL [$tag] $1 (want '$3' got '$2')"; f=$((f+1)); fi; }
  # golden-FALSE: a table without duplicates runs the selected mutant once
  d="$T/$tag.good"; mk "$h" "$d" || return 99
  log="$d.log"; (cd "$d" && TMPDIR="$T" bash tests/test_run_full_suite_mutations.sh M3) >"$log" 2>&1; rc=$?
  ck "no duplicate: exit 0" "$rc" "0"
  ck "no duplicate: baseline ran" "$(grep -c '^ok   baseline' "$log")" "1"
  ck "no duplicate: M3 killed exactly once" "$(grep -c '^killed M3 ' "$log")" "1"
  # golden-TRUE: a duplicate id is refused before anything runs, also when it is the selected id
  for sel in M3 ""; do
    d="$T/$tag.dup${sel:-all}"; mk "$h" "$d" dup || return 99
    log="$d.log"; (cd "$d" && TMPDIR="$T" bash tests/test_run_full_suite_mutations.sh $sel) >"$log" 2>&1; rc=$?
    ck "duplicate (args: '${sel}'): exit 2" "$rc" "2"
    ck "duplicate (args: '${sel}'): refusal names M3" "$(grep -c '^FAIL mutant table: duplicate mutant id(s): M3 ' "$log")" "1"
    ck "duplicate (args: '${sel}'): baseline not run" "$(grep -c 'baseline' "$log")" "0"
    ck "duplicate (args: '${sel}'): no mutant run" "$(grep -cE '^(killed|SURVIVED|BAD) ' "$log")" "0"
  done
  return "$f"
}

H="$HERE/tests/test_run_full_suite_mutations.sh"
cases "$H" real; n=$?
if [ "$n" -eq 0 ]; then pass=$((pass+1)); echo "ok   real harness: all cases pass"
else fail=$((fail+1)); echo "FAIL real harness: $n case check(s) failed"; fi
if [ "$(grep -cxF -- "$CHECK_LINE" "$H")" != 1 ]; then
  echo "FAIL the duplicate-id check line occurs $(grep -cxF -- "$CHECK_LINE" "$H") time(s) in $H (want 1)"; echo "passed=$pass failed=$((fail+1))"; exit 1
fi

# paired mutant: the harness without its duplicate-id check
M="$T/mutant_harness.sh"
grep -vxF -- "$CHECK_LINE" "$H" > "$M"
cases "$M" mutant > "$T/mutant.out"; n=$?
if [ "$n" -gt 0 ] && [ "$n" -ne 99 ]; then pass=$((pass+1)); echo "ok   paired mutant (duplicate-id check removed) is killed: $n case check(s) fail"
else fail=$((fail+1)); echo "FAIL paired mutant (duplicate-id check removed) survived (failed checks: $n)"; cat "$T/mutant.out"; fi

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
