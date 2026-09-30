#!/bin/bash
# Purpose : T140 Round 6 (batched Opus-xhigh independent review of SpecKit-004
#           "fast-dev-cycles" User Story 5) regression guard for
#           `orchestration/custody_sweep.py` finding R6-I3 (two sub-cases)
#           plus its own sibling R6-I1(b)/R6-I2(write-guard) fixes -- none of
#           which had any dedicated regression-test coverage before this
#           file landed (section 11.4.224 test-first; the pre-existing
#           `test_custody_sweep_red.sh` is a T129 absence-check baseline,
#           never exercises `verify-proposal`/`inventory`/`propose` against
#           the real tool at all -- see this file's own control needle
#           below).
#
# R6-I3 (verbatim summary from the Round 6 review, section 11.4.6): an
# EARLIER round's docstring elsewhere in this tree (limit_class.py's own
# `_validate_placement_fixture_shape`, discussing R5-I3) incorrectly claimed
# `custody_sweep.py`'s `cmd_verify_proposal` "ALREADY handles equivalent
# malformed inputs cleanly" -- it did NOT:
#   (1) a --proposal top-level JSON value that is a NON-ITERABLE scalar (a
#       bare int or `null`) crashed uncaught at `k not in d` ("argument of
#       type 'int'/'NoneType' is not iterable").
#   (2) a wrong-type `backup_artifact_path` (e.g. a JSON list) separately
#       crashed `derive_verdict` uncaught at `os.path.isabs()`
#       ("expected str, bytes or os.PathLike object, not list").
# Fixed by: (1) an up-front `isinstance(d, dict)` check, BEFORE the
# `missing`-keys membership check, returning its own EXIT_USAGE(2); (2)
# explicit string-type checks on `backup_hash`/`backup_artifact_path`
# (when present), also returning EXIT_USAGE(2), BEFORE `derive_verdict` is
# ever called.
#
# This file's own sibling Round 6 fixes to `custody_sweep.py` (verified
# here too, alongside R6-I3, since they share the exact same "an
# uncaught crash where an honest verdict belongs" shape and were landed in
# the SAME uncommitted diff -- section 11.4.227 reuse-not-reinvention, never
# a fourth, narrower test file per finding):
#   R6-I1(b) sibling: a non-finite JSON constant (`NaN`) anywhere in
#     --inventory/--proposal used to be silently ACCEPTED by plain
#     `json.load` (Python's stdlib default `allow_nan=True`) -- now refused
#     at parse time via the shared `fc_common.strict_loads`
#     (`json.JSONDecodeError`-only except clauses widened to `ValueError`,
#     never narrowed: `json.JSONDecodeError` is itself a `ValueError`
#     subclass, so every case the old clause already caught is still
#     caught).
#   R6-I2 sibling: an unwritable --out path (parent directory missing/not
#     writable/a permissions error) used to crash ALL THREE subcommands
#     (`inventory`/`propose`/`verify-proposal`) uncaught at `write_doc`'s own
#     `os.makedirs(out_dir, exist_ok=True)` -- now each wrapped in its own
#     `try/except OSError`, failing closed with its own diagnosable exit
#     code 2.
#
# FOUR new fixtures (matching this suite's existing flat
# `fixtures/custody_sweep/*.json` layout; `cs_r6_*` prefix, this being the
# FIRST test file to populate `fixtures/custody_sweep/` at all -- see
# control needle below):
#   cs_r6_nondict_int.json          -- top-level value is the bare int 5.
#   cs_r6_nondict_null.json         -- top-level value is JSON null.
#   cs_r6_backup_path_list.json     -- a well-formed destructive ('retire')
#     proposal whose backup_artifact_path is a JSON list, not a string.
#   cs_r6_nan_proposal.json         -- a well-formed non-destructive ('keep')
#     proposal carrying an unrelated `"note": NaN` field -- proves the
#     PARSE-TIME rejection fires regardless of which field the non-finite
#     constant sits under, and regardless of whether that field is ever
#     otherwise used.
# The unwritable-`--out` case (R6-I2 sibling) is exercised WITHOUT a
# checked-in fixture, via a scratch tmpdir whose parent path component is a
# regular FILE standing in for a directory -- not expressible as a static
# JSON fixture.
#
# Guard-viability proof (section 11.4.115(F)): every live-CLI case is ALSO
# run against `fixtures/custody_sweep/_pinned/custody_sweep_pre_r6_fix.py`
# -- extracted ONCE, via `git show HEAD:...`, from this submodule's own HEAD
# commit cf0242a0b99faa0956b8cab1b297a7be93543137 (T140 Round 7 review
# finding M1, section 11.4.6 -- CORRECTED here: an earlier revision of this
# comment cited a925a8dabf644f2b075290cce9404da484f4d410, matching the
# OTHER two sibling files' own [now also corrected] label. For THIS file
# specifically that hash was DOUBLY imprecise: custody_sweep.py's own last
# content-changing commit before the Round 6 fix is cf0242a0b99faa...
# -- a DIFFERENT commit from the 80ef88cb47e25274797c4bf49704... that is
# the correct answer for handoff.py/limit_class.py (verified
# independently: `git log -- .../custody_sweep.py` up to the Round 6 fix
# commit's own parent ends at cf0242a, never 80ef88c; and `git diff
# cf0242a:.../custody_sweep.py a925a8d:.../custody_sweep.py` is empty,
# confirming the CONTENT match while the commit that actually WROTE it is
# cf0242a, never 80ef88c nor a925a8d themselves). Unlike
# `limit_class.py`, `custody_sweep.py` ALREADY imports `fc_common` via the
# SAME `_LIB_DIR`-relative sys.path insertion `handoff.py` uses (pre-dating
# Round 6 -- only its `cmd_propose`/`cmd_verify_proposal` reads were widened
# from plain `json.load` to `fc_common.strict_loads` THIS round), so the
# pinned copy needs the SAME two-directory scratch layout
# (`test_handoff_i4_regression.sh`'s own `run_against_pinned()` convention:
# $TMP/orchestration_scratch/custody_sweep.py, sibling of
# $TMP/lib/fc_common.py) -- never run directly from its own checked-in
# `_pinned/` path (that path has no sibling `../lib/fc_common.py` of its
# own, so a direct run fails with a plain `ModuleNotFoundError`, proven
# live at authoring time before adopting the scratch-copy convention here).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/custody_sweep"
PINDIR="$FIXDIR/_pinned"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
PINNED="$PINDIR/custody_sweep_pre_r6_fix.py"
REPO_ROOT_ARG="$ROOT/constitution"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R6 regression guard: control needle -- fixtures + the fixed tool + pinned copy all exist ==="
for p in "$IMPL" "$LIB" "$PINNED" \
         "$FIXDIR/cs_r6_nondict_int.json" \
         "$FIXDIR/cs_r6_nondict_null.json" \
         "$FIXDIR/cs_r6_backup_path_list.json" \
         "$FIXDIR/cs_r6_nan_proposal.json"; do
  if [ ! -f "$p" ]; then
    echo "NOT ok control needle FAILED: $p not found"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: implementation + lib + pinned pre-R6-fix copy + all four new fixtures resolve"
fi
echo "ok control needle: this is the FIRST test file in this suite to invoke"
echo "   custody_sweep.py's verify-proposal/inventory subcommands against"
echo "   the real tool -- test_custody_sweep_red.sh (T129) is an absence-"
echo "   check baseline only, and never exercises this tool's live behaviour"

run_against_pinned() {
  # $1..$N = argv for the pinned copy; writes to stdout/stderr as invoked.
  mkdir -p "$TMP/orchestration_scratch" "$TMP/lib"
  cp "$PINNED" "$TMP/orchestration_scratch/custody_sweep.py"
  cp "$LIB" "$TMP/lib/fc_common.py"
  python3 "$TMP/orchestration_scratch/custody_sweep.py" "$@"
}

echo
echo "=== R6-I3(1)/nondict-int: --proposal top-level value is the bare int 5 ==="
FIXED_ERR="$TMP/ndi.fixed.err"
FIXED_OUT="$TMP/ndi.fixed.json"
python3 "$IMPL" verify-proposal --proposal "$FIXDIR/cs_r6_nondict_int.json" \
  --repo-root "$REPO_ROOT_ARG" --out "$FIXED_OUT" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && grep -q "not a JSON object" "$FIXED_ERR"; then
  echo "ok R6-I3(1)/int real (fixed) tool: verify-proposal fails closed with"
  echo "   EXIT_USAGE (2), no --out written, names the real bad type -- $(cat "$FIXED_ERR")"
else
  echo "NOT ok R6-I3(1)/int real (fixed) tool: rc=$FIXED_RC (wanted 2), out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) -- $(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
PIN_ERR="$TMP/ndi.pin.err"
PIN_OUT="$TMP/ndi.pin.json"
run_against_pinned verify-proposal --proposal "$FIXDIR/cs_r6_nondict_int.json" \
  --repo-root "$REPO_ROOT_ARG" --out "$PIN_OUT" >"$PIN_ERR" 2>&1
if [ -f "$PIN_OUT" ]; then
  echo "NOT ok R6-I3(1)/int guard-viability FAILED: pinned pre-R6-fix copy WROTE"
  echo "     an --out document instead of crashing"
  failx
elif grep -q "^Traceback" "$PIN_ERR" 2>/dev/null && grep -qi "is not iterable" "$PIN_ERR" 2>/dev/null; then
  echo "ok R6-I3(1)/int guard-viability: the PINNED pre-R6-fix custody_sweep.py"
  echo "   CRASHED uncaught (Traceback + 'not iterable' TypeError in stderr,"
  echo "   NO --out document written) -- proving this fixture genuinely"
  echo "   catches the R6-I3(1) regression if the fix is ever reverted"
else
  echo "NOT ok R6-I3(1)/int guard-viability BLIND: $(cat "$PIN_ERR" 2>/dev/null)"
  failx
fi

echo
echo "=== R6-I3(1)/nondict-null: --proposal top-level value is JSON null ==="
FIXED_ERR="$TMP/ndn.fixed.err"
FIXED_OUT="$TMP/ndn.fixed.json"
python3 "$IMPL" verify-proposal --proposal "$FIXDIR/cs_r6_nondict_null.json" \
  --repo-root "$REPO_ROOT_ARG" --out "$FIXED_OUT" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && grep -q "not a JSON object" "$FIXED_ERR"; then
  echo "ok R6-I3(1)/null real (fixed) tool: verify-proposal fails closed with"
  echo "   EXIT_USAGE (2), no --out written -- $(cat "$FIXED_ERR")"
else
  echo "NOT ok R6-I3(1)/null real (fixed) tool: rc=$FIXED_RC (wanted 2), out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) -- $(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
PIN_ERR="$TMP/ndn.pin.err"
PIN_OUT="$TMP/ndn.pin.json"
run_against_pinned verify-proposal --proposal "$FIXDIR/cs_r6_nondict_null.json" \
  --repo-root "$REPO_ROOT_ARG" --out "$PIN_OUT" >"$PIN_ERR" 2>&1
if [ -f "$PIN_OUT" ]; then
  echo "NOT ok R6-I3(1)/null guard-viability FAILED: pinned pre-R6-fix copy WROTE"
  echo "     an --out document instead of crashing"
  failx
elif grep -q "^Traceback" "$PIN_ERR" 2>/dev/null && grep -qi "is not iterable" "$PIN_ERR" 2>/dev/null; then
  echo "ok R6-I3(1)/null guard-viability: the PINNED pre-R6-fix custody_sweep.py"
  echo "   CRASHED uncaught (Traceback + 'not iterable' TypeError in stderr,"
  echo "   NO --out document written) -- proving this fixture genuinely"
  echo "   catches the R6-I3(1) regression if the fix is ever reverted"
else
  echo "NOT ok R6-I3(1)/null guard-viability BLIND: $(cat "$PIN_ERR" 2>/dev/null)"
  failx
fi

echo
echo "=== R6-I3(2): backup_artifact_path is a JSON list, not a string ==="
FIXED_ERR="$TMP/bap.fixed.err"
FIXED_OUT="$TMP/bap.fixed.json"
python3 "$IMPL" verify-proposal --proposal "$FIXDIR/cs_r6_backup_path_list.json" \
  --repo-root "$REPO_ROOT_ARG" --out "$FIXED_OUT" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && grep -q "must be a JSON string when present" "$FIXED_ERR"; then
  echo "ok R6-I3(2) real (fixed) tool: verify-proposal fails closed with"
  echo "   EXIT_USAGE (2), no --out written, names the real bad field -- $(cat "$FIXED_ERR")"
else
  echo "NOT ok R6-I3(2) real (fixed) tool: rc=$FIXED_RC (wanted 2), out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) -- $(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
PIN_ERR="$TMP/bap.pin.err"
PIN_OUT="$TMP/bap.pin.json"
run_against_pinned verify-proposal --proposal "$FIXDIR/cs_r6_backup_path_list.json" \
  --repo-root "$REPO_ROOT_ARG" --out "$PIN_OUT" >"$PIN_ERR" 2>&1
if [ -f "$PIN_OUT" ]; then
  echo "NOT ok R6-I3(2) guard-viability FAILED: pinned pre-R6-fix copy WROTE an"
  echo "     --out document instead of crashing"
  failx
elif grep -q "^Traceback" "$PIN_ERR" 2>/dev/null && grep -qi "expected str, bytes or os.PathLike" "$PIN_ERR" 2>/dev/null; then
  echo "ok R6-I3(2) guard-viability: the PINNED pre-R6-fix custody_sweep.py"
  echo "   CRASHED uncaught inside derive_verdict's os.path.isabs() call"
  echo "   (Traceback + the real PathLike TypeError in stderr, NO --out"
  echo "   document written) -- proving this fixture genuinely catches the"
  echo "   R6-I3(2) regression if the fix is ever reverted"
else
  echo "NOT ok R6-I3(2) guard-viability BLIND: $(cat "$PIN_ERR" 2>/dev/null)"
  failx
fi

echo
echo "=== R6-I1(b) sibling: non-finite JSON constant (note: NaN) anywhere in --proposal ==="
FIXED_ERR="$TMP/nan.fixed.err"
FIXED_OUT="$TMP/nan.fixed.json"
python3 "$IMPL" verify-proposal --proposal "$FIXDIR/cs_r6_nan_proposal.json" \
  --repo-root "$REPO_ROOT_ARG" --out "$FIXED_OUT" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && grep -qi "not valid JSON" "$FIXED_ERR"; then
  echo "ok R6-I1(b)-sibling real (fixed) tool: verify-proposal refuses at"
  echo "   parse time (rc=2/EXIT_USAGE, no --out written) even though the"
  echo "   proposal is otherwise well-formed and non-destructive -- $(cat "$FIXED_ERR")"
else
  echo "NOT ok R6-I1(b)-sibling real (fixed) tool: rc=$FIXED_RC (wanted 2), out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) -- $(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
PIN_ERR="$TMP/nan.pin.err"
PIN_OUT="$TMP/nan.pin.json"
run_against_pinned verify-proposal --proposal "$FIXDIR/cs_r6_nan_proposal.json" \
  --repo-root "$REPO_ROOT_ARG" --out "$PIN_OUT" >"$PIN_ERR" 2>&1
PIN_RC=$?
if [ "$PIN_RC" = "0" ] && [ -f "$PIN_OUT" ]; then
  echo "ok R6-I1(b)-sibling guard-viability: the PINNED pre-R6-fix"
  echo "   custody_sweep.py silently ACCEPTS the NaN-bearing --proposal (rc=0,"
  echo "   real --out written, verdict=ALLOWED) -- proving this fixture"
  echo "   genuinely catches the parse-time non-finite-constant regression if"
  echo "   the fix is ever reverted"
else
  echo "NOT ok R6-I1(b)-sibling guard-viability BLIND: pinned copy did not"
  echo "     cleanly accept, rc=$PIN_RC, out_exists=$([ -f "$PIN_OUT" ] && echo yes || echo no) -- $(cat "$PIN_ERR" 2>/dev/null)"
  failx
fi

echo
echo "=== R6-I2 sibling: unwritable --out (parent path component is a regular FILE) -- inventory ==="
mkdir -p "$TMP/notadir_parent"
touch "$TMP/notadir_parent/not_a_dir"
FIXED_ERR="$TMP/inv.fixed.err"
python3 "$IMPL" inventory --repo-root "$REPO_ROOT_ARG" --out "$TMP/notadir_parent/not_a_dir/sub.json" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && grep -qi "cannot write --out" "$FIXED_ERR"; then
  echo "ok R6-I2-sibling/inventory real (fixed) tool: fails closed with"
  echo "   EXIT_USAGE (2), never an uncaught crash -- $(cat "$FIXED_ERR")"
else
  echo "NOT ok R6-I2-sibling/inventory real (fixed) tool: rc=$FIXED_RC (wanted 2) -- $(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
PIN_ERR="$TMP/inv.pin.err"
run_against_pinned inventory --repo-root "$REPO_ROOT_ARG" --out "$TMP/notadir_parent/not_a_dir/sub2.json" >"$PIN_ERR" 2>&1
if grep -q "^Traceback" "$PIN_ERR" 2>/dev/null && grep -qi "FileExistsError\|NotADirectoryError" "$PIN_ERR" 2>/dev/null; then
  echo "ok R6-I2-sibling/inventory guard-viability: the PINNED pre-R6-fix"
  echo "   custody_sweep.py CRASHED uncaught on the same unwritable --out"
  echo "   path -- proving this scenario genuinely catches the R6-I2-sibling"
  echo "   regression if the fix is ever reverted"
else
  echo "NOT ok R6-I2-sibling/inventory guard-viability BLIND: $(cat "$PIN_ERR" 2>/dev/null)"
  failx
fi

echo
echo "=== R6-I2 sibling STATIC control needle: ALL THREE write_doc(...) call sites (inventory/propose/verify-proposal) are guarded ==="
# Live-exercising the OSError write-guard for propose/verify-proposal too
# would need a real --inventory document as an upstream input, purely to
# exercise the SAME already-proven try/except shape a third and fourth
# time; instead this asserts, statically, that cmd_propose's and
# cmd_verify_proposal's own write_doc(...) calls are each wrapped in their
# own try/except (never merely cmd_inventory's) -- so a regression that
# strips the guard from one specific subcommand (not all three at once)
# is still caught even though only cmd_inventory is exercised live above.
#
# T140 Round 7 review finding M2 (section 11.4.6, fixed here): this needle
# used to count GUARDED TRY NODES globally across all three target
# functions, not DISTINCT GUARDED FUNCTIONS -- `guarded += 1` fired once
# PER matching Try block found by the inner `ast.walk(node)`, so a
# function with TWO guarded Try blocks (e.g. duplicated/refactored
# defensive code) could push the total to 3 while a DIFFERENT one of the
# three target functions had ZERO guards at all (e.g. 2+1+0 or 2+0+1 both
# sum to 3) -- a genuinely missing guard in one function was masked by a
# double-counted guard in another, a false PASS on a real regression.
# Fixed by tracking the SET of function NAMES that have at least one
# guarded Try (never a raw count), and requiring len() == 3 -- i.e. all
# THREE distinct target functions individually guarded, regardless of how
# many guarded Try blocks any one of them happens to contain.
GUARD_COUNT=$(python3 - "$IMPL" <<'PYEOF'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read(), filename=sys.argv[1])
TARGETS = ("cmd_inventory", "cmd_propose", "cmd_verify_proposal")
guarded_functions = set()
for node in ast.walk(tree):
    if isinstance(node, ast.FunctionDef) and node.name in TARGETS:
        for sub in ast.walk(node):
            if isinstance(sub, ast.Try):
                handled = any(
                    (isinstance(h.type, ast.Name) and h.type.id == "OSError")
                    for h in sub.handlers if h.type is not None
                )
                calls_write_doc = any(
                    isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "write_doc"
                    for n in ast.walk(sub)
                )
                if handled and calls_write_doc:
                    guarded_functions.add(node.name)
                    break  # one guarded Try in this function suffices -- stop scanning it
print(len(guarded_functions))
PYEOF
)
if [ "$GUARD_COUNT" = "3" ]; then
  echo "ok R6-I2-sibling static control needle: all THREE of"
  echo "   cmd_inventory/cmd_propose/cmd_verify_proposal wrap their own"
  echo "   write_doc(...) call in a try/except OSError -- a regression"
  echo "   stripping the guard from any ONE of the three (not just"
  echo "   cmd_inventory, the only one exercised live above) is caught"
else
  echo "NOT ok R6-I2-sibling static control needle FAILED: found $GUARD_COUNT"
  echo "     OSError-guarded write_doc(...) call(s) inside"
  echo "     cmd_inventory/cmd_propose/cmd_verify_proposal (wanted 3)"
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R6 REGRESSION GUARD (custody_sweep.py): ALL CHECKS PASS -- R6-I3(1)'s"
  echo "    non-dict --proposal rejection, R6-I3(2)'s wrong-type"
  echo "    backup_artifact_path rejection, R6-I1(b)'s parse-time non-finite-"
  echo "    constant rejection, and R6-I2's write-guard (live-proven on"
  echo "    inventory, statically proven present on all three subcommands)"
  echo "    are all load-bearing: reverting any one of them makes its own"
  echo "    matching pinned pre-fix copy either crash uncaught or silently"
  echo "    accept a malformed input. ==="
  exit 0
else
  echo "=== R6 REGRESSION GUARD (custody_sweep.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
