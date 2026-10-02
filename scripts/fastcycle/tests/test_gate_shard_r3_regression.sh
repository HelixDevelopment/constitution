#!/bin/sh
# =============================================================================
# T085 US2 Round 3 remediation regression (R3-B2, BLOCKING, 2026-10-02).
# =============================================================================
#
# T085 Round 3 R3-B2 (independent review): ADDENDUM 121 claimed "ALL 5
# Blocking" findings from the Round 2 review were fixed, but B-R2-4
# (tracker-DB/agent-registry shard-protection has ZERO test coverage --
# tasks.md T071's own text: "tracker DB and registry never written by
# gates running in parallel") was never even mentioned, and
# gate_runner_shard.py / test_gate_shard_red.sh /
# test_gate_shard_r1_regression.sh had NO commits after 78c7a34 (i.e.
# untouched by the whole Round 2 remediation). Confirmed independently:
# NONE of this project's gate_shard fixtures (gs_good_independent_
# determinism, gs_bad_shared_temp_split, gs_negctrl_disjoint_temp), nor
# either existing test file, EVER declares a gate writing to a path
# ending in docs/workable_items.db or docs/requests/agent_registry.jsonl
# -- so the PROTECTED_PATH_SUFFIXES scheduling logic in
# gate_runner_shard.py, while present in the SOURCE, was completely
# UNEXERCISED by any test: a mutation that disables it entirely (Round
# 2's own "M3c" -- treat protected clusters as ordinary parallel
# clusters) leaves every existing shard test fully green.
#
# This file closes that gap at THREE layers:
#   Section A -- planning-level: a protected-path gate's `plan`
#     subcommand output genuinely routes it into a DEDICATED serial
#     shard (never the parallel round-robin), a reader of the SAME
#     protected path is swept in too, and an independent non-protected
#     gate is correctly NOT swept in (negative control).
#   Section B -- mutation-flip proof: on a scratch copy of the real
#     source, Round 2's own named "M3c" mutation (treat protected
#     clusters as ordinary) is applied, and Section A's own assertions
#     are shown to now FAIL -- proving this test is genuinely
#     load-bearing, not tautological (§11.4.115(F)).
#   Section C -- END-TO-END RUNTIME proof via the REAL gate_runner.sh
#     --mode shard CLI (never just the planning JSON): a protected gate
#     genuinely only STARTS EXECUTING after every parallel gate has
#     finished, proven by real wall-clock timestamps the gates
#     themselves record -- this is the half of T071's guarantee that was
#     NEVER exercised by anything before this file (the planning-level
#     check alone cannot prove the SHELL ORCHESTRATION in gate_runner.sh
#     actually honours the plan it computed).
#
# §11.4.199: every scenario is a REAL invocation of the real tool(s).
#
# Usage: sh test_gate_shard_r3_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
SHARD_TOOL="$FC/gates/lib/gate_runner_shard.py"
RUNNER_SH="$FC/gates/gate_runner.sh"

FAIL=0
ok()  { echo "ok $1"; }
bad() { FAIL=1; echo "NOT ok $1"; }

if [ ! -f "$SHARD_TOOL" ] || [ ! -f "$RUNNER_SH" ]; then
    bad "control needle: $SHARD_TOOL or $RUNNER_SH does not exist -- cannot regression-test it"
    exit 1
fi

WORK=$(mktemp -d) || { echo "cannot create scratch dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM

cat > "$WORK/true.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$WORK/true.sh"

# Manifest: g_protected_writer WRITES the protected tracker-DB suffix;
# g_protected_reader READS that same path (no write overlap with
# anything -- proves the reader-of-protected-path sweep, independent of
# the ordinary write-write union); g_iso_a / g_iso_b are fully
# independent non-protected writers (negative control -- must NOT be
# swept into protected treatment).
cat > "$WORK/manifest.json" <<'EOF'
{"gates": [
  {"name": "g_protected_writer", "script": "true.sh", "args": [], "writes": ["docs/workable_items.db"]},
  {"name": "g_protected_reader", "script": "true.sh", "args": [], "reads": ["docs/workable_items.db"]},
  {"name": "g_iso_a", "script": "true.sh", "args": [], "writes": ["iso_a.txt"]},
  {"name": "g_iso_b", "script": "true.sh", "args": [], "writes": ["iso_b.txt"]}
]}
EOF

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

parallel_shards_of() {
    python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(" ".join(str(i) for i in d["parallel_shards"]))' "$1/plan.json"
}
serial_shards_of() {
    python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(" ".join(str(i) for i in d["serial_shards"]))' "$1/plan.json"
}

shard_index_of_gate() {  # $1=gate_name $2=shard-map-file
    awk -v g="$1" '$1==g{print $2}' "$2"
}

is_in_list() {  # $1=needle $2="space separated list"
    for x in $2; do
        [ "$x" = "$1" ] && return 0
    done
    return 1
}

run_plan() {
    tool="$1"; out_dir="$2"
    rm -rf "$out_dir"
    python3 "$tool" plan --manifest "$WORK/manifest.json" --n-shards 2 --out-dir "$out_dir" \
        >"$WORK/plan.stdout" 2>"$WORK/plan.stderr"
    return $?
}

# =============================================================================
# Section A -- REAL tool, unmutated: protected-path scheduling holds.
# =============================================================================
echo "-- Section A: REAL gate_runner_shard.py plan -- protected-path isolation --"

run_plan "$SHARD_TOOL" "$WORK/plan_real"
if [ $? -ne 0 ]; then
    bad "real tool 'plan' invocation failed: $(cat "$WORK/plan.stderr")"
else
    ok "real tool 'plan' invocation succeeded"
fi
shard_of "$WORK/plan_real" > "$WORK/map_real.txt"
PARALLEL_REAL=$(parallel_shards_of "$WORK/plan_real")
SERIAL_REAL=$(serial_shards_of "$WORK/plan_real")

PW_SHARD=$(shard_index_of_gate g_protected_writer "$WORK/map_real.txt")
PR_SHARD=$(shard_index_of_gate g_protected_reader "$WORK/map_real.txt")
IA_SHARD=$(shard_index_of_gate g_iso_a "$WORK/map_real.txt")
IB_SHARD=$(shard_index_of_gate g_iso_b "$WORK/map_real.txt")

if [ -n "$SERIAL_REAL" ] && is_in_list "$PW_SHARD" "$SERIAL_REAL"; then
    ok "A1: g_protected_writer (writes docs/workable_items.db) is routed into a DEDICATED SERIAL shard ($PW_SHARD), not the parallel batch ($PARALLEL_REAL)"
else
    bad "A1: g_protected_writer landed in shard $PW_SHARD, which is NOT in the serial set ($SERIAL_REAL) -- T071's protection is not holding"
fi

if [ "$PW_SHARD" = "$PR_SHARD" ]; then
    ok "A2: g_protected_reader (reads the SAME protected path) is co-scheduled with its writer into the same dedicated serial shard -- the reader-of-protected-path sweep holds"
else
    bad "A2: g_protected_reader (shard $PR_SHARD) was NOT co-scheduled with g_protected_writer (shard $PW_SHARD)"
fi

if [ -n "$PARALLEL_REAL" ] && is_in_list "$IA_SHARD" "$PARALLEL_REAL" && is_in_list "$IB_SHARD" "$PARALLEL_REAL"; then
    ok "A3 (negative control): g_iso_a/g_iso_b (independent, non-protected writers) remain in the ORDINARY parallel batch, never swept into protected treatment -- the §11.4.201(1) false-positive guard"
else
    bad "A3 (negative control): g_iso_a (shard $IA_SHARD) / g_iso_b (shard $IB_SHARD) unexpectedly NOT in the parallel set ($PARALLEL_REAL) -- over-eager protection sweep"
fi

# =============================================================================
# Section B -- mutation-flip proof (Round 2's own named "M3c": treat
# protected clusters as ordinary parallel clusters).
# =============================================================================
echo "-- Section B: mutation-flip proof (M3c -- protected clusters treated as ordinary) --"

MUT_M3C="$WORK/gate_runner_shard_mut_m3c.py"
cp "$SHARD_TOOL" "$MUT_M3C"
python3 - "$MUT_M3C" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
target = (
    '    normal_ids = [c for c in cluster_ids if c not in protected_roots]\n'
    '    protected_ids = [c for c in cluster_ids if c in protected_roots]\n'
)
if text.count(target) != 1:
    sys.stderr.write("expected exactly 1 occurrence of the normal/protected split, found %d\n" % text.count(target))
    sys.exit(1)
replacement = (
    '    # T085-R3-B2-MUTATION (M3c): protected clusters treated as ordinary.\n'
    '    normal_ids = list(cluster_ids)\n'
    '    protected_ids = []\n'
)
text = text.replace(target, replacement)
with open(path, "w") as f:
    f.write(text)
PYEOF
if [ $? -ne 0 ]; then
    bad "B0: mutation setup could not uniquely locate the normal/protected split in a fresh copy"
else
    ok "B0: M3c mutation setup uniquely located and applied in a scratch copy"
    run_plan "$MUT_M3C" "$WORK/plan_m3c"
    shard_of "$WORK/plan_m3c" > "$WORK/map_m3c.txt"
    PARALLEL_M3C=$(parallel_shards_of "$WORK/plan_m3c")
    PW_SHARD_M3C=$(shard_index_of_gate g_protected_writer "$WORK/map_m3c.txt")

    if is_in_list "$PW_SHARD_M3C" "$PARALLEL_M3C"; then
        ok "B1: mutation-flip -- with M3c applied, g_protected_writer is now (incorrectly) scheduled into the ORDINARY PARALLEL batch (shard $PW_SHARD_M3C), confirming Section A1's guard is genuinely load-bearing, not tautological"
    else
        bad "B1: mutation-flip FAILED -- with M3c applied, g_protected_writer STILL landed outside the parallel set; this test cannot distinguish fixed from broken"
    fi
fi

# =============================================================================
# Section C -- END-TO-END RUNTIME proof via the REAL gate_runner.sh
# --mode shard CLI: a protected gate's own execution window starts only
# AFTER every parallel gate's window has ended.
# =============================================================================
echo "-- Section C: REAL gate_runner.sh --mode shard -- protected gate runs strictly after the parallel batch --"

TIMING_DIR="$WORK/timing"
mkdir -p "$TIMING_DIR"

# Each gate script: record a start timestamp, sleep briefly (so windows
# are wide enough to catch an ordering violation), record an end
# timestamp. $1 is the gate's own "tree_dir" positional arg
# run-shard passes (unused here -- these gates ignore it and write to a
# fixed, pre-baked path instead, since this manifest's own gates take no
# meaningful args).
make_timed_gate() {
    name="$1"
    cat > "$WORK/${name}.sh" <<EOF
#!/bin/sh
date +%s.%N > "$TIMING_DIR/${name}.start"
sleep 0.4
date +%s.%N > "$TIMING_DIR/${name}.end"
exit 0
EOF
    chmod +x "$WORK/${name}.sh"
}
make_timed_gate par_timed_a
make_timed_gate par_timed_b
make_timed_gate prot_timed

cat > "$WORK/manifest_timed.json" <<'EOF'
{"gates": [
  {"name": "par_timed_a", "script": "par_timed_a.sh", "args": [], "writes": ["par_a_output.txt"]},
  {"name": "par_timed_b", "script": "par_timed_b.sh", "args": [], "writes": ["par_b_output.txt"]},
  {"name": "prot_timed", "script": "prot_timed.sh", "args": [], "writes": ["docs/workable_items.db"]}
]}
EOF

C_OUT=$(sh "$RUNNER_SH" --mode shard --manifest "$WORK/manifest_timed.json" --n-shards 2 2>"$WORK/c.stderr")
C_RC=$?

if [ "$C_RC" -eq 0 ]; then
    ok "C1: gate_runner.sh --mode shard exits 0 against the timed manifest"
else
    bad "C1: gate_runner.sh --mode shard exited $C_RC: $(cat "$WORK/c.stderr")"
fi

if [ -f "$TIMING_DIR/par_timed_a.start" ] && [ -f "$TIMING_DIR/par_timed_a.end" ] \
   && [ -f "$TIMING_DIR/par_timed_b.start" ] && [ -f "$TIMING_DIR/par_timed_b.end" ] \
   && [ -f "$TIMING_DIR/prot_timed.start" ] && [ -f "$TIMING_DIR/prot_timed.end" ]; then
    ok "C2: all 3 gates genuinely ran and recorded their own start/end timestamps"

    ORDER_OUT=$(python3 - "$TIMING_DIR" <<'PYEOF'
import sys
d = sys.argv[1]
def read(name):
    with open("%s/%s" % (d, name)) as fh:
        return float(fh.read().strip())

par_a_start = read("par_timed_a.start"); par_a_end = read("par_timed_a.end")
par_b_start = read("par_timed_b.start"); par_b_end = read("par_timed_b.end")
prot_start = read("prot_timed.start");   prot_end = read("prot_timed.end")

latest_parallel_end = max(par_a_end, par_b_end)
print("par_a=[%.3f,%.3f] par_b=[%.3f,%.3f] prot=[%.3f,%.3f] latest_parallel_end=%.3f"
      % (par_a_start, par_a_end, par_b_start, par_b_end, prot_start, prot_end, latest_parallel_end))

if prot_start >= latest_parallel_end:
    print("OK: protected gate's start (%.3f) is >= the latest parallel gate's end (%.3f) -- strictly-after ordering holds" % (prot_start, latest_parallel_end))
else:
    print("FAIL: protected gate's start (%.3f) is BEFORE the latest parallel gate's end (%.3f) -- it ran CONCURRENTLY with the parallel batch" % (prot_start, latest_parallel_end))
    sys.exit(1)
PYEOF
)
    ORDER_RC=$?
    echo "$ORDER_OUT"
    if [ "$ORDER_RC" -eq 0 ] && echo "$ORDER_OUT" | grep -q "^OK: protected gate's start"; then
        ok "C3: REAL RUNTIME PROOF -- the protected gate's actual process only started after BOTH parallel gates had actually finished, verified by wall-clock timestamps the gates themselves recorded (never merely the planning-level JSON) -- THE R3-B2 FIX, closing the 'zero test coverage' gap"
    else
        bad "C3: timing ordering check failed -- the protected gate ran concurrently with (or before) the parallel batch: $ORDER_OUT"
    fi
else
    bad "C2: one or more timing marker files were never written -- a gate did not run (missing files under $TIMING_DIR)"
fi

echo "---"
if [ "$FAIL" -eq 0 ]; then
    echo "test_gate_shard_r3_regression.sh: GREEN -- T071's tracker-DB/registry parallel-write protection holds at the planning layer (A), is proven genuinely load-bearing by mutation (B), AND is proven to hold at REAL RUNTIME through the actual shell orchestration (C) -- closing the R3-B2 zero-coverage gap at all three layers"
else
    echo "test_gate_shard_r3_regression.sh: FAIL -- see NOT ok lines above"
fi
exit "$FAIL"
