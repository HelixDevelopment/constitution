#!/usr/bin/env bash
# test_s4_round8.sh — round 8 (2026-11-14) of the S4 placement producer scripts/jev/jev-place.sh (§11.4.291), review of
# c811d0cd (docs/qa/jev_s3s4_20261112/round8/). GATE-LOGIC tests (§11.4.289(C)(2)): the stub llmctl in
# tests/jev/fixtures/bin-place answers from a declared file; these prove the producer DECIDES correctly, never that a
# local model runs. Rows marked "RED-first" were run against c811d0cd and failed there (round8/red_*.txt); rows marked
# "mutant row" pass on c811d0cd as well and exist to kill a named mutant (round8/mutants.md).
#
#   P91 (R7-A)  REAL CLOCK, scaled reviewer probe p_markttl_origin.sh: a live starter whose mark is set late in its
#               acquire (two slow capacity reads and a disposal stop first) keeps the mark: an observer that runs once the
#               acquire's PROCESS is older than MARK_TTL (but the mark is not) does not clear it, and the start is kept.
#               Scaled: start/stop timeout 10 s, 1 record retry, lock timeout 1 s -> MARK_TTL 43 s; stub calls of 9 s and
#               17 s. RED-first
#   P92 (R7-A)  REAL CLOCK, scaled reviewer probe p_markttl_concurrent.sh: in the same state a second session asking for
#               another profile is refused (endpoint_starting); it neither stops decide-a nor starts decide-c while A's start
#               is in flight (§11.4.291(J)(3), the one-start-at-a-time rule R5-1). RED-first
#   P93 (R7-A)  THE ADVANCING TEST CLOCK (JEV_NOW_FILE, advanced by the stub when a call ends): every age-bearing field is
#               stamped with the time it is WRITTEN (the mark's `at`, the lease's `heartbeat_at`, `started_at`, `health.at`,
#               `start_failed.at`, `stop_failed.at`, the record's `evaluated_at`); a lock wait is not counted as writing
#               time; the mark is kept at exactly MARK_TTL of ITS OWN age. Plus: the seam is ignored without JEV_TEST=1, and
#               an unreadable clock file is a config error (exit 2). RED-first (the stamping rows)
#   P94 (R7-C2) reviewer probe F1 (p_floor_equal.sh): the reap floor when the observer's ticket is the NEWEST one; kills
#               OWN01 (ticket == floor judges) and OWN02 (floor = counter - 1). Mutant row
#   P95 (R7-C3) the freshness check at the start mark runs AFTER the reap: a lease holder that dies between the plan and the
#               mark makes the answer stale, so the acquire plans again (and runs the owed stop that plan now sees) instead
#               of starting on the old answer; kills OWN03. CRAFTED STATE: a stop_owed set that holds a lease is not produced
#               by this producer (a stop_owed set never gets a lease here); the row pins the rule stated at
#               mark_start_locked, so what it guards is defence in depth. Mutant row
#   P96 (R7-C4) a last release during a start does not stop the set that is still starting; its starter stops it when the
#               start returns (one stop, by the starter); kills OWN10. Mutant row
#   P97 (R7-C5) a mark whose pid is alive but whose recorded start time differs (a reused pid) is a dead marker's mark and is
#               cleared; kills OWN07. Mutant row
#   P98 (R7-C5) a pid-less lease is alive AT its TTL and reaped one second later; kills OWN12. Mutant row
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; FIXTURES="$HERE/fixtures"
# shellcheck source=lib_assert.sh
. "$HERE/lib_assert.sh"
PLACE="${S4_PLACE_UNDER_TEST:-$ROOT/scripts/jev/jev-place.sh}"
STUB="$FIXTURES/bin-place/llmctl"
GATEBIN="$FIXTURES/bin-flockgate"

assert_eqx() { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (expected [$1] got [$2])"; fi; }
has()  { if grep -q -- "$2" "$1" 2>/dev/null; then ok "$3"; else fail "$3 (no [$2] in $1)"; fi; }
hasnt(){ if grep -q -- "$2" "$1" 2>/dev/null; then fail "$3 (found [$2] in $1)"; else ok "$3"; fi; }

cap() { # cap <file> [a-verdict] [b-verdict] [headroom|none] — every field the §11.4.291(C) table requires
  jq -n --arg va "${2:-fits}" --arg vb "${3:-fits}" --arg hr "${4:-5000}" '
    {schema:"llmctl.capacity/1", time:1700000000, measurement:{ok:true, critical_inputs_unreadable:[]},
     host:({cpus_online:16, mem_total_mb:20000, mem_available_mb:18000, usable_mem_mb:15000, swap_total_mb:0, swap_free_mb:0,
            load:{"1":1.0,"5":1.0,"15":1.0}, psi:{memory:{some:0.0,full:0.0},cpu:{some:0.0},io:{some:0.0,full:0.0}}, cgroup:{memory_max_mb:null}}
           + (if $hr=="none" then {} else {nproc:{rlimit_soft:123694, rlimit_hard:123694, user_threads:400, headroom:($hr|tonumber)}} end)),
     reserve:{mem_reserved_mb:4000, cpus_reserved:4}, pressure:{ok:true, reasons:[]},
     llmctl:{units:[]}, fallback:{recommended:"cloud", key_variable:null}, unknown_profiles:[], degraded:false, largest_decision_fit:null,
     profiles:{"decide-a":{verdict:$va, verdict_class:$va, running:false, threads:(if $va=="does_not_fit" then 0 else 3 end), reasons:[], headroom:{footprint_mb:1000}},
               "decide-b":{verdict:$vb, verdict_class:$vb, running:false, threads:(if $vb=="does_not_fit" then 0 else 3 end), reasons:[], headroom:{footprint_mb:1000}}}}' > "$1"
}
LOCKHELD_TOTAL=0
count_lockheld() { local n=0; [ -n "${STUB_LOG:-}" ] && [ -f "$STUB_LOG/llmctl.log" ] && n="$(grep -c '^LOCKHELD' "$STUB_LOG/llmctl.log" || true)"; LOCKHELD_TOTAL=$((LOCKHELD_TOTAL + ${n:-0})); }
fresh() {
  count_lockheld
  make_fixture_env s4r8
  export PATH="$FIXTURES/bin-place:$PATH" JEV_TEST=1 PLACE_CAP_JSON="$T/cap.json" JEV_LOCK_TIMEOUT=2
  unset PLACE_CAP_RC PLACE_CAP_RC_FILE PLACE_CAP_SLEEP PLACE_CAP_RAW PLACE_CAP_GATE PLACE_CAP_GATE_AT PLACE_CAP_GATE_WHEN \
        PLACE_START_RC PLACE_START_SLEEP PLACE_STOP_RC PLACE_STOP_SLEEP PLACE_DEGRADED PLACE_GONE PLACE_FULL_AFTER PLACE_DCAP_RC \
        PLACE_STATUS_RC PLACE_STATUS_URL PLACE_STATUS_NOGW JEV_LLMCTL_TIMEOUT JEV_LLMCTL_START_TIMEOUT JEV_PLACE_MAX \
        JEV_PLACE_PROFILES LLMCTL_GATEWAY_URL LLMCTL_CACERT LLMCTL_TENANT_ID JEV_LEASE_TTL JEV_REEVAL_CADENCE JEV_RECORD_RETRIES \
        JEV_PROJECT FLOCK_GATE_DIR FLOCK_GATE_AT FLOCK_GATE_KILL_AT \
        JEV_NOW_FILE PLACE_CAP_CLOCK_ADD PLACE_START_CLOCK_ADD PLACE_STOP_CLOCK_ADD PLACE_START_SNAPSHOT
  : > "$STUB_LOG/llmctl.log"
  cap "$T/cap.json"
}
starts() { grep -c '^llmctl start' "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
startsof() { grep -c "^llmctl start $1\$" "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
stops()  { grep -c '^llmctl stop' "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
pl() { jq -r "$1" "$JEV_STATE_DIR/placement.json" 2>/dev/null; }
L() { jq -r "$1" "$JEV_STATE_DIR/leases.json" 2>/dev/null; }
running() { (cd "$STUB_LOG" && for f in running.*; do [ -e "$f" ] && printf '%s ' "${f#running.}"; done); }
wait_file() { local n=0; while [ "$n" -lt "${2:-900}" ]; do [ -e "$1" ] && return 0; sleep 0.1; n=$((n+1)); done; return 1; }
# waitb <pid> [secs]: `wait` bounded by a deadline (default 300 s). A gated process that loops or hangs is a FAIL here,
# never a hang of the whole suite: past the deadline it is sent TERM (pid > 1 only, §11.4.263) and 124 is returned.
waitb() {
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
# field 22 of /proc/<pid>/stat (the start time), read after the LAST ") " so a command name with spaces cannot shift it
proc_start_of() { local st; local -a f; st="$(cat "/proc/$1/stat" 2>/dev/null)" || return 0; st="${st##*') '}"; read -ra f <<<"$st"; printf '%s\n' "${f[19]:-}"; }

# gated <gate-dir> <gate-at (comma list, 0 none)> <kill-at (0 none)> <out-prefix> [NAME=value ...] -- <jev-place args>
# runs "$PLACE" in the background behind the flock gate; GPID = its pid (registered for the EXIT cleanup)
gated() {
  local d="$1" at="$2" kat="$3" o="$4"; shift 4
  local -a envs=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  mkdir -p "$d"
  # shellcheck disable=SC2030  # the gated process gets its own lock timeout; the change is meant to stay in the subshell
  ( export PATH="$GATEBIN:$PATH" FLOCK_GATE_DIR="$d" FLOCK_GATE_AT="$at" FLOCK_GATE_KILL_AT="$kat" JEV_LOCK_TIMEOUT=10
    exec env "${envs[@]}" "$PLACE" "$@" > "$o.out" 2> "$o.err" ) &
  GPID=$!; jev_track_pid "$GPID"
}
# reach <gate-dir> <n> <label>: waits until the gated process is paused at flock call <n>
reach() { if wait_file "$1/reached.$2"; then ok "$3 (paused at flock call $2)"; else fail "$3: never reached flock call $2"; fi; }
go() { : > "$1/go.$2"; }
# registry_write <note>: a registry write by another session (under the lock, the generation raised as this producer
# does); only a field no decision reads changes, so the write makes an answer stale without changing any verdict
registry_write() {
  [ -s "$JEV_STATE_DIR/leases.json" ] || { fail "registry_write: no registry to write (the instrument would write nothing)"; return 1; }
  ( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock -w 10 8 || exit 4
    jq -c --arg n "$1" '.gen = ((.gen // 0) + 1) | .other_session_note = $n' "$JEV_STATE_DIR/leases.json" > "$JEV_STATE_DIR/leases.json.w" \
      && mv -f -- "$JEV_STATE_DIR/leases.json.w" "$JEV_STATE_DIR/leases.json" )
}
# older_pin_place <profile> <holder>: a producer of an OLDER constitution pin (no `gen`; the registry is per user and
# host-level, §11.4.291(J)) adds a held, constitution-started set under the lock, then starts the stub unit
older_pin_place() {
  ( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock -w 10 8 || exit 4
    jq -c --arg p "$1" --arg h "$2" --argjson now "$JEV_NOW_EPOCH" --argjson pid "$$" \
      '.sets[$p] = {constitution_started:true, started_at:$now, starting:null, stopping:null,
                    leases:[{holder:$h, pid:$pid, pid_start:null, heartbeat_at:$now, ttl:900, project:null, started_by_this_session:true}]}' \
      "$JEV_STATE_DIR/leases.json" > "$JEV_STATE_DIR/leases.json.w" && mv -f -- "$JEV_STATE_DIR/leases.json.w" "$JEV_STATE_DIR/leases.json" )
  "$STUB" start "$1" >/dev/null
}
# inv_violations: in llmctl.log, a `llmctl start` that follows another start or a stop with no `llmctl capacity --json`
# in between (the NF-2 inventory property: every start is decided on an answer read after the last start / stop)
inv_violations() {
  awk 'BEGIN{f=0; bad=0} /^llmctl capacity --json/{f=0} /^llmctl start /{ if (f) bad++; f=1 } /^llmctl stop /{f=1} END{print bad}' "$STUB_LOG/llmctl.log"
}

# a third profile for P92 (B asks for decide-c)
cap3() { cap "$1"; jq '.profiles["decide-c"] = .profiles["decide-a"]' "$1" > "$1.w" && mv -f -- "$1.w" "$1"; }
clockset() { printf '%s\n' "$1" > "$JEV_NOW_FILE"; }

# ---- P91 / P92 (R7-A): REAL clock, scaled reviewer probes --------------------------------------------------------------
# One shared scenario. A (decide-a) first reads a slow capacity answer (17 s), disposes the degraded lease-less set decide-b
# (a 9 s stop), reads a slow answer again (17 s) and only then marks and starts decide-a (a 9 s start). Its mark is set
# about 43 s after its process started, i.e. as old as MARK_TTL (43 s) would be if it were measured from process start.
# The observer runs once A's process age is past MARK_TTL + 1 while A's start is in flight.
STMO8=10 RET8=1 LOCK8=1; TTL8=$(( STMO8 + 2 + RET8 * LOCK8 + 30 ))
p9x_setup() {
  fresh; unset JEV_NOW_EPOCH
  export JEV_LLMCTL_START_TIMEOUT=$STMO8 JEV_RECORD_RETRIES=$RET8 JEV_LOCK_TIMEOUT=$LOCK8 JEV_LLMCTL_TIMEOUT=20 JEV_PROJECT=r8
  cap3 "$T/cap.json"
  T0="$(date +%s)"
  jq -n --argjson now "$T0" '{gen:1, sets:{"decide-b":{constitution_started:true, started_at:$now, starting:null, stopping:null, leases:[]}}}' > "$JEV_STATE_DIR/leases.json"
  : > "$STUB_LOG/running.decide-b"
  ( export PLACE_DEGRADED=decide-b PLACE_CAP_SLEEP=17 PLACE_STOP_SLEEP=9 PLACE_START_SLEEP=9 JEV_PLACE_PROFILES=decide-a,decide-b
    exec "$PLACE" acquire sA --pid $$ > "$T/a9x.out" 2> "$T/a9x.err" ) &
  APID=$!; jev_track_pid "$APID"
  local n=0; while ! grep -q '^llmctl start decide-a$' "$STUB_LOG/llmctl.log" && [ "$n" -lt 900 ]; do sleep 0.1; n=$((n+1)); done
  while [ $(( $(date +%s) - T0 )) -le $(( TTL8 + 1 )) ]; do sleep 0.2; done
  TOBS="$(date +%s)"; INFLIGHT=no
  if [ ! -e "$STUB_LOG/running.decide-a" ] && kill -0 "$APID" 2>/dev/null; then INFLIGHT=yes; fi
  MARK_AT="$(L '.sets["decide-a"].starting.at // "none"')"
}
p9x_controls() { # the instrument: the scenario the row needs was reached
  assert_eqx "1 yes" "$(grep -c '^llmctl stop decide-b$' "$STUB_LOG/llmctl.log") $INFLIGHT" "$1 CONTROL: A disposed decide-b and its start of decide-a is in flight when the observer runs"
  if [ $(( TOBS - T0 )) -gt "$TTL8" ]; then ok "$1 CONTROL: the observer runs when A's process is older than MARK_TTL ($(( TOBS - T0 )) s > $TTL8 s)"
  else fail "$1 CONTROL: the observer ran too early ($(( TOBS - T0 )) s <= $TTL8 s)"; fi
}
# P91
p9x_setup
p9x_controls P91
if [ "$MARK_AT" != none ] && [ $(( MARK_AT - T0 )) -ge 30 ]; then ok "P91 the starting mark carries the time it was SET (t0+$(( MARK_AT - T0 )) s), not A's process start"
else fail "P91 the starting mark's at is [$MARK_AT] (t0=$T0): stamped from the process start, not when it was set"; fi
"$PLACE" status > "$T/o91a.out" 2> "$T/o91a.err"; o1=$?
hasnt "$T/o91a.err" "cleared the starting mark of decide-a" "P91 the observer keeps the live starter's mark (its age is below MARK_TTL)"
assert_eqx "0 true" "$o1 $(L '.sets["decide-a"].starting != null')" "P91 after the observer the set still carries the starting mark"
"$PLACE" status > "$T/o91b.out" 2> "$T/o91b.err"
hasnt "$T/o91b.err" "endpoint_gone" "P91 a second observer does not release A's lease (no endpoint_gone)"
waitb "$APID" 120; arc=$?
assert_eqx "0 decide-a 0" "$arc $(cat "$T/a9x.out") $(grep -c '^llmctl stop decide-a$' "$STUB_LOG/llmctl.log")" "P91 A's start is kept: rc 0, decide-a placed, never stopped"
assert_eqx "decide-a " "$(running)" "P91 decide-a runs at the end"
# P92
p9x_setup
p9x_controls P92
( export JEV_PLACE_PROFILES=decide-c PLACE_START_SLEEP=3; exec "$PLACE" acquire sB --pid $$ > "$T/b92.out" 2> "$T/b92.err" ) &
BPID=$!; jev_track_pid "$BPID"
waitb "$BPID" 120; brc=$?
assert_eqx "5 0" "$brc $(startsof decide-c)" "P92 B is refused and starts nothing while A's start is in flight"
has "$T/b92.err" "endpoint_starting" "P92 B's refusal names endpoint_starting (§11.4.291(J)(3))"
assert_eqx 0 "$(grep -c '^llmctl stop decide-a$' "$STUB_LOG/llmctl.log")" "P92 B does not stop decide-a while it is being started"
waitb "$APID" 120; arc=$?
assert_eqx "0 decide-a decide-a " "$arc $(cat "$T/a9x.out") $(running)" "P92 A's start is kept and decide-a is the only unit that runs"

# ---- P93 (R7-A): the advancing test clock ---------------------------------------------------------------------------
# t0 = JEV_NOW_EPOCH = the clock file: a producer that ignores the file (c811d0cd) sees a fixed t0 throughout.
T0=1700000000
p93_env() { fresh; export JEV_NOW_FILE="$T/now"; clockset "$T0"; export JEV_PLACE_PROFILES=decide-a; }
# (a) a mark, a lease, started_at, health.at and the record: A's first capacity read takes 100 s, its start 50 s
p93_env
gated "$T/gA" 7 0 "$T/a93" PLACE_CAP_CLOCK_ADD=100 PLACE_START_CLOCK_ADD=50 PLACE_START_SNAPSHOT=1 -- acquire sA --pid $$; a93=$GPID
reach "$T/gA" 7 "P93a A started decide-a and is paused at its record step"
S="$STUB_LOG/leases_at_start.decide-a.json"
assert_eqx "$(( T0 + 100 )) $(( T0 + 100 ))" "$(jq -r '.sets["decide-a"].starting.at' "$S" 2>/dev/null) $(jq -r '.sets["decide-a"].leases[0].heartbeat_at' "$S" 2>/dev/null)" "P93a the starting mark and the lease carry the time they were written (after the 100 s capacity read)"
# the observer (MARK_TTL = 300 + 2 + 3 x 2 + 30 = 338 s here) runs when the mark is exactly MARK_TTL old: kept
MT93=338
clockset $(( T0 + 100 + MT93 ))
JEV_NOW_EPOCH=$(( T0 + 100 + MT93 )) "$PLACE" status > /dev/null 2> "$T/o93.err"
assert_eqx true "$(L '.sets["decide-a"].starting != null')" "P93a a live starter's mark is kept at MARK_TTL of its own age (process age MARK_TTL + 100 s)"
hasnt "$T/o93.err" "cleared the starting mark" "P93a the observer clears no mark"
go "$T/gA" 7; waitb "$a93"; arc=$?
assert_eqx "0 $(( T0 + 100 + MT93 ))" "$arc $(L '.sets["decide-a"].started_at')" "P93a started_at is the time the start was recorded"
assert_eqx "ok $(( T0 + 100 + MT93 + 100 )) $(( T0 + 100 + MT93 + 100 ))" "$(L '.sets["decide-a"].health.state') $(L '.sets["decide-a"].health.at') $(pl .placement.evaluated_at)" "P93a health.at and the record's evaluated_at are the time of the post-start observation"
# (b) a failed start whose cleanup stop fails too: start_failed.at and stop_failed.at
p93_env
PLACE_CAP_CLOCK_ADD=100 PLACE_START_RC=1 PLACE_START_CLOCK_ADD=50 PLACE_STOP_RC=1 PLACE_STOP_CLOCK_ADD=25 timeout 120 "$PLACE" acquire sA --pid $$ > /dev/null 2> "$T/e93b"; rc=$?
assert_eqx "5 $(( T0 + 150 )) $(( T0 + 175 ))" "$rc $(L '.sets["decide-a"].start_failed.at') $(L '.sets["decide-a"].stop_failed.at')" "P93b start_failed.at and stop_failed.at carry the time each was recorded"
# (c) a lock wait is not counted as the time a mark is written: A is paused before its start-mark lock and 1000 s pass
p93_env
gated "$T/gA" 5 0 "$T/a93c" PLACE_CAP_CLOCK_ADD=100 PLACE_START_SNAPSHOT=1 -- acquire sA --pid $$; a93c=$GPID
reach "$T/gA" 5 "P93c A is paused before its start-mark lock"
clockset $(( T0 + 1100 )); go "$T/gA" 5; waitb "$a93c"
assert_eqx "$(( T0 + 1100 ))" "$(jq -r '.sets["decide-a"].starting.at' "$STUB_LOG/leases_at_start.decide-a.json" 2>/dev/null)" "P93c the mark carries the time after the lock was taken"
# (d) the seam is a TEST seam: without JEV_TEST=1 the file is ignored (the record is dated with the real clock)
p93_env
( unset JEV_TEST; exec "$PLACE" acquire sA --pid $$ > /dev/null 2> "$T/e93d" ); rc=$?
assert_eqx "0 true" "$rc $(pl '(.placement.evaluated_at > 1750000000)')" "P93d without JEV_TEST=1 JEV_NOW_FILE is ignored"
# (e) an unreadable clock file is a config error, never a silent clock
p93_env; : > "$JEV_NOW_FILE"
"$PLACE" status > /dev/null 2> "$T/e93e"; rc=$?
assert_eqx 2 "$rc" "P93e an empty JEV_NOW_FILE: exit 2"
has "$T/e93e" "the clock could not be read" "P93e the config error says so"

# ---- P94 (reviewer probe F1, R7-C2; mutant row OWN01/OWN02): the floor when the observer's ticket is the newest -----
# C takes its ticket AFTER A's and reads its answer before A's start mark (A paused at its mark lock, call 5); A then
# marks, starts (rc 0) and is SIGKILLed at its record lock (call 7); C's finalize reaps A's mark with floor = C's own
# ticket. C's answer predates the start, so it must NOT judge the set (NF-3).
fresh
gated "$T/gA" 5 7 "$T/a94" JEV_PLACE_PROFILES=decide-a -- acquire sA --pid $$; a94=$GPID
reach "$T/gA" 5 "P94 A planned (ticket taken) and is paused before its start mark"
gated "$T/gC" 3 0 "$T/c94" -- status; c94=$GPID
reach "$T/gC" 3 "P94 C took its ticket after A's and read its answer (no start yet)"
assert_eqx "0 2" "$(starts) $(cat "$JEV_STATE_DIR/obs.seq")" "P94 CONTROL: no start before C's answer; C's ticket (2) is the newest"
go "$T/gA" 5; waitb "$a94" 2>/dev/null
if [ -e "$T/gA/killed" ]; then ok "P94 A was killed after llmctl start rc 0, before its record (the instrument)"; else fail "P94 A was not killed at its record step"; fi
assert_eqx "1 decide-a  true" "$(starts) $(running) $(L '.sets["decide-a"].starting != null')" "P94 the unit runs; the set carries the dead starter's mark"
go "$T/gC" 3; waitb "$c94"; crc=$?
assert_eqx "0 null 1 2" "$crc $(L '.sets["decide-a"].gone') $(L '.sets["decide-a"].leases | length') $(L '.sets["decide-a"].health.seq')" "P94 C clears the mark at floor 2 (its own ticket) and does NOT mark the running set gone"
hasnt "$T/c94.err" "endpoint_gone" "P94 no endpoint_gone"

# ---- P95 (R7-C3; mutant row OWN03): the start-mark freshness check runs after the reap ------------------------------
fresh
sleep 300 & HP=$!; jev_track_pid "$HP"
HPST="$(proc_start_of "$HP")"
jq -n --argjson now "$JEV_NOW_EPOCH" --argjson pid "$HP" --argjson pst "${HPST:-null}" \
  '{gen:1, sets:{"decide-b":{constitution_started:true, started_at:$now, starting:null, stopping:null, stop_owed:{at:$now, reason:"crafted (P95)"},
     leases:[{holder:"hB", pid:$pid, pid_start:$pst, heartbeat_at:$now, ttl:900, project:null, started_by_this_session:false}]}}}' > "$JEV_STATE_DIR/leases.json"
gated "$T/gA" 5 0 "$T/a95" JEV_PLACE_PROFILES=decide-a -- acquire sA --pid $$; a95=$GPID
reach "$T/gA" 5 "P95 A planned a start of decide-a (decide-b holds a live lease) and is paused before its start mark"
assert_eqx "0 1" "$(stops) $(L '.sets["decide-b"].leases | length')" "P95 CONTROL: no stop yet; decide-b still holds hB's lease"
if [ "$HP" -gt 1 ] 2>/dev/null; then kill "$HP" 2>/dev/null; wait "$HP" 2>/dev/null; fi
go "$T/gA" 5; waitb "$a95"; arc=$?
has "$T/a95.err" "planning again on a fresh answer" "P95 the reap at the mark made the answer stale: A plans again"
assert_eqx "0 decide-a" "$arc $(cat "$T/a95.out")" "P95 A then places decide-a"
assert_eqx "stop decide-b,start decide-a" "$(grep -E '^llmctl (start|stop) ' "$STUB_LOG/llmctl.log" | sed 's/^llmctl //' | paste -sd, -)" "P95 the owed stop of decide-b (seen by the new plan) runs before the start of decide-a"

# ---- P96 (R7-C4; mutant row OWN10): a last release during a start does not stop the starting set --------------------
fresh
gated "$T/gA" 7 0 "$T/a96" JEV_PLACE_PROFILES=decide-a -- acquire sA --pid $$; a96=$GPID
reach "$T/gA" 7 "P96 A started decide-a and is paused at its record step (the set carries its starting mark)"
"$PLACE" release sA > "$T/r96.out" 2> "$T/r96.err"; rrc=$?
assert_eqx "0  0 true" "$rrc $(cat "$T/r96.out") $(stops) $(L '.sets["decide-a"].starting != null')" "P96 the release of the last lease stops nothing while decide-a is starting; the mark is kept"
go "$T/gA" 7; waitb "$a96"; arc=$?
has "$T/a96.err" "its lease was released during the start; stopping it again" "P96 the starter sees the release when its start returns"
assert_eqx "5 1 " "$arc $(stops) $(running)" "P96 the starter stops decide-a (one stop in all); no unit is left"

# ---- P97 (R7-C5; mutant row OWN07): a mark whose pid is alive but was reused is a dead marker's mark --------------------
p97() { # p97 <recorded pid_start>
  fresh; local pst; pst="$(proc_start_of $$)"
  jq -n --argjson now "$JEV_NOW_EPOCH" --argjson pid "$$" --argjson mpst "$1" --argjson pst "${pst:-null}" \
    '{gen:1, sets:{"decide-a":{constitution_started:true, started_at:null, stopping:null, starting:{at:$now, pid:$pid, pid_start:$mpst},
       leases:[{holder:"sA", pid:$pid, pid_start:$pst, heartbeat_at:$now, ttl:900, project:null, started_by_this_session:true}]}}}' > "$JEV_STATE_DIR/leases.json"
  "$PLACE" status > /dev/null 2> "$T/st97.err"
}
p97 "$(proc_start_of $$)"; assert_eqx true "$(L '.sets["decide-a"].starting != null')" "P97 CONTROL: a live marker (pid and start time match) keeps its mark"
p97 1;                     assert_eqx "null starting" "$(L '.sets["decide-a"].starting') $(L '.sets["decide-a"].mark_cleared.mark')" "P97 a reused pid (start time differs) is a dead marker: the mark is cleared"

# ---- P98 (R7-C5; mutant row OWN12): a pid-less lease is alive AT its TTL, reaped one second later -------------------
p98() { # p98 <seconds after the heartbeat>
  fresh; : > "$STUB_LOG/running.decide-a"
  jq -n --argjson now "$JEV_NOW_EPOCH" \
    '{gen:1, sets:{"decide-a":{constitution_started:true, started_at:$now, starting:null, stopping:null,
       leases:[{holder:"sN", pid:null, pid_start:null, heartbeat_at:$now, ttl:900, project:null, started_by_this_session:true}]}}}' > "$JEV_STATE_DIR/leases.json"
  JEV_NOW_EPOCH=$(( JEV_NOW_EPOCH + $1 )) "$PLACE" status > /dev/null 2> "$T/st98.err"
}
p98 900; assert_eqx 1 "$(L '.sets["decide-a"].leases | length')" "P98 a pid-less lease is alive at its TTL (900 s)"
p98 901; assert_eqx 0 "$(L '.sets["decide-a"].leases | length')" "P98 it is reaped one second later"

count_lockheld
assert_eqx 0 "$LOCKHELD_TOTAL" "P67 no llmctl call ran while the lease lock was held (across this file)"
finish
