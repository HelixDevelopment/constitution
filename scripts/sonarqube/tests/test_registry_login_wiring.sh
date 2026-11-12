#!/usr/bin/env bash
# test_registry_login_wiring.sh - UNIT-CLASS gate-logic test (§11.4.289(C)(2)): the registry
# login runs BEFORE the compose pull in `sonarqube_container.sh up` (the only image pull
# in scripts/sonarqube) and fails closed / SKIPs honestly. Fake podman; no network, no
# registry, no real credentials. Override REGISTRY_WIRING_SQ_DIR to test a mutated copy.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="${REGISTRY_WIRING_SQ_DIR:-${HERE}/..}"
W="$(mktemp -d "${TMPDIR:-/tmp}/rlwire.XXXXXX")" || exit 2
trap 'rm -rf "${W:?}"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$2' got '$3')"; fi; }
TOOLS="${W}/tools"; mkdir -p "${TOOLS}" "${W}/fake" "${W}/home/.config/helix"
for t in bash env stat grep sed mktemp cat rm date dirname basename mkdir chmod tr head id seq sleep curl cp base64 python3; do
    p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "${TOOLS}/$t"
done
cat >"${W}/fake/podman" <<'F'
#!/bin/bash
echo "podman $1" >>"${FAKE_LOG:?}"
if [ "$1" = login ]; then cat >/dev/null; exit "${FAKE_RC:-0}"; fi
exit 0
F
chmod +x "${W}/fake/podman"
EF="${W}/home/.config/helix/sonar_registry.env"
mkenv() { printf 'DOCKER_REGISTRY=r.t\nDOCKER_USERNAME=u\nDOCKER_PASSWORD=pw\n' >"${EF}"; chmod "$1" "${EF}"; }
up() { rm -f "${W}/log"; env -i PATH="${W}/fake:${TOOLS}" HOME="${W}/home" XDG_CONFIG_HOME="${W}/home/.config" \
    FAKE_LOG="${W}/log" SONAR_WAIT_TIMEOUT=0 SONAR_HOST_URL=http://127.0.0.1:1 ${ENVS:-} \
    bash "${SQ}/sonarqube_container.sh" up >"${W}/out" 2>"${W}/err"; echo $?; }
if [ "$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)" -lt 262144 ]; then
    echo "SKIP host vm.max_map_count too low for the real 'up' preflight (reason: topology_unsupported)"; exit 0; fi

ENVS=""; mkenv 600
up >/dev/null
grep -q 'podman login' "${W}/log" && ok "login happens in 'up'" || no "login happens in 'up'"
l="$(grep -n 'podman login' "${W}/log" | head -1 | cut -d: -f1)"; c="$(grep -n 'podman compose' "${W}/log" | head -1 | cut -d: -f1)"
if [ -n "$l" ] && [ -n "$c" ] && [ "$l" -lt "$c" ]; then ok "login precedes compose pull"; else no "login precedes compose pull (login=$l compose=$c)"; fi

mkenv 644; rc=$(up); chk "bad env perms -> up exits 2" 2 "$rc"
grep -q 'podman compose' "${W}/log" 2>/dev/null && no "no compose after refused login" || ok "no compose after refused login"
grep -q 'authentication failed' "${W}/err" && ok "fail-closed message" || no "fail-closed message"

mkenv 600; ENVS="FAKE_RC=1"; rc=$(up); chk "engine rejects login (rc 1) -> up exits 2 (not SKIP)" 2 "$rc"
grep -q 'podman compose' "${W}/log" 2>/dev/null && no "no compose after failed login" || ok "no compose after failed login"

ENVS="SONAR_REGISTRY_ENV_FILE=${W}/absent.env"; rc=$(up); chk "explicit missing env file -> exit 2" 2 "$rc"

rm -f "${EF}"; ENVS=""; rc=$(up)
grep -q 'SKIP credentials_absent' "${W}/err" && ok "no creds -> documented SKIP" || no "no creds -> documented SKIP"
grep -q 'podman compose' "${W}/log" && ok "compose proceeds after SKIP" || no "compose proceeds after SKIP"

mkenv 600; ENVS="SONAR_REGISTRY_LOGIN=off"; rc=$(up)
grep -q 'podman login' "${W}/log" && no "off switch honoured" || ok "off switch honoured"

# .env-style non-exported DOCKER_* reach the child (sourced, not exported)
rm -f "${W}/log"
env -i PATH="${W}/fake:${TOOLS}" HOME="${W}/home" XDG_CONFIG_HOME="${W}/none" FAKE_LOG="${W}/log" bash -c '
  . "$1/sonarqube_lib.sh"; DOCKER_REGISTRY=r.t; DOCKER_USERNAME=u; DOCKER_PASSWORD=pw; sq_registry_login_auto' _ "${SQ}" >/dev/null 2>&1
grep -q 'podman login' "${W}/log" 2>/dev/null && ok "non-exported DOCKER_* are exported to the login child" || no "non-exported DOCKER_* are exported to the login child"

# xtrace must never expose a secret on the library path (I-1): trace under bash -x,
# secrets as plain (non-exported) variables and as DOCKER_AUTH_CONFIG
LEAK='ZZSECRETZZ-lib/leak'
rm -f "${W}/log"
env -i PATH="${W}/fake:${TOOLS}" HOME="${W}/home" XDG_CONFIG_HOME="${W}/none" FAKE_LOG="${W}/log" bash -xc '
  . "$1/sonarqube_lib.sh"; set +x; DOCKER_REGISTRY=r.t; DOCKER_USERNAME=u; DOCKER_PASSWORD="$2"; DOCKER_TOKEN="$2"
  DOCKER_AUTH_CONFIG="{\"auths\":{\"h\":{\"auth\":\"$2\"}}}"; set -x; sq_registry_login_auto' _ "${SQ}" "${LEAK}" >"${W}/xout" 2>"${W}/xerr"
if grep -qF -- "${LEAK}" "${W}/xout" "${W}/xerr"; then no "xtrace leak: secret visible under bash -x"; else ok "xtrace leak: no secret under bash -x"; fi
grep -q 'podman login' "${W}/log" 2>/dev/null && ok "xtrace run really logged in (needle can see)" || no "xtrace run really logged in (needle can see)"
grep -qF -- 'sq_registry_login_auto' "${W}/xerr" && ok "xtrace needle: trace is active (function name visible)" || no "xtrace needle: trace is active"
# tracing is restored after the call
env -i PATH="${W}/fake:${TOOLS}" HOME="${W}/home" XDG_CONFIG_HOME="${W}/none" FAKE_LOG="${W}/log" bash -xc '
  . "$1/sonarqube_lib.sh"; sq_registry_login_auto; echo AFTERCALL' _ "${SQ}" 2>&1 >/dev/null | grep -q "echo AFTERCALL" && ok "xtrace restored after the call" || no "xtrace restored after the call"

# R7: library maps registry_login exit 3 (SKIP) to success: helper-only DOCKER_AUTH_CONFIG via real `up` proceeds
rm -f "${EF}"; ENVS="DOCKER_AUTH_CONFIG={\"credsStore\":\"desktop\"}"; rc=$(up)
grep -q 'SKIP credentials_absent' "${W}/err" && ok "helper-only config: SKIP logged through the library" || no "helper-only config: SKIP logged through the library"
grep -q 'podman login' "${W}/log" 2>/dev/null && no "helper-only config: no login attempted" || ok "helper-only config: no login attempted"
grep -q 'podman compose' "${W}/log" 2>/dev/null && ok "helper-only config: up proceeds (lib maps rc 3 to 0)" || no "helper-only config: up proceeds (lib maps rc 3 to 0)"
# malformed config must NOT proceed
ENVS='DOCKER_AUTH_CONFIG={"x":1}'; rc=$(up); chk "malformed config -> up exits 2" 2 "$rc"
grep -q 'podman compose' "${W}/log" 2>/dev/null && no "malformed config: no compose" || ok "malformed config: no compose"

# round 5: set-up-but-unusable credentials must stop `up` (never read as absent)
rm -f "${W}/ef"; ENVS="DOCKER_USERNAME=u"; rc=$(up); chk "user without password -> up exits 2" 2 "$rc"
grep -q 'podman compose' "${W}/log" 2>/dev/null && no "user only: no compose" || ok "user only: no compose"
printf 'DOCKER_REGISTRY=r.t\nDOCKER_USERNAME=u\nDOCKER_PASWORD=pw\n' >"${EF}"; chmod 600 "${EF}"; ENVS=""; rc=$(up)
chk "env file with misspelled password key -> up exits 2" 2 "$rc"
grep -q 'podman compose' "${W}/log" 2>/dev/null && no "misspelled key: no compose" || ok "misspelled key: no compose"
rm -f "${EF}"

# R2: a caller with tracing OFF stays OFF after the call, on every return path; a later secret is not traced
for path in rc0 rc2 off missing; do
  rm -f "${W}/log"; mkenv 600; envs=""; sqd="${SQ}"
  case "${path}" in
    rc0) envs="" ;;
    rc2) chmod 644 "${EF}" ;;
    off) envs="SONAR_REGISTRY_LOGIN=off" ;;
    missing) sqd="${W}/emptysq"; mkdir -p "${sqd}"; cp "${SQ}/sonarqube_lib.sh" "${sqd}/" ;;
  esac
  env -i PATH="${W}/fake:${TOOLS}" HOME="${W}/home" XDG_CONFIG_HOME="${W}/home/.config" FAKE_LOG="${W}/log" ${envs:+$envs} bash -c '
    . "$1/sonarqube_lib.sh"; set +x; sq_registry_login_auto; S=LATERSECRET-$2; echo "$S" >/dev/null; case $- in *x*) echo TRACEON ;; *) echo TRACEOFF ;; esac' _ "${sqd}" "${path}" >"${W}/ro" 2>"${W}/re"
  grep -q TRACEOFF "${W}/ro" && ok "trace stays OFF after call (${path})" || no "trace stays OFF after call (${path})"
  grep -q LATERSECRET "${W}/re" && no "later secret not traced (${path})" || ok "later secret not traced (${path})"
done

# the scan script itself pulls nothing and must not claim to log in
grep -q 'sq_registry_login_auto' "${SQ}/sonarqube_run_scan.sh" && no "run_scan does not claim login" || ok "run_scan does not claim login"
printf '\n%s passed, %s failed\n' "${PASS}" "${FAIL}"; [ "${FAIL}" -eq 0 ]
