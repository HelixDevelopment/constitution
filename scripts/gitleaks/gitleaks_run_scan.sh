#!/usr/bin/env bash
# gitleaks_run_scan.sh — Helix Universal gitleaks — run a REAL secrets scan +
#                         capture REAL findings as sink-side evidence (§11.4.69).
#
# Purpose      : Run `gitleaks detect` against the INVOCATION project
#                (§11.4.177), covering the full git history by default, and
#                write the REAL findings (JSON) plus a Markdown report to a
#                captured-evidence dir. A PASS here cites the real findings
#                count pulled from gitleaks' own report — never "command
#                exited 0" alone (§11.4 / §11.4.5 / §11.4.69).
# Usage        : bash gitleaks_run_scan.sh [project-root] [-- <extra gitleaks args>]
# Inputs (env) : GITLEAKS_CONFIG override path to a .gitleaks.toml
# Outputs      : Evidence dir containing findings.json, GITLEAKS_SCAN_REPORT.md.
# Exit codes   : 0 scan ran, ZERO leaks found ·
#                1 scan ran, ONE OR MORE leaks found (gitleaks' own convention) ·
#                2 gitleaks missing / scan could not run
# Side-effects : Creates the evidence dir. Read-only against the scanned repo.
# Dependencies : bash, gitleaks
# Cross-ref    : §11.4.184(I) · §11.4.5 · §11.4.6 · §11.4.69 · §11.4.177
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./gitleaks_lib.sh
. "${SCRIPT_DIR}/gitleaks_lib.sh"

PROJ_ARG=""; EXTRA_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --) shift; while [ "$#" -gt 0 ]; do EXTRA_ARGS+=("$1"); shift; done ;;
        *) if [ -z "${PROJ_ARG}" ]; then PROJ_ARG="$1"; fi; shift ;;
    esac
done
ROOT="$(gl_project_root "${PROJ_ARG}")"
[ -d "${ROOT}" ] || { gl_err "project root not found: ${PROJ_ARG:-$PWD}"; exit 2; }

gl_have_gitleaks || { gl_err "gitleaks not on PATH — run gitleaks_install_check.sh"; exit 2; }

EVID="$(gl_evidence_dir "${ROOT}")"
mkdir -p "${EVID}"
gl_log "project root : ${ROOT}"
gl_log "evidence dir : ${EVID}"

CFG_ARGS=()
if [ -n "${GITLEAKS_CONFIG:-}" ] && [ -f "${GITLEAKS_CONFIG}" ]; then
    CFG_ARGS=(--config "${GITLEAKS_CONFIG}")
    gl_log "using config: ${GITLEAKS_CONFIG}"
elif [ -f "${ROOT}/.gitleaks.toml" ]; then
    CFG_ARGS=(--config "${ROOT}/.gitleaks.toml")
    gl_log "using project config: ${ROOT}/.gitleaks.toml"
fi

gl_log "running gitleaks detect (full history) ..."
set +e
( cd "${ROOT}" && gitleaks detect \
    --source "${ROOT}" \
    --report-format json \
    --report-path "${EVID}/findings.json" \
    --no-banner \
    "${CFG_ARGS[@]}" \
    "${EXTRA_ARGS[@]}" ) >"${EVID}/gitleaks.log" 2>&1
SCAN_RC=$?
set -e 2>/dev/null || true

# gitleaks' own convention: 0 = no leaks, 1 = leaks found, >1 = scan error.
if [ "${SCAN_RC}" -gt 1 ]; then
    gl_err "gitleaks exited ${SCAN_RC} (scan error) — see ${EVID}/gitleaks.log"
    tail -20 "${EVID}/gitleaks.log" >&2 || true
    exit 2
fi

TOTAL=0
if [ -s "${EVID}/findings.json" ]; then
    if command -v jq >/dev/null 2>&1; then
        TOTAL="$(jq 'length' "${EVID}/findings.json" 2>/dev/null || echo 0)"
    else
        TOTAL="$(grep -c '"RuleID"' "${EVID}/findings.json" 2>/dev/null || echo 0)"
    fi
fi
TOTAL="${TOTAL:-0}"

REPORT="${EVID}/GITLEAKS_SCAN_REPORT.md"
{
    echo "# gitleaks Scan Report"
    echo
    echo "**Revision:** 1"
    echo "**Last modified:** $(date -u +%FT%TZ)"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| Project root | \`${ROOT}\` |"
    echo "| gitleaks | $(gitleaks version 2>&1 | head -1) |"
    echo "| Real findings (leaks) | **${TOTAL}** |"
    echo
    echo "Full finding list captured at \`findings.json\` in this directory as the §11.4.69 sink-side evidence for this scan."
} >"${REPORT}"

echo "----------------------------------------------------------------------"
if [ "${SCAN_RC}" -eq 0 ]; then
    echo "PASS: gitleaks scan completed — ${TOTAL} real leak(s) found"
else
    echo "FAIL: gitleaks scan completed — ${TOTAL} real leak(s) found"
fi
echo "      [evidence: ${EVID}]"
echo "----------------------------------------------------------------------"
exit "${SCAN_RC}"
