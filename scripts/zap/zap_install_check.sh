#!/usr/bin/env bash
# zap_install_check.sh — Helix Universal OWASP ZAP — install verifier.
#
# Purpose      : Prove rootless podman is present and the ZAP image is pullable
#                BEFORE any scan is attempted (§11.4.108 install/ARTIFACT
#                layer). ZAP itself ships only as a container image here —
#                there is no separate host-installed "zap" binary to check for.
# Usage        : bash zap_install_check.sh
# Inputs       : none (reads PATH; may pull the ZAP image if absent)
# Outputs      : Human-readable report on stdout; exit 0 = ZAP runnable.
# Exit codes   : 0 podman present + image pulled/pullable · 1 podman missing ·
#                2 image pull failed (network / registry problem)
# Side-effects : May pull docker.io/zaproxy/zap-stable (a few hundred MB) if
#                not already cached locally.
# Dependencies : bash, podman (rootless, §11.4.161)
# Cross-ref    : §11.4.184(I) · §11.4.69 · §11.4.108 · §11.4.161
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./zap_lib.sh
. "${SCRIPT_DIR}/zap_lib.sh"

rc=0
echo "=== OWASP ZAP integration — install check ==="

if zap_have_podman; then
    echo "PASS  podman: $(podman --version 2>&1)"
else
    echo "FAIL  podman NOT on PATH (rootless podman is required, §11.4.161)"
    echo "=== install check exit 1 ==="
    exit 1
fi

IMAGE="$(zap_image)"
if podman image exists "${IMAGE}" 2>/dev/null; then
    echo "PASS  ZAP image already present locally: ${IMAGE}"
else
    echo "INFO  ZAP image not cached locally — pulling ${IMAGE} (one-time, no account needed) ..."
    if podman pull "${IMAGE}" >/dev/null 2>&1; then
        echo "PASS  ZAP image pulled: ${IMAGE}"
    else
        echo "FAIL  could not pull ${IMAGE} — check network/registry reachability"
        rc=2
    fi
fi

echo "=== install check exit ${rc} ==="
exit "${rc}"
