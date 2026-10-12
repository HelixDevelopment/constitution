#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-session-start.sh
#
# Purpose : Claude Code SessionStart hook. Registers (or re-asserts) the SESSION
#           entity in the label-sync state: session_id, owning claude pid
#           (liveness), cwd, track/branch/alias/model/effort derived by the
#           canonical labeler. When the session was RESUMED under a DIFFERENT
#           alias than its previous registration, publishes the alias change:
#           the session is registered non-following (state layer republishes the
#           whole subtree, CONTRACT §4.3) and the new alias is published as the
#           ACTIVE alias (alias_switch) unless LABEL_SYNC_NO_SWITCH_ON_RESUME=1.
#           Emits the live label as additionalContext so the model sees it.
# Usage   : configured in settings.json hooks.SessionStart; reads the hook JSON on
#           stdin ({session_id, cwd, source: startup|resume|clear|compact|fork}).
# Inputs  : stdin JSON; env CLAUDE_CONFIG_DIR (alias source), LABEL_SYNC_* (see
#           label-sync-lib.sh).
# Outputs : stdout: ONE JSON line {"hookSpecificOutput":{"hookEventName":
#           "SessionStart","additionalContext":"[label-sync] ..."}} or nothing.
# Exit    : ALWAYS 0 (fail-soft; never blocks the session; <150 ms typical).
# Side-effects: appends events to the label-sync state; hook-private files under
#           $LABEL_SYNC_DIR/hooks/. No network.
# Deps    : bash, jq, labelctl (built by labelctl.sh), the canonical labeler.
# Cross-refs: §11.4.182, CONTRACT §4.3, docs/label-sync/HOOKS.md.
# Classification: universal (§11.4.17).
set -u
_d="${BASH_SOURCE[0]:-$0}"; _d="${_d%/*}"
. "$_d/label-sync-lib.sh" 2>/dev/null || exit 0
main() {
  LS_EVENT=SessionStart
  ls_init || return 0
  ls_read_payload || return 0
  ls_have_bin || return 0
  ls_ensure_session "session-start" || return 0
  local lbl; lbl="$(ls_ctl label "$(ls_session_entity)")" || return 0
  [ -n "$lbl" ] || return 0
  ls_emit_context SessionStart "[label-sync] work-stream label of this session: $lbl (updates live when the operator switches alias)"
}
ls_hook_run main
