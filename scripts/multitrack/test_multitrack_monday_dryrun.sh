#!/bin/sh
# =============================================================================
# test_multitrack_monday_dryrun.sh — RB-13 Monday dry-run acceptance: the
#     end-to-end, device-AND-account-INDEPENDENT chain proof that the WHOLE
#     ruler-bridge mechanism works via the mock, so Monday activation is a
#     CONFIG FLIP (swap mock claude -> real binary + real tokens), not a
#     first-run (docs/superpowers/plans/ruler_bridge_plan.md RB-13 + §4).
# -----------------------------------------------------------------------------
# Purpose:
#   Chains RB-05 (headless spawn) -> RB-06-style fallback/reuse (the RB-04
#   transcript monitor + orchestrator's own reuse-on-limit semantics) ->
#   RB-07 (ruler self-supervisor) -> RB-08 (bootstrap) -> RB-09 (auto-
#   conductor) into ONE scratch-environment run, proving every §4 Monday
#   acceptance criterion mechanically:
#     1. spawn captures session_id from the mock init; resume/drive re-invoke
#        at the SAME cwd (the §1 storage-collision gotcha).
#     2. success read from result.is_error/subtype, NEVER the exit code.
#     3. ANTHROPIC_API_KEY is unset in the CHILD before every worker launch
#        (the §2 precedence trap) -- proven via a private env-probe wrapper
#        (NOT the shared rb05_fixtures/mock_claude.sh, which this test reads
#        but never modifies).
#     4. a simulated headless quota event (api_retry/rate_limit) fires
#        `orchestrator fallback --track T`; T rebinds onto the next healthy
#        alias. This scenario is deliberately set up as a REUSE case (the
#        target alias already serves ANOTHER track), not merely "fresh".
#     5. when every alias is cooled, a further fallback attempt exits 5
#        (ENOFREE) -- a bounded park (§11.4.101), never a hang.
#     6. the configured `conductor:` alias NEVER resolves to a worktree and
#        NEVER appears in the orchestrator's bindings.snapshot.
#     7. a simulated ruler crash (kill a recorded ruler_pid) is detected by
#        `multitrack_supervisor.sh watch --once`, which REHYDRATES every
#        track's alias/session_id from the live RB-05 registry -- no work
#        lost.
#     8. the "Monday flip" (mock -> real binary + real tokens, SAME code
#        path) is a documented, honestly-SKIPPED claim this week (native
#        accounts exhausted) -- never faked as tested.
#
#   RED_MODE=1 (default): the honest pre-fix/pre-wiring world. Bootstrap and
#     the orchestrator bind still wire cleanly (proving the break is NOT
#     spurious upstream breakage) but the headless-spawn worker target is
#     DELIBERATELY STUBBED-OUT (MT_CLAUDE_BIN points at a no-op executable
#     that emits zero stream-json, simulating "the mock/worker isn't wired")
#     -- the chain must break LOUDLY at that FIRST missing link (spawn
#     returns rc=6, "no session_id captured"), never silently "succeed".
#     NOTE (host-safety): RED deliberately does NOT strip `claude` from
#     $PATH -- this host may have a REAL `claude` binary reachable on PATH
#     (this test runs under Claude Code itself), and invoking it recursively
#     from a test would be a live, unbounded, account-consuming subprocess --
#     exactly what §11.4.98/§12.6/§11.4.133 forbid. MT_CLAUDE_BIN is a
#     first-class override multitrack_sessions.sh already honors (RB-05),
#     so the "stubbed-out spawn" RED path is 100% safe and deterministic.
#   RED_MODE=0 (GREEN): drives the FULL chain against the shared RB-05 mock
#     (scripts/multitrack/rb05_fixtures/mock_claude.sh) end-to-end, 3x for
#     §11.4.50 determinism (normalized, PID/timestamp-free comparison).
#
# Usage:
#   RED_MODE=1 sh constitution/scripts/multitrack/test_multitrack_monday_dryrun.sh   # RED
#   RED_MODE=0 sh constitution/scripts/multitrack/test_multitrack_monday_dryrun.sh   # GREEN
#
# Inputs: RED_MODE (0|1, default 1); optional MT_RB13_TEST_EVIDENCE_DIR.
#
# Outputs: PASS/FAIL/SKIP lines on stdout + $EV/results.log; a per-link
#   captured log + normalized-result file per iteration under $EV. Exit 0
#   iff FAIL count is 0.
#
# Side-effects: creates + removes ONE scratch tmp dir per iteration (scratch
#   MT_CONFIG / MT_ALIAS_DIR / MT_SESSIONS_DIR / MT_RULER_STATE_DIR /
#   CMA_CWD_HOOK / PROJECT_ROOT -- NEVER the live host's ~/.claude*, ~/.local
#   /bin, or real repo config); `trap ... EXIT INT TERM` cleanup on every exit
#   path (§11.4.14); one throwaway `sleep 30` background subprocess per GREEN
#   iteration is started + explicitly killed+reaped to simulate a ruler
#   crash (never a real ruler, never a real device, never a real credential).
#
# Dependencies: sh (POSIX), bash (for the bash-shebang engine scripts: the
#   resolver, orchestrator, fallback monitor, bootstrap, cwd-hook), git,
#   date, mktemp, diff, sed, awk, grep, kill, wait.
#
# Cross-references: docs/superpowers/plans/ruler_bridge_plan.md RB-13 + §4;
#   constitution/scripts/multitrack/{multitrack_sessions.sh (RB-05),
#   multitrack_fallback_monitor.sh + multitrack_alias_orchestrator.sh
#   (RB-04/RB-06 reuse-on-limit), multitrack_supervisor.sh (RB-07),
#   multitrack_bootstrap.sh (RB-08), multitrack_resolve_worktree.sh (RB-09
#   auto-conductor)}; scripts/multitrack/rb05_fixtures/mock_claude.sh (READ,
#   never modified); scripts/multitrack/test_multitrack_sessions_spawn.sh +
#   constitution/scripts/multitrack/test_multitrack_bootstrap.sh (the house
#   style this file mirrors: self-contained CONST_DIR/REPO_ROOT derivation,
#   local pass/fail/skip helpers, normalized-iteration determinism diff).
#   §11.4.43/§11.4.115 (RED->GREEN polarity); §11.4.50/§11.4.98 (deterministic,
#   re-runnable, fully automated); §11.4.69 (feature class boot_service);
#   §11.4.6 (no-guessing -- every assertion reads a real registry/state file,
#   never a self-report); §11.4.67 (sh/bash -n clean); §11.4.10 (no
#   credentials anywhere -- names only, poison env values are test-local).
# =============================================================================

set -u

MT_TEST_SELF=$0
case "$MT_TEST_SELF" in
    */*) MT_TEST_DIR=${MT_TEST_SELF%/*} ;;
    *)   MT_TEST_DIR=. ;;
esac

# --- self-contained CONST_DIR/REPO_ROOT derivation (mirrors
#     test_multitrack_bootstrap.sh's documented rationale: this file lives
#     INSIDE the constitution submodule, which has its OWN .git -- `git
#     rev-parse --show-toplevel` from here would resolve to the SUBMODULE
#     root, not the parent project. Derive directly from this file's own
#     location instead: constitution/scripts/multitrack/../.. == constitution/.
_rb13_const_dir() {
    if [ -n "${MT_CONST_DIR_FOR_TEST:-}" ]; then
        printf '%s\n' "$MT_CONST_DIR_FOR_TEST"
        return 0
    fi
    ( cd "$MT_TEST_DIR/../.." 2>/dev/null && pwd )
}
CONST_DIR=$(_rb13_const_dir)
if [ -z "$CONST_DIR" ] || [ ! -f "$CONST_DIR/Constitution.md" ]; then
    echo "FATAL: could not derive the constitution submodule root from $MT_TEST_DIR (got '$CONST_DIR')" >&2
    exit 90
fi
REPO_ROOT=$(cd "$CONST_DIR/.." 2>/dev/null && pwd)
if [ -z "$REPO_ROOT" ]; then
    echo "FATAL: could not derive the parent project root from CONST_DIR=$CONST_DIR" >&2
    exit 90
fi

SESSIONS="$CONST_DIR/scripts/multitrack/multitrack_sessions.sh"
RESOLVER="$CONST_DIR/scripts/multitrack/multitrack_resolve_worktree.sh"
ORCH="$CONST_DIR/scripts/multitrack/multitrack_alias_orchestrator.sh"
FBMON="$CONST_DIR/scripts/multitrack/multitrack_fallback_monitor.sh"
SUP="$CONST_DIR/scripts/multitrack/multitrack_supervisor.sh"
BOOT="$CONST_DIR/scripts/multitrack/multitrack_bootstrap.sh"
MOCK="$REPO_ROOT/scripts/multitrack/rb05_fixtures/mock_claude.sh"

for _mt_f in "$SESSIONS" "$RESOLVER" "$ORCH" "$FBMON" "$SUP" "$BOOT" "$MOCK"; do
    if [ ! -f "$_mt_f" ]; then
        case "$_mt_f" in */rb05_fixtures/*) echo "SKIP topology_unsupported: consumer-project fixture absent (not part of canon alone): $_mt_f" >&2; exit 77 ;; esac
        echo "FATAL: required engine/fixture file not found: $_mt_f" >&2
        exit 91
    fi
done
sh -n "$SESSIONS"  2>/dev/null || { echo "FATAL: $SESSIONS fails sh -n"  >&2; exit 92; }
sh -n "$SUP"       2>/dev/null || { echo "FATAL: $SUP fails sh -n"       >&2; exit 92; }
bash -n "$RESOLVER" 2>/dev/null || { echo "FATAL: $RESOLVER fails bash -n" >&2; exit 92; }
bash -n "$ORCH"     2>/dev/null || { echo "FATAL: $ORCH fails bash -n"     >&2; exit 92; }
bash -n "$FBMON"    2>/dev/null || { echo "FATAL: $FBMON fails bash -n"    >&2; exit 92; }
bash -n "$BOOT"     2>/dev/null || { echo "FATAL: $BOOT fails bash -n"     >&2; exit 92; }

RED_MODE="${RED_MODE:-1}"
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
EV="${MT_RB13_TEST_EVIDENCE_DIR:-$REPO_ROOT/qa-results/multitrack/rb13_test_${RUN_TS}-$$}"
mkdir -p "$EV"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_rb13_test.XXXXXX")
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s (%s) [evidence: %s]\n' "$1" "$2" "$3" | tee -a "$EV/results.log"; }

echo "RED_MODE=$RED_MODE  REPO_ROOT=$REPO_ROOT  EV=$EV" | tee -a "$EV/results.log"

# --- deterministic per-host hostname string (mirrors multitrack_config.sh's
#     OWN mt_resolve_host() algorithm EXACTLY, since the resolver's config
#     lookup -- unlike the orchestrator/bootstrap -- does NOT honor an
#     MT_CONFIG override; it always derives host via mt_resolve_host() then
#     looks under MT_CONFIG_DIR/$host.yaml. Replicating the SAME algorithm
#     here -- never inventing a different one, §11.4.6 -- guarantees the
#     scratch config file this test writes is the ONE the resolver finds).
_rb13_host() {
    h=""
    if command -v hostname >/dev/null 2>&1; then
        h=$(hostname 2>/dev/null | cut -d. -f1)
    fi
    if [ -z "$h" ] && [ -r /etc/hostname ]; then
        h=$(cut -d. -f1 < /etc/hostname 2>/dev/null)
    fi
    if [ -z "$h" ]; then
        [ -r /etc/machine-id ] && h=$(cut -c1-16 < /etc/machine-id)
    fi
    printf '%s\n' "$h"
}
RB13_HOST=$(_rb13_host)
[ -n "$RB13_HOST" ] || { echo "FATAL: could not derive a host string (hostname/etc-hostname/machine-id all empty)" >&2; exit 93; }

# a deterministic, no-hardware fixture drive set (mirrors RB-08's own house
# convention) -- bootstrap's step 5 track-drive probe is READ-ONLY /
# INFORMATIONAL and never affects exit code, but this keeps it 100%
# host-independent (no real lsblk dependency, §11.4.3/§11.4.98).
MT_FIXTURE_DRIVES_FOR_TEST='RB13FIXTUREDISK|/dev/rb13fixture0||0'

# a stub host-safety lib (identical convention to test_multitrack_sessions_
# spawn.sh) so the RB-02 budget guard certifies deterministically -- NEVER
# reads the host's real memory/CPU.
HSS="$WORK/hss.sh"
printf 'host_safe_parallel_jobs() { echo 4; }\nHOST_SAFETY_BUDGET_GB=99\n' > "$HSS"

# ...and the SAME host-independence intent applied to the OTHER half of the
# RB-02 budget guard. `mt_host_budget_can_spawn` has TWO inputs: the memory/CPU
# budget (stubbed by $HSS above) AND a build-in-flight detector that reads the
# REAL host process table via `pgrep -f "$MT_HOST_BUDGET_BUILD_PGREP_PATTERN"`.
# Leaving that second input un-stubbed makes THIS chain test's verdict depend on
# whether an unrelated heavy build happens to be running on the host: the guard
# correctly returns rc=2 ("heavy build in flight"), cmd_spawn refuses before
# launch, and L3a/L3b/L3c/L4a/L4b/L8 all FAIL — a §11.4.50 determinism and
# §11.4.98 re-runnability defect in the HARNESS, not a product defect (FACT,
# measured 2026-08-03: with a real containerised AOSP build live the chain
# scored PASS=16 FAIL=18; with this detector pinned and NOTHING else changed it
# scored PASS=34 FAIL=0 — the build was the whole delta).
# Pinning it to a sentinel that cannot appear in any real command line makes the
# chain hermetic. NO coverage is lost (§11.4.120 reconcile, never fake-pass):
# the RB-02 guard's own behaviour keeps its two dedicated suites —
# test_multitrack_host_budget_rb02_pgrep.sh + test_multitrack_host_budget_jvm_daemons.sh
# — and the guard is NOT weakened in production; only THIS mock chain, which
# tests spawn/resume/session-id/supervisor and not the host-safety guard, is
# isolated from the host's build state (the same reason $HSS exists).
MT_BUILD_PGREP_SENTINEL_FOR_TEST='__rb13_hermetic_no_such_build_process__'

# --- scratch per-host config writer (schema_version:1; conductor +
#     worktree_subdir + 3 tracks + the fallback signature pair). Mounts are
#     deliberately non-existent placeholders -- this test always passes
#     explicit --cwd/MT_WORKER_CWD to multitrack_sessions.sh (bypassing the
#     resolver's own mount+git validation), so no real mountpoint is ever
#     required by the GREEN chain; the ONE resolver call this test makes
#     (RB-09 conductor check) short-circuits BEFORE any mount validation.
_rb13_write_config() {
    _cfgfile="$1"
    cat > "$_cfgfile" <<EOF
schema_version: 1
host:
  hostname: "$RB13_HOST"
conductor: "claude-conductor"
worktree_subdir: "proj"
tracks:
  - id: track-1
    role: main
    mount: "/tmp/rb13-nonexistent-track1"
  - id: track-2
    role: feature
    mount: "/tmp/rb13-nonexistent-track2"
  - id: track-3
    role: feature
    mount: "/tmp/rb13-nonexistent-track3"
fallback:
  signatures:
    - '"apiErrorStatus":429'
    - '"isApiErrorMessage":true'
EOF
}

# =============================================================================
# GREEN battery (RED_MODE=0): the full chain, one scratch environment per
# iteration, run 3x for §11.4.50 determinism (normalized results diffed).
# =============================================================================
run_green_iteration() {
    _i="$1"
    _norm="$EV/normalized_iter${_i}.txt"; : > "$_norm"
    _ib="$WORK/green_$_i"; mkdir -p "$_ib"

    _cfgdir="$_ib/config"; mkdir -p "$_cfgdir"
    _cfgfile="$_cfgdir/$RB13_HOST.yaml"
    _rb13_write_config "$_cfgfile"
    _project="$_ib/project"; mkdir -p "$_project"
    _sessdir="$_ib/sessions"
    _aliasdir="$_ib/aliasorch"
    _rulerdir="$_ib/ruler_state"
    _hook="$_ib/cwd_hook_symlink"
    _wt2="$_ib/wt2"; _wt3="$_ib/wt3"; mkdir -p "$_wt2" "$_wt3"
    _fakebin="$_ib/bin"; mkdir -p "$_fakebin"
    _envlog="$_ib/env_probe.log"; : > "$_envlog"

    # private env-probe wrapper (THIS test's own scratch file -- never a
    # modification of the shared rb05_fixtures/mock_claude.sh) that records
    # whether ANTHROPIC_API_KEY leaked into the child BEFORE chaining to the
    # real shared mock (§2 precedence-trap proof, criterion #3).
    cat > "$_fakebin/claude" <<WRAP
#!/bin/sh
printf 'ANTHROPIC_API_KEY_STATE=%s\n' "\${ANTHROPIC_API_KEY:-<UNSET>}" >> "$_envlog"
exec "$MOCK" "\$@"
WRAP
    chmod +x "$_fakebin/claude"

    export MT_CONFIG="$_cfgfile"
    export MT_CONFIG_DIR="$_cfgdir"
    export MT_REPO_ROOT="$_project"
    export MT_ALIAS_DIR="$_aliasdir"
    export MT_SESSIONS_DIR="$_sessdir"
    export MT_RULER_STATE_DIR="$_rulerdir"
    export MT_ALIAS_ROSTER="claude1:native,claude2:native"
    export HOST_SAFETY_LIB="$HSS"
    export MT_HOST_BUDGET_BUILD_PGREP_PATTERN="$MT_BUILD_PGREP_SENTINEL_FOR_TEST"
    export CMA_CWD_HOOK="$_hook"
    export MT_ORCHESTRATOR="$ORCH"
    export MT_FIXTURE_DRIVES="$MT_FIXTURE_DRIVES_FOR_TEST"
    export ANTHROPIC_API_KEY="poison-should-be-unset-iter$_i"

    # ---- L1: bootstrap (scratch) --------------------------------------------
    _bootout=$(bash "$BOOT" "$_project" 2>&1); _bootrc=$?
    printf '%s\n' "$_bootout" > "$_ib/bootstrap.log"
    if [ "$_bootrc" -eq 0 ]; then
        pass "L1 bootstrap: multitrack_bootstrap.sh wired PROJECT_ROOT=$_project (rc=0, config loaded, orchestrator reconciled)" "$_ib/bootstrap.log"
        echo "L1_BOOTSTRAP=OK" >> "$_norm"
    else
        fail "L1 bootstrap: rc=$_bootrc (expected 0)" "$_ib/bootstrap.log"
        echo "L1_BOOTSTRAP=FAIL rc=$_bootrc" >> "$_norm"
    fi

    # ---- L2: orchestrator pre-existing bindings (sets up the REUSE case) ----
    # claude1->track-2 (about to hit a limit), claude2->track-3 (ALREADY
    # serving another track) -- so track-2's eventual fallback exercises the
    # "reuse an already-bound healthy alias" tier, not merely "pick a fresh
    # one" (plan requirement d: "rebind onto the next healthy alias (reuse)").
    _bindout=$(bash "$ORCH" bind --alias claude1 --track track-2 --worktree "$_wt2" 2>&1); _bindrc=$?
    _bindout2=$(bash "$ORCH" bind --alias claude2 --track track-3 --worktree "$_wt3" 2>&1); _bindrc2=$?
    printf '%s\n%s\n' "$_bindout" "$_bindout2" > "$_ib/bind.log"
    if [ "$_bindrc" -eq 0 ] && [ "$_bindrc2" -eq 0 ]; then
        pass "L2 orchestrator bind: claude1->track-2, claude2->track-3 established (reuse scenario primed)" "$_ib/bind.log"
        echo "L2_BIND=OK" >> "$_norm"
    else
        fail "L2 orchestrator bind: rc1=$_bindrc rc2=$_bindrc2 (expected 0/0)" "$_ib/bind.log"
        echo "L2_BIND=FAIL rc1=$_bindrc rc2=$_bindrc2" >> "$_norm"
    fi

    # ---- L3: RB-05 headless spawn (mock) for BOTH tracks --------------------
    _pin2="RB13-MOCK-track2-iter$_i"
    _spawnout2=$(MOCK_CLAUDE_SESSION_ID="$_pin2" MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_IS_ERROR=false \
        MOCK_CLAUDE_LOG="$_ib/mock2.log" PATH="$_fakebin:$PATH" \
        sh "$SESSIONS" spawn track-2 --alias claude1 --cwd "$_wt2" 2>&1); _spawnrc2=$?
    _cap2=$(grep '"session_id"' "$_sessdir/tracks/track-2.json" 2>/dev/null | sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p' | head -n1)
    printf '%s\n' "$_spawnout2" > "$_ib/spawn2.log"
    if [ "$_spawnrc2" -eq 0 ] && [ "$_cap2" = "$_pin2" ]; then
        pass "L3a spawn(track-2): session_id captured=$_pin2, SUCCESS read from result.is_error=false (mock's non-zero exit ignored -- criterion #2)" "$_ib/spawn2.log"
        echo "L3A_SPAWN=OK" >> "$_norm"
    else
        fail "L3a spawn(track-2): rc=$_spawnrc2 captured='$_cap2' expected='$_pin2'" "$_ib/spawn2.log"
        echo "L3A_SPAWN=FAIL rc=$_spawnrc2" >> "$_norm"
    fi

    _pin3="RB13-MOCK-track3-iter$_i"
    _spawnout3=$(MOCK_CLAUDE_SESSION_ID="$_pin3" MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_IS_ERROR=false \
        MOCK_CLAUDE_LOG="$_ib/mock3.log" PATH="$_fakebin:$PATH" \
        sh "$SESSIONS" spawn track-3 --alias claude2 --cwd "$_wt3" 2>&1); _spawnrc3=$?
    _cap3=$(grep '"session_id"' "$_sessdir/tracks/track-3.json" 2>/dev/null | sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p' | head -n1)
    printf '%s\n' "$_spawnout3" > "$_ib/spawn3.log"
    if [ "$_spawnrc3" -eq 0 ] && [ "$_cap3" = "$_pin3" ]; then
        pass "L3b spawn(track-3): session_id captured=$_pin3 (second track, so the ruler-supervisor step below has >1 track to rehydrate)" "$_ib/spawn3.log"
        echo "L3B_SPAWN=OK" >> "$_norm"
    else
        fail "L3b spawn(track-3): rc=$_spawnrc3 captured='$_cap3' expected='$_pin3'" "$_ib/spawn3.log"
        echo "L3B_SPAWN=FAIL rc=$_spawnrc3" >> "$_norm"
    fi

    # env-unset precedence-trap proof (criterion #3, §2): every worker
    # invocation this iteration must show ANTHROPIC_API_KEY UNSET, never the
    # poisoned ambient value.
    if [ -s "$_envlog" ] && ! grep -q 'ANTHROPIC_API_KEY_STATE=poison' "$_envlog" && grep -q 'ANTHROPIC_API_KEY_STATE=<UNSET>' "$_envlog"; then
        pass "L3c precedence-trap: ANTHROPIC_API_KEY unset in EVERY worker invocation this iteration (poisoned ambient value never observed by a child)" "$_envlog"
        echo "L3C_ENVUNSET=OK" >> "$_norm"
    else
        fail "L3c precedence-trap: the poisoned ANTHROPIC_API_KEY leaked into a worker, or the env-probe log is empty" "$_envlog"
        echo "L3C_ENVUNSET=FAIL" >> "$_norm"
    fi

    # ---- L4: drive + resume reuse the SAME cwd (criterion #1) --------------
    _driveout=$(MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_LOG="$_ib/mock2_drive.log" PATH="$_fakebin:$PATH" \
        sh "$SESSIONS" drive "$_pin2" 2>&1); _driverc=$?
    printf '%s\n' "$_driveout" > "$_ib/drive2.log"
    if [ "$_driverc" -eq 0 ] && grep -q -- "--resume $_pin2" "$_ib/mock2_drive.log" 2>/dev/null && grep -q "pwd=$_wt2" "$_ib/mock2_drive.log" 2>/dev/null; then
        pass "L4a drive: 'drive $_pin2' re-invokes the mock with --resume at the recorded (SAME) spawn cwd $_wt2" "$_ib/mock2_drive.log"
        echo "L4A_DRIVE=OK" >> "$_norm"
    else
        fail "L4a drive: rc=$_driverc (expected --resume $_pin2 at pwd=$_wt2)" "$_ib/mock2_drive.log"
        echo "L4A_DRIVE=FAIL rc=$_driverc" >> "$_norm"
    fi

    _resumeout=$(MOCK_CLAUDE_EXIT=3 MOCK_CLAUDE_LOG="$_ib/mock2_resume.log" PATH="$_fakebin:$PATH" \
        sh "$SESSIONS" resume "$_pin2" 2>&1); _resumerc=$?
    printf '%s\n' "$_resumeout" > "$_ib/resume2.log"
    if [ "$_resumerc" -eq 0 ] && grep -q -- "--resume $_pin2" "$_ib/mock2_resume.log" 2>/dev/null && grep -q "pwd=$_wt2" "$_ib/mock2_resume.log" 2>/dev/null; then
        pass "L4b resume: 'resume $_pin2' re-invokes the mock with --resume at the SAME spawn cwd $_wt2 -- the §1 storage-collision gotcha is proven closed" "$_ib/mock2_resume.log"
        echo "L4B_RESUME=OK" >> "$_norm"
    else
        fail "L4b resume: rc=$_resumerc (expected --resume $_pin2 at pwd=$_wt2)" "$_ib/mock2_resume.log"
        echo "L4B_RESUME=FAIL rc=$_resumerc" >> "$_norm"
    fi

    # ---- L5: inject a REAL captured 429+quota transcript line -> the --------
    # RB-04 fallback monitor (--once) classifies it -> fires 'orchestrator
    # fallback --track track-2' -> track-2 REBINDS onto claude2 (REUSE --
    # claude2 already served track-3; both bindings survive, §11.4.119).
    _transcript="$_ib/transcript_track2.jsonl"
    # §11.4.120 reconcile 2026-07-13: monitor pinned 2026-07-12 to the REAL
    # captured token `"api_error_status":429` (substring `":429`) + a quota marker
    # (`resets`/`weekly limit`/`session limit`); the old mock `system/api_retry`
    # shape matched NO real line + no quota marker, so the monitor never fired.
    printf '{"type":"result","subtype":"error_during_execution","is_error":true,"api_error_status":429,"result":"Claude usage limit reached; your weekly limit resets 2026-07-14T00:00:00Z"}\n' > "$_transcript"
    _monout=$(MT_MONITOR_STATE_DIR="$_ib/monitor_state" bash "$FBMON" --once --alias claude1 --track track-2 --transcript "$_transcript" 2>&1); _monrc=$?
    printf '%s\n' "$_monout" > "$_ib/monitor1.log"
    _bindsnap="$_aliasdir/bindings.snapshot"
    _coolsnap="$_aliasdir/cooldowns.snapshot"
    _t2alias=$(awk -F'|' '$2=="track-2"{print $1; exit}' "$_bindsnap" 2>/dev/null)
    _t3alias=$(awk -F'|' '$2=="track-3"{print $1; exit}' "$_bindsnap" 2>/dev/null)
    _c1cooled=$(grep -c '^claude1|' "$_coolsnap" 2>/dev/null); _c1cooled=${_c1cooled:-0}
    if printf '%s\n' "$_monout" | grep -q 'MATCH quota-exhausted' \
        && printf '%s\n' "$_monout" | grep -q 'FIRING fallback' \
        && printf '%s\n' "$_monout" | grep -q 'orchestrator fallback exit=0' \
        && [ "$_t2alias" = "claude2" ] && [ "$_t3alias" = "claude2" ] && [ "$_c1cooled" -ge 1 ]; then
        pass "L5 fallback-reuse: injected headless api_retry/rate_limit line -> monitor classified quota-exhausted -> fired 'orchestrator fallback --track track-2' -> track-2 REBOUND onto claude2 (REUSE: claude2 already served track-3, BOTH bindings preserved), claude1 now cooled" "$_bindsnap"
        echo "L5_FALLBACK_REUSE=OK t2=claude2 t3=claude2 cooled=1" >> "$_norm"
    else
        fail "L5 fallback-reuse: expected t2=claude2 t3=claude2 claude1-cooled>=1, got t2=$_t2alias t3=$_t3alias cooled=$_c1cooled" "$_ib/monitor1.log"
        echo "L5_FALLBACK_REUSE=FAIL t2=$_t2alias t3=$_t3alias cooled=$_c1cooled" >> "$_norm"
    fi

    # ---- L6: ALL aliases cooled -> orchestrator fallback exits 5 (ENOFREE) --
    # -- criterion #5, a bounded §11.4.101 park, NEVER a hang.
    _fb2out=$(bash "$ORCH" fallback --track track-2 --reason rate-limit 2>&1); _fb2rc=$?
    printf '%s\n' "$_fb2out" > "$_ib/fallback2.log"
    if [ "$_fb2rc" -eq 5 ] && printf '%s\n' "$_fb2out" | grep -qi 'ENOFREE'; then
        pass "L6 all-cooled-park: with BOTH claude1+claude2 now cooled, a second fallback for track-2 exits 5 (ENOFREE) -- bounded park, never a hang (criterion #5)" "$_ib/fallback2.log"
        echo "L6_ALLCOOLED=OK" >> "$_norm"
    else
        fail "L6 all-cooled-park: expected rc=5 + ENOFREE, got rc=$_fb2rc" "$_ib/fallback2.log"
        echo "L6_ALLCOOLED=FAIL rc=$_fb2rc" >> "$_norm"
    fi

    # ---- L7: conductor stays home (criterion #6, RB-09) ---------------------
    # 'claude-conductor' is NOT even in MT_ALIAS_ROSTER (so the orchestrator
    # can never bind it), AND the resolver's own conductor:-key check must
    # independently keep it worktree-less.
    _condout=$(bash "$RESOLVER" resolve claude-conductor 2>"$_ib/resolve_conductor.err"); _condrc=$?
    _condbound=$(grep -c 'claude-conductor' "$_bindsnap" 2>/dev/null); _condbound=${_condbound:-0}
    if [ "$_condrc" -eq 0 ] && [ -z "$_condout" ] && [ "$_condbound" -eq 0 ]; then
        pass "L7 conductor-stays-home: resolve(claude-conductor) -> empty output / rc=0 (silent stay-home on /home), NEVER a row in bindings.snapshot" "$_bindsnap"
        echo "L7_CONDUCTOR=OK" >> "$_norm"
    else
        fail "L7 conductor-stays-home: rc=$_condrc out='$_condout' bound_rows=$_condbound (expected empty/0/0)" "$_bindsnap"
        echo "L7_CONDUCTOR=FAIL rc=$_condrc bound=$_condbound" >> "$_norm"
    fi

    # ---- L8: ruler-supervisor crash + rehydrate (criterion #7, RB-07) -------
    ( sleep 30 ) & _fakerulerpid=$!
    sh "$SUP" snapshot --ruler-pid "$_fakerulerpid" >"$_ib/sup_before.log" 2>&1
    kill "$_fakerulerpid" 2>/dev/null
    wait "$_fakerulerpid" 2>/dev/null
    _watchout=$(sh "$SUP" watch --once 2>&1); _watchrc=$?
    printf '%s\n' "$_watchout" > "$_ib/sup_watch.log"
    _rulerstate="$_rulerdir/ruler_state.json"
    if printf '%s\n' "$_watchout" | grep -q "ruler DEAD (recorded pid=$_fakerulerpid)" \
        && printf '%s\n' "$_watchout" | grep -q 'REHYDRATING' \
        && grep -q '"rehydrated_at"' "$_rulerstate" 2>/dev/null \
        && grep -qF "\"track\":\"track-2\",\"alias\":\"claude1\",\"session_id\":\"$_pin2\"" "$_rulerstate" 2>/dev/null \
        && grep -qF "\"track\":\"track-3\",\"alias\":\"claude2\",\"session_id\":\"$_pin3\"" "$_rulerstate" 2>/dev/null; then
        pass "L8 ruler-supervisor: simulated ruler crash (killed pid=$_fakerulerpid) DETECTED DEAD by 'watch --once', REHYDRATED both tracks' alias/session_id from the live RB-05 registry -- no work lost" "$_rulerstate"
        echo "L8_SUPERVISOR=OK" >> "$_norm"
    else
        fail "L8 ruler-supervisor: crash/rehydrate did not reproduce as expected (rc=$_watchrc)" "$_ib/sup_watch.log"
        echo "L8_SUPERVISOR=FAIL rc=$_watchrc" >> "$_norm"
    fi

    unset ANTHROPIC_API_KEY
}

# =============================================================================
# RED battery (RED_MODE=1, default): bootstrap + bind still wire cleanly, but
# the headless-spawn worker target is deliberately stubbed-out -- the chain
# MUST break loudly at that first missing link (§11.4.115 RED-on-broken).
# =============================================================================
run_red_once() {
    _i="$1"
    _norm="$EV/red_normalized_iter${_i}.txt"; : > "$_norm"
    _ib="$WORK/red_$_i"; mkdir -p "$_ib"

    _cfgdir="$_ib/config"; mkdir -p "$_cfgdir"
    _cfgfile="$_cfgdir/$RB13_HOST.yaml"
    _rb13_write_config "$_cfgfile"
    _project="$_ib/project"; mkdir -p "$_project"
    _sessdir="$_ib/sessions"
    _aliasdir="$_ib/aliasorch"
    _rulerdir="$_ib/ruler_state"
    _hook="$_ib/cwd_hook_symlink"
    _wt2="$_ib/wt2"; mkdir -p "$_wt2"

    export MT_CONFIG="$_cfgfile"
    export MT_CONFIG_DIR="$_cfgdir"
    export MT_REPO_ROOT="$_project"
    export MT_ALIAS_DIR="$_aliasdir"
    export MT_SESSIONS_DIR="$_sessdir"
    export MT_RULER_STATE_DIR="$_rulerdir"
    export MT_ALIAS_ROSTER="claude1:native,claude2:native"
    export HOST_SAFETY_LIB="$HSS"
    export MT_HOST_BUDGET_BUILD_PGREP_PATTERN="$MT_BUILD_PGREP_SENTINEL_FOR_TEST"
    export CMA_CWD_HOOK="$_hook"
    export MT_ORCHESTRATOR="$ORCH"
    export MT_FIXTURE_DRIVES="$MT_FIXTURE_DRIVES_FOR_TEST"

    _bootout=$(bash "$BOOT" "$_project" 2>&1); _bootrc=$?
    printf '%s\n' "$_bootout" > "$_ib/bootstrap.log"
    if [ "$_bootrc" -eq 0 ]; then
        pass "RED pre-link L1 bootstrap still wires cleanly (rc=0) -- the break below is isolated to the spawn link, not spurious upstream breakage" "$_ib/bootstrap.log"
        echo "RED_L1_BOOTSTRAP=OK" >> "$_norm"
    else
        fail "RED pre-link L1 bootstrap unexpectedly broken (rc=$_bootrc) -- RED baseline invalid" "$_ib/bootstrap.log"
        echo "RED_L1_BOOTSTRAP=FAIL rc=$_bootrc" >> "$_norm"
    fi

    _bindout=$(bash "$ORCH" bind --alias claude1 --track track-2 --worktree "$_wt2" 2>&1); _bindrc=$?
    printf '%s\n' "$_bindout" > "$_ib/bind.log"
    if [ "$_bindrc" -eq 0 ]; then
        pass "RED pre-link L2 orchestrator bind still wires cleanly (rc=0)" "$_ib/bind.log"
        echo "RED_L2_BIND=OK" >> "$_norm"
    else
        fail "RED pre-link L2 orchestrator bind unexpectedly broken (rc=$_bindrc)" "$_ib/bind.log"
        echo "RED_L2_BIND=FAIL rc=$_bindrc" >> "$_norm"
    fi

    # THE deliberately-broken link: a no-op executable standing in for "the
    # headless-spawn worker isn't wired" -- emits ZERO stream-json. Never
    # strips `claude` from $PATH (see file docstring: this host may have a
    # REAL claude binary reachable, and invoking it recursively from a test
    # would be a live, account-consuming, unbounded subprocess -- forbidden
    # by §11.4.98/§12.6/§11.4.133). MT_CLAUDE_BIN is RB-05's own first-class
    # override, so this is a safe, deterministic, honest simulation.
    _brokenstub="$_ib/broken_stub"
    printf '#!/bin/sh\nexit 0\n' > "$_brokenstub"
    chmod +x "$_brokenstub"
    _redout=$(MT_CLAUDE_BIN="$_brokenstub" sh "$SESSIONS" spawn track-2 --alias claude1 --cwd "$_wt2" 2>&1); _redrc=$?
    printf '%s\n' "$_redout" > "$_ib/red_spawn.log"
    if [ "$_redrc" -eq 6 ] && printf '%s\n' "$_redout" | grep -qi 'no session_id captured'; then
        pass "RED L3 (the deliberately-broken link): with the headless-spawn worker STUBBED-OUT (MT_CLAUDE_BIN=no-op, simulating 'unwired'), spawn breaks LOUDLY at the FIRST missing link (rc=6, 'no session_id captured') -- never a silent/fake success" "$_ib/red_spawn.log"
        echo "RED_L3_BREAK=OK rc=6" >> "$_norm"
    else
        fail "RED L3: expected rc=6 + 'no session_id captured' with the stubbed spawn target, got rc=$_redrc" "$_ib/red_spawn.log"
        echo "RED_L3_BREAK=FAIL rc=$_redrc" >> "$_norm"
    fi
}

# =============================================================================
# main
# =============================================================================
if [ "$RED_MODE" = "1" ]; then
    for _i in 1 2 3; do run_red_once "$_i"; done
    echo "=== §11.4.50 determinism check: red_normalized_iter1/2/3 byte-identical? ===" | tee -a "$EV/results.log"
    if diff -q "$EV/red_normalized_iter1.txt" "$EV/red_normalized_iter2.txt" >/dev/null 2>&1 \
        && diff -q "$EV/red_normalized_iter2.txt" "$EV/red_normalized_iter3.txt" >/dev/null 2>&1; then
        pass "determinism: 3/3 RED iterations byte-identical (normalized)" "$EV/red_normalized_iter1.txt"
    else
        fail "determinism: RED iterations diverged" "$EV"
    fi
else
    for _i in 1 2 3; do run_green_iteration "$_i"; done
    echo "=== §11.4.50 determinism check: normalized_iter1/2/3 byte-identical? ===" | tee -a "$EV/results.log"
    if diff -q "$EV/normalized_iter1.txt" "$EV/normalized_iter2.txt" >/dev/null 2>&1 \
        && diff -q "$EV/normalized_iter2.txt" "$EV/normalized_iter3.txt" >/dev/null 2>&1; then
        pass "determinism: 3/3 GREEN iterations byte-identical (normalized)" "$EV/normalized_iter1.txt"
    else
        fail "determinism: GREEN iterations diverged" "$EV"
    fi
fi

# Criterion #8 (Monday flip): genuinely NOT testable this week (claude1/2/3
# native accounts exhausted per the plan's own §6 honest boundary) -- honest
# SKIP-with-reason per §11.4.3/§11.4.69, never a faked PASS. The mechanism
# (this SAME test path) is what proves the flip requires no code change: only
# the mock-vs-real `claude` binary on PATH + real tokens in the alias config
# differ between this week's GREEN run and Monday's real run.
skip "L9 Monday-flip real-token smoke: swap the mock claude for the real binary + real tokens in the alias roster; the SAME RB-13 path exercises real workers with NO code change" "operator_attended -- claude1/2/3 native accounts exhausted this week (plan §6); this GREEN run against the mock proves the mechanism now" "$EV"

echo "" | tee -a "$EV/results.log"
echo "RED_MODE=$RED_MODE  PASS=$PASS FAIL=$FAIL SKIP=$SKIP" | tee -a "$EV/results.log"
echo "Evidence: $EV"

[ "$FAIL" -eq 0 ]
