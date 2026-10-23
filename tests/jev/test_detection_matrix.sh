#!/usr/bin/env bash
# test_detection_matrix.sh — provider / local-instance detection matrix, all
# against stubs (no real provider, no real credential, loopback only, no
# network: GIT_SSH_COMMAND=/bin/false):
#   M1 local llmctl gateway on loopback (real HTTP stub) + Kev / Laya / Verdict
#      profiles running; stopped profiles are NOT listed; parallel from capacity
#   M2 hosted TypeSafe + OpenRouter via the toolkit endpoint cache
#      ($CMA_PROVIDERS_DIR/jev-endpoints.json, fields provider_id/base_url/model/
#      key_var). Keys are referenced by env var NAME only; the env vars hold
#      DUMMY placeholders and the placeholder VALUE must reach no file at all
#   M3 mixed local + hosted
#   M4 hosted reachability is null (unknown) — never claimed reachable
#   M5 nothing available: empty endpoints + explicit reason (lawful, rc 0)
#   M6 model download is consent-gated (JEV_BOOTSTRAP_DOWNLOAD_PROFILE) and
#      capacity-gated; never silent
#   M7 REAL llmctl schema (decision_instances as object keyed by profile):
#      no fabricated "null" endpoints
#   M8 llmctl absent: not invented
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
command -v jq >/dev/null 2>&1 || { assert_skip "jq absent: detection matrix skipped (bootstrap itself needs jq, rc 2)"; finish; exit $?; }

DUMMY_A="DUMMY-PLACEHOLDER-aaaa-not-a-real-key"
DUMMY_B="DUMMY-PLACEHOLDER-bbbb-not-a-real-key"

run_case() { # run_case <name> [extra bootstrap args]
  local n="$1"; shift
  bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive "$@" >"$T/$n.out" 2>"$T/$n.err"
  RC=$?; DET="$JEV_EVIDENCE_DIR/jev-detection.json"
}
no_secret_in_outputs() { # no_secret_in_outputs <msg>
  local hits
  hits="$(grep -rlF -e "$DUMMY_A" -e "$DUMMY_B" "$T" "$HOME" 2>/dev/null | tr '\n' ' ')"
  assert_eq "" "$hits" "$1: placeholder credential VALUE appears in no output/state/evidence file"
}
status_json() { # status_json <outfile> <running-profile>...   (stopped: prefix '!')
  local out="$1"; shift; local items="" p run
  for p in "$@"; do run=true; case "$p" in !*) run=false; p="${p#!}";; esac
    items="${items:+$items,}{\"profile\":\"$p\",\"running\":$run}"; done
  printf '{"gateway":{"running":true},"profiles":[%s]}\n' "$items" > "$out"
}

# ---- M1 ---------------------------------------------------------------------
make_fixture_env m1
make_fixture_constitution_root with-submodules
nice -n 10 python3 "$FIXTURES/jev_server.py" 0 >"$T/srv.port" 2>/dev/null & SRV=$!
trap 'kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do grep -q '^PORT ' "$T/srv.port" 2>/dev/null && break; sleep 0.1; done
PORT="$(sed -n 's/^PORT //p' "$T/srv.port" | head -1)"
[ -n "$PORT" ] || { fail "M1 stub gateway did not start"; finish; exit $?; }
curl -fsS --max-time 3 "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; assert_rc 0 "$?" "M1 loopback gateway stub reachable"
status_json "$T/status.json" decide-kev-08b decide-laya decide-verdict '!decide-max'
cat > "$T/cap.json" <<'JSON'
{"decision_instances":{
 "decide-kev-08b":{"instances_gpu":2,"instances_cpu":0,"effective_slots_per_instance":2},
 "decide-laya":{"instances_gpu":2,"instances_cpu":4,"effective_slots_per_instance":4},
 "decide-verdict":{"instances_gpu":0,"instances_cpu":1,"effective_slots_per_instance":1},
 "decide-max":{"instances_gpu":1,"instances_cpu":0,"effective_slots_per_instance":9}}}
JSON
export LLMCTL_STATUS_JSON="$T/status.json" LLMCTL_CAPACITY_JSON="$T/cap.json"
run_case m1
assert_rc 0 "$RC" "M1 bootstrap rc 0"
assert_eq "llmctl-decide-kev-08b llmctl-decide-laya llmctl-decide-verdict" "$(jq -r '[.endpoints[].id]|join(" ")' "$DET")" "M1 Kev, Laya, Verdict profiles detected; stopped decide-max NOT listed"
assert_eq "local-llmctl" "$(jq -r '[.endpoints[].source]|unique|join(",")' "$DET")" "M1 all sourced local-llmctl"
assert_eq "2 4 1" "$(jq -r '[.endpoints[].parallel]|join(" ")' "$DET")" "M1 per-profile parallelism = effective_slots_per_instance"
assert_eq "3" "$(jq -r '.capacity.instances' "$DET")" "M1 capacity.instances == endpoint count"
assert_eq "7" "$(jq -r '.capacity.parallel_total' "$DET")" "M1 capacity.parallel_total == sum of parallelism"
assert_eq "null" "$(jq -r '.reason' "$DET")" "M1 no absence reason when endpoints exist"
# NEG: a profile that stops is dropped on the next run (detection tracks reality)
status_json "$T/status.json" '!decide-kev-08b' decide-laya
run_case m1b
assert_eq "llmctl-decide-laya" "$(jq -r '[.endpoints[].id]|join(" ")' "$DET")" "M1-NEG: after kev stops, only laya remains (stage re-ran: status is part of the key)"

# ---- M2 ---------------------------------------------------------------------
make_fixture_env m2
make_fixture_constitution_root with-submodules
export JEV_TEST_TYPESAFE_KEY="$DUMMY_A" JEV_TEST_OPENROUTER_KEY="$DUMMY_B"
cat > "$T/endpoints.json" <<'JSON'
{"endpoints":[
 {"provider_id":"typesafe-hosted","base_url":"https://typesafe.example.invalid/v1","model":"jev-hosted","key_var":"JEV_TEST_TYPESAFE_KEY"},
 {"provider_id":"openrouter-hosted","base_url":"https://openrouter.example.invalid/api/v1","model":"jev-or","key_var":"JEV_TEST_OPENROUTER_KEY"}]}
JSON
export FIXTURE_ENDPOINTS="$T/endpoints.json"
status_json "$T/status.json"; echo '{"gateway":{"running":false},"profiles":[]}' > "$T/status.json"
export LLMCTL_STATUS_JSON="$T/status.json"
run_case m2
assert_rc 0 "$RC" "M2 bootstrap rc 0"
assert_eq "typesafe-hosted openrouter-hosted" "$(jq -r '[.endpoints[].id]|join(" ")' "$DET")" "M2 both hosted providers detected from the endpoint cache"
assert_eq "toolkit-cache" "$(jq -r '[.endpoints[].source]|unique|join(",")' "$DET")" "M2 provenance source = toolkit-cache"
assert_eq "jev-hosted jev-or" "$(jq -r '[.endpoints[].model]|join(" ")' "$DET")" "M2 models preserved"
assert_contains "$STUB_LOG/claude-providers.log" "sync-jev" "M2 detection refreshed the cache through claude-providers sync-jev"
assert_file_exists "$CMA_PROVIDERS_DIR/jev-endpoints.json" "M2 cache lives at \$CMA_PROVIDERS_DIR/jev-endpoints.json"
no_secret_in_outputs "M2"
# the detection must not even carry key_var values: names are fine, values never
assert_not_contains "$DET" "$DUMMY_A" "M2 detection evidence holds no key value"

# ---- M3 mixed ---------------------------------------------------------------
make_fixture_env m3
make_fixture_constitution_root with-submodules
status_json "$T/status.json" decide-kev-08b
printf '{"decision_instances":{"decide-kev-08b":{"instances_gpu":1,"instances_cpu":0,"effective_slots_per_instance":3}}}\n' > "$T/cap.json"
cat > "$T/endpoints.json" <<'JSON'
{"endpoints":[{"provider_id":"typesafe-hosted","base_url":"https://typesafe.example.invalid/v1","model":"jev-hosted","key_var":"JEV_TEST_TYPESAFE_KEY"}]}
JSON
export LLMCTL_STATUS_JSON="$T/status.json" LLMCTL_CAPACITY_JSON="$T/cap.json" FIXTURE_ENDPOINTS="$T/endpoints.json"
run_case m3
assert_eq "2" "$(jq '.endpoints|length' "$DET")" "M3 one local + one hosted endpoint"
assert_eq "3" "$(jq -r '.endpoints[]|select(.source=="local-llmctl")|.parallel' "$DET")" "M3 local instance carries parallel=3"
hp="$(jq -r '.endpoints[]|select(.source=="toolkit-cache")|.parallel' "$DET")"
if [ "$hp" -lt 3 ] 2>/dev/null; then ok "M3 hosted endpoint does not inherit local parallelism (parallel=$hp)"; else fail "M3 hosted parallel [$hp] inherited/invalid"; fi
no_secret_in_outputs "M3"

# ---- M4 reachability is unknown, never fabricated -----------------------------
assert_eq "null" "$(jq -r '.endpoints[]|select(.source=="toolkit-cache")|.reachable' "$DET")" "M4 hosted reachable=null (cache records resolution, not a probe)"
assert_eq "true" "$(jq -r '.endpoints[]|select(.source=="local-llmctl")|.reachable' "$DET")" "M4 local reachable=true only because the gateway reports running"
# NEG: gateway not running => local instance not claimed reachable
echo '{"gateway":{"running":false},"profiles":[{"profile":"decide-kev-08b","running":true}]}' > "$T/status.json"
run_case m4b
assert_eq "false" "$(jq -r '.endpoints[]|select(.source=="local-llmctl")|.reachable' "$DET")" "M4-NEG: gateway down => reachable=false"

# ---- M5 nothing available -------------------------------------------------------
make_fixture_env m5
make_fixture_constitution_root with-submodules
echo '{"gateway":{"running":false},"profiles":[]}' > "$T/status.json"
export LLMCTL_STATUS_JSON="$T/status.json"; unset FIXTURE_ENDPOINTS LLMCTL_CAPACITY_JSON
run_case m5
assert_rc 0 "$RC" "M5 empty detection is lawful (rc 0)"
assert_eq "0" "$(jq '.endpoints|length' "$DET")" "M5 zero endpoints recorded"
assert_ne "null" "$(jq -r '.reason' "$DET")" "M5 absence carries an explicit reason (never silent)"
assert_not_contains "$STUB_LOG/llmctl.log" "models download" "M5 NEG: nothing downloaded without consent"

# ---- M6 download is consent- and capacity-gated -----------------------------------
m6_env() { # m6_env <name> <cap-instances-cpu>  (fresh T, so fixture files are written AFTER it)
  make_fixture_env "$1"; make_fixture_constitution_root with-submodules
  echo '{"gateway":{"running":false},"profiles":[]}' > "$T/status.json"
  printf '{"decision_instances":{"decide-tiny":{"instances_gpu":0,"instances_cpu":%s,"effective_slots_per_instance":1}}}\n' "$2" > "$T/cap.json"
  export LLMCTL_STATUS_JSON="$T/status.json" LLMCTL_CAPACITY_JSON="$T/cap.json"
}
m6_env m6a 1
run_case m6a
assert_not_contains "$STUB_LOG/llmctl.log" "models download" "M6-NEG: capacity fits but NO consent => no download"
m6_env m6b 1
JEV_BOOTSTRAP_DOWNLOAD_PROFILE=decide-tiny run_case m6b
assert_contains "$STUB_LOG/llmctl.log" "models download decide-tiny" "M6 consent + capacity fits => download requested"
assert_file_exists "$JEV_STATE_DIR/bootstrap.pending" "M6 downloaded-but-not-started is recorded as pending"
m6_env m6c 0
JEV_BOOTSTRAP_DOWNLOAD_PROFILE=decide-tiny run_case m6c
assert_not_contains "$STUB_LOG/llmctl.log" "models download" "M6-NEG: consent given but capacity does not fit => no download"
assert_contains "$DET" "does not fit" "M6-NEG: the refusal reason is in the evidence"
JEV_BOOTSTRAP_DOWNLOAD_PROFILE='x;rm -rf' bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >/dev/null 2>&1
assert_rc 2 "$?" "M6-NEG: shell-metacharacter profile name rejected (rc 2)"

# ---- M7 REAL llmctl schema ---------------------------------------------------------
make_fixture_env m7
make_fixture_constitution_root with-submodules
status_json "$T/status.json" decide-kev-08b decide-laya decide-verdict
cat > "$T/cap.json" <<'JSON'
{"tier":"below-minimum",
 "decision_instances":{
  "decide-kev-08b":{"instances_gpu":2,"instances_cpu":0,"per_instance":{"ram_mb":2048,"vram_mb":2900,"slots":1},"total_decision_slots":2,"protocol":"systemone-native","effective_slots_per_instance":1,"tier_ok":true},
  "decide-laya":{"instances_gpu":2,"instances_cpu":4,"per_instance":{"ram_mb":2048,"vram_mb":574,"slots":1},"total_decision_slots":4,"protocol":"systemone-native","effective_slots_per_instance":1,"tier_ok":true},
  "decide-verdict":{"instances_gpu":0,"instances_cpu":1,"per_instance":{"ram_mb":1024,"vram_mb":0,"slots":1},"total_decision_slots":1,"protocol":"systemone-native","effective_slots_per_instance":1,"tier_ok":true}},
 "capacity":{"instances":3}}
JSON
export LLMCTL_STATUS_JSON="$T/status.json" LLMCTL_CAPACITY_JSON="$T/cap.json"
run_case m7
assert_rc 0 "$RC" "M7 bootstrap rc 0 on the real-schema capacity report"
assert_eq "0" "$(jq '[.endpoints[]|select(.id=="null" or .model=="null" or .id==null)]|length' "$DET")" "M7 NEG: no endpoint with id/model null fabricated from the object-shaped report"
assert_eq "3" "$(jq '.endpoints|length' "$DET")" "M7 Kev, Laya and Verdict each yield one endpoint"

# ---- M8 llmctl absent --------------------------------------------------------------
make_fixture_env m8
make_fixture_constitution_root
mkdir -p "$T/nobin"; cp "$FIXTURES/bin/git" "$T/nobin/git"
SAVE_PATH="$PATH"; export PATH="$T/nobin:/usr/bin:/bin"
unset LLMCTL_STATUS_JSON LLMCTL_CAPACITY_JSON FIXTURE_ENDPOINTS
run_case m8
export PATH="$SAVE_PATH"
assert_eq "0" "$(jq '.endpoints|length' "$DET")" "M8 NEG: no toolkit/llmctl on PATH -> endpoints NOT invented"
assert_ne "null" "$(jq -r '.reason' "$DET")" "M8 absence carries an explicit reason"
assert_contains "$DET" "llmctl not found" "M8 reason says llmctl was not found"
finish
