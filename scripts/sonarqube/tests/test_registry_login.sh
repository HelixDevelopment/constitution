#!/usr/bin/env bash
# test_registry_login.sh - UNIT-CLASS gate-logic test of registry_login.sh (§11.4.289(C)(2)).
# A local FAKE podman/docker records argv + stdin; this proves the script's own
# decisions, NOT that a real registry login works (no live claim is made).
# Usage: bash test_registry_login.sh   Exit: 0 all pass, 1 any fail.
# Mutation: REGISTRY_LOGIN_UNDER_TEST=<path to mutated copy> (see mutation test).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${REGISTRY_LOGIN_UNDER_TEST:-${HERE}/../registry_login.sh}"
W="$(mktemp -d "${TMPDIR:-/tmp}/rltest.XXXXXX")" || exit 2
trap 'rm -rf "${W:?}"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$2' got '$3')"; fi; }

SECRET='S3cr3t-Pa$$w0rd/x&y'
TOOLS="${W}/tools"; mkdir -p "${TOOLS}"
for t in bash env stat grep sed mktemp cat rm date dirname basename mkdir chmod tr head id uname readlink base64 timeout ln; do
    p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "${TOOLS}/$t"
done
mkfake() { # $1=name dir
    mkdir -p "$1"
    cat >"$1/$2" <<'FAKE'
#!/bin/bash
{ printf '%s\n' "$0" ; for a in "$@"; do printf 'ARG:%s\n' "$a"; done; } >>"${FAKE_LOG:?}"
if [ "${1:-}" = login ] || [ "${1:-}" = logout ]; then
  case " $* " in *" --password-stdin "*) cat >"${FAKE_LOG}.stdin";; esac
  [ -n "${FAKE_ECHO_SECRET:-}" ] && printf 'login line %s\n' "${FAKE_ECHO_SECRET}"
fi
printf 'REGISTRY_AUTH_FILE=%s\n' "${REGISTRY_AUTH_FILE:-}" >>"${FAKE_LOG}"
exit "${FAKE_RC:-0}"
FAKE
    chmod +x "$1/$2"
}
mkfake "${W}/fakeP" podman
mkfake "${W}/fakeD" docker
mkdir -p "${W}/fakeB"; cp "${W}/fakeP/podman" "${W}/fakeB/podman"; cp "${W}/fakeD/docker" "${W}/fakeB/docker"

run() { # runs SUT in clean env; extra env via E_* passthrough in $ENVS; args after --
    local path="$1"; shift
    env -i PATH="${path}" HOME="${W}/home" XDG_CONFIG_HOME="${W}/home/.config" XDG_RUNTIME_DIR="${W}/run" \
        FAKE_LOG="${W}/log" ${ENVS:-} bash "${SUT}" "$@" >"${W}/out" 2>"${W}/err"
    echo $?
}
reset() { rm -rf "${W:?}/home" "${W:?}/run" "${W}/log" "${W}/log.stdin"; mkdir -p "${W}/home/.config/helix" "${W}/run"; ENVS=""; }
envfile() { # $1 mode ; writes standard creds
    local f="${W}/home/.config/helix/sonar_registry.env"
    { echo "DOCKER_REGISTRY=reg.example.test"; echo "DOCKER_USERNAME=ci-user"; echo "DOCKER_PASSWORD='${SECRET}'"; } >"$f"
    chmod "$1" "$f"
}
noleak() { # $1 label : secret must not be in out/err/argv
    if grep -qF -- "${SECRET}" "${W}/out" "${W}/err" 2>/dev/null; then no "$1 secret leaked to output"; else ok "$1 no secret in output"; fi
    if [ -f "${W}/log" ] && grep -qF -- "${SECRET}" "${W}/log"; then no "$1 secret in argv"; else ok "$1 no secret in argv"; fi
}

# 1 golden-good: env file 0600, podman present -> login via stdin, exit 0
reset; envfile 600
rc=$(PATHX="${W}/fakeB:${TOOLS}" run "${W}/fakeB:${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env")
chk "login ok exit" 0 "$rc"
chk "podman preferred over docker" "${W}/fakeB/podman" "$(head -1 "${W}/log")"
grep -q '^ARG:--password-stdin$' "${W}/log" && ok "password-stdin flag used" || no "password-stdin flag used"
chk "password delivered on stdin" "${SECRET}" "$(cat "${W}/log.stdin" 2>/dev/null)"
grep -q '^ARG:reg.example.test$' "${W}/log" && ok "registry host passed" || no "registry host passed"
noleak "login"

# 2 docker fallback when podman absent
reset; envfile 600
rc=$(run "${W}/fakeD:${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env")
chk "docker fallback exit" 0 "$rc"
chk "docker fallback engine" "${W}/fakeD/docker" "$(head -1 "${W}/log")"

# 3 negative control: SONAR_REGISTRY_ENGINE=docker forces docker even if podman present
reset; envfile 600; ENVS="SONAR_REGISTRY_ENGINE=docker"
rc=$(run "${W}/fakeB:${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env")
chk "engine override docker" "${W}/fakeB/docker" "$(head -1 "${W}/log")"

# 4 golden-bad: env file group/world readable -> exit 2, no engine call, no secret
for m in 040 060 070 640 604 644 660 777 004 020; do
  reset; envfile "$m"
  rc=$(run "${W}/fakeB:${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env")
  chk "env file mode $m refused (exit 2)" 2 "$rc"
  [ -f "${W}/log" ] && no "mode $m: engine must not be called" || ok "mode $m: engine not called"
  noleak "mode $m"
done
reset; envfile 400
rc=$(run "${W}/fakeB:${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env")
chk "env file mode 400 accepted" 0 "$rc"

# 5 SKIP credentials_absent (no env file, no env) names variables only
reset
rc=$(run "${W}/fakeB:${TOOLS}" login)
chk "no creds -> SKIP exit 3" 3 "$rc"
grep -q 'credentials_absent' "${W}/err" "${W}/out" && ok "reason credentials_absent" || no "reason credentials_absent"
grep -q 'DOCKER_USERNAME' "${W}/err" "${W}/out" && ok "names variables" || no "names variables"
[ -f "${W}/log" ] && no "SKIP: engine not called" || ok "SKIP: engine not called"

# 6 env from environment (no file)
reset; ENVS="DOCKER_REGISTRY=r.t DOCKER_USERNAME=u DOCKER_TOKEN=${SECRET}"
rc=$(run "${W}/fakeP:${TOOLS}" login)
chk "env DOCKER_TOKEN login" 0 "$rc"
chk "token on stdin" "${SECRET}" "$(cat "${W}/log.stdin" 2>/dev/null)"; noleak "env-token"

# 7 engine failure -> exit 1 and masked output
reset; envfile 600; ENVS="FAKE_RC=1 FAKE_ECHO_SECRET=${SECRET}"
rc=$(run "${W}/fakeP:${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env")
chk "engine failure exit 1" 1 "$rc"; noleak "engine-failure-echo"
grep -q '\*\*\*' "${W}/err" "${W}/out" && ok "masking marker present" || no "masking marker present"

# 8 no engine -> exit 2
reset; envfile 600
rc=$(run "${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env")
chk "no engine -> exit 2" 2 "$rc"

# 9a --auth-file-only: podman-format file, 0600, JSON shape, private dir, no echo
reset; ENVS="DOCKER_REGISTRY=r.t DOCKER_USERNAME=u DOCKER_PASSWORD=pw1"
rc=$(run "${W}/fakeP:${TOOLS}" login --auth-file-only)
chk "auth-file-only exit" 0 "$rc"
AF="$(env -i PATH="${TOOLS}" HOME="${W}/home" XDG_RUNTIME_DIR="${W}/run" bash "${SUT}" auth-file-path 2>/dev/null)"
[ -f "$AF" ] && ok "auth file created" || no "auth file created"
chk "auth file mode 600" 600 "$(stat -c %a "$AF" 2>/dev/null)"
chk "auth dir mode 700" 700 "$(stat -c %a "$(dirname "$AF")" 2>/dev/null)"
want="{\"auths\":{\"r.t\":{\"auth\":\"$(printf 'u:pw1' | base64 | tr -d '\n')\"}}}"
chk "auth JSON shape" "$want" "$(cat "$AF" 2>/dev/null)"
grep -q 'pw1' "${W}/out" "${W}/err" && no "auth: password not echoed" || ok "auth: password not echoed"
grep -q "$(printf 'u:pw1' | base64 | tr -d '\n')" "${W}/out" "${W}/err" && no "auth: b64 not echoed" || ok "auth: b64 not echoed"
[ -f "${W}/log" ] && no "auth-file-only makes no engine call" || ok "auth-file-only makes no engine call"
# docker + auth-file-only is an honest refusal, not a faked success
reset; ENVS="DOCKER_REGISTRY=r.t DOCKER_USERNAME=u DOCKER_PASSWORD=pw1"
rc=$(run "${W}/fakeD:${TOOLS}" login --auth-file-only); chk "docker + auth-file-only -> exit 2" 2 "$rc"
# registry needing JSON escaping is rejected
reset; ENVS="DOCKER_REGISTRY=r\"x DOCKER_USERNAME=u DOCKER_PASSWORD=pw1"
rc=$(run "${W}/fakeP:${TOOLS}" login --auth-file-only); chk "unsafe registry chars rejected" 2 "$rc"

# 9b DOCKER_AUTH_CONFIG usual content (auths JSON): decoded in-process, engine login via stdin
for eng in fakeP fakeD; do
  reset; AUTHJ="{\"auths\":{\"reg.one.test\":{\"auth\":\"$(printf 'bob:%s' "${SECRET}" | base64 | tr -d '\n')\"}}}"
  rc=$(env -i PATH="${W}/${eng}:${TOOLS}" HOME="${W}/home" XDG_RUNTIME_DIR="${W}/run" FAKE_LOG="${W}/log" DOCKER_AUTH_CONFIG="${AUTHJ}" bash "${SUT}" login >"${W}/out" 2>"${W}/err"; echo $?)
  chk "AUTH_CONFIG JSON login ($eng) exit" 0 "$rc"
  grep -q '^ARG:reg.one.test$' "${W}/log" && ok "AUTH_CONFIG host used ($eng)" || no "AUTH_CONFIG host used ($eng)"
  grep -q '^ARG:bob$' "${W}/log" && ok "AUTH_CONFIG user decoded ($eng)" || no "AUTH_CONFIG user decoded ($eng)"
  chk "AUTH_CONFIG password on stdin ($eng)" "${SECRET}" "$(cat "${W}/log.stdin" 2>/dev/null)"; noleak "auth-config $eng"
done
reset; rc=$(env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" DOCKER_AUTH_CONFIG='not json' bash "${SUT}" login >/dev/null 2>&1; echo $?)
chk "malformed DOCKER_AUTH_CONFIG -> exit 2" 2 "$rc"
reset; rc=$(env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" DOCKER_AUTH_CONFIG='{"auths":{"h":{}},"credsStore":"x"}' bash "${SUT}" login >/dev/null 2>&1; echo $?)
chk "AUTH_CONFIG without auth entries -> exit 2 (no fake success)" 2 "$rc"

# 9c docker branch must not leak the password to argv (reviewer R2)
reset; envfile 600
rc=$(run "${W}/fakeD:${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env"); noleak "docker branch"
chk "docker branch stdin" "${SECRET}" "$(cat "${W}/log.stdin" 2>/dev/null)"

# 9d options without a value must exit 2 and never hang (reviewer finding 2)
for o in "login --env-file" "verify --probe-image" "login --engine" "discover --registry"; do
  reset; rc=$(cd "${W}" && env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" timeout 5 bash "${SUT}" $o >/dev/null 2>&1; echo $?)
  chk "no hang, exit 2: $o" 2 "$rc"
done

# 9e symlinked env file refused (R3); not-owned file refused with the owner message (R5)
reset; envfile 600; ln -s "${W}/home/.config/helix/sonar_registry.env" "${W}/link.env"
rc=$(run "${W}/fakeP:${TOOLS}" login --env-file "${W}/link.env"); chk "symlinked env file refused" 2 "$rc"
[ -f "${W}/log" ] && no "symlink: engine not called" || ok "symlink: engine not called"
grep -q 'symlink' "${W}/err" && ok "symlink refusal names the symlink" || no "symlink refusal names the symlink"
reset
if [ -f /etc/hostname ] && [ ! -O /etc/hostname ]; then
  rc=$(run "${W}/fakeP:${TOOLS}" login --env-file /etc/hostname); chk "not-owned env file refused" 2 "$rc"
  grep -q 'not owned' "${W}/err" && ok "owner check message" || no "owner check message"
else echo "SKIP owner check: no foreign-owned fixture file (reason: topology_unsupported)"; fi

# 9f env file with set -x must not leak (finding 6), also under bash -x
reset; { echo "set -x"; echo "DOCKER_REGISTRY=reg.example.test"; echo "DOCKER_USERNAME=ci-user"; echo "DOCKER_PASSWORD='${SECRET}'"; echo "set -x"; } >"${W}/home/.config/helix/sonar_registry.env"
chmod 600 "${W}/home/.config/helix/sonar_registry.env"
rc=$(run "${W}/fakeP:${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env"); chk "planted set -x: login ok" 0 "$rc"; noleak "planted set -x"
env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" FAKE_LOG="${W}/log" BASH_XTRACEFD= bash -x "${SUT}" login --env-file "${W}/home/.config/helix/sonar_registry.env" >"${W}/out" 2>"${W}/err"
noleak "planted set -x + bash -x"

# 9g engine flag beats env; explicit-missing env file is exit 2 not SKIP (finding 8)
reset; envfile 600; ENVS="SONAR_REGISTRY_ENGINE=docker"
rc=$(run "${W}/fakeB:${TOOLS}" login --engine podman --env-file "${W}/home/.config/helix/sonar_registry.env")
chk "--engine beats SONAR_REGISTRY_ENGINE" "${W}/fakeB/podman" "$(head -1 "${W}/log")"
reset; ENVS="SONAR_REGISTRY_ENV_FILE=${W}/absent.env"; rc=$(run "${W}/fakeP:${TOOLS}" login); chk "explicit missing SONAR_REGISTRY_ENV_FILE -> 2" 2 "$rc"
reset; rc=$(run "${W}/fakeP:${TOOLS}" login --env-file "${W}/absent2.env"); chk "explicit missing --env-file -> 2" 2 "$rc"
reset; ENVS="SONAR_REGISTRY_ENGINE=nonsense"; envfile 600; rc=$(run "${W}/fakeP:${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env"); chk "invalid engine name -> 2" 2 "$rc"

# 9h logout engine failure must not be reported as success (R1)
reset; envfile 600; ENVS="FAKE_RC=1"; rc=$(run "${W}/fakeP:${TOOLS}" logout --env-file "${W}/home/.config/helix/sonar_registry.env"); chk "logout engine failure -> 1" 1 "$rc"

# 10 discover reports presence only, helper detection
reset; mkdir -p "${W}/home/.docker"
printf '{"auths":{"reg.example.test":{"auth":"QUJDOkRFRg=="}}}' >"${W}/home/.docker/config.json"
rc=$(run "${TOOLS}" discover --registry reg.example.test)
chk "discover finds docker config" 0 "$rc"
grep -q 'config.json' "${W}/out" && ok "discover names file" || no "discover names file"
grep -q 'QUJDOkRFRg' "${W}/out" "${W}/err" && no "discover no auth value" || ok "discover no auth value"
printf '{"credsStore":"secretservice"}' >"${W}/home/.docker/config.json"
rc=$(run "${TOOLS}" discover)
grep -q 'credential-helper' "${W}/out" && ok "helper detected" || no "helper detected"
rm -f "${W}/home/.docker/config.json"
rc=$(run "${TOOLS}" discover); chk "discover none -> SKIP 3" 3 "$rc"
ENVS="REGISTRY_AUTH_FILE=${W}/custom.json"; echo '{"auths":{}}' >"${W}/custom.json"
rc=$(run "${TOOLS}" discover); chk "discover REGISTRY_AUTH_FILE" 0 "$rc"

# 11 verify
reset; rc=$(run "${W}/fakeP:${TOOLS}" verify)
chk "verify no probe -> SKIP 3" 3 "$rc"; grep -q probe_image_absent "${W}/err" "${W}/out" && ok "probe reason" || no "probe reason"
rc=$(run "${W}/fakeP:${TOOLS}" verify --probe-image reg.example.test/priv/img:1)
chk "verify pull ok" 0 "$rc"; grep -q '^ARG:pull$' "${W}/log" && ok "verify uses pull" || no "verify uses pull"
reset; ENVS="FAKE_RC=1"; rc=$(run "${W}/fakeP:${TOOLS}" verify --probe-image x/y:1); chk "verify pull fail -> 1" 1 "$rc"

# 12 logout
reset; envfile 600
rc=$(run "${W}/fakeP:${TOOLS}" logout --env-file "${W}/home/.config/helix/sonar_registry.env")
chk "logout ok" 0 "$rc"; grep -q '^ARG:logout$' "${W}/log" && ok "logout verb" || no "logout verb"
reset; rc=$(run "${W}/fakeP:${TOOLS}" logout); chk "logout no registry -> SKIP" 3 "$rc"

# 13 bad usage -> 2; xtrace cannot leak
rc=$(run "${TOOLS}" frobnicate); chk "unknown mode -> 2" 2 "$rc"
reset; envfile 600; ENVS="SHELLOPTS=xtrace"
env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" XDG_RUNTIME_DIR="${W}/run" FAKE_LOG="${W}/log" BASHOPTS= bash -x "${SUT}" login --env-file "${W}/home/.config/helix/sonar_registry.env" >"${W}/out" 2>"${W}/err"
noleak "bash -x invocation"

# 14 control needles (§11.4.273): the leak detector can see a planted secret
printf '%s' "${SECRET}" >"${W}/needle"; grep -qF -- "${SECRET}" "${W}/needle" && ok "needle: detector sees planted secret" || no "needle: detector blind"
grep -qF -- "ABSENT-FABRICATED-NEEDLE" "${W}/needle" && no "needle: negative control" || ok "needle: negative control absent"

printf '\n%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
