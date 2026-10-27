#!/usr/bin/env bash
# test_bootstrap_e2e_stub_server.sh — end-to-end, hermetic, in a TEMP HOME:
#   detection -> shadow -> calibrate -> promotion, previous thresholds preserved.
# The decision endpoint is the real HTTP stub tests/jev/fixtures/jev_server.py
# (127.0.0.1, ephemeral port). Decisions are produced by genuine
# POST /v1/systemone round-trips, not hand-written rows. No real provider,
# no network beyond loopback.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq curl python3; do
  command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent: e2e test cannot run"; finish; exit $?; }
done

make_fixture_env e2e
make_fixture_constitution_root with-submodules
cp -r "$FIXTURES/home_seed/.claude" "$HOME/.claude"

# --- start the stub decision server on an ephemeral loopback port ------------
SRVLOG="$T/server.port"
nice -n 10 python3 "$FIXTURES/jev_server.py" 0 >"$SRVLOG" 2>"$T/server.err" &
SRV=$!
trap 'kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do grep -q '^PORT ' "$SRVLOG" 2>/dev/null && break; sleep 0.1; done
PORT="$(sed -n 's/^PORT //p' "$SRVLOG" | head -1)"
[ -n "$PORT" ] || { fail "stub server did not report a port"; finish; exit $?; }
BASE="http://127.0.0.1:$PORT"
assert_eq '{"ok": true}' "$(curl -fsS "$BASE/healthz" | python3 -c 'import sys,json;print(json.dumps(json.load(sys.stdin)))')" "stub server healthz answers on loopback"

# control: a closed port really fails (so a passing round-trip below is real)
curl -fsS --max-time 2 "http://127.0.0.1:1/healthz" >/dev/null 2>&1
assert_nonzero "$?" "NEG: unreachable endpoint makes curl fail (round-trips are not faked)"

# --- 1. DETECTION: llmctl status says the stub's profile is running; the
# toolkit cache adds a hosted pin. (`llmctl plan --json` is NOT used.)
cat > "$T/status.json" <<JSON
{"gateway":{"running":true,"base_url":"$BASE"},"profiles":[{"profile":"decide-kev-08b","running":true},{"profile":"decide-laya","running":false}]}
JSON
cat > "$T/capacity.json" <<'JSON'
{"decision_instances":{"decide-kev-08b":{"instances_gpu":1,"instances_cpu":1,"effective_slots_per_instance":2}}}
JSON
cat > "$T/endpoints.json" <<'JSON'
{"endpoints":[{"provider_id":"typesafe-hosted","base_url":"https://example.invalid/v1","model":"jev-hosted","key_var":"JEV_TEST_KEY_VAR"}]}
JSON
export LLMCTL_STATUS_JSON="$T/status.json" LLMCTL_CAPACITY_JSON="$T/capacity.json" FIXTURE_ENDPOINTS="$T/endpoints.json"
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --yes >"$T/b1.out" 2>"$T/b1.err"
assert_rc 0 "$?" "bootstrap rc 0"
DET="$JEV_EVIDENCE_DIR/jev-detection.json"
assert_file_exists "$DET" "detection evidence written"
assert_eq "llmctl-decide-kev-08b typesafe-hosted" "$(jq -r '[.endpoints[].id]|join(" ")' "$DET")" "DETECTION: running local profile + hosted pin detected; stopped profile (decide-laya) NOT listed"
assert_eq "2" "$(jq -r '.endpoints[0].parallel' "$DET")" "DETECTION: parallelism taken from llmctl decide capacity"
assert_eq "null" "$(jq -r '.endpoints[]|select(.id=="typesafe-hosted")|.reachable' "$DET")" "DETECTION: hosted reachability is UNKNOWN (null), never claimed true without a probe"
assert_eq "2" "$(jq -r '.capacity.instances' "$DET")" "DETECTION: capacity.instances matches endpoints"
assert_not_contains "$STUB_LOG/llmctl.log" "llmctl plan" "DETECTION: NEG: the retired 'llmctl plan --json' is not called"
assert_contains "$STUB_LOG/llmctl.log" "decide status --json" "DETECTION: llmctl decide status --json consulted"

# --- 2. SHADOW: mode is shadow, no thresholds, status says so ----------------
assert_contains "$JEV_CONFIG_DIR/env" "JEV_MODE=shadow" "SHADOW: default mode shadow"
assert_file_absent "$JEV_CONFIG_DIR/jev-thresholds.json" "SHADOW: no thresholds before calibration"
assert_eq "null" "$(bash "$REPO/scripts/jev/jev-status.sh" --json | jq -r '.thresholds')" "SHADOW: status reports no thresholds"

# decisions come from REAL round-trips to the stub server
DEC="$JEV_STATE_DIR/decisions.jsonl"; : > "$DEC"
roundtrip() { # roundtrip <type> <i> <label_hint>
  local resp ans conf
  resp="$(curl -fsS --max-time 5 -X POST "$BASE/v1/systemone" -H 'Content-Type: application/json' \
    -d "{\"model\":\"jev-fixture\",\"state\":\"s\",\"questions\":{\"q\":{\"type\":\"choice\",\"instructions\":\"i\",\"criteria\":{\"yes\":\"y\",\"no\":\"n\"}}}}")" || return 1
  ans="$(printf '%s' "$resp" | jq -r '.answers.q.choice')"
  conf="$(printf '%s' "$resp" | jq -r '.answers.q.confidence')"
  [ -n "$ans" ] && [ "$ans" != null ] || return 1
  printf '{"ts":%d,"question_type":"%s","question":"q-%s-%d","criteria":{"yes":"y","no":"n"},"answer":"%s","confidence":%s,"state_hash":"h%d","label_hint":"%s","mode":"shadow"}\n' \
    $((1000 + $2)) "$1" "$1" "$2" "$ans" "$conf" "$2" "$3" >> "$DEC"
}
for i in $(seq 1 40); do roundtrip good "$i" yes || { fail "round-trip failed (good,$i)"; break; }; done
for i in $(seq 1 40); do roundtrip bad "$i" no  || { fail "round-trip failed (bad,$i)"; break; }; done
assert_eq "80" "$(wc -l < "$DEC" | tr -d ' ')" "SHADOW: 80 decisions captured from live stub round-trips"
assert_eq "yes" "$(jq -r 'select(.question_type=="good")|.answer' "$DEC" | sort -u)" "SHADOW: answers are the stub server's own (first criteria key)"

# --- 3. CALIBRATE + 4. PROMOTION ---------------------------------------------
export JEV_CALIBRATE_ALIAS_CMD="jev-label-stub"
bash "$REPO/scripts/jev/jev-calibrate.sh" --now >"$T/c1.out" 2>"$T/c1.err"
assert_rc 0 "$?" "calibrate rc 0"
THR="$JEV_CONFIG_DIR/jev-thresholds.json"
assert_eq "true"    "$(jq -r '.per_type.good.promoted' "$THR")" "PROMOTION: type agreeing with labels is promoted"
assert_eq "enforce" "$(jq -r '.per_type.good.mode' "$THR")" "PROMOTION: promoted type mode=enforce"
assert_eq "false"   "$(jq -r '.per_type.bad.promoted' "$THR")"  "NEG: type disagreeing with labels is NOT promoted"
assert_eq "shadow"  "$(jq -r '.per_type.bad.mode' "$THR")"      "NEG: non-promoted type stays shadow"
assert_eq "true" "$(bash "$REPO/scripts/jev/jev-status.sh" --json | jq -r '.thresholds.per_type.good.promoted')" "PROMOTION: visible through jev-status --json"
cp "$THR" "$T/thr.v1.json"

# --- 5. PREVIOUS VERSION PRESERVED on recalibration with degraded labels -----
# same decisions, but ground truth flips for 'good' -> demotion
sed -i 's/"label_hint":"yes"/"label_hint":"no"/' "$DEC"
JEV_NOW_EPOCH=1700003600 bash "$REPO/scripts/jev/jev-calibrate.sh" --now >"$T/c2.out" 2>"$T/c2.err"
assert_rc 0 "$?" "recalibration rc 0"
assert_contains "$T/c2.err" "DEMOTED type 'good'" "DEMOTION announced loudly"
assert_eq "shadow" "$(jq -r '.per_type.good.mode' "$THR")" "current thresholds: good reverted to shadow"
PREV="$JEV_CONFIG_DIR/jev-thresholds.1700003600.json"
assert_file_exists "$PREV" "previous thresholds preserved as jev-thresholds.<epoch>.json"
if cmp -s "$PREV" "$T/thr.v1.json"; then ok "preserved file is byte-identical to the pre-recalibration version"; else fail "preserved file differs from the previous version"; fi
assert_eq "true" "$(jq -r '.per_type.good.promoted' "$PREV")" "preserved version still records the earlier promotion"
assert_ne "$(jq -r '.calibrated_at' "$THR")" "$(jq -r '.calibrated_at' "$PREV")" "current and previous differ in calibrated_at"

# --- bootstrap enforce now honours the calibrated file; without it it defers -
make_fixture_env e2e_enforce_nocal
make_fixture_constitution_root with-submodules
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --enforce >/dev/null 2>"$T/e.err"
assert_contains "$JEV_CONFIG_DIR/env" "JEV_MODE=shadow" "NEG: --enforce without calibrated thresholds stays shadow"
assert_contains "$T/e.err" "enforce-deferred" "NEG: deferral is announced, not silent"
assert_file_exists "$JEV_STATE_DIR/enforce-deferred" "NEG: deferral recorded in state"
finish
