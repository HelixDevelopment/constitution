#!/usr/bin/env bash
# test_rotate_e2e.sh — END-TO-END: a throwaway copy of the repository layout
# (scripts/prompts + scripts/gates + docs/prompts/setup) in a mktemp sandbox;
# the REAL scripts are copied in and run with their default directory resolution
# (no --dir). Three rotations in a row must give 03_, 04_, 05_, latest.md must be
# present after every step, and the real gate must PASS on the result.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -r "$ROTATE" ] || { no "rotate script present"; summary e2e; exit 1; }
[ -r "$GATE" ] || { no "gate present"; summary e2e; exit 1; }

R="$(mk_sandbox)"
mkdir -p "$R/scripts/prompts" "$R/scripts/gates" "$R/scripts/lib"
cp "$ROTATE" "$R/scripts/prompts/"; cp "$GATE" "$R/scripts/gates/"
cp "$REPO/scripts/lib/setup_prompt_extract.sh" "$R/scripts/lib/"
D="$(mk_setup_dir "$R")"
cite_doc() { # a prompt that cites a script existing in the fake repo
  printf '# Prompt %s\n\n## PROMPT\n\n```\nMarker %s. Run: bash submodules/constitution/scripts/prompts/rotate_setup_prompt.sh --help\n```\n' "$1" "$1"
}
cite_doc current >"$D/latest.md"
i=3
for name in alpha beta gamma; do
  cite_doc "$name" >"$R/src_$name.md"
  prev="$(cat "$D/latest.md")"
  out="$(cd "$R" && bash scripts/prompts/rotate_setup_prompt.sh "$name" --source "$R/src_$name.md" 2>&1)"; rc=$?
  nn="$(printf '%02d' "$i")"
  [ "$rc" -eq 0 ] && ok "rotation $name rc=0" || no "rotation $name rc=$rc: $out"
  [ -f "$D/${nn}_$name.md" ] && ok "${nn}_$name.md created" || no "${nn}_$name.md missing"
  [ "$(cat "$D/${nn}_$name.md" 2>/dev/null)" = "$prev" ] && ok "${nn}_$name.md = previous latest" || no "${nn}_$name.md content wrong"
  [ -f "$D/latest.md" ] && ok "latest.md present after $name" || no "latest.md missing after $name"
  cmp -s "$D/latest.md" "$R/src_$name.md" && ok "latest.md = src_$name" || no "latest.md != src_$name"
  i=$((i + 1))
done
listing="$(cd "$D" && ls | LC_ALL=C sort | tr '\n' ' ')"
[ "$listing" = "01_old.md 02_middle.md 03_alpha.md 04_beta.md 05_gamma.md latest.md " ] && ok "final listing exact" || no "final listing: $listing"
out="$(bash "$R/scripts/gates/cm_setup_prompt_latest_present.sh" --root "$R" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "gate PASS on rotated tree" || no "gate rc=$rc on rotated tree: $out"

# the shared extractor library is required: without it rotation refuses (fail closed)
# and the gate reports BLIND, never PASS
R3="$(mk_sandbox)"; mkdir -p "$R3/scripts/prompts" "$R3/scripts/gates"; cp "$ROTATE" "$R3/scripts/prompts/"; cp "$GATE" "$R3/scripts/gates/"
D3="$(mk_setup_dir "$R3")"; cite_doc x >"$R3/src.md"
expect_rc "library missing -> rotation refuses" 3 bash "$R3/scripts/prompts/rotate_setup_prompt.sh" x --source "$R3/src.md"
[ ! -e "$D3/03_x.md" ] && ok "library missing: nothing archived" || no "library missing: archived anyway"
expect_rc "library missing -> gate BLIND" 2 env -u SETUP_PROMPT_EXTRACT_LIB bash "$R3/scripts/gates/cm_setup_prompt_latest_present.sh" --root "$R3"

# default directory resolution refuses when the repo has no docs/prompts/setup
R2="$(mk_sandbox)"; mkdir -p "$R2/scripts/prompts"; cp "$ROTATE" "$R2/scripts/prompts/"
expect_rc "default dir missing -> refuse" 3 bash "$R2/scripts/prompts/rotate_setup_prompt.sh" x

summary e2e
