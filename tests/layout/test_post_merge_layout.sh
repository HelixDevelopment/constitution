#!/usr/bin/env bash
# tests/layout/test_post_merge_layout.sh — e2e tests for scripts/hooks/post-merge
# in BOTH layouts, driven by REAL `git merge` runs in a real consumer repo whose
# constitution is a real submodule added from a local bare upstream.
#
# Asserts: the hook fires (calls the post-update hook with the right
# PROJECT_ROOT/CONST_DIR) when a merge moves the constitution gitlink; stays
# quiet and exits 0 when it does not; and NEVER exits 0 silently when it cannot
# find the constitution (a warning on stderr is required, §11.4.201).
# Usage: bash tests/layout/test_post_merge_layout.sh
LT_SUITE="post_merge_layout"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

URL="$(lt_make_const_upstream pm)"
lt_bump_const_upstream pm          # upstream now has 2 commits
export LAYOUT_RECORD="$LT_SB/record.txt"

for rel in submodules/constitution constitution; do
    tag="[$rel]"
    P="$LT_SB/pm $(printf '%s' "$rel" | tr / _)"
    lt_make_project "$P" "$URL" "$rel" || { lt_bad "$tag fixture"; continue; }
    # pin the submodule to the FIRST upstream commit on main
    first="$(git -C "$P/$rel" rev-list --max-parents=0 HEAD)"
    lt_git -C "$P/$rel" checkout -q "$first"
    lt_git -C "$P" commit -q -am "pin constitution to v1"
    cp "$P/$rel/scripts/hooks/post-merge" "$P/.git/hooks/post-merge"
    chmod +x "$P/.git/hooks/post-merge"

    # 1. a merge that does NOT touch the gitlink -> no call, exit 0
    lt_git -C "$P" checkout -q -b side
    printf 'x\n' > "$P/side.txt"; lt_git -C "$P" add side.txt; lt_git -C "$P" commit -q -m side
    lt_git -C "$P" checkout -q main
    : > "$LAYOUT_RECORD"
    lt_git -C "$P" merge -q --no-ff -m "merge side" side >"$LT_SB/m1.out" 2>&1; rc=$?
    lt_check "$tag unrelated merge: exit 0 (rc=$rc)" test "$rc" -eq 0
    lt_check "$tag unrelated merge: post-update hook NOT called" test ! -s "$LAYOUT_RECORD"

    # 2. a merge that bumps the constitution gitlink -> hook fires
    lt_git -C "$P" checkout -q -b bump
    lt_git -C "$P/$rel" checkout -q origin/HEAD 2>/dev/null || lt_git -C "$P/$rel" checkout -q origin/main
    lt_git -C "$P" commit -q -am "bump constitution"
    lt_git -C "$P" checkout -q main      # submodule worktree stays on the bumped commit
    : > "$LAYOUT_RECORD"
    lt_git -C "$P" merge -q --no-ff -m "merge bump" bump >"$LT_SB/m2.out" 2>"$LT_SB/m2.err"; rc=$?
    lt_check "$tag gitlink-bump merge: exit 0 (rc=$rc)" test "$rc" -eq 0
    lt_check "$tag gitlink-bump merge: post-update hook FIRED with PROJECT_ROOT=<project> CONST_DIR=<project>/$rel" \
        grep -qF "CALLED PROJECT_ROOT=$P CONST_DIR=$P/$rel " "$LAYOUT_RECORD"
    lt_check "$tag gitlink-bump merge: hook ran from the project root" grep -qF " PWD=$P OLD=" "$LAYOUT_RECORD"
    lt_check "$tag gitlink-bump merge: announced (git routes hook stdout to stderr)" grep -q '\[post-merge\] Constitution submodule updated' "$LT_SB/m2.out" "$LT_SB/m2.err"
    lt_check "$tag gitlink-bump merge: submodule HEAD read from the SUBMODULE (no stale-checkout warning)" \
        eval '! grep -q "checkout is at" "$LT_SB/m2.err"'
    bumped="$(git -C "$P" rev-parse "HEAD:$rel")"
    lt_check "$tag gitlink-bump merge: OLD..NEW gitlink range handed to the hook (I6)" \
        grep -qF " OLD=$first NEW=$bumped" "$LAYOUT_RECORD"
    : > "$LAYOUT_RECORD"
    lt_git -C "$P" commit -q --allow-empty -m noop
    lt_git -C "$P" merge -q --ff-only main >/dev/null 2>&1
    lt_check "$tag re-run (already merged): no second call (idempotent)" test ! -s "$LAYOUT_RECORD"

    # I5: a FAST-FORWARD of 2 commits where the gitlink bump is the FIRST one
    # (HEAD^1 already carries the new gitlink; only ORIG_HEAD..HEAD sees it).
    lt_bump_const_upstream pm
    lt_git -C "$P" checkout -q -b ff2
    lt_git -C "$P/$rel" fetch -q origin
    lt_git -C "$P/$rel" checkout -q origin/main
    new2="$(git -C "$P/$rel" rev-parse HEAD)"
    lt_git -C "$P" commit -q -am "bump constitution (first of two)"
    printf 'z\n' > "$P/after.txt"; lt_git -C "$P" add after.txt; lt_git -C "$P" commit -q -m "unrelated second commit"
    lt_git -C "$P" checkout -q main      # submodule worktree stays at new2
    : > "$LAYOUT_RECORD"
    lt_git -C "$P" merge -q --ff-only ff2 >/dev/null 2>"$LT_SB/ff.err"; rc=$?
    lt_check "$tag ff of 2 commits, bump in the FIRST: exit 0 (rc=$rc)" test "$rc" -eq 0
    lt_check "$tag ff of 2 commits, bump in the FIRST: hook FIRED with OLD=$bumped NEW=$new2" \
        grep -qF " OLD=$bumped NEW=$new2" "$LAYOUT_RECORD"

    # I6: a merge that moves the gitlink while the submodule checkout is STALE
    # (checkout != merged gitlink, e.g. `git pull` without submodule update):
    # the hook must NOT run on the old checkout; a warning is required instead.
    lt_bump_const_upstream pm
    lt_git -C "$P" checkout -q -b stale
    lt_git -C "$P/$rel" fetch -q origin
    lt_git -C "$P/$rel" checkout -q origin/main
    new3="$(git -C "$P/$rel" rev-parse HEAD)"
    lt_git -C "$P" commit -q -am "bump constitution (checkout will be stale)"
    lt_git -C "$P/$rel" checkout -q "$new2"   # back to the old checkout
    lt_git -C "$P" checkout -q main
    : > "$LAYOUT_RECORD"
    lt_git -C "$P" merge -q --no-ff -m "merge stale" stale >/dev/null 2>"$LT_SB/stale.err"; rc=$?
    lt_check "$tag stale checkout: merge exits 0 (rc=$rc)" test "$rc" -eq 0
    lt_check "$tag stale checkout: post-update hook NOT run on the old checkout" test ! -s "$LAYOUT_RECORD"
    lt_check "$tag stale checkout: a WARNING names the stale checkout and the update command" \
        eval 'grep -q "checkout is at" "$LT_SB/stale.err" && grep -q "git submodule update" "$LT_SB/stale.err"'
    lt_git -C "$P/$rel" checkout -q "$new3"
done

# 3. hook installed but the constitution cannot be found -> loud warning, exit 0
P="$LT_SB/pm submodules_constitution"
cp "$P/.git/hooks/post-merge" "$LT_SB/post-merge.saved"
mv "$P/submodules/constitution" "$LT_SB/moved_away"
lt_git -C "$P" checkout -q -b side2
printf 'y\n' > "$P/side2.txt"; lt_git -C "$P" add side2.txt; lt_git -C "$P" commit -q -m side2
lt_git -C "$P" checkout -q main
lt_git -C "$P" merge -q --no-ff -m "merge side2" side2 >"$LT_SB/m3.out" 2>"$LT_SB/m3.err"; rc=$?
lt_check "missing constitution: merge still exits 0 (non-fatal) (rc=$rc)" test "$rc" -eq 0
# round 2 (M-c/M-e): a merge that moves NO gitlink is a real no-op -> no noise
lt_check "missing constitution + merge moving no gitlink: no hook output (no per-merge noise)" \
    eval '! grep -q "post-merge" "$LT_SB/m3.err"'
# ...but a merge that moves the constitution gitlink while the checkout is
# missing gets ONE concise warning naming the command (never a silent exit 0)
lt_bump_const_upstream pm
nsha="$(git -C "$LT_SB/src_pm" rev-parse HEAD)"
lt_git -C "$P" checkout -q -b gl3
lt_git -C "$P" update-index --cacheinfo "160000,$nsha,submodules/constitution"
lt_git -C "$P" commit -q -m "bump gitlink while checkout is missing"
lt_git -C "$P" checkout -q main 2>/dev/null
lt_git -C "$P" merge -q --no-ff -m "merge gl3" gl3 >/dev/null 2>"$LT_SB/m3b.err"; rc=$?
lt_check "missing constitution + gitlink bump: exit 0 + exactly ONE warning line with the init command (rc=$rc)" \
    eval 'test "$rc" -eq 0 && test "$(grep -c "post-merge" "$LT_SB/m3b.err")" = 1 && grep -q "WARNING.*no initialized checkout.*submodule update --init" "$LT_SB/m3b.err"'
mv "$LT_SB/moved_away" "$P/submodules/constitution"

# 4. CONSTITUTION_DIR override + a custom .gitmodules path
PC="$LT_SB/pm_custom"
lt_make_project "$PC" "$URL" vendor/helix || lt_bad "custom fixture"
first="$(git -C "$PC/vendor/helix" rev-list --max-parents=0 HEAD)"
lt_git -C "$PC/vendor/helix" checkout -q "$first"; lt_git -C "$PC" commit -q -am pin
cp "$PC/vendor/helix/scripts/hooks/post-merge" "$PC/.git/hooks/post-merge"; chmod +x "$PC/.git/hooks/post-merge"
lt_git -C "$PC" checkout -q -b bump
lt_git -C "$PC/vendor/helix" checkout -q origin/main 2>/dev/null || lt_git -C "$PC/vendor/helix" checkout -q origin/HEAD
lt_git -C "$PC" commit -q -am bump; lt_git -C "$PC" checkout -q main
: > "$LAYOUT_RECORD"
lt_git -C "$PC" merge -q --no-ff -m mb bump >/dev/null 2>&1
lt_check "custom .gitmodules path: hook fires with CONST_DIR=<project>/vendor/helix" \
    grep -qF "CALLED PROJECT_ROOT=$PC CONST_DIR=$PC/vendor/helix " "$LAYOUT_RECORD"

# 5. I1: an ambient CONSTITUTION_DIR naming ANOTHER checkout must not hide the
#    project's own gitlink move (the override only helps locate the lib).
PO="$LT_SB/pm_override"
lt_make_project "$PO" "$URL" submodules/constitution || lt_bad "override fixture"
first="$(git -C "$PO/submodules/constitution" rev-list --max-parents=0 HEAD)"
lt_git -C "$PO/submodules/constitution" checkout -q "$first"; lt_git -C "$PO" commit -q -am pin
cp "$PO/submodules/constitution/scripts/hooks/post-merge" "$PO/.git/hooks/post-merge"; chmod +x "$PO/.git/hooks/post-merge"
lt_git -C "$PO" checkout -q -b bump
lt_git -C "$PO/submodules/constitution" checkout -q origin/main
lt_git -C "$PO" commit -q -am bump; lt_git -C "$PO" checkout -q main
: > "$LAYOUT_RECORD"
CONSTITUTION_DIR="$LT_SB/src_pm" lt_git -C "$PO" merge -q --no-ff -m mb bump >/dev/null 2>"$LT_SB/ov.err"
lt_check "CONSTITUTION_DIR elsewhere: the project's gitlink bump still FIRES with CONST_DIR=<project>/submodules/constitution" \
    grep -qF "CALLED PROJECT_ROOT=$PO CONST_DIR=$PO/submodules/constitution " "$LAYOUT_RECORD"
NOC="$LT_SB/pm_noconst"; mkdir -p "$NOC"; lt_git init -q "$NOC"
printf 'a\n' > "$NOC/a"; lt_git -C "$NOC" add a; lt_git -C "$NOC" commit -q -m a
cp "$PO/.git/hooks/post-merge" "$NOC/.git/hooks/post-merge"
lt_git -C "$NOC" checkout -q -b s; printf 'b\n' > "$NOC/b"; lt_git -C "$NOC" add b; lt_git -C "$NOC" commit -q -m b
lt_git -C "$NOC" checkout -q main
: > "$LAYOUT_RECORD"
CONSTITUTION_DIR="$LT_SB/src_pm" lt_git -C "$NOC" merge -q --no-ff -m m s >/dev/null 2>"$LT_SB/noc.err"; rc=$?
lt_check "CONSTITUTION_DIR set, no gitlink moved: exit 0, no call, no noise (rc=$rc)" \
    eval 'test "$rc" -eq 0 && ! grep -q "post-merge" "$LT_SB/noc.err" && test ! -s "$LAYOUT_RECORD"'
# the project gains a constitution gitlink (no checkout): the override must
# not stand in for the missing project checkout -> warning, no call.
lt_git -C "$NOC" checkout -q -b s2
lt_git -C "$NOC" update-index --add --cacheinfo "160000,$(git -C "$LT_SB/src_pm" rev-parse HEAD),submodules/constitution"
lt_git -C "$NOC" commit -q -m "gitlink without checkout"; lt_git -C "$NOC" checkout -q main
CONSTITUTION_DIR="$LT_SB/src_pm" lt_git -C "$NOC" merge -q --no-ff -m m2 s2 >/dev/null 2>"$LT_SB/noc2.err"; rc=$?
lt_check "CONSTITUTION_DIR set, project gitlink moved but no checkout: exit 0 + WARNING, no call (rc=$rc)" \
    eval 'test "$rc" -eq 0 && grep -q "WARNING" "$LT_SB/noc2.err" && test ! -s "$LAYOUT_RECORD"'

# 6. M2: a submodule whose NAME (and path) contain spaces
PSP="$LT_SB/pm_spaces"; mkdir -p "$PSP"; lt_git init -q "$PSP"
printf '# c\n' > "$PSP/README.md"; lt_git -C "$PSP" add README.md; lt_git -C "$PSP" commit -q -m init
lt_git -C "$PSP" submodule add -q --name "my helix const" "$URL" "vendor/my const" >/dev/null 2>&1 || lt_bad "spaces fixture"
SPC="$PSP/vendor/my const"
lt_git -C "$SPC" checkout -q "$(git -C "$SPC" rev-list --max-parents=0 HEAD)"
lt_git -C "$PSP" commit -q -am "add pinned"
cp "$SPC/scripts/hooks/post-merge" "$PSP/.git/hooks/post-merge"; chmod +x "$PSP/.git/hooks/post-merge"
lt_git -C "$PSP" checkout -q -b bump; lt_git -C "$SPC" checkout -q origin/main
lt_git -C "$PSP" commit -q -am bump; lt_git -C "$PSP" checkout -q main
: > "$LAYOUT_RECORD"
lt_git -C "$PSP" merge -q --no-ff -m mb bump >/dev/null 2>&1
lt_check "submodule name with spaces: hook FIRES with CONST_DIR=<project>/vendor/my const" \
    grep -qF "CALLED PROJECT_ROOT=$PSP CONST_DIR=$SPC " "$LAYOUT_RECORD"

# 7. M4: `git merge --squash` invokes post-merge before any commit: no run, a
#    warning tells the user to run the hook after committing.
lt_bump_const_upstream pm
lt_git -C "$PSP" checkout -q -b sq; lt_git -C "$SPC" fetch -q origin; lt_git -C "$SPC" checkout -q origin/main
lt_git -C "$PSP" commit -q -am "bump for squash"; lt_git -C "$PSP" checkout -q main
: > "$LAYOUT_RECORD"
lt_git -C "$PSP" merge -q --squash sq >/dev/null 2>"$LT_SB/sq.err"
lt_check "squash merge moving the gitlink: not run yet + a WARNING mentions squash" \
    eval 'test ! -s "$LAYOUT_RECORD" && grep -qi "squash" "$LT_SB/sq.err"'

lt_check "post-merge parses under bash -n" bash -n "$LAYOUT_SRC_ROOT/scripts/hooks/post-merge"
lt_summary
