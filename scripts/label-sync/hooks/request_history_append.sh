#!/usr/bin/env bash
# scripts/label-sync/hooks/request_history_append.sh
#
# Purpose : Append ONE operator-request row to the project-local §11.4.208
#           request-history ledger. This is the auto-capture seam that
#           label-sync-prompt.sh (UserPromptSubmit) calls for every prompt. No
#           pre-existing append helper exists in the constitution tree (searched
#           2026-10-12), so this is that helper.
#           Row = JSONL object, newest LAST (append-only, atomic under flock):
#             {accepted, timezone, session_id, prompt, prompt_kind:"verbatim",
#              track, alias, model, effort, cwd, source}
#           Unrecoverable fields are the literal string "UNKNOWN" (§11.4.208(A):
#           never invented). `accepted` is ISO-8601 WITH numeric UTC offset;
#           `timezone` is the zone abbreviation.
#           EXACTLY-ONCE: the same (session, prompt-sha256) arriving twice within
#           LABEL_SYNC_LEDGER_DEDUPE_MS (default 2000 ms) is the SAME event
#           delivered twice (hook registered in two settings files) and is not
#           re-appended; the same text after the window is a new prompt.
#           OPTIONAL human-readable twin: when <ledger dir>/history.md exists and
#           contains the line `<!-- label-sync:request-history:insert -->`, a
#           rendered newest-first block is inserted right after that marker.
# Usage   : (a) executed: printf '%s' '{"session_id":..,"prompt":..,"track":..,
#           "alias":..,"model":..,"effort":..,"cwd":..}' | request_history_append.sh
#           (b) sourced (what label-sync-prompt.sh does — saves a process spawn and
#           two jq parses on the hot path): . request_history_append.sh;
#           rha_append <sid> <prompt> <track> <alias> <model> <effort> <cwd>
# Inputs  : stdin JSON (above); env LABEL_SYNC_REQUEST_LEDGER (explicit path),
#           CLAUDE_PROJECT_DIR (default <proj>/docs/requests/history.jsonl when
#           <proj>/docs/requests exists), LS_LEDGER_STATE (dir for dedupe state;
#           falls back to $TMPDIR/label-sync-ledger-<uid>).
# Outputs : none on stdout.
# Exit    : 0 appended | 0 deduped | 0 no ledger configured (the project has not
#           declared one — nothing is invented) | 1 write failed. Callers treat
#           every exit as non-fatal.
# Side-effects: appends to the ledger (+ optional md twin); dedupe state file.
# Deps    : bash (>=4.2: printf %(..)T, EPOCHREALTIME), jq, flock when present.
#           Hot-path discipline: no external process except jq/flock (each spawn
#           costs 15-25 ms on a loaded host; the hook latency budget is 150 ms).
# Cross-refs: §11.4.208, §11.4.210, §11.4.6 (UNKNOWN never fabricated),
#           docs/label-sync/HOOKS.md. The markdown/html/pdf exports of the
#           ledger (§11.4.65) are the project's docs-chain job, not this helper's.
# Classification: universal (§11.4.17).
set -u

# rha_append sid prompt track alias model effort cwd  — returns 0 (appended /
# deduped / no ledger configured) or 1 (write failed).
rha_append() {
  local sid="$1" prompt="$2" track="$3" alias="$4" model="$5" effort="$6" cwd="$7"
  command -v jq >/dev/null 2>&1 || return 0
  [ -n "$prompt" ] || return 0
  local ledger="${LABEL_SYNC_REQUEST_LEDGER:-}"
  if [ -z "$ledger" ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR/docs/requests" ]; then
    ledger="$CLAUDE_PROJECT_DIR/docs/requests/history.jsonl"
  fi
  [ -n "$ledger" ] || return 0          # project declared no ledger: nothing is invented
  local ldir="${ledger%/*}"; [ "$ldir" = "$ledger" ] && ldir="."
  [ -d "$ldir" ] || mkdir -p "$ldir" 2>/dev/null || return 1

  local state="${LS_LEDGER_STATE:-}"
  if [ -n "$state" ]; then state="$state/ledger-last"; [ -d "$state" ] || mkdir -p "$state" 2>/dev/null || state=""; fi
  if [ -z "$state" ]; then state="${TMPDIR:-/tmp}/label-sync-ledger-${UID:-0}"; [ -d "$state" ] || mkdir -p "$state" 2>/dev/null || state=""; fi
  local last=""; [ -n "$state" ] && last="$state/${sid:-nosession}"

  local now_us="${EPOCHREALTIME/./}" win="${LABEL_SYNC_LEDGER_DEDUPE_MS:-2000}"
  local now_ms=$(( now_us / 1000 ))
  local acc tz; printf -v acc '%(%Y-%m-%dT%H:%M:%S%z)T' -1; printf -v tz '%(%Z)T' -1

  _rha_do() {
    if [ -n "$last" ] && [ -f "$last" ]; then
      local lms lprompt
      { IFS= read -r lms; IFS= read -r -d '' lprompt; } <"$last" 2>/dev/null
      lprompt="${lprompt%$'\n'}"
      if [ "$lprompt" = "$prompt" ] && [ $(( now_ms - ${lms:-0} )) -lt "$win" ]; then return 0; fi
    fi
    jq -nc --arg acc "$acc" --arg tz "$tz" --arg sid "${sid:-UNKNOWN}" --arg p "$prompt" \
           --arg tr "${track:-UNKNOWN}" --arg al "${alias:-UNKNOWN}" --arg mo "${model:-UNKNOWN}" \
           --arg ef "${effort:-UNKNOWN}" --arg cwd "${cwd:-UNKNOWN}" \
      '{accepted:$acc,timezone:$tz,session_id:$sid,prompt:$p,prompt_kind:"verbatim",track:$tr,alias:$al,model:$mo,effort:$ef,cwd:$cwd,source:"label-sync-prompt-hook"}' \
      >>"$ledger" || return 1
    [ -n "$last" ] && printf '%s\n%s\n' "$now_ms" "$prompt" >"$last" 2>/dev/null
    _rha_md_twin
    return 0
  }
  _rha_md_twin() {
    local md="$ldir/history.md"
    [ -f "$md" ] || return 0
    grep -qF '<!-- label-sync:request-history:insert -->' "$md" 2>/dev/null || return 0
    local blk tmp
    blk="$(mktemp "${md}.blk.XXXXXX" 2>/dev/null)" || return 0
    tmp="$(mktemp "${md}.new.XXXXXX" 2>/dev/null)" || { rm -f "${blk:?}"; return 0; }
    {
      printf '### %s (%s) — session %s\n' "$acc" "$tz" "${sid:-UNKNOWN}"
      printf -- '- Track: %s | Alias: %s | Model: %s | Effort: %s\n' "${track:-UNKNOWN}" "${alias:-UNKNOWN}" "${model:-UNKNOWN}" "${effort:-UNKNOWN}"
      printf -- '- Request (verbatim):\n\n'
      printf '%s\n' "$prompt" | sed 's/^/    /'
      printf '\n'
    } >"$blk"
    awk -v blk="$blk" '{print} /<!-- label-sync:request-history:insert -->/ && !d { while ((getline l < blk) > 0) print l; d=1 }' "$md" >"$tmp" \
      && mv "$tmp" "$md"
    rm -f "${blk:?}" "${tmp:?}" 2>/dev/null
    return 0
  }

  local rc
  if command -v flock >/dev/null 2>&1; then
    ( flock -w 3 9 || exit 1; _rha_do ) 9>>"${ledger}.lock"; rc=$?
  else
    _rha_do; rc=$?
  fi
  return "$rc"
}

# executed directly: read the JSON from stdin
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  command -v jq >/dev/null 2>&1 || exit 0
  IN="$(cat 2>/dev/null)" || exit 0
  [ -n "$IN" ] || exit 0
  eval "$(printf '%s' "$IN" | jq -r '@sh "sid=\(.session_id // "") prompt=\(.prompt // "") track=\(.track // "") alias=\(.alias // "") model=\(.model // "") effort=\(.effort // "") cwd=\(.cwd // "")"' 2>/dev/null)" || exit 0
  rha_append "${sid:-}" "${prompt:-}" "${track:-}" "${alias:-}" "${model:-}" "${effort:-}" "${cwd:-}"
  exit $?
fi
