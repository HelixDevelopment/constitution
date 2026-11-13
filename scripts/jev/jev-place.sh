#!/usr/bin/env bash
# jev-place.sh — capacity-gated LOCAL decision-model placement producer (§11.4.291, stream S4, 2026-11-12).
#
# Reads `llmctl capacity --json` under the §11.4.291(C) contract table, keeps a per-user lease set per profile, starts
# the best fitting systemone-native decide profile ON DEMAND (a session acquires a lease), keeps the llmctl-local entry of
# the decision-endpoint cache (priority 10) as a view DERIVED from the lease registry, and stops the model when the LAST
# lease is released (only a model THIS producer started). It never calls `llmctl enable`, `disable`, `switch` or `auto`;
# every llmctl call is time-bounded and none runs while the lease lock is held.
#
# Usage:
#   jev-place.sh verdict  [--json]               placement state + verdict per candidate profile (no start, no stop)
#   jev-place.sh acquire  <holder> [--pid P] [--ttl S]   take a lease; start a fitting profile if none is running
#   jev-place.sh heartbeat <holder>              refresh a lease (exit 3 when the holder holds no lease)
#   jev-place.sh release  <holder>               drop a lease; the last release stops EVERY constitution-started model
#                                                with no lease left (bounded by the start/stop timeout)
#   jev-place.sh reap                            drop leases whose holder pid is dead or whose heartbeat expired
#   jev-place.sh status   [--json]               lease sets + last placement entry + the current route
# Every subcommand reads the capacity answer once (bounded, outside the lock) and records it on the lease sets under the
# lock: verdict, status, heartbeat, reap and release are re-evaluations too (see "Round 6" below). None of them starts or
# stops a model except acquire (start, disposal stop) and release (last-lease stop).
# Exit codes: 0 done; 2 usage / config error / cannot determine (jq absent);
#             3 heartbeat: the holder holds no lease (released, reaped, released because its endpoint is gone, or never
#               taken): the session must not route locally, a lease is never assumed (§11.4.291(J)(1));
#             4 lease lock timeout: no lease taken, the caller falls back. One exception, logged as such: when an
#               `llmctl start` FAILED and its result could not be recorded, the registry may still hold the holder's lease
#               under the starting mark; `release <holder>` removes it (a release of a holder without a lease is harmless);
#             5 no local placement (no fit / undetermined / start refused / join refused / gateway refused): the
#               placement entry names the fallback route (cloud when a non-placeholder hosted key exists, else none);
#             6 release: an `llmctl stop` failed or timed out. The lease set is KEPT (constitution_started, stopping
#               mark, stop_failed {at, rc}); once the stop mark is cleared (stopper process gone, or older than the stop
#               timeout + 30 s) the next release retries the stop, and the next acquire judges the set like any other
#               lease-less set (joined when its unit is `ok`, stopped when it is degraded or gone). Never orphaned.
# Env (names only):
#   JEV_LLMCTL_BIN (default llmctl), JEV_LLMCTL_TIMEOUT (default 20 s, read calls), JEV_LLMCTL_START_TIMEOUT (default 300 s,
#   start and stop), JEV_PLACE_PROFILES (comma list: candidate order; default = every systemone-native decide profile in
#   llmctl order), JEV_PLACE_MAX (instances to start per acquire, default 1), JEV_LEASE_TTL (default 900 s),
#   JEV_REEVAL_CADENCE (the caller's re-evaluation cadence, consumer DATA, default 300 s; a lease TTL that is not greater
#   than the cadence + the llmctl timeout is a config error and is refused, §11.4.291(J)(1)), JEV_LOCK_TIMEOUT (default
#   10 s), JEV_RECORD_RETRIES (lock waits for the record step after an llmctl start/stop and for the placement record,
#   default 3, at least 1), JEV_PROJECT (the project named in a lease; default the basename of the git top level of the
#   working directory, else null), LLMCTL_TENANT_ID (the tenant key llmctl puts in front of its own unit names),
#   JEV_STATE_DIR / JEV_HOME (state), CMA_PROVIDERS_DIR (endpoint cache dir), LLMCTL_GATEWAY_URL / LLMCTL_CACERT (default
#   from the `llmctl decide status --json` registry, else https://127.0.0.1:8095; https:// only), JEV_NOW_EPOCH (clock
#   seam, ONLY with JEV_TEST=1).
#
# Round 6 (structural, review of 5a9e72be: R5-1, R5-2, R5-14; inventory docs/qa/jev_s3s4_20261112/round6/inventory.md):
# * THE ENDPOINT CACHE IS A DERIVED VIEW (R5-2). The single llmctl-local entry of the per-user endpoint cache is computed
#   at ONE point, derive_cache, which leases_save runs after every write of the lease registry; no other code writes it.
#   It is a function of the registry alone: the entry exists iff the registry holds an https:// gateway and some set
#   holds >= 1 lease, carries no starting / stopping mark and no start_failed / stop_owed record, and its recorded health
#   is `ok`. It names route_pref (the set last placed or joined) when that set is routable, else the model already named
#   when it is still routable, else the first routable set (sorted).
# * HEALTH IS AN OBSERVATION (R5-2). Every subcommand takes an observation ticket under the lock (a counter in obs.seq),
#   reads `llmctl capacity --json` WITHOUT the lock, and records the instance state of every unmarked set under the lock
#   (obs_locked) only when its ticket is newer than the one already recorded on the set, so an older answer never
#   overwrites a newer one. A start that completes records the current counter as the set's floor (state `pending`), so an
#   answer read before the start cannot judge the started set. An undetermined answer records `unknown` (not routable).
#   A held set whose unit is GONE (state absent) has every lease released with reason endpoint_gone (§11.4.291(J)(6));
#   nothing is restarted. A held set whose unit is degraded keeps its leases (the session drains, then releases,
#   §11.4.291(D)(1)) and leaves the cache at once. A route change caused by an observation or a reap is announced and,
#   outside acquire, recorded (event route_changed). The (D)(2) recovery hold window is NOT built: a unit that reads ok
#   again is routed at the next observation.
# * THE RECORD STEP (R5-1). After `llmctl start` returns, its result is recorded under the lock with at most
#   JEV_RECORD_RETRIES lock waits. When every wait expires after a SUCCESSFUL start, the outcome is "lease held, start
#   recorded late": the lease of the holder is in the registry since the start mark, so acquire prints the profile and
#   exits 0; the starting mark is cleared once this process is gone (reap), after which the set is a normal held set that
#   the next observation routes. No further candidate is started after a successful start whose result is not recorded,
#   after a start whose lease was released during the start, or after a failed start whose cleanup stop failed; with
#   JEV_PLACE_MAX > 1 a further start is judged on a FRESH capacity answer read after the previous model is resident. A
#   start mark is refused while ANY set carries a starting or stopping mark, this process's own marks included. The stop
#   record step follows the same retry rule.
# * GATEWAY (R5-14, §11.4.289(I), §11.4.10): only an https:// gateway URL is registered (the key LLMCTL_API_KEY never goes
#   over plain HTTP). An http:// (or malformed) URL from LLMCTL_GATEWAY_URL or the llmctl registry is refused: acquire
#   exits 5 with event gateway_refused and the registry's gateway is cleared (so the derived entry is removed). Applying the
#   default https://127.0.0.1:8095 is logged with its cause.
# * RECORD (R5-3, R5-8): every placement record is written under the lock (bounded retries, else logged "placement record
#   NOT written"; never written unlocked). It carries reason_code, previous {profile, verdict, event, route, evaluated_at},
#   lease {holder, held}, override_id (null: no override path is built) and detection_merged; it is merged into an
#   EXISTING jev-detection.json and a missing one is never created (a fabricated detection record would be a §11.4.279
#   bluff). A lease carries holder, pid, pid_start, heartbeat_at, ttl, project and started_by_this_session.
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
#   An unlimited RLIMIT_NPROC (rlimit_soft null with a measured thread census) is reported as `nproc_unlimited`, distinct
#   from an unmeasured headroom (`nproc_not_measured`); both stay undetermined (an operator decision is owed, R5-13).
# * NO llmctl CALL UNDER THE LEASE LOCK (R4-3): the capacity answer, the candidate list and the gateway URL are read
#   before the lock; a set that needs an llmctl stop or start is MARKED under the lock (`stopping` / `starting`, naming
#   this process), the call runs with the lock released, and the result is recorded under the lock again. A `starting`
#   mark is cleared like a `stopping` mark (starter gone, or older than the stop timeout + 30 s). A set that is starting
#   or stopping refuses a new acquire (event refused_starting / refused_stopping, reason_code endpoint_starting /
#   endpoint_stopping, §11.4.291(J)(3)). When the lease file changed between the capacity read and the lock, the answer
#   is read again (at most 3 times).
# * ONE STOP HELPER (R4-1): every `llmctl stop` (last release, disposal, retry of an owed stop, cleanup after a failed
#   start) goes through do_stop -> finish_stop_locked, which drops the set on success (the derived cache follows) and
#   writes the placement record. After a successful stop the acquire reads the capacity answer again before a start.
# Verdicts (§11.4.291(A)): fits | fits_with_reduced_threads | does_not_fit | undetermined (or null when no capacity
# verdict applies: a join of a running instance, a stop). undetermined is NEVER fits. What HAPPENED is in the separate
# `event` field, closed set: placed | joined | joined_running | no_fit | undetermined | start_failed | start_refused |
# refused_stopping | refused_starting | refused_degraded | refused_join | lease_lock_timeout | stopped | stop_failed |
# endpoint_gone | gateway_refused | route_changed (write_placement refuses any other value).
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
LEASES="$STATE/leases.json"; LOCK="$STATE/placement.lock"; PLACEMENT="$STATE/placement.json"; OBSSEQ="$STATE/obs.seq"
DETECTION="$(jev_detection_file)"
CACHE="$(jev_providers_dir)/jev-endpoints.json"
LLMCTL="${JEV_LLMCTL_BIN:-llmctl}"
RTMO="${JEV_LLMCTL_TIMEOUT:-20}"; STMO="${JEV_LLMCTL_START_TIMEOUT:-300}"
TTL_DEFAULT="${JEV_LEASE_TTL:-900}"; LOCK_TMO="${JEV_LOCK_TIMEOUT:-10}"; MAXN="${JEV_PLACE_MAX:-1}"
CADENCE="${JEV_REEVAL_CADENCE:-300}"; RETRIES="${JEV_RECORD_RETRIES:-3}"
TENANT="${LLMCTL_TENANT_ID:-}"
NOW="$(date +%s)"; [ "${JEV_TEST:-}" != "1" ] || NOW="${JEV_NOW_EPOCH:-$NOW}"
for n in "$RTMO" "$STMO" "$TTL_DEFAULT" "$LOCK_TMO" "$MAXN" "$CADENCE" "$RETRIES"; do case "$n" in ''|*[!0-9]*) echo "jev-place: numeric setting expected, got '$n' (config error)" >&2; exit 2 ;; esac; done
[ "$RETRIES" -ge 1 ] || { echo "jev-place: JEV_RECORD_RETRIES must be at least 1 (config error)" >&2; exit 2; }
log() { printf '[jev-place] %s\n' "$*" >&2; }
WORK="$(mktemp -d)"; trap 'rm -rf "${WORK:?}"' EXIT
US=$'\x1f'
PROJECT="${JEV_PROJECT:-}"
if [ -z "$PROJECT" ] && command -v git >/dev/null 2>&1; then PROJECT="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || true)")"; [ "$PROJECT" != "." ] || PROJECT=""; fi
HOLDER=""            # the holder of the running subcommand (acquire / heartbeat / release), named in the placement record
GW_DEFAULT="https://127.0.0.1:8095"

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

# candidates: systemone-native decide profiles (decide capacity protocol), in order (JEV_PLACE_PROFILES wins). Sets
# CAND_RC (0 = the list is an answer). A failed `llmctl decide capacity` is an UNDETERMINED list, never "no candidate"
# (R5-7): the caller reports undetermined, never does_not_fit. Call it in the current shell (not in $(...)).
CAND_RC=0
candidates() {
  CAND_RC=0
  if [ -n "${JEV_PLACE_PROFILES:-}" ]; then printf '%s\n' "${JEV_PLACE_PROFILES//,/$'\n'}"; return 0; fi
  bounded "$RTMO" "$WORK/dcap.raw" "$LLMCTL" decide capacity --json || CAND_RC=$?
  [ "$CAND_RC" = 0 ] || return 0
  if ! jq -r '(.decision_instances // {}) | to_entries[] | select(.value.protocol == "systemone-native") | .key' "$WORK/dcap.raw" 2>/dev/null; then
    CAND_RC=65   # an answer that is not JSON is not a list
  fi
  return 0
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
    | if any(.unknown_profiles[]?; . == $p) then out("unknown"; "undetermined"; 0; "unknown profile")
      elif $e == null then out("unknown"; "undetermined"; 0; "profile absent from capacity output")
      elif ($e.threads|type) != "number" or ($e.reasons|type) != "array" then out("unknown"; "undetermined"; 0; "threads/reasons missing")
      elif $e.verdict == "running" then
        if ($own | length) == 0 then out("unknown"; "undetermined"; 0; "verdict running but llmctl reports no own unit \($key)")
        elif ($sts | all(. == "ok" or . == "degraded")) | not then out("unknown"; "undetermined"; 0; "unit status \($sts | join(",")) is not ok/degraded")
        elif any($sts[]; . == "degraded") then out("degraded"; "does_not_fit"; 0; "unit degraded: \([$own[] | .reasons[]?] | join("; "))")
        else out("ok"; ""; 0; "running instance, unit status ok") end
      elif ($own | length) > 0 then out("unknown"; "undetermined"; 0; "an own unit \($key) is reported but the verdict is \($e.verdict // "null"), not running")
      elif $e.verdict == "undetermined" then out("unknown"; "undetermined"; 0; "llmctl verdict undetermined: \($e.reasons | join("; "))")
      elif (($e.verdict // "") | IN("fits","fits_with_reduced_threads","does_not_fit")) | not then out("unknown"; "undetermined"; 0; "verdict outside the closed set")
      elif $e.verdict == "does_not_fit" then out("absent"; "does_not_fit"; $e.threads; ($e.reasons | join("; ")))
      elif ($np|type) != "number" then
        # R5-13: llmctl 3.4.1 reports headroom null both when RLIMIT_NPROC is unlimited (rlimit_soft null, census read) and
        # when the census is unreadable (user_threads null); they are different facts, both undetermined here
        (if ((.host.nproc|type) == "object") and (.host.nproc | has("rlimit_soft")) and .host.nproc.rlimit_soft == null
            and ((.host.nproc.user_threads|type) == "number")
         then out("absent"; "undetermined"; $e.threads; "nproc_unlimited: RLIMIT_NPROC is unlimited (measured: rlimit_soft null, \(.host.nproc.user_threads) user threads); whether an unlimited limit admits a start is an operator decision (§11.4.291(C)), so the verdict stays undetermined")
         else out("absent"; "undetermined"; $e.threads; "nproc_not_measured: RLIMIT_NPROC headroom not measured") end)
      elif $np < $e.threads then out("absent"; "does_not_fit"; $e.threads; "nproc headroom \($np) < threads")
      elif .pressure.ok == false then out("absent"; "does_not_fit"; $e.threads; "pressure: \((.pressure.reasons // []) | join("; "))")
      else out("absent"; $e.verdict; $e.threads; ($e.reasons | join("; "))) end' "$WORK/cap.json"
}

hosted_key_var() { local v; for v in TYPESAFE_API_KEY OPENROUTER_API_KEY; do [ "$(key_state "$v" | cut -f1)" = real ] && { echo "$v"; return 0; }; done; return 0; }

# write_placement <profile> <verdict|""> <reason> <route> <started> <threads> <event> [reason_code] (caller holds the lock)
write_placement() {
  local kv code merged=false prev held=false
  kv="$(hosted_key_var)"
  case "$2" in ""|fits|fits_with_reduced_threads|does_not_fit|undetermined) ;; *) log "internal: verdict '$2' outside the closed set"; return 2 ;; esac
  case "${7:-}" in placed|joined|joined_running|no_fit|undetermined|start_failed|start_refused|refused_stopping|refused_starting|refused_degraded|refused_join|lease_lock_timeout|stopped|stop_failed|endpoint_gone|gateway_refused|route_changed) ;;
    *) log "internal: event '${7:-}' outside the closed set"; return 2 ;; esac
  code="${8:-}"
  if [ -z "$code" ]; then
    case "$7" in refused_stopping) code=endpoint_stopping ;; refused_starting) code=endpoint_starting ;; endpoint_gone) code=endpoint_gone ;;
      lease_lock_timeout) code=lease_lock_timeout ;; gateway_refused) code=gateway_refused ;; esac
  fi
  prev="$(jq -c '.placement // {} | {profile, verdict, event, route, evaluated_at}' "$PLACEMENT" 2>/dev/null || echo null)"
  [ -n "$prev" ] || prev=null
  if [ -n "$HOLDER" ] && leases_load | jq -e --arg h "$HOLDER" 'any(.sets[]?.leases[]?; .holder == $h)' >/dev/null 2>&1; then held=true; fi
  if [ -f "$DETECTION" ] && jq -e . "$DETECTION" >/dev/null 2>&1; then merged=true; fi
  jq -nc --arg p "$1" --arg v "$2" --arg r "$3" --arg route "$4" --argjson st "$5" --arg th "${6:-0}" --arg ev "${7:-}" --arg kv "$kv" --argjson now "$NOW" \
     --arg code "$code" --argjson prev "$prev" --arg holder "$HOLDER" --argjson held "$held" --argjson merged "$merged" \
     --slurpfile cap <(jq -c '{host:{mem_total_mb:.host.mem_total_mb, mem_available_mb:.host.mem_available_mb, usable_mem_mb:.host.usable_mem_mb, load:.host.load, nproc_headroom:(.host.nproc.headroom // null), nproc_rlimit_soft:(.host.nproc.rlimit_soft // null)}, reserve:{mem_reserved_mb:.reserve.mem_reserved_mb, cpus_reserved:.reserve.cpus_reserved}, pressure:.pressure, time:.time}' "$WORK/cap.json" 2>/dev/null || echo '{}') \
     '{placement:{profile:(if $p=="" then null else $p end), verdict:(if $v=="" then null else $v end), event:(if $ev=="" then null else $ev end),
                 reason_code:(if $code=="" then null else $code end), reason:$r, route:$route, key_variable:(if $route=="cloud" then $kv else null end),
                 constitution_started:$st, threads:($th|tonumber? // 0),
                 lease:(if $holder=="" then null else {holder:$holder, held:$held} end),
                 override_id:null, override_note:"no override path is built (§11.4.291(A.1) waiver / attestation not implemented); undetermined is never lifted",
                 previous:$prev, detection_merged:$merged,
                 inputs:($cap[0] // {}), source:"llmctl capacity --json (schema llmctl.capacity/1)", evaluated_at:$now}}' > "$WORK/pl.json"
  jev_write_atomic "$PLACEMENT" < "$WORK/pl.json"
  if [ "$merged" = true ]; then
    if jq -c --slurpfile pl "$WORK/pl.json" '. + $pl[0]' "$DETECTION" > "$WORK/det.json" 2>/dev/null; then jev_write_atomic "$DETECTION" < "$WORK/det.json"
    else log "placement entry not merged into $DETECTION (merge failed)"; fi
  fi
}
# record_placement <write_placement args...>: write the record under the lock, with up to RETRIES lock waits; when every
# wait expires the record is logged as NOT written (R5-3). Never written without the lock.
record_placement() {
  local i=0 rc
  while [ "$i" -lt "$RETRIES" ]; do
    rc=0; with_lock write_placement "$@" || rc=$?
    [ "$rc" = 4 ] || return 0
    i=$((i+1))
  done
  log "placement record NOT written: the lease lock could not be taken ($RETRIES waits of ${LOCK_TMO}s); event ${7:-} reason: ${3:-}"
  return 0
}

fallback_route() { if [ -n "$(hosted_key_var)" ]; then echo cloud; else echo none; fi; }
# the route decision traffic takes now: local while the (derived) cache holds an llmctl-local entry, else the fallback
current_route() { if [ -f "$CACHE" ] && jq -e 'any(.endpoints[]?; .provider_id == "llmctl-local")' "$CACHE" >/dev/null 2>&1; then echo local; else fallback_route; fi; }

# gateway_url -> sets GW_URL GW_CA GW_SRC; rc 1 (GW_WHY set) when the URL is refused. NEVER called under the lock (it may
# run `llmctl decide status`). Only https:// is accepted (§11.4.289(I), §11.4.10: the key never goes over plain HTTP).
GW_URL=""; GW_CA=""; GW_SRC=""; GW_WHY=""
gateway_url() {
  local rc=0 line
  if [ -n "${LLMCTL_GATEWAY_URL:-}" ]; then GW_URL="$LLMCTL_GATEWAY_URL"; GW_CA="${LLMCTL_CACERT:-}"; GW_SRC="LLMCTL_GATEWAY_URL"
  else
    bounded "$RTMO" "$WORK/st.raw" "$LLMCTL" decide status --json || rc=$?
    if [ "$rc" != 0 ]; then
      GW_URL="$GW_DEFAULT"; GW_CA=""; GW_SRC="default"
      log "gateway: llmctl decide status exit $rc; default applied: $GW_DEFAULT"
    else
      line="$(jq -r '[.registry.services[]? | select((.labels.kind // "") == "gateway")][0] as $g | if $g == null then "" else "\($g.url // "")\u001f\($g.labels.ca_file // "")" end' "$WORK/st.raw" 2>/dev/null || true)"
      if [ -z "$line" ] || [ -z "${line%%"$US"*}" ]; then
        GW_URL="$GW_DEFAULT"; GW_CA=""; GW_SRC="default"
        log "gateway: no gateway listed in the llmctl registry (or its output is unreadable); default applied: $GW_DEFAULT"
      else
        GW_URL="${line%%"$US"*}"; GW_CA="${line#*"$US"}"; GW_SRC="llmctl decide status registry"
      fi
    fi
  fi
  case "$GW_URL" in
    https://*) jev_check_url "$GW_URL" && return 0
               GW_WHY="the gateway URL from $GW_SRC is malformed"; return 1 ;;
    *) GW_WHY="the gateway URL from $GW_SRC is not https:// (only https is registered: the key LLMCTL_API_KEY never goes over plain HTTP, §11.4.289(I), §11.4.10)"; return 1 ;;
  esac
}

leases_load() { [ -s "$LEASES" ] && jq -e . "$LEASES" >/dev/null 2>&1 && cat "$LEASES" || echo '{"sets":{}}'; }
# leases_save (content on stdin; caller holds the lock): the registry write, then THE one cache derivation point
leases_save() { jev_write_atomic "$LEASES"; derive_cache || log "endpoint cache could not be derived (rc $?)"; }
leases_hash() { if [ -f "$LEASES" ]; then cksum < "$LEASES"; else echo none; fi; }

# derive_cache (caller holds the lock): the llmctl-local entry of the endpoint cache as a pure function of leases.json
# (R5-2). Other entries of the cache (hosted providers written by other tools) are kept. The file is rewritten only when
# the result differs; it is not created when there is nothing to add.
derive_cache() {
  local cur new
  if [ -s "$CACHE" ] && jq -e . "$CACHE" >/dev/null 2>&1; then cur="$(jq -c . "$CACHE")"
  else
    jq -e '[.sets // {} | to_entries[] | select(((.value.leases // [])|length) > 0)] | length > 0' "$LEASES" >/dev/null 2>&1 || return 0
    cur='{"version":1,"generated_at":0,"ttl":300,"endpoints":[]}'
  fi
  new="$(jq -c --argjson c "$cur" '
    ([.sets // {} | to_entries[] | select(((.value.leases // []) | length) > 0 and (.value.stopping // null) == null and (.value.starting // null) == null
        and (.value.start_failed // null) == null and (.value.stop_owed // null) == null and ((.value.health.state // "") == "ok")) | .key] | sort) as $r
    | (.gateway // null) as $g
    | ([$c.endpoints[]? | select(.provider_id == "llmctl-local")] | first // null) as $old
    | (.route_pref // null) as $rp
    | . as $reg
    | (if ($g | type) == "object" and ((($g.url // "") | tostring) | startswith("https://")) and ($r | length) > 0 then
         (if $rp != null and any($r[]; . == $rp) then $rp
          elif $old != null and any($r[]; . == $old.model) then $old.model
          else $r[0] end) as $m
         | {provider_id:"llmctl-local", base_url:$g.url, model:$m, key_var:"LLMCTL_API_KEY", ca_file:($g.ca // ""), priority:10,
            probed_at:($reg.sets[$m].health.at // 0),
            reason:"derived from the lease registry: held, unmarked, unit observed ok (scripts/jev/jev-place.sh derive_cache, §11.4.291)"}
       else null end) as $e
    | $c | .endpoints = (([.endpoints[]? | select(.provider_id != "llmctl-local")] + (if $e == null then [] else [$e] end)) | sort_by(.priority // 100))' "$LEASES")" || return 1
  [ "$new" = "$cur" ] && return 0
  mkdir -p "$(dirname "$CACHE")"
  printf '%s\n' "$new" | jev_write_atomic "$CACHE"
}

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
  # stop timeout + 30 s (§11.4.291(J)); the set is then judged like any other set by the next observation / acquire
  while IFS="$US" read -r prof mk sat spid sst; do
    [ -n "$prof" ] || continue
    # a mark without a pid cannot name a dead process: only its age clears it (review R2 nit RS3)
    arc=0; if [ "$spid" != "null" ] && [ -n "$spid" ]; then pid_alive "$spid" "$sst" || arc=$?; fi
    if [ "$arc" = 1 ] || [ $(( NOW - sat )) -gt $(( STMO + 30 )) ]; then
      log "cleared the $mk mark of $prof (its process is gone or the mark is older than the stop timeout); recovery recorded at the next observation"
      out="$(jq -c --arg p "$prof" --arg m "$mk" --argjson now "$NOW" '.sets[$p][$m] = null | .sets[$p].mark_cleared = {mark:$m, at:$now}' <<<"$out")"
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
# lease_json <holder> <pid> <pid_start> <ttl> <started_by_this_session true|false> -> one lease object (R5-8)
lease_json() {
  jq -nc --arg h "$1" --arg pid "$2" --arg pst "$3" --argjson now "$NOW" --argjson ttl "$4" --argjson sb "$5" --arg proj "$PROJECT" \
    '{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), pid_start:($pst|tonumber? // null), heartbeat_at:$now, ttl:$ttl,
      project:(if $proj=="" then null else $proj end), started_by_this_session:$sb}'
}

# ---- observation (R5-2) ----------------------------------------------------------------------------------------------
take_ticket_locked() { # caller holds the lock: next observation ticket + the lease-file hash at that moment
  local c=0
  [ -s "$OBSSEQ" ] && c="$(head -c 32 "$OBSSEQ" | tr -dc '0-9')"
  c=$(( ${c:-0} + 1 ))
  printf '%s\n' "$c" | jev_write_atomic "$OBSSEQ"
  TICKET="$c"; OBS_H0="$(leases_hash)"
}
obs_counter() { local c=0; [ -s "$OBSSEQ" ] && c="$(head -c 32 "$OBSSEQ" | tr -dc '0-9')"; echo "${c:-0}"; }
# observe_read -> 0 (OBS_TICKET, OBS_H0, CAP_ST, CAP_REASON, $WORK/cap.json set) or 4 (lock timeout: nothing read)
OBS_TICKET=""; OBS_H0=""; CAP_ST=""; CAP_REASON=""
observe_read() {
  TICKET=""; with_lock take_ticket_locked || return 4
  OBS_TICKET="$TICKET"
  IFS="$US" read -r CAP_ST CAP_REASON < <(capacity_read)
}
# obs_locked (caller holds the lock; OBS_TICKET + CAP_ST from observe_read): records the instance state of every unmarked
# set when this ticket is newer than the recorded one; a held set whose unit is gone has every lease released
# (endpoint_gone, §11.4.291(J)(6)); a lease-less set this producer did not start is forgotten (never stopped).
GONE_WRITTEN=0
obs_locked() {
  [ -n "$OBS_TICKET" ] || return 0
  local cur out p st v th r det gone="" newer holders
  declare -A gdet=()
  cur="$(leases_load)"; out="$cur"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ "$CAP_ST" = ok ]; then IFS="$US" read -r st v th r <<<"$(inst_state "$p")"; else st=unknown; v=undetermined; r="capacity undetermined: ${CAP_REASON:-unread}"; fi
    newer="$(jq -r --arg p "$p" --argjson t "$OBS_TICKET" '((.sets[$p].health.seq // -1) < $t)' <<<"$out")"
    [ "$newer" = true ] || continue
    out="$(jq -c --arg p "$p" --arg s "$st" --arg r "$r" --argjson t "$OBS_TICKET" --argjson now "$NOW" '.sets[$p].health = {state:$s, reason:$r, seq:$t, at:$now}' <<<"$out")"
    if [ "$st" = absent ] && [ "$(jq -r --arg p "$p" '((.sets[$p].leases // []) | length) > 0 and (.sets[$p].start_failed // null) == null and (.sets[$p].stop_owed // null) == null' <<<"$out")" = true ]; then
      det="$r"; [ -n "$det" ] || det="no own unit reported, verdict ${v:-null}"
      holders="$(jq -r --arg p "$p" '[.sets[$p].leases[].holder] | join(",")' <<<"$out")"
      out="$(jq -c --arg p "$p" --arg d "$det" --argjson now "$NOW" '.sets[$p].leases = [] | .sets[$p].gone = {at:$now, detail:$d}' <<<"$out")"
      gone+=" $p"; gdet[$p]="$det|$holders"
    fi
  done < <(jq -r '.sets | to_entries[] | select((.value.stopping // null) == null and (.value.starting // null) == null) | .key' <<<"$cur")
  out="$(jq -c '.sets |= with_entries(select(((.value.leases // []) | length) > 0 or .value.constitution_started == true))' <<<"$out")"
  [ "$out" = "$cur" ] || printf '%s\n' "$out" | leases_save
  for p in $gone; do
    det="${gdet[$p]%|*}"; holders="${gdet[$p]##*|}"
    log "endpoint_gone: the unit of $p is gone ($det); every lease released (holders $holders); route $(current_route); nothing is restarted (§11.4.291(J)(6))"
    write_placement "$p" "" "endpoint_gone: $det" "$(current_route)" "$(jq -r --arg p "$p" '.sets[$p].constitution_started == true' "$LEASES")" 0 endpoint_gone || true
    GONE_WRITTEN=1
  done
}
# finalize_locked <reap 0|1> <record 0|1> (caller holds the lock): reap (optional), observe, and announce a route change;
# record it as route_changed when <record> is 1 (acquire writes its own record) and no endpoint_gone record was written
finalize_locked() {
  local r0 r1; GONE_WRITTEN=0
  r0="$(current_route)"
  [ "$1" = 0 ] || reap_locked
  obs_locked
  r1="$(current_route)"
  if [ "$r0" != "$r1" ]; then
    log "route changed: $r0 -> $r1 (the endpoint cache is derived from the lease registry and the observed unit state, §11.4.291(D)(1)(F))"
    if [ "$2" = 1 ] && [ "$GONE_WRITTEN" = 0 ]; then write_placement "" "" "route_changed: $r0 -> $r1" "$r1" false 0 route_changed || true; fi
  fi
}

cmd_verdict() {
  local json="${1:-}" p line first=1 cst=ok
  candidates > "$WORK/cands"
  [ "$CAND_RC" = 0 ] || cst=undetermined
  if observe_read; then with_lock finalize_locked 1 1 || log "verdict: the observation could not be recorded (lock rc $?)"
  else log "verdict: lease lock timeout; the observation is not recorded"; IFS="$US" read -r CAP_ST CAP_REASON < <(capacity_read); fi
  {
    printf '['
    if [ "$CAP_ST" = ok ]; then
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        line="$(inst_state "$p")"
        [ "$first" = 1 ] || printf ','; first=0
        jq -nc --arg p "$p" --arg l "$line" '($l|split("\u001f")) as $f | {profile:$p, state:$f[0], verdict:(if $f[1] == "" then null else $f[1] end), threads:($f[2]|tonumber? // 0), reason:($f[3] // "")}'
      done < "$WORK/cands"
    fi
    printf ']'
  } > "$WORK/v.json"
  if [ "$json" = "--json" ]; then
    jq -c --arg st "$CAP_ST" --arg r "${CAP_REASON:-}" --arg cs "$cst" --arg crc "$CAND_RC" \
      '{contract:$st, contract_reason:$r, candidates_contract:$cs, candidates_reason:(if $cs == "ok" then "" else "llmctl decide capacity exit \($crc)" end), candidates:.}' "$WORK/v.json"
  else
    [ "$CAP_ST" = ok ] || log "capacity contract: undetermined ($CAP_REASON) - no local start"
    [ "$cst" = ok ] || log "candidate list undetermined: llmctl decide capacity exit $CAND_RC"
    jq -r '.[] | "\(.profile)\t\(.state)\t\(.verdict // "null")\tthreads=\(.threads)\t\(.reason)"' "$WORK/v.json"
  fi
}

# ---- the ONE stop helper (review R4-1, R4-3) -----------------------------------------------------------------------
# finish_stop_locked <profile> <stop-rc> <kind> (caller holds the lock). kind: release | dispose | owed | cleanup.
#   rc 0     : the set is removed (the derived cache follows), placement `stopped`.
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
  write_placement "$p" "" "llmctl stop $p rc=$rc ($kind; failed or timed out); the set is kept and the stop is retried" "$(current_route)" true 0 stop_failed
}
# do_stop <profile> <kind> -> 0 stopped, 1 the stop failed, 4 the result could not be recorded (every record wait timed out).
# The set was marked `stopping` (or is a release set) under the lock; the bounded stop itself runs WITHOUT the lock.
do_stop() {
  local p="$1" kind="$2" src=0 frc=4 i=0
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
  while [ "$i" -lt "$RETRIES" ]; do
    frc=0; with_lock finish_stop_locked "$p" "$src" "$kind" || frc=$?
    [ "$frc" = 4 ] || break
    i=$((i+1)); log "record step for llmctl stop $p: lock wait $i/$RETRIES timed out"
  done
  if [ "$frc" != 0 ]; then log "the result of llmctl stop $p (rc $src) could not be recorded (lock rc $frc); the stopping mark expires and the next release / acquire re-judges the set"; return 4; fi
  [ "$src" = 0 ]
}

# ---- acquire: plan under the lock, llmctl calls outside it ------------------------------------------------------------
# plan_locked <holder> <pid> <ttl> <leases-hash|""> (caller holds the lock; NO llmctl call). Reads $WORK/cap.json
# (CAP_ST, OBS_TICKET) and $WORK/cands (CAND_RC). Sets: PLAN_STOPS (lines "<profile><US><kind>", each set already marked
# stopping), START_CANDS (lines "<profile><US><verdict><US><threads><US><reason>"), and the result F_RC / F_OUT plus the
# placement record F_P F_V F_R F_ST F_TH F_EV F_CODE. rc 99: the lease file changed after the ticket (the caller reads
# again).
declare -A DISPOSE_WHY=()
plan_locked() {
  local holder="$1" pid="$2" ttl="$3" h0="$4" cur pst mark p jp v th r st hs leased cs lline ref_p="" ref_v="" ref_r="" ref_ev="" any_undet=0 foreign held=""
  if [ -n "$h0" ] && [ "$(leases_hash)" != "$h0" ]; then return 99; fi
  PLAN_STOPS=""; START_CANDS=""; F_RC=5; F_OUT=""; F_P=""; F_V="does_not_fit"; F_R="no candidate profile fits"; F_ST=false; F_TH=0; F_EV=no_fit; F_CODE=""
  pst="$(lease_obj_args "$pid")"; mark="$(me_mark)"
  # the https gateway read before the lock is part of the registry: the derived cache uses it
  cur="$(leases_load)"
  cur="$(jq -c --arg u "$GW_URL" --arg ca "$GW_CA" --arg src "$GW_SRC" '.gateway = {url:$u, ca:$ca, source:$src}' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  finalize_locked 1 0
  cur="$(leases_load)"
  # marks set by OTHER processes before this plan (our own marks below are added after this read)
  foreign="$(jq -r '[.sets | to_entries[] | (if (.value.starting // null) != null then "starting" elif (.value.stopping // null) != null then "stopping" else empty end)] | first // ""' <<<"$cur")"
  # (A) owed stops: a failed start whose cleanup stop failed, or a failed disposal stop (never joined; retried)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    cur="$(jq -c --arg p "$p" --argjson m "$mark" '.sets[$p].stopping = $m' <<<"$cur")"
    PLAN_STOPS+="$p${US}owed"$'\n'
  done < <(jq -r '.sets | to_entries[] | select(((.value.start_failed // null) != null or (.value.stop_owed // null) != null) and (.value.stopping // null) == null and (.value.starting // null) == null and (.value.leases | length) == 0) | .key' <<<"$cur")
  [ -z "$PLAN_STOPS" ] || printf '%s\n' "$cur" | leases_save
  # (B) every existing, unmarked set, judged by its RECORDED health (the observation above, or a newer one): joined when
  # ok; a lease-less constitution-started set whose unit is degraded or gone is stopped (dispose); a set that still has a
  # live lease is never stopped here; nothing is judged or stopped on an undetermined answer or an unknown state.
  local jprofs; jprofs="$(jq -r '.sets | to_entries[] | select((.value.stopping // null) == null and (.value.starting // null) == null and (.value.start_failed // null) == null and (.value.stop_owed // null) == null) | .key' <<<"$cur")"
  if [ -n "$jprofs" ]; then
    while IFS= read -r jp; do
      [ -n "$jp" ] || continue
      hs="$(jq -r --arg p "$jp" '.sets[$p].health.state // "unknown"' <<<"$cur")"
      r="$(jq -r --arg p "$jp" '.sets[$p].health.reason // "not observed"' <<<"$cur")"
      leased="$(jq -r --arg p "$jp" '.sets[$p].leases | length' <<<"$cur")"
      cs="$(jq -r --arg p "$jp" '.sets[$p].constitution_started == true' <<<"$cur")"
      if [ "$hs" = ok ]; then
        cur="$(jq -c --arg p "$jp" --arg h "$holder" --argjson l "$(lease_json "$holder" "$pid" "$pst" "$ttl" false)" \
          '.sets[$p].leases = ([.sets[$p].leases[] | select(.holder != $h)] + [$l]) | .route_pref = $p' <<<"$cur")"
        printf '%s\n' "$cur" | leases_save
        F_RC=0; F_OUT="$jp"; F_P="$jp"; F_V=""; F_R="joined an existing lease set ($r)"; F_ST="$cs"; F_TH=0; F_EV=joined
        log "lease joined: holder=$holder profile=$jp ($r)"
        return 0
      fi
      if [ "$leased" = 0 ] && [ "$cs" = true ] && { [ "$hs" = degraded ] || [ "$hs" = absent ]; }; then
        log "disposing $jp: no lease left, constitution-started, instance $hs ($r); bounded llmctl stop outside the lock"
        cur="$(jq -c --arg p "$jp" --argjson m "$mark" '.sets[$p].stopping = $m' <<<"$cur")"
        printf '%s\n' "$cur" | leases_save
        DISPOSE_WHY[$jp]="instance $hs: $r"
        PLAN_STOPS+="$jp${US}dispose"$'\n'
        continue
      fi
      log "refused for $holder: $jp (instance $hs: $r); it keeps its $leased lease(s) and is not stopped; it is not routed"
      if [ -z "$ref_p" ]; then
        ref_p="$jp"; ref_v=undetermined; ref_r="instance $hs: $r"; ref_ev=refused_join
        [ "$hs" != degraded ] || { ref_v=does_not_fit; ref_ev=refused_degraded; }
      fi
    done <<<"$jprofs"
    if [ -n "$ref_p" ]; then
      F_P="$ref_p"; F_V="$ref_v"; F_R="join refused: $ref_r"; F_EV="$ref_ev"
      [ "$ref_ev" != refused_degraded ] || F_R="unit degraded: not joined ($ref_r)"
      log "refused: $ref_p ($ref_r); not joined; fallback route $(fallback_route)"; return 0
    fi
  fi
  # (C) a set another process is starting or stopping refuses this acquire (§11.4.291(J)(3))
  if [ -n "$foreign" ]; then
    F_V=undetermined; F_EV="refused_$foreign"; F_CODE="endpoint_$foreign"
    F_R="endpoint_$foreign: a lease set is $foreign; this acquire is refused and falls back (§11.4.291(J)(3))"
    log "refused ($F_CODE): a lease set is $foreign; fallback route $(fallback_route)"; return 0
  fi
  if [ "$CAP_ST" != ok ]; then
    F_V=undetermined; F_R="$CAP_REASON"; F_EV=undetermined
    log "undetermined ($CAP_REASON): no local start; fallback route $(fallback_route)"; return 0
  fi
  if [ "$CAND_RC" != 0 ]; then
    F_V=undetermined; F_R="candidate list undetermined: llmctl decide capacity exit $CAND_RC (R5-7: never read as no candidate)"; F_EV=undetermined
    log "undetermined: the candidate list could not be read (llmctl decide capacity exit $CAND_RC); no local start; fallback route $(fallback_route)"; return 0
  fi
  # (D) adoption first: a candidate llmctl already runs for this user (ok) and that has no set was started by someone
  # else (the operator, or a session outside this registry): join it as NOT constitution-started (never stopped by this
  # producer, §11.4.291(G)(J)); routing adds no resident footprint, so it is preferred over starting another model.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    jq -e --arg p "$p" '.sets[$p] != null' <<<"$cur" >/dev/null && continue
    IFS="$US" read -r st v th r <<<"$(inst_state "$p")"
    [ "$st" = ok ] || continue
    cur="$(jq -c --arg p "$p" --argjson l "$(lease_json "$holder" "$pid" "$pst" "$ttl" false)" \
      '.sets[$p] = {constitution_started:false, stopping:null, starting:null, leases:[$l]} | .route_pref = $p' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    obs_locked   # this answer saw the unit ok: record it on the new set (the derived cache then routes it)
    F_RC=0; F_OUT="$p"; F_P="$p"; F_V=""; F_R="already running (not started by the constitution; $r)"; F_ST=false; F_TH=0; F_EV=joined_running
    log "joined the already-running unit $p (not constitution-started; it is never stopped by this producer)"
    return 0
  done < "$WORK/cands"
  # (E) start candidates (started one by one after this plan, outside the lock)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if jq -e --arg p "$p" '.sets[$p] != null' <<<"$cur" >/dev/null; then log "candidate $p: a lease set already exists (not joinable); skipped"; continue; fi
    case " ${DISPOSED:-} " in *" $p "*) log "candidate $p: stopped by this acquire (hold until the next evaluation, §11.4.291(D))"; held+="$p "; continue ;; esac
    lline="$(inst_state "$p")"; IFS="$US" read -r st v th r <<<"$lline"
    case "$st:$v" in
      absent:fits|absent:fits_with_reduced_threads) START_CANDS+="$p$US$v$US$th$US$r"$'\n' ;;
      degraded:*) log "candidate $p: unit degraded ($r); not started a second time, not adopted" ;;
      *) [ "$v" != undetermined ] || any_undet=1; log "candidate $p: $st/$v ($r)" ;;
    esac
  done < "$WORK/cands"
  if [ "$any_undet" = 1 ]; then F_V=undetermined; F_R="no candidate fits; at least one is undetermined"; fi
  # a profile this acquire stopped is not restarted by it (no restart loop, §11.4.291(J)(6)): say so in the record
  if [ -n "$held" ]; then F_R="$F_R; held until the next evaluation (stopped by this acquire, never restarted by it): ${held% }"; fi
  return 0
}

# mark_start_locked <profile> <holder> <pid> <pid_start> <ttl> -> 0 marked (set created with a `starting` mark naming this
# process and the holder's lease), 1 not startable any more (a set exists, or ANY set is starting or stopping - this
# process's own marks included, R5-1)
mark_start_locked() {
  local p="$1" cur
  reap_locked
  cur="$(leases_load)"
  if jq -e --arg p "$p" '.sets[$p] != null' <<<"$cur" >/dev/null; then return 1; fi
  if jq -e 'any(.sets[]?; (.starting // null) != null or (.stopping // null) != null)' <<<"$cur" >/dev/null; then return 1; fi
  cur="$(jq -c --arg p "$p" --argjson l "$(lease_json "$2" "$3" "$4" "$5" true)" --argjson m "$(me_mark)" \
    '.sets[$p] = {constitution_started:true, started_at:null, stopping:null, starting:$m, leases:[$l]}' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
}
# finish_start_locked <profile> <start-rc> -> sets START_RES placed | released | refused | failed (and marks `stopping`
# for released / failed: the caller then runs do_stop <profile> release|cleanup)
finish_start_locked() {
  local p="$1" src="$2" cur leased floor
  cur="$(leases_load)"
  leased="$(jq -r --arg p "$p" '(.sets[$p].leases // []) | length' <<<"$cur")"
  if [ "$src" = 0 ]; then
    if [ "$leased" = 0 ]; then
      cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson m "$(me_mark)" '.sets[$p] = ((.sets[$p] // {constitution_started:true, leases:[]}) + {started_at:$now, starting:null, stopping:$m})' <<<"$cur")"
      START_RES=released
    else
      # floor: an observation whose ticket was taken before this point read the capacity before the start, so it never
      # judges the started set (an absent unit there would otherwise be read as endpoint_gone)
      floor="$(obs_counter)"
      cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson f "$floor" \
        '.sets[$p].starting = null | .sets[$p].started_at = $now | .sets[$p].health = {state:"pending", reason:"started; not observed yet", seq:$f, at:$now} | .route_pref = $p' <<<"$cur")"
      START_RES=placed
    fi
  elif [ "$src" = 75 ]; then
    cur="$(jq -c --arg p "$p" 'del(.sets[$p])' <<<"$cur")"
    START_RES=refused
  else
    cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson src "$src" --argjson m "$(me_mark)" \
      '.sets[$p] = {constitution_started:true, started_at:$now, starting:null, stopping:$m, leases:[], start_failed:{at:$now, rc:$src}}' <<<"$cur")"
    START_RES=failed
  fi
  printf '%s\n' "$cur" | leases_save
}

gw_refuse_locked() { # the refused gateway is cleared from the registry: the derived cache drops the llmctl-local entry
  local cur; cur="$(leases_load)"
  cur="$(jq -c '.gateway = null' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
}

cmd_acquire() {
  local holder="$1" pid="$2" ttl="$3" rc tries round p kind v th r st src started=0 n=0 prof="" pst mrc frc i
  local out_v="" out_ev="" out_r="" out_p="" out_th=0 stops_done
  pst="$(lease_obj_args "$pid")"
  if ! gateway_url; then
    log "gateway refused: $GW_WHY; no local placement"
    rc=0; with_lock gw_refuse_locked || rc=$?
    [ "$rc" != 4 ] || log "the refused gateway could not be cleared from the registry (lock timeout); the next acquire retries"
    record_placement "" "" "gateway_refused: $GW_WHY" "$(fallback_route)" false 0 gateway_refused
    return 5
  fi
  candidates > "$WORK/cands"
  DISPOSED=""
  for round in 1 2; do
    stops_done=0; tries=0
    while :; do
      observe_read || return 4
      rc=0; if [ "$tries" -lt 3 ]; then with_lock plan_locked "$holder" "$pid" "$ttl" "$OBS_H0" || rc=$?; else with_lock plan_locked "$holder" "$pid" "$ttl" "" || rc=$?; fi
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
    record_placement "$F_P" "$F_V" "$F_R" "$(current_route)" "$F_ST" "$F_TH" "$F_EV"
    echo "$F_OUT"; return 0
  fi
  while IFS="$US" read -r p v th r; do
    [ -n "$p" ] || continue
    [ "$n" -lt "$MAXN" ] || break
    if [ "$n" -gt 0 ]; then
      # R5-1: a model started by THIS acquire is resident now; the next start is judged on a fresh answer
      log "candidate $p: reading a fresh capacity answer (a model started by this acquire is resident now)"
      IFS="$US" read -r CAP_ST CAP_REASON < <(capacity_read)
      if [ "$CAP_ST" != ok ]; then log "candidate $p: the fresh answer is undetermined ($CAP_REASON); no further start"; break; fi
      IFS="$US" read -r st v th r <<<"$(inst_state "$p")"
      case "$st:$v" in absent:fits|absent:fits_with_reduced_threads) ;; *) log "candidate $p: $st/$v on the fresh answer ($r); not started"; continue ;; esac
    fi
    mrc=0; with_lock mark_start_locked "$p" "$holder" "$pid" "$pst" "$ttl" || mrc=$?
    if [ "$mrc" = 4 ]; then
      if [ "$n" = 0 ]; then return 4; fi
      log "candidate $p: lease lock timeout before its start mark; no further start"; break
    fi
    if [ "$mrc" != 0 ]; then log "candidate $p: no longer startable (a set exists or a set is starting/stopping)"; continue; fi
    src=0; bounded "$STMO" "$WORK/start.out" "$LLMCTL" start "$p" || src=$?
    START_RES=""; frc=4; i=0
    while [ "$i" -lt "$RETRIES" ]; do
      frc=0; with_lock finish_start_locked "$p" "$src" || frc=$?
      [ "$frc" = 4 ] || break
      i=$((i+1)); log "record step for llmctl start $p (rc $src): lock wait $i/$RETRIES timed out"
    done
    if [ "$frc" != 0 ]; then
      if [ "$src" = 0 ]; then
        started=1; n=$((n+1)); prof="${prof:-$p}"
        out_p="$prof"; out_v="$v"; out_ev=placed; out_th="$th"
        out_r="lease held, start recorded late: llmctl start $p rc 0; the record step could not take the lock ($RETRIES waits of ${LOCK_TMO}s)"
        log "lease held, start recorded late: llmctl start $p rc 0, but the record step could not take the lease lock ($RETRIES waits of ${LOCK_TMO}s). The lease of $holder is in the registry since the start mark; the starting mark is cleared once this process is gone and the next observation routes the set. No further candidate is started."
        break
      fi
      log "llmctl start $p rc $src: its result could not be recorded ($RETRIES lock waits); the registry may still hold the lease of $holder under the starting mark: release it. No further candidate is started."
      if [ "$n" = 0 ]; then return 4; fi
      break
    fi
    case "$START_RES" in
      placed)
        started=1; n=$((n+1)); prof="${prof:-$p}"
        out_p="$prof"; out_v="$v"; out_ev=placed; out_r="$r"; out_th="$th"
        log "started $p ($v, threads=$th); lease holder=$holder; it is routed once an observation newer than the start reads its unit ok" ;;
      released)
        log "started $p but its lease was released during the start; stopping it again; no further candidate is started"
        do_stop "$p" release || true
        break ;;
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
        if ! do_stop "$p" cleanup; then
          out_r="llmctl start $p failed rc=$src; cleanup stop failed (set kept, stop retried)"
          log "the cleanup stop of $p failed: the model may be resident, so no further candidate is started"
          break
        fi ;;
    esac
  done <<<"$START_CANDS"
  if [ "$started" = 1 ]; then
    # observe the started model(s): the set is routed only after an observation newer than its start (derive_cache)
    if observe_read; then frc=0; with_lock finalize_locked 0 0 || frc=$?; [ "$frc" = 0 ] || log "the observation after the start could not be recorded (lock rc $frc); the next observation routes the set"
    else log "the observation after the start could not take the lock; the next observation routes the set"; fi
    record_placement "$out_p" "$out_v" "$out_r" "$(current_route)" true "$out_th" placed
    echo "$prof"; return 0
  fi
  if [ -n "$out_ev" ]; then F_P="$out_p"; F_V="$out_v"; F_R="$out_r"; F_TH="$out_th"; F_EV="$out_ev"; F_CODE=""; fi
  record_placement "$F_P" "$F_V" "$F_R" "$(fallback_route)" false "$F_TH" "$F_EV" "$F_CODE"
  log "no local placement ($F_EV); fallback route $(fallback_route)"; return 5
}

release_locked() {
  local holder="$1" cur prof mark r0 r1 stops=""
  r0="$(current_route)"
  finalize_locked 1 0
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
    echo "$prof"; stops+=" $prof"
  done < <(jq -r '.sets | to_entries[] | select((.value.leases | length) == 0 and (.value.constitution_started == true) and (.value.stopping // null) == null and (.value.starting // null) == null) | .key' <<<"$cur")
  # an empty set this producer did not start is just forgotten (an operator-started model is never stopped)
  cur="$(jq -c '.sets |= with_entries(select((.value.leases | length) > 0 or .value.constitution_started == true))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  r1="$(current_route)"
  # a route change with no stop to record (the stop writes its own record) is recorded here
  if [ "$r0" != "$r1" ] && [ -z "$stops" ] && [ "$GONE_WRITTEN" = 0 ]; then
    log "route changed: $r0 -> $r1 (release)"
    write_placement "" "" "route_changed: $r0 -> $r1 (release of $holder)" "$r1" false 0 route_changed || true
  fi
}

hb_locked() { # hb_locked <holder> (caller holds the lock) -> 0 refreshed, 3 the holder holds no lease
  local c
  finalize_locked 1 1
  c="$(leases_load)"
  if ! jq -e --arg h "$1" 'any(.sets[]?.leases[]?; .holder == $h)' <<<"$c" >/dev/null; then
    log "heartbeat: holder $1 holds no lease (released, reaped, released because its endpoint is gone, or never taken); route locally only after a new acquire - a lease is never assumed (§11.4.291(J)(1))"
    return 3
  fi
  c="$(jq -c --arg h "$1" --argjson now "$NOW" '.sets |= map_values(.leases |= map(if .holder == $h then .heartbeat_at = $now else . end))' <<<"$c")"
  printf '%s\n' "$c" | leases_save
}

sub="${1:-}"; shift || true
case "$sub" in
  verdict) cmd_verdict "${1:-}" ;;
  acquire)
    holder="${1:-}"; shift || true; pid=""; ttl="$TTL_DEFAULT"
    jev_check_word "$holder" || { echo "jev-place: acquire needs a holder id ([A-Za-z0-9._-]+)" >&2; exit 2; }
    while [ $# -gt 0 ]; do case "$1" in --pid) pid="${2:-}"; shift 2 ;; --ttl) ttl="${2:-}"; shift 2 ;; *) echo "jev-place: unknown arg $1" >&2; exit 2 ;; esac; done
    case "$pid" in *[!0-9]*) echo "jev-place: --pid must be an integer" >&2; exit 2 ;; esac
    case "$ttl" in ''|*[!0-9]*) echo "jev-place: --ttl must be an integer" >&2; exit 2 ;; esac
    # R5-4, §11.4.291(J)(1): a lease must outlive one re-evaluation cycle plus one bounded llmctl call
    if [ "$ttl" -le $(( CADENCE + RTMO )) ]; then
      echo "jev-place: lease TTL ${ttl}s is not greater than the re-evaluation cadence ${CADENCE}s (JEV_REEVAL_CADENCE) + the llmctl timeout ${RTMO}s (JEV_LLMCTL_TIMEOUT): config error, refused (§11.4.291(J)(1))" >&2
      exit 2
    fi
    HOLDER="$holder"
    rc=0; cmd_acquire "$holder" "$pid" "$ttl" || rc=$?
    if [ "$rc" = 4 ]; then record_placement "" "undetermined" "lease_lock_timeout: no lease taken" "$(fallback_route)" false 0 lease_lock_timeout; log "lease_lock_timeout: no lease taken"; fi
    exit "$rc" ;;
  heartbeat)
    holder="${1:-}"; jev_check_word "$holder" || { echo "jev-place: heartbeat needs a holder id" >&2; exit 2; }
    HOLDER="$holder"
    observe_read || { log "heartbeat: lease lock timeout (the heartbeat is not recorded)"; exit 4; }
    rc=0; with_lock hb_locked "$holder" || rc=$?
    [ "$rc" != 4 ] || log "heartbeat: lease lock timeout (the heartbeat is not recorded)"
    exit "$rc" ;;
  release)
    holder="${1:-}"; jev_check_word "$holder" || { echo "jev-place: release needs a holder id" >&2; exit 2; }
    HOLDER="$holder"
    observe_read || { log "release: lock timeout (rc 4)"; exit 4; }
    rc=0; stopprofs="$(with_lock release_locked "$holder")" || rc=$?
    [ "$rc" = 0 ] || { log "release: lock timeout (rc $rc)"; exit "$rc"; }
    rrc=0
    while IFS= read -r stopprof; do
      [ -n "$stopprof" ] || continue
      # a stop can take as long as a start (model unload, unit shutdown): bounded by the START/STOP timeout, not RTMO
      do_stop "$stopprof" release || rrc=6
    done <<< "$stopprofs"
    exit "$rrc" ;;
  reap)
    observe_read || { log "reap: lock timeout (rc 4)"; exit 4; }
    with_lock finalize_locked 1 1 ;;
  status)
    if observe_read; then with_lock finalize_locked 1 1 || log "status: the observation could not be recorded (lock rc $?)"
    else log "status: lease lock timeout; the observation is not recorded"; fi
    if [ "${1:-}" = "--json" ]; then jq -nc --slurpfile l <(leases_load) --slurpfile p <( [ -f "$PLACEMENT" ] && cat "$PLACEMENT" || echo '{}') --arg route "$(current_route)" '{leases:$l[0], placement:($p[0].placement // null), route:$route}'
    else leases_load | jq -r '.sets | to_entries[] | "\(.key): leases=\(.value.leases|length) constitution_started=\(.value.constitution_started) stopping=\(.value.stopping != null) starting=\((.value.starting // null) != null) health=\(.value.health.state // "unobserved")"'
      echo "route: $(current_route)"
      [ -f "$PLACEMENT" ] && jq -r '.placement | "placement: profile=\(.profile) verdict=\(.verdict) event=\(.event) route=\(.route) reason=\(.reason)"' "$PLACEMENT"; fi ;;
  ""|-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; [ -n "$sub" ] && exit 0 || exit 2 ;;
  enable|disable|switch|auto) echo "jev-place: '$sub' is never run by the constitution (§11.4.291(G))" >&2; exit 2 ;;
  *) echo "jev-place: unknown subcommand '$sub'" >&2; exit 2 ;;
esac
