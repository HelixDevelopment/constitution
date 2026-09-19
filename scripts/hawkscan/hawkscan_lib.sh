#!/usr/bin/env bash
# hawkscan_lib.sh — Helix Universal HawkScan (StackHawk DAST) integration —
#                    shared library.
#
# Purpose      : Project-AGNOSTIC (§11.4.28) helpers shared by every HawkScan
#                script in this directory. Sourced, never executed directly.
#                Operates on the INVOCATION directory (§11.4.177) — never a
#                hardcoded project path or target.
#                HawkScan is the ONE tool under §11.4.184(I) that is
#                SaaS-backed, not self-contained: the scanner image always
#                authenticates against StackHawk's own backend. There is no
#                fully-local, no-account mode — see README.md for the
#                unavoidable manual, operator-only setup steps.
# Usage        : source "<constitution>/scripts/hawkscan/hawkscan_lib.sh"
# Inputs (env) : HAWK_API_KEY      REQUIRED for a real scan (never committed,
#                                  §11.4.10 — load from the project's
#                                  gitignored .env at runtime only)
#                HAWKSCAN_IMAGE    default docker.io/stackhawk/hawkscan
#                HAWKSCAN_CONFIG   path to the project's stackhawk.yml
#                                  (default: <project-root>/stackhawk.yml)
# Outputs      : Shell functions in the hs_* namespace.
# Side-effects : None on source.
# Dependencies : bash, podman (rootless, §11.4.161) or docker.
# Cross-ref    : §11.4.184(I) (this tool's mandate) · §11.4.6 (fail-open, never
#                fabricate a pass) · §11.4.10 (credentials) · §11.4.69
#                (sink-side evidence) · §11.4.177 (invocation dir).
#
# No `set -e` here (library) — callers own their own error policy.

HS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

hs_project_root() {
    if [ -n "${1:-}" ]; then ( cd "$1" 2>/dev/null && pwd ) && return 0; fi
    printf '%s' "${PWD}"
}

hs_log() { printf '[hawkscan] %s\n' "$*" >&2; }
hs_err() { printf '[hawkscan][ERROR] %s\n' "$*" >&2; }

hs_image() { printf '%s' "${HAWKSCAN_IMAGE:-docker.io/stackhawk/hawkscan}"; }

hs_have_runtime() { command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1; }
hs_runtime() {
    if command -v podman >/dev/null 2>&1; then printf 'podman'; return 0; fi
    if command -v docker >/dev/null 2>&1; then printf 'docker'; return 0; fi
    return 1
}

hs_config_path() {
    local root="${1:-$(hs_project_root)}"
    printf '%s' "${HAWKSCAN_CONFIG:-${root}/stackhawk.yml}"
}

# Fail-OPEN credential/config guard (§11.4.184(I) — a missing third-party
# credential is an operator setup gap, never a build/gate failure). Returns
# 0 = ready to scan, 1 = not ready (caller must print the warning and exit 0,
# never exit non-zero for a missing credential).
hs_ready() {
    local cfg="${1:-$(hs_config_path)}"
    [ -n "${HAWK_API_KEY:-}" ] || return 1
    [ -f "${cfg}" ] || return 1
    grep -q "REPLACE_WITH_REAL_STACKHAWK_APPLICATION_ID" "${cfg}" 2>/dev/null && return 1
    hs_have_runtime || return 1
    return 0
}

# <project-root>/qa-results/hawkscan/<UTC-timestamp>/
hs_evidence_dir() {
    local root ts
    root="$(hs_project_root "${1:-}")"
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    printf '%s/qa-results/hawkscan/%s' "${root}" "${ts}"
}
