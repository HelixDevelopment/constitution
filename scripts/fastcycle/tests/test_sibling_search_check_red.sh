#!/bin/sh
# =============================================================================
# T088 RED test, shell half (SpecKit-004 "fast-dev-cycles", Phase 5 / User
# Story 3; plan.md T-D03; contract closure-refusal.md CR-004; FR-011, SC-004).
# =============================================================================
#
# Purpose: prove, BEFORE T096's `closure/sibling_search_check.sh`
# implementation exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed -- §11.4.6; `constitution/scripts/fastcycle/closure/` is
#       confirmed to hold nothing but `.gitkeep`);
#   (B) the underlying MECHANISM the real tool will validate artefacts of
#       (a grep-style search + a control-needle proof that the search
#       genuinely works) is itself sound on this host, proven by a REAL
#       grep invocation against a REAL known-present symbol in this repo
#       (never merely assumed present, per §11.4.273: "the path is part of
#       the instrument");
#   (C) once T096 lands, invoking the real tool through the SAME shared
#       self-validation harness (`lib/triple_harness.sh`, already
#       implemented, C-005) against the 5 fixtures under
#       fixtures/sibling_search_check/ produces the outcome each scenario
#       expects -- self-flipping from RED to GREEN with NO edit to this
#       file.
#
# Contract: specs/004-fast-dev-cycles/contracts/closure-refusal.md CR-004
#   ("Every Bug closure requires a valid SiblingSearchArtefact ... Absent or
#   invalid => REFUSED(missing: sibling-instance search)") +
#   data-model.md §6.4 (SiblingSearchArtefact field list) +
#   common-conventions.md C-001/C-004/C-005. The assumed CLI contract for
#   sibling_search_check.sh (UNCONFIRMED by the contract text itself --
#   neither names an exact argv shape -- DEFINED here, binding-if-adopted on
#   T096's implementer) is documented in
#   fixtures/sibling_search_check/README.md, following the house precedent
#   set by fixtures/verdict_cache/README.md and fixtures/io_trace/README.md.
#
# Task line (tasks.md T088, verbatim): "[P] [US3] [TDD] RED tests
# `constitution/scripts/fastcycle/tests/test_sibling_search_check_red.sh`
# and
# `constitution/scripts/workable-items/cmd/workable-items/fastcycle_sibling_search_test.go`
# (Bug closure without the artefact accepted today; golden-bad: refused;
# golden-bad: an artefact whose search shows no control needle is rejected;
# negative control: a Task closes without it) (plan T-D03; FR-011, SC-004)".
# The Go half (fastcycle_sibling_search_test.go, same task) proves the
# "Bug closure without the artefact accepted today" bullet (today's REAL
# `close` subcommand) and the "negative control: a Task closes without it"
# bullet (the future `closure-check` seam, CR-004's own Tasks-exempt
# clause); THIS shell test proves the two "golden-bad" bullets plus the
# artefact-shape self-validation triple at the standalone-tool layer
# (T096, the tool CR-004's seam calls into).
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# its fixtures under fixtures/sibling_search_check/. It does NOT implement
# closure/sibling_search_check.sh (T096, a separate later task), and never
# fabricates a tool-invocation result -- every scenario below is either
# (a) a real grep invocation this file performs itself (Section B,
# self-validating the underlying mechanism), or (b) a real invocation of
# the shared triple_harness.sh runner against the (today, absent) tool,
# reported RED because the runner itself refuses a --tool that is not a
# regular file.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected FAIL>0
#       for Section C's harness invocation -- Section A's control needle
#       and Section B's self-check of the grep MECHANISM are expected to
#       PASS today, since they exercise only this repo's real state and
#       grep itself, never the absent tool).
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$FC/../../.." && pwd)
TOOL="$FC/closure/sibling_search_check.sh"
FIXDIR="$HERE/fixtures/sibling_search_check"
HARNESS="$HERE/lib/triple_harness.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T088 RED (shell half): sibling-instance search artefact validator (plan T-D03; contract CR-004; FR-011, SC-004) =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T096 has landed; Section C's real"
    echo "   triple_harness.sh invocation below is the functional test to run"
else
    echo "RED: $TOOL is absent -- T096 (closure/sibling_search_check.sh) has"
    echo "     not landed yet, confirming this file's own premise is real,"
    echo "     not assumed"
fi

if [ -d "$FC/closure" ]; then
    NON_GITKEEP=$(find "$FC/closure" -maxdepth 1 -type f ! -name '.gitkeep' 2>/dev/null | wc -l)
    if [ "$NON_GITKEEP" -eq 0 ]; then
        ok "control needle: $FC/closure/ genuinely holds nothing but .gitkeep --"
        echo "   confirms sibling_search_check.sh is absent by DIRECTORY"
        echo "   CONTENT, not merely by the single-path check above"
    else
        echo "NOTE: $FC/closure/ holds $NON_GITKEEP non-.gitkeep file(s) already --"
        echo "      re-check whether T096 (or a sibling closure task) has"
        echo "      partially landed"
    fi
else
    bad "control needle FAILED: $FC/closure/ does not exist at all -- Setup"
    echo "   phase (T001-T006) has not created it"
fi

if [ ! -f "$HARNESS" ]; then
    bad "control needle FAILED: $HARNESS does not exist -- T007/T008/T010's"
    echo "   shared C-001..C-007 self-validation machinery has not landed;"
    echo "   Section C below cannot even attempt to drive the (absent) tool"
else
    ok "control needle: the shared self-validation harness $HARNESS"
    echo "   genuinely exists (T007/T008/T010 landed it) -- Section C can"
    echo "   drive the (today, absent) tool through it"
fi

if [ ! -d "$FIXDIR" ]; then
    bad "control needle FAILED: $FIXDIR does not exist -- this RED test's"
    echo "   own fixtures are missing; re-check the commit that added this file"
else
    ok "control needle: this RED test's own fixture directory $FIXDIR"
    echo "   genuinely exists on disk"
fi

# =============================================================================
# Section B -- self-validation of the underlying SEARCH + CONTROL-NEEDLE
# mechanism (§11.4.107(10)/§11.4.273: "the path is part of the instrument" --
# proving the grep-style search this file's own fixtures describe genuinely
# finds a real, known-present symbol in THIS repo, BEFORE any claim is made
# about what the (absent) real sibling_search_check.sh tool should accept or
# reject from an artefact that cites it). This is never a substitute for
# Section C's real tool invocations -- it only proves the mechanism T096's
# implementer will validate artefacts OF is sound.
# =============================================================================
WI_DIR="$REPO_ROOT/constitution/scripts/workable-items/cmd/workable-items"
if [ ! -d "$WI_DIR" ]; then
    bad "self-check FAILED: $WI_DIR does not exist -- the control needle"
    echo "   every fixture in $FIXDIR cites (crud.go:requireEvidencePath)"
    echo "   cannot possibly be real; re-derive REPO_ROOT before trusting"
    echo "   anything in Section C"
else
    NEEDLE_HITS=$(grep -rl 'requireEvidencePath' "$WI_DIR" 2>/dev/null | wc -l)
    if [ "$NEEDLE_HITS" -gt 0 ]; then
        ok "self-check: a real 'grep -rl requireEvidencePath' against"
        echo "   $WI_DIR genuinely found $NEEDLE_HITS file(s) -- the control"
        echo "   needle every fixture below cites (crud.go:requireEvidencePath)"
        echo "   is a REAL, present symbol, not a fabricated placeholder"
        echo "   (§11.4.273(b): a control needle proven found through the"
        echo "   same class of search the fixture itself describes)"
    else
        bad "self-check FAILED: 'grep -rl requireEvidencePath' against"
        echo "   $WI_DIR found NOTHING -- either the symbol was renamed/moved"
        echo "   (re-derive the fixtures' control_needle field) or grep itself"
        echo "   is not behaving as expected on this host"
    fi

    # Negative half of the same self-check (§11.4.201(1) false-positive
    # guard on the SELF-CHECK itself, not the absent tool): a genuinely
    # fabricated symbol name must NOT be found by the identical search --
    # proving the positive hit above is not an artefact of an
    # over-permissive grep invocation (e.g. an unquoted glob matching
    # everything).
    FABRICATED="xyzzy_not_a_real_symbol_T088_negative_control_qqq"
    FAB_HITS=$(grep -rl "$FABRICATED" "$WI_DIR" 2>/dev/null | wc -l)
    if [ "$FAB_HITS" -eq 0 ]; then
        ok "self-check negative control: a fabricated symbol"
        echo "   ($FABRICATED) is correctly NOT found by the identical"
        echo "   'grep -rl' search -- the positive hit above is a genuine"
        echo "   needle match, not an over-permissive search"
    else
        bad "self-check negative control FAILED: the fabricated symbol"
        echo "   $FABRICATED was found $FAB_HITS time(s) -- grep is somehow"
        echo "   matching everything on this host; the positive needle check"
        echo "   above cannot be trusted"
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "NOTE: python3 not found -- if T096's implementer chooses a"
    echo "      python3-based JSON-shape validator, Section C's real"
    echo "      invocations below will need it; not required for THIS"
    echo "      RED test's own checks"
fi

# =============================================================================
# Section C -- real invocation of the shared self-validation harness
# (triple_harness.sh, C-005) against the (today, absent) sibling_search_
# check.sh tool over the 5 fixtures under fixtures/sibling_search_check/.
# This is a REAL command execution, never a synthetic "tool absent ->
# assume PASS" stub: the harness's own `[ -f "$tool" ]` guard genuinely
# refuses a --tool that is not a regular file, so the moment T096 lands,
# this single invocation self-flips to running the real per-fixture
# verdicts -- with NO further edits to this file.
# =============================================================================
if [ ! -f "$HARNESS" ]; then
    bad "C1: cannot invoke triple_harness.sh -- it does not exist (see"
    echo "    Section A control needle above)"
else
    HARNESS_OUT=$(sh "$HARNESS" --tool "$TOOL" --fixtures "$FIXDIR" 2>&1)
    HARNESS_RC=$?
    if [ -f "$TOOL" ]; then
        # T096 has landed: the harness genuinely ran the tool over every
        # fixture. rc 0 means every scenario matched its expectation
        # (golden-good/negative-control exit 0; every golden-bad* exit 1
        # AND named its expected token). Print the harness's own per-fixture
        # JSON verdict lines for a human/CI reviewer to read directly.
        if [ "$HARNESS_RC" -eq 0 ]; then
            ok "C1: triple_harness.sh reports ALL 5 fixtures matched their"
            echo "    expectation against the real sibling_search_check.sh:"
            echo "$HARNESS_OUT" | sed 's/^/    /'
        else
            bad "C1: triple_harness.sh reports a MISMATCH (rc=$HARNESS_RC)"
            echo "    against the real sibling_search_check.sh -- at least"
            echo "    one of golden-good / golden-bad /"
            echo "    golden-bad-needle-not-found /"
            echo "    golden-bad-invalid-disposition / negative-control did"
            echo "    not behave as this RED test's own contract requires:"
            echo "$HARNESS_OUT" | sed 's/^/    /'
        fi
    else
        # T096 has NOT landed: the harness's own `[ -f "$tool" ]` guard
        # refuses immediately with "bad --tool" (exit 2) -- this IS the
        # genuine RED signal, confirmed live, not fabricated.
        if [ "$HARNESS_RC" -eq 2 ] && echo "$HARNESS_OUT" | grep -q 'bad --tool'; then
            bad "C1 (expected RED): triple_harness.sh correctly refuses"
            echo "    (rc=2, \"bad --tool\") because sibling_search_check.sh"
            echo "    does not exist yet -- this is the documented absence,"
            echo "    not a harness defect (self-flips to a real per-fixture"
            echo "    verdict the moment T096 lands, with no edit to this"
            echo "    file): $HARNESS_OUT"
        else
            bad "C1: UNEXPECTED harness behaviour with the tool absent --"
            echo "    wanted rc=2 and \"bad --tool\" (the harness's own"
            echo "    documented refusal for a non-regular-file --tool),"
            echo "    got rc=$HARNESS_RC out=$HARNESS_OUT -- either the"
            echo "    harness's contract changed or REPO_ROOT/TOOL/FIXDIR"
            echo "    were mis-derived above"
        fi
    fi
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
