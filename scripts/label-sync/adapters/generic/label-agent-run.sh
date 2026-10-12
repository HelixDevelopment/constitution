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
# Side-effects: register at start, unregister at exit (also on TERM/INT/HUP). A
#           SIGKILL'd wrapper cannot clean up: its entity goes stale on TTL.
# Deps    : bash>=4, labelctl.sh.
# Cross-refs: §11.4.182, §11.4.263, render/labelrun, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../lib/adapter_lib.sh"
usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }
agent="" alias="" mdl="" eff="" cwd="$PWD"
while [ $# -gt 0 ]; do
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

registered=0 id=""
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

child=0
fwd() { [ "$child" -gt 1 ] && kill -s "$1" "$child" 2>/dev/null; return 0; }
cleanup() { [ "$registered" = 1 ] && al_ctl unregister --id "$id" >/dev/null; return 0; }
trap 'fwd TERM' TERM
trap 'fwd INT' INT
trap 'fwd HUP' HUP
trap cleanup EXIT

"$@" <&0 &
child=$!
wait "$child"; rc=$?
while kill -0 "$child" 2>/dev/null; do wait "$child"; rc=$?; done
exit "$rc"
