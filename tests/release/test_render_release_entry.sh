#!/usr/bin/env bash
# tests/release/test_render_release_entry.sh — hermetic test of scripts/release/render_release_entry.py.
# Oracle: hand-written expected lines below, never output of the script under test.
# Exit 0 when every case passes; last line "RESULT: pass=N fail=M".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
S="${RRE_SCRIPT:-$ROOT/scripts/release/render_release_entry.py}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/rre_test.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT INT TERM
printf '<!--\ninstructions {{not_a_key}}\n-->\n## v1 -- {{MANUAL:date}}\nbase {{base}}\nreopened: {{reopened_ids}}\n{{states_block}}\n{{unmerged_refs_block}}\n{{MANUAL:block}}\n' >"$W/t.md"
printf 'base=abc\nreopened_ids=\nopen_states[A/b]=2\nopen_states_ids[A/b]=X-1 X-2\nopen_states[UNSET/UNSET]=9\nunmerged_refs_count[origin]=1\nunmerged_refs[origin]=feat/x:3\n' >"$W/f.txt"
printf '@@date\n2026-11-11\n@@block\nline one\nline two\n' >"$W/m.txt"
run(){ OUT="$(python3 -I "$S" "$@" 2>"$W/err")"; RC=$?; }
has(){ if printf '%s\n' "$OUT" | grep -qxF -- "$2"; then ok "$1"; else bad "$1 (missing: $2)"; fi; }
run "$W/t.md" "$W/f.txt" "$W/m.txt"
[ "$RC" = 0 ] && ok "exit 0" || bad "exit 0 (got $RC: $(cat "$W/err"))"
has "manual value" "## v1 -- 2026-11-11"
has "fact value" "base abc"
has "empty fact rendered as none" "reopened: (none recorded in the tracker)"
has "states block, ids listed" "- A/b: 2 (X-1 X-2)"
printf '%s\n' "$OUT" | grep -q 'UNSET/UNSET' && bad "UNSET/UNSET not in states block" || ok "UNSET/UNSET not in states block"
has "refs block" "- origin: 1 ref(s): feat/x:3"
has "multi-line manual" "line two"
printf '%s\n' "$OUT" | grep -q 'instructions\|not_a_key\|<!--' && bad "leading comment dropped" || ok "leading comment dropped"
printf '%s\n' "$OUT" | grep -q '{{' && bad "no placeholder left" || ok "no placeholder left"
# refusals: exit 3, nothing on stdout
printf '@@date\n2026-11-11\n' >"$W/m2.txt"; run "$W/t.md" "$W/f.txt" "$W/m2.txt"
[ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'MANUAL:block' "$W/err" && ok "missing manual refused" || bad "missing manual refused ($RC)"
printf '@@date\nTODO\n@@block\nx\n' >"$W/m3.txt"; run "$W/t.md" "$W/f.txt" "$W/m3.txt"
[ "$RC" = 3 ] && [ -z "$OUT" ] && ok "TODO value refused" || bad "TODO value refused ($RC)"
printf '@@date\nd\n@@block\nx\n@@typo\ny\n' >"$W/m4.txt"; run "$W/t.md" "$W/f.txt" "$W/m4.txt"
[ "$RC" = 3 ] && grep -q typo "$W/err" && ok "unused manual block refused" || bad "unused manual block refused ($RC)"
grep -v '^base=' "$W/f.txt" >"$W/f2.txt"; run "$W/t.md" "$W/f2.txt" "$W/m.txt"
[ "$RC" = 3 ] && grep -q '\bbase\b' "$W/err" && ok "missing fact refused" || bad "missing fact refused ($RC)"
run "$W/t.md" "$W/f.txt"; [ "$RC" = 2 ] && ok "usage exit 2" || bad "usage exit 2 ($RC)"
# the real template renders from real facts when every manual key is given (smoke over the shipped files)
T="$ROOT/docs/release/helixconstitution-v73.4_entry.template.md"
if [ -n "${RRE_FACTS:-}" ] && [ -f "$RRE_FACTS" ]; then
  : >"$W/mall.txt"
  for k in $(sed '1,/-->/d' "$T" | grep -o '{{MANUAL:[^}]*}}' | sed 's/{{MANUAL:\(.*\)}}/\1/' | sort -u); do printf '@@%s\nvalue-%s\n' "$k" "$k" >>"$W/mall.txt"; done
  run "$T" "$RRE_FACTS" "$W/mall.txt"
  [ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q '{{' && ok "shipped template renders from real facts" || bad "shipped template renders ($RC: $(cat "$W/err"))"
fi
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
