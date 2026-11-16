#!/usr/bin/env bash
# cm_badge_self_validated.sh — CM-BADGE-SELF-VALIDATED gate
# (§11.4.259 — the badge-computer MUST be self-validated per §11.4.107(10) /
# §11.4.201: golden-good/golden-bad/negative-control fixtures, `--selftest`
# genuinely runs and exits 0).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.259 mandates "badge-computer self-validated golden-good/golden-bad/
# negative-control per §11.4.107(10)/§11.4.201". This gate asserts, for the
# consumer-declared badge-computer script (the mechanism that COMPUTES the
# README badge row's colors/values), that it: (1) genuinely supports a
# `--selftest` invocation that exits 0 (a REAL self-check run, not merely
# claimed); (2) its own source statically contains evidence of all three
# fixture classes — golden-good, golden-bad, negative-control — so the
# selftest is not a vacuous no-op that always exits 0 regardless of what it
# is asked to validate (the §11.4.107(10) discipline: "an analyzer that
# PASSes its golden-bad fixture is a bluff gate").
#
# Honest boundary (§11.4.6): this gate proves the THREE FIXTURE CLASSES are
# named in source AND the selftest invocation exits 0 — it does NOT
# re-implement the analyzer's own internal correctness proof (that the
# analyzer's golden-bad fixture genuinely makes IT fail, etc.) — that proof
# lives inside the badge-computer's own selftest run, which this gate
# requires to have actually executed successfully.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_badge_self_validated.sh [--root <project-root>] [--readme <path>]
#                              [--badge-computer <path>]
#     --root <dir>            project root (default: $CONSUMER_ROOT or ".").
#     --readme <path>         README entry point, relative to --root unless
#                              absolute (default: README.md).
#     --badge-computer <path> the badge-computing script, relative to --root
#                              unless absolute
#                              (default: scripts/badges/compute_badges.sh).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-sub-check OK/FAIL line + final PASS/FAIL banner.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Invokes `<badge-computer> --selftest` (the consumer's own script decides
#   what that does — this gate assumes it is safe + side-effect-free per the
#   consumer's own self-test contract). No other side-effects from this gate.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed. Sources lib_badge_row.sh (same directory). Parses clean
#   under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.259 (this gate's mandate), §11.4.107(10) (self-validated analyzer
#   discipline this gate enforces), §11.4.201 (a guard/analyzer must assert
#   the REAL condition — a fake `--selftest` that always exits 0 is exactly
#   the false-negative-PASS bluff §11.4.201 forbids), lib_badge_row.sh
#   (shared badge-row-presence check), §1.1 (paired mutation test
#   cm_badge_self_validated_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — no badge row exists (nothing to check) OR the badge-computer exists,
#       is executable, its source names all three fixture classes, AND its
#       `--selftest` invocation exits 0.
#   1 — a badge row exists but the badge-computer is missing / not executable
#       / missing a fixture class in source / its selftest failed.
#   2 — environment error (root not found, README not found, lib missing).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-BADGE-SELF-VALIDATED"
ANCHOR="11.4.259"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

root="${CONSUMER_ROOT:-.}"
readme_rel="README.md"
computer_rel="scripts/badges/compute_badges.sh"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --readme) readme_rel="$2"; shift 2 ;;
        --badge-computer) computer_rel="$2"; shift 2 ;;
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

case "$computer_rel" in
    /*) computer="$computer_rel" ;;
    *) computer="${root}/${computer_rel}" ;;
esac

fail=0

if [ ! -f "$computer" ]; then
    echo "${GATE}: FAIL badge-computer='${computer}' reason=MISSING (README carries a badge row but no declared badge-computer script exists)" >&2
    exit 1
fi

if [ ! -x "$computer" ]; then
    echo "${GATE}: FAIL badge-computer='${computer}' reason=NOT_EXECUTABLE"
    fail=$((fail + 1))
else
    echo "${GATE}: OK badge-computer='${computer}' is executable"
fi

# ---- static fixture-class check (§11.4.107(10)) ----
for marker_pair in "golden-good:GOLDEN_GOOD_FIXTURE_MISSING" "golden-bad:GOLDEN_BAD_FIXTURE_MISSING" "negative-control:NEGATIVE_CONTROL_FIXTURE_MISSING"; do
    marker="${marker_pair%%:*}"
    reason="${marker_pair##*:}"
    marker_us="$(echo "$marker" | tr '-' '_')"
    if grep -qiE "${marker}|${marker_us}" "$computer"; then
        echo "${GATE}: OK badge-computer source names fixture class '${marker}'"
    else
        echo "${GATE}: FAIL badge-computer source missing fixture-class marker '${marker}' reason=${reason}"
        fail=$((fail + 1))
    fi
done

# ---- --selftest genuinely runs and exits 0 (only if executable) ----
if [ -x "$computer" ]; then
    if "$computer" --selftest >"${TMPDIR:-/tmp}"/.cm_badge_selftest_out.$$ 2>&1; then
        echo "${GATE}: OK badge-computer '--selftest' exited 0"
    else
        echo "${GATE}: FAIL badge-computer '--selftest' exited non-zero reason=SELFTEST_FAILED"
        cat "${TMPDIR:-/tmp}"/.cm_badge_selftest_out.$$ | sed 's/^/    /'
        fail=$((fail + 1))
    fi
    rm -f "${TMPDIR:-/tmp}"/.cm_badge_selftest_out.$$
fi

echo "${GATE}: SUMMARY badge-computer=${computer} fail=${fail}"

if [ "$fail" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fail} sub-check(s) failed (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — badge-computer is executable, names all three fixture classes, and its selftest exits 0 (§${ANCHOR})"
exit 0
