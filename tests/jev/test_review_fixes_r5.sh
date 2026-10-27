#!/usr/bin/env bash
# test_review_fixes_r5.sh — regression tests for the ROUND-5 independent review of the decision layer (fix round 6):
#   I5-1 the validator is called as `llmctl require-validated <profile>` (the pinned CLI takes exactly one argument; a `--`
#        is a usage error, rc 2, so real validation could never pass). The stub validator now rejects what the real CLI rejects.
#   I5-2 ONE config-dir derivation (jev_config_dir) for register / bootstrap / jev-status / the resolver: JEV_HOME honoured
#   m5-1 env-file values are read like a shell would: last assignment wins, optional `export `, ANY non-loopback occurrence
#        or an unresolvable value => shadow ; m5-2 toolkit MCP locations are read ; m5-3 clock/age knobs are JEV_TEST-only
#   m5-4 malformed .mcp.json fails closed ; m5-5 bootstrap rewrites + status checks the MCP entry's JEV_MODE ; m5-6/7 docs
#   M4   stored enforce survives a re-run without --enforce ; nit: make_fixture_env leaks no tmp dirs
# Every case drives the REAL code; llmctl / validator are stubs, every URL is loopback or a reserved test name.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq python3; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done
ST="$REPO/scripts/jev/jev-status.sh"; REG="$REPO/skills/jev-decision-layer/register.sh"; BS="$REPO/scripts/jev/bootstrap.sh"
LOOP=https://127.0.0.1:8095; HOSTED=https://api.typesafe.test

promoted() { jq -n '{per_type:{gate:{promoted:true,threshold:0.9}}}' > "$1"; }
eff() { ( set +u; source "${LIBDIR:-$REPO/scripts/jev}/lib_keys.sh" 2>/dev/null; source "${LIBDIR:-$REPO/scripts/jev}/lib_decide.sh"; jev_effective_mode "$@" ); }
strip() { sed 's/;test-override(JEV_TEST=1)//'; }
mkdet() { jq -n --arg id "$2" --arg u "$3" --argjson g "${4:-1700000000}" '{version:1,generated_at:$g,endpoints:[{id:$id,source:"local-llmctl",reachable:true,url:$u}],reason:null}' > "$1"; }
fx() { make_fixture_env "$1"; jev_test_enforce_env 0; unset JEV_BASE_URL
  mkdet "$T/det.json" llmctl-decide "http://127.0.0.1:9"; promoted "$JEV_CONFIG_DIR/jev-thresholds.json"
  export JEV_DETECTION_FILE="$T/det.json"; cp "$T/det.json" "$JEV_EVIDENCE_DIR/jev-detection.json"
  B="$T/box"; mkdir -p "$B/.claude"; printf '{"mcpServers":{}}\n' > "$B/.mcp.json"; export JEV_HOME="$B"; }
mode_of() { grep -E '^[[:space:]]*(export[[:space:]]+)?JEV_MODE=' "$1" 2>/dev/null | tail -1 | sed -E 's/^[[:space:]]*(export[[:space:]]+)?JEV_MODE=//'; }
shell_mode() { ( set +u; . "$1" >/dev/null 2>&1; printf '%s' "${JEV_MODE:-}" ); }   # what a shell sourcing the file would see
status_json() { bash "$ST" --json 2>/dev/null; }

# ---- I5-1: the validator argv shape (stub rejects exactly what the pinned CLI rejects) ----------------------------------
fx a1
assert_eq "enforce" "$(eff enforce "$LOOP" "$T/det.json" | cut -f1)" "I5-1 enforce reachable with a validator that rejects '--' and extra args"
assert_contains "$STUB_LOG/rv.log" "args=decide" "I5-1 the validator receives exactly: <profile>"
assert_not_contains "$STUB_LOG/rv.log" "args=--" "I5-1 no '--' in the validator argv"
# the REAL pinned llmctl, when its tree is present: the arity contract the stub imitates
LLB=""; for c in "$REPO/submodules/llmctl/bin/llmctl" "$(getent passwd "$(id -u)" | cut -d: -f6)/Projects/catalogizer/constitution/submodules/llmctl/bin/llmctl" "${REAL_LLMCTL_BIN:-/nonexistent}"; do [ -x "$c" ] && { LLB="$c"; break; }; done
if [ -n "$LLB" ]; then
  r1="$(env -u LLMCTL_API_KEY "$LLB" require-validated -- no-such-profile-r5 2>&1 >/dev/null)"; rc1=$?
  r2="$(env -u LLMCTL_API_KEY "$LLB" require-validated no-such-profile-r5 2>&1 >/dev/null)"; rc2=$?
  assert_eq "2" "$rc1" "I5-1 real llmctl: 'require-validated -- X' is rejected (rc 2)"
  case "$r1" in *usage*) ok "I5-1 real llmctl: '--' form is a usage error";; *) fail "I5-1 real llmctl '--' output: $r1";; esac
  case "$r2" in *"unknown profile"*) ok "I5-1 real llmctl: single-arg form reaches the profile lookup";; *) fail "I5-1 real llmctl single-arg output: $r2";; esac
else assert_skip "I5-1 real pinned llmctl tree absent"; fi

# ---- I5-2: one config-dir derivation -----------------------------------------------------------------------------------
fx b1; unset JEV_CONFIG_DIR
BC="$B/.config/jev"; mkdir -p "$BC"; promoted "$BC/jev-thresholds.json"; printf 'JEV_MODE=enforce\nJEV_BASE_URL=%s\n' "$HOSTED" > "$BC/env"
env JEV_MODE=enforce bash "$REG" >/dev/null 2>&1
assert_eq "shadow" "$(mode_of "$BC/env")" "I5-2 JEV_HOME set, JEV_CONFIG_DIR unset: register.sh stores shadow (hosted base in the box env file)"
printf 'JEV_MODE=enforce\nJEV_BASE_URL=%s\n' "$HOSTED" > "$BC/env"
assert_eq "shadow" "$(status_json | jq -r .mode)" "I5-2 jev-status agrees (shadow) for the same box"
assert_eq "enforce" "$(status_json | jq -r .mode_stored)" "I5-2 jev-status reads the BOX env file (stored enforce)"
fx b2; unset JEV_CONFIG_DIR; BC="$B/.config/jev"; mkdir -p "$BC"
bash "$BS" --non-interactive >/dev/null 2>&1 </dev/null
assert_file_exists "$BC/env" "I5-2 bootstrap writes the env file under \$JEV_HOME/.config/jev"
assert_file_absent "$HOME/.config/jev/env" "I5-2 bootstrap wrote nothing under \$HOME/.config/jev"
fx b3; unset JEV_CONFIG_DIR
assert_eq "$B/.config/jev" "$( set +u; source "$REPO/scripts/jev/lib_decide.sh"; jev_config_dir )" "I5-2 jev_config_dir = \$JEV_HOME/.config/jev when JEV_CONFIG_DIR is unset"
assert_eq "/x/y" "$( set +u; source "$REPO/scripts/jev/lib_decide.sh"; JEV_CONFIG_DIR=/x/y jev_config_dir )" "I5-2 JEV_CONFIG_DIR wins"
# resolver reads the box env file (hosted base only there => shadow) with JEV_CONFIG_DIR unset
BC="$B/.config/jev"; mkdir -p "$BC"; printf 'JEV_BASE_URL=%s\n' "$HOSTED" > "$BC/env"; promoted "$BC/jev-thresholds.json"
assert_eq "shadow	hosted-or-non-loopback-base-url(env-file)" "$(eff enforce "" "$T/det.json" | strip)" "I5-2 resolver finds the box env file via JEV_HOME"

# ---- m5-1: env-file evaluated like a shell ------------------------------------------------------------------------------
envbase() { fx "$1"; printf '%b' "$2" > "$JEV_CONFIG_DIR/env"; }
r() { eff enforce "" "$T/det.json" | strip; }
envbase c1 "JEV_BASE_URL=$LOOP\nJEV_BASE_URL=$HOSTED\n";  assert_eq "shadow	hosted-or-non-loopback-base-url(env-file)" "$(r)" "m5-1 loopback then hosted (last wins) => shadow"
envbase c2 "JEV_BASE_URL=$HOSTED\nJEV_BASE_URL=$LOOP\n";  assert_eq "shadow	hosted-or-non-loopback-base-url(env-file)" "$(r)" "m5-1 hosted then loopback (ANY occurrence hosted) => shadow"
envbase c3 "export JEV_BASE_URL=$HOSTED\n";               assert_eq "shadow	hosted-or-non-loopback-base-url(env-file)" "$(r)" "m5-1 'export JEV_BASE_URL=hosted' honoured => shadow"
envbase c4 "JEV_BASE_URL=\"$HOSTED\"\n";                  assert_eq "shadow	hosted-or-non-loopback-base-url(env-file)" "$(r)" "m5-1 quoted hosted value => shadow"
envbase c5 'JEV_BASE_URL=$SOMEWHERE\n';                   assert_eq "shadow	hosted-or-non-loopback-base-url(env-file)" "$(r)" "m5-1 a value needing shell expansion cannot be determined => shadow"
envbase c6 "JEV_BASE_URL=$LOOP\nexport JEV_BASE_URL=$LOOP\n"; assert_eq "enforce	promoted+validated" "$(r)" "m5-1 control: two loopback assignments (plain + export) => enforce"
envbase c7 "  export   JEV_BASE_URL='$LOOP'\n";           assert_eq "enforce	promoted+validated" "$(r)" "m5-1 control: indented export with single quotes, loopback => enforce"
# JEV_MODE read the same way (last assignment, export form) by status
fx c8; printf 'JEV_MODE=enforce\nJEV_MODE=shadow\n' > "$JEV_CONFIG_DIR/env"
assert_eq "shadow" "$(status_json | jq -r .mode_stored)" "m5-1 JEV_MODE: last assignment wins in jev-status"
fx c9; printf 'export JEV_MODE=enforce\nJEV_BASE_URL=%s\n' "$HOSTED" > "$JEV_CONFIG_DIR/env"
assert_eq "enforce" "$(status_json | jq -r .mode_stored)" "m5-1 JEV_MODE: 'export JEV_MODE=' is read by jev-status"
env JEV_MODE=enforce bash "$REG" >/dev/null 2>&1
assert_eq "shadow" "$(shell_mode "$JEV_CONFIG_DIR/env")" "m5-1 register rewrites an 'export JEV_MODE=' line: a shell sourcing the file sees shadow"

# ---- m5-2: toolkit MCP locations ---------------------------------------------------------------------------------------
fx d1; mkdir -p "$HOME/.claude-acct1"; jq -n --arg u "$HOSTED" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u}}}}' > "$HOME/.claude-acct1/.mcp.json"
assert_eq "shadow	hosted-or-non-loopback-base-url(mcp-entry)" "$(JEV_BASE_URL="$LOOP" eff enforce "" "$T/det.json" | strip)" "m5-2 hosted base in \$HOME/.claude-*/.mcp.json => shadow"
fx d2; jq -n --arg u "$HOSTED" '{projects:{"/p":{mcpServers:{jev:{env:{JEV_BASE_URL:$u}}}}}}' > "$HOME/.claude.json"
assert_eq "shadow	hosted-or-non-loopback-base-url(mcp-entry)" "$(JEV_BASE_URL="$LOOP" eff enforce "" "$T/det.json" | strip)" "m5-2 hosted base nested in ~/.claude.json => shadow"
fx d3; mkdir -p "$HOME/.claude-acct1"; jq -n --arg u "$LOOP" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u}}}}' > "$HOME/.claude-acct1/.mcp.json"; jq -n --arg u "$LOOP" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u}}}}' > "$HOME/.claude.json"
assert_eq "enforce	promoted+validated" "$(JEV_BASE_URL="$LOOP" eff enforce "" "$T/det.json" | strip)" "m5-2 control: loopback in every toolkit MCP location => enforce"

# ---- m5-3: clock / age knobs are JEV_TEST-only ---------------------------------------------------------------------------
fx e1; mkdet "$T/det.json" llmctl-decide "http://127.0.0.1:9" 1700000000
assert_eq "enforce	promoted+validated" "$(JEV_BASE_URL="$LOOP" eff enforce "" "$T/det.json" | strip)" "m5-3 control: JEV_TEST=1 honours JEV_NOW_EPOCH (old record counts fresh)"
assert_eq "shadow	detection-record-stale-or-undated" "$(unset JEV_TEST; JEV_BASE_URL="$LOOP" eff enforce "" "$T/det.json" | sed 's/;override-ignored.*//')" "m5-3 JEV_TEST unset: JEV_NOW_EPOCH ignored => old record is stale"
assert_eq "shadow	detection-record-stale-or-undated" "$(unset JEV_TEST; JEV_NOW_EPOCH=1700000000 JEV_DETECTION_MAX_AGE=99999999999 JEV_BASE_URL="$LOOP" eff enforce "" "$T/det.json" | sed 's/;override-ignored.*//')" "m5-3 JEV_TEST unset: JEV_DETECTION_MAX_AGE ignored too"

# ---- m5-4: malformed .mcp.json -------------------------------------------------------------------------------------------
fx f1; printf '{"mcpServers":{"jev":{"env":{"JEV_BASE_URL":"%s"' "$HOSTED" > "$B/.mcp.json"
assert_eq "shadow	hosted-or-non-loopback-base-url(mcp-entry)" "$(JEV_BASE_URL="$LOOP" eff enforce "" "$T/det.json" | strip)" "m5-4 malformed .mcp.json carrying a hosted URL => shadow"
fx f2; printf '{"mcpServers": {broken' > "$B/.mcp.json"
assert_eq "shadow	hosted-or-non-loopback-base-url(mcp-unparseable)" "$(JEV_BASE_URL="$LOOP" eff enforce "" "$T/det.json" | strip)" "m5-4 unparseable .mcp.json with no readable URL fails closed => shadow"

# ---- m5-5 / M4: bootstrap stage 5 owns the MCP mode too; stored enforce survives a re-run ---------------------------------
mcp_mode() { jq -r '.mcpServers.jev.env.JEV_MODE // empty' "$B/.mcp.json"; }
fx g1; printf 'JEV_MODE=enforce\nJEV_BASE_URL=%s\n' "$LOOP" > "$JEV_CONFIG_DIR/env"; rm -f "$JEV_CONFIG_DIR/jev-thresholds.json"
jq -n --arg u "$LOOP" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u,JEV_MODE:"enforce"}}}}' > "$B/.mcp.json"
bash "$BS" --non-interactive >/dev/null 2>&1 </dev/null
assert_eq "shadow" "$(mode_of "$JEV_CONFIG_DIR/env")" "m5-5 no promoted threshold: bootstrap downgrades the env file to shadow"
assert_eq "shadow" "$(mcp_mode)" "m5-5 ... and downgrades the MCP entry's env.JEV_MODE too"
fx g2; printf 'JEV_MODE=enforce\nJEV_BASE_URL=%s\n' "$LOOP" > "$JEV_CONFIG_DIR/env"
jq -n --arg u "$LOOP" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u,JEV_MODE:"shadow"}}}}' > "$B/.mcp.json"
bash "$BS" --non-interactive >/dev/null 2>&1 </dev/null
assert_eq "enforce" "$(mode_of "$JEV_CONFIG_DIR/env")" "M4 stored enforce with every enforce condition holding SURVIVES a bootstrap re-run without --enforce"
assert_eq "enforce" "$(mcp_mode)" "m5-5 ... and the MCP entry follows to enforce"
fx g3; printf 'JEV_MODE=enforce\nJEV_BASE_URL=%s\n' "$LOOP" > "$JEV_CONFIG_DIR/env"
jq -n --arg u "$LOOP" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u,JEV_MODE:"shadow"}}}}' > "$B/.mcp.json"
assert_eq "true" "$(status_json | jq -r '.mcp_mode_mismatch')" "m5-5 jev-status reports an MCP/env mode mismatch (json)"
bash "$ST" >"$T/h.out" 2>/dev/null; assert_contains "$T/h.out" "MCP" "m5-5 jev-status human view names the MCP mismatch"
jq -n --arg u "$LOOP" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u,JEV_MODE:"enforce"}}}}' > "$B/.mcp.json"
assert_eq "false" "$(status_json | jq -r '.mcp_mode_mismatch')" "m5-5 control: matching modes => no mismatch"

# ---- m5-6 / m5-7: documentation truth ------------------------------------------------------------------------------------
assert_not_contains "$REPO/docs/jev/governance-guide.md" "(or unset)" "m5-6 governance guide: no contradictory '(or unset)'"
assert_not_contains "$ST" "contacts no endpoint" "m5-7 jev-status header no longer claims it contacts no endpoint"
assert_not_contains "$REPO/docs/jev/bootstrap-reference.md" "whether the real llmctl accepts" "I5-1 bootstrap reference no longer calls the argv shape UNCONFIRMED"

# ---- nit: make_fixture_env leaks no tmp dirs ----------------------------------------------------------------------------
LK="$(mktemp -d)"
( export TMPDIR="$LK"; source "$HERE/lib_assert.sh"; FIXTURES="$HERE/fixtures"; make_fixture_env x1; make_fixture_env x2; make_fixture_env x3 ) >/dev/null 2>&1
assert_eq "0" "$(find "$LK" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" "nit make_fixture_env x3 leaves no mktemp dirs behind"
rmdir "$LK" 2>/dev/null || true
finish
