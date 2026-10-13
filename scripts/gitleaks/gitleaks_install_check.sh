#!/usr/bin/env bash
# gitleaks_install_check.sh — Helix Universal gitleaks — install verifier.
#
# Purpose      : Prove the gitleaks CLI is installed and runnable BEFORE any
#                scan is attempted (§11.4.108 install/ARTIFACT layer). Emits
#                the observed version as captured evidence (§11.4.6 — state
#                the fact, never assume).
# Usage        : bash gitleaks_install_check.sh
# Inputs       : none (reads PATH)
# Outputs      : Human-readable report on stdout; exit 0 = gitleaks runnable.
# Exit codes   : 0 present+runnable · 1 missing/broken
# Side-effects : none (read-only probe)
# Dependencies : bash, gitleaks
# Cross-ref    : §11.4.184(I) · §11.4.69 · §11.4.108
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./gitleaks_lib.sh
. "${SCRIPT_DIR}/gitleaks_lib.sh"

rc=0
echo "=== gitleaks integration — install check ==="

if gl_have_gitleaks; then
    ver_line="$(gitleaks version 2>&1 | head -1)"
    if [ -n "${ver_line}" ]; then
        echo "PASS  gitleaks: $(command -v gitleaks) — ${ver_line}"
    else
        echo "FAIL  gitleaks found but 'version' produced no output"
        rc=1
    fi
else
    echo "FAIL  gitleaks NOT on PATH."
    echo "      Install: package manager (e.g. 'brew install gitleaks', 'apt install gitleaks'"
    echo "      where packaged) or download a release binary from"
    echo "      https://github.com/gitleaks/gitleaks/releases and place it on PATH."
    echo "      No account, no server, no network callout required to run it."
    rc=1
fi

echo "=== install check exit ${rc} ==="
exit "${rc}"
