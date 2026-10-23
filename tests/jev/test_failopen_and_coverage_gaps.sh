#!/usr/bin/env bash
# test_failopen_and_coverage_gaps.sh — two honesty properties, both executed:
#  A. FAIL-OPEN: the decision layer never blocks the host's work.
#     A1 post-update hook: bootstrap failure degrades to --defer, hook rc 0
#     A2 post-update hook: bootstrap failing even on --defer => hook still rc 0
#        path (logged), the pull is never broken
#     A3 jev-gate hook (lives in claude_toolkit, not this repo): when a real
#        gate script is supplied via JEV_GATE_SCRIPT (or found in
#        submodules/claude_toolkit/scripts), it MUST exit 0 against an
#        unreachable decision endpoint. SKIP (counted, named) when absent.
#     A4 the documentation states the fail-open semantic (so it is a declared
#        property, not an accident).
#  B. OPENCODE PARTIAL COVERAGE, recorded verbatim: register.sh must write the
#     coverage-gap note stating that the plugin hook intercepts direct tool
#     calls only and does NOT intercept MCP-tool calls or subagent/task calls;
#     the note must be written, must survive a second registration unchanged,
#     and the gate CM-JEV-WIRING must go RED if the note is removed.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"

HOSTS=()
host() { make_hook_host "$@"; HOSTS+=("$HOST_C"); }

# ---- A1 ---------------------------------------------------------------------
host scripts/jev/bootstrap.sh; run_hook_host BOOTSTRAP_STUB_FAIL=1
assert_rc 0 "$HOOK_RC" "A1 hook rc 0 although bootstrap fails (fail-open)"
assert_contains "$HOST_P/bootstrap.log" "bootstrap --defer" "A1 degraded to --defer"
assert_file_exists "$HOST_P/.jev-state/bootstrap.pending" "A1 pending stamp written"
assert_contains "$HOST_P/hook.out" "[WARN]" "A1 failure surfaced as a WARNING (never silent)"
assert_not_contains "$HOST_P/hook.out" "[ERROR] step install_jev_bootstrap" "A1 failure is NOT escalated to a hook ERROR"
# control: without the failure no defer happens (the fallback is conditional, not constant)
host scripts/jev/bootstrap.sh; run_hook_host
assert_not_contains "$HOST_P/bootstrap.log" "--defer" "A1-NEG: healthy bootstrap does NOT defer"

# ---- A2 ---------------------------------------------------------------------
host scripts/jev/bootstrap.sh; run_hook_host BOOTSTRAP_STUB_FAIL=1 BOOTSTRAP_STUB_DEFER_FAIL=1
assert_rc 0 "$HOOK_RC" "A2 hook rc 0 even when bootstrap AND --defer both fail"
assert_contains "$HOST_P/hook.out" "even with --defer" "A2 total failure is logged loudly, not swallowed"

# ---- A3 ---------------------------------------------------------------------
GATE="${JEV_GATE_SCRIPT:-}"
[ -z "$GATE" ] && for c in "$REPO/submodules/claude_toolkit/scripts/jev-gate.sh"; do [ -s "$c" ] && GATE="$c"; done
if [ -n "$GATE" ] && [ -f "$GATE" ] && [ "$(grep -vc '^#' "$GATE")" -gt 3 ]; then
  out="$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | JEV_BASE_URL="http://127.0.0.1:1" JEV_MODE=enforce timeout 15 bash "$GATE" 2>/dev/null)"; grc=$?
  assert_rc 0 "$grc" "A3 jev-gate exits 0 when the decision endpoint is unreachable (fail-open)"
  if printf '%s' "$out" | grep -qE '"(decision|permissionDecision)" *: *"(block|deny)"'; then fail "A3 gate emitted a block/deny for an unreachable endpoint"; else ok "A3 no block/deny emitted for an unreachable endpoint"; fi
else
  assert_skip "A3 jev-gate.sh not available in this tree (claude_toolkit submodule not populated / only a stand-in); UNCONFIRMED here — set JEV_GATE_SCRIPT to run"
fi

# ---- A4 ---------------------------------------------------------------------
for d in "$REPO/docs/jev/governance-guide.md" "$REPO/skills/jev-decision-layer/SKILL.md"; do
  if [ -f "$d" ]; then
    grep -qiE 'fail[- ]open' "$d" && ok "A4 ${d#"$REPO"/} declares the fail-open semantic" || fail "A4 ${d#"$REPO"/} does not declare fail-open"
  else fail "A4 missing $d"; fi
done

# ---- B ----------------------------------------------------------------------
for tool in jq; do command -v $tool >/dev/null 2>&1 || { assert_skip "$tool absent: B skipped"; finish; exit $?; }; done
SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"; for h in "${HOSTS[@]:-}"; do [ -n "$h" ] && rm -rf "$(dirname "$h")"; done' EXIT
mkdir -p "$SBX/.config/opencode"
JEV_HOME="$SBX" bash "$REPO/skills/jev-decision-layer/register.sh" >/dev/null 2>&1
assert_rc 0 "$?" "B register.sh rc 0"
NOTE="$SBX/.config/opencode/jev-coverage-gaps.md"
assert_file_exists "$NOTE" "B opencode coverage-gap note written"
assert_contains "$NOTE" "intercepts direct tool calls only" "B verbatim: hook intercepts direct tool calls only"
assert_contains "$NOTE" "MCP-tool calls" "B verbatim: MCP-tool calls named as NOT covered"
if grep -qiE 'subagent' "$NOTE" && grep -qiE 'task' "$NOTE"; then ok "B verbatim: subagent/task calls named as NOT covered"; else fail "B subagent/task gap missing from note"; fi
assert_contains "$NOTE" "bypass the decision-layer gate" "B verbatim: states those classes bypass the gate"
assert_not_contains "$NOTE" "full coverage is guaranteed" "B NEG: note never claims full coverage"
# plugin file carries the same caveat
assert_contains "$SBX/.config/opencode/plugin/jev.js" "COVERAGE GAP" "B plugin source repeats the coverage-gap caveat"
# idempotent: second run does not alter the note
h1="$(sha256sum "$NOTE" | awk '{print $1}')"
JEV_HOME="$SBX" bash "$REPO/skills/jev-decision-layer/register.sh" >/dev/null 2>&1
assert_eq "$h1" "$(sha256sum "$NOTE" | awk '{print $1}')" "B note byte-stable across re-registration"
# the SKILL.md limitations section records the gap too
assert_contains "$REPO/skills/jev-decision-layer/SKILL.md" "opencode coverage gap" "B SKILL.md limitations record the opencode gap"
# gate pair: removing the note must turn CM-JEV-WIRING red
GATE_W="$REPO/scripts/gates/cm_jev_wiring.sh"
if [ -f "$GATE_W" ]; then
  DET="$REPO/scripts/gates/fixtures/jev/evidence/jev-detection.json"
  JEV_HOME="$SBX" JEV_DETECTION_FILE="$DET" bash "$GATE_W" >/dev/null 2>&1
  assert_rc 0 "$?" "B gate CM-JEV-WIRING green with the note present"
  rm -f "$NOTE"
  JEV_HOME="$SBX" JEV_DETECTION_FILE="$DET" bash "$GATE_W" >/dev/null 2>&1
  assert_nonzero "$?" "B NEG: CM-JEV-WIRING RED when the opencode gap note is removed"
else
  fail "B gate $GATE_W missing (scope not landed?)"
fi
finish
