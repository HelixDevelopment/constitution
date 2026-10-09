#!/bin/sh
# shellcheck disable=SC2016 # printf fixtures write literal shell text with dollar signs on purpose
# =============================================================================
# test_precheck_pack_build_red.sh
# =============================================================================
#
# Two guards in one file, both regression-protecting a real, measured
# recurring bottleneck in the SpecKit-004 fast-dev-cycles review pipeline
# (RB-001/RB-002, contracts/review-batch-and-precheck.md), T085/T048/T177's
# own review-round history: the manual "write a config.yaml, hand-construct
# per-change descriptor JSON files with real sha256-verified sibling diffs,
# run slicer.py, create a git worktree, run precheck_pack.sh, interpret an
# `all_pass: false` caused by a whole-checkout-scan limitation, clean up the
# worktree" sequence, repeated by hand on every review round.
#
# Section B -- the ROOT-CAUSE fix regression guard: review/lib/
# precheck_pack_run.py's parse/shellcheck/secret-scan checks used to
# unconditionally walk the ENTIRE --clean-checkout tree, so ANY batch --
# no matter how clean its own changes were -- inherited every pre-existing,
# unrelated repo-wide finding and reported all_pass=false, making
# all_pass=true structurally unachievable on a real multi-thousand-file
# checkout. Fixed to scope these three checks to exactly the files the
# batch's own slices declare changed (review/lib/precheck_pack_run.py's own
# _batch_scoped_files()), falling back to the full checkout ONLY when the
# batch's own data cannot confidently establish a per-file scope (never
# risking a silently under-scanned false PASS). Self-contained fixtures,
# built fresh under $TMP -- never touches the real tree.
#
# Section C -- the WRAPPER (review/precheck_pack_build.sh), which automates
# the ENTIRE manual sequence above from a single git commit/range: real
# disposable commits are created via a SCRATCH WORKTREE of this project's
# own live constitution checkout (git worktree add --detach, never a
# `git checkout` on the shared main working tree -- this project runs under
# heavy concurrent multi-track load, and mutating the shared checkout's own
# HEAD/working-tree files, even briefly, risks a concurrent reader
# observing a torn view; a worktree is fully isolated from that), proving
# the wrapper against REAL git plumbing, not a fabricated/mocked repo.
# Every disposable commit this file creates is UNREACHABLE from any branch
# the moment its scratch worktree is removed (git worktree add --detach
# with no -b) -- eligible for ordinary gc, no residue claimed otherwise.
#
# Producer != Verifier (11.4.240): this file only tests
# review/lib/precheck_pack_run.py's scoping fix and review/
# precheck_pack_build.sh; it does not implement either (both already land
# in the SAME change this file is part of, per house precedent --
# test_precheck_slicer_red.sh's own sibling tools T-C11/T078 relationship).
#
# Exit: 0 all as expected; 1 any FAIL recorded.
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
CONST_ROOT="$FC"
REVIEW_DIR="$FC/review"
PRECHECK="$REVIEW_DIR/precheck_pack.sh"
BUILD_WRAPPER="$REVIEW_DIR/precheck_pack_build.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

TMP=$(mktemp -d) || { echo "cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
WT_CLEANUP_LIST="$TMP/.worktrees_to_remove"
: >"$WT_CLEANUP_LIST"
register_wt() { echo "$1" >>"$WT_CLEANUP_LIST"; }

reap_children() {
    # Direct children of THIS shell only, matched by parent pid (never a
    # command-line pattern: `pkill -f` can match unrelated processes).
    pkill -KILL -P "$$" 2>/dev/null
    return 0
}
cleanup_worktrees() {
    # Remove every scratch worktree this run registered, regardless of
    # whether the run reached its own normal removal call -- never leaves
    # an orphan `git worktree` entry on this project's own live checkout.
    if [ -f "$WT_CLEANUP_LIST" ]; then
        while IFS= read -r _wt; do
            [ -n "$_wt" ] || continue
            git -C "$CONST_ROOT" worktree remove --force "$_wt" >/dev/null 2>&1
            rm -rf "$_wt" 2>/dev/null
        done <"$WT_CLEANUP_LIST"
    fi
}
# Safety net for C2's deliberate chmod-000 window: if this run is
# interrupted precisely between C2's chmod 000 and its own restore, these
# (set only for that window -- see C2 below) restore the REAL, saved
# original mode bits on exit rather than leave either tool unreadable on
# the live tree.
cleanup_modes() {
    [ -n "${_SLICER_MODE:-}" ] && chmod "$_SLICER_MODE" "$REVIEW_DIR/slicer.py" >/dev/null 2>&1
    [ -n "${_PRECHECK_MODE:-}" ] && chmod "$_PRECHECK_MODE" "$PRECHECK" >/dev/null 2>&1
}
trap 'reap_children; cleanup_worktrees; cleanup_modes; rm -rf "$TMP"' EXIT
trap 'reap_children; cleanup_worktrees; cleanup_modes; rm -rf "$TMP"; exit 130' INT
trap 'reap_children; cleanup_worktrees; cleanup_modes; rm -rf "$TMP"; exit 143' TERM

echo "== T085-adjacent RED: precheck_pack_run.py batch-scoping fix + precheck_pack_build.sh wrapper =="

# =============================================================================
# Section A -- control needles.
# =============================================================================
if [ -f "$BUILD_WRAPPER" ]; then
    ok "control needle: $BUILD_WRAPPER exists -- the wrapper has landed;"
    echo "   Section C's real invocation checks below are the functional"
    echo "   tests to run"
else
    bad "control needle FAILED: $BUILD_WRAPPER is absent -- the wrapper has"
    echo "   not landed yet"
fi
if [ -f "$PRECHECK" ]; then
    ok "control needle: $PRECHECK exists (precheck_pack.sh, already landed"
    echo "   pre-T085)"
else
    bad "control needle FAILED: $PRECHECK is absent"
fi

# =============================================================================
# Section B -- the ROOT-CAUSE scoping-fix regression guard: 4 self-contained
# fixtures run directly against the real precheck_pack.sh (never through the
# wrapper, so this guard stays meaningful even if the wrapper is ever
# removed/replaced).
# =============================================================================

# --- B1: a clean declared file + UNRELATED pre-existing noise elsewhere in
# the checkout -- must PASS (the bug this fix closes: this used to FAIL,
# purely from content the batch never touched). ---
B1="$TMP/b1"
mkdir -p "$B1/mychange" "$B1/unrelated"
cat >"$B1/mychange/clean.sh" <<'EOF'
#!/bin/sh
echo "clean and valid"
EOF
# A real, planted SC2086 (unquoted variable) in a file the batch does NOT
# declare -- "pre-existing unrelated repo content" at fixture scale.
cat >"$B1/unrelated/noise.sh" <<'EOF'
#!/bin/sh
X=$1
echo $X
EOF
cat >"$B1/batch.json" <<'EOF'
{
  "batch_id": "RB-SCOPE-B1",
  "changes": ["sha256:0000000000000000000000000000000000000000000000000000000000000b1"],
  "related_by": "logic_group:scope-fixture-b1",
  "total_changed_lines": 1,
  "slices": [
    {
      "slice_id": "S1",
      "lines": 1,
      "context_pack": {
        "intent": "Slice 1/1 of logic_group:scope-fixture-b1: 1 change(s) touching mychange/clean.sh",
        "blast_radius": "1 changed path(s) in this slice: mychange/clean.sh",
        "sibling_search_ref": "UNMEASURED"
      }
    }
  ]
}
EOF
sh "$PRECHECK" --batch "$B1/batch.json" --clean-checkout "$B1" --out "$B1/out.json" \
    >"$TMP/b1.out" 2>"$TMP/b1.err"
B1_RC=$?
B1_ALL_PASS=$(python3 -c "import json,sys
try:
    print(json.load(open('$B1/out.json')).get('all_pass'))
except Exception:
    print('UNREADABLE')" 2>/dev/null)
if [ "$B1_RC" -eq 0 ] && [ "$B1_ALL_PASS" = "True" ]; then
    ok "B1: a batch declaring ONE clean file reports all_pass=true even"
    echo "   though an UNRELATED, undeclared file elsewhere in the checkout"
    echo "   carries a real shellcheck finding -- the whole-checkout-scan"
    echo "   bug is fixed (rc=$B1_RC, all_pass=$B1_ALL_PASS)"
else
    bad "B1: expected rc=0/all_pass=true, got rc=$B1_RC all_pass=$B1_ALL_PASS"
    echo "   ($(cat "$B1/out.json" 2>/dev/null | head -c 500))"
fi

# --- B2: the declared file ITSELF carries a real defect -- must still FAIL,
# proving the fix never suppresses a genuine in-scope finding. ---
B2="$TMP/b2"
mkdir -p "$B2/mychange"
cat >"$B2/mychange/broken.sh" <<'EOF'
#!/bin/sh
if [ "x" = "x" ]; then
  echo "unterminated
EOF
cat >"$B2/batch.json" <<'EOF'
{
  "batch_id": "RB-SCOPE-B2",
  "changes": ["sha256:0000000000000000000000000000000000000000000000000000000000000b2"],
  "related_by": "logic_group:scope-fixture-b2",
  "total_changed_lines": 1,
  "slices": [
    {
      "slice_id": "S1",
      "lines": 1,
      "context_pack": {
        "intent": "Slice 1/1 of logic_group:scope-fixture-b2: 1 change(s) touching mychange/broken.sh",
        "blast_radius": "1 changed path(s) in this slice: mychange/broken.sh",
        "sibling_search_ref": "UNMEASURED"
      }
    }
  ]
}
EOF
sh "$PRECHECK" --batch "$B2/batch.json" --clean-checkout "$B2" --out "$B2/out.json" \
    >"$TMP/b2.out" 2>"$TMP/b2.err"
B2_RC=$?
B2_RESULT=$(python3 -c "import json,sys
try:
    d = json.load(open('$B2/out.json'))
    cites = any(c.get('verdict')=='FAIL' and 'broken.sh' in str(c.get('evidence',''))
                for c in d.get('checks', []))
    print('%s %s' % (d.get('all_pass'), 'YES' if cites else 'NO'))
except Exception as e:
    print('UNREADABLE %s' % e)" 2>/dev/null)
case "$B2_RESULT" in
    "False YES")
        ok "B2: a batch declaring ONE genuinely broken file still reports"
        echo "   all_pass=false citing broken.sh (rc=$B2_RC) -- the scoping"
        echo "   fix never suppresses a real in-scope defect"
        ;;
    *)
        bad "B2: expected 'all_pass=False' citing broken.sh, got '$B2_RESULT'"
        echo "   (rc=$B2_RC)"
        ;;
esac

# --- B3: a secret in an UNRELATED file must not fail; the declared file is
# clean -- extends B1's proof to the secret-scan check specifically. ---
B3="$TMP/b3"
mkdir -p "$B3/mychange" "$B3/unrelated"
cat >"$B3/mychange/clean2.sh" <<'EOF'
#!/bin/sh
echo "clean"
EOF
# Assembled at runtime so this test source itself never carries the literal
# credential-shaped line (the batch-scoped secret-scan lints this file too).
printf '%s_key = "%s"\n' api EXAMPLE_PLACEHOLDER_VALUE_123 >"$B3/unrelated/has_secret.txt"
cat >"$B3/batch.json" <<'EOF'
{
  "batch_id": "RB-SCOPE-B3",
  "changes": ["sha256:0000000000000000000000000000000000000000000000000000000000000b3"],
  "related_by": "logic_group:scope-fixture-b3",
  "total_changed_lines": 1,
  "slices": [
    {
      "slice_id": "S1",
      "lines": 1,
      "context_pack": {
        "intent": "Slice 1/1 of logic_group:scope-fixture-b3: 1 change(s) touching mychange/clean2.sh",
        "blast_radius": "1 changed path(s) in this slice: mychange/clean2.sh",
        "sibling_search_ref": "UNMEASURED"
      }
    }
  ]
}
EOF
sh "$PRECHECK" --batch "$B3/batch.json" --clean-checkout "$B3" --out "$B3/out.json" \
    >"$TMP/b3.out" 2>"$TMP/b3.err"
B3_RC=$?
B3_ALL_PASS=$(python3 -c "import json
try:
    print(json.load(open('$B3/out.json')).get('all_pass'))
except Exception:
    print('UNREADABLE')" 2>/dev/null)
if [ "$B3_RC" -eq 0 ] && [ "$B3_ALL_PASS" = "True" ]; then
    ok "B3: an UNRELATED, undeclared secret elsewhere in the checkout does"
    echo "   not fail a batch declaring only a clean file -- secret-scan is"
    echo "   scoped exactly like parse/shellcheck (rc=$B3_RC)"
else
    bad "B3: expected rc=0/all_pass=true, got rc=$B3_RC all_pass=$B3_ALL_PASS"
fi

# --- B4: free-form (non-canonical, hand-authored) blast_radius -> honest
# full-checkout fallback -- the unrelated noise is STILL caught, proving the
# fix never silently under-scans a batch it cannot confidently attribute
# (the exact shape fixtures/precheck_slicer/case2_lint_in_pack already
# relies on and which this fix must never regress). ---
B4="$TMP/b4"
mkdir -p "$B4/mychange" "$B4/unrelated"
cp "$B1/mychange/clean.sh" "$B4/mychange/clean.sh"
cp "$B1/unrelated/noise.sh" "$B4/unrelated/noise.sh"
cat >"$B4/batch.json" <<'EOF'
{
  "batch_id": "RB-SCOPE-B4",
  "changes": ["sha256:0000000000000000000000000000000000000000000000000000000000000b4"],
  "related_by": "logic_group:scope-fixture-b4",
  "total_changed_lines": 1,
  "slices": [
    {
      "slice_id": "S1",
      "lines": 1,
      "context_pack": {
        "intent": "hand-authored free-form intent, not slicer.py's canonical form",
        "blast_radius": "one toy file; no real callers (fallback fixture)",
        "sibling_search_ref": "UNMEASURED"
      }
    }
  ]
}
EOF
sh "$PRECHECK" --batch "$B4/batch.json" --clean-checkout "$B4" --out "$B4/out.json" \
    >"$TMP/b4.out" 2>"$TMP/b4.err"
B4_RC=$?
B4_SCOPE=$(python3 -c "import json
try:
    d = json.load(open('$B4/out.json'))
    sc = next((c for c in d.get('checks', []) if c.get('check')=='shellcheck'), {})
    print('%s %s' % (d.get('all_pass'), sc.get('evidence', {}).get('scope')))
except Exception as e:
    print('UNREADABLE %s' % e)" 2>/dev/null)
case "$B4_SCOPE" in
    "False whole-checkout")
        ok "B4: a batch whose blast_radius is free-form prose (not"
        echo "   slicer.py's canonical form) falls back to a full-checkout"
        echo "   scan -- still catches the unrelated noise.sh finding"
        echo "   (all_pass=false, shellcheck evidence.scope=whole-checkout)"
        echo "   -- never risks a silently under-scanned false PASS"
        ;;
    *)
        bad "B4: expected 'False whole-checkout', got '$B4_SCOPE' (rc=$B4_RC)"
        ;;
esac

# =============================================================================
# Section C -- review/precheck_pack_build.sh, the one-shot wrapper. Real
# disposable commits are created via a SCRATCH WORKTREE of this project's
# own live constitution checkout, never via `git checkout` on the shared
# main working tree (concurrency-safe under this project's heavy multi-
# track load -- see module docstring).
# =============================================================================
if [ ! -f "$BUILD_WRAPPER" ]; then
    bad "Section C skipped: $BUILD_WRAPPER is absent"
else

make_disposable_commit() {
    # $1 = relative path to write under the scratch worktree; the file's
    # content is read from stdin. Prints the resulting commit sha on
    # stdout. The scratch worktree is removed before this function
    # returns -- the commit becomes UNREACHABLE from any ref the instant
    # that happens (git worktree add --detach, no -b), eligible for
    # ordinary gc.
    _rel="$1"
    _wt="$TMP/mkwt.$$.$(date +%s%N 2>/dev/null || echo 0)"
    git -C "$CONST_ROOT" worktree add --detach --quiet "$_wt" main >"$TMP/mkwt.out" 2>"$TMP/mkwt.err" || {
        echo "FAILED-WORKTREE-ADD" ; return 1
    }
    register_wt "$_wt"
    mkdir -p "$(dirname "$_wt/$_rel")"
    cat >"$_wt/$_rel"
    git -C "$_wt" add "$_rel" >/dev/null 2>&1
    git -C "$_wt" -c user.email="precheck-pack-build-test@local" \
        -c user.name="precheck_pack_build RED test" \
        commit -q -m "scratch(test_precheck_pack_build_red): disposable fixture, never merged/pushed" \
        >/dev/null 2>&1
    _sha=$(git -C "$_wt" rev-parse HEAD 2>/dev/null)
    git -C "$CONST_ROOT" worktree remove --force "$_wt" >/dev/null 2>&1
    rm -rf "$_wt" 2>/dev/null
    echo "$_sha"
}

# --- C1: a clean disposable commit -> rc=0, all_pass=true, real markers. ---
C1_PATH="scripts/fastcycle/tests/precheck_build_scratch_c1_SCRATCH.sh"
C1_SHA=$(printf '#!/bin/sh\necho "clean scratch fixture C1"\n' | make_disposable_commit "$C1_PATH")
if [ -z "$C1_SHA" ] || [ "$C1_SHA" = "FAILED-WORKTREE-ADD" ]; then
    bad "C1 setup FAILED: could not create a disposable commit via a scratch worktree"
else
    ok "C1 setup: real disposable commit $C1_SHA created via a scratch worktree,"
    echo "   never touching the shared main checkout's own HEAD/working tree"
    C1_OUT="$TMP/c1_out"
    sh "$BUILD_WRAPPER" --commit "$C1_SHA" --out-dir "$C1_OUT" >"$TMP/c1.out" 2>"$TMP/c1.err"
    C1_RC=$?
    C1_MARKERS=$(grep -c '^PRECHECK-PACK: \|^BATCH-ID: ' "$TMP/c1.out")
    if [ "$C1_RC" -eq 0 ] && [ "$C1_MARKERS" -eq 2 ] && [ -f "$C1_OUT/precheck.json" ]; then
        C1_SHAPE=$(python3 -c "import json
d = json.load(open('$C1_OUT/precheck.json'))
print('%s %s %s' % (d.get('schema'), d.get('all_pass'),
                     d.get('batch_id') not in (None, '', 'UNKNOWN')))" 2>/dev/null)
        if [ "$C1_SHAPE" = "precheck/v1 True True" ]; then
            ok "C1: the wrapper built a real, schema-valid, all_pass=true pack"
            echo "   for a genuinely clean disposable commit in ONE invocation"
            echo "   (rc=$C1_RC), printing both PRECHECK-PACK: and BATCH-ID:"
            echo "   marker lines with a real, non-fabricated batch_id"
            echo "   ($(grep '^BATCH-ID:' "$TMP/c1.out"))"
        else
            bad "C1: precheck.json shape wrong: '$C1_SHAPE'"
        fi
    else
        bad "C1: expected rc=0 + 2 marker lines + a written precheck.json,"
        echo "   got rc=$C1_RC markers=$C1_MARKERS ($(cat "$TMP/c1.err"))"
    fi

    # --- C6: the wrapper BINDS the pack to the batch BASE/HEAD and runs the
    # the shellcheck check in WHOLE-FILE mode (T048 structural simplification):
    # evidence.mode == whole-file, evidence.binding.base_ref == the commit's
    # own base sha, provenance base_sha/head_sha recorded. ---
    if [ "$C1_RC" -eq 0 ]; then
        C1_BASE=$(git -C "$CONST_ROOT" rev-parse "${C1_SHA}^" 2>/dev/null)
        C6_SHAPE=$(python3 - "$C1_OUT/precheck.json" "$C1_BASE" "$C1_SHA" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
sc = next(c for c in d["checks"] if c["check"] == "shellcheck")
b = sc["evidence"].get("binding", {})
p = d.get("provenance") or {}
print("%s %s %s %s" % (sc["evidence"].get("mode"), b.get("base_ref") == sys.argv[2],
                       sys.argv[2] in (p.get("base_sha") or []), p.get("head_sha") == sys.argv[3]))
PY
)
        if [ "$C6_SHAPE" = "whole-file True True True" ]; then
            ok "C6: the wrapper ran shellcheck in whole-file mode bound to the commit's real BASE sha ($C1_BASE) and recorded base_sha/head_sha provenance"
        else
            bad "C6: wrapper did not bind the pack to the batch base: '$C6_SHAPE' (want 'whole-file True True True')"
        fi
    fi

    # --- C2: idempotency -- with slicer.py/precheck_pack.sh made
    # UNUSABLE, a second invocation for the SAME commit still succeeds,
    # proving it genuinely reused the cache rather than rebuilding, and
    # is measurably fast (real wall-clock comparison, not assumed). ---
    if [ "$C1_RC" -eq 0 ]; then
        SLICER_PY="$REVIEW_DIR/slicer.py"
        # Save the REAL, current mode bits before mutating them -- restored
        # EXACTLY afterward (never a hardcoded guess such as 755, which
        # would wrongly leave slicer.py's own tracked 644 mode flipped to
        # executable, a real side effect a prior draft of this test left
        # behind on the live tree and which this comment documents fixing).
        _SLICER_MODE=$(stat -c '%a' "$SLICER_PY" 2>/dev/null || stat -f '%OLp' "$SLICER_PY" 2>/dev/null)
        _PRECHECK_MODE=$(stat -c '%a' "$PRECHECK" 2>/dev/null || stat -f '%OLp' "$PRECHECK" 2>/dev/null)
        chmod 000 "$SLICER_PY" "$PRECHECK" 2>/dev/null
        C2_START=$(date +%s%N 2>/dev/null || echo 0)
        sh "$BUILD_WRAPPER" --commit "$C1_SHA" --out-dir "$C1_OUT" >"$TMP/c2.out" 2>"$TMP/c2.err"
        C2_RC=$?
        C2_END=$(date +%s%N 2>/dev/null || echo 0)
        [ -n "$_SLICER_MODE" ] && chmod "$_SLICER_MODE" "$SLICER_PY" >/dev/null 2>&1
        [ -n "$_PRECHECK_MODE" ] && chmod "$_PRECHECK_MODE" "$PRECHECK" >/dev/null 2>&1
        C2_MS=$(( (C2_END - C2_START) / 1000000 ))
        C2_MARKERS=$(grep -c '^PRECHECK-PACK: \|^BATCH-ID: ' "$TMP/c2.out")
        if [ "$C2_RC" -eq 0 ] && [ "$C2_MARKERS" -eq 2 ]; then
            ok "C2: with slicer.py AND precheck_pack.sh made genuinely"
            echo "   unreadable/unexecutable (chmod 000), a SECOND invocation"
            echo "   for the SAME commit still succeeds (rc=$C2_RC) in"
            echo "   ${C2_MS}ms -- proving it reused the cached pack and"
            echo "   never touched either tool, never rebuilt"
        else
            bad "C2: second (cache-hit) invocation failed with slicer.py/"
            echo "   precheck_pack.sh deliberately unusable (rc=$C2_RC,"
            echo "   markers=$C2_MARKERS, stderr='$(cat "$TMP/c2.err")') --"
            echo "   either caching is broken, or it silently fell through"
            echo "   to a real rebuild that needed the now-unusable tools"
        fi
    else
        bad "C2 skipped: C1 did not succeed, cannot test idempotency on it"
    fi
fi

# --- C3: a disposable commit with a REAL planted defect -> rc=1,
# all_pass=false, citing the defect by name (never silently swallowed by
# the wrapper, matching precheck_pack.sh's own RB-002 contract). ---
C3_PATH="scripts/fastcycle/tests/precheck_build_scratch_c3_SCRATCH.sh"
C3_SHA=$(printf '#!/bin/sh\necho "deliberately broken scratch fixture C3\n' | make_disposable_commit "$C3_PATH")
if [ -z "$C3_SHA" ] || [ "$C3_SHA" = "FAILED-WORKTREE-ADD" ]; then
    bad "C3 setup FAILED: could not create a disposable defect commit"
else
    C3_OUT="$TMP/c3_out"
    sh "$BUILD_WRAPPER" --commit "$C3_SHA" --out-dir "$C3_OUT" >"$TMP/c3.out" 2>"$TMP/c3.err"
    C3_RC=$?
    C3_CITES=$(python3 -c "import json
try:
    d = json.load(open('$C3_OUT/precheck.json'))
    print('%s %s' % (d.get('all_pass'),
          any('precheck_build_scratch_c3' in str(c.get('evidence',''))
              for c in d.get('checks', []) if c.get('verdict')=='FAIL')))
except Exception as e:
    print('UNREADABLE %s' % e)" 2>/dev/null)
    if [ "$C3_RC" -eq 1 ] && [ "$C3_CITES" = "False True" ]; then
        ok "C3: a disposable commit with a real planted parse defect makes"
        echo "   the wrapper exit 1 (not 0, not a crash) with a written,"
        echo "   schema-valid precheck.json citing the real defect file by"
        echo "   name -- the failure genuinely returns to the producer"
        echo "   (RB-002), never silently swallowed"
    else
        bad "C3: expected rc=1 + all_pass=false citing the defect, got"
        echo "   rc=$C3_RC shape='$C3_CITES' ($(cat "$TMP/c3.err"))"
    fi

    # --- C5: the SAME defect commit addressed via two-dot RANGE syntax
    # (--commit <parent>..<head>) -- proves the range form is genuinely
    # parsed and produces the same real result as single-commit mode. ---
    if git -C "$CONST_ROOT" rev-parse --verify "${C3_SHA}^" >/dev/null 2>&1; then
        C3_PARENT=$(git -C "$CONST_ROOT" rev-parse "${C3_SHA}^")
        C5_OUT="$TMP/c5_out"
        sh "$BUILD_WRAPPER" --commit "${C3_PARENT}..${C3_SHA}" --out-dir "$C5_OUT" \
            >"$TMP/c5.out" 2>"$TMP/c5.err"
        C5_RC=$?
        if [ "$C5_RC" -eq 1 ] && [ -f "$C5_OUT/precheck.json" ]; then
            ok "C5: the SAME defect, addressed via two-dot range syntax"
            echo "   (--commit <parent>..<head>), also exits 1 with a real,"
            echo "   written precheck.json -- range parsing genuinely works"
        else
            bad "C5: range-syntax invocation expected rc=1, got rc=$C5_RC"
            echo "   ($(cat "$TMP/c5.err"))"
        fi
    else
        bad "C5 skipped: could not resolve the defect commit's own parent"
    fi
fi

# --- C4: a missing/unresolvable --commit -> rc=2 (usage error), never a
# crash, never a fabricated pack. ---
sh "$BUILD_WRAPPER" --commit "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" \
    --out-dir "$TMP/c4_out" >"$TMP/c4.out" 2>"$TMP/c4.err"
C4_RC=$?
if [ "$C4_RC" -eq 2 ] && [ ! -f "$TMP/c4_out/precheck.json" ]; then
    ok "C4: an unresolvable --commit refuses with exit 2 and writes no"
    echo "   precheck.json at all -- never a fabricated pack for a commit"
    echo "   that does not exist"
else
    bad "C4: expected rc=2 + no precheck.json, got rc=$C4_RC"
    echo "   ($(cat "$TMP/c4.err"))"
fi


# =============================================================================
# Section D -- structural round 3 (11.4.276(E)) builder regressions:
# F-R2-1 binding, F-R2-2 NUL-safe paths, F-R2-6 mode-only, F-R2-9 cache
# provenance, POLICY 1 directive declarations, uncommitted-work snapshot.
# =============================================================================
BUILD_LIB="$REVIEW_DIR/lib/precheck_pack_build_run.py"

# D1 (F-R2-2): a NON-ASCII file name used to be C-quoted by `git diff
# --name-only` ("\303\251"), dropped as a "deletion", and never linted.
D1_PATH="scripts/fastcycle/tests/precheck_build_scratch_$(printf '\303\251')_SCRATCH.sh"
# The commit ALSO adds a clean ASCII-named file so the batch scope stays
# batch-scoped (a single unparseable path would fall back to a whole-checkout
# scan and catch the finding by accident -- the reviewer's real case was a
# multi-file batch).
D1_SHA=""
D1_WT="$TMP/d1wt"
if git -C "$CONST_ROOT" worktree add --detach --quiet "$D1_WT" main >/dev/null 2>&1; then
    register_wt "$D1_WT"
    cat >"$D1_WT/$D1_PATH" <<'EOF_D1'
#!/bin/sh
rm -rf $1
EOF_D1
    printf '#!/bin/sh\necho "clean d1 companion"\n' >"$D1_WT/scripts/fastcycle/tests/precheck_build_scratch_d1_ascii_SCRATCH.sh"
    git -C "$D1_WT" add -A scripts/fastcycle/tests >/dev/null 2>&1
    git -C "$D1_WT" -c user.email="precheck-pack-build-test@local" -c user.name="precheck_pack_build RED test" \
        commit -q -m "scratch(test_precheck_pack_build_red): non-ASCII name, never merged/pushed" >/dev/null 2>&1
    D1_SHA=$(git -C "$D1_WT" rev-parse HEAD)
fi
if [ -z "$D1_SHA" ] || [ "$D1_SHA" = "FAILED-WORKTREE-ADD" ]; then
    bad "D1 setup FAILED: could not create the non-ASCII disposable commit"
else
    sh "$BUILD_WRAPPER" --commit "$D1_SHA" --out-dir "$TMP/d1_out" >"$TMP/d1.out" 2>"$TMP/d1.err"
    D1_RC=$?
    D1_SHAPE=$(python3 - "$TMP/d1_out/precheck.json" "$D1_PATH" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
sc = next(c for c in d["checks"] if c["check"] == "shellcheck")
print("%s %s" % (sc["verdict"], any(f.get("file") == sys.argv[2] and f.get("rule") == "SC2086"
                                     for f in sc["evidence"].get("findings", []))))
PY
)
    if [ "$D1_RC" -eq 1 ] && [ "$D1_SHAPE" = "FAIL True" ]; then
        ok "D1 (F-R2-2): a new non-ASCII-named script with 'rm -rf \$1' is enumerated NUL-safely and linted => rc=1, the SC2086 cited on the real name"
    else
        bad "D1 (F-R2-2): non-ASCII path escaped linting: rc=$D1_RC shape='$D1_SHAPE' ($(head -c 300 "$TMP/d1.err"))"
    fi
fi

# D2 (F-R2-1 + F1): the builder writes a binding into batch.json and the gate
# verifies it => provenance batch-binding-verified. The disposable commit's file
# is NOT in the live constitution working tree, so the dispatch verifier must
# report the pack STALE (F1) -- and that must be its ONLY reason (every other
# readiness check holds). The READY path is proven in
# scripts/hooks/test_review_dispatch_guard_provenance_red.sh.
if [ -n "${C1_SHA:-}" ] && [ -f "${C1_OUT:-/nonexistent}/precheck.json" ]; then
    D2_SHAPE=$(python3 - "$C1_OUT/batch.json" "$C1_OUT/precheck.json" "$C1_SHA" <<'PY'
import json, sys
b = json.load(open(sys.argv[1])); d = json.load(open(sys.argv[2]))
bd = b.get("binding") or {}
print("%s %s %s" % (bd.get("head_sha") == sys.argv[3], (d.get("provenance") or {}).get("head_sha_source"),
                    bool(bd.get("paths"))))
PY
)
    python3 "$BUILD_LIB" verify --pack "$C1_OUT/precheck.json" >"$TMP/d2.verify" 2>&1
    D2_V=$?
    D2_REASONS=$(grep -c '^NOT-READY:' "$TMP/d2.verify")
    if [ "$D2_SHAPE" = "True batch-binding-verified True" ] && [ "$D2_V" -eq 1 ] && [ "$D2_REASONS" -eq 1 ] \
       && grep -q "diverges from the reviewed head for: $C1_PATH" "$TMP/d2.verify"; then
        ok "D2 (F-R2-1 + F1): the builder binds batch.json to base/head, the gate verifies the binding, and the verifier's ONLY objection is the stale working tree"
    else
        bad "D2 (F-R2-1): binding not produced/verified: shape='$D2_SHAPE' verify_rc=$D2_V ($(head -c 300 "$TMP/d2.verify"))"
    fi

    # D3 (F-R2-9): a cached pack whose gate_version is stale (body_hash recomputed,
    # so it is schema-valid and intact) is NOT reused -- the builder rebuilds.
    python3 - "$C1_OUT/precheck.json" <<'PY'
import hashlib, json, sys
p = sys.argv[1]; d = json.load(open(p))
d["gate_version"] = "0" * 64
body = {k: v for k, v in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
    sh "$BUILD_WRAPPER" --commit "$C1_SHA" --out-dir "$C1_OUT" >"$TMP/d3.out" 2>"$TMP/d3.err"
    D3_RC=$?
    D3_GV=$(python3 -c "import json;print(json.load(open('$C1_OUT/precheck.json')).get('gate_version'))")
    if [ "$D3_RC" -eq 0 ] && [ "$D3_GV" != "0000000000000000000000000000000000000000000000000000000000000000" ] && grep -q "not reusable" "$TMP/d3.err"; then
        ok "D3 (F-R2-9): a schema-valid cached pack produced by a STALE gate_version is rebuilt, never reused"
    else
        bad "D3 (F-R2-9): stale-gate cache reused: rc=$D3_RC gate_version=$D3_GV ($(head -c 300 "$TMP/d3.err"))"
    fi
else
    bad "D2/D3 skipped: C1 produced no pack"
fi

# D4 (whole-file strict): a MODE-ONLY change still touches the file, so it is
# linted whole ("touch a file, own its findings"): a clean script whose mode is
# flipped in the second of two scratch commits builds an all_pass pack with
# files_linted == 1; the same flip on a script with a finding FAILs.
D4_WT="$TMP/d4wt"
if git -C "$CONST_ROOT" worktree add --detach --quiet "$D4_WT" main >/dev/null 2>&1; then
    register_wt "$D4_WT"
    D4_G="scripts/fastcycle/tests/precheck_build_scratch_d4_SCRATCH.sh"
    D4_B="scripts/fastcycle/tests/precheck_build_scratch_d4bad_SCRATCH.sh"
    printf '#!/bin/sh\necho "clean d4"\n' >"$D4_WT/$D4_G"
    printf '#!/bin/sh\nrm -rf $1\n' >"$D4_WT/$D4_B"
    D4C="git -C $D4_WT -c user.email=precheck-pack-build-test@local -c user.name=precheck_pack_build_RED_test -c commit.gpgsign=false"
    $D4C add "$D4_G" "$D4_B" >/dev/null 2>&1
    $D4C commit -q -m "scratch(test_precheck_pack_build_red): d4 base, never merged/pushed" >/dev/null 2>&1
    D4_BASE=$(git -C "$D4_WT" rev-parse HEAD)
    chmod +x "$D4_WT/$D4_G"; $D4C add "$D4_G" >/dev/null 2>&1
    $D4C commit -q -m "scratch: mode-only (clean)" >/dev/null 2>&1
    D4_SHA=$(git -C "$D4_WT" rev-parse HEAD)
    chmod +x "$D4_WT/$D4_B"; $D4C add "$D4_B" >/dev/null 2>&1
    $D4C commit -q -m "scratch: mode-only (finding)" >/dev/null 2>&1
    D4_SHA2=$(git -C "$D4_WT" rev-parse HEAD)
    sh "$BUILD_WRAPPER" --commit "$D4_BASE..$D4_SHA" --out-dir "$TMP/d4_out" >"$TMP/d4.out" 2>"$TMP/d4.err"
    D4_RC=$?
    sh "$BUILD_WRAPPER" --commit "$D4_SHA..$D4_SHA2" --out-dir "$TMP/d4b_out" >"$TMP/d4b.out" 2>"$TMP/d4b.err"
    D4B_RC=$?
    D4_N=$(python3 -c "import json;d=json.load(open('$TMP/d4_out/precheck.json'));sc=[c for c in d['checks'] if c['check']=='shellcheck'][0];print(sc['evidence']['counts']['files_linted'])" 2>&1)
    D4B_F=$(python3 -c "import json;d=json.load(open('$TMP/d4b_out/precheck.json'));sc=[c for c in d['checks'] if c['check']=='shellcheck'][0];print(sorted({f['rule'] for f in sc['evidence'].get('findings',[])}))" 2>&1)
    if [ "$D4_RC" -eq 0 ] && [ "$D4_N" = "1" ] && [ "$D4B_RC" -eq 1 ] && [ "$D4B_F" = "['SC2086']" ]; then
        ok "D4 (whole-file strict): a mode-only change is linted whole -- clean script rc=0 (files_linted=1), script with a finding rc=1 citing SC2086"
    else
        bad "D4 (whole-file strict): mode-only handling wrong: clean rc=$D4_RC files=$D4_N; finding rc=$D4B_RC rules=$D4B_F ($(head -c 300 "$TMP/d4.err"))"
    fi
else
    bad "D4 setup FAILED: could not add a scratch worktree"
fi

# D5 (directive policy D5): a `# shellcheck disable=` passes only with its
# justification on the SAME line; the same directive with the reason on the line
# ABOVE, or with a placeholder reason, FAILs (rc=1).
D5_PATH="scripts/fastcycle/tests/precheck_build_scratch_d5_SCRATCH.sh"
D5_SHA=$(printf '#!/bin/sh\n# shellcheck disable=SC2034 # set for a sourcing caller\nUNUSED_FOR_CALLER=1\n' | make_disposable_commit "$D5_PATH")
D5B_SHA=$(printf '#!/bin/sh\n# set for a sourcing caller\n# shellcheck disable=SC2034\nUNUSED_FOR_CALLER=1\n' | make_disposable_commit "$D5_PATH")
D5C_SHA=$(printf '#!/bin/sh\n# shellcheck disable=SC2034 # noise\nUNUSED_FOR_CALLER=1\n' | make_disposable_commit "$D5_PATH")
if [ -n "$D5_SHA" ] && [ -n "$D5B_SHA" ] && [ -n "$D5C_SHA" ] && [ "$D5_SHA" != "FAILED-WORKTREE-ADD" ]; then
    sh "$BUILD_WRAPPER" --commit "$D5_SHA" --out-dir "$TMP/d5a_out" >"$TMP/d5a.out" 2>"$TMP/d5a.err"; D5A_RC=$?
    sh "$BUILD_WRAPPER" --commit "$D5B_SHA" --out-dir "$TMP/d5b_out" >"$TMP/d5b.out" 2>"$TMP/d5b.err"; D5B_RC=$?
    sh "$BUILD_WRAPPER" --commit "$D5C_SHA" --out-dir "$TMP/d5c_out" >"$TMP/d5c.out" 2>"$TMP/d5c.err"; D5C_RC=$?
    if [ "$D5A_RC" -eq 0 ] && [ "$D5B_RC" -eq 1 ] && [ "$D5C_RC" -eq 1 ]; then
        ok "D5 (directive policy): same-line justification passes (rc=0); reason on the line above (rc=1) and a placeholder reason (rc=1) FAIL"
    else
        bad "D5 (directive policy): same-line=$D5A_RC above=$D5B_RC placeholder=$D5C_RC (want 0 1 1) ($(head -c 300 "$TMP/d5a.err"))"
    fi
else
    bad "D5 setup FAILED: could not create the directive commits"
fi

# D6: uncommitted-work snapshot -- unreferenced commit, deterministic, no ref /
# index / working-tree change (unit-level, on a scratch repo).
D6R="$TMP/d6repo"; mkdir -p "$D6R/pkg"
printf '#!/bin/sh\necho "base"\n' >"$D6R/pkg/a.sh"
( cd "$D6R" && git init -q . && git -c user.name=t -c user.email=t@x -c commit.gpgsign=false add -A && \
  git -c user.name=t -c user.email=t@x -c commit.gpgsign=false commit -q -m base ) >/dev/null 2>&1
printf '#!/bin/sh\necho "edited"\n' >"$D6R/pkg/a.sh"; printf '#!/bin/sh\necho "new"\n' >"$D6R/pkg/b.sh"
printf 'pkg/a.sh\npkg/b.sh\n' >"$TMP/d6.paths"
D6_REFS_BEFORE=$(git -C "$D6R" for-each-ref --format='%(refname) %(objectname)' | sha256sum); D6_ST_BEFORE=$(git -C "$D6R" status --porcelain | sha256sum)
D6_A=$(python3 "$BUILD_LIB" snapshot --repo "$D6R" --paths-file "$TMP/d6.paths" 2>&1); D6_A_RC=$?
D6_B=$(python3 "$BUILD_LIB" snapshot --repo "$D6R" --paths-file "$TMP/d6.paths" 2>&1)
D6_REFS_AFTER=$(git -C "$D6R" for-each-ref --format='%(refname) %(objectname)' | sha256sum); D6_ST_AFTER=$(git -C "$D6R" status --porcelain | sha256sum)
D6_HEAD=$(printf '%s\n' "$D6_A" | sed -n 's/^HEAD_SHA=//p')
D6_SHOW=$(git -C "$D6R" show "$D6_HEAD:pkg/a.sh" 2>/dev/null; git -C "$D6R" show "$D6_HEAD:pkg/b.sh" 2>/dev/null)
if [ "$D6_A_RC" -eq 0 ] && [ "$D6_A" = "$D6_B" ] && [ "$D6_REFS_BEFORE" = "$D6_REFS_AFTER" ] && [ "$D6_ST_BEFORE" = "$D6_ST_AFTER" ] \
   && [ "$D6_SHOW" = "$(printf '#!/bin/sh\necho "edited"\n#!/bin/sh\necho "new"')" ]; then
    ok "D6: snapshot freezes the working-tree bytes into an UNREFERENCED, deterministic commit (same sha twice) with no ref, index or working-tree change"
else
    bad "D6: snapshot wrong: rc=$D6_A_RC a='$D6_A' b='$D6_B' refs_same=$([ "$D6_REFS_BEFORE" = "$D6_REFS_AFTER" ] && echo y) status_same=$([ "$D6_ST_BEFORE" = "$D6_ST_AFTER" ] && echo y)"
fi

# D7 (F2): --repo-root builds a pack for ANOTHER repository with a PARTIAL
# checkout (only the changed paths materialised). The scratch "parent" repo and
# the constitution BOTH carry README.md: the pack must examine the scratch
# README.md (a planted secret there FAILs secret-scan) and never the
# constitution's; a clean variant is dispatch-READY against the scratch repo.
D7R="$TMP/d7parent"; mkdir -p "$D7R/pkg" "$D7R/big"
printf 'parent readme\n' >"$D7R/README.md"; printf '#!/bin/sh\necho "b"\n' >"$D7R/pkg/x.sh"
for i in 1 2 3 4 5 6 7 8; do printf 'unrelated %s\n' "$i" >"$D7R/big/f$i.txt"; done
D7G="git -C $D7R -c user.name=t -c user.email=t@x -c commit.gpgsign=false"
git init -q "$D7R" && $D7G add -A >/dev/null 2>&1 && $D7G commit -q -m base >/dev/null 2>&1
# the planted secret is assembled at run time so this test file itself never carries one
printf 'parent readme\n%s = "%s%s"\n' api_key AKIA ABCDEFGHIJKLMNOP >"$D7R/README.md"; printf '#!/bin/sh\necho "h"\n' >"$D7R/pkg/x.sh"
$D7G commit -q -am secret >/dev/null 2>&1; D7_SECRET=$(git -C "$D7R" rev-parse HEAD)
printf 'parent readme, clean edit\n' >"$D7R/README.md"
$D7G commit -q -am clean >/dev/null 2>&1; D7_CLEAN=$(git -C "$D7R" rev-parse HEAD)
sh "$BUILD_WRAPPER" --repo-root "$D7R" --commit "$D7_SECRET" --out-dir "$TMP/d7a_out" >"$TMP/d7a.out" 2>"$TMP/d7a.err"; D7A_RC=$?
sh "$BUILD_WRAPPER" --repo-root "$D7R" --commit "$D7_CLEAN" --out-dir "$TMP/d7b_out" >"$TMP/d7b.out" 2>"$TMP/d7b.err"; D7B_RC=$?
D7A=$(python3 -c "import json;d=json.load(open('$TMP/d7a_out/precheck.json'));s=[c for c in d['checks'] if c['check']=='secret-scan'][0];print(s['verdict'], sorted({h['file'] for h in s['evidence'].get('hits',[])}), d['provenance']['repo']=='$D7R')" 2>&1)
D7B=$(python3 -c "import json;d=json.load(open('$TMP/d7b_out/precheck.json'));co=d['checkout'];print(d['all_pass'], co['partial'], co['materialised'], co['tracked_at_head'])" 2>&1)
python3 "$BUILD_LIB" verify --pack "$TMP/d7b_out/precheck.json" >"$TMP/d7b.verify" 2>&1; D7V=$?
if [ "$D7A_RC" -eq 1 ] && [ "$D7A" = "FAIL ['README.md'] True" ] && [ "$D7B_RC" -eq 0 ] && [ "$D7B" = "True True 1 10" ] && [ "$D7V" -eq 0 ]; then
    ok "D7 (F2): --repo-root packs another repo with a PARTIAL checkout (1 of 10 tracked paths), examines ITS README.md (secret caught), and the clean pack is READY"
else
    bad "D7 (F2): repo-root pack wrong: secret rc=$D7A_RC '$D7A'; clean rc=$D7B_RC '$D7B' verify=$D7V ($(head -c 300 "$TMP/d7b.err") $(head -c 300 "$TMP/d7b.verify"))"
fi
D7CFG=$(git -C "$D7R" config --list --local | grep -c -i sparse)
if [ "$D7CFG" -eq 0 ]; then ok "D7b (F2): the partial checkout wrote NO sparse-checkout config into the reviewed repo"
else bad "D7b (F2): sparse config leaked into the repo ($D7CFG entries)"; fi

# D8 (F14 + F15 + F5): --snapshot-paths with a NUL-separated list carrying a
# newline/space/leading-dash name; binding kind=snapshot; a fresh
# WORKTREE_SNAPSHOT_MD5.txt whose md5s equal the frozen bytes; READY.
D8R="$TMP/d8repo"; mkdir -p "$D8R"
printf 'r\n' >"$D8R/README.md"
D8G="git -C $D8R -c user.name=t -c user.email=t@x -c commit.gpgsign=false"
git init -q "$D8R" && $D8G add -A >/dev/null 2>&1 && $D8G commit -q -m base >/dev/null 2>&1
D8N1=$(printf 'new\nline.sh'); D8N2='-dash name.sh'
printf '#!/bin/sh\necho "one"\n' >"$D8R/$D8N1"; printf '#!/bin/sh\necho "two"\n' >"$D8R/$D8N2"
printf '%s\0%s\0' "$D8N1" "$D8N2" >"$TMP/d8.paths"
sh "$BUILD_WRAPPER" --repo-root "$D8R" --snapshot-paths "$TMP/d8.paths" --out-dir "$TMP/d8_out" >"$TMP/d8.out" 2>"$TMP/d8.err"; D8_RC=$?
D8K=$(python3 -c "import json;b=json.load(open('$TMP/d8_out/batch.json'));print(b['binding']['kind'], sorted(p['path'] for p in b['binding']['paths'])==sorted(['$D8N2', 'new\nline.sh']))" 2>&1)
D8M=$(python3 - "$TMP/d8_out/WORKTREE_SNAPSHOT_MD5.txt" "$D8R/$D8N1" "$D8R/$D8N2" <<'PY'
import hashlib, sys
txt = open(sys.argv[1], encoding="utf-8").read()
print(all(hashlib.md5(open(p, "rb").read()).hexdigest() in txt for p in sys.argv[2:]), txt.count("UNTRACKED-new"))
PY
)
python3 "$BUILD_LIB" verify --pack "$TMP/d8_out/precheck.json" >"$TMP/d8.verify" 2>&1; D8V=$?
if [ "$D8_RC" -eq 0 ] && [ "$D8K" = "snapshot True" ] && [ "$D8M" = "True 2" ] && [ "$D8V" -eq 0 ]; then
    ok "D8 (F14/F15/F5): a NUL-separated snapshot list (newline + leading-dash names) binds kind=snapshot, writes a fresh md5 manifest of the frozen bytes, and is READY"
else
    bad "D8: rc=$D8_RC kind='$D8K' manifest='$D8M' verify=$D8V ($(head -c 300 "$TMP/d8.err") $(head -c 300 "$TMP/d8.verify"))"
fi
printf '#!/bin/sh\necho "one, edited after the pack"\n' >"$D8R/$D8N1"
python3 "$BUILD_LIB" verify --pack "$TMP/d8_out/precheck.json" >"$TMP/d8b.verify" 2>&1; D8BV=$?
if [ "$D8BV" -eq 1 ] && grep -q "diverges from the reviewed head" "$TMP/d8b.verify"; then
    ok "D8b (F1): editing a snapshotted file after the pack makes the snapshot pack STALE"
else bad "D8b: verify=$D8BV ($(head -c 300 "$TMP/d8b.verify"))"; fi

# D9: the legacy-exception TSV defaults to config/shellcheck_legacy_exceptions.tsv
# at the reviewed head of --repo-root and is applied (pin ratchet) + recorded.
D9R="$TMP/d9repo"; mkdir -p "$D9R/config" "$D9R/pkg"
printf 'pkg/legacy.sh\tgenerated\tATM-9999\tSC2086=2\t2026-10-09\n' >"$D9R/config/shellcheck_legacy_exceptions.tsv"
printf '#!/bin/sh\n# generated by the d9 fixture -- do not edit\necho $1\necho $2\necho "a"\n' >"$D9R/pkg/legacy.sh"
D9G="git -C $D9R -c user.name=t -c user.email=t@x -c commit.gpgsign=false"
git init -q "$D9R" && $D9G add -A >/dev/null 2>&1 && $D9G commit -q -m base >/dev/null 2>&1
printf '#!/bin/sh\n# generated by the d9 fixture -- do not edit\necho $1\necho $2\necho "b"\n' >"$D9R/pkg/legacy.sh"; $D9G commit -q -am ok >/dev/null 2>&1; D9_OK=$(git -C "$D9R" rev-parse HEAD)
printf '#!/bin/sh\n# generated by the d9 fixture -- do not edit\necho $1\necho $2\necho $3\n' >"$D9R/pkg/legacy.sh"; $D9G commit -q -am worse >/dev/null 2>&1; D9_BAD=$(git -C "$D9R" rev-parse HEAD)
sh "$BUILD_WRAPPER" --repo-root "$D9R" --commit "$D9_OK" --out-dir "$TMP/d9a_out" >"$TMP/d9a.out" 2>"$TMP/d9a.err"; D9A_RC=$?
sh "$BUILD_WRAPPER" --repo-root "$D9R" --commit "$D9_BAD" --out-dir "$TMP/d9b_out" >"$TMP/d9b.out" 2>"$TMP/d9b.err"; D9B_RC=$?
D9A=$(python3 -c "import json;d=json.load(open('$TMP/d9a_out/precheck.json'));e=[c for c in d['checks'] if c['check']=='shellcheck'][0]['evidence'];print(e['exceptions_file']['path'].endswith('config/shellcheck_legacy_exceptions.tsv'), e['legacy_exceptions'][0]['verdict'])" 2>&1)
if [ "$D9A_RC" -eq 0 ] && [ "$D9A" = "True PASS" ] && [ "$D9B_RC" -eq 1 ]; then
    ok "D9: the builder picks up config/shellcheck_legacy_exceptions.tsv at the reviewed head; at-pin PASSes (rc=0), a third SC2086 FAILs (rc=1)"
else
    bad "D9: ok rc=$D9A_RC '$D9A'; worse rc=$D9B_RC ($(head -c 300 "$TMP/d9a.err"))"
fi

# D10 (M5): the cache key is the commit range, but a cached pack built with
# OTHER shellcheck budgets is rebuilt, never reused; the same budgets reuse it.
D10R="$TMP/d10repo"; mkdir -p "$D10R/pkg"
D10G="git -C $D10R -c user.name=t -c user.email=t@x -c commit.gpgsign=false"
printf 'readme\n' >"$D10R/README.md"
git init -q "$D10R" && $D10G add -A >/dev/null 2>&1 && $D10G commit -q -m base >/dev/null 2>&1
printf '#!/bin/sh\necho "d10"\n' >"$D10R/pkg/a.sh"; $D10G add -A >/dev/null 2>&1; $D10G commit -q -m head >/dev/null 2>&1
D10_SHA=$(git -C "$D10R" rev-parse HEAD)
sh "$BUILD_WRAPPER" --repo-root "$D10R" --commit "$D10_SHA" --out-dir "$TMP/d10_out" >"$TMP/d10a.out" 2>"$TMP/d10a.err"; D10A=$?
sh "$BUILD_WRAPPER" --repo-root "$D10R" --commit "$D10_SHA" --out-dir "$TMP/d10_out" --shellcheck-timeout 30 >"$TMP/d10b.out" 2>"$TMP/d10b.err"; D10B=$?
D10T=$(python3 -c "import json;d=json.load(open('$TMP/d10_out/precheck.json'));print(float([c for c in d['checks'] if c['check']=='shellcheck'][0]['evidence']['tool']['timeout_s']) == 30.0)" 2>&1)
sh "$BUILD_WRAPPER" --repo-root "$D10R" --commit "$D10_SHA" --out-dir "$TMP/d10_out" --shellcheck-timeout 30 >"$TMP/d10c.out" 2>"$TMP/d10c.err"; D10C=$?
if [ "$D10A" -eq 0 ] && [ "$D10B" -eq 0 ] && [ "$D10C" -eq 0 ] && [ "$D10T" = "True" ] \
   && grep -q "not reusable" "$TMP/d10b.err" && grep -q -- "--shellcheck-timeout" "$TMP/d10b.err" \
   && ! grep -q "not reusable" "$TMP/d10c.err"; then
    ok "D10 (M5): a cached pack built with another --shellcheck-timeout is rebuilt (the new pack records 30 s); the same budget reuses it"
else
    bad "D10 (M5): rc=$D10A/$D10B/$D10C timeout=$D10T ($(head -c 300 "$TMP/d10b.err") || $(head -c 300 "$TMP/d10c.err"))"
fi

# D11 (I1): a bound build accepts only the canonical exceptions path.
sh "$BUILD_WRAPPER" --repo-root "$D10R" --commit "$D10_SHA" --out-dir "$TMP/d11_out" --shellcheck-exceptions ../lax.tsv >"$TMP/d11.out" 2>"$TMP/d11.err"; D11=$?
if [ "$D11" -eq 2 ] && grep -q "canonical" "$TMP/d11.err" && [ ! -f "$TMP/d11_out/precheck.json" ]; then
    ok "D11 (I1): --shellcheck-exceptions naming any file but the canonical TSV exits 2 before anything is built"
else
    bad "D11: rc=$D11 ($(head -c 300 "$TMP/d11.err"))"
fi

fi  # Section C wrapper-presence guard

# =============================================================================
echo
echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ]
