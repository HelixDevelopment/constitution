#!/bin/sh
# =============================================================================
# T085 US2 Round 2 remediation regression (I-R2-6, IMPORTANT, 2026-09-30).
# =============================================================================
#
# Proves backstop_compare.py's exit codes now match C-001
# (contracts/common-conventions.md): UNVERIFIED -> 4 (BLIND), a
# change_id-mismatch/unconfirmed-identity -> 2 (usage error, --out NOT
# written), a full lane missing its OWN change_id (not merely differing
# from --fast) is caught too, and a completely EMPTY full lane is
# UNVERIFIED (4), never the clean NO_DRIFT/0 state.
#
# §11.4.199: every check is a real invocation of the real tool against
# scratch verdicts/v1 documents this file constructs.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/lib/backstop_compare.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 2 I-R2-6 regression: backstop_compare.py C-001-aligned exit codes =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

# -----------------------------------------------------------------------
# R1 (golden-good): matching change_id, one FAIL both lanes, one PASS both
# -> NO_DRIFT, exit 0, --out written.
# -----------------------------------------------------------------------
cat > "$SCRATCH/r1_fast.json" <<'EOF'
{"schema":"verdicts/v1","change_id":"CH-R2-1","results":[
  {"gate_id":"GATE-A","verdict":"PASS","source":"RUN","evidence":"e.txt","duration_ms":1},
  {"gate_id":"GATE-B","verdict":"FAIL","source":"RUN","evidence":"e.txt","duration_ms":1}
],"summary":{"total":2,"pass":1,"fail":1}}
EOF
cp "$SCRATCH/r1_fast.json" "$SCRATCH/r1_full.json"
OUT_R1=$(python3 "$TOOL" --fast "$SCRATCH/r1_fast.json" --full "$SCRATCH/r1_full.json" --out "$SCRATCH/r1_out.json" 2>&1)
RC_R1=$?
if [ "$RC_R1" -eq 0 ] && echo "$OUT_R1" | grep -q "^NO_DRIFT" && [ -f "$SCRATCH/r1_out.json" ]; then
    ok "R1 golden-good: matching change_id, consistent verdicts -> NO_DRIFT/exit 0, --out written"
else
    bad "R1 golden-good FAILED (rc=$RC_R1): $OUT_R1"
fi

# -----------------------------------------------------------------------
# R2: UNVERIFIED now maps to exit 4 (C-001 BLIND), not 3 -- full-lane
# verdict SKIP for one gate.
# -----------------------------------------------------------------------
cat > "$SCRATCH/r2_fast.json" <<'EOF'
{"schema":"verdicts/v1","change_id":"CH-R2-2","results":[
  {"gate_id":"GATE-A","verdict":"PASS","source":"RUN","evidence":"e.txt","duration_ms":1}
],"summary":{"total":1,"pass":1,"fail":0}}
EOF
cat > "$SCRATCH/r2_full.json" <<'EOF'
{"schema":"verdicts/v1","change_id":"CH-R2-2","results":[
  {"gate_id":"GATE-A","verdict":"SKIP","source":"RUN","evidence":"e.txt","duration_ms":1}
],"summary":{"total":1,"pass":0,"fail":0}}
EOF
OUT_R2=$(python3 "$TOOL" --fast "$SCRATCH/r2_fast.json" --full "$SCRATCH/r2_full.json" --out "$SCRATCH/r2_out.json" 2>&1)
RC_R2=$?
if [ "$RC_R2" -eq 4 ] && echo "$OUT_R2" | grep -q "^UNVERIFIED" && [ -f "$SCRATCH/r2_out.json" ]; then
    ok "R2 (I-R2-6): UNVERIFIED (full-lane SKIP) maps to exit 4 (C-001 BLIND), --out written"
else
    bad "R2 (I-R2-6) FAILED: expected exit 4 with --out written, got rc=$RC_R2: $OUT_R2"
fi

# -----------------------------------------------------------------------
# R3: change_id mismatch (both present, different) maps to exit 2,
# --out NOT written.
# -----------------------------------------------------------------------
cat > "$SCRATCH/r3_fast.json" <<'EOF'
{"schema":"verdicts/v1","change_id":"CH-R2-3-FAST","results":[
  {"gate_id":"GATE-A","verdict":"PASS","source":"RUN","evidence":"e.txt","duration_ms":1}
],"summary":{"total":1,"pass":1,"fail":0}}
EOF
cat > "$SCRATCH/r3_full.json" <<'EOF'
{"schema":"verdicts/v1","change_id":"CH-R2-3-FULL","results":[
  {"gate_id":"GATE-A","verdict":"PASS","source":"RUN","evidence":"e.txt","duration_ms":1}
],"summary":{"total":1,"pass":1,"fail":0}}
EOF
rm -f "$SCRATCH/r3_out.json"
OUT_R3=$(python3 "$TOOL" --fast "$SCRATCH/r3_fast.json" --full "$SCRATCH/r3_full.json" --out "$SCRATCH/r3_out.json" 2>&1)
RC_R3=$?
if [ "$RC_R3" -eq 2 ] && echo "$OUT_R3" | grep -q "CHANGE_ID_MISMATCH" && [ ! -f "$SCRATCH/r3_out.json" ]; then
    ok "R3 (I-R2-6): both-present-and-different change_id maps to exit 2 (C-001 usage error), --out NOT written"
else
    bad "R3 (I-R2-6) FAILED: expected exit 2 with NO --out file, got rc=$RC_R3, out_exists=$([ -f "$SCRATCH/r3_out.json" ] && echo yes || echo no): $OUT_R3"
fi

# -----------------------------------------------------------------------
# R4 (I-R2-6's own named repro): full lane missing change_id ENTIRELY
# (fast lane HAS one) -- Round 1 silently compared these as if confirmed
# equal; now also refused as exit 2, --out not written.
# -----------------------------------------------------------------------
cat > "$SCRATCH/r4_fast.json" <<'EOF'
{"schema":"verdicts/v1","change_id":"CH-R2-4","results":[
  {"gate_id":"GATE-A","verdict":"PASS","source":"RUN","evidence":"e.txt","duration_ms":1}
],"summary":{"total":1,"pass":1,"fail":0}}
EOF
cat > "$SCRATCH/r4_full_no_change_id.json" <<'EOF'
{"schema":"verdicts/v1","results":[
  {"gate_id":"GATE-A","verdict":"PASS","source":"RUN","evidence":"e.txt","duration_ms":1}
],"summary":{"total":1,"pass":1,"fail":0}}
EOF
rm -f "$SCRATCH/r4_out.json"
OUT_R4=$(python3 "$TOOL" --fast "$SCRATCH/r4_fast.json" --full "$SCRATCH/r4_full_no_change_id.json" --out "$SCRATCH/r4_out.json" 2>&1)
RC_R4=$?
if [ "$RC_R4" -eq 2 ] && echo "$OUT_R4" | grep -q "CHANGE_ID_MISMATCH" && [ ! -f "$SCRATCH/r4_out.json" ]; then
    ok "R4 (I-R2-6 core repro): a full lane with NO change_id at all is refused (exit 2), never silently compared as if confirmed-equal"
else
    bad "R4 (I-R2-6 core repro) FAILED: expected exit 2, got rc=$RC_R4, out_exists=$([ -f "$SCRATCH/r4_out.json" ] && echo yes || echo no): $OUT_R4"
fi

# -----------------------------------------------------------------------
# R5 (I-R2-6's own named repro): TWO entirely empty lanes previously
# reported a clean NO_DRIFT/exit-0 -- now UNVERIFIED/exit 4 (nothing was
# ever actually verified).
# -----------------------------------------------------------------------
cat > "$SCRATCH/r5_empty.json" <<'EOF'
{"schema":"verdicts/v1","change_id":"CH-R2-5","results":[],"summary":{"total":0,"pass":0,"fail":0}}
EOF
OUT_R5=$(python3 "$TOOL" --fast "$SCRATCH/r5_empty.json" --full "$SCRATCH/r5_empty.json" --out "$SCRATCH/r5_out.json" 2>&1)
RC_R5=$?
if [ "$RC_R5" -eq 4 ] && ! echo "$OUT_R5" | grep -q "^NO_DRIFT"; then
    ok "R5 (I-R2-6 core repro): two entirely-empty lanes are UNVERIFIED/exit 4, NEVER the clean NO_DRIFT state"
else
    bad "R5 (I-R2-6 core repro) FAILED: expected exit 4 and no NO_DRIFT line, got rc=$RC_R5: $OUT_R5"
fi

# -----------------------------------------------------------------------
# R6 (negative control): a non-empty full lane with a genuine, fully-
# clean PASS/PASS match is STILL NO_DRIFT/exit 0 -- R5's fix does not
# over-trigger on legitimate non-empty lanes.
# -----------------------------------------------------------------------
cat > "$SCRATCH/r6_clean.json" <<'EOF'
{"schema":"verdicts/v1","change_id":"CH-R2-6","results":[
  {"gate_id":"GATE-A","verdict":"PASS","source":"RUN","evidence":"e.txt","duration_ms":1}
],"summary":{"total":1,"pass":1,"fail":0}}
EOF
OUT_R6=$(python3 "$TOOL" --fast "$SCRATCH/r6_clean.json" --full "$SCRATCH/r6_clean.json" --out "$SCRATCH/r6_out.json" 2>&1)
RC_R6=$?
if [ "$RC_R6" -eq 0 ] && echo "$OUT_R6" | grep -q "^NO_DRIFT"; then
    ok "R6 negative control: a genuinely clean, non-empty, fully-verified lane pair still correctly reports NO_DRIFT/exit 0"
else
    bad "R6 negative control FAILED: expected exit 0 NO_DRIFT, got rc=$RC_R6: $OUT_R6"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
