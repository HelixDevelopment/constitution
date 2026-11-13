#!/usr/bin/env bash
# test_s4_placement.sh — S4 (2026-11-12): the capacity-gated local placement producer scripts/jev/jev-place.sh (§11.4.291).
# GATE-LOGIC tests (§11.4.289(C)(2)): a stub llmctl (tests/jev/fixtures/bin-place/llmctl) answers `capacity --json` from a
# declared file; these prove the producer DECIDES correctly, never that a local model runs (the live run is T5 under docs/qa).
#   P1  fits -> first systemone-native candidate started, lease taken, gateway in the endpoint cache at priority 10, route local
#   P2  a second holder joins the running set: no second start
#   P3  release of one of two holders: no stop; release of the last: llmctl stop, cache entry removed, set removed
#   P4  wrong schema -> undetermined, rc 5, no start; route none without a key, cloud (key NAME only) with a real hosted key
#   P5  capacity exit 1 -> undetermined; capacity slower than the bound -> undetermined (bounded call)
#   P6  candidate a does_not_fit, b fits -> b started
#   P7  RLIMIT_NPROC headroom absent -> undetermined, never fits;  P8 headroom < threads -> does_not_fit
#   P9  a degraded unit for the profile -> does_not_fit;  P10 start refused (75) -> rc 5, no lease
#   P11 dead-pid holder reaped on the next acquire; the reap itself never stops the model; acquire rejoins (no second start)
#   P12 a set marked stopping refuses a new acquire (rc 5);  P13 lease lock held -> rc 4, no lease
#   P14 enable/disable/switch/auto refused (rc 2) and never sent to llmctl;  P15 verdict --json lists only systemone-native
#   P16 heartbeat refreshes; a pid-less lease past its TTL is reaped;  P17 pressure.ok=false -> does_not_fit
#   (round 2, review 2026-11-12 F2/F5)
#   P21 a FAILED last-release stop keeps the lease set (constitution_started, stopping mark), records event stop_failed,
#       returns rc 6; the next release (stopper gone) re-attempts the stop and only a successful stop removes the set
#   P22 the release stop is bounded by the START/STOP timeout (JEV_LLMCTL_START_TIMEOUT), not by the read timeout;
#       a stop slower than that bound is a stop_failed (the set is kept)
#   P23 JEV_PLACE_MAX=2: both started profiles are stopped on the last release (not only the first set)
#   P24 a pid holder is identified by pid AND process start time: a reused pid (start time differs) is reaped
#   P25 joining an existing set re-checks the unit (degraded -> refused, rc 5, no lease) and re-registers the cache entry
#   P26 every placement verdict is in the closed set {fits, fits_with_reduced_threads, does_not_fit, undetermined} or null;
#       start/stop outcomes are in the separate `event` field
#   (round 3, review R2-2/R2-3/R2-6)
#   P27 a failed start whose cleanup stop ALSO fails keeps a set {constitution_started:true, leases:[], start_failed,
#       stop_failed}; a later acquire never joins or adopts it (never constitution_started:false), retries the stop, and
#       a successful retry (acquire or release) removes it; the unit is never left running untracked
#   P28 joining an existing set is an ALLOW-list: unit failed / starting / absent, verdict does_not_fit and an
#       undetermined capacity answer are all refused (rc 5, event refused_join, no lease, the gateway NOT registered)
#   P29 the recorded pid start time is /proc/<pid>/stat field 22 (independent python oracle, not the function itself)
#   P30 a zombie holder (pid exists, start time matches, empty cmdline) is dead and reaped
#   P31 a stop mark that names no pid is kept until it is older than the stop timeout + 30 s (never "dead stopper")
#   P32 every placement event written by these scenarios is in the closed event set
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; FIXTURES="$HERE/fixtures"
# shellcheck source=lib_assert.sh
. "$HERE/lib_assert.sh"
PLACE="${S4_PLACE_UNDER_TEST:-$ROOT/scripts/jev/jev-place.sh}"

assert_eqx() { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (expected [$1] got [$2])"; fi; }
has()  { if grep -q -- "$2" "$1" 2>/dev/null; then ok "$3"; else fail "$3 (no [$2] in $1)"; fi; }
hasnt(){ if grep -q -- "$2" "$1" 2>/dev/null; then fail "$3 (found [$2] in $1)"; else ok "$3"; fi; }

# cap <file> [a-verdict] [b-verdict] [headroom|none] [unit-status-for-a] [pressure-ok]
cap() {
  jq -n --arg va "${2:-fits}" --arg vb "${3:-fits}" --arg hr "${4:-5000}" --arg us "${5:-}" --arg pok "${6:-true}" '
    {schema:"llmctl.capacity/1", time:1700000000,
     host:({mem_total_mb:20000, mem_available_mb:18000, usable_mem_mb:15000, load:{}}
           + (if $hr=="none" then {} else {nproc:{headroom:($hr|tonumber)}} end)),
     reserve:{mem_reserved_mb:4000, cpus_reserved:4}, pressure:{ok:($pok=="true"), reasons:(if $pok=="true" then [] else ["psi full"] end)},
     llmctl:{units:(if $us=="" then [] else [{profile:"decide-a", status:$us}] end)},
     fallback:{recommended:"local", key_variable:null}, unknown_profiles:[],
     profiles:{"decide-a":{verdict:$va, threads:3, reasons:[]}, "decide-b":{verdict:$vb, threads:3, reasons:[]},
               "decide-x":{verdict:"fits", threads:3, reasons:[]}}}' > "$1"
}
fresh() {
  make_fixture_env s4
  export PATH="$FIXTURES/bin-place:$PATH" JEV_TEST=1 PLACE_CAP_JSON="$T/cap.json" JEV_LOCK_TIMEOUT=2
  unset PLACE_CAP_RC PLACE_CAP_SLEEP PLACE_START_RC PLACE_STOP_RC PLACE_STOP_SLEEP JEV_LLMCTL_TIMEOUT JEV_LLMCTL_START_TIMEOUT JEV_PLACE_MAX LLMCTL_GATEWAY_URL
  : > "$STUB_LOG/llmctl.log"
  CACHE="$CMA_PROVIDERS_DIR/jev-endpoints.json"
}
starts() { grep -c '^llmctl start' "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
stops()  { grep -c '^llmctl stop' "$STUB_LOG/llmctl.log" 2>/dev/null || true; }

# ---- P1 / P2 / P3 ------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"
out="$("$PLACE" acquire s1 --pid $$ 2>"$T/e1")"; rc=$?
assert_eqx 0 "$rc" "P1 acquire rc 0 when a candidate fits"
assert_eqx decide-a "$out" "P1 first systemone-native candidate (decide-a) placed"
assert_eqx 1 "$(starts)" "P1 exactly one llmctl start"
assert_eqx 10 "$(jq -r '.endpoints[] | select(.provider_id=="llmctl-local") | .priority' "$CACHE")" "P1 local gateway in the cache at priority 10"
assert_eqx https://127.0.0.1:18095 "$(jq -r '.endpoints[] | select(.provider_id=="llmctl-local") | .base_url' "$CACHE")" "P1 gateway URL from the llmctl registry"
assert_eqx LLMCTL_API_KEY "$(jq -r '.endpoints[] | select(.provider_id=="llmctl-local") | .key_var' "$CACHE")" "P1 key referenced by NAME"
assert_eqx local "$(jq -r .placement.route "$JEV_STATE_DIR/placement.json")" "P1 placement route local"
assert_eqx true "$(jq -r '.sets["decide-a"].constitution_started' "$JEV_STATE_DIR/leases.json")" "P1 set records constitution_started"
out="$("$PLACE" acquire s2 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a" "$rc $out" "P2 second holder joins decide-a"
assert_eqx 1 "$(starts)" "P2 no second start"
assert_eqx 2 "$(jq -r '.sets["decide-a"].leases|length' "$JEV_STATE_DIR/leases.json")" "P2 two leases"
"$PLACE" release s1 2>/dev/null; assert_eqx 0 "$(stops)" "P3 release of one of two holders does not stop"
"$PLACE" release s2 2>"$T/e3"; rc=$?
assert_eqx 0 "$rc" "P3 last release rc 0"
assert_eqx 1 "$(stops)" "P3 last release stops the model"
has "$STUB_LOG/llmctl.log" '^llmctl stop decide-a$' "P3 stop names the started profile"
assert_eqx 0 "$(jq '[.endpoints[] | select(.provider_id=="llmctl-local")] | length' "$CACHE")" "P3 cache entry removed"
assert_eqx null "$(jq -c '.sets["decide-a"]' "$JEV_STATE_DIR/leases.json")" "P3 lease set removed"
[ ! -e "$STUB_LOG/running.decide-a" ] && ok "P3 stub reports the model stopped" || fail "P3 model still running"

# ---- P4 ------------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"; jq '.schema="llmctl.capacity/2"' "$T/cap.json" > "$T/c2" && mv "$T/c2" "$T/cap.json"
"$PLACE" acquire s1 >/dev/null 2>"$T/e4"; rc=$?
assert_eqx 5 "$rc" "P4 wrong schema -> rc 5"
assert_eqx 0 "$(starts)" "P4 no start under undetermined"
assert_eqx undetermined "$(jq -r .placement.verdict "$JEV_STATE_DIR/placement.json")" "P4 verdict undetermined"
assert_eqx none "$(jq -r .placement.route "$JEV_STATE_DIR/placement.json")" "P4 route none without a key"
SECRET="tsk-s4-$(date +%N)-realvalue"
export TYPESAFE_API_KEY="$SECRET"
"$PLACE" acquire s1 >/dev/null 2>>"$T/e4"
assert_eqx cloud "$(jq -r .placement.route "$JEV_STATE_DIR/placement.json")" "P4 route cloud with a real hosted key"
assert_eqx TYPESAFE_API_KEY "$(jq -r .placement.key_variable "$JEV_STATE_DIR/placement.json")" "P4 key variable NAME recorded"
if grep -rqF -- "$SECRET" "$JEV_STATE_DIR" "$T/e4" "$CMA_PROVIDERS_DIR"; then fail "P4 key VALUE leaked"; else ok "P4 key value never written"; fi
unset TYPESAFE_API_KEY

# ---- P5 ------------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"; export PLACE_CAP_RC=1
"$PLACE" acquire s1 >/dev/null 2>"$T/e5"; rc=$?
assert_eqx "5 0" "$rc $(starts)" "P5 capacity exit 1 -> rc 5, no start"
has "$T/e5" "exit 1" "P5 reason names the exit code"
unset PLACE_CAP_RC; export PLACE_CAP_SLEEP=5 JEV_LLMCTL_TIMEOUT=1
t0=$(date +%s); "$PLACE" acquire s1 >/dev/null 2>"$T/e5b"; rc=$?; t1=$(date +%s)
assert_eqx "5 0" "$rc $(starts)" "P5 slow capacity -> rc 5, no start"
[ $((t1 - t0)) -le 4 ] && ok "P5 llmctl call bounded ($((t1 - t0))s)" || fail "P5 call not bounded ($((t1 - t0))s)"
has "$T/e5b" "timed out" "P5 reason says timed out"
unset PLACE_CAP_SLEEP JEV_LLMCTL_TIMEOUT

# ---- P6 - P10, P17 ---------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json" does_not_fit fits
out="$("$PLACE" acquire s1 --pid $$ 2>/dev/null)"; assert_eqx decide-b "$out" "P6 does_not_fit a skipped, b placed"
hasnt "$STUB_LOG/llmctl.log" '^llmctl start decide-a' "P6 a never started"
fresh; cap "$T/cap.json" fits fits none
"$PLACE" acquire s1 >/dev/null 2>"$T/e7"; rc=$?
assert_eqx "5 0" "$rc $(starts)" "P7 nproc headroom unmeasured -> rc 5, no start (undetermined is never fits)"
has "$T/e7" "RLIMIT_NPROC" "P7 reason names RLIMIT_NPROC"
fresh; cap "$T/cap.json" fits does_not_fit 2
"$PLACE" acquire s1 >/dev/null 2>"$T/e8"; rc=$?
assert_eqx "5 0" "$rc $(starts)" "P8 headroom < threads -> does_not_fit, no start"
fresh; cap "$T/cap.json" fits does_not_fit 5000 degraded
"$PLACE" acquire s1 >/dev/null 2>"$T/e9"; rc=$?
assert_eqx "5 0" "$rc $(starts)" "P9 degraded unit -> does_not_fit, no start"
has "$T/e9" "unit degraded" "P9 reason unit degraded"
fresh; cap "$T/cap.json" fits does_not_fit; export PLACE_START_RC=75
"$PLACE" acquire s1 >/dev/null 2>"$T/e10"; rc=$?
assert_eqx 5 "$rc" "P10 start refused (75) -> rc 5"
assert_eqx null "$(jq -c '.sets["decide-a"]' "$JEV_STATE_DIR/leases.json" 2>/dev/null || echo null)" "P10 no lease after a refused start"
unset PLACE_START_RC
fresh; cap "$T/cap.json" fits fits 5000 "" false
"$PLACE" acquire s1 >/dev/null 2>"$T/e17"; rc=$?
assert_eqx "5 0" "$rc $(starts)" "P17 pressure not ok -> no start"

# ---- P11 ----------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"
dead="$(bash -c 'echo $$')"   # a pid that has already exited
kill -0 "$dead" 2>/dev/null && fail "P11 setup: pid $dead unexpectedly alive"
"$PLACE" acquire ghost --pid "$dead" >/dev/null 2>&1
assert_eqx 1 "$(starts)" "P11 setup: one start"
"$PLACE" reap 2>"$T/e11"
assert_eqx 0 "$(stops)" "P11 reap never stops the model"
assert_eqx 0 "$(jq -r '.sets["decide-a"].leases|length' "$JEV_STATE_DIR/leases.json")" "P11 dead holder reaped"
out="$("$PLACE" acquire live --pid $$ 2>/dev/null)"
assert_eqx "decide-a 1" "$out $(starts)" "P11 acquire rejoins the running constitution-started model (no second start)"

# ---- P12 / P13 -------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"
echo '{"sets":{"decide-a":{"constitution_started":true,"started_at":1700000000,"stopping":{"at":1700000000,"pid":1},"leases":[]}}}' > "$JEV_STATE_DIR/leases.json"
"$PLACE" acquire s1 >/dev/null 2>"$T/e12"; rc=$?
assert_eqx "5 0" "$rc $(starts)" "P12 stopping set refuses a new acquire"
fresh; cap "$T/cap.json"
( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock 8; sleep 6 ) & lk=$!; sleep 0.5
JEV_LOCK_TIMEOUT=1 "$PLACE" acquire s1 >/dev/null 2>"$T/e13"; rc=$?
kill "$lk" 2>/dev/null; wait "$lk" 2>/dev/null
assert_eqx "4 0" "$rc $(starts)" "P13 lock held -> rc 4, no start"
has "$T/e13" "lease_lock_timeout" "P13 reason lease_lock_timeout"

# ---- P14 / P15 / P16 -------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"
for s in enable disable switch auto; do "$PLACE" "$s" decide-a >/dev/null 2>"$T/e14"; rc=$?; assert_eqx 2 "$rc" "P14 '$s' refused"; has "$T/e14" "never run by the constitution" "P14 '$s' refused as a forbidden verb, not as an unknown one"; done
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1; "$PLACE" release s1 >/dev/null 2>&1
if grep -Eq '^llmctl (enable|disable|switch|auto)' "$STUB_LOG/llmctl.log"; then fail "P14 a forbidden llmctl verb was sent"; else ok "P14 no enable/disable/switch/auto ever sent"; fi
fresh; cap "$T/cap.json"
assert_eqx "decide-a,decide-b" "$("$PLACE" verdict --json 2>/dev/null | jq -r '[.candidates[].profile]|join(",")')" "P15 candidates = systemone-native only"
assert_eqx 0 "$(starts)" "P15 verdict never starts"
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --ttl 100 >/dev/null 2>&1
JEV_NOW_EPOCH=1700000050 "$PLACE" heartbeat s1
assert_eqx 1700000050 "$(jq -r '.sets["decide-a"].leases[0].heartbeat_at' "$JEV_STATE_DIR/leases.json")" "P16 heartbeat refreshed"
JEV_NOW_EPOCH=1700000200 "$PLACE" reap 2>/dev/null
assert_eqx 0 "$(jq -r '.sets["decide-a"].leases|length' "$JEV_STATE_DIR/leases.json")" "P16 pid-less lease past TTL reaped"


# ---- P18 / P19 / P20 (live T5 finding 2026-11-12: a start that fails after the unit began starting must not leave it
# behind; an operator-started unit is never claimed or stopped) -----------------------------------------------------
fresh; cap "$T/cap.json"; export PLACE_START_RC=1
"$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e18"; rc=$?
assert_eqx 5 "$rc" "P18 failed start -> no local placement (rc 5)"
assert_eqx 0 "$(find "$STUB_LOG" -maxdepth 1 -name 'running.*' | wc -l)" "P18 a unit the producer tried to start and that failed is stopped again (no orphan)"
has "$T/e18" "stopping it again" "P18 the cleanup stop is logged"
fresh; cap "$T/cap.json"; export PLACE_START_RC=75
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
assert_eqx 0 "$(stops)" "P19 a start refused by the pressure gate (75, no partial start) sends no stop"
unset PLACE_START_RC
fresh; cap "$T/cap.json" fits fits 5000 running
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1; rc=$?
assert_eqx "0 0" "$rc $(grep -c '^llmctl start decide-a' "$STUB_LOG/llmctl.log")" "P20 an already-running unit is joined, never started again"
assert_eqx false "$(jq -r '.sets["decide-a"].constitution_started' "$JEV_STATE_DIR/leases.json")" "P20 an operator-started unit is recorded constitution_started=false"
"$PLACE" release s1 >/dev/null 2>&1
assert_eqx 0 "$(stops)" "P20 releasing the last lease of an operator-started unit never stops it"

# ---- P21 failed stop keeps the set; the next release retries ------------------------------------------------------
pl() { jq -r "$1" "$JEV_STATE_DIR/placement.json"; }
closed_verdict() { case "$(pl '.placement.verdict')" in fits|fits_with_reduced_threads|does_not_fit|undetermined|null) ok "P26 $1: verdict $(pl '.placement.verdict') in the closed set" ;; *) fail "P26 $1: verdict $(pl '.placement.verdict') outside the closed set" ;; esac; }
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
export PLACE_STOP_RC=1
"$PLACE" release s1 >/dev/null 2>"$T/e21"; rc=$?
assert_eqx 6 "$rc" "P21 a failed stop on the last release returns rc 6 (never 0)"
assert_eqx 1 "$(stops)" "P21 one stop attempted"
assert_eqx true "$(jq -r '.sets["decide-a"].constitution_started' "$JEV_STATE_DIR/leases.json")" "P21 the set is KEPT with constitution_started=true"
assert_eqx true "$(jq -r '.sets["decide-a"].stopping != null' "$JEV_STATE_DIR/leases.json")" "P21 the stopping mark is kept"
assert_eqx 1 "$(jq -r '.sets["decide-a"].stop_failed.rc' "$JEV_STATE_DIR/leases.json")" "P21 the set records the failed stop rc"
assert_eqx stop_failed "$(pl '.placement.event')" "P21 placement event stop_failed"
closed_verdict "stop_failed"
assert_eqx 1 "$(jq '[.endpoints[] | select(.provider_id=="llmctl-local")] | length' "$CACHE")" "P21 the cache entry stays while the model runs"
has "$T/e21" "stop_failed" "P21 stop_failed is logged"
unset PLACE_STOP_RC
"$PLACE" release s1 >/dev/null 2>"$T/e21b"; rc=$?
assert_eqx 0 "$rc" "P21 the next release re-attempts the stop and succeeds (rc 0)"
assert_eqx 2 "$(stops)" "P21 a second stop was sent (retry)"
assert_eqx null "$(jq -c '.sets["decide-a"]' "$JEV_STATE_DIR/leases.json")" "P21 only a successful stop removes the set"
assert_eqx stopped "$(pl '.placement.event')" "P21 placement event stopped after the retry"
closed_verdict "stopped"
[ ! -e "$STUB_LOG/running.decide-a" ] && ok "P21 model stopped after the retry" || fail "P21 model still running after the retry"
# a failed stop followed by an acquire joins the kept set (no second start, still constitution-started)
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
PLACE_STOP_RC=1 "$PLACE" release s1 >/dev/null 2>&1
out="$("$PLACE" acquire s2 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a 1" "$rc $out $(starts)" "P21 after a failed stop a new acquire joins the kept model (no second start)"
assert_eqx true "$(jq -r '.sets["decide-a"].constitution_started' "$JEV_STATE_DIR/leases.json")" "P21 the joined set stays constitution-started (a later release still stops it)"

# ---- P22 the stop uses the stop timeout ---------------------------------------------------------------------------
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
PLACE_STOP_SLEEP=3 JEV_LLMCTL_TIMEOUT=1 JEV_LLMCTL_START_TIMEOUT=10 "$PLACE" release s1 >/dev/null 2>"$T/e22"; rc=$?
assert_eqx 0 "$rc" "P22 a 3 s stop with read timeout 1 s and stop timeout 10 s succeeds (bounded by the stop timeout)"
assert_eqx null "$(jq -c '.sets["decide-a"]' "$JEV_STATE_DIR/leases.json")" "P22 set removed after the slow stop"
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
t0=$(date +%s); PLACE_STOP_SLEEP=8 JEV_LLMCTL_START_TIMEOUT=1 "$PLACE" release s1 >/dev/null 2>"$T/e22b"; rc=$?; t1=$(date +%s)
assert_eqx 6 "$rc" "P22 a stop slower than the stop timeout is stop_failed (rc 6)"
[ $((t1 - t0)) -le 6 ] && ok "P22 the stop is bounded ($((t1 - t0))s)" || fail "P22 the stop was not bounded ($((t1 - t0))s)"
assert_eqx true "$(jq -r '.sets["decide-a"].constitution_started' "$JEV_STATE_DIR/leases.json")" "P22 timed-out stop keeps the set"

# ---- P23 MAXN>1 -----------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"; export JEV_PLACE_MAX=2
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
assert_eqx 2 "$(starts)" "P23 two profiles started with JEV_PLACE_MAX=2"
"$PLACE" release s1 >/dev/null 2>"$T/e23"; rc=$?
assert_eqx "0 2" "$rc $(stops)" "P23 the last release stops BOTH started profiles"
assert_eqx 0 "$(jq '.sets | length' "$JEV_STATE_DIR/leases.json")" "P23 both sets removed"
assert_eqx 0 "$(find "$STUB_LOG" -maxdepth 1 -name 'running.*' | wc -l | tr -d ' ')" "P23 no model left running"
unset JEV_PLACE_MAX

# ---- P24 pid identity ------------------------------------------------------------------------------------------------
if [ -r "/proc/$$/stat" ]; then
  fresh; cap "$T/cap.json"
  "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
  assert_eqx number "$(jq -r '.sets["decide-a"].leases[0].pid_start | type' "$JEV_STATE_DIR/leases.json")" "P24 the lease records the holder's process start time"
  JEV_NOW_EPOCH=1700099999 "$PLACE" reap 2>/dev/null
  assert_eqx 1 "$(jq -r '.sets["decide-a"].leases|length' "$JEV_STATE_DIR/leases.json")" "P24 a live pid holder with a matching start time is kept"
  jq '.sets["decide-a"].leases[0].pid_start = 1' "$JEV_STATE_DIR/leases.json" > "$T/l24" && cp "$T/l24" "$JEV_STATE_DIR/leases.json"
  "$PLACE" reap 2>"$T/e24"
  assert_eqx 0 "$(jq -r '.sets["decide-a"].leases|length' "$JEV_STATE_DIR/leases.json")" "P24 a reused pid (start time differs) is reaped"
  assert_eqx 0 "$(stops)" "P24 the reap never stops the model"
else
  assert_skip "P24 /proc/<pid>/stat unreadable: pid identity falls back to the TTL"
fi

# ---- P25 join of an existing set re-checks the unit and re-registers the cache -----------------------------------------
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
jq '.endpoints = []' "$CACHE" > "$T/c25" && cp "$T/c25" "$CACHE"
out="$("$PLACE" acquire s2 --pid $$ 2>/dev/null)"
assert_eqx decide-a "$out" "P25 second holder joins"
assert_eqx 1 "$(jq '[.endpoints[] | select(.provider_id=="llmctl-local")] | length' "$CACHE")" "P25 the join re-registers the local gateway in the cache"
assert_eqx joined "$(pl '.placement.event')" "P25 placement event joined"
closed_verdict "joined"
cap "$T/cap.json" fits fits 5000 degraded
"$PLACE" acquire s3 --pid $$ >/dev/null 2>"$T/e25"; rc=$?
assert_eqx 5 "$rc" "P25 a degraded unit is not joined (rc 5)"
assert_eqx 2 "$(jq -r '.sets["decide-a"].leases|length' "$JEV_STATE_DIR/leases.json")" "P25 no lease added for the degraded unit"
assert_eqx "does_not_fit" "$(pl '.placement.verdict')" "P25 degraded => does_not_fit"
assert_eqx refused_degraded "$(pl '.placement.event')" "P25 degraded => event refused_degraded (not the generic refused_join)"
has "$T/e25" "degraded" "P25 reason names the degraded unit"
assert_eqx 1 "$(starts)" "P25 no second start"

# ---- P26 closed verdict set for a failed start ------------------------------------------------------------------------
fresh; cap "$T/cap.json" fits does_not_fit; export PLACE_START_RC=1
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
assert_eqx start_failed "$(pl '.placement.event')" "P26 a failed start is recorded as event start_failed"
assert_eqx fits "$(pl '.placement.verdict')" "P26 the verdict stays the measured capacity verdict (fits), not a false does_not_fit"
closed_verdict "start_failed"
unset PLACE_START_RC
fresh; cap "$T/cap.json" does_not_fit does_not_fit
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
assert_eqx "does_not_fit no_fit" "$(pl '"\(.placement.verdict) \(.placement.event)"')" "P26 no candidate fits => does_not_fit, event no_fit"

# ---- P27 failed start + failed cleanup stop (review R2-2) ----------------------------------------------------------------
L() { jq -r "$1" "$JEV_STATE_DIR/leases.json"; }
fresh; cap "$T/cap.json" fits does_not_fit; export PLACE_START_RC=1 PLACE_STOP_RC=1
"$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e27"; rc=$?
assert_eqx 5 "$rc" "P27 failed start -> rc 5"
assert_eqx start_failed "$(pl '.placement.event')" "P27 event start_failed"
assert_eqx "true 0 1 1" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.leases|length) \(.start_failed.rc) \(.stop_failed.rc)"')" "P27 the set is KEPT: constitution_started, no lease, start_failed rc 1, stop_failed rc 1"
assert_eqx 1 "$(ls "$STUB_LOG"/running.decide-a 2>/dev/null | wc -l | tr -d ' ')" "P27 setup: the stub unit still runs after the failed cleanup"
has "$T/e27" "the set is kept" "P27 the kept set is logged"
"$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e27b"; rc=$?
assert_eqx 5 "$rc" "P27 a later acquire (stop still failing) -> rc 5, nothing joined"
assert_eqx "true 0" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.leases|length)"')" "P27 the set is never adopted as operator-started and gets no lease"
case "$(pl '.placement.event')" in joined|joined_running) fail "P27 a later acquire joined the failed-start unit" ;; *) ok "P27 a later acquire does not join the failed-start unit" ;; esac
assert_eqx "1 2" "$(starts) $(stops)" "P27 the later acquire retried the stop (2 stops) and never started again (1 start)"
has "$T/e27b" "retried the cleanup stop" "P27 the retry is logged"
unset PLACE_STOP_RC
"$PLACE" release nobody 2>"$T/e27c"; rc=$?
assert_eqx 0 "$rc" "P27 a release with the stop working -> rc 0"
assert_eqx null "$(L '.sets["decide-a"]')" "P27 the successful stop removes the set"
assert_eqx 0 "$(ls "$STUB_LOG"/running.decide-a 2>/dev/null | wc -l | tr -d ' ')" "P27 the unit is no longer running"
# the acquire path of the retry: stop works again on the next acquire, the set goes, and a fresh start is allowed
fresh; cap "$T/cap.json" fits does_not_fit; export PLACE_START_RC=1 PLACE_STOP_RC=1
"$PLACE" acquire s1 >/dev/null 2>&1
unset PLACE_START_RC PLACE_STOP_RC
out="$("$PLACE" acquire s2 --pid $$ 2>"$T/e27d")"; rc=$?
assert_eqx "0 decide-a" "$rc $out" "P27 acquire retries the stop (rc 0), removes the kept set, then places normally"
assert_eqx "true 1 null" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.leases|length) \(.start_failed)"')" "P27 the new set is a normal constitution-started set"
unset PLACE_START_RC PLACE_STOP_RC

# ---- P28 join allow-list (review R2-3) ------------------------------------------------------------------------------------
for us in failed starting absent; do
  fresh; cap "$T/cap.json" fits does_not_fit
  "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
  jq '.endpoints = []' "$CACHE" > "$T/c28" && cp "$T/c28" "$CACHE"
  if [ "$us" = absent ]; then export PLACE_CAP_RAW=1; else cap "$T/cap.json" fits does_not_fit 5000 "$us"; fi
  "$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e28"; rc=$?
  assert_eqx "5 refused_join" "$rc $(pl '.placement.event')" "P28 unit $us -> join refused (rc 5, event refused_join)"
  assert_eqx 1 "$(L '.sets["decide-a"].leases|length')" "P28 unit $us -> no lease added"
  assert_eqx 0 "$(jq '[.endpoints[] | select(.provider_id=="llmctl-local")] | length' "$CACHE")" "P28 unit $us -> the gateway is NOT registered in the cache"
  unset PLACE_CAP_RAW
done
fresh; cap "$T/cap.json" fits does_not_fit
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
cap "$T/cap.json" does_not_fit does_not_fit
"$PLACE" acquire s2 --pid $$ >/dev/null 2>/dev/null; rc=$?
assert_eqx "5 refused_join does_not_fit" "$rc $(pl '.placement.event') $(pl '.placement.verdict')" "P28 verdict does_not_fit -> join refused"
echo '{"schema":"other"}' > "$T/cap.json"
"$PLACE" acquire s3 --pid $$ >/dev/null 2>"$T/e28u"; rc=$?
has "$T/e28u" "capacity undetermined" "P28 an unreadable capacity answer is refused at the capacity check itself (not later by the unit check)"
assert_eqx "5 refused_join undetermined" "$rc $(pl '.placement.event') $(pl '.placement.verdict')" "P28 undetermined capacity -> join refused (never a join on an unread answer)"
assert_eqx 1 "$(L '.sets["decide-a"].leases|length')" "P28 no lease added on a refused join"
cap "$T/cap.json" fits_with_reduced_threads does_not_fit
out="$("$PLACE" acquire s4 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a joined" "$rc $out $(pl '.placement.event')" "P28 CONTROL: unit running + fits_with_reduced_threads -> joined"

# ---- P32 closed event set ----------------------------------------------------------------------------------------------------
case "$(pl '.placement.event')" in placed|joined|joined_running|no_fit|undetermined|start_failed|start_refused|refused_stopping|refused_degraded|refused_join|lease_lock_timeout|stopped|stop_failed)
  ok "P32 the last placement event is in the closed set" ;; *) fail "P32 event outside the closed set: $(pl '.placement.event')" ;; esac
# P32b the guard itself: write_placement (its real text, cut from the producer) refuses an event outside the set (rc 2,
# nothing written) and accepts one inside it (control)
wp="$(sed -n '/^write_placement() {/,/^}/p' "$PLACE")"
if [ -z "$wp" ]; then fail "P32b write_placement not found in the producer"; else
  # shellcheck disable=SC2034  # DETECTION and NOW are read by the eval'd write_placement
  ( set +eu; WORK="$T/wpw"; mkdir -p "$WORK"; PLACEMENT="$T/wpw/pl.out"; DETECTION="$T/wpw/none"; NOW=1700000000
    hosted_key_var() { :; }; log() { :; }; jev_write_atomic() { cat > "$1"; }; eval "$wp"
    write_placement p fits r none false 0 bogus_event; echo "rc=$? file=$([ -e "$PLACEMENT" ] && echo yes || echo no)"
    write_placement p fits r none false 0 placed; echo "rc=$? file=$([ -e "$PLACEMENT" ] && echo yes || echo no)" ) > "$T/wpw.out" 2>&1
  assert_eqx "rc=2 file=no" "$(sed -n 1p "$T/wpw.out")" "P32b an event outside the closed set is refused (rc 2, nothing written)"
  assert_eqx "rc=0 file=yes" "$(sed -n 2p "$T/wpw.out")" "P32b CONTROL: an event in the set is written"
fi

# ---- P29 pid start time is field 22 (review X6) ---------------------------------------------------------------------------
if [ -r "/proc/$$/stat" ] && command -v python3 >/dev/null 2>&1; then
  fresh; cap "$T/cap.json"
  sleep 60 & SPID=$!; jev_track_pid "$SPID"
  "$PLACE" acquire s1 --pid "$SPID" >/dev/null 2>&1
  oracle="$(python3 -I -c 'import sys; print(open("/proc/%s/stat" % sys.argv[1]).read().rsplit(")", 1)[1].split()[19])' "$SPID")"
  assert_eqx "$oracle" "$(L '.sets["decide-a"].leases[0].pid_start')" "P29 pid_start equals /proc/<pid>/stat field 22 (python oracle)"
  vsz="$(python3 -I -c 'import sys; print(open("/proc/%s/stat" % sys.argv[1]).read().rsplit(")", 1)[1].split()[20])' "$SPID")"
  [ "$vsz" != "$oracle" ] && ok "P29 CONTROL: field 23 (vsize) differs from field 22, so the oracle discriminates" || fail "P29 the oracle cannot tell field 22 from 23"
  kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
else
  assert_skip "P29 /proc or python3 unavailable"
fi

# ---- P30 zombie holder (review X7) ---------------------------------------------------------------------------------------
if [ -r "/proc/$$/stat" ]; then
  fresh; cap "$T/cap.json"
  bash -c 'sleep 0.3 & echo $! > "$1"; exec sleep 60' _ "$T/zpid" & ZP=$!; jev_track_pid "$ZP"
  for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$T/zpid" ] && break; sleep 0.1; done
  Z="$(cat "$T/zpid" 2>/dev/null)"
  "$PLACE" acquire s1 --pid "$Z" >/dev/null 2>&1
  for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do grep -q '^State:[[:space:]]*Z' "/proc/$Z/status" 2>/dev/null && break; sleep 0.1; done
  if grep -q '^State:[[:space:]]*Z' "/proc/$Z/status" 2>/dev/null && [ -d "/proc/$Z" ]; then
    ok "P30 setup: the holder is a zombie (pid exists, empty cmdline)"
    "$PLACE" reap 2>"$T/e30"
    assert_eqx 0 "$(L '.sets["decide-a"].leases|length')" "P30 a zombie holder is dead: its lease is reaped"
  else
    fail "P30 setup: could not make a zombie holder"
  fi
  kill "$ZP" 2>/dev/null; wait "$ZP" 2>/dev/null
fi

# ---- P31 stop mark without pid (review RS3) --------------------------------------------------------------------------------
fresh; cap "$T/cap.json"
printf '{"sets":{"decide-a":{"constitution_started":true,"stopping":{"at":1700000000},"leases":[]}}}\n' > "$JEV_STATE_DIR/leases.json"
"$PLACE" reap 2>/dev/null
assert_eqx true "$(L '.sets["decide-a"].stopping != null')" "P31 a fresh stop mark with no pid is kept (no pid is never a dead stopper)"
JEV_NOW_EPOCH=1700000400 "$PLACE" reap 2>/dev/null
assert_eqx false "$(L '.sets["decide-a"].stopping != null')" "P31 the same mark older than the stop timeout + 30 s is cleared"



# ---- P33 a lease-less constitution-started set whose unit is NOT live is disposed (review R3-1, RS4) ------------------------
# Before round 4 such a set was refused on every acquire (refused_join) and never reaped: the profile was never placed again.
# Now the acquire stops it (bounded), drops the set and the cache entry, holds the profile for this evaluation
# (§11.4.291(D) hold window: it is not restarted by the acquire that stopped it) and the NEXT acquire places it normally.
orphan_a() { # a constitution-started decide-a set whose only holder is a pid that has already exited
  local dead; dead="$(bash -c 'echo $$')"
  "$PLACE" acquire ghost --pid "$dead" >/dev/null 2>&1
}
cachen() { jq '[.endpoints[]? | select(.provider_id=="llmctl-local")] | length' "$CACHE" 2>/dev/null || echo 0; }
for us in failed absent starting; do
  fresh; cap "$T/cap.json" fits does_not_fit; orphan_a
  assert_eqx "1 1" "$(starts) $(L '.sets["decide-a"].constitution_started == true | if . then 1 else 0 end')" "P33 setup ($us): one constitution-started set"
  export PLACE_CAP_RAW=1
  if [ "$us" = absent ]; then cap "$T/cap.json" fits does_not_fit; else cap "$T/cap.json" fits does_not_fit 5000 "$us"; fi
  "$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e33"; rc=$?
  assert_eqx 1 "$(stops)" "P33 unit $us, no lease: the acquire stops the constitution-started model (one bounded stop)"
  assert_eqx null "$(L '.sets["decide-a"]')" "P33 unit $us: the stopped set is removed (no stuck refused_join)"
  assert_eqx 0 "$(cachen)" "P33 unit $us: the dead gateway is not left in the endpoint cache"
  case "$(pl '.placement.event')" in refused_join|refused_degraded) fail "P33 unit $us: still refused ($(pl '.placement.event'))" ;; *) ok "P33 unit $us: not a refused join" ;; esac
  assert_eqx "5 0" "$rc $(starts | awk '{print $1-1}')" "P33 unit $us: the stopping acquire does not restart the profile (hold), rc 5 (b does not fit)"
  unset PLACE_CAP_RAW; cap "$T/cap.json" fits does_not_fit   # the next evaluation reads llmctl's answer after the stop
  out="$("$PLACE" acquire s3 --pid $$ 2>/dev/null)"; rc=$?
  assert_eqx "0 decide-a 2 placed" "$rc $out $(starts) $(pl '.placement.event')" "P33 unit $us: the NEXT acquire places the profile again"
  assert_eqx "true s3" "$(L '.sets["decide-a"] | "\(.constitution_started) \([.leases[].holder]|join(","))"')" "P33 unit $us: the new set is constitution-started with the new holder only"
  unset PLACE_CAP_RAW
done
# the disposal stop fails: the set is KEPT (owned, never joined, no lease) and the stop is retried by every acquire
fresh; cap "$T/cap.json" fits does_not_fit; orphan_a
export PLACE_CAP_RAW=1 PLACE_STOP_RC=1; cap "$T/cap.json" fits does_not_fit 5000 failed
"$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e33f"; rc=$?
assert_eqx "5 1" "$rc $(stops)" "P33 disposal stop fails: rc 5, one stop attempted"
assert_eqx "true 0 1" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.leases|length) \(.stop_failed.rc)"')" "P33 disposal stop fails: the set is kept (constitution_started, no lease, stop_failed rc 1)"
assert_eqx true "$(L '.sets["decide-a"].stop_owed != null')" "P33 disposal stop fails: the set records the owed stop"
"$PLACE" acquire s3 --pid $$ >/dev/null 2>&1; rc=$?
assert_eqx "5 2 0" "$rc $(stops) $(L '.sets["decide-a"].leases|length')" "P33 the next acquire retries the owed stop (2 stops), never joins it (no lease)"
unset PLACE_STOP_RC
out="$("$PLACE" acquire s4 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a 3" "$rc $out $(stops)" "P33 the owed stop succeeds on a later acquire, the set goes and the profile is placed again"
assert_eqx "true null" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.stop_owed)"')" "P33 the new set is a normal constitution-started set"
unset PLACE_CAP_RAW

# ---- P34 every set is checked, not only the first (review R3-1, RS5) ---------------------------------------------------------
fresh; cap "$T/cap.json"; export JEV_PLACE_MAX=2
"$PLACE" acquire h1 --pid $$ >/dev/null 2>&1
assert_eqx 2 "$(starts)" "P34 setup: two sets (decide-a, decide-b) under holder h1"
export PLACE_CAP_RAW=1
jq '.llmctl.units=[{profile:"decide-a",status:"failed"},{profile:"decide-b",status:"running"}]' "$T/cap.json" > "$T/c34" && cp "$T/c34" "$T/cap.json"
out="$("$PLACE" acquire h2 --pid $$ 2>"$T/e34")"; rc=$?
assert_eqx "0 decide-b joined" "$rc $out $(pl '.placement.event')" "P34 a failed first set does not block joining the healthy second set"
assert_eqx "h1,h2" "$(L '[.sets["decide-b"].leases[].holder]|join(",")')" "P34 the new lease is on decide-b"
assert_eqx "h1 0" "$(L '[.sets["decide-a"].leases[].holder]|join(",")') $(stops)" "P34 the failed set that still has a live holder is left alone (no lease added, never stopped)"
unset PLACE_CAP_RAW JEV_PLACE_MAX

# ---- P35 a lease-less constitution-started model that runs but does not fit is stopped (review R3-1, RS6) ---------------------
for us in running degraded; do
  fresh; cap "$T/cap.json"; orphan_a
  export PLACE_CAP_RAW=1; cap "$T/cap.json" does_not_fit fits 5000 "$us"
  out="$("$PLACE" acquire t1 --pid $$ 2>"$T/e35")"; rc=$?
  assert_eqx 1 "$(stops)" "P35 unit $us + verdict not a fit, no lease: the model is stopped"
  [ ! -e "$STUB_LOG/running.decide-a" ] && ok "P35 unit $us: decide-a no longer runs" || fail "P35 unit $us: decide-a still runs with no lease"
  assert_eqx null "$(L '.sets["decide-a"]')" "P35 unit $us: its set is removed"
  assert_eqx "0 decide-b" "$rc $out" "P35 unit $us: the fitting candidate decide-b is placed instead"
  unset PLACE_CAP_RAW
done
fresh; cap "$T/cap.json"; orphan_a
export PLACE_CAP_RAW=1 JEV_PLACE_PROFILES=decide-a; cap "$T/cap.json" does_not_fit fits 5000 running
"$PLACE" acquire t2 --pid $$ >/dev/null 2>&1; rc=$?
assert_eqx "5 1 null" "$rc $(stops) $(L '.sets["decide-a"]')" "P35 single candidate that no longer fits: stopped, set removed, rc 5 (fallback route)"
unset PLACE_CAP_RAW JEV_PLACE_PROFILES
# CONTROL: a lease-less constitution-started model that runs AND fits is joined, never stopped (P11 shape, RAW answer)
fresh; cap "$T/cap.json"; orphan_a
export PLACE_CAP_RAW=1; cap "$T/cap.json" fits fits 5000 running
out="$("$PLACE" acquire t3 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a 0 joined" "$rc $out $(stops) $(pl '.placement.event')" "P35 CONTROL: running + fits, no lease -> joined, never stopped"
unset PLACE_CAP_RAW
# CONTROL: an operator-started (constitution_started:false) set is never stopped by this path
fresh; cap "$T/cap.json" fits fits 5000 running
"$PLACE" acquire op1 --pid "$(bash -c 'echo $$')" >/dev/null 2>&1
export PLACE_CAP_RAW=1; cap "$T/cap.json" does_not_fit does_not_fit 5000 failed
"$PLACE" acquire op2 --pid $$ >/dev/null 2>&1
assert_eqx 0 "$(stops)" "P35 CONTROL: an operator-started unit is never stopped by the disposal path"
unset PLACE_CAP_RAW

# ---- P36 the cleanup stop after a failed start is recognised as failed for EVERY non-zero rc, a timeout included (Y7) ---------
fresh; cap "$T/cap.json" fits does_not_fit; export PLACE_START_RC=1 PLACE_STOP_SLEEP=8 JEV_LLMCTL_START_TIMEOUT=1
t0=$(date +%s); "$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e36"; rc=$?; t1=$(date +%s)
assert_eqx 5 "$rc" "P36 failed start + cleanup stop timing out -> rc 5"
[ $((t1 - t0)) -le 8 ] && ok "P36 the cleanup stop is bounded ($((t1 - t0))s)" || fail "P36 the cleanup stop was not bounded ($((t1 - t0))s)"
case "$(L '.sets["decide-a"].stop_failed.rc')" in 124|137) ok "P36 a timed-out cleanup stop keeps the set with stop_failed rc $(L '.sets["decide-a"].stop_failed.rc')" ;;
  *) fail "P36 a timed-out cleanup stop did not keep the owned set (stop_failed rc $(L '.sets["decide-a"].stop_failed.rc'))" ;; esac
assert_eqx "true 0" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.leases|length)"')" "P36 the kept set is owned and has no lease (never adopted as operator-started)"
unset PLACE_START_RC PLACE_STOP_SLEEP JEV_LLMCTL_START_TIMEOUT

# ---- P37 reap never stops a model, also for a lease-less owned set whose unit failed (§11.4.291(J)) ----------------------------
fresh; cap "$T/cap.json"; orphan_a
export PLACE_CAP_RAW=1; cap "$T/cap.json" fits fits 5000 failed
"$PLACE" reap 2>/dev/null
assert_eqx "0 true" "$(stops) $(L '.sets["decide-a"] != null')" "P37 reap alone never stops (disposal happens only in an acquire)"
unset PLACE_CAP_RAW

finish
