#!/usr/bin/env bash
# hawkscan_install_check.sh — Helix Universal HawkScan — install verifier.
#
# Purpose      : Prove the LOCAL prerequisites (container runtime, image
#                pullable) are met, and REPORT — without failing the build —
#                whether the operator-only StackHawk account/Application setup
#                has been completed. This gate's PASS bar for HawkScan is
#                "correctly scaffolded with a fail-open guard," never "an
#                account exists," per §11.4.184(I)'s honest boundary.
# Usage        : bash hawkscan_install_check.sh [project-root]
# Inputs (env) : HAWK_API_KEY, HAWKSCAN_CONFIG (see hawkscan_lib.sh)
# Outputs      : Human-readable report on stdout.
# Exit codes   : 0 ALWAYS for the credential/config half (fail-open, §11.4.184(I))
#                unless the container runtime itself is absent, which is a
#                real local-environment gap → exit 1.
# Side-effects : May pull the HawkScan image if not already cached.
# Dependencies : bash, podman or docker
# Cross-ref    : §11.4.184(I) · §11.4.6 · §11.4.69 · §11.4.108 · §11.4.161
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hawkscan_lib.sh
. "${SCRIPT_DIR}/hawkscan_lib.sh"

ROOT="$(hs_project_root "${1:-}")"
echo "=== HawkScan integration — install check ==="
echo "project root: ${ROOT}"

if hs_have_runtime; then
    RT="$(hs_runtime)"
    echo "PASS  container runtime: ${RT} ($(${RT} --version 2>&1 | head -1))"
else
    echo "FAIL  neither podman nor docker is available on this host."
    echo "=== install check exit 1 ==="
    exit 1
fi

IMAGE="$(hs_image)"
RT="$(hs_runtime)"
if "${RT}" image exists "${IMAGE}" 2>/dev/null || "${RT}" images -q "${IMAGE}" 2>/dev/null | grep -q .; then
    echo "PASS  HawkScan image already present locally: ${IMAGE}"
else
    echo "INFO  HawkScan image not cached locally — pulling ${IMAGE} ..."
    if "${RT}" pull "${IMAGE}" >/dev/null 2>&1; then
        echo "PASS  HawkScan image pulled: ${IMAGE}"
    else
        echo "WARN  could not pull ${IMAGE} — check network/registry reachability"
        echo "      (this does not fail the gate — see the credential check below)"
    fi
fi

CFG="$(hs_config_path "${ROOT}")"
if [ -z "${HAWK_API_KEY:-}" ]; then
    echo "WARN  HAWK_API_KEY is not set — HawkScan is SaaS-backed and cannot run without it."
    echo "      This is expected until an operator completes StackHawk account setup."
    echo "      See README.md in this directory for the step-by-step key-acquisition guide."
elif [ ! -f "${CFG}" ]; then
    echo "WARN  no stackhawk.yml found at ${CFG} — create one from stackhawk.yml.example."
elif grep -q "REPLACE_WITH_REAL_STACKHAWK_APPLICATION_ID" "${CFG}" 2>/dev/null; then
    echo "WARN  ${CFG} still has the placeholder applicationId — create a real"
    echo "      Application at app.stackhawk.com and paste its id in."
else
    echo "PASS  HAWK_API_KEY set + ${CFG} configured with a real applicationId"
    echo "      (a live scan will still verify the key/applicationId are VALID"
    echo "      against StackHawk's backend — presence here is not proof of validity)"
fi

echo "=== install check exit 0 (fail-open on credential state, §11.4.184(I)) ==="
exit 0
