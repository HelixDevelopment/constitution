# shellcheck shell=bash
# scripts/label-sync/render/shell-integration.bash
#
# Purpose : Bash integration for label-sync. SOURCE it from an interactive
#           shell (instructions only — nothing here edits any rc file):
#               source /path/to/scripts/label-sync/render/shell-integration.bash
#           On each PROMPT it refreshes the terminal title (and the optional PS1
#           segment) from the live snapshot, and via a DEBUG trap it registers
#           the shell as a `shell` entity and each command as a `command`
#           entity (argv0 only, and only if this shell can resolve it as a
#           command — the command TEXT never leaves the shell, see shell-hook.sh).
#           The title is refreshed at the NEXT PROMPT after a change (an alias
#           switch while a long command runs shows up when that command ends).
# Cost model (the prompt must never feel slower):
#           * every prompt: ONE builtin `read` of the tiny `seq` file and a
#             string compare — no fork — and nothing else while seq is unchanged;
#           * when seq changed: ONE `jq` (a fork, ~10 ms) and a title rewrite
#             only if the label text actually changed;
#           * registration / heartbeat / unregister run in a detached background
#             process (`( … & )`, setsid when present) so the prompt NEVER waits
#             on labelctl, a lock, or a dead state dir.
# Usage   : source this file. Optional env, read at source time:
#           LABEL_SYNC_PS1=1                 prepend the label to PS1
#           LABEL_SYNC_CMD_MIN_INTERVAL=1    min seconds between command registrations (rate cap)
#           LABEL_SYNC_HEARTBEAT=30          shell heartbeat period, seconds
#           LABEL_SYNC_TITLE_SINK=FILE       write title bytes to FILE (tests)
#           LABEL_SYNC_DIR / LABEL_SYNC_LABELCTL  see lib.sh
# Exports : LABEL_SYNC_SHELL_ID only (parent id for `labelrun` and child tools).
#           Nothing secret is exported (no salt: the digest was removed).
# Functions (public for tests): __ls_precmd, __ls_debug, __ls_exit; variable __LS_SEG.
# Exit    : sourcing returns 0; every hook function returns 0 and never trips
#           `set -e` / `set -u` in the user's shell (bash itself restores `$?`
#           around PROMPT_COMMAND, so the prompt's `$?` is unaffected); the DEBUG
#           trap preserves `$_` (installed as `__ls_debug "$_"`).
# Side-effects: appends to PROMPT_COMMAND, installs a DEBUG and an EXIT trap
#           (chaining any existing ones — they still run). Idempotent: sourcing
#           twice is a no-op.
# Deps    : bash>=4.4, jq, labelctl.sh.
# Cross-refs: §11.4.182, §11.4.116, docs/label-sync/RENDERERS.md, shell-hook.sh.
# Classification: universal (§11.4.17).

[ -n "${BASH_VERSION:-}" ] || return 0 2>/dev/null
[ -n "${__LS_LOADED:-}" ] && return 0
__LS_LOADED=1
__LS_RDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$__LS_RDIR/lib.sh" || return 0
__LS_DIR="$(ls_dir)"
__LS_HOOK="$__LS_RDIR/shell-hook.sh"
__LS_MIN="${LABEL_SYNC_CMD_MIN_INTERVAL:-1}"
__LS_HB="${LABEL_SYNC_HEARTBEAT:-30}"
__LS_SETSID=""; command -v setsid >/dev/null 2>&1 && __LS_SETSID="setsid"
__LS_PARENT="${LABEL_SYNC_SHELL_ID:-}"
__LS_HOST="${HOSTNAME:-host}"; __LS_HOST="${__LS_HOST//[^A-Za-z0-9.-]/-}"   # id grammar: no `_`
export LABEL_SYNC_SHELL_ID="shell-${__LS_HOST:0:60}-$$-${EPOCHSECONDS:-0}"
__LS_SEG=""
__ls_label="" __ls_seen_seq="" __ls_first=1 __ls_in_prompt=0 __ls_started="" __ls_cmd_id="" __ls_n=0 __ls_a0="?"
__ls_hb_at=$SECONDS __ls_cmd_at=-9999

# detached, silent, never a job-control line, survives a terminal hangup
__ls_bg() { ( $__LS_SETSID "$@" >/dev/null 2>&1 </dev/null & ); }

# Every statement below is errexit-safe: a missing seq file / failing jq must
# never end a `set -e` shell (review finding 6). Returns 0 always; bash restores
# the user's `$?` around PROMPT_COMMAND itself (measured: PS1 `$?` after `false`
# still reads 1 with a PROMPT_COMMAND that returns 0).
__ls_precmd() {
  local s="" new=""
  __ls_in_prompt=1
  if [ -n "$__ls_cmd_id" ]; then
    __ls_bg "$__LS_HOOK" cmd-end --id "$__ls_cmd_id"; __ls_cmd_id=""
  fi
  __ls_started=""
  { read -r s <"$__LS_DIR/seq"; } 2>/dev/null || :
  if [ "$__ls_first" = 1 ] || { [ -n "$s" ] && [ "$s" != "$__ls_seen_seq" ]; }; then
    __ls_first=0; __ls_seen_seq="$s"
    new="$(ls_entity_label "$LABEL_SYNC_SHELL_ID" 2>/dev/null)" || new=""
    if [ -n "$new" ] && [ "$new" != "$__ls_label" ]; then
      __ls_label="$new"
      ls_sanitize_into __LS_SEG "$new" 256        # PS1 segment: same strict sanitiser
      ls_emit_title "$new" "${LABEL_SYNC_TITLE_SINK:-}"
    fi
  fi
  if [ "$((SECONDS - __ls_hb_at))" -ge "$__LS_HB" ] 2>/dev/null; then
    __ls_hb_at=$SECONDS
    __ls_bg "$__LS_HOOK" shell-beat --id "$LABEL_SYNC_SHELL_ID"
  fi
  __ls_in_prompt=0
  return 0
}

# __ls_argv0 CMDLINE — sets __ls_a0 to the first word after leading VAR=value
# assignments, ONLY if this shell resolves it as a command (`type -t`: alias,
# keyword, function, builtin, file); otherwise `?`. A pasted token or a password
# typed as the first word is not a command, so it is never recorded (review
# finding 3). Quoted / expanded words fail closed to `?`. No fork.
__ls_argv0() {
  local c="${1-}" w n=0
  __ls_a0="?"
  while [ "$n" -lt 16 ]; do
    n=$((n+1))
    c="${c#"${c%%[![:space:]]*}"}"
    w="${c%%[[:space:]]*}"
    [ -n "$w" ] || return 0
    if [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      case "$w" in *[\"\'\`\$\\]*) return 0 ;; esac
      c="${c:${#w}}"; continue
    fi
    case "$w" in *[\"\'\`\$\\\(\)\{\}\<\>\|\;\&]*) return 0 ;; esac
    type -t -- "$w" >/dev/null 2>&1 || return 0
    __ls_a0="$w"; return 0
  done
  return 0
}

# DEBUG trap: runs before each simple command; only the FIRST command of a
# prompt cycle is recorded, and only if the rate cap allows. The command TEXT
# never leaves this shell: only the resolved argv0 is handed to the helper.
# Installed as `__ls_debug "$_"`, and the wrapper's LAST command is `: "$1"`, so
# the user's `$_` is exactly what it was before the trap (review finding 6).
__ls_debug() {
  # only top-level command lines (FUNCNAME = (__ls_debug) interactively, (__ls_debug main) in a script)
  if [ "${#FUNCNAME[@]}" -le 1 ] || [ "${FUNCNAME[1]}" = main ]; then __ls_debug_body; fi
  : "${1-}"
}
__ls_debug_body() {
  [ "$__ls_in_prompt" = 1 ] && return 0
  [ -n "$__ls_started" ] && return 0
  [[ $BASH_COMMAND == __ls_* ]] && return 0
  [ -n "${COMP_LINE:-}" ] && return 0
  __ls_started=1
  [ "$((SECONDS - __ls_cmd_at))" -lt "$__LS_MIN" ] 2>/dev/null && return 0
  __ls_cmd_at=$SECONDS
  __ls_cmd_id="${LABEL_SYNC_SHELL_ID}-c$((++__ls_n))"
  __ls_argv0 "$BASH_COMMAND"
  __ls_bg "$__LS_HOOK" cmd-start --id "$__ls_cmd_id" \
      --parent "$LABEL_SYNC_SHELL_ID" --pid "$$" --cwd "$PWD" --argv0 "$__ls_a0"
  return 0
}

__ls_exit() {
  if [ -n "$__ls_cmd_id" ]; then __ls_bg "$__LS_HOOK" cmd-end --id "$__ls_cmd_id"; fi
  __ls_bg "$__LS_HOOK" shell-end --id "$LABEL_SYNC_SHELL_ID"
  return 0
}

# --- install (idempotent; chains pre-existing traps / PROMPT_COMMAND) -------
if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
  PROMPT_COMMAND+=(__ls_precmd)
elif [ -n "${PROMPT_COMMAND:-}" ]; then
  PROMPT_COMMAND="${PROMPT_COMMAND%;};__ls_precmd"
else
  PROMPT_COMMAND="__ls_precmd"
fi
# Build the trap string for SIG that runs <fn> first, then any pre-existing
# handler. Computed in a function but INSTALLED at the top level of this file
# (a trap installed from inside a function would be traced into functions).
__ls_trapstr() { # <SIG> <our-function>
  local sig="$1" fn="$2" prev p=""
  prev="$(trap -p "$sig")"
  if [ -n "$prev" ]; then p="${prev#trap -- }"; p="${p% "$sig"}"; eval "p=$p"; fi
  if [ -n "$p" ]; then printf '%s; %s' "$fn" "$p"; else printf '%s' "$fn"; fi
}
__ls_ts="$(__ls_trapstr DEBUG '__ls_debug "$_"')"; trap "$__ls_ts" DEBUG
__ls_ts="$(__ls_trapstr EXIT __ls_exit)"; trap "$__ls_ts" EXIT
unset __ls_ts
if [ -n "${LABEL_SYNC_PS1:-}" ]; then
  PS1='${__LS_SEG:+$__LS_SEG }'"$PS1"
fi
__ls_bg "$__LS_HOOK" shell-start --id "$LABEL_SYNC_SHELL_ID" --pid "$$" --cwd "$PWD" --parent "$__LS_PARENT"
return 0 2>/dev/null || true
