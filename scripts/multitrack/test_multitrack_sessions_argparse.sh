#!/bin/sh
# =============================================================================
# test_multitrack_sessions_argparse.sh — C1 permanent regression guard:
#     bounded arg-parsing for multitrack_sessions.sh's cmd_spawn/cmd_resume
#     value-taking flags (--cwd/--config-dir/--alias). Independent-review
#     finding C1 (RB_FOUNDATION_REVIEW_report.md): a value-taking flag given
#     as the LAST CLI token (no following value) made `shift 2` a no-op
#     (POSIX/bash: `shift N` with N > $# does NOT shift), so `$1` never
#     changed and `while [ $# -gt 0 ]` spun forever — a genuine unbounded
#     busy-loop DoS (verified: bash spins silently forever; POSIX sh floods
#     stderr with "shift count out of range" at ~5.7MB/s).
# -----------------------------------------------------------------------------
# Purpose (§11.4.114/§11.4.115 RED-on-the-broken-artifact + polarity switch):
#   RED_MODE=1 — reproduces the defect against the PRE-FIX copy of
#     multitrack_sessions.sh extracted at the PINNED commit RED_PIN (the parent
#     of 55998fb, which introduced the "missing value" guard), NOT a synthetic
#     snippet — the actual artifact this fix replaced. It is NEVER `git show
#     HEAD:`: once the fix is committed HEAD holds the FIXED copy, so a
#     HEAD-built RED can never go RED on a committed tree (redpin class,
#     §11.4.115/§11.4.292(E)); an unreachable pin FAILs closed. Drives `spawn sometrack --cwd` (dangling flag, no
#     value) under a bounded `timeout` (this test itself NEVER lets a hung
#     child run unbounded, §12 host-safety) and asserts the pre-fix copy IS
#     killed by the timeout (exit 124) — proving the loop is real, not
#     theoretical, on the exact code this PWU replaces.
#   RED_MODE=0 (GREEN) — drives the CURRENT (working-tree, fixed) primitive
#     with the SAME dangling-flag input (both `spawn` and `resume`, both
#     bash and POSIX sh per §11.4.67) and asserts BOUNDED behaviour: a clean
#     "missing value" error + non-zero exit, well inside the timeout
#     (NEVER 124), with a well-formed value still accepted normally
#     (negative-control — the fix must not break the happy path).
#   Both modes run their battery 3 times (§11.4.50 determinism) and assert
#   the normalized results are byte-identical across all 3 iterations.
#
# Usage:
#   sh constitution/scripts/multitrack/test_multitrack_sessions_argparse.sh              # RED then GREEN
#   RED_MODE=1 sh constitution/scripts/multitrack/test_multitrack_sessions_argparse.sh   # RED only
#   RED_MODE=0 sh constitution/scripts/multitrack/test_multitrack_sessions_argparse.sh   # GREEN only
#   (default RED_MODE=both if unset: one default-tier run proves the defect on
#   the pinned pre-fix copy AND the fix on the current copy)
#
# Inputs: RED_MODE (both|1|0, default both); MT_TEST_CONST_ROOT (optional override for
#   the constitution submodule root, else `git rev-parse --show-toplevel`
#   from this file's own directory); MT_ARGPARSE_TEST_EVIDENCE_DIR (optional).
#
# Outputs: PASS/FAIL/SKIP lines on stdout + $EV/results.log; per-iteration
#   normalized result files under $EV. Exit 0 iff FAIL count is 0.
#
# Side-effects: creates + removes ONE scratch tmp dir (extracted pre-fix
#   copy of multitrack_sessions.sh for RED_MODE=1 only); `trap ... EXIT INT
#   TERM` cleanup on every exit path (§11.4.14); writes ONLY under
#   qa-results/ (in the PROJECT root, if reachable) and the scratch dir;
#   NEVER spawns a real worker, NEVER touches a device or credential; every
#   bounded process is killed by `timeout` well inside a few seconds.
#
# Dependencies: sh (POSIX), bash, git, timeout, date, mktemp, diff, wc.
#
# Cross-references: multitrack_sessions.sh (unit under test, cmd_spawn +
#   cmd_resume arg loops); qa-results/multitrack/RB_FOUNDATION_REVIEW_report.md
#   (finding C1); qa-results/multitrack/rbfix_20260709T104854Z/C1_red_repro.log
#   (this fix's own captured RED evidence); §11.4.114 (known-good/known-bad
#   diff oracle); §11.4.115 (RED-on-broken-artifact + polarity switch);
#   §11.4.50 (determinism); §11.4.67 (sh-parseable); §11.4.135 (permanent
#   regression guard for every fixed defect).
# =============================================================================

set -u

MT_ARGT_SELF=$0
case "$MT_ARGT_SELF" in
    */*) MT_ARGT_DIR=${MT_ARGT_SELF%/*} ;;
    *)   MT_ARGT_DIR=. ;;
esac

_argt_const_root() {
    if [ -n "${MT_TEST_CONST_ROOT:-}" ]; then printf '%s\n' "$MT_TEST_CONST_ROOT"; return 0; fi
    ( cd "$MT_ARGT_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
CONST_ROOT=$(_argt_const_root)
[ -n "$CONST_ROOT" ] || { echo "FATAL: no constitution submodule root (git toplevel / \$MT_TEST_CONST_ROOT)" >&2; exit 90; }

SESSIONS="$CONST_ROOT/scripts/multitrack/multitrack_sessions.sh"
[ -f "$SESSIONS" ] || { echo "FATAL: primitive not found: $SESSIONS" >&2; exit 91; }
sh -n "$SESSIONS" 2>/dev/null || { echo "FATAL: primitive fails sh -n: $SESSIONS" >&2; exit 92; }
bash -n "$SESSIONS" 2>/dev/null || { echo "FATAL: primitive fails bash -n: $SESSIONS" >&2; exit 92; }

RED_MODE="${RED_MODE:-both}"
case "$RED_MODE" in
    both) PHASES="1 0" ;;
    1)    PHASES="1" ;;
    0)    PHASES="0" ;;
    *)    echo "FATAL: RED_MODE must be both, 1 or 0 (got '$RED_MODE')" >&2; exit 2 ;;
esac
REQ_MODE=$RED_MODE
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
# best-effort project-root qa-results/ home; falls back to a scratch dir if
# this checkout is not embedded under a project with qa-results/ (the
# constitution submodule is designed to be usable standalone, §11.4.28).
_argt_evidence_home() {
    _ph=$(cd "$CONST_ROOT/.." 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$_ph" ] && [ -d "$_ph" ]; then printf '%s/qa-results/multitrack\n' "$_ph"; return 0; fi
    printf '%s/qa-results/multitrack\n' "$CONST_ROOT"
}
EV="${MT_ARGPARSE_TEST_EVIDENCE_DIR:-$(_argt_evidence_home)/argparse_test_${RUN_TS}-$$}"
mkdir -p "$EV"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_argt_test.XXXXXX")
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s (%s) [evidence: %s]\n' "$1" "$2" "$3" | tee -a "$EV/results.log"; }

# --- RED artifact pin (§11.4.114/§11.4.115, redpin class) -------------------
# The RED artifact is the pre-fix copy at a FIXED commit, never `git show
# HEAD:` (HEAD holds the FIXED copy once the fix is committed; the old
# 'shift 2' sanity check could not tell the two apart, because the fixed copy
# still uses 'shift 2' behind its guard). RED_PIN is the parent of 55998fb,
# which introduced the "missing value" guard. Assertions: the pin is reachable
# (else FAIL closed); the pinned copy has the unguarded 'shift 2' loop AND no
# "missing value" guard; the CURRENT copy has the guard (control needle).
RED_PIN=e60cbde2e33e7d0542a937331763f6be7e739c9a
RED_PATH=scripts/multitrack/multitrack_sessions.sh
PREFIX_NEEDLE='shift 2'
FIX_NEEDLE='missing value for'
_cur_fix=$(grep -cF -- "$FIX_NEEDLE" "$SESSIONS")
if [ "${_cur_fix:-0}" -ge 1 ]; then
    pass "control: the CURRENT $RED_PATH carries the fix ('$FIX_NEEDLE' x$_cur_fix)" "$SESSIONS"
else
    fail "control: the CURRENT $RED_PATH lost the fix ('$FIX_NEEDLE' x${_cur_fix:-0})" "$SESSIONS"
fi
PREFIX_COPY="$WORK/multitrack_sessions_prefix.sh"
case " $PHASES " in *" 1 "*)
    if ! git -C "$CONST_ROOT" cat-file -e "$RED_PIN^{commit}" 2>/dev/null; then
        echo "FAIL: RED pin $RED_PIN is not reachable from $CONST_ROOT (shallow clone?) -- the RED cannot be reproduced; refusing to pass (§11.4.6)" >&2
        exit 93
    fi
    if ! git -C "$CONST_ROOT" show "$RED_PIN:$RED_PATH" > "$PREFIX_COPY" 2>/dev/null; then
        echo "FAIL: could not extract $RED_PATH at RED pin $RED_PIN from $CONST_ROOT" >&2
        exit 93
    fi
    if ! grep -qF -- "$PREFIX_NEEDLE" "$PREFIX_COPY" || grep -qF -- "$FIX_NEEDLE" "$PREFIX_COPY"; then
        echo "FAIL: the copy at RED pin $RED_PIN is not the pre-fix artifact (needs '$PREFIX_NEEDLE' and not '$FIX_NEEDLE') -- cannot honestly claim RED reproduction (§11.4.6)" >&2
        exit 94
    fi
    pass "RED pin $RED_PIN resolves and its $RED_PATH is the pre-fix artifact (has the pre-fix construct, lacks the fix)" "$PREFIX_COPY"
;; esac

# _shift_survives SHELL -> "yes" when a failed over-count `shift` lets SHELL
# carry on (bash), "no" when it aborts the shell (dash). Probed, not assumed.
_shift_survives() {
    if [ "$("$1" -c 'set -- a; shift 2 2>/dev/null; echo survived' 2>/dev/null)" = "survived" ]; then
        echo yes
    else
        echo no
    fi
}

run_battery() {
    _iter="$1"
    _norm="$EV/normalized_m${RED_MODE}_iter${_iter}.txt"
    : > "$_norm"

    if [ "$RED_MODE" = "1" ]; then
        # RED: the pre-fix pinned copy's cmd_spawn arg loop has no guard for a
        # dangling --cwd (no value) -- bounded by `timeout` (this test's own
        # host-safety guard). Both shells. What an over-count `shift 2` does
        # is SHELL-dependent (probed once, below, never assumed): a shell that
        # survives a failed shift (bash) leaves $1 unchanged and spins
        # forever (rc=124); a shell whose failed shift is a fatal
        # special-builtin error (dash as /bin/sh) aborts with rc!=0 and a
        # "shift" diagnostic. Both are the pre-fix defect (no "missing value"
        # guard); only the first is the unbounded loop.
        for _shell in sh bash; do
            _t0=$(date +%s%N 2>/dev/null || date +%s)
            timeout 2 "$_shell" "$PREFIX_COPY" spawn redtrack --cwd \
                > "$WORK/red_${_shell}_${_iter}.out" 2> "$WORK/red_${_shell}_${_iter}.err"
            _rc=$?
            _bytes=$(wc -c < "$WORK/red_${_shell}_${_iter}.err" 2>/dev/null | tr -d ' ')
            if [ "$(_shift_survives "$_shell")" = "no" ]; then
                if [ "$_rc" != "0" ] && [ "$_rc" != "124" ] \
                   && grep -q 'shift' "$WORK/red_${_shell}_${_iter}.err" 2>/dev/null \
                   && ! grep -qi 'missing value' "$WORK/red_${_shell}_${_iter}.err" 2>/dev/null; then
                    pass "RED($_shell): this $_shell aborts on a failed shift, so the pre-fix pinned copy dies on the dangling --cwd with a raw shift error (rc=$_rc) and no 'missing value' guard -- the unguarded loop, as this shell exposes it" "$WORK/red_${_shell}_${_iter}.err"
                    echo "RED_${_shell}_SHIFT_FATAL_NO_GUARD" >> "$_norm"
                else
                    fail "RED($_shell): expected a raw shift abort without a 'missing value' guard from the pre-fix copy, got rc=$_rc (bytes=$_bytes) -- defect not reproduced" "$WORK/red_${_shell}_${_iter}.err"
                    echo "RED_${_shell}_RC=$_rc bytes=$_bytes" >> "$_norm"
                fi
                continue
            fi
            if [ "$_rc" = "124" ]; then
                pass "RED($_shell): pre-fix pinned copy's dangling --cwd loops UNBOUNDED, killed by timeout (rc=124, stderr_bytes=$_bytes)" "$WORK/red_${_shell}_${_iter}.err"
                # NOTE: stderr byte-count is CPU-speed-dependent (not part of
                # the normalized/determinism-compared line) -- the qualitative
                # rc=124 timeout-kill verdict is what §11.4.50 compares.
                echo "RED_${_shell}_RC=124_TIMEOUT_KILLED" >> "$_norm"
            else
                fail "RED($_shell): expected the pre-fix copy to be timeout-killed (rc=124), got rc=$_rc (bytes=$_bytes) -- defect not reproduced" "$WORK/red_${_shell}_${_iter}.err"
                echo "RED_${_shell}_RC=$_rc bytes=$_bytes" >> "$_norm"
            fi
        done
        return 0
    fi

    # ---------------------------------------------------------------- GREEN ---
    # G1/G2: spawn + resume with a DANGLING value-taking flag (no value) MUST
    # error cleanly + bounded (never 124), under BOTH shells.
    for _shell in sh bash; do
        for _cmd_args in "spawn redtrack --cwd" "spawn redtrack --config-dir" "spawn redtrack --alias" "resume RB-SOME-ID --cwd" "resume RB-SOME-ID --config-dir"; do
            _tag=$(printf '%s' "$_cmd_args" | tr ' /' '__')
            timeout 2 "$_shell" "$SESSIONS" $_cmd_args \
                > "$WORK/g_${_shell}_${_tag}_${_iter}.out" 2> "$WORK/g_${_shell}_${_tag}_${_iter}.err"
            _rc=$?
            if [ "$_rc" != "0" ] && [ "$_rc" != "124" ] && grep -qi "missing value" "$WORK/g_${_shell}_${_tag}_${_iter}.err" 2>/dev/null; then
                pass "GREEN($_shell,$_cmd_args): dangling flag errors cleanly + bounded (rc=$_rc, never 124)" "$WORK/g_${_shell}_${_tag}_${_iter}.err"
                echo "GREEN_${_shell}_${_tag}=clean_error rc=$_rc" >> "$_norm"
            else
                fail "GREEN($_shell,$_cmd_args): expected a bounded clean 'missing value' error, got rc=$_rc" "$WORK/g_${_shell}_${_tag}_${_iter}.err"
                echo "GREEN_${_shell}_${_tag}=UNEXPECTED rc=$_rc" >> "$_norm"
            fi
        done
    done

    # G3 negative control: a WELL-FORMED --cwd (with a value) is still parsed
    # normally (the fix must not regress the happy path) -- proven by the
    # arg loop consuming the flag+value pair and proceeding all the way past
    # arg-parsing (rc=2, "missing value") AND past the RB-02 budget guard
    # (rc=4, lib unavailable) into the actual worker-launch attempt, which
    # then fails LATER for an UNRELATED reason (the given cwd does not exist
    # -> the worker subshell's `cd` fails -> "no session_id captured", rc=6)
    # -- empirically verified (not guessed, §11.4.6):
    # qa-results/multitrack/rbfix_20260709T104854Z/ manual verification run.
    # MT_REPO_ROOT is pinned to the outer project so the RB-02 budget guard
    # resolves its host-safety lib and does not itself short-circuit at rc=4
    # before argparse's happy path can be observed reaching the worker stage.
    _g3_repo_root=$(cd "$CONST_ROOT/.." 2>/dev/null && pwd)
    for _shell in sh bash; do
        MT_REPO_ROOT="$_g3_repo_root" timeout 2 "$_shell" "$SESSIONS" spawn redtrack --cwd /nonexistent/dir/for/argparse/test \
            > "$WORK/g3_${_shell}_${_iter}.out" 2> "$WORK/g3_${_shell}_${_iter}.err"
        _rc3=$?
        if [ "$_rc3" != "2" ] && [ "$_rc3" != "124" ] && ! grep -qi "missing value" "$WORK/g3_${_shell}_${_iter}.err" 2>/dev/null; then
            pass "GREEN(G3,$_shell): well-formed --cwd VALUE consumed correctly (rc=$_rc3, reached worker-launch stage, NOT a parse error -- happy path unregressed)" "$WORK/g3_${_shell}_${_iter}.err"
            echo "GREEN_G3_${_shell}=happy_path_ok rc=$_rc3" >> "$_norm"
        else
            fail "GREEN(G3,$_shell): well-formed --cwd VALUE mis-parsed (rc=$_rc3)" "$WORK/g3_${_shell}_${_iter}.err"
            echo "GREEN_G3_${_shell}=REGRESSION rc=$_rc3" >> "$_norm"
        fi
    done
}

for RED_MODE in $PHASES; do
    for _i in 1 2 3; do run_battery "$_i"; done

    echo "=== §11.4.50 determinism check (RED_MODE=$RED_MODE): normalized iter1/2/3 byte-identical? ===" | tee -a "$EV/results.log"
    if diff -q "$EV/normalized_m${RED_MODE}_iter1.txt" "$EV/normalized_m${RED_MODE}_iter2.txt" >/dev/null 2>&1 \
       && diff -q "$EV/normalized_m${RED_MODE}_iter2.txt" "$EV/normalized_m${RED_MODE}_iter3.txt" >/dev/null 2>&1; then
        pass "determinism: 3/3 iterations byte-identical (normalized, RED_MODE=$RED_MODE)" "$EV/normalized_m${RED_MODE}_iter1.txt"
    else
        fail "determinism: iterations diverged (RED_MODE=$RED_MODE)" "$EV"
    fi
done

echo "" | tee -a "$EV/results.log"
echo "RED_MODE=$REQ_MODE  PASS=$PASS FAIL=$FAIL SKIP=$SKIP" | tee -a "$EV/results.log"
echo "Evidence: $EV"

[ "$FAIL" -eq 0 ]
