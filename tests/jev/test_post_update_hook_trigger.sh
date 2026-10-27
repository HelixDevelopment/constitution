#!/usr/bin/env bash
# test_post_update_hook_trigger.sh — drives the REAL scripts/post_update_hook.sh
# against a throwaway git repo (no stub git, no network):
#   1. a change under scripts/jev/ fires bootstrap, --non-interactive, in the
#      consuming project dir
#   1b. each other Jev trigger path fires it (skill, mcp, registry)
#   2. an unrelated change does NOT fire it (NEG)
#   3. .jev/bootstrap.disabled => no fire, the skip is LOGGED; and the
#      CM-JEV-BOOTSTRAP-IDEMPOTENT gate still passes (it asserts the block, not
#      the absence of the opt-out file)
#   3b. CONSTITUTION_JEV_HOOK=off => no fire, logged
#   4. bootstrap failure degrades to --defer, hook exits 0, pending stamp written
#   5. rc 3 (operator-required stop) is surfaced and NOT deferred over
#   6. bootstrap script absent => pending marker, hook exits 0
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
command -v git >/dev/null 2>&1 || { assert_skip "git absent"; finish; exit $?; }
HOSTS=()
cleanup() { for h in "${HOSTS[@]:-}"; do [ -n "$h" ] && rm -rf "$(dirname "$h")"; done; }
trap cleanup EXIT
host() { make_hook_host "$@"; HOSTS+=("$HOST_C"); }

# 1
host scripts/jev/bootstrap.sh; run_hook_host
assert_rc 0 "$HOOK_RC" "1 hook rc 0"
assert_contains "$HOST_P/bootstrap.log" "bootstrap --non-interactive" "1 scripts/jev/ change fired bootstrap with --non-interactive"
assert_not_contains "$HOST_P/bootstrap.log" "--defer" "1 healthy bootstrap is not deferred"
assert_contains "$HOST_P/hook.out" "1 jev file(s)" "1 hook reports the Jev change it detected"

# 1b every trigger path
for trig in skills/jev-decision-layer/SKILL.md mcp/templates/jev-decisions.json.tmpl actions/registry.yaml; do
  host "$trig"; run_hook_host
  assert_contains "$HOST_P/bootstrap.log" "bootstrap --non-interactive" "1b trigger path $trig fires bootstrap"
done

# 1c the template is a trigger but NEVER a live MCP config to merge
host mcp/templates/jev-decisions.json.tmpl; run_hook_host
assert_not_contains "$HOST_P/hook.out" "Merging MCP config:" "1c template change is not merged as a live MCP config"
assert_not_contains "$HOST_P/hook.out" "jev-decisions" "1c template is not treated as an MCP server name"
host mcp/templates/other.json; run_hook_host
assert_not_contains "$HOST_P/hook.out" "Merging MCP config:" "1d any .json under mcp/templates/ is a template, never merged live"

# 2 NEG unrelated change
host docs/guides/something.md; run_hook_host
assert_rc 0 "$HOOK_RC" "2 unrelated change: hook rc 0"
assert_file_absent "$HOST_P/bootstrap.log" "2 NEG: unrelated change does not fire bootstrap"

# 3 opt-out marker
host scripts/jev/bootstrap.sh; mkdir -p "$HOST_P/.jev"; : > "$HOST_P/.jev/bootstrap.disabled"; run_hook_host
assert_file_absent "$HOST_P/bootstrap.log" "3 opt-out marker: bootstrap not fired"
assert_contains "$HOST_P/hook.out" "opt-out marker" "3 the skip is logged, never silent"
if JEV_HOOK_FILE="$HOST_C/scripts/post_update_hook.sh" bash "$REPO/scripts/gates/cm_jev_bootstrap_idempotent.sh" >/dev/null 2>&1; then
  ok "3b CM-JEV-BOOTSTRAP-IDEMPOTENT passes with the opt-out marker present"
else fail "3b gate should pass: the opt-out file must not trip the block assertion"; fi

# 3c env kill switch
host scripts/jev/bootstrap.sh; run_hook_host CONSTITUTION_JEV_HOOK=off
assert_file_absent "$HOST_P/bootstrap.log" "3c CONSTITUTION_JEV_HOOK=off: bootstrap not fired"
assert_contains "$HOST_P/hook.out" "CONSTITUTION_JEV_HOOK=off" "3c kill-switch skip is logged"

# 4 failure -> defer
host mcp/templates/jev-decisions.json.tmpl; run_hook_host BOOTSTRAP_STUB_FAIL=1
assert_rc 0 "$HOOK_RC" "4 hook rc 0 although bootstrap fails (fail-open: the pull is never broken)"
assert_contains "$HOST_P/bootstrap.log" "bootstrap --defer" "4 failure degraded to --defer"
assert_file_exists "$HOST_P/.jev-state/bootstrap.pending" "4 pending stamp written"
assert_contains "$HOST_P/hook.out" "degrading to --defer" "4 degradation is logged loudly"

# 5 rc 3 = operator-required stop: surfaced, NOT deferred over
host scripts/jev/bootstrap.sh; run_hook_host BOOTSTRAP_STUB_RC=3
assert_rc 0 "$HOOK_RC" "5 rc 3 does not break the pull"
assert_contains "$HOST_P/hook.out" "operator action required" "5 rc 3 surfaced to the operator"
assert_not_contains "$HOST_P/bootstrap.log" "--defer" "5 NEG: rc 3 is not papered over with --defer"

# 6 bootstrap script absent
host scripts/jev/bootstrap.sh; rm -f "$HOST_C/scripts/jev/bootstrap.sh"; run_hook_host
assert_rc 0 "$HOOK_RC" "6 missing bootstrap script: hook rc 0"
assert_file_exists "$HOST_P/.jev-state/bootstrap.pending" "6 missing script recorded as pending (at the state-level path jev-status reads), not ignored"

finish
