#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_attacks.sh — adversarial / attack-surface tests:
# missing submodule, missing governance file, missing mandate section, empty submodule.
# Each case must produce the correct deterministic triage code and NOT report "healthy".
#
# Oracle strategy: SPECIFIED (expected triage codes hand-written from the plugin contract).
#
# Run: bash tests/pi-constitution/test_attacks.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=attacks

# --- A1: Missing submodule -> constitution_submodule_missing ------------------
P="$SB/proj"; make_project "$P" >/dev/null  # no submodules/constitution
run_audit "$P"
eq "attack missing-submodule exit non-zero" 1 "$AUDIT_RC"
assert_unhealthy_audit "$AUDIT_OUT" "constitution_submodule_missing"

# --- A2: Missing governance file -> constitution_governance_file_missing ------
P2="$SB/proj2"; make_project "$P2" >/dev/null
SUB2="$P2/submodules/constitution"; mkdir -p "$SUB2"
cat >"$SUB2/Constitution.md" <<'EOF'
# TEST

### §11.4.26 — fixture
### §11.4.28 — fixture
### §11.4.31 — fixture
### §11.4.32 — fixture
EOF
git -C "$SUB2" init -q -b main && git -C "$SUB2" add -A && git -C "$SUB2" commit -q -m "partial constitution"
run_audit "$P2"
eq "attack missing-govfile exit non-zero" 1 "$AUDIT_RC"
assert_unhealthy_audit "$AUDIT_OUT" "constitution_governance_file_missing"

# --- A3: Missing mandate section -> constitution_mandate_section_missing ------
P3="$SB/proj3"; make_project "$P3" >/dev/null
SUB3="$P3/submodules/constitution"; mkdir -p "$SUB3"
cat >"$SUB3/Constitution.md" <<'EOF'
# TEST

### §11.4.26 — fixture
### §11.4.28 — fixture
EOF
cat >"$SUB3/CLAUDE.md" <<'EOF'
# CLAUDE
EOF
cat >"$SUB3/AGENTS.md" <<'EOF'
# AGENTS
EOF
git -C "$SUB3" init -q -b main && git -C "$SUB3" add -A && git -C "$SUB3" commit -q -m "partial mandates"
run_audit "$P3"
eq "attack missing-mandate exit non-zero" 1 "$AUDIT_RC"
assert_unhealthy_audit "$AUDIT_OUT" "constitution_mandate_section_missing"

# --- A4: Empty submodule directory (git repo without governance files) --------
P4="$SB/proj4"; make_project "$P4" >/dev/null
SUB4="$P4/submodules/constitution"; mkdir -p "$SUB4"
git -C "$SUB4" init -q -b main && git -C "$SUB4" commit -q --allow-empty -m "empty constitution"
run_audit "$P4"
eq "attack empty-submodule exit non-zero" 1 "$AUDIT_RC"
assert_unhealthy_audit "$AUDIT_OUT" "constitution_governance_file_missing"

# --- A5: Healthy case still reports healthy (control) -------------------------
P5="$SB/proj5"; make_project "$P5" >/dev/null
add_constitution_dir "$P5" submodules/constitution >/dev/null
run_audit "$P5"
eq "attack control exit 0" 0 "$AUDIT_RC"
assert_healthy_audit "$AUDIT_OUT"

finish
