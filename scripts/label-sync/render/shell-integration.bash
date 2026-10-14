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
#           * every prompt: ONE string compare of $PWD and ONE builtin `read` of
#             the repository's HEAD file (found once per directory change by a
#             pure-bash walk up to the nearest .git) — a `cd` or a `git checkout`
#             then triggers ONE background `shell-refresh` that re-derives the
#             shell entity's track/branch/cwd (review-2 finding 8); nothing
#             forks while neither changed;
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
__ls_ref_pwd="" __ls_head_file="" __ls_head="" __ls_rseq=0

# __ls_find_head : set __ls_head_file to the HEAD file of the repository that
# contains $PWD ('' outside a repository). Pure bash (no fork); a `.git` FILE
# (worktree / submodule) is followed through its "gitdir:" line.
__ls_find_head() {
  local d="$PWD" g="" l=""
  __ls_head_file=""
  while [ -n "$d" ]; do
    if [ -d "$d/.git" ]; then g="$d/.git"; break; fi
    if [ -f "$d/.git" ]; then
      { IFS= read -r l <"$d/.git"; } 2>/dev/null || l=""
      l="${l#gitdir: }"
      case "$l" in "") ;; /*) g="$l" ;; *) g="$d/$l" ;; esac
      break
    fi
    [ "$d" = / ] && break
    d="${d%/*}"; [ -n "$d" ] || d=/
  done
  [ -n "$g" ] && [ -r "$g/HEAD" ] && __ls_head_file="$g/HEAD"
  return 0
}

# __ls_place_changed : 0 when $PWD or the repository's HEAD changed since the
# last derivation (and records the new reference), 1 otherwise. Cheap.
__ls_place_changed() {
  local h="" ch=1
  if [ "$PWD" != "$__ls_ref_pwd" ]; then
    __ls_ref_pwd="$PWD"; __ls_find_head; ch=0                 # MUT:refreshcwd
  fi
  if [ -n "$__ls_head_file" ]; then { IFS= read -r h <"$__ls_head_file"; } 2>/dev/null || h=""; fi
  if [ "$h" != "$__ls_head" ]; then __ls_head="$h"; ch=0; fi  # MUT:refreshhead
  return "$ch"
}

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
  if __ls_place_changed; then
    __ls_rseq=$((__ls_rseq + 1))   # re-review 6: orders the detached refreshes
    __ls_bg "$__LS_HOOK" shell-refresh --id "$LABEL_SYNC_SHELL_ID" --cwd "$PWD" --seq "$__ls_rseq"
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
  [[ $BASH_COMMAND == __ls_* || $BASH_COMMAND == *__LS_DBG_INSTALL* ]] && return 0
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
# __ls_trapstr SIG FN "TRAP -P OUTPUT": __ls_ts = FN, then any pre-existing handler.
__ls_trapstr() {
  local sig="$1" fn="$2" prev="${3%$'\n'}" p=""
  __ls_ts="$fn"
  if [ -n "$prev" ]; then p="${prev#trap -- }"; p="${p% "$sig"}"; eval "p=$p"; fi
  if [ -n "$p" ]; then __ls_ts="$fn; $p"; fi
  return 0
}
# DEBUG: bash unsets the DEBUG trap while a file is `source`d (unless `set -T`)
# and a DEBUG trap set by the sourced file REPLACES the saved one — so a user's
# DEBUG trap cannot even be read from here (measured: `trap -p DEBUG` prints
# nothing), and installing ours here silently dropped it (review finding 6).
# Interactive shells therefore install it at the FIRST PROMPT, from top-level
# PROMPT_COMMAND code, where `trap -p DEBUG` sees the user's trap and chains it.
# Non-interactive shells (scripts) install it now; a script's earlier DEBUG
# trap is chained only under `set -T` (otherwise invisible — documented).
__LS_DBG_INSTALL='__ls_tp="$(trap -p DEBUG)"; __ls_trapstr DEBUG "__ls_debug \"\$_\"" "$__ls_tp"; trap -- "$__ls_ts" DEBUG; unset __ls_tp __ls_ts __LS_DBG_INSTALL'
__ls_pc=__ls_precmd
if [[ $- == *i* ]]; then __ls_pc='eval "${__LS_DBG_INSTALL-}";__ls_precmd'; fi
if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
  PROMPT_COMMAND+=("$__ls_pc")
elif [ -n "${PROMPT_COMMAND:-}" ]; then
  PROMPT_COMMAND="${PROMPT_COMMAND%;};$__ls_pc"
else
  PROMPT_COMMAND="$__ls_pc"
fi
unset __ls_pc
if [[ $- != *i* ]]; then eval "$__LS_DBG_INSTALL"; fi
# EXIT: `trap -p EXIT` is read at this file's top level through a private temp
# file (no command substitution, no function), then chained the same way.
__ls_tf="$(mktemp "${TMPDIR:-/tmp}/ls_trap.XXXXXX" 2>/dev/null)" || __ls_tf=""
__ls_tp=""
if [ -n "$__ls_tf" ]; then trap -p EXIT >"$__ls_tf" 2>/dev/null; IFS= read -r -d '' __ls_tp <"$__ls_tf" || :; rm -f -- "$__ls_tf"; fi
__ls_trapstr EXIT __ls_exit "$__ls_tp"; trap "$__ls_ts" EXIT
unset __ls_ts __ls_tp __ls_tf
if [ -n "${LABEL_SYNC_PS1:-}" ]; then
  PS1='${__LS_SEG:+$__LS_SEG }'"$PS1"
fi
__ls_place_changed || :          # reference = what shell-start derives below
__ls_bg "$__LS_HOOK" shell-start --id "$LABEL_SYNC_SHELL_ID" --pid "$$" --cwd "$PWD" --parent "$__LS_PARENT"
return 0 2>/dev/null || true
