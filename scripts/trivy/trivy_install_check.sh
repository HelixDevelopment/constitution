#!/usr/bin/env bash
# trivy_install_check.sh — Helix Universal Trivy — install verifier.
#
# Purpose      : Prove the Trivy CLI is installed and runnable BEFORE any scan
#                is attempted (§11.4.108 install/ARTIFACT layer). Emits the
#                observed version as captured evidence (§11.4.6).
# Usage        : bash trivy_install_check.sh
# Inputs       : none (reads PATH)
# Outputs      : Human-readable report on stdout; exit 0 = trivy runnable.
# Exit codes   : 0 present+runnable · 1 missing/broken
# Side-effects : none (read-only probe)
# Dependencies : bash, trivy
# Cross-ref    : §11.4.184(I) · §11.4.69 · §11.4.108
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./trivy_lib.sh
. "${SCRIPT_DIR}/trivy_lib.sh"

rc=0
echo "=== Trivy integration — install check ==="

if tv_have_trivy; then
    ver_line="$(trivy --version 2>&1 | head -1)"
    if [ -n "${ver_line}" ]; then
        echo "PASS  trivy: $(command -v trivy) — ${ver_line}"
    else
        echo "FAIL  trivy found but '--version' produced no output"
        rc=1
    fi
else
    echo "FAIL  trivy NOT on PATH."
    echo "      Install: package manager (e.g. 'brew install trivy', or the"
    echo "      apt/yum repo per https://aquasecurity.github.io/trivy) or the"
    echo "      install.sh from https://github.com/aquasecurity/trivy/releases."
    echo "      No account required to run it; the vulnerability DB is fetched"
    echo "      on first use and cached (refreshable offline thereafter)."
    rc=1
fi

echo "=== install check exit ${rc} ==="
exit "${rc}"
