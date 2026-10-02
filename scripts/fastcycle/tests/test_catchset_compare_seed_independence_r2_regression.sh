#!/bin/sh
# =============================================================================
# T085 US2 Round 2 remediation regression (I-R2-9, IMPORTANT, 2026-09-30).
# =============================================================================
#
# Proves three independent fixes to catchset_compare.py's per-defect seed
# handling:
#   1. --seed-manifest supplies an INDEPENDENT seed source; when given, the
#      --old/--new gate manifests' own self-declared seed_defects are
#      entirely ignored (neither manifest under test can neutralize its
#      own seed).
#   2. In LEGACY mode (no --seed-manifest), a defect_id both old and new
#      declare with DIFFERENT patches is no longer silently resolved by
#      "new wins" -- it is excluded and reported as seed_conflict.
#   3. A gate that times out/errors for a defect is BLIND, never silently
#      folded into a clean MISSED.
#
# §11.4.199: every check is a real invocation of the real tool against a
# scratch corpus this file constructs.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/catchset_compare.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 2 I-R2-9 regression: catchset_compare.py independent seed source + seed_conflict + defect_blind =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM
mkdir -p "$SCRATCH/gates" "$SCRATCH/patches" "$SCRATCH/base_tree" "$SCRATCH/workdir"

cat > "$SCRATCH/base_tree/widget.sh" <<'EOF'
#!/bin/sh
echo "MARKER OK"
exit 0
EOF

cat > "$SCRATCH/patches/patch_removes_marker.sh" <<'EOF'
#!/pool/sh
exit 0
EOF
# (deliberately NOT echoing "MARKER OK" -- this is the real catching patch)
cat > "$SCRATCH/patches/patch_removes_marker.sh" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$SCRATCH/patches/patch_noop.sh" <<'EOF'
#!/bin/sh
echo "MARKER OK"
exit 0
EOF

cat > "$SCRATCH/gates/gate_catcher.sh" <<'EOF'
#!/bin/sh
sh "$1" 2>/dev/null | grep -q "MARKER OK" && exit 0
exit 1
EOF
chmod +x "$SCRATCH/gates/gate_catcher.sh" "$SCRATCH/base_tree/widget.sh" \
    "$SCRATCH/patches/patch_removes_marker.sh" "$SCRATCH/patches/patch_noop.sh"

cat > "$SCRATCH/old_manifest.json" <<'EOF'
{
  "config_id": "r2i9.old",
  "gates": [{"id": "g_catcher", "script": "gates/gate_catcher.sh"}],
  "base_tree": "base_tree/widget.sh",
  "seed_defects": [{"defect_id": "D1", "patch": "patches/patch_removes_marker.sh"}]
}
EOF
cat > "$SCRATCH/new_manifest.json" <<'EOF'
{
  "config_id": "r2i9.new",
  "gates": [{"id": "g_catcher", "script": "gates/gate_catcher.sh"}],
  "base_tree": "base_tree/widget.sh",
  "seed_defects": [{"defect_id": "D1", "patch": "patches/patch_noop.sh"}]
}
EOF
cat > "$SCRATCH/seed_manifest.json" <<'EOF'
{
  "config_id": "r2i9.seeds",
  "gates": [],
  "base_tree": "base_tree/widget.sh",
  "seed_defects": [{"defect_id": "D1", "patch": "patches/patch_removes_marker.sh"}]
}
EOF

# Minimal fastcycle.yaml scratch config (only the keys cmd_compare's own
# config-independent flags need; gate/patch/base_tree resolution here
# comes entirely from the manifests' own relative paths, matching the
# existing fixture corpus's own convention).
cat > "$SCRATCH/fastcycle.yaml" <<EOF
schema: fastcycle-config/v1
paths:
  mutation_source: $HERE/../lib/fc_common.sh
  guard_registry: $SCRATCH/registry.tsv
  workable_items_db: $SCRATCH/wi.db
  gate_sites: $SCRATCH/gate_sites.yaml
  thresholds: $SCRATCH/thresholds.yaml
  consumers_seed: $SCRATCH/consumers.seed.tsv
  evidence_root: $SCRATCH/evidence_root
  pre_build_verification: $SCRATCH/pre_build.sh
  gate_search_dirs:
    - $SCRATCH/gates
  patch_search_dirs:
    - $SCRATCH/patches
  base_tree_dirs:
    - $SCRATCH/base_tree
  transfer_records_dir: $SCRATCH/transfer_records
EOF
: > "$SCRATCH/registry.tsv"; : > "$SCRATCH/gate_sites.yaml"; : > "$SCRATCH/thresholds.yaml"
: > "$SCRATCH/consumers.seed.tsv"; : > "$SCRATCH/pre_build.sh"

cat > "$SCRATCH/corpus.json" <<'EOF'
{"mutation_defects": [{"id": "M1"}], "guard_defects": []}
EOF

# -----------------------------------------------------------------------
# R1 (I-R2-9's own repro, legacy mode): old and new declare D1 with
# DIFFERENT patches -- must be excluded as seed_conflict, never silently
# resolved by "new wins" (which would make D1 vanish entirely, since
# new's patch_noop.sh does NOT trip the catcher gate).
# -----------------------------------------------------------------------
OUT1=$(python3 "$TOOL" compare --config "$SCRATCH/fastcycle.yaml" \
    --corpus "$SCRATCH/corpus.json" --old "$SCRATCH/old_manifest.json" --new "$SCRATCH/new_manifest.json" \
    --workdir "$SCRATCH/workdir/r1" --out "$SCRATCH/r1_out.json" 2>&1)
RC1=$?
if [ -f "$SCRATCH/r1_out.json" ] && python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
details = d.get('named_defects_detail', [])
ok = any(x.get('reason') == 'seed_conflict' and x.get('defect_id') == 'D1' for x in details)
sys.exit(0 if ok else 1)
" "$SCRATCH/r1_out.json"; then
    ok "R1 (I-R2-9 legacy-mode core repro): a defect_id both manifests declare with DIFFERENT patches is reported as seed_conflict, never silently resolved by 'new wins'"
else
    bad "R1 (I-R2-9 legacy-mode core repro) FAILED: no seed_conflict finding for D1 (rc=$RC1): $OUT1"
fi

# T085 Round 3 R3-I2 (IMPORTANT): a seed_conflict finding MUST change the
# reported VERDICT, not merely populate a detail list no caller
# consults. The pre-R3-I2 version produced rc=0, superset:true, lost:0,
# per_defect:[] for this EXACT scenario -- the detail entry existed, but
# `superset`/`named_defects`/the process exit code were computed from
# `named_defects` alone, which the pre-fix code never appended `did`
# into. Assert all three here (exit code, `superset`, `named_defects`
# membership) -- not merely that a detail entry exists.
if [ -f "$SCRATCH/r1_out.json" ]; then
    R1_VERDICT_OUT=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
superset = d.get('superset')
named = d.get('named_defects', [])
lost = d.get('counts', {}).get('lost')
print('superset=%r named_defects=%r lost=%r' % (superset, named, lost))
ok = (superset is False) and ('D1' in named) and (lost is not None and lost >= 1)
sys.exit(0 if ok else 1)
" "$SCRATCH/r1_out.json")
    R1_VERDICT_RC=$?
    if [ "$R1_VERDICT_RC" -eq 0 ] && [ "$RC1" -eq 1 ]; then
        ok "R1b (R3-I2): the seed_conflict genuinely FLIPS the verdict -- rc=$RC1 (EXIT_FINDING), superset=false, D1 in named_defects ($R1_VERDICT_OUT)"
    else
        bad "R1b (R3-I2) FAILED: seed_conflict detected but the VERDICT did not change -- rc=$RC1 (expected 1), $R1_VERDICT_OUT"
    fi
else
    bad "R1b (R3-I2) FAILED: $SCRATCH/r1_out.json was not written"
fi

# -----------------------------------------------------------------------
# R2 (I-R2-9's own repro, --seed-manifest mode): the SAME old/new manifests
# (whose own seed_defects conflict as above) are given an INDEPENDENT
# --seed-manifest naming the REAL catching patch -- the manifests' own
# seed_defects are entirely ignored, D1 is evaluated against the
# independent patch, and old catches it correctly (both old and new share
# the SAME g_catcher gate here, so CAUGHT/CAUGHT, no violation -- the
# point is that the independent source, not either manifest, determined
# the outcome).
# -----------------------------------------------------------------------
OUT2=$(python3 "$TOOL" compare --config "$SCRATCH/fastcycle.yaml" \
    --corpus "$SCRATCH/corpus.json" --old "$SCRATCH/old_manifest.json" --new "$SCRATCH/new_manifest.json" \
    --seed-manifest "$SCRATCH/seed_manifest.json" \
    --workdir "$SCRATCH/workdir/r2" --out "$SCRATCH/r2_out.json" 2>&1)
RC2=$?
if [ -f "$SCRATCH/r2_out.json" ] && python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
pd = d.get('per_defect', [])
ok = any(x['defect_id'] == 'D1' and x['old_verdict'] == 'CAUGHT' and x['new_verdict'] == 'CAUGHT' for x in pd)
sys.exit(0 if ok else 1)
" "$SCRATCH/r2_out.json"; then
    ok "R2 (I-R2-9 --seed-manifest core repro): an independent --seed-manifest's own D1/patch is used -- neither manifest's own (conflicting) self-declared seed_defects determined the outcome"
else
    bad "R2 (I-R2-9 --seed-manifest core repro) FAILED (rc=$RC2): $OUT2"
fi

# -----------------------------------------------------------------------
# R3 (I-R2-9's own repro, timeout -> BLIND): a gate that hangs past its
# own timeout must report BLIND, never a silent MISSED. ~15s unavoidable
# real wait (the gate's own hardcoded timeout).
# -----------------------------------------------------------------------
cat > "$SCRATCH/gates/gate_hang.sh" <<'EOF'
#!/bin/sh
sleep 60
EOF
chmod +x "$SCRATCH/gates/gate_hang.sh"
cat > "$SCRATCH/old_hang_manifest.json" <<'EOF'
{
  "config_id": "r2i9.hang.old",
  "gates": [{"id": "g_hang", "script": "gates/gate_hang.sh"}],
  "base_tree": "base_tree/widget.sh",
  "seed_defects": [{"defect_id": "D1", "patch": "patches/patch_removes_marker.sh"}]
}
EOF
cp "$SCRATCH/old_hang_manifest.json" "$SCRATCH/new_hang_manifest.json"
echo "waiting up to ~15s for the hang gate's own timeout (unavoidable, real)..."
OUT3=$(python3 "$TOOL" compare --config "$SCRATCH/fastcycle.yaml" \
    --corpus "$SCRATCH/corpus.json" --old "$SCRATCH/old_hang_manifest.json" --new "$SCRATCH/new_hang_manifest.json" \
    --workdir "$SCRATCH/workdir/r3" --out "$SCRATCH/r3_out.json" 2>&1)
RC3=$?
if [ -f "$SCRATCH/r3_out.json" ] && python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
pd = d.get('per_defect', [])
ok = any(x['defect_id'] == 'D1' and x['old_verdict'] == 'BLIND' for x in pd)
det = d.get('named_defects_detail', [])
ok2 = any(x.get('reason') == 'defect_blind' and x.get('defect_id') == 'D1' for x in det)
sys.exit(0 if (ok and ok2) else 1)
" "$SCRATCH/r3_out.json"; then
    ok "R3 (I-R2-9 timeout core repro): a gate that hangs past its timeout reports the defect as BLIND (defect_blind finding), never a silent MISSED"
else
    bad "R3 (I-R2-9 timeout core repro) FAILED (rc=$RC3): $OUT3"
fi

# -----------------------------------------------------------------------
# R4 (T085 Round 3 R3-I2 mutation-flip proof): on a scratch copy of the
# real source, strip the EXACT fix line this round added
# (`named_defects.append(did)` inside the seed_conflicts loop) and
# confirm R1b's own verdict-change assertion now FAILS to hold -- proving
# this guard is genuinely load-bearing, not tautological (§11.4.115(F)).
# -----------------------------------------------------------------------
echo "-- R4: mutation-flip proof (seed_conflict verdict-flip line stripped) --"

MUT_R3I2="$SCRATCH/catchset_compare_mut_r3i2.py"
cp "$TOOL" "$MUT_R3I2"
# catchset_compare.py resolves its sibling gate_audit.py via its OWN
# directory (os.path.dirname(os.path.abspath(__file__))) -- give the
# mutated copy the same sibling so that import still resolves.
cp "$FC/gates/gate_audit.py" "$SCRATCH/gate_audit.py"
python3 - "$MUT_R3I2" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()
target_if = '        if did not in named_defects:\n'
target_append = '            named_defects.append(did)\n'
hits = [i for i in range(len(lines) - 1) if lines[i] == target_if and lines[i + 1] == target_append]
if len(hits) != 1:
    sys.stderr.write("expected exactly 1 occurrence of the R3-I2 fix lines, found %d\n" % len(hits))
    sys.exit(1)
i = hits[0]
lines[i] = "        pass  # T085-R3-I2-MUTATION: verdict-flip stripped\n"
lines[i + 1] = ""
with open(path, "w") as f:
    f.writelines(lines)
PYEOF
if [ $? -ne 0 ]; then
    bad "R4 mutation setup: could not uniquely locate the R3-I2 fix lines in a fresh copy"
else
    ok "R4 mutation setup: R3-I2 fix lines uniquely located and stripped in a scratch copy"

    MUT_OUT=$(python3 "$MUT_R3I2" compare --config "$SCRATCH/fastcycle.yaml" \
        --corpus "$SCRATCH/corpus.json" --old "$SCRATCH/old_manifest.json" --new "$SCRATCH/new_manifest.json" \
        --workdir "$SCRATCH/workdir/r4" --out "$SCRATCH/r4_out.json" 2>&1)
    MUT_RC=$?

    if [ "$MUT_RC" -eq 0 ] && [ -f "$SCRATCH/r4_out.json" ]; then
        MUT_SUPERSET=$(python3 -c "import json; print(json.load(open('$SCRATCH/r4_out.json')).get('superset'))")
        if [ "$MUT_SUPERSET" = "True" ]; then
            ok "R4: mutation-flip -- with the R3-I2 fix lines stripped, this EXACT scenario reverts to rc=0 superset=True (the pre-R3-I2 bug), confirming R1b's guard is genuinely load-bearing"
        else
            bad "R4: mutation-flip FAILED -- stripping the fix lines did not revert superset to True (got $MUT_SUPERSET); the test cannot distinguish fixed from broken"
        fi
    else
        bad "R4: mutated tool invocation failed unexpectedly (rc=$MUT_RC): $MUT_OUT"
    fi
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
