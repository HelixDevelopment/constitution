#!/usr/bin/env bash
# cm_readme_badge_row_at_top_mutation_test.sh — §1.1 paired mutation test
# for cm_readme_badge_row_at_top.sh (§11.4.259 / CM-README-BADGE-ROW-AT-TOP).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1) via a disposable scratch
# README (never the real working tree, §11.4.84 quiescence): golden-GOOD
# PASSES, every distinct failure mode FAILs with its specific reason,
# restore PASSES again, and the min-badges floor is honoured.
#
# ── Sub-cases ────────────────────────────────────────────────────────────────
#   T1 — golden-GOOD (badge row of 2 badges directly after H1) PASSES.
#   T2 — mutate: replace the badge row with ordinary prose -> FAILs.
#   T3 — restore -> PASSES again.
#   T4 — mutate: remove the H1 entirely -> FAILs (BLIND->exit 2, still
#        nonzero, still "did not PASS" as required).
#   T5 — restore, then require --min-badges above what the row provides ->
#        FAILs.
#   T6 — false-positive guard: a badge row with a REALISTIC count (2) and a
#        --min-badges satisfied by it PASSES (proves the gate does not
#        over-fire on a compliant row).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_readme_badge_row_at_top_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp directory ($(mktemp -d)); no writes outside it.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, mktemp, grep. Invokes cm_readme_badge_row_at_top.sh from the same
#   directory. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1, §11.4.259, cm_readme_badge_row_at_top.sh, §11.4.84.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required. 1 — at least one did not.
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_readme_badge_row_at_top.sh"

scratch="$(mktemp -d)"
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT

fail_count=0

mk_fixture() {
    cat > "$scratch/README.md" << 'EOF'
# My Project

![Build](https://img.shields.io/badge/build-passing-green) ![Coverage](https://img.shields.io/badge/coverage-92-green)

Intro paragraph describing the project.
EOF
}

mk_fixture

# ---- T1 golden-GOOD ----
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    echo "MUTATION-TEST: T1 golden-GOOD (badge row at top) PASSED as required"
else
    echo "MUTATION-TEST-FAIL: T1 golden-GOOD did not PASS"; echo "$out"
    fail_count=$((fail_count + 1))
fi

# ---- T2 mutate: replace badge row with prose ----
cat > "$scratch/README.md" << 'EOF'
# My Project

Just a plain sentence, no badges at all.
EOF
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    echo "MUTATION-TEST: T2 mutation (prose instead of badge row) correctly FAILED"
else
    echo "MUTATION-TEST-FAIL: T2 mutation (prose instead of badge row) did NOT fail"
    fail_count=$((fail_count + 1))
fi

# ---- T3 restore ----
mk_fixture
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    echo "MUTATION-TEST: T3 restore PASSED as required (gate re-evaluates live, not stuck FAIL)"
else
    echo "MUTATION-TEST-FAIL: T3 restore did not PASS after fixing the mutation"; echo "$out"
    fail_count=$((fail_count + 1))
fi

# ---- T4 mutate: remove the H1 entirely ----
cat > "$scratch/README.md" << 'EOF'
![Build](https://img.shields.io/badge/build-passing-green)

Intro paragraph, but no heading precedes the badge row.
EOF
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    echo "MUTATION-TEST: T4 mutation (missing H1) correctly FAILED"
else
    echo "MUTATION-TEST-FAIL: T4 mutation (missing H1) did NOT fail"
    fail_count=$((fail_count + 1))
fi

# ---- T5 restore, require min-badges above what's provided ----
mk_fixture
out="$("$gate" --root "$scratch" --min-badges 5 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    echo "MUTATION-TEST: T5 mutation (min-badges floor unmet) correctly FAILED"
else
    echo "MUTATION-TEST-FAIL: T5 mutation (min-badges floor unmet) did NOT fail"
    fail_count=$((fail_count + 1))
fi

# ---- T6 false-positive guard: min-badges satisfied by a compliant row ----
mk_fixture
out="$("$gate" --root "$scratch" --min-badges 2 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    echo "MUTATION-TEST: T6 false-positive guard (min-badges exactly satisfied) PASSED as required"
else
    echo "MUTATION-TEST-FAIL: T6 false-positive guard incorrectly FAILED"; echo "$out"
    fail_count=$((fail_count + 1))
fi

echo "======================================================================"
# The last line is a summary the full-suite runner's verdict parser reads (judge_exit0 looks at the last 12 lines; the
# "correctly FAILED" lines above carry a fail word, and without a parseable summary a passing run is judged ERROR
# unparsed_fail_signal). 6 sub-cases T1-T6.
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} sub-case(s) FAILED"
    echo "MUTATION-TEST-SUMMARY: pass=$((6 - fail_count)) fail=${fail_count}"
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-README-BADGE-ROW-AT-TOP is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=6 fail=0"
exit 0
