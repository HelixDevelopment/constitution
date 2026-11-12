#!/usr/bin/env bash
# registry_login.sh - Helix Universal SonarQube - non-interactive container-registry
#                     authentication for scans that pull images (Docker OR Podman).
#
# Purpose      : Log in to a private container registry BEFORE any pull a Sonar scan
#                makes, without a human, without a secret in argv/stdout/stderr/logs.
#                Project-agnostic (§11.4.28/§11.4.177): every value is consumer DATA.
# Usage        : registry_login.sh <mode> [options]
#                  login    log in (creds from env or --env-file); --auth-file-only
#                           writes a DOCKER_AUTH_CONFIG-style auth file instead
#                  discover report which auth files / credential helpers exist
#                           (presence only; cannot invent credentials)
#                  verify   pull a probe image to prove stored auth works
#                  logout   log out of the registry
#                  auth-file-path  print the private auth-file path this tool uses
#                Options: --env-file F  --engine podman|docker  --registry HOST
#                         --probe-image IMG  --auth-file-only
# Inputs (env) : DOCKER_REGISTRY, DOCKER_USERNAME, DOCKER_PASSWORD | DOCKER_TOKEN,
#                DOCKER_AUTH_CONFIG (any non-empty value, like --auth-file-only: build+write
#                the auths JSON from username/password, base64(user:pass), to a 0600
#                file instead of calling the engine; never echoed),
#                SONAR_REGISTRY_ENV_FILE (default
#                ${XDG_CONFIG_HOME:-$HOME/.config}/helix/sonar_registry.env, mode
#                0600/0400 REQUIRED), SONAR_REGISTRY_ENGINE (podman|docker; default
#                auto: podman first per §11.4.161, docker fallback),
#                SONAR_REGISTRY_PROBE_IMAGE, REGISTRY_AUTH_FILE (honoured by engines).
# Outputs      : Status lines on stderr. NEVER a secret. auth-file-path prints a path.
# Exit codes   : 0 ok - 1 failed (engine rejected) - 2 BLIND/config error (bad args,
#                no engine, env file unreadable or group/world accessible) - 3 SKIP
#                (credentials_absent / probe_image_absent / registry_absent; names
#                variables only, never fakes success).
# Side-effects : May write ${XDG_RUNTIME_DIR:-/tmp-private}/helix/sonar_registry_auth.json
#                (0600) in --auth-file-only mode; engine login/logout/pull.
# Dependencies : bash, stat, grep, sed, mktemp, base64 (auth-config only), podman|docker.
# Security     : set +x enforced; password only via --password-stdin; env file sourced
#                in a subshell and refused unless mode has no group/other bits; engine
#                output passes through a literal-substring masker; credential helpers
#                are reported, never parsed.
# Cross-ref    : §11.4.10 · §11.4.18 · §11.4.28 · §11.4.161 · §11.4.177 · §11.4.201 ·
#                §11.4.224 · §11.4.273 · §11.4.184
set +x
set -u

RL_EXIT_OK=0; RL_EXIT_FAIL=1; RL_EXIT_BLIND=2; RL_EXIT_SKIP=3

rl_log() { printf '[registry-login] %s\n' "$*" >&2; }
rl_err() { printf '[registry-login][ERROR] %s\n' "$*" >&2; }

rl_default_env_file() { printf '%s' "${SONAR_REGISTRY_ENV_FILE:-${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/helix/sonar_registry.env}"; }

rl_auth_file_path() {
    local base="${XDG_RUNTIME_DIR:-}"
    [ -n "${base}" ] || base="${HOME:-/nonexistent}/.cache"
    printf '%s/helix/sonar_registry_auth.json' "${base}"
}

# Engine: explicit override, else podman first (§11.4.161 rootless), docker fallback.
rl_engine() {
    case "${SONAR_REGISTRY_ENGINE:-${RL_ENGINE_ARG:-}}" in
        podman|docker) command -v "${SONAR_REGISTRY_ENGINE:-${RL_ENGINE_ARG}}" 2>/dev/null; return ;;
        "") : ;;
        *) return 1 ;;
    esac
    command -v podman 2>/dev/null || command -v docker 2>/dev/null
}

# Mode check: no group/other permission bits at all (fail closed).
rl_env_file_ok() {
    local f="$1" m
    [ -f "${f}" ] && [ ! -L "${f}" ] || { rl_err "env file missing or a symlink: ${f}"; return 1; }
    m="$(stat -c %a "${f}" 2>/dev/null)" || { rl_err "cannot stat env file"; return 1; }
    case "${m}" in
        [0-7]00|[0-7]0) : ;;
        *) rl_err "env file ${f} has mode ${m}; require 0600 or 0400 (no group/other access). Refusing."; return 1 ;;
    esac
    [ -O "${f}" ] || { rl_err "env file ${f} is not owned by the current user"; return 1; }
}

# Mask every literal occurrence of the given secrets in stdin. Args = secrets.
rl_mask() {
    local line s
    while IFS= read -r line || [ -n "${line}" ]; do
        for s in "$@"; do
            [ -n "${s}" ] && line="${line//"${s}"/***}"
        done
        printf '%s\n' "${line}"
    done
}

# Resolve creds in the CURRENT (sub)shell; sets RL_REG RL_USER RL_PASS.
rl_resolve() {
    RL_REG="${RL_REG_ARG:-${DOCKER_REGISTRY:-}}"
    RL_USER="${DOCKER_USERNAME:-}"
    RL_PASS="${DOCKER_PASSWORD:-${DOCKER_TOKEN:-}}"
}

rl_load_env_file() { # sources in the calling subshell; caller guarantees subshell
    local f="$1"
    rl_env_file_ok "${f}" || return 2
    set +x; set -a
    # shellcheck disable=SC1090
    . "${f}" >/dev/null 2>&1 || { set +a; rl_err "env file failed to source"; return 2; }
    set +a
}

rl_mode_login() {
    local ef="${RL_ENV_FILE_ARG:-}" rc
    if [ -z "${ef}" ] && [ -f "$(rl_default_env_file)" ]; then ef="$(rl_default_env_file)"; fi
    (
        set +x
        if [ -n "${ef}" ]; then rl_load_env_file "${ef}" || exit "$?"; fi
        rl_resolve
        if [ -z "${RL_REG}" ] || [ -z "${RL_USER}" ] || [ -z "${RL_PASS}" ]; then
            rl_log "SKIP credentials_absent: need DOCKER_REGISTRY, DOCKER_USERNAME and DOCKER_PASSWORD (or DOCKER_TOKEN) (env or ${ef:-$(rl_default_env_file)}); no login attempted"
            exit "${RL_EXIT_SKIP}"
        fi
        if [ "${RL_AUTH_ONLY:-}" = 1 ] || [ -n "${DOCKER_AUTH_CONFIG:-}" ]; then
            command -v base64 >/dev/null 2>&1 || { rl_err "base64 not available"; exit "${RL_EXIT_BLIND}"; }
            af="$(rl_auth_file_path)"
            ( umask 077; mkdir -p "$(dirname "${af}")" && chmod 700 "$(dirname "${af}")" ) 2>/dev/null \
                || { rl_err "cannot create private auth dir"; exit "${RL_EXIT_BLIND}"; }
            ( umask 077; printf '{"auths":{"%s":{"auth":"%s"}}}' "${RL_REG}" \
                "$(printf '%s:%s' "${RL_USER}" "${RL_PASS}" | base64 -w0)" >"${af}" ) \
                || { rl_err "cannot write auth file"; exit "${RL_EXIT_BLIND}"; }
            chmod 600 "${af}"
            rl_log "auth file written (0600): ${af} - export REGISTRY_AUTH_FILE to use it"
            exit "${RL_EXIT_OK}"
        fi
        eng="$(rl_engine)" || { rl_err "no container engine (podman/docker) on PATH or invalid SONAR_REGISTRY_ENGINE"; exit "${RL_EXIT_BLIND}"; }
        out="$(printf '%s' "${RL_PASS}" | "${eng}" login --username "${RL_USER}" --password-stdin "${RL_REG}" 2>&1)"
        erc=$?
        printf '%s\n' "${out}" | rl_mask "${RL_PASS}" "${RL_USER}:${RL_PASS}" >&2
        if [ "${erc}" -ne 0 ]; then rl_err "$(basename "${eng}") login to ${RL_REG} failed (exit ${erc})"; exit "${RL_EXIT_FAIL}"; fi
        rl_log "login to ${RL_REG} OK via $(basename "${eng}") (password via stdin)"
        exit "${RL_EXIT_OK}"
    )
    rc=$?; return "${rc}"
}

rl_mode_discover() {
    local reg="${RL_REG_ARG:-${DOCKER_REGISTRY:-}}" found=0 f
    local cands=()
    [ -n "${REGISTRY_AUTH_FILE:-}" ] && cands+=("${REGISTRY_AUTH_FILE}")
    [ -n "${XDG_RUNTIME_DIR:-}" ] && cands+=("${XDG_RUNTIME_DIR}/containers/auth.json")
    cands+=("${HOME:-/nonexistent}/.config/containers/auth.json" "${HOME:-/nonexistent}/.docker/config.json")
    for f in "${cands[@]}"; do
        [ -f "${f}" ] || continue
        found=1
        printf 'auth-file present: %s\n' "${f}"
        if grep -q -E '"(credsStore|credHelpers)"' "${f}" 2>/dev/null; then
            printf '  credential-helper configured (credentials not stored in this file; the engine invokes the helper)\n'
        fi
        if [ -n "${reg}" ]; then
            if grep -qF "\"${reg}\"" "${f}" 2>/dev/null; then printf '  entry for %s: present\n' "${reg}"; else printf '  entry for %s: absent\n' "${reg}"; fi
        fi
    done
    if [ "${found}" -eq 0 ]; then rl_log "SKIP credentials_absent: no existing auth file (REGISTRY_AUTH_FILE, XDG_RUNTIME_DIR/containers/auth.json, ~/.config/containers/auth.json, ~/.docker/config.json)"; return "${RL_EXIT_SKIP}"; fi
    return "${RL_EXIT_OK}"
}

rl_mode_verify() {
    local img="${RL_PROBE_ARG:-${SONAR_REGISTRY_PROBE_IMAGE:-}}" eng out erc
    if [ -z "${img}" ]; then rl_log "SKIP probe_image_absent: pass --probe-image or set SONAR_REGISTRY_PROBE_IMAGE (a private image to pull); nothing verified"; return "${RL_EXIT_SKIP}"; fi
    eng="$(rl_engine)" || { rl_err "no container engine on PATH"; return "${RL_EXIT_BLIND}"; }
    out="$("${eng}" pull "${img}" 2>&1)"; erc=$?
    printf '%s\n' "${out}" | rl_mask "${DOCKER_PASSWORD:-}" "${DOCKER_TOKEN:-}" | tail -5 >&2
    if [ "${erc}" -ne 0 ]; then rl_err "pull of probe image failed (exit ${erc}); auth NOT verified"; return "${RL_EXIT_FAIL}"; fi
    rl_log "verify OK: pulled ${img} via $(basename "${eng}")"
    return "${RL_EXIT_OK}"
}

rl_mode_logout() {
    local ef="${RL_ENV_FILE_ARG:-}" rc
    if [ -z "${ef}" ] && [ -f "$(rl_default_env_file)" ]; then ef="$(rl_default_env_file)"; fi
    (
        set +x
        if [ -n "${ef}" ]; then rl_load_env_file "${ef}" || exit "$?"; fi
        rl_resolve
        if [ -z "${RL_REG}" ]; then rl_log "SKIP registry_absent: set DOCKER_REGISTRY or --registry; nothing to log out of"; exit "${RL_EXIT_SKIP}"; fi
        eng="$(rl_engine)" || { rl_err "no container engine on PATH"; exit "${RL_EXIT_BLIND}"; }
        "${eng}" logout "${RL_REG}" >/dev/null 2>&1 || { rl_err "logout from ${RL_REG} failed"; exit "${RL_EXIT_FAIL}"; }
        rl_log "logged out of ${RL_REG}"
        exit "${RL_EXIT_OK}"
    )
    rc=$?; return "${rc}"
}

rl_main() {
    local mode="${1:-}"; [ "$#" -gt 0 ] && shift
    RL_ENV_FILE_ARG=""; RL_ENGINE_ARG=""; RL_REG_ARG=""; RL_PROBE_ARG=""; RL_AUTH_ONLY=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --env-file) RL_ENV_FILE_ARG="${2:-}"; shift 2 || true ;;
            --engine) RL_ENGINE_ARG="${2:-}"; shift 2 || true ;;
            --registry) RL_REG_ARG="${2:-}"; shift 2 || true ;;
            --probe-image) RL_PROBE_ARG="${2:-}"; shift 2 || true ;;
            --auth-file-only) RL_AUTH_ONLY=1; shift ;;
            *) rl_err "unknown option: $1"; return "${RL_EXIT_BLIND}" ;;
        esac
    done
    case "${mode}" in
        login) rl_mode_login ;;
        discover) rl_mode_discover ;;
        verify) rl_mode_verify ;;
        logout) rl_mode_logout ;;
        auth-file-path) rl_auth_file_path; echo ;;
        *) rl_err "usage: registry_login.sh login|discover|verify|logout|auth-file-path [options]"; return "${RL_EXIT_BLIND}" ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then rl_main "$@"; exit $?; fi
