#!/bin/sh
# =============================================================================
# Constitution 11.4.235(D) FINDING-LAYER CLASSIFIER -- RED test for
# review_record.py's new optional per-finding `finding_layer` field
# (closed set source-defect | test-instrumentation | process-doc), added
# 2026-10-03 per the just-landed clause.
# =============================================================================
#
# Purpose: pin the per-finding `finding_layer` field's full behaviour --
#          valid-value accept + round-trip, closed-set rejection, additive
#          absent-is-unaffected, independence from the pre-existing
#          `class` axis, and backfill parity. Test-first discipline was
#          proven on this file: it ran RED on 2026-10-03 against the
#          then-unpatched review_record.py (every assertion below unmet,
#          the field did not exist), then GREEN once implemented. This
#          revision additionally adds the B1-remediation cases (tests
#          8-17 below: wrong-case/underscore near-misses, empty-string
#          and falsy-non-string values, explicit-null round-trip) added
#          after an independent review found the original suite did not
#          exercise them; each new case was itself confirmed RED against
#          the reviewer's own two proposed mutations before being trusted
#          GREEN against the unmutated tool (see the mutation-proof notes
#          this round's commit/report cites).
#
# This field is DISTINCT from review_record.py's PRE-EXISTING `class`
# field (T-A04 closed set mechanical|judgment|false-positive, see
# classify_finding() in review/review_record.py) -- a different axis
# entirely. Tests 5/6 below prove the two are independent: setting one
# must never move the other.
#
# Mechanism (this tool's own existing calling convention, constitution
# 11.4.18): review_record.py has NO per-finding CLI flags today --
# severity/rule/file/line all arrive embedded in each finding object
# inside --verdict-file's "findings" array (record) or --input's
# "findings" array (backfill). The natural, convention-matching way for
# a reviewer to "set finding_layer when recording a finding" is
# therefore the SAME mechanism: an optional "finding_layer" key on the
# raw finding object, read/validated/copied into the output record's
# finding entry.
#
# Backward compatibility (the load-bearing half): `tests/fixtures/
# review_record_finding_layer/pre_existing_real_record.json` is a REAL
# ReviewVerdictRecord produced by actually RUNNING the real, unpatched
# `record` subcommand (captured 2026-10-03, before this field existed)
# against the project's own golden-good fixture -- not a hand-authored
# stand-in. Its one finding carries no "finding_layer" key at all. Test
# 1 below proves this genuine pre-existing file still loads/validates
# via the SAME code path `gate` already uses (_gate_collect_records),
# unedited by this change, exactly as before.
#
# §11.4.199: every check is a real invocation of the real tool.
#
# Usage: sh test_review_record_finding_layer_red.sh
# Exit: 0 all checks held (GREEN against the real, implemented tool); 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/review/review_record.py"
FX="$HERE/fixtures/review_record_finding_layer"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== 11.4.235(D) RED: review_record.py optional per-finding finding_layer =="

SCRATCH=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'rm -rf "$SCRATCH"' EXIT INT TERM
mkdir -p "$SCRATCH/records"

# -----------------------------------------------------------------------
# Fixture self-check: the real pre-existing record fixture exists,
# parses, and genuinely predates the field (no "finding_layer" key on
# its one finding) -- confirms the backward-compat fixture itself is
# honest before relying on it below.
# -----------------------------------------------------------------------
PRE_EXISTING="$FX/pre_existing_real_record.json"
if [ -f "$PRE_EXISTING" ]; then
    ok "fixture self-check: pre_existing_real_record.json exists"
else
    bad "fixture self-check: pre_existing_real_record.json MISSING at $PRE_EXISTING"
fi
HAS_FIELD=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
f1 = doc["findings"][0]
print("1" if "finding_layer" in f1 else "0")
' "$PRE_EXISTING" 2>/dev/null)
if [ "$HAS_FIELD" = "0" ]; then
    ok "fixture self-check: pre-existing record genuinely has NO finding_layer key (predates the field)"
else
    bad "fixture self-check: pre-existing record already carries finding_layer (got '$HAS_FIELD') -- fixture does not test what it claims to"
fi
CHANGE_ID=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
print(doc["change_ids"][0])
' "$PRE_EXISTING" 2>/dev/null)

# =============================================================================
# 1 (BACKWARD COMPATIBILITY, the load-bearing test): the real
#    pre-existing record -- authored before finding_layer existed --
#    MUST still load/validate via the exact same code path `gate` uses
#    (_gate_collect_records), with no parse/required-field error. The
#    record's own verdict is NO-GO, so the correct outcome is a clean
#    UNCOVERED (rc=1) decision -- NOT a BLIND/parse failure (rc=4).
# =============================================================================
echo "-- 1: a REAL pre-existing record (no finding_layer) still loads via gate's own record-collection path --"
cp "$PRE_EXISTING" "$SCRATCH/records/pre_existing.json"
cp "$FX"/*.precheck-evidence "$SCRATCH/records/" 2>/dev/null || true
OUT1=$(python3 "$TOOL" gate --change "$CHANGE_ID" --records "$SCRATCH/records" 2>&1)
RC1=$?
if [ "$RC1" != "4" ] && ! echo "$OUT1" | grep -q "missing required field"; then
    ok "1: pre-existing finding_layer-less record parses cleanly through gate (rc=$RC1, no parse/field error) -- backward compatible"
else
    bad "1 FAILED: pre-existing record triggered a parse/field error (rc=$RC1): $OUT1"
fi
rm -f "$SCRATCH/records/pre_existing.json" "$SCRATCH/records"/*.precheck-evidence

# -----------------------------------------------------------------------
# Shared fresh-call fixture inputs (record subcommand).
# -----------------------------------------------------------------------
mk_batch() {
    cat > "$1" <<EOF
{"batch_id":"BATCH-FL","changes":["CH-FL"],"related_by":"logic_group:fl-fixture","slices":[]}
EOF
}

# =============================================================================
# 2 (valid value accepted + round-trips): a finding carrying a valid
#    "finding_layer" value MUST be accepted (rc=0) and the output
#    record's matching finding MUST carry that exact value.
# =============================================================================
echo "-- 2: a valid finding_layer value is accepted and round-trips verbatim --"
mk_batch "$SCRATCH/batch2.json"
cat > "$SCRATCH/verdict2.json" <<'EOF'
{"round":1,"verdict":"NO-GO","findings":[
  {"id":"F1","severity":"MINOR","finding_layer":"source-defect"}
]}
EOF
OUT2=$(python3 "$TOOL" record --batch "$SCRATCH/batch2.json" --round 1 \
    --verdict-file "$SCRATCH/verdict2.json" --tier opus --effort xhigh \
    --out "$SCRATCH/rev2.json" 2>&1)
RC2=$?
GOT2=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
print(doc["findings"][0].get("finding_layer", "<ABSENT>"))
' "$SCRATCH/rev2.json" 2>/dev/null)
if [ "$RC2" -eq 0 ] && [ "$GOT2" = "source-defect" ]; then
    ok "2: valid finding_layer 'source-defect' accepted (rc=0) and round-trips verbatim into the output record"
else
    bad "2 FAILED: rc=$RC2 got='$GOT2' out='$OUT2'"
fi

# =============================================================================
# 3 (invalid value rejected, clear error, nothing written): a
#    finding_layer outside the closed set MUST be refused with a clear
#    error and MUST NOT write --out.
# =============================================================================
echo "-- 3: an invalid finding_layer value is refused with a clear error, no file written --"
mk_batch "$SCRATCH/batch3.json"
cat > "$SCRATCH/verdict3.json" <<'EOF'
{"round":1,"verdict":"NO-GO","findings":[
  {"id":"F1","severity":"MINOR","finding_layer":"not-a-real-layer"}
]}
EOF
rm -f "$SCRATCH/rev3.json"
OUT3=$(python3 "$TOOL" record --batch "$SCRATCH/batch3.json" --round 1 \
    --verdict-file "$SCRATCH/verdict3.json" --tier opus --effort xhigh \
    --out "$SCRATCH/rev3.json" 2>&1)
RC3=$?
if [ "$RC3" -eq 2 ] && [ ! -f "$SCRATCH/rev3.json" ] && echo "$OUT3" | grep -qi "finding_layer"; then
    ok "3: invalid finding_layer value refused (exit 2), no file written, error names 'finding_layer'"
else
    bad "3 FAILED: rc=$RC3 out='$OUT3' file_exists=$([ -f "$SCRATCH/rev3.json" ] && echo yes || echo no)"
fi

# =============================================================================
# 4 (absent finding_layer on a FRESH call behaves exactly as before): a
#    finding with NO finding_layer key at all must still be accepted,
#    classified normally, and the output finding must carry NO
#    finding_layer key (pure additive behaviour for callers who have not
#    adopted the field yet).
# =============================================================================
echo "-- 4: a fresh finding with no finding_layer key behaves exactly as before (absent in output too) --"
mk_batch "$SCRATCH/batch4.json"
cat > "$SCRATCH/verdict4.json" <<'EOF'
{"round":1,"verdict":"NO-GO","findings":[
  {"id":"F1","severity":"MINOR","rule":"SC2086"}
]}
EOF
OUT4=$(python3 "$TOOL" record --batch "$SCRATCH/batch4.json" --round 1 \
    --verdict-file "$SCRATCH/verdict4.json" --tier opus --effort xhigh \
    --out "$SCRATCH/rev4.json" 2>&1)
RC4=$?
RES4=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
f1 = doc["findings"][0]
print(f1.get("class", "<NOCLASS>") + "|" + ("PRESENT" if "finding_layer" in f1 else "ABSENT"))
' "$SCRATCH/rev4.json" 2>/dev/null)
if [ "$RC4" -eq 0 ] && [ "$RES4" = "mechanical|ABSENT" ]; then
    ok "4: absent finding_layer -- accepted, class still 'mechanical', no finding_layer key emitted (additive, no behaviour change for non-adopters)"
else
    bad "4 FAILED: rc=$RC4 got='$RES4' out='$OUT4'"
fi

# =============================================================================
# 5 (independence A): a finding with ONLY "rule" set (no finding_layer)
#    classifies "class":"mechanical" as always, proving the pre-existing
#    `class` field is unaffected by the new field's absence.
# =============================================================================
echo "-- 5: setting only 'rule' (no finding_layer) leaves 'class' computation unaffected --"
RES5=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
f1 = doc["findings"][0]
print(f1.get("class", "<NOCLASS>"))
' "$SCRATCH/rev4.json" 2>/dev/null)
if [ "$RES5" = "mechanical" ]; then
    ok "5: 'class' still resolves to 'mechanical' from 'rule' alone -- finding_layer absence does not perturb the pre-existing classifier"
else
    bad "5 FAILED: got class='$RES5' (expected 'mechanical')"
fi

# =============================================================================
# 6 (independence B): a finding with ONLY "finding_layer" set (no
#    "rule", no already-fixed-marker match) MUST classify "class" as
#    "judgment" exactly as it would without finding_layer, AND must
#    still carry the finding_layer value -- proving the two fields are
#    computed independently in BOTH directions.
# =============================================================================
echo "-- 6: setting only finding_layer (no rule) leaves 'class' at its normal 'judgment' value, and finding_layer survives --"
mk_batch "$SCRATCH/batch6.json"
cat > "$SCRATCH/verdict6.json" <<'EOF'
{"round":1,"verdict":"NO-GO","findings":[
  {"id":"F1","severity":"MINOR","description":"substantive design concern","finding_layer":"process-doc"}
]}
EOF
OUT6=$(python3 "$TOOL" record --batch "$SCRATCH/batch6.json" --round 1 \
    --verdict-file "$SCRATCH/verdict6.json" --tier opus --effort xhigh \
    --out "$SCRATCH/rev6.json" 2>&1)
RC6=$?
RES6=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
f1 = doc["findings"][0]
print(f1.get("class", "<NOCLASS>") + "|" + f1.get("finding_layer", "<ABSENT>"))
' "$SCRATCH/rev6.json" 2>/dev/null)
if [ "$RC6" -eq 0 ] && [ "$RES6" = "judgment|process-doc" ]; then
    ok "6: 'class' resolves to its normal 'judgment' value AND finding_layer='process-doc' is independently preserved -- the two fields are orthogonal"
else
    bad "6 FAILED: rc=$RC6 got='$RES6' out='$OUT6'"
fi

# =============================================================================
# 7 (backfill consistency): `backfill`'s per-finding finding_layer
#    follows the same accept/round-trip + validate-closed-set discipline
#    as `record`'s, since both subcommands build the same
#    ReviewVerdictRecord finding shape.
# =============================================================================
echo "-- 7: backfill accepts + round-trips a valid finding_layer, and rejects an invalid one --"
cat > "$SCRATCH/backfill_input7.json" <<'EOF'
{
  "review_id": "R-FL7-1",
  "batch_id": "BATCH-FL7",
  "round": 1,
  "verdict": "GO",
  "source_evidence": "docs/CONTINUATION.md",
  "model_tier": "opus",
  "effort": "xhigh",
  "change_ids": ["CH-FL7"],
  "findings": [
    {"id": "F1", "severity": "NIT", "class": "judgment", "finding_layer": "test-instrumentation"}
  ]
}
EOF
OUT7=$(python3 "$TOOL" backfill --input "$SCRATCH/backfill_input7.json" --records-root "$FC" \
    --out "$SCRATCH/rev7.json" 2>&1)
RC7=$?
RES7=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
f1 = doc["findings"][0]
print(f1.get("finding_layer", "<ABSENT>"))
' "$SCRATCH/rev7.json" 2>/dev/null)
if [ "$RC7" -eq 0 ] && [ "$RES7" = "test-instrumentation" ]; then
    ok "7a: backfill round-trips a valid finding_layer ('test-instrumentation')"
else
    bad "7a FAILED: rc=$RC7 got='$RES7' out='$OUT7'"
fi
cat > "$SCRATCH/backfill_input7b.json" <<'EOF'
{
  "review_id": "R-FL7B-1",
  "batch_id": "BATCH-FL7B",
  "round": 1,
  "verdict": "GO",
  "source_evidence": "docs/CONTINUATION.md",
  "model_tier": "opus",
  "effort": "xhigh",
  "change_ids": ["CH-FL7B"],
  "findings": [
    {"id": "F1", "severity": "NIT", "class": "judgment", "finding_layer": "bogus-layer"}
  ]
}
EOF
rm -f "$SCRATCH/rev7b.json"
OUT7B=$(python3 "$TOOL" backfill --input "$SCRATCH/backfill_input7b.json" --records-root "$FC" \
    --out "$SCRATCH/rev7b.json" 2>&1)
RC7B=$?
if [ "$RC7B" -eq 2 ] && [ ! -f "$SCRATCH/rev7b.json" ]; then
    ok "7b: backfill refuses an invalid finding_layer value (exit 2), no file written"
else
    bad "7b FAILED: rc=$RC7B out='$OUT7B' file_exists=$([ -f "$SCRATCH/rev7b.json" ] && echo yes || echo no)"
fi

# =============================================================================
# B1 REMEDIATION (added after an independent review found tests 1-7 above
# never exercised a near-case-miss / near-underscore-miss / empty-string /
# falsy-non-string value -- so a regression that NORMALIZED those inputs
# into acceptance (case-fold + underscore-to-hyphen before the closed-set
# check), or that swapped the None-vs-absent guard for a generic falsy
# check (`if not value:` instead of `if value is None:`), would sail
# through undetected. Tests 8-11 (record) and 12-15 (backfill) below
# prove each of those near-miss/
# falsy shapes is genuinely REFUSED on BOTH the record and backfill
# paths; tests 16-17 pin the companion documented-correct behaviour
# (explicit JSON null IS accepted as "absent", key omitted from output)
# so the guard's accept side stays proven too, not only its refuse side.
# Reviewer's exact two mutations (manually re-applied + reverted to
# prove these new cases catch them -- not asserted blind):
#   (M-A) value.strip().lower().replace("_","-") in FINDING_LAYERS
#         before the closed-set membership check -- tests 8/9/12/13
#         below MUST fail against this mutation (case/underscore
#         near-misses would then be silently normalized and accepted).
#   (M-B) `if value is None:` -> `if not value:` in the absent-check
#         inside _validated_finding_layer() -- tests 10/11/14/15 below
#         MUST fail against this mutation ("" / false would then be
#         silently treated as "absent" instead of refused).
# =============================================================================

# -----------------------------------------------------------------------
# 8 (record, near-miss case): "Source-Defect" is NOT "source-defect" --
#    the closed-set check is exact-match, case-sensitive, never folded.
# -----------------------------------------------------------------------
echo "-- 8: record refuses a wrong-case near-miss 'Source-Defect' (no silent case-fold) --"
mk_batch "$SCRATCH/batch8.json"
cat > "$SCRATCH/verdict8.json" <<'EOF'
{"round":1,"verdict":"NO-GO","findings":[
  {"id":"F1","severity":"MINOR","finding_layer":"Source-Defect"}
]}
EOF
rm -f "$SCRATCH/rev8.json"
OUT8=$(python3 "$TOOL" record --batch "$SCRATCH/batch8.json" --round 1 \
    --verdict-file "$SCRATCH/verdict8.json" --tier opus --effort xhigh \
    --out "$SCRATCH/rev8.json" 2>&1)
RC8=$?
if [ "$RC8" -eq 2 ] && [ ! -f "$SCRATCH/rev8.json" ]; then
    ok "8: record refuses wrong-case 'Source-Defect' (exit 2), no file written"
else
    bad "8 FAILED: rc=$RC8 out='$OUT8' file_exists=$([ -f "$SCRATCH/rev8.json" ] && echo yes || echo no)"
fi

# -----------------------------------------------------------------------
# 9 (record, near-miss underscore): "source_defect" is NOT
#    "source-defect" -- underscore is never silently rewritten to hyphen.
# -----------------------------------------------------------------------
echo "-- 9: record refuses an underscore near-miss 'source_defect' (no silent underscore-to-hyphen) --"
mk_batch "$SCRATCH/batch9.json"
cat > "$SCRATCH/verdict9.json" <<'EOF'
{"round":1,"verdict":"NO-GO","findings":[
  {"id":"F1","severity":"MINOR","finding_layer":"source_defect"}
]}
EOF
rm -f "$SCRATCH/rev9.json"
OUT9=$(python3 "$TOOL" record --batch "$SCRATCH/batch9.json" --round 1 \
    --verdict-file "$SCRATCH/verdict9.json" --tier opus --effort xhigh \
    --out "$SCRATCH/rev9.json" 2>&1)
RC9=$?
if [ "$RC9" -eq 2 ] && [ ! -f "$SCRATCH/rev9.json" ]; then
    ok "9: record refuses underscore near-miss 'source_defect' (exit 2), no file written"
else
    bad "9 FAILED: rc=$RC9 out='$OUT9' file_exists=$([ -f "$SCRATCH/rev9.json" ] && echo yes || echo no)"
fi

# -----------------------------------------------------------------------
# 10 (record, empty string): "" is a PRESENT value, not an absence --
#     it must be refused, never silently treated as "no finding_layer".
# -----------------------------------------------------------------------
echo "-- 10: record refuses the empty string '' (present-but-empty is not absent) --"
mk_batch "$SCRATCH/batch10.json"
cat > "$SCRATCH/verdict10.json" <<'EOF'
{"round":1,"verdict":"NO-GO","findings":[
  {"id":"F1","severity":"MINOR","finding_layer":""}
]}
EOF
rm -f "$SCRATCH/rev10.json"
OUT10=$(python3 "$TOOL" record --batch "$SCRATCH/batch10.json" --round 1 \
    --verdict-file "$SCRATCH/verdict10.json" --tier opus --effort xhigh \
    --out "$SCRATCH/rev10.json" 2>&1)
RC10=$?
if [ "$RC10" -eq 2 ] && [ ! -f "$SCRATCH/rev10.json" ]; then
    ok "10: record refuses empty string '' (exit 2), no file written"
else
    bad "10 FAILED: rc=$RC10 out='$OUT10' file_exists=$([ -f "$SCRATCH/rev10.json" ] && echo yes || echo no)"
fi

# -----------------------------------------------------------------------
# 11 (record, falsy non-string): JSON `false` is a PRESENT value (and
#     not a string at all) -- it must be refused, never silently treated
#     as absent by a generic falsy check.
# -----------------------------------------------------------------------
echo "-- 11: record refuses the falsy non-string value 'false' (present-but-falsy is not absent) --"
mk_batch "$SCRATCH/batch11.json"
cat > "$SCRATCH/verdict11.json" <<'EOF'
{"round":1,"verdict":"NO-GO","findings":[
  {"id":"F1","severity":"MINOR","finding_layer":false}
]}
EOF
rm -f "$SCRATCH/rev11.json"
OUT11=$(python3 "$TOOL" record --batch "$SCRATCH/batch11.json" --round 1 \
    --verdict-file "$SCRATCH/verdict11.json" --tier opus --effort xhigh \
    --out "$SCRATCH/rev11.json" 2>&1)
RC11=$?
if [ "$RC11" -eq 2 ] && [ ! -f "$SCRATCH/rev11.json" ]; then
    ok "11: record refuses falsy non-string 'false' (exit 2), no file written"
else
    bad "11 FAILED: rc=$RC11 out='$OUT11' file_exists=$([ -f "$SCRATCH/rev11.json" ] && echo yes || echo no)"
fi

# -----------------------------------------------------------------------
# 12-15 (backfill parity): the SAME four near-miss/falsy shapes refused
#     on the backfill path, since both subcommands share
#     _validated_finding_layer() and must share its guarantees.
# -----------------------------------------------------------------------
echo "-- 12: backfill refuses a wrong-case near-miss 'Source-Defect' --"
cat > "$SCRATCH/backfill_input12.json" <<'EOF'
{
  "review_id": "R-FL12-1", "batch_id": "BATCH-FL12", "round": 1, "verdict": "GO",
  "source_evidence": "docs/CONTINUATION.md", "model_tier": "opus", "effort": "xhigh",
  "change_ids": ["CH-FL12"],
  "findings": [{"id": "F1", "severity": "NIT", "class": "judgment", "finding_layer": "Source-Defect"}]
}
EOF
rm -f "$SCRATCH/rev12.json"
OUT12=$(python3 "$TOOL" backfill --input "$SCRATCH/backfill_input12.json" --records-root "$FC" \
    --out "$SCRATCH/rev12.json" 2>&1)
RC12=$?
if [ "$RC12" -eq 2 ] && [ ! -f "$SCRATCH/rev12.json" ]; then
    ok "12: backfill refuses wrong-case 'Source-Defect' (exit 2), no file written"
else
    bad "12 FAILED: rc=$RC12 out='$OUT12' file_exists=$([ -f "$SCRATCH/rev12.json" ] && echo yes || echo no)"
fi

echo "-- 13: backfill refuses an underscore near-miss 'source_defect' --"
cat > "$SCRATCH/backfill_input13.json" <<'EOF'
{
  "review_id": "R-FL13-1", "batch_id": "BATCH-FL13", "round": 1, "verdict": "GO",
  "source_evidence": "docs/CONTINUATION.md", "model_tier": "opus", "effort": "xhigh",
  "change_ids": ["CH-FL13"],
  "findings": [{"id": "F1", "severity": "NIT", "class": "judgment", "finding_layer": "source_defect"}]
}
EOF
rm -f "$SCRATCH/rev13.json"
OUT13=$(python3 "$TOOL" backfill --input "$SCRATCH/backfill_input13.json" --records-root "$FC" \
    --out "$SCRATCH/rev13.json" 2>&1)
RC13=$?
if [ "$RC13" -eq 2 ] && [ ! -f "$SCRATCH/rev13.json" ]; then
    ok "13: backfill refuses underscore near-miss 'source_defect' (exit 2), no file written"
else
    bad "13 FAILED: rc=$RC13 out='$OUT13' file_exists=$([ -f "$SCRATCH/rev13.json" ] && echo yes || echo no)"
fi

echo "-- 14: backfill refuses the empty string '' --"
cat > "$SCRATCH/backfill_input14.json" <<'EOF'
{
  "review_id": "R-FL14-1", "batch_id": "BATCH-FL14", "round": 1, "verdict": "GO",
  "source_evidence": "docs/CONTINUATION.md", "model_tier": "opus", "effort": "xhigh",
  "change_ids": ["CH-FL14"],
  "findings": [{"id": "F1", "severity": "NIT", "class": "judgment", "finding_layer": ""}]
}
EOF
rm -f "$SCRATCH/rev14.json"
OUT14=$(python3 "$TOOL" backfill --input "$SCRATCH/backfill_input14.json" --records-root "$FC" \
    --out "$SCRATCH/rev14.json" 2>&1)
RC14=$?
if [ "$RC14" -eq 2 ] && [ ! -f "$SCRATCH/rev14.json" ]; then
    ok "14: backfill refuses empty string '' (exit 2), no file written"
else
    bad "14 FAILED: rc=$RC14 out='$OUT14' file_exists=$([ -f "$SCRATCH/rev14.json" ] && echo yes || echo no)"
fi

echo "-- 15: backfill refuses the falsy non-string value 'false' --"
cat > "$SCRATCH/backfill_input15.json" <<'EOF'
{
  "review_id": "R-FL15-1", "batch_id": "BATCH-FL15", "round": 1, "verdict": "GO",
  "source_evidence": "docs/CONTINUATION.md", "model_tier": "opus", "effort": "xhigh",
  "change_ids": ["CH-FL15"],
  "findings": [{"id": "F1", "severity": "NIT", "class": "judgment", "finding_layer": false}]
}
EOF
rm -f "$SCRATCH/rev15.json"
OUT15=$(python3 "$TOOL" backfill --input "$SCRATCH/backfill_input15.json" --records-root "$FC" \
    --out "$SCRATCH/rev15.json" 2>&1)
RC15=$?
if [ "$RC15" -eq 2 ] && [ ! -f "$SCRATCH/rev15.json" ]; then
    ok "15: backfill refuses falsy non-string 'false' (exit 2), no file written"
else
    bad "15 FAILED: rc=$RC15 out='$OUT15' file_exists=$([ -f "$SCRATCH/rev15.json" ] && echo yes || echo no)"
fi

# -----------------------------------------------------------------------
# 16-17 (explicit null accepted, companion to 8-15's refusals): JSON
#     null is DOCUMENTED as equivalent to absent (module docstring:
#     "value is None: return None, None") -- pin that it is genuinely
#     ACCEPTED (rc=0) and the key is OMITTED from the output, on both
#     paths, so the accept side of the guard is proven as rigorously as
#     the refuse side tested above.
# -----------------------------------------------------------------------
echo "-- 16: record accepts explicit JSON null as absent; output omits the finding_layer key --"
mk_batch "$SCRATCH/batch16.json"
cat > "$SCRATCH/verdict16.json" <<'EOF'
{"round":1,"verdict":"NO-GO","findings":[
  {"id":"F1","severity":"MINOR","rule":"SC2086","finding_layer":null}
]}
EOF
OUT16=$(python3 "$TOOL" record --batch "$SCRATCH/batch16.json" --round 1 \
    --verdict-file "$SCRATCH/verdict16.json" --tier opus --effort xhigh \
    --out "$SCRATCH/rev16.json" 2>&1)
RC16=$?
RES16=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
f1 = doc["findings"][0]
print("PRESENT" if "finding_layer" in f1 else "ABSENT")
' "$SCRATCH/rev16.json" 2>/dev/null)
if [ "$RC16" -eq 0 ] && [ "$RES16" = "ABSENT" ]; then
    ok "16: record accepts explicit null (rc=0), output omits finding_layer key -- null == absent, pinned"
else
    bad "16 FAILED: rc=$RC16 got='$RES16' out='$OUT16'"
fi

echo "-- 17: backfill accepts explicit JSON null as absent; output omits the finding_layer key --"
cat > "$SCRATCH/backfill_input17.json" <<'EOF'
{
  "review_id": "R-FL17-1", "batch_id": "BATCH-FL17", "round": 1, "verdict": "GO",
  "source_evidence": "docs/CONTINUATION.md", "model_tier": "opus", "effort": "xhigh",
  "change_ids": ["CH-FL17"],
  "findings": [{"id": "F1", "severity": "NIT", "class": "judgment", "finding_layer": null}]
}
EOF
OUT17=$(python3 "$TOOL" backfill --input "$SCRATCH/backfill_input17.json" --records-root "$FC" \
    --out "$SCRATCH/rev17.json" 2>&1)
RC17=$?
RES17=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
f1 = doc["findings"][0]
print("PRESENT" if "finding_layer" in f1 else "ABSENT")
' "$SCRATCH/rev17.json" 2>/dev/null)
if [ "$RC17" -eq 0 ] && [ "$RES17" = "ABSENT" ]; then
    ok "17: backfill accepts explicit null (rc=0), output omits finding_layer key -- null == absent, pinned"
else
    bad "17 FAILED: rc=$RC17 got='$RES17' out='$OUT17'"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
