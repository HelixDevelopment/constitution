#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-subagent-start.sh
#
# Purpose : Claude Code SubagentStart hook. Correlates the runtime `agent_id`
#           with the entity that label-sync-agent-register.sh created at
#           PreToolUse (which only knew the tool_use_id): picks the OLDEST pending
#           registration of this session (preferring one whose subagent_type
#           equals the payload's agent_type) and records agentmap/<agent_id>.
# Usage   : settings.json hooks.SubagentStart; stdin = hook JSON {session_id,
#           agent_id, agent_type}.
# Inputs  : stdin JSON; LABEL_SYNC_* env.
# Outputs : none.
# Exit    : ALWAYS 0.
# Side-effects: moves a file from hooks/pending/<sid>/ to hooks/agentmap/.
# Honest boundary (§11.4.6): the tool_use_id <-> agent_id correspondence is
#           UNCONFIRMED in Claude Code's documentation; pairing is oldest-first
#           (+ type match), so for PARALLEL dispatches of the same type the
#           pairing is a best effort. An unpaired entity is cleaned at Stop /
#           SessionEnd, never left running forever.
# Deps    : bash, jq.
# Cross-refs: §11.4.147, docs/label-sync/HOOKS.md.
# Classification: universal (§11.4.17).
set -u
_d="${BASH_SOURCE[0]:-$0}"; _d="${_d%/*}"
. "$_d/label-sync-lib.sh" 2>/dev/null || exit 0
main() {
  LS_EVENT=SubagentStart
  ls_init || return 0
  ls_read_payload || return 0
  [ -n "$LS_AGENT_ID" ] || return 0
  local atype="$LS_ATYPE"
  local d="$LS_HOOKSTATE/pending/$LS_SID" f pick="" first=""
  [ -d "$d" ] || return 0
  for f in $(ls -1 "$d" 2>/dev/null | sort); do
    [ -n "$first" ] || first="$f"
    if [ -n "$atype" ] && [ "$(sed -n 2p "$d/$f")" = "$atype" ]; then pick="$f"; break; fi
  done
  [ -n "$pick" ] || pick="$first"
  [ -n "$pick" ] || return 0
  ls_hookdir
  sed -n 1p "$d/$pick" >"$LS_HOOKSTATE/agentmap/$LS_AGENT_ID" 2>/dev/null
  rm -f "${d:?}/${pick:?}"
  return 0
}
ls_hook_run main
