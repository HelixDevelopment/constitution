#!/bin/sh
# =============================================================================
# test_multitrack_orchestrator_reconcile.sh — RB-FIX2 permanent regression
#     guard: multitrack_alias_orchestrator.sh cmd_reconcile's embedded awk
#     program used the scalar variable name `exp` (built from JSON key
#     "expires") to hold each event's expiry timestamp. `exp` is a GAWK
#     BUILT-IN function (exponential, e^x). gawk 5.1.0 fatal-errors with a
#     syntax error the moment a built-in function name is assigned as a
#     scalar ("exp=val(...)" / "te[tr]=exp" / "te[t]=exp"), so `orchestrator
#     reconcile` was silently broken on this host: the awk program never
#     ran to completion, the bindings.snapshot was NEVER rebuilt (mv is
#     skipped by the `&&` short-circuit after awk's non-zero exit), yet the
#     command still printed "RECONCILE: bindings snapshot rebuilt ..." and
#     exited 0 — a PASS-bluff at the tooling layer (this test does not fix
#     that secondary silent-failure defect; it is out of this fix's scope,
#     flagged honestly in the RB_FIX2 report per §11.4.6/§11.4.124). The fix
#     (this PWU) renames the scalar to `xp` at every occurrence inside the
#     SAME awk program — no other gawk built-in-name collision was found in
#     the block (index/length/substr/match appear only as FUNCTION CALLS,
#     which is fine; only a VARIABLE/array name colliding with a built-in
#     is the defect class, per the operator's brief).
# -----------------------------------------------------------------------------
# Purpose (§11.4.114/§11.4.115 RED-on-the-broken-artifact + polarity switch):
#   RED_MODE=1 — extracts the PRE-FIX copy of multitrack_alias_orchestrator.sh
#     at the PINNED commit RED_PIN (the parent of 55998fb, the commit that
#     introduced the fix) — the actual artifact this fix replaced, not a
#     synthetic snippet. It is NEVER `git show HEAD:`: once the fix is
#     committed HEAD holds the FIXED copy, so a HEAD-built RED can never go
#     RED on a committed tree (redpin class, §11.4.115/§11.4.292(E)). The
#     pinned copy must contain the pre-fix construct and lack the fix; an
#     unreachable pin (shallow clone) FAILs closed. It drives `reconcile` against a
#     scratch registry seeded with a real BIND event (so the "expires" JSON
#     key IS present and the awk program actually reaches the `exp=val(...)`
#     line). Asserts the pre-fix copy: (a) emits "syntax error" on stderr
#     from gawk, AND (b) leaves bindings.snapshot EMPTY (byte count 0) —
#     proving the defect is genuinely present on the broken artifact, not a
#     synthetic failure the fix is then written to agree with.
#   RED_MODE=0 (GREEN) — drives the CURRENT (working-tree, fixed) primitive
#     against a non-trivial 8-event fixture exercising every reconcile
#     semantic (BIND, a second independent BIND, FALLBACK overriding a
#     BIND, HEARTBEAT refreshing an unrelated track's expiry, a THIRD BIND
#     by an alias that already holds another track, UNBIND dropping a
#     track, a fourth BIND, then REAP dropping it) and asserts: (a) NO
#     "syntax error" appears on stderr, (b) the reconciled bindings.snapshot
#     is BYTE-IDENTICAL to the hand-computed expected 2-row result (only
#     the two tracks never unbound/reaped survive, with the CORRECT
#     winning alias/worktree/pid/acq/expires per the replay-in-order-keyed-
#     by-TRACK semantics documented in cmd_reconcile's own header comment).
#   Both modes ALSO re-run bind/heartbeat/fallback/unbind/status/reap against
#     the current primitive (untouched by this fix's diff — the awk block is
#     private to cmd_reconcile) to confirm the fix did not regress any
#     sibling subcommand.
#   Both modes run their battery 3 times (§11.4.50 determinism) and assert
#     the normalized results are byte-identical across all 3 iterations.
#   Portability (§11.4.67): this host has ONLY gawk (no mawk/busybox awk
#     installed — `readlink -f /usr/bin/awk` -> gawk, verified FACT, not
#     guessed). The RED/GREEN batteries above run under gawk (the only
#     interpreter available); a SKIP-with-reason line is emitted, honestly,
#     for the mawk/busybox portability claim this host cannot exercise
#     (§11.4.6 — never fabricate a cross-interpreter PASS we did not
#     actually perform). The fix itself uses no gawk extension (POSIX
#     match/substr/index/split/delete/for-in — a portability regression
#     test on a host WITH mawk/busybox is a tracked follow-up, not silently
#     claimed here).
#
# Usage:
#   sh constitution/scripts/multitrack/test_multitrack_orchestrator_reconcile.sh              # RED then GREEN
#   RED_MODE=1 sh constitution/scripts/multitrack/test_multitrack_orchestrator_reconcile.sh   # RED only
#   RED_MODE=0 sh constitution/scripts/multitrack/test_multitrack_orchestrator_reconcile.sh   # GREEN only
#   (default RED_MODE=both if unset: the default-tier run proves the defect on
#   the pinned pre-fix copy AND the fix on the current copy in one run, so a
#   regression of the current copy is caught by the default tier)
#
# Inputs: RED_MODE (both|1|0, default both); MT_TEST_CONST_ROOT (optional override for
#   the constitution submodule root, else `git rev-parse --show-toplevel`
#   from this file's own directory); MT_RECONCILE_TEST_EVIDENCE_DIR
#   (optional).
#
# Outputs: PASS/FAIL/SKIP lines on stdout + $EV/results.log; per-iteration
#   normalized result files + captured raw stdout/stderr under $EV. Exit 0
#   iff FAIL count is 0.
#
# Side-effects: creates + removes ONE scratch tmp dir (extracted pre-fix
#   copy for RED_MODE=1, scratch config/alias-dir registry for BOTH modes);
#   `trap ... EXIT INT TERM` cleanup on every exit path (§11.4.14); writes
#   ONLY under qa-results/ (in the PROJECT root, if reachable) and the
#   scratch dir; NEVER touches the real ~/.claude / live registry, NEVER
#   spawns a real worker, NEVER touches a device or credential.
#
# Dependencies: sh (POSIX), bash, gawk (or any awk on PATH), git, date,
#   mktemp, diff, wc, grep.
#
# Cross-references: multitrack_alias_orchestrator.sh (unit under test,
#   cmd_reconcile awk program); qa-results/multitrack/rbfix2_<ts>/
#   (this fix's own captured RED + GREEN evidence);
#   qa-results/multitrack/RB_FIX2_report.md (full narrative); §11.4.6
#   (no-guessing); §11.4.111 (resolve-by-stable-name — the `xp` rename is a
#   name-collision fix, not an index-binding fix, but shares the "a name
#   MUST be chosen deliberately, never accidentally colliding" spirit);
#   §11.4.114 (known-good/known-bad diff oracle); §11.4.115 (RED-on-
#   broken-artifact + polarity switch); §11.4.50 (determinism); §11.4.67
#   (sh-parseable); §11.4.135 (permanent regression guard for every fixed
#   defect).
# =============================================================================

set -u

MT_RECT_SELF=$0
case "$MT_RECT_SELF" in
    */*) MT_RECT_DIR=${MT_RECT_SELF%/*} ;;
    *)   MT_RECT_DIR=. ;;
esac

_rect_const_root() {
    if [ -n "${MT_TEST_CONST_ROOT:-}" ]; then printf '%s\n' "$MT_TEST_CONST_ROOT"; return 0; fi
    ( cd "$MT_RECT_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
CONST_ROOT=$(_rect_const_root)
[ -n "$CONST_ROOT" ] || { echo "FATAL: no constitution submodule root (git toplevel / \$MT_TEST_CONST_ROOT)" >&2; exit 90; }

ORCH="$CONST_ROOT/scripts/multitrack/multitrack_alias_orchestrator.sh"
[ -f "$ORCH" ] || { echo "FATAL: primitive not found: $ORCH" >&2; exit 91; }
sh -n "$ORCH" 2>/dev/null   || { echo "FATAL: primitive fails sh -n: $ORCH" >&2; exit 92; }
bash -n "$ORCH" 2>/dev/null || { echo "FATAL: primitive fails bash -n: $ORCH" >&2; exit 92; }

RED_MODE="${RED_MODE:-both}"
case "$RED_MODE" in
    both) PHASES="1 0" ;;
    1)    PHASES="1" ;;
    0)    PHASES="0" ;;
    *)    echo "FATAL: RED_MODE must be both, 1 or 0 (got '$RED_MODE')" >&2; exit 2 ;;
esac
REQ_MODE=$RED_MODE
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
_rect_evidence_home() {
    _ph=$(cd "$CONST_ROOT/.." 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$_ph" ] && [ -d "$_ph" ]; then printf '%s/qa-results/multitrack\n' "$_ph"; return 0; fi
    printf '%s/qa-results/multitrack\n' "$CONST_ROOT"
}
EV="${MT_RECONCILE_TEST_EVIDENCE_DIR:-$(_rect_evidence_home)/reconcile_test_${RUN_TS}-$$}"
mkdir -p "$EV"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_recon_test.XXXXXX")
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s (%s) [evidence: %s]\n' "$1" "$2" "$3" | tee -a "$EV/results.log"; }

# --- RED artifact pin (§11.4.114/§11.4.115, redpin class) -------------------
# The RED artifact is the pre-fix copy at a FIXED commit, never `git show
# HEAD:` (HEAD holds the FIXED copy once the fix is committed). RED_PIN is the
# parent of 55998fb, which introduced the `xp` rename. Assertions: the pin is
# reachable (else FAIL closed: a shallow clone cannot reproduce the RED); the
# pinned copy contains the pre-fix construct AND lacks the fix; the CURRENT
# copy contains the fix AND lacks the pre-fix construct (control needle).
RED_PIN=e60cbde2e33e7d0542a937331763f6be7e739c9a
RED_PATH=scripts/multitrack/multitrack_alias_orchestrator.sh
PREFIX_NEEDLE='exp=val($0,"expires")'
FIX_NEEDLE='; xp=val($0,"expires")'
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

# --- portability honesty (§11.4.6/§11.4.67): note which awk this host has ---
AWK_BIN=$(command -v gawk 2>/dev/null || command -v mawk 2>/dev/null || command -v awk 2>/dev/null || true)
AWK_KIND="unknown"
if [ -n "$AWK_BIN" ]; then
    if "$AWK_BIN" --version 2>&1 | grep -qiE 'gnu awk|gawk'; then AWK_KIND="gawk"
    elif "$AWK_BIN" -W version 2>&1 | grep -qi 'mawk'; then AWK_KIND="mawk"
    else AWK_KIND="other-awk"; fi
fi
if command -v mawk >/dev/null 2>&1 || command -v busybox >/dev/null 2>&1; then
    :  # alternate interpreter present -- battery below already runs under
       # whichever /usr/bin/awk resolves to; a dedicated cross-interpreter
       # run is a tracked follow-up, not fabricated here (§11.4.6).
else
    skip "portability: mawk/busybox awk cross-interpreter run" \
         "neither mawk nor busybox installed on this host (awk resolves to $AWK_KIND only) -- static review confirms the fix uses no gawk extension (match/substr/index/split/delete/for-in are all POSIX), but this claim is UNCONFIRMED beyond gawk without an alternate interpreter present" \
         "n/a (informational)"
fi

# --- scratch registry construction (shared by RED and GREEN) ----------------
_seed_scratch() {
    _seed_root=$1
    mkdir -p "$_seed_root/config" "$_seed_root/aliasdir"
    cat > "$_seed_root/config/scratch-host.yaml" <<'CFGEOF'
schema_version: 1

host:
  hostname: scratch-host
  machine_id: "deadbeefdeadbeef"

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
  - id: track-3
    role: feature
    branch_pattern: "feature/*"
    mount: /mnt/track3
  - id: track-4
    role: feature
    branch_pattern: "feature/*"
    mount: /mnt/track4
CFGEOF
    : > "$_seed_root/aliasdir/bindings.snapshot"
    : > "$_seed_root/aliasdir/cooldowns.snapshot"
    : > "$_seed_root/aliasdir/events.jsonl"
}

# a single-BIND fixture -- minimal, sufficient to exercise the "expires" JSON
# key and trigger the pre-fix gawk fatal on RED_MODE=1.
_seed_single_bind() {
    _t0=$(date +%s)
    printf '{"ts":%s,"iso":"x","event":"BIND","alias":"claude1","track":"track-1","worktree":"/mnt/track1","expires":"%s","pid":12345,"note":"n"}\n' \
        "$_t0" "$((_t0+900))" > "$1/aliasdir/events.jsonl"
}

# an 8-event fixture exercising BIND/FALLBACK/HEARTBEAT/UNBIND/REAP together
# -- the GREEN correctness oracle (hand-computed expected result below).
_seed_multi_event() {
    _t0=$(date +%s)
    cat > "$1/aliasdir/events.jsonl" <<EOF
{"ts":$((_t0)),"iso":"x","event":"BIND","alias":"claude1","track":"track-1","worktree":"/mnt/track1","expires":"$((_t0+900))","pid":100,"note":"n"}
{"ts":$((_t0+10)),"iso":"x","event":"BIND","alias":"claude2","track":"track-2","worktree":"/mnt/track2","expires":"$((_t0+910))","pid":200,"note":"n"}
{"ts":$((_t0+20)),"iso":"x","event":"FALLBACK","alias":"claude3","track":"track-1","worktree":"/mnt/track1","expires":"$((_t0+920))","pid":300,"note":"n"}
{"ts":$((_t0+30)),"iso":"x","event":"HEARTBEAT","alias":"claude2","track":"","worktree":"","expires":"$((_t0+930))","pid":0,"note":"n"}
{"ts":$((_t0+40)),"iso":"x","event":"BIND","alias":"claude1","track":"track-3","worktree":"/mnt/track3","expires":"$((_t0+940))","pid":400,"note":"n"}
{"ts":$((_t0+50)),"iso":"x","event":"UNBIND","alias":"claude2","track":"track-2","worktree":"","expires":"","pid":0,"note":"n"}
{"ts":$((_t0+60)),"iso":"x","event":"BIND","alias":"claude1","track":"track-4","worktree":"/mnt/track4","expires":"$((_t0+960))","pid":500,"note":"n"}
{"ts":$((_t0+70)),"iso":"x","event":"REAP","alias":"","track":"track-4","worktree":"","expires":"","pid":0,"note":"n"}
EOF
    # hand-computed expected reconciled snapshot (replay-in-order, keyed by
    # TRACK; last BIND/FALLBACK wins; HEARTBEAT refreshes; UNBIND/REAP drop):
    #   track-1 -> claude3 (FALLBACK@+20 overrides the BIND@+0), pid=300,
    #             acq=t0+20, exp=t0+920
    #   track-2 -> UNBIND@+50 -> dropped
    #   track-3 -> claude1 (BIND@+40), pid=400, acq=t0+40, exp=t0+940
    #   track-4 -> REAP@+70 -> dropped
    printf '%s|%s|%s|%s|%s|%s|%s\n' "claude3" "track-1" "/mnt/track1" "300" "$((_t0+20))" "$((_t0+920))" "active" > "$1/expected_bind.txt"
    printf '%s|%s|%s|%s|%s|%s|%s\n' "claude1" "track-3" "/mnt/track3" "400" "$((_t0+40))" "$((_t0+940))" "active" >> "$1/expected_bind.txt"
}

run_iteration() {
    _iter="$1"
    _norm="$EV/normalized_m${RED_MODE}_iter${_iter}.txt"
    : > "$_norm"
    _reg="$WORK/reg_m${RED_MODE}_${_iter}"
    _seed_scratch "$_reg"

    if [ "$RED_MODE" = "1" ]; then
        _seed_single_bind "$_reg"
        MT_SCRIPTS_DIR="$CONST_ROOT/scripts/multitrack" \
        MT_REPO_ROOT="$_reg" MT_CONFIG_DIR="$_reg/config" MT_CONFIG="$_reg/config/scratch-host.yaml" \
        MT_ALIAS_DIR="$_reg/aliasdir" MT_HOST="scratch-host" \
            bash "$PREFIX_COPY" reconcile > "$WORK/red_${_iter}.out" 2> "$WORK/red_${_iter}.err"
        _rc=$?
        _bindbytes=$(wc -c < "$_reg/aliasdir/bindings.snapshot" 2>/dev/null | tr -d ' ')
        if grep -q 'syntax error' "$WORK/red_${_iter}.err" && [ "${_bindbytes:-1}" = "0" ]; then
            pass "RED: pre-fix pinned copy's reconcile awk emits a gawk syntax error AND bindings.snapshot stays EMPTY (byte count 0, defect genuinely present)" "$WORK/red_${_iter}.err"
            echo "RED_defect_present rc=$_rc bindbytes=$_bindbytes" >> "$_norm"
        else
            fail "RED: expected a gawk syntax error + empty bindings.snapshot on the pre-fix copy, got rc=$_rc bindbytes=$_bindbytes -- defect not reproduced" "$WORK/red_${_iter}.err"
            echo "RED_defect_NOT_reproduced rc=$_rc bindbytes=$_bindbytes" >> "$_norm"
        fi
        return 0
    fi

    # ---------------------------------------------------------------- GREEN ---
    _seed_multi_event "$_reg"
    MT_REPO_ROOT="$_reg" MT_CONFIG_DIR="$_reg/config" MT_CONFIG="$_reg/config/scratch-host.yaml" \
    MT_ALIAS_DIR="$_reg/aliasdir" MT_HOST="scratch-host" \
        bash "$ORCH" reconcile > "$WORK/green_${_iter}.out" 2> "$WORK/green_${_iter}.err"
    _rc=$?
    if grep -q 'syntax error' "$WORK/green_${_iter}.err"; then
        fail "GREEN: unexpected gawk syntax error on the FIXED primitive (rc=$_rc)" "$WORK/green_${_iter}.err"
        echo "GREEN_syntax_error rc=$_rc" >> "$_norm"
    else
        pass "GREEN: reconcile runs clean (no gawk syntax error, rc=$_rc)" "$WORK/green_${_iter}.err"
        echo "GREEN_clean_run rc=$_rc" >> "$_norm"
    fi

    if diff -q "$_reg/aliasdir/bindings.snapshot" "$_reg/expected_bind.txt" >/dev/null 2>&1; then
        pass "GREEN: reconciled bindings.snapshot BYTE-IDENTICAL to hand-computed expected (BIND/FALLBACK/HEARTBEAT/UNBIND/REAP semantics all correct)" "$_reg/aliasdir/bindings.snapshot"
        echo "GREEN_snapshot_correct=yes" >> "$_norm"
    else
        fail "GREEN: reconciled bindings.snapshot DIVERGED from hand-computed expected" "$_reg/aliasdir/bindings.snapshot"
        echo "GREEN_snapshot_correct=no" >> "$_norm"
        { echo "--- got ---"; cat "$_reg/aliasdir/bindings.snapshot"; echo "--- expected ---"; cat "$_reg/expected_bind.txt"; } >> "$EV/results.log"
    fi

    # --- sibling-subcommand no-regression battery (bind/heartbeat/fallback/
    #     unbind/status/reap) -- the awk fix is private to cmd_reconcile, but
    #     confirm no collateral breakage on the current primitive. -----------
    _sib="$WORK/sib_${_iter}"
    _seed_scratch "$_sib"
    export MT_REPO_ROOT="$_sib" MT_CONFIG_DIR="$_sib/config" MT_CONFIG="$_sib/config/scratch-host.yaml" \
           MT_ALIAS_DIR="$_sib/aliasdir" MT_HOST="scratch-host"
    _sib_ok=1
    bash "$ORCH" bind --track track-1 --alias claude1 --worktree /mnt/track1 >/dev/null 2>"$WORK/sib_bind_${_iter}.err" || _sib_ok=0
    bash "$ORCH" heartbeat --alias claude1 >/dev/null 2>"$WORK/sib_hb_${_iter}.err" || _sib_ok=0
    bash "$ORCH" fallback --track track-1 --alias claude2 --worktree /mnt/track1 --reason test >/dev/null 2>"$WORK/sib_fb_${_iter}.err" || _sib_ok=0
    bash "$ORCH" status >/dev/null 2>"$WORK/sib_status_${_iter}.err" || _sib_ok=0
    bash "$ORCH" unbind --track track-1 >/dev/null 2>"$WORK/sib_unbind_${_iter}.err" || _sib_ok=0
    bash "$ORCH" reap >/dev/null 2>"$WORK/sib_reap_${_iter}.err" || _sib_ok=0
    _sib_bindbytes=$(wc -c < "$_sib/aliasdir/bindings.snapshot" 2>/dev/null | tr -d ' ')
    unset MT_REPO_ROOT MT_CONFIG_DIR MT_CONFIG MT_ALIAS_DIR MT_HOST
    if [ "$_sib_ok" = "1" ] && [ "${_sib_bindbytes:-1}" = "0" ]; then
        pass "GREEN: sibling subcommands (bind/heartbeat/fallback/status/unbind/reap) all still exit 0 and correctly leave bindings empty after the unbind" "$_sib/aliasdir/bindings.snapshot"
        echo "GREEN_siblings_ok=yes" >> "$_norm"
    else
        fail "GREEN: a sibling subcommand regressed (ok=$_sib_ok bindbytes=$_sib_bindbytes)" "$WORK"
        echo "GREEN_siblings_ok=no" >> "$_norm"
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
