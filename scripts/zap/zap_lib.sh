#!/usr/bin/env bash
# zap_lib.sh — Helix Universal OWASP ZAP integration — shared library.
#
# Purpose      : Project-AGNOSTIC (§11.4.28) helpers shared by every ZAP
#                script in this directory. Sourced, never executed directly.
#                Operates on the INVOCATION directory (§11.4.177) — never a
#                hardcoded project path or target.
#                ZAP baseline/full scans are ONE-SHOT rootless-podman
#                container runs (§11.4.161), not a long-lived daemon — unlike
#                SonarQube's singleton server, there is no persistent ZAP
#                service to bring up/down here.
# Usage        : source "<constitution>/scripts/zap/zap_lib.sh"
# Inputs (env) : ZAP_TARGET (the URL to scan; REQUIRED for a real scan)
#                ZAP_IMAGE  (default docker.io/zaproxy/zap-stable)
# Outputs      : Shell functions in the zap_* namespace.
# Side-effects : None on source.
# Dependencies : bash, podman (rootless, §11.4.161).
# Cross-ref    : §11.4.184(I) (this tool's mandate) · §11.4.69 (sink-side
#                evidence) · §11.4.161 (rootless) · §11.4.177 (invocation dir).
#
# No `set -e` here (library) — callers own their own error policy.

ZAP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

zap_project_root() {
    if [ -n "${1:-}" ]; then ( cd "$1" 2>/dev/null && pwd ) && return 0; fi
    printf '%s' "${PWD}"
}

zap_log() { printf '[zap] %s\n' "$*" >&2; }
zap_err() { printf '[zap][ERROR] %s\n' "$*" >&2; }

zap_have_podman() { command -v podman >/dev/null 2>&1; }
zap_image() { printf '%s' "${ZAP_IMAGE:-docker.io/zaproxy/zap-stable}"; }

# <project-root>/qa-results/zap/<UTC-timestamp>/
zap_evidence_dir() {
    local root ts
    root="$(zap_project_root "${1:-}")"
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    printf '%s/qa-results/zap/%s' "${root}" "${ts}"
}
