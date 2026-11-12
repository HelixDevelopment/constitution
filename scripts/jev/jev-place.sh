#!/usr/bin/env bash
# jev-place.sh — capacity-gated LOCAL decision-model placement producer (§11.4.291, stream S4, 2026-11-12).
#
# Reads `llmctl capacity --json` under the §11.4.291(C) contract table, keeps a per-user lease set per profile, starts
# the best fitting systemone-native decide profile ON DEMAND (a session acquires a lease), registers the local gateway in
# the decision-endpoint cache at priority 10, and stops the model when the LAST lease is released (only a model THIS
# producer started). It never calls `llmctl enable`, `disable`, `switch` or `auto`; every llmctl call is time-bounded.
#
# Usage:
#   jev-place.sh verdict  [--json]               capacity verdict per candidate profile (read-only, no start)
#   jev-place.sh acquire  <holder> [--pid P] [--ttl S]   take a lease; start a fitting profile if none is running
#   jev-place.sh heartbeat <holder>              refresh a lease
#   jev-place.sh release  <holder>               drop a lease; the last release stops a constitution-started model
#   jev-place.sh reap                            drop leases whose holder pid is dead or whose heartbeat expired
#   jev-place.sh status   [--json]               lease sets + last placement entry
# Exit codes: 0 done; 2 usage / cannot determine (jq absent); 4 lease lock timeout (no lease taken: caller falls back);
#             5 no local placement (verdict not fits / undetermined / start refused): the placement entry names the
#               fallback route (cloud when a non-placeholder hosted key exists, else none).
# Env (names only):
#   JEV_LLMCTL_BIN (default llmctl), JEV_LLMCTL_TIMEOUT (default 20 s, read calls), JEV_LLMCTL_START_TIMEOUT (default 300 s),
#   JEV_PLACE_PROFILES (comma list: candidate order; default = every systemone-native decide profile in llmctl order),
#   JEV_PLACE_MAX (instances to start per acquire, default 1), JEV_LEASE_TTL (default 900 s; must exceed the
#   re-evaluation cadence + the llmctl timeout, §11.4.291(J)), JEV_LOCK_TIMEOUT (default 10 s),
#   JEV_STATE_DIR / JEV_HOME (state), CMA_PROVIDERS_DIR (endpoint cache dir), LLMCTL_GATEWAY_URL (default from
#   `llmctl decide status --json` registry), JEV_NOW_EPOCH (clock seam, ONLY with JEV_TEST=1).
# Verdicts (§11.4.291(A)): fits | fits_with_reduced_threads | does_not_fit | undetermined. undetermined is NEVER fits.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_decide.sh
. "$SCRIPT_DIR/lib_decide.sh"
# shellcheck source=lib_keys.sh
. "$SCRIPT_DIR/lib_keys.sh"
command -v jq >/dev/null 2>&1 || { echo "jev-place: jq is required (cannot determine)" >&2; exit 2; }

STATE="$(jev_state_dir)"; mkdir -p "$STATE"
LEASES="$STATE/leases.json"; LOCK="$STATE/placement.lock"; PLACEMENT="$STATE/placement.json"
DETECTION="$(jev_detection_file)"
CACHE="$(jev_providers_dir)/jev-endpoints.json"
LLMCTL="${JEV_LLMCTL_BIN:-llmctl}"
RTMO="${JEV_LLMCTL_TIMEOUT:-20}"; STMO="${JEV_LLMCTL_START_TIMEOUT:-300}"
TTL_DEFAULT="${JEV_LEASE_TTL:-900}"; LOCK_TMO="${JEV_LOCK_TIMEOUT:-10}"; MAXN="${JEV_PLACE_MAX:-1}"
NOW="$(date +%s)"; [ "${JEV_TEST:-}" != "1" ] || NOW="${JEV_NOW_EPOCH:-$NOW}"
for n in "$RTMO" "$STMO" "$TTL_DEFAULT" "$LOCK_TMO" "$MAXN"; do case "$n" in ''|*[!0-9]*) echo "jev-place: numeric setting expected, got '$n'" >&2; exit 2 ;; esac; done
log() { printf '[jev-place] %s\n' "$*" >&2; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

bounded() { # bounded <seconds> <out> cmd... -> rc of cmd (124/137 on timeout)
  local t="$1" o="$2" rc=0; shift 2
  timeout --kill-after=2 "$t" "$@" >"$o" 2>"$o.err" </dev/null || rc=$?
  return "$rc"
}

# ---- §11.4.291(C) contract table: schema llmctl.capacity/1 -------------------------------------------------
# capacity_read -> writes $WORK/cap.json and prints "ok" or "undetermined\t<reason>"
capacity_read() {
  local rc=0
  bounded "$RTMO" "$WORK/cap.raw" "$LLMCTL" capacity --json || rc=$?
  case "$rc" in 0|75|3) ;; 124|137) printf 'undetermined\tllmctl capacity timed out after %ss\n' "$RTMO"; return 0 ;;
    *) printf 'undetermined\tllmctl capacity exit %s (not an answer code 0/75/3)\n' "$rc"; return 0 ;; esac
  if ! jq -e . "$WORK/cap.raw" >"$WORK/cap.json" 2>/dev/null; then printf 'undetermined\tunparseable capacity output\n'; return 0; fi
  local miss
  miss="$(jq -r '[ (if .schema != "llmctl.capacity/1" then "schema" else empty end),
                   (if (.time|type) != "number" then "time" else empty end),
                   (if (.profiles|type) != "object" then "profiles" else empty end),
                   (if (.host.mem_total_mb|type) != "number" or (.host.mem_available_mb|type) != "number" or (.host.usable_mem_mb|type) != "number" then "host.mem" else empty end),
                   (if (.reserve|type) != "object" then "reserve" else empty end),
                   (if (.pressure|type) != "object" then "pressure" else empty end),
                   (if (.llmctl.units|type) != "array" then "llmctl.units" else empty end),
                   (if ((.fallback.recommended // "") | IN("local","cloud","none")) | not then "fallback.recommended" else empty end),
                   (if (.unknown_profiles|type) != "array" then "unknown_profiles" else empty end) ] | join(",")' "$WORK/cap.json")"
  if [ -n "$miss" ]; then printf 'undetermined\tcontract fields missing or wrong: %s\n' "$miss"; return 0; fi
  echo ok
}

# candidate profiles: systemone-native decide profiles (decide capacity protocol), in order (JEV_PLACE_PROFILES wins)
candidates() {
  if [ -n "${JEV_PLACE_PROFILES:-}" ]; then printf '%s\n' "${JEV_PLACE_PROFILES//,/$'\n'}"; return 0; fi
  local rc=0
  bounded "$RTMO" "$WORK/dcap.raw" "$LLMCTL" decide capacity --json || rc=$?
  [ "$rc" = 0 ] || return 0
  jq -r '(.decision_instances // {}) | to_entries[] | select(.value.protocol == "systemone-native") | .key' "$WORK/dcap.raw" 2>/dev/null || true
}

# verdict_for <profile> -> "<verdict>\t<threads>\t<reason>" (contract-checked; undetermined never reads as fits)
verdict_for() {
  local p="$1"
  jev_profile_name_ok "$p" || { printf 'undetermined\t0\tinvalid profile name\n'; return 0; }
  jq -r --arg p "$p" '
    (.profiles[$p] // null) as $e
    | (.host.nproc.headroom // null) as $np
    | ([.llmctl.units[]? | select(((.profile // .name // "") | sub("^llmctl-[a-z]+@";"")) == $p) | (.status // .state // "")] | first // "") as $us
    | if (.unknown_profiles | index($p)) then "undetermined\t0\tunknown profile"
      elif $e == null then "undetermined\t0\tprofile absent from capacity output"
      elif (($e.verdict // "") | IN("fits","fits_with_reduced_threads","does_not_fit")) | not then "undetermined\t0\tverdict outside the closed set"
      elif ($e.threads|type) != "number" or ($e.reasons|type) != "array" then "undetermined\t0\tthreads/reasons missing"
      elif $us == "degraded" then "does_not_fit\t\($e.threads)\tunit degraded"
      elif $e.verdict != "does_not_fit" and (($np|type) != "number") then "undetermined\t\($e.threads)\tRLIMIT_NPROC headroom not measured"
      elif $e.verdict != "does_not_fit" and $np < $e.threads then "does_not_fit\t\($e.threads)\tnproc headroom \($np) < threads"
      elif (.pressure.ok == false) and $e.verdict != "does_not_fit" then "does_not_fit\t\($e.threads)\tpressure: \((.pressure.reasons // []) | join("; "))"
      else "\($e.verdict)\t\($e.threads)\t\(($e.reasons // []) | join("; "))" end' "$WORK/cap.json"
}

# unit_status_of <profile> -> the llmctl unit status the capacity answer reports for it ("" when none)
unit_status_of() {
  jq -r --arg p "$1" '[.llmctl.units[]? | select(((.profile // .name // "") | sub("^llmctl-[a-z]+@";"")) == $p) | (.status // .state // "")] | first // ""' "$WORK/cap.json" 2>/dev/null || true
}

hosted_key_var() { local v; for v in TYPESAFE_API_KEY OPENROUTER_API_KEY; do [ "$(key_state "$v" | cut -f1)" = real ] && { echo "$v"; return 0; }; done; return 0; }

write_placement() { # write_placement <profile> <verdict> <reason> <route> <started> <threads>
  local kv; kv="$(hosted_key_var)"
  jq -nc --arg p "$1" --arg v "$2" --arg r "$3" --arg route "$4" --argjson st "$5" --arg th "${6:-0}" --arg kv "$kv" --argjson now "$NOW" \
     --slurpfile cap <(jq -c '{host:{mem_total_mb:.host.mem_total_mb, mem_available_mb:.host.mem_available_mb, usable_mem_mb:.host.usable_mem_mb, load:.host.load, nproc_headroom:(.host.nproc.headroom // null)}, reserve:{mem_reserved_mb:.reserve.mem_reserved_mb, cpus_reserved:.reserve.cpus_reserved}, pressure:.pressure, time:.time}' "$WORK/cap.json" 2>/dev/null || echo '{}') \
     '{placement:{profile:$p, verdict:$v, reason:$r, route:$route, key_variable:(if $route=="cloud" then $kv else null end), constitution_started:$st, threads:($th|tonumber? // 0),
                 inputs:($cap[0] // {}), source:"llmctl capacity --json (schema llmctl.capacity/1)", evaluated_at:$now}}' > "$WORK/pl.json"
  jev_write_atomic "$PLACEMENT" < "$WORK/pl.json"
  if [ -f "$DETECTION" ]; then
    jq -c --slurpfile pl "$WORK/pl.json" '. + $pl[0]' "$DETECTION" > "$WORK/det.json" 2>/dev/null && jev_write_atomic "$DETECTION" < "$WORK/det.json" || true
  fi
}

fallback_route() { if [ -n "$(hosted_key_var)" ]; then echo cloud; else echo none; fi; }

gateway_url() {
  if [ -n "${LLMCTL_GATEWAY_URL:-}" ]; then printf '%s\t%s\n' "$LLMCTL_GATEWAY_URL" "${LLMCTL_CACERT:-}"; return 0; fi
  local rc=0
  bounded "$RTMO" "$WORK/st.raw" "$LLMCTL" decide status --json || rc=$?
  [ "$rc" = 0 ] || { printf 'https://127.0.0.1:8095\t\n'; return 0; }
  jq -r '[.registry.services[]? | select((.labels.kind // "") == "gateway")][0] as $g | "\($g.url // "https://127.0.0.1:8095")\t\($g.labels.ca_file // "")"' "$WORK/st.raw" 2>/dev/null || printf 'https://127.0.0.1:8095\t\n'
}

cache_register() { # cache_register <profile> : add/replace the llmctl-local entry at priority 10
  local u ca; IFS=$'\t' read -r u ca < <(gateway_url)
  mkdir -p "$(dirname "$CACHE")"
  [ -f "$CACHE" ] || jq -n '{version:1, generated_at:0, ttl:300, endpoints:[]}' > "$CACHE"
  jq -c --arg u "$u" --arg ca "$ca" --arg p "$1" --argjson now "$NOW" '
    .endpoints = ([.endpoints[]? | select(.provider_id != "llmctl-local")]
      + [{provider_id:"llmctl-local", base_url:$u, model:$p, key_var:"LLMCTL_API_KEY", ca_file:$ca, priority:10, probed_at:$now,
          reason:"local placement lease (scripts/jev/jev-place.sh, §11.4.291)"}] | sort_by(.priority // 100))' "$CACHE" > "$WORK/cache.json"
  jev_write_atomic "$CACHE" < "$WORK/cache.json"
}
cache_unregister() {
  [ -f "$CACHE" ] || return 0
  jq -c '.endpoints = [.endpoints[]? | select(.provider_id != "llmctl-local")]' "$CACHE" > "$WORK/cache.json" && jev_write_atomic "$CACHE" < "$WORK/cache.json"
}

leases_load() { [ -s "$LEASES" ] && jq -e . "$LEASES" >/dev/null 2>&1 && cat "$LEASES" || echo '{"sets":{}}'; }
leases_save() { jev_write_atomic "$LEASES"; }

holder_alive() { # holder_alive <pid> <heartbeat_at> <ttl>
  local pid="$1" hb="$2" ttl="$3"
  if [ -n "$pid" ] && [ "$pid" != "null" ]; then
    kill -0 "$pid" 2>/dev/null || return 1
    # a /proc file reports size 0, so read it: an empty cmdline is a zombie or a kernel thread, not a session holder
    if [ -d /proc ]; then [ -n "$(head -c 64 "/proc/$pid/cmdline" 2>/dev/null | tr -d '\0')" ] || return 1; fi
    return 0
  fi
  [ $(( NOW - hb )) -le "$ttl" ]
}

reap_locked() { # drops dead holders from every set (caller holds the lock); never stops a model
  # every loop variable is local: bash scoping is dynamic, so a bare `read pid ttl` here would clear the CALLER's pid/ttl
  local cur out prof h pid hb ttl; cur="$(leases_load)"; out="$cur"
  while IFS=$'\t' read -r prof h pid hb ttl; do
    [ -n "$prof" ] || continue
    if ! holder_alive "$pid" "$hb" "$ttl"; then
      log "reaped dead lease holder=$h profile=$prof"
      out="$(jq -c --arg p "$prof" --arg h "$h" '.sets[$p].leases |= map(select(.holder != $h))' <<<"$out")"
    fi
  done < <(jq -r '.sets | to_entries[] | .key as $p | .value.leases[]? | [$p, .holder, (.pid // "null" | tostring), .heartbeat_at, .ttl] | @tsv' <<<"$cur")
  # a stale `stopping` mark (stopper dead or older than the stop timeout) is cleared (§11.4.291(J))
  out="$(jq -c --argjson now "$NOW" --argjson st "$STMO" '.sets |= with_entries(if (.value.stopping // null) != null and ($now - .value.stopping.at) > ($st + 30) then .value.stopping = null else . end)' <<<"$out")"
  [ "$out" = "$cur" ] || printf '%s\n' "$out" | leases_save
}

with_lock() { # with_lock <fn> args... -> rc 4 on lock timeout
  exec 9>>"$LOCK"
  if ! flock -w "$LOCK_TMO" 9; then exec 9>&-; return 4; fi
  local rc=0; "$@" || rc=$?
  flock -u 9; exec 9>&-
  return "$rc"
}

cmd_verdict() {
  local json="${1:-}" st reason p line first=1
  IFS=$'\t' read -r st reason < <(capacity_read)
  {
    printf '['
    if [ "$st" = ok ]; then
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        line="$(verdict_for "$p")"
        [ "$first" = 1 ] || printf ','; first=0
        jq -nc --arg p "$p" --arg l "$line" '($l|split("\t")) as $f | {profile:$p, verdict:$f[0], threads:($f[1]|tonumber? // 0), reason:($f[2] // "")}'
      done < <(candidates)
    fi
    printf ']'
  } > "$WORK/v.json"
  if [ "$json" = "--json" ]; then jq -c --arg st "$st" --arg r "${reason:-}" '{contract:$st, contract_reason:$r, candidates:.}' "$WORK/v.json"
  else
    [ "$st" = ok ] || log "capacity contract: undetermined ($reason) - no local start"
    jq -r '.[] | "\(.profile)\t\(.verdict)\tthreads=\(.threads)\t\(.reason)"' "$WORK/v.json"
  fi
}

acquire_locked() {
  local holder="$1" pid="$2" ttl="$3" cur prof st reason line v th r us started=0 n=0
  reap_locked
  cur="$(leases_load)"
  # an existing, non-stopping set (or a constitution-started model whose holders were reaped): join it, no second start
  prof="$(jq -r '[.sets | to_entries[] | select((.value.stopping // null) == null and ((.value.leases | length) > 0 or .value.constitution_started == true)) | .key][0] // empty' <<<"$cur")"
  if [ -n "$prof" ]; then
    cur="$(jq -c --arg p "$prof" --arg h "$holder" --arg pid "$pid" --argjson now "$NOW" --argjson ttl "$ttl" \
      '.sets[$p].leases = ([.sets[$p].leases[] | select(.holder != $h)] + [{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), heartbeat_at:$now, ttl:$ttl}])' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    log "lease joined: holder=$holder profile=$prof"
    echo "$prof"; return 0
  fi
  if jq -e '[.sets[] | select((.stopping // null) != null)] | length > 0' <<<"$cur" >/dev/null; then
    write_placement "" "undetermined" "a lease set is stopping (refused per §11.4.291(J))" "$(fallback_route)" false 0
    log "refused: a lease set is stopping; fallback route $(fallback_route)"; return 5
  fi
  IFS=$'\t' read -r st reason < <(capacity_read)
  if [ "$st" != ok ]; then
    write_placement "" "undetermined" "$reason" "$(fallback_route)" false 0
    log "undetermined ($reason): no local start; fallback route $(fallback_route)"; return 5
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$n" -lt "$MAXN" ] || break
    line="$(verdict_for "$p")"; IFS=$'\t' read -r v th r <<<"$line"
    # A unit llmctl already runs was started by someone else (the operator, or a session outside this lease
    # registry): join it as NOT constitution-started, so the last release never stops it (§11.4.291(J)).
    # A unit still starting is neither started again nor claimed.
    us="$(unit_status_of "$p")"
    case "$us" in
      running|active)
        cur="$(jq -c --arg p "$p" --arg h "$holder" --arg pid "$pid" --argjson now "$NOW" --argjson ttl "$ttl" \
          '.sets[$p] = {constitution_started:false, stopping:null, leases:[{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), heartbeat_at:$now, ttl:$ttl}]}' <<<"$cur")"
        printf '%s\n' "$cur" | leases_save
        write_placement "$p" "$v" "already running (not started by the constitution)" local false "$th"
        cache_register "$p"
        log "joined the already-running unit $p (not constitution-started; it is never stopped by this producer)"
        echo "$p"; return 0 ;;
      starting|activating) log "candidate $p: unit is $us; not started a second time"; continue ;;
    esac
    case "$v" in fits|fits_with_reduced_threads) ;; *) log "candidate $p: $v ($r)"; continue ;; esac
    local src=0
    bounded "$STMO" "$WORK/start.out" "$LLMCTL" start "$p" || src=$?
    if [ "$src" = 0 ]; then
      started=1; n=$((n+1)); prof="${prof:-$p}"
      cur="$(jq -c --arg p "$p" --arg h "$holder" --arg pid "$pid" --argjson now "$NOW" --argjson ttl "$ttl" \
        '.sets[$p] = {constitution_started:true, started_at:$now, stopping:null, leases:[{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), heartbeat_at:$now, ttl:$ttl}]}' <<<"$cur")"
      printf '%s\n' "$cur" | leases_save
      write_placement "$p" "$v" "$r" local true "$th"
      cache_register "$p"
      log "started $p ($v, threads=$th); lease holder=$holder; local gateway registered at priority 10"
    elif [ "$src" = 75 ]; then
      log "llmctl start $p refused (75): does_not_fit"
    else
      log "llmctl start $p failed rc=$src: $(head -c 300 "$WORK/start.out.err" 2>/dev/null | tr '\n' ' ')"
      # Live T5 (2026-11-12): llmctl can fail AFTER the unit began starting (health not answered in time, or our own
      # bound expired). The unit was not running before (checked above), so this producer started it: stopping it
      # again is the only way it is not left behind with no lease. 75 (pressure gate, no partial start) needs nothing.
      log "start of $p failed after it was requested; stopping it again so no unit is left without a lease"
      bounded "$STMO" "$WORK/stop.out" "$LLMCTL" stop "$p" || log "cleanup stop of $p failed rc=$?; check: llmctl status"
    fi
  done < <(candidates)
  if [ "$started" = 1 ]; then echo "$prof"; return 0; fi
  write_placement "" "does_not_fit" "no candidate profile fits or started" "$(fallback_route)" false 0
  log "no local placement; fallback route $(fallback_route)"; return 5
}

release_locked() {
  local holder="$1" cur prof
  reap_locked
  cur="$(leases_load)"
  cur="$(jq -c --arg h "$holder" '.sets |= map_values(.leases |= map(select(.holder != $h)))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  # last lease of a constitution-started set: mark stopping (others refuse), then stop OUTSIDE the lock
  prof="$(jq -r '[.sets | to_entries[] | select((.value.leases | length) == 0 and (.value.constitution_started == true) and (.value.stopping // null) == null) | .key][0] // empty' <<<"$cur")"
  if [ -n "$prof" ]; then
    cur="$(jq -c --arg p "$prof" --argjson now "$NOW" --arg pid "$$" '.sets[$p].stopping = {at:$now, pid:($pid|tonumber)}' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    echo "$prof"
  fi
  # an empty set this producer did not start is just forgotten (an operator-started model is never stopped)
  cur="$(jq -c '.sets |= with_entries(select((.value.leases | length) > 0 or .value.constitution_started == true))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
}
finish_stop_locked() { # finish_stop_locked <profile> <stop-rc>
  local cur; cur="$(leases_load)"
  cur="$(jq -c --arg p "$1" 'del(.sets[$p])' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  cache_unregister
  write_placement "$1" "stopped" "last lease released; llmctl stop rc=$2" "$(fallback_route)" false 0
}

sub="${1:-}"; shift || true
case "$sub" in
  verdict) cmd_verdict "${1:-}" ;;
  acquire)
    holder="${1:-}"; shift || true; pid=""; ttl="$TTL_DEFAULT"
    jev_check_word "$holder" || { echo "jev-place: acquire needs a holder id ([A-Za-z0-9._-]+)" >&2; exit 2; }
    while [ $# -gt 0 ]; do case "$1" in --pid) pid="${2:-}"; shift 2 ;; --ttl) ttl="${2:-}"; shift 2 ;; *) echo "jev-place: unknown arg $1" >&2; exit 2 ;; esac; done
    case "$pid$ttl" in *[!0-9]*) echo "jev-place: --pid/--ttl must be integers" >&2; exit 2 ;; esac
    rc=0; with_lock acquire_locked "$holder" "$pid" "$ttl" || rc=$?
    if [ "$rc" = 4 ]; then write_placement "" "undetermined" "lease_lock_timeout" "$(fallback_route)" false 0 2>/dev/null || true; log "lease_lock_timeout: no lease taken"; fi
    exit "$rc" ;;
  heartbeat)
    holder="${1:-}"; jev_check_word "$holder" || { echo "jev-place: heartbeat needs a holder id" >&2; exit 2; }
    hb() { local c; c="$(leases_load)"; c="$(jq -c --arg h "$1" --argjson now "$NOW" '.sets |= map_values(.leases |= map(if .holder == $h then .heartbeat_at = $now else . end))' <<<"$c")"; printf '%s\n' "$c" | leases_save; }
    with_lock hb "$holder" ;;
  release)
    holder="${1:-}"; jev_check_word "$holder" || { echo "jev-place: release needs a holder id" >&2; exit 2; }
    rc=0; stopprof="$(with_lock release_locked "$holder")" || rc=$?
    [ "$rc" = 0 ] || { log "release: lock timeout (rc $rc)"; exit "$rc"; }
    if [ -n "$stopprof" ]; then
      src=0; bounded "$RTMO" "$WORK/stop.out" "$LLMCTL" stop "$stopprof" || src=$?
      log "last lease released: llmctl stop $stopprof rc=$src"
      with_lock finish_stop_locked "$stopprof" "$src" || true
    fi ;;
  reap) with_lock reap_locked ;;
  status)
    if [ "${1:-}" = "--json" ]; then jq -nc --slurpfile l <(leases_load) --slurpfile p <( [ -f "$PLACEMENT" ] && cat "$PLACEMENT" || echo '{}') '{leases:$l[0], placement:($p[0].placement // null)}'
    else leases_load | jq -r '.sets | to_entries[] | "\(.key): leases=\(.value.leases|length) constitution_started=\(.value.constitution_started) stopping=\(.value.stopping != null)"'
      [ -f "$PLACEMENT" ] && jq -r '.placement | "placement: profile=\(.profile) verdict=\(.verdict) route=\(.route) reason=\(.reason)"' "$PLACEMENT"; fi ;;
  ""|-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; [ -n "$sub" ] && exit 0 || exit 2 ;;
  enable|disable|switch|auto) echo "jev-place: '$sub' is never run by the constitution (§11.4.291(G))" >&2; exit 2 ;;
  *) echo "jev-place: unknown subcommand '$sub'" >&2; exit 2 ;;
esac
