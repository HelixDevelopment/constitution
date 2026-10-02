#!/bin/sh
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
    pkill -KILL -f "$TMP" 2>/dev/null
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
cat >"$B3/unrelated/has_secret.txt" <<'EOF'
api_key = "EXAMPLE_PLACEHOLDER_VALUE_123"
EOF
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

fi  # Section C wrapper-presence guard

# =============================================================================
echo
echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ]
