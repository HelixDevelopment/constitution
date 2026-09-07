#!/usr/bin/env bash
# =============================================================================
# multitrack_bootstrap.sh — ONE idempotent command that wires the generic
#     multi-track engine into a consuming project out-of-the-box (RB-08,
#     Phase C). §11.4.164 / §11.4.167 / §11.4.28 / §11.4.177 / §11.4.133 /
#     §11.4.6 / §11.4.115.
# -----------------------------------------------------------------------------
# Purpose:
#   The single entry point that makes the multi-track system "just work" the
#   moment a consuming project (a) first adds this constitution submodule,
#   and (b) on every subsequent `git submodule update --remote constitution`
#   pull (auto-fired via the §11.4.164 skill-register.sh seam —
#   constitution/skills/multitrack/register.sh — DESIGN §2.2). EVERY step is
#   IDEMPOTENT: running this script twice in a row against the SAME
#   environment produces byte-identical resulting state (cwd-hook symlink
#   target, loaded config track-count, orchestrator `status` exit code) —
#   this script NEVER writes a timestamped/per-run state file of its own;
#   idempotency is structural (100% delegated to already-idempotent
#   siblings), never memoised.
#
#   Steps (DESIGN §2.1):
#     1. Install the cwd-hook symlink -> THIS constitution copy
#        (multitrack_cwd_hook.sh --install; already idempotent — it checks
#        the existing target and refuses to clobber a foreign symlink).
#     2. VERIFY (never install/modify) `command -v claude1` + that the
#        installed symlink resolves to the constitution copy — purely
#        INFORMATIONAL; a toolkit account not yet provisioned is NOT a
#        bootstrap failure (account provisioning is the Claude-Toolkit's own
#        job, orthogonal to this project's git/config wiring, §11.4.177).
#     3. Validate config — source multitrack_config.sh, resolve the per-host
#        config/multitrack/<hostname>.yaml (or an explicit $MT_CONFIG
#        override), assert MT_TRACK_COUNT>=1. A MISSING/unparsable host
#        config is the ONLY genuinely fatal path (§11.4.6 no-guessing):
#        print the exact template + the operator authoring step and exit
#        non-zero — NEVER invent host data, NEVER report success on an
#        unconfigured host.
#     4. Seed orchestrator state — `multitrack_alias_orchestrator.sh
#        reconcile` (idempotent: rebuilds bindings.snapshot deterministically
#        from the append-only events.jsonl) + confirm `... status` runs
#        (exit 0, no crash).
#     5. Operator-gate drive-prep (§11.4.133 / §9-D8) — READ-ONLY probe via
#        the sourced `mt_plan` for each configured track; any track whose
#        drive is not READY gets an INFORMATIONAL operator-mount note. NEVER
#        calls multitrack_drive_prep.sh nor any mount/format op
#        autonomously — this step is purely informational and does NOT
#        affect bootstrap's exit code (an unmounted drive is a separately-
#        tracked §11.4.21 operator hand-off, not a bootstrap defect).
#     6. (RB-FIX3 I-a, OPT-IN, default OFF) — start the RB-07 ruler self-
#        supervisor watchdog (multitrack_supervisor.sh watch) as a
#        backgrounded daemon when MT_SUPERVISOR_WATCH_ENABLE=1 is set.
#        Idempotent (pgrep-guarded, mirrors multitrack_cwd_hook.sh's own
#        daemon-start idiom). Disabled by default -- a complete no-op unless
#        the operator opts in, so this step never changes bootstrap's
#        existing default behaviour/exit-code for any pre-existing caller.
#
# Usage:
#   multitrack_bootstrap.sh [--check|--dry-run] [PROJECT_ROOT]
#   PROJECT_ROOT=/path/to/project multitrack_bootstrap.sh
#   (no args -> PROJECT_ROOT defaults to $PWD; §11.4.177 — NEVER a hardcoded
#   project path, always the invocation directory / an explicit target)
#
# Inputs (env):
#   PROJECT_ROOT   consuming-project root ($1 takes priority over this var)
#   MT_HOST / MT_CONFIG / MT_CONFIG_DIR
#                  forwarded verbatim to multitrack_config.sh's per-host
#                  config-resolution contract (DESIGN §1.2) — an explicit
#                  MT_CONFIG always wins over the hostname-keyed lookup.
#   MT_ALIAS_DIR / MT_LOCK_WAIT / MT_ALIAS_TTL / MT_COOLDOWN
#                  forwarded verbatim to multitrack_alias_orchestrator.sh.
#   CMA_CWD_HOOK   forwarded to multitrack_cwd_hook.sh --install (else its
#                  own default $HOME/.local/bin/claude-cwd-hook).
#   MT_FIXTURE_DRIVES
#                  forwarded to multitrack_config.sh's mt_detect_drives —
#                  the deterministic no-hardware test seam (§1.2 doc).
#   MT_SUPERVISOR_WATCH_ENABLE
#                  opt-in (default 0/unset = disabled). Set to 1 to start
#                  the RB-07 ruler self-supervisor `watch` daemon in step 6.
#   MT_SUPERVISOR_WATCH_INTERVAL / MT_SUPERVISOR_WATCH_LOG
#                  forwarded to the started watch daemon (interval seconds,
#                  default 15; log file path, default under PROJECT_ROOT/
#                  .ws_state/multitrack/).
#
# Outputs: a human-readable 5-step report on stdout. Exit 0 = fully wired
#   (or wired-except-informational-notes); non-zero = a genuinely fatal step.
#
# Exit codes:
#   0  bootstrap complete (config loaded, cwd-hook installed, orchestrator
#      reconciled+status OK). A missing toolkit alias / an unmounted track
#      drive are printed as informational NOTEs, NEVER a non-zero exit.
#   1  a required sibling engine script is missing (tree incomplete), OR
#      cwd-hook --install itself failed.
#   2  no per-host config resolvable for this host AND no default single-track
#      fallback could be established (§11.4.187) — prints the exact YAML
#      template + the operator authoring step. Also the strict-mode fatal path
#      when MT_REQUIRE_HOST_CONFIG=1 is set.
#   3  config resolved but failed to parse, or parsed with zero tracks — a
#      malformed config is NEVER defaulted past (§11.4.6).
#   4  orchestrator reconcile or status failed unexpectedly.
#
# Side-effects:
#   - Creates AT MOST one symlink ($CMA_CWD_HOOK, default
#     ~/.local/bin/claude-cwd-hook) — idempotent, 100% delegated to
#     multitrack_cwd_hook.sh --install (this script performs NO symlink
#     logic of its own).
#   - Rewrites $MT_ALIAS_DIR/bindings.snapshot via the orchestrator's OWN
#     atomic `reconcile` (idempotent — the same events.jsonl always yields
#     the same bindings.snapshot; no bootstrap-specific state).
#   - NEVER mounts/formats/writes to a physical drive (§11.4.133).
#   - NEVER writes a timestamped state file of its own (the property the
#     paired §1.1 mutation + test_multitrack_bootstrap.sh RED_MODE=1(b)
#     scenario proves is load-bearing).
#
# Dependencies: bash; the three siblings in this directory
#   (multitrack_config.sh, multitrack_cwd_hook.sh,
#   multitrack_alias_orchestrator.sh); awk (via multitrack_config.sh).
#
# Cross-references:
#   docs/research/universal_auto_multitrack_20260704/DESIGN.md §2 (2.1/2.2/2.3)
#   docs/superpowers/plans/ruler_bridge_plan.md RB-08
#   constitution/skills/multitrack/register.sh (the §11.4.164 auto-install seam)
#   constitution/scripts/multitrack/test_multitrack_bootstrap.sh (RED/GREEN)
#   qa-results/multitrack/rb08_snippets/{gate.sh,mutation.sh,challenge.yaml}
#   §11.4.6 (no-guessing — missing config is fatal, never invented) ·
#   §11.4.28(B) / §11.4.177 (project-agnostic — no `atmosphere` literal here;
#   PROJECT_ROOT is always an explicit arg/env, NEVER hardcoded) ·
#   §11.4.133 / §9-D8 (operator-gated drive-prep — never autonomous
#   mount/format) · §11.4.164 (the constitution auto-propagation seam this
#   is wired into) · §11.4.115 (RED/GREEN polarity discipline for the test).
# Last verified: 2026-07-09
# =============================================================================

set -u

# --- self-locate (mirrors multitrack_cwd_hook.sh's _cwh_self idiom, so this
#     script resolves its own real directory even when invoked via a symlink
#     or a relative path) --------------------------------------------------
_mtb_self() {
    src="${BASH_SOURCE:-$0}"
    while [ -h "$src" ]; do
        d="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
        src="$(readlink "$src")"
        case "$src" in /*) ;; *) src="$d/$src" ;; esac
    done
    d="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    printf '%s/%s\n' "$d" "$(basename "$src")"
}

MTB_SELF="$(_mtb_self)"
MTB_DIR="$(cd -P "$(dirname "$MTB_SELF")" >/dev/null 2>&1 && pwd)"

CONFIG_LIB="$MTB_DIR/multitrack_config.sh"
CWH="$MTB_DIR/multitrack_cwd_hook.sh"
ORCH="$MTB_DIR/multitrack_alias_orchestrator.sh"

for _mtb_sib in "$CONFIG_LIB" "$CWH" "$ORCH"; do
    if [ ! -r "$_mtb_sib" ]; then
        echo "FATAL: missing sibling engine script: $_mtb_sib (engine tree incomplete)" >&2
        exit 1
    fi
done

# --- flags: --check / --dry-run (INSPECT-ONLY, mutate NOTHING) --------------
# A caller must be able to see exactly what activation WOULD do before anything
# on the host is touched. In check mode this script installs no symlink, starts
# no daemon and runs no orchestrator reconcile — it only resolves + reports.
MTB_CHECK=0
MTB_ARGS=""
for _mtb_a in "$@"; do
    case "$_mtb_a" in
        --check|--dry-run) MTB_CHECK=1 ;;
        -h|--help)
            echo "usage: multitrack_bootstrap.sh [--check|--dry-run] [PROJECT_ROOT]"
            echo "  --check / --dry-run   inspect + report only; installs nothing,"
            echo "                        starts nothing, reconciles nothing."
            exit 0 ;;
        *) [ -n "$MTB_ARGS" ] || MTB_ARGS="$_mtb_a" ;;
    esac
done

# --- PROJECT_ROOT resolution (§11.4.177 — first non-flag arg > $PROJECT_ROOT
#     env > invocation cwd; NEVER a hardcoded project path) -----------------
PROJECT_ROOT="${MTB_ARGS:-${PROJECT_ROOT:-$(pwd)}}"
export PROJECT_ROOT

# The engine's OWN config-contract override — an explicit MT_REPO_ROOT always
# wins in multitrack_config.sh's mt_repo_root() (DESIGN §1.2). Pointing it at
# PROJECT_ROOT makes every accessor sourced/invoked below resolve THIS
# project's config/multitrack/ regardless of where multitrack_bootstrap.sh
# physically lives (submodule vs standalone, §11.4.35).
export MT_REPO_ROOT="$PROJECT_ROOT"
export MT_SELF="$MTB_SELF"

# shellcheck source=constitution/scripts/multitrack/multitrack_config.sh disable=SC1091
. "$CONFIG_LIB"

echo "== multitrack_bootstrap.sh: wiring PROJECT_ROOT=$PROJECT_ROOT =="
echo

# ---------------------------------------------------------------------------
# STEP 1/5 — install the cwd-hook symlink (idempotent, delegated in full)
# ---------------------------------------------------------------------------
echo "-- step 1/5: cwd-hook symlink --"
if [ "$MTB_CHECK" -eq 1 ]; then
    echo "CHECK: would run: bash $CWH --install   (skipped — inspect-only)"
else
    _mtb_install_out="$(bash "$CWH" --install 2>&1)"
    _mtb_install_rc=$?
    echo "$_mtb_install_out"
    if [ "$_mtb_install_rc" -ne 0 ]; then
        echo "FATAL: multitrack_cwd_hook.sh --install failed (rc=$_mtb_install_rc)" >&2
        exit 1
    fi
fi
echo

# ---------------------------------------------------------------------------
# STEP 2/5 — verify (never install) the toolkit alias + symlink target
#            (INFORMATIONAL — absence is never fatal, §11.4.177)
# ---------------------------------------------------------------------------
echo "-- step 2/5: verify toolkit wiring (informational only) --"
if command -v claude1 >/dev/null 2>&1; then
    echo "OK: claude1 resolves on PATH (Claude-Toolkit account alias present)"
else
    echo "NOTE: claude1 not found on PATH — account provisioning is the"
    echo "      Claude-Toolkit's own job (outside this bootstrap's scope);"
    echo "      the cwd-hook engages the instant it IS provisioned."
fi
_mtb_link="${CMA_CWD_HOOK:-$HOME/.local/bin/claude-cwd-hook}"
if [ -L "$_mtb_link" ]; then
    _mtb_target="$(readlink "$_mtb_link" 2>/dev/null)"
    if [ "$_mtb_target" = "$MTB_DIR/multitrack_cwd_hook.sh" ]; then
        echo "OK: $_mtb_link -> $_mtb_target (resolves to the constitution copy)"
    else
        echo "NOTE: $_mtb_link -> $_mtb_target (points elsewhere — left as-is;"
        echo "      --install refuses to clobber a foreign symlink)"
    fi
elif [ "$MTB_CHECK" -eq 1 ]; then
    echo "NOTE: $_mtb_link is not a symlink (nothing was installed — inspect-only run)"
else
    echo "NOTE: $_mtb_link is not a symlink (unexpected right after --install)"
fi
echo

# ---------------------------------------------------------------------------
# STEP 3/5 — validate config (THE fatal path — §11.4.6, never invent data)
# ---------------------------------------------------------------------------
echo "-- step 3/5: validate per-host config --"
_mtb_host="${MT_HOST:-$(mt_resolve_host)}"
# §11.4.187 universality: a per-host config is loaded exactly as before; a host
# with NO config falls back to the universal DEFAULT single-track mode (ONE
# track, track-1 = the invocation project root) with a loud notice; a config
# that EXISTS but is malformed/zero-track stays FATAL (rc 3) — that IS ambiguity
# and is NEVER defaulted past (§11.4.6). Strict pre-§11.4.187 behaviour (fatal
# on a missing config) remains available via MT_REQUIRE_HOST_CONFIG=1.
mt_resolve_and_load
_mtb_cfg_rc=$?
if [ "$_mtb_cfg_rc" -eq 3 ]; then
    echo "FATAL: the per-host config for host='$_mtb_host' exists but is unusable" >&2
    echo "       (unparsable, or it defines zero tracks). A malformed config is" >&2
    echo "       never defaulted past — fix it, or remove it to fall back to" >&2
    echo "       default single-track mode." >&2
    exit 3
fi
if [ "$_mtb_cfg_rc" -ne 0 ]; then
    echo "FATAL: no per-host multitrack config for host='$_mtb_host'" >&2
    echo "       (looked under $(mt_config_dir)/$_mtb_host.yaml)" >&2
    echo "       and no default single-track fallback could be established." >&2
    cat >&2 <<OPBLOCK

OPERATOR STEP REQUIRED (§11.4.6 — host config is DATA, never invented):
  Author config/multitrack/${_mtb_host}.yaml (schema_version: 1), e.g.:

    schema_version: 1
    host:
      hostname: "${_mtb_host}"
    tracks:
      - id: track-1
        role: main
        mount: "/path/to/track-1"
      - id: track-2
        role: feature
        drive_serial: "<stable-drive-serial>"
        mount: "/path/to/track-2"

  Then re-run: bash "$MTB_SELF" "$PROJECT_ROOT"
OPBLOCK
    exit 2
fi
_mtb_cfg="${MT_CFG_FILE:-}"
if [ "${MT_DEFAULT_MODE:-0}" = "1" ]; then
    echo "OK: DEFAULT SINGLE-TRACK MODE (no per-host config for '$_mtb_host')"
    echo "    MT_TRACK_COUNT=$MT_TRACK_COUNT  track-1=${MT_DEFAULT_TRACK1_ROOT:-?}"
else
    echo "OK: $_mtb_cfg loaded, MT_TRACK_COUNT=$MT_TRACK_COUNT"
fi
echo

# ---------------------------------------------------------------------------
# STEP 4/5 — seed orchestrator state (idempotent reconcile + status confirm)
# ---------------------------------------------------------------------------
echo "-- step 4/5: orchestrator reconcile + status --"
if [ "$MTB_CHECK" -eq 1 ]; then
    echo "CHECK: would run: bash $ORCH reconcile && bash $ORCH status   (skipped — inspect-only)"
    echo
else
_mtb_reconcile_out="$(bash "$ORCH" reconcile 2>&1)"
_mtb_reconcile_rc=$?
echo "$_mtb_reconcile_out"
if [ "$_mtb_reconcile_rc" -ne 0 ]; then
    echo "FATAL: orchestrator reconcile failed (rc=$_mtb_reconcile_rc)" >&2
    exit 4
fi
_mtb_status_out="$(bash "$ORCH" status 2>&1)"
_mtb_status_rc=$?
echo "$_mtb_status_out"
if [ "$_mtb_status_rc" -ne 0 ]; then
    echo "FATAL: orchestrator status failed (rc=$_mtb_status_rc)" >&2
    exit 4
fi
echo "OK: orchestrator reconcile+status rc=0"
fi
echo

# ---------------------------------------------------------------------------
# STEP 5/5 — operator-gate drive-prep (§11.4.133/§9-D8, READ-ONLY, informational)
# ---------------------------------------------------------------------------
echo "-- step 5/5: track drive readiness (read-only probe) --"
_mtb_plan="$(mt_plan 2>/dev/null || true)"
printf '%s\n' "$_mtb_plan" | while IFS= read -r _mtb_line; do
    case "$_mtb_line" in
        TRACKS_READY=*) : ;;   # the summary line, not a track (was caught by TRACK*)
        TRACK*STATUS=READY*) : ;;      # READY and READY-DIR both land here
        TRACK*)
            echo "NOTE: $_mtb_line"
            echo "      OPERATOR STEP (§11.4.133 — NEVER auto-mount/format):"
            echo "      mount/prep this track's drive per"
            echo "      docs/guides/MULTITRACK_WORKTREE_RUNBOOK.md, then re-run bootstrap."
            ;;
        *) : ;;
    esac
done
echo


# ---------------------------------------------------------------------------
# STEP 6 (opt-in, RB-FIX3 I-a) — start the RB-07 ruler self-supervisor
#            watchdog (multitrack_supervisor.sh watch) as a backgrounded
#            daemon. An independent code review found NOTHING real ever
#            invokes `watch` -- it was reachable only from its own test. This
#            closes that gap WITHOUT changing bootstrap's existing default
#            behaviour for any caller that has not opted in: disabled unless
#            MT_SUPERVISOR_WATCH_ENABLE=1 is set (§11.4.1 non-breaking --
#            rc, symlink, config, and orchestrator state stay byte-for-byte
#            identical to before this step existed when the flag is unset).
#            Idempotency mirrors the EXACT pgrep-based guard multitrack_cwd_
#            hook.sh's _cwh_monitor_async already uses for its own
#            backgrounded daemon (§11.4.74 extend-not-reinvent) -- never a
#            new PID-file convention.
# ---------------------------------------------------------------------------
echo "-- step 6 (opt-in): ruler supervisor watchdog --"
SUP="$MTB_DIR/multitrack_supervisor.sh"
if [ "$MTB_CHECK" -eq 1 ]; then
    echo "CHECK: would evaluate the supervisor watchdog (MT_SUPERVISOR_WATCH_ENABLE=${MT_SUPERVISOR_WATCH_ENABLE:-0}); starts nothing — inspect-only"
elif [ "${MT_SUPERVISOR_WATCH_ENABLE:-0}" != "1" ]; then
    echo "NOTE: disabled by default -- set MT_SUPERVISOR_WATCH_ENABLE=1 to start the watchdog"
elif [ ! -r "$SUP" ]; then
    echo "NOTE: multitrack_supervisor.sh not found at $SUP -- watchdog NOT started"
else
    _mtb_watch_interval="${MT_SUPERVISOR_WATCH_INTERVAL:-15}"
    _mtb_watch_sig="multitrack_supervisor.sh watch --interval $_mtb_watch_interval"
    _mtb_watch_running=0
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "$_mtb_watch_sig" >/dev/null 2>&1 && _mtb_watch_running=1
    fi
    if [ "$_mtb_watch_running" = "1" ]; then
        echo "OK: supervisor watchdog already running (matches '$_mtb_watch_sig')"
    else
        _mtb_watch_logdir="$PROJECT_ROOT/.ws_state/multitrack"
        mkdir -p "$_mtb_watch_logdir" 2>/dev/null || _mtb_watch_logdir="${TMPDIR:-/tmp}"
        _mtb_watch_log="${MT_SUPERVISOR_WATCH_LOG:-$_mtb_watch_logdir/supervisor_watch_$(date +%s).log}"
        nohup sh "$SUP" watch --interval "$_mtb_watch_interval" > "$_mtb_watch_log" 2>&1 &
        _mtb_watch_pid=$!
        disown "$_mtb_watch_pid" 2>/dev/null || true
        echo "OK: supervisor watchdog started (pid=$_mtb_watch_pid, log=$_mtb_watch_log)"
    fi
fi
echo

echo "== multitrack_bootstrap.sh: DONE (PROJECT_ROOT=$PROJECT_ROOT, tracks=$MT_TRACK_COUNT) =="
exit 0
