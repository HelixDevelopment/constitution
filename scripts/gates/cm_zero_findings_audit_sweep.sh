#!/usr/bin/env bash
# cm_zero_findings_audit_sweep.sh — CM-ZERO-FINDINGS-AUDIT-SWEEP gate
# (§11.4.261(B) — the consumer's mechanical audit-sweep script MUST be
# present, executable, self-validated per §11.4.107(10), and MUST NOT
# silently narrow the closed finding-vocabulary per §11.4.261(A)/(E)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.261 mandates a single executable script that iterates the CLOSED
# finding vocabulary (10 classes: shortcomings, gaps, weak spots, danger
# zones, TODO/FIXME/placeholder/dead-code, skipped tests, bluffs, unresolved
# §11.4.197 items, divergent/stale/orphan artifacts per §11.4.233, and
# un-catalogued anti-patterns) and emits a machine-readable ledger, with each
# finding class shipping golden-good/golden-bad fixtures per §11.4.107(10) so
# the audit itself cannot bluff. This gate checks THE MECHANISM, not the
# project's actual finding count (that is CM-EVERY-FINDING-CLOSED-OR-TRACKED's
# job, reading the ledger this sweep emits):
#   (1) the declared sweep script exists, is executable, parses clean;
#   (2) its source names all 10 closed-vocabulary finding classes (§11.4.6 —
#       a script that silently drops a class from its vocabulary is the
#       narrowed-vocabulary fabrication §11.4.261(E) forbids);
#   (3) its source names all three §11.4.107(10) fixture classes (golden-good,
#       golden-bad, negative-control);
#   (4) it genuinely supports `--selftest` and that invocation exits 0.
#
# Honest boundary (§11.4.6): this gate proves PRESENCE of the vocabulary
# classes + fixture classes in source, via static grep, exactly as
# CM-BADGE-SELF-VALIDATED does for its three fixture classes — it does NOT
# re-implement or re-verify the sweep script's OWN internal correctness proof
# (that its golden-bad fixture genuinely makes it flag a finding, etc.); that
# proof lives inside the sweep script's own `--selftest` run, which this gate
# requires to have actually executed and exited 0. A class name referenced
# only in an explanatory comment still counts as "covering the class" — this
# gate is a presence check, not a behavioural proof, and MUST NOT refuse a
# legitimately-documented-but-present class reference.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_zero_findings_audit_sweep.sh [--root <project-root>]
#                                   [--sweep-script <path>]
#     --root <dir>           project root (default: $CONSUMER_ROOT or ".").
#     --sweep-script <path>  the audit-sweep script, relative to --root
#                             unless absolute
#                             (default: scripts/audit/zero_findings_sweep.sh
#                             — the §11.4.261(B) Lava binding).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-sub-check OK/FAIL line + final PASS/FAIL banner.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Invokes `<sweep-script> --selftest` (the consumer's own script decides
#   what that does — this gate assumes it is safe + side-effect-free per the
#   consumer's own self-test contract, same assumption CM-BADGE-SELF-VALIDATED
#   makes of its badge-computer). No other side-effects from this gate.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed. No shared lib required. Parses clean under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.261 (this gate's mandate), §11.4.107(10) (self-validated analyzer
#   discipline — same pattern as cm_badge_self_validated.sh), §11.4.201
#   (a guard/analyzer must assert the REAL condition — a fake `--selftest`
#   that always exits 0 is the false-negative-PASS bluff §11.4.201 forbids),
#   §11.4.6 (no-guessing — vocabulary narrowing is a fabrication), §1.1
#   (paired mutation test cm_zero_findings_audit_sweep_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — sweep script exists, is executable, parses clean, names all 10
#       vocabulary classes + all 3 fixture classes, and `--selftest` exits 0.
#   1 — any of the above is missing/failing.
#   2 — environment error (root not found).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-ZERO-FINDINGS-AUDIT-SWEEP"
ANCHOR="11.4.261"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

root="${CONSUMER_ROOT:-.}"
sweep_rel="scripts/audit/zero_findings_sweep.sh"
standalone=0   # --standalone-canon: the invocation DECLARES a canon with no consumer sweep (only way to get the honest SKIP)
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --sweep-script) sweep_rel="$2"; shift 2 ;;
        --standalone-canon) standalone=1; shift ;;
        -h|--help) sed -n '1,60p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

case "$sweep_rel" in
    /*) sweep="$sweep_rel" ;;
    *) sweep="${root}/${sweep_rel}" ;;
esac

fail=0

if [ ! -f "$sweep" ] && [ "$standalone" -eq 1 ]; then
    echo "${GATE}: SKIP sweep-script='${sweep}' reason=STANDALONE_CANON_DECLARED (--standalone-canon: the sweep is consumer data and does not exist here; honest SKIP, not a PASS; the canon's own missing sweep is an owed §11.4.261 gap, not hidden by this SKIP)"
    exit 3
fi
if [ ! -f "$sweep" ]; then
    echo "${GATE}: FAIL sweep-script='${sweep}' reason=SWEEP_SCRIPT_MISSING (§11.4.261 mandates a mechanical audit sweep — none declared/found)" >&2
    exit 1
fi

if [ ! -x "$sweep" ]; then
    echo "${GATE}: FAIL sweep-script='${sweep}' reason=NOT_EXECUTABLE"
    fail=$((fail + 1))
else
    echo "${GATE}: OK sweep-script='${sweep}' is executable"
fi

if head -n1 "$sweep" 2>/dev/null | grep -qE '^#!.*\b(bash|sh)\b'; then
    if bash -n "$sweep" 2>/tmp/.cm_zfas_parse.$$; then
        echo "${GATE}: OK sweep-script parses clean (bash -n)"
    else
        echo "${GATE}: FAIL sweep-script reason=PARSE_ERROR"
        cat /tmp/.cm_zfas_parse.$$ | sed 's/^/    /'
        fail=$((fail + 1))
    fi
    rm -f /tmp/.cm_zfas_parse.$$
fi

# ---- closed 10-class vocabulary presence check (§11.4.261(A)/(E)) ----
# One representative, case/spacing-tolerant regex per class; a class
# referenced anywhere in source (including comments/docstrings) counts.
declare -a vocab_patterns=(
    "shortcoming"
    "gap"
    "weak[_[:space:]-]?spot"
    "danger[_[:space:]-]?zone"
    "todo|fixme|placeholder"
    "skip(ped)?[_[:space:]-]?(test|gate)?"
    "bluff"
    "unresolved"
    "divergent|stale|orphan"
    "uncatalog"
)
declare -a vocab_reasons=(
    "SHORTCOMINGS_CLASS_MISSING"
    "GAPS_CLASS_MISSING"
    "WEAK_SPOTS_CLASS_MISSING"
    "DANGER_ZONES_CLASS_MISSING"
    "TODO_FIXME_CLASS_MISSING"
    "SKIPPED_CLASS_MISSING"
    "BLUFFS_CLASS_MISSING"
    "UNRESOLVED_CLASS_MISSING"
    "DIVERGENT_STALE_ORPHAN_CLASS_MISSING"
    "UNCATALOGUED_CLASS_MISSING"
)
# NOTE (bug fix, §11.4.201/§11.4.6): a prior single-combined-string
# "<regex>:<REASON>" design, split via ${pair%%:*}/${pair##*:}, broke for
# regexes that themselves contain a literal ':' (from a POSIX [:space:]
# bracket-expression) -- the split landed on the wrong colon, truncating
# the pattern into an invalid, unmatched-bracket regex that grep -qiE
# rejected as a hard error, never a genuine content-based non-match. Two
# PARALLEL arrays (indexed together) eliminate the entire delimiter-
# collision bug class rather than picking a marginally-safer delimiter.
for idx in "${!vocab_patterns[@]}"; do
    pattern="${vocab_patterns[$idx]}"
    reason="${vocab_reasons[$idx]}"
    if grep -qiE "$pattern" "$sweep"; then
        echo "${GATE}: OK sweep-script source names vocabulary class matching '${pattern}'"
    else
        echo "${GATE}: FAIL sweep-script source missing vocabulary class '${pattern}' reason=${reason}"
        fail=$((fail + 1))
    fi
done

# ---- three fixture-class markers (§11.4.107(10)) ----
for marker_pair in "golden-good:GOLDEN_GOOD_FIXTURE_MISSING" "golden-bad:GOLDEN_BAD_FIXTURE_MISSING" "negative-control:NEGATIVE_CONTROL_FIXTURE_MISSING"; do
    marker="${marker_pair%%:*}"
    reason="${marker_pair##*:}"
    marker_us="$(echo "$marker" | tr '-' '_')"
    if grep -qiE "${marker}|${marker_us}" "$sweep"; then
        echo "${GATE}: OK sweep-script source names fixture class '${marker}'"
    else
        echo "${GATE}: FAIL sweep-script source missing fixture-class marker '${marker}' reason=${reason}"
        fail=$((fail + 1))
    fi
done

# ---- --selftest genuinely runs and exits 0 (only if executable) ----
if [ -x "$sweep" ]; then
    if "$sweep" --selftest >/tmp/.cm_zfas_selftest.$$ 2>&1; then
        echo "${GATE}: OK sweep-script '--selftest' exited 0"
    else
        echo "${GATE}: FAIL sweep-script '--selftest' exited non-zero reason=SELFTEST_FAILED"
        cat /tmp/.cm_zfas_selftest.$$ | sed 's/^/    /'
        fail=$((fail + 1))
    fi
    rm -f /tmp/.cm_zfas_selftest.$$
fi

echo "${GATE}: SUMMARY sweep-script=${sweep} fail=${fail}"

if [ "$fail" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fail} sub-check(s) failed (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — sweep-script is executable, parses clean, names all 10 vocabulary classes + all 3 fixture classes, and its selftest exits 0 (§${ANCHOR})"
exit 0
