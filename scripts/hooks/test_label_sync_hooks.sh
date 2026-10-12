#!/usr/bin/env bash
# scripts/hooks/test_label_sync_hooks.sh
#
# Purpose : Hermetic test suite for the label-sync HOOKS + WIRING stream
#           (§11.4.182 labels, §11.4.208 request ledger, §11.4.228/§11.4.164
#           auto-wiring): the Claude Code hook scripts under
#           scripts/label-sync/hooks/, the alias-switch signal, the claude
#           toolkit wrapper (scripts/label-sync/toolkit/cma_label_hook.sh), the
#           installer (scripts/label-sync/install_label_sync.sh) and its
#           post_update_hook.sh wiring.
# Usage   : bash scripts/hooks/test_label_sync_hooks.sh [--keep] [--fail-fast]
#           --fail-fast  stop at the first FAIL (used by prove_hook_mutations.sh)
#           env LS_TEST_BIN      reuse a prebuilt labelctl/label-busd dir
#           env LS_LATENCY_MS    per-hook median latency bound (default 150)
# Inputs  : the sibling scripts (read-only), a temp HOME + temp LABEL_SYNC_DIR.
# Outputs : one PASS/FAIL line per assertion + a summary.
# Exit    : 0 all assertions passed | 1 at least one failed | 2 environment
#           error (no jq / cannot build the Go binaries). 2 is never a pass.
# Side-effects: everything under one mktemp dir (removed on exit unless
#           --keep). NEVER touches the real $HOME, ~/.claude* or the real state
#           dir: HOME, LABEL_SYNC_DIR, LABEL_SYNC_BIN and CLAUDE_CONFIG_DIR are
#           all re-pointed at the temp dir before any script runs.
# Deps    : bash, jq, git, go (only to build the binaries when LS_TEST_BIN is
#           not set), diff, sha256sum.
# Cross-refs: §11.4.182, §11.4.208, §11.4.228, §11.4.164, §1.1, §11.4.201,
#           docs/label-sync/HOOKS.md, scripts/gates/cm_label_sync_hooks.sh.
# Classification: universal (§11.4.17).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CROOT="$(cd "$HERE/../.." && pwd)"
LS="$CROOT/scripts/label-sync"
HK="$LS/hooks"
INSTALLER="$LS/install_label_sync.sh"
WRAPPER="$LS/toolkit/cma_label_hook.sh"
POSTHOOK="$CROOT/scripts/post_update_hook.sh"
KEEP=""; FAILFAST=""
for _a in "$@"; do case "$_a" in --keep) KEEP=1 ;; --fail-fast) FAILFAST=1 ;; esac; done

command -v jq >/dev/null 2>&1 || { echo "ENV: jq required" >&2; exit 2; }
T="$(mktemp -d "${TMPDIR:-/tmp}/ls_hooks_test.XXXXXX")"
[ -n "$KEEP" ] || trap 'rm -rf "$T"' EXIT

export HOME="$T/home"; mkdir -p "$HOME"
export LABEL_SYNC_DIR="$T/state"
export LABEL_SYNC_BIN="${LS_TEST_BIN:-$T/bin}"
export LABEL_SYNC_LABELER="$CROOT/scripts/multitrack/track_branch_label.sh"
export LABEL_SYNC_NO_BUILD=1          # hooks must never build inline in tests
export LABEL_SYNC_CLAUDE_PID="$$"
unset CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR LABEL_SYNC_DISABLE \
      LABEL_SYNC_REQUEST_LEDGER LABEL_SYNC_HOOK_DEBUG CLAUDE_EFFORT CLAUDE_CODE_EFFORT AGENT_EFFORT CMA_EFFORT

PASS=0; FAIL=0
ok() { # desc rc(0=pass)
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "✅ PASS  $1"
  else FAIL=$((FAIL+1)); echo "❌ FAIL  $1"
    if [ -n "$FAILFAST" ]; then echo "label-sync hooks suite: $PASS passed, $FAIL failed (fail-fast)"; exit 1; fi
  fi
}
check() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
eq()    { [ "$2" = "$3" ]; ok "$1 (got '$2' want '$3')" $?; }

# ---- build the Go binaries once (outside the tests' time budget) ----------
if [ ! -x "$LABEL_SYNC_BIN/labelctl" ]; then
  if ! LABEL_SYNC_NO_BUILD= bash "$LS/labelctl.sh" --build >/dev/null 2>"$T/build.err"; then
    echo "ENV: cannot build label-sync binaries: $(tail -3 "$T/build.err")" >&2; exit 2
  fi
fi
CTL="$LABEL_SYNC_BIN/labelctl"

# ---- fixtures -------------------------------------------------------------
PROJ="$T/proj"; mkdir -p "$PROJ"
git -C "$PROJ" init -q -b main
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
SID="11111111-aaaa-bbbb-cccc-000000000001"
slug="$(printf '%s' "$PROJ" | sed 's/[^A-Za-z0-9]/-/g')"
mk_cfg() { # alias model -> prints config dir; writes a transcript with that model
  local d="$HOME/.claude-$1"; mkdir -p "$d/projects/$slug"
  printf '{"type":"assistant","message":{"model":"%s"}}\n' "$2" >"$d/projects/$slug/$SID.jsonl"
  printf '%s' "$d"
}
CFG1="$(mk_cfg claude1 claude-opus-4-8)"
CFG2="$(mk_cfg claude2 claude-sonnet-5)"
export CLAUDE_CONFIG_DIR="$CFG1"

OUT=""; RC=0; MS=0
run_hook() { # script json [env assignments...]
  local s="$1" j="$2"; shift 2
  local t0 t1
  t0=$(date +%s%N)
  OUT="$(printf '%s' "$j" | env "$@" bash "$HK/$s" 2>"$T/hook.err")"; RC=$?
  t1=$(date +%s%N); MS=$(( (t1 - t0) / 1000000 ))
}
j() { # event extra-json-object
  jq -nc --arg sid "$SID" --arg cwd "$PROJ" --arg ev "$1" --argjson x "${2:-{\}}" \
     '{session_id:$sid,cwd:$cwd,hook_event_name:$ev,transcript_path:"/x"}+$x'
}
ent() { "$CTL" get --id "$1" --json 2>/dev/null; }
field() { ent "$1" | jq -r ".$2 // empty"; }
nstate() { # count of live (non-done) entities of kind
  "$CTL" list --json 2>/dev/null | jq "[.entities[]|select(.kind==\"$1\" and .state!=\"done\")]|length"
}

# =========================================================================
echo "== 0. the scripts under test exist (RED until implemented) =="
for f in label-sync-lib.sh label-sync-session-start.sh label-sync-prompt.sh label-sync-agent-register.sh \
         label-sync-subagent-start.sh label-sync-subagent-stop.sh label-sync-stop.sh label-sync-session-end.sh \
         label-sync-model-switch.sh label-sync-alias-switch.sh request_history_append.sh; do
  check "hook script present: $f" test -f "$HK/$f"
done
check "installer present" test -x "$INSTALLER"
check "toolkit wrapper present" test -f "$WRAPPER"

# =========================================================================
echo "== 1. SessionStart registers the session entity =="
run_hook label-sync-session-start.sh "$(j SessionStart '{"source":"startup"}')"
eq "session-start exit 0" "$RC" 0
SE="session:$SID"
eq "session entity kind" "$(field "$SE" kind)" session
eq "session entity session_id" "$(field "$SE" session_id)" "$SID"
eq "session label (alias+model derived from env/transcript)" "$(field "$SE" label)" "(T1/main - claude1 - opus - ?)"
eq "session pid recorded" "$(field "$SE" pid)" "$$"
eq "session state running" "$(field "$SE" state)" running
check "SessionStart output is empty or valid JSON" bash -c "[ -z '$OUT' ] || printf '%s' '$OUT' | jq -e . >/dev/null"

# =========================================================================
echo "== 2. UserPromptSubmit: heartbeat + additionalContext + ledger exactly once =="
LEDGER="$T/ledger/history.jsonl"; mkdir -p "$T/ledger"
export LABEL_SYNC_REQUEST_LEDGER="$LEDGER"
before="$(field "$SE" updated_at)"; sleep 1.1
run_hook label-sync-prompt.sh "$(j UserPromptSubmit '{"prompt":"first request: do X"}')"
eq "prompt exit 0" "$RC" 0
after="$(field "$SE" updated_at)"
[ "$before" != "$after" ]; ok "heartbeat advanced updated_at ($before -> $after)" $?
ctx="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
case "$ctx" in *"(T1/main - claude1 - opus - ?)"*) r=0 ;; *) r=1 ;; esac
ok "additionalContext carries the live label (got: ${ctx:0:120})" $r
eq "additionalContext hookEventName" "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" UserPromptSubmit
eq "ledger has exactly 1 row after 1 prompt" "$(wc -l <"$LEDGER" 2>/dev/null | tr -d ' ')" 1
eq "ledger row: prompt content" "$(head -n1 "$LEDGER" | jq -r .prompt 2>/dev/null)" "first request: do X"
eq "ledger row: alias" "$(head -n1 "$LEDGER" | jq -r .alias 2>/dev/null)" claude1
eq "ledger row: model" "$(head -n1 "$LEDGER" | jq -r .model 2>/dev/null)" opus
eq "ledger row: track" "$(head -n1 "$LEDGER" | jq -r .track 2>/dev/null)" 1
eq "ledger row: effort unknown is literal UNKNOWN (never invented)" "$(head -n1 "$LEDGER" | jq -r .effort 2>/dev/null)" UNKNOWN
check "ledger row carries an explicit timezone stamp" bash -c "head -n1 '$LEDGER' | jq -e '.accepted|test(\"[+-][0-9]{4}\$|Z\$\")' >/dev/null"
# double-fire of the SAME event (hook registered twice) must NOT double-count
run_hook label-sync-prompt.sh "$(j UserPromptSubmit '{"prompt":"first request: do X"}')"
eq "duplicate delivery of the same prompt within the dedupe window is NOT re-appended" "$(wc -l <"$LEDGER" | tr -d ' ')" 1
run_hook label-sync-prompt.sh "$(j UserPromptSubmit '{"prompt":"second, different request"}')"
eq "a different prompt appends exactly one more row" "$(wc -l <"$LEDGER" | tr -d ' ')" 2
sleep 2.2
run_hook label-sync-prompt.sh "$(j UserPromptSubmit '{"prompt":"second, different request"}')"
eq "the same text re-submitted AFTER the window is a new prompt (counted)" "$(wc -l <"$LEDGER" | tr -d ' ')" 3
# multiline / quote-bearing prompt survives JSON round trip
P=$'line1 "quoted"\nline2 \\ back'
run_hook label-sync-prompt.sh "$(j UserPromptSubmit "$(jq -nc --arg p "$P" '{prompt:$p}')")"
eq "multiline prompt stored verbatim" "$(tail -n1 "$LEDGER" | jq -r .prompt)" "$P"
unset LABEL_SYNC_REQUEST_LEDGER
# no ledger configured and no docs/requests dir => no ledger file invented
run_hook label-sync-prompt.sh "$(j UserPromptSubmit '{"prompt":"zzz"}')" CLAUDE_PROJECT_DIR="$T/none"
check "no ledger path invented when the project has no docs/requests dir" test ! -e "$T/none/docs/requests/history.jsonl"
mkdir -p "$T/withreq/docs/requests"
run_hook label-sync-prompt.sh "$(j UserPromptSubmit '{"prompt":"zzz"}')" CLAUDE_PROJECT_DIR="$T/withreq"
check "project with docs/requests gets history.jsonl by default" test -s "$T/withreq/docs/requests/history.jsonl"
export LABEL_SYNC_REQUEST_LEDGER="$LEDGER"

# =========================================================================
echo "== 3. PreToolUse Agent|Task registers the subagent; non-agent tools ignored =="
TU="toolu_01AAA"
LBL='(T1/main - claude1 - opus - high) ATM-312 implement the thing'
run_hook label-sync-agent-register.sh "$(j PreToolUse "$(jq -nc --arg t "$TU" --arg d "$LBL" '{tool_name:"Agent",tool_use_id:$t,tool_input:{description:$d,subagent_type:"general-purpose"}}')")"
eq "agent-register exit 0 (never blocks)" "$RC" 0
check "agent-register prints nothing (no noise)" test -z "$OUT"
SA="subagent:$TU"
eq "subagent registered kind" "$(field "$SA" kind)" subagent
eq "subagent parent is the session" "$(field "$SA" parent_id)" "$SE"
eq "subagent label parsed from the description" "$(field "$SA" label)" "(T1/main - claude1 - opus - high)"
run_hook label-sync-agent-register.sh "$(j PreToolUse '{"tool_name":"Bash","tool_use_id":"toolu_bash","tool_input":{"command":"ls"}}')"
eq "non-agent tool: exit 0" "$RC" 0
check "non-agent tool registers nothing" bash -c "! '$CTL' get --id subagent:toolu_bash >/dev/null 2>&1"
run_hook label-sync-agent-register.sh "$(j PreToolUse '{"tool_name":"Agent","tool_use_id":"toolu_nolabel","tool_input":{"description":"no label here"}}')"
eq "unlabelled dispatch: exit 0 (the guard blocks, we never do)" "$RC" 0
check "unlabelled dispatch registers nothing (guard will block it; no phantom)" bash -c "! '$CTL' get --id subagent:toolu_nolabel >/dev/null 2>&1"
run_hook label-sync-agent-register.sh "$(j PreToolUse '{"tool_name":"Task","tool_use_id":"toolu_wrongalias","tool_input":{"description":"(T1/main - claude9 - opus - high) stale alias"}}')"
check "stale-alias dispatch registers nothing (guard blocks it; no phantom)" bash -c "! '$CTL' get --id subagent:toolu_wrongalias >/dev/null 2>&1"
# SubagentStart adopts the pending registration; SubagentStop unregisters it
run_hook label-sync-subagent-start.sh "$(j SubagentStart '{"agent_id":"agent-777","agent_type":"general-purpose"}')"
eq "subagent-start exit 0" "$RC" 0
eq "subagent still running after SubagentStart" "$(field "$SA" state)" running
run_hook label-sync-subagent-stop.sh "$(j SubagentStop '{"agent_id":"agent-777","agent_type":"general-purpose"}')"
eq "subagent-stop exit 0" "$RC" 0
eq "SubagentStop marks the correlated subagent done" "$(field "$SA" state)" done

# =========================================================================
echo "== 4. Stop / SessionEnd =="
run_hook label-sync-agent-register.sh "$(j PreToolUse '{"tool_name":"Agent","tool_use_id":"toolu_02BBB","tool_input":{"description":"(T1/main - claude1 - opus - ?) second"}}')"
eq "second subagent running" "$(field subagent:toolu_02BBB state)" running
run_hook label-sync-stop.sh "$(j Stop '{}')"
eq "Stop exit 0" "$RC" 0
eq "Stop marks the session idle" "$(field "$SE" state)" idle
eq "Stop reaps an UNADOPTED pending subagent (denied/never-started => no phantom)" "$(field subagent:toolu_02BBB state)" done
run_hook label-sync-prompt.sh "$(j UserPromptSubmit '{"prompt":"after stop"}')"
eq "next prompt revives the idle session to running" "$(field "$SE" state)" running
run_hook label-sync-agent-register.sh "$(j PreToolUse '{"tool_name":"Agent","tool_use_id":"toolu_03CCC","tool_input":{"description":"(T1/main - claude1 - opus - ?) third"}}')"
run_hook label-sync-session-end.sh "$(j SessionEnd '{"reason":"other"}')"
eq "SessionEnd exit 0" "$RC" 0
eq "SessionEnd marks the session done" "$(field "$SE" state)" done
eq "SessionEnd marks remaining subagents of the session done" "$(field subagent:toolu_03CCC state)" done
check "verify still OK after the whole lifecycle" "$CTL" verify

# =========================================================================
echo "== 5. alias switch signal =="
"$CTL" switch-alias --alias claude1 --model opus --effort high >/dev/null
"$CTL" register --id follower --kind agent --track 1 --branch main --pid $$ >/dev/null
bash "$HK/label-sync-alias-switch.sh" claude2 --model sonnet --effort xhigh >"$T/sw.out" 2>&1; swrc=$?
eq "alias-switch exit 0" "$swrc" 0
eq "alias-switch relabels followers immediately" "$("$CTL" label follower)" "(T1/main - claude2 - sonnet - xhigh)"
bash "$HK/label-sync-alias-switch.sh" >/dev/null 2>&1; eq "alias-switch with no alias is a usage error (exit 2)" "$?" 2
bash "$HK/label-sync-alias-switch.sh" claude3 --bogus >/dev/null 2>&1; eq "alias-switch rejects unknown flag (exit 2)" "$?" 2

# =========================================================================
echo "== 6. RESUMED under a DIFFERENT alias republishes the subtree =="
rm -rf "$LABEL_SYNC_DIR"
SID="22222222-aaaa-bbbb-cccc-000000000002"
CFG1="$(mk_cfg claude1 claude-opus-4-8)"; CFG2="$(mk_cfg claude2 claude-sonnet-5)"
export CLAUDE_CONFIG_DIR="$CFG1"; SE="session:$SID"
"$CTL" switch-alias --alias claude1 --model opus --effort high >/dev/null
run_hook label-sync-session-start.sh "$(j SessionStart '{"source":"startup"}')"
run_hook label-sync-agent-register.sh "$(j PreToolUse '{"tool_name":"Agent","tool_use_id":"toolu_R1","tool_input":{"description":"(T1/main - claude1 - opus - ?) child"}}')"
eq "before resume: session follows claude1" "$(field "$SE" label)" "(T1/main - claude1 - opus - high)"
eq "before resume: subagent shows claude1" "$(field subagent:toolu_R1 alias)" claude1
export CLAUDE_CONFIG_DIR="$CFG2"
run_hook label-sync-session-start.sh "$(j SessionStart '{"source":"resume"}')"
eq "resume exit 0" "$RC" 0
eq "after resume under claude2: session label shows claude2" "$(field "$SE" alias)" claude2
eq "after resume: subagent subtree republished to claude2" "$(field subagent:toolu_R1 alias)" claude2
eq "after resume: active alias published as claude2 (alias_switch)" "$(jq -r .alias "$LABEL_SYNC_DIR/active.json")" claude2
"$CTL" switch-alias --alias claude3 --model haiku --effort low >/dev/null
eq "after resume + later operator switch: session FOLLOWS (label updates)" "$(field "$SE" alias)" claude3
eq "after resume + later operator switch: subagent FOLLOWS" "$(field subagent:toolu_R1 alias)" claude3
# variant: publish only the subtree (no global switch)
rm -rf "$LABEL_SYNC_DIR"; export CLAUDE_CONFIG_DIR="$CFG1"
"$CTL" switch-alias --alias claude1 --model opus --effort high >/dev/null
run_hook label-sync-session-start.sh "$(j SessionStart '{"source":"startup"}')"
run_hook label-sync-agent-register.sh "$(j PreToolUse '{"tool_name":"Agent","tool_use_id":"toolu_R2","tool_input":{"description":"(T1/main - claude1 - opus - ?) child"}}')"
export CLAUDE_CONFIG_DIR="$CFG2"
run_hook label-sync-session-start.sh "$(j SessionStart '{"source":"resume"}')" LABEL_SYNC_NO_SWITCH_ON_RESUME=1
eq "no-switch variant: active alias untouched" "$(jq -r .alias "$LABEL_SYNC_DIR/active.json")" claude1
eq "no-switch variant: session pinned to its own alias claude2" "$(field "$SE" alias)" claude2
eq "no-switch variant: subtree republished to claude2" "$(field subagent:toolu_R2 alias)" claude2
"$CTL" switch-alias --alias claude4 >/dev/null
eq "no-switch variant: pinned subtree does NOT follow a later switch" "$(field subagent:toolu_R2 alias)" claude2
# same-alias resume: no republish churn
rm -rf "$LABEL_SYNC_DIR"; export CLAUDE_CONFIG_DIR="$CFG1"
"$CTL" switch-alias --alias claude1 >/dev/null
run_hook label-sync-session-start.sh "$(j SessionStart '{"source":"startup"}')"
s1="$(cat "$LABEL_SYNC_DIR/seq")"
run_hook label-sync-session-start.sh "$(j SessionStart '{"source":"resume"}')"
eq "resume under the SAME alias does not switch the active alias" "$(jq -r .alias "$LABEL_SYNC_DIR/active.json")" claude1
check "same-alias resume leaves exactly one session entity" bash -c "[ \"\$('$CTL' list --json | jq '[.entities[]|select(.kind==\"session\")]|length')\" = 1 ]"


echo "== 6b. active alias without a model is filled from the live session (never overwritten) =="
rm -rf "$LABEL_SYNC_DIR"; export CLAUDE_CONFIG_DIR="$CFG1"
"$CTL" switch-alias --alias claude1 >/dev/null
run_hook label-sync-session-start.sh "$(j SessionStart '{"source":"startup"}')"
eq "empty active model filled from the live session transcript" "$(jq -r .model "$LABEL_SYNC_DIR/active.json")" opus
"$CTL" switch-alias --alias claude1 --model haiku --effort low >/dev/null
run_hook label-sync-session-start.sh "$(j SessionStart '{"source":"clear"}')"
eq "an explicit operator model is NEVER overwritten" "$(jq -r .model "$LABEL_SYNC_DIR/active.json")" haiku

echo "== 6c. markdown twin of the ledger (opt-in via marker) =="
MDD="$T/mdproj/docs/requests"; mkdir -p "$MDD"
printf '# history\n<!-- label-sync:request-history:insert -->\n## older\n' >"$MDD/history.md"
export CLAUDE_CONFIG_DIR="$CFG1"
run_hook label-sync-prompt.sh "$(j UserPromptSubmit '{"prompt":"md twin probe"}')" CLAUDE_PROJECT_DIR="$T/mdproj" LABEL_SYNC_REQUEST_LEDGER=
check "md twin: block inserted right after the marker (newest first)" bash -c "awk '/insert -->/{f=1;next} f&&/md twin probe/{ok=1} f&&/## older/{exit} END{exit !ok}' '$MDD/history.md'"
check "md twin: prior content preserved" grep -q '^## older' "$MDD/history.md"
check "md twin: jsonl row also written" test -s "$MDD/history.jsonl"

# =========================================================================
echo "== 7. fail-soft: hooks exit 0 and print nothing when the bus/state/binary is unusable =="
export CLAUDE_CONFIG_DIR="$CFG1"
for scr in session-start prompt agent-register subagent-start subagent-stop stop session-end model-switch; do
  PAY="$(j X '{"prompt":"p","tool_name":"Agent","tool_use_id":"t","tool_input":{"description":"(T1/main - claude1 - opus - ?) d"},"agent_id":"a","to_model":"claude-opus-4-8"}')"
  # (a) daemon never started: normal operation above; (b) state dir is a file
  : >"$T/notadir"
  run_hook "label-sync-$scr.sh" "$PAY" LABEL_SYNC_DIR="$T/notadir/sub"
  [ "$RC" -eq 0 ] && [ -z "$OUT" ]; ok "$scr: state dir unusable => exit 0, silent (rc=$RC out='${OUT:0:40}')" $?
  # (c) binary missing + no build allowed
  mkdir -p "$T/emptybin"
  run_hook "label-sync-$scr.sh" "$PAY" LABEL_SYNC_BIN="$T/emptybin"
  [ "$RC" -eq 0 ] && [ -z "$OUT" ]; ok "$scr: binary missing => exit 0, silent (rc=$RC)" $?
  # (d) garbage payload
  run_hook "label-sync-$scr.sh" 'not json at all {{{'
  [ "$RC" -eq 0 ] && [ -z "$OUT" ]; ok "$scr: garbage stdin => exit 0, silent (rc=$RC)" $?
  # (e) empty stdin
  run_hook "label-sync-$scr.sh" ''
  [ "$RC" -eq 0 ]; ok "$scr: empty stdin => exit 0 (rc=$RC)" $?
  # (f) kill switch
  run_hook "label-sync-$scr.sh" "$PAY" LABEL_SYNC_DISABLE=1
  [ "$RC" -eq 0 ] && [ -z "$OUT" ]; ok "$scr: LABEL_SYNC_DISABLE=1 => exit 0, silent" $?
done
# NOTE: label-busd is deliberately never started in this suite: "bus down" is the normal case
# for every assertion above, which proves the hooks have no daemon/socket dependence.

# =========================================================================
echo "== 8. latency bound (median of 5 per hook; bound ${LS_LATENCY_MS:-150} ms) =="
rm -rf "$LABEL_SYNC_DIR"; mkdir -p "$T/ledger2"; export LABEL_SYNC_REQUEST_LEDGER="$T/ledger2/h.jsonl"
SID="33333333-aaaa-bbbb-cccc-000000000003"; CFG1="$(mk_cfg claude1 claude-opus-4-8)"; export CLAUDE_CONFIG_DIR="$CFG1"
lat() { # script json
  local s="$1" js="$2" i; local -a v=()
  for i in 1 2 3 4 5; do run_hook "$s" "$(printf '%s' "$js" | sed "s/@@N@@/$i/g")"; v+=("$MS"); done
  printf '%s\n' "${v[@]}" | sort -n | sed -n 3p
}
declare -A LAT
LAT[session-start]="$(lat label-sync-session-start.sh "$(j SessionStart '{"source":"startup"}')")"
LAT[prompt]="$(lat label-sync-prompt.sh "$(j UserPromptSubmit '{"prompt":"latency probe @@N@@"}')")"
LAT[agent-register]="$(lat label-sync-agent-register.sh "$(j PreToolUse '{"tool_name":"Agent","tool_use_id":"toolu_lat@@N@@","tool_input":{"description":"(T1/main - claude1 - opus - ?) lat"}}')")"
LAT[subagent-stop]="$(lat label-sync-subagent-stop.sh "$(j SubagentStop '{"agent_id":"nope@@N@@"}')")"
LAT[stop]="$(lat label-sync-stop.sh "$(j Stop '{}')")"
for k in "${!LAT[@]}"; do
  [ "${LAT[$k]}" -lt "${LS_LATENCY_MS:-150}" ]; ok "latency $k median ${LAT[$k]} ms < ${LS_LATENCY_MS:-150} ms" $?
done

# =========================================================================
echo "== 9. toolkit wrapper (cma_label_hook.sh) =="
rm -rf "$LABEL_SYNC_DIR"
mkdir -p "$HOME/.local/share/claude-multi-account/providers"
printf "CMA_PROVIDER_MODEL='deepseek-v4-pro'\nCMA_API_KEY='{canary_must_not_leak}'\n" >"$HOME/.local/share/claude-multi-account/providers/deepseek.env"
cat >"$T/wrap_test.sh" <<'EOS'
set -u
CALLS="$1"; : >"$CALLS"
cma_run()          { echo "run:${CLAUDE_CONFIG_DIR:-}:$*" >>"$CALLS"; return "${FAKE_RC:-0}"; }
cma_run_provider() { echo "prov:$*" >>"$CALLS"; return "${FAKE_RC:-0}"; }
source "$WRAPPER"; source "$WRAPPER"      # double-source MUST be idempotent
CLAUDE_CONFIG_DIR="$HOME/.claude-claude2" cma_run --resume abc; echo "rc=$?" >>"$CALLS"
echo "active1:$(jq -r .alias "$LABEL_SYNC_DIR/active.json")" >>"$CALLS"
FAKE_RC=7 cma_run_provider deepseek --force -p hi; echo "rc=$?" >>"$CALLS"
echo "active2:$(jq -r '.alias+":"+.model' "$LABEL_SYNC_DIR/active.json")" >>"$CALLS"
EOS
WRAPPER="$WRAPPER" bash "$T/wrap_test.sh" "$T/calls.txt" >"$T/wrap.out" 2>&1
check "wrapper sources cleanly" test -f "$WRAPPER"
eq "wrapper: native launch reached the real cma_run exactly once" "$(grep -c '^run:' "$T/calls.txt")" 1
eq "wrapper: args forwarded unchanged" "$(grep '^run:' "$T/calls.txt")" "run:$HOME/.claude-claude2:--resume abc"
eq "wrapper: native launch published alias_switch (active alias) BEFORE the real launcher ran" "$(grep '^active1:' "$T/calls.txt")" "active1:claude2"
eq "wrapper: provider launch published provider alias + REAL model from the registry" "$(grep '^active2:' "$T/calls.txt")" "active2:deepseek:deepseek-v4-pro"
eq "wrapper: provider launch reached the real cma_run_provider exactly once" "$(grep -c '^prov:' "$T/calls.txt")" 1
eq "wrapper: provider exit status propagated" "$(grep '^rc=' "$T/calls.txt" | tail -n1)" "rc=7"
check "wrapper never reads/prints the provider API key" bash -c "! grep -rq '{canary_must_not_leak}' '$T/wrap.out' '$T/calls.txt' '$LABEL_SYNC_DIR'"
# switch ordering: the native launch happened first and published claude2
WRAPPER="$WRAPPER" bash -c '
  set -u; cma_run(){ return 0; }; cma_run_provider(){ return 0; }; source "$WRAPPER"
  CLAUDE_CONFIG_DIR="$HOME/.claude-claude2" cma_run; jq -r .alias "$LABEL_SYNC_DIR/active.json"' >"$T/o2" 2>&1
eq "wrapper: native launch under .claude-claude2 sets active alias claude2" "$(tail -n1 "$T/o2")" claude2
# tooling absent => launch must still happen
WRAPPER="$WRAPPER" LABEL_SYNC_BIN="$T/emptybin" LABEL_SYNC_DISABLE=1 bash -c '
  set -u; cma_run(){ echo launched; return 3; }; source "$WRAPPER"; CLAUDE_CONFIG_DIR="$HOME/.claude-claude2" cma_run; echo "rc=$?"' >"$T/o3" 2>&1
check "wrapper: label tooling disabled/absent never blocks the launch" grep -q '^launched$' "$T/o3"
eq "wrapper: launch exit status preserved when tooling is absent" "$(tail -n1 "$T/o3")" "rc=3"

# =========================================================================
echo "== 10. installer =="
S="$T/inst"; mkdir -p "$S"
SETT="$S/.claude/settings.json"
mkdir -p "$S/.claude"
cat >"$SETT" <<'EOJ'
{
  "env": {"FOO": "bar"},
  "permissions": {"allow": ["Bash(ls:*)"]},
  "hooks": {
    "PreToolUse": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "bash /opt/guard.sh"}]},
      {"matcher": "Agent|Task", "hooks": [{"type": "command", "command": "bash /opt/other-agent-hook.sh"}]}
    ],
    "Stop": [ {"hooks": [{"type": "command", "command": "echo stop-user-hook"}]} ]
  }
}
EOJ
# the renderer belongs to another stream: use the --render-path override pointing at a fixture
FIXREND="$T/fixture/render/statusline.sh"; mkdir -p "$(dirname "$FIXREND")"; printf '#!/usr/bin/env bash\necho x\n' >"$FIXREND"; chmod +x "$FIXREND"
mkdir -p "$S/submodules"; ln -s "$CROOT" "$S/submodules/constitution"
cp "$FIXREND" "$S/rendfix-statusline.sh"
IA=(bash "$INSTALLER" --project-root "$S" --constitution-root "$S/submodules/constitution" --render-path "$S/rendfix-statusline.sh")
sha0="$(sha256sum "$SETT" | cut -d' ' -f1)"
"${IA[@]}" >"$T/dry.out" 2>&1; rc=$?
eq "dry-run (default) exit 0" "$rc" 0
eq "dry-run writes NOTHING (settings byte-identical)" "$(sha256sum "$SETT" | cut -d' ' -f1)" "$sha0"
check "dry-run left no backup file" bash -c "! ls '$S/.claude/'*.bak* >/dev/null 2>&1"
check "dry-run prints a unified diff" grep -q '^+++ ' "$T/dry.out"
check "dry-run diff mentions our SessionStart hook" grep -q 'label-sync-session-start.sh' "$T/dry.out"
"${IA[@]}" --dry-run >/dev/null 2>&1; eq "explicit --dry-run exit 0" "$?" 0
check "explicit --dry-run still writes nothing" test "$(sha256sum "$SETT" | cut -d' ' -f1)" = "$sha0"
"${IA[@]}" --apply >"$T/apply1.out" 2>&1; rc=$?
eq "apply exit 0" "$rc" 0
check "apply produced valid JSON" jq -e . "$SETT"
check "apply made a backup of the previous settings" bash -c "ls '$S/.claude/'settings.json.label-sync.bak.* >/dev/null 2>&1"
eq "unrelated key env preserved" "$(jq -c .env "$SETT")" '{"FOO":"bar"}'
eq "unrelated key permissions preserved" "$(jq -c .permissions "$SETT")" '{"allow":["Bash(ls:*)"]}'
check "unrelated PreToolUse * guard hook preserved" bash -c "jq -e '[.hooks.PreToolUse[].hooks[].command]|index(\"bash /opt/guard.sh\")' '$SETT' >/dev/null"
check "unrelated Agent|Task hook preserved" bash -c "jq -e '[.hooks.PreToolUse[].hooks[].command]|index(\"bash /opt/other-agent-hook.sh\")' '$SETT' >/dev/null"
check "unrelated Stop user hook preserved" bash -c "jq -e '[.hooks.Stop[].hooks[].command]|index(\"echo stop-user-hook\")' '$SETT' >/dev/null"
for ev in SessionStart UserPromptSubmit PreToolUse SubagentStart SubagentStop Stop SessionEnd; do
  check "event $ev wired" bash -c "jq -e '[.hooks.$ev[].hooks[].command]|map(select(test(\"label-sync/hooks/label-sync-\")))|length>=1' '$SETT' >/dev/null"
done
check "PreToolUse label hook uses the Agent|Task matcher" bash -c "jq -e '[.hooks.PreToolUse[]|select(.hooks[].command|test(\"label-sync-agent-register\"))|.matcher]|.[0]==\"Agent|Task\"' '$SETT' >/dev/null"
check "statusLine wired to the renderer" bash -c "jq -e '.statusLine.command|test(\"statusline.sh\")' '$SETT' >/dev/null"
check "hook commands reference the constitution via \$CLAUDE_PROJECT_DIR (portable, never copied)" bash -c "jq -e '[.hooks.SessionStart[].hooks[].command]|map(select(test(\"label-sync-session-start\")))|.[0]|test(\"CLAUDE_PROJECT_DIR\")' '$SETT' >/dev/null"
check "PostModelSwitch NOT wired by default (opt-in; event unconfirmed in docs)" bash -c "jq -e '.hooks.PostModelSwitch == null' '$SETT' >/dev/null"
shaA="$(sha256sum "$SETT" | cut -d' ' -f1)"; nb1="$(ls "$S/.claude/" | grep -c 'label-sync.bak')"
"${IA[@]}" --apply >/dev/null 2>&1; "${IA[@]}" --apply >/dev/null 2>&1
eq "apply x3 => byte-identical settings (idempotent)" "$(sha256sum "$SETT" | cut -d' ' -f1)" "$shaA"
eq "idempotent re-apply creates no extra backup" "$(ls "$S/.claude/" | grep -c 'label-sync.bak')" "$nb1"
eq "no duplicated entries: our SessionStart hook appears exactly once" "$(jq '[.hooks.SessionStart[].hooks[].command|select(test("label-sync-session-start"))]|length' "$SETT")" 1
eq "no duplicated entries: total label-sync hook commands" "$(jq '[.. | objects | select(has("command")) | .command | select(test("label-sync/hooks/label-sync-"))]|length' "$SETT")" 7
"${IA[@]}" --apply --with-model-switch >/dev/null 2>&1
check "--with-model-switch wires PostModelSwitch" bash -c "jq -e '[.hooks.PostModelSwitch[].hooks[].command]|map(select(test(\"label-sync-model-switch\")))|length==1' '$SETT' >/dev/null"
# invalid JSON refused
BAD="$T/bad"; mkdir -p "$BAD/.claude"; printf '{ "hooks": { oops ' >"$BAD/.claude/settings.json"; shab="$(sha256sum "$BAD/.claude/settings.json" | cut -d' ' -f1)"
bash "$INSTALLER" --project-root "$BAD" --render-path "$FIXREND" --apply >"$T/bad.out" 2>&1; eq "invalid JSON refused (exit 1)" "$?" 1
eq "invalid JSON file left byte-identical" "$(sha256sum "$BAD/.claude/settings.json" | cut -d' ' -f1)" "$shab"
check "invalid JSON: no backup/temp litter" bash -c "[ \"\$(ls -A '$BAD/.claude' | wc -l)\" = 1 ]"
check "invalid JSON refusal message names the file" grep -q 'settings.json' "$T/bad.out"
bash "$INSTALLER" --project-root "$BAD" --render-path "$FIXREND" >/dev/null 2>&1; eq "invalid JSON refused in dry-run too (exit 1)" "$?" 1
# fresh project: creates the file
FRESH="$T/fresh"; mkdir -p "$FRESH"
bash "$INSTALLER" --project-root "$FRESH" --render-path "$FIXREND" --apply >/dev/null 2>&1; eq "fresh project apply exit 0" "$?" 0
check "fresh project: settings.json created and valid" jq -e '.hooks.SessionStart' "$FRESH/.claude/settings.json"
bash "$INSTALLER" --project-root "$T/fresh2" --render-path "$FIXREND" >/dev/null 2>&1
check "dry-run on a fresh project creates nothing" test ! -e "$T/fresh2"
# existing different statusLine is preserved
SL="$T/sl"; mkdir -p "$SL/.claude"; echo '{"statusLine":{"type":"command","command":"my-own-statusline"}}' >"$SL/.claude/settings.json"
bash "$INSTALLER" --project-root "$SL" --render-path "$FIXREND" --apply >"$T/sl.out" 2>&1
eq "existing foreign statusLine NOT clobbered" "$(jq -r .statusLine.command "$SL/.claude/settings.json")" my-own-statusline
check "foreign statusLine reported honestly" grep -qi 'statusLine' "$T/sl.out"
# missing renderer at apply time => clear message, exit 2, nothing written
NR="$T/nr"; mkdir -p "$NR"
bash "$INSTALLER" --project-root "$NR" --render-path "$T/does/not/exist.sh" --apply >"$T/nr.out" 2>&1; eq "missing renderer at --apply => exit 2" "$?" 2
check "missing renderer: clear message names the path" grep -q 'does/not/exist.sh' "$T/nr.out"
check "missing renderer: nothing written" test ! -e "$NR/.claude/settings.json"
bash "$INSTALLER" --project-root "$NR" --render-path "$T/does/not/exist.sh" >/dev/null 2>&1; eq "missing renderer in DRY-RUN is only a note (exit 0)" "$?" 0
bash "$INSTALLER" --project-root "$NR" --render-path "$T/does/not/exist.sh" --no-statusline --apply >/dev/null 2>&1; eq "--no-statusline wires hooks without the renderer (exit 0)" "$?" 0
check "--no-statusline: hooks present, statusLine absent" bash -c "jq -e '.hooks.SessionStart and (.statusLine==null)' '$NR/.claude/settings.json' >/dev/null"
# --home isolation (user scope)
UH="$T/userhome"; mkdir -p "$UH"; realhome_before="$(ls -A "$HOME" | sort | tr '\n' ' ')"
bash "$INSTALLER" --scope user --home "$UH" --render-path "$FIXREND" --apply >"$T/uh.out" 2>&1; eq "user scope with --home exit 0" "$?" 0
check "user scope wrote under --home/.claude/settings.json" jq -e '.hooks.SessionStart' "$UH/.claude/settings.json"
check "user scope uses absolute hook paths" bash -c "jq -e '[.hooks.SessionStart[].hooks[].command]|.[0]|contains(\"$CROOT\")' '$UH/.claude/settings.json' >/dev/null"
eq "--home isolation: the process HOME was not written" "$(ls -A "$HOME" | sort | tr '\n' ' ')" "$realhome_before"
CD="$T/cfgdir"; mkdir -p "$CD"
bash "$INSTALLER" --scope user --config-dir "$CD" --render-path "$FIXREND" --apply >/dev/null 2>&1
check "--config-dir targets <dir>/settings.json" jq -e '.hooks.Stop' "$CD/settings.json"
# platforms
bash "$INSTALLER" --project-root "$T/pl" --platform all --render-path "$FIXREND" >"$T/pl.out" 2>&1; eq "--platform all dry-run exit 0" "$?" 0
check "--platform all reports non-Claude platforms honestly" grep -qiE 'opencode|gemini|qwen' "$T/pl.out"
bash "$INSTALLER" --project-root "$T/pl" --platform bogus >/dev/null 2>&1; eq "unknown platform => usage exit 2" "$?" 2
# rollback instruction: restoring the backup yields the original
cp "$SETT" "$T/after.json"; bk="$(ls "$S/.claude/"settings.json.label-sync.bak.* | head -n1)"
check "backup is the pre-install original (no label-sync hooks inside)" bash -c "! grep -q label-sync '$bk'"
"${IA[@]}" --uninstall --apply >"$T/un.out" 2>&1; eq "--uninstall --apply exit 0" "$?" 0
eq "--uninstall removes every label-sync hook" "$(jq '[.. | objects | select(has("command")) | .command | select(test("label-sync/hooks/label-sync-"))]|length' "$SETT")" 0
check "--uninstall keeps unrelated hooks" bash -c "jq -e '[.hooks.PreToolUse[].hooks[].command]|index(\"bash /opt/guard.sh\")' '$SETT' >/dev/null"
check "--uninstall removes our statusLine" bash -c "jq -e '.statusLine==null' '$SETT' >/dev/null"

# =========================================================================
echo "== 11. post_update_hook.sh wiring (default NON-destructive) =="
FC="$T/fakeconst"; mkdir -p "$FC/scripts/label-sync/hooks" "$FC/scripts/multitrack" "$FC/docs"
cp "$POSTHOOK" "$FC/scripts/post_update_hook.sh"
cp -r "$LS/hooks/." "$FC/scripts/label-sync/hooks/" 2>/dev/null
cp "$INSTALLER" "$FC/scripts/label-sync/install_label_sync.sh" 2>/dev/null
mkdir -p "$FC/scripts/label-sync/render"; cp "$FIXREND" "$FC/scripts/label-sync/render/statusline.sh"
echo '# c' >"$FC/Constitution.md"
( cd "$FC" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -q -m base \
  && echo '# touched' >>scripts/label-sync/hooks/label-sync-lib.sh && git add -A && git -c user.email=t@t -c user.name=t commit -q -m change )
PR="$T/consumer"; mkdir -p "$PR/.claude"
echo '{"env":{"K":"v"}}' >"$PR/.claude/settings.json"; shp="$(sha256sum "$PR/.claude/settings.json" | cut -d' ' -f1)"
( cd "$PR" && CONST_DIR="$FC" PROJECT_ROOT="$PR" bash "$FC/scripts/post_update_hook.sh" ) >"$T/ph1.out" 2>&1; rc=$?
check "post-update (default mode) finished" test "$rc" -le 1
eq "post-update default mode did NOT modify the consumer settings (non-destructive)" "$(sha256sum "$PR/.claude/settings.json" | cut -d' ' -f1)" "$shp"
check "post-update default mode RECORDED what would be wired" grep -qi 'label-sync' "$T/ph1.out"
check "post-update default mode names the apply switch" grep -q 'LABEL_SYNC_AUTOWIRE=apply' "$T/ph1.out"
( cd "$PR" && CONST_DIR="$FC" PROJECT_ROOT="$PR" LABEL_SYNC_AUTOWIRE=apply bash "$FC/scripts/post_update_hook.sh" ) >"$T/ph2.out" 2>&1
check "post-update apply mode wired the hooks" jq -e '.hooks.SessionStart and .env.K=="v"' "$PR/.claude/settings.json"
shq="$(sha256sum "$PR/.claude/settings.json" | cut -d' ' -f1)"
( cd "$PR" && CONST_DIR="$FC" PROJECT_ROOT="$PR" LABEL_SYNC_AUTOWIRE=apply bash "$FC/scripts/post_update_hook.sh" ) >"$T/ph3.out" 2>&1
eq "post-update apply is idempotent" "$(sha256sum "$PR/.claude/settings.json" | cut -d' ' -f1)" "$shq"

# =========================================================================
echo "----------------------------------------------------------------------"
echo "label-sync hooks suite: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
echo "✅ ALL PASSED"
exit 0
