#!/usr/bin/env bash
# cm_badge_self_validated_mutation_test.sh — §1.1 paired mutation test for
# CM-BADGE-SELF-VALIDATED.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1): golden-good PASSes, each
# distinct mutation class correctly FAILs with the right reason, restore
# PASSes again (the gate re-evaluates live, not stuck), and a false-positive
# guard (no badge row at all -> honest vacuous PASS) is exercised. All work
# happens in a disposable mktemp -d scratch tree (§11.4.84 — never the real
# working tree).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_badge_self_validated_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required.
#   1 — at least one sub-case did NOT behave as required (gate is decoration).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_badge_self_validated.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/scripts/badges"

fail_count=0
note() { echo "MUTATION-TEST: $*"; }
run_gate() { bash "$gate" --root "$D" --readme README.md --badge-computer scripts/badges/compute_badges.sh; }
expect_pass() {
    local label="$1"
    if run_gate >"${TMPDIR:-/tmp}"/.mtest_out.$$ 2>&1; then
        note "$label PASSED as required"
    else
        note "$label FAILED unexpectedly (should have PASSed) — output:"
        cat "${TMPDIR:-/tmp}"/.mtest_out.$$
        fail_count=$((fail_count + 1))
    fi
    rm -f "${TMPDIR:-/tmp}"/.mtest_out.$$
}
expect_fail() {
    local label="$1" grep_for="$2"
    if run_gate >"${TMPDIR:-/tmp}"/.mtest_out.$$ 2>&1; then
        note "$label INCORRECTLY PASSED (should have FAILed) — output:"
        cat "${TMPDIR:-/tmp}"/.mtest_out.$$
        fail_count=$((fail_count + 1))
    else
        if grep -qF "$grep_for" "${TMPDIR:-/tmp}"/.mtest_out.$$; then
            note "$label correctly FAILED citing '$grep_for'"
        else
            note "$label FAILED but did NOT cite expected reason '$grep_for' — output:"
            cat "${TMPDIR:-/tmp}"/.mtest_out.$$
            fail_count=$((fail_count + 1))
        fi
    fi
    rm -f "${TMPDIR:-/tmp}"/.mtest_out.$$
}

cat > "$D/README.md" << 'EOF'
# My Project

![Build](https://img.shields.io/badge/build-green) ![Security](https://img.shields.io/badge/security-amber)

Intro text.
EOF

golden_good_computer() {
    cat > "$D/scripts/badges/compute_badges.sh" << 'EOF'
#!/usr/bin/env bash
# Computes README badge colors from real signals.
# Self-validated per §11.4.107(10): golden-good / golden-bad / negative-control fixtures below.
set -u
selftest() {
    echo "selftest: golden-good OK, golden-bad OK, negative-control OK"
    return 0
}
if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi
echo "green"
EOF
    chmod +x "$D/scripts/badges/compute_badges.sh"
}

# ---- T1: golden-GOOD ----
golden_good_computer
expect_pass "T1 golden-GOOD (executable, all 3 fixture classes named, selftest exits 0)"

# ---- T2: mutation — strip executable bit ----
chmod -x "$D/scripts/badges/compute_badges.sh"
expect_fail "T2 mutation (not executable)" "NOT_EXECUTABLE"

# ---- T3: restore ----
golden_good_computer
expect_pass "T3 restore"

# ---- T4: mutation — strip the negative-control fixture-class marker ----
cat > "$D/scripts/badges/compute_badges.sh" << 'EOF'
#!/usr/bin/env bash
set -u
selftest() {
    echo "selftest: golden-good OK, golden-bad OK"
    return 0
}
if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi
echo "green"
EOF
chmod +x "$D/scripts/badges/compute_badges.sh"
expect_fail "T4 mutation (negative-control fixture-class marker stripped)" "NEGATIVE_CONTROL_FIXTURE_MISSING"

# ---- T5: restore ----
golden_good_computer
expect_pass "T5 restore"

# ---- T6: mutation — selftest now exits non-zero (a genuinely-failing
#          self-check, proving the gate does not fake-pass an unhealthy
#          badge-computer) ----
cat > "$D/scripts/badges/compute_badges.sh" << 'EOF'
#!/usr/bin/env bash
# golden-good golden-bad negative-control
set -u
if [ "${1:-}" = "--selftest" ]; then
    echo "selftest: golden-bad fixture INCORRECTLY passed!"
    exit 1
fi
echo "green"
EOF
chmod +x "$D/scripts/badges/compute_badges.sh"
expect_fail "T6 mutation (selftest exits non-zero)" "SELFTEST_FAILED"

# ---- T7: restore ----
golden_good_computer
expect_pass "T7 restore"

# ---- T8: mutation — badge-computer deleted entirely while README still
#          carries a badge row ----
rm -f "$D/scripts/badges/compute_badges.sh"
expect_fail "T8 mutation (badge-computer deleted entirely)" "MISSING"

# ---- T9: restore + false-positive guard — no badge row at all -> vacuous
#          PASS (nothing to self-validate) ----
golden_good_computer
cat > "$D/README.md" << 'EOF'
# My Project

No badges here, just prose.
EOF
expect_pass "T9 false-positive guard (no badge row -> vacuous PASS)"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} SUB-CASE(S) FAILED — CM-BADGE-SELF-VALIDATED is DECORATION" >&2
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-BADGE-SELF-VALIDATED is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=9 fail=0"   # a summary the full-suite runner parses (its last 12 lines carry "correctly FAILED" fail words)
exit 0
