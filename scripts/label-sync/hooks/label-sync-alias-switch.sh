#!/usr/bin/env bash
# scripts/label-sync/hooks/label-sync-alias-switch.sh
#
# Purpose : The ALIAS-SWITCH SIGNAL. Publishes "the operator's active Claude
#           alias is now <alias>" to the label-sync state so EVERY follower
#           entity (sessions, subagents, streams, shells, statuslines) re-renders
#           its label on the very next snapshot (CONTRACT §4.1) — no separate
#           propagation step. Called by the claude-toolkit wrapper
#           (toolkit/cma_label_hook.sh) on every launch/resume, and usable by
#           hand or by any launcher/shell function.
# Usage   : label-sync-alias-switch.sh <alias> [--model M] [--effort E]
#             alias   claude1 | claude2 | prov-xyz | deepseek | ...
#             --model  short name (opus|sonnet|haiku|fable) or a provider's real
#                      model id; omitted => stored empty and rendered `?`
#                      (a switch never invents a model/effort, §11.4.6)
#             --effort low|medium|high|xhigh|max; omitted => `?`
# Inputs  : args; env LABEL_SYNC_DIR / LABEL_SYNC_BIN (see labelctl.sh).
# Outputs : stdout: labelctl's confirmation line
#           ("active alias=<a> model=<m> effort=<e> seq=<n>").
# Exit    : 0 published | 1 rejected by the state layer | 2 usage error / cannot
#           determine (no go toolchain + no binary, state dir unusable). 2 is
#           never a pass. (Unlike the event hooks this is an explicit CLI, so it
#           reports failures; the toolkit wrapper decides to ignore them.)
# Side-effects: appends an `alias_switch` event; labelctl.sh may build the Go
#           binaries on first use (serialised, niced).
# Deps    : bash, labelctl.sh (+ go on first build).
# Cross-refs: §11.4.182, §11.4.231, CONTRACT §4, docs/label-sync/HOOKS.md.
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LS_DIR="$(cd "$HERE/.." && pwd)"
usage() { sed -n '/^# Usage/,/^# Inputs/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 2; }

alias_="${1:-}"
[ -n "$alias_" ] || usage
case "$alias_" in -h|--help) usage ;; --*) usage ;; esac
case "$alias_" in *[!A-Za-z0-9._-]*) echo "label-sync-alias-switch: invalid alias '$alias_'" >&2; exit 2 ;; esac
shift
model=""; effort=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model)  [ $# -ge 2 ] || usage; model="$2"; shift 2 ;;
    --effort) [ $# -ge 2 ] || usage; effort="$2"; shift 2 ;;
    *) echo "label-sync-alias-switch: unknown argument '$1'" >&2; usage ;;
  esac
done
exec bash "$LS_DIR/labelctl.sh" switch-alias --alias "$alias_" ${model:+--model "$model"} ${effort:+--effort "$effort"}
