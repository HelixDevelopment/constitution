#!/usr/bin/env bash
# test_bootstrap_noninteractive.sh — design §7 test 1.
# Full wizard run in a fixture host: all 7 stages report, jev-detection.json
# written, bootstrap stamp written, rc 0. Non-TTY without --non-interactive
# must exit rc 2 immediately (<5s, never hangs).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"

make_fixture_env noninteractive
make_fixture_constitution_root with-submodules
# Seed agent homes so stage 4 has something to wire.
cp -r "$FIXTURES/home_seed/.claude" "$HOME/.claude"
cp -r "$FIXTURES/home_seed/.kimi-code" "$HOME/.kimi-code"

# --- full non-interactive run --------------------------------------------
out="$T/run1.out"; err="$T/run1.err"
# consent boundaries (W2): tool installers need --install-tools, agent-home
# editing needs --yes. A fully-consented run is exercised first; the
# no-consent run is the negative control further down.
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --install-tools --yes --report-json "$T/report.jsonl" \
  >"$out" 2>"$err"
rc=$?
assert_rc 0 "$rc" "non-interactive run exits rc 0"

for s in "1/7" "2/7" "3/7" "4/7" "5/7" "6/7" "7/7"; do
  if grep -qF "[jev-bootstrap $s]" "$err"; then ok "stage $s reported"; else fail "stage $s reported"; fi
done

assert_file_exists "$JEV_EVIDENCE_DIR/jev-detection.json" "jev-detection.json written"
if command -v jq >/dev/null 2>&1; then
  assert_eq "llmctl-decide-tiny" "$(jq -r '.endpoints[0].id' "$JEV_EVIDENCE_DIR/jev-detection.json")" "detection records the running local decision profile"
  assert_eq "submodule" "$(jq -r '.tools.llmctl.source' "$JEV_EVIDENCE_DIR/jev-detection.json")" "llmctl provenance source=submodule"
  assert_eq "submodule" "$(jq -r '.tools.claude_toolkit.source' "$JEV_EVIDENCE_DIR/jev-detection.json")" "toolkit provenance source=submodule"
else
  assert_skip "jq absent: detection content assertions skipped"
fi
assert_file_exists "$JEV_STATE_DIR/bootstrap.stamp" "bootstrap stamp written"
assert_file_exists "$STUB_LOG/installers.log" "tool installers invoked"
assert_contains "$STUB_LOG/installers.log" "llmctl/make-install" "llmctl installer ran (consented via --install-tools)"
assert_contains "$STUB_LOG/installers.log" "claude_toolkit/scripts/install.sh" "toolkit installer ran (consented via --install-tools)"
assert_file_exists "$STUB_LOG/jev-setup.log" "per-agent jev-setup invoked"
assert_contains "$STUB_LOG/jev-setup.log" "check=1 yes=0" "jev-setup --check is called first"
assert_contains "$STUB_LOG/jev-setup.log" "check=0 yes=1" "jev-setup applied only with --yes consent"
assert_file_exists "$HOME/.claude/jev-wiring.marker" "claude home wired"
assert_file_exists "$HOME/.kimi-code/jev-wiring.marker" "kimi home wired"
assert_file_exists "$JEV_CONFIG_DIR/env" "jev env file written"
assert_contains "$JEV_CONFIG_DIR/env" "JEV_MODE=shadow" "default mode is shadow"
assert_file_exists "$JEV_STATE_DIR/decisions.jsonl" "decisions.jsonl scaffolded"
assert_file_exists "$T/report.jsonl" "report-json written"
assert_contains "$T/report.jsonl" '"name":"detect-models","result":"ok' "report-json logs detect-models ok"

# --- non-TTY without flag => rc 2, fast ----------------------------------
start=$SECONDS
bash "$REPO/scripts/jev/bootstrap.sh" </dev/null >"$T/rc2.out" 2>"$T/rc2.err"
rc=$?
elapsed=$((SECONDS - start))
assert_rc 2 "$rc" "non-TTY without --non-interactive exits rc 2"
if [ "$elapsed" -lt 5 ]; then ok "rc-2 path returned in ${elapsed}s (<5s, no hang)"; else fail "rc-2 path too slow (${elapsed}s)"; fi
assert_contains "$T/rc2.err" "refusing to hang" "rc-2 error message explains"

# --- NEG: no consent flags => nothing installed, nothing wired, pending recorded
make_fixture_env noconsent
make_fixture_constitution_root with-submodules
cp -r "$FIXTURES/home_seed/.claude" "$HOME/.claude"
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >/dev/null 2>"$T/nc.err"
assert_rc 0 "$?" "no-consent run rc 0 (degraded states are reported, not fatal)"
assert_file_absent "$STUB_LOG/installers.log" "NEG: tool installers did NOT run without --install-tools"
assert_file_absent "$HOME/.claude/jev-wiring.marker" "NEG: agent home NOT edited without --yes"
if [ -f "$STUB_LOG/jev-setup.log" ]; then
  assert_not_contains "$STUB_LOG/jev-setup.log" "yes=1" "NEG: jev-setup never called with --yes without consent"
fi
assert_file_exists "$JEV_STATE_DIR/bootstrap.pending" "NEG: awaiting-consent state is recorded as pending, not hidden"
assert_contains "$JEV_STATE_DIR/bootstrap.pending" "consent" "NEG: pending reason names consent"
# a later consented run discharges the pending stamp
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --yes >/dev/null 2>&1
assert_file_exists "$HOME/.claude/jev-wiring.marker" "consented follow-up run wires the agent home"
assert_file_absent "$JEV_STATE_DIR/bootstrap.pending" "completed run discharges the pending stamp"

# --- NEG: jq is a hard prerequisite => rc 2 (never a pass) -----------------
make_fixture_env nojq
make_fixture_constitution_root
mkdir -p "$T/nojq-bin"
for c in bash env mktemp awk sed grep cat date mkdir rm ls tr cut head tail dirname basename cmp mv cp sort wc sha256sum touch printf true false timeout nice; do
  p="$(command -v "$c" 2>/dev/null || true)"; [ -n "$p" ] && [ -x "$p" ] && ln -sf "$p" "$T/nojq-bin/$c"
done
PATH="$T/nojq-bin" bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >"$T/nojq.out" 2>"$T/nojq.err"
assert_rc 2 "$?" "NEG: missing jq => rc 2 (cannot determine), never 0"
assert_contains "$T/nojq.err" "jq" "NEG: error names the missing prerequisite"
assert_file_absent "$JEV_EVIDENCE_DIR/jev-detection.json" "NEG: no detection evidence fabricated without jq"

# --- NEG: bad enum / missing option value => rc 2 --------------------------
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --agent 'Claude;rm' >/dev/null 2>&1
assert_rc 2 "$?" "NEG: malformed --agent value rejected (rc 2)"
JEV_BOOTSTRAP_MODE=bogus bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >/dev/null 2>&1
assert_rc 2 "$?" "NEG: invalid JEV_BOOTSTRAP_MODE rejected (rc 2)"

finish
