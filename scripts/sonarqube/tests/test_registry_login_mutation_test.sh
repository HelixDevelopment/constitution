#!/usr/bin/env bash
# test_registry_login_mutation_test.sh - paired §1.1 mutation test for registry_login.sh and
# its wiring. Each mutant is applied to a scratch COPY and must make the matching test FAIL;
# the unmutated copies must PASS and the source files must be byte-identical afterwards
# (cmp-verified). Mutants M1..M15 target registry_login.sh (test_registry_login.sh),
# W1..W4 target sonarqube_lib.sh / sonarqube_container.sh (test_registry_login_wiring.sh).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="${HERE}/.."
W="$(mktemp -d "${TMPDIR:-/tmp}/rlmut.XXXXXX")" || exit 2
trap 'rm -rf "${W:?}"' EXIT
BAD=0; KILLED=0
mkdir -p "${W}/orig"; cp "${SQ}/registry_login.sh" "${SQ}/sonarqube_lib.sh" "${SQ}/sonarqube_container.sh" "${SQ}/sonarqube_run_scan.sh" "${W}/orig/"
rl_test() { REGISTRY_LOGIN_UNDER_TEST="$1" bash "${HERE}/test_registry_login.sh" >/dev/null 2>&1; }
wire_test() { REGISTRY_WIRING_SQ_DIR="$1" bash "${HERE}/test_registry_login_wiring.sh" >/dev/null 2>&1; }
mkdir -p "${W}/sqcopy"; cp -r "${SQ}/compose" "${W}/sqcopy/" 2>/dev/null; cp "${W}/orig/"*.sh "${W}/sqcopy/"
rl_test "${SQ}/registry_login.sh" && echo "ok   baseline registry_login passes" || { echo "FAIL baseline registry_login"; BAD=1; }
wire_test "${W}/sqcopy" && echo "ok   baseline wiring passes" || { echo "FAIL baseline wiring"; BAD=1; }

mutate() { # file name old new [all]
    python3 - "$1" "$3" "$4" <<'PY'
import sys
f,old,new=sys.argv[1:4]; s=open(f).read()
assert old in s, "anchor missing: "+old
open(f,'w').write(s.replace(old,new,1))
PY
}
rlmut() { # name old new
    cp "${W}/orig/registry_login.sh" "${W}/m.sh"
    mutate "${W}/m.sh" "$1" "$2" "$3" || { echo "FAIL $1 (anchor missing)"; BAD=1; return; }
    if rl_test "${W}/m.sh"; then echo "FAIL mutant survived: $1"; BAD=1; else echo "ok   mutant killed: $1"; KILLED=$((KILLED+1)); fi
}
wmut() { # name file old new
    rm -rf "${W}/wm"; cp -r "${W}/sqcopy" "${W}/wm"
    mutate "${W}/wm/$2" "$1" "$3" "$4" || { echo "FAIL $1 (anchor missing)"; BAD=1; return; }
    if wire_test "${W}/wm"; then echo "FAIL mutant survived: $1"; BAD=1; else echo "ok   mutant killed: $1"; KILLED=$((KILLED+1)); fi
}
rlmut M1-password-in-argv 'login --username "${user}" --password-stdin "${reg}"' 'login --username "${user}" --password "${pass}" --password-stdin "${reg}"'
rlmut M2-no-mode-check 'if [ $(( 8#${m} & 8#077 )) -ne 0 ]; then' 'if false; then'
rlmut M3-loose-mode-mask '8#${m} & 8#077' '8#${m} & 8#007'
rlmut M4-docker-first 'command -v podman 2>/dev/null || command -v docker 2>/dev/null' 'command -v docker 2>/dev/null || command -v podman 2>/dev/null'
rlmut M5-no-masking 'line="${line//"${s}"/***}"' ':'
rlmut M7-fake-success 'return "${RL_EXIT_FAIL}"; fi
    rl_log "login' 'return 0; fi
    rl_log "login'
rlmut M8-skip-as-pass 'exit "${RL_EXIT_SKIP}"
        fi
        if [ "${RL_AUTH_ONLY' 'exit 0
        fi
        if [ "${RL_AUTH_ONLY'
rlmut M9-logout-ignores-failure '|| { rl_err "logout from ${reg} failed"; exit "${RL_EXIT_FAIL}"; }' '|| true'
rlmut M10-symlink-accepted 'if [ -L "${f}" ] ||' 'if false ||'
rlmut M11-no-owner-check '[ -O "${f}" ] || { rl_err "env file ${f} is not owned' 'true || { rl_err "env file ${f} is not owned'
rlmut M12-option-value-unchecked 'if [ -z "${2:-}" ]; then rl_err "option $1 needs a value"; return 1; fi' ':'
rlmut M13-env-engine-beats-flag '${RL_ENGINE_ARG:-${SONAR_REGISTRY_ENGINE:-}}' '${SONAR_REGISTRY_ENGINE:-${RL_ENGINE_ARG:-}}'
rlmut M14-explicit-missing-envfile-skip 'does not exist"; return 2; fi' 'does not exist"; return 0; fi'
rlmut M15-auth-config-ignored 'elif [ -z "${user}${pass}" ] && [ -n "${DOCKER_AUTH_CONFIG:-}" ]; then' 'elif false; then'
rlmut M16-fake-auth-config-success 'rl_err "DOCKER_AUTH_CONFIG is not an' 'exit 0; rl_err "DOCKER_AUTH_CONFIG is not an'
# M6: xtrace enforcement off everywhere (all set +x, the xtrace redirection and the re-assert)
cp "${W}/orig/registry_login.sh" "${W}/m.sh"; sed -i 's/set +x/set -x/g; s/BASH_XTRACEFD=9/BASH_XTRACEFD=2/g' "${W}/m.sh"
if rl_test "${W}/m.sh"; then echo "FAIL mutant survived: M6-xtrace-enforcement-off"; BAD=1; else echo "ok   mutant killed: M6-xtrace-enforcement-off"; KILLED=$((KILLED+1)); fi
wmut W1-rc1-treated-as-skip sonarqube_lib.sh '        3)  sq_log' '        1|3)  sq_log'
wmut W2-login-call-removed sonarqube_container.sh '    sq_registry_login_auto || {' '    true || {'
wmut W3-no-export-of-docker-vars sonarqube_lib.sh '[ -n "${!v:-}" ] && export "${v?}"' ':'
wmut W4-explicit-missing-file-skipped sonarqube_lib.sh ' && [ -z "${SONAR_REGISTRY_ENV_FILE:-}" ]; then' '; then'
# restore proof: sources untouched
for f in registry_login.sh sonarqube_lib.sh sonarqube_container.sh sonarqube_run_scan.sh; do
    cmp -s "${SQ}/${f}" "${W}/orig/${f}" && echo "ok   source unchanged: ${f}" || { echo "FAIL source changed: ${f}"; BAD=1; }
done
echo "mutants killed: ${KILLED}"
[ "${KILLED}" -ge 12 ] || BAD=1
exit "${BAD}"
