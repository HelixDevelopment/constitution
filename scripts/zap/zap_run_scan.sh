#!/usr/bin/env bash
# zap_run_scan.sh — Helix Universal OWASP ZAP — run a REAL baseline DAST scan
#                    against a locally-reachable target + capture REAL findings
#                    as sink-side evidence (§11.4.69).
#
# Purpose      : Run ZAP's own `zap-baseline.py` (bundled in the official
#                image) against ZAP_TARGET, a ONE-SHOT rootless-podman
#                container run (§11.4.161) — no persistent ZAP daemon. A PASS
#                here cites the real alert count pulled from ZAP's own JSON
#                report — never "container exited 0" alone (§11.4 / §11.4.5 /
#                §11.4.69).
# Usage        : ZAP_TARGET=http://127.0.0.1:8080 bash zap_run_scan.sh [project-root] [-- <extra zap-baseline.py args>]
# Inputs (env) : ZAP_TARGET REQUIRED — the base URL to scan, must be reachable
#                           from the container (use --network host on Linux,
#                           which this script does by default)
#                ZAP_IMAGE  default docker.io/zaproxy/zap-stable
# Outputs      : Evidence dir containing zap-report.json, ZAP_SCAN_REPORT.md.
# Exit codes   : 0 scan ran, ZAP baseline PASS (no WARN/FAIL alerts) ·
#                1 scan ran, ZAP baseline found WARN/FAIL alerts (its own
#                  convention) · 2 podman/target/config problem
# Side-effects : Creates the evidence dir; runs a network scan against
#                ZAP_TARGET (read-only/passive by default — zap-baseline.py
#                does not perform active/destructive attacks).
# Dependencies : bash, podman (rootless, §11.4.161)
# Cross-ref    : §11.4.184(I) · §11.4.5 · §11.4.6 · §11.4.69 · §11.4.161 · §11.4.177
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./zap_lib.sh
. "${SCRIPT_DIR}/zap_lib.sh"

PROJ_ARG=""; EXTRA_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --) shift; while [ "$#" -gt 0 ]; do EXTRA_ARGS+=("$1"); shift; done ;;
        *) if [ -z "${PROJ_ARG}" ]; then PROJ_ARG="$1"; fi; shift ;;
    esac
done
ROOT="$(zap_project_root "${PROJ_ARG}")"
[ -d "${ROOT}" ] || { zap_err "project root not found: ${PROJ_ARG:-$PWD}"; exit 2; }

zap_have_podman || { zap_err "podman not on PATH — run zap_install_check.sh"; exit 2; }
if [ -z "${ZAP_TARGET:-}" ]; then
    zap_err "ZAP_TARGET unset. Set it to the base URL to scan, e.g.:"
    zap_err "  ZAP_TARGET=http://127.0.0.1:8080 bash zap_run_scan.sh"
    exit 2
fi

IMAGE="$(zap_image)"
EVID="$(zap_evidence_dir "${ROOT}")"
mkdir -p "${EVID}"
zap_log "project root : ${ROOT}"
zap_log "target       : ${ZAP_TARGET}"
zap_log "image        : ${IMAGE}"
zap_log "evidence dir : ${EVID}"

zap_log "running zap-baseline.py (passive scan) ..."
set +e
podman run --rm \
    --network host \
    -v "${EVID}:/zap/wrk:Z" \
    "${IMAGE}" \
    zap-baseline.py \
    -t "${ZAP_TARGET}" \
    -J zap-report.json \
    -r zap-report.html \
    "${EXTRA_ARGS[@]}" >"${EVID}/zap.log" 2>&1
SCAN_RC=$?
set -e 2>/dev/null || true

# zap-baseline.py's own convention: 0 = no WARN/FAIL, 1 = WARN present,
# 2 = FAIL present, 3 = scan itself errored.
if [ "${SCAN_RC}" -gt 2 ]; then
    zap_err "zap-baseline.py exited ${SCAN_RC} (scan error) — see ${EVID}/zap.log"
    tail -30 "${EVID}/zap.log" >&2 || true
    exit 2
fi

TOTAL=0
if [ -s "${EVID}/zap-report.json" ]; then
    if command -v jq >/dev/null 2>&1; then
        TOTAL="$(jq '[.site[]?.alerts[]?] | length' "${EVID}/zap-report.json" 2>/dev/null || echo 0)"
    else
        TOTAL="$(grep -c '"alertRef"' "${EVID}/zap-report.json" 2>/dev/null || echo 0)"
    fi
fi
TOTAL="${TOTAL:-0}"

REPORT="${EVID}/ZAP_SCAN_REPORT.md"
{
    echo "# OWASP ZAP Baseline Scan Report"
    echo
    echo "**Revision:** 1"
    echo "**Last modified:** $(date -u +%FT%TZ)"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| Project root | \`${ROOT}\` |"
    echo "| Target | ${ZAP_TARGET} |"
    echo "| Image | ${IMAGE} |"
    echo "| Real alerts found | **${TOTAL}** |"
    echo
    echo "Full alert list captured at \`zap-report.json\` / \`zap-report.html\` in this directory as the §11.4.69 sink-side evidence for this scan."
} >"${REPORT}"

echo "----------------------------------------------------------------------"
if [ "${SCAN_RC}" -eq 0 ]; then
    echo "PASS: ZAP baseline scan completed — ${TOTAL} real alert(s)"
else
    echo "FAIL: ZAP baseline scan completed — ${TOTAL} real alert(s) (rc=${SCAN_RC})"
fi
echo "      [evidence: ${EVID}]"
echo "----------------------------------------------------------------------"
[ "${SCAN_RC}" -eq 0 ] && exit 0 || exit 1
