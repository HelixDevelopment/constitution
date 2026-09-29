#!/usr/bin/env bash
# =============================================================================
# multitrack_alias_orchestrator.sh — Claude Toolkit multi-alias <-> Track
#   orchestration layer (REM-18 / draft §11.4.179).
#   §11.4.167 (feature work-stream lifecycle / worktrees) /
#   §11.4.119 (single-resource-owner) / §11.4.116 (real-time sync substrate) /
#   §11.4.147 (crash respawn / no-work-loss registry) / §11.4.10 (NAMES not keys,
#   no secrets) / §11.4.6 (no guessing).
# -----------------------------------------------------------------------------
# Purpose:
#   Coordinate the host's Claude Toolkit ALIASES (each a distinct running Claude
#   Code instance on a DIFFERENT Claude Max subscription, plus provider aliases)
#   against the project's TRACKS (per-§11.4.167 feature work-streams, each in its
#   own git worktree) AND the shared SCARCE test-device pool (D1/D2 + future
#   nano_kvm) — so that:
#     (a) every Track runs under exactly ONE claude alias (track single-owner,
#         §11.4.119 — prevents cross-contamination). An alias MAY drive MULTIPLE
#         Tracks (operator mandate 2026-07: "fallback to the next claude native
#         alias if the one on a track hits a limit; the same alias may be used on
#         more than one track") — so a Track can fall back onto an alias already
#         serving another Track when unbound aliases are scarce;
#     (b) each Track's worktree (§11.4.167 sibling-dir / btrfs-CoW clone) is
#         registered so any alias can resume it (§11.4.147 no-work-loss);
#     (c) the 2-device pool is handed off SAFELY across N Tracks via the ALREADY
#         BUILT + verified `multitrack_device_lock.sh` arbiter — this layer NEVER
#         reimplements device leasing, it delegates to it (§11.4.74 extend-not-
#         reimplement);
#     (d) on a limit / error / rate-limit, a Track FALLS BACK to the next
#         available alias — preferring a fresh (unbound) one, else REUSING a
#         healthy (not-cooled) alias already bound to another Track (least-loaded
#         first) — WITHOUT losing its device leases (the leases are keyed by the
#         STABLE Track id in the arbiter — the alias changes, not the Track, so
#         the hand-off is race-free). Only when EVERY alias is cooled does it
#         park (exit 5). A cooled (rate-limited) alias is NEVER selected.
#
# Deadlock-freedom (the load-bearing anti-bluff claim — proven by the paired
#   stress/chaos test test_multitrack_alias_orchestrator.sh). The alias<->track
#   binding breaks all four Coffman conditions BY CONSTRUCTION, exactly like the
#   device arbiter it composes with:
#     1. mutual-exclusion : RELAXED on the alias side — a Track still has exactly
#                           ONE alias (track single-owner, §11.4.119) but an alias
#                           MAY hold MULTIPLE Tracks (operator mandate). Still
#                           bounded to a microsecond flock critical section, and
#                           the Track remains the UNIQUE row key so no Track can
#                           ever gain a second owner (no track-double-owner).
#     2. hold-and-wait    : ELIMINATED — bind claims the (alias,track) pair
#                           ATOMICALLY inside one critical section; it never holds
#                           a half-binding while waiting for the rest.
#     3. no-preemption    : RELAXED via lease TTL + heartbeat + reap — a crashed
#                           alias's binding auto-expires (§11.4.147) so a dead
#                           alias can NEVER hold a Track hostage forever.
#     4. circular-wait    : ELIMINATED — bind is NON-BLOCKING: it wins the pair
#                           immediately or returns EBUSY at once; it NEVER waits
#                           on a Track/alias held by another binder, so no wait-for
#                           cycle can form. Callers retry at a higher level holding
#                           nothing. Device hand-off delegates to the arbiter whose
#                           own deadlock-freedom is already proven.
#   The only lock ever HELD is a short bounded `flock -w` on the registry file,
#   released before any device work.
#
# Registry (§11.4.116 real-time sync substrate — same shape as the arbiter):
#   MT_ALIAS_DIR (default ${XDG_RUNTIME_DIR:-/tmp}/<project>/multitrack/aliasorch)
#     bindings.snapshot   alias|track|worktree|pid|acq|exp|state  (ATOMIC rewrite)
#     cooldowns.snapshot  alias|until|reason  (rate-limited aliases; ATOMIC rewrite)
#     events.jsonl        append-only BIND/UNBIND/HANDOFF/FALLBACK/HEARTBEAT/REAP/
#                         COOLDOWN/DENY — never rewritten (§11.4.116).
#     registry.lock       flock target for the atomic critical section.
#   Ephemeral runtime state (tmpfs, cleared on reboot) — correct: a binding has no
#   meaning across a host reboot / after every alias process exits.
#
# Alias roster (§11.4.10 — NAMES ONLY, never keys/tokens; keys live in the host's
#   ~/api_keys.sh OUTSIDE the repo). Resolution order (first non-empty wins):
#     1. env  MT_ALIAS_ROSTER  = "name:kind,name:kind,..." (used by the tests)
#     2. an  `aliases:`  YAML block in the per-host config (git-versioned NAMES)
#     3. the built-in default roster (3 native Claude Max + 3 provider aliases).
#
# Usage:
#   multitrack_alias_orchestrator.sh aliases
#   multitrack_alias_orchestrator.sh tracks
#   multitrack_alias_orchestrator.sh status
#   multitrack_alias_orchestrator.sh bind    --alias A --track T [--worktree P] [--ttl S]
#   multitrack_alias_orchestrator.sh unbind  (--alias A | --track T)
#   multitrack_alias_orchestrator.sh heartbeat --alias A [--ttl S]
#   multitrack_alias_orchestrator.sh fallback --track T [--reason R] [--class session|weekly|subscription] [--until EPOCH] [--ttl S]
#   multitrack_alias_orchestrator.sh mark-limited --alias A [--class session|weekly|subscription] [--until EPOCH] [--reason R]
#   multitrack_alias_orchestrator.sh mark-operational --alias A
#   multitrack_alias_orchestrator.sh promote [--ttl S]
#   multitrack_alias_orchestrator.sh auto-assign [--ttl S]
#   multitrack_alias_orchestrator.sh acquire-devices --track T [ARBITER acquire ARGS...]
#   multitrack_alias_orchestrator.sh release-devices --track T [--device D]
#   multitrack_alias_orchestrator.sh handoff --from-track T1 --to-track T2 (--devices d,d | --caps c [--count N])
#   multitrack_alias_orchestrator.sh reap
#   multitrack_alias_orchestrator.sh reconcile
#
# Exit codes: 0 = ok · 2 = usage · 3 = EBUSY (track already driven by ANOTHER
#             alias — track single-owner; an alias holding >1 track is ALLOWED) ·
#             4 = unknown alias/track OR alias in cooldown · 5 = no available
#             (non-cooled) alias for fallback — every alias is cooled (bounded
#             operator-block per §11.4.101) ·
#             1 = internal error. Device sub-commands propagate the arbiter's
#             own exit codes (3 EBUSY / 4 ENODEV/ENOCAP).
#
# Inputs:  MT_CONFIG or config/multitrack/<host>.yaml (tracks + device_pool).
#          Env: MT_ALIAS_DIR, MT_LOCK_WAIT (flock wait, default 10s),
#          MT_ALIAS_TTL (default 900s), MT_COOLDOWN (default 300s),
#          MT_ALIAS_ROSTER, MT_SCRIPTS_DIR (dir holding multitrack_config.sh +
#          multitrack_device_lock.sh — defaults to this script's dir, falls back
#          to <repo>/scripts/multitrack), MT_HOLDER_PID, MT_CONFIG/MT_HOST.
# Outputs: human-readable lines on stdout; JSONL + snapshots in MT_ALIAS_DIR.
# Side-effects: writes ONLY under MT_ALIAS_DIR; delegates device leasing to the
#          arbiter (which writes only under MT_LOCK_DIR). NEVER a device, NEVER a
#          disk, NEVER credentials (§11.4.10).
# Dependencies: bash, awk, flock, date, mkdir, mv; multitrack_config.sh +
#          multitrack_device_lock.sh (REUSED, not reimplemented).
# Cross-references: scripts/multitrack/multitrack_device_lock.sh (device arbiter);
#          scripts/multitrack/multitrack_config.sh (tracks + device_pool loader);
#          qa-results/p3_rem18/test_multitrack_alias_orchestrator.sh (stress/chaos
#          + paired mutation, captured evidence); config/multitrack/<host>.yaml.
# =============================================================================

set -u

ORCH_SELF=$0
case "$ORCH_SELF" in
    */*) ORCH_DIR=${ORCH_SELF%/*} ;;
    *)   ORCH_DIR=. ;;
esac

# Locate the reused multitrack scripts (works both in-place after move-in AND
# from the qa-results prototype location where MT_SCRIPTS_DIR points at the real
# scripts/multitrack). §11.4.6 — resolve explicitly, never guess.
MT_SCRIPTS_DIR=${MT_SCRIPTS_DIR:-$ORCH_DIR}
if [ ! -r "$MT_SCRIPTS_DIR/multitrack_config.sh" ]; then
    for cand in \
        "$ORCH_DIR/../../scripts/multitrack" \
        "$ORCH_DIR/../scripts/multitrack" \
        "$ORCH_DIR"; do
        if [ -r "$cand/multitrack_config.sh" ]; then MT_SCRIPTS_DIR=$cand; break; fi
    done
fi
[ -r "$MT_SCRIPTS_DIR/multitrack_config.sh" ] || {
    echo "FATAL: cannot locate multitrack_config.sh (set MT_SCRIPTS_DIR)" >&2; exit 1; }
ARB="$MT_SCRIPTS_DIR/multitrack_device_lock.sh"
[ -x "$ARB" ] || [ -r "$ARB" ] || {
    echo "FATAL: cannot locate multitrack_device_lock.sh at $ARB (set MT_SCRIPTS_DIR)" >&2; exit 1; }

# shellcheck source=scripts/multitrack/multitrack_config.sh
. "$MT_SCRIPTS_DIR/multitrack_config.sh"

MT_ALIAS_DIR=${MT_ALIAS_DIR:-${XDG_RUNTIME_DIR:-/tmp}/$(basename "$(mt_repo_root)")/multitrack/aliasorch}
MT_LOCK_WAIT=${MT_LOCK_WAIT:-10}
MT_ALIAS_TTL=${MT_ALIAS_TTL:-900}
MT_COOLDOWN=${MT_COOLDOWN:-300}
# Per-reason-CLASS cooldown durations (operator mandate 2026-07-14: a session
# 429, a weekly-limit-reached, and a subscription-expiry are DIFFERENT "not
# operational until…" windows, NOT one flat cooldown — §11.4.111 resolve-by-real-
# state, §11.4.6 no-guessing). The `until` epoch stored per cooled alias IS its
# operational-again timestamp. All overridable; a caller MAY pass an exact
# `--until` (e.g. parsed from a real reset marker) which wins over the class default.
MT_COOLDOWN_SESSION=${MT_COOLDOWN_SESSION:-$MT_COOLDOWN}          # 429 session rate-limit: short (self-heals at reset)
MT_COOLDOWN_WEEKLY=${MT_COOLDOWN_WEEKLY:-604800}                  # weekly-limit-reached: ~7d until the weekly reset
# subscription expiry: operational-again is UNKNOWN until a real renewal signal —
# park with a far-future sentinel (2100-01-01Z) so a subscription-expired alias is
# never auto-picked until an explicit `mark-operational`/renewal clears it (§11.4.6:
# never GUESS a renewal date; an operator/config supplies the real one via --until).
MT_COOLDOWN_SUBSCRIPTION_SENTINEL=${MT_COOLDOWN_SUBSCRIPTION_SENTINEL:-4102444800}
BIND="$MT_ALIAS_DIR/bindings.snapshot"
COOL="$MT_ALIAS_DIR/cooldowns.snapshot"
EVENTS="$MT_ALIAS_DIR/events.jsonl"
LOCKF="$MT_ALIAS_DIR/registry.lock"

# Built-in fallback roster (used ONLY when neither MT_ALIAS_ROSTER nor a config
# `aliases:` block is present). Natives FIRST, then providers in the operator-
# mandated priority order (deepseek -> xiaomi -> opencode -> kimi-for-coding).
# The class:kind tag on every token is load-bearing: _next_available_alias
# partitions by kind (native before provider), so this order is a sane default
# but the native-first GUARANTEE does not depend on it (§11.4.111).
DEFAULT_ROSTER="claude1:native claude2:native claude3:native claude4:native deepseek:provider xiaomi:provider opencode:provider kimi-for-coding:provider"

_now() { date +%s; }
_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_jsan() { printf '%s' "${1:-}" | tr '"' "'" ; }

_ensure_dirs() {
    mkdir -p "$MT_ALIAS_DIR" 2>/dev/null || { echo "FATAL: cannot create $MT_ALIAS_DIR" >&2; exit 1; }
    [ -e "$BIND" ]   || : > "$BIND"
    [ -e "$COOL" ]   || : > "$COOL"
    [ -e "$EVENTS" ] || : > "$EVENTS"
    [ -e "$LOCKF" ]  || : > "$LOCKF"
}

# _event EVENT ALIAS TRACK WORKTREE EXPIRES NOTE  -> one JSONL line (§11.4.116).
_event() {
    printf '{"ts":%s,"iso":"%s","event":"%s","alias":"%s","track":"%s","worktree":"%s","expires":"%s","pid":%s,"note":"%s"}\n' \
        "$(_now)" "$(_iso)" "$(_jsan "$1")" "$(_jsan "$2")" "$(_jsan "$3")" \
        "$(_jsan "$4")" "$(_jsan "$5")" "${HOLDER_PID:-0}" "$(_jsan "$6")" >> "$EVENTS"
}

# --- config: tracks + alias roster -------------------------------------------
# §11.4.187: a per-host config loads exactly as before; a host with NO config
# falls back to the universal DEFAULT single-track mode (ONE track = the
# invocation project root) instead of fataling — otherwise the orchestrator
# stays the one component that makes multi-track non-universal. A config that
# EXISTS but is malformed is STILL fatal (never defaulted past, §11.4.6).
# ORCH_CFG is the empty string in default mode; the file-reading accessors
# (conductor / excluded-aliases / alias roster) correctly yield nothing, which
# is the honest answer when no alias policy has been declared for this host.
_load_tracks() {
    local host rc
    host=${MT_HOST:-$(mt_resolve_host)}
    mt_resolve_and_load
    rc=$?
    if [ "$rc" -eq 3 ]; then
        echo "FATAL: the per-host config for host=$host exists but is unusable (unparsable, or zero tracks)" >&2
        exit 1
    fi
    if [ "$rc" -ne 0 ]; then
        echo "FATAL: no per-host config for host=$host and no default single-track fallback could be established" >&2
        exit 1
    fi
    ORCH_CFG=${MT_CFG_FILE:-}
}

_track_exists() {  # $1 track-id
    local i=1 id
    while [ "$i" -le "${MT_TRACK_COUNT:-0}" ]; do
        eval "id=\${MT_TRACK_${i}_ID:-}"
        [ "$id" = "$1" ] && return 0
        i=$((i + 1))
    done
    return 1
}
_track_mount() {  # $1 track-id -> worktree/mount (§11.4.167)
    local i=1 id
    while [ "$i" -le "${MT_TRACK_COUNT:-0}" ]; do
        eval "id=\${MT_TRACK_${i}_ID:-}"
        if [ "$id" = "$1" ]; then eval "printf '%s' \"\${MT_TRACK_${i}_MOUNT:-}\""; return 0; fi
        i=$((i + 1))
    done
    return 1
}
_all_tracks() {
    local i=1 id
    while [ "$i" -le "${MT_TRACK_COUNT:-0}" ]; do
        eval "id=\${MT_TRACK_${i}_ID:-}"; [ -n "$id" ] && printf '%s\n' "$id"
        i=$((i + 1))
    done
}

# Parse an optional `aliases:` YAML block (name/kind pairs) from the config.
# Emits "name:kind" lines. NAMES ONLY (§11.4.10). Tolerant of absence.
_roster_from_config() {
    [ -n "${ORCH_CFG:-}" ] && [ -r "$ORCH_CFG" ] || return 1
    awk '
        /^[a-zA-Z0-9_]+:/ { inblk = ($1=="aliases:") ? 1 : 0 }
        inblk==1 {
            if ($1=="-" || $1=="name:") {
                for(i=1;i<=NF;i++){ if($i=="name:"){ n=$(i+1) } if($i=="kind:"){ k=$(i+1) } }
            }
            if (match($0, /name:[ \t]*/)) { s=substr($0,RSTART+RLENGTH); gsub(/[",]/,"",s); split(s,a," "); n=a[1] }
            if (match($0, /kind:[ \t]*/)) { s=substr($0,RSTART+RLENGTH); gsub(/[",]/,"",s); split(s,a," "); k=a[1] }
            if (n!="" && $0 ~ /kind:/) { print n ":" (k==""?"provider":k); n=""; k="" }
        }
    ' "$ORCH_CFG" 2>/dev/null
}

# Resolve the alias roster -> ROSTER (space-separated "name:kind"). §11.4.10.
_load_roster() {
    ROSTER=""
    if [ -n "${MT_ALIAS_ROSTER:-}" ]; then
        ROSTER=$(printf '%s' "$MT_ALIAS_ROSTER" | tr ',' ' ')
    else
        local fromcfg; fromcfg=$(_roster_from_config)
        if [ -n "$fromcfg" ]; then ROSTER=$(printf '%s' "$fromcfg" | tr '\n' ' ')
        else ROSTER=$DEFAULT_ROSTER; fi
    fi
    # normalise: ensure every token has a :kind (default provider)
    local out="" tok
    for tok in $ROSTER; do
        case "$tok" in *:*) out="$out $tok" ;; *) out="$out $tok:provider" ;; esac
    done
    ROSTER=$(printf '%s' "$out" | sed 's/^ *//')
}
_alias_kind() {  # $1 alias-name -> kind (empty if unknown)
    local tok
    for tok in $ROSTER; do
        case "$tok" in "$1:"*) printf '%s' "${tok#*:}"; return 0 ;; esac
    done
    return 1
}
_alias_known() { _alias_kind "$1" >/dev/null 2>&1; }
_all_aliases() { local tok; for tok in $ROSTER; do printf '%s\n' "${tok%%:*}"; done; }
# alias names of a given class ("native" | "provider"), in roster order.
# §11.4.111 resolve-by-CLASS-not-by-file-position: the native-first guarantee in
# _next_available_alias iterates the "native" class COMPLETELY before "provider",
# so a provider can NEVER be selected while any non-cooled native exists —
# regardless of the order aliases happen to appear in the roster file /
# MT_ALIAS_ROSTER (operator mandate 2026-07-08: native FIRST, providers ONLY when
# NO native works). A token is `name:kind`; the `*:native` / `*:provider` suffix
# match is safe because kinds are the fixed literals native|provider.
_aliases_of_class() {  # $1 = native|provider
    local tok
    for tok in $ROSTER; do
        case "$tok" in *:"$1") printf '%s\n' "${tok%%:*}" ;; esac
    done
}

# --- snapshot helpers (callers hold the flock; writes atomic) -----------------
_reap() {  # drop expired bindings + expired cooldowns; emit REAP. (inside lock)
    # `class` MUST be local: the cooldown read loop below uses it, and if it
    # leaked it would clobber a caller's own `class` var (cmd_mark_limited /
    # cmd_fallback) on the final EOF read — recording every limit as `session`.
    local now tmp a t wt pid acq exp state until reason class
    now=$(_now)
    if [ -s "$BIND" ]; then
        tmp="$BIND.tmp.$$"; : > "$tmp"
        while IFS='|' read -r a t wt pid acq exp state; do
            [ -n "$a" ] || continue
            if [ "${exp:-0}" -le "$now" ]; then
                _event REAP "$a" "$t" "$wt" "$exp" "binding-expired-ttl-elapsed"
            else
                printf '%s|%s|%s|%s|%s|%s|%s\n' "$a" "$t" "$wt" "$pid" "$acq" "$exp" "$state" >> "$tmp"
            fi
        done < "$BIND"
        mv -f "$tmp" "$BIND"
    fi
    if [ -s "$COOL" ]; then
        tmp="$COOL.tmp.$$"; : > "$tmp"
        # 4-field cooldown rows: alias|until|reason|class. Legacy 3-field rows
        # (class empty) are normalised to `session` on rewrite — backward-compat.
        while IFS='|' read -r a until reason class; do
            [ -n "$a" ] || continue
            [ "${until:-0}" -gt "$now" ] && printf '%s|%s|%s|%s\n' "$a" "$until" "$reason" "${class:-session}" >> "$tmp"
        done < "$COOL"
        mv -f "$tmp" "$COOL"
    fi
}

_alias_bound_track() { awk -F'|' -v a="$1" '$1==a{print $2; exit}' "$BIND" 2>/dev/null; }
# all tracks an alias currently holds (an alias MAY hold several), comma-joined.
_alias_bound_tracks() { awk -F'|' -v a="$1" '$1==a{printf "%s%s",sep,$2; sep=","} END{print ""}' "$BIND" 2>/dev/null; }
# how many tracks an alias currently holds (its "load"). 0 = unbound (§11.4.119).
_alias_load() { awk -F'|' -v a="$1" 'BEGIN{c=0} $1==a{c++} END{print c}' "$BIND" 2>/dev/null; }
_track_bound_alias() { awk -F'|' -v t="$1" '$2==t{print $1; exit}' "$BIND" 2>/dev/null; }
_alias_in_cooldown() { awk -F'|' -v a="$1" 'BEGIN{r=1} $1==a{r=0} END{exit r}' "$COOL" 2>/dev/null; }
# the alias's cooldown reason-CLASS + operational-again epoch (empty if not cooled).
_alias_cooldown_class() { awk -F'|' -v a="$1" '$1==a{print ($4==""?"session":$4); exit}' "$COOL" 2>/dev/null; }
_alias_cooldown_until() { awk -F'|' -v a="$1" '$1==a{print $2; exit}' "$COOL" 2>/dev/null; }

# operational-again epoch for a limit reason-CLASS (item 2 — session/weekly/
# subscription have DIFFERENT windows; §11.4.6 never guesses a renewal date).
_cooldown_until_for_class() {  # $1 = session|weekly|subscription -> epoch
    _now2=$(_now)
    case "$1" in
        weekly)       printf '%s' "$((_now2 + MT_COOLDOWN_WEEKLY))" ;;
        subscription) printf '%s' "$MT_COOLDOWN_SUBSCRIPTION_SENTINEL" ;;
        session|*)    printf '%s' "$((_now2 + MT_COOLDOWN_SESSION))" ;;
    esac
    unset _now2
}

# alias PRIORITY rank (lower = higher priority): native class outranks provider
# class UNCONDITIONALLY, then roster order within the class (the operator-mandated
# order the config authoritatively defines: deepseek->xiaomi->opencode->kimi...).
# This is the SAME native-first ordering _next_available_alias enforces, exposed
# as a comparable integer so cmd_promote can rebind a track UPWARD on recovery.
_alias_rank() {  # $1 alias -> integer (empty + rc1 if unknown)
    _k=$(_alias_kind "$1") || return 1
    # >>MT_ALIAS_MUT_RANK_NATIVE_FIRST (paired §1.1 mutation target — native base 0
    #   < provider base 100000 IS the native-first-in-promote guarantee. The test
    #   seds a throwaway copy swapping the two bases so a provider outranks a native
    #   and cmd_promote stops preferring a recovered native; do NOT remove marker.)
    case "$_k" in native) _base=0 ;; *) _base=100000 ;; esac
    # <<MT_ALIAS_MUT_RANK_NATIVE_FIRST
    _idx=0
    for _t in $(_aliases_of_class "$_k"); do
        if [ "$_t" = "$1" ]; then printf '%s' "$((_base + _idx))"; unset _k _base _idx _t; return 0; fi
        _idx=$((_idx + 1))
    done
    unset _k _base _idx _t
    return 1
}
# best (highest-priority = lowest-rank) alias NOT in cooldown (empty if all cooled).
_best_operational_alias() {
    _best=""; _bestrank=""
    for _a in $(_all_aliases); do
        _alias_in_cooldown "$_a" && continue
        _r=$(_alias_rank "$_a") || continue
        if [ -z "$_best" ] || [ "$_r" -lt "$_bestrank" ]; then _best=$_a; _bestrank=$_r; fi
    done
    printf '%s' "$_best"; unset _best _bestrank _a _r
}

# next available alias for fallback / auto-assign (operator mandate — an alias
# MAY serve multiple Tracks). PROVABLY NATIVE-FIRST (operator mandate 2026-07-08:
# native Claude aliases FIRST, providers ONLY when NO native works). The "native"
# class is scanned COMPLETELY (both tiers below) before the "provider" class is
# considered at all, so ANY non-cooled native — fresh OR reused — always outranks
# EVERY provider. Within each class, selection order (never $1, the excluded /
# limited alias; never a cooled alias):
#   (a) a known alias of this class NOT in cooldown AND NOT currently bound
#       (fresh) — preferred;
#   (b) else a known alias of this class NOT in cooldown even if ALREADY bound to
#       another Track (REUSE), least-loaded first (fewest current Track bindings)
#       — the "same alias may be used on more than one track" behaviour;
#   (c) only after BOTH classes yield nothing → caller exits 5 (every alias is
#       cooled / only the excluded one is healthy). A cooled (rate-limited) alias
#       is NEVER selected — that IS the "fallback on limit" behaviour. Track
#       single-owner (§11.4.119) is kept by the caller's atomic same-track
#       rewrite, so reuse never double-owns a Track. Deterministic (§11.4.50):
#       first-in-class-order ties.
_next_available_alias() {  # $1 exclude-alias (may be empty)
    local class a best bestload load
    # >>MT_ALIAS_MUT_NATIVE_FIRST (paired §1.1 mutation target — the CLASS
    #   iteration order IS the native-first guarantee. Flipping `native provider`
    #   to `provider native` lets a provider win while a native is healthy;
    #   test_multitrack_native_first_fallback.sh asserts the flip breaks it. Do
    #   NOT remove this marker, and do NOT reorder the class list inline.)
    for class in native provider; do
        # tier (a): fresh — unbound and not cooled (preferred), within this class.
        for a in $(_aliases_of_class "$class"); do
            [ "$a" = "${1:-}" ] && continue
            _alias_in_cooldown "$a" && continue
            [ -n "$(_alias_bound_track "$a")" ] && continue
            printf '%s' "$a"; return 0
        done
        # tier (b): reuse — healthy (not cooled) even if already bound to another
        #   Track, least-loaded first, within this class.
        best=""; bestload=""
        for a in $(_aliases_of_class "$class"); do
            [ "$a" = "${1:-}" ] && continue
            _alias_in_cooldown "$a" && continue
            load=$(_alias_load "$a")
            if [ -z "$best" ] || [ "$load" -lt "$bestload" ]; then best=$a; bestload=$load; fi
        done
        [ -n "$best" ] && { printf '%s' "$best"; return 0; }
        # no available alias in THIS class -> fall through to the next (providers).
    done
    # <<MT_ALIAS_MUT_NATIVE_FIRST
    # tier (c): no healthy alias in any class.
    return 1
}

# --- device delegation (REUSE the arbiter — never reimplement) ----------------
_arb() { MT_LOCK_DIR="${MT_LOCK_DIR:-}" MT_CONFIG="${MT_CONFIG:-}" "$ARB" "$@"; }

# --- commands -----------------------------------------------------------------
cmd_aliases() {
    _load_tracks; _load_roster; _ensure_dirs
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
      _reap
      printf 'ALIAS             KIND      STATE       TRACK(S)\n'
      local a bt state
      for a in $(_all_aliases); do
          bt=$(_alias_bound_tracks "$a")   # comma-joined — an alias MAY hold >1
          if [ -n "$bt" ]; then state=bound
          elif _alias_in_cooldown "$a"; then state=cooldown; bt="-"
          else state=free; bt="-"; fi
          printf '%-17s %-9s %-11s %s\n' "$a" "$(_alias_kind "$a")" "$state" "$bt"
      done
    ) 9<"$LOCKF"
}

cmd_tracks() {
    _load_tracks; _load_roster; _ensure_dirs
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
      _reap
      printf 'TRACK        ALIAS             WORKTREE\n'
      local t a wt
      for t in $(_all_tracks); do
          a=$(_track_bound_alias "$t"); [ -n "$a" ] || a='(unbound)'
          wt=$(awk -F'|' -v t="$t" '$2==t{print $3; exit}' "$BIND" 2>/dev/null)
          [ -n "$wt" ] || wt=$(_track_mount "$t")
          printf '%-12s %-17s %s\n' "$t" "$a" "$wt"
      done
    ) 9<"$LOCKF"
}

cmd_status() {
    _load_tracks; _load_roster; _ensure_dirs
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
      _reap
      local now; now=$(_now)
      printf '== alias<->track bindings (%s) ==\n' "$BIND"
      if [ -s "$BIND" ]; then
          printf 'ALIAS             TRACK        REMAIN  WORKTREE\n'
          awk -F'|' -v now="$now" '{ rem=$6-now; if(rem<0)rem=0;
              printf "%-17s %-12s %-6ss %s\n",$1,$2,rem,$3 }' "$BIND"
      else printf '(none bound)\n'; fi
      printf '\n== cooldown (limited aliases: class + operational-again) ==\n'
      if [ -s "$COOL" ]; then
          awk -F'|' -v now="$now" '{ rem=$2-now; if(rem<0)rem=0; cls=($4==""?"session":$4);
              printf "%-17s class=%-12s remaining=%ss operational-again-epoch=%s reason=%s\n",$1,cls,rem,$2,$3 }' "$COOL"
      else printf '(none)\n'; fi
    ) 9<"$LOCKF"
    printf '\n== device pool (delegated to arbiter) ==\n'
    _arb status 2>/dev/null || printf '(arbiter status unavailable)\n'
}

cmd_bind() {
    [ -n "${OPT_ALIAS:-}" ] && [ -n "${OPT_TRACK:-}" ] || { echo "usage: bind --alias A --track T [--worktree P] [--ttl S]" >&2; exit 2; }
    _load_tracks; _load_roster; _ensure_dirs
    _alias_known "$OPT_ALIAS" || { echo "ENOALIAS: unknown alias '$OPT_ALIAS' (not in roster)" >&2; exit 4; }
    _track_exists "$OPT_TRACK" || { echo "ENOTRACK: unknown track '$OPT_TRACK'" >&2; exit 4; }
    local ttl=${OPT_TTL:-$MT_ALIAS_TTL} wt=${OPT_WORKTREE:-}
    [ -n "$wt" ] || wt=$(_track_mount "$OPT_TRACK")
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy (flock timeout)" >&2; exit 1; }
      _reap
      # ---- track-side single-owner conflict scan (NO write on any conflict) --
      # Alias-side exclusivity is RELAXED (operator mandate): an alias MAY hold
      # multiple Tracks, so binding an alias to a 2nd Track is NOT rejected. Only
      # track-side single-owner is enforced (§11.4.119 — a Track has exactly one
      # alias; prevents cross-contamination). The cooldown skip is what makes a
      # rate-limited alias unusable until it expires.
      # >>MT_ALIAS_MUT_DOUBLEBIND (paired §1.1 mutation target — do NOT remove marker)
      if _alias_in_cooldown "$OPT_ALIAS"; then
          _event DENY "$OPT_ALIAS" "$OPT_TRACK" "$wt" "" "alias-in-cooldown"
          echo "ECOOLDOWN: alias '$OPT_ALIAS' is rate-limited (in cooldown) — pick another" >&2; exit 4
      fi
      local tb
      tb=$(_track_bound_alias "$OPT_TRACK")
      if [ -n "$tb" ] && [ "$tb" != "$OPT_ALIAS" ]; then
          _event DENY "$OPT_ALIAS" "$OPT_TRACK" "$wt" "" "track-already-bound:$tb"
          echo "EBUSY: track '$OPT_TRACK' already driven by alias '$tb' (one track = one alias)" >&2; exit 3
      fi
      # <<MT_ALIAS_MUT_DOUBLEBIND
      # ---- claim the (track) row atomically (single snapshot rewrite) -------
      # Drop ONLY the row for THIS Track (Track is the unique key — one alias per
      # Track), preserving every OTHER row incl. this alias's OTHER Tracks.
      local now exp
      now=$(_now); exp=$((now + ttl))
      {
          [ -s "$BIND" ] && awk -F'|' -v t="$OPT_TRACK" '$2!=t { print }' "$BIND"
          printf '%s|%s|%s|%s|%s|%s|%s\n' "$OPT_ALIAS" "$OPT_TRACK" "$wt" "${HOLDER_PID:-0}" "$now" "$exp" "active"
      } > "$BIND.tmp.$$" && mv -f "$BIND.tmp.$$" "$BIND"
      _event BIND "$OPT_ALIAS" "$OPT_TRACK" "$wt" "$exp" "ttl=$ttl"
      printf 'BOUND: alias=%s -> track=%s worktree=%s ttl=%ss expires=%s\n' \
          "$OPT_ALIAS" "$OPT_TRACK" "$wt" "$ttl" "$exp"
    ) 9<"$LOCKF"
}

cmd_unbind() {
    [ -n "${OPT_ALIAS:-}" ] || [ -n "${OPT_TRACK:-}" ] || { echo "usage: unbind (--alias A | --track T)" >&2; exit 2; }
    _load_tracks; _load_roster; _ensure_dirs
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
      _reap
      local a=${OPT_ALIAS:-} t=${OPT_TRACK:-} n
      n=$(awk -F'|' -v a="$a" -v t="$t" '(a!=""&&$1==a)||(t!=""&&$2==t){c++} END{print c+0}' "$BIND" 2>/dev/null)
      awk -F'|' -v a="$a" -v t="$t" '{ if((a!=""&&$1==a)||(t!=""&&$2==t)) next; print }' "$BIND" \
          > "$BIND.tmp.$$" 2>/dev/null && mv -f "$BIND.tmp.$$" "$BIND"
      _event UNBIND "$a" "$t" "" "" "removed=$n"
      printf 'UNBOUND: removed %s binding(s)%s%s\n' "$n" "${a:+ alias=$a}" "${t:+ track=$t}"
    ) 9<"$LOCKF"
}

cmd_heartbeat() {
    [ -n "${OPT_ALIAS:-}" ] || { echo "usage: heartbeat --alias A [--ttl S]" >&2; exit 2; }
    _load_tracks; _load_roster; _ensure_dirs
    local ttl=${OPT_TTL:-$MT_ALIAS_TTL}
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
      _reap
      local now exp n
      now=$(_now); exp=$((now + ttl))
      n=$(awk -F'|' -v a="$OPT_ALIAS" '$1==a{c++} END{print c+0}' "$BIND")
      [ "$n" -ge 1 ] || { echo "no binding held by alias '$OPT_ALIAS' (nothing to refresh)"; exit 0; }
      awk -F'|' -v a="$OPT_ALIAS" -v e="$exp" 'BEGIN{OFS="|"} { if($1==a){$6=e} print }' "$BIND" \
          > "$BIND.tmp.$$" && mv -f "$BIND.tmp.$$" "$BIND"
      _event HEARTBEAT "$OPT_ALIAS" "$(_alias_bound_track "$OPT_ALIAS")" "" "$exp" "refreshed=$n ttl=$ttl"
      printf 'HEARTBEAT: alias=%s refreshed %s binding(s) -> expires=%s\n' "$OPT_ALIAS" "$n" "$exp"
    ) 9<"$LOCKF"
}

# fallback: current alias for TRACK hit a limit/error/rate-limit -> put it in
# cooldown and rebind the SAME track to the next available alias, PRESERVING the
# worktree AND the track's device leases (leases are keyed by the STABLE track id
# in the arbiter — the alias changes, not the track). Race-free hand-off.
cmd_fallback() {
    [ -n "${OPT_TRACK:-}" ] || { echo "usage: fallback --track T [--reason R] [--ttl S]" >&2; exit 2; }
    _load_tracks; _load_roster; _ensure_dirs
    _track_exists "$OPT_TRACK" || { echo "ENOTRACK: unknown track '$OPT_TRACK'" >&2; exit 4; }
    # reason-CLASS-aware cooldown (item 2): --class session|weekly|subscription
    # sets the operational-again window; an explicit --until (parsed reset epoch)
    # wins. Default class = session (the common 429 self-heal case), preserving
    # the pre-existing fallback behaviour for callers that pass no --class.
    local ttl=${OPT_TTL:-$MT_ALIAS_TTL} reason=${OPT_REASON:-rate-limit} class=${OPT_CLASS:-session}
    case "$class" in session|weekly|subscription) : ;;
        *) echo "EBADCLASS: --class must be session|weekly|subscription (got '$class')" >&2; exit 2 ;; esac
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
      _reap
      local cur nxt wt now exp until
      cur=$(_track_bound_alias "$OPT_TRACK")
      [ -n "$cur" ] || { echo "ENOBIND: track '$OPT_TRACK' has no bound alias to fall back FROM" >&2; exit 4; }
      nxt=$(_next_available_alias "$cur") || {
          _event DENY "$cur" "$OPT_TRACK" "" "" "no-available-alias-for-fallback"
          echo "ENOFREE: no available alias to fall back TO for track '$OPT_TRACK' (all bound/cooldown) — parked (§11.4.101 bounded block)" >&2
          exit 5; }
      wt=$(awk -F'|' -v t="$OPT_TRACK" '$2==t{print $3; exit}' "$BIND"); [ -n "$wt" ] || wt=$(_track_mount "$OPT_TRACK")
      now=$(_now); exp=$((now + ttl))
      until=${OPT_UNTIL:-$(_cooldown_until_for_class "$class")}
      # 1) put the failing alias into cooldown (drop any prior row for it first)
      if [ -s "$COOL" ]; then awk -F'|' -v a="$cur" '$1!=a' "$COOL" > "$COOL.tmp.$$" && mv -f "$COOL.tmp.$$" "$COOL"; fi
      printf '%s|%s|%s|%s\n' "$cur" "$until" "$reason" "$class" >> "$COOL"
      _event COOLDOWN "$cur" "$OPT_TRACK" "" "$until" "class=$class reason=$reason operational-again=$until"
      # 2) rebind SAME track to the next alias (atomic snapshot rewrite). Drop
      #    ONLY this Track's row (Track is the unique key) so that if $nxt is a
      #    REUSED alias already serving other Tracks, those bindings survive.
      {
          awk -F'|' -v t="$OPT_TRACK" '$2!=t { print }' "$BIND"
          printf '%s|%s|%s|%s|%s|%s|%s\n' "$nxt" "$OPT_TRACK" "$wt" "${HOLDER_PID:-0}" "$now" "$exp" "active"
      } > "$BIND.tmp.$$" && mv -f "$BIND.tmp.$$" "$BIND"
      _event FALLBACK "$nxt" "$OPT_TRACK" "$wt" "$exp" "from=$cur reason=$reason (device leases preserved)"
      printf 'FALLBACK: track=%s %s->%s (device leases untouched) worktree=%s expires=%s\n' \
          "$OPT_TRACK" "$cur" "$nxt" "$wt" "$exp"
    ) 9<"$LOCKF"
}

# mark-limited: record a per-alias limit from a REAL signal (item 2), WITHOUT a
# track hand-off — the explicit "this alias is not operational until <until>"
# entry point the fallback monitor calls when it classifies a captured 429 /
# weekly-limit / subscription-expiry signature (§11.4.6: the class comes from a
# real signal, never a guess). --until (a parsed reset epoch) wins over the class
# default. A cooled alias is NEVER auto-selected until its `until` passes (session/
# weekly) or an explicit mark-operational/renewal clears it (subscription).
cmd_mark_limited() {
    [ -n "${OPT_ALIAS:-}" ] || { echo "usage: mark-limited --alias A [--class session|weekly|subscription] [--until EPOCH] [--reason R]" >&2; exit 2; }
    _load_tracks; _load_roster; _ensure_dirs
    _alias_known "$OPT_ALIAS" || { echo "ENOALIAS: unknown alias '$OPT_ALIAS' (not in roster)" >&2; exit 4; }
    local class=${OPT_CLASS:-session} reason=${OPT_REASON:-}
    case "$class" in session|weekly|subscription) : ;;
        *) echo "EBADCLASS: --class must be session|weekly|subscription (got '$class')" >&2; exit 2 ;; esac
    [ -n "$reason" ] || reason="${class}-limit"
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
      _reap
      local until
      until=${OPT_UNTIL:-$(_cooldown_until_for_class "$class")}
      if [ -s "$COOL" ]; then awk -F'|' -v a="$OPT_ALIAS" '$1!=a' "$COOL" > "$COOL.tmp.$$" && mv -f "$COOL.tmp.$$" "$COOL"; fi
      printf '%s|%s|%s|%s\n' "$OPT_ALIAS" "$until" "$reason" "$class" >> "$COOL"
      _event COOLDOWN "$OPT_ALIAS" "" "" "$until" "class=$class reason=$reason operational-again=$until (mark-limited)"
      printf 'MARK-LIMITED: alias=%s class=%s reason=%s operational-again=%s (%s)\n' \
          "$OPT_ALIAS" "$class" "$reason" "$until" "$(date -u -d "@$until" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "epoch=$until")"
    ) 9<"$LOCKF"
}

# mark-operational: clear an alias's cooldown NOW (item 2/3 — a subscription
# renewal / an operator-confirmed recovery makes a higher-priority native
# operational again; the next auto-assign/promote will prefer it). Idempotent.
cmd_mark_operational() {
    [ -n "${OPT_ALIAS:-}" ] || { echo "usage: mark-operational --alias A" >&2; exit 2; }
    _load_tracks; _load_roster; _ensure_dirs
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
      _reap
      local n=0
      if [ -s "$COOL" ]; then
          n=$(awk -F'|' -v a="$OPT_ALIAS" '$1==a{c++} END{print c+0}' "$COOL")
          awk -F'|' -v a="$OPT_ALIAS" '$1!=a' "$COOL" > "$COOL.tmp.$$" && mv -f "$COOL.tmp.$$" "$COOL"
      fi
      _event COOLDOWN "$OPT_ALIAS" "" "" "0" "cleared=$n (mark-operational — alias recovered)"
      printf 'MARK-OPERATIONAL: alias=%s cooldown cleared (%s row[s]); now eligible for auto-assign/promote\n' "$OPT_ALIAS" "$n"
    ) 9<"$LOCKF"
}

# promote: auto-use-on-recovery (item 3) — for EVERY bound track, if a strictly
# HIGHER-priority (lower _alias_rank: native before provider, then config order)
# NON-cooled alias exists, rebind the track UPWARD to it, PRESERVING the worktree
# AND the track's device leases (leases are keyed by the STABLE track id in the
# arbiter — the alias changes, not the track). This is the "as soon as a higher-
# priority native recovers, rebind the tracks to it" behaviour: run it after every
# reap/tick so a track that fell onto a provider returns to a recovered native
# automatically. Idempotent (a track already on the best alias is left untouched).
cmd_promote() {
    _load_tracks; _load_roster; _ensure_dirs
    local ttl=${OPT_TTL:-$MT_ALIAS_TTL}
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
      _reap
      local t cur currank best bestrank wt now exp moved=0
      now=$(_now); exp=$((now + ttl))
      for t in $(_all_tracks); do
          cur=$(_track_bound_alias "$t"); [ -n "$cur" ] || continue
          currank=$(_alias_rank "$cur") || continue
          best=$(_best_operational_alias); [ -n "$best" ] || continue
          bestrank=$(_alias_rank "$best") || continue
          if [ "$bestrank" -lt "$currank" ] && [ "$best" != "$cur" ]; then
              wt=$(awk -F'|' -v t="$t" '$2==t{print $3; exit}' "$BIND"); [ -n "$wt" ] || wt=$(_track_mount "$t")
              {
                  awk -F'|' -v t="$t" '$2!=t { print }' "$BIND"
                  printf '%s|%s|%s|%s|%s|%s|%s\n' "$best" "$t" "$wt" "${HOLDER_PID:-0}" "$now" "$exp" "active"
              } > "$BIND.tmp.$$" && mv -f "$BIND.tmp.$$" "$BIND"
              _event FALLBACK "$best" "$t" "$wt" "$exp" "promote from=$cur (higher-priority alias recovered; device leases preserved)"
              printf 'PROMOTE: track=%s %s->%s (higher-priority alias recovered; leases untouched)\n' "$t" "$cur" "$best"
              moved=$((moved + 1))
          fi
      done
      printf 'PROMOTE: %s track(s) rebound upward to a higher-priority alias\n' "$moved"
    ) 9<"$LOCKF"
}

cmd_auto_assign() {
    _load_tracks; _load_roster; _ensure_dirs
    local ttl=${OPT_TTL:-$MT_ALIAS_TTL}
    ( flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
      _reap
      local t a now exp wt bound=0
      now=$(_now); exp=$((now + ttl))
      for t in $(_all_tracks); do
          [ -n "$(_track_bound_alias "$t")" ] && continue      # already bound
          a=$(_next_available_alias "") || { echo "note: no available (non-cooled) aliases (track $t left unbound)"; break; }
          wt=$(_track_mount "$t")
          # drop ONLY this Track's row (Track = unique key); $a MAY already serve
          # other Tracks (reuse when aliases are scarce) — keep those rows.
          {
              awk -F'|' -v t="$t" '$2!=t { print }' "$BIND"
              printf '%s|%s|%s|%s|%s|%s|%s\n' "$a" "$t" "$wt" "${HOLDER_PID:-0}" "$now" "$exp" "active"
          } > "$BIND.tmp.$$" && mv -f "$BIND.tmp.$$" "$BIND"
          _event BIND "$a" "$t" "$wt" "$exp" "auto-assign ttl=$ttl"
          printf 'AUTO-BOUND: alias=%s -> track=%s worktree=%s\n' "$a" "$t" "$wt"
          bound=$((bound + 1))
      done
      printf 'AUTO-ASSIGN: %s track(s) newly bound\n' "$bound"
    ) 9<"$LOCKF"
}

# require the track to have an ACTIVE alias binding before it may lease devices
# (§11.4.119 — only a live, alias-driven track owns hardware). Then DELEGATE to
# the arbiter under the STABLE track id (never reimplement device leasing).
_require_bound() {  # $1 track
    _load_tracks; _load_roster; _ensure_dirs
    _track_exists "$1" || { echo "ENOTRACK: unknown track '$1'" >&2; exit 4; }
    local a
    ( flock -w "$MT_LOCK_WAIT" 9 || exit 1; _reap ) 9<"$LOCKF"
    a=$(_track_bound_alias "$1")
    [ -n "$a" ] || { echo "ENOBIND: track '$1' has no bound alias — bind an alias before leasing devices (§11.4.119)" >&2; exit 4; }
    printf '%s' "$a"
}

cmd_acquire_devices() {
    [ -n "${OPT_TRACK:-}" ] || { echo "usage: acquire-devices --track T [arbiter acquire args...]" >&2; exit 2; }
    local a; a=$(_require_bound "$OPT_TRACK") || exit $?
    printf '# track=%s driven by alias=%s -> delegating to arbiter\n' "$OPT_TRACK" "$a"
    _arb acquire --track "$OPT_TRACK" "$@"
}

cmd_release_devices() {
    [ -n "${OPT_TRACK:-}" ] || { echo "usage: release-devices --track T [--device D]" >&2; exit 2; }
    _arb release --track "$OPT_TRACK" "$@"
}

# safe pool hand-off across tracks: release FROM-track's leases, acquire for
# TO-track — ALL-OR-NOTHING at the arbiter level. Both tracks MUST be alias-bound.
cmd_handoff() {
    [ -n "${OPT_FROM:-}" ] && [ -n "${OPT_TO:-}" ] || { echo "usage: handoff --from-track T1 --to-track T2 (--devices d,d | --caps c [--count N])" >&2; exit 2; }
    local fa ta
    fa=$(OPT_TRACK=$OPT_FROM _require_bound "$OPT_FROM") || exit $?
    ta=$(OPT_TRACK=$OPT_TO   _require_bound "$OPT_TO")   || exit $?
    printf '# hand-off: %s(alias=%s) -> %s(alias=%s)\n' "$OPT_FROM" "$fa" "$OPT_TO" "$ta"
    # 1) TO-track pre-acquires (all-or-nothing). If it EBUSYs because FROM still
    #    holds the set, release FROM first then retry once (non-blocking, bounded).
    if _arb acquire --track "$OPT_TO" "$@" 2>/dev/null; then
        _arb release --track "$OPT_FROM" >/dev/null 2>&1
        _event HANDOFF "$ta" "$OPT_TO" "" "" "from=$OPT_FROM (direct)"
        printf 'HANDOFF: %s -> %s complete (to-track acquired free devices; from-track released)\n' "$OPT_FROM" "$OPT_TO"
        return 0
    fi
    _arb release --track "$OPT_FROM" >/dev/null 2>&1
    if _arb acquire --track "$OPT_TO" "$@"; then
        _event HANDOFF "$ta" "$OPT_TO" "" "" "from=$OPT_FROM (via-release)"
        printf 'HANDOFF: %s -> %s complete (from-track released, to-track acquired)\n' "$OPT_FROM" "$OPT_TO"
        return 0
    fi
    _event DENY "$ta" "$OPT_TO" "" "" "handoff-failed from=$OPT_FROM"
    echo "EHANDOFF: hand-off $OPT_FROM -> $OPT_TO failed (to-track could not acquire even after release)" >&2
    exit 3
}

cmd_reap() {
    _load_tracks; _load_roster; _ensure_dirs
    ( flock -w "$MT_LOCK_WAIT" 9 || exit 1; _reap; echo "REAP: stale bindings + cooldowns expired (see events.jsonl)"; ) 9<"$LOCKF"
    _arb reap >/dev/null 2>&1 || true
}

cmd_reconcile() {
    # rebuild bindings from the append-only JSONL (§11.4.116 recovery path):
    # replay in order keyed by TRACK (the unique key — an alias MAY hold several
    # Tracks, so keying by alias would silently collapse multi-Track state). Last
    # BIND/FALLBACK per Track wins; HEARTBEAT refreshes all a Track's-alias rows;
    # UNBIND/REAP drop; then reap expired. `expires` is JSON-quoted -> val().
    _load_tracks; _load_roster; _ensure_dirs
    ( flock -w "$MT_LOCK_WAIT" 9 || exit 1
      awk '
        function val(line,key,   re,s,q){ re="\""key"\":\""; if(match(line,re)){ s=substr(line,RSTART+length(re)); q=index(s,"\""); return substr(s,1,q-1)} return "" }
        function num(line,key,   re,s,i,c,d){ re="\""key"\":"; if(match(line,re)){ s=substr(line,RSTART+length(re)); d=""; for(i=1;i<=length(s);i++){c=substr(s,i,1); if(c ~ /[0-9]/) d=d c; else break} return d} return "" }
        {
          # NOTE (RB-FIX2, section 11.4.111/11.4.115): xp (NOT exp) is
          # deliberate --- exp is a gawk BUILT-IN function (exponential);
          # gawk 5.1.0 fatal-errors with a syntax error when a built-in
          # function name is assigned as a scalar variable. POSIX awk and
          # mawk historically tolerated this shadowing; gawk does not.
          # Regression-guarded by test_multitrack_orchestrator_reconcile.sh
          # (RED reproduces the gawk fatal on the pre-fix program; GREEN
          # asserts a clean run plus correct reconciled snapshot).
          ev=val($0,"event"); al=val($0,"alias"); tr=val($0,"track"); wt=val($0,"worktree"); xp=val($0,"expires"); pid=num($0,"pid"); ts=num($0,"ts")
          if(ev=="BIND" || ev=="FALLBACK"){ if(tr!=""){ t2a[tr]=al; twt[tr]=wt; te[tr]=xp; tp[tr]=pid; tacq[tr]=ts } }
          else if(ev=="HEARTBEAT"){ if(al!=""){ for(t in t2a) if(t2a[t]==al) te[t]=xp } }
          else if(ev=="UNBIND"){ if(tr!=""){ delete t2a[tr] } if(al!=""){ for(t in t2a) if(t2a[t]==al) delete t2a[t] } }
          else if(ev=="REAP"){ if(tr!=""){ delete t2a[tr] } else if(al!=""){ for(t in t2a) if(t2a[t]==al) delete t2a[t] } }
        }
        END{ for(t in t2a) if(t!="") printf "%s|%s|%s|%s|%s|%s|%s\n", t2a[t], t, twt[t], tp[t], tacq[t], te[t], "active" }
      ' "$EVENTS" > "$BIND.tmp.$$"
      # RB-FIX3 (I-b): capture the awk pipeline's OWN exit status explicitly.
      # The previous `awk '...' > tmp && mv ...` form let `&&` short-circuit
      # `mv` on a genuine awk failure (correctly leaving bindings.snapshot
      # un-clobbered) but then fell through to an UNCONDITIONAL success
      # `echo` as the subshell's last command -- so `cmd_reconcile` ALWAYS
      # returned 0 regardless of whether the rebuild actually happened (an
      # independent code review reproduced this live on the pre-fix `exp`
      # gawk-fatal artifact: "syntax error" on stderr + bindings.snapshot
      # stays empty/stale, yet rc=0 and "RECONCILE: ... rebuilt" still
      # prints -- a PASS-bluff at the tooling layer). On failure: discard
      # the (possibly partial/empty) tmp file, print a clearly-labelled
      # error to stderr, and return non-zero -- NEVER the false-success
      # message, NEVER a silent rc=0. The happy path (awk succeeds) is
      # byte-for-byte unchanged: mv + reap + the SAME success echo.
      _reconcile_awk_rc=$?
      if [ "$_reconcile_awk_rc" -ne 0 ]; then
          rm -f "$BIND.tmp.$$" 2>/dev/null || true
          echo "ERECONCILE: awk rebuild FAILED (rc=$_reconcile_awk_rc) -- bindings.snapshot NOT rebuilt, prior state preserved (see $EVENTS + the stderr above)" >&2
          exit 1
      fi
      mv -f "$BIND.tmp.$$" "$BIND"
      _reap
      echo "RECONCILE: bindings snapshot rebuilt from $EVENTS"
    ) 9<"$LOCKF"
}

# --- CLI ----------------------------------------------------------------------
usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$ORCH_SELF" 2>/dev/null | sed 's/^# \{0,1\}//'; }

[ $# -ge 1 ] || { usage >&2; exit 2; }
CMD=$1; shift

OPT_ALIAS=""; OPT_TRACK=""; OPT_WORKTREE=""; OPT_TTL=""; OPT_REASON=""
OPT_CLASS=""; OPT_UNTIL=""
OPT_FROM=""; OPT_TO=""; HOLDER_PID=${MT_HOLDER_PID:-$PPID}
PASSTHRU=""   # remaining args forwarded to the arbiter (device sub-commands)
while [ $# -gt 0 ]; do
    case "$1" in
        --alias)     OPT_ALIAS=$2; shift ;;   --alias=*)    OPT_ALIAS=${1#--alias=} ;;
        --track)     OPT_TRACK=$2; shift ;;   --track=*)    OPT_TRACK=${1#--track=} ;;
        --worktree)  OPT_WORKTREE=$2; shift ;;--worktree=*) OPT_WORKTREE=${1#--worktree=} ;;
        --ttl)       OPT_TTL=$2; shift ;;     --ttl=*)      OPT_TTL=${1#--ttl=} ;;
        --reason)    OPT_REASON=$2; shift ;;  --reason=*)   OPT_REASON=${1#--reason=} ;;
        --class)     OPT_CLASS=$2; shift ;;   --class=*)    OPT_CLASS=${1#--class=} ;;
        --until)     OPT_UNTIL=$2; shift ;;   --until=*)    OPT_UNTIL=${1#--until=} ;;
        --from-track)OPT_FROM=$2; shift ;;    --from-track=*)OPT_FROM=${1#--from-track=} ;;
        --to-track)  OPT_TO=$2; shift ;;      --to-track=*) OPT_TO=${1#--to-track=} ;;
        --help|-h)   usage; exit 0 ;;
        # device-passthru flags (forwarded verbatim to the arbiter):
        --device|--devices|--caps|--count|--policy|--pid)
                     PASSTHRU="$PASSTHRU $1 $2"; shift ;;
        --device=*|--devices=*|--caps=*|--count=*|--policy=*|--pid=*)
                     PASSTHRU="$PASSTHRU $1" ;;
        *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
# shellcheck disable=SC2086
set -- $PASSTHRU

case "$CMD" in
    aliases)         cmd_aliases ;;
    tracks)          cmd_tracks ;;
    status)          cmd_status ;;
    bind)            cmd_bind ;;
    unbind)          cmd_unbind ;;
    heartbeat)       cmd_heartbeat ;;
    fallback)        cmd_fallback ;;
    mark-limited)    cmd_mark_limited ;;
    mark-operational) cmd_mark_operational ;;
    promote)         cmd_promote ;;
    auto-assign)     cmd_auto_assign ;;
    acquire-devices) cmd_acquire_devices "$@" ;;
    release-devices) cmd_release_devices "$@" ;;
    handoff)         cmd_handoff "$@" ;;
    reap)            cmd_reap ;;
    reconcile)       cmd_reconcile ;;
    --help|-h|help)  usage ;;
    *) echo "unknown command: $CMD" >&2; usage >&2; exit 2 ;;
esac
