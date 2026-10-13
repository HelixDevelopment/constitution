#!/usr/bin/env bash
# cm_opendesign_ui_system.sh — CM-OPENDESIGN-UI-SYSTEM gate (§11.4.162).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Mechanically enforces the §11.4.162 OpenDesign UI design-system mandate on a
# consuming project. Asserts FOUR sub-invariants, each printing PASS/FAIL with
# the evidence that backs it:
#   (a) OpenDesign is a DECLARED dependency (open-design-mcp installed OR a
#       project manifest / .mcp.json references it).
#   (b) A design-token artifact EXISTS and is CONSUMED — i.e. theme sources do
#       NOT carry ad-hoc hardcoded hex colours when no token file exists. A
#       hardcoded `#RRGGBB` literal in a theme source WITH no token artifact is
#       the ad-hoc pattern §11.4.162 forbids → FAIL.
#   (c) LIGHT + DARK variants are both present in the theme sources.
#   (d) Visual-regression tests exist for the UI.
#
# Degrades gracefully (§11.4.3): a project with NO UI surface (no theme sources,
# no UI dirs) SKIPs-with-reason rather than faking a PASS — an honest SKIP, never
# a green-by-absence bluff. The overall verdict is PASS only when every
# applicable sub-check passed; SKIP when there is genuinely no UI surface; FAIL
# on any applicable sub-check failure.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_opendesign_ui_system.sh [--root <project-root>]
#     --root <dir>   project root to audit (default: $CONSUMER_ROOT or "..").
#
# ── Inputs (env, project-agnostic per §11.4.28 — sane defaults, never hardcoded
#    consumer paths) ────────────────────────────────────────────────────────────
#   CONSUMER_ROOT       project root (arg --root takes precedence).
#   OD_THEME_GLOBS      space-separated globs (relative to root) for theme/UI
#                       style sources to scan for hardcoded hex.
#                       Default: common theme paths (see below).
#   OD_TOKEN_GLOBS      space-separated globs for the design-token artifact(s).
#                       Default: common token-file names.
#   OD_VISREG_GLOBS     space-separated globs for visual-regression tests.
#                       Default: common visual-regression test names.
#   OD_MANIFEST_GLOBS   manifests that may declare the OpenDesign dependency.
#                       Default: .mcp.json package.json go.mod Cargo.toml
#                                pubspec.yaml requirements.txt opencode.json
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-sub-check PASS / FAIL / SKIP lines with evidence; final overall verdict;
#   nonzero exit on any applicable FAIL.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, POSIX grep + find. `command -v open-design-mcp` consulted but optional.
#   Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.162 (OpenDesign mandate), §11.4.3 (SKIP-with-reason, never fake PASS),
#   §11.4.28 (decoupling — consumer registers paths via env), §11.4.35
#   (project instantiation), §11.4.74 (extend-don't-reimplement), §1.1 (paired
#   mutation — plant hex-without-token / light-only → this gate FAILs).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — all applicable sub-checks PASS, OR no-UI-surface SKIP.
#   1 — at least one applicable sub-check FAILed.
#   2 — environment error (root not found).
#
# Classification: universal (§11.4.17).

set -euo pipefail
# §11.4.201(7)(c)-class detector fix: OD_VISREG_GLOBS's default patterns use
# `**/` to signal "search recursively at any depth" (e.g.
# `**/*screenshot*test*`). Without `shopt -s globstar`, bash's `**` behaves
# identically to a single `*` — it matches exactly ONE path component, not a
# recursive descent — so a visual-regression suite nested two-or-more levels
# below root (e.g. `e2e/visual/screenshot_test.spec.ts`) is silently missed
# while the glob's OWN syntax claims to find it. Control-needle proven
# 2026-09-22: a 1-level-deep needle matched either way; a 2-level-deep needle
# matched ONLY with globstar enabled. Enabling it here makes every `**`
# pattern in this script behave as its authors' own naming documents.
shopt -s globstar

GATE="CM-OPENDESIGN-UI-SYSTEM"
ANCHOR="11.4.162"

root="${CONSUMER_ROOT:-..}"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        -h|--help) sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done
[ -d "$root" ] || { echo "${GATE}: project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

# ---- consumer-registered paths (§11.4.35) with sane defaults (§11.4.28) ----
OD_THEME_GLOBS="${OD_THEME_GLOBS:-src/theme/* src/styles/* styles/* theme/* themes/* ui/theme/* assets/theme/* *.theme.css tailwind.config.* tokens.css}"
OD_TOKEN_GLOBS="${OD_TOKEN_GLOBS:-tokens.json design-tokens.json design-tokens/* tokens/*.json *.tokens.json open-design.tokens.json src/tokens/* ui/tokens/*}"
OD_VISREG_GLOBS="${OD_VISREG_GLOBS:-**/*visual*regression* **/*visreg* **/__image_snapshots__/* **/*.snap.png tests/visual/* test/visual/* **/*pixel*diff* **/*screenshot*test*}"
OD_MANIFEST_GLOBS="${OD_MANIFEST_GLOBS:-.mcp.json package.json go.mod Cargo.toml pubspec.yaml requirements.txt opencode.json .qwen/settings.json}"

# Expand a space-separated glob list (relative to $root) into existing files.
_expand() {
    # $1 = space-separated glob list
    local g out
    out=""
    for g in $1; do
        for f in "$root"/$g; do
            [ -e "$f" ] && out="$out $f"
        done
    done
    printf '%s' "$out"
}

fail=0
applicable_checks=0

theme_files="$(_expand "$OD_THEME_GLOBS" | tr ' ' '\n' | grep -v '^$' | sort -u || true)"
token_files="$(_expand "$OD_TOKEN_GLOBS" | tr ' ' '\n' | grep -v '^$' | sort -u || true)"
visreg_files="$(_expand "$OD_VISREG_GLOBS" | tr ' ' '\n' | grep -v '^$' | sort -u || true)"

# ---- No-UI-surface honest SKIP (§11.4.3) ----
if [ -z "${theme_files//[$' \t\r\n']/}" ] && [ -z "${token_files//[$' \t\r\n']/}" ] \
   && [ -z "${visreg_files//[$' \t\r\n']/}" ]; then
    echo "⏭️  SKIP ${GATE}: no UI surface detected under ${root} (no theme/token/visreg sources matched OD_*_GLOBS) — §11.4.3 SKIP-with-reason, not a fake PASS"
    exit 0
fi

echo "${GATE} (§${ANCHOR}) — auditing ${root}"
echo "======================================================================"

# ---- (a) OpenDesign declared as a dependency ----
applicable_checks=$((applicable_checks + 1))
od_declared=""
od_evidence=""
if command -v open-design-mcp >/dev/null 2>&1; then
    od_declared="1"; od_evidence="open-design-mcp on PATH ($(command -v open-design-mcp))"
fi
if [ -z "$od_declared" ]; then
    for m in $OD_MANIFEST_GLOBS; do
        for f in "$root"/$m; do
            [ -f "$f" ] || continue
            if grep -qiE 'open[-_]?design' "$f"; then
                od_declared="1"; od_evidence="declared in ${f#"$root"/}"
                break 2
            fi
        done
    done
fi
if [ -n "$od_declared" ]; then
    echo "✅ (a) OpenDesign declared dependency — ${od_evidence}"
else
    echo "❌ (a) OpenDesign NOT a declared dependency — open-design-mcp not on PATH AND no manifest (${OD_MANIFEST_GLOBS}) references open-design"
    fail=$((fail + 1))
fi

# ---- (b) design-token artifact exists AND is consumed (no ad-hoc hex) ----
applicable_checks=$((applicable_checks + 1))
have_token=""
[ -n "${token_files//[$' \t\r\n']/}" ] && have_token="1"

hex_hits=""
if [ -n "${theme_files//[$' \t\r\n']/}" ]; then
    # Scan theme sources for hardcoded 6-digit hex colour literals.
    while IFS= read -r tf; do
        [ -f "$tf" ] || continue
        h="$(grep -onE '#[0-9A-Fa-f]{6}\b' "$tf" 2>/dev/null || true)"
        if [ -n "$h" ]; then
            hex_hits="${hex_hits}\n  ${tf#"$root"/}:\n$(echo "$h" | sed 's/^/    /')"
        fi
    done <<< "$theme_files"
fi

if [ -n "$have_token" ] && [ -z "${hex_hits//[$'\\n ']/}" ]; then
    echo "✅ (b) design-token artifact present AND theme sources free of ad-hoc hex"
    echo "      tokens: $(echo "$token_files" | tr '\n' ' ' | sed "s#$root/##g")"
elif [ -n "$have_token" ] && [ -n "${hex_hits//[$'\\n ']/}" ]; then
    # Token file exists but theme still inlines hex → not genuinely consumed.
    echo "❌ (b) token artifact exists but theme sources still inline hardcoded hex (token not consumed):"
    printf '%b\n' "$hex_hits"
    fail=$((fail + 1))
elif [ -z "$have_token" ] && [ -n "${hex_hits//[$'\\n ']/}" ]; then
    echo "❌ (b) NO design-token artifact AND theme sources carry hardcoded hex (the ad-hoc pattern §11.4.162 forbids):"
    printf '%b\n' "$hex_hits"
    fail=$((fail + 1))
else
    # No token, no hex — theme sources exist but neither tokens nor hex. Cannot
    # prove token consumption; honest FAIL (a UI theme with neither tokens nor
    # any colour is not consuming OpenDesign tokens).
    echo "❌ (b) NO design-token artifact found (globs: ${OD_TOKEN_GLOBS}) — token system not consumed"
    fail=$((fail + 1))
fi

# ---- (c) light + dark variants present ----
applicable_checks=$((applicable_checks + 1))
scan_for_variants="$theme_files
$token_files"
has_light=""; has_dark=""
while IFS= read -r vf; do
    [ -f "$vf" ] || continue
    grep -qiE '\blight\b' "$vf" 2>/dev/null && has_light="1"
    grep -qiE '\bdark\b'  "$vf" 2>/dev/null && has_dark="1"
done <<< "$scan_for_variants"
if [ -n "$has_light" ] && [ -n "$has_dark" ]; then
    echo "✅ (c) light + dark variants both present in theme/token sources"
else
    miss=""
    [ -z "$has_light" ] && miss="light"
    [ -z "$has_dark" ]  && miss="${miss:+$miss + }dark"
    echo "❌ (c) missing theme variant(s): ${miss} — every component MUST ship light + dark (§11.4.162)"
    fail=$((fail + 1))
fi

# ---- (d) visual-regression tests exist for UI ----
applicable_checks=$((applicable_checks + 1))
if [ -n "${visreg_files//[$' \t\r\n']/}" ]; then
    echo "✅ (d) visual-regression tests present"
    echo "      $(echo "$visreg_files" | tr '\n' ' ' | sed "s#$root/##g")"
else
    echo "❌ (d) NO visual-regression tests found (globs: ${OD_VISREG_GLOBS}) — all UI changes MUST be covered (§11.4.162)"
    fail=$((fail + 1))
fi

echo "======================================================================"
if [ "$fail" -gt 0 ]; then
    echo "❌ ${GATE}: FAIL — ${fail}/${applicable_checks} applicable sub-check(s) failed"
    exit 1
fi
echo "✅ ${GATE}: PASS — all ${applicable_checks} applicable sub-checks passed"
exit 0
