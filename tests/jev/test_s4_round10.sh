#!/usr/bin/env bash
# test_s4_round10.sh — round 10 (2026-11-15) of the S4 placement producer scripts/jev/jev-place.sh (§11.4.291), review of
# 911c5b9a (docs/qa/jev_s3s4_20261112/round10/). GATE-LOGIC tests (§11.4.289(C)(2)): the stub llmctl in
# tests/jev/fixtures/bin-place answers from a declared file; these rows prove the producer DECIDES correctly, never that a
# local model runs. "RED-first" rows were run against 911c5b9a and failed there (round10/red_r10_on_r9.txt); "mutant row"
# rows pass on 911c5b9a too and exist to kill a named mutant (round10/mutants.md).
# Every interleaving uses the flock gate (bin-flockgate: the starter paused at its record step, flock call 7) or the stub's
# PLACE_STOP_GATE; every age uses the test clocks JEV_NOW_FILE / JEV_MONO_FILE. No row sleeps for a timing window.
#
#   P115 (R9-1)  THE ONE OWNERSHIP RULE FOR A START'S RESULT. A starter's mark is cleared while it is alive (monotonic +400 s
#                > MARK_TTL 338 s: SIGSTOP, a host suspend) and session B joins the set. When A's start then returns
#                (a) rc 1, (b) rc 75, (c) rc 0 with A's own lease released meanwhile, A drops only ITS lease: B keeps its
#                lease, the unit is not stopped under B and the set is never handed over as operator-started; the kept set
#                is not routed until an observation newer than A's result; B's last release then stops the model (never
#                orphaned). The review's reproduction (probes/p_start_overwrite.sh) made deterministic. RED-first
#   P115d (R9-1, CRAFTED STATE) the mark is still A's but another writer added a lease: kept for it, A's mark cleared. RED-first
#   P115e (R9-1, CRAFTED STATE) a set another process marks `stopping` when A's start returns rc 0 with no lease left: the
#                foreign mark is kept, A runs no stop. RED-first
#   P115f (R9-1) the mark was cleared but nobody joined: the set is SOLE (claim gone), the failed start's cleanup stop runs.
#                Mutant row
#   P115g (R9-1) a profile whose start this acquire tried is never adopted by it as operator-started. RED-first
#   P116 (R9-2, mutant R9-10) a live mark suspends the TTL of the lease of the holder it NAMES only. Mutant row
#   P117 (R9-5, mutant R9-02) the holder named by a mark that this same reap CLEARS gets no TTL suspension. Mutant row
#   P118 (R9-4, mutant R9-04) a stop's turn reaps first: a dead holder's lease that appeared after the plan does not skip the
#                stop. Mutant row
#   P119 (R9-3, mutant R9-11) a set kept by a stop's result (stopped_while_held) has health `pending` and is NOT routed (no
#                llmctl-local entry in the derived cache) until an observation newer than the stop. Mutant row
#   P120 (R9-6)  a record whose monotonic time is ahead of the reader is judged on wall time; a negative wall age is expired.
#                RED-first
#   P121 (R9-7)  the plan reaps before its gateway write: the acquiring holder's expired lease is reaped, not refreshed by the
#                write. RED-first
#   P123 (R9-1, stop side) a stop's rc 0 result keeps a set another process marks `starting` (re-anchored mutant R9-07).
#                Mutant row
#   P122 (census) every bounded `llmctl stop` / `llmctl start` of every scenario in this file runs under a mark its process
#                wrote after its previous bounded call (tests/jev/fixtures/mark_census.py)
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
TRD="$(mktemp -d)"; NTRACE=0
case "$TRD" in "${TMPDIR:-/tmp}"/*) ;; *) echo "FATAL: trace dir outside TMPDIR ($TRD)" >&2; exit 2 ;; esac
LOCKHELD_TOTAL=0
count_lockheld() { local n=0; [ -n "${STUB_LOG:-}" ] && [ -f "$STUB_LOG/llmctl.log" ] && n="$(grep -c '^LOCKHELD' "$STUB_LOG/llmctl.log" || true)"; LOCKHELD_TOTAL=$((LOCKHELD_TOTAL + ${n:-0})); }
T0=1700000000; M0=5000
fresh() {
  count_lockheld
  make_fixture_env s4r10
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

# ---- P115 (R9-1): a start's result never takes a lease another session holds ----------------------------------------
# p115 <fail|refuse|handed>: A starts decide-a and pauses at its record step (flock call 7); its mark is cleared by B's reap
# (monotonic +400 s > B's MARK_TTL 338 s; A is alive) and B joins the set (its unit is up)
p115() {
  local v="$1" rcs=0
  case "$v" in fail) rcs=1 ;; refuse) rcs=75 ;; esac
  fresh; monoset "$M0"
  gated "$T/gA" 7 0 "$T/a115" JEV_PLACE_PROFILES=decide-a PLACE_START_RC="$rcs" -- acquire sA --pid $$; A115=$GPID
  reach "$T/gA" 7 "P115 ($v) A's llmctl start returned rc $rcs; A is paused before its record step"
  # refuse: rc 75 starts nothing; the unit is made to look up so B can join (the reviewer's probe)
  [ "$v" != refuse ] || : > "$STUB_LOG/running.decide-a"
  monoset $(( M0 + 400 ))
  ( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sB --pid $$ > "$T/b115.out" 2> "$T/b115.err" ); local brc=$?
  assert_eqx "0 decide-a" "$brc $(cat "$T/b115.out")" "P115 ($v) B joins decide-a after A's live mark aged out"
  has "$T/b115.err" "cleared the starting mark of decide-a" "P115 ($v) CONTROL: B's reap cleared A's mark (the precondition of R9-1)"
  if [ "$v" = handed ]; then "$PLACE" release sA > /dev/null 2> "$T/r115.err"; fi
  go "$T/gA" 7; waitb "$A115"; A115RC=$?
}
p115 fail
assert_eqx "5 sB true null 0 decide-a " "$A115RC $(holders decide-a) $(L '.sets["decide-a"].constitution_started') $(L '.sets["decide-a"].stopping') $(stopsof decide-a) $(running)" \
  "P115a A's failed start keeps B's lease, writes no stopping mark and stops nothing under B (the unit still runs)"
assert_eqx "gone 1 pending no" "$(L '.sets["decide-a"].start_kept.claim') $(L '.sets["decide-a"].start_kept.leases') $(L '.sets["decide-a"].health.state') $(routed)" \
  "P115a the result is recorded (start_kept, claim gone) and the kept set is not routed until an observation newer than it"
has "$T/a115.err" "only this acquire's own lease is dropped" "P115a A says what it did"
"$PLACE" heartbeat sB > /dev/null 2> "$T/hb115.err"; hrc=$?
assert_eqx "0 yes" "$hrc $(routed)" "P115a B's lease is held (heartbeat 0); the observation in the heartbeat routes the set again"
"$PLACE" release sB > /dev/null 2> "$T/rb115.err"; rrc=$?
assert_eqx "0 1  {}" "$rrc $(stopsof decide-a) $(running) $(L '.sets')" "P115a B's last release stops the model this producer started: never orphaned"

p115 refuse
assert_eqx "0 decide-a sB,sA true 0 decide-a " "$A115RC $(cat "$T/a115.out") $(holders decide-a) $(L '.sets["decide-a"].constitution_started') $(stopsof decide-a) $(running)" \
  "P115b A's refused start (75) keeps B's lease; the re-plan joins the running set B holds and it stays constitution-started (never re-adopted as operator-started)"
hasnt "$T/a115.err" "not constitution-started" "P115b A does not adopt the unit as operator-started"
"$PLACE" heartbeat sB > /dev/null 2> /dev/null; hrc=$?
"$PLACE" release sA > /dev/null 2> /dev/null; r1=$?
assert_eqx "0 0 0" "$hrc $r1 $(stopsof decide-a)" "P115b B holds its lease; A's release is not the last one and stops nothing"
"$PLACE" release sB > /dev/null 2> "$T/rb115.err"; rrc=$?
assert_eqx "0 1 " "$rrc $(stopsof decide-a) $(running)" "P115b the last release stops the model this producer started (never orphaned)"

p115 handed
assert_eqx "5  sB 0 decide-a " "$A115RC $(cat "$T/a115.out") $(holders decide-a) $(stopsof decide-a) $(running)" \
  "P115c A's start returns rc 0 after its own lease was released: not placed for A (no profile printed, exit 5); B keeps the set; nothing stopped"
has "$T/a115.err" "kept for them, not stopped and not placed" "P115c A says the set is handed to B"
"$PLACE" heartbeat sB > /dev/null 2> /dev/null; hrc=$?
assert_eqx 0 "$hrc" "P115c B still holds its lease"

# ---- P115d (R9-1, CRAFTED STATE): the mark is still A's, another writer added a lease ------------------------------------
fresh; live_proc
gated "$T/gA" 7 0 "$T/a115d" JEV_PLACE_PROFILES=decide-a PLACE_START_RC=1 -- acquire sA --pid $$; a=$GPID
reach "$T/gA" 7 "P115d A's start failed; A is paused before its record step"
under_lock '.sets["decide-a"].leases += [{holder:"hX", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:false}]' \
  --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
go "$T/gA" 7; waitb "$a"; arc=$?
assert_eqx "5 hX null null 0 ours" "$arc $(holders decide-a) $(L '.sets["decide-a"].starting') $(L '.sets["decide-a"].stopping') $(stopsof decide-a) $(L '.sets["decide-a"].start_kept.claim')" \
  "P115d the set is kept for hX: A's own mark is cleared (claim ours), no stopping mark, no stop"

# ---- P115e (R9-1, CRAFTED STATE): another process marks the set `stopping` when A's start returns ----------------------
fresh; live_proc
gated "$T/gA" 7 0 "$T/a115e" JEV_PLACE_PROFILES=decide-a -- acquire sA --pid $$; a=$GPID
reach "$T/gA" 7 "P115e A's start returned rc 0; A is paused before its record step"
"$PLACE" release sA > /dev/null 2> "$T/r115e.err"
under_lock '.sets["decide-a"].stopping = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:null}' --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
go "$T/gA" 7; waitb "$a"; arc=$?
assert_eqx "5 $HP null 0" "$arc $(L '.sets["decide-a"].stopping.pid') $(L '.sets["decide-a"].starting') $(stopsof decide-a)" \
  "P115e the other process's stopping mark is kept and A runs no stop of its own (A's own starting mark is cleared)"

# ---- P115f (R9-1): the mark was cleared but nobody joined: SOLE, the cleanup stop runs ---------------------------------
fresh; monoset "$M0"
gated "$T/gA" 7 0 "$T/a115f" JEV_PLACE_PROFILES=decide-a PLACE_START_RC=1 -- acquire sA --pid $$; a=$GPID
reach "$T/gA" 7 "P115f A's start failed; A is paused before its record step"
monoset $(( M0 + 400 ))
"$PLACE" status > /dev/null 2> "$T/o115f.err"
has "$T/o115f.err" "cleared the starting mark of decide-a" "P115f CONTROL: an observer cleared A's mark"
go "$T/gA" 7; waitb "$a"; arc=$?
assert_eqx "5 1  {}" "$arc $(stopsof decide-a) $(running) $(L '.sets')" "P115f the set is SOLE (claim gone, no other lease): the failed start's cleanup stop runs and the set is removed"

# ---- P115g (R9-1): no adoption of a profile this acquire tried to start ------------------------------------------------
fresh
gated "$T/gA" 7 0 "$T/a115g" JEV_PLACE_PROFILES=decide-a PLACE_START_RC=75 -- acquire sA --pid $$; a=$GPID
reach "$T/gA" 7 "P115g A's start was refused (75); A is paused before its record step"
: > "$STUB_LOG/running.decide-a"
go "$T/gA" 7; waitb "$a"; arc=$?
assert_eqx "5 {}" "$arc $(L '.sets')" "P115g A does not adopt decide-a as operator-started after its own start of it was refused"
has "$T/a115g.err" "this acquire tried to start it; it is not adopted" "P115g A says why"

# ---- P116 (R9-2, mutant R9-10): a live mark suspends only the lease of the holder it names ------------------------------
fresh; live_proc; clockset $(( T0 + 100 )); : > "$STUB_LOG/running.decide-b"
reg -n --argjson t "$T0" --argjson pid "$HP" --argjson pst "${HPST:-null}" '{gen:1, sets:{
   "decide-a":{constitution_started:true, started_at:null, stopping:null, starting:{at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"hM"}, leases:[]},
   "decide-b":{constitution_started:true, started_at:$t, starting:null, stopping:null, health:{state:"ok", reason:"crafted", seq:0, at:$t},
               leases:[{holder:"hO", pid:null, pid_start:null, heartbeat_at:$t, ttl:60, project:null, started_by_this_session:false},
                       {holder:"hM", pid:null, pid_start:null, heartbeat_at:$t, ttl:60, project:null, started_by_this_session:true}]}}}'
"$PLACE" status > /dev/null 2> "$T/o116.err"
assert_eqx "hM true" "$(holders decide-b) $(L '.sets["decide-a"].starting != null')" "P116 the expired lease of hO is reaped; hM, named by the live mark, is kept"
has "$T/o116.err" "reaped dead lease holder=hO" "P116 the reap says so"

# ---- P117 (R9-5, mutant R9-02): a mark cleared by this reap suspends nothing -------------------------------------------
fresh; live_proc; clockset $(( T0 + 400 )); : > "$STUB_LOG/running.decide-b"
reg -n --argjson t "$T0" --argjson pid "$HP" --argjson pst "${HPST:-null}" '{gen:1, sets:{
   "decide-a":{constitution_started:true, started_at:null, stopping:null, starting:{at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"hX"}, leases:[]},
   "decide-b":{constitution_started:true, started_at:$t, starting:null, stopping:null, health:{state:"ok", reason:"crafted", seq:0, at:$t},
               leases:[{holder:"hX", pid:null, pid_start:null, heartbeat_at:$t, ttl:60, project:null, started_by_this_session:true}]}}}'
"$PLACE" status > /dev/null 2> "$T/o117.err"
assert_eqx "null " "$(L '.sets["decide-a"].starting') $(holders decide-b)" "P117 the mark older than MARK_TTL is cleared and the expired lease of the holder it named is reaped in the same reap"
hasnt "$T/o117.err" "kept while a live mark names the holder" "P117 no suspension by a cleared mark"

# ---- P118 (R9-4, mutant R9-04): a stop's turn reaps before it judges ---------------------------------------------------
fresh; SG="$T/sg"; mkdir -p "$SG"; MYST="$(proc_start_of $$)"
reg -n --argjson t "$T0" --argjson pid "$$" --argjson pst "${MYST:-null}" '{gen:1, sets:
  ({"decide-a":{constitution_started:true, started_at:$t, starting:null, stopping:null, health:{state:"ok", reason:"crafted", seq:0, at:$t},
                leases:[{holder:"sA", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}
   | .["decide-b"] = .["decide-a"])}'
: > "$STUB_LOG/running.decide-a"; : > "$STUB_LOG/running.decide-b"
( export PLACE_STOP_GATE="$SG"; exec "$PLACE" release sA > "$T/r118.out" 2> "$T/r118.err" ) &
RPID=$!; jev_track_pid "$RPID"
reachstop "$SG" decide-a "P118 the release of sA stops decide-a first"
sleep 0 & DP=$!; wait "$DP"
under_lock '.sets["decide-b"].leases += [{holder:"hD", pid:$dp, pid_start:1, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:false}]' --argjson dp "$DP" --argjson t "$T0"
gostop "$SG" decide-a
reachstop "$SG" decide-b "P118 decide-b's stop runs at its turn"
gostop "$SG" decide-b; waitb "$RPID"; rrc=$?
assert_eqx "0 1 1" "$rrc $(stopsof decide-a) $(stopsof decide-b)" "P118 the dead holder's lease added after the plan is reaped at the stop's turn; decide-b is stopped"
hasnt "$T/r118.err" "stop of decide-b (release) not run at its turn" "P118 the stop is not skipped"

# ---- P119 (R9-3, mutant R9-11): a set kept by a stop's result is not routed ------------------------------------------
fresh; live_proc; MYST="$(proc_start_of $$)"; SG="$T/sg"; mkdir -p "$SG"
reg -n --argjson t "$T0" --argjson pid "$$" --argjson pst "${MYST:-null}" '{gen:1, gateway:{url:"https://127.0.0.1:18095", ca:"", source:"crafted"}, sets:{
   "decide-b":{constitution_started:true, started_at:$t, starting:null, stopping:null, health:{state:"ok", reason:"crafted", seq:0, at:$t},
               leases:[{holder:"sA", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}}'
: > "$STUB_LOG/running.decide-b"
( export PLACE_STOP_GATE="$SG"; exec "$PLACE" release sA > "$T/r119.out" 2> "$T/r119.err" ) &
RPID=$!; jev_track_pid "$RPID"
reachstop "$SG" decide-b "P119 the release of sA stops decide-b"
assert_eqx "ok https" "$(L '.sets["decide-b"].health.state') $(L '.gateway.url | split(":")[0]')" "P119 CONTROL: the set was observed ok and the registry holds an https gateway (it would be routed with a lease)"
under_lock '.sets["decide-b"].leases += [{holder:"hX", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:false}]' \
  --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
gostop "$SG" decide-b; waitb "$RPID"
assert_eqx "1 pending no" "$(L '.sets["decide-b"].stopped_while_held.leases') $(L '.sets["decide-b"].health.state') $(routed)" \
  "P119 the kept set has health pending and no llmctl-local entry is derived for it (not routed until observed again)"

# ---- P120 (R9-6): a monotonic time ahead of the reader -------------------------------------------------------------------
p120() { # p120 <wall now> <mark mono json> <mark at>
  fresh; live_proc; clockset "$1"; monoset "$M0"
  reg -n --argjson t "$3" --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson mo "$2" '{gen:1, sets:{"decide-a":{constitution_started:true, started_at:null, stopping:null,
      starting:{at:$t, mono:$mo, pid:$pid, pid_start:$pst, holder:"sM"}, leases:[]}}}'
  "$PLACE" status > /dev/null 2> "$T/o120.err"
}
p120 $(( T0 + 10 )) "\"test:$(( M0 + 4000 ))\"" "$T0";   assert_eqx true "$(L '.sets["decide-a"].starting != null')" "P120 a mark whose mono is ahead of the reader, wall age 10 s: judged on wall time, kept"
p120 $(( T0 + 400 )) "\"test:$(( M0 + 4000 ))\"" "$T0";  assert_eqx null "$(L '.sets["decide-a"].starting')" "P120 the same mark at wall age 400 s: cleared (before round 10 it was never cleared)"
p120 "$T0" null $(( T0 + 1000 ));                         assert_eqx null "$(L '.sets["decide-a"].starting')" "P120 a mark with no mono stamped 1000 s in the future: a negative age is expired, not fresh for ever"

# ---- P121 (R9-7): the plan reaps before its gateway write --------------------------------------------------------------
fresh; live_proc; clockset $(( T0 + 500 ))
reg -n --argjson t "$T0" --argjson t5 $(( T0 + 500 )) --argjson pid "$HP" --argjson pst "${HPST:-null}" '{gen:1, gateway:{url:"https://127.0.0.1:1", ca:"", source:"crafted"}, sets:{
   "decide-a":{constitution_started:false, started_at:$t, starting:null, stopping:null, health:{state:"ok", reason:"crafted", seq:0, at:$t},
               leases:[{holder:"sA", pid:null, pid_start:null, heartbeat_at:$t, ttl:400, project:null, started_by_this_session:false}]},
   "decide-b":{constitution_started:true, started_at:null, stopping:null, starting:{at:$t5, mono:null, pid:$pid, pid_start:$pst, holder:"hM"}, leases:[]}}}'
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sA > "$T/a121.out" 2> "$T/a121.err" ); rc=$?
assert_eqx "5 https://127.0.0.1:18095" "$rc $(L '.gateway.url')" "P121 CONTROL: the acquire is refused (decide-b is starting) and wrote the changed gateway"
has "$T/a121.err" "reaped dead lease holder=sA profile=decide-a" "P121 the expired lease of the acquiring holder is reaped before the plan's gateway write"
hasnt "$T/a121.err" "endpoint_gone" "P121 it is not refreshed by that write and then released as endpoint_gone"

# ---- P123 (R9-1 class, finish_stop side; kills the re-anchored R9-07): a starting mark of another process on the set --
# Our stopping mark is cleared while our stop runs and another process marks the set `starting`: the stop's rc 0 result
# must not delete the set under that starter (THE RULE: no other mark)
fresh; live_proc; MYST="$(proc_start_of $$)"; SG="$T/sg"; mkdir -p "$SG"
reg -n --argjson t "$T0" --argjson pid "$$" --argjson pst "${MYST:-null}" '{gen:1, sets:{
   "decide-b":{constitution_started:true, started_at:$t, starting:null, stopping:null, health:{state:"ok", reason:"crafted", seq:0, at:$t},
               leases:[{holder:"sA", pid:$pid, pid_start:$pst, heartbeat_at:$t, ttl:900, project:null, started_by_this_session:true}]}}}'
: > "$STUB_LOG/running.decide-b"
( export PLACE_STOP_GATE="$SG"; exec "$PLACE" release sA > "$T/r123.out" 2> "$T/r123.err" ) &
RPID=$!; jev_track_pid "$RPID"
reachstop "$SG" decide-b "P123 the release of sA stops decide-b"
under_lock '.sets["decide-b"].stopping = null | .sets["decide-b"].starting = {at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"hS"}' \
  --argjson pid "$HP" --argjson pst "${HPST:-null}" --argjson t "$T0"
gostop "$SG" decide-b; waitb "$RPID"
assert_eqx "$HP true" "$(L '.sets["decide-b"].starting.pid') $(L '.sets["decide-b"] != null')" \
  "P123 the set is kept with the other process's starting mark: a stop result never deletes a set another process marks"

# ---- P122 (census): marks are never held across bounded calls ------------------------------------------------------------
count_lockheld
python3 "$CENSUS" --needle "$TRD"/trace.* > "$TRD/census.out" 2>&1; crc=$?
assert_eqx 0 "$crc" "P122 every bounded stop / start in this file runs under a mark written after its process's previous bounded call ($(head -1 "$TRD/census.out"))"
grep '^VIOLATION' "$TRD/census.out" | head -5 | while IFS= read -r v; do echo "  # $v"; done

assert_eqx 0 "$LOCKHELD_TOTAL" "P67 no llmctl call ran while the lease lock was held (across this file)"
case "$TRD" in "${TMPDIR:-/tmp}"/tmp.*) rm -rf -- "${TRD:?}" ;; esac
finish
