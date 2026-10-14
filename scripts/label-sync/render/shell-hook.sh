#!/usr/bin/env bash
# scripts/label-sync/render/shell-hook.sh
#
# Purpose : Fire-and-forget worker behind the shell integrations (bash/zsh/fish).
#           Registers / heartbeats / unregisters the interactive SHELL as a
#           `shell` entity and each COMMAND as a `command` entity, and is the
#           ONE place that decides what may be recorded about a command.
# Usage   : shell-hook.sh shell-start --id ID --pid PID --cwd DIR [--parent P]
#           shell-hook.sh shell-beat  --id ID
#           shell-hook.sh shell-refresh --id ID --cwd DIR [--seq N]   (re-derive track/branch/cwd;
#                         N = the shell's increasing refresh counter: an older refresh never
#                         overwrites a newer one; retried once when the shell is not registered yet)
#           shell-hook.sh shell-end   --id ID
#           shell-hook.sh cmd-start   --id ID --parent SHELL_ID --pid PID --cwd DIR [--argv0 NAME]
#           shell-hook.sh cmd-end     --id ID
# SECRET HANDLING (§11.4.10 / §11.4.252, fail-closed) — ARGV0-ONLY POLICY:
#           the command TEXT never leaves the user's shell: it is not an argument,
#           not piped on stdin, not hashed, not stored. The integration resolves
#           the first word itself and passes it as --argv0 ONLY when the shell can
#           resolve it as a command (`type -t` / `whence -w` / `type -q`: alias,
#           function, builtin, keyword or file); anything else — a pasted token, a
#           password typed at the prompt — arrives as `?`. This worker then
#           applies a second, independent backstop: basename, charset
#           [A-Za-z0-9._+-], max 40 chars, and redaction to `?` of anything shaped
#           like a credential (ghp_/gho_/ghu_/ghs_/ghr_/github_pat_, glpat-,
#           xox[abprs]-, AKIA/ASIA, sk-/sk_live_/rk_live_, and any >= 24-char
#           [A-Za-z0-9+/=] word containing a digit). Recorded in the entity's
#           `source` field as `shell-integration:argv0=<argv0>` — nothing else.
#           (No salted digest: it added no consumer-visible value and its salt
#           had to live in the environment — removed, review finding 7.)
# BINDING : shell-start registers with --derive (track/branch/alias/model/effort
#           from the canonical labeler). An alias the labeler derives PINS the
#           entity (CONTRACT §4.2) — correct ONLY when it comes from a real Claude
#           alias environment (CLAUDE_CONFIG_DIR basename `.claude-<alias>`). Any
#           other shell is registered with `--follow-active true`, so a plain
#           terminal follows `labelctl switch-alias` instead of freezing on
#           whatever alias a labeler might guess.
# Inputs  : env LABEL_SYNC_DIR, LABEL_SYNC_LABELCTL, CLAUDE_CONFIG_DIR,
#           CLAUDE_CODE_SESSION_ID, LABEL_SYNC_LOCK_TIMEOUT (default here 500ms),
#           LABEL_SYNC_DEBUG (=1: print failures, sanitised, to stderr).
# Outputs : none (stderr only with LABEL_SYNC_DEBUG=1, through lib.sh ls_sanitize).
# Exit    : 0 ALWAYS — it is a background hook and must never disturb a shell;
#           failures are observable through the state itself (`labelctl verify`).
# Side-effects: labelctl writes under LABEL_SYNC_DIR. cmd-end / shell-end RETRY
#           the unregister up to 10 x 0.2 s because the matching register runs in
#           a sibling background process and may land a moment later.
# Deps    : bash, labelctl.sh.
# Cross-refs: §11.4.182, §11.4.116, §11.4.10, docs/label-sync/RENDERERS.md, CONTRACT §2, §4.2.
# Classification: universal (§11.4.17).
set -u
RDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
. "$RDIR/lib.sh" || exit 0
LCTL="$(ls_labelctl)"
export LABEL_SYNC_LOCK_TIMEOUT="${LABEL_SYNC_LOCK_TIMEOUT:-500ms}"   # a hook never waits long on the lock
op="${1:-}"; shift || true
id="" pid="" cwd="" parent="" argv0="?" seq=""
while [ $# -gt 0 ]; do
  case "$1" in
    --id) id="${2:-}"; shift 2 ;; --pid) pid="${2:-}"; shift 2 ;; --seq) seq="${2:-}"; shift 2 ;;
    --cwd) cwd="${2:-}"; shift 2 ;; --parent) parent="${2:-}"; shift 2 ;;
    --argv0) argv0="${2:-?}"; shift 2 ;;
    *) shift ;;
  esac
done
dbg() { local m; [ "${LABEL_SYNC_DEBUG:-}" = 1 ] || return 0; ls_sanitize_into m "shell-hook: $*" 512; echo "$m" >&2; return 0; }
[ -n "$id" ] || { dbg "missing --id"; exit 0; }
[ -x "$LCTL" ] || { dbg "labelctl not executable: $LCTL"; exit 0; }
sess=(); [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] && sess=(--session "$CLAUDE_CODE_SESSION_ID")
par=();  [ -n "$parent" ] && par=(--parent "$parent")

# ls_argv0_clean NAME — the backstop (second, independent layer after the shell's
# own resolvability check). Prints the recordable argv0 or `?`.
ls_argv0_clean() {
  local w="${1:-?}"
  w="${w##*/}"; w="${w//[^A-Za-z0-9._+-]/}"; w="${w:0:40}"
  [ -n "$w" ] || { printf '?'; return 0; }
  case "$w" in
    ghp_*|gho_*|ghu_*|ghs_*|ghr_*|github_pat_*|glpat-*|xox[abprs]-*|AKIA*|ASIA*|sk-*|sk_live_*|rk_live_*|sk_test_*)
      printf '?'; return 0 ;;
  esac
  if [ "${#w}" -ge 24 ] && [[ $w =~ ^[A-Za-z0-9+/=]+$ ]] && [[ $w == *[0-9]* ]]; then
    printf '?'; return 0                       # long base64/hex-shaped word
  fi
  printf '%s' "$w"
}

unreg() { # retry: the register may still be in flight
  local n=10
  while [ "$n" -gt 0 ]; do "$LCTL" unregister --id "$1" >/dev/null 2>&1 && return 0; sleep 0.2; n=$((n-1)); done
  dbg "unregister $1 never succeeded"
}

case "$op" in
  shell-start)
    fol=(--follow-active true)
    cfg="${CLAUDE_CONFIG_DIR:-}"; cfg="${cfg%/}"
    case "${cfg##*/}" in .claude-?*) fol=() ;; esac   # a real Claude alias env pins (CONTRACT §4.2)
    "$LCTL" register --id "$id" --kind shell --pid "${pid:-0}" --cwd "${cwd:-$PWD}" "${par[@]}" "${sess[@]}" \
      --derive "${fol[@]}" --source "shell-integration" >/dev/null 2>&1 || dbg "shell-start failed" ;;
  shell-beat) "$LCTL" heartbeat --id "$id" >/dev/null 2>&1 || dbg "shell-beat failed" ;;
  shell-refresh)
    # review-2 finding 8: after a `cd` / `git checkout` the shell entity's
    # PLACE (track, branch, cwd) is re-derived with the canonical labeler. The
    # binding (alias/model/effort) is NOT touched: it was decided at
    # shell-start. A field the labeler reports as `?` is CLEARED, never kept
    # from the previous directory (§11.4.6).
    # re-review finding 6: refreshes run detached and may finish out of order.
    case "$seq" in ''|*[!0-9]*) seq="" ;; esac
    case "$id" in */*|.*) dbg "shell-refresh: bad id"; exit 0 ;; esac
    last="" seqf=""
    rdir="$(ls_dir)/shellrefresh"
    if mkdir -p -m 700 "$rdir" 2>/dev/null; then
      seqf="$rdir/$id"
      if command -v flock >/dev/null 2>&1 && { exec 9>>"$seqf.lock"; } 2>/dev/null; then
        flock -w 5 9 2>/dev/null || dbg "shell-refresh: lock busy, continuing unlocked"
      fi
      { IFS= read -r last <"$seqf"; } 2>/dev/null || last=""
      case "$last" in *[!0-9]*) last="" ;; esac
    fi
    lb="${LABEL_SYNC_LABELER:-$RDIR/../../multitrack/track_branch_label.sh}"
    d="${cwd:-$PWD}"
    lab="$(cd "$d" 2>/dev/null && bash "$lb" 2>/dev/null)" || lab=""
    lab="${lab%%$'\n'*}"
    case "$lab" in "(T"*" - "*")") ;; *) dbg "shell-refresh: no label from $lb"; exit 0 ;; esac
    in="${lab#\(T}"; tr="${in%%/*}"; rest="${in#*/}"; br="${rest%% - *}"
    up=(update --id "$id" --cwd "$d"); clr=()
    if [[ $tr =~ ^[0-9]+$ ]]; then up+=(--track "$tr"); else clr+=(track); fi
    if [ -n "$br" ] && [ "$br" != "?" ]; then up+=(--branch "$br"); else clr+=(branch); fi
    [ "${#clr[@]}" -gt 0 ] && up+=(--clear "$(IFS=,; echo "${clr[*]}")")
    # The ordering decision and the update happen under ONE per-shell lock, so a
    # newer refresh cannot interleave between an older one's check and write.
    if [ -n "$last" ] && [ -n "$seq" ] && [ "$seq" -le "$last" ]; then   # MUT:refreshorder
      dbg "shell-refresh: seq $seq <= applied $last — older refresh dropped"; exit 0
    fi
    if ! "$LCTL" "${up[@]}" >/dev/null 2>&1; then
      sleep 1   # the shell-start register may still be in flight: retry ONCE
      "$LCTL" "${up[@]}" >/dev/null 2>&1 || { dbg "shell-refresh failed"; exit 0; }   # MUT:refreshretry
    fi
    [ -n "$seq" ] && [ -n "$seqf" ] && printf '%s\n' "$seq" >"$seqf" 2>/dev/null ;;
  shell-end)  unreg "$id"
              case "$id" in */*|.*) ;; *) rm -f -- "$(ls_dir)/shellrefresh/$id" "$(ls_dir)/shellrefresh/$id.lock" 2>/dev/null ;; esac ;;
  cmd-end)    unreg "$id" ;;
  cmd-start)
    a0="$(ls_argv0_clean "$argv0")"
    n=5
    while [ "$n" -gt 0 ]; do
      "$LCTL" register --id "$id" --kind command --pid "${pid:-0}" --cwd "${cwd:-$PWD}" "${par[@]}" "${sess[@]}" \
        --source "shell-integration:argv0=${a0}" >/dev/null 2>&1 && break
      sleep 0.2; n=$((n-1))
    done
    [ "$n" -gt 0 ] || dbg "cmd-start failed" ;;
  *) dbg "unknown op '$op'" ;;
esac
exit 0
