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
