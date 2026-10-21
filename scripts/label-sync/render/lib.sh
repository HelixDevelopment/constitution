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
#           ls_sanitize TEXT [MAX]  STRICT, locale-independent output sanitiser (below)
#           ls_sanitize_into VAR TEXT [MAX]   same, assigned to VAR without a fork
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

# ls_sanitize TEXT [MAX_BYTES] — the ONE output sanitiser every renderer uses
# (statusline, title, tmux-status, watch-labels, labelrun banner, PS1 segment,
# shell-hook diagnostics). It works on BYTES under a function-local LC_ALL=C,
# so the result is identical whatever the caller's locale ([[:cntrl:]] under
# LC_ALL=C does NOT match UTF-8-encoded C1 controls — review finding 2). Removes:
#   * C0 controls 0x01-0x1f (ESC, BEL, CR, LF, TAB, ...) and DEL 0x7f
#     (NUL cannot occur: a bash string cannot hold it);
#   * C1 controls U+0080-U+009F as UTF-8 (c2 80 .. c2 9f; c2 9b = CSI, c2 9d = OSC);
#   * bidi/direction controls U+200E U+200F U+202A-U+202E U+2066-U+2069 U+061C;
#   * every byte that is not part of a well-formed UTF-8 sequence (overlongs,
#     surrogates, stray continuation bytes, truncated sequences);
# then caps the result at MAX_BYTES (default $LABEL_SYNC_SANITIZE_MAX or 512)
# on a character boundary. Pure bash, no fork.
__LS_UTF8_RE=$'^([\x01-\x7f]+|[\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|[\xe1-\xec\xee\xef][\x80-\xbf][\x80-\xbf]|\xed[\x80-\x9f][\x80-\xbf]|\xf0[\x90-\xbf][\x80-\xbf][\x80-\xbf]|[\xf1-\xf3][\x80-\xbf][\x80-\xbf][\x80-\xbf]|\xf4[\x80-\x8f][\x80-\xbf][\x80-\xbf])'
ls_sanitize() { local __r; ls_sanitize_into __r "${1-}" "${2-}"; printf '%s' "$__r"; }
# ls_sanitize_into VAR TEXT [MAX_BYTES] — same, result assigned to VAR (no fork).
ls_sanitize_into() {
  local LC_ALL=C __v="$1" __s="${2-}" __max="${3:-${LABEL_SYNC_SANITIZE_MAX:-512}}" __out="" __m
  case "$__max" in ''|*[!0-9]*) __max=512 ;; esac
  __s="${__s:0:$((__max * 4 + 64))}"                         # bound the work on huge input
  __s="${__s//[$'\x01'-$'\x1f'$'\x7f']/}"                  # C0 + DEL
  if [[ $__s != *[$'\x80'-$'\xff']* ]]; then             # pure ASCII fast path
    printf -v "$__v" '%s' "${__s:0:__max}"; return 0
  fi
  while [ -n "$__s" ]; do                                # keep well-formed UTF-8 only
    if [[ $__s =~ $__LS_UTF8_RE ]]; then
      __m="${BASH_REMATCH[1]}"; __s="${__s:${#__m}}"
      case "$__m" in                                   # per-sequence, so removals never join bytes
        $'\xc2'[$'\x80'-$'\x9f']) continue ;;           # C1 (c2 9b CSI, c2 9d OSC, ...)
        $'\xe2\x80'[$'\x8e'$'\x8f'$'\xaa'-$'\xae']) continue ;; # LRM RLM LRE RLE PDF LRO RLO
        $'\xe2\x81'[$'\xa6'-$'\xa9']) continue ;;       # LRI RLI FSI PDI
        $'\xd8\x9c') continue ;;                        # ALM
      esac
      if [ $(( ${#__out} + ${#__m} )) -gt "$__max" ]; then
        [[ $__m == [$'\x01'-$'\x7f']* ]] && __out+="${__m:0:$((__max - ${#__out}))}"
        break
      fi
      __out+="$__m"
    else
      __s="${__s:1}"                                       # drop one invalid byte
    fi
  done
  printf -v "$__v" '%s' "$__out"
}

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
#  * TEXT passed through ls_sanitize (C0/DEL/C1/bidi/invalid UTF-8, capped);
#  * TERM=dumb or empty TEXT  => no-op;
#  * explicit SINK (file) wins; else $LABEL_SYNC_TITLE_SINK; else stdout/stderr
#    ONLY if that fd is a tty — a non-tty never receives escape bytes;
#  * under tmux the plain OSC is accepted by tmux itself (sets the pane title);
#    PASSTHROUGH=1 additionally wraps it in tmux's DCS passthrough so the OUTER
#    terminal sees it (needs `set -g allow-passthrough on`);
#  * under GNU screen ($STY) the window-name sequence ESC k ... ESC \ is added.
ls_emit_title() {
  local text sink="${2:-${LABEL_SYNC_TITLE_SINK:-}}" pt="${3:-}" seq
  ls_sanitize_into text "${1-}" 256
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
