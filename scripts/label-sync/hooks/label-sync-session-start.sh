#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-session-start.sh
#
# Purpose : Claude Code SessionStart hook. Registers (or re-asserts) the SESSION
#           entity in the label-sync state: session_id, owning claude pid
#           (liveness), cwd, track/branch/alias/model/effort derived by the
#           canonical labeler. A session whose alias is derived from this
#           process (CLAUDE_CONFIG_DIR) is PINNED to it (CONTRACT §4.2): two
#           terminals on two aliases each keep their own label whatever the
#           operator-global active alias does. RESUMED under a different alias
#           => re-registered with the new alias; the core re-renders the whole
#           subtree (CONTRACT §4.3). The hook never writes active.json.
#           Emits the live label as additionalContext so the model sees it.
# Usage   : configured in settings.json hooks.SessionStart; reads the hook JSON on
#           stdin ({session_id, cwd, source: startup|resume|clear|compact|fork,
#           model} — a string `model` wins over the transcript lookup).
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
  LS_PAYLOAD_MODEL="$LS_TOMODEL"            # SessionStart's own `model` (string only)
  ls_ensure_session "session-start" || return 0
  local lbl="${LS_LABEL%%$'\n'*}"             # the label register printed
  [ -n "$lbl" ] || return 0
  ls_emit_context SessionStart "[label-sync] work-stream label of this session: $lbl (pinned to the alias this session runs under)"
}
ls_hook_run main
