#!/usr/bin/env bash
# T3 live detection run N: real llmctl, real keys file (by path), real hosted probes; every Jev dir in a sandbox.
set -uo pipefail
R="${1:?repo}"; S="${2:?sandbox}"; mkdir -p "$S"/{state,config,evidence,providers,bshome,claude}
export JEV_STATE_DIR="$S/state" JEV_CONFIG_DIR="$S/config" JEV_EVIDENCE_DIR="$S/evidence" CMA_PROVIDERS_DIR="$S/providers" \
       JEV_BOOTSTRAP_HOME="$S/bshome" CLAUDE_CONFIG_DIR="$S/claude" JEV_API_KEYS_FILE="$HOME/api_keys.sh"
unset JEV_BOOTSTRAP_DEFAULT_ON JEV_BOOTSTRAP_CONSENT TYPESAFE_API_KEY OPENROUTER_API_KEY LLMCTL_API_KEY
bash "$R/scripts/jev/bootstrap.sh" --non-interactive > "$S/out.txt" 2> "$S/err.txt"; echo "$?" > "$S/rc"
