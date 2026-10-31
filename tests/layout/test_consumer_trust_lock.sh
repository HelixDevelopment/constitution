#!/usr/bin/env bash
# tests/layout/test_consumer_trust_lock.sh — round-3 review fixes of the
# §11.4.164 pending-update consumer (scripts/hooks/constitution-submodule-post-checkout)
# and the post-merge direct path:
#   I2  per-worktree stamp/applied state (two linked worktrees, end to end);
#   I3  lock states: empty+old, empty+fresh, dead pid, reused pid, live pid,
#       symlinked lock, two concurrent reclaimers (m6);
#   I5  reviewer mutants RM1 (CUR==LINK), RM2 (stamp ROOT), RM3 (live lock),
#       RM6 (file checkout $3), RM7 (CONSTITUTION_PENDING_UPDATE_RUNNING);
#   I6  trust model: hostile upstream commit (not on the default branch) not
#       run, reachable run, downgrade not run, opt-out (env + git config);
#   m1  branch switch to an older gitlink never runs the older hook, stale
#       applied ref harmless.
# Real git (local bare upstreams), hooks installed by the REAL setup.sh.
# Test double (§11.4.289): scripts/post_update_hook.sh in the fake
# constitution is a recording stub (unit/gate-logic class).
# Usage: bash tests/layout/test_consumer_trust_lock.sh
LT_SUITE="consumer_trust_lock"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

URL="$(lt_make_const_upstream tl)"
export LAYOUT_RECORD="$LT_SB/record.txt"
calls() { grep -c '^CALLED ' "$LAYOUT_RECORD" 2>/dev/null || true; }
REL=submodules/constitution
SLEEPERS=()
trap 'for _p in "${SLEEPERS[@]:-}"; do [ -n "$_p" ] && kill "$_p" 2>/dev/null; done; lt_cleanup' EXIT

mkpair() { # NAME -> W PB B (setup run in B)
    W="$LT_SB/w_$1"; PB="$LT_SB/$1.proj.git"; B="$LT_SB/b_$1"
    lt_make_project "$W" "$URL" "$REL" || return 1
    lt_git clone -q --bare "$W" "$PB"
    lt_git -C "$W" remote add origin "file://$PB"
    lt_git -C "$W" fetch -q origin
    lt_git -C "$W" branch -q -u origin/main
    lt_git clone -q --recurse-submodules "file://$PB" "$B" || return 1
    ( cd "$B" && bash "$REL/scripts/setup.sh" >"$LT_SB/setup_$1.out" 2>&1 ) || return 1
    : > "$LAYOUT_RECORD"
}
bump() { # new upstream constitution commit, gitlink bumped + pushed by W; prints new sha
    lt_bump_const_upstream tl
    lt_git -C "$W/$REL" fetch -q origin
    lt_git -C "$W/$REL" checkout -q origin/main
    lt_git -C "$W" commit -q -am "bump constitution"
    lt_git -C "$W" push -q origin main
    git -C "$W/$REL" rev-parse HEAD
}
st() { git -C "$1" rev-parse --absolute-git-dir; }           # per-worktree state dir
hk() { printf '%s/post-checkout' "$(git -C "$1/$REL" rev-parse --path-format=absolute --git-path hooks)"; }
consume() { # DIR [env...] — run the installed consumer as git would (branch checkout)
    local d="$1"; shift
    ( cd "$d/$REL" && env "$@" bash "$(hk "$d")" x y 1 ) 2>"$LT_SB/consume.err"
}
# pending STATE: plain pull leaves a stamp; then move the submodule to the new
# gitlink WITHOUT hooks (and fetch it, so the commit is on origin/main).
pending() { # -> sets NEWV OLDV
    OLDV="$(git -C "$B/$REL" rev-parse HEAD)"
    NEWV="$(bump)"
    lt_git -C "$B" pull -q --no-rebase --no-recurse-submodules >/dev/null 2>&1
    lt_git -C "$B/$REL" fetch -q origin
    lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$NEWV"
    : > "$LAYOUT_RECORD"
}
write_stamp() { # DIR OLD NEW [ROOT]
    printf 'ROOT=%s\nREL=%s\nOLD=%s\nNEW=%s\n' "${4:-$(cd "$1" && pwd -P)}" "$REL" "$2" "$3" > "$(st "$1")/constitution-pending-update"
}
pstart() { local s f; s="$(cat "/proc/$1/stat")"; s="${s##*) }"; read -r -a f <<<"$s"; printf '%s' "${f[19]}"; }
spawn_sleeper() { sleep 300 & SLEEPERS+=("$!"); SL="$!"; }

# ============================================================================
# I5: RM1 / RM6 / RM7 — the consumer only runs for a branch checkout AT the gitlink
# ============================================================================
mkpair rm || lt_bad "fixture rm"
pending
lt_git -C "$B/$REL" checkout -q "$OLDV"   # fires the real hook: CUR (old) != LINK
lt_check "RM1: checkout of the OLD commit (CUR != gitlink) does not run the old checkout's hook" test "$(calls)" = 0
lt_check "RM1: ... and does not mark the gitlink applied" eval '! grep -qx "REF=$NEWV" "$(st "$B")/constitution-applied-ref"'
lt_check "RM1: ... and the stamp stays pending" test -f "$(st "$B")/constitution-pending-update"
lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$NEWV"
printf 'x\n' >> "$B/$REL/Constitution.md"
lt_git -C "$B/$REL" checkout -q -- Constitution.md       # file checkout: $3 = 0
lt_check "RM6: a FILE checkout (\$3=0) never runs propagation" test "$(calls)" = 0
consume "$B" CONSTITUTION_PENDING_UPDATE_RUNNING=1
lt_check "RM7: CONSTITUTION_PENDING_UPDATE_RUNNING=1 -> not run" test "$(calls)" = 0
consume "$B"
lt_check "control: branch checkout at the gitlink runs it once with OLD=old NEW=new" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$OLDV NEW=$NEWV" "$LAYOUT_RECORD"'

# RM2: a stamp whose ROOT is another tree is ignored (OLD falls back to applied)
: > "$LAYOUT_RECORD"; rm -f "$(st "$B")/constitution-applied-ref"
FAKEOLD="$(git -C "$B/$REL" rev-list --max-parents=0 HEAD)"
write_stamp "$B" "$FAKEOLD" "$NEWV" "$LT_SB/some/other/root"
consume "$B"
lt_check "RM2: stamp with a foreign ROOT and no applied ref -> nothing run (never guesses)" test "$(calls)" = 0
printf 'REL=%s\nREF=%s\n' "$REL" "$OLDV" > "$(st "$B")/constitution-applied-ref"
consume "$B"
lt_check "RM2: foreign-ROOT stamp ignored, OLD taken from the applied ref" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$OLDV NEW=$NEWV" "$LAYOUT_RECORD"'

# ============================================================================
# I3 / m6: lock states
# ============================================================================
mkpair lk || lt_bad "fixture lk"
pending
LK="$(st "$B")/constitution-pending-update.lock"
reset_state() { : > "$LAYOUT_RECORD"; rm -f "$(st "$B")/constitution-applied-ref"; write_stamp "$B" "$OLDV" "$NEWV"; }
no_stale_left() { ! ls -d "$LK".stale.* >/dev/null 2>&1; }

reset_state; mkdir "$LK"; touch -d '5 minutes ago' "$LK"
consume "$B"
lt_check "lock: empty lock dir older than 60 s -> reclaimed (WARNING), propagation runs once, lock released" \
    eval 'test "$(calls)" = 1 && grep -q "reclaimed a stale propagation lock" "$LT_SB/consume.err" && test ! -e "$LK" && no_stale_left'

reset_state; mkdir "$LK"
consume "$B"
lt_check "lock: fresh empty lock dir -> NOT reclaimed, loud WARNING with the command, stamp stays" \
    eval 'test "$(calls)" = 0 && grep -q "WARNING: the propagation lock" "$LT_SB/consume.err" && grep -qF "CONSTITUTION_UPDATE_NEW_REF=$NEWV" "$LT_SB/consume.err" && test -f "$(st "$B")/constitution-pending-update" && test -d "$LK"'
rmdir "$LK"

reset_state; sh -c 'exit 0' & dpid=$!; wait "$dpid"
mkdir "$LK"; printf 'PID=%s\nSTART=1\nNONCE=x\n' "$dpid" > "$LK/owner"
consume "$B"
lt_check "lock: owner pid dead -> reclaimed, runs once" \
    eval 'test "$(calls)" = 1 && grep -q "is dead" "$LT_SB/consume.err" && test ! -e "$LK"'

reset_state; spawn_sleeper
mkdir "$LK"; printf 'PID=%s\nSTART=1\nNONCE=x\n' "$SL" > "$LK/owner"
consume "$B"
lt_check "lock: owner pid alive but REUSED (start time differs) -> reclaimed, runs once" \
    eval 'test "$(calls)" = 1 && grep -q "was reused" "$LT_SB/consume.err" && test ! -e "$LK"'

reset_state
mkdir "$LK"; printf 'PID=%s\nSTART=%s\nNONCE=x\n' "$SL" "$(pstart "$SL")" > "$LK/owner"
consume "$B"
lt_check "RM3: live holder (pid + start time match) -> NEVER reclaimed, WARNING, stamp stays, lock intact" \
    eval 'test "$(calls)" = 0 && grep -q "held by live pid $SL" "$LT_SB/consume.err" && test -f "$(st "$B")/constitution-pending-update" && grep -qx "PID=$SL" "$LK/owner"'
safe_rm_rf "${LK:?}"

reset_state; mkdir -p "$LT_SB/lock_target"; printf 'keep\n' > "$LT_SB/lock_target/keep"
ln -s "$LT_SB/lock_target" "$LK"
consume "$B"
lt_check "lock: symlinked lock -> renamed away (WARNING), target untouched, runs once" \
    eval 'test "$(calls)" = 1 && grep -q "it is a symlink" "$LT_SB/consume.err" && test ! -L "$LK" && test ! -e "$LK" && grep -qx keep "$LT_SB/lock_target/keep"'

ok_conc=0
for i in 1 2 3; do
    reset_state; sh -c 'exit 0' & dpid=$!; wait "$dpid"
    mkdir "$LK"; printf 'PID=%s\nSTART=1\nNONCE=x\n' "$dpid" > "$LK/owner"
    ( cd "$B/$REL" && LAYOUT_STUB_SLEEP=1 bash "$(hk "$B")" x y 1 ) 2>"$LT_SB/c1.err" &
    p1=$!
    ( cd "$B/$REL" && LAYOUT_STUB_SLEEP=1 bash "$(hk "$B")" x y 1 ) 2>"$LT_SB/c2.err" &
    p2=$!
    wait "$p1" "$p2"
    if [ "$(calls)" = 1 ] && test ! -e "$LK" && no_stale_left && \
       grep -q "reclaimed a stale" "$LT_SB/c1.err" "$LT_SB/c2.err"; then ok_conc=$((ok_conc + 1)); fi
done
lt_check "m6: two concurrent reclaimers of a stale lock -> exactly one run, no leftover lock (ok $ok_conc/3)" test "$ok_conc" = 3

# ============================================================================
# I6: trust model
# ============================================================================
mkpair tr || lt_bad "fixture tr"
SRCW="$LT_SB/src_tl"; BARE="$LT_SB/tl.git"
v1="$(git -C "$B/$REL" rev-parse HEAD)"
lt_git -C "$SRCW" checkout -q -b evil
printf 'evil\n' > "$SRCW/EVIL.txt"; lt_git -C "$SRCW" add -A; lt_git -C "$SRCW" commit -q -m evil
lt_git -C "$SRCW" push -q "$BARE" evil
EV="$(git -C "$SRCW" rev-parse HEAD)"
lt_git -C "$SRCW" checkout -q main
lt_git -C "$W/$REL" fetch -q origin; lt_git -C "$W/$REL" checkout -q "$EV"
lt_git -C "$W" commit -q -am "pin evil"; lt_git -C "$W" push -q origin main
: > "$LAYOUT_RECORD"
lt_git -C "$B" pull -q --recurse-submodules >/dev/null 2>"$LT_SB/ev.err"
lt_check "I6: hostile gitlink NOT reachable from upstream main -> checkout made, hook NOT run" \
    eval 'test "$(git -C "$B/$REL" rev-parse HEAD)" = "$EV" && test "$(calls)" = 0'
lt_check "I6: ... one WARNING says not reachable + the exact manual command" \
    eval 'grep -q "NOT reachable from the submodule" "$LT_SB/ev.err" && grep -qF "CONSTITUTION_UPDATE_NEW_REF=$EV" "$LT_SB/ev.err"'
lt_check "I6: ... the stamp stays pending, nothing recorded applied" \
    eval 'test -f "$(st "$B")/constitution-pending-update" && ! grep -qx "REF=$EV" "$(st "$B")/constitution-applied-ref"'
# the same commit, once merged upstream (reachable), is run
lt_git -C "$SRCW" merge -q --ff-only evil; lt_git -C "$SRCW" push -q "$BARE" main
lt_git -C "$B/$REL" fetch -q origin
consume "$B"
lt_check "I6: once reachable from origin/main -> run once with OLD=v1 NEW=evil" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$v1 NEW=$EV" "$LAYOUT_RECORD"'

# opt-out: env and git config
: > "$LAYOUT_RECORD"
v3="$(bump)"
CONSTITUTION_AUTO_PROPAGATE=off lt_git -C "$B" pull -q --recurse-submodules >/dev/null 2>"$LT_SB/oo.err"
lt_check "I6 opt-out: CONSTITUTION_AUTO_PROPAGATE=off -> not run, NOTE + manual command, stamp kept" \
    eval 'test "$(calls)" = 0 && grep -q "auto-propagation is disabled" "$LT_SB/oo.err" && grep -qF "CONSTITUTION_UPDATE_NEW_REF=$v3" "$LT_SB/oo.err" && test -f "$(st "$B")/constitution-pending-update"'
lt_git -C "$B" config constitution.autoPropagate false
consume "$B"
lt_check "I6 opt-out: git config constitution.autoPropagate false -> not run" test "$(calls)" = 0
lt_git -C "$B" config constitution.autoPropagate maybe
consume "$B"
lt_check "I6 opt-out: unreadable boolean value -> treated as disabled (not run)" test "$(calls)" = 0
lt_git -C "$B" config constitution.autoPropagate true
consume "$B"
lt_check "I6 opt-in again (true): runs once with OLD=evil NEW=v3" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$EV NEW=$v3" "$LAYOUT_RECORD"'

# ============================================================================
# I6(b) + m1: downgrade / branch switch to an older gitlink
# ============================================================================
: > "$LAYOUT_RECORD"
OLDC="$(git -C "$B" log --format=%H -n1 -- "$REL" | xargs -I{} git -C "$B" rev-parse '{}^')"
old_link="$(git -C "$B" rev-parse "$OLDC:$REL")"
lt_git -C "$B" checkout -q -b oldbr "$OLDC"
lt_git -C "$B" submodule update -q >/dev/null 2>"$LT_SB/dg.err"
lt_check "m1/I6: plain branch switch to an older gitlink + submodule update -> checkout moved, hook NOT run" \
    eval 'test "$(git -C "$B/$REL" rev-parse HEAD)" = "$old_link" && test "$(calls)" = 0'
lt_check "m1/I6: ... WARNING names the downgrade + the manual command" \
    eval 'grep -q "downgrade" "$LT_SB/dg.err" && grep -qF "CONSTITUTION_UPDATE_NEW_REF=$old_link" "$LT_SB/dg.err"'
lt_check "m1: applied ref stays at v3 (not rewritten to the older gitlink)" grep -qx "REF=$v3" "$(st "$B")/constitution-applied-ref"
lt_git -C "$B" checkout -q main
lt_git -C "$B" submodule update -q >/dev/null 2>&1
lt_git -C "$B" -c submodule.recurse=true checkout -q oldbr >/dev/null 2>&1
lt_git -C "$B" -c submodule.recurse=true checkout -q main >/dev/null 2>&1
lt_check "m1: back on main / recurse switches: still nothing run (stale applied ref harmless)" test "$(calls)" = 0
v4="$(bump)"
lt_git -C "$B" pull -q --recurse-submodules >/dev/null 2>&1
lt_check "m1: the next real upgrade runs once with OLD=v3 NEW=v4" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$v3 NEW=$v4" "$LAYOUT_RECORD"'

# post-merge DIRECT path applies the same trust rules
: > "$LAYOUT_RECORD"
lt_git -C "$SRCW" checkout -q -b evil2
printf 'evil2\n' > "$SRCW/EVIL2.txt"; lt_git -C "$SRCW" add -A; lt_git -C "$SRCW" commit -q -m evil2
lt_git -C "$SRCW" push -q "$BARE" evil2; EV2="$(git -C "$SRCW" rev-parse HEAD)"; lt_git -C "$SRCW" checkout -q main
lt_git -C "$W/$REL" fetch -q origin; lt_git -C "$W/$REL" checkout -q "$EV2"
lt_git -C "$W" commit -q -am "pin evil2"; lt_git -C "$W" push -q origin main
lt_git -C "$B" fetch -q origin
lt_git -C "$B/$REL" fetch -q origin
lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$EV2"
lt_git -C "$B" merge -q --ff-only origin/main >/dev/null 2>"$LT_SB/pmd.err"
lt_check "I6: post-merge direct path (checkout already at the hostile gitlink) -> NOT run, WARNING" \
    eval 'test "$(calls)" = 0 && grep -q "NOT reachable" "$LT_SB/pmd.err"'

# ============================================================================
# I2: two linked worktrees, end to end
# ============================================================================
mkpair wt || lt_bad "fixture wt"
WT2="$LT_SB/wt2"
lt_git -C "$B" worktree add -q -b wt2 "$WT2" origin/main >/dev/null 2>&1
lt_git -C "$WT2" submodule update -q --init >/dev/null 2>&1
( cd "$WT2" && bash "$REL/scripts/setup.sh" >"$LT_SB/setup_wt2.out" 2>&1 ); rc=$?
lt_check "I2: setup in the linked worktree exits 0 and installs its own submodule consumer (rc=$rc)" \
    eval 'test "$rc" -eq 0 && test -f "$(hk "$WT2")" && test "$(hk "$WT2")" != "$(hk "$B")"'
lt_check "I2: state lives in the worktree git dir (.git/worktrees/wt2), not the common dir" \
    eval 'test "$(st "$WT2")" != "$(git -C "$WT2" rev-parse --path-format=absolute --git-common-dir)" && test -f "$(st "$WT2")/constitution-applied-ref"'
w1="$(git -C "$WT2/$REL" rev-parse HEAD)"
: > "$LAYOUT_RECORD"
w2="$(bump)"
lt_git -C "$B" pull -q --recurse-submodules >/dev/null 2>&1
lt_check "I2: main worktree pull -> ran once (OLD=$w1 NEW=$w2)" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$w1 NEW=$w2" "$LAYOUT_RECORD"'
lt_git -C "$WT2" fetch -q origin
lt_git -C "$WT2" merge -q --ff-only origin/main >/dev/null 2>"$LT_SB/wt2.err"
lt_check "I2: the linked worktree's plain merge writes ITS stamp (worktree git dir), not the common dir's" \
    eval 'grep -qx "NEW=$w2" "$(st "$WT2")/constitution-pending-update" && test ! -e "$(st "$B")/constitution-pending-update"'
lt_git -C "$WT2" submodule update -q >/dev/null 2>>"$LT_SB/wt2.err"
lt_check "I2: the LINKED worktree's update is NOT skipped: runs once more there (calls=$(calls))" \
    eval 'test "$(calls)" = 2 && test "$(grep -c " CONST_DIR=$WT2/$REL .* NEW=$w2" "$LAYOUT_RECORD")" = 1'
lt_check "I2: each worktree recorded its own applied ref" \
    eval 'grep -qx "REF=$w2" "$(st "$B")/constitution-applied-ref" && grep -qx "REF=$w2" "$(st "$WT2")/constitution-applied-ref"'

lt_check "consumer hook parses under bash -n" bash -n "$LAYOUT_SRC_ROOT/scripts/hooks/constitution-submodule-post-checkout"
lt_summary
