#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-prompt.sh
#
# Purpose : Claude Code UserPromptSubmit hook. (1) heartbeat + live refresh of
#           the session entity (branch/model/effort may have changed since the
#           last prompt; re-registers if the entity is missing — level-triggered,
#           §11.4.233); (2) appends the §11.4.208 per-prompt request-history
#           ledger row EXACTLY ONCE via request_history_append.sh; (3) emits the
#           live (effective) label as additionalContext so the model itself
#           always sees its current track/alias/model/effort.
# Usage   : configured in settings.json hooks.UserPromptSubmit; stdin = hook JSON
#           ({session_id, cwd, prompt}).
# Inputs  : stdin JSON; env CLAUDE_CONFIG_DIR, CLAUDE_PROJECT_DIR (ledger path
#           default <proj>/docs/requests/history.jsonl when that dir exists),
#           LABEL_SYNC_REQUEST_LEDGER (explicit ledger path), LABEL_SYNC_*.
# Outputs : stdout: ONE JSON line with hookSpecificOutput.additionalContext
#           ("[label-sync] current work-stream label: ...") or nothing.
# Exit    : ALWAYS 0; never blocks the prompt; median < 150 ms.
# Side-effects: label-sync events; one ledger row per prompt (see
#           request_history_append.sh for the dedupe window).
# Deps    : bash, jq, labelctl, the canonical labeler.
# Cross-refs: §11.4.208 (request-history ledger), §11.4.210 (zero-loss intake),
#           §11.4.182, docs/label-sync/HOOKS.md.
# Classification: universal (§11.4.17).
set -u
_d="${BASH_SOURCE[0]:-$0}"; _d="${_d%/*}"
. "$_d/label-sync-lib.sh" 2>/dev/null || exit 0
. "$_d/request_history_append.sh" 2>/dev/null || exit 0
main() {
  LS_EVENT=UserPromptSubmit
  ls_init || return 0
  ls_read_payload || return 0
  local lab alias="" model="" effort="" track="" branch=""
  lab="$(ls_derive)" || lab=""
  if [ -n "$lab" ] && ls_parse_label "$lab"; then
    alias="$LS_L_ALIAS"; model="$LS_L_MODEL"; effort="$LS_L_EFFORT"; track="$LS_L_TRACK"; branch="$LS_L_BRANCH"
  fi
  # (2) ledger first: it needs no daemon/binary (zero-loss intake, §11.4.210)
  if [ -n "$LS_PROMPT" ]; then
    LS_LEDGER_STATE="${LS_HOOKSTATE:-}" rha_append "$LS_SID" "$LS_PROMPT" "$track" "$alias" "$model" "$effort" "$LS_CWD" >/dev/null 2>&1
  fi
  ls_have_bin || return 0
  export CLAUDE_CODE_SESSION_ID="$LS_SID"
  local id; id="$(ls_session_entity)"
  # Re-assert the PINNED binding on every prompt (review finding 1): the
  # derived alias is this process's truth, so it is written together with
  # --follow-active false in the SAME single update — no read, no compare, no
  # extra call. A session whose alias cannot be derived is left as it is.
  local -a u=(update --id "$id" --state running --cwd "$LS_CWD")
  [ -n "$track" ] && u+=(--track "$track")
  [ -n "$branch" ] && u+=(--branch "$branch")
  [ -n "$alias" ] && u+=(--alias "$alias" --follow-active false)
  [ -n "$model" ] && u+=(--model "$model")
  [ -n "$effort" ] && u+=(--effort "$effort")
  local rc=0
  ls_ctl "${u[@]}" >/dev/null || rc=$?
  [ "$rc" -eq 2 ] && return 0          # lock busy / state unusable: no further waits
  if [ "$rc" -ne 0 ]; then
    ls_ensure_session "prompt" || return 0
  fi
  local eff; eff="$(ls_ctl label "$id")" || return 0
  [ -n "$eff" ] || return 0
  ls_emit_context UserPromptSubmit "[label-sync] current work-stream label: $eff"
}
ls_hook_run main
