#!/usr/bin/env bash
# test_registry_login_mutation_test.sh - paired §1.1 mutation test for registry_login.sh and
# its wiring. Each mutant is applied to a scratch COPY and must make the matching test FAIL;
# the unmutated copies must PASS and the source files must be byte-identical afterwards
# (cmp-verified). Mutants M1..M26, R1..R8, F3a..F4 target registry_login.sh (test_registry_login.sh),
# W1..W8 target sonarqube_lib.sh / sonarqube_container.sh (test_registry_login_wiring.sh).
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
wmut() { # name file old new   (the xtrace wrapper and ${!v+x} are redundant defences; W5 removes both)
    rm -rf "${W}/wm"; cp -r "${W}/sqcopy" "${W}/wm"
    mutate "${W}/wm/$2" "$1" "$3" "$4" || { echo "FAIL $1 (anchor missing)"; BAD=1; return; }
    if wire_test "${W}/wm"; then echo "FAIL mutant survived: $1"; BAD=1; else echo "ok   mutant killed: $1"; KILLED=$((KILLED+1)); fi
}
rlmut M1-password-in-argv 'login "--username=${user}" --password-stdin "${reg}"' 'login "--username=${user}" --password "${pass}" --password-stdin "${reg}"'
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
rlmut M15-auth-config-ignored 'elif [ -n "${ac}" ]; then' 'elif false; then'
rlmut M16-fake-auth-config-success 'rl_err "DOCKER_AUTH_CONFIG is not a usable' 'exit 0; rl_err "DOCKER_AUTH_CONFIG is not a usable'
rlmut M17-helper-only-config-aborts 'exit "${RL_EXIT_SKIP}" ;;
                *)' 'exit "${RL_EXIT_BLIND}" ;;
                *)'
rlmut M21-config-error-widened-to-skip 'unknown keys or empty)"; exit "${RL_EXIT_BLIND}" ;;' 'unknown keys or empty)"; exit "${RL_EXIT_SKIP}" ;;'
rlmut M22-typo-entry-key-accepted '        else:
            return 2
    if pairs:' '        else:
            helper_only = True
    if pairs:'
rlmut M23-non-dict-auths-skipped 'if not isinstance(a, dict):
        return 2' 'if not isinstance(a, dict):
        return 3'
rlmut M24-partial-creds-read-as-absent 'elif [ -n "${user}${pass}" ]; then' 'elif false; then'
rlmut M25-registry-only-read-as-absent 'elif [ -n "${reg}" ]; then
            rl_err "a registry' 'elif false; then
            rl_err "a registry'
rlmut M26-unusable-env-file-read-as-absent 'elif [ -n "${RL_EF}" ]; then' 'elif false; then'
rlmut R1-empty-entry-skips-without-helper 'elif e == {} and helper:' 'elif e == {}:'
rlmut R2-empty-credsstore-accepted 'and o["credsStore"] != ""' ''
rlmut R4-python-not-isolated 'python3 -I -c' 'python3 -c'
rlmut R5-python-crash-becomes-skip '                3) rl_log "SKIP credentials_absent: DOCKER_AUTH_CONFIG holds' '                1|3) rl_log "SKIP credentials_absent: DOCKER_AUTH_CONFIG holds'
rlmut R6-empty-identitytoken-accepted 'and e["identitytoken"] != ""' ''
rlmut R7-credhelper-value-unchecked 'all(isinstance(v, str) and v for v in ch.values())' 'True'
rlmut R8-python-missing-is-skip 'command -v python3 >/dev/null 2>&1 || return 2' 'command -v python3 >/dev/null 2>&1 || return 3'
rlmut F3a-control-char-in-auth-value-allowed 'or any(c in v for c in "\t\n\r"):' ':'
rlmut F3b-control-char-in-host-allowed 'or any(c in h for c in "\t\n\r"):' ':'
rlmut F4-surrogate-passes-through '.encode("utf-8")
        except' '.encode("utf-8", "surrogatepass")
        except'
rlmut N-plain-user-whitespace-split-allowed 'rl_field_ok "username" "${user}" && rl_field_ok "password" "${pass}" || exit "${RL_EXIT_BLIND}"' ':'
rlmut N-decoded-fields-unvalidated 'rl_field_ok "username (entry ${h})" "${du}" && rl_field_ok "password (entry ${h})" "${dp}" || exit "${RL_EXIT_BLIND}"' ':'
rlmut N-control-char-check-dropped 'if [[ "${v}" =~ [[:cntrl:]] ]]; then' 'if false; then'
rlmut N-whitespace-only-check-dropped 'if [[ "${v}" =~ ^[[:space:]]+$ ]]; then' 'if false; then'
rlmut N-empty-check-dropped 'if [ -z "${v}" ]; then rl_err "${n} is empty"; return 1; fi' ':'
rlmut N-username-bare-option 'login "--username=${user}"' 'login --username "${user}"'
# trailing newline stripped AND the (redundant) length check dropped: the newline must still be caught by the control-char rule alone being bypassed
cp "${W}/orig/registry_login.sh" "${W}/m.sh"
mutate "${W}/m.sh" x 'printf x)"; d="${d%x}"' 'printf x)"; d="${d%x}"; d="${d%$'"'"'\n'"'"'}"' && mutate "${W}/m.sh" x '[ "$(LC_ALL=C; echo "${#d}")" = "${nb//[[:space:]]/}" ] ||' 'true ||' || { echo "FAIL N-trailing anchors"; BAD=1; }
if rl_test "${W}/m.sh"; then echo "FAIL mutant survived: N-trailing-newline-stripped"; BAD=1; else echo "ok   mutant killed: N-trailing-newline-stripped"; KILLED=$((KILLED+1)); fi
rlmut N-nul-length-check-dropped '[ "$(LC_ALL=C; echo "${#d}")" = "${nb//[[:space:]]/}" ] ||' 'true ||'
rlmut N-empty-host-allowed 'or h == "" or any(c in h' 'or any(c in h'
rlmut N-registry-arg-alone-skipped 'elif [ -n "${reg}" ]; then
            rl_err "a registry' 'elif [ -n "${DOCKER_REGISTRY:-}" ]; then
            rl_err "a registry'
rlmut M18-registry-charset-unchecked 'case "${h}" in -*|*[!A-Za-z0-9._:/-]*|"")' 'case "${h}" in "__none__")'
rlmut M19-verify-unmasked 'rl_mask "${DOCKER_PASSWORD:-}" "${DOCKER_TOKEN:-}" | tail' 'cat | tail'
rlmut M20-existing-auth-dir-trusted '[ "$(stat -c %a "${ad}" 2>/dev/null)" = 700 ]' 'true'
# M6: xtrace enforcement off everywhere (all set +x, the xtrace redirection and the re-assert)
cp "${W}/orig/registry_login.sh" "${W}/m.sh"; sed -i 's/set +x/set -x/g; s/BASH_XTRACEFD=9/BASH_XTRACEFD=2/g' "${W}/m.sh"
if rl_test "${W}/m.sh"; then echo "FAIL mutant survived: M6-xtrace-enforcement-off"; BAD=1; else echo "ok   mutant killed: M6-xtrace-enforcement-off"; KILLED=$((KILLED+1)); fi
wmut W1-rc1-treated-as-skip sonarqube_lib.sh '        3)  sq_log' '        1|3)  sq_log'
wmut W2-login-call-removed sonarqube_container.sh '    sq_registry_login_auto || {' '    true || {'
wmut W3-no-export-of-docker-vars sonarqube_lib.sh '[ -n "${!v+x}" ] && export "${v?}"' ':'
wmut W4-explicit-missing-file-skipped sonarqube_lib.sh ' && [ -z "${SONAR_REGISTRY_ENV_FILE:-}" ]; then' '; then'
# W5: BOTH xtrace defences removed (scoped set +x and the value-free set-ness test) must leak
rm -rf "${W}/wm"; cp -r "${W}/sqcopy" "${W}/wm"
mutate "${W}/wm/sonarqube_lib.sh" x 'case $- in *x*) _xt=1; set +x ;; esac' ':' && mutate "${W}/wm/sonarqube_lib.sh" x '[ -n "${!v+x}" ] && export' '[ -n "${!v:-}" ] && export' \
    || { echo "FAIL W5 anchors"; BAD=1; }
if wire_test "${W}/wm"; then echo "FAIL mutant survived: W5-xtrace-defences-removed"; BAD=1; else echo "ok   mutant killed: W5-xtrace-defences-removed"; KILLED=$((KILLED+1)); fi
# W6: trace not restored after the call
wmut W6-xtrace-not-restored sonarqube_lib.sh '[ "${_xt}" = 1 ] && set -x' ':'
wmut N1-token-trigger-dropped sonarqube_lib.sh '${DOCKER_TOKEN+x}' ''
wmut N7-registry-trigger-dropped sonarqube_lib.sh '${DOCKER_REGISTRY+x}' ''
wmut N-password-trigger-dropped sonarqube_lib.sh '${DOCKER_PASSWORD+x}' ''
# W7: trace turned on unconditionally after the call (caller with tracing OFF must stay OFF)
wmut W7-xtrace-forced-on sonarqube_lib.sh '[ "${_xt}" = 1 ] && set -x' 'set -x'
# W8: library maps registry_login exit 3 (SKIP) to a failure instead of success
wmut W8-skip-rc3-not-success sonarqube_lib.sh 'continuing"; return 0 ;;' 'continuing"; return 3 ;;'
# restore proof: sources untouched
for f in registry_login.sh sonarqube_lib.sh sonarqube_container.sh sonarqube_run_scan.sh; do
    cmp -s "${SQ}/${f}" "${W}/orig/${f}" && echo "ok   source unchanged: ${f}" || { echo "FAIL source changed: ${f}"; BAD=1; }
done
echo "mutants killed: ${KILLED}"
[ "${KILLED}" -ge 12 ] || BAD=1
exit "${BAD}"
