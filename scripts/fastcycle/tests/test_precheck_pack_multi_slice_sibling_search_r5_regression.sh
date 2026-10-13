#!/bin/sh
# =============================================================================
# T085 US2 Round 5 remediation regression (Process finding #5, 2026-10-02).
# =============================================================================
#
# T085 Round 4's independent review, Process finding #5: "the pre-check
# pack's sibling-search check still reports PASS while unmeasured (Round
# 3 recommendation (2) not done -- this is how R4-I2's siblings
# recurred)."
#
# Reproduced: review/lib/precheck_pack_run.py's check_sibling_search()/
# check_blast_radius() (fixed once, T085 Round 3 commit 9313143, for the
# single-slice "hardcoded PASS regardless of presence" bug) read field
# presence via _first_slice_field() -- which samples ONLY THE FIRST
# slice that happens to carry the field, saying NOTHING about every
# OTHER slice. A multi-slice ReviewBatch (the realistic shape for
# anything beyond a trivial one-file change) where slice 0 carries
# `sibling_search_ref`/`blast_radius` and a LATER slice does not still
# reports the WHOLE batch's check as PASS -- the later slice was NEVER
# measured, yet the batch-wide verdict claims it was: the IDENTICAL
# "unmeasured but claims PASS" class of 11.4.201(6) false-null the
# Round 3 fix was meant to close everywhere, recurring via a different
# mechanism (first-slice-only sampling instead of a hardcoded constant).
#
# Fixed with _batch_wide_field_check() (section 11.4.227): PASS now
# requires EVERY slice to genuinely carry the field; a batch with zero
# slices is likewise FAIL (nothing was measured); any single missing
# slice makes the WHOLE batch-wide check FAIL, citing exactly which
# slice indices were never measured.
#
# §11.4.199: every check is a real invocation of the real tool
# (precheck_pack.sh, the real CLI entry point), never a bare unit-level
# function call standing in for it.
#
# Usage: sh test_precheck_pack_multi_slice_sibling_search_r5_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
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

echo "== T085 Round 5 Process#5 regression: precheck_pack multi-slice sibling-search/blast-radius coverage =="

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/clean"
cat >"$TMP/clean/good.sh" <<'EOF'
#!/bin/sh
echo "clean and valid"
EOF

triple() {
    python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    checks = {c.get("check"): c for c in d.get("checks", []) if isinstance(c, dict)}
    sib = checks.get("sibling-search", {})
    bla = checks.get("blast-radius", {})
    print("%s %s %s" % (d.get("all_pass"), sib.get("verdict", "MISSING"), bla.get("verdict", "MISSING")))
except Exception as e:
    print("UNREADABLE %s" % e)
PY
}

# =============================================================================
# Section A (the recurrence repro): a 2-slice batch where slice 0 carries
# BOTH fields genuinely, and slice 1 carries NEITHER -- must FAIL both
# checks and report all_pass=false (slice 1 was never measured).
# =============================================================================
cat >"$TMP/batch_multi_slice_gap.json" <<'EOF'
{
  "batch_id": "RB-MULTISLICE-GAP",
  "changes": [
    "sha256:0000000000000000000000000000000000000000000000000000000000000a01",
    "sha256:0000000000000000000000000000000000000000000000000000000000000a02"
  ],
  "related_by": "logic_group:multislice-fixture",
  "total_changed_lines": 2,
  "slices": [
    {
      "paths": ["mychange/file_a.sh"],
      "context_pack": {
        "intent": "slice 0 -- genuinely measured",
        "blast_radius": "1 changed path(s) in this slice: mychange/file_a.sh",
        "sibling_search_ref": "grep -rn pattern -- found 0 siblings"
      }
    },
    {
      "paths": ["mychange/file_b.sh"],
      "context_pack": {
        "intent": "slice 1 -- NEVER measured (neither field present)"
      }
    }
  ]
}
EOF

sh "$PRECHECK" --batch "$TMP/batch_multi_slice_gap.json" --clean-checkout "$TMP/clean" \
    --out "$TMP/a_out.json" >"$TMP/a.out" 2>"$TMP/a.err"
A_RC=$?
A_RESULT=$(triple "$TMP/a_out.json")
if [ "$A_RC" -eq 1 ] && [ "$A_RESULT" = "False FAIL FAIL" ]; then
    ok "A (recurrence repro): a 2-slice batch where slice 1 was never measured correctly reports all_pass=false with BOTH checks FAIL -- the batch-wide gap is caught, not hidden behind slice 0's genuine data"
else
    bad "A (recurrence repro) FAILED: expected 'False FAIL FAIL' (rc=1), got rc=$A_RC '$A_RESULT'"
    echo "   ($(cat "$TMP/a.err" 2>/dev/null))"
fi

# T085 Round 6 (R5-I2): check_sibling_search() was REWRITTEN to
# genuinely MEASURE (search `root`) rather than read a declared field --
# its own evidence key for "this slice could not even be resolved" is
# now `unresolved_slice_indices` (a DIFFERENT, more precise concept:
# "there was nothing parseable to search for", distinct from
# check_blast_radius()'s still-field-reading `unmeasured_slice_indices`,
# renamed from `missing_slice_indices` at the same round to also cover a
# PRESENT-but-literally-"UNMEASURED" value, never only a genuinely
# absent key -- see _batch_wide_field_check()'s own docstring).
if python3 -c "
import json
d = json.load(open('$TMP/a_out.json'))
checks = {c['check']: c for c in d['checks']}
assert checks['sibling-search']['evidence'].get('unresolved_slice_indices') == [1]
assert checks['blast-radius']['evidence'].get('unmeasured_slice_indices') == [1]
" 2>/dev/null; then
    ok "A2: the FAIL evidence names the EXACT unmeasured/unresolved slice index (1), not merely a bare FAIL verdict -- an actionable, pinpoint finding (section 11.4.4)"
else
    bad "A2: the FAIL evidence did not cite the specific unmeasured/unresolved slice index"
fi

# =============================================================================
# Section B (negative control): a 2-slice batch where BOTH slices
# genuinely carry both fields -- must PASS both checks, proving the fix
# does not over-reject a genuinely fully-measured multi-slice batch.
# =============================================================================
cat >"$TMP/batch_multi_slice_ok.json" <<'EOF'
{
  "batch_id": "RB-MULTISLICE-OK",
  "changes": [
    "sha256:0000000000000000000000000000000000000000000000000000000000000b01",
    "sha256:0000000000000000000000000000000000000000000000000000000000000b02"
  ],
  "related_by": "logic_group:multislice-ok-fixture",
  "total_changed_lines": 2,
  "slices": [
    {
      "paths": ["mychange/file_a.sh"],
      "context_pack": {
        "intent": "slice 0 -- genuinely measured",
        "blast_radius": "1 changed path(s) in this slice: mychange/file_a.sh",
        "sibling_search_ref": "grep -rn pattern -- found 0 siblings (slice 0)"
      }
    },
    {
      "paths": ["mychange/file_b.sh"],
      "context_pack": {
        "intent": "slice 1 -- ALSO genuinely measured",
        "blast_radius": "1 changed path(s) in this slice: mychange/file_b.sh",
        "sibling_search_ref": "grep -rn pattern -- found 0 siblings (slice 1)"
      }
    }
  ]
}
EOF

sh "$PRECHECK" --batch "$TMP/batch_multi_slice_ok.json" --clean-checkout "$TMP/clean" \
    --out "$TMP/b_out.json" >"$TMP/b.out" 2>"$TMP/b.err"
B_RC=$?
B_RESULT=$(triple "$TMP/b_out.json")
if [ "$B_RC" -eq 0 ] && [ "$B_RESULT" = "True PASS PASS" ]; then
    ok "B (negative control): a 2-slice batch where BOTH slices are genuinely measured correctly reports all_pass=true -- the fix does not over-reject a fully-measured multi-slice batch"
else
    bad "B (negative control) FAILED: expected 'True PASS PASS' (rc=0), got rc=$B_RC '$B_RESULT'"
    echo "   ($(cat "$TMP/b.err" 2>/dev/null))"
fi

# =============================================================================
# Section C (guard-viability, 11.4.115(F)): a scratch copy with JUST the
# batch-wide check reverted to first-slice-only sampling must WRONGLY
# report Section A's exact gap batch as all_pass=true -- proving this
# test genuinely catches the recurrence, not a tautology.
# =============================================================================
SCRATCH="$TMP/scratch_mutated"
mkdir -p "$SCRATCH/lib"
cp "$PRECHECK" "$SCRATCH/precheck_pack.sh"
cp "$RUN_PY" "$SCRATCH/lib/precheck_pack_run.py"

# T085 Round 6 (R5-I2): check_sibling_search() was REWRITTEN from a
# field-reading check into a genuine-measurement one that is INHERENTLY
# multi-slice-aware (it iterates every slice by construction). The
# meaningful guard-viability mutation for THIS file's own question
# ("is multi-slice coverage genuinely load-bearing for sibling-search")
# is therefore the ORIGINAL Round-3/4-era bug this file was written
# against: first-slice-ONLY sampling via _first_slice_field() (which
# remains present in precheck_pack_run.py, unused by production code,
# specifically so this class of mutation stays constructible) -- NOT a
# revert to the Round-5 multi-slice-aware _batch_wide_field_check(),
# which would NOT reproduce this bug (it already checks every slice).
python3 - "$SCRATCH/lib/precheck_pack_run.py" <<'PYEOF'
import re, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()

m = re.search(
    r"\ndef check_sibling_search\(batch, root\):.*?\n\n\ndef check_blast_radius\(batch\):",
    c, re.DOTALL,
)
if m is None:
    sys.exit("mutate: check_sibling_search function body not found (source shape changed)")
if c.count(m.group(0)) != 1:
    sys.exit("mutate: check_sibling_search function body did not match exactly once (count=%d)" % c.count(m.group(0)))

new_fn = (
    "\ndef check_sibling_search(batch, root):\n"
    "    # GUARD-VIABILITY MUTATION: reverted to the ORIGINAL Round-3/4-era\n"
    "    # bug -- first-slice-ONLY sampling via _first_slice_field() (root\n"
    "    # accepted per the real call site's signature, deliberately unused).\n"
    "    ref = _first_slice_field(batch, \"sibling_search_ref\")\n"
    "    return {\"check\": \"sibling-search\", \"verdict\": \"PASS\" if ref is not None else \"FAIL\",\n"
    "            \"evidence\": {\"ref\": ref if ref is not None else \"UNMEASURED\"}}\n"
    "\n\n"
    "def check_blast_radius(batch):"
)
c = c.replace(m.group(0), new_fn, 1)

with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
MUTATE_RC=$?

if [ "$MUTATE_RC" -ne 0 ]; then
    bad "C setup: could not apply the revert-to-first-slice-only mutation"
else
    ok "C setup: scratch copy mutated -- check_sibling_search reverted to first-slice-only sampling (the exact pre-fix bug)"
    sh "$SCRATCH/precheck_pack.sh" --batch "$TMP/batch_multi_slice_gap.json" \
        --clean-checkout "$TMP/clean" --out "$TMP/c_out.json" \
        >"$TMP/c.out" 2>"$TMP/c.err"
    C_RESULT=$(triple "$TMP/c_out.json")
    # Only check_sibling_search() was reverted (check_blast_radius() is
    # untouched and still correctly FAILs on the same slice-1 gap, so
    # all_pass correctly stays false even under this partial mutation --
    # this assertion targets the ONE reverted check specifically, proving
    # IT was genuinely load-bearing, independent of the other check's own
    # (separately, already-proven-load-bearing) guard.
    if echo "$C_RESULT" | awk '{print $2}' | grep -q "^PASS$"; then
        ok "C: with check_sibling_search() reverted to first-slice-only sampling, Section A's exact 2-slice gap batch WRONGLY reports sibling-search=PASS again (full result: '$C_RESULT') -- proving this test genuinely catches the recurrence, it is not a tautology"
    else
        bad "C: expected the REVERTED copy to wrongly report sibling-search=PASS, got '$C_RESULT' -- either the mutation did not genuinely revert the fix, or the fix is not what this test exercises"
    fi
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
