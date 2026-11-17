#!/usr/bin/env bash
# test_s4_round13.sh - round 13 (2026-11-16) of the S4 placement producer scripts/jev/jev-place.sh (section 11.4.291),
# review of c0455825 (review_jev_r12.md; docs/qa/jev_s3s4_20261112/round13/). GATE-LOGIC tests (section 11.4.289(C)(2)):
# the stub llmctl in tests/jev/fixtures/bin-place answers from a declared file; these rows prove the producer DECIDES
# correctly, never that a local model runs. Each row names the finding or mutant it kills (round13/mutants.md). The
# helpers are those of test_s4_round12_mc.sh (each round file carries its own copy).
#
#   R13-1  (R12-B1, RED-first: the reviewer's experiment, shipped) the start/dispose/third-acquire race of R12-F1 with
#          the starter A SIGKILLed at its record lock call (an OOM kill), orders starCA, starAC, straCA, aAstrC; and the
#          same orders without the kill (controls). After A, B and C: a running unit is held, owed a stop, or named by an
#          unanswered start intent; nothing is adopted as operator-started; after the cleanup (releases of C, B and A, an
#          acquire that runs every owed stop, its release, a reap) no unit runs, no set and no start intent is left.
#   R13-2  (R12-B1, the start intent itself) crafted registries: a dead starter's intent with the unit running becomes
#          an owed stop (by an acquire, and by a release); with the unit absent it is removed and does not block a start;
#          a live starter's intent refuses adoption (CONTROL: without it the same unit IS adopted) and refuses a second
#          start; a dead intent with an existing set makes it constitution-started; an unknown state keeps the intent; a
#          normal start leaves no intent and keeps another profile's
#   R13-3  (R12-B3, reviewer mutant R08) a failed owed retry inside a release stop: the release exits 6 and keeps the
#          set (golden-FALSE: the same retry succeeding exits 0); inside a failed start's cleanup stop: no further
#          candidate is started (CONTROL: with the retry succeeding the next candidate IS started)
#   R13-4  (R12-M1, reviewer mutant R01) the arm step's first lock wait times out, the second succeeds: the release stops
#          the unit and exits 0
#   R13-5  (R12-M2, reviewer mutant R06) a refused start (rc 75) recorded while another (live) process marks the set
#          stopping and no other lease holds it carries NO owed stop; CONTROL: a failed start (rc 1) in the same place does.
#          With the set made by this acquire's own mark the set is dropped either way (R06 is not visible there); R13-5c
#          (crafted: the set already constitution-started) is the row that kills R06
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
  make_fixture_env s4r12
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

# lease-set fixtures (as in round 11)
rset() { reg -n --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0" "$@"; }
craft_b() { rset '{gen:1, sets:{"decide-b":{constitution_started:true, started_at:$t, stopping:null, starting:null,
  leases:[{holder:"sA", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}}'; : > "$STUB_LOG/running.decide-b"; }
craft_a() { rset --arg owed "$1" '{gen:1, gateway:{url:"https://127.0.0.1:18095", ca:"", source:"crafted"}, sets:{"decide-a":({constitution_started:true, started_at:$t, stopping:null, starting:null,
  leases:[{holder:"sA", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}
  + (if $owed == "1" then {stop_owed:{at:$t, reason:"test"}} else {} end))}}'; : > "$STUB_LOG/running.decide-a"; }
holdlock() { # holdlock <dir>: another process takes the lease lock and keeps it until <dir>/free exists (bounded 120 s)
  local d="$1"; mkdir -p "$d"
  ( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock -w 10 8 || exit 4; : > "$d/held"; n=0
    while [ ! -e "$d/free" ] && [ "$n" -lt 1200 ]; do sleep 0.1 8>&-; n=$((n+1)); done ) &
  HLP=$!; jev_track_pid "$HLP"
  if wait_file "$d/held" 100; then ok "CONTROL: the external holder has the lease lock"; else fail "the external holder never took the lease lock"; fi
}
freelock() { : > "$1/free"; waitb "$HLP" 30 >/dev/null; }
waitlog() { # waitlog <file> <fixed string> [limit-s]: 0 when the line appears
  local n=0 lim=$(( ${3:-60} * 10 ))
  while [ "$n" -lt "$lim" ]; do grep -qF -- "$2" "$1" 2>/dev/null && return 0; sleep 0.1; n=$((n+1)); done; return 1
}
rc_of() { waitb "$1" "${2:-120}"; }

# ---- calibration of the A/B race (as in round 11) ------------------------------------------------------------------
# the flock call numbers of A's record step and of B's arm step ---------------------------------------
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

mc2() { # mc2 <A rc> <A gates> <B gates> <B env ...>: mc_launch with extra environment for B
  local rc="$1" ga="$2" gb="$3"; shift 3
  fresh; monoset "$M0"; SG="$T/sg"; mkdir -p "$SG"
  gated "$T/gA" "$ga" 0 "$T/a" JEV_PLACE_PROFILES=decide-a PLACE_START_GATE="$SG" PLACE_START_RC="$rc" -- acquire sA; AP=$GPID
  wait_file "$SG/reached.start.decide-a" 1200 || { fail "mc2: A's start never began"; return 1; }
  monoset $(( M0 + 2400 ))
  gated "$T/gB" "$gb" 0 "$T/b" JEV_PLACE_PROFILES=decide-a PLACE_STOP_GATE="$SG" "$@" -- acquire sB; BP=$GPID
}
r11one() { # the R11-1 order up to A's record: B arms, B's stop returns, A's unit comes up, A records; B waits before its record
  reach "$T/gB" "$NB" "$1 B is paused before its arm step"
  go "$T/gB" "$NB"; reachstop "$SG" decide-a "$1 B armed its stop"
  gostop "$SG" decide-a; reach "$T/gB" "$((NB+2))" "$1 B's stop returned; B is paused before its record step"
  : > "$SG/go.start.decide-a"; reach "$T/gA" "$NA" "$1 A's start returned; A is paused before its record step"
  go "$T/gA" "$NA"; waitb "$AP" 120
}



intents() { jq -c '.start_intents // null' "$JEV_STATE_DIR/leases.json" 2>/dev/null; }
adopts() { cat "$@" 2>/dev/null | grep -c 'joined the already-running unit' || true; }
dead_proc() { # dead_proc: a pid (and its start time) of a process that existed and is gone now (pid > 1 only, §11.4.263)
  sleep 600 & DP=$!; DPST="$(proc_start_of "$DP")"
  if [ "$DP" -gt 1 ] 2>/dev/null; then kill -TERM "$DP" 2>/dev/null; fi
  wait "$DP" 2>/dev/null; true
}

# ---- R13-1 (R12-B1): the reviewer's experiment, shipped --------------------------------------------------------------
mc3() { # mc3 <kill-at>: A's record lock call gated (and SIGKILLed when <kill-at> is its number), B gated at arm and record
  local kat="$1"
  fresh; monoset "$M0"; SG="$T/sg"; mkdir -p "$SG"
  gated "$T/gA" "$NA" "$kat" "$T/a" JEV_PLACE_PROFILES=decide-a PLACE_START_GATE="$SG" PLACE_START_RC=0 -- acquire sA; AP=$GPID
  wait_file "$SG/reached.start.decide-a" 1200 || { fail "mc3: A's start never began"; return 1; }
  monoset $(( M0 + 2400 ))
  gated "$T/gB" "$NB,$((NB+2))" 0 "$T/b" JEV_PLACE_PROFILES=decide-a PLACE_STOP_GATE="$SG" -- acquire sB; BP=$GPID
}
mc_ev() {
  case "$1" in
    a) : > "$SG/go.start.decide-a"; waitany "$AP" "$T/gA/reached.$NA" ;;
    A) go "$T/gA" "$NA"; waitb "$AP" 120 >/dev/null; true ;;
    s) go "$T/gB" "$NB"; waitany "$BP" "$SG/reached.stop.decide-a" "$T/gB/reached.$((NB+2))" ;;
    t) gostop "$SG" decide-a; waitany "$BP" "$T/gB/reached.$((NB+2))" ;;
    r) go "$T/gB" "$((NB+2))"; waitb "$BP" 120 >/dev/null; true ;;
    C) ( export JEV_PLACE_PROFILES=decide-a JEV_LOCK_TIMEOUT=10; exec timeout 120 "$PLACE" acquire sC --pid "$HP" >> "$T/c.out" 2>> "$T/c.err" ); true ;;
  esac
}
nk=0
for spec in "starCA:k" "starAC:k" "straCA:k" "aAstrC:k" "starCA:-" "starAC:-" "straCA:-" "aAstrC:-"; do
  oo="${spec%%:*}"; kill="${spec#*:}"; kat=0; [ "$kill" = k ] && kat="$NA"
  mc3 "$kat" || continue; live_proc; : > "$T/c.err"
  wait_file "$T/gB/reached.$NB" 300 || { fail "R13-1 $oo: B never reached its arm gate"; continue; }
  i=0; while [ "$i" -lt "${#oo}" ]; do mc_ev "${oo:$i:1}"; i=$((i+1)); done
  kill -0 "$AP" 2>/dev/null && waitb "$AP" 60; kill -0 "$BP" 2>/dev/null && waitb "$BP" 60
  killed=no; [ -e "$T/gA/killed" ] && killed=yes
  [ "$kill" = k ] && [ "$killed" = yes ] && nk=$((nk+1))
  [ "$kill" = k ] || assert_eqx no "$killed" "R13-1 $oo CONTROL: A was not killed"
  # I1 (extended in round 13): a running unit is held by a lease, owed a stop, or named by an unanswered start intent
  i1="$(jq -r 'if (.sets["decide-a"] // null) != null then (if ((.sets["decide-a"].leases // []) | length) > 0 then "held" elif (.sets["decide-a"].stop_owed // null) != null then "owed" else "bare" end)
               elif ((.start_intents // {})["decide-a"] // null) != null then "intent" else "noset" end' "$JEV_STATE_DIR/leases.json" 2>/dev/null)"
  if [ -n "$(running)" ]; then
    case "$i1" in held|owed|intent) ok "R13-1 $oo kill=$kill: the running unit is $i1 after A, B and C" ;;
      *) fail "R13-1 $oo kill=$kill: a unit runs and is $i1 (no lease, no owed stop, no start intent) after A, B and C" ;; esac
  else ok "R13-1 $oo kill=$kill: no unit runs after A, B and C"; fi
  cs="$(L '.sets["decide-a"].constitution_started // "noset"')"
  [ "$cs" != false ] && ok "R13-1 $oo kill=$kill: the set (if any) is not operator-owned (constitution_started $cs)" || fail "R13-1 $oo kill=$kill: the set is operator-owned (constitution_started false) although the constitution started the unit"
  assert_eqx 0 "$(adopts "$T/a.err" "$T/b.err" "$T/c.err")" "R13-1 $oo kill=$kill: no process adopted the unit as operator-started"
  for h in sC sB sA; do "$PLACE" release "$h" > /dev/null 2>> "$T/c.err"; done
  ( export JEV_PLACE_PROFILES=decide-a PLACE_START_RC=75; exec "$PLACE" acquire sD > /dev/null 2>> "$T/c.err" ); "$PLACE" release sD > /dev/null 2>> "$T/c.err"
  "$PLACE" reap > /dev/null 2>> "$T/c.err"
  assert_eqx "|{}|null" "$(running)|$(jq -c .sets "$JEV_STATE_DIR/leases.json")|$(intents)" "R13-1 $oo kill=$kill: after the cleanup no unit runs, no set and no start intent is left (stops $(stopsof decide-a), starts $(starts decide-a))"
done
assert_eqx 4 "$nk" "R13-1 CONTROL: A was SIGKILLed at its record lock call in all four kill orders"

# ---- R13-2 (R12-B1): the start intent, on crafted registries ---------------------------------------------------------
# Round 14 adaptation (review R13-B1): an intent written by the round-14 producer names its start process (child: pid +
# start time), and a dead starter's intent is judged only once that start process is seen gone. These crafted intents
# therefore name a start process that is gone (dead_proc); a crafted intent WITHOUT a child is a round-13 intent, in
# flight until it is older than MARK_TTL (tests/jev/test_s4_round14.sh covers both).
ireg() { # ireg <pid> <pid_start|null> [sets-json]: a registry with one start intent of decide-a and the given sets
  local dp="${DP:-}" dps="${DPST:-}"
  dead_proc; local cp="$DP" cps="${DPST:-null}"; DP="$dp"; DPST="$dps"
  reg -n --argjson pid "$1" --argjson pst "$2" --argjson t "$T0" --argjson s "${3:-{\}}" --argjson cp "$cp" --argjson cps "$cps" \
    '{gen:1, sets:$s, start_intents:{"decide-a":{at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"sZ", child:{pid:$cp, pid_start:$cps}}}}'
}
# (a) a dead starter, no set, the unit runs: an acquire turns the intent into an owed stop and runs it
fresh; live_proc; dead_proc; ireg "$DP" "${DPST:-null}"; : > "$STUB_LOG/running.decide-a"
( export JEV_PLACE_PROFILES=decide-a PLACE_START_RC=75; exec "$PLACE" acquire sD > /dev/null 2> "$T/i1.err" )
has "$T/i1.err" "recorded constitution-started with an owed stop" "R13-2a a dead starter's unanswered intent with the unit running becomes an owed stop"
assert_eqx "1 |null|0" "$(stopsof decide-a) $(running)|$(intents)|$(adopts "$T/i1.err")" "R13-2a the owed stop ran: no unit, no intent, no adoption"
# (a') the same, recovered by a release (any holder): the release stops the recovered set
fresh; live_proc; dead_proc; ireg "$DP" "${DPST:-null}"; : > "$STUB_LOG/running.decide-a"
"$PLACE" release sNobody > /dev/null 2> "$T/i1r.err"; rrc=$?
assert_eqx "0 1 |{}|null" "$rrc $(stopsof decide-a) $(running)|$(jq -c .sets "$JEV_STATE_DIR/leases.json")|$(intents)" "R13-2a' a release recovers the intent and stops the unit (rc 0, one stop, nothing left)"
# (b) a dead starter, no set, the unit absent: the intent is removed and a start is not blocked
fresh; live_proc; dead_proc; ireg "$DP" "${DPST:-null}"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/i2.err" ); arc=$?
has "$T/i2.err" "no unit runs: the intent is removed" "R13-2b a dead starter's intent with no unit is removed"
assert_eqx "0 1 0 null" "$arc $(starts decide-a) $(stopsof decide-a) $(intents)" "R13-2b the acquire then starts decide-a (the old intent never blocks a start)"
# (c) a LIVE starter's intent, no set, the unit runs: never adopted; CONTROL: without the intent it IS adopted
fresh; live_proc; ireg "$HP" "${HPST:-null}"; : > "$STUB_LOG/running.decide-a"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sC --pid "$HP" > /dev/null 2> "$T/i3.err" )
has "$T/i3.err" "is in flight (start intent, unanswered)" "R13-2c a live starter's intent refuses adoption (the log names it)"
assert_eqx "0 0 decide-a  $HP null" "$(adopts "$T/i3.err") $(stopsof decide-a) $(running) $(jq -r '.start_intents["decide-a"].pid' "$JEV_STATE_DIR/leases.json") $(L '.sets["decide-a"] // null')" \
  "R13-2c not adopted, not stopped, the intent kept, no set made"
fresh; live_proc; : > "$STUB_LOG/running.decide-a"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sC --pid "$HP" > /dev/null 2> "$T/i3c.err" )
assert_eqx "1 false" "$(adopts "$T/i3c.err") $(L '.sets["decide-a"].constitution_started')" "R13-2c CONTROL: with no intent the same running unit IS adopted as operator-started (the row can see an adoption)"
# (d) a LIVE starter's intent, no set, the unit absent: no second start
fresh; live_proc; ireg "$HP" "${HPST:-null}"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/i4.err" )
has "$T/i4.err" "is unanswered; not started" "R13-2d a live starter's intent refuses a second start (the log names it)"
assert_eqx "0 $HP" "$(starts decide-a) $(jq -r '.start_intents["decide-a"].pid' "$JEV_STATE_DIR/leases.json")" "R13-2d no start ran; the intent is kept"
# (e) a dead starter, an operator-owned set exists: the set becomes constitution-started, the intent is removed
fresh; live_proc; dead_proc
ireg "$DP" "${DPST:-null}" "$(jq -nc --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0" '{"decide-a":{constitution_started:false, stopping:null, starting:null,
  leases:[{holder:"sQ", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:false}]}}')"
: > "$STUB_LOG/running.decide-a"
"$PLACE" status > /dev/null 2> "$T/i5.err"
assert_eqx "true null" "$(L '.sets["decide-a"].constitution_started') $(intents)" "R13-2e a dead intent and an existing set: the set is made constitution-started, the intent removed"
# (f) a dead starter, no set, the capacity answer undetermined: the intent is kept, nothing stopped
fresh; live_proc; dead_proc; ireg "$DP" "${DPST:-null}"; : > "$STUB_LOG/running.decide-a"
PLACE_CAP_RC=1 "$PLACE" status > /dev/null 2> "$T/i6.err"
assert_eqx "$DP 0 null" "$(jq -r '.start_intents["decide-a"].pid' "$JEV_STATE_DIR/leases.json") $(stopsof decide-a) $(L '.sets["decide-a"] // null')" "R13-2f an unknown unit state keeps the dead starter's intent; nothing is stopped or made"
has "$T/i6.err" "the unit state is not known now; the intent is kept" "R13-2f the log says why"
# (g) a normal start leaves no intent of its own, and keeps another profile's
fresh; live_proc
reg -n --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0" '{gen:1, sets:{}, start_intents:{"decide-b":{at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"sZ"}}}'
( export JEV_PLACE_PROFILES=decide-a PLACE_START_SNAPSHOT=1; exec "$PLACE" acquire sA --pid "$HP" > /dev/null 2> "$T/i7.err" )
assert_eqx "1 sA [\"decide-a\",\"decide-b\"] [\"decide-b\"]" "$(starts decide-a) $(jq -r '.start_intents["decide-a"].holder' "$STUB_LOG/leases_at_start.decide-a.json") $(jq -c '.start_intents | keys' "$STUB_LOG/leases_at_start.decide-a.json") $(jq -c '.start_intents | keys' "$JEV_STATE_DIR/leases.json")" \
  "R13-2g the intent is in the registry while the start runs, removed by its record; another profile's intent is untouched"
# (h) CRAFTED: while this acquire's start runs, the intent on its own profile is replaced by another LIVE process's
# intent. The record removes an intent only when it names this process (pid + start time), so the foreign one stays.
# (Not reachable through the producer: a second start is refused while an intent exists; the row checks the rule.)
fresh; live_proc; SG="$T/sg2h"; mkdir -p "$SG"
( export JEV_PLACE_PROFILES=decide-a PLACE_START_GATE="$SG"; exec "$PLACE" acquire sA --pid $$ > /dev/null 2> "$T/i8.err" ) &
a=$!; jev_track_pid "$a"
if wait_file "$SG/reached.start.decide-a" 1200; then
  # (a foreign intent with ANOTHER pid but THIS acquire's start time cannot be made live: its pid's real start time
  # differs, so the observation reads it as a reused pid, a dead starter, and recovers it. Measured; see mutants.md F15)
  under_lock '.start_intents["decide-a"] = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"sZ"}' --argjson t "$T0" --argjson pid "$HP" --argjson pst "${HPST:-null}"
  : > "$SG/go.start.decide-a"; rc_of "$a" >/dev/null
  assert_eqx "sZ $HP" "$(jq -r '.start_intents["decide-a"].holder' "$JEV_STATE_DIR/leases.json") $(jq -r '.start_intents["decide-a"].pid' "$JEV_STATE_DIR/leases.json")" \
    "R13-2h the start's record never removes another live process's intent (only its own)"
else fail "R13-2h the start never began"; fi

# ---- R13-3 (R12-B3, reviewer mutant R08): a FAILED owed retry is a failed stop -----------------------------------------
kept_after_arm() { # inject, under the lock, a start result recorded after this stop was armed (start_kept.seen_stopping = the mark)
  under_lock ".sets[\"$1\"].start_kept = {at:\$t, mono:null, rc:0, leases:0, claim:\"gone\", seen_stopping:.sets[\"$1\"].stopping}" --argjson t "$T0"
}
r133() { # r133 <stop rc>: a release of decide-b whose stop sees a start recorded after its arm; the owed retry gets <stop rc>
  fresh; live_proc; craft_b; SG="$T/sg3"; mkdir -p "$SG"
  ( export PLACE_STOP_GATE="$SG" PLACE_STOP_RC="$1"; exec "$PLACE" release sA > "$T/r3.out" 2> "$T/r3.err" ) &
  r=$!; jev_track_pid "$r"
  reachstop "$SG" decide-b "R13-3 (stop rc $1) the release's stop is armed and in flight"
  kept_after_arm decide-b; gostop "$SG" decide-b
  rc_of "$r"; RRC=$?
}
r133 1
has "$T/r3.err" "retrying the stop of decide-b at once" "R13-3 (rc 1) the owed retry runs"
assert_eqx "6 2 true true decide-b " "$RRC $(stopsof decide-b) $(L '.sets["decide-b"] != null') $(L '.sets["decide-b"].stop_failed != null') $(running)" \
  "R13-3 (rc 1) the release whose owed retry failed exits 6; two stops ran; the set is kept with stop_failed; the unit runs"
r133 0
assert_eqx "0 2 false " "$RRC $(stopsof decide-b) $(L '.sets["decide-b"] != null') $(running)" "R13-3 golden-FALSE (rc 0): the same release whose owed retry succeeds exits 0; the set and the unit are gone"
r133c() { # r133c <stop rc>: a failed start (rc 1) of two candidates; its cleanup stop sees a start recorded after its arm
  fresh; live_proc; SG="$T/sg3c"; mkdir -p "$SG"
  ( export JEV_PLACE_PROFILES=decide-a,decide-b PLACE_START_RC=1 PLACE_STOP_GATE="$SG" PLACE_STOP_RC="$1"
    exec "$PLACE" acquire sA --pid $$ > "$T/a3.out" 2> "$T/a3.err" ) &
  a=$!; jev_track_pid "$a"; n=0; P1=""
  while [ "$n" -lt 1200 ] && [ -z "$P1" ]; do for f in "$SG"/reached.stop.*; do [ -e "$f" ] && P1="${f##*/reached.stop.}"; done; sleep 0.1; n=$((n+1)); done
  [ -n "$P1" ] || { fail "R13-3c the cleanup stop never began"; return 1; }
  if [ "$P1" = decide-a ]; then P2=decide-b; else P2=decide-a; fi
  : > "$SG/go.stop.$P2"
  kept_after_arm "$P1"; gostop "$SG" "$P1"
  rc_of "$a" >/dev/null
}
r133c 1
has "$T/a3.err" "retrying the stop of $P1 at once" "R13-3c (rc 1) the cleanup stop's owed retry runs"
assert_eqx "1 0" "$(starts "$P1") $(starts "$P2")" "R13-3c (rc 1) the owed retry failed: the next candidate is never started (the old model may be resident)"
has "$T/a3.err" "the model may be resident, so no further candidate is started" "R13-3c (rc 1) the acquire says why it stops"
r133c 0
assert_eqx "1 1" "$(starts "$P1") $(starts "$P2")" "R13-3c CONTROL (rc 0): with the owed retry succeeding the next candidate IS started (the row can see a second start)"

# ---- R13-4 (R12-M1, reviewer mutant R01): the arm step retries after a lock wait ---------------------------------------
fresh; live_proc; craft_b; SG="$T/sg4"; mkdir -p "$SG"
gated "$T/gC" 0 0 "$T/c4" PLACE_STOP_GATE="$SG" -- release sA; c=$GPID
reachstop "$SG" decide-b "R13-4 calibration: the release stops decide-b"; NR=$(( $(cat "$T/gC/count") - 1 ))
gostop "$SG" decide-b; waitb "$c"
if grep -q "^flock#$NR -u" "$T/gC/calls.log" || ! grep -q "^flock#$((NR+1)) -u" "$T/gC/calls.log"; then fail "R13-4 calibration: call $NR is not the arm lock"; else ok "R13-4 calibration: the release arms at flock call $NR"; fi
fresh; live_proc; craft_b
gated "$T/gR" "$NR" 0 "$T/r4" JEV_LOCK_TIMEOUT=1 JEV_RECORD_RETRIES=3 -- release sA; r=$GPID
reach "$T/gR" "$NR" "R13-4 the release is paused before its arm lock"
holdlock "$T/h4"; go "$T/gR" "$NR"
if waitlog "$T/r4.err" "lock wait 1/3 for its stopping mark timed out" 60; then ok "R13-4 the first arm wait timed out (the producer says so)"; else fail "R13-4 the first arm wait never timed out"; fi
freelock "$T/h4"; rc_of "$r"; rrc=$?
assert_eqx "0 1 false " "$rrc $(stopsof decide-b) $(L '.sets["decide-b"] != null') $(running)" "R13-4 the second arm wait succeeds: one stop, the release exits 0, the set and the unit are gone"

# ---- R13-5 (R12-M2, reviewer mutant R06): rc 75 never makes a set owed ------------------------------------------------
# An acquire's start is in flight; another process (a live pid) then marks the set stopping; the start returns. At the
# record the set is NOT sole (the foreign mark) and no other lease holds it: the non-sole branch with n == 0.
r135() { # r135 <start rc>
  fresh; live_proc; SG="$T/sg5"; mkdir -p "$SG"
  ( export JEV_PLACE_PROFILES=decide-a PLACE_START_GATE="$SG" PLACE_START_RC="$1"; exec "$PLACE" acquire sA --pid $$ > "$T/a5.out" 2> "$T/a5.err" ) &
  a=$!; jev_track_pid "$a"
  wait_file "$SG/reached.start.decide-a" 1200 || { fail "R13-5 (rc $1) the start never began"; return 1; }
  under_lock '.sets["decide-a"].stopping = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"sStopper"}' --argjson t "$T0" --argjson pid "$HP" --argjson pst "${HPST:-null}"
  : > "$SG/go.start.decide-a"; rc_of "$a" >/dev/null
  R5="$(L '.sets["decide-a"].start_kept.rc') $(L '.sets["decide-a"].start_kept.leases') $(L '.sets["decide-a"].stopping.holder') $(L '.sets["decide-a"].stop_owed != null') $(stopsof decide-a)"
}
r135 75
has "$T/a5.err" "found that no other lease holds the set, but another process" "R13-5 (rc 75) the record took the non-sole branch with no other lease (the log names it)"
# rc 75 started nothing: the set (made by this acquire's own mark, so constitution-started by nobody) is dropped by the
# next observation (no lease, not constitution-started), WITH OR WITHOUT a stop_owed field: in this order an owed stop
# set by mutant R06 is dropped with the set and cannot be seen (measured: R06 passes this row). R13-5c below is the case
# where it can be seen.
assert_eqx "null null null false 0" "$R5" "R13-5 a refused start (rc 75) under another process's stopping mark, no other lease: no owed stop, no stop run, the set is gone"
r135 1
assert_eqx "1 0 sStopper true 0" "$R5" "R13-5 CONTROL: a failed start (rc 1) in the same place carries an owed stop (the row can see stop_owed)"
# R13-5c (CRAFTED registry): the set is already constitution-started by an earlier recorded start (started_at set) when
# the foreign stopping mark is written; rc 75 keeps it constitution-started, so the set survives the observation and a
# stop_owed written for rc 75 (mutant R06) is visible. The order that produces this state is not shown here; the row
# checks the record rule only (gate-logic, §11.4.289(C)(2)).
r135c() { # r135c <start rc>
  fresh; live_proc; SG="$T/sg5c"; mkdir -p "$SG"
  ( export JEV_PLACE_PROFILES=decide-a PLACE_START_GATE="$SG" PLACE_START_RC="$1"; exec "$PLACE" acquire sA --pid $$ > "$T/a5c.out" 2> "$T/a5c.err" ) &
  a=$!; jev_track_pid "$a"
  wait_file "$SG/reached.start.decide-a" 1200 || { fail "R13-5c (rc $1) the start never began"; return 1; }
  under_lock '.sets["decide-a"].stopping = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"sStopper"} | .sets["decide-a"].started_at = $t | .sets["decide-a"].constitution_started = true' --argjson t "$T0" --argjson pid "$HP" --argjson pst "${HPST:-null}"
  : > "$SG/go.start.decide-a"; rc_of "$a" >/dev/null
  R5C="$(L '.sets["decide-a"].start_kept.rc') $(L '.sets["decide-a"].constitution_started') $(L '.sets["decide-a"].stopping.holder') $(L '.sets["decide-a"].stop_owed != null') $(stopsof decide-a)"
}
r135c 75
has "$T/a5c.err" "found that no other lease holds the set, but another process" "R13-5c (rc 75) the record took the non-sole branch with no other lease"
assert_eqx "75 true sStopper false 0" "$R5C" "R13-5c a refused start (rc 75) on a set already constitution-started, under a foreign stopping mark: the set is kept for its stopper, no owed stop, no stop run (kills R06)"
r135c 1
assert_eqx "1 true sStopper true 0" "$R5C" "R13-5c CONTROL: rc 1 in the same place carries an owed stop"

count_lockheld
assert_eqx 0 "$LOCKHELD_TOTAL" "P68 no llmctl call ran while the lease lock was held (across this file)"
case "$TRD" in "${TMPDIR:-/tmp}"/tmp.*) rm -rf -- "${TRD:?}" ;; esac
finish
