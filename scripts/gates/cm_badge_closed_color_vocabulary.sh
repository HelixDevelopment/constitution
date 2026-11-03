#!/usr/bin/env bash
# cm_badge_closed_color_vocabulary.sh — CM-BADGE-CLOSED-COLOR-VOCABULARY gate
# (§11.4.259 — every README badge uses ONLY the closed color vocabulary
# GREEN / AMBER / RED / GRAY, never an ad-hoc palette).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Locates the README's top-of-file badge row (via the shared lib_badge_row.sh
# engine, same badge-row placement contract as CM-README-BADGE-ROW-AT-TOP)
# and asserts EVERY badge entry in it carries an unambiguous color token drawn
# from the closed vocabulary {green, amber, red, gray, grey (British-spelling
# alias for gray, treated as the same closed-set member)}. A badge whose URL
# or alt text carries no recognisable color token at all, OR one whose color
# word falls OUTSIDE the closed set (e.g. "yellow", "blue", "brightgreen" —
# shields.io's own decorative variant, which this gate treats as OUTSIDE the
# closed set on purpose, per the honest boundary below), FAILs.
#
# Honest boundary (§11.4.6): a strict closed-vocabulary match is used
# (`green`/`amber`/`red`/`gray`/`grey` as a whole separated token) — a
# palette variant like shields.io's `brightgreen` is DELIBERATELY treated as
# a DIFFERENT token, not silently folded into `green`; §11.4.259 mandates a
# CLOSED vocabulary specifically to prevent ad-hoc palette drift, and a
# generator emitting `brightgreen` is exactly the drift this gate is meant to
# catch. Consumers whose badge-generation tooling emits shields.io's decorative
# names MUST configure that tooling to emit the closed-set literal color
# words instead — this gate does not paper over the mismatch.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_badge_closed_color_vocabulary.sh [--root <project-root>] [--readme <path>]
#     --root <dir>     project root (default: $CONSUMER_ROOT or ".").
#     --readme <path>  README entry point, relative to --root unless
#                       absolute (default: README.md).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-badge OK/FAIL line + final PASS/FAIL banner naming every offending
#   badge alt-text + reason.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed. Sources lib_badge_row.sh (same directory). Parses clean
#   under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.259 (this gate's mandate), lib_badge_row.sh (shared badge-row +
#   color-token extraction engine), §11.4.6 (no-guessing — strict closed-set
#   token match, no fuzzy/synonym folding), §1.1 (paired mutation test
#   cm_badge_closed_color_vocabulary_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — no badge row exists (nothing to check — CM-README-BADGE-ROW-AT-TOP is
#       the gate that mandates the row's EXISTENCE; this gate only judges the
#       colors of badges that ARE present) OR every present badge carries a
#       closed-vocabulary color.
#   1 — at least one present badge has no recognisable color token, or one
#       outside the closed set.
#   2 — environment error (root not found, README not found, lib missing).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-BADGE-CLOSED-COLOR-VOCABULARY"
ANCHOR="11.4.259"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

root="${CONSUMER_ROOT:-.}"
readme_rel="README.md"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --readme) readme_rel="$2"; shift 2 ;;
        -h|--help) sed -n '1,50p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

lib="${here}/lib_badge_row.sh"
[ -f "$lib" ] || { echo "${GATE}: BLIND — lib_badge_row.sh not found at $lib" >&2; exit 2; }
# shellcheck source=lib_badge_row.sh
. "$lib"

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

total=0
fails=0
static_alts="|$(br_static_alts "$root" | paste -sd'|' -)|"

while IFS=$'\t' read -r alt url; do
    [ -n "${alt:-}${url:-}" ] || continue
    case "$static_alts" in *"|$alt|"*) echo "${GATE}: OK badge='${alt}' static (declared in config/static_badges.list; carries no derived colour/value)"; continue ;; esac
    total=$((total + 1))

    color="$(br_color_token "$url")"
    if [ -z "$color" ]; then
        color="$(br_color_token "$alt")"
    fi

    if [ -z "$color" ]; then
        fails=$((fails + 1))
        echo "${GATE}: FAIL badge='${alt}' url='${url}' reason=NO_CLOSED_COLOR_TOKEN"
        continue
    fi

    echo "${GATE}: OK badge='${alt}' color='${color}'"
done < <(br_extract_entries "$row")

echo "${GATE}: SUMMARY readme=${readme} declared=${total} fail=${fails}"

if [ "$fails" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fails}/${total} badge(s) do not carry a closed-vocabulary color token (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — all ${total} badge(s) carry a closed-vocabulary color token (§${ANCHOR})"
exit 0
