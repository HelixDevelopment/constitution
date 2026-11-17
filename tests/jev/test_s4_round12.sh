#!/usr/bin/env bash
# test_s4_round12.sh - round 12 (2026-11-16) of the S4 placement producer scripts/jev/jev-place.sh (section 11.4.291),
# review of a1eeb0d7 (review_jev_r11.md; docs/qa/jev_s3s4_20261112/round12/). GATE-LOGIC tests (section 11.4.289(C)(2)):
# the stub llmctl in tests/jev/fixtures/bin-place answers from a declared file; these rows prove the producer DECIDES
# correctly, never that a local model runs. Every row kills a named mutant (round12/mutants.md); a row tagged RED-first
# was run against the reviewer's mutant and failed there (round12/runs/).
# Interleavings are fixed by gates (bin-flockgate before a lock call, the stub's start and stop gates) and by an external
# lock holder (holdlock: a subshell that takes the lease lock and keeps it until the row frees it). No row sleeps for a
# timing window; a lock-timeout row waits for the producer's own log line before it frees the lock.
#
#   R12-1  (R11-G, mutant X06) a release whose stop result cannot be recorded (the lock is held across every record
#          wait): release exits 6, the set is kept; golden-FALSE: the same release without the held lock exits 0
#   R12-2  (R11-G, mutant X06) an acquire whose failed start's cleanup stop cannot be recorded never starts the next
#          candidate; CONTROL: without the held lock the second candidate IS started
#   R12-3  (lock-timeout sweep) a release whose stopping mark cannot be written: exit 6, no stop, the unit keeps running
#   R12-4  (lock-timeout sweep) the record step's first wait times out, the second succeeds: exit 0, the set is gone
#   R12-5  (lock-timeout sweep) heartbeat, release and acquire with the lock held at their first lock call: exit 4,
#          nothing stopped or started; the acquire's record (itself under the lock) is not written and its log names
#          lease_lock_timeout
#   R12-6  (R11-D, mutant X05) a failed start (rc 1) recorded while another process marks the set stopping owes a stop
#   R12-7  (R11-D, mutant X10) the owed-after-start branch of a FAILED stop records stop_failed
#   R12-8  (R11-D/F, mutant X04) the owed-after-start branch keeps a third process's stopping mark (and so never runs a
#          second stop under it)
#   R12-9  (R11-D/F, mutant X08) a stop's arm step refuses a set a third process marked stopping after the plan
#   R12-12 (own mutant Y10) a release whose stop failed (rc 1, recorded) exits 6 and keeps the set and the unit
#   R12-13 (own mutant Y13) a failed cleanup stop (rc 1) stops the candidate loop; CONTROL: a good cleanup does not
#   R12-10 (R11-F) the three-process model check is in tests/jev/test_s4_round12_mc.sh (its own file: 60 runs)
#   R12-11 (R11-D) tests/jev/fixtures/write_census.py is closed-world: PASS on the producer, FAIL on a copy with an
#          uncategorised lease write
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

# ---- R12-1 (R11-G, X06): the release's stop result cannot be recorded ----------------------------------------------
fresh; live_proc; craft_b; SG="$T/sg1"; mkdir -p "$SG"
( export PLACE_STOP_GATE="$SG" JEV_LOCK_TIMEOUT=1 JEV_RECORD_RETRIES=2; exec "$PLACE" release sA > "$T/r1.out" 2> "$T/r1.err" ) &
r=$!; jev_track_pid "$r"
reachstop "$SG" decide-b "R12-1 the release's stop is in flight (armed)"
holdlock "$T/h1"; gostop "$SG" decide-b
if waitlog "$T/r1.err" "could not be recorded" 60; then ok "R12-1 every record wait timed out (the producer says so)"; else fail "R12-1 the record step never timed out"; fi
freelock "$T/h1"; rc_of "$r"; rrc=$?
assert_eqx "6 1 true" "$rrc $(stopsof decide-b) $(L '.sets["decide-b"] != null')" "R12-1 release exits 6 (the stop result is not recorded), one stop ran, the set is kept"
fresh; live_proc; craft_b
"$PLACE" release sA > /dev/null 2> "$T/r1c.err"; rrc=$?
assert_eqx "0 1 false" "$rrc $(stopsof decide-b) $(L '.sets["decide-b"] != null')" "R12-1 golden-FALSE: the same release with the lock free exits 0 and removes the set"

# ---- R12-2 (R11-G, X06): an unrecorded cleanup stop never lets the next candidate start ------------------------------
r122() { # r122 <hold 0|1>: acquire of two candidates whose starts fail (rc 1); sets P1 (first start) and P2 (the other)
  fresh; live_proc; SG="$T/sg2"; mkdir -p "$SG"
  ( export JEV_PLACE_PROFILES=decide-a,decide-b PLACE_START_RC=1 PLACE_STOP_GATE="$SG" JEV_LOCK_TIMEOUT=1 JEV_RECORD_RETRIES=2
    exec "$PLACE" acquire sA --pid $$ > "$T/a2.out" 2> "$T/a2.err" ) &
  a=$!; jev_track_pid "$a"; n=0; P1=""
  while [ "$n" -lt 1200 ] && [ -z "$P1" ]; do for f in "$SG"/reached.stop.*; do [ -e "$f" ] && P1="${f##*/reached.stop.}"; done; sleep 0.1; n=$((n+1)); done
  [ -n "$P1" ] || { fail "R12-2 the cleanup stop never began"; return 1; }
  if [ "$P1" = decide-a ]; then P2=decide-b; else P2=decide-a; fi
  : > "$SG/go.stop.$P2"   # a second cleanup stop (a mutant's) never waits
  if [ "$1" = 1 ]; then holdlock "$T/h2"; fi
  gostop "$SG" "$P1"
  if [ "$1" = 1 ]; then
    if waitlog "$T/a2.err" "could not be recorded" 60; then ok "R12-2 the cleanup stop's record waits timed out"; else fail "R12-2 the cleanup record step never timed out"; fi
    freelock "$T/h2"
  fi
  rc_of "$a" >/dev/null
}
r122 1
assert_eqx "1 0" "$(starts "$P1") $(starts "$P2")" "R12-2 the first candidate started once; the next candidate is never started (the old model may be resident)"
has "$T/a2.err" "no further candidate is started" "R12-2 the acquire says why it stops"
r122 0
assert_eqx "1 1" "$(starts "$P1") $(starts "$P2")" "R12-2 CONTROL: with the cleanup stop recorded the next candidate IS started (the row can see a second start)"

# ---- R12-12 (own mutant Y10): a release whose stop FAILED (rc 1, the result recorded) exits 6 ---------------------------
fresh; live_proc; craft_b
PLACE_STOP_RC=1 "$PLACE" release sA > /dev/null 2> "$T/r12.err"; rrc=$?
assert_eqx "6 1 true decide-b " "$rrc $(stopsof decide-b) $(L '.sets["decide-b"] != null') $(running)" "R12-12 a release whose stop failed exits 6; the set and the unit are kept"

# ---- R12-13 (own mutant Y13): a FAILED cleanup stop (rc 1) never lets the next candidate start ------------------------
fresh; live_proc
JEV_PLACE_PROFILES=decide-a,decide-b PLACE_START_RC=1 PLACE_STOP_RC=1 "$PLACE" acquire sA --pid $$ > /dev/null 2> "$T/a13.err"
assert_eqx 1 "$(( $(starts decide-a) + $(starts decide-b) ))" "R12-13 one start ran: after its cleanup stop failed no further candidate is started"
has "$T/a13.err" "the model may be resident, so no further candidate is started" "R12-13 the acquire says why it stops"
fresh; live_proc
JEV_PLACE_PROFILES=decide-a,decide-b PLACE_START_RC=1 "$PLACE" acquire sA --pid $$ > /dev/null 2> "$T/a13c.err"
assert_eqx 2 "$(( $(starts decide-a) + $(starts decide-b) ))" "R12-13 CONTROL: with the cleanup stop succeeding the next candidate IS started"

# ---- R12-3 (lock-timeout sweep): the release's stopping mark cannot be written --------------------------------------
fresh; live_proc; craft_b; SG="$T/sg3"; mkdir -p "$SG"
gated "$T/gC" 0 0 "$T/c3" PLACE_STOP_GATE="$SG" -- release sA; c=$GPID
reachstop "$SG" decide-b "R12-3 calibration: the release stops decide-b"; NR=$(( $(cat "$T/gC/count") - 1 ))
gostop "$SG" decide-b; waitb "$c"
if grep -q "^flock#$NR -u" "$T/gC/calls.log" || ! grep -q "^flock#$NR " "$T/gC/calls.log"; then fail "R12-3 CONTROL: call $NR is not a lock call"; else ok "R12-3 CONTROL: the arm step is flock call $NR"; fi
fresh; live_proc; craft_b
gated "$T/gR" "$NR" 0 "$T/r3" JEV_LOCK_TIMEOUT=1 JEV_RECORD_RETRIES=2 -- release sA; r=$GPID
reach "$T/gR" "$NR" "R12-3 the release is paused before its arm step"
holdlock "$T/h3"; go "$T/gR" "$NR"; rc_of "$r"; rrc=$?; freelock "$T/h3"
assert_eqx "6 0 decide-b  true" "$rrc $(stopsof decide-b) $(running) $(L '.sets["decide-b"] != null')" "R12-3 release exits 6, no stop ran, the unit and the set are kept"
has "$T/r3.err" "its stopping mark could not be written (lock timeout)" "R12-3 the release names the lock timeout"

# ---- R12-4 (lock-timeout sweep): the record step's retry ------------------------------------------------------------
fresh; live_proc; craft_b; SG="$T/sg4"; mkdir -p "$SG"
( export PLACE_STOP_GATE="$SG" JEV_LOCK_TIMEOUT=3 JEV_RECORD_RETRIES=2; exec "$PLACE" release sA > "$T/r4.out" 2> "$T/r4.err" ) &
r=$!; jev_track_pid "$r"
reachstop "$SG" decide-b "R12-4 the release's stop is in flight"
holdlock "$T/h4"; gostop "$SG" decide-b
if waitlog "$T/r4.err" "lock wait 1/2 timed out" 60; then ok "R12-4 the first record wait timed out"; else fail "R12-4 the first record wait never timed out"; fi
freelock "$T/h4"; rc_of "$r"; rrc=$?
assert_eqx "0 1 false" "$rrc $(stopsof decide-b) $(L '.sets["decide-b"] != null')" "R12-4 the second record wait succeeds: exit 0, the set is removed"
hasnt "$T/r4.err" "could not be recorded" "R12-4 the result is recorded"

# ---- R12-5 (lock-timeout sweep): heartbeat, release, acquire at their first lock call ---------------------------------
fresh; live_proc; craft_a 0; holdlock "$T/h5"
JEV_LOCK_TIMEOUT=1 "$PLACE" heartbeat sA > /dev/null 2> "$T/h5.err"; hrc=$?
JEV_LOCK_TIMEOUT=1 JEV_RECORD_RETRIES=2 "$PLACE" release sA > /dev/null 2> "$T/r5.err"; rrc=$?
pl0="$(sha256sum "$JEV_STATE_DIR/placement.json" 2>/dev/null | cut -c1-64)"
JEV_LOCK_TIMEOUT=1 JEV_RECORD_RETRIES=2 JEV_PLACE_PROFILES=decide-b "$PLACE" acquire sB > /dev/null 2> "$T/a5.err"; arc=$?
freelock "$T/h5"
assert_eqx "4 4 4" "$hrc $rrc $arc" "R12-5 heartbeat, release and acquire exit 4 when the lease lock cannot be taken"
assert_eqx "0 0 decide-a  sA" "$(stopsof decide-a) $(starts decide-b) $(running) $(holders decide-a)" "R12-5 nothing was stopped or started and the lease is kept"
# the placement record is itself written under the lock, so with the lock held it is never written (R5-3): the acquire
# logs the record it could not write, and that log line names the event
has "$T/a5.err" "placement record NOT written: the lease lock could not be taken (2 waits of 1s); event lease_lock_timeout" "R12-5 the acquire's unwritten record names lease_lock_timeout (no lease assumed)"
assert_eqx "$pl0" "$(sha256sum "$JEV_STATE_DIR/placement.json" 2>/dev/null | cut -c1-64)" "R12-5 no placement record is written without the lock (placement.json unchanged)"

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

# ---- R12-6 (X05): a failed start recorded under another process's stopping mark owes a stop -------------------------
mc2 1 "$NA" "$NB,$((NB+2))"; r11one R12-6
assert_eqx "1 true decide-a " "$(L '.sets["decide-a"].start_kept.rc') $(L '.sets["decide-a"].stop_owed != null') $(running)" \
  "R12-6 A's failed start (rc 1; the stub leaves the unit up) is recorded with an owed stop before B records"
go "$T/gB" "$((NB+2))"; waitb "$BP" 120
assert_eqx " {}" "$(running) $(jq -c .sets "$JEV_STATE_DIR/leases.json")" "R12-6 B runs the owed stop: no unit, no set"

# ---- R12-7 (X10): the owed-after-start branch of a failed stop records stop_failed -----------------------------------
mc2 0 "$NA" "$NB,$((NB+2)),$((NB+4))" PLACE_STOP_RC=1; r11one R12-7
go "$T/gB" "$((NB+2))"; reach "$T/gB" "$((NB+4))" "R12-7 B recorded its failed stop; B is paused before its owed retry's arm step"
if grep -q "^flock#$((NB+4)) -u" "$T/gB/calls.log" || ! grep -q "^flock#$((NB+4)) " "$T/gB/calls.log"; then fail "R12-7 CONTROL: B's call $((NB+4)) is not a lock call"; else ok "R12-7 CONTROL: B's call $((NB+4)) is a lock call"; fi
has "$T/b.err" "a start of decide-a was recorded after this stop was armed" "R12-7 B's failed stop took the owed-after-start branch"
assert_eqx "1 true true" "$(L '.sets["decide-a"].stop_failed.rc') $(L '.sets["decide-a"].stop_owed != null') $(L '.sets["decide-a"].constitution_started')" \
  "R12-7 the owed-after-start record of the failed stop carries stop_failed (rc 1) and the owed stop"
go "$T/gB" "$((NB+4))"; waitb "$BP" 120
( export JEV_PLACE_PROFILES=decide-a PLACE_START_RC=75; exec "$PLACE" acquire sC > /dev/null 2> "$T/c7.err" )
assert_eqx "" "$(running)" "R12-7 the next acquire runs the owed stop: no unit"

# ---- R12-8 (X04): the owed-after-start branch keeps a third process's stopping mark ----------------------------------
mc2 0 "$NA" "$NB,$((NB+2))"; live_proc; r11one R12-8
under_lock '.sets["decide-a"].stopping = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:null}' --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
go "$T/gB" "$((NB+2))"; waitb "$BP" 120
assert_eqx "$HP 1 true decide-a " "$(L '.sets["decide-a"].stopping.pid') $(stopsof decide-a) $(L '.sets["decide-a"].stop_owed != null') $(running)" \
  "R12-8 B keeps the third process's stopping mark, keeps the owed stop and runs no second stop under it"
has "$T/b.err" "another process is stopping it" "R12-8 B's owed retry refuses the set the third process is stopping"

# ---- R12-9 (X08): a stop's arm refuses a set a third process marked stopping after the plan ---------------------------
fresh; live_proc; craft_b; SG="$T/sg9"; mkdir -p "$SG"
gated "$T/gC" 0 0 "$T/c9" PLACE_STOP_GATE="$SG" -- release sA; c=$GPID
reachstop "$SG" decide-b "R12-9 calibration: the release stops decide-b"; NR=$(( $(cat "$T/gC/count") - 1 ))
gostop "$SG" decide-b; waitb "$c"
fresh; live_proc; craft_b
gated "$T/gR" "$NR" 0 "$T/r9" -- release sA; r=$GPID
reach "$T/gR" "$NR" "R12-9 the release is paused before its arm step"
under_lock '.sets["decide-b"].stopping = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:null}' --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
go "$T/gR" "$NR"; waitb "$r"
has "$T/r9.err" "another process is stopping it" "R12-9 the arm step refuses the set another process is stopping"
assert_eqx "0 decide-b  $HP" "$(stopsof decide-b) $(running) $(L '.sets["decide-b"].stopping.pid')" "R12-9 no stop runs; the unit and the third process's mark are kept"

# ---- R12-11 (R11-D): the write census is closed-world -------------------------------------------------------------
python3 -I "$FIXTURES/write_census.py" "$PLACE" > "$TRD/wc.out" 2>&1; wrc=$?
assert_eqx 0 "$wrc" "R12-11 write_census.py: every lease write and map_values line of the producer is categorised"
has "$TRD/wc.out" "release_locked | .* | \[1367\]\|release_locked |" "R12-11 CONTROL: the census lists release_locked"
sed 's/\.sets |= map_values(.leases |= map(select(.holder != $h)))/.sets |= map_values(.leases |= map(select(.ttl > 0)))/' "$PLACE" > "$TRD/wcneg.sh"
if cmp -s "$PLACE" "$TRD/wcneg.sh"; then fail "R12-11 CONTROL: the negative copy was not changed"; fi
python3 -I "$FIXTURES/write_census.py" "$TRD/wcneg.sh" > "$TRD/wcneg.out" 2>&1; wrc=$?
assert_eqx 2 "$wrc" "R12-11 a copy whose release no longer removes a lease by holder is BLIND (its needle is gone)"
awk '{print} /^hb_locked\(\) \{/ {print "  c=\"$(jq -c '"'"'.sets |= map_values(.leases |= reverse)'"'"' <<<\"$c\")\""}' "$PLACE" > "$TRD/wcneg2.sh"
python3 -I "$FIXTURES/write_census.py" "$TRD/wcneg2.sh" > "$TRD/wcneg2.out" 2>&1; wrc=$?
assert_eqx 1 "$wrc" "R12-11 a copy with an uncategorised map_values lease write FAILs (closed world)"

count_lockheld
assert_eqx 0 "$LOCKHELD_TOTAL" "P67 no llmctl call ran while the lease lock was held (across this file)"
case "$TRD" in "${TMPDIR:-/tmp}"/tmp.*) rm -rf -- "${TRD:?}" ;; esac
finish
