#!/usr/bin/env bash
# cm_badge_machine_derived_source.sh — CM-BADGE-MACHINE-DERIVED-SOURCE gate
# (§11.4.259 — every README badge is MACHINE-DERIVED, provenance embedded,
# never hand-typed).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.259 mandates every badge be "MACHINE-DERIVED (§11.4.6 no hand-typed
# colors), provenance embedded in tooltip or docs/BADGES.md". This gate
# enforces the docs/BADGES.md provenance-manifest form of that mandate: for
# EVERY badge present in the README's top-of-file badge row (via the shared
# lib_badge_row.sh engine, same placement contract as
# CM-README-BADGE-ROW-AT-TOP), a provenance manifest MUST declare a non-empty
# `Source:` value naming the script/pipeline/data-source that COMPUTES that
# badge — proving the badge's value is generated, not hand-typed into the
# README by an editor.
#
# ── Provenance manifest format (consumer-owned DATA per §11.4.28/§11.4.35) ──
#   Markdown, one `## <badge alt text>` heading per badge, followed within a
#   few non-blank lines by a `Source: <script-or-pipeline-path>` line:
#
#     ## Build
#     Source: scripts/badges/compute_build_badge.sh
#
#     ## Security
#     Source: scripts/testing/security_scan.sh
#
#   The badge alt text (the `![<alt>](...)` text) is the lookup key — it MUST
#   match a `## ` heading in the manifest EXACTLY (case-sensitive).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_badge_machine_derived_source.sh [--root <project-root>] [--readme <path>]
#                                      [--provenance <path>]
#     --root <dir>        project root (default: $CONSUMER_ROOT or ".").
#     --readme <path>     README entry point, relative to --root unless
#                          absolute (default: README.md).
#     --provenance <path> provenance manifest, relative to --root unless
#                          absolute (default: docs/BADGES.md).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-badge OK/FAIL line + final PASS/FAIL banner naming every offending
#   badge alt-text + reason.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed, awk. Sources lib_badge_row.sh + lib_doc_manifest.sh (same
#   directory). Parses clean under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.259 (this gate's mandate), §11.4.6 (no-guessing — a badge with no
#   provenance entry is treated as hand-typed, never assumed machine-derived),
#   §11.4.86 (fingerprint-driven roster sync — the provenance manifest is the
#   roster this gate cross-checks against), lib_badge_row.sh + lib_doc_manifest.sh
#   (shared engines), §1.1 (paired mutation test
#   cm_badge_machine_derived_source_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — no badge row exists (nothing to check) OR every present badge has a
#       non-empty Source: entry in the provenance manifest.
#   1 — at least one present badge has no provenance entry, or an empty one.
#   2 — environment error (root not found, README not found, libs missing).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-BADGE-MACHINE-DERIVED-SOURCE"
ANCHOR="11.4.259"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

root="${CONSUMER_ROOT:-.}"
readme_rel="README.md"
provenance_rel="docs/BADGES.md"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --readme) readme_rel="$2"; shift 2 ;;
        --provenance) provenance_rel="$2"; shift 2 ;;
        -h|--help) sed -n '1,60p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

lib_badge="${here}/lib_badge_row.sh"
[ -f "$lib_badge" ] || { echo "${GATE}: BLIND — lib_badge_row.sh not found at $lib_badge" >&2; exit 2; }
# shellcheck source=lib_badge_row.sh
. "$lib_badge"

lib_manifest="${here}/lib_doc_manifest.sh"
[ -f "$lib_manifest" ] || { echo "${GATE}: BLIND — lib_doc_manifest.sh not found at $lib_manifest" >&2; exit 2; }
# shellcheck source=lib_doc_manifest.sh
. "$lib_manifest"

case "$readme_rel" in
    /*) readme="$readme_rel" ;;
    *) readme="${root}/${readme_rel}" ;;
esac
[ -f "$readme" ] || { echo "${GATE}: BLIND — README not found: $readme" >&2; exit 2; }

row="$(br_badge_row_text "$readme")"
if [ -z "$row" ]; then
    echo "${GATE}: no badge row present at the top of ${readme} — nothing to check (CM-README-BADGE-ROW-AT-TOP governs presence) — SKIP-vacuous"
    echo "${GATE}: PASS — 0 badge(s) present, vacuously compliant (§${ANCHOR})"
    exit 0
fi

case "$provenance_rel" in
    /*) provenance="$provenance_rel" ;;
    *) provenance="${root}/${provenance_rel}" ;;
esac

pstatus="$(dm_check_target "$root" "$provenance_rel")"
if [ "$pstatus" != "OK" ]; then
    echo "${GATE}: FAIL provenance manifest='${provenance}' reason=${pstatus}"
    echo "${GATE}: FAIL — provenance manifest is ${pstatus}, cannot prove any badge is machine-derived (§${ANCHOR})" >&2
    exit 1
fi

# Build the alt -> Source lookup: a "## <alt>" heading followed within the
# next 6 non-blank lines (before the next "## " heading) by "Source: <val>".
_lookup_source() {
    # $1 = badge alt text (exact match against a "## " heading)
    local alt="$1"
    awk -v want="$alt" '
        BEGIN { in_section = 0; found_source = "" }
        /^## / {
            if (in_section && found_source != "") {
                print found_source
                in_section = 0
                found_source = ""
                exit
            }
            heading = $0
            sub(/^## /, "", heading)
            in_section = (heading == want)
            found_source = ""
            next
        }
        in_section && /^Source:[[:space:]]*/ {
            val = $0
            sub(/^Source:[[:space:]]*/, "", val)
            found_source = val
        }
        END {
            if (in_section && found_source != "") print found_source
        }
    ' "$provenance"
}

total=0
fails=0
static_alts="|$(br_static_alts "$root" | paste -sd'|' -)|"

while IFS=$'\t' read -r alt url; do
    [ -n "${alt:-}${url:-}" ] || continue
    case "$static_alts" in *"|$alt|"*) echo "${GATE}: OK badge='${alt}' static (declared in config/static_badges.list; carries no derived colour/value)"; continue ;; esac
    total=$((total + 1))

    src="$(_lookup_source "$alt")"
    if [ -z "$src" ]; then
        fails=$((fails + 1))
        echo "${GATE}: FAIL badge='${alt}' reason=NO_PROVENANCE_ENTRY (no '## ${alt}' section with a non-empty Source: line in ${provenance})"
        continue
    fi

    echo "${GATE}: OK badge='${alt}' source='${src}'"
done < <(br_extract_entries "$row")

echo "${GATE}: SUMMARY readme=${readme} provenance=${provenance} declared=${total} fail=${fails}"

if [ "$fails" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fails}/${total} badge(s) have no machine-derivation provenance entry (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — all ${total} badge(s) have a provenance entry proving machine-derivation (§${ANCHOR})"
exit 0
