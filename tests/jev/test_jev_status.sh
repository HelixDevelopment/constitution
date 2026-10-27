#!/usr/bin/env bash
# test_jev_status.sh — design §7 test 7.
# Seeded state (detection json, thresholds, stamp, decisions.jsonl) ->
# jev-status.sh human sections and --json schema exact-match.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"

make_fixture_env status

# --- seed state -------------------------------------------------------------
cat > "$JEV_EVIDENCE_DIR/jev-detection.json" <<'JSON'
{"version":1,"generated_at":1700000000,
 "endpoints":[{"id":"local-1","source":"local-llmctl","model":"jev-local-4b","reachable":true,"parallel":2,"probed_at":1700000000,"reason":null}],
 "reason":null,"capacity":{"instances":1},
 "tools":{"llmctl":{"path":"/x/llmctl","ref":"llmctl-v1.4.0","source":"submodule","installer":"install.sh"},
          "claude_toolkit":{"path":"/x/claude_toolkit","ref":"toolkit-v1.28.0","source":"clone","installer":"install.sh"}}}
JSON
cat > "$JEV_CONFIG_DIR/jev-thresholds.json" <<'JSON'
{"version":1,"calibrated_at":1700000000,"floor":0.9,"min_sample":30,
 "per_type":{"gate":{"threshold":0.9,"n":40,"agreement":0.95,"floor":0.9,"promoted":true,"mode":"enforce","reason":""}}}
JSON
printf 'JEV_MODE=enforce\n' > "$JEV_CONFIG_DIR/env"
printf '{"version":"1.0.0","created_at":1700000000,"stages":{"detect-tools":"abc"}}\n' > "$JEV_STATE_DIR/bootstrap.stamp"
printf '{"pending_at":1700000000,"reason":"operator-defer"}\n' > "$JEV_STATE_DIR/bootstrap.pending"
touch "$JEV_STATE_DIR/decisions.jsonl"

# --- human output ------------------------------------------------------------
bash "$REPO/scripts/jev/jev-status.sh" >"$T/human.out" 2>"$T/human.err"
assert_rc 0 "$?" "human run rc 0"
for section in "Mode: enforce" "Endpoints:" "local-1" "Tools:" "Thresholds:" "gate: threshold=0.9" "Bootstrap:" "PENDING"; do
  assert_contains "$T/human.out" "$section" "human section: $section"
done

# --- --json schema exact-match ----------------------------------------------
if command -v jq >/dev/null 2>&1; then
  bash "$REPO/scripts/jev/jev-status.sh" --json >"$T/status.json"
  assert_rc 0 "$?" "--json run rc 0"
  keys="$(jq -r 'keys_unsorted | join(",")' "$T/status.json")"
  assert_eq "version,detection,thresholds,bootstrap,mode" "$keys" "--json top-level keys exact"
  bkeys="$(jq -r '.bootstrap | keys_unsorted | join(",")' "$T/status.json")"
  assert_eq "stamp,pending" "$bkeys" "--json bootstrap keys exact"
  assert_eq "1" "$(jq -r '.version' "$T/status.json")" "--json version=1"
  assert_eq "local-1" "$(jq -r '.detection.endpoints[0].id' "$T/status.json")" "--json detection inlined"
  assert_eq "0.9" "$(jq -r '.thresholds.per_type.gate.threshold' "$T/status.json")" "--json thresholds inlined"
  assert_eq "true" "$(jq -r '.bootstrap.pending' "$T/status.json")" "--json pending true"
  assert_eq "abc" "$(jq -r '.bootstrap.stamp.stages["detect-tools"]' "$T/status.json")" "--json stamp inlined"
  assert_eq "enforce" "$(jq -r '.mode' "$T/status.json")" "--json mode"

  # empty state: nulls + pending false
  make_fixture_env status_empty
  bash "$REPO/scripts/jev/jev-status.sh" --json >"$T/empty.json"
  assert_eq "null" "$(jq -r '.detection' "$T/empty.json")" "empty state: detection null"
  assert_eq "null" "$(jq -r '.thresholds' "$T/empty.json")" "empty state: thresholds null"
  assert_eq "null" "$(jq -r '.bootstrap.stamp' "$T/empty.json")" "empty state: stamp null"
  assert_eq "false" "$(jq -r '.bootstrap.pending' "$T/empty.json")" "empty state: pending false"
else
  assert_skip "jq absent: --json schema assertions skipped"
fi

# --- negative controls on the human output ----------------------------------
make_fixture_env status_empty_human
bash "$REPO/scripts/jev/jev-status.sh" >"$T/empty_human.out" 2>"$T/empty_human.err"
assert_rc 0 "$?" "empty-state human run rc 0 (status never errors on a fresh host)"
assert_not_contains "$T/empty_human.out" "PENDING" "NEG: empty state does not claim a pending bootstrap"
assert_not_contains "$T/empty_human.out" "gate: threshold=" "NEG: empty state invents no thresholds"
assert_not_contains "$T/empty_human.out" "local-1" "NEG: empty state invents no endpoints"
# malformed detection file must not crash status or be reported as healthy
make_fixture_env status_corrupt
printf 'not json{' > "$JEV_EVIDENCE_DIR/jev-detection.json"
bash "$REPO/scripts/jev/jev-status.sh" >"$T/corrupt.out" 2>"$T/corrupt.err"
rc=$?
if [ "$rc" -le 2 ]; then ok "NEG: corrupt detection file handled without crash (rc $rc)"; else fail "NEG: corrupt detection file crashed status (rc $rc)"; fi
assert_not_contains "$T/corrupt.out" "local-1" "NEG: corrupt file yields no phantom endpoint"

finish
