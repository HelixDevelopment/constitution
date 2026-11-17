#!/usr/bin/env bash
# cm_faq_from_real_questions_mutation_test.sh — §1.1 paired mutation test
# for cm_faq_from_real_questions.sh (§11.4.257(c) / CM-FAQ-FROM-REAL-QUESTIONS).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1) — not a tautology — by
# building a disposable scratch project tree (never the real working tree,
# §11.4.84 quiescence), running the gate against a golden-GOOD fixture
# (MUST PASS), then mutating the fixture through every distinct failure
# mode the gate claims to detect (MUST FAIL each time, citing the specific
# reason), restoring (MUST PASS again — proves the gate re-evaluates live,
# never permanently bricked), and finally proving the false-positive guard
# (an empty manifest — nothing declared — MUST still PASS, per §11.4.257's
# honest boundary that a project owes nothing for an undeclared capability).
#
# ── Sub-cases ────────────────────────────────────────────────────────────────
#   T1 — golden-GOOD (FAQ + corpus present, every Source: id resolves) PASSES.
#   T2 — mutate a Source: id to one absent from the corpus -> FAILs,
#        reason=UNRESOLVED_SOURCE naming the bad id.
#   T3 — restore -> PASSES again (gate is not stuck FAIL).
#   T4 — strip every Source: line from the FAQ -> FAILs,
#        reason=NO_SOURCE_CITATIONS.
#   T5 — restore, then delete the corpus file -> FAILs, reason=CORPUS_MISSING.
#   T6 — restore, then empty the FAQ file -> FAILs, reason=EMPTY.
#   T7 — false-positive guard: header-only manifest (zero components
#        declared) -> PASSES (gate does not fire on nothing declared).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_faq_from_real_questions_mutation_test.sh
#     (no arguments; builds + tears down its own scratch tree under $(mktemp -d))
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-sub-case PASS/FAIL line to stdout; final summary; nonzero exit if any
#   sub-case behaved incorrectly.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp directory ($(mktemp -d)); no writes outside it.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, mktemp, sed, grep. Invokes cm_faq_from_real_questions.sh from the
#   same directory. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation test discipline), §11.4.257(c) (the mandate under
#   test), cm_faq_from_real_questions.sh (gate under test), §11.4.84 (scratch
#   tree, never the real working tree).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required (gate is genuinely load-bearing).
#   1 — at least one sub-case behaved incorrectly (gate is decoration or broken).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_faq_from_real_questions.sh"

scratch="$(mktemp -d)"
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT

fail_count=0

mk_fixture() {
    mkdir -p "$scratch/docs/faq"
    cat > "$scratch/docs/faq/MANIFEST.tsv" << 'EOF'
# component_id	faq_path	corpus_path
compA	docs/faq/compA.md	docs/faq/compA_corpus.md
EOF
    cat > "$scratch/docs/faq/compA_corpus.md" << 'EOF'
[q1] How do I reset my password for compA?
[q2] Why does compA fail to start on ARM?
EOF
    cat > "$scratch/docs/faq/compA.md" << 'EOF'
## Q: How do I reset my password?
Go to Settings > Account > Reset Password.
Source: q1

## Q: Why does the app fail to start on ARM?
Check the ARM-specific build flag.
Source: q2
EOF
}

mk_fixture

# ---- T1 golden-GOOD ----
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    echo "MUTATION-TEST: T1 golden-GOOD (both FAQ+corpus present, sources resolve) PASSED as required"
else
    echo "MUTATION-TEST-FAIL: T1 golden-GOOD did not PASS"
    echo "$out"
    fail_count=$((fail_count + 1))
fi

# ---- T2 mutate: unresolved Source: id ----
sed -i 's/Source: q2/Source: q99/' "$scratch/docs/faq/compA.md"
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    echo "MUTATION-TEST: T2 mutation (unresolved Source id) correctly FAILED"
    if ! echo "$out" | grep -q "UNRESOLVED_SOURCE:q99"; then
        echo "MUTATION-TEST-FAIL: T2 FAIL output did not cite reason=UNRESOLVED_SOURCE:q99"
        echo "$out"
        fail_count=$((fail_count + 1))
    fi
else
    echo "MUTATION-TEST-FAIL: T2 mutation (unresolved Source id) did NOT fail"
    fail_count=$((fail_count + 1))
fi

# ---- T3 restore ----
mk_fixture
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    echo "MUTATION-TEST: T3 restore PASSED as required (gate re-evaluates live, not stuck FAIL)"
else
    echo "MUTATION-TEST-FAIL: T3 restore did not PASS after fixing the mutation"
    echo "$out"
    fail_count=$((fail_count + 1))
fi

# ---- T4 mutate: strip every Source: line ----
cat > "$scratch/docs/faq/compA.md" << 'EOF'
## Q: How do I reset my password?
Go to Settings > Account > Reset Password.

## Q: Why does the app fail to start on ARM?
Check the ARM-specific build flag.
EOF
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    echo "MUTATION-TEST: T4 mutation (no Source citations) correctly FAILED"
    if ! echo "$out" | grep -q "reason=NO_SOURCE_CITATIONS"; then
        echo "MUTATION-TEST-FAIL: T4 FAIL output did not cite reason=NO_SOURCE_CITATIONS"
        echo "$out"
        fail_count=$((fail_count + 1))
    fi
else
    echo "MUTATION-TEST-FAIL: T4 mutation (no Source citations) did NOT fail"
    fail_count=$((fail_count + 1))
fi

# ---- T5 restore, then delete the corpus ----
mk_fixture
rm -f "$scratch/docs/faq/compA_corpus.md"
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    echo "MUTATION-TEST: T5 mutation (missing corpus) correctly FAILED"
    if ! echo "$out" | grep -q "reason=CORPUS_MISSING"; then
        echo "MUTATION-TEST-FAIL: T5 FAIL output did not cite reason=CORPUS_MISSING"
        echo "$out"
        fail_count=$((fail_count + 1))
    fi
else
    echo "MUTATION-TEST-FAIL: T5 mutation (missing corpus) did NOT fail"
    fail_count=$((fail_count + 1))
fi

# ---- T6 restore, then empty the FAQ ----
mk_fixture
: > "$scratch/docs/faq/compA.md"
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    echo "MUTATION-TEST: T6 mutation (empty FAQ) correctly FAILED"
    if ! echo "$out" | grep -q "reason=EMPTY"; then
        echo "MUTATION-TEST-FAIL: T6 FAIL output did not cite reason=EMPTY"
        echo "$out"
        fail_count=$((fail_count + 1))
    fi
else
    echo "MUTATION-TEST-FAIL: T6 mutation (empty FAQ) did NOT fail"
    fail_count=$((fail_count + 1))
fi

# ---- T7 false-positive guard: empty manifest (nothing declared) ----
mkdir -p "$scratch/docs/faq"
cat > "$scratch/docs/faq/MANIFEST.tsv" << 'EOF'
# component_id	faq_path	corpus_path
EOF
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    echo "MUTATION-TEST: T7 false-positive guard (empty manifest) PASSED as required — gate does not fire on nothing declared"
else
    echo "MUTATION-TEST-FAIL: T7 false-positive guard: empty manifest incorrectly FAILED"
    echo "$out"
    fail_count=$((fail_count + 1))
fi

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} sub-case(s) FAILED"
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-FAQ-FROM-REAL-QUESTIONS is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=7 fail=0"   # a summary the full-suite runner parses (the case lines above carry fail words such as "correctly FAILED"); 7 sub-cases
exit 0
