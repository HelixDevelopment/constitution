#!/usr/bin/env bash
# test_s4_placement.sh — S4 (2026-11-12): the capacity-gated local placement producer scripts/jev/jev-place.sh (§11.4.291).
# GATE-LOGIC tests (§11.4.289(C)(2)): a stub llmctl (tests/jev/fixtures/bin-place/llmctl) answers `capacity --json` from a
# declared file; these prove the producer DECIDES correctly, never that a local model runs (the live run is T5 under docs/qa).
# Round 5 (review R4-2): the stub answers in the SHAPE of the pinned llmctl (unit status ok|degraded only, verdict `running`
# for a running profile, exit 75/3/0; docs/qa/jev_s3s4_20261112/round5/ground_truth.md). Every scenario that used a shape
# llmctl never emits (unit status running/failed/starting, a `fits` verdict for a running profile) was rewritten. A unit
# that crashed is modelled with the stub flag PLACE_GONE (no unit in the answer); nothing in this file deletes a file.
#   P1  fits -> first systemone-native candidate started, lease taken, gateway in the endpoint cache at priority 10, route local
#   P2  a second holder joins the running set (unit status ok, verdict running): no second start
#   P3  release of one of two holders: no stop; release of the last: llmctl stop, cache entry removed, set removed
#   P4  wrong schema -> undetermined, rc 5, no start; route none without a key, cloud (key NAME only) with a real hosted key
#   P5  capacity exit 1 -> undetermined; capacity slower than the bound -> undetermined (bounded call)
#   P6  candidate a does_not_fit, b fits -> b started
#   P7  RLIMIT_NPROC headroom absent -> undetermined, never fits;  P8 headroom < threads -> does_not_fit
#   P9  a degraded operator unit of the profile -> not adopted, not started;  P10 start refused (75) -> rc 5, no lease
#   P11 dead-pid holder reaped on the next acquire; the reap itself never stops the model; acquire rejoins (no second start)
#   P12 a set marked stopping refuses a new acquire (rc 5);  P13 lease lock held -> rc 4, no lease
#   P14 enable/disable/switch/auto refused (rc 2) and never sent to llmctl;  P15 verdict --json lists only systemone-native
#   P16 heartbeat refreshes; a pid-less lease past its TTL is reaped (cadence 10 s so --ttl 100 is admitted, R5-4);  P17 pressure.ok=false -> does_not_fit
#   P18-P20 a failed start is stopped again; 75 sends no stop; an operator-started unit is adopted, never stopped
#   P21 a FAILED last-release stop keeps the set (constitution_started, stopping mark, stop_failed), rc 6; the next release
#       retries; an acquire after a failed stop joins the kept model when its unit is ok
#   P22 the release stop is bounded by the START/STOP timeout;  P23 JEV_PLACE_MAX=2: the last release stops both
#   P24 pid identity (pid + start time);  P25 a join re-checks the unit (degraded -> refused_degraded) and re-registers
#   P26 closed verdict set;  P27 failed start + failed cleanup stop: kept set, never joined, stop retried
#   P28 join refusals on the REAL shapes: verdict running without an own unit, verdict undetermined, host pressure (every
#       unit degraded), a unit status outside ok/degraded, an unread answer; CONTROL joins. A GONE unit (crashed, or only a
#       foreign-owner unit left) is endpoint_gone since round 6 (R5-6): lease released, set disposed, not restarted
#   P29 pid start = /proc stat field 22;  P30 zombie holder reaped;  P31 a pid-less stop mark is cleared only by age
#   P32 closed event set (refused_starting included)
#   P33 a lease-less constitution-started set whose unit is gone or degraded is stopped (held for this evaluation) and the next
#       acquire places it; an UNKNOWN instance state never stops; a failed disposal stop is owed and retried
#   P34 every set is checked: a degraded / crashed first set does not block joining a healthy second set (a crashed one is
#       released and disposed, R5-6)
#   P35 (R4-2) degraded -> stopped and the other candidate placed; a lease-less constitution-started model whose unit is ok
#       is JOINED, never stopped, whatever a second start would get; single candidate degraded -> stopped, rc 5;
#       an operator-started unit is never stopped
#   P36 a timed-out cleanup stop keeps the owned set;  P37 reap never stops
#   (round 5)
#   P38 (R4-2) an operator-started unit that is ok is adopted in preference to starting another profile
#   P39 (R4-2) LLMCTL_TENANT_ID: the tenant-keyed unit is joined; another tenant's or another owner's unit is never adopted
#   P40 (R4-1) after any stop the endpoint cache never names the stopped model: an owed retry drops it; a release that stops
#       one set re-points the entry to the set that is still held
#   P41 (R4-3) no llmctl call under the lease lock: a heartbeat during a slow stop and during a slow start answers at once
#       (rc 3: that holder has no lease, R5-5; never rc 4, a lock timeout); a concurrent acquire is refused (refused_stopping / refused_starting), never a lock timeout
#   P42 a dead starter's `starting` mark is cleared; a live one is kept and refuses an acquire
#   P43 (R4-1) structure: exactly one `llmctl stop` and one `llmctl start` call site in the producer (control needles)
#   P44 verdict --json reports the instance state;  P45 a unit status outside ok/degraded is unknown: nothing started or adopted
#   P46 an own unit next to a non-running verdict is unknown;  P47 measurement.ok false -> undetermined
#   P48 (R4-3) across every scenario of this file no llmctl call ran while the lease lock was held (stub LOCKHELD record)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; FIXTURES="$HERE/fixtures"
# shellcheck source=lib_assert.sh
. "$HERE/lib_assert.sh"
PLACE="${S4_PLACE_UNDER_TEST:-$ROOT/scripts/jev/jev-place.sh}"

assert_eqx() { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (expected [$1] got [$2])"; fi; }
has()  { if grep -q -- "$2" "$1" 2>/dev/null; then ok "$3"; else fail "$3 (no [$2] in $1)"; fi; }
hasnt(){ if grep -q -- "$2" "$1" 2>/dev/null; then fail "$3 (found [$2] in $1)"; else ok "$3"; fi; }

# cap <file> [a-verdict] [b-verdict] [headroom|none] [units] [pressure-ok]
# The verdicts are what llmctl reports for a NEW start of each profile; the stub turns a profile it runs into verdict
# `running` with its own unit (status ok, or degraded via PLACE_DEGRADED / pressure). [units] declares extra units in
# llmctl's shape: op (an operator-started decide-a, status ok), opdeg (the same, degraded), opweird (status outside the set),
# foreign (a decide-a unit of another user), opb (an operator-started decide-b, status ok).
cap() {
  local units='[]' u='{"unit":"llmctl-llama@decide-a.service","profile":"decide-a","base_profile":"decide-a","owner":"self","status":"ok","reasons":[]}'
  case "${5:-}" in
    "") ;;
    op) units="[$u]" ;;
    opdeg) units="$(jq -c '[. + {status:"degraded", reasons:["memory 950 MiB is at >= 90% of its 1000 MiB limit"]}]' <<<"$u")" ;;
    opweird) units="$(jq -c '[. + {status:"failed"}]' <<<"$u")" ;;
    foreign) units="$(jq -c '[. + {owner:"user-4242"}]' <<<"$u")" ;;
    opb) units="$(jq -c '[. + {unit:"llmctl-llama@decide-b.service", profile:"decide-b", base_profile:"decide-b"}]' <<<"$u")" ;;
    *) echo "cap: unknown units token $5" >&2; return 2 ;;
  esac
  jq -n --arg va "${2:-fits}" --arg vb "${3:-fits}" --arg hr "${4:-5000}" --argjson units "$units" --arg pok "${6:-true}" '
    {schema:"llmctl.capacity/1", time:1700000000, measurement:{ok:true, critical_inputs_unreadable:[]},
     host:({cpus_online:16, mem_total_mb:20000, mem_available_mb:18000, usable_mem_mb:15000, swap_total_mb:0, swap_free_mb:0,
            load:{"1":1.0,"5":1.0,"15":1.0}, psi:{memory:{some:0.0,full:0.0},cpu:{some:0.0},io:{some:0.0,full:0.0}}, cgroup:{memory_max_mb:null}}
           + (if $hr=="none" then {} else {nproc:{headroom:($hr|tonumber)}} end)),
     reserve:{mem_reserved_mb:4000, cpus_reserved:4}, pressure:{ok:($pok=="true"), reasons:(if $pok=="true" then [] else ["psi full avg10 3.1 > 2"] end)},
     llmctl:{units:$units},
     fallback:{recommended:"cloud", key_variable:null}, unknown_profiles:[], degraded:false, largest_decision_fit:null,
     profiles:{"decide-a":{verdict:$va, verdict_class:$va, running:false, threads:(if $va=="does_not_fit" then 0 else 3 end), reasons:[], headroom:{footprint_mb:1000}},
               "decide-b":{verdict:$vb, verdict_class:$vb, running:false, threads:(if $vb=="does_not_fit" then 0 else 3 end), reasons:[], headroom:{footprint_mb:1000}},
               "decide-x":{verdict:"fits", verdict_class:"fits", running:false, threads:3, reasons:[], headroom:{footprint_mb:1000}}}}' > "$1"
}
# rawcap <file> <jq-filter>: a document the stub returns UNCHANGED (PLACE_CAP_RAW=1), built from the default cap and edited
rawcap() { cap "$1"; jq "$2" "$1" > "$1.r" && mv "$1.r" "$1"; export PLACE_CAP_RAW=1; }
LOCKHELD_TOTAL=0
count_lockheld() { local n=0; [ -n "${STUB_LOG:-}" ] && [ -f "$STUB_LOG/llmctl.log" ] && n="$(grep -c '^LOCKHELD' "$STUB_LOG/llmctl.log" || true)"; LOCKHELD_TOTAL=$((LOCKHELD_TOTAL + ${n:-0})); }
fresh() {
  count_lockheld
  make_fixture_env s4
  export PATH="$FIXTURES/bin-place:$PATH" JEV_TEST=1 PLACE_CAP_JSON="$T/cap.json" JEV_LOCK_TIMEOUT=2
  unset PLACE_CAP_RC PLACE_CAP_SLEEP PLACE_CAP_RAW PLACE_START_RC PLACE_START_SLEEP PLACE_STOP_RC PLACE_STOP_SLEEP PLACE_DEGRADED \
        PLACE_GONE JEV_LLMCTL_TIMEOUT JEV_LLMCTL_START_TIMEOUT JEV_PLACE_MAX JEV_PLACE_PROFILES LLMCTL_GATEWAY_URL LLMCTL_TENANT_ID
  : > "$STUB_LOG/llmctl.log"
  CACHE="$CMA_PROVIDERS_DIR/jev-endpoints.json"
}
starts() { grep -c '^llmctl start' "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
stops()  { grep -c '^llmctl stop' "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
pl() { jq -r "$1" "$JEV_STATE_DIR/placement.json"; }
L() { jq -r "$1" "$JEV_STATE_DIR/leases.json"; }
cachen() { jq '[.endpoints[]? | select(.provider_id=="llmctl-local")] | length' "$CACHE" 2>/dev/null || echo 0; }
cachem() { jq -r '[.endpoints[]? | select(.provider_id=="llmctl-local") | .model] | join(",")' "$CACHE" 2>/dev/null || true; }
closed_verdict() { case "$(pl '.placement.verdict')" in fits|fits_with_reduced_threads|does_not_fit|undetermined|null) ok "P26 $1: verdict $(pl '.placement.verdict') in the closed set" ;; *) fail "P26 $1: verdict $(pl '.placement.verdict') outside the closed set" ;; esac; }
orphan_a() { # a constitution-started decide-a set whose only holder is a pid that has already exited
  local dead; dead="$(bash -c 'echo $$')"
  "$PLACE" acquire ghost --pid "$dead" >/dev/null 2>&1
}
# unit_gone <key>: the unit crashed or was stopped outside the producer; the stub reports no unit for <key>
unit_gone() { export PLACE_GONE="${PLACE_GONE:+$PLACE_GONE,}${1:?}"; }

# ---- P1 / P2 / P3 ------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"
out="$("$PLACE" acquire s1 --pid $$ 2>"$T/e1")"; rc=$?
assert_eqx 0 "$rc" "P1 acquire rc 0 when a candidate fits"
assert_eqx decide-a "$out" "P1 first systemone-native candidate (decide-a) placed"
assert_eqx 1 "$(starts)" "P1 exactly one llmctl start"
assert_eqx 10 "$(jq -r '.endpoints[] | select(.provider_id=="llmctl-local") | .priority' "$CACHE")" "P1 local gateway in the cache at priority 10"
assert_eqx https://127.0.0.1:18095 "$(jq -r '.endpoints[] | select(.provider_id=="llmctl-local") | .base_url' "$CACHE")" "P1 gateway URL from the llmctl registry"
assert_eqx LLMCTL_API_KEY "$(jq -r '.endpoints[] | select(.provider_id=="llmctl-local") | .key_var' "$CACHE")" "P1 key referenced by NAME"
assert_eqx local "$(pl .placement.route)" "P1 placement route local"
assert_eqx true "$(L '.sets["decide-a"].constitution_started')" "P1 set records constitution_started"
assert_eqx null "$(L '.sets["decide-a"].starting')" "P1 the starting mark is cleared after the start"
"$FIXTURES/bin-place/llmctl" capacity --json > "$T/cap.after" 2>/dev/null
assert_eqx "running ok" "$(jq -r '"\(.profiles["decide-a"].verdict) \([.llmctl.units[] | select(.profile=="decide-a") | .status] | join(","))"' "$T/cap.after")" "P2 setup: the stub reports the started profile in llmctl's shape (verdict running, unit ok)"
out="$("$PLACE" acquire s2 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a" "$rc $out" "P2 second holder joins decide-a (verdict running, unit status ok)"
assert_eqx 1 "$(starts)" "P2 no second start"
assert_eqx 2 "$(L '.sets["decide-a"].leases|length')" "P2 two leases"
assert_eqx "joined null" "$(pl '"\(.placement.event) \(.placement.verdict)"')" "P2 event joined, no capacity verdict for a running instance"
"$PLACE" release s1 2>/dev/null; assert_eqx 0 "$(stops)" "P3 release of one of two holders does not stop"
assert_eqx 1 "$(cachen)" "P3 the cache entry stays while a lease is held"
"$PLACE" release s2 2>"$T/e3"; rc=$?
assert_eqx 0 "$rc" "P3 last release rc 0"
assert_eqx 1 "$(stops)" "P3 last release stops the model"
has "$STUB_LOG/llmctl.log" '^llmctl stop decide-a$' "P3 stop names the started profile"
assert_eqx 0 "$(cachen)" "P3 cache entry removed"
assert_eqx null "$(L '.sets["decide-a"]')" "P3 lease set removed"
[ ! -e "$STUB_LOG/running.decide-a" ] && ok "P3 stub reports the model stopped" || fail "P3 model still running"

# ---- P4 ------------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"; jq '.schema="llmctl.capacity/2"' "$T/cap.json" > "$T/c2" && mv "$T/c2" "$T/cap.json"
"$PLACE" acquire s1 >/dev/null 2>"$T/e4"; rc=$?
assert_eqx 5 "$rc" "P4 wrong schema -> rc 5"
assert_eqx 0 "$(starts)" "P4 no start under undetermined"
assert_eqx undetermined "$(pl .placement.verdict)" "P4 verdict undetermined"
assert_eqx none "$(pl .placement.route)" "P4 route none without a key"
SECRET="tsk-s4-$(date +%N)-realvalue"
export TYPESAFE_API_KEY="$SECRET"
"$PLACE" acquire s1 >/dev/null 2>>"$T/e4"
assert_eqx cloud "$(pl .placement.route)" "P4 route cloud with a real hosted key"
assert_eqx TYPESAFE_API_KEY "$(pl .placement.key_variable)" "P4 key variable NAME recorded"
if grep -rqF -- "$SECRET" "$JEV_STATE_DIR" "$T/e4" "$CMA_PROVIDERS_DIR"; then fail "P4 key VALUE leaked"; else ok "P4 key value never written"; fi
unset TYPESAFE_API_KEY

# ---- P5 ------------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"; export PLACE_CAP_RC=1
"$PLACE" acquire s1 >/dev/null 2>"$T/e5"; rc=$?
assert_eqx "5 0" "$rc $(starts)" "P5 capacity exit 1 -> rc 5, no start"
has "$T/e5" "exit 1" "P5 reason names the exit code"
# Round 7 (T6-2): the bound is proven by the stub's own completion marker, never by a wall clock (a loaded host made the
# round-6 `<= 4 s` row flaky). A capacity call that runs to its end appends a line to $STUB_LOG/cap.done AFTER its
# PLACE_CAP_SLEEP; a call killed by the producer's timeout never writes it. Control needle: the call above (no sleep)
# wrote it.
if [ -s "$STUB_LOG/cap.done" ]; then ok "P5 CONTROL: a capacity call that completes writes the completion marker"
else fail "P5 CONTROL: no completion marker after a completed capacity call (the instrument is blind)"; fi
: > "$STUB_LOG/cap.done"
unset PLACE_CAP_RC; export PLACE_CAP_SLEEP=30 JEV_LLMCTL_TIMEOUT=1
"$PLACE" acquire s1 >/dev/null 2>"$T/e5b"; rc=$?
assert_eqx "5 0" "$rc $(starts)" "P5 slow capacity -> rc 5, no start"
if [ ! -s "$STUB_LOG/cap.done" ]; then ok "P5 llmctl call bounded: the 30 s capacity call never ran to its end"
else fail "P5 call not bounded: the slow capacity call completed ($(wc -l < "$STUB_LOG/cap.done") completion lines)"; fi
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
fresh; cap "$T/cap.json" fits does_not_fit 5000 opdeg
"$PLACE" acquire s1 >/dev/null 2>"$T/e9"; rc=$?
assert_eqx "5 0" "$rc $(starts)" "P9 a degraded operator unit of decide-a -> not started a second time, rc 5"
assert_eqx null "$(L '.sets["decide-a"]')" "P9 the degraded unit is not adopted"
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
assert_eqx 0 "$(L '.sets["decide-a"].leases|length')" "P11 dead holder reaped"
out="$("$PLACE" acquire live --pid $$ 2>/dev/null)"
assert_eqx "decide-a 1 0" "$out $(starts) $(stops)" "P11 acquire rejoins the running constitution-started model (no second start, no stop)"

# ---- P12 / P13 -------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"
echo '{"sets":{"decide-a":{"constitution_started":true,"started_at":1700000000,"stopping":{"at":1700000000,"pid":1},"leases":[]}}}' > "$JEV_STATE_DIR/leases.json"
"$PLACE" acquire s1 >/dev/null 2>"$T/e12"; rc=$?
assert_eqx "5 0 refused_stopping" "$rc $(starts) $(pl .placement.event)" "P12 stopping set refuses a new acquire"
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
# round 6 (R5-4): a TTL must exceed the re-evaluation cadence plus the llmctl call timeout; a 10 s cadence admits --ttl 100
export JEV_REEVAL_CADENCE=10
"$PLACE" acquire s1 --ttl 100 >/dev/null 2>&1
JEV_NOW_EPOCH=1700000050 "$PLACE" heartbeat s1
assert_eqx 1700000050 "$(L '.sets["decide-a"].leases[0].heartbeat_at')" "P16 heartbeat refreshed"
JEV_NOW_EPOCH=1700000200 "$PLACE" reap 2>/dev/null
assert_eqx 0 "$(L '.sets["decide-a"].leases|length')" "P16 pid-less lease past TTL reaped"
unset JEV_REEVAL_CADENCE

# ---- P18 / P19 / P20 -------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"; export PLACE_START_RC=1
"$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e18"; rc=$?
assert_eqx 5 "$rc" "P18 failed start -> no local placement (rc 5)"
assert_eqx 0 "$(find "$STUB_LOG" -maxdepth 1 -name 'running.*' | wc -l | tr -d ' ')" "P18 a unit the producer tried to start and that failed is stopped again (no orphan)"
has "$T/e18" "stopping it again" "P18 the cleanup stop is logged"
fresh; cap "$T/cap.json"; export PLACE_START_RC=75
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
assert_eqx 0 "$(stops)" "P19 a start refused by the pressure gate (75, no partial start) sends no stop"
unset PLACE_START_RC
fresh; cap "$T/cap.json" fits fits 5000 op
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1; rc=$?
assert_eqx "0 0 joined_running" "$rc $(starts) $(pl .placement.event)" "P20 an already-running operator unit (status ok) is adopted, never started again"
assert_eqx false "$(L '.sets["decide-a"].constitution_started')" "P20 an operator-started unit is recorded constitution_started=false"
"$PLACE" release s1 >/dev/null 2>&1
assert_eqx 0 "$(stops)" "P20 releasing the last lease of an operator-started unit never stops it"

# ---- P21 failed stop keeps the set; the next release retries ------------------------------------------------------
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
export PLACE_STOP_RC=1
"$PLACE" release s1 >/dev/null 2>"$T/e21"; rc=$?
assert_eqx 6 "$rc" "P21 a failed stop on the last release returns rc 6 (never 0)"
assert_eqx 1 "$(stops)" "P21 one stop attempted"
assert_eqx true "$(L '.sets["decide-a"].constitution_started')" "P21 the set is KEPT with constitution_started=true"
assert_eqx true "$(L '.sets["decide-a"].stopping != null')" "P21 the stopping mark is kept"
assert_eqx 1 "$(L '.sets["decide-a"].stop_failed.rc')" "P21 the set records the failed stop rc"
assert_eqx stop_failed "$(pl '.placement.event')" "P21 placement event stop_failed"
closed_verdict "stop_failed"
assert_eqx 0 "$(cachen)" "P21 a set with no lease is not routable: the cache entry is removed (R4-1 invariant)"
assert_eqx none "$(pl .placement.route)" "P21 the recorded route is the fallback, not local"
has "$T/e21" "stop_failed" "P21 stop_failed is logged"
unset PLACE_STOP_RC
"$PLACE" release s1 >/dev/null 2>"$T/e21b"; rc=$?
assert_eqx 0 "$rc" "P21 the next release re-attempts the stop and succeeds (rc 0)"
assert_eqx 2 "$(stops)" "P21 a second stop was sent (retry)"
assert_eqx null "$(L '.sets["decide-a"]')" "P21 only a successful stop removes the set"
assert_eqx stopped "$(pl '.placement.event')" "P21 placement event stopped after the retry"
closed_verdict "stopped"
[ ! -e "$STUB_LOG/running.decide-a" ] && ok "P21 model stopped after the retry" || fail "P21 model still running after the retry"
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
PLACE_STOP_RC=1 "$PLACE" release s1 >/dev/null 2>&1
out="$("$PLACE" acquire s2 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a 1" "$rc $out $(starts)" "P21 after a failed stop a new acquire joins the kept model (unit ok; no second start)"
assert_eqx true "$(L '.sets["decide-a"].constitution_started')" "P21 the joined set stays constitution-started (a later release still stops it)"
assert_eqx decide-a "$(cachem)" "P21 the join registers the gateway again"

# ---- P22 the stop uses the stop timeout ---------------------------------------------------------------------------
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
PLACE_STOP_SLEEP=3 JEV_LLMCTL_TIMEOUT=1 JEV_LLMCTL_START_TIMEOUT=10 "$PLACE" release s1 >/dev/null 2>"$T/e22"; rc=$?
assert_eqx 0 "$rc" "P22 a 3 s stop with read timeout 1 s and stop timeout 10 s succeeds (bounded by the stop timeout)"
assert_eqx null "$(L '.sets["decide-a"]')" "P22 set removed after the slow stop"
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
t0=$(date +%s); PLACE_STOP_SLEEP=8 JEV_LLMCTL_START_TIMEOUT=1 "$PLACE" release s1 >/dev/null 2>"$T/e22b"; rc=$?; t1=$(date +%s)
assert_eqx 6 "$rc" "P22 a stop slower than the stop timeout is stop_failed (rc 6)"
[ $((t1 - t0)) -le 6 ] && ok "P22 the stop is bounded ($((t1 - t0))s)" || fail "P22 the stop was not bounded ($((t1 - t0))s)"
assert_eqx true "$(L '.sets["decide-a"].constitution_started')" "P22 timed-out stop keeps the set"

# ---- P23 MAXN>1 -----------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"; export JEV_PLACE_MAX=2
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
assert_eqx 2 "$(starts)" "P23 two profiles started with JEV_PLACE_MAX=2"
"$PLACE" release s1 >/dev/null 2>"$T/e23"; rc=$?
assert_eqx "0 2" "$rc $(stops)" "P23 the last release stops BOTH started profiles"
assert_eqx 0 "$(jq '.sets | length' "$JEV_STATE_DIR/leases.json")" "P23 both sets removed"
assert_eqx 0 "$(find "$STUB_LOG" -maxdepth 1 -name 'running.*' | wc -l | tr -d ' ')" "P23 no model left running"
assert_eqx 0 "$(cachen)" "P23 no cache entry names a stopped model"
unset JEV_PLACE_MAX

# ---- P24 pid identity ------------------------------------------------------------------------------------------------
if [ -r "/proc/$$/stat" ]; then
  fresh; cap "$T/cap.json"
  "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
  assert_eqx number "$(L '.sets["decide-a"].leases[0].pid_start | type')" "P24 the lease records the holder's process start time"
  JEV_NOW_EPOCH=1700099999 "$PLACE" reap 2>/dev/null
  assert_eqx 1 "$(L '.sets["decide-a"].leases|length')" "P24 a live pid holder with a matching start time is kept"
  jq '.sets["decide-a"].leases[0].pid_start = 1' "$JEV_STATE_DIR/leases.json" > "$T/l24" && cp "$T/l24" "$JEV_STATE_DIR/leases.json"
  "$PLACE" reap 2>"$T/e24"
  assert_eqx 0 "$(L '.sets["decide-a"].leases|length')" "P24 a reused pid (start time differs) is reaped"
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
assert_eqx 1 "$(cachen)" "P25 the join re-registers the local gateway in the cache"
assert_eqx joined "$(pl '.placement.event')" "P25 placement event joined"
closed_verdict "joined"
PLACE_DEGRADED=decide-a "$PLACE" acquire s3 --pid $$ >/dev/null 2>"$T/e25"; rc=$?
assert_eqx 5 "$rc" "P25 a degraded unit is not joined (rc 5)"
assert_eqx 2 "$(L '.sets["decide-a"].leases|length')" "P25 no lease added for the degraded unit"
assert_eqx "does_not_fit" "$(pl '.placement.verdict')" "P25 degraded => does_not_fit"
assert_eqx refused_degraded "$(pl '.placement.event')" "P25 degraded => event refused_degraded (not the generic refused_join)"
has "$T/e25" "degraded" "P25 reason names the degraded unit"
assert_eqx "1 0" "$(starts) $(stops)" "P25 no second start, and a held set is never stopped"

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
fresh; cap "$T/cap.json" fits does_not_fit; export PLACE_START_RC=1 PLACE_STOP_RC=1
"$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e27"; rc=$?
assert_eqx 5 "$rc" "P27 failed start -> rc 5"
assert_eqx start_failed "$(pl '.placement.event')" "P27 event start_failed"
assert_eqx "true 0 1 1" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.leases|length) \(.start_failed.rc) \(.stop_failed.rc)"')" "P27 the set is KEPT: constitution_started, no lease, start_failed rc 1, stop_failed rc 1"
assert_eqx 1 "$(find "$STUB_LOG" -maxdepth 1 -name 'running.decide-a' | wc -l | tr -d ' ')" "P27 setup: the stub unit still runs after the failed cleanup"
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
assert_eqx 0 "$(find "$STUB_LOG" -maxdepth 1 -name 'running.decide-a' | wc -l | tr -d ' ')" "P27 the unit is no longer running"
fresh; cap "$T/cap.json" fits does_not_fit; export PLACE_START_RC=1 PLACE_STOP_RC=1
"$PLACE" acquire s1 >/dev/null 2>&1
unset PLACE_START_RC PLACE_STOP_RC
out="$("$PLACE" acquire s2 --pid $$ 2>"$T/e27d")"; rc=$?
assert_eqx "0 decide-a" "$rc $out" "P27 acquire retries the stop (rc 0), removes the kept set, reads capacity again, then places normally"
assert_eqx "true 1 null" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.leases|length) \(.start_failed)"')" "P27 the new set is a normal constitution-started set"
has "$T/e27d" "reading the capacity answer again" "P27 after the stop the start is decided on a fresh capacity answer"

# ---- P28 join refusals on the REAL shapes (review R2-3, R4-2) -------------------------------------------------------------
p28() { # p28 <label> <expected-event>: s1 holds decide-a; the case was set up by the caller after p28_setup
  "$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e28"; rc=$?
  assert_eqx "5 $2" "$rc $(pl '.placement.event')" "P28 $1 -> join refused (rc 5, event $2)"
  assert_eqx 1 "$(L '.sets["decide-a"].leases|length')" "P28 $1 -> no lease added"
  assert_eqx 0 "$(cachen)" "P28 $1 -> the gateway is NOT registered in the cache"
  assert_eqx 0 "$(stops)" "P28 $1 -> a set that still holds a lease is never stopped"
  unset PLACE_CAP_RAW PLACE_DEGRADED PLACE_GONE
}
p28_setup() { fresh; cap "$T/cap.json" fits does_not_fit; "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1; jq '.endpoints = []' "$CACHE" > "$T/c28" && cp "$T/c28" "$CACHE"; }
RUN_NO_UNIT='.profiles["decide-a"] += {verdict:"running", verdict_class:null, running:true, threads:0, reasons:["already running"]}'
# round 6 (R5-6): a GONE endpoint is not a join refusal any more. Its leases are released (endpoint_gone, §11.4.291(J)(6)),
# the lease-less constitution-started set is disposed (one idempotent bounded stop) and the profile is NOT restarted by the
# same acquire (no restart loop): rc 5, no_fit with the held profile named, no lease, no cache entry.
p28gone() { # p28gone <label>
  "$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e28"; rc=$?
  assert_eqx "5 no_fit" "$rc $(pl '.placement.event')" "P28 $1 -> no join and no restart (rc 5, event no_fit)"
  has "$T/e28" "endpoint_gone: the unit of decide-a is gone" "P28 $1 -> endpoint_gone is logged"
  has "$T/e28" "every lease released (holders s1)" "P28 $1 -> the lease of the gone endpoint is released and named"
  assert_eqx "null 0 0" "$(L '.sets["decide-a"]') $(cachen) $(starts_after_setup)" "P28 $1 -> the set is disposed, nothing is in the cache, nothing is restarted"
  assert_eqx 1 "$(stops)" "P28 $1 -> exactly one (idempotent) stop of the gone constitution-started unit"
  case "$(pl '.placement.reason')" in *"held until the next evaluation"*decide-a*) ok "P28 $1 -> the record names the held profile" ;; *) fail "P28 $1 -> the record does not name the held profile: $(pl '.placement.reason')" ;; esac
  unset PLACE_CAP_RAW PLACE_DEGRADED PLACE_GONE
}
starts_after_setup() { echo $(( $(starts) - 1 )); }
p28_setup; unit_gone decide-a;                                                           p28gone "unit gone (crashed)"
p28_setup; rawcap "$T/cap.json" "$RUN_NO_UNIT";                                          p28 "verdict running without an own unit" refused_join
p28_setup; unit_gone decide-a; cap "$T/cap.json" fits does_not_fit 5000 foreign;         p28gone "only another user's unit"
p28_setup; rawcap "$T/cap.json" '.profiles["decide-a"].verdict = "undetermined" | .profiles["decide-a"].threads = 0'
                                                                                         p28 "verdict undetermined" refused_join
p28_setup; cap "$T/cap.json" fits does_not_fit 5000 "" false;                            p28 "host pressure (every unit degraded)" refused_degraded
p28_setup; rawcap "$T/cap.json" "$RUN_NO_UNIT"' | .llmctl.units = [{unit:"llmctl-llama@decide-a.service", profile:"decide-a", owner:"self", status:"failed", reasons:[]}]'
                                                                                         p28 "unit status outside ok/degraded" refused_join
p28_setup; echo '{"schema":"other"}' > "$T/cap.json"
"$PLACE" acquire s3 --pid $$ >/dev/null 2>"$T/e28u"; rc=$?
has "$T/e28u" "capacity undetermined" "P28 an unreadable capacity answer is refused at the capacity check itself"
assert_eqx "5 refused_join undetermined" "$rc $(pl '.placement.event') $(pl '.placement.verdict')" "P28 undetermined capacity -> join refused (never a join on an unread answer)"
assert_eqx "1 0" "$(L '.sets["decide-a"].leases|length') $(stops)" "P28 no lease added and nothing stopped on an unread answer"
p28_setup; cap "$T/cap.json" does_not_fit does_not_fit
out="$("$PLACE" acquire s4 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a joined" "$rc $out $(pl '.placement.event')" "P28 CONTROL: unit ok -> joined, whatever a SECOND start of the profile would get"

# ---- P32 closed event set ----------------------------------------------------------------------------------------------------
case "$(pl '.placement.event')" in placed|joined|joined_running|no_fit|undetermined|start_failed|start_refused|refused_stopping|refused_starting|refused_degraded|refused_join|lease_lock_timeout|stopped|stop_failed|endpoint_gone|gateway_refused|route_changed)
  ok "P32 the last placement event is in the closed set" ;; *) fail "P32 event outside the closed set: $(pl '.placement.event')" ;; esac
wp="$(sed -n '/^write_placement() {/,/^}/p' "$PLACE")"
if [ -z "$wp" ]; then fail "P32b write_placement not found in the producer"; else
  # shellcheck disable=SC2034  # DETECTION and NOW are read by the eval'd write_placement
  ( set +eu; WORK="$T/wpw"; mkdir -p "$WORK"; PLACEMENT="$T/wpw/pl.out"; DETECTION="$T/wpw/none"; NOW=1700000000
    hosted_key_var() { :; }; log() { :; }; jev_write_atomic() { cat > "$1"; }; eval "$wp"
    write_placement p fits r none false 0 bogus_event; echo "rc=$? file=$([ -e "$PLACEMENT" ] && echo yes || echo no)"
    write_placement p fits r none false 0 placed; echo "rc=$? file=$([ -e "$PLACEMENT" ] && echo yes || echo no)"
    PLACEMENT="$T/wpw/pl3.out"; write_placement p "" r none false 0 refused_starting; echo "rc=$? file=$([ -e "$PLACEMENT" ] && echo yes || echo no)" ) > "$T/wpw.out" 2>&1
  assert_eqx "rc=2 file=no" "$(sed -n 1p "$T/wpw.out")" "P32b an event outside the closed set is refused (rc 2, nothing written)"
  assert_eqx "rc=0 file=yes" "$(sed -n 2p "$T/wpw.out")" "P32b CONTROL: an event in the set is written"
  assert_eqx "rc=0 file=yes" "$(sed -n 3p "$T/wpw.out")" "P32b refused_starting is in the closed set"
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

# ---- P33 a lease-less constitution-started set whose unit is gone or degraded is disposed (review R3-1, R4-2) ---------------
for us in gone degraded; do
  fresh; cap "$T/cap.json" fits does_not_fit; orphan_a
  assert_eqx "1 1" "$(starts) $(L '.sets["decide-a"].constitution_started == true | if . then 1 else 0 end')" "P33 setup ($us): one constitution-started set"
  if [ "$us" = gone ]; then unit_gone decide-a; else export PLACE_DEGRADED=decide-a; fi
  "$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e33"; rc=$?
  assert_eqx 1 "$(stops)" "P33 unit $us, no lease: the acquire stops the constitution-started model (one bounded stop)"
  assert_eqx null "$(L '.sets["decide-a"]')" "P33 unit $us: the stopped set is removed (no stuck refused_join)"
  assert_eqx 0 "$(cachen)" "P33 unit $us: the dead gateway is not left in the endpoint cache"
  case "$(pl '.placement.event')" in refused_join|refused_degraded) fail "P33 unit $us: still refused ($(pl '.placement.event'))" ;; *) ok "P33 unit $us: not a refused join" ;; esac
  assert_eqx "5 0" "$rc $(starts | awk '{print $1-1}')" "P33 unit $us: the stopping acquire does not restart the profile (hold), rc 5 (b does not fit)"
  unset PLACE_DEGRADED PLACE_GONE
  out="$("$PLACE" acquire s3 --pid $$ 2>/dev/null)"; rc=$?
  assert_eqx "0 decide-a 2 placed" "$rc $out $(starts) $(pl '.placement.event')" "P33 unit $us: the NEXT acquire places the profile again"
  assert_eqx "true s3" "$(L '.sets["decide-a"] | "\(.constitution_started) \([.leases[].holder]|join(","))"')" "P33 unit $us: the new set is constitution-started with the new holder only"
done
fresh; cap "$T/cap.json" fits does_not_fit; orphan_a
rawcap "$T/cap.json" "$RUN_NO_UNIT"
"$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e33u"; rc=$?
assert_eqx "5 0 refused_join" "$rc $(stops) $(pl '.placement.event')" "P33 an UNKNOWN instance state (running, no own unit) never stops the model and is refused"
assert_eqx "true 0" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.leases|length)"')" "P33 the unknown set is kept as it was"
unset PLACE_CAP_RAW
fresh; cap "$T/cap.json" fits does_not_fit; orphan_a
export PLACE_DEGRADED=decide-a PLACE_STOP_RC=1
"$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e33f"; rc=$?
assert_eqx "5 1" "$rc $(stops)" "P33 disposal stop fails: rc 5, one stop attempted"
assert_eqx "true 0 1" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.leases|length) \(.stop_failed.rc)"')" "P33 disposal stop fails: the set is kept (constitution_started, no lease, stop_failed rc 1)"
assert_eqx "true null" "$(L '.sets["decide-a"] | "\(.stop_owed != null) \(.stopping)"')" "P33 disposal stop fails: the owed stop is recorded and the stop mark is cleared"
"$PLACE" acquire s3 --pid $$ >/dev/null 2>&1; rc=$?
assert_eqx "5 2 0" "$rc $(stops) $(L '.sets["decide-a"].leases|length')" "P33 the next acquire retries the owed stop (2 stops), never joins it (no lease)"
unset PLACE_STOP_RC PLACE_DEGRADED
out="$("$PLACE" acquire s4 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a 3" "$rc $out $(stops)" "P33 the owed stop succeeds on a later acquire, the set goes and the profile is placed again"
assert_eqx "true null" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.stop_owed)"')" "P33 the new set is a normal constitution-started set"

# ---- P34 every set is checked, not only the first (review R3-1) ---------------------------------------------------------------
for us in degraded gone; do
  fresh; cap "$T/cap.json"; export JEV_PLACE_MAX=2
  "$PLACE" acquire h1 --pid $$ >/dev/null 2>&1
  assert_eqx 2 "$(starts)" "P34 setup ($us): two sets (decide-a, decide-b) under holder h1"
  if [ "$us" = gone ]; then unit_gone decide-a; else export PLACE_DEGRADED=decide-a; fi
  out="$("$PLACE" acquire h2 --pid $$ 2>"$T/e34")"; rc=$?
  assert_eqx "0 decide-b joined" "$rc $out $(pl '.placement.event')" "P34 a $us first set does not block joining the healthy second set"
  assert_eqx "h1,h2" "$(L '[.sets["decide-b"].leases[].holder]|join(",")')" "P34 ($us) the new lease is on decide-b"
  if [ "$us" = gone ]; then
    # round 6 (R5-6): the gone first set loses its lease (endpoint_gone) and is disposed; decide-b is joined all the same
    assert_eqx "null 1" "$(L '.sets["decide-a"]') $(stops)" "P34 (gone) the gone first set is released and disposed (one stop), never restarted"
    has "$T/e34" "endpoint_gone: the unit of decide-a is gone" "P34 (gone) endpoint_gone is logged"
  else
    assert_eqx "h1 0" "$(L '[.sets["decide-a"].leases[].holder]|join(",")') $(stops)" "P34 ($us) the first set that still has a live holder is left alone (no lease added, never stopped)"
  fi
  unset JEV_PLACE_MAX PLACE_DEGRADED PLACE_GONE
done

# ---- P35 (review R4-2) ------------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"; orphan_a
export PLACE_DEGRADED=decide-a
out="$("$PLACE" acquire t1 --pid $$ 2>"$T/e35")"; rc=$?
assert_eqx 1 "$(stops)" "P35 degraded unit, no lease: the model is stopped"
[ ! -e "$STUB_LOG/running.decide-a" ] && ok "P35 decide-a no longer runs" || fail "P35 decide-a still runs with no lease"
assert_eqx null "$(L '.sets["decide-a"]')" "P35 its set is removed"
assert_eqx "0 decide-b" "$rc $out" "P35 the fitting candidate decide-b is placed instead"
assert_eqx decide-b "$(cachem)" "P35 the cache names the placed model only"
unset PLACE_DEGRADED
fresh; cap "$T/cap.json"; orphan_a; cap "$T/cap.json" does_not_fit fits
out="$("$PLACE" acquire t2 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a 0 joined" "$rc $out $(stops) $(pl '.placement.event')" "P35 a lease-less constitution-started unit that is ok is JOINED, never stopped (a second start would not fit: irrelevant)"
assert_eqx 1 "$(starts)" "P35 no other profile is started instead"
fresh; cap "$T/cap.json"; orphan_a
export JEV_PLACE_PROFILES=decide-a PLACE_DEGRADED=decide-a
"$PLACE" acquire t3 --pid $$ >/dev/null 2>&1; rc=$?
assert_eqx "5 1 null" "$rc $(stops) $(L '.sets["decide-a"]')" "P35 single candidate degraded: stopped, set removed, rc 5 (fallback route)"
unset JEV_PLACE_PROFILES PLACE_DEGRADED
fresh; cap "$T/cap.json" fits fits 5000 op
"$PLACE" acquire op1 --pid "$(bash -c 'echo $$')" >/dev/null 2>&1
assert_eqx joined_running "$(pl .placement.event)" "P35 setup: an operator unit adopted by a holder that has since exited"
cap "$T/cap.json" fits fits 5000 opdeg
"$PLACE" acquire op2 --pid $$ >/dev/null 2>&1
hasnt "$STUB_LOG/llmctl.log" '^llmctl stop decide-a' "P35 CONTROL: a degraded operator-started unit is never stopped by the disposal path"

# ---- P36 the cleanup stop after a failed start is recognised as failed for EVERY non-zero rc, a timeout included (Y7) ---------
fresh; cap "$T/cap.json" fits does_not_fit; export PLACE_START_RC=1 PLACE_STOP_SLEEP=8 JEV_LLMCTL_START_TIMEOUT=1
t0=$(date +%s); "$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e36"; rc=$?; t1=$(date +%s)
assert_eqx 5 "$rc" "P36 failed start + cleanup stop timing out -> rc 5"
[ $((t1 - t0)) -le 8 ] && ok "P36 the cleanup stop is bounded ($((t1 - t0))s)" || fail "P36 the cleanup stop was not bounded ($((t1 - t0))s)"
case "$(L '.sets["decide-a"].stop_failed.rc')" in 124|137) ok "P36 a timed-out cleanup stop keeps the set with stop_failed rc $(L '.sets["decide-a"].stop_failed.rc')" ;;
  *) fail "P36 a timed-out cleanup stop did not keep the owned set (stop_failed rc $(L '.sets["decide-a"].stop_failed.rc'))" ;; esac
assert_eqx "true 0" "$(L '.sets["decide-a"] | "\(.constitution_started) \(.leases|length)"')" "P36 the kept set is owned and has no lease (never adopted as operator-started)"
unset PLACE_START_RC PLACE_STOP_SLEEP JEV_LLMCTL_START_TIMEOUT

# ---- P37 reap never stops a model (§11.4.291(J)) -------------------------------------------------------------------------------
fresh; cap "$T/cap.json"; orphan_a
PLACE_DEGRADED=decide-a "$PLACE" reap 2>/dev/null
assert_eqx "0 true" "$(stops) $(L '.sets["decide-a"] != null')" "P37 reap alone never stops (disposal happens only in an acquire)"

# ---- P38 adoption is preferred over a start (review R4-2) --------------------------------------------------------------------
fresh; cap "$T/cap.json" fits fits 5000 opb
out="$("$PLACE" acquire s1 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-b joined_running 0" "$rc $out $(pl .placement.event) $(starts)" "P38 an operator-started decide-b (ok) is adopted instead of starting decide-a"
assert_eqx "false decide-b" "$(L '.sets["decide-b"].constitution_started') $(cachem)" "P38 the adopted set is not constitution-started and the cache names it"

# ---- P39 tenant-keyed units (review R4-2) ------------------------------------------------------------------------------------
fresh; cap "$T/cap.json" fits does_not_fit; export LLMCTL_TENANT_ID=t1
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
[ -e "$STUB_LOG/running.t1--decide-a" ] && ok "P39 setup: the stub runs the tenant-keyed unit t1--decide-a" || fail "P39 setup: no t1--decide-a unit"
out="$("$PLACE" acquire s2 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a 1 joined" "$rc $out $(starts) $(pl .placement.event)" "P39 the tenant-keyed own unit is joined (no second start)"
fresh; export LLMCTL_TENANT_ID=t1 JEV_PLACE_PROFILES=decide-b
cap "$T/cap.json" does_not_fit fits
jq '.llmctl.units = [{unit:"llmctl-llama@t2--decide-b.service", profile:"t2--decide-b", base_profile:"decide-b", owner:"self", status:"ok", reasons:[]},
                     {unit:"llmctl-llama@decide-b.service", profile:"decide-b", base_profile:"decide-b", owner:"user-4242", status:"ok", reasons:[]}]' "$T/cap.json" > "$T/c39" && mv "$T/c39" "$T/cap.json"
out="$("$PLACE" acquire s3 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-b placed true" "$rc $out $(pl .placement.event) $(L '.sets["decide-b"].constitution_started')" "P39 another tenant's (t2--) and another user's unit are never adopted: decide-b is started for t1"
unset LLMCTL_TENANT_ID JEV_PLACE_PROFILES

# ---- P40 the endpoint cache never names a stopped model (review R4-1) ---------------------------------------------------------
fresh; cap "$T/cap.json" fits does_not_fit; export PLACE_START_RC=1 PLACE_STOP_RC=1
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
unset PLACE_START_RC PLACE_STOP_RC
# an entry that names decide-a (as an earlier placement registers it); the owed set is never routable
jq -n '{version:1, generated_at:0, ttl:300, endpoints:[{provider_id:"llmctl-local", base_url:"https://127.0.0.1:18095", model:"decide-a", key_var:"LLMCTL_API_KEY", priority:10, probed_at:0}]}' > "$CACHE"
cap "$T/cap.json" does_not_fit does_not_fit
"$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e40"; rc=$?
assert_eqx "5 2 null" "$rc $(stops) $(L '.sets["decide-a"]')" "P40 setup: the owed stop is retried and succeeds, nothing placed"
assert_eqx 0 "$(cachen)" "P40 after the owed stop no cache entry names the stopped model"
fresh; cap "$T/cap.json"; export JEV_PLACE_MAX=2
"$PLACE" acquire h1 --pid $$ >/dev/null 2>&1
unset JEV_PLACE_MAX
jq '.sets["decide-b"].leases[0].holder = "h2"' "$JEV_STATE_DIR/leases.json" > "$T/l40" && cp "$T/l40" "$JEV_STATE_DIR/leases.json"
assert_eqx decide-b "$(cachem)" "P40 setup: the cache names decide-b (the last model registered), decide-a is held by h1"
"$PLACE" release h2 >/dev/null 2>&1; rc=$?
assert_eqx "0 1" "$rc $(stops)" "P40 release of h2 stops decide-b only"
assert_eqx decide-a "$(cachem)" "P40 the cache entry is re-pointed to decide-a (still held), never left naming the stopped decide-b"

# ---- P41 no llmctl call under the lease lock (review R4-3) --------------------------------------------------------------------
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
( PLACE_STOP_SLEEP=8 "$PLACE" release s1 >/dev/null 2>&1 ) & bg=$!; jev_track_pid "$bg"
sleep 1
t0=$(date +%s); JEV_LOCK_TIMEOUT=4 "$PLACE" heartbeat s1 2>"$T/e41a"; rc=$?; t1=$(date +%s)
# round 6 (R5-5): s1 released its lease, so the heartbeat answers 3 (no lease); a held lock would have been rc 4
assert_eqx 3 "$rc" "P41 a heartbeat during a slow stop returns rc 3 (no lease), not 4 (the lock is not held across the stop)"
has "$T/e41a" "holds no lease" "P41 the heartbeat says it holds no lease"
# the bound is the lock timeout (4 s), not the heartbeat's own run time: a held lock means >= 4 s and rc 4
[ $((t1 - t0)) -lt 4 ] && ok "P41 the heartbeat did not wait for the stop ($((t1 - t0))s < lock timeout 4s)" || fail "P41 the heartbeat waited ($((t1 - t0))s, lock timeout 4s)"
JEV_LOCK_TIMEOUT=2 "$PLACE" acquire s2 --pid $$ >/dev/null 2>/dev/null; rc=$?
assert_eqx "5 refused_stopping" "$rc $(pl .placement.event)" "P41 an acquire during the stop is refused_stopping, not a lock timeout"
wait "$bg" 2>/dev/null
assert_eqx null "$(L '.sets["decide-a"]')" "P41 the slow stop completed and removed the set"
fresh; cap "$T/cap.json" fits does_not_fit
( PLACE_START_SLEEP=8 "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1 ) & bg=$!; jev_track_pid "$bg"
sleep 1
t0=$(date +%s); JEV_LOCK_TIMEOUT=4 "$PLACE" heartbeat sx 2>/dev/null; rc=$?; t1=$(date +%s)
assert_eqx 3 "$rc" "P41 a heartbeat during a slow start returns rc 3 (sx holds no lease), not 4 (no lock wait)"
[ $((t1 - t0)) -lt 4 ] && ok "P41 the heartbeat did not wait for the start ($((t1 - t0))s < lock timeout 4s)" || fail "P41 the heartbeat waited ($((t1 - t0))s, lock timeout 4s)"
JEV_LOCK_TIMEOUT=2 "$PLACE" acquire s2 --pid $$ >/dev/null 2>/dev/null; rc=$?
assert_eqx "5 refused_starting" "$rc $(pl .placement.event)" "P41 an acquire during the start is refused_starting, not a lock timeout"
wait "$bg" 2>/dev/null
assert_eqx "1 null 1" "$(starts) $(L '.sets["decide-a"].starting') $(L '.sets["decide-a"].leases|length')" "P41 the slow start completed: one start, mark cleared, one lease"
out="$("$PLACE" acquire s3 --pid $$ 2>/dev/null)"; rc=$?
assert_eqx "0 decide-a 1" "$rc $out $(starts)" "P41 after the start a new acquire joins"

# ---- P42 starting marks --------------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"
dead="$(bash -c 'echo $$')"
printf '{"sets":{"decide-a":{"constitution_started":true,"stopping":null,"starting":{"at":1700000000,"pid":%s,"pid_start":null},"leases":[]}}}\n' "$dead" > "$JEV_STATE_DIR/leases.json"
"$PLACE" reap 2>"$T/e42"
assert_eqx null "$(L '.sets["decide-a"].starting')" "P42 the starting mark of a starter that is gone is cleared"
printf '{"sets":{"decide-a":{"constitution_started":true,"stopping":null,"starting":{"at":1700000000,"pid":%s,"pid_start":null},"leases":[]}}}\n' "$$" > "$JEV_STATE_DIR/leases.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>/dev/null; rc=$?
assert_eqx "5 refused_starting 0" "$rc $(pl .placement.event) $(starts)" "P42 a live starter's mark is kept and refuses an acquire"

# ---- P43 one stop and one start call site (review R4-1) -----------------------------------------------------------------------
assert_eqx 1 "$(grep -c '"\$LLMCTL" stop' "$PLACE")" "P43 exactly one llmctl stop call site (do_stop)"
assert_eqx 1 "$(grep -c '"\$LLMCTL" start' "$PLACE")" "P43 exactly one llmctl start call site"
assert_eqx 1 "$(grep -c '"\$LLMCTL" capacity --json' "$PLACE")" "P43 CONTROL needle: the capacity call site is found (the instrument sees call sites)"
assert_eqx 0 "$(grep -c '"\$LLMCTL" frobnicate' "$PLACE")" "P43 CONTROL needle: a fabricated verb is not found"

# ---- P44 - P47 -----------------------------------------------------------------------------------------------------------------
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
"$PLACE" verdict --json > "$T/v44" 2>/dev/null
assert_eqx "ok null absent fits" "$(jq -r '[.candidates[] | "\(.state) \(.verdict)"] | join(" ")' "$T/v44")" "P44 verdict --json: decide-a ok (no capacity verdict), decide-b absent/fits"
fresh; cap "$T/cap.json" fits does_not_fit 5000 opweird
"$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e45"; rc=$?
assert_eqx "5 0 null" "$rc $(starts) $(L '.sets["decide-a"]')" "P45 a unit status outside ok/degraded: unknown, nothing started or adopted"
has "$T/e45" "not ok/degraded" "P45 the reason names the unit status"
fresh; rawcap "$T/cap.json" '.profiles["decide-b"].verdict = "does_not_fit" | .llmctl.units = [{unit:"llmctl-llama@decide-a.service", profile:"decide-a", owner:"self", status:"ok", reasons:[]}]'
"$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e46"; rc=$?
assert_eqx "5 0 null" "$rc $(starts) $(L '.sets["decide-a"]')" "P46 an own unit next to a non-running verdict: unknown, nothing started or adopted"
fresh; rawcap "$T/cap.json" '.measurement = {ok:false, reason:"psi read failed"} | .host.mem_available_mb = null'; export PLACE_CAP_RC=75
"$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e47"; rc=$?
assert_eqx "5 0 undetermined" "$rc $(starts) $(pl .placement.verdict)" "P47 measurement.ok false (exit 75) -> undetermined, no start"
has "$T/e47" "measurement failed" "P47 the reason names the failed measurement"

# ---- P48 no llmctl call under the lease lock, across the whole file (review R4-3) -----------------------------------------------
count_lockheld
assert_eqx 0 "$LOCKHELD_TOTAL" "P48 no llmctl call ran while the lease lock was held (stub LOCKHELD records over every scenario)"
fresh; cap "$T/cap.json"
( exec 9>>"$JEV_STATE_DIR/placement.lock"; "$FIXTURES/bin-place/llmctl" capacity --json >/dev/null 2>&1 )
assert_eqx 1 "$(grep -c '^LOCKHELD' "$STUB_LOG/llmctl.log" || true)" "P48 CONTROL: the stub records a call made with the lock file open (the instrument sees)"
: > "$STUB_LOG/llmctl.log"

# ---- P49 jev-status shows a `starting` mark next to `stopping` (round 5: the mark is new, the display must not hide it) ----
fresh
jq -n '{version:1, sets:{"decide-a":{leases:[], constitution_started:true, stopping:null, starting:{pid:1, since:1700000000}}}}' > "$JEV_STATE_DIR/leases.json"
JEV_STATUS_NO_VALIDATE=1 bash "${S4_STATUS_UNDER_TEST:-$ROOT/scripts/jev/jev-status.sh}" > "$T/st49" 2>/dev/null
has "$T/st49" "lease set decide-a: leases=0 constitution_started=true stopping=false starting=true" "P49 the human status names the starting mark"

# ---- P50 a HELD set whose unit turns degraded leaves the endpoint cache (§11.4.291(D)(1): the route switches first) ------
# Found while judging mutant M03: the refused_degraded path returned without normalising the cache against the current
# answer, so the gateway kept routing to a degraded model for as long as its lease was held.
fresh; cap "$T/cap.json"
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
assert_eqx 1 "$(cachen)" "P50 setup: the started set is in the cache"
PLACE_DEGRADED=decide-a "$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/e50"; rc=$?
assert_eqx "5 refused_degraded" "$rc $(pl '.placement.event')" "P50 the degraded unit is refused"
assert_eqx 0 "$(cachen)" "P50 no cache entry names the degraded (still held) model"
assert_eqx "1 0" "$(L '.sets["decide-a"].leases|length') $(stops)" "P50 the held set keeps its lease and is not stopped"
"$PLACE" acquire s3 --pid $$ >/dev/null 2>&1
assert_eqx 1 "$(cachen)" "P50 CONTROL: once the unit is ok again a join registers it again"

finish
