#!/bin/sh
# =============================================================================
# T085 US2 Round 2 remediation regression (I-R2-8, IMPORTANT, 2026-09-30).
# =============================================================================
#
# Proves review_record.py `gate` no longer accepts a hand-authored
# "backfill" row as genuine review coverage unless its source_evidence
# resolves to a REAL, EXISTING file -- reproduced live before this fix: a
# fabricated backfill row claiming opus/xhigh/GO/zero-findings with
# source_evidence="none really" was accepted (rc=0 COVERED).
#
# §11.4.199: every check is a real invocation of the real tool.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/review/review_record.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 2 I-R2-8 regression: review_record.py gate rejects unbacked backfill rows =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM
mkdir -p "$SCRATCH/records"

# -----------------------------------------------------------------------
# R1 (golden-bad, I-R2-8's own exact repro): a fabricated backfill row
# with an untraceable source_evidence placeholder -- must NOT count as
# coverage.
# -----------------------------------------------------------------------
cat > "$SCRATCH/backfill_input_fake.json" <<'EOF'
{
  "review_id": "R2-FAKE-1",
  "batch_id": "BATCH-R2-FAKE",
  "round": 1,
  "verdict": "GO",
  "source_evidence": "none really",
  "model_tier": "opus",
  "effort": "xhigh",
  "change_ids": ["CH-R2-FAKE"],
  "findings": []
}
EOF
python3 "$TOOL" backfill --input "$SCRATCH/backfill_input_fake.json" --out "$SCRATCH/records/fake.json" >/dev/null 2>&1
RC_BACKFILL=$?
if [ "$RC_BACKFILL" -eq 0 ] && [ -f "$SCRATCH/records/fake.json" ]; then
    ok "R1 setup: fabricated backfill record written (backfill itself is legal -- the GATE consultation is what must refuse it)"
else
    bad "R1 setup FAILED: could not write the fabricated backfill record (rc=$RC_BACKFILL)"
fi

OUT1=$(python3 "$TOOL" gate --change CH-R2-FAKE --records "$SCRATCH/records" 2>&1)
RC1=$?
if [ "$RC1" -eq 1 ] && echo "$OUT1" | grep -q "^UNCOVERED CH-R2-FAKE"; then
    ok "R1 (I-R2-8 core repro): a fabricated backfill row with an untraceable source_evidence placeholder is REFUSED as coverage (UNCOVERED, exit 1)"
else
    bad "R1 (I-R2-8 core repro) FAILED: expected UNCOVERED/exit 1, got rc=$RC1: $OUT1"
fi

# -----------------------------------------------------------------------
# R2 (golden-good): an identical backfill row whose source_evidence names
# a REAL, existing, non-empty file INSIDE the --records tree (T085 Round
# 3 R3-I4: evidence is now required to be genuinely traceable to this
# project's own records corpus, not an arbitrary external path -- see
# R4/R5 below for the exact forgery/non-determinism this closes) --
# correctly counts as coverage. The path is given RELATIVE to --records
# (the convention this fix's deterministic resolution is FOR), proving
# relative resolution against records_root, not cwd, genuinely works.
# -----------------------------------------------------------------------
echo "# Real historical review notes -- round 1, opus xhigh, GO, zero findings" > "$SCRATCH/records/real_historical_review_notes.md"

cat > "$SCRATCH/backfill_input_real.json" <<'EOF'
{
  "review_id": "R2-REAL-1",
  "batch_id": "BATCH-R2-REAL",
  "round": 1,
  "verdict": "GO",
  "source_evidence": "real_historical_review_notes.md",
  "model_tier": "opus",
  "effort": "xhigh",
  "change_ids": ["CH-R2-REAL"],
  "findings": []
}
EOF
python3 "$TOOL" backfill --input "$SCRATCH/backfill_input_real.json" --out "$SCRATCH/records/real.json" >/dev/null 2>&1

OUT2=$(python3 "$TOOL" gate --change CH-R2-REAL --records "$SCRATCH/records" 2>&1)
RC2=$?
if [ "$RC2" -eq 0 ] && echo "$OUT2" | grep -q "^COVERED CH-R2-REAL"; then
    ok "R2 golden-good: a backfill row whose source_evidence names a REAL, existing, non-empty file inside --records (given as a relative path) correctly counts as coverage"
else
    bad "R2 golden-good FAILED: expected COVERED/exit 0, got rc=$RC2: $OUT2"
fi

# -----------------------------------------------------------------------
# R4 (T085 Round 3 R3-I4 core repro, part (a)): a forged backfill row
# citing a REAL, existing file that is NOT genuine evidence of anything
# (the exact reviewer's own example, /etc/hostname) must be REFUSED --
# "a file that happens to exist" is not "traceable evidence".
# -----------------------------------------------------------------------
if [ -f /etc/hostname ]; then
    cat > "$SCRATCH/backfill_input_forged.json" <<'EOF'
{
  "review_id": "R3I4-FORGED-1",
  "batch_id": "BATCH-R3I4-FORGED",
  "round": 1,
  "verdict": "GO",
  "source_evidence": "/etc/hostname",
  "model_tier": "opus",
  "effort": "xhigh",
  "change_ids": ["CH-ANY"],
  "findings": []
}
EOF
    python3 "$TOOL" backfill --input "$SCRATCH/backfill_input_forged.json" --out "$SCRATCH/records/forged.json" >/dev/null 2>&1
    OUT4=$(python3 "$TOOL" gate --change CH-ANY --records "$SCRATCH/records" 2>&1)
    RC4=$?
    if [ "$RC4" -eq 1 ] && echo "$OUT4" | grep -q "^UNCOVERED CH-ANY"; then
        ok "R4 (R3-I4 part a): a forged backfill row citing a REAL-but-unrelated existing file (/etc/hostname, the reviewer's own example) is correctly REFUSED as coverage -- a file that merely EXISTS is not traceable evidence"
    else
        bad "R4 (R3-I4 part a) FAILED: expected UNCOVERED/exit 1 for a /etc/hostname-cited forgery, got rc=$RC4: $OUT4"
    fi
    rm -f "$SCRATCH/records/forged.json"
else
    echo "NOTE: /etc/hostname does not exist on this host -- R4 SKIPPED (honest, not fabricated as pass)"
fi

# -----------------------------------------------------------------------
# R5 (T085 Round 3 R3-I4 core repro, part (b)): the SAME record's
# coverage verdict is DETERMINISTIC regardless of the gate command's own
# ambient invoking cwd -- the pre-fix version resolved a relative
# source_evidence against os.getcwd(), so this exact record was COVERED
# from one cwd and UNCOVERED from another. Re-check R2's own record from
# a DIFFERENT cwd (one that happens to contain a SAME-NAMED decoy file,
# the strongest form of the non-determinism this closes) and confirm the
# verdict is IDENTICAL to R2's.
# -----------------------------------------------------------------------
DECOY_CWD="$SCRATCH/decoy_cwd"
mkdir -p "$DECOY_CWD"
# A decoy file with the SAME basename as the real evidence, but empty/
# unrelated -- if resolution were still cwd-anchored, this decoy would
# itself satisfy the pre-fix "any file that exists" check from THIS cwd.
: > "$DECOY_CWD/real_historical_review_notes.md"

OUT5=$(cd "$DECOY_CWD" && python3 "$TOOL" gate --change CH-R2-REAL --records "$SCRATCH/records" 2>&1)
RC5=$?
if [ "$RC5" = "$RC2" ] && [ "$OUT5" = "$OUT2" ]; then
    ok "R5 (R3-I4 part b): the SAME record's coverage verdict (rc=$RC5, '$OUT5') is IDENTICAL regardless of the gate command's own ambient cwd -- deterministic, never cwd-dependent"
else
    bad "R5 (R3-I4 part b) FAILED: verdict changed when invoked from a different cwd -- R2 was rc=$RC2 '$OUT2', this run was rc=$RC5 '$OUT5'"
fi

# -----------------------------------------------------------------------
# R3 (T085 Round 5 R4-I1 core repro, updated from its original Round 2/3
# shape -- see the inline note below for exactly what changed and why):
# a HAND-WRITTEN live record carrying only `precheck_used:true` with NO
# archived, hash-verifiable precheck evidence behind it is now correctly
# REFUSED as coverage -- this is the EXACT "gate trusts any .json file
# under --records" forgery the Round 4 independent review demonstrated:
# "a hand-written 'live' record with precheck_used: true and no evidence
# at all, since `gate` trusts any .json file under --records." Prior
# rounds' own version of this fixture (identical shape) was treated as a
# legitimate "negative control" expected to COVER -- under T085 Round 5
# that is now understood to BE the forgery class itself, and this
# project's explicit, documented decision (per the Round 4 reviewer's
# own recommendation) is to refuse it: a live record's precheck claim is
# trusted ONLY when independently verifiable against an archived,
# content-hash-pinned precheck document (see review_record.py's
# cmd_record()/`_evidence_hash_verified()`), never on the boolean
# field's say-so alone.
# -----------------------------------------------------------------------
cat > "$SCRATCH/records/live.json" <<'EOF'
{"review_id":"R2-LIVE-1","batch_id":"BATCH-R2-LIVE","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R2-LIVE"],"findings":[],
 "source":"live","precheck_used":true}
EOF
OUT3=$(python3 "$TOOL" gate --change CH-R2-LIVE --records "$SCRATCH/records" 2>&1)
RC3=$?
if [ "$RC3" -eq 1 ] && echo "$OUT3" | grep -q "^UNCOVERED CH-R2-LIVE"; then
    ok "R3 (T085 Round 5 R4-I1): a hand-written live record with precheck_used:true and NO archived/hash-verifiable evidence is correctly REFUSED -- closes 'gate trusts any .json file under --records'"
else
    bad "R3 (T085 Round 5 R4-I1) FAILED: expected UNCOVERED/exit 1 for an unbacked hand-written live record, got rc=$RC3: $OUT3"
fi

# -----------------------------------------------------------------------
# R3b (the TRUE negative control this file's original R3 was meant to
# be): a GENUINE live record, produced via the REAL `record` CLI against
# a REAL --precheck file, correctly counts as coverage -- proving the
# T085 Round 5 fix does not over-reject legitimate, producer-established
# live coverage, it only refuses the UNBACKED hand-written shape above.
# -----------------------------------------------------------------------
cat > "$SCRATCH/batch_r3b.json" <<'EOF'
{"batch_id": "BATCH-R2-LIVE-REAL", "changes": ["CH-R2-LIVE-REAL"]}
EOF
cat > "$SCRATCH/verdict_r3b.json" <<'EOF'
{"verdict": "GO", "round": 1, "findings": []}
EOF
cat > "$SCRATCH/precheck_r3b.json" <<'EOF'
{"evidence": {"markers": []}}
EOF
python3 "$TOOL" record --batch "$SCRATCH/batch_r3b.json" --round 1 \
    --verdict-file "$SCRATCH/verdict_r3b.json" --precheck "$SCRATCH/precheck_r3b.json" \
    --tier opus --effort xhigh --out "$SCRATCH/records/live_real.json" >/dev/null 2>&1
OUT3B=$(python3 "$TOOL" gate --change CH-R2-LIVE-REAL --records "$SCRATCH/records" 2>&1)
RC3B=$?
if [ "$RC3B" -eq 0 ] && echo "$OUT3B" | grep -q "^COVERED CH-R2-LIVE-REAL"; then
    ok "R3b (true negative control): a GENUINE live record produced via the real 'record' CLI with a real --precheck file correctly counts as coverage -- the fix does not over-reject legitimate coverage"
else
    bad "R3b (true negative control) FAILED: expected COVERED/exit 0, got rc=$RC3B: $OUT3B"
fi

# -----------------------------------------------------------------------
# R6 (T085 Round 3 R3-I4 core repro, the original Round 2 finding's
# still-open second half: "gate ... never checks precheck_used"): a LIVE
# record that admits NO precheck was ever consulted (precheck_used
# missing/false) must NOT qualify as coverage, exactly like an untraced
# backfill row does not.
# -----------------------------------------------------------------------
cat > "$SCRATCH/records/live_no_precheck.json" <<'EOF'
{"review_id":"R3I4-LIVE-NOPRECHECK-1","batch_id":"BATCH-R3I4-LIVE-NOPRECHECK","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-LIVE-NOPRECHECK"],"findings":[],
 "source":"live","precheck_used":false}
EOF
OUT6=$(python3 "$TOOL" gate --change CH-LIVE-NOPRECHECK --records "$SCRATCH/records" 2>&1)
RC6=$?
if [ "$RC6" -eq 1 ] && echo "$OUT6" | grep -q "^UNCOVERED CH-LIVE-NOPRECHECK"; then
    ok "R6 (R3-I4 'precheck_used' half): a LIVE record whose own precheck_used==false (no precheck genuinely consulted) is correctly REFUSED as qualifying coverage -- closes the still-open second half of the original Round 2 finding"
else
    bad "R6 (R3-I4 'precheck_used' half) FAILED: expected UNCOVERED/exit 1, got rc=$RC6: $OUT6"
fi

# -----------------------------------------------------------------------
# R7 (closed-set source guard): a record whose `source` field is neither
# "live" nor "backfill" (missing, forged, or a typo) must NEVER qualify
# -- the conservative-safe default on an unrecognised value.
# -----------------------------------------------------------------------
cat > "$SCRATCH/records/unknown_source.json" <<'EOF'
{"review_id":"R3I4-UNKSRC-1","batch_id":"BATCH-R3I4-UNKSRC","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-UNKSRC"],"findings":[],
 "source":"imported-from-elsewhere","precheck_used":true,"source_evidence":"real_historical_review_notes.md"}
EOF
OUT7=$(python3 "$TOOL" gate --change CH-UNKSRC --records "$SCRATCH/records" 2>&1)
RC7=$?
if [ "$RC7" -eq 1 ] && echo "$OUT7" | grep -q "^UNCOVERED CH-UNKSRC"; then
    ok "R7 (closed-set source guard): a record with an unrecognised source value never qualifies, regardless of how plausible its other fields look"
else
    bad "R7 (closed-set source guard) FAILED: expected UNCOVERED/exit 1, got rc=$RC7: $OUT7"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
