#!/usr/bin/env bash
# =============================================================================
# test_guard_agent_type_label.sh — hermetic tests for the §11.4.182 / §11.4.231(F)
#   AGENT-TYPE check of scripts/hooks/guard-track-branch-label.sh.
#
# Purpose : (1) when GENERATED label agent types T<N>-<branch>-<alias>-<model>-
#   <effort> exist for the dispatch label's identity, a catch-all dispatch
#   (subagent_type empty / general-purpose / claude) draws a WARN (exit 0) or a
#   BLOCK under AGENT_TYPE_LABEL_ENFORCE=1; (2) a label type whose track, branch,
#   alias, model or effort disagrees with the dispatch label is flagged; (3) a
#   per-invocation model/effort override, or CLAUDE_CODE_EFFORT_LEVEL, that
#   contradicts the label type is flagged (the type name would lie); (4) the
#   WARN payload is valid JSON for hostile input; specialist/plugin types are
#   never touched; an audited bypass exists.
# Usage   : bash scripts/hooks/test_guard_agent_type_label.sh
# Side-effects: temp dir under ${TMPDIR:-/tmp}, removed on exit.
# Cross-refs: §11.4.182 (8), §11.4.231(F.5), §11.4.201 (golden-FALSE cases),
#   test_guard_track_branch_label.sh (the pre-existing suite stays green).
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HERE/guard-track-branch-label.sh"
GEN="$HERE/../multitrack/gen_agent_label_defs.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/guard_agent_type_test.XXXXXX")"
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s%s\n' "$1" "${2:+ — $2}"; FAIL=$((FAIL+1)); }

LIVE_CFG="/nonexistent/.claude-hooktest"
PROJ="$W/proj"; mkdir -p "$PROJ/.claude/agents"
bash "$GEN" --track 1 --branch main --alias hooktest --out-dir "$PROJ/.claude/agents" --all-types >/dev/null
PROJ2="$W/proj2"; mkdir -p "$PROJ2/.claude/agents"      # generated types for T2 only
bash "$GEN" --track 2 --branch feature/x --alias hooktest --out-dir "$PROJ2/.claude/agents" >/dev/null
PROJ0="$W/proj0"; mkdir -p "$PROJ0/.claude/agents"      # none
PROJH="$W/projh"; mkdir -p "$PROJH/.claude/agents"      # hand-made T1 type only
printf -- '---\nname: T1-main-hooktest-sonnet-medium\ndescription: "hand"\nmodel: sonnet\neffort: medium\ncolor: blue\n---\nH\n' >"$PROJH/.claude/agents/T1-main-hooktest-sonnet-medium.md"
PROJZ="$W/projz"; mkdir -p "$PROJZ/.claude/agents"      # generated T1 types of alias 'hooktest-zz' only (a prefix-extension of hooktest)
bash "$GEN" --track 1 --branch main --alias hooktest-zz --out-dir "$PROJZ/.claude/agents" >/dev/null
PROJS="$W/projs"; mkdir -p "$PROJS/.claude/agents"      # generated T1 types of a STALE alias only
bash "$GEN" --track 1 --branch main --alias oldalias --out-dir "$PROJS/.claude/agents" >/dev/null

# payload <tool> <desc> [subagent_type] [model] [effort]  (built with python json.dumps: hostile-safe)
payload() {
  python3 -I -c 'import json,sys
a=sys.argv[1:]; ti={"description":a[1],"prompt":"p"}
if len(a)>2 and a[2]: ti["subagent_type"]=a[2]
if len(a)>3 and a[3]: ti["model"]=a[3]
if len(a)>4 and a[4]: ti["effort"]=a[4]
print(json.dumps({"tool_name":a[0],"tool_input":ti}))' "$@"
}
# run_case <name> <want-exit> <want-warn:yes|no> <project-dir> <enforce:0|1> <payload> [extra env KEY=VAL...]
run_case() {
  local name="$1" want="$2" warn="$3" dir="$4" enf="$5" pl="$6"; shift 6
  local out="$W/o" err="$W/e" got hasw=no
  if [ "$enf" = 1 ]; then
    printf '%s' "$pl" | env -u CLAUDE_CODE_EFFORT_LEVEL -u CLAUDE_EFFORT -u CLAUDE_CODE_EFFORT -u AGENT_EFFORT -u CMA_EFFORT "$@" CLAUDE_PROJECT_DIR="$dir" CLAUDE_CONFIG_DIR="$LIVE_CFG" AGENT_TYPE_LABEL_ENFORCE=1 bash "$HOOK" >"$out" 2>"$err"; got=$?
  else
    printf '%s' "$pl" | env -u CLAUDE_CODE_EFFORT_LEVEL -u CLAUDE_EFFORT -u CLAUDE_CODE_EFFORT -u AGENT_EFFORT -u CMA_EFFORT -u AGENT_TYPE_LABEL_ENFORCE "$@" CLAUDE_PROJECT_DIR="$dir" CLAUDE_CONFIG_DIR="$LIVE_CFG" bash "$HOOK" >"$out" 2>"$err"; got=$?
  fi
  grep -qi 'agent type\|agent-type' "$out" "$err" && hasw=yes
  if [ "$got" = "$want" ] && [ "$hasw" = "$warn" ]; then ok "$name"; else bad "$name" "exit $got (want $want), warn=$hasw (want $warn) :: $(head -c 240 "$err")"; fi
}
L="(T1/main - hooktest - opus - high) ATM-1 task"
GP="$(payload Agent "$L" general-purpose)"

echo "guard-track-branch-label.sh AGENT-TYPE check test suite"
# --- catch-all dispatches ---------------------------------------------------------------
run_case "U01 general-purpose + matching types exist -> WARN, allow"    0 yes "$PROJ" 0 "$GP"
run_case "U02 same + ENFORCE=1 -> BLOCK"                               2 yes "$PROJ" 1 "$GP"
run_case "U03 subagent_type absent -> WARN, allow"                     0 yes "$PROJ" 0 "$(payload Agent "$L")"
run_case "U03b subagent_type absent + ENFORCE -> BLOCK"                2 yes "$PROJ" 1 "$(payload Agent "$L")"
run_case "U03c catch-all 'claude' -> WARN (AL-7)"                      0 yes "$PROJ" 0 "$(payload Agent "$L" claude)"
run_case "U03d catch-all 'claude' + ENFORCE -> BLOCK (AL-7)"           2 yes "$PROJ" 1 "$(payload Agent "$L" claude)"
run_case "U03e custom catch-all list honoured"                        2 yes "$PROJ" 1 "$(payload Agent "$L" helper)" AGENT_TYPE_LABEL_CATCHALL="general-purpose claude helper"
# --- label type consistent with the label ------------------------------------------------
run_case "U04 matching label type -> silent allow (enforce)"           0 no  "$PROJ" 1 "$(payload Agent "$L" T1-main-hooktest-opus-high)"
run_case "U04b type model/effort differ from label -> BLOCK (AL-7)"    2 yes "$PROJ" 1 "$(payload Agent "$L" T1-main-hooktest-sonnet-low)"
run_case "U04c type of another branch, same track -> BLOCK (AL-7)"     2 yes "$PROJ" 1 "$(payload Agent "$L" T1-other-hooktest-opus-high)"
run_case "U04d type of another alias -> BLOCK"                         2 yes "$PROJ" 1 "$(payload Agent "$L" T1-main-oldalias-opus-high)"
run_case "U04e label effort '?' with a label type -> BLOCK (AL-7)"     2 yes "$PROJ" 1 "$(payload Agent "(T1/main - hooktest - opus - ?) x" T1-main-hooktest-opus-high)"
run_case "U04f label type mismatch, warn mode -> WARN, allow"          0 yes "$PROJ" 0 "$(payload Agent "$L" T1-main-hooktest-sonnet-low)"
run_case "U04g legacy 3-field label (no model/effort) -> silent"       0 no  "$PROJ" 1 "$(payload Agent "(T1/main - hooktest) x" T1-main-hooktest-opus-high)"
run_case "U20 exact match: type of alias 'hooktest-zz' under label alias 'hooktest' -> BLOCK (AL2-4)" 2 yes "$PROJ" 1 "$(payload Agent "(T1/main - hooktest - opus - xhigh) x" T1-main-hooktest-zz-opus-xhigh)"
run_case "U20b exact match: 'hooktest-zz' types are not counted as this label's (stale WARN, never BLOCK)" 0 yes "$PROJZ" 1 "$GP"
run_case "U20c '?' alias label + alias-less round-1 type -> BLOCK under ENFORCE (RV7)" 2 yes "$PROJ" 1 "$(payload Agent "(T1/main - ? - opus - high) x" T1-main-opus-high)"
run_case "U20d '?' alias label + a full alias-bearing type -> silent" 0 no "$PROJ" 1 "$(payload Agent "(T1/main - ? - opus - high) x" T1-main-hooktest-opus-high)"
run_case "U04i label model sonnet with an opus label type, same effort -> BLOCK (HK1)" 2 yes "$PROJ" 1 "$(payload Agent "(T1/main - hooktest - sonnet - high) x" T1-main-hooktest-opus-high)"
run_case "U04j label model '?' with a label type -> BLOCK (HK1)" 2 yes "$PROJ" 1 "$(payload Agent "(T1/main - hooktest - ? - high) x" T1-main-hooktest-opus-high)"
run_case "U04h round-1 name without alias -> BLOCK (stale type)"       2 yes "$PROJ" 1 "$(payload Agent "$L" T1-main-opus-high)"
# --- per-dispatch / env overrides (AL-3) ----------------------------------------------------
run_case "U18 dispatch model+effort override a label type -> WARN"     0 yes "$PROJ" 0 "$(payload Agent "$L" T1-main-hooktest-opus-high sonnet low)"
run_case "U18a same + ENFORCE -> BLOCK"                                2 yes "$PROJ" 1 "$(payload Agent "$L" T1-main-hooktest-opus-high sonnet low)"
run_case "U18b only effort overridden + ENFORCE -> BLOCK"              2 yes "$PROJ" 1 "$(payload Agent "$L" T1-main-hooktest-opus-high "" low)"
run_case "U18c override equal to the type -> silent"                  0 no  "$PROJ" 1 "$(payload Agent "$L" T1-main-hooktest-opus-high opus high)"
run_case "U18d CLAUDE_CODE_EFFORT_LEVEL contradicts type + ENFORCE -> BLOCK" 2 yes "$PROJ" 1 "$(payload Agent "$L" T1-main-hooktest-opus-high)" CLAUDE_CODE_EFFORT_LEVEL=low
run_case "U18e CLAUDE_CODE_EFFORT_LEVEL equal to type -> silent"      0 no  "$PROJ" 1 "$(payload Agent "$L" T1-main-hooktest-opus-high)" CLAUDE_CODE_EFFORT_LEVEL=high
# --- golden-FALSE: never touched ------------------------------------------------------------
run_case "U05a specialist Explore -> never touched (enforce)"          0 no  "$PROJ" 1 "$(payload Agent "$L" Explore)"
run_case "U05b plugin specialist -> never touched (enforce)"           0 no  "$PROJ" 1 "$(payload Agent "$L" plugin-dev:agent-creator)"
run_case "U05c Plan -> never touched (enforce)"                        0 no  "$PROJ" 1 "$(payload Agent "$L" Plan)"
run_case "U06 no generated types at all -> silent allow (enforce)"     0 no  "$PROJ0" 1 "$GP"
run_case "U07 types only for T2, dispatch is T1 -> silent (enforce)"   0 no  "$PROJ2" 1 "$GP"
run_case "U07b dispatch T2 with T2 types -> WARN"                      0 yes "$PROJ2" 0 "$(payload Agent "(T2/feature/x - hooktest - sonnet - medium) SPK-1 t" general-purpose)"
run_case "U07c only STALE-alias T1 types + ENFORCE -> allow + WARN (never block on types that cannot be used)" 0 yes "$PROJS" 1 "$GP"
grep -q 'only for other aliases or stale identities' "$W/e" && ok "U07d WARN text names other aliases' types, not only 'stale' (AL3-3a)" || bad "U07d WARN wording" "$(head -c 200 "$W/e")"
run_case "U10 hand-made (unmarked) T1 type does not count (enforce)"   0 no  "$PROJH" 1 "$GP"
run_case "U11 type track T2 but label T1 -> WARN"                      0 yes "$PROJ" 0 "$(payload Agent "$L" T2-feature-x-hooktest-sonnet-low)"
run_case "U11b same + ENFORCE -> BLOCK"                                2 yes "$PROJ" 1 "$(payload Agent "$L" T2-feature-x-hooktest-sonnet-low)"
run_case "U12 non-agent tool Bash -> untouched"                        0 no  "$PROJ" 1 '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
run_case "U13 TaskCreate has no subagent_type notion -> silent"        0 no  "$PROJ" 1 "$(payload TaskCreate "$L")"
run_case "U13b Task tool general-purpose -> WARN"                      0 yes "$PROJ" 0 "$(payload Task "$L" general-purpose)"
run_case "U09 invalid label still BLOCKS first (format)"               2 no  "$PROJ" 0 "$(payload Agent 'no label here' T1-main-hooktest-opus-high)"
run_case "U14 honest '?' track label -> type check skipped"            0 no  "$PROJ" 1 "$(payload Agent '(T?/main - hooktest) x' general-purpose)"
# --- bypass: audited -------------------------------------------------------------------------
out="$(printf '%s' "$GP" | env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" AGENT_TYPE_LABEL_ENFORCE=1 AGENT_TYPE_LABEL_BYPASS="plugin skill needs general-purpose" bash "$HOOK" 2>&1 >/dev/null)"; got=$?
[ "$got" = 0 ] && ok "U08a ENFORCE + audited bypass -> allow" || bad "U08a ENFORCE + audited bypass -> allow" "exit $got"
printf '%s' "$out" | grep -q 'plugin skill needs general-purpose' && ok "U08b bypass reason is audited to stderr" || bad "U08b bypass reason is audited to stderr"
printf '%s' "$GP" | env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" AGENT_TYPE_LABEL_ENFORCE=1 AGENT_TYPE_LABEL_BYPASS="" bash "$HOOK" >/dev/null 2>&1; got=$?
[ "$got" = 2 ] && ok "U08c EMPTY bypass reason does not bypass" || bad "U08c EMPTY bypass reason does not bypass" "exit $got"
# --- WARN payload: valid JSON naming the matching types; hostile subagent_type stays valid JSON ---
jsok() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["hookSpecificOutput"]["hookEventName"]=="PreToolUse"; assert sys.argv[2] in d["hookSpecificOutput"]["additionalContext"]' "$1" "$2" 2>/dev/null; }
printf '%s' "$GP" | env -u AGENT_TYPE_LABEL_ENFORCE CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" bash "$HOOK" >"$W/js" 2>/dev/null
jsok "$W/js" "T1-main-hooktest-" && ok "U15 WARN emits valid additionalContext JSON naming the matching types" || bad "U15 WARN JSON" "$(head -c 200 "$W/js")"
for hs in $'T2-a\x01b-sonnet-max' $'T1-main-hooktest-\x01-opus-max' 'T2-a"b\c-sonnet-max' 'T1-main-hooktest-"q"-opus-max'; do
  payload Agent "$L" "$hs" | env -u AGENT_TYPE_LABEL_ENFORCE CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" bash "$HOOK" >"$W/js2" 2>/dev/null; got=$?
  if [ "$got" = 0 ] && [ -s "$W/js2" ] && python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$W/js2" 2>/dev/null; then ok "U19 hostile subagent_type keeps stdout valid JSON ($(printf '%q' "$hs"))"; else bad "U19 hostile subagent_type JSON ($(printf '%q' "$hs"))" "exit $got :: $(head -c 160 "$W/js2")"; fi
done
payload Agent "$L" $'T1-main-hooktest-x\ny-opus-high' | env -u AGENT_TYPE_LABEL_ENFORCE CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" bash "$HOOK" >"$W/js3" 2>/dev/null; got=$?
if [ "$got" = 0 ] && { [ ! -s "$W/js3" ] || python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$W/js3" 2>/dev/null; }; then ok "U19b newline in subagent_type: no output or valid JSON"; else bad "U19b newline subagent_type JSON"; fi
# --- without jq the fallback JSON field extraction must still see subagent_type / model / effort --------
if command -v jq >/dev/null 2>&1; then
  mkdir -p "$W/nojq"; for t in bash cat env awk sed grep tr cut head tail basename dirname pwd git ls sort printf python3 sha256sum cmp mktemp rm; do p="$(command -v $t)"; [ -n "$p" ] && ln -sf "$p" "$W/nojq/$t"; done
  printf '%s' "$GP" | env -i PATH="$W/nojq" HOME="$W" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" AGENT_TYPE_LABEL_ENFORCE=1 "$W/nojq/bash" "$HOOK" >/dev/null 2>&1; got=$?
  [ "$got" = 2 ] && ok "U16 no-jq fallback still blocks general-purpose under ENFORCE" || bad "U16 no-jq fallback blocks general-purpose" "exit $got"
  payload Agent "$L" T1-main-hooktest-opus-high sonnet low | env -i PATH="$W/nojq" HOME="$W" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" AGENT_TYPE_LABEL_ENFORCE=1 "$W/nojq/bash" "$HOOK" >/dev/null 2>&1; got=$?
  [ "$got" = 2 ] && ok "U16b no-jq fallback still sees a model/effort override" || bad "U16b no-jq fallback override" "exit $got"
fi
printf '%s' "$(payload Agent 'no label here')" | env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" bash "$HOOK" >/dev/null 2>"$W/fmt"
grep -q "never a block-cause except" "$W/fmt" && ok "U21 format-block message qualifies the '?' effort rule for label agent types (AL2-6b)" || bad "U21 format-block message qualification" "$(grep -i 'block-cause' "$W/fmt")"
bash -n "$HOOK" 2>/dev/null && ok "U17 hook bash -n clean" || bad "U17 hook bash -n clean"

# U99 the guard doc states this suite's real case count (this check included) (AL5-4)
dc="$(grep -o 'test_guard_agent_type_label.sh` ([0-9]* cases' "$(dirname "$HOOK")/../../docs/scripts/guard-track-branch-label.md" | grep -o '[0-9]*' | head -1)"
if [ "$dc" = "$((PASS + FAIL + 1))" ]; then ok "U99 guard doc case count equals the real total"; else bad "U99 guard doc case count equals the real total" "want '$((PASS + FAIL + 1))' got '${dc:-none}'"; fi

echo; echo "  total: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && { echo "  RESULT: PASS"; exit 0; } || { echo "  RESULT: FAIL"; exit 1; }
