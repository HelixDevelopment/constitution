#!/usr/bin/env bash
# test_decision_layer_gaps.sh — regression tests for the 2026-10-24 live-validation
# findings (all against stubs; payloads built with jq -n, never heredocs):
#   G1  externally started decide engines that llmctl's registry lists healthy are
#       detected although .profiles[].running is false (running = scheduler-managed)
#   G2  cm_jev_detection FAILs an empty endpoints array when llmctl contradicts it;
#       a lawful reasoned-empty record still passes when llmctl reports nothing
#   G3  the report stage runs the gates against THE detection file of this run, and
#       cm_jev_detection never prints `cd: .jev: No such file` for an absent record
#   G4  cm_jev_token_reduction is BLIND (rc 2) without a real pair; bootstrap reports
#       BLIND (not PASS); no `ok clause N` line follows a FAIL of the same clause
#   I2  gateway URL comes from llmctl's registry / env, and `reachable` is PROBED
#   I3  run_all.sh unsets ambient tool-location overrides (hostile-env run)
#   I4  a profile whose protocol is jev-verdict (no driver) is never decision capacity
#   I5  cm_jev_wiring reads the env file from JEV_CONFIG_DIR when it is relocated
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq curl python3; do
  command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }
done
GATES="$REPO/scripts/gates"

run_bs() { # run_bs <name> [args]  -> RC, DET, $T/<name>.err
  local n="$1"; shift
  bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive "$@" >"$T/$n.out" 2>"$T/$n.err"
  RC=$?; DET="$JEV_EVIDENCE_DIR/jev-detection.json"
}
# mk_status <out> <gw-running> <gw-url-or-empty> <registry-json> <profiles-json>
mk_status() {
  jq -n --argjson run "$2" --arg url "$3" --argjson reg "$4" --argjson prof "$5" \
    '{profiles:$prof, gateway:{available:true,running:$run,detail:"llmctl decide gateway: running pid 1, up 1h"},
      registry:{services:(($reg) + (if $url=="" then [] else [{name:"decide-gateway",protocol:"http",healthy:true,url:$url,labels:{kind:"gateway",profile:"decide"}}] end))}}' > "$1"
}
prof_list() { # prof_list name:running ...
  local p out="[]"; for p in "$@"; do out="$(jq -c --arg n "${p%%:*}" --argjson r "${p##*:}" '. + [{profile:$n,running:$r,enabled:false}]' <<<"$out")"; done; printf '%s' "$out"
}
svc() { # svc <name> <kind> <profile> <healthy> <url>
  jq -nc --arg n "$1" --arg k "$2" --arg p "$3" --argjson h "$4" --arg u "$5" \
    '{name:$n,protocol:"http",healthy:$h,url:$u,labels:{kind:$k,profile:$p}}'
}

# ---- stub gateway so probes have something real to hit ------------------------
make_fixture_env g1
make_fixture_constitution_root with-submodules
nice -n 10 python3 "$FIXTURES/jev_server.py" 0 >"$T/srv.port" 2>/dev/null & SRV=$!
trap 'kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do grep -q '^PORT ' "$T/srv.port" 2>/dev/null && break; sleep 0.1; done
PORT="$(sed -n 's/^PORT //p' "$T/srv.port" | head -1)"
[ -n "$PORT" ] || { fail "stub gateway did not start"; finish; exit $?; }
BASE="http://127.0.0.1:$PORT"

# ---- G1: registry-healthy decide service, profiles all running=false -----------
REG="$( { svc decide-nli decide decide-nli true "http://127.0.0.1:9"; svc decide-julia decide decide-julia false "http://127.0.0.1:8103"; svc some-llm llm decide-x true "http://127.0.0.1:9"; } | jq -sc '.')"
mk_status "$T/status.json" true "$BASE" "$REG" "$(prof_list decide-nli:false decide-julia:false)"
export LLMCTL_STATUS_JSON="$T/status.json"
run_bs g1
assert_rc 0 "$RC" "G1 bootstrap rc 0"
assert_eq "llmctl-decide-nli" "$(jq -r '[.endpoints[].id]|join(" ")' "$DET")" "G1 healthy registry decide service detected; unhealthy and non-decide services are NOT"
assert_eq "http://127.0.0.1:9" "$(jq -r '.endpoints[0].url' "$DET")" "G1 the service's own URL is recorded"
# NEG: registry says nothing healthy -> still honestly empty (no invention)
mk_status "$T/status.json" true "$BASE" "$(svc decide-nli decide decide-nli false 'http://127.0.0.1:9' | jq -sc '.')" "$(prof_list decide-nli:false)"
run_bs g1n
assert_eq "0" "$(jq '.endpoints|length' "$DET")" "G1-NEG unhealthy registry service is not an endpoint"
# no duplicate when the scheduler also reports the profile running
mk_status "$T/status.json" true "$BASE" "$(svc decide-nli decide decide-nli true 'http://127.0.0.1:9' | jq -sc '.')" "$(prof_list decide-nli:true)"
run_bs g1d
assert_eq "1" "$(jq '[.endpoints[]|select(.id=="llmctl-decide-nli")]|length' "$DET")" "G1 profile reported by both profiles[] and registry yields ONE endpoint"

# ---- I2: gateway URL + probed reachability --------------------------------------
make_fixture_env i2
make_fixture_constitution_root with-submodules
mk_status "$T/status.json" true "$BASE" "[]" "$(prof_list decide-laya:true)"
export LLMCTL_STATUS_JSON="$T/status.json"
run_bs i2a
assert_eq "$BASE" "$(jq -r '.endpoints[0].url' "$DET")" "I2 gateway URL taken from llmctl's registry (non-default port)"
assert_eq "true" "$(jq -r '.endpoints[0].reachable' "$DET")" "I2 reachable=true because the URL really answered /healthz"
assert_eq "probe" "$(jq -r '.endpoints[0].reachable_basis' "$DET")" "I2 reachable_basis=probe"
# NEG: gateway 'running' per llmctl but nothing listens at the URL -> NOT claimed reachable
mk_status "$T/status.json" true "http://127.0.0.1:1" "[]" "$(prof_list decide-laya:true)"
run_bs i2b
assert_eq "false" "$(jq -r '.endpoints[0].reachable' "$DET")" "I2-NEG running-but-unreachable gateway is reachable=false (was true from 'running')"
# env fallback when llmctl status carries no URL at all
jq -n '{profiles:[{profile:"decide-laya",running:true}],gateway:{running:true,detail:"running pid 1"}}' > "$T/status.json"
LLMCTL_ENDPOINT="$BASE" run_bs i2c
assert_eq "$BASE" "$(jq -r '.endpoints[0].url' "$DET")" "I2 LLMCTL_ENDPOINT env supplies the URL when status has none"
assert_eq "true" "$(jq -r '.endpoints[0].reachable' "$DET")" "I2 env-supplied URL probed reachable"
run_bs i2d
assert_eq "https://127.0.0.1:8095" "$(jq -r '.endpoints[0].url' "$DET")" "I2 documented default only as last resort"
assert_eq "false" "$(jq -r '.endpoints[0].reachable' "$DET")" "I2-NEG default port with nothing listening is reachable=false"

# ---- I4: jev-verdict profile has no driver: never capacity ----------------------
make_fixture_env i4
make_fixture_constitution_root with-submodules
mk_status "$T/status.json" true "$BASE" "[]" "$(prof_list decide-tiny:true)"
jq -n '{decision_instances:{"decide-tiny":{instances_gpu:0,instances_cpu:1,effective_slots_per_instance:2,protocol:"jev-verdict"}}}' > "$T/cap.json"
export LLMCTL_STATUS_JSON="$T/status.json" LLMCTL_CAPACITY_JSON="$T/cap.json"
run_bs i4
assert_eq "0" "$(jq '.endpoints|length' "$DET")" "I4 running decide-tiny (protocol jev-verdict, no driver) is NOT an endpoint"
assert_eq "0" "$(jq '.capacity.parallel_total' "$DET")" "I4 and contributes no parallel capacity"
assert_contains "$DET" "no driver" "I4 the evidence says why (protocol jev-verdict has no driver)"
jq -n '{decision_instances:{"decide-tiny":{instances_cpu:1,effective_slots_per_instance:2,protocol:"systemone-native"}}}' > "$T/cap.json"
run_bs i4b
assert_eq "1" "$(jq '.endpoints|length' "$DET")" "I4-NEG same profile with a native protocol IS an endpoint (exclusion is by protocol, not by name)"

# ---- G2: gate contradiction check -----------------------------------------------
make_fixture_env g2
make_fixture_constitution_root with-submodules
EMPTY="$T/empty-det.json"
jq -n --arg p "$T" '{version:1,generated_at:1700000000,endpoints:[],reason:"no decide profile is running and the toolkit endpoint cache is empty",
  capacity:{instances:0,decision_instances:0,parallel_total:0},
  tools:{llmctl:{source:"unavailable",ref:"x",path:"",reason:"t"},claude_toolkit:{source:"unavailable",ref:"x",path:"",reason:"t"}}}' > "$EMPTY"
mk_status "$T/status.json" true "$BASE" "$(svc decide-nli decide decide-nli true 'http://127.0.0.1:9' | jq -sc '.')" "$(prof_list decide-nli:false)"
export LLMCTL_STATUS_JSON="$T/status.json"
JEV_DETECTION_FILE="$EMPTY" bash "$GATES/cm_jev_detection.sh" >"$T/g2a.out" 2>&1; rc=$?
assert_nonzero "$rc" "G2 empty endpoints + llmctl reports a healthy decide service => gate FAILs"
assert_contains "$T/g2a.out" "contradict" "G2 the failure names the llmctl contradiction"
mk_status "$T/status.json" true "$BASE" "[]" "$(prof_list decide-nli:false)"
JEV_DETECTION_FILE="$EMPTY" bash "$GATES/cm_jev_detection.sh" >"$T/g2b.out" 2>&1; rc=$?
assert_rc 0 "$rc" "G2 empty endpoints + llmctl says only the gateway is running (no usable decision profile) => lawful, gate passes (review I1; the contradiction is a running USABLE profile, see test_review_fixes.sh)"
mk_status "$T/status.json" false "" "[]" "$(prof_list decide-nli:false)"
JEV_DETECTION_FILE="$EMPTY" bash "$GATES/cm_jev_detection.sh" >"$T/g2c.out" 2>&1; rc=$?
assert_rc 0 "$rc" "G2-NEG lawful reasoned-empty record PASSes when llmctl reports nothing running"
( export PATH="$T/nobin:/usr/bin:/bin"; mkdir -p "$T/nobin"; JEV_DETECTION_FILE="$EMPTY" bash "$GATES/cm_jev_detection.sh" >"$T/g2d.out" 2>&1 ); rc=$?
assert_rc 0 "$rc" "G2-NEG llmctl absent: reasoned-empty record still passes (contradiction unverifiable, noted)"
assert_contains "$T/g2d.out" "NOTE" "G2 llmctl-absent case is NOTEd, not silent"

# ---- G3: absent record must not leak a cd error; report uses this run's file ----
mkdir -p "$T/cwd"
( cd "$T/cwd" && bash "$GATES/cm_jev_detection.sh" >"$T/g3a.out" 2>&1 ); rc=$?
assert_nonzero "$rc" "G3 absent record => gate FAILs"
assert_not_contains "$T/g3a.out" "cd:" "G3 no 'cd: .jev: No such file' noise from the gate"
assert_contains "$T/g3a.out" "detection record missing" "G3 the real reason is reported"

make_fixture_env g3
make_fixture_constitution_root with-submodules
mkdir -p "$T/constitution/scripts"; ln -s "$GATES" "$T/constitution/scripts/gates"   # report stage runs the REAL gates
mk_status "$T/status.json" true "$BASE" "[]" "$(prof_list decide-laya:true)"
export LLMCTL_STATUS_JSON="$T/status.json"
mkdir -p "$T/elsewhere"
( cd "$T/elsewhere" && run_bs g3 )
RC=$?; DET="$JEV_EVIDENCE_DIR/jev-detection.json"
assert_contains "$T/g3.err" "gate cm_jev_detection: PASS" "G3 report-stage detection gate PASSes against this run's record from a foreign cwd"

# ---- G4: token gate BLIND without a real pair; honest report --------------------
mkdir -p "$T/cwd"
( cd "$T/cwd" && env -u JEV_BEFORE -u JEV_AFTER bash "$GATES/cm_jev_token_reduction.sh" >"$T/g4a.out" 2>&1 ); rc=$?
assert_rc 2 "$rc" "G4 no real BEFORE/AFTER pair configured => BLIND (rc 2), not GREEN on synthetic fixtures"
assert_contains "$T/g4a.out" "BLIND" "G4 the output says BLIND"
assert_contains "$T/g3.err" "gate cm_jev_token_reduction: BLIND" "G4 bootstrap reports BLIND for the token gate"
assert_not_contains "$T/g3.err" "gate cm_jev_token_reduction: PASS" "G4 bootstrap does not print PASS for the token gate from fixtures"
# no `ok clause N` after a FAIL of the same clause
JEV_BEFORE="$T/missing-b.jsonl" JEV_AFTER="$T/missing-a.jsonl" JEV_DECISIONS="$T/missing-d.jsonl" bash "$GATES/cm_jev_token_reduction.sh" >"$T/g4b.out" 2>&1; rc=$?
assert_rc 1 "$rc" "G4 missing artifacts => RED"
assert_not_contains "$T/g4b.out" "ok: clause 1" "G4 no 'ok: clause 1' line after the clause-1 FAIL"
# explicit real pair still GREEN
JEV_BEFORE="$GATES/fixtures/jev/evidence/before.jsonl" JEV_AFTER="$GATES/fixtures/jev/evidence/after.jsonl" JEV_DECISIONS="$GATES/fixtures/jev/evidence/decisions.jsonl" \
  JEV_BEFORE_CONFIG="$GATES/fixtures/jev/evidence/before.config" JEV_AFTER_CONFIG="$GATES/fixtures/jev/evidence/after.config" \
  bash "$GATES/cm_jev_token_reduction.sh" >"$T/g4c.out" 2>&1; rc=$?
assert_rc 0 "$rc" "G4-NEG an explicitly configured pair is still evaluated (GREEN)"

# ---- I5: wiring gate reads JEV_CONFIG_DIR/env ------------------------------------
make_fixture_env i5
RELOC="$T/relocated-config"; mkdir -p "$RELOC"; printf 'JEV_MODE=shadow\n' > "$RELOC/env"
rm -f "$HOME/.config/jev/env"
JEV_HOME="$HOME" JEV_CONFIG_DIR="$RELOC" JEV_DETECTION_FILE="$T/none.json" bash "$GATES/cm_jev_wiring.sh" >"$T/i5a.out" 2>&1
assert_contains "$T/i5a.out" "clause 3: env exports present" "I5 env file found in the relocated JEV_CONFIG_DIR"
JEV_HOME="$HOME" JEV_CONFIG_DIR="$T/empty-cfg" JEV_DETECTION_FILE="$T/none.json" bash "$GATES/cm_jev_wiring.sh" >"$T/i5b.out" 2>&1
assert_not_contains "$T/i5b.out" "clause 3: env exports present" "I5-NEG relocated dir without env: clause 3 not satisfied by a stale default"

# ---- I3: run_all.sh scrubs ambient overrides --------------------------------------
make_fixture_env i3
RT="$T/rt"; mkdir -p "$RT"
cp "$HERE/run_all.sh" "$RT/run_all.sh"
# the probe's own output lives in $HOME/out.1 of run_all's throwaway HOME, which is gone; so make it fail loudly instead
printf '#!/usr/bin/env bash\nleak="$(env | grep -E "^(LLMCTL_DIR|CLAUDE_TOOLKIT_DIR|LLMCTL_ENDPOINT|LLMCTL_CACERT|JEV_API_KEYS_FILE|TYPESAFE_API_KEY|OPENROUTER_API_KEY|LLMCTL_API_KEY|JEV_MODE|JEV_GATE|JEV_KEY_VAR)=" | cut -d= -f1 | tr "\\n" " ")"\n[ -z "$leak" ] || { echo "FAIL leaked: $leak"; exit 1; }\nexit 0\n' > "$RT/test_envprobe.sh"
LLMCTL_DIR=/nonexistent CLAUDE_TOOLKIT_DIR=/nonexistent LLMCTL_ENDPOINT=http://x LLMCTL_CACERT=/x JEV_API_KEYS_FILE=/x \
  TYPESAFE_API_KEY=a OPENROUTER_API_KEY=b LLMCTL_API_KEY=c JEV_MODE=enforce JEV_GATE=on JEV_KEY_VAR=z \
  bash "$RT/run_all.sh" >"$T/i3.out" 2>&1; rc=$?
assert_rc 0 "$rc" "I3 hostile-env run: no ambient tool-location / key / mode variable reaches a test"
assert_contains "$T/i3.out" "PASS test_envprobe.sh" "I3 the probe test actually ran (non-vacuous)"
finish
