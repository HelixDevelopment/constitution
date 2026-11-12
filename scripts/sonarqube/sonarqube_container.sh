#!/usr/bin/env bash
# sonarqube_container.sh — Helix Universal SonarQube — rootless container control.
#
# Purpose      : Bring the singleton SonarQube Community Build + PostgreSQL stack
#                up / down / status via ROOTLESS podman-compose (§11.4.161) on the
#                declarative compose in ./compose. ONE server per host; every
#                project/track shares it (analysis is separated by projectKey), so
#                there is no §11.4.178 name collision. Does NOT hand-roll ad-hoc
#                `podman run` — the compose file is the orchestration surface,
#                consistent with the Containers submodule podman runtime (§11.4.76).
# Usage        : bash sonarqube_container.sh <up|down|status|wait|logs|restart>
#                  up      preflight (§11.4.133) + compose up -d + wait UP
#                  down    compose down (containers only; named volumes preserved)
#                  status  podman ps + /api/system/status (sink-side, §11.4.69)
#                  wait    block until /api/system/status == UP (default 180s)
#                  logs    tail SonarQube container logs
#                  restart down + up
# Inputs (env) : SONAR_HOST_PORT (default 9000) · SONAR_DB_USER · SONAR_DB_PASSWORD
#                DOCKER_* / SONAR_REGISTRY_ENV_FILE: optional registry login before the
#                compose pull in `up` (see registry_login.sh)
#                SONAR_WAIT_TIMEOUT (default 180, for up/wait)
# Outputs      : Status lines on stdout/stderr; exit 0 on success.
# Exit codes   : 0 ok · 1 operation failed · 2 environment/tool problem
# Side-effects : Creates/removes rootless podman containers + named volumes.
# Dependencies : bash, podman, podman-compose, curl
# Cross-ref    : §11.4.69 · §11.4.76 · §11.4.108 · §11.4.133 · §11.4.161 · §12.6
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./sonarqube_lib.sh
. "${SCRIPT_DIR}/sonarqube_lib.sh"

_compose() {
    local cc; cc="$(sq_compose_cmd)" || { sq_err "no podman-compose available (§11.4.161)"; exit 2; }
    # shellcheck disable=SC2086
    ${cc} -p "${SQ_COMPOSE_PROJECT}" -f "${SQ_COMPOSE_FILE}" "$@"
}

cmd_up() {
    sq_have_podman || { sq_err "podman not found (rootless required, §11.4.161)"; exit 2; }
    sq_check_max_map_count || exit 1        # §11.4.133 host-safety preflight
    # Registry auth BEFORE the compose pull (SKIPs honestly when nothing is configured).
    sq_registry_login_auto || { sq_err "registry authentication failed or refused (see above)"; exit 2; }
    sq_log "compose up -d (project ${SQ_COMPOSE_PROJECT})"
    _compose up -d || { sq_err "compose up failed"; exit 1; }
    podman ps --format '{{.Names}} {{.Status}} {{.Ports}}' | grep -i sonar || true
    sq_wait_up "${SONAR_WAIT_TIMEOUT:-180}"
}

cmd_down()   { sq_log "compose down"; _compose down; }
cmd_restart(){ cmd_down; cmd_up; }
cmd_wait()   { sq_wait_up "${SONAR_WAIT_TIMEOUT:-180}"; }
cmd_logs()   { podman logs --tail "${1:-80}" helix_sonarqube 2>&1 || _compose logs --tail "${1:-80}" sonarqube; }

cmd_status() {
    echo "=== podman ps ==="
    podman ps --format '{{.Names}} {{.Status}} {{.Ports}}' | grep -i sonar || echo "(no sonar containers running)"
    echo "=== /api/system/status ($(sq_host_url)) ==="
    sq_status_json || echo "(server unreachable)"
    echo
}

main() {
    case "${1:-status}" in
        up) cmd_up ;;
        down) cmd_down ;;
        restart) cmd_restart ;;
        status) cmd_status ;;
        wait) cmd_wait ;;
        logs) shift || true; cmd_logs "${1:-80}" ;;
        *) sq_err "unknown command '${1:-}'"; grep -E '^#   (up|down|status|wait|logs|restart)' "$0" >&2 || true; exit 2 ;;
    esac
}
main "$@"
