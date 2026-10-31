#!/usr/bin/env bash
# cm_zero_findings_monotone_ratchet.sh — CM-ZERO-FINDINGS-MONOTONE-RATCHET gate
# (§11.4.261(C) — the per-class + total finding count in the §11.4.261 zero-
# findings ledger MUST NEVER EXCEED its checked-in ratchet-snapshot ceiling;
# the ratchet is a MONOTONE-DECREASING adoption mechanism for brownfield
# backlogs, per §11.4.66/§11.4.224(E) — day one is green against a captured
# baseline, and the disease cannot silently spread).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.261(C) mandates a monotone-decreasing ratchet: a per-class + TOTAL
# ceiling recorded ONCE (the brownfield snapshot), against which the LIVE
# finding count from the ledger is compared on every run. This gate:
#   (1) requires the ratchet-snapshot file to exist — a MISSING snapshot is a
#       FAIL (§11.4.6 — "we never recorded a baseline" is not compliance, it
#       is the absence of the very brownfield-adoption mechanism the anchor
#       mandates; this is a hard FAIL, never a BLIND/skip);
#   (2) for every class named in the ratchet-snapshot: the ledger's current
#       count for that class MUST be <= the snapshot's ceiling for that class
#       (equality is explicitly PASS — the invariant is <=, not <);
#   (3) for every class present in the LEDGER but NOT recorded in the
#       ratchet-snapshot: its ceiling is implicitly 0 (an un-ratcheted class
#       tolerates zero findings — a brand-new finding class must be
#       explicitly ratcheted, even at 0, before any instance of it is
#       tolerated);
#   (4) the reserved class name `TOTAL` in the ratchet-snapshot ceilings the
#       SUM of all per-class counts in the ledger.
#
# Honest boundary (§11.4.6): this gate is a STATELESS per-run check — it
# proves the CURRENT ledger does not exceed the CURRENT checked-in ratchet
# ceiling. It does NOT itself verify, across git history, that the ratchet
# ceiling value has never been RAISED (a cross-commit history audit is a
# heavier, separate verification a consuming project may layer on top); this
# gate's contract is bounded to the single invariant "live count <= stored
# ceiling, right now" — exactly the invariant §11.4.261(C) requires this
# mechanism to enforce at every run.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_zero_findings_monotone_ratchet.sh [--root <project-root>]
#                                        [--ledger <path>] [--ratchet <path>]
#     --root <dir>      project root (default: $CONSUMER_ROOT or ".").
#     --ledger <path>   the JSONL findings ledger, relative to --root unless
#                        absolute (default: docs/findings/zero_findings_ledger.jsonl
#                        — same default as CM-EVERY-FINDING-CLOSED-OR-TRACKED,
#                        so both gates read one shared ledger).
#     --ratchet <path>  the ratchet-snapshot TSV (`<class>\t<max-count>`,
#                        `#`-comments and blank lines tolerated), relative to
#                        --root unless absolute (default:
#                        docs/findings/zero_findings_ratchet.tsv).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-class OK/FAIL line + final PASS/FAIL banner.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None — read-only.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed. No shared lib required. Parses clean under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.261 (this gate's mandate — clause C monotone-decreasing ratchet),
#   §11.4.135 (the ratchet pattern this generalises), §11.4.66/§11.4.224(E)
#   (brownfield adoption via a one-time snapshot), §11.4.6 (missing snapshot
#   is a FAIL not a guess), §1.1 (paired mutation test
#   cm_zero_findings_monotone_ratchet_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every class's live count is <= its ratchet ceiling (or the class has
#       zero live findings and no ratchet entry).
#   1 — at least one class's live count exceeds its ratchet ceiling.
#   2 — environment error (root not found, OR ratchet-snapshot missing).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-ZERO-FINDINGS-MONOTONE-RATCHET"
ANCHOR="11.4.261"

root="${CONSUMER_ROOT:-.}"
ledger_rel="docs/findings/zero_findings_ledger.jsonl"
ratchet_rel="docs/findings/zero_findings_ratchet.tsv"
standalone=0   # --standalone-canon: the invocation DECLARES a canon with no consumer ratchet (only way to get the honest SKIP)
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --ledger) ledger_rel="$2"; shift 2 ;;
        --ratchet) ratchet_rel="$2"; shift 2 ;;
        --standalone-canon) standalone=1; shift ;;
        -h|--help) sed -n '1,60p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

case "$ledger_rel" in
    /*) ledger="$ledger_rel" ;;
    *) ledger="${root}/${ledger_rel}" ;;
esac
case "$ratchet_rel" in
    /*) ratchet="$ratchet_rel" ;;
    *) ratchet="${root}/${ratchet_rel}" ;;
esac

# ---- ratchet-snapshot MUST exist: missing is a hard FAIL, never BLIND ----
# (§11.4.6 -- "no baseline was ever recorded" is not compliance; the anchor
# mandates the brownfield-adoption snapshot as the mechanism itself).
if [ ! -f "$ratchet" ] && [ "$standalone" -eq 1 ]; then
    echo "${GATE}: SKIP ratchet-snapshot='${ratchet}' reason=STANDALONE_CANON_DECLARED (--standalone-canon: the snapshot is consumer data and does not exist here; honest SKIP, not a PASS; the canon's own missing ceiling is an owed §11.4.261 gap, not hidden by this SKIP)"
    exit 3
fi
if [ ! -f "$ratchet" ]; then
    echo "${GATE}: FAIL ratchet-snapshot='${ratchet}' reason=RATCHET_SNAPSHOT_MISSING (§11.4.261(C) mandates a checked-in brownfield ceiling -- none found)" >&2
    exit 1
fi

json_field() {
    local line="$1" field="$2"
    echo "$line" | grep -oE "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed -E "s/^\"${field}\"[[:space:]]*:[[:space:]]*\"//; s/\"\$//"
}

# ---- tally live per-class counts from the ledger (absent ledger = all-zero) ----
declare -A live_count
total_live=0
if [ -f "$ledger" ]; then
    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        trimmed="$(echo "$raw_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [ -z "$trimmed" ] && continue
        case "$trimmed" in \#*) continue ;; esac
        cls="$(json_field "$trimmed" class)"
        [ -z "$cls" ] && cls="uncatalogued-class"
        live_count["$cls"]=$(( ${live_count["$cls"]:-0} + 1 ))
        total_live=$((total_live + 1))
    done < "$ledger"
fi

# ---- read the ratchet-snapshot ceilings ----
declare -A ceiling
total_ceiling=""
while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    trimmed="$(echo "$raw_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -z "$trimmed" ] && continue
    case "$trimmed" in \#*) continue ;; esac
    cls="$(echo "$trimmed" | awk -F'\t' '{print $1}')"
    val="$(echo "$trimmed" | awk -F'\t' '{print $2}')"
    [ -z "$cls" ] && continue
    if [ "$cls" = "TOTAL" ]; then
        total_ceiling="$val"
    else
        ceiling["$cls"]="$val"
    fi
done < "$ratchet"

fail=0

# ---- per-class check: every ratcheted class ----
for cls in "${!ceiling[@]}"; do
    cur="${live_count[$cls]:-0}"
    max="${ceiling[$cls]}"
    if [ "$cur" -gt "$max" ]; then
        echo "${GATE}: FAIL class='${cls}' reason=RATCHET_EXCEEDED (live=${cur} > ceiling=${max})"
        fail=$((fail + 1))
    else
        echo "${GATE}: OK class='${cls}' live=${cur} <= ceiling=${max}"
    fi
done

# ---- per-class check: any class present LIVE but NOT ratcheted (implicit ceiling 0) ----
for cls in "${!live_count[@]}"; do
    if [ -z "${ceiling[$cls]+set}" ]; then
        cur="${live_count[$cls]}"
        if [ "$cur" -gt 0 ]; then
            echo "${GATE}: FAIL class='${cls}' reason=UNRATCHETED_CLASS_PRESENT (live=${cur}, no ratchet-snapshot entry -- implicit ceiling=0)"
            fail=$((fail + 1))
        fi
    fi
done

# ---- TOTAL check ----
if [ -n "$total_ceiling" ]; then
    if [ "$total_live" -gt "$total_ceiling" ]; then
        echo "${GATE}: FAIL class='TOTAL' reason=RATCHET_EXCEEDED (live=${total_live} > ceiling=${total_ceiling})"
        fail=$((fail + 1))
    else
        echo "${GATE}: OK class='TOTAL' live=${total_live} <= ceiling=${total_ceiling}"
    fi
fi

echo "${GATE}: SUMMARY ledger=${ledger} ratchet=${ratchet} total_live=${total_live} fail=${fail}"

if [ "$fail" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fail} class(es) exceed their ratchet ceiling (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — every class's live finding count is within its ratchet ceiling (§${ANCHOR})"
exit 0
