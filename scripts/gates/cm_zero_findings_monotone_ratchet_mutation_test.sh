#!/usr/bin/env bash
# cm_zero_findings_monotone_ratchet_mutation_test.sh — §1.1 paired mutation
# test for cm_zero_findings_monotone_ratchet.sh (§11.4.261(C) —
# CM-ZERO-FINDINGS-MONOTONE-RATCHET).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1): golden-good PASSes, each
# distinct violation class correctly FAILs with the right reason, restore
# PASSes again, and a false-positive guard is exercised (a live count
# EXACTLY EQUAL to its ratchet ceiling MUST PASS — the invariant is <=, not
# <; a gate that refuses on equality is a FAIL-bluff, §11.4.201(1)). All work
# happens in a disposable mktemp -d scratch tree (§11.4.84).
#
# ── Sub-cases ────────────────────────────────────────────────────────────────
#   T1 — golden-GOOD (every class's live count strictly under its ceiling)
#        PASSES.
#   T2 — mutation: add findings so one class's live count EXCEEDS its
#        ceiling -> FAILs reason=RATCHET_EXCEEDED.
#   T3 — restore -> PASSES again.
#   T4 — mutation: a finding of a class with NO ratchet-snapshot entry at all
#        -> FAILs reason=UNRATCHETED_CLASS_PRESENT (implicit ceiling 0).
#   T5 — restore.
#   T6 — mutation: the ratchet-snapshot file is deleted entirely ->
#        FAILs reason=RATCHET_SNAPSHOT_MISSING (a hard FAIL, never BLIND).
#   T7 — restore.
#   T8 — FALSE-POSITIVE GUARD: a class's live count is set EXACTLY EQUAL to
#        its ratchet ceiling -> the gate MUST PASS (the invariant is <=, not
#        <; refusing on exact equality would be a FAIL-bluff §11.4.201(1)).
#   T9 — restore -> PASSES again (gate not stuck after the boundary case).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_zero_findings_monotone_ratchet_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required (gate is genuinely load-bearing).
#   1 — at least one sub-case behaved incorrectly (gate is decoration or broken).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_zero_findings_monotone_ratchet.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/docs/findings"
LEDGER="$D/docs/findings/zero_findings_ledger.jsonl"
RATCHET="$D/docs/findings/zero_findings_ratchet.tsv"

fail_count=0
note() { echo "MUTATION-TEST: $*"; }

run_gate() {
    bash "$gate" --root "$D" \
        --ledger docs/findings/zero_findings_ledger.jsonl \
        --ratchet docs/findings/zero_findings_ratchet.tsv
}

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

# Golden-good ledger: 1 shortcomings finding (ceiling 2, headroom), 2
# weak_spot findings (ceiling 3, headroom) -- both strictly under ceiling.
mk_ledger_good() {
    cat > "$LEDGER" << 'FIXTURE_EOF'
{"finding_id":"F1","class":"shortcomings","status":"tracked","tracker_ref":"ATM-1","mitigation_evidence":"docs/a.md"}
{"finding_id":"F2","class":"weak_spot","status":"tracked","tracker_ref":"ATM-2","mitigation_evidence":"docs/b.md"}
{"finding_id":"F3","class":"weak_spot","status":"closed","mitigation_evidence":"qa-results/c.log"}
FIXTURE_EOF
}
mk_ratchet_good() {
    cat > "$RATCHET" << 'FIXTURE_EOF'
shortcomings	2
weak_spot	3
TOTAL	5
FIXTURE_EOF
}

mk_ledger_good
mk_ratchet_good

# ---- T1 golden-GOOD ----
expect_pass "T1 golden-GOOD (every class strictly under its ceiling)"

# ---- T2 mutation: push shortcomings over its ceiling (2) ----
cat > "$LEDGER" << 'FIXTURE_EOF'
{"finding_id":"F1","class":"shortcomings","status":"tracked","tracker_ref":"ATM-1","mitigation_evidence":"docs/a.md"}
{"finding_id":"F1b","class":"shortcomings","status":"tracked","tracker_ref":"ATM-1b","mitigation_evidence":"docs/a2.md"}
{"finding_id":"F1c","class":"shortcomings","status":"tracked","tracker_ref":"ATM-1c","mitigation_evidence":"docs/a3.md"}
{"finding_id":"F2","class":"weak_spot","status":"tracked","tracker_ref":"ATM-2","mitigation_evidence":"docs/b.md"}
FIXTURE_EOF
expect_fail "T2 mutation (shortcomings live=3 exceeds ceiling=2)" "reason=RATCHET_EXCEEDED"

# ---- T3 restore ----
mk_ledger_good
expect_pass "T3 restore (gate re-evaluates live, not stuck FAIL)"

# ---- T4 mutation: an un-ratcheted class appears (no entry in ratchet snapshot) ----
cat > "$LEDGER" << 'FIXTURE_EOF'
{"finding_id":"F1","class":"shortcomings","status":"tracked","tracker_ref":"ATM-1","mitigation_evidence":"docs/a.md"}
{"finding_id":"F4","class":"brand_new_danger_zone_class","status":"tracked","tracker_ref":"ATM-4","mitigation_evidence":"docs/d.md"}
FIXTURE_EOF
expect_fail "T4 mutation (un-ratcheted class present, implicit ceiling 0)" "reason=UNRATCHETED_CLASS_PRESENT"

# ---- T5 restore ----
mk_ledger_good
expect_pass "T5 restore"

# ---- T6 mutation: ratchet-snapshot deleted entirely ----
rm -f "$RATCHET"
expect_fail "T6 mutation (ratchet-snapshot deleted -- hard FAIL not BLIND)" "reason=RATCHET_SNAPSHOT_MISSING"

# ---- T7 restore ----
mk_ratchet_good
expect_pass "T7 restore"

# ---- T8 FALSE-POSITIVE GUARD: live count EXACTLY EQUAL to ceiling MUST PASS ----
# shortcomings ceiling is 2; set live shortcomings count to exactly 2.
cat > "$LEDGER" << 'FIXTURE_EOF'
{"finding_id":"F1","class":"shortcomings","status":"tracked","tracker_ref":"ATM-1","mitigation_evidence":"docs/a.md"}
{"finding_id":"F1b","class":"shortcomings","status":"tracked","tracker_ref":"ATM-1b","mitigation_evidence":"docs/a2.md"}
FIXTURE_EOF
expect_pass "T8 false-positive guard (live shortcomings count == ceiling exactly -- <=, not <, MUST PASS)"

# ---- T9 restore -> PASSES again ----
mk_ledger_good
expect_pass "T9 restore after boundary case (gate not stuck)"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} sub-case(s) FAILED"
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-ZERO-FINDINGS-MONOTONE-RATCHET is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=9 fail=0"   # a summary the full-suite runner parses (the case lines above carry fail words such as "correctly FAILED"); 9 sub-cases
exit 0
