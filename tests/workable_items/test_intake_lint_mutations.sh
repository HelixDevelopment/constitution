#!/usr/bin/env bash
# tests/workable_items/test_intake_lint_mutations.sh -- paired mutation test (section 1.1) for
# scripts/workable-items/intake_lint.py and its suite tests/workable_items/test_intake_lint.sh.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md.
#
# WHAT  Each mutant is one exact text replacement in a COPY of the lint (the replaced text must occur
#   exactly once, otherwise the mutant is stale and the test fails). For each mutant the suite runs
#   twice: (a) with --no-selfcheck, so the suite's own cases must kill it; (b) as shipped, where a
#   mutant of a check must also be stopped by the built-in control needles (BLIND, exit 3). An
#   unmutated copy must pass both runs (the control).
# EXIT  0 every mutant killed as declared and the control passes; 1 otherwise; 2 setup error.
# EVIDENCE CLASS  gate-logic only (section 11.4.289).
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
root=$(cd "$here/../.." && pwd) || exit 2
src=$root/scripts/workable-items/intake_lint.py
suite=$here/test_intake_lint.sh
[ -f "$src" ] && [ -f "$suite" ] || { echo "setup: lint or suite missing" >&2; exit 2; }
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$root/scripts/lib/safe_rm.sh" || exit 2
tmp=$(mktemp -d) || exit 2
trap 'safe_rm_rf "${tmp:?}"' EXIT

# Escapes in old/new: \n is a newline, \\n is a literal backslash-n (as written in Python source).
# id | needle (yes: the control needles must stop it too; no: only the suite's cases reach it) | old | new
mutants=(
  'O1 XREF-DANGLING check off|yes|            if ref not in all_items:|            if False and ref not in all_items:'
  'O2 XREF-LABEL check off|yes|                if lw and not (lw & words(all_items[ref]["title"])):|                if False:'
  'O3 declared foreign ids not excluded|yes|            if ref in fids:\n                continue|            if False:\n                continue'
  'O4 ephemeral note exempts the whole description|yes|            if "(ephemeral" in line:|            if "(ephemeral" in desc:'
  'O5 UNREPRODUCED accepted for any column value|yes|                ok = (rs in UNREPRO_FAMILY) if canon == "UNREPRODUCED" else (rs == canon)\n                if not ok:\n                    findings.append(("STATE-PROSE", iid, "prose says|                ok = True if canon == "UNREPRODUCED" else (rs == canon)\n                if not ok:\n                    findings.append(("STATE-PROSE", iid, "prose says'
  'O6 structured state line not checked|yes|            if line.startswith("**Reproduction:**"):|            if False:'
  'O7 PATH-MISSING check off|yes|                if not exists(rel):|                if False:'
  'O8 SAME-DEFECT head not compared|no| and head in dup_named):|):'
  'O9 SHARED-PATH check off|yes|            if hit and o["id"] not in dup_named:|            if False:'
  'O10 empty selection exits 0|no|        print("BLIND: the selection is empty", file=sys.stderr)\n        return 3|        print("BLIND: the selection is empty", file=sys.stderr)\n        return 0'
  'O11 unknown --skip-check code accepted|no|        print("intake_lint: unknown --skip-check code(s): " + ",".join(unknown), file=sys.stderr)\n        return 2|        print("intake_lint: unknown --skip-check code(s): " + ",".join(unknown), file=sys.stderr)'
  'O12 SECRET does not scan the title|no|            if pat.search(r["title"] + "\\n" + desc):|            if pat.search(desc):'
  'O13 XREF does not scan the title|no|        body_text = r["title"] + "\\n" + text_without_foreign_line(desc)|        body_text = text_without_foreign_line(desc)'
  'O14 PROBABLY accepted as a verdict|yes|            elif dl.group(1).rstrip(";,.:") not in DUP_VERDICTS:|            elif dl.group(1).rstrip(";,.:") not in DUP_VERDICTS | {"PROBABLY"}:'
  'O15 embeddings call foreign ids own|no|            ns = "foreign" if ref in fids else|            ns = "own" if ref in fids else'
  'O16 BODY-SYNC check off|yes|        if r["body"] and desc not in r["body"]:|        if False:'
  'O17 SECRET prints the matched string|no|                findings.append(("SECRET", iid, name))|                findings.append(("SECRET", iid, name + " " + pat.search(r["title"] + "\\n" + desc).group(0)))'
  'O18 FOREIGN-STALE check off|yes|        for f in sorted(fids - named):|        for f in []:'
  'O19 unreadable database exits 0|no|        print("BLIND: database unreadable: %s" % e, file=sys.stderr)\n        return 3|        print("BLIND: database unreadable: %s" % e, file=sys.stderr)\n        return 0'
)

mkcopy() { # mkcopy <dest> <old> <new>  (\n in old/new is a newline)
  python3 -I - "$src" "$1" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
def unesc(t):  # "\\\\n" (two backslashes) is a literal backslash-n; "\\n" is a newline
    return t.replace("\\\\n", "\0").replace("\\n", "\n").replace("\0", "\\n")
old, new = unesc(old), unesc(new)
s = open(src).read()
n = s.count(old)
if old and n != 1:
    sys.stderr.write("stale mutant: %d matches for %r\n" % (n, old[:80])); sys.exit(1)
open(dst, "w").write(s.replace(old, new) if old else s)
PY
}
runs() { # runs <lint> <extra> -> prints the suite rc; stdout of the suite into $tmp/log
  INTAKE_LINT=$1 INTAKE_LINT_EXTRA=$2 bash "$suite" >"$tmp/log" 2>&1
  echo $?
}

fail=0
mkcopy "$tmp/ctl.py" "" "" || exit 2
a=$(runs "$tmp/ctl.py" --no-selfcheck); b=$(runs "$tmp/ctl.py" "")
if [ "$a" = 0 ] && [ "$b" = 0 ]; then echo "PASS control: unmutated copy passes both runs"
else echo "FAIL control: rc no-selfcheck=$a shipped=$b"; fail=1; fi

for m in "${mutants[@]}"; do
  id=${m%%|*}; rest=${m#*|}; needle=${rest%%|*}; rest=${rest#*|}; old=${rest%%|*}; new=${rest#*|}
  if ! mkcopy "$tmp/m.py" "$old" "$new"; then echo "FAIL $id: stale mutant"; fail=1; continue; fi
  a=$(runs "$tmp/m.py" --no-selfcheck)
  b=$(runs "$tmp/m.py" ""); nb=no; grep -q 'BLIND: control needle failed' "$tmp/log" && nb=yes
  verdict=PASS
  [ "$a" = 0 ] && verdict=FAIL
  [ "$b" = 0 ] && verdict=FAIL
  [ "$needle" = yes ] && [ "$nb" != yes ] && verdict=FAIL
  [ "$verdict" = FAIL ] && fail=1
  echo "$verdict $id: cases-kill=$([ "$a" != 0 ] && echo yes || echo no) needle-kill=$nb (declared $needle)"
done
echo "RESULT: mutants=${#mutants[@]} $([ "$fail" = 0 ] && echo 'all killed as declared' || echo 'FAILED')"
[ "$fail" = 0 ]
