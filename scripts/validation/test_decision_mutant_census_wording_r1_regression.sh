#!/bin/bash
# Purpose : CON-159 regression guard for the WORDING of the decision-mutant census
#           (review fsfix6 m1). enumerate_decision_mutants.py uses a CLOSED list of
#           single-edit operators, so it enumerates the decision points those
#           operators MATCH, not every decision point of its targets (reviewer
#           mutants Y1, Y2, Y8, Y9, Y10 are real decision-point mutants no operator
#           generates). The tool docstring, the meta-test header that cites it and the
#           CON-158 tracker text said "every decision point" / "closes the class".
# Usage   : bash test_decision_mutant_census_wording_r1_regression.sh
#           Exit 0 when every check passes, 1 otherwise; the last line is the summary.
# Method  : greps the REAL files (the tool, the meta-test, docs/Issues.md section of
#           CON-158); control needles: each file is read (a known heading/phrase is
#           found) before an absence is believed. Paired mutants re-insert the
#           overstating phrase into a copy of each file; each must fail its check.
#           CON-219 (review fu_a n1, reviewer mutant RH): the guard matched only the
#           three historical phrases, so a re-overstatement in other words passed.
#           The docstring's accurate scope sentence is now PINNED (whitespace
#           normalised: "enumerates the decision points of a fixed set of target
#           scripts that are matched by its closed list of single-edit operators"
#           and "not that every decision point is covered"), and any
#           "enumerates/covers/mutates all|every|each decision point" wording fails.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=$((fail + 1)); echo "NOT ok $*"; }
TMP=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 1; }
trap 'rm -rf "${TMP:?}"' EXIT

# checks <enum.py> <meta-test.sh> <Issues.md> -> prints "ok"/"NOT ok" lines, returns the failure count
checks() {
  local e=$1 m=$2 i=$3 bad=0 sect
  grep -q 'enumerate_decision_mutants' "$e" && grep -q 'Operators:' "$e" || { echo "NOT ok control needle: tool docstring not read"; return 9; }
  grep -q 'single-edit mutant' "$m" || { echo "NOT ok control needle: meta-test header not read"; return 9; }
  sect=$(awk '/^## CON-158 /{f=1;next} /^## CON-/{f=0} f' "$i")
  printf '%s' "$sect" | grep -q 'enumerate_decision_mutants.py' || { echo "NOT ok control needle: CON-158 section not read"; return 9; }
  if grep -Eq 'enumerates EVERY decision point' "$e"; then echo "NOT ok tool docstring still says it enumerates EVERY decision point"; bad=$((bad+1)); else echo "ok tool docstring does not claim EVERY decision point"; fi
  if grep -Eq 'closed list' "$e" && grep -Eq 'MATCHED by|matched by' "$e"; then echo "ok tool docstring states the scope: decision points matched by the closed operator list"; else echo "NOT ok tool docstring lacks the scope statement (matched by the closed operator list)"; bad=$((bad+1)); fi
  # CON-219: pin the accurate wording (newlines and runs of spaces normalised), reject any re-wording that claims all/every/each.
  if tr -s ' \n' '  ' < "$e" | grep -Fq 'enumerates the decision points of a fixed set of target scripts that are matched by its closed list of single-edit operators' \
     && tr -s ' \n' '  ' < "$e" | grep -Fq 'not that every decision point is covered'; then echo "ok tool docstring keeps the pinned scope sentences"; else echo "NOT ok tool docstring lost a pinned scope sentence (CON-219)"; bad=$((bad+1)); fi
  if tr -s ' \n' '  ' < "$e" | grep -Eiq '(enumerates|covers|mutates|generates) (all|every|each) (of )?(the )?decision points?'; then echo "NOT ok tool docstring claims all/every/each decision point (CON-219)"; bad=$((bad+1)); else echo "ok tool docstring does not claim all/every/each decision point"; fi
  if grep -Eq 'single-edit mutant of every decision point' "$m"; then echo "NOT ok meta-test header still says single-edit mutant of every decision point"; bad=$((bad+1)); else echo "ok meta-test header does not claim every decision point"; fi
  if printf '%s' "$sect" | grep -Eq 'Class closed \(section 11\.4\.274\): scripts/validation/enumerate_decision_mutants\.py enumerates every decision point'; then echo "NOT ok CON-158 text still says the census closes the class and enumerates every decision point"; bad=$((bad+1)); else echo "ok CON-158 text does not claim the census closes the class"; fi
  return $bad
}
OUT=$(checks "$ROOT/scripts/validation/enumerate_decision_mutants.py" "$ROOT/scripts/validation/test_meta_test_verification_r1_regression.sh" "$ROOT/docs/Issues.md"); RC=$?
printf '%s\n' "$OUT" | sed 's/^/  | /'
[ $RC = 0 ] && ok "real files: all 6 wording checks pass" || notok "real files: $RC failing"

# paired mutants: re-insert the overstating phrase, each must fail
cp "$ROOT/scripts/validation/enumerate_decision_mutants.py" "$TMP/e.py"; cp "$ROOT/scripts/validation/test_meta_test_verification_r1_regression.sh" "$TMP/m.sh"; cp "$ROOT/docs/Issues.md" "$TMP/i.md"
python3 -I - "$TMP" <<'PY' || { notok "mutant setup failed (blind)"; exit 1; }
import sys, re
d = sys.argv[1]
e = open(d + "/e.py").read(); open(d + "/e1.py", "w").write(e.replace("This tool enumerates", "This tool enumerates EVERY decision point of a fixed set, enumerates EVERY decision point", 1) if "This tool enumerates" in e else e + "\nenumerates EVERY decision point\n")
m = open(d + "/m.sh").read(); open(d + "/m1.sh", "w").write(m + "\n# single-edit mutant of every decision point\n")
i = open(d + "/i.md").read()
k = i.index("## CON-158 ")
# CON-219: reviewer mutant RH (fu_a review) verbatim, and a drop of the scope sentence.
assert e.count("enumerates the decision points") == 1, "RH pattern"
open(d + "/e2.py", "w").write(e.replace("enumerates the decision points", "enumerates all decision points", 1))
sc = "that every decision point is covered"
assert e.count(sc) == 1, "scope pattern"
open(d + "/e3.py", "w").write(e.replace(sc, "that the closed list is complete", 1))
open(d + "/i1.md", "w").write(i[:k] + "## CON-158 x\nClass closed (section 11.4.274): scripts/validation/enumerate_decision_mutants.py enumerates every decision point\n\n" + i[k + len("## CON-158 "):])
PY
for pair in "M1_tool_claims_every:$TMP/e1.py:$TMP/m.sh:$TMP/i.md" "M2_meta_header_claims_every:$TMP/e.py:$TMP/m1.sh:$TMP/i.md" "M3_tracker_claims_closes_class:$TMP/e.py:$TMP/m.sh:$TMP/i1.md" "RH_enumerates_all:$TMP/e2.py:$TMP/m.sh:$TMP/i.md" "M4_scope_sentence_dropped:$TMP/e3.py:$TMP/m.sh:$TMP/i.md"; do
  IFS=: read -r n e m i <<<"$pair"
  checks "$e" "$m" "$i" >/dev/null && notok "mutant $n SURVIVED" || ok "mutant $n killed"
done
echo "=== census wording r1 (CON-159): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
