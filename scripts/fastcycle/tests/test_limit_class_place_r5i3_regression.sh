#!/bin/bash
# Purpose : T140 Round 5 (batched Opus-xhigh independent review of SpecKit-004
#           "fast-dev-cycles" User Story 5) finding R5-I3 regression guard --
#           `orchestration/limit_class.py`'s `place` subcommand (T136,
#           SEPARATE from this task's own R5-I1/R5-I2 fixes to
#           orchestration/handoff.py -- lower blast radius since every
#           fixture here is operator-authored, per the review's own text).
#
# R5-I3 (verbatim from the Round 5 review): "`limit_class.py`'s `cmd_place`
# crashes uncaught on malformed fixtures, and its crash exit code (1)
# COLLIDES with the tool's own intentional `EXIT_PLACE_REFUSED` code (also
# 1, at `limit_class.py:217`) -- making a genuine crash indistinguishable
# from an intentional refusal to a caller reading only the exit code."
#
# `derive_placement` (limit_class.py) already raises KeyError, cleanly
# caught by `cmd_place` as EXIT_USAGE, when a fixture is MISSING
# `live_agents`/`aliases`/an alias entry's own required keys (by that
# function's own documented design). The genuinely uncaught gap was a
# field whose VALUE has the WRONG JSON TYPE (present, not missing) -- four
# distinct repros, all reproduced live against the pinned pre-R5-I3-fix
# copy per the reviewer's own exact inputs, BEFORE fixing (section
# 11.4.199):
#   (A) fixture top-level value is a JSON list (`[]`) instead of an object
#       -- crashed `list indices must be integers or slices, not str` at
#       `fx["live_agents"]`.
#   (B) `live_agents` is a JSON string (`"x"`) instead of an integer --
#       crashed `unsupported operand type(s) for /: 'str' and 'int'` at
#       `derive_placement`'s `cap_per_alias = math.ceil(live_agents / m)`.
#   (C) `aliases` is a JSON integer (`5`) instead of a list -- crashed
#       `'int' object is not iterable` at `derive_placement`'s
#       list-comprehension partitioning.
#   (D) `aliases` is a JSON list of integers (`[5]`) rather than a list of
#       alias objects -- crashed `'int' object is not subscriptable` at
#       `a["operational"]`.
# On every crash, rc=1 -- the SAME value as `EXIT_PLACE_REFUSED`, and no
# `--out` document is written, indistinguishable-by-exit-code-alone from a
# genuine "no eligible alias" refusal.
#
# Fixed in orchestration/limit_class.py (source-file commit alongside this
# test) by:
#   (1) a new, up-front `_validate_placement_fixture_shape(fx)` check, run
#       in `cmd_place` immediately after the fixture is parsed and BEFORE
#       `derive_placement` is called -- mirroring the reviewer's own cited
#       reference pattern, `orchestration/custody_sweep.py`'s
#       `cmd_verify_proposal` (section 11.4.227 reuse-the-pattern): that
#       function ALREADY handles equivalent malformed inputs cleanly (a
#       list top-level value still supports `k not in d` with no crash; a
#       wrong-type `action`/`entry_id` still resolves to a clean REFUSED
#       verdict via ordinary membership/set comparisons, which never raise
#       on a wrong-type value). `_validate_placement_fixture_shape` is an
#       EXPLICIT check (rather than relying purely on membership-test-safe
#       code, as `derive_verdict` does) because `derive_placement` itself
#       genuinely INDEXES into structured dicts/lists by field name and
#       cannot avoid a wrong-type crash purely through
#       membership-test-shaped code the way `derive_verdict` can. A shape
#       violation now returns EXIT_USAGE (2) -- genuinely DIFFERENT from
#       BOTH EXIT_OK (0) and EXIT_PLACE_REFUSED (1) -- naming the exact bad
#       field + expected type + actual type/value.
#   (2) a DEFENSE-IN-DEPTH `except TypeError` alongside `cmd_place`'s
#       existing `except KeyError`, wrapping the `derive_placement(fx)`
#       call: a genuinely unanticipated wrong-type field the check above
#       does not enumerate (section 11.4.6, that check is not claimed
#       exhaustive) still fails closed with EXIT_USAGE (2) and a
#       diagnosable message naming the real exception, never landing on
#       EXIT_PLACE_REFUSED's own exit code by falling through uncaught.
# `_validate_placement_fixture_shape` checks TYPE only, never PRESENCE --
# a genuinely MISSING field is left entirely to the pre-existing KeyError
# path (unchanged by this fix).
#
# `fixtures/alias_spread/_pinned/limit_class_pre_r5i3_fix.py` (this
# submodule's HEAD -- commit 862be3782af74b7a5f2834baabbb1154d28d0803 --
# immediately BEFORE this fix landed, extracted via `git show <verified
# commit>:...` ONCE at authoring time, per the SAME checked-in-pinned-copy
# convention `test_handoff_i4_regression.sh` already established --
# section 11.4.227) is this file's own guard-viability substrate.
# `limit_class.py` has no sibling-lib import (unlike
# `orchestration/handoff.py`'s `fc_common` dependency), so the pinned copy
# is run directly from its own checked-in path -- no scratch-directory
# copying is needed.
#
# Four NEW malformed fixtures (this file's OWN, never added to
# `fixtures/alias_spread/`'s pre-existing three golden/negative-control
# fixtures that `test_alias_spread_red.sh` -- a SEPARATE, EARLIER,
# completed T128/T136 deliverable -- already owns and is left untouched;
# `fixtures/alias_spread/README.md`'s own "Explicit scope exclusion" notes
# no golden-bad fixture is in scope for THAT file, which is exactly why
# this SEPARATE regression-guard file exists rather than extending that
# one): flat fixture JSON files (matching this directory's own existing
# `as_*.json` flat-file convention, since `place --fixture <path>` takes a
# single file, never a directory):
#   as_r5i3_malformed_top_level_not_object.json      -- case (A)
#   as_r5i3_malformed_live_agents_not_int.json        -- case (B)
#   as_r5i3_malformed_aliases_not_list.json           -- case (C)
#   as_r5i3_malformed_aliases_list_of_scalars.json    -- case (D)
# Plus ONE genuinely-valid negative control, per the task's own
# instruction ("plus a genuinely-valid case as a negative control") --
# REUSING the pre-existing `as_negctrl_single_alias.json` fixture rather
# than adding a redundant new one (section 11.4.227): it is already a
# real, checked-in, `place`-shaped fixture producing a genuine EXIT_OK
# placement, exercised here to prove this file's OWN checks do not
# false-positive-refuse a well-formed fixture (section 11.4.201's
# false-positive guard).
#
# Guard-viability proof (section 11.4.115(F), the canonical §1.1 mutation
# for a landed fix being the fix-commit's own revert): each of the four
# malformed fixtures is re-run against the pinned pre-R5-I3-fix copy and
# is asserted to CRASH uncaught (non-zero exit, NO `--out` document
# written, a genuine Python "Traceback"+"TypeError" in stderr) -- proving
# each fixture genuinely triggers the pre-fix crash-into-collision if the
# fix is ever reverted (the SAME CRASH-detection style
# test_handoff_i4_regression.sh's own R4-I1/R5-I1 sections established).
# The negative-control fixture is ALSO re-run against the pinned copy and
# is asserted to STILL exit 0 -- a control needle proving the pinned copy
# is genuinely the SAME tool minus only this fix, not a universally-broken
# stand-in that would trivially "catch" every fixture regardless of
# content (section 11.4.201(7)(b)).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/alias_spread"
PINDIR="$FIXDIR/_pinned"
IMPL="$FC/orchestration/limit_class.py"
PINNED="$PINDIR/limit_class_pre_r5i3_fix.py"

MALFORMED_FIXTURES="as_r5i3_malformed_top_level_not_object as_r5i3_malformed_live_agents_not_int as_r5i3_malformed_aliases_not_list as_r5i3_malformed_aliases_list_of_scalars"
NEGCTRL_FIXTURE="as_negctrl_single_alias"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R5-I3 regression guard: control needle -- fixtures + the fixed tool + pinned copy all exist ==="
if [ ! -f "$IMPL" ]; then
  echo "NOT ok control needle FAILED: $IMPL not found"
  failx
else
  echo "ok control needle: $IMPL resolves"
fi
if [ ! -f "$PINNED" ]; then
  echo "NOT ok control needle FAILED: pinned pre-fix copy $PINNED not found"
  failx
else
  echo "ok control needle: pinned pre-R5-I3-fix copy resolves"
fi
for scen in $MALFORMED_FIXTURES; do
  if [ ! -f "$FIXDIR/$scen.json" ]; then
    echo "NOT ok control needle FAILED: $FIXDIR/$scen.json not found"
    failx
  fi
done
if [ ! -f "$FIXDIR/$NEGCTRL_FIXTURE.json" ]; then
  echo "NOT ok control needle FAILED: $FIXDIR/$NEGCTRL_FIXTURE.json not found"
  failx
fi
if [ "$fail" = 0 ]; then
  echo "ok control needle: all $(echo $MALFORMED_FIXTURES | wc -w) malformed fixtures + the reused negative-control fixture present"
fi

echo
echo "=== Real-tool invocation (FIXED limit_class.py): every malformed fixture reports EXIT_USAGE (2), distinct from EXIT_OK (0) and EXIT_PLACE_REFUSED (1) ==="
for scen in $MALFORMED_FIXTURES; do
  OUT="$TMP/${scen}.actual.json"
  ERR="$TMP/${scen}.err"
  rm -f "$OUT"
  python3 "$IMPL" place --fixture "$FIXDIR/$scen.json" --out "$OUT" >"$ERR" 2>&1
  RC=$?
  if [ "$RC" != "2" ]; then
    echo "NOT ok $scen: real (fixed) place invocation rc=$RC (wanted 2/EXIT_USAGE) -- $(cat "$ERR" 2>/dev/null)"
    failx
    continue
  fi
  if [ -f "$OUT" ]; then
    echo "NOT ok $scen: real (fixed) place invocation rc=2 but WROTE an --out document anyway -- a usage error must never write a verdict"
    failx
    continue
  fi
  if ! grep -q "malformed field" "$ERR" 2>/dev/null; then
    echo "NOT ok $scen: real (fixed) place invocation rc=2 but stderr does not name a malformed field -- $(cat "$ERR" 2>/dev/null)"
    failx
    continue
  fi
  echo "ok $scen: real (fixed) limit_class.py place exited 2 (EXIT_USAGE), wrote no"
  echo "   --out document, and its stderr names the malformed field"
done

echo
echo "=== Real-tool invocation (FIXED limit_class.py): the reused negative-control fixture is UNAFFECTED, still exits 0 (EXIT_OK) ==="
OUT="$TMP/${NEGCTRL_FIXTURE}.actual.json"
ERR="$TMP/${NEGCTRL_FIXTURE}.err"
python3 "$IMPL" place --fixture "$FIXDIR/$NEGCTRL_FIXTURE.json" --out "$OUT" >"$ERR" 2>&1
RC=$?
if [ "$RC" != "0" ] || [ ! -f "$OUT" ]; then
  echo "NOT ok $NEGCTRL_FIXTURE: real (fixed) place invocation rc=$RC (wanted 0), out_exists=$([ -f "$OUT" ] && echo yes || echo no) -- $(cat "$ERR" 2>/dev/null)"
  failx
else
  REFUSED=$(python3 -c "import json; print(json.load(open('$OUT'))['refused'])")
  if [ "$REFUSED" = "False" ]; then
    echo "ok $NEGCTRL_FIXTURE: real (fixed) limit_class.py place still exits 0 and places"
    echo "   the agent (refused=False) -- the R5-I3 fix does not false-positive-refuse"
    echo "   a well-formed fixture"
  else
    echo "NOT ok $NEGCTRL_FIXTURE: place exited 0 but refused=$REFUSED (wanted False) -- unexpected change to a well-formed fixture's own outcome"
    failx
  fi
fi

echo
echo "=== Guard-viability: each malformed fixture's PINNED pre-R5-I3-fix copy CRASHES uncaught (checked-in, never HEAD-relative) ==="
for scen in $MALFORMED_FIXTURES; do
  MUT_OUT="$TMP/${scen}.pin.mut.json"
  MUT_ERR="$TMP/${scen}.pin.mut.err"
  rm -f "$MUT_OUT"
  python3 "$PINNED" place --fixture "$FIXDIR/$scen.json" --out "$MUT_OUT" >"$MUT_ERR" 2>&1
  if [ -f "$MUT_OUT" ]; then
    echo "NOT ok guard-viability ($scen) FAILED: the pinned pre-R5-I3-fix copy WROTE an"
    echo "     --out document instead of crashing -- this fixture would NOT catch a"
    echo "     revert of the R5-I3 fix and needs revising"
    failx
    continue
  fi
  if grep -q "^Traceback" "$MUT_ERR" 2>/dev/null && grep -q "^TypeError" "$MUT_ERR" 2>/dev/null; then
    echo "ok guard-viability ($scen): the PINNED pre-R5-I3-fix limit_class.py CRASHED"
    echo "   uncaught (Traceback + TypeError in stderr, NO --out document written) --"
    echo "   proving this fixture genuinely catches the R5-I3 crash-into-collision"
    echo "   regression if the fix is ever reverted"
  else
    echo "NOT ok guard-viability ($scen) BLIND: the pinned pre-R5-I3-fix copy wrote no"
    echo "     --out document but its stderr does not show the expected"
    echo "     Traceback+TypeError crash signature -- $(cat "$MUT_ERR" 2>/dev/null)"
    failx
  fi
done

echo
echo "=== Guard-viability control needle: the PINNED pre-R5-I3-fix copy is NOT universally broken -- the reused negative-control fixture still exits 0 against it ==="
MUT_OUT="$TMP/${NEGCTRL_FIXTURE}.pin.mut.json"
MUT_ERR="$TMP/${NEGCTRL_FIXTURE}.pin.mut.err"
python3 "$PINNED" place --fixture "$FIXDIR/$NEGCTRL_FIXTURE.json" --out "$MUT_OUT" >"$MUT_ERR" 2>&1
MUT_RC=$?
if [ "$MUT_RC" = "0" ] && [ -f "$MUT_OUT" ]; then
  echo "ok guard-viability control needle: the pinned pre-R5-I3-fix copy still exits 0"
  echo "   on the well-formed negative-control fixture -- proving it is genuinely the"
  echo "   SAME tool minus only the R5-I3 fix, not a stand-in that would trivially"
  echo "   'catch' every fixture regardless of content"
else
  echo "NOT ok guard-viability control needle BLIND: the pinned pre-R5-I3-fix copy did"
  echo "     NOT cleanly exit 0 on the well-formed negative-control fixture (rc=$MUT_RC) --"
  echo "     the pinned copy may itself be broken in an unrelated way, which would make"
  echo "     every crash-detection check above meaningless -- $(cat "$MUT_ERR" 2>/dev/null)"
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R5-I3 REGRESSION GUARD: ALL CHECKS PASS -- the fixed limit_class.py"
  echo "    correctly fails with EXIT_USAGE (2), genuinely distinct from EXIT_OK (0)"
  echo "    and EXIT_PLACE_REFUSED (1), on every malformed fixture; the reused"
  echo "    negative-control fixture is unaffected; and every malformed fixture's own"
  echo "    pinned pre-fix copy is independently confirmed to crash uncaught -- every"
  echo "    guard here is load-bearing. ==="
else
  echo "=== R5-I3 REGRESSION GUARD: FAILURES ABOVE -- see NOT ok lines. ==="
fi

exit $fail
