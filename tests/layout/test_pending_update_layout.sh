#!/usr/bin/env bash
# tests/layout/test_pending_update_layout.sh — §11.4.164 propagation in the REAL
# `git pull` flows (round-2 I-1), both layouts.
#
# git runs the parent's post-merge BEFORE it updates submodules (measured, git
# 2.53.0), so post-merge alone always saw the stale checkout. These tests drive
# REAL `git pull --recurse-submodules`, `git -c submodule.recurse=true pull`,
# plain `git pull` + `git submodule update`, a conflict-resolved merge, and a
# deinit'd submodule, against local bare upstreams, with the hooks installed
# by the REAL scripts/setup.sh, and assert the (recording-stub) post-update
# hook ran EXACTLY ONCE with the right OLD/NEW gitlink range.
# Test double (§11.4.289): scripts/post_update_hook.sh in the fake constitution
# is a recording stub (unit/gate-logic class); nothing here proves the real
# post-update hook works.
# Usage: bash tests/layout/test_pending_update_layout.sh
LT_SUITE="pending_update_layout"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

URL="$(lt_make_const_upstream pu)"
export LAYOUT_RECORD="$LT_SB/record.txt"
calls() { grep -c '^CALLED ' "$LAYOUT_RECORD" 2>/dev/null || true; }

# mkpair NAME REL -> sets W (writer clone) PB (bare) B (reader clone, setup run)
mkpair() {
    local name="$1" rel="$2"
    W="$LT_SB/w_$name"; PB="$LT_SB/$name.proj.git"; B="$LT_SB/b $name"
    lt_make_project "$W" "$URL" "$rel" || return 1
    lt_git clone -q --bare "$W" "$PB"
    lt_git -C "$W" remote add origin "file://$PB"
    lt_git -C "$W" fetch -q origin
    lt_git -C "$W" branch -q -u origin/main
    lt_git clone -q --recurse-submodules "file://$PB" "$B" || return 1
    : > "$LAYOUT_RECORD"
    ( cd "$B" && bash "$rel/scripts/setup.sh" >"$LT_SB/setup_$name.out" 2>&1 ) || return 1
    : > "$LAYOUT_RECORD"
}
# bump REL -> new upstream constitution commit, gitlink bumped + pushed by W; prints new sha
bump() {
    local rel="$1"
    lt_bump_const_upstream pu
    lt_git -C "$W/$rel" fetch -q origin
    lt_git -C "$W/$rel" checkout -q origin/main
    lt_git -C "$W" commit -q -am "bump constitution"
    lt_git -C "$W" push -q origin main
    git -C "$W/$rel" rev-parse HEAD
}
common() { git -C "$1" rev-parse --path-format=absolute --git-common-dir; }

for rel in submodules/constitution constitution; do
    t="$(printf '%s' "$rel" | tr / _)"
    # --- 1. git pull --recurse-submodules (fast-forward with a gitlink bump)
    mkpair "rec_$t" "$rel" || { lt_bad "[$rel] fixture rec"; continue; }
    v1="$(git -C "$B/$rel" rev-parse HEAD)"
    lt_check "[$rel] setup installed the consumer as the SUBMODULE's post-checkout (executable)" \
        test -x "$(git -C "$B/$rel" rev-parse --path-format=absolute --git-path hooks)/post-checkout"
    lt_check "[$rel] setup recorded the applied ref = v1" \
        grep -qx "REF=$v1" "$(common "$B")/constitution-applied-ref"
    v2="$(bump "$rel")"
    lt_git -C "$B" pull -q --recurse-submodules >"$LT_SB/p1.out" 2>"$LT_SB/p1.err"; rc=$?
    lt_check "[$rel] pull --recurse-submodules exits 0 (rc=$rc)" test "$rc" -eq 0
    lt_check "[$rel] pull --recurse-submodules: checkout reached v2" test "$(git -C "$B/$rel" rev-parse HEAD)" = "$v2"
    lt_check "[$rel] pull --recurse-submodules: post-update ran EXACTLY once (got $(calls))" test "$(calls)" = 1
    lt_check "[$rel] pull --recurse-submodules: OLD=v1 NEW=v2 handed over" grep -qF " OLD=$v1 NEW=$v2" "$LAYOUT_RECORD"
    lt_check "[$rel] pull --recurse-submodules: PROJECT_ROOT=<project>, run from the project root" \
        grep -qF "CALLED PROJECT_ROOT=$B CONST_DIR=$B/$rel PWD=$B OLD=" "$LAYOUT_RECORD"
    lt_check "[$rel] pull --recurse-submodules: stamp consumed" test ! -e "$(common "$B")/constitution-pending-update"
    lt_check "[$rel] pull --recurse-submodules: applied ref = v2" grep -qx "REF=$v2" "$(common "$B")/constitution-applied-ref"
    lt_git -C "$B" submodule update -q 2>/dev/null
    lt_git -C "$B" pull -q --recurse-submodules >/dev/null 2>&1
    lt_check "[$rel] re-update / re-pull: still exactly one run (got $(calls))" test "$(calls)" = 1

    # --- 2. git -c submodule.recurse=true pull
    : > "$LAYOUT_RECORD"
    v3="$(bump "$rel")"
    lt_git -C "$B" -c submodule.recurse=true pull -q >/dev/null 2>&1; rc=$?
    lt_check "[$rel] -c submodule.recurse=true pull: rc=0, ran once with OLD=v2 NEW=v3 (calls=$(calls))" \
        eval 'test "$rc" -eq 0 && test "$(calls)" = 1 && grep -qF " OLD=$v2 NEW=$v3" "$LAYOUT_RECORD"'

    # --- 3. plain git pull (no recurse) twice, then git submodule update
    : > "$LAYOUT_RECORD"
    v4="$(bump "$rel")"
    lt_git -C "$B" pull -q --no-recurse-submodules >/dev/null 2>"$LT_SB/p3.err"; rc=$?
    st="$(common "$B")/constitution-pending-update"
    lt_check "[$rel] plain pull: rc=0, NOT run on the stale checkout" eval 'test "$rc" -eq 0 && test "$(calls)" = 0'
    lt_check "[$rel] plain pull: stamp written with OLD=v3 NEW=v4" eval 'grep -qx "OLD=$v3" "$st" && grep -qx "NEW=$v4" "$st"'
    lt_check "[$rel] plain pull: hint names the quoted 'cd' + 'git submodule update' command" \
        eval 'grep -qF "cd -- " "$LT_SB/p3.err" && grep -q "git submodule update" "$LT_SB/p3.err"'
    # the stamp, not the applied record, carries the earliest OLD: drop the
    # applied record so only the stamp can supply v3 (kills a "latest OLD" bug)
    mv "$(common "$B")/constitution-applied-ref" "$LT_SB/applied.keep"
    v5="$(bump "$rel")"
    lt_git -C "$B" pull -q --no-recurse-submodules >/dev/null 2>&1
    mv "$LT_SB/applied.keep" "$(common "$B")/constitution-applied-ref"
    lt_check "[$rel] second plain pull keeps the EARLIEST OLD (v3) and NEW=v5" eval 'grep -qx "OLD=$v3" "$st" && grep -qx "NEW=$v5" "$st"'
    lt_git -C "$B" submodule update -q >/dev/null 2>"$LT_SB/su.err"; rc=$?
    lt_check "[$rel] git submodule update: rc=0, ran once with OLD=v3 NEW=v5 (calls=$(calls))" \
        eval 'test "$rc" -eq 0 && test "$(calls)" = 1 && grep -qF " OLD=$v3 NEW=$v5" "$LAYOUT_RECORD"'
    lt_check "[$rel] git submodule update: stamp consumed" test ! -e "$st"

    # --- 4. conflict-resolved merge (post-merge is NOT invoked for the commit)
    : > "$LAYOUT_RECORD"
    printf 'mine\n' > "$B/conf.txt"; lt_git -C "$B" add conf.txt; lt_git -C "$B" commit -q -m mine
    printf 'theirs\n' > "$W/conf.txt"; lt_git -C "$W" add conf.txt; lt_git -C "$W" commit -q -m theirs
    v6="$(bump "$rel")"
    lt_git -C "$B" pull -q --no-rebase --no-recurse-submodules >/dev/null 2>&1; rc=$?
    lt_check "[$rel] conflicting pull stops (rc=$rc != 0), nothing run" eval 'test "$rc" -ne 0 && test "$(calls)" = 0'
    printf 'resolved\n' > "$B/conf.txt"; lt_git -C "$B" add conf.txt
    lt_git -C "$B" commit -q --no-edit >/dev/null 2>&1
    lt_check "[$rel] conflict resolved + committed: still nothing run (post-merge not invoked)" test "$(calls)" = 0
    lt_git -C "$B" submodule update -q >/dev/null 2>&1
    lt_check "[$rel] conflict path: git submodule update runs it once with OLD=applied(v5) NEW=v6 (calls=$(calls))" \
        eval 'test "$(calls)" = 1 && grep -qF " OLD=$v5 NEW=$v6" "$LAYOUT_RECORD"'

    # --- 5. consumer missing: the post-merge hint is a loud WARNING with commands
    : > "$LAYOUT_RECORD"
    rm -f "$(git -C "$B/$rel" rev-parse --path-format=absolute --git-path hooks)/post-checkout"
    v7="$(bump "$rel")"
    lt_git -C "$B" pull -q --no-rebase --no-recurse-submodules >/dev/null 2>"$LT_SB/p5.err"
    lt_check "[$rel] consumer missing: WARNING says not installed + gives quoted cd and the env range" \
        eval 'grep -q "WARNING" "$LT_SB/p5.err" && grep -q "not installed" "$LT_SB/p5.err" && grep -qF "cd -- " "$LT_SB/p5.err" && grep -qF "CONSTITUTION_UPDATE_NEW_REF=$v7" "$LT_SB/p5.err"'
done

# --- 6. GIT_DIR exported into post-merge (N6): must still read the SUBMODULE's HEAD
mkpair gitdir submodules/constitution || lt_bad "fixture gitdir"
lt_git -C "$B/submodules/constitution" fetch -q origin
v1="$(git -C "$B/submodules/constitution" rev-parse HEAD)"
v2="$(bump submodules/constitution)"
lt_git -C "$B" fetch -q origin
lt_git -C "$B/submodules/constitution" fetch -q origin
lt_git -C "$B/submodules/constitution" checkout -q "$v2"     # checkout already at the new gitlink
: > "$LAYOUT_RECORD"
lt_git -C "$B" merge -q --ff-only origin/main >/dev/null 2>&1
: > "$LAYOUT_RECORD"
rm -f "$(common "$B")/constitution-applied-ref"
lt_git -C "$B" update-ref ORIG_HEAD HEAD~1
( cd "$B" && GIT_DIR="$B/.git" bash .git/hooks/post-merge 0 >/dev/null 2>"$LT_SB/gd.err" )
lt_check "GIT_DIR exported into post-merge: runs directly once with OLD=v1 NEW=v2 (no stale/stamp path)" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$v1 NEW=$v2" "$LAYOUT_RECORD" && test ! -e "$(common "$B")/constitution-pending-update"'

# --- 7. deinit'd submodule: unrelated merge silent; gitlink bump -> ONE warning
mkpair deinit submodules/constitution || lt_bad "fixture deinit"
cp "$B/.git/hooks/post-merge" "$LT_SB/pm.keep"
lt_git -C "$B" submodule deinit -q -f submodules/constitution >/dev/null 2>&1
printf 'u\n' > "$W/u.txt"; lt_git -C "$W" add u.txt; lt_git -C "$W" commit -q -m u; lt_git -C "$W" push -q origin main
lt_git -C "$B" pull -q --no-recurse-submodules >/dev/null 2>"$LT_SB/d1.err"
lt_check "deinit'd + unrelated pull: no hook output at all" eval '! grep -q "post-merge" "$LT_SB/d1.err"'
v9="$(bump submodules/constitution)"
lt_git -C "$B" pull -q --no-recurse-submodules >/dev/null 2>"$LT_SB/d2.err"
lt_check "deinit'd + gitlink bump: exactly ONE concise warning line naming the init command (got $(grep -c 'post-merge' "$LT_SB/d2.err"))" \
    eval 'test "$(grep -c "post-merge" "$LT_SB/d2.err")" = 1 && grep -q "no initialized checkout" "$LT_SB/d2.err" && grep -q "submodule update --init" "$LT_SB/d2.err"'

# --- 8. M-a: a tracked NON-gitlink dir at submodules/constitution carrying a
#        trojan resolver lib is never sourced, even when a real gitlink moved.
TJ="$LT_SB/trojan"; mkdir -p "$TJ"; lt_git init -q "$TJ"
mkdir -p "$TJ/submodules/constitution/scripts/lib"
printf '# fake\n' > "$TJ/submodules/constitution/Constitution.md"
printf 'touch %q\n' "$LT_SB/TROJAN_SOURCED" > "$TJ/submodules/constitution/scripts/lib/constitution_layout.sh"
lt_git -C "$TJ" add -A; lt_git -C "$TJ" commit -q -m trojan
# vendor/other is a NON-constitution repository (round 7: it used to be "$URL",
# a constitution, which the M-4 gitlink-first rule now — correctly — resolves).
NCW="$LT_SB/nonconst_w"; mkdir -p "$NCW"; lt_git init -q "$NCW"
printf 'a\n' > "$NCW/a.txt"; lt_git -C "$NCW" add a.txt; lt_git -C "$NCW" commit -q -m a
printf 'b\n' >> "$NCW/a.txt"; lt_git -C "$NCW" commit -q -am b
lt_git clone -q --bare "$NCW" "$LT_SB/nonconst.git"
lt_git -C "$TJ" submodule add -q "file://$LT_SB/nonconst.git" vendor/other >/dev/null 2>&1; lt_git -C "$TJ" commit -q -m other
lt_check "M-e fixture: vendor/other is a gitlink and NOT a constitution checkout" \
    eval 'test "$(git -C "$TJ" ls-files -s vendor/other | cut -c1-6)" = 160000 && test ! -e "$TJ/vendor/other/Constitution.md"'
# .gitmodules also lists a traversal and an absolute path to another trojan
mkdir -p "$LT_SB/evil/scripts/lib"; printf '# e\n' > "$LT_SB/evil/Constitution.md"
printf 'touch %q\n' "$LT_SB/TROJAN_SOURCED" > "$LT_SB/evil/scripts/lib/constitution_layout.sh"
lt_git -C "$TJ" config -f .gitmodules submodule.ev.path ../evil
lt_git -C "$TJ" config -f .gitmodules submodule.ab.path "$LT_SB/evil"
lt_git -C "$TJ" add .gitmodules; lt_git -C "$TJ" commit -q -m gm
first="$(git -C "$TJ/vendor/other" rev-list --max-parents=0 HEAD)"
lt_git -C "$TJ/vendor/other" checkout -q "$first"; lt_git -C "$TJ" commit -q -am pin
cp "$LT_SB/pm.keep" "$TJ/.git/hooks/post-merge"; chmod +x "$TJ/.git/hooks/post-merge"
lt_git -C "$TJ" checkout -q -b b; lt_git -C "$TJ/vendor/other" checkout -q origin/main
lt_git -C "$TJ" commit -q -am bump; lt_git -C "$TJ" checkout -q main
lt_git -C "$TJ" merge -q --no-ff -m m b >/dev/null 2>"$LT_SB/tj.err"
lt_check "M-a: non-gitlink submodules/constitution trojan lib NOT sourced; ../ and absolute .gitmodules paths NOT sourced" \
    test ! -e "$LT_SB/TROJAN_SOURCED"

lt_check "no constitution found + only a NON-constitution gitlink moved: no warning (M-e scope)" \
    eval '! grep -q "post-merge" "$LT_SB/tj.err"'
lt_check "consumer hook parses under bash -n" bash -n "$LAYOUT_SRC_ROOT/scripts/hooks/constitution-submodule-post-checkout"
lt_summary
