#!/usr/bin/env bash
# cm_evidence_analyzer_self_validated.sh — CM-EVIDENCE-ANALYZER-SELF-VALIDATED
# gate (§11.4.262(D) / §11.4.107(10) — every evidence analyzer this project
# declares MUST be self-validated with golden-good / golden-bad / negative-
# control fixtures, so the analyzer itself cannot bluff).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.262(D) mandates: "Every evidence analyzer golden-good/golden-bad/
# negative-control validated per §11.4.107(10); analyzer that passes its
# golden-bad = bluff itself + release-blocker (§11.4.201)." This gate reads a
# consumer-owned manifest of declared analyzer scripts (§11.4.28/§11.4.35
# decoupling — the gate itself carries NO project literal) and, for EACH
# declared analyzer, checks:
#   (1) the analyzer script exists and is executable;
#   (2) its source names all three §11.4.107(10) fixture classes (golden-
#       good, golden-bad, negative-control) — presence, not behaviour
#       (mirrors cm_zero_findings_audit_sweep.sh's identical honest
#       boundary for its own sweep-script check);
#   (3) it genuinely supports `--selftest` and that invocation exits 0 (the
#       analyzer's OWN internal proof that its golden-bad fixture makes it
#       FAIL and its golden-good/negative-control fixtures make it PASS —
#       this gate does NOT re-implement that proof, it requires the
#       analyzer to have already run it and exited 0, exactly as
#       cm_badge_self_validated.sh requires of its single badge-computer
#       target, generalised here to an arbitrary-length manifest of
#       analyzers).
#
# This gate deliberately does NOT require `bash -n` parse-cleanliness —
# unlike the sweep-script gate, evidence analyzers may legitimately be
# written in Python, Go, or any other language (§11.4.107 names OCR/vision
# analyzers, audio-loudness analyzers, frame-freeze analyzers — none of
# which are bash scripts in general). Requiring bash-only parseability here
# would be a false-positive refusal (§11.4.201) against a legitimately
# non-bash, genuinely-working analyzer.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_evidence_analyzer_self_validated.sh [--root <project-root>]
#                                          [--manifest <path>]
#     --root <dir>       project root (default: $CONSUMER_ROOT or ".").
#     --manifest <path>  TSV manifest of declared analyzers, relative to
#                         --root unless absolute (default:
#                         docs/evidence/analyzer_manifest.tsv). Format,
#                         one analyzer per non-blank/non-'#'-comment line:
#                             <analyzer_id><TAB><script-path-relative-to-root>
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-analyzer OK/FAIL lines + final PASS/FAIL banner.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Invokes `<analyzer-script> --selftest` for every declared analyzer (the
#   consumer's own script decides what that does — this gate assumes it is
#   safe + side-effect-free per the consumer's own self-test contract, same
#   assumption cm_badge_self_validated.sh and cm_zero_findings_audit_sweep.sh
#   make of their respective targets). No other side-effects from this gate.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep. No shared lib required. Parses clean under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.262(D) (this gate's mandate), §11.4.107(10) (self-validated
#   analyzer discipline — the analyzer-fixture-class pattern this gate
#   audits for), §11.4.201 (a guard/analyzer must assert the REAL condition
#   — a fake `--selftest` that always exits 0 is the false-negative-PASS
#   bluff §11.4.201 forbids; conversely this gate itself must not
#   false-REFUSE a genuinely-empty declared-analyzer set, per the
#   false-positive-guard discipline §11.4.201(1) also mandates), §11.4.28/
#   §11.4.35 (decoupling — no project literal in this gate), §1.1 (paired
#   mutation test cm_evidence_analyzer_self_validated_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every declared analyzer exists, is executable, names all three
#       fixture classes, and its --selftest exits 0. A manifest declaring
#       ZERO analyzers is a vacuous PASS (§11.4.201(1) false-positive guard
#       — no declared analyzers means nothing for this gate to validate;
#       that is NOT itself a defect this gate detects).
#   1 — any declared analyzer is missing/not-executable/missing a fixture
#       class/failing its own --selftest.
#   2 — environment error (root not found).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-EVIDENCE-ANALYZER-SELF-VALIDATED"
ANCHOR="11.4.262"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

root="${CONSUMER_ROOT:-.}"
manifest_rel="docs/evidence/analyzer_manifest.tsv"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --manifest) manifest_rel="$2"; shift 2 ;;
        -h|--help) sed -n '1,60p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

case "$manifest_rel" in
    /*) manifest="$manifest_rel" ;;
    *) manifest="${root}/${manifest_rel}" ;;
esac

fail=0
declared=0

if [ ! -f "$manifest" ]; then
    echo "${GATE}: PASS — no analyzer manifest declared at '${manifest}' (nothing to validate, honest §11.4.201(1) vacuous case, §${ANCHOR})"
    exit 0
fi

while IFS=$'\t' read -r analyzer_id script_rel || [ -n "${analyzer_id:-}" ]; do
    # skip blank lines and '#'-comment lines
    case "$analyzer_id" in
        ''|'#'*) continue ;;
    esac
    [ -n "${script_rel:-}" ] || {
        echo "${GATE}: FAIL manifest row for '${analyzer_id}' reason=MALFORMED_ROW (missing script-path field)"
        fail=$((fail + 1))
        continue
    }
    declared=$((declared + 1))

    case "$script_rel" in
        /*) script="$script_rel" ;;
        *) script="${root}/${script_rel}" ;;
    esac

    if [ ! -f "$script" ]; then
        echo "${GATE}: FAIL analyzer='${analyzer_id}' script='${script}' reason=ANALYZER_SCRIPT_MISSING"
        fail=$((fail + 1))
        continue
    fi

    if [ ! -x "$script" ]; then
        echo "${GATE}: FAIL analyzer='${analyzer_id}' script='${script}' reason=NOT_EXECUTABLE"
        fail=$((fail + 1))
    else
        echo "${GATE}: OK analyzer='${analyzer_id}' script is executable"
    fi

    # ---- three fixture-class markers (§11.4.107(10)) — presence check,
    #      same honest boundary as cm_zero_findings_audit_sweep.sh: a class
    #      referenced only in a comment still counts as covering the class.
    for marker_pair in "golden-good:GOLDEN_GOOD_FIXTURE_MISSING" "golden-bad:GOLDEN_BAD_FIXTURE_MISSING" "negative-control:NEGATIVE_CONTROL_FIXTURE_MISSING"; do
        marker="${marker_pair%%:*}"
        reason="${marker_pair##*:}"
        marker_us="$(echo "$marker" | tr '-' '_')"
        if grep -qiE "${marker}|${marker_us}" "$script" 2>/dev/null; then
            echo "${GATE}: OK analyzer='${analyzer_id}' source names fixture class '${marker}'"
        else
            echo "${GATE}: FAIL analyzer='${analyzer_id}' script='${script}' reason=${reason}"
            fail=$((fail + 1))
        fi
    done

    # ---- --selftest genuinely runs and exits 0 (only if executable) ----
    if [ -x "$script" ]; then
        if "$script" --selftest >"${TMPDIR:-/tmp}"/.cm_eas_selftest.$$ 2>&1; then
            echo "${GATE}: OK analyzer='${analyzer_id}' '--selftest' exited 0"
        else
            echo "${GATE}: FAIL analyzer='${analyzer_id}' '--selftest' exited non-zero reason=SELFTEST_FAILED"
            cat "${TMPDIR:-/tmp}"/.cm_eas_selftest.$$ | sed 's/^/    /'
            fail=$((fail + 1))
        fi
        rm -f "${TMPDIR:-/tmp}"/.cm_eas_selftest.$$
    fi
done < "$manifest"

echo "${GATE}: SUMMARY manifest=${manifest} declared=${declared} fail=${fail}"

if [ "$declared" -eq 0 ]; then
    echo "${GATE}: PASS — manifest declares zero analyzers (nothing to validate, honest §11.4.201(1) vacuous case, §${ANCHOR})"
    exit 0
fi

if [ "$fail" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fail} sub-check(s) failed across ${declared} declared analyzer(s) (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — all ${declared} declared analyzer(s) exist, are executable, name all 3 fixture classes, and their selftests exit 0 (§${ANCHOR})"
exit 0
