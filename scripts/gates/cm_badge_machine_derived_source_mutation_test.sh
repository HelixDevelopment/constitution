#!/usr/bin/env bash
# cm_badge_machine_derived_source_mutation_test.sh — §1.1 paired mutation
# test for CM-BADGE-MACHINE-DERIVED-SOURCE.
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
#   cm_badge_machine_derived_source_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required.
#   1 — at least one sub-case did NOT behave as required (gate is decoration).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_badge_machine_derived_source.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/docs"

fail_count=0
note() { echo "MUTATION-TEST: $*"; }
run_gate() { bash "$gate" --root "$D" --readme README.md --provenance docs/BADGES.md; }
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

# ---- T1: golden-GOOD — 2 badges, both have provenance entries ----
cat > "$D/README.md" << 'EOF'
# My Project

![Build](https://img.shields.io/badge/build-green) ![Security](https://img.shields.io/badge/security-amber)

Intro text.
EOF
cat > "$D/docs/BADGES.md" << 'EOF'
# Badge Provenance

## Build
Source: scripts/badges/compute_build_badge.sh

## Security
Source: scripts/testing/security_scan.sh
EOF
expect_pass "T1 golden-GOOD (both badges provenanced)"

# ---- T2: mutation — remove the Security section entirely (missing entry) ----
cat > "$D/docs/BADGES.md" << 'EOF'
# Badge Provenance

## Build
Source: scripts/badges/compute_build_badge.sh
EOF
expect_fail "T2 mutation (Security section removed from provenance)" "NO_PROVENANCE_ENTRY"

# ---- T3: restore ----
cat > "$D/docs/BADGES.md" << 'EOF'
# Badge Provenance

## Build
Source: scripts/badges/compute_build_badge.sh

## Security
Source: scripts/testing/security_scan.sh
EOF
expect_pass "T3 restore"

# ---- T4: mutation — Security section present but Source: value emptied
#          (present-but-hand-typed-looking entry) ----
cat > "$D/docs/BADGES.md" << 'EOF'
# Badge Provenance

## Build
Source: scripts/badges/compute_build_badge.sh

## Security
Source:
EOF
expect_fail "T4 mutation (empty Source: value)" "NO_PROVENANCE_ENTRY"

# ---- T5: restore again ----
cat > "$D/docs/BADGES.md" << 'EOF'
# Badge Provenance

## Build
Source: scripts/badges/compute_build_badge.sh

## Security
Source: scripts/testing/security_scan.sh
EOF
expect_pass "T5 restore"

# ---- T6: mutation — provenance manifest deleted entirely ----
rm -f "$D/docs/BADGES.md"
expect_fail "T6 mutation (provenance manifest deleted)" "MISSING"

# ---- T7: restore + false-positive guard — no badge row at all -> vacuous
#          PASS (nothing to prove machine-derived) ----
cat > "$D/docs/BADGES.md" << 'EOF'
# Badge Provenance

## Build
Source: scripts/badges/compute_build_badge.sh

## Security
Source: scripts/testing/security_scan.sh
EOF
cat > "$D/README.md" << 'EOF'
# My Project

No badges here, just prose.
EOF
expect_pass "T7 false-positive guard (no badge row -> vacuous PASS)"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} SUB-CASE(S) FAILED — CM-BADGE-MACHINE-DERIVED-SOURCE is DECORATION" >&2
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-BADGE-MACHINE-DERIVED-SOURCE is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=7 fail=0"   # a summary the full-suite runner parses (its last 12 lines carry "correctly FAILED" fail words)
exit 0
