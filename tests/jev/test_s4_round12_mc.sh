#!/usr/bin/env bash
# test_s4_round12_mc.sh - round 12 (2026-11-16), review R11-F: the THREE-process model check of the S4 placement
# producer scripts/jev/jev-place.sh (section 11.4.291). GATE-LOGIC test (section 11.4.289(C)(2)): the stub llmctl in
# tests/jev/fixtures/bin-place answers from a declared file; this proves the producer DECIDES correctly for the
# interleavings below, never that a local model runs. The helpers are those of test_s4_round12.sh (each round file
# carries its own copy). Kept in its own file because it is 60 runs.
#
#   R12-10 A start (A), a dispose-stop (B) and a whole third acquire C (--pid of a live process) inserted at each of the
#          6 positions of each of the 10 orders of A's two and B's three events (60 runs). Invariants after A, B and C:
#          a running unit has a set with a lease or an owed stop; after the
#          cleanup (release C, B and A, an acquire that runs every owed stop, its release) no unit runs and no set is
#          left. CONTROL: in some orders C joins a running set, in others C starts the unit itself.
#          Honest limit: these 60 orders, one profile, start rc 0; not every interleaving of three processes.
#          FINDING R12-F1 (open, not fixed): in orders starCA and straCA, C adopts the running unit as operator-started:
#          B's record deletes the set after A's start returned but before A recorded it (A's mark was judged expired), so
#          C sees a running unit with no set. A's later record makes the set constitution-started again and the cleanup
#          leaves nothing running, but in that window C treats a constitution-started unit as operator-owned. The
#          adoption list is pinned as a characterisation row, not as a pass of the property.
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

# ---- R12-10 (R11-F): three-process model check --------------------------------------------------------------------
mc_ev() {
  case "$1" in
    a) : > "$SG/go.start.decide-a"; waitany "$AP" "$T/gA/reached.$NA" ;;
    A) go "$T/gA" "$NA"; waitb "$AP" 120 >/dev/null; [ "$?" != 124 ] ;;
    s) go "$T/gB" "$NB"; waitany "$BP" "$SG/reached.stop.decide-a" "$T/gB/reached.$((NB+2))" ;;
    t) gostop "$SG" decide-a; waitany "$BP" "$T/gB/reached.$((NB+2))" ;;
    r) go "$T/gB" "$((NB+2))"; waitb "$BP" 120 >/dev/null; [ "$?" != 124 ] ;;
    C) ( export JEV_PLACE_PROFILES=decide-a JEV_LOCK_TIMEOUT=10; exec timeout 120 "$PLACE" acquire sC --pid "$HP" >> "$T/c.out" 2>> "$T/c.err" ); true ;;
  esac
}
MC_ORDERS="aAstr asAtr astAr astrA saAtr satAr satrA staAr starA straA"
nmc=0; nbad=0; ncjoin=0; ncstart=0; adopted=""
for o in $MC_ORDERS; do
  for pos in 0 1 2 3 4 5; do
    oo="${o:0:$pos}C${o:$pos}"
    mc2 0 "$NA" "$NB,$((NB+2))"; live_proc; : > "$T/c.err"
    if ! wait_file "$T/gB/reached.$NB" 300; then fail "R12-10 order $oo: B never reached its arm gate"; nbad=$((nbad+1)); continue; fi
    i=0; while [ "$i" -lt "${#oo}" ]; do mc_ev "${oo:$i:1}" || fail "R12-10 order $oo: event ${oo:$i:1} timed out"; i=$((i+1)); done
    kill -0 "$AP" 2>/dev/null && waitb "$AP" 60; kill -0 "$BP" 2>/dev/null && waitb "$BP" 60
    grep -q 'lease joined: holder=sC' "$T/c.err" && ncjoin=$((ncjoin+1))
    grep -q '^started decide-a\|started decide-a (' "$T/c.err" && ncstart=$((ncstart+1))
    # I1: a running unit is held (a lease) or owed a stop; I2: nothing adopted as operator-started
    i1="$(jq -r 'if (.sets["decide-a"] // null) == null then "noset" elif ((.sets["decide-a"].leases // []) | length) > 0 then "held" elif (.sets["decide-a"].stop_owed // null) != null then "owed" else "bare" end' "$JEV_STATE_DIR/leases.json" 2>/dev/null)"
    adopt="$(cat "$T/a.err" "$T/b.err" "$T/c.err" 2>/dev/null | grep -c 'joined the already-running unit' || true)"
    good=1
    if [ -n "$(running)" ]; then case "$i1" in held|owed) ;; *) good=0 ;; esac; fi
    # I2 is characterised, not asserted per order: round 12 found orders where C adopts as operator-started a unit whose
    # set B deleted before A recorded its start (finding R12-F1, round12/README.md); the list is pinned below
    [ "${adopt:-0}" = 0 ] || adopted="$adopted $oo"
    # cleanup: the releases of C, B and A (B and A are acquires too: either may hold a lease), an acquire that runs every
    # owed stop, its release
    for h in sC sB sA; do "$PLACE" release "$h" > /dev/null 2>> "$T/c.err"; done
    ( export JEV_PLACE_PROFILES=decide-a PLACE_START_RC=75; exec "$PLACE" acquire sD > /dev/null 2>> "$T/c.err" ); "$PLACE" release sD > /dev/null 2>> "$T/c.err"
    fin="$(running)|$(jq -c .sets "$JEV_STATE_DIR/leases.json" 2>/dev/null)"
    [ "$fin" = "|{}" ] || good=0
    nmc=$((nmc+1))
    if [ "$good" = 0 ]; then nbad=$((nbad+1)); fail "R12-10 order $oo: running=[$(running)] i1=$i1 adopt=$adopt final=[$fin]"; sed 's/^/#   c: /' "$T/c.err" | head -20; fi
  done
done
assert_eqx "60 0" "$nmc $nbad" "R12-10 all 60 three-process interleavings: a running unit is always held or owed a stop, and after the cleanup no unit and no set is left"
assert_eqx " starCA straCA" "$adopted" "R12-10 KNOWN FINDING R12-F1 (characterised, open): C adopts the unit as operator-started in exactly these orders (B deleted the set after A's start returned and before A recorded it); any change to this list is a change of behaviour"
assert_eqx yes "$( [ "$ncjoin" -ge 1 ] && [ "$ncstart" -ge 1 ] && echo yes || echo no )" "R12-10 CONTROL: C both joined a running set (count $ncjoin) and started the unit itself (count $ncstart) in some orders"


count_lockheld
assert_eqx 0 "$LOCKHELD_TOTAL" "P67 no llmctl call ran while the lease lock was held (across this file)"
case "$TRD" in "${TMPDIR:-/tmp}"/tmp.*) rm -rf -- "${TRD:?}" ;; esac
finish
