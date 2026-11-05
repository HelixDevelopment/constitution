#!/bin/sh
# =============================================================================
# test_multitrack_sessions_pid_status.sh — C2+C3 permanent regression guards:
#     no PID-reuse kill hazard (C2) + honest terminal live/finished status
#     bookkeeping (C3) for multitrack_sessions.sh. Independent-review
#     findings (RB_FOUNDATION_REVIEW_report.md):
#       C2 — `_spawn_pid=$$` recorded the WRAPPER's own pid (the synchronous
#            `-p` worker had ALREADY EXITED by that line) as if it were a
#            live, killable worker handle; `cmd_stop`'s later `kill "$_pid"`
#            could signal an ARBITRARY unrelated process once the kernel
#            recycled that exited pid (a real §11.4.133 host-safety hazard).
#       C3 — spawn-completion hardcoded `status="running"` regardless of
#            outcome and was never demoted; RB-02's `_mts_live_count` counted
#            every past, already-finished spawn as permanently "live",
#            falsely refusing a fresh re-spawn of the SAME track as
#            "pool at cap" once all MT_MAX_WORKERS tracks had been spawned
#            once (a self-inflicted permanent DoS on the spawn pool).
# -----------------------------------------------------------------------------
# Purpose (§11.4.114/§11.4.115 RED-on-the-broken-artifact + polarity switch):
#   RED_MODE=1 (default) — drives the LAST-COMMITTED (git HEAD, pre-fix)
#     copy of multitrack_sessions.sh against the RB-05 mock `claude`
#     (device-AND-account-independent, §11.4.98/§12.6/§11.4.133 -- same mock
#     as the sibling RB-05 test) and proves, on that actual pre-fix
#     artifact:
#       (C2-RED) the pid persisted to the track snapshot EQUALS the wrapper
#         subshell's OWN pid ($!) -- a process already confirmed exited by
#         the time the assertion runs (proven WITHOUT racing real kernel PID
#         reuse: the wrong SEMANTIC -- recorded_pid==wrapper_pid, not any
#         worker pid -- is what's asserted, deterministic and race-free).
#       (C3-RED) `_mts_live_count` (sourced from the SAME pre-fix copy)
#         reports 1 live worker after ONE spawn that has ALREADY completed
#         successfully -- the false "still running" count.
#   RED_MODE=0 (GREEN) — drives the CURRENT (working-tree, fixed) primitive
#     and proves:
#       (C2-GREEN-a) the persisted pid field is EMPTY (no live-pid claim for
#         a synchronously-completed spawn).
#       (C2-GREEN-b) `cmd_stop` against a snapshot carrying a LEGACY-style
#         non-empty pid that IS alive but is NOT a worker (its /proc cmdline
#         does not contain "stream-json" -- e.g. this very test's own shell)
#         declines to signal it -- a fake `kill` shim on PATH proves it was
#         NEVER invoked (the identity guard fires, covering stale pre-fix
#         registry entries + any future backgrounded-worker design).
#       (C3-GREEN) `_mts_live_count` reports 0 after a completed spawn (the
#         false-permanent-live defect is gone), and STILL correctly reports 1
#         for a snapshot directly seeded with status="running" (a genuinely
#         live entry is not silently hidden by the fix).
#   Both modes run their battery 3 times (§11.4.50 determinism).
#
# Usage:
#   RED_MODE=1 sh constitution/scripts/multitrack/test_multitrack_sessions_pid_status.sh   # RED
#   RED_MODE=0 sh constitution/scripts/multitrack/test_multitrack_sessions_pid_status.sh   # GREEN
#   (default RED_MODE=1 if unset)
#
# Inputs: RED_MODE (0|1, default 1); MT_TEST_CONST_ROOT (optional override for
#   the constitution submodule root); MT_TEST_PROJECT_ROOT (optional override
#   for the outer project root, where the RB-05 mock fixture lives);
#   MT_PIDSTAT_TEST_EVIDENCE_DIR (optional).
#
# Outputs: PASS/FAIL/SKIP lines on stdout + $EV/results.log; per-iteration
#   normalized result files under $EV. Exit 0 iff FAIL count is 0.
#
# Side-effects: creates + removes ONE scratch tmp dir (fake `claude` = the
#   RB-05 mock, fake `kill` shim, extracted pre-fix copy for RED_MODE=1
#   only); `trap ... EXIT INT TERM` cleanup on every exit path (§11.4.14);
#   writes ONLY under qa-results/ (if reachable) and the scratch dir; NEVER
#   spawns a real worker, NEVER signals a real process (the fake `kill` shim
#   intercepts every kill this test issues), NEVER touches a device.
#
# Dependencies: sh (POSIX), git, date, mktemp, diff, sed, grep, wc.
#
# Cross-references: multitrack_sessions.sh (unit under test: cmd_spawn's
#   `_spawn_pid`/terminal-status write, `_mts_live_count`, `cmd_stop`'s kill
#   guard); scripts/multitrack/rb05_fixtures/mock_claude.sh (RB-05 mock,
#   reused here by reference); qa-results/multitrack/
#   RB_FOUNDATION_REVIEW_report.md (findings C2, C3);
#   qa-results/multitrack/rbfix_20260709T104854Z/{C2,C3}_red_repro.log (this
#   fix's own captured RED evidence); §11.4.114/§11.4.115/§11.4.50/§11.4.67/
#   §11.4.133 (host-safety -- never signal an unverified pid)/§11.4.135
#   (permanent regression guard for every fixed defect).
# =============================================================================

set -u

MT_PST_SELF=$0
case "$MT_PST_SELF" in
    */*) MT_PST_DIR=${MT_PST_SELF%/*} ;;
    *)   MT_PST_DIR=. ;;
esac

_pst_const_root() {
    if [ -n "${MT_TEST_CONST_ROOT:-}" ]; then printf '%s\n' "$MT_TEST_CONST_ROOT"; return 0; fi
    ( cd "$MT_PST_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
CONST_ROOT=$(_pst_const_root)
[ -n "$CONST_ROOT" ] || { echo "FATAL: no constitution submodule root (git toplevel / \$MT_TEST_CONST_ROOT)" >&2; exit 90; }

_pst_project_root() {
    if [ -n "${MT_TEST_PROJECT_ROOT:-}" ]; then printf '%s\n' "$MT_TEST_PROJECT_ROOT"; return 0; fi
    ( cd "$CONST_ROOT/.." 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
PROJECT_ROOT=$(_pst_project_root)
[ -n "$PROJECT_ROOT" ] || { echo "SKIP topology_unsupported: no outer project root (git toplevel above constitution/ / \$MT_TEST_PROJECT_ROOT): canon is not nested in a consumer" >&2; exit 77; }

SESSIONS="$CONST_ROOT/scripts/multitrack/multitrack_sessions.sh"
MOCK="$PROJECT_ROOT/scripts/multitrack/rb05_fixtures/mock_claude.sh"
[ -f "$SESSIONS" ] || { echo "FATAL: primitive not found: $SESSIONS" >&2; exit 91; }
[ -f "$MOCK" ] || { echo "FATAL: RB-05 mock not found: $MOCK" >&2; exit 91; }
sh -n "$SESSIONS" 2>/dev/null || { echo "FATAL: primitive fails sh -n: $SESSIONS" >&2; exit 92; }

RED_MODE="${RED_MODE:-1}"
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
_pst_evidence_home() {
    printf '%s/qa-results/multitrack\n' "$PROJECT_ROOT"
}
EV="${MT_PIDSTAT_TEST_EVIDENCE_DIR:-$(_pst_evidence_home)/pidstatus_test_${RUN_TS}-$$}"
mkdir -p "$EV"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_pst_test.XXXXXX")
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

FAKEBIN="$WORK/bin"; mkdir -p "$FAKEBIN"
ln -sf "$MOCK" "$FAKEBIN/claude"
HSS="$WORK/hss.sh"
printf 'host_safe_parallel_jobs() { echo 4; }\nHOST_SAFETY_BUDGET_GB=99\n' > "$HSS"

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s (%s) [evidence: %s]\n' "$1" "$2" "$3" | tee -a "$EV/results.log"; }

# Extracted pre-fix world lives in its OWN directory (not $WORK directly) so
# multitrack_sessions.sh's sibling-resolution of MTS_BUDGET_LIB (a literal
# "multitrack_host_budget.sh" next to $0) finds a REAL (also pre-fix, git
# HEAD) budget guard rather than refusing with "guard missing" before ever
# reaching the persist step this test needs to observe.
PREFIX_DIR="$WORK/prefix"; mkdir -p "$PREFIX_DIR"
PREFIX_COPY="$PREFIX_DIR/multitrack_sessions.sh"
if [ "$RED_MODE" = "1" ]; then
    if ! git -C "$CONST_ROOT" show HEAD:scripts/multitrack/multitrack_sessions.sh > "$PREFIX_COPY" 2>/dev/null; then
        echo "FATAL: could not extract git HEAD copy of multitrack_sessions.sh from $CONST_ROOT" >&2
        exit 93
    fi
    if ! git -C "$CONST_ROOT" show HEAD:scripts/multitrack/multitrack_host_budget.sh > "$PREFIX_DIR/multitrack_host_budget.sh" 2>/dev/null; then
        echo "FATAL: could not extract git HEAD copy of multitrack_host_budget.sh from $CONST_ROOT" >&2
        exit 93
    fi
    if ! grep -qF '_spawn_pid=$$' "$PREFIX_COPY"; then
        echo "FATAL: extracted HEAD copy does not contain the expected pre-fix '_spawn_pid=\$\$' construct -- cannot honestly claim RED reproduction (§11.4.6)" >&2
        exit 94
    fi
fi

run_battery() {
    _iter="$1"
    _norm="$EV/normalized_iter${_iter}.txt"
    : > "$_norm"

    if [ "$RED_MODE" = "1" ]; then
        # --- C2-RED: recorded pid == the wrapper's OWN (now-exited) pid ----
        _reg="$WORK/red_reg_$_iter"; _cwd="$WORK/red_cwd_$_iter"; mkdir -p "$_cwd"
        MT_SESSIONS_DIR="$_reg" HOST_SAFETY_LIB="$HSS" MT_WORKER_CWD="$_cwd" \
            MOCK_CLAUDE_SESSION_ID="PST-RED-$_iter" MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_IS_ERROR=false \
            PATH="$FAKEBIN:$PATH" sh "$PREFIX_COPY" spawn redtrack >/dev/null 2>&1 &
        _wrapper_pid=$!
        wait "$_wrapper_pid" 2>/dev/null
        _recorded_pid=$(grep '"pid"' "$_reg/tracks/redtrack.json" 2>/dev/null | sed -n 's/.*"pid":"\([^"]*\)".*/\1/p')
        if [ "$_recorded_pid" = "$_wrapper_pid" ] && [ -n "$_recorded_pid" ]; then
            pass "RED(C2): pre-fix copy recorded pid=$_recorded_pid == wrapper's own \$! ($_wrapper_pid, an already-exited process) -- not any worker" "$_reg/tracks/redtrack.json"
            echo "RED_C2_RECORDED_EQUALS_WRAPPER=1" >> "$_norm"
        else
            fail "RED(C2): expected recorded pid ($_recorded_pid) == wrapper pid ($_wrapper_pid), defect not reproduced" "$_reg/tracks/redtrack.json"
            echo "RED_C2_RECORDED_EQUALS_WRAPPER=0" >> "$_norm"
        fi
        if kill -0 "$_wrapper_pid" 2>/dev/null; then
            fail "RED(C2b): wrapper pid $_wrapper_pid unexpectedly still alive after wait" "$EV"
            echo "RED_C2_WRAPPER_DEAD=0" >> "$_norm"
        else
            pass "RED(C2b): wrapper pid $_wrapper_pid confirmed DEAD -- cmd_stop's bare kill -0 check against this recorded pid is a pure PID-reuse gamble" "$EV"
            echo "RED_C2_WRAPPER_DEAD=1" >> "$_norm"
        fi

        # --- C3-RED: _mts_live_count reports 1 after ONE finished spawn ----
        _livecount=$(MT_SESSIONS_DIR="$_reg" sh -c '. "'"$PREFIX_COPY"'" 2>/dev/null; _mts_live_count' 2>/dev/null)
        if [ "$_livecount" = "1" ]; then
            pass "RED(C3): _mts_live_count==1 after ONE already-finished spawn (pre-fix defect: permanently-live status never demoted)" "$_reg"
            echo "RED_C3_LIVECOUNT=1" >> "$_norm"
        else
            fail "RED(C3): expected live_count=1 (the defect), got '$_livecount'" "$_reg"
            echo "RED_C3_LIVECOUNT=$_livecount" >> "$_norm"
        fi
        return 0
    fi

    # ---------------------------------------------------------------- GREEN ---
    # C2-GREEN-a: persisted pid field is EMPTY for a synchronous spawn.
    _reg="$WORK/g_reg_$_iter"; _cwd="$WORK/g_cwd_$_iter"; mkdir -p "$_cwd"
    MT_SESSIONS_DIR="$_reg" HOST_SAFETY_LIB="$HSS" MT_WORKER_CWD="$_cwd" \
        MOCK_CLAUDE_SESSION_ID="PST-GRN-$_iter" MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_IS_ERROR=false \
        PATH="$FAKEBIN:$PATH" sh "$SESSIONS" spawn grntrack >/dev/null 2>&1
    _grc=$?
    _pid_field=$(grep '"pid"' "$_reg/tracks/grntrack.json" 2>/dev/null | sed -n 's/.*"pid":"\([^"]*\)".*/\1/p')
    if [ "$_grc" = "0" ] && [ -z "$_pid_field" ]; then
        pass "GREEN(C2a): persisted pid field is EMPTY (no live-pid claim for a completed synchronous spawn)" "$_reg/tracks/grntrack.json"
        echo "GREEN_C2a_PID_EMPTY=1" >> "$_norm"
    else
        fail "GREEN(C2a): expected empty pid field, got '$_pid_field' (rc=$_grc)" "$_reg/tracks/grntrack.json"
        echo "GREEN_C2a_PID_EMPTY=0 pid=$_pid_field" >> "$_norm"
    fi

    # C3-GREEN-a: _mts_live_count reports 0 after the completed spawn above.
    _livecount0=$(MT_SESSIONS_DIR="$_reg" sh -c '. "'"$SESSIONS"'" 2>/dev/null; _mts_live_count' 2>/dev/null)
    if [ "$_livecount0" = "0" ]; then
        pass "GREEN(C3a): _mts_live_count==0 after a completed spawn (the false-permanent-live defect is gone)" "$_reg"
        echo "GREEN_C3a_LIVECOUNT=0" >> "$_norm"
    else
        fail "GREEN(C3a): expected live_count=0, got '$_livecount0'" "$_reg"
        echo "GREEN_C3a_LIVECOUNT=$_livecount0" >> "$_norm"
    fi

    # C3-GREEN-b: a snapshot directly seeded with status="running" is STILL
    # correctly counted as live (the fix must not hide a genuinely-live entry).
    _reg2="$WORK/g2_reg_$_iter"; mkdir -p "$_reg2/tracks"
    printf '{"track":"liveone","alias":"","session_id":"SEED","cwd":"x","config_dir":"","pid":"","status":"running","updated":"t"}\n' > "$_reg2/tracks/liveone.json"
    _livecount1=$(MT_SESSIONS_DIR="$_reg2" sh -c '. "'"$SESSIONS"'" 2>/dev/null; _mts_live_count' 2>/dev/null)
    if [ "$_livecount1" = "1" ]; then
        pass "GREEN(C3b): a genuinely status=running snapshot is STILL counted live (no over-correction)" "$_reg2"
        echo "GREEN_C3b_LIVECOUNT=1" >> "$_norm"
    else
        fail "GREEN(C3b): expected live_count=1 for a genuinely-running seed, got '$_livecount1'" "$_reg2"
        echo "GREEN_C3b_LIVECOUNT=$_livecount1" >> "$_norm"
    fi

    # C2-GREEN-b: cmd_stop declines to kill a LEGACY-style non-empty pid that
    # is ALIVE but is NOT a worker (its /proc cmdline lacks "stream-json") --
    # a fake `kill` shim on PATH proves it was NEVER invoked. Seed a snapshot
    # whose recorded pid is THIS TEST's own $$ (genuinely alive, genuinely
    # not a claude worker).
    _reg3="$WORK/g3_reg_$_iter"; mkdir -p "$_reg3/tracks"
    printf '{"track":"legacy","alias":"","session_id":"LEGACY","cwd":"x","config_dir":"","pid":"%s","status":"running","updated":"t"}\n' "$$" > "$_reg3/tracks/legacy.json"
    _killbin="$WORK/killbin_$_iter"; mkdir -p "$_killbin"
    _killlog="$WORK/kill_invoked_$_iter.log"
    : > "$_killlog"
    cat > "$_killbin/kill" <<KILLEOF
#!/bin/sh
echo "KILL-INVOKED \$*" >> "$_killlog"
exit 0
KILLEOF
    chmod +x "$_killbin/kill"
    _stop_out=$(MT_SESSIONS_DIR="$_reg3" PATH="$_killbin:$PATH" sh "$SESSIONS" stop legacy 2>&1)
    _kill_calls=$(wc -l < "$_killlog" 2>/dev/null | tr -d ' '); _kill_calls=${_kill_calls:-0}
    if [ "$_kill_calls" = "0" ] && printf '%s\n' "$_stop_out" | grep -q "PID-reuse guard"; then
        pass "GREEN(C2b): cmd_stop declined to signal a live-but-non-worker recorded pid (identity guard fired, fake kill invoked 0 times)" "$_killlog"
        echo "GREEN_C2b_KILL_DECLINED=1" >> "$_norm"
    else
        fail "GREEN(C2b): expected 0 kill invocations + identity-guard message, got $_kill_calls invocation(s): $_stop_out" "$_killlog"
        echo "GREEN_C2b_KILL_DECLINED=0 calls=$_kill_calls" >> "$_norm"
    fi
}

for _i in 1 2 3; do run_battery "$_i"; done

echo "=== §11.4.50 determinism check: normalized_iter1/2/3 byte-identical? ===" | tee -a "$EV/results.log"
if diff -q "$EV/normalized_iter1.txt" "$EV/normalized_iter2.txt" >/dev/null 2>&1 \
   && diff -q "$EV/normalized_iter2.txt" "$EV/normalized_iter3.txt" >/dev/null 2>&1; then
    pass "determinism: 3/3 iterations byte-identical (normalized, RED_MODE=$RED_MODE)" "$EV/normalized_iter1.txt"
else
    fail "determinism: iterations diverged (RED_MODE=$RED_MODE)" "$EV"
fi

echo "" | tee -a "$EV/results.log"
echo "RED_MODE=$RED_MODE  PASS=$PASS FAIL=$FAIL SKIP=$SKIP" | tee -a "$EV/results.log"
echo "Evidence: $EV"

[ "$FAIL" -eq 0 ]
