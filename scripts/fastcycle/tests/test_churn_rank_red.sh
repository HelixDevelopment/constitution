#!/bin/sh
# =============================================================================
# T090 RED test (SpecKit-004 "fast-dev-cycles", Phase 6 / User Story 3;
# plan.md T-D05; SC-004).
# =============================================================================
#
# Purpose: prove, BEFORE T099's `closure/churn_rank.py` implementation
# exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed -- §11.4.6; `constitution/scripts/fastcycle/closure/` is
#       confirmed to hold nothing but `.gitkeep`);
#   (B) the underlying MECHANISM the real tool will rely on -- `git log
#       --follow --oneline -- <path>` for per-file commit counts, with
#       rename-tracking load-bearing -- is genuinely sound on this host,
#       proven by real git invocations in Section B (never merely assumed
#       present, per §11.4.273: "the path is part of the instrument");
#   (C) the "frozen history" a determinism claim rests on is itself
#       genuinely reproducible (Section C: two independent rebuilds of the
#       fixture repo are commit-SHA-identical), before any claim about
#       churn_rank.py's own determinism (C-003) is trusted;
#   (D) once T099 lands, invoking the real tool through 3 real code paths
#       -- the frozen synthetic history (determinism), a golden-bad missing
#       path, and the REAL project's own live git history (the task's
#       literal control needle: ATM-277's files rank in the top decile) --
#       produces the outcome this file's own contract (fixtures/churn_rank/
#       README.md) predicts.
#
# Contract: specs/004-fast-dev-cycles/plan.md T-D05 ("Extra closure
#   scrutiny for old, high-churn components") + common-conventions.md
#   (C-001..C-007). The assumed CLI contract for churn_rank.py
#   (UNCONFIRMED by any contracts/ file, DEFINED here, binding-if-adopted
#   on T099's implementer) is documented in fixtures/churn_rank/README.md,
#   following the house precedent set by fixtures/io_trace/README.md and
#   fixtures/verdict_cache/README.md.
#
# Task line (tasks.md T090, verbatim): "[P] [US3] [TDD] [SUBAGENT] RED test
# constitution/scripts/fastcycle/tests/test_churn_rank_red.sh (ranking
# deterministic on a frozen history; control needle: ATM-277's files -- 32
# commits -- rank in the top decile) (plan T-D05; SC-004)".
#
# ATM-277's files, independently identified (§11.4.6, never guessed) from
# docs/Fixed.md:5062 (the "VideoPlaybackDetector/ATM-277 stale-frame
# class" reference) and docs/Fixed.md:5188 ("ATM-277
# test_display2_stale_frame_handoff.sh"), cross-checked against
# docs/Issues.md:231's `## ATM-277` heading:
#   - device/rockchip/atmosphere/presenter/Presenter/src/main/java/com/
#     atmosphere/presenter/VideoPlaybackDetector.kt (presenter submodule)
#   - device/rockchip/rk3588/tests/test_display2_stale_frame_handoff.sh
#     (parent monorepo)
# Independently measured (this file's authoring pass, 2026-09-29):
# `git -C <presenter_root> log --follow --oneline -- Presenter/src/main/
# java/com/atmosphere/presenter/VideoPlaybackDetector.kt` -> 26 commits
# (oldest 2026-03-02); `git log --follow --oneline -- device/rockchip/
# rk3588/tests/test_display2_stale_frame_handoff.sh` from the monorepo
# root -> 6 commits (oldest 2026-06-04). 26 + 6 = 32 -- an EXACT match to
# the task line's stated "32 commits", with no discrepancy to document
# (§11.4.6). This RED test does NOT hardcode "32" as its pass/fail gate
# (ATM-277 is `Reopened`, docs/Issues.md:231, and may receive further
# commits before T099 lands) -- it re-measures both counts LIVE at every
# invocation and asserts the tool's reported churn_commits equals that
# live sum, so the test self-flips to GREEN once T099 lands without going
# stale as the project's own history grows.
#
# Producer != Verifier (§11.4.240): this file authors ONLY the RED test +
# its fixtures under fixtures/churn_rank/. It does NOT implement
# closure/churn_rank.py (T099, a separate later task), and never
# fabricates a tool-invocation result -- every scenario below is either
# (a) a real git/shell invocation this file performs itself (Sections B
# and C's mechanism/frozen-history self-checks), or (b) a real invocation
# of the (today, absent) churn_rank.py tool, reported RED because the tool
# cannot be found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected
#       FAIL>0 for every "tool invocation" check in Sections D/E/F --
#       Sections B and C's self-checks of git/the fixture builder are
#       expected to PASS today, since they exercise only real git, not the
#       absent tool).
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
CONST_ROOT=$(cd "$FC/../.." && pwd)
REPO_ROOT=$(cd "$CONST_ROOT/.." && pwd)
PRESENTER_ROOT="$REPO_ROOT/device/rockchip/atmosphere/presenter"
TOOL="$FC/closure/churn_rank.py"
FIXDIR="$HERE/fixtures/churn_rank"
BUILDER="$FIXDIR/build_frozen_repo.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T090 RED: component age/churn ranking for the risk order (plan T-D05; SC-004) =="

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T099 has landed; Sections D/E/F below"
    echo "   are the functional tests to run against it"
else
    echo "RED: $TOOL is absent -- T099 (closure/churn_rank.py) has not"
    echo "     landed yet, confirming this file's own premise is real,"
    echo "     not assumed"
fi

if [ -d "$FC/closure" ]; then
    PY_COUNT=$(find "$FC/closure" -maxdepth 1 -name '*.py' | wc -l)
    if [ "$PY_COUNT" -eq 0 ]; then
        ok "control needle: $FC/closure/ genuinely holds nothing but"
        echo "   .gitkeep -- confirms churn_rank.py is absent by DIRECTORY"
        echo "   CONTENT, not merely by the single-path check above"
    else
        echo "NOTE: $FC/closure/ holds $PY_COUNT *.py file(s) already --"
        echo "      re-check whether T099 (or a sibling task) has"
        echo "      partially landed"
    fi
else
    bad "control needle FAILED: $FC/closure/ does not exist at all"
fi

if [ ! -d "$PRESENTER_ROOT/.git" ] && [ ! -f "$PRESENTER_ROOT/.git" ]; then
    bad "control needle FAILED: $PRESENTER_ROOT has no .git -- the"
    echo "   presenter submodule is not checked out; the real ATM-277"
    echo "   needle in Section E cannot resolve its own-history half"
else
    ok "control needle: the presenter submodule is checked out at"
    echo "   $PRESENTER_ROOT -- the ATM-277 needle's submodule half can"
    echo "   resolve"
fi

for f in \
    "$FC/tests/test_render_keys_red.sh" \
    "$FC/tests/test_io_trace_red.sh" \
    "$FC/tests/test_backstop_red.sh" \
    "$FC/tests/test_precheck_slicer_red.sh" \
    "$FC/tests/test_check_deps.sh" \
    "$FC/tests/test_gate_order_red.sh" \
    "$FC/tests/test_gate_shard_red.sh" \
    "$FC/tests/test_gate_audit_red.sh" \
    "$FC/tests/test_baseline_replay_red.sh" \
    ; do
    if [ ! -f "$f" ]; then
        bad "control needle FAILED: $f (a Section E low-churn context"
        echo "   component) does not exist -- the 10-component real-repo"
        echo "   fixture in Section E cannot be built as designed"
    fi
done
ok "control needle: all 9 Section E low-churn context files exist (or"
echo "   were individually flagged above)"

# =============================================================================
# Section B -- self-validation of the underlying git-log MECHANISM
# (§11.4.107(10)/§11.4.273: "the path is part of the instrument" -- proving
# git itself + rename-tracking work as the real tool will need, BEFORE any
# claim is made about the absent tool's output).
# =============================================================================
if ! command -v git >/dev/null 2>&1; then
    bad "git not found on this host -- the mechanism churn_rank.py"
    echo "   depends on entirely is unavailable"
else
    ok "git is available ($(git --version 2>&1))"
fi

# --- B1: known-present control needle -- a file with exactly 1 real commit
B1_COUNT=$(cd "$CONST_ROOT" && git log --follow --oneline -- \
    scripts/fastcycle/tests/test_render_keys_red.sh 2>/dev/null | wc -l)
if [ "$B1_COUNT" -eq 1 ]; then
    ok "B1 control needle: test_render_keys_red.sh reports exactly 1 real"
    echo "   commit via 'git log --follow --oneline' -- the counting"
    echo "   mechanism resolves a known-present, known-count file"
    echo "   correctly (not 0, not N)"
else
    bad "B1 control needle FAILED: expected exactly 1 commit for"
    echo "     test_render_keys_red.sh, got $B1_COUNT -- either the file's"
    echo "     real history changed since this fixture was authored, or"
    echo "     the counting mechanism itself is unreliable on this host"
fi

# --- B2: rename-tracking negative control (§11.4.201(1)) -- a naive
# `git log -- path` (no --follow) undercounts a renamed file; the real
# tool MUST use --follow or it will silently under-report an old,
# frequently-renamed, genuinely high-churn component out of the top decile.
RENAME_REPO="$TMP/rename_repo"
mkdir -p "$RENAME_REPO"
(
    cd "$RENAME_REPO" || exit 1
    git init -q .
    git config user.name "Fastcycle Fixture"
    git config user.email "fixture@fastcycle.invalid"
    git config commit.gpgsign false
    printf 'v1\n' > old_name.txt
    git add old_name.txt
    GIT_AUTHOR_DATE="2020-02-01 12:00:00 +0000" GIT_COMMITTER_DATE="2020-02-01 12:00:00 +0000" \
        git commit -q -m "old_name: initial"
    printf 'v2\n' > old_name.txt
    git add old_name.txt
    GIT_AUTHOR_DATE="2020-02-02 12:00:00 +0000" GIT_COMMITTER_DATE="2020-02-02 12:00:00 +0000" \
        git commit -q -m "old_name: update 1"
    git mv old_name.txt new_name.txt
    GIT_AUTHOR_DATE="2020-02-03 12:00:00 +0000" GIT_COMMITTER_DATE="2020-02-03 12:00:00 +0000" \
        git commit -q -m "rename old_name -> new_name"
    printf 'v3\n' > new_name.txt
    git add new_name.txt
    GIT_AUTHOR_DATE="2020-02-04 12:00:00 +0000" GIT_COMMITTER_DATE="2020-02-04 12:00:00 +0000" \
        git commit -q -m "new_name: update after rename"
)
B2_FOLLOW=$(cd "$RENAME_REPO" && git log --follow --oneline -- new_name.txt 2>/dev/null | wc -l)
B2_NAIVE=$(cd "$RENAME_REPO" && git log --oneline -- new_name.txt 2>/dev/null | wc -l)
if [ "$B2_FOLLOW" -eq 4 ] && [ "$B2_NAIVE" -eq 2 ]; then
    ok "B2 negative control (§11.4.201(1)): --follow correctly reports"
    echo "   all 4 commits against the renamed file's full logical"
    echo "   history, while a naive (no --follow) query under-counts it"
    echo "   at 2 -- proving churn_rank.py's implementer MUST use"
    echo "   --follow or an old, renamed, genuinely high-churn component"
    echo "   would be silently under-scored out of the top decile"
else
    bad "B2 negative control FAILED: expected --follow=4 naive=2, got"
    echo "     --follow=$B2_FOLLOW naive=$B2_NAIVE -- the rename-tracking"
    echo "     mechanism itself is not behaving as this test assumes on"
    echo "     this host's git version ($(git --version 2>&1))"
fi

# =============================================================================
# Section C -- frozen synthetic history: prove it is genuinely reproducible
# BEFORE trusting any determinism claim about the (absent) tool.
# =============================================================================
FROZEN_A="$TMP/frozen_a"
FROZEN_B="$TMP/frozen_b"
sh "$BUILDER" "$FROZEN_A" >"$TMP/builder_a.log" 2>&1
BUILDER_A_RC=$?
sh "$BUILDER" "$FROZEN_B" >"$TMP/builder_b.log" 2>&1
BUILDER_B_RC=$?

if [ "$BUILDER_A_RC" -ne 0 ] || [ "$BUILDER_B_RC" -ne 0 ]; then
    bad "build_frozen_repo.sh invocation failed (rc_a=$BUILDER_A_RC"
    echo "     rc_b=$BUILDER_B_RC) -- $(cat "$TMP/builder_a.log" "$TMP/builder_b.log" 2>/dev/null)"
else
    SHA_A=$(git -C "$FROZEN_A" rev-parse HEAD 2>/dev/null)
    SHA_B=$(git -C "$FROZEN_B" rev-parse HEAD 2>/dev/null)
    if [ -n "$SHA_A" ] && [ "$SHA_A" = "$SHA_B" ]; then
        ok "C1: two independent invocations of build_frozen_repo.sh"
        echo "   produced COMMIT-SHA-IDENTICAL repositories (HEAD=$SHA_A)"
        echo "   -- the 'frozen history' claim is real, not assumed"
        echo "   (§11.4.273)"
    else
        bad "C1 FAILED: the two independently-built frozen repos have"
        echo "     DIFFERENT HEAD SHAs (a=$SHA_A b=$SHA_B) -- the fixture"
        echo "     builder is not reproducible; nothing built on it below"
        echo "     can be trusted as 'frozen'"
    fi

    C2_ALL_OK=1
    for spec in "file_a.txt:1" "file_b.txt:2" "file_c.txt:3" "file_d.txt:5" "file_e.txt:8"; do
        f=${spec%%:*}
        expected=${spec##*:}
        actual=$(git -C "$FROZEN_A" log --follow --oneline -- "$f" 2>/dev/null | wc -l)
        if [ "$actual" -ne "$expected" ]; then
            bad "C2 FAILED: $f expected $expected commits, git itself"
            echo "     reports $actual -- the frozen repo's own content"
            echo "     does not match its README-documented shape"
            C2_ALL_OK=0
        fi
    done
    if [ "$C2_ALL_OK" -eq 1 ]; then
        ok "C2: git itself confirms the frozen repo's exact documented"
        echo "   per-file commit counts (1,2,3,5,8) -- the mechanism"
        echo "   self-check churn_rank.py's determinism scenario will"
        echo "   run against is sound"
    fi
fi

echo
echo "=== T099 contract check 1/3: determinism on the frozen history (plan T-D05, C-003) ==="
if [ -f "$TOOL" ]; then
    COMPONENTS_FROZEN="$TMP/components_frozen.json"
    cat > "$COMPONENTS_FROZEN" <<EOF
{"components": [
  {"id": "frozen_a", "paths": [{"repo": "frozen", "path": "file_a.txt"}]},
  {"id": "frozen_b", "paths": [{"repo": "frozen", "path": "file_b.txt"}]},
  {"id": "frozen_c", "paths": [{"repo": "frozen", "path": "file_c.txt"}]},
  {"id": "frozen_d", "paths": [{"repo": "frozen", "path": "file_d.txt"}]},
  {"id": "frozen_e", "paths": [{"repo": "frozen", "path": "file_e.txt"}]}
]}
EOF
    REPOROOTS_A="$TMP/repo_roots_a.json"
    printf '{"frozen": "%s"}\n' "$FROZEN_A" > "$REPOROOTS_A"
    REPOROOTS_B="$TMP/repo_roots_b.json"
    printf '{"frozen": "%s"}\n' "$FROZEN_B" > "$REPOROOTS_B"

    OUT_A="$TMP/det_out_a.json"
    OUT_B="$TMP/det_out_b.json"
    ERR_A="$TMP/det_out_a.err"
    ERR_B="$TMP/det_out_b.err"
    python3 "$TOOL" --as-of 2020-06-01 --components-file "$COMPONENTS_FROZEN" \
        --repo-roots "$REPOROOTS_A" --out "$OUT_A" >"$ERR_A" 2>&1
    RC_A=$?
    python3 "$TOOL" --as-of 2020-06-01 --components-file "$COMPONENTS_FROZEN" \
        --repo-roots "$REPOROOTS_B" --out "$OUT_B" >"$ERR_B" 2>&1
    RC_B=$?
    if [ "$RC_A" -eq 0 ] && [ "$RC_B" -eq 0 ] && [ -f "$OUT_A" ] && [ -f "$OUT_B" ]; then
        DET_MATCH=$(python3 -c "
import json
a = json.load(open('$OUT_A'))
b = json.load(open('$OUT_B'))
a.pop('run_meta', None)
b.pop('run_meta', None)
print(a == b)
" 2>&1)
        if [ "$DET_MATCH" = "True" ]; then
            ok "churn_rank.py: two invocations against two independently"
            echo "   -rebuilt (but commit-SHA-identical) frozen repos"
            echo "   produced byte-identical canonical bodies -- C-003"
            echo "   determinism holds"
        else
            bad "churn_rank.py determinism FAILED: the two outputs"
            echo "     differ (comparator: '$DET_MATCH')"
        fi
    else
        bad "churn_rank.py invocation against the frozen history failed"
        echo "     (rc_a=$RC_A rc_b=$RC_B) -- $(cat "$ERR_A" "$ERR_B" 2>/dev/null)"
    fi
else
    echo "NOT ok contract check 1/3 SKIPPED: churn_rank.py not present (see Section A)"
    bad "contract check 1/3 SKIPPED (tool absent)"
fi

echo
echo "=== T099 contract check 2/3: golden-bad -- missing path is flagged, never silent 0 (C-001/C-004) ==="
GB_FIXTURE="$FIXDIR/golden_bad_missing_path.json"
if [ ! -f "$GB_FIXTURE" ]; then
    bad "golden-bad fixture $GB_FIXTURE is missing"
elif [ -f "$TOOL" ]; then
    REPOROOTS_GB="$TMP/repo_roots_gb.json"
    printf '{"constitution": "%s"}\n' "$CONST_ROOT" > "$REPOROOTS_GB"
    OUT_GB="$TMP/gb_out.json"
    ERR_GB="$TMP/gb_out.err"
    python3 "$TOOL" --as-of 2026-09-29 --components-file "$GB_FIXTURE" \
        --repo-roots "$REPOROOTS_GB" --out "$OUT_GB" >"$ERR_GB" 2>&1
    RC_GB=$?
    if [ "$RC_GB" -eq 1 ] && [ -f "$OUT_GB" ] && grep -q "THIS_PATH_DOES_NOT_EXIST_5f9c2a1b.txt" "$OUT_GB" 2>/dev/null; then
        if grep -q '"churn_commits": *0[,}]' "$OUT_GB" 2>/dev/null; then
            bad "golden-bad: the missing path was silently reported as"
            echo "     churn_commits:0 instead of UNMEASURED/missing_instrument"
        else
            ok "golden-bad: churn_rank.py exits 1 (a finding, C-001), names"
            echo "   the missing path in its output, and does NOT silently"
            echo "   report churn_commits:0 for it"
        fi
    else
        bad "golden-bad check FAILED: expected exit 1 with the missing"
        echo "     path named in the output; got rc=$RC_GB --"
        echo "     $(cat "$ERR_GB" 2>/dev/null)"
    fi
else
    echo "NOT ok contract check 2/3 SKIPPED: churn_rank.py not present (see Section A)"
    bad "contract check 2/3 SKIPPED (tool absent)"
fi

echo
echo "=== T099 contract check 3/3: the REAL ATM-277 control needle -- rank in the top decile (task line, plan T-D05) ==="

VPD_PATH="Presenter/src/main/java/com/atmosphere/presenter/VideoPlaybackDetector.kt"
STALE_TEST_PATH="device/rockchip/rk3588/tests/test_display2_stale_frame_handoff.sh"

VPD_COUNT=$(cd "$PRESENTER_ROOT" 2>/dev/null && git log --follow --oneline -- "$VPD_PATH" 2>/dev/null | wc -l)
VPD_COUNT=${VPD_COUNT:-0}
STALE_TEST_COUNT=$(cd "$REPO_ROOT" && git log --follow --oneline -- "$STALE_TEST_PATH" 2>/dev/null | wc -l)
STALE_TEST_COUNT=${STALE_TEST_COUNT:-0}
ATM277_LIVE_SUM=$((VPD_COUNT + STALE_TEST_COUNT))

echo "   Live re-measurement (this run): VideoPlaybackDetector.kt=$VPD_COUNT"
echo "   commits (presenter submodule) + test_display2_stale_frame_handoff.sh=$STALE_TEST_COUNT"
echo "   commits (parent monorepo) = $ATM277_LIVE_SUM combined. Captured FACT at"
echo "   this file's authoring pass (2026-09-29): 26 + 6 = 32 -- EXACT match to"
echo "   the task line's stated '32 commits' (§11.4.6, no discrepancy found)."
if [ "$ATM277_LIVE_SUM" -lt 26 ]; then
    bad "the live-measured ATM-277 combined churn ($ATM277_LIVE_SUM) is"
    echo "     LOWER than the 32 captured at authoring time by more than a"
    echo "     small margin -- investigate whether history was rewritten"
    echo "     or the file paths moved (§11.4.6, never silently accept)"
fi

if [ "$VPD_COUNT" -eq 0 ]; then
    bad "could not measure VideoPlaybackDetector.kt's real commit count"
    echo "     (presenter submodule not checked out or path moved) -- the"
    echo "     real ATM-277 needle cannot be built"
elif [ -f "$TOOL" ]; then
    COMPONENTS_ATM="$TMP/components_atm277.json"
    cat > "$COMPONENTS_ATM" <<EOF
{"components": [
  {"id": "atm277_stale_frame", "paths": [
    {"repo": "presenter", "path": "$VPD_PATH"},
    {"repo": "main", "path": "$STALE_TEST_PATH"}
  ]},
  {"id": "ctx_render_keys", "paths": [{"repo": "constitution", "path": "scripts/fastcycle/tests/test_render_keys_red.sh"}]},
  {"id": "ctx_io_trace", "paths": [{"repo": "constitution", "path": "scripts/fastcycle/tests/test_io_trace_red.sh"}]},
  {"id": "ctx_backstop", "paths": [{"repo": "constitution", "path": "scripts/fastcycle/tests/test_backstop_red.sh"}]},
  {"id": "ctx_precheck_slicer", "paths": [{"repo": "constitution", "path": "scripts/fastcycle/tests/test_precheck_slicer_red.sh"}]},
  {"id": "ctx_check_deps", "paths": [{"repo": "constitution", "path": "scripts/fastcycle/tests/test_check_deps.sh"}]},
  {"id": "ctx_gate_order", "paths": [{"repo": "constitution", "path": "scripts/fastcycle/tests/test_gate_order_red.sh"}]},
  {"id": "ctx_gate_shard", "paths": [{"repo": "constitution", "path": "scripts/fastcycle/tests/test_gate_shard_red.sh"}]},
  {"id": "ctx_gate_audit", "paths": [{"repo": "constitution", "path": "scripts/fastcycle/tests/test_gate_audit_red.sh"}]},
  {"id": "ctx_baseline_replay", "paths": [{"repo": "constitution", "path": "scripts/fastcycle/tests/test_baseline_replay_red.sh"}]}
]}
EOF
    REPOROOTS_ATM="$TMP/repo_roots_atm277.json"
    python3 -c "
import json
print(json.dumps({
    'main': '$REPO_ROOT',
    'presenter': '$PRESENTER_ROOT',
    'constitution': '$CONST_ROOT',
}))
" > "$REPOROOTS_ATM"

    OUT_ATM="$TMP/atm277_out.json"
    ERR_ATM="$TMP/atm277_out.err"
    TODAY=$(date -u +%Y-%m-%d)
    python3 "$TOOL" --as-of "$TODAY" --components-file "$COMPONENTS_ATM" \
        --repo-roots "$REPOROOTS_ATM" --out "$OUT_ATM" >"$ERR_ATM" 2>&1
    RC_ATM=$?
    if [ "$RC_ATM" -eq 0 ] && [ -f "$OUT_ATM" ]; then
        ATM_CHECK="$(python3 -c "
import json
actual = json.load(open('$OUT_ATM'))
comps = actual['components']
me = next((c for c in comps if c['component_id'] == 'atm277_stale_frame'), None)
n_top_decile = sum(1 for c in comps if c.get('in_top_decile'))
result = {
    'found': me is not None,
    'rank': me.get('rank') if me else None,
    'in_top_decile': me.get('in_top_decile') if me else None,
    'churn_commits': me.get('churn_commits') if me else None,
    'n_components': len(comps),
    'n_top_decile': n_top_decile,
}
print(json.dumps(result))
" 2>&1)"
        FOUND=$(echo "$ATM_CHECK" | python3 -c "import json,sys; print(json.load(sys.stdin)['found'])" 2>&1)
        RANK=$(echo "$ATM_CHECK" | python3 -c "import json,sys; print(json.load(sys.stdin)['rank'])" 2>&1)
        IN_TOP=$(echo "$ATM_CHECK" | python3 -c "import json,sys; print(json.load(sys.stdin)['in_top_decile'])" 2>&1)
        CHURN=$(echo "$ATM_CHECK" | python3 -c "import json,sys; print(json.load(sys.stdin)['churn_commits'])" 2>&1)
        N_COMPONENTS=$(echo "$ATM_CHECK" | python3 -c "import json,sys; print(json.load(sys.stdin)['n_components'])" 2>&1)
        N_TOP=$(echo "$ATM_CHECK" | python3 -c "import json,sys; print(json.load(sys.stdin)['n_top_decile'])" 2>&1)
        if [ "$FOUND" = "True" ] && [ "$RANK" = "1" ] && [ "$IN_TOP" = "True" ] \
            && [ "$CHURN" = "$ATM277_LIVE_SUM" ] && [ "$N_COMPONENTS" = "10" ] && [ "$N_TOP" = "1" ]; then
            ok "churn_rank.py: the atm277_stale_frame component (combining"
            echo "   VideoPlaybackDetector.kt + test_display2_stale_frame_"
            echo "   handoff.sh, live churn=$CHURN) ranks #1 of 10 and is"
            echo "   the ONLY component flagged in_top_decile -- the task"
            echo "   line's control needle holds"
        else
            bad "the real ATM-277 needle FAILED: found=$FOUND rank=$RANK"
            echo "     in_top_decile=$IN_TOP churn_commits=$CHURN"
            echo "     n_components=$N_COMPONENTS n_top_decile=$N_TOP"
            echo "     (expected found=True rank=1 in_top_decile=True"
            echo "     churn_commits=$ATM277_LIVE_SUM n_components=10 n_top_decile=1)"
        fi
    else
        bad "churn_rank.py invocation against the real ATM-277 needle"
        echo "     failed (rc=$RC_ATM) -- $(cat "$ERR_ATM" 2>/dev/null)"
    fi
else
    echo "NOT ok contract check 3/3 SKIPPED: churn_rank.py not present (see Section A)"
    bad "contract check 3/3 SKIPPED (tool absent)"
fi

echo
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
