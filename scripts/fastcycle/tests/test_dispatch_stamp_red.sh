#!/bin/bash
# Purpose : T036 (SpecKit-004 "fast-dev-cycles", User Story 1) RED baseline
#           for `constitution/scripts/fastcycle/tokens/dispatch_stamp.sh`.
#           Originally proved the tool absent and printed the derived
#           contract; since T036 landed it EXECUTES that contract against
#           the real tool (see the T048 restart round-1 note below).
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
# Producer != Verifier (constitution 11.4.240): this file is authored at
# the RED step (T036); dispatch_stamp.sh's implementation is a SEPARATE,
# later task -- this file's author never implements it.
#
# T048 RESTART ROUND-1 (R3-F4, review class "tests that never run the real
# artifact"): this file used to prove the contract only by file existence
# and greps, and printed five "NOT YET IMPLEMENTED" stubs long after T036
# and T037 landed. The stubs are now executed: every contract point below
# runs the real dispatch_stamp.sh (stdin JSON, GUARD and --extract-item-id
# modes) and checks its exit code / stdout / stderr. The two greps of other
# files (the sibling label guard and agent_registry_writer.sh) were removed:
# the first checked a stale pre-T036 premise, and the writer's "item" column
# is checked by running the real writer in test_token_attribution_red.sh
# PART A.
#
# Usage : bash test_dispatch_stamp_red.sh   Exit 0 = every contract point
#         holds on the real tool; exit 1 = at least one does not.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DISPATCH_STAMP="$HERE/../tokens/dispatch_stamp.sh"
FIXDIR="$HERE/fixtures/dispatch_stamp"

# Hermetic configuration (no dependence on the checkout this runs in): the
# static fixtures use the ATM prefix, so the release prefix is pinned to a
# fixture value that derives ATM, and the two FC_* overrides are unset.
unset FC_DISPATCH_ITEM_ID_RE FC_DISPATCH_EXTRA_ITEM_PREFIXES HELIX_PROJECT_ROOT 2>/dev/null || true
export HELIX_RELEASE_PREFIX=atm_fixture_prefix

fail=0
okm()  { echo "ok $1"; }
notok() { echo "NOT ok $1"; fail=1; }

if [ ! -f "$DISPATCH_STAMP" ]; then
  notok "tokens/dispatch_stamp.sh is absent -- T036 landed 2026-09-28; a regression removed it"
  exit 1
fi
okm "tokens/dispatch_stamp.sh exists"

# guard <payload> -> exit code of GUARD mode; stderr kept in $WORK_ERR
WORK_ERR="$(mktemp)"; trap 'rm -f "$WORK_ERR"' EXIT
guard()   { printf '%s' "$1" | bash "$DISPATCH_STAMP" >/dev/null 2>"$WORK_ERR"; echo $?; }
extract() { printf '%s' "$1" | bash "$DISPATCH_STAMP" --extract-item-id 2>"$WORK_ERR"; echo "|$?"; }

echo
echo "=== contract 1/5 + 5/5: GUARD verdicts on the three static fixtures ==="
for CASE in golden-good golden-bad negative-control; do
  if [ ! -f "$FIXDIR/$CASE/input" ] || [ ! -f "$FIXDIR/$CASE/expected" ] || [ ! -f "$FIXDIR/$CASE/expected_extract" ]; then
    notok "fixture $CASE is incomplete under $FIXDIR/$CASE"
    continue
  fi
  payload="$(cat "$FIXDIR/$CASE/input")"
  want="$(cat "$FIXDIR/$CASE/expected")"
  got="$(guard "$payload")"
  if [ "$got" = "$want" ]; then okm "fixture $CASE: GUARD exit $got"; else notok "fixture $CASE: GUARD exit $got, want $want"; fi
  want_x="$(cat "$FIXDIR/$CASE/expected_extract")"
  got_x="$(extract "$payload")"
  if [ "$got_x" = "${want_x}|0" ]; then okm "fixture $CASE: --extract-item-id '${want_x}', exit 0"; else notok "fixture $CASE: --extract-item-id gave '$got_x', want '${want_x}|0'"; fi
done
needle_payload="$(cat "$FIXDIR/golden-bad/input" 2>/dev/null)"
guard "$needle_payload" >/dev/null
if grep -q "item=" "$WORK_ERR"; then okm "a BLOCK explains the fix on stderr (names item=)"; else notok "a BLOCK gave no item= explanation on stderr"; fi

echo
echo "=== contract 1/5: only Agent / Task / TaskCreate are gated ==="
for tool in Agent Task TaskCreate; do
  got="$(guard "{\"tool_name\":\"$tool\",\"tool_input\":{\"description\":\"(T1/main - x) no tag\"}}")"
  if [ "$got" = 2 ]; then okm "$tool without a tag is blocked (exit 2)"; else notok "$tool without a tag gave exit $got, want 2"; fi
done
got="$(guard '{"tool_name":"Bash","tool_input":{"command":"true"}}')"
if [ "$got" = 0 ]; then okm "Bash (not an agent dispatch) passes untouched"; else notok "Bash gave exit $got, want 0"; fi

echo
echo "=== contract 2/5: the tag may sit anywhere at a token boundary; honest item=? accepted ==="
got="$(guard '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) some text then item=ATM-77 later"}}')"
if [ "$got" = 0 ]; then okm "a tag later in the description is accepted"; else notok "a tag later in the description gave exit $got, want 0"; fi
got="$(extract '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=? unknown"}}')"
if [ "$got" = "?|0" ]; then okm "item=? is extracted as '?'"; else notok "item=? gave '$got', want '?|0'"; fi

echo
echo "=== contract 3/5 + 4/5: extraction mode prints only the id and always exits 0 ==="
for bad in '' 'null' '{"tool_name":' '42'; do
  got="$(extract "$bad")"
  if [ "$got" = "|0" ] && [ ! -s "$WORK_ERR" ]; then okm "malformed stdin '$bad' -> empty stdout, empty stderr, exit 0"; else notok "malformed stdin '$bad' gave '$got' stderr='$(head -c 120 "$WORK_ERR")', want '|0' and empty stderr"; fi
done

exit $fail
