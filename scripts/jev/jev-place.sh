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
#   jev-place.sh release  <holder>               drop a lease; the last release stops EVERY constitution-started model
#                                                with no lease left (bounded by the start/stop timeout)
#   jev-place.sh reap                            drop leases whose holder pid is dead or whose heartbeat expired
#   jev-place.sh status   [--json]               lease sets + last placement entry
# Exit codes: 0 done; 2 usage / cannot determine (jq absent); 4 lease lock timeout (no lease taken: caller falls back);
#             5 no local placement (verdict not fits / undetermined / start refused): the placement entry names the
#               fallback route (cloud when a non-placeholder hosted key exists, else none);
#             6 release: an `llmctl stop` failed or timed out. The lease set is KEPT (constitution_started, stopping
#               mark, stop_failed {at, rc}); the next release (or an acquire, which joins it) retries once the stop mark
#               is cleared (stopper process gone, or older than the stop timeout + 30 s). The model is never orphaned.
# Env (names only):
#   JEV_LLMCTL_BIN (default llmctl), JEV_LLMCTL_TIMEOUT (default 20 s, read calls), JEV_LLMCTL_START_TIMEOUT (default 300 s),
#   JEV_PLACE_PROFILES (comma list: candidate order; default = every systemone-native decide profile in llmctl order),
#   JEV_PLACE_MAX (instances to start per acquire, default 1), JEV_LEASE_TTL (default 900 s; must exceed the
#   re-evaluation cadence + the llmctl timeout, §11.4.291(J)), JEV_LOCK_TIMEOUT (default 10 s),
#   JEV_STATE_DIR / JEV_HOME (state), CMA_PROVIDERS_DIR (endpoint cache dir), LLMCTL_GATEWAY_URL (default from
#   `llmctl decide status --json` registry), JEV_NOW_EPOCH (clock seam, ONLY with JEV_TEST=1).
# Verdicts (§11.4.291(A)): fits | fits_with_reduced_threads | does_not_fit | undetermined (or null when no capacity
# verdict applies, e.g. a stop). undetermined is NEVER fits. What HAPPENED is in the separate `event` field, closed set:
# placed | joined | joined_running | no_fit | undetermined | start_failed | start_refused | refused_stopping |
# refused_degraded | refused_join | lease_lock_timeout | stopped | stop_failed (write_placement refuses any other value).
# Join (round 3, review R2-3): an existing set is joined ONLY when the capacity contract is readable, the unit llmctl
# reports for the profile is `running` or `active`, and the verdict is `fits` or `fits_with_reduced_threads` (an
# allow-list: failed, absent, unknown, starting, degraded, does_not_fit and undetermined are all refused, event
# refused_join / refused_degraded, rc 5, no lease, no cache registration).
# Disposal (round 4, review R3-1): every existing set is evaluated, not only the first. A set whose holders were all reaped
# (no lease left) and that THIS producer started is stopped by the next acquire when its unit is not running/active or its
# verdict is not a fit (bounded stop; the set and its cache entry are dropped; that acquire does not restart the profile,
# the next one evaluates it afresh). A failed disposal stop keeps the set {stop_owed, stop_failed}: never joined, the stop
# is retried by every later acquire and release. A set that still has a live lease is never stopped by this path, and a
# reap alone never stops a model (§11.4.291(J)).
# Failed start (round 3, review R2-2): when `llmctl start` fails and the cleanup `llmctl stop` fails too, the producer
# keeps a set {constitution_started:true, leases:[], start_failed, stop_failed}: it is never joined, never adopted as
# operator-started and never started again; every later acquire and every release retries the stop.
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

write_placement() { # write_placement <profile> <verdict|""> <reason> <route> <started> <threads> <event>
  local kv; kv="$(hosted_key_var)"
  case "$2" in ""|fits|fits_with_reduced_threads|does_not_fit|undetermined) ;; *) log "internal: verdict '$2' outside the closed set"; return 2 ;; esac
  case "${7:-}" in placed|joined|joined_running|no_fit|undetermined|start_failed|start_refused|refused_stopping|refused_degraded|refused_join|lease_lock_timeout|stopped|stop_failed) ;;
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

gateway_url() {
  if [ -n "${LLMCTL_GATEWAY_URL:-}" ]; then printf '%s\t%s\n' "$LLMCTL_GATEWAY_URL" "${LLMCTL_CACERT:-}"; return 0; fi
  local rc=0
  bounded "$RTMO" "$WORK/st.raw" "$LLMCTL" decide status --json || rc=$?
  [ "$rc" = 0 ] || { printf 'https://127.0.0.1:8095\t\n'; return 0; }
  jq -r '[.registry.services[]? | select((.labels.kind // "") == "gateway")][0] as $g | "\($g.url // "https://127.0.0.1:8095")\t\($g.labels.ca_file // "")"' "$WORK/st.raw" 2>/dev/null || printf 'https://127.0.0.1:8095\t\n'
}

cache_register() { # cache_register <profile> : add/replace the llmctl-local entry at priority 10
  local u ca; IFS=$'\x1f' read -r u ca < <(gateway_url | tr '\t' '\037')
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

proc_start() { # proc_start <pid> -> the process start time (clock ticks since boot, /proc/<pid>/stat field 22) or ""
  local st; st="$(cat "/proc/$1/stat" 2>/dev/null)" || return 0
  st="${st##*) }"   # the comm field may hold spaces and ')': fields after the LAST ") " start at field 3
  # shellcheck disable=SC2086
  set -- $st; printf '%s\n' "${20:-}"
}
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
  local cur out prof h pid hb ttl pst sat spid sst arc; cur="$(leases_load)"; out="$cur"
  while IFS=$'\x1f' read -r prof h pid hb ttl pst; do
    [ -n "$prof" ] || continue
    if ! holder_alive "$pid" "$hb" "$ttl" "$pst"; then
      log "reaped dead lease holder=$h profile=$prof"
      out="$(jq -c --arg p "$prof" --arg h "$h" '.sets[$p].leases |= map(select(.holder != $h))' <<<"$out")"
    fi
  done < <(jq -r '.sets | to_entries[] | .key as $p | .value.leases[]? | [$p, (.holder // ""), (.pid // "null"), (.heartbeat_at // 0), (.ttl // 0), (.pid_start // "null")] | map(tostring) | join("\u001f")' <<<"$cur")
  # a `stopping` mark is cleared when its stopper process is gone (pid + start time) or the mark is older than the stop
  # timeout + 30 s (§11.4.291(J)); a set kept after a failed stop then becomes stoppable again by the next release
  while IFS=$'\x1f' read -r prof sat spid sst; do
    [ -n "$prof" ] || continue
    # a mark without a pid cannot name a dead stopper: only its age clears it (review R2 nit RS3)
    arc=0; if [ "$spid" != "null" ] && [ -n "$spid" ]; then pid_alive "$spid" "$sst" || arc=$?; fi
    if [ "$arc" = 1 ] || [ $(( NOW - sat )) -gt $(( STMO + 30 )) ]; then
      log "cleared the stop mark of $prof (stopper gone or mark older than the stop timeout)"
      out="$(jq -c --arg p "$prof" '.sets[$p].stopping = null' <<<"$out")"
    fi
  done < <(jq -r '.sets | to_entries[] | select((.value.stopping // null) != null) | [.key, (.value.stopping.at // 0), (.value.stopping.pid // "null"), (.value.stopping.pid_start // "null")] | map(tostring) | join("\u001f")' <<<"$out")
  [ "$out" = "$cur" ] || printf '%s\n' "$out" | leases_save
}

with_lock() { # with_lock <fn> args... -> rc 4 on lock timeout
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
  IFS=$'\x1f' read -r st reason < <(capacity_read | tr '\t' '\037')
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
  local holder="$1" pid="$2" ttl="$3" cur prof st reason line v th r us started=0 n=0 pst
  local out_v="does_not_fit" out_ev="no_fit" out_r="no candidate profile fits" out_p="" out_th=0 any_undet=0
  pst="$(lease_obj_args "$pid")"
  reap_locked
  cur="$(leases_load)"
  # Round 3 (R2-2): a set kept after a failed start + failed cleanup stop, and round 4 (R3-1): a set whose disposal stop
  # failed (stop_owed), is retried here (bounded stop), never joined.
  local fprof frc
  while IFS= read -r fprof; do
    [ -n "$fprof" ] || continue
    frc=0; bounded "$STMO" "$WORK/stop.out" "$LLMCTL" stop "$fprof" || frc=$?
    if [ "$frc" = 0 ]; then
      log "retried the cleanup stop of $fprof (its start or its disposal stop had failed): rc 0, set removed"
      cur="$(jq -c --arg p "$fprof" 'del(.sets[$p])' <<<"$cur")"
    else
      log "retried the cleanup stop of $fprof (its start or its disposal stop had failed): rc $frc; the set is kept and retried again"
      cur="$(jq -c --arg p "$fprof" --argjson now "$NOW" --argjson rc "$frc" '.sets[$p].stop_failed = {at:$now, rc:$rc}' <<<"$cur")"
    fi
    printf '%s\n' "$cur" | leases_save
  done < <(jq -r '.sets | to_entries[] | select(((.value.start_failed // null) != null or (.value.stop_owed // null) != null) and (.value.stopping // null) == null and (.value.leases | length) == 0) | .key' <<<"$cur")
  # an empty set this producer did not start (its holders were reaped) is forgotten, like release does; never stopped
  cur="$(jq -c '.sets |= with_entries(select((.value.leases | length) > 0 or .value.constitution_started == true))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  # Join (round 4, review R3-1): EVERY existing, non-stopping set is evaluated (with JEV_PLACE_MAX>1 the first set can be
  # dead while the second serves). A set is joined ONLY when the capacity contract is readable, the unit llmctl reports is
  # running/active and the verdict is a fit (an ALLOW-list; review 2026-11-12 F5, round 3 R2-3). A set that fails the check:
  #   * still held by a live lease: left alone (refused for this holder; never stopped, its holders still use it);
  #   * lease-less and constitution-started (its holders were reaped): DISPOSED here - a bounded `llmctl stop` (only a model
  #     THIS producer started, §11.4.291(G)), then the set and its cache entry are dropped; a failed stop keeps the set
  #     {stop_owed, stop_failed} so it is never joined and the stop is retried by every later acquire and release. A
  #     disposed profile is not restarted by the SAME acquire (§11.4.291(D) hold): the next acquire evaluates it afresh.
  # A reap alone never stops a model (§11.4.291(J)); only an acquire, which has read the capacity answer, disposes.
  local jprofs disposed="" ref_p="" ref_v="" ref_r="" ref_ev="" jp leased
  jprofs="$(jq -r '.sets | to_entries[] | select((.value.stopping // null) == null and (.value.start_failed // null) == null and (.value.stop_owed // null) == null and ((.value.leases | length) > 0 or .value.constitution_started == true)) | .key' <<<"$cur")"
  if [ -n "$jprofs" ]; then
    IFS=$'\x1f' read -r st reason < <(capacity_read | tr '\t' '\037')
    if [ "$st" != ok ]; then
      # nothing can be judged (and nothing is stopped) on an unread answer
      prof="$(head -n1 <<<"$jprofs")"
      write_placement "$prof" "undetermined" "join refused: ${reason:-capacity unreadable}" "$(fallback_route)" false 0 refused_join
      log "refused: capacity undetermined ($reason); $prof not joined; fallback route $(fallback_route)"; return 5
    fi
    while IFS= read -r jp; do
      [ -n "$jp" ] || continue
      us="$(unit_status_of "$jp")"
      IFS=$'\x1f' read -r v th r <<<"$(verdict_for "$jp" | tr '\t' '\037')"
      local why="" wev=refused_join
      if [ "$us" = degraded ]; then why="unit degraded"; wev=refused_degraded; v=does_not_fit
      else
        case "$us" in running|active) ;; *) why="unit status '${us:-absent}' is not running/active" ;; esac
        if [ -z "$why" ]; then case "$v" in fits|fits_with_reduced_threads) ;; *) why="capacity verdict $v${r:+ ($r)}" ;; esac; fi
      fi
      if [ -z "$why" ]; then
        cur="$(jq -c --arg p "$jp" --arg h "$holder" --arg pid "$pid" --arg pst "$pst" --argjson now "$NOW" --argjson ttl "$ttl" \
          '.sets[$p].leases = ([.sets[$p].leases[] | select(.holder != $h)] + [{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), pid_start:($pst|tonumber? // null), heartbeat_at:$now, ttl:$ttl}])' <<<"$cur")"
        printf '%s\n' "$cur" | leases_save
        write_placement "$jp" "$v" "joined an existing lease set${r:+ ($r)}" local "$(jq -r --arg p "$jp" '.sets[$p].constitution_started == true' <<<"$cur")" "$th" joined
        cache_register "$jp"
        log "lease joined: holder=$holder profile=$jp (capacity $v)"
        echo "$jp"; return 0
      fi
      leased="$(jq -r --arg p "$jp" '.sets[$p].leases | length' <<<"$cur")"
      if [ "$leased" = 0 ] && [ "$(jq -r --arg p "$jp" '.sets[$p].constitution_started == true' <<<"$cur")" = true ]; then
        local drc=0
        log "disposing $jp: no lease left, constitution-started, $why; bounded llmctl stop"
        bounded "$STMO" "$WORK/stop.out" "$LLMCTL" stop "$jp" || drc=$?
        if [ "$drc" = 0 ]; then
          cur="$(jq -c --arg p "$jp" 'del(.sets[$p])' <<<"$cur")"
          printf '%s\n' "$cur" | leases_save
          # the cache holds ONE llmctl-local entry: drop it when it names this model or when no lease set is left
          if [ "$(jq '.sets | length' <<<"$cur")" = 0 ] || jq -e --arg p "$jp" 'any(.endpoints[]?; .provider_id == "llmctl-local" and .model == $p)' "$CACHE" >/dev/null 2>&1; then cache_unregister; fi
          log "disposed $jp: llmctl stop rc 0, set removed (not restarted by this acquire)"
        else
          cur="$(jq -c --arg p "$jp" --argjson now "$NOW" --argjson rc "$drc" --arg why "$why" '.sets[$p].stop_owed = {at:$now, reason:$why} | .sets[$p].stop_failed = {at:$now, rc:$rc}' <<<"$cur")"
          printf '%s\n' "$cur" | leases_save
          log "disposal stop of $jp failed rc=$drc (124/137 = timed out after ${STMO}s); the set is kept (stop_owed) and the stop is retried"
        fi
        disposed="$disposed $jp"
        continue
      fi
      log "refused for $holder: $jp ($why); it keeps its $leased live lease(s) and is not stopped"
      [ -n "$ref_p" ] || { ref_p="$jp"; ref_v="$v"; ref_r="$why"; ref_ev="$wev"; }
    done <<<"$jprofs"
    if [ -n "$ref_p" ]; then
      if [ "$ref_ev" = refused_degraded ]; then write_placement "$ref_p" "does_not_fit" "unit degraded: not joined" "$(fallback_route)" false 0 refused_degraded
      else write_placement "$ref_p" "$ref_v" "join refused: $ref_r" "$(fallback_route)" false 0 refused_join; fi
      log "refused: $ref_p ($ref_r); not joined; fallback route $(fallback_route)"; return 5
    fi
  fi
  if jq -e '[.sets[] | select((.stopping // null) != null)] | length > 0' <<<"$cur" >/dev/null; then
    write_placement "" "undetermined" "a lease set is stopping (refused per §11.4.291(J))" "$(fallback_route)" false 0 refused_stopping
    log "refused: a lease set is stopping; fallback route $(fallback_route)"; return 5
  fi
  IFS=$'\x1f' read -r st reason < <(capacity_read | tr '\t' '\037')
  if [ "$st" != ok ]; then
    write_placement "" "undetermined" "$reason" "$(fallback_route)" false 0 undetermined
    log "undetermined ($reason): no local start; fallback route $(fallback_route)"; return 5
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$n" -lt "$MAXN" ] || break
    # a profile that already has a set (e.g. a failed start whose cleanup stop failed) is never adopted or started again
    if jq -e --arg p "$p" '.sets[$p] != null' <<<"$cur" >/dev/null; then log "candidate $p: a lease set already exists (not joinable); skipped"; continue; fi
    case " $disposed " in *" $p "*) log "candidate $p: stopped by this acquire (hold until the next evaluation, §11.4.291(D))"; continue ;; esac
    line="$(verdict_for "$p")"; IFS=$'\x1f' read -r v th r <<<"$(tr '\t' '\037' <<<"$line")"
    # A unit llmctl already runs was started by someone else (the operator, or a session outside this lease
    # registry): join it as NOT constitution-started, so the last release never stops it (§11.4.291(J)).
    # A unit still starting is neither started again nor claimed.
    us="$(unit_status_of "$p")"
    case "$us" in
      running|active)
        cur="$(jq -c --arg p "$p" --arg h "$holder" --arg pid "$pid" --arg pst "$pst" --argjson now "$NOW" --argjson ttl "$ttl" \
          '.sets[$p] = {constitution_started:false, stopping:null, leases:[{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), pid_start:($pst|tonumber? // null), heartbeat_at:$now, ttl:$ttl}]}' <<<"$cur")"
        printf '%s\n' "$cur" | leases_save
        write_placement "$p" "$v" "already running (not started by the constitution)" local false "$th" joined_running
        cache_register "$p"
        log "joined the already-running unit $p (not constitution-started; it is never stopped by this producer)"
        echo "$p"; return 0 ;;
      starting|activating) log "candidate $p: unit is $us; not started a second time"; continue ;;
    esac
    case "$v" in fits|fits_with_reduced_threads) ;; *) [ "$v" != undetermined ] || any_undet=1; log "candidate $p: $v ($r)"; continue ;; esac
    local src=0
    bounded "$STMO" "$WORK/start.out" "$LLMCTL" start "$p" || src=$?
    if [ "$src" = 0 ]; then
      started=1; n=$((n+1)); prof="${prof:-$p}"
      cur="$(jq -c --arg p "$p" --arg h "$holder" --arg pid "$pid" --arg pst "$pst" --argjson now "$NOW" --argjson ttl "$ttl" \
        '.sets[$p] = {constitution_started:true, started_at:$now, stopping:null, leases:[{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), pid_start:($pst|tonumber? // null), heartbeat_at:$now, ttl:$ttl}]}' <<<"$cur")"
      printf '%s\n' "$cur" | leases_save
      write_placement "$p" "$v" "$r" local true "$th" placed
      cache_register "$p"
      log "started $p ($v, threads=$th); lease holder=$holder; local gateway registered at priority 10"
    elif [ "$src" = 75 ]; then
      log "llmctl start $p refused (75): does_not_fit"
      [ "$out_ev" = start_failed ] || { out_v="does_not_fit"; out_ev="start_refused"; out_r="llmctl start $p refused (75, pressure gate)"; out_p="$p"; out_th="$th"; }
    else
      log "llmctl start $p failed rc=$src: $(head -c 300 "$WORK/start.out.err" 2>/dev/null | tr '\n' ' ')"
      # the capacity verdict stays what was MEASURED; the failure is the event (review 2026-11-12 F5)
      out_v="$v"; out_ev="start_failed"; out_r="llmctl start $p failed rc=$src"; out_p="$p"; out_th="$th"
      # Live T5 (2026-11-12): llmctl can fail AFTER the unit began starting (health not answered in time, or our own
      # bound expired). The unit was not running before (checked above), so this producer started it: stopping it
      # again is the only way it is not left behind with no lease. 75 (pressure gate, no partial start) needs nothing.
      log "start of $p failed after it was requested; stopping it again so no unit is left without a lease"
      local crc=0; bounded "$STMO" "$WORK/stop.out" "$LLMCTL" stop "$p" || crc=$?
      if [ "$crc" != 0 ]; then
        # Round 3 (R2-2): the unit may still run. Keep a set THIS producer owns so it is never adopted as operator-started
        # and the stop is retried by the next acquire or release (the F2 path); no lease, no cache entry.
        log "cleanup stop of $p failed rc=$crc; the set is kept (constitution_started, start_failed, stop_failed) and the stop is retried"
        cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson src "$src" --argjson crc "$crc" \
          '.sets[$p] = {constitution_started:true, started_at:$now, stopping:null, leases:[], start_failed:{at:$now, rc:$src}, stop_failed:{at:$now, rc:$crc}}' <<<"$cur")"
        printf '%s\n' "$cur" | leases_save
        out_r="llmctl start $p failed rc=$src; cleanup stop failed rc=$crc (set kept, stop retried)"
      fi
    fi
  done < <(candidates)
  if [ "$started" = 1 ]; then echo "$prof"; return 0; fi
  if [ "$out_ev" = no_fit ] && [ "$any_undet" = 1 ]; then out_v="undetermined"; out_r="no candidate fits; at least one is undetermined"; fi
  write_placement "$out_p" "$out_v" "$out_r" "$(fallback_route)" false "$out_th" "$out_ev"
  log "no local placement ($out_ev); fallback route $(fallback_route)"; return 5
}

release_locked() {
  local holder="$1" cur prof
  reap_locked
  cur="$(leases_load)"
  cur="$(jq -c --arg h "$holder" '.sets |= map_values(.leases |= map(select(.holder != $h)))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  # EVERY constitution-started set with no lease left (JEV_PLACE_MAX>1 starts several): mark stopping (others refuse),
  # then stop OUTSIDE the lock. The mark names this process (pid + start time) so a dead stopper's mark is cleared.
  local me_start; me_start="$(proc_start "$$")"
  while IFS= read -r prof; do
    [ -n "$prof" ] || continue
    cur="$(jq -c --arg p "$prof" --argjson now "$NOW" --arg pid "$$" --arg pst "$me_start" '.sets[$p].stopping = {at:$now, pid:($pid|tonumber), pid_start:($pst|tonumber? // null)}' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    echo "$prof"
  done < <(jq -r '.sets | to_entries[] | select((.value.leases | length) == 0 and (.value.constitution_started == true) and (.value.stopping // null) == null) | .key' <<<"$cur")
  # an empty set this producer did not start is just forgotten (an operator-started model is never stopped)
  cur="$(jq -c '.sets |= with_entries(select((.value.leases | length) > 0 or .value.constitution_started == true))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
}
finish_stop_locked() { # finish_stop_locked <profile> <stop-rc>
  local cur; cur="$(leases_load)"
  if [ "$2" != 0 ]; then
    # review 2026-11-12 F2: a failed or timed-out stop leaves the model RUNNING. Keep the set (constitution_started,
    # stopping mark) so it is never orphaned; record the failure; the cache entry stays because the model still answers.
    cur="$(jq -c --arg p "$1" --argjson now "$NOW" --argjson rc "$2" '.sets[$p].stop_failed = {at:$now, rc:$rc}' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    write_placement "$1" "" "llmctl stop rc=$2 (failed or timed out); the set is kept and the stop is retried by the next release" local true 0 stop_failed
    return 0
  fi
  cur="$(jq -c --arg p "$1" 'del(.sets[$p])' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  # the cache holds ONE llmctl-local entry; drop it only when no lease set (no local model) is left
  [ "$(jq '.sets | length' <<<"$cur")" != 0 ] || cache_unregister
  write_placement "$1" "" "last lease released; llmctl stop rc=0" "$(fallback_route)" false 0 stopped
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
      src=0; bounded "$STMO" "$WORK/stop.out" "$LLMCTL" stop "$stopprof" || src=$?
      if [ "$src" = 0 ]; then log "last lease released: llmctl stop $stopprof rc=0"
      else log "stop_failed: llmctl stop $stopprof rc=$src (124/137 = timed out after ${STMO}s); the set is kept, retried by the next release"; rrc=6; fi
      with_lock finish_stop_locked "$stopprof" "$src" || rrc=6
    done <<< "$stopprofs"
    exit "$rrc" ;;
  reap) with_lock reap_locked ;;
  status)
    if [ "${1:-}" = "--json" ]; then jq -nc --slurpfile l <(leases_load) --slurpfile p <( [ -f "$PLACEMENT" ] && cat "$PLACEMENT" || echo '{}') '{leases:$l[0], placement:($p[0].placement // null)}'
    else leases_load | jq -r '.sets | to_entries[] | "\(.key): leases=\(.value.leases|length) constitution_started=\(.value.constitution_started) stopping=\(.value.stopping != null)"'
      [ -f "$PLACEMENT" ] && jq -r '.placement | "placement: profile=\(.profile) verdict=\(.verdict) event=\(.event) route=\(.route) reason=\(.reason)"' "$PLACEMENT"; fi ;;
  ""|-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; [ -n "$sub" ] && exit 0 || exit 2 ;;
  enable|disable|switch|auto) echo "jev-place: '$sub' is never run by the constitution (§11.4.291(G))" >&2; exit 2 ;;
  *) echo "jev-place: unknown subcommand '$sub'" >&2; exit 2 ;;
esac
