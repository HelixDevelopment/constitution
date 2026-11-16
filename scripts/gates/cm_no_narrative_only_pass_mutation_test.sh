#!/usr/bin/env bash
# cm_no_narrative_only_pass_mutation_test.sh — §1.1 paired mutation test for
# cm_no_narrative_only_pass.sh (§11.4.262(C) — CM-NO-NARRATIVE-ONLY-PASS).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1): golden-good PASSes, each
# distinct violation class correctly FAILs with the right reason, restore
# PASSes again, and a false-positive guard is exercised (a report containing
# ONLY the substring "PASSWORD" -- never a standalone "PASS" token -- MUST
# NOT be mis-flagged as a narrative-PASS-claim bluff; a word-boundary miss
# would be a §11.4.201(1) FAIL-bluff). All work happens in a disposable
# mktemp -d scratch tree (§11.4.84).
#
# ── Sub-cases ────────────────────────────────────────────────────────────────
#   T1 — golden-GOOD (a free-text report whose PASS claim cites a nearby
#        evidence: line, plus a JSON report auto-OK'd) PASSES.
#   T2 — mutation: the free-text report's evidence: citation is removed ->
#        FAILs reason=NARRATIVE_PASS_NO_EVIDENCE.
#   T3 — restore -> PASSES again.
#   T4 — mutation: the manifest declares a report path that does not exist
#        -> FAILs reason=DECLARED_REPORT_MISSING.
#   T5 — restore.
#   T6 — FALSE-POSITIVE GUARD: a declared report contains ONLY the substring
#        "PASSWORD" (repeatedly, in several sentences) and NEVER a
#        standalone word-boundary "PASS" token -> the gate MUST NOT fire
#        (word-boundary match, not substring match).
#   T7 — restore -> PASSES again (gate not stuck).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_no_narrative_only_pass_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required (gate is genuinely load-bearing).
#   1 — at least one sub-case behaved incorrectly (gate is decoration or broken).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_no_narrative_only_pass.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/docs/evidence" "$D/qa-results"
MANIFEST="$D/docs/evidence/narrative_reports_manifest.tsv"
FREE_TEXT="$D/qa-results/report_free_text.md"
JSON_REPORT="$D/qa-results/report_json.json"

fail_count=0
note() { echo "MUTATION-TEST: $*"; }

run_gate() { bash "$gate" --root "$D" --manifest docs/evidence/narrative_reports_manifest.tsv; }

expect_pass() {
    local label="$1"
    local out; out="$(run_gate 2>&1)"; local rc=$?
    if [ "$rc" -eq 0 ]; then
        note "$label PASSED as required"
    else
        note "$label FAILED unexpectedly (should have PASSed) — output:"
        echo "$out"
        fail_count=$((fail_count + 1))
    fi
}

expect_fail() {
    local label="$1" grep_for="$2"
    local out; out="$(run_gate 2>&1)"; local rc=$?
    if [ "$rc" -eq 0 ]; then
        note "$label INCORRECTLY PASSED (should have FAILed) — output:"
        echo "$out"
        fail_count=$((fail_count + 1))
    else
        if echo "$out" | grep -qF "$grep_for"; then
            note "$label correctly FAILED citing '$grep_for'"
        else
            note "$label FAILED but did NOT cite expected reason '$grep_for' — output:"
            echo "$out"
            fail_count=$((fail_count + 1))
        fi
    fi
}

mk_manifest_good() {
    cat > "$MANIFEST" << 'FIXTURE_EOF'
R1	qa-results/report_free_text.md
R2	qa-results/report_json.json
FIXTURE_EOF
}

mk_free_text_with_evidence() {
    cat > "$FREE_TEXT" << 'FIXTURE_EOF'
Ran the audit sweep against the clean baseline.
Result: PASS (evidence: qa-results/red_green_proof.log)
Sweep complete.
FIXTURE_EOF
}

mk_free_text_without_evidence() {
    cat > "$FREE_TEXT" << 'FIXTURE_EOF'
Ran the audit sweep against the clean baseline.
Result: PASS
Sweep complete, trust me.
FIXTURE_EOF
}

mk_json_report() {
    cat > "$JSON_REPORT" << 'FIXTURE_EOF'
{"status":"PASS","evidence":"qa-results/red_green_proof.log"}
FIXTURE_EOF
}

mk_manifest_good
mk_free_text_with_evidence
mk_json_report

# ---- T1 golden-GOOD ----
expect_pass "T1 golden-GOOD (PASS claim cites nearby evidence:, JSON report auto-OK)"

# ---- T2 mutation: strip the evidence: citation from the free-text PASS claim ----
mk_free_text_without_evidence
expect_fail "T2 mutation (PASS claim with no nearby evidence: citation)" "reason=NARRATIVE_PASS_NO_EVIDENCE"

# ---- T3 restore ----
mk_free_text_with_evidence
expect_pass "T3 restore (gate re-evaluates live, not stuck FAIL)"

# ---- T4 mutation: manifest declares a report path that does not exist ----
cat > "$MANIFEST" << 'FIXTURE_EOF'
R1	qa-results/report_free_text.md
R3	qa-results/this_report_was_never_produced.md
FIXTURE_EOF
expect_fail "T4 mutation (manifest declares a missing report)" "reason=DECLARED_REPORT_MISSING"

# ---- T5 restore ----
mk_manifest_good
expect_pass "T5 restore"

# ---- T6 FALSE-POSITIVE GUARD: report contains ONLY "PASSWORD" repeatedly,
#       NEVER a standalone "PASS" token. Fixture hand-checked to contain no
#       bare "PASS" word anywhere (word-boundary substring collision trap). ----
cat > "$FREE_TEXT" << 'FIXTURE_EOF'
Set the PASSWORD in the .env file before running the sweep.
Rotation of the PASSWORD is required every 90 days.
Never commit the PASSWORD to version control.
FIXTURE_EOF
if grep -qE '\bPASS\b' "$FREE_TEXT"; then
    note "T6 FIXTURE-AUTHORING ERROR: fixture unexpectedly contains a standalone PASS token — aborting"
    fail_count=$((fail_count + 1))
else
    expect_pass "T6 false-positive guard (report contains only PASSWORD, never standalone PASS -- MUST NOT false-match)"
fi

# ---- T7 restore -> PASSES again ----
mk_free_text_with_evidence
expect_pass "T7 restore after false-positive-guard case (gate not stuck)"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} sub-case(s) FAILED"
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-NO-NARRATIVE-ONLY-PASS is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=7 fail=0"   # a summary the full-suite runner parses (the case lines above carry fail words such as "correctly FAILED"); 7 sub-cases
exit 0
