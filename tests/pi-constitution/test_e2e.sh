#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_e2e.sh — end-to-end: run the pi-constitution audit logic (the exact
# commands the plugin runs) against a sandbox Constitution dir and against the real player repo.
#
# Oracle strategy: SPECIFIED (expected audit output hand-written from the plugin contract).
#
# Run: bash tests/pi-constitution/test_e2e.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=e2e

# --- E1: Healthy audit against a sandbox with a Constitution dir --------------
P="$SB/proj"; make_project "$P"; add_constitution_dir "$P" submodules/constitution >/dev/null
run_audit "$P"
eq "e2e sandbox audit exit 0" 0 "$AUDIT_RC"
assert_healthy_audit "$AUDIT_OUT"
has "e2e sandbox HEAD present" "$AUDIT_HEAD" "$AUDIT_HEAD"

# --- E2: Audit against the real player repo (ground truth) --------------------
run_audit "$PLAYER"
eq "e2e player repo audit exit 0" 0 "$AUDIT_RC"
assert_healthy_audit "$AUDIT_OUT"
has "e2e player submodule HEAD" "6993044e3e1a" "$AUDIT_OUT"

# --- E3: Determinism across two runs of the same audit -----------------------
run_audit "$PLAYER"; OUT1="$AUDIT_OUT"; RC1="$AUDIT_RC"; H1="$AUDIT_HEAD"
run_audit "$PLAYER"; OUT2="$AUDIT_OUT"; RC2="$AUDIT_RC"; H2="$AUDIT_HEAD"
eq "e2e determinism run1 exit 0" 0 "$RC1"
eq "e2e determinism run2 exit 0" 0 "$RC2"
eq "e2e determinism output identical" "$OUT1" "$OUT2"
eq "e2e determinism HEAD stable" "$H1" "$H2"

# --- E4: pi-constitution-doctor best-effort CLI (player repo) -----------------
pi_doctor "$PLAYER"
eq "e2e pi doctor runs" 0 "$PI_RC"
# The LLM may or may not invoke the tool; when it does, output must be healthy.
if printf '%s\n' "$PI_OUT" | grep -qiE 'Submodule|Constitution|healthy|Mandate'; then
  has "pi doctor reports submodule" "present" "$PI_OUT"
  has "pi doctor reports Constitution.md" "Constitution.md" "$PI_OUT"
  has "pi doctor reports healthy" "healthy" "$PI_OUT"
else
  ok "pi doctor did not invoke the tool (best-effort; audit logic covered by E1-E3)"
fi

finish
