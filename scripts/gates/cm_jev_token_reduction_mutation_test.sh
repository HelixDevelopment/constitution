#!/usr/bin/env bash
# Paired §1.1 mutation test for CM-JEV-TOKEN-REDUCTION.
# Mutation: replace after.jsonl with a copy of before.jsonl whose usage fields
# are inflated x1.2 — the gate MUST FAIL clause 3 (AFTER > BEFORE).
set -uo pipefail
# Tool preflight: an absent tool is CANNOT-DETERMINE (rc 2), never a pass or a false RED.
for _t in jq python3 mktemp; do command -v "$_t" >/dev/null 2>&1 || { echo "[mutation] cannot determine: required tool '$_t' missing" >&2; exit 2; }; done
GREEN_LOG=$(mktemp); trap 'rm -f "$GREEN_LOG"' EXIT
HERE=$(cd "$(dirname "$0")" && pwd)
FIX="$HERE/fixtures/jev"
GATE="$HERE/cm_jev_token_reduction.sh"
rc=0
say() { printf '[mutation:token] %s\n' "$*"; }

# GREEN first on genuine fixture harness.
JEV_BEFORE="$FIX/evidence/before.jsonl" JEV_AFTER="$FIX/evidence/after.jsonl" \
JEV_DECISIONS="$FIX/evidence/decisions.jsonl" \
JEV_STATS_REPORT="$FIX/evidence/jev-stats-report.txt" \
  bash "$GATE" >"$GREEN_LOG" 2>&1 \
  || { say "SETUP FAILURE: gate not GREEN on genuine fixture harness"; cat "$GREEN_LOG"; exit 2; }
say "GREEN on genuine fixture harness confirmed"

# Mutation: after.jsonl := before.jsonl with usage x1.2.
SBX=$(mktemp -d); trap 'rm -rf "$SBX" "$GREEN_LOG"' EXIT
cp "$FIX/evidence/before.jsonl" "$SBX/after.jsonl"
cp "$FIX/evidence/before.config" "$SBX/before.config"
cp "$FIX/evidence/after.config" "$SBX/after.config"
tmp=$(mktemp)
while IFS= read -r line; do
  [ -n "$line" ] || continue
  printf '%s' "$line" | jq '.usage.input_tokens = ((.usage.input_tokens * 1.2) | floor)
                          | .usage.output_tokens = ((.usage.output_tokens * 1.2) | floor)'
done < "$SBX/after.jsonl" > "$tmp"
mv "$tmp" "$SBX/after.jsonl"

JEV_BEFORE="$FIX/evidence/before.jsonl" JEV_AFTER="$SBX/after.jsonl" \
JEV_BEFORE_CONFIG="$SBX/before.config" JEV_AFTER_CONFIG="$SBX/after.config" \
JEV_DECISIONS="$FIX/evidence/decisions.jsonl" \
  bash "$GATE" > "$SBX/out.log" 2>&1
if [ $? -eq 0 ]; then
  say "MUTATION SURVIVED: inflated AFTER passed — gate is a bluff"; rc=1
else
  grep -q 'clause3' "$SBX/out.log" || { say "gate failed but not on clause 3"; cat "$SBX/out.log"; rc=1; }
  [ "$rc" -eq 0 ] && say "RED flip asserted: inflated AFTER rejected by clause 3 (measured reduction)"
fi

# Mutation B — arms differ in a non-allowlisted key (clause 2).
sed 's/^MODEL=.*/MODEL=opus/' "$FIX/evidence/after.config" > "$SBX/after_b.config"
JEV_BEFORE="$FIX/evidence/before.jsonl" JEV_AFTER="$FIX/evidence/after.jsonl" \
JEV_BEFORE_CONFIG="$FIX/evidence/before.config" JEV_AFTER_CONFIG="$SBX/after_b.config" \
JEV_DECISIONS="$FIX/evidence/decisions.jsonl" bash "$GATE" > "$SBX/outB.log" 2>&1
{ [ $? -ne 0 ] && grep -q 'clause2' "$SBX/outB.log"; } \
  && say "RED flip B asserted: non-isolated arms rejected (clause 2)" \
  || { say "MUTATION B SURVIVED: differing MODEL key accepted"; rc=1; }

# Mutation C — empty harness (0 <= 0 vacuous pass) must be rejected.
: > "$SBX/empty.jsonl"
JEV_BEFORE="$SBX/empty.jsonl" JEV_AFTER="$SBX/empty.jsonl" \
JEV_BEFORE_CONFIG="$FIX/evidence/before.config" JEV_AFTER_CONFIG="$FIX/evidence/after.config" \
JEV_DECISIONS="$FIX/evidence/decisions.jsonl" bash "$GATE" > "$SBX/outC.log" 2>&1
{ [ $? -ne 0 ] && grep -q 'empty/zero harness' "$SBX/outC.log"; } \
  && say "RED flip C asserted: empty harness rejected (no vacuous pass)" \
  || { say "MUTATION C SURVIVED: empty BEFORE/AFTER passed vacuously"; rc=1; }

if [ "$rc" -eq 0 ]; then
  say "PASS: cm_jev_token_reduction.sh genuinely discriminates (GREEN genuine / RED mutated)"
else
  say "FAIL: mutation test detected a bluff gate"
fi
exit "$rc"
