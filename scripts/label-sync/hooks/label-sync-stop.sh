#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-stop.sh
#
# Purpose : Claude Code Stop hook (end of an assistant turn). Marks the session
#           idle (the next prompt revives it to running) and reaps PENDING
#           subagent registrations that were never adopted by a SubagentStart —
#           i.e. dispatches that were refused/denied or never started — so no
#           phantom "running" subagent survives the turn.
# Usage   : settings.json hooks.Stop; stdin = hook JSON {session_id}.
# Inputs  : stdin JSON; LABEL_SYNC_* env.
# Outputs : none.
# Exit    : ALWAYS 0 (never returns exit 2 / never keeps the turn going).
# Side-effects: label-sync update/unregister events; removes hooks/pending/<sid>/*.
# Deps    : bash, jq, labelctl.
# Cross-refs: §11.4.233 (level-triggered cleanup), docs/label-sync/HOOKS.md.
# Classification: universal (§11.4.17).
set -u
_d="${BASH_SOURCE[0]:-$0}"; _d="${_d%/*}"
. "$_d/label-sync-lib.sh" 2>/dev/null || exit 0
main() {
  LS_EVENT=Stop
  ls_init || return 0
  ls_read_payload || return 0
  ls_have_bin || return 0
  local id d f eid
  id="$(ls_session_entity)"; d="$LS_HOOKSTATE/pending/$LS_SID"
  local rc=0
  ls_ctl update --id "$id" --state idle >/dev/null || rc=$?
  # rc 2 = writer lock busy (bounded wait elapsed) or state unusable: every
  # further write would just wait again — stop here, the next event re-asserts.
  [ "$rc" -eq 2 ] && return 0
  if [ "$rc" -ne 0 ]; then
    ls_ensure_session "stop" && ls_ctl update --id "$id" --state idle >/dev/null
  fi
  if [ -d "$d" ]; then
    for f in "$d"/*; do
      [ -f "$f" ] || continue
      eid="$(sed -n 1p "$f")"
      [ -n "$eid" ] && ls_ctl unregister --id "$eid" >/dev/null
      rm -f -- "$f"
    done
  fi
  return 0
}
ls_hook_run main
