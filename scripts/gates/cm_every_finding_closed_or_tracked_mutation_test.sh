#!/usr/bin/env bash
# cm_every_finding_closed_or_tracked_mutation_test.sh — §1.1 paired mutation
# test for cm_every_finding_closed_or_tracked.sh (§11.4.261(D) —
# CM-EVERY-FINDING-CLOSED-OR-TRACKED).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1): golden-good PASSes, each
# distinct violation class correctly FAILs with the right reason, restore
# PASSes again (the gate re-evaluates live), and a false-positive guard is
# exercised (a genuinely-empty/absent ledger — the target "zero findings
# outstanding" state — MUST PASS vacuously, never mis-reported as a defect).
# All work happens in a disposable mktemp -d scratch tree (§11.4.84 — never
# the real working tree).
#
# ── Sub-cases ────────────────────────────────────────────────────────────────
#   T1  — golden-GOOD (one tracked row with tracker_ref+mitigation_evidence,
#         one closed row with mitigation_evidence) PASSES.
#   T2  — mutation: a row with status="open" -> FAILs reason=FINDING_STILL_OPEN.
#   T3  — restore -> PASSES again.
#   T4  — mutation: a tracked row with empty tracker_ref ->
#         FAILs reason=TRACKED_MISSING_FIELDS.
#   T5  — restore.
#   T6  — mutation: a closed row with no mitigation_evidence field at all ->
#         FAILs reason=CLOSED_MISSING_MITIGATION_EVIDENCE.
#   T7  — restore.
#   T8  — mutation: a row with an unrecognised status value ("wontfix") ->
#         FAILs reason=UNRECOGNISED_OR_MISSING_STATUS.
#   T9  — restore.
#   T10 — FALSE-POSITIVE GUARD: the ledger file does not exist at all (the
#         genuinely-clean, zero-findings-outstanding target state) -> the
#         gate MUST NOT fire — it PASSES vacuously, exactly as a "nothing to
#         disposition" state deserves (§11.4.201(1) — a false refusal on a
#         legitimately-empty/absent case is a FAIL-bluff of equal severity
#         to a false pass).
#   T11 — restore (recreate the golden-good ledger) -> PASSES again, proving
#         the gate is not "stuck" from the absent-ledger case.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_every_finding_closed_or_tracked_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required (gate is genuinely load-bearing).
#   1 — at least one sub-case behaved incorrectly (gate is decoration or broken).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_every_finding_closed_or_tracked.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/docs/findings"
LEDGER="$D/docs/findings/zero_findings_ledger.jsonl"

fail_count=0
note() { echo "MUTATION-TEST: $*"; }

run_gate() { bash "$gate" --root "$D" --ledger docs/findings/zero_findings_ledger.jsonl; }

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

# A complete, real, golden-good ledger: one TRACKED finding (tracker_ref +
# mitigation_evidence both non-empty) and one CLOSED finding (mitigation_evidence
# non-empty) — a genuine mixed real-world ledger, not a trivial single-row stub.
mk_fixture() {
    cat > "$LEDGER" << 'FIXTURE_EOF'
{"finding_id":"F1","class":"shortcomings","file":"src/a.go","line":10,"description":"TODO left in source","status":"tracked","tracker_ref":"ATM-501","mitigation_evidence":"docs/issues/ATM-501/plan.md"}
{"finding_id":"F2","class":"weak_spot","file":"src/b.go","line":42,"description":"unbounded retry loop","status":"closed","tracker_ref":"","mitigation_evidence":"qa-results/atm-499/red_green_proof.log"}
FIXTURE_EOF
}

mk_fixture

# ---- T1 golden-GOOD ----
expect_pass "T1 golden-GOOD (one tracked + one closed, both correctly dispositioned)"

# ---- T2 mutation: a row with status=open ----
cat > "$LEDGER" << 'FIXTURE_EOF'
{"finding_id":"F1","class":"shortcomings","file":"src/a.go","line":10,"description":"TODO left in source","status":"open","tracker_ref":"","mitigation_evidence":""}
FIXTURE_EOF
expect_fail "T2 mutation (finding status=open, no disposition)" "reason=FINDING_STILL_OPEN"

# ---- T3 restore ----
mk_fixture
expect_pass "T3 restore (gate re-evaluates live, not stuck FAIL)"

# ---- T4 mutation: tracked row with empty tracker_ref ----
cat > "$LEDGER" << 'FIXTURE_EOF'
{"finding_id":"F1","class":"shortcomings","file":"src/a.go","line":10,"description":"TODO left in source","status":"tracked","tracker_ref":"","mitigation_evidence":"docs/issues/ATM-501/plan.md"}
FIXTURE_EOF
expect_fail "T4 mutation (tracked row, empty tracker_ref)" "reason=TRACKED_MISSING_FIELDS"

# ---- T5 restore ----
mk_fixture
expect_pass "T5 restore"

# ---- T6 mutation: closed row with no mitigation_evidence field at all ----
cat > "$LEDGER" << 'FIXTURE_EOF'
{"finding_id":"F2","class":"weak_spot","file":"src/b.go","line":42,"description":"unbounded retry loop","status":"closed"}
FIXTURE_EOF
expect_fail "T6 mutation (closed row, mitigation_evidence field absent)" "reason=CLOSED_MISSING_MITIGATION_EVIDENCE"

# ---- T7 restore ----
mk_fixture
expect_pass "T7 restore"

# ---- T8 mutation: unrecognised status value ----
cat > "$LEDGER" << 'FIXTURE_EOF'
{"finding_id":"F3","class":"bluffs","file":"src/c.go","line":7,"description":"stale bluff finding","status":"wontfix","tracker_ref":"ATM-777","mitigation_evidence":"n/a"}
FIXTURE_EOF
expect_fail "T8 mutation (unrecognised status value 'wontfix')" "reason=UNRECOGNISED_OR_MISSING_STATUS"

# ---- T9 restore ----
mk_fixture
expect_pass "T9 restore"

# ---- T10 FALSE-POSITIVE GUARD: ledger absent entirely (genuinely-clean
#       zero-findings-outstanding state) MUST PASS vacuously. ----
rm -f "$LEDGER"
expect_pass "T10 false-positive guard (ledger absent -- genuinely-clean zero-findings state MUST NOT be mis-flagged as a defect)"

# ---- T11 restore (recreate golden-good ledger) -> PASSES again ----
mk_fixture
expect_pass "T11 restore after absent-ledger case (gate not stuck)"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} sub-case(s) FAILED"
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-EVERY-FINDING-CLOSED-OR-TRACKED is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=11 fail=0"   # a summary the full-suite runner parses (the case lines above carry fail words such as "correctly FAILED"); 11 sub-cases
exit 0
