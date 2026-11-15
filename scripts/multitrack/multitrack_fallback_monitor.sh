#!/usr/bin/env bash
# =============================================================================
# multitrack_fallback_monitor.sh — per-alias rate-limit transcript monitor
#                                   (§11.4.177 auto-fallback / DESIGN §4.2(C)).
# -----------------------------------------------------------------------------
# Purpose:
#   Side-effect-free (§11.4.128 observer-effect budget) background monitor that
#   tails ONE Claude Code session transcript (JSONL) for a rate-limit signature
#   and, ONLY on a genuine quota-exhausted limit, triggers the alias<->track
#   orchestrator to fall the limited alias's track over to a healthy alias.
#
#   WHY transcript-tail and not exit-code / router-rotation (honest mechanism,
#   §11.4.6 / §11.4.123): the native interactive account path (claudeN =
#   `CLAUDE_CONFIG_DIR=… cma_run`) NEVER goes through the router, and a hard
#   usage-limit 429 does NOT make the interactive process exit — the session
#   CONTINUES with new turns (captured FACT, DESIGN §4.2 Option B). The ONLY
#   real-time signal for that path is the persisted transcript, where Claude
#   Code writes an API-error line. This is NOT true photon-level detection; it
#   is the DESIGN-confirmed transcript-signature approximation, the single
#   mechanism confirmed by BOTH official docs AND captured local evidence for
#   the interactive account path (DESIGN §4.2 "Why C").
#
#   Signature (captured FACT, DESIGN §4.2(C) — no UNCONFIRMED hedge):
#     STRUCTURAL  : a JSONL line containing BOTH  "apiErrorStatus":429
#                   AND                            "isApiErrorMessage":true
#     SUB-CLASSIFY by message text (the guard against false fallback):
#       quota-exhausted  → line ALSO carries a reset/weekly-limit marker
#                          (e.g. "resets", "weekly limit") — a session/usage
#                          limit that will NOT clear until reset  ⇒ ACT
#       transient        → line carries a not-your-usage-limit / retryable
#                          marker (e.g. "not your usage limit")   ⇒ NO-OP
#                          (Claude's own bounded backoff clears it; acting
#                          here would thrash the leases)
#       unclassified 429 → structural match, NO quota AND NO transient marker
#                          ⇒ NO-OP (safe default: never fire without positive
#                          quota evidence, §11.4.101 reversible-safe-decision)
#       no structural    → ignore
#
#   The STRUCTURAL signature set is consumer-overridable: it is read from
#   `mt_config_fallback_signatures` (multitrack_config.sh) when a --config /
#   MT_CONFIG path is given, else it falls back to the two captured-FACT
#   defaults built in below (README: "the monitor decides its own default").
#   Neither default is a project literal (§11.4.28) — both are Claude Code
#   transcript-format tokens, universal to every consumer.
#
# Usage:
#   multitrack_fallback_monitor.sh --daemon --alias A --track T --transcript P
#       Follow-mode (tail -F, new lines only): the long-lived per-alias monitor.
#       READ-ONLY on the transcript; bounded CPU; runs until killed OR until
#       MT_MONITOR_MAX_SECONDS (0 = unbounded). This is the START ENTRY POINT.
#   multitrack_fallback_monitor.sh --once   --alias A --track T --transcript P
#       Process the transcript's current contents ONCE (from MT_MONITOR_FROM_LINE,
#       default 1) then exit. Deterministic entry for anti-bluff tests / probes.
#   multitrack_fallback_monitor.sh --help
#
#   Options:  --alias A --track T --transcript P   (all three REQUIRED)
#             --route R            (optional; RB-06 — the balance route this
#                                   headless worker uses. When given, a HEADLESS
#                                   rate-limit signature ALSO fires the balance
#                                   DROP-HOOK mt_balance_mark_fail so the route
#                                   is dropped from the rotation. Absent => the
#                                   interactive-only behaviour, unchanged.)
#             --config PATH        (optional; else $MT_CONFIG; else built-in sigs)
#
#   START-MECHANISM CONTRACT (documented here; the actual auto-start wiring into
#   the cwd-hook / multitrack-up is a SEPARATE later step — DESIGN §3.2 step 4,
#   PWU-5). A launcher spawns ONE detached monitor per launched alias, e.g.:
#
#     tp="$CLAUDE_CONFIG_DIR/projects/<encoded-worktree-path>/<newest>.jsonl"
#     nohup multitrack_fallback_monitor.sh --daemon \
#           --alias "$alias" --track "$track" --transcript "$tp" \
#           > "qa-results/multitrack/monitor_${alias}_$(date +%s).log" 2>&1 &
#     disown
#
#   (`<encoded-worktree-path>` = the worker's absolute cwd with every '/'→'-',
#    the Claude Code transcript directory convention, DESIGN §4.2(C).)
#
# Inputs (env, all optional — safe defaults):
#   MT_CONFIG              config path for mt_config_fallback_signatures (else built-ins)
#   MT_ORCHESTRATOR        path/name of the orchestrator to invoke (else sibling, else PATH)
#   MT_MONITOR_STATE_DIR   idempotency state dir (default: XDG_RUNTIME_DIR/.../monitor)
#   MT_MONITOR_COOLDOWN    idempotency window seconds (default 300 = orchestrator MT_COOLDOWN)
#   MT_MONITOR_MAX_SECONDS bounded daemon lifetime, 0 = unbounded (default 0)
#   MT_MONITOR_READ_TIMEOUT daemon read poll seconds for deadline re-check (default 2)
#   MT_MONITOR_FROM_LINE   --once starting line number (default 1)
#   MT_MONITOR_LOG         extra append log target for orchestrator output (default: stdout)
#   MT_MONITOR_QUOTA_MARKERS      newline/pipe list overriding the quota markers
#   MT_MONITOR_TRANSIENT_MARKERS  newline/pipe list overriding the transient markers
#
# Outputs:
#   Human-readable "[fbmon] <iso-ts> <event> ..." lines on stdout (the launcher
#   redirects them to the per-alias log). On a quota match: invokes
#   `<orchestrator> fallback --track T --reason rate-limit` (best-effort).
#
# Side-effects:
#   NONE on the device-under-test. The transcript + session are NEVER written,
#   truncated, or opened for writing (READ-ONLY tail). The ONLY writes are one
#   tiny epoch-integer idempotency file under MT_MONITOR_STATE_DIR (the
#   monitor's OWN scratch dir, not the DUT). Clean exit + trap kills the tail.
#
# Dependencies:  bash, tail (coreutils, -F follow), date.  multitrack_config.sh
#   is sourced best-effort for mt_config_fallback_signatures (optional).
#
# Cross-references:
#   docs/research/universal_auto_multitrack_20260704/DESIGN.md §4.2(C) / §7
#   constitution/scripts/multitrack/multitrack_alias_orchestrator.sh (fallback CLI)
#   constitution/scripts/multitrack/multitrack_config.sh (mt_config_fallback_signatures)
#   §11.4.177 auto-fallback · §11.4.128 observer-effect · §11.4.101 safe-decision ·
#   §11.4.6 no-guessing · §11.4.28 decoupling (zero project literals)
# =============================================================================

set -u

# --- self location (for the sibling orchestrator + config source) -------------
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
MT_FBMON_SELF="${BASH_SOURCE[0]}"
MT_FBMON_DIR="$(cd "$(dirname "$MT_FBMON_SELF")" 2>/dev/null && pwd)"

# --- built-in captured-FACT structural signature (NOT a project literal) ------
# AND-set (mt_fbmon_line_has_all_signatures): a line matches only if it contains
# EVERY token below. Pinned 2026-07-12 to the REAL captured 429 token so the
# AUTO-launched (no --config) monitor fires on live limits — engine-default
# parity with config/multitrack/the-factory.yaml (pinned in 66b34d3b, §11.4.26).
# A headless probe of weekly-rejected accounts (claude1/claude4) showed Claude
# Code's real result line carries `"api_error_status":429` (snake_case); the old
# camelCase pair (`"apiErrorStatus":429` + `"isApiErrorMessage":true`) matched NO
# real line, so the engine default never fired. `":429` is the substring common
# to BOTH the interactive (`"apiErrorStatus":429`) and headless
# (`"api_error_status":429`) shapes (AND-listing both casings would match
# nothing). The quota-marker gate (resets / weekly limit / session limit) keeps a
# coincidental bare 429 a NO-OP; healthy accounts emit `"api_error_status":null`
# (no 429) so never match — verified no-false-positive (§11.4.6).
MT_FBMON_SIG_DEFAULT_1='":429'
MT_FBMON_SIG_DEFAULT_2='":429'

# --- built-in captured-FACT sub-classification markers (overridable) ----------
# quota-exhausted markers (session/usage limit that will NOT clear until reset)
MT_FBMON_QUOTA_DEFAULT=$'resets\nweekly limit\nsession limit'
# transient markers (Claude self-heals — acting would thrash)
MT_FBMON_TRANSIENT_DEFAULT=$'not your usage limit'

# --- RB-06 HEADLESS rate-limit signature (the stream-json worker path) --------
# A HEADLESS `claude -p --output-format stream-json` worker emits a stream-json
# result event when it hits a rate-limit; RB-06's DROP-HOOK (mt_balance_mark_fail)
# drops that worker's route so mt_balance_select re-picks among the live routes.
# CONFIRMED 2026-07-12 (§11.4.6, was UNCONFIRMED/mock): the headless probe of
# weekly-rejected accounts (claude1/claude4) showed the real headless limit line
# is the SAME `"api_error_status":429` result shape as interactive — NOT the
# earlier mock `system/api_retry` shape. Pinned to `":429` so the headless
# default mirrors the real captured token; still DATA, config-overridable via a
# one-line pin (MT_MONITOR_HEADLESS_SIGNATURES / MT_MONITOR_HEADLESS_QUOTA_MARKERS),
# never a code change (§11.4.111). NOTE: `":429` also matches the interactive
# AND-set, checked first, so a real `":429` line classifies "interactive" + fires
# the fallback rebind; the headless-kind drop-hook path is reached only when a
# config supplies a distinct interactive signature (honest §11.4.6).
MT_FBMON_HEADLESS_SIG_DEFAULT='":429'
MT_FBMON_HEADLESS_QUOTA_DEFAULT=$'rate_limit\nrate-limit'

# --- knobs (env-overridable, safe defaults) -----------------------------------
MT_MONITOR_COOLDOWN=${MT_MONITOR_COOLDOWN:-300}
MT_MONITOR_MAX_SECONDS=${MT_MONITOR_MAX_SECONDS:-0}
MT_MONITOR_READ_TIMEOUT=${MT_MONITOR_READ_TIMEOUT:-2}
MT_MONITOR_FROM_LINE=${MT_MONITOR_FROM_LINE:-1}
MT_MONITOR_STATE_DIR=${MT_MONITOR_STATE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/multitrack/monitor}

# --- runtime state ------------------------------------------------------------
MT_FBMON_ALIAS=""
MT_FBMON_TRACK=""
MT_FBMON_TRANSCRIPT=""
MT_FBMON_CONFIG="${MT_CONFIG:-}"
MT_FBMON_MODE=""
MT_FBMON_SIGNATURES=""
MT_FBMON_QUOTA_MARKERS=""
MT_FBMON_TRANSIENT_MARKERS=""
MT_FBMON_ROUTE=""                 # RB-06: the balance route this worker uses (drop-hook target)
MT_FBMON_HEADLESS_SIGNATURES=""   # RB-06: headless stream-json rate-limit structural sig
MT_FBMON_HEADLESS_QUOTA_MARKERS="" # RB-06: headless quota sub-markers
MT_FBMON_TAIL_PID=""
MT_FBMON_FIRED_IN_RUN=0   # in-process idempotency guard (belt; state file = suspenders)

# --- logging ------------------------------------------------------------------
mt_fbmon_log() {
    printf '[fbmon] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

# --- cleanup / trap (never perturb the session) -------------------------------
mt_fbmon_cleanup() {
    if [ -n "${MT_FBMON_TAIL_PID:-}" ]; then
        kill "$MT_FBMON_TAIL_PID" 2>/dev/null || true
        wait "$MT_FBMON_TAIL_PID" 2>/dev/null || true
    fi
}
trap 'mt_fbmon_cleanup' EXIT INT TERM

# --- usage --------------------------------------------------------------------
mt_fbmon_usage() {
    sed -n '2,72p' "$MT_FBMON_SELF" 2>/dev/null | sed 's/^# \{0,1\}//'
}

# --- signature + marker loading ----------------------------------------------
# STRUCTURAL signatures: config function when a config path is known, else the
# built-in captured-FACT defaults (README: "the monitor decides its own default").
mt_fbmon_load_signatures() {
    local out=""
    if [ -n "$MT_FBMON_CONFIG" ] && declare -F mt_config_fallback_signatures >/dev/null 2>&1; then
        out="$(mt_config_fallback_signatures "$MT_FBMON_CONFIG" 2>/dev/null || true)"
    fi
    if [ -n "$out" ]; then
        MT_FBMON_SIGNATURES="$out"
    else
        MT_FBMON_SIGNATURES="$MT_FBMON_SIG_DEFAULT_1"$'\n'"$MT_FBMON_SIG_DEFAULT_2"
    fi
}

# markers: env override (newline OR '|' separated) → optional config fn → default
mt_fbmon_norm_list() {
    # normalise a '|'-or-newline list to one-per-line, drop blanks
    printf '%s\n' "$1" | tr '|' '\n' | sed '/^[[:space:]]*$/d'
}
mt_fbmon_load_markers() {
    if [ -n "${MT_MONITOR_QUOTA_MARKERS:-}" ]; then
        MT_FBMON_QUOTA_MARKERS="$(mt_fbmon_norm_list "$MT_MONITOR_QUOTA_MARKERS")"
    elif declare -F mt_config_fallback_quota_markers >/dev/null 2>&1 && [ -n "$MT_FBMON_CONFIG" ]; then
        MT_FBMON_QUOTA_MARKERS="$(mt_config_fallback_quota_markers "$MT_FBMON_CONFIG" 2>/dev/null || true)"
    fi
    [ -n "$MT_FBMON_QUOTA_MARKERS" ] || MT_FBMON_QUOTA_MARKERS="$MT_FBMON_QUOTA_DEFAULT"

    if [ -n "${MT_MONITOR_TRANSIENT_MARKERS:-}" ]; then
        MT_FBMON_TRANSIENT_MARKERS="$(mt_fbmon_norm_list "$MT_MONITOR_TRANSIENT_MARKERS")"
    elif declare -F mt_config_fallback_transient_markers >/dev/null 2>&1 && [ -n "$MT_FBMON_CONFIG" ]; then
        MT_FBMON_TRANSIENT_MARKERS="$(mt_config_fallback_transient_markers "$MT_FBMON_CONFIG" 2>/dev/null || true)"
    fi
    [ -n "$MT_FBMON_TRANSIENT_MARKERS" ] || MT_FBMON_TRANSIENT_MARKERS="$MT_FBMON_TRANSIENT_DEFAULT"
}

# RB-06 headless signature + quota-marker loading (env override → default).
mt_fbmon_load_headless() {
    if [ -n "${MT_MONITOR_HEADLESS_SIGNATURES:-}" ]; then
        MT_FBMON_HEADLESS_SIGNATURES="$(mt_fbmon_norm_list "$MT_MONITOR_HEADLESS_SIGNATURES")"
    else
        MT_FBMON_HEADLESS_SIGNATURES="$MT_FBMON_HEADLESS_SIG_DEFAULT"
    fi
    if [ -n "${MT_MONITOR_HEADLESS_QUOTA_MARKERS:-}" ]; then
        MT_FBMON_HEADLESS_QUOTA_MARKERS="$(mt_fbmon_norm_list "$MT_MONITOR_HEADLESS_QUOTA_MARKERS")"
    else
        MT_FBMON_HEADLESS_QUOTA_MARKERS="$MT_FBMON_HEADLESS_QUOTA_DEFAULT"
    fi
}

# --- matching (literal substring, no regex — cheap per §11.4.128) -------------
# structural: line must contain EVERY configured signature (AND). Empty set ⇒ no
# match (never a vacuous true). Case-SENSITIVE (JSON tokens are fixed-case).
mt_fbmon_line_has_all_signatures() {
    local line=$1 sig count=0
    while IFS= read -r sig; do
        [ -n "$sig" ] || continue
        count=$((count + 1))
        case "$line" in
            *"$sig"*) : ;;
            *) return 1 ;;
        esac
    done <<EOF
$MT_FBMON_SIGNATURES
EOF
    [ "$count" -gt 0 ]
}

# RB-06: headless stream-json rate-limit structural signature (AND-set over the
# headless signatures). Empty set ⇒ no match (never a vacuous true).
mt_fbmon_line_has_all_headless_signatures() {
    local line=$1 sig count=0
    [ -n "$MT_FBMON_HEADLESS_SIGNATURES" ] || return 1
    while IFS= read -r sig; do
        [ -n "$sig" ] || continue
        count=$((count + 1))
        case "$line" in
            *"$sig"*) : ;;
            *) return 1 ;;
        esac
    done <<EOF
$MT_FBMON_HEADLESS_SIGNATURES
EOF
    [ "$count" -gt 0 ]
}

# markers: line contains ANY listed marker (OR). Case-INSENSITIVE (message text).
mt_fbmon_line_matches_any() {
    local line_lc marker_lc list=$2 m
    line_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r m; do
        [ -n "$m" ] || continue
        marker_lc="$(printf '%s' "$m" | tr '[:upper:]' '[:lower:]')"
        case "$line_lc" in
            *"$marker_lc"*) return 0 ;;
        esac
    done <<EOF
$list
EOF
    return 1
}

# --- orchestrator resolution: env override FIRST (so tests use their stub, --
# NEVER the real sibling), then co-located sibling, then PATH ------------------
mt_fbmon_resolve_orchestrator() {
    local sib
    if [ -n "${MT_ORCHESTRATOR:-}" ]; then
        if [ -x "$MT_ORCHESTRATOR" ]; then printf '%s\n' "$MT_ORCHESTRATOR"; return 0; fi
        if command -v "$MT_ORCHESTRATOR" >/dev/null 2>&1; then command -v "$MT_ORCHESTRATOR"; return 0; fi
        return 1
    fi
    sib="$MT_FBMON_DIR/multitrack_alias_orchestrator.sh"
    if [ -x "$sib" ]; then printf '%s\n' "$sib"; return 0; fi
    if command -v multitrack_alias_orchestrator.sh >/dev/null 2>&1; then
        command -v multitrack_alias_orchestrator.sh; return 0
    fi
    return 1
}

# --- idempotent, best-effort fallback fire ------------------------------------
mt_fbmon_fire_fallback() {
    local now statef last delta orch rc=0 safe
    now="$(date +%s)"

    # in-process guard (survives a state-dir write failure)
    if [ "$MT_FBMON_FIRED_IN_RUN" -eq 1 ]; then
        mt_fbmon_log "IDEMPOTENT-SKIP fallback (already fired this run; ${MT_MONITOR_COOLDOWN}s window)"
        return 0
    fi

    safe="$(printf '%s_%s' "$MT_FBMON_ALIAS" "$MT_FBMON_TRACK" | tr -c 'A-Za-z0-9._-' '_')"
    statef="$MT_MONITOR_STATE_DIR/last_fallback_$safe"
    if [ -f "$statef" ]; then
        last=""
        IFS= read -r last < "$statef" 2>/dev/null || true
        case "$last" in ''|*[!0-9]*) last=0 ;; esac
        delta=$((now - last))
        if [ "$delta" -lt "$MT_MONITOR_COOLDOWN" ]; then
            mt_fbmon_log "IDEMPOTENT-SKIP fallback (last fired ${delta}s ago < ${MT_MONITOR_COOLDOWN}s window)"
            MT_FBMON_FIRED_IN_RUN=1
            return 0
        fi
    fi

    # record BEFORE the call so a same-window burst is suppressed even mid-call
    mkdir -p "$MT_MONITOR_STATE_DIR" 2>/dev/null || true
    printf '%s\n' "$now" > "$statef" 2>/dev/null || true
    MT_FBMON_FIRED_IN_RUN=1

    orch="$(mt_fbmon_resolve_orchestrator)" || {
        mt_fbmon_log "ORCH-NOT-FOUND — cannot fire fallback for track=$MT_FBMON_TRACK (set MT_ORCHESTRATOR)"
        return 0
    }
    mt_fbmon_log "FIRING fallback --track $MT_FBMON_TRACK --reason rate-limit (orchestrator=$orch)"
    "$orch" fallback --track "$MT_FBMON_TRACK" --reason rate-limit \
        >>"${MT_MONITOR_LOG:-/dev/stdout}" 2>&1 || rc=$?
    mt_fbmon_log "orchestrator fallback exit=$rc"
    return 0   # best-effort — a non-zero orchestrator (e.g. exit 5 all-cooled) never kills the monitor
}

# --- RB-06 balance DROP-HOOK: drop this worker's route from the rotation ------
# Best-effort, idempotency-guarded by the balance registry itself (mark_fail is
# a monotonic counter). ONLY fires when a --route was supplied (a headless
# worker). Sources multitrack_balance.sh (sibling) and calls mt_balance_mark_fail
# so mt_balance_select re-picks among the remaining live routes (reuse/rebalance).
mt_fbmon_fire_drop_hook() {
    [ -n "$MT_FBMON_ROUTE" ] || { mt_fbmon_log "DROP-HOOK skipped (no --route given)"; return 0; }
    local bal="$MT_FBMON_DIR/multitrack_balance.sh"
    if [ ! -f "$bal" ]; then
        mt_fbmon_log "DROP-HOOK: balance lib missing ($bal) — route not dropped (honest, §11.4.6)"
        return 0
    fi
    (
        MT_BALANCE_SELF="$bal"
        # shellcheck source=/dev/null
        . "$bal" 2>/dev/null || exit 0
        mt_balance_mark_fail "$MT_FBMON_ROUTE" rate-limit >/dev/null 2>&1 || true
    )
    mt_fbmon_log "DROP-HOOK fired: mt_balance_mark_fail route=$MT_FBMON_ROUTE reason=rate-limit"
    return 0
}

# --- per-line classification + action -----------------------------------------
mt_fbmon_process_line() {
    local line=$1 kind=""
    # match EITHER the interactive 429 transcript signature (existing) OR the
    # RB-06 headless stream-json rate-limit signature. Interactive path behaviour
    # is unchanged; headless is purely additive.
    if mt_fbmon_line_has_all_signatures "$line"; then
        kind="interactive"
    elif mt_fbmon_line_has_all_headless_signatures "$line"; then
        kind="headless"
    else
        return 0   # no limit signature → ignore
    fi

    # transient takes precedence over quota — the guard against false fallback:
    # a "not your usage limit" throttle self-heals, so NEVER act on it.
    if mt_fbmon_line_matches_any "$line" "$MT_FBMON_TRANSIENT_MARKERS"; then
        mt_fbmon_log "MATCH transient-throttle ($kind alias=$MT_FBMON_ALIAS track=$MT_FBMON_TRACK) — NO-OP (self-heals)"
        return 0
    fi

    # quota classification: interactive uses its markers; headless ALSO honors
    # the headless quota markers (rate_limit / rate-limit).
    local is_quota=0
    if mt_fbmon_line_matches_any "$line" "$MT_FBMON_QUOTA_MARKERS"; then is_quota=1; fi
    if [ "$kind" = "headless" ] && mt_fbmon_line_matches_any "$line" "$MT_FBMON_HEADLESS_QUOTA_MARKERS"; then is_quota=1; fi

    if [ "$is_quota" = "1" ]; then
        mt_fbmon_log "MATCH quota-exhausted ($kind alias=$MT_FBMON_ALIAS track=$MT_FBMON_TRACK route=${MT_FBMON_ROUTE:-<none>})"
        mt_fbmon_fire_fallback                            # existing: rebind track to next alias
        [ "$kind" = "headless" ] && mt_fbmon_fire_drop_hook  # RB-06: drop route from balance rotation
        return 0
    fi
    mt_fbmon_log "MATCH ${kind}-limit-unclassified (alias=$MT_FBMON_ALIAS track=$MT_FBMON_TRACK) — NO-OP (no quota marker; safe default)"
    return 0
}

# --- --once: process current transcript contents once, READ-ONLY --------------
mt_fbmon_run_once() {
    local line n=0 from=$MT_MONITOR_FROM_LINE
    if [ ! -r "$MT_FBMON_TRANSCRIPT" ]; then
        mt_fbmon_log "transcript not readable (nothing to scan): $MT_FBMON_TRANSCRIPT"
        return 0
    fi
    while IFS= read -r line; do
        n=$((n + 1))
        [ "$n" -lt "$from" ] && continue
        mt_fbmon_process_line "$line"
    done < "$MT_FBMON_TRANSCRIPT"
    mt_fbmon_log "once-scan complete (lines=$n from=$from)"
    return 0
}

# --- --daemon: follow new lines only, READ-ONLY, bounded, killable ------------
mt_fbmon_run_daemon() {
    local deadline=0 now line rc
    if [ "$MT_MONITOR_MAX_SECONDS" -gt 0 ] 2>/dev/null; then
        deadline=$(( $(date +%s) + MT_MONITOR_MAX_SECONDS ))
    fi
    mt_fbmon_log "daemon start (alias=$MT_FBMON_ALIAS track=$MT_FBMON_TRACK transcript=$MT_FBMON_TRANSCRIPT max_seconds=$MT_MONITOR_MAX_SECONDS)"

    # `tail -n0 -F` = NEW lines only + follow across truncate/rotate; READ-ONLY.
    # coproc gives a reliable child PID for clean kill on trap (§11.4.128).
    coproc MT_FBMON_TAILCO { tail -n0 -F -- "$MT_FBMON_TRANSCRIPT" 2>/dev/null; }
    MT_FBMON_TAIL_PID=$MT_FBMON_TAILCO_PID

    while : ; do
        if [ "$deadline" -gt 0 ]; then
            now="$(date +%s)"
            [ "$now" -ge "$deadline" ] && { mt_fbmon_log "max-seconds reached — exiting"; break; }
        fi
        if IFS= read -r -t "$MT_MONITOR_READ_TIMEOUT" -u "${MT_FBMON_TAILCO[0]}" line; then
            mt_fbmon_process_line "$line"
        else
            rc=$?
            [ "$rc" -gt 128 ] && continue   # read timeout → re-check deadline
            mt_fbmon_log "transcript stream ended (rc=$rc) — exiting"
            break
        fi
    done
    return 0
}

# --- arg parse ----------------------------------------------------------------
mt_fbmon_parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --daemon)      MT_FBMON_MODE="daemon" ;;
            --once)        MT_FBMON_MODE="once" ;;
            --alias)       MT_FBMON_ALIAS="${2:-}"; shift ;;
            --alias=*)     MT_FBMON_ALIAS="${1#--alias=}" ;;
            --track)       MT_FBMON_TRACK="${2:-}"; shift ;;
            --track=*)     MT_FBMON_TRACK="${1#--track=}" ;;
            --transcript)  MT_FBMON_TRANSCRIPT="${2:-}"; shift ;;
            --transcript=*) MT_FBMON_TRANSCRIPT="${1#--transcript=}" ;;
            --route)       MT_FBMON_ROUTE="${2:-}"; shift ;;
            --route=*)     MT_FBMON_ROUTE="${1#--route=}" ;;
            --config)      MT_FBMON_CONFIG="${2:-}"; shift ;;
            --config=*)    MT_FBMON_CONFIG="${1#--config=}" ;;
            -h|--help)     mt_fbmon_usage; exit 0 ;;
            *)             mt_fbmon_log "unknown argument: $1"; mt_fbmon_usage; exit 2 ;;
        esac
        shift
    done
}

# --- main ---------------------------------------------------------------------
mt_fbmon_main() {
    mt_fbmon_parse_args "$@"

    if [ -z "$MT_FBMON_MODE" ]; then
        mt_fbmon_log "no mode given (need --daemon or --once)"; mt_fbmon_usage; exit 2
    fi
    if [ -z "$MT_FBMON_ALIAS" ] || [ -z "$MT_FBMON_TRACK" ] || [ -z "$MT_FBMON_TRANSCRIPT" ]; then
        mt_fbmon_log "missing required arg (--alias, --track, --transcript all required)"; exit 2
    fi

    # best-effort source of the config library for mt_config_fallback_signatures
    if [ -n "$MT_FBMON_CONFIG" ] && [ -r "$MT_FBMON_DIR/multitrack_config.sh" ]; then
        # shellcheck source=/dev/null
        . "$MT_FBMON_DIR/multitrack_config.sh" 2>/dev/null || true
    fi

    mt_fbmon_load_signatures
    mt_fbmon_load_markers
    mt_fbmon_load_headless

    case "$MT_FBMON_MODE" in
        once)   mt_fbmon_run_once ;;
        daemon) mt_fbmon_run_daemon ;;
    esac
}

mt_fbmon_main "$@"
