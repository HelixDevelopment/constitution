#!/usr/bin/env bash
# Paired §1.1 mutation test for CM-JEV-WIRING.
# Mutation A: remove the kimi [[hooks]] marker block from a sandboxed home —
#   the gate MUST FAIL naming kimi.
# Mutation B: inject a decision endpoint into a fake provider models.json —
#   the gate MUST FAIL under clause 5 (§11.4.284(D)).
set -uo pipefail
# Tool preflight: an absent tool is CANNOT-DETERMINE (rc 2), never a pass or a false RED.
for _t in jq python3 mktemp; do command -v "$_t" >/dev/null 2>&1 || { echo "[mutation] cannot determine: required tool '$_t' missing" >&2; exit 2; }; done
GREEN_LOG=$(mktemp); trap 'rm -f "$GREEN_LOG"' EXIT
HERE=$(cd "$(dirname "$0")" && pwd)
FIX="$HERE/fixtures/jev"
GATE="$HERE/cm_jev_wiring.sh"
rc=0
say() { printf '[mutation:wiring] %s\n' "$*"; }

# GREEN first.
JEV_HOME="$FIX/home" JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" \
  bash "$GATE" >"$GREEN_LOG" 2>&1 \
  || { say "SETUP FAILURE: gate not GREEN on genuine fixture home"; cat "$GREEN_LOG"; exit 2; }
say "GREEN on genuine fixture home confirmed"

# Mutation A — strip kimi [[hooks]] block.
SBX=$(mktemp -d); trap 'rm -rf "$SBX" "$GREEN_LOG"' EXIT
cp -r "$FIX/home" "$SBX/home"
python3 - "$SBX/home/.kimi-code/config.toml" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'(?ms)# >>> helix-jev >>>.*?# <<< helix-jev <<<\n?', '', s)
open(p, 'w').write(s)
PYEOF
JEV_HOME="$SBX/home" JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" \
  bash "$GATE" > "$SBX/outA.log" 2>&1
if [ $? -eq 0 ]; then
  say "MUTATION A SURVIVED: kimi hook block removed yet gate passed — bluff gate"; rc=1
else
  grep -q 'kimi' "$SBX/outA.log" || { say "mutation A: gate failed but did NOT name kimi"; cat "$SBX/outA.log"; rc=1; }
  [ "$rc" -eq 0 ] && say "RED flip A asserted: gate fails naming kimi"
fi

# Mutation B — decision endpoint in chat config.
cp -r "$FIX/home" "$SBX/homeB"
jq '.providers.openrouter.models += ["jev-local-gateway"]' \
  "$FIX/home/providers/models.json" > "$SBX/homeB/providers/models.json"
JEV_HOME="$SBX/homeB" JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" \
  bash "$GATE" > "$SBX/outB.log" 2>&1
if [ $? -eq 0 ]; then
  say "MUTATION B SURVIVED: decision endpoint in chat config yet gate passed — bluff gate"; rc=1
else
  grep -q 'clause5' "$SBX/outB.log" || { say "mutation B: gate failed but not under clause 5"; cat "$SBX/outB.log"; rc=1; }
  [ "$rc" -eq 0 ] && say "RED flip B asserted: gate fails on decision-endpoint-in-chat-config (§11.4.284(D))"
fi

# Mutation C — remove the opencode coverage-gap note (clause 4).
cp -r "$FIX/home" "$SBX/homeC"; rm -f "$SBX/homeC/.config/opencode/jev-coverage-gaps.md"
JEV_HOME="$SBX/homeC" JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" bash "$GATE" > "$SBX/outC.log" 2>&1
{ [ $? -ne 0 ] && grep -q 'coverage-gap' "$SBX/outC.log"; } \
  && say "RED flip C asserted: missing opencode coverage-gap note rejected" \
  || { say "MUTATION C SURVIVED: coverage-gap note removed yet gate passed"; rc=1; }

# Mutation D — enforce mode without calibrated thresholds (clause 6).
cp -r "$FIX/home" "$SBX/homeD"; sed -i 's/^JEV_MODE=.*/JEV_MODE=enforce/' "$SBX/homeD/.config/jev/env"; rm -f "$SBX/homeD/.config/jev/jev-thresholds.json"
JEV_HOME="$SBX/homeD" JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" bash "$GATE" > "$SBX/outD.log" 2>&1
{ [ $? -ne 0 ] && grep -q 'thresholds:' "$SBX/outD.log"; } \
  && say "RED flip D asserted: enforce without thresholds rejected" \
  || { say "MUTATION D SURVIVED: enforce mode without thresholds passed"; rc=1; }

if [ "$rc" -eq 0 ]; then
  say "PASS: cm_jev_wiring.sh genuinely discriminates (GREEN genuine / RED mutated)"
else
  say "FAIL: mutation test detected a bluff gate"
fi
exit "$rc"
