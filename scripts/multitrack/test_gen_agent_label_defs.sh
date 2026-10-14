#!/usr/bin/env bash
# =============================================================================
# test_gen_agent_label_defs.sh — hermetic test suite for the §11.4.182 /
#   §11.4.231(F) agent-type label definition generator
#   (scripts/multitrack/gen_agent_label_defs.sh), the shared naming library
#   (agent_label_lib.sh) and the independent strict frontmatter checker
#   (agent_label_frontmatter_check.py).
#
# Purpose : prove the generator emits ONE definition per selected type, named
#   exactly T<N>-<branch>-<alias>-<model>-<effort>, deterministically on every
#   locale, refuses an unknown alias, never exits 0 on output its own checker
#   rejects, refuses to clobber hand-made / hand-edited files (front matter AND
#   body), and that --check detects drift. Every emitted file is parsed by a
#   strict parser that is independent of the generator.
# Usage   : bash scripts/multitrack/test_gen_agent_label_defs.sh
# Inputs  : none (TMPDIR honoured for scratch space).
# Outputs : PASS/FAIL line per case; exit 0 only if every case passes.
# Side-effects: creates + removes a temp dir under ${TMPDIR:-/tmp}.
# Deps    : bash >= 4, sha256sum, python3 (+ optional PyYAML), shellcheck (optional).
# Cross-refs: §11.4.182, §11.4.231(F), §11.4.224(A) test-first, §11.4.201.
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GEN="$HERE/gen_agent_label_defs.sh"
CHK="$HERE/agent_label_frontmatter_check.py"
LIB="$HERE/agent_label_lib.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/gen_agent_label_test.XXXXXX")"
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s%s\n' "$1" "${2:+ — $2}"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$2' got '$3'"; fi; }
tree_hash() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1); }
run() { bash "$GEN" "$@" >"$W/out" 2>"$W/err"; echo $?; }
A=(--alias claude4)
DEF="T1-main-claude4-opus-high.md T1-main-claude4-opus-xhigh.md T1-main-claude4-sonnet-high.md T1-main-claude4-sonnet-medium.md "

echo "gen_agent_label_defs.sh test suite"

# --- usage errors ---------------------------------------------------------------
check "G01 missing --track -> 2" 2 "$(run --branch main "${A[@]}" --out-dir "$W/a")"
check "G02 non-numeric track -> 2" 2 "$(run --track x --branch main "${A[@]}" --out-dir "$W/a")"
check "G02b missing --out-dir -> 2" 2 "$(run --track 1 --branch main "${A[@]}")"
check "G02c missing --branch -> 2" 2 "$(run --track 1 "${A[@]}" --out-dir "$W/a")"
check "G02e missing --alias -> 2" 2 "$(run --track 1 --branch main --out-dir "$W/a")"
check "G02f honest '?' alias refused (never guessed) -> 2" 2 "$(run --track 1 --branch main --alias '?' --out-dir "$W/a")"
grep -qi 'alias' "$W/err" && ok "G02g '?' alias refusal names the alias" || bad "G02g '?' alias refusal names the alias" "$(cat "$W/err")"
check "G02h alias that sanitises to empty -> 2" 2 "$(run --track 1 --branch main --alias '!!!' --out-dir "$W/a")"
check "G18 type outside the ladder -> 2" 2 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/a" --types fable-low)"
check "G19 effort outside ladder -> 2" 2 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/a" --types opus-ultra)"
[ ! -e "$W/a" ] && ok "G02d usage errors create nothing" || bad "G02d usage errors create nothing"

# --- default set: 4 alias-bearing types -------------------------------------------
check "G03a default generation exit 0" 0 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/t1")"
check "G03b default = 4 types, exact alias-bearing names" "$DEF" "$(cd "$W/t1" && ls | LC_ALL=C sort | tr '\n' ' ')"
[ -n "$(find "$W/t1" -mindepth 1 -maxdepth 1 -name '.*')" ] && bad "G25 no hidden/temp files left behind" || ok "G25 no hidden/temp files left behind"
check "G03c --all-types -> 10 files" 10 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/all" --all-types >/dev/null; ls "$W/all" | wc -l)"
check "G17 --types opus-low -> exactly that file" "T1-main-claude4-opus-low.md" "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/sub" --types opus-low >/dev/null; ls "$W/sub")"

# --- strict independent frontmatter parse -------------------------------------------
if python3 -I "$CHK" "$W/t1"/*.md "$W/all"/*.md >"$W/chk.out" 2>&1; then ok "G14 strict parser accepts every generated file"; else bad "G14 strict parser accepts every generated file" "$(grep -m2 BAD "$W/chk.out")"; fi
f="$W/t1/T1-main-claude4-sonnet-medium.md"
grep -q '^description: "(T1/main - claude4 - sonnet - medium) ' "$f" && ok "G14b description begins with the full §11.4.182 label incl. alias" || bad "G14b description label" "$(sed -n 3p "$f")"
grep -q '^model: sonnet$' "$f" && grep -q '^effort: medium$' "$f" && ok "G14c model+effort in frontmatter" || bad "G14c model+effort in frontmatter"
grep -q 'generated-by: gen_agent_label_defs.sh v2' "$f" && ok "G14d v2 generated marker present" || bad "G14d v2 generated marker present"
grep -qi 'enforced by construction\|enforced by this' "$W/t1"/*.md && bad "G14g no false 'enforced' claim in any definition (AL-3)" || ok "G14g no false 'enforced' claim in any definition (AL-3)"
grep -qi 'refuses' "$W/t1"/*.md && bad "G14i no definition claims the guard 'refuses' overrides (default is WARN, AL2-3)" || ok "G14i no definition claims the guard 'refuses' overrides (default is WARN, AL2-3)"
grep -q 'flags such overrides (WARN; BLOCK under AGENT_TYPE_LABEL_ENFORCE=1)' "$f" && ok "G14j body states WARN-by-default, BLOCK under ENFORCE" || bad "G14j body WARN/BLOCK wording"
grep -q 'CLAUDE_CODE_EFFORT_LEVEL' "$f" && ok "G14h body states the per-invocation / env override boundary (AL-3)" || bad "G14h body states the override boundary"
# token budget (AL-10): name + description of the default 4 types
chars=0; for x in "$W/t1"/*.md; do n=$(sed -n 's/^name: //p' "$x"); d=$(sed -n 's/^description: //p' "$x"); chars=$((chars + ${#n} + ${#d})); done
[ "$chars" -le 640 ] && ok "G28 default listing cost <= 640 chars (~160 tokens), measured $chars" || bad "G28 default listing cost <= 640 chars" "measured $chars"

# --- checker golden-bad fixtures (the oracle must reject bad files) ---------------------
mkf() { # file name desc-label model effort color
  printf -- '---\nname: %s\ndescription: "%s x"\nmodel: %s\neffort: %s\ncolor: %s\n---\nbody\n' "$2" "$3" "$4" "$5" "$6" >"$1"
}
mkdir -p "$W/bad" "$W/good"
mkf "$W/good/T1-main-claude4-opus-low.md" T1-main-claude4-opus-low "(T1/main - claude4 - opus - low)" opus low blue
python3 -I "$CHK" "$W/good/T1-main-claude4-opus-low.md" >/dev/null 2>&1 && ok "G14f golden-good file accepted (oracle is not reject-all)" || bad "G14f golden-good file accepted"
mkf "$W/bad/T1-main-claude4-haiku-low.md"  T1-main-claude4-haiku-low "(T1/main - claude4 - haiku - low)" haiku low blue
mkf "$W/bad/T1-main-claude4-opus-ultra.md" T1-main-claude4-opus-ultra "(T1/main - claude4 - opus - ultra)" opus ultra blue
mkf "$W/bad/T1-main-claude4-opus-medium.md" T1-main-claude4-opus-medium "(T1/main - claude4 - opus - medium)" opus medium magenta
mkf "$W/bad/T1-x-claude4-opus-low.md"      T1-main-claude4-opus-low "(T1/main - claude4 - opus - low)" opus low blue
mkf "$W/bad/T1-main-claude3-opus-high.md"  T1-main-claude3-opus-high "(T1/main - claude4 - opus - high)" opus high blue
mkf "$W/bad/T1-main-opus-max.md"           T1-main-opus-max "(T1/main - <alias> - opus - max)" opus max blue
mkf "$W/bad/T1-main-q-sonnet-low.md"       T1-main-q-sonnet-low "(T1/main - ? - sonnet - low)" sonnet low blue
printf 'no frontmatter\n' >"$W/bad/T1-main-claude4-opus-xhigh.md"
for f in "$W"/bad/*.md; do
  if python3 -I "$CHK" "$f" >/dev/null 2>&1; then bad "G14e checker rejects $(basename "$f")"; else ok "G14e checker rejects $(basename "$f")"; fi
done
python3 -I "$CHK" "$W/good/T1-main-claude4-opus-low.md" | grep -Eq 'cross-parse: (ran|skipped)' && ok "N1 checker reports whether the PyYAML cross-parse ran" || bad "N1 checker reports cross-parse ran/skipped"

# --- colour by track ------------------------------------------------------------------
colour_of() { run --track "$1" --branch main "${A[@]}" --out-dir "$W/c$1" --types sonnet-low >/dev/null; sed -n 's/^color: //p' "$W/c$1/T$1-main-claude4-sonnet-low.md"; }
check "G15 T1 blue" blue "$(colour_of 1)"; check "G15 T2 green" green "$(colour_of 2)"; check "G15 T7 yellow (default)" yellow "$(colour_of 7)"

# --- sanitisation (AL-6) ---------------------------------------------------------------
check "G04a odd branch accepted" 0 "$(run --track 2 --branch 'feature/Mistiq_Vader:x"y' "${A[@]}" --out-dir "$W/br" --types sonnet-low)"
check "G04b sanitised name" "T2-feature-mistiq-vader-x-y-claude4-sonnet-low.md" "$(ls "$W/br")"
grep -q 'T2/feature/Mistiq_Vader:x"y' "$W/br"/*.md && bad "G24b raw branch must not be embedded unescaped" || ok "G24b raw branch must not be embedded unescaped"
check "G04c a '.' never survives into the name (RM1)" "T1-release-1-2-rc-claude4-opus-low.md" "$(run --track 1 --branch 'release/1.2_rc' "${A[@]}" --out-dir "$W/dot" --types opus-low >/dev/null; ls "$W/dot")"
check "G04d alias sanitised too" "T1-main-kimi-for-coding-opus-low.md" "$(run --track 1 --branch main --alias 'Kimi_For.Coding' --out-dir "$W/al" --types opus-low >/dev/null; ls "$W/al")"
check "G04e track 01 normalised to T1" "T1-main-claude4-opus-low.md" "$(run --track 01 --branch main "${A[@]}" --out-dir "$W/t01" --types opus-low >/dev/null; ls "$W/t01")"
for loc in C C.utf8 en_US.utf8 ru_RU; do
  LC_ALL="$loc" bash "$GEN" --track 1 --branch 'Fé/Ñ' --alias 'İstanbul' --out-dir "$W/loc_$loc" --types opus-low >/dev/null 2>&1
done
lnames="$(for loc in C C.utf8 en_US.utf8 ru_RU; do ls "$W/loc_$loc" 2>/dev/null; done | sort -u | tr '\n' ' ')"
check "G04f locale-independent (C, C.utf8, en_US.utf8, ru_RU give one name)" "T1-f-stanbul-opus-low.md " "$lnames"
python3 -I "$CHK" "$W"/loc_*/*.md >/dev/null 2>&1 && ok "G04g non-ASCII input still parses strictly on every locale" || bad "G04g non-ASCII parses strictly" "$(python3 -I "$CHK" "$W"/loc_*/*.md | grep BAD | head -2)"
rc=$(run --track 1 --branch $'x\nmodel: haiku' "${A[@]}" --out-dir "$W/nl" --types opus-low)
check "G04h newline in branch -> exit 0 with a clean name" "0 T1-x-model-haiku-claude4-opus-low.md" "$rc $(ls "$W/nl" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
python3 -I "$CHK" "$W/nl"/*.md >/dev/null 2>&1 && ok "G04i newline branch: output passes the strict checker" || bad "G04i newline branch: output passes the strict checker"
long="$(printf 'b%.0s' $(seq 1 240))"
check "G04j over-long name -> exit 2 (never truncated)" 2 "$(run --track 1 --branch "$long" "${A[@]}" --out-dir "$W/long" --types opus-low)"
grep -qi 'too long' "$W/err" && ok "G04k over-long name names the real cause (N-1)" || bad "G04k over-long name message" "$(cat "$W/err")"
# the generator never exits 0 on output its own checker rejects (hostile inputs)
nbad=0; i=0
for b in '../../etc' '-leading' 'a:b' 'a"b' 'a\b' "a'b" 'a#b' '$(touch PWNED)' 'feature/x y' 'İ/İ/x' $'t\tab' $'cr\rx'; do
  i=$((i+1)); d="$W/h_$i"; bash "$GEN" --track 3 --branch "$b" "${A[@]}" --out-dir "$d" --types opus-low >/dev/null 2>&1; r=$?
  if [ "$r" -eq 0 ]; then python3 -I "$CHK" "$d"/*.md >/dev/null 2>&1 || nbad=$((nbad+1)); fi
done
check "G04l no hostile branch yields exit 0 with checker-rejected output" 0 "$nbad"
# the library itself is locale-free (the hook sources it WITHOUT exporting LC_ALL=C)
lres="$(for loc in C.utf8 en_US.utf8 ru_RU; do LC_ALL="$loc" bash -c '. "$0"; al_sanitise "Fé/Ñ İstanbul"; echo' "$LIB"; done | sort -u | tr '\n' ' ')"
check "G04n al_sanitise is locale-independent when sourced (hook path)" "f-stanbul " "$lres"
[ ! -e "$HERE/PWNED" ] && [ ! -e PWNED ] && ok "G04m no command substitution executed" || bad "G04m no command substitution executed"

# --- idempotent + deterministic -----------------------------------------------------------
h1=$(tree_hash "$W/t1"); rc=$(run --track 1 --branch main "${A[@]}" --out-dir "$W/t1"); h2=$(tree_hash "$W/t1")
check "G05a rerun exit 0" 0 "$rc"; check "G05b rerun byte-identical" "$h1" "$h2"
run --track 1 --branch main "${A[@]}" --out-dir "$W/t1b" >/dev/null; check "G06 same bytes in a different out-dir" "$h1" "$(tree_hash "$W/t1b")"
grep -rEq '(19|20)[0-9]{2}-[01][0-9]-[0-3][0-9]|[0-2][0-9]:[0-5][0-9]:[0-5][0-9]' "$W/t1" && bad "G16 no timestamps in output" || ok "G16 no timestamps in output"
grep -q '11.4.209' "$W/t1/T1-main-claude4-opus-xhigh.md" && ok "G20 opus-xhigh body names the reviewer pin" || bad "G20 opus-xhigh body names the reviewer pin"
grep -q '11.4.209' "$W/t1/T1-main-claude4-sonnet-high.md" && bad "G20b sonnet-high is not described as a reviewer" || ok "G20b sonnet-high is not described as a reviewer"

# --- --print-names (the installer's single source of desired names, AL-6) ------------------
check "G29 --print-names lists the default names" "$DEF" "$(bash "$GEN" --track 1 --branch main "${A[@]}" --out-dir "$W/none" --print-names | LC_ALL=C sort | tr '\n' ' ')"
[ ! -e "$W/none" ] && ok "G29b --print-names writes nothing" || bad "G29b --print-names writes nothing"

# --- --check ---------------------------------------------------------------------------------
check "G07 --check clean -> 0" 0 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/t1" --check)"
cp -r "$W/t1" "$W/d1"; rm "$W/d1/T1-main-claude4-opus-high.md"
check "G08 --check missing file -> 1" 1 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/d1" --check)"
cp -r "$W/t1" "$W/d2"; sed -i 's/^color: blue$/color: red/' "$W/d2/T1-main-claude4-opus-high.md"
check "G09 --check hand-edited generated file -> 1" 1 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/d2" --check)"
cp -r "$W/t1" "$W/d3"; sed -i 's/^You are /You really are /' "$W/d3/T1-main-claude4-opus-high.md"
check "G21 --check body tamper with marker kept -> 1" 1 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/d3" --check)"
run --track 1 --branch main "${A[@]}" --out-dir "$W/extra" --types opus-low,opus-medium >/dev/null
check "G10a --check extra generated file (narrower set) -> 1" 1 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/extra" --types opus-low --check)"
cp -r "$W/t1" "$W/hm"; printf -- '---\nname: T1-main-hand\ndescription: "h"\n---\nhand\n' >"$W/hm/T1-main-hand.md"
check "G10b hand-made same-prefix file is NOT counted extra" 0 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/hm" --check)"
rm -rf "$W/neverwritten"; run --track 1 --branch main "${A[@]}" --out-dir "$W/neverwritten" --check >/dev/null
[ ! -e "$W/neverwritten" ] && ok "G10d --check does not create the out-dir" || bad "G10d --check does not create the out-dir"

# --- refusals ---------------------------------------------------------------------------------
mkdir -p "$W/h1"; printf -- '---\nname: T1-main-claude4-sonnet-medium\ndescription: "hand made"\nmodel: sonnet\neffort: medium\ncolor: blue\n---\nHAND\n' >"$W/h1/T1-main-claude4-sonnet-medium.md"
before=$(sha256sum "$W/h1/T1-main-claude4-sonnet-medium.md")
check "G11a hand-made target -> exit 3" 3 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/h1")"
check "G11b hand-made file unchanged" "$before" "$(sha256sum "$W/h1/T1-main-claude4-sonnet-medium.md")"
check "G11c all-or-nothing: no other file written" 1 "$(ls "$W/h1" | wc -l)"
grep -q 'T1-main-claude4-sonnet-medium' "$W/err" && ok "G11d refusal names the file" || bad "G11d refusal names the file"
cp -r "$W/t1" "$W/he"; sed -i 's/^color: blue$/color: red/' "$W/he/T1-main-claude4-opus-high.md"; b2=$(sha256sum "$W/he/T1-main-claude4-opus-high.md")
check "G12a hand-edited generated (front matter) -> exit 4" 4 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/he")"
check "G12b hand-edited generated unchanged" "$b2" "$(sha256sum "$W/he/T1-main-claude4-opus-high.md")"
cp -r "$W/t1" "$W/hb"; sed -i 's/^You are /You really are /' "$W/hb/T1-main-claude4-opus-high.md"; b3=$(sha256sum "$W/hb/T1-main-claude4-opus-high.md")
check "G12c hand-edited BODY, write mode -> exit 4 (RM2)" 4 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/hb")"
check "G12d hand-edited body unchanged" "$b3" "$(sha256sum "$W/hb/T1-main-claude4-opus-high.md")"
# the marker must sit exactly on the line after the closing --- (RM10)
cp "$W/t1/T1-main-claude4-opus-high.md" "$W/mk.md"
python3 -I - "$W/mk.md" <<'PY'
import sys
p = sys.argv[1]; L = open(p).read().split("\n")
k = L.index("---", 1); m = L.pop(k + 1); L.insert(k + 2, m); open(p, "w").write("\n".join(L))
PY
check "G27e marker not on line k+1 -> handmade (RM10)" handmade "$(bash "$GEN" --classify "$W/mk.md")"
# dry run
rm -rf "$W/dr"; check "G13a dry-run exit 0" 0 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/dr" --dry-run)"
[ ! -e "$W/dr" ] && ok "G13b dry-run writes nothing" || bad "G13b dry-run writes nothing"
check "G13c dry-run lists the 4 planned files" 4 "$(grep -c 'PLAN' "$W/out")"
check "G23 nested out-dir created" 0 "$(run --track 1 --branch main "${A[@]}" --out-dir "$W/n/e/s/t" --types opus-low)"
# classify
cls() { bash "$GEN" --classify "$1" 2>/dev/null; }
check "G27a classify genuine" genuine "$(cls "$W/t1/T1-main-claude4-opus-high.md")"
check "G27b classify handmade" handmade "$(cls "$W/h1/T1-main-claude4-sonnet-medium.md")"
check "G27c classify edited" edited "$(cls "$W/he/T1-main-claude4-opus-high.md")"
check "G27d classify absent" absent "$(cls "$W/nope.md")"
# a genuine round-1 (v1 marker) file is recognised as generated so the installer can prune it
v1="$W/v1.md"; fm=$'---\nname: T1-main-opus-low\ndescription: "(T1/main - <alias> - opus - low) x"\nmodel: opus\neffort: low\ncolor: blue\n---'; body='old body'
hv=$( { printf '%s\n' "$fm"; printf '%s\n' "$body"; } | sha256sum | cut -d' ' -f1)
{ printf '%s\n' "$fm"; printf '<!-- generated-by: gen_agent_label_defs.sh v1 (x); content-sha256: %s; y -->\n' "$hv"; printf '%s\n' "$body"; } >"$v1"
check "G27f a genuine v1 (round-1) file classifies genuine" genuine "$(cls "$v1")"
# --owner-alias: the alias that OWNS a genuine v2 file, read from its description label (AL2-1)
check "G31a --owner-alias of a generated file" claude4 "$(bash "$GEN" --owner-alias "$W/t1/T1-main-claude4-opus-high.md")"
check "G31b --owner-alias of a hyphenated alias (label text, not the name)" "kimi-for-coding" "$(bash "$GEN" --track 1 --branch main --alias kimi-for-coding --out-dir "$W/kfc" --types opus-low >/dev/null; bash "$GEN" --owner-alias "$W/kfc/T1-main-kimi-for-coding-opus-low.md")"
check "G31c --owner-alias of a hand-made file is empty" "" "$(bash "$GEN" --owner-alias "$W/h1/T1-main-claude4-sonnet-medium.md")"
check "G31d --owner-alias of a v1 file is empty" "" "$(bash "$GEN" --owner-alias "$v1")"
check "G31e --owner-alias of a hand-edited file still reads its label" claude4 "$(bash "$GEN" --owner-alias "$W/he/T1-main-claude4-opus-high.md")"
# bash version requirement is explicit and checked (AL-2)
check "G30 generator refuses bash < 4 with exit 7 (simulated major 3)" 7 "$(AGENT_LABEL_BASH_MAJOR=3 run --track 1 --branch main "${A[@]}" --out-dir "$W/b3")"
grep -q 'bash >= 4' "$W/err" && [ ! -e "$W/b3" ] && ok "G30b refusal names the requirement and writes nothing" || bad "G30b bash<4 refusal message / no write"
# lint
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -s bash "$GEN" "$LIB" >"$W/sc" 2>&1; then ok "G22 shellcheck clean (generator + lib)"; else bad "G22 shellcheck clean" "$(head -3 "$W/sc")"; fi
else ok "G22 shellcheck unavailable (SKIP-with-reason)"; fi
bash -n "$GEN" 2>/dev/null && bash -n "$LIB" 2>/dev/null && ok "G22b bash -n clean" || bad "G22b bash -n clean"

# G30 options taking a value: missing / followed by a flag / empty / leading '-' -> exit 2 naming the
#   option, nothing written (AL5-5); paths with control characters refused (AL5-2)
base=(--track 1 --branch main --alias claude4 --out-dir "$W/v")
for opt in --track --branch --alias --out-dir --types --colors-file --classify --owner-alias; do
  for form in missing flag empty dash; do
    args=("${base[@]}")
    case "$form" in missing) args+=("$opt") ;; flag) args+=("$opt" --dry-run) ;; empty) args+=("$opt" '') ;; dash) args+=("$opt" -x) ;; esac
    rc="$(run "${args[@]}")"
    check "G30 $opt $form -> 2 naming the option, nothing written" "2 1 0" "$rc $(grep -c -- "$opt needs a value" "$W/err") $(ls -d "$W/v" 2>/dev/null | wc -l)"
  done
done
check "G30 control needle: the same base with real values writes 4 files" "0 4" "$(run "${base[@]}") $(ls "$W/v" | wc -l)"
for cname in tab lf cr soh del; do
  case "$cname" in tab) c=$'\t' ;; lf) c=$'\n' ;; cr) c=$'\r' ;; soh) c=$'\001' ;; del) c=$'\177' ;; esac
  check "G31 --out-dir with $cname -> 2, nothing written" "2 0" "$(run --track 1 --branch main --alias claude4 --out-dir "$W/c${c}d") $(ls -d "$W/c${c}d" 2>/dev/null | wc -l)"
done
# G99 the generator doc states this suite's real case count (this check included) (AL5-4)
dc="$(grep -o 'test_gen_agent_label_defs.sh` ([0-9]* cases' "$HERE/../../docs/scripts/gen_agent_label_defs.md" | grep -o '[0-9]*' | head -1)"
check "G99 generator doc case count equals the real total" "$((PASS + FAIL + 1))" "${dc:-none}"

echo; echo "  total: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && { echo "  RESULT: PASS"; exit 0; } || { echo "  RESULT: FAIL"; exit 1; }
