#!/usr/bin/env bash
# =============================================================================
# test_guard_agent_type_label.sh — hermetic tests for the §11.4.182 / §11.4.231(F)
#   AGENT-TYPE check added to scripts/hooks/guard-track-branch-label.sh.
#
# Purpose : when GENERATED label agent types (T<N>-<branch>-<model>-<effort>)
#   exist for the dispatch label's track, a dispatch with subagent_type empty or
#   `general-purpose` draws a WARN (exit 0, AGENT_TYPE_LABEL_ENFORCE unset) or a
#   BLOCK (exit 2, AGENT_TYPE_LABEL_ENFORCE=1). Specialist / plugin types and
#   label types are never touched; an explicit audited bypass exists.
# Usage   : bash scripts/hooks/test_guard_agent_type_label.sh
# Side-effects: temp dir under ${TMPDIR:-/tmp}, removed on exit.
# Cross-refs: §11.4.182, §11.4.231(F), §11.4.201 (golden-FALSE cases),
#   test_guard_track_branch_label.sh (the pre-existing 38-case suite stays green).
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
bash "$GEN" --track 1 --branch main --out-dir "$PROJ/.claude/agents" >/dev/null
PROJ2="$W/proj2"; mkdir -p "$PROJ2/.claude/agents"      # generated types for T2 only
bash "$GEN" --track 2 --branch feature/x --out-dir "$PROJ2/.claude/agents" >/dev/null
PROJ0="$W/proj0"; mkdir -p "$PROJ0/.claude/agents"      # none
PROJH="$W/projh"; mkdir -p "$PROJH/.claude/agents"      # hand-made T1 type only
printf -- '---\nname: T1-main-sonnet-medium\ndescription: "hand"\nmodel: sonnet\neffort: medium\ncolor: blue\n---\nH\n' >"$PROJH/.claude/agents/T1-main-sonnet-medium.md"

payload() { # tool desc subagent_type
  if [ -n "${3:-}" ]; then
    printf '{"tool_name":"%s","tool_input":{"description":"%s","subagent_type":"%s","prompt":"p"}}' "$1" "$2" "$3"
  else
    printf '{"tool_name":"%s","tool_input":{"description":"%s","prompt":"p"}}' "$1" "$2"
  fi
}
# run <name> <want-exit> <want-warn:yes|no> <project-dir> <enforce:0|1> <payload> [extra env KEY=VAL...]
run_case() {
  local name="$1" want="$2" warn="$3" dir="$4" enf="$5" pl="$6"; shift 6
  local out err got hasw=no
  out="$W/o.$$"; err="$W/e.$$"
  if [ "$enf" = 1 ]; then
    printf '%s' "$pl" | env "$@" CLAUDE_PROJECT_DIR="$dir" CLAUDE_CONFIG_DIR="$LIVE_CFG" AGENT_TYPE_LABEL_ENFORCE=1 bash "$HOOK" >"$out" 2>"$err"; got=$?
  else
    printf '%s' "$pl" | env "$@" -u AGENT_TYPE_LABEL_ENFORCE CLAUDE_PROJECT_DIR="$dir" CLAUDE_CONFIG_DIR="$LIVE_CFG" bash "$HOOK" >"$out" 2>"$err"; got=$?
  fi
  grep -qi 'agent type\|agent-type' "$out" "$err" && hasw=yes
  if [ "$got" = "$want" ] && [ "$hasw" = "$warn" ]; then ok "$name"; else bad "$name" "exit $got (want $want), warn=$hasw (want $warn)"; fi
}
L="(T1/main - hooktest - opus - high) ATM-1 task"
GP="$(payload Agent "$L" general-purpose)"

echo "guard-track-branch-label.sh AGENT-TYPE check test suite"
run_case "U01 general-purpose + T1 types exist -> WARN, allow"         0 yes "$PROJ" 0 "$GP"
run_case "U02 same + ENFORCE=1 -> BLOCK"                               2 yes "$PROJ" 1 "$GP"
run_case "U03 subagent_type absent -> WARN, allow"                     0 yes "$PROJ" 0 "$(payload Agent "$L")"
run_case "U03b subagent_type absent + ENFORCE -> BLOCK"                2 yes "$PROJ" 1 "$(payload Agent "$L")"
run_case "U04 label type T1-main-sonnet-medium -> silent allow"        0 no  "$PROJ" 1 "$(payload Agent "$L" T1-main-sonnet-medium)"
run_case "U05a specialist Explore -> never touched (enforce)"          0 no  "$PROJ" 1 "$(payload Agent "$L" Explore)"
run_case "U05b plugin specialist -> never touched (enforce)"           0 no  "$PROJ" 1 "$(payload Agent "$L" plugin-dev:agent-creator)"
run_case "U05c Plan -> never touched (enforce)"                        0 no  "$PROJ" 1 "$(payload Agent "$L" Plan)"
run_case "U06 no generated types at all -> silent allow (enforce)"     0 no  "$PROJ0" 1 "$GP"
run_case "U07 types only for T2, dispatch is T1 -> silent (enforce)"   0 no  "$PROJ2" 1 "$GP"
run_case "U07b dispatch T2 with T2 types -> WARN"                      0 yes "$PROJ2" 0 "$(payload Agent "(T2/feature/x - hooktest - sonnet - low) SPK-1 t" general-purpose)"
run_case "U10 hand-made (unmarked) T1 type does not count (enforce)"   0 no  "$PROJH" 1 "$GP"
run_case "U11 type track T2 but label T1 -> WARN"                      0 yes "$PROJ" 0 "$(payload Agent "$L" T2-feature-x-sonnet-low)"
run_case "U11b same + ENFORCE -> BLOCK"                                2 yes "$PROJ" 1 "$(payload Agent "$L" T2-feature-x-sonnet-low)"
run_case "U12 non-agent tool Bash -> untouched"                        0 no  "$PROJ" 1 '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
run_case "U13 TaskCreate has no subagent_type notion -> silent"        0 no  "$PROJ" 1 "$(payload TaskCreate "$L")"
run_case "U13b Task tool general-purpose -> WARN"                      0 yes "$PROJ" 0 "$(payload Task "$L" general-purpose)"
run_case "U09 invalid label still BLOCKS first (format)"               2 no  "$PROJ" 0 "$(payload Agent 'no label here' T1-main-sonnet-medium)"
run_case "U14 honest '?' track label -> type check skipped"            0 no  "$PROJ" 1 "$(payload Agent '(T?/main - hooktest) x' general-purpose)"
# bypass: audited
out="$(printf '%s' "$GP" | env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" AGENT_TYPE_LABEL_ENFORCE=1 AGENT_TYPE_LABEL_BYPASS="plugin skill needs general-purpose" bash "$HOOK" 2>&1 >/dev/null)"; got=$?
[ "$got" = 0 ] && ok "U08a ENFORCE + audited bypass -> allow" || bad "U08a ENFORCE + audited bypass -> allow" "exit $got"
printf '%s' "$out" | grep -q 'plugin skill needs general-purpose' && ok "U08b bypass reason is audited to stderr" || bad "U08b bypass reason is audited to stderr"
printf '%s' "$GP" | env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" AGENT_TYPE_LABEL_ENFORCE=1 AGENT_TYPE_LABEL_BYPASS="" bash "$HOOK" >/dev/null 2>&1; got=$?
[ "$got" = 2 ] && ok "U08c EMPTY bypass reason does not bypass" || bad "U08c EMPTY bypass reason does not bypass" "exit $got"
# warn payload structure: additionalContext JSON on stdout (non-blocking surfacing)
printf '%s' "$GP" | env -u AGENT_TYPE_LABEL_ENFORCE CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" bash "$HOOK" >"$W/js" 2>/dev/null
if python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["hookSpecificOutput"]["hookEventName"]=="PreToolUse"; assert "T1-main-" in d["hookSpecificOutput"]["additionalContext"]' "$W/js" 2>/dev/null; then ok "U15 WARN emits valid additionalContext JSON naming the T1 types"; else bad "U15 WARN emits valid additionalContext JSON" "$(head -c 200 "$W/js")"; fi
# without jq the fallback JSON field extraction must still see subagent_type
if command -v jq >/dev/null 2>&1; then
  mkdir -p "$W/nojq"; for t in bash cat env awk sed grep tr cut head tail basename dirname pwd git ls sort printf python3 sha256sum cmp mktemp rm; do p="$(command -v $t)"; [ -n "$p" ] && ln -sf "$p" "$W/nojq/$t"; done
  printf '%s' "$GP" | env -i PATH="$W/nojq" HOME="$W" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$LIVE_CFG" AGENT_TYPE_LABEL_ENFORCE=1 "$W/nojq/bash" "$HOOK" >/dev/null 2>&1; got=$?
  [ "$got" = 2 ] && ok "U16 no-jq fallback still blocks general-purpose under ENFORCE" || bad "U16 no-jq fallback still blocks general-purpose under ENFORCE" "exit $got"
fi
bash -n "$HOOK" 2>/dev/null && ok "U17 hook bash -n clean" || bad "U17 hook bash -n clean"

echo; echo "  total: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && { echo "  RESULT: PASS"; exit 0; } || { echo "  RESULT: FAIL"; exit 1; }
