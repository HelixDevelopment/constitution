#!/bin/bash
# Purpose : T036 (SpecKit-004 "fast-dev-cycles", User Story 1) RED baseline
#           for `constitution/scripts/fastcycle/tokens/dispatch_stamp.sh` --
#           proves the tool is absent today, and documents the contract its
#           implementer must satisfy.
#
# THE GAP -- CORRECTED 2026-09-28 (§11.4.1/§11.4.6 remediation, found by an
# independent Opus-xhigh review of the implementation this file guards): the
# claim originally here -- "NONE of T015-T026 reference dispatch_stamp.sh"
# -- was FALSE and has been disproven by direct grep. T020's own RED test,
# `constitution/scripts/fastcycle/tests/test_token_attribution_red.sh`
# (part of the SAME T015-T026 batch, landed BEFORE this file was authored),
# explicitly guards dispatch_stamp.sh: its header states "Guards two
# NOT-YET-BUILT tools (T036/T037's `$FC/tokens/dispatch_stamp.sh` and
# T038's ...)", it sets `DISPATCH_STAMP="$FC/tokens/dispatch_stamp.sh"`,
# and its entire "PART A" section is dedicated to this exact tool's
# `item=<ATM-nnnn>` enforcement gap -- including a
# captured, real dispatch example proving no current dispatch carries the
# tag. tasks.md:102 (T020) also literally names `item=<ATM-nnnn>`. The
# ORIGINAL author's own control-needle discipline (§11.4.273) verified two
# NARROWER claims (about the sibling guard hooks and the registry writer)
# but never verified the actual, broader "T015-T026 corpus" claim this
# header asserted -- a genuine investigation gap, corrected here rather
# than left standing (a disprovable "verified directly" claim shipped in a
# file's own header is PASS-bluff-severity per this project's standard,
# regardless of whether the file's operative CONCLUSIONS below -- absence
# proof, control needles, the derived contract stubs -- remain correct,
# which they do; T020's own reproduction happens to have arrived
# independently at the SAME contract shape T036's implementer landed,
# corroborating rather than contradicting this file's stubs).
#
# What genuinely IS true (re-verified, narrower and accurate): no
# `contracts/*.md` file exists for dispatch_stamp.sh (confirmed: `ls
# specs/004-fast-dev-cycles/contracts/ | grep -i dispatch` -> empty), and
# tasks.md's own T036 line is the only tasks.md line NAMING an "until T0NN
# is GREEN" clause pointing AT a pre-existing RED test the way T038/T039/
# T041/T046 each do -- T020 guards it as a SECONDARY concern (one of its
# five parts) rather than as T036's own primary, dedicated RED gate. This
# file remains the primary, dedicated RED baseline + derived contract for
# T036 specifically; T020 is a real, independently-corroborating SIBLING
# guard, not a substitute for it, and not something this file's original
# author was entitled to claim didn't exist.
#
# THE ONE LINE OF SPEC THIS DERIVES FROM (tasks.md:120, verbatim):
#   "[P] [US1] [SUBAGENT] [REVIEW] Implement
#   constitution/scripts/fastcycle/tokens/dispatch_stamp.sh (requires
#   `item=<ATM-nnnn>` in every agent-dispatch description alongside the
#   §11.4.182 label and hands the id to the registry writer) (plan T-A06;
#   FR-013, FR-001, SC-005)"
#
# WHERE THE DESIGN BELOW COMES FROM (derived, not invented -- every clause
# traces to a real, currently-existing sibling mechanism, read in full
# before writing this file):
#   1. plan.md:182 places the file at
#      `constitution/scripts/fastcycle/tokens/dispatch_stamp.sh`.
#   2. The EXISTING sibling PreToolUse guard hooks on the SAME
#      `Agent|Task|TaskCreate` matcher (.claude/settings.json, verified
#      live) are `guard-track-branch-label.sh` (enforces the §11.4.182
#      `(T<N>/<branch> - <alias>...)` label) and `guard-work-track-
#      binding.sh` -- both share ONE contract: stdin carries the tool
#      invocation as JSON, exit 0 = allow, exit 2 = BLOCK with stderr
#      explaining the fix, every OTHER tool_name passes through untouched.
#      T036's task line says it "requires item=<ATM-nnnn> ... alongside
#      the §11.4.182 label" -- the natural reading, given it sits in the
#      SAME hook chain as its sibling per T037 ("Wire dispatch_stamp.sh
#      into ... the PreToolUse hook list in .claude/settings.json"), is
#      that dispatch_stamp.sh follows the IDENTICAL stdin-JSON /
#      exit-0-allow / exit-2-block contract as its two siblings, not a
#      new one.
#   3. `agent_registry_writer.sh` (verified live, read in full) currently
#      has NO `item` field anywhere in its JSONL row schema
#      ({ts,event,key,tool_name,session_id,description,note}) -- this
#      independently confirms "hands the id to the registry writer" is a
#      FUTURE wiring step (T037, SERIAL, conductor-only, NOT this task),
#      and that T036's OWN scope is producing the id in a form T037 can
#      consume, not writing the registry row itself.
#   4. `guard-track-branch-label.sh`'s LABEL_RE
#      (`^\(T([0-9]+|\?)/[^)]+ - [^)]+( - [^)]+){0,2}\) `) matches the
#      label PREFIX only, leaving the remainder of the description free --
#      T036's `item=<ATM-nnnn>` token therefore has a real, uncontended
#      place to live: immediately after the label, before the free-text
#      task description (exactly how every dispatch this session has
#      already been written, e.g. "(T1/main - claude5 - sonnet - high)
#      T039 fix pass anchor_citations" -- MISSING an item= token today,
#      confirming the gap is real and current, not hypothetical).
#
# §11.4.273 control needle: before trusting "no current dispatch enforces
# item=<ATM-nnnn>" as a finding, this file independently confirms the
# CLAIM (not merely asserts it) by reading guard-track-branch-label.sh's
# own LABEL_RE and confirming it contains no `item=` token anywhere, AND
# by confirming agent_registry_writer.sh's JSONL schema (grepped from its
# real source, not assumed) has no `item` key today -- both checked below,
# live, never assumed.
#
# Producer != Verifier (constitution 11.4.240): this file is authored at
# the RED step (T036); dispatch_stamp.sh's implementation is a SEPARATE,
# later task -- this file's author never implements it.
#
# Usage : bash test_dispatch_stamp_red.sh   Exit 0 = RED baseline holds
#         (absence proven + control needles confirmed) and the derived
#         contract stubs are printed for T036's implementer.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
SIBLING_GUARD="$ROOT/constitution/scripts/hooks/guard-track-branch-label.sh"
REGISTRY_WRITER="$ROOT/scripts/hooks/agent_registry_writer.sh"

fail=0
failx() { fail=1; }

# --- §11.4.273 control needle 1: the sibling label guard's regex genuinely ---
#     has NO item= awareness today (independently re-derived, not assumed).
if [ ! -f "$SIBLING_GUARD" ]; then
  echo "NOT ok sibling guard-track-branch-label.sh missing at $SIBLING_GUARD --"
  echo "     the control needle below cannot be trusted without it"
  failx
else
  if grep -q 'item=' "$SIBLING_GUARD"; then
    echo "NOT ok guard-track-branch-label.sh already references 'item=' --"
    echo "     T036 may have partially landed inside the sibling hook; re-check"
    echo "     whether this RED baseline still holds before trusting it"
    failx
  else
    echo "ok control needle 1: the live §11.4.182 label guard's own LABEL_RE"
    echo "   and full source contain ZERO 'item=' awareness today (confirmed"
    echo "   2026-09-28 via direct grep of the real, current file) -- no"
    echo "   dispatch this session is currently required to carry an item id"
  fi
fi

# --- §11.4.273 control needle 2: agent_registry_writer.sh's real JSONL row ---
#     schema genuinely has no `item` field today.
if [ ! -f "$REGISTRY_WRITER" ]; then
  echo "NOT ok agent_registry_writer.sh missing at $REGISTRY_WRITER"
  failx
else
  if grep -qE '"item"' "$REGISTRY_WRITER"; then
    echo "NOT ok agent_registry_writer.sh already writes an \"item\" JSONL key --"
    echo "     T037's wiring may have partially landed; re-check this baseline"
    failx
  else
    echo "ok control needle 2: agent_registry_writer.sh's real JSONL row schema"
    echo "   ({ts,event,key,tool_name,session_id,description,note}, confirmed"
    echo "   via direct grep of the real, current file) has NO 'item' key"
    echo "   today -- confirms T037 (the wiring step) has not landed either,"
    echo "   consistent with T036 (its prerequisite) being absent"
  fi
fi

# --- Absence check: dispatch_stamp.sh ---
# NOTE (2026-09-28, §11.4.1 remediation, found by round-1 Opus-xhigh review
# of the implementation this file guards): a "NOT ok ... now exists --
# DELETE this" assertion left un-flipped once its guarded tool lands
# silently converts run_all.sh (tasks.md:34's designated test runner) into
# reporting FAIL for an otherwise-correct, committed tool -- misleading
# exactly like a §11.4.1 PASS-bluff, just inverted (a FAIL-bluff). The
# SAME defect class was found + fixed in this same remediation round across
# sibling RED tests test_cycle_report_red.sh (T023/T041) and
# test_plan_struct_causes_red.sh (T025/T046) -- this file's own check is
# fixed identically here, retaining real regression-detection value (a
# future accidental deletion of dispatch_stamp.sh is still caught) while no
# longer permanently misreporting a working, landed tool as failing.
DISPATCH_STAMP="$FC/tokens/dispatch_stamp.sh"
if [ -f "$DISPATCH_STAMP" ]; then
  echo "ok tokens/dispatch_stamp.sh exists -- T036 has landed (expected,"
  echo "   permanent state since 2026-09-28). The fixture-driven checks"
  echo "   under tests/fixtures/dispatch_stamp/ are the real functional"
  echo "   tests to run against it (README.md documents both GUARD-mode"
  echo "   and EXTRACTION-mode invocation)."
else
  echo "NOT ok tokens/dispatch_stamp.sh is absent -- T036 landed on this"
  echo "     checkout as of 2026-09-28; a regression removed the item-id"
  echo "     dispatch-stamping mechanism"
  failx
fi

echo
echo "=== T036 contract stub 1/5: PreToolUse guard contract (derived from the ==="
echo "===   sibling guard-track-branch-label.sh / guard-work-track-binding.sh ==="
echo "===   hooks on the SAME Agent|Task|TaskCreate matcher, .claude/           ==="
echo "===   settings.json, verified live 2026-09-28)                            ==="
echo "NOT YET IMPLEMENTED: dispatch_stamp.sh MUST accept the tool invocation as"
echo "  JSON on stdin (identical to its two siblings), read"
echo "  .tool_input.description (falling back to .tool_input.subagent exactly"
echo "  as guard-track-branch-label.sh does), and for tool_name in"
echo "  {Agent, Task, TaskCreate} MUST require an 'item=<ATM-nnnn>' token"
echo "  (regex candidate: 'item=(ATM-[0-9]+|\\?)', the honest '?' form ALWAYS"
echo "  accepted per the §11.4.6/§11.4.182 no-fabricated-verdict precedent"
echo "  the sibling hook already establishes for alias/model/effort) present"
echo "  SOMEWHERE in that description -- exit 0 (allow) if present, exit 2"
echo "  (BLOCK, stderr explains the fix + shows a corrected example) if"
echo "  absent. EVERY OTHER tool_name MUST pass through untouched (exit 0)."

echo
echo "=== T036 contract stub 2/5: placement relative to the §11.4.182 label ==="
echo "NOT YET IMPLEMENTED: per tasks.md's own wording ('alongside the §11.4.182"
echo "  label'), the natural placement is immediately AFTER the label prefix"
echo "  guard-track-branch-label.sh already validates, e.g.:"
echo "    (T1/main - claude5 - sonnet - high) item=ATM-1041 T036 implement ..."
echo "  T036's implementer decides the EXACT required position (immediately-"
echo "  after-label vs anywhere-in-description) and states it explicitly in"
echo "  the tool's own docstring -- this file does not prescribe one over the"
echo "  other, since tasks.md's one line does not settle it (§11.4.6: an"
echo "  underspecified placement is an honest ambiguity, not a guessed answer)."

echo
echo "=== T036 contract stub 3/5: extraction mode -- 'hands the id to the ==="
echo "===   registry writer' (T037's prerequisite, this task's real deliverable) ==="
echo "NOT YET IMPLEMENTED: since agent_registry_writer.sh has NO 'item' field"
echo "  today (control needle 2, above) and T037 (a SEPARATE, later, SERIAL"
echo "  task) is what actually wires the id INTO that writer's JSONL row,"
echo "  T036's OWN scope must expose the extracted id in a form T037 can"
echo "  consume without re-deriving the parsing logic -- e.g. a second CLI"
echo "  mode such as 'dispatch_stamp.sh --extract-item-id' reading the SAME"
echo "  stdin JSON shape and printing ONLY the extracted 'ATM-nnnn' (or '?')"
echo "  to stdout with no other output, so T037 can call it as a one-line"
echo "  helper inside agent_registry_writer.sh's existing python3 JSON-parsing"
echo "  block. T036's implementer names the EXACT invocation T037 will use."

echo
echo "=== T036 contract stub 4/5: robustness guarantee (matches BOTH siblings) ==="
echo "NOT YET IMPLEMENTED: like guard-track-branch-label.sh (exit 2 only on a"
echo "  genuinely missing/malformed item id) and unlike"
echo "  agent_registry_writer.sh (which NEVER blocks, always exits 0 per its"
echo "  own CRITICAL ROBUSTNESS GUARANTEE comment) -- dispatch_stamp.sh in its"
echo "  GUARD mode legitimately DOES block (exit 2) on a missing item= token,"
echo "  since that is its whole purpose (matching its sibling label guard's"
echo "  same blocking behavior for a missing label). Its EXTRACTION mode"
echo "  (stub 3, above), if ever invoked from inside agent_registry_writer.sh's"
echo "  ALWAYS-exit-0 contract, must itself never exit non-zero in a way that"
echo "  could propagate into the writer's guarantee -- T037's wiring step is"
echo "  responsible for isolating that, but T036's implementer should note"
echo "  this interaction in the docstring so T037 does not have to rediscover"
echo "  it."

echo
echo "=== T036 contract stub 5/5: anti-bluff self-validation (§11.4.107(10)) ==="
echo "NOT YET IMPLEMENTED: like its two siblings, dispatch_stamp.sh needs a"
echo "  golden-good fixture (a real Agent/Task tool_input JSON with a"
echo "  well-formed item=ATM-nnnn token -> exit 0), a golden-bad fixture (the"
echo "  identical shape but item= missing entirely -> exit 2 naming the fix),"
echo "  and a negative control (a non-Agent/Task/TaskCreate tool_name, e.g."
echo "  'Bash', with NO item= anywhere -> exit 0, proving the guard does not"
echo "  over-fire on tools it was never meant to gate)."

exit $fail
