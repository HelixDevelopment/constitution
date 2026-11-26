#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_integration.sh — integration: pi-constitution plugin wired into a
# consuming project with a real Constitution submodule, verifying the full audit path end to end
# including submodule HEAD capture, governance file detection, and mandate section coverage.
#
# Oracle strategy: SPECIFIED (expected outcomes hand-written from the integration contract).
#
# Run: bash tests/pi-constitution/test_integration.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=integration

# --- I1: Full integration — project + Constitution submodule, audit reports healthy ---------
P="$SB/proj"; make_project "$P"; add_constitution_dir "$P" submodules/constitution >/dev/null
run_audit "$P"
eq "integration sandbox audit exit 0" 0 "$AUDIT_RC"
assert_healthy_audit "$AUDIT_OUT"
has "integration HEAD captured" "$AUDIT_HEAD" "$AUDIT_HEAD"
[ -n "$AUDIT_HEAD" ] && ok "integration submodule HEAD non-empty ($AUDIT_HEAD)" || nok "integration submodule HEAD empty"

# --- I2: Governance file absence breaks integration (all three files required) -------------
for gf in Constitution.md CLAUDE.md AGENTS.md; do
  Pi="$SB/proj_$gf"; make_project "$Pi" >/dev/null
  add_constitution_dir "$Pi" submodules/constitution >/dev/null
  rm -f "$Pi/submodules/constitution/$gf"
  git -C "$Pi/submodules/constitution" add -A && git -C "$Pi/submodules/constitution" commit -q -m "remove $gf"
  run_audit "$Pi"
  eq "integration missing $gf exit non-zero" 1 "$AUDIT_RC"
  assert_unhealthy_audit "$AUDIT_OUT" "constitution_governance_file_missing"
done

# --- I3: Submodule HEAD changes between audits are reflected (drift detection) -------------
Pd="$SB/proj_drift"; make_project "$Pd" >/dev/null
add_constitution_dir "$Pd" submodules/constitution >/dev/null
run_audit "$Pd"; H1="$AUDIT_HEAD"
# Amend the constitution submodule (new commit)
echo "update" >>"$Pd/submodules/constitution/Constitution.md"
git -C "$Pd/submodules/constitution" add -A && git -C "$Pd/submodules/constitution" commit -q -m "update constitution"
run_audit "$Pd"; H2="$AUDIT_HEAD"
[ "$H1" != "$H2" ] && ok "integration HEAD drift detected ($H1 -> $H2)" || nok "integration HEAD drift not detected"

# --- I4: Player repo integration (ground truth) -------------------------------------------
run_audit "$PLAYER"
eq "integration player repo exit 0" 0 "$AUDIT_RC"
assert_healthy_audit "$AUDIT_OUT"
has "integration player HEAD" "6993044e3e1a" "$AUDIT_OUT"

finish
