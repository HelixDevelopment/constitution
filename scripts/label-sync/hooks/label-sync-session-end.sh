#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-session-end.sh
#
# Purpose : Claude Code SessionEnd hook. Marks the session entity AND every
#           entity of that session_id (subagents, streams, shells) done, and
#           removes the hook-private correlation state of the session. Entities
#           stay visible as `done` for the retention window and are then reaped
#           by label-busd (CONTRACT §6).
# Usage   : settings.json hooks.SessionEnd; stdin = hook JSON {session_id, reason}.
# Inputs  : stdin JSON; LABEL_SYNC_* env.
# Outputs : none.
# Exit    : ALWAYS 0.
# Side-effects: label-sync unregister events; deletes hooks/pending/<sid>/,
#           hooks/sessions/<sid>.alias and hooks/ledger-last/<sid>.
# Deps    : bash, jq, labelctl.
# Cross-refs: §11.4.233, CONTRACT §6, docs/label-sync/HOOKS.md.
# Classification: universal (§11.4.17).
set -u
_d="${BASH_SOURCE[0]:-$0}"; _d="${_d%/*}"
. "$_d/label-sync-lib.sh" 2>/dev/null || exit 0
main() {
  LS_EVENT=SessionEnd
  ls_init || return 0
  ls_read_payload || return 0
  [ -n "$LS_SID" ] || return 0
  ls_have_bin || return 0
  local id ids x
  id="$(ls_session_entity)"
  ids="$(ls_ctl list --json | jq -r --arg sid "$LS_SID" --arg me "$id" \
        '.entities[]|select((.id==$me or .session_id==$sid) and .state!="done")|.id' 2>/dev/null)"
  for x in $ids; do ls_ctl unregister --id "$x" >/dev/null; done
  # Hook-private state of this session. LS_SID is a validated id (lib:
  # ls_read_payload), and even so nothing here is a recursive removal of a
  # stdin-derived path: only the regular files of OUR fixed layout are removed,
  # one by one, then the (now empty) per-session dir is rmdir'ed.
  ls_drop_pending_dir "$LS_SID"
  rm -f -- "$LS_HOOKSTATE/ledger-last/$LS_SID"
  return 0
}
ls_hook_run main
