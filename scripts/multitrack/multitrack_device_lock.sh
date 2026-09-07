#!/usr/bin/env bash
# =============================================================================
# multitrack_device_lock.sh — capability-aware, deadlock-proof multi-track
#                             DEVICE-LOCK arbiter (REM-02).
#                             §11.4.167 / §11.4.119 / §11.4.116 / §11.4.147 /
#                             §11.4.10 / §11.4.6.
# -----------------------------------------------------------------------------
# Purpose:
#   Arbitrate exclusive use of a SHARED, SCARCE pool of test devices (Orange Pi
#   5 Max: D1 <serial-D1> / D2 <serial-D2>, + future Nano-KVM devices)
#   across N parallel work-STREAM tracks that outnumber the M physical devices.
#   A track leases ONE OR MORE devices selected by required CAPABILITY (not just
#   identity) — e.g. the Mistiq/Vader track needs a `nano_kvm` device; the main
#   track leases BOTH D1+D2 for maximal interface coverage. This is the §11.4.119
#   single-resource-owner partition for hardware, made mechanical.
#
# Deadlock-freedom (the load-bearing anti-bluff claim — proven by the paired
#   stress/chaos test test_multitrack_device_lock.sh). All four Coffman
#   conditions are broken BY CONSTRUCTION:
#     1. mutual-exclusion  — kept (devices ARE exclusive) but bounded:
#     2. hold-and-wait     — ELIMINATED: multi-device acquire is ALL-OR-NOTHING
#                            inside ONE critical section; a track never holds a
#                            partial set while waiting for the rest.
#     3. no-preemption     — RELAXED via lease TTL + heartbeat + reap: a crashed
#                            holder's lease auto-expires (§11.4.147) so a dead
#                            track can NEVER hold the pool hostage forever.
#     4. circular-wait     — ELIMINATED: acquire is NON-BLOCKING — it either wins
#                            the whole set immediately or returns EBUSY at once;
#                            it NEVER waits on a device held by another track, so
#                            no wait-for cycle can form. (Callers retry with
#                            backoff at a HIGHER level, holding nothing.)
#   The only lock ever *held* is a short flock on the registry file, taken solely
#   for the microsecond check-and-claim critical section and released before any
#   device work — and even that flock is bounded (`flock -w`), so it can never
#   hang.
#
# Registry (§11.4.116 real-time sync substrate):
#   MT_LOCK_DIR (default ${XDG_RUNTIME_DIR:-/tmp}/<project>/multitrack/devicelock)
#     events.jsonl        append-only JSONL event stream (ACQUIRE/RELEASE/
#                         HEARTBEAT/REAP/DENY) — never rewritten (§11.4.116).
#     leases.snapshot     current held leases, ATOMICALLY rewritten (temp+rename)
#                         so a lock-free reader never sees a torn write.
#     registry.lock       the flock target for the atomic critical section.
#   Locks are ephemeral runtime state (tmpfs, cleared on reboot) — correct: a
#   lease has no meaning across a host reboot.
#
# Usage:
#   multitrack_device_lock.sh pool
#   multitrack_device_lock.sh status
#   multitrack_device_lock.sh acquire --track <id> \
#         ( --device <id> | --devices <id,id> | --caps <c1,c2> [--count N]
#           | --count N | --policy <name> ) [--ttl SEC] [--pid PID]
#   multitrack_device_lock.sh heartbeat --track <id> [--ttl SEC]
#   multitrack_device_lock.sh release   --track <id> [--device <id>]
#   multitrack_device_lock.sh reap
#   multitrack_device_lock.sh reconcile        # rebuild snapshot from JSONL
#
# Exit codes:  0 = ok · 2 = usage · 3 = EBUSY (requested set not fully free) ·
#              4 = no matching-capability device exists · 1 = internal error.
#
# Inputs:   config/multitrack/<host>.yaml  (device_pool + lease_policy) via
#           multitrack_config.sh mt_load_pool. Env: MT_LOCK_DIR, MT_LOCK_WAIT
#           (flock wait, default 10s), MT_DEFAULT_TTL (default 900s), MT_CONFIG /
#           MT_HOST overrides, MT_HOLDER_PID.
# Outputs:  human-readable lines on stdout; JSONL + snapshot in MT_LOCK_DIR.
# Side-effects:  writes ONLY under MT_LOCK_DIR (never a device, never a disk).
#           Read-only against the physical devices — it coordinates, it does not
#           flash. NEVER touches credentials (§11.4.10).
# Dependencies:  bash, awk, flock, date, mkdir, mv.
# Cross-references:  scripts/multitrack/multitrack_config.sh (device_pool loader);
#                    scripts/multitrack/test_multitrack_device_lock.sh (stress/
#                    chaos + paired mutation, captured evidence);
#                    config/multitrack/<host>.yaml (device_pool/lease_policy);
#                    docs/scripts/multitrack_device_lock.md.
# =============================================================================

set -u

MT_SELF=$0
case "$MT_SELF" in
    */*) MT_DIR=${MT_SELF%/*} ;;
    *)   MT_DIR=. ;;
esac
export MT_SELF

# shellcheck source=scripts/multitrack/multitrack_config.sh
. "$MT_DIR/multitrack_config.sh"

MT_LOCK_DIR=${MT_LOCK_DIR:-${XDG_RUNTIME_DIR:-/tmp}/$(basename "$(mt_repo_root)")/multitrack/devicelock}
MT_LOCK_WAIT=${MT_LOCK_WAIT:-10}
MT_DEFAULT_TTL=${MT_DEFAULT_TTL:-900}
EVENTS="$MT_LOCK_DIR/events.jsonl"
SNAP="$MT_LOCK_DIR/leases.snapshot"
LOCKF="$MT_LOCK_DIR/registry.lock"

_now() { date +%s; }
_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

_ensure_dirs() {
    mkdir -p "$MT_LOCK_DIR" 2>/dev/null || { echo "FATAL: cannot create $MT_LOCK_DIR" >&2; exit 1; }
    [ -e "$EVENTS" ] || : > "$EVENTS"
    [ -e "$SNAP" ]   || : > "$SNAP"
    [ -e "$LOCKF" ]  || : > "$LOCKF"
}

# JSON-safe: strip embedded double-quotes (keeps the JSONL line well-formed).
_jsan() { printf '%s' "${1:-}" | tr '"' "'" ; }

# _event EVENT TRACK DEVICE CAPS EXPIRES NOTE  -> append one JSONL line.
_event() {
    printf '{"ts":%s,"iso":"%s","event":"%s","track":"%s","device":"%s","caps":"%s","expires":"%s","pid":%s,"note":"%s"}\n' \
        "$(_now)" "$(_iso)" "$(_jsan "$1")" "$(_jsan "$2")" "$(_jsan "$3")" \
        "$(_jsan "$4")" "$(_jsan "$5")" "${HOLDER_PID:-0}" "$(_jsan "$6")" >> "$EVENTS"
}

# --- config (device pool + lease policy) -------------------------------------
# §11.4.187 / §11.4.201: "this host declares no physical device pool" is a
# legitimate, extremely common state (default single-track mode; any project
# that is pure software and leases no hardware — note even a fully-configured
# host may carry `device_pool: []`). Treating it as FATAL made every read-only
# device-lock query fail on such a host — a false refusal. An ABSENT config or
# an EMPTY pool now yields an honest EMPTY pool (MT_DEVICE_COUNT=0); only the
# commands that genuinely NEED a device refuse, via _require_pool below.
_load_pool() {
    local host cfg
    host=${MT_HOST:-$(mt_resolve_host)}
    if [ -n "${MT_CONFIG:-}" ]; then
        cfg=$MT_CONFIG
    else
        cfg=$(mt_config_file "$host" 2>/dev/null) || cfg=""
    fi
    if [ -z "$cfg" ]; then
        MT_DEVICE_COUNT=0; export MT_DEVICE_COUNT
        MT_POOL_SOURCE="none (no per-host config for host=$host — default single-track mode)"
        return 0
    fi
    mt_load_pool "$cfg" || { echo "FATAL: device_pool parse failed for $cfg" >&2; exit 1; }
    MT_POOL_SOURCE="$cfg"
}

# Commands that cannot do their job without at least one declared device.
_require_pool() {
    [ "${MT_DEVICE_COUNT:-0}" -ge 1 ] && return 0
    echo "REFUSED: this host declares no device_pool (source: ${MT_POOL_SOURCE:-unknown})." >&2
    echo "  '$1' needs at least one device. Declare a device_pool in the per-host" >&2
    echo "  config, or use a command that does not require a device (pool/status)." >&2
    exit 1
}

# device index -> field lookups
_dev_field() {  # $1 device-id  $2 field(ADB|CAPS|MODEL)
    local i=1 id
    while [ "$i" -le "${MT_DEVICE_COUNT:-0}" ]; do
        eval "id=\${MT_DEVICE_${i}_ID:-}"
        if [ "$id" = "$1" ]; then eval "printf '%s' \"\${MT_DEVICE_${i}_$2:-}\""; return 0; fi
        i=$((i + 1))
    done
    return 1
}
_dev_exists() { _dev_field "$1" ID >/dev/null 2>&1 || _dev_field "$1" ADB >/dev/null 2>&1; }
_all_devices() {
    local i=1 id
    while [ "$i" -le "${MT_DEVICE_COUNT:-0}" ]; do
        eval "id=\${MT_DEVICE_${i}_ID:-}"; [ -n "$id" ] && printf '%s\n' "$id"
        i=$((i + 1))
    done
}

# 0 if device's capabilities include EVERY required cap (space list); 1 otherwise.
_caps_match() {  # $1 device-id  $2 required-caps (space-separated, may be empty)
    local dev=$1 req=$2 have c
    [ -n "$req" ] || return 0
    have=$(_dev_field "$dev" CAPS 2>/dev/null || printf '')
    for c in $req; do
        case " $have " in *" $c "*) : ;; *) return 1 ;; esac
    done
    return 0
}

# --- snapshot helpers (ALL callers hold the flock; writes are atomic) ---------
_reap() {  # drop expired leases; emit REAP events. (inside lock)
    local now tmp dev track pid acq exp caps
    now=$(_now)
    [ -s "$SNAP" ] || return 0
    tmp="$SNAP.tmp.$$"
    : > "$tmp"
    while IFS='|' read -r dev track pid acq exp caps; do
        [ -n "$dev" ] || continue
        if [ "${exp:-0}" -le "$now" ]; then
            _event REAP "$track" "$dev" "$caps" "$exp" "lease-expired-ttl-elapsed"
        else
            printf '%s|%s|%s|%s|%s|%s\n' "$dev" "$track" "$pid" "$acq" "$exp" "$caps" >> "$tmp"
        fi
    done < "$SNAP"
    mv -f "$tmp" "$SNAP"
}

_held_by() {  # $1 device -> prints holding track (empty if free). (post-reap)
    awk -F'|' -v d="$1" '$1==d{print $2; exit}' "$SNAP" 2>/dev/null
}

# 0 if device is free OR already held by TRACK (refresh-eligible).
_free_or_mine() {  # $1 device
    local h; h=$(_held_by "$1")
    [ -z "$h" ] || [ "$h" = "$TRACK" ]
}

# --- request resolution -------------------------------------------------------
# Resolves the flag set into REQ (space-separated device-id list) OR fails.
# ALL-OR-NOTHING: if the required count/caps cannot be fully satisfied from the
# free pool, it fails here (no partial claim ever reaches the snapshot).
_resolve_request() {
    REQ=""
    local d tok n picked count
    if [ -n "${OPT_DEVICE:-}" ]; then
        _dev_exists "$OPT_DEVICE" || { echo "ENODEV: unknown device '$OPT_DEVICE'" >&2; exit 4; }
        REQ=$OPT_DEVICE
        return 0
    fi
    if [ -n "${OPT_DEVICES:-}" ]; then
        for tok in $(printf '%s' "$OPT_DEVICES" | tr ',' ' '); do
            _dev_exists "$tok" || { echo "ENODEV: unknown device '$tok'" >&2; exit 4; }
            REQ="$REQ $tok"
        done
        REQ=$(printf '%s' "$REQ" | sed 's/^ *//')
        return 0
    fi
    if [ -n "${OPT_POLICY:-}" ]; then
        # policy value is a space list of EITHER device ids OR capabilities.
        local pval allids=1
        eval "pval=\${MT_LEASE_${OPT_POLICY}:-}"
        [ -n "$pval" ] || { echo "ENOPOLICY: lease_policy has no '$OPT_POLICY'" >&2; exit 4; }
        for tok in $pval; do _dev_exists "$tok" || allids=0; done
        if [ "$allids" = 1 ]; then REQ=$pval; return 0; fi
        # else: policy tokens are capabilities -> fall through as caps
        OPT_CAPS=$(printf '%s' "$pval" | tr ' ' ',')
    fi
    # capability / count selection from the FREE pool (config order = determinism)
    local reqcaps
    reqcaps=$(printf '%s' "${OPT_CAPS:-}" | tr ',' ' ')
    count=${OPT_COUNT:-1}
    picked=""; n=0
    for d in $(_all_devices); do
        _caps_match "$d" "$reqcaps" || continue
        _free_or_mine "$d" || continue
        picked="$picked $d"; n=$((n + 1))
        [ "$n" -ge "$count" ] && break
    done
    if [ "$n" -lt "$count" ]; then
        # distinguish "no such capability at all" (4) from "all busy" (3)
        local anymatch=0
        for d in $(_all_devices); do _caps_match "$d" "$reqcaps" && anymatch=1; done
        if [ "$anymatch" = 0 ]; then
            echo "ENOCAP: no device in pool has capability set [${OPT_CAPS:-<any>}]" >&2
            exit 4
        fi
        echo "EBUSY: only $n of $count matching device(s) free (caps=[${OPT_CAPS:-<any>}]) — NOT leasing (all-or-nothing)" >&2
        exit 3
    fi
    REQ=$(printf '%s' "$picked" | sed 's/^ *//')
    return 0
}

# --- commands -----------------------------------------------------------------
cmd_pool() {
    _load_pool
    _ensure_dirs
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
        _reap
        local d adb caps holder
        printf 'DEVICE  ADB_SERIAL          HOLDER      CAPS\n'
        for d in $(_all_devices); do
            adb=$(_dev_field "$d" ADB 2>/dev/null || printf '?')
            caps=$(_dev_field "$d" CAPS 2>/dev/null || printf '')
            holder=$(_held_by "$d"); [ -n "$holder" ] || holder='(free)'
            printf '%-7s %-19s %-11s %s\n' "$d" "$adb" "$holder" "$caps"
        done
    ) 9<"$LOCKF"
}

cmd_status() {
    _load_pool
    _ensure_dirs
    # read-only: snapshot is rewritten atomically so a lock-free read is coherent
    _reap_needed=0
    printf '== held leases (%s) ==\n' "$SNAP"
    if [ -s "$SNAP" ]; then
        local now; now=$(_now)
        printf 'DEVICE  TRACK        PID     REMAINING  CAPS\n'
        awk -F'|' -v now="$now" '{ rem=$5-now; if(rem<0)rem=0;
            printf "%-7s %-12s %-7s %-9ss %s\n",$1,$2,$3,rem,$6 }' "$SNAP"
    else
        printf '(none)\n'
    fi
    printf '\n== free devices ==\n'
    local d
    for d in $(_all_devices); do
        awk -F'|' -v d="$d" 'BEGIN{h=0} $1==d{h=1} END{exit h}' "$SNAP" 2>/dev/null && printf '%s ' "$d"
    done
    printf '\n'
}

cmd_acquire() {
    [ -n "${TRACK:-}" ] || { echo "usage: acquire --track <id> ..." >&2; exit 2; }
    _load_pool
    _require_pool acquire
    _ensure_dirs
    local ttl=${OPT_TTL:-$MT_DEFAULT_TTL}
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy (flock timeout)" >&2; exit 1; }
        _reap
        _resolve_request           # sets REQ (all-or-nothing; may exit 3/4)
        # ---- conflict scan (all-or-nothing; NO write on any conflict) --------
        local d holder conflict=0 conflicts=""
        for d in $REQ; do
            holder=$(_held_by "$d")
            # >>MT_LOCK_MUT_DOUBLELEASE (paired §1.1 mutation target — do NOT remove marker)
            if [ -n "$holder" ] && [ "$holder" != "$TRACK" ]; then
                conflict=1; conflicts="$conflicts $d(held-by:$holder)"
            fi
            # <<MT_LOCK_MUT_DOUBLELEASE
        done
        if [ "$conflict" = 1 ]; then
            _event DENY "$TRACK" "$REQ" "${OPT_CAPS:-}" "" "busy:$conflicts"
            echo "EBUSY: cannot acquire for $TRACK —$conflicts (all-or-nothing: nothing leased)" >&2
            exit 3
        fi
        # ---- claim the WHOLE set atomically (single snapshot rewrite) --------
        local now exp caps
        now=$(_now); exp=$((now + ttl))
        {
            [ -s "$SNAP" ] && awk -F'|' -v req=" $REQ " '{ if(index(req," "$1" ")==0) print }' "$SNAP"
            for d in $REQ; do
                caps=$(_dev_field "$d" CAPS 2>/dev/null || printf '')
                printf '%s|%s|%s|%s|%s|%s\n' "$d" "$TRACK" "${HOLDER_PID:-0}" "$now" "$exp" "$caps"
            done
        } > "$SNAP.tmp.$$" && mv -f "$SNAP.tmp.$$" "$SNAP"
        for d in $REQ; do _event ACQUIRE "$TRACK" "$d" "$(_dev_field "$d" CAPS 2>/dev/null)" "$exp" "ttl=$ttl"; done
        printf 'ACQUIRED: %s -> [%s] ttl=%ss expires=%s\n' "$TRACK" "$REQ" "$ttl" "$exp"
        for d in $REQ; do printf '  %s adb_serial=%s\n' "$d" "$(_dev_field "$d" ADB 2>/dev/null)"; done
    ) 9<"$LOCKF"
}

cmd_heartbeat() {
    [ -n "${TRACK:-}" ] || { echo "usage: heartbeat --track <id> [--ttl SEC]" >&2; exit 2; }
    _load_pool; _ensure_dirs
    _require_pool heartbeat
    local ttl=${OPT_TTL:-$MT_DEFAULT_TTL}
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
        _reap
        [ -s "$SNAP" ] || { echo "no leases held by $TRACK (nothing to refresh)"; exit 0; }
        local now exp n
        now=$(_now); exp=$((now + ttl))
        n=$(awk -F'|' -v t="$TRACK" '$2==t{c++} END{print c+0}' "$SNAP")
        awk -F'|' -v t="$TRACK" -v e="$exp" 'BEGIN{OFS="|"} { if($2==t){$5=e} print }' "$SNAP" \
            > "$SNAP.tmp.$$" && mv -f "$SNAP.tmp.$$" "$SNAP"
        _event HEARTBEAT "$TRACK" "" "" "$exp" "refreshed=$n ttl=$ttl"
        printf 'HEARTBEAT: %s refreshed %s lease(s) -> expires=%s\n' "$TRACK" "$n" "$exp"
    ) 9<"$LOCKF"
}

cmd_release() {
    [ -n "${TRACK:-}" ] || { echo "usage: release --track <id> [--device <id>]" >&2; exit 2; }
    _load_pool; _ensure_dirs
    _require_pool release
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: registry busy" >&2; exit 1; }
        _reap
        local d=${OPT_DEVICE:-} n
        n=$(awk -F'|' -v t="$TRACK" -v d="$d" '$2==t && (d==""||$1==d){c++} END{print c+0}' "$SNAP" 2>/dev/null)
        awk -F'|' -v t="$TRACK" -v d="$d" '{ if($2==t && (d==""||$1==d)) next; print }' "$SNAP" \
            > "$SNAP.tmp.$$" 2>/dev/null && mv -f "$SNAP.tmp.$$" "$SNAP"
        _event RELEASE "$TRACK" "$d" "" "" "released=$n"
        printf 'RELEASED: %s freed %s lease(s)%s\n' "$TRACK" "$n" "${d:+ (device $d)}"
    ) 9<"$LOCKF"
}

cmd_reap() {
    _load_pool; _ensure_dirs

    _require_pool reap
    ( flock -w "$MT_LOCK_WAIT" 9 || exit 1; _reap; echo "REAP: stale leases expired (see events.jsonl)"; ) 9<"$LOCKF"
}

cmd_reconcile() {
    # Rebuild the snapshot from the append-only JSONL (§11.4.116 recovery path):
    # replay events in order, keeping the last ACQUIRE/HEARTBEAT per device and
    # dropping RELEASE/REAP'd devices; then reap expired.
    _load_pool; _ensure_dirs
    _require_pool reconcile
    ( flock -w "$MT_LOCK_WAIT" 9 || exit 1
      awk -F'"' '
        # crude JSONL field pluck by key (values are simple, no nested quotes)
        function val(line,key,   re,a){ re="\""key"\":\""; if(match(line,re)){ s=substr(line,RSTART+length(re)); q=index(s,"\""); return substr(s,1,q-1)} return "" }
        function num(line,key,   re,s,i,d){ re="\""key"\":"; if(match(line,re)){ s=substr(line,RSTART+length(re)); d=""; for(i=1;i<=length(s);i++){c=substr(s,i,1); if(c ~ /[0-9]/) d=d c; else break} return d} return "" }
        {
          ev=val($0,"event"); dev=val($0,"device"); tr=val($0,"track"); caps=val($0,"caps"); exp=num($0,"expires"); pid=num($0,"pid"); ts=num($0,"ts")
          if(ev=="ACQUIRE"){ hold[dev]=tr; e[dev]=exp; c[dev]=caps; p[dev]=pid; a[dev]=ts }
          else if(ev=="HEARTBEAT"){ for(d in hold) if(hold[d]==tr) e[d]=exp }
          else if(ev=="RELEASE"){ if(dev!=""){ delete hold[dev] } else { for(d in hold) if(hold[d]==tr) delete hold[d] } }
          else if(ev=="REAP"){ if(dev!="") delete hold[dev] }
        }
        END{ for(d in hold) if(d!="") printf "%s|%s|%s|%s|%s|%s\n", d, hold[d], p[d], a[d], e[d], c[d] }
      ' "$EVENTS" > "$SNAP.tmp.$$" && mv -f "$SNAP.tmp.$$" "$SNAP"
      _reap
      echo "RECONCILE: snapshot rebuilt from $EVENTS"
    ) 9<"$LOCKF"
}

# --- CLI ----------------------------------------------------------------------
usage() { sed -n '38,52p' "$MT_SELF" 2>/dev/null | sed 's/^# \{0,1\}//'; }

[ $# -ge 1 ] || { usage >&2; exit 2; }
CMD=$1; shift

TRACK=""; OPT_DEVICE=""; OPT_DEVICES=""; OPT_CAPS=""; OPT_COUNT=""
OPT_POLICY=""; OPT_TTL=""; HOLDER_PID=${MT_HOLDER_PID:-$PPID}
while [ $# -gt 0 ]; do
    case "$1" in
        --track)   TRACK=$2; shift ;;
        --track=*) TRACK=${1#--track=} ;;
        --device)   OPT_DEVICE=$2; shift ;;
        --device=*) OPT_DEVICE=${1#--device=} ;;
        --devices)   OPT_DEVICES=$2; shift ;;
        --devices=*) OPT_DEVICES=${1#--devices=} ;;
        --caps)   OPT_CAPS=$2; shift ;;
        --caps=*) OPT_CAPS=${1#--caps=} ;;
        --count)   OPT_COUNT=$2; shift ;;
        --count=*) OPT_COUNT=${1#--count=} ;;
        --policy)   OPT_POLICY=$2; shift ;;
        --policy=*) OPT_POLICY=${1#--policy=} ;;
        --ttl)   OPT_TTL=$2; shift ;;
        --ttl=*) OPT_TTL=${1#--ttl=} ;;
        --pid)   HOLDER_PID=$2; shift ;;
        --pid=*) HOLDER_PID=${1#--pid=} ;;
        --help|-h) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

case "$CMD" in
    pool)      cmd_pool ;;
    status)    cmd_status ;;
    acquire)   cmd_acquire ;;
    heartbeat) cmd_heartbeat ;;
    release)   cmd_release ;;
    reap)      cmd_reap ;;
    reconcile) cmd_reconcile ;;
    --help|-h|help) usage ;;
    *) echo "unknown command: $CMD" >&2; usage >&2; exit 2 ;;
esac
