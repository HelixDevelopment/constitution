#!/usr/bin/env bash
# scripts/label-sync/adapters/generic/label-agent-run.sh
#
# Purpose : GUARANTEED-FALLBACK adapter for ANY CLI agent, installed or not,
#           hook-capable or not: run the agent as a supervised child of a
#           wrapper that owns its label-bus entity. The label is published for
#           exactly as long as the agent runs, regardless of what the agent
#           itself supports. (Same supervision discipline as render/labelrun:
#           no exec, exact exit code, signals forwarded to the ONE child we
#           started — never a process group, §11.4.263.)
# Usage   : label-agent-run.sh --agent NAME [--alias A] [--model M] [--effort E]
#                              [--cwd DIR] -- <agent command> [args...]
#           e.g. label-agent-run.sh --agent codex --model gpt-5 -- codex "fix the tests"
# Inputs  : flags; env of adapter_lib.sh. The child inherits
#           LABEL_SYNC_ENTITY_ID (its own entity id) and LABEL_SYNC_AGENT_ALIAS so
#           an agent-side hook (aider-notify.sh, codex-notify.sh, ...) updates THE
#           SAME entity instead of creating a second one.
# Outputs : the child's own output; on a tty, one `label-agent-run: <label>` line
#           on stderr. Command arguments are NEVER recorded or printed (§11.4.10).
# Exit    : the child's exit status verbatim (127 not found, 126 not executable,
#           128+N on signal N); 2 only for wrapper usage errors. FAIL-SOFT: if the
#           bus is unusable the agent still runs and its exit code still returns.
# Side-effects: register at start, unregister at exit (also on TERM/INT/HUP,
#           including one that arrives while registering: the agent is then
#           never started). A SIGKILL'd wrapper cannot clean up: its entity goes
#           stale on TTL and is swept later (CONTRACT, stale sweeper).
# Signals : the agent runs with DEFAULT SIGINT/SIGQUIT (a terminal Ctrl-C
#           stops it); TERM/HUP are forwarded to the ONE child; INT/QUIT are
#           forwarded only when the child is NOT in the terminal's foreground
#           process group (else the tty already delivered them — exactly once).
# Deps    : bash>=4, labelctl.sh.
# Cross-refs: §11.4.182, §11.4.263, render/labelrun, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../lib/adapter_lib.sh"
usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }
agent="" alias="" mdl="" eff="" cwd="$PWD"
# an option that takes a value but is last on the line used to make `shift 2`
# fail and loop forever (review-2 finding I)
needv() { [ "$1" -ge 2 ] || { echo "label-agent-run: $2 requires a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --agent|--alias|--model|--effort|--cwd) needv $# "$1" ;;
  esac
  case "$1" in
    --agent) agent="${2:-}"; shift 2 ;;
    --alias) alias="${2:-}"; shift 2 ;;
    --model) mdl="${2:-}"; shift 2 ;;
    --effort) eff="${2:-}"; shift 2 ;;
    --cwd) cwd="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "label-agent-run: unknown option '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$agent" ] && [ $# -gt 0 ] || { usage >&2; exit 2; }
[ -n "$alias" ] && export LABEL_SYNC_AGENT_ALIAS="$alias"

# Signals are trapped BEFORE the entity is registered (review-2 finding F): a
# TERM that arrives while registering used to kill the wrapper with the default
# action, leaving a `running` ghost entity. Now it is remembered (stop) and the
# wrapper exits 128+N right after registering, through the EXIT cleanup —
# never starting the agent.
registered=0 id="" child=0 stop=""
# Single child pid only, validated > 1 — never a process group (§11.4.263).
fwd() { case "$child" in ''|*[!0-9]*) return 0 ;; esac; [ "$child" -gt 1 ] && kill -s "$1" "$child" 2>/dev/null; return 0; }
# INT/QUIT: NOT forwarded when the child sits in the terminal's foreground
# process group — the tty already delivered the same signal (review-2 finding
# B: a Ctrl-C used to reach the child twice). /proc/<pid>/stat after ')':
# state ppid pgrp session tty_nr tpgid ...
fwd_tty() {
  local st rest f
  case "$child" in ''|*[!0-9]*) return 0 ;; esac
  if { IFS= read -r st <"/proc/$child/stat"; } 2>/dev/null; then
    rest="${st##*) }"; read -r -a f <<<"$rest"
    if [ "${f[5]:-0}" -gt 0 ] 2>/dev/null && [ "${f[2]:-x}" = "${f[5]}" ]; then return 0; fi  # MUT:fwdtty
  fi
  fwd "$1"
}
on_sig() { # signal
  if [ "$child" -gt 1 ] 2>/dev/null; then
    case "$1" in INT|QUIT) fwd_tty "$1" ;; *) fwd "$1" ;; esac
  else
    stop="$1"                                   # before the child exists
  fi
  return 0
}
cleanup() { [ "$registered" = 1 ] && al_ctl unregister --id "$id" >/dev/null; return 0; }
trap 'on_sig TERM' TERM
trap 'on_sig INT' INT
trap 'on_sig QUIT' QUIT
trap 'on_sig HUP' HUP
trap cleanup EXIT

if al_init; then
  sess="run$$-${EPOCHSECONDS:-0}"
  unset LABEL_SYNC_ENTITY_ID
  id="$(al_entity_id "$agent" "$sess")"
  export LABEL_SYNC_ENTITY_ID="$id"
  LABEL_SYNC_AGENT_PID="$$" al_upsert "$agent" "$sess" "$cwd" "$mdl" "$eff" running
  if al_ctl get --id "$id" >/dev/null; then registered=1; fi
  if [ "$registered" = 1 ] && [ -t 2 ]; then
    printf 'label-agent-run: %s\n' "$(al_ctl label "$id" | tr -d '[:cntrl:]')" >&2
  fi
fi
if [ -n "$stop" ]; then                        # signalled while registering
  case "$stop" in HUP) exit 129 ;; INT) exit 130 ;; QUIT) exit 131 ;; *) exit 143 ;; esac
fi

# The agent must keep a DEFAULT SIGINT/SIGQUIT: an `&` child of a non-interactive
# bash inherits them IGNORED, so Ctrl-C did not stop the agent (review-2
# finding B; measured: SigIgn 0x6 before, 0x0 with the subshell reset). Its
# stdin is the wrapper's (`<&0`: an async command otherwise reads /dev/null).
( trap - INT QUIT; exec "$@" ) <&0 &   # MUT:sigreset
child=$!
wait "$child"; rc=$?
while kill -0 "$child" 2>/dev/null; do wait "$child"; rc=$?; done
exit "$rc"
