#!/usr/bin/env bash
# test_registry_login_wiring.sh - UNIT-CLASS gate-logic test (§11.4.289(C)(2)) that
# sonarqube_run_scan.sh / sq_registry_login_auto log in BEFORE the scan and fail
# closed / SKIP honestly. Fake podman + fake sonar-scanner; no network, no registry.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="${REGISTRY_WIRING_SQ_DIR:-${HERE}/..}"
W="$(mktemp -d "${TMPDIR:-/tmp}/rlwire.XXXXXX")" || exit 2
trap 'rm -rf "${W:?}"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }
chk() { [ "$2" = "$3" ] && ok "$1" || no "$1 (want '$2' got '$3')"; }
TOOLS="${W}/tools"; mkdir -p "${TOOLS}" "${W}/fake" "${W}/proj" "${W}/home/.config/helix"
for t in bash env stat grep sed mktemp cat rm date dirname basename mkdir chmod tr head id seq sleep curl cp; do
    p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "${TOOLS}/$t"
done
cat >"${W}/fake/podman" <<'F'
#!/bin/bash
echo "podman $1" >>"${FAKE_LOG:?}"; [ "$1" = login ] && cat >/dev/null; exit 0
F
cat >"${W}/fake/sonar-scanner" <<'F'
#!/bin/bash
echo scanner-ran >>"${FAKE_LOG:?}"; exit 0
F
chmod +x "${W}/fake/"*
EF="${W}/home/.config/helix/sonar_registry.env"
mkenv() { printf 'DOCKER_REGISTRY=r.t\nDOCKER_USERNAME=u\nDOCKER_PASSWORD=pw\n' >"${EF}"; chmod "$1" "${EF}"; }
scan() { rm -f "${W}/log"; env -i PATH="${W}/fake:${TOOLS}" HOME="${W}/home" XDG_CONFIG_HOME="${W}/home/.config" \
    FAKE_LOG="${W}/log" SONAR_TOKEN=tok SONAR_HOST_URL=http://127.0.0.1:1 ${ENVS:-} \
    bash "${SQ}/sonarqube_run_scan.sh" "${W}/proj" >"${W}/out" 2>"${W}/err"; echo $?; }

ENVS=""; mkenv 600
rc=$(scan); grep -q 'podman login' "${W}/log" && ok "login happens during scan startup" || no "login happens during scan startup"
grep -q scanner-ran "${W}/log" && no "scanner must not run (server down)" || ok "scan stopped after login at server check"
chk "proceeds past login (exit 2 server-down, not auth)" 2 "$rc"; grep -q 'not UP' "${W}/err" && ok "reached server check after login" || no "reached server check after login"

mkenv 644; rc=$(scan); chk "bad env perms -> scan aborts exit 2" 2 "$rc"
grep -q 'podman' "${W}/log" 2>/dev/null && no "no engine call on bad perms" || ok "no engine call on bad perms"
grep -q 'authentication failed' "${W}/err" && ok "fail-closed message" || no "fail-closed message"

rm -f "${EF}"; rc=$(scan); grep -q 'SKIP credentials_absent' "${W}/err" && ok "no creds -> documented SKIP" || no "no creds -> documented SKIP"
grep -q 'not UP' "${W}/err" && ok "scan continues after SKIP" || no "scan continues after SKIP"

mkenv 600; ENVS="SONAR_REGISTRY_LOGIN=off"; rc=$(scan)
grep -q podman "${W}/log" 2>/dev/null && no "off switch honoured" || ok "off switch honoured"
printf '\n%s passed, %s failed\n' "${PASS}" "${FAIL}"; [ "${FAIL}" -eq 0 ]
