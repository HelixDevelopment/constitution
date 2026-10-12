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
# round-5 F-F class: die BY the signal after cleaning up (never an `exit 128+N` look-alike).
trap 'cleanup; trap - INT; kill -s INT "$BASHPID"; exit 130' INT
trap 'cleanup; trap - TERM; kill -s TERM "$BASHPID"; exit 143' TERM

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
# T048 restart round-3 (reviewer RN4): a NON-NUMERIC --rc is an unknown exit status -> 255 and
# a FAIL row, never rc=0 / WARN (an unknown status must never read as a clean exit).
fc_timer_start "nonnumeric-rc-open"
fc_timer_close_all --rc "abc"
chk "RN4: fc_timer_close_all --rc abc records FAIL with result=aborted;rc=255 (an unknown status is never a clean exit)" \
  "$([ "$(tail -n1 "$TMP/g1b.tsv" | awk -F'\t' '{print $3":"$7":"$11}')" = "nonnumeric-rc-open:FAIL:result=aborted;rc=255" ] && echo 1 || echo 0)"
# T048 restart round-3 (reviewer RN2): fc_timer_reset RE-MINTS the source timestamp, so two
# resets one second apart in the SAME process yield two different auto run ids (same pid).
_RN2_SAVE_TSV="$FC_TIMER_TSV"; _RN2_SAVE_RID="${FC_TIMER_RUN_ID-__unset__}"
unset FC_TIMER_RUN_ID
fc_timer_reset; RN2_A="$(fc_timer_run_id)"
sleep 1.1
fc_timer_reset; RN2_B="$(fc_timer_run_id)"
chk "RN2: fc_timer_reset re-mints the run timestamp -- two resets 1 s apart give distinct auto run ids ($RN2_A vs $RN2_B)" \
  "$([ -n "$RN2_A" ] && [ -n "$RN2_B" ] && [ "$RN2_A" != "$RN2_B" ] && echo 1 || echo 0)"
export FC_TIMER_TSV="$_RN2_SAVE_TSV"
[ "$_RN2_SAVE_RID" = "__unset__" ] || export FC_TIMER_RUN_ID="$_RN2_SAVE_RID"
fc_timer_reset

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

# --- T048 round-4 F1 (the signal-death CLASS): bash runs its EXIT trap on a fatal signal with
# `$?` = the last COMPLETED command's status, so a frame open when the process is killed was
# recorded `WARN|result=aborted;rc=0` (a clean exit). EVERY signal the flush covers must record
# FAIL rc=128+N and the process must end with status 128+N. The `true` before the kill makes
# the stale `$?` exactly 0 -- the value the defect reported. PROF is in the class although
# bash never ran the EXIT trap for it (measured): there the row was missing altogether.
# V6 review round 4, F6: the class is PINNED here, independently of the library under test (a
# selftest that iterates the library's own list loses a signal's assertions when that signal is
# dropped from the library -- reviewer mutant R18, PIPE removed, passed with 0 failures). The
# library's list must EQUAL the pinned one, every per-signal case below iterates the PINNED list,
# and the total assertion count is pinned at the end (FC_SELFTEST_EXPECTED_N). ---
_PINNED_FLUSH_SIGS="HUP INT TERM USR1 USR2 ALRM PIPE XCPU XFSZ VTALRM PROF"
_LIB_FLUSH_SIGS="$(bash -c 'export FC_TIMER_TSV=/dev/null; . "$1"; printf %s "$_FC_TIMER_FLUSH_SIGNALS"' _ "$FC_TIMER" 2>/dev/null)"
_pinned_n=0; for _w in $_PINNED_FLUSH_SIGS; do _pinned_n=$((_pinned_n + 1)); done
chk "F1-class: the library's flush signal class equals the pinned 11-signal class (library '$_LIB_FLUSH_SIGS'; pinned '$_PINNED_FLUSH_SIGS', $_pinned_n signals)" \
  "$([ "$_pinned_n" = 11 ] && [ "$_LIB_FLUSH_SIGS" = "$_PINNED_FLUSH_SIGS" ] && echo 1 || echo 0)"
_FLUSH_SIGS="$_PINNED_FLUSH_SIGS"
for _sig in $_FLUSH_SIGS; do
  _num="$(kill -l "$_sig")"
  cat > "$TMP/case_sig_$_sig.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/sig_$_sig.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush --signals
fc_timer_start "sig-$_sig"
true
kill -s $_sig \$BASHPID
echo "NOT-REACHED"
EOF
  RC=$(run_subprocess "$TMP/case_sig_$_sig.sh")
  SIGROW="$(tail -n +2 "$TMP/sig_$_sig.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
  chk "F1-$_sig: a process killed by SIG$_sig mid-frame records FAIL rc=$((128 + _num)) and exits $((128 + _num)) (row='$SIGROW' rc=$RC)" \
    "$([ "$SIGROW" = "sig-$_sig:FAIL:result=aborted;rc=$((128 + _num)) " ] && [ "$RC" -eq $((128 + _num)) ] && ! grep -q NOT-REACHED "$TMP/sub.out" && echo 1 || echo 0)"
done
# the death must still be BY THE SIGNAL (WIFSIGNALED), not an `exit 128+N` look-alike: a parent
# shell aborts its own loop on a child's SIGINT death (wait-and-cooperative-exit) but NOT on an
# `exit 130`. python3 reports a signal death as a NEGATIVE returncode.
if command -v python3 >/dev/null 2>&1; then
  for _sig in INT TERM; do
    _num="$(kill -l "$_sig")"
    _prc="$(python3 -c 'import subprocess,sys; print(subprocess.run(["bash", sys.argv[1]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode)' "$TMP/case_sig_$_sig.sh" 2>/dev/null)"
    chk "F1-$_sig-signaled: the process dies BY SIG$_sig (python returncode $_prc, want -$_num)" \
      "$([ "$_prc" = "-$_num" ] && echo 1 || echo 0)"
  done
else
  skip "F1-signaled: python3 absent -- WIFSIGNALED not checkable"
fi
# QUIT is deliberately NOT in the class: bash ignores SIGQUIT in every mode, so the flush must
# leave that untouched -- the script survives and the frame closes normally (no false death).
cat > "$TMP/case_sig_quit.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/sig_quit.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush --signals
fc_timer_start "sig-QUIT"
kill -s QUIT \$BASHPID
fc_timer_end
echo "SURVIVED"
EOF
RC=$(run_subprocess "$TMP/case_sig_quit.sh")
QROW="$(tail -n +2 "$TMP/sig_quit.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s ", $3, $7}')"
chk "F1-QUIT: SIGQUIT (ignored by bash) is not turned into a death by the flush ($QROW rc=$RC)" \
  "$(grep -q SURVIVED "$TMP/sub.out" && [ "$RC" -eq 0 ] && [ "$QROW" = "sig-QUIT:PASS " ] && echo 1 || echo 0)"
# FC_TIMING=0: the flush installs NO signal trap (signal behaviour unchanged when timing is off).
cat > "$TMP/case_sig_off.sh" <<EOF
set -u
export FC_TIMING=0
export FC_TIMER_TSV="$TMP/sig_off.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush --signals
echo "traps=[\$(trap -p TERM)]"
EOF
RC=$(run_subprocess "$TMP/case_sig_off.sh")
chk "F1-off: FC_TIMING=0 installs no signal trap ($(cat "$TMP/sub.out"))" \
  "$(grep -qx 'traps=\[\]' "$TMP/sub.out" && [ ! -e "$TMP/sig_off.tsv" ] && echo 1 || echo 0)"
# compose (a): a PRIOR TERM trap that RETURNS keeps its semantics -- the handler runs, the
# script continues, and the frame is closed later by the real exit (a frame still open at a
# clean exit stays WARN rc=0, with the V6 F6 note: armed, rc=0 cannot rule out a death by a
# signal outside the class). Our flush must never turn a handled TERM into a death.
cat > "$TMP/case_sig_prior_return.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/sig_prior_return.tsv"
source "$FC_TIMER"
trap 'echo handled >> "$TMP/sig_prior_return.mark"' TERM
fc_timer_install_exit_flush --signals
fc_timer_start "prior-return"
kill -s TERM \$BASHPID
echo "CONTINUED"
exit 0
EOF
RC=$(run_subprocess "$TMP/case_sig_prior_return.sh")
PRROW="$(tail -n +2 "$TMP/sig_prior_return.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
chk "F1-compose-return: a prior TERM handler that returns still runs, the script continues, rc=0 ($PRROW rc=$RC)" \
  "$([ "$(cat "$TMP/sig_prior_return.mark" 2>/dev/null)" = handled ] && grep -q CONTINUED "$TMP/sub.out" && [ "$RC" -eq 0 ] && [ "$PRROW" = "prior-return:WARN:result=aborted;rc=0;signals=untracked-nonclass " ] && echo 1 || echo 0)"
# compose (b): a PRIOR TERM trap that EXITS 0 -- the process exit status is the prior trap's
# choice (0, never changed), but the frame open at the signal is still a FAIL rc=143.
cat > "$TMP/case_sig_prior_exit0.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/sig_prior_exit0.tsv"
source "$FC_TIMER"
trap 'echo bye >> "$TMP/sig_prior_exit0.mark"; exit 0' TERM
fc_timer_install_exit_flush --signals
fc_timer_start "prior-exit0"
kill -s TERM \$BASHPID
echo "NOT-REACHED"
EOF
RC=$(run_subprocess "$TMP/case_sig_prior_exit0.sh")
PEROW="$(tail -n +2 "$TMP/sig_prior_exit0.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
chk "F1-compose-exit0: a prior TERM handler exiting 0 keeps rc=0 but the open frame is FAIL rc=143 ($PEROW rc=$RC)" \
  "$([ "$(cat "$TMP/sig_prior_exit0.mark" 2>/dev/null)" = bye ] && [ "$RC" -eq 0 ] && [ "$PEROW" = "prior-exit0:FAIL:result=aborted;rc=143 " ] && ! grep -q NOT-REACHED "$TMP/sub.out" && echo 1 || echo 0)"
# compose (c): an IGNORED signal (trap '' TERM, or nohup's SIG_IGN) stays ignored -- the flush
# must never re-arm a signal the caller chose to ignore.
cat > "$TMP/case_sig_ignored.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/sig_ignored.tsv"
source "$FC_TIMER"
trap '' TERM
fc_timer_install_exit_flush --signals
fc_timer_start "ignored"
kill -s TERM \$BASHPID
fc_timer_end
echo "SURVIVED"
exit 0
EOF
RC=$(run_subprocess "$TMP/case_sig_ignored.sh")
IGROW="$(tail -n +2 "$TMP/sig_ignored.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s ", $3, $7}')"
chk "F1-compose-ignored: an ignored TERM stays ignored (SURVIVED, rc=0, frame closed normally: $IGROW rc=$RC)" \
  "$(grep -q SURVIVED "$TMP/sub.out" && [ "$RC" -eq 0 ] && [ "$IGROW" = "ignored:PASS " ] && echo 1 || echo 0)"

# --- T048 round-5 F-A (the signal-DEFERRAL class): bash defers a TRAPPED signal until the
# running FOREGROUND child exits, so a flush that trapped every signal made its caller
# unkillable by a single-PID kill for as long as a child ran. Every case below has a REAL
# foreground child (`sleep 3`) and a separate killer process; elapsed time and the WIFSIGNALED
# status come from python3 (a signal death is a NEGATIVE returncode; the child's stdio goes to
# /dev/null so no pipe is held open past the script's death -- timing measures the script). ---
timed_run() {  # <scriptfile> -> prints "<python returncode> <elapsed ms>"; stdout/stderr -> $TMP/sub.out/.err
  python3 -c '
import subprocess, sys, time
t = time.monotonic()
import signal
def dfl():  # a caller running this selftest under nohup / in a background job must not hide a class signal
    for n in ("SIGHUP", "SIGINT", "SIGQUIT", "SIGTERM"):
        signal.signal(getattr(signal, n), signal.SIG_DFL)
r = subprocess.run(["bash", sys.argv[1]], preexec_fn=dfl, stdin=subprocess.DEVNULL, stdout=open(sys.argv[2], "wb"), stderr=open(sys.argv[3], "wb"))
print(r.returncode, int((time.monotonic() - t) * 1000))' "$1" "$TMP/sub.out" "$TMP/sub.err"
}
# fa_case <file> <signal> <tsv> <instrument: none|flush|signals> <child: plain|run>
fa_case() {
  {
    echo 'set -u'
    if [ "$4" != none ]; then
      echo "export FC_TIMER_TSV=\"$3\""
      echo "source \"$FC_TIMER\""
      if [ "$4" = signals ]; then echo 'fc_timer_install_exit_flush --signals'; else echo 'fc_timer_install_exit_flush'; fi
      echo 'fc_timer_start "fa-frame"'
    fi
    echo "( sleep 0.4; kill -s $2 \$\$ ) </dev/null >/dev/null 2>&1 &"
    if [ "$5" = run ]; then echo 'fc_timer_run sleep 3 </dev/null >/dev/null 2>&1'; else echo 'sleep 3 </dev/null >/dev/null 2>&1'; fi
    [ "$4" != none ] && echo 'fc_timer_end'
    echo 'echo SURVIVED'
  } > "$1"
}
if command -v python3 >/dev/null 2>&1; then
  for _sig in $_FLUSH_SIGS; do
    _num="$(kill -l "$_sig")"
    # (1) DEFAULT install (no --signals): the process's signal behaviour must be identical to the
    #     SAME script without the library (parity, including INT, which bash itself defers and
    #     then survives when the child exits normally) -- no trap may be armed.
    fa_case "$TMP/fa_ctl_$_sig.sh" "$_sig" "$TMP/fa_ctl_$_sig.tsv" none plain
    read -r _crc _cms <<<"$(timed_run "$TMP/fa_ctl_$_sig.sh")"
    _csurv="$(grep -c SURVIVED "$TMP/sub.out")"
    fa_case "$TMP/fa_def_$_sig.sh" "$_sig" "$TMP/fa_def_$_sig.tsv" flush plain
    read -r _drc _dms <<<"$(timed_run "$TMP/fa_def_$_sig.sh")"
    _dsurv="$(grep -c SURVIVED "$TMP/sub.out")"
    _cfast=0; [ "$_cms" -lt 1500 ] && _cfast=1
    _dfast=0; [ "$_dms" -lt 1500 ] && _dfast=1
    chk "F-A-default-$_sig: without --signals a SIG$_sig with a foreground child behaves exactly like the uninstrumented script (control rc=$_crc ${_cms}ms survived=$_csurv; flush rc=$_drc ${_dms}ms survived=$_dsurv)" \
      "$([ "$_crc" = "$_drc" ] && [ "$_cfast" = "$_dfast" ] && [ "$_csurv" = "$_dsurv" ] && echo 1 || echo 0)"
    if [ "$_sig" != INT ]; then
      # an untracked signal death: the honest row (rc=0 is the stale `$?`, and says so)
      _drow="$(tail -n +2 "$TMP/fa_def_$_sig.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
      if [ "$_sig" = PROF ]; then
        # measured: bash runs no EXIT trap at all for SIGPROF -- the row is honestly absent
        chk "F-A-default-PROF: an untrapped SIGPROF death writes no row (bash runs no EXIT trap for it): '$_drow'" "$([ -z "$_drow" ] && echo 1 || echo 0)"
      else
        chk "F-A-default-$_sig: the open frame is recorded WARN rc=0 with the signals=untracked note, never a bare clean exit ('$_drow')" \
          "$([ "$_drow" = "fa-frame:WARN:result=aborted;rc=0;signals=untracked " ] && echo 1 || echo 0)"
      fi
      chk "F-A-default-$_sig: the death is immediate (${_dms}ms < 1500ms with a 3s foreground child) and BY the signal (rc=$_drc)" \
        "$([ "$_dfast" = 1 ] && [ "$_drc" = "-$_num" ] && echo 1 || echo 0)"
    fi
    # (2) --signals + fc_timer_run: the trapped signal takes effect AT ONCE, the frame is FAIL
    #     rc=128+N and the process still dies by the signal.
    fa_case "$TMP/fa_run_$_sig.sh" "$_sig" "$TMP/fa_run_$_sig.tsv" signals run
    read -r _rrc _rms <<<"$(timed_run "$TMP/fa_run_$_sig.sh")"
    _rrow="$(tail -n +2 "$TMP/fa_run_$_sig.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
    chk "F-A-run-$_sig: --signals + fc_timer_run: SIG$_sig with a 3s foreground child takes effect at once (${_rms}ms < 1500ms), FAIL rc=$((128 + _num)), death by the signal (rc=$_rrc) ($_rrow)" \
      "$([ "$_rms" -lt 1500 ] && [ "$_rrc" = "-$_num" ] && [ "$_rrow" = "fa-frame:FAIL:result=aborted;rc=$((128 + _num)) " ] && echo 1 || echo 0)"
  done
  # (3) characterization of the documented contract: --signals WITHOUT fc_timer_run still defers
  #     the signal until the plain foreground child exits (the obligation the docs state).
  fa_case "$TMP/fa_plain.sh" TERM "$TMP/fa_plain.tsv" signals plain
  read -r _prc _pms <<<"$(timed_run "$TMP/fa_plain.sh")"
  _prow="$(tail -n +2 "$TMP/fa_plain.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
  chk "F-A-contract: --signals with a PLAIN foreground child defers the TERM until the child exits (${_pms}ms >= 2000ms) and then records FAIL rc=143 ($_prow rc=$_prc)" \
    "$([ "$_pms" -ge 2000 ] && [ "$_prc" = -15 ] && [ "$_prow" = "fa-frame:FAIL:result=aborted;rc=143 " ] && echo 1 || echo 0)"
else
  skip "F-A: python3 absent -- elapsed time / WIFSIGNALED not measurable"
fi
# (4) the default install arms NO signal trap at all; --signals arms the whole class; a bad flag
#     is refused and installs nothing.
cat > "$TMP/fa_traps.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/fa_traps.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush
echo "default=[\$(trap -p TERM)\$(trap -p HUP)\$(trap -p USR1)]"
fc_timer_install_exit_flush --signals
# a pure-bash case, not \`trap -p | grep -q\` (CM-SIGPIPE-PIPEFAIL-CLASS) and not a here-string:
# measured, \`grep ... <<< "\$(trap -p SIG)"\` sees the RESET traps (prints nothing) in this shell.
echo "armed=\$(for s in \$_FC_TIMER_FLUSH_SIGNALS; do case "\$(trap -p "\$s")" in *_fc_timer_signal_flush*) printf x ;; esac; done)"
EOF
RC=$(run_subprocess "$TMP/fa_traps.sh")
read -r -a _flush_sig_arr <<< "$_FLUSH_SIGS"   # the signal list is a space-separated word list; count its words
_nsig="${#_flush_sig_arr[@]}"
chk "F-A-traps: a default install arms no signal trap; a later --signals arms all $_nsig class signals ($(tr '\n' ' ' < "$TMP/sub.out"))" \
  "$(grep -qx 'default=\[\]' "$TMP/sub.out" && grep -qx "armed=$(printf 'x%.0s' $(seq 1 "$_nsig"))" "$TMP/sub.out" && echo 1 || echo 0)"
cat > "$TMP/fa_badflag.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/fa_badflag.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush --sigals
echo "rc=\$? exit=[\$(trap -p EXIT)]"
EOF
RC=$(run_subprocess "$TMP/fa_badflag.sh")
chk "F-A-badflag: an unknown install flag is refused (rc=2) and installs nothing ($(cat "$TMP/sub.out"))" \
  "$(grep -qx 'rc=2 exit=\[\]' "$TMP/sub.out" && echo 1 || echo 0)"
# (5) fc_timer_run keeps the child's foreground semantics when armed (every call here runs in the
#     CURRENT shell -- redirections and here-strings, never a pipeline, whose subshell would not
#     ignore INT/QUIT for a background job and so could not see the restore being tested): exit status, stdin, SIGINT/
#     SIGQUIT NOT ignored (a background job would ignore them), a caller-ignored INT stays ignored,
#     a shell function still runs in place (its state change survives), and a composed prior
#     trap that RETURNS does not make fc_timer_run report the signal instead of the child's status.
cat > "$TMP/fa_sem.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/fa_sem.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush --signals
fc_timer_run sh -c 'exit 7'; echo "status=\$?"
fc_timer_run head -c 11 <<<"piped-input"; echo
fc_timer_run grep '^SigIgn' /proc/self/status > "$TMP/fa_ign_def.txt"; sed 's/^/default-/' "$TMP/fa_ign_def.txt"
fc_timer_run sh -c 'kill -s TERM \$\$'; echo "childsig=\$?"
setglobal() { GLOBAL_SET=yes; }
GLOBAL_SET=no; fc_timer_run setglobal; echo "function=\$GLOBAL_SET"
cd /; fc_timer_run cd "$TMP"; echo "builtin_cd=\$? pwd=\$PWD"
fc_timer_run read -r READ_VAL <<<"read-value"; echo "builtin_read=\$? val=\${READ_VAL:-unset}"
rm -f "$TMP/fa_closed.mark"; fc_timer_run sh -c 'echo closed-stdin-ran > "$TMP/fa_closed.mark"' 0<&-; echo "closedstdin=\$?"
trap '' INT
fc_timer_run grep '^SigIgn' /proc/self/status > "$TMP/fa_ign_ign.txt"; sed 's/^/ignored-/' "$TMP/fa_ign_ign.txt"
EOF
RC=$(run_subprocess "$TMP/fa_sem.sh")
_ign_def="$(sed -n 's/^default-SigIgn:[[:space:]]*//p' "$TMP/sub.out")"
_ign_ign="$(sed -n 's/^ignored-SigIgn:[[:space:]]*//p' "$TMP/sub.out")"
_bit() { [ -n "$1" ] && [ $(( 0x$1 & $2 )) -ne 0 ] && echo 1 || echo 0; }
chk "F-A-run-status: fc_timer_run returns the child's own exit status (want status=7)" "$(grep -qx 'status=7' "$TMP/sub.out" && echo 1 || echo 0)"
chk "F-A-run-stdin: fc_timer_run passes the caller's stdin to the child (a background job would read /dev/null)" "$(grep -qx 'piped-input' "$TMP/sub.out" && echo 1 || echo 0)"
chk "F-A-run-intquit: the child does NOT ignore SIGINT/SIGQUIT (SigIgn=$_ign_def; a bare background job ignores both)" \
  "$([ "$(_bit "$_ign_def" 2)" = 0 ] && [ "$(_bit "$_ign_def" 4)" = 0 ] && echo 1 || echo 0)"
chk "F-A-run-ignored: a caller-ignored INT stays ignored in the child (SigIgn=$_ign_ign), exactly as in the foreground" \
  "$([ "$(_bit "$_ign_ign" 2)" = 1 ] && echo 1 || echo 0)"
chk "F-A-run-childsig: a child that dies of SIGTERM is reported 143 (got $(sed -n 's/^childsig=//p' "$TMP/sub.out"))" "$(grep -qx 'childsig=143' "$TMP/sub.out" && echo 1 || echo 0)"
chk "F-A-run-function: a shell function still runs in place (its global assignment survives)" "$(grep -qx 'function=yes' "$TMP/sub.out" && echo 1 || echo 0)"
# V6 review round 3 (reviewer mutant AM7): a BUILTIN must run in place too -- `cd` and `read` run
# in a background subshell would change nothing in the caller.
chk "F-A-run-builtin-cd: fc_timer_run cd changes the CALLER's directory (got '$(sed -n 's/^builtin_cd=//p' "$TMP/sub.out")', want '0 pwd=$TMP')" "$(grep -qxF "builtin_cd=0 pwd=$TMP" "$TMP/sub.out" && echo 1 || echo 0)"
chk "F-A-run-builtin-read: fc_timer_run read assigns the CALLER's variable (got '$(sed -n 's/^builtin_read=//p' "$TMP/sub.out")')" "$(grep -qx 'builtin_read=0 val=read-value' "$TMP/sub.out" && echo 1 || echo 0)"
# V6 review round 3 (reviewer mutant AM8): with fd 0 CLOSED the command must still run (a `<&0`
# redirection on a closed fd fails, and the child would never start).
chk "F-A-run-closed-stdin: with stdin closed the command still runs and returns 0 (got '$(sed -n 's/^closedstdin=//p' "$TMP/sub.out")', marker='$(cat "$TMP/fa_closed.mark" 2>/dev/null)')" "$(grep -qx 'closedstdin=0' "$TMP/sub.out" && [ "$(cat "$TMP/fa_closed.mark" 2>/dev/null)" = closed-stdin-ran ] && echo 1 || echo 0)"
if command -v python3 >/dev/null 2>&1; then
  cat > "$TMP/fa_compose.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/fa_compose.tsv"
source "$FC_TIMER"
trap 'echo handled >> "$TMP/fa_compose.mark"' TERM
fc_timer_install_exit_flush --signals
( sleep 0.3; kill -s TERM \$\$ ) </dev/null >/dev/null 2>&1 &
fc_timer_run sh -c 'sleep 1; exit 7' </dev/null; echo "status=\$?"
EOF
  read -r _xrc _xms <<<"$(timed_run "$TMP/fa_compose.sh")"
  chk "F-A-run-compose: a prior TERM handler that returns runs once, and fc_timer_run still returns the child's status 7 (rc=$_xrc $(tr '\n' ' ' < "$TMP/sub.out"))" \
    "$([ "$(cat "$TMP/fa_compose.mark" 2>/dev/null)" = handled ] && grep -qx 'status=7' "$TMP/sub.out" && [ "$_xrc" = 0 ] && echo 1 || echo 0)"
fi
# (6) unarmed fc_timer_run is a plain in-place call (a background start would lose the function's
#     state and is not needed when no signal is trapped).
cat > "$TMP/fa_unarmed.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/fa_unarmed.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush
fc_timer_run sh -c 'exit 5'; echo "status=\$?"
fc_timer_run head -c 2 <<<"in"; echo
EOF
RC=$(run_subprocess "$TMP/fa_unarmed.sh")
chk "F-A-run-unarmed: without --signals fc_timer_run is a plain call (status=5, stdin passed)" \
  "$(grep -qx 'status=5' "$TMP/sub.out" && grep -qx 'in' "$TMP/sub.out" && echo 1 || echo 0)"

# --- T048 round-5 V6 F1: ANY trap whose handler RETURNS interrupts `wait` -- not only a class
# trap composed at install time, but also a trap on a NON-class signal (WINCH) and a class
# signal whose trap the caller set AFTER the install (USR2 here, which replaces the flush
# handler). fc_timer_run must keep waiting while its child is alive and return the child's OWN
# status, never 128+N with the child still running. The child writes a marker as its last act,
# so the marker existing when fc_timer_run returns proves the child had finished. ---
for _f1 in WINCH USR2; do
  cat > "$TMP/f1_$_f1.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/f1_$_f1.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush --signals
trap 'echo handled >> "$TMP/f1_$_f1.mark"' $_f1
( sleep 0.3; kill -s $_f1 \$\$ ) </dev/null >/dev/null 2>&1 &
fc_timer_run sh -c 'sleep 1.2; echo done > "$TMP/f1_$_f1.child"; exit 4' </dev/null
echo "status=\$? child=\$(cat "$TMP/f1_$_f1.child" 2>/dev/null)"
EOF
  RC=$(run_subprocess "$TMP/f1_$_f1.sh")
  chk "F1-late-trap-$_f1: a returning $_f1 trap interrupts wait, yet fc_timer_run returns the child's own status 4 only after the child finished ($(tr '\n' ' ' < "$TMP/sub.out") handler=$(cat "$TMP/f1_$_f1.mark" 2>/dev/null))" \
    "$(grep -qx 'status=4 child=done' "$TMP/sub.out" && [ "$(cat "$TMP/f1_$_f1.mark" 2>/dev/null)" = handled ] && echo 1 || echo 0)"
done

# --- V6 review round 4 (reviewer mutant R13: the spin bound 10000 -> 2 survived, because every
# F1-late case interrupts the wait only ONCE). Here the wait is interrupted FIVE times by a
# returning WINCH trap while the child runs: fc_timer_run must re-wait every time and still
# return the child's own status 4 only after the child finished. ---
cat > "$TMP/f1_repeat.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/f1_repeat.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush --signals
trap 'echo handled >> "$TMP/f1_repeat.mark"' WINCH
( for _i in 1 2 3 4 5; do sleep 0.25; kill -s WINCH \$\$; done ) </dev/null >/dev/null 2>&1 &
fc_timer_run sh -c 'sleep 2; echo done > "$TMP/f1_repeat.child"; exit 4' </dev/null
echo "status=\$? child=\$(cat "$TMP/f1_repeat.child" 2>/dev/null)"
EOF
RC=$(run_subprocess "$TMP/f1_repeat.sh")
_rep_n="$(grep -c handled "$TMP/f1_repeat.mark" 2>/dev/null)"
chk "F1-repeat-WINCH: five returning WINCH traps interrupt the wait five times, yet fc_timer_run returns the child's own status 4 only after the child finished ($(tr '\n' ' ' < "$TMP/sub.out") handlers=$_rep_n)" \
  "$(grep -qx 'status=4 child=done' "$TMP/sub.out" && [ "$_rep_n" = 5 ] && echo 1 || echo 0)"

# --- V6 F3 (reviewer mutant R12): an ARMED signal death must still run the caller's OWN EXIT
# cleanup (the flush re-raises the signal; it must never drop the EXIT trap on the way). ---
cat > "$TMP/f3_exit.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/f3_exit.tsv"
source "$FC_TIMER"
trap 'echo CALLER-EXIT-CLEANUP-RAN >> "$TMP/f3_exit.mark"' EXIT
fc_timer_install_exit_flush --signals
fc_timer_start "f3-frame"
kill -s TERM \$BASHPID
echo NOT-REACHED
EOF
RC=$(run_subprocess "$TMP/f3_exit.sh")
F3ROW="$(tail -n +2 "$TMP/f3_exit.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
chk "F3-exit-cleanup: an armed SIGTERM death records FAIL rc=143 AND still runs the caller's EXIT cleanup (mark='$(cat "$TMP/f3_exit.mark" 2>/dev/null)' row='$F3ROW' rc=$RC)" \
  "$([ "$(cat "$TMP/f3_exit.mark" 2>/dev/null)" = CALLER-EXIT-CLEANUP-RAN ] && [ "$F3ROW" = "f3-frame:FAIL:result=aborted;rc=143 " ] && [ "$RC" -eq 143 ] && ! grep -q NOT-REACHED "$TMP/sub.out" && echo 1 || echo 0)"

# --- V6 F4 (reviewer mutant R11): a SUBSHELL that sources the library and arms it must kill
# ITSELF on a signal, never its parent (the re-raise targets $BASHPID, not $$). ---
cat > "$TMP/f4_sub.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/f4_sub.tsv"
( source "$FC_TIMER"; fc_timer_install_exit_flush --signals; fc_timer_start "f4-sub"; kill -s TERM \$BASHPID; echo NOT-REACHED )
echo "subrc=\$?"
echo OUTER-SURVIVED
exit 0
EOF
RC=$(run_subprocess "$TMP/f4_sub.sh")
F4ROW="$(tail -n +2 "$TMP/f4_sub.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
chk "F4-subshell: an armed subshell killed by SIGTERM dies itself (subrc=143) while its parent survives (rc=0) ($(tr '\n' ' ' < "$TMP/sub.out") row='$F4ROW' rc=$RC)" \
  "$(grep -qx 'subrc=143' "$TMP/sub.out" && grep -qx OUTER-SURVIVED "$TMP/sub.out" && ! grep -q NOT-REACHED "$TMP/sub.out" && [ "$RC" -eq 0 ] && [ "$F4ROW" = "f4-sub:FAIL:result=aborted;rc=143 " ] && echo 1 || echo 0)"

# --- V6 F6: armed, but killed by a signal OUTSIDE the class (ABRT, deliberately untrapped): the
# EXIT trap sees rc=0 and the row must say why rc=0 cannot be trusted -- never a bare clean exit. ---
cat > "$TMP/f6_abrt.sh" <<EOF
set -u
ulimit -c 0
export FC_TIMER_TSV="$TMP/f6_abrt.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush --signals
fc_timer_start "f6-frame"
true
kill -s ABRT \$BASHPID
echo NOT-REACHED
EOF
RC=$(run_subprocess "$TMP/f6_abrt.sh")
F6ROW="$(tail -n +2 "$TMP/f6_abrt.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
chk "F6-armed-nonclass: armed + an untrapped ABRT death records WARN rc=0 WITH the signals=untracked-nonclass note ('$F6ROW' rc=$RC)" \
  "$([ "$F6ROW" = "f6-frame:WARN:result=aborted;rc=0;signals=untracked-nonclass " ] && [ "$RC" -eq 134 ] && echo 1 || echo 0)"


# --- T048 round-5 F-D: _FC_TIMER_SIGNAL_RC is the library's own marker. An exported value
# inherited from the environment must NOT turn a clean exit into a recorded signal death. ---
cat > "$TMP/fd_env.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/fd_env.tsv"
source "$FC_TIMER"
fc_timer_install_exit_flush --signals
fc_timer_start "fd-frame"
echo "child-sees=[\$(bash -c 'printf %s "\${_FC_TIMER_SIGNAL_RC-unset}"')]"
exit 0
EOF
RC="$(_FC_TIMER_SIGNAL_RC=143 bash "$TMP/fd_env.sh" >"$TMP/sub.out" 2>"$TMP/sub.err"; echo $?)"
FDROW="$(tail -n +2 "$TMP/fd_env.tsv" 2>/dev/null | awk -F'\t' '{printf "%s:%s:%s ", $3, $7, $11}')"
chk "F-D: an inherited _FC_TIMER_SIGNAL_RC=143 does not make a clean exit 0 record a signal death ($FDROW rc=$RC)" \
  "$([ "$FDROW" = "fd-frame:WARN:result=aborted;rc=0;signals=untracked-nonclass " ] && [ "$RC" -eq 0 ] && echo 1 || echo 0)"
chk "F-D: the marker is not re-exported to this process's children ($(cat "$TMP/sub.out"))" \
  "$(grep -qx 'child-sees=\[unset\]' "$TMP/sub.out" && echo 1 || echo 0)"

# --- T048 round-5 F-E: a frame is popped only AFTER its row is appended. A failing append or a
# failing `date` leaves the frame on the stack (return 2), so it is never silently lost. ---
cat > "$TMP/fe.sh" <<EOF
set -u
export FC_TIMER_TSV="$TMP/fe.tsv"
export FC_TIMER_RUN_ID=fe FC_TIMER_CANDIDATE_FINGERPRINT=fe
source "$FC_TIMER"
fc_timer_start "fe-append"
chmod 444 "$TMP/fe.tsv"
fc_timer_end; echo "append-fail rc=\$? depth=\$(fc_timer_stack_depth)"
chmod 644 "$TMP/fe.tsv"
fc_timer_end; echo "append-retry rc=\$? depth=\$(fc_timer_stack_depth)"
fc_timer_start "fe-date"
date() { return 1; }
fc_timer_end; echo "date-fail rc=\$? depth=\$(fc_timer_stack_depth)"
unset -f date
fc_timer_end; echo "date-retry rc=\$? depth=\$(fc_timer_stack_depth)"
EOF
if [ "$(id -u)" = 0 ]; then
  skip "F-E: running as root -- chmod 444 cannot make the TSV unwritable, the append-failure case is not drivable"
else
RC=$(run_subprocess "$TMP/fe.sh")
FEIDS="$(tail -n +2 "$TMP/fe.tsv" 2>/dev/null | awk -F'\t' '{printf "%s ", $3}')"
chk "F-E: a failed append returns 2 with the frame KEPT (depth 1), a retry writes it ($(tr '\n' ' ' < "$TMP/sub.out"))" \
  "$(grep -qx 'append-fail rc=2 depth=1' "$TMP/sub.out" && grep -qx 'append-retry rc=0 depth=0' "$TMP/sub.out" && echo 1 || echo 0)"
chk "F-E: a failed end-time read returns 2 with the frame KEPT (depth 1), a retry writes it" \
  "$(grep -qx 'date-fail rc=2 depth=1' "$TMP/sub.out" && grep -qx 'date-retry rc=0 depth=0' "$TMP/sub.out" && echo 1 || echo 0)"
chk "F-E: exactly the two frames were written, once each ($FEIDS)" "$([ "$FEIDS" = "fe-append fe-date " ] && echo 1 || echo 0)"
fi

# --- T048 round-5 F-B: the prior-trap text is re-quoted EXACTLY. A body containing a single
# quote must run as written (the `'\''` escape trap -p prints is undone), for EXIT and signals. ---
printf '%s\n' 'set -u' \
  "export FC_TIMER_TSV=\"$TMP/fb.tsv\"" \
  "source \"$FC_TIMER\"" \
  "trap 'echo \"it'\\''s handled\" >> \"$TMP/fb_sig.mark\"' TERM" \
  "trap 'echo \"it'\\''s the exit\" >> \"$TMP/fb_exit.mark\"' EXIT" \
  'fc_timer_install_exit_flush --signals' \
  "kill -s TERM \$BASHPID" \
  'exit 0' > "$TMP/fb.sh"
RC=$(run_subprocess "$TMP/fb.sh")
chk "F-B: a prior TERM trap body with a single quote runs verbatim ('$(cat "$TMP/fb_sig.mark" 2>/dev/null)')" \
  "$([ "$(cat "$TMP/fb_sig.mark" 2>/dev/null)" = "it's handled" ] && echo 1 || echo 0)"
chk "F-B: a prior EXIT trap body with a single quote runs verbatim ('$(cat "$TMP/fb_exit.mark" 2>/dev/null)')" \
  "$([ "$(cat "$TMP/fb_exit.mark" 2>/dev/null)" = "it's the exit" ] && [ "$RC" -eq 0 ] && echo 1 || echo 0)"

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

# V6 review round 4, F6: the assertion count is pinned (skip() counts too, so a host without python3
# / shellcheck / a non-root user still reaches the same N). A selftest that silently loses
# assertions -- a loop over a list the library under test shrank -- fails here.
FC_SELFTEST_EXPECTED_N=165
chk "assertion count: $N assertions ran before this one (want $FC_SELFTEST_EXPECTED_N)" "$([ "$N" = "$FC_SELFTEST_EXPECTED_N" ] && echo 1 || echo 0)"

echo "SUMMARY: $((N - FAIL - SKIPPED)) pass / $FAIL fail / $SKIPPED skip of $N assertions"
[ "$FAIL" = 0 ]
