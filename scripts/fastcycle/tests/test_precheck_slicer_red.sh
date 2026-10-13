#!/bin/sh
# =============================================================================
# T061 RED test (SpecKit-004 "fast-dev-cycles", Phase 5 / User Story 2;
# plan.md T-C11; FR-023, SC-009, SC-002).
# =============================================================================
#
# Purpose: prove, BEFORE T-C11's `review/slicer.py`, `review/precheck_pack.sh`,
# and `review/review_record.py`'s `gate` subcommand are implemented (T078),
# that:
#   (A) all three are genuinely absent/unregistered today (control needles:
#       measured by real invocation, not assumed -- §11.4.6);
#   (B) the underlying MECHANISM the real `precheck_pack.sh` will rely on for
#       its "parse" and "shellcheck" DEC-33 checks -- `sh -n`/`bash -n` and
#       `shellcheck` -- genuinely detects two REAL, planted defects on this
#       host, proven by REAL invocations against REAL toy scripts in Section B
#       (never merely assumed present, per §11.4.273: "the path is part of
#       the instrument");
#   (C) once T-C11 lands, invoking the real tools through the fixtures under
#       fixtures/precheck_slicer/ produces the outcome each scenario's
#       documented expectation predicts, for the 4 cases named verbatim in
#       tasks.md T061.
#
# Contract: specs/004-fast-dev-cycles/contracts/review-batch-and-precheck.md
#   (RB-001..RB-007, read in full before this file was written) +
#   specs/004-fast-dev-cycles/plan.md T-C11 section + FR-023/SC-009/SC-002 in
#   spec.md. The `--changes <list>` wire format for slicer.py (UNCONFIRMED by
#   the contract beyond "sha-range|list") is this file's own definition,
#   documented in fixtures/precheck_slicer/README.md, binding-if-adopted on
#   T-C11's implementer, following house precedent
#   (fixtures/verdict_cache/README.md, fixtures/io_trace/README.md).
#
# Task line (tasks.md T061, verbatim): "[P] [US2] [TDD] [SUBAGENT] RED test
# constitution/scripts/fastcycle/tests/test_precheck_slicer_red.sh per
# contract review-batch-and-precheck (a review request without a pack is
# accepted today; golden: a planted lint error appears in the pack, not in
# the review; golden-bad: a review record with a non-pinned tier or effort
# is refused; negative control: an unrelated change is not batched with the
# others) (plan T-C11; FR-023, SC-009, SC-002)".
#
# Distinct from, and does NOT duplicate, T018's
# tests/test_review_record_red.sh (fixtures/review_record/rb_bad_wrong_tier,
# rb_bad_low_effort, rb_negctrl_unknown_effort) -- that file already proves,
# and keeps GREEN today (T034 has landed `record`/`backfill`), that
# review_record.py's `record` subcommand itself refuses a non-pinned
# tier/effort AT WRITE TIME. This file's case 3 (below) exercises the
# genuinely different, defense-in-depth question RB-004/RB-006 also demand:
# once a non-pinned-tier record exists ON DISK (placed here via the REAL,
# already-landed `backfill` subcommand, which -- unlike `record` -- does NOT
# validate tier/effort, empirically confirmed before this file was written),
# does the absent `gate` subcommand still correctly refuse to count it as
# coverage? See fixtures/precheck_slicer/README.md "Case 3" for the full
# reasoning.
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test + its
# fixtures under fixtures/precheck_slicer/. It does NOT implement
# review/slicer.py, review/precheck_pack.sh, or review_record.py's `gate`
# subcommand (T-C11/T078, a separate later task), and never fabricates a
# tool-invocation result -- every scenario below is either (a) a real
# `sh -n`/`bash -n`/`shellcheck` invocation this file performs itself
# (Section B, self-validating the underlying mechanism), (b) a real
# invocation of the ALREADY-LANDED `review_record.py record`/`backfill`
# subcommands (used to ground fixture assumptions in real tool output, never
# as a stub for the absent tools), or (c) a real invocation of the (today,
# absent) slicer.py/precheck_pack.sh/`gate`, reported RED because the tool
# or subcommand cannot be found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected FAIL>0
#       for every real invocation of an absent tool/subcommand -- Section B's
#       self-checks of the parse/shellcheck MECHANISM, and the real
#       record/backfill invocations grounding cases 1/2/3, are expected to
#       PASS today, since they exercise only real, already-landed components,
#       never the absent ones).
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$FC/../../.." && pwd)
REVIEW_DIR="$FC/review"
SLICER="$REVIEW_DIR/slicer.py"
PRECHECK="$REVIEW_DIR/precheck_pack.sh"
RECORD_TOOL="$REVIEW_DIR/review_record.py"
FIXDIR="$HERE/fixtures/precheck_slicer"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

TMP=$(mktemp -d) || { echo "cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
reap_children() {
  # Process-leak guard (house convention, test_review_record_red.sh): kill
  # anything this test spawned whose command line names $TMP, in case a
  # future implementation leaves a descendant running past our own reap.
  pkill -KILL -f "$TMP" 2>/dev/null
  return 0
}
trap 'reap_children; rm -rf "$TMP"' EXIT
trap 'reap_children; rm -rf "$TMP"; exit 130' INT
trap 'reap_children; rm -rf "$TMP"; exit 143' TERM

echo "== T061 RED: machine pre-check pack, review slicing and batching (plan T-C11; FR-023, SC-009, SC-002) =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption carried over from plan.md/the contract.
# =============================================================================

# --- A1: slicer.py genuinely absent ---
if [ -f "$SLICER" ]; then
    echo "ok slicer.py exists at $SLICER -- T-C11 has landed; Section C's"
    echo "   real invocation checks below are the functional tests to run"
else
    echo "RED: $SLICER is absent -- T-C11 (review/slicer.py) has not landed"
    echo "     yet, confirming this file's own premise is real, not assumed"
fi

# --- A2: precheck_pack.sh genuinely absent ---
if [ -f "$PRECHECK" ]; then
    echo "ok precheck_pack.sh exists at $PRECHECK -- T-C11 has landed"
else
    echo "RED: $PRECHECK is absent -- T-C11 (review/precheck_pack.sh) has"
    echo "     not landed yet"
fi

# --- A3: control needle -- review/ genuinely holds nothing that could ---
# satisfy slicer.py/precheck_pack.sh beyond the already-landed
# review_record.py (+ its __pycache__), confirmed by DIRECTORY CONTENT, not
# merely by the two single-path checks above.
if [ -d "$REVIEW_DIR" ]; then
    UNEXPECTED=$(find "$REVIEW_DIR" -maxdepth 1 -type f \
        ! -name 'review_record.py' ! -name '.gitkeep' 2>/dev/null | wc -l)
    if [ "$UNEXPECTED" -eq 0 ]; then
        ok "control needle: $REVIEW_DIR/ genuinely holds no file besides"
        echo "   review_record.py -- confirms slicer.py/precheck_pack.sh are"
        echo "   absent by DIRECTORY CONTENT, not merely by A1/A2's checks"
    else
        echo "NOTE: $REVIEW_DIR/ holds $UNEXPECTED unexpected file(s) --"
        echo "      re-check whether T-C11 (or a sibling task) has partially"
        echo "      landed before trusting A1/A2 above"
    fi
else
    bad "control needle FAILED: $REVIEW_DIR does not exist at all"
fi

# --- A4: review_record.py's `gate` subcommand -- pre-T078 absence needle,
# post-T078 real-behaviour needle (distinct from A1/A2: review_record.py
# the FILE exists, T034/T018 landed it; only whether `gate` is registered
# on it changes here).
#
# T078 fix-forward (documented per this project's own HARD RULES "never
# weaken the test... if it has a genuine bug, fix forward with documented
# evidence"): this block originally scored `bad` on ANY outcome other
# than the pre-landing "invalid choice: 'gate'" signature -- with no
# second branch for the POST-landing state, unlike A1/A2's own two-branch
# `if -f exists; ok "landed" ... else echo "RED: absent"` pattern. Once
# `gate` is genuinely registered (T078), the pre-landing signature can
# never reappear by construction, so the original code would permanently
# score `bad` here even on a fully correct T078 landing -- an inverted
# control needle, not a real regression signal. Fixed forward by adding
# the missing landed-state branch, mirroring A1/A2: it makes its OWN real
# assertion (a genuinely nonexistent --records dir refuses with the
# DEC-33 contract's own documented exit code 4, naming the unreadable
# path -- specs/004-fast-dev-cycles/contracts/review-batch-and-precheck.md
# "Exit codes": "gate 0 covered, 1 uncovered (lists changes), 4 records
# unreadable"), never a bare exit-code-only relaxation of the original
# check -- verified for real before this fix landed: rc=4, stderr
# "review_record: gate refused -- --records is not a readable directory:
# y".
if [ ! -f "$RECORD_TOOL" ]; then
    bad "control needle FAILED: $RECORD_TOOL does not exist at all -- T034"
    echo "   (which this file's cases 1/2/3 depend on for real) has not"
    echo "   landed; re-derive REPO_ROOT/paths before trusting anything below"
else
    GATE_ERR=$(python3 "$RECORD_TOOL" gate --change x --records y 2>&1 >/dev/null)
    GATE_RC=$?
    if [ "$GATE_RC" -ne 0 ] && echo "$GATE_ERR" | grep -qF "invalid choice: 'gate'"; then
        ok "control needle: review_record.py's \`gate\` subcommand is"
        echo "   genuinely unregistered today (real argparse rc=$GATE_RC,"
        echo "   stderr names 'gate' as an invalid choice) -- confirmed by a"
        echo "   real invocation, not assumed from reading source"
    elif [ "$GATE_RC" -eq 4 ] && echo "$GATE_ERR" | grep -qF "not a readable directory"; then
        ok "control needle: review_record.py's \`gate\` subcommand is now"
        echo "   registered and landed (T078) -- a real invocation against a"
        echo "   genuinely nonexistent --records dir correctly refuses with"
        echo "   the contract's own exit code 4 ('records unreadable'),"
        echo "   naming the unreadable path (rc=$GATE_RC,"
        echo "   stderr='$GATE_ERR') -- confirmed by a real invocation, not"
        echo "   assumed from reading source"
    else
        bad "control needle FAILED: review_record.py gate did not fail the"
        echo "   way expected (rc=$GATE_RC, stderr='$GATE_ERR') -- either"
        echo "   \`gate\` has landed with different behaviour than the"
        echo "   contract documents (re-check T078's compliance) or"
        echo "   something else about review_record.py changed; re-derive"
        echo "   before trusting case 3 below"
    fi
fi

# --- A5: no dispatch-enforcement hook exists in either hooks directory ---
# (plan.md line 236 names `scripts/hooks/review_dispatch_guard.sh` as the
# NEW hook T-C11 introduces -- "refuses a review without a pre-check pack or
# off-tier record". Its absence is the structural reason case 1's baseline
# below is real: nothing currently enforces the pack requirement. Bounded
# to the two real hooks directories (repo-root `scripts/hooks/` and
# `constitution/scripts/hooks/`, where every other project hook lives) --
# NOT a whole-repo `find` (a real bug caught while authoring this file: an
# earlier draft searched the full ~584K-file AOSP tree and took >20s for
# this one check alone, defeating the point of a fast-dev-cycles test;
# fixed to search only the two directories the plan itself names).
GUARD_HITS=0
for HOOKS_DIR in "$REPO_ROOT/scripts/hooks" "$REPO_ROOT/constitution/scripts/hooks"; do
    if [ -d "$HOOKS_DIR" ]; then
        HITS=$(find "$HOOKS_DIR" -maxdepth 1 -iname 'review_dispatch_guard*' 2>/dev/null | wc -l)
        GUARD_HITS=$((GUARD_HITS + HITS))
    fi
done
if [ "$GUARD_HITS" -eq 0 ]; then
    ok "control needle: no review_dispatch_guard.sh (or similarly-named"
    echo "   file) exists in scripts/hooks/ or constitution/scripts/hooks/"
    echo "   -- confirmed by real, bounded finds, not assumed -- there is"
    echo "   currently NO mechanism that could refuse an unpacked review"
    echo "   request"
else
    echo "NOTE: $GUARD_HITS file(s) matching review_dispatch_guard* found --"
    echo "      re-check whether the T-C11 dispatch guard has landed before"
    echo "      trusting case 1's baseline premise below"
fi

if ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- cannot run the JSON-shape checks in this file"
fi

# =============================================================================
# Section B -- self-validation of the underlying parse/shellcheck MECHANISM
# (§11.4.107(10)/§11.4.273: "the path is part of the instrument" -- proving
# `sh -n`/`bash -n` and `shellcheck` genuinely detect this file's own two
# planted defects, BEFORE any claim is made about what the (absent) real
# precheck_pack.sh should produce from them). Never a substitute for Section
# C's real tool invocations -- it only proves the mechanism T-C11's
# implementer will build on is sound, and that this RED test's own
# expected_precheck.json fixture (case 2) is grounded in real tool output,
# not invented.
# =============================================================================

BROKEN_SYNTAX="$FIXDIR/case2_lint_in_pack/broken_syntax_gate.sh"
UNQUOTED_VAR="$FIXDIR/case2_lint_in_pack/unquoted_var_gate.sh"

# --- B1: sh -n / bash -n genuinely detects the planted parse error ---
if [ ! -f "$BROKEN_SYNTAX" ]; then
    bad "B1: fixture $BROKEN_SYNTAX is missing -- cannot self-validate the"
    echo "   parse-check mechanism"
else
    sh -n "$BROKEN_SYNTAX" >"$TMP/b1_sh.out" 2>"$TMP/b1_sh.err"
    B1_SH_RC=$?
    if [ "$B1_SH_RC" -ne 0 ] && grep -q 'syntax error' "$TMP/b1_sh.err"; then
        ok "B1 self-check: a real 'sh -n' run against broken_syntax_gate.sh"
        echo "   genuinely reports a syntax error (rc=$B1_SH_RC,"
        echo "   '$(cat "$TMP/b1_sh.err")') -- the underlying parse-check"
        echo "   mechanism T-C11 depends on is proven sound on this host,"
        echo "   not merely assumed present (§11.4.273 -- the null-hypothesis"
        echo "   needle: had 'sh -n' reported success, that would mean this"
        echo "   fixture's own planted defect is not real, and case 2's"
        echo "   golden premise would be false)"
    else
        bad "B1 self-check FAILED: 'sh -n' against broken_syntax_gate.sh did"
        echo "   NOT report a syntax error (rc=$B1_SH_RC,"
        echo "   stderr='$(cat "$TMP/b1_sh.err")') -- the planted defect is"
        echo "   not being detected on this host; re-derive the fixture"
        echo "   before trusting case 2 below"
    fi
fi

# --- B2: shellcheck genuinely detects the planted SC2086 ---
if ! command -v shellcheck >/dev/null 2>&1; then
    echo "NOTE: shellcheck not found on this host -- B2 self-check skipped"
    echo "      (honest gap, not a fabricated PASS; case 2's shellcheck half"
    echo "      cannot be self-validated in THIS run, per §11.4.6)"
elif [ ! -f "$UNQUOTED_VAR" ]; then
    bad "B2: fixture $UNQUOTED_VAR is missing -- cannot self-validate the"
    echo "   shellcheck mechanism"
else
    shellcheck -s sh "$UNQUOTED_VAR" >"$TMP/b2_sc.out" 2>"$TMP/b2_sc.err"
    B2_SC_RC=$?
    if [ "$B2_SC_RC" -ne 0 ] && grep -q 'SC2086' "$TMP/b2_sc.out"; then
        ok "B2 self-check: a real 'shellcheck -s sh' run against"
        echo "   unquoted_var_gate.sh genuinely reports SC2086 (rc=$B2_SC_RC)"
        echo "   -- the underlying shellcheck mechanism T-C11 depends on is"
        echo "   proven sound on this host, not merely assumed present"
        echo "   (§11.4.273 -- had shellcheck NOT reported SC2086, that would"
        echo "   mean this fixture's own planted defect is not real)"
    else
        bad "B2 self-check FAILED: 'shellcheck -s sh' against"
        echo "   unquoted_var_gate.sh did NOT report SC2086 (rc=$B2_SC_RC,"
        echo "   stdout='$(cat "$TMP/b2_sc.out")') -- re-derive the fixture"
        echo "   before trusting case 2 below"
    fi
fi

# =============================================================================
# Section C -- the 4 named cases (tasks.md T061, verbatim order). Every
# check here is a REAL command execution, never a synthetic "tool absent ->
# assume PASS" stub -- each invocation genuinely attempts to run the real
# CLI with contract-shaped args, so the moment T-C11 lands, these checks
# self-flip GREEN with no further edits to this file.
# =============================================================================

# -----------------------------------------------------------------------
# C1 -- "a review request without a pack is accepted today" (baseline
# needle: the PRE-state T-C11 will change, not something the absent tool
# is claimed to produce). Real invocation of the ALREADY-LANDED
# review_record.py record, with NO --precheck flag and NO sibling
# precheck.json present in the scratch dir.
# -----------------------------------------------------------------------
C1_DIR="$TMP/c1"
mkdir -p "$C1_DIR"
cp "$FIXDIR/case1_no_pack/batch.json" "$C1_DIR/batch.json"
cp "$FIXDIR/case1_no_pack/verdict.json" "$C1_DIR/verdict.json"
# Deliberately NOT copying any precheck.json -- proving the absence, not
# merely asserting it.
if [ -e "$C1_DIR/precheck.json" ]; then
    bad "C1 setup FAILED: a precheck.json leaked into the scratch dir --"
    echo "   the baseline premise cannot be tested cleanly"
else
    ok "C1 setup: scratch dir genuinely has no precheck.json (confirmed by"
    echo "   real -e check, not assumed)"
fi
C1_OUT="$C1_DIR/rev.json"
python3 "$RECORD_TOOL" record \
    --batch "$C1_DIR/batch.json" --round 1 --verdict-file "$C1_DIR/verdict.json" \
    --tier opus --effort xhigh --out "$C1_OUT" >"$TMP/c1.out" 2>"$TMP/c1.err"
C1_RC=$?
if [ "$C1_RC" -eq 0 ] && [ -f "$C1_OUT" ]; then
    ok "C1: review_record.py record ACCEPTED (exit 0) a review with no"
    echo "   --precheck flag and no sibling precheck.json -- a genuine review"
    echo "   is recordable today with no machine pre-check pack at all"
else
    bad "C1: review_record.py record did NOT accept the no-pack review as"
    echo "   expected (rc=$C1_RC, stderr='$(cat "$TMP/c1.err")') -- either"
    echo "   record's behaviour changed, or something in the fixture is"
    echo "   wrong; re-derive before trusting this test's premise"
fi
C1_PRECHECK_USED=$(python3 - "$C1_OUT" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    print("UNREADABLE")
    raise SystemExit
print(doc.get("precheck_used", "MISSING") if isinstance(doc, dict) else "NOT_AN_OBJECT")
PY
)
if [ "$C1_PRECHECK_USED" = "False" ]; then
    ok "C1: the real recorded review's precheck_used field is False --"
    echo "   proving, from the tool's own real output JSON, that this review"
    echo "   genuinely proceeded with NO machine pre-check consulted (the"
    echo "   exact baseline the absent dispatcher/precheck_pack.sh must"
    echo "   change once T-C11 lands)"
else
    bad "C1: expected precheck_used=False in the real record output, got"
    echo "   '$C1_PRECHECK_USED' -- either the field's spelling changed or"
    echo "   the baseline assumption above is wrong"
fi

# -----------------------------------------------------------------------
# C2 -- golden: "a planted lint error appears in the pack, not in the
# review". Two halves: (a) the absent precheck_pack.sh must surface the two
# real, self-validated (Section B) defects in its own output; (b) the
# ALREADY-LANDED review_record.py record, given a genuinely clean (zero
# finding) verdict for the SAME batch, must carry no finding about them.
# -----------------------------------------------------------------------
C2_DIR="$TMP/c2"
mkdir -p "$C2_DIR"
cp "$FIXDIR/case2_lint_in_pack/broken_syntax_gate.sh" "$C2_DIR/"
cp "$FIXDIR/case2_lint_in_pack/unquoted_var_gate.sh" "$C2_DIR/"
cp "$FIXDIR/case2_lint_in_pack/batch.json" "$C2_DIR/batch.json"
cp "$FIXDIR/case2_lint_in_pack/clean_review_verdict.json" "$C2_DIR/verdict.json"

# --- C2a: real invocation of the (pre-T078) absent precheck_pack.sh ---
#
# T078 fix-forward (documented per this project's own HARD RULES "never
# weaken the test... if it has a genuine bug, fix forward with documented
# evidence"): this block originally required C2A_RC -eq 0 for the
# GREEN-mode branch. That contradicts the DEC-33 contract's own stated
# exit codes (specs/004-fast-dev-cycles/contracts/review-batch-and-
# precheck.md "Exit codes": "precheck 0 all pass, 1 any fail, 4 clean
# checkout unavailable") -- this fixture's own two files are DELIBERATELY
# planted defects (module docstring above: "a genuine, planted parse
# error"/"a genuine, planted shellcheck SC2086 issue"), so a CORRECT
# precheck_pack.sh implementation MUST report all_pass=false and MUST
# therefore exit 1, never 0, for this exact batch. Verified against a
# real precheck_pack.sh run before this fix landed: rc=1, --out written,
# all_pass=false, both a "parse" FAIL citing "syntax error" and a
# "shellcheck" FAIL citing "SC2086" present -- exactly the golden shape
# fixtures/precheck_slicer/case2_lint_in_pack/expected_precheck.json
# documents, on a run this same block's own "else" branch was incorrectly
# routing to "bad" (rc=1 != the old check's rc=0) as though the tool were
# still absent. Corrected to require rc -eq 1 (this golden case's real,
# contractually-correct exit code), never weakening what the branch
# actually verifies below (all_pass=false AND a FAIL check citing the
# real evidence are still both required).
sh "$PRECHECK" --config "$FIXDIR/case2_lint_in_pack" \
    --batch "$C2_DIR/batch.json" --clean-checkout "$C2_DIR" \
    --out "$C2_DIR/precheck.json" >"$TMP/c2a.out" 2>"$TMP/c2a.err"
C2A_RC=$?
if [ "$C2A_RC" -eq 1 ] && [ -f "$C2_DIR/precheck.json" ]; then
    # GREEN mode: the real tool exists; check its real output for real.
    C2A_ALL_PASS=$(python3 - "$C2_DIR/precheck.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
print(doc.get("all_pass", "MISSING"))
PY
)
    C2A_HAS_LINT=$(python3 - "$C2_DIR/precheck.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
checks = doc.get("checks") or []
hit = any(
    isinstance(c, dict)
    and c.get("verdict") == "FAIL"
    and ("SC2086" in str(c.get("evidence", "")) or "syntax error" in str(c.get("evidence", "")))
    for c in checks
)
print("YES" if hit else "NO")
PY
)
    if [ "$C2A_ALL_PASS" = "False" ] && [ "$C2A_HAS_LINT" = "YES" ]; then
        ok "C2a: precheck_pack.sh reports all_pass=false with a FAIL check"
        echo "   citing the planted SC2086/syntax defect -- the error is in"
        echo "   the pack, as the golden case requires"
    else
        bad "C2a: precheck_pack.sh's real output did not contain the"
        echo "   expected FAIL/evidence (all_pass=$C2A_ALL_PASS,"
        echo "   has_lint=$C2A_HAS_LINT)"
    fi
else
    bad "C2a: precheck_pack.sh is absent/failed (rc=$C2A_RC,"
    echo "   stderr='$(cat "$TMP/c2a.err")') -- T-C11 has not landed;"
    echo "   fixtures/precheck_slicer/case2_lint_in_pack/expected_precheck.json"
    echo "   documents the required GREEN-branch shape once it does"
fi

# --- C2b: real invocation of the ALREADY-LANDED review_record.py record,
# with a genuinely clean (zero-finding) verdict for the same batch ---
C2B_OUT="$C2_DIR/rev.json"
python3 "$RECORD_TOOL" record \
    --batch "$C2_DIR/batch.json" --round 1 --verdict-file "$C2_DIR/verdict.json" \
    --tier opus --effort xhigh --out "$C2B_OUT" >"$TMP/c2b.out" 2>"$TMP/c2b.err"
C2B_RC=$?
if [ "$C2B_RC" -eq 0 ] && [ -f "$C2B_OUT" ]; then
    ok "C2b: review_record.py record accepted the clean (zero-finding)"
    echo "   verdict for the same batch (real exit 0)"
else
    bad "C2b: review_record.py record did NOT accept the clean verdict"
    echo "   (rc=$C2B_RC, stderr='$(cat "$TMP/c2b.err")')"
fi
C2B_FINDING_COUNT=$(python3 - "$C2B_OUT" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    print("-1")
    raise SystemExit
findings = doc.get("findings") if isinstance(doc, dict) else None
print(len(findings) if isinstance(findings, list) else "-1")
PY
)
if [ "$C2B_FINDING_COUNT" = "0" ]; then
    ok "C2b: the real recorded review's findings array is genuinely EMPTY"
    echo "   -- the mechanical lint/parse defect the pack caught (C2a) is NOT"
    echo "   independently re-reported inside the review record; the error"
    echo "   is in the pack, not in the review, proven with two real"
    echo "   artifacts"
else
    bad "C2b: expected 0 findings in the real review record, got"
    echo "   '$C2B_FINDING_COUNT'"
fi

# -----------------------------------------------------------------------
# C3 -- golden-bad: "a review record with a non-pinned tier or effort is
# refused". Uses the ALREADY-LANDED backfill subcommand (which does NOT
# validate tier/effort, unlike record) to place two REAL, on-disk
# ReviewVerdictRecords with a non-pinned tier and a non-pinned effort, then
# queries the absent `gate` subcommand against each. Distinct from T018's
# own record-level refusal fixtures (see README.md "Case 3").
# -----------------------------------------------------------------------
C3_DIR="$TMP/c3"
mkdir -p "$C3_DIR/wt" "$C3_DIR/le"
CHANGE_SHA="sha256:01c1a0b095e5a74560f689ad24169c4dc2e22113a5b1a1b1d0bfd2c4e815a472"

# --- C3 setup: place the two bad-tier/bad-effort records for real via the
# already-landed backfill subcommand ---
python3 "$RECORD_TOOL" backfill \
    --input "$FIXDIR/case3_wrong_tier_gate/backfill_wrong_tier.json" \
    --out "$C3_DIR/wt/rev.json" >"$TMP/c3wt_backfill.out" 2>"$TMP/c3wt_backfill.err"
C3WT_BACKFILL_RC=$?
python3 "$RECORD_TOOL" backfill \
    --input "$FIXDIR/case3_wrong_tier_gate/backfill_low_effort.json" \
    --out "$C3_DIR/le/rev.json" >"$TMP/c3le_backfill.out" 2>"$TMP/c3le_backfill.err"
C3LE_BACKFILL_RC=$?

if [ "$C3WT_BACKFILL_RC" -eq 0 ] && [ -f "$C3_DIR/wt/rev.json" ]; then
    ok "C3 setup: backfill genuinely wrote a real, on-disk record with"
    echo "   model_tier=sonnet (rc=0) -- backfill does not enforce tier,"
    echo "   confirmed here by a real invocation, not by reading source"
else
    bad "C3 setup FAILED: backfill (wrong-tier spec) did not write a record"
    echo "   as expected (rc=$C3WT_BACKFILL_RC,"
    echo "   stderr='$(cat "$TMP/c3wt_backfill.err")') -- case 3's"
    echo "   wrong-tier half cannot be tested"
fi
if [ "$C3LE_BACKFILL_RC" -eq 0 ] && [ -f "$C3_DIR/le/rev.json" ]; then
    ok "C3 setup: backfill genuinely wrote a real, on-disk record with"
    echo "   effort=high (rc=0) -- backfill does not enforce effort either,"
    echo "   confirmed here by a real invocation"
else
    bad "C3 setup FAILED: backfill (low-effort spec) did not write a record"
    echo "   as expected (rc=$C3LE_BACKFILL_RC,"
    echo "   stderr='$(cat "$TMP/c3le_backfill.err")') -- case 3's"
    echo "   low-effort half cannot be tested"
fi

# --- C3a: real invocation of the absent `gate` against the wrong-tier record ---
python3 "$RECORD_TOOL" gate --change "$CHANGE_SHA" --records "$C3_DIR/wt" \
    >"$TMP/c3a_gate.out" 2>"$TMP/c3a_gate.err"
C3A_RC=$?
if [ "$C3A_RC" -eq 1 ] && grep -qF "$CHANGE_SHA" "$TMP/c3a_gate.out"; then
    ok "C3a: gate refused (exit 1) to treat the sonnet-tier record as"
    echo "   covering $CHANGE_SHA, naming it in stdout, as the golden-bad"
    echo "   case requires"
else
    bad "C3a: gate is absent/did not refuse the sonnet-tier record as"
    echo "   expected (rc=$C3A_RC, stdout='$(cat "$TMP/c3a_gate.out")',"
    echo "   stderr='$(cat "$TMP/c3a_gate.err")') -- T-C11 has not landed;"
    echo "   fixtures/precheck_slicer/case3_wrong_tier_gate/expected_gate.json"
    echo "   documents the required GREEN-branch shape once it does"
fi

# --- C3b: real invocation of the absent `gate` against the low-effort record ---
python3 "$RECORD_TOOL" gate --change "$CHANGE_SHA" --records "$C3_DIR/le" \
    >"$TMP/c3b_gate.out" 2>"$TMP/c3b_gate.err"
C3B_RC=$?
if [ "$C3B_RC" -eq 1 ] && grep -qF "$CHANGE_SHA" "$TMP/c3b_gate.out"; then
    ok "C3b: gate refused (exit 1) to treat the below-xhigh-effort record as"
    echo "   covering $CHANGE_SHA, naming it in stdout"
else
    bad "C3b: gate is absent/did not refuse the low-effort record as"
    echo "   expected (rc=$C3B_RC, stdout='$(cat "$TMP/c3b_gate.out")',"
    echo "   stderr='$(cat "$TMP/c3b_gate.err")')"
fi

# --- C3c: control needle grounding -- the ALREADY-LANDED record subcommand
# (T018/T034, kept GREEN by test_review_record_red.sh) genuinely refuses the
# SAME bad tier/effort AT WRITE TIME, proving this case-3 fixture's
# assumptions are consistent with record's real, already-verified behaviour
# (not merely asserted here as a duplicate of T018 -- used once, as
# grounding, exactly as T052 used strace and T057 used sha256 to ground
# their own fixtures) ---
python3 "$RECORD_TOOL" record \
    --batch "$FIXDIR/case1_no_pack/batch.json" --round 1 \
    --verdict-file "$FIXDIR/case1_no_pack/verdict.json" \
    --tier sonnet --effort xhigh --out "$TMP/c3c_should_not_exist.json" \
    >"$TMP/c3c.out" 2>"$TMP/c3c.err"
C3C_RC=$?
if [ "$C3C_RC" -eq 1 ] && [ ! -f "$TMP/c3c_should_not_exist.json" ]; then
    ok "C3c control needle: the already-landed record subcommand genuinely"
    echo "   refuses --tier sonnet (real exit 1, nothing written) -- case 3's"
    echo "   premise that a bad-tier record can ONLY reach disk via backfill"
    echo "   is grounded in real, current tool behaviour"
else
    bad "C3c control needle FAILED: record --tier sonnet did not refuse as"
    echo "   expected (rc=$C3C_RC) -- re-derive case 3's premise; this is"
    echo "   the SAME refusal path T018's own rb_bad_wrong_tier fixture"
    echo "   already pins, so a failure here means that path itself changed"
fi

# -----------------------------------------------------------------------
# C4 -- negative control: "an unrelated change is not batched with the
# others". Real invocation of the absent slicer.py against 3 toy changes:
# 2 genuinely related (same config-defined logic group), 1 genuinely
# unrelated (a different logic group).
# -----------------------------------------------------------------------
C4_DIR="$TMP/c4"
mkdir -p "$C4_DIR"
cp "$FIXDIR/case4_unrelated_not_batched/config.yaml" "$C4_DIR/"
cp "$FIXDIR/case4_unrelated_not_batched"/change_widget_*.json "$C4_DIR/"
cp "$FIXDIR/case4_unrelated_not_batched"/change_widget_*.diff "$C4_DIR/"

CHANGES_LIST="$C4_DIR/change_widget_a_1.json,$C4_DIR/change_widget_a_2.json,$C4_DIR/change_widget_c_unrelated.json"
python3 "$SLICER" --config "$C4_DIR/config.yaml" --changes "$CHANGES_LIST" \
    --slice-limit 400 --out "$C4_DIR/batch.json" \
    >"$TMP/c4.out" 2>"$TMP/c4.err"
C4_RC=$?
WIDGET_A1="sha256:538a07cce2baf7f98efb013bbccdee401fe65d294adcb22d3057020afa2605f2"
WIDGET_A2="sha256:ec03963a62b8a47f048015878c2313d7899df85f0ad5b09b500867ee349fb9a2"
WIDGET_C="sha256:78ea8f557204f1251690e45c3179335cb6408cc6f6cf57322ee355ecd68702c9"

if [ "$C4_RC" -eq 0 ] && [ -f "$C4_DIR/batch.json" ]; then
    C4_RESULT=$(python3 - "$C4_DIR/batch.json" "$WIDGET_A1" "$WIDGET_A2" "$WIDGET_C" <<'PY'
import json, sys
path, a1, a2, c = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    docs = [json.load(open(path, encoding="utf-8"))]
except json.JSONDecodeError:
    # possibly multiple batches emitted as JSON Lines
    docs = [json.loads(ln) for ln in open(path, encoding="utf-8") if ln.strip()]

def members_of(doc):
    out = set()
    for s in doc.get("slices") or []:
        out.update(s.get("changes") or [])
    out.update(doc.get("changes") or [])
    return out

batch_for = {}
all_members = set()
for i, d in enumerate(docs):
    m = members_of(d)
    all_members |= m
    for x in m:
        batch_for[x] = i

same_batch = (a1 in batch_for and a2 in batch_for and batch_for[a1] == batch_for[a2])
separated = (c not in batch_for) or (a1 not in batch_for) or (batch_for.get(c) != batch_for.get(a1))
conserved = all_members == {a1, a2, c}

if same_batch and separated and conserved:
    print("OK")
else:
    print("FAIL same_batch=%s separated=%s conserved=%s members=%s" % (same_batch, separated, conserved, sorted(all_members)))
PY
)
    if [ "$C4_RESULT" = "OK" ]; then
        ok "C4: slicer.py batched the 2 related widget_a changes together"
        echo "   and kept the unrelated widget_c change out of that batch,"
        echo "   with every one of the 3 changes conserved across all"
        echo "   produced batches (RB-001)"
    else
        bad "C4: slicer.py's real batch.json did not satisfy RB-001"
        echo "   ($C4_RESULT)"
    fi
else
    bad "C4: slicer.py is absent/failed (rc=$C4_RC,"
    echo "   stderr='$(cat "$TMP/c4.err")') -- T-C11 has not landed;"
    echo "   fixtures/precheck_slicer/case4_unrelated_not_batched/expected_batch.json"
    echo "   documents the required GREEN-branch shape once it does"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
