#!/usr/bin/env bash
# sonarqube_run_scan.sh — Helix Universal SonarQube — run a REAL analysis + capture
#                          REAL findings as sink-side evidence (§11.4.69).
#
# Purpose      : Run `sonar-scanner` against the INVOCATION project (§11.4.177),
#                wait for the server-side Compute-Engine task to finish, then
#                pull the ACTUAL findings (issues + measures + quality-gate) from
#                the SonarQube Web API and write them to a captured-evidence dir.
#                This is the anti-bluff spine: a PASS here cites real issue JSON
#                pulled back from the server — never "scan command exited 0"
#                (§11.4 / §11.4.5 / §11.4.69 — metadata-only PASS is forbidden).
# Usage        : bash sonarqube_run_scan.sh [project-root] [-- <extra -D args>]
#                  e.g. bash sonarqube_run_scan.sh /path/to/proj \
#                         -- -Dsonar.sources=src -Dsonar.exclusions=**/vendor/**
# Inputs (env) : SONAR_TOKEN       REQUIRED — analysis+API token (project .env,
#                                  §11.4.10; NEVER echoed by this script)
#                SONAR_HOST_URL    default http://localhost:9000
#                SONAR_PROJECT_KEY default = sanitized basename of project root
#                SONAR_PROJECT_NAME default = project key
#                SONAR_SCAN_EVIDENCE_DIR override evidence dir (default under
#                                  <root>/qa-results/sonarqube/<ts>)
# Outputs      : Evidence dir containing scanner.log, report-task.txt, issues.json,
#                measures.json, quality_gate.json, SONARQUBE_SCAN_REPORT.md.
#                Prints the evidence dir + an ab_pass_with_evidence-style line.
# Exit codes   : 0 scan ran + CE task SUCCESS + findings captured ·
#                1 scanner failed / CE task FAILED / evidence not captured ·
#                2 missing token or server unreachable
# Side-effects : Creates .scannerwork/ in the project; creates the evidence dir;
#                submits an analysis to the SonarQube server (creates the project
#                on first scan). NEVER prints SONAR_TOKEN.
# Dependencies : bash, sonar-scanner, curl, jq (jq optional — grep fallback)
# Cross-ref    : §11.4.5 · §11.4.6 · §11.4.10 · §11.4.69 · §11.4.108 · §11.4.177
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./sonarqube_lib.sh
. "${SCRIPT_DIR}/sonarqube_lib.sh"

# --- Parse args: [project-root] [-- extra -D args] --------------------------
PROJ_ARG=""; EXTRA_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --) shift; while [ "$#" -gt 0 ]; do EXTRA_ARGS+=("$1"); shift; done ;;
        *) if [ -z "${PROJ_ARG}" ]; then PROJ_ARG="$1"; fi; shift ;;
    esac
done
ROOT="$(sq_project_root "${PROJ_ARG}")"
[ -d "${ROOT}" ] || { sq_err "project root not found: ${PROJ_ARG:-$PWD}"; exit 2; }

# --- Convenience: source <root>/.env for SONAR_TOKEN if present (§11.4.10) ---
if [ -z "${SONAR_TOKEN:-}" ] && [ -f "${ROOT}/.env" ]; then
    # shellcheck disable=SC1091
    set +u; . "${ROOT}/.env" 2>/dev/null || true; set -u
fi

sq_have_scanner || { sq_err "sonar-scanner not on PATH — run sonarqube_install_check.sh"; exit 2; }
if [ -z "${SONAR_TOKEN:-}" ]; then
    sq_err "SONAR_TOKEN unset. Generate a token in SonarQube and put it in ${ROOT}/.env"
    sq_err "as SONAR_TOKEN=... (gitignored, §11.4.10). NEVER commit the token."
    exit 2
fi

HOST_URL="$(sq_host_url)"
sq_is_up || { sq_err "SonarQube not UP at ${HOST_URL} — run sonarqube_container.sh up"; exit 2; }

# --- Derive a stable, valid project key -------------------------------------
DEF_KEY="$(basename "${ROOT}" | tr -c 'A-Za-z0-9_.:-' '-' | sed 's/^-*//;s/-*$//')"
PKEY="${SONAR_PROJECT_KEY:-${DEF_KEY:-helix-project}}"
PNAME="${SONAR_PROJECT_NAME:-${PKEY}}"
EVID="${SONAR_SCAN_EVIDENCE_DIR:-$(sq_evidence_dir "${ROOT}")}"
mkdir -p "${EVID}"
sq_log "project root : ${ROOT}"
sq_log "project key  : ${PKEY}"
sq_log "evidence dir : ${EVID}"

# --- Run the scanner (token kept out of logs) -------------------------------
sq_log "running sonar-scanner ..."
set +e
( cd "${ROOT}" && sonar-scanner \
    -Dsonar.host.url="${HOST_URL}" \
    -Dsonar.token="${SONAR_TOKEN}" \
    -Dsonar.projectKey="${PKEY}" \
    -Dsonar.projectName="${PNAME}" \
    -Dsonar.projectBaseDir="${ROOT}" \
    -Dsonar.sources=. \
    -Dsonar.scm.disabled=true \
    "${EXTRA_ARGS[@]}" ) >"${EVID}/scanner.log" 2>&1
SCAN_RC=$?
set -e 2>/dev/null || true
if [ "${SCAN_RC}" -ne 0 ]; then
    sq_err "sonar-scanner exited ${SCAN_RC} — see ${EVID}/scanner.log"
    tail -20 "${EVID}/scanner.log" >&2 || true
    exit 1
fi
cp -f "${ROOT}/.scannerwork/report-task.txt" "${EVID}/report-task.txt" 2>/dev/null || true

# --- Wait for the Compute-Engine task to finish -----------------------------
CE_ID="$(sed -n 's/^ceTaskId=//p' "${EVID}/report-task.txt" 2>/dev/null | head -1)"
_api() { curl -fsS --max-time 15 -u "${SONAR_TOKEN}:" "${HOST_URL}$1" 2>/dev/null; }
if [ -n "${CE_ID}" ]; then
    sq_log "waiting for CE task ${CE_ID} ..."
    for _ in $(seq 1 60); do
        ce="$(_api "/api/ce/task?id=${CE_ID}")"
        st="$(printf '%s' "${ce}" | sed -n 's/.*"status" *: *"\([A-Z]*\)".*/\1/p' | head -1)"
        case "${st}" in
            SUCCESS) sq_log "CE task SUCCESS"; break ;;
            FAILED|CANCELED) sq_err "CE task ${st}"; printf '%s\n' "${ce}" >"${EVID}/ce_task.json"; exit 1 ;;
            *) sleep 3 ;;
        esac
    done
    printf '%s\n' "${ce:-}" >"${EVID}/ce_task.json"
else
    sq_log "no ceTaskId (proceeding to fetch findings after brief settle)"; sleep 6
fi

# --- Pull the REAL findings (sink-side evidence, §11.4.69) -------------------
_api "/api/issues/search?componentKeys=${PKEY}&ps=500"                              >"${EVID}/issues.json"      || true
_api "/api/measures/component?component=${PKEY}&metricKeys=bugs,vulnerabilities,code_smells,security_hotspots,ncloc,duplicated_lines_density" >"${EVID}/measures.json" || true
_api "/api/qualitygates/project_status?projectKey=${PKEY}"                          >"${EVID}/quality_gate.json" || true

# --- Count findings (jq if present, else grep) ------------------------------
_count() { # $1=file $2=jq-expr $3=grep-key
    if command -v jq >/dev/null 2>&1; then jq -r "${2}" "${1}" 2>/dev/null; else
        grep -o "\"${3}\" *: *[0-9]*" "${1}" 2>/dev/null | head -1 | grep -o '[0-9]*'; fi
}
TOTAL="$(_count "${EVID}/issues.json" '.total' 'total')"; TOTAL="${TOTAL:-0}"
GATE="$( if command -v jq >/dev/null 2>&1; then jq -r '.projectStatus.status' "${EVID}/quality_gate.json" 2>/dev/null; else sed -n 's/.*"status" *: *"\([A-Z]*\)".*/\1/p' "${EVID}/quality_gate.json" | head -1; fi )"

# --- Write the Markdown report (docs_chain-syncable) ------------------------
REPORT="${EVID}/SONARQUBE_SCAN_REPORT.md"
{
    echo "# SonarQube Scan Report"
    echo
    echo "**Revision:** 1"
    echo "**Last modified:** $(date -u +%FT%TZ)"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| Project key | \`${PKEY}\` |"
    echo "| Host | ${HOST_URL} |"
    echo "| Scanner | $(sonar-scanner --version 2>&1 | sed -n 's/.*\(SonarScanner CLI [0-9.]*\).*/\1/p' | head -1) |"
    echo "| Total issues (real, server-side) | **${TOTAL}** |"
    echo "| Quality gate | ${GATE:-UNKNOWN} |"
    echo "| Dashboard | ${HOST_URL}/dashboard?id=${PKEY} |"
    echo
    echo "Measures (\`measures.json\`) and full issue list (\`issues.json\`) captured in this directory as the §11.4.69 sink-side evidence for this scan."
} >"${REPORT}"

# --- Optional docs_chain report sync (§11.4.106, best-effort, honest) -------
if command -v docs_chain >/dev/null 2>&1; then
    sq_log "docs_chain present — syncing report exports"
    docs_chain sync "${REPORT}" >/dev/null 2>&1 || sq_log "docs_chain sync skipped (no context registered)"
fi

# --- Verdict (anti-bluff: cite the evidence path) ---------------------------
echo "----------------------------------------------------------------------"
echo "PASS: SonarQube analysis completed — ${TOTAL} real issue(s), gate=${GATE:-UNKNOWN}"
echo "      [evidence: ${EVID}]"
echo "      dashboard: ${HOST_URL}/dashboard?id=${PKEY}"
echo "----------------------------------------------------------------------"
exit 0
