#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-lib.sh
#
# Purpose : Shared, SOURCE-ONLY helper library for the label-sync Claude Code
#           hook scripts (label-sync-<event>.sh). Resolves the labelctl binary,
#           reads the hook payload once, derives the live label fields, and
#           provides the fail-soft / bounded-latency primitives every hook uses.
#           Nothing here prints to stdout on its own; hooks decide their output.
# Usage   : . "$(dirname "${BASH_SOURCE[0]}")/label-sync-lib.sh"      (sourced)
#           then: ls_init; ls_read_payload; ls_ctl <labelctl args...>
# Inputs  : stdin JSON of the hook event (Claude Code hook contract), env:
#           LABEL_SYNC_DIR        state dir (CONTRACT §1; tests: a temp dir)
#           LABEL_SYNC_BIN        binary cache dir (as labelctl.sh)
#           LABEL_SYNC_LABELER    canonical labeler (default: sibling multitrack)
#           LABEL_SYNC_DISABLE=1  kill switch: every hook becomes a silent no-op
#           LABEL_SYNC_NO_BUILD=1 never spawn the background binary build
#           LABEL_SYNC_CLAUDE_PID override the discovered claude process pid
#           LABEL_SYNC_HOOK_DEBUG=1 append hook diagnostics to $LABEL_SYNC_DIR/hooks/debug.log
#           LABEL_SYNC_CTL_TIMEOUT optional per-labelctl-call timeout seconds (default: none)
# Outputs : none by itself (functions set shell variables / return codes).
# Exit    : n/a (library). Hooks that source it ALWAYS exit 0 (fail-soft).
# Side-effects: creates $LABEL_SYNC_DIR/hooks/{pending,agentmap,sessions,ledger-last}
#           (mode 0700) for hook-private correlation state; may spawn ONE
#           detached `labelctl.sh --build` when the binary is missing/stale
#           (rate-limited to once per 60 s). Never writes under $HOME/.claude*.
# Deps    : bash, jq (payload parsing; absent => hooks degrade to silent no-op),
#           coreutils; flock/timeout used when present.
# Cross-refs: §11.4.182 (labels), §11.4.116 (event stream), §11.4.233
#           (level-triggered: every hook re-asserts state, none depends on
#           having seen the previous event), §11.4.201 (guards assert the real
#           condition), docs/label-sync/{CONTRACT,HOOKS}.md.
# Classification: universal (§11.4.17).

# Never leak "unbound variable"/errexit behaviour into the sourcing hook.
LS_HOOK_DIR="${BASH_SOURCE[0]:-$0}"; LS_HOOK_DIR="${LS_HOOK_DIR%/*}"
case "$LS_HOOK_DIR" in /*) ;; *) LS_HOOK_DIR="$PWD/$LS_HOOK_DIR" ;; esac
LS_DIR="${LS_HOOK_DIR%/*}"                    # .../scripts/label-sync
LS_CONST_DIR="${LS_DIR%/*}"; LS_CONST_DIR="${LS_CONST_DIR%/*}"   # constitution root

ls_dbg() { # debug line when LABEL_SYNC_HOOK_DEBUG=1 (never stdout, never stderr)
  [ "${LABEL_SYNC_HOOK_DEBUG:-}" = 1 ] || return 0
  [ -d "${LS_HOOKSTATE:-}" ] || return 0
  printf '%s %s %s\n' "$(date +%s)" "${LS_EVENT:-?}" "$*" >>"$LS_HOOKSTATE/debug.log" 2>/dev/null || true
}

# ls_init : resolve paths. Returns 1 (=> hook must exit 0 silently) when
# disabled or jq is absent. Does NOT create the state dir (labelctl does).
ls_init() {
  [ "${LABEL_SYNC_DISABLE:-}" = 1 ] && return 1
  command -v jq >/dev/null 2>&1 || return 1
  LS_STATE="${LABEL_SYNC_DIR:-${HOME:-/tmp}/.local/state/constitution-label-sync}"
  LS_HOOKSTATE="$LS_STATE/hooks"
  LS_BINDIR="${LABEL_SYNC_BIN:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/constitution-label-sync/bin}"
  LS_CTL_BIN="$LS_BINDIR/labelctl"
  : "${LABEL_SYNC_LABELER:=$LS_CONST_DIR/scripts/multitrack/track_branch_label.sh}"
  export LABEL_SYNC_LABELER LABEL_SYNC_DIR="$LS_STATE"
  return 0
}

# ls_have_bin : 0 when a usable labelctl exists. A missing binary kicks ONE
# detached background build (rate-limited) and returns 1: the hook then exits 0
# silently — the next event re-asserts state (level-triggered), nothing is lost.
# A STALE-but-present binary is still used (and a rebuild is kicked).
ls_have_bin() {
  if [ -x "$LS_CTL_BIN" ]; then
    if [ -n "$(find "$LS_DIR" \( -name '*.go' -o -name go.mod \) -newer "$LS_CTL_BIN" -print -quit 2>/dev/null)" ]; then
      ls_kick_build
    fi
    return 0
  fi
  ls_kick_build
  return 1
}

ls_kick_build() {
  [ "${LABEL_SYNC_NO_BUILD:-}" = 1 ] && return 0
  command -v go >/dev/null 2>&1 || return 0
  local mark="$LS_BINDIR/.hook-build-attempt" now last=0
  now=$(date +%s)
  [ -f "$mark" ] && last=$(stat -c %Y "$mark" 2>/dev/null || echo 0)
  [ $((now - last)) -lt 60 ] && return 0
  mkdir -p "$LS_BINDIR" 2>/dev/null || return 0
  : >"$mark" 2>/dev/null || true
  # detached, niced, no inherited stdio: can never delay or pollute the hook
  ( setsid nice -n 10 bash "$LS_DIR/labelctl.sh" --build >/dev/null 2>&1 </dev/null & ) >/dev/null 2>&1 || true
}

# ls_ctl <args...> : run labelctl; stdout passthrough, stderr dropped.
# NO `timeout` wrapper by default: on hosts whose coreutils `timeout` polls at
# 100 ms granularity (measured on this host: +100 ms per call, the whole latency
# budget) it is the dominant cost. The hook is bounded instead by the `timeout`
# field the installer writes into settings.json (5 s, enforced by Claude Code).
# Set LABEL_SYNC_CTL_TIMEOUT=<seconds> to opt into a per-call bound anyway.
ls_ctl() {
  if [ -n "${LABEL_SYNC_CTL_TIMEOUT:-}" ] && command -v timeout >/dev/null 2>&1; then
    timeout "$LABEL_SYNC_CTL_TIMEOUT" "$LS_CTL_BIN" "$@" 2>/dev/null
  else
    "$LS_CTL_BIN" "$@" 2>/dev/null
  fi
}

# ls_hookdir : create hook-private state dirs (0700).
ls_hookdir() {
  [ -d "$LS_HOOKSTATE/ledger-last" ] && [ -d "$LS_HOOKSTATE/sessions" ] && [ -d "$LS_HOOKSTATE/agentmap" ] && [ -d "$LS_HOOKSTATE/pending" ] && return 0
  ( umask 077; mkdir -p "$LS_HOOKSTATE/pending" "$LS_HOOKSTATE/agentmap" "$LS_HOOKSTATE/sessions" "$LS_HOOKSTATE/ledger-last" ) 2>/dev/null
}

# ls_read_payload : read stdin ONCE, parse the common fields with ONE jq call.
# Sets: LS_PAYLOAD LS_SID LS_CWD LS_EVENT LS_TOOL LS_TUID LS_DESC LS_SUBTYPE
#       LS_PROMPT LS_SOURCE LS_AGENT_ID LS_TOMODEL LS_TOOLMODEL
# Returns 1 when stdin is not a JSON object (hook then exits 0 silently).
ls_read_payload() {
  IFS= read -r -d '' LS_PAYLOAD || true       # builtin: no `cat` spawn
  [ -n "$LS_PAYLOAD" ] || return 1
  local parsed
  parsed="$(printf '%s' "$LS_PAYLOAD" | jq -r '
    select(type=="object") |
    @sh "LS_SID=\(.session_id // "")
         LS_CWD=\(.cwd // "")
         LS_EVENT=\(.hook_event_name // "")
         LS_TOOL=\(.tool_name // "")
         LS_TUID=\(.tool_use_id // "")
         LS_DESC=\(.tool_input.description // "")
         LS_SUBTYPE=\(.tool_input.subagent_type // "")
         LS_TOOLMODEL=\(.tool_input.model // "")
         LS_PROMPT=\(.prompt // .user_prompt // "")
         LS_SOURCE=\(.source // .reason // "")
         LS_AGENT_ID=\(.agent_id // "")
         LS_TOMODEL=\(.to_model // .model // "")"
  ' 2>/dev/null)" || return 1
  [ -n "$parsed" ] || return 1
  eval "$parsed"
  [ -n "$LS_SID" ] || LS_SID="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$LS_CWD" ] || LS_CWD="$PWD"
  return 0
}

# ls_claude_pid : pid of the owning claude process (liveness proof for the
# entity). Walks parents from $PPID looking for comm "claude". 0 = unknown.
ls_claude_pid() {
  if [ -n "${LABEL_SYNC_CLAUDE_PID:-}" ]; then printf '%s' "$LABEL_SYNC_CLAUDE_PID"; return; fi
  local p=$PPID i=0 comm rest
  while [ "$i" -lt 8 ] && [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
    read -r comm <"/proc/$p/comm" 2>/dev/null || break
    case "$comm" in claude|claude-*) printf '%s' "$p"; return ;; esac
    read -r rest <"/proc/$p/stat" 2>/dev/null || break
    rest="${rest##*) }"; set -- $rest
    p="${2:-}"; i=$((i + 1))
  done
  printf '0'
}

# ls_derive : run the canonical labeler for $LS_CWD with the session id exported
# (so its transcript-based model lookup resolves). Echoes the label line.
ls_derive() {
  [ -x "$LABEL_SYNC_LABELER" ] || [ -f "$LABEL_SYNC_LABELER" ] || return 1
  local out
  out="$( cd "$LS_CWD" 2>/dev/null || true
          CLAUDE_CODE_SESSION_ID="$LS_SID" bash "$LABEL_SYNC_LABELER" 2>/dev/null )" || return 1
  printf '%s' "${out%%$'\n'*}"          # first line, no head(1) spawn
}

# ls_parse_label "<(T<N>/<branch> - <alias>[ - <model>[ - <effort>]])...>"
# Sets LS_L_TRACK LS_L_BRANCH LS_L_ALIAS LS_L_MODEL LS_L_EFFORT ('' for '?'/absent).
# Returns 1 when the string does not START with a well-formed label.
ls_parse_label() {
  local s="$1" in rest f1 f2 f3 f4
  case "$s" in "(T"*) ;; *) return 1 ;; esac
  in="${s#\(}"; in="${in%%)*}"            # content of the first parentheses
  [ "$in" != "${s#\(}" ] || return 1       # a closing ')' must exist
  case "$in" in T*/*) ;; *) return 1 ;; esac
  LS_L_TRACK="${in#T}"; LS_L_TRACK="${LS_L_TRACK%%/*}"
  rest="${in#*/}"
  f1="${rest%% - *}"; [ "$f1" != "$rest" ] || return 1
  rest="${rest#* - }"
  f2="${rest%% - *}"
  if [ "$f2" != "$rest" ]; then rest="${rest#* - }"; f3="${rest%% - *}"
    if [ "$f3" != "$rest" ]; then f4="${rest#* - }"; else f4=""; fi
  else f3=""; f4=""; fi
  [ "$LS_L_TRACK" = '?' ] && LS_L_TRACK=""
  LS_L_BRANCH="$f1"; LS_L_ALIAS="$f2"; LS_L_MODEL="$f3"; LS_L_EFFORT="$f4"
  [ "$LS_L_BRANCH" = '?' ] && LS_L_BRANCH=""
  [ "$LS_L_ALIAS" = '?' ] && LS_L_ALIAS=""
  [ "$LS_L_MODEL" = '?' ] && LS_L_MODEL=""
  [ "$LS_L_EFFORT" = '?' ] && LS_L_EFFORT=""
  case "$LS_L_TRACK" in ''|*[!0-9]*) [ -z "$LS_L_TRACK" ] || return 1 ;; esac
  [ -n "$LS_L_ALIAS" ] || [ "$f2" = '?' ] || return 1
  return 0
}

# ls_model_short <model-id> : closed short-name mapping (same as the labeler).
ls_model_short() {
  case "$1" in
    *[Oo][Pp][Uu][Ss]*) printf opus ;;
    *[Ss][Oo][Nn][Nn][Ee][Tt]*) printf sonnet ;;
    *[Hh][Aa][Ii][Kk][Uu]*) printf haiku ;;
    *[Ff][Aa][Bb][Ll][Ee]*) printf fable ;;
    *) printf '%s' "$1" ;;
  esac
}

# ls_active_field <alias|model|effort> : one field of active.json ('' when
# none). Pure bash (no jq spawn — each spawn costs 15-25 ms on a loaded host).
ls_active_field() {
  local j re
  IFS= read -r -d '' j <"$LS_STATE/active.json" 2>/dev/null || true
  re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  [[ "$j" =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
  return 0
}
# ls_active_alias : the operator's ACTIVE alias from active.json ('' when none).
ls_active_alias() { ls_active_field alias; }

# ls_session_id : entity id of the current session.
ls_session_entity() { printf 'session:%s' "${LS_SID:-unknown}"; }

# ls_flock <file> <cmd...> : run cmd under an exclusive flock when available.
ls_flock() {
  local f="$1"; shift
  if command -v flock >/dev/null 2>&1; then ( flock -w 2 9 || exit 1; "$@" ) 9>"$f"; else "$@"; fi
}

# ls_ensure_session [source] : (re)assert the session entity. Idempotent and
# level-triggered: safe to call from ANY hook, including when SessionStart was
# missed (binary was building, state dir was unusable at that moment).
# Implements the CONTRACT §4.3 alias-change handling:
#   * previous alias for this session_id is remembered in hooks/sessions/<sid>.alias
#   * if it differs from the freshly derived alias (a RESUME under another
#     alias) the session is registered NON-following first — that makes the
#     state layer republish the whole subtree (same session_id + descendants)
#     to the new alias — then, unless LABEL_SYNC_NO_SWITCH_ON_RESUME=1, the
#     new alias is published as the ACTIVE alias (alias_switch) and the session
#     and its descendants are restored to FOLLOW it, so later operator
#     switches relabel them.
ls_ensure_session() {
  local src="${1:-hook}" id lab alias model effort track branch active follow prevf prev=""
  id="$(ls_session_entity)"
  lab="$(ls_derive)" || lab=""
  alias=""; model=""; effort=""; track=""; branch=""
  if [ -n "$lab" ] && ls_parse_label "$lab"; then
    alias="$LS_L_ALIAS"; model="$LS_L_MODEL"; effort="$LS_L_EFFORT"; track="$LS_L_TRACK"; branch="$LS_L_BRANCH"
  fi
  ls_hookdir
  prevf="$LS_HOOKSTATE/sessions/$LS_SID.alias"
  [ -f "$prevf" ] && prev="$(cat "$prevf" 2>/dev/null)"
  active="$(ls_active_alias)"
  follow=false; [ -n "$alias" ] && [ "$alias" = "$active" ] && follow=true
  local changed=""
  [ -n "$prev" ] && [ -n "$alias" ] && [ "$prev" != "$alias" ] && changed=1

  local -a a=(register --id "$id" --kind session --session "$LS_SID" --cwd "$LS_CWD" --source "hook:label-sync-$src"
              --state running --follow-active "$([ -n "$changed" ] && echo false || echo $follow)")
  [ -n "$track" ] && a+=(--track "$track")
  [ -n "$branch" ] && a+=(--branch "$branch")
  [ -n "$alias" ] && a+=(--alias "$alias")
  [ -n "$model" ] && a+=(--model "$model")
  [ -n "$effort" ] && a+=(--effort "$effort")
  local pid; pid="$(ls_claude_pid)"; [ "$pid" -gt 0 ] 2>/dev/null && a+=(--pid "$pid")
  ls_ctl "${a[@]}" >/dev/null || { ls_dbg "register session failed"; return 1; }
  [ -n "$alias" ] && printf '%s' "$alias" >"$prevf" 2>/dev/null

  # An ACTIVE alias with an empty model (an alias_switch that carried none) is
  # filled from THIS live session when it runs under that very alias — real data
  # (the model actually answering), never invented; an existing model is never
  # overwritten (the operator's explicit switch wins).
  if [ -z "$changed" ] && [ -n "$alias" ] && [ "$alias" = "$active" ] && [ -n "$model" ] \
     && [ -z "$(ls_active_field model)" ]; then
    local aeff; aeff="$(ls_active_field effort)"
    ls_ctl switch-alias --alias "$alias" --model "$model" ${aeff:+--effort "$aeff"} >/dev/null || true
  fi

  if [ -n "$changed" ]; then
    ls_dbg "alias change $prev -> $alias on session $LS_SID (source=$src)"
    if [ "${LABEL_SYNC_NO_SWITCH_ON_RESUME:-}" != 1 ]; then
      ls_ctl switch-alias --alias "$alias" ${model:+--model "$model"} ${effort:+--effort "$effort"} >/dev/null || true
      active="$alias"
    fi
    if [ "$alias" = "$active" ]; then
      # restore FOLLOW on the session and every descendant (they now equal active)
      local ids x
      ids="$(ls_ctl list --json | jq -r --arg sid "$LS_SID" --arg me "$id" '
        [ .entities[] | select(.id==$me or .session_id==$sid) | .id ] | unique | .[]' 2>/dev/null)"
      for x in $ids; do ls_ctl update --id "$x" --follow-active true >/dev/null || true; done
    fi
  fi
  return 0
}

# ls_emit_context <hookEventName> <text> : the documented hook JSON that injects
# additionalContext for the model (stdout, exit 0). Built in pure bash (JSON
# escaping of backslash, quote and the control characters that can occur in a
# one-line label) — no jq spawn on the hot path.
ls_emit_context() {
  local ev="$1" t="$2"
  t="${t//\\/\\\\}"; t="${t//\"/\\\"}"; t="${t//$'\n'/\\n}"; t="${t//$'\t'/\\t}"; t="${t//$'\r'/\\r}"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$ev" "$t"
}

# ls_hook_run <main-function> : run it fail-soft (stderr dropped, any failure
# swallowed), print its stdout once if non-empty, ALWAYS exit 0. A hook must
# never block, never delay (each call is bounded by the settings.json timeout) and never add noise.
ls_hook_run() {
  local out
  out="$("$1" 2>>"${LABEL_SYNC_HOOK_STDERR:-/dev/null}")" || true
  [ -n "$out" ] && printf '%s\n' "$out"
  exit 0
}
