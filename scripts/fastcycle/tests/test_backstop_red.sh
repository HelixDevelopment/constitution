#!/bin/sh
# =============================================================================
# T060 RED test (SpecKit-004 "fast-dev-cycles", Phase 5 / User Story 2;
# plan.md T-C10; FR-006, FR-022, SC-003).
# =============================================================================
#
# Purpose: prove, BEFORE T-C10's `gates/backstop.sh` implementation (T077)
# exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed -- §11.4.6; `constitution/scripts/fastcycle/gates/` is
#       confirmed to hold nothing but `.gitkeep`; no dedicated
#       contracts/*.md file exists for T-C10, confirmed by a real
#       directory listing AND by common-conventions.md's own explicit
#       "open gap" listing of `$FC/gates/backstop.sh (T-C10)`);
#   (B) this file's own reference implementation of DEC-17's drift rule
#       (`dec17_drift_ref.py`) is non-vacuous -- the `bs_selection_hole`
#       fixture pair genuinely encodes a drift (a gate FAILed by the full
#       lane, absent from the fast lane's selection) and the
#       `bs_negctrl_equal` fixture pair genuinely encodes NO drift
#       (including a shared genuine FAIL both lanes caught, proving the
#       negative control is not merely "nothing failed anywhere") --
#       proven by REAL computation, never merely asserted (§11.4.273);
#   (C) this file's own reference implementation of the §11.4.226 /
#       §11.4.189 guard-freshness-queue ordering rule
#       (`guard_freshness_ref.py`) is non-vacuous -- the toy
#       `bs_freshness_queue` registry genuinely discriminates
#       most-reopened-first ordering from staleness-only ordering, and
#       genuinely discriminates freshness-gated membership from
#       reopens-count-only ranking (a guard with the single highest
#       reopens_count of all 5 is fresh and MUST be excluded) -- proven by
#       REAL computation, never merely asserted;
#   (D) once T-C10 lands, invoking the real tool through the SAME 3
#       fixtures under fixtures/backstop/ produces the outcome each
#       scenario's `expected` file predicts.
#
# Contract: no dedicated specs/004-fast-dev-cycles/contracts/*.md file
# exists for T-C10 at the time this file was written (confirmed by a real
# `ls` of that directory AND by common-conventions.md's own "Tool map"
# section explicitly listing `$FC/gates/backstop.sh (T-C10)` among the
# tools with "no contract is invented here ... interface, output and RED
# fixtures are fixed by the plan task text until a contract is written" --
# see Section A below). plan.md's T-C10 section (Work / Protecting-tests /
# Origin), research.md's DEC-17, and affected-set-and-verdict-cache.md's
# VC-005 clause + `verdicts/v1` output schema (reused here rather than
# inventing a new one, §11.4.6) are the authoritative sources this file
# implements against. fixtures/backstop/README.md documents the invented,
# binding-if-adopted CLI wire format in full.
#
# Task line (tasks.md T060, verbatim): "[P] [US2] [TDD] [SUBAGENT] RED test
# `constitution/scripts/fastcycle/tests/test_backstop_red.sh` (golden-bad:
# a fast-lane configuration with a planted selection hole produces a drift
# report and blocks; negative control: equal fast/full runs report no
# drift; guard-freshness queue drained most-reopened-first) (plan T-C10;
# FR-006, FR-022, SC-003)".
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# the fixtures under fixtures/backstop/ (created in this same task) + the
# two from-scratch reference modules under lib/ (dec17_drift_ref.py,
# guard_freshness_ref.py). It does NOT implement gates/backstop.sh
# (T-C10 / T077, a separate later task), and never fabricates a tool
# invocation result -- every DRIFT/NO_DRIFT/QUEUE claim below is either
# (a) a real reference computation this file performs itself with python3,
# or (b) a real invocation of the (today, absent) tool, reported RED
# because the tool cannot be found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected FAIL>0
#       for every scenario's real-tool-invocation check in Section D --
#       the reference self-checks in Sections B/C are expected to PASS
#       today, since they exercise only this file's own reference
#       computation, not the absent tool).
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$FC/../../.." && pwd)
TOOL="$FC/gates/backstop.sh"
FIXDIR="$HERE/fixtures/backstop"
DRIFT_REF="$HERE/lib/dec17_drift_ref.py"
FRESH_REF="$HERE/lib/guard_freshness_ref.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T060 RED: full backstop lane, drift monitor, guard-freshness queue (plan T-C10; FR-006, FR-022, SC-003) =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption carried over from plan.md/research.md.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T-C10/T077 has landed; the invocation"
    echo "   checks in Section D below are the real functional tests to run"
else
    echo "RED: $TOOL is absent -- T-C10/T077 (gates/backstop.sh) has not"
    echo "     landed yet, confirming this file's own premise is real, not"
    echo "     assumed"
fi

if [ -d "$FC/gates" ]; then
    NON_GITKEEP=$(find "$FC/gates" -maxdepth 1 -type f ! -name '.gitkeep' 2>/dev/null | wc -l)
    if [ "$NON_GITKEEP" -eq 0 ]; then
        ok "control needle: $FC/gates/ genuinely holds nothing but .gitkeep --"
        echo "   confirms backstop.sh is absent by DIRECTORY CONTENT, not"
        echo "   merely by the single-path check above"
    else
        echo "NOTE: $FC/gates/ holds $NON_GITKEEP non-.gitkeep file(s) already --"
        echo "      re-check whether T-C10 (or a sibling gates/ task) has"
        echo "      partially landed"
    fi
else
    bad "control needle FAILED: $FC/gates/ does not exist at all -- Setup"
    echo "   phase (T001-T006) has not created it"
fi

CONTRACTS_DIR=$(cd "$REPO_ROOT/specs/004-fast-dev-cycles/contracts" 2>/dev/null && pwd)
if [ -n "$CONTRACTS_DIR" ]; then
    if find "$CONTRACTS_DIR" -maxdepth 1 -iname '*backstop*' 2>/dev/null | grep -q .; then
        bad "control needle FAILED: a contracts/*backstop*.md file now"
        echo "   exists at $CONTRACTS_DIR -- this file's header claim 'no"
        echo "   dedicated contract exists for T-C10' is stale; re-derive"
        echo "   this test's wire-format assumptions against the real"
        echo "   contract before trusting anything below"
    else
        ok "control needle: no contracts/*backstop*.md file exists under"
        echo "   $CONTRACTS_DIR -- confirmed LIVE, not assumed from memory;"
        echo "   this file's own CLI wire format (fixtures/backstop/README.md)"
        echo "   is the only definition and is binding-if-adopted on T-C10"
    fi
    CCONV="$CONTRACTS_DIR/common-conventions.md"
    if [ -f "$CCONV" ] && grep -q 'gates/backstop\.sh.*T-C10' "$CCONV" 2>/dev/null; then
        ok "control needle: common-conventions.md's own 'Tool map' section"
        echo "   still lists \$FC/gates/backstop.sh (T-C10) among the tools"
        echo "   with no contract invented -- confirms this file's premise"
        echo "   against the LIVE contract text, not memory"
    else
        bad "control needle FAILED: common-conventions.md no longer lists"
        echo "   gates/backstop.sh (T-C10) as an open-gap tool (file missing"
        echo "   or the line changed) -- re-check whether a contract now"
        echo "   governs backstop.sh before trusting this file's invented CLI"
    fi
else
    bad "control needle FAILED: specs/004-fast-dev-cycles/contracts/ itself"
    echo "   could not be resolved -- cannot confirm the no-contract claim"
fi

if [ -d "$FC/gates" ]; then
    if [ -n "$(find "$FC/gates" -maxdepth 1 \( -name '*.sh' -o -name '*.py' \) -exec grep -l 'dec17_drift_ref\|guard_freshness_ref' {} \; 2>/dev/null)" ]; then
        bad "control needle FAILED: something under $FC/gates already"
        echo "   imports this test's own reference modules -- a real"
        echo "   implementation should never import the test's reference"
        echo "   code (they must be independently authored, per this"
        echo "   file's header comment)"
    else
        ok "control needle: nothing under $FC/gates/ imports this test's"
        echo "   own reference drift/freshness-queue modules -- their"
        echo "   independence is confirmed LIVE, not assumed"
    fi
else
    echo "SKIP: $FC/gates/ does not exist yet -- the needle above is"
    echo "      therefore vacuously true and NOT counted as a separate pass"
fi

# =============================================================================
# Section B -- reference DEC-17 drift detector + its own self-validation
# (§11.4.107(10)/§11.4.273): this is THIS FILE's independent, from-scratch
# implementation of DEC-17's drift rule, used ONLY to prove the
# bs_selection_hole / bs_negctrl_equal fixture pairs are non-vacuous BEFORE
# any claim is made about the absent real tool.
# =============================================================================
if [ ! -f "$DRIFT_REF" ]; then
    bad "reference DEC-17 drift detector missing at $DRIFT_REF -- Section B self-checks cannot run"
elif ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- cannot run the reference DEC-17 drift detector"
else
    HOLE_DIR="$FIXDIR/bs_selection_hole"
    EQUAL_DIR="$FIXDIR/bs_negctrl_equal"

    hole_out=$(python3 "$DRIFT_REF" "$HOLE_DIR/fast_verdicts.json" "$HOLE_DIR/full_verdicts.json" 2>&1)
    hole_rc=$?
    if [ "$hole_rc" -eq 1 ] && printf '%s\n' "$hole_out" | grep -q '^DRIFT gate=GATE-HOLE fast=ABSENT full=FAIL$'; then
        ok "bs_selection_hole: reference detector reports DRIFT gate=GATE-HOLE"
        echo "   fast=ABSENT full=FAIL (exit 1) -- matching this fixture's own"
        echo "   README claim; the golden-bad pair is confirmed non-vacuous"
    else
        bad "bs_selection_hole: reference detector expected exit 1 with a"
        echo "   'DRIFT gate=GATE-HOLE fast=ABSENT full=FAIL' line, got rc=$hole_rc"
        echo "   output='$hole_out' -- this fixture pair does not actually"
        echo "   encode the selection-hole scenario its README claims"
    fi
    if printf '%s\n' "$hole_out" | grep -q '^DRIFT_COUNT=1$'; then
        ok "bs_selection_hole: reference detector reports DRIFT_COUNT=1 --"
        echo "   exactly the one planted hole, no phantom drifts on GATE-A/B/C"
    else
        bad "bs_selection_hole: expected DRIFT_COUNT=1, got output='$hole_out'"
        echo "   -- either the planted hole was not isolated, or GATE-A/B/C"
        echo "   (which agree between fast and full) were wrongly flagged too"
    fi

    equal_out=$(python3 "$DRIFT_REF" "$EQUAL_DIR/fast_verdicts.json" "$EQUAL_DIR/full_verdicts.json" 2>&1)
    equal_rc=$?
    if [ "$equal_rc" -eq 0 ] && printf '%s\n' "$equal_out" | grep -q '^NO_DRIFT$' && printf '%s\n' "$equal_out" | grep -q '^DRIFT_COUNT=0$'; then
        ok "bs_negctrl_equal: reference detector reports NO_DRIFT DRIFT_COUNT=0"
        echo "   (exit 0) -- matching this fixture's own README claim; the"
        echo "   negative-control pair is confirmed non-vacuous"
    else
        bad "bs_negctrl_equal: reference detector expected exit 0 with"
        echo "   NO_DRIFT/DRIFT_COUNT=0, got rc=$equal_rc output='$equal_out'"
        echo "   -- this negative-control fixture does not actually encode"
        echo "   equal fast/full selections as its README claims"
    fi

    # -------------------------------------------------------------------
    # Control needle: bs_negctrl_equal's shared FAIL (GATE-B) is genuinely
    # a FAIL in BOTH documents, not an accidental omission that would make
    # the "no drift" verdict trivially true for the wrong reason (e.g. a
    # buggy detector that only ever compares PASS-vs-PASS pairs and
    # silently ignores any gate that FAILed in either document would ALSO
    # report NO_DRIFT here, but for a reason that says nothing about
    # DEC-17's real rule). Confirmed directly against the raw JSON, not
    # merely inferred from the reference detector's own exit code above.
    # -------------------------------------------------------------------
    fast_b=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(next(r['verdict'] for r in d['results'] if r['gate_id']=='GATE-B'))" "$EQUAL_DIR/fast_verdicts.json" 2>/dev/null)
    full_b=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(next(r['verdict'] for r in d['results'] if r['gate_id']=='GATE-B'))" "$EQUAL_DIR/full_verdicts.json" 2>/dev/null)
    if [ "$fast_b" = FAIL ] && [ "$full_b" = FAIL ]; then
        ok "control needle: bs_negctrl_equal/GATE-B is genuinely FAIL in"
        echo "   BOTH fast_verdicts.json and full_verdicts.json (raw JSON"
        echo "   read directly) -- the NO_DRIFT verdict above is proven to"
        echo "   come from 'the fast lane ALSO caught this FAIL', never"
        echo "   from 'nothing failed anywhere'"
    else
        bad "control needle FAILED: bs_negctrl_equal/GATE-B is not FAIL in"
        echo "   both documents (fast=$fast_b full=$full_b) -- this fixture's"
        echo "   negative control is vacuous (the 'shared genuine FAIL' claim"
        echo "   in its README is false)"
    fi

    # -------------------------------------------------------------------
    # Control needle: the reference detector's rule genuinely NEEDS the
    # "absent from fast" branch, not only the "present with wrong verdict"
    # branch -- a buggy implementation that only compares gates present in
    # BOTH documents' results (intersection-only, silently ignoring any
    # gate the fast lane never selected at all) would WRONGLY report
    # NO_DRIFT on bs_selection_hole, since GATE-HOLE is entirely absent
    # from fast_verdicts.json and an intersection-only comparison would
    # simply never look at it. Proven here with an inline reference of
    # that WRONG rule, confirming it disagrees with the correct rule on
    # this exact fixture (so the fixture genuinely discriminates the two).
    # -------------------------------------------------------------------
    intersection_only_drift=$(python3 - "$HOLE_DIR/fast_verdicts.json" "$HOLE_DIR/full_verdicts.json" <<'PYEOF'
import json, sys
fast = {r["gate_id"]: r["verdict"] for r in json.load(open(sys.argv[1]))["results"]}
full = {r["gate_id"]: r["verdict"] for r in json.load(open(sys.argv[2]))["results"]}
# WRONG rule (deliberately, for the control needle only): only compares
# gate_ids present in BOTH documents, ignoring any gate absent from fast.
drifts = [g for g in full if g in fast and full[g] == "FAIL" and fast[g] != "FAIL"]
print(len(drifts))
PYEOF
)
    if [ "$intersection_only_drift" = "0" ]; then
        ok "control needle: an intersection-only ('ignore gates absent from"
        echo "   fast') comparison of bs_selection_hole's own two documents"
        echo "   finds ZERO drifts -- disagreeing with the correct reference"
        echo "   detector's DRIFT_COUNT=1 above -- proving this fixture"
        echo "   genuinely REQUIRES the 'gate entirely absent from fast'"
        echo "   branch of DEC-17's rule, not merely a coincidence of the"
        echo "   'present with wrong verdict' branch"
    else
        bad "control needle FAILED: the deliberately-wrong intersection-only"
        echo "   comparison also found a drift ($intersection_only_drift) on"
        echo "   bs_selection_hole -- this fixture does not actually isolate"
        echo "   the 'selection hole' (gate absent from fast) case from the"
        echo "   'present but wrong verdict' case"
    fi
fi

# =============================================================================
# Section C -- reference guard-freshness-queue builder + its own
# self-validation: proves the bs_freshness_queue registry fixture is
# non-vacuous BEFORE any claim is made about the absent real tool's
# `freshness-queue` subcommand.
# =============================================================================
if [ ! -f "$FRESH_REF" ]; then
    bad "reference guard-freshness-queue builder missing at $FRESH_REF -- Section C self-checks cannot run"
elif ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- cannot run the reference guard-freshness-queue builder"
else
    QDIR="$FIXDIR/bs_freshness_queue"
    FP=$(cat "$QDIR/fingerprint.txt" 2>/dev/null | tr -d '\r\n')

    if [ -z "$FP" ]; then
        bad "bs_freshness_queue: could not read fingerprint.txt"
    else
        queue_out=$(python3 "$FRESH_REF" "$QDIR/registry.json" "$FP" 2>&1)
        queue_rc=$?
        expected_order="GUARD-HIGH
GUARD-MID
GUARD-TIE
GUARD-NEVER"
        actual_order=$(printf '%s\n' "$queue_out" | grep '^QUEUE ' | sed -n 's/^QUEUE [0-9]* guard=\([^ ]*\).*/\1/p')

        if [ "$queue_rc" -eq 0 ] && [ "$actual_order" = "$expected_order" ]; then
            ok "bs_freshness_queue: reference builder emits the exact"
            echo "   required drain order GUARD-HIGH, GUARD-MID, GUARD-TIE,"
            echo "   GUARD-NEVER (most-reopened-first, then stalest-first on"
            echo "   the GUARD-MID/GUARD-TIE tie) -- exit 0"
        else
            bad "bs_freshness_queue: expected drain order '$expected_order'"
            echo "   (rc=0), got rc=$queue_rc actual_order='$actual_order'"
            echo "   full_output='$queue_out'"
        fi

        if printf '%s\n' "$queue_out" | grep -q 'guard=GUARD-FRESH'; then
            bad "bs_freshness_queue: GUARD-FRESH (fingerprint matches"
            echo "   current, i.e. FRESH) appears in the queue output -- a"
            echo "   fresh guard must NEVER be queued regardless of its"
            echo "   reopens_count"
        else
            ok "bs_freshness_queue: GUARD-FRESH (reopens_count=99, the"
            echo "   single highest of all 5 guards) is genuinely ABSENT from"
            echo "   the queue output -- the freshness gate correctly"
            echo "   excludes it despite its reopens_count, confirming this"
            echo "   negative control is non-vacuous"
        fi

        if printf '%s\n' "$queue_out" | grep -q '^FRESH_COUNT=1$' && printf '%s\n' "$queue_out" | grep -q '^STALE_COUNT=4$'; then
            ok "bs_freshness_queue: reference builder reports FRESH_COUNT=1"
            echo "   STALE_COUNT=4, matching the registry's 1 fresh / 4 stale"
            echo "   guard split"
        else
            bad "bs_freshness_queue: expected FRESH_COUNT=1 STALE_COUNT=4,"
            echo "   got output='$queue_out'"
        fi

        # -----------------------------------------------------------------
        # Control needle #1: sorting the SAME stale set by staleness ALONE
        # (ignoring reopens_count) produces a DIFFERENT order -- GUARD-NEVER
        # (never executed, maximally stale) would rank FIRST -- proving
        # this fixture genuinely discriminates "most-reopened-first" from
        # "stalest-first" as the PRIMARY key, not merely by coincidence.
        # -----------------------------------------------------------------
        staleness_only_order=$(python3 - "$QDIR/registry.json" "$FP" <<'PYEOF'
import json, sys
guards = json.load(open(sys.argv[1]))["guards"]
fp = sys.argv[2]
stale = [g for g in guards if g.get("last_verdict_fingerprint", "") != fp]
ordered = sorted(stale, key=lambda g: g.get("last_verdict_at") or "")
for g in ordered:
    print(g["guard_id"])
PYEOF
)
        if [ "$staleness_only_order" != "$actual_order" ] && printf '%s\n' "$staleness_only_order" | head -n1 | grep -q '^GUARD-NEVER$'; then
            ok "control needle: a staleness-ONLY ordering of the same stale"
            echo "   set puts GUARD-NEVER FIRST (order: $(printf '%s' "$staleness_only_order" | tr '\n' ' ')),"
            echo "   which DIFFERS from the correct most-reopened-first order"
            echo "   above -- proving reopens_count genuinely dominates the"
            echo "   primary sort, this is not a fixture where both orderings"
            echo "   coincide"
        else
            bad "control needle FAILED: a staleness-only ordering did not"
            echo "   differ from the reopens-first order as expected"
            echo "   (staleness_only='$staleness_only_order' actual='$actual_order')"
            echo "   -- this fixture does not discriminate the two ordering"
            echo "   rules"
        fi

        # -----------------------------------------------------------------
        # Control needle #2: ranking by reopens_count ALONE (ignoring the
        # freshness gate) would WRONGLY place GUARD-FRESH at rank 1 (its
        # reopens_count=99 is the single highest of all 5 guards) --
        # proving the freshness gate is a real, necessary, separate
        # mechanism from the ranking, not a redundant restatement of it.
        # -----------------------------------------------------------------
        reopens_only_top=$(python3 -c "import json,sys; g=json.load(open(sys.argv[1]))['guards']; print(max(g, key=lambda x: x['reopens_count'])['guard_id'])" "$QDIR/registry.json" 2>/dev/null)
        if [ "$reopens_only_top" = "GUARD-FRESH" ]; then
            ok "control needle: ranking ALL 5 guards by reopens_count alone"
            echo "   (ignoring freshness) puts GUARD-FRESH at rank 1 -- which"
            echo "   the correct freshness-gated queue above correctly"
            echo "   EXCLUDES entirely, proving the freshness gate is a real,"
            echo "   necessary, separate mechanism from the reopens-count"
            echo "   ranking"
        else
            bad "control needle FAILED: reopens-count-only ranking's top"
            echo "   guard is '$reopens_only_top', not GUARD-FRESH as this"
            echo "   fixture's design requires -- the negative-control"
            echo "   property (highest reopens_count is also the one that"
            echo "   must be excluded) does not hold on this registry"
        fi

        # -----------------------------------------------------------------
        # Determinism (C-003 / §11.4.50): running the reference builder
        # twice on byte-identical input must produce byte-identical output.
        # -----------------------------------------------------------------
        queue_out_2=$(python3 "$FRESH_REF" "$QDIR/registry.json" "$FP" 2>&1)
        if [ "$queue_out" = "$queue_out_2" ]; then
            ok "determinism: two consecutive reference-builder runs on the"
            echo "   same registry+fingerprint produce byte-identical output"
        else
            bad "determinism FAILED: two consecutive reference-builder runs"
            echo "   produced different output (run1='$queue_out' vs"
            echo "   run2='$queue_out_2')"
        fi
    fi
fi

# =============================================================================
# Section D -- the real functional checks: invoke $TOOL for every scenario.
# $TOOL is absent today, so every check below is the expected RED outcome,
# reported per-scenario (never collapsed into one opaque "tool missing"
# line), matching the established sibling convention
# (test_io_trace_red.sh / test_mutation_reuse_red.sh).
# =============================================================================
SCRATCH=$(mktemp -d) || { echo "FAIL: cannot create scratch dir"; FAIL=$((FAIL+1)); SCRATCH=""; }
trap '[ -n "${SCRATCH:-}" ] && rm -rf "$SCRATCH"' EXIT

# --- (1) golden-bad: planted selection hole -> DRIFT report, block (exit 1) ---
HOLE_DIR="$FIXDIR/bs_selection_hole"
if [ ! -f "$TOOL" ]; then
    bad "RED: bs_selection_hole (expected exit 1, DRIFT gate=GATE-HOLE) -- $TOOL is absent, cannot run compare"
elif [ -z "${SCRATCH:-}" ]; then
    bad "bs_selection_hole: no scratch dir available, skipping invocation"
else
    out=$(sh "$TOOL" compare --fast "$HOLE_DIR/fast_verdicts.json" --full "$HOLE_DIR/full_verdicts.json" --out "$SCRATCH/hole_drift.json" 2>&1)
    rc=$?
    if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'GATE-HOLE'; then
        ok "bs_selection_hole: backstop.sh compare reports drift naming"
        echo "   GATE-HOLE and exits 1 (block) as expected"
    else
        bad "bs_selection_hole: expected exit 1 with GATE-HOLE named in"
        echo "   the drift report, got rc=$rc output='$out'"
    fi
fi

# --- (2) negative control: equal fast/full -> NO_DRIFT (exit 0) ---
EQUAL_DIR="$FIXDIR/bs_negctrl_equal"
if [ ! -f "$TOOL" ]; then
    bad "RED: bs_negctrl_equal (expected exit 0, NO_DRIFT) -- $TOOL is absent, cannot run compare"
elif [ -z "${SCRATCH:-}" ]; then
    bad "bs_negctrl_equal: no scratch dir available, skipping invocation"
else
    out=$(sh "$TOOL" compare --fast "$EQUAL_DIR/fast_verdicts.json" --full "$EQUAL_DIR/full_verdicts.json" --out "$SCRATCH/equal_drift.json" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'NO_DRIFT'; then
        ok "bs_negctrl_equal: backstop.sh compare reports NO_DRIFT and"
        echo "   exits 0 as expected"
    else
        bad "bs_negctrl_equal: expected exit 0 with NO_DRIFT reported, got"
        echo "   rc=$rc output='$out'"
    fi
fi

# --- (3) guard-freshness queue drained most-reopened-first ---
QDIR="$FIXDIR/bs_freshness_queue"
if [ ! -f "$TOOL" ]; then
    bad "RED: bs_freshness_queue (expected exit 0, queue ordered GUARD-HIGH,GUARD-MID,GUARD-TIE,GUARD-NEVER, GUARD-FRESH excluded) -- $TOOL is absent, cannot run freshness-queue"
elif [ -z "${SCRATCH:-}" ]; then
    bad "bs_freshness_queue: no scratch dir available, skipping invocation"
else
    fp=$(cat "$QDIR/fingerprint.txt" 2>/dev/null | tr -d '\r\n')
    out=$(sh "$TOOL" freshness-queue --registry "$QDIR/registry.json" --fingerprint "$fp" --out "$SCRATCH/queue.json" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ] \
        && printf '%s\n' "$out" | grep -q '^QUEUE 1 guard=GUARD-HIGH ' \
        && ! printf '%s\n' "$out" | grep -q 'guard=GUARD-FRESH'; then
        ok "bs_freshness_queue: backstop.sh freshness-queue ranks GUARD-HIGH"
        echo "   first (most-reopened) and excludes GUARD-FRESH entirely,"
        echo "   exit 0 as expected"
    else
        bad "bs_freshness_queue: expected exit 0, rank-1 guard=GUARD-HIGH,"
        echo "   GUARD-FRESH absent from output; got rc=$rc output='$out'"
    fi
fi

echo
echo "=== T060 contract stub 1/3: compare wire format (drift detection + block) ==="
echo "NOT YET IMPLEMENTED: backstop.sh MUST accept 'compare --fast"
echo "  <fast_verdicts.json> --full <full_verdicts.json> --out <drift.json>"
echo "  [--apply --map <gate_map.json>]' -- inputs are verdicts/v1-shaped"
echo "  documents (reusing affected-set-and-verdict-cache.md's existing"
echo "  schema); DEC-17 drift = full verdict FAIL and fast verdict != FAIL"
echo "  for the same gate_id (absent from fast counts as != FAIL). Exit 0"
echo "  + stdout first line 'NO_DRIFT' when DRIFT_COUNT is 0; exit 1"
echo "  (block, release blocker per DEC-17/C-001) + one 'DRIFT gate=<id>"
echo "  fast=<verdict|ABSENT> full=FAIL' line per drifting gate (sorted by"
echo "  gate_id) + 'DRIFT_COUNT=<n>' otherwise. --out writes a"
echo "  backstop_drift/v1 document per C-002; the --apply --map pair (the"
echo "  DEC-17/AS-010a force-full write-back) is out of this RED test's"
echo "  scope -- see fixtures/backstop/README.md 'What this RED test does"
echo "  NOT cover'."

echo
echo "=== T060 contract stub 2/3: freshness-queue wire format ==="
echo "NOT YET IMPLEMENTED: backstop.sh MUST accept 'freshness-queue"
echo "  --registry <registry.json> --fingerprint <fp> --out <queue.json>'."
echo "  A guard is STALE (queued) iff its stored last_verdict_fingerprint"
echo "  != <fp> (never-executed counts as stale); a guard whose stored"
echo "  fingerprint MATCHES <fp> is FRESH and is excluded from the queue"
echo "  REGARDLESS of reopens_count (§11.4.226's freshness contract"
echo "  gates membership). Queue order: reopens_count descending"
echo "  (§11.4.189 most-reopened-first) PRIMARY, staleness descending"
echo "  (older/absent last_verdict_at first) SECONDARY tie-break only."
echo "  Exit 0 always; stdout one 'QUEUE <rank> guard=<id> reopens=<n>'"
echo "  line per queued guard in drain order, then 'FRESH_COUNT=<n>'"
echo "  'STALE_COUNT=<m>'."

echo
echo "=== T060 contract stub 3/3: run subcommand + honest scope ==="
echo "NOT YET IMPLEMENTED: 'backstop.sh run --config <cfg> --no-cache --out"
echo "  <full_verdicts.json>' composes \$FC/gates/gate_runner.sh over EVERY"
echo "  gate (no --affected narrowing, --no-cache) to produce the full"
echo "  lane's verdicts/v1 document consumed by 'compare' above -- NOT"
echo "  exercised by this RED test's fixtures (it requires a real gate"
echo "  corpus + gate_runner.sh, neither constructed here; T077's own"
echo "  implementer-task job, §11.4.240). The scheduling triggers DEC-17"
echo "  names for WHEN the full lane runs (before every release tag,"
echo "  nightly on main when the fast lane ran that day, on any gate-"
echo "  engine/map/key change) and the --apply --map force-full write-back"
echo "  are likewise out of this RED test's scope -- see"
echo "  fixtures/backstop/README.md 'What this RED test does NOT cover'."

echo
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
