#!/usr/bin/env bash
# tests/release/test_derive_release_facts_provisional_mutants.sh — paired mutations (§1.1) of the rel1 and
# rel2 derivations of scripts/release/derive_release_facts.sh: each mutant is a copy of scripts/release and
# scripts/lib with one change back to a broken behaviour; test_derive_release_facts_provisional.sh must FAIL on it
# (and pass on the unmutated copy, the control). M1-M5 are the author's first set, M6-M16 cover the review of
# e5efbf77 (F2 fences, F3 word boundary, F4 first due:, F8 closure binding, F9 lookup failure, CR handling), R1-R8
# are the reviewer's mutants of that review re-expressed on this code (R2 = M1, R4 = M3; R5, removing the awk exit,
# is equivalent here: every line after the first starts with "V", so the shell's date test and ${due:0:10} read
# the first line only; it is listed as equivalent, not run). X2-X13 are the reviewer's mutants of the review of
# f4c6e8ab (N1), adopted verbatim; Y12-Y16 are the fixer's own mutants of the N5 date code. MUT_ONLY=ID runs one mutant.
# Evidence class: gate-logic (PROVISIONAL).
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/drf_mut.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
mk(){ local d="$W/$1"; mkdir -p "$d/scripts"; cp -r "$ROOT/scripts/release" "$ROOT/scripts/lib" "$d/scripts/"; echo "$d/scripts/release/derive_release_facts.sh"; }
run(){ DRF_SCRIPT="$1" bash "$HERE/test_derive_release_facts_provisional.sh" >"$W/out" 2>&1; }
# apply ID FILE: replace the one occurrence of the mutant's text (python, so no shell quoting touches the texts)
apply(){ python3 -I - "$1" "$2" <<'MUTPY'
import sys
mid, p = sys.argv[1], sys.argv[2]
M = {
 "M1": ('if (index(line, m) != 1) next', 'if (index(line, m) == 0) next'),
 "M2": ('if (fc != "") next', 'if (0) next'),
 "M3": ('if [ "$rloc" = Fixed ] && [ -n "$rclos" ] && [ "$rclos" \\> "$PREV_DATE" ]; then', 'if [ -n "$rloc" ]; then'),
 "M4": ('if [ "$REQ_RETEST" -eq 1 ]; then', 'if false; then'),
 "M5": ('  elif [ -z "$rrow" ]; then', '  elif [ -z "$rrow" ] && false; then'),
 "M6": ('(c == "`" || c == "~")', '(c == "`")'),
 "M7": ('while (ind < 4 && substr(line, ind + 1, 1) == " ") ind++', 'while (ind < 0 && substr(line, ind + 1, 1) == " ") ind++'),
 "M8": ('fc == c && n >= fl && tail', 'fc == c && tail'),
 "M9": ('n >= fl && tail ~ /^[ \\t]*$/) { fc = ""', 'n >= fl) { fc = ""'),
 "M10": ('if (after ~ /[A-Za-z0-9_]/) next', 'if (0) next'),
 "M11": ('due = substr(r, 1, RLENGTH); break }', 'due = substr(r, 1, RLENGTH) }'),
 "M12": ('if (pre !~ /[A-Za-z0-9_]/) {', 'if (1) {'),
 "M13": (' && [ "$rclos" \\> "$PREV_DATE" ]; then', '; then'),
 "M14": (' && !(c == "`" && index(tail, "`") > 0)', ''),
 "M15": ('  if [ "$rok" -eq 0 ]; then', '  if false; then'),
 "M16": ('sub(/\\r$/, "", line)', 'line = line'),
 "R1": ('  [ -n "$vline" ] || continue\n', ''),
 "R3": ('if (n >= 3 && fc == ""', 'if (n >= 99 && fc == ""'),
 "R6": ('"$RETEST" "$rstat" "$rloc" >&3\n        echo retest >>"$QFAIL"', '"$RETEST" "$rstat" "$rloc" >&3'),
 "R7": ('"$RETEST" "$B" >&3\n    echo retest >>"$QFAIL"', '"$RETEST" "$B" >&3'),
 # round 3 (review of f4c6e8ab, N1): the reviewer's mutants, verbatim (their texts and replacements as the reviewer
 # wrote them in review_relfix2_20261117T135012/tools/rmut.sh)
 "X2": ('!(c == "`" && index(tail, "`") > 0)', '!(index(tail, "`") > 0)'),
 "X3": ('if (ind < 4 && (c == "`" || c == "~")) {', 'if ((c == "`" || c == "~")) {'),
 "X4": ('tail ~ /^[ \\t]*$/) { fc = ""', 'tail ~ /^$/) { fc = ""'),
 "X5": ('[ "${due:0:10}" \\< "$TODAY" ] && OVER=', '! [ "${due:0:10}" \\> "$TODAY" ] && OVER='),
 "X6": ('[ -n "$rclos" ] && [ "$rclos" \\> "$PREV_DATE" ]', '[ -n "$rclos" ] && ! [ "$rclos" \\< "$PREV_DATE" ]'),
 "X11": ('if [ "$rloc" = Fixed ] && [ -n "$rclos" ]', 'if [ -n "$rclos" ]'),
 "X13": ('kv retest_item_closure "${rclos:-none}"', 'kv retest_item_closure "${rclos:-}"'),
 # round 3, the fixer's own mutants of the N5 code: V counts a closure on the tag's own day (Y12); the calendar
 # check of due: removed (Y13); the closure reduced to its day no longer (Y14); V reads the raw text, so 9999-99-99
 # and a same-day timestamp count (Y15); a date with a digit after the day is accepted (Y16)
 "Y12": ('closure_day "$vclos" && [ "$CDAY" \\> "$PREV_DATE" ]', 'closure_day "$vclos" && ! [ "$CDAY" \\< "$PREV_DATE" ]'),
 "Y13": ('  cal_date "$due" || due="not-a-date"', '  :'),
 "Y14": ('closure_day "$rclos"; rclos="$CDAY"', 'closure_day "$rclos"'),
 "Y15": ('closure_day "$vclos" && [ "$CDAY" \\> "$PREV_DATE" ]', '[ -n "$vclos" ] && [ "$vclos" \\> "$PREV_DATE" ]'),
 "Y16": ('  [[ ${1:10:1} == [0-9] ]] && return 1\n', ''),
 "R8": ('  due="${vline#V}"', "  due=\"$(printf '%s\\n' \"$body\" | grep -m1 -F '**Verification:** provisional' | sed -n 's/.*due:[[:space:]]*\\([^[:space:]]*\\).*/\\1/p')\""),
}
a, b = M[mid]
s = open(p, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit("mutant %s: text found %d times, expected 1" % (mid, s.count(a)))
open(p, "w", encoding="utf-8").write(s.replace(a, b))
MUTPY
}
S0="$(mk control)"; run "$S0" && ok "control: the unmutated copy passes" || bad "control: the unmutated copy passes"
for id in M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11 M12 M13 M14 M15 M16 R1 R3 R6 R7 R8 X2 X3 X4 X5 X6 X11 X13 Y12 Y13 Y14 Y15 Y16; do
  [ -z "${MUT_ONLY:-}" ] || [ "$MUT_ONLY" = "$id" ] || continue
  Sm="$(mk "$id")"
  if ! apply "$id" "$Sm"; then bad "$id could not be applied"; continue; fi
  if run "$Sm"; then bad "$id survives"; else ok "$id is caught ($(grep -c '^FAIL' "$W/out") failing checks)"; fi
done
echo "EQUIVALENT R5 (awk exit removed): not run, see the header"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
