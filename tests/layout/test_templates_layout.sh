#!/usr/bin/env bash
# tests/layout/test_templates_layout.sh — the project templates default to the
# standard layout (submodules/constitution) and keep a documented legacy note.
# e2e: a consumer CLAUDE.md rendered from templates/CLAUDE.project.md.template
# into a standard-layout project passes CM-CANONICAL-ROOT-CLARITY with the
# consumer root DERIVED (no --consumer-root).
# Usage: bash tests/layout/test_templates_layout.sh
LT_SUITE="templates_layout"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

T="$LAYOUT_SRC_ROOT/templates"
CL="$T/CLAUDE.project.md.template"
lt_check "CLAUDE template: live heading names submodules/constitution" grep -qx '## INHERITED FROM submodules/constitution/CLAUDE.md' "$CL"
lt_check "CLAUDE template: live @import names submodules/constitution" grep -qx '@submodules/constitution/CLAUDE.md' "$CL"
lt_check "CLAUDE template: no live legacy heading/import left" \
    eval '! grep -qE "^(## INHERITED FROM constitution/|@constitution/)" "$CL"'
for f in CLAUDE.project.md.template AGENTS.project.md.template Constitution.project.md.template helix-deps.yaml.template; do
    lt_check "$f: documents the legacy ./constitution layout" grep -qi 'legacy' "$T/$f"
    # every command/path that is not on the legacy-note line uses the standard prefix
    stray="$(grep -nE '(^|[ `(])constitution/(scripts|docs|templates|CLAUDE|AGENTS|Constitution|submodules)' "$T/$f" | grep -vi 'legacy' || true)"
    lt_check "$f: no bare constitution/... path outside the legacy note" test -z "$stray"
    [ -z "$stray" ] || printf '   stray: %s\n' "$stray"
done
lt_check "AGENTS template: base rules at submodules/constitution/AGENTS.md" grep -q 'submodules/constitution/AGENTS.md' "$T/AGENTS.project.md.template"
lt_check "Constitution template: extends submodules/constitution/Constitution.md" grep -q 'submodules/constitution/Constitution.md' "$T/Constitution.project.md.template"
lt_check "helix-deps template: hub layout under <root>/submodules/constitution/submodules" \
    grep -q '<root>/submodules/constitution/submodules/<name>/' "$T/helix-deps.yaml.template"

# e2e: rendered template passes the gate in the standard layout
P="$LT_SB/tpl proj"; R="$P/submodules/constitution"
mkdir -p "$R/scripts/gates" "$R/scripts/lib"
cp "$LAYOUT_SRC_ROOT/scripts/gates/cm_canonical_root_clarity.sh" "$R/scripts/gates/"
cp "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" "$R/scripts/lib/" 2>/dev/null
for f in Constitution.md CLAUDE.md AGENTS.md; do cp "$LAYOUT_SRC_ROOT/$f" "$R/$f"; done
sed 's/<PROJECT NAME>/Layout Fixture/' "$CL" > "$P/CLAUDE.md"
bash "$R/scripts/gates/cm_canonical_root_clarity.sh" --quiet >"$LT_SB/g.out" 2>&1; rc=$?
lt_check "rendered CLAUDE template passes CM-CANONICAL-ROOT-CLARITY (standard layout, derived root) rc=$rc" test "$rc" -eq 0
[ "$rc" -eq 0 ] || tail -3 "$LT_SB/g.out"
lt_summary
