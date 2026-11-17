#!/usr/bin/env bash
# cm_evidence_analyzer_self_validated_mutation_test.sh — §1.1 paired
# mutation test for cm_evidence_analyzer_self_validated.sh (§11.4.262(D) /
# §11.4.107(10) — CM-EVIDENCE-ANALYZER-SELF-VALIDATED).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1): golden-good PASSes, each
# distinct violation class correctly FAILs with the right reason, restore
# PASSes again (the gate re-evaluates live, not stuck), and a false-positive
# guard is exercised (a manifest declaring ZERO analyzers, and the total
# absence of a manifest, are both genuinely-vacuous states that MUST NOT be
# mis-flagged as defects — §11.4.201(1)). All work happens in a disposable
# mktemp -d scratch tree (§11.4.84 — never the real working tree).
#
# ── Sub-cases ────────────────────────────────────────────────────────────────
#   T1  — golden-GOOD (one declared analyzer, executable, all 3 fixture
#         classes named, --selftest exits 0) PASSES.
#   T2  — mutation: strip the executable bit -> FAILs reason=NOT_EXECUTABLE.
#   T3  — restore -> PASSES again.
#   T4  — mutation: remove the 'golden-bad' fixture-class marker ->
#         FAILs reason=GOLDEN_BAD_FIXTURE_MISSING.
#   T5  — restore.
#   T6  — mutation: remove the 'negative-control' fixture-class marker ->
#         FAILs reason=NEGATIVE_CONTROL_FIXTURE_MISSING.
#   T7  — restore.
#   T8  — mutation: --selftest now exits non-zero -> FAILs reason=SELFTEST_FAILED.
#   T9  — restore.
#   T10 — mutation: manifest declares an analyzer whose script does not
#         exist -> FAILs reason=ANALYZER_SCRIPT_MISSING.
#   T11 — restore.
#   T12 — FALSE-POSITIVE GUARD (a): manifest exists but declares ZERO
#         analyzers (comment-only) -> MUST PASS (vacuous, §11.4.201(1)).
#   T13 — FALSE-POSITIVE GUARD (b): manifest file does not exist at all ->
#         MUST PASS (vacuous, §11.4.201(1)).
#   T14 — restore to golden-GOOD -> PASSES again (gate not stuck).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_evidence_analyzer_self_validated_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required (gate is genuinely load-bearing).
#   1 — at least one sub-case behaved incorrectly (gate is decoration or broken).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_evidence_analyzer_self_validated.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/docs/evidence" "$D/scripts/analyzers"
MANIFEST="$D/docs/evidence/analyzer_manifest.tsv"
ANALYZER="$D/scripts/analyzers/frame_freeze_analyzer.sh"

fail_count=0
note() { echo "MUTATION-TEST: $*"; }

run_gate() { bash "$gate" --root "$D" --manifest docs/evidence/analyzer_manifest.tsv; }

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
A1	scripts/analyzers/frame_freeze_analyzer.sh
FIXTURE_EOF
}

mk_analyzer_good() {
    cat > "$ANALYZER" << 'FIXTURE_EOF'
#!/usr/bin/env bash
# frame_freeze_analyzer.sh -- fixture evidence analyzer. Self-validated per
# §11.4.107(10) with golden-good / golden-bad / negative-control fixtures.
set -u
if [ "${1:-}" = "--selftest" ]; then
    good_result="no_freeze"
    bad_result="freeze_detected"
    if [ "$good_result" = "no_freeze" ] && [ "$bad_result" = "freeze_detected" ]; then
        echo "selftest: golden-good=OK golden-bad=OK negative-control=OK"
        exit 0
    fi
    echo "selftest: FAILED"
    exit 1
fi
echo '{"verdict":"no_freeze","confidence":0.98}'
exit 0
FIXTURE_EOF
    chmod +x "$ANALYZER"
}

mk_manifest_good
mk_analyzer_good

# ---- T1 golden-GOOD ----
expect_pass "T1 golden-GOOD (one analyzer, all fixture classes present, selftest exits 0)"

# ---- T2 mutation: strip executable bit ----
chmod -x "$ANALYZER"
expect_fail "T2 mutation (strip executable bit)" "reason=NOT_EXECUTABLE"

# ---- T3 restore ----
mk_analyzer_good
expect_pass "T3 restore (gate re-evaluates live, not stuck FAIL)"

# ---- T4 mutation: remove golden-bad marker ----
sed -i 's/golden-bad/g_o_l_d_e_n_bad/g' "$ANALYZER"
expect_fail "T4 mutation (remove golden-bad fixture marker)" "reason=GOLDEN_BAD_FIXTURE_MISSING"

# ---- T5 restore ----
mk_analyzer_good
expect_pass "T5 restore"

# ---- T6 mutation: remove negative-control marker ----
sed -i 's/negative-control/n_e_g_a_t_i_v_e_control/g' "$ANALYZER"
expect_fail "T6 mutation (remove negative-control fixture marker)" "reason=NEGATIVE_CONTROL_FIXTURE_MISSING"

# ---- T7 restore ----
mk_analyzer_good
expect_pass "T7 restore"

# ---- T8 mutation: --selftest now exits non-zero ----
sed -i 's/echo "selftest: golden-good=OK golden-bad=OK negative-control=OK"/echo "selftest: FORCED-FAIL"/; s/exit 0$/exit 1/' "$ANALYZER"
expect_fail "T8 mutation (selftest now exits non-zero)" "reason=SELFTEST_FAILED"

# ---- T9 restore ----
mk_analyzer_good
expect_pass "T9 restore"

# ---- T10 mutation: manifest declares an analyzer whose script is missing ----
cat > "$MANIFEST" << 'FIXTURE_EOF'
A1	scripts/analyzers/frame_freeze_analyzer.sh
A2	scripts/analyzers/this_analyzer_was_never_produced.sh
FIXTURE_EOF
expect_fail "T10 mutation (manifest declares a missing analyzer script)" "reason=ANALYZER_SCRIPT_MISSING"

# ---- T11 restore ----
mk_manifest_good
expect_pass "T11 restore"

# ---- T12 FALSE-POSITIVE GUARD (a): manifest exists, declares zero analyzers ----
cat > "$MANIFEST" << 'FIXTURE_EOF'
# no analyzers declared yet -- genuinely-empty manifest
FIXTURE_EOF
expect_pass "T12 false-positive guard (manifest declares zero analyzers -- MUST PASS, vacuous §11.4.201(1))"

# ---- T13 FALSE-POSITIVE GUARD (b): manifest file absent entirely ----
rm -f "$MANIFEST"
expect_pass "T13 false-positive guard (manifest file absent entirely -- MUST PASS, vacuous §11.4.201(1))"

# ---- T14 restore to golden-GOOD -> PASSES again ----
mk_manifest_good
expect_pass "T14 restore after false-positive-guard cases (gate not stuck)"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} sub-case(s) FAILED"
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-EVIDENCE-ANALYZER-SELF-VALIDATED is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=14 fail=0"   # a summary the full-suite runner parses (its last 12 lines carry "correctly FAILED" fail words)
exit 0
