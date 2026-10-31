#!/usr/bin/env bash
# test_setup_prompt_extract_equivalence.sh — EQUIVALENCE of the PROMPT-block
# extractor in scripts/lib/setup_prompt_extract.sh with the installer's inline
# hi_extract_prompt (scripts/install_constitution.sh; read only, never edited).
#
#   E1 the installer's function is extracted from the installer FILE (sed between
#      `hi_extract_prompt() {` and the next `}` line) into a sandbox and sourced;
#   E2 both extractors run on a fixture matrix (backtick, tilde, info string, fence
#      under a later heading, unclosed, empty, whitespace-only, CRLF, multiple
#      blocks, inner shorter fence, other-character fence, indented closer, closer
#      with text, longer closer, second PROMPT heading, no heading, heading with
#      trailing spaces); rc AND stdout must be identical on every fixture;
#   E3 control needle: the matrix MUST contain at least one rc=0 and one rc=1 case
#      (an all-same outcome would make "identical" meaningless);
#   E4 mutation: four mutated copies of the library extractor MUST each differ from
#      the installer on at least one fixture (otherwise the matrix is too weak);
#   E5 the validators use the library: rotate_setup_prompt.sh's rsp_has_prompt_block
#      gives the same verdict as spx_has_prompt_block on every fixture, and the
#      validator form refuses the whitespace-only block (the one documented,
#      deliberate difference from the installer).
# Nothing outside a mktemp -d sandbox is written. No network.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INST="$REPO/scripts/install_constitution.sh"
LIBX="$REPO/scripts/lib/setup_prompt_extract.sh"
[ -r "$INST" ] || { no "installer present at $INST"; summary extract_equivalence; exit 1; }
[ -r "$LIBX" ] || { no "library present at $LIBX"; summary extract_equivalence; exit 1; }

S="$(mk_sandbox)"
sed -n '/^hi_extract_prompt() {$/,/^}$/p' "$INST" >"$S/inst_fn.sh"
if grep -q '^hi_extract_prompt() {$' "$S/inst_fn.sh" && [ "$(tail -n1 "$S/inst_fn.sh")" = "}" ] \
   && ( . "$S/inst_fn.sh"; declare -F hi_extract_prompt >/dev/null ); then
  ok "E1 installer hi_extract_prompt extracted ($(wc -l <"$S/inst_fn.sh") lines)"
else
  no "E1 could not extract hi_extract_prompt from the installer"; summary extract_equivalence; exit 1
fi

F="$S/fx"; mkdir -p "$F"
B='```'; T='~~~'
w() { printf "$2" >"$F/$1.md"; }
w backtick          "# t\n\n## PROMPT\n\n${B}\nline one\nline two\n${B}\n\n## After\n"
w tilde             "# t\n\n## PROMPT\n\n${T}\ntilde body\n${T}\n"
w info_string       "## PROMPT\n${B}bash\necho hi\n${B}\n"
w later_heading     "## PROMPT\n\nprose only\n\n## Other\n\n${B}\nnot the prompt\n${B}\n"
w unclosed          "## PROMPT\n\n${B}\nopen only\n"
w empty             "## PROMPT\n\n${B}\n${B}\n"
w whitespace_only   "## PROMPT\n\n${B}\n   \n\t\n${B}\n"
w crlf              "## PROMPT\r\n\r\n${B}\r\ncrlf body\r\n${B}\r\n"
w multiple          "## PROMPT\n\n${B}\nfirst\n${B}\n\n${B}\nsecond\n${B}\n"
w inner_shorter     "## PROMPT\n\n\`\`\`\`\nouter\n${B}\ninner\n${B}\n\`\`\`\`\n"
w other_char        "## PROMPT\n\n${B}\nbody\n${T}\nstill body\n${B}\n"
w indented_closer   "## PROMPT\n\n${B}\nbody\n  ${B}\nmore\n${B}\n"
w closer_with_text  "## PROMPT\n\n${B}\nbody\n${B} not a closer\nmore\n${B}\n"
w longer_closer     "## PROMPT\n\n${B}\nbody\n\`\`\`\`\`\n"
w second_heading    "## PROMPT\n\nx\n## PROMPT\n\n${B}\nbody\n${B}\n"
w no_heading        "# t\n\n${B}\nbody\n${B}\n"
w heading_trailing  "## PROMPT   \n\n${B}\nbody\n${B}\n"
w heading_h3        "### PROMPT\n\n${B}\nbody\n${B}\n"
w closer_trailing_ws "## PROMPT\n\n${B}\nbody\n${B}   \n"
w short_opener      "## PROMPT\n\n\`\`\nbody\n\`\`\n"
nfx="$(find "$F" -name '*.md' | wc -l)"

run_one() { # <fn-file> <fn-name> <fixture> -> "rc sha"
  ( . "$1"; out="$("$2" "$3" 2>/dev/null; printf 'rc=%s' "$?")"; printf '%s' "$out" | sha256sum | cut -c1-16 | tr -d '\n'; printf ' %s\n' "${out##*rc=}" )
}
compare() { # <lib-file> -> number of fixtures whose outcome differs from the installer
  local d=0 f a b
  for f in "$F"/*.md; do
    a="$(run_one "$S/inst_fn.sh" hi_extract_prompt "$f")"
    b="$(run_one "$1" spx_extract_prompt "$f")"
    [ "$a" = "$b" ] || d=$((d + 1))
  done
  printf '%s\n' "$d"
}

# E2: identical on every fixture, reported per fixture
diffs=0; n0=0; n1=0
for f in "$F"/*.md; do
  a="$(run_one "$S/inst_fn.sh" hi_extract_prompt "$f")"
  b="$(run_one "$LIBX" spx_extract_prompt "$f")"
  case "${a##* }" in 0) n0=$((n0 + 1)) ;; *) n1=$((n1 + 1)) ;; esac
  if [ "$a" = "$b" ]; then ok "E2 identical on $(basename "$f" .md) (rc=${a##* })"
  else no "E2 DIFFERS on $(basename "$f" .md): installer=[$a] lib=[$b]"; diffs=$((diffs + 1)); fi
done
# E3 control needle
[ "$n0" -ge 3 ] && [ "$n1" -ge 3 ] && ok "E3 matrix has both outcomes (rc0=$n0 rc1=$n1 of $nfx)" \
  || no "E3 matrix degenerate (rc0=$n0 rc1=$n1)"
# spot facts (so a both-wrong pair cannot hide): later heading and unclosed are rc 1; tilde is rc 0
[ "$(run_one "$LIBX" spx_extract_prompt "$F/later_heading.md" | cut -d' ' -f2)" = 1 ] && ok "E3 fence under a later heading is NOT the prompt" || no "E3 later heading accepted"
[ "$(run_one "$LIBX" spx_extract_prompt "$F/tilde.md" | cut -d' ' -f2)" = 0 ] && ok "E3 tilde fence accepted" || no "E3 tilde refused"
[ "$(run_one "$LIBX" spx_extract_prompt "$F/whitespace_only.md" | cut -d' ' -f2)" = 0 ] && ok "E3 extractor (like the installer) accepts a whitespace-only block" || no "E3 whitespace-only differs from installer semantics"

# E4 mutants of the library must be caught by the matrix
mut() { # <name> <sed-expr>
  local m="$S/mut_$1.sh"
  sed -e "$2" "$LIBX" >"$m"
  if cmp -s "$m" "$LIBX"; then no "E4 mutant $1: sed did not change the library (stale)"; return; fi
  local d; d="$(compare "$m")"
  [ "$d" -gt 0 ] && ok "E4 mutant $1 killed ($d fixtures differ)" || no "E4 mutant $1 SURVIVED"
}
mut no-tilde            's/|~~~+)/)/'
mut no-later-heading    '/st == 1 \&\& \/\^## \/ { exit }/d'
mut strict-length       's/length(line) >= flen/length(line) > flen/'
mut empty-accepted      's/got \&\& n > 0/got/'
mut no-trailing-trim    's/sub(\/\[\[:space:\]\]+\$\/, "", line)/line = line/'

# E5 validators share the library
# shellcheck disable=SC1090
( ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 . "$ROTATE"; . "$LIBX"
  bad=0
  for f in "$F"/*.md; do
    rsp_has_prompt_block "$f"; a=$?; spx_has_prompt_block "$f"; b=$?
    [ "$a" = "$b" ] || { echo "rotate=$a lib=$b on $(basename "$f")"; bad=1; }
  done
  exit "$bad" ) >"$S/e5.out" 2>&1 && ok "E5 rotate validator == library validator on all $nfx fixtures" \
  || no "E5 rotate validator differs: $(cat "$S/e5.out")"
( . "$LIBX"; ! spx_has_prompt_block "$F/whitespace_only.md" && spx_has_prompt_block "$F/tilde.md" ) \
  && ok "E5 validator refuses whitespace-only, accepts tilde" || no "E5 validator whitespace/tilde wrong"
grep -q 'setup_prompt_extract.sh' "$REPO/scripts/gates/cm_setup_prompt_latest_present.sh" \
  && ok "E5 gate sources the shared library" || no "E5 gate does not use the shared library"

summary extract_equivalence
