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
#   new-builder  a NEW `git show <HEAD>:... > file` RED builder added to a
#                default-tier test in the scratch clone              -> FAIL
#                (the census catches it, naming the line)
#   r1-*         the eight shapes the round-1 independent review found the
#                detector blind to, adopted verbatim (§11.4.276(D)): an option
#                before the revision, the @ alias, a 1> redirect, a two-step
#                capture, a rev-parse revision, git archive | tar, a Python
#                f-string in a new test, a new UNTRACKED test        -> FAIL
#   own-file     the control run must not name the guard's own file (the
#                round-1 defect: its fixture text was flagged)
# The revision word and its @ alias are spelled at run time ($H, $AT), so this
# file never carries a builder line of its own.
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

H=$(printf 'HE%s' AD)
AT=$(printf '\100')   # the @ alias, spelled so that no line of this file reads as a builder
bash "$G" > "$S/control.out" 2>&1; rc=$?
if [ "$rc" = "0" ]; then pass "control: unmutated guard passes in the scratch clone"
else fail "control: unmutated guard exited $rc"; tail -5 "$S/control.out"; fi
if grep -q 'builder: tests/test_no_head_red_builder' "$S/control.out"; then
    fail "own-file: the census flagged the guard's own files"; grep 'builder: tests/test_no_head_red_builder' "$S/control.out"
else pass "own-file: the census does not flag the guard's own fixture text"; fi

REDPIN_DETECTOR_MUTANT=never-match bash "$G" > "$S/m1.out" 2>&1; rc=$?
if [ "$rc" != "0" ] && grep -q '^FAIL: detector golden-TRUE' "$S/m1.out" && grep -q '^FAIL: positive control' "$S/m1.out"; then
    pass "never-match mutant killed (rc=$rc): golden-TRUE and the positive control fail"
else fail "never-match mutant survived (rc=$rc)"; tail -5 "$S/m1.out"; fi

REDPIN_DETECTOR_MUTANT=ignore-write bash "$G" > "$S/m2.out" 2>&1; rc=$?
if [ "$rc" != "0" ] && grep -q '^FAIL: detector golden-FALSE' "$S/m2.out"; then
    pass "ignore-write mutant killed (rc=$rc): golden-FALSE fails"
else fail "ignore-write mutant survived (rc=$rc)"; tail -5 "$S/m2.out"; fi

VREL=scripts/multitrack/test_multitrack_orchestrator_reconcile.sh
V="$T/$VREL"; cp -a "$V" "$S/v.orig"
A=scripts/multitrack/multitrack_alias_orchestrator.sh
# leg name, then the line(s) appended to $V; the census must FAIL and name $VREL.
append_leg() {   # $1 = leg name, $2 = text to append
    cp -a "$S/v.orig" "$V"
    printf '\n%s\n' "$2" >> "$V"
    bash "$G" > "$S/$1.out" 2>&1; rc=$?
    if [ "$rc" != "0" ] && grep -q '^FAIL: census' "$S/$1.out" && grep -q "builder: $VREL:" "$S/$1.out"; then
        pass "$1 mutant killed (rc=$rc): the census names the added line"
    else fail "$1 mutant survived (rc=$rc)"; tail -5 "$S/$1.out"; fi
    cp -a "$S/v.orig" "$V"
}
append_leg new-builder "git -C \"\$CONST_ROOT\" show $H:$A > \"\$WORK/redpin_mutant_copy.sh\""
append_leg r1-option   "git -C \"\$CONST_ROOT\" show --no-textconv $H:$A > \"\$WORK/m.sh\""
append_leg r1-at-alias "git -C \"\$CONST_ROOT\" show $AT:$A > \"\$WORK/m.sh\""
append_leg r1-fd1      "git -C \"\$CONST_ROOT\" show $H:$A 1>\"\$WORK/m.sh\""
append_leg r1-two-step "_c=\$(git -C \"\$CONST_ROOT\" show $H:$A)
printf '%s\\n' \"\$_c\" > \"\$WORK/m.sh\""
append_leg r1-rev-parse "git -C \"\$CONST_ROOT\" show \"\$(git -C \"\$CONST_ROOT\" rev-parse $H)\":$A > \"\$WORK/m.sh\""
append_leg r1-archive  "git -C \"\$CONST_ROOT\" archive $H $A | tar -x -C \"\$WORK\""

# a Python f-string read in a NEW tracked python test
PYT=tests/test_redpin_pyprobe.py
printf 'import subprocess\np = "scripts/x.sh"\nout = subprocess.run(["git", "show", f"%s:{p}"], capture_output=True).stdout\n' "$H" > "$T/$PYT"
git -C "$T" add "$PYT"
bash "$G" > "$S/r1-py.out" 2>&1; rc=$?
if [ "$rc" != "0" ] && grep -q "builder: $PYT:" "$S/r1-py.out"; then pass "r1-py-fstring mutant killed (rc=$rc): the census names the new python test"
else fail "r1-py-fstring mutant survived (rc=$rc)"; tail -5 "$S/r1-py.out"; fi
git -C "$T" rm -q -f "$PYT"

# a NEW test that is not yet tracked (git add not run)
UNT=tests/test_redpin_untracked.sh
printf '#!/bin/sh\ngit show %s:scripts/x.sh > "$W/x.sh"\n' "$H" > "$T/$UNT"
bash "$G" > "$S/r1-untracked.out" 2>&1; rc=$?
if [ "$rc" != "0" ] && grep -q "builder: $UNT:" "$S/r1-untracked.out"; then pass "r1-untracked mutant killed (rc=$rc): the census scans an untracked new test"
else fail "r1-untracked mutant survived (rc=$rc)"; tail -5 "$S/r1-untracked.out"; fi
safe_rm_rf "${T:?}/${UNT:?}"

echo ""
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
