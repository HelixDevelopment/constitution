#!/usr/bin/env bash
# cm_guide_per_user_workflow_mutation_test.sh — §1.1 paired mutation test
# for CM-GUIDE-PER-USER-WORKFLOW (§11.4.257(b)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (never a tautology) via six
# sub-cases, all run against disposable scratch trees (never the real
# checkout — §11.4.84 quiescence):
#   T1 (golden-GOOD)        — two workflows, both guides present/non-empty
#                             -> gate MUST PASS.
#   T2 (mutation: MISSING)  — delete one guide's file -> gate MUST FAIL.
#   T3 (restore)            — recreate that file -> gate MUST PASS again
#                             (proves the gate is not permanently bricked by
#                             one prior failure — a live, re-evaluated check).
#   T4 (mutation: EMPTY)    — truncate a guide to zero bytes -> gate MUST FAIL.
#   T5 (mutation: INCOMPLETE) — write only the `<!-- STATUS: INCOMPLETE -->`
#                             marker -> gate MUST FAIL (an honestly-tracked
#                             gap still fails THIS gate per §11.4.257's
#                             "ships without its trio" standard).
#   T6 (golden-BAD false-positive guard) — an EMPTY manifest (zero declared
#                             workflows) MUST PASS, not FAIL — proves the
#                             gate never fires on genuinely-nothing-declared
#                             (the false-positive guard per §11.4.201).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_guide_per_user_workflow_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — all six sub-cases behaved as required.
#   1 — at least one sub-case did not behave as required.
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_guide_per_user_workflow.sh"

fails=0
note() { echo "MUTATION-TEST: $*"; }
fail() { echo "MUTATION-TEST-FAIL: $*" >&2; fails=$((fails + 1)); }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

mkdir -p "${scratch}/docs/guides"
cat > "${scratch}/docs/guides/MANIFEST.tsv" <<'M'
# workflow_id	guide_path
wfA	docs/guides/wfA.md
wfB	docs/guides/wfB.md
M
echo "Real, non-trivial guide content for workflow A." > "${scratch}/docs/guides/wfA.md"
echo "Real, non-trivial guide content for workflow B." > "${scratch}/docs/guides/wfB.md"

# ── T1: golden-GOOD ──────────────────────────────────────────────────────────
if "$gate" --root "$scratch" >"${TMPDIR:-/tmp}"/.cm_gpuw_t1.log 2>&1; then
    note "T1 golden-GOOD (both guides present) PASSED as required"
else
    fail "T1 golden-GOOD did not PASS"; cat "${TMPDIR:-/tmp}"/.cm_gpuw_t1.log >&2
fi

# ── T2: mutation — delete wfB's guide ────────────────────────────────────
rm -f "${scratch}/docs/guides/wfB.md"
if "$gate" --root "$scratch" >"${TMPDIR:-/tmp}"/.cm_gpuw_t2.log 2>&1; then
    fail "T2 mutation (MISSING guide) did NOT FAIL — gate is a tautology"
else
    note "T2 mutation (MISSING guide) correctly FAILED"
fi
grep -q "wfB" "${TMPDIR:-/tmp}"/.cm_gpuw_t2.log || fail "T2 FAIL output did not name the offending workflow 'wfB'"

# ── T3: restore ──────────────────────────────────────────────────────────────
echo "Real, non-trivial guide content for workflow B." > "${scratch}/docs/guides/wfB.md"
if "$gate" --root "$scratch" >"${TMPDIR:-/tmp}"/.cm_gpuw_t3.log 2>&1; then
    note "T3 restore PASSED as required (gate re-evaluates live, not stuck FAIL)"
else
    fail "T3 restore did not PASS after fixing the mutation"; cat "${TMPDIR:-/tmp}"/.cm_gpuw_t3.log >&2
fi

# ── T4: mutation — EMPTY guide ──────────────────────────────────────────────
: > "${scratch}/docs/guides/wfA.md"
if "$gate" --root "$scratch" >"${TMPDIR:-/tmp}"/.cm_gpuw_t4.log 2>&1; then
    fail "T4 mutation (EMPTY guide) did NOT FAIL"
else
    note "T4 mutation (EMPTY guide) correctly FAILED"
fi
grep -q "EMPTY" "${TMPDIR:-/tmp}"/.cm_gpuw_t4.log || fail "T4 FAIL output did not cite reason=EMPTY"
echo "Real, non-trivial guide content for workflow A." > "${scratch}/docs/guides/wfA.md"

# ── T5: mutation — INCOMPLETE marker ────────────────────────────────────────
printf '%s\n' '<!-- STATUS: INCOMPLETE -->' > "${scratch}/docs/guides/wfA.md"
if "$gate" --root "$scratch" >"${TMPDIR:-/tmp}"/.cm_gpuw_t5.log 2>&1; then
    fail "T5 mutation (INCOMPLETE marker) did NOT FAIL — a tracked-but-not-done guide must still fail this gate"
else
    note "T5 mutation (INCOMPLETE marker) correctly FAILED"
fi
grep -q "INCOMPLETE" "${TMPDIR:-/tmp}"/.cm_gpuw_t5.log || fail "T5 FAIL output did not cite reason=INCOMPLETE"
echo "Real, non-trivial guide content for workflow A." > "${scratch}/docs/guides/wfA.md"

# ── T6: golden-BAD false-positive guard — empty manifest MUST PASS ─────────
printf '# nothing declared yet\n' > "${scratch}/docs/guides/MANIFEST.tsv"
if "$gate" --root "$scratch" >"${TMPDIR:-/tmp}"/.cm_gpuw_t6.log 2>&1; then
    note "T6 false-positive guard (empty manifest) PASSED as required — gate does not fire on nothing declared"
else
    fail "T6 false-positive guard: empty manifest incorrectly FAILED"; cat "${TMPDIR:-/tmp}"/.cm_gpuw_t6.log >&2
fi

if [ "$fails" -eq 0 ]; then
    echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-GUIDE-PER-USER-WORKFLOW is genuinely load-bearing"
    echo "MUTATION-TEST-SUMMARY: pass=6 fail=0"   # a summary the full-suite runner parses (its last 12 lines carry "correctly FAILED" fail words)
    exit 0
else
    echo "MUTATION-TEST: ${fails} sub-case(s) FAILED" >&2
    exit 1
fi
