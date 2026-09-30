#!/bin/bash
# Purpose : T140 Round 1 (batched Opus-xhigh independent review of SpecKit-004
#           "fast-dev-cycles" User Story 5) finding I4 regression guard.
#
# I4 (verbatim from the review, recorded in docs/CONTINUATION.md ADDENDUM 78):
# "`handoff.py resume-check` fails OPEN (non-git-tree deps and a missing
# `ground_truth_effects.json` are silently skipped, reporting
# `safe_to_resume_without_reverification: true` with no skip recorded -- a
# section 11.4.201(6) false-null)."
#
# Fixed in orchestration/handoff.py's cmd_resume_check by:
#   (a) an external_deps entry whose `kind` is anything OTHER than the only
#       re-hashable kind, "git-tree", is now recorded as its own
#       "unverifiable-external-dependency" unsafe_reasons entry (with its
#       declared affects_verified ids added to facts_needing_reverification)
#       instead of being silently `continue`d past;
#   (b) a MISSING ground_truth_effects.json sibling is now recorded as its
#       own "unverifiable-ground-truth" unsafe_reasons entry WHEN the
#       record's own effects_performed is non-empty (the record claims a
#       real effect happened and this tool has no independent way to
#       confirm that claim is complete) -- an EMPTY effects_performed with
#       no sibling remains the pre-existing, correct, honest skip (section
#       11.4.3): nothing in the record claims an effect occurred, so there
#       is nothing this check could cross-verify either way.
#
# This file is a SELF-CONTAINED regression guard for that fix -- it does
# NOT import, source, or otherwise couple to test_resume_revalidate_red.sh's
# own derive_resume_check() oracle (Producer != Verifier, section 11.4.240):
# its own comparison logic below is written fresh, directly against the two
# new fixtures' own checked-in expected_verdict.json documents.
#
# Two NEW fixtures under fixtures/resume_revalidate/ (NOT added to the
# pre-existing, closed T126 RED test's own fixed $SCENARIOS list -- that
# file is a completed historical deliverable and is left untouched; these
# fixtures are exercised ONLY by this file):
#   rr_unverifiable_external_dependency_kind/  -- case (a) above
#   rr_unverifiable_ground_truth/              -- case (b) above
#
# Guard-viability proof (section 11.4.115(F), the canonical §1.1 mutation
# for a landed fix being the fix-commit's own revert): this file ALSO
# re-runs both new fixtures against the REAL PRE-FIX handoff.py -- the
# exact bytes at git HEAD (`constitution` submodule) as they stood
# immediately before this fix's own edit landed -- copied to a throwaway
# scratch file, NEVER the tracked file itself -- and asserts that copy
# WRONGLY reports safe_to_resume_without_reverification=true (rc=0) on
# BOTH fixtures, proving these two fixtures genuinely catch the I4
# regression if this fix is ever reverted.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/resume_revalidate"
IMPL="$FC/orchestration/handoff.py"

FIXTURES="rr_unverifiable_external_dependency_kind rr_unverifiable_ground_truth"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== I4 regression guard: control needle -- fixtures + the fixed tool exist ==="
if [ ! -f "$IMPL" ]; then
  echo "NOT ok control needle FAILED: $IMPL not found"
  failx
else
  echo "ok control needle: $IMPL resolves"
fi
for scen in $FIXTURES; do
  if [ ! -f "$FIXDIR/$scen/handoff.json" ] || [ ! -f "$FIXDIR/$scen/expected_verdict.json" ]; then
    echo "NOT ok control needle FAILED: $scen missing handoff.json or expected_verdict.json"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: both new fixtures carry handoff.json + expected_verdict.json"
fi

# --- own, from-scratch comparison (never imported from test_resume_revalidate_red.sh) ---
compare_outcome() {
  local derived_path="$1" expected_path="$2"
  python3 -c "
import json
d = json.load(open('$derived_path'))
e = json.load(open('$expected_path'))
def norm_reasons(r):
    return sorted(((x['class'], x['detail']) for x in r))
ok = (d.get('handoff_id') == e.get('handoff_id')
      and d['safe_to_resume_without_reverification'] == e['safe_to_resume_without_reverification']
      and norm_reasons(d['unsafe_reasons']) == norm_reasons(e['unsafe_reasons'])
      and sorted(d['facts_needing_reverification']) == sorted(e['facts_needing_reverification'])
      and sorted(d['effects_not_to_repeat']) == sorted(e['effects_not_to_repeat']))
print('MATCH' if ok else 'MISMATCH derived=%s expected=%s' % (json.dumps(d, sort_keys=True), json.dumps(e, sort_keys=True)))
"
}

echo
echo "=== Real-tool invocation (FIXED handoff.py): both new fixtures report UNSAFE, matching expected_verdict.json ==="
for scen in $FIXTURES; do
  SDIR="$FIXDIR/$scen"
  ACTUAL="$TMP/${scen}.actual.json"
  ERR="$TMP/${scen}.err"
  python3 "$IMPL" resume-check --handoff "$SDIR/handoff.json" --out "$ACTUAL" >"$ERR" 2>&1
  RC=$?
  if [ ! -f "$ACTUAL" ]; then
    echo "NOT ok $scen: real resume-check invocation wrote no --out document -- $(cat "$ERR" 2>/dev/null)"
    failx
    continue
  fi
  RESULT=$(compare_outcome "$ACTUAL" "$SDIR/expected_verdict.json")
  if [ "$RC" = "1" ] && [ "$RESULT" = "MATCH" ]; then
    echo "ok $scen: real (fixed) handoff.py resume-check exited 1 (UNSAFE) as"
    echo "   expected and its outcome matches expected_verdict.json"
  else
    echo "NOT ok $scen: real (fixed) resume-check invocation rc=$RC (wanted 1), $RESULT"
    failx
  fi
done

# --- Guard-viability (section 11.4.115(F)): the REAL PRE-FIX tool wrongly reports SAFE ---
echo
echo "=== Guard-viability: the PRE-FIX handoff.py (git HEAD, before the I4 fix) wrongly reports SAFE on both new fixtures ==="
cd "$ROOT/constitution" || { echo "NOT ok: could not cd into constitution submodule"; failx; exit 1; }
PRE_FIX_COPY="$TMP/handoff_pre_i4_fix.py"
if ! git show HEAD:scripts/fastcycle/orchestration/handoff.py > "$PRE_FIX_COPY" 2>"$TMP/git_show.err"; then
  echo "NOT ok guard-viability BLIND: could not retrieve HEAD's handoff.py via git show -- $(cat "$TMP/git_show.err")"
  failx
else
  # Copy the sibling fc_common.py the pre-fix copy imports by relative path
  # (../lib/fc_common.py from orchestration/) into the SAME relative layout
  # inside the scratch dir so the pre-fix copy's own sys.path insertion
  # resolves correctly -- never editing or moving the tracked lib file.
  mkdir -p "$TMP/orchestration_scratch/../lib"
  cp "$PRE_FIX_COPY" "$TMP/orchestration_scratch/handoff.py"
  mkdir -p "$TMP/lib"
  cp "scripts/fastcycle/lib/fc_common.py" "$TMP/lib/fc_common.py"
  for scen in $FIXTURES; do
    SDIR="$FIXDIR/$scen"
    MUT_OUT="$TMP/${scen}.mut.json"
    python3 "$TMP/orchestration_scratch/handoff.py" resume-check --handoff "$SDIR/handoff.json" --out "$MUT_OUT" >"$TMP/${scen}.mut.err" 2>&1
    MUT_RC=$?
    if [ ! -f "$MUT_OUT" ]; then
      echo "NOT ok guard-viability $scen BLIND: pre-fix copy wrote no --out document -- $(cat "$TMP/${scen}.mut.err")"
      failx
      continue
    fi
    MUT_SAFE=$(python3 -c "import json; print(json.load(open('$MUT_OUT'))['safe_to_resume_without_reverification'])")
    if [ "$MUT_SAFE" = "True" ] && [ "$MUT_RC" = "0" ]; then
      echo "ok guard-viability ($scen): the PRE-FIX handoff.py wrongly reports"
      echo "   safe_to_resume_without_reverification=true (rc=0) on this fixture"
      echo "   (whose correct, FIXED verdict is UNSAFE) -- proving this fixture"
      echo "   genuinely catches the I4 fail-open regression if the fix is ever"
      echo "   reverted"
    else
      echo "NOT ok guard-viability ($scen) FAILED: pre-fix rc=$MUT_RC safe=$MUT_SAFE"
      echo "     (expected rc=0, safe=True) -- this fixture would NOT catch a"
      echo "     revert of the I4 fix and needs revising"
      failx
    fi
  done
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== I4 REGRESSION GUARD: ALL CHECKS PASS -- the fixed handoff.py correctly"
  echo "    fails CLOSED on both new fixtures, and the pre-fix handoff.py is"
  echo "    independently confirmed to have failed OPEN on both -- the guard is"
  echo "    load-bearing. ==="
else
  echo "=== I4 REGRESSION GUARD: FAILURES ABOVE -- see NOT ok lines. ==="
fi

exit $fail
