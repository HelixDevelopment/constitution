# shellcheck shell=bash
# scripts/label-sync/render/shell-integration.bash
#
# Purpose : Bash integration for label-sync. SOURCE it from an interactive
#           shell (instructions only — nothing here edits any rc file):
#               source /path/to/scripts/label-sync/render/shell-integration.bash
#           On each PROMPT it refreshes the terminal title (and the optional PS1
#           segment) from the live snapshot, and via a DEBUG trap it registers
#           the shell as a `shell` entity and each command as a `command`
#           entity (argv0 + salted digest only, see shell-hook.sh).
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
# Exports : LABEL_SYNC_SHELL_ID (parent id for `labelrun` and child tools),
#           LABEL_SYNC_SALT (per-shell random salt for command digests).
# Functions (public for tests): __ls_precmd, __ls_debug, __ls_exit; variable __LS_SEG.
# Exit    : sourcing returns 0; every hook function returns the previous $? or 0.
# Side-effects: appends to PROMPT_COMMAND, installs a DEBUG and an EXIT trap
#           (chaining any existing ones). Idempotent: sourcing twice is a no-op.
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
__LS_HOST="${HOSTNAME:-host}"; __LS_HOST="${__LS_HOST//[^A-Za-z0-9_.-]/_}"
export LABEL_SYNC_SHELL_ID="shell-${__LS_HOST}-$$-${EPOCHSECONDS:-0}"
export LABEL_SYNC_SALT="${RANDOM}${RANDOM}${RANDOM}-${EPOCHREALTIME:-0}"
__LS_SEG=""
__ls_label="" __ls_seen_seq="" __ls_first=1 __ls_in_prompt=0 __ls_started="" __ls_cmd_id="" __ls_n=0
__ls_hb_at=$SECONDS __ls_cmd_at=-9999

# detached, silent, never a job-control line, survives a terminal hangup
__ls_bg() { ( $__LS_SETSID "$@" >/dev/null 2>&1 </dev/null & ); }

__ls_precmd() {
  local __rc=$? s=""
  __ls_in_prompt=1
  if [ -n "$__ls_cmd_id" ]; then
    __ls_bg "$__LS_HOOK" cmd-end --id "$__ls_cmd_id"; __ls_cmd_id=""
  fi
  __ls_started=""
  { read -r s <"$__LS_DIR/seq"; } 2>/dev/null
  if [ "$__ls_first" = 1 ] || { [ -n "$s" ] && [ "$s" != "$__ls_seen_seq" ]; }; then
    __ls_first=0; __ls_seen_seq="$s"
    local new; new="$(ls_entity_label "$LABEL_SYNC_SHELL_ID" 2>/dev/null)"
    if [ -n "$new" ] && [ "$new" != "$__ls_label" ]; then
      __ls_label="$new"; __LS_SEG="$new"
      ls_emit_title "$new" "${LABEL_SYNC_TITLE_SINK:-}"
    fi
  fi
  if [ $((SECONDS - __ls_hb_at)) -ge "$__LS_HB" ]; then
    __ls_hb_at=$SECONDS
    __ls_bg "$__LS_HOOK" shell-beat --id "$LABEL_SYNC_SHELL_ID"
  fi
  __ls_in_prompt=0
  return $__rc
}

# DEBUG trap: runs before each simple command; only the FIRST command of a
# prompt cycle is recorded, and only if the rate cap allows. The command text
# is piped to the helper on STDIN (never an argument).
__ls_debug() {
  # only top-level command lines (FUNCNAME = (__ls_debug) interactively, (__ls_debug main) in a script)
  [ "${#FUNCNAME[@]}" -gt 1 ] && [ "${FUNCNAME[1]}" != main ] && return 0
  [ "$__ls_in_prompt" = 1 ] && return 0
  [ -n "$__ls_started" ] && return 0
  [[ $BASH_COMMAND == __ls_* ]] && return 0
  [ -n "${COMP_LINE:-}" ] && return 0
  local __cmd="$BASH_COMMAND"   # capture NOW: inside the subshell BASH_COMMAND is the printf itself
  __ls_started=1
  [ $((SECONDS - __ls_cmd_at)) -lt "$__LS_MIN" ] && return 0
  __ls_cmd_at=$SECONDS
  __ls_cmd_id="${LABEL_SYNC_SHELL_ID}-c$((++__ls_n))"
  ( printf '%s' "$__cmd" | $__LS_SETSID "$__LS_HOOK" cmd-start --id "$__ls_cmd_id" \
      --parent "$LABEL_SYNC_SHELL_ID" --pid "$$" --cwd "$PWD" >/dev/null 2>&1 & )
  return 0
}

__ls_exit() {
  [ -n "$__ls_cmd_id" ] && __ls_bg "$__LS_HOOK" cmd-end --id "$__ls_cmd_id"
  __ls_bg "$__LS_HOOK" shell-end --id "$LABEL_SYNC_SHELL_ID"
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
__ls_ts="$(__ls_trapstr DEBUG __ls_debug)"; trap "$__ls_ts" DEBUG
__ls_ts="$(__ls_trapstr EXIT __ls_exit)"; trap "$__ls_ts" EXIT
unset __ls_ts
if [ -n "${LABEL_SYNC_PS1:-}" ]; then
  PS1='${__LS_SEG:+$__LS_SEG }'"$PS1"
fi
__ls_bg "$__LS_HOOK" shell-start --id "$LABEL_SYNC_SHELL_ID" --pid "$$" --cwd "$PWD" --parent "$__LS_PARENT"
return 0 2>/dev/null || true
