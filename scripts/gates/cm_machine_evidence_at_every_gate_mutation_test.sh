#!/usr/bin/env bash
# cm_machine_evidence_at_every_gate_mutation_test.sh — §1.1 paired mutation
# test for cm_machine_evidence_at_every_gate.sh (§11.4.262(A)(B)(E) —
# CM-MACHINE-EVIDENCE-AT-EVERY-GATE).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1): golden-good PASSes
# (proven across ALL FOUR legal §11.4.108 layers at once — the
# false-positive-guard proof that the layer-validator does not spuriously
# reject any legitimate layer value), each distinct violation class
# correctly FAILs with the right reason, restore PASSes again, and a
# second false-positive guard is exercised (a manifest declaring ZERO
# rows, and the total absence of a manifest, are both genuinely-vacuous
# states that MUST NOT be mis-flagged as defects — §11.4.201(1)). All work
# happens in a disposable mktemp -d scratch tree (§11.4.84 — never the
# real working tree).
#
# ── Sub-cases ────────────────────────────────────────────────────────────────
#   T1  — golden-GOOD: all 4 legal §11.4.108 layers declared (SOURCE,
#         ARTIFACT, RUNTIME_ON_CLEAN_TARGET, USER_VISIBLE), each with an
#         existing non-empty evidence file whose declared sha256 matches
#         its real sha256 -> PASSES (proves the layer-validator accepts
#         every legitimate layer value, not just one).
#   T2  — mutation: one row's layer value is corrupted to an illegal token
#         -> FAILs reason=INVALID_LAYER.
#   T3  — restore -> PASSES again.
#   T4  — mutation: one row's declared evidence file is deleted ->
#         FAILs reason=EVIDENCE_MISSING.
#   T5  — restore.
#   T6  — mutation: one row's declared evidence file is truncated to
#         zero bytes -> FAILs reason=EVIDENCE_EMPTY.
#   T7  — restore.
#   T8  — mutation: one row's declared evidence file is tampered
#         (appended-to) after its sha256 was recorded, so the real hash
#         no longer matches the declared hash -> FAILs
#         reason=EVIDENCE_HASH_MISMATCH (the content-addressed tamper /
#         staleness detector per §11.4.207).
#   T9  — restore.
#   T10 — FALSE-POSITIVE GUARD (a): manifest exists but declares ZERO
#         rows (comment-only) -> MUST PASS (vacuous, §11.4.201(1)).
#   T11 — FALSE-POSITIVE GUARD (b): manifest file does not exist at all
#         -> MUST PASS (vacuous, §11.4.201(1)).
#   T12 — restore to golden-GOOD -> PASSES again (gate not stuck).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_machine_evidence_at_every_gate_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required (gate is genuinely load-bearing).
#   1 — at least one sub-case behaved incorrectly (gate is decoration or broken).
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_machine_evidence_at_every_gate.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/docs/evidence" "$D/qa-results"
MANIFEST="$D/docs/evidence/gate_evidence_manifest.tsv"
EV_SOURCE="$D/qa-results/ev_source.txt"
EV_ARTIFACT="$D/qa-results/ev_artifact.txt"
EV_RUNTIME="$D/qa-results/ev_runtime.txt"
EV_USERVISIBLE="$D/qa-results/ev_uservisible.txt"

fail_count=0
note() { echo "MUTATION-TEST: $*"; }

run_gate() { bash "$gate" --root "$D" --manifest docs/evidence/gate_evidence_manifest.tsv; }

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

mk_evidence_files_good() {
    echo "source-layer grep transcript, iteration $$" > "$EV_SOURCE"
    echo "artifact-byte-check output, iteration $$" > "$EV_ARTIFACT"
    echo "runtime-signature dumpsys capture, iteration $$" > "$EV_RUNTIME"
    echo "user-visible captured screencap/audio proof, iteration $$" > "$EV_USERVISIBLE"
}

mk_manifest_good() {
    local sha_source sha_artifact sha_runtime sha_uservisible
    sha_source="$(sha256sum "$EV_SOURCE" | awk '{print $1}')"
    sha_artifact="$(sha256sum "$EV_ARTIFACT" | awk '{print $1}')"
    sha_runtime="$(sha256sum "$EV_RUNTIME" | awk '{print $1}')"
    sha_uservisible="$(sha256sum "$EV_USERVISIBLE" | awk '{print $1}')"
    printf 'G1\tSOURCE\tqa-results/ev_source.txt\t%s\n' "$sha_source" > "$MANIFEST"
    printf 'G2\tARTIFACT\tqa-results/ev_artifact.txt\t%s\n' "$sha_artifact" >> "$MANIFEST"
    printf 'G3\tRUNTIME_ON_CLEAN_TARGET\tqa-results/ev_runtime.txt\t%s\n' "$sha_runtime" >> "$MANIFEST"
    printf 'G4\tUSER_VISIBLE\tqa-results/ev_uservisible.txt\t%s\n' "$sha_uservisible" >> "$MANIFEST"
}

mk_evidence_files_good
mk_manifest_good

# ---- T1 golden-GOOD (all 4 legal layers) ----
expect_pass "T1 golden-GOOD (all 4 legal §11.4.108 layers, correct hashes)"

# ---- T2 mutation: corrupt one row's layer to an illegal token ----
sed -i 's/^G3\tRUNTIME_ON_CLEAN_TARGET\t/G3\tNOT_A_REAL_LAYER\t/' "$MANIFEST"
expect_fail "T2 mutation (row's layer value is illegal)" "reason=INVALID_LAYER"

# ---- T3 restore ----
mk_manifest_good
expect_pass "T3 restore (gate re-evaluates live, not stuck FAIL)"

# ---- T4 mutation: delete one row's declared evidence file ----
rm -f "$EV_ARTIFACT"
expect_fail "T4 mutation (declared evidence file deleted)" "reason=EVIDENCE_MISSING"

# ---- T5 restore ----
mk_evidence_files_good
mk_manifest_good
expect_pass "T5 restore"

# ---- T6 mutation: truncate one row's evidence file to zero bytes ----
: > "$EV_USERVISIBLE"
expect_fail "T6 mutation (declared evidence file truncated to zero bytes)" "reason=EVIDENCE_EMPTY"

# ---- T7 restore ----
mk_evidence_files_good
mk_manifest_good
expect_pass "T7 restore"

# ---- T8 mutation: tamper one row's evidence AFTER its sha256 was recorded ----
echo "TAMPERED-AFTER-THE-FACT" >> "$EV_RUNTIME"
expect_fail "T8 mutation (evidence tampered after sha256 was recorded)" "reason=EVIDENCE_HASH_MISMATCH"

# ---- T9 restore ----
mk_evidence_files_good
mk_manifest_good
expect_pass "T9 restore"

# ---- T10 FALSE-POSITIVE GUARD (a): manifest exists, declares zero rows ----
cat > "$MANIFEST" << 'FIXTURE_EOF'
# no gate-evidence rows declared yet -- genuinely-empty manifest
FIXTURE_EOF
expect_pass "T10 false-positive guard (manifest declares zero rows -- MUST PASS, vacuous §11.4.201(1))"

# ---- T11 FALSE-POSITIVE GUARD (b): manifest file absent entirely ----
rm -f "$MANIFEST"
expect_pass "T11 false-positive guard (manifest file absent entirely -- MUST PASS, vacuous §11.4.201(1))"

# ---- T12 restore to golden-GOOD -> PASSES again ----
mk_evidence_files_good
mk_manifest_good
expect_pass "T12 restore after false-positive-guard cases (gate not stuck)"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} sub-case(s) FAILED"
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-MACHINE-EVIDENCE-AT-EVERY-GATE is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=12 fail=0"   # a summary the full-suite runner parses (the case lines above carry fail words such as "correctly FAILED"); 12 sub-cases
exit 0
