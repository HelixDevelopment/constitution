#!/usr/bin/env bash
# test_jev_status_health.sh — jev-status.sh control view (2026-11-12): per-endpoint health from decisions.jsonl, calibration
# age, consent state, wiring state, placement + leases. GATE-LOGIC test over declared state files (§11.4.289(C)(2)).
#   S1 health: per endpoint total / ok (2xx) / last_success / counts by class; a row with no endpoint is "unknown"
#   S2 calibration age = now - calibrated_at; absent thresholds -> null, never 0
#   S3 consent: consent.json inlined; absent -> null;  S4 wiring: hook found in the agent settings -> wired=true, else false
#   S5 placement + leases inlined;  S6 human view prints every section;  S7 key VALUES never appear in the output
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export FIXTURES="$HERE/fixtures"; REPO="$(cd "$HERE/../.." && pwd)"
source "$HERE/lib_assert.sh"
command -v jq >/dev/null 2>&1 || { assert_skip "jq absent"; finish; exit $?; }
make_fixture_env sh; export JEV_TEST=1 JEV_NOW_EPOCH=1700001000
ST="$REPO/scripts/jev/jev-status.sh"
D="$JEV_STATE_DIR/decisions.jsonl"
{
  echo '{"ts":1700000100,"endpoint":"typesafe","model":"jev-latest","http_status":200,"class":"2xx"}'
  echo '{"ts":1700000200,"endpoint":"typesafe","model":"jev-latest","http_status":200,"class":"2xx"}'
  echo '{"ts":1700000300,"endpoint":"openrouter","model":"typesafe/jev-1.13","http_status":402,"class":"no_credit"}'
  echo '{"ts":1700000400,"endpoint":"openrouter","model":"typesafe/jev-1.13","http_status":402,"class":"no_credit"}'
  echo '{"ts":1700000500,"question":"gate","answer":"yes"}'
} > "$D"
printf '{"version":1,"calibrated_at":1700000400,"per_type":{}}\n' > "$JEV_CONFIG_DIR/jev-thresholds.json"
printf '{"consent":{"default_on":true,"basis":"operator-standing-order-2026-11-12"}}\n' > "$JEV_STATE_DIR/consent.json"
printf '{"placement":{"profile":"decide-kev-08b","verdict":"fits","route":"local"}}\n' > "$JEV_STATE_DIR/placement.json"
printf '{"sets":{"decide-kev-08b":{"constitution_started":true,"stopping":null,"leases":[{"holder":"s1"}]}}}\n' > "$JEV_STATE_DIR/leases.json"
mkdir -p "$HOME/.claude"; printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"/x/jev-gate.sh"}]}]}}\n' > "$HOME/.claude/settings.json"
TYPESAFE_API_KEY="tsk-status-$(date +%N)-value"; export TYPESAFE_API_KEY
bash "$ST" --json --no-validate > "$T/s.json" 2>"$T/s.err"; rc=$?
assert_rc 0 "$rc" "status --json rc 0"
assert_eq "2 2 1700000200" "$(jq -r '.health.typesafe | "\(.total) \(.ok) \(.last_success)"' "$T/s.json")" "S1 typesafe total/ok/last_success"
assert_eq "2 0 null 2" "$(jq -r '.health.openrouter | "\(.total) \(.ok) \(.last_success) \(.by_class.no_credit)"' "$T/s.json")" "S1 openrouter: 2 no_credit, never a success"
assert_eq 1 "$(jq -r '.health.unknown.total' "$T/s.json")" "S1 rows without an endpoint counted as unknown"
assert_eq 600 "$(jq -r '.calibration_age_s' "$T/s.json")" "S2 calibration age = now - calibrated_at"
assert_eq true "$(jq -r '.consent.default_on' "$T/s.json")" "S3 consent inlined"
assert_eq true "$(jq -r '.wiring.claude' "$T/s.json")" "S4 hook found in the agent settings => wired"
assert_eq "local 1" "$(jq -r '"\(.placement.route) \(.leases.sets["decide-kev-08b"].leases|length)"' "$T/s.json")" "S5 placement + leases inlined"
bash "$ST" --no-validate > "$T/h.out" 2>&1
for sec in "Endpoint health" "Calibration" "Consent" "Wiring" "Placement"; do assert_contains "$T/h.out" "$sec" "S6 human view shows '$sec'"; done
assert_contains "$T/h.out" "openrouter" "S6 human view names the failing endpoint"
if grep -qF -- "$TYPESAFE_API_KEY" "$T/s.json" "$T/h.out" "$T/s.err"; then fail "S7 key value leaked"; else ok "S7 key value never printed"; fi
# S2/S3/S4 absent cases
rm -f "$JEV_CONFIG_DIR/jev-thresholds.json" "$JEV_STATE_DIR/consent.json" "$HOME/.claude/settings.json"
bash "$ST" --json --no-validate > "$T/s2.json" 2>/dev/null
assert_eq "null null false" "$(jq -r '"\(.calibration_age_s) \(.consent) \(.wiring.claude)"' "$T/s2.json")" "S2-S4 absent => null / null / false (never a false green)"
finish
