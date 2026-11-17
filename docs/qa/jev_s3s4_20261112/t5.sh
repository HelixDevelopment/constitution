#!/usr/bin/env bash
# T5 live placement run: real llmctl capacity + start/stop of ONE systemone-native decide profile through jev-place.sh,
# lease held by a sleep process this script owns; Jev state in a sandbox. Never enable/disable/switch/auto.
set -uo pipefail
R="${1:?repo}"; S="${2:?sandbox}"; P="${3:-decide-kev-08b}"; mkdir -p "$S"
export JEV_STATE_DIR="$S/state" JEV_CONFIG_DIR="$S/config" JEV_EVIDENCE_DIR="$S/ev" CMA_PROVIDERS_DIR="$S/prov" JEV_PLACE_PROFILES="$P"
PL="$R/scripts/jev/jev-place.sh"
sleep 900 & HP=$!
u() { systemctl --user show -p ActiveState,SubState,MainPID "llmctl-llama@$P.service" 2>/dev/null | tr "\n" " "; }
{ echo "unit_before: $(u)"
  timeout 600 bash "$PL" acquire t5holder --pid "$HP" > "$S/acq.out" 2> "$S/acq.err"; echo "acquire_rc: $?"
  echo "unit_after_acquire: $(u)"
  # placement.json nests its fields under .placement (review 2026-11-12 F6: the first capture read the top level and got
  # nulls); the control needle proves the file was readable before its fields are believed
  echo "placement_control: $(jq -r 'if (.placement|type) == "object" then "placement-object-present" else "PLACEMENT-OBJECT-ABSENT" end' "$JEV_STATE_DIR/placement.json" 2>/dev/null || echo PLACEMENT-UNREADABLE)"
  echo "placement: $(jq -c '.placement | {profile,verdict,event,route,constitution_started,reason}' "$JEV_STATE_DIR/placement.json" 2>/dev/null)"
  echo "leases: $(jq -c '.sets' "$JEV_STATE_DIR/leases.json" 2>/dev/null)"
  echo "cache: $(jq -c '[.endpoints[]?|select(.provider_id=="llmctl-local")|{provider_id,priority,base_url,model}]' "$CMA_PROVIDERS_DIR/jev-endpoints.json" 2>/dev/null)"
  timeout 600 bash "$PL" release t5holder > "$S/rel.out" 2> "$S/rel.err"; echo "release_rc: $?"
  echo "unit_after_release: $(u)"
  echo "leases_after: $(jq -c '.sets' "$JEV_STATE_DIR/leases.json" 2>/dev/null)"
  echo "cache_after: $(jq -c '[.endpoints[]?|select(.provider_id=="llmctl-local")]|length' "$CMA_PROVIDERS_DIR/jev-endpoints.json" 2>/dev/null)"
} > "$S/t5.txt" 2>&1
[ "$(cat /proc/$HP/comm 2>/dev/null)" = sleep ] && kill "$HP"; wait "$HP" 2>/dev/null; true
