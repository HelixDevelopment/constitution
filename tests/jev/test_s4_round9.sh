#!/usr/bin/env bash
# test_s4_round9.sh — round 9 (2026-11-15) of the S4 placement producer scripts/jev/jev-place.sh (§11.4.291), review of
# 3bd53782 (docs/qa/jev_s3s4_20261112/round9/). GATE-LOGIC tests (§11.4.289(C)(2)): the stub llmctl in
# tests/jev/fixtures/bin-place answers from a declared file; these rows prove the producer DECIDES correctly, never that a
# local model runs. "RED-first" rows were run against 3bd53782 and failed there (round9/red_*.txt); "mutant row" rows pass
# on 3bd53782 too and exist to kill a named mutant (round9/mutants.md); "behaviour row" rows pin a rule that round 9 changed
# on purpose (they fail on 3bd53782 because the old rule was different, not because it was a defect there).
# Every stop interleaving uses the stub's PLACE_STOP_GATE (a file gate, no timing window); every age uses the advancing
# test clock JEV_NOW_FILE (and JEV_MONO_FILE for the monotonic clock), so the expected stamps follow from the calls made.
#
#   P99  (R8-1)  ONE acquire disposes two sets: each `stopping` mark is written at the set's OWN turn (the second carries
#                the clock after the first stop), an observer keeps it, and a session asking while it is in flight is
#                refused (endpoint_stopping) and loses no lease. The review's reproduction, made deterministic. RED-first
#   P100 (R8-1)  two stoppers: a set already stopped by another session at A's turn is not stopped again (one stop). Mutant row
#   P101 (R8-1)  a release that stops two sets: a set joined while the first stop runs is kept (judged at its turn); the
#                joiner keeps its lease. Behaviour row (3bd53782 marked both at release time and refused the joiner)
#   P102 (R8-2)  a set that holds a lease when its stop returns rc 0 is KEPT (stopped_while_held, health pending, not
#                routed) and the next observation releases the lease as endpoint_gone; a set carrying ANOTHER stopper's mark
#                is kept with that mark. CRAFTED STATE (a writer that adds a lease to a marked set). RED-first
#   P103 (RV08, RV06) a mark's age is judged at the time of the locked section that judges it, not at process start;
#                mark_cleared.at and health.at carry that time. Mutant row
#   P104 (RV09)  a pid-less lease's heartbeat age is judged at the same time. Mutant row
#   P105 (RV03)  gone.at is the time of the observation that found the unit gone. Mutant row
#   P106 (RV05)  a failed disposal stop records stop_owed.at / stop_failed.at at the time the result is recorded. Mutant row
#   P107 (R8-1 census) every bounded `llmctl stop` / `llmctl start` of every scenario in this file runs under a mark its
#                process wrote AFTER its previous bounded call (tests/jev/fixtures/mark_census.py over the producer's
#                JEV_TRACE_FILE trace), plus the census's own golden-bad / empty controls
#   P108 (RV07)  a heartbeat refreshes heartbeat_at and heartbeat_mono at the time of its locked section. Mutant row
#   P109 (RV10)  a start whose lease was released during the start records started_at when the result is recorded. Mutant row
#   P110 (RV12)  the producer's OWN marks carry pid, pid_start (this process's start time), mono and holder. RED-first
#   P111 (R8-6)  THE MONOTONIC CLOCK: an NTP step of the wall clock neither expires a live mark nor keeps an old one; a
#                mark from another boot is expired; a mark without `mono` (an older producer) is judged on wall time; an
#                unreadable JEV_MONO_FILE is a config error; with no seam the producer writes "<boot id>:<uptime>". RED-first
#   P112 (R8-1 class) a lease is not reaped while a live mark names its holder (the acquire's start is in flight), the
#                acquire refreshes it when it records, the suspension ends with the mark, and a DEAD holder is never kept
#   P113 (R8-1 class) a join is not taken in a plan that also stops a set; it is taken by the fresh plan after the stops,
#                so the lease is written after the last bounded call. Behaviour row
#   P114 (R8-1)  a disposal planned on a degraded answer is NOT run when the set is recorded ok again at its turn (the
#                pressure cleared while an earlier stop ran). Behaviour row
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; FIXTURES="$HERE/fixtures"
# shellcheck source=lib_assert.sh
. "$HERE/lib_assert.sh"
PLACE="${S4_PLACE_UNDER_TEST:-$ROOT/scripts/jev/jev-place.sh}"
GATEBIN="$FIXTURES/bin-flockgate"
CENSUS="$FIXTURES/mark_census.py"

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
# the trace of every scenario (P107): one file per fresh(), in a directory this process created (removed at exit)
TRD="$(mktemp -d)"; NTRACE=0
case "$TRD" in "${TMPDIR:-/tmp}"/*) ;; *) echo "FATAL: trace dir outside TMPDIR ($TRD)" >&2; exit 2 ;; esac
LOCKHELD_TOTAL=0
count_lockheld() { local n=0; [ -n "${STUB_LOG:-}" ] && [ -f "$STUB_LOG/llmctl.log" ] && n="$(grep -c '^LOCKHELD' "$STUB_LOG/llmctl.log" || true)"; LOCKHELD_TOTAL=$((LOCKHELD_TOTAL + ${n:-0})); }
T0=1700000000; M0=5000
fresh() {
  count_lockheld
  make_fixture_env s4r9
  NTRACE=$((NTRACE+1))
  export PATH="$FIXTURES/bin-place:$PATH" JEV_TEST=1 PLACE_CAP_JSON="$T/cap.json" JEV_LOCK_TIMEOUT=2 JEV_TRACE_FILE="$TRD/trace.$NTRACE"
  unset PLACE_CAP_RC PLACE_CAP_RC_FILE PLACE_CAP_SLEEP PLACE_CAP_RAW PLACE_CAP_GATE PLACE_CAP_GATE_AT PLACE_CAP_GATE_WHEN \
        PLACE_START_RC PLACE_START_SLEEP PLACE_STOP_RC PLACE_STOP_SLEEP PLACE_DEGRADED PLACE_GONE PLACE_FULL_AFTER PLACE_DCAP_RC \
        PLACE_STATUS_RC PLACE_STATUS_URL PLACE_STATUS_NOGW JEV_LLMCTL_TIMEOUT JEV_LLMCTL_START_TIMEOUT JEV_PLACE_MAX \
        JEV_PLACE_PROFILES LLMCTL_GATEWAY_URL LLMCTL_CACERT LLMCTL_TENANT_ID JEV_LEASE_TTL JEV_REEVAL_CADENCE JEV_RECORD_RETRIES \
        JEV_PROJECT FLOCK_GATE_DIR FLOCK_GATE_AT FLOCK_GATE_KILL_AT JEV_MONO_FILE \
        JEV_NOW_FILE PLACE_CAP_CLOCK_ADD PLACE_START_CLOCK_ADD PLACE_STOP_CLOCK_ADD PLACE_START_SNAPSHOT PLACE_STOP_SNAPSHOT PLACE_STOP_GATE
  : > "$STUB_LOG/llmctl.log"
  cap "$T/cap.json"
  export JEV_NOW_FILE="$T/now"; clockset "$T0"
}
clockset() { printf '%s\n' "$1" > "$JEV_NOW_FILE"; }
clk() { tr -dc '0-9' < "$JEV_NOW_FILE"; }
stopsof() { grep -c "^llmctl stop $1\$" "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
starts() { grep -c '^llmctl start' "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
caps() { grep -c '^llmctl capacity --json$' "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
L() { jq -r "$1" "$JEV_STATE_DIR/leases.json" 2>/dev/null; }
running() { (cd "$STUB_LOG" && for f in running.*; do [ -e "$f" ] && printf '%s ' "${f#running.}"; done); }
wait_file() { local n=0; while [ "$n" -lt "${2:-900}" ]; do [ -e "$1" ] && return 0; sleep 0.1; n=$((n+1)); done; return 1; }
waitb() { # bounded wait (as round 8): past the deadline TERM (pid > 1 only, §11.4.263) and 124
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
# a live process this test owns (a holder or a marker that stays alive): HP + HPST
live_proc() { sleep 600 & HP=$!; jev_track_pid "$HP"; HPST="$(proc_start_of "$HP")"; }
gated() { # as round 8: "$PLACE" behind the flock gate; GPID
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
# under_lock <jq filter> [jq args...]: a registry write by another writer, under the lock (gen raised)
under_lock() {
  local filt="$1"; shift
  ( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock -w 10 8 || exit 4
    jq -c "$@" "(.gen = ((.gen // 0) + 1)) | $filt" "$JEV_STATE_DIR/leases.json" > "$JEV_STATE_DIR/leases.json.w" \
      && mv -f -- "$JEV_STATE_DIR/leases.json.w" "$JEV_STATE_DIR/leases.json" )
}
reg() { jq -c "$@" > "$JEV_STATE_DIR/leases.json"; }
# two lease-less, constitution-started, degraded sets (the review's scenario); both units run
two_degraded() {
  reg -n --argjson t "$T0" '{gen:1, sets:{
    "decide-a":{constitution_started:true, started_at:$t, starting:null, stopping:null, leases:[], health:{state:"degraded", reason:"crafted", seq:0, at:$t}},
    "decide-b":{constitution_started:true, started_at:$t, starting:null, stopping:null, leases:[], health:{state:"degraded", reason:"crafted", seq:0, at:$t}}}}'
  : > "$STUB_LOG/running.decide-a"; : > "$STUB_LOG/running.decide-b"
}
TTL43() { export JEV_LLMCTL_START_TIMEOUT=10 JEV_RECORD_RETRIES=1 JEV_LOCK_TIMEOUT=1; }   # MARK_TTL = 10 + 2 + 1 + 30 = 43
MT=338   # MARK_TTL with the defaults: 300 + 2 + 3 x 2 + 30 (JEV_LOCK_TIMEOUT=2 in fresh)

# ---- P99 (R8-1) + P110 (RV12, stopping mark): one acquire, two disposal stops -----------------------------------------
fresh; TTL43; two_degraded; SG="$T/sg"; mkdir -p "$SG"
( export PLACE_DEGRADED=decide-a,decide-b PLACE_STOP_CLOCK_ADD=44 PLACE_STOP_SNAPSHOT=1 PLACE_STOP_GATE="$SG"
  exec "$PLACE" acquire sA --pid $$ > "$T/a99.out" 2> "$T/a99.err" ) &
APID=$!; jev_track_pid "$APID"
reachstop "$SG" decide-a "P99 A disposes decide-a first"
APST="$(proc_start_of "$APID")"
gostop "$SG" decide-a
reachstop "$SG" decide-b "P99 then decide-b"
assert_eqx "$(( T0 + 44 ))" "$(clk)" "P99 CONTROL: the first stop took 44 s of the test clock (MARK_TTL is 43 s)"
S1="$STUB_LOG/leases_at_stop.decide-a.1.json"; S2="$STUB_LOG/leases_at_stop.decide-b.1.json"
assert_eqx "$T0 null" "$(jq -r '.sets["decide-a"].stopping.at' "$S1") $(jq -r '.sets["decide-b"].stopping' "$S1")" "P99 while decide-a is stopped, decide-b carries NO mark yet (it is marked at its own turn)"
assert_eqx "$(( T0 + 44 ))" "$(jq -r '.sets["decide-b"].stopping.at' "$S2")" "P99 decide-b's mark carries the time of ITS turn (after the first stop), not the plan's"
assert_eqx "$APID $APST test:$(( T0 + 44 )) sA" "$(jq -r '.sets["decide-b"].stopping | "\(.pid) \(.pid_start) \(.mono) \(.holder)"' "$S2")" "P110 the producer's own stopping mark: pid, pid_start (its start time), mono, holder"
PLACE_DEGRADED=decide-a,decide-b "$PLACE" reap > /dev/null 2> "$T/o99.err"
hasnt "$T/o99.err" "cleared the stopping mark" "P99 an observer keeps the live stopper's mark (its age is 0, not 44)"
assert_eqx "$APID" "$(L '.sets["decide-b"].stopping.pid')" "P99 after the observer the mark is still A's"
( exec "$PLACE" acquire sC --pid $$ > "$T/c99.out" 2> "$T/c99.err" ); crc=$?
assert_eqx "5 0" "$crc $(L '[.sets[]?.leases[]? | select(.holder == "sC")] | length')" "P99 C (the unit is ok for it) is refused while decide-b is stopping and holds no lease"
has "$T/c99.err" "endpoint_stopping" "P99 C's refusal names endpoint_stopping (§11.4.291(J)(3))"
gostop "$SG" decide-b; waitb "$APID"; arc=$?
assert_eqx "5 1 1 {}" "$arc $(stopsof decide-a) $(stopsof decide-b) $(L '.sets')" "P99 A stops each set once; the registry is empty; nothing was lost (C never held a lease)"
assert_eqx "" "$(running)" "P99 no unit runs at the end"

# ---- P100 (R8-1): two stoppers, one stop -------------------------------------------------------------------------------
fresh; two_degraded; SG="$T/sg"; mkdir -p "$SG"
( export PLACE_DEGRADED=decide-a,decide-b PLACE_STOP_GATE="$SG"; exec "$PLACE" acquire sA --pid $$ > "$T/a100.out" 2> "$T/a100.err" ) &
APID=$!; jev_track_pid "$APID"
reachstop "$SG" decide-a "P100 A disposes decide-a first"
( export PLACE_DEGRADED=decide-a,decide-b; exec "$PLACE" acquire sB --pid $$ > "$T/b100.out" 2> "$T/b100.err" ); brc=$?
assert_eqx "5 1" "$brc $(stopsof decide-b)" "P100 B (refused: decide-a is stopping) disposes decide-b, which nobody had marked yet"
gostop "$SG" decide-a; waitb "$APID"; arc=$?
assert_eqx "5 1 1" "$arc $(stopsof decide-a) $(stopsof decide-b)" "P100 A does not stop decide-b again: one stop of each set"
has "$T/a100.err" "stop of decide-b (dispose) not run at its turn: the set is gone" "P100 A judges decide-b at its turn and says why it is not stopped"

# ---- P101 (R8-1): a release that stops two sets keeps the one joined meanwhile --------------------------------------------
fresh; SG="$T/sg"; mkdir -p "$SG"; MYST="$(proc_start_of $$)"
reg -n --argjson t "$T0" --argjson pid "$$" --argjson pst "${MYST:-null}" '{gen:1, sets:
  ({"decide-a":{constitution_started:true, started_at:$t, starting:null, stopping:null, health:{state:"ok", reason:"crafted", seq:0, at:$t},
                leases:[{holder:"sA", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}
   | .["decide-b"] = .["decide-a"])}'
: > "$STUB_LOG/running.decide-a"; : > "$STUB_LOG/running.decide-b"
( export PLACE_STOP_GATE="$SG"; exec "$PLACE" release sA > "$T/r101.out" 2> "$T/r101.err" ) &
RPID=$!; jev_track_pid "$RPID"
reachstop "$SG" decide-a "P101 the release of sA stops decide-a first"
assert_eqx null "$(L '.sets["decide-b"].stopping')" "P101 decide-b is not marked while decide-a is stopped"
( export JEV_PLACE_PROFILES=decide-b; exec "$PLACE" acquire sC --pid $$ > "$T/c101.out" 2> "$T/c101.err" ); crc=$?
assert_eqx "0 decide-b" "$crc $(cat "$T/c101.out")" "P101 C joins decide-b while decide-a's stop is in flight"
gostop "$SG" decide-a; waitb "$RPID"; rrc=$?
assert_eqx "0 1 0" "$rrc $(stopsof decide-a) $(stopsof decide-b)" "P101 the release stops decide-a only"
has "$T/r101.err" "stop of decide-b (release) not run at its turn: it holds 1 lease(s) now" "P101 the release judges decide-b at its turn"
"$PLACE" heartbeat sC > /dev/null 2> "$T/hb101.err"; hrc=$?
assert_eqx "0 decide-b " "$hrc $(running)" "P101 C still holds its lease and decide-b runs"

# ---- P102 (R8-2): a set holding a lease when its stop returns rc 0 is kept -----------------------------------------------
p102_setup() {
  fresh; SG="$T/sg"; mkdir -p "$SG"
  reg -n --argjson t "$T0" '{gen:1, sets:{"decide-b":{constitution_started:true, started_at:$t, starting:null, stopping:null, leases:[],
      health:{state:"degraded", reason:"crafted", seq:0, at:$t}}}}'
  : > "$STUB_LOG/running.decide-b"
  ( export PLACE_DEGRADED=decide-b JEV_PLACE_PROFILES=decide-b PLACE_STOP_GATE="$SG"; exec "$PLACE" acquire sA --pid $$ > "$T/a102.out" 2> "$T/a102.err" ) &
  APID=$!; jev_track_pid "$APID"
  reachstop "$SG" decide-b "$1 A disposes decide-b"
  live_proc
}
# (a) CRAFTED STATE: a writer (an older pin that ignores marks) adds a lease to the set while its stop is in flight
p102_setup P102a
under_lock '.sets["decide-b"].leases += [{holder:"hX", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:false}]' \
  --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
gostop "$SG" decide-b; waitb "$APID"
# the set is not deleted with the lease: the stop's record keeps it (stopped_while_held, health pending), and A's own next
# observation (its re-plan after the stop) finds the unit gone and releases the lease as endpoint_gone, announced
assert_eqx "1 dispose true 0 null" "$(L '.sets["decide-b"].stopped_while_held.leases') $(L '.sets["decide-b"].stopped_while_held.kind') $(L '.sets["decide-b"].gone != null') $(L '.sets["decide-b"].leases | length') $(L '.sets["decide-b"].stopping')" \
  "P102a the set is KEPT when its stop returns with a lease in it (the anomaly recorded), then the lease is released as endpoint_gone; A's mark is cleared"
has "$T/a102.err" "the set is KEPT (never deleted with a lease)" "P102a A says the set is kept"
has "$T/a102.err" "endpoint_gone: the unit of decide-b is gone" "P102a the lease is released through endpoint_gone (announced), never dropped silently"
# (b) a set whose mark is ANOTHER stopper's when the stop returns (A's mark expired and was taken) keeps that mark
p102_setup P102b
under_lock '.sets["decide-b"].stopping = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:null}' --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
gostop "$SG" decide-b; waitb "$APID"
assert_eqx "$HP" "$(L '.sets["decide-b"].stopping.pid')" "P102b the set is kept and the other stopper's mark is not cleared by A"

# ---- P103 (RV08, RV06): a mark's age at the time of the judging lock ---------------------------------------------------
p103() { # p103 <capacity clock add> -> the observer runs at T0+300, its locked reap at T0+300+<add>
  fresh; live_proc; clockset $(( T0 + 300 ))
  reg -n --argjson t "$T0" --argjson pid "$HP" --argjson pst "${HPST:-null}" --arg mo "test:$T0" '{gen:1, sets:{"decide-a":{constitution_started:true, started_at:null, stopping:null,
      starting:{at:$t, mono:$mo, pid:$pid, pid_start:$pst, holder:"sM"}, leases:[]}}}'
  PLACE_CAP_CLOCK_ADD="$1" "$PLACE" status > /dev/null 2> "$T/o103.err"
}
p103 0;   assert_eqx true "$(L '.sets["decide-a"].starting != null')" "P103 CONTROL: a live marker's mark 300 s old (MARK_TTL $MT) is kept"
p103 100; assert_eqx "null $(( T0 + 400 )) test:$(( T0 + 400 )) $(( T0 + 400 ))" "$(L '.sets["decide-a"].starting') $(L '.sets["decide-a"].mark_cleared.at') $(L '.sets["decide-a"].mark_cleared.mono') $(L '.sets["decide-a"].health.at')" \
  "P103 after a 100 s capacity read the mark is 400 s old at the judging lock: cleared; mark_cleared and health carry that time"

# ---- P104 (RV09): a pid-less lease's heartbeat age at the time of the judging lock ------------------------------------
p104() {
  fresh; clockset $(( T0 + 850 )); : > "$STUB_LOG/running.decide-a"
  reg -n --argjson t "$T0" '{gen:1, sets:{"decide-a":{constitution_started:true, started_at:$t, starting:null, stopping:null,
      leases:[{holder:"sN", pid:null, pid_start:null, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}}'
  PLACE_CAP_CLOCK_ADD="$1" "$PLACE" status > /dev/null 2> "$T/o104.err"
}
p104 0;   assert_eqx 1 "$(L '.sets["decide-a"].leases | length')" "P104 CONTROL: a pid-less lease 850 s old (TTL 900) is kept"
p104 100; assert_eqx 0 "$(L '.sets["decide-a"].leases | length')" "P104 after a 100 s capacity read it is 950 s old at the judging lock: reaped"

# ---- P105 (RV03): gone.at ------------------------------------------------------------------------------------------------
fresh; live_proc
reg -n --argjson t "$T0" --argjson pid "$HP" --argjson pst "${HPST:-null}" '{gen:1, sets:{"decide-a":{constitution_started:true, started_at:$t, starting:null, stopping:null,
    health:{state:"ok", reason:"crafted", seq:0, at:$t}, leases:[{holder:"hL", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}}'
PLACE_CAP_CLOCK_ADD=100 "$PLACE" status > /dev/null 2> "$T/o105.err"
assert_eqx "$(( T0 + 100 )) 0" "$(L '.sets["decide-a"].gone.at') $(L '.sets["decide-a"].leases | length')" "P105 gone.at is the time of the observation that found the unit gone (after its 100 s read)"

# ---- P106 (RV05): a failed disposal stop ----------------------------------------------------------------------------------
fresh
reg -n --argjson t "$T0" '{gen:1, sets:{"decide-b":{constitution_started:true, started_at:$t, starting:null, stopping:null, leases:[], health:{state:"degraded", reason:"crafted", seq:0, at:$t}}}}'
: > "$STUB_LOG/running.decide-b"
( export PLACE_DEGRADED=decide-b JEV_PLACE_PROFILES=decide-b PLACE_STOP_RC=1 PLACE_CAP_CLOCK_ADD=100 PLACE_STOP_CLOCK_ADD=25
  exec timeout 120 "$PLACE" acquire sA --pid $$ > /dev/null 2> "$T/e106" ); rc=$?
assert_eqx "5 1 $(( T0 + 125 )) $(( T0 + 125 )) null" "$rc $(stopsof decide-b) $(L '.sets["decide-b"].stop_owed.at') $(L '.sets["decide-b"].stop_failed.at') $(L '.sets["decide-b"].stopping')" \
  "P106 the failed disposal stop (read +100 s, stop +25 s) records stop_owed.at and stop_failed.at at T0+125; A's mark is cleared"

# ---- P108 (RV07): a heartbeat refresh at the time of its locked section ----------------------------------------------
fresh; live_proc; : > "$STUB_LOG/running.decide-a"
reg -n --argjson t "$T0" --argjson pid "$HP" --argjson pst "${HPST:-null}" '{gen:1, sets:{"decide-a":{constitution_started:true, started_at:$t, starting:null, stopping:null,
    leases:[{holder:"hA", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}}'
PLACE_CAP_CLOCK_ADD=100 "$PLACE" heartbeat hA > /dev/null 2> "$T/h108.err"; hrc=$?
assert_eqx "0 $(( T0 + 100 )) test:$(( T0 + 100 ))" "$hrc $(L '.sets["decide-a"].leases[0].heartbeat_at') $(L '.sets["decide-a"].leases[0].heartbeat_mono')" "P108 the heartbeat stamps heartbeat_at and heartbeat_mono after its 100 s read"

# ---- P109 (RV10) + P110 (RV12, starting mark): a start whose lease is released during the start ------------------------
fresh
gated "$T/gA" 7 0 "$T/a109" JEV_PLACE_PROFILES=decide-a PLACE_CAP_CLOCK_ADD=100 PLACE_START_CLOCK_ADD=50 PLACE_STOP_RC=1 PLACE_START_SNAPSHOT=1 -- acquire sA --pid $$; a109=$GPID
reach "$T/gA" 7 "P109 A started decide-a and is paused at its record step"
A9ST="$(proc_start_of "$a109")"
assert_eqx "$a109 $A9ST test:$(( T0 + 100 )) sA $(( T0 + 100 ))" "$(jq -r '.sets["decide-a"].starting | "\(.pid) \(.pid_start) \(.mono) \(.holder) \(.at)"' "$STUB_LOG/leases_at_start.decide-a.json")" \
  "P110 the producer's own starting mark: pid, pid_start (its start time), mono, holder, written after the 100 s read"
"$PLACE" release sA > /dev/null 2> "$T/r109.err"
go "$T/gA" 7; waitb "$a109"
assert_eqx "$(( T0 + 150 )) $(( T0 + 150 )) $a109" "$(L '.sets["decide-a"].started_at') $(L '.sets["decide-a"].stop_failed.at') $(L '.sets["decide-a"].stopping.pid')" \
  "P109 started_at and stop_failed.at are the time the result was recorded (read +100, start +50); the failed release stop keeps A's mark"

# ---- P111 (R8-6): the monotonic clock -------------------------------------------------------------------------------------
p111() { # p111 <wall now> <mono now|""> <mark mono json> : a live marker's starting mark written at wall T0
  fresh; live_proc; clockset "$1"
  if [ -n "$2" ]; then export JEV_MONO_FILE="$T/mono"; printf '%s\n' "$2" > "$JEV_MONO_FILE"; fi
  reg -n --argjson t "$T0" --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson mo "$3" '{gen:1, sets:{"decide-a":{constitution_started:true, started_at:null, stopping:null,
      starting:{at:$t, mono:$mo, pid:$pid, pid_start:$pst, holder:"sM"}, leases:[]}}}'
  local rc=0; "$PLACE" status > /dev/null 2> "$T/o111.err" || rc=$?
  [ "$rc" = 0 ] || fail "P111 status ($1 / ${2:-no mono} / $3) exited $rc, expected 0"
}
p111 $(( T0 + 10000 )) $(( M0 + 10 )) "\"test:$M0\"";  assert_eqx true "$(L '.sets["decide-a"].starting != null')" "P111 the wall clock stepped +10000 s, monotonic +10 s: the live mark is kept"
p111 "$T0" $(( M0 + 400 )) "\"test:$M0\"";            assert_eqx null "$(L '.sets["decide-a"].starting')" "P111 the wall clock stepped back to the mark's time, monotonic +400 s: the mark is cleared"
p111 "$T0" $(( M0 + 10 )) "\"otherboot:$M0\"";        assert_eqx null "$(L '.sets["decide-a"].starting')" "P111 a mark from another boot is expired"
p111 $(( T0 + 10 )) $(( M0 + 10 )) null;              assert_eqx true "$(L '.sets["decide-a"].starting != null')" "P111 a mark with no mono (an older producer), wall age 10 s: kept"
p111 $(( T0 + 400 )) $(( M0 + 10 )) null;             assert_eqx null "$(L '.sets["decide-a"].starting')" "P111 the same mark at wall age 400 s: cleared (the wall rule)"
p111 "$T0" "" null; : > "$T/mono"; export JEV_MONO_FILE="$T/mono"
"$PLACE" status > /dev/null 2> "$T/e111"; rc=$?
assert_eqx 2 "$rc" "P111 an empty JEV_MONO_FILE: exit 2"
has "$T/e111" "the monotonic clock could not be read" "P111 the config error says so"
# a pid-less lease: the monotonic heartbeat age decides
p111l() { # p111l <wall now> <mono now>
  fresh; clockset "$1"; export JEV_MONO_FILE="$T/mono"; printf '%s\n' "$2" > "$JEV_MONO_FILE"; : > "$STUB_LOG/running.decide-a"
  reg -n --argjson t "$T0" --arg mo "test:$M0" '{gen:1, sets:{"decide-a":{constitution_started:true, started_at:$t, starting:null, stopping:null,
      leases:[{holder:"sN", pid:null, pid_start:null, heartbeat_at:$t, heartbeat_mono:$mo, ttl:900, project:null, started_by_this_session:true}]}}}'
  "$PLACE" status > /dev/null 2> "$T/o111l.err"
}
p111l $(( T0 + 5000 )) $(( M0 + 10 )); assert_eqx 1 "$(L '.sets["decide-a"].leases | length')" "P111 a pid-less lease, wall +5000 s, monotonic +10 s: kept"
p111l "$T0" $(( M0 + 901 ));           assert_eqx 0 "$(L '.sets["decide-a"].leases | length')" "P111 wall +0 s, monotonic +901 s (TTL 900): reaped"
# no seam: the producer writes "<boot id>:<uptime>" (the instrument first: the boot id must be readable here)
fresh; unset JEV_NOW_FILE JEV_NOW_EPOCH JEV_MONO_FILE
BOOT="$(tr -dc '0-9a-f-' < /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
if [ -n "$BOOT" ]; then ok "P111 CONTROL: the boot id is readable in this run"; else fail "P111 CONTROL: no boot id: the real-clock row cannot be judged (BLIND)"; fi
( export JEV_PLACE_PROFILES=decide-a PLACE_START_SNAPSHOT=1; exec "$PLACE" acquire sA --pid $$ > /dev/null 2> "$T/a111.err" ); rc=$?
assert_eqx "0 yes yes" "$rc $(jq -r --arg b "$BOOT" '.sets["decide-a"].starting.mono | if type == "string" and test("^" + $b + ":[0-9]+$") then "yes" else "no" end' "$STUB_LOG/leases_at_start.decide-a.json") $(jq -r --arg b "$BOOT" '.sets["decide-a"].leases[0].heartbeat_mono | if type == "string" and test("^" + $b + ":[0-9]+$") then "yes" else "no" end' "$JEV_STATE_DIR/leases.json")" \
  "P111 with no seam the mark and the lease carry mono = <boot id>:<uptime seconds>"

# ---- P112 (R8-1 class): the lease TTL while a live mark names the holder ----------------------------------------------
fresh; export JEV_REEVAL_CADENCE=10 JEV_LLMCTL_TIMEOUT=20
gated "$T/gA" 7 0 "$T/a112" JEV_PLACE_PROFILES=decide-a PLACE_START_CLOCK_ADD=100 -- acquire sA --ttl 60; a112=$GPID
reach "$T/gA" 7 "P112 A (a pid-less holder, TTL 60 s) started decide-a and is paused at its record step"
assert_eqx "$(( T0 + 100 )) $T0" "$(clk) $(L '.sets["decide-a"].leases[0].heartbeat_at')" "P112 CONTROL: the start took 100 s; the lease was written at the start mark (100 s > TTL 60 s)"
"$PLACE" status > /dev/null 2> "$T/o112a.err"
assert_eqx 1 "$(L '.sets["decide-a"].leases | length')" "P112 an observer keeps the lease while A's live starting mark names its holder"
has "$T/o112a.err" "kept while a live mark names the holder" "P112 the observer says why"
go "$T/gA" 7; waitb "$a112"; arc=$?
"$PLACE" status > /dev/null 2> "$T/o112b.err"
assert_eqx "0 1 $(( T0 + 100 ))" "$arc $(L '.sets["decide-a"].leases | length') $(L '.sets["decide-a"].leases[0].heartbeat_at')" "P112 A refreshed its lease when it recorded the start; an observer at once keeps it"
clockset $(( T0 + 161 ))
"$PLACE" status > /dev/null 2> "$T/o112c.err"
assert_eqx 0 "$(L '.sets["decide-a"].leases | length')" "P112 the suspension ended with the mark: 61 s after the refresh the pid-less lease is reaped"
# a DEAD holder is never kept by a live mark naming it
fresh; live_proc; sleep 0 & DP=$!; wait "$DP"
reg -n --argjson t "$T0" --argjson hp "$HP" --argjson hpst "${HPST:-null}" --argjson dp "$DP" '{gen:1, sets:{
   "decide-a":{constitution_started:true, started_at:null, stopping:null, starting:{at:$t, mono:null, pid:$hp, pid_start:$hpst, holder:"hD"}, leases:[]},
   "decide-b":{constitution_started:true, started_at:$t, starting:null, stopping:null, leases:[{holder:"hD", pid:$dp, pid_start:1, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}}'
# round 9 (O9-13): decide-b's own unit is UP, so the only way its lease can go is the reap; without this the status
# found the unit gone and released the lease as endpoint_gone, and a producer that kept the dead holder still passed
: > "$STUB_LOG/running.decide-b"
"$PLACE" status > /dev/null 2> "$T/o112d.err"
assert_eqx "0 true" "$(L '.sets["decide-b"].leases | length') $(L '.sets["decide-a"].starting != null')" "P112 a lease whose pid is dead is reaped although a live mark names its holder"
has "$T/o112d.err" "reaped dead lease holder=hD profile=decide-b" "P112 the dead holder is dropped by the reap itself"
assert_eqx 0 "$(grep -c 'endpoint_gone' "$T/o112d.err")" "P112 CONTROL: the unit of decide-b is up, nothing is released as endpoint_gone"
assert_eqx 0 "$(grep -c 'kept while a live mark names the holder' "$T/o112d.err")" "P112 a dead holder is never kept by the live mark that names it"

# ---- P113 (R8-1 class): no join in a plan that also stops a set -----------------------------------------------------
fresh; live_proc
reg -n --argjson t "$T0" --argjson hp "$HP" --argjson hpst "${HPST:-null}" '{gen:1, sets:{
   "decide-b":{constitution_started:true, started_at:$t, starting:null, stopping:null, leases:[], stop_owed:{at:$t, reason:"crafted (P113)"}},
   "decide-a":{constitution_started:true, started_at:$t, starting:null, stopping:null, health:{state:"ok", reason:"crafted", seq:0, at:$t},
               leases:[{holder:"hB", pid:$hp, pid_start:$hpst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}}'
: > "$STUB_LOG/running.decide-a"; : > "$STUB_LOG/running.decide-b"
( export JEV_PLACE_PROFILES=decide-a PLACE_CAP_CLOCK_ADD=100 PLACE_STOP_CLOCK_ADD=500; exec "$PLACE" acquire sA --pid $$ > "$T/a113.out" 2> "$T/a113.err" ); rc=$?
assert_eqx "0 decide-a 1 2" "$rc $(cat "$T/a113.out") $(stopsof decide-b) $(caps)" "P113 A runs the owed stop, reads a fresh answer and joins decide-a"
assert_eqx "$(( T0 + 700 ))" "$(L '.sets["decide-a"].leases[] | select(.holder == "sA") | .heartbeat_at')" "P113 the lease is written by the fresh plan after the stop (read +100, stop +500, read +100)"
has "$T/a113.err" "the join is taken after this acquire's stops" "P113 A says why it does not join in the first plan"

# ---- P114 (R8-1): a disposal is judged again at its turn --------------------------------------------------------------
fresh; two_degraded; SG="$T/sg"; mkdir -p "$SG"
( export PLACE_DEGRADED=decide-a,decide-b PLACE_STOP_GATE="$SG"; exec "$PLACE" acquire sA --pid $$ > "$T/a114.out" 2> "$T/a114.err" ) &
APID=$!; jev_track_pid "$APID"
reachstop "$SG" decide-a "P114 A disposes decide-a first"
"$PLACE" status > /dev/null 2> "$T/o114.err"   # the pressure cleared: decide-b's unit is ok now
assert_eqx ok "$(L '.sets["decide-b"].health.state')" "P114 CONTROL: an observer records decide-b ok while decide-a's stop is in flight"
gostop "$SG" decide-a; waitb "$APID"
assert_eqx "1 0 decide-b " "$(stopsof decide-a) $(stopsof decide-b) $(running)" "P114 decide-b is not stopped: at its turn it is recorded ok"
has "$T/a114.err" "stop of decide-b (dispose) not run at its turn: its recorded instance state is ok now" "P114 A says why"

# ---- P107 (R8-1 census): marks are never held across bounded calls ------------------------------------------------------
# an extra scenario for the census: a failed start and its cleanup stop
fresh
( export JEV_PLACE_PROFILES=decide-a PLACE_START_RC=1; exec timeout 120 "$PLACE" acquire sA --pid $$ > /dev/null 2> "$T/e107" ) || true
count_lockheld
python3 "$CENSUS" --needle "$TRD"/trace.* > "$T/census.out" 2>&1; crc=$?
assert_eqx 0 "$crc" "P107 every bounded stop / start in this file runs under a mark written after its process's previous bounded call ($(head -1 "$T/census.out"))"
grep '^VIOLATION' "$T/census.out" | head -5 | while IFS= read -r v; do echo "  # $v"; done
CG="$T/census_controls"; mkdir -p "$CG"
printf '%s\n' 'save 100 {"decide-a":{"stopping":100,"starting":null},"decide-b":{"stopping":100,"starting":null}}' 'call 100 llmctl stop decide-a' \
  'save 100 {"decide-b":{"stopping":100,"starting":null}}' 'call 100 llmctl stop decide-b' \
  'save 100 {"decide-c":{"stopping":null,"starting":100}}' 'call 100 llmctl start decide-c' > "$CG/bad"
python3 "$CENSUS" --needle "$CG/bad" > "$CG/bad.out" 2>&1; brc=$?
assert_eqx "1 1" "$brc $(grep -c '^VIOLATION' "$CG/bad.out")" "P107 CONTROL (golden-bad): the round-8 shape (one plan-time mark over two stops) is one violation"
printf '%s\n' 'save 100 {"decide-a":{"stopping":100,"starting":null}}' 'call 100 llmctl stop decide-a' \
  'save 100 {"decide-b":{"stopping":100,"starting":null}}' 'call 100 llmctl stop decide-b' \
  'save 100 {"decide-c":{"stopping":null,"starting":100}}' 'call 100 llmctl start decide-c' > "$CG/good"
python3 "$CENSUS" --needle "$CG/good" > /dev/null 2>&1; grc=$?
: > "$CG/empty"; python3 "$CENSUS" --needle "$CG/empty" > /dev/null 2>&1; erc=$?
assert_eqx "0 2" "$grc $erc" "P107 CONTROL: the per-turn shape passes; an empty trace is BLIND (2), never clean"

assert_eqx 0 "$LOCKHELD_TOTAL" "P67 no llmctl call ran while the lease lock was held (across this file)"
case "$TRD" in "${TMPDIR:-/tmp}"/tmp.*) rm -rf -- "${TRD:?}" ;; esac
finish
