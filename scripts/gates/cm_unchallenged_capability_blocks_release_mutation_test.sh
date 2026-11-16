#!/usr/bin/env bash
# cm_unchallenged_capability_blocks_release_mutation_test.sh
#   — §1.1 paired mutation test for CM-UNCHALLENGED-CAPABILITY-BLOCKS-RELEASE.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1): the anchor's own golden-
# FALSE fixture — "a fully-populated ledger whose every row has a fresh
# candidate-fingerprinted PASS verdict" — MUST NOT fire it; each of the three
# blocking classes §11.4.266(D) names (challenge ABSENT / NEVER EXECUTED /
# only at a STALE fingerprint) MUST fire it; restoring PASSes again.
#
# Two §11.4.201(7)(a) CARRIER cases are load-bearing here, because the naive
# implementation of a fingerprint check is "does the candidate fingerprint
# appear in the verdict store":
#   * the candidate fingerprint present ONLY on a DIFFERENT challenge's row
#     (with this row's challenge name appearing only inside that row's free
#     text) -> MUST still FAIL;
#   * the candidate fingerprint present ONLY inside an inert `#` comment
#     -> MUST still FAIL.
#
# All work happens in a disposable `mktemp -d` scratch tree (§11.4.84).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required.
#   1 — at least one sub-case did NOT (the gate is decoration).
#
# Classification: universal (§11.4.17).

set -u
set -o pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_unchallenged_capability_blocks_release.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/docs"

FP="sha256:cafe1234"
STALE="sha256:0000dead"
L="$D/docs/claim_reality_ledger.tsv"
V="$D/docs/claim_reality_verdicts.tsv"

fail_count=0
out="$D/.out"
note() { echo "MUTATION-TEST: $*"; }

run_gate() { bash "$gate" --root "$D" "$@" > "$out" 2>&1; }

expect_pass() {
    local label="$1"; shift
    if run_gate "$@"; then
        note "$label PASSED as required"
    else
        note "$label FAILED unexpectedly (rc=$?, should have PASSed) — output:"; cat "$out"
        fail_count=$((fail_count + 1))
    fi
}
expect_fail() {
    local label="$1" grep_for="$2"; shift 2
    local rc
    run_gate "$@"; rc=$?
    if [ "$rc" -eq 1 ]; then
        if grep -qF -- "$grep_for" "$out"; then
            note "$label correctly FAILED citing '$grep_for'"
        else
            note "$label FAILED but did NOT cite '$grep_for' — output:"; cat "$out"
            fail_count=$((fail_count + 1))
        fi
    else
        note "$label did NOT FAIL as required (rc=$rc, wanted 1) — output:"; cat "$out"
        fail_count=$((fail_count + 1))
    fi
}
expect_blind() {
    local label="$1"; shift
    local rc
    run_gate "$@"; rc=$?
    if [ "$rc" -eq 2 ]; then
        note "$label correctly reported BLIND (rc=2)"
    else
        note "$label did NOT report BLIND (rc=$rc, wanted 2) — output:"; cat "$out"
        fail_count=$((fail_count + 1))
    fi
}

golden_ledger() {
    {
        printf '# claim-vs-reality ledger (§11.4.266)\n'
        printf 'capability\tsurface\tbluff_type\tchallenge\n'
        printf 'video-to-tv\tREADME\tgreen-but-broken\ttests/route.sh\n'
        printf 'audio-multichannel\tmanual\tstubbed-core\ttests/audio.sh\n'
    } > "$L"
}
golden_verdicts() {
    {
        printf '# machine-written verdicts (§11.4.115(F))\n'
        printf 'challenge\tfingerprint\tverdict\tnotes\n'
        printf 'tests/route.sh\t%s\tPASS\tlive on target\n' "$FP"
        printf 'tests/audio.sh\t%s\tpass\tlive on target\n' "$FP"
    } > "$V"
}

# ---- T1 golden-FALSE fixture (the anchor's own): fully populated, all fresh PASS
golden_ledger; golden_verdicts
expect_pass "T1 golden-FALSE fixture (every row fresh candidate-fingerprinted PASS)" --candidate-fingerprint "$FP"

# ---- T2 mutation: blank one row's challenge reference ---------------------
golden_ledger; golden_verdicts
sed -i 's#\ttests/audio.sh$#\t#' "$L"
expect_fail "T2 mutation (challenge reference blanked)" "CHALLENGE_ABSENT" --candidate-fingerprint "$FP"

# ---- T3 restore -----------------------------------------------------------
golden_ledger; golden_verdicts
expect_pass "T3 restore (proves live re-evaluation, not a stuck FAIL)" --candidate-fingerprint "$FP"

# ---- T4 mutation: challenge never executed (no verdict row at all) --------
golden_ledger; golden_verdicts
sed -i '/^tests\/audio.sh/d' "$V"
expect_fail "T4 mutation (challenge never executed — no verdict row)" "NO_VERDICT_FOR_CANDIDATE" --candidate-fingerprint "$FP"

# ---- T5 mutation: verdict exists but only at a STALE fingerprint ----------
golden_ledger
{
    printf 'challenge\tfingerprint\tverdict\n'
    printf 'tests/route.sh\t%s\tPASS\n' "$FP"
    printf 'tests/audio.sh\t%s\tPASS\n' "$STALE"
} > "$V"
expect_fail "T5 mutation (PASS exists only at a STALE fingerprint)" "NO_VERDICT_FOR_CANDIDATE" --candidate-fingerprint "$FP"

# ---- T6 mutation: verdict present at candidate but FAIL ------------------
golden_ledger
{
    printf 'challenge\tfingerprint\tverdict\n'
    printf 'tests/route.sh\t%s\tPASS\n' "$FP"
    printf 'tests/audio.sh\t%s\tFAIL\n' "$FP"
} > "$V"
expect_fail "T6 mutation (verdict at candidate is FAIL)" "CHALLENGE_NOT_PASS" --candidate-fingerprint "$FP"

# ---- T7 CARRIER: candidate fp present only on a DIFFERENT challenge's row,
#       with this row's challenge name appearing only in that row's free text
golden_ledger
{
    printf 'challenge\tfingerprint\tverdict\tnotes\n'
    printf 'tests/route.sh\t%s\tPASS\talso covers tests/audio.sh indirectly\n' "$FP"
} > "$V"
expect_fail "T7 CARRIER (fp + challenge name only inside ANOTHER row's free text)" "NO_VERDICT_FOR_CANDIDATE" --candidate-fingerprint "$FP"

# ---- T8 CARRIER: candidate fp present only inside an inert comment --------
golden_ledger
{
    printf '# validated against %s on 2026-08-20\n' "$FP"
    printf 'challenge\tfingerprint\tverdict\n'
    printf 'tests/route.sh\t%s\tPASS\n' "$STALE"
    printf 'tests/audio.sh\t%s\tPASS\n' "$STALE"
} > "$V"
expect_fail "T8 CARRIER (candidate fp only inside a '#' comment line)" "NO_VERDICT_FOR_CANDIDATE" --candidate-fingerprint "$FP"

# ---- T9 false-positive guard: no ledger at all -> vacuous PASS ------------
rm -f "$L" "$V"
expect_pass "T9 false-positive guard (no ledger present -> vacuous PASS)" --candidate-fingerprint "$FP"

# ---- T10 verdict store absent entirely -> blocks (absence == FAIL) --------
golden_ledger
rm -f "$V"
expect_fail "T10 verdict store absent entirely (absence blocks as a FAIL)" "NO_VERDICT_FOR_CANDIDATE" --candidate-fingerprint "$FP"

# ---- T11 no candidate fingerprint supplied while rows exist -> BLIND ------
golden_ledger; golden_verdicts
expect_blind "T11 no candidate fingerprint supplied -> BLIND, never a guessed candidate"

# ---- T12 placeholder challenge cell ---------------------------------------
{
    printf 'capability\tchallenge\n'
    printf 'video-to-tv\tTODO\n'
} > "$L"
golden_verdicts
expect_fail "T12 placeholder challenge cell ('TODO')" "CHALLENGE_ABSENT" --candidate-fingerprint "$FP"

# ---- T13 ledger with no challenge column ---------------------------------
{
    printf 'capability\tbluff_type\n'
    printf 'video-to-tv\tgreen-but-broken\n'
} > "$L"
expect_fail "T13 ledger names no challenge column" "NO_CHALLENGE_COLUMN" --candidate-fingerprint "$FP"

# ---- T14 markdown ledger + markdown verdicts, all fresh PASS -> PASS ------
LM="$D/docs/claim_reality_ledger.md"
VM="$D/docs/claim_reality_verdicts.md"
{
    printf '| capability | challenge |\n'
    printf '|---|---|\n'
    printf '| video-to-tv | tests/route.sh |\n'
} > "$LM"
{
    printf '| challenge | fingerprint | verdict |\n'
    printf '|---|---|---|\n'
    printf '| tests/route.sh | %s | PASS |\n' "$FP"
} > "$VM"
expect_pass "T14 markdown ledger + markdown verdict store (fresh PASS)" \
    --ledger docs/claim_reality_ledger.md --verdicts docs/claim_reality_verdicts.md \
    --candidate-fingerprint "$FP"

# ---- T15 verdict store missing a required column -> BLIND ----------------
{
    printf 'capability\tchallenge\n'
    printf 'video-to-tv\ttests/route.sh\n'
} > "$L"
{
    printf 'challenge\tverdict\n'
    printf 'tests/route.sh\tPASS\n'
} > "$V"
expect_blind "T15 verdict store lacks a fingerprint column -> BLIND, never a guessed match" --candidate-fingerprint "$FP"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} SUB-CASE(S) FAILED — CM-UNCHALLENGED-CAPABILITY-BLOCKS-RELEASE is DECORATION" >&2
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-UNCHALLENGED-CAPABILITY-BLOCKS-RELEASE is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=15 fail=0"   # a summary the full-suite runner parses (the case lines above carry fail words such as "correctly FAILED"); 15 sub-cases
exit 0
