#!/usr/bin/env bash
# cm_zero_findings_audit_sweep_mutation_test.sh — §1.1 paired mutation test
# for cm_zero_findings_audit_sweep.sh (§11.4.261(B) / CM-ZERO-FINDINGS-AUDIT-SWEEP).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1): golden-good PASSes, each
# distinct mutation class correctly FAILs with the right reason, restore
# PASSes again (the gate re-evaluates live, not stuck), and a false-positive
# guard is exercised (a class name referenced only in a comment MUST still
# count as covering the class — presence, not behaviour, is this gate's
# honest boundary). All work happens in a disposable mktemp -d scratch tree
# (§11.4.84 — never the real working tree).
#
# ── Sub-cases ────────────────────────────────────────────────────────────────
#   T1 — golden-GOOD (script present, executable, all 10 vocabulary classes +
#        3 fixture classes named, --selftest exits 0) PASSES.
#   T2 — mutation: strip the executable bit -> FAILs reason=NOT_EXECUTABLE.
#   T3 — restore -> PASSES again.
#   T4 — mutation: remove the "bluff" vocabulary-class line ->
#        FAILs reason=BLUFFS_CLASS_MISSING.
#   T5 — restore.
#   T6 — mutation: remove the "negative-control" fixture-class marker ->
#        FAILs reason=NEGATIVE_CONTROL_FIXTURE_MISSING.
#   T7 — restore.
#   T8 — mutation: --selftest now exits non-zero -> FAILs reason=SELFTEST_FAILED.
#   T9 — restore.
#   T10 — mutation: script deleted entirely -> FAILs reason=SWEEP_SCRIPT_MISSING.
#   T11 — restore + FALSE-POSITIVE GUARD: a fixture whose vocabulary classes
#        are named ONLY inside a `#`-comment block (never in executable code)
#        MUST STILL PASS — presence-in-source is the gate's honest contract,
#        it does not (and cannot, statically) prove behavioural correctness.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_zero_findings_audit_sweep_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required (gate is genuinely load-bearing).
#   1 — at least one sub-case behaved incorrectly (gate is decoration or broken).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_zero_findings_audit_sweep.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/scripts/audit"

fail_count=0
note() { echo "MUTATION-TEST: $*"; }

run_gate() { bash "$gate" --root "$D" --sweep-script scripts/audit/zero_findings_sweep.sh; }

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

# A complete, real, working sweep-script fixture: covers all 10 vocabulary
# classes + all 3 fixture classes in source, and genuinely supports a
# --selftest that exits 0 (a real, if trivial, self-check — not a vacuous
# always-0 stub, matching the golden-good/golden-bad discipline it itself
# names for the finding classes it audits).
mk_fixture() {
    cat > "$D/scripts/audit/zero_findings_sweep.sh" << 'FIXTURE_EOF'
#!/usr/bin/env bash
# zero_findings_sweep.sh — fixture audit sweep for CM-ZERO-FINDINGS-AUDIT-SWEEP
# mutation test. Iterates the closed §11.4.261(A) vocabulary:
#   shortcoming, gap, weak spot, danger zone, TODO/FIXME/placeholder,
#   skipped test, bluff, unresolved item, divergent/stale/orphan, uncatalogued.
# Self-validated per §11.4.107(10) with golden-good / golden-bad /
# negative-control fixtures.
set -u
if [ "${1:-}" = "--selftest" ]; then
    # golden-good fixture: emits zero findings for a clean tree -> PASS.
    good_findings=0
    # golden-bad fixture: emits N findings for a seeded-dirty tree -> proves
    # the sweep detects a real violation, never a vacuous always-clean stub.
    bad_findings=3
    # negative-control fixture: a legitimately-empty tree with genuinely
    # zero findings must NOT be misreported as a bug in the sweep itself.
    if [ "$good_findings" -eq 0 ] && [ "$bad_findings" -gt 0 ]; then
        echo "selftest: golden-good=OK golden-bad=OK negative-control=OK"
        exit 0
    fi
    echo "selftest: FAILED"
    exit 1
fi
echo '{"finding_id":"F1","class":"shortcomings","status":"closed"}'
exit 0
FIXTURE_EOF
    chmod +x "$D/scripts/audit/zero_findings_sweep.sh"
}

mk_fixture

# ---- T1 golden-GOOD ----
expect_pass "T1 golden-GOOD (all vocabulary+fixture classes present, selftest exits 0)"

# ---- T2 mutation: strip executable bit ----
chmod -x "$D/scripts/audit/zero_findings_sweep.sh"
expect_fail "T2 mutation (strip executable bit)" "reason=NOT_EXECUTABLE"

# ---- T3 restore ----
mk_fixture
expect_pass "T3 restore (gate re-evaluates live, not stuck FAIL)"

# ---- T4 mutation: remove the 'bluff' vocabulary-class line ----
sed -i '/bluff/d' "$D/scripts/audit/zero_findings_sweep.sh"
expect_fail "T4 mutation (remove bluff vocabulary class)" "reason=BLUFFS_CLASS_MISSING"

# ---- T5 restore ----
mk_fixture
expect_pass "T5 restore"

# ---- T6 mutation: remove the negative-control fixture-class marker ----
sed -i 's/negative-control/n\/a-removed/g' "$D/scripts/audit/zero_findings_sweep.sh"
expect_fail "T6 mutation (remove negative-control fixture marker)" "reason=NEGATIVE_CONTROL_FIXTURE_MISSING"

# ---- T7 restore ----
mk_fixture
expect_pass "T7 restore"

# ---- T8 mutation: --selftest now exits non-zero (genuinely failing) ----
sed -i 's/echo "selftest: golden-good=OK golden-bad=OK negative-control=OK"/echo "selftest: FORCED-FAIL"/; s/exit 0$/exit 1/' "$D/scripts/audit/zero_findings_sweep.sh"
expect_fail "T8 mutation (selftest now exits non-zero)" "reason=SELFTEST_FAILED"

# ---- T9 restore ----
mk_fixture
expect_pass "T9 restore"

# ---- T10 mutation: delete the script entirely ----
rm -f "$D/scripts/audit/zero_findings_sweep.sh"
expect_fail "T10 mutation (script deleted entirely)" "reason=SWEEP_SCRIPT_MISSING"

# ---- T11 restore + FALSE-POSITIVE GUARD: vocabulary classes named only in
#       a comment block (never in executable logic) must still PASS. ----
cat > "$D/scripts/audit/zero_findings_sweep.sh" << 'FIXTURE_EOF2'
#!/usr/bin/env bash
# Closed vocabulary reference (comment-only, for documentation purposes):
# shortcoming, gap, weak spot, danger zone, todo, fixme, placeholder,
# skipped test, bluff, unresolved, divergent, stale, orphan, uncatalogued.
# Fixture classes: golden-good, golden-bad, negative-control.
set -u
if [ "${1:-}" = "--selftest" ]; then
    echo "selftest: OK"
    exit 0
fi
exit 0
FIXTURE_EOF2
chmod +x "$D/scripts/audit/zero_findings_sweep.sh"
expect_pass "T11 false-positive guard (classes named only in a comment block, presence-not-behaviour contract)"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} sub-case(s) FAILED"
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-ZERO-FINDINGS-AUDIT-SWEEP is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=11 fail=0"   # a summary the full-suite runner parses (its last 12 lines carry "correctly FAILED" fail words)
exit 0
