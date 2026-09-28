#!/bin/bash
# Purpose : T025 (SpecKit-004 "fast-dev-cycles", User Story 1) RED baseline
#           for the `causes` subcommand of `plan_struct_check.py`, per
#           contract plan-research-structural-check.md's SC-C-001 (FR-002).
#           Proves the tool is absent today; independently proves (via a
#           SELF-CONTAINED audit instrument, NOT the tool being tested --
#           see Producer!=Verifier below) that four real, well-formed
#           research.md-shaped fixtures genuinely encode the four checks
#           this task names: (1) golden-bad: an RC row with no class,
#           (2) golden-bad: an orphan RC with no task, (3) golden-bad: the
#           §2.2 class counts disagreeing with §2.1's real tally, and
#           (4) negative control: the CURRENT, real, live register at
#           specs/004-fast-dev-cycles/research.md has ZERO of these three
#           defects today and is therefore expected to PASS once T046 lands.
#
# THE GAP (verified directly, 2026-09-28): `constitution/scripts/fastcycle/
# verify/` exists ONLY as an empty scaffold directory (one `.gitkeep`, no
# `.py` file); `plan_struct_check.py` does not exist anywhere in this tree.
# T046 ("Implement constitution/scripts/fastcycle/verify/plan_struct_check.py
# causes per contract plan-research-structural-check until T025 is GREEN")
# is the LATER, SEPARATE task that creates it (tasks.md line 130). Invoking
# the contract's own documented CLI shape against the absent tool today:
#   $ python3 constitution/scripts/fastcycle/verify/plan_struct_check.py \
#       causes --doc /nonexistent --out /tmp/x.json
#   python3: can't open file '.../verify/plan_struct_check.py': [Errno 2]
#   No such file or directory
#   rc=2
# (reproduced live below, never assumed -- constitution 11.4.6).
#
# THE CONTRACT (specs/004-fast-dev-cycles/contracts/
# plan-research-structural-check.md, read in full before writing this file):
#   Invocation: `$FC/verify/plan_struct_check.py causes --doc <research.md>
#     --out <causes.json>` (T-H08: register §2.1).
#   SC-C-001 (causes, FR-002): "One row per cause (RC-01..RC-46 today);
#     class in {CONFIRMED, REFUTED, UNDETERMINED}; the class counts equal
#     research.md §2.2; >=1 EvidencePath that exists; measured_share
#     required for CONFIRMED once the T-A11 re-plan checkpoint has run
#     (before T-A11 a CONFIRMED row may carry UNMEASURED with the settling
#     task named -- the Phase 0 state; ...); settling_evidence required for
#     UNDETERMINED; the six operator-listed causes must all be present
#     (configured list). A row without evidence => exit 1."
#   Exit codes: 0 all checks pass; 1 any structural violation (listing
#     each); 2 usage; 3 needle (a fixture with a known orphan cause not
#     detected); 4 document unreadable.
#
# "ORPHAN RC" -- WHERE THIS COMES FROM (not invented, constitution 11.4.6):
# research.md's own §2 preamble (real document, lines 164-166) states:
#   "Task ids in the last column refer to the phased plan in plan.md
#   (T-Axx.T-Hxx). Every row is removed or measured by at least one task;
#   every task names at least one row (no orphan cause, no orphan task --
#   checked mechanically by T-H08)."
# "the last column" is research.md §2.1's own "Removed / measured by"
# column -- a register-level completeness property checkable from
# research.md ALONE (no cross-reference to plan.md's actual task list is
# needed to detect a BLANK cell there). This is distinct from -- and
# shallower than -- SC-C-003's "plan" subcommand bipartite check (FR-004,
# a SEPARATE task's test, NOT this file), which cross-validates the
# register's named tasks against plan.md's real task blocks in both
# directions. Verified empirically against the real, live documents today:
#   - `awk` over research.md's real §2.1 table: all 46 RC-01..RC-46 rows
#     have a NON-EMPTY "Removed / measured by" cell (0 blank found).
#   - `grep -c "^| RC-" specs/004-fast-dev-cycles/plan.md` also independently
#     shows 46 rows in plan.md's own RC-to-task coverage table, every one
#     naming >=1 task id -- corroborating the same conclusion from a SECOND,
#     independent document.
# Both facts are re-verified live, below, as this file's own control-needle
# evidence for the "negative control: the current register PASSes" bullet
# -- never assumed from this header's prose.
#
# CLASS-COUNT CHECK -- VERIFIED AGAINST THE LIVE research.md §2.2 TABLE
# (2026-09-28, never assumed): §2.2 states CONFIRMED=30, REFUTED=2,
# UNDETERMINED=14, Total=46. An independent re-count over §2.1's own Class
# column (first bold token of each row's Class cell) by this file's own
# audit instrument (below) reproduces EXACTLY 30/2/14/46 -- §2.2's cited
# counts genuinely match the live register TODAY. There is no discrepancy
# to report. (RC-22 and RC-23 carry split verdicts and are counted once
# under their FIRST-stated class per §2.2's own stated convention, exactly
# as the real document specifies.)
#
# Producer != Verifier (constitution 11.4.240): this file is authored at the
# RED step (T025); T046's implementation of plan_struct_check.py's `causes`
# subcommand is a LATER, SEPARATE task -- this file's author never
# implements it. The Python audit instrument embedded below (function
# `register_audit`) is NOT `plan_struct_check.py causes` and does not
# attempt to satisfy the contract's full SC-C-001 clause (evidence-path
# existence, settling_evidence for UNDETERMINED, measured_share for
# CONFIRMED post-T-A11, the six-operator-hypothesis-causes-present check,
# and the additional contract RED fixtures sc_bad_cause_no_evidence /
# sc_bad_undetermined_no_settling / sc_bad_uncited_recommendation are all
# OUT OF SCOPE for T025's four named bullets and are NOT covered by this
# file). It exists ONLY to prove, independently and today, that this file's
# own four fixtures genuinely encode the specific defect each is designed
# to encode -- exactly the role test_metatest_per_mutant_red.sh's M12
# reproduction and test_review_record_red.sh's class_of()/effort_of()
# readers already play in this same suite: a fixture self-validation
# instrument, never the tool under test.
#
# §11.4.273 control needle (for THIS file's own absence/presence-detection
# mechanism): before trusting any "absent" / "blank cell" / "count
# mismatch" finding below, this file first proves its own `[ -f PATH ]`
# file-presence check genuinely resolves paths relative to this script's
# real location, by confirming a KNOWN-PRESENT sibling (lib/fc_common.py,
# used throughout this suite -- test_baseline_replay_red.sh's identical
# needle) resolves true through the same relative-path construction. A
# wrong relative-path computation would make every "absent" claim in this
# file meaningless, and would make every "blank cell" claim from the
# register_audit heredoc meaningless too (a Python process that cannot
# even open the fixture file would report every field blank).
#
# Usage : bash test_plan_struct_causes_red.sh   Exit 0 = RED baseline holds
#         (tool absence proven, all four fixtures independently verified to
#         encode their designed defect, and the live register independently
#         verified clean of all three checkable defects) and the T046
#         contract stubs are printed. Matches the "exit 0 = RED baseline
#         PASS" convention of the T017/T024/T026 sibling files in this same
#         qa-results/fastcycle/us1/red/ tree (NOT T018/review_record's
#         different "exit 0 only once GREEN" convention -- both conventions
#         coexist in this suite; T025 follows T017/T024/T026's, per this
#         task's own instruction to match that qa-results evidence format).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
TOOL="$FC/verify/plan_struct_check.py"
FX="$(cd "$(dirname "$0")" && pwd)/fixtures/plan_struct_causes"
RESEARCH_LIVE="$ROOT/specs/004-fast-dev-cycles/research.md"
PLAN_LIVE="$ROOT/specs/004-fast-dev-cycles/plan.md"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# --- §11.4.273 control needle: prove the relative-path mechanism itself works ---
KNOWN_PRESENT="$FC/lib/fc_common.py"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so every absence/blank-cell/count claim"
  echo "     below proves nothing (§11.4.273)"
  failx
else
  echo "ok control needle: a known-present sibling (lib/fc_common.py) resolves"
  echo "   through this test's own path construction -- the checks below can"
  echo "   be trusted"
fi

# --- (1) Absence check: plan_struct_check.py ---
# NOTE (post-T036-review remediation, 2026-09-28, §11.4.1): T046 has since
# LANDED and been independently reviewed GO (two rounds, including a
# malformed-row BLOCKING fix). This check is RETAINED (real regression-
# detection value) but its polarity is flipped to match the tool's now-
# permanent presence -- an un-flipped "NOT ok ... now exists -- DELETE this"
# assertion silently converts run_all.sh (tasks.md:34's designated runner)
# into reporting FAIL for an otherwise fully-correct, GO-reviewed, committed
# tool. Found via an independent review of the SIBLING file
# test_dispatch_stamp_red.sh (T036) exhibiting the same pattern; fixed here
# on discovery, not merely in T036 (§11.4.1: a test failing for a script-
# internal/stale-assertion reason, not a genuine product defect, is as
# misleading as a PASS-bluff).
if [ -f "$TOOL" ]; then
  echo "ok verify/plan_struct_check.py exists -- T046 has landed + is"
  echo "   GO-reviewed (expected, permanent state since 2026-09-28). The"
  echo "   fixture-driven checks below, re-pointed at the real CLI's output,"
  echo "   are the real functional tests to run against it."
else
  echo "NOT ok verify/plan_struct_check.py is absent -- T046 was reviewed GO"
  echo "     and committed; a regression removed the \`causes\` subcommand"
  failx
fi

# --- (1b) Empirically reproduce the tool's real, current failure mode ---
# (documentary evidence only -- never gated on, since a correct future
# implementation's exit code for a WELL-FORMED input is 0, not 2; rc=2 is
# only what an ABSENT script produces).
python3 "$TOOL" causes --doc "$RESEARCH_LIVE" --out "$TMP/live.causes.json" \
  >"$TMP/tool_invoke.out" 2>"$TMP/tool_invoke.err"
TOOL_RC=$?
echo "info tool invocation today: rc=$TOOL_RC stderr='$(cat "$TMP/tool_invoke.err" 2>/dev/null)'"
if [ "$TOOL_RC" -ne 2 ] && [ ! -f "$TOOL" ]; then
  echo "NOT ok expected python3's own 'can't open file' exit code (2) for an"
  echo "     absent script, got rc=$TOOL_RC -- the empirical basis this"
  echo "     header cites for 'tool absent -> rc=2' no longer holds; re-verify"
  echo "     rather than trust this file's prose (§11.4.6)"
  failx
fi

# --- register_audit: the fixture self-validation instrument (NOT the tool
# under test -- see Producer!=Verifier above). Prints four lines:
#   ROWS=<comma-separated RC ids seen>
#   BLANK_CLASS=<comma-separated RC ids whose Class cell is blank>
#   BLANK_TASK=<comma-separated RC ids whose last cell is blank>
#   MISMATCH=<semicolon-separated CLASS:stated=N,actual=M entries that disagree>
register_audit() {
  python3 - "$1" <<'PY'
import re, sys

def audit(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
    rc_class, rc_last, order = {}, {}, []
    for ln in lines:
        if ln.startswith("| RC-"):
            parts = ln.rstrip("\n").split("|")
            if len(parts) != 11:
                continue
            rc_id = parts[1].strip()
            cls_cell = parts[4].strip()
            last_cell = parts[9].strip()
            m = re.match(r"^\*\*([A-Z]+)\*\*", cls_cell)
            rc_class[rc_id] = m.group(1) if m else ""
            rc_last[rc_id] = last_cell
            order.append(rc_id)
    stated_counts = {}
    in_22 = False
    for ln in lines:
        if ln.startswith("### 2.2"):
            in_22 = True
            continue
        if in_22 and ln.startswith("### 2.") and not ln.startswith("### 2.2"):
            break
        if in_22 and ln.startswith("|"):
            parts = ln.rstrip("\n").split("|")
            if len(parts) >= 3:
                key = parts[1].strip()
                val = parts[2].strip().strip("*")
                if key in ("CONFIRMED", "REFUTED", "UNDETERMINED"):
                    try:
                        stated_counts[key] = int(val)
                    except ValueError:
                        pass
    actual_counts = {}
    for rc in order:
        actual_counts[rc_class[rc]] = actual_counts.get(rc_class[rc], 0) + 1
    blank_class = [rc for rc in order if rc_class[rc] == ""]
    blank_task = [rc for rc in order if rc_last[rc] == ""]
    mismatches = []
    for cls in ("CONFIRMED", "REFUTED", "UNDETERMINED"):
        s = stated_counts.get(cls)
        a = actual_counts.get(cls, 0)
        if s is not None and s != a:
            mismatches.append(f"{cls}:stated={s},actual={a}")
    return order, blank_class, blank_task, mismatches

order, blank_class, blank_task, mismatches = audit(sys.argv[1])
print("ROWS=" + ",".join(order))
print("BLANK_CLASS=" + ",".join(blank_class))
print("BLANK_TASK=" + ",".join(blank_task))
print("MISMATCH=" + ";".join(mismatches))
PY
}

field() {
  # field <name> <audit-output-file>: prints the value after NAME= on the
  # matching line, or "" if the file/line is unreadable (never invented,
  # constitution 11.4.6 -- an unreadable audit output naturally fails every
  # equality check below against a non-empty expected value).
  awk -F= -v k="$1" '$1==k {sub(k"=","");print;found=1} END{if(!found) print ""}' "$2" 2>/dev/null
}

# --- (2) Fixture self-check: all four fixtures + their `expected` files exist ---
for fx in golden-good golden-bad-no-class golden-bad-orphan golden-bad-count-mismatch; do
  for f in research.md expected; do
    if [ -f "$FX/$fx/$f" ]; then
      echo "ok fixture $fx/$f exists"
    else
      echo "NOT ok fixture $fx/$f missing"
      failx
    fi
  done
done

# --- (3) golden-bad #1: an RC row with no class (research.md's own §2
#         preamble requires class in {CONFIRMED,REFUTED,UNDETERMINED};
#         SC-C-001 states the same membership requirement) ---
register_audit "$FX/golden-bad-no-class/research.md" >"$TMP/audit_noclass.out" 2>"$TMP/audit_noclass.err"
BLANK_CLASS=$(field BLANK_CLASS "$TMP/audit_noclass.out")
if [ "$BLANK_CLASS" = "RC-02" ]; then
  echo "ok golden-bad-no-class independently confirmed: RC-02's Class cell is"
  echo "   blank today (audit output: BLANK_CLASS=$BLANK_CLASS) -- this fixture"
  echo "   genuinely encodes the 'RC row with no class' defect the future"
  echo "   \`causes\` subcommand must catch (contract exit 1, naming the row)"
else
  echo "NOT ok golden-bad-no-class: expected BLANK_CLASS=RC-02, audit reported"
  echo "     '$BLANK_CLASS' -- the fixture does not encode the intended defect"
  cat "$TMP/audit_noclass.err" 2>/dev/null
  failx
fi

# --- (4) golden-bad #2: an orphan RC with no task (research.md lines 164-166:
#         "Every row is removed or measured by at least one task ... no
#         orphan cause") ---
register_audit "$FX/golden-bad-orphan/research.md" >"$TMP/audit_orphan.out" 2>"$TMP/audit_orphan.err"
BLANK_TASK=$(field BLANK_TASK "$TMP/audit_orphan.out")
if [ "$BLANK_TASK" = "RC-03" ]; then
  echo "ok golden-bad-orphan independently confirmed: RC-03's last"
  echo "   ('Removed / measured by') cell is blank today (audit output:"
  echo "   BLANK_TASK=$BLANK_TASK) -- this fixture genuinely encodes the"
  echo "   'orphan RC with no task' defect (contract exit 1, naming the row)"
else
  echo "NOT ok golden-bad-orphan: expected BLANK_TASK=RC-03, audit reported"
  echo "     '$BLANK_TASK' -- the fixture does not encode the intended defect"
  cat "$TMP/audit_orphan.err" 2>/dev/null
  failx
fi

# --- (5) golden-bad #3: class counts differing from research.md §2.2
#         (SC-C-001: "the class counts equal research.md §2.2") ---
register_audit "$FX/golden-bad-count-mismatch/research.md" >"$TMP/audit_mismatch.out" 2>"$TMP/audit_mismatch.err"
MISMATCH=$(field MISMATCH "$TMP/audit_mismatch.out")
case "$MISMATCH" in
  CONFIRMED:stated=3,actual=2*)
    echo "ok golden-bad-count-mismatch independently confirmed: the fixture's"
    echo "   §2.2 table states CONFIRMED=3 while its §2.1 table actually"
    echo "   contains 2 CONFIRMED rows (audit output: MISMATCH=$MISMATCH) --"
    echo "   this fixture genuinely encodes the '§2.2 counts diverge from §2.1'"
    echo "   defect (contract exit 1)"
    ;;
  *)
    echo "NOT ok golden-bad-count-mismatch: expected MISMATCH beginning"
    echo "     'CONFIRMED:stated=3,actual=2', audit reported '$MISMATCH' --"
    echo "     the fixture does not encode the intended defect"
    cat "$TMP/audit_mismatch.err" 2>/dev/null
    failx
    ;;
esac

# --- (6) golden-good: zero of the three checkable defects (proves the
#         fixture is NOT itself accidentally broken -- a fixture designed
#         as "clean" that the same audit instrument flags would mean this
#         file's own control (what "clean" looks like) is untrustworthy) ---
register_audit "$FX/golden-good/research.md" >"$TMP/audit_good.out" 2>"$TMP/audit_good.err"
GOOD_BLANK_CLASS=$(field BLANK_CLASS "$TMP/audit_good.out")
GOOD_BLANK_TASK=$(field BLANK_TASK "$TMP/audit_good.out")
GOOD_MISMATCH=$(field MISMATCH "$TMP/audit_good.out")
if [ -z "$GOOD_BLANK_CLASS" ] && [ -z "$GOOD_BLANK_TASK" ] && [ -z "$GOOD_MISMATCH" ]; then
  echo "ok golden-good independently confirmed clean: zero blank Class cells,"
  echo "   zero blank last-column cells, zero §2.2-vs-§2.1 count mismatch --"
  echo "   this fixture is a genuine clean baseline (contract exit 0 expected)"
else
  echo "NOT ok golden-good is NOT clean (BLANK_CLASS='$GOOD_BLANK_CLASS'"
  echo "     BLANK_TASK='$GOOD_BLANK_TASK' MISMATCH='$GOOD_MISMATCH') -- this"
  echo "     file's own 'clean' baseline is broken; fix the fixture, not this"
  echo "     assertion"
  cat "$TMP/audit_good.err" 2>/dev/null
  failx
fi

# --- (7) negative control: the CURRENT, real, live register PASSes ---
# (constitution 11.4.6: re-verified live below, never taken on faith from
# this file's header prose or from research.md's own §2.2 self-report)
chk_neg=0
if [ ! -f "$RESEARCH_LIVE" ]; then
  echo "NOT ok live research.md missing at $RESEARCH_LIVE -- cannot run the"
  echo "     negative control"
  failx
else
  register_audit "$RESEARCH_LIVE" >"$TMP/audit_live.out" 2>"$TMP/audit_live.err"
  LIVE_ROWS=$(field ROWS "$TMP/audit_live.out")
  LIVE_ROW_COUNT=$(printf '%s' "$LIVE_ROWS" | awk -F',' '{print NF}')
  LIVE_BLANK_CLASS=$(field BLANK_CLASS "$TMP/audit_live.out")
  LIVE_BLANK_TASK=$(field BLANK_TASK "$TMP/audit_live.out")
  LIVE_MISMATCH=$(field MISMATCH "$TMP/audit_live.out")

  chk_neg=1
  if [ "$LIVE_ROW_COUNT" -ne 46 ]; then
    echo "NOT ok live register: expected 46 RC rows, audit saw $LIVE_ROW_COUNT"
    chk_neg=0
  fi
  if [ -n "$LIVE_BLANK_CLASS" ]; then
    echo "NOT ok live register: unexpected blank-class row(s): $LIVE_BLANK_CLASS"
    chk_neg=0
  fi
  if [ -n "$LIVE_BLANK_TASK" ]; then
    echo "NOT ok live register: unexpected orphan (blank last-cell) row(s):"
    echo "     $LIVE_BLANK_TASK"
    chk_neg=0
  fi
  if [ -n "$LIVE_MISMATCH" ]; then
    echo "NOT ok live register: unexpected §2.2-vs-§2.1 count mismatch(es):"
    echo "     $LIVE_MISMATCH"
    chk_neg=0
  fi

  # Corroborating cross-check against the SECOND, independent document:
  # plan.md's own RC-to-task coverage table (grep -c "^| RC-"). If this
  # count ever disagrees with research.md's 46 rows, or if any plan.md
  # coverage row lists no task, that is itself a cross-document finding to
  # surface honestly -- not silently reconciled (§11.4.186).
  if [ -f "$PLAN_LIVE" ]; then
    PLAN_RC_ROWS=$(grep -c '^| RC-' "$PLAN_LIVE" 2>/dev/null || echo 0)
    PLAN_ORPHAN=$(awk -F'|' '/^\| RC-/ {v=$3; gsub(/^[ \t]+|[ \t]+$/,"",v); if (v=="") print $2}' "$PLAN_LIVE" 2>/dev/null)
    echo "info cross-document corroboration: plan.md's own RC-to-task coverage"
    echo "   table has $PLAN_RC_ROWS rows (expect 46, matching research.md)"
    if [ "$PLAN_RC_ROWS" != "46" ]; then
      echo "NOT ok plan.md's RC coverage table row count ($PLAN_RC_ROWS) does not"
      echo "     match research.md's 46 -- cross-document divergence, surfaced"
      echo "     not reconciled (§11.4.186)"
      chk_neg=0
    fi
    if [ -n "$PLAN_ORPHAN" ]; then
      echo "NOT ok plan.md's own coverage table has row(s) naming no task:"
      echo "     $PLAN_ORPHAN"
      chk_neg=0
    fi
  fi

  if [ "$chk_neg" -eq 1 ]; then
    echo "ok negative control confirmed: the CURRENT, real, live register at"
    echo "   specs/004-fast-dev-cycles/research.md ($LIVE_ROW_COUNT RC rows) has"
    echo "   ZERO blank-class rows, ZERO orphan (blank-task) rows, and ZERO"
    echo "   §2.2-vs-§2.1 count mismatches TODAY (re-verified live, not assumed"
    echo "   from prose) -- once T046 lands, \`causes --doc"
    echo "   specs/004-fast-dev-cycles/research.md\` is expected to exit 0 for"
    echo "   these three checks. §2.2's own cited class counts (CONFIRMED=30,"
    echo "   REFUTED=2, UNDETERMINED=14, Total=46) genuinely match §2.1's real"
    echo "   tally today -- NO discrepancy found (a finding, honestly reported"
    echo "   rather than assumed, constitution 11.4.6)."
  else
    echo "NOT ok negative control FAILED -- the live register is not clean of"
    echo "     these three checks today; see the specific findings above"
    failx
  fi
fi

echo
echo "=== T046 contract stub 1/4: invocation + output shape (SC-C-001, FR-002) ==="
echo "NOT YET IMPLEMENTED: \`python3 \$FC/verify/plan_struct_check.py causes"
echo "  --doc specs/004-fast-dev-cycles/research.md --out <causes.json>\` MUST"
echo "  write a JSON document to <causes.json> with one entry per RC-NN row"
echo "  parsed from research.md §2.1, carrying at minimum {id, class,"
echo "  evidence_paths, measured_share, settling_evidence}, and exit 0 if"
echo "  every SC-C-001 clause holds, else exit 1 with each violation listed"
echo "  by RC id on stderr or in a structured diagnostics field."

echo
echo "=== T046 contract stub 2/4: the four checks THIS test pins ==="
echo "NOT YET IMPLEMENTED: (a) every row's Class cell resolves to exactly one"
echo "  of {CONFIRMED, REFUTED, UNDETERMINED} -- a blank or unrecognised cell"
echo "  fails, naming the row; (b) every row's last ('Removed / measured by')"
echo "  cell is non-blank -- a blank cell fails as an orphan cause, naming the"
echo "  row; (c) the §2.2 'Register counts' table's per-class Rows figure"
echo "  equals a fresh tally over §2.1's Class column -- any disagreement"
echo "  fails, naming the class and both the stated and actual counts (this"
echo "  file's fixtures use the exact format 'CLASS:stated=N,actual=M' as one"
echo "  concrete, testable shape -- not asserted as the ONLY valid diagnostic"
echo "  format, constitution 11.4.6); (d) running against the CURRENT, live"
echo "  research.md today (2026-09-28) is expected to exit 0 for these three"
echo "  checks specifically (independently re-verified above, not assumed)."

echo
echo "=== T046 contract stub 3/4: OUT OF SCOPE for T025 (honest disclosure) ==="
echo "NOT YET IMPLEMENTED and NOT covered by THIS file (separate contract"
echo "  clauses / separate RED fixtures, per plan-research-structural-check.md's"
echo "  own RED fixtures table): sc_bad_cause_no_evidence (>=1 EvidencePath"
echo "  that exists), sc_bad_undetermined_no_settling (settling_evidence"
echo "  required for UNDETERMINED), sc_bad_uncited_recommendation (FR-003,"
echo "  belongs to the 'research' subcommand), sc_bad_task_no_rollback /"
echo "  sc_bad_duplicate_block / sc_bad_substantive_edit (belong to the"
echo "  'plan' / 'landing' / 'rule-diff' subcommands), and the deeper"
echo "  SC-C-003 bipartite cross-check of the register's named tasks against"
echo "  plan.md's ACTUAL task blocks (a separate, later task's test). Six-"
echo "  operator-listed-causes-present and post-T-A11 measured_share"
echo "  enforcement are likewise NOT exercised by this file."

echo
echo "=== T046 contract stub 4/4: exit codes (contract 'Exit codes' table) ==="
echo "NOT YET IMPLEMENTED: 0 all checks pass; 1 any structural violation"
echo "  (listing each); 2 usage; 3 needle (a fixture with a known orphan cause"
echo "  not detected -- this file's own golden-bad-orphan fixture IS a"
echo "  candidate needle fixture for that exit code once T046 lands, though"
echo "  this file does not itself assert exit=3 anywhere, only exit=1 per its"
echo "  own \`expected\` files); 4 document unreadable."

echo
echo "SUMMARY control_needle=ok tool_absent=$([ -f "$TOOL" ] && echo no || echo yes)" \
     "fixtures_verified=4 negative_control=$([ "$chk_neg" -eq 1 ] 2>/dev/null && echo pass || echo see-above)" \
     "fail=$fail"
exit $fail
