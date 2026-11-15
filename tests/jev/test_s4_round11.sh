#!/usr/bin/env bash
# test_s4_round11.sh - round 11 (2026-11-15) of the S4 placement producer scripts/jev/jev-place.sh (section 11.4.291),
# review of aaa2b3b0 (review_jev_r10.md; docs/qa/jev_s3s4_20261112/round11/). GATE-LOGIC tests (section 11.4.289(C)(2)): the
# stub llmctl in tests/jev/fixtures/bin-place answers from a declared file; these rows prove the producer DECIDES correctly,
# never that a local model runs. "RED-first" rows were run against aaa2b3b0 and failed there (round11/red_r11_on_r10.txt);
# "mutant row" rows exist to kill a named reviewer mutant (round11/mutants.md).
# Every interleaving is fixed by gates (bin-flockgate before a lock call, the stub's PLACE_START_GATE before the unit comes
# up, PLACE_STOP_GATE before the unit goes down); every age uses the test clocks. No row sleeps for a timing window.
#
#   R11-1 (R10-1, RED-first) the reviewer's probe shape, made deterministic: A's start is in flight, A's mark and A's pid-less
#         lease age out, B disposes the set and its stop returns BEFORE A's unit comes up; A records first, B second. The
#         unit must end stopped and the set gone; A's log names the real reason (another process's stopping mark, 0 leases);
#         B keeps the set with an owed stop and retries it; B never adopts the unit as operator-started.
#   R11-2 (R10-1, model check) every interleaving of A's two remaining events {unit up, record} with B's three {arm, stop,
#         record} (10 orders), for A's start rc 0, 1 and 75 (30 runs). Invariant at the end: no unit is running, no lease
#         set is left, llmctl start ran once, no set was adopted as operator-started.
#         For rc 75 (operator decision on R10-3, mutant W07) B's stop result never treats the refused start as a start:
#         no kept-after-arm set and at most one stop.
#   R11-3 (R10-1) the stopper dies before its record step: the owed stop A recorded is run by the next acquire.
#   R11-4 (mutant V01) a start's `placed` result keeps another process's starting mark.
#   R11-5 (mutant V05) a stop's turn refuses a set another process marked `starting` after the plan.
#   R11-6 (mutant V06) a set carrying stop_owed is never routed, even when its unit is observed ok.
#   R11-7 (mutant V07) a release does not list a set another process is starting as a stop candidate.
#   R11-8 (mutant V10) a placeholder hosted key is never a fallback route (route none, no key variable recorded).
#   R11-9 (mutant V11) a failed start found with its set gone (noset) keeps start_failed when its cleanup stop fails: the
#         next acquire retries the stop, it does not join the unit.
#   R11-10 (mutant W09) a start recorded after the arm plus a lease taken before the stop's record: kept for the holder, not
#         stopped again.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; FIXTURES="$HERE/fixtures"
# shellcheck source=lib_assert.sh
. "$HERE/lib_assert.sh"
PLACE="${S4_PLACE_UNDER_TEST:-$ROOT/scripts/jev/jev-place.sh}"
GATEBIN="$FIXTURES/bin-flockgate"

assert_eqx() { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (expected [$1] got [$2])"; fi; }
has()  { if grep -q -- "$2" "$1" 2>/dev/null; then ok "$3"; else fail "$3 (no [$2] in $1)"; fi; }
hasnt(){ if grep -q -- "$2" "$1" 2>/dev/null; then fail "$3 (found [$2] in $1)"; else ok "$3"; fi; }

cap() { # cap <file> — every field the §11.4.291(C) table requires (decide-a, decide-b fit as new starts)
  jq -n '
    {schema:"llmctl.capacity/1", time:1700000000, measurement:{ok:true, critical_inputs_unreadable:[]},
     host:{cpus_online:16, mem_total_mb:20000, mem_available_mb:18000, usable_mem_mb:15000, swap_total_mb:0, swap_free_mb:0,
           load:{"1":1.0,"5":1.0,"15":1.0}, psi:{memory:{some:0.0,full:0.0},cpu:{some:0.0},io:{some:0.0,full:0.0}}, cgroup:{memory_max_mb:null},
           nproc:{rlimit_soft:123694, rlimit_hard:123694, user_threads:400, headroom:5000}},
     reserve:{mem_reserved_mb:4000, cpus_reserved:4}, pressure:{ok:true, reasons:[]},
     llmctl:{units:[]}, fallback:{recommended:"cloud", key_variable:null}, unknown_profiles:[], degraded:false, largest_decision_fit:null,
     profiles:{"decide-a":{verdict:"fits", verdict_class:"fits", running:false, threads:3, reasons:[], headroom:{footprint_mb:1000}},
               "decide-b":{verdict:"fits", verdict_class:"fits", running:false, threads:3, reasons:[], headroom:{footprint_mb:1000}}}}' > "$1"
}
TRD="$(mktemp -d)"; NTRACE=0
case "$TRD" in "${TMPDIR:-/tmp}"/*) ;; *) echo "FATAL: trace dir outside TMPDIR ($TRD)" >&2; exit 2 ;; esac
LOCKHELD_TOTAL=0
count_lockheld() { local n=0; [ -n "${STUB_LOG:-}" ] && [ -f "$STUB_LOG/llmctl.log" ] && n="$(grep -c '^LOCKHELD' "$STUB_LOG/llmctl.log" || true)"; LOCKHELD_TOTAL=$((LOCKHELD_TOTAL + ${n:-0})); }
T0=1700000000; M0=5000
fresh() {
  count_lockheld
  make_fixture_env s4r11
  NTRACE=$((NTRACE+1))
  export PATH="$FIXTURES/bin-place:$PATH" JEV_TEST=1 PLACE_CAP_JSON="$T/cap.json" JEV_LOCK_TIMEOUT=2 JEV_TRACE_FILE="$TRD/trace.$NTRACE"
  unset PLACE_CAP_RC PLACE_CAP_RC_FILE PLACE_CAP_SLEEP PLACE_CAP_RAW PLACE_CAP_GATE PLACE_CAP_GATE_AT PLACE_CAP_GATE_WHEN \
        PLACE_START_RC PLACE_START_SLEEP PLACE_STOP_RC PLACE_STOP_SLEEP PLACE_DEGRADED PLACE_GONE PLACE_FULL_AFTER PLACE_DCAP_RC \
        PLACE_STATUS_RC PLACE_STATUS_URL PLACE_STATUS_NOGW JEV_LLMCTL_TIMEOUT JEV_LLMCTL_START_TIMEOUT JEV_PLACE_MAX \
        JEV_PLACE_PROFILES LLMCTL_GATEWAY_URL LLMCTL_CACERT LLMCTL_TENANT_ID JEV_LEASE_TTL JEV_REEVAL_CADENCE JEV_RECORD_RETRIES \
        JEV_PROJECT FLOCK_GATE_DIR FLOCK_GATE_AT FLOCK_GATE_KILL_AT JEV_MONO_FILE \
        JEV_NOW_FILE PLACE_CAP_CLOCK_ADD PLACE_START_CLOCK_ADD PLACE_STOP_CLOCK_ADD PLACE_START_SNAPSHOT PLACE_STOP_SNAPSHOT PLACE_STOP_GATE \
        PLACE_START_GATE TYPESAFE_API_KEY OPENROUTER_API_KEY
  : > "$STUB_LOG/llmctl.log"
  cap "$T/cap.json"
  export JEV_NOW_FILE="$T/now"; clockset "$T0"
}
clockset() { printf '%s\n' "$1" > "$JEV_NOW_FILE"; }
monoset() { export JEV_MONO_FILE="$T/mono"; printf '%s\n' "$1" > "$JEV_MONO_FILE"; }
stopsof() { grep -c "^llmctl stop $1\$" "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
L() { jq -r "$1" "$JEV_STATE_DIR/leases.json" 2>/dev/null; }
holders() { L "[.sets[\"$1\"].leases[]?.holder] | join(\",\")"; }
routed() { if jq -e 'any(.endpoints[]?; .provider_id == "llmctl-local")' "$CMA_PROVIDERS_DIR/jev-endpoints.json" >/dev/null 2>&1; then echo yes; else echo no; fi; }
running() { (cd "$STUB_LOG" && for f in running.*; do [ -e "$f" ] && printf '%s ' "${f#running.}"; done); }
wait_file() { local n=0; while [ "$n" -lt "${2:-900}" ]; do [ -e "$1" ] && return 0; sleep 0.1; n=$((n+1)); done; return 1; }
waitb() { # bounded wait: past the deadline TERM (pid > 1 only, §11.4.263) and 124
  local p="$1" lim n=0; lim=$(( ${2:-300} * 10 ))
  while kill -0 "$p" 2>/dev/null; do
    if [ "$n" -ge "$lim" ]; then
      fail "waitb: pid $p still running after ${2:-300} s (a loop or a hang); sent TERM"
      if [ "$p" -gt 1 ] 2>/dev/null; then kill -TERM "$p" 2>/dev/null; fi
      wait "$p" 2>/dev/null; return 124
    fi
    sleep 0.1; n=$((n+1))
  done
  wait "$p"
}
proc_start_of() { local st; local -a f; st="$(cat "/proc/$1/stat" 2>/dev/null)" || return 0; st="${st##*') '}"; read -ra f <<<"$st"; printf '%s\n' "${f[19]:-}"; }
live_proc() { sleep 600 & HP=$!; jev_track_pid "$HP"; HPST="$(proc_start_of "$HP")"; }
gated() { # gated <gate-dir> <gate-at> <kill-at> <out-prefix> [NAME=value ...] -- <jev-place args>; sets GPID
  local d="$1" at="$2" kat="$3" o="$4"; shift 4
  local -a envs=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  mkdir -p "$d"
  # shellcheck disable=SC2030
  ( export PATH="$GATEBIN:$PATH" FLOCK_GATE_DIR="$d" FLOCK_GATE_AT="$at" FLOCK_GATE_KILL_AT="$kat" JEV_LOCK_TIMEOUT=10
    exec env "${envs[@]}" "$PLACE" "$@" > "$o.out" 2> "$o.err" ) &
  GPID=$!; jev_track_pid "$GPID"
}
reach() { if wait_file "$1/reached.$2"; then ok "$3 (paused at flock call $2)"; else fail "$3: never reached flock call $2"; fi; }
go() { : > "$1/go.$2"; }
reachstop() { if wait_file "$1/reached.stop.$2"; then ok "$3 (its stop of $2 is in flight)"; else fail "$3: the stop of $2 never began"; fi; }
gostop() { : > "$1/go.stop.$2"; }
under_lock() { # a registry write by another writer, under the lock (gen raised)
  local filt="$1"; shift
  ( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock -w 10 8 || exit 4
    jq -c "$@" "(.gen = ((.gen // 0) + 1)) | $filt" "$JEV_STATE_DIR/leases.json" > "$JEV_STATE_DIR/leases.json.w" \
      && mv -f -- "$JEV_STATE_DIR/leases.json.w" "$JEV_STATE_DIR/leases.json" )
}
reg() { jq -c "$@" > "$JEV_STATE_DIR/leases.json"; }

waitany() { # waitany <pid> <file>... : until one file exists or the pid is gone (bounded 60 s) -> 0, 1 on timeout
  local p="$1" n=0 f; shift
  while [ "$n" -lt 600 ]; do
    for f in "$@"; do [ -e "$f" ] && return 0; done
    kill -0 "$p" 2>/dev/null || return 0
    sleep 0.1; n=$((n+1))
  done
  return 1
}
starts() { grep -c "^llmctl start $1\$" "$STUB_LOG/llmctl.log" 2>/dev/null || true; }

# ---- calibration: the flock call numbers of A's record step and of B's arm step ---------------------------------------
# A: acquire decide-a with no pid; its start waits at the stub's start gate. B: a second acquire after both clocks
# advanced; it disposes the set and its stop waits at the stop gate. A's record step is A's next lock call; B's arm is the
# lock call just before its stop (lock, unlock, stop), B's record step the lock call after it. Control needle: those numbers
# must be lock calls (not `flock -u`) in the call logs.
mc_launch() { # mc_launch <rc> <A gate list> <B gate list> [B kill-at]
  local rc="$1" ga="$2" gb="$3" kb="${4:-0}"
  fresh; monoset "$M0"; SG="$T/sg"; mkdir -p "$SG"
  gated "$T/gA" "$ga" 0 "$T/a" JEV_PLACE_PROFILES=decide-a PLACE_START_GATE="$SG" PLACE_START_RC="$rc" -- acquire sA; AP=$GPID
  wait_file "$SG/reached.start.decide-a" 1200 || { fail "mc: A's start never began"; return 1; }
  monoset $(( M0 + 2400 ))
  gated "$T/gB" "$gb" "$kb" "$T/b" JEV_PLACE_PROFILES=decide-a PLACE_STOP_GATE="$SG" -- acquire sB; BP=$GPID
}
mc_launch 0 0 0
wait_file "$SG/reached.stop.decide-a" 300 || fail "calibration: B's stop never began"
NA=$(( $(cat "$T/gA/count") + 1 )); NB=$(( $(cat "$T/gB/count") - 1 ))
gostop "$SG" decide-a; waitb "$BP" 120; : > "$SG/go.start.decide-a"; waitb "$AP" 120
if grep -q "^flock#$NA -u" "$T/gA/calls.log" || ! grep -q "^flock#$NA " "$T/gA/calls.log"; then fail "calibration: A's call $NA is not a lock call"; else ok "calibration: A records at flock call $NA"; fi
if grep -q "^flock#$NB -u" "$T/gB/calls.log" || ! grep -q "^flock#$((NB+1)) -u" "$T/gB/calls.log"; then fail "calibration: B's call $NB is not its arm lock"; else ok "calibration: B arms at flock call $NB, records at $((NB+2))"; fi

# ---- R11-1 (R10-1): the reviewer's probe, deterministic --------------------------------------------------------------
mc_launch 0 "$NA" "$NB,$((NB+2))"
reach "$T/gB" "$NB" "R11-1 B planned the disposal and is paused before its arm step"
go "$T/gB" "$NB"; reachstop "$SG" decide-a "R11-1 B armed its stop"
gostop "$SG" decide-a; reach "$T/gB" "$((NB+2))" "R11-1 B's stop returned rc 0 before A's unit came up; B is paused before its record step"
assert_eqx "" "$(running)" "R11-1 CONTROL: no unit runs (B's stop came first)"
: > "$SG/go.start.decide-a"; reach "$T/gA" "$NA" "R11-1 A's start returned rc 0 (the unit is up); A is paused before its record step"
assert_eqx "decide-a " "$(running)" "R11-1 CONTROL: A's unit is up after B's stop"
BPID_MARK="$(L '.sets["decide-a"].stopping.pid')"
go "$T/gA" "$NA"; waitb "$AP" 120; arc=$?
assert_eqx "5 true true $BPID_MARK" "$arc $(L '.sets["decide-a"].constitution_started') $(L '.sets["decide-a"].stop_owed != null') $(L '.sets["decide-a"].start_kept.seen_stopping.pid')" \
  "R11-1 A keeps the set constitution-started, records the stopping mark it saw and an owed stop; A runs no stop of its own"
hasnt "$T/a.err" "held by 0 other lease" "R11-1 A's log does not claim the set is held by other leases"
has "$T/a.err" "no other lease holds the set, but another process (pid $BPID_MARK) marks it stopping" "R11-1 A's log names the real reason"
go "$T/gB" "$((NB+2))"; waitb "$BP" 120
has "$T/b.err" "a start of decide-a was recorded after this stop was armed" "R11-1 B sees A's start record and does not delete the set"
hasnt "$T/b.err" "joined the already-running unit" "R11-1 B never adopts the unit as operator-started"
assert_eqx "2 1  {}" "$(stopsof decide-a) $(starts decide-a) $(running) $(jq -c .sets "$JEV_STATE_DIR/leases.json")" "R11-1 B retries the owed stop: the unit is stopped and the set is gone (never orphaned)"

# ---- R11-2 (R10-1): model check of the two-process start/stop race -----------------------------------------------------
mc_ev() { # mc_ev <event>: release one event and wait until the process reaches its next gate or exits
  case "$1" in
    a) : > "$SG/go.start.decide-a"; waitany "$AP" "$T/gA/reached.$NA" ;;
    A) go "$T/gA" "$NA"; waitb "$AP" 120 >/dev/null; [ "$?" != 124 ] ;;
    s) go "$T/gB" "$NB"; waitany "$BP" "$SG/reached.stop.decide-a" "$T/gB/reached.$((NB+2))" ;;
    t) gostop "$SG" decide-a; waitany "$BP" "$T/gB/reached.$((NB+2))" ;;
    r) go "$T/gB" "$((NB+2))"; waitb "$BP" 120 >/dev/null; [ "$?" != 124 ] ;;
  esac
}
MC_ORDERS="aAstr asAtr astAr astrA saAtr satAr satrA staAr starA straA"
nmc=0; nbad=0; n75ctl=0
for rc in 0 1 75; do
  for o in $MC_ORDERS; do
    mc_launch "$rc" "$NA" "$NB,$((NB+2))"
    if ! wait_file "$T/gB/reached.$NB" 300; then fail "R11-2 rc $rc order $o: B never reached its arm gate (calibration)"; nbad=$((nbad+1)); continue; fi
    i=0; while [ "$i" -lt "${#o}" ]; do mc_ev "${o:$i:1}" || fail "R11-2 rc $rc order $o: event ${o:$i:1} timed out"; i=$((i+1)); done
    kill -0 "$AP" 2>/dev/null && waitb "$AP" 60; kill -0 "$BP" 2>/dev/null && waitb "$BP" 60
    got="$(running)|$(jq -c .sets "$JEV_STATE_DIR/leases.json" 2>/dev/null)|$(starts decide-a)|$(grep -c 'joined the already-running unit' "$T/a.err" "$T/b.err" | awk -F: '{s+=$2} END {print s+0}')"
    nmc=$((nmc+1))
    if [ "$got" = "|{}|1|0" ]; then :; else nbad=$((nbad+1)); fail "R11-2 rc $rc order $o: end state running=[${got%%|*}] rest=[${got#*|}] (expected no unit, no set, one start, no adoption)"; fi
    if [ "$rc" = 75 ]; then
      # operator decision (R10-3): a refused start started nothing, so B's stop result never treats it as a start that
      # may have brought the unit up (no kept set, no owed stop, no second stop of a unit that was never started)
      n75="$(grep -c 'was recorded after this stop was armed' "$T/b.err" 2>/dev/null || true)"
      if [ "${n75:-0}" = 0 ] && [ "$(stopsof decide-a)" -le 1 ]; then :; else
        nbad=$((nbad+1)); fail "R11-2 rc 75 order $o: B treated the refused start as a start (kept-after-arm lines ${n75:-0}, stops $(stopsof decide-a))"; fi
      case "$o" in a*) ;; *) grep -q 'marks it stopping' "$T/a.err" && n75ctl=$((n75ctl+1)) ;; esac
    fi
  done
done
assert_eqx yes "$( [ "${n75ctl:-0}" -ge 1 ] && echo yes || echo no )" "R11-2 CONTROL: at least one rc 75 order reaches A's not-sole record with B's stopping mark (count ${n75ctl:-0})"
assert_eqx "30 0" "$nmc $nbad" "R11-2 all 30 interleavings (rc 0, 1, 75 x 10 orders) end with no unit running, no lease set, one start, no adoption"

# ---- R11-3 (R10-1): the stopper dies before its record step ----------------------------------------------------------
mc_launch 0 "$NA" "$NB" "$((NB+2))"
reach "$T/gB" "$NB" "R11-3 B is paused before its arm step"
go "$T/gB" "$NB"; reachstop "$SG" decide-a "R11-3 B armed its stop"
gostop "$SG" decide-a; waitb "$BP" 120
[ -e "$T/gB/killed" ] && ok "R11-3 CONTROL: B was killed at its record step" || fail "R11-3 B was not killed at its record step"
: > "$SG/go.start.decide-a"; reach "$T/gA" "$NA" "R11-3 A's unit is up; A is paused before its record step"
go "$T/gA" "$NA"; waitb "$AP" 120
assert_eqx "true decide-a " "$(L '.sets["decide-a"].stop_owed != null') $(running)" "R11-3 the unit runs and the set carries the owed stop A recorded"
( export JEV_PLACE_PROFILES=decide-a PLACE_START_RC=75; exec "$PLACE" acquire sC > "$T/c3.out" 2> "$T/c3.err" )
has "$T/c3.err" "retried the cleanup stop of decide-a" "R11-3 the next acquire runs the owed stop (the dead stopper's mark is reaped first)"
assert_eqx "2 " "$(stopsof decide-a) $(running)" "R11-3 the unit is stopped (never orphaned)"

# ---- R11-4 (mutant V01): placed keeps a foreign starting mark ---------------------------------------------------------
fresh; live_proc
gated "$T/gA" 7 0 "$T/a4" JEV_PLACE_PROFILES=decide-a -- acquire sA --pid $$; a=$GPID
reach "$T/gA" 7 "R11-4 A's start returned rc 0; A is paused before its record step"
under_lock '.sets["decide-a"].starting = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"hS"}' --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
go "$T/gA" 7; waitb "$a"; arc=$?
assert_eqx "0 $HP sA" "$arc $(L '.sets["decide-a"].starting.pid') $(holders decide-a)" "R11-4 A is placed and the other process's starting mark is kept (only A's own mark is ever cleared)"

# ---- R11-5 (mutant V05): a stop's turn refuses a set marked starting after the plan -----------------------------------
rset() { reg -n --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0" "$@"; }
craft_b() { rset '{gen:1, sets:{"decide-b":{constitution_started:true, started_at:$t, stopping:null, starting:null,
  leases:[{holder:"sA", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}}'; : > "$STUB_LOG/running.decide-b"; }
fresh; live_proc; craft_b; SG="$T/sg5"; mkdir -p "$SG"
gated "$T/gC" 0 0 "$T/c5" PLACE_STOP_GATE="$SG" -- release sA; c=$GPID
reachstop "$SG" decide-b "R11-5 calibration: the release stops decide-b"; NR=$(( $(cat "$T/gC/count") - 1 ))
gostop "$SG" decide-b; waitb "$c"
fresh; live_proc; craft_b
gated "$T/gR" "$NR" 0 "$T/r5" -- release sA; r=$GPID
reach "$T/gR" "$NR" "R11-5 the release is paused before its stop's arm step"
under_lock '.sets["decide-b"].starting = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"hS"}' --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
go "$T/gR" "$NR"; waitb "$r"
has "$T/r5.err" "another process is starting it" "R11-5 the arm step refuses the set another process is starting"
assert_eqx "0 decide-b  $HP" "$(stopsof decide-b) $(running) $(L '.sets["decide-b"].starting.pid')" "R11-5 no stop runs; the unit and the other process's mark are kept"

# ---- R11-6 (mutant V06): a stop_owed set is never routed ---------------------------------------------------------------
craft_a() { rset --arg owed "$1" '{gen:1, gateway:{url:"https://127.0.0.1:18095", ca:"", source:"crafted"}, sets:{"decide-a":({constitution_started:true, started_at:$t, stopping:null, starting:null,
  leases:[{holder:"sA", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}
  + (if $owed == "1" then {stop_owed:{at:$t, reason:"test"}} else {} end))}}'; : > "$STUB_LOG/running.decide-a"; }
fresh; live_proc; craft_a 0
"$PLACE" heartbeat sA > /dev/null 2> "$T/h6c.err"
assert_eqx "ok yes" "$(L '.sets["decide-a"].health.state') $(routed)" "R11-6 CONTROL: the same set without stop_owed is observed ok and routed"
fresh; live_proc; craft_a 1
"$PLACE" heartbeat sA > /dev/null 2> "$T/h6.err"
assert_eqx "ok no" "$(L '.sets["decide-a"].health.state') $(routed)" "R11-6 a set carrying stop_owed is observed ok but never routed"

# ---- R11-7 (mutant V07): a release does not list a set being started --------------------------------------------------
fresh; live_proc; craft_b
under_lock '.sets["decide-b"].starting = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"hS"}' --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
"$PLACE" release sA > /dev/null 2> "$T/r7.err"
hasnt "$T/r7.err" "stop of decide-b (release) not run at its turn" "R11-7 the set being started is not a stop candidate of the release"
assert_eqx "0 $HP" "$(stopsof decide-b) $(L '.sets["decide-b"].starting.pid')" "R11-7 nothing is stopped; the starter's mark is kept"

# ---- R11-8 (mutant V10): a placeholder hosted key is never a fallback route --------------------------------------------
# the values are built in Python and are fake (section 11.4.10): never a real key
mapfile -t PH < <(python3 -I -c 'print("chan" + "geme"); print("q" * 24); print("short" + "1234"); print("<" + "your-key" + ">")')
REALISH="$(python3 -I -c 'import string; print("tsk-fake-" + string.ascii_letters[3:27])')"
for ph in "${PH[@]}" "$REALISH"; do
  fresh; jq '.schema="llmctl.capacity/2"' "$T/cap.json" > "$T/c2" && mv -f -- "$T/c2" "$T/cap.json"
  export TYPESAFE_API_KEY="$ph"
  "$PLACE" acquire s1 > /dev/null 2> "$T/e8"
  got="$(jq -r '"\(.placement.route) \(.placement.key_variable)"' "$JEV_STATE_DIR/placement.json")"
  unset TYPESAFE_API_KEY
  if [ "$ph" = "$REALISH" ]; then assert_eqx "cloud TYPESAFE_API_KEY" "$got" "R11-8 CONTROL: a well-formed (fake) key gives route cloud"
  else assert_eqx "none null" "$got" "R11-8 a placeholder key (length ${#ph}) gives route none, no key variable"; fi
  if grep -rqF -- "$ph" "$JEV_STATE_DIR" "$T/e8"; then fail "R11-8 the key value was written"; fi
done

# ---- R11-9 (mutant V11): noset failed start + failed cleanup stop -> the next acquire retries the stop -------------------
fresh; live_proc; SG="$T/sg9"; mkdir -p "$SG"
( export JEV_PLACE_PROFILES=decide-a PLACE_START_GATE="$SG" PLACE_START_RC=1 PLACE_STOP_RC=1; exec "$PLACE" acquire sA --pid $$ > "$T/a9.out" 2> "$T/a9.err" ) &
a=$!; jev_track_pid "$a"
wait_file "$SG/reached.start.decide-a" 1200 || { fail "R11-9 A's start never began"; sed 's/^/# a9: /' "$T/a9.err"; sed 's/^/# llmctl: /' "$STUB_LOG/llmctl.log"; }
under_lock 'del(.sets["decide-a"])'
: > "$SG/go.start.decide-a"; waitb "$a"
assert_eqx "true true decide-a " "$(L '.sets["decide-a"].start_failed != null') $(L '.sets["decide-a"].stop_failed != null') $(running)" \
  "R11-9 the failed start found no set: it is recorded with start_failed and the failed cleanup stop with stop_failed; the unit runs"
( export JEV_PLACE_PROFILES=decide-a PLACE_START_RC=75; exec "$PLACE" acquire sC --pid $$ > "$T/c9.out" 2> "$T/c9.err" )
has "$T/c9.err" "retried the cleanup stop of decide-a" "R11-9 the next acquire retries the cleanup stop"
hasnt "$T/c9.err" "lease joined: holder=sC profile=decide-a" "R11-9 the next acquire does not join the unit that is owed a stop"
assert_eqx "2 " "$(stopsof decide-a) $(running)" "R11-9 the unit is stopped"

# ---- R11-10 (mutant W09): a start recorded after the arm, then a lease taken before the stop's record -----------------
# the stop's result finds another lease: the set is kept for that holder (stopped_while_held), and the stopper does NOT
# retry a stop of a unit someone now holds (the owed stop waits for the set to be lease-less, plan step A)
mc_launch 0 "$NA" "$NB,$((NB+2))"; live_proc
reach "$T/gB" "$NB" "R11-10 B is paused before its arm step"
go "$T/gB" "$NB"; reachstop "$SG" decide-a "R11-10 B armed its stop"
gostop "$SG" decide-a; reach "$T/gB" "$((NB+2))" "R11-10 B's stop returned; B is paused before its record step"
: > "$SG/go.start.decide-a"; reach "$T/gA" "$NA" "R11-10 A's unit is up; A is paused before its record step"
go "$T/gA" "$NA"; waitb "$AP" 120
under_lock '.sets["decide-a"].leases += [{holder:"hX", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:false}]' \
  --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
go "$T/gB" "$((NB+2))"; waitb "$BP" 120
assert_eqx "1 decide-a  hX 1" "$(stopsof decide-a) $(running) $(holders decide-a) $(L '.sets["decide-a"].stopped_while_held.leases')" \
  "R11-10 the set is kept for hX (stopped_while_held), the unit hX holds is not stopped again"
hasnt "$T/b.err" "a start of decide-a was recorded after this stop was armed" "R11-10 the start-after-arm rule applies only to a lease-less set"

count_lockheld
assert_eqx 0 "$LOCKHELD_TOTAL" "P67 no llmctl call ran while the lease lock was held (across this file)"
case "$TRD" in "${TMPDIR:-/tmp}"/tmp.*) rm -rf -- "${TRD:?}" ;; esac
finish
