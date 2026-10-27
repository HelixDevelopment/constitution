#!/usr/bin/env bash
# scripts/label-sync/adapters/kimi/kimi-hook.sh
#
# Purpose : Kimi Code CLI hook -> label bus. Kimi Code runs the commands listed
#           under `[[hooks]]` in config.toml and writes ONE JSON document on
#           their stdin (snake_case keys: hook_event_name, session_id, cwd,
#           model, agent_name, ...). This script maps the events to the label
#           contract so a Kimi session shows `(T<N>/<branch> - kimi - <model> - ?)`.
# Usage   : configured by install_adapters.sh as
#             [[hooks]] event = "SessionStart" command = "bash <this script>"
#           (also UserPromptSubmit, Stop, SessionEnd, SubagentStart, SubagentStop).
#           Manual: echo '{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/x"}' | kimi-hook.sh
# Inputs  : stdin JSON (only hook_event_name, session_id, cwd, model, agent_name
#           are read — prompts/tool inputs/responses are NEVER parsed, §11.4.10);
#           env of adapter_lib.sh.
# Outputs : nothing on stdout/stderr (a Kimi hook that prints could be read as a
#           decision).
# Exit    : ALWAYS 0 — in Kimi's contract exit 2 BLOCKS the action; an observer
#           must never block the agent (fail-soft, §11.4.6).
# Mapping : SessionStart->register running | UserPromptSubmit->heartbeat running |
#           Stop->heartbeat idle | SessionEnd->done | SubagentStart->register
#           subagent (parent = the session entity) | SubagentStop->done.
#           Subagent entity id = <session>.sub.<agent_name>: two concurrent
#           subagents of the SAME name share one entity (payload has no unique id).
# Side-effects: labelctl calls. Deps: bash, jq (absent => silent no-op).
# Cross-refs: §11.4.182, §11.4.18, docs/label-sync/ADAPTERS.md (capability: SCHEMA-ONLY).
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../lib/adapter_lib.sh"
al_init || exit 0
command -v jq >/dev/null 2>&1 || exit 0
IFS= read -r -d '' payload || true
[ -n "$payload" ] || exit 0
parsed="$(printf '%s' "$payload" | jq -r 'select(type=="object") |
  [(.hook_event_name // ""), (.session_id // ""), (.cwd // ""),
   (.model | if type=="string" then . elif type=="object" then (.name // .id // .alias // "") else "" end),
   (.agent_name // "")] | map(gsub("[[:cntrl:]]";"")) | join("\u001f")' 2>/dev/null)" || exit 0
[ -n "$parsed" ] || exit 0
IFS=$'\037' read -r ev sess cwd mdl agent_name <<<"$parsed"
[ -n "$sess" ] || exit 0
case "$ev" in
  SessionStart)      al_upsert kimi "$sess" "$cwd" "$mdl" "" running ;;
  UserPromptSubmit)  al_upsert kimi "$sess" "$cwd" "$mdl" "" running ;;
  Stop)              al_upsert kimi "$sess" "$cwd" "$mdl" "" idle ;;
  SessionEnd)        al_done kimi "$sess" ;;
  SubagentStart)
    [ -n "$agent_name" ] || exit 0
    al_upsert kimi "$sess.sub.$agent_name" "$cwd" "$mdl" "" running "$(al_entity_id kimi "$sess")" subagent ;;
  SubagentStop)
    [ -n "$agent_name" ] || exit 0
    al_done kimi "$sess.sub.$agent_name" ;;
esac
exit 0
