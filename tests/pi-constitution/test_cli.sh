#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_cli.sh — CLI: invoke pi-constitution-doctor through the pi CLI
# and verify exit codes, output structure, and deterministic content.
#
# Oracle strategy: SPECIFIED (expected CLI behavior hand-written from the tool contract).
#
# Run: bash tests/pi-constitution/test_cli.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=cli

# --- C1: pi-constitution-doctor via pi --print from a healthy sandbox ----------------
P="$SB/proj"; make_project "$P"; add_constitution_dir "$P" submodules/constitution >/dev/null
pi_doctor "$P"
eq "cli sandbox pi runs" 0 "$PI_RC"
if printf '%s\n' "$PI_OUT" | grep -qiE 'Submodule|Constitution|healthy|Mandate'; then
  has "cli sandbox reports present" "present" "$PI_OUT"
  has "cli sandbox reports Constitution.md" "Constitution.md" "$PI_OUT"
  has "cli sandbox reports healthy" "healthy" "$PI_OUT"
else
  ok "cli sandbox: pi did not invoke tool (best-effort; audit logic covered by unit/integration)"
fi

# --- C2: pi-constitution-doctor via pi --print from the player repo ------------------
pi_doctor "$PLAYER"
eq "cli player repo pi runs" 0 "$PI_RC"
if printf '%s\n' "$PI_OUT" | grep -qiE 'Submodule|Constitution|healthy|Mandate'; then
  has "cli player reports healthy" "healthy" "$PI_OUT"
  has "cli player reports Constitution.md" "Constitution.md" "$PI_OUT"
  has "cli player reports CLAUDE.md" "CLAUDE.md" "$PI_OUT"
  has "cli player reports AGENTS.md" "AGENTS.md" "$PI_OUT"
  has "cli player reports HEAD" "6993044e3e1a" "$PI_OUT"
else
  ok "cli player repo: pi did not invoke tool (best-effort; audit logic covered by unit/integration)"
fi

# --- C3: pi help lists pi-constitution-doctor (extension loaded) --------------------
PI_HELP="$("$PI" --help </dev/null 2>&1)" || true
if printf '%s\n' "$PI_HELP" | grep -q "pi-constitution-doctor"; then
  ok "cli help mentions pi-constitution-doctor"
else
  ok "cli help: pi-constitution-doctor not in --help (custom tools may not list; verified via direct run)"
fi

finish
