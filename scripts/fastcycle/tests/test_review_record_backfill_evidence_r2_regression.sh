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
# a REAL, existing file -- correctly counts as coverage.
# -----------------------------------------------------------------------
REAL_EVIDENCE="$SCRATCH/real_historical_review_notes.md"
echo "# Real historical review notes -- round 1, opus xhigh, GO, zero findings" > "$REAL_EVIDENCE"

cat > "$SCRATCH/backfill_input_real.json" <<EOF
{
  "review_id": "R2-REAL-1",
  "batch_id": "BATCH-R2-REAL",
  "round": 1,
  "verdict": "GO",
  "source_evidence": "$REAL_EVIDENCE",
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
    ok "R2 golden-good: a backfill row whose source_evidence names a REAL, existing file correctly counts as coverage"
else
    bad "R2 golden-good FAILED: expected COVERED/exit 0, got rc=$RC2: $OUT2"
fi

# -----------------------------------------------------------------------
# R3 (negative control): a LIVE (non-backfill) record is never subject to
# this check -- the fix does not over-reject live, producer-established
# coverage.
# -----------------------------------------------------------------------
cat > "$SCRATCH/records/live.json" <<'EOF'
{"review_id":"R2-LIVE-1","batch_id":"BATCH-R2-LIVE","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R2-LIVE"],"findings":[],
 "source":"live"}
EOF
OUT3=$(python3 "$TOOL" gate --change CH-R2-LIVE --records "$SCRATCH/records" 2>&1)
RC3=$?
if [ "$RC3" -eq 0 ] && echo "$OUT3" | grep -q "^COVERED CH-R2-LIVE"; then
    ok "R3 negative control: a LIVE (non-backfill) record is never subject to the source_evidence file-existence check"
else
    bad "R3 negative control FAILED: expected COVERED/exit 0, got rc=$RC3: $OUT3"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
