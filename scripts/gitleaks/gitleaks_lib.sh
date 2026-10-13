#!/usr/bin/env bash
# gitleaks_lib.sh — Helix Universal gitleaks integration — shared library.
#
# Purpose      : Project-AGNOSTIC (§11.4.28) helpers shared by every gitleaks
#                script in this directory. Sourced, never executed directly.
#                Operates on the INVOCATION directory (§11.4.177) — never a
#                hardcoded project path — so any project that inherits the
#                constitution submodule gets it working on its own tree.
#                Complements, does NOT replace, this constitution's own
#                credential_scan_lib.sh pre-commit-hook-seam detector —
#                no prior anchor declares that detector exclusive.
# Usage        : source "<constitution>/scripts/gitleaks/gitleaks_lib.sh"
# Inputs (env) : GITLEAKS_CONFIG (optional path to a .gitleaks.toml)
# Outputs      : Shell functions in the gl_* namespace.
# Side-effects : None on source.
# Dependencies : bash, gitleaks (binary or package-manager install; no server).
# Cross-ref    : §11.4.184(I) (this tool's mandate) · §11.4.10 (credentials) ·
#                §11.4.69 (sink-side evidence) · §11.4.177 (invocation dir).
#
# No `set -e` here (library) — callers own their own error policy.

GL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

gl_project_root() {
    if [ -n "${1:-}" ]; then ( cd "$1" 2>/dev/null && pwd ) && return 0; fi
    printf '%s' "${PWD}"
}

gl_log() { printf '[gitleaks] %s\n' "$*" >&2; }
gl_err() { printf '[gitleaks][ERROR] %s\n' "$*" >&2; }

gl_have_gitleaks() { command -v gitleaks >/dev/null 2>&1; }

# <project-root>/qa-results/gitleaks/<UTC-timestamp>/
gl_evidence_dir() {
    local root ts
    root="$(gl_project_root "${1:-}")"
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    printf '%s/qa-results/gitleaks/%s' "${root}" "${ts}"
}
