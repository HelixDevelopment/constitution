#!/bin/sh
# =============================================================================
# T085 US2 Round 2 remediation regression (B-R2-1, BLOCKING, 2026-09-30).
# =============================================================================
#
# B-R2-1's finding: Round 1's `verify_observed_inputs_integrity()` (the I1
# fix) in BOTH verdict_cache.py and mutation_reuse.py intercepts BEFORE
# their respective compute_key()'s own sha256-based key comparison ever
# runs -- so the EXISTING fixtures (vc_one_byte_flip, mr_one_input_changed,
# mr_gate_isolation) all model a STALE-envelope scenario (the envelope's
# declared sha256 does NOT match the real file on disk), which I1 catches
# and short-circuits to MISS on its own, independent of whether
# compute_key() genuinely differentiates by sha256 at all. The Round 2
# reviewer proved this gap by mutation: removing `sha256` from
# `inputs_part` in compute_key() in BOTH files leaves every existing
# suite's output unchanged.
#
# This file closes EXACTLY that coverage gap with a scenario NEITHER
# existing suite exercises: a SELF-CONSISTENT "honest re-trace" -- a real
# scratch input file's content genuinely changes between put and get, and
# the get-time envelope's declared sha256 is updated to TRUTHFULLY match
# the new real content (so I1's own check PASSES, never intercepting) --
# and asserts the result is still a genuine MISS, proving compute_key()
# itself (not merely I1) is what makes the stale PASS unreachable.
#
# Complementary negative control: I1 is NOT disabled by this fix -- a
# genuinely STALE envelope (declared sha256 does not match the real file)
# is still caught and reported as MISS via I1, independent of the key.
#
# §11.4.199: every check below is a REAL invocation of the real tools
# against a scratch corpus this file constructs and mutates itself.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
VC_TOOL="$FC/gates/verdict_cache.py"
MR_TOOL="$FC/gates/mutation_reuse.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 2 B-R2-1 regression: compute_key() genuinely differentiates by sha256, independent of the I1 integrity gate =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

sha256_of() { python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1"; }

# =============================================================================
# Section V -- verdict_cache.py
# =============================================================================
echo "-- Section V: verdict_cache.py put/get --"

V_FIXDIR="$SCRATCH/vc"
mkdir -p "$V_FIXDIR/envelopes" "$V_FIXDIR/inputs" "$V_FIXDIR/cache"

cat > "$V_FIXDIR/gate_script.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
echo "evidence" > "$V_FIXDIR/evidence.txt"

echo "content-version-one" > "$V_FIXDIR/inputs/x.txt"
H1=$(sha256_of "$V_FIXDIR/inputs/x.txt")

cat > "$V_FIXDIR/envelopes/put_envelope.json" <<EOF
{
  "gate_id": "GATE-R2-KEY",
  "gate_script": "../gate_script.sh",
  "observed_inputs": [{"path": "inputs/x.txt", "sha256": "$H1", "recorded_mtime": "2026-09-30T00:00:00Z"}],
  "tool_versions": {"python3": "3.11.4"},
  "env_allowlist": {"LANG": "C.UTF-8"},
  "target_fingerprint": "hermetic",
  "mutation_id": "none",
  "verdict": "PASS",
  "evidence": "../evidence.txt"
}
EOF

V1_OUT=$(python3 "$VC_TOOL" put --cache-dir "$V_FIXDIR/cache" --gate GATE-R2-KEY \
    --inputs "$V_FIXDIR/envelopes/put_envelope.json" --verdict PASS --evidence "$V_FIXDIR/evidence.txt" 2>&1)
V1_RC=$?
if [ "$V1_RC" -eq 0 ] && echo "$V1_OUT" | grep -q "^PUT key="; then
    ok "V1: verdict_cache.py put succeeds for the initial (self-consistent) envelope"
else
    bad "V1: verdict_cache.py put failed (rc=$V1_RC): $V1_OUT"
fi

# Genuinely mutate the real input file's content -- a real, on-disk change,
# not merely a re-declared hash.
echo "content-version-TWO-genuinely-different" > "$V_FIXDIR/inputs/x.txt"
H2=$(sha256_of "$V_FIXDIR/inputs/x.txt")
if [ "$H1" = "$H2" ]; then
    bad "V2 SETUP: H1 and H2 are identical -- the scratch fixture itself is broken, cannot proceed"
else
    ok "V2 SETUP: the scratch input file's real content genuinely changed (H1=$H1 != H2=$H2)"
fi

# "Honest re-trace": the get-time envelope declares H2, TRUTHFULLY matching
# the new real content -- I1's own integrity check MUST pass (no mismatch).
cat > "$V_FIXDIR/envelopes/get_envelope_honest.json" <<EOF
{
  "gate_id": "GATE-R2-KEY",
  "gate_script": "../gate_script.sh",
  "observed_inputs": [{"path": "inputs/x.txt", "sha256": "$H2", "recorded_mtime": "2026-09-30T00:05:00Z"}],
  "tool_versions": {"python3": "3.11.4"},
  "env_allowlist": {"LANG": "C.UTF-8"},
  "target_fingerprint": "hermetic",
  "mutation_id": "none"
}
EOF

V3_OUT=$(python3 "$VC_TOOL" get --cache-dir "$V_FIXDIR/cache" --gate GATE-R2-KEY \
    --inputs "$V_FIXDIR/envelopes/get_envelope_honest.json" 2>&1)
V3_RC=$?
if [ "$V3_RC" -eq 1 ] && echo "$V3_OUT" | grep -qE '^MISS key=' && ! echo "$V3_OUT" | grep -q 'verdict=PASS'; then
    ok "V3 (B-R2-1 core assertion): a genuinely-changed, HONESTLY re-traced (self-consistent, I1-passing) envelope correctly MISSes -- compute_key() itself differentiates by sha256, not merely the I1 gate"
else
    bad "V3 (B-R2-1 core assertion) FAILED: honest re-trace did not MISS as expected (rc=$V3_RC): $V3_OUT -- this is the exact stale-HIT class B-R2-1 warns about"
fi

# Negative control: I1 is NOT disabled -- a genuinely STALE envelope
# (declared sha256 does not match the CURRENT real file, i.e. H1 again,
# while the real file is now H2) is still caught and MISSes via I1.
cat > "$V_FIXDIR/envelopes/get_envelope_stale.json" <<EOF
{
  "gate_id": "GATE-R2-KEY",
  "gate_script": "../gate_script.sh",
  "observed_inputs": [{"path": "inputs/x.txt", "sha256": "$H1", "recorded_mtime": "2026-09-30T00:00:00Z"}],
  "tool_versions": {"python3": "3.11.4"},
  "env_allowlist": {"LANG": "C.UTF-8"},
  "target_fingerprint": "hermetic",
  "mutation_id": "none"
}
EOF
V4_OUT=$(python3 "$VC_TOOL" get --cache-dir "$V_FIXDIR/cache" --gate GATE-R2-KEY \
    --inputs "$V_FIXDIR/envelopes/get_envelope_stale.json" 2>&1)
V4_RC=$?
if [ "$V4_RC" -eq 1 ] && echo "$V4_OUT" | grep -qE '^MISS key=' && echo "$V4_OUT" >/dev/null; then
    ok "V4 (negative control, I1 still active): a genuinely STALE envelope (declared != real) still MISSes via I1 -- this fix does not disable I1"
else
    bad "V4 (negative control) FAILED: a stale envelope did not MISS as expected (rc=$V4_RC): $V4_OUT"
fi

# =============================================================================
# Section M -- mutation_reuse.py (identical class of scenario, DEC-23 key)
# =============================================================================
echo "-- Section M: mutation_reuse.py put/get --"

M_FIXDIR="$SCRATCH/mr"
mkdir -p "$M_FIXDIR/envelopes" "$M_FIXDIR/inputs" "$M_FIXDIR/cache"

echo "patch-bytes-fixed" > "$M_FIXDIR/patch.diff"
cat > "$M_FIXDIR/gate_script.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
echo "evidence" > "$M_FIXDIR/evidence.txt"

echo "mr-content-version-one" > "$M_FIXDIR/inputs/y.txt"
MH1=$(sha256_of "$M_FIXDIR/inputs/y.txt")

cat > "$M_FIXDIR/envelopes/put_envelope.json" <<EOF
{
  "observed_inputs": [{"path": "inputs/y.txt", "sha256": "$MH1", "recorded_mtime": "2026-09-30T00:00:00Z"}],
  "tool_versions": {"python3": "3.11.4"},
  "verdict": "KILLED",
  "mutation_id": "MUT-R2-1",
  "gate_id": "GATE-MR-R2-KEY"
}
EOF

M1_OUT=$(python3 "$MR_TOOL" put --cache-dir "$M_FIXDIR/cache" --gate GATE-MR-R2-KEY --mutation-id MUT-R2-1 \
    --patch "$M_FIXDIR/patch.diff" --gate-script "$M_FIXDIR/gate_script.sh" \
    --inputs "$M_FIXDIR/envelopes/put_envelope.json" --verdict KILLED --evidence "$M_FIXDIR/evidence.txt" 2>&1)
M1_RC=$?
if [ "$M1_RC" -eq 0 ] && echo "$M1_OUT" | grep -q "^PUT key="; then
    ok "M1: mutation_reuse.py put succeeds for the initial (self-consistent) envelope"
else
    bad "M1: mutation_reuse.py put failed (rc=$M1_RC): $M1_OUT"
fi

echo "mr-content-version-TWO-genuinely-different" > "$M_FIXDIR/inputs/y.txt"
MH2=$(sha256_of "$M_FIXDIR/inputs/y.txt")
if [ "$MH1" = "$MH2" ]; then
    bad "M2 SETUP: MH1 and MH2 are identical -- scratch fixture broken"
else
    ok "M2 SETUP: the scratch input file's real content genuinely changed (MH1=$MH1 != MH2=$MH2)"
fi

cat > "$M_FIXDIR/envelopes/get_envelope_honest.json" <<EOF
{
  "observed_inputs": [{"path": "inputs/y.txt", "sha256": "$MH2", "recorded_mtime": "2026-09-30T00:05:00Z"}],
  "tool_versions": {"python3": "3.11.4"}
}
EOF

M3_OUT=$(python3 "$MR_TOOL" get --cache-dir "$M_FIXDIR/cache" --gate GATE-MR-R2-KEY --mutation-id MUT-R2-1 \
    --patch "$M_FIXDIR/patch.diff" --gate-script "$M_FIXDIR/gate_script.sh" \
    --inputs "$M_FIXDIR/envelopes/get_envelope_honest.json" 2>&1)
M3_RC=$?
if [ "$M3_RC" -eq 1 ] && echo "$M3_OUT" | grep -qE '^MISS key=' && ! echo "$M3_OUT" | grep -q 'verdict=KILLED'; then
    ok "M3 (B-R2-1 core assertion): mutation_reuse.py's honestly-re-traced, I1-passing envelope correctly MISSes -- its compute_key() also genuinely differentiates by sha256"
else
    bad "M3 (B-R2-1 core assertion) FAILED: honest re-trace did not MISS as expected (rc=$M3_RC): $M3_OUT"
fi

cat > "$M_FIXDIR/envelopes/get_envelope_stale.json" <<EOF
{
  "observed_inputs": [{"path": "inputs/y.txt", "sha256": "$MH1", "recorded_mtime": "2026-09-30T00:00:00Z"}],
  "tool_versions": {"python3": "3.11.4"}
}
EOF
M4_OUT=$(python3 "$MR_TOOL" get --cache-dir "$M_FIXDIR/cache" --gate GATE-MR-R2-KEY --mutation-id MUT-R2-1 \
    --patch "$M_FIXDIR/patch.diff" --gate-script "$M_FIXDIR/gate_script.sh" \
    --inputs "$M_FIXDIR/envelopes/get_envelope_stale.json" 2>&1)
M4_RC=$?
if [ "$M4_RC" -eq 1 ] && echo "$M4_OUT" | grep -qE '^MISS key='; then
    ok "M4 (negative control, I1 still active): a genuinely stale mutation_reuse.py envelope still MISSes via I1"
else
    bad "M4 (negative control) FAILED: a stale envelope did not MISS as expected (rc=$M4_RC): $M4_OUT"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
