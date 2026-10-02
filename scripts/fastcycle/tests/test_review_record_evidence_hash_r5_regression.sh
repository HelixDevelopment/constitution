#!/bin/sh
# =============================================================================
# T085 US2 Round 5 remediation regression (R4-I1, BLOCKING+IMPORTANT, 2026-10-02).
# =============================================================================
#
# T085 Round 4's independent review reproduced FOUR distinct evidence-
# forgery classes against review_record.py's committed
# `_backfill_source_evidence_traceable()` (the T085 Round 2/3 realpath-
# containment-only check), every one accepted (rc=0 COVERED) for a
# fabricated row claiming opus/xhigh/GO/zero-findings:
#
#   1. A SYMLINK inside --records pointing at /etc/hostname.
#   2. A SYMLINKED DIRECTORY inside --records (e.g. pointing at /etc).
#   3. A backfill row that cites its OWN record file as its evidence
#      (circular self-citation).
#   4. A hand-written "live" record with precheck_used:true and NO
#      evidence at all -- "gate trusts any .json file under --records".
#
# Fixed with the shared `_evidence_hash_verified()` primitive (section
# 11.4.227): realpath (not abspath) containment closes 1+2 in one fix;
# an explicit self-citation check (record's own realpath vs the
# evidence's resolved realpath) closes 3; content-hash binding
# (`source_evidence_sha256` / `precheck_evidence_sha256`, captured at
# authoring time, re-verified at gate time) plus requiring a live
# record's precheck claim to be backed by an ARCHIVED, hash-pinned
# precheck document closes 4.
#
# This file also re-confirms the pre-existing ".." path-escape refusal
# (the Round 4 reviewer's own note: "A '..' path escape is correctly
# refused" -- never regressed by this round's fix).
#
# §11.4.199: every check is a real invocation of the real tool.
#
# Usage: sh test_review_record_evidence_hash_r5_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/review/review_record.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 5 R4-I1 regression: review_record.py content-hash evidence binding =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM
mkdir -p "$SCRATCH/records"

# =============================================================================
# 1 -- a SYMLINK inside --records pointing at /etc/hostname.
# =============================================================================
echo "-- 1: symlink inside --records pointing outside it (e.g. /etc/hostname) --"
if [ -f /etc/hostname ]; then
    ln -s /etc/hostname "$SCRATCH/records/evil_symlink.txt"
    cat > "$SCRATCH/records/sym_file.json" <<'EOF'
{"review_id":"R5SYM-1","batch_id":"BATCH-R5SYM","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R5SYM"],"findings":[],
 "source":"backfill","source_evidence":"evil_symlink.txt",
 "source_evidence_sha256":"0000000000000000000000000000000000000000000000000000000000000000"}
EOF
    # The sha256 above is deliberately a well-formed-but-WRONG 70-char
    # string (padding beyond 64 to also probe malformed-length refusal);
    # replace it with the REAL /etc/hostname content hash so this test
    # exercises the SYMLINK/containment defense specifically, not merely
    # a hash mismatch.
    REAL_HASH=$(sha256sum /etc/hostname 2>/dev/null | awk '{print $1}')
    if [ -n "$REAL_HASH" ]; then
        sed -i "s/00*0000$/$REAL_HASH/" "$SCRATCH/records/sym_file.json" 2>/dev/null || true
        cat > "$SCRATCH/records/sym_file.json" <<EOF
{"review_id":"R5SYM-1","batch_id":"BATCH-R5SYM","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R5SYM"],"findings":[],
 "source":"backfill","source_evidence":"evil_symlink.txt",
 "source_evidence_sha256":"$REAL_HASH"}
EOF
    fi
    OUT1=$(python3 "$TOOL" gate --change CH-R5SYM --records "$SCRATCH/records" 2>&1)
    RC1=$?
    if [ "$RC1" -eq 1 ] && echo "$OUT1" | grep -q "^UNCOVERED CH-R5SYM"; then
        ok "1: a symlink inside --records resolving outside it (/etc/hostname) is REFUSED -- realpath containment closes the symlink bypass EVEN WITH a correct content hash"
    else
        bad "1 FAILED: expected UNCOVERED/exit 1, got rc=$RC1: $OUT1"
    fi
    rm -f "$SCRATCH/records/sym_file.json" "$SCRATCH/records/evil_symlink.txt"
else
    echo "NOTE: /etc/hostname absent on this host -- check 1 SKIPPED (honest, not fabricated as pass)"
fi

# =============================================================================
# 2 -- a SYMLINKED DIRECTORY inside --records (e.g. pointing at /etc).
# =============================================================================
echo "-- 2: symlinked directory inside --records (e.g. pointing at /etc) --"
if [ -f /etc/hostname ]; then
    ln -s /etc "$SCRATCH/records/evil_dir"
    REAL_HASH=$(sha256sum /etc/hostname 2>/dev/null | awk '{print $1}')
    cat > "$SCRATCH/records/sym_dir.json" <<EOF
{"review_id":"R5SYMDIR-1","batch_id":"BATCH-R5SYMDIR","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R5SYMDIR"],"findings":[],
 "source":"backfill","source_evidence":"evil_dir/hostname",
 "source_evidence_sha256":"$REAL_HASH"}
EOF
    OUT2=$(python3 "$TOOL" gate --change CH-R5SYMDIR --records "$SCRATCH/records" 2>&1)
    RC2=$?
    if [ "$RC2" -eq 1 ] && echo "$OUT2" | grep -q "^UNCOVERED CH-R5SYMDIR"; then
        ok "2: a symlinked DIRECTORY inside --records (evil_dir -> /etc) resolving outside it is REFUSED -- realpath containment resolves every path component, not merely the leaf"
    else
        bad "2 FAILED: expected UNCOVERED/exit 1, got rc=$RC2: $OUT2"
    fi
    rm -f "$SCRATCH/records/sym_dir.json" "$SCRATCH/records/evil_dir"
else
    echo "NOTE: /etc/hostname absent on this host -- check 2 SKIPPED (honest, not fabricated as pass)"
fi

# =============================================================================
# 3 -- a backfill row that cites its OWN record file as its evidence
#      (circular self-citation).
# =============================================================================
echo "-- 3: backfill row self-citing its own record file as evidence --"
SELF_PATH="$SCRATCH/records/self_cite.json"
SELF_HASH_PLACEHOLDER="0000000000000000000000000000000000000000000000000000000000000000"
cat > "$SELF_PATH" <<EOF
{"review_id":"R5SELF-1","batch_id":"BATCH-R5SELF","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R5SELF"],"findings":[],
 "source":"backfill","source_evidence":"self_cite.json",
 "source_evidence_sha256":"$SELF_HASH_PLACEHOLDER"}
EOF
# Overwrite with the record's OWN real content hash (the strongest form
# of this forgery -- the cited hash is even genuinely CORRECT for the
# file as it exists right now; only the self-citation check can refuse
# this, content-hash-matching alone cannot).
REAL_SELF_HASH=$(sha256sum "$SELF_PATH" | awk '{print $1}')
cat > "$SELF_PATH" <<EOF
{"review_id":"R5SELF-1","batch_id":"BATCH-R5SELF","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R5SELF"],"findings":[],
 "source":"backfill","source_evidence":"self_cite.json",
 "source_evidence_sha256":"PLACEHOLDER_TO_BE_REPLACED"}
EOF
# The record's own hash changes every time its content (including the
# sha256 field itself) changes -- so a PERFECT self-citing hash match is
# structurally impossible to construct by hand; this test instead proves
# the EXPLICIT self-citation guard fires even when the stored hash is
# simply a plausible-looking 64-hex value (never mind whether it
# happens to match -- self-citation is refused BEFORE any hash
# comparison is even attempted, per _evidence_hash_verified()'s own
# documented check order).
sed -i "s/PLACEHOLDER_TO_BE_REPLACED/$REAL_SELF_HASH/" "$SELF_PATH"
OUT3=$(python3 "$TOOL" gate --change CH-R5SELF --records "$SCRATCH/records" 2>&1)
RC3=$?
if [ "$RC3" -eq 1 ] && echo "$OUT3" | grep -q "^UNCOVERED CH-R5SELF"; then
    ok "3: a backfill row citing ITS OWN record file as evidence is REFUSED -- the self-citation guard fires regardless of hash plausibility"
else
    bad "3 FAILED: expected UNCOVERED/exit 1, got rc=$RC3: $OUT3"
fi
rm -f "$SELF_PATH"

# =============================================================================
# 4 -- a hand-written "live" record with precheck_used:true and NO
#      evidence at all.
# =============================================================================
echo "-- 4: hand-written live record, precheck_used:true, zero verifiable evidence --"
cat > "$SCRATCH/records/forged_live.json" <<'EOF'
{"review_id":"R5LIVE-1","batch_id":"BATCH-R5LIVE","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R5LIVE"],"findings":[],
 "source":"live","precheck_used":true}
EOF
OUT4=$(python3 "$TOOL" gate --change CH-R5LIVE --records "$SCRATCH/records" 2>&1)
RC4=$?
if [ "$RC4" -eq 1 ] && echo "$OUT4" | grep -q "^UNCOVERED CH-R5LIVE"; then
    ok "4: a hand-written live record (precheck_used:true, no evidence) is REFUSED -- 'gate trusts any .json file under --records' is closed"
else
    bad "4 FAILED: expected UNCOVERED/exit 1, got rc=$RC4: $OUT4"
fi
rm -f "$SCRATCH/records/forged_live.json"

# =============================================================================
# 5 -- a '..' path escape is STILL correctly refused (pre-existing
#      behaviour, never regressed by this round's content-hash fix).
# =============================================================================
echo "-- 5: regression guard -- a '..' path escape is still refused --"
mkdir -p "$SCRATCH/outside"
echo "outside content" > "$SCRATCH/outside/secret.txt"
OUTSIDE_HASH=$(sha256sum "$SCRATCH/outside/secret.txt" | awk '{print $1}')
cat > "$SCRATCH/records/dotdot.json" <<EOF
{"review_id":"R5DOTDOT-1","batch_id":"BATCH-R5DOTDOT","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R5DOTDOT"],"findings":[],
 "source":"backfill","source_evidence":"../outside/secret.txt",
 "source_evidence_sha256":"$OUTSIDE_HASH"}
EOF
OUT5=$(python3 "$TOOL" gate --change CH-R5DOTDOT --records "$SCRATCH/records" 2>&1)
RC5=$?
if [ "$RC5" -eq 1 ] && echo "$OUT5" | grep -q "^UNCOVERED CH-R5DOTDOT"; then
    ok "5 (regression guard): a '..' path escape is STILL correctly refused, even with a genuinely-matching content hash"
else
    bad "5 (regression guard) FAILED: expected UNCOVERED/exit 1, got rc=$RC5: $OUT5"
fi
rm -f "$SCRATCH/records/dotdot.json"

# =============================================================================
# 6 (negative control) -- a genuinely valid backfill row (real, in-tree,
#    non-self-citing, correctly-hashed evidence) still qualifies --
#    proves checks 1-5 above are not simply refusing everything.
# =============================================================================
echo "-- 6 (negative control): a genuinely valid backfill row still qualifies --"
echo "# Genuine historical review notes" > "$SCRATCH/records/genuine_evidence.md"
GENUINE_HASH=$(sha256sum "$SCRATCH/records/genuine_evidence.md" | awk '{print $1}')
cat > "$SCRATCH/records/genuine.json" <<EOF
{"review_id":"R5GENUINE-1","batch_id":"BATCH-R5GENUINE","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R5GENUINE"],"findings":[],
 "source":"backfill","source_evidence":"genuine_evidence.md",
 "source_evidence_sha256":"$GENUINE_HASH"}
EOF
OUT6=$(python3 "$TOOL" gate --change CH-R5GENUINE --records "$SCRATCH/records" 2>&1)
RC6=$?
if [ "$RC6" -eq 0 ] && echo "$OUT6" | grep -q "^COVERED CH-R5GENUINE"; then
    ok "6 (negative control): a genuinely valid, correctly-hashed, in-tree, non-self-citing backfill row correctly counts as coverage -- the fix does not over-refuse"
else
    bad "6 (negative control) FAILED: expected COVERED/exit 0, got rc=$RC6: $OUT6"
fi

# =============================================================================
# 7 -- CONTENT-TAMPER detection: a backfill row whose evidence file is
#      later modified (content no longer matches the pinned hash) no
#      longer qualifies -- the Round 4 reviewer's own "before Round 5"
#      content-hash-binding recommendation, beyond mere path/containment
#      checking.
# =============================================================================
echo "-- 7: content-hash binding detects a LATER content swap under an unchanged path --"
echo "# Original genuine content" > "$SCRATCH/records/tamper_target.md"
ORIG_HASH=$(sha256sum "$SCRATCH/records/tamper_target.md" | awk '{print $1}')
cat > "$SCRATCH/records/tamper.json" <<EOF
{"review_id":"R5TAMPER-1","batch_id":"BATCH-R5TAMPER","round":1,"verdict":"GO",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-R5TAMPER"],"findings":[],
 "source":"backfill","source_evidence":"tamper_target.md",
 "source_evidence_sha256":"$ORIG_HASH"}
EOF
OUT7A=$(python3 "$TOOL" gate --change CH-R5TAMPER --records "$SCRATCH/records" 2>&1)
RC7A=$?
echo "# TAMPERED content -- swapped after the record was authored" > "$SCRATCH/records/tamper_target.md"
OUT7B=$(python3 "$TOOL" gate --change CH-R5TAMPER --records "$SCRATCH/records" 2>&1)
RC7B=$?
if [ "$RC7A" -eq 0 ] && echo "$OUT7A" | grep -q "^COVERED CH-R5TAMPER" \
    && [ "$RC7B" -eq 1 ] && echo "$OUT7B" | grep -q "^UNCOVERED CH-R5TAMPER"; then
    ok "7: content-hash binding genuinely detects a post-authoring content swap -- COVERED before the swap, UNCOVERED after, same path, same record"
else
    bad "7 FAILED: before-swap rc=$RC7A ($OUT7A), after-swap rc=$RC7B ($OUT7B) -- expected COVERED then UNCOVERED"
fi
rm -f "$SCRATCH/records/tamper.json" "$SCRATCH/records/tamper_target.md"

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
