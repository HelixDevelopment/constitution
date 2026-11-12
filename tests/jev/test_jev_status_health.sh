#!/usr/bin/env bash
# test_jev_status_health.sh — jev-status.sh control view (2026-11-12): per-endpoint health from decisions.jsonl, calibration
# age, consent state, wiring state, placement + leases. GATE-LOGIC test over declared state files (§11.4.289(C)(2)).
# Round 2 (review 2026-11-12 F3/F4/RM15): the decision rows are the REAL rows the toolkit gate wrote in the live T4 run
# (docs/qa/jev_s3s4_20261112/t4_run1/decisions.jsonl: class "gate", ts in MILLISECONDS, success = no `fallback`), plus one
# row in the gate's newer per-attempt shape (attempts[].result, the shape claude_toolkit scripts/jev-gate.sh `_log` writes
# and jev-stats.sh reads). No invented "class":"2xx" rows.
#   S1 health: per endpoint total / ok / last_success / last_seen (epoch SECONDS) / by_result; a legacy row is a success
#      when it carries no fallback (and no non-2xx http_status); an attempts row counts one event per attempt
#   S2 calibration age = now - calibrated_at; absent thresholds -> null, never 0
#   S3 consent: consent.json inlined; absent -> null
#   S4 wiring: a PreToolUse hook referencing jev-gate.sh in a settings file the toolkit installer writes
#      ($CLAUDE_CONFIG_DIR, ~/.claude-shared, ~/.claude) -> wired=true and the file is named; a jev-gate mention OUTSIDE a
#      PreToolUse hook is NOT wired (negative, RM15); a non-default $SHARED_DIR is consulted; the same resolver drives
#      cm_jev_wiring
#   S5 placement + leases inlined;  S6 human view prints every section;  S7 key VALUES never appear in the output
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export FIXTURES="$HERE/fixtures"; REPO="$(cd "$HERE/../.." && pwd)"
source "$HERE/lib_assert.sh"
command -v jq >/dev/null 2>&1 || { assert_skip "jq absent"; finish; exit $?; }
make_fixture_env sh; export JEV_TEST=1 JEV_NOW_EPOCH=1794504300
ST="$REPO/scripts/jev/jev-status.sh"
D="$JEV_STATE_DIR/decisions.jsonl"
REAL_ROWS="$REPO/docs/qa/jev_s3s4_20261112/t4_run1/decisions.jsonl"
[ -s "$REAL_ROWS" ] || { fail "real T4 gate rows missing: $REAL_ROWS"; finish; exit 1; }
assert_eq "gate gate" "$(jq -r '.class' "$REAL_ROWS" | tr '\n' ' ' | sed 's/ $//')" "fixture: the real rows carry class \"gate\" (the producer's shape)"
cp "$REAL_ROWS" "$D"
# one row in the per-attempt shape (failover: openrouter failed, typesafe answered), ts in ms like every gate row
jq -nc '{ts:1794504290000, class:"gate", question:"gate", answer:"allow", endpoint:"jev-typesafe", fallback:null, http_status:200,
         attempts:[{endpoint:"jev-openrouter", http_status:402, result:"no_credit", latency_ms:90},
                   {endpoint:"jev-typesafe", http_status:200, result:"ok", latency_ms:200}]}' >> "$D"
echo '{"ts":1794504295000,"class":"gate","question":"gate","answer":"allow","fallback":"timeout"}' >> "$D"   # no endpoint field
printf '{"version":1,"calibrated_at":1794503700,"per_type":{}}\n' > "$JEV_CONFIG_DIR/jev-thresholds.json"
printf '{"consent":{"default_on":true,"basis":"operator-standing-order-2026-11-12"}}\n' > "$JEV_STATE_DIR/consent.json"
printf '{"placement":{"profile":"decide-kev-08b","verdict":"fits","route":"local"}}\n' > "$JEV_STATE_DIR/placement.json"
printf '{"sets":{"decide-kev-08b":{"constitution_started":true,"stopping":null,"leases":[{"holder":"s1"}]}}}\n' > "$JEV_STATE_DIR/leases.json"
HOOK='{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"/x/.local/share/claude-multi-account/jev/jev-gate.sh"}]}]}}'
mkdir -p "$HOME/.claude-shared"; printf '%s\n' "$HOOK" > "$HOME/.claude-shared/settings.json"   # where the toolkit really wired in T4
TYPESAFE_API_KEY="tsk-status-$(date +%N)-value"; export TYPESAFE_API_KEY
bash "$ST" --json --no-validate > "$T/s.json" 2>"$T/s.err"; rc=$?
assert_rc 0 "$rc" "status --json rc 0"
assert_eq "2 2 1794504290 1794504290" "$(jq -r '.health["jev-typesafe"] | "\(.total) \(.ok) \(.last_success) \(.last_seen)"' "$T/s.json")" "S1 jev-typesafe: the real success row + the attempt => ok 2, last_success in SECONDS"
assert_eq "2 0 null 1 1" "$(jq -r '.health["jev-openrouter"] | "\(.total) \(.ok) \(.last_success) \(.by_result.endpoint_error) \(.by_result.no_credit)"' "$T/s.json")" "S1 jev-openrouter: a fallback row and a failed attempt are never a success"
assert_eq "1 0" "$(jq -r '.health.unknown | "\(.total) \(.ok)"' "$T/s.json")" "S1 a row without an endpoint is counted as unknown (a fallback, not a success)"
assert_eq 600 "$(jq -r '.calibration_age_s' "$T/s.json")" "S2 calibration age = now - calibrated_at"
assert_eq true "$(jq -r '.consent.default_on' "$T/s.json")" "S3 consent inlined"
assert_eq true "$(jq -r '.wiring.claude' "$T/s.json")" "S4 the hook in ~/.claude-shared/settings.json (where the toolkit wires) => wired"
assert_eq "$HOME/.claude-shared/settings.json" "$(jq -r '.wiring.claude_settings | map(select(.wired)) | .[0].file' "$T/s.json")" "S4 the wired settings file is named"
assert_eq "local 1" "$(jq -r '"\(.placement.route) \(.leases.sets["decide-kev-08b"].leases|length)"' "$T/s.json")" "S5 placement + leases inlined"
bash "$ST" --no-validate > "$T/h.out" 2>&1
for sec in "Endpoint health" "Calibration" "Consent" "Wiring" "Placement"; do assert_contains "$T/h.out" "$sec" "S6 human view shows '$sec'"; done
assert_contains "$T/h.out" "jev-openrouter" "S6 human view names the failing endpoint"
if grep -qF -- "$TYPESAFE_API_KEY" "$T/s.json" "$T/h.out" "$T/s.err"; then fail "S7 key value leaked"; else ok "S7 key value never printed"; fi
# S4 resolver: CLAUDE_CONFIG_DIR (the active agent config) is consulted
rm -f "$HOME/.claude-shared/settings.json"
mkdir -p "$T/alias1"; printf '%s\n' "$HOOK" > "$T/alias1/settings.json"
CLAUDE_CONFIG_DIR="$T/alias1" bash "$ST" --json --no-validate > "$T/s3.json" 2>/dev/null
assert_eq true "$(jq -r '.wiring.claude' "$T/s3.json")" "S4 the hook in \$CLAUDE_CONFIG_DIR/settings.json => wired"
# S4 resolver: a non-default SHARED_DIR (the toolkit's own override) is consulted; the ~/.claude-* glob cannot reach it
rm -f "$T/alias1/settings.json"
mkdir -p "$T/shared-elsewhere"; printf '%s\n' "$HOOK" > "$T/shared-elsewhere/settings.json"
SHARED_DIR="$T/shared-elsewhere" bash "$ST" --json --no-validate > "$T/s5.json" 2>/dev/null
assert_eq true "$(jq -r '.wiring.claude' "$T/s5.json")" "S4 the hook in \$SHARED_DIR/settings.json (outside \$HOME) => wired"
bash "$ST" --json --no-validate > "$T/s6.json" 2>/dev/null
assert_eq false "$(jq -r '.wiring.claude' "$T/s6.json")" "S4 CONTROL: the same files without SHARED_DIR => not wired"
rm -f "$T/shared-elsewhere/settings.json"
# S4 negative (RM15): jev-gate mentioned outside a PreToolUse hook is NOT wired
printf '{"permissions":{"allow":["Bash(/x/jev-gate.sh)"]},"hooks":{"PostToolUse":[{"hooks":[{"command":"/x/jev-gate.sh"}]}]}}\n' > "$T/alias1/settings.json"
mkdir -p "$HOME/.claude"; printf '{"note":"jev-gate.sh"}\n' > "$HOME/.claude/settings.json"
CLAUDE_CONFIG_DIR="$T/alias1" bash "$ST" --json --no-validate > "$T/s4.json" 2>/dev/null
assert_eq false "$(jq -r '.wiring.claude' "$T/s4.json")" "S4-NEG a jev-gate mention outside a PreToolUse hook => NOT wired"
# the same resolver drives cm_jev_wiring (review F4): shared-dir wiring passes the claude clause; an unwired shared dir fails it
GATE="$REPO/scripts/gates/cm_jev_wiring.sh"
JH="$T/jh"; mkdir -p "$JH/.claude-shared"; printf '%s\n' "$HOOK" > "$JH/.claude-shared/settings.json"
printf '{"mcpServers":{"jev":{"command":"python3"}}}\n' > "$JH/.claude-shared/.mcp.json"
JEV_HOME="$JH" bash "$GATE" > "$T/w1.out" 2>&1
assert_not_contains "$T/w1.out" "FAIL: claude:" "S4 cm_jev_wiring: hook + MCP in ~/.claude-shared => no claude FAIL"
assert_contains "$T/w1.out" "clause 1/2: hook + MCP wiring present for: claude" "S4 cm_jev_wiring CONTROL: the claude clause ran and passed on the shared dir"
# replay of the REAL T4 wiring: the `.hooks` object the toolkit wrote into the sandbox ~/.claude-shared/settings.json in the
# live run (docs/qa/jev_s3s4_20261112/t4_run1/settings.hooks.json); the T4 bootstrap's cm_jev_wiring reported a claude FAIL
# on exactly this wiring because it read only ~/.claude/settings.json
T4H="$REPO/docs/qa/jev_s3s4_20261112/t4_run1/settings.hooks.json"
if [ -s "$T4H" ]; then
  jq '{hooks:.}' "$T4H" > "$JH/.claude-shared/settings.json"
  JEV_HOME="$JH" bash "$GATE" > "$T/w3.out" 2>&1
  assert_not_contains "$T/w3.out" "FAIL: claude:" "S4 cm_jev_wiring on the REAL T4 wiring (captured hooks in ~/.claude-shared) => no claude FAIL"
  assert_contains "$T/w3.out" "clause 1/2: hook + MCP wiring present for: claude" "S4 cm_jev_wiring CONTROL: the T4 replay passes the claude clause"
else fail "captured T4 hooks missing: $T4H"; fi
printf '{"hooks":{}}\n' > "$JH/.claude-shared/settings.json"
JEV_HOME="$JH" bash "$GATE" > "$T/w2.out" 2>&1
assert_contains "$T/w2.out" "FAIL: claude: settings.json lacks a PreToolUse hook entry referencing jev-gate.sh" "S4-NEG cm_jev_wiring: an unwired shared dir is a claude FAIL"
# S2/S3/S4 absent cases
rm -f "$JEV_CONFIG_DIR/jev-thresholds.json" "$JEV_STATE_DIR/consent.json" "$HOME/.claude/settings.json"
bash "$ST" --json --no-validate > "$T/s2.json" 2>/dev/null
assert_eq "null null false" "$(jq -r '"\(.calibration_age_s) \(.consent) \(.wiring.claude)"' "$T/s2.json")" "S2-S4 absent => null / null / false (never a false green)"
finish
