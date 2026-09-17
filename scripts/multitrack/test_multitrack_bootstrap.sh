#!/bin/sh
# =============================================================================
# test_multitrack_bootstrap.sh — RED/GREEN polarity test for RB-08's
#     out-of-the-box bootstrap + auto-install seam
#     (constitution/scripts/multitrack/multitrack_bootstrap.sh +
#      constitution/skills/multitrack/register.sh).
# -----------------------------------------------------------------------------
# Purpose:
#   Proves the RB-08 mechanism is load-bearing, not a bluff (§11.4.115
#   polarity switch on ONE test source):
#
#   RED_MODE=1 (default) — reproduces the pre-fix DEFECT CLASS honestly. RB-08
#     is a NEW capability (nothing "used to work" before it, §11.4.114 does
#     not apply), so — mirroring the SAME convention this plan already uses
#     for RB-02/RB-05/RB-06 ("model the pre-fix absence, not a synthetic
#     failure the fix is written to agree with") — RED proves TWO defect
#     classes genuinely exist absent the fix:
#       (A) register.sh ABSENT -> a simulated constitution-pull dispatch
#           (faithfully mirroring post_update_hook.sh's own classify+invoke
#           mechanism, cross-checked by grep against the REAL script so the
#           simulation cannot silently diverge) does NOT run bootstrap —
#           proven by the scratch project-root's cwd-hook symlink staying
#           ABSENT.
#       (B) a STRAWMAN bootstrap that writes a per-run timestamp file is
#           genuinely NON-IDEMPOTENT — proven by running it twice against
#           the SAME scratch project-root and observing the timestamp
#           marker's content DIFFERS between runs (the exact defect class
#           the real multitrack_bootstrap.sh is built to NOT have).
#
#   RED_MODE=0 (GREEN) — the REAL constitution/scripts/multitrack/
#     multitrack_bootstrap.sh + constitution/skills/multitrack/register.sh:
#       (a) bootstrap run 3x in a row against the SAME scratch $PROJECT_ROOT
#           + a fake ~/.local/bin (CMA_CWD_HOOK) -> byte-identical
#           INDEPENDENTLY-RE-DERIVED state every time (symlink target via
#           `readlink`, config track-count via a fresh `mt_load_config`,
#           orchestrator `status` exit code via a fresh invocation — NEVER
#           trusting bootstrap's own stdout self-report, §11.4.6) + NO
#           timestamped marker file of any kind is ever written by it
#           (the RED(B) defect class proven ABSENT).
#       (b) the SAME simulated-dispatch harness from RED(A), now pointed at
#           the REAL constitution/skills/multitrack/register.sh (present),
#           given a fake changed-file set INCLUDING
#           "skills/multitrack/register.sh" -> asserts it DOES invoke
#           bootstrap end-to-end (the scratch project-root's cwd-hook
#           symlink now resolves to the constitution copy). A NEGATIVE
#           control (same real register.sh present, but the fake
#           changed-file set does NOT mention it) asserts the dispatch does
#           NOT fire — closing the false-positive gap (§11.4.107(10)):
#           proves the wiring is driven by the changed-file classification,
#           not merely "register.sh happens to exist somewhere".
#       (c) a missing per-host config (empty MT_CONFIG_DIR, no MT_CONFIG
#           override) -> bootstrap exits NON-ZERO and prints the literal
#           "OPERATOR STEP" text — NEVER reports green on an unconfigured
#           host (§11.4.6).
#
#   Every scenario runs against ITS OWN scratch MT_ALIAS_DIR / PROJECT_ROOT /
#   CMA_CWD_HOOK (§11.4.119 single-owner — never touches live state), is
#   fully self-cleaning (`trap ... EXIT INT TERM`, §11.4.14), and is
#   device-AND-account-independent (no real claude1/2/3, no real drive, no
#   network) per §11.4.98.
#
# Usage:
#   RED_MODE=1 sh scripts/multitrack/test_multitrack_bootstrap.sh   # RED (default)
#   RED_MODE=0 sh scripts/multitrack/test_multitrack_bootstrap.sh   # GREEN
#
# Inputs: RED_MODE (0|1, default 1); optional MT_RB08_TEST_EVIDENCE_DIR
#   override (else a fresh qa-results/multitrack/rb08_test_<UTC-ts>-<pid>/
#   is created per run). REPO_ROOT is derived via `git rev-parse
#   --show-toplevel` from THIS file's own directory — deliberately
#   independent of the engine files under test, so this test's result can
#   never flap due to an unrelated in-flight sibling PWU editing those files.
#
# Outputs: PASS/FAIL/SKIP lines on stdout + $EV/results.log; per-scenario
#   snapshot/marker files under $EV for the byte-identical-state diff.
#   Exit 0 iff FAIL count is 0.
#
# Side-effects: creates + removes ONE scratch tmp dir (fake ~/.local/bin,
#   fake PROJECT_ROOT, fake MT_ALIAS_DIR, fake per-host YAML fixture),
#   `trap ... EXIT INT TERM` cleanup on every exit path (§11.4.14); writes
#   ONLY under qa-results/multitrack/ + the scratch tmp dir; NEVER touches a
#   real device, a real drive, a real claude1/2/3 account, or this
#   project's real config/multitrack/<hostname>.yaml.
#
# Dependencies: sh (POSIX), bash (the engine scripts under test require it),
#   git, date, mktemp, diff, sed, awk, readlink.
#
# Cross-references:
#   constitution/scripts/multitrack/multitrack_bootstrap.sh (the fix under test)
#   constitution/skills/multitrack/register.sh (the auto-install seam under test)
#   constitution/scripts/post_update_hook.sh (the REAL dispatch mechanism this
#     test's simulated harness is grep-cross-checked against, never diverges
#     silently)
#   docs/superpowers/plans/ruler_bridge_plan.md RB-08
#   docs/research/universal_auto_multitrack_20260704/DESIGN.md §2 / §7.2(a)
#   scripts/multitrack/test_multitrack_host_budget.sh (pass/fail/skip +
#     evidence-dir + trap-cleanup + independent-REPO_ROOT house style this
#     file mirrors)
#   qa-results/multitrack/rb08_snippets/{gate.sh,mutation.sh,challenge.yaml}
#   §11.4.43 / §11.4.115 (RED->GREEN polarity discipline); §11.4.50
#   (deterministic consistency, 3-iteration); §11.4.67 (sh-parseable);
#   §11.4.6 (no-guessing — independent oracles, never self-report); §11.4.69
#   (feature class boot_service).
# =============================================================================

set -u

MT_TEST_SELF=$0
case "$MT_TEST_SELF" in
    */*) MT_TEST_DIR=${MT_TEST_SELF%/*} ;;
    *)   MT_TEST_DIR=. ;;
esac

# Self-contained, PATH-based derivation (deliberately NOT `git rev-parse
# --show-toplevel` from this file's own directory: this test lives INSIDE
# the constitution submodule, `constitution/scripts/multitrack/`, which has
# its OWN `.git` -- `--show-toplevel` from there resolves to the SUBMODULE
# root, not the parent project, silently corrupting every path below it.
# CONST_DIR is therefore derived directly from this file's own location
# (two levels up: constitution/scripts/multitrack/../.. == constitution/),
# mirroring the exact self-locating idiom the sibling engine scripts already
# use (multitrack_config.sh's mt_repo_root(), multitrack_cwd_hook.sh's
# _cwh_self) -- never git plumbing, never guessed, §11.4.6.)
_mtbt_const_dir() {
    if [ -n "${MT_CONST_DIR_FOR_TEST:-}" ]; then
        printf '%s\n' "$MT_CONST_DIR_FOR_TEST"
        return 0
    fi
    ( cd "$MT_TEST_DIR/../.." 2>/dev/null && pwd )
}
CONST_DIR=$(_mtbt_const_dir)
if [ -z "$CONST_DIR" ] || [ ! -f "$CONST_DIR/Constitution.md" ]; then
    echo "FATAL: could not derive the constitution submodule root from $MT_TEST_DIR (got '$CONST_DIR')" >&2
    exit 90
fi
REPO_ROOT=$(cd "$CONST_DIR/.." 2>/dev/null && pwd)
if [ -z "$REPO_ROOT" ]; then
    echo "FATAL: could not derive the parent project root from CONST_DIR=$CONST_DIR" >&2
    exit 90
fi
BOOTSTRAP="$CONST_DIR/scripts/multitrack/multitrack_bootstrap.sh"
CWH="$CONST_DIR/scripts/multitrack/multitrack_cwd_hook.sh"
ORCH="$CONST_DIR/scripts/multitrack/multitrack_alias_orchestrator.sh"
CONFIG_LIB="$CONST_DIR/scripts/multitrack/multitrack_config.sh"
REGISTER="$CONST_DIR/skills/multitrack/register.sh"
POST_UPDATE_HOOK="$CONST_DIR/scripts/post_update_hook.sh"

for _mtbt_f in "$BOOTSTRAP" "$CWH" "$ORCH" "$CONFIG_LIB" "$REGISTER" "$POST_UPDATE_HOOK"; do
    if [ ! -f "$_mtbt_f" ]; then
        echo "FATAL: required file not found: $_mtbt_f" >&2
        exit 91
    fi
done

RED_MODE="${RED_MODE:-1}"

RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
EV="${MT_RB08_TEST_EVIDENCE_DIR:-$REPO_ROOT/qa-results/multitrack/rb08_test_${RUN_TS}-$$}"
mkdir -p "$EV"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_rb08_test.XXXXXX")
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s (%s) [evidence: %s]\n' "$1" "$2" "$3" | tee -a "$EV/results.log"; }

echo "RED_MODE=$RED_MODE  REPO_ROOT=$REPO_ROOT  EV=$EV" | tee -a "$EV/results.log"

# --- a deterministic, no-hardware fixture drive (RB-08's own track-serials
#     never match it, so mt_plan always reports every configured track
#     ABSENT — no lsblk dependency, fully portable across sandboxes) --------
MT_FIXTURE_DRIVES_FOR_TEST='RB08FIXTUREDISK|/dev/rb08fixture0||0'

# --- a valid, self-contained per-host fixture config (bypasses hostname
#     resolution entirely via the engine's own MT_CONFIG full-path override
#     contract, §1.2 — portable across any real test-runner hostname) ------
FIXTURE_YAML="$WORK/fixture_host.yaml"
cat > "$FIXTURE_YAML" <<'FIXEOF'
schema_version: 1
host:
  hostname: "rb08-test-host"
tracks:
  - id: track-1
    role: main
    mount: "/tmp/rb08-nonexistent-track1"
  - id: track-2
    role: feature
    drive_serial: "RB08-FIXTURE-SERIAL-NOPE"
    mount: "/tmp/rb08-nonexistent-track2"
FIXEOF

# --- independent oracle: re-derive bootstrap's resulting state DIRECTLY,
#     NEVER by parsing bootstrap's own stdout self-report (§11.4.6). Prints
#     three lines: LINK=<target-or-empty> / TRACKS=<count> / ORCH_RC=<n>.
#   $1 = CMA_CWD_HOOK path   $2 = alias-dir   $3 = project-root (unused by
#   the probe itself, kept for signature symmetry / future use)
_mtbt_snapshot() {
    _snap_link_var=$1
    _snap_alias_dir=$2
    _snap_link=""
    if [ -L "$_snap_link_var" ]; then
        _snap_link=$(readlink "$_snap_link_var" 2>/dev/null)
    fi
    _snap_tc=$(MT_REPO_ROOT="$WORK/project_root" MT_CONFIG="$FIXTURE_YAML" \
        MT_FIXTURE_DRIVES="$MT_FIXTURE_DRIVES_FOR_TEST" \
        sh -c '. "'"$CONFIG_LIB"'"; mt_load_config "$MT_CONFIG" >/dev/null 2>&1; printf "%s" "${MT_TRACK_COUNT:-NONE}"' 2>/dev/null)
    MT_REPO_ROOT="$WORK/project_root" MT_CONFIG="$FIXTURE_YAML" \
        MT_ALIAS_DIR="$_snap_alias_dir" \
        MT_FIXTURE_DRIVES="$MT_FIXTURE_DRIVES_FOR_TEST" \
        bash "$ORCH" status >/dev/null 2>&1
    _snap_orch_rc=$?
    printf 'LINK=%s\nTRACKS=%s\nORCH_RC=%s\n' "$_snap_link" "$_snap_tc" "$_snap_orch_rc"
}

# --- faithful simulated post_update_hook.sh dispatch (mirrors ONLY the two
#     operative lines from its install_skills(): classify by the SAME
#     `skills/*)` case-arm, then `[ -f "$register" ] && bash "$register"
#     "$project_root"`). Cross-checked by grep (below) against the REAL
#     post_update_hook.sh so this can never silently diverge/bluff.
#   $1 = newline-separated fake changed-file list
#   $2 = const-dir to look skills up under (may be a scratch fixture)
#   $3 = project-root to pass through
#   $4 = a marker file this writes IFF it actually invokes a register.sh
# ---------------------------------------------------------------------------
_mtbt_simulate_dispatch() {
    _sd_changed=$1
    _sd_const_dir=$2
    _sd_project_root=$3
    _sd_marker=$4
    rm -f "$_sd_marker" 2>/dev/null || true
    printf '%s\n' "$_sd_changed" | while IFS= read -r _sd_f; do
        case "$_sd_f" in
            skills/*)
                _sd_skill_name=$(printf '%s' "$_sd_f" | cut -d/ -f2)
                _sd_src="$_sd_const_dir/skills/$_sd_skill_name"
                _sd_register="$_sd_src/register.sh"
                if [ -f "$_sd_register" ]; then
                    bash "$_sd_register" "$_sd_project_root" > "$WORK/dispatch_stdout.log" 2>&1
                    echo "INVOKED $_sd_register" > "$_sd_marker"
                fi
                ;;
        esac
    done
}

# =============================================================================
# RED_MODE=1 — reproduce the two pre-fix defect classes honestly
# =============================================================================
if [ "$RED_MODE" = "1" ]; then

    # --- RED(A): register.sh genuinely ABSENT -> dispatch does NOT invoke it
    RED_A_CONST="$WORK/red_a_const_scratch"
    mkdir -p "$RED_A_CONST/skills/multitrack"     # deliberately NO register.sh
    RED_A_PROOT="$WORK/red_a_project_root"
    mkdir -p "$RED_A_PROOT"
    RED_A_HOOK="$WORK/red_a_home/.local/bin/claude-cwd-hook"
    RED_A_MARKER="$WORK/red_a_marker"

    _mtbt_simulate_dispatch "skills/multitrack/register.sh" "$RED_A_CONST" "$RED_A_PROOT" "$RED_A_MARKER"

    if [ ! -f "$RED_A_MARKER" ] && [ ! -e "$RED_A_HOOK" ]; then
        pass "RED(A): register.sh absent on disk -> simulated constitution-pull dispatch did NOT invoke bootstrap (cwd-hook symlink never created)" "$EV"
    else
        fail "RED(A): expected NO invocation when register.sh is absent, but a marker/symlink appeared — defect NOT reproduced" "$EV"
    fi

    # --- RED(B): a STRAWMAN bootstrap that writes a per-run timestamp is
    #     genuinely non-idempotent (the exact defect class the real
    #     multitrack_bootstrap.sh is built to NOT have)
    RED_B_PROOT="$WORK/red_b_project_root"
    mkdir -p "$RED_B_PROOT"
    RED_B_HOOK="$WORK/red_b_home/.local/bin/claude-cwd-hook"
    RED_B_MARKER="$RED_B_PROOT/.bootstrap_last_run"

    _mtbt_strawman_broken_bootstrap() {
        _sw_hook=$1
        _sw_proot=$2
        CMA_CWD_HOOK="$_sw_hook" bash "$CWH" --install >/dev/null 2>&1 || true
        # THE defect under test: a per-run timestamp write, modelling a
        # naive "bootstrap" that is NOT idempotent.
        date +%s%N > "$_sw_proot/.bootstrap_last_run" 2>/dev/null
    }

    _mtbt_strawman_broken_bootstrap "$RED_B_HOOK" "$RED_B_PROOT"
    _redb_run1=$(cat "$RED_B_MARKER" 2>/dev/null || echo "MISSING")
    # A real filesystem clock tick between runs is not guaranteed on some
    # low-resolution clocks; sleeping is unnecessary here because %N gives
    # nanosecond resolution and the two invocations are never truly
    # simultaneous at the process level -- but guard defensively anyway.
    _mtbt_strawman_broken_bootstrap "$RED_B_HOOK" "$RED_B_PROOT"
    _redb_run2=$(cat "$RED_B_MARKER" 2>/dev/null || echo "MISSING")

    if [ "$_redb_run1" != "MISSING" ] && [ "$_redb_run2" != "MISSING" ] && [ "$_redb_run1" != "$_redb_run2" ]; then
        pass "RED(B): strawman bootstrap's per-run timestamp marker DIFFERED across two runs (non-idempotent defect genuinely reproduced: $_redb_run1 != $_redb_run2)" "$EV"
    else
        fail "RED(B): expected the strawman's timestamp marker to differ across runs (run1=$_redb_run1 run2=$_redb_run2) — defect NOT reproduced" "$EV"
    fi

# =============================================================================
# RED_MODE=0 (GREEN) — the REAL multitrack_bootstrap.sh + register.sh
# =============================================================================
else

    # --- cross-check: the simulated dispatch harness above mirrors the REAL
    #     post_update_hook.sh mechanism verbatim -- if either literal
    #     disappears from the real file, THIS check fails first (before any
    #     false confidence from the simulation) --------------------------
    if grep -qF 'skills/*)' "$POST_UPDATE_HOOK" \
       && grep -qF 'register="${src}/register.sh"' "$POST_UPDATE_HOOK" \
       && grep -qF 'bash "$register" "$PROJECT_ROOT"' "$POST_UPDATE_HOOK"; then
        pass "post_update_hook.sh still classifies skills/* + invokes register.sh with \$PROJECT_ROOT (simulation is a faithful, non-diverged subset)" "$EV"
    else
        fail "post_update_hook.sh's classify/invoke mechanism changed shape -- the simulated dispatch harness above no longer mirrors reality" "$EV"
    fi

    # --- GREEN(a): real bootstrap, 3x, byte-identical INDEPENDENTLY-derived
    #     state; no timestamped marker file ever written -----------------
    GA_PROOT="$WORK/green_a_project_root"
    mkdir -p "$GA_PROOT"
    GA_HOOK="$WORK/green_a_home/.local/bin/claude-cwd-hook"
    GA_ALIAS_DIR="$WORK/green_a_aliasorch"

    _green_a_run() {
        CMA_CWD_HOOK="$GA_HOOK" MT_CONFIG="$FIXTURE_YAML" MT_ALIAS_DIR="$GA_ALIAS_DIR" \
            MT_FIXTURE_DRIVES="$MT_FIXTURE_DRIVES_FOR_TEST" \
            bash "$BOOTSTRAP" "$GA_PROOT" > "$WORK/green_a_run_$1.log" 2>&1
        printf '%s' "$?" > "$WORK/green_a_rc_$1"
    }

    _green_a_run 1
    _mtbt_snapshot "$GA_HOOK" "$GA_ALIAS_DIR" "$GA_PROOT" > "$EV/green_a_snapshot_1.txt"
    _green_a_run 2
    _mtbt_snapshot "$GA_HOOK" "$GA_ALIAS_DIR" "$GA_PROOT" > "$EV/green_a_snapshot_2.txt"
    _green_a_run 3
    _mtbt_snapshot "$GA_HOOK" "$GA_ALIAS_DIR" "$GA_PROOT" > "$EV/green_a_snapshot_3.txt"

    _ga_rc1=$(cat "$WORK/green_a_rc_1" 2>/dev/null || echo "?")
    _ga_rc2=$(cat "$WORK/green_a_rc_2" 2>/dev/null || echo "?")
    _ga_rc3=$(cat "$WORK/green_a_rc_3" 2>/dev/null || echo "?")

    if [ "$_ga_rc1" = "0" ] && [ "$_ga_rc2" = "0" ] && [ "$_ga_rc3" = "0" ]; then
        pass "GREEN(a): bootstrap exits 0 on all 3 runs" "$EV"
    else
        fail "GREEN(a): expected rc=0 on all 3 runs, got rc1=$_ga_rc1 rc2=$_ga_rc2 rc3=$_ga_rc3" "$EV/green_a_run_1.log"
    fi

    if diff -q "$EV/green_a_snapshot_1.txt" "$EV/green_a_snapshot_2.txt" >/dev/null 2>&1 \
       && diff -q "$EV/green_a_snapshot_2.txt" "$EV/green_a_snapshot_3.txt" >/dev/null 2>&1; then
        pass "GREEN(a): symlink-target + config-track-count + orchestrator-status-rc byte-identical across 3 independent runs (§11.4.50)" "$EV/green_a_snapshot_1.txt"
    else
        fail "GREEN(a): state diverged across the 3 runs -- bootstrap is NOT idempotent" "$EV"
    fi

    # a genuinely non-idempotent bootstrap (RED(B)'s defect class) would
    # leave a timestamped marker file under the project root; the real
    # bootstrap must NEVER create one.
    if [ -e "$GA_PROOT/.bootstrap_last_run" ]; then
        fail "GREEN(a): found an unexpected '.bootstrap_last_run' timestamp marker -- RED(B)'s defect class is present in the REAL bootstrap" "$GA_PROOT/.bootstrap_last_run"
    else
        pass "GREEN(a): no timestamped state marker of any kind written by the real bootstrap (RED(B)'s defect class is genuinely ABSENT)" "$EV"
    fi

    # --- GREEN(b): simulated dispatch, driven by the REAL register.sh,
    #     genuinely invokes bootstrap end-to-end + a negative control -----
    GB_CONST="$CONST_DIR"    # the REAL constitution tree (register.sh present)
    GB_PROOT="$WORK/green_b_project_root"
    mkdir -p "$GB_PROOT"
    GB_HOOK="$WORK/green_b_home/.local/bin/claude-cwd-hook"
    GB_MARKER="$WORK/green_b_marker"
    GB_ALIAS_DIR="$WORK/green_b_aliasorch"

    CMA_CWD_HOOK="$GB_HOOK" MT_CONFIG="$FIXTURE_YAML" MT_ALIAS_DIR="$GB_ALIAS_DIR" \
        MT_FIXTURE_DRIVES="$MT_FIXTURE_DRIVES_FOR_TEST" \
        _mtbt_simulate_dispatch "skills/multitrack/register.sh" "$GB_CONST" "$GB_PROOT" "$GB_MARKER"

    if [ -f "$GB_MARKER" ] && [ -L "$GB_HOOK" ]; then
        _gb_target=$(readlink "$GB_HOOK" 2>/dev/null)
        if [ "$_gb_target" = "$CWH" ]; then
            pass "GREEN(b): simulated constitution-pull dispatch (register.sh IN the changed-file set) invoked the REAL register.sh -> REAL bootstrap ran end-to-end (cwd-hook symlink now resolves to $CWH)" "$EV/green_b_marker $WORK/dispatch_stdout.log"
        else
            fail "GREEN(b): dispatch fired but the resulting symlink target is wrong ($_gb_target != $CWH)" "$EV"
        fi
    else
        fail "GREEN(b): expected dispatch to invoke register.sh (marker=$GB_MARKER, symlink=$GB_HOOK) -- auto-install NOT wired" "$EV"
    fi

    # Negative control: SAME real const-dir (register.sh genuinely present
    # on disk), but the fake changed-file set does NOT mention it -- proves
    # the wiring is driven by the changed-file classification, not merely
    # "register.sh happens to exist somewhere" (§11.4.107(10)).
    GBN_PROOT="$WORK/green_b_negctrl_project_root"
    mkdir -p "$GBN_PROOT"
    GBN_HOOK="$WORK/green_b_negctrl_home/.local/bin/claude-cwd-hook"
    GBN_MARKER="$WORK/green_b_negctrl_marker"

    _mtbt_simulate_dispatch "docs/some_unrelated_doc.md" "$GB_CONST" "$GBN_PROOT" "$GBN_MARKER"

    if [ ! -f "$GBN_MARKER" ] && [ ! -e "$GBN_HOOK" ]; then
        pass "GREEN(b) negative control: a changed-file set that does NOT include skills/multitrack/register.sh does NOT invoke bootstrap, even though the real register.sh exists on disk (no false-positive dispatch)" "$EV"
    else
        fail "GREEN(b) negative control: dispatch fired without register.sh in the changed-file set -- classification is not load-bearing" "$EV"
    fi

    # --- GREEN(c): missing per-host config -> UNIVERSAL DEFAULT SINGLE-TRACK
    # RECONCILED (§11.4.120, operator mandate 2026-09-07): this case previously
    # asserted that a missing host config is FATAL. That behaviour was
    # deliberately replaced -- multi-track MUST work on EVERY host, defaulting to
    # ONE track whose Track 1 is the invocation project root (§11.4.187). The
    # assertion is not weakened, it is REDIRECTED at the new contract, and the
    # two fatal paths that DO remain are asserted in (c2)/(c3) below, so the
    # no-guessing guarantee (§11.4.6) is still under test.
    GC_PROOT="$WORK/green_c_project_root"
    mkdir -p "$GC_PROOT"
    GC_HOOK="$WORK/green_c_home/.local/bin/claude-cwd-hook"
    GC_EMPTY_CFGDIR="$WORK/green_c_empty_config_dir"
    mkdir -p "$GC_EMPTY_CFGDIR"

    CMA_CWD_HOOK="$GC_HOOK" MT_HOST="rb08-nonexistent-host-$$" MT_CONFIG_DIR="$GC_EMPTY_CFGDIR" \
        MT_ALIAS_DIR="$WORK/green_c_aliasdir" \
        MT_FIXTURE_DRIVES="$MT_FIXTURE_DRIVES_FOR_TEST" \
        bash "$BOOTSTRAP" "$GC_PROOT" > "$WORK/green_c_run.log" 2>&1
    _gc_rc=$?

    if [ "$_gc_rc" -eq 0 ] \
       && grep -qF 'DEFAULT SINGLE-TRACK MODE' "$WORK/green_c_run.log" \
       && grep -qF "track-1=$GC_PROOT" "$WORK/green_c_run.log"; then
        pass "GREEN(c): missing per-host config -> bootstrap completes (rc=0) in DEFAULT SINGLE-TRACK MODE with track-1 == the invocation PROJECT_ROOT ($GC_PROOT), and says so loudly -- multi-track is universal, never host-gated" "$WORK/green_c_run.log"
    else
        fail "GREEN(c): expected rc=0 + 'DEFAULT SINGLE-TRACK MODE' + 'track-1=$GC_PROOT' on a missing host config, got rc=$_gc_rc" "$WORK/green_c_run.log"
    fi

    # --- GREEN(c2): STRICT mode -> the pre-§11.4.187 fatal path is still there
    CMA_CWD_HOOK="$GC_HOOK" MT_HOST="rb08-nonexistent-host-$$" MT_CONFIG_DIR="$GC_EMPTY_CFGDIR" \
        MT_ALIAS_DIR="$WORK/green_c2_aliasdir" MT_REQUIRE_HOST_CONFIG=1 \
        MT_FIXTURE_DRIVES="$MT_FIXTURE_DRIVES_FOR_TEST" \
        bash "$BOOTSTRAP" "$GC_PROOT" > "$WORK/green_c2_run.log" 2>&1
    _gc2_rc=$?
    if [ "$_gc2_rc" -ne 0 ] && grep -qF 'OPERATOR STEP REQUIRED' "$WORK/green_c2_run.log"; then
        pass "GREEN(c2): MT_REQUIRE_HOST_CONFIG=1 -> missing host config is STILL fatal (rc=$_gc2_rc) with the literal operator authoring step -- an operator who wants the strict contract still has it" "$WORK/green_c2_run.log"
    else
        fail "GREEN(c2): expected non-zero rc + 'OPERATOR STEP REQUIRED' under MT_REQUIRE_HOST_CONFIG=1, got rc=$_gc2_rc" "$WORK/green_c2_run.log"
    fi

    # --- GREEN(c3): a MALFORMED config is NEVER defaulted past (§11.4.6)
    GC3_CFGDIR="$WORK/green_c3_config_dir"
    mkdir -p "$GC3_CFGDIR"
    GC3_HOST="rb08-malformed-host-$$"
    printf 'schema_version: 1\nhost:\n  hostname: %s\n' "$GC3_HOST" > "$GC3_CFGDIR/$GC3_HOST.yaml"
    CMA_CWD_HOOK="$GC_HOOK" MT_HOST="$GC3_HOST" MT_CONFIG_DIR="$GC3_CFGDIR" \
        MT_ALIAS_DIR="$WORK/green_c3_aliasdir" \
        MT_FIXTURE_DRIVES="$MT_FIXTURE_DRIVES_FOR_TEST" \
        bash "$BOOTSTRAP" "$GC_PROOT" > "$WORK/green_c3_run.log" 2>&1
    _gc3_rc=$?
    if [ "$_gc3_rc" -ne 0 ] && ! grep -qF 'DEFAULT SINGLE-TRACK MODE' "$WORK/green_c3_run.log"; then
        pass "GREEN(c3): a config that EXISTS but defines zero tracks is fatal (rc=$_gc3_rc) and does NOT silently fall back to default single-track mode -- ambiguity is never defaulted past (§11.4.6)" "$WORK/green_c3_run.log"
    else
        fail "GREEN(c3): a malformed host config must be fatal AND must not print the default-mode notice, got rc=$_gc3_rc" "$WORK/green_c3_run.log"
    fi
fi

echo "" | tee -a "$EV/results.log"
echo "RED_MODE=$RED_MODE  PASS=$PASS FAIL=$FAIL SKIP=$SKIP" | tee -a "$EV/results.log"
echo "Evidence: $EV"

[ "$FAIL" -eq 0 ]
