#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_unit.sh — unit tests for the pi-constitution plugin (pure checks, no pi runtime).
#
# Covers: plugin.json schema validity, TypeScript forbidden-API absence, tool-name charset,
# name/version alignment between plugin.json and pi-constitution.ts, governance file + mandate
# section lists in plugin.json, and that the plugin sources exist and are non-empty.
#
# Oracle strategy: SPECIFIED (expected outcomes hand-written from the plugin contract, not read back
# from the implementation).
#
# Run: bash tests/pi-constitution/test_unit.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=unit

PLUGIN_DIR="$REPO/plugins/pi-constitution"
PLUGIN_JSON="$PLUGIN_DIR/plugin.json"
PLUGIN_TS="$PLUGIN_DIR/pi-constitution.ts"

# --- U1: plugin.json exists and is valid JSON --------------------------------
check "plugin.json exists" test -f "$PLUGIN_JSON"
if [ -f "$PLUGIN_JSON" ]; then
  PI_JSON_VALID=$(python3 -I -c 'import json,sys; json.load(open(sys.argv[1])); print("valid")' "$PLUGIN_JSON" 2>&1)
  eq "plugin.json is valid JSON" "valid" "$PI_JSON_VALID"
fi

# --- U2: plugin.json has required schema fields -------------------------------
if [ -f "$PLUGIN_JSON" ]; then
  PJ_NAME=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name",""))' "$PLUGIN_JSON")
  PJ_VER=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' "$PLUGIN_JSON")
  PJ_SCHEMA=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("schema",""))' "$PLUGIN_JSON")
  PJ_DESC=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("description",""))' "$PLUGIN_JSON")
  PJ_MAIN=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("main",""))' "$PLUGIN_JSON")
  eq "plugin.json name" "pi-constitution" "$PJ_NAME"
  eq "plugin.json version" "1.0.0" "$PJ_VER"
  eq "plugin.json schema" "pi.extension.v1" "$PJ_SCHEMA"
  has "plugin.json description non-empty" "Pi extension" "$PJ_DESC"
  eq "plugin.json main" "pi-constitution.ts" "$PJ_MAIN"
fi

# --- U3: pi-constitution.ts exists and is non-empty ---------------------------
check "pi-constitution.ts exists" test -f "$PLUGIN_TS"
TS_SIZE=$(wc -c <"$PLUGIN_TS" 2>/dev/null || echo 0)
[ "$TS_SIZE" -gt 0 ] && ok "pi-constitution.ts non-empty ($TS_SIZE bytes)" || nok "pi-constitution.ts empty or missing"

# --- U4: No forbidden Pi ExtensionAPI members ---------------------------------
# pi-constitution.ts must NOT use: pi.cwd(), pi.status, pi.triageError, pi.ask, pi.reply, pi.on("custom_tool")
# (Comments are excluded so a doc line like "not pi.cwd()" does not false-positive.)
if [ -f "$PLUGIN_TS" ]; then
  FORBIDDEN=("pi.cwd()" "pi.status" "pi.triageError" "pi.ask" "pi.reply" 'pi.on("custom_tool")')
  FORBID_FOUND=0
  for f in "${FORBIDDEN[@]}"; do
    if grep -vE '^\s*(//|\*)' "$PLUGIN_TS" | grep -qF -- "$f"; then
      nok "forbidden API present: $f"
      FORBID_FOUND=1
    fi
  done
  if [ "$FORBID_FOUND" -eq 0 ]; then ok "no forbidden Pi ExtensionAPI members"; else nok "forbidden APIs found"; fi
fi

# --- U5: Only documented API members are used ---------------------------------
# Allowed: ctx.cwd (property), ctx.ui.setStatus, ctx.ui.confirm, pi.on, pi.registerTool, pi.exec, pi.sendMessage
if [ -f "$PLUGIN_TS" ]; then
  DOC_USED=0
  for m in "ctx.cwd" "ctx.ui.setStatus" "ctx.ui.confirm" "pi.on(" "pi.registerTool" "pi.exec" "pi.sendMessage"; do
    if grep -qF -- "$m" "$PLUGIN_TS"; then
      DOC_USED=$((DOC_USED+1))
    fi
  done
  [ "$DOC_USED" -ge 6 ] && ok "uses documented Pi ExtensionAPI members (${DOC_USED}/7 found)"
fi

# --- U6: Tool name uses only [a-zA-Z0-9_-] -----------------------------------
if [ -f "$PLUGIN_TS" ]; then
  TOOL_NAME=$(grep -oE 'name: "[a-zA-Z0-9_-]+"' "$PLUGIN_TS" | head -1 | sed 's/name: "//;s/"//')
  eq "pi-constitution-doctor tool name" "pi-constitution-doctor" "$TOOL_NAME"
  # Confirm no colon anywhere in tool name
  if echo "$TOOL_NAME" | grep -q ':'; then
    nok "tool name contains colon"
  else
    ok "tool name has no colon (charset [a-zA-Z0-9_-])"
  fi
fi

# --- U7: name/version alignment between plugin.json and pi-constitution.ts -----
if [ -f "$PLUGIN_JSON" ] && [ -f "$PLUGIN_TS" ]; then
  TS_NAME=$(grep -oE 'PLUGIN_NAME = "[^"]+"' "$PLUGIN_TS" | head -1 | sed 's/PLUGIN_NAME = "//;s/"//')
  TS_VER=$(grep -oE 'PLUGIN_VERSION = "[^"]+"' "$PLUGIN_TS" | head -1 | sed 's/PLUGIN_VERSION = "//;s/"//')
  eq "plugin name aligns (json vs ts)" "$PJ_NAME" "$TS_NAME"
  eq "plugin version aligns (json vs ts)" "$PJ_VER" "$TS_VER"
fi

# --- U8: plugin.json declares required governance files ------------------------
if [ -f "$PLUGIN_JSON" ]; then
  GF_COUNT=$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); g=d.get("constitution",{}).get("governance_files",[]); print(len(g))' "$PLUGIN_JSON")
  eq "governance file count" "3" "$GF_COUNT"
  for gf in Constitution.md CLAUDE.md AGENTS.md; do
    python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1])); g=d.get("constitution",{}).get("governance_files",[])
sys.exit(0 if sys.argv[2] in g else 1)' "$PLUGIN_JSON" "$gf" && ok "governance file declared: $gf" || nok "governance file missing: $gf"
  done
fi

# --- U9: plugin.json declares required mandate sections ------------------------
if [ -f "$PLUGIN_JSON" ]; then
  MS_COUNT=$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); m=d.get("constitution",{}).get("mandate_sections",[]); print(len(m))' "$PLUGIN_JSON")
  eq "mandate section count" "4" "$MS_COUNT"
  for ms in "§11.4.26" "§11.4.28" "§11.4.31" "§11.4.32"; do
    python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1])); m=d.get("constitution",{}).get("mandate_sections",[])
sys.exit(0 if sys.argv[2] in m else 1)' "$PLUGIN_JSON" "$ms" && ok "mandate section declared: $ms" || nok "mandate section missing: $ms"
  done
fi

# --- U10: submodule_path declared ----------------------------------------------
if [ -f "$PLUGIN_JSON" ]; then
  SMP=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("constitution",{}).get("submodule_path",""))' "$PLUGIN_JSON")
  eq "submodule_path" "submodules/constitution" "$SMP"
fi

finish
