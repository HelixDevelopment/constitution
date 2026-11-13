#!/usr/bin/env bash
# test_s4_round7.sh — round 7 (2026-11-13, structural) of the S4 placement producer scripts/jev/jev-place.sh (§11.4.291),
# review of eb29803b (docs/qa/jev_s3s4_20261112/round7/). GATE-LOGIC tests (§11.4.289(C)(2)): the stub llmctl in
# tests/jev/fixtures/bin-place answers from a declared file; these prove the producer DECIDES correctly, never that a
# local model runs. Every row that targets a round-7 change was run RED-first against eb29803b (round7/red_*.txt); the
# rows marked "mutant row" pass on eb29803b as well and exist to kill a named mutant (round7/mutants.md).
#
# Races are replayed in a FIXED order, never by sleeping: tests/jev/fixtures/bin-flockgate/flock pauses one jev-place
# process at a numbered flock call until the test lets it go (FLOCK_GATE_AT), or SIGKILLs it there (FLOCK_GATE_KILL_AT);
# the stub's PLACE_CAP_GATE pauses one capacity call. Flock calls of one acquire (with_lock = lock + `flock -u`):
#   ticket 1-2, plan 3-4, mark 5-6, record 7-8; with JEV_PLACE_MAX > 1 the next start: ticket 9-10, mark 11-12, ...;
#   a re-plan after a stale mark: ticket, plan, mark again (the 2nd mark is call 11, the 3rd 17, the 4th 23);
#   the post-start observation ticket after one start: 9. An observer (status): ticket 1-2, finalize 3-4.
#
#   P72 (NF-1)  THE WHOLE §11.4.291(C) CONTRACT TABLE: every required field, absent and of a wrong type, makes the answer
#               undetermined and the reason names the field; nothing is started. The field list below is written from
#               the canon table (Constitution.md §11.4.291(C)), not from the producer. Plus llmctl's
#               measurement.critical_inputs_unreadable, and the producer's own pressure guard (VM01)
#   P73 (NF-2a) a stale answer is never started on: B's answer predates A's start of decide-a; B joins decide-a (the
#               review's repro: B used to start decide-b on the pre-start answer)
#   P74 (NF-2b) the same with B's own candidate: B used to start decide-a next to C's decide-b
#   P75 (NF-2)  a writer that does not know the generation (an older constitution pin shares the per-user registry):
#               the HASH part of the freshness token catches it
#   P75b (NF-2) ABA: a start that fails and is cleaned up leaves the registry bytes as they were except the generation;
#               an answer read while that unit briefly ran is not used (the GENERATION part catches it)
#   P76 (VM13)  mutant row: a set created after the answer, while the answer lags, is never overwritten by the mark
#   P77 (VM10)  mutant row: the plan's freshness check (seam 1): B re-reads and joins instead of being refused
#   P78 (NF-3)  a reap that clears a dead starter's mark sets a floor: an older answer never marks the set gone
#   P79 (VM06)  a live starter's mark is kept until MARK_TTL (start timeout + 2 + retries x lock timeout + 30) and
#               cleared one second later
#   P80 (VM07)  mutant row: a heartbeat refreshes only its holder's lease; the stale holder is reaped by a later release
#   P81 (NF-2)  INVENTORY PROPERTY: in llmctl's call log no `llmctl start` follows another start or a stop without a
#               capacity answer in between (refused start, failed start + cleanup, disposal stop)
#   P82 (NF-2)  bounded: the registry changes before every start mark -> STALE_MAX re-plans, then no start (stale_answer)
#   P82b (NF-2) bounded: the registry changes during every capacity read -> STALE_MAX re-reads, then a plan with joins
#               and stops only (stale_answer, no start)
#   P83 (NF-2)  mutant row: a plan that changes nothing writes nothing, so a concurrent acquire is not made stale for no
#               reason (the conditional gateway write)
#   P84 (N6-b)  `status` with no placement record yet exits 0 and says so
#   P85 (N6-e)  an undetermined candidate's reason is in the record (nproc_unlimited)
#   P86 (NF-2)  mutant row: an owed stop that fails again is tried once per acquire (STOP_TRIED), so the re-plan ends
#   P87 (R5-1)  mutant row (OM03): on the further-start path (JEV_PLACE_MAX > 1) a set that was already stopping when the
#               fresh answer's ticket was taken refuses the mark (the token cannot see it: it predates the ticket)
#   P88 (NF-2)  the lease this acquire took is the authority for every further start: once it is released, no further
#               start (round 6 P70 relied on the stopping mark alone and became timing-dependent under the round-7 rule)
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
  make_fixture_env s4r7
  export PATH="$FIXTURES/bin-place:$PATH" JEV_TEST=1 PLACE_CAP_JSON="$T/cap.json" JEV_LOCK_TIMEOUT=2
  unset PLACE_CAP_RC PLACE_CAP_RC_FILE PLACE_CAP_SLEEP PLACE_CAP_RAW PLACE_CAP_GATE PLACE_CAP_GATE_AT PLACE_CAP_GATE_WHEN \
        PLACE_START_RC PLACE_START_SLEEP PLACE_STOP_RC PLACE_STOP_SLEEP PLACE_DEGRADED PLACE_GONE PLACE_FULL_AFTER PLACE_DCAP_RC \
        PLACE_STATUS_RC PLACE_STATUS_URL PLACE_STATUS_NOGW JEV_LLMCTL_TIMEOUT JEV_LLMCTL_START_TIMEOUT JEV_PLACE_MAX \
        JEV_PLACE_PROFILES LLMCTL_GATEWAY_URL LLMCTL_CACERT LLMCTL_TENANT_ID JEV_LEASE_TTL JEV_REEVAL_CADENCE JEV_RECORD_RETRIES \
        JEV_PROJECT FLOCK_GATE_DIR FLOCK_GATE_AT FLOCK_GATE_KILL_AT
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

# ---- P72 (NF-1): the whole contract table ---------------------------------------------------------------------------
# The base document carries every field the canon table requires, plus one foreign unit (so the per-unit fields exist).
# Each case is served RAW (the stub returns the document unchanged): <label> <jq edit> <expected verdict> <needle>.
p72_case() {
  local label="$1" edit="$2" ev="$3" needle="$4" rc r v
  fresh; cap "$T/base.json"
  jq ".llmctl.units = [{unit:\"llmctl-llama@other.service\", profile:\"other\", owner:\"other\", status:\"ok\", reasons:[]}] | $edit" "$T/base.json" > "$T/cap.json" \
    || { fail "P72 $label: the test edit is not valid jq"; return; }
  export PLACE_CAP_RAW=1 JEV_PLACE_PROFILES=decide-a
  "$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e72"; rc=$?
  r="$(pl .placement.reason)"; v="$(pl .placement.verdict)"
  if [ "$rc $(starts) $v" = "5 0 $ev" ] && printf '%s' "$r" | grep -qF -- "$needle"; then
    ok "P72 $label: verdict $ev, nothing started, the reason names [$needle]"
  else fail "P72 $label (expected rc 5, 0 starts, verdict $ev, a reason naming [$needle]; got rc $rc, $(starts) starts, verdict $v, reason [$r])"; fi
  unset PLACE_CAP_RAW JEV_PLACE_PROFILES
}
# CONTROLS: the full document (served raw and computed) starts decide-a, so a row's refusal is caused by its edit
fresh; cap "$T/base.json"
jq '.llmctl.units = [{unit:"llmctl-llama@other.service", profile:"other", owner:"other", status:"ok", reasons:[]}]' "$T/base.json" > "$T/cap.json"
PLACE_CAP_RAW=1 JEV_PLACE_PROFILES=decide-a "$PLACE" acquire s1 --pid $$ > "$T/c72.out" 2>"$T/c72.err"; rc=$?
assert_eqx "0 decide-a 1" "$rc $(cat "$T/c72.out") $(starts)" "P72 CONTROL: the full document served raw starts decide-a"
fresh
JEV_PLACE_PROFILES=decide-a "$PLACE" acquire s1 --pid $$ > "$T/c72b.out" 2>/dev/null; rc=$?
assert_eqx "0 decide-a 1" "$rc $(cat "$T/c72b.out") $(starts)" "P72 CONTROL: the full document served computed starts decide-a"
U=undetermined
# required top-level fields (canon table rows 1, 2, 5-9), absent and of a wrong type
p72_case "schema absent"                    'del(.schema)'                        "$U" schema
p72_case "schema of another version"        '.schema = "llmctl.capacity/2"'       "$U" schema
p72_case "time absent"                      'del(.time)'                          "$U" time
p72_case "time a string"                    '.time = "1700000000"'                "$U" time
for f in cpus_online mem_total_mb mem_available_mb usable_mem_mb swap_total_mb swap_free_mb; do
  p72_case "host.$f absent"                 "del(.host.$f)"                       "$U" "host.$f"
  p72_case "host.$f a string"               ".host.$f = \"16\""                   "$U" "host.$f"
done
p72_case "host.load absent"                 'del(.host.load)'                     "$U" host.load
p72_case "host.load a string"               '.host.load = "1.0 1.0 1.0"'          "$U" host.load
p72_case "host.load.5 absent"               'del(.host.load["5"])'                "$U" host.load
p72_case "host.psi absent"                  'del(.host.psi)'                      "$U" host.psi
p72_case "host.psi a string"                '.host.psi = "none"'                  "$U" host.psi
p72_case "host.psi.cpu absent"              'del(.host.psi.cpu)'                  "$U" host.psi
p72_case "host.cgroup absent"               'del(.host.cgroup)'                   "$U" host.cgroup
p72_case "host.cgroup an array"             '.host.cgroup = []'                   "$U" host.cgroup
p72_case "host absent"                      'del(.host)'                          "$U" host
p72_case "reserve absent"                   'del(.reserve)'                       "$U" reserve
p72_case "reserve a string"                 '.reserve = "4000"'                   "$U" reserve
p72_case "pressure absent"                  'del(.pressure)'                      "$U" pressure
p72_case "pressure.ok a string"             '.pressure.ok = "yes"'                "$U" pressure.ok
p72_case "pressure.reasons absent"          'del(.pressure.reasons)'              "$U" pressure.reasons
p72_case "llmctl.units absent"              'del(.llmctl.units)'                  "$U" llmctl.units
p72_case "llmctl.units an object"           '.llmctl.units = {}'                  "$U" llmctl.units
p72_case "llmctl.units[].profile absent"    'del(.llmctl.units[0].profile)'       "$U" llmctl.units
p72_case "llmctl.units[].profile a number"  '.llmctl.units[0].profile = 1'        "$U" llmctl.units
p72_case "llmctl.units[].status absent"     'del(.llmctl.units[0].status)'        "$U" llmctl.units
p72_case "llmctl.units[].status a number"   '.llmctl.units[0].status = 1'         "$U" llmctl.units
p72_case "llmctl.units[].reasons absent"    'del(.llmctl.units[0].reasons)'       "$U" llmctl.units
p72_case "llmctl.units[].reasons a string"  '.llmctl.units[0].reasons = "x"'      "$U" llmctl.units
p72_case "fallback.recommended absent"      'del(.fallback.recommended)'          "$U" fallback.recommended
p72_case "fallback.recommended outside the set" '.fallback.recommended = "maybe"' "$U" fallback.recommended
p72_case "fallback.key_variable absent"     'del(.fallback.key_variable)'         "$U" fallback.key_variable
p72_case "fallback.key_variable a number"   '.fallback.key_variable = 42'         "$U" fallback.key_variable
p72_case "unknown_profiles absent"          'del(.unknown_profiles)'              "$U" unknown_profiles
p72_case "unknown_profiles an object"       '.unknown_profiles = {}'              "$U" unknown_profiles
p72_case "degraded absent"                  'del(.degraded)'                      "$U" degraded
p72_case "degraded a string"                '.degraded = "false"'                 "$U" degraded
p72_case "largest_decision_fit absent"      'del(.largest_decision_fit)'          "$U" largest_decision_fit
p72_case "largest_decision_fit a number"    '.largest_decision_fit = 42'          "$U" largest_decision_fit
p72_case "profiles absent"                  'del(.profiles)'                      "$U" profiles
# per-profile fields (canon table rows 3-4) of the candidate
for f in verdict threads reasons headroom; do
  p72_case "profiles.decide-a.$f absent"    "del(.profiles[\"decide-a\"].$f)"   "$U" "$f"
done
p72_case "profiles.decide-a.verdict a number"   '.profiles["decide-a"].verdict = 1'        "$U" verdict
p72_case "profiles.decide-a.threads a string"   '.profiles["decide-a"].threads = "3"'      "$U" threads
p72_case "profiles.decide-a.reasons a string"   '.profiles["decide-a"].reasons = "none"'   "$U" reasons
p72_case "profiles.decide-a.headroom a number"  '.profiles["decide-a"].headroom = 1000'    "$U" headroom
# llmctl's own list of inputs it could not read (non-strict mode keeps measurement.ok true)
p72_case "measurement.critical_inputs_unreadable non-empty" \
  '.measurement.critical_inputs_unreadable = ["host.psi.memory: /proc/pressure/memory unreadable"]' "$U" host.psi.memory
# VM01: the producer's own pressure guard — an answer with pressure.ok false is never read as fits, even when the
# profile's verdict says fits (the computed stub converts it; a raw answer does not)
p72_case "pressure.ok false with verdict fits (VM01)" \
  '.pressure = {ok:false, reasons:["psi full avg10 3.1 > 2"]}' does_not_fit "psi full avg10 3.1"

# ---- P73 (NF-2a): B's answer predates A's start of decide-a; B joins decide-a, never starts decide-b -----------------
fresh; export PLACE_FULL_AFTER=decide-a
gated "$T/gB" 5 0 "$T/b73" JEV_PLACE_PROFILES=decide-a,decide-b -- acquire sB --pid $$; b73=$GPID
reach "$T/gB" 5 "P73 B planned decide-a on an answer read before any start"
JEV_PLACE_PROFILES=decide-a "$PLACE" acquire sA --pid $$ > "$T/a73.out" 2>"$T/a73.err"; arc=$?
go "$T/gB" 5; wait "$b73"; brc=$?
assert_eqx "0 decide-a" "$arc $(cat "$T/a73.out")" "P73 A starts decide-a while B waits at its start mark"
assert_eqx "0 decide-a" "$brc $(cat "$T/b73.out")" "P73 B joins decide-a (a fresh plan after the stale mark)"
assert_eqx "1 0" "$(starts) $(startsof decide-b)" "P73 one start in all; decide-b is never started on B's pre-start answer"
assert_eqx "decide-a " "$(running)" "P73 only decide-a runs"
has "$T/b73.err" "stale answer" "P73 B announces the stale answer and the fresh plan"
assert_eqx 0 "$(inv_violations)" "P73 every start follows a capacity answer read after the previous start"

# ---- P74 (NF-2b): the same with B's own candidate --------------------------------------------------------------------
fresh; export PLACE_FULL_AFTER=decide-b
gated "$T/gB" 5 0 "$T/b74" JEV_PLACE_PROFILES=decide-a -- acquire sB --pid $$; b74=$GPID
reach "$T/gB" 5 "P74 B planned decide-a"
JEV_PLACE_PROFILES=decide-b "$PLACE" acquire sC --pid $$ > "$T/c74.out" 2>/dev/null; crc=$?
go "$T/gB" 5; wait "$b74"; brc=$?
assert_eqx "0 decide-b" "$crc $(cat "$T/c74.out")" "P74 C starts decide-b while B waits"
assert_eqx "0 decide-b" "$brc $(cat "$T/b74.out")" "P74 B re-plans and joins decide-b (its fresh answer says decide-a does not fit)"
assert_eqx "1 0" "$(starts) $(startsof decide-a)" "P74 decide-a is never started next to decide-b on B's stale answer"

# ---- P75 (NF-2): a writer that does not know the generation; the hash part of the token catches it ------------------
fresh; export PLACE_FULL_AFTER=decide-a
gated "$T/gA" 5 0 "$T/a75" JEV_PLACE_PROFILES=decide-a,decide-b -- acquire sA --pid $$; a75=$GPID
reach "$T/gA" 5 "P75 A planned decide-a"
gen0="$(L '.gen')"; older_pin_place decide-a sOld
assert_eqx "$gen0" "$(L '.gen')" "P75 the older-pin writer left the generation unchanged (the instrument)"
go "$T/gA" 5; wait "$a75"; arc=$?
assert_eqx "0 decide-a" "$arc $(cat "$T/a75.out")" "P75 A re-plans and joins the set the older-pin writer created"
assert_eqx "1 0" "$(starts) $(startsof decide-b)" "P75 only the writer's start; decide-b is never started on A's stale answer"
assert_eqx "sOld,sA" "$(L '[.sets["decide-a"].leases[].holder] | join(",")')" "P75 the writer's lease is kept, A's is added"

# ---- P75b (NF-2): ABA — the generation part of the token ------------------------------------------------------------
# B's capacity call is held BEFORE it computes, so B's answer is read while C's start of decide-a has the unit up (the
# stub start creates the unit, then fails); C's cleanup stop and record then leave the registry bytes as B's ticket saw
# them, except the generation. Without the generation B would adopt a unit that is gone ("already running").
fresh
JEV_PLACE_PROFILES=decide-a PLACE_CAP_RC=99 "$PLACE" acquire s0 >/dev/null 2>&1   # the registry exists (gateway only)
mkdir -p "$T/capB"
gated "$T/gB" 3 0 "$T/b75b" JEV_PLACE_PROFILES=decide-a JEV_LLMCTL_TIMEOUT=180 PLACE_CAP_GATE="$T/capB" PLACE_CAP_GATE_AT=1 PLACE_CAP_GATE_WHEN=before \
  -- acquire sB --pid $$; b75=$GPID
if wait_file "$T/capB/reached"; then ok "P75b B took its ticket; its capacity call waits"; else fail "P75b B never reached its capacity call"; fi
r0_75="$(L 'del(.gen)')"; g0_75="$(L '.gen')"
gated "$T/gC" 7 0 "$T/c75b" JEV_PLACE_PROFILES=decide-a PLACE_START_RC=1 -- acquire sC --pid $$; c75=$GPID
reach "$T/gC" 7 "P75b C's start of decide-a failed with the unit up; its record waits"
: > "$T/capB/go"
reach "$T/gB" 3 "P75b B read its answer while C's unit was up"
go "$T/gC" 7; wait "$c75"; crc=$?
assert_eqx "5 " "$crc $(running)" "P75b C cleaned up: rc 5, no unit left"
# the instrument: the registry is byte-for-byte what B's ticket saw except the generation (an ABA for a hash-only token)
if [ "$(L 'del(.gen)')" = "$r0_75" ] && [ "$(L '.gen')" != "$g0_75" ]; then ok "P75b CONTROL: the registry bytes are as B's ticket saw them, except the generation ($g0_75 -> $(L '.gen'))"
else fail "P75b CONTROL: the registry is not an ABA of B's ticket (the row would not test the generation): $(L 'del(.gen)') vs $r0_75"; fi
go "$T/gB" 3; wait "$b75"; brc=$?
assert_eqx "0 decide-a placed" "$brc $(cat "$T/b75b.out") $(pl .placement.event)" "P75b B re-reads and STARTS decide-a; it never adopts the gone unit"
assert_eqx "decide-a " "$(running)" "P75b decide-a runs"

# ---- P76 (VM13, mutant row): the mark never overwrites a set created after the answer -------------------------------
# A starts decide-a, then (JEV_PLACE_MAX=2) reads a fresh answer for decide-b; that answer lags (PLACE_GONE hides the
# decide-b unit) and the older-pin writer created decide-b's set before A's ticket. The mark must refuse (set exists).
fresh
gated "$T/gA" 9 0 "$T/a76" JEV_PLACE_PROFILES=decide-a,decide-b JEV_PLACE_MAX=2 PLACE_GONE=decide-b -- acquire sA --pid $$; a76=$GPID
reach "$T/gA" 9 "P76 A started decide-a; its next ticket waits"
older_pin_place decide-b sOld
go "$T/gA" 9; wait "$a76"; arc=$?
assert_eqx "0 decide-a" "$arc $(cat "$T/a76.out")" "P76 A placed decide-a"
assert_eqx "1 1" "$(startsof decide-a) $(startsof decide-b)" "P76 decide-b is started once (by the writer), never again by A's mark"
has "$T/a76.err" "candidate decide-b: not started" "P76 A announces it did not start decide-b"

# ---- P77 (VM10, mutant row): the plan's freshness check --------------------------------------------------------------
# B read its answer before A's start; A's set is pending (A waits before its post-start observation). Without the plan
# check B would judge the set on its old ticket (not newer than the start floor) and refuse the join.
fresh
gated "$T/gB" 3 0 "$T/b77" JEV_PLACE_PROFILES=decide-a -- acquire sB --pid $$; b77=$GPID
reach "$T/gB" 3 "P77 B read its answer"
gated "$T/gA" 9 0 "$T/a77" JEV_PLACE_PROFILES=decide-a -- acquire sA --pid $$; a77=$GPID
reach "$T/gA" 9 "P77 A started decide-a; its post-start observation waits"
assert_eqx pending "$(L '.sets["decide-a"].health.state')" "P77 A's set is pending (floored at the start)"
go "$T/gB" 3; wait "$b77"; brc=$?
assert_eqx "0 decide-a joined" "$brc $(cat "$T/b77.out") $(pl .placement.event)" "P77 B re-reads (its answer predates the start) and joins"
go "$T/gA" 9; wait "$a77"; arc=$?
assert_eqx "0 1" "$arc $(starts)" "P77 A finishes; one start"

# ---- P78 (NF-3): a reap that clears a dead starter's mark sets a floor ------------------------------------------------
fresh
gated "$T/gC" 3 0 "$T/c78" -- status; c78=$GPID
reach "$T/gC" 3 "P78 the observer read its answer before any start"
gated "$T/gA" 0 7 "$T/a78" JEV_PLACE_PROFILES=decide-a -- acquire sA --pid $$; a78=$GPID
wait "$a78" 2>/dev/null
if [ -e "$T/gA/killed" ]; then ok "P78 the starter was killed after llmctl start rc 0, before its record (the instrument)"
else fail "P78 the starter was not killed at its record step"; fi
assert_eqx "1 decide-a  true" "$(starts) $(running) $(L '.sets["decide-a"].starting != null')" "P78 the unit runs; the set still carries the dead starter's mark"
go "$T/gC" 3; wait "$c78"; crc=$?
assert_eqx "0 null 1" "$crc $(L '.sets["decide-a"].gone') $(L '.sets["decide-a"].leases | length')" "P78 the observer clears the mark and does NOT mark the set gone (its answer predates the start)"
assert_eqx "pending null" "$(L '.sets["decide-a"].health.state') $(L '.sets["decide-a"].starting')" "P78 the set is pending (floor), its mark cleared"
hasnt "$T/c78.err" "endpoint_gone" "P78 no endpoint_gone"
"$PLACE" heartbeat sA >/dev/null 2>"$T/hb78.err"; hrc=$?
assert_eqx "0 ok" "$hrc $(L '.sets["decide-a"].health.state')" "P78 sA still holds its lease; a newer observation reads the unit ok"
"$PLACE" release sZ >/dev/null 2>"$T/rel78.err"
assert_eqx "0 decide-a " "$(stops) $(running)" "P78 another holder's release stops nothing (the set keeps sA's lease)"

# ---- P79 (VM06): a live starter's mark is kept until MARK_TTL, cleared one second later -----------------------------
# MARK_TTL = start timeout + 2 (timeout's kill-after) + record retries x lock timeout + 30 (header "Round 7")
STMO79=100 LOCK79=2 RET79=3; TTL79=$(( STMO79 + 2 + RET79 * LOCK79 + 30 ))
p79() {
  fresh
  # shellcheck disable=SC2031  # set here for P79 on purpose; the subshell change in gated() is a different scope
  export JEV_LLMCTL_START_TIMEOUT=$STMO79 JEV_LOCK_TIMEOUT=$LOCK79 JEV_RECORD_RETRIES=$RET79
  local now0="$JEV_NOW_EPOCH" pst; pst="$(proc_start_of $$)"
  jq -n --argjson now "$now0" --argjson pid "$$" --argjson pst "${pst:-null}" \
    '{sets:{"decide-a":{constitution_started:true, started_at:null, stopping:null, starting:{at:$now, pid:$pid, pid_start:$pst},
       leases:[{holder:"sA", pid:$pid, pid_start:$pst, heartbeat_at:$now, ttl:900, project:null, started_by_this_session:true}]}}}' \
    > "$JEV_STATE_DIR/leases.json"
  JEV_NOW_EPOCH=$(( now0 + $1 )) "$PLACE" status >/dev/null 2>"$T/st79.err"
  P79_PID="$(L '.sets["decide-a"].starting.pid')"   # called in THIS shell (never in $(...): fresh must set T here)
}
p79 "$TTL79";             assert_eqx "$$" "$P79_PID" "P79 a live starter's mark is kept at MARK_TTL ($TTL79 s)"
p79 $(( TTL79 + 1 ));     assert_eqx null "$P79_PID" "P79 it is cleared one second later"
assert_eqx starting "$(L '.sets["decide-a"].mark_cleared.mark')" "P79 the clearing is recorded"

# ---- P80 (VM07, mutant row): a heartbeat refreshes only its holder's lease -------------------------------------------
fresh; export JEV_PLACE_PROFILES=decide-a; T0="$JEV_NOW_EPOCH"
"$PLACE" acquire sA >/dev/null 2>&1; "$PLACE" acquire sB >/dev/null 2>&1
JEV_NOW_EPOCH=$(( T0 + 800 )) "$PLACE" heartbeat sB >/dev/null 2>&1; hrc=$?
assert_eqx "0 $T0" "$hrc $(L '[.sets["decide-a"].leases[] | select(.holder == "sA") | .heartbeat_at] | first')" "P80 sB's heartbeat leaves sA's heartbeat_at at its own value"
JEV_NOW_EPOCH=$(( T0 + 1000 )) "$PLACE" release sB >/dev/null 2>&1
assert_eqx "1 " "$(stops) $(running)" "P80 sA (no heartbeat for 1000 s > TTL 900) is reaped; the last release stops the model"

# ---- P81 (NF-2): no start without a capacity answer since the previous start / stop ---------------------------------
fresh; export JEV_PLACE_PROFILES=decide-a,decide-b PLACE_START_RC=75
timeout 120 "$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e81a"; rc=$?
assert_eqx "5 1 1 start_refused" "$rc $(startsof decide-a) $(startsof decide-b) $(pl .placement.event)" "P81a both starts refused (75): each tried once, rc 5"
assert_eqx 0 "$(inv_violations)" "P81a after a refused start the next start is decided on a fresh answer"
hasnt "$T/e81a" "stale answer" "P81a the fresh answer comes from the planned re-plan, never from the stale-mark backstop"
fresh; export JEV_PLACE_PROFILES=decide-a,decide-b PLACE_START_RC=1
timeout 120 "$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e81c"; rc=$?
assert_eqx "5 1 1 2 " "$rc $(startsof decide-a) $(startsof decide-b) $(stops) $(running)" "P81c both starts fail; each cleaned up, rc 5, no unit left"
assert_eqx 0 "$(inv_violations)" "P81c after a failed start and its cleanup stop the next start is decided on a fresh answer"
hasnt "$T/e81c" "stale answer" "P81c the fresh answer comes from the planned re-plan, never from the stale-mark backstop"
fresh; export JEV_PLACE_PROFILES=decide-a,decide-b PLACE_DEGRADED=decide-a
: > "$STUB_LOG/running.decide-a"
jq -n '{sets:{"decide-a":{constitution_started:true, started_at:1, stopping:null, starting:null, leases:[]}}}' > "$JEV_STATE_DIR/leases.json"
timeout 120 "$PLACE" acquire s1 --pid $$ > "$T/o81b" 2>"$T/e81b"; rc=$?
assert_eqx "0 decide-b 1 1" "$rc $(cat "$T/o81b") $(stops) $(starts)" "P81b CONTROL shape: the degraded lease-less set is disposed, then decide-b placed"
assert_eqx 0 "$(inv_violations)" "P81b after the disposal stop the start is decided on a fresh answer"
hasnt "$T/e81b" "stale answer" "P81b the fresh answer comes from the planned re-plan, never from the stale-mark backstop"
# CONTROL for the property's instrument: a log with two starts and no capacity read between them is a violation
printf 'llmctl capacity --json\nllmctl start x\nllmctl start y\n' > "$STUB_LOG/llmctl.log"
assert_eqx 1 "$(inv_violations)" "P81 CONTROL: the property checker sees a start right after a start"

# ---- P82 (NF-2): the registry changes before every start mark -> bounded, then no start ------------------------------
fresh
gated "$T/gB" 5,11,17,23 0 "$T/b82" JEV_PLACE_PROFILES=decide-a -- acquire sB --pid $$; b82=$GPID
for n in 5 11 17 23; do
  reach "$T/gB" "$n" "P82 B is at start mark $n"
  registry_write "before mark $n"; go "$T/gB" "$n"
done
wait "$b82"; brc=$?
assert_eqx "5 0 undetermined stale_answer" "$brc $(starts) $(pl .placement.event) $(pl .placement.reason_code)" "P82 four stale marks: no start, undetermined (stale_answer)"
assert_eqx 3 "$(grep -c 'planning again on a fresh answer' "$T/b82.err")" "P82 STALE_MAX (3) re-plans, then it stops"

# ---- P82b (NF-2): the registry changes during every capacity read -> bounded, then a plan without a start ------------
fresh
JEV_PLACE_PROFILES=decide-a PLACE_CAP_RC=99 "$PLACE" acquire s0 >/dev/null 2>&1   # the registry exists (gateway only)
gated "$T/gB" 3,7,11 0 "$T/b82b" JEV_PLACE_PROFILES=decide-a -- acquire sB --pid $$; b82b=$GPID
for n in 3 7 11; do
  reach "$T/gB" "$n" "P82b B is at plan $n"
  registry_write "during read $n"; go "$T/gB" "$n"
done
wait "$b82b"; brc=$?
assert_eqx "5 0 stale_answer" "$brc $(starts) $(pl .placement.reason_code)" "P82b three stale reads: a plan with joins only, no start (stale_answer)"
has "$T/b82b.err" "planning joins only" "P82b the joins-only plan is announced"

# ---- P83 (mutant row): a plan that changes nothing writes nothing ----------------------------------------------------
fresh; mkdir -p "$T/capB"
gated "$T/gB" 5 0 "$T/b83" JEV_PLACE_PROFILES=decide-a PLACE_CAP_GATE="$T/capB" PLACE_CAP_GATE_AT=999 -- acquire sB --pid $$; b83=$GPID
reach "$T/gB" 5 "P83 B is at its start mark"
gen0="$(L '.gen')"
JEV_PLACE_PROFILES=decide-a PLACE_CAP_RC=99 "$PLACE" acquire sC >/dev/null 2>&1; crc=$?
assert_eqx "5 $gen0" "$crc $(L '.gen')" "P83 C's acquire on an undetermined answer wrote nothing to the registry"
go "$T/gB" 5; wait "$b83"; brc=$?
assert_eqx "0 decide-a 2" "$brc $(cat "$T/b83.out") $(cat "$T/capB/count")" "P83 B starts on its answer (one read before the plan, one after the start: no re-read)"

# ---- P84 (N6-b): status with no placement record yet ----------------------------------------------------------------
fresh
"$PLACE" status > "$T/o84" 2>"$T/e84"; rc=$?
assert_eqx 0 "$rc" "P84 status exits 0 when no placement has been recorded yet"
has "$T/o84" "placement: none recorded yet" "P84 it says so"

# ---- P85 (N6-e): the reason of an undetermined candidate is in the record -------------------------------------------
fresh
jq '.host.nproc = {rlimit_soft:null, rlimit_hard:null, user_threads:400, headroom:null}' "$T/cap.json" > "$T/cap85.json" && mv -f -- "$T/cap85.json" "$T/cap.json"
JEV_PLACE_PROFILES=decide-a "$PLACE" acquire s1 >/dev/null 2>&1; rc=$?
assert_eqx "5 undetermined" "$rc $(pl .placement.verdict)" "P85 an unlimited RLIMIT_NPROC: undetermined, no start"
if pl .placement.reason | grep -q 'nproc_unlimited'; then ok "P85 the record names the candidate's reason (nproc_unlimited)"; else fail "P85 the record does not name the reason: $(pl .placement.reason)"; fi

# ---- P86 (mutant row): an owed stop that fails again is tried once per acquire --------------------------------------
fresh; export JEV_PLACE_PROFILES=decide-a PLACE_STOP_RC=1
: > "$STUB_LOG/running.decide-a"
jq -n '{sets:{"decide-a":{constitution_started:true, started_at:1, stopping:null, starting:null, leases:[], start_failed:{at:1, rc:1}}}}' > "$JEV_STATE_DIR/leases.json"
timeout 120 "$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e86"; rc=$?
assert_eqx "5 1" "$rc $(stops)" "P86 the owed stop fails: tried once by this acquire, which ends (rc 5)"
assert_eqx "true" "$(L '.sets["decide-a"].stop_failed != null')" "P86 the set is kept with its failed stop (retried by the next acquire or release)"

# ---- P87 (OM03, mutant row): a stopping set seen only by the mark on the further-start path --------------------------
fresh
gated "$T/gA" 9 0 "$T/a87" JEV_PLACE_PROFILES=decide-a,decide-b JEV_PLACE_MAX=2 -- acquire sA --pid $$; a87=$GPID
reach "$T/gA" 9 "P87 A started decide-a; the ticket of its fresh read for decide-b waits"
pst87="$(proc_start_of $$)"
( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock -w 10 8 || exit 4
  jq -c --argjson now "$JEV_NOW_EPOCH" --argjson pid "$$" --argjson pst "${pst87:-null}" \
    '.gen = ((.gen // 0) + 1) | .sets["decide-c"] = {constitution_started:true, started_at:1, starting:null, leases:[], stopping:{at:$now, pid:$pid, pid_start:$pst}}' \
    "$JEV_STATE_DIR/leases.json" > "$JEV_STATE_DIR/leases.json.w" && mv -f -- "$JEV_STATE_DIR/leases.json.w" "$JEV_STATE_DIR/leases.json" )
assert_eqx true "$(L '.sets["decide-c"].stopping != null')" "P87 another set is stopping (a live stopper) before A's ticket"
go "$T/gA" 9; wait "$a87"; arc=$?
assert_eqx "0 decide-a 0" "$arc $(cat "$T/a87.out") $(startsof decide-b)" "P87 decide-b is not started while decide-c is stopping"
has "$T/a87.err" "candidate decide-b: not started (not fitting on the fresh answer, a set exists, or a set is starting/stopping)" "P87 the refusal is announced"

# ---- P88 (NF-2): a release of the holder during its acquire ends the further starts ---------------------------------
fresh
gated "$T/gA" 9 0 "$T/a88" JEV_PLACE_PROFILES=decide-a,decide-b JEV_PLACE_MAX=2 -- acquire sA --pid $$; a88=$GPID
reach "$T/gA" 9 "P88 A started decide-a; the ticket of its fresh read for decide-b waits"
"$PLACE" release sA >/dev/null 2>"$T/r88.err"; rrc=$?
assert_eqx "0 1 " "$rrc $(stops) $(running)" "P88 the release of sA (its only lease) stopped decide-a"
go "$T/gA" 9; wait "$a88"; arc=$?
assert_eqx "0 0" "$(startsof decide-b) $(L '[.sets[]?.leases[]? | select(.holder == "sA")] | length')" "P88 decide-b is never started for the released sA; sA holds no lease"
has "$T/a88.err" "the lease of sA on decide-a, taken by this acquire, is gone" "P88 the reason is announced"
# CONTROL: the same schedule without the release starts decide-b on the fresh answer
fresh
gated "$T/gA" 9 0 "$T/c88" JEV_PLACE_PROFILES=decide-a,decide-b JEV_PLACE_MAX=2 -- acquire sA --pid $$; c88=$GPID
reach "$T/gA" 9 "P88 CONTROL: A waits at the same ticket"
go "$T/gA" 9; wait "$c88"
assert_eqx 1 "$(startsof decide-b)" "P88 CONTROL: without the release decide-b is started"

count_lockheld
assert_eqx 0 "$LOCKHELD_TOTAL" "P67 no llmctl call ran while the lease lock was held (across this file)"
finish
