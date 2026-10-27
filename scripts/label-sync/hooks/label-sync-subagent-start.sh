#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-subagent-start.sh
#
# Purpose : Claude Code SubagentStart hook. Correlates the runtime `agent_id`
#           with the entity that label-sync-agent-register.sh created at
#           PreToolUse (which only knew the tool_use_id): pairs it with the ONE
#           pending registration of this session whose subagent_type equals the
#           payload's agent_type, and records agentmap/<agent_id>.
# Usage   : settings.json hooks.SubagentStart; stdin = hook JSON {session_id,
#           agent_id, agent_type}.
# Inputs  : stdin JSON; LABEL_SYNC_* env.
# Outputs : none.
# Exit    : ALWAYS 0.
# Side-effects: moves a file from hooks/pending/<sid>/ to hooks/agentmap/
#           (lines: entity id, session id).
# Honest boundary (§11.4.6): SubagentStart carries agent_id + agent_type only;
#           its toolUseID is a fresh random id (read in the 2.1.296 binary), so
#           it CANNOT be matched to the dispatch's tool_use_id. With >= 2 pending
#           registrations of the same type the pairing is AMBIGUOUS and nothing
#           is paired (no guess): those entities stay running, unpaired, until
#           Stop / SessionEnd unregisters them. A repeated SubagentStart for an
#           already-paired agent_id is a no-op (double-scope wiring).
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
  local map="$LS_HOOKSTATE/agentmap/$LS_AGENT_ID"
  # idempotent: a second delivery of the same SubagentStart (hooks wired in two
  # scopes) must never re-pair this agent with ANOTHER pending registration.
  [ -e "$map" ] && return 0
  local d="$LS_HOOKSTATE/pending/$LS_SID" f st n=0 pick=""
  [ -d "$d" ] || return 0
  # Candidates: pending registrations whose subagent_type equals agent_type
  # (an empty type on either side matches anything). SubagentStart's own
  # toolUseID is a fresh random id, NOT the dispatch's tool_use_id, so a type
  # match is the only correlation evidence there is. Exactly one candidate =>
  # paired. Two or more => AMBIGUOUS: nothing is paired (no guess, review
  # finding 4); those registrations stay running, unpaired, until Stop /
  # SessionEnd unregisters them.
  for f in "$d"/*; do
    [ -f "$f" ] || continue
    st=""; { IFS= read -r _; IFS= read -r st; } <"$f" 2>/dev/null
    if [ -z "$LS_ATYPE" ] || [ -z "$st" ] || [ "$st" = "$LS_ATYPE" ]; then n=$((n + 1)); pick="$f"; fi
  done
  if [ "$n" -ne 1 ]; then
    [ "$n" -gt 1 ] && ls_dbg "ambiguous SubagentStart agent=$LS_AGENT_ID type=$LS_ATYPE candidates=$n — not paired"
    return 0
  fi
  ls_hookdir
  local eid; { IFS= read -r eid; } <"$pick" 2>/dev/null
  [ -n "$eid" ] || return 0
  printf '%s\n%s\n' "$eid" "$LS_SID" >"$map" 2>/dev/null || return 0
  rm -f -- "$pick"
  return 0
}
ls_hook_run main
