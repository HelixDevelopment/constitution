#!/usr/bin/env bash
# test_s4_round6.sh — round 6 (2026-11-13) of the S4 placement producer scripts/jev/jev-place.sh (§11.4.291), review of
# 5a9e72be (docs/qa/jev_s3s4_20261112/round6/). GATE-LOGIC tests (§11.4.289(C)(2)): the stub llmctl in
# tests/jev/fixtures/bin-place answers from a declared file; these prove the producer DECIDES correctly, never that a
# local model runs. Every row was written RED-first against the round-5 head (evidence: round6/red_*.txt).
#   P51 (R5-1)  the record step of a successful start cannot take the lock: bounded retry, then "lease held, start recorded
#               late"; NEVER a second start; a retry that gets the lock records the start normally
#               (P51c: the review's repro shape, a lock held just past one record wait)
#   P52 (R5-2a) reap: the endpoint cache never names a set whose leases were reaped
#   P53 (R5-2b) a held set that turns degraded leaves the cache at the next heartbeat / status / verdict / reap; the lease is
#               kept (the session drains and releases); it returns when the unit reads ok again
#   P54 (R5-14) gateway: https-only; the failure default is https and is logged; an http:// registry URL or
#               LLMCTL_GATEWAY_URL is refused (rc 5, gateway_refused, no start, no cache entry)
#   P55 (R5-2)  PROPERTY TABLE: every subcommand x every state transition; after each cell the cache holds an llmctl-local
#               entry iff the lease registry holds a lease set whose unit the stub reports ok (independent oracle: the stub's
#               own answer, not the producer's health field); with control needles for the oracle itself
#   P56 (R5-4)  TTL must exceed the re-evaluation cadence + the llmctl timeout: --ttl 1, JEV_LEASE_TTL=0 and ttl = cadence +
#               timeout are refused (rc 2, no start); ttl above the sum is accepted
#   P57 (R5-5)  heartbeat of a holder with no lease exits 3 (never held, reaped)
#   P58 (R5-6)  canon reasons: a stopping set -> reason_code endpoint_stopping; a held set whose unit is gone -> event
#               endpoint_gone, every lease released, a non-empty detail, nothing restarted by the heartbeat
#   P59 (R5-7)  an unreadable candidate list (llmctl decide capacity fails) -> undetermined, never does_not_fit
#   P60 (R5-8)  placement record: previous verdict, this holder's lease, override id; lease objects carry the project and
#               started_by_this_session; merged into jev-detection.json when it exists, never fabricated when it does not
#   P61 (R5-13) an unlimited RLIMIT_NPROC (rlimit_soft null, measured) is a distinct reason from an unmeasured headroom
#   P62 (R5-12) wiring matcher: bash -s, bash -c --, env -S
#   P63 (R5-3)  a placement record that cannot take the lock is logged as NOT written; nothing is written unlocked
#   P64 (R5-1)  JEV_PLACE_MAX=2: the second start is judged on a fresh answer read after the first model is resident
#   P65 (R5-1)  a failed start whose cleanup stop also failed ends the loop: no further candidate is started
#   P66 (N5-2)  stub: under host pressure a non-running profile is does_not_fit (ground truth lib/capacity.sh)
#   P67 (R4-3)  no llmctl call under the lease lock across this file (stub LOCKHELD record)
#   P68 (R5-2)  observation order: a slow, older capacity answer never overwrites a newer recorded health
#   P69 (R5-2)  start floor: a capacity answer read before a start never marks the started set gone
#   P70 (R5-1)  the start mark is refused while ANY set is stopping, also one marked after this acquire planned
#   P71 (R5-1)  a failed fresh answer ends the start loop: the next candidate is never judged on the stale answer
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; FIXTURES="$HERE/fixtures"
# shellcheck source=lib_assert.sh
. "$HERE/lib_assert.sh"
PLACE="${S4_PLACE_UNDER_TEST:-$ROOT/scripts/jev/jev-place.sh}"
LIBD="${S4_LIBD_UNDER_TEST:-$ROOT/scripts/jev/lib_decide.sh}"
STUB="$FIXTURES/bin-place/llmctl"

assert_eqx() { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (expected [$1] got [$2])"; fi; }
has()  { if grep -q -- "$2" "$1" 2>/dev/null; then ok "$3"; else fail "$3 (no [$2] in $1)"; fi; }
hasnt(){ if grep -q -- "$2" "$1" 2>/dev/null; then fail "$3 (found [$2] in $1)"; else ok "$3"; fi; }

cap() { # cap <file> [a-verdict] [b-verdict] [headroom|none] [pressure-ok]
  jq -n --arg va "${2:-fits}" --arg vb "${3:-fits}" --arg hr "${4:-5000}" --arg pok "${5:-true}" '
    {schema:"llmctl.capacity/1", time:1700000000, measurement:{ok:true},
     host:({mem_total_mb:20000, mem_available_mb:18000, usable_mem_mb:15000, load:{}}
           + (if $hr=="none" then {} else {nproc:{rlimit_soft:123694, rlimit_hard:123694, user_threads:400, headroom:($hr|tonumber)}} end)),
     reserve:{mem_reserved_mb:4000, cpus_reserved:4}, pressure:{ok:($pok=="true"), reasons:(if $pok=="true" then [] else ["psi full avg10 3.1 > 2"] end)},
     llmctl:{units:[]}, fallback:{recommended:"cloud", key_variable:null}, unknown_profiles:[],
     profiles:{"decide-a":{verdict:$va, verdict_class:$va, running:false, threads:(if $va=="does_not_fit" then 0 else 3 end), reasons:[]},
               "decide-b":{verdict:$vb, verdict_class:$vb, running:false, threads:(if $vb=="does_not_fit" then 0 else 3 end), reasons:[]},
               "decide-x":{verdict:"fits", verdict_class:"fits", running:false, threads:3, reasons:[]}}}' > "$1"
}
LOCKHELD_TOTAL=0
count_lockheld() { local n=0; [ -n "${STUB_LOG:-}" ] && [ -f "$STUB_LOG/llmctl.log" ] && n="$(grep -c '^LOCKHELD' "$STUB_LOG/llmctl.log" || true)"; LOCKHELD_TOTAL=$((LOCKHELD_TOTAL + ${n:-0})); }
fresh() {
  count_lockheld
  make_fixture_env s4r6
  export PATH="$FIXTURES/bin-place:$PATH" JEV_TEST=1 PLACE_CAP_JSON="$T/cap.json" JEV_LOCK_TIMEOUT=2
  unset PLACE_CAP_RC PLACE_CAP_RC_FILE PLACE_CAP_SLEEP PLACE_CAP_RAW PLACE_START_RC PLACE_START_SLEEP PLACE_STOP_RC PLACE_STOP_SLEEP PLACE_DEGRADED \
        PLACE_GONE PLACE_FULL_AFTER PLACE_DCAP_RC PLACE_STATUS_RC PLACE_STATUS_URL PLACE_STATUS_NOGW JEV_LLMCTL_TIMEOUT \
        JEV_LLMCTL_START_TIMEOUT JEV_PLACE_MAX JEV_PLACE_PROFILES LLMCTL_GATEWAY_URL LLMCTL_CACERT LLMCTL_TENANT_ID \
        JEV_LEASE_TTL JEV_REEVAL_CADENCE JEV_RECORD_RETRIES JEV_PROJECT
  : > "$STUB_LOG/llmctl.log"
  CACHE="$CMA_PROVIDERS_DIR/jev-endpoints.json"
  cap "$T/cap.json"
}
starts() { grep -c '^llmctl start' "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
stops()  { grep -c '^llmctl stop' "$STUB_LOG/llmctl.log" 2>/dev/null || true; }
pl() { jq -r "$1" "$JEV_STATE_DIR/placement.json" 2>/dev/null; }
L() { jq -r "$1" "$JEV_STATE_DIR/leases.json" 2>/dev/null; }
cachen() { jq '[.endpoints[]? | select(.provider_id=="llmctl-local")] | length' "$CACHE" 2>/dev/null || echo 0; }
cachem() { jq -r '[.endpoints[]? | select(.provider_id=="llmctl-local") | .model] | join(",")' "$CACHE" 2>/dev/null || true; }
running() { (cd "$STUB_LOG" && for f in running.*; do [ -e "$f" ] && printf '%s ' "${f#running.}"; done); }
orphan_a() { local dead; dead="$(bash -c 'echo $$')"; "$PLACE" acquire ghost --pid "$dead" >/dev/null 2>&1; }
wait_for_start() { local i; for i in $(seq 1 100); do grep -q '^llmctl start' "$STUB_LOG/llmctl.log" 2>/dev/null && return 0; sleep 0.1; done; return 1; }

# ---- the independent oracle of P55 ---------------------------------------------------------------------------------
# expected_routable -> the profiles (sorted, comma list) the cache may name: a set in leases.json with >= 1 lease, no
# starting / stopping mark, no start_failed / stop_owed, AND whose own unit the STUB (run here, in the same environment)
# reports with status ok, AND a stub capacity answer that is an answer (exit 0/3/75). The producer's own health field is
# NOT read: the oracle checks that every subcommand really observed the current answer.
expected_routable() {
  local capout crc=0 held
  capout="$("$STUB" capacity --json 2>/dev/null)" || crc=$?
  case "$crc" in 0|3|75) ;; *) echo ""; return 0 ;; esac
  jq -e . >/dev/null 2>&1 <<<"$capout" || { echo ""; return 0; }
  held="$(jq -r '[.sets // {} | to_entries[] | select(((.value.leases // []) | length) > 0 and (.value.starting // null) == null
                  and (.value.stopping // null) == null and (.value.start_failed // null) == null and (.value.stop_owed // null) == null) | .key] | join(",")' \
          "$JEV_STATE_DIR/leases.json" 2>/dev/null)"
  jq -r --arg held "$held" '[.llmctl.units[]? | select((.owner // "self") == "self" and .status == "ok") | .profile
         | select(. as $u | ($held | split(",")) | index($u))] | unique | join(",")' <<<"$capout"
}
# inv_eval -> prints "<OK|BAD> <detail>", rc 0 when the cache holds exactly one llmctl-local entry iff expected_routable is
# non-empty, and its model is one of them. check_invariant <label> records it as a test row.
inv_eval() {
  local exp n m
  exp="$(expected_routable)"; n="$(cachen)"; m="$(cachem)"
  if [ -z "$exp" ]; then
    if [ "$n" = 0 ]; then echo "OK no routable set and no llmctl-local entry"; return 0; fi
    echo "BAD no routable set but the cache names [$m] ($n entries)"; return 1
  fi
  if [ "$n" = 1 ] && printf ',%s,' "$exp" | grep -q ",$m,"; then echo "OK cache names $m, routable {$exp}"; return 0; fi
  echo "BAD routable {$exp} but the cache has $n llmctl-local entries [$m]"; return 1
}
check_invariant() { local r; r="$(inv_eval)"; case "$r" in OK*) ok "$1: ${r#OK }" ;; *) fail "$1: ${r#BAD }" ;; esac; }

# ---- P51 (R5-1): a lock timeout on the record step of a successful start --------------------------------------------
fresh; export PLACE_START_SLEEP=3 JEV_RECORD_RETRIES=2
( "$PLACE" acquire s1 --pid $$ > "$T/a51.out" 2>"$T/a51.err"; echo "$?" > "$T/a51.rc" ) & ap=$!
wait_for_start || fail "P51 setup: no llmctl start seen"
( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock 8; sleep 9 ) & lp=$!
wait "$ap"; wait "$lp" 2>/dev/null; unset PLACE_START_SLEEP
# the announced outcome on stderr: the loop ends at the late record; decide-b is never considered (own mutant OM02:
# `break` -> `continue` reads a fresh answer for decide-b and then fails to mark it). The post-loop observation of the
# started model is a legitimate capacity read, so the stub call count is not the oracle here.
hasnt "$T/a51.err" "candidate decide-b" "P51 no further candidate is considered after the late-recorded start"
hasnt "$T/a51.err" "reading a fresh capacity answer" "P51 no fresh answer is read for a next candidate"
assert_eqx 1 "$(starts)" "P51 exactly one llmctl start when the record step cannot take the lock (never a second candidate)"
assert_eqx "decide-a " "$(running)" "P51 only decide-a runs"
assert_eqx "0 decide-a" "$(cat "$T/a51.rc") $(cat "$T/a51.out")" "P51 rc 0 and the profile: the lease IS held (it is in the registry since the mark)"
has "$T/a51.err" "start recorded late" "P51 the outcome is announced: lease held, start recorded late"
assert_eqx s1 "$(L '.sets["decide-a"].leases[0].holder')" "P51 the registry holds s1's lease on decide-a"
"$PLACE" release s1 >/dev/null 2>"$T/r51.err"; rc=$?
assert_eqx "0 1 " "$rc $(stops) $(running)" "P51 release stops the late-recorded model (nothing orphaned)"
fresh; export PLACE_START_SLEEP=3 JEV_RECORD_RETRIES=3
( "$PLACE" acquire s1 --pid $$ > "$T/b51.out" 2>"$T/b51.err"; echo "$?" > "$T/b51.rc" ) & ap=$!
wait_for_start || fail "P51b setup: no llmctl start seen"
( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock 8; sleep 4 ) & lp=$!
wait "$ap"; wait "$lp" 2>/dev/null; unset PLACE_START_SLEEP
assert_eqx "0 decide-a 1" "$(cat "$T/b51.rc") $(cat "$T/b51.out") $(starts)" "P51b a retried record step that gets the lock records the start"
assert_eqx "null placed" "$(L '.sets["decide-a"].starting') $(pl .placement.event)" "P51b the starting mark is cleared and the placement recorded"
hasnt "$T/b51.err" "recorded late" "P51b not reported late when a retry succeeded"

# P51c: the review's repro shape (repro3.sh): the lock is held a little longer than ONE record wait, so the next
# candidate's mark could take it; the round-5 producer then started decide-b too
fresh; export PLACE_START_SLEEP=3 JEV_RECORD_RETRIES=1
( "$PLACE" acquire s1 --pid $$ > "$T/c51.out" 2>"$T/c51.err"; echo "$?" > "$T/c51.rc" ) & ap=$!
wait_for_start || fail "P51c setup: no llmctl start seen"
( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock 8; sleep 5.5 ) & lp=$!
wait "$ap"; wait "$lp" 2>/dev/null; unset PLACE_START_SLEEP
has "$T/c51.err" "start recorded late" "P51c control needle: the stderr is captured and the late record is announced"
hasnt "$T/c51.err" "candidate decide-b" "P51c the loop ended at the late record: decide-b is never considered"
assert_eqx "1 decide-a " "$(starts) $(running)" "P51c the next candidate is never started after a start succeeded (review repro shape)"
assert_eqx "0 decide-a" "$(cat "$T/c51.rc") $(cat "$T/c51.out")" "P51c rc 0, lease held on decide-a"
"$PLACE" release s1 >/dev/null 2>&1; assert_eqx "" "$(running)" "P51c release leaves nothing running"
# P51d: the same shape with JEV_PLACE_MAX=2, where the loop COULD go on to decide-b: it must not. With the default
# JEV_PLACE_MAX=1 the loop ends at the max check anyway, so own mutant OM02 (`break` -> `continue` after the late record)
# is only observable here.
fresh; export PLACE_START_SLEEP=3 JEV_RECORD_RETRIES=1 JEV_PLACE_MAX=2
( "$PLACE" acquire s1 --pid $$ > "$T/d51.out" 2>"$T/d51.err"; echo "$?" > "$T/d51.rc" ) & ap=$!
wait_for_start || fail "P51d setup: no llmctl start seen"
( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock 8; sleep 5.5 ) & lp=$!
wait "$ap"; wait "$lp" 2>/dev/null; unset PLACE_START_SLEEP JEV_PLACE_MAX
has "$T/d51.err" "start recorded late" "P51d control needle: the late record is announced"
hasnt "$T/d51.err" "candidate decide-b" "P51d JEV_PLACE_MAX=2: after the late-recorded start decide-b is never considered"
assert_eqx "0 decide-a 1" "$(cat "$T/d51.rc") $(cat "$T/d51.out") $(starts)" "P51d rc 0, lease on decide-a, exactly one start"
"$PLACE" release s1 >/dev/null 2>&1

# ---- P52 (R5-2a): reap ------------------------------------------------------------------------------------------------
fresh; orphan_a
assert_eqx "1 1" "$(L '.sets["decide-a"].leases|length') $(cachen)" "P52 setup: one (dead) lease and one cache entry"
"$PLACE" reap 2>"$T/e52"; rc=$?
assert_eqx "0 0 0 0" "$rc $(L '.sets["decide-a"].leases|length') $(cachen) $(stops)" "P52 reap: lease dropped, cache entry removed, no stop"
assert_eqx none "$("$PLACE" status --json 2>/dev/null | jq -r '.route')" "P52 status reports the fallback route (none: no hosted key)"

# ---- P53 (R5-2b): a held set that turns degraded --------------------------------------------------------------------
fresh; "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
assert_eqx "1 decide-a" "$(cachen) $(cachem)" "P53 setup: placed and routed"
export PLACE_DEGRADED=decide-a
"$PLACE" heartbeat s1 2>"$T/e53"; rc=$?
assert_eqx "0 0 1" "$rc $(cachen) $(L '.sets["decide-a"].leases|length')" "P53 heartbeat: entry removed, the lease kept (the session drains, then releases)"
assert_eqx degraded "$(L '.sets["decide-a"].health.state')" "P53 the observation is recorded on the set"
has "$T/e53" "route" "P53 the route change is announced"
assert_eqx 1 "$(starts)" "P53 heartbeat starts nothing (the one start is the setup)"
for sub in status verdict reap; do "$PLACE" "$sub" >/dev/null 2>&1; assert_eqx 0 "$(cachen)" "P53 after $sub: still no entry for the degraded unit"; done
unset PLACE_DEGRADED; "$PLACE" heartbeat s1 2>/dev/null
assert_eqx "1 decide-a" "$(cachen) $(cachem)" "P53 the unit reads ok again: routed again at the next observation"

# ---- P54 (R5-14): https-only gateway -----------------------------------------------------------------------------------
fresh; export PLACE_STATUS_RC=1
out="$("$PLACE" acquire s1 --pid $$ 2>"$T/e54")"; rc=$?
assert_eqx "0 decide-a" "$rc $out" "P54 decide status fails: placement still proceeds"
assert_eqx https://127.0.0.1:8095 "$(jq -r '.endpoints[] | select(.provider_id=="llmctl-local") | .base_url' "$CACHE")" "P54 the failure default is https://127.0.0.1:8095 (RM13)"
has "$T/e54" "default" "P54 applying the default is logged"
fresh; export PLACE_STATUS_NOGW=1
"$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e54b"
assert_eqx https://127.0.0.1:8095 "$(jq -r '.endpoints[] | select(.provider_id=="llmctl-local") | .base_url' "$CACHE")" "P54 no gateway in the registry: the https default"
has "$T/e54b" "default" "P54 the no-gateway default is logged"
fresh; export PLACE_STATUS_URL=http://127.0.0.1:18095
"$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e54c"; rc=$?
assert_eqx "5 0 0 gateway_refused" "$rc $(starts) $(cachen) $(pl .placement.event)" "P54 an http:// registry URL is refused: no start, no entry"
has "$T/e54c" "https" "P54 the refusal names the https rule"
fresh; export LLMCTL_GATEWAY_URL=http://127.0.0.1:9999
"$PLACE" acquire s1 --pid $$ >/dev/null 2>/dev/null; rc=$?
assert_eqx "5 0 0" "$rc $(starts) $(cachen)" "P54 an http:// LLMCTL_GATEWAY_URL is refused"
fresh; "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1; export PLACE_STATUS_URL=http://127.0.0.1:18095
"$PLACE" acquire s2 --pid $$ >/dev/null 2>/dev/null; rc=$?
assert_eqx "5 0" "$rc $(cachen)" "P54 a later http:// registry URL removes the existing local entry (the key never goes over http)"
fresh; export LLMCTL_GATEWAY_URL=https://127.0.0.1:9443
"$PLACE" acquire s1 --pid $$ >/dev/null 2>/dev/null; rc=$?
assert_eqx "0 https://127.0.0.1:9443" "$rc $(jq -r '.endpoints[] | select(.provider_id=="llmctl-local") | .base_url' "$CACHE")" "P54 CONTROL: an https override is used"

# ---- P55 (R5-2): property table over every subcommand x every transition ---------------------------------------------
# oracle self-test (control needles): the checker must see a present entry and must flag a wrong one
fresh; "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
check_invariant "P55 needle+ (the checker sees a correct entry)"
cp "$CACHE" "$T/cache.good"
jq '.endpoints |= map(if .provider_id=="llmctl-local" then .model="decide-b" else . end)' "$T/cache.good" > "$CACHE"
if inv_eval >/dev/null; then fail "P55 needle- the checker accepted an entry naming an unheld set"; else ok "P55 needle- the checker flags an entry naming an unheld set"; fi
jq '.endpoints |= map(select(.provider_id!="llmctl-local"))' "$T/cache.good" > "$CACHE"
if inv_eval >/dev/null; then fail "P55 needle- the checker accepted a missing entry"; else ok "P55 needle- the checker flags a missing entry"; fi
cp "$T/cache.good" "$CACHE"
transition() { # transition <name>: the state change between the setup acquire and the subcommand
  case "$1" in
    none) ;;
    degraded) export PLACE_DEGRADED=decide-a ;;
    gone) export PLACE_GONE=decide-a ;;
    pressure) cap "$T/cap.json" fits fits 5000 false ;;
    capfail) export PLACE_CAP_RC=1 PLACE_CAP_RAW=1; printf 'not json\n' > "$T/cap.json" ;;
    dead) ;;   # the setup itself used a holder pid that has exited
    recover) export PLACE_DEGRADED=decide-a; "$PLACE" heartbeat s1 >/dev/null 2>&1; unset PLACE_DEGRADED ;;
  esac
}
for tr in none degraded gone pressure capfail dead recover; do
  for sub in acquire heartbeat release reap status verdict; do
    fresh
    if [ "$tr" = dead ]; then orphan_a; h=ghost; else "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1; h=s1; fi
    s0="$(starts)"; t0="$(stops)"
    transition "$tr"
    rc=0
    case "$sub" in
      acquire)   "$PLACE" acquire s2 --pid $$ >/dev/null 2>"$T/cell.err" || rc=$? ;;
      heartbeat) "$PLACE" heartbeat "$h" >/dev/null 2>"$T/cell.err" || rc=$? ;;
      release)   "$PLACE" release nobody >/dev/null 2>"$T/cell.err" || rc=$? ;;
      *)         "$PLACE" "$sub" >/dev/null 2>"$T/cell.err" || rc=$? ;;
    esac
    check_invariant "P55 [$tr x $sub] rc=$rc"
    case "$sub" in acquire|release) ;; *)
      assert_eqx "$s0 $t0" "$(starts) $(stops)" "P55 [$tr x $sub] no llmctl start or stop" ;; esac
  done
done

# ---- P56 (R5-4): TTL ----------------------------------------------------------------------------------------------------
fresh; "$PLACE" acquire s1 --ttl 1 >/dev/null 2>"$T/e56"; rc=$?
assert_eqx "2 0" "$rc $(starts)" "P56 --ttl 1 is a config error: refused, no start"
has "$T/e56" "cadence" "P56 the refusal names the cadence rule"
fresh; JEV_LEASE_TTL=0 "$PLACE" acquire s1 >/dev/null 2>/dev/null; rc=$?
assert_eqx "2 0" "$rc $(starts)" "P56 JEV_LEASE_TTL=0 refused"
fresh; "$PLACE" acquire s1 --ttl 320 >/dev/null 2>/dev/null; rc=$?
assert_eqx "2 0" "$rc $(starts)" "P56 ttl = cadence 300 + llmctl timeout 20 is not greater: refused"
fresh; "$PLACE" acquire s1 --ttl 321 >/dev/null 2>/dev/null; rc=$?
assert_eqx "0 1" "$rc $(starts)" "P56 CONTROL: ttl 321 > 300 + 20 accepted"
fresh; JEV_REEVAL_CADENCE=10 "$PLACE" acquire s1 --ttl 100 >/dev/null 2>/dev/null; rc=$?
assert_eqx "0 100" "$rc $(L '.sets["decide-a"].leases[0].ttl')" "P56 CONTROL: a declared cadence 10 s admits ttl 100"
fresh; JEV_REEVAL_CADENCE=x "$PLACE" status >/dev/null 2>/dev/null; rc=$?
assert_eqx 2 "$rc" "P56 a non-numeric cadence is a config error"

# ---- P57 (R5-5): heartbeat without a lease ------------------------------------------------------------------------------
fresh; "$PLACE" heartbeat nobody 2>"$T/e57"; rc=$?
assert_eqx 3 "$rc" "P57 heartbeat of a holder that never held a lease exits 3"
has "$T/e57" "no lease" "P57 the session is told it holds no lease"
fresh; orphan_a; "$PLACE" heartbeat ghost 2>/dev/null; rc=$?
assert_eqx 3 "$rc" "P57 heartbeat of a reaped holder exits 3"
fresh; "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1; "$PLACE" heartbeat s1 2>/dev/null; rc=$?
assert_eqx 0 "$rc" "P57 CONTROL: heartbeat of a live lease exits 0"

# ---- P58 (R5-6): canon reasons ------------------------------------------------------------------------------------------
fresh
echo '{"sets":{"decide-a":{"constitution_started":true,"started_at":1700000000,"stopping":{"at":1700000000,"pid":1},"leases":[]}}}' > "$JEV_STATE_DIR/leases.json"
"$PLACE" acquire s1 >/dev/null 2>/dev/null; rc=$?
assert_eqx "5 refused_stopping endpoint_stopping" "$rc $(pl .placement.event) $(pl .placement.reason_code)" "P58 a stopping set: reason_code endpoint_stopping"
case "$(pl .placement.reason)" in endpoint_stopping*) ok "P58 the reason starts with endpoint_stopping" ;; *) fail "P58 reason [$(pl .placement.reason)]" ;; esac
fresh; "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1; "$PLACE" acquire s2 --pid $$ >/dev/null 2>&1
export PLACE_GONE=decide-a; s0="$(starts)"
"$PLACE" heartbeat s1 >/dev/null 2>"$T/e58"; rc=$?
assert_eqx "3 endpoint_gone endpoint_gone" "$rc $(pl .placement.event) $(pl .placement.reason_code)" "P58 unit gone: endpoint_gone recorded; the heartbeat tells s1 it holds no lease (rc 3)"
assert_eqx "0 0" "$(L '[.sets[]?.leases[]?] | length') $(cachen)" "P58 every lease of the gone endpoint released, no cache entry"
assert_eqx "$s0" "$(starts)" "P58 nothing restarted"
detail="$(pl .placement.reason)"; case "$detail" in *": "|"") fail "P58 the detail is empty [$detail]" ;; *) ok "P58 the detail is filled [$detail]" ;; esac
has "$T/e58" "endpoint_gone" "P58 the notice names endpoint_gone"

# ---- P59 (R5-7): candidate list unreadable -----------------------------------------------------------------------------
fresh; export PLACE_DCAP_RC=1
"$PLACE" acquire s1 >/dev/null 2>/dev/null; rc=$?
assert_eqx "5 0 undetermined undetermined" "$rc $(starts) $(pl .placement.verdict) $(pl .placement.event)" "P59 decide capacity fails: undetermined, not does_not_fit"
case "$(pl .placement.reason)" in *"candidate list undetermined"*) ok "P59 the reason names the candidate list" ;; *) fail "P59 reason [$(pl .placement.reason)]" ;; esac
assert_eqx undetermined "$("$PLACE" verdict --json 2>/dev/null | jq -r '.candidates_contract')" "P59 verdict --json reports the candidate list as undetermined"

# ---- P60 (R5-8): record fields -----------------------------------------------------------------------------------------
fresh; export JEV_PROJECT=proj6
"$PLACE" acquire s1 --pid $$ >/dev/null 2>&1
assert_eqx "proj6 true" "$(L '.sets["decide-a"].leases[0].project') $(L '.sets["decide-a"].leases[0].started_by_this_session')" "P60 a starting lease: project, started_by_this_session true"
assert_eqx "s1 true" "$(pl .placement.lease.holder) $(pl .placement.lease.held)" "P60 the record names this holder's lease"
assert_eqx "true null" "$(pl '.placement | has("override_id")') $(pl .placement.override_id)" "P60 override_id present (null: no override path)"
"$PLACE" acquire s2 --pid $$ >/dev/null 2>&1
assert_eqx "false" "$(L '.sets["decide-a"].leases[] | select(.holder=="s2") | .started_by_this_session')" "P60 a joining lease: started_by_this_session false"
assert_eqx "placed" "$(pl .placement.previous.event)" "P60 the record keeps the previous event (placed)"
assert_eqx "true" "$(pl '.placement.previous | has("verdict")')" "P60 the record keeps the previous verdict"
assert_eqx "false" "$(pl .placement.detection_merged)" "P60 no detection record: not merged"
[ ! -e "$JEV_EVIDENCE_DIR/jev-detection.json" ] && ok "P60 no detection record is fabricated" || fail "P60 a detection record was created"
echo '{"endpoints":[],"reason":"fixture"}' > "$JEV_EVIDENCE_DIR/jev-detection.json"
"$PLACE" acquire s3 --pid $$ >/dev/null 2>&1
assert_eqx "joined fixture true" "$(jq -r '.placement.event' "$JEV_EVIDENCE_DIR/jev-detection.json") $(jq -r .reason "$JEV_EVIDENCE_DIR/jev-detection.json") $(pl .placement.detection_merged)" "P60 an existing detection record gets the placement entry, its fields kept"

# ---- P61 (R5-13): unlimited RLIMIT_NPROC -------------------------------------------------------------------------------
fresh; jq '.host.nproc = {rlimit_soft:null, rlimit_hard:null, user_threads:400, headroom:null, limit_override:null, source:"rlimit"}' "$T/cap.json" > "$T/c" && mv "$T/c" "$T/cap.json"
"$PLACE" verdict --json 2>/dev/null > "$T/v61"
assert_eqx undetermined "$(jq -r '.candidates[0].verdict' "$T/v61")" "P61 unlimited: still undetermined (operator decision owed)"
# the reason CODE (before the first ':') is the machine field; a substring of the prose is not an oracle (own mutant OM12)
assert_eqx nproc_unlimited "$(jq -r '.candidates[0].reason | split(":")[0]' "$T/v61")" "P61 the reason code is nproc_unlimited (measured: rlimit_soft null)"
fresh; cap "$T/cap.json" fits fits none
assert_eqx nproc_not_measured "$("$PLACE" verdict --json 2>/dev/null | jq -r '.candidates[0].reason | split(":")[0]')" "P61 CONTROL: an absent headroom has the reason code nproc_not_measured"
fresh; jq '.host.nproc = {rlimit_soft:123694, rlimit_hard:123694, user_threads:null, headroom:null}' "$T/cap.json" > "$T/c" && mv "$T/c" "$T/cap.json"
assert_eqx nproc_not_measured "$("$PLACE" verdict --json 2>/dev/null | jq -r '.candidates[0].reason | split(":")[0]')" "P61 an unreadable thread census (user_threads null) has the reason code nproc_not_measured, never nproc_unlimited"

# ---- P62 (R5-12): wiring matcher ---------------------------------------------------------------------------------------
m() { ( set +u; . "$LIBD"; _jev_cmd_runs_gate "$1" 0 ) >/dev/null 2>&1 && echo 0 || echo 1; }
assert_eqx 1 "$(m 'bash -s jev-gate.sh')" "P62 bash -s WORD: WORD is a positional parameter, not wiring"
assert_eqx 1 "$(m 'bash -ns jev-gate.sh')" "P62 bash -ns: not wiring"
assert_eqx 0 "$(m 'bash -c -- jev-gate.sh')" "P62 bash -c -- WORD runs WORD"
assert_eqx 0 "$(m 'bash -c -e jev-gate.sh')" "P62 bash -c -e WORD: options before the command string"
assert_eqx 0 "$(m 'env -S "bash jev-gate.sh"')" "P62 env -S STRING is split"
assert_eqx 0 "$(m 'env --split-string="bash jev-gate.sh"')" "P62 env --split-string= is split"
assert_eqx 1 "$(m 'env -S "echo jev-gate.sh"')" "P62 env -S of another command is not wiring"
assert_eqx 0 "$(m 'bash jev-gate.sh')" "P62 CONTROL: bash WORD is wiring"
assert_eqx 1 "$(m 'bash -n jev-gate.sh')" "P62 CONTROL: bash -n is not wiring"

# ---- P63 (R5-3): placement record under a lock timeout -----------------------------------------------------------------
fresh
( exec 8>>"$JEV_STATE_DIR/placement.lock"; flock 8; sleep 6 ) & lk=$!; sleep 0.5
JEV_LOCK_TIMEOUT=1 JEV_RECORD_RETRIES=2 "$PLACE" acquire s1 >/dev/null 2>"$T/e63"; rc=$?
wait "$lk" 2>/dev/null
assert_eqx "4 0" "$rc $(starts)" "P63 lock held: rc 4, no start"
has "$T/e63" "NOT written" "P63 the lost placement record is logged"
[ ! -e "$JEV_STATE_DIR/placement.json" ] && ok "P63 nothing written without the lock" || fail "P63 placement.json written without the lock"

# ---- P64 (R5-1): JEV_PLACE_MAX=2 re-judges the second start on a fresh answer ------------------------------------------
fresh; export JEV_PLACE_MAX=2 PLACE_FULL_AFTER=decide-a
out="$("$PLACE" acquire s1 --pid $$ 2>"$T/e64")"; rc=$?
assert_eqx "0 decide-a 1" "$rc $out $(starts)" "P64 once decide-a is resident the fresh answer says decide-b does not fit: one start"
has "$T/e64" "fresh" "P64 the re-judgement is logged"
fresh; export JEV_PLACE_MAX=2
"$PLACE" acquire s1 --pid $$ >/dev/null 2>/dev/null
assert_eqx 2 "$(starts)" "P64 CONTROL: with room for both, two starts"

# ---- P65 (R5-1): a failed start with a failed cleanup stop ends the loop -----------------------------------------------
fresh; export PLACE_START_RC=1 PLACE_STOP_RC=1
"$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e65"; rc=$?
assert_eqx "5 1" "$rc $(starts)" "P65 the cleanup stop failed (the model may be resident): no further candidate is started"
fresh; export PLACE_START_RC=1
"$PLACE" acquire s1 --pid $$ >/dev/null 2>/dev/null
assert_eqx 2 "$(starts)" "P65 CONTROL: after a failed start whose cleanup stop succeeded the next candidate is tried"

# ---- P66 (N5-2): stub ground truth --------------------------------------------------------------------------------------
fresh; cap "$T/cap.json" fits fits 5000 false
"$STUB" capacity --json > "$T/c66" 2>/dev/null || true
assert_eqx "does_not_fit 0" "$(jq -r '.profiles["decide-a"] | "\(.verdict) \(.threads)"' "$T/c66")" "P66 under pressure a non-running profile is does_not_fit (threads 0)"

# ---- P68 (R5-2, observation order): an older observation never overwrites a newer one --------------------------------
# A takes its ticket, then reads a SLOW answer that says degraded; B takes a later ticket and reads ok meanwhile. A's
# answer arrives last but is older: it must not replace B's recorded health (else the cache drops a healthy set).
fresh; "$PLACE" acquire s1 --pid $$ >/dev/null 2>&1; "$PLACE" status >/dev/null 2>&1
assert_eqx "ok 1" "$(L '.sets["decide-a"].health.state') $(cachen)" "P68 setup: decide-a observed ok and routed"
( PLACE_DEGRADED=decide-a PLACE_CAP_SLEEP=3 "$PLACE" status >/dev/null 2>"$T/e68a" ) & bg=$!; jev_track_pid "$bg"
sleep 1
"$PLACE" status >/dev/null 2>&1; tb="$(L '.sets["decide-a"].health.seq')"
wait "$bg" 2>/dev/null
assert_eqx "ok $tb 1" "$(L '.sets["decide-a"].health.state') $(L '.sets["decide-a"].health.seq') $(cachen)" "P68 the slow older (degraded) answer did not overwrite the newer ok observation; still routed"
PLACE_DEGRADED=decide-a "$PLACE" status >/dev/null 2>&1
assert_eqx "degraded 0" "$(L '.sets["decide-a"].health.state') $(cachen)" "P68 CONTROL: the same degraded answer, when it is the newest, is recorded and leaves the cache"

# ---- P69 (R5-2, start floor): an answer read before a start never judges the started set ------------------------------
# B acquires (its capacity reads take 6 s each: one before the start, one after). A takes its ticket 2 s after B began,
# BEFORE B's start completes, and its slow answer says decide-a has no unit; it arrives after B recorded the start and
# before B's post-start observation. The start floor makes A's ticket too old for the set: no endpoint_gone, lease kept.
fresh
( PLACE_CAP_SLEEP=6 "$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/e69b" ) & b69=$!; jev_track_pid "$b69"
sleep 2
( PLACE_GONE=decide-a PLACE_CAP_SLEEP=6 "$PLACE" status >/dev/null 2>"$T/e69a" ) & a69=$!; jev_track_pid "$a69"
wait "$b69" 2>/dev/null; wait "$a69" 2>/dev/null
assert_eqx "1 1 1 ok" "$(starts) $(L '(.sets["decide-a"].leases // []) | length') $(cachen) $(L '.sets["decide-a"].health.state')" "P69 the pre-start answer (no unit) did not release the started set: one start, lease kept, routed, health ok"
if grep -q endpoint_gone "$T/e69a" "$T/e69b" 2>/dev/null; then fail "P69 no endpoint_gone was announced for the just-started set"; else ok "P69 no endpoint_gone was announced for the just-started set"; fi
PLACE_GONE=decide-a "$PLACE" status >/dev/null 2>"$T/e69c"
assert_eqx "0 0" "$(L '(.sets["decide-a"].leases // []) | length') $(cachen)" "P69 CONTROL: the same answer read after the start does release the set (endpoint_gone)"
has "$T/e69c" "endpoint_gone" "P69 CONTROL: the post-start answer names endpoint_gone"

# ---- P70 (R5-1, mark_start_locked): a set marked stopping AFTER this acquire planned still refuses its next start --------
# JEV_PLACE_MAX=2: s1 starts decide-a, then reads a fresh answer (slow) before decide-b. While that read runs, another
# process releases s1's lease, so decide-a is marked stopping (slow stop). The plan step (C) cannot see that mark (it was
# taken before); only the check in mark_start_locked can (own mutant OM03 removes it and starts decide-b during the stop).
# The trigger is an event in the stub log (the first capacity call after the start of decide-a), not a fixed delay.
fresh; export JEV_PLACE_MAX=2
( PLACE_CAP_SLEEP=5 "$PLACE" acquire s1 --pid $$ > "$T/a70.out" 2>"$T/a70.err"; echo "$?" > "$T/a70.rc" ) & a70=$!; jev_track_pid "$a70"
seen70=1; for i in $(seq 1 300); do
  if awk '/^llmctl start decide-a/{s=1; next} s && /^llmctl capacity/{f=1} END{exit !f}' "$STUB_LOG/llmctl.log" 2>/dev/null; then seen70=0; break; fi
  sleep 0.1; done
[ "$seen70" = 0 ] && ok "P70 setup: decide-a started and the fresh read for the next candidate began" || fail "P70 setup: no fresh read after the start of decide-a"
( PLACE_STOP_SLEEP=8 "$PLACE" release s1 >/dev/null 2>"$T/r70.err" ) & r70=$!; jev_track_pid "$r70"
wait "$a70" 2>/dev/null; wait "$r70" 2>/dev/null; unset JEV_PLACE_MAX
has "$T/r70.err" "llmctl stop decide-a\|last lease released" "P70 setup: the concurrent release stopped decide-a"
assert_eqx 0 "$(grep -c '^llmctl start decide-b' "$STUB_LOG/llmctl.log" || true)" "P70 decide-b is never started while decide-a is stopping (mark refused)"
has "$T/a70.err" "candidate decide-b: no longer startable" "P70 the refusal is announced"
# CONTROL: the same schedule without the concurrent release starts both (P64 control shape)
fresh; export JEV_PLACE_MAX=2
PLACE_CAP_SLEEP=5 "$PLACE" acquire s1 --pid $$ >/dev/null 2>"$T/c70.err"; unset JEV_PLACE_MAX
assert_eqx 1 "$(grep -c '^llmctl start decide-b' "$STUB_LOG/llmctl.log" || true)" "P70 CONTROL: without the release decide-b is started on the fresh answer"

# ---- P71 (R5-1): the fresh answer for the next candidate fails -> no further start ----------------------------------
# JEV_PLACE_MAX=2; the first read succeeds, the read after the start of decide-a exits 1. capacity_read then leaves the
# PRE-start answer in place (decide-b fits there), so only the break on an undetermined fresh answer stops a start judged
# on a stale answer (own mutant OM16 removes it).
fresh; export JEV_PLACE_MAX=2 PLACE_CAP_RC_FILE="$T/caprc71"
( PLACE_START_SLEEP=3 "$PLACE" acquire s1 --pid $$ > "$T/a71.out" 2>"$T/a71.err"; echo "$?" > "$T/a71.rc" ) & a71=$!; jev_track_pid "$a71"
wait_for_start && ok "P71 setup: decide-a is starting" || fail "P71 setup: no llmctl start seen"
echo 1 > "$T/caprc71"
wait "$a71" 2>/dev/null; unset JEV_PLACE_MAX PLACE_CAP_RC_FILE; rm -f "$T/caprc71"
has "$T/a71.err" "the fresh answer is undetermined" "P71 the failed fresh answer is announced"
assert_eqx "0 decide-a 1 0" "$(cat "$T/a71.rc") $(cat "$T/a71.out") $(starts) $(grep -c '^llmctl start decide-b' "$STUB_LOG/llmctl.log" || true)" "P71 one start (decide-a, rc 0); decide-b is never started on the stale pre-start answer"
# CONTROL: the same schedule with a good fresh answer starts decide-b
fresh; export JEV_PLACE_MAX=2
PLACE_START_SLEEP=3 "$PLACE" acquire s1 --pid $$ >/dev/null 2>/dev/null; unset JEV_PLACE_MAX
assert_eqx 2 "$(starts)" "P71 CONTROL: with a good fresh answer decide-b is started"

count_lockheld
assert_eqx 0 "$LOCKHELD_TOTAL" "P67 no llmctl call ran while the lease lock was held (across this file)"
finish
