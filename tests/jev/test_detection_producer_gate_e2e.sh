#!/usr/bin/env bash
# test_detection_producer_gate_e2e.sh — end-to-end: the REAL scripts/jev/bootstrap.sh
# produces jev-detection.json, then the REAL scripts/gates/cm_jev_detection.sh judges
# it. The producer/gate contract (§11.4.279(D)):
#   (a) capacity.decision_instances is a number equal to capacity.instances
#   (b) tools.<t>.source in {submodule, clone, explicit, unavailable}; unavailable
#       carries a non-empty reason
#   (c) endpoints[].reachable is true|false|null (null = not probed); a claimed
#       reachable endpoint carries .url so a probe can replay it
#   (d) toolkit-cache endpoints keep reachable:null + reachable_basis:"resolution-only"
# Offline, isolated HOME, GIT_SSH_COMMAND=/bin/false (set by make_fixture_env), every
# run under `timeout`. The probe command is a local stub standing in for a live probe.
#   E1 default (no consent, no submodules): degraded-but-honest record -> gate rc 0
#   E2 submodule fixtures: full provenance -> gate rc 0
#   E3 negative controls: a mutated record MUST make the gate fail
#   E4 no network was attempted and no managed-clone dir was created without consent
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"   # used by lib_assert helpers
export FIXTURES
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh disable=SC1091
source "$HERE/lib_assert.sh"
command -v jq >/dev/null 2>&1 || { assert_skip "jq absent: e2e skipped (bootstrap needs jq, rc 2)"; finish; exit $?; }

GATE="$REPO/scripts/gates/cm_jev_detection.sh"
assert_file_exists "$GATE" "gate present"

# shellcheck disable=SC2016  # the probe script body must stay literal
make_probe() { # a probe stub: exit 0 for the recorded local endpoint url
  printf '#!/usr/bin/env bash\n[ -n "${2:-}" ] && exit 0\nexit 1\n' > "$T/probe.sh"; chmod +x "$T/probe.sh"
}
run_gate() { # run_gate <detection.json> -> GATE_RC, output in $T/gate.out
  JEV_DETECTION_FILE="$1" JEV_PROBE_CMD="$T/probe.sh" JEV_FIXTURE_ROOT="$T" \
    timeout 60 bash "$GATE" >"$T/gate.out" 2>&1
  GATE_RC=$?
}

# ---- E1: default run, no consent for provisioning ----
make_fixture_env e1; make_fixture_constitution_root; make_probe
timeout 120 bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >"$T/b.out" 2>"$T/b.err"
assert_rc 0 "$?" "E1 bootstrap rc 0 (fail-open without consent)"
DET="$JEV_EVIDENCE_DIR/jev-detection.json"
assert_file_exists "$DET" "E1 detection written"
assert_eq "unavailable" "$(jq -r '.tools.llmctl.source' "$DET")" "E1 llmctl source=unavailable"
assert_eq "true" "$(jq -r '.tools.llmctl.reason|type=="string" and length>0' "$DET")" "E1 unavailable carries a non-empty reason"
assert_eq "true" "$(jq -r '.capacity.decision_instances|type=="number"' "$DET")" "E1 capacity.decision_instances is a number"
assert_eq "$(jq -r '.capacity.instances' "$DET")" "$(jq -r '.capacity.decision_instances' "$DET")" "E1 decision_instances == instances"
assert_eq "true" "$(jq -r '[.endpoints[]|select(.reachable==true)|.url|type=="string" and length>0]|all' "$DET")" "E1 claimed-reachable endpoints carry .url"
assert_contains "$JEV_STATE_DIR/bootstrap.pending" "provision requires consent" "E1 pending reason recorded"
run_gate "$DET"
assert_rc 0 "$GATE_RC" "E1 gate cm_jev_detection accepts the degraded-but-honest record (real gate rc)"

# ---- E4 (same run): no network, no out-of-tree clone dir ----
assert_file_absent "$JEV_BOOTSTRAP_HOME" "E4 no managed-clone dir created without consent"

# ---- E2: submodule fixtures + cache endpoint ----
make_fixture_env e2; make_fixture_constitution_root with-submodules; make_probe
printf '{"version":1,"endpoints":[{"provider_id":"jev-openrouter","base_url":"https://openrouter.ai/api","model":"jev-latest","key_var":"OPENROUTER_API_KEY"}]}\n' > "$T/endpoints.json"
export FIXTURE_ENDPOINTS="$T/endpoints.json"   # the claude-providers stub copies it into the cache
timeout 120 bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >"$T/b.out" 2>"$T/b.err"
assert_rc 0 "$?" "E2 bootstrap rc 0"
DET="$JEV_EVIDENCE_DIR/jev-detection.json"
assert_eq "submodule" "$(jq -r '.tools.claude_toolkit.source' "$DET")" "E2 toolkit source=submodule"
assert_eq "null" "$(jq -r '.endpoints[]|select(.source=="toolkit-cache")|.reachable' "$DET")" "E2 cache endpoint reachable:null"
assert_eq "resolution-only" "$(jq -r '.endpoints[]|select(.source=="toolkit-cache")|.reachable_basis' "$DET")" "E2 cache endpoint basis=resolution-only"
run_gate "$DET"
assert_rc 0 "$GATE_RC" "E2 gate accepts the full record (real gate rc)"

# ---- E3: negative controls (the gate must NOT pass a broken record) ----
jq '.tools.llmctl.source="vendored"' "$DET" > "$T/n1.json"; run_gate "$T/n1.json"
assert_nonzero "$GATE_RC" "E3a unknown tool source is rejected"
jq '.endpoints[0].reachable="yes"' "$DET" > "$T/n2.json"; run_gate "$T/n2.json"
assert_nonzero "$GATE_RC" "E3b non-boolean/null reachable is rejected"
jq '.tools.llmctl.source="unavailable" | .tools.llmctl.reason=""' "$DET" > "$T/n3.json"; run_gate "$T/n3.json"
assert_nonzero "$GATE_RC" "E3c unavailable without a reason is rejected"
jq 'del(.capacity.decision_instances)' "$DET" > "$T/n4.json"; run_gate "$T/n4.json"
assert_nonzero "$GATE_RC" "E3d missing capacity.decision_instances is rejected"
finish
