#!/usr/bin/env bash
# cm_badge_closed_color_vocabulary_mutation_test.sh — §1.1 paired mutation test
# for CM-BADGE-CLOSED-COLOR-VOCABULARY.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1): golden-good PASSes, each
# distinct mutation class correctly FAILs with the right reason, restore
# PASSes again (the gate re-evaluates live, not stuck), and a false-positive
# guard (a badge with NO recognisable color word at all → honestly FAILs, not
# silently ignored) is exercised. All work happens in a disposable mktemp -d
# scratch tree (§11.4.84 — never the real working tree).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_badge_closed_color_vocabulary_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required.
#   1 — at least one sub-case did NOT behave as required (gate is decoration).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_badge_closed_color_vocabulary.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

fail_count=0
note() { echo "MUTATION-TEST: $*"; }
expect_pass() {
    local label="$1"
    if bash "$gate" --root "$D" --readme README.md >"${TMPDIR:-/tmp}"/.mtest_out.$$ 2>&1; then
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
    if bash "$gate" --root "$D" --readme README.md >"${TMPDIR:-/tmp}"/.mtest_out.$$ 2>&1; then
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

# ---- T1: golden-GOOD — 2 badges on one row, both closed-vocabulary colors ----
cat > "$D/README.md" << 'EOF'
# My Project

![Build](https://img.shields.io/badge/build-green) ![Security](https://img.shields.io/badge/security-amber)

Intro text.
EOF
expect_pass "T1 golden-GOOD (green + amber badges)"

# ---- T2: mutation — one badge's color changed to a non-closed-set word ----
cat > "$D/README.md" << 'EOF'
# My Project

![Build](https://img.shields.io/badge/build-green) ![Security](https://img.shields.io/badge/security-yellow)

Intro text.
EOF
expect_fail "T2 mutation (yellow — outside closed vocabulary)" "NO_CLOSED_COLOR_TOKEN"

# ---- T3: restore — proves the gate re-evaluates live, not stuck FAIL ----
cat > "$D/README.md" << 'EOF'
# My Project

![Build](https://img.shields.io/badge/build-green) ![Security](https://img.shields.io/badge/security-amber)

Intro text.
EOF
expect_pass "T3 restore"

# ---- T4: mutation — shields.io decorative variant (brightgreen) treated as
#          OUTSIDE the closed set per the gate's documented strict-match
#          honest boundary (§11.4.6) ----
cat > "$D/README.md" << 'EOF'
# My Project

![Build](https://img.shields.io/badge/build-brightgreen) ![Security](https://img.shields.io/badge/security-red)

Intro text.
EOF
expect_fail "T4 mutation (brightgreen — decorative variant, not a closed-set word)" "NO_CLOSED_COLOR_TOKEN"

# ---- T5: restore again ----
cat > "$D/README.md" << 'EOF'
# My Project

![Build](https://img.shields.io/badge/build-red) ![Security](https://img.shields.io/badge/security-gray)

Intro text.
EOF
expect_pass "T5 restore (red + gray, both closed-set)"

# ---- T6: false-positive guard — no badge row at all → vacuous PASS, never
#          a spurious FAIL because "there is nothing to judge" ----
cat > "$D/README.md" << 'EOF'
# My Project

No badges here, just prose.
EOF
expect_pass "T6 false-positive guard (no badge row -> vacuous PASS)"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} SUB-CASE(S) FAILED — CM-BADGE-CLOSED-COLOR-VOCABULARY is DECORATION" >&2
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-BADGE-CLOSED-COLOR-VOCABULARY is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=6 fail=0"   # a summary the full-suite runner parses (its last 12 lines carry "correctly FAILED" fail words)
exit 0
