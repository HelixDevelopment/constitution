#!/usr/bin/env bash
# Paired §1.1 mutation test for CM-JEV-DETECTION.
# Mutation: fabricate a plausible jev-detection.json claiming reachable endpoints
# and tool provenance in a sandbox where llmctl/claude_toolkit checkouts and all
# endpoints are ABSENT. The gate MUST fail (probe replay + provenance path
# checks expose the fabrication). Also asserts GREEN on the genuine fixture.
set -uo pipefail
# Tool preflight: an absent tool is CANNOT-DETERMINE (rc 2), never a pass or a false RED.
for _t in jq python3 mktemp; do command -v "$_t" >/dev/null 2>&1 || { echo "[mutation] cannot determine: required tool '$_t' missing" >&2; exit 2; }; done
GREEN_LOG=$(mktemp); trap 'rm -f "$GREEN_LOG"' EXIT
HERE=$(cd "$(dirname "$0")" && pwd)
FIX="$HERE/fixtures/jev"
GATE="$HERE/cm_jev_detection.sh"

rc=0
say() { printf '[mutation:detection] %s\n' "$*"; }

# 1) GREEN first: genuine fixture state must pass.
JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" \
JEV_EVIDENCE_WINDOW_START=1759999000 \
JEV_PROBE_CMD="$FIX/bin/jev-probe-ok.sh" \
JEV_FIXTURE_ROOT="$FIX" \
  bash "$GATE" >"$GREEN_LOG" 2>&1 \
  || { say "SETUP FAILURE: gate not GREEN on genuine fixture"; cat "$GREEN_LOG"; exit 2; }
say "GREEN on genuine fixture confirmed"

# 2) Mutation: sandbox with NO tools, NO endpoints; fabricated record.
SBX=$(mktemp -d)
trap 'rm -rf "$SBX" "$GREEN_LOG"' EXIT
# Fabricated record: claims 2 reachable endpoints + submodule provenance —
# none of it exists in the sandbox.
jq '.tools.llmctl.path="submodules/llmctl" | .tools.claude_toolkit.path="submodules/claude_toolkit"' \
  "$FIX/evidence/jev-detection.json" > "$SBX/jev-detection.json"

JEV_DETECTION_FILE="$SBX/jev-detection.json" \
JEV_EVIDENCE_WINDOW_START=1759999000 \
JEV_PROBE_CMD="$FIX/bin/jev-probe-fail.sh" \
JEV_FIXTURE_ROOT="$SBX" \
  bash "$GATE" > "$SBX/out.log" 2>&1
gate_rc=$?
if [ "$gate_rc" -eq 0 ]; then
  say "MUTATION SURVIVED: gate passed on a fabricated detection record with absent tools/endpoints — gate is a bluff"
  cat "$SBX/out.log"
  rc=1
else
  grep -q 'CM-JEV-DETECTION FAIL' "$SBX/out.log" \
    || { say "gate failed but without a named failure line"; cat "$SBX/out.log"; rc=1; }
  grep -Eq 'probe replay FAILED|does not exist on this host' "$SBX/out.log" \
    || { say "gate failed for an unexpected reason (want probe/provenance exposure)"; cat "$SBX/out.log"; rc=1; }
fi
[ "$rc" -eq 0 ] && say "RED flip asserted: gate fails on fabricated record (probe replay + provenance exposure)"

# 3) Second mutation class: stale record (outside evidence window) must fail too.
JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" \
JEV_EVIDENCE_WINDOW_START=1760000001 \
JEV_PROBE_CMD="$FIX/bin/jev-probe-ok.sh" \
JEV_FIXTURE_ROOT="$FIX" \
  bash "$GATE" >/dev/null 2>&1 && {
    say "MUTATION SURVIVED: stale detection record passed the window check"; rc=1; } \
  || say "RED flip asserted: stale record rejected by evidence-window clause"

# 4) Mutation C: materialized secret in a hosted entry must be rejected (clause 3).
jq '.endpoints[1].api_key = "placeholder-not-a-real-secret"' "$FIX/evidence/jev-detection.json" > "$SBX/secret.json"
JEV_DETECTION_FILE="$SBX/secret.json" JEV_EVIDENCE_WINDOW_START=1759999000 \
JEV_PROBE_CMD="$FIX/bin/jev-probe-ok.sh" JEV_FIXTURE_ROOT="$FIX" bash "$GATE" > "$SBX/outC.log" 2>&1
{ [ $? -ne 0 ] && grep -q 'secrets:' "$SBX/outC.log"; } \
  && say "RED flip C asserted: materialized secret field rejected (clause 3)" \
  || { say "MUTATION C SURVIVED: materialized secret not flagged"; rc=1; }

# 5) Mutation D: empty endpoints without a reason must be rejected (clause 1).
jq '.endpoints = [] | del(.reason)' "$FIX/evidence/jev-detection.json" > "$SBX/empty.json"
JEV_DETECTION_FILE="$SBX/empty.json" JEV_EVIDENCE_WINDOW_START=1759999000 \
JEV_PROBE_CMD="$FIX/bin/jev-probe-ok.sh" JEV_FIXTURE_ROOT="$FIX" bash "$GATE" > "$SBX/outD.log" 2>&1
{ [ $? -ne 0 ] && grep -q 'require a non-empty' "$SBX/outD.log"; } \
  && say "RED flip D asserted: unreasoned empty detection rejected (clause 1)" \
  || { say "MUTATION D SURVIVED: unreasoned empty record accepted"; rc=1; }

# 6) Contract mutations (producer contract: scripts/jev/bootstrap.sh).
mut() { # mut <name> <jq-filter> <expected-fail-text>; probe-ok + window so only the mutated rule can trip
  jq "$2" "$FIX/evidence/jev-detection.json" > "$SBX/m_$1.json"
  JEV_DETECTION_FILE="$SBX/m_$1.json" JEV_EVIDENCE_WINDOW_START=1759999000 \
  JEV_PROBE_CMD="$FIX/bin/jev-probe-ok.sh" JEV_FIXTURE_ROOT="$FIX" bash "$GATE" > "$SBX/m_$1.log" 2>&1
  local r=$?
  if [ "$r" -eq 1 ] && grep -q "$3" "$SBX/m_$1.log"; then
    say "RED flip $1 asserted: $3"
  else
    say "MUTATION $1 SURVIVED (rc=$r, wanted FAIL matching '$3')"; cat "$SBX/m_$1.log"; rc=1
  fi
}
mut E_unavail_noreason '.tools.llmctl.source="unavailable" | .tools.llmctl.path=""' "requires a non-empty .reason"
mut F_true_nourl 'del(.endpoints[0].url)' "carry no .url"
mut G_null_nobasis 'del(.endpoints[2].reachable_basis)' "unprobed (null) without reachable_basis"
mut H_instances_array '.capacity.decision_instances=[{"profile":"x"}]' "decision_instances must be a non-negative number"
mut I_bad_source '.tools.llmctl.source="vendored"' "must be submodule|clone|explicit|unavailable"
mut J_reachable_string '.endpoints[0].reachable="yes"' "reachable not true|false|null"
# Positive controls: the new lawful shapes must pass (else the rules over-reject).
jq '.tools.llmctl.source="unavailable" | .tools.llmctl.path="" | .tools.llmctl.reason="git absent: cannot clone llmctl"' \
  "$FIX/evidence/jev-detection.json" > "$SBX/p_unavail.json"
JEV_DETECTION_FILE="$SBX/p_unavail.json" JEV_EVIDENCE_WINDOW_START=1759999000 \
JEV_PROBE_CMD="$FIX/bin/jev-probe-ok.sh" JEV_FIXTURE_ROOT="$FIX" bash "$GATE" > "$SBX/p_unavail.log" 2>&1 \
  && say "GREEN control: reasoned 'unavailable' tool with empty path accepted" \
  || { say "OVER-REJECT: reasoned unavailable tool failed"; cat "$SBX/p_unavail.log"; rc=1; }
grep -q 'NOTE: 1 of 3 endpoint(s) have reachable=null' "$SBX/p_unavail.log" \
  && say "NOTE control: unprobed count printed for null endpoints" \
  || { say "MISSING NOTE for unprobed endpoints"; rc=1; }
# No 'ok' lines after a FAIL in the same clause: a failing clause 5 must not print its ok line.
grep -q 'ok: clause 5' "$SBX/m_H_instances_array.log" && { say "COSMETIC BUG: ok printed for a failed clause"; rc=1; }
# Fabricated reachable=true with probe replay failing must still be caught (url present).
JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" JEV_EVIDENCE_WINDOW_START=1759999000 \
JEV_PROBE_CMD="$FIX/bin/jev-probe-fail.sh" JEV_FIXTURE_ROOT="$FIX" bash "$GATE" > "$SBX/fab.log" 2>&1
{ [ $? -eq 1 ] && grep -q 'probe replay FAILED' "$SBX/fab.log"; } \
  && say "RED flip K asserted: fabricated reachable=true still caught by replay" \
  || { say "MUTATION K SURVIVED: failing probe not caught"; rc=1; }
# reachable=true with no probe mechanism at all must fail.
JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" JEV_EVIDENCE_WINDOW_START=1759999000 JEV_FIXTURE_ROOT="$FIX" \
  bash "$GATE" > "$SBX/noprobe.log" 2>&1
{ [ $? -eq 1 ] && grep -q 'no JEV_PROBE_CMD' "$SBX/noprobe.log"; } \
  && say "RED flip L asserted: reachable=true without probe mechanism rejected" \
  || { say "MUTATION L SURVIVED: no-probe claim accepted"; rc=1; }

if [ "$rc" -eq 0 ]; then
  say "PASS: cm_jev_detection.sh genuinely discriminates (GREEN genuine / RED mutated)"
else
  say "FAIL: mutation test detected a bluff gate"
fi
exit "$rc"
