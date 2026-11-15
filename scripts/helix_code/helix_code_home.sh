#!/usr/bin/env bash
# ============================================================================
# helix_code_home.sh — resolve HELIX_CODE_HOME + HELIX_CODE_REMOTE_BASE_URL
#
# Purpose:    §11.4.6 no-guessing HELIX_CODE_HOME resolver. Mirrors the
#             env-else-submodule-default idiom from subagent_tier.sh:53-54 +
#             the 3-tier env→.env→derived-default from release_prefix.sh:67-75.
#             SOURCED library — consumers do `source helix_code_home.sh && hc_home`.
#
# Usage:      source constitution/scripts/helix_code/helix_code_home.sh
#             home="$(hc_home)"           # resolved meta-repo path (clones if needed)
#             base="$(hc_remote_base)"    # remote base URL (mode=remote) or empty
#
# Resolution (3-case contract, INTEGRATION_PLAN.md §2.1):
#   1. $HELIX_CODE_HOME env → project .env → default = <project-root>/submodules/helix_code
#   2. If path exists + non-empty + has .git → use it (ensure submodules)
#   3. If path absent/empty → full recursive clone into it
#
# Outputs:    hc_home prints the resolved path to stdout.
#             hc_remote_base prints the remote base URL (empty if mode=local).
# Side-effects: may clone HelixCode if case (b) triggers (stderr progress).
# Dependencies: bash, git, grep, sed, curl (optional for health checks).
# Anti-bluff (§11.4.6): case (a) trusts ONLY if .git exists AND dir non-empty;
#             never "var is set → assume valid".
# Cross-references: docs/helix_code/INTEGRATION_PLAN.md §2,
#             docs/helix_code/CLAUDE_TOOLKIT_EXTENSION.md §2,
#             docs/helix_code/CONSTITUTION_DESIGN.md §3,
#             Constitution §11.4.6, §11.4.28, §11.4.177.
# Revision:   1
# Last modified: 2026-07-17T00:00:00Z
# ============================================================================
set -euo pipefail

# Guard: do not re-source if already loaded
[ "${_HELIX_CODE_HOME_LOADED:-0}" = "1" ] && return 0
_HELIX_CODE_HOME_LOADED=1

# --- internal helpers --------------------------------------------------------

# Every git call goes through hc__git. This file is SOURCED, so the scrub runs in a
# subshell and never clears the consumer shell's own git variables (CON-402).
hc__git() {
  (
    for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: subshell-scoped (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
    exec git "$@"
  )
}

hc__script_dir() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P
}

# Consumer project root: env override else git superproject working tree.
# Mirrors multitrack_config.sh:mt_repo_root (lines 62-90).
hc__project_root() {
  if [ -n "${HELIX_PROJECT_ROOT:-}" ]; then
    printf '%s' "$HELIX_PROJECT_ROOT"
    return 0
  fi
  local sp
  sp="$(hc__git -C "$(hc__script_dir)" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [ -n "$sp" ]; then
    printf '%s' "$sp"
    return 0
  fi
  hc__git -C "$(hc__script_dir)" rev-parse --show-toplevel 2>/dev/null
}

# Load a project-local .env value without exporting the whole file.
# Mirrors release_prefix.sh:38-42 pattern.
hc__from_dotenv() {  # $1 = var name
  local root f
  root="$(hc__project_root)"
  f="$root/.env"
  [ -f "$f" ] || return 1
  grep -E "^\s*(export\s+)?${1}=" "$f" 2>/dev/null \
    | tail -n1 \
    | sed -E "s/^\s*(export\s+)?${1}=//; s/^[\"']//; s/[\"']\s*$//"
}

# --- public API --------------------------------------------------------------

# HELIX_CODE_HOME resolution (the 3-case contract, INTEGRATION_PLAN.md §2.1).
# Prints the resolved meta-repo path to stdout. May clone on first use (stderr).
hc_home() {
  local root home
  root="$(hc__project_root)"

  # (1) env else .env else (2) default submodule path
  home="${HELIX_CODE_HOME:-$(hc__from_dotenv HELIX_CODE_HOME 2>/dev/null || true)}"
  if [ -z "$home" ]; then
    home="$root/submodules/helix_code"  # case (c): UNSET → default
  fi

  # case (a): present + non-empty → ensure submodules, use it
  if [ -d "$home/.git" ] && [ -n "$(ls -A "$home" 2>/dev/null)" ]; then
    hc__git -C "$home" submodule update --init --recursive >&2 || true
    printf '%s' "$home"
    return 0
  fi

  # case (b): set-but-empty/absent → full recursive clone into it
  mkdir -p "$home"
  if [ -z "$(ls -A "$home" 2>/dev/null)" ]; then
    echo "[helix_code_home] Cloning HelixCode into $home ..." >&2
    hc__git clone --recursive git@github.com:HelixDevelopment/HelixCode.git "$home" >&2
  fi
  printf '%s' "$home"
}

# Remote base URL (mode=remote): api_keys.sh OR project .env.
# Prints empty if mode=local (the default).
hc_remote_base() {
  [ "${HELIX_CODE_MODE:-local}" = "remote" ] || { printf ''; return 0; }
  # api_keys.sh is sourced by the login shell (~/.bashrc), so the var is already
  # in-env when a login shell ran it; fall back to project .env otherwise.
  if [ -n "${HELIX_CODE_REMOTE_BASE_URL:-}" ]; then
    printf '%s' "$HELIX_CODE_REMOTE_BASE_URL"
    return 0
  fi
  hc__from_dotenv HELIX_CODE_REMOTE_BASE_URL 2>/dev/null || printf ''
}

# Health check helper: curl a service endpoint, print OK/FAIL.
# Usage: hc_health [host] [port] [path]
hc_health() {
  local host="${1:-localhost}" port="${2:-8080}" path="${3:-/health}"
  if curl -fsS --max-time 5 "http://${host}:${port}${path}" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    return 1
  fi
}
