#!/bin/sh
# =============================================================================
# test_precheck_sibling_blast_radius_honest_verdict_red.sh
# =============================================================================
#
# Regression guard for a T085 Round 3 independent-review finding on
# review/lib/precheck_pack_run.py's check_sibling_search() and
# check_blast_radius() (contracts/review-batch-and-precheck.md RB-002,
# data-model.md #10.3 PreCheckReport): "The pack reported its
# sibling-search check as PASS while unmeasured, which is how this
# slipped through" -- an 11.4.201(6) false-null. Both checks used to
# HARDCODE `"verdict": "PASS"` regardless of whether the ReviewBatch's
# own first-slice context_pack genuinely carried a sibling_search_ref /
# blast_radius field, so a batch with neither field present still
# reported all_pass=true -- a genuinely unmeasured sibling-search /
# blast-radius silently satisfied the "all_pass == true" precondition
# every review-dispatch consumer of this tool relies on to mean
# "genuinely checked", not "silently skipped".
#
# Fix (same change this test file lands in): the verdict now tracks
# FIELD PRESENCE -- PASS only when context_pack genuinely carries the
# field (any non-None value, INCLUDING a hand-authored fixture whose
# real declared value literally happens to be the string "UNMEASURED" --
# that is still real data the batch supplied, not this tool's own
# fallback); FAIL only when the field is genuinely absent from every
# slice and precheck_pack_run.py had to manufacture the "UNMEASURED"
# evidence literal itself.
#
# Section A -- the RED case: a batch with NEITHER field present anywhere
# must report FAIL for both checks and all_pass=false.
# Section B -- the real-value case: a batch carrying genuine field
# values must still report PASS/PASS and all_pass=true.
# Section C -- the false-positive guard (11.4.201(1)): a batch whose
# field IS present but whose hand-authored value happens to literally
# spell "UNMEASURED" (the exact shape test_precheck_pack_build_red.sh's
# own B1/B3/C1 fixtures already use) MUST still PASS -- the fix must
# never over-trigger on real, present, if-oddly-spelled data.
# Section D -- guard-viability (11.4.115(F)): a scratch copy of
# precheck_pack.sh + review/lib/precheck_pack_run.py with JUST this fix
# reverted (hardcoded PASS restored, every other change in the file
# untouched) is run against Section A's exact no-field batch, proving
# this test genuinely catches the pre-fix bug -- never a tautology that
# cannot fail.
#
# Producer != Verifier (11.4.240): this file only tests
# review/lib/precheck_pack_run.py's two checks; it does not implement
# them (the fix lands in the SAME change this file is part of, per house
# precedent -- test_precheck_pack_build_red.sh's own Section B/Section C
# relationship to the scoping fix it guards).
#
# Exit: 0 all as expected; 1 any FAIL recorded.
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
REVIEW_DIR="$FC/review"
PRECHECK="$REVIEW_DIR/precheck_pack.sh"
RUN_PY="$REVIEW_DIR/lib/precheck_pack_run.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok: $1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "== T085 round-3 RED: check_sibling_search / check_blast_radius honest verdict =="

# =============================================================================
# Control needles.
# =============================================================================
if [ -f "$PRECHECK" ]; then
    ok "control needle: $PRECHECK exists"
else
    bad "control needle FAILED: $PRECHECK is absent -- nothing below can run"
fi
if [ -f "$RUN_PY" ]; then
    ok "control needle: $RUN_PY exists"
else
    bad "control needle FAILED: $RUN_PY is absent -- nothing below can run"
fi

mkdir -p "$TMP/clean"
cat >"$TMP/clean/good.sh" <<'EOF'
#!/bin/sh
echo "clean and valid"
EOF

triple() {
    # $1 = precheck.json path. Prints "<all_pass> <sibling-search verdict>
    # <blast-radius verdict>" with no eval() -- plain dict/.get() lookups
    # only, no execution of any dynamically-assembled expression. Prints
    # UNREADABLE on any load failure.
    python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    checks = {c.get("check"): c.get("verdict") for c in d.get("checks", []) if isinstance(c, dict)}
    print("%s %s %s" % (d.get("all_pass"),
                         checks.get("sibling-search", "MISSING"),
                         checks.get("blast-radius", "MISSING")))
except Exception as e:
    print("UNREADABLE %s" % e)
PY
}

# =============================================================================
# Section A -- RED: neither field present anywhere -- must FAIL both
# checks and report all_pass=false.
# =============================================================================
cat >"$TMP/batch_no_fields.json" <<'EOF'
{
  "batch_id": "RB-SIBRAD-A-NOFIELD",
  "changes": ["sha256:00000000000000000000000000000000000000000000000000000000000a01"],
  "related_by": "logic_group:sibrad-fixture-a",
  "total_changed_lines": 1,
  "slices": [
    {
      "slice_id": "S1",
      "lines": 1,
      "context_pack": {
        "intent": "Slice with NO sibling_search_ref and NO blast_radius field anywhere -- the genuinely-absent-field case."
      }
    }
  ]
}
EOF
sh "$PRECHECK" --batch "$TMP/batch_no_fields.json" --clean-checkout "$TMP/clean" \
    --out "$TMP/a_out.json" >"$TMP/a.out" 2>"$TMP/a.err"
A_RC=$?
A_RESULT=$(triple "$TMP/a_out.json")
if [ "$A_RC" -eq 1 ] && [ "$A_RESULT" = "False FAIL FAIL" ]; then
    ok "A: a batch with NEITHER sibling_search_ref NOR blast_radius"
    echo "   anywhere reports all_pass=false with BOTH checks FAIL"
    echo "   (rc=$A_RC) -- an unmeasured signal no longer silently"
    echo "   satisfies all_pass"
else
    bad "A: expected rc=1 / 'False FAIL FAIL', got rc=$A_RC '$A_RESULT'"
    echo "   ($(cat "$TMP/a.err" 2>/dev/null))"
fi

# =============================================================================
# Section B -- real, genuine field values present -- must PASS both
# checks and (on an otherwise-clean batch) report all_pass=true.
# =============================================================================
cat >"$TMP/batch_real_fields.json" <<'EOF'
{
  "batch_id": "RB-SIBRAD-B-REALFIELD",
  "changes": ["sha256:00000000000000000000000000000000000000000000000000000000000b01"],
  "related_by": "logic_group:sibrad-fixture-b",
  "total_changed_lines": 1,
  "slices": [
    {
      "slice_id": "S1",
      "lines": 1,
      "context_pack": {
        "intent": "Slice 1/1 of logic_group:sibrad-fixture-b: 1 change(s) touching clean/good.sh",
        "blast_radius": "1 changed path(s) in this slice: clean/good.sh",
        "sibling_search_ref": "qa-results/fastcycle/sibrad-fixture-b/sibling_search.json"
      }
    }
  ]
}
EOF
sh "$PRECHECK" --batch "$TMP/batch_real_fields.json" --clean-checkout "$TMP/clean" \
    --out "$TMP/b_out.json" >"$TMP/b.out" 2>"$TMP/b.err"
B_RC=$?
B_RESULT=$(triple "$TMP/b_out.json")
if [ "$B_RC" -eq 0 ] && [ "$B_RESULT" = "True PASS PASS" ]; then
    ok "B: a batch carrying real, non-empty sibling_search_ref AND"
    echo "   blast_radius values reports all_pass=true with BOTH checks"
    echo "   PASS (rc=$B_RC) -- the fix never regresses the genuine case"
else
    bad "B: expected rc=0 / 'True PASS PASS', got rc=$B_RC '$B_RESULT'"
    echo "   ($(cat "$TMP/b.err" 2>/dev/null))"
fi

# =============================================================================
# Section C -- false-positive guard (11.4.201(1)): a field that IS
# present, whose real declared value happens to literally spell the word
# "UNMEASURED" (the exact shape test_precheck_pack_build_red.sh's own
# B1/B3/C1 fixtures already use for sibling_search_ref), MUST still PASS
# -- the fix keys off FIELD PRESENCE, never off the evidence string.
# =============================================================================
cat >"$TMP/batch_literal_unmeasured.json" <<'EOF'
{
  "batch_id": "RB-SIBRAD-C-LITERALSTR",
  "changes": ["sha256:00000000000000000000000000000000000000000000000000000000000c01"],
  "related_by": "logic_group:sibrad-fixture-c",
  "total_changed_lines": 1,
  "slices": [
    {
      "slice_id": "S1",
      "lines": 1,
      "context_pack": {
        "intent": "Slice 1/1 of logic_group:sibrad-fixture-c: 1 change(s) touching clean/good.sh",
        "blast_radius": "1 changed path(s) in this slice: clean/good.sh",
        "sibling_search_ref": "UNMEASURED"
      }
    }
  ]
}
EOF
sh "$PRECHECK" --batch "$TMP/batch_literal_unmeasured.json" --clean-checkout "$TMP/clean" \
    --out "$TMP/c_out.json" >"$TMP/c.out" 2>"$TMP/c.err"
C_RC=$?
C_RESULT=$(triple "$TMP/c_out.json")
if [ "$C_RC" -eq 0 ] && [ "$C_RESULT" = "True PASS PASS" ]; then
    ok "C: a batch whose sibling_search_ref field IS present but whose"
    echo "   real, hand-authored value literally spells 'UNMEASURED'"
    echo "   (the same shape test_precheck_pack_build_red.sh's own"
    echo "   B1/B3/C1 fixtures use) still reports all_pass=true -- the"
    echo "   fix keys off FIELD PRESENCE, never off the evidence string,"
    echo "   so it never false-positives on real, present, oddly-spelled"
    echo "   data (rc=$C_RC)"
else
    bad "C: expected rc=0 / 'True PASS PASS', got rc=$C_RC '$C_RESULT'"
    echo "   ($(cat "$TMP/c.err" 2>/dev/null))"
fi

# =============================================================================
# Section D -- guard-viability (11.4.115(F)): revert JUST this fix on a
# scratch copy and prove Section A's exact batch now WRONGLY passes --
# this test genuinely catches the pre-fix bug, it is not a tautology.
# =============================================================================
SCRATCH="$TMP/scratch_mutated"
mkdir -p "$SCRATCH/lib"
cp "$PRECHECK" "$SCRATCH/precheck_pack.sh"
cp "$RUN_PY" "$SCRATCH/lib/precheck_pack_run.py"

python3 - "$SCRATCH/lib/precheck_pack_run.py" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()

old_sib = (
    'def check_sibling_search(batch):\n'
    '    # T085 round-3 fix: verdict tracks FIELD PRESENCE (11.4.201(6) false-null\n'
    '    # fix), never a hardcoded PASS -- see module docstring\'s per-check\n'
    '    # breakdown for the full rationale. A genuinely-absent field (ref is\n'
    '    # None) is honestly FAIL; a present field -- even one whose real value\n'
    '    # happens to be the literal string "UNMEASURED" (a hand-authored\n'
    '    # fixture\'s own real data, not this tool\'s fallback) -- is PASS.\n'
    '    ref = _first_slice_field(batch, "sibling_search_ref")\n'
    '    verdict = "PASS" if ref is not None else "FAIL"\n'
    '    return {"check": "sibling-search", "verdict": verdict,\n'
    '            "evidence": {"ref": ref if ref is not None else "UNMEASURED"}}\n'
)
new_sib = (
    'def check_sibling_search(batch):\n'
    '    # GUARD-VIABILITY MUTATION: T085 round-3 fix reverted -- hardcoded PASS restored\n'
    '    ref = _first_slice_field(batch, "sibling_search_ref")\n'
    '    return {"check": "sibling-search", "verdict": "PASS",\n'
    '            "evidence": {"ref": ref if ref is not None else "UNMEASURED"}}\n'
)
if c.count(old_sib) != 1:
    sys.exit("mutate: check_sibling_search source did not match exactly once (count=%d)" % c.count(old_sib))
c = c.replace(old_sib, new_sib, 1)

old_blast = (
    'def check_blast_radius(batch):\n'
    '    # See check_sibling_search()\'s comment -- identical fix, same rationale.\n'
    '    scope = _first_slice_field(batch, "blast_radius")\n'
    '    verdict = "PASS" if scope is not None else "FAIL"\n'
    '    return {"check": "blast-radius", "verdict": verdict,\n'
    '            "evidence": {"scope": scope if scope is not None else "UNMEASURED"}}\n'
)
new_blast = (
    'def check_blast_radius(batch):\n'
    '    # GUARD-VIABILITY MUTATION: T085 round-3 fix reverted -- hardcoded PASS restored\n'
    '    scope = _first_slice_field(batch, "blast_radius")\n'
    '    return {"check": "blast-radius", "verdict": "PASS",\n'
    '            "evidence": {"scope": scope if scope is not None else "UNMEASURED"}}\n'
)
if c.count(old_blast) != 1:
    sys.exit("mutate: check_blast_radius source did not match exactly once (count=%d)" % c.count(old_blast))
c = c.replace(old_blast, new_blast, 1)

with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
MUTATE_RC=$?

if [ "$MUTATE_RC" -ne 0 ]; then
    bad "D setup: could not apply the revert-mutation to the scratch copy"
    echo "   (rc=$MUTATE_RC) -- the fix's exact source shape must have"
    echo "   changed; this guard needs updating to match"
else
    ok "D setup: scratch copy mutated -- JUST the two verdict-presence"
    echo "   fixes reverted to hardcoded PASS, every other line untouched"

    sh "$SCRATCH/precheck_pack.sh" --batch "$TMP/batch_no_fields.json" \
        --clean-checkout "$TMP/clean" --out "$TMP/d_out.json" \
        >"$TMP/d.out" 2>"$TMP/d.err"
    D_RC=$?
    D_RESULT=$(triple "$TMP/d_out.json")
    if [ "$D_RC" -eq 0 ] && [ "$D_RESULT" = "True PASS PASS" ]; then
        ok "D: with JUST this fix reverted, Section A's exact no-field"
        echo "   batch WRONGLY reports all_pass=true again (rc=$D_RC,"
        echo "   '$D_RESULT') -- proving this test genuinely catches the"
        echo "   pre-fix bug, it is not a tautology that can never fail"
    else
        bad "D: expected the REVERTED copy to wrongly report rc=0 /"
        echo "   'True PASS PASS' (reproducing the pre-fix bug), got"
        echo "   rc=$D_RC '$D_RESULT' -- either the mutation did not"
        echo "   genuinely revert the fix, or the fix is not what this"
        echo "   guard thinks it is"
    fi
fi

echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ]
