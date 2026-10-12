# shellcheck shell=bash
# scripts/label-sync/render/lib.sh
#
# Purpose : Shared helpers for the label-sync RENDERERS (statusline, title,
#           shell integration, tmux-status, watch-labels, labelrun). SOURCED,
#           never executed. Pure bash + jq; defines functions only (no side
#           effects at source time except two read-only variable assignments).
# Usage   : . "$(dirname "$0")/lib.sh"
#           ls_dir                  state dir (honours $LABEL_SYNC_DIR)
#           ls_labelctl             path of labelctl.sh (honours $LABEL_SYNC_LABELCTL)
#           ls_entity_label ID      rendered label of entity ID (+ [stale]/[done] marker)
#           ls_emit_title TEXT [SINK] [PASSTHROUGH]   write an OSC 0 title (see title.sh)
#           ls_sanitize TEXT        strip control characters
# Inputs  : env LABEL_SYNC_DIR, LABEL_SYNC_LABELCTL, LABEL_SYNC_TITLE_SINK, TERM,
#           TMUX, STY.
# Outputs : functions print to stdout; ls_emit_title writes the escape sequence.
# Exit    : functions return 0 on success, 1 when there is nothing to report
#           (no snapshot / no such entity) — callers treat that as "unknown"
#           and render an honest `?`, never an invented value (§11.4.6).
# Side-effects: ls_emit_title appends to its sink only.
# Deps    : bash>=4, jq (ls_entity_label only).
# Cross-refs: §11.4.182, docs/label-sync/CONTRACT.md §1-§3, §11.4.18.
# Classification: universal (§11.4.17).

__LS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

ls_dir() { printf '%s' "${LABEL_SYNC_DIR:-${HOME:-/tmp}/.local/state/constitution-label-sync}"; }

ls_labelctl() { printf '%s' "${LABEL_SYNC_LABELCTL:-$__LS_LIB_DIR/../labelctl.sh}"; }

# Strip every control character (ESC, BEL, CR, LF, ...) so a hostile or odd
# branch/name can never inject a terminal escape sequence.
ls_sanitize() { local s="$1"; printf '%s' "${s//[[:cntrl:]]/}"; }

# label (+ marker) of entity $1 from the atomically-replaced snapshot.
ls_entity_label() {
  local snap; snap="$(ls_dir)/snapshot.json"
  [ -r "$snap" ] || return 1
  jq -r --arg id "$1" '
    first(.entities[]? | select(.id == $id))
    | .label + (if .stale then " [stale]" elif .state == "done" then " [done]" else "" end)' \
    "$snap" 2>/dev/null
}

# OSC 0 (icon + window title). Safe by construction:
#  * control chars stripped from TEXT;
#  * TERM=dumb or empty TEXT  => no-op;
#  * explicit SINK (file) wins; else $LABEL_SYNC_TITLE_SINK; else stdout/stderr
#    ONLY if that fd is a tty — a non-tty never receives escape bytes;
#  * under tmux the plain OSC is accepted by tmux itself (sets the pane title);
#    PASSTHROUGH=1 additionally wraps it in tmux's DCS passthrough so the OUTER
#    terminal sees it (needs `set -g allow-passthrough on`);
#  * under GNU screen ($STY) the window-name sequence ESC k ... ESC \ is added.
ls_emit_title() {
  local text="${1//[[:cntrl:]]/}" sink="${2:-${LABEL_SYNC_TITLE_SINK:-}}" pt="${3:-}" seq
  [ "${TERM:-}" = dumb ] && return 0
  [ -n "$text" ] || return 0
  seq=$'\033]0;'"$text"$'\007'
  [ -n "${STY:-}" ] && seq+=$'\033k'"$text"$'\033\\'
  if [ -n "$pt" ] && [ -n "${TMUX:-}" ]; then
    seq=$'\033Ptmux;'"${seq//$'\033'/$'\033\033'}"$'\033\\'
  fi
  if [ -n "$sink" ]; then
    { printf '%s' "$seq" >>"$sink"; } 2>/dev/null
  elif [ -t 1 ]; then
    printf '%s' "$seq"
  elif [ -t 2 ]; then
    printf '%s' "$seq" >&2
  fi
  return 0
}
