#!/usr/bin/env bash
# scripts/label-sync/adapters/lib/adapter_lib.sh
#
# Purpose : SOURCE-ONLY helper library shared by every non-Claude CLI-agent
#           adapter (kimi, opencode, crush, aider, codex, gemini, qwen, the
#           generic wrapper). Turns "agent X started / is working / went idle /
#           ended" into labelctl calls against the shared label bus
#           (docs/label-sync/CONTRACT.md), so EVERY agent shows a live
#           `(T<N>/<branch> - <alias> - <model> - <effort>)` label.
#           All logic lives here once; the per-agent scripts only translate
#           THEIR native hook payload into these functions.
# Usage   : . "$(dirname "${BASH_SOURCE[0]}")/../lib/adapter_lib.sh"
#             al_init || exit 0
#             al_upsert  AGENT SESSION CWD MODEL EFFORT STATE [PARENT] [KIND]
#             al_done    AGENT SESSION
#             al_entity_id AGENT SESSION      -> prints the entity id
#             al_find_pid  AGENT              -> prints the agent's pid or nothing
# Inputs  : env LABEL_SYNC_DIR            state dir (CONTRACT §1; tests: temp dir)
#           LABEL_SYNC_AGENT_ALIAS        alias to show (default: the agent name)
#           LABEL_SYNC_FOLLOW_ACTIVE=1    follow the operator's active alias
#                                         (default: NOT following — a non-Claude
#                                         agent's own identity is per-process
#                                         truth, CONTRACT §4.2)
#           LABEL_SYNC_ENTITY_ID          force the entity id (wrapper -> hooks)
#           LABEL_SYNC_AGENT_PID          the agent's pid when the caller knows it
#                                         (default: nearest ancestor named like the agent)
#           LABEL_SYNC_DISABLE=1          kill switch: every adapter is a no-op
#           LABEL_SYNC_LABELCTL           labelctl.sh path override
#           LABEL_SYNC_BIN, LABEL_SYNC_LABELER   as labelctl.sh
# Outputs : none (functions set/return values). NEVER prints on its own.
# Exit    : functions return 0 even when the bus is unusable (FAIL-SOFT: a label
#           is cosmetic and an adapter must never break the agent it observes,
#           §11.4.6 — the failure is recorded to $LABEL_SYNC_DIR/adapters/debug.log
#           only when LABEL_SYNC_ADAPTER_DEBUG=1). al_init returns 1 when the
#           adapter should do nothing (disabled / labelctl absent).
# Side-effects: labelctl register/update/heartbeat/unregister. Command lines,
#           prompts, tool inputs and file contents are NEVER read from payloads
#           by the adapters, so they cannot be recorded (§11.4.10): only ids,
#           cwd, model, effort and state cross into the bus.
# Deps    : bash>=4, coreutils; labelctl.sh (builds the Go binary on first use).
# Cross-refs: §11.4.182, §11.4.116, §11.4.233 (level-triggered: every call
#           re-asserts the whole entity, none depends on a previous call),
#           §11.4.228(D), §11.4.18, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).

__AL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
AL_LS_DIR="$(cd "$__AL_LIB_DIR/../.." && pwd)"          # scripts/label-sync

al_dbg() { # debug line (never stdout/stderr)
  [ "${LABEL_SYNC_ADAPTER_DEBUG:-}" = 1 ] || return 0
  local d="${LABEL_SYNC_DIR:-${HOME:-/tmp}/.local/state/constitution-label-sync}/adapters"
  mkdir -p "$d" 2>/dev/null && printf '%s %s\n' "$(date +%s)" "$*" >>"$d/debug.log" 2>/dev/null
  return 0
}

# al_init : resolve labelctl. Returns 1 => the caller must exit 0 silently.
al_init() {
  [ "${LABEL_SYNC_DISABLE:-}" = 1 ] && return 1
  if [ -n "${LABEL_SYNC_BIN:-}" ]; then AL_BINDIR="$LABEL_SYNC_BIN"
  else . "$AL_LS_DIR/bincache.sh" 2>/dev/null || return 1; ls_bincache_into AL_BINDIR "$AL_LS_DIR"; fi  # per-checkout cache
  AL_CTL_SH="${LABEL_SYNC_LABELCTL:-$AL_LS_DIR/labelctl.sh}"
  : "${LABEL_SYNC_LABELER:=$AL_LS_DIR/../multitrack/track_branch_label.sh}"
  export LABEL_SYNC_LABELER
  [ -x "$AL_CTL_SH" ] || [ -x "$AL_BINDIR/labelctl" ] || return 1
  return 0
}

# al_ctl <labelctl args> : fast path = the cached binary, else the building wrapper.
al_ctl() {
  if [ -x "$AL_BINDIR/labelctl" ] && [ -z "${LABEL_SYNC_LABELCTL:-}" ]; then
    "$AL_BINDIR/labelctl" "$@" 2>/dev/null
  else
    "$AL_CTL_SH" "$@" 2>/dev/null
  fi
}

# al_safe TEXT [MAX] : keep [A-Za-z0-9._-], map the rest to '_', bound the length
# (a long tail is replaced by a short hash so distinct ids stay distinct).
al_safe() {
  local s="${1//[^A-Za-z0-9._-]/_}" max="${2:-64}" h
  if [ "${#s}" -gt "$max" ]; then
    h="$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
    s="${s:0:$((max - 9))}-$h"
  fi
  printf '%s' "$s"
}

al_entity_id() { # AGENT SESSION
  if [ -n "${LABEL_SYNC_ENTITY_ID:-}" ]; then printf '%s' "$LABEL_SYNC_ENTITY_ID"; return 0; fi
  printf '%s-%s' "$(al_safe "$1" 24)" "$(al_safe "${2:-unknown}")"
}

# al_find_pid AGENT : walk the parent chain of this process; print the first
# ancestor whose comm or argv[0..1] mentions AGENT. Prints nothing when none is
# found (the entity then carries no pid and goes stale on TTL — honest).
al_find_pid() {
  local want="$1" p="${PPID:-0}" i=0 comm a0 a1
  while [ "$p" -gt 1 ] 2>/dev/null && [ "$i" -lt 12 ]; do
    comm="$(cat "/proc/$p/comm" 2>/dev/null)" || break
    # argv[0] and argv[1] basenames: covers `agent`, `python3 /x/aider`, `node /x/crush`.
    # NOT a substring match: the hook's own `sh -c "<.../kimi-hook.sh>"` parent
    # must never be mistaken for the agent.
    { IFS= read -r -d '' a0; IFS= read -r -d '' a1; } <"/proc/$p/cmdline" 2>/dev/null
    a0="${a0##*/}"; a1="${a1##*/}"
    if [ "$comm" = "$want" ] || [ "$a0" = "$want" ] || [ "$a1" = "$want" ]; then
      printf '%s' "$p"; return 0
    fi
    p="$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)" || break
    i=$((i + 1))
  done
  return 0
}

# al_upsert AGENT SESSION CWD MODEL EFFORT STATE [PARENT] [KIND]
# Level-triggered: if the entity exists, refresh the given non-empty fields and
# heartbeat; otherwise register it (track/branch derived from CWD by the canonical
# labeler; explicit alias/model/effort win over derived values).
al_upsert() {
  local agent="$1" sess="$2" cwd="${3:-}" mdl="${4:-}" eff="${5:-}" st="${6:-}" parent="${7:-}" kind="${8:-session}"
  local id alias follow pid
  # the core validates session_id (charset/length): never pass a raw, possibly hostile or overlong, agent-supplied id
  id="$(al_entity_id "$agent" "$sess")"
  alias="${LABEL_SYNC_AGENT_ALIAS:-$agent}"
  follow=false; [ "${LABEL_SYNC_FOLLOW_ACTIVE:-}" = 1 ] && follow=true
  [ -d "$cwd" ] || cwd=""
  if al_ctl get --id "$id" >/dev/null; then
    local args=(update --id "$id" --alias "$alias" --follow-active "$follow" --source "adapter:$agent")
    [ -n "$sess" ] && args+=(--session "$(al_safe "$sess" 120)")
    [ -n "$mdl" ] && args+=(--model "$mdl")
    [ -n "$eff" ] && args+=(--effort "$eff")
    [ -n "$cwd" ] && args+=(--cwd "$cwd")
    [ -n "$st" ] && args+=(--state "$st")
    al_ctl "${args[@]}" >/dev/null || al_dbg "update $id failed"
    al_ctl heartbeat --id "$id" ${st:+--state "$st"} >/dev/null || al_dbg "heartbeat $id failed"
    return 0
  fi
  pid="${LABEL_SYNC_AGENT_PID:-$(al_find_pid "$agent")}"
  local args=(register --id "$id" --kind "$kind" --alias "$alias" --follow-active "$follow" \
              --source "adapter:$agent" --derive)
  [ -n "$sess" ] && args+=(--session "$(al_safe "$sess" 120)")
  [ -n "$parent" ] && args+=(--parent "$parent")
  # --model/--effort are ALWAYS passed (possibly empty): an explicitly-set flag
  # stops --derive from filling them with the CLAUDE session's model/effort,
  # which would be a false label for a non-Claude agent (§11.4.6).
  args+=(--model "$mdl" --effort "$eff")
  [ -n "$cwd" ] && args+=(--cwd "$cwd")
  [ -n "$pid" ] && args+=(--pid "$pid")
  [ -n "$st" ] && args+=(--state "$st")
  if ! al_ctl "${args[@]}" >/dev/null; then
    # the canonical labeler may be absent/failing (exit 2): register WITHOUT derive
    # (track/branch stay '?' — never guessed, §11.4.6)
    local plain=() a
    for a in "${args[@]}"; do [ "$a" = "--derive" ] || plain+=("$a"); done
    al_ctl "${plain[@]}" >/dev/null || al_dbg "register $id failed"
  fi
  return 0
}

al_done() { # AGENT SESSION
  local id; id="$(al_entity_id "$1" "$2")"
  al_ctl unregister --id "$id" >/dev/null || al_dbg "unregister $id failed"
  return 0
}
