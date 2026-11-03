#!/usr/bin/env bash
# cm_agent_type_label_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-AGENT-TYPE-LABEL (§11.4.182 / §11.4.231(F)).
#
# Purpose : prove the gate is NOT a bluff — it PASSes the real toolchain and
#   FAILs every planted regression of the generator / installer / hook:
#     M0  clean copy                                   -> PASS (golden-FALSE)
#     M1  non-idempotent generator ($RANDOM in body)    -> FAIL
#     M2  generator overwrites hand-made files          -> FAIL
#     M3  --check always exits 0 (blind drift check)    -> FAIL
#     M4  frontmatter effort disagrees with the name    -> FAIL
#     M5  colour outside the supported set (data file)  -> FAIL
#     M6  hook skips the agent-type check               -> FAIL
#     M7  hook ignores AGENT_TYPE_LABEL_ENFORCE         -> FAIL
#     M8  hook also flags specialist/plugin types       -> FAIL
#     M9  hook counts hand-made (unmarked) types        -> FAIL
#     M10 installer prunes hand-made files              -> FAIL
#     M11 generator silently drops the `max` effort     -> FAIL
#     M12 hook forgets the audited bypass reason        -> FAIL
#     R1  reviewer text moved from opus-xhigh to opus-max -> FAIL  (review 2026-11-03 M4)
#     R2  hook drops the cross-track detection             -> FAIL  (review 2026-11-03 M7)
#     R3  hook ignores the call's model/effort parameters  -> FAIL  (F2)
#     R4  hook WARN payload built without JSON escaping    -> FAIL  (F7)
#     R5  installer prunes declared tracks outside filter  -> FAIL  (F4)
#     R6  installer accepts a user-level config dir        -> FAIL  (F1)
#     R7  installer does not resolve symlinks of user config dirs -> FAIL (R2-1)
#     R8  installer allows an out-dir that contains a user config dir -> FAIL (R2-3, ME)
#     R9  installer prunes undeclared files outside the --models filter -> FAIL (R2-3, MA)
#     R10 installer allows a project root equal to / above HOME -> FAIL (R2-3, MF)
#     R11 installer prunes a declared-but-unresolvable track -> FAIL (R2-2)
#     R12 installer prunes with no usable config -> FAIL (R2-2)
#     R13 installer ignores the passwd home when HOME is empty -> FAIL (R2-1)
#     E2  an ambient AGENT_TYPE_LABEL_AGENTS_DIR does not change the verdict (R2-4)
#     E1  an ambient HP in the caller's environment does not change the verdict (F3)
#   plus gate-level cases on the dispatch-log audit (warn vs enforce) and a
#   removed-doc / removed-script case.
# Usage   : bash scripts/gates/cm_agent_type_label_mutation_test.sh
# Side-effects: temp tree under ${TMPDIR:-/tmp}, removed on exit; the real
#   scripts are only READ (copied), never modified.
# Exit    : 0 every case had the expected verdict · 1 otherwise · 2 env error.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONST="$(cd "$HERE/../.." && pwd -P)"
GATE="$HERE/cm_agent_type_label.sh"
[ -f "$GATE" ] || { echo "META: gate missing: $GATE" >&2; exit 2; }
T="$(mktemp -d "${TMPDIR:-/tmp}/cm_atl_mut.XXXXXX")"
trap 'rm -rf "$T"' EXIT
rc=0
note() { echo "$@"; }
expect() { # want(pass|fail) desc cmd...
  local want="$1" desc="$2"; shift 2
  if "$@" >"$T/last.out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then note "OK    $desc (gate ${got}ed as required)"; else note "META FAIL: $desc — gate ${got}ed, wanted $want"; sed 's/^/        | /' "$T/last.out" | tail -8; rc=1; fi
}

fresh_tree() { # name -> $T/name/scripts/{multitrack,hooks,gates}
  local d="$T/$1"; mkdir -p "$d/scripts/gates" "$d/docs/scripts"
  cp -r "$CONST/scripts/multitrack" "$d/scripts/multitrack"
  cp -r "$CONST/scripts/hooks" "$d/scripts/hooks"
  cp "$GATE" "$d/scripts/gates/"
  cp "$CONST/docs/scripts/gen_agent_label_defs.md" "$CONST/docs/scripts/install_agent_label_defs.md" "$CONST/docs/scripts/guard-track-branch-label.md" "$d/docs/scripts/" 2>/dev/null
  echo "$d"
}
gate_in() { # tree -> runs the gate copy living inside that tree
  bash "$1/scripts/gates/cm_agent_type_label.sh" --quiet
}
mutate() { # tree file python-snippet-old python-snippet-new
  python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import sys
path, old, new = sys.argv[2], sys.argv[3].encode().decode('unicode_escape'), sys.argv[4].encode().decode('unicode_escape')
s = open(path).read()
if old not in s:
    sys.stderr.write("MUTANT-NOT-APPLIED: %r not found in %s\n" % (old, path)); sys.exit(3)
open(path, "w").write(s.replace(old, new, 1))
PY
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-AGENT-TYPE-LABEL"

D=$(fresh_tree m0);  expect pass "M0 clean copy of the real toolchain" gate_in "$D"

D=$(fresh_tree m1); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '  hash="$({' '  body="$body #$RANDOM"\n  hash="$({' || rc=1
expect fail "M1 non-idempotent generator" gate_in "$D"

D=$(fresh_tree m2); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" 'if [ "$nhand" -gt 0 ] || [ "$nedit" -gt 0 ]; then' 'if false; then' || rc=1
expect fail "M2 generator overwrites hand-made files" gate_in "$D"

D=$(fresh_tree m3); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '[ "$ndrift" -eq 0 ] && exit 0 || exit 1' 'exit 0' || rc=1
expect fail "M3 --check is blind to drift" gate_in "$D"

D=$(fresh_tree m4); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '"$m" "$e" "$color")"' '"$m" "medium" "$color")"' || rc=1
expect fail "M4 frontmatter effort disagrees with the type name" gate_in "$D"

D=$(fresh_tree m5); sed -i 's/^1\tblue$/1\tmagenta/;s/^\*\tyellow$/*\tmagenta/' "$D/scripts/multitrack/agent_label_colors.tsv"
expect fail "M5 colour outside the supported set" gate_in "$D"

D=$(fresh_tree m6); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '    _type_check\n    exit $?' '    exit 0' || rc=1
expect fail "M6 hook skips the agent-type check" gate_in "$D"

D=$(fresh_tree m7); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '"${AGENT_TYPE_LABEL_ENFORCE:-0}" == "1"' '"0" == "1"' || rc=1
expect fail "M7 hook ignores AGENT_TYPE_LABEL_ENFORCE" gate_in "$D"

D=$(fresh_tree m8); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '    *) return 0 ;;\n  esac\n  if [[ -n "${AGENT_TYPE_LABEL_BYPASS' '    *) reason="specialist" ;;\n  esac\n  if [[ -n "${AGENT_TYPE_LABEL_BYPASS' || rc=1
expect fail "M8 hook flags specialist/plugin types" gate_in "$D"

D=$(fresh_tree m9); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" "    grep -q '^<!-- generated-by: gen_agent_label_defs\\\\.sh v1 ' \"\$f\" 2>/dev/null || continue\n" '' || rc=1
expect fail "M9 hook counts hand-made types as generated" gate_in "$D"

D=$(fresh_tree m10); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '      genuine)\n' '      genuine|handmade)\n' || rc=1
expect fail "M10 installer prunes hand-made files" gate_in "$D"

D=$(fresh_tree m11); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '  for e in "${EFFORT_LIST[@]}"; do\n    f=' '  for e in "${EFFORT_LIST[@]}"; do\n    [ "$e" = max ] && continue\n    f=' || rc=1
expect fail "M11 generator silently drops the max effort" gate_in "$D"

D=$(fresh_tree m12); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '  if [[ -n "${AGENT_TYPE_LABEL_BYPASS:-}" ]]; then' '  if [[ -n "${AGENT_TYPE_LABEL_BYPASS+x}" ]]; then' || rc=1
expect fail "M12 empty bypass reason bypasses" gate_in "$D"

D=$(fresh_tree r1); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" 'if [ "$m" = opus ] && [ "$e" = xhigh ]; then' 'if [ "$m" = opus ] && [ "$e" = max ]; then' || rc=1
expect fail "R1 reviewer-substrate body moved from opus-xhigh to opus-max" gate_in "$D"

D=$(fresh_tree r2); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '      if [[ "$nmatch" != "$ltrack" ]]; then' '      if false; then' || rc=1
expect fail "R2 hook drops the cross-track detection" gate_in "$D"

D=$(fresh_tree r3); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '        pmodel="$(json_field .tool_input.model)"; peffort="$(json_field .tool_input.effort)"' '        pmodel=""; peffort=""' || rc=1
expect fail "R3 hook ignores the call's model/effort parameters" gate_in "$D"

D=$(fresh_tree r4); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '"$(_json_esc "$msg")"' '"$msg"' || rc=1
expect fail "R4 WARN payload without JSON escaping" gate_in "$D"

D=$(fresh_tree r5); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '    [ -n "${DECLARED[${BASH_REMATCH[1]}]:-}" ] && continue\n' '' || rc=1
mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '    [ -n "${INFILTER[${BASH_REMATCH[2]}-${BASH_REMATCH[3]}]:-}" ] || continue' '    [ -n "${INFILTER[${BASH_REMATCH[2]}-${BASH_REMATCH[3]}]:-}" ] && [ -n "${DECLARED[${BASH_REMATCH[1]}]:-}" ] && continue' || rc=1
expect fail "R5 installer prunes a declared track's files outside the --models filter" gate_in "$D"

D=$(fresh_tree r6); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'refuse6() { echo' 'refuse6() { return 0; echo' || rc=1
expect fail "R6 installer accepts a user-level config dir" gate_in "$D"

D=$(fresh_tree r7); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'add_cfg() { add_uniq USERCFG "$1"; add_uniq USERCFG "$(canon "$1")"; }' 'add_cfg() { add_uniq USERCFG "$1"; }' || rc=1
expect fail "R7 installer does not resolve symlinked user config dirs" gate_in "$D"

D=$(fresh_tree r8); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '  under "$c" "$od_c" && refuse6' '  false && refuse6' || rc=1
expect fail "R8 installer allows an out-dir containing a user config dir" gate_in "$D"

D=$(fresh_tree r9); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '    [ -n "${INFILTER[${BASH_REMATCH[2]}-${BASH_REMATCH[3]}]:-}" ] || continue' '    true' || rc=1
expect fail "R9 installer prunes undeclared files outside the --models filter" gate_in "$D"

D=$(fresh_tree r10); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '  under "$h" "$pr_c" && refuse6' '  false && refuse6' || rc=1
expect fail "R10 installer allows a project root that is / above HOME" gate_in "$D"

D=$(fresh_tree r11); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '    [ -n "${UNRESOLVED[$((10#$tnum))]:-}" ] && continue' '    true' || rc=1
expect fail "R11 installer prunes a declared-but-unresolvable track" gate_in "$D"

D=$(fresh_tree r12); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'if [ "$cfg_ok" -eq 1 ] && [ -d "$out_dir" ]; then' 'if [ -d "$out_dir" ]; then' || rc=1
expect fail "R12 installer prunes with no usable config" gate_in "$D"

# R14: the root is guarded by TWO independent layers (the explicit '[ "$t" = / ]' check and under()'s root-ancestor
# rule, which also makes '/' an ancestor of every system dir); both are removed together, one alone is redundant.
D=$(fresh_tree r14); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '[ "$2" = / ] && return 0; ' '' || rc=1
mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '  [ "$t" = / ] && refuse6' '  false && refuse6' || rc=1
expect fail "R14 the filesystem root is not refused (--out-dir / written)" gate_in "$D"

D=$(fresh_tree r15); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '    under "$t" "$sd" && refuse6' '    false && refuse6' || rc=1
expect fail "R15 system directories are not refused as out-dir" gate_in "$D"

D=$(fresh_tree r16); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '[ "$1" = "$2" ] && return 0; ' '' || rc=1
expect fail "R16 under() loses its equality branch (out-dir equal to a user config dir)" gate_in "$D"

D=$(fresh_tree x3); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '{ [ -e "$c" ] || [ -L "$c" ]; }' '[ -e "$c" ]' || rc=1
expect fail "X3 the ~/.claude-* glob ignores dangling symlinks" gate_in "$D"

D=$(fresh_tree x4); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'UNRESOLVED["$((10#$tn))"]=1' 'UNRESOLVED["$tn"]=1' || rc=1
expect fail "X4 UNRESOLVED keyed by the raw track digits (007 vs 7)" gate_in "$D"

D=$(fresh_tree x5); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'add_uniq HOMES "$(canon "$HOME")"; ' '' || rc=1
expect fail "X5 HOME is not canonicalised" gate_in "$D"

D=$(fresh_tree x7); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" 'if [ "${#HOMES[@]}" -eq 0 ] && [ "$do_check" -eq 0 ]; then' 'if false; then' || rc=1
expect fail "X7 the no-resolvable-home refusal is disabled" gate_in "$D"

D=$(fresh_tree r13); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '[ -n "$pw_home" ] && { add_uniq HOMES "$pw_home"; add_uniq HOMES "$(canon "$pw_home")"; }' 'true' || rc=1
expect fail "R13 installer ignores the passwd home when HOME is empty" gate_in "$D"

D=$(fresh_tree e2); expect pass "E2 ambient AGENT_TYPE_LABEL_AGENTS_DIR does not change the verdict" env AGENT_TYPE_LABEL_AGENTS_DIR=/tmp bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet

D=$(fresh_tree e1); expect pass "E1 ambient HP pointing elsewhere does not change the verdict" env HP="$T/nonexistent-hp" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet

D=$(fresh_tree m13); rm "$D/docs/scripts/gen_agent_label_defs.md"
expect fail "M13 missing generator doc" gate_in "$D"
D=$(fresh_tree m14); rm "$D/scripts/multitrack/install_agent_label_defs.sh"
expect fail "M14 missing installer" gate_in "$D"

# dispatch-log audit (gate-level)
D=$(fresh_tree m0b)
mkdir -p "$T/aud/agents"; bash "$D/scripts/multitrack/gen_agent_label_defs.sh" --track 1 --branch main --out-dir "$T/aud/agents" >/dev/null
printf '%s\n' '{"subagent_type":"general-purpose","description":"(T1/main - claude1 - opus - high) ATM-1 x"}' '{"subagent_type":"Explore","description":"(T1/main - claude1 - sonnet - low) y"}' >"$T/aud/bad.jsonl"
printf '%s\n' '{"subagent_type":"T1-main-sonnet-low","description":"(T1/main - claude1 - sonnet - low) y"}' '{"subagent_type":"plugin-dev:agent-creator","description":"(T1/main - claude1 - sonnet - low) z"}' '{"subagent_type":"general-purpose","description":"(T9/other - claude1 - sonnet - low) no types for T9"}' >"$T/aud/good.jsonl"
expect pass "A1 dispatch-log with a general-purpose dispatch, warn mode -> WARN only" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents"
expect fail "A2 same log, enforce mode -> FAIL" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents" --mode enforce
expect pass "A3 golden-FALSE log (labelled types, specialists, track without types), enforce -> PASS" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/good.jsonl" --agents-dir "$T/aud/agents" --mode enforce
grep -q 'WARN' <(bash "$D/scripts/gates/cm_agent_type_label.sh" --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents" 2>&1) && note "OK    A1b warn mode prints a WARN line" || { note "META FAIL: A1b warn mode prints a WARN line"; rc=1; }
expect fail "A4 unknown mode -> bad arg (nonzero)" bash "$D/scripts/gates/cm_agent_type_label.sh" --mode bogus
echo "----------------------------------------------------------------------"
[ "$rc" -eq 0 ] && { echo "META: PASS — CM-AGENT-TYPE-LABEL is not a bluff gate"; exit 0; } || { echo "META: FAIL — see above"; exit 1; }
