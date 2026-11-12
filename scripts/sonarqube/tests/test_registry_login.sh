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
for t in bash env stat grep sed mktemp cat rm date dirname basename mkdir chmod tr head id uname readlink base64 timeout ln tail python3; do
    p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "${TOOLS}/$t"
done
mkfake() { # $1=name dir
    mkdir -p "$1"
    cat >"$1/$2" <<'FAKE'
#!/bin/bash
{ printf '%s\n' "$0" ; for a in "$@"; do printf 'ARG:%s\n' "$a"; done; } >>"${FAKE_LOG:?}"
if [ "${1:-}" = pull ] && [ -n "${FAKE_ECHO_SECRET:-}" ]; then printf 'pull line %s\n' "${FAKE_ECHO_SECRET}"; fi
if [ "${1:-}" = login ] || [ "${1:-}" = logout ]; then
  case " $* " in *" --password-stdin "*) cat >>"${FAKE_LOG}.stdin"; echo >>"${FAKE_LOG}.stdin";; esac
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
chk "AUTH_CONFIG without auth entries -> SKIP 3 (no fake success)" 3 "$rc"

# 9c docker branch must not leak the password to argv (reviewer R2)
reset; envfile 600
rc=$(run "${W}/fakeD:${TOOLS}" login --env-file "${W}/home/.config/helix/sonar_registry.env"); noleak "docker branch"
chk "docker branch stdin" "${SECRET}" "$(cat "${W}/log.stdin" 2>/dev/null)"

# 9d options without a value must exit 2 and never hang (reviewer finding 2)
for o in "login --env-file" "verify --probe-image" "login --engine" "discover --registry"; do
  reset; rc=$(cd "${W}" && env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" timeout 5 bash "${SUT}" $o >/dev/null 2>&1; echo $?)
  chk "no hang, exit 2: $o" 2 "$rc"
done

# 9d2 credHelpers/identitytoken-only config: honest SKIP, no engine call (m-1)
reset; rc=$(env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" FAKE_LOG="${W}/log" DOCKER_AUTH_CONFIG='{"credsStore":"desktop","auths":{"h":{"identitytoken":"abc"}}}' bash "${SUT}" login >"${W}/out" 2>"${W}/err"; echo $?)
chk "helper/identitytoken-only AUTH_CONFIG -> SKIP 3" 3 "$rc"; [ -f "${W}/log" ] && no "helper-only: engine not called" || ok "helper-only: engine not called"

# 9d2b config errors are NEVER a SKIP: each must exit 2 with no engine call (m-1 regression)
i=0
for bad in '{"x":1}' '{"auths": garbage' '{"auths":{"r.io":{"auth":"dTpw' '{"auths":{"r.io":{"Auth":"dTpw"}}}' '{x}' '{"auths":{}}' '{"auths":[]}' '{"auths":{"r.io":{"auth":"%%%notbase64"}}}' '{"auths":{"r.io":"str"}}'; do
  i=$((i+1)); reset
  rc=$(env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" FAKE_LOG="${W}/log" DOCKER_AUTH_CONFIG="$bad" bash "${SUT}" login >"${W}/out" 2>"${W}/err"; echo $?)
  chk "config error #$i -> exit 2 not SKIP" 2 "$rc"; [ -f "${W}/log" ] && no "config error #$i: engine not called" || ok "config error #$i: engine not called"
done
# genuine helper-only shapes remain an honest SKIP
for okskip in '{"credsStore":"x"}' '{"credHelpers":{"h":"y"}}' '{"auths":{"h":{"identitytoken":"abc"}}}'; do
  reset; rc=$(env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" FAKE_LOG="${W}/log" DOCKER_AUTH_CONFIG="$okskip" bash "${SUT}" login >/dev/null 2>&1; echo $?)
  chk "helper-only shape SKIP: $okskip" 3 "$rc"
done

# 9e FULL MATRIX (round 5, class-level): registry x user x password x token x auth-config,
# no env file. Expected exit comes from an independent oracle below; 0 = login done, 2 = config
# error (incomplete / unusable credentials), 3 = nothing configured or valid helper-only.
UAUTH="{\"auths\":{\"h.t\":{\"auth\":\"$(printf 'a:b' | base64)\"}}}"
mrun() { # args: VAR=VAL ...  -> exit code (no env file)
    reset; env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" XDG_CONFIG_HOME="${W}/home/.config" FAKE_LOG="${W}/log" "$@" bash "${SUT}" login >"${W}/out" 2>"${W}/err"; echo $?; }
oracle() { # $1 reg $2 user $3 pass $4 token $5 ac(absent|empty|usable|helper) -> expected
    local r="$1" u="$2" p="$3" k="$4" a="$5" pw=""
    [ "$p" = set ] && pw=1; [ -z "$pw" ] && [ "$k" = set ] && pw=1
    if [ "$u" = set ] && [ -n "$pw" ] && [ "$r" = set ]; then echo 0
    elif [ "$u" = set ] || [ -n "$pw" ]; then echo 2
    elif [ "$a" = usable ]; then echo 0
    elif [ "$a" = helper ]; then echo 3
    elif [ "$r" = set ]; then echo 2
    else echo 3; fi; }
mrows=0; mbad=0
for r in absent empty set; do for u in absent empty set; do for p in absent empty set; do for k in absent empty set; do for a in absent empty usable helper; do
  e=(); [ "$r" != absent ] && e+=("DOCKER_REGISTRY=$([ "$r" = set ] && echo reg.t)")
  [ "$u" != absent ] && e+=("DOCKER_USERNAME=$([ "$u" = set ] && echo usr)")
  [ "$p" != absent ] && e+=("DOCKER_PASSWORD=$([ "$p" = set ] && echo pw)")
  [ "$k" != absent ] && e+=("DOCKER_TOKEN=$([ "$k" = set ] && echo tok)")
  case "$a" in empty) e+=("DOCKER_AUTH_CONFIG=") ;; usable) e+=("DOCKER_AUTH_CONFIG=${UAUTH}") ;; helper) e+=('DOCKER_AUTH_CONFIG={"credsStore":"x"}') ;; esac
  want="$(oracle "$r" "$u" "$p" "$k" "$a")"; got="$(mrun "${e[@]}")"; mrows=$((mrows+1))
  [ "$want" = "$got" ] || { mbad=$((mbad+1)); no "matrix reg=$r user=$u pass=$p token=$k ac=$a (want $want got $got)"; }
done; done; done; done; done
[ "$mbad" -eq 0 ] && ok "matrix: ${mrows} rows all as expected"
# a 2-exit never reaches the engine; secret values never in output
reset; rc=$(mrun DOCKER_REGISTRY=r.t DOCKER_USERNAME=u); grep -q . "${W}/log" 2>/dev/null && no "partial creds: engine not called" || ok "partial creds: engine not called"
reset; rc=$(mrun DOCKER_USERNAME=u DOCKER_AUTH_CONFIG='{"credsStore":"x"}'); chk "user + helper-only config -> 2" 2 "$rc"
# env-file dimension: file with content X, nothing else in env
efrun() { reset; printf '%s\n' "$@" >"${W}/home/.config/helix/sonar_registry.env"; chmod 600 "${W}/home/.config/helix/sonar_registry.env"
    env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" XDG_CONFIG_HOME="${W}/home/.config" FAKE_LOG="${W}/log" bash "${SUT}" login >"${W}/out" 2>"${W}/err"; echo $?; }
chk "env file complete -> 0" 0 "$(efrun DOCKER_REGISTRY=r.t DOCKER_USERNAME=u DOCKER_PASSWORD=p)"
chk "env file misspelled password key -> 2" 2 "$(efrun DOCKER_REGISTRY=r.t DOCKER_USERNAME=u DOCKER_PASWORD=p)"
chk "env file empty -> 2" 2 "$(efrun '')"
chk "env file comments only -> 2" 2 "$(efrun '# nothing')"
chk "env file unrelated vars only -> 2" 2 "$(efrun FOO=bar)"
chk "env file registry only -> 2" 2 "$(efrun DOCKER_REGISTRY=r.t)"
chk "env file user+pass no registry -> 2" 2 "$(efrun DOCKER_USERNAME=u DOCKER_PASSWORD=p)"
chk "env file helper-only config -> 3" 3 "$(efrun "DOCKER_AUTH_CONFIG='{\"credsStore\":\"x\"}'")"
chk "env file DOCKER_PASSWORD='' with user -> 2" 2 "$(efrun DOCKER_REGISTRY=r.t DOCKER_USERNAME=u DOCKER_PASSWORD=)"
reset; rc=$(env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" XDG_CONFIG_HOME="${W}/home/.config" bash "${SUT}" login >/dev/null 2>&1; echo $?); chk "no env file, nothing configured -> 3" 3 "$rc"

# 9f python classifier hardening (round 5)
rm -f "${W}/pwned"; mkdir -p "${W}/pp" "${W}/cwd"
printf 'open("%s","w").write("x")\nraise SystemExit(0)\n' "${W}/pwned" >"${W}/pp/json.py"
cp "${W}/pp/json.py" "${W}/cwd/json.py"; cp "${W}/pp/json.py" "${W}/cwd/sitecustomize.py"
reset; rc=$(cd "${W}/cwd" && env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" PYTHONPATH="${W}/pp" FAKE_LOG="${W}/log" DOCKER_AUTH_CONFIG="${UAUTH}" bash "${SUT}" login >/dev/null 2>&1; echo $?)
[ -e "${W}/pwned" ] && no "python isolation: planted json.py/sitecustomize.py did not run" || ok "python isolation: planted json.py/sitecustomize.py did not run"
chk "python isolation: login still works" 0 "$rc"
# a python crash (rc 1) must be a config error, never a SKIP
mkdir -p "${W}/badpy"; printf '#!/bin/sh\nexit 1\n' >"${W}/badpy/python3"; chmod +x "${W}/badpy/python3"
chk "python crash -> 2 not SKIP" 2 "$(reset; env -i PATH="${W}/badpy:${W}/fakeP:${TOOLS}" HOME="${W}/home" FAKE_LOG="${W}/log" DOCKER_AUTH_CONFIG="${UAUTH}" bash "${SUT}" login >/dev/null 2>&1; echo $?)"
# python3 absent -> 2 (not 3)
NOPY="${W}/nopy"; mkdir -p "${NOPY}"; for f in "${TOOLS}"/*; do [ "$(basename "$f")" = python3 ] || ln -s "$(readlink "$f")" "${NOPY}/$(basename "$f")"; done
chk "python3 absent -> 2 not SKIP" 2 "$(reset; env -i PATH="${W}/fakeP:${NOPY}" HOME="${W}/home" FAKE_LOG="${W}/log" DOCKER_AUTH_CONFIG='{"credsStore":"x"}' bash "${SUT}" login >/dev/null 2>&1; echo $?)"
# shape rules
for pair in '{"auths":{"h":{}}}|2' '{"auths":{"h":{}},"credsStore":"x"}|3' '{"auths":{"h":{}},"credsStore":""}|2' \
  '{"auths":{"h":{"identitytoken":""}}}|2' '{"auths":{"h":{"identitytoken":"t"}}}|3' \
  '{"credHelpers":{"h":1}}|2' '{"credHelpers":{}}|2' '{"credHelpers":{"h":"x"}}|3' \
  '{"auths":{"h":{"username":"u","password":"p"}}}|2' \
  '{"auths":{"h\r":{"auth":"YTpi"}}}|2' '{"auths":{"h":{"auth":"YT\tpi"}}}|2' '{"auths":{"h":{"auth":"YTpi\nZZ"}}}|2' '{"auths":{"h":{"auth":"YTpi\r"}}}|2' \
  '{"auths":{"h\ud800":{"auth":"YTpi"}}}|2' '{"auths":{"h":{"auth":"\udc00"}}}|2'; do
  cfg="${pair%|*}"; want="${pair##*|}"
  rc=$(reset; env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" FAKE_LOG="${W}/log" DOCKER_AUTH_CONFIG="$cfg" bash "${SUT}" login >"${W}/out" 2>"${W}/err"; echo $?)
  chk "shape ${cfg} -> ${want}" "${want}" "$rc"
  grep -q Traceback "${W}/err" "${W}/out" && no "no traceback for ${cfg}" || true
done
# classifier called directly (downstream host checks would mask these): function text extracted from the SUT
CLS="$(sed -n '/^rl_auths_pairs() {/,/^}/p' "${SUT}")"
clsrun() { printf '%s' "$1" | PATH="${TOOLS}" bash -c "${CLS}"$'\n''rl_auths_pairs' 2>/dev/null; echo "rc=$?"; }
chk "classifier: usable entry -> rc 0 with the pair" "h.t	YTpi
rc=0" "$(clsrun '{"auths":{"h.t":{"auth":"YTpi"}}}')"
chk "classifier: CR in host -> rc 2, no output" "rc=2" "$(clsrun '{"auths":{"h\r":{"auth":"YTpi"}}}')"
chk "classifier: TAB in host -> rc 2, no output" "rc=2" "$(clsrun '{"auths":{"h\tx":{"auth":"YTpi"}}}')"
chk "classifier: lone surrogate in host -> rc 2, no output" "rc=2" "$(clsrun '{"auths":{"h\ud800":{"auth":"YTpi"}}}')"
chk "classifier: lone surrogate in auth -> rc 2, no output" "rc=2" "$(clsrun '{"auths":{"h":{"auth":"\udc00"}}}')"
# injection: a TAB/newline in an auth value must never become two login records
reset; env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" FAKE_LOG="${W}/log" DOCKER_AUTH_CONFIG='{"auths":{"h.t":{"auth":"YTpi\tx.t\tZZ"}}}' bash "${SUT}" login >/dev/null 2>&1
[ "$(grep -c '^ARG:login$' "${W}/log" 2>/dev/null || true)" != 1 ] && [ ! -s "${W}/log.stdin" ] && ok "tab in auth value: no login record" || no "tab in auth value: no login record"

# 9d3 two-host auths JSON: every entry logged in (N2); long credential >57 bytes survives base64 line wrapping (N3)
reset; LONG="$(printf 'L%.0s' $(seq 1 90))-tail"
AJ="{\"auths\":{\"one.test\":{\"auth\":\"$(printf 'a:%s' "${SECRET}" | base64 | tr -d '\n')\"},\"two.test\":{\"auth\":\"$(printf 'b:%s' "${LONG}" | base64 | tr -d '\n')\"}}}"
rc=$(env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" FAKE_LOG="${W}/log" DOCKER_AUTH_CONFIG="${AJ}" bash "${SUT}" login >"${W}/out" 2>"${W}/err"; echo $?)
chk "two-host AUTH_CONFIG exit" 0 "$rc"
grep -q '^ARG:one.test$' "${W}/log" && grep -q '^ARG:two.test$' "${W}/log" && ok "both hosts logged in" || no "both hosts logged in"
chk "both passwords delivered intact on stdin" "${SECRET}
${LONG}" "$(cat "${W}/log.stdin" 2>/dev/null | sed '/^$/d')"
grep -qF -- "${LONG}" "${W}/out" "${W}/err" && no "long credential not in output" || ok "long credential not in output"

# 9d4 registry host starting with '-' or with odd characters never reaches the engine (m-2)
for bad in '--authfile=/x' '-x' 'a b' 'h;id'; do
  reset; rc=$(env -i PATH="${W}/fakeP:${TOOLS}" HOME="${W}/home" FAKE_LOG="${W}/log" DOCKER_REGISTRY="$bad" DOCKER_USERNAME=u DOCKER_PASSWORD=p bash "${SUT}" login >/dev/null 2>&1; echo $?)
  chk "bad registry '$bad' -> exit 2" 2 "$rc"; [ -f "${W}/log" ] && no "bad registry: engine not called" || ok "bad registry: engine not called"
done

# 9d5 verify masks secrets coming from the env file (N4)
reset; envfile 600; ENVS="FAKE_ECHO_SECRET=${SECRET}"
rc=$(run "${W}/fakeP:${TOOLS}" verify --env-file "${W}/home/.config/helix/sonar_registry.env" --probe-image x/y:1)
chk "verify with env file ok" 0 "$rc"; noleak "verify output"
grep -q '\*\*\*' "${W}/err" && ok "verify masking marker" || no "verify masking marker"

# 9d6 pre-made 0755 auth dir is refused, not trusted (N8)
reset; mkdir -p "${W}/run/helix_sonar_registry"; chmod 755 "${W}/run/helix_sonar_registry"
ENVS="DOCKER_REGISTRY=r.t DOCKER_USERNAME=u DOCKER_PASSWORD=pw1"
rc=$(run "${W}/fakeP:${TOOLS}" login --auth-file-only); chk "0755 auth dir refused" 2 "$rc"
[ -f "${W}/run/helix_sonar_registry/auth.json" ] && no "nothing written into the 0755 dir" || ok "nothing written into the 0755 dir"

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
