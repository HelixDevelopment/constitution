#!/usr/bin/env bash
# cm_diagram_embedded_not_orphan_mutation_test.sh — §1.1 paired mutation test
# for cm_diagram_embedded_not_orphan.sh (§11.4.258 / CM-DIAGRAM-EMBEDDED-NOT-ORPHAN).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1) — not a tautology — by
# building a disposable scratch project tree (never the real working tree,
# §11.4.84 quiescence) with a README -> guide -> diagram link chain, running
# the gate against a golden-GOOD fixture (MUST PASS), then mutating it
# through every distinct failure mode the gate claims to detect (MUST FAIL
# each time, citing the specific reason), restoring (MUST PASS again — the
# gate re-evaluates live, never permanently bricked), and finally proving
# the false-positive guard (an empty manifest — nothing declared — MUST
# still PASS).
#
# ── Sub-cases ────────────────────────────────────────────────────────────────
#   T1 — golden-GOOD (README -> guide -> diagram all linked) PASSES.
#   T2 — mutate: remove the guide's link to the diagram (orphan it) -> FAILs,
#        reason=ORPHAN_NOT_README_REACHABLE.
#   T3 — restore -> PASSES again (gate is not stuck FAIL).
#   T4 — mutate: delete the diagram file entirely -> FAILs, reason=MISSING.
#   T5 — restore, then break the README's link to the guide (severing the
#        reachability chain one hop up) -> FAILs, reason=ORPHAN_NOT_README_REACHABLE
#        (the diagram is still linked from the guide, but the guide itself is
#        no longer README-reachable, so the diagram effectively is not either).
#   T6 — false-positive guard: header-only manifest (zero diagrams declared)
#        -> PASSES (gate does not fire on nothing declared).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_diagram_embedded_not_orphan_mutation_test.sh
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
#   bash, mktemp, sed, grep. Invokes cm_diagram_embedded_not_orphan.sh from
#   the same directory. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation test discipline), §11.4.258 (the mandate under
#   test), cm_diagram_embedded_not_orphan.sh (gate under test), §11.4.84
#   (scratch tree, never the real working tree).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required (gate is genuinely load-bearing).
#   1 — at least one sub-case behaved incorrectly (gate is decoration or broken).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_diagram_embedded_not_orphan.sh"

scratch="$(mktemp -d)"
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT

fail_count=0

mk_fixture() {
    mkdir -p "$scratch/docs/diagrams" "$scratch/docs/guides"
    cat > "$scratch/README.md" << 'EOF'
# My Project

See the [architecture guide](docs/guides/architecture.md) for details.
EOF
    cat > "$scratch/docs/guides/architecture.md" << 'EOF'
# Architecture

Here is the system diagram:

![System diagram](../diagrams/system.mmd)
EOF
    cat > "$scratch/docs/diagrams/system.mmd" << 'EOF'
graph TD; A-->B;
EOF
    cat > "$scratch/docs/diagrams/MANIFEST.tsv" << 'EOF'
# diagram_id	diagram_path
system	docs/diagrams/system.mmd
EOF
}

mk_fixture

# ---- T1 golden-GOOD ----
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    echo "MUTATION-TEST: T1 golden-GOOD (README->guide->diagram linked) PASSED as required"
else
    echo "MUTATION-TEST-FAIL: T1 golden-GOOD did not PASS"
    echo "$out"
    fail_count=$((fail_count + 1))
fi

# ---- T2 mutate: orphan the diagram (unlink from the guide) ----
cat > "$scratch/docs/guides/architecture.md" << 'EOF'
# Architecture
No diagram linked here.
EOF
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    echo "MUTATION-TEST: T2 mutation (orphaned diagram) correctly FAILED"
    if ! echo "$out" | grep -q "reason=ORPHAN_NOT_README_REACHABLE"; then
        echo "MUTATION-TEST-FAIL: T2 FAIL output did not cite reason=ORPHAN_NOT_README_REACHABLE"
        echo "$out"
        fail_count=$((fail_count + 1))
    fi
else
    echo "MUTATION-TEST-FAIL: T2 mutation (orphaned diagram) did NOT fail"
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

# ---- T4 mutate: delete the diagram file ----
rm -f "$scratch/docs/diagrams/system.mmd"
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    echo "MUTATION-TEST: T4 mutation (deleted diagram file) correctly FAILED"
    if ! echo "$out" | grep -q "reason=MISSING"; then
        echo "MUTATION-TEST-FAIL: T4 FAIL output did not cite reason=MISSING"
        echo "$out"
        fail_count=$((fail_count + 1))
    fi
else
    echo "MUTATION-TEST-FAIL: T4 mutation (deleted diagram file) did NOT fail"
    fail_count=$((fail_count + 1))
fi

# ---- T5 restore, then sever the README->guide hop ----
mk_fixture
cat > "$scratch/README.md" << 'EOF'
# My Project
No links to any guide here.
EOF
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    echo "MUTATION-TEST: T5 mutation (severed README->guide hop) correctly FAILED"
    if ! echo "$out" | grep -q "reason=ORPHAN_NOT_README_REACHABLE"; then
        echo "MUTATION-TEST-FAIL: T5 FAIL output did not cite reason=ORPHAN_NOT_README_REACHABLE"
        echo "$out"
        fail_count=$((fail_count + 1))
    fi
else
    echo "MUTATION-TEST-FAIL: T5 mutation (severed README->guide hop) did NOT fail"
    fail_count=$((fail_count + 1))
fi

# ---- T6 false-positive guard: empty manifest (nothing declared) ----
mk_fixture
cat > "$scratch/docs/diagrams/MANIFEST.tsv" << 'EOF'
# diagram_id	diagram_path
EOF
out="$("$gate" --root "$scratch" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    echo "MUTATION-TEST: T6 false-positive guard (empty manifest) PASSED as required — gate does not fire on nothing declared"
else
    echo "MUTATION-TEST-FAIL: T6 false-positive guard: empty manifest incorrectly FAILED"
    echo "$out"
    fail_count=$((fail_count + 1))
fi

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} sub-case(s) FAILED"
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-DIAGRAM-EMBEDDED-NOT-ORPHAN is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=6 fail=0"   # a summary the full-suite runner parses (the case lines above carry fail words such as "correctly FAILED"); 6 sub-cases
exit 0
