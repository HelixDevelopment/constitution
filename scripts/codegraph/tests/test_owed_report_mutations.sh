#!/usr/bin/env bash
# ============================================================================
# test_owed_report_mutations.sh — paired §1.1 mutation harness for owed_report.py
# ============================================================================
# Purpose      Prove every guard of owed_report.py is load-bearing: the GOLDEN tool passes test_owed_report.py; each mutant
#              (substring reference accepted, filename-suffix boundary dropped, fixtures counted as tests, guide always present,
#              --strict never blocks, blind scan accepted, runner patches not discovered, name-rule loosened) must make the suite FAIL.
#              A surviving mutant = a test that cannot catch that defect.
# Usage        bash test_owed_report_mutations.sh      (exit 0 only if golden passes AND every mutant is killed)
# Inputs       ../owed_report.py, ./test_owed_report.py
# Outputs      lines `GOLDEN PASS|FAIL` and `MUTANT Mn KILLED|SURVIVED <what>`; exit 1 on any golden failure or survivor
# Side effects temp dir under $TMPDIR (removed on exit); never touches the real tool or any repo file
# Dependencies bash, python3
# Cross-refs   owed_report.py, test_owed_report.py, docs/scripts/owed_report.md, constitution §1.1 / §11.4.224
# ============================================================================
set -u
HERE=$(cd "$(dirname "$0")" && pwd); GOLD="$HERE/../owed_report.py"
W=$(mktemp -d "${TMPDIR:-/tmp}/owed_mut.XXXXXX"); trap 'rm -rf "$W"' EXIT
fail=0
run_suite() { TOOL="$1" python3 "$HERE/test_owed_report.py" >"$W/out.txt" 2>&1; }
if run_suite "$GOLD"; then echo "GOLDEN PASS"; else echo "GOLDEN FAIL (see suite)"; fail=1; fi
mutate() {  # id, description, OLD, NEW (exactly-once replacement in a copy of the tool)
  local id=$1 desc=$2; cp "$GOLD" "$W/$id.py"
  OLD=$3 NEW=$4 F="$W/$id.py" python3 - <<'PY' || { echo "MUTANT $id NOT-APPLIED (anchor text moved — update harness)"; fail=1; return; }
import os,sys
p=os.environ["F"]; s=open(p,encoding="utf-8").read(); o=os.environ["OLD"]; n=os.environ["NEW"]
if s.count(o)!=1: sys.exit(1)
open(p,"w",encoding="utf-8").write(s.replace(o,n))
PY
  if run_suite "$W/$id.py"; then echo "MUTANT $id SURVIVED $desc"; fail=1; else echo "MUTANT $id KILLED $desc"; fi
}
mutate M1 "leading boundary dropped (substring counts as a test reference)" '(?<![A-Za-z0-9_.\-])' ''
mutate M2 "filename trailing boundary dropped (.bak / .jsx counted)" '(?![A-Za-z0-9_]|\.[A-Za-z0-9])' '(?![A-Za-z0-9_])'
mutate M3 "fixtures/ counted as tests" 'dns[:] = sorted(d for d in dns if d not in ("fixtures", "__pycache__"))' 'dns[:] = sorted(d for d in dns if d not in ("__pycache__",))'
mutate M4 "guide always considered present" 'owed = (["tests"] if not hits else []) + (["guide"] if guide is None else [])' 'owed = (["tests"] if not hits else [])'
mutate M5 "--strict never blocks" 'return 1 if (a.strict and owed_rows) else 0' 'return 0'
mutate M6 "blind scan accepted (no refusal on zero tools)" '    if not tools:
        refuse(' '    if False:
        refuse('
mutate M7 "runner patches not discovered" 'for f in list_files(os.path.join(cg, "runner_patches"), (".py",)):' 'for f in []:'
mutate M8 "test-name rule loosened to any prefix" 'pat = r"^(?:test_%s(?:_mutate|_mutations)?|t_%s)\.(?:sh|py|js|bats)$" % (re.escape(stem), re.escape(stem))' 'pat = r"^.*%s.*$" % re.escape(stem)'
exit $fail
