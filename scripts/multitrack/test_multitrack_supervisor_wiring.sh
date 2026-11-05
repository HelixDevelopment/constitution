#!/bin/sh
# =============================================================================
# test_multitrack_supervisor_wiring.sh — RB-FIX3 (I-a) permanent regression
#     guard: an independent code review of RB-05/RB-07/RB-08
#     (qa-results/multitrack/RB_COMBINED_REVIEW_report.md) found that
#     multitrack_supervisor.sh's `snapshot`/`watch` primitives (RB-07) were
#     built + tested but reachable from NOTHING except the supervisor's own
#     test: `grep -rn multitrack_supervisor` across the whole tree outside
#     the file + its own test returned ZERO hits -- no wrapper, no
#     orchestrator, no bootstrap step, no doc reference ever called
#     `snapshot`/`watch`. In production, NOTHING ever populated
#     ruler_state.json and NO watchdog process ever ran `watch` -- the
#     "crash-resilient ruler" claim in the file's own header docstring was
#     aspirational.
# -----------------------------------------------------------------------------
# The fix (this PWU) wires TWO real callers, minimally + non-breakingly:
#   (1) multitrack_sessions.sh (RB-05) calls the new
#       `_mts_supervisor_snapshot` helper right after EVERY `_mts_snapshot`
#       (i.e. on every genuine ruler-state change: `spawn` binding a track,
#       `stop` marking one stopped) -- guarded (never a hard dependency;
#       never fails the primary operation) and NEVER guesses a repo root of
#       its own: it engages ONLY when the caller has already established a
#       real durable-state target (MT_REPO_ROOT and/or MT_RULER_STATE_DIR
#       set -- exactly what multitrack_bootstrap.sh's real
#       `export MT_REPO_ROOT="$PROJECT_ROOT"` already does), or an explicit
#       MT_SUPERVISOR_SNAPSHOT_FORCE=1 (this test's own proof knob). Without
#       this guard, a bare/test invocation of multitrack_sessions.sh (which
#       lives INSIDE the constitution submodule -- its OWN `.git` -- would
#       make the supervisor's `git rev-parse --show-toplevel` fallback
#       resolve to the SUBMODULE's root, silently writing an untracked
#       ruler_state.json into a tree other tracks may be concurrently
#       working in, §11.4.84) -- so the wiring is opt-engaged by real
#       context, never a guessed default (§11.4.6).
#   (2) multitrack_bootstrap.sh (RB-08) gains an OPT-IN step 6 that starts
#       `multitrack_supervisor.sh watch` as a backgrounded, pgrep-guarded
#       (idempotent) daemon when MT_SUPERVISOR_WATCH_ENABLE=1 -- default OFF,
#       so bootstrap's existing default behaviour (rc, symlink, config,
#       orchestrator state) is byte-for-byte unchanged for every caller that
#       has not opted in (§11.4.1 non-breaking; proven explicitly below).
#
# Purpose (§11.4.114/§11.4.115 RED-on-the-broken-artifact + polarity switch):
#   RED_MODE=1 — reproduces the exact review finding against the REAL
#     git-history artifacts (never synthetic), extracted at the PINNED commit
#     RED_PIN (the parent of 55998fb, which wired the supervisor in). It is
#     NEVER `git show HEAD:`: once the fix is committed HEAD holds the FIXED
#     copy, so a HEAD-built RED can never go RED on a committed tree (redpin
#     class, §11.4.115/§11.4.292(E)); an unreachable pin FAILs closed:
#       (A) grep census against the pin: the pre-fix copy of
#           multitrack_sessions.sh (a REAL, tracked, previously-shipped
#           artifact) contains ZERO references to "multitrack_supervisor";
#           multitrack_bootstrap.sh does not exist at the pin AT ALL
#           (`git show <pin>:...` genuinely fails) -- so it
#           definitionally invoked nothing. This is the review's own
#           reproduction method (a grep census), run mechanically against
#           git history rather than merely quoted.
#       (B) functional: driving a REAL mocked `spawn` through the pinned copy
#           of multitrack_sessions.sh, with a scratch MT_RULER_STATE_DIR
#           that WOULD receive a durable snapshot if anything wired it,
#           leaves that directory's ruler_state.json genuinely ABSENT --
#           the concrete, end-to-end manifestation of "nothing calls
#           snapshot", not merely a textual absence.
#   RED_MODE=0 (GREEN) — drives the CURRENT (fixed) working-tree scripts and
#     proves, end-to-end, both wiring points + the non-breaking guarantee:
#       (a) the SAME grep census now finds >=1 hit in sessions.sh AND >=1 hit
#           in bootstrap.sh (excluding multitrack_supervisor.sh's own file,
#           its dedicated test, and the Monday-dryrun SIMULATION harness --
#           a test file, not production code, per the review's own exclusion
#           convention).
#       (b) `spawn` (real mock, MT_RULER_STATE_DIR + MT_REPO_ROOT set to a
#           scratch project context -- mirroring what multitrack_bootstrap.sh
#           already does in real use) genuinely populates ruler_state.json
#           with the spawned track's alias/session_id, cross-checked against
#           the independently-read tracks/<track>.json (never trusting only
#           the CLI's own stdout).
#       (c) `stop` on that same track updates ruler_state.json's status for
#           it to "stopped" (both wiring points fire, not just spawn).
#       (d) DEFAULT-SAFE proof: a BARE spawn (mirroring
#           test_multitrack_sessions_spawn.sh's own house style -- NEITHER
#           MT_REPO_ROOT NOR MT_RULER_STATE_DIR set) leaves the constitution
#           submodule's own working tree free of any new untracked
#           `.ws_state` artifact -- proving the guard never guesses a repo
#           root of its own (§11.4.6) and never pollutes a tree concurrent
#           tracks are working in (§11.4.84).
#       (e) bootstrap, opt-in step 6 OFF (default, MT_SUPERVISOR_WATCH_ENABLE
#           unset): NO watch daemon process starts (pgrep census empty) --
#           bootstrap's non-breaking default is proven, not assumed.
#       (f) bootstrap, opt-in step 6 ON (MT_SUPERVISOR_WATCH_ENABLE=1): a
#           REAL watch daemon starts (found via the EXACT pgrep signature
#           bootstrap itself uses for its idempotency guard), performs >= 1
#           genuine loop iteration (its own log shows a "WATCH:" line), and
#           is killed cleanly by this test (never left as an orphan --
#           §11.4.14).
#   Both modes run their battery 3 times (§11.4.50 determinism) and assert
#   the normalized (PID/timestamp-free) results are byte-identical across
#   all 3 iterations.
#
# Usage:
#   sh constitution/scripts/multitrack/test_multitrack_supervisor_wiring.sh              # RED then GREEN
#   RED_MODE=1 sh constitution/scripts/multitrack/test_multitrack_supervisor_wiring.sh   # RED only
#   RED_MODE=0 sh constitution/scripts/multitrack/test_multitrack_supervisor_wiring.sh   # GREEN only
#   (default RED_MODE=both if unset)
#
# Inputs: RED_MODE (both|1|0, default both); optional MT_TEST_PROJECT_ROOT
#   (outer project root, where the RB-05 mock fixture lives; default: the git
#   toplevel above the constitution checkout); optional MT_TEST_MOCK_CLAUDE
#   (path to the RB-05 mock); optional MT_SUPWIRE_TEST_EVIDENCE_DIR override.
#
# Environment dependency (honest SKIP, §11.4.3): the RB-05 mock lives in the
#   CONSUMER project (scripts/multitrack/rb05_fixtures/mock_claude.sh). With no
#   reachable mock the test exits 77 with "reason=rb05_mock_absent" (decided
#   before any evidence directory is created) instead of a false RED. The
#   evidence default is <project>/qa-results, else <constitution>/qa-results;
#   it is never the bare parent directory of the checkout.
#
# Outputs: PASS/FAIL/SKIP lines on stdout + $EV/results.log; per-iteration
#   captured logs + normalized-result files under $EV. Exit 0 iff FAIL count
#   is 0.
#
# Side-effects: creates + removes ONE scratch tmp dir per iteration (scratch
#   MT_RULER_STATE_DIR / MT_SESSIONS_DIR / PROJECT_ROOT / MT_ALIAS_DIR --
#   NEVER the live host's real repo state); backgrounds >=1 short-lived
#   `multitrack_supervisor.sh watch` daemon per GREEN iteration, ALWAYS
#   explicitly killed by its captured pid (both at the point of assertion
#   AND again, unconditionally, in a `trap ... EXIT INT TERM` cleanup,
#   §11.4.14); NEVER touches a real device, a real claude account, or this
#   project's real config/multitrack/<hostname>.yaml.
#
# Dependencies: sh (POSIX), bash (bootstrap.sh/orchestrator require it), git,
#   date, mktemp, diff, sed, grep, cut, kill, pgrep.
#
# Cross-references:
#   qa-results/multitrack/RB_COMBINED_REVIEW_report.md (the finding this test
#     closes -- Important finding on multitrack_supervisor.sh not being
#     wired into any real invocation path);
#   constitution/scripts/multitrack/multitrack_sessions.sh (RB-05, fix site 1);
#   constitution/scripts/multitrack/multitrack_bootstrap.sh (RB-08, fix site 2);
#   constitution/scripts/multitrack/multitrack_supervisor.sh (RB-07, unit
#     wired in, unmodified by this fix);
#   constitution/scripts/multitrack/test_multitrack_supervisor.sh (RB-07's
#     OWN unit test -- proves the primitive works in isolation; THIS file
#     proves something REAL now calls it);
#   scripts/multitrack/rb05_fixtures/mock_claude.sh (READ, never modified);
#   scripts/multitrack/test_multitrack_sessions_spawn.sh (house style this
#     file mirrors: self-contained CONST_ROOT/REPO_ROOT derivation, local
#     pass/fail/skip helpers, normalized-iteration determinism diff);
#   §11.4.1 (non-breaking); §11.4.6 (no-guessing -- the engagement gate is
#   explicit context, never an invented repo root); §11.4.14 (cleanup);
#   §11.4.43/§11.4.115 (RED->GREEN polarity); §11.4.50 (determinism); §11.4.67
#   (sh/bash -n clean); §11.4.74 (extend-not-reinvent -- the watch-daemon
#   idempotency guard mirrors multitrack_cwd_hook.sh's own pgrep idiom);
#   §11.4.84 (working-tree quiescence -- the default-safe proof).
# =============================================================================

set -u

MT_TEST_SELF=$0
case "$MT_TEST_SELF" in
    */*) MT_TEST_DIR=${MT_TEST_SELF%/*} ;;
    *)   MT_TEST_DIR=. ;;
esac

# self-contained derivation -- this file lives INSIDE the constitution
# submodule, which has its OWN .git; `git rev-parse --show-toplevel` from
# here correctly resolves to the SUBMODULE root (CONST_ROOT), never the
# outer project (mirrors test_multitrack_orchestrator_reconcile.sh /
# test_multitrack_supervisor.sh's own documented idiom).
_supwire_const_root() {
    if [ -n "${MT_TEST_CONST_ROOT:-}" ]; then printf '%s\n' "$MT_TEST_CONST_ROOT"; return 0; fi
    ( cd "$MT_TEST_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
CONST_ROOT=$(_supwire_const_root)
[ -n "$CONST_ROOT" ] || { echo "FATAL: no constitution submodule root (git toplevel / \$MT_TEST_CONST_ROOT)" >&2; exit 90; }
# outer project = the git toplevel ABOVE the constitution checkout (or
# MT_TEST_PROJECT_ROOT); empty when this checkout stands alone. Never the bare
# parent directory: that is not a project and must not receive evidence.
_supwire_project_root() {
    if [ -n "${MT_TEST_PROJECT_ROOT:-}" ]; then printf '%s\n' "$MT_TEST_PROJECT_ROOT"; return 0; fi
    ( cd "$CONST_ROOT/.." 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
REPO_ROOT=$(_supwire_project_root)

SESSIONS="$CONST_ROOT/scripts/multitrack/multitrack_sessions.sh"
BOOT="$CONST_ROOT/scripts/multitrack/multitrack_bootstrap.sh"
SUP="$CONST_ROOT/scripts/multitrack/multitrack_supervisor.sh"
CWH="$CONST_ROOT/scripts/multitrack/multitrack_cwd_hook.sh"
if [ -n "${MT_TEST_MOCK_CLAUDE:-}" ]; then
    MOCK=$MT_TEST_MOCK_CLAUDE
elif [ -n "$REPO_ROOT" ]; then
    MOCK="$REPO_ROOT/scripts/multitrack/rb05_fixtures/mock_claude.sh"
else
    MOCK=""
fi
if [ -z "$MOCK" ] || [ ! -f "$MOCK" ]; then
    echo "SKIP: the RB-05 mock claude is not reachable (no outer project root above $CONST_ROOT, no MT_TEST_MOCK_CLAUDE; looked for '${MOCK:-<none>}'); this test needs the consumer fixture scripts/multitrack/rb05_fixtures/mock_claude.sh reason=rb05_mock_absent"
    exit 77
fi

for _f in "$SESSIONS" "$BOOT" "$SUP" "$CWH" "$MOCK"; do
    [ -f "$_f" ] || { echo "FATAL: required file not found: $_f" >&2; exit 91; }
done
sh -n "$SESSIONS" 2>/dev/null   || { echo "FATAL: $SESSIONS fails sh -n" >&2; exit 92; }
sh -n "$SUP" 2>/dev/null        || { echo "FATAL: $SUP fails sh -n" >&2; exit 92; }
bash -n "$BOOT" 2>/dev/null     || { echo "FATAL: $BOOT fails bash -n" >&2; exit 92; }

RED_MODE="${RED_MODE:-both}"
case "$RED_MODE" in
    both) PHASES="1 0" ;;
    1)    PHASES="1" ;;
    0)    PHASES="0" ;;
    *)    echo "FATAL: RED_MODE must be both, 1 or 0 (got '$RED_MODE')" >&2; exit 2 ;;
esac
REQ_MODE=$RED_MODE
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
EV="${MT_SUPWIRE_TEST_EVIDENCE_DIR:-${REPO_ROOT:-$CONST_ROOT}/qa-results/multitrack/supwire_test_${RUN_TS}-$$}"
mkdir -p "$EV"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_supwire_test.XXXXXX")
PIDS_FILE="$WORK/pids_to_kill"
: > "$PIDS_FILE"
cleanup() {
    if [ -f "$PIDS_FILE" ]; then
        while IFS= read -r _p; do
            [ -n "$_p" ] || continue
            kill "$_p" 2>/dev/null || true
        done < "$PIDS_FILE"
        sleep 1 2>/dev/null || true
        while IFS= read -r _p; do
            [ -n "$_p" ] || continue
            kill -9 "$_p" 2>/dev/null || true
        done < "$PIDS_FILE"
    fi
    rm -rf "$WORK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s (%s) [evidence: %s]\n' "$1" "$2" "$3" | tee -a "$EV/results.log"; }

# extract the PRE-FIX copy of sessions.sh at the PINNED commit RED_PIN, once,
# into its OWN scratch directory alongside its sibling scripts
# (multitrack_host_budget.sh / multitrack_resolve_worktree.sh) taken from the
# SAME pin, so the pre-fix world is consistent (the siblings have changed
# since the pin, and today's copies are not what the pre-fix copy shipped
# with) -- sibling resolution inside
# multitrack_sessions.sh is directory-relative (`$MTS_DIR/multitrack_host_
# budget.sh`, MTS_DIR derived from `$0`'s dirname at runtime), so a bare
# extracted copy sitting alone in $WORK cannot find its budget guard and
# would REFUSE (rc=4, "guard missing") for a reason that has NOTHING to do
# with the defect under test here (§11.4.6 -- do not let an unrelated
# resolution gap masquerade as the reproduced defect).
PREFIX_DIR="$WORK/prefix_engine"
mkdir -p "$PREFIX_DIR"
PREFIX_SESSIONS="$PREFIX_DIR/multitrack_sessions.sh"
# --- RED artifact pin (§11.4.114/§11.4.115, redpin class) -------------------
# The RED artifact is the pre-fix copy at a FIXED commit, never `git show
# HEAD:` (HEAD holds the FIXED copy once the fix is committed). RED_PIN is the
# parent of 55998fb, which wired multitrack_supervisor into sessions.sh and
# added multitrack_bootstrap.sh. Assertions: the pin is reachable (else FAIL
# closed); the pinned sessions.sh lacks every 'multitrack_supervisor'
# reference; the CURRENT sessions.sh has the 'MTS_SUPERVISOR=' wiring
# (control needle).
RED_PIN=e60cbde2e33e7d0542a937331763f6be7e739c9a
RED_PATH=scripts/multitrack/multitrack_sessions.sh
FIX_NEEDLE='MTS_SUPERVISOR='
_cur_fix=$(grep -cF -- "$FIX_NEEDLE" "$SESSIONS")
if [ "${_cur_fix:-0}" -ge 1 ]; then
    pass "control: the CURRENT $RED_PATH carries the fix ('$FIX_NEEDLE' x$_cur_fix)" "$SESSIONS"
else
    fail "control: the CURRENT $RED_PATH lost the fix ('$FIX_NEEDLE' x${_cur_fix:-0})" "$SESSIONS"
fi
BOOTSTRAP_ABSENT_AT_PIN=0
case " $PHASES " in *" 1 "*)
    if ! git -C "$CONST_ROOT" cat-file -e "$RED_PIN^{commit}" 2>/dev/null; then
        echo "FAIL: RED pin $RED_PIN is not reachable from $CONST_ROOT (shallow clone?) -- the RED cannot be reproduced; refusing to pass (§11.4.6)" >&2
        exit 93
    fi
    for _sib in multitrack_sessions.sh multitrack_host_budget.sh multitrack_resolve_worktree.sh; do
        if ! git -C "$CONST_ROOT" show "$RED_PIN:scripts/multitrack/$_sib" > "$PREFIX_DIR/$_sib" 2>/dev/null; then
            echo "FAIL: could not extract scripts/multitrack/$_sib at RED pin $RED_PIN from $CONST_ROOT" >&2
            exit 93
        fi
    done
    if grep -qF 'multitrack_supervisor' "$PREFIX_SESSIONS" || ! grep -qF 'cmd_spawn' "$PREFIX_SESSIONS"; then
        echo "FAIL: the copy at RED pin $RED_PIN is not the pre-fix artifact (needs cmd_spawn and no 'multitrack_supervisor') -- cannot honestly claim RED reproduction (§11.4.6)" >&2
        exit 94
    fi
    pass "RED pin $RED_PIN resolves and its $RED_PATH is the pre-fix artifact (cmd_spawn present, no supervisor wiring)" "$PREFIX_SESSIONS"
    if git -C "$CONST_ROOT" show "$RED_PIN:scripts/multitrack/multitrack_bootstrap.sh" > "$WORK/boot_pin_probe" 2>/dev/null; then
        BOOTSTRAP_ABSENT_AT_PIN=0
    else
        BOOTSTRAP_ABSENT_AT_PIN=1
    fi
;; esac

# HOST_SAFETY_LIB stub (mirrors test_multitrack_sessions_spawn.sh's $HSS) --
# deterministic §12.6 budget arithmetic, never the real host's /proc/meminfo.
HSS="$WORK/hss.sh"
printf 'host_safe_parallel_jobs() { echo 4; }\nHOST_SAFETY_BUDGET_GB=99\n' > "$HSS"

FAKEBIN="$WORK/bin"; mkdir -p "$FAKEBIN"
ln -sf "$MOCK" "$FAKEBIN/claude"

PIN_ID_BASE="RB-SUPWIRE-$$"

run_iteration() {
    _iter="$1"
    _norm="$EV/normalized_m${RED_MODE}_iter${_iter}.txt"
    : > "$_norm"

    if [ "$RED_MODE" = "1" ]; then
        # --- RED(A): grep census against the pinned pre-fix copy --------------
        _headhit=$(grep -c 'multitrack_supervisor' "$PREFIX_SESSIONS" 2>/dev/null); _headhit=${_headhit:-0}
        if [ "${_headhit:-0}" -eq 0 ] && [ "$BOOTSTRAP_ABSENT_AT_PIN" = "1" ]; then
            pass "RED(A): pinned pre-fix sessions.sh has ZERO 'multitrack_supervisor' references AND bootstrap.sh is genuinely absent at the pin (definitionally invokes nothing)" "$PREFIX_SESSIONS"
            echo "RED_A_census=defect_present headhit=$_headhit boot_absent=$BOOTSTRAP_ABSENT_AT_PIN" >> "$_norm"
        else
            fail "RED(A): expected zero hits at the pin + bootstrap absent at the pin, got headhit=$_headhit boot_absent=$BOOTSTRAP_ABSENT_AT_PIN" "$PREFIX_SESSIONS"
            echo "RED_A_census=UNEXPECTED headhit=$_headhit boot_absent=$BOOTSTRAP_ABSENT_AT_PIN" >> "$_norm"
        fi

        # --- RED(B): functional -- the pinned sessions.sh spawn never populates
        #     ruler_state.json even when a durable target IS available. ------
        _reg="$WORK/red_reg_$_iter"; _cwd="$WORK/red_wt_$_iter"; mkdir -p "$_cwd"
        _rulerdir="$WORK/red_ruler_$_iter"
        _pin="${PIN_ID_BASE}-red-$_iter"
        MT_SESSIONS_DIR="$_reg" HOST_SAFETY_LIB="$HSS" MT_WORKER_CWD="$_cwd" \
            MT_RULER_STATE_DIR="$_rulerdir" MT_SUPERVISOR_SNAPSHOT_FORCE=1 \
            MOCK_CLAUDE_SESSION_ID="$_pin" MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_IS_ERROR=false \
            PATH="$FAKEBIN:$PATH" \
            sh "$PREFIX_SESSIONS" spawn claude1 >"$WORK/red_spawn_$_iter.out" 2>&1
        _redspawn_rc=$?
        if [ "$_redspawn_rc" = "0" ] && [ ! -e "$_rulerdir/ruler_state.json" ]; then
            pass "RED(B): a real (mocked) spawn via the pinned copy succeeds (rc=0) but ruler_state.json stays genuinely ABSENT (nothing calls snapshot)" "$_rulerdir"
            echo "RED_B_ruler_state=ABSENT spawn_rc=$_redspawn_rc" >> "$_norm"
        else
            fail "RED(B): expected spawn rc=0 + ruler_state.json absent, got spawn_rc=$_redspawn_rc exists=$([ -e "$_rulerdir/ruler_state.json" ] && echo yes || echo no)" "$WORK/red_spawn_$_iter.out"
            echo "RED_B_ruler_state=UNEXPECTED spawn_rc=$_redspawn_rc" >> "$_norm"
        fi
        return 0
    fi

    # =========================================================== GREEN =====
    # (a) grep census against the CURRENT (fixed) tree.
    _sesshit=$(grep -c 'multitrack_supervisor' "$SESSIONS" 2>/dev/null); _sesshit=${_sesshit:-0}
    _boothit=$(grep -c 'multitrack_supervisor' "$BOOT" 2>/dev/null); _boothit=${_boothit:-0}
    if [ "${_sesshit:-0}" -gt 0 ] && [ "${_boothit:-0}" -gt 0 ]; then
        pass "GREEN(a): current sessions.sh ($_sesshit hits) AND bootstrap.sh ($_boothit hits) now reference multitrack_supervisor (real callers wired)" "$SESSIONS"
        echo "GREEN_a_census=wired sesshit=$_sesshit boothit=$_boothit" >> "$_norm"
    else
        fail "GREEN(a): expected >=1 hit in both sessions.sh and bootstrap.sh, got sesshit=$_sesshit boothit=$_boothit" "$SESSIONS"
        echo "GREEN_a_census=UNWIRED sesshit=$_sesshit boothit=$_boothit" >> "$_norm"
    fi

    # (b) functional: real spawn populates ruler_state.json.
    _greg="$WORK/green_reg_$_iter"; _gcwd="$WORK/green_wt_$_iter"; mkdir -p "$_gcwd"
    _gruler="$WORK/green_ruler_$_iter"
    _gproot="$WORK/green_proot_$_iter"; mkdir -p "$_gproot"
    _gpin="${PIN_ID_BASE}-green-$_iter"
    MT_SESSIONS_DIR="$_greg" HOST_SAFETY_LIB="$HSS" MT_WORKER_CWD="$_gcwd" \
        MT_REPO_ROOT="$_gproot" MT_RULER_STATE_DIR="$_gruler" \
        MOCK_CLAUDE_SESSION_ID="$_gpin" MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_IS_ERROR=false \
        PATH="$FAKEBIN:$PATH" \
        sh "$SESSIONS" spawn claude1 >"$WORK/green_spawn_$_iter.out" 2>&1
    _gspawn_rc=$?
    _gtracksid=$(grep '"session_id"' "$_greg/tracks/claude1.json" 2>/dev/null | sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p' | head -n1)
    _grulercontent=""
    [ -f "$_gruler/ruler_state.json" ] && _grulercontent=$(cat "$_gruler/ruler_state.json")
    if [ "$_gspawn_rc" = "0" ] && [ "$_gtracksid" = "$_gpin" ] \
       && printf '%s' "$_grulercontent" | grep -qF "\"track\":\"claude1\"" \
       && printf '%s' "$_grulercontent" | grep -qF "\"session_id\":\"$_gpin\""; then
        pass "GREEN(b): real spawn populates ruler_state.json for track=claude1 session_id=$_gpin (cross-checked against the independently-read tracks/claude1.json)" "$_gruler/ruler_state.json"
        echo "GREEN_b_spawn=WIRED rc=$_gspawn_rc" >> "$_norm"
    else
        fail "GREEN(b): spawn_rc=$_gspawn_rc tracks_sid=$_gtracksid ruler_content=[$_grulercontent]" "$WORK/green_spawn_$_iter.out"
        echo "GREEN_b_spawn=UNEXPECTED rc=$_gspawn_rc" >> "$_norm"
    fi

    # (c) functional: stop updates ruler_state.json's status for the track.
    MT_SESSIONS_DIR="$_greg" HOST_SAFETY_LIB="$HSS" \
        MT_REPO_ROOT="$_gproot" MT_RULER_STATE_DIR="$_gruler" \
        PATH="$FAKEBIN:$PATH" \
        sh "$SESSIONS" stop claude1 >"$WORK/green_stop_$_iter.out" 2>&1
    _gstop_rc=$?
    _grulercontent2=""
    [ -f "$_gruler/ruler_state.json" ] && _grulercontent2=$(cat "$_gruler/ruler_state.json")
    if [ "$_gstop_rc" = "0" ] && printf '%s' "$_grulercontent2" | grep -qF "\"track\":\"claude1\"" \
       && printf '%s' "$_grulercontent2" | grep -qE '"last_verdict":"stopped"'; then
        pass "GREEN(c): stop updates the SAME track's ruler_state.json entry to status=stopped (both wiring points fire)" "$_gruler/ruler_state.json"
        echo "GREEN_c_stop=WIRED rc=$_gstop_rc" >> "$_norm"
    else
        fail "GREEN(c): stop_rc=$_gstop_rc ruler_content=[$_grulercontent2]" "$WORK/green_stop_$_iter.out"
        echo "GREEN_c_stop=UNEXPECTED rc=$_gstop_rc" >> "$_norm"
    fi

    # (d) DEFAULT-SAFE: a BARE spawn (no MT_REPO_ROOT, no MT_RULER_STATE_DIR)
    #     must leave the constitution submodule's own tree free of any new
    #     untracked .ws_state artifact (never guess a repo root, §11.4.6/.84).
    _pre_status=$(git -C "$CONST_ROOT" status --porcelain -- .ws_state 2>/dev/null)
    _dreg="$WORK/default_reg_$_iter"; _dcwd="$WORK/default_wt_$_iter"; mkdir -p "$_dcwd"
    _dpin="${PIN_ID_BASE}-default-$_iter"
    MT_SESSIONS_DIR="$_dreg" HOST_SAFETY_LIB="$HSS" MT_WORKER_CWD="$_dcwd" \
        MOCK_CLAUDE_SESSION_ID="$_dpin" MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_IS_ERROR=false \
        PATH="$FAKEBIN:$PATH" \
        sh "$SESSIONS" spawn claude1 >"$WORK/default_spawn_$_iter.out" 2>&1
    _post_status=$(git -C "$CONST_ROOT" status --porcelain -- .ws_state 2>/dev/null)
    if [ "$_pre_status" = "$_post_status" ] && [ -z "$_post_status" ]; then
        pass "GREEN(d): a BARE spawn (no MT_REPO_ROOT/MT_RULER_STATE_DIR) leaves the constitution submodule's own tree free of any new .ws_state artifact (default-safe, no guessed repo root)" "$CONST_ROOT"
        echo "GREEN_d_default_safe=CLEAN" >> "$_norm"
    else
        fail "GREEN(d): constitution submodule tree changed after a bare spawn (pre=[$_pre_status] post=[$_post_status])" "$CONST_ROOT"
        echo "GREEN_d_default_safe=DIRTY" >> "$_norm"
    fi

    # (e) bootstrap opt-in OFF (default) -> NO watch daemon starts.
    #     Fixture mirrors test_multitrack_bootstrap.sh's own PROVEN-working
    #     shape exactly (schema_version 1, main+feature tracks, a
    #     never-matching fixture drive serial -- no lsblk dependency, no
    #     real hardware, fully portable, §11.4.3).
    _eproot="$WORK/boot_off_proot_$_iter"; mkdir -p "$_eproot"
    _ehook="$WORK/boot_off_home_$_iter/.local/bin/claude-cwd-hook"
    _ealias="$WORK/boot_off_alias_$_iter"
    _efixture="$WORK/boot_off_fixture_$_iter.yaml"
    cat > "$_efixture" <<FIXEOF
schema_version: 1
host:
  hostname: "supwire-test-host-$_iter"
tracks:
  - id: track-1
    role: main
    mount: "/tmp/supwire-nonexistent-track1-$_iter"
  - id: track-2
    role: feature
    drive_serial: "SUPWIRE-FIXTURE-SERIAL-NOPE"
    mount: "/tmp/supwire-nonexistent-track2-$_iter"
FIXEOF
    _eintv="99871$_iter"
    CMA_CWD_HOOK="$_ehook" MT_CONFIG="$_efixture" MT_ALIAS_DIR="$_ealias" \
        MT_REPO_ROOT="$_eproot" \
        MT_FIXTURE_DRIVES='SUPWIRE-FIXTUREDISK|/dev/supwirefixture0||0' \
        bash "$BOOT" "$_eproot" >"$WORK/boot_off_$_iter.log" 2>&1
    _eboot_rc=$?
    _eoff_running=0
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "multitrack_supervisor.sh watch --interval $_eintv" >/dev/null 2>&1 && _eoff_running=1
    fi
    if [ "$_eboot_rc" = "0" ] && [ "$_eoff_running" = "0" ]; then
        pass "GREEN(e): bootstrap opt-in step 6 OFF by default -- NO watch daemon started (rc=$_eboot_rc)" "$WORK/boot_off_$_iter.log"
        echo "GREEN_e_optin_off=NO_DAEMON rc=$_eboot_rc" >> "$_norm"
    else
        fail "GREEN(e): expected rc=0 + no daemon, got rc=$_eboot_rc running=$_eoff_running" "$WORK/boot_off_$_iter.log"
        echo "GREEN_e_optin_off=UNEXPECTED rc=$_eboot_rc running=$_eoff_running" >> "$_norm"
    fi

    # (f) bootstrap opt-in ON -> a REAL watch daemon starts, does >=1
    #     iteration, then is killed cleanly.
    _fproot="$WORK/boot_on_proot_$_iter"; mkdir -p "$_fproot"
    _fhook="$WORK/boot_on_home_$_iter/.local/bin/claude-cwd-hook"
    _falias="$WORK/boot_on_alias_$_iter"
    _ffixture="$WORK/boot_on_fixture_$_iter.yaml"
    cat > "$_ffixture" <<FIXEOF
schema_version: 1
host:
  hostname: "supwire-test-host-on-$_iter"
tracks:
  - id: track-1
    role: main
    mount: "/tmp/supwire-nonexistent-track1-on-$_iter"
  - id: track-2
    role: feature
    drive_serial: "SUPWIRE-FIXTURE-SERIAL-NOPE-ON"
    mount: "/tmp/supwire-nonexistent-track2-on-$_iter"
FIXEOF
    _fintv="99872$_iter"
    CMA_CWD_HOOK="$_fhook" MT_CONFIG="$_ffixture" MT_ALIAS_DIR="$_falias" \
        MT_REPO_ROOT="$_fproot" \
        MT_FIXTURE_DRIVES='SUPWIRE-FIXTUREDISK|/dev/supwirefixture0||0' \
        MT_SUPERVISOR_WATCH_ENABLE=1 MT_SUPERVISOR_WATCH_INTERVAL="$_fintv" \
        bash "$BOOT" "$_fproot" >"$WORK/boot_on_$_iter.log" 2>&1
    _fboot_rc=$?
    _fwatchpid=$(sed -n "s/.*supervisor watchdog started (pid=\([0-9][0-9]*\).*/\1/p" "$WORK/boot_on_$_iter.log" | head -n1)
    [ -n "$_fwatchpid" ] && echo "$_fwatchpid" >> "$PIDS_FILE"
    _flog=$(sed -n 's/.*log=\(.*\))$/\1/p' "$WORK/boot_on_$_iter.log" | head -n1)
    _frunning=0
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "multitrack_supervisor.sh watch --interval $_fintv" >/dev/null 2>&1 && _frunning=1
    fi
    _fwaited=0; _fsaw_watch_line=0
    while [ "$_fwaited" -lt 10 ]; do
        if [ -n "$_flog" ] && [ -f "$_flog" ] && grep -qE '^(WATCH:|REHYDRATE:)' "$_flog" 2>/dev/null; then
            _fsaw_watch_line=1
            break
        fi
        sleep 1
        _fwaited=$((_fwaited+1))
    done
    if [ "$_fboot_rc" = "0" ] && [ "$_frunning" = "1" ] && [ "$_fsaw_watch_line" = "1" ]; then
        pass "GREEN(f): bootstrap opt-in step 6 ON -- a REAL watch daemon started (pid=$_fwatchpid), matched the pgrep signature, and logged >=1 genuine loop iteration" "$_flog"
        echo "GREEN_f_optin_on=DAEMON_RAN rc=$_fboot_rc running=$_frunning saw_line=$_fsaw_watch_line" >> "$_norm"
    else
        fail "GREEN(f): rc=$_fboot_rc running=$_frunning saw_line=$_fsaw_watch_line pid=$_fwatchpid log=$_flog" "$WORK/boot_on_$_iter.log"
        echo "GREEN_f_optin_on=UNEXPECTED rc=$_fboot_rc running=$_frunning saw_line=$_fsaw_watch_line" >> "$_norm"
    fi
    # kill it NOW (in addition to the unconditional trap sweep below).
    if [ -n "$_fwatchpid" ]; then
        kill "$_fwatchpid" 2>/dev/null || true
        sleep 1 2>/dev/null || true
        kill -9 "$_fwatchpid" 2>/dev/null || true
    fi
    _fstill=0
    if [ -n "$_fwatchpid" ] && kill -0 "$_fwatchpid" 2>/dev/null; then _fstill=1; fi
    if [ "$_fstill" = "0" ]; then
        pass "GREEN(f2): watch daemon (pid=$_fwatchpid) killed cleanly by this test, no orphan left (§11.4.14)" "$WORK"
        echo "GREEN_f2_killed=clean" >> "$_norm"
    else
        fail "GREEN(f2): watch daemon pid=$_fwatchpid still alive after kill" "$WORK"
        echo "GREEN_f2_killed=STILL_ALIVE" >> "$_norm"
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
