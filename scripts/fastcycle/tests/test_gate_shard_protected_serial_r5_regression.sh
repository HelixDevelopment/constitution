#!/bin/sh
# =============================================================================
# T085 US2 Round 5 remediation regression (Minor finding 2, 2026-10-02).
# =============================================================================
#
# T085 Round 4's independent review, Minor finding 2: "Serial-shard
# coverage: nothing tests that the protected serial shards run one at a
# time. Making them concurrent (& + wait) passes test_gate_shard_r3 9/9;
# the source itself is correct."
#
# gate_runner.sh's own protected-shard loop (`for i in $serial_idx; do
# ... done`, a plain sequential shell for-loop) is genuinely correct --
# this file closes the COVERAGE gap the review named: a REAL end-to-end
# runtime proof, via gate_runner.sh's own --mode shard CLI, that TWO
# PROTECTED (tracker-DB-writing) gates' own execution windows NEVER
# overlap each other -- not merely that a protected gate runs after the
# parallel batch (test_gate_shard_r3_regression.sh's own Section C,
# which this file complements rather than duplicates).
#
# §11.4.199: a real invocation of the real tool, never a bare unit-level
# stand-in.
#
# Usage: sh test_gate_shard_protected_serial_r5_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
RUNNER_SH="$FC/gates/gate_runner.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "ok $1"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $1"; }

if [ ! -f "$RUNNER_SH" ]; then
    bad "control needle: $RUNNER_SH does not exist -- cannot regression-test it"
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

echo "== T085 Round 5 Minor-2 regression: TWO protected (tracker-DB-writing) shards never overlap each other =="

TIMING_DIR="$WORK/timing"
mkdir -p "$TIMING_DIR"

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
# The two gates write to DIFFERENT PROTECTED_PATH_SUFFIXES
# (docs/workable_items.db vs docs/requests/agent_registry.jsonl) -- each
# independently classifies PROTECTED (serial), and since their write
# sets do NOT intersect, the shard planner's union-find clustering does
# NOT merge them into the SAME shard (confirmed: plan.json reports TWO
# distinct serial_shards indices for this exact manifest shape) -- this
# is deliberate: it is gate_runner.sh's own OUTER for-loop over
# serial_idx (iterating across DISTINCT shards) this test exercises, not
# gate_runner_shard.py's inner per-shard for-loop (which is a bog-
# standard sequential Python loop and was never in question -- two
# gates sharing ONE protected path land in the SAME shard and are
# trivially serial by construction, exercising nothing about the OUTER
# loop under test here).
make_timed_gate prot_timed_x
make_timed_gate prot_timed_y
# A genuinely disjoint parallel gate too, so this manifest exercises the
# realistic mixed shape (not an all-protected manifest, which would be a
# weaker/less representative test).
make_timed_gate par_timed_z

cat > "$WORK/manifest_dual_protected.json" <<'EOF'
{"gates": [
  {"name": "prot_timed_x", "script": "prot_timed_x.sh", "args": [], "writes": ["docs/workable_items.db"]},
  {"name": "prot_timed_y", "script": "prot_timed_y.sh", "args": [], "writes": ["docs/requests/agent_registry.jsonl"]},
  {"name": "par_timed_z", "script": "par_timed_z.sh", "args": [], "writes": ["par_z_output.txt"]}
]}
EOF

sh "$RUNNER_SH" --mode shard --manifest "$WORK/manifest_dual_protected.json" --n-shards 2 >/dev/null 2>"$WORK/c.stderr"
C_RC=$?

if [ "$C_RC" -eq 0 ]; then
    ok "C1: gate_runner.sh --mode shard exits 0 against the dual-protected-gate manifest"
else
    bad "C1: gate_runner.sh --mode shard exited $C_RC: $(cat "$WORK/c.stderr")"
fi

if [ -f "$TIMING_DIR/prot_timed_x.start" ] && [ -f "$TIMING_DIR/prot_timed_x.end" ] \
   && [ -f "$TIMING_DIR/prot_timed_y.start" ] && [ -f "$TIMING_DIR/prot_timed_y.end" ]; then
    ok "C2: both protected gates genuinely ran and recorded their own start/end timestamps"

    ORDER_OUT=$(python3 - "$TIMING_DIR" <<'PYEOF'
import sys
d = sys.argv[1]
def read(name):
    with open("%s/%s" % (d, name)) as fh:
        return float(fh.read().strip())

x_start = read("prot_timed_x.start"); x_end = read("prot_timed_x.end")
y_start = read("prot_timed_y.start"); y_end = read("prot_timed_y.end")

print("x=[%.3f,%.3f] y=[%.3f,%.3f]" % (x_start, x_end, y_start, y_end))

# Two intervals overlap iff x_start < y_end AND y_start < x_end.
overlap = x_start < y_end and y_start < x_end
if not overlap:
    print("OK: the two protected gates' execution windows do NOT overlap -- genuine one-at-a-time serial execution")
else:
    print("FAIL: the two protected gates' execution windows OVERLAP -- they ran CONCURRENTLY, violating tasks.md T071's 'never overlapping' guarantee")
PYEOF
)
    echo "$ORDER_OUT"
    if echo "$ORDER_OUT" | grep -q "^OK: "; then
        ok "C3: REAL RUNTIME PROOF -- the two protected (tracker-DB-writing) gates' execution windows never overlap each other, verified by wall-clock timestamps the gates themselves recorded -- closes the Minor-2 coverage gap"
    else
        bad "C3: $ORDER_OUT"
    fi
else
    bad "C2: one or both protected gates' timing files were never written"
fi

# =============================================================================
# Section D -- guard-viability (11.4.115(F)): proves THIS test genuinely
# catches a regression to concurrent protected-shard execution -- a
# scratch copy with gate_runner.sh's serial for-loop replaced by a
# background-and-wait pattern (the reviewer's own "& + wait" mutation)
# must make Section C's own check FAIL.
# =============================================================================
echo "-- Section D: guard-viability -- a scratch copy backgrounding the protected loop must FAIL Section C's own check --"

SCRATCH="$WORK/scratch_mutated"
mkdir -p "$SCRATCH"
cp "$RUNNER_SH" "$SCRATCH/gate_runner.sh"
# gate_runner.sh resolves $SHARD_LIB relative to its OWN location
# ($HERE/lib/gate_runner_shard.py, $HERE=dirname($0)) and $HOST_GUARD
# relative to ITS PARENT ($FC/lib/host_guard.sh, $FC=$HERE/..) -- the
# scratch copy needs BOTH sibling lib/ directories in the SAME relative
# shape gate_runner.sh's real deployment has, or every invocation fails
# with "not found" before the mutation under test is ever exercised.
ln -s "$FC/gates/lib" "$SCRATCH/lib"
ln -s "$FC/lib" "$WORK/lib"

python3 - "$SCRATCH/gate_runner.sh" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()

old = (
    '    for i in $serial_idx; do\n'
    '        python3 "$SHARD_LIB" run-shard \\\n'
    '            --manifest "$manifest" --shard-file "$workdir/shard_$i.json" --out "$workdir/result_$i.json"\n'
    '    done\n'
)
new = (
    '    # GUARD-VIABILITY MUTATION: protected shards backgrounded + waited\n'
    '    # on together (the reviewer\'s own "& + wait" example), restoring\n'
    '    # the concurrent-execution hazard the serial for-loop exists to\n'
    '    # prevent.\n'
    '    for i in $serial_idx; do\n'
    '        python3 "$SHARD_LIB" run-shard \\\n'
    '            --manifest "$manifest" --shard-file "$workdir/shard_$i.json" --out "$workdir/result_$i.json" &\n'
    '    done\n'
    '    wait\n'
)
if c.count(old) != 1:
    sys.exit("mutate: serial for-loop source did not match exactly once (count=%d)" % c.count(old))
c = c.replace(old, new, 1)

with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
MUTATE_RC=$?

if [ "$MUTATE_RC" -ne 0 ]; then
    bad "D setup: could not apply the backgrounding mutation to the scratch copy -- the serial loop's exact source shape must have changed; this guard needs updating to match"
else
    ok "D setup: scratch copy mutated -- protected shards now backgrounded (& + wait), every other line untouched"

    rm -rf "$TIMING_DIR"
    mkdir -p "$TIMING_DIR"
    sh "$SCRATCH/gate_runner.sh" --mode shard --manifest "$WORK/manifest_dual_protected.json" --n-shards 2 \
        >/dev/null 2>"$WORK/d.stderr"

    if [ -f "$TIMING_DIR/prot_timed_x.start" ] && [ -f "$TIMING_DIR/prot_timed_x.end" ] \
       && [ -f "$TIMING_DIR/prot_timed_y.start" ] && [ -f "$TIMING_DIR/prot_timed_y.end" ]; then
        D_OUT=$(python3 - "$TIMING_DIR" <<'PYEOF'
import sys
d = sys.argv[1]
def read(name):
    with open("%s/%s" % (d, name)) as fh:
        return float(fh.read().strip())
x_start = read("prot_timed_x.start"); x_end = read("prot_timed_x.end")
y_start = read("prot_timed_y.start"); y_end = read("prot_timed_y.end")
overlap = x_start < y_end and y_start < x_end
print("MUTATED_OVERLAP=%s x=[%.3f,%.3f] y=[%.3f,%.3f]" % (overlap, x_start, x_end, y_start, y_end))
PYEOF
)
        echo "$D_OUT"
        if echo "$D_OUT" | grep -q "^MUTATED_OVERLAP=True"; then
            ok "D: with the serial loop mutated to background+wait, the two protected gates' windows DO overlap -- proving Section C's check genuinely catches this regression, it is not a tautology"
        else
            bad "D: expected the mutated copy to produce overlapping windows, got: $D_OUT (the mutation may not have taken effect, or xargs/system scheduling happened to still serialise them on this run)"
        fi
    else
        bad "D: one or both protected gates' timing files were never written under the mutated copy"
    fi
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
