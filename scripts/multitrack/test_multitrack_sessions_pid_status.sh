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
#   RED_MODE=1 — drives the PRE-FIX copy of multitrack_sessions.sh (and its
#     sibling multitrack_host_budget.sh) extracted at the PINNED commit
#     RED_PIN (the parent of 55998fb, which introduced the fix). It is NEVER
#     `git show HEAD:`: once the fix is committed HEAD holds the FIXED copy,
#     so a HEAD-built RED can never go RED on a committed tree (redpin class,
#     §11.4.115/§11.4.292(E)); an unreachable pin FAILs closed. It runs
#     against the RB-05 mock `claude`
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
#   sh constitution/scripts/multitrack/test_multitrack_sessions_pid_status.sh              # RED then GREEN
#   RED_MODE=1 sh constitution/scripts/multitrack/test_multitrack_sessions_pid_status.sh   # RED only
#   RED_MODE=0 sh constitution/scripts/multitrack/test_multitrack_sessions_pid_status.sh   # GREEN only
#   (default RED_MODE=both if unset)
#
# Inputs: RED_MODE (both|1|0, default both); MT_TEST_CONST_ROOT (optional
#   override for the constitution submodule root); MT_TEST_PROJECT_ROOT
#   (optional override for the outer project root, where the RB-05 mock
#   fixture lives); MT_TEST_MOCK_CLAUDE (optional path to the RB-05 mock,
#   used instead of the project-root copy); MT_PIDSTAT_TEST_EVIDENCE_DIR
#   (optional).
#
# Evidence class (§11.4.289): UNIT-CLASS. Every spawn here runs through the
#   RB-05 mock `claude` and the HSS host-safety stub, which are test doubles,
#   so a verdict of this test is gate/logic evidence about the engine's code
#   paths, never live evidence that a real worker spawn works.
#
# Environment dependency (honest SKIP, §11.4.3): the RB-05 mock lives in the
#   CONSUMER project (scripts/multitrack/rb05_fixtures/mock_claude.sh), not in
#   this repository. When no mock is reachable (a standalone constitution
#   checkout with no outer project and no MT_TEST_MOCK_CLAUDE) the test exits
#   77 with "reason=rb05_mock_absent" instead of a false RED.
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

SESSIONS="$CONST_ROOT/scripts/multitrack/multitrack_sessions.sh"
[ -f "$SESSIONS" ] || { echo "FATAL: primitive not found: $SESSIONS" >&2; exit 91; }
# The RB-05 mock is a consumer-project fixture. No mock => honest SKIP (rc 77),
# decided BEFORE any evidence directory is created, never a false RED.
if [ -n "${MT_TEST_MOCK_CLAUDE:-}" ]; then
    MOCK=$MT_TEST_MOCK_CLAUDE
elif [ -n "$PROJECT_ROOT" ]; then
    MOCK="$PROJECT_ROOT/scripts/multitrack/rb05_fixtures/mock_claude.sh"
else
    MOCK=""
fi
if [ -z "$MOCK" ] || [ ! -f "$MOCK" ]; then
    echo "SKIP: the RB-05 mock claude is not reachable (no outer project root above $CONST_ROOT, no MT_TEST_MOCK_CLAUDE; looked for '${MOCK:-<none>}'); this test needs the consumer fixture scripts/multitrack/rb05_fixtures/mock_claude.sh reason=rb05_mock_absent"
    exit 77
fi
sh -n "$SESSIONS" 2>/dev/null || { echo "FATAL: primitive fails sh -n: $SESSIONS" >&2; exit 92; }

RED_MODE="${RED_MODE:-both}"
case "$RED_MODE" in
    both) PHASES="1 0" ;;
    1)    PHASES="1" ;;
    0)    PHASES="0" ;;
    *)    echo "FATAL: RED_MODE must be both, 1 or 0 (got '$RED_MODE')" >&2; exit 2 ;;
esac
REQ_MODE=$RED_MODE
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
_pst_evidence_home() {
    if [ -n "$PROJECT_ROOT" ]; then printf '%s/qa-results/multitrack\n' "$PROJECT_ROOT"; return 0; fi
    printf '%s/qa-results/multitrack\n' "$CONST_ROOT"
}
EV="${MT_PIDSTAT_TEST_EVIDENCE_DIR:-$(_pst_evidence_home)/pidstatus_test_${RUN_TS}-$$}"
mkdir -p "$EV"

# Remove $WORK through safe_rm_rf (§11.4.287(B)). scripts/lib/safe_rm.sh is
# bash-only, so it runs in a bash child; when bash or the library is missing
# nothing is removed (a leaked scratch dir, never an unguarded delete).
_rm_work() {
    [ -n "${WORK:-}" ] && [ -d "$WORK" ] || return 0
    bash -c '. "$1" && safe_rm_rf "${2:?}"' _rm_work "$CONST_ROOT/scripts/lib/safe_rm.sh" "$WORK" >/dev/null 2>&1 || true
}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_pst_test.XXXXXX")
cleanup() { _rm_work; }
trap cleanup EXIT INT TERM

FAKEBIN="$WORK/bin"; mkdir -p "$FAKEBIN"
ln -sf "$MOCK" "$FAKEBIN/claude"
HSS="$WORK/hss.sh"
printf 'host_safe_parallel_jobs() { echo 4; }\nHOST_SAFETY_BUDGET_GB=99\n' > "$HSS"
# >>CARRIER_IMMUNE (round-1 review F2, §11.4.196(D) / §11.4.201(1) / §11.4.50)
# The RED leg runs the PINNED pre-fix sibling multitrack_host_budget.sh, whose
# build and worker guards are a bare `pgrep -f` (the pre-RB-02 carrier
# footgun): any process on the host whose command line merely MENTIONS a build
# word and `claude ... --output-format stream-json` (an agent prompt, for
# example) made that guard refuse the spawn, so the RED verdict depended on
# what else was running. This test is about pid/status (resp. supervisor)
# wiring, not about the host budget (which has its own tests), so both
# patterns are set, in both modes, to a token built at run time: the joined
# value is in no command line on the host, so pgrep finds nothing and the
# verdict depends only on the artifact under test.
_mt_nomatch=$(printf 'QXZZ_%s_%s_%s' "$$" "$(date +%s%N 2>/dev/null)" nomatch)
MT_HOST_BUDGET_BUILD_PGREP_PATTERN="${_mt_nomatch}_build"
MT_HOST_BUDGET_WORKER_PGREP_PATTERN="${_mt_nomatch}_worker"
export MT_HOST_BUDGET_BUILD_PGREP_PATTERN MT_HOST_BUDGET_WORKER_PGREP_PATTERN
# <<CARRIER_IMMUNE

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
# --- RED artifact pin (§11.4.114/§11.4.115, redpin class) -------------------
# The RED artifact is the pre-fix copy at a FIXED commit, never `git show
# HEAD:` (HEAD holds the FIXED copy once the fix is committed). RED_PIN is the
# parent of 55998fb, which replaced `_spawn_pid=$$` with `_spawn_pid=""`.
# Assertions: the pin is reachable (else FAIL closed); the pinned copy has the
# pre-fix construct AND lacks the fix; the CURRENT copy has the fix and not
# the pre-fix construct (control needle).
RED_PIN=e60cbde2e33e7d0542a937331763f6be7e739c9a
RED_PATH=scripts/multitrack/multitrack_sessions.sh
PREFIX_NEEDLE='_spawn_pid=$$'
FIX_NEEDLE='_spawn_pid=""'
_cur_fix=$(grep -cF -- "$FIX_NEEDLE" "$SESSIONS"); _cur_pre=$(grep -cF -- "$PREFIX_NEEDLE" "$SESSIONS")
if [ "${_cur_fix:-0}" -ge 1 ] && [ "${_cur_pre:-0}" -eq 0 ]; then
    pass "control: the CURRENT $RED_PATH carries the fix ('$FIX_NEEDLE' x$_cur_fix) and not the pre-fix construct" "$SESSIONS"
else
    fail "control: the CURRENT $RED_PATH lost the fix (fix x${_cur_fix:-0}, pre-fix x${_cur_pre:-0})" "$SESSIONS"
fi
case " $PHASES " in *" 1 "*)
    if ! git -C "$CONST_ROOT" cat-file -e "$RED_PIN^{commit}" 2>/dev/null; then
        echo "FAIL: RED pin $RED_PIN is not reachable from $CONST_ROOT (shallow clone?) -- the RED cannot be reproduced; refusing to pass (§11.4.6)" >&2
        exit 93
    fi
    if ! git -C "$CONST_ROOT" show "$RED_PIN:$RED_PATH" > "$PREFIX_COPY" 2>/dev/null \
       || ! git -C "$CONST_ROOT" show "$RED_PIN:scripts/multitrack/multitrack_host_budget.sh" > "$PREFIX_DIR/multitrack_host_budget.sh" 2>/dev/null; then
        echo "FAIL: could not extract the pre-fix engine files at RED pin $RED_PIN from $CONST_ROOT" >&2
        exit 93
    fi
    if ! grep -qF -- "$PREFIX_NEEDLE" "$PREFIX_COPY" || grep -qF -- "$FIX_NEEDLE" "$PREFIX_COPY"; then
        echo "FAIL: the copy at RED pin $RED_PIN is not the pre-fix artifact (needs '$PREFIX_NEEDLE' and not '$FIX_NEEDLE') -- cannot honestly claim RED reproduction (§11.4.6)" >&2
        exit 94
    fi
    pass "RED pin $RED_PIN resolves and its $RED_PATH is the pre-fix artifact (has the pre-fix construct, lacks the fix)" "$PREFIX_COPY"
;; esac

# Sourcing multitrack_sessions.sh runs its `main "$@"`; with NO positional
# argument its `shift 2>/dev/null || true` is a fatal special-builtin error
# under dash (/bin/sh on this host) and the sourcing shell dies before
# `_mts_live_count` runs (measured: empty count, both copies). The C3 probes
# therefore source it with the benign argument `help` (usage, rc 0) and
# discard its output, so only the count reaches stdout.
run_battery() {
    _iter="$1"
    _norm="$EV/normalized_m${RED_MODE}_iter${_iter}.txt"
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
            pass "RED(C2): pre-fix pinned copy recorded pid=$_recorded_pid == wrapper's own \$! ($_wrapper_pid, an already-exited process) -- not any worker" "$_reg/tracks/redtrack.json"
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
        _livecount=$(MT_SESSIONS_DIR="$_reg" sh -c '. "'"$PREFIX_COPY"'" >/dev/null 2>&1; _mts_live_count' mt_pst_src help 2>/dev/null)
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
    _livecount0=$(MT_SESSIONS_DIR="$_reg" sh -c '. "'"$SESSIONS"'" >/dev/null 2>&1; _mts_live_count' mt_pst_src help 2>/dev/null)
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
    _livecount1=$(MT_SESSIONS_DIR="$_reg2" sh -c '. "'"$SESSIONS"'" >/dev/null 2>&1; _mts_live_count' mt_pst_src help 2>/dev/null)
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
