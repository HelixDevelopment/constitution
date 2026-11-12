#!/usr/bin/env bash
# T4 live default-on in a FRESH project: sandbox HOME (no operator agent home is read or written), real keys file by path,
# real toolkit checkout, bootstrap --default-on; then ONE real PreToolUse Bash gate call through the wired hook command.
set -uo pipefail
R="${1:?repo}"; S="${2:?sandbox}"; TK="${3:?toolkit}"; LM="${4:?llmctl}"
RH="$HOME"; mkdir -p "$S/home/.claude" "$S/proj"
export HOME="$S/home" JEV_API_KEYS_FILE="$RH/api_keys.sh" CLAUDE_TOOLKIT_DIR="$TK" LLMCTL_DIR="$LM"
unset CLAUDE_CONFIG_DIR JEV_STATE_DIR JEV_CONFIG_DIR JEV_EVIDENCE_DIR CMA_PROVIDERS_DIR JEV_BOOTSTRAP_HOME TYPESAFE_API_KEY OPENROUTER_API_KEY LLMCTL_API_KEY JEV_WIRING
cd "$S/proj"
bash "$R/scripts/jev/bootstrap.sh" --non-interactive --default-on > "$S/boot.out" 2> "$S/boot.err"; echo "$?" > "$S/boot.rc"
