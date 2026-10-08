#!/usr/bin/env bash
# =============================================================================
# test_baseline_replay_r4_findings.sh -- permanent regression guard for T043
# round-4 independent review's 3 BLOCKING findings (agent ad5d869e28efdddbd,
# 2026-09-28), all against baseline_replay.sh / cycle_report.py:
#
#   B1 (now guarded by the round-3 stop matrix, see below):
#       SIGHUP/SIGQUIT during a replay's gate-cmd leaked an orphan git
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
SCRIPT_PATH="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"

PASS=0
FAIL=0
# private per-filesystem replay lock directory (never contend with another replay on this host)
FC_REPLAY_LOCK_DIR="$(mktemp -d)"
export FC_REPLAY_LOCK_DIR
trap 'rm -rf "$FC_REPLAY_LOCK_DIR"' EXIT
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
# B1 (SIGHUP/SIGQUIT handled PROMPTLY, gate stopped, no orphan worktree): the
# round-4 case and its "gate back in the FOREGROUND" paired mutation lived here.
# T048 restart round 3 replaced the stop subsystem with one supervisor and every
# per-finding signal case with ONE stop matrix (test_baseline_replay_r2_findings.sh
# case SM, wall-clock deadlines, gates that never end by themselves). The B1
# mutation is kept as R3-M-FG in test_fastcycle_r6_mutations.sh: the worker's
# long-running child back in the foreground -> every HUP/QUIT/TERM/INT to the
# worker is deferred until the gate ends -> the matrix's deadline catches it.
# =============================================================================

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
# (paths are passed as argv, never spliced into Python source -- R6-F5 class)
CANDCOUNT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_commit_count"])' "$OUT" 2>/dev/null)"
SUBJECT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("commit_subject",""))' "$OUT" 2>/dev/null)"
if [ "$CANDCOUNT" = "1" ] && [ "$SUBJECT" = "ATM-103 fix the thing" ]; then
    ok "B2 (baseline_replay.sh git_subject_freeze): ATM-103 matches ONLY the correct commit, never the ATM-1038 collision (count=$CANDCOUNT subject='$SUBJECT')"
else
    bad "B2 (baseline_replay.sh git_subject_freeze): wrong match -- count=$CANDCOUNT subject='$SUBJECT'"
fi
rm -rf "$REPO" "$OUT"

# --- cycle_report.py's sibling function ---
# T048 restart round 1 (R6-F16): this used to assert only that
# git_subject_matches.__doc__ is not None, which cannot fail on a token-boundary
# regression. It now calls the real function against a scratch repo holding an
# ATM-103 commit and an ATM-1038 commit and requires exactly the ATM-103 one.
REPO="$(mktemp -d)"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.com
git -C "$REPO" config user.name t
echo a > "$REPO/f.txt" && git -C "$REPO" add f.txt && git -C "$REPO" commit -q -m "ATM-103 fix the thing"
echo b >> "$REPO/f.txt" && git -C "$REPO" add f.txt && git -C "$REPO" commit -q -m "ATM-1038 unrelated later item"
CR_CHECK="$(python3 - "$FC/cycle" "$REPO" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import cycle_report
r = cycle_report.git_subject_matches(sys.argv[2], "ATM-103")
# cycle_report.py's return shape is owned by a sibling slice: accept both the
# plain list and the ("ok", list) form, and fail loudly on anything else.
if isinstance(r, tuple):
    status, m = r
    if status != "ok":
        print("STATUS=%s %s" % (status, m))
        sys.exit(0)
else:
    m = r
print("SUBJECTS=" + "|".join(x["subject"] for x in m))
PY
)"
if [ "$CR_CHECK" = "SUBJECTS=ATM-103 fix the thing" ]; then
    ok "cycle_report.py git_subject_matches: ATM-103 matches only its own commit, never ATM-1038"
else
    bad "cycle_report.py git_subject_matches token boundary: $CR_CHECK"
fi
rm -rf "$REPO"

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
    --min-free-kb 0 --gate-cmd "test -f f.txt" --cold-runs 1 --warm-runs 0 --out "$OUT2" >/dev/null 2>&1 )
# T048 restart round 1 (R6-F17): a non-empty tree field alone does not prove the
# gate ran against the real checkout (the original bug was a FALSE "FAIL" for
# exactly this gate). The gate `test -f f.txt` must PASS, and the tree must be
# the commit's real tree.
TREE_FIELD="$(python3 - "$OUT2" <<'PY' 2>/dev/null
import json, sys
print(json.load(open(sys.argv[1])).get("tree", ""))
PY
)"
VSET="$(python3 - "$OUT2" <<'PY' 2>/dev/null
import json, sys
print(",".join(json.load(open(sys.argv[1]))["verdict_set"]["cold"]))
PY
)"
REAL_TREE="$(git -C "$REPO2" rev-parse 'HEAD^{tree}')"
if [ -d "$OTHER_CWD/relwt" ] && [ "$TREE_FIELD" = "$REAL_TREE" ] && [ "$VSET" = PASS ]; then
    ok "B3: relative --worktree-root resolved consistently (created at $OTHER_CWD/relwt, tree=$TREE_FIELD, gate 'test -f f.txt' PASS)"
else
    bad "B3: relative --worktree-root did not resolve consistently (dir-exists=$([ -d "$OTHER_CWD/relwt" ] && echo yes || echo no) tree='$TREE_FIELD' want '$REAL_TREE' cold-verdicts='$VSET')"
fi
rm -rf "$REPO2" "$OTHER_CWD" "$OUT2"

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
