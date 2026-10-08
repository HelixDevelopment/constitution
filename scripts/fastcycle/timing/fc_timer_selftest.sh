#!/bin/bash
# fc_timer_selftest.sh - standalone self-test for fc_timer.sh (spec 004-fast-dev-cycles,
#                        plan.md T-A01/T-A02, tasks.md T028).
#
# Purpose: prove fc_timer.sh's OWN behaviour is correct in isolation from any real caller
#          (pre_build_verification.sh, commit_all.sh) -- independent of whether either of
#          those has been wired to it yet (T029/T030, separate later tasks). Every assertion
#          below runs REAL fc_timer.sh code (sourced, or via a real `bash -c`/`bash <file>`
#          subprocess for the scenarios that need their own process -- FC_TIMING toggling,
#          strict `set -euo pipefail` compatibility, direct-execution refusal, missing-
#          FC_TIMER_TSV fail-closed behaviour) -- nothing here is mocked or hand-simulated.
#
# Producer!=Verifier (S11.4.240): this file is the implementer's own self-test for the
#          library it ships alongside (T028); it is NOT a substitute for the separate,
#          already-authored, read-only RED tests test_fc_timer_prebuild_red.sh /
#          test_fc_timer_golden_output.sh, which this task does not modify.
#
# Usage: bash fc_timer_selftest.sh
#        Exit 0 = every assertion passed. Exit 1 = at least one FAIL. Exit 2 = fc_timer.sh not
#        found (cannot even attempt the self-test).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# FC_TIMER_SELFTEST_LIB: run this SAME selftest against a mutated copy of the library
# (fc_timer_selftest_mutations.sh, the paired §1.1 mutation runner). Defaults to the real file.
FC_TIMER="${FC_TIMER_SELFTEST_LIB:-$HERE/fc_timer.sh}"
ROOT="$(cd "$HERE/../../../.." && pwd)"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

FAIL=0; N=0; SKIPPED=0
chk() { N=$((N + 1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL + 1)); fi; }
skip() { N=$((N + 1)); SKIPPED=$((SKIPPED + 1)); echo "SKIP[$N]: $1"; }

[ -f "$FC_TIMER" ] || { echo "FATAL: fc_timer.sh not found at $FC_TIMER"; exit 2; }

# ============================================================================
# GROUP 0 -- sanity / control needle: prove the instrument (this test's own sourcing +
# subprocess-scripting mechanism) genuinely works before trusting any assertion built on it.
# ============================================================================
chk "fc_timer.sh parses cleanly (bash -n)" "$(bash -n "$FC_TIMER" >/dev/null 2>&1 && echo 1 || echo 0)"

# ============================================================================
# GROUP 1 -- in-process behaviour (this selftest sources fc_timer.sh directly; `set -u` only,
# deliberately NOT `set -e`, so a nonzero return from a library call can be inspected below
# instead of aborting this whole selftest -- Group 5 separately proves strict-mode compat).
# ============================================================================
TSV1="$TMP/g1.tsv"
export FC_TIMER_TSV="$TSV1"
export FC_TIMER_RUN_ID="selftest-run-fixed-id"
export FC_TIMER_CANDIDATE_FINGERPRINT="selftest-fixed-fingerprint"
# shellcheck source=/dev/null
source "$FC_TIMER"

chk "sourcing fc_timer.sh defines fc_timer_start as a function" "$(declare -F fc_timer_start >/dev/null 2>&1 && echo 1 || echo 0)"
chk "fc_timer_enabled is true by default (FC_TIMING unset)" "$(fc_timer_enabled && echo 1 || echo 0)"

RUN_ID_1="$(fc_timer_run_id)"
RUN_ID_2="$(fc_timer_run_id)"
chk "fc_timer_run_id is stable across repeated calls in one process ('$RUN_ID_1')" "$([ "$RUN_ID_1" = "$RUN_ID_2" ] && [ -n "$RUN_ID_1" ] && echo 1 || echo 0)"
chk "FC_TIMER_RUN_ID env override is honoured verbatim" "$([ "$RUN_ID_1" = "selftest-run-fixed-id" ] && echo 1 || echo 0)"

REAL_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "")"
FP_1="$(fc_timer_candidate_fingerprint)"
chk "FC_TIMER_CANDIDATE_FINGERPRINT env override is honoured verbatim (real HEAD is '$REAL_HEAD', override used instead)" "$([ "$FP_1" = "selftest-fixed-fingerprint" ] && echo 1 || echo 0)"

# --- single start/end: exactly one row, correct header, correct column count ---
fc_timer_start "T028-selftest-section-A"
fc_timer_end
chk "single start/end wrote exactly one row" "$([ "$(tail -n +2 "$TSV1" | grep -c .)" -eq 1 ] && echo 1 || echo 0)"
HEADER="$(head -n1 "$TSV1")"
chk "TSV header has the documented 11 columns in order" "$([ "$HEADER" = "$(printf 'run_id\tcandidate_fingerprint\tid\tstart_ns\tend_ns\tduration_ms\tverdict\tchecks\tfails\twarns\textra')" ] && echo 1 || echo 0)"
ROW1="$(tail -n1 "$TSV1")"
COLS=$(awk -F'\t' '{print NF}' <<<"$ROW1")
chk "row 1 has 11 tab-separated fields ($COLS found)" "$([ "$COLS" -eq 11 ] && echo 1 || echo 0)"
chk "row 1's run_id column matches the fixed override" "$([ "$(awk -F'\t' '{print $1}' <<<"$ROW1")" = "selftest-run-fixed-id" ] && echo 1 || echo 0)"
chk "row 1's candidate_fingerprint column matches the fixed override" "$([ "$(awk -F'\t' '{print $2}' <<<"$ROW1")" = "selftest-fixed-fingerprint" ] && echo 1 || echo 0)"
chk "row 1's id column matches the started section id" "$([ "$(awk -F'\t' '{print $3}' <<<"$ROW1")" = "T028-selftest-section-A" ] && echo 1 || echo 0)"
chk "row 1's default verdict is PASS with no counters tracked" "$([ "$(awk -F'\t' '{print $7}' <<<"$ROW1")" = "PASS" ] && echo 1 || echo 0)"
chk "fc_timer_rows_written reports 1 after one completed section" "$([ "$(fc_timer_rows_written)" -eq 1 ] && echo 1 || echo 0)"

# --- verdict derivation from explicit --checks/--fails/--warns ---
fc_timer_start "verdict-pass"
fc_timer_end --checks 5 --fails 0 --warns 0
V_PASS="$(awk -F'\t' '{print $7}' <(tail -n1 "$TSV1"))"
chk "explicit fails=0 warns=0 -> verdict PASS" "$([ "$V_PASS" = "PASS" ] && echo 1 || echo 0)"

fc_timer_start "verdict-warn"
fc_timer_end --checks 5 --fails 0 --warns 2
V_WARN="$(awk -F'\t' '{print $7}' <(tail -n1 "$TSV1"))"
chk "explicit fails=0 warns=2 -> verdict WARN" "$([ "$V_WARN" = "WARN" ] && echo 1 || echo 0)"

fc_timer_start "verdict-fail"
fc_timer_end --checks 5 --fails 1 --warns 2
V_FAIL="$(awk -F'\t' '{print $7}' <(tail -n1 "$TSV1"))"
chk "explicit fails=1 warns=2 -> verdict FAIL (fails wins over warns)" "$([ "$V_FAIL" = "FAIL" ] && echo 1 || echo 0)"

CHK_COL="$(awk -F'\t' '{print $8}' <(tail -n1 "$TSV1"))"
FAIL_COL="$(awk -F'\t' '{print $9}' <(tail -n1 "$TSV1"))"
WARN_COL="$(awk -F'\t' '{print $10}' <(tail -n1 "$TSV1"))"
chk "explicit --checks/--fails/--warns values land verbatim in their columns (5/1/2)" "$([ "$CHK_COL" = "5" ] && [ "$FAIL_COL" = "1" ] && [ "$WARN_COL" = "2" ] && echo 1 || echo 0)"

ROWS_BEFORE_NESTING="$(fc_timer_rows_written)"

# --- nesting: A wraps B; both rows written; B's window nested strictly inside A's ---
fc_timer_start "outer-A"
fc_timer_start "inner-B"
fc_timer_end
fc_timer_end
ROWS_AFTER_NESTING="$(fc_timer_rows_written)"
chk "nesting (start A, start B, end B, end A) writes exactly two rows" "$([ "$((ROWS_AFTER_NESTING - ROWS_BEFORE_NESTING))" -eq 2 ] && echo 1 || echo 0)"
B_ROW="$(tail -n2 "$TSV1" | head -n1)"
A_ROW="$(tail -n1 "$TSV1")"
B_START=$(awk -F'\t' '{print $4}' <<<"$B_ROW"); B_END=$(awk -F'\t' '{print $5}' <<<"$B_ROW")
A_START=$(awk -F'\t' '{print $4}' <<<"$A_ROW"); A_END=$(awk -F'\t' '{print $5}' <<<"$A_ROW")
chk "inner B's real timestamps land strictly inside outer A's window (A_start<=B_start<=B_end<=A_end)" \
  "$([ "$A_START" -le "$B_START" ] && [ "$B_START" -le "$B_END" ] && [ "$B_END" -le "$A_END" ] && echo 1 || echo 0)"
chk "B row (inner, written first) has id 'inner-B'" "$([ "$(awk -F'\t' '{print $3}' <<<"$B_ROW")" = "inner-B" ] && echo 1 || echo 0)"
chk "A row (outer, written second) has id 'outer-A'" "$([ "$(awk -F'\t' '{print $3}' <<<"$A_ROW")" = "outer-A" ] && echo 1 || echo 0)"

# --- auto-tracking via fc_timer_track: diffs, not cumulative totals ---
FAKE_PASS=0; FAKE_FAIL=0; FAKE_WARN=0
fc_timer_track FAKE_PASS FAKE_FAIL FAKE_WARN
fc_timer_start "auto-track-1"
FAKE_PASS=$((FAKE_PASS + 3)); FAKE_FAIL=$((FAKE_FAIL + 0)); FAKE_WARN=$((FAKE_WARN + 1))
fc_timer_end
R1="$(tail -n1 "$TSV1")"
fc_timer_start "auto-track-2"
FAKE_PASS=$((FAKE_PASS + 7))
fc_timer_end
R2="$(tail -n1 "$TSV1")"
chk "auto-tracked section 1: checks delta = 3 (not cumulative 3)" "$([ "$(awk -F'\t' '{print $8}' <<<"$R1")" -eq 3 ] && echo 1 || echo 0)"
chk "auto-tracked section 1: warns delta = 1 -> verdict WARN" "$([ "$(awk -F'\t' '{print $10}' <<<"$R1")" -eq 1 ] && [ "$(awk -F'\t' '{print $7}' <<<"$R1")" = "WARN" ] && echo 1 || echo 0)"
chk "auto-tracked section 2: checks DELTA = 7, never the cumulative total 10" "$([ "$(awk -F'\t' '{print $8}' <<<"$R2")" -eq 7 ] && echo 1 || echo 0)"
chk "auto-tracked section 2: no new fails/warns since section 1 ended -> verdict PASS" "$([ "$(awk -F'\t' '{print $7}' <<<"$R2")" = "PASS" ] && echo 1 || echo 0)"
fc_timer_track "" "" ""

# --- id / extra sanitisation: embedded TAB and NEWLINE must not corrupt the row shape ---
fc_timer_start "$(printf 'has\ttab\nand-newline')"
fc_timer_end --extra "$(printf 'k1=v1\tk2=v2')"
DIRTY_ROW="$(tail -n1 "$TSV1")"
DIRTY_COLS=$(awk -F'\t' '{print NF}' <<<"$DIRTY_ROW")
chk "an id/extra with embedded tab+newline still yields exactly 11 tab-separated columns" "$([ "$DIRTY_COLS" -eq 11 ] && echo 1 || echo 0)"

# --- --min-ms gate suppression (T-A01 "per-gate rows for gates > 1 s" primitive) ---
ROWS_BEFORE_GATE="$(fc_timer_rows_written)"
fc_timer_start "fast-gate"
fc_timer_end --min-ms 100000
ROWS_AFTER_FAST="$(fc_timer_rows_written)"
chk "a near-instant timer with --min-ms 100000 (100s) writes NO row" "$([ "$ROWS_AFTER_FAST" -eq "$ROWS_BEFORE_GATE" ] && echo 1 || echo 0)"
fc_timer_start "instant-section-no-threshold"
fc_timer_end
ROWS_AFTER_NO_THRESHOLD="$(fc_timer_rows_written)"
chk "the SAME near-instant timer with no --min-ms (section-style) DOES write a row" "$([ "$ROWS_AFTER_NO_THRESHOLD" -eq "$((ROWS_AFTER_FAST + 1))" ] && echo 1 || echo 0)"

ROWS_BEFORE_GATE_DEFAULT="$(fc_timer_rows_written)"
fc_timer_gate_start "gate-default-threshold"
fc_timer_gate_end
ROWS_AFTER_GATE_DEFAULT="$(fc_timer_rows_written)"
chk "fc_timer_gate_end with no explicit --min-ms applies the >=1s default threshold (an instant gate writes no row)" "$([ "$ROWS_AFTER_GATE_DEFAULT" -eq "$ROWS_BEFORE_GATE_DEFAULT" ] && echo 1 || echo 0)"

FC_TIMER_GATE_THRESHOLD_MS=0 fc_timer_gate_start "gate-zero-threshold-a"
FC_TIMER_GATE_THRESHOLD_MS=0 fc_timer_gate_end
ROWS_AFTER_ZERO_THRESHOLD="$(fc_timer_rows_written)"
chk "FC_TIMER_GATE_THRESHOLD_MS=0 lets even an instant gate write a row" "$([ "$ROWS_AFTER_ZERO_THRESHOLD" -eq "$((ROWS_AFTER_GATE_DEFAULT + 1))" ] && echo 1 || echo 0)"

# --- T027-style mutation proof at the library level: drop ONE end-timer for section A while
# sibling section B still runs and completes normally -- A's row must never appear; B's must.
ROWS_BEFORE_DROP="$(fc_timer_rows_written)"
fc_timer_start "dropped-section-A"
# (deliberately no fc_timer_end for dropped-section-A -- simulating T027's mutation)
fc_timer_start "sibling-section-B"
fc_timer_end
ROWS_AFTER_DROP="$(fc_timer_rows_written)"
chk "dropping one section's end-timer writes exactly one row (the sibling), never the dropped one" "$([ "$((ROWS_AFTER_DROP - ROWS_BEFORE_DROP))" -eq 1 ] && echo 1 || echo 0)"
LAST_ID="$(awk -F'\t' '{print $3}' <(tail -n1 "$TSV1"))"
chk "the one row that WAS written is the sibling's, not the dropped section's" "$([ "$LAST_ID" = "sibling-section-B" ] && echo 1 || echo 0)"
chk "the dropped section's id never appears anywhere in the TSV" "$([ "$(grep -c 'dropped-section-A' "$TSV1" || true)" -eq 0 ] && echo 1 || echo 0)"
chk "the dangling frame is still on the stack (never silently auto-flushed)" "$([ "$(fc_timer_stack_depth)" -eq 1 ] && echo 1 || echo 0)"
fc_timer_end >/dev/null 2>&1  # clean up the dangling frame so it doesn't leak into later assertions
chk "stack depth is 0 again after manually cleaning up the dangling frame" "$([ "$(fc_timer_stack_depth)" -eq 0 ] && echo 1 || echo 0)"

# --- id-mismatch on fc_timer_end: warns, never aborts, still records the REAL popped frame ---
fc_timer_start "actual-id"
MISMATCH_STDERR="$(fc_timer_end "wrong-expected-id" 2>&1 1>/dev/null)"
chk "fc_timer_end with a mismatched expected id emits a warning to stderr" "$([ -n "$MISMATCH_STDERR" ] && echo 1 || echo 0)"
chk "...but still records the REAL (actual) frame's id in the row, never the mismatched guess" "$([ "$(awk -F'\t' '{print $3}' <(tail -n1 "$TSV1"))" = "actual-id" ] && echo 1 || echo 0)"

# --- fc_timer_end on an empty stack: warns, returns 0, never aborts ---
fc_timer_reset
EMPTY_END_STDERR="$(fc_timer_end 2>&1 1>/dev/null)"
EMPTY_END_RC=$?
chk "fc_timer_end on an empty stack warns to stderr and returns 0" "$([ -n "$EMPTY_END_STDERR" ] && [ "$EMPTY_END_RC" -eq 0 ] && echo 1 || echo 0)"

# --- fc_timer_reset: clears stack/rows-written and lets a new run id be generated ---
export FC_TIMER_TSV="$TMP/g1_after_reset.tsv"
unset FC_TIMER_RUN_ID FC_TIMER_CANDIDATE_FINGERPRINT
fc_timer_reset
chk "fc_timer_reset zeroes the stack depth" "$([ "$(fc_timer_stack_depth)" -eq 0 ] && echo 1 || echo 0)"
chk "fc_timer_reset zeroes the rows-written counter" "$([ "$(fc_timer_rows_written)" -eq 0 ] && echo 1 || echo 0)"
NEW_RUN_ID="$(fc_timer_run_id)"
chk "after reset (with no FC_TIMER_RUN_ID override), a run id is generated automatically (non-empty)" "$([ -n "$NEW_RUN_ID" ] && echo 1 || echo 0)"
chk "the freshly generated run id differs from the earlier fixed override" "$([ "$NEW_RUN_ID" != "selftest-run-fixed-id" ] && echo 1 || echo 0)"
GIT_FP="$(fc_timer_candidate_fingerprint)"
chk "with no FC_TIMER_CANDIDATE_FINGERPRINT override, the default resolves to this checkout's real git HEAD" "$([ -n "$REAL_HEAD" ] && [ "$GIT_FP" = "$REAL_HEAD" ] && echo 1 || echo 0)"

# --- unknown flag / bad numeric input: genuine fail-closed usage errors (return 2), and the
# offending frame MUST survive on the stack (validation happens before the pop) so a caller
# who fixes their call can retry fc_timer_end without having silently lost that frame's data.
fc_timer_start "bad-flag-test"
fc_timer_end --nope 2>/dev/null
chk "fc_timer_end with an unknown flag returns nonzero (2)" "$([ $? -eq 2 ] && echo 1 || echo 0)"
chk "...and the rejected call's frame is STILL on the stack (never silently lost)" "$([ "$(fc_timer_stack_depth)" -eq 1 ] && echo 1 || echo 0)"
fc_timer_end >/dev/null 2>&1  # now drain it for real
chk "...and a correct retry successfully pops it (stack depth back to 0)" "$([ "$(fc_timer_stack_depth)" -eq 0 ] && echo 1 || echo 0)"

fc_timer_start "bad-checks-test"
fc_timer_end --checks not-a-number 2>/dev/null
chk "fc_timer_end with a non-numeric --checks value returns nonzero (2)" "$([ $? -eq 2 ] && echo 1 || echo 0)"
chk "...and that frame is ALSO still on the stack (validate-before-pop applies uniformly)" "$([ "$(fc_timer_stack_depth)" -eq 1 ] && echo 1 || echo 0)"
fc_timer_end >/dev/null 2>&1
chk "...and a correct retry (no --checks override) successfully pops it too" "$([ "$(fc_timer_stack_depth)" -eq 0 ] && echo 1 || echo 0)"

# ============================================================================
# GROUP 1b -- T048 restart round-1 R1-I1/R1-I5/R1-m4 (2026-10-08). Every check below runs
# the REAL library with NO FC_TIMER_RUN_ID/FINGERPRINT pin, so memoisation itself is what
# is exercised (the pinned checks in GROUP 1 can never see a memoisation defect -- R1-I5).
# ============================================================================
unset FC_TIMER_RUN_ID FC_TIMER_CANDIDATE_FINGERPRINT
export FC_TIMER_TSV="$TMP/g1b.tsv"
fc_timer_reset
# R1-I1: every real caller reads the run id through a $(...) command substitution, i.e. in a
# SUBSHELL whose memoisation can never reach the parent. Two such reads straddling a second
# boundary, plus a row the PARENT writes afterwards, must all carry ONE run id.
MEMO_A="$(fc_timer_run_id)"
sleep 1.1
MEMO_B="$(fc_timer_run_id)"
fc_timer_start "memo-row"
fc_timer_end
MEMO_ROW="$(awk -F'\t' 'NR>1 {print $1}' "$TMP/g1b.tsv" | tail -n1)"
chk "R1-I1: unpinned run id is identical across two \$(...) reads 1.1s apart and the parent's own row ('$MEMO_A' / '$MEMO_B' / '$MEMO_ROW')" \
  "$([ -n "$MEMO_A" ] && [ "$MEMO_A" = "$MEMO_B" ] && [ "$MEMO_A" = "$MEMO_ROW" ] && echo 1 || echo 0)"

# R1-I5 / reviewer mutation M3: the candidate fingerprint is resolved ONCE (fc_timer_init in
# the caller's own shell) and never re-derived when HEAD later moves (commit_all.sh commits
# mid-run). A throwaway repo makes HEAD move for real.
FPREPO="$TMP/fprepo"
mkdir -p "$FPREPO"
git -C "$FPREPO" init -q 2>/dev/null
git -C "$FPREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one 2>/dev/null
FP_HEAD1="$(git -C "$FPREPO" rev-parse HEAD 2>/dev/null)"
export FC_TIMER_REPO_ROOT="$FPREPO"
fc_timer_reset
fc_timer_init
git -C "$FPREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m two 2>/dev/null
FP_HEAD2="$(git -C "$FPREPO" rev-parse HEAD 2>/dev/null)"
fc_timer_start "fp-memo-row"
fc_timer_end
FP_ROW="$(awk -F'\t' 'NR>1 {print $2}' "$TMP/g1b.tsv" | tail -n1)"
chk "M3: the fingerprint memoised by fc_timer_init survives a later HEAD move (row=$FP_ROW, init-time HEAD=$FP_HEAD1, moved HEAD=$FP_HEAD2)" \
  "$([ -n "$FP_HEAD1" ] && [ "$FP_HEAD1" != "$FP_HEAD2" ] && [ "$FP_ROW" = "$FP_HEAD1" ] && echo 1 || echo 0)"
unset FC_TIMER_REPO_ROOT

# R1-I5 / reviewer mutation M4: the auto-tracked FAILS delta is computed against the fails
# snapshot (never the checks one) and drives a FAIL verdict -- the path pre_build uses.
fc_timer_reset
TRK_C=10; TRK_F=1; TRK_W=4
fc_timer_track TRK_C TRK_F TRK_W
fc_timer_start "auto-fail-delta"
TRK_C=$((TRK_C + 5)); TRK_F=$((TRK_F + 2)); TRK_W=$((TRK_W + 0))
fc_timer_end
FROW="$(tail -n1 "$TMP/g1b.tsv")"
chk "M4: auto-tracked deltas checks=5 fails=2 warns=0 and verdict FAIL ($(awk -F'\t' '{print $8"/"$9"/"$10"/"$7}' <<<"$FROW"))" \
  "$([ "$(awk -F'\t' '{print $8"/"$9"/"$10"/"$7}' <<<"$FROW")" = "5/2/0/FAIL" ] && echo 1 || echo 0)"
fc_timer_track "" "" ""

# R1-m4 / reviewer mutation M6: an --extra VALUE that happens to read "--min-ms" is a value,
# never a flag -- the default gate threshold must still apply (an instant gate writes no row).
G_BEFORE="$(fc_timer_rows_written)"
fc_timer_gate_start "gate-extra-looks-like-flag"
fc_timer_gate_end --extra "--min-ms"
chk "M6: fc_timer_gate_end --extra '--min-ms' still applies the default >=1s threshold (no row for an instant gate)" \
  "$([ "$(fc_timer_rows_written)" -eq "$G_BEFORE" ] && echo 1 || echo 0)"

# R1-I2 (class fix): fc_timer_close_all closes EVERY open frame (innermost first) with an
# aborted row carrying the exit status; FAIL for a nonzero status, WARN for a zero one.
fc_timer_reset
fc_timer_start "outer-open"
fc_timer_start "inner-open"
fc_timer_close_all --rc 3
CA_IDS="$(tail -n2 "$TMP/g1b.tsv" | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
chk "I2: fc_timer_close_all --rc 3 writes inner then outer, both FAIL with result=aborted;rc=3 ($CA_IDS)" \
  "$([ "$CA_IDS" = "inner-open:FAIL:result=aborted;rc=3 outer-open:FAIL:result=aborted;rc=3 " ] && [ "$(fc_timer_stack_depth)" -eq 0 ] && echo 1 || echo 0)"
fc_timer_start "zero-rc-open"
fc_timer_close_all --rc 0
chk "I2: fc_timer_close_all --rc 0 on a still-open frame records WARN (a frame left open at a clean exit is a wiring bug, never a silent PASS)" \
  "$([ "$(tail -n1 "$TMP/g1b.tsv" | awk -F'\t' '{print $3":"$7":"$11}')" = "zero-rc-open:WARN:result=aborted;rc=0" ] && echo 1 || echo 0)"
CA_BEFORE="$(fc_timer_rows_written)"
CA_ERR="$(fc_timer_close_all --rc 1 2>&1 1>/dev/null)"
chk "I2: fc_timer_close_all on an empty stack writes nothing and prints nothing" \
  "$([ "$(fc_timer_rows_written)" -eq "$CA_BEFORE" ] && [ -z "$CA_ERR" ] && echo 1 || echo 0)"

# ============================================================================
# GROUP 2 -- real, isolated subprocess scenarios (each needs its own process: a distinct
# FC_TIMING value, strict `set -euo pipefail`, direct execution, or a missing FC_TIMER_TSV).
# ============================================================================
run_subprocess() {  # <scriptfile> -- runs it as `bash <scriptfile>`, captures stdout/stderr/rc
  local sf="$1"
  bash "$sf" >"$TMP/sub.out" 2>"$TMP/sub.err"
  echo "$?"
}

# --- FC_TIMING=0: a real subprocess, several start/end calls, must write ZERO rows and
# never touch the filesystem for FC_TIMER_TSV at all (not even the header). ---
cat > "$TMP/case_notiming.sh" <<EOF
set -u
export FC_TIMING=0
export FC_TIMER_TSV="$TMP/notiming.tsv"
source "$FC_TIMER"
fc_timer_start "should-not-time-1"
fc_timer_end
fc_timer_gate_start "should-not-time-2"
fc_timer_gate_end
exit 0
EOF
RC=$(run_subprocess "$TMP/case_notiming.sh")
chk "FC_TIMING=0 subprocess exits 0" "$([ "$RC" -eq 0 ] && echo 1 || echo 0)"
chk "FC_TIMING=0: FC_TIMER_TSV is never created at all (true no-op, zero filesystem side effects)" "$([ ! -e "$TMP/notiming.tsv" ] && echo 1 || echo 0)"

# --- strict `set -euo pipefail` compatibility: the NORMAL success path must not abort the
# caller -- this is the critical proof that sourcing into pre_build_verification.sh (which
# itself uses `set -euo pipefail`) is safe. ---
cat > "$TMP/case_strict.sh" <<EOF
set -euo pipefail
export FC_TIMER_TSV="$TMP/strict.tsv"
source "$FC_TIMER"
fc_timer_track TESTS_PASSED ERRORS WARNINGS
TESTS_PASSED=0; ERRORS=0; WARNINGS=0
fc_timer_start "strict-mode-section"
TESTS_PASSED=\$((TESTS_PASSED + 1))
fc_timer_end
echo "SURVIVED_STRICT_MODE"
EOF
RC=$(run_subprocess "$TMP/case_strict.sh")
STRICT_OUT="$(cat "$TMP/sub.out")"
chk "sourcing fc_timer.sh + a normal start/end sequence under 'set -euo pipefail' does not abort the caller" "$([ "$RC" -eq 0 ] && [ "$STRICT_OUT" = "SURVIVED_STRICT_MODE" ] && echo 1 || echo 0)"
chk "the strict-mode run produced exactly one real TSV row" "$([ -f "$TMP/strict.tsv" ] && [ "$(tail -n +2 "$TMP/strict.tsv" | grep -c .)" -eq 1 ] && echo 1 || echo 0)"

# --- missing FC_TIMER_TSV with timing enabled: fails closed (nonzero), never a silent no-op ---
cat > "$TMP/case_notsv.sh" <<EOF
set -u
unset FC_TIMER_TSV
source "$FC_TIMER"
fc_timer_start "no-tsv-configured"
echo "RC_AFTER_START=\$?"
EOF
RC=$(run_subprocess "$TMP/case_notsv.sh")
NOTSV_OUT="$(cat "$TMP/sub.out")"
NOTSV_ERR="$(cat "$TMP/sub.err")"
chk "timing enabled with FC_TIMER_TSV unset: fc_timer_start returns nonzero (2), never silently succeeds" "$([ "$NOTSV_OUT" = "RC_AFTER_START=2" ] && echo 1 || echo 0)"
# here-string, not a pipe: this runs under `set -euo pipefail` (line 256) and a
# `printf | grep -qc` pipeline here would fall into the SIGPIPE×pipefail
# false-negative class (grep matches early, printf gets SIGPIPE, pipefail
# promotes 141 over grep's real 0) whenever NOTSV_ERR is provably-not-single-
# line -- CM-SIGPIPE-PIPEFAIL-CLASS correctly reports this shape UNDECIDABLE
# rather than assuming immunity. A here-string has no separate writer process,
# so the class cannot occur here at all.
chk "the FC_TIMER_TSV-unset failure names the missing variable on stderr (never a bare/guessed failure)" "$(grep -qc 'FC_TIMER_TSV' <<< "$NOTSV_ERR" && echo 1 || echo 0)"

# --- direct execution (not sourced) is refused with a clear message and exit 1 ---
DIRECT_OUT="$(bash "$FC_TIMER" 2>&1)"
DIRECT_RC=$?
chk "executing fc_timer.sh directly (not sourcing it) exits 1" "$([ "$DIRECT_RC" -eq 1 ] && echo 1 || echo 0)"
# here-string per the CM-SIGPIPE-PIPEFAIL-CLASS fix (see NOTSV_ERR chk above).
chk "...and prints a clear 'meant to be sourced' usage message" "$(grep -qc "meant to be 'source'd" <<< "$DIRECT_OUT" && echo 1 || echo 0)"

# --- idempotent double-sourcing: sourcing twice does not duplicate/corrupt behaviour ---
cat > "$TMP/case_double_source.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/double_source.tsv"
source "$FC_TIMER"
source "$FC_TIMER"
fc_timer_start "only-once"
fc_timer_end
fc_timer_rows_written
EOF
RC=$(run_subprocess "$TMP/case_double_source.sh")
DOUBLE_OUT="$(cat "$TMP/sub.out")"
chk "sourcing fc_timer.sh twice then running one start/end still writes exactly one row (rows_written=1)" "$([ "$DOUBLE_OUT" = "1" ] && echo 1 || echo 0)"
chk "double-sourcing produces exactly one data row in the TSV (not two)" "$([ "$(tail -n +2 "$TMP/double_source.tsv" | grep -c .)" -eq 1 ] && echo 1 || echo 0)"

# --- zero stdout in the hot path: a normal start/end sequence prints NOTHING to stdout ---
cat > "$TMP/case_silent.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/silent.tsv"
source "$FC_TIMER"
fc_timer_track TESTS_PASSED ERRORS WARNINGS
TESTS_PASSED=0; ERRORS=0; WARNINGS=0
fc_timer_start "silent-check"
TESTS_PASSED=1
fc_timer_end
fc_timer_gate_start "silent-gate"
fc_timer_gate_end
EOF
RC=$(run_subprocess "$TMP/case_silent.sh")
SILENT_OUT_BYTES="$(wc -c < "$TMP/sub.out" | tr -d ' ')"
chk "a normal start/end (+gate) sequence writes ZERO bytes to stdout (golden-output safety)" "$([ "$SILENT_OUT_BYTES" -eq 0 ] && echo 1 || echo 0)"

# --- R1-I2 class fix: fc_timer_install_exit_flush closes every frame left open when the
# process exits (any `exit N`, any `set -e` abort), keeps the caller's PRIOR EXIT trap
# running with the ORIGINAL status, and never changes the process exit status. ---
cat > "$TMP/case_exitflush.sh" <<EOF
set -euo pipefail
export FC_TIMER_TSV="$TMP/exitflush.tsv"
export FC_TIMER_RUN_ID="exitflush-run"
source "$FC_TIMER"
trap 'echo "old-trap-rc=\$?" > "$TMP/exitflush.oldtrap"' EXIT
fc_timer_install_exit_flush
fc_timer_install_exit_flush
fc_timer_start "will-abort"
false
echo "NOT-REACHED"
EOF
RC=$(run_subprocess "$TMP/case_exitflush.sh")
EF_ROWS="$(tail -n +2 "$TMP/exitflush.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
chk "I2: a set -e abort with an open frame -> exactly ONE aborted FAIL row (double install is idempotent) ($EF_ROWS)" \
  "$([ "$EF_ROWS" = "will-abort:FAIL:result=aborted;rc=1 " ] && echo 1 || echo 0)"
chk "I2: the caller's prior EXIT trap still ran and saw the ORIGINAL status 1 ($(cat "$TMP/exitflush.oldtrap" 2>/dev/null))" \
  "$([ "$(cat "$TMP/exitflush.oldtrap" 2>/dev/null)" = "old-trap-rc=1" ] && echo 1 || echo 0)"
chk "I2: the process exit status is unchanged by the flush (rc=$RC, want 1) and nothing after the abort ran" \
  "$([ "$RC" -eq 1 ] && ! grep -q NOT-REACHED "$TMP/sub.out" && echo 1 || echo 0)"
cat > "$TMP/case_exitflush_explicit.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/exitflush2.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush
fc_timer_start "explicit-exit"
fc_timer_start "explicit-exit-inner"
exit 9
EOF
RC=$(run_subprocess "$TMP/case_exitflush_explicit.sh")
EF2="$(tail -n +2 "$TMP/exitflush2.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s ", $3, $11}')"
chk "I2: an explicit exit 9 with two open frames -> both rows, innermost first, rc=9, exit status 9 ($EF2 rc=$RC)" \
  "$([ "$EF2" = "explicit-exit-inner:result=aborted;rc=9 explicit-exit:result=aborted;rc=9 " ] && [ "$RC" -eq 9 ] && echo 1 || echo 0)"
cat > "$TMP/case_exitflush_off.sh" <<EOF
set -u
export FC_TIMING=0
export FC_TIMER_TSV="$TMP/exitflush_off.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush
fc_timer_start "off"
exit 4
EOF
RC=$(run_subprocess "$TMP/case_exitflush_off.sh")
chk "I2: FC_TIMING=0 -> the exit flush writes nothing (no TSV created) and the status is untouched (rc=$RC)" \
  "$([ ! -e "$TMP/exitflush_off.tsv" ] && [ "$RC" -eq 4 ] && echo 1 || echo 0)"

# --- reviewer mutation M2: a backward wall-clock step clamps the duration to 0, the row is
# still written, and the raw start/end stamps are recorded unmodified. A real `date` shell
# function shadows the binary (the library calls `date +%s%N` by name). ---
cat > "$TMP/case_clockskew.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/clockskew.tsv"
export FC_TIMER_RUN_ID="skew"
export FC_TIMER_CANDIDATE_FINGERPRINT="skew"
source "$FC_TIMER"
# the library calls date inside \$(...) subshells, so the call counter lives in a file
date() { local n; n="\$(cat "$TMP/skew.n" 2>/dev/null || echo 0)"; n=\$((n + 1)); echo "\$n" > "$TMP/skew.n"; if [ "\$n" = 1 ]; then echo 2000000000000000000; else echo 1999999999000000000; fi; }
fc_timer_start "skewed"
fc_timer_end
EOF
RC=$(run_subprocess "$TMP/case_clockskew.sh")
SKEW="$(tail -n1 "$TMP/clockskew.tsv" 2>/dev/null | awk -F'\t' '{print $3":"$4":"$5":"$6}')"
chk "M2: a backward clock step yields duration_ms 0 with the raw stamps kept ($SKEW)" \
  "$([ "$SKEW" = "skewed:2000000000000000000:1999999999000000000:0" ] && echo 1 || echo 0)"

# ============================================================================
# GROUP 3 -- optional: shellcheck, only if the tool is genuinely present on PATH (honest
# SKIP, never a fabricated PASS, when it is not).
# ============================================================================
if command -v shellcheck >/dev/null 2>&1; then
  SC_OUT="$(shellcheck -s bash "$FC_TIMER" 2>&1)"
  SC_RC=$?
  chk "shellcheck reports zero findings against fc_timer.sh" "$([ "$SC_RC" -eq 0 ] && echo 1 || echo 0)"
  if [ "$SC_RC" -ne 0 ]; then
    echo "$SC_OUT"
  fi
else
  skip "shellcheck lint of fc_timer.sh (shellcheck not found on PATH)"
fi

echo "SUMMARY: $((N - FAIL - SKIPPED)) pass / $FAIL fail / $SKIPPED skip of $N assertions"
[ "$FAIL" = 0 ]
