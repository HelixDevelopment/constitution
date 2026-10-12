# shellcheck shell=bash disable=all
# scripts/label-sync/render/shell-integration.zsh
#
# Purpose : zsh integration for label-sync — the zsh counterpart of
#           shell-integration.bash (same behaviour, same cost model, same secret
#           policy: the command TEXT never leaves this shell; only argv0 is
#           handed to shell-hook.sh, and only if `whence` resolves it). SOURCE it (instructions only —
#           nothing here edits any rc file):
#               source /path/to/scripts/label-sync/render/shell-integration.zsh
#           precmd  : cheap `seq` compare (zsh builtin read, no fork); on change
#                     calls title.sh --entity <this shell> (one jq fork) and
#                     reaps the previous command entity; heartbeat every
#                     LABEL_SYNC_HEARTBEAT seconds (default 30), in background.
#           preexec : registers the command (rate-capped by
#                     LABEL_SYNC_CMD_MIN_INTERVAL, default 1 s) in background.
#           zshexit : unregisters the command + shell in background.
# Usage   : see above. Env: LABEL_SYNC_DIR, LABEL_SYNC_LABELCTL,
#           LABEL_SYNC_TITLE_SINK, LABEL_SYNC_CMD_MIN_INTERVAL, LABEL_SYNC_HEARTBEAT.
# Exports : LABEL_SYNC_SHELL_ID only (nothing secret).
# Exit    : sourcing returns 0; hooks never fail the prompt.
# Side-effects: add-zsh-hook precmd/preexec/zshexit; idempotent.
# Deps    : zsh>=5.0, jq (via title.sh), labelctl.sh.
# STATUS  : UNCONFIRMED — written against the zsh hook API but NOT executed:
#           zsh is not installed on the host that built it (§11.4.6). Validate
#           with `zsh -n` + a manual prompt cycle before relying on it.
# Cross-refs: §11.4.182, docs/label-sync/RENDERERS.md, shell-hook.sh.
# Classification: universal (§11.4.17).
[[ -n ${ZSH_VERSION-} ]] || return 0
(( ${+__LS_LOADED} )) && return 0
typeset -g __LS_LOADED=1
zmodload zsh/datetime 2>/dev/null
typeset -g __LS_RDIR="${${(%):-%x}:A:h}"
typeset -g __LS_DIR="${LABEL_SYNC_DIR:-$HOME/.local/state/constitution-label-sync}"
typeset -g __LS_HOOK="$__LS_RDIR/shell-hook.sh"
typeset -g __LS_MIN="${LABEL_SYNC_CMD_MIN_INTERVAL:-1}" __LS_HB="${LABEL_SYNC_HEARTBEAT:-30}"
typeset -g __LS_PARENT="${LABEL_SYNC_SHELL_ID-}"
typeset -g __LS_SETSID=""; (( $+commands[setsid] )) && __LS_SETSID="setsid"
export LABEL_SYNC_SHELL_ID="shell-${${HOST:-host}//[^A-Za-z0-9.-]/-}-$$-${EPOCHSECONDS:-0}"
typeset -g __ls_seen="" __ls_cmd_id="" __ls_first=1
typeset -gi __ls_n=0 __ls_hb_at=$SECONDS __ls_cmd_at=-9999

__ls_bg() { ( $__LS_SETSID "$@" >/dev/null 2>&1 </dev/null & ) }

__ls_precmd() {
  local s=""
  if [[ -n $__ls_cmd_id ]]; then __ls_bg "$__LS_HOOK" cmd-end --id "$__ls_cmd_id"; __ls_cmd_id=""; fi
  { read -r s < "$__LS_DIR/seq" } 2>/dev/null || :
  if (( __ls_first )) || [[ -n $s && $s != $__ls_seen ]]; then
    __ls_first=0; __ls_seen=$s
    "$__LS_RDIR/title.sh" --entity "$LABEL_SYNC_SHELL_ID" ${LABEL_SYNC_TITLE_SINK:+--sink "$LABEL_SYNC_TITLE_SINK"} 2>/dev/null
  fi
  if (( SECONDS - __ls_hb_at >= __LS_HB )); then
    __ls_hb_at=$SECONDS; __ls_bg "$__LS_HOOK" shell-beat --id "$LABEL_SYNC_SHELL_ID"
  fi
  return 0
}

__ls_preexec() { # $1 = the command line as typed; it NEVER leaves this shell
  (( SECONDS - __ls_cmd_at < __LS_MIN )) && return 0
  __ls_cmd_at=$SECONDS
  __ls_cmd_id="${LABEL_SYNC_SHELL_ID}-c$(( ++__ls_n ))"
  local a0="?" w
  local -a ws; ws=(${(z)1})
  for w in $ws; do
    if [[ $w =~ '^[A-Za-z_][A-Za-z0-9_]*=' ]]; then
      [[ $w == *[\"\'\`\$\\]* ]] && break; continue
    fi
    [[ $w == *[\"\'\`\$\\\(\)\{\}\<\>\|\;\&]* ]] && break
    whence -- "$w" >/dev/null 2>&1 && a0="$w"   # alias/function/builtin/file only
    break
  done
  __ls_bg "$__LS_HOOK" cmd-start --id "$__ls_cmd_id" --parent "$LABEL_SYNC_SHELL_ID" \
      --pid "$$" --cwd "$PWD" --argv0 "$a0"
  return 0
}

__ls_zshexit() {
  if [[ -n $__ls_cmd_id ]]; then __ls_bg "$__LS_HOOK" cmd-end --id "$__ls_cmd_id"; fi
  __ls_bg "$__LS_HOOK" shell-end --id "$LABEL_SYNC_SHELL_ID"
  return 0
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd __ls_precmd
add-zsh-hook preexec __ls_preexec
add-zsh-hook zshexit __ls_zshexit
__ls_bg "$__LS_HOOK" shell-start --id "$LABEL_SYNC_SHELL_ID" --pid "$$" --cwd "$PWD" --parent "$__LS_PARENT"
return 0
