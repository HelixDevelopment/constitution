#!/usr/bin/env bash
# =============================================================================
# tests/test_no_head_red_builder_mutations.sh — paired §1.1 mutations for
#     tests/test_no_head_red_builder.sh (the redpin census guard).
# -----------------------------------------------------------------------------
# Each mutant MUST make the guard FAIL; the unmutated guard MUST pass:
#   control      the guard, unmutated, in a scratch clone            -> rc 0
#   never-match  detector that cannot see a HEAD read                -> FAIL
#                (golden-TRUE and the positive control catch it)
#   ignore-write detector that flags every HEAD read, write or not   -> FAIL
#                (golden-FALSE catches it)
#   new-builder  a NEW `git show HEAD:... > file` RED builder added to a
#                default-tier test in the scratch clone              -> FAIL
#                (the census catches it, naming the line)
#
# Usage: bash tests/test_no_head_red_builder_mutations.sh
# Exit: 0 when every mutant is killed and the control passes; 1 otherwise.
# Side-effects: one scratch directory (a shared clone), removed on exit with
#   safe_rm_rf (§11.4.287); never touches this checkout.
# Dependencies: bash, git, python3.
# =============================================================================
set -u

ROOT=$(cd "$(dirname "$0")/.." && git rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] || { echo "FATAL: not inside a git checkout"; exit 90; }
# shellcheck source=../scripts/lib/safe_rm.sh
. "$ROOT/scripts/lib/safe_rm.sh" || { echo "FATAL: cannot source safe_rm.sh"; exit 90; }

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); echo "PASS: $*"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $*"; }

S=$(mktemp -d "${TMPDIR:-/tmp}/redpin_census_mut.XXXXXX") || { echo "FATAL: mktemp failed"; exit 90; }
cleanup() { [ -n "${S:-}" ] && [ -d "$S" ] && safe_rm_rf "${S:?}"; }
trap cleanup EXIT INT TERM

T="$S/tree"
git clone -q --shared --no-checkout "$ROOT" "$T" && git -C "$T" checkout -q --detach "$(git -C "$ROOT" rev-parse HEAD)" \
    || { echo "FATAL: scratch clone failed"; exit 90; }
# test the working-tree copies (uncommitted edits included)
cp -a "$ROOT/tests/test_no_head_red_builder.sh" "$T/tests/"
cp -a "$ROOT/scripts/multitrack/." "$T/scripts/multitrack/"
cp -a "$ROOT/scripts/lib/." "$T/scripts/lib/"
G="$T/tests/test_no_head_red_builder.sh"

bash "$G" > "$S/control.out" 2>&1; rc=$?
if [ "$rc" = "0" ]; then pass "control: unmutated guard passes in the scratch clone"
else fail "control: unmutated guard exited $rc"; tail -5 "$S/control.out"; fi

REDPIN_DETECTOR_MUTANT=never-match bash "$G" > "$S/m1.out" 2>&1; rc=$?
if [ "$rc" != "0" ] && grep -q '^FAIL: detector golden-TRUE' "$S/m1.out" && grep -q '^FAIL: positive control' "$S/m1.out"; then
    pass "never-match mutant killed (rc=$rc): golden-TRUE and the positive control fail"
else fail "never-match mutant survived (rc=$rc)"; tail -5 "$S/m1.out"; fi

REDPIN_DETECTOR_MUTANT=ignore-write bash "$G" > "$S/m2.out" 2>&1; rc=$?
if [ "$rc" != "0" ] && grep -q '^FAIL: detector golden-FALSE' "$S/m2.out"; then
    pass "ignore-write mutant killed (rc=$rc): golden-FALSE fails"
else fail "ignore-write mutant survived (rc=$rc)"; tail -5 "$S/m2.out"; fi

V="$T/scripts/multitrack/test_multitrack_orchestrator_reconcile.sh"
printf '\ngit -C "$CONST_ROOT" show HEAD:scripts/multitrack/multitrack_alias_orchestrator.sh > "$WORK/redpin_mutant_copy.sh"\n' >> "$V"
bash "$G" > "$S/m3.out" 2>&1; rc=$?
if [ "$rc" != "0" ] && grep -q '^FAIL: census' "$S/m3.out" && grep -q 'builder: scripts/multitrack/test_multitrack_orchestrator_reconcile.sh:' "$S/m3.out"; then
    pass "new-builder mutant killed (rc=$rc): the census names the added line"
else fail "new-builder mutant survived (rc=$rc)"; tail -5 "$S/m3.out"; fi

echo ""
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
