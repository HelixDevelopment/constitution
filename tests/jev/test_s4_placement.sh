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
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; FIXTURES="$HERE/fixtures"
# shellcheck source=lib_assert.sh
. "$HERE/lib_assert.sh"
PLACE="$ROOT/scripts/jev/jev-place.sh"

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
  unset PLACE_CAP_RC PLACE_CAP_SLEEP PLACE_START_RC JEV_LLMCTL_TIMEOUT LLMCTL_GATEWAY_URL
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

finish
