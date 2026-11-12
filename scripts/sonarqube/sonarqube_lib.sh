#!/usr/bin/env bash
# sonarqube_lib.sh — Helix Universal SonarQube integration — shared library.
#
# Purpose      : Project-AGNOSTIC (§11.4.28) helpers shared by every SonarQube
#                script in this directory. Sourced, never executed directly.
#                Operates on the INVOCATION directory (§11.4.177) — never a
#                hardcoded project path — so any project that inherits the
#                constitution submodule gets it working on its own tree.
# Usage        : source "<constitution>/scripts/sonarqube/sonarqube_lib.sh"
# Inputs (env) : SONAR_HOST_URL   (default http://localhost:9000)
#                SONAR_HOST_PORT  (default 9000)
#                SONAR_TOKEN      (analysis + API token; from project .env,
#                                  §11.4.10 — NEVER echoed by these scripts)
#                SONAR_DB_USER / SONAR_DB_PASSWORD (compose DB creds)
# Outputs      : Shell functions in the sq_* namespace.
# Side-effects : None on source (pure function definitions + a few readonly vars).
# Dependencies : bash, curl, podman, podman-compose (rootless §11.4.161).
# Cross-ref    : §11.4.69 (sink-side evidence) · §11.4.108 (four-layer verify) ·
#                §11.4.133 (host safety preflight) · §11.4.161 (rootless) ·
#                §11.4.177 (operate on invocation dir) · §12.6 (mem cap).
#
# No `set -e` here (library) — callers own their own error policy.

# --- Resolve our own location + the constitution root -----------------------
SQ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ_CONST_ROOT="$(cd "${SQ_LIB_DIR}/../.." && pwd)"
SQ_COMPOSE_FILE="${SQ_LIB_DIR}/compose/docker-compose.sonarqube.yml"
SQ_COMPOSE_PROJECT="helix_sonarqube"
SQ_MIN_MAX_MAP_COUNT=262144

# --- Config resolvers (all env-overridable, safe defaults) ------------------
sq_host_port() { printf '%s' "${SONAR_HOST_PORT:-9000}"; }
sq_host_url()  { printf '%s' "${SONAR_HOST_URL:-http://localhost:$(sq_host_port)}"; }

# §11.4.177: resolve the project root from the invocation context, never hardcoded.
sq_project_root() {
    if [ -n "${1:-}" ]; then ( cd "$1" 2>/dev/null && pwd ) && return 0; fi
    printf '%s' "${PWD}"
}

# --- Logging (stderr; never prints SONAR_TOKEN) -----------------------------
sq_log() { printf '[sonarqube] %s\n' "$*" >&2; }
sq_err() { printf '[sonarqube][ERROR] %s\n' "$*" >&2; }

# --- Host readiness preflight (§11.4.133) -----------------------------------
# Elasticsearch (embedded in SonarQube) refuses to start below 262144. Rootless
# containers share the host sysctl and cannot raise it without privilege, so we
# ASSERT it as a host precondition rather than trying to write it (§11.4.161 —
# no escalation, §11.4.6 — prove the value, never assume).
sq_check_max_map_count() {
    local v
    v="$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)"
    if [ "${v:-0}" -ge "${SQ_MIN_MAX_MAP_COUNT}" ] 2>/dev/null; then
        sq_log "host vm.max_map_count=${v} (>= ${SQ_MIN_MAX_MAP_COUNT}) OK"
        return 0
    fi
    sq_err "host vm.max_map_count=${v} < ${SQ_MIN_MAX_MAP_COUNT}. SonarQube ES will not start."
    sq_err "Remediation (needs privilege, one-time): sudo sysctl -w vm.max_map_count=262144"
    return 1
}

# --- Tooling presence -------------------------------------------------------
sq_have_scanner() { command -v sonar-scanner >/dev/null 2>&1; }
sq_have_podman()  { command -v podman >/dev/null 2>&1; }
sq_compose_cmd() {
    # Prefer `podman-compose`; fall back to `podman compose` (both rootless).
    if command -v podman-compose >/dev/null 2>&1; then printf 'podman-compose'; return 0; fi
    if podman compose version >/dev/null 2>&1; then printf 'podman compose'; return 0; fi
    return 1
}

# --- Server status (sink-side probe, §11.4.69) ------------------------------
# Echoes the raw /api/system/status JSON; caller inspects "status" field.
sq_status_json() { curl -fsS --max-time 8 "$(sq_host_url)/api/system/status" 2>/dev/null; }
sq_is_up() { sq_status_json | grep -q '"status" *: *"UP"'; }

# Block until UP or timeout (seconds). Returns 0 UP / 1 timeout.
sq_wait_up() {
    local timeout="${1:-180}" waited=0 st
    while [ "${waited}" -lt "${timeout}" ]; do
        st="$(sq_status_json | sed -n 's/.*"status" *: *"\([A-Z]*\)".*/\1/p')"
        case "${st}" in
            UP) sq_log "server UP after ${waited}s"; return 0 ;;
            STARTING|DB_MIGRATION_NEEDED|DB_MIGRATION_RUNNING|"") : ;;
            *) sq_log "server status=${st} (${waited}s)" ;;
        esac
        sleep 5; waited=$((waited + 5))
    done
    sq_err "server not UP within ${timeout}s (last status='${st:-unreachable}')"
    return 1
}

# --- Evidence directory (§11.4.69 / §11.4.128 layout) -----------------------
# <project-root>/qa-results/sonarqube/<UTC-timestamp>/
sq_evidence_dir() {
    local root ts
    root="$(sq_project_root "${1:-}")"
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    printf '%s/qa-results/sonarqube/%s' "${root}" "${ts}"
}

# --- Registry authentication before image pulls (§11.4.184(J)) ---------------
# The only image pull in this directory is `compose up` in sonarqube_container.sh
# (host sonar-scanner pulls nothing), so that is where this is called. Consumer
# DATA only: env DOCKER_* or the env file (SONAR_REGISTRY_ENV_FILE, default
# ${XDG_CONFIG_HOME:-~/.config}/helix/sonar_registry.env, no group/other bits).
# Nothing configured: logged SKIP, return 0. Config error / failed login: non-zero
# (caller fails closed). SONAR_REGISTRY_LOGIN=off disables. Never prints a secret.
sq_registry_login_auto() {
    # Secrets are never expanded under xtrace: tracing is switched off for the body
    # and restored; the body also tests set-ness with ${!v+x}, not the value.
    local _xt=0 _rc
    case $- in *x*) _xt=1; set +x ;; esac
    _sq_registry_login_auto_body; _rc=$?
    [ "${_xt}" = 1 ] && set -x
    return "${_rc}"
}
_sq_registry_login_auto_body() {
    local rl rc ef v
    [ "${SONAR_REGISTRY_LOGIN:-auto}" = "off" ] && { sq_log "registry auth: disabled (SONAR_REGISTRY_LOGIN=off)"; return 0; }
    rl="${SQ_LIB_DIR}/registry_login.sh"
    [ -f "${rl}" ] || { sq_err "registry_login.sh missing next to the library"; return 2; }
    # DOCKER_* set by a sourced (non-exporting) .env must reach the child process.
    for v in DOCKER_REGISTRY DOCKER_USERNAME DOCKER_PASSWORD DOCKER_TOKEN DOCKER_AUTH_CONFIG; do
        [ -n "${!v+x}" ] && export "${v?}"
    done
    ef="${SONAR_REGISTRY_ENV_FILE:-${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/helix/sonar_registry.env}"
    if [ -z "${DOCKER_USERNAME+x}" ] && [ -z "${DOCKER_AUTH_CONFIG+x}" ] && [ ! -e "${ef}" ] && [ -z "${SONAR_REGISTRY_ENV_FILE:-}" ]; then
        sq_log "registry auth: SKIP credentials_absent (set DOCKER_* or ${ef}); continuing without registry login"
        return 0
    fi
    bash "${rl}" login; rc=$?
    case "${rc}" in
        0)  return 0 ;;
        3)  sq_log "registry auth: SKIP (see reason above); continuing"; return 0 ;;
        *)  return "${rc}" ;;
    esac
}
