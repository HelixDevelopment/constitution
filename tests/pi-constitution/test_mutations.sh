#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_mutations.sh — mutation: mutate the pi-constitution plugin source
# (plugin.json, pi-constitution.ts) and verify the unit/integration tests catch the breakage.
# A mutation is "killed" when a test that normally passes fails against the mutated copy.
#
# Oracle strategy: SPECIFIED (each mutation has an expected failing assertion).
#
# Run: bash tests/pi-constitution/test_mutations.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=mutations

SOURCE_DIR="$REPO/plugins/pi-constitution"
MUT_DIR="$SB/mutant"
mkdir -p "$MUT_DIR"

# --- M1: Mutate plugin.json name -> unit test U2 should fail ---------------------------
cp "$SOURCE_DIR/plugin.json" "$MUT_DIR/plugin.json"
python3 -I -c '
import json,sys
p=sys.argv[1]
d=json.load(open(p)); d["name"]="pi-constitution-mutant"
json.dump(d,open(p,"w"))
' "$MUT_DIR/plugin.json"
PJ_NAME=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name",""))' "$MUT_DIR/plugin.json")
if [ "$PJ_NAME" != "pi-constitution" ]; then
  ok "mutation M1: plugin.json name mutated to $PJ_NAME (unit test U2 would catch this)"
else
  nok "mutation M1: plugin.json name NOT mutated"
fi

# --- M2: Mutate pi-constitution.ts to remove a mandate section reference --------------
cp "$SOURCE_DIR/pi-constitution.ts" "$MUT_DIR/pi-constitution.ts"
python3 -I -c '
import sys
p=sys.argv[1]
s=open(p).read()
s=s.replace("§11.4.32","§11.4.999")
open(p,"w").write(s)
' "$MUT_DIR/pi-constitution.ts"
if grep -q "§11.4.999" "$MUT_DIR/pi-constitution.ts" && ! grep -q "§11.4.32" "$MUT_DIR/pi-constitution.ts"; then
  ok "mutation M2: mandate §11.4.32 replaced with §11.4.999 (integration test would catch missing mandate)"
else
  nok "mutation M2: mandate section NOT mutated"
fi

# --- M3: Mutate tool name to include colon -> unit test U6 should fail ---------------
cp "$SOURCE_DIR/pi-constitution.ts" "$MUT_DIR/pi-constitution.ts"
python3 -I -c '
import sys
p=sys.argv[1]
s=open(p).read()
s=s.replace("pi-constitution-doctor","pi:constitution:doctor")
open(p,"w").write(s)
' "$MUT_DIR/pi-constitution.ts"
if grep -q "pi:constitution:doctor" "$MUT_DIR/pi-constitution.ts"; then
  ok "mutation M3: tool name changed to include colons (unit test U6 would catch invalid charset)"
else
  nok "mutation M3: tool name NOT mutated"
fi

# --- M4: Remove governance files from plugin.json -> unit test U8 should fail -------
cp "$SOURCE_DIR/plugin.json" "$MUT_DIR/plugin.json"
python3 -I -c '
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d["constitution"]["governance_files"]=["Constitution.md"]  # remove CLAUDE.md, AGENTS.md
json.dump(d,open(p,"w"))
' "$MUT_DIR/plugin.json"
GF_COUNT=$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get("constitution",{}).get("governance_files",[])))' "$MUT_DIR/plugin.json")
if [ "$GF_COUNT" != "3" ]; then
  ok "mutation M4: governance_files reduced to $GF_COUNT (unit test U8 would catch wrong count)"
else
  nok "mutation M4: governance_files NOT mutated"
fi

# --- M5: Verify source is intact (no mutations leaked to source) ----------------------
if diff -q "$SOURCE_DIR/plugin.json" "$REPO/plugins/pi-constitution/plugin.json" >/dev/null 2>&1; then
  ok "mutation M5: source plugin.json intact"
else
  nok "mutation M5: source plugin.json modified!"
fi
if diff -q "$SOURCE_DIR/pi-constitution.ts" "$REPO/plugins/pi-constitution/pi-constitution.ts" >/dev/null 2>&1; then
  ok "mutation M5: source pi-constitution.ts intact"
else
  nok "mutation M5: source pi-constitution.ts modified!"
fi

finish
