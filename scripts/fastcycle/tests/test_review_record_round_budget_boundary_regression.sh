#!/bin/bash
# test_review_record_round_budget_boundary_regression.sh
#
# CON-033 round 2 (review I6, reviewer mutant RM1, section 11.4.276(D)): the
# LAST legal round of the review-round budget is a legal round. The gate's
# guard G-Q-ROUND-BUDGET refuses `rec["round"] > ctx["round_budget"]`; the
# reviewer's mutant `>=` (refuse the last legal round) survived every suite,
# because no case recorded a round EQUAL to the budget. The record side's
# guard G-R-ROUND-BUDGET has the same boundary and is pinned here too.
#
# Every case drives the REAL `review_record.py record` / `gate` CLI through
# lib/review_record_genuine.sh (nothing re-implements gate logic). This suite
# is not one of the suites the sub-clause kill ledger hashes, so adding it
# does not make that ledger stale.
#
#   B1  round 5 under the default budget 5: recorded, and COVERED by gate;
#   B2  round 7 under --round-budget 7: recorded, COVERED by gate with
#       --round-budget 7, UNCOVERED (naming the budget) under the default 5
#       -- the control: the boundary is the budget, not "always covered";
#   B3  round 8 under --round-budget 7: refused by record (one past the end).
#
# Exit 0 = all passed; 1 = a check failed; 2 = scratch dir unusable.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
# shellcheck disable=SC2034 # RR_TOOL is consumed by the sourced lib/review_record_genuine.sh
RR_TOOL="$FC/review/review_record.py"
# shellcheck source=lib/review_record_genuine.sh
# shellcheck disable=SC1091 # sourced helper is linted on its own
. "$HERE/lib/review_record_genuine.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+w "${S:?}" 2>/dev/null; rm -rf -- "${S:?}"' EXIT
RR_WORK="$S/work"; mkdir -p "$RR_WORK"
NONE='[]'
fresh_case() {
  CASE="$S/$1"; mkdir -p "$CASE/records"
  RR_LEDGER="$CASE/ledger.jsonl"; : > "$RR_LEDGER"
  REC="$CASE/records"
}
gate() { # gate CHANGE [extra args] -> sets G_RC, G_OUT
  G_OUT=$(python3 "$RR_TOOL" gate --change "$1" --records "$REC" --dispatch-ledger "$RR_LEDGER" "${@:2}" 2>&1)
  G_RC=$?
}
covered()   { [ "$G_RC" -eq 0 ] && printf '%s\n' "$G_OUT" | grep -q "^COVERED $1 "; }
uncovered() { [ "$G_RC" -eq 1 ] && printf '%s\n' "$G_OUT" | grep -q "^UNCOVERED $1"; }

echo "== review-round budget boundary (11.4.276) =="

fresh_case b1
rr_genuine "$REC/r5.json" B-RB1 CH-RB1 5 GO "$NONE" D-RB1
if [ "$RR_RC" -eq 0 ] && [ -f "$REC/r5.json" ]; then ok "B1a: record accepts round 5 under the default budget 5"
else bad "B1a: record rc=$RR_RC err=$(cat "$RR_WORK/r5/record.err" 2>/dev/null)"; fi
gate CH-RB1
if covered CH-RB1; then ok "B1b: gate COVERS a round-5 GO under the default budget 5 (the last legal round is legal)"
else bad "B1b: rc=$G_RC out=$G_OUT"; fi

fresh_case b2
rr_genuine "$REC/r7.json" B-RB2 CH-RB2 7 GO "$NONE" D-RB2 --round-budget 7
if [ "$RR_RC" -eq 0 ] && [ -f "$REC/r7.json" ]; then ok "B2a: record accepts round 7 under --round-budget 7"
else bad "B2a: record rc=$RR_RC err=$(cat "$RR_WORK/r7/record.err" 2>/dev/null)"; fi
gate CH-RB2 --round-budget 7
if covered CH-RB2; then ok "B2b: gate --round-budget 7 COVERS a round-7 GO"
else bad "B2b: rc=$G_RC out=$G_OUT"; fi
gate CH-RB2
if uncovered CH-RB2 && printf '%s\n' "$G_OUT" | grep -q "exceeds the review-round budget 5"; then
  ok "B2c: control -- the same round-7 GO is UNCOVERED under the default budget 5, naming the budget"
else bad "B2c: rc=$G_RC out=$G_OUT"; fi

fresh_case b3
rr_genuine "$REC/r8.json" B-RB3 CH-RB3 8 GO "$NONE" D-RB3 --round-budget 7
if [ "$RR_RC" -eq 1 ] && [ ! -f "$REC/r8.json" ] && grep -q "review-round budget 7" "$RR_WORK/r8/record.err"; then
  ok "B3: record refuses round 8 under --round-budget 7 (one past the end; nothing written)"
else bad "B3: record rc=$RR_RC"; fi

echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ]
