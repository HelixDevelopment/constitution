#!/usr/bin/env bash
# =============================================================================
# test_multitrack_redpin_mutations.sh — paired §1.1 mutations for the five
#     multitrack RED/GREEN regression guards whose RED artifact is PINNED to a
#     pre-fix commit (redpin class, §11.4.115 / §11.4.224 / §11.4.292(E)).
# -----------------------------------------------------------------------------
# The guarded tests:
#   test_multitrack_orchestrator_reconcile.sh     (RB-FIX2: awk `exp` -> `xp`)
#   test_multitrack_orchestrator_reconcile_rc.sh  (RB-FIX3: awk rc captured)
#   test_multitrack_sessions_argparse.sh          (C1: "missing value" guard)
#   test_multitrack_sessions_pid_status.sh        (C2: no wrapper pid recorded)
#   test_multitrack_supervisor_wiring.sh          (RB-07: supervisor snapshot)
#
# For each guarded test, in a SCRATCH clone of this checkout (`git clone
# --shared`, then the working-tree scripts/multitrack/ copied over it so
# uncommitted edits are what is tested), this suite asserts:
#   (control) the unmutated scratch tree: the guard exits 0;
#   (fix)     the fix is removed from the CURRENT artifact by a BEHAVIOURAL
#             mutation (the guard's fix-needle string is kept wherever the
#             fix allows, so the kill must come from a GREEN behaviour leg,
#             not only from the needle check): the guard exits non-zero, not
#             77, and prints at least one "FAIL: GREEN" line;
#   (pin)     the guard's RED_PIN is pointed back at HEAD (the redpin class
#             itself): the guard refuses, rc 94 ("not the pre-fix artifact");
#   (absent)  the guard's RED_PIN names a commit the clone does not have (the
#             shallow-clone case): the guard FAILs closed, rc 93.
#
# Environment dependency (honest SKIP, §11.4.3): two guards need the RB-05
#   mock claude, a CONSUMER-project fixture. The mock is taken from
#   MT_TEST_MOCK_CLAUDE, else <outer project>/scripts/multitrack/rb05_fixtures/
#   mock_claude.sh (outer project = git toplevel above this checkout). Without
#   it those two guards' legs are reported SKIP (reason=rb05_mock_absent); the
#   other three always run. When no leg can run at all the suite exits 77.
#
# Usage: bash scripts/multitrack/test_multitrack_redpin_mutations.sh
# Inputs: MT_TEST_MOCK_CLAUDE (optional); TMPDIR (scratch root, default /tmp).
# Outputs: PASS/FAIL/SKIP lines, a "PASS=n FAIL=n SKIP=n" summary. Exit 0 iff
#   no FAIL (77 when nothing could run).
# Side-effects: one scratch directory (a shared clone plus evidence),
#   removed with safe_rm_rf (§11.4.287) on exit; never touches this checkout.
# Dependencies: bash, git, python3, grep, cp, mktemp, and what the guarded
#   tests need (sh, gawk, timeout).
# =============================================================================
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
CONST_ROOT=$(cd "$SELF_DIR" && git rev-parse --show-toplevel 2>/dev/null)
[ -n "$CONST_ROOT" ] || { echo "FATAL: not inside a git checkout"; exit 90; }
# shellcheck source=../lib/safe_rm.sh
. "$CONST_ROOT/scripts/lib/safe_rm.sh" || { echo "FATAL: cannot source safe_rm.sh"; exit 90; }

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); echo "PASS: $*"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $*"; }
skip() { SKIP=$((SKIP+1)); echo "SKIP: $*"; }

# --- RB-05 mock (consumer fixture) -------------------------------------------
MOCK=""
if [ -n "${MT_TEST_MOCK_CLAUDE:-}" ]; then
    MOCK=$MT_TEST_MOCK_CLAUDE
else
    _outer=$(cd "$CONST_ROOT/.." 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    [ -n "$_outer" ] && MOCK="$_outer/scripts/multitrack/rb05_fixtures/mock_claude.sh"
fi
[ -n "$MOCK" ] && [ -f "$MOCK" ] || MOCK=""

S=$(mktemp -d "${TMPDIR:-/tmp}/mt_redpin_mut.XXXXXX") || { echo "FATAL: mktemp failed"; exit 90; }
cleanup() { [ -n "${S:-}" ] && [ -d "$S" ] && safe_rm_rf "${S:?}"; }
trap cleanup EXIT INT TERM

# _tree NAME -> path of a fresh scratch clone with the working-tree
# scripts/multitrack/ (and scripts/lib/) copied over it.
_tree() {
    local t="$S/$1"
    git clone -q --shared --no-checkout "$CONST_ROOT" "$t" >/dev/null 2>&1 || return 1
    git -C "$t" checkout -q --detach "$(git -C "$CONST_ROOT" rev-parse HEAD)" >/dev/null 2>&1 || return 1
    cp -a "$CONST_ROOT/scripts/multitrack/." "$t/scripts/multitrack/" || return 1
    cp -a "$CONST_ROOT/scripts/lib/." "$t/scripts/lib/" || return 1
    printf '%s\n' "$t"
}

# _mutate FILE OLD NEW [COUNT] -> exact literal replacement; refuses a no-op or a
# count mismatch (a mutation that did not apply proves nothing).
_mutate() {
    python3 -I - "$1" "$2" "$3" "${4:-1}" <<'PY'
import sys
p, old, new, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
s = open(p).read()
if s.count(old) != n:
    sys.exit("mutation text found %d times, expected %d" % (s.count(old), n))
open(p, "w").write(s.replace(old, new))
PY
}

# _run TREE TEST -> runs the guard from TREE, prints its rc; output in $S/last.out
_run() {
    local t=$1 name=$2
    env MT_TEST_MOCK_CLAUDE="$MOCK" \
        MT_RECONCILE_TEST_EVIDENCE_DIR="$S/ev/$RANDOM.r" \
        MT_RECONCILE_RC_TEST_EVIDENCE_DIR="$S/ev/$RANDOM.rc" \
        MT_ARGPARSE_TEST_EVIDENCE_DIR="$S/ev/$RANDOM.a" \
        MT_PIDSTAT_TEST_EVIDENCE_DIR="$S/ev/$RANDOM.p" \
        MT_SUPWIRE_TEST_EVIDENCE_DIR="$S/ev/$RANDOM.s" \
        timeout 600 sh "$t/scripts/multitrack/test_multitrack_$name.sh" > "$S/last.out" 2>&1
    echo $?
}

O=scripts/multitrack/multitrack_alias_orchestrator.sh
SS=scripts/multitrack/multitrack_sessions.sh
HEAD_SHA=$(git -C "$CONST_ROOT" rev-parse HEAD)
PIN=e60cbde2e33e7d0542a937331763f6be7e739c9a
ABSENT=0000000000000000000000000000000000000001

# One row per guard: name, needs-mock flag, file whose FIX is mutated, the
# exact fix text, its behavioural replacement, expected occurrence count.
G_NAME=(orchestrator_reconcile orchestrator_reconcile_rc sessions_argparse sessions_pid_status supervisor_wiring)
G_MOCK=(0 0 0 1 1)
G_FILE=("$O" "$O" "$SS" "$SS" "$SS")
G_OLD=('xp=val($0,"expires")'
       'if [ "$_reconcile_awk_rc" -ne 0 ]; then'
       '                if [ $# -lt 2 ]; then'
       '    _spawn_pid=""'
       '        sh "$MTS_SUPERVISOR" snapshot >/dev/null 2>&1 || true')
G_NEW=('exp=val($0,"expires")'
       'if false; then'
       '                if false; then'
       '    _spawn_pid=$$'
       '        : supervisor snapshot removed by mutation')
G_COUNT=(1 1 2 1 1)

RAN=0
for i in "${!G_NAME[@]}"; do
    g=${G_NAME[$i]}; file=${G_FILE[$i]}; old=${G_OLD[$i]}; new=${G_NEW[$i]}; count=${G_COUNT[$i]}
    if [ "${G_MOCK[$i]}" = "1" ] && [ -z "$MOCK" ]; then
        skip "$g: all legs (the RB-05 mock claude is not reachable) reason=rb05_mock_absent"
        continue
    fi
    RAN=1

    t=$(_tree "${g}_control") || { fail "$g: scratch clone failed"; continue; }
    rc=$(_run "$t" "$g")
    if [ "$rc" = "0" ]; then pass "$g control: unmutated scratch tree exits 0"
    else fail "$g control: unmutated scratch tree exited $rc"; tail -5 "$S/last.out"; fi

    t=$(_tree "${g}_fix") || { fail "$g: scratch clone failed"; continue; }
    if ! _mutate "$t/$file" "$old" "$new" "$count"; then
        fail "$g fix mutation did not apply to $file"
    else
        # the RB-FIX2 rename also renames the two uses of the scalar
        if [ "$g" = "orchestrator_reconcile" ]; then
            _mutate "$t/$file" 'te[tr]=xp' 'te[tr]=exp' 1 && _mutate "$t/$file" 'te[t]=xp' 'te[t]=exp' 1 \
                || fail "$g fix mutation (uses of xp) did not apply"
        fi
        rc=$(_run "$t" "$g")
        if [ "$rc" != "0" ] && [ "$rc" != "77" ] && grep -q '^FAIL: GREEN' "$S/last.out"; then
            pass "$g fix removed from the current artifact: the guard goes RED (rc=$rc, $(grep -c '^FAIL: GREEN' "$S/last.out") behavioural GREEN failure(s))"
        else
            fail "$g fix removed from the current artifact but the guard did not go RED on a behaviour leg (rc=$rc)"; tail -5 "$S/last.out"
        fi
    fi

    t=$(_tree "${g}_pin") || { fail "$g: scratch clone failed"; continue; }
    if _mutate "$t/scripts/multitrack/test_multitrack_$g.sh" "RED_PIN=$PIN" "RED_PIN=$HEAD_SHA" 1; then
        rc=$(_run "$t" "$g")
        if [ "$rc" = "94" ] && grep -q 'is not the pre-fix artifact' "$S/last.out"; then
            pass "$g RED pinned back to HEAD: the guard refuses (rc=94), it can no longer pass on a HEAD-built RED"
        else
            fail "$g RED pinned back to HEAD was not refused (rc=$rc)"; tail -5 "$S/last.out"
        fi
    else
        fail "$g: RED_PIN line not found exactly once in the guard"
    fi

    t=$(_tree "${g}_absent") || { fail "$g: scratch clone failed"; continue; }
    if _mutate "$t/scripts/multitrack/test_multitrack_$g.sh" "RED_PIN=$PIN" "RED_PIN=$ABSENT" 1; then
        rc=$(_run "$t" "$g")
        if [ "$rc" = "93" ] && grep -q 'is not reachable' "$S/last.out"; then
            pass "$g RED pin missing from the clone (shallow-clone case): the guard FAILs closed (rc=93)"
        else
            fail "$g RED pin missing from the clone was not a closed failure (rc=$rc)"; tail -5 "$S/last.out"
        fi
    fi
done

echo ""
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
if [ "$RAN" = "0" ]; then
    echo "SKIP: no guard could run reason=rb05_mock_absent"
    exit 77
fi
[ "$FAIL" -eq 0 ]
