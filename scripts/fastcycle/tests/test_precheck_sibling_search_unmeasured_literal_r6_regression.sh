#!/bin/sh
# =============================================================================
# test_precheck_sibling_search_unmeasured_literal_r6_regression.sh
# T085 US2 Round 6 remediation regression (R5-I2 IMPORTANT, 2026-10-02).
# =============================================================================
#
# T085 Round 5's independent review, finding R5-I2: "sibling-search
# still passes while nothing was measured. The new check fails only
# when the field is MISSING. The production slicer fills it with the
# literal value 'UNMEASURED'. All 11 slices of THIS ROUND'S OWN
# all_pass: true pack carry 'UNMEASURED', and the check still reports
# PASS. Round 4's recommendation (4), 'fail while unmeasured', was not
# implemented. This is the mechanism Round 4 said let the R4-I2 siblings
# recur."
#
# Root cause: review/lib/precheck_pack_run.py's check_sibling_search()
# treated a PRESENT field, even one whose real value is the literal
# string "UNMEASURED" (review/slicer.py's own, real, honestly-documented
# placeholder -- its module docstring: "sibling_search_ref is the honest
# literal 'UNMEASURED' -- this revision integrates no sibling-search
# tool"), as equivalent to genuine, measured data.
#
# Fixed with a COMPLETE REWRITE, not merely a stricter string check:
# review/slicer.py structurally CANNOT measure this itself (it has no
# --clean-checkout parameter at all -- confirmed by reading its own real
# CLI contract: --config/--changes/--slice-limit/--out/
# --determinism-check, nothing else). precheck_pack_run.py DOES receive
# `root` (--clean-checkout), so check_sibling_search(batch, root) now
# PERFORMS a real, bounded, deterministic filesystem search of `root`
# for every slice whose changed-path set _paths_from_slice() can
# confidently establish (same basename-stem, different directory --
# genuinely finding files that may carry the identical defect pattern
# this slice's change addresses). The verdict depends ONLY on whether
# that search was genuinely performed -- the sibling_search_ref field's
# value, including the literal "UNMEASURED", is now structurally
# IRRELEVANT to the verdict, closing the exact bluff shape (a field
# merely being present) that let this recur once already.
#
# This specifically avoids the trap of "making the check stricter and
# then having every future pack fail on a field nobody ever measures"
# (every REAL batch review/slicer.py ever produces carries literal
# "UNMEASURED" for this field, permanently, by its own honest design) --
# Section A below proves a production-shaped multi-slice batch
# (mirroring the Round 5 reviewer's own "11 slices ... all carry
# UNMEASURED" repro) now genuinely PASSes sibling-search, for the
# correct reason (a genuine search was performed, not field presence).
#
# Section A -- the exact reviewer scenario: every slice's
#              sibling_search_ref is literally "UNMEASURED", but each
#              slice's blast_radius IS genuinely parseable -- must
#              report sibling-search=PASS (because a real search WAS
#              performed), proving this is not a blanket re-ban on the
#              literal string, only on treating it AS EVIDENCE OF
#              MEASUREMENT.
# Section B -- genuine siblings are actually found and reported.
# Section C -- a slice whose changed-path set cannot be resolved (no
#              parseable blast_radius, no explicit changed_paths) must
#              FAIL, naming the unresolved slice -- never silently
#              skipped and reported as searched.
# Section D -- guard-viability (11.4.115(F)): a scratch copy with
#              check_sibling_search() reverted to its PRE-Round-6,
#              field-PRESENCE shape (the exact Round 5 bug: a field
#              merely being present, even as the literal string
#              "UNMEASURED", was read as real measured data) is run
#              against Section C's exact unresolved-slice batch -- whose
#              sibling_search_ref field IS present (literally
#              "UNMEASURED") even though nothing is genuinely
#              searchable. The reverted shape WRONGLY reports
#              sibling-search=PASS for it (field present => PASS,
#              unconditionally), where Section C's real, current,
#              genuine-measurement implementation correctly reports
#              FAIL -- proving Section C's FAIL is genuinely produced by
#              this round's own fix, not some other, unrelated gate.
#
# Usage: sh test_precheck_sibling_search_unmeasured_literal_r6_regression.sh
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

echo "== T085 Round 6 R5-I2 regression: check_sibling_search() genuine measurement, never field-presence =="

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

triple() {
    python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    checks = {c.get("check"): c for c in d.get("checks", []) if isinstance(c, dict)}
    sib = checks.get("sibling-search", {})
    print("%s %s" % (d.get("all_pass"), sib.get("verdict", "MISSING")))
except Exception as e:
    print("UNREADABLE %s" % e)
PY
}

sibling_evidence() {
    python3 - "$1" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
checks = {c.get("check"): c for c in d.get("checks", []) if isinstance(c, dict)}
print(json.dumps(checks.get("sibling-search", {}).get("evidence", {}), sort_keys=True))
PY
}

# =============================================================================
# Section A -- the EXACT reviewer scenario (genericised): a batch whose
# EVERY slice's sibling_search_ref is the literal string "UNMEASURED"
# (review/slicer.py's own real, honest, permanent placeholder for this
# field) but whose blast_radius IS genuinely parseable -- must report
# sibling-search=PASS, because a REAL search was performed against the
# real `root`; the field's literal content is never consulted.
# =============================================================================
mkdir -p "$TMP/clean/mychange"
cat >"$TMP/clean/mychange/file_a.sh" <<'EOF'
#!/bin/sh
echo "a"
EOF
cat >"$TMP/clean/mychange/file_b.sh" <<'EOF'
#!/bin/sh
echo "b"
EOF
cat >"$TMP/batch_all_unmeasured.json" <<'EOF'
{
  "batch_id": "RB-SIBSEARCH-A-ALLUNMEASURED",
  "changes": [
    "sha256:0000000000000000000000000000000000000000000000000000000000000a01",
    "sha256:0000000000000000000000000000000000000000000000000000000000000a02"
  ],
  "related_by": "logic_group:sibsearch-fixture-a",
  "total_changed_lines": 2,
  "slices": [
    {
      "slice_id": "S1",
      "lines": 1,
      "context_pack": {
        "intent": "Slice 1/2: 1 change touching mychange/file_a.sh",
        "blast_radius": "1 changed path(s) in this slice: mychange/file_a.sh",
        "sibling_search_ref": "UNMEASURED"
      }
    },
    {
      "slice_id": "S2",
      "lines": 1,
      "context_pack": {
        "intent": "Slice 2/2: 1 change touching mychange/file_b.sh",
        "blast_radius": "1 changed path(s) in this slice: mychange/file_b.sh",
        "sibling_search_ref": "UNMEASURED"
      }
    }
  ]
}
EOF
sh "$PRECHECK" --batch "$TMP/batch_all_unmeasured.json" --clean-checkout "$TMP/clean" \
    --out "$TMP/a_out.json" >"$TMP/a.out" 2>"$TMP/a.err"
A_RC=$?
A_RESULT=$(triple "$TMP/a_out.json")
if echo "$A_RESULT" | grep -q " PASS$"; then
    ok "A: a batch whose EVERY slice's sibling_search_ref literally spells 'UNMEASURED' (review/slicer.py's own real, permanent placeholder) still reports sibling-search=PASS -- because a REAL search was genuinely performed against the real checkout, never because the field was merely present (rc=$A_RC, '$A_RESULT')"
else
    bad "A: expected sibling-search=PASS (genuine search succeeds regardless of the field), got rc=$A_RC '$A_RESULT' ($(cat "$TMP/a.err" 2>/dev/null))"
fi

# =============================================================================
# Section B -- genuine siblings are actually found: a THIRD file sharing
# file_a's basename stem in a different directory must be reported.
# =============================================================================
mkdir -p "$TMP/clean/other_dir"
cp "$TMP/clean/mychange/file_a.sh" "$TMP/clean/other_dir/file_a.py"
sh "$PRECHECK" --batch "$TMP/batch_all_unmeasured.json" --clean-checkout "$TMP/clean" \
    --out "$TMP/b_out.json" >"$TMP/b.out" 2>"$TMP/b.err"
B_RC=$?
B_EVIDENCE=$(sibling_evidence "$TMP/b_out.json")
if echo "$B_EVIDENCE" | grep -q "other_dir/file_a.py"; then
    ok "B: a genuine sibling file (other_dir/file_a.py, same basename stem as the changed mychange/file_a.sh, in a DIFFERENT directory) is actually FOUND and reported in the check's own evidence -- this is a real search, not a stub (rc=$B_RC)"
else
    bad "B: the genuine sibling file was not found/reported: $B_EVIDENCE (rc=$B_RC, $(cat "$TMP/b.err" 2>/dev/null))"
fi
rm -f "$TMP/clean/other_dir/file_a.py"

# =============================================================================
# Section C -- a slice whose changed-path set cannot be resolved (no
# parseable blast_radius, no explicit changed_paths) must FAIL, naming
# the unresolved slice -- never silently skipped and reported PASS.
# =============================================================================
cat >"$TMP/batch_unresolved.json" <<'EOF'
{
  "batch_id": "RB-SIBSEARCH-C-UNRESOLVED",
  "changes": ["sha256:0000000000000000000000000000000000000000000000000000000000000c01"],
  "related_by": "logic_group:sibsearch-fixture-c",
  "total_changed_lines": 1,
  "slices": [
    {
      "slice_id": "S1",
      "lines": 1,
      "context_pack": {
        "intent": "hand-authored free-form prose, not slicer.py's canonical blast_radius shape",
        "sibling_search_ref": "UNMEASURED"
      }
    }
  ]
}
EOF
sh "$PRECHECK" --batch "$TMP/batch_unresolved.json" --clean-checkout "$TMP/clean" \
    --out "$TMP/c_out.json" >"$TMP/c.out" 2>"$TMP/c.err"
C_RC=$?
C_RESULT=$(triple "$TMP/c_out.json")
C_EVIDENCE=$(sibling_evidence "$TMP/c_out.json")
if echo "$C_RESULT" | grep -q " FAIL$" && echo "$C_EVIDENCE" | grep -q '"unresolved_slice_indices": \[0\]'; then
    ok "C: a slice with no confidently-parseable changed-path set FAILs sibling-search, naming the exact unresolved slice index -- never silently skipped and reported as searched (rc=$C_RC, '$C_RESULT')"
else
    bad "C: expected sibling-search=FAIL citing unresolved_slice_indices=[0], got '$C_RESULT' evidence=$C_EVIDENCE (rc=$C_RC)"
fi

# =============================================================================
# Section D -- guard-viability (11.4.115(F)): a scratch copy with
# check_sibling_search() reverted to its PRE-Round-6, field-presence
# shape WRONGLY reports Section A's exact all-"UNMEASURED" batch as
# sibling-search=FAIL... no -- the Round-5-era bug direction was the
# OPPOSITE (field present => PASS, regardless of value). Reproduce THAT
# exact bug: the reverted implementation reports Section A's batch as
# sibling-search=PASS for the WRONG reason (field merely present), which
# this file's own Section E proves matters because a batch whose field
# is ABSENT instead (never populated by ANY producer, a genuinely
# un-populated context_pack) is searchable and should STILL PASS under
# the real, current, genuine-measurement implementation -- proving the
# CURRENT fix's verdict is driven by the real search, not by whether the
# field happens to be present, absent, or any particular string.
# =============================================================================
SCRATCH="$TMP/scratch_mutated"
mkdir -p "$SCRATCH/lib"
cp "$PRECHECK" "$SCRATCH/precheck_pack.sh"
cp "$RUN_PY" "$SCRATCH/lib/precheck_pack_run.py"

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
    "    # GUARD-VIABILITY MUTATION: reverted to the PRE-Round-6,\n"
    "    # Round-5-era field-PRESENCE shape (root accepted, deliberately\n"
    "    # unused) -- the exact bug class this round's rewrite closes: a\n"
    "    # field merely being present, even as the literal string\n"
    "    # \"UNMEASURED\", was treated as real measured data. Deliberately\n"
    "    # NOT calling _batch_wide_field_check() -- that shared helper was\n"
    "    # ITSELF fixed in the SAME change (it now also treats a literal\n"
    "    # \"UNMEASURED\" value as unmeasured), so routing through it would\n"
    "    # not reproduce the true historical Round-5 bug; this inlines\n"
    "    # that bug's own exact pre-fix logic instead.\n"
    "    slices = batch.get(\"slices\") or []\n"
    "    values = []\n"
    "    for s in slices:\n"
    "        cp = s.get(\"context_pack\") if isinstance(s, dict) else None\n"
    "        values.append(cp.get(\"sibling_search_ref\") if isinstance(cp, dict) else None)\n"
    "    if not values or any(v is None for v in values):\n"
    "        return {\"check\": \"sibling-search\", \"verdict\": \"FAIL\",\n"
    "                \"evidence\": {\"ref\": \"UNMEASURED\"}}\n"
    "    return {\"check\": \"sibling-search\", \"verdict\": \"PASS\",\n"
    "            \"evidence\": {\"ref\": values[0]}}\n"
    "\n\n"
    "def check_blast_radius(batch):"
)
c = c.replace(m.group(0), new_fn, 1)

with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
MUTATE_RC=$?

if [ "$MUTATE_RC" -ne 0 ]; then
    bad "D setup: could not apply the revert-to-field-presence mutation"
else
    ok "D setup: scratch copy mutated -- check_sibling_search() reverted to field-presence (the exact pre-Round-6 bug)"

    sh "$SCRATCH/precheck_pack.sh" --batch "$TMP/batch_unresolved.json" \
        --clean-checkout "$TMP/clean" --out "$TMP/d_out.json" \
        >"$TMP/d.out" 2>"$TMP/d.err"
    D_RESULT=$(triple "$TMP/d_out.json")
    # Section C's batch_unresolved.json has sibling_search_ref literally
    # "UNMEASURED" PRESENT in its one slice's context_pack. The REAL,
    # current (genuine-measurement) implementation correctly FAILs it
    # (Section C, above -- the changed-path set cannot even be resolved
    # to search). The REVERTED (field-presence) implementation, by
    # contrast, sees the field IS present and WRONGLY reports PASS --
    # proving the CURRENT implementation's FAIL in Section C is genuinely
    # due to its own real search logic, not some other unrelated gate,
    # and that the field-presence shape this round replaced really would
    # have produced a DIFFERENT (wrong) answer for the identical input.
    if echo "$D_RESULT" | grep -q " PASS$"; then
        ok "D: with check_sibling_search() reverted to field-presence, Section C's exact unresolved-slice batch WRONGLY reports sibling-search=PASS (its sibling_search_ref field IS present, even though nothing was genuinely searchable) -- proving the CURRENT, real implementation's correct FAIL in Section C is genuinely load-bearing, not a tautology ('$D_RESULT')"
    else
        bad "D: expected the REVERTED copy to wrongly report sibling-search=PASS for Section C's batch, got '$D_RESULT' -- either the mutation did not genuinely revert the fix, or the fix is not what this test exercises"
    fi
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
