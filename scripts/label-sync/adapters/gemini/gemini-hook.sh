#!/usr/bin/env bash
# scripts/label-sync/adapters/gemini/gemini-hook.sh
#
# Purpose : Gemini CLI hook -> label bus (also used by Qwen Code through
#           qwen/qwen-hook.sh, which sets LABEL_SYNC_HOOK_AGENT=qwen). Reads the
#           hook JSON on stdin (session_id, cwd, hook_event_name) and maps
#           lifecycle events to register / heartbeat / done.
# Usage   : configured under `hooks` in ~/.gemini/settings.json (see
#           docs/label-sync/ADAPTERS.md for the snippet).
#           Manual: echo '{"hook_event_name":"SessionStart","session_id":"s","cwd":"/x"}' | gemini-hook.sh
# Inputs  : stdin JSON (only hook_event_name, session_id, cwd are read; prompts,
#           tool input/output are NEVER parsed, §11.4.10); env LABEL_SYNC_HOOK_AGENT
#           (default gemini).
# Outputs : stdout `{}` (an empty, decision-free JSON object — Gemini parses hook
#           stdout as JSON).
# Exit    : ALWAYS 0 (a non-zero exit may block).
# Mapping : SessionStart->register running | BeforeAgent|BeforeTool|BeforeModel->
#           heartbeat running | AfterAgent|Notification->heartbeat idle |
#           SessionEnd->done. Unknown events are ignored.
# STATUS  : UNCONFIRMED — neither Gemini CLI nor Qwen Code is installed on the
#           host this was written on; event names are from the upstream hooks
#           documentation as remembered, NEVER run against a real agent (§11.4.6).
#           The guaranteed path is generic/label-agent-run.sh.
# Side-effects: labelctl calls. Deps: bash, jq (absent => prints `{}` only).
# Cross-refs: §11.4.182, §11.4.18, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../lib/adapter_lib.sh"
agent="${LABEL_SYNC_HOOK_AGENT:-gemini}"
IFS= read -r -d '' payload || true
if [ -n "$payload" ] && command -v jq >/dev/null 2>&1 && al_init; then
  parsed="$(printf '%s' "$payload" | jq -r 'select(type=="object") |
    [(.hook_event_name // ""), (.session_id // ""), (.cwd // "")] | map(gsub("[[:cntrl:]]";"")) | join("\u001f")' 2>/dev/null)"
  IFS=$'\037' read -r ev sess cwd <<<"${parsed:-}"
  if [ -n "$sess" ]; then
    case "$ev" in
      SessionStart) al_upsert "$agent" "$sess" "$cwd" "" "" running ;;
      BeforeAgent|BeforeTool|BeforeModel) al_upsert "$agent" "$sess" "$cwd" "" "" running ;;
      AfterAgent|Notification) al_upsert "$agent" "$sess" "$cwd" "" "" idle ;;
      SessionEnd) al_done "$agent" "$sess" ;;
    esac
  fi
fi
printf '{}\n'
exit 0
