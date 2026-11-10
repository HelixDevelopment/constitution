#!/usr/bin/env bash
# meta_test_verification.sh — Paired mutation proving the verification gate catches regressions
# Constitution §1.1: Every gate MUST have a paired mutation proving it's not a bluff gate.
#
# Usage   : bash scripts/validation/meta_test_verification.sh
#           Exit 0 when both mutations behave as required, 1 otherwise. The
#           last line is the summary line.
# Method  : (CON-120) the checked tree is NEVER changed. Each mutation runs on
#           a scratch root under $TMPDIR (mktemp -d): a COPY of
#           run_verification.sh plus one symlink per real submodule, so a stop
#           at any moment (TERM, KILL) cannot leave a renamed submodule or an
#           edited tracked gate behind; the scratch root is removed on exit.
#           Mutation 1: the real gate on a root that lacks the 'verification'
#           submodule must FAIL. Mutation 2: a copy of the gate with the
#           'verification' requirement and check removed (a weakened gate that
#           still parses) must PASS on that same root -- so the real gate's
#           failure in mutation 1 comes from that check and nothing else.
#           Control: the real gate on the real tree (read-only) must PASS.
# Known gap: the scratch root is removed by an EXIT trap (TERM, INT and HUP also
#           run it), but SIGKILL cannot run a trap, so after a KILL the scratch
#           root stays under $TMPDIR. It holds only SYMLINKS to the real
#           submodules and a copy of the gate: `rm -rf` removes the links and
#           leaves their targets alone, but a tool that follows links (`find
#           -L`, `cp -rL`, `chmod -R` with -L) would reach the checked tree.
#           The checked tree itself is never changed (see the regression test).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSTITUTION_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERIFICATION_SCRIPT="${CONSTITUTION_ROOT}/scripts/validation/run_verification.sh"
SUBMODULES_DIR="${CONSTITUTION_ROOT}/submodules"
TEST_SUBMODULE="verification"

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "✓ $*"; }
notok() { fail=$((fail + 1)); echo "✗ $*"; }
finish() {
    echo
    echo "=== meta-test verification: pass=${pass} fail=${fail} ==="
    [ "${fail}" = 0 ] && exit 0
    exit 1
}

W="$(mktemp -d "${TMPDIR:-/tmp}/meta_test_verification.XXXXXX")" || { echo "✗ mktemp failed"; exit 1; }
cleanup() { [ -n "${W:-}" ] && [ -d "${W}" ] && rm -rf -- "${W:?}"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

echo "=== Meta-Test Mutation for Verification Gate ==="
echo "Constitution root: ${CONSTITUTION_ROOT}"
echo "Verification script: ${VERIFICATION_SCRIPT}"
echo "Scratch root: ${W} (the checked tree is never changed)"
echo

# build_root NAME [GATEFILE]: a scratch root with a copy of the gate (or GATEFILE)
# and a symlink to every real submodule except the test submodule.
build_root() {
    local r="${W}/$1" s
    mkdir -p "${r}/scripts/validation" "${r}/submodules" || return 1
    cp -- "${2:-${VERIFICATION_SCRIPT}}" "${r}/scripts/validation/run_verification.sh" || return 1
    for s in "${SUBMODULES_DIR}"/*; do
        [ -e "${s}" ] || continue
        [ "$(basename -- "${s}")" = "${TEST_SUBMODULE}" ] && continue
        ln -s -- "${s}" "${r}/submodules/$(basename -- "${s}")" || return 1
    done
    printf '%s' "${r}"
}

if [[ ! -f "${VERIFICATION_SCRIPT}" ]]; then
    notok "verification script not found: ${VERIFICATION_SCRIPT}"
    finish
fi
if [[ ! -d "${SUBMODULES_DIR}/${TEST_SUBMODULE}" ]]; then
    notok "test submodule not present: ${SUBMODULES_DIR}/${TEST_SUBMODULE} (initialise the submodules first)"
    finish
fi

# Control: the real gate on the real tree (read-only) passes.
echo "=== Control: real gate, real tree ==="
if bash "${VERIFICATION_SCRIPT}" > "${W}/verify_real.txt" 2>&1; then
    ok "real gate passes with every submodule present"
else
    notok "real gate does not pass on the real tree; output:"
    sed 's/^/    /' "${W}/verify_real.txt"
fi

# Mutation 1: the real gate on a root missing the test submodule must fail.
echo
echo "=== Mutation 1: missing submodule detection ==="
R1="$(build_root m1)" || { notok "could not build the mutation-1 scratch root"; finish; }
if bash "${R1}/scripts/validation/run_verification.sh" > "${W}/verify_missing.txt" 2>&1; then
    notok "real gate passed despite the missing '${TEST_SUBMODULE}' submodule (gate is a bluff)"
else
    ok "real gate exits non-zero when '${TEST_SUBMODULE}' is missing"
    grep -E "(MISSING|not cloned)" "${W}/verify_missing.txt" | head -5 | sed 's/^/    /'
fi

# Mutation 2: weaken a COPY of the gate (drop the test submodule's requirement
# and check); it must still parse, and it must pass on the same missing root.
echo
echo "=== Mutation 2: weakened gate (requirement removed) ==="
if python3 -I - "${VERIFICATION_SCRIPT}" "${W}/run_verification_weak.sh" "${TEST_SUBMODULE}" <<'PYEOF'
import sys
src, dst, name = sys.argv[1:4]
c = open(src, encoding="utf-8").read()
edits = ['    "%s"\n' % name,
         'run_check "%s (agent-skills)" \\\n    "ls -la %s/ && [ -f %s/README.md ]" \\\n    "${SUBMODULES_DIR}"\n' % (name, name, name)]
for old in edits:
    if c.count(old) != 1:
        sys.exit("anchor not unique: %r" % old)
    c = c.replace(old, "")
open(dst, "w", encoding="utf-8").write(c)
PYEOF
then
    if bash -n "${W}/run_verification_weak.sh" 2> "${W}/weak_syntax.txt"; then
        ok "the weakened gate parses (bash -n): a real mutation, not a syntax error"
        R2="$(build_root m2 "${W}/run_verification_weak.sh")" || { notok "could not build the mutation-2 scratch root"; finish; }
        if bash "${R2}/scripts/validation/run_verification.sh" > "${W}/verify_weak.txt" 2>&1; then
            ok "weakened gate passes on the same missing root: the '${TEST_SUBMODULE}' check is what makes the real gate exit non-zero"
        else
            notok "weakened gate still exits non-zero; the real gate's mutation-1 result is not tied to the '${TEST_SUBMODULE}' check; output:"
            tail -5 "${W}/verify_weak.txt" | sed 's/^/    /'
        fi
    else
        notok "the weakened gate does not parse:"
        sed 's/^/    /' "${W}/weak_syntax.txt"
    fi
else
    notok "could not build the weakened gate (gate text changed; update the mutation anchors)"
fi

finish
