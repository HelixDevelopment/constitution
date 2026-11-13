#!/usr/bin/env bash
# tests/workable_items/test_intake_lint_mutations.sh -- paired mutation test (section 1.1) for
# scripts/workable-items/intake_lint.py and its suite tests/workable_items/test_intake_lint.sh.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md.
#
# WHAT  Each mutant is one exact text replacement in a COPY of the lint, or of the suite (target S);
#   the replaced text must occur exactly once, otherwise the mutant is stale and the test fails.
#   For each mutant: (a) the suite runs with --no-selfcheck (and stops at its first failing case),
#   so the suite's own cases must kill it; (b) for a lint mutant declared "yes", the shipped lint's
#   built-in control needles must also stop it (one direct call, which must print
#   "BLIND: control needle failed"). An unmutated copy must pass the full suite (the control).
#   The O-mutants are the round-1/round-2 set, adapted to the v3 text; the C-mutants are the round-2
#   reviewer's surviving code mutants (C2, C3, C4, C6, C8, C9, C11, C14); the N-mutants cover the
#   checks added in round 3; S1 mutates the suite's own cleanup (round-2 review R2-10).
# ENV   INTAKE_LINT_MUT_JOBS  parallel mutants (default 3)
#       INTAKE_LINT_MUT_ONLY  run only the mutants whose id is listed (comma separated)
# EXIT  0 every mutant killed as declared and the control passes; 1 otherwise; 2 setup error, or
#       the cleanup of the temp dir was refused.
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
cleanup() {
  local st=$?
  if ! safe_rm_rf "${tmp:?}"; then echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2; exit 2; fi
  exit "$st"
}
trap cleanup EXIT
jobs=${INTAKE_LINT_MUT_JOBS:-3}
case "$jobs" in ''|*[!0-9]*|0) echo "setup: INTAKE_LINT_MUT_JOBS must be a positive integer" >&2; exit 2 ;; esac

# Escapes in old/new: \n is a newline, \\n is a literal backslash-n (as written in Python source).
# id | target (L lint, S suite) | needle (yes: the control needles must stop it too) | old ||| new
# (old and new are split at the first "|||", so either may contain a single "|")
mutants=(
  'O1 XREF-DANGLING check off|L|yes|            if ref not in fids and ref not in all_items:|||            if False:'
  'O2 XREF-LABEL check off|L|yes|                    if not (lw & tw) or 3 * len(missing) > len(lw):|||                    if False:'
  'O3 declared foreign ids not excluded|L|yes|            if ref not in fids and ref not in all_items:|||            if ref not in all_items:'
  'O4 ephemeral note exempts the whole description|L|yes|            if "(ephemeral" in line:|||            if "(ephemeral" in desc:'
  'O5 UNREPRODUCED accepted for any column value|L|yes|                ok = (rs in UNREPRO_FAMILY) if canon == "UNREPRODUCED" else (rs == canon)|||                ok = True if canon == "UNREPRODUCED" else (rs == canon)'
  'O6 structured state line not checked|L|yes|            if line.startswith("**Reproduction:**"):|||            if False:'
  'O7 PATH-MISSING check off|L|yes|                if not exists(rel):|||                if False:'
  'O8 SAME-DEFECT head not compared|L|yes| and r["obsolete_superseding"] == head):|||):'
  'O9 SHARED-PATH check off|L|yes|            if hit and o["id"] not in dup_named:|||            if False:'
  'O10 empty selection exits 0|L|no|        print("BLIND: the selection is empty", file=sys.stderr)\n        return 3|||        print("BLIND: the selection is empty", file=sys.stderr)\n        return 0'
  'O11 unknown --skip-check code accepted|L|no|        print("intake_lint: unknown --skip-check code(s): " + ",".join(unknown), file=sys.stderr)\n        return 2|||        print("intake_lint: unknown --skip-check code(s): " + ",".join(unknown), file=sys.stderr)'
  'O12 SECRET does not scan the title|L|no|            if pat.search(r["title"] + "\\n" + desc):|||            if pat.search(desc):'
  'O13 XREF does not scan the title|L|no|        body_text = r["title"] + "\\n" + text_without_foreign_line(desc)|||        body_text = text_without_foreign_line(desc)'
  'O14 PROBABLY accepted as a verdict|L|yes|            elif verdict not in DUP_VERDICTS:|||            elif verdict not in DUP_VERDICTS | {"PROBABLY"}:'
  'O15 embeddings call foreign ids own|L|no|            ns = "foreign" if ref in fids else|||            ns = "own" if ref in fids else'
  'O16 BODY-SYNC check off|L|yes|        for p in body_problems(r):|||        for p in []:'
  'O17 SECRET prints the matched string|L|no|                findings.append(("SECRET", iid, name))|||                findings.append(("SECRET", iid, name + " " + pat.search(r["title"] + "\\n" + desc).group(0)))'
  'O18 FOREIGN-STALE check off|L|yes|        for f in sorted(fids - named):|||        for f in []:'
  'O19 unreadable database exits 0|L|no|        print("BLIND: database unreadable: %s" % e, file=sys.stderr)\n        return 3|||        print("BLIND: database unreadable: %s" % e, file=sys.stderr)\n        return 0'
  'C2 mktemp mixed suffix lower bound 4 to 5|L|yes|[A-Za-z0-9]{4,12}|||[A-Za-z0-9]{5,12}'
  'C3 github token minimum 30 to 40|L|yes|gh[pousr]_[A-Za-z0-9]{30,}|||gh[pousr]_[A-Za-z0-9]{40,}'
  'C4 private-key-block pattern broken|L|yes|PRIVATE KEY( BLOCK)?-----|||PRIVATE KEYS( BLOCK)?-----'
  'C6 prefix auto-detection takes the alphabetically first|L|no|        prefix = max(sorted(counts), key=lambda k: counts[k])|||        prefix = sorted(counts)[0]'
  'C8 PATH-MISSING ignores operator_decisions/|L|yes|docs/(?:qa|operator_decisions)/|||docs/(?:qa)/'
  'C9 UNDECIDED dropped from the verdict set|L|yes|"SAME-DEFECT", "UNDECIDED"}|||"SAME-DEFECT"}'
  'C11 jwt segment minimum 8 to 80|L|yes|eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}|||eyJ[A-Za-z0-9_-]{80,}\.eyJ[A-Za-z0-9_-]{80,}'
  'C14 stopword list emptied|L|yes|    "they them will would should could".split()\n)|||    "they them will would should could".split()\n) & set()'
  'N1 XREF-UNLABELLED check off|L|yes|                if not (cw & tw):|||                if False:'
  'N2 XREF-LABEL accepts one shared title word|L|yes|                    if not (lw & tw) or 3 * len(missing) > len(lw):|||                    if not (lw & tw):'
  'N3 range interiors not expanded|L|yes|        if 0 < b - a <= MAX_RANGE:|||        if False:'
  'N4 empty body_md accepted|L|yes|        return ["body_md is empty"]|||        return []'
  'N5 text after the description in body_md ignored|L|yes|    if suf.strip():|||    if False:'
  'N6 body_md heading not compared|L|no|    if m.group(1) != r["id"] or m.group(2) != r["title"]:|||    if False:'
  'N7 body_md Status line not compared|L|no|    if st is None or not st[len("**Status:** "):].startswith(r["status"]):|||    if False:'
  'N8 body_md header keys not checked|L|no|        if key not in BODY_KEYS:|||        if False:'
  'N9 body_md Reproduction line not compared|L|no|    elif rl is None or not (rl.startswith|||    elif False and not (rl.startswith'
  'N10 mktemp-default pattern blind|L|yes|tmp\.(?!X{10})[A-Za-z0-9]{10}|||tmp\.(?!X{10})[A-Za-z0-9]{11}'
  'N11 lowercase mktemp directory branch removed|L|yes||[a-z]{4,12}(?=/))")),|||)")),'
  'N12 DUP-HEAD accepts an Obsolete target|L|no|                if t["status"].startswith("Obsolete") or t["location"] != "Issues":|||                if False:'
  'N13 DUP-HEAD ignores open UNDECIDED candidates|L|yes|                    if others:|||                    if False:'
  'N14 any named id counts as the head (round-2 behaviour)|L|yes|r["obsolete_superseding"] == head)|||r["obsolete_superseding"] in dup_named)'
  'N15 UNDECIDED without a candidate accepted|L|yes|            if not cands:|||            if False:'
  'N16 closed UNDECIDED item accepted|L|no|            if r["status"].startswith("Obsolete") or r["location"] != "Issues":\n                findings.append(("DUP-UNDECIDED"|||            if False:\n                findings.append(("DUP-UNDECIDED"'
  'N17 DUP-STATUS check off|L|yes|        if closed_dup and verdict != "SAME-DEFECT":|||        if False:'
  'N18 OBSOLETE-STALE check off|L|yes|            if not ok:\n                findings.append(("OBSOLETE-STALE"|||            if False:\n                findings.append(("OBSOLETE-STALE"'
  'N19 stale note may name a closed item|L|no|                    if o and o["location"] == "Issues" and not o["status"].startswith("Obsolete"):\n                        ok = True|||                    if o:\n                        ok = True'
  'N20 prefix with no ids not BLIND|L|no|    if not any(id_re(prefix).fullmatch(i) for i in items):|||    if False:'
  'N21 unknown --skip-check accepted with --embeddings|L|no|    if unknown:|||    if unknown and not a.embeddings:'
  'N22 every line exempt from XREF-UNLABELLED|L|yes|    return bool(DUP_LINE.match(line) or STALE_NOTE.match(line))|||    return True'
  'N24 header line separator not reported|L|yes|        if LINE_SEPARATORS.search(line):|||        if False:'
  'N25 NULL columns not reported by name|L|no|    if nulls:|||    if False:'
  'N26 a crash escapes as a traceback|L|no|    except Exception as e:  # noqa: BLE001|||    except ZeroDivisionError as e:  # noqa: BLE001'
  'S1 suite cleanup refusal not an error|S|no|    echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2\n    exit 2|||    echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2'
)

mkcopy() { # mkcopy <src> <dest> <old> <new>  (\n in old/new is a newline)
  python3 -I - "$1" "$2" "$3" "$4" <<'PY'
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

# one_mutant <index>: prints one verdict line; never touches files outside its own dir $tmp/m<index>
one_mutant() {
  local i=$1 m id rest target needle old new d a nb verdict
  m=${mutants[$i]}
  id=${m%%|*}; rest=${m#*|}; target=${rest%%|*}; rest=${rest#*|}; needle=${rest%%|*}; rest=${rest#*|}
  old=${rest%%|||*}; new=${rest#*|||}
  d=$tmp/m$i; mkdir -p "$d" || { echo "FAIL $id: no work dir"; return; }
  if [ "$target" = S ]; then
    if ! mkcopy "$suite" "$d/test_intake_lint.sh" "$old" "$new" 2>"$d/err"; then echo "FAIL $id: stale mutant"; return; fi
    INTAKE_LINT_ROOT=$root INTAKE_LINT=$src INTAKE_LINT_EXTRA=--no-selfcheck INTAKE_LINT_FAILFAST=1 \
      bash "$d/test_intake_lint.sh" >"$d/log" 2>&1
    a=$?
    nb=n/a
  else
    if ! mkcopy "$src" "$d/m.py" "$old" "$new" 2>"$d/err"; then echo "FAIL $id: stale mutant"; return; fi
    INTAKE_LINT=$d/m.py INTAKE_LINT_EXTRA=--no-selfcheck INTAKE_LINT_FAILFAST=1 bash "$suite" >"$d/log" 2>&1
    a=$?
    python3 -I "$d/m.py" --db "$d/none.db" --ids X-1 >"$d/needle" 2>&1
    nb=no; grep -q 'BLIND: control needle failed' "$d/needle" && nb=yes
  fi
  verdict=PASS
  [ "$a" = 0 ] && verdict=FAIL
  [ "$needle" = yes ] && [ "$nb" != yes ] && verdict=FAIL
  echo "$verdict $id: cases-kill=$([ "$a" != 0 ] && echo yes || echo no) first-failure=$(grep -m1 '^FAIL' "$d/log" | cut -c6-70) needle-kill=$nb (declared $needle)"
}

fail=0
mkcopy "$src" "$tmp/ctl.py" "" "" || exit 2
INTAKE_LINT=$tmp/ctl.py INTAKE_LINT_EXTRA=--no-selfcheck bash "$suite" >"$tmp/ctl.log" 2>&1; a=$?
python3 -I "$tmp/ctl.py" --db "$tmp/none.db" --ids X-1 >"$tmp/ctl.needle" 2>&1
if [ "$a" = 0 ] && grep -q 'BLIND: database not found' "$tmp/ctl.needle"; then echo "PASS control: unmutated copy passes the suite and its control needles"
else echo "FAIL control: suite rc=$a; $(tr '\n' '|' <"$tmp/ctl.needle")"; fail=1; fi

sel=()
for i in "${!mutants[@]}"; do
  id=${mutants[$i]%% *}
  if [ -n "${INTAKE_LINT_MUT_ONLY:-}" ]; then case ",$INTAKE_LINT_MUT_ONLY," in *",$id,"*) ;; *) continue ;; esac; fi
  sel+=("$i")
done
export -f one_mutant mkcopy
export tmp root src suite
# bash cannot export arrays: hand each worker the mutant list through a file
printf '%s\n' "${mutants[@]}" >"$tmp/mutants.txt"
printf '%s\n' "${sel[@]}" | xargs -P "$jobs" -I{} bash -c 'mapfile -t mutants <"$tmp/mutants.txt"; one_mutant "$1" >"$tmp/v$1"' _ {}
for i in "${sel[@]}"; do
  if [ -f "$tmp/v$i" ]; then cat "$tmp/v$i"; grep -q '^PASS' "$tmp/v$i" || fail=1
  else echo "FAIL ${mutants[$i]%%|*}: no verdict"; fail=1; fi
done
echo "RESULT: mutants=${#sel[@]} $([ "$fail" = 0 ] && echo 'all killed as declared' || echo 'FAILED')"
[ "$fail" = 0 ]
