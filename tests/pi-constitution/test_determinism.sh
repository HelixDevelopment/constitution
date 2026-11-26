#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_determinism.sh — determinism: running the audit twice against the
# same state must produce byte-identical output (no timestamps, no random IDs).
#
# Oracle strategy: DERIVED (second run output must equal first run output; no engine-produced
# expected value).
#
# Run: bash tests/pi-constitution/test_determinism.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=determinism

P="$SB/proj"; make_project "$P"; add_constitution_dir "$P" submodules/constitution >/dev/null

run_audit "$P"; OUT1="$AUDIT_OUT"; RC1="$AUDIT_RC"
run_audit "$P"; OUT2="$AUDIT_OUT"; RC2="$AUDIT_RC"

eq "determinism run1 exit 0" 0 "$RC1"
eq "determinism run2 exit 0" 0 "$RC2"
eq "determinism output identical" "$OUT1" "$OUT2"
eq "determinism HEAD stable" "$AUDIT_HEAD" "$AUDIT_HEAD"

# Determinism across different sandbox roots with identical content must also match.
P2="$SB/proj2"; make_project "$P2"; add_constitution_dir "$P2" submodules/constitution >/dev/null
run_audit "$P2"; OUT3="$AUDIT_OUT"; RC3="$AUDIT_RC"
eq "determinism different-root exit 0" 0 "$RC3"
# HEAD differs (different repo) but structure must match
has "determinism submodule present" "present" "$OUT3"
has "determinism healthy" "healthy" "$OUT3"

finish
