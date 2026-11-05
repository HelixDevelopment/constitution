#!/bin/sh
# =============================================================================
# test_multitrack_orchestrator_reconcile_rc.sh — RB-FIX3 (I-b) permanent
#     regression guard: multitrack_alias_orchestrator.sh's `cmd_reconcile`
#     ran `awk '...' > "$BIND.tmp.$$" && mv -f "$BIND.tmp.$$" "$BIND"` then
#     an UNCONDITIONAL `echo "RECONCILE: bindings snapshot rebuilt..."` as
#     the subshell's LAST command -- so on a genuine awk failure, `&&`
#     correctly short-circuited `mv` (bindings.snapshot was never clobbered
#     with a bad rebuild) but the trailing unconditional echo still ran,
#     making `cmd_reconcile` **always return 0** regardless of whether the
#     rebuild actually happened. An independent code review reproduced this
#     live on the pre-fix `exp` gawk-fatal artifact (RB-FIX2's own defect,
#     separately fixed and separately regression-guarded by
#     test_multitrack_orchestrator_reconcile.sh -- that test's own docstring
#     HONESTLY flags the rc-swallowing as "a second, out-of-scope defect...
#     not fixed there"). This file closes that gap directly: `cmd_reconcile`
#     now captures the awk pipeline's OWN exit status explicitly and, on
#     failure, discards the (possibly partial) tmp file, prints a clearly-
#     labelled `ERECONCILE:` error to stderr, and returns non-zero -- NEVER
#     the false-success message, NEVER a silent rc=0.
# -----------------------------------------------------------------------------
# Purpose (§11.4.114/§11.4.115 RED-on-the-broken-artifact + polarity switch):
#   RED_MODE=1 — reproduces the defect on the ACTUAL pre-fix artifact this fix
#     replaced, extracted at the PINNED commit RED_PIN (the parent of 55998fb,
#     which introduced both the RB-FIX2 `xp` rename and this RB-FIX3 rc
#     capture). It is NEVER `git show HEAD:`: once the fix is committed HEAD
#     holds the FIXED copy, so a HEAD-built RED can never go RED on a
#     committed tree (redpin class, §11.4.115/§11.4.292(E)); an unreachable
#     pin (shallow clone) FAILs closed. Seeds a BIND event (triggers the real
#     gawk `exp` fatal) into a scratch
#     registry whose bindings.snapshot is PRE-SEEDED with a known sentinel,
#     then asserts on the pinned copy's `reconcile`:
#       (a) stderr genuinely shows "syntax error" (the awk fatal fired);
#       (b) bindings.snapshot is UNCHANGED (still the sentinel -- no data
#           loss, the pre-existing `&&`-short-circuit correctly protected
#           this half);
#       (c) stdout STILL prints the false-success "RECONCILE: bindings
#           snapshot rebuilt..." message despite the genuine failure;
#       (d) **the exit code is STILL 0** despite (a) -- THIS is the specific
#           bug under test: rc=0 masking a genuine, captured, on-stderr
#           failure.
#   RED_MODE=0 (GREEN) — drives the CURRENT (fixed) working-tree orchestrator
#     and proves BOTH directions:
#       (e) FAILURE path — an awk-pipeline failure independent of any
#           gawk-builtin-name quirk (the `exp`/`xp` defect is ALREADY fixed
#           in the working tree, so this must be triggered a different,
#           source-agnostic way): the scratch registry directory is made
#           read-only (chmod 555) AFTER `_ensure_dirs` has already created
#           bindings.snapshot/events.jsonl/etc, so `awk ... > "$BIND.tmp.$$"`
#           genuinely fails at the shell-redirection layer (EACCES creating
#           the tmp file) -- a real, reproducible, source-independent
#           failure of the SAME pipeline this fix wraps. Asserts: rc != 0,
#           stdout does NOT contain the false-success message, stderr shows
#           the new `ERECONCILE:` label, and bindings.snapshot is UNCHANGED
#           (still its pre-failure content -- no data loss on failure).
#       (f) HAPPY path (unchanged) — a fresh, writable scratch registry with
#           a real multi-event fixture (BIND/FALLBACK/HEARTBEAT/UNBIND/BIND/
#           REAP) reconciles successfully: rc=0, the SAME success message
#           prints, and bindings.snapshot is BYTE-IDENTICAL to a
#           hand-computed expected result -- proving the fix did not
#           regress the pre-existing correct-rebuild behaviour.
#       (g) sibling no-regression battery (bind/heartbeat/fallback/status/
#           unbind/reap) — all still exit 0 on the current primitive.
#   Both modes run their battery 3 times (§11.4.50 determinism) and assert
#   the normalized (PID/timestamp-free) results are byte-identical across
#   all 3 iterations.
#
# Usage:
#   sh constitution/scripts/multitrack/test_multitrack_orchestrator_reconcile_rc.sh              # RED then GREEN
#   RED_MODE=1 sh constitution/scripts/multitrack/test_multitrack_orchestrator_reconcile_rc.sh   # RED only
#   RED_MODE=0 sh constitution/scripts/multitrack/test_multitrack_orchestrator_reconcile_rc.sh   # GREEN only
#   (default RED_MODE=both if unset: one default-tier run proves the defect on
#   the pinned pre-fix copy AND the fix on the current copy)
#
# Inputs: RED_MODE (both|1|0, default both); MT_TEST_CONST_ROOT (optional override,
#   else `git rev-parse --show-toplevel` from this file's own directory);
#   optional MT_RECONCILE_RC_TEST_EVIDENCE_DIR override.
#
# Outputs: PASS/FAIL/SKIP lines on stdout + $EV/results.log; per-iteration
#   captured stdout/stderr + normalized-result files under $EV. Exit 0 iff
#   FAIL count is 0.
#
# Side-effects: creates + removes ONE scratch tmp dir (extracted pre-fix
#   copy for RED_MODE=1, scratch config/alias-dir registries for BOTH
#   modes); a chmod-555 scratch subdirectory is ALWAYS restored to writable
#   (chmod -R u+rwx) at the TOP of cleanup(), BEFORE the generic `rm -rf`,
#   so trap cleanup never leaves orphaned unremovable files (§11.4.14);
#   `trap ... EXIT INT TERM` on every exit path; writes ONLY under
#   qa-results/ (project root, if reachable) and the scratch dir; NEVER
#   touches the real ~/.claude / live registry, NEVER spawns a real worker,
#   NEVER touches a device or credential.
#
# Dependencies: sh (POSIX), bash, gawk (or any awk on PATH), git, date,
#   mktemp, diff, wc, grep, chmod, id.
#
# Cross-references: multitrack_alias_orchestrator.sh (`cmd_reconcile`, unit
#   under test); test_multitrack_orchestrator_reconcile.sh (the SIBLING
#   RB-FIX2 regression guard for the `exp`->`xp` rename -- that test's own
#   docstring honestly flags the rc-swallowing this file fixes as "out of
#   scope" for it); qa-results/multitrack/RB_COMBINED_REVIEW_report.md (the
#   Important finding this closes); §11.4.6 (no-guessing); §11.4.111
#   (resolve-by-stable-name spirit -- N/A directly, cited by the sibling
#   test only); §11.4.114 (known-good/known-bad diff oracle); §11.4.115
#   (RED-on-broken-artifact + polarity switch); §11.4.50 (determinism);
#   §11.4.67 (sh-parseable); §11.4.135 (permanent regression guard).
# =============================================================================

set -u

MT_RCT_SELF=$0
case "$MT_RCT_SELF" in
    */*) MT_RCT_DIR=${MT_RCT_SELF%/*} ;;
    *)   MT_RCT_DIR=. ;;
esac

_rcrc_const_root() {
    if [ -n "${MT_TEST_CONST_ROOT:-}" ]; then printf '%s\n' "$MT_TEST_CONST_ROOT"; return 0; fi
    ( cd "$MT_RCT_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
CONST_ROOT=$(_rcrc_const_root)
[ -n "$CONST_ROOT" ] || { echo "FATAL: no constitution submodule root (git toplevel / \$MT_TEST_CONST_ROOT)" >&2; exit 90; }

ORCH="$CONST_ROOT/scripts/multitrack/multitrack_alias_orchestrator.sh"
[ -f "$ORCH" ] || { echo "FATAL: primitive not found: $ORCH" >&2; exit 91; }
sh -n "$ORCH" 2>/dev/null   || { echo "FATAL: primitive fails sh -n: $ORCH" >&2; exit 92; }
bash -n "$ORCH" 2>/dev/null || { echo "FATAL: primitive fails bash -n: $ORCH" >&2; exit 92; }

# this test's own chmod-555 fault-injection scenario is meaningless (and
# would silently no-op) if run as root, since root bypasses directory
# permission checks -- honest SKIP rather than a false PASS (§11.4.6).
if [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
    RUNNING_AS_ROOT=1
else
    RUNNING_AS_ROOT=0
fi

RED_MODE="${RED_MODE:-both}"
case "$RED_MODE" in
    both) PHASES="1 0" ;;
    1)    PHASES="1" ;;
    0)    PHASES="0" ;;
    *)    echo "FATAL: RED_MODE must be both, 1 or 0 (got '$RED_MODE')" >&2; exit 2 ;;
esac
REQ_MODE=$RED_MODE
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
_rcrc_evidence_home() {
    _ph=$(cd "$CONST_ROOT/.." 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$_ph" ] && [ -d "$_ph" ]; then printf '%s/qa-results/multitrack\n' "$_ph"; return 0; fi
    printf '%s/qa-results/multitrack\n' "$CONST_ROOT"
}
EV="${MT_RECONCILE_RC_TEST_EVIDENCE_DIR:-$(_rcrc_evidence_home)/reconcile_rc_test_${RUN_TS}-$$}"
mkdir -p "$EV"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_recon_rc_test.XXXXXX")
cleanup() {
    # restore writability BEFORE removal -- a chmod-555 scratch dir left
    # from an interrupted run must never leave unremovable orphans.
    chmod -R u+rwx "$WORK" 2>/dev/null || true
    rm -rf "$WORK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s (%s) [evidence: %s]\n' "$1" "$2" "$3" | tee -a "$EV/results.log"; }

# --- RED artifact pin (§11.4.114/§11.4.115, redpin class) -------------------
# The RED artifact is the pre-fix copy at a FIXED commit, never `git show
# HEAD:` (HEAD holds the FIXED copy once the fix is committed). RED_PIN is the
# parent of 55998fb, which introduced the RB-FIX3 awk exit-status capture.
# Assertions: the pin is reachable (else FAIL closed); the pinned copy contains
# the pre-fix `exp` construct (the awk fatal the RED drives) AND lacks the
# rc capture; the CURRENT copy has the rc capture (control needle).
RED_PIN=e60cbde2e33e7d0542a937331763f6be7e739c9a
RED_PATH=scripts/multitrack/multitrack_alias_orchestrator.sh
PREFIX_NEEDLE='exp=val($0,"expires")'
FIX_NEEDLE='_reconcile_awk_rc=$?'
_cur_fix=$(grep -cF -- "$FIX_NEEDLE" "$ORCH"); _cur_pre=$(grep -cF -- "$PREFIX_NEEDLE" "$ORCH")
if [ "${_cur_fix:-0}" -ge 1 ] && [ "${_cur_pre:-0}" -eq 0 ]; then
    pass "control: the CURRENT $RED_PATH carries the fix ('$FIX_NEEDLE' x$_cur_fix) and not the pre-fix construct" "$ORCH"
else
    fail "control: the CURRENT $RED_PATH lost the fix (fix x${_cur_fix:-0}, pre-fix x${_cur_pre:-0})" "$ORCH"
fi
PREFIX_COPY="$WORK/multitrack_alias_orchestrator_prefix.sh"
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

_seed_scratch() {
    _seed_root=$1
    mkdir -p "$_seed_root/config" "$_seed_root/aliasdir"
    cat > "$_seed_root/config/scratch-host.yaml" <<'CFGEOF'
schema_version: 1

host:
  hostname: scratch-host
  machine_id: "deadbeefdeedbeef"

protected_drives: []

tracks:
  - id: track-1
    role: main
    branch: main
    mount: /mnt/track1
  - id: track-2
    role: feature
    branch_pattern: "feature/*"
    mount: /mnt/track2
CFGEOF
    : > "$_seed_root/aliasdir/cooldowns.snapshot"
    : > "$_seed_root/aliasdir/events.jsonl"
}

# single-BIND fixture -- exercises the "expires" JSON key (triggers the
# pre-fix gawk fatal on RED_MODE=1's HEAD copy).
_seed_single_bind() {
    _t0=$(date +%s)
    printf '{"ts":%s,"iso":"x","event":"BIND","alias":"claude1","track":"track-1","worktree":"/mnt/track1","expires":"%s","pid":12345,"note":"n"}\n' \
        "$_t0" "$((_t0+900))" > "$1/aliasdir/events.jsonl"
}

# multi-event fixture + hand-computed expected result (GREEN happy-path oracle).
_seed_multi_event() {
    _t0=$(date +%s)
    cat > "$1/aliasdir/events.jsonl" <<EOF
{"ts":$((_t0)),"iso":"x","event":"BIND","alias":"claude1","track":"track-1","worktree":"/mnt/track1","expires":"$((_t0+900))","pid":100,"note":"n"}
{"ts":$((_t0+10)),"iso":"x","event":"BIND","alias":"claude2","track":"track-2","worktree":"/mnt/track2","expires":"$((_t0+910))","pid":200,"note":"n"}
{"ts":$((_t0+20)),"iso":"x","event":"FALLBACK","alias":"claude3","track":"track-1","worktree":"/mnt/track1","expires":"$((_t0+920))","pid":300,"note":"n"}
{"ts":$((_t0+30)),"iso":"x","event":"HEARTBEAT","alias":"claude2","track":"","worktree":"","expires":"$((_t0+930))","pid":0,"note":"n"}
{"ts":$((_t0+50)),"iso":"x","event":"UNBIND","alias":"claude2","track":"track-2","worktree":"","expires":"","pid":0,"note":"n"}
EOF
    printf '%s|%s|%s|%s|%s|%s|%s\n' "claude3" "track-1" "/mnt/track1" "300" "$((_t0+20))" "$((_t0+920))" "active" > "$1/expected_bind.txt"
}

run_iteration() {
    _iter="$1"
    _norm="$EV/normalized_m${RED_MODE}_iter${_iter}.txt"
    : > "$_norm"
    _reg="$WORK/reg_m${RED_MODE}_${_iter}"
    _seed_scratch "$_reg"

    if [ "$RED_MODE" = "1" ]; then
        _seed_single_bind "$_reg"
        # NOTE: the 6th pipe field is `_reap()`'s own TTL "expires" epoch --
        # `_reap()` runs UNCONDITIONALLY after cmd_reconcile's awk block
        # (independent of whether that awk step succeeded) and PRUNES any
        # row whose exp<=now, so the sentinel's expiry MUST be a genuine
        # future timestamp or `_reap()` itself (not the awk/mv short-circuit
        # under test) would drop it -- a test-fixture bug, not a defect in
        # the orchestrator (§11.4.6/§11.4.102: verified by direct
        # reproduction before writing this comment).
        _sentinel_exp=$(( $(date +%s) + 3600 ))
        printf 'sentinelalias|sentineltrack|sentinelworktree|0|0|%s|active\n' "$_sentinel_exp" > "$_reg/aliasdir/bindings.snapshot"
        _sentinel_before=$(cat "$_reg/aliasdir/bindings.snapshot")

        MT_SCRIPTS_DIR="$CONST_ROOT/scripts/multitrack" \
        MT_REPO_ROOT="$_reg" MT_CONFIG_DIR="$_reg/config" MT_CONFIG="$_reg/config/scratch-host.yaml" \
        MT_ALIAS_DIR="$_reg/aliasdir" MT_HOST="scratch-host" \
            bash "$PREFIX_COPY" reconcile > "$WORK/red_${_iter}.out" 2> "$WORK/red_${_iter}.err"
        _rc=$?
        _sentinel_after=$(cat "$_reg/aliasdir/bindings.snapshot" 2>/dev/null)

        if grep -q 'syntax error' "$WORK/red_${_iter}.err"; then
            pass "RED(a): pre-fix pinned copy's reconcile awk emits a genuine gawk syntax error" "$WORK/red_${_iter}.err"
            echo "RED_a_syntax_error=yes" >> "$_norm"
        else
            fail "RED(a): expected a gawk syntax error on the pre-fix copy, none seen" "$WORK/red_${_iter}.err"
            echo "RED_a_syntax_error=no" >> "$_norm"
        fi

        if [ "$_sentinel_after" = "$_sentinel_before" ]; then
            pass "RED(b): bindings.snapshot UNCHANGED (still the sentinel) -- no data loss despite the awk failure" "$_reg/aliasdir/bindings.snapshot"
            echo "RED_b_unchanged=yes" >> "$_norm"
        else
            fail "RED(b): bindings.snapshot changed unexpectedly (before=[$_sentinel_before] after=[$_sentinel_after])" "$_reg/aliasdir/bindings.snapshot"
            echo "RED_b_unchanged=no" >> "$_norm"
        fi

        if grep -qF 'RECONCILE: bindings snapshot rebuilt' "$WORK/red_${_iter}.out"; then
            pass "RED(c): the pre-fix primitive STILL prints the false-success 'RECONCILE: ... rebuilt' message despite the genuine awk failure (the PASS-bluff, captured)" "$WORK/red_${_iter}.out"
            echo "RED_c_false_success_message=yes" >> "$_norm"
        else
            fail "RED(c): expected the false-success message to still print on the pre-fix primitive, it did not" "$WORK/red_${_iter}.out"
            echo "RED_c_false_success_message=no" >> "$_norm"
        fi

        if [ "$_rc" = "0" ]; then
            pass "RED(d): cmd_reconcile returns rc=0 DESPITE the genuine, captured awk failure -- the specific bug under test, reproduced" "$WORK/red_${_iter}.err"
            echo "RED_d_rc_swallowed=yes rc=$_rc" >> "$_norm"
        else
            fail "RED(d): expected rc=0 (the swallowed-failure defect) on the pre-fix primitive, got rc=$_rc" "$WORK/red_${_iter}.err"
            echo "RED_d_rc_swallowed=no rc=$_rc" >> "$_norm"
        fi
        return 0
    fi

    # ---------------------------------------------------------------- GREEN ---
    if [ "$RUNNING_AS_ROOT" = "1" ]; then
        skip "GREEN(e): chmod-555 awk-failure fault injection" \
             "running as root -- directory permission checks are bypassed, a chmod-555 scratch dir would NOT genuinely deny write access, so this scenario cannot be honestly exercised here (§11.4.6)" \
             "n/a (informational)"
        echo "GREEN_e_failure_path=SKIPPED_ROOT" >> "$_norm"
    else
        _fail_reg="$WORK/fail_reg_${_iter}"
        _seed_scratch "$_fail_reg"
        _seed_single_bind "$_fail_reg"   # content is irrelevant here -- the fixed
                                          # awk program parses it fine; the FAILURE
                                          # is injected at the redirection layer.
        _prefail_exp=$(( $(date +%s) + 3600 ))
        printf 'prefailalias|prefailtrack|prefailworktree|1|2|%s|active\n' "$_prefail_exp" > "$_fail_reg/aliasdir/bindings.snapshot"
        _prefail_content=$(cat "$_fail_reg/aliasdir/bindings.snapshot")

        # prime bindings.snapshot/cooldowns/events/lock via one successful
        # reconcile FIRST (writable), THEN lock the directory read-only so
        # the NEXT reconcile's `awk ... > "$BIND.tmp.$$"` genuinely fails to
        # create its tmp file (EACCES) -- a real, source-agnostic pipeline
        # failure, independent of the (already-fixed) exp/xp gawk quirk.
        MT_SCRIPTS_DIR="$CONST_ROOT/scripts/multitrack" \
        MT_REPO_ROOT="$_fail_reg" MT_CONFIG_DIR="$_fail_reg/config" MT_CONFIG="$_fail_reg/config/scratch-host.yaml" \
        MT_ALIAS_DIR="$_fail_reg/aliasdir" MT_HOST="scratch-host" \
            bash "$ORCH" reconcile >/dev/null 2>&1 || true
        printf '%s' "$_prefail_content" > "$_fail_reg/aliasdir/bindings.snapshot"
        chmod 555 "$_fail_reg/aliasdir"

        MT_SCRIPTS_DIR="$CONST_ROOT/scripts/multitrack" \
        MT_REPO_ROOT="$_fail_reg" MT_CONFIG_DIR="$_fail_reg/config" MT_CONFIG="$_fail_reg/config/scratch-host.yaml" \
        MT_ALIAS_DIR="$_fail_reg/aliasdir" MT_HOST="scratch-host" \
            bash "$ORCH" reconcile > "$WORK/fail_${_iter}.out" 2> "$WORK/fail_${_iter}.err"
        _fail_rc=$?
        chmod u+rwx "$_fail_reg/aliasdir" 2>/dev/null || true
        _postfail_content=$(cat "$_fail_reg/aliasdir/bindings.snapshot" 2>/dev/null)

        if [ "$_fail_rc" != "0" ]; then
            pass "GREEN(e1): reconcile returns NON-ZERO on a genuine awk-pipeline failure (rc=$_fail_rc)" "$WORK/fail_${_iter}.err"
            echo "GREEN_e1_rc_nonzero=yes rc=$_fail_rc" >> "$_norm"
        else
            fail "GREEN(e1): expected non-zero rc on injected failure, got rc=0" "$WORK/fail_${_iter}.err"
            echo "GREEN_e1_rc_nonzero=no rc=$_fail_rc" >> "$_norm"
        fi

        if grep -qF 'RECONCILE: bindings snapshot rebuilt' "$WORK/fail_${_iter}.out"; then
            fail "GREEN(e2): false-success message unexpectedly printed on a genuine failure" "$WORK/fail_${_iter}.out"
            echo "GREEN_e2_no_false_success=no" >> "$_norm"
        else
            pass "GREEN(e2): the false-success 'RECONCILE: ... rebuilt' message is NEVER printed on a genuine failure" "$WORK/fail_${_iter}.out"
            echo "GREEN_e2_no_false_success=yes" >> "$_norm"
        fi

        if grep -qF 'ERECONCILE:' "$WORK/fail_${_iter}.err"; then
            pass "GREEN(e3): a clearly-labelled ERECONCILE: error is printed to stderr on failure" "$WORK/fail_${_iter}.err"
            echo "GREEN_e3_labelled_error=yes" >> "$_norm"
        else
            fail "GREEN(e3): expected an ERECONCILE: labelled error on stderr" "$WORK/fail_${_iter}.err"
            echo "GREEN_e3_labelled_error=no" >> "$_norm"
        fi

        if [ "$_postfail_content" = "$_prefail_content" ]; then
            pass "GREEN(e4): bindings.snapshot UNCHANGED after the failure (no clobber, no data loss)" "$_fail_reg/aliasdir/bindings.snapshot"
            echo "GREEN_e4_unchanged=yes" >> "$_norm"
        else
            fail "GREEN(e4): bindings.snapshot changed unexpectedly after a failed reconcile (before=[$_prefail_content] after=[$_postfail_content])" "$_fail_reg/aliasdir/bindings.snapshot"
            echo "GREEN_e4_unchanged=no" >> "$_norm"
        fi
    fi

    # --- GREEN(f): happy path unchanged ------------------------------------
    _ok_reg="$WORK/ok_reg_${_iter}"
    _seed_scratch "$_ok_reg"
    _seed_multi_event "$_ok_reg"
    MT_SCRIPTS_DIR="$CONST_ROOT/scripts/multitrack" \
    MT_REPO_ROOT="$_ok_reg" MT_CONFIG_DIR="$_ok_reg/config" MT_CONFIG="$_ok_reg/config/scratch-host.yaml" \
    MT_ALIAS_DIR="$_ok_reg/aliasdir" MT_HOST="scratch-host" \
        bash "$ORCH" reconcile > "$WORK/ok_${_iter}.out" 2> "$WORK/ok_${_iter}.err"
    _ok_rc=$?
    if [ "$_ok_rc" = "0" ] && grep -qF 'RECONCILE: bindings snapshot rebuilt' "$WORK/ok_${_iter}.out" \
       && diff -q "$_ok_reg/aliasdir/bindings.snapshot" "$_ok_reg/expected_bind.txt" >/dev/null 2>&1; then
        pass "GREEN(f): happy path unchanged -- rc=0, success message prints, bindings.snapshot BYTE-IDENTICAL to hand-computed expected" "$_ok_reg/aliasdir/bindings.snapshot"
        echo "GREEN_f_happy_path=ok rc=$_ok_rc" >> "$_norm"
    else
        fail "GREEN(f): happy-path regressed (rc=$_ok_rc)" "$WORK/ok_${_iter}.out"
        echo "GREEN_f_happy_path=REGRESSED rc=$_ok_rc" >> "$_norm"
    fi

    # --- GREEN(g): sibling no-regression battery ---------------------------
    _sib="$WORK/sib_${_iter}"
    _seed_scratch "$_sib"
    export MT_SCRIPTS_DIR="$CONST_ROOT/scripts/multitrack"
    export MT_REPO_ROOT="$_sib" MT_CONFIG_DIR="$_sib/config" MT_CONFIG="$_sib/config/scratch-host.yaml" \
           MT_ALIAS_DIR="$_sib/aliasdir" MT_HOST="scratch-host"
    _sib_ok=1
    bash "$ORCH" bind --track track-1 --alias claude1 --worktree /mnt/track1 >/dev/null 2>"$WORK/sib_bind_${_iter}.err" || _sib_ok=0
    bash "$ORCH" heartbeat --alias claude1 >/dev/null 2>"$WORK/sib_hb_${_iter}.err" || _sib_ok=0
    bash "$ORCH" fallback --track track-1 --alias claude2 --worktree /mnt/track1 --reason test >/dev/null 2>"$WORK/sib_fb_${_iter}.err" || _sib_ok=0
    bash "$ORCH" status >/dev/null 2>"$WORK/sib_status_${_iter}.err" || _sib_ok=0
    bash "$ORCH" unbind --track track-1 >/dev/null 2>"$WORK/sib_unbind_${_iter}.err" || _sib_ok=0
    bash "$ORCH" reap >/dev/null 2>"$WORK/sib_reap_${_iter}.err" || _sib_ok=0
    unset MT_SCRIPTS_DIR MT_REPO_ROOT MT_CONFIG_DIR MT_CONFIG MT_ALIAS_DIR MT_HOST
    if [ "$_sib_ok" = "1" ]; then
        pass "GREEN(g): sibling subcommands (bind/heartbeat/fallback/status/unbind/reap) all still exit 0 -- no collateral regression" "$_sib/aliasdir"
        echo "GREEN_g_siblings_ok=yes" >> "$_norm"
    else
        fail "GREEN(g): a sibling subcommand regressed" "$WORK"
        echo "GREEN_g_siblings_ok=no" >> "$_norm"
    fi
}

for RED_MODE in $PHASES; do
    for _i in 1 2 3; do run_iteration "$_i"; done

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
