#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-prompt.sh
#
# Purpose : Claude Code UserPromptSubmit hook. (1) heartbeat + live refresh of
#           the session entity (branch/model/effort may have changed since the
#           last prompt; re-registers if the entity is missing — level-triggered,
#           §11.4.233); (2) appends the §11.4.208 per-prompt request-history
#           ledger row EXACTLY ONCE via request_history_append.sh; (3) emits the
#           live (effective) label as additionalContext so the model itself
#           always sees its current track/alias/model/effort — the session's OWN
#           (pinned) binding, re-asserted in the single update.
# Usage   : configured in settings.json hooks.UserPromptSubmit; stdin = hook JSON
#           ({session_id, cwd, prompt}).
# Inputs  : stdin JSON; env CLAUDE_CONFIG_DIR, LABEL_SYNC_REQUEST_LEDGER (the
#           ledger path — OPT-IN, no ledger without it; relative => against
#           CLAUDE_PROJECT_DIR), LABEL_SYNC_*. Large prompts (> 64 Ki chars) go
#           from the payload to the ledger's 0600 temp file without ever being a
#           shell variable or an argv (8 MiB: ~1.5 s on a loaded host).
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
  # an explicitly recorded model switch wins over the (pre-switch) transcript
  # until a newer assistant entry proves otherwise (review-2 finding 3)
  ls_switched_model && model="$LS_SWITCH_MODEL"
  # (2) ledger first: it needs no daemon/binary (zero-loss intake, §11.4.210)
  if [ -n "${LABEL_SYNC_REQUEST_LEDGER:-}" ]; then
    export LS_LEDGER_STATE="${LS_HOOKSTATE:-}"
    if [ -n "${LS_PROMPT_BIG:-}" ]; then
      # large prompt: never a shell copy, never an argv (E2BIG at 128 KiB) —
      # jq streams it from the payload into the 0600 temp file.
      if rha_prepare --tmp; then
        printf '%s' "$LS_PAYLOAD" | jq -j '(.prompt // .user_prompt // "") | if type=="string" then . else "" end' >"$RHA_TMP" 2>/dev/null
        rha_append_file "$LS_SID" "$RHA_TMP" "$track" "$alias" "$model" "$effort" "$LS_CWD" >/dev/null
      else
        rha_lost_row "$LS_SID" "" "$track" "$alias" "$model" "$effort" "$LS_CWD" "no state dir for the temp file" >/dev/null
      fi
    elif [ -n "$LS_PROMPT" ]; then
      rha_append "$LS_SID" "$LS_PROMPT" "$track" "$alias" "$model" "$effort" "$LS_CWD" >/dev/null
    fi
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
  # `update` (like `register`) prints the rendered EFFECTIVE label after the
  # write — that is the additionalContext; no second `labelctl label` spawn.
  local rc=0 eff
  eff="$(ls_ctl "${u[@]}")" || rc=$?
  [ "$rc" -eq 2 ] && return 0          # lock busy / state unusable: no further waits
  if [ "$rc" -ne 0 ]; then
    ls_ensure_session "prompt" || return 0
    eff="$LS_LABEL"
  fi
  eff="${eff%%$'\n'*}"
  [ -n "$eff" ] || return 0
  ls_emit_context UserPromptSubmit "[label-sync] current work-stream label: $eff"
}
ls_hook_run main
