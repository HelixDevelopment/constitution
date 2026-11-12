#!/usr/bin/env bash
# registry_login.sh - Helix Universal SonarQube - non-interactive container-registry
#                     authentication for scans that pull images (Docker OR Podman).
#
# Purpose      : Log in to a private container registry BEFORE any pull a Sonar scan
#                makes, without a human, without a secret in argv/stdout/stderr/logs.
#                Project-agnostic (§11.4.28/§11.4.177): every value is consumer DATA.
# Usage        : registry_login.sh <mode> [options]
#                  login    log in (creds from env, DOCKER_AUTH_CONFIG auths JSON or
#                           --env-file); --auth-file-only writes a podman-format auth
#                           file (REGISTRY_AUTH_FILE) instead of calling the engine
#                  discover report which auth files / credential helpers exist
#                           (presence only; cannot invent credentials)
#                  verify   pull a probe image to prove stored auth works
#                  logout   log out of the registry
#                  auth-file-path  print the private auth-file path this tool uses
#                Options: --env-file F  --engine podman|docker  --registry HOST
#                         --probe-image IMG  --auth-file-only
# Inputs (env) : DOCKER_REGISTRY, DOCKER_USERNAME, DOCKER_PASSWORD | DOCKER_TOKEN,
#                DOCKER_AUTH_CONFIG (the usual {"auths":{host:{"auth":base64(user:pass)}}}
#                JSON; used when no username/password is given: each entry is decoded
#                in-process and logged in through the engine with --password-stdin),
#                SONAR_REGISTRY_ENV_FILE (default
#                ${XDG_CONFIG_HOME:-$HOME/.config}/helix/sonar_registry.env, no
#                group/other permission bits REQUIRED; if set explicitly and missing
#                the result is exit 2, not SKIP), SONAR_REGISTRY_ENGINE (podman|docker; --engine wins;
#                default auto: podman first per §11.4.161, docker fallback),
#                SONAR_REGISTRY_PROBE_IMAGE, REGISTRY_AUTH_FILE (honoured by podman only).
# Outputs      : Status lines on stderr. NEVER a secret. auth-file-path prints a path.
# Exit codes   : 0 ok - 1 failed (engine rejected) - 2 BLIND/config error (bad args,
#                no engine, env file unreadable or group/world accessible) - 3 SKIP
#                (credentials_absent / probe_image_absent / registry_absent; names
#                variables only, never fakes success).
# Side-effects : --auth-file-only writes ${XDG_RUNTIME_DIR:-$HOME/.cache}/helix_sonar_registry/auth.json
#                (0600, private 0700 directory); engine login/logout/pull.
# Dependencies : bash, stat, grep, sed, tr, tail, base64, podman|docker.
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

rl_default_env_file() { printf '%s' "${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/helix/sonar_registry.env"; }

rl_auth_dir() {
    local base="${XDG_RUNTIME_DIR:-}"
    [ -n "${base}" ] || base="${HOME:-/nonexistent}/.cache"
    printf '%s/helix_sonar_registry' "${base}"
}
rl_auth_file_path() { printf '%s/auth.json' "$(rl_auth_dir)"; }

# Engine: --engine wins over SONAR_REGISTRY_ENGINE; unset = podman first (§11.4.161),
# docker fallback. An explicit but invalid/missing engine is a failure (no fallback).
rl_engine() {
    local want="${RL_ENGINE_ARG:-${SONAR_REGISTRY_ENGINE:-}}"
    case "${want}" in
        podman|docker) command -v "${want}" 2>/dev/null; return ;;
        "") : ;;
        *) return 1 ;;
    esac
    command -v podman 2>/dev/null || command -v docker 2>/dev/null
}

# Require exactly no group/other bits (mode & 077 == 0), regular file, not a symlink, ours.
rl_env_file_ok() {
    local f="$1" m
    if [ -L "${f}" ] || [ ! -f "${f}" ]; then rl_err "env file missing or a symlink: ${f}"; return 1; fi
    [ -O "${f}" ] || { rl_err "env file ${f} is not owned by the current user"; return 1; }
    m="$(stat -c %a "${f}" 2>/dev/null)" || { rl_err "cannot stat env file"; return 1; }
    case "${m}" in *[!0-7]*|"") rl_err "unreadable mode of env file"; return 1 ;; esac
    if [ $(( 8#${m} & 8#077 )) -ne 0 ]; then
        rl_err "env file ${f} has mode ${m}; require no group/other access (0600 or 0400). Refusing."; return 1
    fi
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

# Choose the env file into RL_EF. 0 ok (RL_EF may be empty), 2 explicit-but-missing.
rl_pick_env_file() {
    RL_EF="${RL_ENV_FILE_ARG:-}"
    if [ -n "${RL_EF}" ]; then return 0; fi
    if [ -n "${SONAR_REGISTRY_ENV_FILE:-}" ]; then
        if [ ! -e "${SONAR_REGISTRY_ENV_FILE}" ]; then rl_err "SONAR_REGISTRY_ENV_FILE is set but ${SONAR_REGISTRY_ENV_FILE} does not exist"; return 2; fi
        RL_EF="${SONAR_REGISTRY_ENV_FILE}"; return 0
    fi
    [ -f "$(rl_default_env_file)" ] && RL_EF="$(rl_default_env_file)"
    return 0
}
# --env-file given explicitly must exist too (rl_env_file_ok reports it).

# Source the env file in the CALLING subshell with tracing impossible to re-enable.
rl_load_env_file() {
    local f="$1"
    rl_env_file_ok "${f}" || return 2
    set +x
    set -a
    # shellcheck disable=SC1090
    . "${f}" >/dev/null 2>&1 || { set +a; set +x; rl_err "env file failed to source"; return 2; }
    set +a
    set +x
    BASH_XTRACEFD=9
}

rl_quiet_trace() { set +x; exec 9>/dev/null; BASH_XTRACEFD=9; }

# Classify a DOCKER_AUTH_CONFIG JSON on stdin. Prints "host<TAB>base64" lines for
# decodable entries. Exit 0 = at least one entry; 3 = valid config that holds only
# credential-helper / identity-token material (honest SKIP); 2 = anything else
# (non-JSON, no auths, wrong types, typo'd keys, empty): a config error, never a SKIP.
# Values are never printed on error paths. Needs python3 (absent -> exit 2).
rl_auths_pairs() {
    command -v python3 >/dev/null 2>&1 || return 2
    python3 -I -c '
import sys, json
try:
    o = json.loads(sys.stdin.read())
except Exception:
    sys.exit(2)
if not isinstance(o, dict):
    sys.exit(2)
helper = isinstance(o.get("credsStore"), str) and o["credsStore"] != ""
ch = o.get("credHelpers")
if isinstance(ch, dict) and ch and all(isinstance(v, str) and v for v in ch.values()):
    helper = True
a = o.get("auths")
pairs = []
helper_only = False
if a is None:
    sys.exit(3 if helper else 2)
if not isinstance(a, dict):
    sys.exit(2)
for h, e in a.items():
    if not isinstance(e, dict):
        sys.exit(2)
    if "auth" in e:
        v = e["auth"]
        if not isinstance(v, str) or v == "" or "\t" in h or "\n" in h:
            sys.exit(2)
        pairs.append((h, v))
    elif isinstance(e.get("identitytoken"), str) and e["identitytoken"] != "":
        helper_only = True
    elif e == {} and helper:
        helper_only = True
    else:
        sys.exit(2)
if pairs:
    for h, v in pairs:
        sys.stdout.write(h + "\t" + v + "\n")
    sys.exit(0)
sys.exit(3 if (helper or helper_only) else 2)
'
}

# rl_engine_login ENGINE REG USER PASS  (password through printf builtin -> stdin)
rl_engine_login() {
    local eng="$1" reg="$2" user="$3" pass="$4" out erc
    out="$(printf '%s' "${pass}" | "${eng}" login --username "${user}" --password-stdin "${reg}" 2>&1)"
    erc=$?
    printf '%s\n' "${out}" | rl_mask "${pass}" "${user}:${pass}" >&2
    if [ "${erc}" -ne 0 ]; then rl_err "$(basename "${eng}") login to ${reg} failed (exit ${erc})"; return "${RL_EXIT_FAIL}"; fi
    rl_log "login to ${reg} OK via $(basename "${eng}") (password via stdin)"
    return 0
}

rl_mode_login() {
    local rc
    rl_pick_env_file || return $?
    (
        rl_quiet_trace
        if [ -n "${RL_EF}" ]; then rl_load_env_file "${RL_EF}" || exit "$?"; fi
        reg="${RL_REG_ARG:-${DOCKER_REGISTRY:-}}"; user="${DOCKER_USERNAME:-}"; pass="${DOCKER_PASSWORD:-${DOCKER_TOKEN:-}}"
        triples=()
        if [ -n "${user}" ] && [ -n "${pass}" ] && [ -n "${reg}" ]; then
            triples+=("${reg}"$'\t'"${user}"$'\t'"${pass}")
        elif [ -z "${user}${pass}" ] && [ -n "${DOCKER_AUTH_CONFIG:-}" ]; then
            pairs="$(printf '%s' "${DOCKER_AUTH_CONFIG}" | rl_auths_pairs)"; prc=$?
            case "${prc}" in
                0) : ;;
                3) rl_log "SKIP credentials_absent: DOCKER_AUTH_CONFIG holds only credential-helper / identity-token entries (not decoded here); no login attempted"
                   exit "${RL_EXIT_SKIP}" ;;
                *) rl_err "DOCKER_AUTH_CONFIG is not a usable auths JSON object (not JSON, no auths, wrong types, unknown keys or empty)"; exit "${RL_EXIT_BLIND}" ;;
            esac
            while IFS=$'\t' read -r h b; do
                d="$(printf '%s' "${b}" | base64 -d 2>/dev/null)"
                case "${d}" in *:*) triples+=("${h}"$'\t'"${d%%:*}"$'\t'"${d#*:}") ;; *) rl_err "undecodable auth entry for ${h}"; exit "${RL_EXIT_BLIND}" ;; esac
            done <<<"${pairs}"
        else
            rl_log "SKIP credentials_absent: need DOCKER_REGISTRY, DOCKER_USERNAME and DOCKER_PASSWORD (or DOCKER_TOKEN), or a DOCKER_AUTH_CONFIG auths JSON (env or ${RL_EF:-$(rl_default_env_file)}); no login attempted"
            exit "${RL_EXIT_SKIP}"
        fi
        if [ "${RL_AUTH_ONLY:-}" = 1 ]; then
            [ "${#triples[@]}" -eq 1 ] || { rl_err "--auth-file-only needs DOCKER_REGISTRY + username + password"; exit "${RL_EXIT_BLIND}"; }
            IFS=$'\t' read -r reg user pass <<<"${triples[0]}"
            case "${reg}" in *[!A-Za-z0-9._:/-]*|"") rl_err "registry contains characters not allowed in the auth JSON"; exit "${RL_EXIT_BLIND}" ;; esac
            case "$(basename "$(rl_engine 2>/dev/null)" 2>/dev/null)" in
                docker) rl_err "--auth-file-only writes the podman REGISTRY_AUTH_FILE format; docker ignores it. Use plain login."; exit "${RL_EXIT_BLIND}" ;;
            esac
            ad="$(rl_auth_dir)"; mkdir -p "$(dirname "${ad}")" 2>/dev/null
            [ -d "${ad}" ] || ( umask 077; mkdir -m 700 "${ad}" ) 2>/dev/null
            [ -d "${ad}" ] && [ ! -L "${ad}" ] && [ -O "${ad}" ] && [ "$(stat -c %a "${ad}" 2>/dev/null)" = 700 ] \
                || { rl_err "private auth dir ${ad} missing, a symlink, not ours or not mode 700"; exit "${RL_EXIT_BLIND}"; }
            af="$(rl_auth_file_path)"
            ( umask 077; printf '{"auths":{"%s":{"auth":"%s"}}}' "${reg}" \
                "$(printf '%s:%s' "${user}" "${pass}" | base64 | tr -d '\n')" >"${af}" ) \
                || { rl_err "cannot write auth file"; exit "${RL_EXIT_BLIND}"; }
            chmod 600 "${af}"
            rl_log "auth file written (0600): ${af}; NOT verified - export REGISTRY_AUTH_FILE (podman) and run verify"
            exit "${RL_EXIT_OK}"
        fi
        eng="$(rl_engine)" || { rl_err "no usable container engine (podman/docker) on PATH, or invalid/missing explicitly requested engine"; exit "${RL_EXIT_BLIND}"; }
        worst=0
        for t in "${triples[@]}"; do
            IFS=$'\t' read -r h u pw <<<"${t}"
            case "${h}" in -*|*[!A-Za-z0-9._:/-]*|"") rl_err "registry host '${h}' has characters not allowed (or starts with '-'); refusing"; exit "${RL_EXIT_BLIND}" ;; esac
            rl_engine_login "${eng}" "${h}" "${u}" "${pw}" || worst=$?
        done
        exit "${worst}"
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
    local rc
    rl_pick_env_file || return $?
    (
        rl_quiet_trace
        if [ -n "${RL_EF}" ]; then rl_load_env_file "${RL_EF}" || exit "$?"; fi
        img="${RL_PROBE_ARG:-${SONAR_REGISTRY_PROBE_IMAGE:-}}"
        if [ -z "${img}" ]; then rl_log "SKIP probe_image_absent: pass --probe-image or set SONAR_REGISTRY_PROBE_IMAGE (a private image to pull); nothing verified"; exit "${RL_EXIT_SKIP}"; fi
        eng="$(rl_engine)" || { rl_err "no usable container engine on PATH"; exit "${RL_EXIT_BLIND}"; }
        out="$("${eng}" pull "${img}" 2>&1)"; erc=$?
        printf '%s\n' "${out}" | rl_mask "${DOCKER_PASSWORD:-}" "${DOCKER_TOKEN:-}" | tail -5 >&2
        if [ "${erc}" -ne 0 ]; then rl_err "pull of probe image failed (exit ${erc}); auth NOT verified"; exit "${RL_EXIT_FAIL}"; fi
        rl_log "verify OK: pulled ${img} via $(basename "${eng}")"
        exit "${RL_EXIT_OK}"
    )
    rc=$?; return "${rc}"
}

rl_mode_logout() {
    local rc
    rl_pick_env_file || return $?
    (
        rl_quiet_trace
        if [ -n "${RL_EF}" ]; then rl_load_env_file "${RL_EF}" || exit "$?"; fi
        reg="${RL_REG_ARG:-${DOCKER_REGISTRY:-}}"
        if [ -z "${reg}" ]; then rl_log "SKIP registry_absent: set DOCKER_REGISTRY or --registry; nothing to log out of"; exit "${RL_EXIT_SKIP}"; fi
        eng="$(rl_engine)" || { rl_err "no usable container engine on PATH"; exit "${RL_EXIT_BLIND}"; }
        "${eng}" logout "${reg}" >/dev/null 2>&1 || { rl_err "logout from ${reg} failed"; exit "${RL_EXIT_FAIL}"; }
        rl_log "logged out of ${reg}"
        exit "${RL_EXIT_OK}"
    )
    rc=$?; return "${rc}"
}

rl_need_value() { # $1 option, $2 value
    if [ -z "${2:-}" ]; then rl_err "option $1 needs a value"; return 1; fi
}

rl_main() {
    local mode="${1:-}"; [ "$#" -gt 0 ] && shift
    RL_ENV_FILE_ARG=""; RL_ENGINE_ARG=""; RL_REG_ARG=""; RL_PROBE_ARG=""; RL_AUTH_ONLY=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --env-file)    rl_need_value "$1" "${2:-}" || return "${RL_EXIT_BLIND}"; RL_ENV_FILE_ARG="$2"; shift 2 ;;
            --engine)      rl_need_value "$1" "${2:-}" || return "${RL_EXIT_BLIND}"; RL_ENGINE_ARG="$2"; shift 2 ;;
            --registry)    rl_need_value "$1" "${2:-}" || return "${RL_EXIT_BLIND}"; RL_REG_ARG="$2"; shift 2 ;;
            --probe-image) rl_need_value "$1" "${2:-}" || return "${RL_EXIT_BLIND}"; RL_PROBE_ARG="$2"; shift 2 ;;
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
