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
#
# Revised 2026-10-08 (T048 restart round 1, R7 B1): backfill rows record
# history and are NEVER gate coverage, however well cited (R2 below now
# asserts that). R3b previously asserted that a producer-written verdict
# file ({"verdict":"GO"} with no reviewer identity) recorded via `record`
# was COVERED -- that WAS the self-certification path R7 B1 reported; it
# now asserts UNCOVERED, and R3c is the genuine negative control (a
# reviewer-authored verdict with an authenticated dispatch). R5's
# cwd-determinism check is re-pointed at that genuine live record, whose
# verdict can actually change if resolution were cwd-anchored.
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
if [ "$RC2" -eq 1 ] && echo "$OUT2" | grep -q "^UNCOVERED CH-R2-REAL .*backfill"; then
    ok "R2 (R7 B1): even a well-cited backfill row (real, in-tree, hash-pinned evidence) is history only -- never gate coverage"
else
    bad "R2 (R7 B1) FAILED: expected UNCOVERED naming backfill, got rc=$RC2: $OUT2"
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
# shellcheck disable=SC2034 # RR_TOOL is consumed by the sourced lib/review_record_genuine.sh
RR_TOOL="$TOOL"
# shellcheck source=lib/review_record_genuine.sh
# shellcheck disable=SC1091 # sourced helper is linted on its own; the precheck pack runs shellcheck without -x
. "$HERE/lib/review_record_genuine.sh"
RR_WORK="$SCRATCH/work"; mkdir -p "$RR_WORK"
RR_LEDGER="$SCRATCH/ledger.jsonl"; : > "$RR_LEDGER"
mkdir -p "$SCRATCH/live"
rr_genuine "$SCRATCH/live/genuine.json" BATCH-R5-CWD CH-R5-CWD 1 GO '[]' D-R5-CWD
LIVE_EV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verdict_evidence"])' "$SCRATCH/live/genuine.json")
OUT2L=$(python3 "$TOOL" gate --change CH-R5-CWD --records "$SCRATCH/live" --dispatch-ledger "$RR_LEDGER" 2>&1)
RC2L=$?
DECOY_CWD="$SCRATCH/decoy_cwd"
mkdir -p "$DECOY_CWD"
# A decoy file with the SAME basename as the real archived verdict evidence
# but forged content -- if resolution were cwd-anchored this decoy would be
# what `gate` hashes from THIS cwd.
echo '{"verdict":"GO","findings":[],"forged":true}' > "$DECOY_CWD/$LIVE_EV"

OUT5=$(cd "$DECOY_CWD" && python3 "$TOOL" gate --change CH-R5-CWD --records "$SCRATCH/live" --dispatch-ledger "$RR_LEDGER" 2>&1)
RC5=$?
if [ "$RC2L" -eq 0 ] && [ "$RC5" = "$RC2L" ] && [ "$OUT5" = "$OUT2L" ]; then
    ok "R5 (R3-I4 part b): a genuine live record's COVERED verdict (rc=$RC5) is IDENTICAL from a cwd holding a same-named forged decoy -- never cwd-dependent"
else
    bad "R5 (R3-I4 part b) FAILED: own-dir rc=$RC2L '$OUT2L', decoy-cwd rc=$RC5 '$OUT5'"
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
# V3 round 3 (record as pointer): such a record is now INADMISSIBLE -- the
# whole run exits 4 naming it -- whether its body_hash is absent (R3) or
# recomputed by the forger (R3r: then it fails on the missing evidence).
# Each forged-record case runs in its OWN records dir so one inadmissible
# record never masks the next case's own reason.
mkdir -p "$SCRATCH/r3rec"
cat > "$SCRATCH/r3rec/live.json" <<'EOF'
{"review_id":"R2-LIVE-1","batch_id":"BATCH-R2-LIVE","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R2-LIVE"],"findings":[],
 "source":"live","precheck_used":true}
EOF
OUT3=$(python3 "$TOOL" gate --change CH-R2-LIVE --records "$SCRATCH/r3rec" 2>&1)
RC3=$?
if [ "$RC3" -eq 4 ] && echo "$OUT3" | grep -q "live.json: record body_hash"; then
    ok "R3 (T085 Round 5 R4-I1): a hand-written live record with precheck_used:true and NO archived/hash-verifiable evidence is INADMISSIBLE (exit 4) -- closes 'gate trusts any .json file under --records'"
else
    bad "R3 (T085 Round 5 R4-I1) FAILED: expected exit 4 naming the record, got rc=$RC3: $OUT3"
fi
python3 - "$SCRATCH/r3rec/live.json" <<'PY'
import hashlib, json, sys
p = sys.argv[1]; d = json.load(open(p))
d["body_hash"] = hashlib.sha256(json.dumps(d, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
OUT3R=$(python3 "$TOOL" gate --change CH-R2-LIVE --records "$SCRATCH/r3rec" 2>&1)
RC3R=$?
if [ "$RC3R" -eq 4 ] && echo "$OUT3R" | grep -q "live.json: verdict_evidence missing"; then
    ok "R3r: the same forgery with a correct body_hash is still inadmissible (no reviewer evidence to derive it from)"
else
    bad "R3r FAILED: expected exit 4 naming missing verdict_evidence, got rc=$RC3R: $OUT3R"
fi

# -----------------------------------------------------------------------
# R3b (R7 B1 probe A, inverted from its pre-2026-10-08 shape): a verdict
# file the PRODUCER wrote -- {"verdict":"GO"} with no reviewer identity --
# run through the real `record` CLI with a real precheck is NOT coverage.
# R3c is the genuine negative control: a reviewer-authored verdict whose
# dispatch is in the ledger, precheck/v1 all_pass, distinct producer.
# -----------------------------------------------------------------------
cat > "$SCRATCH/batch_r3b.json" <<'EOF'
{"batch_id": "BATCH-R2-LIVE-REAL", "changes": ["CH-R2-LIVE-REAL"]}
EOF
cat > "$SCRATCH/verdict_r3b.json" <<'EOF'
{"verdict": "GO", "round": 1, "findings": []}
EOF
cat > "$SCRATCH/precheck_r3b.json" <<'EOF'
{"schema": "precheck/v1", "batch_id": "BATCH-R2-LIVE-REAL", "all_pass": true, "checks": []}
EOF
mkdir -p "$SCRATCH/r3brec"
python3 "$TOOL" record --batch "$SCRATCH/batch_r3b.json" --round 1 \
    --verdict-file "$SCRATCH/verdict_r3b.json" --precheck "$SCRATCH/precheck_r3b.json" \
    --tier opus --effort xhigh --producer-id PRODUCER-R3B --out "$SCRATCH/r3brec/live_real.json" >/dev/null 2>&1
OUT3B=$(python3 "$TOOL" gate --change CH-R2-LIVE-REAL --records "$SCRATCH/r3brec" --dispatch-ledger "$RR_LEDGER" 2>&1)
RC3B=$?
# V3 round 3: a verdict with neither a reviewer nor a review binding cannot be
# placed (nothing authenticates which batch/changes/round it speaks for), so
# it is inadmissible -- the reviewer-less-WITH-binding case (admitted, then
# UNCOVERED "no reviewer identity") is B1-A in the r1 suite.
if [ "$RC3B" -eq 4 ] && echo "$OUT3B" | grep -q "live_real.json: verdict evidence review binding missing"; then
    ok "R3b (R7 B1): a producer-written verdict with no reviewer identity and no binding is inadmissible (exit 4), even through the real record CLI with a passing precheck"
else
    bad "R3b (R7 B1) FAILED: expected exit 4 naming the missing binding, got rc=$RC3B: $OUT3B"
fi
mkdir -p "$SCRATCH/r3crec"
rr_genuine "$SCRATCH/r3crec/live_genuine.json" BATCH-R2-LIVE-GEN CH-R2-LIVE-GEN 1 GO '[]' D-R3C
OUT3C=$(python3 "$TOOL" gate --change CH-R2-LIVE-GEN --records "$SCRATCH/r3crec" --dispatch-ledger "$RR_LEDGER" 2>&1)
RC3C=$?
if [ "$RC3C" -eq 0 ] && echo "$OUT3C" | grep -q "^COVERED CH-R2-LIVE-GEN "; then
    ok "R3c (true negative control): a genuine reviewer-authored live record is COVERED -- the fix does not over-reject legitimate coverage"
else
    bad "R3c (true negative control) FAILED: expected COVERED/exit 0, got rc=$RC3C: $OUT3C"
fi

# -----------------------------------------------------------------------
# R6 (T085 Round 3 R3-I4 core repro, the original Round 2 finding's
# still-open second half: "gate ... never checks precheck_used"): a LIVE
# record that admits NO precheck was ever consulted (precheck_used
# missing/false) must NOT qualify as coverage, exactly like an untraced
# backfill row does not.
# -----------------------------------------------------------------------
# V3 round 3: driven through the REAL record CLI with no precheck at all (a
# hand-written record would now be inadmissible before this guard is reached).
mkdir -p "$SCRATCH/r6rec"
RR_NO_PRECHECK=1 rr_genuine "$SCRATCH/r6rec/live_no_precheck.json" BATCH-R3I4-LIVE-NOPRECHECK CH-LIVE-NOPRECHECK 1 GO '[]' D-R6
OUT6=$(python3 "$TOOL" gate --change CH-LIVE-NOPRECHECK --records "$SCRATCH/r6rec" --dispatch-ledger "$RR_LEDGER" 2>&1)
RC6=$?
if [ "$RR_RC" -eq 0 ] && [ "$RC6" -eq 1 ] && echo "$OUT6" | grep -q "^UNCOVERED CH-LIVE-NOPRECHECK .*no precheck was consulted"; then
    ok "R6 (R3-I4 'precheck_used' half): a LIVE record whose own precheck_used==false (no precheck genuinely consulted) is correctly REFUSED as qualifying coverage -- closes the still-open second half of the original Round 2 finding"
else
    bad "R6 (R3-I4 'precheck_used' half) FAILED: expected UNCOVERED/exit 1, got rc=$RC6: $OUT6"
fi

# -----------------------------------------------------------------------
# R7 (closed-set source guard): a record whose `source` field is neither
# "live" nor "backfill" (missing, forged, or a typo) must NEVER qualify
# -- the conservative-safe default on an unrecognised value.
# -----------------------------------------------------------------------
# V3 round 3: body_hash recomputed (as a forger would) so the SOURCE guard is
# the one that refuses -- inadmissible, exit 4, naming the unrecognised value.
mkdir -p "$SCRATCH/r7rec"
cat > "$SCRATCH/r7rec/unknown_source.json" <<'EOF'
{"review_id":"R3I4-UNKSRC-1","batch_id":"BATCH-R3I4-UNKSRC","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-UNKSRC"],"findings":[],
 "source":"imported-from-elsewhere","precheck_used":true,"source_evidence":"real_historical_review_notes.md"}
EOF
python3 - "$SCRATCH/r7rec/unknown_source.json" <<'PY'
import hashlib, json, sys
p = sys.argv[1]; d = json.load(open(p))
d["body_hash"] = hashlib.sha256(json.dumps(d, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
OUT7=$(python3 "$TOOL" gate --change CH-UNKSRC --records "$SCRATCH/r7rec" 2>&1)
RC7=$?
if [ "$RC7" -eq 4 ] && echo "$OUT7" | grep -q "unrecognised record source 'imported-from-elsewhere'"; then
    ok "R7 (closed-set source guard): a record with an unrecognised source value is inadmissible (exit 4), regardless of how plausible its other fields look"
else
    bad "R7 (closed-set source guard) FAILED: expected exit 4 naming the source, got rc=$RC7: $OUT7"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
