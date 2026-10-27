#!/usr/bin/env bash
# scripts/label-sync/render/title.sh
#
# Purpose : Set the terminal window/tab title (OSC 0) to the live §11.4.182
#           label of an entity, a session, or an explicit text. Safe in a
#           non-tty (writes nothing, exit 0) and under tmux/screen.
# Usage   : title.sh [--text T | --entity ID | --session SID] [--sink FILE]
#                    [--passthrough]
#           default entity = $LABEL_SYNC_SHELL_ID, else session =
#           $CLAUDE_CODE_SESSION_ID. Nothing resolvable => title left alone.
# Inputs  : snapshot.json in $LABEL_SYNC_DIR (see CONTRACT.md); env TERM, TMUX,
#           STY, LABEL_SYNC_TITLE_SINK.
# Outputs : the escape sequence on the sink (file) or, if stdout/stderr is a
#           tty, on that tty. Nothing otherwise.
# Exit    : 0 always (a title is cosmetic and must never fail a caller).
# Side-effects: appends to the sink only.
# Deps    : bash, jq (only for --entity/--session lookups).
# Cross-refs: §11.4.182, docs/label-sync/RENDERERS.md, lib.sh (ls_emit_title).
# Classification: universal (§11.4.17).
set -u
RDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
. "$RDIR/lib.sh" || exit 0
text="" ent="" sid="" sink="" pt=""
while [ $# -gt 0 ]; do
  case "$1" in
    --text) text="${2:-}"; shift 2 ;;
    --entity) ent="${2:-}"; shift 2 ;;
    --session) sid="${2:-}"; shift 2 ;;
    --sink) sink="${2:-}"; shift 2 ;;
    --passthrough) pt=1; shift ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done
if [ -z "$text" ]; then
  if [ -z "$ent" ] && [ -z "$sid" ]; then
    ent="${LABEL_SYNC_SHELL_ID:-}"
    [ -n "$ent" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
  fi
  if [ -n "$ent" ]; then
    text="$(ls_entity_label "$ent")"
  elif [ -n "$sid" ] && [ -r "$(ls_dir)/snapshot.json" ]; then
    text="$(jq -r --arg s "$sid" '([.entities[]? | select(.session_id == $s)] | (map(select(.kind=="session")) + .) | first) | .label // empty' "$(ls_dir)/snapshot.json" 2>/dev/null)"
  fi
fi
ls_emit_title "$text" "$sink" "$pt"
exit 0
