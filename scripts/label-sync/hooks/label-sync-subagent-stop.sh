#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-subagent-stop.sh
#
# Purpose : Claude Code SubagentStop hook. Marks the subagent entity correlated
#           to payload.agent_id as done (unregister => state=done, kept for the
#           retention window then reaped by label-busd) and drops the
#           correlation file. An agent_id with no correlation is NOT guessed
#           (§11.4.6) — such entities are cleaned at Stop/SessionEnd.
# Usage   : settings.json hooks.SubagentStop; stdin = hook JSON {session_id,
#           agent_id}.
# Inputs  : stdin JSON; LABEL_SYNC_* env.
# Outputs : none.
# Exit    : ALWAYS 0.
# Side-effects: label-sync unregister event; removes hooks/agentmap/<agent_id>.
# Deps    : bash, jq, labelctl.
# Cross-refs: §11.4.147, docs/label-sync/HOOKS.md.
# Classification: universal (§11.4.17).
set -u
_d="${BASH_SOURCE[0]:-$0}"; _d="${_d%/*}"
. "$_d/label-sync-lib.sh" 2>/dev/null || exit 0
main() {
  LS_EVENT=SubagentStop
  ls_init || return 0
  ls_read_payload || return 0
  [ -n "$LS_AGENT_ID" ] || return 0
  local m="$LS_HOOKSTATE/agentmap/$LS_AGENT_ID" eid
  [ -f "$m" ] || return 0
  { IFS= read -r eid; } <"$m" 2>/dev/null
  ls_have_bin || return 0
  [ -n "$eid" ] && ls_ctl unregister --id "$eid" >/dev/null
  rm -f -- "$m"
  return 0
}
ls_hook_run main
