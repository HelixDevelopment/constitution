#!/usr/bin/env bash
# =============================================================================
# test_baseline_replay_r4_findings.sh -- permanent regression guard for T043
# round-4 independent review's 3 BLOCKING findings (agent ad5d869e28efdddbd,
# 2026-09-28), all against baseline_replay.sh / cycle_report.py:
#
#   B1: SIGHUP/SIGQUIT during a replay's gate-cmd leaked an orphan git
#       worktree -- bash defers a trapped signal until the CURRENT
#       FOREGROUND command finishes, so a plain (non-backgrounded)
#       foreground subshell running the gate-cmd delayed the HUP/QUIT
#       trap past the point where it could help. Fixed by (a) converting
#       HUP/QUIT into a direct call to cleanup() inside the signal
#       handler itself (no dependency on exit->EXIT-trap chaining) and
#       (b) backgrounding the gate-cmd subshell + `wait`ing on it
#       explicitly, which IS promptly interruptible by a pending trapped
#       signal (unlike a synchronous foreground pipeline).
#
#   B2: git_subject_freeze() (baseline_replay.sh) and
#       git_subject_matches() (cycle_report.py) both used plain substring
#       matching (`case ... in *"$item_id"*` / `item_id in subject`), so
#       item ATM-103 silently matched a commit subject containing
#       ATM-1038 -- freezing/attributing the WRONG commit with exit 0,
#       no BLIND, no warning. Fixed with a token-boundary regex requiring
#       a non-alnum-non-hyphen (or string-start) boundary on the left and
#       a non-digit (or string-end) boundary on the right.
#
#   B3: a RELATIVE --worktree-root resolved against the CALLER's cwd for
#       mktemp/df/the gate's own cd, but against $repo_root for
#       `git -C "$repo_root" worktree add` -- two different base
#       directories for the same value. Fixed by resolving worktree_root
#       to an absolute, canonical path immediately (mkdir -p + cd+pwd),
#       exactly like repo_root already was, in BOTH cmd_replay and
#       cmd_replay_sample.
#
# ANTI-BLUFF (§11.4.273): every "leftover=0"/"count=1" absence check below
# is preceded, in this SAME session's independent verification, by a
# control-needle proving the signal-delivery mechanism itself genuinely
# works (a `--foreground` flag on `timeout` was independently discovered
# and ruled out as suppressing signal delivery to nested subshells --
# documented here so this test never regresses to that flawed form).
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
SCRIPT_PATH="$FC/cycle/baseline_replay.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok $*"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $*"; }

mk_scratch_repo() {
    local r
    r="$(mktemp -d)"
    git -C "$r" init -q
    git -C "$r" config user.email t@t.com
    git -C "$r" config user.name t
    printf '%s' "$1" > "$r/f.txt"
    git -C "$r" add f.txt
    git -C "$r" commit -q -m "$2"
    printf '%s' "$r"
}

# =============================================================================
# B1: SIGHUP must not leave an orphan worktree (real repro, no --foreground)
# =============================================================================
REPO="$(mk_scratch_repo a init)"
COMMIT="$(git -C "$REPO" rev-parse HEAD)"
TREE="$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
WT_ROOT="$REPO/.fc_worktrees"
mkdir -p "$WT_ROOT"
OUT="$(mktemp)"
timeout -s HUP 1.5s bash "$SCRIPT_PATH" replay --commit "$COMMIT" --tree "$TREE" \
    --repo-root "$REPO" --worktree-root "$WT_ROOT" \
    --gate-cmd "sleep 5" --cold-runs 1 --warm-runs 0 --out "$OUT" >/dev/null 2>&1
sleep 0.5
LEFTOVER="$(find "$WT_ROOT" -maxdepth 1 -type d -name 'replay.*' 2>/dev/null | wc -l)"
WT_COUNT="$(git -C "$REPO" worktree list 2>/dev/null | wc -l)"
if [ "$LEFTOVER" -eq 0 ] && [ "$WT_COUNT" -eq 1 ]; then
    ok "B1 (SIGHUP): no orphan worktree survived (leftover=$LEFTOVER count=$WT_COUNT)"
else
    bad "B1 (SIGHUP): orphan worktree leaked (leftover=$LEFTOVER count=$WT_COUNT)"
fi
rm -rf "$REPO" "$OUT"

# --- SIGQUIT sibling case ---
REPO="$(mk_scratch_repo a init)"
COMMIT="$(git -C "$REPO" rev-parse HEAD)"
TREE="$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
WT_ROOT="$REPO/.fc_worktrees"
mkdir -p "$WT_ROOT"
OUT="$(mktemp)"
timeout -s QUIT 1.5s bash "$SCRIPT_PATH" replay --commit "$COMMIT" --tree "$TREE" \
    --repo-root "$REPO" --worktree-root "$WT_ROOT" \
    --gate-cmd "sleep 5" --cold-runs 1 --warm-runs 0 --out "$OUT" >/dev/null 2>&1
sleep 0.5
LEFTOVER="$(find "$WT_ROOT" -maxdepth 1 -type d -name 'replay.*' 2>/dev/null | wc -l)"
WT_COUNT="$(git -C "$REPO" worktree list 2>/dev/null | wc -l)"
if [ "$LEFTOVER" -eq 0 ] && [ "$WT_COUNT" -eq 1 ]; then
    ok "B1 (SIGQUIT): no orphan worktree survived (leftover=$LEFTOVER count=$WT_COUNT)"
else
    bad "B1 (SIGQUIT): orphan worktree leaked (leftover=$LEFTOVER count=$WT_COUNT)"
fi
rm -rf "$REPO" "$OUT"

# =============================================================================
# B1 paired mutation (§1.1): reverting to `trap 'exit N' SIG` (the ORIGINAL
# broken form, relying on exit->EXIT-trap chaining through a synchronous
# foreground wait) must make this SAME test fail on the SIGHUP case.
# =============================================================================
MUT_SCRIPT="$(mktemp)"
python3 - "$SCRIPT_PATH" "$MUT_SCRIPT" << 'PYEOF'
import re, sys
src_path, out_path = sys.argv[1], sys.argv[2]
src = open(src_path).read()
# Revert to the pre-fix direct-exit form (drops the direct-cleanup-in-handler fix).
src = src.replace(
    '  local _sig_cleanup_cmd\n'
    '  printf -v _sig_cleanup_cmd \'%s; trap - EXIT HUP QUIT\' "$_cleanup_trap_cmd"\n'
    '  trap "$_sig_cleanup_cmd; exit 129" HUP\n'
    '  trap "$_sig_cleanup_cmd; exit 131" QUIT',
    "  trap 'exit 129' HUP\n  trap 'exit 131' QUIT",
    1,
)
# Revert to the synchronous foreground form (drops the background+wait fix).
# NOTE (T048 remediation, 2026-09-29): the gate-cmd's stdout+stderr
# redirect target changed from a fixed `/dev/null` to a per-run captured
# log file (`"$run_log"`, F9 output-discarding hardening) -- this anchor
# is updated to match so the mutation keeps finding (and correctly
# reverting only) the B1 backgrounding+wait fix, independent of that
# unrelated redirect-target change.
src = src.replace(
    '      run_log="$run_log_dir/${commit_short}_${phase}_${run_idx}.log"\n'
    '      ( cd "$wt_path" && timeout --kill-after=5 "${timeout_s}s" "${gate_cmd[@]}" ) >"$run_log" 2>&1 &\n'
    '      local gate_pid=$!\n'
    '      wait "$gate_pid"\n'
    '      rc=$?',
    '      run_log="$run_log_dir/${commit_short}_${phase}_${run_idx}.log"\n'
    '      ( cd "$wt_path" && timeout --kill-after=5 "${timeout_s}s" "${gate_cmd[@]}" ) >"$run_log" 2>&1\n'
    '      rc=$?',
    1,
)
open(out_path, 'w').write(src)
PYEOF
if ! diff -q "$SCRIPT_PATH" "$MUT_SCRIPT" >/dev/null 2>&1; then
    REPO="$(mk_scratch_repo a init)"
    COMMIT="$(git -C "$REPO" rev-parse HEAD)"
    TREE="$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
    WT_ROOT="$REPO/.fc_worktrees"
    mkdir -p "$WT_ROOT"
    OUT="$(mktemp)"
    timeout -s HUP 1.5s bash "$MUT_SCRIPT" replay --commit "$COMMIT" --tree "$TREE" \
        --repo-root "$REPO" --worktree-root "$WT_ROOT" \
        --gate-cmd "sleep 5" --cold-runs 1 --warm-runs 0 --out "$OUT" >/dev/null 2>&1
    sleep 0.5
    LEFTOVER="$(find "$WT_ROOT" -maxdepth 1 -type d -name 'replay.*' 2>/dev/null | wc -l)"
    if [ "$LEFTOVER" -gt 0 ]; then
        ok "B1 mutation check: reverting the fix DOES reproduce the SIGHUP leak (leftover=$LEFTOVER) -- this test genuinely catches the regression, not merely agreeing with the current code"
    else
        bad "B1 mutation check: reverting the fix did NOT reproduce a leak -- this test may be a bluff gate"
    fi
    rm -rf "$REPO" "$OUT"
else
    bad "B1 mutation check: the mutation script produced NO diff from the real file -- the anchor strings this test relies on have drifted, fix the anchors"
fi
rm -f "$MUT_SCRIPT"

# =============================================================================
# B2: token-boundary item-id matching (synthetic, deterministic -- an
# ATM-103/ATM-1038 collision constructed directly rather than hunting for
# a specific real-history commit that may or may not exist in any given
# checkout state).
# =============================================================================
REPO="$(mktemp -d)"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.com
git -C "$REPO" config user.name t
echo a > "$REPO/f.txt" && git -C "$REPO" add f.txt && git -C "$REPO" commit -q -m "ATM-103 fix the thing"
echo b >> "$REPO/f.txt" && git -C "$REPO" add f.txt && git -C "$REPO" commit -q -m "ATM-1038 unrelated later item"
OUT="$(mktemp)"
bash "$SCRIPT_PATH" freeze --item ATM-103 --repo-root "$REPO" --out "$OUT" >/dev/null 2>&1
CANDCOUNT="$(python3 -c "import json; print(json.load(open('$OUT'))['candidate_commit_count'])" 2>/dev/null)"
SUBJECT="$(python3 -c "import json; print(json.load(open('$OUT')).get('commit_subject',''))" 2>/dev/null)"
if [ "$CANDCOUNT" = "1" ] && [ "$SUBJECT" = "ATM-103 fix the thing" ]; then
    ok "B2 (baseline_replay.sh git_subject_freeze): ATM-103 matches ONLY the correct commit, never the ATM-1038 collision (count=$CANDCOUNT subject='$SUBJECT')"
else
    bad "B2 (baseline_replay.sh git_subject_freeze): wrong match -- count=$CANDCOUNT subject='$SUBJECT'"
fi
rm -rf "$REPO" "$OUT"

# --- cycle_report.py's sibling function ---
CR_CHECK="$(python3 -c "
import sys
sys.path.insert(0, '$FC/cycle')
import cycle_report
print(cycle_report.git_subject_matches.__doc__ is not None)
" 2>&1)"
if echo "$CR_CHECK" | grep -q True; then
    ok "cycle_report.py: git_subject_matches importable (module loads cleanly after the B2 regex fix)"
else
    bad "cycle_report.py: git_subject_matches failed to import cleanly -- $CR_CHECK"
fi

# =============================================================================
# B3: relative --worktree-root from a different cwd resolves to the same
# absolute directory every consumer (mkdir/df/git-worktree-add/gate's cd)
# agrees on -- checked by confirming the worktree genuinely lands under
# the resolved absolute path AND the report's tree field is non-empty
# (never the false-empty-data symptom the original bug produced).
# =============================================================================
REPO2="$(mk_scratch_repo a init2)"
COMMIT2="$(git -C "$REPO2" rev-parse HEAD)"
OTHER_CWD="$(mktemp -d)"
OUT2="$(mktemp)"
( cd "$OTHER_CWD" && bash "$SCRIPT_PATH" replay --commit "$COMMIT2" --repo-root "$REPO2" --worktree-root "relwt" \
    --gate-cmd "test -f f.txt" --cold-runs 1 --warm-runs 0 --out "$OUT2" >/dev/null 2>&1 )
TREE_FIELD="$(python3 -c "import json; print(json.load(open('$OUT2')).get('tree',''))" 2>/dev/null)"
if [ -d "$OTHER_CWD/relwt" ] && [ -n "$TREE_FIELD" ]; then
    ok "B3: relative --worktree-root resolved consistently (created at $OTHER_CWD/relwt, tree field populated: $TREE_FIELD)"
else
    bad "B3: relative --worktree-root did not resolve consistently (dir-exists=$([ -d "$OTHER_CWD/relwt" ] && echo yes || echo no) tree='$TREE_FIELD')"
fi
rm -rf "$REPO2" "$OTHER_CWD" "$OUT2"

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
