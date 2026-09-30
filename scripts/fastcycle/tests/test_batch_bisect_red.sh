#!/bin/sh
# =============================================================================
# T056 RED test (SpecKit-004 "fast-dev-cycles", Phase 5 / User Story 2;
# plan.md T-C06; SC-002, FR-005).
# =============================================================================
#
# Purpose: prove, BEFORE the T-C06 implementation of
# `constitution/scripts/fastcycle/gates/batch_bisect.py` exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed -- §11.4.6);
#   (B) this file's own toy corpus (fixtures/batch_bisect/) is non-vacuous:
#       a real reference bisector (lib/bb_ref_bisect.py, a from-scratch
#       standalone helper that NEVER informs the real T-C06 implementation
#       -- the same role T051's lib/dec07_key_ref.py plays for its DEC-07
#       key formula) genuinely runs a real toy gate against real toy trees
#       and reproduces every fixture's expected.json exactly;
#   (C) task T056's three specifically-cited clauses are each covered by a
#       real, running check: (1) a seeded batch with one bad change ->
#       bisection names it, (2) per-change verdicts equal individual runs,
#       (3) two concurrent workers never receive each other's verdicts;
#   (D) the task's own named paired-mutation anti-pattern ("attribute the
#       batch verdict to every member -> the attribution fixture FAILs")
#       is proven caught, not merely asserted -- a real
#       "naive-attribution" computation is compared against the real
#       golden per-change map and shown to differ.
#
# Task line (tasks.md T056, verbatim): "RED test
# constitution/scripts/fastcycle/tests/test_batch_bisect_red.sh (seeded
# batch with one bad change -> bisection names it; per-change verdicts
# equal individual runs; two concurrent workers never receive each other's
# verdicts) (plan T-C06; SC-002, FR-005)".
#
# plan.md T-C06's own text: "gates/batch_bisect.py validates a batch of
# related changes in one gate run; on a FAIL it bisects to the culprit;
# per-change verdicts are recorded and must equal the individual-run
# verdicts; WIP caps per queue per DEC-21 set from T-A09 throughput."
#
# No dedicated contracts/*.md file exists for T-C06 as of this writing
# (checked: specs/004-fast-dev-cycles/contracts/ has no batch-bisect*.md;
# review-batch-and-precheck.md is a DIFFERENT contract, T-C11's review
# batching, not T-C06's gate-run batching). The CLI wire format below is
# therefore DEFINED here, UNCONFIRMED by any contract, binding-if-adopted
# -- the same established house precedent T051 followed for
# verdict_cache.py's wire format.
#
# Wire format for gates/batch_bisect.py (UNCONFIRMED, DEFINED here):
#   batch_bisect.py run --batch <batch.json> --base-tree <dir> \
#       --patches <dir> --gate <gate.sh> --out <result.json>
#   Exit 0 if batch_verdict == PASS, exit 1 if batch_verdict == FAIL
#   (bisection still runs and result.json is still written on FAIL -- exit
#   code communicates the batch OUTCOME, never whether bisection itself
#   succeeded). result.json schema: {"batch_verdict": "PASS"|"FAIL",
#   "per_change": {change_id: "PASS"|"FAIL", ...}, "culprits": [change_id, ...]}.
#   batch.json / expected.json schemas: see fixtures/batch_bisect/*/README.md.
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# the fixtures under fixtures/batch_bisect/ + the reference bisector at
# lib/bb_ref_bisect.py (all created in this same task). It does NOT
# implement gates/batch_bisect.py (T-C06's real implementation task, a
# separate later task), and never fabricates a tool invocation result --
# every claim below is either (a) a real reference-bisector run this file
# performs itself against real toy trees via subprocess, or (b) a real
# invocation of the (today, absent) real tool, reported RED because the
# tool cannot be found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected
#       FAIL>0 for every scenario's REAL-TOOL invocation check -- the
#       reference-bisector self-checks in Sections B-E are expected to
#       PASS today, since they exercise only this file's own toy corpus +
#       reference computation, never the absent real tool).

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/batch_bisect.py"
REF="$HERE/lib/bb_ref_bisect.py"
FIXDIR="$HERE/fixtures/batch_bisect"
BASE_TREE="$FIXDIR/_shared/base_tree"
PATCHES="$FIXDIR/_shared/patches"
GATE="$FIXDIR/_shared/gate.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T056 RED: batch validation + bisection (plan T-C06; SC-002, FR-005) =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption carried over from plan.md.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T-C06 has landed; Section F below (real"
    echo "   tool invocations) are the real functional tests to run"
else
    echo "RED: $TOOL is absent -- T-C06's gates/batch_bisect.py has not"
    echo "     landed yet, confirming this file's own premise is real, not"
    echo "     assumed"
fi

if [ -x "$GATE" ] && [ -f "$BASE_TREE/widget_a.sh" ] && [ -f "$PATCHES/change_c_bad.sh" ]; then
    ok "control needle: the toy corpus (gate.sh, base_tree/widget_{a,b,c}.sh, 3 patches) exists on disk, not merely claimed"
else
    bad "control needle FAILED: the toy corpus under $FIXDIR/_shared/ is incomplete -- Sections B-E below cannot be trusted"
fi

if ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- the reference bisector (Section B) cannot run"
elif [ ! -f "$REF" ]; then
    bad "reference bisector missing at $REF -- Sections B-E cannot run"
else
    ok "python3 + reference bisector ($REF) both present"
fi

# =============================================================================
# Section B -- reference bisector self-validation on the golden fixtures
# (§11.4.107(10)/§11.4.273): run the REAL toy gate against REAL toy trees
# and prove the two hand-authored expected.json files are non-vacuous --
# i.e. this fixture pair genuinely encodes "no culprit" and "chg-C is the
# culprit", not an assertion nobody ever computed.
# =============================================================================
check_scenario() {
    name=$1; batch_json=$2; exp_json=$3
    got=$(python3 "$REF" "$batch_json" "$BASE_TREE" "$PATCHES" "$GATE" 2>/dev/null)
    if [ -z "$got" ]; then
        bad "$name: reference bisector produced no output"
        return
    fi
    want_verdict=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['batch_verdict'])" "$exp_json" 2>/dev/null)
    got_verdict=$(printf '%s' "$got" | python3 -c "import json,sys; print(json.load(sys.stdin)['batch_verdict'])" 2>/dev/null)
    if [ "$want_verdict" = "$got_verdict" ]; then
        ok "$name: reference bisector's batch_verdict ($got_verdict) matches expected.json"
    else
        bad "$name: expected batch_verdict=$want_verdict but reference bisector computed $got_verdict"
    fi
    same_per_change=$(python3 -c "
import json,sys
want=json.load(open(sys.argv[1]))['per_change']
got=json.loads(sys.argv[2])['per_change']
print('1' if want==got else '0')
" "$exp_json" "$got" 2>/dev/null)
    if [ "$same_per_change" = 1 ]; then
        ok "$name: reference bisector's per_change map matches expected.json exactly"
    else
        bad "$name: reference bisector's per_change map does NOT match expected.json ($got)"
    fi
    same_culprits=$(python3 -c "
import json,sys
want=sorted(json.load(open(sys.argv[1]))['culprits'])
got=sorted(json.loads(sys.argv[2])['culprits'])
print('1' if want==got else '0')
" "$exp_json" "$got" 2>/dev/null)
    if [ "$same_culprits" = 1 ]; then
        ok "$name: reference bisector's culprits list matches expected.json exactly"
    else
        bad "$name: reference bisector's culprits list does NOT match expected.json ($got)"
    fi
}

check_scenario "bb_good_all_pass" "$FIXDIR/bb_good_all_pass/batch.json" "$FIXDIR/bb_good_all_pass/expected.json"
check_scenario "bb_bad_one_culprit" "$FIXDIR/bb_bad_one_culprit/batch.json" "$FIXDIR/bb_bad_one_culprit/expected.json"

# =============================================================================
# Section C -- task clause (2): "per-change verdicts equal individual runs".
# For each of chg-A, chg-B, chg-C, run it ALONE (an individually-sized
# batch of 1) through the reference bisector, and assert the resulting
# per-change verdict is IDENTICAL to bb_bad_one_culprit's per_change value
# for that same change -- proving the bisected verdict is not an artefact
# of which OTHER changes happened to share its batch.
# =============================================================================
INDIV_JSON="$FIXDIR/bb_per_change_matches_individual/individual_batches.json"
INDIV_EXP="$FIXDIR/bb_per_change_matches_individual/expected.json"
BATCH_EXP="$FIXDIR/bb_bad_one_culprit/expected.json"

if [ -f "$INDIV_JSON" ] && [ -f "$INDIV_EXP" ]; then
    n=$(python3 -c "import json; print(len(json.load(open('$INDIV_JSON'))['individual_batches']))")
    i=0
    all_match=1
    while [ "$i" -lt "$n" ]; do
        one_batch_json=$(mktemp)
        python3 -c "
import json
d=json.load(open('$INDIV_JSON'))['individual_batches'][$i]
json.dump(d, open('$one_batch_json','w'))
"
        cid=$(python3 -c "import json; print(json.load(open('$one_batch_json'))['changes'][0]['change_id'])")
        got=$(python3 "$REF" "$one_batch_json" "$BASE_TREE" "$PATCHES" "$GATE" 2>/dev/null)
        got_v=$(printf '%s' "$got" | python3 -c "import json,sys; print(json.load(sys.stdin)['batch_verdict'])" 2>/dev/null)
        rm -f "$one_batch_json"

        batch_v=$(python3 -c "import json; print(json.load(open('$BATCH_EXP'))['per_change'].get('$cid',''))")
        indiv_exp_v=$(python3 -c "import json; print(json.load(open('$INDIV_EXP'))['individual'].get('$cid',''))")

        if [ "$got_v" != "$batch_v" ] || [ "$got_v" != "$indiv_exp_v" ]; then
            bad "individual run of $cid: got=$got_v, bb_bad_one_culprit per_change=$batch_v, individual expected.json=$indiv_exp_v -- these three MUST all agree"
            all_match=0
        fi
        i=$((i+1))
    done
    if [ "$all_match" = 1 ]; then
        ok "individual-run verdicts for chg-A/chg-B/chg-C each equal their bisected per-change verdict inside bb_bad_one_culprit's batch (task clause: per-change verdicts equal individual runs)"
    fi
else
    bad "bb_per_change_matches_individual fixture files missing"
fi

# =============================================================================
# Section D -- task clause (3): "two concurrent workers never receive each
# other's verdicts". Launch two reference-bisector runs as REAL background
# subshells, each writing to a DISTINCT result file, wait for both, then
# assert: (i) each worker's own result matches its expected outcome, (ii)
# neither worker's result file contains the OTHER worker's change_id --
# the load-bearing cross-contamination check.
# =============================================================================
CONC_DIR="$FIXDIR/bb_concurrent_isolation"
if [ -f "$CONC_DIR/worker1_batch.json" ] && [ -f "$CONC_DIR/worker2_batch.json" ] && [ -f "$CONC_DIR/expected.json" ]; then
    R1=$(mktemp)
    R2=$(mktemp)
    ( python3 "$REF" "$CONC_DIR/worker1_batch.json" "$BASE_TREE" "$PATCHES" "$GATE" >"$R1" 2>/dev/null ) &
    W1PID=$!
    ( python3 "$REF" "$CONC_DIR/worker2_batch.json" "$BASE_TREE" "$PATCHES" "$GATE" >"$R2" 2>/dev/null ) &
    W2PID=$!
    wait "$W1PID"
    wait "$W2PID"

    w1_verdict=$(python3 -c "import json; print(json.load(open('$R1'))['batch_verdict'])" 2>/dev/null)
    w2_verdict=$(python3 -c "import json; print(json.load(open('$R2'))['batch_verdict'])" 2>/dev/null)
    w1_exp=$(python3 -c "import json; print(json.load(open('$CONC_DIR/expected.json'))['worker1']['batch_verdict'])")
    w2_exp=$(python3 -c "import json; print(json.load(open('$CONC_DIR/expected.json'))['worker2']['batch_verdict'])")

    if [ "$w1_verdict" = "$w1_exp" ]; then
        ok "concurrent worker1's real batch_verdict ($w1_verdict) matches expected"
    else
        bad "concurrent worker1's batch_verdict=$w1_verdict, expected=$w1_exp"
    fi
    if [ "$w2_verdict" = "$w2_exp" ]; then
        ok "concurrent worker2's real batch_verdict ($w2_verdict) matches expected"
    else
        bad "concurrent worker2's batch_verdict=$w2_verdict, expected=$w2_exp"
    fi

    if grep -q 'chg-C' "$R2" 2>/dev/null; then
        bad "ISOLATION VIOLATED: worker2's result file mentions chg-C (worker1's culprit) -- cross-contamination between concurrent workers"
    else
        ok "isolation: worker2's result file never mentions chg-C (worker1's own culprit stayed in worker1's own result)"
    fi
    if grep -q 'chg-B' "$R1" 2>/dev/null; then
        bad "ISOLATION VIOLATED: worker1's result file mentions chg-B (worker2's change) -- cross-contamination between concurrent workers"
    else
        ok "isolation: worker1's result file never mentions chg-B (worker2's own change stayed in worker2's own result)"
    fi
    rm -f "$R1" "$R2"
else
    bad "bb_concurrent_isolation fixture files missing"
fi

# =============================================================================
# Section E -- task's named paired-mutation anti-pattern, proven caught:
# "attribute the batch verdict to every member -> the attribution fixture
# FAILs". Compute the NAIVE (wrong) attribution explicitly and assert it
# does NOT equal the real golden per_change map -- a hypothetical
# batch_bisect.py that took this shortcut would therefore be caught by
# comparing its output against bb_bad_one_culprit/expected.json.
# =============================================================================
NEGCTRL="$FIXDIR/bb_negctrl_attribute_to_all/naive_attribution.json"
if [ -f "$NEGCTRL" ]; then
    naive_matches_golden=$(python3 -c "
import json
naive = json.load(open('$NEGCTRL'))['per_change']
golden = json.load(open('$BATCH_EXP'))['per_change']
print('1' if naive == golden else '0')
")
    if [ "$naive_matches_golden" = 0 ]; then
        ok "negative control: the naive 'attribute batch verdict to every member' output ({chg-A:FAIL,chg-B:FAIL,chg-C:FAIL}) does NOT match the real golden per_change map ({chg-A:PASS,chg-B:PASS,chg-C:FAIL}) -- comparing a real bisector's output against this fixture would CATCH that anti-pattern, satisfying task T056's own named paired-mutation clause"
    else
        bad "ANTI-PATTERN UNDETECTABLE: the naive attribution output accidentally equals the golden per_change map -- this fixture pair cannot distinguish genuine bisection from the attribute-to-all shortcut"
    fi
    naive_a=$(python3 -c "import json; print(json.load(open('$NEGCTRL'))['per_change']['chg-A'])")
    golden_a=$(python3 -c "import json; print(json.load(open('$BATCH_EXP'))['per_change']['chg-A'])")
    if [ "$naive_a" != "$golden_a" ]; then
        ok "named check: chg-A (a genuinely clean change) is wrongly reported FAIL by the naive attribution while the golden fixture correctly says PASS -- exactly the failure mode T056 names"
    else
        bad "named check: chg-A's naive-attribution value ($naive_a) accidentally matches golden ($golden_a) -- weakens the anti-pattern proof"
    fi
else
    bad "bb_negctrl_attribute_to_all/naive_attribution.json missing"
fi

# =============================================================================
# Section F -- the real functional checks: invoke $TOOL for every batch
# scenario. $TOOL is absent today, so every check below is the expected RED
# outcome, reported per-scenario (never collapsed into one opaque "tool
# missing" line), matching the established sibling convention
# (test_catchset_compare_red.sh, test_verdict_cache_red.sh).
# =============================================================================
for scen in bb_good_all_pass bb_bad_one_culprit; do
    scen_dir="$FIXDIR/$scen"
    if [ ! -f "$TOOL" ]; then
        bad "RED: $scen -- $TOOL is absent, cannot run batch_bisect.py run --batch $scen_dir/batch.json ..."
        continue
    fi
    OUT_JSON=$(mktemp)
    "$TOOL" run --batch "$scen_dir/batch.json" --base-tree "$BASE_TREE" --patches "$PATCHES" --gate "$GATE" --out "$OUT_JSON"
    rc=$?
    want_v=$(python3 -c "import json; print(json.load(open('$scen_dir/expected.json'))['batch_verdict'])")
    if [ "$want_v" = PASS ] && [ "$rc" -eq 0 ]; then
        ok "$scen: real tool exit code (0) matches expected batch_verdict=PASS"
    elif [ "$want_v" = FAIL ] && [ "$rc" -eq 1 ]; then
        ok "$scen: real tool exit code (1) matches expected batch_verdict=FAIL"
    else
        bad "$scen: real tool exit=$rc, expected batch_verdict=$want_v"
    fi

    # STRENGTHENED (T072, fixed forward per T056's own header: "Section F
    # below (real tool invocations) are the real functional tests to run"
    # -- this ADDS assertions, it removes/weakens none of the above).
    # The exit-code check alone cannot distinguish a genuine bisector from
    # the "attribute the batch verdict to every member" anti-pattern T056
    # itself names as the paired-mutation target: a naive implementation
    # that copies batch_verdict onto every change's per_change entry
    # produces the SAME exit code (batch_verdict, and therefore the exit
    # code, never depends on how per_change was computed) while reporting
    # every clean member as a false culprit. Directly comparing the real
    # tool's per_change/culprits against the golden expected.json closes
    # that gap -- the exact check this scenario's own expected.json exists
    # to make possible.
    if [ -s "$OUT_JSON" ]; then
        per_change_ok=$(python3 -c "
import json
want = json.load(open('$scen_dir/expected.json'))['per_change']
got = json.load(open('$OUT_JSON')).get('per_change')
print('1' if want == got else '0')
" 2>/dev/null)
        if [ "$per_change_ok" = 1 ]; then
            ok "$scen: real tool's per_change map matches expected.json exactly (catches attribute-to-every-member)"
        else
            bad "$scen: real tool's per_change map does NOT match expected.json"
        fi
        culprits_ok=$(python3 -c "
import json
want = sorted(json.load(open('$scen_dir/expected.json'))['culprits'])
got = sorted(json.load(open('$OUT_JSON')).get('culprits', []))
print('1' if want == got else '0')
" 2>/dev/null)
        if [ "$culprits_ok" = 1 ]; then
            ok "$scen: real tool's culprits list matches expected.json exactly"
        else
            bad "$scen: real tool's culprits list does NOT match expected.json"
        fi
    else
        bad "$scen: real tool did not write a non-empty --out $OUT_JSON -- cannot check per_change/culprits"
    fi
    rm -f "$OUT_JSON"
done

echo
echo "=== T056 contract stub 1/2: batch_bisect.py CLI + result.json wire ==="
echo "===   format (derived, UNCONFIRMED by any contracts/*.md file, ==="
echo "===   binding on T-C06's implementer per the header comment above) ==="
echo "NOT YET IMPLEMENTED: 'batch_bisect.py run --batch <batch.json>"
echo "  --base-tree <dir> --patches <dir> --gate <gate.sh> --out <result.json>'"
echo "  must exit 0 iff the batch (all changes applied together) PASSes"
echo "  the gate, exit 1 iff it FAILs; result.json must ALWAYS be written"
echo "  (batch_verdict, per_change map, culprits list) regardless of exit"
echo "  code, per-change verdicts computed by isolating each change"
echo "  individually and re-running the gate."

echo
echo "=== T056 contract stub 2/2: WIP caps (DEC-21) -- honest scope gap ==="
echo "NOT YET IMPLEMENTED and NOT EXERCISED by this RED test: plan.md"
echo "  T-C06's 'WIP caps per queue per DEC-21 set from T-A09 throughput'"
echo "  clause requires T-A09's measured throughput figures as an input,"
echo "  which do not exist yet (T-A09 is itself still open). This is an"
echo "  honestly-flagged owed gap for T-C06's real implementer, not"
echo "  silently tested here."

echo
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
