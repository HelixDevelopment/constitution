#!/usr/bin/env bash
# =============================================================================
# multitrack.sh — multi-track development top-level ENTRYPOINT ("permanent-
#                 switch" wiring seam). §11.4.167 / §11.4.21 / §11.4.101 /
#                 §11.4.119 / §11.4.133 / §11.4.6.
# -----------------------------------------------------------------------------
# Purpose:
#   ONE operational entrypoint that BINDS the three already-built, standalone
#   multi-track pieces into a single command surface, WITHOUT reimplementing any
#   of them:
#     * multitrack_config.sh       — host/config resolution + track enumeration
#     * multitrack_registry.sh     — the .ws_state/streams.tsv state accessor
#     * multitrack_device_lock.sh  — the D1/D2 device-lock arbiter
#   It operates on the SOFTWARE layer (no mounted drives required) so it is
#   testable NOW: it PROBES (read-only) whether each track's drive is mounted,
#   reports the registry + device-lock state, and — when a track's LUKS2 drive
#   is not mounted (mounting needs operator `su` + the LUKS passphrase) — reports
#   OPERATOR-BLOCKED HONESTLY per §11.4.21 / §11.4.101 instead of faking success
#   or attempting a mount (§11.4.133 forbids autonomous mount/format).
#
# Usage:
#   multitrack.sh status   # read-only: per-track registry row + live mount probe
#                          # + device-lock pool state. Exit 0 (it is a REPORT;
#                          # blocked tracks are DATA in the report, not a failure).
#   multitrack.sh up       # preflight: probe mounts (read-only), reconcile the
#                          # registry to live reality (only on divergence), report
#                          # what is blocked. NEVER mounts / formats. Exit 0 if
#                          # every track is live-mounted; exit 20 (OPERATOR-BLOCKED)
#                          # if any track needs operator action to bring up.
#   multitrack.sh help
#
# Inputs:
#   Env MT_HOST / MT_CONFIG   host / config-file override (else auto-resolved via
#                             multitrack_config.sh, exactly like the sibling scripts)
#   Env MT_STREAMS_TSV        registry path (forwarded to multitrack_registry.sh)
#   Env MT_REGISTRY_LOCK      registry flock (forwarded); default runtime tmpfs
#   (device-lock env — MT_LOCK_DIR etc. — flows through to the arbiter subprocess)
#
# Outputs:  a human-readable per-track table + a device-lock pool section on stdout.
# Exit codes: 0 ok · 2 usage · 20 OPERATOR-BLOCKED (up: track(s) need operator
#             mount) · 1 internal error (config unresolvable, missing sibling, ...).
#
# Side-effects:
#   status = READ-ONLY (no writes anywhere in the repo). up = MAY reconcile the
#   registry via multitrack_registry.sh set ONLY when the LIVE mount state
#   DIFFERS from the recorded state (atomic TSV rewrite; a no-op on an all-
#   unmounted host). NEVER mounts, unmounts, formats, or otherwise touches a
#   physical drive (§11.4.133) — mounting the LUKS2 drives is the operator's
#   su+passphrase job (docs/guides/MULTITRACK_WORKTREE_RUNBOOK.md).
#
# Dependencies: bash (POSIX-clean body), awk; the three sibling multitrack_*.sh;
#   reads /proc/self/mounts (read-only) for the live mount probe.
#
# Cross-references:
#   scripts/multitrack/multitrack_config.sh · multitrack_registry.sh ·
#   multitrack_device_lock.sh · docs/scripts/multitrack.md ·
#   docs/guides/MULTITRACK_WORKTREE_RUNBOOK.md · docs/guides/MULTITRACK_ACTIVATION.md
# =============================================================================

set -u

MT_SELF=$0
case "$MT_SELF" in
    */*) MT_DIR=${MT_SELF%/*} ;;
    *)   MT_DIR=. ;;
esac
export MT_SELF                 # so sourced multitrack_config.sh resolves repo root from HERE

CONFIG_LIB="$MT_DIR/multitrack_config.sh"
REGISTRY="$MT_DIR/multitrack_registry.sh"
DEVLOCK="$MT_DIR/multitrack_device_lock.sh"

[ -r "$CONFIG_LIB" ] || { echo "FATAL: missing sibling $CONFIG_LIB" >&2; exit 1; }
[ -r "$REGISTRY" ]   || { echo "FATAL: missing sibling $REGISTRY" >&2; exit 1; }
[ -r "$DEVLOCK" ]    || { echo "FATAL: missing sibling $DEVLOCK" >&2; exit 1; }

# shellcheck source=scripts/multitrack/multitrack_config.sh disable=SC1091
. "$CONFIG_LIB"

OPBLOCKED_RC=20

# delegate helpers (invoked under `bash` so the exec bit is not required) -------
_reg()     { bash "$REGISTRY" "$@"; }
_devlock() { bash "$DEVLOCK" "$@"; }

usage() {
cat <<'EOF'
multitrack.sh — multi-track development entrypoint (§11.4.167)

  status   read-only: per-track registry + live mount probe + device-lock state
  up       preflight mounts (read-only), reconcile registry, report blocked;
           NEVER mounts/formats a drive
  help     this help

Env : MT_HOST  MT_CONFIG  MT_STREAMS_TSV  MT_REGISTRY_LOCK
Exit: 0 ok · 2 usage · 20 operator-blocked (up) · 1 internal
See docs/scripts/multitrack.md + docs/guides/MULTITRACK_WORKTREE_RUNBOOK.md
EOF
}

# --- read-only live mount probe (root-free; never touches a drive) ------------
# 0 = a filesystem is currently mounted AT the given mountpoint, else 1.
_is_mounted() {
    _im_mp=$1
    [ -n "$_im_mp" ] || return 1
    _im_f=/proc/self/mounts
    [ -r "$_im_f" ] || _im_f=/proc/mounts
    [ -r "$_im_f" ] || return 1
    awk -v mp="$_im_mp" '$2==mp { f=1; exit } END { exit(f?0:1) }' "$_im_f"
}

# --- track readiness, serial-aware (§11.4.187 / §11.4.201) --------------------
# A DRIVE-backed track (one with a drive_serial) is ready IFF a filesystem is
# mounted at its mountpoint — unchanged. A track with NO drive_serial is a plain
# DIRECTORY (default single-track mode, or any directory track an operator
# configures): it is ready IFF that directory EXISTS. Probing /proc/mounts for a
# directory track reports "unmounted" for a perfectly usable track and drags in
# the LUKS operator-blocked hand-off that does not apply to it — the §11.4.201
# false-refusal class. Args: <track-index> <mountpoint>.
_track_ready() {
    _tr_i=$1; _tr_mp=$2
    eval "_tr_serial=\${MT_TRACK_${_tr_i}_SERIAL:-}"
    if [ -n "${_tr_serial:-}" ]; then
        _is_mounted "$_tr_mp"
        return $?
    fi
    [ -n "$_tr_mp" ] && [ -d "$_tr_mp" ]
}

# --- host/config resolution (delegated to multitrack_config.sh) ---------------
# §11.4.187: delegates to mt_resolve_and_load — a real per-host config is loaded
# exactly as before; a host with NO config falls back to the universal DEFAULT
# single-track mode (track-1 = the invocation project root) with a loud notice;
# a config that EXISTS but is malformed stays FATAL (rc 3, never defaulted past).
_resolve_config() {
    _rc_host=${MT_HOST:-$(mt_resolve_host)}
    mt_resolve_and_load
    _rc_rc=$?
    case "$_rc_rc" in
        0) : ;;
        3) echo "FATAL: per-host multitrack config for host='$_rc_host' is present but unusable" >&2
           exit 1 ;;
        *) echo "FATAL: could not resolve a multitrack config for host='$_rc_host' (looked under $(mt_config_dir)) and no default could be established" >&2
           exit 1 ;;
    esac
    MT_CFG=${MT_CFG_FILE:-}
}

# --- the §11.4.21 OPERATOR-BLOCKED hand-off note ------------------------------
_print_block_note() {
cat <<'EOF'

OPERATOR-BLOCKED (§11.4.21) — one or more track drives are NOT mounted.
  WHAT    : mount each track's LUKS2+btrfs NVMe drive at its /mnt/trackN.
  WHY     : the drives are LUKS-locked; mounting needs `su` + the LUKS passphrase,
            which this agent does not hold, and §11.4.133 forbids autonomous
            mount/format of a physical drive. This is NOT a failure — it is a
            bounded operator hand-off (§11.4.101).
  UNBLOCK : operator opens + mounts the drives per
            docs/guides/MULTITRACK_WORKTREE_RUNBOOK.md
            (see also docs/guides/MULTITRACK_ACTIVATION.md), then re-runs
            `bash scripts/multitrack/multitrack.sh up`.
  WHO     : operator (root/su on host <host>).
EOF
}

cmd_status() {
    _resolve_config
    printf '== multi-track status (host=%s config=%s) ==\n' "${MT_HOSTNAME:-?}" "$MT_CFG"
    printf '%-9s %-7s %-22s %-10s %-16s %-14s %s\n' \
        TRACK ROLE BRANCH MOUNTED REG-MOUNT WS-STATE OVERALL
    _st_i=1; _st_blocked=0; _st_active=0
    # _st_id/_st_mount/_st_role/_st_branch are assigned via eval of the dynamic
    # MT_TRACK_<i>_* names (same idiom as the sibling multitrack scripts).
    # shellcheck disable=SC2154
    while [ "$_st_i" -le "$MT_TRACK_COUNT" ]; do
        eval "_st_id=\${MT_TRACK_${_st_i}_ID:-}"
        eval "_st_mount=\${MT_TRACK_${_st_i}_MOUNT:-}"
        eval "_st_role=\${MT_TRACK_${_st_i}_ROLE:-}"
        eval "_st_branch=\${MT_TRACK_${_st_i}_BRANCH:-}"
        _st_reg=$(_reg get "$_st_id" mount_state 2>/dev/null || printf '?')
        _st_ws=$(_reg get "$_st_id" ws_state 2>/dev/null || printf '?')
        eval "_st_serial=\${MT_TRACK_${_st_i}_SERIAL:-}"
        if _track_ready "$_st_i" "$_st_mount"; then
            if [ -n "${_st_serial:-}" ]; then _st_live=mounted; else _st_live=directory; fi
            _st_overall=ACTIVE; _st_active=$((_st_active + 1))
        elif [ -z "${_st_serial:-}" ]; then
            # directory track whose directory is absent — a real problem, but
            # NOT a LUKS/mount operator hand-off (never counted as blocked).
            _st_live=missing-dir; _st_overall=MISSING-DIR
        else
            _st_live=unmounted; _st_blocked=$((_st_blocked + 1))
            case "$_st_reg" in
                unmounted-locked) _st_overall=OPERATOR-BLOCKED ;;
                *)                _st_overall=UNMOUNTED ;;
            esac
        fi
        printf '%-9s %-7s %-22s %-10s %-16s %-14s %s\n' \
            "$_st_id" "$_st_role" "${_st_branch:--}" "$_st_live" "$_st_reg" "$_st_ws" "$_st_overall"
        _st_i=$((_st_i + 1))
    done
    printf '\nSummary: %s active, %s not-mounted (of %s tracks)\n' \
        "$_st_active" "$_st_blocked" "$MT_TRACK_COUNT"
    [ "$_st_blocked" -gt 0 ] && _print_block_note
    printf '\n== device-lock pool (delegated to multitrack_device_lock.sh) ==\n'
    _devlock status 2>&1 || printf '(device-lock status unavailable — see message above)\n'
    return 0
}

cmd_up() {
    _resolve_config
    printf '== multi-track up (preflight; host=%s) ==\n' "${MT_HOSTNAME:-?}"
    _up_i=1; _up_blocked=0; _up_ok=0; _up_reconciled=0
    # _up_id/_up_mount are assigned via eval of the dynamic MT_TRACK_<i>_* names.
    # shellcheck disable=SC2154
    while [ "$_up_i" -le "$MT_TRACK_COUNT" ]; do
        eval "_up_id=\${MT_TRACK_${_up_i}_ID:-}"
        eval "_up_mount=\${MT_TRACK_${_up_i}_MOUNT:-}"
        _up_reg=$(_reg get "$_up_id" mount_state 2>/dev/null || printf '?')
        eval "_up_serial=\${MT_TRACK_${_up_i}_SERIAL:-}"
        if _track_ready "$_up_i" "$_up_mount"; then
            _up_note=""
            [ -n "${_up_serial:-}" ] || _up_note="(directory track — no drive)"
            if [ "$_up_reg" != "mounted" ]; then
                if _reg set "$_up_id" mount_state mounted >/dev/null 2>&1; then
                    _up_reconciled=$((_up_reconciled + 1))
                    _up_note="(reconciled: $_up_reg -> mounted)"
                else
                    _up_note="(reconcile FAILED — inspect registry)"
                fi
            fi
            printf '  %-9s %-12s at %-12s %s\n' "$_up_id" \
                "$( [ -n "${_up_serial:-}" ] && printf MOUNTED || printf READY-DIR )" \
                "$_up_mount" "$_up_note"
            _up_ok=$((_up_ok + 1))
        elif [ -z "${_up_serial:-}" ]; then
            # directory track with a missing directory: a real problem, but NOT
            # a LUKS/mount operator hand-off (§11.4.201 — never a false refusal).
            printf '  %-9s MISSING-DIR %s (create it, or fix the track mount)\n' "$_up_id" "$_up_mount"
            _up_blocked=$((_up_blocked + 1))
        else
            # not mounted: reconcile ONLY if the registry wrongly claims "mounted"
            if [ "$_up_reg" = "mounted" ]; then
                _reg set "$_up_id" mount_state unmounted-locked >/dev/null 2>&1 \
                    && _up_reconciled=$((_up_reconciled + 1))
                _up_reg=unmounted-locked
            fi
            printf '  %-9s NOT-MOUNTED (registry=%s) -> OPERATOR-BLOCKED\n' "$_up_id" "$_up_reg"
            _up_blocked=$((_up_blocked + 1))
        fi
        _up_i=$((_up_i + 1))
    done
    printf '\nUp: %s mounted, %s operator-blocked, %s registry reconcile(s).\n' \
        "$_up_ok" "$_up_blocked" "$_up_reconciled"
    if [ "$_up_blocked" -gt 0 ]; then
        _print_block_note
        return "$OPBLOCKED_RC"
    fi
    printf 'All tracks mounted — the multi-track layer is UP.\n'
    return 0
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
MT_CMD=$1; shift
case "$MT_CMD" in
    status)         cmd_status ;;
    up)             cmd_up ;;
    help|--help|-h) usage ;;
    *) echo "multitrack: unknown command '$MT_CMD'" >&2; usage >&2; exit 2 ;;
esac
