#!/usr/bin/env bash
# tests/release/test_derive_release_facts_injection_mutants.sh — paired mutations (§1.1) of the fact-output integrity
# code of scripts/release/derive_release_facts.sh (review of f4c6e8ab, N4): each mutant is a copy of scripts/release
# and scripts/lib with one change back to a broken behaviour; test_derive_release_facts_injection.sh or
# test_fact_value_guard.sh (named per mutant) must FAIL on it, and both pass on the unmutated copy (the control).
# Y1-Y11 and Y17 are the fixer's own mutants. MUT_ONLY=ID runs one mutant. Evidence class: gate-logic (PROVISIONAL).
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/drf_imut.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
mk(){ local d="$W/$1"; mkdir -p "$d/scripts"; cp -r "$ROOT/scripts/release" "$ROOT/scripts/lib" "$d/scripts/"; echo "$d/scripts/release/derive_release_facts.sh"; }
# run SUITE SCRIPT: SUITE is inj (the end-to-end injection suite) or guard (the exhaustive guard suite)
run(){ local t=test_derive_release_facts_injection.sh; [ "$1" = guard ] && t=test_fact_value_guard.sh; DRF_SCRIPT="$2" bash "$HERE/$t" >"$W/out" 2>&1; }
apply(){ python3 -I - "$1" "$2" <<'MUTPY'
import sys
mid, p = sys.argv[1], sys.argv[2]
M = {
 # kv prints every value unchecked (the defect of the review, N4)
 "Y1": ('  if fact_key_ok "$1" && fact_text_ok "$1" && fact_text_ok "$2"; then', '  if true; then'),
 # the C1 controls (NEL among them) and SOFT HYPHEN are no longer refused
 "Y2": ("""    *$'\\xc2'[$'\\x80'-$'\\x9f']*|*$'\\xc2\\xad'*) return 1 ;;""", "    ZZNEVER) return 1 ;;"),
 # zero-width characters, LINE/PARAGRAPH SEPARATOR and the embedding/override bidi controls are no longer refused
 "Y3": ("""    *$'\\xe2\\x80'[$'\\x8b'-$'\\x8f']*|*$'\\xe2\\x80'[$'\\xa8'-$'\\xae']*) return 1 ;;""", "    ZZNEVER) return 1 ;;"),
 # the Unicode TAG characters are no longer refused
 "Y4": ("""    *$'\\xf3\\xa0'[$'\\x80'$'\\x81'][$'\\x80'-$'\\xbf']*) return 1 ;;""", "    ZZNEVER) return 1 ;;"),
 # the item-id grammar check is not recorded
 "Y5": ('[ "$nbadid" = 0 ] || printf', 'true || printf'),
 # the separator-byte check is not recorded
 "Y6": ('[ "$nsep" = 0 ] || printf', 'true || printf'),
 # a duplicate key is not recorded
 "Y7": ('[ -z "$_dup" ] || printf', 'true || printf'),
 # the key shape check accepts [, ] and = in the bracket part
 "Y8": ("""_FV_KEY='^[a-z][a-z0-9_]*(\\[[^]=[]*\\])?$'""", """_FV_KEY='^[a-z][a-z0-9_]*(\\[.*\\])?$'"""),
 # the cut heading keeps its partial character (the trim is skipped)
 "Y9": ('if [ "${#_h}" -eq 120 ] && ! [[ $_h =~ $_FV_UTF8 ]]; then', 'if false; then'),
 # the retest status shown on stderr is no longer replaced when the guard refuses it
 "Y10": ('then rstat="(not shown)"; rloc="(not shown)"; echo', 'then echo'),
 # the UTF-8 pattern admits any byte (a lone C1 byte, an overlong form)
 "Y11": ("""_FV_UTF8=$'^([ -~]|""", """_FV_UTF8=$'^([ -~]|[\\x80-\\xff]|"""),
 # an item location outside the closed set Issues, Fixed is not recorded
 "Y17": ('[ "$nloc" = 0 ] || printf', 'true || printf'),
}
a, b = M[mid]
s = open(p, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit("mutant %s: text found %d times, expected 1" % (mid, s.count(a)))
open(p, "w", encoding="utf-8").write(s.replace(a, b))
MUTPY
}
S0="$(mk control)"
run inj "$S0" && ok "control: the unmutated copy passes the injection suite" || bad "control: the unmutated copy passes the injection suite: $(grep '^FAIL' "$W/out" | head -3 | tr '\n' '|')"
run guard "$S0" && ok "control: the unmutated copy passes the guard suite" || bad "control: the unmutated copy passes the guard suite: $(grep '^FAIL' "$W/out" | head -3 | tr '\n' '|')"
for spec in Y1:inj Y2:guard Y3:guard Y4:guard Y5:inj Y6:inj Y7:inj Y8:guard Y9:inj Y10:inj Y11:guard Y17:inj; do
  id="${spec%%:*}"; suite="${spec#*:}"
  [ -z "${MUT_ONLY:-}" ] || [ "$MUT_ONLY" = "$id" ] || continue
  Sm="$(mk "$id")"
  if ! apply "$id" "$Sm"; then bad "$id could not be applied"; continue; fi
  if run "$suite" "$Sm"; then bad "$id survives the $suite suite"; else ok "$id is caught by the $suite suite ($(grep -c '^FAIL' "$W/out") failing checks)"; fi
done
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
