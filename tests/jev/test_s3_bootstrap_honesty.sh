#!/usr/bin/env bash
# test_s3_bootstrap_honesty.sh — Jev stream S3 (operator decision 2026-11-12, recorded per §11.4.66):
#   H1  reachable means "answers 2xx" ONLY: HTTP 402 => auth_status_class no_credit, reachable=false, usable=false;
#       429 => rate_limited; 401/403/500/timeout => reachable=false; 200 => reachable=true, usable=true
#   H2  the replayable probe (jev-probe.sh) agrees: exit 0 only on 2xx, exit 1 on 402/401/429
#   H3  CM-JEV-DETECTION: a PROBED unusable endpoint (real key, reachable=false, class no_credit) is not a bluff (PASS,
#       with a note naming it unusable); reachable=false with class 2xx is a contradiction (RED); reachable=true with
#       class no_credit is a contradiction (RED); reachable=null with a real key stays RED
#   H4  exit 5 "detected, not wired": a usable endpoint was detected but no agent is wired; rc 0 with no key
#   H5  default-on wiring: --default-on + a REAL key => consent for wiring is applied (logged loudly), the fixture
#       toolkit wires, rc 0; placeholder key / no key / opt-out marker => NOT engaged (logged), wiring stays pending
#   H6  post_update_hook STEP 4e: a real key present and NO Jev file changed => bootstrap still runs with --default-on;
#       bootstrap rc 5 is a WARNING (never deferred, never an ERROR)
#   (round 2, review 2026-11-12 F1/F7)
#   H7  a change of the endpoint's answer between two runs is NOTICED: 402 -> 200 (credit added) and 200 -> 402 (credit lost)
#       re-run stage 3 and rewrite the record; an unchanged answer is a byte-stable no-change (§11.4.281(C)); one probe per
#       endpoint per run (the stage reuses the pre-key probe); the same holds for the toolkit-cache probe path
#   H8  JEV_WIRING=off (env opt-out) with --default-on and a real key => not engaged, nothing wired, rc 0, NOT wired
#   H9  the key VALUE never appears in the bootstrap output or consent.json of a DEFAULT-ON run (needle scan with a control)
# Keys are DUMMY values assembled from fragments. These are GATE-LOGIC tests (stub curl, fixture toolkit; §11.4.289(C)(2)):
# they prove the decisions, never that a real endpoint works (the live run is docs/qa/jev_s3s4_20261112/).
set -uo pipefail
export HELIX_TEST_MODE=1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq curl git; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done
GATES="$REPO/scripts/gates"
ORIG_PATH="$PATH"

mkkey() { printf '%s-%s-%s' "dummyk$1" "Q1w2E3r4" "T5y6U7i8O9p0"; }
KEY_A="$(mkkey a)"

setup() { # setup <name> [with-submodules]
  make_fixture_env "$1"
  if [ "${2:-}" = "with-submodules" ]; then make_fixture_constitution_root with-submodules; else make_fixture_constitution_root; fi
  mkdir -p "$T/constitution/scripts"; ln -s "$GATES" "$T/constitution/scripts/gates"
  export PATH="$FIXTURES/bin-hosted:$PATH"
  jq -n '{hosted:{typesafe:{key_var:"TYPESAFE_API_KEY",base_url:"https://api.typesafe.test",systemone_path:"/v1/systemone",models:["jev-latest"],enabled:true},
          openrouter:{key_var:"OPENROUTER_API_KEY",base_url:"https://api.openrouter.test/api",systemone_path:"/v1/systemone",models:["typesafe/jev-1.13"],enabled:true}}}' > "$T/pins.json"
  export CMA_JEV_PINS_FILE="$T/pins.json"
  jq -n '{gateway:{running:false},profiles:[]}' > "$T/status.json"; export LLMCTL_STATUS_JSON="$T/status.json"
  export JEV_HOSTED_PROBE=1
  KEYS="$HOME/api_keys.sh"
}
write_keys() { local f="$1" m="$2"; shift 2; : > "$f"; local kv; for kv in "$@"; do printf 'export %s=%s\n' "${kv%%=*}" "'${kv#*=}'" >> "$f"; done; chmod "$m" "$f"; }
run_bs() { local n="$1"; shift
  bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive "$@" >"$T/$n.out" 2>"$T/$n.err"
  RC=$?; DET="$JEV_EVIDENCE_DIR/jev-detection.json"; }
gate() { JEV_DETECTION_FILE="$1" JEV_PROBE_CMD="$REPO/scripts/jev/jev-probe.sh" bash "$GATES/cm_jev_detection.sh" >"$T/gate.out" 2>&1; }

# ---- H1 status classes -> reachable / usable ----------------------------------------------------------
for row in "200:2xx:true:true" "402:no_credit:false:false" "429:rate_limited:false:false" "401:401:false:false" \
           "403:403:false:false" "500:other:false:false" "000:timeout:false:false"; do
  IFS=: read -r code cls reach usable <<<"$row"
  setup h1; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; export STUB_CODE="$code"
  run_bs h1
  assert_eq "$cls" "$(jq -r '.endpoints[0].auth_status_class' "$DET")" "H1 HTTP $code => class $cls"
  assert_eq "$reach" "$(jq -r '.endpoints[0].reachable' "$DET")" "H1 HTTP $code => reachable=$reach (2xx only)"
  assert_eq "$usable" "$(jq -r '.endpoints[0].usable' "$DET")" "H1 HTTP $code => usable=$usable"
  assert_eq "probe" "$(jq -r '.endpoints[0].reachable_basis' "$DET")" "H1 HTTP $code => basis probe (a probed answer, never resolution-only)"
  if [ "$code" = "402" ]; then
    assert_contains "$T/h1.err" "no_credit" "H1 402 is reported loudly on stderr as no_credit"
    assert_not_contains "$T/h1.err" "detect-models: ok endpoints" "H1 402 never prints a bare 'detect-models: ok' (false green)"
  fi
  unset STUB_CODE
done
# H1c the toolkit-cache probe path applies the same 2xx-only rule (a cache entry at the pinned origin answering 402)
for row in "402:no_credit:false" "200:2xx:true"; do
  IFS=: read -r code cls reach <<<"$row"
  setup h1c with-submodules; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; export STUB_CODE="$code"
  jq -n '{endpoints:[{provider_id:"tscache",base_url:"https://api.typesafe.test",model:"jev-latest",key_var:"TYPESAFE_API_KEY"}]}' > "$T/eps.json"
  mkdir -p "$CMA_PROVIDERS_DIR"; cp "$T/eps.json" "$CMA_PROVIDERS_DIR/jev-endpoints.json"; export FIXTURE_ENDPOINTS="$T/eps.json"
  run_bs h1c
  assert_eq "$cls" "$(jq -r '[.endpoints[]|select(.source=="toolkit-cache")|.auth_status_class][0]' "$DET")" "H1c toolkit-cache probe HTTP $code => class $cls"
  assert_eq "$reach" "$(jq -r '[.endpoints[]|select(.source=="toolkit-cache")|.reachable][0]' "$DET")" "H1c toolkit-cache probe HTTP $code => reachable=$reach (2xx only)"
  unset STUB_CODE FIXTURE_ENDPOINTS
done

# ---- H2 the replayable probe agrees ------------------------------------------------------------------
setup h2; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; run_bs h2
for row in "200:0" "402:1" "401:1" "429:1"; do
  IFS=: read -r code want <<<"$row"
  JEV_DETECTION_FILE="$DET" STUB_CODE="$code" bash "$REPO/scripts/jev/jev-probe.sh" hosted-typesafe https://api.typesafe.test >/dev/null 2>&1
  assert_rc "$want" "$?" "H2 jev-probe replay of HTTP $code exits $want (usable = 2xx only)"
done

# ---- H3 detection gate --------------------------------------------------------------------------------
setup h3; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; export STUB_CODE=402; run_bs h3; unset STUB_CODE
cp "$DET" "$T/nocredit.json"
gate "$T/nocredit.json"; assert_rc 0 "$?" "H3 probed-unusable (402, real key) is an honest record: gate PASS"
assert_contains "$T/gate.out" "no_credit" "H3 the gate names the unusable class"
jq '.endpoints[0].auth_status_class="2xx"' "$T/nocredit.json" > "$T/contra1.json"
gate "$T/contra1.json"; assert_nonzero "$?" "H3 reachable=false with class 2xx is a contradiction => RED"
jq '.endpoints[0].reachable=true' "$T/nocredit.json" > "$T/contra2.json"
gate "$T/contra2.json"; assert_nonzero "$?" "H3 reachable=true with class no_credit is a contradiction => RED"
jq '.endpoints[0].reachable=null | .endpoints[0].reachable_basis="resolution-only" | del(.endpoints[0].auth_status_class)' "$T/nocredit.json" > "$T/null.json"
gate "$T/null.json"; assert_nonzero "$?" "H3 reachable=null with a real key stays RED"
jq 'del(.endpoints[0].auth_status_class)' "$T/nocredit.json" > "$T/noclass.json"
gate "$T/noclass.json"; assert_nonzero "$?" "H3 reachable=false with NO recorded class is unproven => RED"

# ---- H4 exit 5: detected, not wired ----------------------------------------------------------------------
setup h4; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; run_bs h4
assert_rc 5 "$RC" "H4 a usable endpoint detected but no agent wired => rc 5 (never 0)"
assert_contains "$T/h4.err" "detected, not wired" "H4 the reason is printed"
setup h4n; run_bs h4n
assert_rc 0 "$RC" "H4-NEG no key, nothing detected => rc 0 (reasoned-empty record)"
setup h4c; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; export STUB_CODE=402; run_bs h4c; unset STUB_CODE
assert_rc 5 "$RC" "H4 only an unusable (402) endpoint => rc 5 (no usable endpoint), never 0"
assert_contains "$T/h4c.err" "no usable decision endpoint" "H4 no-usable reason printed"

# ---- H5 default-on wiring ------------------------------------------------------------------------------------
setup h5 with-submodules; mkdir -p "$HOME/.claude"; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
run_bs h5 --default-on
assert_contains "$T/h5.err" "DEFAULT-ON" "H5 default-on is logged loudly"
assert_contains "$T/h5.err" "jev-setup --uninstall" "H5 the log says how to undo it"
assert_file_exists "$HOME/.claude/jev-wiring.marker" "H5 the fixture agent home was wired"
assert_contains "$STUB_LOG/jev-setup.log" "check=0 yes=1" "H5 jev-setup ran with --yes (consent applied)"
assert_rc 0 "$RC" "H5 detected AND wired => rc 0"
assert_eq "true" "$(jq -r '.consent.default_on' "$JEV_STATE_DIR/consent.json")" "H5 consent record says default_on=true"
assert_eq "operator-standing-order-2026-11-12" "$(jq -r '.consent.basis' "$JEV_STATE_DIR/consent.json")" "H5 consent basis recorded"
# placeholder key => not engaged
setup h5p with-submodules; mkdir -p "$HOME/.claude"; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=changeme"
run_bs h5p --default-on
assert_contains "$T/h5p.err" "default-on not engaged" "H5-NEG placeholder key => default-on not engaged (logged)"
assert_file_absent "$HOME/.claude/jev-wiring.marker" "H5-NEG placeholder key => nothing wired"
# opt-out marker
setup h5o with-submodules; mkdir -p "$HOME/.claude"; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; : > "$JEV_CONFIG_DIR/wiring.disabled"
run_bs h5o --default-on
assert_contains "$T/h5o.err" "wiring.disabled" "H5-NEG opt-out marker honoured and named"
assert_file_absent "$HOME/.claude/jev-wiring.marker" "H5-NEG opt-out marker => nothing wired"
assert_rc 0 "$RC" "H5-NEG explicit opt-out => rc 0 (a declared state, not a failure)"
assert_contains "$T/h5o.err" "NOT wired - the operator opted out" "H5-NEG opt-out => the RESULT line says NOT wired, never serving"
assert_not_contains "$T/h5o.err" "RESULT rc 0: serving" "H5-NEG opt-out never claims serving"
# without --default-on the old consent boundary holds
setup h5d with-submodules; mkdir -p "$HOME/.claude"; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
run_bs h5d
assert_file_absent "$HOME/.claude/jev-wiring.marker" "H5-NEG no --default-on and no --yes => nothing wired"
assert_eq "0" "$(grep -rlF -- "$KEY_A" "$T" 2>/dev/null | grep -vF "$KEYS" | wc -l | tr -d ' ')" "H5 the key value appears in no output/state file"
assert_eq "1" "$(grep -rlF -- "$KEY_A" "$T" 2>/dev/null | grep -cF "$KEYS")" "H5 CONTROL NEEDLE: the scan sees the key in the keys file"

# ---- H7 probe outcome is part of the stage-3 input (review F1) ---------------------------------------------------------
probes() { grep -c '^verdict .*typesafe\.test' "$STUB_LOG/curl.log" 2>/dev/null || true; }
setup h7; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
export STUB_CODE=402; run_bs h7a
assert_eq "5 no_credit" "$RC $(jq -r '.endpoints[0].auth_status_class' "$DET")" "H7 run 1 (402): rc 5, class no_credit"
p1="$(probes)"
export STUB_CODE=200; run_bs h7b
assert_eq "2xx true" "$(jq -r '.endpoints[0] | "\(.auth_status_class) \(.reachable)"' "$DET")" "H7 402 -> 200 (credit added): the record is rewritten to 2xx / reachable=true"
assert_not_contains "$T/h7b.err" "detect-models: no-change" "H7 402 -> 200: stage 3 is NOT a stale no-change"
# 2 = ONE stage-3 probe (the pre-key probe, reused by the stage through the memo) + ONE replay by cm_jev_detection, which
# re-probes every endpoint the record calls reachable=true (bootstrap runs the gate at the end). Without the memo it is 3.
assert_eq "2" "$(( $(probes) - p1 ))" "H7 run 2: one stage-3 probe (memo reused by the stage) + one cm_jev_detection replay of the reachable endpoint"
cat "$T/h7b.out" "$T/h7b.err" > "$T/h7b.all"
assert_contains "$T/h7b.all" "gate cm_jev_detection: PASS" "H7 CONTROL: run 2 did run the detection gate whose replay is the second probe"
p2="$(probes)"
export STUB_CODE=402; run_bs h7c
assert_eq "no_credit false false" "$(jq -r '.endpoints[0] | "\(.auth_status_class) \(.reachable) \(.usable)"' "$DET")" "H7 200 -> 402 (credit lost): the record no longer calls the endpoint usable"
assert_rc 5 "$RC" "H7 200 -> 402: rc 5 (no usable endpoint)"
assert_contains "$T/h7c.err" "no_credit" "H7 200 -> 402: no_credit reported"
cp "$DET" "$T/det_h7c.json"
run_bs h7d
assert_contains "$T/h7d.err" "detect-models: no-change" "H7 an unchanged answer (402, 402) is a no-change"
if cmp -s "$T/det_h7c.json" "$DET"; then ok "H7 the unchanged run leaves the record byte-identical"; else fail "H7 the unchanged run rewrote the record"; fi
assert_eq "1" "$(( $(probes) - p2 - 1 ))" "H7 the unchanged run still probed once (so a later change is seen)"
unset STUB_CODE
# toolkit-cache probe path: 402 -> 200
setup h7t with-submodules; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
jq -n '{endpoints:[{provider_id:"tscache",base_url:"https://api.typesafe.test",model:"jev-latest",key_var:"TYPESAFE_API_KEY"}]}' > "$T/eps.json"
mkdir -p "$CMA_PROVIDERS_DIR"; cp "$T/eps.json" "$CMA_PROVIDERS_DIR/jev-endpoints.json"; export FIXTURE_ENDPOINTS="$T/eps.json"
export STUB_CODE=402; run_bs h7t1
export STUB_CODE=200; run_bs h7t2
assert_eq "2xx true" "$(jq -r '[.endpoints[]|select(.source=="toolkit-cache")][0] | "\(.auth_status_class) \(.reachable)"' "$DET")" "H7 toolkit-cache 402 -> 200: the record is rewritten"
unset STUB_CODE FIXTURE_ENDPOINTS

# ---- H8 JEV_WIRING=off (review RM5) --------------------------------------------------------------------------------------
setup h8 with-submodules; mkdir -p "$HOME/.claude"; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
JEV_WIRING=off run_bs h8 --default-on
assert_contains "$T/h8.err" "default-on not engaged: JEV_WIRING=off" "H8 JEV_WIRING=off => default-on not engaged, and the reason is named"
assert_file_absent "$HOME/.claude/jev-wiring.marker" "H8 JEV_WIRING=off => nothing wired"
assert_rc 0 "$RC" "H8 JEV_WIRING=off => rc 0 (a declared opt-out)"
assert_contains "$T/h8.err" "NOT wired - the operator opted out" "H8 JEV_WIRING=off => RESULT says NOT wired"
assert_eq "false" "$(jq -r '.consent.default_on' "$JEV_STATE_DIR/consent.json")" "H8 consent record default_on=false"
# negative control: the same run without the opt-out wires (so H8 is not passing for another reason)
setup h8c with-submodules; mkdir -p "$HOME/.claude"; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
run_bs h8c --default-on
assert_file_exists "$HOME/.claude/jev-wiring.marker" "H8 CONTROL: without JEV_WIRING=off the same run wires"

# ---- H9 key value never in a DEFAULT-ON run's output or consent.json (review RM12) --------------------------------------
setup h9 with-submodules; mkdir -p "$HOME/.claude"; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
run_bs h9 --default-on
assert_eq "true" "$(jq -r '.consent.default_on' "$JEV_STATE_DIR/consent.json")" "H9 setup: default-on engaged (the leak path is exercised)"
assert_eq "TYPESAFE_API_KEY" "$(jq -r '.consent.key_vars | join(",")' "$JEV_STATE_DIR/consent.json")" "H9 consent.json names the key variable only"
if leak_scan_selftest "$T"; then ok "H9 CONTROL NEEDLE: the scan of the run dir can see a planted needle"; else fail "H9 the scan is blind"; fi
assert_eq "1" "$(grep -rlF -- "$KEY_A" "$T" 2>/dev/null | grep -cF "$KEYS")" "H9 CONTROL: the scan sees the key in the keys file"
assert_eq "0" "$(leaks_count "$KEY_A" "$T")" "H9 the key value is in no bootstrap output, log, consent.json or state file of the default-on run"
assert_eq "0" "$(grep -cF -- "$KEY_A" "$T/h9.err" "$T/h9.out" "$JEV_STATE_DIR/consent.json" 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')" "H9 stderr/stdout/consent.json carry no key value"

# ---- H10 fresh-state idempotency with a PROBED hosted endpoint (round 3, review R2-1, §11.4.281(C)) ----------------------
# Run 1 starts with no detection record, so a stage key built only from the PREVIOUS record differed between run 1 and
# run 2 and run 2 re-ran stage 3. The stored key must be the one the NEXT run will compute from the record this run wrote.
s3_line() { grep -o 'detect-models: [a-z-]*' "$1" | head -1; }
setup h10; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; export STUB_CODE=200
run_bs h10a
assert_eq "detect-models: running" "$(s3_line "$T/h10a.err")" "H10 run 1 (fresh state, hosted 200): stage 3 runs"
cp "$DET" "$T/det_h10a.json"; cp "$JEV_STATE_DIR/bootstrap.stamp" "$T/stamp_h10a"
run_bs h10b
assert_eq "detect-models: no-change" "$(s3_line "$T/h10b.err")" "H10 run 2 (unchanged probe answer): stage 3 is a no-change"
if cmp -s "$T/det_h10a.json" "$DET"; then ok "H10 run 2 leaves the detection record byte-identical"; else fail "H10 run 2 rewrote the detection record"; fi
if cmp -s "$T/stamp_h10a" "$JEV_STATE_DIR/bootstrap.stamp"; then ok "H10 run 2 leaves the stamp byte-identical"; else fail "H10 run 2 changed the stamp"; fi
run_bs h10c
assert_eq "detect-models: no-change" "$(s3_line "$T/h10c.err")" "H10 run 3 (unchanged): stage 3 is still a no-change"
if cmp -s "$T/det_h10a.json" "$DET"; then ok "H10 run 3 leaves the detection record byte-identical"; else fail "H10 run 3 rewrote the detection record"; fi
export STUB_CODE=402; run_bs h10d
assert_eq "detect-models: running" "$(s3_line "$T/h10d.err")" "H10 run 4 (200 -> 402): stage 3 re-runs"
assert_eq "no_credit" "$(jq -r '.endpoints[0].auth_status_class' "$DET")" "H10 run 4 rewrote the record to no_credit"
run_bs h10e
assert_eq "detect-models: no-change" "$(s3_line "$T/h10e.err")" "H10 run 5 (402 unchanged): no-change"
export STUB_CODE=200; run_bs h10f
assert_eq "detect-models: running" "$(s3_line "$T/h10f.err")" "H10 run 6 (402 -> 200): stage 3 re-runs"
assert_eq "2xx true" "$(jq -r '.endpoints[0] | "\(.auth_status_class) \(.reachable)"' "$DET")" "H10 run 6 rewrote the record to 2xx / reachable=true"
unset STUB_CODE

# ---- H11 a LOCAL llmctl gateway's healthz answer is part of the stage-3 input (round 3, review X1) -----------------------
# The gateway URL is on a stub-answered host, so the healthz GET answers STUB_CODE (000 = connection failure).
setup h11
jq -n '{gateway:{running:true,detail:"gateway up at https://gw.typesafe.test:8095 (stub)"},profiles:[{profile:"decide-tiny",running:true}]}' > "$T/status.json"
export STUB_CODE=200; run_bs h11a
assert_eq "true" "$(jq -r '[.endpoints[]|select(.source=="local-llmctl")][0].reachable' "$DET")" "H11 run 1: the local gateway answered healthz (reachable=true)"
run_bs h11b
assert_eq "detect-models: no-change" "$(s3_line "$T/h11b.err")" "H11 run 2 (healthz unchanged): no-change"
export STUB_CODE=000; run_bs h11c
assert_eq "detect-models: running" "$(s3_line "$T/h11c.err")" "H11 run 3 (healthz now fails): stage 3 re-runs (the local health answer is in the key)"
assert_eq "false" "$(jq -r '[.endpoints[]|select(.source=="local-llmctl")][0].reachable' "$DET")" "H11 run 3 rewrote the record: reachable=false"
run_bs h11d
assert_eq "detect-models: no-change" "$(s3_line "$T/h11d.err")" "H11 run 4 (healthz still failing): no-change"
unset STUB_CODE

# ---- H12 a local gateway WITH a CA file: the stage-3 signature probes it the same way the stage does (round 4, Y2) ------
# The signature and the stage share one memo keyed on url AND ca file. A signature that dropped the CA would probe a
# second time (without --cacert) in run 1 and probe without the CA in every later run: one probe per run, all with the CA.
healthz_calls() { grep -c '^curl .*healthz' "$STUB_LOG/curl.log" 2>/dev/null || true; }
healthz_nocacert() { grep '^curl .*healthz' "$STUB_LOG/curl.log" 2>/dev/null | grep -vc -- '--cacert' || true; }
setup h12; : > "$T/ca.crt"
jq -n --arg ca "$T/ca.crt" '{gateway:{running:true,detail:"gateway up at https://gw.typesafe.test:8095 (stub)"},
  profiles:[{profile:"decide-tiny",running:true}],
  registry:{services:[{name:"gateway",healthy:true,url:"https://gw.typesafe.test:8095",labels:{kind:"gateway",ca_file:$ca}}]}}' > "$T/status.json"
export STUB_CODE=200; : > "$STUB_LOG/curl.log"; run_bs h12a
assert_eq "$T/ca.crt" "$(jq -r '[.endpoints[]|select(.source=="local-llmctl")][0].ca_file' "$DET")" "H12 run 1: the record carries the gateway's CA file"
assert_eq "1" "$(healthz_calls)" "H12 run 1: the gateway healthz is probed exactly once (the signature reuses the stage's probe)"
assert_eq "0" "$(healthz_nocacert)" "H12 run 1: every healthz probe carries --cacert"
: > "$STUB_LOG/curl.log"; run_bs h12b
assert_eq "detect-models: no-change" "$(s3_line "$T/h12b.err")" "H12 run 2 (unchanged): no-change"
assert_eq "1" "$(healthz_calls)" "H12 run 2: exactly one healthz probe"
assert_eq "0" "$(healthz_nocacert)" "H12 run 2: the signature probe carries --cacert"
unset STUB_CODE

# ---- H13 an explicit JEV_LLMCTL_BIN / JEV_TOOLKIT_BIN is the only candidate (round 4, review R3-2 nit) -------------------
# A spy llmctl / claude-providers first on PATH must never be called when the variable is set; a value that is not an
# executable makes the tool absent (logged), never a fall-back to PATH.
setup h13; mkdir -p "$T/spy"
for s in llmctl claude-providers; do printf '#!/bin/sh\necho "%s $*" >> "%s"\necho "{}"\n' "$s" "$T/spy.log" > "$T/spy/$s"; chmod +x "$T/spy/$s"; done
jq -n '{gateway:{running:true,detail:"gateway up at https://gw.typesafe.test:8095 (stub)"},profiles:[{profile:"decide-tiny",running:true}]}' > "$T/status.json"
export STUB_CODE=200
: > "$T/spy.log"; PATH="$T/spy:$PATH" JEV_LLMCTL_BIN="$T/no-such-llmctl" JEV_TOOLKIT_BIN="$T/no-such-cp" run_bs h13a
assert_eq "" "$(cat "$T/spy.log")" "H13 non-executable overrides: no llmctl / claude-providers on PATH was called"
assert_contains "$T/h13a.err" "JEV_LLMCTL_BIN is set but is not an executable file: llmctl treated as absent" "H13 the absent llmctl is logged"
assert_contains "$T/h13a.err" "JEV_TOOLKIT_BIN is set but is not an executable file: claude-providers treated as absent" "H13 the absent claude-providers is logged"
assert_eq "0" "$(jq '[.endpoints[]|select(.source=="local-llmctl")]|length' "$DET")" "H13 llmctl absent: no local endpoint is read"
: > "$T/spy.log"; PATH="$T/spy:$PATH" JEV_LLMCTL_BIN="$FIXTURES/bin/llmctl" JEV_TOOLKIT_BIN="$FIXTURES/bin/claude-providers" run_bs h13b
assert_eq "" "$(cat "$T/spy.log")" "H13 executable overrides: the PATH spies are still not called"
assert_eq "1" "$(jq '[.endpoints[]|select(.source=="local-llmctl")]|length' "$DET")" "H13 the explicit llmctl is used (its status names the running decide-tiny)"
: > "$T/spy.log"; PATH="$T/spy:$PATH" run_bs h13c
assert_contains "$T/spy.log" "llmctl decide status --json" "H13 CONTROL: with no override the llmctl on PATH is used (the spies can see a call)"
unset STUB_CODE

# ---- H6 post_update_hook STEP 4e ------------------------------------------------------------------------------
HOSTS=()
export PATH="$ORIG_PATH"   # the fixture bin dirs carry a stub git; the hook host needs the real one
unset JEV_STATE_DIR JEV_CONFIG_DIR JEV_EVIDENCE_DIR CMA_JEV_PINS_FILE
make_hook_host README.md; HOSTS+=("$HOST_C")
cp "$REPO/scripts/jev/lib_keys.sh" "$REPO/scripts/jev/lib_decide.sh" "$HOST_C/scripts/jev/"
mkdir -p "$HOST_P/home"; write_keys "$HOST_P/home/api_keys.sh" 600 "TYPESAFE_API_KEY=$KEY_A"
run_hook_host
assert_contains "$HOST_P/bootstrap.log" "--default-on" "H6 a real key present and no Jev change => bootstrap still runs, --default-on"
assert_contains "$HOST_P/hook.out" "real decision key present" "H6 the hook says why it ran"
make_hook_host README.md; HOSTS+=("$HOST_C")
cp "$REPO/scripts/jev/lib_keys.sh" "$REPO/scripts/jev/lib_decide.sh" "$HOST_C/scripts/jev/"
mkdir -p "$HOST_P/home"; write_keys "$HOST_P/home/api_keys.sh" 600 "TYPESAFE_API_KEY=$KEY_A"
run_hook_host BOOTSTRAP_STUB_RC=5
assert_rc 0 "$HOOK_RC" "H6 bootstrap rc 5 never fails the pull"
assert_contains "$HOST_P/hook.out" "detected, not wired" "H6 rc 5 is surfaced as a warning"
assert_not_contains "$HOST_P/bootstrap.log" "--defer" "H6 rc 5 is NOT deferred over"
make_hook_host README.md; HOSTS+=("$HOST_C")
cp "$REPO/scripts/jev/lib_keys.sh" "$REPO/scripts/jev/lib_decide.sh" "$HOST_C/scripts/jev/"
run_hook_host
if [ -f "$HOST_P/bootstrap.log" ]; then assert_not_contains "$HOST_P/bootstrap.log" "bootstrap" "H6-NEG no key and no Jev change => no bootstrap"
else ok "H6-NEG no key and no Jev change => no bootstrap (never invoked)"; fi
for h in "${HOSTS[@]}"; do rm -rf "$(dirname "$h")"; done
finish
