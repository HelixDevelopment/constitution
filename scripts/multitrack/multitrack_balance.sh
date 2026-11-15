#!/bin/sh
# =============================================================================
# multitrack_balance.sh — RB-06 subscription/route balance + reuse selector for
#     the multi-track ruler-bridge worker pool.
# -----------------------------------------------------------------------------
# Purpose:
#   RB-05 (multitrack_sessions.sh) SPAWNS a worker but is balancer-agnostic: it
#   takes a first-class auth SELECTOR (MT_WORKER_ALIAS / MT_WORKER_CONFIG_DIR)
#   and hardcodes NO alias. RB-06 is the CALLER-SIDE policy that decides WHICH
#   route each spawn uses. It adds NO new spawn mechanism.
#
#   Two cooperating capabilities (operator mandate 2026-07-06, ×2 CRITICAL):
#     (a) REUSE — the SAME route may back MANY workers (ccr is stateless per
#         request; N headless workers can all point at the same provider route,
#         and one native account can back several tracks). Reuse = multiple
#         RB-05 spawns pass the same route as MT_WORKER_ALIAS.
#     (b) PROACTIVE BALANCE — spread the tracks across the live-operable route
#         set UP FRONT (least-loaded at spawn time), not merely failover after a
#         rate-limit. Layered ON TOP of (a), never instead of it.
#
#   Priority ordering (operator mandate — native `claude` accounts are ABSOLUTE
#   PRIORITY over provider aliases): the NATIVE tier is always tried FIRST; only
#   when no native route is available (all excluded / dropped) does selection
#   spill to the PROVIDER tier, where it load-balances across ALL live-operable
#   providers. This reads the mandate literally ("native claude2 FIRST, then
#   least-loaded across the operable providers") — native FIRST (tier), then
#   least-loaded within the reached tier (§11.4.6 — this is the determination,
#   not a guess: the wording is sequential "FIRST … then").
#
#   NO HARDCODED ALIAS anywhere (§11.4.28). "native FIRST" is by route KIND
#   (native), never a literal `claude2` — the actual native route(s) come from
#   the operable set (env override / cache / config roster). NO --force / no
#   escape that bypasses the RB-02 host-safety budget (that guard runs FIRST, in
#   the RB-05 spawn; RB-06 only decides WHICH route, never WHETHER to spawn).
#
# DESIGN INVARIANT (the anti-bluff lever): mt_balance_select is a PURE FUNCTION
#   of (per-route inflight registry + operable-set) — it touches NO network, NO
#   `claude`, NO `ccr`. Given an identical registry + operable set it returns an
#   identical route (§11.4.50 determinism), so it is proven device-AND-account-
#   INDEPENDENTLY against a MOCK registry. The ONE network-touching function,
#   mt_provider_operability_probe, is a SEPARATE bounded sweep that only WRITES
#   the operable-set cache; select merely READS it. The probe is NOT on the
#   pure-select path and is NOT required for the RED/GREEN test to pass.
#
# Usage (SOURCED — a pure function library, like multitrack_host_budget.sh):
#     . /path/to/multitrack_balance.sh
#     route=$(mt_balance_select) && echo "spawn onto: $route"
#     mt_balance_mark_spawn "$route" "$pid"     # inflight++
#     mt_balance_mark_done  "$route" "$pid"     # inflight--
#     mt_balance_mark_fail  "$route" rate-limit # consecutive_fails++ ; drop-if-threshold
#
#   Route encoding (the value passed to RB-05 as MT_WORKER_ALIAS):
#     native   route == an alias name           e.g. `claude2`
#     provider route == "<provider>,<model>"    e.g. `opencode,big-pickle`
#   Operable-set line encoding (kind-tagged, TAB-separated):
#     native<TAB>claude2
#     provider<TAB>opencode,big-pickle
#   Callers that only have bare routes may use the honest KIND heuristic: a
#   route containing a comma is a provider route, else native (documented,
#   §11.4.6 — a determination from the encoding above, not a guess).
#
# Inputs (env, all optional, documented defaults — §11.4.6):
#   MT_BALANCE_OPERABLE   — explicit operable set (wins). Newline OR '|'
#                           separated; each entry `kind<TAB>route`, `kind:route`,
#                           or a bare route (kind inferred by the comma
#                           heuristic). Used by tests + by the caller after a
#                           fresh probe. Absence => cache => config roster.
#   MT_BALANCE_PRIORITY_KINDS — space list of route kinds tried FIRST, in order
#                           (default "native"). Never a literal alias.
#   MT_BALANCE_DROP_THRESHOLD  — consecutive_fails at which a route is DROPPED
#                           from the rotation (default 3). A dropped route is
#                           re-eligible only after mt_balance_mark_ok / a fresh
#                           probe clears it.
#   MT_BALANCE_STATE_DIR  — registry root (events.jsonl + routes/<safe>.json +
#                           operable.cache). Default
#                           ${XDG_RUNTIME_DIR:-/tmp}/<repo-basename>/multitrack/balance.
#   MT_BALANCE_CACHE_TTL  — operable.cache freshness window, seconds (default
#                           120). Older cache is ignored by the operable-set
#                           resolver (a fresh probe must re-seed it).
#   MT_REPO_ROOT / MT_CONFIG — consumer project root / config path (for the
#                           config-roster fallback + native-kind tagging).
#   MT_CCR_BASE_URL       — ccr Anthropic endpoint for the probe (default
#                           http://127.0.0.1:3456). Probe-only; not on select.
#   MT_BALANCE_PROBE_TIMEOUT — per-provider probe bound, seconds (default 40).
#
# Outputs: mt_balance_select prints ONE route on stdout (rc 0) or nothing
#   (rc 5 = every candidate excluded/dropped — §11.4.101 park, no hang; rc 2 =
#   empty operable set). mark_* print nothing on success. probe prints the
#   newline route list it cached.
#
# Side-effects: writes ONLY under MT_BALANCE_STATE_DIR (append-only events.jsonl
#   + atomic per-route snapshots + operable.cache). NEVER touches a device,
#   NEVER prints a credential (§11.4.10 — the probe sends ccr a DUMMY x-api-key;
#   ccr injects the real provider key server-side, so no provider secret is ever
#   handled here). select/mark touch NO network.
#
# Dependencies: sh (POSIX), sed, awk, date, mktemp, tr; `curl` + `timeout` used
#   ONLY by mt_provider_operability_probe (optional — absent => honest empty
#   probe, never a fake-operable route).
#
# Cross-references: docs/superpowers/plans/ruler_bridge_plan.md RB-06;
#   scratchpad rb06_report.md (operable BALANCE SET = {opencode,nvidia,chutes,
#   siliconflow,zai-coding-plan,kilo} captured 2026-07-06 + the interface
#   contract); constitution/scripts/multitrack/multitrack_sessions.sh (RB-05
#   consumer — sets MT_WORKER_ALIAS to the selected route);
#   multitrack_host_budget.sh (RB-02 — the WHETHER guard, runs first);
#   multitrack_fallback_monitor.sh (RB-06 headless drop-hook calls mark_fail);
#   §11.4.116 (agent-registry events.jsonl + snapshot); §11.4.50 (determinism);
#   §11.4.107(10) (self-validated select against golden registries);
#   §11.4.28/§11.4.35 (constitution-layer, project-agnostic); §11.4.10
#   (no provider secret handled); §11.4.18 (this doc block); §11.4.67 (POSIX sh).
#   Recommended pre-build gate: CM-MULTITRACK-ALIAS-REUSE-ON-LIMIT (the brief's
#   name; rb06_report §5 alt name CM-MULTITRACK-PROVIDER-BALANCE — same gate).
# =============================================================================

# NOTE: sourced library — do NOT `set -e`/`set -u` here (would leak into the
# caller's shell). Functions are individually defensive instead.

# ---------------------------------------------------------------------------
# self-location + registry root
# ---------------------------------------------------------------------------
_mt_bal_self="${MT_BALANCE_SELF:-$0}"
case "$_mt_bal_self" in
    */*) MT_BAL_DIR=${_mt_bal_self%/*} ;;
    *)   MT_BAL_DIR=. ;;
esac

_mt_bal_repo_root() {
    if [ -n "${MT_REPO_ROOT:-}" ]; then printf '%s\n' "$MT_REPO_ROOT"; return 0; fi
    ( cd "$MT_BAL_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}

_mt_bal_state_dir() {
    if [ -n "${MT_BALANCE_STATE_DIR:-}" ]; then printf '%s\n' "$MT_BALANCE_STATE_DIR"; return 0; fi
    _brr=$(_mt_bal_repo_root); _bb=$(basename "${_brr:-project}")
    printf '%s\n' "${XDG_RUNTIME_DIR:-/tmp}/$_bb/multitrack/balance"
}

MT_BAL_PRIORITY_KINDS="${MT_BALANCE_PRIORITY_KINDS:-native}"
MT_BAL_DROP_THRESHOLD="${MT_BALANCE_DROP_THRESHOLD:-3}"
MT_BAL_CACHE_TTL="${MT_BALANCE_CACHE_TTL:-120}"
MT_BAL_CCR_BASE="${MT_CCR_BASE_URL:-http://127.0.0.1:3456}"
MT_BAL_PROBE_TIMEOUT="${MT_BALANCE_PROBE_TIMEOUT:-40}"

_mt_bal_now()  { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }
_mt_bal_epoch(){ date +%s 2>/dev/null || echo 0; }
_mt_bal_safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }
_mt_bal_jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# ---------------------------------------------------------------------------
# per-route snapshot read helpers (§11.4.116). A route with NO snapshot has
# inflight=0, consecutive_fails=0, last_fail_ts=0, dropped=0 (fresh).
# ---------------------------------------------------------------------------
_mt_bal_route_file() { printf '%s/routes/%s.json\n' "$(_mt_bal_state_dir)" "$(_mt_bal_safe "$1")"; }

_mt_bal_field() {
    # $1=route $2=field (integer field) -> value or 0
    _rf=$(_mt_bal_route_file "$1")
    [ -f "$_rf" ] || { printf '0\n'; return 0; }
    _v=$(sed -n 's/.*"'"$2"'":\([0-9]*\).*/\1/p' "$_rf" 2>/dev/null | head -n1)
    printf '%s\n' "${_v:-0}"
}
_mt_bal_inflight()   { _mt_bal_field "$1" inflight; }
_mt_bal_fails()      { _mt_bal_field "$1" consecutive_fails; }
_mt_bal_last_fail()  { _mt_bal_field "$1" last_fail_ts; }
_mt_bal_dropped()    { _mt_bal_field "$1" dropped; }

# a route is a live candidate iff not dropped AND fails < threshold.
_mt_bal_route_live() {
    [ "$(_mt_bal_dropped "$1")" = "0" ] || return 1
    _f=$(_mt_bal_fails "$1")
    [ "$_f" -lt "$MT_BAL_DROP_THRESHOLD" ]
}

_mt_bal_write_snapshot() {
    # $1=route $2=inflight $3=fails $4=last_fail_ts $5=dropped
    _sd=$(_mt_bal_state_dir); mkdir -p "$_sd/routes" 2>/dev/null || true
    _rf="$_sd/routes/$(_mt_bal_safe "$1").json"
    _tmp="$_sd/routes/.$(_mt_bal_safe "$1").json.tmp.$$"
    printf '{"route":"%s","inflight":%s,"consecutive_fails":%s,"last_fail_ts":%s,"dropped":%s,"updated":"%s"}\n' \
        "$(_mt_bal_jesc "$1")" "$2" "$3" "$4" "$5" "$(_mt_bal_now)" > "$_tmp" 2>/dev/null \
        && mv -f "$_tmp" "$_rf" 2>/dev/null || true
}

_mt_bal_event() {
    # $1=event $2=route $3=detail
    _sd=$(_mt_bal_state_dir); mkdir -p "$_sd" 2>/dev/null || true
    printf '{"ts":"%s","event":"%s","route":"%s","detail":"%s"}\n' \
        "$(_mt_bal_now)" "$1" "$(_mt_bal_jesc "$2")" "$(_mt_bal_jesc "$3")" >> "$_sd/events.jsonl" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# operable-set resolution (ordered, kind-tagged). Priority order (§11.4.6):
#   1. MT_BALANCE_OPERABLE env override (wins — tests + post-probe callers).
#   2. fresh operable.cache (within MT_BALANCE_CACHE_TTL).
#   3. config roster `aliases:` (native first, providers next) — a STATIC
#      fallback, honest: it is the configured roster, NOT a liveness claim.
# Emits `kind<TAB>route` lines, native routes first, then provider routes,
# preserving each source's intra-tier order. NEVER invents a route (§11.4.6).
# ---------------------------------------------------------------------------
_mt_bal_norm_operable() {
    # normalise a '|'-or-newline list into `kind<TAB>route` lines.
    printf '%s\n' "$1" | tr '|' '\n' | while IFS= read -r _e; do
        _e=$(printf '%s' "$_e" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$_e" ] || continue
        case "$_e" in
            *"$(printf '\t')"*) printf '%s\n' "$_e" ;;                 # already kind<TAB>route
            native:*)    printf 'native\t%s\n'   "${_e#native:}" ;;
            provider:*)  printf 'provider\t%s\n' "${_e#provider:}" ;;
            *,*)         printf 'provider\t%s\n' "$_e" ;;              # comma => provider,model
            *)           printf 'native\t%s\n'   "$_e" ;;             # bare => native alias
        esac
    done
}

_mt_bal_operable_from_config() {
    # emit `kind<TAB>route` from the consumer roster (native first). Best-effort:
    # sources multitrack_config.sh if a config path is known; else nothing.
    _cfg="${MT_CONFIG:-}"
    [ -n "$_cfg" ] || return 1
    [ -r "$MT_BAL_DIR/multitrack_config.sh" ] || return 1
    # shellcheck source=/dev/null
    ( . "$MT_BAL_DIR/multitrack_config.sh" 2>/dev/null
      if command -v mt_config_aliases >/dev/null 2>&1; then
          # expect lines "<name> <kind>" ; native first then provider
          _al=$(mt_config_aliases "$_cfg" 2>/dev/null) || exit 1
          printf '%s\n' "$_al" | awk '$2=="native"{print "native\t" $1}'
          printf '%s\n' "$_al" | awk '$2=="provider"{print "provider\t" $1}'
      else exit 1; fi )
}

mt_balance_operable_set() {
    if [ -n "${MT_BALANCE_OPERABLE:-}" ]; then
        _mt_bal_norm_operable "$MT_BALANCE_OPERABLE"; return 0
    fi
    _cache="$(_mt_bal_state_dir)/operable.cache"
    if [ -f "$_cache" ]; then
        _cts=$(sed -n '1s/^#ts=\([0-9]*\).*/\1/p' "$_cache" 2>/dev/null); _cts=${_cts:-0}
        _age=$(( $(_mt_bal_epoch) - _cts ))
        if [ "$_age" -ge 0 ] && [ "$_age" -lt "$MT_BAL_CACHE_TTL" ]; then
            _mt_bal_norm_operable "$(grep -v '^#' "$_cache" 2>/dev/null)"
            return 0
        fi
    fi
    _mt_bal_operable_from_config && return 0
    return 0   # empty set (honest) — select then returns rc 2
}

# ordered candidate routes for a kind, in operable-set order, live only.
_mt_bal_candidates_for_kind() {
    # $1=kind ; stdin=operable set (kind<TAB>route) ; $2..=excludes
    _kind="$1"; shift
    _excl=" $* "
    while IFS="$(printf '\t')" read -r _k _r; do
        [ "$_k" = "$_kind" ] || continue
        [ -n "$_r" ] || continue
        case "$_excl" in *" $_r "*) continue ;; esac
        _mt_bal_route_live "$_r" || continue
        printf '%s\n' "$_r"
    done
}

# least-loaded route among a candidate list (stdin), tie-break oldest last_fail
# then first-seen (operable order). Prints the winner or nothing.
_mt_bal_least_loaded() {
    _best=""; _best_inf=-1; _best_lf=-1
    while IFS= read -r _r; do
        [ -n "$_r" ] || continue
        _inf=$(_mt_bal_inflight "$_r"); _lf=$(_mt_bal_last_fail "$_r")
        if [ "$_best_inf" -lt 0 ] || [ "$_inf" -lt "$_best_inf" ]; then
            _best="$_r"; _best_inf="$_inf"; _best_lf="$_lf"
        elif [ "$_inf" -eq "$_best_inf" ]; then
            # tie: prefer the route whose last failure is OLDER (healthier).
            # last_fail_ts==0 (never failed) is the OLDEST => most preferred.
            if [ "$_lf" -lt "$_best_lf" ] 2>/dev/null; then
                _best="$_r"; _best_lf="$_lf"
            fi
        fi
    done
    [ -n "$_best" ] && printf '%s\n' "$_best"
}

# ---------------------------------------------------------------------------
# mt_balance_select [exclude...] — THE selector. Pure function of registry +
#   operable set. Native tier tried FIRST (least-loaded within it = reuse),
#   then provider tier (least-loaded = proactive balance). rc 5 = every
#   candidate excluded/dropped (park, no hang); rc 2 = empty operable set.
# ---------------------------------------------------------------------------
mt_balance_select() {
    _op=$(mt_balance_operable_set)
    if [ -z "$_op" ]; then
        _mt_bal_event select-empty "" "no operable routes (empty set)"
        return 2
    fi
    for _kind in $MT_BAL_PRIORITY_KINDS; do
        _cand=$(printf '%s\n' "$_op" | _mt_bal_candidates_for_kind "$_kind" "$@")
        if [ -n "$_cand" ]; then
            _pick=$(printf '%s\n' "$_cand" | _mt_bal_least_loaded)
            if [ -n "$_pick" ]; then
                _mt_bal_event select "$_pick" "kind=$_kind inflight=$(_mt_bal_inflight "$_pick")"
                printf '%s\n' "$_pick"
                return 0
            fi
        fi
    done
    # any kind NOT in the priority list (proactive balance across the rest —
    # e.g. providers when priority is native-only). Least-loaded overall.
    _rest=$(printf '%s\n' "$_op" | while IFS="$(printf '\t')" read -r _k _r; do
        _skip=0
        for _pk in $MT_BAL_PRIORITY_KINDS; do [ "$_k" = "$_pk" ] && _skip=1; done
        [ "$_skip" = "0" ] || continue
        [ -n "$_r" ] || continue
        _excl=" $* "
        case "$_excl" in *" $_r "*) continue ;; esac
        _mt_bal_route_live "$_r" || continue
        printf '%s\n' "$_r"
    done)
    if [ -n "$_rest" ]; then
        _pick=$(printf '%s\n' "$_rest" | _mt_bal_least_loaded)
        if [ -n "$_pick" ]; then
            _mt_bal_event select "$_pick" "kind=overflow inflight=$(_mt_bal_inflight "$_pick")"
            printf '%s\n' "$_pick"
            return 0
        fi
    fi
    _mt_bal_event select-park "" "all candidates excluded/dropped"
    return 5
}

# ---------------------------------------------------------------------------
# mark_* — registry mutations (§11.4.116). Deterministic given prior state.
# ---------------------------------------------------------------------------
mt_balance_mark_spawn() {
    _r="${1:-}"; _pid="${2:-}"
    [ -n "$_r" ] || return 2
    _inf=$(_mt_bal_inflight "$_r"); _f=$(_mt_bal_fails "$_r"); _lf=$(_mt_bal_last_fail "$_r"); _d=$(_mt_bal_dropped "$_r")
    _mt_bal_write_snapshot "$_r" "$((_inf + 1))" "$_f" "$_lf" "$_d"
    _mt_bal_event mark-spawn "$_r" "pid=$_pid inflight=$((_inf + 1))"
}

mt_balance_mark_done() {
    _r="${1:-}"; _pid="${2:-}"
    [ -n "$_r" ] || return 2
    _inf=$(_mt_bal_inflight "$_r"); _f=$(_mt_bal_fails "$_r"); _lf=$(_mt_bal_last_fail "$_r"); _d=$(_mt_bal_dropped "$_r")
    _ninf=$((_inf - 1)); [ "$_ninf" -lt 0 ] && _ninf=0
    # a clean completion clears the consecutive-fail streak (route re-healthy).
    _mt_bal_write_snapshot "$_r" "$_ninf" 0 "$_lf" 0
    _mt_bal_event mark-done "$_r" "pid=$_pid inflight=$_ninf fails-cleared"
}

# mt_balance_mark_fail <route> <reason> — the DROP-HOOK. Increments
#   consecutive_fails; when it reaches MT_BALANCE_DROP_THRESHOLD the route is
#   marked dropped (removed from the rotation) so mt_balance_select re-picks
#   among the remaining live routes (reuse / rebalance). The fallback_monitor's
#   headless rate-limit path invokes this.
mt_balance_mark_fail() {
    _r="${1:-}"; _reason="${2:-unknown}"
    [ -n "$_r" ] || return 2
    _inf=$(_mt_bal_inflight "$_r"); _f=$(_mt_bal_fails "$_r"); _d=$(_mt_bal_dropped "$_r")
    _nf=$((_f + 1)); _now=$(_mt_bal_epoch); _drop="$_d"
    if [ "$_nf" -ge "$MT_BAL_DROP_THRESHOLD" ]; then _drop=1; fi
    _mt_bal_write_snapshot "$_r" "$_inf" "$_nf" "$_now" "$_drop"
    _mt_bal_event mark-fail "$_r" "reason=$_reason fails=$_nf dropped=$_drop"
    [ "$_drop" = "1" ] && _mt_bal_event route-dropped "$_r" "reason=$_reason (>= threshold $MT_BAL_DROP_THRESHOLD)"
    return 0
}

# mt_balance_mark_ok <route> — clear a route's fail streak + un-drop it
#   (e.g. a fresh probe found it operable again). Re-enters the rotation.
mt_balance_mark_ok() {
    _r="${1:-}"; [ -n "$_r" ] || return 2
    _inf=$(_mt_bal_inflight "$_r")
    _mt_bal_write_snapshot "$_r" "$_inf" 0 "$(_mt_bal_last_fail "$_r")" 0
    _mt_bal_event mark-ok "$_r" "streak cleared, un-dropped"
}

# ---------------------------------------------------------------------------
# mt_provider_operability_probe — the ONE network-touching function (NOT on the
#   pure-select path). Sequentially probes the ccr Anthropic endpoint for each
#   candidate provider route (bounded, §12.6/host fork-limit), writes the live
#   route list to operable.cache (with a #ts= header), and clears the drop flag
#   for every route it confirms operable (mark_ok). ccr injects the provider key
#   server-side, so this handles NO provider secret (§11.4.10). Absence of curl/
#   timeout => an HONEST empty probe (never a fake-operable route, §11.4.6).
#
#   Arguments: the candidate provider routes to probe, one per arg
#   (`provider,model`). Native routes are NOT probed here (their liveness is an
#   account-auth question, not a ccr HTTP question) — they are seeded operable
#   by config and demoted only by the monitor's mark_fail drop-hook.
# ---------------------------------------------------------------------------
mt_provider_operability_probe() {
    _sd=$(_mt_bal_state_dir); mkdir -p "$_sd" 2>/dev/null || true
    _cache="$_sd/operable.cache"; _tmp="$_sd/.operable.cache.tmp.$$"
    printf '#ts=%s probe of ccr %s\n' "$(_mt_bal_epoch)" "$MT_BAL_CCR_BASE" > "$_tmp"
    # native routes (from MT_BALANCE_NATIVE_ROUTES, space list) are seeded live.
    for _n in ${MT_BALANCE_NATIVE_ROUTES:-}; do
        printf 'native\t%s\n' "$_n" >> "$_tmp"
    done
    if ! command -v curl >/dev/null 2>&1; then
        printf '#note: curl absent — provider probe skipped (native-only, honest)\n' >> "$_tmp"
        mv -f "$_tmp" "$_cache" 2>/dev/null || true
        _mt_bal_event probe-degraded "" "curl absent"
        grep -v '^#' "$_cache" 2>/dev/null | sed 's/^[a-z]*\t//'
        return 0
    fi
    _to=""; command -v timeout >/dev/null 2>&1 && _to="timeout $MT_BAL_PROBE_TIMEOUT"
    for _route in "$@"; do
        [ -n "$_route" ] || continue
        _body='{"model":"'"$_route"'","max_tokens":16,"messages":[{"role":"user","content":"PING"}]}'
        # shellcheck disable=SC2086
        _code=$(trap '' TTIN TTOU; $_to curl -s -o /dev/null -w '%{http_code}' \
                 -H 'content-type: application/json' -H 'x-api-key: dummy' \
                 -X POST "$MT_BAL_CCR_BASE/v1/messages" -d "$_body" 2>/dev/null)
        if [ "$_code" = "200" ]; then
            printf 'provider\t%s\n' "$_route" >> "$_tmp"
            mt_balance_mark_ok "$_route" 2>/dev/null || true
        fi
        _mt_bal_event probe "$_route" "http=$_code"
    done
    mv -f "$_tmp" "$_cache" 2>/dev/null || true
    grep -v '^#' "$_cache" 2>/dev/null | sed 's/^[a-z]*\t//'
}
