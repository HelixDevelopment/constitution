#!/usr/bin/env bash
# test_bootstrap_idempotent.sh — design §7 test 2.
# Run the wizard twice: resulting-file digests identical; second run reports
# "no-change" per stage; --defer writes pending stamp rc 0; jev-status
# surfaces the pending stamp.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"

make_fixture_env idempotent
make_fixture_constitution_root with-submodules
cp -r "$FIXTURES/home_seed/.claude" "$HOME/.claude"
# Seed the toolkit endpoint cache as `claude-providers sync-jev` would leave it,
# so run 1 -> run 2 is a genuine "inputs unchanged" comparison (otherwise the
# first sync itself changes an input and convergence takes one extra run).
printf '{"endpoints":[]}\n' > "$CMA_PROVIDERS_DIR/jev-endpoints.json"

state_digest() {
  find "$JEV_STATE_DIR" "$JEV_CONFIG_DIR" "$JEV_EVIDENCE_DIR" "$HOME/.claude" -type f \
    ! -name 'bootstrap.pending' 2>/dev/null | sort | xargs sha256sum | sha256sum | awk '{print $1}'
}

bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >"$T/r1.out" 2>"$T/r1.err"
assert_rc 0 "$?" "first run rc 0"
d1="$(state_digest)"

bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >"$T/r2.out" 2>"$T/r2.err"
assert_rc 0 "$?" "second run rc 0"
d2="$(state_digest)"

assert_eq "$d1" "$d2" "resulting-state digests identical across runs"
count_nochange="$(grep -c 'no-change' "$T/r2.err" || true)"
assert_eq "7" "$count_nochange" "second run reports no-change for all 7 stages"
assert_contains "$T/r2.err" "detect-models: no-change" "detect-models no-change line"

# stamp byte-stability
s1="$(sha256sum "$JEV_STATE_DIR/bootstrap.stamp" | awk '{print $1}')"
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >/dev/null 2>&1
s2="$(sha256sum "$JEV_STATE_DIR/bootstrap.stamp" | awk '{print $1}')"
assert_eq "$s1" "$s2" "bootstrap.stamp byte-stable on third run"

# --defer semantics
bash "$REPO/scripts/jev/bootstrap.sh" --defer >"$T/defer.out" 2>"$T/defer.err"
assert_rc 0 "$?" "--defer exits rc 0"
assert_file_exists "$JEV_STATE_DIR/bootstrap.pending" "--defer writes pending stamp"
assert_contains "$T/defer.err" "deferred" "--defer reports deferral"

# pending surfaced by jev-status
if command -v jq >/dev/null 2>&1; then
  pend="$(bash "$REPO/scripts/jev/jev-status.sh" --json | jq -r '.bootstrap.pending')"
  assert_eq "true" "$pend" "jev-status --json surfaces bootstrap.pending=true"
else
  bash "$REPO/scripts/jev/jev-status.sh" >"$T/status.out"
  assert_contains "$T/status.out" "PENDING" "jev-status human output surfaces pending"
fi

# --- negative control: a changed input MUST re-run the affected stage -------
# (otherwise "no-change" is a constant the detector prints regardless of input)
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --enforce >"$T/r4.out" 2>"$T/r4.err"
assert_rc 0 "$?" "changed-input run (--enforce) rc 0"
assert_not_contains "$T/r4.err" "configure: no-change" "NEG: --enforce changes configure inputs, stage is NOT reported no-change"
assert_not_contains "$T/r4.err" "detect-tools: no-change" "NEG: mode is part of stage-1 key, stage re-runs"
n4="$(grep -c 'no-change' "$T/r4.err" || true)"
if [ "$n4" -lt 7 ]; then ok "NEG: fewer than 7 no-change lines after an input change ($n4)"; else fail "NEG: all stages still no-change after an input change"; fi
# --enforce with no calibrated thresholds must NOT flip the mode (needs calibration first)
assert_contains "$JEV_CONFIG_DIR/env" "JEV_MODE=shadow" "NEG: enforce refused without calibrated thresholds, env stays shadow"
# unknown flag is an error, not silently ignored
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --bogus-flag >/dev/null 2>&1
assert_nonzero "$?" "NEG: unknown flag exits nonzero"

# --- convergence with consent and NO pre-seeded cache ------------------------
# The first run itself creates the endpoint cache and wires the agent home, so
# run 2 may legitimately re-run those stages; by run 3 every stage MUST be
# no-change and the state byte-identical to run 2.
make_fixture_env converge
make_fixture_constitution_root with-submodules
cp -r "$FIXTURES/home_seed/.claude" "$HOME/.claude"
for i in 1 2 3; do bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --yes >"$T/c$i.out" 2>"$T/c$i.err"; done
assert_eq "7" "$(grep -c 'no-change' "$T/c3.err" || true)" "converged: run 3 reports no-change for all 7 stages"
cd1="$(state_digest)"
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --yes >/dev/null 2>&1
assert_eq "$cd1" "$(state_digest)" "converged: state byte-identical on a further run"
n2="$(grep -c 'no-change' "$T/c2.err" || true)"
printf 'note - consented first-contact run 2 reported %s/7 no-change (inputs created by run 1 legitimately re-run)\n' "$n2"
assert_eq "1" "$(grep -c 'jev-setup check=0 yes=1' "$STUB_LOG/jev-setup.log")" "converged: agent wiring applied exactly once across 4 runs"

finish
