#!/usr/bin/env bash
# test_registry_login_mutation_test.sh - paired §1.1 mutation test for registry_login.sh.
# Each mutant of a scratch COPY must make test_registry_login.sh FAIL; the unmutated
# copy must PASS. Mutants: password in argv, drop mode check, docker-first order,
# unmasked output, enable xtrace, fake success on failure.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${HERE}/../registry_login.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/rlmut.XXXXXX")" || exit 2
trap 'rm -rf "${W:?}"' EXIT
BAD=0
runcopy() { REGISTRY_LOGIN_UNDER_TEST="$1" bash "${HERE}/test_registry_login.sh" >/dev/null 2>&1; }
cp "${SRC}" "${W}/base.sh"
runcopy "${W}/base.sh" && echo "ok   baseline copy passes" || { echo "FAIL baseline copy does not pass"; BAD=1; }
mut() { # name, python replace old new
    python3 - "$SRC" "${W}/m.sh" "$2" "$3" <<'PY'
import sys
s=open(sys.argv[1]).read(); old,new=sys.argv[3],sys.argv[4]
assert old in s, "mutation anchor missing: "+old
open(sys.argv[2],'w').write(s.replace(old,new,1))
PY
    [ $? -eq 0 ] || { echo "FAIL $1 (anchor missing)"; BAD=1; return; }
    if runcopy "${W}/m.sh"; then echo "FAIL mutant survived: $1"; BAD=1; else echo "ok   mutant killed: $1"; fi
}
mut password-in-argv 'login --username "${RL_USER}" --password-stdin "${RL_REG}"' 'login --username "${RL_USER}" --password "${RL_PASS}" --password-stdin "${RL_REG}"'
mut no-mode-check '[0-7]00|[0-7]0) : ;;' '*) : ;;'
mut docker-first 'command -v podman 2>/dev/null || command -v docker 2>/dev/null' 'command -v docker 2>/dev/null || command -v podman 2>/dev/null'
mut no-masking 'line="${line//"${s}"/***}"' ':'
# xtrace enforcement removed everywhere (every set +x -> set -x) and enabled at top
python3 - "$SRC" "${W}/m.sh" <<'PY'
import sys
s=open(sys.argv[1]).read().replace('set +x','set -x'); open(sys.argv[2],'w').write(s)
PY
if runcopy "${W}/m.sh"; then echo "FAIL mutant survived: xtrace-enforced-off"; BAD=1; else echo "ok   mutant killed: xtrace-enforced-off"; fi
mut fake-success 'then rl_err "$(basename "${eng}") login to ${RL_REG} failed (exit ${erc})"; exit "${RL_EXIT_FAIL}"; fi' 'then rl_err "x"; exit 0; fi'
mut skip-as-pass 'exit "${RL_EXIT_SKIP}"
        fi
        if [ "${RL_AUTH_ONLY' 'exit 0
        fi
        if [ "${RL_AUTH_ONLY'
exit "${BAD}"
