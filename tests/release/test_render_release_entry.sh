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
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM   # round 7 (L5): a signal ends the suite (the EXIT trap cleans up); a handler that returns would let the suite run on
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
# CON-417: the retest sentence is conditional on a recorded verdict (operator decision 2026-11-12, relayed):
# a retest_statement value must START with PASS-FULL, PARTIAL-TOPOLOGY, FAIL or NOT RUN, so no entry implies a pass
printf '## r\nretest: {{MANUAL:retest_statement}}\n' >"$W/rt.md"; printf 'x=1\n' >"$W/rf.txt"
for v in 'PASS-FULL on base abc, tier default+heavy, log L' 'PARTIAL-TOPOLOGY on base abc, log L' 'FAIL on base abc, log L' 'NOT RUN on this candidate'; do
  printf '@@retest_statement\n%s\n' "$v" >"$W/rm.txt"; run "$W/rt.md" "$W/rf.txt" "$W/rm.txt"
  [ "$RC" = 0 ] && has "retest verdict accepted: ${v%% *}" "retest: $v" || bad "retest verdict accepted: ${v%% *} ($RC: $(cat "$W/err"))"
done
for v in 'passed' 'all green' 'PASS-FULLY done' 'pass-full' 'has never run' 'FAILED' 'the retest: PASS-FULL'; do
  printf '@@retest_statement\n%s\n' "$v" >"$W/rm.txt"; run "$W/rt.md" "$W/rf.txt" "$W/rm.txt"
  [ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'retest_statement (must start with' "$W/err" && ok "retest value without a leading verdict token refused: $v" || bad "retest value without a leading verdict token refused: $v ($RC)"
done
# fail closed: a template naming the key with a manual file that lacks it is refused, and names the key
printf '@@other\nx\n' >"$W/rm2.txt"; printf '## r\nretest: {{MANUAL:retest_statement}}\n{{MANUAL:other}}\n' >"$W/rt2.md"; run "$W/rt2.md" "$W/rf.txt" "$W/rm2.txt"
[ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'MANUAL:retest_statement' "$W/err" && ok "retest_statement missing from the manual file: refused" || bad "retest_statement missing from the manual file: refused ($RC)"
# a template without the key renders without it (the verdict check binds only where the key is used)
printf '## r\nother: {{MANUAL:other}}\n' >"$W/rt3.md"; run "$W/rt3.md" "$W/rf.txt" "$W/rm2.txt"
[ "$RC" = 0 ] && has "a template without retest_statement renders" "other: x" || bad "a template without retest_statement renders ($RC: $(cat "$W/err"))"
run "$W/t.md" "$W/f.txt"; [ "$RC" = 2 ] && ok "usage exit 2" || bad "usage exit 2 ($RC)"
# CON-231 (review m-5): a status or severity value new at cut time must not drop silently; a FACTS
# count key open_status[...] / open_severity[...] the template does not render is refused
printf '## v -- {{MANUAL:date}}\nQueued {{open_status[Queued]}}, high {{open_severity[high]}}\n{{MANUAL:block}}\n' >"$W/t5.md"
printf 'open_status[Queued]=3\nopen_severity[high]=1\nopen_severity_ids[high]=X-1\n' >"$W/f5.txt"
run "$W/t5.md" "$W/f5.txt" "$W/m.txt"
[ "$RC" = 0 ] && ok "CON-231 every status/severity key rendered: exit 0" || bad "CON-231 every status/severity key rendered: exit 0 ($RC: $(cat "$W/err"))"
printf 'open_status[In testing]=2\nopen_severity[critical]=1\n' >>"$W/f5.txt"; run "$W/t5.md" "$W/f5.txt" "$W/m.txt"
[ "$RC" = 3 ] && [ -z "$OUT" ] && grep -qF 'open_status[In testing]' "$W/err" && grep -qF 'open_severity[critical]' "$W/err" \
  && ok "CON-231 a status/severity value the template does not render is refused" || bad "CON-231 a status/severity value the template does not render is refused ($RC: $(cat "$W/err"))"
# the shipped template renders when every key is given (smoke over the shipped file). CON-232 (review
# m-6): the synthetic case always runs (one value per key named by the template itself); the real-facts
# case runs when RRE_FACTS names a facts file and otherwise prints an explicit SKIP line (§11.4.3).
# CON-423 (rehearsal of the v73.4 cut, REHEARSAL_REPORT.md D5): a MANUAL value that still says DRAFT is refused unless
# the caller asks for a draft rendering with --draft (first argument); a draft rendering starts with a fixed marker line
# so it can never pass for a release entry. DRAFT is matched as a whole word, case-sensitive (as TODO and TBD are).
printf '@@date\n2026-11-11\n@@block\nDRAFT: the provisional list\n' >"$W/md.txt"; run "$W/t.md" "$W/f.txt" "$W/md.txt"
[ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'MANUAL:block (still says DRAFT; use --draft for a draft rendering)' "$W/err" && ok "D5 a DRAFT manual value is refused without --draft" || bad "D5 a DRAFT manual value is refused without --draft ($RC: $(cat "$W/err"))"
printf '@@date\n2026-11-11\n@@block\nx\n@@retest_statement\nNOT RUN — DRAFT: rehearsal\n' >"$W/md2.txt"; printf '## v\n{{MANUAL:date}}\n{{MANUAL:block}}\nretest: {{MANUAL:retest_statement}}\n' >"$W/td2.md"
run "$W/td2.md" "$W/f.txt" "$W/md2.txt"
[ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'MANUAL:retest_statement (still says DRAFT' "$W/err" && ok "D5 a DRAFT retest_statement is refused without --draft" || bad "D5 a DRAFT retest_statement is refused without --draft ($RC: $(cat "$W/err"))"
run --draft "$W/t.md" "$W/f.txt" "$W/md.txt"
[ "$RC" = 0 ] && ok "D5 --draft renders a DRAFT value: exit 0" || bad "D5 --draft renders a DRAFT value: exit 0 ($RC: $(cat "$W/err"))"
chk1="$(printf '%s\n' "$OUT" | head -n 1)"
[ "$chk1" = '<!-- DRAFT RENDERING (render_release_entry.py --draft): NOT A RELEASE ENTRY; do not commit it as one -->' ] && ok "D5 a draft rendering starts with the fixed marker line" || bad "D5 a draft rendering starts with the fixed marker line (got: $chk1)"
has "D5 --draft keeps the DRAFT value" "DRAFT: the provisional list"
grep -q 'draft rendering' "$W/err" && ok "D5 --draft says so on stderr" || bad "D5 --draft says so on stderr"
run "$W/t.md" "$W/f.txt" "$W/m.txt"; printf '%s\n' "$OUT" | grep -q 'DRAFT RENDERING' && bad "D5 a normal rendering has no draft marker" || ok "D5 a normal rendering has no draft marker"
for v in 'DRAFTED by the conductor' 'a draft column' 'redraft'; do
  printf '@@date\n2026-11-11\n@@block\n%s\n' "$v" >"$W/md3.txt"; run "$W/t.md" "$W/f.txt" "$W/md3.txt"
  [ "$RC" = 0 ] && ok "D5 not the word DRAFT, accepted: $v" || bad "D5 not the word DRAFT, accepted: $v ($RC: $(cat "$W/err"))"
done
run --draft "$W/t.md" "$W/f.txt"; [ "$RC" = 2 ] && ok "D5 --draft with two files: usage exit 2" || bad "D5 --draft with two files: usage exit 2 ($RC)"
run "$W/t.md" --draft "$W/f.txt" "$W/md.txt"; [ "$RC" = 2 ] && ok "D5 --draft only as the first argument: usage exit 2" || bad "D5 --draft only as the first argument: usage exit 2 ($RC)"
run --drafty "$W/t.md" "$W/f.txt" "$W/md.txt"; [ "$RC" = 2 ] && ok "D5 an unknown option: usage exit 2" || bad "D5 an unknown option: usage exit 2 ($RC)"
run --draft "$W/t.md" "$W/f.txt" "$W/m3.txt"; [ "$RC" = 3 ] && ok "D5 --draft still refuses TODO" || bad "D5 --draft still refuses TODO ($RC)"
# CON-423 (D9): the heading takes MANUAL:cut_date whole, so it must be a bare calendar date YYYY-MM-DD (also with --draft)
printf '## v -- {{MANUAL:cut_date}}\n' >"$W/tc.md"
for v in '2026-11-16' '2028-02-29'; do printf '@@cut_date\n%s\n' "$v" >"$W/mc.txt"; run "$W/tc.md" "$W/f.txt" "$W/mc.txt"
  [ "$RC" = 0 ] && has "D9 cut_date bare date accepted: $v" "## v -- $v" || bad "D9 cut_date bare date accepted: $v ($RC: $(cat "$W/err"))"; done
# the last two values are forms date.fromisoformat accepts; only the YYYY-MM-DD shape refuses them
for v in '2026-11-16 (DRAFT)' '16 Nov 2026' '2026-13-01' '2026-02-30' '2027-02-29' ' 2026-11-16x' '2026-11-6' '20261116' '2026-W46-1'; do printf '@@cut_date\n%s\n' "$v" >"$W/mc.txt"
  run --draft "$W/tc.md" "$W/f.txt" "$W/mc.txt"
  [ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'MANUAL:cut_date (must be a bare calendar date YYYY-MM-DD)' "$W/err" && ok "D9 cut_date not a bare date refused (also with --draft): $v" || bad "D9 cut_date not a bare date refused (also with --draft): $v ($RC: $(cat "$W/err"))"; done
T="${RRE_TEMPLATE:-$ROOT/docs/release/helixconstitution-v73.4_entry.template.md}"
# CON-417: no unconditional never-run sentence, the retest sentence comes from retest_statement, and no
# wording that lets (L7) ride open or calls the operator decision a conforming waiver of (L7) (§11.4.230(E.3)/(F.3)(2))
grep -q 'has never run on this candidate' "$T" && bad "template has no unconditional never-run sentence" || ok "template has no unconditional never-run sentence"
grep -q '{{MANUAL:retest_statement}}' "$T" && ok "template takes the retest sentence from MANUAL:retest_statement" || bad "template takes the retest sentence from MANUAL:retest_statement"
grep -qE 'and \(L7\) \(no .*ride open|for \(L1\), \(L6\), \(L7\)|relaxes \(F\.3\)' "$T" && bad "template does not say (L7) rides open or is relaxed" || ok "template does not say (L7) rides open or is relaxed"
grep -q 'blocks a release of every class' "$T" && ok "template states an open (L7) blocks every class" || bad "template states an open (L7) blocks every class"
grep -q 'not a conforming waiver' "$T" && ok "template calls the decision an override, not a conforming waiver" || bad "template calls the decision an override, not a conforming waiver"
: >"$W/mall.txt"
for k in $(sed '1,/-->/d' "$T" | grep -o '{{MANUAL:[^}]*}}' | sed 's/{{MANUAL:\(.*\)}}/\1/' | sort -u); do
  case "$k" in retest_statement) printf '@@%s\nNOT RUN on this candidate\n' "$k" ;; cut_date) printf '@@%s\n2026-11-16\n' "$k" ;;
    *) printf '@@%s\nvalue-%s\n' "$k" "$k" ;; esac >>"$W/mall.txt"; done
sed '1,/-->/d' "$T" | grep -o '{{[^}]*}}' | sed 's/^{{\(.*\)}}$/\1/' | grep -v '^MANUAL:' | grep -vx 'states_block\|unmerged_refs_block' | sort -u \
  | while IFS= read -r k; do printf '%s=value-%s\n' "$k" "$k"; done >"$W/fall.txt"
# CON-423 (D9): the last ref of the §11.4.288 block is never followed by a "." the template appends (one remote with
# two refs; the rendered line must equal the block line exactly, and no line may be the block line plus ".")
printf 'unmerged_refs_count[origin]=2\nunmerged_refs[origin]=feat/a:1 feat/zz_last:15\n' >>"$W/fall.txt"
nk="$(wc -l <"$W/fall.txt" | tr -d ' ')"
[ "$nk" -gt 10 ] && ok "shipped template: $nk fact keys named (control: more than 10)" || bad "shipped template: fact keys named ($nk)"
run "$T" "$W/fall.txt" "$W/mall.txt"
[ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q '{{' && printf '%s\n' "$OUT" | grep -q 'value-count_line' \
  && ok "shipped template renders from synthetic facts" || bad "shipped template renders from synthetic facts ($RC: $(cat "$W/err"))"
printf '%s\n' "$OUT" | grep -qx -- '- origin: 2 ref(s): feat/a:1 feat/zz_last:15' && ok "D9 the refs line is rendered exactly (positive needle)" || bad "D9 the refs line is rendered exactly"
printf '%s\n' "$OUT" | grep -q 'feat/zz_last:15\.' && bad "D9 no '.' after the last ref name" || ok "D9 no '.' after the last ref name"
printf '%s\n' "$OUT" | grep -qx '## helixconstitution-v73.4 — 2026-11-16 — .*' && ok "D9 the heading carries the bare cut date" || bad "D9 the heading carries the bare cut date"
if [ -n "${RRE_FACTS:-}" ] && [ -f "$RRE_FACTS" ]; then
  run "$T" "$RRE_FACTS" "$W/mall.txt"
  [ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q '{{' && ok "shipped template renders from real facts" || bad "shipped template renders ($RC: $(cat "$W/err"))"
else
  # round 8 (N6): this is the one EXPECTED skip of the release suites (the real-facts case needs a facts file the
  # hermetic run does not make); it is printed, it is not counted as a pass, and the suite's status is the pass/fail
  # status of the hermetic cases. Every other release suite exits 77 on a skipped case (suite_exit of
  # tests/release/env_allow.sh; round 9, F5: test_redact_cut.sh C11 and test_tag_and_release.sh C22-C23 too)
  echo "SKIP shipped template renders from real facts: RRE_FACTS is not set to a facts file (run derive_release_facts.sh and set RRE_FACTS=<file> to run it)"
fi
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
