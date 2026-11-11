#!/bin/sh
# =============================================================================
# multitrack_supervisor.sh — RB-07 ruler self-supervisor + durable handoff
#     (D-2 fix): the multi-track ruler (Track-1 conductor) writes a DURABLE
#     ruler_state.json (per-track alias/session_id/worktree/last-verdict) and
#     is itself crash-resilient via a lightweight watchdog that re-hydrates
#     every track's known state after a ruler death — so a conductor crash
#     never loses the multi-track state (§11.4.131 durable-resumption-file
#     discipline applied to the ruler layer + §11.4.147 crash-respawn).
# -----------------------------------------------------------------------------
# Purpose:
#   Close the D-2 gap identified in docs/superpowers/plans/ruler_bridge_plan.md
#   RB-07: RB-05's own agent-registry (multitrack_sessions.sh's events.jsonl +
#   tracks/<track>.json) defaults to `${XDG_RUNTIME_DIR:-/tmp}/<repo>/multitrack
#   /sessions` -- a TMPFS-class location that does NOT survive a reboot / a
#   container restart / any tmpfs-clearing event that can co-occur with a ruler
#   crash. If the ruler dies at the same moment the tmpfs area is lost, EVERY
#   track's alias/session_id/worktree binding is gone with no way to recover
#   which track was talking to which alias, from where, with what session.
#
#   This file adds a SEPARATE, DURABLE side-channel:
#     (1) `snapshot`  -- read RB-05's live registry (tracks/<t>.json, falling
#         back to a replay of events.jsonl when a per-track snapshot file is
#         itself missing) and MERGE it into a durable `ruler_state.json`,
#         written by write-temp-then-rename (atomic, never a torn read) to a
#         location that NEVER defaults to `${XDG_RUNTIME_DIR}` or `/tmp`.
#     (2) `watch [--once]` -- a lightweight watchdog: check whether the
#         `ruler_pid` recorded in the durable state is still alive
#         (`kill -0`). If DEAD (or no prior state exists at all), REHYDRATE:
#         re-run the same merge (durable-state-as-base, live-registry-as-
#         overlay-when-present, events.jsonl-replay-as-fallback-when-the-
#         live per-track snapshot is itself missing) and claim a fresh
#         `ruler_pid` (the watcher itself, or an explicit `--ruler-pid`) --
#         so every track's alias/session_id/worktree is recovered even if
#         the live registry was wiped in the SAME event that killed the
#         ruler.
#     (3) `status` -- print the current durable state (or an honest
#         "no state" message naming the resolved path -- §11.4.6, never a
#         silent empty success).
#
#   ruler_state.json is newline-delimited JSON (JSONL): line 1 is the header
#   record `{"ruler_pid":...,"updated":...[,"rehydrated_at":...]}`; every
#   subsequent line is one independently-valid-JSON per-track record
#   `{"track":...,"alias":...,"session_id":...,"cwd":...,"last_verdict":...}`.
#   This is a DELIBERATE, DOCUMENTED format choice (matching the events.jsonl
#   style RB-05 already ships) -- POSIX sh has no JSON-array serializer, and
#   hand-rolling a single valid JSON array/object with an unbounded, dynamic
#   number of per-track members in `sh` is exactly the kind of fragile
#   string-surgery this project avoids; every line is still trivially valid
#   JSON on its own, and every consumer (this file, its test, a future `jq
#   -R 'fromjson?'` reader) can parse it line-by-line.
#
#   CONSTITUTION-LAYER + PROJECT-AGNOSTIC (§11.4.28 / §11.4.35 / §11.4.177):
#   no project name, no device serial, no package id, no region string, no
#   hardcoded alias. multitrack_sessions.sh (RB-05) and multitrack_config.sh
#   are referenced BY CONTRACT (same env-var names, same default-path formula,
#   same JSON field names) -- multitrack_sessions.sh is NOT `.`-sourced here
#   because it is an EXECUTABLE entry point ending in an unconditional
#   `main "$@"` call; sourcing an executable-style script would re-run its
#   dispatcher against THIS script's own argv, which is unsafe. Reading its
#   on-disk registry format (a stable, documented contract) is safe and is
#   the pattern this file uses.
#
# Usage (EXECUTED, not sourced):
#   multitrack_supervisor.sh snapshot [--ruler-pid PID]
#   multitrack_supervisor.sh watch    [--once] [--interval SECONDS] [--ruler-pid PID]
#   multitrack_supervisor.sh status
#   multitrack_supervisor.sh -h | --help
#
# Inputs (env, all optional):
#   MT_RULER_STATE_DIR   durable state directory. Default resolution NEVER
#                         touches `${XDG_RUNTIME_DIR}` or a hardcoded `/tmp`
#                         path -- it derives `<repo-root>/.ws_state/multitrack`
#                         (the SAME durable, git-tracked-style state directory
#                         the rest of the multi-track substrate already uses
#                         for streams.tsv / claims.jsonl / track_orchestration
#                         .tsv), falling back to `${HOME:-.}/.multitrack_ruler
#                         _state` only when no repo root is resolvable at all
#                         (still never a tmpfs-class path).
#   MT_SESSIONS_DIR       RB-05 registry root (events.jsonl + tracks/<track>
#                         .json). Same env var + same default formula as
#                         multitrack_sessions.sh (`${XDG_RUNTIME_DIR:-/tmp}/
#                         <repo-basename>/multitrack/sessions`) -- that
#                         default IS tmpfs by RB-05's own design (the live,
#                         ephemeral, per-boot registry); THIS file's own
#                         state file is the durable side-channel that survives
#                         when that ephemeral area is lost.
#   MT_REPO_ROOT          consumer project root (else git toplevel from here).
#
# Outputs: PASS/decision/status lines on stdout; the durable `ruler_state
#   .json` under MT_RULER_STATE_DIR, atomically written (write-temp-then-
#   rename, never a torn read for a concurrent reader).
#
# Side-effects: writes ONLY under MT_RULER_STATE_DIR (mkdir -p + one
#   temp-file + one rename per write); reads (read-only) under
#   MT_SESSIONS_DIR; never spawns a worker, never touches a device, never
#   touches a credential, never deletes anything.
#
# Dependencies: sh (POSIX), sed, grep, date, mkdir, mv, kill (for the
#   liveness check), cut.
#
# Cross-references: docs/superpowers/plans/ruler_bridge_plan.md RB-07;
#   constitution/scripts/multitrack/multitrack_sessions.sh (RB-05 -- the
#   registry this file reads BY CONTRACT, never sourced); constitution/
#   scripts/multitrack/multitrack_config.sh (repo-root/self-dir resolution
#   convention referenced, not sourced -- this file re-implements the same
#   tiny formula rather than sourcing a library not designed as a pure
#   function set for this purpose); constitution/scripts/multitrack/
#   test_multitrack_supervisor.sh (RED/GREEN §11.4.115 polarity driver,
#   alongside this file); §11.4.131 (durable session-resumption file
#   discipline -- this is that discipline applied to the ruler layer
#   itself); §11.4.147 (crash-respawn -- no-work-loss registry mandate);
#   §11.4.116 (real-time sync-channel / atomically-rewritten snapshot
#   convention this file's write-temp-then-rename follows); §11.4.28 /
#   §11.4.177 (project-agnostic, engine-in-constitution, no project string).
#   Companion doc docs/scripts/multitrack_supervisor.md is NOT authored by
#   this PWU (flagged for the conductor -- none of this file's sibling
#   scripts under constitution/scripts/multitrack/ have a docs/scripts/*.md
#   companion either; pre-existing gap, not a regression introduced here).
# =============================================================================

set -u

# ---------------------------------------------------------------------------
# self-location (POSIX $0; executed, not sourced).
# ---------------------------------------------------------------------------
SUP_SELF=$0
case "$SUP_SELF" in
    */*) SUP_DIR=${SUP_SELF%/*} ;;
    *)   SUP_DIR=. ;;
esac

_sup_repo_root() {
    if [ -n "${MT_REPO_ROOT:-}" ]; then printf '%s\n' "$MT_REPO_ROOT"; return 0; fi
    ( cd "$SUP_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}

# --- RB-05 live-registry location (BY CONTRACT — same env var + same default
#     formula as multitrack_sessions.sh's own _mts_sessions_dir; that default
#     IS tmpfs by RB-05's design — the ephemeral side this file complements).
_sup_sessions_dir() {
    if [ -n "${MT_SESSIONS_DIR:-}" ]; then printf '%s\n' "$MT_SESSIONS_DIR"; return 0; fi
    _rr=$(_sup_repo_root); _base=$(basename "${_rr:-project}")
    printf '%s\n' "${XDG_RUNTIME_DIR:-/tmp}/$_base/multitrack/sessions"
}

# --- THE durable side-channel (RB-07). NEVER `${XDG_RUNTIME_DIR}`, NEVER a
#     hardcoded `/tmp` path — this is the exact invariant the paired §1.1
#     mutation flips to reproduce the D-2 defect ("point the state file back
#     at tmpfs"). Region-marked (mirrors the RB-02 MT_MAX_WORKERS_CLAMP /
#     MT_BUILD_PGREP_GUARD idiom) so the gate can assert this exact function
#     body never mentions XDG_RUNTIME_DIR, and the paired mutation can target
#     it precisely without touching _sup_sessions_dir()'s OWN, DELIBERATE
#     XDG_RUNTIME_DIR reference just above (RB-05's live registry IS allowed
#     to default to tmpfs; only THIS function may not).
# >>MRS_NO_TMPFS_DEFAULT
_sup_ruler_state_dir() {
    if [ -n "${MT_RULER_STATE_DIR:-}" ]; then printf '%s\n' "$MT_RULER_STATE_DIR"; return 0; fi
    _rr=$(_sup_repo_root)
    if [ -n "$_rr" ]; then printf '%s\n' "$_rr/.ws_state/multitrack"; return 0; fi
    printf '%s\n' "${HOME:-.}/.multitrack_ruler_state"
}
# <<MRS_NO_TMPFS_DEFAULT

MT_SESSIONS_DIR_RESOLVED=$(_sup_sessions_dir)
MT_SESSIONS_TRACKS_DIR="$MT_SESSIONS_DIR_RESOLVED/tracks"
MT_SESSIONS_EVENTS="$MT_SESSIONS_DIR_RESOLVED/events.jsonl"

STATE_DIR=$(_sup_ruler_state_dir)
STATE_FILE="$STATE_DIR/ruler_state.json"

# ---------------------------------------------------------------------------
# tiny JSON helpers (same sed-based extraction idiom as multitrack_sessions.sh
# _mts_json_str / _mts_json_escape — one field per line, values never contain
# unescaped quotes).
# ---------------------------------------------------------------------------
_sup_now() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }
_sup_json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
_sup_json_str() { sed -n 's/.*"'"$1"'":"\([^"]*\)".*/\1/p' | head -n1; }

# ---------------------------------------------------------------------------
# enumerate every track NAME known from any of the three sources: the
# existing durable state, the live registry's per-track snapshot dir, and the
# live registry's events.jsonl. Sorted + de-duplicated.
# ---------------------------------------------------------------------------
_sup_all_tracks() {
    {
        if [ -f "$STATE_FILE" ]; then
            tail -n +2 "$STATE_FILE" 2>/dev/null | while IFS= read -r _l; do
                printf '%s\n' "$_l" | _sup_json_str track
            done
        fi
        if [ -d "$MT_SESSIONS_TRACKS_DIR" ]; then
            for _f in "$MT_SESSIONS_TRACKS_DIR"/*.json; do
                [ -e "$_f" ] || continue
                _b=$(basename "$_f")
                printf '%s\n' "${_b%.json}"
            done
        fi
        if [ -f "$MT_SESSIONS_EVENTS" ]; then
            grep -o '"track":"[^"]*"' "$MT_SESSIONS_EVENTS" 2>/dev/null | sed 's/.*"track":"\([^"]*\)"/\1/'
        fi
    } | grep -v '^[[:space:]]*$' | sort -u
}

# ---------------------------------------------------------------------------
# resolve ONE track's {alias, session_id, cwd/worktree, last_verdict}, in
# priority order: (1) the live per-track snapshot file (freshest, RB-05's own
# atomic write) -> (2) a replay of events.jsonl, LAST matching line wins
# (present even when the per-track snapshot file itself is missing/corrupt)
# -> (3) the EXISTING durable ruler_state.json record (the only surviving
# source when the entire live registry area was lost together with the
# ruler — the D-2 recovery path this file exists to provide).
#   prints "<alias>\t<session_id>\t<cwd>\t<last_verdict>"; rc 3 if unresolved.
# ---------------------------------------------------------------------------
_sup_resolve_track() {
    _t="$1"
    _tf="$MT_SESSIONS_TRACKS_DIR/$_t.json"
    if [ -f "$_tf" ]; then
        _alias=$(_sup_json_str alias < "$_tf")
        _sid=$(_sup_json_str session_id < "$_tf")
        _cwd=$(_sup_json_str cwd < "$_tf")
        _st=$(_sup_json_str status < "$_tf")
        printf '%s\t%s\t%s\t%s\n' "$_alias" "$_sid" "$_cwd" "${_st:-unknown}"
        return 0
    fi
    if [ -f "$MT_SESSIONS_EVENTS" ]; then
        _line=$(grep -F "\"track\":\"$_t\"" "$MT_SESSIONS_EVENTS" 2>/dev/null | tail -n1)
        if [ -n "$_line" ]; then
            _alias=$(printf '%s' "$_line" | _sup_json_str alias)
            _sid=$(printf '%s' "$_line" | _sup_json_str session_id)
            _cwd=$(printf '%s' "$_line" | _sup_json_str cwd)
            _st=$(printf '%s' "$_line" | _sup_json_str status)
            printf '%s\t%s\t%s\t%s\n' "$_alias" "$_sid" "$_cwd" "${_st:-unknown}"
            return 0
        fi
    fi
    if [ -f "$STATE_FILE" ]; then
        _line=$(tail -n +2 "$STATE_FILE" 2>/dev/null | grep -F "\"track\":\"$_t\"" | tail -n1)
        if [ -n "$_line" ]; then
            _alias=$(printf '%s' "$_line" | _sup_json_str alias)
            _sid=$(printf '%s' "$_line" | _sup_json_str session_id)
            _cwd=$(printf '%s' "$_line" | _sup_json_str cwd)
            _lv=$(printf '%s' "$_line" | _sup_json_str last_verdict)
            printf '%s\t%s\t%s\t%s\n' "$_alias" "$_sid" "$_cwd" "${_lv:-unknown}"
            return 0
        fi
    fi
    return 3
}

# ---------------------------------------------------------------------------
# atomic write-temp-then-rename of the merged durable state.
#   $1 = ruler_pid to record;  $2 = "1" iff this write is a rehydrate (dead-
#   ruler recovery) so the caller/test can distinguish a plain snapshot from
#   a genuine rehydrate event.
# ---------------------------------------------------------------------------
_sup_write_state() {
    _pid="$1"; _rehydrated="${2:-}"
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    _tmp="$STATE_FILE.tmp.$$"
    {
        if [ -n "$_rehydrated" ]; then
            printf '{"ruler_pid":"%s","updated":"%s","rehydrated_at":"%s"}\n' \
                "$(_sup_json_escape "$_pid")" "$(_sup_now)" "$(_sup_now)"
        else
            printf '{"ruler_pid":"%s","updated":"%s"}\n' "$(_sup_json_escape "$_pid")" "$(_sup_now)"
        fi
        for _t in $(_sup_all_tracks); do
            _rec=$(_sup_resolve_track "$_t") || continue
            _alias=$(printf '%s' "$_rec" | cut -f1)
            _sid=$(printf '%s' "$_rec" | cut -f2)
            _cwd=$(printf '%s' "$_rec" | cut -f3)
            _lv=$(printf '%s' "$_rec" | cut -f4)
            printf '{"track":"%s","alias":"%s","session_id":"%s","cwd":"%s","last_verdict":"%s"}\n' \
                "$(_sup_json_escape "$_t")" "$(_sup_json_escape "$_alias")" \
                "$(_sup_json_escape "$_sid")" "$(_sup_json_escape "$_cwd")" \
                "$(_sup_json_escape "$_lv")"
        done
    } > "$_tmp" && mv -f "$_tmp" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# commands
# ---------------------------------------------------------------------------
cmd_snapshot() {
    _pid="$$"
    while [ $# -gt 0 ]; do
        case "$1" in
            --ruler-pid) _pid="${2:-$$}"; shift 2 ;;
            *) shift ;;
        esac
    done
    _sup_write_state "$_pid" ""
    _n=$(_sup_all_tracks | grep -c . 2>/dev/null)
    printf 'SNAPSHOT: ruler_pid=%s state=%s tracks=%s\n' "$_pid" "$STATE_FILE" "${_n:-0}"
}

cmd_watch() {
    _once=0; _interval=15; _claim_pid=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --once) _once=1; shift ;;
            --interval) _interval="${2:-15}"; shift 2 ;;
            --ruler-pid) _claim_pid="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done
    # The sleep between iterations runs in the background and is waited for,
    # so a SIGTERM/SIGINT/SIGHUP to the daemon stops that sleep too. With a
    # foreground `sleep` the shell died on the signal and its sleep was
    # orphaned to init for a whole interval (CON-128, review F-PRE-1). The
    # child pid is a single positive pid (section 11.4.263), never a group.
    _sup_sleep_pid=""
    trap '_sup_watch_stop 143' TERM
    trap '_sup_watch_stop 130' INT
    trap '_sup_watch_stop 129' HUP
    while :; do
        _recorded_pid=""
        [ -f "$STATE_FILE" ] && _recorded_pid=$(head -n1 "$STATE_FILE" 2>/dev/null | _sup_json_str ruler_pid)
        if [ -n "$_recorded_pid" ] && kill -0 "$_recorded_pid" 2>/dev/null; then
            printf 'WATCH: ruler alive (pid=%s) -- no action\n' "$_recorded_pid"
        else
            _new_pid="${_claim_pid:-$$}"
            printf 'WATCH: ruler DEAD (recorded pid=%s) -- REHYDRATING (claiming ruler_pid=%s)\n' \
                "${_recorded_pid:-<none>}" "$_new_pid"
            _sup_write_state "$_new_pid" "1"
            _n=$(_sup_all_tracks | grep -c . 2>/dev/null)
            printf 'REHYDRATE: state=%s tracks_recovered=%s\n' "$STATE_FILE" "${_n:-0}"
        fi
        [ "$_once" = "1" ] && { trap - TERM INT HUP; return 0; }
        sleep "$_interval" 2>/dev/null &
        _sup_sleep_pid=$!
        wait "$_sup_sleep_pid" || sleep 1
        _sup_sleep_pid=""
    done
}

# _sup_watch_stop <rc>: signal handler of `watch`; stops the pending sleep
# child, then exits with <rc>.
_sup_watch_stop() {
    case "${_sup_sleep_pid:-}" in
        ''|*[!0-9]*) ;;
        *) [ "$_sup_sleep_pid" -gt 1 ] && kill "$_sup_sleep_pid" 2>/dev/null ;;
    esac
    exit "$1"
}

cmd_status() {
    if [ ! -f "$STATE_FILE" ]; then
        printf 'status: no state (%s)\n' "$STATE_FILE"
        return 0
    fi
    cat "$STATE_FILE"
}

usage() {
    cat >&2 <<'USG'
usage: multitrack_supervisor.sh <command> [args]
  snapshot [--ruler-pid PID]
  watch    [--once] [--interval SECONDS] [--ruler-pid PID]
  status
  -h | --help
env:
  MT_RULER_STATE_DIR  durable ruler_state.json dir (NEVER defaults to
                       ${XDG_RUNTIME_DIR} or /tmp -- see docstring)
  MT_SESSIONS_DIR      RB-05 live registry root (events.jsonl + tracks/*.json)
  MT_REPO_ROOT         consumer project root (else git toplevel from here)
USG
}

main() {
    _cmd="${1:-}"; shift 2>/dev/null || true
    case "$_cmd" in
        snapshot) cmd_snapshot "$@" ;;
        watch)    cmd_watch    "$@" ;;
        status)   cmd_status   "$@" ;;
        -h|--help|help|'') usage; [ -n "$_cmd" ] && return 0 || return 2 ;;
        *) usage; return 2 ;;
    esac
}

main "$@"
