#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-model-switch.sh
#
# Purpose : OPTIONAL Claude Code PostModelSwitch hook (the installer wires it
#           only with --with-model-switch). When the session model changes
#           (/model, model picker, autonomous tier switch §11.4.231) the session
#           entity's model is updated at once so every label shows the real
#           current model without waiting for the next prompt.
# Usage   : settings.json hooks.PostModelSwitch; stdin = hook JSON {session_id,
#           to_model, from_model, source, ...}.
# Inputs  : stdin JSON; LABEL_SYNC_* env.
# Outputs : none.
# Exit    : ALWAYS 0.
# Honest boundary (§11.4.6): the PreModelSwitch/PostModelSwitch events and their
#           `to_model` field were CONFIRMED only by reading the installed Claude
#           Code 2.1.296 binary's built-in hook descriptions (not by observing a
#           live delivery, and not in the public plugin-dev documentation) —
#           hence opt-in. Without this hook the model is still refreshed on every
#           prompt (label-sync-prompt.sh).
# Side-effects: label-sync update event.
# Deps    : bash, jq, labelctl.
# Cross-refs: §11.4.182, §11.4.231, docs/label-sync/HOOKS.md.
# Classification: universal (§11.4.17).
set -u
_d="${BASH_SOURCE[0]:-$0}"; _d="${_d%/*}"
. "$_d/label-sync-lib.sh" 2>/dev/null || exit 0
main() {
  LS_EVENT=PostModelSwitch
  ls_init || return 0
  ls_read_payload || return 0
  [ -n "$LS_TOMODEL" ] || return 0
  ls_have_bin || return 0
  ls_ctl update --id "$(ls_session_entity)" --model "$(ls_model_short "$LS_TOMODEL")" >/dev/null || true
  return 0
}
ls_hook_run main
