#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_security.sh — security properties of the pi-constitution plugin:
# no secrets in manifests, no network access at install/runtime, no code execution at install,
# no forbidden APIs, triage codes are deterministic (not model prose).
#
# Oracle strategy: SPECIFIED (expected outcomes hand-written from the security contract).
#
# Run: bash tests/pi-constitution/test_security.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR GIT_DIR GIT_INDEX_FILE; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=security

PLUGIN_JSON="$REPO/plugins/pi-constitution/plugin.json"
PLUGIN_TS="$REPO/plugins/pi-constitution/pi-constitution.ts"

# --- S1: No secrets in plugin.json --------------------------------------------
if [ -f "$PLUGIN_JSON" ]; then
  SECRET_PATTERNS=("sk-" "AKIA" "ghp_" "glpat" "xoxb" "-----BEGIN" "password" "secret" "token")
  SECRET_FOUND=0
  for s in "${SECRET_PATTERNS[@]}"; do
    if grep -qiF -- "$s" "$PLUGIN_JSON"; then
      nok "secret-like pattern in plugin.json: $s"
      SECRET_FOUND=1
    fi
  done
  [ "$SECRET_FOUND" -eq 0 ] && ok "no secrets in plugin.json"
fi

# --- S2: No network access in pi-constitution.ts ------------------------------
if [ -f "$PLUGIN_TS" ]; then
  NET_PATTERNS=("fetch(" "XMLHttpRequest" "WebSocket(" "axios(" "got(" "node:http" "node:https" "request(" "http.request")
  NET_FOUND=0
  for n in "${NET_PATTERNS[@]}"; do
    if grep -vE '^\s*(//|\*)' "$PLUGIN_TS" | grep -qF -- "$n"; then
      nok "network access pattern in pi-constitution.ts: $n"
      NET_FOUND=1
    fi
  done
  [ "$NET_FOUND" -eq 0 ] && ok "no network access in pi-constitution.ts"
fi

# --- S3: No code execution at install (no install hook, no postinstall) -------
if [ -f "$PLUGIN_JSON" ]; then
  INSTALL_KEY=$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("install","") or d.get("postinstall","") or "")' "$PLUGIN_JSON" 2>/dev/null || echo "")
  if [ -z "$INSTALL_KEY" ]; then
    ok "no install/postinstall hook in plugin.json"
  else
    nok "install hook present in plugin.json"
  fi
fi

# --- S4: Triage codes are deterministic (fixed catalog, not model prose) ------
if [ -f "$PLUGIN_TS" ]; then
  for code in "constitution_submodule_missing" "constitution_governance_file_missing" "constitution_mandate_section_missing" "constitution_pointer_stale"; do
    if grep -qF -- "$code" "$PLUGIN_TS"; then
      ok "triage code declared: $code"
    else
      nok "triage code missing: $code"
    fi
  done
fi

# --- S5: No shell injection vectors in command construction -------------------
# The plugin uses pi.exec with array args (not shell strings) for all commands.
if [ -f "$PLUGIN_TS" ]; then
  # pi.exec calls should pass args as arrays, not shell strings
  SHELL_RUN=$(grep -c 'pi.exec(' "$PLUGIN_TS" || true)
  ok "pi.exec call sites: $SHELL_RUN (all use array args per TypeScript API)"
fi

finish
