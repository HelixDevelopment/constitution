#!/usr/bin/env bash
# test_bootstrap_provision_fallback.sh — design §7 test 3.
# (a) submodule present -> submodule checkout path used (source=submodule);
# (b) submodule absent -> managed clone fallback: stub-git records clone with
#     the pinned ref from the fixture helix-deps.yaml;
# (c) diverged managed clone (stub reports local changes) -> operator-required
#     stop, rc != 0, nothing overwritten.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"

# --- (a) submodule present ------------------------------------------------
make_fixture_env provision_a
make_fixture_constitution_root with-submodules
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >/dev/null 2>"$T/err"
assert_rc 0 "$?" "(a) run rc 0"
if command -v jq >/dev/null 2>&1; then
  assert_eq "submodule" "$(jq -r '.tools.llmctl.source' "$JEV_EVIDENCE_DIR/jev-detection.json")" "(a) llmctl source=submodule"
  assert_eq "$JEV_CONSTITUTION_ROOT/submodules/llmctl" "$(jq -r '.tools.llmctl.path' "$JEV_EVIDENCE_DIR/jev-detection.json")" "(a) llmctl path is submodule checkout"
else
  assert_skip "jq absent: (a) provenance assertions skipped"
fi
# git is still used read-only (rev-parse for provenance); a CLONE must not happen
if [ -f "$STUB_LOG/git.log" ]; then
  assert_not_contains "$STUB_LOG/git.log" " clone " "(a) no git clone attempted when submodule present"
else ok "(a) no git invoked at all when submodule present"; fi

# --- (b0) NEG: submodule absent and NO clone consent -> network never touched ---
make_fixture_env provision_b0
make_fixture_constitution_root   # no submodules
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >"$T/b0.out" 2>"$T/b0.err"
assert_rc 0 "$?" "(b0) no-consent run exits 0 (degraded, not fatal)"
if [ -f "$STUB_LOG/git.log" ]; then
  for verb in clone fetch checkout; do assert_not_contains "$STUB_LOG/git.log" " $verb " "(b0) git stub log has no '$verb' without consent"; done
else ok "(b0) git was not invoked at all without consent"; fi
assert_file_absent "$JEV_BOOTSTRAP_HOME/llmctl" "(b0) no llmctl clone dir created without consent"
assert_file_absent "$JEV_BOOTSTRAP_HOME/claude_toolkit" "(b0) no claude_toolkit clone dir created without consent"
assert_file_absent "$STUB_LOG/git-checkout.log" "(b0) no checkout recorded"
assert_eq "unavailable" "$(jq -r '.tools.llmctl.source' "$JEV_EVIDENCE_DIR/jev-detection.json")" "(b0) llmctl recorded source=unavailable"
assert_ne "" "$(jq -r '.tools.llmctl.reason // ""' "$JEV_EVIDENCE_DIR/jev-detection.json")" "(b0) unavailable carries a reason"
assert_file_exists "$JEV_STATE_DIR/bootstrap.pending" "(b0) pending stamp written"
assert_contains "$JEV_STATE_DIR/bootstrap.pending" "consent" "(b0) pending reason names the missing consent"
# each consent form grants the clone: --yes and JEV_BOOTSTRAP_CONSENT=1 (positive controls for the gate)
make_fixture_env provision_b0y; make_fixture_constitution_root
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --yes >/dev/null 2>&1
assert_contains "$STUB_LOG/git.log" "clone --quiet" "(b0) --yes also grants cloning"
make_fixture_env provision_b0e; make_fixture_constitution_root
JEV_BOOTSTRAP_ALLOW_CLONE=1 bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >/dev/null 2>&1
assert_contains "$STUB_LOG/git.log" "clone --quiet" "(b0) JEV_BOOTSTRAP_ALLOW_CLONE=1 grants cloning"

# --- (b4) a failed/unavailable provision is RETRIED; a good one is cached ------
make_fixture_env provision_retry
make_fixture_constitution_root
for i in 1 2; do bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >"$T/retry$i.out" 2>"$T/retry$i.err"; done
assert_contains "$T/retry1.err" "provision: running" "(b4) no-consent run 1 runs provision"
assert_contains "$T/retry2.err" "provision: running" "(b4) no-consent run 2 RETRIES provision (not cached as no-change)"
assert_not_contains "$T/retry2.err" "provision: no-change" "(b4) NEG: unavailable provision never reported no-change"
# once consent is given the retry succeeds, and from then on it is stable
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --allow-clone >"$T/retry3.out" 2>"$T/retry3.err"
assert_eq "clone" "$(jq -r '.tools.llmctl.source' "$JEV_EVIDENCE_DIR/jev-detection.json")" "(b4) consented run succeeds after the failed ones"
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --allow-clone >"$T/retry4.out" 2>"$T/retry4.err"
assert_contains "$T/retry4.err" "provision: no-change" "(b4) successful provision is cached (no-change)"
digest_all() { find "$JEV_STATE_DIR" "$JEV_CONFIG_DIR" "$JEV_EVIDENCE_DIR" -type f ! -name 'bootstrap.pending' | sort | xargs sha256sum | sha256sum | cut -d' ' -f1; }
d1="$(digest_all)"
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --allow-clone >/dev/null 2>&1
assert_eq "$d1" "$(digest_all)" "(b4) two successful runs leave byte-identical state"

# --- (b) submodule absent -> managed clone at pinned ref ------------------
make_fixture_env provision_b
make_fixture_constitution_root   # no submodules
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --allow-clone >/dev/null 2>"$T/err"
assert_rc 0 "$?" "(b) run rc 0"
assert_file_exists "$STUB_LOG/git.log" "(b) git stub recorded clone"
assert_contains "$STUB_LOG/git.log" "clone --quiet git@github.com:HelixDevelopment/llmctl.git $JEV_BOOTSTRAP_HOME/llmctl" "(b) clone url+dest for llmctl"
assert_contains "$STUB_LOG/git.log" "clone --quiet git@github.com:HelixDevelopment/claude_toolkit.git $JEV_BOOTSTRAP_HOME/claude_toolkit" "(b) clone url+dest for toolkit"
assert_contains "$STUB_LOG/git-checkout.log" "llmctl-v1.4.0" "(b) pinned llmctl ref from helix-deps.yaml checked out"
assert_contains "$STUB_LOG/git-checkout.log" "toolkit-v1.28.0" "(b) pinned toolkit ref from helix-deps.yaml checked out"
if command -v jq >/dev/null 2>&1; then
  assert_eq "clone" "$(jq -r '.tools.llmctl.source' "$JEV_EVIDENCE_DIR/jev-detection.json")" "(b) llmctl source=clone"
  assert_eq "llmctl-v1.4.0" "$(jq -r '.tools.llmctl.ref' "$JEV_EVIDENCE_DIR/jev-detection.json")" "(b) llmctl ref pinned in provenance"
else
  assert_skip "jq absent: (b) provenance assertions skipped"
fi

# (b2) the clone URL is the helix-deps.yaml ssh_url, not a hard-coded one
make_fixture_env provision_b2
make_fixture_constitution_root
sed -i 's#git@github.com:HelixDevelopment/llmctl.git#git@example.invalid:fixture/llmctl-from-manifest.git#' "$JEV_CONSTITUTION_ROOT/helix-deps.yaml"
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --allow-clone >/dev/null 2>"$T/err"
assert_contains "$STUB_LOG/git.log" "clone --quiet git@example.invalid:fixture/llmctl-from-manifest.git" "(b2) clone URL comes from helix-deps.yaml ssh_url"
assert_not_contains "$STUB_LOG/git.log" "git@github.com:HelixDevelopment/llmctl.git" "(b2) NEG: no hard-coded fallback URL used when the manifest has one"

# (b3) clone failure is recorded as unavailable, not a crash and not a fake success
make_fixture_env provision_b3
make_fixture_constitution_root
mkdir -p "$T/failgit"; printf '#!/usr/bin/env bash\n[ "${1:-}" = clone ] && exit 128\nexit 0\n' > "$T/failgit/git"; chmod +x "$T/failgit/git"
PATH="$T/failgit:$PATH" bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --allow-clone >/dev/null 2>"$T/err"
assert_rc 0 "$?" "(b3) failed clone does not abort the wizard"
assert_eq "unavailable" "$(jq -r '.tools.llmctl.source' "$JEV_EVIDENCE_DIR/jev-detection.json")" "(b3) failed clone recorded as source=unavailable"

# --- (c) diverged managed clone -> stop, nothing overwritten --------------
make_fixture_env provision_c
make_fixture_constitution_root   # no submodules
# Pre-seed a managed clone with local divergence.
mkdir -p "$JEV_BOOTSTRAP_HOME/llmctl"
echo "operator-local-work" > "$JEV_BOOTSTRAP_HOME/llmctl/LOCAL.txt"
echo '#!/bin/sh' > "$JEV_BOOTSTRAP_HOME/llmctl/install.sh"
GIT_STUB_DIRTY=1 bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --allow-clone >/dev/null 2>"$T/err"
rc=$?
assert_ne "0" "$rc" "(c) diverged managed clone -> rc != 0"
assert_contains "$T/err" "operator-required stop" "(c) error names operator-required stop"
assert_contains "$JEV_BOOTSTRAP_HOME/llmctl/LOCAL.txt" "operator-local-work" "(c) local changes untouched"

finish
