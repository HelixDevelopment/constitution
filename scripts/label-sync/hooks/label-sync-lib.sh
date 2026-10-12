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
#           LABEL_SYNC_DEBUG=1    let hook stderr through (ledger failures are reported there)
#           LABEL_SYNC_CTL_TIMEOUT optional per-labelctl-call timeout seconds (default: none)
#           LABEL_SYNC_HOOK_LOCK_TIMEOUT writer-lock wait per call (default 500ms)
# Outputs : none by itself (functions set shell variables / return codes).
# Exit    : n/a (library). Hooks that source it ALWAYS exit 0 (fail-soft).
# Side-effects: creates $LABEL_SYNC_DIR/hooks/{pending,agentmap,ledger-last}
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
# Every call carries a SHORT writer-lock bound (review finding 9): the core's
# default wait is 2 s per call, so a stuck/slow writer could stall a prompt by
# seconds; with --lock-timeout 500ms a busy lock makes labelctl exit 2 at once
# and the hook still exits 0 (the next event re-asserts — level-triggered).
# The child is waited for synchronously and is bounded by that timeout, so a
# hook killed mid-call cannot leave a labelctl behind for more than ~0.5 s.
# NO `timeout` wrapper by default: on hosts whose coreutils `timeout` polls at
# 100 ms granularity it is the dominant cost. Set LABEL_SYNC_CTL_TIMEOUT=<s>
# to opt into a per-call bound anyway; LABEL_SYNC_HOOK_LOCK_TIMEOUT overrides
# the 500ms lock bound (Go duration or seconds).
ls_ctl() {
  local lt="${LABEL_SYNC_HOOK_LOCK_TIMEOUT:-500ms}"
  if [ -n "${LABEL_SYNC_CTL_TIMEOUT:-}" ] && command -v timeout >/dev/null 2>&1; then
    timeout "$LABEL_SYNC_CTL_TIMEOUT" "$LS_CTL_BIN" --lock-timeout "$lt" "$@" 2>/dev/null
  else
    "$LS_CTL_BIN" --lock-timeout "$lt" "$@" 2>/dev/null
  fi
}

# ls_hookdir : create hook-private state dirs (0700).
ls_hookdir() {
  [ -d "$LS_HOOKSTATE/ledger-last" ] && [ -d "$LS_HOOKSTATE/agentmap" ] && [ -d "$LS_HOOKSTATE/pending" ] && return 0
  ( umask 077; mkdir -p "$LS_HOOKSTATE/pending" "$LS_HOOKSTATE/agentmap" "$LS_HOOKSTATE/ledger-last" ) 2>/dev/null
}

# ls_drop_pending_dir <sid> : remove the regular files of hooks/pending/<sid>/
# one by one, then rmdir it. Never recursive, never follows a symlink out (a
# symlinked entry is unlinked, its target untouched); refuses an invalid sid.
ls_drop_pending_dir() {
  ls_valid_id "${1:-}" || return 0
  local d="$LS_HOOKSTATE/pending/$1" f
  [ -d "$d" ] && [ ! -L "$d" ] || return 0
  for f in "$d"/*; do
    { [ -f "$f" ] || [ -L "$f" ]; } && rm -f -- "$f"
  done
  rmdir -- "$d" 2>/dev/null
  return 0
}

# ls_read_payload : read stdin ONCE, parse the common fields with ONE jq call.
# Sets: LS_PAYLOAD LS_SID LS_CWD LS_EVENT LS_TOOL LS_TUID LS_DESC LS_SUBTYPE
#       LS_PROMPT LS_PROMPT_BIG LS_SOURCE LS_AGENT_ID LS_ATYPE LS_TOMODEL LS_TOOLMODEL
# A prompt longer than 65536 characters is NOT copied into LS_PROMPT (each bash
# copy of an 8 MiB string costs ~0.5 s): LS_PROMPT_BIG=1 tells the prompt hook to
# stream it from LS_PAYLOAD straight into the ledger's temp file with jq.
# Returns 1 when stdin is not a JSON object, or when ANY id field is present but
# not a safe id (hook then exits 0 silently, doing nothing).
#
# Id safety (review finding 3): session_id / agent_id / tool_use_id end up in
# file names under $LS_HOOKSTATE and in entity ids, so a value such as
# `../../../x`, a space, a newline or a NUL would escape the state dir (a
# `rm` of a stdin-derived path deleted a directory outside it). An id is used
# ONLY if it matches ^[A-Za-z0-9_-]{1,128}$, checked INSIDE jq on the raw JSON
# string with \A..\z anchors (Oniguruma's ^/$ are LINE anchors; and bash would
# silently drop a NUL, turning "a\u0000b" into the valid-looking "ab").
LS_ID_RE='^[A-Za-z0-9_-]{1,128}$'
ls_valid_id() { [[ "$1" =~ $LS_ID_RE ]]; }
ls_read_payload() {
  # `$(cat)`, NOT `read -d ''`: Claude Code feeds stdin through a PIPE, where
  # bash's read builtin consumes ONE BYTE PER SYSCALL (measured: 4.1 s for an
  # 8 MiB prompt payload vs 0.17 s with cat; review finding 2). One small spawn.
  LS_PAYLOAD="$(cat 2>/dev/null)" || true
  [ -n "$LS_PAYLOAD" ] || return 1
  local parsed LS_BADID=""
  parsed="$(printf '%s' "$LS_PAYLOAD" | jq -r '
    def okid: type=="string" and test("\\A[A-Za-z0-9_-]{1,128}\\z");
    def idf($k): (.[$k] // "") as $v | if $v == "" then "" elif ($v|okid) then $v else null end;
    def s: if type=="string" then . else "" end;
    select(type=="object") |
    (idf("session_id")) as $sid | (idf("agent_id")) as $aid | (idf("tool_use_id")) as $tuid |
    @sh "LS_SID=\($sid // "")
         LS_BADID=\(if ($sid == null or $aid == null or $tuid == null) then "1" else "" end)
         LS_CWD=\(.cwd // "" | s)
         LS_EVENT=\(.hook_event_name // "" | s)
         LS_TOOL=\(.tool_name // "" | s)
         LS_TUID=\($tuid // "")
         LS_DESC=\(.tool_input.description // "" | s)
         LS_SUBTYPE=\(.tool_input.subagent_type // "" | s)
         LS_TOOLMODEL=\(.tool_input.model // "" | s)
         LS_PROMPT=\(.prompt // .user_prompt // "" | s | if length <= 65536 then . else "" end)
         LS_PROMPT_BIG=\(.prompt // .user_prompt // "" | s | if length > 65536 then "1" else "" end)
         LS_SOURCE=\(.source // .reason // "" | s)
         LS_AGENT_ID=\($aid // "")
         LS_ATYPE=\(.agent_type // "" | s)
         LS_TOMODEL=\(.to_model // .model // "" | s)"
  ' 2>/dev/null)" || return 1
  [ -n "$parsed" ] || return 1
  eval "$parsed"
  [ -z "$LS_BADID" ] || { ls_dbg "rejected payload: unsafe id"; return 1; }
  # No usable session id => nothing to correlate: no-op (a shared
  # "session:unknown" entity would merge unrelated sessions into one).
  [ -n "$LS_SID" ] || LS_SID="${CLAUDE_CODE_SESSION_ID:-}"
  ls_valid_id "$LS_SID" || return 1
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

# ls_session_id : entity id of the current session.
ls_session_entity() { printf 'session:%s' "$LS_SID"; }

# ls_flock <file> <cmd...> : run cmd under an exclusive flock when available.
ls_flock() {
  local f="$1"; shift
  if command -v flock >/dev/null 2>&1; then ( flock -w 2 9 || exit 1; "$@" ) 9>"$f"; else "$@"; fi
}

# ls_ensure_session [source] : (re)assert the session entity. Idempotent and
# level-triggered: safe to call from ANY hook, including when SessionStart was
# missed (binary was building, state dir was unusable at that moment).
#
# Binding (CONTRACT §4.2, review finding 1): a session whose alias the labeler
# DERIVES from this process (CLAUDE_CONFIG_DIR) is registered PINNED to it
# (--follow-active false) — per-process truth. Two terminals on two aliases
# therefore each keep their own label through any number of operator
# `alias_switch` events; their alias-less children inherit it through the
# session. Only a session whose alias cannot be derived follows the ACTIVE
# context. A resume under another alias simply re-registers the session with
# the new alias: the core re-renders its whole subtree, no republish step.
# The hooks NEVER read or write active.json (no check-then-act race): only the
# CLI signal (label-sync-alias-switch.sh) and the toolkit wrapper publish it.
ls_ensure_session() {
  local src="${1:-hook}" id lab alias="" model="" effort="" track="" branch=""
  id="$(ls_session_entity)"
  lab="$(ls_derive)" || lab=""
  if [ -n "$lab" ] && ls_parse_label "$lab"; then
    alias="$LS_L_ALIAS"; model="$LS_L_MODEL"; effort="$LS_L_EFFORT"; track="$LS_L_TRACK"; branch="$LS_L_BRANCH"
  fi
  # SessionStart carries the live model itself (2.1.296 binary: {source,
  # agent_type, model, session_title}); the session-start hook hands it over in
  # LS_PAYLOAD_MODEL and it wins over the labeler's transcript lookup.
  [ -n "${LS_PAYLOAD_MODEL:-}" ] && model="$(ls_model_short "$LS_PAYLOAD_MODEL")"
  local -a a=(register --id "$id" --kind session --session "$LS_SID" --cwd "$LS_CWD" --source "hook:label-sync-$src"
              --state running)
  if [ -n "$alias" ]; then a+=(--alias "$alias" --follow-active false); else a+=(--follow-active true); fi
  [ -n "$track" ] && a+=(--track "$track")
  [ -n "$branch" ] && a+=(--branch "$branch")
  [ -n "$model" ] && a+=(--model "$model")
  [ -n "$effort" ] && a+=(--effort "$effort")
  local pid; pid="$(ls_claude_pid)"; [ "$pid" -gt 0 ] 2>/dev/null && a+=(--pid "$pid")
  ls_ctl "${a[@]}" >/dev/null || { ls_dbg "register session failed (source=$src)"; return 1; }
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
  local out err="${LABEL_SYNC_HOOK_STDERR:-/dev/null}"
  # LABEL_SYNC_DEBUG=1: diagnostics (e.g. a ledger row that could not be
  # stored) reach the hook's stderr, which Claude Code shows in its transcript.
  [ "${LABEL_SYNC_DEBUG:-}" = 1 ] && [ -z "${LABEL_SYNC_HOOK_STDERR:-}" ] && err=/dev/stderr
  out="$("$1" 2>>"$err")" || true
  [ -n "$out" ] && printf '%s\n' "$out"
  exit 0
}
