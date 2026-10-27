#!/usr/bin/env bash
# test_calibration_math.sh — design §7 test 5.
# Fixture decisions.jsonl with a known answer/confidence distribution (4
# question types) + deterministic stub alias (fixtures/bin/jev-label-stub)
# -> exact expected jev-thresholds.json (canonicalized byte-compare),
# floor-boundary promotion, below-floor shadow revert, insufficient sample,
# label_error counting (never guessed), demotion loudness, atomic backup,
# dry-run writes nothing.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"

if ! command -v jq >/dev/null 2>&1; then
  assert_skip "jq absent: calibration-math exact comparisons skipped entirely"
  finish
  exit $?
fi

make_fixture_env calibrate
export JEV_TEST=1   # r6 n6-1: JEV_NOW_EPOCH (the deterministic clock these cases pin) is honoured only under JEV_TEST=1
export JEV_CALIBRATE_ALIAS_CMD="jev-label-stub"

# --- build fixture decisions.jsonl (deterministic, fixed ts) ---------------
DEC="$JEV_STATE_DIR/decisions.jsonl"
: > "$DEC"
emit() { # emit <type> <count> <conf> <agree|disagree|invalid> <ts-start>
  local type="$1" count="$2" conf="$3" kind="$4" ts="$5" i
  for ((i=0; i<count; i++)); do
    local answer="yes" hint="yes"
    [ "$kind" = "disagree" ] && hint="no"
    [ "$kind" = "invalid" ] && hint="INVALID"
    printf '{"ts":%d,"question_type":"%s","question":"q-%s-%d","criteria":{"yes":"y","no":"n"},"answer":"%s","confidence":%s,"state_hash":"h%d","label_hint":"%s","mode":"shadow"}\n' \
      $((ts+i)) "$type" "$type" "$i" "$answer" "$conf" "$i" "$hint" >> "$DEC"
  done
}
# gate: 38 agree @0.95 (bin .9 -> 1.0), 2 disagree @0.55 (bin .5 -> 0.0)
emit gate 38 0.95 agree 1000
emit gate 2 0.55 disagree 2000
# route: 34 agree + 4 disagree @0.95, 2 invalid (label_error)
emit route 34 0.95 agree 3000
emit route 4 0.95 disagree 4000
emit route 2 0.95 invalid 5000
# edge: 27 agree + 3 disagree @0.92 -> agreement exactly 0.9000 (floor boundary)
emit edge 27 0.92 agree 6000
emit edge 3 0.92 disagree 7000
# tiny: 10 agree @0.99 -> below min sample 30
emit tiny 10 0.99 agree 8000

bash "$REPO/scripts/jev/jev-calibrate.sh" --now >"$T/cal.out" 2>"$T/cal.err"
assert_rc 0 "$?" "calibrate rc 0"

THR="$JEV_CONFIG_DIR/jev-thresholds.json"
assert_file_exists "$THR" "jev-thresholds.json written"
assert_file_exists "$JEV_EVIDENCE_DIR/jev-thresholds.json" "thresholds mirrored to evidence dir"

# exact per-type values
assert_eq "0.9"    "$(jq -r '.per_type.gate.threshold' "$THR")"  "gate threshold 0.9"
assert_eq "40"     "$(jq -r '.per_type.gate.n' "$THR")"          "gate n=40"
assert_eq "0.95"   "$(jqn "$THR" '.per_type.gate.agreement')"  "gate agreement 0.9500"
assert_eq "true"   "$(jq -r '.per_type.gate.promoted' "$THR")"   "gate promoted"
assert_eq "enforce" "$(jq -r '.per_type.gate.mode' "$THR")"      "gate mode enforce"

assert_eq "null"   "$(jq -r '.per_type.route.threshold' "$THR")" "route threshold null (below floor)"
assert_eq "38"     "$(jq -r '.per_type.route.n' "$THR")"         "route n=38 labeled (2 label_errors excluded)"
assert_eq "2"      "$(jq -r '.per_type.route.label_errors' "$THR")" "route label_errors=2 counted, never guessed"
assert_eq "0.8947" "$(jqn "$THR" '.per_type.route.agreement')" "route agreement 0.8947"
assert_eq "false"  "$(jq -r '.per_type.route.promoted' "$THR")"  "route not promoted"
assert_eq "shadow" "$(jq -r '.per_type.route.mode' "$THR")"      "route mode shadow"

assert_eq "0.9"    "$(jq -r '.per_type.edge.threshold' "$THR")"  "edge threshold 0.9"
assert_eq "0.9"    "$(jqn "$THR" '.per_type.edge.agreement')"  "edge agreement exactly at floor 0.9000"
assert_eq "true"   "$(jq -r '.per_type.edge.promoted' "$THR")"   "edge promoted (floor boundary is inclusive)"

assert_eq "false"  "$(jq -r '.per_type.tiny.promoted' "$THR")"   "tiny not promoted (insufficient sample)"
assert_eq "10"     "$(jq -r '.per_type.tiny.n' "$THR")"          "tiny n=10"
assert_contains "$T/cal.out" "insufficient-sample" "tiny reason reported"

# canonicalized byte-compare against exact expected thresholds document
CANON='walk(if type=="number" then .+0 else . end)'
jq -S "$CANON" "$THR" > "$T/actual.canon.json"
cat > "$T/expected.json" <<'JSON'
{"version":1,"calibrated_at":1700000000,"floor":0.9,"min_sample":30,"sample_per_type":50,
 "per_type":{
   "edge":{"threshold":0.9,"n":30,"label_errors":0,"agreement":0.9,"floor":0.9,"promoted":true,"mode":"enforce","reason":""},
   "gate":{"threshold":0.9,"n":40,"label_errors":0,"agreement":0.95,"floor":0.9,"promoted":true,"mode":"enforce","reason":""},
   "route":{"threshold":null,"n":38,"label_errors":2,"agreement":0.8947,"floor":0.9,"promoted":false,"mode":"shadow","reason":"no-confidence-bin-meets-floor (0.90)"},
   "tiny":{"threshold":0.9,"n":10,"label_errors":0,"agreement":1,"floor":0.9,"promoted":false,"mode":"shadow","reason":"insufficient-sample (10 < 30)"}
 }}
JSON
jq -S "$CANON" "$T/expected.json" > "$T/expected.canon.json"
if cmp -s "$T/expected.canon.json" "$T/actual.canon.json"; then
  ok "thresholds document byte-equal (canonicalized) to exact expected"
else
  fail "thresholds document differs from exact expected"
  diff "$T/expected.canon.json" "$T/actual.canon.json" | head -20
fi

# --- demotion: previously-promoted route now fails -------------------------
cat > "$THR" <<'JSON'
{"version":1,"calibrated_at":1690000000,"per_type":{"route":{"threshold":0.9,"n":40,"agreement":0.95,"floor":0.9,"promoted":true,"mode":"enforce","reason":""}}}
JSON
bash "$REPO/scripts/jev/jev-calibrate.sh" --now --question-type route >"$T/cal2.out" 2>"$T/cal2.err"
assert_rc 0 "$?" "demotion run rc 0"
assert_contains "$T/cal2.err" "DEMOTED type 'route'" "demotion recorded loudly on stderr"
assert_eq "shadow" "$(jq -r '.per_type.route.mode' "$THR")" "demoted type reverts to shadow"
assert_file_exists "$JEV_CONFIG_DIR/jev-thresholds.1700000000.json" "previous thresholds preserved as .<epoch>.json"


# --- dry-run writes nothing -------------------------------------------------
make_fixture_env calibrate_dry
export JEV_CALIBRATE_ALIAS_CMD="jev-label-stub"
cp "$DEC" "$JEV_STATE_DIR/decisions.jsonl"
bash "$REPO/scripts/jev/jev-calibrate.sh" --now --dry-run >"$T/cal3.out" 2>&1
assert_rc 0 "$?" "dry-run rc 0"
assert_file_absent "$JEV_CONFIG_DIR/jev-thresholds.json" "dry-run writes no thresholds"
assert_contains "$T/cal3.out" "dry-run" "dry-run reported"

# --- negative controls: the math must be able to say NO ---------------------
make_fixture_env calibrate_neg
export JEV_CALIBRATE_ALIAS_CMD="jev-label-stub"
DEC="$JEV_STATE_DIR/decisions.jsonl"; : > "$DEC"
emit bad 40 0.95 disagree 1000          # 0% agreement at high confidence
emit near 26 0.95 agree 2000            # 26/30 = 0.8667 < floor 0.90
emit near 4 0.95 disagree 3000
bash "$REPO/scripts/jev/jev-calibrate.sh" --now >"$T/neg.out" 2>"$T/neg.err"
assert_rc 0 "$?" "negative-control calibrate rc 0"
THR="$JEV_CONFIG_DIR/jev-thresholds.json"
assert_eq "false" "$(jq -r '.per_type.bad.promoted' "$THR")" "NEG: 0% agreement type is NOT promoted"
assert_eq "null"  "$(jq -r '.per_type.bad.threshold' "$THR")" "NEG: 0% agreement type has null threshold"
assert_eq "false" "$(jq -r '.per_type.near.promoted' "$THR")" "NEG: 26/30 (0.8667) just below floor is NOT promoted"
assert_eq "shadow" "$(jq -r '.per_type.near.mode' "$THR")" "NEG: below-floor type stays in shadow"
# floor override moves the verdict (proves floor is actually consulted, not hard-coded)
JEV_CALIBRATE_FLOOR=0.80 bash "$REPO/scripts/jev/jev-calibrate.sh" --now --question-type near >/dev/null 2>&1
assert_eq "true" "$(jq -r '.per_type.near.promoted' "$THR")" "NEG: lowering floor to 0.80 promotes the 0.8667 type (floor is honoured)"
# unlabelable alias => zero labeled, never guessed
JEV_CALIBRATE_ALIAS_CMD="false" bash "$REPO/scripts/jev/jev-calibrate.sh" --now --question-type bad >/dev/null 2>&1
assert_eq "40" "$(jq -r '.per_type.bad.label_errors' "$THR")" "NEG: failing labeler => every row counted as label_error, none guessed"
assert_eq "false" "$(jq -r '.per_type.bad.promoted' "$THR")" "NEG: failing labeler never promotes"
# no decisions at all => nonzero, no thresholds file
make_fixture_env calibrate_empty
bash "$REPO/scripts/jev/jev-calibrate.sh" --now >/dev/null 2>&1
assert_nonzero "$?" "NEG: calibrate with no decisions exits nonzero"
assert_file_absent "$JEV_CONFIG_DIR/jev-thresholds.json" "NEG: no thresholds fabricated from nothing"


finish
