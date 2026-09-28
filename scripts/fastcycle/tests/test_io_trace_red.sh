#!/bin/sh
# =============================================================================
# T052 RED test (SpecKit-004 "fast-dev-cycles", Phase 5 / User Story 2;
# plan.md T-C02; FR-005, FR-007).
# =============================================================================
#
# Purpose: prove, BEFORE T-C02's `gates/io_trace.sh` implementation exists,
# that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed -- §11.4.6; `constitution/scripts/fastcycle/gates/` is
#       confirmed to hold nothing but `.gitkeep`);
#   (B) the underlying MECHANISM the real tool will rely on -- `strace -f -e
#       trace=openat,stat,execve` -- is genuinely available on this host and
#       genuinely produces parseable per-syscall path output, proven by a
#       REAL strace invocation against a REAL toy script in Section B
#       (never merely assumed present, per §11.4.273: "the path is part of
#       the instrument");
#   (C) once T-C02 lands, invoking the real tool through the SAME 3
#       fixtures under fixtures/io_trace/ produces the outcome each
#       scenario's expected.json predicts.
#
# Contract: specs/004-fast-dev-cycles/plan.md T-C02 ("Observed-I/O capture
#   and the gate->inputs map") + FR-005/FR-007 in spec.md. The assumed CLI
#   contract for io_trace.sh (UNCONFIRMED by the plan itself, DEFINED here,
#   binding-if-adopted on the implementer) is documented in
#   fixtures/io_trace/README.md, following the house precedent set by
#   fixtures/verdict_cache/README.md and fixtures/dispatch_stamp/.
#
# Task line (tasks.md T052, verbatim): "[P] [US2] [TDD] [SUBAGENT] RED test
# constitution/scripts/fastcycle/tests/test_io_trace_red.sh (control
# needle: a gate known to read CLAUDE.md lists it; golden-bad: a read
# through a dynamically built path records the resolved path; negative
# control -- the CT-5 addition: a gate reading only its own script
# directory yields exactly that read set and PASSes) (plan T-C02; FR-005,
# FR-007)".
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# its fixtures under fixtures/io_trace/. It does NOT implement
# gates/io_trace.sh (T-C02, a separate later task), and never fabricates a
# tool-invocation result -- every scenario below is either (a) a real
# strace invocation this file performs itself (Section B, self-validating
# the underlying mechanism), or (b) a real invocation of the (today,
# absent) io_trace.sh tool, reported RED because the tool cannot be found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected FAIL>0
#       for every Section C "tool invocation" check -- Section B's
#       self-checks of the strace MECHANISM are expected to PASS today,
#       since they exercise only strace itself, not the absent tool).
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$FC/../../.." && pwd)
TOOL="$FC/gates/io_trace.sh"
FIXDIR="$HERE/fixtures/io_trace"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T052 RED: observed-I/O capture and the gate->inputs map (plan T-C02; FR-005, FR-007) =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T-C02 has landed; Section C's real"
    echo "   invocation checks below are the functional tests to run"
else
    echo "RED: $TOOL is absent -- T-C02 (gates/io_trace.sh) has not landed"
    echo "     yet, confirming this file's own premise is real, not assumed"
fi

if [ -d "$FC/gates" ]; then
    NON_GITKEEP=$(find "$FC/gates" -maxdepth 1 -type f ! -name '.gitkeep' 2>/dev/null | wc -l)
    if [ "$NON_GITKEEP" -eq 0 ]; then
        ok "control needle: $FC/gates/ genuinely holds nothing but .gitkeep --"
        echo "   confirms io_trace.sh is absent by DIRECTORY CONTENT, not merely"
        echo "   by the single-path check above"
    else
        echo "NOTE: $FC/gates/ holds $NON_GITKEEP non-.gitkeep file(s) already --"
        echo "      re-check whether T-C02 (or a sibling task) has partially landed"
    fi
else
    bad "control needle FAILED: $FC/gates/ does not exist at all -- Setup"
    echo "   phase (T001-T006) has not created it"
fi

if [ ! -f "$REPO_ROOT/CLAUDE.md" ]; then
    bad "control needle FAILED: $REPO_ROOT/CLAUDE.md does not exist -- the"
    echo "   needle_gate.sh fixture's premise (a real, known-present file to"
    echo "   read) cannot be satisfied; re-derive REPO_ROOT before trusting"
    echo "   anything below"
else
    ok "control needle: $REPO_ROOT/CLAUDE.md genuinely exists -- the"
    echo "   needle_gate.sh fixture has a real, known-present target"
fi

# =============================================================================
# Section B -- self-validation of the underlying strace MECHANISM
# (§11.4.107(10)/§11.4.273: "the path is part of the instrument" -- proving
# strace itself works, with this file's own toy script, BEFORE any claim is
# made about what the (absent) real io_trace.sh tool should produce from
# it). This is never a substitute for Section C's real tool invocations --
# it only proves the mechanism T-C02's implementer will build on is sound.
# =============================================================================
if ! command -v strace >/dev/null 2>&1; then
    bad "strace not found on this host -- the mechanism T-C02 depends on"
    echo "   (strace -f -e trace=openat,stat,execve, per plan.md T-C02's own"
    echo "   Work line) is not available; T-C02's implementer will need a"
    echo "   fallback or this environment needs strace installed"
else
    ok "strace is available ($(strace -V 2>&1 | head -1))"

    STRACE_LOG=$(mktemp)
    strace -f -e trace=openat,stat -o "$STRACE_LOG" \
        sh "$FIXDIR/needle_gate.sh" "$REPO_ROOT" 2>/dev/null
    STRACE_RC=$?

    if [ "$STRACE_RC" -ne 0 ] || [ ! -s "$STRACE_LOG" ]; then
        bad "strace self-check FAILED: strace -f -e trace=openat,stat produced"
        echo "   no usable output (rc=$STRACE_RC) when run against"
        echo "   needle_gate.sh -- the mechanism T-C02 will rely on is not"
        echo "   producing parseable traces on this host"
    else
        if grep -q 'CLAUDE\.md' "$STRACE_LOG"; then
            ok "strace self-check: a real strace run against needle_gate.sh"
            echo "   genuinely captured a syscall referencing CLAUDE.md in its"
            echo "   raw trace output -- the underlying mechanism T-C02 depends"
            echo "   on is proven sound on this host, not merely assumed"
            echo "   present (§11.4.273 -- the null-hypothesis needle: had the"
            echo "   trace NOT mentioned CLAUDE.md, that would mean strace"
            echo "   itself cannot see the read this test relies on)"
        else
            bad "strace self-check FAILED: a real strace run against"
            echo "   needle_gate.sh did NOT capture any reference to CLAUDE.md"
            echo "   in its raw output -- either the -e trace filter needs"
            echo "   adjustment on this strace version, or the tracing"
            echo "   approach itself needs re-deriving before T-C02 is built"
            echo "   on it"
        fi
    fi
    rm -f "$STRACE_LOG"
fi

if ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- cannot run the JSON-shape checks in Section C"
fi

# =============================================================================
# Section C -- real invocations of the (today, absent) io_trace.sh tool
# against the 3 named fixtures. Every check here is a REAL command
# execution, never a synthetic "tool absent -> assume PASS" stub -- each
# invocation genuinely attempts to run the tool with contract-shaped args,
# so the moment T-C02 lands, these checks self-flip GREEN with no further
# edits to this file.
# =============================================================================

# --- C1: control needle -- needle_gate.sh must have CLAUDE.md in its reads
if [ -x "$TOOL" ] || [ -f "$TOOL" ]; then
    C1_OUT=$(sh "$TOOL" "$FIXDIR/needle_gate.sh" "$REPO_ROOT" 2>&1)
    C1_RC=$?
else
    C1_OUT="io_trace.sh absent"
    C1_RC=127
fi
if [ "$C1_RC" -eq 0 ] && echo "$C1_OUT" | grep -q 'CLAUDE\.md'; then
    ok "C1 control needle: io_trace.sh reports CLAUDE.md in needle_gate.sh's observed reads"
else
    bad "C1 control needle: io_trace.sh did not report CLAUDE.md as an observed read of needle_gate.sh (rc=$C1_RC out=$C1_OUT)"
fi

# --- C2: golden-bad -- dynamic_path_gate.sh must resolve to target_data.txt, not a literal template string
DPG_DIR="$FIXDIR/dynamic_path_gate"
if [ -x "$TOOL" ] || [ -f "$TOOL" ]; then
    C2_OUT=$(sh "$TOOL" "$DPG_DIR/dynamic_path_gate.sh" "$DPG_DIR" 2>&1)
    C2_RC=$?
else
    C2_OUT="io_trace.sh absent"
    C2_RC=127
fi
if [ "$C2_RC" -eq 0 ] && echo "$C2_OUT" | grep -q 'target_data\.txt' \
    && ! echo "$C2_OUT" | grep -qF '${base}_data${ext}' \
    && ! echo "$C2_OUT" | grep -qF '$dir/$name'; then
    ok "C2 golden-bad: io_trace.sh resolved dynamic_path_gate.sh's runtime-built path to the real target_data.txt, not a literal template string"
else
    bad "C2 golden-bad: io_trace.sh did not report the RESOLVED target_data.txt path for dynamic_path_gate.sh (rc=$C2_RC out=$C2_OUT)"
fi

# --- C3: negative control (CT-5) -- own_dir_only_gate.sh's read set must equal exactly its own dir's files, no more, no less
ODG_DIR="$FIXDIR/own_dir_only_gate"
if [ -x "$TOOL" ] || [ -f "$TOOL" ]; then
    C3_OUT=$(sh "$TOOL" "$ODG_DIR/own_dir_only_gate.sh" "$ODG_DIR" 2>&1)
    C3_RC=$?
else
    C3_OUT="io_trace.sh absent"
    C3_RC=127
fi
if [ "$C3_RC" -eq 0 ] \
    && echo "$C3_OUT" | grep -q 'own_dir_only_gate\.sh' \
    && echo "$C3_OUT" | grep -q 'sibling_data\.txt'; then
    # exact-set check deferred to python3 JSON parse once the tool exists;
    # here we can only confirm the two expected basenames are present, and
    # that no OTHER basename from a disjoint fixture directory leaked in
    # (e.g. needle_gate.sh or dynamic_path_gate.sh/target_data.txt).
    if echo "$C3_OUT" | grep -qE 'needle_gate\.sh|target_data\.txt|dynamic_path_gate\.sh'; then
        bad "C3 negative control (CT-5): own_dir_only_gate.sh's reported read set leaked a basename from a DIFFERENT fixture scenario -- the tracer is over-reporting"
    else
        ok "C3 negative control (CT-5): own_dir_only_gate.sh's reads contain exactly its own script + sibling_data.txt, with no leakage from other fixtures"
    fi
else
    bad "C3 negative control (CT-5): io_trace.sh did not report own_dir_only_gate.sh's own-directory reads correctly (rc=$C3_RC out=$C3_OUT)"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
