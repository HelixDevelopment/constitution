#!/usr/bin/env bash
# cm_opendesign_ui_system_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-OPENDESIGN-UI-SYSTEM + CM-COVENANT-114-162-PROPAGATION (§11.4.162).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the two §11.4.162 gates are NOT bluffs: builds disposable fixtures,
# plants a deliberate violation, and ASSERTS each gate FAILs (nonzero) on the
# planted violation; then asserts each gate PASSes (zero) on a clean fixture.
# The pair only passes if BOTH gates correctly FAIL-on-mutation AND PASS-on-clean
# — the §1.1 discriminator that a gate's assertion is real, not a tautology.
#
# Mutations planted:
#   * propagation gate: a carrier (CLAUDE.md) MISSING the `11.4.162` literal
#     → CM-COVENANT-114-162-PROPAGATION MUST FAIL.
#   * ui-system gate: a theme source with a hardcoded hex AND no token file,
#     plus a light-only (no dark) variant → CM-OPENDESIGN-UI-SYSTEM MUST FAIL.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_opendesign_ui_system_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the two sibling gate scripts. Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.162, §11.4.3 (clean fixture exercises the
#   SKIP-vs-PASS boundary), §11.4.28 (gates driven via env, no hardcoded paths).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — both gates FAIL-on-mutation AND PASS-on-clean (the §1.1 proof holds).
#   1 — a gate did not FAIL on its planted mutation, or did not PASS clean.
#   2 — environment error (a gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROP_GATE="${SCRIPT_DIR}/cm_covenant_114_162_propagation.sh"
UI_GATE="${SCRIPT_DIR}/cm_opendesign_ui_system.sh"

for g in "$PROP_GATE" "$UI_GATE"; do
    [ -f "$g" ] || { echo "META: gate script missing: $g" >&2; exit 2; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/od_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
note() { echo "$@"; }
expect_fail() { # $1=desc  $2..=command
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        note "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        note "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}
expect_pass() { # $1=desc  $2..=command
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        note "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
    else
        note "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false alarm!)"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for §11.4.162 gates"
echo "fixtures under: $TMP"
echo "======================================================================"

# ===================================================================
# PART 1 — CM-COVENANT-114-162-PROPAGATION
# ===================================================================

# --- 1a. MUTATED fleet: a carrier MISSING the 11.4.162 literal ---
MUT_FLEET="$TMP/prop_mut"
mkdir -p "$MUT_FLEET/sub"
# good carrier (carries the anchor)
printf '**§11.4.162 — OpenDesign anchor block (fixture).**\nanchor 11.4.162 present here\n' > "$MUT_FLEET/AGENTS.md"
# MUTATION: this carrier omits the literal entirely
printf '# Project carrier\nno anchor here at all\n' > "$MUT_FLEET/CLAUDE.md"
expect_fail "propagation gate / missing-anchor carrier" \
    bash "$PROP_GATE" --root "$MUT_FLEET" --quiet

# --- 1b. CLEAN fleet: every carrier carries the literal ---
CLEAN_FLEET="$TMP/prop_clean"
mkdir -p "$CLEAN_FLEET"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '# carrier %s\n**§11.4.162 — OpenDesign anchor block (fixture).** literal 11.4.162\n' "$c" \
        > "$CLEAN_FLEET/$c"
done
expect_pass "propagation gate / clean fleet" \
    bash "$PROP_GATE" --root "$CLEAN_FLEET" --quiet

# ===================================================================
# PART 2 — CM-OPENDESIGN-UI-SYSTEM
# ===================================================================

# --- 2a. MUTATED project: hardcoded hex + no token file + light-only +
#         no visual-regression + OpenDesign not declared ---
MUT_UI="$TMP/ui_mut"
mkdir -p "$MUT_UI/theme"
# MUTATION: theme with hardcoded hex, only a "light" variant, no "dark"
cat > "$MUT_UI/theme/app.theme.css" <<'CSS'
/* light theme only — ad-hoc hardcoded hex, the §11.4.162 anti-pattern */
:root.light { --primary: #A8DD22; --bg: #FFFFFF; }
CSS
expect_fail "ui-system gate / hex-without-token + light-only + no visreg + undeclared" \
    env CONSUMER_ROOT="" OD_THEME_GLOBS="theme/*.css" \
        OD_TOKEN_GLOBS="tokens.json" \
        OD_VISREG_GLOBS="tests/visual/*" \
        OD_MANIFEST_GLOBS="package.json" \
    bash "$UI_GATE" --root "$MUT_UI"

# --- 2b. CLEAN project: token file present + consumed (no hex in theme) +
#         light+dark in tokens + visual-regression test + OD declared ---
CLEAN_UI="$TMP/ui_clean"
mkdir -p "$CLEAN_UI/theme" "$CLEAN_UI/tokens" "$CLEAN_UI/tests/visual"
# declared dependency
cat > "$CLEAN_UI/package.json" <<'JSON'
{ "name": "x", "dependencies": { "open-design": "^1.0.0" } }
JSON
# token artifact with light + dark, no raw hex in theme source
cat > "$CLEAN_UI/tokens/design-tokens.json" <<'JSON'
{ "color": { "light": { "primary": "primary" }, "dark": { "primary": "primary" } } }
JSON
# theme consumes tokens — references token names, no inline hex
cat > "$CLEAN_UI/theme/app.theme.css" <<'CSS'
/* consumes OpenDesign tokens: light + dark, no hardcoded hex */
:root.light { --primary: var(--token-primary-light); }
:root.dark  { --primary: var(--token-primary-dark); }
CSS
# visual-regression test
printf 'visual regression placeholder\n' > "$CLEAN_UI/tests/visual/theme_visreg_test.txt"
expect_pass "ui-system gate / clean project (tokens consumed, light+dark, visreg, declared)" \
    env CONSUMER_ROOT="" OD_THEME_GLOBS="theme/*.css" \
        OD_TOKEN_GLOBS="tokens/*.json" \
        OD_VISREG_GLOBS="tests/visual/*" \
        OD_MANIFEST_GLOBS="package.json" \
    bash "$UI_GATE" --root "$CLEAN_UI"

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS — both §11.4.162 gates FAIL-on-mutation AND PASS-on-clean (§1.1 proof holds)"
else
    echo "❌ META FAIL — a §11.4.162 gate is a bluff (did not FAIL on mutation OR failed clean)"
fi
exit "$rc"
