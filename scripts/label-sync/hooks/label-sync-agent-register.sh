#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-agent-register.sh
#
# Purpose : Claude Code PreToolUse hook for matcher `Agent|Task`. Registers the
#           about-to-run SUBAGENT as an entity whose label fields are parsed
#           from the dispatch description's §11.4.182 label prefix
#           `(T<N>/<branch> - <alias>[ - <model>[ - <effort>]]) ...`.
#           It COMPOSES with — and never replaces — guard-track-branch-label.sh
#           (the guard BLOCKS unlabelled / stale-alias dispatches; this hook
#           NEVER blocks and prints nothing). To avoid phantom entities for a
#           dispatch the guard is about to refuse, it registers ONLY when the
#           description starts with a well-formed label whose alias does not
#           provably contradict the live alias (same rule as the guard).
#           A pending-correlation file lets SubagentStart/SubagentStop find the
#           entity later.
# Usage   : settings.json hooks.PreToolUse, matcher "Agent|Task"; stdin = hook JSON.
# Inputs  : stdin JSON {tool_name, tool_use_id, tool_input:{description,
#           subagent_type, model}}; env CLAUDE_CONFIG_DIR, LABEL_SYNC_*.
# Outputs : none (stdout stays empty).
# Exit    : ALWAYS 0 — it must never block a dispatch.
# Side-effects: label-sync register event; $LABEL_SYNC_DIR/hooks/pending/<sid>/<tool_use_id>
#           (lines: entity id, subagent_type).
# Deps    : bash, jq, labelctl.
# Cross-refs: §11.4.182, §11.4.147 (agent registry), guard-track-branch-label.sh,
#           CONTRACT §4.2 (pinned when labelled with an alias, else inherits
#           its session's binding).
# Classification: universal (§11.4.17).
set -u
_d="${BASH_SOURCE[0]:-$0}"; _d="${_d%/*}"
. "$_d/label-sync-lib.sh" 2>/dev/null || exit 0
main() {
  LS_EVENT=PreToolUse
  ls_init || return 0
  ls_read_payload || return 0
  case "$LS_TOOL" in Agent|Task) ;; *) return 0 ;; esac
  ls_parse_label "$LS_DESC" || return 0          # unlabelled: the guard blocks it
  local live="" cb; cb="$(basename "${CLAUDE_CONFIG_DIR:-}")"
  case "$cb" in .claude-?*) live="${cb#.claude-}" ;; esac
  if [ -n "$LS_L_ALIAS" ] && [ -n "$live" ] && [ "$LS_L_ALIAS" != "$live" ]; then return 0; fi
  ls_have_bin || return 0
  local sid_ent follow parent
  sid_ent="$(ls_session_entity)"
  # level-triggered: make sure the session (the subtree root) exists
  ls_ctl get --id "$sid_ent" --json >/dev/null || ls_ensure_session "agent-register" || return 0
  # Binding (CONTRACT §4.2, review finding 1): a label carrying an alias (the
  # guard has just checked it equals the live alias of THIS process) PINS the
  # subagent to its own declared triple; a label without an alias ("?") leaves
  # the subagent following, i.e. it INHERITS its session's binding. Nothing is
  # ever bound to the operator-global active alias by a hook.
  follow=false; [ -n "$LS_L_ALIAS" ] || follow=true
  parent="$sid_ent"
  ls_hookdir
  # dispatched from INSIDE a paired subagent => that subagent is the parent
  if [ -n "$LS_AGENT_ID" ] && [ -f "$LS_HOOKSTATE/agentmap/$LS_AGENT_ID" ]; then
    local pm; { IFS= read -r pm; } <"$LS_HOOKSTATE/agentmap/$LS_AGENT_ID" 2>/dev/null
    [ -n "$pm" ] && parent="$pm"
  fi
  # tool_use_id keys BOTH the entity and the pending file, so the same event
  # delivered twice (hooks wired in user AND project scope) is one registration
  # (review finding 5). Absent id => a DETERMINISTIC id from the payload (never
  # time-based: a double delivery must collapse, not duplicate).
  local tuid="$LS_TUID"
  if [ -z "$tuid" ]; then
    tuid="$(printf '%s\n%s\n%s' "$LS_SID" "$LS_DESC" "$LS_SUBTYPE" | sha1sum 2>/dev/null)"; tuid="h${tuid:0:20}"
  fi
  local eid="subagent:$tuid" model="$LS_L_MODEL"
  if [ -z "$model" ] && [ -n "$LS_TOOLMODEL" ]; then model="$(ls_model_short "$LS_TOOLMODEL")"; fi
  local -a a=(register --id "$eid" --kind subagent --parent "$parent" --session "$LS_SID" --cwd "$LS_CWD"
              --source "hook:label-sync-agent-register" --state running --follow-active "$follow")
  [ -n "$LS_L_TRACK" ] && a+=(--track "$LS_L_TRACK")
  [ -n "$LS_L_BRANCH" ] && a+=(--branch "$LS_L_BRANCH")
  [ -n "$LS_L_ALIAS" ] && a+=(--alias "$LS_L_ALIAS")
  [ -n "$model" ] && a+=(--model "$model")
  [ -n "$LS_L_EFFORT" ] && a+=(--effort "$LS_L_EFFORT")
  ls_ctl "${a[@]}" >/dev/null || return 0
  ( umask 077; mkdir -p "$LS_HOOKSTATE/pending/$LS_SID" ) 2>/dev/null
  printf '%s\n%s\n' "$eid" "$LS_SUBTYPE" >"$LS_HOOKSTATE/pending/$LS_SID/$tuid" 2>/dev/null
  return 0
}
ls_hook_run main
