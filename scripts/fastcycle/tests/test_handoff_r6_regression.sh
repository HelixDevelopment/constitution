#!/bin/bash
# Purpose : T140 Round 6 (batched Opus-xhigh independent review of SpecKit-004
#           "fast-dev-cycles" User Story 5) regression guard for
#           `orchestration/handoff.py` findings R6-I1(a), R6-I1(b), and N1 --
#           the THREE Round 6 sub-findings touching this file, none of which
#           had any dedicated regression-test coverage before this file
#           landed (section 11.4.224 test-first: every one of R6-I1/N1's own
#           source-level fixes already existed uncommitted, but the round's
#           own review verdict had no falsifiable guard proving it).
#
# R6-I1(a) (section 11.4.201(11) artifact-usability, section 11.4.250
# heuristic-tower/primitive-defect): `_merkle_over_dir` walks real
# filesystem entries and opens each one (`content_address` ->
# `open(path, "rb")`) -- a dangling symlink under a real dependency's
# `tree_current/<locator>` (plausible at AOSP-scale on a real checkout, never
# merely a fixture-only concern) raises `FileNotFoundError` (an `OSError`),
# uncaught pre-fix, crashing `cmd_resume_check` with no honest verdict
# written and the caller's stale --out left un-rewritten. Fixed by wrapping
# the `_merkle_over_dir(current_dir)` call in `try/except OSError`, folding
# the filesystem error into the SAME "unverifiable-external-dependency"
# class the "unrecognized dependency kind" branch already uses (section
# 11.4.6, never a new class), with its own distinct filesystem-error detail
# variant.
#
# R6-I1(b) (section 11.4.6, section 11.4.227 reuse-not-reinvention): a
# non-finite JSON constant (`NaN`/`Infinity`/`-Infinity`) anywhere in
# --handoff parsed fine via the stdlib `json.load` (which defaults to
# `allow_nan=True`) but crashed uncaught with a `ValueError` far later, at
# ANY of `cmd_resume_check`'s THREE separate `write_report_atomic(...)` call
# sites (`fc_common.canon`'s own `allow_nan=False`), each of which echoes
# `doc.get("handoff_id")` straight into `body["handoff_id"]` regardless of
# which reasoning path was taken. Fixed at the ONE shared parse-time point
# (`fc_common.strict_loads`, never a per-write-site patch) that closes the
# whole non-finite-JSON-constant class for every caller-supplied blob this
# tool reads.
#
# N1 (section 11.4.201(6) FALSE-NULL): `reverify` (the accumulator behind
# `facts_needing_reverification`) was a `set()` of BARE `affects_verified`
# id values -- Python's `1 == True` and `hash(1) == hash(True)`, so
# `affects_verified: [1, true]` silently deduped `true` away at INSERTION
# time, before the pre-existing `sorted(reverify, key=_typed_id_key)` ever
# ran (a typed SORT key cannot recover a dedup that already happened on the
# UNTYPED bare value). This is the SAME id-type-collision class Round 5's
# R5-I2 already fixed for the effects_performed<->ground_truth_effects.json
# comparison, present here too in a sibling code path that fix did not
# reach. Fixed by storing `_typed_id_key(ref_id)` (never the bare
# `ref_id`) at every `reverify.add(...)` call site, unwrapping back to the
# bare value only in the final `facts_needing_reverification` list
# comprehension.
#
# Three NEW fixtures, one per finding (matching this suite's existing
# `fixtures/resume_revalidate/rr_<scenario>/handoff.json` convention;
# `rr_r6_*` prefix, never colliding with the pre-existing `rr_*` fixtures
# `test_resume_revalidate_red.sh`/`test_handoff_i4_regression.sh` already
# own):
#   rr_r6_dangling_symlink_dep -- a single git-tree external dep whose
#     tree_current/dep_a/ contains ONE dangling symlink (R6-I1(a)).
#   rr_r6_nan_handoff_id -- handoff_id: NaN, otherwise a minimal
#     otherwise-valid record with no external_deps/pending/verified
#     (R6-I1(b)).
#   rr_r6_typed_id_dedup -- one external dep of an UNRECOGNIZED kind (so
#     `affects_verified` is copied into `reverify` with zero filesystem
#     interaction -- isolating this finding from R6-I1(a)'s own fix) whose
#     `affects_verified: [1, true]` exercises the bool/int type collision
#     (N1).
#
# Guard-viability proof (section 11.4.115(F), the canonical section 1.1
# mutation for a landed fix being the fix-commit's own revert): each
# fixture is ALSO run against
# `fixtures/resume_revalidate/_pinned/handoff_pre_r6_fix.py` -- extracted
# ONCE, via `git show HEAD:...`, from this submodule's own HEAD commit
# 80ef88cb47e25274797c4bf4970469c495052a75 (T140 Round 7 review finding M1,
# section 11.4.6 -- CORRECTED here: an earlier revision of this comment
# cited a925a8dabf644f2b075290cce9404da484f4d410 instead. That commit's OWN
# tree for handoff.py IS byte-identical to this one -- `git diff
# 80ef88c:.../handoff.py a925a8d:.../handoff.py` is empty -- but a925a8d
# never itself touched handoff.py's content (it is a LATER, unrelated
# feature commit -- T070-T074 -- that merely happened to land on top of an
# unchanged handoff.py); 80ef88c is the genuine, precise "last commit that
# actually changed handoff.py's content before the Round 6 fix", verified
# independently via `git log -- .../handoff.py` up to the Round 6 fix
# commit's own parent). The entire R6-I1/R6-I2/R6-I3/N1/N2 source-level
# fix existed ONLY as an uncommitted working-tree diff on top of that
# commit before this file's own commit, per this task's own resume brief
# -- proving each
# fixture genuinely reproduces the pre-fix defect if the fix is ever
# reverted. Layout matches `test_handoff_i4_regression.sh`'s own
# `run_against_pinned()` helper EXACTLY (one level deep,
# $TMP/orchestration_scratch/handoff.py sibling of $TMP/lib/fc_common.py,
# fc_common.py copied from the CURRENT fixed lib -- the pinned copy's own
# `_LIB_DIR` resolution is unaffected by any of this round's fc_common.py
# additions, since none of R6-I1(a)/R6-I1(b)/N1 depend on
# SAFE_EXCEPTIONS/is_strict_nonneg_int).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/resume_revalidate"
PINDIR="$FIXDIR/_pinned"
IMPL="$FC/orchestration/handoff.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
PINNED="$PINDIR/handoff_pre_r6_fix.py"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R6 regression guard: control needle -- fixtures + the fixed tool + pinned copy all exist ==="
for p in "$IMPL" "$LIB" "$PINNED" \
         "$FIXDIR/rr_r6_dangling_symlink_dep/handoff.json" \
         "$FIXDIR/rr_r6_nan_handoff_id/handoff.json" \
         "$FIXDIR/rr_r6_typed_id_dedup/handoff.json"; do
  if [ ! -e "$p" ]; then
    echo "NOT ok control needle FAILED: $p not found"
    failx
  fi
done
# `broken_link` is deliberately a DANGLING symlink (see the dedicated check
# below) -- `-e` follows a symlink and checks its TARGET, which for THIS one
# is deliberately absent, so it is checked separately with `-L` (never
# folded into the generic `-e` loop above, which would always false-fail on
# it).
if [ ! -L "$FIXDIR/rr_r6_dangling_symlink_dep/tree_current/dep_a/broken_link" ]; then
  echo "NOT ok control needle FAILED: $FIXDIR/rr_r6_dangling_symlink_dep/tree_current/dep_a/broken_link not found (not even a symlink)"
  failx
fi
if [ "$fail" = 0 ]; then
  echo "ok control needle: implementation + lib + pinned pre-R6-fix copy + all three new fixtures resolve"
fi
if [ ! -L "$FIXDIR/rr_r6_dangling_symlink_dep/tree_current/dep_a/broken_link" ]; then
  echo "NOT ok control needle FAILED: broken_link is not actually a symlink (fixture setup regressed)"
  failx
elif [ -e "$FIXDIR/rr_r6_dangling_symlink_dep/tree_current/dep_a/broken_link" ]; then
  echo "NOT ok control needle FAILED: broken_link's target unexpectedly EXISTS -- fixture is no longer dangling"
  failx
else
  echo "ok control needle: broken_link is a genuinely dangling symlink (is a link, target does not exist)"
fi

run_against_pinned() {
  # $1 = scenario dir under $FIXDIR, $2 = --out path.
  local scen="$1" out="$2"
  mkdir -p "$TMP/orchestration_scratch" "$TMP/lib"
  cp "$PINNED" "$TMP/orchestration_scratch/handoff.py"
  cp "$LIB" "$TMP/lib/fc_common.py"
  cp "$EXLIB" "$TMP/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
  python3 "$TMP/orchestration_scratch/handoff.py" resume-check \
    --handoff "$FIXDIR/$scen/handoff.json" --out "$out" >"$TMP/${scen}.pin.err" 2>&1
}

echo
echo "=== R6-I1(a): dangling symlink under a git-tree external dep's tree_current/ ==="
FIXED_OUT="$TMP/r6d.fixed.json"
python3 "$IMPL" resume-check --handoff "$FIXDIR/rr_r6_dangling_symlink_dep/handoff.json" \
  --out "$FIXED_OUT" >"$TMP/r6d.fixed.err" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" != "1" ] || [ ! -f "$FIXED_OUT" ]; then
  echo "NOT ok R6-I1(a) real (fixed) tool: rc=$FIXED_RC (wanted 1/EXIT_FINDING), out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no)"
  failx
else
  CLS=$(python3 -c "
import json
d = json.load(open('$FIXED_OUT'))
print(','.join(sorted(r['class'] for r in d['unsafe_reasons'])))
")
  # T140 Round 10 independent review finding I2 (docs/CONTINUATION.md
  # ADDENDUM 114) changed the EXPECTED class here, honestly, for a real
  # reason: `_merkle_over_dir` now delegates to the shared, lstat-based
  # `fc_common.merkle_over_dir_lstat` (see that function's own docstring),
  # which hashes a symlink from its OWN link text -- exactly as git
  # hashes a symlink blob -- NEVER by following it. A DANGLING symlink's
  # link text is fully readable via `os.readlink()` whether or not its
  # target exists, so `broken_link` is no longer an `open()` failure at
  # all (the class this fixture was originally built to exercise, R6-I1(a)'s
  # own "fails CLOSED, never a crash" framing) -- it is now a genuinely
  # hashable tree entry, same as git would see it. The fixture's own
  # RECORDED `content_address` was computed under the OLD, following-based
  # scheme (which never reached a hash for this dependency at all, since it
  # crashed first) -- so the freshly, correctly lstat-computed live hash
  # now legitimately DIFFERS from that stale recorded value, correctly
  # reported as `stale-external-dependency` rather than
  # `unverifiable-external-dependency`. This is the intended, honest
  # consequence of I2's fix, not a regression: the dependency is no longer
  # UNVERIFIABLE (this tool CAN now verify it, structurally, without ever
  # opening the dangling target) -- it is VERIFIED to be stale.
  if [ "$CLS" = "stale-external-dependency,unverifiable-ground-truth" ]; then
    echo "ok R6-I1(a) real (fixed) tool: resume-check exits 1, writes a real --out"
    echo "   document, and reports 'stale-external-dependency' for the dangling"
    echo "   symlink -- T140 Round 10's lstat-based tree hasher (I2) now hashes"
    echo "   a dangling symlink from its own link text rather than failing to"
    echo "   open it, so this dependency is VERIFIED stale, never merely"
    echo "   unverifiable (still fails CLOSED, never a crash)"
  else
    echo "NOT ok R6-I1(a) real (fixed) tool: unexpected unsafe_reasons classes: $CLS"
    failx
  fi
fi
run_against_pinned "rr_r6_dangling_symlink_dep" "$TMP/r6d.pin.json"
if [ -f "$TMP/r6d.pin.json" ]; then
  echo "NOT ok R6-I1(a) guard-viability FAILED: the pinned pre-R6-fix copy WROTE an"
  echo "     --out document instead of crashing -- this fixture would not catch a"
  echo "     revert of the R6-I1(a) fix"
  failx
elif grep -q "^Traceback" "$TMP/rr_r6_dangling_symlink_dep.pin.err" 2>/dev/null && \
     grep -q "FileNotFoundError" "$TMP/rr_r6_dangling_symlink_dep.pin.err" 2>/dev/null; then
  echo "ok R6-I1(a) guard-viability: the PINNED pre-R6-fix handoff.py CRASHED"
  echo "   uncaught (Traceback + FileNotFoundError in stderr, NO --out document"
  echo "   written) -- proving this fixture genuinely catches the R6-I1(a)"
  echo "   uncaught-OSError regression if the fix is ever reverted"
else
  echo "NOT ok R6-I1(a) guard-viability BLIND: pinned copy wrote no --out but its"
  echo "     stderr does not show the expected Traceback+FileNotFoundError -- $(cat "$TMP/rr_r6_dangling_symlink_dep.pin.err" 2>/dev/null)"
  failx
fi

echo
echo "=== R6-I1(b): non-finite JSON constant (handoff_id: NaN) in --handoff ==="
FIXED_OUT="$TMP/r6n.fixed.json"
python3 "$IMPL" resume-check --handoff "$FIXDIR/rr_r6_nan_handoff_id/handoff.json" \
  --out "$FIXED_OUT" >"$TMP/r6n.fixed.err" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && grep -qi "nan" "$TMP/r6n.fixed.err"; then
  echo "ok R6-I1(b) real (fixed) tool: resume-check refuses at parse time"
  echo "   (rc=2/EXIT_USAGE, no --out written, stderr names the non-finite"
  echo "   constant) -- $(cat "$TMP/r6n.fixed.err")"
else
  echo "NOT ok R6-I1(b) real (fixed) tool: rc=$FIXED_RC (wanted 2), out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no), stderr=$(cat "$TMP/r6n.fixed.err" 2>/dev/null)"
  failx
fi
run_against_pinned "rr_r6_nan_handoff_id" "$TMP/r6n.pin.json"
if [ -f "$TMP/r6n.pin.json" ]; then
  echo "NOT ok R6-I1(b) guard-viability FAILED: the pinned pre-R6-fix copy WROTE an"
  echo "     --out document instead of crashing -- this fixture would not catch a"
  echo "     revert of the R6-I1(b) fix"
  failx
elif grep -q "^Traceback" "$TMP/rr_r6_nan_handoff_id.pin.err" 2>/dev/null && \
     grep -qi "not JSON compliant: nan" "$TMP/rr_r6_nan_handoff_id.pin.err" 2>/dev/null; then
  echo "ok R6-I1(b) guard-viability: the PINNED pre-R6-fix handoff.py CRASHED"
  echo "   uncaught (Traceback + 'not JSON compliant: nan' ValueError in stderr,"
  echo "   NO --out document written) -- proving this fixture genuinely catches"
  echo "   the R6-I1(b) uncaught-ValueError regression if the fix is ever"
  echo "   reverted"
else
  echo "NOT ok R6-I1(b) guard-viability BLIND: pinned copy wrote no --out but its"
  echo "     stderr does not show the expected Traceback+ValueError -- $(cat "$TMP/rr_r6_nan_handoff_id.pin.err" 2>/dev/null)"
  failx
fi

echo
echo "=== N1: mixed-type affects_verified ids ([1, true]) must NOT collapse in facts_needing_reverification ==="
FIXED_OUT="$TMP/r6t.fixed.json"
python3 "$IMPL" resume-check --handoff "$FIXDIR/rr_r6_typed_id_dedup/handoff.json" \
  --out "$FIXED_OUT" >"$TMP/r6t.fixed.err" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" != "1" ] || [ ! -f "$FIXED_OUT" ]; then
  echo "NOT ok N1 real (fixed) tool: rc=$FIXED_RC (wanted 1), out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no)"
  failx
else
  NFACTS=$(python3 -c "import json; print(len(json.load(open('$FIXED_OUT'))['facts_needing_reverification']))")
  if [ "$NFACTS" = "2" ]; then
    echo "ok N1 real (fixed) tool: facts_needing_reverification carries BOTH"
    echo "   the int 1 AND the bool true as two DISTINCT entries (len=2) --"
    echo "   the typed-key fix stops them from colliding in the reverify set"
  else
    echo "NOT ok N1 real (fixed) tool: facts_needing_reverification has len=$NFACTS (wanted 2) -- $(cat "$FIXED_OUT" 2>/dev/null)"
    failx
  fi
fi
run_against_pinned "rr_r6_typed_id_dedup" "$TMP/r6t.pin.json"
if [ ! -f "$TMP/r6t.pin.json" ]; then
  echo "NOT ok N1 guard-viability BLIND: the pinned pre-R6-fix copy wrote no --out"
  echo "     at all (wanted a real, GEOMETRICALLY-COLLAPSED document, not a"
  echo "     crash) -- $(cat "$TMP/rr_r6_typed_id_dedup.pin.err" 2>/dev/null)"
  failx
else
  PIN_NFACTS=$(python3 -c "import json; print(len(json.load(open('$TMP/r6t.pin.json'))['facts_needing_reverification']))")
  if [ "$PIN_NFACTS" = "1" ]; then
    echo "ok N1 guard-viability: the PINNED pre-R6-fix handoff.py's"
    echo "   facts_needing_reverification silently COLLAPSES the int 1 and the"
    echo "   bool true into a single entry (len=1) -- proving this fixture"
    echo "   genuinely catches the N1 silent-dedup regression if the fix is"
    echo "   ever reverted"
  else
    echo "NOT ok N1 guard-viability BLIND: pinned copy's facts_needing_reverification"
    echo "     has len=$PIN_NFACTS (wanted the pre-fix collapse, 1) -- the pinned copy"
    echo "     may not genuinely be pre-N1-fix"
    failx
  fi
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R6 REGRESSION GUARD (handoff.py): ALL CHECKS PASS -- R6-I1(a)'s"
  echo "    fail-closed OSError handling, R6-I1(b)'s parse-time non-finite-"
  echo "    constant rejection, and N1's typed-id dedup fix are all load-"
  echo "    bearing: reverting any one of them makes its own matching pinned"
  echo "    pre-fix copy either crash uncaught or silently produce a"
  echo "    collapsed/wrong verdict. ==="
  exit 0
else
  echo "=== R6 REGRESSION GUARD (handoff.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
