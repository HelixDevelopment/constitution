#!/usr/bin/env bash
# trivy_lib.sh — Helix Universal Trivy integration — shared library.
#
# Purpose      : Project-AGNOSTIC (§11.4.28) helpers shared by every Trivy
#                script in this directory. Sourced, never executed directly.
#                Operates on the INVOCATION directory (§11.4.177) — never a
#                hardcoded project path.
# Usage        : source "<constitution>/scripts/trivy/trivy_lib.sh"
# Inputs (env) : TRIVY_SEVERITY (default CRITICAL,HIGH)
#                TRIVY_CACHE_DIR (default ~/.cache/trivy — Trivy's own default)
# Outputs      : Shell functions in the tv_* namespace.
# Side-effects : None on source.
# Dependencies : bash, trivy (binary or package-manager install; DB pull is
#                cacheable/refreshable offline after first fetch).
# Cross-ref    : §11.4.184(I) (this tool's mandate) · §11.4.69 (sink-side
#                evidence) · §11.4.177 (invocation dir).
#
# No `set -e` here (library) — callers own their own error policy.

TV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tv_project_root() {
    if [ -n "${1:-}" ]; then ( cd "$1" 2>/dev/null && pwd ) && return 0; fi
    printf '%s' "${PWD}"
}

tv_log() { printf '[trivy] %s\n' "$*" >&2; }
tv_err() { printf '[trivy][ERROR] %s\n' "$*" >&2; }

tv_have_trivy() { command -v trivy >/dev/null 2>&1; }
tv_severity() { printf '%s' "${TRIVY_SEVERITY:-CRITICAL,HIGH}"; }

# <project-root>/qa-results/trivy/<UTC-timestamp>/
tv_evidence_dir() {
    local root ts
    root="$(tv_project_root "${1:-}")"
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    printf '%s/qa-results/trivy/%s' "${root}" "${ts}"
}
