#!/usr/bin/env bash
# scripts/label-sync/adapters/crush/crush-hook.sh
#
# Purpose : Crush `PreToolUse` hook -> label bus. Crush (v0.91) supports ONLY the
#           PreToolUse event; it fires before every tool call and passes
#           CRUSH_SESSION_ID / CRUSH_CWD / CRUSH_PROJECT_DIR in the environment
#           and a JSON envelope on stdin. Every tool call therefore re-asserts
#           (level-triggered) that this Crush session is alive and working.
# Usage   : configured by install_adapters.sh into crush.json
#           {"hooks":{"PreToolUse":[{"command":"bash <this script>","timeout":10}]}}
# Inputs  : env CRUSH_SESSION_ID, CRUSH_CWD (preferred; stdin `session_id`/`cwd`
#           is the fallback). Tool names, tool inputs and commands are NEVER read.
# Outputs : stdout `{"version":1}` — an explicit no-decision envelope: no
#           `decision`, so the tool call and the permission prompt are untouched.
# Exit    : ALWAYS 0 (Crush: exit 2 blocks the tool call, exit 49 halts the turn;
#           an observer must never do either).
# Limits  : Crush has NO session-start/end events. The entity appears on the first
#           tool call, is kept alive by its pid (the nearest ancestor named
#           `crush`) and goes stale on TTL after Crush exits; it is never marked
#           `done` by Crush itself. Model/effort are not in the payload => `?`.
# Side-effects: labelctl calls. Deps: bash, jq (absent => the env-only path runs).
# Cross-refs: §11.4.182, §11.4.18, docs/label-sync/ADAPTERS.md (capability: SCHEMA-ONLY).
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../lib/adapter_lib.sh"
IFS= read -r -d '' payload || true
sess="${CRUSH_SESSION_ID:-}" cwd="${CRUSH_CWD:-}"
if { [ -z "$sess" ] || [ -z "$cwd" ]; } && [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
  parsed="$(printf '%s' "$payload" | jq -r 'select(type=="object") | [(.session_id // ""), (.cwd // "")] | map(gsub("[[:cntrl:]]";"")) | join("\u001f")' 2>/dev/null)"
  IFS=$'\037' read -r psess pcwd <<<"${parsed:-}"
  [ -n "$sess" ] || sess="$psess"
  [ -n "$cwd" ] || cwd="$pcwd"
fi
if [ -n "$sess" ] && al_init; then
  al_upsert crush "$sess" "$cwd" "" "" running
fi
printf '{"version":1}\n'
exit 0
