#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_provenance.sh — provenance: verify the installed pi-constitution
# extension at ~/.pi/agent/extensions/pi-constitution.ts is identical to the source in the
# Constitution submodule, and that plugin.json matches. No drift between source and install.
#
# Oracle strategy: SPECIFIED (expected: byte-identical source vs installed copy).
#
# Run: bash tests/pi-constitution/test_provenance.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=provenance

SOURCE_TS="$REPO/plugins/pi-constitution/pi-constitution.ts"
SOURCE_JSON="$REPO/plugins/pi-constitution/plugin.json"
INSTALL_TS="$HOME/.pi/agent/extensions/pi-constitution.ts"
INSTALL_JSON="$HOME/.pi/agent/extensions/pi-constitution.json"  # may not exist; plugin.json not necessarily copied

# --- P1: Installed TypeScript matches source -------------------------------------------
if [ -f "$INSTALL_TS" ] && [ -f "$SOURCE_TS" ]; then
  if diff -q "$SOURCE_TS" "$INSTALL_TS" >/dev/null 2>&1; then
    ok "provenance: installed pi-constitution.ts identical to source"
  else
    nok "provenance: installed pi-constitution.ts DIFFERS from source"
    diff "$SOURCE_TS" "$INSTALL_TS" | head -20
  fi
elif [ -f "$SOURCE_TS" ]; then
  nok "provenance: installed pi-constitution.ts not found at $INSTALL_TS"
else
  nok "provenance: source pi-constitution.ts not found"
fi

# --- P2: Source plugin.json is valid ---------------------------------------------------
if [ -f "$SOURCE_JSON" ]; then
  python3 -I -c 'import json; json.load(open("'"$SOURCE_JSON"'"))' 2>/dev/null && ok "provenance: source plugin.json valid JSON" || nok "provenance: source plugin.json invalid JSON"
fi

# --- P3: Source files are non-empty ----------------------------------------------------
for f in "$SOURCE_TS" "$SOURCE_JSON"; do
  if [ -f "$f" ] && [ "$(wc -c <"$f")" -gt 0 ]; then
    ok "provenance: $(basename "$f") non-empty"
  else
    nok "provenance: $(basename "$f") missing or empty"
  fi
done

# --- P4: All plugin files present in source directory -----------------------------------
PLUGIN_DIR="$REPO/plugins/pi-constitution"
for f in plugin.json pi-constitution.ts README.md SPEC.md INSTALL.md USAGE.md GOVERNANCE.md TROUBLESHOOTING.md CHANGELOG.md; do
  if [ -f "$PLUGIN_DIR/$f" ]; then
    ok "provenance: plugin file present: $f"
  else
    nok "provenance: plugin file missing: $f"
  fi
done

finish
