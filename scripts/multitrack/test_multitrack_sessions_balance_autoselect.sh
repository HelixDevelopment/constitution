#!/bin/sh
# =============================================================================
# test_multitrack_sessions_balance_autoselect.sh — I2 wiring regression guard:
#     proves multitrack_sessions.sh's cmd_spawn genuinely calls RB-06's
#     mt_balance_select/mark_spawn/mark_done on the REAL spawn path when the
#     caller opts in (MT_BALANCE_AUTOSELECT=1), AND that the wiring is a
#     TRUE no-op (byte-identical to pre-existing behaviour) when the caller
#     does not opt in (the default). Independent-review finding I2
#     (RB_FOUNDATION_REVIEW_report.md): mt_balance_select/mark_spawn/
#     mark_done were reachable ONLY from RB-06's own test
#     (test_multitrack_balance_reuse.sh) -- never from the real spawn path,
#     nor from any real caller (multitrack_alias_orchestrator.sh's fallback
#     path uses its OWN independent `_next_available_alias()`, entirely
#     bypassing multitrack_balance.sh). The RB-06 header's stated design
#     explicitly includes PROACTIVE (spawn-time, not just failover-time)
#     balance -- so this is a genuine "should be wired, was not" gap, not a
#     failover-only-by-design case (see the fix report's I2 determination).
#
#   Scope: native-tier routes ONLY (a bare alias name, no comma). A
#   `provider,model` route needs ccr-invocation plumbing multitrack_sessions.sh
#   does not have -- NOT wired here, honestly left as a follow-up (§11.4.6 --
#   never invented).
# -----------------------------------------------------------------------------
# Purpose:
#   (A) OPT-IN, WIRED: with MT_BALANCE_AUTOSELECT=1 and no explicit --alias/
#       MT_WORKER_ALIAS, a native operable route IS selected by
#       mt_balance_select and used as the spawn's alias; mark_spawn/mark_done
#       bracket the worker's lifetime (inflight nets back to 0 afterward).
#   (B) DEFAULT-OFF, TRUE NO-OP: with MT_BALANCE_AUTOSELECT unset (the
#       default), the alias field is exactly what it was before this wiring
#       existed (empty/ambient) -- proving zero behaviour change for every
#       existing caller (the RB-05 test suite's S1-S5 already re-verify this
#       implicitly by staying fully GREEN; this test asserts it explicitly).
#   (C) Caller-supplied --alias/MT_WORKER_ALIAS ALWAYS wins over autoselect
#       (never overridden), even with MT_BALANCE_AUTOSELECT=1.
#   Battery runs 3 times (§11.4.50 determinism).
#
# Usage:
#   sh constitution/scripts/multitrack/test_multitrack_sessions_balance_autoselect.sh
#
# Inputs: MT_TEST_CONST_ROOT, MT_TEST_PROJECT_ROOT (optional overrides, same
#   convention as the sibling test_multitrack_sessions_{argparse,pid_status}.sh).
#
# Outputs: PASS/FAIL lines on stdout + $EV/results.log. Exit 0 iff FAIL==0.
#
# Side-effects: scratch tmp dir only (fake claude=RB-05 mock, scratch
#   MT_SESSIONS_DIR + MT_BALANCE_STATE_DIR); trap cleanup on every exit path;
#   never spawns a real worker, never touches a device or credential.
#
# Dependencies: sh (POSIX), git, date, mktemp, diff, sed, grep.
#
# Cross-references: multitrack_sessions.sh (cmd_spawn's I2 opt-in balance
#   block); multitrack_balance.sh (mt_balance_select/mark_spawn/mark_done);
#   scripts/multitrack/rb05_fixtures/mock_claude.sh (reused mock);
#   qa-results/multitrack/RB_FOUNDATION_REVIEW_report.md (finding I2);
#   §11.4.124 (investigate-before-remove/wire discipline); §11.4.50; §11.4.67.
# =============================================================================

set -u

MT_BAT_SELF=$0
case "$MT_BAT_SELF" in
    */*) MT_BAT_DIR=${MT_BAT_SELF%/*} ;;
    *)   MT_BAT_DIR=. ;;
esac

_bat_const_root() {
    if [ -n "${MT_TEST_CONST_ROOT:-}" ]; then printf '%s\n' "$MT_TEST_CONST_ROOT"; return 0; fi
    ( cd "$MT_BAT_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
CONST_ROOT=$(_bat_const_root)
[ -n "$CONST_ROOT" ] || { echo "FATAL: no constitution submodule root" >&2; exit 90; }

_bat_project_root() {
    if [ -n "${MT_TEST_PROJECT_ROOT:-}" ]; then printf '%s\n' "$MT_TEST_PROJECT_ROOT"; return 0; fi
    ( cd "$CONST_ROOT/.." 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
PROJECT_ROOT=$(_bat_project_root)
[ -n "$PROJECT_ROOT" ] || { echo "SKIP: no outer project root: canon is not nested in a consumer reason=topology_unsupported"; exit 77; }

SESSIONS="$CONST_ROOT/scripts/multitrack/multitrack_sessions.sh"
BALANCE="$CONST_ROOT/scripts/multitrack/multitrack_balance.sh"
MOCK="$PROJECT_ROOT/scripts/multitrack/rb05_fixtures/mock_claude.sh"
[ -f "$SESSIONS" ] || { echo "FATAL: primitive not found: $SESSIONS" >&2; exit 91; }
[ -f "$BALANCE" ] || { echo "FATAL: balance lib not found: $BALANCE" >&2; exit 91; }
[ -f "$MOCK" ] || { echo "FATAL: RB-05 mock not found: $MOCK" >&2; exit 91; }
sh -n "$SESSIONS" 2>/dev/null || { echo "FATAL: primitive fails sh -n" >&2; exit 92; }
sh -n "$BALANCE" 2>/dev/null || { echo "FATAL: balance lib fails sh -n" >&2; exit 92; }
grep -qF 'MT_BALANCE_AUTOSELECT' "$SESSIONS" || { echo "FATAL: I2 wiring not present in $SESSIONS" >&2; exit 95; }

RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
EV="${MT_BAT_TEST_EVIDENCE_DIR:-$PROJECT_ROOT/qa-results/multitrack/balance_autoselect_test_${RUN_TS}-$$}"
mkdir -p "$EV"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_bat_test.XXXXXX")
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

FAKEBIN="$WORK/bin"; mkdir -p "$FAKEBIN"
ln -sf "$MOCK" "$FAKEBIN/claude"
HSS="$WORK/hss.sh"
printf 'host_safe_parallel_jobs() { echo 4; }\nHOST_SAFETY_BUDGET_GB=99\n' > "$HSS"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }

run_battery() {
    _iter="$1"
    _norm="$EV/normalized_iter${_iter}.txt"
    : > "$_norm"

    # (A) opt-in + wired: autoselect picks the ONLY operable native route.
    _reg="$WORK/a_reg_$_iter"; _cwd="$WORK/a_cwd_$_iter"; _bal="$WORK/a_bal_$_iter"; mkdir -p "$_cwd"
    MT_SESSIONS_DIR="$_reg" HOST_SAFETY_LIB="$HSS" MT_WORKER_CWD="$_cwd" \
        MT_BALANCE_AUTOSELECT=1 MT_BALANCE_STATE_DIR="$_bal" MT_BALANCE_OPERABLE="claude9" \
        MOCK_CLAUDE_SESSION_ID="BAT-A-$_iter" MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_IS_ERROR=false \
        PATH="$FAKEBIN:$PATH" sh "$SESSIONS" spawn atrack >/dev/null 2>&1
    _arc=$?
    _alias_field=$(grep '"alias"' "$_reg/tracks/atrack.json" 2>/dev/null | sed -n 's/.*"alias":"\([^"]*\)".*/\1/p')
    if [ "$_arc" = "0" ] && [ "$_alias_field" = "claude9" ]; then
        pass "A: MT_BALANCE_AUTOSELECT=1 -> mt_balance_select picked 'claude9' and cmd_spawn used it as the alias" "$_reg/tracks/atrack.json"
        echo "A_ALIAS=claude9" >> "$_norm"
    else
        fail "A: expected alias=claude9 rc=0, got alias='$_alias_field' rc=$_arc" "$_reg/tracks/atrack.json"
        echo "A_ALIAS=$_alias_field rc=$_arc" >> "$_norm"
    fi
    _inflight=$(grep '"inflight"' "$_bal/routes/claude9.json" 2>/dev/null | sed -n 's/.*"inflight":\([0-9]*\).*/\1/p')
    if [ "$_inflight" = "0" ]; then
        pass "A: mark_spawn/mark_done bracket nets inflight back to 0 after the (synchronous) worker completes" "$_bal/routes/claude9.json"
        echo "A_INFLIGHT=0" >> "$_norm"
    else
        fail "A: expected inflight=0 after completion, got '$_inflight'" "$_bal/routes/claude9.json"
        echo "A_INFLIGHT=$_inflight" >> "$_norm"
    fi

    # (B) default-off: MT_BALANCE_AUTOSELECT unset -> alias stays ambient/empty
    # (byte-identical to pre-wiring behaviour).
    _regb="$WORK/b_reg_$_iter"; _cwdb="$WORK/b_cwd_$_iter"; mkdir -p "$_cwdb"
    MT_SESSIONS_DIR="$_regb" HOST_SAFETY_LIB="$HSS" MT_WORKER_CWD="$_cwdb" \
        MT_BALANCE_STATE_DIR="$WORK/b_bal_$_iter" MT_BALANCE_OPERABLE="claude9" \
        MOCK_CLAUDE_SESSION_ID="BAT-B-$_iter" MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_IS_ERROR=false \
        PATH="$FAKEBIN:$PATH" sh "$SESSIONS" spawn btrack >/dev/null 2>&1
    _brc=$?
    _alias_fieldb=$(grep '"alias"' "$_regb/tracks/btrack.json" 2>/dev/null | sed -n 's/.*"alias":"\([^"]*\)".*/\1/p')
    if [ "$_brc" = "0" ] && [ -z "$_alias_fieldb" ]; then
        pass "B: MT_BALANCE_AUTOSELECT unset (default) -> alias stays empty/ambient (true no-op, unregressed)" "$_regb/tracks/btrack.json"
        echo "B_ALIAS_EMPTY=1" >> "$_norm"
    else
        fail "B: expected empty alias with autoselect unset, got '$_alias_fieldb' rc=$_brc" "$_regb/tracks/btrack.json"
        echo "B_ALIAS_EMPTY=0 alias=$_alias_fieldb" >> "$_norm"
    fi

    # (C) explicit --alias always wins over autoselect, even with it enabled.
    _regc="$WORK/c_reg_$_iter"; _cwdc="$WORK/c_cwd_$_iter"; mkdir -p "$_cwdc"
    MT_SESSIONS_DIR="$_regc" HOST_SAFETY_LIB="$HSS" MT_WORKER_CWD="$_cwdc" \
        MT_BALANCE_AUTOSELECT=1 MT_BALANCE_STATE_DIR="$WORK/c_bal_$_iter" MT_BALANCE_OPERABLE="claude9" \
        MOCK_CLAUDE_SESSION_ID="BAT-C-$_iter" MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_IS_ERROR=false \
        PATH="$FAKEBIN:$PATH" sh "$SESSIONS" spawn ctrack --alias explicit-alias >/dev/null 2>&1
    _crc=$?
    _alias_fieldc=$(grep '"alias"' "$_regc/tracks/ctrack.json" 2>/dev/null | sed -n 's/.*"alias":"\([^"]*\)".*/\1/p')
    if [ "$_crc" = "0" ] && [ "$_alias_fieldc" = "explicit-alias" ]; then
        pass "C: caller-supplied --alias ALWAYS wins over autoselect (never silently overridden)" "$_regc/tracks/ctrack.json"
        echo "C_ALIAS=explicit-alias" >> "$_norm"
    else
        fail "C: expected explicit --alias to win, got '$_alias_fieldc' rc=$_crc" "$_regc/tracks/ctrack.json"
        echo "C_ALIAS=$_alias_fieldc rc=$_crc" >> "$_norm"
    fi
}

for _i in 1 2 3; do run_battery "$_i"; done

echo "=== §11.4.50 determinism check ===" | tee -a "$EV/results.log"
if diff -q "$EV/normalized_iter1.txt" "$EV/normalized_iter2.txt" >/dev/null 2>&1 \
   && diff -q "$EV/normalized_iter2.txt" "$EV/normalized_iter3.txt" >/dev/null 2>&1; then
    pass "determinism: 3/3 iterations byte-identical" "$EV/normalized_iter1.txt"
else
    fail "determinism: iterations diverged" "$EV"
fi

echo "" | tee -a "$EV/results.log"
echo "PASS=$PASS FAIL=$FAIL" | tee -a "$EV/results.log"
echo "Evidence: $EV"

[ "$FAIL" -eq 0 ]
