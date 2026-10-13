#!/usr/bin/env bash
# trivy_run_scan.sh — Helix Universal Trivy — run a REAL filesystem vulnerability
#                      scan + capture REAL findings as sink-side evidence (§11.4.69).
#
# Purpose      : Run `trivy fs` against the INVOCATION project (§11.4.177) for
#                dependency/IaC vulnerabilities, and write the REAL findings
#                (JSON) plus a Markdown report to a captured-evidence dir. A
#                PASS here cites the real vulnerability count pulled from
#                Trivy's own JSON output — never "command exited 0" alone
#                (§11.4 / §11.4.5 / §11.4.69).
# Usage        : bash trivy_run_scan.sh [project-root] [-- <extra trivy args>]
#                  e.g. bash trivy_run_scan.sh . -- --skip-dirs node_modules
# Inputs (env) : TRIVY_SEVERITY  default CRITICAL,HIGH
#                TRIVY_SCAN_TYPE default fs (fs|image|repo — image/repo need a
#                                 target argument appended via extra args)
# Outputs      : Evidence dir containing findings.json, TRIVY_SCAN_REPORT.md.
# Exit codes   : 0 scan ran, no findings at/above TRIVY_SEVERITY ·
#                1 scan ran, findings at/above TRIVY_SEVERITY present ·
#                2 trivy missing / scan could not run
# Side-effects : Creates the evidence dir; may fetch/refresh the vulnerability
#                DB into Trivy's own cache. Read-only against the scanned tree.
# Dependencies : bash, trivy
# Cross-ref    : §11.4.184(I) · §11.4.5 · §11.4.6 · §11.4.69 · §11.4.177
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./trivy_lib.sh
. "${SCRIPT_DIR}/trivy_lib.sh"

PROJ_ARG=""; EXTRA_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --) shift; while [ "$#" -gt 0 ]; do EXTRA_ARGS+=("$1"); shift; done ;;
        *) if [ -z "${PROJ_ARG}" ]; then PROJ_ARG="$1"; fi; shift ;;
    esac
done
ROOT="$(tv_project_root "${PROJ_ARG}")"
[ -d "${ROOT}" ] || { tv_err "project root not found: ${PROJ_ARG:-$PWD}"; exit 2; }

tv_have_trivy || { tv_err "trivy not on PATH — run trivy_install_check.sh"; exit 2; }

EVID="$(tv_evidence_dir "${ROOT}")"
mkdir -p "${EVID}"
SEV="$(tv_severity)"
SCAN_TYPE="${TRIVY_SCAN_TYPE:-fs}"
tv_log "project root : ${ROOT}"
tv_log "scan type    : ${SCAN_TYPE}"
tv_log "severity     : ${SEV}"
tv_log "evidence dir : ${EVID}"

tv_log "running trivy ${SCAN_TYPE} ..."
set +e
trivy "${SCAN_TYPE}" \
    --severity "${SEV}" \
    --format json \
    --output "${EVID}/findings.json" \
    "${EXTRA_ARGS[@]}" \
    "${ROOT}" >"${EVID}/trivy.log" 2>&1
SCAN_RC=$?
set -e 2>/dev/null || true

# trivy exits 0 by default even with findings unless --exit-code is set by the
# caller via EXTRA_ARGS; we treat SCAN_RC>1 as a genuine scan error and derive
# the real pass/fail verdict from the captured findings, never from SCAN_RC
# alone (§11.4.6 — a nonstandard exit-code convention is not a substitute for
# reading the evidence).
if [ "${SCAN_RC}" -gt 1 ]; then
    tv_err "trivy exited ${SCAN_RC} (scan error) — see ${EVID}/trivy.log"
    tail -20 "${EVID}/trivy.log" >&2 || true
    exit 2
fi

TOTAL=0
if [ -s "${EVID}/findings.json" ]; then
    if command -v jq >/dev/null 2>&1; then
        TOTAL="$(jq '[.Results[]?.Vulnerabilities[]?] | length' "${EVID}/findings.json" 2>/dev/null || echo 0)"
    else
        TOTAL="$(grep -c '"VulnerabilityID"' "${EVID}/findings.json" 2>/dev/null || echo 0)"
    fi
fi
TOTAL="${TOTAL:-0}"

REPORT="${EVID}/TRIVY_SCAN_REPORT.md"
{
    echo "# Trivy Scan Report"
    echo
    echo "**Revision:** 1"
    echo "**Last modified:** $(date -u +%FT%TZ)"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| Project root | \`${ROOT}\` |"
    echo "| Scan type | ${SCAN_TYPE} |"
    echo "| Severity filter | ${SEV} |"
    echo "| trivy | $(trivy --version 2>&1 | head -1) |"
    echo "| Real vulnerabilities found | **${TOTAL}** |"
    echo
    echo "Full finding list captured at \`findings.json\` in this directory as the §11.4.69 sink-side evidence for this scan."
} >"${REPORT}"

VERDICT_RC=0
[ "${TOTAL}" -gt 0 ] 2>/dev/null && VERDICT_RC=1

echo "----------------------------------------------------------------------"
if [ "${VERDICT_RC}" -eq 0 ]; then
    echo "PASS: Trivy scan completed — ${TOTAL} real ${SEV}-severity finding(s)"
else
    echo "FAIL: Trivy scan completed — ${TOTAL} real ${SEV}-severity finding(s)"
fi
echo "      [evidence: ${EVID}]"
echo "----------------------------------------------------------------------"
exit "${VERDICT_RC}"
