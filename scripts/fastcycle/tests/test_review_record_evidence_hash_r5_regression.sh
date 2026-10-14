#!/bin/sh
# =============================================================================
# T085 US2 Round 5 remediation regression (R4-I1, BLOCKING+IMPORTANT, 2026-10-02).
# Re-pointed 2026-10-08 (T048 restart round 1, R7 B1): every forgery below now
# attacks a GENUINE LIVE record's archived evidence, because backfill rows are
# history only and are never gate coverage (R7 B1 -- the previous version of
# this file asserted that a hand-authored backfill row was COVERED, which was
# itself the self-certification path R7 reported). Each attack would be
# COVERED if its guard were removed (the forged evidence carries a correct
# content hash and the record's body_hash is recomputed), so every check is
# discriminating, not refused for some unrelated reason.
# =============================================================================
#
# Forgery classes (T085 Round 4 + R7):
#   1. A SYMLINK inside --records pointing at a file outside it.
#   2. A SYMLINKED DIRECTORY inside --records pointing outside it.
#   3. A record that cites its OWN file as its evidence (structurally cannot
#      verify: a file cannot contain its own sha256 -- documented here as the
#      hash guard's own consequence, not as a separately discriminating check).
#   4. A hand-written "live" record with precheck_used:true and NO evidence.
#   5. A ".." path escape to a file outside --records.
#   6. Negative control: the genuine live record is COVERED.
#   7. Content swap of the archived verdict evidence after the record was
#      written: COVERED before, UNCOVERED after.
#
# Shared primitive: `_evidence_hash_verified()` (realpath containment against
# --records, self-citation refusal, content-hash binding; R7 I2: relative
# citations resolve against the citing record's own directory).
#
# §11.4.199: every check is a real invocation of the real tool, building the
# genuine record through the real `record` CLI (lib/review_record_genuine.sh).
#
# Usage: sh test_review_record_evidence_hash_r5_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/review/review_record.py"
# shellcheck disable=SC2034 # RR_TOOL is consumed by the sourced lib/review_record_genuine.sh
RR_TOOL="$TOOL"
# shellcheck source=lib/review_record_genuine.sh
# shellcheck disable=SC1091 # sourced helper is linted on its own; the precheck pack runs shellcheck without -x
. "$HERE/lib/review_record_genuine.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 5 R4-I1 regression: review_record.py content-hash evidence binding =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM
REC="$SCRATCH/records"; mkdir -p "$REC" "$SCRATCH/outside"
RR_WORK="$SCRATCH/work"; mkdir -p "$RR_WORK"
RR_LEDGER="$SCRATCH/ledger.jsonl"; : > "$RR_LEDGER"

# V3 round 3 (record as pointer): a record whose evidence cannot be verified is
# INADMISSIBLE -- the whole gate run exits 4 naming the record and the reason,
# never a quiet UNCOVERED (the evidence is what places the record at all).
inadmissible() { # inadmissible RECORD_BASENAME REASON_FRAGMENT
    [ "$G_RC" -eq 4 ] && echo "$G_OUT" | grep -q "inadmissible record .*$1: .*$2"
}
gate() { # gate CHANGE -> G_RC, G_OUT
    G_OUT=$(python3 "$TOOL" gate --change "$1" --records "$REC" --dispatch-ledger "$RR_LEDGER" 2>&1)
    G_RC=$?
}
# repoint RECORD NEW_EVIDENCE: rewrite the record's verdict_evidence to
# NEW_EVIDENCE (sha256 of what that path resolves to, from the record's own
# dir) and recompute body_hash -- the strongest forgery a producer can make.
repoint() {
    python3 - "$1" "$2" <<'PY'
import hashlib, json, os, sys
p, ev = sys.argv[1], sys.argv[2]
d = json.load(open(p))
target = os.path.join(os.path.dirname(p), ev)
d["verdict_evidence"] = ev
d["verdict_evidence_sha256"] = hashlib.sha256(open(target, "rb").read()).hexdigest()
body = {k: v for k, v in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
}

rr_genuine "$REC/genuine.json" BATCH-R5 CH-R5 1 GO '[]' D-R5
GENUINE_EV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verdict_evidence"])' "$REC/genuine.json")
cp "$REC/genuine.json" "$SCRATCH/genuine.pristine"

# --- 6 (negative control, run first so every attack below is grounded) ---
echo "-- 6 (negative control): a genuine live record qualifies --"
gate CH-R5
if [ "$RR_RC" -eq 0 ] && [ "$G_RC" -eq 0 ] && echo "$G_OUT" | grep -q "^COVERED CH-R5 "; then
    ok "6 (negative control): a genuine live record (reviewer-authored, archived, hash-verified) counts as coverage -- the attacks below are refused for their own reason, not wholesale"
else
    bad "6 (negative control) FAILED: record rc=$RR_RC gate rc=$G_RC: $G_OUT"
fi

# Move the genuine evidence OUT of --records; every attack points back at it.
mv "$REC/$GENUINE_EV" "$SCRATCH/outside/$GENUINE_EV"

echo "-- 1: symlink inside --records pointing outside it --"
ln -s "$SCRATCH/outside/$GENUINE_EV" "$REC/evil_symlink.verdict-evidence"
cp "$SCRATCH/genuine.pristine" "$REC/genuine.json"; repoint "$REC/genuine.json" evil_symlink.verdict-evidence
gate CH-R5
if inadmissible genuine.json verdict_evidence; then
    ok "1: a symlink inside --records resolving outside it is REFUSED (inadmissible, exit 4) even with a correct content hash"
else
    bad "1 FAILED: expected exit 4 naming verdict_evidence, got rc=$G_RC: $G_OUT"
fi
rm -f "$REC/evil_symlink.verdict-evidence"

echo "-- 2: symlinked directory inside --records pointing outside it --"
ln -s "$SCRATCH/outside" "$REC/evil_dir"
cp "$SCRATCH/genuine.pristine" "$REC/genuine.json"; repoint "$REC/genuine.json" "evil_dir/$GENUINE_EV"
gate CH-R5
if inadmissible genuine.json verdict_evidence; then
    ok "2: a symlinked DIRECTORY inside --records resolving outside it is REFUSED (exit 4)"
else
    bad "2 FAILED: expected exit 4, got rc=$G_RC: $G_OUT"
fi
rm -f "$REC/evil_dir"

echo "-- 5: '..' path escape --"
cp "$SCRATCH/genuine.pristine" "$REC/genuine.json"; repoint "$REC/genuine.json" "../outside/$GENUINE_EV"
gate CH-R5
if inadmissible genuine.json verdict_evidence; then
    ok "5: a '..' path escape is refused (exit 4), even with a genuinely-matching content hash"
else
    bad "5 FAILED: expected exit 4, got rc=$G_RC: $G_OUT"
fi

echo "-- 3: self-citation --"
cp "$SCRATCH/genuine.pristine" "$REC/genuine.json"; repoint "$REC/genuine.json" genuine.json
gate CH-R5
if inadmissible genuine.json verdict_evidence; then
    ok "3: a record citing its own file as evidence is refused (exit 4; self-citation guard -- a file can never carry its own content hash, so the hash guard refuses it too)"
else
    bad "3 FAILED: expected exit 4, got rc=$G_RC: $G_OUT"
fi

# restore the genuine record + evidence for 7
mv "$SCRATCH/outside/$GENUINE_EV" "$REC/$GENUINE_EV"
cp "$SCRATCH/genuine.pristine" "$REC/genuine.json"

echo "-- 4: hand-written live record, precheck_used:true, zero verifiable evidence --"
cat > "$REC/forged_live.json" <<'EOF'
{"review_id":"R5LIVE-1","batch_id":"BATCH-R5LIVE","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R5LIVE"],"findings":[],
 "source":"live","precheck_used":true}
EOF
gate CH-R5LIVE
if inadmissible forged_live.json body_hash; then
    ok "4: a hand-written live record (no evidence) is REFUSED (inadmissible, exit 4)"
else
    bad "4 FAILED: expected exit 4 naming forged_live.json, got rc=$G_RC: $G_OUT"
fi
rm -f "$REC/forged_live.json"

echo "-- 7: content swap of the archived verdict evidence --"
gate CH-R5; RC7A=$G_RC; OUT7A=$G_OUT
python3 - "$REC/$GENUINE_EV" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["swapped"] = True; json.dump(d, open(p, "w"))
PY
gate CH-R5
if [ "$RC7A" -eq 0 ] && echo "$OUT7A" | grep -q "^COVERED CH-R5 " \
    && inadmissible genuine.json verdict_evidence; then
    ok "7: content-hash binding detects a post-authoring swap of the reviewer's archived verdict -- COVERED before, inadmissible (exit 4) after"
else
    bad "7 FAILED: before rc=$RC7A ($OUT7A), after rc=$G_RC ($G_OUT)"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
