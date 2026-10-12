#!/usr/bin/env bash
# scripts/label-sync/render/shell-hook.sh
#
# Purpose : Fire-and-forget worker behind the shell integrations (bash/zsh/fish).
#           Registers / heartbeats / unregisters the interactive SHELL as a
#           `shell` entity and each COMMAND as a `command` entity, and is the
#           ONE place that decides what may be recorded about a command.
# Usage   : shell-hook.sh shell-start --id ID --pid PID --cwd DIR [--parent P]
#           shell-hook.sh shell-beat  --id ID
#           shell-hook.sh shell-end   --id ID
#           shell-hook.sh cmd-start   --id ID --parent SHELL_ID --pid PID --cwd DIR   (command text on STDIN)
#           shell-hook.sh cmd-end     --id ID
# SECRET HANDLING (§11.4.10 / §11.4.252, fail-closed): the command text is read
#           from STDIN ONLY — it is never an argument, so it never appears in any
#           process listing. What is recorded is exactly:
#             argv0  = basename of the first word after any leading VAR=value
#                      assignments, restricted to [A-Za-z0-9._+-], max 40 chars
#                      (a quoted assignment or an unparseable word => `?`);
#             h      = first 12 hex chars of sha256(SALT + full command text),
#                      SALT = $LABEL_SYNC_SALT, a per-shell random value that is
#                      never written to disk, so the digest cannot be brute-forced
#                      from the state files; it only lets one shell correlate
#                      repeats of the same command.
#           stored in the entity's `source` field as
#           `shell-integration:argv0=<argv0>:h=<digest>`. No argument values, no
#           environment, no full text — ever. (No repo-wide command redaction
#           convention exists; credential_scan_lib.sh scans FILES, not shell
#           input, so the conservative rule above is used instead.)
# Inputs  : env LABEL_SYNC_DIR, LABEL_SYNC_LABELCTL, LABEL_SYNC_SALT,
#           CLAUDE_CODE_SESSION_ID, LABEL_SYNC_DEBUG (=1: print failures).
# Outputs : none (stderr only with LABEL_SYNC_DEBUG=1).
# Exit    : 0 ALWAYS — it is a background hook and must never disturb a shell;
#           failures are observable through the state itself (`labelctl verify`).
# Side-effects: labelctl writes under LABEL_SYNC_DIR. cmd-end / shell-end RETRY
#           the unregister up to 10 x 0.2 s because the matching register runs in
#           a sibling background process and may land a moment later.
# Deps    : bash, labelctl.sh, sha256sum (digest; absent => `h=none`).
# Cross-refs: §11.4.182, §11.4.116, docs/label-sync/RENDERERS.md, CONTRACT §2.
# Classification: universal (§11.4.17).
set -u
RDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
. "$RDIR/lib.sh" || exit 0
LCTL="$(ls_labelctl)"
op="${1:-}"; shift || true
id="" pid="" cwd="" parent=""
while [ $# -gt 0 ]; do
  case "$1" in
    --id) id="${2:-}"; shift 2 ;; --pid) pid="${2:-}"; shift 2 ;;
    --cwd) cwd="${2:-}"; shift 2 ;; --parent) parent="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
dbg() { [ "${LABEL_SYNC_DEBUG:-}" = 1 ] && echo "shell-hook: $*" >&2; return 0; }
[ -n "$id" ] || { dbg "missing --id"; exit 0; }
[ -x "$LCTL" ] || { dbg "labelctl not executable: $LCTL"; exit 0; }
sess=(); [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] && sess=(--session "$CLAUDE_CODE_SESSION_ID")
par=();  [ -n "$parent" ] && par=(--parent "$parent")

unreg() { # retry: the register may still be in flight
  local n=10
  while [ "$n" -gt 0 ]; do "$LCTL" unregister --id "$1" >/dev/null 2>&1 && return 0; sleep 0.2; n=$((n-1)); done
  dbg "unregister $1 never succeeded"
}

case "$op" in
  shell-start)
    "$LCTL" register --id "$id" --kind shell --pid "${pid:-0}" --cwd "${cwd:-$PWD}" "${par[@]}" "${sess[@]}" \
      --derive --source "shell-integration" >/dev/null 2>&1 || dbg "shell-start failed" ;;
  shell-beat) "$LCTL" heartbeat --id "$id" >/dev/null 2>&1 || dbg "shell-beat failed" ;;
  shell-end)  unreg "$id" ;;
  cmd-end)    unreg "$id" ;;
  cmd-start)
    text=""; IFS= read -r -d '' text || :
    argv0="?"; skip=0; w=""
    set -f
    for w in $text; do
      if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        case "$w" in *\"*|*\'*) argv0="?"; skip=2; break ;; esac
        continue
      fi
      w="${w##*/}"; w="${w//[^A-Za-z0-9._+-]/}"; w="${w:0:40}"
      [ -n "$w" ] && argv0="$w"
      break
    done
    set +f
    [ "$skip" = 2 ] && argv0="?"
    h="none"
    command -v sha256sum >/dev/null 2>&1 && h="$(printf '%s' "${LABEL_SYNC_SALT:-}${text}" | sha256sum | cut -c1-12)"
    text=""
    n=5
    while [ "$n" -gt 0 ]; do
      "$LCTL" register --id "$id" --kind command --pid "${pid:-0}" --cwd "${cwd:-$PWD}" "${par[@]}" "${sess[@]}" \
        --source "shell-integration:argv0=${argv0}:h=${h}" >/dev/null 2>&1 && break
      sleep 0.2; n=$((n-1))
    done
    [ "$n" -gt 0 ] || dbg "cmd-start failed" ;;
  *) dbg "unknown op '$op'" ;;
esac
exit 0
