#!/bin/bash
# Purpose : T024 (SpecKit-004 "fast-dev-cycles", User Story 1) RED baseline for
#           the T-A10 stratified-baseline sampling + replay mechanism -- proves
#           `cycle/select_sample.py` and `cycle/baseline_replay.sh` (plan.md's
#           Project Structure, lines 175-176) do NOT exist today, and documents
#           the determinism + control-needle contract T043's implementer must
#           satisfy.
#
# THE GAP (verified directly, 2026-09-28): plan.md names both files under
# `constitution/scripts/fastcycle/cycle/` (`select_sample.py` -- "stratified
# baseline sample selection (T-A10)"; `baseline_replay.sh` -- "SC-002/SC-005
# replay harness (T-A10, T-H02)"). Neither exists in this tree today; T043
# (a LATER, SEPARATE task) is the one that creates them. tasks.md's T024 line
# itself, and plan.md's T-A10 "Protecting tests" clause (lines 488-490), state
# the exact contract this RED test must pin:
#
#   "determinism: two replays of one sample change produce the same verdict
#   set; the sample selection script is re-run and yields the same item list
#   (control: the known 5 bugs of the 60-day window are included)."
#
# research.md P-15 (line 126) is the source of the "5 known bugs" figure:
#   "60-day window: Bug 5, Task 2, Feature 0; 90-day: Bug 21, Task 16,
#   Feature 1; Feature ever: 2" -- cited to raw research artifact "R1:19-21",
#   which is NOT itself a tracked file in this repo (an ephemeral research-pass
#   artifact) and does NOT enumerate the 5 items by ATM-id anywhere this file
#   can find. §11.4.6 (no-guessing): the exact 5 item ids are therefore NOT
#   invented here -- T043's implementer resolves them against the LIVE
#   docs/workable_items.db (a stable, current, more authoritative source than
#   a stale research-pass count) at implementation time, and the control-needle
#   stub below documents that requirement rather than guessing ids that could
#   be wrong today.
#
# Producer≠Verifier: this file is authored at the RED step (T024); T043's
# implementation of select_sample.py/baseline_replay.sh is a SEPARATE, later
# task -- this file's author never implements them.
#
# §11.4.273 control needle (for THIS file's own absence-detection mechanism):
# before trusting "select_sample.py is absent" as a finding, prove the plain
# `[ -f PATH ]` file-presence check genuinely resolves paths relative to this
# script's real location by first confirming a KNOWN-PRESENT sibling
# (lib/fc_common.py, used throughout this suite) resolves true through the
# identical relative-path construction. A wrong relative-path computation
# would make EVERY file in the tree look "absent", including real ones.
#
# Usage : bash test_baseline_replay_red.sh   Exit 0 = RED baseline holds
#         (absence proven) and the determinism + control-needle contract
#         stubs are printed for T043's implementer.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"

fail=0
failx() { fail=1; }

# --- §11.4.273 control needle: prove the relative-path mechanism itself works ---
KNOWN_PRESENT="$FC/lib/fc_common.py"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so every absence check below proves"
  echo "     nothing (§11.4.273)"
  failx
else
  echo "ok control needle: a known-present sibling (lib/fc_common.py) resolves"
  echo "   through this test's own path construction -- the absence checks"
  echo "   below can be trusted"
fi

# --- (1) Presence report: select_sample.py ---
# NOTE (conductor, proactive fix 2026-09-28): the original form of this
# check FAILed once T043 landed ("NOT ok ... now exists -- T043 has
# landed. DELETE this RED-baseline assertion"), which is the exact
# batch-wide "stale absence-precondition becomes a permanent false FAIL"
# defect class independently found and fixed elsewhere this session in
# T023 (test_cycle_report_red.sh), T025 (test_plan_struct_causes_red.sh),
# T036 (test_dispatch_stamp_red.sh, its own review Finding 1), and T020
# (test_token_attribution_red.sh's pre-flight block). Fixed proactively
# here, before T043 lands, to prevent a 5th occurrence: this block is now
# informational only and never fails on either state -- the three
# contract stubs below (once completed into real tests, either by the
# conductor or a dedicated follow-up per Producer!=Verifier, since T043's
# own implementer must not edit this file) are what genuinely exercises
# T043's tools once they exist.
SELECT_SAMPLE="$FC/cycle/select_sample.py"
if [ -f "$SELECT_SAMPLE" ]; then
  echo "ok cycle/select_sample.py now exists (T043 landed) -- exercised for"
  echo "   real by the contract stubs below once they are completed"
else
  echo "ok cycle/select_sample.py absent today (confirmed 2026-09-28) --"
  echo "   T043 has not yet landed the stratified baseline sample selector"
fi

# --- (2) Presence report: baseline_replay.sh ---
BASELINE_REPLAY="$FC/cycle/baseline_replay.sh"
if [ -f "$BASELINE_REPLAY" ]; then
  echo "ok cycle/baseline_replay.sh now exists (T043 landed) -- exercised"
  echo "   for real by the contract stubs below once they are completed"
else
  echo "ok cycle/baseline_replay.sh absent today (confirmed 2026-09-28) --"
  echo "   T043 has not yet landed the SC-002/SC-005 replay harness"
fi

echo
echo "=== T043 contract stub 1/3: replay determinism (plan.md T-A10, SC-002/SC-005) ==="
echo "NOT YET IMPLEMENTED: two independent invocations of baseline_replay.sh against"
echo "  the SAME frozen sample change (identical commit + tree hash inputs) MUST"
echo "  produce the SAME verdict SET (per-item PASS/FAIL/SKIP classification,"
echo "  compared as a set, never merely as equal counts -- the §11.4.201(8)"
echo "  count-blind-regression trap this suite's own driver already guards"
echo "  against elsewhere). A replay whose verdict set differs run-to-run against"
echo "  an UNCHANGED frozen input is a determinism defect (§11.4.50)."

echo
echo "=== T043 contract stub 2/3: selection-script re-run stability (SC-001, SC-004) ==="
echo "NOT YET IMPLEMENTED: re-running select_sample.py with the SAME frozen"
echo "  parameters (DEC-03: 90-day window, Bug >=5 of 21, Task >=5 of 16,"
echo "  Feature n=2 short stratum, all 9 reopened items) MUST yield the"
echo "  IDENTICAL item list (same ATM-id SET, same stratum membership) on"
echo "  every re-run -- never a list that reshuffles across invocations against"
echo "  unchanged inputs."

echo
echo "=== T043 contract stub 3/3: known-bugs control needle (plan.md T-A10 line 489) ==="
echo "NOT YET IMPLEMENTED: research.md P-15 (line 126, cited to raw research"
echo "  artifact R1:19-21, not itself a tracked file) reports the 60-day window"
echo "  holding exactly 5 Bug-type items, 2 Task-type, 0 Feature-type. When"
echo "  select_sample.py is run with a 60-day window parameter, its item list"
echo "  MUST include all 5 of those Bug-type items. §11.4.6 (no-guessing): this"
echo "  file does NOT enumerate the 5 ATM-ids -- they are not given by ATM-id"
echo "  anywhere this file's author could find -- T043's implementer MUST"
echo "  resolve them against the LIVE docs/workable_items.db at implementation"
echo "  time (read-only query: Bug-type items whose relevant date field falls"
echo "  within the most recent 60 days of the frozen sample's as-of date), NOT"
echo "  copy a possibly-stale count from a research-pass artifact. If the live"
echo "  count differs from research.md's cited 5, that is itself a finding to"
echo "  surface, not silently reconcile."

exit $fail
