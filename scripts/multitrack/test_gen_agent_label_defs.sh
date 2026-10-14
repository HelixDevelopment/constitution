#!/usr/bin/env bash
# =============================================================================
# test_gen_agent_label_defs.sh — hermetic test suite for the §11.4.182 /
#   §11.4.231(F) agent-type label definition generator
#   (scripts/multitrack/gen_agent_label_defs.sh) and the independent strict
#   frontmatter checker (scripts/multitrack/agent_label_frontmatter_check.py).
#
# Purpose : prove the generator emits ONE definition per (model x effort) named
#   exactly T<N>-<sanitised-branch>-<model>-<effort>, deterministically and
#   idempotently, REFUSES to clobber hand-made / hand-edited files, and that
#   --check detects drift / missing / extra generated files. Every emitted file
#   is parsed by a strict parser that is independent of the generator.
# Usage   : bash scripts/multitrack/test_gen_agent_label_defs.sh
# Inputs  : none (TMPDIR honoured for scratch space).
# Outputs : PASS/FAIL line per case; exit 0 only if every case passes.
# Side-effects: creates + removes a temp dir under ${TMPDIR:-/tmp}.
# Deps    : bash, sha256sum, python3 (+ optional PyYAML), shellcheck (optional).
# Cross-refs: §11.4.182, §11.4.231(F), §11.4.224(A) test-first, §11.4.201.
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GEN="$HERE/gen_agent_label_defs.sh"
CHK="$HERE/agent_label_frontmatter_check.py"
W="$(mktemp -d "${TMPDIR:-/tmp}/gen_agent_label_test.XXXXXX")"
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s%s\n' "$1" "${2:+ — $2}"; FAIL=$((FAIL+1)); }
check() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$2' got '$3'"; fi
}
tree_hash() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1); }
run() { bash "$GEN" "$@" >"$W/out" 2>"$W/err"; echo $?; }

echo "gen_agent_label_defs.sh test suite"

# --- G01..G02 usage errors ----------------------------------------------------
check "G01 missing --track -> exit 2" 2 "$(run --branch main --out-dir "$W/a")"
check "G02 non-numeric track -> exit 2" 2 "$(run --track x --branch main --out-dir "$W/a")"
check "G02b missing --out-dir -> exit 2" 2 "$(run --track 1 --branch main)"
check "G02c missing --branch -> exit 2" 2 "$(run --track 1 --out-dir "$W/a")"
check "G18 model outside {sonnet,opus} -> exit 2" 2 "$(run --track 1 --branch main --out-dir "$W/a" --models fable)"
check "G19 effort outside ladder -> exit 2" 2 "$(run --track 1 --branch main --out-dir "$W/a" --efforts ultra)"
[ ! -e "$W/a" ] && ok "G02d usage errors create nothing" || bad "G02d usage errors create nothing"

# --- G03 default set -----------------------------------------------------------
rc=$(run --track 1 --branch main --out-dir "$W/t1")
check "G03a default generation exit 0" 0 "$rc"
want=$(for m in opus sonnet; do for e in high low max medium xhigh; do echo "T1-main-$m-$e.md"; done; done | LC_ALL=C sort | tr '\n' ' ')
got=$(cd "$W/t1" && ls | LC_ALL=C sort | tr '\n' ' ')
check "G03b exactly 10 files, exact names (2 models x 5 efforts)" "$want" "$got"
[ -n "$(find "$W/t1" -mindepth 1 -maxdepth 1 -name '.*')" ] && bad "G25 no hidden/temp files left behind" || ok "G25 no hidden/temp files left behind"

# --- G14 strict independent frontmatter parse ----------------------------------
if python3 -I "$CHK" "$W/t1"/*.md >"$W/chk.out" 2>&1; then ok "G14 strict parser accepts all 10 generated files"; else bad "G14 strict parser accepts all 10 generated files" "$(head -3 "$W/chk.out")"; fi
head -4 "$W/t1/T1-main-sonnet-medium.md" | grep -q '^description: "(T1/main - <alias> - sonnet - medium) ' && ok "G14b description begins with the §11.4.182 label text" || bad "G14b description begins with the §11.4.182 label text" "$(sed -n 3p "$W/t1/T1-main-sonnet-medium.md")"
grep -q '^model: sonnet$' "$W/t1/T1-main-sonnet-medium.md" && grep -q '^effort: medium$' "$W/t1/T1-main-sonnet-medium.md" && ok "G14c model+effort enforced in frontmatter" || bad "G14c model+effort enforced in frontmatter"
grep -q 'generated-by: gen_agent_label_defs.sh' "$W/t1/T1-main-sonnet-medium.md" && ok "G14d generated marker present" || bad "G14d generated marker present"

# --- checker golden-bad fixtures (the oracle must reject bad files) ---------------
mkbad() { # file name model effort color
  printf -- '---\nname: %s\ndescription: "(T1/main - <alias> - %s - %s) x"\nmodel: %s\neffort: %s\ncolor: %s\n---\nbody\n' "$2" "$3" "$4" "$3" "$4" "$5" >"$1"
}
mkdir -p "$W/bad" "$W/good"
mkbad "$W/good/T1-main-opus-low.md" T1-main-opus-low opus low blue
python3 -I "$CHK" "$W/good/T1-main-opus-low.md" >/dev/null 2>&1 && ok "G14f golden-good helper-built file accepted (oracle is not reject-all)" || bad "G14f golden-good helper-built file accepted"
mkbad "$W/bad/T1-main-haiku-low.md"  T1-main-haiku-low haiku low blue
mkbad "$W/bad/T1-main-opus-ultra.md" T1-main-opus-ultra opus ultra blue
mkbad "$W/bad/T1-main-opus-low.md"   T1-main-opus-low opus low magenta
mkbad "$W/bad/T1-x-opus-low.md"      T1-main-opus-low opus low blue
mkbad "$W/bad/t1-main-opus-low.md"   t1-main-opus-low opus low blue
mkbad "$W/bad/T1-ma:in-opus-low.md"  "T1-ma:in-opus-low" opus low blue
printf 'no frontmatter\n' >"$W/bad/T1-main-opus-high.md"
printf -- '---\nname: T1-main-opus-max\nname: T1-main-opus-max\ndescription: "(T1/main - <alias> - opus - max) x"\nmodel: opus\neffort: max\ncolor: blue\n---\n' >"$W/bad/T1-main-opus-max.md"
for f in "$W"/bad/*.md; do
  if python3 -I "$CHK" "$f" >/dev/null 2>&1; then bad "G14e checker rejects $(basename "$f")"; else ok "G14e checker rejects $(basename "$f")"; fi
done

# --- G15 colour by track --------------------------------------------------------
colour_of() { rc=$(run --track "$1" --branch main --out-dir "$W/c$1" --models sonnet --efforts low); sed -n 's/^color: //p' "$W/c$1/T$1-main-sonnet-low.md"; }
check "G15 T1 blue"   blue   "$(colour_of 1)"
check "G15 T2 green"  green  "$(colour_of 2)"
check "G15 T3 orange" orange "$(colour_of 3)"
check "G15 T4 purple" purple "$(colour_of 4)"
check "G15 T5 cyan"   cyan   "$(colour_of 5)"
check "G15 T7 yellow (default)" yellow "$(colour_of 7)"

# --- G04 branch sanitisation ----------------------------------------------------
rc=$(run --track 2 --branch 'feature/Mistiq_Vader:x"y' --out-dir "$W/br" --models sonnet --efforts low)
check "G04a odd branch accepted" 0 "$rc"
check "G04b sanitised name" "T2-feature-mistiq-vader-x-y-sonnet-low.md" "$(ls "$W/br")"
python3 -I "$CHK" "$W/br"/*.md >/dev/null 2>&1 && ok "G24 sanitised odd branch still parses strictly" || bad "G24 sanitised odd branch still parses strictly"
grep -q 'T2/feature/Mistiq_Vader:x"y' "$W/br"/*.md && bad "G24b raw branch must not be embedded unescaped" || ok "G24b raw branch must not be embedded unescaped"

# --- G05/G06 idempotent + deterministic -----------------------------------------
h1=$(tree_hash "$W/t1"); rc=$(run --track 1 --branch main --out-dir "$W/t1"); h2=$(tree_hash "$W/t1")
check "G05a rerun exit 0" 0 "$rc"; check "G05b rerun byte-identical" "$h1" "$h2"
run --track 1 --branch main --out-dir "$W/t1b" >/dev/null; check "G06 same bytes in a different out-dir" "$h1" "$(tree_hash "$W/t1b")"
grep -rEq '(19|20)[0-9]{2}-[01][0-9]-[0-3][0-9]|[0-2][0-9]:[0-5][0-9]:[0-5][0-9]' "$W/t1" && bad "G16 no timestamps in output" || ok "G16 no timestamps in output"

# --- G17 subsets ----------------------------------------------------------------
run --track 1 --branch main --out-dir "$W/sub" --models opus >/dev/null
check "G17 --models opus -> 5 files" 5 "$(ls "$W/sub" | wc -l)"
# --- G20 reviewer pin documented -------------------------------------------------
grep -q '11.4.209' "$W/t1/T1-main-opus-xhigh.md" && grep -q '11.4.211' "$W/t1/T1-main-opus-xhigh.md" && ok "G20 opus-xhigh body names the reviewer/merge pin" || bad "G20 opus-xhigh body names the reviewer/merge pin"
grep -q '11.4.209' "$W/t1/T1-main-sonnet-low.md" && bad "G20b sonnet-low is not described as a reviewer" || ok "G20b sonnet-low is not described as a reviewer"

# --- G07..G10 --check --------------------------------------------------------------
check "G07 --check clean -> 0" 0 "$(run --track 1 --branch main --out-dir "$W/t1" --check)"
cp -r "$W/t1" "$W/drift1"; rm "$W/drift1/T1-main-opus-low.md"
check "G08 --check missing file -> 1" 1 "$(run --track 1 --branch main --out-dir "$W/drift1" --check)"
cp -r "$W/t1" "$W/drift2"; sed -i 's/^color: blue$/color: red/' "$W/drift2/T1-main-opus-low.md"
check "G09 --check hand-edited generated file -> 1" 1 "$(run --track 1 --branch main --out-dir "$W/drift2" --check)"
cp -r "$W/t1" "$W/drift3"; sed -i 's/^You are /You really are /' "$W/drift3/T1-main-opus-low.md"
check "G21 --check body tamper with marker kept -> 1" 1 "$(run --track 1 --branch main --out-dir "$W/drift3" --check)"
run --track 1 --branch main --out-dir "$W/extra" --models opus --efforts low,medium >/dev/null
check "G10a --check extra generated file (narrower set) -> 1" 1 "$(run --track 1 --branch main --out-dir "$W/extra" --models opus --efforts low --check)"
cp -r "$W/t1" "$W/hm"; printf -- '---\nname: T1-main-hand\ndescription: "h"\n---\nhand\n' >"$W/hm/T1-main-hand.md"
check "G10b hand-made same-prefix file is NOT counted extra" 0 "$(run --track 1 --branch main --out-dir "$W/hm" --check)"
check "G10c --check never writes" "$(tree_hash "$W/drift1")" "$(tree_hash "$W/drift1")"
rm -rf "$W/neverwritten"; run --track 1 --branch main --out-dir "$W/neverwritten" --check >/dev/null
[ ! -e "$W/neverwritten" ] && ok "G10d --check does not create the out-dir" || bad "G10d --check does not create the out-dir"

# --- G11 refuse to overwrite hand-made ------------------------------------------------
mkdir -p "$W/h1"; printf -- '---\nname: T1-main-sonnet-medium\ndescription: "hand made"\nmodel: sonnet\neffort: medium\ncolor: blue\n---\nHAND\n' >"$W/h1/T1-main-sonnet-medium.md"
before=$(sha256sum "$W/h1/T1-main-sonnet-medium.md")
rc=$(run --track 1 --branch main --out-dir "$W/h1")
check "G11a hand-made target -> exit 3" 3 "$rc"
check "G11b hand-made file unchanged" "$before" "$(sha256sum "$W/h1/T1-main-sonnet-medium.md")"
check "G11c all-or-nothing: no other file written" 1 "$(ls "$W/h1" | wc -l)"
grep -q 'T1-main-sonnet-medium' "$W/err" && ok "G11d refusal names the file" || bad "G11d refusal names the file"
# --- G12 refuse hand-edited generated ---------------------------------------------------
cp -r "$W/t1" "$W/he"; sed -i 's/^color: blue$/color: red/' "$W/he/T1-main-opus-low.md"; b2=$(sha256sum "$W/he/T1-main-opus-low.md")
check "G12a hand-edited generated -> exit 4" 4 "$(run --track 1 --branch main --out-dir "$W/he")"
check "G12b hand-edited generated unchanged" "$b2" "$(sha256sum "$W/he/T1-main-opus-low.md")"
# --- G13 dry run -----------------------------------------------------------------------------
rm -rf "$W/dr"; rc=$(run --track 1 --branch main --out-dir "$W/dr" --dry-run)
check "G13a dry-run exit 0" 0 "$rc"; [ ! -e "$W/dr" ] && ok "G13b dry-run writes nothing" || bad "G13b dry-run writes nothing"
grep -c 'T1-main-' "$W/out" | grep -q '^10$' && ok "G13c dry-run lists the 10 planned files" || bad "G13c dry-run lists the 10 planned files" "$(wc -l <"$W/out")"
# --- G23 out-dir created -----------------------------------------------------------------------
check "G23 nested out-dir created" 0 "$(run --track 1 --branch main --out-dir "$W/n/e/s/t" --models opus --efforts low)"
# --- G26 permission-less safety: output only inside out-dir --------------------------------------
[ "$(find "$W/t1" -type d | wc -l)" = 1 ] && ok "G26 no subdirectories created" || bad "G26 no subdirectories created"
# --- G27 --classify mode (used by the installer) -------------------------------------
cls() { bash "$GEN" --classify "$1" 2>/dev/null; }
check "G27a classify genuine" genuine "$(cls "$W/t1/T1-main-opus-low.md")"
check "G27b classify handmade" handmade "$(cls "$W/h1/T1-main-sonnet-medium.md")"
check "G27c classify edited" edited "$(cls "$W/he/T1-main-opus-low.md")"
check "G27d classify absent" absent "$(cls "$W/nope.md")"
# --- G22 shellcheck ----------------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -s bash "$GEN" >"$W/sc" 2>&1; then ok "G22 shellcheck clean"; else bad "G22 shellcheck clean" "$(head -3 "$W/sc")"; fi
else ok "G22 shellcheck unavailable (SKIP-with-reason)"; fi
bash -n "$GEN" 2>/dev/null && ok "G22b bash -n clean" || bad "G22b bash -n clean"

echo; echo "  total: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && { echo "  RESULT: PASS"; exit 0; } || { echo "  RESULT: FAIL"; exit 1; }
