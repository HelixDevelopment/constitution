#!/usr/bin/env bash
# T4 gate leg: one real PreToolUse Bash call through the hook command the default-on bootstrap wired in sandbox S.
# variant A = the inherited operator session env (CMA_JEV_*/JEV_* as exported); variant B = routing from the toolkit's
# TypeSafe provider pin. Keys come from the operator keys file (sourced into THIS process only; values never printed).
set -uo pipefail
S="${1:?sandbox}"; V="${2:?A|B}"; RH="$HOME"
G=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$S/home/.claude-shared/settings.json")
set -a; . "$RH/api_keys.sh" >/dev/null 2>&1; set +a
if [ "$V" = B ]; then
  unset CMA_JEV_ENDPOINT_ID JEV_BASE_URL JEV_KEY_VAR JEV_MODEL
  export CMA_JEV_ENDPOINT_ID=jev-typesafe JEV_BASE_URL=https://api.typesafe.ai JEV_KEY_VAR=TYPESAFE_API_KEY JEV_MODEL=jev-latest
fi
export HOME="$S/home"; unset JEV_STATE_DIR JEV_CONFIG_DIR; cd "$S/proj" || exit 1
printf '%s' '{"session_id":"t4","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"'"$S/proj"'"}' \
  | timeout 30 "$G" > "$S/gate$V.out" 2> "$S/gate$V.err"; echo "$?" > "$S/gate$V.rc"
