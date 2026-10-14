#!/usr/bin/env bash
# scripts/label-sync/adapters/lib/label-adapter-event.sh
#
# Purpose : Agent-neutral command-line entry to the label bus for adapters that
#           cannot (or should not) source bash: the OpenCode plugin, Codex's
#           `notify` program, Aider's notifications command, third-party
#           wrappers. One call = one level-triggered state assertion.
# Usage   : label-adapter-event.sh --agent NAME --event register|heartbeat|done
#             [--session ID] [--cwd DIR] [--model M] [--effort E]
#             [--state running|idle|done|unknown] [--parent ENTITY_ID]
#             [--kind session|agent|subagent|stream|shell|command|flow] [--pid N]
#           `register` and `heartbeat` are BOTH upserts (heartbeat of an unknown
#           entity registers it), so a missed SessionStart never loses a label.
# Inputs  : flags above; env of adapter_lib.sh (LABEL_SYNC_DIR, ...). If --session
#           is omitted the id falls back to LABEL_SYNC_ENTITY_ID, else to the pid
#           of the nearest ancestor process named NAME, else `unknown`.
# Outputs : prints the entity id on stdout (so a caller can reuse it as
#           --parent), nothing else.
# Exit    : 0 always on a valid invocation (fail-soft), 2 on a usage error
#           (missing/unknown --agent/--event). 2 is never a pass.
# Side-effects: labelctl calls (see adapter_lib.sh). Deps: bash, labelctl.sh.
# Cross-refs: §11.4.182, §11.4.18, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/adapter_lib.sh"
agent="" event="" sess="" cwd="" mdl="" eff="" st="" parent="" kind=session
needv() { [ "$1" -ge 2 ] || { echo "label-adapter-event: $2 requires a value" >&2; exit 2; }; }  # review-2 finding I: no endless loop
while [ $# -gt 0 ]; do
  case "$1" in --agent|--event|--session|--cwd|--model|--effort|--state|--parent|--kind|--pid) needv $# "$1" ;; esac
  case "$1" in
    --agent) agent="${2:-}"; shift 2 ;;
    --event) event="${2:-}"; shift 2 ;;
    --session) sess="${2:-}"; shift 2 ;;
    --cwd) cwd="${2:-}"; shift 2 ;;
    --model) mdl="${2:-}"; shift 2 ;;
    --effort) eff="${2:-}"; shift 2 ;;
    --state) st="${2:-}"; shift 2 ;;
    --parent) parent="${2:-}"; shift 2 ;;
    --kind) kind="${2:-}"; shift 2 ;;
    --pid) LABEL_SYNC_AGENT_PID="${2:-}"; export LABEL_SYNC_AGENT_PID; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "label-adapter-event: unknown option '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$agent" ] || { echo "label-adapter-event: --agent required" >&2; exit 2; }
case "$event" in register|heartbeat|done) ;; *) echo "label-adapter-event: --event must be register|heartbeat|done" >&2; exit 2 ;; esac
[ -n "$sess" ] || { [ -n "${LABEL_SYNC_ENTITY_ID:-}" ] && sess="env"; }
if [ -z "$sess" ]; then sess="$(al_find_pid "$agent")"; sess="pid${sess:-unknown}"; fi
al_init || exit 0
case "$event" in
  done) al_done "$agent" "$sess" ;;
  *) al_upsert "$agent" "$sess" "$cwd" "$mdl" "$eff" "${st:-running}" "$parent" "$kind" ;;
esac
al_entity_id "$agent" "$sess"; echo
exit 0
