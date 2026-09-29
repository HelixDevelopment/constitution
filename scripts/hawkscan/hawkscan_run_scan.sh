#!/usr/bin/env bash
# hawkscan_run_scan.sh — Helix Universal HawkScan — run a REAL DAST scan via
#                         StackHawk's backend, or fail OPEN with a loud warning
#                         if the operator-only account setup is incomplete.
#
# Purpose      : Run HawkScan against the INVOCATION project's configured
#                target (§11.4.177), and capture StackHawk's REAL findings as
#                sink-side evidence (§11.4.69) when credentials are present.
#                NEVER blocks other work over a missing third-party credential
#                (§11.4.184(I)) — that is an operator setup gap, not a build
#                or gate failure.
# Usage        : bash hawkscan_run_scan.sh [project-root] [-- <extra hawk args>]
# Inputs (env) : HAWK_API_KEY REQUIRED for a real scan (never committed)
#                HAWKSCAN_CONFIG path to stackhawk.yml (default project-root)
#                HAWKSCAN_TARGET_OVERRIDE optional app.host override
# Outputs      : Evidence dir containing hawkscan.log (+ StackHawk-side report,
#                viewable in the StackHawk dashboard — findings are NOT
#                mirrored locally by the scanner itself beyond the console log).
# Exit codes   : 0 SKIPPED (missing credential/config/runtime — fail-open) OR
#                scan ran with no findings above policy threshold ·
#                1 scan ran, findings above policy threshold (HawkScan's own
#                  exit convention) · 2 scan itself errored (runtime/network)
# Side-effects : Creates the evidence dir; on a real run, submits a scan to
#                StackHawk's backend and authenticates with HAWK_API_KEY
#                (never printed to logs).
# Dependencies : bash, podman or docker
# Cross-ref    : §11.4.184(I) · §11.4.5 · §11.4.6 · §11.4.10 · §11.4.69 · §11.4.177
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hawkscan_lib.sh
. "${SCRIPT_DIR}/hawkscan_lib.sh"

PROJ_ARG=""; EXTRA_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --) shift; while [ "$#" -gt 0 ]; do EXTRA_ARGS+=("$1"); shift; done ;;
        *) if [ -z "${PROJ_ARG}" ]; then PROJ_ARG="$1"; fi; shift ;;
    esac
done
ROOT="$(hs_project_root "${PROJ_ARG}")"
[ -d "${ROOT}" ] || { hs_err "project root not found: ${PROJ_ARG:-$PWD}"; exit 2; }

CFG="$(hs_config_path "${ROOT}")"

warn_and_skip() {
    cat >&2 <<EOF

⚠️  HawkScan SKIPPED — $1

    This does NOT block your work. HawkScan is a third-party DAST scanner
    (StackHawk) requiring an account and API key this host does not have
    configured. See scripts/hawkscan/README.md for setup steps. Per
    §11.4.184(I), a missing third-party credential is an operator setup
    gap, never a build/gate failure.

EOF
    exit 0
}

[ -n "${HAWK_API_KEY:-}" ] || warn_and_skip "HAWK_API_KEY is not set in the environment."
[ -f "${CFG}" ] || warn_and_skip "no stackhawk.yml found at ${CFG} (see stackhawk.yml.example)."
grep -q "REPLACE_WITH_REAL_STACKHAWK_APPLICATION_ID" "${CFG}" 2>/dev/null && \
    warn_and_skip "${CFG} still has the placeholder applicationId — create a real Application at app.stackhawk.com first."
hs_have_runtime || warn_and_skip "neither podman nor docker is available on this host."

RT="$(hs_runtime)"
IMAGE="$(hs_image)"
EVID="$(hs_evidence_dir "${ROOT}")"
mkdir -p "${EVID}"
hs_log "project root : ${ROOT}"
hs_log "config       : ${CFG}"
hs_log "runtime      : ${RT}"
hs_log "evidence dir : ${EVID}"

EXTRA_HAWK_ARGS=()
if [ -n "${HAWKSCAN_TARGET_OVERRIDE:-}" ]; then
    EXTRA_HAWK_ARGS+=(-e "app.host=${HAWKSCAN_TARGET_OVERRIDE}")
fi

hs_log "running HawkScan via ${RT} ..."
set +e
"${RT}" run --rm \
    --network host \
    -e "HAWK_API_KEY=${HAWK_API_KEY}" \
    -v "${CFG}:/hawk/stackhawk.yml:ro" \
    "${IMAGE}" \
    "${EXTRA_HAWK_ARGS[@]}" \
    "${EXTRA_ARGS[@]}" >"${EVID}/hawkscan.log" 2>&1
SCAN_RC=$?
set -e 2>/dev/null || true

if [ "${SCAN_RC}" -gt 1 ]; then
    hs_err "HawkScan exited ${SCAN_RC} (scan error) — see ${EVID}/hawkscan.log"
    tail -30 "${EVID}/hawkscan.log" >&2 || true
    exit 2
fi

REPORT="${EVID}/HAWKSCAN_SCAN_REPORT.md"
{
    echo "# HawkScan Scan Report"
    echo
    echo "**Revision:** 1"
    echo "**Last modified:** $(date -u +%FT%TZ)"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| Project root | \`${ROOT}\` |"
    echo "| Config | \`${CFG}\` |"
    echo "| Image | ${IMAGE} |"
    echo "| Exit code | ${SCAN_RC} |"
    echo
    echo "HawkScan reports its full findings in the StackHawk dashboard for the"
    echo "configured \`applicationId\`; \`hawkscan.log\` in this directory captures"
    echo "the console output as local §11.4.69 sink-side evidence of the run itself."
} >"${REPORT}"

echo "----------------------------------------------------------------------"
if [ "${SCAN_RC}" -eq 0 ]; then
    echo "PASS: HawkScan scan completed — no findings above policy threshold"
else
    echo "FAIL: HawkScan scan completed — findings above policy threshold (see StackHawk dashboard)"
fi
echo "      [evidence: ${EVID}]"
echo "----------------------------------------------------------------------"
exit "${SCAN_RC}"
