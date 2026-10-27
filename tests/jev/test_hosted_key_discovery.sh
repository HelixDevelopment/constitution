#!/usr/bin/env bash
# test_hosted_key_discovery.sh — a Jev (Typesafe) API key present in the operator's keys file is used
# out of the box (detected by variable NAME, probed, shadow-served), and no secret ever leaks:
#   K1  real key => hosted endpoint recorded + really probed (auth sent on STDIN, never argv)
#   K2  HTTP class only is recorded: 2xx / 401 / 403 / timeout
#   K3  placeholder values are ABSENT with an explicit reason (never the value)
#   K4  keys file missing / unreadable => lawful empty record with a reason
#   K5  group/world-readable keys file => warning + perms_warning in the evidence
#   K6  precedence JEV_API_KEYS_FILE > CMA_KEYS_FILE > ~/api_keys.sh
#   K7  hosted endpoints never enforce (shadow even with --enforce)
#   K8  H1 gate: hosted endpoint reachable null/false while a real key is present => RED
#   K9  H2 gate accepts --root
#   K10 H3 token gate parses toolkit-shaped decisions (.question, no .class)
#   K11 H5 bootstrap reads the cache where claude-providers sync-jev really writes
# Keys are DUMMY values assembled from fragments; the control-needle scan proves the scan can see them.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq curl; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done
GATES="$REPO/scripts/gates"

mkkey() { printf '%s-%s-%s' "dummyk$1" "A1b2C3d4" "E5f6G7h8I9j0"; }   # >= 16 chars, not a known dummy
KEY_A="$(mkkey a)"; KEY_B="$(mkkey b)"; KEY_C="$(mkkey c)"

setup() { # setup <name> : sandbox, pins file, stub curl first on PATH, constitution root
  make_fixture_env "$1"
  make_fixture_constitution_root with-submodules
  mkdir -p "$T/constitution/scripts"; ln -s "$GATES" "$T/constitution/scripts/gates"
  export PATH="$FIXTURES/bin-hosted:$PATH"
  PINS="$T/pins.json"
  jq -n '{hosted:{typesafe:{key_var:"TYPESAFE_API_KEY",base_url:"https://api.typesafe.test",systemone_path:"/v1/systemone",models:["jev-latest","jev-1.13.0"],enabled:true},
          openrouter:{key_var:"OPENROUTER_API_KEY",base_url:"https://api.openrouter.test/api",systemone_path:"/v1/systemone",models:["typesafe/jev-1.13"],enabled:true}},
          local_gateway:{host:"127.0.0.1",port:8095,scheme:"https",key_var:"LLMCTL_API_KEY",enabled:true}}' > "$PINS"
  export CMA_JEV_PINS_FILE="$PINS"
  jq -n '{gateway:{running:false},profiles:[]}' > "$T/status.json"; export LLMCTL_STATUS_JSON="$T/status.json"
  export JEV_HOSTED_PROBE=1
  KEYS="$HOME/api_keys.sh"
}
write_keys() { # write_keys <file> <mode> VAR=VALUE...
  local f="$1" m="$2"; shift 2
  : > "$f"; local kv; for kv in "$@"; do printf 'export %s=%s\n' "${kv%%=*}" "'${kv#*=}'" >> "$f"; done
  chmod "$m" "$f"
}
run_bs() { local n="$1"; shift
  bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive "$@" >"$T/$n.out" 2>"$T/$n.err"
  RC=$?; DET="$JEV_EVIDENCE_DIR/jev-detection.json"; }
leaks() { # leaks <needle> : count files under $T (keys file excluded) that contain it; the scan is control-needled first
  leak_scan_selftest "$T" || { echo "BLIND leak scan" >&2; echo 999; return 0; }
  leaks_count "$1" "$T"; }

# ---- K1 / K2 / K7 -------------------------------------------------------------
setup k1
write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
export STUB_EXPECT_KEY="$KEY_A"
run_bs k1
assert_rc 0 "$RC" "K1 bootstrap rc 0"
assert_eq "hosted-typesafe" "$(jq -r '[.endpoints[].id]|join(" ")' "$DET")" "K1 hosted endpoint recorded from the real key (OpenRouter has no key: not listed)"
assert_eq "https://api.typesafe.test" "$(jq -r '.endpoints[0].url' "$DET")" "K1 host comes from the claude_toolkit pin, https"
assert_eq "TYPESAFE_API_KEY" "$(jq -r '.endpoints[0].key_var' "$DET")" "K1 key_var NAME recorded"
assert_eq "true" "$(jq -r '.endpoints[0].reachable' "$DET")" "K1 reachable=true from a real authenticated probe"
assert_eq "2xx" "$(jq -r '.endpoints[0].auth_status_class' "$DET")" "K1 auth status CLASS recorded (2xx)"
assert_eq "probe" "$(jq -r '.endpoints[0].reachable_basis' "$DET")" "K1 reachable_basis=probe"
assert_eq "jev-latest" "$(jq -r '.endpoints[0].model' "$DET")" "K1 model from the pin"
assert_contains "$STUB_LOG/curl.log" "verdict AUTH_OK https://api.typesafe.test" "K1 the probe carried the Authorization header on stdin config"
assert_not_contains "$STUB_LOG/curl.log" "$KEY_A" "K1 NEG: key never on a curl command line"
assert_eq "real" "$(jq -r '.key_discovery.vars[]|select(.key_var=="TYPESAFE_API_KEY")|.state' "$DET")" "K1 key state recorded by NAME"
assert_eq "absent" "$(jq -r '.key_discovery.vars[]|select(.key_var=="OPENROUTER_API_KEY")|.state' "$DET")" "K1 OpenRouter key absent, recorded with a reason"
assert_ne "null" "$(jq -r '.key_discovery.vars[]|select(.key_var=="OPENROUTER_API_KEY")|.reason // "null"' "$DET")" "K1 absent key carries a reason"
assert_eq "shadow" "$(grep -s '^JEV_MODE=' "$JEV_CONFIG_DIR/env" | cut -d= -f2)" "K1 immediately in shadow mode"
assert_eq "0" "$(leaks "$KEY_A")" "K1 key value appears in no output/evidence/state file"
assert_eq "1" "$(grep -rlF -- "$KEY_A" "$T" 2>/dev/null | grep -cF "$KEYS")" "K1 CONTROL NEEDLE: the scan does see the key in the keys file (instrument can see)"
assert_contains "$T/k1.err" "gate cm_jev_detection: PASS" "K1 report-stage detection gate PASSes with a probed hosted endpoint"
# K7 hosted never enforces
rm -rf "$JEV_STATE_DIR"/* "$JEV_CONFIG_DIR"/env; export JEV_BASE_URL=https://127.0.0.1:8095; JEV_NOW_EPOCH="$(date +%s)" run_bs k7 --enforce; unset JEV_BASE_URL   # a loopback base isolates the hosted-ENDPOINT reason (an empty base is its own shadow, r4 I4-1)
assert_eq "shadow" "$(grep -s '^JEV_MODE=' "$JEV_CONFIG_DIR/env" | cut -d= -f2)" "K7 --enforce with only hosted endpoints stays shadow (hosted never enforce)"
assert_contains "$JEV_STATE_DIR/enforce-deferred" "hosted" "K7 the deferral says why"
# K7b (r3 I3-3): the same with PROMOTED thresholds + a passing validator + JEV_TEST seam => still shadow, hosted is the reason
rm -rf "$JEV_STATE_DIR"/* "$JEV_CONFIG_DIR"/env
jq -n '{per_type:{gate:{promoted:true,threshold:0.9}}}' > "$JEV_CONFIG_DIR/jev-thresholds.json"
jev_test_enforce_env 0
run_bs k7b --enforce
assert_eq "shadow" "$(grep -s '^JEV_MODE=' "$JEV_CONFIG_DIR/env" | cut -d= -f2)" "K7b --enforce + PROMOTED thresholds + passing validator, hosted-only endpoints => shadow"
assert_contains "$JEV_STATE_DIR/enforce-deferred" "hosted" "K7b the deferral names the hosted-endpoint reason"
rm -f "$JEV_CONFIG_DIR/jev-thresholds.json"; unset JEV_TEST JEV_DECISION_PROFILES JEV_REQUIRE_VALIDATED_CMD
# K2 status classes
for pair in "401:401:true" "403:403:true" "000:timeout:false" "500:other:true"; do
  code="${pair%%:*}"; rest="${pair#*:}"; cls="${rest%%:*}"; reach="${rest#*:}"
  setup k2; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; unset STUB_EXPECT_KEY; export STUB_CODE="$code"
  run_bs k2
  assert_eq "$cls" "$(jq -r '.endpoints[0].auth_status_class' "$DET")" "K2 HTTP $code => class $cls"
  assert_eq "$reach" "$(jq -r '.endpoints[0].reachable' "$DET")" "K2 HTTP $code => reachable=$reach"
done
unset STUB_CODE

# ---- K3 placeholders --------------------------------------------------------------
for v in "x" "short" "changeme" "your-key-here" "aaaaaaaaaaaaaaaaaaaaaaaa"; do
  setup k3; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$v"
  run_bs k3
  assert_eq "0" "$(jq '.endpoints|length' "$DET")" "K3 placeholder [$v] => no endpoint"
  assert_eq "placeholder" "$(jq -r '.key_discovery.vars[]|select(.key_var=="TYPESAFE_API_KEY")|.state' "$DET")" "K3 [$v] classified placeholder"
  assert_contains "$DET" "TYPESAFE_API_KEY placeholder" "K3 [$v] explicit reason names the variable"
  if [ -f "$STUB_LOG/curl.log" ]; then assert_not_contains "$STUB_LOG/curl.log" "typesafe.test" "K3 [$v] NEG: no probe is made with a placeholder"; else ok "K3 [$v] NEG: no probe is made with a placeholder (curl never invoked)"; fi
done
assert_eq "0" "$(grep -rlF -- "your-key-here" "$JEV_EVIDENCE_DIR" "$T/k3.err" "$JEV_STATE_DIR" 2>/dev/null | wc -l)" "K3 placeholder VALUE is not echoed either"

# ---- K4 missing / unreadable ----------------------------------------------------------
setup k4a
run_bs k4a
assert_rc 0 "$RC" "K4 missing keys file is lawful (rc 0)"
assert_eq "0" "$(jq '.endpoints|length' "$DET")" "K4 no endpoint without a key"
assert_contains "$DET" "keys file missing" "K4 reason: keys file missing"
if [ "$(id -u)" != "0" ]; then
  setup k4b; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; chmod 000 "$KEYS"
  run_bs k4b
  assert_rc 0 "$RC" "K4 unreadable keys file is lawful (rc 0)"
  assert_contains "$DET" "keys file not readable" "K4 reason: keys file not readable"
  chmod 600 "$KEYS"
else assert_skip "K4 unreadable-file case needs a non-root user"; fi

# ---- K5 permissions warning -----------------------------------------------------------------
setup k5; write_keys "$KEYS" 644 "TYPESAFE_API_KEY=$KEY_A"
run_bs k5
assert_eq "true" "$(jq -r '.key_discovery.perms_warning' "$DET")" "K5 group/world-readable keys file => perms_warning true"
assert_contains "$T/k5.err" "chmod 600" "K5 the warning tells the operator what to do"
assert_eq "hosted-typesafe" "$(jq -r '[.endpoints[].id]|join(" ")' "$DET")" "K5 the key is still used (warning, not refusal)"
setup k5b; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
run_bs k5b
assert_eq "false" "$(jq -r '.key_discovery.perms_warning' "$DET")" "K5-NEG mode 600 => no warning"

# ---- K6 precedence -------------------------------------------------------------------------------
setup k6
write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
write_keys "$T/keysB.sh" 600 "TYPESAFE_API_KEY=$KEY_B"
write_keys "$T/keysC.sh" 600 "TYPESAFE_API_KEY=$KEY_C"
export STUB_EXPECT_KEY="$KEY_C" JEV_API_KEYS_FILE="$T/keysC.sh" CMA_KEYS_FILE="$T/keysB.sh"
run_bs k6a
assert_eq "2xx" "$(jq -r '.endpoints[0].auth_status_class' "$DET")" "K6 JEV_API_KEYS_FILE wins over CMA_KEYS_FILE and ~/api_keys.sh"
setup k6b; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; write_keys "$T/keysB.sh" 600 "TYPESAFE_API_KEY=$KEY_B"
export STUB_EXPECT_KEY="$KEY_B" CMA_KEYS_FILE="$T/keysB.sh"
run_bs k6b
assert_eq "2xx" "$(jq -r '.endpoints[0].auth_status_class' "$DET")" "K6 CMA_KEYS_FILE wins over ~/api_keys.sh"
setup k6c; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; export STUB_EXPECT_KEY="$KEY_A"
run_bs k6c
assert_eq "2xx" "$(jq -r '.endpoints[0].auth_status_class' "$DET")" "K6 default ~/api_keys.sh when neither override is set"
export STUB_EXPECT_KEY="$KEY_B"; rm -rf "$JEV_STATE_DIR"/*; run_bs k6d
assert_eq "401" "$(jq -r '.endpoints[0].auth_status_class' "$DET")" "K6-NEG a wrong key is a recorded 401 class, not a silent success"
unset JEV_API_KEYS_FILE CMA_KEYS_FILE STUB_EXPECT_KEY

# ---- K8 H1: gate refuses an unproven hosted endpoint when a real key is present ----------------------
setup k8; write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"; export STUB_EXPECT_KEY="$KEY_A"
run_bs k8
GOOD="$DET"
gate() { JEV_DETECTION_FILE="$1" JEV_PROBE_CMD="$REPO/scripts/jev/jev-probe.sh" bash "$GATES/cm_jev_detection.sh" >"$T/gate.out" 2>&1; }
gate "$GOOD"; assert_rc 0 "$?" "K8 probed hosted endpoint + real key: GREEN"
jq '.endpoints[0].reachable=null | .endpoints[0].reachable_basis="resolution-only"' "$GOOD" > "$T/null.json"
gate "$T/null.json"; assert_nonzero "$?" "K8 hosted endpoint reachable=null while a real key is present => RED"
assert_contains "$T/gate.out" "TYPESAFE_API_KEY" "K8 the failure names the key variable (never its value)"
jq '.endpoints[0].reachable=false' "$GOOD" > "$T/false.json"
gate "$T/false.json"; assert_nonzero "$?" "K8 hosted endpoint reachable=false while a real key is present => RED"
assert_eq "0" "$(leaks "$KEY_A")" "K8 gate output/evidence carries no key value"
write_keys "$KEYS" 600 "TYPESAFE_API_KEY=changeme"
jq '.key_discovery={vars:[{key_var:"TYPESAFE_API_KEY",state:"placeholder"}]}' "$T/null.json" > "$T/null-ph.json"
gate "$T/null-ph.json"; assert_rc 0 "$?" "K8-NEG reachable=null with only a PLACEHOLDER key is not a failure"
write_keys "$KEYS" 600 "TYPESAFE_API_KEY=$KEY_A"
jq 'del(.endpoints[0].key_var)' "$T/null.json" > "$T/nokv.json"
gate "$T/nokv.json"; assert_rc 0 "$?" "K8-NEG reachable=null on an endpoint with no key_var (nothing to prove) stays lawful"
gate "$T/nope-never-created.json"; assert_nonzero "$?" "K8-NEG absent record still RED"

# ---- K9 H2: --root ----------------------------------------------------------------------------------------
mkdir -p "$T/proj/.jev"; cp "$GOOD" "$T/proj/.jev/jev-detection.json"
env -u JEV_DETECTION_FILE JEV_PROBE_CMD="$REPO/scripts/jev/jev-probe.sh" bash "$GATES/cm_jev_detection.sh" --root "$T/proj" >"$T/root.out" 2>&1
assert_rc 0 "$?" "K9 cm_jev_detection.sh --root <dir> reads <dir>/.jev/jev-detection.json"
env -u JEV_DETECTION_FILE bash "$GATES/cm_jev_detection.sh" --root "$T/proj-missing" >"$T/root2.out" 2>&1
assert_nonzero "$?" "K9 --root without a record is RED (not silently green)"
env -u JEV_DETECTION_FILE bash "$GATES/cm_jev_detection.sh" --bogus >"$T/root3.out" 2>&1
assert_rc 2 "$?" "K9 unknown option is a usage error (rc 2)"
JEV_DETECTION_FILE="$GOOD" JEV_PROBE_CMD="$REPO/scripts/jev/jev-probe.sh" bash "$GATES/cm_jev_detection.sh" >/dev/null 2>&1
assert_rc 0 "$?" "K9 the JEV_DETECTION_FILE env var still works"

# ---- K10 H3: toolkit-shaped decisions (.question only) -------------------------------------------------------
DEC="$T/dec.jsonl"
jq -nc '{ts:1,question:"gate",answer:"deny",confidence:0.88}' > "$DEC"
jq -nc '{ts:2,question:"routing",answer:"sonnet",confidence:0.9}' >> "$DEC"
jq -nc '{ts:3,question:"score",answer:"3",confidence:0.9}' >> "$DEC"
TOK() { JEV_BEFORE="$GATES/fixtures/jev/evidence/before.jsonl" JEV_AFTER="$GATES/fixtures/jev/evidence/after.jsonl" \
  JEV_BEFORE_CONFIG="$GATES/fixtures/jev/evidence/before.config" JEV_AFTER_CONFIG="$GATES/fixtures/jev/evidence/after.config" \
  JEV_DECISIONS="$1" bash "$GATES/cm_jev_token_reduction.sh" >"$T/tok.out" 2>&1; }
TOK "$DEC"; assert_rc 0 "$?" "K10 decisions with .question (no .class), as jev-gate.sh writes them, satisfy clause 4"
jq -nc '{ts:1,question:"gate",answer:"deny"}' > "$T/dec2.jsonl"
TOK "$T/dec2.jsonl"; assert_nonzero "$?" "K10-NEG a log covering only the 'gate' class still FAILs for routing/score"
jq -nc '{ts:1,class:"gate",question:"allow Read?",answer:"yes"}' > "$T/dec3.jsonl"; jq -nc '{ts:2,class:"routing",question:"tier?"}' >> "$T/dec3.jsonl"; jq -nc '{ts:3,class:"score",question:"q?"}' >> "$T/dec3.jsonl"
TOK "$T/dec3.jsonl"; assert_rc 0 "$?" "K10 an explicit .class still takes precedence over .question"

# ---- K11 H5: cache dir sync-jev really writes ---------------------------------------------------------------------
make_fixture_env k11; make_fixture_constitution_root with-submodules
mkdir -p "$T/realbin"
printf '%s\n' '#!/usr/bin/env bash' \
  'case "${1:-}" in sync-jev) d="$HOME/.local/share/claude-multi-account/providers"; mkdir -p "$d"; cp "$FIXTURE_ENDPOINTS" "$d/jev-endpoints.json" ;; *) exit 1 ;; esac' > "$T/realbin/claude-providers"
chmod +x "$T/realbin/claude-providers"
export PATH="$T/realbin:$PATH" CMA_PROVIDERS_DIR="$T/relocated-providers"   # sync-jev ignores this dir (live-measured)
mkdir -p "$CMA_PROVIDERS_DIR"
jq -n '{endpoints:[{provider_id:"jev-typesafe",base_url:"https://api.typesafe.test",model:"jev-latest",key_var:"TYPESAFE_API_KEY"}]}' > "$T/eps.json"
export FIXTURE_ENDPOINTS="$T/eps.json" JEV_HOSTED_PROBE=0
jq -n '{gateway:{running:false},profiles:[]}' > "$T/status.json"; export LLMCTL_STATUS_JSON="$T/status.json"
run_bs k11
assert_eq "jev-typesafe" "$(jq -r '[.endpoints[].id]|join(" ")' "$DET")" "K11 relocated CMA_PROVIDERS_DIR: bootstrap still reads the cache sync-jev wrote under HOME"
# ---- K12 discovery must not depend on the toolkit, the cache, or a pins file (2026-10-24 defect) -----------
# Layout of the operator's real run: toolkit unavailable (no pins file), EMPTY cache, a keys file with several
# variables. The endpoint must come from the key file alone and key_discovery must describe the file truthfully.
bare() { # bare <name> : fake HOME holding only api_keys.sh, no pins, no toolkit checkout, empty cache, stub curl
  make_fixture_env "$1"
  make_fixture_constitution_root          # no submodules => no toolkit checkout, no pins file
  export PATH="$FIXTURES/bin-hosted:$PATH"
  unset CMA_JEV_PINS_FILE
  jq -n '{gateway:{running:false},profiles:[]}' > "$T/status.json"; export LLMCTL_STATUS_JSON="$T/status.json"
  export JEV_HOSTED_PROBE=1 STUB_EXPECT_KEY="$KEY_A"
  KEYS="$HOME/api_keys.sh"
}
bare k12
write_keys "$KEYS" 600 "OTHER_SERVICE_TOKEN=abcdefghijklmnop12345" "TYPESAFE_API_KEY=$KEY_A" "UNRELATED=1"
run_bs k12
assert_rc 0 "$RC" "K12 bootstrap rc 0 without toolkit/pins"
assert_eq "hosted-typesafe" "$(jq -r '[.endpoints[]|select(.source=="api-keys-file")|.id]|join(" ")' "$DET")" "K12 hosted endpoint discovered from the key file ALONE (empty cache, no pins file)"
assert_eq "true" "$(jq -r '.key_discovery.keys_file_present' "$DET")" "K12 key_discovery.keys_file_present is true for an existing file"
assert_eq "600" "$(jq -r '.key_discovery.keys_file_mode' "$DET")" "K12 the real file mode is recorded"
assert_eq "real" "$(jq -r '.key_discovery.vars[]|select(.key_var=="TYPESAFE_API_KEY")|.state' "$DET")" "K12 variable NAME listed with its state"
assert_eq "builtin-default" "$(jq -r '.key_discovery.pins_source' "$DET")" "K12 the built-in default pins are used, and the record says so"
assert_eq "false" "$(jq -r '.key_discovery.perms_warning' "$DET")" "K12 mode 600 => no perms warning"
assert_eq "0" "$(leaks "$KEY_A")" "K12 no key value in any output/evidence"
chmod 644 "$KEYS"; rm -rf "$JEV_STATE_DIR"/*; run_bs k12b
assert_eq "true" "$(jq -r '.key_discovery.perms_warning' "$DET")" "K12 mode 644 => perms_warning true"
assert_eq "644" "$(jq -r '.key_discovery.keys_file_mode' "$DET")" "K12 mode 644 recorded"
# the operator's layout: env -i with only PATH/HOME and the scratch dirs
chmod 600 "$KEYS"; rm -rf "$JEV_STATE_DIR"/* "$JEV_EVIDENCE_DIR"/*
env -i PATH="$PATH" HOME="$HOME" JEV_STATE_DIR="$JEV_STATE_DIR" JEV_CONFIG_DIR="$JEV_CONFIG_DIR" JEV_EVIDENCE_DIR="$JEV_EVIDENCE_DIR" \
  JEV_BOOTSTRAP_HOME="$JEV_BOOTSTRAP_HOME" JEV_CONSTITUTION_ROOT="$JEV_CONSTITUTION_ROOT" STUB_LOG="$STUB_LOG" STUB_EXPECT_KEY="$KEY_A" \
  LLMCTL_STATUS_JSON="$LLMCTL_STATUS_JSON" GIT_SSH_COMMAND=/bin/false \
  bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >"$T/k12c.out" 2>"$T/k12c.err"
assert_eq "hosted-typesafe" "$(jq -r '[.endpoints[]|select(.source=="api-keys-file")|.id]|join(" ")' "$DET")" "K12 env -i + real-HOME layout: endpoint still discovered"
assert_eq "true" "$(jq -r '.key_discovery.keys_file_present' "$DET")" "K12 env -i: keys_file_present true"
assert_eq "600" "$(jq -r '.key_discovery.keys_file_mode' "$DET")" "K12 env -i: mode recorded"
# NEG: no keys file at all => present=false is truthful, vars still listed as absent by name
bare k12d; run_bs k12d
assert_eq "false" "$(jq -r '.key_discovery.keys_file_present' "$DET")" "K12-NEG missing file => keys_file_present false"
assert_eq "absent" "$(jq -r '.key_discovery.vars[]|select(.key_var=="TYPESAFE_API_KEY")|.state' "$DET")" "K12-NEG names are listed (absent) even with no file"

# ---- K16 (review round 2, N1) the source label names where the key REALLY came from -------------------------------------
# a key in the process environment with NO keys file must not be labelled `api-keys-file`; a key in the file keeps
# that label (K12); the key value never reaches any output.
bare k16
export TYPESAFE_API_KEY="$KEY_A"
run_bs k16
assert_rc 0 "$RC" "K16 bootstrap rc 0 with an env-only key"
assert_eq "false" "$(jq -r '.key_discovery.keys_file_present' "$DET")" "K16 precondition: no keys file exists"
assert_eq "hosted-typesafe" "$(jq -r '[.endpoints[]|select(.key_var=="TYPESAFE_API_KEY")|.id]|join(" ")' "$DET")" "K16 the env-sourced key still yields the hosted endpoint"
assert_eq "environment" "$(jq -r '.endpoints[]|select(.id=="hosted-typesafe")|.source' "$DET")" "K16 source says the key came from the process environment"
assert_eq "0" "$(jq -r '[.endpoints[]|select(.source=="api-keys-file")]|length' "$DET")" "K16 nothing is labelled api-keys-file when no keys file exists"
assert_eq "0" "$(leaks "$KEY_A")" "K16 no key value in any output/evidence"
unset TYPESAFE_API_KEY

# ---- K13 wiring gate scans agent config dirs only (it walked the whole HOME: >100 s on a real home) ----------
make_fixture_env k13
mkdir -p "$HOME/.claude" "$HOME/work/a/b/c/d/e/f/g"
jq -n '{endpoints:[{id:"llmctl-x",source:"local-llmctl",model:"decide-x",reachable:true,url:"http://127.0.0.1:1",parallel:1,probed_at:1}]}' > "$T/det.json"
printf '{"x":"llmctl-x"}\n' > "$HOME/work/a/b/c/d/e/f/g/models.json"
JEV_HOME="$HOME" JEV_DETECTION_FILE="$T/det.json" bash "$GATES/cm_jev_wiring.sh" >"$T/k13a.out" 2>&1
assert_not_contains "$T/k13a.out" "clause5: decision endpoint id" "K13 a models.json deep in unrelated project dirs is not scanned (bounded walk)"
printf '{"x":"llmctl-x"}\n' > "$HOME/.claude/models.json"
JEV_HOME="$HOME" JEV_DETECTION_FILE="$T/det.json" bash "$GATES/cm_jev_wiring.sh" >"$T/k13b.out" 2>&1
assert_contains "$T/k13b.out" "clause5: decision endpoint id 'llmctl-x' found" "K13-NEG a decision id inside an agent config dir is still caught"

# ---- K14 per-call timeouts: a tool or gate that never answers must not hang bootstrap -------------------------------
bare k14
mkdir -p "$T/hang"; printf '%s\n' '#!/usr/bin/env bash' 'sleep 300' > "$T/hang/llmctl"; chmod +x "$T/hang/llmctl"
export PATH="$T/hang:$PATH" JEV_TOOL_TIMEOUT=2
st=$(date +%s); run_bs k14; el=$(( $(date +%s) - st ))
assert_rc 0 "$RC" "K14 bootstrap completes (rc 0) with an llmctl that never answers"
if [ "$el" -lt 40 ]; then ok "K14 bounded: finished in ${el}s (< 40s) with a hanging llmctl"; else fail "K14 took ${el}s with a hanging llmctl"; fi
assert_contains "$T/k14.err" "timed out" "K14 the timeout is reported, not silent"
unset JEV_TOOL_TIMEOUT
# a hanging gate
bare k14g; mkdir -p "$T/constitution/scripts/gates"
printf '%s\n' '#!/usr/bin/env bash' 'sleep 300' > "$T/constitution/scripts/gates/cm_jev_detection.sh"
export JEV_GATE_TIMEOUT=2
st=$(date +%s); run_bs k14g; el=$(( $(date +%s) - st ))
assert_rc 0 "$RC" "K14 bootstrap completes with a gate that never returns"
if [ "$el" -lt 40 ]; then ok "K14 bounded: finished in ${el}s with a hanging gate"; else fail "K14 gate hang took ${el}s"; fi
assert_contains "$T/k14g.err" "gate cm_jev_detection: TIMEOUT" "K14 the hanging gate is reported as TIMEOUT"
unset JEV_GATE_TIMEOUT

# ---- K15 the gate says how to supply the probe, and the docs give the exact rerun command -------------------------------
env -u JEV_PROBE_CMD JEV_DETECTION_FILE="$GOOD" bash "$GATES/cm_jev_detection.sh" >"$T/k15.out" 2>&1
assert_contains "$T/k15.out" "scripts/jev/jev-probe.sh" "K15 the no-probe failure names jev-probe.sh"
assert_contains "$T/k15.out" "JEV_PROBE_CMD=" "K15 and shows the exact env assignment to use"
assert_contains "$REPO/docs/jev/bootstrap-reference.md" "JEV_PROBE_CMD=" "K15 bootstrap-reference documents the one-line rerun"
finish
