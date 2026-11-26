#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_chaos.sh — chaos: inject adverse conditions (missing env, read-only
# files, missing directories, corrupted git state) and verify the audit degrades gracefully
# with correct triage codes instead of crashing.
#
# Oracle strategy: SPECIFIED (each adverse condition produces a specific non-crash outcome).
#
# Run: bash tests/pi-constitution/test_chaos.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=chaos

# --- X1: Missing submodule directory entirely --------------------------------------
P="$SB/proj1"; make_project "$P" >/dev/null
run_audit "$P"
eq "chaos no-submodule exit non-zero" 1 "$AUDIT_RC"
assert_unhealthy_audit "$AUDIT_OUT" "constitution_submodule_missing"

# --- X2: Submodule directory exists but is not a git repo --------------------------
P2="$SB/proj2"; make_project "$P2" >/dev/null
mkdir -p "$P2/submodules/constitution"
echo "not a git repo" >"$P2/submodules/constitution/README.txt"
run_audit "$P2"
eq "chaos non-git-submodule exit non-zero" 1 "$AUDIT_RC"
# Submodule is "present" (dir exists) but governance files missing
has "chaos reports submodule present" "present" "$AUDIT_OUT"
assert_unhealthy_audit "$AUDIT_OUT" "constitution_governance_file_missing"

# --- X3: Read-only governance file can still be read -------------------------------
P3="$SB/proj3"; make_project "$P3" >/dev/null
add_constitution_dir "$P3" submodules/constitution >/dev/null
chmod 444 "$P3/submodules/constitution/Constitution.md"
run_audit "$P3"
eq "chaos read-only file exit 0" 0 "$AUDIT_RC"
has "chaos read-only reports present" "present" "$AUDIT_OUT"

# --- X4: Deeply nested path still works -------------------------------------------
P4="$SB/a/b/c/proj"; make_project "$P4" >/dev/null
add_constitution_dir "$P4" submodules/constitution >/dev/null
run_audit "$P4"
eq "chaos deep path exit 0" 0 "$AUDIT_RC"
assert_healthy_audit "$AUDIT_OUT"

# --- X5: Concurrent-ish sequential audits don't interfere --------------------------
P5="$SB/proj5"; make_project "$P5" >/dev/null
add_constitution_dir "$P5" submodules/constitution >/dev/null
for i in 1 2 3 4 5; do
  run_audit "$P5"
  [ "$AUDIT_RC" -eq 0 ] && ok "chaos sequential run $i exit 0" || nok "chaos sequential run $i exit non-zero"
done

# --- X6: Very long submodule path still resolves ----------------------------------
P6="$(mktemp -d)"
P6="$P6/$(printf 'x%.0s' $(seq 1 200))/proj"  # deep path
make_project "$P6" >/dev/null
add_constitution_dir "$P6" submodules/constitution >/dev/null
run_audit "$P6"
eq "chaos long path exit 0" 0 "$AUDIT_RC"
assert_healthy_audit "$AUDIT_OUT"
chmod -R u+w "$(dirname "$P6")" 2>/dev/null || true
safe_rm_rf "$(dirname "$P6")"

finish
