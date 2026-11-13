#!/usr/bin/env bash
# jev-place.sh — capacity-gated LOCAL decision-model placement producer (§11.4.291, stream S4, 2026-11-12).
#
# Reads `llmctl capacity --json` under the §11.4.291(C) contract table, keeps a per-user lease set per profile, starts
# the best fitting systemone-native decide profile ON DEMAND (a session acquires a lease), registers the local gateway in
# the decision-endpoint cache at priority 10, and stops the model when the LAST lease is released (only a model THIS
# producer started). It never calls `llmctl enable`, `disable`, `switch` or `auto`; every llmctl call is time-bounded.
#
# Usage:
#   jev-place.sh verdict  [--json]               placement state + verdict per candidate profile (read-only, no start)
#   jev-place.sh acquire  <holder> [--pid P] [--ttl S]   take a lease; start a fitting profile if none is running
#   jev-place.sh heartbeat <holder>              refresh a lease
#   jev-place.sh release  <holder>               drop a lease; the last release stops EVERY constitution-started model
#                                                with no lease left (bounded by the start/stop timeout)
#   jev-place.sh reap                            drop leases whose holder pid is dead or whose heartbeat expired
#   jev-place.sh status   [--json]               lease sets + last placement entry
# Exit codes: 0 done; 2 usage / cannot determine (jq absent); 4 lease lock timeout (no lease taken: caller falls back);
#             5 no local placement (no fit / undetermined / start refused / join refused): the placement entry names the
#               fallback route (cloud when a non-placeholder hosted key exists, else none);
#             6 release: an `llmctl stop` failed or timed out. The lease set is KEPT (constitution_started, stopping
#               mark, stop_failed {at, rc}); once the stop mark is cleared (stopper process gone, or older than the stop
#               timeout + 30 s) the next release retries the stop, and the next acquire judges the set like any other
#               lease-less set (joined when its unit is `ok`, stopped when it is degraded or gone). Never orphaned.
# Env (names only):
#   JEV_LLMCTL_BIN (default llmctl), JEV_LLMCTL_TIMEOUT (default 20 s, read calls), JEV_LLMCTL_START_TIMEOUT (default 300 s,
#   start and stop), JEV_PLACE_PROFILES (comma list: candidate order; default = every systemone-native decide profile in
#   llmctl order), JEV_PLACE_MAX (instances to start per acquire, default 1), JEV_LEASE_TTL (default 900 s; must exceed
#   the re-evaluation cadence + the llmctl timeout, §11.4.291(J)), JEV_LOCK_TIMEOUT (default 10 s), LLMCTL_TENANT_ID (the
#   tenant key llmctl puts in front of its own unit names), JEV_STATE_DIR / JEV_HOME (state), CMA_PROVIDERS_DIR (endpoint
#   cache dir), LLMCTL_GATEWAY_URL (default from `llmctl decide status --json` registry), JEV_NOW_EPOCH (clock seam, ONLY
#   with JEV_TEST=1).
#
# Round 5 (structural, review R4-1 to R4-3; ground truth docs/qa/jev_s3s4_20261112/round5/ground_truth.md):
# * THE CAPACITY ANSWER (§11.4.291(A)(C), pinned llmctl lib/capacity.sh): a running profile has verdict `running` and is
#   judged by the status of its OWN unit (owner `self`, unit profile = <LLMCTL_TENANT_ID>--<p> or <p>), which is exactly
#   `ok` or `degraded`. Every candidate gets ONE instance state (inst_state):
#     ok        running, own unit ok        -> joined (an existing lease set, also a lease-less constitution-started one)
#                                              or adopted as operator-started (no set); never stopped by an acquire
#     degraded  running, own unit degraded  -> does_not_fit for that instance: never joined or adopted; a lease-less
#                                              constitution-started set is stopped (§11.4.291(D)(1))
#     absent    fits / fits_with_reduced_threads / does_not_fit and no own unit -> a start candidate when it fits and
#                                              the RLIMIT_NPROC headroom and pressure checks pass; a lease-less
#                                              constitution-started set whose unit is gone is stopped and dropped
#     unknown   anything else (verdict undetermined or outside the set, running without an own unit, an own unit next
#               to a non-running verdict, a unit status outside ok/degraded) -> nothing is started, joined or stopped
# * NO llmctl CALL UNDER THE LEASE LOCK (R4-3): the capacity answer, the candidate list and the gateway URL are read
#   before the lock; a set that needs an llmctl stop or start is MARKED under the lock (`stopping` / `starting`, naming
#   this process), the call runs with the lock released, and the result is recorded under the lock again. A heartbeat,
#   release or acquire of another session therefore only ever waits for local file updates. A `starting` mark is
#   cleared like a `stopping` mark (starter gone, or older than the stop timeout + 30 s). A set that is starting or
#   stopping refuses a new acquire (event refused_starting / refused_stopping, §11.4.291(J)). When the lease file
#   changed between the capacity read and the lock, the answer is read again (at most 3 times).
# * ONE STOP HELPER (R4-1): every `llmctl stop` (last release, disposal, retry of an owed stop, cleanup after a failed
#   start) goes through do_stop -> finish_stop_locked, which drops the set on success and normalises the endpoint cache:
#   the single llmctl-local entry names a held, healthy lease set or is removed (cache_normalize); it never names a
#   stopped model. finish_stop_locked also writes the placement record. After a successful stop the acquire reads the
#   capacity answer again before it decides on a start.
# Verdicts (§11.4.291(A)): fits | fits_with_reduced_threads | does_not_fit | undetermined (or null when no capacity
# verdict applies: a join of a running instance, a stop). undetermined is NEVER fits. What HAPPENED is in the separate
# `event` field, closed set: placed | joined | joined_running | no_fit | undetermined | start_failed | start_refused |
# refused_stopping | refused_starting | refused_degraded | refused_join | lease_lock_timeout | stopped | stop_failed
# (write_placement refuses any other value).
# Failed start: when `llmctl start` fails (not 75) the producer stops the unit again; when that cleanup stop fails too it
# keeps a set {constitution_started:true, leases:[], start_failed, stop_failed}: never joined, never adopted as
# operator-started and never started again; every later acquire and release retries the stop. A failed disposal stop
# keeps {stop_owed, stop_failed} the same way. A reap alone never stops a model (§11.4.291(J)).
# Stop mark: a mark that names no pid (older state format) is never treated as a dead stopper; it is cleared only when it
# is older than the stop timeout + 30 s.
# Holder identity: a --pid holder records its process start time (/proc/<pid>/stat field 22); it is alive while
# /proc/<pid> exists, its start time matches and its cmdline is non-empty (a reused pid is dead). Without /proc the
# holder is alive while `kill -0` succeeds AND its heartbeat is within its TTL. A pid-less holder lives by its TTL.
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
TENANT="${LLMCTL_TENANT_ID:-}"
NOW="$(date +%s)"; [ "${JEV_TEST:-}" != "1" ] || NOW="${JEV_NOW_EPOCH:-$NOW}"
for n in "$RTMO" "$STMO" "$TTL_DEFAULT" "$LOCK_TMO" "$MAXN"; do case "$n" in ''|*[!0-9]*) echo "jev-place: numeric setting expected, got '$n'" >&2; exit 2 ;; esac; done
log() { printf '[jev-place] %s\n' "$*" >&2; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
US=$'\x1f'

bounded() { # bounded <seconds> <out> cmd... -> rc of cmd (124/137 on timeout)
  local t="$1" o="$2" rc=0; shift 2
  timeout --kill-after=2 "$t" "$@" >"$o" 2>"$o.err" </dev/null || rc=$?
  return "$rc"
}

# ---- §11.4.291(C) contract table: schema llmctl.capacity/1 -------------------------------------------------
# capacity_read -> writes $WORK/cap.json and prints "ok" or "undetermined<US><reason>". NEVER called under the lock.
capacity_read() {
  local rc=0
  bounded "$RTMO" "$WORK/cap.raw" "$LLMCTL" capacity --json || rc=$?
  case "$rc" in 0|75|3) ;; 124|137) printf 'undetermined%sllmctl capacity timed out after %ss\n' "$US" "$RTMO"; return 0 ;;
    *) printf 'undetermined%sllmctl capacity exit %s (not an answer code 0/75/3)\n' "$US" "$rc"; return 0 ;; esac
  if ! jq -e . "$WORK/cap.raw" >"$WORK/cap.json" 2>/dev/null; then printf 'undetermined%sunparseable capacity output\n' "$US"; return 0; fi
  # llmctl's own failed measurement (measurement.ok false; exit 75 with no profile named): every verdict is undetermined
  if [ "$(jq -r '.measurement.ok == false' "$WORK/cap.json")" = true ]; then
    printf 'undetermined%sllmctl measurement failed: %s\n' "$US" "$(jq -r '.measurement.reason // "no reason given"' "$WORK/cap.json" | tr -d '\037\n')"; return 0
  fi
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
  if [ -n "$miss" ]; then printf 'undetermined%scontract fields missing or wrong: %s\n' "$US" "$miss"; return 0; fi
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

# inst_state <profile> -> "<state><US><verdict><US><threads><US><reason>" from $WORK/cap.json (read ok). state is one of
# ok | degraded | absent | unknown (see the header); verdict is the placement verdict ("" = null for a running instance).
inst_state() {
  local p="$1"
  jev_profile_name_ok "$p" || { printf 'unknown%sundetermined%s0%sinvalid profile name\n' "$US" "$US" "$US"; return 0; }
  jq -r --arg p "$p" --arg tn "$TENANT" '
    def out($s; $v; $t; $r): "\($s)\u001f\($v)\u001f\($t)\u001f\($r | gsub("[\u001f\n\t]"; " "))";
    (if $tn == "" then $p else "\($tn)--\($p)" end) as $key
    | (.profiles[$p] // null) as $e
    | (.host.nproc.headroom // null) as $np
    | [.llmctl.units[]? | select(((.owner // "self") == "self") and ((.profile // "") == $key))] as $own
    | [$own[] | (.status // "")] as $sts
    | if (.unknown_profiles | index($p)) then out("unknown"; "undetermined"; 0; "unknown profile")
      elif $e == null then out("unknown"; "undetermined"; 0; "profile absent from capacity output")
      elif ($e.threads|type) != "number" or ($e.reasons|type) != "array" then out("unknown"; "undetermined"; 0; "threads/reasons missing")
      elif $e.verdict == "running" then
        if ($own | length) == 0 then out("unknown"; "undetermined"; 0; "verdict running but llmctl reports no own unit \($key)")
        elif ($sts | all(. == "ok" or . == "degraded")) | not then out("unknown"; "undetermined"; 0; "unit status \($sts | join(",")) is not ok/degraded")
        elif ($sts | index("degraded")) then out("degraded"; "does_not_fit"; 0; "unit degraded: \([$own[] | .reasons[]?] | join("; "))")
        else out("ok"; ""; 0; "running instance, unit status ok") end
      elif ($own | length) > 0 then out("unknown"; "undetermined"; 0; "an own unit \($key) is reported but the verdict is \($e.verdict // "null"), not running")
      elif $e.verdict == "undetermined" then out("unknown"; "undetermined"; 0; "llmctl verdict undetermined: \($e.reasons | join("; "))")
      elif (($e.verdict // "") | IN("fits","fits_with_reduced_threads","does_not_fit")) | not then out("unknown"; "undetermined"; 0; "verdict outside the closed set")
      elif $e.verdict == "does_not_fit" then out("absent"; "does_not_fit"; $e.threads; ($e.reasons | join("; ")))
      elif ($np|type) != "number" then out("absent"; "undetermined"; $e.threads; "RLIMIT_NPROC headroom not measured")
      elif $np < $e.threads then out("absent"; "does_not_fit"; $e.threads; "nproc headroom \($np) < threads")
      elif .pressure.ok == false then out("absent"; "does_not_fit"; $e.threads; "pressure: \((.pressure.reasons // []) | join("; "))")
      else out("absent"; $e.verdict; $e.threads; ($e.reasons | join("; "))) end' "$WORK/cap.json"
}

hosted_key_var() { local v; for v in TYPESAFE_API_KEY OPENROUTER_API_KEY; do [ "$(key_state "$v" | cut -f1)" = real ] && { echo "$v"; return 0; }; done; return 0; }

write_placement() { # write_placement <profile> <verdict|""> <reason> <route> <started> <threads> <event>
  local kv; kv="$(hosted_key_var)"
  case "$2" in ""|fits|fits_with_reduced_threads|does_not_fit|undetermined) ;; *) log "internal: verdict '$2' outside the closed set"; return 2 ;; esac
  case "${7:-}" in placed|joined|joined_running|no_fit|undetermined|start_failed|start_refused|refused_stopping|refused_starting|refused_degraded|refused_join|lease_lock_timeout|stopped|stop_failed) ;;
    *) log "internal: event '${7:-}' outside the closed set"; return 2 ;; esac
  jq -nc --arg p "$1" --arg v "$2" --arg r "$3" --arg route "$4" --argjson st "$5" --arg th "${6:-0}" --arg ev "${7:-}" --arg kv "$kv" --argjson now "$NOW" \
     --slurpfile cap <(jq -c '{host:{mem_total_mb:.host.mem_total_mb, mem_available_mb:.host.mem_available_mb, usable_mem_mb:.host.usable_mem_mb, load:.host.load, nproc_headroom:(.host.nproc.headroom // null)}, reserve:{mem_reserved_mb:.reserve.mem_reserved_mb, cpus_reserved:.reserve.cpus_reserved}, pressure:.pressure, time:.time}' "$WORK/cap.json" 2>/dev/null || echo '{}') \
     '{placement:{profile:(if $p=="" then null else $p end), verdict:(if $v=="" then null else $v end), event:(if $ev=="" then null else $ev end), reason:$r, route:$route, key_variable:(if $route=="cloud" then $kv else null end), constitution_started:$st, threads:($th|tonumber? // 0),
                 inputs:($cap[0] // {}), source:"llmctl capacity --json (schema llmctl.capacity/1)", evaluated_at:$now}}' > "$WORK/pl.json"
  jev_write_atomic "$PLACEMENT" < "$WORK/pl.json"
  if [ -f "$DETECTION" ]; then
    jq -c --slurpfile pl "$WORK/pl.json" '. + $pl[0]' "$DETECTION" > "$WORK/det.json" 2>/dev/null && jev_write_atomic "$DETECTION" < "$WORK/det.json" || true
  fi
}

fallback_route() { if [ -n "$(hosted_key_var)" ]; then echo cloud; else echo none; fi; }
# the route decision traffic takes now: local while the cache holds an llmctl-local entry, else the fallback
current_route() { if [ -f "$CACHE" ] && jq -e 'any(.endpoints[]?; .provider_id == "llmctl-local")' "$CACHE" >/dev/null 2>&1; then echo local; else fallback_route; fi; }

gateway_url() { # -> "url<US>ca"; NEVER called under the lock (it may run `llmctl decide status`)
  if [ -n "${LLMCTL_GATEWAY_URL:-}" ]; then printf '%s%s%s\n' "$LLMCTL_GATEWAY_URL" "$US" "${LLMCTL_CACERT:-}"; return 0; fi
  local rc=0
  bounded "$RTMO" "$WORK/st.raw" "$LLMCTL" decide status --json || rc=$?
  [ "$rc" = 0 ] || { printf 'https://127.0.0.1:8095%s\n' "$US"; return 0; }
  jq -r '[.registry.services[]? | select((.labels.kind // "") == "gateway")][0] as $g | "\($g.url // "https://127.0.0.1:8095")\u001f\($g.labels.ca_file // "")"' "$WORK/st.raw" 2>/dev/null || printf 'https://127.0.0.1:8095%s\n' "$US"
}
GW_URL=""; GW_CA=""

cache_register() { # cache_register <profile> : add/replace the llmctl-local entry at priority 10 (GW_URL read before the lock)
  mkdir -p "$(dirname "$CACHE")"
  [ -f "$CACHE" ] || jq -n '{version:1, generated_at:0, ttl:300, endpoints:[]}' > "$CACHE"
  jq -c --arg u "$GW_URL" --arg ca "$GW_CA" --arg p "$1" --argjson now "$NOW" '
    .endpoints = ([.endpoints[]? | select(.provider_id != "llmctl-local")]
      + [{provider_id:"llmctl-local", base_url:$u, model:$p, key_var:"LLMCTL_API_KEY", ca_file:$ca, priority:10, probed_at:$now,
          reason:"local placement lease (scripts/jev/jev-place.sh, §11.4.291)"}] | sort_by(.priority // 100))' "$CACHE" > "$WORK/cache.json"
  jev_write_atomic "$CACHE" < "$WORK/cache.json"
}
# cache_normalize <leases-json> [profile-not-ok...] (caller holds the lock): the ONE llmctl-local entry names a ROUTABLE
# set (it exists, holds a lease, is not stopping/starting, not start_failed/stop_owed, and is not listed as not ok in the
# current capacity answer) or it is removed. When the named model is gone it is re-pointed to the first routable set (the
# gateway URL stays the one already registered), else dropped. Review R4-1: a stopped model is never left in the cache.
cache_normalize() {
  [ -f "$CACHE" ] || return 0
  local sets="$1" bad; shift
  bad="$(printf '%s\n' "$@" | jq -R . | jq -sc 'map(select(. != ""))')"
  jq -c --argjson s "$sets" --argjson bad "$bad" --argjson now "$NOW" '
    ([$s.sets | to_entries[] | select(((.value.leases // []) | length) > 0 and (.value.stopping // null) == null and (.value.starting // null) == null
        and (.value.start_failed // null) == null and (.value.stop_owed // null) == null) | .key | select(. as $k | $bad | index($k) | not)]) as $routable
    | ([.endpoints[]? | select(.provider_id == "llmctl-local")] | first // null) as $loc
    | if $loc == null then .
      elif ($routable | index($loc.model)) then .
      elif ($routable | length) > 0 then .endpoints = [.endpoints[] | if .provider_id == "llmctl-local"
          then .model = $routable[0] | .probed_at = $now | .reason = "re-pointed to a held lease set after a set was removed (scripts/jev/jev-place.sh, §11.4.291)" else . end]
      else .endpoints = [.endpoints[] | select(.provider_id != "llmctl-local")] end' "$CACHE" > "$WORK/cache.json" \
    && jev_write_atomic "$CACHE" < "$WORK/cache.json"
}

leases_load() { [ -s "$LEASES" ] && jq -e . "$LEASES" >/dev/null 2>&1 && cat "$LEASES" || echo '{"sets":{}}'; }
leases_save() { jev_write_atomic "$LEASES"; }
leases_hash() { if [ -f "$LEASES" ]; then cksum < "$LEASES"; else echo none; fi; }

proc_start() { # proc_start <pid> -> the process start time (clock ticks since boot, /proc/<pid>/stat field 22) or ""
  local st; st="$(cat "/proc/$1/stat" 2>/dev/null)" || return 0
  st="${st##*) }"   # the comm field may hold spaces and ')': fields after the LAST ") " start at field 3
  # shellcheck disable=SC2086
  set -- $st; printf '%s\n' "${20:-}"
}
ME_START="$(proc_start "$$")"
me_mark() { jq -nc --argjson now "$NOW" --arg pid "$$" --arg pst "$ME_START" '{at:$now, pid:($pid|tonumber), pid_start:($pst|tonumber? // null)}'; }
pid_alive() { # pid_alive <pid> <recorded-start|""|null> -> 0 alive, 1 dead, 2 unknown (/proc unavailable)
  local pid="$1" rec="${2:-}" cur
  [ -d /proc/self ] || return 2
  [ -d "/proc/$pid" ] || return 1
  if [ -n "$rec" ] && [ "$rec" != "null" ]; then cur="$(proc_start "$pid")"; [ "$cur" = "$rec" ] || return 1; fi
  # a /proc file reports size 0, so read it: an empty cmdline is a zombie or a kernel thread, not a session holder
  [ -n "$(head -c 64 "/proc/$pid/cmdline" 2>/dev/null | tr -d '\0')" ] || return 1
  return 0
}
holder_alive() { # holder_alive <pid> <heartbeat_at> <ttl> [pid_start]
  local pid="$1" hb="$2" ttl="$3" rc=0
  if [ -n "$pid" ] && [ "$pid" != "null" ]; then
    pid_alive "$pid" "${4:-}" || rc=$?
    case "$rc" in 0) return 0 ;; 1) return 1 ;; esac
    # no /proc: kill -0 cannot tell a reused pid, so the heartbeat TTL bounds the lease as well
    kill -0 "$pid" 2>/dev/null || return 1
  fi
  [ $(( NOW - hb )) -le "$ttl" ]
}

reap_locked() { # drops dead holders from every set (caller holds the lock); never stops a model
  # every loop variable is local: bash scoping is dynamic, so a bare `read pid ttl` here would clear the CALLER's pid/ttl
  local cur out prof h pid hb ttl pst sat spid sst arc mk; cur="$(leases_load)"; out="$cur"
  while IFS="$US" read -r prof h pid hb ttl pst; do
    [ -n "$prof" ] || continue
    if ! holder_alive "$pid" "$hb" "$ttl" "$pst"; then
      log "reaped dead lease holder=$h profile=$prof"
      out="$(jq -c --arg p "$prof" --arg h "$h" '.sets[$p].leases |= map(select(.holder != $h))' <<<"$out")"
    fi
  done < <(jq -r '.sets | to_entries[] | .key as $p | .value.leases[]? | [$p, (.holder // ""), (.pid // "null"), (.heartbeat_at // 0), (.ttl // 0), (.pid_start // "null")] | map(tostring) | join("\u001f")' <<<"$cur")
  # a `stopping` or `starting` mark is cleared when its process is gone (pid + start time) or the mark is older than the
  # stop timeout + 30 s (§11.4.291(J)); the set is then judged like any other set by the next acquire / release
  while IFS="$US" read -r prof mk sat spid sst; do
    [ -n "$prof" ] || continue
    # a mark without a pid cannot name a dead process: only its age clears it (review R2 nit RS3)
    arc=0; if [ "$spid" != "null" ] && [ -n "$spid" ]; then pid_alive "$spid" "$sst" || arc=$?; fi
    if [ "$arc" = 1 ] || [ $(( NOW - sat )) -gt $(( STMO + 30 )) ]; then
      log "cleared the $mk mark of $prof (its process is gone or the mark is older than the stop timeout)"
      out="$(jq -c --arg p "$prof" --arg m "$mk" '.sets[$p][$m] = null' <<<"$out")"
    fi
  done < <(jq -r '.sets | to_entries[] | .key as $p | .value as $v | ("stopping", "starting") as $m | select(($v[$m] // null) != null)
                  | [$p, $m, ($v[$m].at // 0), ($v[$m].pid // "null"), ($v[$m].pid_start // "null")] | map(tostring) | join("\u001f")' <<<"$out")
  [ "$out" = "$cur" ] || printf '%s\n' "$out" | leases_save
}

with_lock() { # with_lock <fn> args... -> rc 4 on lock timeout. The function must not run llmctl (R4-3).
  exec 9>>"$LOCK"
  if ! flock -w "$LOCK_TMO" 9; then exec 9>&-; return 4; fi
  local rc=0; "$@" || rc=$?
  flock -u 9; exec 9>&-
  return "$rc"
}

lease_obj_args() { # lease_obj_args <pid> -> the start time of a --pid holder ("" when none / unreadable)
  if [ -n "$1" ]; then proc_start "$1"; fi
}

cmd_verdict() {
  local json="${1:-}" st reason p line first=1
  IFS="$US" read -r st reason < <(capacity_read)
  {
    printf '['
    if [ "$st" = ok ]; then
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        line="$(inst_state "$p")"
        [ "$first" = 1 ] || printf ','; first=0
        jq -nc --arg p "$p" --arg l "$line" '($l|split("\u001f")) as $f | {profile:$p, state:$f[0], verdict:(if $f[1] == "" then null else $f[1] end), threads:($f[2]|tonumber? // 0), reason:($f[3] // "")}'
      done < <(candidates)
    fi
    printf ']'
  } > "$WORK/v.json"
  if [ "$json" = "--json" ]; then jq -c --arg st "$st" --arg r "${reason:-}" '{contract:$st, contract_reason:$r, candidates:.}' "$WORK/v.json"
  else
    [ "$st" = ok ] || log "capacity contract: undetermined ($reason) - no local start"
    jq -r '.[] | "\(.profile)\t\(.state)\t\(.verdict // "null")\tthreads=\(.threads)\t\(.reason)"' "$WORK/v.json"
  fi
}

# ---- the ONE stop helper (review R4-1, R4-3) -----------------------------------------------------------------------
# finish_stop_locked <profile> <stop-rc> <kind> (caller holds the lock). kind: release | dispose | owed | cleanup.
#   rc 0     : the set is removed, the endpoint cache is normalised (never names the stopped model), placement `stopped`.
#   rc != 0  : the model may still run, so the set is KEPT and records stop_failed {at, rc}:
#              release -> the stopping mark (this process) is kept until this process is gone (then a later release
#                         retries; a later acquire judges the lease-less set like any other);
#              dispose -> stopping cleared, stop_owed {at, reason}: never joined, retried by every acquire and release;
#              owed / cleanup -> stopping cleared, the start_failed / stop_owed record stays: never joined, retried.
finish_stop_locked() {
  local p="$1" rc="$2" kind="$3" cur
  cur="$(leases_load)"
  if [ "$rc" = 0 ]; then
    cur="$(jq -c --arg p "$p" 'del(.sets[$p])' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    # shellcheck disable=SC2086  # CAP_BAD is a space-separated profile list
    cache_normalize "$cur" ${CAP_BAD:-}
    write_placement "$p" "" "llmctl stop $p rc=0 ($kind)" "$(current_route)" false 0 stopped
    return 0
  fi
  case "$kind" in
    release) cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson rc "$rc" '.sets[$p].stop_failed = {at:$now, rc:$rc}' <<<"$cur")" ;;
    dispose) cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson rc "$rc" --arg why "${DISPOSE_WHY[$p]:-disposal}" \
                 '.sets[$p].stopping = null | .sets[$p].stop_owed = {at:$now, reason:$why} | .sets[$p].stop_failed = {at:$now, rc:$rc}' <<<"$cur")" ;;
    *)       cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson rc "$rc" '.sets[$p].stopping = null | .sets[$p].stop_failed = {at:$now, rc:$rc}' <<<"$cur")" ;;
  esac
  printf '%s\n' "$cur" | leases_save
  # a set that holds no lease is not routable (cache_normalize), so the route is the current one (the fallback unless
  # another held set is registered); the model may still run until the retried stop succeeds
  write_placement "$p" "" "llmctl stop $p rc=$rc ($kind; failed or timed out); the set is kept and the stop is retried" "$(current_route)" true 0 stop_failed
}
# do_stop <profile> <kind> -> 0 stopped, 1 the stop failed, 4 the result could not be recorded (lock timeout).
# The set was marked `stopping` (or is a release set) under the lock; the bounded stop itself runs WITHOUT the lock.
do_stop() {
  local p="$1" kind="$2" src=0 frc=0
  bounded "$STMO" "$WORK/stop.out" "$LLMCTL" stop "$p" || src=$?
  case "$kind:$src" in
    release:0) log "last lease released: llmctl stop $p rc=0" ;;
    release:*) log "stop_failed: llmctl stop $p rc=$src (124/137 = timed out after ${STMO}s); the set is kept, retried by the next release" ;;
    dispose:0) log "disposed $p: llmctl stop rc 0, set removed (not restarted by this acquire)" ;;
    dispose:*) log "disposal stop of $p failed rc=$src (124/137 = timed out after ${STMO}s); the set is kept (stop_owed) and the stop is retried" ;;
    owed:0)    log "retried the cleanup stop of $p (its start or its disposal stop had failed): rc 0, set removed" ;;
    owed:*)    log "retried the cleanup stop of $p (its start or its disposal stop had failed): rc $src; the set is kept and retried again" ;;
    cleanup:0) log "cleanup stop of $p after the failed start: rc 0" ;;
    cleanup:*) log "cleanup stop of $p failed rc=$src; the set is kept (constitution_started, start_failed, stop_failed) and the stop is retried" ;;
  esac
  with_lock finish_stop_locked "$p" "$src" "$kind" || frc=$?
  if [ "$frc" != 0 ]; then log "the result of llmctl stop $p (rc $src) could not be recorded (lock rc $frc); the next acquire re-judges the set"; return 4; fi
  [ "$src" = 0 ]
}

# ---- acquire: plan under the lock, llmctl calls outside it ------------------------------------------------------------
# plan_locked <holder> <pid> <ttl> <leases-hash|""> (caller holds the lock; NO llmctl call). Reads $WORK/cap.json
# (CAP_ST) and $WORK/cands. Sets: PLAN_STOPS (lines "<profile><US><kind>", each set already marked stopping), START_CANDS
# (lines "<profile><US><verdict><US><threads><US><reason>"), CAP_BAD, and the result F_RC / F_OUT plus the placement
# record F_P F_V F_R F_ST F_TH F_EV (F_ROUTE local for a lease, else the fallback). rc 99: the lease file changed after
# the capacity read (the caller reads again).
declare -A DISPOSE_WHY=()
plan_locked() {
  local holder="$1" pid="$2" ttl="$3" h0="$4" cur pst mark p jp v th r st kind leased cs lline ref_p="" ref_v="" ref_r="" ref_ev="" any_undet=0
  if [ -n "$h0" ] && [ "$(leases_hash)" != "$h0" ]; then return 99; fi
  PLAN_STOPS=""; START_CANDS=""; CAP_BAD=""; F_RC=5; F_OUT=""; F_P=""; F_V="does_not_fit"; F_R="no candidate profile fits"; F_ST=false; F_TH=0; F_EV=no_fit; F_ROUTE=""
  pst="$(lease_obj_args "$pid")"; mark="$(me_mark)"
  reap_locked
  cur="$(leases_load)"
  # marks set by OTHER processes before this plan (our own marks below are added after this read)
  local foreign; foreign="$(jq -r '[.sets | to_entries[] | (if (.value.starting // null) != null then "starting" elif (.value.stopping // null) != null then "stopping" else empty end)] | first // ""' <<<"$cur")"
  # (A) owed stops: a failed start whose cleanup stop failed, or a failed disposal stop (never joined; retried)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    cur="$(jq -c --arg p "$p" --argjson m "$mark" '.sets[$p].stopping = $m' <<<"$cur")"
    PLAN_STOPS+="$p${US}owed"$'\n'
  done < <(jq -r '.sets | to_entries[] | select(((.value.start_failed // null) != null or (.value.stop_owed // null) != null) and (.value.stopping // null) == null and (.value.starting // null) == null and (.value.leases | length) == 0) | .key' <<<"$cur")
  # an empty set this producer did not start (its holders were reaped) is forgotten, like release does; never stopped
  cur="$(jq -c '.sets |= with_entries(select((.value.leases | length) > 0 or .value.constitution_started == true))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  cache_normalize "$cur"
  # (B) every existing, unmarked set: joined when its instance is ok; a lease-less constitution-started set whose instance
  # is degraded or gone is stopped (dispose); a set that still has a live lease is never stopped here; nothing is judged
  # or stopped on an unread capacity answer or an unknown instance state.
  local jprofs; jprofs="$(jq -r '.sets | to_entries[] | select((.value.stopping // null) == null and (.value.starting // null) == null and (.value.start_failed // null) == null and (.value.stop_owed // null) == null) | .key' <<<"$cur")"
  if [ -n "$jprofs" ]; then
    if [ "$CAP_ST" != ok ]; then
      F_P="$(head -n1 <<<"$jprofs")"; F_V=undetermined; F_R="join refused: ${CAP_REASON:-capacity unreadable}"; F_EV=refused_join
      log "refused: capacity undetermined ($CAP_REASON); $F_P not joined; nothing is stopped on an unread answer"; return 0
    fi
    while IFS= read -r jp; do
      [ -n "$jp" ] || continue
      IFS="$US" read -r st v th r <<<"$(inst_state "$jp")"
      leased="$(jq -r --arg p "$jp" '.sets[$p].leases | length' <<<"$cur")"
      cs="$(jq -r --arg p "$jp" '.sets[$p].constitution_started == true' <<<"$cur")"
      if [ "$st" = ok ]; then
        cur="$(jq -c --arg p "$jp" --arg h "$holder" --arg pid "$pid" --arg pst "$pst" --argjson now "$NOW" --argjson ttl "$ttl" \
          '.sets[$p].leases = ([.sets[$p].leases[] | select(.holder != $h)] + [{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), pid_start:($pst|tonumber? // null), heartbeat_at:$now, ttl:$ttl}])' <<<"$cur")"
        printf '%s\n' "$cur" | leases_save
        cache_register "$jp"
        F_RC=0; F_OUT="$jp"; F_P="$jp"; F_V=""; F_R="joined an existing lease set ($r)"; F_ST="$cs"; F_TH=0; F_EV=joined; F_ROUTE=local
        log "lease joined: holder=$holder profile=$jp ($r)"
        return 0
      fi
      CAP_BAD+=" $jp"
      if [ "$leased" = 0 ] && [ "$cs" = true ] && { [ "$st" = degraded ] || [ "$st" = absent ]; }; then
        log "disposing $jp: no lease left, constitution-started, instance $st ($r); bounded llmctl stop outside the lock"
        cur="$(jq -c --arg p "$jp" --argjson m "$mark" '.sets[$p].stopping = $m' <<<"$cur")"
        printf '%s\n' "$cur" | leases_save
        DISPOSE_WHY[$jp]="instance $st: $r"
        PLAN_STOPS+="$jp${US}dispose"$'\n'
        continue
      fi
      log "refused for $holder: $jp (instance $st: $r); it keeps its $leased lease(s) and is not stopped"
      if [ -z "$ref_p" ]; then
        ref_p="$jp"; ref_v="$v"; ref_r="instance $st: $r"; ref_ev=refused_join
        [ "$st" != degraded ] || { ref_v=does_not_fit; ref_ev=refused_degraded; }
      fi
    done <<<"$jprofs"
    # a set that is not ok in THIS answer (degraded or unknown), held or not, is not routable: the cache never names it, so
    # the route switches to the fallback before anything else happens (§11.4.291(D)(1); found by the round-5 P50 test)
    # shellcheck disable=SC2086  # CAP_BAD is a space-separated profile list
    [ -z "$CAP_BAD" ] || cache_normalize "$cur" $CAP_BAD
    if [ -n "$ref_p" ]; then
      F_P="$ref_p"; F_V="${ref_v:-undetermined}"; F_R="join refused: $ref_r"; F_EV="$ref_ev"
      [ "$ref_ev" != refused_degraded ] || F_R="unit degraded: not joined ($ref_r)"
      log "refused: $ref_p ($ref_r); not joined; fallback route $(fallback_route)"; return 0
    fi
  fi
  # (C) a set another process is starting or stopping refuses this acquire (§11.4.291(J))
  if [ -n "$foreign" ]; then
    F_V=undetermined; F_R="a lease set is $foreign (refused per §11.4.291(J))"; F_EV="refused_$foreign"
    log "refused: a lease set is $foreign; fallback route $(fallback_route)"; return 0
  fi
  if [ "$CAP_ST" != ok ]; then
    F_V=undetermined; F_R="$CAP_REASON"; F_EV=undetermined
    log "undetermined ($CAP_REASON): no local start; fallback route $(fallback_route)"; return 0
  fi
  # (D) adoption first: a candidate llmctl already runs for this user (ok) and that has no set was started by someone
  # else (the operator, or a session outside this registry): join it as NOT constitution-started (never stopped by this
  # producer, §11.4.291(G)(J)); routing adds no resident footprint, so it is preferred over starting another model.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    jq -e --arg p "$p" '.sets[$p] != null' <<<"$cur" >/dev/null && continue
    IFS="$US" read -r st v th r <<<"$(inst_state "$p")"
    [ "$st" = ok ] || continue
    cur="$(jq -c --arg p "$p" --arg h "$holder" --arg pid "$pid" --arg pst "$pst" --argjson now "$NOW" --argjson ttl "$ttl" \
      '.sets[$p] = {constitution_started:false, stopping:null, starting:null, leases:[{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), pid_start:($pst|tonumber? // null), heartbeat_at:$now, ttl:$ttl}]}' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    cache_register "$p"
    F_RC=0; F_OUT="$p"; F_P="$p"; F_V=""; F_R="already running (not started by the constitution; $r)"; F_ST=false; F_TH=0; F_EV=joined_running; F_ROUTE=local
    log "joined the already-running unit $p (not constitution-started; it is never stopped by this producer)"
    return 0
  done < "$WORK/cands"
  # (E) start candidates (started one by one after this plan, outside the lock)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if jq -e --arg p "$p" '.sets[$p] != null' <<<"$cur" >/dev/null; then log "candidate $p: a lease set already exists (not joinable); skipped"; continue; fi
    case " ${DISPOSED:-} " in *" $p "*) log "candidate $p: stopped by this acquire (hold until the next evaluation, §11.4.291(D))"; continue ;; esac
    lline="$(inst_state "$p")"; IFS="$US" read -r st v th r <<<"$lline"
    case "$st:$v" in
      absent:fits|absent:fits_with_reduced_threads) START_CANDS+="$p$US$v$US$th$US$r"$'\n' ;;
      degraded:*) log "candidate $p: unit degraded ($r); not started a second time, not adopted" ;;
      *) [ "$v" != undetermined ] || any_undet=1; log "candidate $p: $st/$v ($r)" ;;
    esac
  done < "$WORK/cands"
  if [ "$any_undet" = 1 ]; then F_V=undetermined; F_R="no candidate fits; at least one is undetermined"; fi
  return 0
}

# mark_start_locked <profile> <holder> <pid> <pid_start> <ttl> -> 0 marked (set created with a `starting` mark naming this
# process and the holder's lease), 1 not startable any more (a set exists or another process marked one meanwhile)
mark_start_locked() {
  local p="$1" cur
  reap_locked
  cur="$(leases_load)"
  if jq -e --arg p "$p" '.sets[$p] != null' <<<"$cur" >/dev/null; then return 1; fi
  if jq -e --argjson me "$$" '[.sets[] | select(((.starting // null) != null and .starting.pid != $me) or ((.stopping // null) != null and .stopping.pid != $me))] | length > 0' <<<"$cur" >/dev/null; then return 1; fi
  cur="$(jq -c --arg p "$p" --arg h "$2" --arg pid "$3" --arg pst "$4" --argjson now "$NOW" --argjson ttl "$5" --argjson m "$(me_mark)" \
    '.sets[$p] = {constitution_started:true, started_at:null, stopping:null, starting:$m, leases:[{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), pid_start:($pst|tonumber? // null), heartbeat_at:$now, ttl:$ttl}]}' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
}
# finish_start_locked <profile> <start-rc> -> sets START_RES placed | released | refused | failed (and marks `stopping`
# for released / failed: the caller then runs do_stop <profile> release|cleanup)
finish_start_locked() {
  local p="$1" src="$2" cur leased
  cur="$(leases_load)"
  leased="$(jq -r --arg p "$p" '(.sets[$p].leases // []) | length' <<<"$cur")"
  if [ "$src" = 0 ]; then
    if [ "$leased" = 0 ]; then
      cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson m "$(me_mark)" '.sets[$p] = ((.sets[$p] // {constitution_started:true, leases:[]}) + {started_at:$now, starting:null, stopping:$m})' <<<"$cur")"
      START_RES=released
    else
      cur="$(jq -c --arg p "$p" --argjson now "$NOW" '.sets[$p].starting = null | .sets[$p].started_at = $now' <<<"$cur")"
      START_RES=placed
    fi
    printf '%s\n' "$cur" | leases_save
    [ "$START_RES" != placed ] || cache_register "$p"
  elif [ "$src" = 75 ]; then
    cur="$(jq -c --arg p "$p" 'del(.sets[$p])' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    cache_normalize "$cur"
    START_RES=refused
  else
    cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson src "$src" --argjson m "$(me_mark)" \
      '.sets[$p] = {constitution_started:true, started_at:$now, starting:null, stopping:$m, leases:[], start_failed:{at:$now, rc:$src}}' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    cache_normalize "$cur"
    START_RES=failed
  fi
}

cmd_acquire() {
  local holder="$1" pid="$2" ttl="$3" rc tries=0 round p kind v th r src started=0 n=0 prof="" pst
  local out_v="" out_ev="" out_r="" out_p="" out_th=0 stops_done
  pst="$(lease_obj_args "$pid")"
  IFS="$US" read -r GW_URL GW_CA < <(gateway_url)
  candidates > "$WORK/cands"
  DISPOSED=""
  for round in 1 2; do
    stops_done=0
    while :; do
      local h0; h0="$(leases_hash)"
      IFS="$US" read -r CAP_ST CAP_REASON < <(capacity_read)
      rc=0; if [ "$tries" -lt 3 ]; then with_lock plan_locked "$holder" "$pid" "$ttl" "$h0" || rc=$?; else with_lock plan_locked "$holder" "$pid" "$ttl" "" || rc=$?; fi
      if [ "$rc" = 99 ]; then tries=$((tries+1)); log "the lease file changed during the capacity read; reading it again ($tries)"; continue; fi
      break
    done
    if [ "$rc" = 4 ]; then return 4; fi
    while IFS="$US" read -r p kind; do
      [ -n "$p" ] || continue
      [ "$kind" != dispose ] || DISPOSED+=" $p"
      if do_stop "$p" "$kind"; then stops_done=1; fi
    done <<<"$PLAN_STOPS"
    # a model was stopped: the budget changed, so a start is decided on a fresh answer (once); a join is final
    if [ "$stops_done" = 1 ] && [ "$F_RC" != 0 ] && [ "$round" = 1 ]; then log "a model was stopped; reading the capacity answer again before a start"; continue; fi
    break
  done
  if [ "$F_RC" = 0 ]; then
    with_lock write_placement "$F_P" "$F_V" "$F_R" "$F_ROUTE" "$F_ST" "$F_TH" "$F_EV" || true
    echo "$F_OUT"; return 0
  fi
  while IFS="$US" read -r p v th r; do
    [ -n "$p" ] || continue
    [ "$n" -lt "$MAXN" ] || break
    if ! with_lock mark_start_locked "$p" "$holder" "$pid" "$pst" "$ttl"; then log "candidate $p: no longer startable (a set exists or another process is starting/stopping one)"; continue; fi
    src=0; bounded "$STMO" "$WORK/start.out" "$LLMCTL" start "$p" || src=$?
    START_RES=""; rc=0; with_lock finish_start_locked "$p" "$src" || rc=$?
    if [ "$rc" != 0 ]; then log "the result of llmctl start $p (rc $src) could not be recorded (lock rc $rc); the starting mark expires"; continue; fi
    case "$START_RES" in
      placed)
        started=1; n=$((n+1)); prof="${prof:-$p}"
        out_p="$prof"; out_v="$v"; out_ev=placed; out_r="$r"; out_th="$th"
        log "started $p ($v, threads=$th); lease holder=$holder; local gateway registered at priority 10" ;;
      released)
        log "started $p but its lease was released during the start; stopping it again"
        do_stop "$p" release || true ;;
      refused)
        log "llmctl start $p refused (75): does_not_fit"
        [ "$out_ev" = start_failed ] || { out_v="does_not_fit"; out_ev="start_refused"; out_r="llmctl start $p refused (75, pressure gate)"; out_p="$p"; out_th="$th"; } ;;
      failed)
        log "llmctl start $p failed rc=$src: $(head -c 300 "$WORK/start.out.err" 2>/dev/null | tr '\n' ' ')"
        # the capacity verdict stays what was MEASURED; the failure is the event (review 2026-11-12 F5)
        out_v="$v"; out_ev="start_failed"; out_r="llmctl start $p failed rc=$src"; out_p="$p"; out_th="$th"
        # Live T5 (2026-11-12): llmctl can fail AFTER the unit began starting; the unit was not running before (its
        # state was absent), so this producer started it and stops it again. 75 (no partial start) needs nothing.
        log "start of $p failed after it was requested; stopping it again so no unit is left without a lease"
        do_stop "$p" cleanup || out_r="llmctl start $p failed rc=$src; cleanup stop failed (set kept, stop retried)" ;;
    esac
  done <<<"$START_CANDS"
  if [ "$started" = 1 ]; then
    with_lock write_placement "$out_p" "$out_v" "$out_r" local true "$out_th" placed || true
    echo "$prof"; return 0
  fi
  if [ -n "$out_ev" ]; then F_P="$out_p"; F_V="$out_v"; F_R="$out_r"; F_TH="$out_th"; F_EV="$out_ev"; fi
  with_lock write_placement "$F_P" "$F_V" "$F_R" "$(fallback_route)" false "$F_TH" "$F_EV" || true
  log "no local placement ($F_EV); fallback route $(fallback_route)"; return 5
}

release_locked() {
  local holder="$1" cur prof mark
  reap_locked
  mark="$(me_mark)"
  cur="$(leases_load)"
  cur="$(jq -c --arg h "$holder" '.sets |= map_values(.leases |= map(select(.holder != $h)))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  # EVERY constitution-started set with no lease left (JEV_PLACE_MAX>1 starts several) and no mark: mark stopping (others
  # refuse), then stop OUTSIDE the lock. A set still starting is finished by its starter (it stops it when no lease is
  # left). The mark names this process (pid + start time) so a dead stopper's mark is cleared.
  while IFS= read -r prof; do
    [ -n "$prof" ] || continue
    cur="$(jq -c --arg p "$prof" --argjson m "$mark" '.sets[$p].stopping = $m' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    echo "$prof"
  done < <(jq -r '.sets | to_entries[] | select((.value.leases | length) == 0 and (.value.constitution_started == true) and (.value.stopping // null) == null and (.value.starting // null) == null) | .key' <<<"$cur")
  # an empty set this producer did not start is just forgotten (an operator-started model is never stopped)
  cur="$(jq -c '.sets |= with_entries(select((.value.leases | length) > 0 or .value.constitution_started == true))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  cache_normalize "$cur"
}

sub="${1:-}"; shift || true
case "$sub" in
  verdict) cmd_verdict "${1:-}" ;;
  acquire)
    holder="${1:-}"; shift || true; pid=""; ttl="$TTL_DEFAULT"
    jev_check_word "$holder" || { echo "jev-place: acquire needs a holder id ([A-Za-z0-9._-]+)" >&2; exit 2; }
    while [ $# -gt 0 ]; do case "$1" in --pid) pid="${2:-}"; shift 2 ;; --ttl) ttl="${2:-}"; shift 2 ;; *) echo "jev-place: unknown arg $1" >&2; exit 2 ;; esac; done
    case "$pid$ttl" in *[!0-9]*) echo "jev-place: --pid/--ttl must be integers" >&2; exit 2 ;; esac
    rc=0; cmd_acquire "$holder" "$pid" "$ttl" || rc=$?
    if [ "$rc" = 4 ]; then write_placement "" "undetermined" "lease_lock_timeout" "$(fallback_route)" false 0 lease_lock_timeout 2>/dev/null || true; log "lease_lock_timeout: no lease taken"; fi
    exit "$rc" ;;
  heartbeat)
    holder="${1:-}"; jev_check_word "$holder" || { echo "jev-place: heartbeat needs a holder id" >&2; exit 2; }
    hb() { local c; c="$(leases_load)"; c="$(jq -c --arg h "$1" --argjson now "$NOW" '.sets |= map_values(.leases |= map(if .holder == $h then .heartbeat_at = $now else . end))' <<<"$c")"; printf '%s\n' "$c" | leases_save; }
    with_lock hb "$holder" ;;
  release)
    holder="${1:-}"; jev_check_word "$holder" || { echo "jev-place: release needs a holder id" >&2; exit 2; }
    rc=0; stopprofs="$(with_lock release_locked "$holder")" || rc=$?
    [ "$rc" = 0 ] || { log "release: lock timeout (rc $rc)"; exit "$rc"; }
    rrc=0
    while IFS= read -r stopprof; do
      [ -n "$stopprof" ] || continue
      # a stop can take as long as a start (model unload, unit shutdown): bounded by the START/STOP timeout, not RTMO
      do_stop "$stopprof" release || rrc=6
    done <<< "$stopprofs"
    exit "$rrc" ;;
  reap) with_lock reap_locked ;;
  status)
    if [ "${1:-}" = "--json" ]; then jq -nc --slurpfile l <(leases_load) --slurpfile p <( [ -f "$PLACEMENT" ] && cat "$PLACEMENT" || echo '{}') '{leases:$l[0], placement:($p[0].placement // null)}'
    else leases_load | jq -r '.sets | to_entries[] | "\(.key): leases=\(.value.leases|length) constitution_started=\(.value.constitution_started) stopping=\(.value.stopping != null) starting=\((.value.starting // null) != null)"'
      [ -f "$PLACEMENT" ] && jq -r '.placement | "placement: profile=\(.profile) verdict=\(.verdict) event=\(.event) route=\(.route) reason=\(.reason)"' "$PLACEMENT"; fi ;;
  ""|-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; [ -n "$sub" ] && exit 0 || exit 2 ;;
  enable|disable|switch|auto) echo "jev-place: '$sub' is never run by the constitution (§11.4.291(G))" >&2; exit 2 ;;
  *) echo "jev-place: unknown subcommand '$sub'" >&2; exit 2 ;;
esac
