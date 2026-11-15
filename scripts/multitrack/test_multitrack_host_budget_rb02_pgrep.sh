#!/bin/sh
# =============================================================================
# test_multitrack_host_budget_rb02_pgrep.sh
#   — PROVABLY the RB-02 pgrep-footgun fix + the §11.4.201 VANISHED-PID liveness
#     fix in multitrack_host_budget.sh: `_mt_host_budget_heavy_build_running` MUST
#     NOT count (a) a process that merely MENTIONS a build token (pattern-carrier /
#     `claude` worker / multitrack engine / this guard's own process), NOR (b) a
#     matched PID that has VANISHED/DIED (the `pgrep -f`->/proc read race — a
#     DEAD PID, empty cmdline) — as a "heavy build in flight"; while STILL
#     detecting a genuine soong/gradle/JVM-daemon build AND still conservatively
#     REFUSING a LIVE process whose cmdline is unreadable (safe default).
#     (§11.4.201 assert-the-real-condition / §11.4.180 liveness-proven / §12.12
#      process-footgun / §11.4.115 RED-polarity / §1.1 paired mutation /
#      §11.4.120 fix-breaks-its-own-gate reconciliation / §11.4.50 determinism /
#      §11.4.69 captured evidence / §11.4.6 no-guessing.)
# -----------------------------------------------------------------------------
# Forensic anchor (FACT, captured 2026-07-13/14 in
#   qa-results/multitrack/rb02_pgrep_footgun_*): on a host with ZERO real builds,
#   the guard REFUSED every §11.4.187 worker spawn because `pgrep -f "$PATTERN"`
#   substring-matched a live `claude` worker whose prompt QUOTED the pgrep pattern
#   (a pattern-CARRIER + multitrack + claude-worker all at once). The fix re-reads
#   each matched PID's REAL /proc cmdline and excludes the carrier / multitrack /
#   claude-worker / self+parent classes; an UNREADABLE cmdline (vanished PID, or a
#   simulated test PID) is conservatively counted as a build (REFUSE — the safe,
#   reversible default, §11.4.101 / §12.8).
#
# Two independent evidence layers (both required for GREEN):
#   (1) DETERMINISTIC HERMETIC unit layer — a fake `pgrep` (PATH shim) returns a
#       controlled PID set ($MT_RB02_SIM_PIDS); the stubbable seam
#       `_mt_host_budget_pid_cmdline` is overridden to return a controlled cmdline
#       per PID ($MT_RB02_CL_<pid>). NO real process, NO spawn-timing flake, fully
#       repeatable (§11.4.50). This layer runs its whole battery 3x and asserts
#       the normalized results are byte-identical across all 3 iterations.
#   (2) REAL-/proc E2E layer — spawns bounded `sleep` decoys via `exec -a` with a
#       controlled argv[0] (each decoy writes its own pid to a pidfile so the
#       harness NEVER uses `pgrep -f`/`pkill -f` on a marker that would self-match
#       — the same §12.12 footgun the fix itself addresses). Proves the fix on the
#       REAL /proc read, not only the stub. Best-effort: if a decoy cannot be
#       spawned/observed it SKIPs-with-reason (§11.4.3), never fake-passes.
#
# Anti-bluff polarity (§11.4.115 one-source-two-roles via RED_MODE, default 1):
#   RED_MODE=1 (RED — reproduce BOTH footguns on the BROKEN artifacts): (a) run the
#       carrier scenario against a MUTATED copy whose strict-filter constant is
#       flipped to 0 (the pre-fix naive `pgrep` path) and assert it WRONGLY REFUSES
#       (rc=2) on a carrier-only set; (b) run the VANISHED(dead)-matched-PID
#       scenario against a MUTATED copy whose liveness-gate constant is flipped to 0
#       (the pre-fix unconditional empty-cmdline REFUSE) and assert it WRONGLY
#       REFUSES (rc=2) — the §11.4.201 false-refuse footgun PRESENT. A RED that does
#       NOT reproduce is a blind test (§11.4.115) -> FAIL.
#   RED_MODE=0 (GREEN — both defects ABSENT on the REAL/fixed artifact): assert
#       every scenario's correct verdict on the real guard (incl. unreadable+LIVE
#       -> REFUSE and unreadable+VANISHED -> ALLOW), AND re-run BOTH §1.1 mutation
#       self-checks (strict-filter mutant -> carrier wrongly REFUSES; liveness-gate
#       mutant -> vanished PID wrongly REFUSES) so the GREEN run itself proves the
#       fix catches each negation.
#
# Usage:  RED_MODE=1 sh test_multitrack_host_budget_rb02_pgrep.sh   # RED
#         RED_MODE=0 sh test_multitrack_host_budget_rb02_pgrep.sh   # GREEN
# Exit:   0 iff FAIL count is 0 (SKIP does not fail).
# Evidence: qa-results/multitrack/rb02_pgrep_test_<UTC>/  (per-iteration rc lines,
#           normalized determinism files, real-/proc capture).
# Deps: POSIX sh, bash (the guard's shebang is /bin/sh but it is bash-safe too),
#       date, mktemp, sed, diff, tr, grep, sleep. NEVER a real build, NEVER a
#       device, NEVER credentials.
# Cross-refs: multitrack_host_budget.sh (>>MT_HB_STRICT_BUILD_FILTER marker +
#   >>MT_HB_LIVENESS_GATE marker + _mt_host_budget_pid_cmdline seam +
#   _mt_host_budget_pid_alive seam); test_multitrack_host_budget_jvm_daemons.sh
#   (the sibling DETECTION test whose fake-pgrep house style this mirrors);
#   CM-MULTITRACK-GUARD-VANISHED-PID-LIVENESS pre-build gate + its paired
#   meta-mutation; §11.4.201 / §11.4.180 / §11.4.120 / §12.12 / §12.6 / §12.7 /
#   §12.8 / §11.4.6 / §11.4.50 / §11.4.101 / §11.4.115.
# =============================================================================

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
SELF=$0
case "$SELF" in */*) DIR=${SELF%/*} ;; *) DIR=. ;; esac
DIR=$(cd "$DIR" 2>/dev/null && pwd)
[ -n "$DIR" ] || { echo "FATAL: cannot resolve self dir" >&2; exit 2; }

GUARD="$DIR/multitrack_host_budget.sh"
[ -f "$GUARD" ] || { echo "FATAL: guard not found: $GUARD" >&2; exit 2; }
sh -n "$GUARD"   || { echo "FATAL: guard fails sh -n"  >&2; exit 2; }
bash -n "$GUARD" 2>/dev/null || { echo "FATAL: guard fails bash -n" >&2; exit 2; }

ROOT=$(cd "$DIR/../../.." 2>/dev/null && pwd)
[ -n "$ROOT" ] || ROOT=$(cd "$DIR" && git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || ROOT="$DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%s)
EV="$ROOT/qa-results/multitrack/rb02_pgrep_test_$TS"
mkdir -p "$EV" 2>/dev/null || { echo "FATAL: cannot create $EV" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/rb02.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
DECOY_PIDS=""
cleanup() {
    for _p in $DECOY_PIDS; do kill "$_p" 2>/dev/null || true; done
    rm -rf "$WORK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

RED_MODE="${RED_MODE:-1}"
PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" | tee -a "$EV/results.log"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s (%s)\n' "$1" "$2" | tee -a "$EV/results.log"; }

# --- host-safety stub: budget always allows, so ONLY the build-guard trips ----
HSS="$WORK/hss.sh"
printf 'host_safe_parallel_jobs() { echo 99; }\nHOST_SAFETY_BUDGET_GB=999\n' > "$HSS"

# --- fake pgrep: returns the controlled sim PID set (ignores the pattern; the
#     test decides membership). Exits 1 (no match) when the set is empty. -------
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/pgrep" <<'PGEOF'
#!/bin/sh
[ -n "${MT_RB02_SIM_PIDS:-}" ] || exit 1
for _p in $MT_RB02_SIM_PIDS; do printf '%s\n' "$_p"; done
exit 0
PGEOF
chmod +x "$FAKEBIN/pgrep"

# The unique multi-token alternation the fake matcher "detects" (never carried by
# any ambient host process; the carrier cmdline embeds it verbatim).
SENT='RB02SENTINELA|RB02SENTINELB|RB02SENTINELC'

# --- hermetic runner: given a guard file + a sim PID set + per-pid cmdlines
#     (as "pid=cmdline" args), returns mt_host_budget_can_spawn's rc. ----------
# Stubs _mt_host_budget_pid_cmdline AFTER sourcing so it maps pid -> $MT_RB02_CL_<pid>.
_hermetic_rc() {
    _g="$1"; _pids="$2"; shift 2
    _envassign=""
    for _kv in "$@"; do
        _pid=${_kv%%=*}; _cl=${_kv#*=}
        _envassign="$_envassign MT_RB02_CL_${_pid}=$(printf '%s' "$_cl" | sed "s/'/'\\\\''/g")"
        eval "export MT_RB02_CL_${_pid}=\$_cl"
    done
    PATH="$FAKEBIN:$PATH" HOST_SAFETY_LIB="$HSS" MT_REPO_ROOT="$ROOT" \
        MT_MAX_WORKERS=99 MT_HOST_BUDGET_BUILD_PGREP_PATTERN="$SENT" \
        MT_RB02_SIM_PIDS="$_pids" GUARDF="$_g" \
        bash -c '
            . "$GUARDF" 2>/dev/null
            # stub the /proc read seam: pid -> $MT_RB02_CL_<pid> (empty => unreadable)
            _mt_host_budget_pid_cmdline() { eval "printf %s \"\${MT_RB02_CL_$1:-}\""; }
            # stub the liveness seam (§11.4.201/§11.4.180): pid -> $MT_RB02_ALIVE_<pid>
            # (default 1=alive). DETERMINISTIC — never depends on whether some real
            # host PID happens to exist (§11.4.50). Only consulted on the empty-cmdline
            # branch, so scenarios with a non-empty cmdline never touch it.
            _mt_host_budget_pid_alive() { eval "[ \"\${MT_RB02_ALIVE_$1:-1}\" = 1 ]"; }
            mt_host_budget_can_spawn 0 >/dev/null 2>&1
            echo "$?"
        '
    for _kv in "$@"; do _pid=${_kv%%=*}; unset "MT_RB02_CL_${_pid}" 2>/dev/null || true; done
}

# --- build the mutated (pre-fix) guard copy: strict-filter constant -> 0 -------
MUT="$WORK/guard_mut.sh"
sed 's/^_mt_hb_strict_build_filter=1$/_mt_hb_strict_build_filter=0/' "$GUARD" > "$MUT"
if ! grep -q '^_mt_hb_strict_build_filter=0$' "$MUT"; then
    echo "FATAL: mutation did not apply (>>MT_HB_STRICT_BUILD_FILTER marker moved?)" >&2
    exit 2
fi

# --- build the liveness-gate mutated (pre-fix vanished-PID footgun) copy --------
# §11.4.120 reconciliation: the §11.4.201 fix (empty-cmdline branch skips a
# DEAD/vanished matched PID) is gated on the plain constant _mt_hb_liveness_gate=1.
# Flipping it to 0 reverts the branch to the pre-fix UNCONDITIONAL REFUSE, so a
# VANISHED PID wrongly REFUSEs — the footgun. The paired §1.1 self-check + RED
# scenario below drive this mutant to prove the liveness line is load-bearing.
MUT_LIV="$WORK/guard_mut_liveness.sh"
sed 's/^_mt_hb_liveness_gate=1$/_mt_hb_liveness_gate=0/' "$GUARD" > "$MUT_LIV"
if ! grep -q '^_mt_hb_liveness_gate=0$' "$MUT_LIV"; then
    echo "FATAL: liveness-gate mutation did not apply (>>MT_HB_LIVENESS_GATE marker moved?)" >&2
    exit 2
fi

# --- scenario cmdlines (sim PIDs 101..107) ------------------------------------
CL_CARRIER="worker carrier $SENT tail"                                   # full alternation => carrier
CL_CLAUDE="claude -p uses RB02SENTINELB in prompt --output-format stream-json"  # claude worker
CL_MULTI="bash multitrack_alias_orchestrator.sh RB02SENTINELB route"    # multitrack engine
CL_GENUINE="java -cp /opt/x RB02SENTINELB org.gradle.launcher.GradleMain"       # genuine build
CL_EMPTY=""                                                              # unreadable => conservative build

# =============================================================================
run_battery() {  # $1 = iteration index; writes normalized rc lines to $2
    _it="$1"; _norm="$2"; : > "$_norm"

    if [ "$RED_MODE" = "1" ]; then
        # -------- RED: the carrier footgun MUST reproduce on the strict-filter-MUTATED guard.
        _rc=$(_hermetic_rc "$MUT" "101" "101=$CL_CARRIER")
        printf 'RED_carrier_mut=%s\n' "$_rc" >> "$_norm"
        if [ "$_rc" = "2" ]; then
            pass "RED[it$_it]: pre-fix (strict-filter=0) guard WRONGLY REFUSES (rc=2) on a carrier-only process set — footgun reproduced"
        else
            fail "RED[it$_it]: expected rc=2 (footgun REFUSE) on the pre-fix guard, got rc=$_rc — blind test (§11.4.115)"
        fi
        # -------- RED: the vanished-PID footgun MUST reproduce on the liveness-MUTATED guard.
        # An empty-cmdline matched PID that is DEAD (alive-stub=0) MUST wrongly REFUSE
        # under the pre-fix liveness-gate=0 branch (the §11.4.201 FALSE-REFUSE).
        MT_RB02_ALIVE_106=0; export MT_RB02_ALIVE_106
        _rc=$(_hermetic_rc "$MUT_LIV" "106" "106=$CL_EMPTY")
        unset MT_RB02_ALIVE_106
        printf 'RED_vanished_mut=%s\n' "$_rc" >> "$_norm"
        if [ "$_rc" = "2" ]; then
            pass "RED[it$_it]: pre-fix (liveness-gate=0) guard WRONGLY REFUSES (rc=2) a VANISHED(dead) matched PID — vanished-PID footgun reproduced (§11.4.201)"
        else
            fail "RED[it$_it]: expected rc=2 (vanished-PID footgun REFUSE) on the pre-fix liveness-mutated guard, got rc=$_rc — blind test (§11.4.115)"
        fi
        return 0
    fi

    # -------- GREEN: every scenario's correct verdict on the REAL (fixed) guard.
    # carrier only -> ALLOW (rc=0)
    _rc=$(_hermetic_rc "$GUARD" "101" "101=$CL_CARRIER");  printf 'carrier=%s\n' "$_rc" >> "$_norm"
    [ "$_rc" = "0" ] && pass "GREEN[it$_it] carrier-only -> ALLOW (rc=0)" \
                     || fail "GREEN[it$_it] carrier-only: expected rc=0 ALLOW, got rc=$_rc"
    # claude worker only -> ALLOW
    _rc=$(_hermetic_rc "$GUARD" "102" "102=$CL_CLAUDE");   printf 'claude=%s\n' "$_rc" >> "$_norm"
    [ "$_rc" = "0" ] && pass "GREEN[it$_it] claude-worker-only -> ALLOW (rc=0)" \
                     || fail "GREEN[it$_it] claude-worker-only: expected rc=0 ALLOW, got rc=$_rc"
    # multitrack engine only -> ALLOW
    _rc=$(_hermetic_rc "$GUARD" "103" "103=$CL_MULTI");    printf 'multitrack=%s\n' "$_rc" >> "$_norm"
    [ "$_rc" = "0" ] && pass "GREEN[it$_it] multitrack-engine-only -> ALLOW (rc=0)" \
                     || fail "GREEN[it$_it] multitrack-engine-only: expected rc=0 ALLOW, got rc=$_rc"
    # genuine build only -> REFUSE (rc=2) — NO over-exclusion
    _rc=$(_hermetic_rc "$GUARD" "104" "104=$CL_GENUINE");  printf 'genuine=%s\n' "$_rc" >> "$_norm"
    [ "$_rc" = "2" ] && pass "GREEN[it$_it] genuine-build-only -> REFUSE (rc=2, real build still caught)" \
                     || fail "GREEN[it$_it] genuine-build-only: expected rc=2 REFUSE, got rc=$_rc"
    # unreadable cmdline + LIVE process -> REFUSE (conservative safe default preserved)
    MT_RB02_ALIVE_105=1; export MT_RB02_ALIVE_105
    _rc=$(_hermetic_rc "$GUARD" "105" "105=$CL_EMPTY");    printf 'unreadable_live=%s\n' "$_rc" >> "$_norm"
    unset MT_RB02_ALIVE_105
    [ "$_rc" = "2" ] && pass "GREEN[it$_it] unreadable-cmdline+LIVE -> REFUSE (rc=2, conservative safe default §11.4.101/§11.4.201)" \
                     || fail "GREEN[it$_it] unreadable-cmdline+LIVE: expected rc=2 REFUSE, got rc=$_rc"
    # unreadable cmdline + VANISHED/DEAD PID (the pgrep->/proc read RACE) -> ALLOW
    # (the RB-02 vanished-PID FALSE-REFUSE footgun REMOVED — a dead PID is provably
    #  not a live build, §11.4.201). This is the load-bearing fix scenario.
    MT_RB02_ALIVE_106=0; export MT_RB02_ALIVE_106
    _rc=$(_hermetic_rc "$GUARD" "106" "106=$CL_EMPTY");    printf 'unreadable_vanished=%s\n' "$_rc" >> "$_norm"
    unset MT_RB02_ALIVE_106
    [ "$_rc" = "0" ] && pass "GREEN[it$_it] unreadable-cmdline+VANISHED(dead) -> ALLOW (rc=0, vanished-PID false-refuse footgun REMOVED §11.4.201)" \
                     || fail "GREEN[it$_it] unreadable-cmdline+VANISHED: expected rc=0 ALLOW, got rc=$_rc"
    # mixed [carrier, genuine] -> REFUSE (genuine survives the carrier exclusion)
    _rc=$(_hermetic_rc "$GUARD" "101 104" "101=$CL_CARRIER" "104=$CL_GENUINE"); printf 'mixed=%s\n' "$_rc" >> "$_norm"
    [ "$_rc" = "2" ] && pass "GREEN[it$_it] mixed[carrier,genuine] -> REFUSE (rc=2, genuine survives)" \
                     || fail "GREEN[it$_it] mixed[carrier,genuine]: expected rc=2 REFUSE, got rc=$_rc"
    # no match at all -> ALLOW
    _rc=$(_hermetic_rc "$GUARD" "" );                     printf 'nomatch=%s\n' "$_rc" >> "$_norm"
    [ "$_rc" = "0" ] && pass "GREEN[it$_it] no-pattern-match -> ALLOW (rc=0)" \
                     || fail "GREEN[it$_it] no-pattern-match: expected rc=0 ALLOW, got rc=$_rc"
    # §1.1 strict-filter self-check: carrier on the strict-filter-MUTATED guard MUST footgun (REFUSE)
    _rc=$(_hermetic_rc "$MUT" "101" "101=$CL_CARRIER");   printf 'mut_selfcheck=%s\n' "$_rc" >> "$_norm"
    [ "$_rc" = "2" ] && pass "GREEN[it$_it] §1.1 self-check: strict-filter-mutated guard REFUSES on carrier (fix provably catches the negation)" \
                     || fail "GREEN[it$_it] §1.1 self-check: strict-filter-mutated guard did NOT footgun (rc=$_rc) — bluff-capable"
    # §1.1 liveness-gate self-check: a VANISHED(dead) matched PID on the LIVENESS-
    # MUTATED guard MUST footgun (wrongly REFUSE) — proves the §11.4.201 liveness
    # line is load-bearing (§11.4.120 fix-breaks-its-own-gate reconciliation).
    MT_RB02_ALIVE_106=0; export MT_RB02_ALIVE_106
    _rc=$(_hermetic_rc "$MUT_LIV" "106" "106=$CL_EMPTY"); printf 'mut_liveness_selfcheck=%s\n' "$_rc" >> "$_norm"
    unset MT_RB02_ALIVE_106
    [ "$_rc" = "2" ] && pass "GREEN[it$_it] §1.1 liveness self-check: liveness-mutated guard REFUSES a VANISHED PID (fix provably catches the negation)" \
                     || fail "GREEN[it$_it] §1.1 liveness self-check: liveness-mutated guard did NOT footgun (rc=$_rc) — bluff-capable"
}

for _i in 1 2 3; do run_battery "$_i" "$EV/normalized_iter${_i}.txt"; done

# --- §11.4.50 determinism: 3 iterations byte-identical --------------------------
if diff -q "$EV/normalized_iter1.txt" "$EV/normalized_iter2.txt" >/dev/null 2>&1 \
   && diff -q "$EV/normalized_iter2.txt" "$EV/normalized_iter3.txt" >/dev/null 2>&1; then
    pass "determinism: 3/3 iterations byte-identical (RED_MODE=$RED_MODE)"
else
    fail "determinism: iterations diverged (RED_MODE=$RED_MODE)"
fi

# --- REAL-/proc E2E layer (GREEN only; best-effort, SKIP-with-reason) -----------
if [ "$RED_MODE" = "0" ]; then
    RDEC="$WORK/realdecoy.sh"
    printf '#!/bin/bash\necho $$ > "$2"\nexec -a "$1" sleep 30\n' > "$RDEC"; chmod +x "$RDEC"
    _real_rc() {  # $1 guard $2 sim-pattern (unused here — real pgrep runs)
        HOST_SAFETY_LIB="$HSS" MT_REPO_ROOT="$ROOT" MT_MAX_WORKERS=99 \
            MT_HOST_BUDGET_BUILD_PGREP_PATTERN="$1REALPAT" GUARDF="$GUARD" \
            bash -c '. "$GUARDF" 2>/dev/null; mt_host_budget_can_spawn 0 >/dev/null 2>&1; echo "$?"'
    }
    RSENT='RB02REALA|RB02REALB|RB02REALC'
    _spawn_real() {  # $1 argv0 -> echoes real pid (via pidfile, never pgrep)
        _pf="$WORK/pf.$$.$RANDOM"; nohup bash "$RDEC" "$1" "$_pf" >/dev/null 2>&1 &
        sleep 0.5; _rp=$(cat "$_pf" 2>/dev/null); rm -f "$_pf"; printf '%s' "$_rp"
    }
    _real_guard() {  # runs the real guard with the real RSENT pattern (real pgrep + /proc)
        HOST_SAFETY_LIB="$HSS" MT_REPO_ROOT="$ROOT" MT_MAX_WORKERS=99 \
            MT_HOST_BUDGET_BUILD_PGREP_PATTERN="$RSENT" GUARDF="$GUARD" \
            bash -c '. "$GUARDF" 2>/dev/null; mt_host_budget_can_spawn 0 >/dev/null 2>&1; echo "$?"'
    }
    rp_carrier=$(_spawn_real "realcarrier $RSENT tail")
    if [ -n "$rp_carrier" ] && [ -r "/proc/$rp_carrier/cmdline" ]; then
        DECOY_PIDS="$DECOY_PIDS $rp_carrier"
        _rc=$(_real_guard)
        [ "$_rc" = "0" ] && pass "REAL-/proc: live carrier decoy (pid=$rp_carrier) -> ALLOW (rc=0)" \
                         || fail "REAL-/proc: live carrier decoy -> expected rc=0 ALLOW, got rc=$_rc"
        kill "$rp_carrier" 2>/dev/null; sleep 0.2
    else
        skip "REAL-/proc carrier decoy" "could not spawn/observe a bounded decoy in this env"
    fi
    rp_gen=$(_spawn_real "java -cp /o RB02REALB org.gradle.launcher.GradleMain")
    if [ -n "$rp_gen" ] && [ -r "/proc/$rp_gen/cmdline" ]; then
        DECOY_PIDS="$DECOY_PIDS $rp_gen"
        _rc=$(_real_guard)
        [ "$_rc" = "2" ] && pass "REAL-/proc: live genuine-build decoy (pid=$rp_gen) -> REFUSE (rc=2)" \
                         || fail "REAL-/proc: live genuine-build decoy -> expected rc=2 REFUSE, got rc=$_rc"
        kill "$rp_gen" 2>/dev/null; sleep 0.2
    else
        skip "REAL-/proc genuine decoy" "could not spawn/observe a bounded decoy in this env"
    fi
fi

{
    printf 'test=test_multitrack_host_budget_rb02_pgrep.sh RED_MODE=%s\n' "$RED_MODE"
    printf 'PASS=%s FAIL=%s SKIP=%s\n' "$PASS" "$FAIL" "$SKIP"
    printf 'result=%s\n' "$( [ "$FAIL" -eq 0 ] && echo PASS || echo FAIL )"
} > "$EV/SUMMARY.txt"

printf '\n== RB-02 pgrep test (RED_MODE=%s): %s ==  PASS=%s FAIL=%s SKIP=%s\nEvidence: %s\n' \
    "$RED_MODE" "$( [ "$FAIL" -eq 0 ] && echo PASS || echo FAIL )" "$PASS" "$FAIL" "$SKIP" "$EV"

[ "$FAIL" -eq 0 ]
