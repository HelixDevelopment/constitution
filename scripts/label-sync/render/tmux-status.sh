#!/usr/bin/env bash
# scripts/label-sync/render/tmux-status.sh
#
# Purpose : Print the live label for tmux `status-right` / `status-left`. Meant to
#           be called by tmux's `#(...)` every `status-interval` seconds; it is a
#           pure snapshot READ (one jq fork), so the cost is negligible.
# Usage   : tmux-status.sh --pane-pid PID [--kind shell|command|...]
#           tmux-status.sh --entity ID | --session SID | --active
#           (install text: docs/label-sync/RENDERERS.md "tmux")
# Inputs  : snapshot.json in $LABEL_SYNC_DIR. `--pane-pid` matches the entity
#           whose registered pid equals the pane's shell pid (the shell
#           integrations register `--pid $$`); `shell` entities are preferred.
# Outputs : one line: the label (+ [stale]/[done] marker), or `?` when unknown
#           (never invented). `#` characters are replaced by `_` so the text can
#           never be re-interpreted as a tmux format/style sequence; every byte
#           first passes lib.sh ls_sanitize (C0/DEL/C1/bidi/invalid UTF-8, capped).
# Exit    : 0 always (a status segment must not break the status line).
# Side-effects: none. Deps: bash, jq.
# Cross-refs: §11.4.182, docs/label-sync/RENDERERS.md. Classification: universal (§11.4.17).
set -u
RDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
. "$RDIR/lib.sh" 2>/dev/null || { echo '?'; exit 0; }
pid="" kind="" ent="" sid="" active=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pane-pid) pid="${2:-}"; shift 2 ;; --kind) kind="${2:-}"; shift 2 ;;
    --entity) ent="${2:-}"; shift 2 ;; --session) sid="${2:-}"; shift 2 ;;
    --active) active=1; shift ;; *) shift ;;
  esac
done
snap="$(ls_dir)/snapshot.json"
out=""
if [ -r "$snap" ] && command -v jq >/dev/null 2>&1; then
  if [ -n "$active" ]; then
    out="$(jq -r '"\(.active.alias // "?") \(.active.model // "?") \(.active.effort // "?")"' "$snap" 2>/dev/null)"
  else
    out="$(jq -r --arg pid "${pid:-0}" --arg kind "$kind" --arg ent "$ent" --arg sid "$sid" '
      [.entities[]? | select(
          ($ent != "" and .id == $ent)
          or ($sid != "" and .session_id == $sid)
          or ($pid != "0" and $pid != "" and (.pid | tostring) == $pid and ($kind == "" or .kind == $kind)))]
      | (map(select(.kind == "shell")) + .) | first
      | if . then .label + (if .stale then " [stale]" elif .state == "done" then " [done]" else "" end) else empty end' "$snap" 2>/dev/null)"
  fi
fi
[ -n "$out" ] || out="?"
ls_sanitize_into out "$out"; printf '%s\n' "${out//#/_}"
exit 0
