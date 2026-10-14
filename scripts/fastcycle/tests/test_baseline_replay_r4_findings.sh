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
SCRIPT_PATH="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"

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
# B1: SIGHUP/SIGQUIT must be handled PROMPTLY -- the gate stopped, the worktree
# removed, the script gone -- not deferred until the gate finishes on its own.
#
# T048 restart round 1 (R6-F13): the earlier version of this block replayed a
# `sleep 5` gate and only counted leftover worktrees 2 s later, and its paired
# mutation anchored on a string that no longer existed in the script, so the
# mutation silently changed only half of what it claimed (the `diff -q` "some
# difference" check could not see that). Now (1) the gate runs 30 s, so a
# deferred handler is observable as elapsed time; (2) the gate process itself
# must be dead; (3) every mutation anchor must match EXACTLY ONCE or the
# mutation is reported as broken.
# =============================================================================
sleep_gate() { # sleep_gate <path> <pidfile> -- a 30 s gate whose cmdline carries <path>
    printf '#!/bin/bash\necho $$ >"%s"\nexec -a "r4-test-sleep %s" sleep 30\n' "$2" "$1" >"$1"
    chmod +x "$1"
}
gate_alive() { # pid still running (not a zombie) AND still our gate (§11.4.263: never act on a reused pid)
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -gt 1 ] || return 1
    tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null | grep -q "r4-test-sleep" || return 1
    [ "$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null)" != Z ]
}
reap_gate() { gate_alive "$1" && kill -KILL "$1" 2>/dev/null; return 0; }

# b1_case <script> <signal> -> sets B1_ELAPSED B1_LEFTOVER B1_WT B1_GATE_ALIVE
b1_case() {
    local script="$1" sig="$2" repo commit tree wtr out pidf
    repo="$(mk_scratch_repo a init)"
    commit="$(git -C "$repo" rev-parse HEAD)"; tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
    wtr="$repo/.fc_worktrees"; mkdir -p "$wtr"
    out="$(mktemp)"; pidf="$repo/gate.pid"
    sleep_gate "$repo/gate.sh" "$pidf"
    local t0=$SECONDS
    # a private TMPDIR: the mutant case below is ended by SIGKILL, which no trap
    # can clean up after -- its temp files must not leak into the caller's TMPDIR
    local td; td="$(mktemp -d)"
    TMPDIR="$td" timeout -s "$sig" -k 25 1.5s bash "$script" replay --commit "$commit" --tree "$tree" \
        --repo-root "$repo" --worktree-root "$wtr" --min-free-kb 0 \
        --gate-cmd "$repo/gate.sh" --cold-runs 1 --warm-runs 0 --out "$out" >/dev/null 2>&1
    B1_ELAPSED=$((SECONDS - t0))
    sleep 0.5
    B1_LEFTOVER="$(find "$wtr" -maxdepth 1 -type d -name 'replay.*' 2>/dev/null | wc -l)"
    B1_WT="$(git -C "$repo" worktree list 2>/dev/null | wc -l)"
    local gp; gp="$(cat "$pidf" 2>/dev/null)"
    if gate_alive "$gp"; then B1_GATE_ALIVE=yes; else B1_GATE_ALIVE=no; fi
    reap_gate "$gp"
    git -C "$repo" worktree prune >/dev/null 2>&1
    rm -rf "$repo" "$out" "$td"
}

for SIG in HUP QUIT; do
    b1_case "$SCRIPT_PATH" "$SIG"
    if [ "$B1_LEFTOVER" -eq 0 ] && [ "$B1_WT" -eq 1 ] && [ "$B1_GATE_ALIVE" = no ] && [ "$B1_ELAPSED" -le 15 ]; then
        ok "B1 (SIG$SIG): handled promptly -- script gone in ${B1_ELAPSED}s, gate stopped, no orphan worktree (leftover=$B1_LEFTOVER count=$B1_WT)"
    else
        bad "B1 (SIG$SIG): elapsed=${B1_ELAPSED}s leftover=$B1_LEFTOVER worktrees=$B1_WT gate-alive=$B1_GATE_ALIVE"
    fi
done

# =============================================================================
# B1 paired mutation (§1.1): put the gate back into the FOREGROUND (no `&` +
# `wait`). bash then defers every trapped signal until the 30 s gate ends on its
# own, so this SAME check must fail on the SIGHUP case.
# =============================================================================
# The mutant lives in a throwaway replica (cycle/ + lib/) so the real tree is
# never written and the script's own $FC/lib resolution still works.
MUT_ROOT="$(mktemp -d)"
cp -r "$(dirname "$SCRIPT_PATH")/../lib" "$MUT_ROOT/lib"
mkdir -p "$MUT_ROOT/cycle"
MUT_SCRIPT="$MUT_ROOT/cycle/baseline_replay.sh"
python3 - "$SCRIPT_PATH" "$MUT_SCRIPT" << 'PYEOF'
import sys
# B1 mutation builder
src_path, out_path = sys.argv[1], sys.argv[2]
src = open(src_path).read()
# (T048 restart round 2: the launch line now also closes fd 9, the replay lock)
old = ("exit 127' fc-gate \"$marker\" \"$cwd\" \"$@\" >\"$log\" 2>&1 </dev/null 9>&- &\n"
       "  _FC_CHILD_PGID=$!\n"
       "  wait \"$_FC_CHILD_PGID\"\n"
       "  RG_RC=$?\n")
new = ("exit 127' fc-gate \"$marker\" \"$cwd\" \"$@\" >\"$log\" 2>&1 </dev/null 9>&-\n"
       "  RG_RC=$?\n")
n = src.count(old)
if n != 1:
    sys.stderr.write("B1 mutation anchor matched %d times (need exactly 1)\n" % n)
    sys.exit(3)
open(out_path, "w").write(src.replace(old, new, 1))
PYEOF
MUT_BUILD_RC=$?
if [ "$MUT_BUILD_RC" -eq 0 ]; then
    b1_case "$MUT_SCRIPT" HUP
    if [ "$B1_ELAPSED" -gt 15 ] || [ "$B1_LEFTOVER" -gt 0 ] || [ "$B1_GATE_ALIVE" = yes ]; then
        ok "B1 mutation check: a foreground gate DOES defer the SIGHUP handler (elapsed=${B1_ELAPSED}s leftover=$B1_LEFTOVER gate-alive=$B1_GATE_ALIVE) -- this test genuinely catches the regression"
    else
        bad "B1 mutation check: the foreground-gate mutant was handled promptly anyway (elapsed=${B1_ELAPSED}s) -- this test may be a bluff gate"
    fi
else
    bad "B1 mutation check: the mutation anchor did not match exactly once -- the anchor has drifted, fix it"
fi
rm -rf "$MUT_ROOT"

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
