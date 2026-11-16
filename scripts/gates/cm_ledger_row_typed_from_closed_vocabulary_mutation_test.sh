#!/usr/bin/env bash
# cm_ledger_row_typed_from_closed_vocabulary_mutation_test.sh
#   — §1.1 paired mutation test for CM-LEDGER-ROW-TYPED-FROM-CLOSED-VOCABULARY.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuinely load-bearing (§1.1) rather than decoration:
# golden-GOOD passes; every distinct mutation class FAILs with the right
# reason; restoring PASSes again (the gate re-evaluates live, never stuck);
# and the §11.4.201(1) false-positive guards plus the §11.4.201(7)(a)
# CARRIER cases — the single most common false finding in this codebase — are
# exercised in BOTH directions:
#
#   * carrier that must NOT rescue a bad row: an invented type in the TYPE
#     column while a NOTES column merely MENTIONS a valid closed-set word
#     -> MUST still FAIL (a whole-row substring scan would wrongly PASS);
#   * carrier that must NOT condemn a good row: a valid type in the TYPE
#     column while a NOTES column merely MENTIONS an invented word
#     -> MUST still PASS.
#
# All work happens in a disposable `mktemp -d` scratch tree (§11.4.84 — never
# the real working tree).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_ledger_row_typed_from_closed_vocabulary_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case behaved as required.
#   1 — at least one sub-case did NOT (the gate is decoration).
#
# Classification: universal (§11.4.17).

set -u
set -o pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_ledger_row_typed_from_closed_vocabulary.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/docs"

fail_count=0
out="$D/.out"
note() { echo "MUTATION-TEST: $*"; }

run_gate() { bash "$gate" --root "$D" --ledger "${1:-docs/claim_reality_ledger.tsv}" > "$out" 2>&1; }

expect_pass() {
    local label="$1" led="${2:-docs/claim_reality_ledger.tsv}"
    if run_gate "$led"; then
        note "$label PASSED as required"
    else
        note "$label FAILED unexpectedly (rc=$?, should have PASSed) — output:"; cat "$out"
        fail_count=$((fail_count + 1))
    fi
}
expect_fail() {
    local label="$1" grep_for="$2" led="${3:-docs/claim_reality_ledger.tsv}" rc
    run_gate "$led"; rc=$?
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
    local label="$1" led="${2:-docs/claim_reality_ledger.tsv}" rc
    run_gate "$led"; rc=$?
    if [ "$rc" -eq 2 ]; then
        note "$label correctly reported BLIND (rc=2)"
    else
        note "$label did NOT report BLIND (rc=$rc, wanted 2) — output:"; cat "$out"
        fail_count=$((fail_count + 1))
    fi
}

L="$D/docs/claim_reality_ledger.tsv"

golden_good() {
    {
        printf '# claim-vs-reality ledger (§11.4.266) — comment line, inert\n'
        printf '\n'
        printf 'capability\tsurface\tbluff_type\tchallenge\tnotes\n'
        printf 'video-to-tv\tREADME\tgreen-but-broken\ttests/route.sh\tpasses CI, fails on device\n'
        printf 'audio-multichannel\tmanual\tSTUBBED-CORE\ttests/audio.sh\tmixed case is fine\n'
        printf 'ota-update\tbadge\tconfig-present-but-unwired\ttests/ota.sh\t-\n'
    } > "$L"
}

# ---- T1 golden-GOOD -------------------------------------------------------
golden_good
expect_pass "T1 golden-GOOD (3 rows, all closed-set types, mixed case)"

# ---- T2 mutation: invented type ------------------------------------------
golden_good
sed -i 's/\bconfig-present-but-unwired\b/mostly-fine/' "$L"
expect_fail "T2 mutation (invented type 'mostly-fine')" "TYPE_OUTSIDE_CLOSED_VOCABULARY"

# ---- T3 restore -----------------------------------------------------------
golden_good
expect_pass "T3 restore (proves live re-evaluation, not a stuck FAIL)"

# ---- T4 CARRIER golden-FALSE: bad type cell, valid word only in NOTES ------
{
    printf 'capability\tsurface\tbluff_type\tchallenge\tnotes\n'
    printf 'video-to-tv\tREADME\tmostly-fine\ttests/route.sh\twe first thought this was stubbed-core but it is not\n'
} > "$L"
expect_fail "T4 CARRIER (invalid type cell; 'stubbed-core' only in NOTES prose)" "TYPE_OUTSIDE_CLOSED_VOCABULARY"

# ---- T5 CARRIER golden-TRUE: good type cell, invented word only in NOTES ---
{
    printf 'capability\tsurface\tbluff_type\tchallenge\tnotes\n'
    printf 'video-to-tv\tREADME\tstubbed-core\ttests/route.sh\ta reviewer called it mostly-fine, which is not a type\n'
} > "$L"
expect_pass "T5 CARRIER false-positive guard (valid type; invented word only in NOTES)"

# ---- T6 mutation: blank type cell ----------------------------------------
{
    printf 'capability\tsurface\tbluff_type\tchallenge\tnotes\n'
    printf 'video-to-tv\tREADME\t\ttests/route.sh\tuntyped\n'
} > "$L"
expect_fail "T6 mutation (blank type cell)" "UNTYPED_ROW"

# ---- T7 mutation: type column removed entirely ---------------------------
{
    printf 'capability\tsurface\tchallenge\tnotes\n'
    printf 'video-to-tv\tREADME\ttests/route.sh\tno type column at all\n'
} > "$L"
expect_fail "T7 mutation (no bluff-type column in header)" "NO_TYPE_COLUMN"

# ---- T8 false-positive guard: no ledger at all -> vacuous PASS ------------
rm -f "$L"
expect_pass "T8 false-positive guard (no ledger present -> vacuous PASS)"

# ---- T9 markdown pipe-table form, all valid -------------------------------
M="$D/docs/claim_reality_ledger.md"
{
    printf '| capability | bluff_type | challenge |\n'
    printf '|---|---|---|\n'
    printf '| video-to-tv | doc-vs-code-drift | tests/route.sh |\n'
    printf '| ota-update | byte-identical-fork | tests/ota.sh |\n'
} > "$M"
expect_pass "T9 markdown pipe-table form (alignment row inert, both types valid)" "docs/claim_reality_ledger.md"

# ---- T10 markdown mutation: invented type --------------------------------
{
    printf '| capability | bluff_type | challenge |\n'
    printf '|---|---|---|\n'
    printf '| video-to-tv | probably-fine | tests/route.sh |\n'
} > "$M"
expect_fail "T10 markdown mutation (invented type)" "TYPE_OUTSIDE_CLOSED_VOCABULARY" "docs/claim_reality_ledger.md"

# ---- T11 strict-match boundary: punctuation variant is NOT folded ---------
{
    printf 'capability\tbluff_type\tchallenge\n'
    printf 'video-to-tv\tstubbed_core\ttests/route.sh\n'
} > "$L"
expect_fail "T11 strict boundary ('stubbed_core' underscore variant is NOT the closed-set token)" "TYPE_OUTSIDE_CLOSED_VOCABULARY"

# ---- T12 BLIND: ledger present but in neither supported tabular form ------
{
    printf 'This ledger is prose. It mentions stubbed-core and green-but-broken.\n'
    printf 'But it has no tabs and no pipe table, so no column can be resolved.\n'
} > "$L"
expect_blind "T12 unsupported ledger form (prose mentioning valid types) -> BLIND, never a guessed green"

# ---- T13 header-only ledger + inert comments -> vacuous PASS --------------
{
    printf '# only a header below\n'
    printf 'capability\tbluff_type\tchallenge\n'
} > "$L"
expect_pass "T13 header-only ledger (0 data rows) -> vacuous PASS"

echo "======================================================================"
if [ "$fail_count" -gt 0 ]; then
    echo "MUTATION-TEST: ${fail_count} SUB-CASE(S) FAILED — CM-LEDGER-ROW-TYPED-FROM-CLOSED-VOCABULARY is DECORATION" >&2
    exit 1
fi
echo "MUTATION-TEST: ALL SUB-CASES PASSED — CM-LEDGER-ROW-TYPED-FROM-CLOSED-VOCABULARY is genuinely load-bearing"
echo "MUTATION-TEST-SUMMARY: pass=13 fail=0"   # a summary the full-suite runner parses (the case lines above carry fail words such as "correctly FAILED"); 13 sub-cases
exit 0
