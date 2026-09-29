#!/bin/sh
# =============================================================================
# T054 RED test (SpecKit-004 "fast-dev-cycles", Phase 5 / User Story 2;
# plan.md T-C04; SC-002).
# =============================================================================
#
# Purpose: prove, BEFORE the T070 implementation of "fail-fast ordering" in
# `constitution/scripts/fastcycle/gates/gate_runner.sh` exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed -- §11.4.6) -- gate_runner.sh itself is ALSO the target of
#       the SIBLING task T-C05/T055 (bounded sharding); this file tests
#       ONLY the T-C04 ordering half (AS-013), never the sharding half;
#   (B) once T070 lands, invoking the real tool with `--order history-cost`
#       against a toy 4-gate corpus whose historical fail_rate/mean_cost
#       (fixtures/gate_order/_shared/history/prebuild_sections.tsv, the
#       real T-A01 TSV schema) ranks a PLANTED FAILING gate declared LAST
#       in section order as the HIGHEST-ranked gate produces the outcome
#       the task text literally states: "a planted failing gate placed
#       last in section order is reported first" and "the final verdict
#       set is identical with and without ordering" (tasks.md T054;
#       contract AS-013).
#
# Contract: specs/004-fast-dev-cycles/contracts/affected-set-and-verdict-cache.md
#   AS-013 (ordering clause, this file's ENTIRE scope) -- AS-014 (parallel
#   sharding) is OUT OF SCOPE here, covered by test_gate_shard_red.sh (T055).
#   CLI per the contract's "Components and invocations" section:
#     $FC/gates/gate_runner.sh --config <cfg> --affected <affected.json>
#       [--order history-cost] [--no-cache] --out <verdicts.json>
#   Exit codes (contract's own override of common-conventions.md C-001):
#     0 all PASS, 1 any FAIL, 4 any BLIND.
#   Output schema (verdicts/v1): {change_id, results: [{gate_id, verdict,
#     source, cache_key?, evidence, duration_ms}], summary} sorted by
#     gate_id (C-002/C-003 determinism -- this is a FIXED property of the
#     canonical `results` array regardless of --order).
#
# Task line (tasks.md T054, verbatim): "[P] [US2] [TDD] [SUBAGENT] RED test
# constitution/scripts/fastcycle/tests/test_gate_order_red.sh (a planted
# failing gate placed last in section order is reported first; the final
# verdict set is identical with and without ordering) (plan T-C04; SC-002)".
#
# `execution_order` output field: UNCONFIRMED by the contract itself (it
# fixes `results` as sorted-by-gate_id for determinism, C-002/C-003, so
# "reported first" cannot be observed from `results`' order alone --
# proven directly below in Section B by parsing the contract's own literal
# schema text). DEFINED here, binding-if-adopted on T070, exactly per the
# established house precedent (fixtures/verdict_cache/'s own get/put wire
# format, fixtures/gate_order/go_ordered_planted_fail_first/README.md
# "Design note"): the real tool's `--out <verdicts.json>` document is
# expected to carry an ADDITIONAL top-level `execution_order` array (list
# of gate_id, actual run sequence) alongside the canonical `results` array
# -- the only way a deterministically-sorted output format can ALSO expose
# which gate the ordering mechanism genuinely ran first. If T070's real
# implementation names this field differently, only this file's field-name
# constant (EXEC_ORDER_KEY below) needs updating, never the fixture data.
#
# DEC-10 "new gates at the median rate": the median's POPULATION is
# UNCONFIRMED by the contract text (whole historical log vs only the
# gates-with-history present in the current run's members). This file's
# go_new_gate_median_rate/ fixture is deliberately constructed so the
# assertion (strict relative ordering c > d > a) holds under EITHER
# reasonable population choice -- see that fixture's own README.md.
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# the fixtures under fixtures/gate_order/ (created in this same task). It
# does NOT implement gates/gate_runner.sh (T070, a separate later task),
# and never fabricates a tool invocation result -- every PASS/FAIL claim
# below is either (a) a real, independent computation this file performs
# itself over the fixture TSV/JSON (the reference fail_rate/mean_cost
# ranking, Section B), or (b) a real invocation of the (today, absent)
# tool, reported RED because the tool cannot be found (Section C).
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected
#       FAIL>0 for every scenario's real tool-invocation check in Section
#       C -- the reference-ranking self-checks in Section B are expected
#       to PASS today, since they exercise only this file's own
#       computation over the fixture data, never the absent tool).

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/gate_runner.sh"
FIXDIR="$HERE/fixtures/gate_order"
SHARED="$FIXDIR/_shared"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T054 RED: fail-fast gate ordering (plan T-C04; SC-002) =="

# =============================================================================
# Section A -- control needle (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption carried over from tasks.md/plan.md.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T070 has landed; the invocation checks"
    echo "   in Section C below are the real functional tests to run"
else
    echo "RED: $TOOL is absent -- T070 (gates/gate_runner.sh, the ordering"
    echo "     half) has not landed yet, confirming this file's own"
    echo "     premise is real, not assumed"
fi

if [ -f "$SHARED/history/prebuild_sections.tsv" ] && [ -f "$SHARED/affected.json" ] \
   && [ -f "$SHARED/config.yaml" ]; then
    ok "control needle: this file's own toy fixtures (history TSV + shared"
    echo "   affected.json + config.yaml) genuinely exist on disk"
else
    bad "control needle: the toy fixtures this test depends on are missing"
    echo "     -- fixture-authoring defect in THIS file, not a T070 finding"
fi

# =============================================================================
# Section B -- reference ranking self-check (this file's OWN computation,
# never the absent tool). Proves the fixture's own fail_rate/mean_cost
# design is non-vacuous BEFORE it is used to judge the real tool.
# =============================================================================
echo "-- Section B: reference fail_rate/mean_cost ranking over the fixture TSV --"

REF_RANK=$(python3 - "$SHARED/history/prebuild_sections.tsv" <<'PYEOF'
import csv, sys
from collections import defaultdict

path = sys.argv[1]
runs = defaultdict(list)  # gate_id -> [(verdict, duration_ms), ...]
with open(path, newline="") as f:
    for row in csv.DictReader(f, delimiter="\t"):
        runs[row["id"]].append((row["verdict"], int(row["duration_ms"])))

ratios = {}
for gid, rows in runs.items():
    n = len(rows)
    fails = sum(1 for v, _ in rows if v == "FAIL")
    fail_rate = fails / n
    mean_cost = sum(d for _, d in rows) / n
    ratios[gid] = fail_rate / mean_cost if mean_cost else float("inf")

# DEC-10: a gate absent from the log (gate_d_new) defaults to the MEDIAN
# rate across the gates that DO have history in this reference computation.
known = sorted(ratios.values())
mid = len(known) // 2
median = known[mid] if len(known) % 2 == 1 else (known[mid - 1] + known[mid]) / 2
ratios["gate_d_new"] = median

for gid in sorted(ratios, key=lambda g: -ratios[g]):
    print(f"{gid}\t{ratios[gid]:.6f}")
PYEOF
)

REF_FIRST=$(echo "$REF_RANK" | head -1 | cut -f1)
REF_LAST=$(echo "$REF_RANK" | tail -1 | cut -f1)

echo "$REF_RANK" | sed 's/^/   /'

if [ "$REF_FIRST" = "gate_c_planted_fail" ]; then
    ok "reference ranking: gate_c_planted_fail computed as HIGHEST"
    echo "   fail_rate/mean_cost -- the fixture's design premise is real"
else
    bad "reference ranking: expected gate_c_planted_fail first, got $REF_FIRST"
    echo "     -- fixture-authoring defect, fix the TSV before trusting Section C"
fi

if [ "$REF_LAST" = "gate_a_reliable" ]; then
    ok "reference ranking: gate_a_reliable computed as LOWEST"
    echo "   fail_rate/mean_cost (0 historical fails)"
else
    bad "reference ranking: expected gate_a_reliable last, got $REF_LAST"
fi

# gate_d_new (median default) must rank strictly between a and c.
REF_D_POS=$(echo "$REF_RANK" | cut -f1 | grep -n '^gate_d_new$' | cut -d: -f1)
REF_A_POS=$(echo "$REF_RANK" | cut -f1 | grep -n '^gate_a_reliable$' | cut -d: -f1)
REF_C_POS=$(echo "$REF_RANK" | cut -f1 | grep -n '^gate_c_planted_fail$' | cut -d: -f1)
if [ "$REF_C_POS" -lt "$REF_D_POS" ] && [ "$REF_D_POS" -lt "$REF_A_POS" ]; then
    ok "reference ranking: gate_d_new (no history, median default) ranks"
    echo "   strictly between gate_c_planted_fail and gate_a_reliable (DEC-10)"
else
    bad "reference ranking: gate_d_new's median-default position is wrong"
    echo "     (expected strictly between c and a; positions c=$REF_C_POS d=$REF_D_POS a=$REF_A_POS)"
fi

# =============================================================================
# Section C -- real invocations of the (today, absent) tool.
# =============================================================================
echo "-- Section C: real tool invocations (today: absent -> RED expected) --"

EXEC_ORDER_KEY="execution_order"  # see header comment: UNCONFIRMED field name

# run_gate_runner <affected.json> <order-flag: yes|no> <out-file>
# Returns the tool's real exit code via $? after the call.
run_gate_runner() {
    affected="$1"; order="$2"; out="$3"
    if [ "$order" = "yes" ]; then
        "$TOOL" --config "$SHARED/config.yaml" --affected "$affected" \
            --order history-cost --out "$out" 2>&1
    else
        "$TOOL" --config "$SHARED/config.yaml" --affected "$affected" \
            --out "$out" 2>&1
    fi
}

WORKDIR=$(mktemp -d 2>/dev/null || mktemp -d -t gate_order_t054)
trap 'rm -rf "$WORKDIR"' EXIT

# --- Scenario 1: golden -- planted-fail-last is reported first when ordered.
echo "  scenario: go_ordered_planted_fail_first"
OUT1="$WORKDIR/verdicts_ordered.json"
if [ ! -x "$TOOL" ]; then
    bad "go_ordered_planted_fail_first: $TOOL absent or not executable --"
    echo "     real invocation could not be attempted (expected today)"
else
    LOG1=$(run_gate_runner "$SHARED/affected.json" yes "$OUT1")
    RC1=$?
    if [ -f "$OUT1" ]; then
        FIRST=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('$EXEC_ORDER_KEY', ['<missing>'])[0])" "$OUT1" 2>/dev/null)
        C_VERDICT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); r=[x for x in d.get('results',[]) if x.get('gate_id')=='gate_c_planted_fail']; print(r[0]['verdict'] if r else '<missing>')" "$OUT1" 2>/dev/null)
        if [ "$FIRST" = "gate_c_planted_fail" ] && [ "$C_VERDICT" = "FAIL" ]; then
            ok "go_ordered_planted_fail_first: execution_order[0]==gate_c_planted_fail, verdict==FAIL"
        else
            bad "go_ordered_planted_fail_first: got execution_order[0]='$FIRST' verdict='$C_VERDICT' (rc=$RC1)"
        fi
    else
        bad "go_ordered_planted_fail_first: no output produced (rc=$RC1): $LOG1"
    fi
fi

# --- Scenario 2: negative control -- already-first order is a no-op.
echo "  scenario: go_negctrl_already_first"
OUT2="$WORKDIR/verdicts_negctrl.json"
if [ ! -x "$TOOL" ]; then
    bad "go_negctrl_already_first: $TOOL absent or not executable --"
    echo "     real invocation could not be attempted (expected today)"
else
    LOG2=$(run_gate_runner "$FIXDIR/go_negctrl_already_first/affected.json" yes "$OUT2")
    RC2=$?
    if [ -f "$OUT2" ]; then
        FIRST2=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('$EXEC_ORDER_KEY', ['<missing>'])[0])" "$OUT2" 2>/dev/null)
        if [ "$FIRST2" = "gate_c_planted_fail" ]; then
            ok "go_negctrl_already_first: execution_order[0]==gate_c_planted_fail (no-op reorder correct)"
        else
            bad "go_negctrl_already_first: got execution_order[0]='$FIRST2' (rc=$RC2)"
        fi
    else
        bad "go_negctrl_already_first: no output produced (rc=$RC2): $LOG2"
    fi
fi

# --- Scenario 3: determinism -- final results set identical with/without ordering.
echo "  scenario: go_determinism_identical_results"
OUT3A="$WORKDIR/verdicts_with_order.json"
OUT3B="$WORKDIR/verdicts_without_order.json"
if [ ! -x "$TOOL" ]; then
    bad "go_determinism_identical_results: $TOOL absent or not executable --"
    echo "     real invocation could not be attempted (expected today)"
else
    LOG3A=$(run_gate_runner "$SHARED/affected.json" yes "$OUT3A")
    RC3A=$?
    LOG3B=$(run_gate_runner "$SHARED/affected.json" no "$OUT3B")
    RC3B=$?
    if [ -f "$OUT3A" ] && [ -f "$OUT3B" ]; then
        RESULTS_EQUAL=$(python3 -c "
import json, sys
a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
ra = sorted(a.get('results', []), key=lambda r: r.get('gate_id',''))
rb = sorted(b.get('results', []), key=lambda r: r.get('gate_id',''))
pa = [(r.get('gate_id'), r.get('verdict')) for r in ra]
pb = [(r.get('gate_id'), r.get('verdict')) for r in rb]
print('yes' if pa == pb and len(pa) == 4 else 'no')
" "$OUT3A" "$OUT3B" 2>/dev/null)
        if [ "$RESULTS_EQUAL" = "yes" ]; then
            ok "go_determinism_identical_results: results identical (ordered vs unordered)"
        else
            bad "go_determinism_identical_results: results DIFFER between ordered/unordered runs (rc=$RC3A/$RC3B)"
        fi
    else
        bad "go_determinism_identical_results: no output produced (rc=$RC3A/$RC3B): $LOG3A / $LOG3B"
    fi
fi

# --- Scenario 4: control needle -- new-gate median-rate default (DEC-10).
echo "  scenario: go_new_gate_median_rate"
OUT4="$WORKDIR/verdicts_median.json"
if [ ! -x "$TOOL" ]; then
    bad "go_new_gate_median_rate: $TOOL absent or not executable --"
    echo "     real invocation could not be attempted (expected today)"
else
    LOG4=$(run_gate_runner "$FIXDIR/go_new_gate_median_rate/affected.json" yes "$OUT4")
    RC4=$?
    if [ -f "$OUT4" ]; then
        ORDER4=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(','.join(d.get('$EXEC_ORDER_KEY', ['<missing>'])))" "$OUT4" 2>/dev/null)
        if [ "$ORDER4" = "gate_c_planted_fail,gate_d_new,gate_a_reliable" ]; then
            ok "go_new_gate_median_rate: execution_order == [c, d, a] (median-default confirmed)"
        else
            bad "go_new_gate_median_rate: got execution_order=[$ORDER4] (rc=$RC4)"
        fi
    else
        bad "go_new_gate_median_rate: no output produced (rc=$RC4): $LOG4"
    fi
fi

echo "== T054 RED summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
