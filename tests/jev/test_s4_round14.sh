#!/usr/bin/env bash
# test_s4_round14.sh - round 14 (2026-11-17) of the S4 placement producer scripts/jev/jev-place.sh (section 11.4.291),
# review of 9442791d (rev_r13; docs/qa/jev_s3s4_20261112/round14/). GATE-LOGIC tests (section 11.4.289(C)(2)): the stub
# llmctl in tests/jev/fixtures/bin-place answers from a declared file; these rows prove the producer DECIDES correctly,
# never that a local model runs. Each row names the finding or mutant it kills (round14/mutants.md). The helpers are
# those of test_s4_round13.sh (each round file carries its own copy). The exhaustive kill sweep of the start/record
# sequence is tests/jev/test_s4_round14_sweep.sh.
#
#   R14-1  (R13-B1, RED-first) the starter A is SIGKILLed while its start is in flight (the start process survives it).
#          B: the intent is kept (its start process runs), no second start, no adoption; the start then brings the unit
#          up; C (after the start process is gone): the intent becomes an owed stop, it is run, nothing is adopted; the
#          cleanup leaves no unit, no set, no intent. The intent names the start process: its pid is a live process group
#          while the start runs (mutant M6: no child recorded)
#   R14-2  the rule on crafted registries (a dead starter): a LIVE start process keeps the intent (unit absent: no start;
#          unit running: no adoption, no stop) and, once it is gone, the intent is resolved (M1); a reused start pid is
#          gone (M3); a start process whose process group still has a member is in flight (M2); a round-13 intent (no
#          start process) is in flight until it is older than MARK_TTL (M7); the reviewer's witnesses WV01 (a reused
#          starter pid, V01) and WV02 (a degraded unit, V02); a live starter's intent refuses the start with no
#          stale_answer and one capacity read (F3, V08); a start process with no recorded start time is in flight while
#          its pid lives (M11)
#   R14-3  the gate: a refused mark runs no llmctl start (M4); a starter SIGKILLed after its intent was written and
#          before `go` runs no llmctl start, and the intent is then removed (unit absent)
#   R14-4  (M5) an answer read while the start process ran, delivered after it ended (and after the unit came up), never
#          resolves the intent: it is kept; the next observation resolves it
#   R14-5  (M8) a start process that exits after `go` without running llmctl (its <out>.went write failed): the start is
#          recorded as refused (rc 75), no stop is owed or run
#   R14-6  the state the first sweep run reported as a violation ("ours": a lease-less constitution-started set whose
#          stopping mark belongs to a dead process, the starter killed between its no-set record write and its own stop)
#          is never orphaned: a release by any holder stops it; an acquire joins it as constitution-started (no start, no
#          adoption) and its release stops it
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


intents() { jq -c '.start_intents // null' "$JEV_STATE_DIR/leases.json" 2>/dev/null; }
adopts() { cat "$@" 2>/dev/null | grep -c 'joined the already-running unit' || true; }
dead_proc() { # dead_proc: a pid (and its start time) of a process that existed and is gone now (pid > 1 only, §11.4.263)
  sleep 600 & DP=$!; DPST="$(proc_start_of "$DP")"
  if [ "$DP" -gt 1 ] 2>/dev/null; then kill -TERM "$DP" 2>/dev/null; fi
  wait "$DP" 2>/dev/null; true
}

ireg14() { # ireg14 <starter pid> <starter start|null> <start pid|null> <start start|null> [sets-json]: one intent of decide-a
  if [ "$3" = null ]; then
    reg -n --argjson pid "$1" --argjson pst "$2" --argjson t "$T0" --argjson s "${5:-{\}}" \
      '{gen:1, sets:$s, start_intents:{"decide-a":{at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"sZ"}}}'
  else
    reg -n --argjson pid "$1" --argjson pst "$2" --argjson t "$T0" --argjson s "${5:-{\}}" --argjson cp "$3" --argjson cps "$4" \
      '{gen:1, sets:$s, start_intents:{"decide-a":{at:$t, mono:null, pid:$pid, pid_start:$pst, holder:"sZ", child:{pid:$cp, pid_start:$cps}}}}'
  fi
}
live_child() { sleep 600 & CP=$!; jev_track_pid "$CP"; CPST="$(proc_start_of "$CP")"; }
stop_child() { if [ "$CP" -gt 1 ] 2>/dev/null; then kill -TERM "$CP" 2>/dev/null; fi; wait "$CP" 2>/dev/null; true; }
grp_alive() { [ "$1" -gt 1 ] 2>/dev/null && kill -0 -- "-$1" 2>/dev/null; }
gone_wait() { # gone_wait <pid>: until the pid and its process group are gone (bounded 60 s) -> 0, 1 on timeout
  local n=0
  while [ "$n" -lt 600 ]; do
    if [ ! -d "/proc/$1" ] && ! grp_alive "$1"; then return 0; fi
    sleep 0.1; n=$((n+1))
  done
  return 1
}
capreads() { [ -f "$STUB_LOG/cap.done" ] && wc -l < "$STUB_LOG/cap.done" | tr -d ' ' || echo 0; }
pl() { jq -r "$1" "$JEV_STATE_DIR/placement.json" 2>/dev/null; }
cleanup_row() { # the R13-1 cleanup: releases, an acquire that runs every owed stop (its own start refused), its release, a reap
  for h in sC sB sA sE; do "$PLACE" release "$h" > /dev/null 2>> "$T/c.err"; done
  ( export JEV_PLACE_PROFILES=decide-a PLACE_START_RC=75; exec "$PLACE" acquire sD > /dev/null 2>> "$T/c.err" ); "$PLACE" release sD > /dev/null 2>> "$T/c.err"
  "$PLACE" reap > /dev/null 2>> "$T/c.err"
  assert_eqx "|{}|null" "$(running)|$(jq -c .sets "$JEV_STATE_DIR/leases.json")|$(intents)" "$1: after the cleanup no unit runs, no set and no start intent is left"
}

# ---- R14-1 (R13-B1): the starter is SIGKILLed while its start is in flight ---------------------------------------------
fresh; monoset "$M0"; live_proc; SG="$T/sg"; mkdir -p "$SG"; : > "$T/c.err"
( export JEV_PLACE_PROFILES=decide-a PLACE_START_GATE="$SG"; exec "$PLACE" acquire sA > "$T/a.out" 2> "$T/a.err" ) &
AP=$!; jev_track_pid "$AP"
if wait_file "$SG/reached.start.decide-a" 1200; then
  cp1="$(L '.start_intents["decide-a"].child.pid')"; cps1="$(L '.start_intents["decide-a"].child.pid_start')"
  assert_eqx "$AP" "$(L '.start_intents["decide-a"].pid')" "R14-1 the intent names the starter A"
  if grp_alive "$cp1" && tr '\0' ' ' < "/proc/$cp1/cmdline" 2>/dev/null | grep -q 'timeout'; then ok "R14-1 the intent names the start process: pid $cp1 (start $cps1) runs timeout and is a live process group (M6)"
  else fail "R14-1 the intent's start process [$cp1] is not the running start (no live process group running timeout)"; fi
  if [ "$AP" -gt 1 ] 2>/dev/null; then kill -9 "$AP" 2>/dev/null; fi; wait "$AP" 2>/dev/null
  if grp_alive "$cp1"; then ok "R14-1 CONTROL: A is SIGKILLed and its start is still in flight (the start process group lives)"; else fail "R14-1 the start process died with A (the row cannot show the in-flight case)"; fi
  monoset $(( M0 + 2400 ))
  ( export JEV_PLACE_PROFILES=decide-a; exec timeout 120 "$PLACE" acquire sB > "$T/b.out" 2> "$T/b.err" ); true
  has "$T/b.err" "its start process ($cp1) may still run" "R14-1 B keeps the intent while the start process runs (the log names it)"
  assert_eqx "1 $AP 0 " "$(starts decide-a) $(L '.start_intents["decide-a"].pid') $(adopts "$T/b.err") $(running)" "R14-1 after B: no second start, the intent of A kept, no adoption, the unit not up yet"
  : > "$SG/go.start.decide-a"
  if gone_wait "$cp1"; then ok "R14-1 the orphaned start ended"; else fail "R14-1 the orphaned start never ended"; fi
  assert_eqx "decide-a " "$(running)" "R14-1 CONTROL: the orphaned start brought the unit up after B"
  ( export JEV_PLACE_PROFILES=decide-a JEV_LOCK_TIMEOUT=10; exec timeout 120 "$PLACE" acquire sC --pid "$HP" > "$T/c.out" 2> "$T/c1.err" ); true
  has "$T/c1.err" "recorded constitution-started with an owed stop" "R14-1 C resolves the intent: the running unit is owed a stop"
  assert_eqx "sC true null 0" "$(holders decide-a) $(L '.sets["decide-a"].constitution_started') $(intents) $(adopts "$T/a.err" "$T/b.err" "$T/c1.err")" \
    "R14-1 after C: the owed stop ran, C holds its own constitution-started set, no intent, nothing adopted (stops $(stopsof decide-a))"
  cleanup_row "R14-1"
else fail "R14-1 A's start never began"; fi

# ---- R14-2: the rule on crafted registries ----------------------------------------------------------------------------
# (a) a dead starter, its start process LIVE, the unit absent: kept, no start; the start process ends: removed, started (M1)
fresh; live_proc; dead_proc; live_child; ireg14 "$DP" "${DPST:-null}" "$CP" "${CPST:-null}"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/2a.err" )
has "$T/2a.err" "may still run or was not seen gone" "R14-2a a dead starter's intent with a live start process is kept (M1)"
assert_eqx "0 $DP" "$(starts decide-a) $(L '.start_intents["decide-a"].pid')" "R14-2a no start while the start process runs; the intent kept"
stop_child
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/2a2.err" ); arc=$?
has "$T/2a2.err" "no unit runs: the intent is removed" "R14-2a once the start process is gone the intent is removed"
assert_eqx "0 1 null" "$arc $(starts decide-a) $(intents)" "R14-2a then decide-a is started"
# (b) the same with the unit running: no adoption, no stop while the start process runs; then an owed stop
fresh; live_proc; dead_proc; live_child; ireg14 "$DP" "${DPST:-null}" "$CP" "${CPST:-null}"; : > "$STUB_LOG/running.decide-a"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sC --pid "$HP" > /dev/null 2> "$T/2b.err" )
assert_eqx "0 0 decide-a  $DP null" "$(adopts "$T/2b.err") $(stopsof decide-a) $(running) $(L '.start_intents["decide-a"].pid') $(L '.sets["decide-a"] // null')" \
  "R14-2b a live start process: the running unit is not adopted, not stopped, the intent kept, no set made (M1)"
stop_child
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sC --pid "$HP" > /dev/null 2> "$T/2b2.err" )
has "$T/2b2.err" "recorded constitution-started with an owed stop" "R14-2b once the start process is gone the running unit is owed a stop"
assert_eqx "1 0 null" "$(stopsof decide-a) $(adopts "$T/2b2.err") $(intents)" "R14-2b the owed stop ran, nothing adopted, no intent"
# (c) a REUSED start pid (a live process with another start time) is gone (M3)
fresh; live_proc; dead_proc; ireg14 "$DP" "${DPST:-null}" "$HP" "$(( ${HPST:-1} + 777 ))"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/2c.err" ); arc=$?
assert_eqx "0 1 null" "$arc $(starts decide-a) $(intents)" "R14-2c a reused start pid is a gone start process: the intent is removed and decide-a started (M3)"
# (d) the start process is gone but its process group has a member: in flight (M2); the member ends: resolved
fresh; live_proc; dead_proc; mkdir -p "$T/grp"
setsid bash -c 'cut -d" " -f22 /proc/$$/stat > "$1/lead.st"; echo $$ > "$1/lead.pid"; sleep 600 < /dev/null > /dev/null 2>&1 & echo $! > "$1/mem.pid"; exit 0' _ "$T/grp"
GL="$(cat "$T/grp/lead.pid" 2>/dev/null)"; GLS="$(cat "$T/grp/lead.st" 2>/dev/null)"; GM="$(cat "$T/grp/mem.pid" 2>/dev/null)"; jev_track_pid "$GM"
if [ -n "$GL" ] && [ ! -d "/proc/$GL" ] && grp_alive "$GL"; then ok "R14-2d CONTROL: the leader $GL is gone and its process group has a member"; else fail "R14-2d CONTROL: no group with a dead leader [$GL]"; fi
ireg14 "$DP" "${DPST:-null}" "$GL" "${GLS:-null}"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/2d.err" )
assert_eqx "0 $DP" "$(starts decide-a) $(L '.start_intents["decide-a"].pid')" "R14-2d a start process group with a live member is in flight: kept, no start (M2)"
if [ "${GM:-0}" -gt 1 ] 2>/dev/null; then kill -TERM "$GM" 2>/dev/null; fi
if gone_wait "$GL"; then ok "R14-2d the group member ended"; else fail "R14-2d the group member never ended"; fi
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/2d2.err" ); arc=$?
assert_eqx "0 1 null" "$arc $(starts decide-a) $(intents)" "R14-2d once the group is empty the intent is removed and decide-a started"
# (e) a round-13 intent (no start process): in flight until older than MARK_TTL (M7)
fresh; live_proc; dead_proc; ireg14 "$DP" "${DPST:-null}" null null
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/2e.err" )
assert_eqx "0 $DP" "$(starts decide-a) $(L '.start_intents["decide-a"].pid')" "R14-2e a round-13 intent younger than MARK_TTL is kept, no start (M7)"
clockset $(( T0 + 100000 ))
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/2e2.err" ); arc=$?
assert_eqx "0 1 null" "$arc $(starts decide-a) $(intents)" "R14-2e a round-13 intent older than MARK_TTL is resolved: removed, decide-a started (M7)"
# (f) the reviewer's witness WV01: a REUSED starter pid (V01: pid_start ignored for intents)
fresh; live_proc; dead_proc; ireg14 "$HP" "$(( ${HPST:-1} + 777 ))" "$DP" "${DPST:-null}"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/2f.err" ); arc=$?
has "$T/2f.err" "no unit runs: the intent is removed" "R14-2f (WV01) a reused starter pid is a dead starter (V01)"
assert_eqx "0 1 null" "$arc $(starts decide-a) $(intents)" "R14-2f (WV01) the intent is removed and decide-a started"
# (g) the reviewer's witness WV02: a dead starter, no set, the unit DEGRADED (V02: degraded treated as unknown)
fresh; live_proc; dead_proc; ireg14 "$DP" "${DPST:-null}" "$DP" "${DPST:-null}"; : > "$STUB_LOG/running.decide-a"
( export JEV_PLACE_PROFILES=decide-a PLACE_DEGRADED=decide-a PLACE_START_RC=75; exec "$PLACE" acquire sD > /dev/null 2> "$T/2g.err" )
has "$T/2g.err" "recorded constitution-started with an owed stop" "R14-2g (WV02) a degraded unit under a dead intent is owed a stop (V02)"
assert_eqx "1 null" "$(stopsof decide-a) $(intents)" "R14-2g (WV02) the owed stop ran, no intent left"
# (h) F3 (V08: the intent refusal returned as a stale mark): a live starter's intent refuses the start on ONE answer
fresh; live_proc; live_child; ireg14 "$HP" "${HPST:-null}" "$CP" "${CPST:-null}"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/2h.err" ); arc=$?
has "$T/2h.err" "is unanswered; not started" "R14-2h a live starter's intent refuses the start (the log names it)"
assert_eqx "5 0 1 no_fit null" "$arc $(starts decide-a) $(capreads) $(pl .placement.event) $(pl .placement.reason_code)" \
  "R14-2h no start, one capacity read, event no_fit with no reason code (never stale_answer) (F3, V08)"
stop_child
# (i) M11: an intent whose start process has no recorded start time cannot tell its pid from a reused one: while that pid
# lives the start is in flight (fail-safe: kept, no start)
fresh; live_proc; dead_proc; live_child; ireg14 "$DP" "${DPST:-null}" "$CP" null
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/2i.err" )
has "$T/2i.err" "may still run or was not seen gone" "R14-2i a live start pid with no recorded start time keeps the intent (M11)"
assert_eqx "0 $DP" "$(starts decide-a) $(L '.start_intents["decide-a"].pid')" "R14-2i no start, the intent kept"
stop_child

# ---- R14-3: the gate -------------------------------------------------------------------------------------------------
# (a) a refused mark runs no llmctl start: the start process is told `no` and exits (M4: an ungated start)
assert_eqx "0" "$(grep -c '^llmctl start' "$STUB_LOG/llmctl.log")" "R14-3a the refused mark of R14-2h ran no llmctl start at all (M4)"
# (b) the starter is SIGKILLed after its intent was written and before `go`: its start process exits, llmctl never runs
fresh; SG="$T/sg3"; mkdir -p "$SG"
gated "$T/g3c" 0 0 "$T/a3c" JEV_PLACE_PROFILES=decide-a PLACE_START_GATE="$SG" -- acquire sA; ap=$GPID
wait_file "$SG/reached.start.decide-a" 1200 || fail "R14-3b calibration: the start never began"
NM="$(cat "$T/g3c/count")"
if grep -q "^flock#$NM -u" "$T/g3c/calls.log"; then ok "R14-3b calibration: the call before the start is the mark's unlock (flock call $NM)"; else fail "R14-3b calibration: flock call $NM is not an unlock"; fi
: > "$SG/go.start.decide-a"; rc_of "$ap" >/dev/null
fresh; monoset "$M0"; SG="$T/sg3"; mkdir -p "$SG"
gated "$T/g3" 0 "$NM" "$T/a3" JEV_PLACE_PROFILES=decide-a PLACE_START_GATE="$SG" -- acquire sA; ap=$GPID
rc_of "$ap" >/dev/null
cp3="$(L '.start_intents["decide-a"].child.pid')"
assert_eqx "y $ap" "$([ -e "$T/g3/killed" ] && echo y || echo n) $(L '.start_intents["decide-a"].pid')" "R14-3b A was SIGKILLed at the mark's unlock; its intent is in the registry"
if gone_wait "$cp3"; then ok "R14-3b the start process ($cp3) exited on the closed gate"; else fail "R14-3b the start process ($cp3) is still running"; fi
assert_eqx "0 " "$(grep -c '^llmctl start' "$STUB_LOG/llmctl.log") $(running)" "R14-3b llmctl start never ran, no unit (M4)"
monoset $(( M0 + 2400 ))   # A's lease (no pid) is past its TTL: the set A left is disposed of
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/3b.err" ); arc=$?
# the set A left exists: the intent is removed with it made constitution-started, and the set (no lease) is disposed of;
# a profile this acquire stopped is held until the next evaluation (§11.4.291(D)), which starts it
assert_eqx "5 0 1 null" "$arc $(starts decide-a) $(stopsof decide-a) $(intents)" "R14-3b the next acquire removes the intent and disposes of the set A left (one stop, no start: held)"
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE > /dev/null 2> "$T/3b2.err" ); arc=$?
assert_eqx "0 1 null" "$arc $(starts decide-a) $(intents)" "R14-3b the next evaluation starts decide-a (the intent never blocks it)"

# ---- R14-4 (M5): an answer read while the start process ran never resolves the intent ---------------------------------
fresh; live_proc; dead_proc; live_child; ireg14 "$DP" "${DPST:-null}" "$CP" "${CPST:-null}"; mkdir -p "$T/cg"
( export JEV_PLACE_PROFILES=decide-a PLACE_CAP_GATE="$T/cg" PLACE_CAP_GATE_AT=1; exec "$PLACE" acquire sE > /dev/null 2> "$T/4.err" ) &
bp=$!; jev_track_pid "$bp"
if wait_file "$T/cg/reached" 600; then
  stop_child; : > "$STUB_LOG/running.decide-a"
  if gone_wait "$CP"; then ok "R14-4 the start process ended after B's answer was fixed (the unit came up)"; else fail "R14-4 the start process never ended"; fi
  : > "$T/cg/go"; rc_of "$bp" >/dev/null
  has "$T/4.err" "may still run or was not seen gone" "R14-4 B's answer was read while the start process ran: the intent is kept (M5)"
  assert_eqx "0 0 $DP decide-a " "$(starts decide-a) $(adopts "$T/4.err") $(L '.start_intents["decide-a"].pid') $(running)" "R14-4 B: no start, no adoption, the intent kept, the unit running"
  ( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sC --pid "$HP" > /dev/null 2> "$T/4c.err" )
  has "$T/4c.err" "recorded constitution-started with an owed stop" "R14-4 the next observation resolves it: an owed stop"
  assert_eqx "1 0 null" "$(stopsof decide-a) $(adopts "$T/4c.err") $(intents)" "R14-4 the owed stop ran, nothing adopted, no intent"
else fail "R14-4 B never reached its capacity gate"; fi

# ---- R14-5 (M8): a start process that exits after `go` without running llmctl started nothing ---------------------
# The start gate of the producer under test is copied and changed so that it exits 79 where it would write <out>.went
# (that write failing): llmctl never runs. The starter must record a refused start (rc 75: no stop owed, no stop run),
# never a failed start whose unit may be up.
GD="$(mktemp -d)"; _JEV_FIXTURE_DIRS+=("$GD"); mkdir -p "$GD/scripts"; cp -R "$(dirname "$PLACE")" "$GD/scripts/jev"
python3 - "$GD/scripts/jev/jev-start-gate.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = ': > "$o.went" || exit 79\n'
assert s.count(a) == 1, "gate anchor not found"
open(p, "w").write(s.replace(a, 'exit 79\n'))
PY
fresh
( export JEV_PLACE_PROFILES=decide-a; exec "$GD/scripts/jev/jev-place.sh" acquire sE > /dev/null 2> "$T/5.err" ); arc=$?
has "$T/5.err" "before it ran llmctl" "R14-5 the starter sees that llmctl never ran (no <out>.went)"
assert_eqx "0 0 null" "$(grep -c '^llmctl start' "$STUB_LOG/llmctl.log") $(stopsof decide-a) $(intents)" \
  "R14-5 no llmctl start, no stop (a refused start owes none), no intent left (M8)"
if [ "$arc" != 0 ]; then ok "R14-5 the acquire does not report a start that never ran (rc $arc)"; else fail "R14-5 the acquire returned 0 on a start that never ran"; fi

# ---- R14-6: the "ours" state of the sweep is never orphaned -----------------------------------------------------------
oursreg() { # a lease-less constitution-started set of decide-a, its stopping mark naming a dead process; the unit runs
  dead_proc
  reg -n --argjson dp "$DP" --argjson dps "${DPST:-null}" --argjson t "$T0" \
    '{gen:1, sets:{"decide-a":{constitution_started:true, started_at:$t, starting:null, leases:[],
      stopping:{at:$t, mono:null, pid:$dp, pid_start:$dps, holder:"sA"}}}}'
  : > "$STUB_LOG/running.decide-a"
}
fresh; oursreg
"$PLACE" release sQ > /dev/null 2> "$T/6a.err"
assert_eqx "1 |{}|null" "$(stopsof decide-a) $(running)|$(jq -c .sets "$JEV_STATE_DIR/leases.json")|$(intents)" \
  "R14-6a a release by a holder with no lease clears the dead stopper's mark and stops the lease-less constitution-started set"
fresh; live_proc; oursreg
( export JEV_PLACE_PROFILES=decide-a; exec "$PLACE" acquire sE --pid "$HP" > /dev/null 2> "$T/6b.err" ); arc=$?
assert_eqx "0 0 0 sE true" "$arc $(starts decide-a) $(adopts "$T/6b.err") $(holders decide-a) $(L '.sets["decide-a"].constitution_started')" \
  "R14-6b an acquire joins it as constitution-started: no start, no adoption as operator-started"
"$PLACE" release sE > /dev/null 2>> "$T/6b.err"
assert_eqx "1 " "$(stopsof decide-a) $(running)" "R14-6b its release stops the unit"

count_lockheld
assert_eqx 0 "$LOCKHELD_TOTAL" "no llmctl call ran under the lease lock in any row (R4-3)"
finish
