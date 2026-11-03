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
#     --root <dir>   project root to audit (default: $CONSUMER_ROOT or the gate-location default: superproject if vendored as a submodule, else the canon repo itself).
#     --standalone-canon  DECLARE that --root/the default root is the canon repository itself. Only then, and only
#                    when the root has NO token-bound UI system (no design-token artifact matching OD_TOKEN_GLOBS AND
#                    no manifest in OD_MANIFEST_GLOBS referencing open-design; PATH is deliberately ignored so the
#                    verdict is host-independent), the gate records an honest SKIP (exit 3,
#                    VERDICT line reason=topology_unsupported) instead of FAILing on the canon's own report styles
#                    (they are not a UI product). If the root HAS a token artifact or declares OpenDesign, the
#                    declaration changes nothing and the audit runs (a consumer that has the surface and violates
#                    it still FAILs). No environment opt-in exists, by design (an ambient variable would turn a
#                    real consumer FAIL into a SKIP) -- same precedent as CM-CANONICAL-ROOT-CLARITY.
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
#   The four OD_*_GLOBS decide WHAT is scanned (a glob list matching nothing would turn a FAIL into a SKIP), so the
#   ENVIRONMENT form is GUARDED (honoured only under HELIX_TEST_MODE=1, scripts/lib/gate_env_override.sh). A consumer
#   registers its paths with the explicit flags --theme-globs / --token-globs / --visreg-globs / --manifest-globs
#   (an explicit flag is not ambient and is always honoured).
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
#   3 — SKIP (distinct, never a PASS): --standalone-canon declared and no token-bound UI system present.
#   A final `OD-VERDICT<TAB>PASS|FAIL|SKIP<TAB>...` line is machine-readable.
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

standalone_decl=0
od_cli_theme=""; od_cli_token=""; od_cli_visreg=""; od_cli_manifest=""
root="${CONSUMER_ROOT:-}"   # empty => resolved from the gate location after arg parsing (lib/default_scan_root.sh), NOT from cwd
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --standalone-canon) standalone_decl=1; shift ;;
        --theme-globs)    od_cli_theme="${2:?--theme-globs needs a value}"; shift 2 ;;
        --token-globs)    od_cli_token="${2:?--token-globs needs a value}"; shift 2 ;;
        --visreg-globs)   od_cli_visreg="${2:?--visreg-globs needs a value}"; shift 2 ;;
        --manifest-globs) od_cli_manifest="${2:?--manifest-globs needs a value}"; shift 2 ;;
        -h|--help) awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

if [ -z "$root" ]; then
    # shellcheck source=/dev/null
    . "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib/default_scan_root.sh" 2>/dev/null \
        && root="$(cm_default_scan_root "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)")"
    [ -n "$root" ] || { echo "${GATE}: cannot resolve a default scan root from the gate location; pass --root" >&2; exit 2; }
fi
[ -d "$root" ] || { echo "${GATE}: project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

# ---- consumer-registered paths (§11.4.35) with sane defaults (§11.4.28) ----
# verdict-affecting ambient overrides are guarded (11.4.201(6)-(8)): honoured only under HELIX_TEST_MODE=1 (+ temp path for paths)
_ge_lib="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/../lib/gate_env_override.sh"
# shellcheck source=/dev/null
if [ -r "$_ge_lib" ]; then . "$_ge_lib"; else cm_gate_env_set() { printf -v "$1" '%s' "$3"; [ -z "${!2:-}" ] || echo "gate_env_override: ignoring $2 (guard lib missing: fail closed)" >&2; }; fi
cm_gate_env_set OD_THEME_GLOBS OD_THEME_GLOBS "src/theme/* src/styles/* styles/* theme/* themes/* ui/theme/* assets/theme/* *.theme.css tailwind.config.* tokens.css" value
cm_gate_env_set OD_TOKEN_GLOBS OD_TOKEN_GLOBS "tokens.json design-tokens.json design-tokens/* tokens/*.json *.tokens.json open-design.tokens.json src/tokens/* ui/tokens/*" value
cm_gate_env_set OD_VISREG_GLOBS OD_VISREG_GLOBS "**/*visual*regression* **/*visreg* **/__image_snapshots__/* **/*.snap.png tests/visual/* test/visual/* **/*pixel*diff* **/*screenshot*test*" value
cm_gate_env_set OD_MANIFEST_GLOBS OD_MANIFEST_GLOBS ".mcp.json package.json go.mod Cargo.toml pubspec.yaml requirements.txt opencode.json .qwen/settings.json" value
[ -z "$od_cli_theme" ]    || OD_THEME_GLOBS="$od_cli_theme"
[ -z "$od_cli_token" ]    || OD_TOKEN_GLOBS="$od_cli_token"
[ -z "$od_cli_visreg" ]   || OD_VISREG_GLOBS="$od_cli_visreg"
[ -z "$od_cli_manifest" ] || OD_MANIFEST_GLOBS="$od_cli_manifest"

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

# ---- Standalone-canon honest SKIP (declared invocation only; §11.4.201(1), §11.4.3, §11.4.69 topology_unsupported) ----
if [ "$standalone_decl" = 1 ]; then
    # F5: the declaration is only honoured for a real canon root (Constitution.md at the root, not a vendored submodule)
    # shellcheck source=/dev/null
    . "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib/default_scan_root.sh" 2>/dev/null \
        && cm_is_canon_root "$root" || {
        echo "${GATE}: --standalone-canon refused: ${root} is not a canon repository (needs Constitution.md at its root and not a vendored submodule); not a SKIP" >&2
        exit 2
    }
    od_manifest_decl=""
    for m in $OD_MANIFEST_GLOBS; do
        for f in "$root"/$m; do
            [ -f "$f" ] || continue
            if grep -qiE 'open[-_]?design' "$f"; then od_manifest_decl="1"; break 2; fi
        done
    done
    if [ -z "${token_files//[$' \t\r\n']/}" ] && [ -z "$od_manifest_decl" ]; then
        echo "⏭️  SKIP ${GATE}: standalone canon DECLARED and ${root} has no token-bound UI system (no design-token artifact, no manifest referencing open-design) — topology_unsupported (§11.4.3/§11.4.69), not a PASS"
        printf 'OD-VERDICT\tSKIP\treason=topology_unsupported\tstandalone_canon=declared\n'
        exit 3
    fi
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
    printf 'OD-VERDICT\tFAIL\tfailed=%s\n' "$fail"
    exit 1
fi
echo "✅ ${GATE}: PASS — all ${applicable_checks} applicable sub-checks passed"
printf 'OD-VERDICT\tPASS\tchecks=%s\n' "$applicable_checks"
exit 0
