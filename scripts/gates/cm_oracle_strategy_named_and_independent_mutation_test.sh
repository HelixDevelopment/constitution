#!/usr/bin/env bash
# cm_oracle_strategy_named_and_independent_mutation_test.sh — §1.1 paired
# mutation test for CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT (§11.4.245).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is NOT a bluff: plants deliberate violations (missing
# annotation, unknown/invalid strategy value) and asserts the gate FAILs;
# then asserts the gate PASSes on clean fixtures (trailing comment, preceding
# comment, docstring form, hyphen-alias closed-set member). Also carries a
# dedicated REGRESSION fixture for a real cross-function-contamination bug
# discovered and fixed while authoring this gate: an earlier version of the
# backward-looking preceding-comment scan could bleed into a PRIOR test
# function's own body and pick up ITS oracle annotation as if it satisfied
# the CURRENT function -- a false-negative (§11.4.201 PASS-bluff). This
# fixture MUST keep catching that class of defect on every future edit.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_oracle_strategy_named_and_independent_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling gate script. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.245 (the anchor enforced), §1.1 (paired mutation), §11.4.201(1)
#   (false-positive refusal is a FAIL-bluff -- the negative controls prove
#   this), §11.4.6 (honest documented bounded limitation).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every case behaves correctly (FAIL-on-mutation AND PASS-on-clean).
#   1 — the gate is a bluff (did not FAIL on a mutation, or false-positive
#       refused a clean/negative-control fixture).
#   2 — environment error (gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail
# The legacy absolute mode is what these fixtures assert (no baseline in a fixture); ratchet mode is covered by tests/gates/test_oracle_ratchet_and_consumer_skips.sh.
export ORACLE_GUARD_STRICT=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_oracle_strategy_named_and_independent.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/oracle_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
expect_fail() { # $1=desc  $2=dir
    local desc="$1" dir="$2"
    if bash "$GATE" --root "$dir" >/dev/null 2>&1; then
        echo "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        echo "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}
expect_pass() { # $1=desc  $2=dir
    local desc="$1" dir="$2"
    if bash "$GATE" --root "$dir" >/dev/null 2>&1; then
        echo "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
    else
        echo "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false-positive refusal, §11.4.201(1))"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT (§11.4.245)"
echo "fixtures under: $TMP"
echo "======================================================================"

# --- 1. no oracle annotation at all (bad) vs trailing-comment SPECIFIED (good) ---
mkdir -p "$TMP/1_bad" "$TMP/1_good"
cat > "$TMP/1_bad/test_case1.py" <<'PY'
def test_add():
    result = add(2, 3)
    assert result == 5
PY
cat > "$TMP/1_good/test_case1.py" <<'PY'
def test_add():
    # oracle: SPECIFIED
    result = add(2, 3)
    assert result == 5
PY
expect_fail "no oracle annotation at all" "$TMP/1_bad"
expect_pass "trailing-comment SPECIFIED annotation" "$TMP/1_good"

# --- 2. unknown/invalid strategy value (bad) vs preceding-comment DERIVED (good) ---
mkdir -p "$TMP/2_bad" "$TMP/2_good"
cat > "$TMP/2_bad/test_case2.py" <<'PY'
def test_multiply():
    # oracle: VIBES
    assert mul(2, 3) == 6
PY
cat > "$TMP/2_good/test_case2.py" <<'PY'
# oracle: DERIVED
def test_multiply():
    assert mul(2, 3) == 6
PY
expect_fail "unknown/invalid strategy value ('VIBES' not in closed set)" "$TMP/2_bad"
expect_pass "preceding-comment DERIVED annotation" "$TMP/2_good"

# --- 3. docstring-form Oracle: line (good) + hyphen-alias GOLDEN-MASTER (good) ---
mkdir -p "$TMP/3_good"
cat > "$TMP/3_good/test_case3.py" <<'PY'
def test_docstring_form():
    """Verifies a metamorphic relation holds.
    Oracle: METAMORPHIC
    """
    assert True

def test_hyphen_alias_form():
    # oracle: golden-master
    assert True
PY
expect_pass "docstring-form + hyphen-alias closed-set member (both real tests, no cross-contamination)" "$TMP/3_good"

# --- 4. REGRESSION FIXTURE: cross-function-contamination -----------------
#   A test WITH a valid annotation immediately precedes a test WITH NONE.
#   The gate's backward-looking preceding-comment scan MUST NOT bleed
#   across the blank-line/def boundary into the PRIOR function's body and
#   satisfy the LATER function's requirement -- this is the exact
#   false-negative bug found + fixed while authoring this gate.
mkdir -p "$TMP/4_regression"
cat > "$TMP/4_regression/test_case4.py" <<'PY'
def test_with_valid_annotation():
    # oracle: SPECIFIED
    assert True

def test_with_no_annotation_at_all():
    assert True
PY
expect_fail "cross-function-contamination REGRESSION: 2nd test has no own annotation, must not inherit the 1st's" "$TMP/4_regression"

# --- 5. Negative control: SKIP on no candidate files (never a fake pass/fail) ---
mkdir -p "$TMP/5_no_tests"
cat > "$TMP/5_no_tests/helpers.py" <<'PY'
def add(a, b):
    return a + b
PY
expect_pass "no candidate test files present — honest SKIP (exit 0), never a fake FAIL" "$TMP/5_no_tests"

# --- 6. Adoption path (--adopt-new-files --reason): narrow, audited, never raises ---------------------
adopt() { env -u ORACLE_GUARD_STRICT bash "$GATE" --root "$1" --baseline "$1/b.txt" "${@:2}" >/dev/null 2>&1; }
mkdir -p "$TMP/6_adopt"
printf 'def test_u1():\n    assert 1\n' > "$TMP/6_adopt/test_new6.py"
printf 'def test_o():\n    assert 1\n' > "$TMP/6_adopt/test_old6.py"
printf 'test_old6.py\t1\n' > "$TMP/6_adopt/b.txt"
if adopt "$TMP/6_adopt" --adopt-new-files; then echo "❌ META FAIL: adoption without --reason accepted"; rc=1; else echo "✅ META OK:   adoption without --reason refused"; fi
if adopt "$TMP/6_adopt" --adopt-new-files --reason "meta" && grep -q $'^test_new6.py\t1$' "$TMP/6_adopt/b.txt" && grep -q 'reason=meta' "$TMP/6_adopt/oracle_ratchet_adoptions.log"; then echo "✅ META OK:   adoption adds the new file and logs it"; else echo "❌ META FAIL: adoption did not add/log"; rc=1; fi
printf 'def test_o2():\n    assert 1\n' >> "$TMP/6_adopt/test_old6.py"
printf 'def test_u2():\n    assert 1\n' > "$TMP/6_adopt/test_new7.py"
if adopt "$TMP/6_adopt" --adopt-new-files --reason "raise attempt" || grep -q test_new7 "$TMP/6_adopt/b.txt"; then echo "❌ META FAIL: adoption raised/ignored an over-baseline existing file"; rc=1; else echo "✅ META OK:   adoption refuses while an existing entry would increase"; fi

# --- 7. --help prints the header through its REAL end (Classification line), derived not hardcoded (round 5 N-1) ---
_cls="$(grep -m1 '^# Classification:' "$GATE" | sed 's/^# \{0,1\}//')"
_help_last="$(bash "$GATE" --help 2>/dev/null | tail -1)"
if [ -n "$_cls" ] && [ "$_help_last" = "$_cls" ]; then echo "✅ META OK:   --help ends on the Classification line"; else echo "❌ META FAIL: --help last line '${_help_last}' != Classification line '${_cls}'"; rc=1; fi
# mutant: hardcoded cut at a stale line count must be DETECTED by the same check
_mg="$TMP/help_mut.sh"; sed "s|sed -n \"1,\$(awk '/^# Classification:/{print NR; exit}' \"\$0\")p\" \"\$0\"|sed -n '1,150p' \"\$0\"|" "$GATE" > "$_mg"
if grep -q "1,150p" "$_mg" && [ "$(bash "$_mg" --help 2>/dev/null | tail -1)" != "$_cls" ]; then echo "✅ META OK:   hardcoded-150 help mutant is killed"; else echo "❌ META FAIL: hardcoded-help mutant survived or was not applied"; rc=1; fi

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS — CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT FAILs-on-mutation AND PASSes-on-clean for every fixture, including the cross-contamination regression (§1.1 proof holds)"
else
    echo "❌ META FAIL — CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT is a bluff gate"
fi
exit "$rc"
