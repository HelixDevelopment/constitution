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
# a retest_statement value must START with a run verdict word of the runner (B-M1) or NOT RUN, so no entry implies a pass
printf '## r\nretest: {{MANUAL:retest_statement}}\n' >"$W/rt.md"; printf 'x=1\n' >"$W/rf.txt"
for v in 'PASS-FULL on base abc, tier default+heavy, log L' 'FAIL on base abc, log L' 'NOT RUN on this candidate'; do   # B-M1: PARTIAL-TOPOLOGY now renders with a gap note (checked below)
  printf '@@retest_statement\n%s\n' "$v" >"$W/rm.txt"; run "$W/rt.md" "$W/rf.txt" "$W/rm.txt"
  [ "$RC" = 0 ] && has "retest verdict accepted: ${v%% *}" "retest: $v" || bad "retest verdict accepted: ${v%% *} ($RC: $(cat "$W/err"))"
done
for v in 'passed' 'all green' 'PASS-FULLY done' 'pass-full' 'has never run' 'FAILED' 'the retest: PASS-FULL'; do
  printf '@@retest_statement\n%s\n' "$v" >"$W/rm.txt"; run "$W/rt.md" "$W/rf.txt" "$W/rm.txt"
  [ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'retest_statement (must start with' "$W/err" && ok "retest value without a leading verdict token refused: $v" || bad "retest value without a leading verdict token refused: $v ($RC)"
done
# B-M1 (v73.4 dry run, 2026-11-16): the renderer's verdict set is the runner's. Oracle: the hand-written table below
# (word, exit code, class) taken from the EXIT table of scripts/run_full_suite.sh, never from the renderer.
# Class "retest" and "fail" render as given; every "gap" word renders with a fixed gap note after the word, so a
# PARTIAL, MISMATCH, REFUSED or WITH-KNOWN verdict can never read as a pass.
RUNNER="$ROOT/scripts/full_suite/run_full_suite.py"
ORACLE='PASS-FULL 0 retest
FAIL 1 fail
MANIFEST-MISMATCH 3 gap-not-run
PARTIAL-NOT-RUN 4 gap
PARTIAL-DEFAULT-SET 5 gap
PARTIAL-SKIPS 6 gap
PASS-FULL-WITH-KNOWN 7 gap
PARTIAL-TOPOLOGY 8 gap
REFUSED-TOPOLOGY 9 gap-not-run
PARTIAL-DIRTY-TREE 10 gap
PARTIAL-EXCLUSIONS-UNACCEPTED 11 gap'
GAPNOTE='[gap: not a section 11.4.40 full retest; (L6) stays open]'
NRNOTE='[gap: nothing was run; not a section 11.4.40 retest; (L6) stays open]'
# (a) the runner's main() prints exactly these RESULT words followed by exactly these return codes (read with ast; the
# three non-run modes --verify-manifest, --generate-manifest and --sync-guide are named in the oracle too), and the
# runner's RETEST_RESULTS table is the oracle table
pairs="$(python3 -I - "$RUNNER" <<'PY'
import ast, sys
t = ast.parse(open(sys.argv[1], encoding="utf-8").read())
main = [f for f in t.body if isinstance(f, ast.FunctionDef) and f.name == "main"][0]
def word(e):
    s = e.value if isinstance(e, ast.Constant) else (e.left.value if isinstance(e, ast.BinOp) and isinstance(e.left, ast.Constant) else None)
    if isinstance(s, str) and s.startswith("RESULT: "):
        return s[8:].split(" ")[0]
    return None
out = set()
for node in ast.walk(main):
    for field in ("body", "orelse"):
        b = getattr(node, field, None)
        if not isinstance(b, list):
            continue
        for a, r in zip(b, b[1:]):
            if (isinstance(a, ast.Expr) and isinstance(a.value, ast.Call) and getattr(a.value.func, "id", "") == "out"
                    and a.value.args and word(a.value.args[0]) and isinstance(r, ast.Return) and isinstance(r.value, ast.Constant)):
                out.add("%s %d" % (word(a.value.args[0]), r.value.value))
tab = [n for n in t.body if isinstance(n, ast.Assign) and any(getattr(x, "id", "") == "RETEST_RESULTS" for x in n.targets)]
print("\n".join(sorted(out)))
print("TABLE " + (" ".join("%s:%d:%s" % tuple(x) for x in ast.literal_eval(tab[0].value)) if tab else "absent"))
PY
)"
want_pairs="$( { printf '%s\n' "$ORACLE" | awk '{print $1" "$2}'; printf 'MANIFEST-OK 0\nMANIFEST-NOT-GENERATED 3\nGUIDE-NOT-SYNCED 3\n'; } | sort -u)"
got_run="$(printf '%s\n' "$pairs" | grep -v '^TABLE ' | sort -u)"
[ "$got_run" = "$want_pairs" ] && ok "B-M1 the runner's main() prints these RESULT words with these exit codes (ast; control: $(printf '%s\n' "$got_run" | wc -l) pairs)" \
  || bad "B-M1 runner RESULT/exit pairs differ from the oracle: got [$got_run]"
want_tab="TABLE $(printf '%s\n' "$ORACLE" | awk '{printf "%s%s:%s:%s", (NR>1?" ":""), $1, $2, $3}')"
[ "$(printf '%s\n' "$pairs" | grep '^TABLE ')" = "$want_tab" ] && ok "B-M1 the runner's RETEST_RESULTS table is the oracle table" \
  || bad "B-M1 RETEST_RESULTS table: got [$(printf '%s\n' "$pairs" | grep '^TABLE ')]"
# (b) every runner word is accepted and rendered with its class note
printf '%s\n' "$ORACLE" >"$W/oracle.txt"
while read -r wd rc cls; do
  printf '@@retest_statement\n%s (run_full_suite exit %s) on base abc, log L\n' "$wd" "$rc" >"$W/rm.txt"; run "$W/rt.md" "$W/rf.txt" "$W/rm.txt"
  case "$cls" in
    retest|fail) want="retest: $wd (run_full_suite exit $rc) on base abc, log L" ;;
    gap) want="retest: $wd $GAPNOTE (run_full_suite exit $rc) on base abc, log L" ;;
    *) want="retest: $wd $NRNOTE (run_full_suite exit $rc) on base abc, log L" ;;
  esac
  if [ "$RC" = 0 ]; then has "B-M1 runner verdict $wd rendered as $cls" "$want"; else bad "B-M1 runner verdict $wd rendered as $cls ($RC: $(cat "$W/err"))"; fi
done <"$W/oracle.txt"
# (c) no gap word ever renders bare (negative needle over every gap row), and PASS-FULL and FAIL never get a note
while read -r wd rc cls; do
  printf '@@retest_statement\n%s\n' "$wd" >"$W/rm.txt"; run "$W/rt.md" "$W/rf.txt" "$W/rm.txt"
  case "$cls" in
    gap*) if [ "$RC" = 0 ] && ! printf '%s\n' "$OUT" | grep -qxF "retest: $wd"; then ok "B-M1 $wd never rendered bare"; else bad "B-M1 $wd rendered bare or refused ($RC)"; fi ;;
    *) if [ "$RC" = 0 ] && ! printf '%s\n' "$OUT" | grep -qF 'gap:'; then ok "B-M1 $wd carries no gap note"; else bad "B-M1 $wd got a gap note or was refused ($RC)"; fi ;;
  esac
done <"$W/oracle.txt"
# (d) words that are not run verdicts stay refused: MANIFEST-OK (a --verify-manifest result), a lower-case word, a
# prefix of a real word and a real word with a suffix (PASS-FULL-WITH must not match PASS-FULL)
for v in 'MANIFEST-OK' 'partial-skips' 'PARTIAL' 'PASS-FULL-WITH' 'PARTIAL-TOPOLOGYX' 'REFUSED' 'PASS-FULL-WITH-KNOWNS'; do
  printf '@@retest_statement\n%s\n' "$v" >"$W/rm.txt"; run "$W/rt.md" "$W/rf.txt" "$W/rm.txt"
  if [ "$RC" = 3 ] && [ -z "$OUT" ]; then ok "B-M1 not a run verdict refused: $v"; else bad "B-M1 not a run verdict refused: $v ($RC)"; fi
done
# (e) the refusal message names the words from the runner's table (positive needle on two of them and NOT RUN)
printf '@@retest_statement\npassed\n' >"$W/rm.txt"; run "$W/rt.md" "$W/rf.txt" "$W/rm.txt"
grep -qF 'PARTIAL-DEFAULT-SET' "$W/err" && grep -qF 'NOT RUN' "$W/err" && ok "B-M1 the refusal lists the runner's words and NOT RUN" || bad "B-M1 refusal message: $(cat "$W/err")"
# (f) fail closed: the renderer cannot read the runner's table -> exit 3 naming RETEST_RESULTS, never a fixed list
mkdir -p "$W/iso/scripts/release" "$W/iso/scripts/full_suite"; cp "$S" "$W/iso/scripts/release/render_release_entry.py"
printf 'RETEST_RESULTS = 7\n' >"$W/iso/scripts/full_suite/run_full_suite.py"
printf '@@retest_statement\nPASS-FULL on base abc\n' >"$W/rm.txt"
OUT="$(python3 -I "$W/iso/scripts/release/render_release_entry.py" "$W/rt.md" "$W/rf.txt" "$W/rm.txt" 2>"$W/err")"; RC=$?
[ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'RETEST_RESULTS' "$W/err" && ok "B-M1 a malformed runner table is refused (exit 3)" || bad "B-M1 malformed runner table ($RC: $(cat "$W/err"))"
rm -f -- "$W/iso/scripts/full_suite/run_full_suite.py"
OUT="$(python3 -I "$W/iso/scripts/release/render_release_entry.py" "$W/rt.md" "$W/rf.txt" "$W/rm.txt" 2>"$W/err")"; RC=$?
[ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'RETEST_RESULTS' "$W/err" && ok "B-M1 an absent runner is refused (exit 3)" || bad "B-M1 absent runner ($RC: $(cat "$W/err"))"
cp "$RUNNER" "$W/iso/scripts/full_suite/run_full_suite.py"
OUT="$(python3 -I "$W/iso/scripts/release/render_release_entry.py" "$W/rt.md" "$W/rf.txt" "$W/rm.txt" 2>"$W/err")"; RC=$?
[ "$RC" = 0 ] && ok "B-M1 control: the same isolated copy renders with the real runner beside it" || bad "B-M1 isolated control ($RC: $(cat "$W/err"))"
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
# round 3 (review of f4c6e8ab, N4): the FACTS reader refuses a duplicate key (it kept the last copy, a first-match
# reader kept the first, so a forged earlier copy fooled one of them), a line that is not KEY=VALUE, a malformed key,
# and any control or invisible format character; the value is never echoed. Payload lines are written with printf
# escapes, never typed raw.
printf '## r\nbase {{base}}\n' >"$W/rn.md"; : >"$W/rn_m.txt"
for c in 'dup:base=abc\nbase=def\n:occurs twice' 'noeq:base=abc\njunk line\n:not KEY=VALUE' 'key:base=abc\nopen_status[a]b]=1\n:malformed key' 'key2:base=abc\nBase2=1\n:malformed key' \
         'lf-forged:base=abc\nretest_item_evidence=yes\nretest_item_evidence=no\n:occurs twice' 'cr:base=ab\rc\n:control' \
         'nel:base=ab\302\205c\n:control' 'ls:base=ab\342\200\250c\n:control' 'rlo:base=ab\342\200\256c\n:control' \
         'zwsp:base=ab\342\200\213c\n:control' 'esc:base=ab\033[31mc\n:control' 'notutf8:base=ab\205c\n:not UTF-8'; do
  n="${c%%:*}"; r="${c#*:}"; body="${r%:*}"; why="${r##*:}"
  printf "$body" >"$W/rn_$n.txt"; run "$W/rn.md" "$W/rn_$n.txt" "$W/rn_m.txt"
  [ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q "$why" "$W/err" && ok "FACTS $n refused (rc 3, '$why')" || bad "FACTS $n refused (rc $RC: $(cat "$W/err"))"
done
printf '## r\nbase {{base}}\nready {{open_status[Ready for testing]}}\n' >"$W/rn_ok.md"
printf 'base=ab\303\251\342\200\224c\nopen_status[Ready for testing]=1\n' >"$W/rn_ok.txt"; run "$W/rn_ok.md" "$W/rn_ok.txt" "$W/rn_m.txt"
[ "$RC" = 0 ] && has "FACTS with non-ASCII letters accepted (false-positive control)" "base abé—c" || bad "FACTS with non-ASCII letters accepted (rc $RC: $(cat "$W/err"))"
# B-M4 (v73.4 dry run, 2026-11-16): a lander placeholder or draft text in a MANUAL value is refused (exit 3) unless the
# render is an explicit --draft, and a --draft render carries a fixed marker line that tag_and_release.sh refuses.
# Oracle: the shapes below are the ones the dry run rendered with rc 0 (BLOCKERS.md B-M4), written by hand here.
DMARK='> **DRAFT RENDER — not a release entry.** Made by render_release_entry.py --draft; it may carry placeholders, and scripts/release/tag_and_release.sh refuses to cut a release from notes that contain this line.'
printf '<!--\nx\n-->\n## v1 -- {{MANUAL:cut_date}}\nbody {{MANUAL:block}}\n' >"$W/d.md"; printf 'x=1\n' >"$W/df.txt"
mkm(){ printf '@@cut_date\n%s\n@@block\n%s\n' "$1" "$2" >"$W/dm.txt"; }
while IFS='|' read -r key cd blk; do
  mkm "$cd" "$blk"; run "$W/d.md" "$W/df.txt" "$W/dm.txt"
  [ "$RC" = 3 ] && [ -z "$OUT" ] && grep -qF "MANUAL:$key" "$W/err" && grep -q 'placeholder' "$W/err" \
    && ok "B-M4 placeholder refused without --draft: $key=${cd}${blk}" || bad "B-M4 placeholder refused without --draft: $key=${cd}${blk} ($RC: $(cat "$W/err"))"
  run --draft "$W/d.md" "$W/df.txt" "$W/dm.txt"
  [ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "$DMARK" ] && printf '%s\n' "$OUT" | sed -n 1p | grep -q '^## v1 -- ' \
    && ok "B-M4 the same value renders with --draft, marker right after the heading: $key" || bad "B-M4 --draft render: $key ($RC: $(cat "$W/err"))"
done <<'CASES'
cut_date|DRAFT|ok
cut_date|UNCONFIRMED-CUT-DATE (not cut yet)|ok
cut_date|2026-11-31|ok
cut_date|16.11.2026|ok
cut_date|2026-11-16 (draft)|ok
block|2026-11-16|`<CON-NNN>`
block|2026-11-16|expires `<recorded date + 30 days>`
block|2026-11-16|`<paste the summary line>`
block|2026-11-16|push to <all 10 remotes>
block|2026-11-16|see <...>
block|2026-11-16|this is DRAFT text
CASES
# negative controls: real values that look a little like the shapes above render without --draft and with no marker
mkm 2026-11-16 'see <https://example.org/x>, <details>, <br/>; UNCONFIRMED: x; a draft note; CON-PENDING-relmach; ATM-NNN notation'
run "$W/d.md" "$W/df.txt" "$W/dm.txt"
[ "$RC" = 0 ] && ! printf '%s\n' "$OUT" | grep -qF 'DRAFT RENDER' && has "B-M4 control: real values render, no marker" "## v1 -- 2026-11-16" \
  || bad "B-M4 control: real values render ($RC: $(cat "$W/err"))"
# --draft relaxes only the placeholder check: TODO, a missing value and an unused block are still refused
mkm DRAFT TODO; run --draft "$W/d.md" "$W/df.txt" "$W/dm.txt"
[ "$RC" = 3 ] && [ -z "$OUT" ] && ok "B-M4 --draft still refuses TODO" || bad "B-M4 --draft still refuses TODO ($RC)"
printf '@@cut_date\nDRAFT\n' >"$W/dm.txt"; run --draft "$W/d.md" "$W/df.txt" "$W/dm.txt"
[ "$RC" = 3 ] && grep -qF 'MANUAL:block' "$W/err" && ok "B-M4 --draft still refuses a missing value" || bad "B-M4 --draft still refuses a missing value ($RC)"
# --draft with no "## " heading: the marker is the first line
printf 'no heading {{MANUAL:cut_date}} {{MANUAL:block}}\n' >"$W/d2.md"; mkm DRAFT x; run --draft "$W/d2.md" "$W/df.txt" "$W/dm.txt"
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | sed -n 1p)" = "$DMARK" ] && ok "B-M4 --draft without a heading: marker first" || bad "B-M4 --draft without a heading ($RC)"
# usage: an unknown option and --draft with too few arguments are usage errors (exit 2)
run --drafty "$W/d.md" "$W/df.txt" "$W/dm.txt"; [ "$RC" = 2 ] && ok "B-M4 unknown option is a usage error" || bad "B-M4 unknown option is a usage error ($RC)"
run --draft "$W/d.md" "$W/df.txt"; [ "$RC" = 2 ] && ok "B-M4 --draft with two files is a usage error" || bad "B-M4 --draft with two files ($RC)"
# the marker the renderer writes is the line tag_and_release.sh refuses (same literal in both, checked here)
TARS="$ROOT/scripts/release/tag_and_release.sh"
grep -qF 'DRAFT RENDER — not a release entry' "$TARS" && ok "B-M4 tag_and_release.sh knows the draft marker" || bad "B-M4 tag_and_release.sh knows the draft marker"
# the shipped template renders when every key is given (smoke over the shipped file). CON-232 (review
# m-6): the synthetic case always runs (one value per key named by the template itself); the real-facts
# case runs when RRE_FACTS names a facts file and otherwise prints an explicit SKIP line (§11.4.3).
# CON-423 (rehearsal of the v73.4 cut, REHEARSAL_REPORT.md D5): a MANUAL value that still says DRAFT is refused unless
# the caller asks for a draft rendering with --draft (first argument); a draft rendering starts with a fixed marker line
# so it can never pass for a release entry. DRAFT is matched as a whole word, case-sensitive (as TODO and TBD are).
printf '@@date\n2026-11-11\n@@block\nDRAFT: the provisional list\n' >"$W/md.txt"; run "$W/t.md" "$W/f.txt" "$W/md.txt"
[ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'MANUAL:block (still a placeholder: the word DRAFT' "$W/err" && ok "D5 a DRAFT manual value is refused without --draft" || bad "D5 a DRAFT manual value is refused without --draft ($RC: $(cat "$W/err"))"
printf '@@date\n2026-11-11\n@@block\nx\n@@retest_statement\nNOT RUN — DRAFT: rehearsal\n' >"$W/md2.txt"; printf '## v\n{{MANUAL:date}}\n{{MANUAL:block}}\nretest: {{MANUAL:retest_statement}}\n' >"$W/td2.md"
run "$W/td2.md" "$W/f.txt" "$W/md2.txt"
[ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'MANUAL:retest_statement (still a placeholder: the word DRAFT' "$W/err" && ok "D5 a DRAFT retest_statement is refused without --draft" || bad "D5 a DRAFT retest_statement is refused without --draft ($RC: $(cat "$W/err"))"
run --draft "$W/t.md" "$W/f.txt" "$W/md.txt"
[ "$RC" = 0 ] && ok "D5 --draft renders a DRAFT value: exit 0" || bad "D5 --draft renders a DRAFT value: exit 0 ($RC: $(cat "$W/err"))"
# landing merge with B-M4: the one marker is DMARK, put right after the first "## " heading (first line without one)
printf '%s\n' "$OUT" | head -n 2 | grep -qxF "$DMARK" && ok "D5 a draft rendering carries the fixed marker line" || bad "D5 a draft rendering carries the fixed marker line (got: $(printf '%s\n' "$OUT" | head -n 2))"
has "D5 --draft keeps the DRAFT value" "DRAFT: the provisional list"
grep -q 'DRAFT render' "$W/err" && ok "D5 --draft says so on stderr" || bad "D5 --draft says so on stderr"
run "$W/t.md" "$W/f.txt" "$W/m.txt"; printf '%s\n' "$OUT" | grep -q 'DRAFT RENDER' && bad "D5 a normal rendering has no draft marker" || ok "D5 a normal rendering has no draft marker"
for v in 'DRAFTED by the conductor' 'a draft column' 'redraft'; do
  printf '@@date\n2026-11-11\n@@block\n%s\n' "$v" >"$W/md3.txt"; run "$W/t.md" "$W/f.txt" "$W/md3.txt"
  [ "$RC" = 0 ] && ok "D5 not the word DRAFT, accepted: $v" || bad "D5 not the word DRAFT, accepted: $v ($RC: $(cat "$W/err"))"
done
# CON-423 review r1 (M4): DRAFT glued to a digit, an underscore or a hyphen is still the marker (DRAFT_1, DRAFT2), and so
# is a full-width or zero-width-split DRAFT (folded with NFKC, format characters removed); TODO and TBD get the same
# boundary (TODO_1). Golden FALSE: a letter on either side is another word (DRAFTED, DRAFTS, REDRAFT), and lower or
# mixed case stays accepted by design (case-sensitive marker words).
for v in 'DRAFT_1 of the list' 'see DRAFT2' 'v-DRAFT-3' '(DRAFT)' $'ＤＲＡＦＴ list' $'DR​AFT list'; do
  printf '@@date\n2026-11-11\n@@block\n%s\n' "$v" >"$W/md4.txt"; run "$W/t.md" "$W/f.txt" "$W/md4.txt"
  [ "$RC" = 3 ] && grep -q 'MANUAL:block (still a placeholder: the word DRAFT' "$W/err" && ok "M4 a DRAFT marker is refused: $v" || bad "M4 a DRAFT marker is refused: $v ($RC: $(cat "$W/err"))"
done
for v in 'TODO_1 the list' 'TBD2'; do
  printf '@@date\n2026-11-11\n@@block\n%s\n' "$v" >"$W/md4.txt"; run "$W/t.md" "$W/f.txt" "$W/md4.txt"
  [ "$RC" = 3 ] && grep -q 'MANUAL:block' "$W/err" && ok "M4 a TODO/TBD marker glued to a digit or underscore is refused: $v" || bad "M4 TODO/TBD glued: $v ($RC: $(cat "$W/err"))"
done
# CON-423 r3 (review r2 X8, X9): an underscore or a digit before the word is still no letter (MY_TODO, 2DRAFT); and a
# Cyrillic or Greek look-alike letter is folded to the Latin one (the same map as check_provisional_verification_lines.py)
for v in 'MY_TODO the list' 'see 2DRAFT list' $'DRАFT list' $'ТBD later' $'ТОDО list' $'DRΑFT list' $'D̈RAFT list'; do
  printf '@@date\n2026-11-11\n@@block\n%s\n' "$v" >"$W/md4.txt"; run "$W/t.md" "$W/f.txt" "$W/md4.txt"
  [ "$RC" = 3 ] && grep -q 'MANUAL:block' "$W/err" && ok "M4 r3 a marker after _ or a digit, or in look-alike letters, is refused: $v" || bad "M4 r3 refused: $v ($RC: $(cat "$W/err"))"
done
# golden FALSE: a look-alike word that is not a marker word stays accepted (Cyrillic "Пlan", a Greek word)
for v in $'Пlan notes' $'λόγος list' $'ДRAFT is not D'; do
  printf '@@date\n2026-11-11\n@@block\n%s\n' "$v" >"$W/md4.txt"; run "$W/t.md" "$W/f.txt" "$W/md4.txt"
  [ "$RC" = 0 ] && ok "M4 r3 golden FALSE, accepted: $v" || bad "M4 r3 golden FALSE, accepted: $v ($RC: $(cat "$W/err"))"
done
# the look-alike map of the renderer equals the map of the verification-line checker (one map, two copies)
CHK="${PVL_SCRIPT:-$ROOT/scripts/validation/check_provisional_verification_lines.py}"
python3 -I - "$S" "$CHK" <<'PYEOF' && ok "M4 r3 the two look-alike maps are equal" || bad "M4 r3 the two look-alike maps are equal"
import ast, sys
def m(p):
    for n in ast.parse(open(p, encoding="utf-8").read()).body:
        if isinstance(n, ast.Assign) and any(getattr(t, "id", "") == "CONFUSABLES" for t in n.targets):
            return ast.literal_eval(n.value)
a, b = m(sys.argv[1]), m(sys.argv[2])
sys.exit(0 if a and a == b else 1)
PYEOF
# CON-423 r3: in-suite mutants. X8 and X9 are the reviewer's verbatim; R1-R4 are this fixer's. Each mutant copy must
# make at least one of its cases give a result other than the real script's.
mut(){ # name, python replace-from, replace-to, value that the real script refuses
  python3 -I -c 'import sys;s=open(sys.argv[1],encoding="utf-8").read();a,b=sys.argv[3],sys.argv[4]
if a not in s: sys.exit(5)
open(sys.argv[2],"w",encoding="utf-8").write(s.replace(a,b,1))' "$S" "$W/mut.py" "$2" "$3"; mrc=$?
  [ "$mrc" = 0 ] || { bad "mutant $1 applies (rc $mrc)"; return; }
  printf '@@date\n2026-11-11\n@@block\n%s\n' "$4" >"$W/mdm.txt"
  run "$W/t.md" "$W/f.txt" "$W/mdm.txt"; rr=$RC
  OUT="$(python3 -I "$W/mut.py" "$W/t.md" "$W/f.txt" "$W/mdm.txt" 2>"$W/err")"; mr=$?
  [ "$rr" = 3 ] && [ "$mr" = 0 ] && ok "mutant $1 killed (real refuses rc 3, mutant accepts: $4)" || bad "mutant $1 SURVIVED (real $rr, mutant $mr)"
}
mut X8 'PLACEHOLDER_WORD = re.compile(r"(?<![A-Za-z])(TODO|TBD)' 'PLACEHOLDER_WORD = re.compile(r"(?<![A-Za-z_])(TODO|TBD)' 'MY_TODO the list'
mut X9 'DRAFT_WORD = re.compile(r"(?<![A-Za-z])DRAFT' 'DRAFT_WORD = re.compile(r"(?<![A-Za-z0-9])DRAFT' 'see 2DRAFT list'
mut R1-no-confusables 'CONFUSABLES.get(ch, ch)' 'ch' $'DRАFT list'
mut R2-no-mark-strip 'if unicodedata.category(ch) != "Mn"' 'if True' $'D̈RAFT list'
mut R3-cyrillic-T-dropped '"Т": "T", ' '' $'ТBD later'
mut R4-greek-A-dropped '"Α": "A", ' '' $'DRΑFT list'
for v in 'DRAFTS of the plan' 'REDRAFT done' 'Draft notes' 'draft_1 lower case' 'TODOS done' 'XTBD'; do
  printf '@@date\n2026-11-11\n@@block\n%s\n' "$v" >"$W/md4.txt"; run "$W/t.md" "$W/f.txt" "$W/md4.txt"
  [ "$RC" = 0 ] && ok "M4 golden FALSE, accepted: $v" || bad "M4 golden FALSE, accepted: $v ($RC: $(cat "$W/err"))"
done
run --draft "$W/t.md" "$W/f.txt"; [ "$RC" = 2 ] && ok "D5 --draft with two files: usage exit 2" || bad "D5 --draft with two files: usage exit 2 ($RC)"
run "$W/t.md" --draft "$W/f.txt" "$W/md.txt"; [ "$RC" = 2 ] && ok "D5 --draft only as the first argument: usage exit 2" || bad "D5 --draft only as the first argument: usage exit 2 ($RC)"
run --drafty "$W/t.md" "$W/f.txt" "$W/md.txt"; [ "$RC" = 2 ] && ok "D5 an unknown option: usage exit 2" || bad "D5 an unknown option: usage exit 2 ($RC)"
run --draft "$W/t.md" "$W/f.txt" "$W/m3.txt"; [ "$RC" = 3 ] && ok "D5 --draft still refuses TODO" || bad "D5 --draft still refuses TODO ($RC)"
# CON-423 (D9): the heading takes MANUAL:cut_date whole, so it must be a bare calendar date YYYY-MM-DD. Landing merge with
# B-M4: --draft relaxes this check (B-M4 rehearsals render cut_date=DRAFT), so the refusals are checked without --draft;
# "also with --draft" is a tracked follow-up.
printf '## v -- {{MANUAL:cut_date}}\n' >"$W/tc.md"
for v in '2026-11-16' '2028-02-29'; do printf '@@cut_date\n%s\n' "$v" >"$W/mc.txt"; run "$W/tc.md" "$W/f.txt" "$W/mc.txt"
  [ "$RC" = 0 ] && has "D9 cut_date bare date accepted: $v" "## v -- $v" || bad "D9 cut_date bare date accepted: $v ($RC: $(cat "$W/err"))"; done
# the last two values are forms date.fromisoformat accepts; only the YYYY-MM-DD shape refuses them
for v in '2026-11-16 (DRAFT)' '16 Nov 2026' '2026-13-01' '2026-02-30' '2027-02-29' ' 2026-11-16x' '2026-11-6' '20261116' '2026-W46-1'; do printf '@@cut_date\n%s\n' "$v" >"$W/mc.txt"
  run "$W/tc.md" "$W/f.txt" "$W/mc.txt"
  [ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'MANUAL:cut_date (still a placeholder' "$W/err" && ok "D9 cut_date not a bare date refused: $v" || bad "D9 cut_date not a bare date refused: $v ($RC: $(cat "$W/err"))"; done
T="${RRE_TEMPLATE:-$ROOT/docs/release/helixconstitution-v73.4_entry.template.md}"
# CON-417: no unconditional never-run sentence, the retest sentence comes from retest_statement, and no
# wording that lets (L7) ride open or calls the operator decision a conforming waiver of (L7) (§11.4.230(E.3)/(F.3)(2))
grep -q 'has never run on this candidate' "$T" && bad "template has no unconditional never-run sentence" || ok "template has no unconditional never-run sentence"
grep -q '{{MANUAL:retest_statement}}' "$T" && ok "template takes the retest sentence from MANUAL:retest_statement" || bad "template takes the retest sentence from MANUAL:retest_statement"
grep -qE 'and \(L7\) \(no .*ride open|for \(L1\), \(L6\), \(L7\)|relaxes \(F\.3\)' "$T" && bad "template does not say (L7) rides open or is relaxed" || ok "template does not say (L7) rides open or is relaxed"
grep -q 'blocks a release of every class' "$T" && ok "template states an open (L7) blocks every class" || bad "template states an open (L7) blocks every class"
grep -q 'not a conforming waiver' "$T" && ok "template calls the decision an override, not a conforming waiver" || bad "template calls the decision an override, not a conforming waiver"
: >"$W/mall.txt"   # B-M4: cut_date gets a real date (the renderer checks it)
for k in $(sed '1,/-->/d' "$T" | grep -o '{{MANUAL:[^}]*}}' | sed 's/{{MANUAL:\(.*\)}}/\1/' | sort -u); do
  if [ "$k" = retest_statement ]; then printf '@@%s\nNOT RUN on this candidate\n' "$k" >>"$W/mall.txt"
  elif [ "$k" = cut_date ]; then printf '@@%s\n2026-11-16\n' "$k" >>"$W/mall.txt"; else printf '@@%s\nvalue-%s\n' "$k" "$k" >>"$W/mall.txt"; fi; done
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
