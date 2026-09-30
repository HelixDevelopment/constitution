#!/bin/bash
# Purpose : T140 Round 1 (batched Opus-xhigh independent review of SpecKit-004
#           "fast-dev-cycles" User Story 5) finding I4 regression guard --
#           EXTENDED by T140 Round 2's I2 + I3 fixes (this file's own header
#           documents all three rounds so the guard's own history is legible
#           from the file alone).
#
# I4 (verbatim from the Round 1 review, recorded in docs/CONTINUATION.md
# ADDENDUM 78):
# "`handoff.py resume-check` fails OPEN (non-git-tree deps and a missing
# `ground_truth_effects.json` are silently skipped, reporting
# `safe_to_resume_without_reverification: true` with no skip recorded -- a
# section 11.4.201(6) false-null)."
#
# Fixed in orchestration/handoff.py's cmd_resume_check (commit cf0242a) by:
#   (a) an external_deps entry whose `kind` is anything OTHER than the only
#       re-hashable kind, "git-tree", is now recorded as its own
#       "unverifiable-external-dependency" unsafe_reasons entry (with its
#       declared affects_verified ids added to facts_needing_reverification)
#       instead of being silently `continue`d past;
#   (b) a MISSING ground_truth_effects.json sibling is now recorded as its
#       own "unverifiable-ground-truth" unsafe_reasons entry WHEN the
#       record's own effects_performed is non-empty.
#
# R2-I2 (T140 Round 2 review, three sub-findings on the Round 1 I4 fix
# itself -- (C) is a genuine ARCHITECTURAL correction of the Round 1 fix's
# own design, not merely a missed case: an EMPTY effects_performed does NOT
# prove no effect occurred -- the agent could have crashed BEFORE it ever
# recorded one in its own handoff doc -- so a missing ground_truth_effects.json
# is now ALWAYS an unverifiable gap, regardless of effects_performed's own
# emptiness):
#   (C) missing ground_truth_effects.json with an EMPTY effects_performed
#       used to give safe=true with no skip recorded -- now ALWAYS an
#       "unverifiable-ground-truth" finding (the empty-vs-non-empty cases
#       stay honestly DISTINGUISHED in the detail text, both now unsafe).
#   (D) a malformed/unreadable ground_truth_effects.json (parse error, or a
#       valid-JSON-but-non-list top-level value) used to be silently
#       coerced to `[]` (read as "no ground truth effects exist") -- now its
#       own distinct "unreadable-ground-truth" finding, never silently
#       absorbed.
#   (F) a non-dict external_deps entry, or a dict entry whose `kind` field
#       is itself missing/malformed, used to be silently `continue`d past
#       (DEC-34 requires EVERY dependency be re-hashed) -- now its own
#       distinct "malformed-external-dependency" finding, never silently
#       skipped.
# Fixed in orchestration/handoff.py's cmd_resume_check (this file's own
# accompanying source commit).
#
# R2-I3 (T140 Round 2 review, a regression THIS test file itself had):
# "test_handoff_i4_regression.sh now fails every run. Its guard-viability
# step uses `git show HEAD:scripts/fastcycle/orchestration/handoff.py` as
# the 'pre-fix' version. Since commit cf0242a, HEAD *is* the fixed version.
# ... The pre-fix copy should be pinned (a fixture file or an explicit
# commit such as d677f0c), never HEAD."
#
# R2-I3 fix (this file, this edit): `d677f0c` was VERIFIED (via `git log
# --oneline -- scripts/fastcycle/orchestration/handoff.py`) to be the WRONG
# commit -- it is T140 Round 1 finding I5's *limit_class.py* half, a
# different file entirely, never touching handoff.py. The genuinely correct
# pre-I4-fix commit for handoff.py is `64daa96` (the last commit that
# touched this file before cf0242a landed the I4 fix), confirmed by:
#   git log --oneline -- scripts/fastcycle/orchestration/handoff.py
#     cf0242a  <- I3+I4+I5(handoff.py half) fix
#     64daa96  <- T134: resume/resume-check FIRST implemented (pre-I4-fix)
#     f2a11de  <- T133: write/validate implemented
# Rather than a commit-hash pin (which the R2-I3 finding itself proves is a
# footgun -- a wrong hash silently resolves to a DIFFERENT, unrelated file's
# history with no error), this fix uses the MORE ROBUST of the two options
# the task text offers: a CHECKED-IN FIXTURE COPY of each pre-fix file's
# EXACT byte content, immune to any future history rewrite, branch move, or
# HEAD advance -- `fixtures/resume_revalidate/_pinned/handoff_pre_i4_fix.py`
# (commit 64daa96, the TRUE pre-I4-fix content) and
# `fixtures/resume_revalidate/_pinned/handoff_pre_r2i2_fix.py` (this
# submodule's HEAD immediately BEFORE the R2-I2 fix landed -- i.e. the
# I4-fixed-but-still-R2-I2-broken content, used to prove the THREE new R2-I2
# fixtures below genuinely catch a revert of THAT fix). Both pinned copies
# were extracted via `git show <verified-commit>:...` ONCE, at authoring
# time, and are themselves ordinary tracked files from this point on -- this
# script never invokes `git show` against a moving ref again.
#
# This file is a SELF-CONTAINED regression guard -- it does NOT import,
# source, or otherwise couple to test_resume_revalidate_red.sh's own
# derive_resume_check() oracle (Producer != Verifier, section 11.4.240): its
# own comparison logic below is written fresh, directly against each
# fixture's own checked-in expected_verdict.json document.
#
# Five fixtures total under fixtures/resume_revalidate/ (NONE added to the
# pre-existing, closed T126 RED test's own fixed $SCENARIOS list -- that
# file is a completed historical deliverable and is left untouched; every
# fixture below is exercised ONLY by this file):
#   rr_unverifiable_external_dependency_kind/   -- I4 case (a)
#   rr_unverifiable_ground_truth/                -- I4 case (b)
#   rr_missing_ground_truth_empty_effects/       -- R2-I2 case (C)
#   rr_malformed_ground_truth_file/              -- R2-I2 case (D)
#   rr_malformed_external_dep/                   -- R2-I2 case (F), two
#                                                    malformed entries in one
#                                                    fixture (non-dict AND
#                                                    dict-missing-kind)
#
# Guard-viability proof (section 11.4.115(F), the canonical §1.1 mutation
# for a landed fix being the fix-commit's own revert): this file re-runs
# EVERY fixture above against its own matching PINNED pre-fix copy (never a
# moving ref) and asserts the pinned copy's output does NOT match that
# fixture's own expected_verdict.json -- proving each fixture genuinely
# catches its own regression if the corresponding fix is ever reverted. This
# is a STRICTER check than "wrongly reports safe=true" (which R1's own
# version used): the rr_malformed_external_dep fixture's PRE-R2-I2-fix
# behaviour is NOT "wrongly safe" (the I4 fix already makes the
# dict-missing-kind entry unsafe via a DIFFERENT class,
# "unverifiable-external-dependency", while silently skipping the non-dict
# entry entirely) -- a naive safe==true check would have MISSED that this
# fixture still genuinely catches the R2-I2 regression via its full-verdict
# mismatch (wrong class name + one missing reason), so this file compares
# the COMPLETE verdict shape, not merely the boolean safe flag.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/resume_revalidate"
PINDIR="$FIXDIR/_pinned"
IMPL="$FC/orchestration/handoff.py"
LIB="$FC/lib/fc_common.py"

# scenario -> which pinned pre-fix copy proves its guard-viability
I4_FIXTURES="rr_unverifiable_external_dependency_kind rr_unverifiable_ground_truth"
R2I2_FIXTURES="rr_missing_ground_truth_empty_effects rr_malformed_ground_truth_file rr_malformed_external_dep"
ALL_FIXTURES="$I4_FIXTURES $R2I2_FIXTURES"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== I4+R2-I2 regression guard: control needle -- fixtures + the fixed tool + pinned copies all exist ==="
if [ ! -f "$IMPL" ]; then
  echo "NOT ok control needle FAILED: $IMPL not found"
  failx
else
  echo "ok control needle: $IMPL resolves"
fi
for scen in $ALL_FIXTURES; do
  if [ ! -f "$FIXDIR/$scen/handoff.json" ] || [ ! -f "$FIXDIR/$scen/expected_verdict.json" ]; then
    echo "NOT ok control needle FAILED: $scen missing handoff.json or expected_verdict.json"
    failx
  fi
done
for pinned in handoff_pre_i4_fix.py handoff_pre_r2i2_fix.py; do
  if [ ! -f "$PINDIR/$pinned" ]; then
    echo "NOT ok control needle FAILED: pinned pre-fix copy $PINDIR/$pinned not found"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: all $(echo $ALL_FIXTURES | wc -w) fixtures carry handoff.json + expected_verdict.json, both pinned pre-fix copies present"
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
echo "=== Real-tool invocation (FIXED handoff.py): every fixture reports UNSAFE, matching its own expected_verdict.json ==="
for scen in $ALL_FIXTURES; do
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

# --- Guard-viability (section 11.4.115(F)): each fixture's matching PINNED
# pre-fix copy must NOT reproduce the fixed tool's expected verdict ---
run_against_pinned() {
  # $1 = pinned copy basename (under $PINDIR), $2 = scenario, $3 = out path.
  # Layout MUST stay exactly ONE level deep ($TMP/orchestration_scratch/
  # handoff.py, sibling of $TMP/lib/fc_common.py) -- the pinned script
  # itself computes its own _LIB_DIR as dirname(__file__)/../lib, so an
  # extra nested directory level (e.g. naming a dir after $pinned) breaks
  # that relative resolution.
  local pinned="$1" scen="$2" out="$3"
  mkdir -p "$TMP/orchestration_scratch" "$TMP/lib"
  cp "$PINDIR/$pinned" "$TMP/orchestration_scratch/handoff.py"
  cp "$LIB" "$TMP/lib/fc_common.py"
  python3 "$TMP/orchestration_scratch/handoff.py" resume-check \
    --handoff "$FIXDIR/$scen/handoff.json" --out "$out" >"$TMP/${scen}.${pinned}.mut.err" 2>&1
}

echo
echo "=== Guard-viability: each fixture's PINNED pre-fix copy does NOT reproduce the fixed verdict (checked-in, never HEAD-relative) ==="
for scen in $I4_FIXTURES; do
  MUT_OUT="$TMP/${scen}.i4pin.mut.json"
  run_against_pinned "handoff_pre_i4_fix.py" "$scen" "$MUT_OUT"
  if [ ! -f "$MUT_OUT" ]; then
    echo "NOT ok guard-viability $scen BLIND: pinned pre-I4-fix copy wrote no --out document -- $(cat "$TMP/${scen}.handoff_pre_i4_fix.py.mut.err" 2>/dev/null)"
    failx
    continue
  fi
  MUT_RESULT=$(compare_outcome "$MUT_OUT" "$FIXDIR/$scen/expected_verdict.json")
  if [ "$MUT_RESULT" != "MATCH" ]; then
    echo "ok guard-viability ($scen): the PINNED pre-I4-fix handoff.py's verdict"
    echo "   does NOT match this fixture's expected_verdict.json ($MUT_RESULT) --"
    echo "   proving this fixture genuinely catches the I4 fail-open regression"
    echo "   if the fix is ever reverted"
  else
    echo "NOT ok guard-viability ($scen) FAILED: the pinned pre-I4-fix copy"
    echo "     ALREADY matches the fixed verdict -- this fixture would NOT catch"
    echo "     a revert of the I4 fix and needs revising"
    failx
  fi
done
for scen in $R2I2_FIXTURES; do
  MUT_OUT="$TMP/${scen}.r2i2pin.mut.json"
  run_against_pinned "handoff_pre_r2i2_fix.py" "$scen" "$MUT_OUT"
  if [ ! -f "$MUT_OUT" ]; then
    echo "NOT ok guard-viability $scen BLIND: pinned pre-R2-I2-fix copy wrote no --out document -- $(cat "$TMP/${scen}.handoff_pre_r2i2_fix.py.mut.err" 2>/dev/null)"
    failx
    continue
  fi
  MUT_RESULT=$(compare_outcome "$MUT_OUT" "$FIXDIR/$scen/expected_verdict.json")
  if [ "$MUT_RESULT" != "MATCH" ]; then
    echo "ok guard-viability ($scen): the PINNED pre-R2-I2-fix handoff.py's"
    echo "   verdict does NOT match this fixture's expected_verdict.json"
    echo "   ($MUT_RESULT) -- proving this fixture genuinely catches the R2-I2"
    echo "   fail-open regression if the fix is ever reverted"
  else
    echo "NOT ok guard-viability ($scen) FAILED: the pinned pre-R2-I2-fix copy"
    echo "     ALREADY matches the fixed verdict -- this fixture would NOT catch"
    echo "     a revert of the R2-I2 fix and needs revising"
    failx
  fi
done

echo
if [ "$fail" = 0 ]; then
  echo "=== I4+R2-I2 REGRESSION GUARD: ALL CHECKS PASS -- the fixed handoff.py"
  echo "    correctly fails CLOSED on every fixture, and every fixture's own"
  echo "    pinned pre-fix copy is independently confirmed to NOT reproduce that"
  echo "    verdict -- every guard here is load-bearing. ==="
else
  echo "=== I4+R2-I2 REGRESSION GUARD: FAILURES ABOVE -- see NOT ok lines. ==="
fi

exit $fail
