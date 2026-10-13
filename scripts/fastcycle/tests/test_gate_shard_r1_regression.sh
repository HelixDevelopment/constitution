#!/bin/sh
# =============================================================================
# T085 Round 1 regression test (SpecKit-004 "fast-dev-cycles", User Story
# 2; guards constitution/scripts/fastcycle/gates/lib/gate_runner_shard.py's
# _union_find_clusters()).
# =============================================================================
#
# Purpose: prove, against the REAL tool (never the tests/lib/shard_ref.py
# mock T063's own evidence text wrongly credited with covering this),
# that _union_find_clusters() genuinely co-schedules BOTH:
#   (I4) two gates whose WRITE sets intersect (the class T085 Round 1's
#        I4 finding proved the mock-only test_gate_shard_red.sh's own
#        Section B never actually exercises against the real tool --
#        reviewer-reverted `union()` at the write-write pass survived
#        T055 12/12 PASS x3), and
#   (I3) a gate that READS a path another gate WRITES (the class T085
#        Round 1's I3 finding identified as entirely unimplemented before
#        this round: reads were never consulted at all).
#
# Each of the two co-scheduling mechanisms is proven load-bearing by a
# REAL mutation applied to a SCRATCH COPY of the real source file (never
# the tracked file itself) -- the specific `union()` call line the
# mechanism depends on is commented out, the REAL tool (run from that
# mutated copy) is invoked again, and the test asserts the expected
# co-scheduling now FAILS to hold. A mutation whose absence this test
# cannot detect would be a tautological/vacuous regression guard
# (§11.4.115(F)) -- this file proves each mutation is genuinely caught,
# not merely asserts a static claim.
#
# A negative control (two gates with fully disjoint write sets and no
# read/write overlap with anything) proves the test does not vacuously
# report "co-scheduled" for every pair regardless of input (the
# §11.4.201(1) false-positive guard).
#
# Usage: sh test_gate_shard_r1_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/lib/gate_runner_shard.py"

FAIL=0
ok()  { echo "ok $1"; }
bad() { FAIL=1; echo "NOT ok $1"; }

if [ ! -f "$TOOL" ]; then
    bad "control needle: $TOOL does not exist -- cannot regression-test it"
    exit 1
fi

WORK=$(mktemp -d) || { echo "cannot create scratch dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/true.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$WORK/true.sh"

# Manifest exercising BOTH mechanisms at once, plus a negative control:
#   writer_x / writer_y  -- WRITE-WRITE intersection on shared_w.txt (I4)
#   writer_z / reader_r  -- WRITE (writer_z) vs READ (reader_r) on
#                            shared_wr.txt, no write-write overlap at all
#                            with anything (I3)
#   iso_a / iso_b         -- fully disjoint writers, no overlap with
#                            anything -- MUST land in different shards
#                            when n_shards >= 2 (negative control)
cat > "$WORK/manifest.json" <<'EOF'
{"gates": [
  {"name": "writer_x", "script": "true.sh", "args": [], "writes": ["shared_w.txt"]},
  {"name": "writer_y", "script": "true.sh", "args": [], "writes": ["shared_w.txt"]},
  {"name": "writer_z", "script": "true.sh", "args": [], "writes": ["shared_wr.txt"]},
  {"name": "reader_r", "script": "true.sh", "args": [], "reads": ["shared_wr.txt"]},
  {"name": "iso_a", "script": "true.sh", "args": [], "writes": ["iso_a.txt"]},
  {"name": "iso_b", "script": "true.sh", "args": [], "writes": ["iso_b.txt"]}
]}
EOF

# shard_of <plan-out-dir> -- prints "gate_name shard_index" lines by
# reading every shard_<i>.json the real tool's `plan` subcommand wrote.
shard_of() {
    out_dir="$1"
    for f in "$out_dir"/shard_*.json; do
        [ -f "$f" ] || continue
        python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for g in d["gates"]:
    print(g["name"], d["shard"])
' "$f"
    done
}

run_plan() {
    tool="$1"; out_dir="$2"
    rm -rf "$out_dir"
    python3 "$tool" plan --manifest "$WORK/manifest.json" --n-shards 3 --out-dir "$out_dir" \
        >"$WORK/plan.stdout" 2>"$WORK/plan.stderr"
    return $?
}

same_shard() {  # $1=gate_name_a $2=gate_name_b $3=shard-map-file
    a_shard=$(awk -v g="$1" '$1==g{print $2}' "$3")
    b_shard=$(awk -v g="$2" '$1==g{print $2}' "$3")
    [ -n "$a_shard" ] && [ -n "$b_shard" ] && [ "$a_shard" = "$b_shard" ]
}

# =============================================================================
# Section A -- REAL tool, unmutated: both co-scheduling mechanisms hold,
# plus the negative control.
# =============================================================================
run_plan "$TOOL" "$WORK/plan_real"
if [ $? -ne 0 ]; then
    bad "real tool 'plan' invocation failed (rc=$?): $(cat "$WORK/plan.stderr")"
else
    ok "real tool 'plan' invocation succeeded"
fi
shard_of "$WORK/plan_real" > "$WORK/map_real.txt"

if same_shard writer_x writer_y "$WORK/map_real.txt"; then
    ok "I4: writer_x/writer_y (write-write intersection on shared_w.txt) co-scheduled"
else
    bad "I4: writer_x/writer_y did NOT co-schedule (write-write union broken)"
fi

if same_shard writer_z reader_r "$WORK/map_real.txt"; then
    ok "I3: writer_z/reader_r (write-vs-read intersection on shared_wr.txt) co-scheduled"
else
    bad "I3: writer_z/reader_r did NOT co-schedule (write-read union missing/broken)"
fi

if same_shard iso_a iso_b "$WORK/map_real.txt"; then
    bad "negative control: iso_a/iso_b (fully disjoint) were co-scheduled -- the test vacuously reports co-scheduling for every pair"
else
    ok "negative control: iso_a/iso_b (fully disjoint writers) correctly landed in DIFFERENT shards"
fi

# =============================================================================
# Section B -- mutation-flip proof (I4): strip the write-write union()
# call on a SCRATCH COPY of the real source (never the tracked file), and
# confirm the I4 co-scheduling assertion NOW FAILS to hold.
# =============================================================================
MUT_I4="$WORK/gate_runner_shard_mut_i4.py"
cp "$TOOL" "$MUT_I4"
# The exact line this fix added, targeted uniquely by its own literal
# text (never a line-number guess -- §11.4.6): the write-write union call
# inside the FIRST (writes) loop of _union_find_clusters().
python3 - "$MUT_I4" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()
target = '                union(g["name"], write_owner[path])\n'
hits = [i for i, l in enumerate(lines) if l == target]
if len(hits) != 1:
    sys.stderr.write(f"expected exactly 1 occurrence of the write-write union() line, found {len(hits)}\n")
    sys.exit(1)
lines[hits[0]] = '                pass  # T085-R1-I4-MUTATION: union() stripped\n'
with open(path, "w") as f:
    f.writelines(lines)
PYEOF
if [ $? -ne 0 ]; then
    bad "I4 mutation setup: could not locate the write-write union() line uniquely in a fresh copy"
else
    ok "I4 mutation setup: write-write union() line uniquely located and stripped in scratch copy"
    run_plan "$MUT_I4" "$WORK/plan_i4mut"
    shard_of "$WORK/plan_i4mut" > "$WORK/map_i4mut.txt"
    if same_shard writer_x writer_y "$WORK/map_i4mut.txt"; then
        bad "I4 mutation-flip: writer_x/writer_y STILL co-scheduled with the write-write union() stripped -- this guard is NOT load-bearing (tautological)"
    else
        ok "I4 mutation-flip: writer_x/writer_y correctly STOP co-scheduling once the write-write union() is stripped -- guard is genuinely load-bearing"
    fi
fi

# =============================================================================
# Section C -- mutation-flip proof (I3): strip the write-vs-read union()
# call (the whole read pass this round's fix ADDED) on a fresh scratch
# copy, and confirm the I3 co-scheduling assertion NOW FAILS to hold.
# =============================================================================
MUT_I3="$WORK/gate_runner_shard_mut_i3.py"
cp "$TOOL" "$MUT_I3"
python3 - "$MUT_I3" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()
target = '                union(g["name"], owner)\n'
hits = [i for i, l in enumerate(lines) if l == target]
if len(hits) != 1:
    sys.stderr.write(f"expected exactly 1 occurrence of the write-read union() line, found {len(hits)}\n")
    sys.exit(1)
lines[hits[0]] = '                pass  # T085-R1-I3-MUTATION: union() stripped\n'
with open(path, "w") as f:
    f.writelines(lines)
PYEOF
if [ $? -ne 0 ]; then
    bad "I3 mutation setup: could not locate the write-read union() line uniquely in a fresh copy"
else
    ok "I3 mutation setup: write-read union() line uniquely located and stripped in scratch copy"
    run_plan "$MUT_I3" "$WORK/plan_i3mut"
    shard_of "$WORK/plan_i3mut" > "$WORK/map_i3mut.txt"
    if same_shard writer_z reader_r "$WORK/map_i3mut.txt"; then
        bad "I3 mutation-flip: writer_z/reader_r STILL co-scheduled with the write-read union() stripped -- this guard is NOT load-bearing (tautological)"
    else
        ok "I3 mutation-flip: writer_z/reader_r correctly STOP co-scheduling once the write-read union() is stripped -- guard is genuinely load-bearing"
    fi
fi

# =============================================================================
# Section D -- determinism: 3 independent 'plan' runs against the REAL
# (unmutated) tool produce byte-identical shard-assignment maps.
# =============================================================================
run_plan "$TOOL" "$WORK/plan_det1"; shard_of "$WORK/plan_det1" | sort > "$WORK/det1.txt"
run_plan "$TOOL" "$WORK/plan_det2"; shard_of "$WORK/plan_det2" | sort > "$WORK/det2.txt"
run_plan "$TOOL" "$WORK/plan_det3"; shard_of "$WORK/plan_det3" | sort > "$WORK/det3.txt"
if diff -q "$WORK/det1.txt" "$WORK/det2.txt" >/dev/null 2>&1 && diff -q "$WORK/det2.txt" "$WORK/det3.txt" >/dev/null 2>&1; then
    ok "determinism: 3 independent real 'plan' runs produce byte-identical shard assignments"
else
    bad "determinism: shard assignments differ across independent runs of the SAME manifest"
fi

echo "---"
if [ "$FAIL" -eq 0 ]; then
    echo "test_gate_shard_r1_regression.sh: GREEN -- I3 and I4 co-scheduling mechanisms both hold and are proven load-bearing"
else
    echo "test_gate_shard_r1_regression.sh: FAIL -- see NOT ok lines above"
fi
exit "$FAIL"
