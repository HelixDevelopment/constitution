#!/usr/bin/env bash
# tests/layout/test_round4_hardening.sh — round-4 review fixes (I-A, I-B, I-C,
# m-A, m-B, m-C) of the §11.4.164 hook wiring. Real git, local bare upstreams,
# hooks installed by the REAL scripts/setup.sh.
#   I-A  the propagation lock is an exclusive create independent of coreutils:
#        N>=8 fresh contenders x >=20 rounds -> exactly one run per round;
#        legacy directory locks (dead / live owner), symlink and FIFO locks;
#   I-B  scripts/post_update_hook.sh STEP 4 (the REAL script) never touches a
#        hooks dir outside the repository (global core.hooksPath, symlinked
#        .git/hooks) unless CONSTITUTION_ALLOW_GLOBAL_HOOKS_PATH=1, and backs up
#        a differing local hook before replacing it;
#   I-C  setup.sh compares PHYSICAL paths: a symlinked .git/hooks or submodule
#        hooks dir pointing at a shared dir is refused (exit 1, nothing
#        written) unless --allow-global-hooks-path; the consumer is never put
#        outside the submodule's own git dir;
#   m-A  post-merge never sources code from the (possibly unverified) checkout;
#   m-B  setup.sh prints the "branch switch runs nothing" limitation;
#   m-C  post-merge's direct path ("checkout already equals NEW") refuses a
#        downgrade end to end (kills mutant X01).
# Test double (§11.4.289): scripts/post_update_hook.sh in the fake constitution
# is a recording stub (unit/gate-logic class). The I-B cases run the REAL
# post_update_hook.sh from a copy of LAYOUT_SRC_ROOT.
# Usage: bash tests/layout/test_round4_hardening.sh
LT_SUITE="round4_hardening"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

URL="$(lt_make_const_upstream r4)"
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
bump() {
    lt_bump_const_upstream r4
    lt_git -C "$W/$REL" fetch -q origin
    lt_git -C "$W/$REL" checkout -q origin/main
    lt_git -C "$W" commit -q -am "bump constitution"
    lt_git -C "$W" push -q origin main
    git -C "$W/$REL" rev-parse HEAD
}
st() { git -C "$1" rev-parse --absolute-git-dir; }
hk() { printf '%s/post-checkout' "$(git -C "$1/$REL" rev-parse --path-format=absolute --git-path hooks)"; }
pending() { # -> NEWV OLDV; stamp written by a plain pull, checkout moved without hooks
    OLDV="$(git -C "$B/$REL" rev-parse HEAD)"
    NEWV="$(bump)"
    lt_git -C "$B" pull -q --no-rebase --no-recurse-submodules >/dev/null 2>&1
    lt_git -C "$B/$REL" fetch -q origin
    lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$NEWV"
    : > "$LAYOUT_RECORD"
}
write_stamp() { printf 'ROOT=%s\nREL=%s\nOLD=%s\nNEW=%s\n' "$(cd "$B" && pwd -P)" "$REL" "$OLDV" "$NEWV" > "$(st "$B")/constitution-pending-update"; }
pstart() { local s f; s="$(cat "/proc/$1/stat")"; s="${s##*) }"; read -r -a f <<<"$s"; printf '%s' "${f[19]}"; }
consume() { ( cd "$B/$REL" && timeout 60 bash "$(hk "$B")" x y 1 ) 2>"$LT_SB/consume.err"; }

# ============================================================================
# I-A: exclusive lock under contention (no stale lock; fresh contenders)
# ============================================================================
mkpair lk || lt_bad "fixture lk"
pending
LK="$(st "$B")/constitution-pending-update.lock"
HOOK="$(hk "$B")"
N=8; ROUNDS=20; bad_rounds=0; leftovers=0; worst=0
for r in $(seq 1 "$ROUNDS"); do
    : > "$LAYOUT_RECORD"; rm -f "$(st "$B")/constitution-applied-ref"; write_stamp
    GO="$LT_SB/go.$r"; pids=()
    for k in $(seq 1 "$N"); do
        ( cd "$B/$REL" && while [ ! -e "$GO" ]; do :; done
          LAYOUT_STUB_SLEEP=1 exec timeout 60 bash "$HOOK" x y 1 ) 2>"$LT_SB/race.$k.err" &
        pids+=("$!")
    done
    sleep 0.3; : > "$GO"; wait "${pids[@]}"
    c="$(calls)"; [ "$c" -gt "$worst" ] && worst="$c"
    [ "$c" = 1 ] || bad_rounds=$((bad_rounds + 1))
    if [ -e "$LK" ] || [ -L "$LK" ] || ls -d "$LK".* >/dev/null 2>&1; then leftovers=$((leftovers + 1)); fi
done
lt_check "I-A: $N fresh contenders x $ROUNDS rounds -> exactly one run every round (bad rounds=$bad_rounds, worst calls=$worst)" \
    test "$bad_rounds" = 0
lt_check "I-A: ... no lock or reclaim leftover after any round (rounds with leftovers=$leftovers)" test "$leftovers" = 0

reset_state() { : > "$LAYOUT_RECORD"; rm -f "$(st "$B")/constitution-applied-ref"; write_stamp; }
# legacy (pre-round-4) DIRECTORY lock forms
reset_state; sh -c 'exit 0' & dpid=$!; wait "$dpid"
mkdir "$LK"; printf 'PID=%s\nSTART=1\nNONCE=x\n' "$dpid" > "$LK/owner"
consume
lt_check "I-A legacy: directory lock with a dead owner -> reclaimed (WARNING), runs once, nothing left" \
    eval 'test "$(calls)" = 1 && grep -q "reclaimed a stale propagation lock" "$LT_SB/consume.err" && test ! -e "$LK" && ! ls -d "$LK".* >/dev/null 2>&1'
reset_state; sleep 300 & SL=$!; SLEEPERS+=("$SL")
mkdir "$LK"; printf 'PID=%s\nSTART=%s\nNONCE=x\n' "$SL" "$(pstart "$SL")" > "$LK/owner"
consume
lt_check "I-A legacy: directory lock with a LIVE owner -> never reclaimed, WARNING, stamp kept" \
    eval 'test "$(calls)" = 0 && grep -q "held by live pid $SL" "$LT_SB/consume.err" && test -d "$LK" && test -f "$(st "$B")/constitution-pending-update"'
safe_rm_rf "${LK:?}"
# new FILE lock forms
reset_state; printf 'PID=%s\nSTART=%s\nNONCE=y\n' "$SL" "$(pstart "$SL")" > "$LK"
consume
lt_check "I-A: file lock with a LIVE owner -> contention WARNING, nothing run, lock intact" \
    eval 'test "$(calls)" = 0 && grep -q "held by live pid $SL" "$LT_SB/consume.err" && grep -qx "NONCE=y" "$LK"'
rm -f "$LK"
reset_state; sh -c 'exit 0' & dpid=$!; wait "$dpid"
printf 'PID=%s\nSTART=1\nNONCE=z\n' "$dpid" > "$LK"
consume
lt_check "I-A: file lock with a dead owner -> reclaimed, runs once, released" \
    eval 'test "$(calls)" = 1 && grep -q "is dead" "$LT_SB/consume.err" && test ! -e "$LK"'
reset_state; : > "$LK"
consume
lt_check "I-A: fresh EMPTY file lock (being written) -> not reclaimed, WARNING" \
    eval 'test "$(calls)" = 0 && grep -q "WARNING: the propagation lock" "$LT_SB/consume.err" && test -f "$LK"'
touch -d '5 minutes ago' "$LK"
consume
lt_check "I-A: old EMPTY file lock -> reclaimed, runs once" \
    eval 'test "$(calls)" = 1 && test ! -e "$LK"'
reset_state; mkdir -p "$LT_SB/victim"; printf 'keep\n' > "$LT_SB/victim/owner"
ln -s "$LT_SB/victim/owner" "$LK"
consume
lt_check "I-A: symlink lock (to a regular file) -> renamed away, target untouched, runs once" \
    eval 'test "$(calls)" = 1 && test ! -L "$LK" && grep -qx keep "$LT_SB/victim/owner" && grep -q "symlink" "$LT_SB/consume.err"'
reset_state; mkfifo "$LT_SB/victim/fifo"; ln -s "$LT_SB/victim/fifo" "$LK"
consume; rc=$?
lt_check "I-A: symlink lock to a FIFO -> no hang (rc=$rc), reclaimed, runs once, FIFO untouched" \
    eval 'test "$rc" -ne 124 && test "$(calls)" = 1 && test -p "$LT_SB/victim/fifo" && test ! -L "$LK"'
reset_state; mkfifo "$LK"
consume; rc=$?
lt_check "I-A: a FIFO at the lock path -> no hang (rc=$rc), reclaimed, runs once" \
    eval 'test "$rc" -ne 124 && test "$(calls)" = 1 && test ! -e "$LK"'

# ============================================================================
# m-C: post-merge direct path refuses a downgrade (checkout already == NEW)
# ============================================================================
mkpair dg || lt_bad "fixture dg"
v1="$(git -C "$B/$REL" rev-parse HEAD)"
v2="$(bump)"
lt_git -C "$B" pull -q --recurse-submodules >/dev/null 2>&1
lt_check "m-C fixture: upgrade ran once and recorded v2 applied" \
    eval 'test "$(calls)" = 1 && grep -qx "REF=$v2" "$(st "$B")/constitution-applied-ref"'
: > "$LAYOUT_RECORD"
lt_git -C "$W/$REL" checkout -q "$v1"; lt_git -C "$W" commit -q -am "pin back to v1"; lt_git -C "$W" push -q origin main
lt_git -C "$B" fetch -q origin
lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$v1"   # checkout already at NEW (= v1)
lt_git -C "$B" merge -q --ff-only origin/main >/dev/null 2>"$LT_SB/dg.err"
lt_check "m-C: post-merge direct path, gitlink moved back to an OLDER commit -> NOT run, WARNING names the downgrade" \
    eval 'test "$(calls)" = 0 && grep -q "downgrade" "$LT_SB/dg.err" && grep -qF "CONSTITUTION_UPDATE_NEW_REF=$v1" "$LT_SB/dg.err"'
lt_check "m-C: ... applied ref stays v2" grep -qx "REF=$v2" "$(st "$B")/constitution-applied-ref"
# control (golden-FALSE): the same direct path with an UPGRADE runs once
v3="$(bump)"
lt_git -C "$B" fetch -q origin; lt_git -C "$B/$REL" fetch -q origin
lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$v3"
lt_git -C "$B" merge -q --ff-only origin/main >/dev/null 2>&1
lt_check "m-C control: direct path with an upgrade (v2 -> v3) runs once" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$v2 NEW=$v3" "$LAYOUT_RECORD"'

# ============================================================================
# m-A: post-merge never sources code from the checkout
# ============================================================================
mkpair ma || lt_bad "fixture ma"
MARK="$LT_SB/PWNED_LIB"
printf '\n: > %q\n' "$MARK" >> "$B/$REL/scripts/lib/constitution_layout.sh"
v2="$(bump)"
lt_git -C "$B" pull -q --no-rebase --no-recurse-submodules >/dev/null 2>"$LT_SB/ma.err"
lt_check "m-A: a hostile scripts/lib/constitution_layout.sh in the checkout is NOT sourced by post-merge" test ! -e "$MARK"
lt_check "m-A: ... post-merge still resolved the constitution and wrote the pending stamp" \
    eval 'grep -qx "NEW=$v2" "$(st "$B")/constitution-pending-update"'
lt_check "m-B/m-A: setup prints the branch-switch limitation and the setup self-run truth" \
    eval 'grep -q "runs NO hook" "$LT_SB/setup_ma.out" && grep -q "WITHOUT these checks" "$LT_SB/setup_ma.out"'

# ============================================================================
# I-C: setup.sh with a SYMLINKED hooks dir
# ============================================================================
mkshared() { SH="$LT_SB/shared_$1"; mkdir -p "$SH"; printf '#!/bin/sh\necho shared-%s\n' "$1" > "$SH/post-merge"; chmod +x "$SH/post-merge"; sh_sum="$(cat "$SH"/* | sha256sum)"; }
P="$LT_SB/symh"; lt_make_project "$P" "$URL" "$REL"; mkshared symh
safe_rm_rf "${P:?}/.git/hooks"; ln -s "$SH" "$P/.git/hooks"
: > "$LAYOUT_RECORD"
out="$( cd "$P" && bash "$REL/scripts/setup.sh" 2>&1 )"; rc=$?
lt_check "I-C: .git/hooks -> shared dir symlink -> setup refuses (rc=$rc == 1), names the physical dir" \
    eval 'test "$rc" -eq 1 && grep -qF "$SH" <<<"$out" && grep -q -- "--allow-global-hooks-path" <<<"$out"'
lt_check "I-C: ... shared dir untouched, no config written, nothing run" \
    eval 'test "$(cat "$SH"/* | sha256sum)" = "$sh_sum" && test "$(ls -A "$SH" | wc -l)" = 1 && test -z "$(git -C "$P" config --get constitution.autoPropagate)" && test "$(calls)" = 0'
out="$( cd "$P" && bash "$REL/scripts/setup.sh" --allow-global-hooks-path 2>&1 )"; rc=$?
lt_check "I-C: --allow-global-hooks-path -> installs post-merge into the shared dir (rc=$rc), backup in the common dir" \
    eval 'test "$rc" -eq 0 && cmp -s "$SH/post-merge" "$P/$REL/scripts/hooks/post-merge" && grep -rqs "shared-symh" "$P/.git/constitution-hook-backup"'

P="$LT_SB/symsub"; lt_make_project "$P" "$URL" "$REL"; mkshared symsub
SG="$(git -C "$P/$REL" rev-parse --absolute-git-dir)"
safe_rm_rf "${SG:?}/hooks"; ln -s "$SH" "$SG/hooks"
: > "$LAYOUT_RECORD"
out="$( cd "$P" && bash "$REL/scripts/setup.sh" 2>&1 )"; rc=$?
lt_check "I-C: submodule hooks dir -> shared dir symlink -> setup refuses (rc=$rc == 1), nothing written anywhere" \
    eval 'test "$rc" -eq 1 && test "$(cat "$SH"/* | sha256sum)" = "$sh_sum" && test "$(ls -A "$SH" | wc -l)" = 1 && test ! -e "$P/.git/hooks/post-merge" && test "$(calls)" = 0'
out="$( cd "$P" && bash "$REL/scripts/setup.sh" --allow-global-hooks-path 2>&1 )"; rc=$?
lt_check "I-C: ... with the flag: project post-merge installed, the consumer NOT put in the shared dir (rc=$rc)" \
    eval 'test "$rc" -eq 0 && cmp -s "$P/.git/hooks/post-merge" "$P/$REL/scripts/hooks/post-merge" && test ! -e "$SH/post-checkout" && grep -q "outside its own git dir" <<<"$out"'
# golden-FALSE: .git/hooks symlinked to a dir INSIDE the git dir is fine
P="$LT_SB/symin"; lt_make_project "$P" "$URL" "$REL"
mkdir -p "$P/.git/myhooks"; safe_rm_rf "${P:?}/.git/hooks"; ln -s myhooks "$P/.git/hooks"
( cd "$P" && bash "$REL/scripts/setup.sh" >"$LT_SB/symin.out" 2>&1 ); rc=$?
lt_check "I-C golden-FALSE: .git/hooks -> a dir inside .git -> accepted (rc=$rc), installed" \
    eval 'test "$rc" -eq 0 && test -x "$P/.git/myhooks/post-merge"'

# ============================================================================
# I-B: the REAL post_update_hook.sh STEP 4
# ============================================================================
RC="$LT_SB/realc"; mkdir -p "$RC"; lt_git init -q "$RC"
for p in scripts templates .claude-plugin plugins actions skills mcp Constitution.md CLAUDE.md AGENTS.md helix-deps.yaml; do
    [ -e "$LAYOUT_SRC_ROOT/$p" ] && cp -a "$LAYOUT_SRC_ROOT/$p" "$RC/$p"
done
find "$RC" -name __pycache__ -type d -prune -exec rm -r {} + 2>/dev/null
lt_git -C "$RC" add -A >/dev/null; lt_git -C "$RC" commit -q -m v1; RV1="$(git -C "$RC" rev-parse HEAD)"
printf '\n# trivial change\n' >> "$RC/scripts/hooks/post-merge"; lt_git -C "$RC" commit -q -am v2; RV2="$(git -C "$RC" rev-parse HEAD)"
lt_git clone -q --bare "$RC" "$LT_SB/realc.git"
mkreal() { # NAME -> P (project with the real constitution at RV2)
    P="$LT_SB/real_$1"; mkdir -p "$P"; lt_git init -q "$P"; printf 'x\n' > "$P/README.md"
    lt_git -C "$P" add .; lt_git -C "$P" commit -q -m i
    lt_git -C "$P" submodule add -q "file://$LT_SB/realc.git" "$REL" >/dev/null 2>&1
    lt_git -C "$P" commit -q -m add
    git -C "$P/$REL" checkout -q "$RV2"
}
runpu() { # [env...] -> rc, output in $LT_SB/pu.out
    ( cd "$P" && env HOME="$LT_SB/home" PROJECT_ROOT="$P" CONST_DIR="$P/$REL" CONSTITUTION_UPDATE_OLD_REF="$RV1" \
        CONSTITUTION_UPDATE_NEW_REF="$RV2" "$@" timeout 300 bash "$P/$REL/scripts/post_update_hook.sh" ) >"$LT_SB/pu.out" 2>&1
}
mkdir -p "$LT_SB/home"

mkreal local
printf '#!/bin/sh\necho USER-LOCAL-HOOK\n' > "$P/.git/hooks/post-merge"; chmod +x "$P/.git/hooks/post-merge"
runpu; rc=$?
bk="$(grep -rls 'USER-LOCAL-HOOK' "$P/.git/constitution-hook-backup" 2>/dev/null | head -1)"
lt_check "I-B local: differing user post-merge BACKED UP to <common-dir>/constitution-hook-backup before replace (rc=$rc)" \
    eval 'test -n "$bk" && cmp -s "$P/.git/hooks/post-merge" "$P/$REL/scripts/hooks/post-merge" && test -x "$P/.git/hooks/post-merge"'
runpu; rc=$?
n_bk="$(grep -rls 'USER-LOCAL-HOOK' "$P/.git/constitution-hook-backup" 2>/dev/null | wc -l)"
lt_check "I-B local: a re-run with the identical hook installed is a no-op (no new backup, n=$n_bk)" \
    eval 'test "$n_bk" = 1 && grep -q "post-merge unchanged" "$LT_SB/pu.out"'

mkreal symlink; mkshared real_sym
safe_rm_rf "${P:?}/.git/hooks"; ln -s "$SH" "$P/.git/hooks"
runpu; rc=$?
lt_check "I-B symlinked .git/hooks: shared dir NOT touched, WARNING names it (rc=$rc)" \
    eval 'test "$(cat "$SH"/* | sha256sum)" = "$sh_sum" && test "$(ls -A "$SH" | wc -l)" = 1 && grep -q "NOT installed" "$LT_SB/pu.out" && grep -qF "$SH" "$LT_SB/pu.out"'

mkreal global; mkshared real_glob
GC="$LT_SB/glob.gitconfig"; printf '[core]\n\thooksPath = %s\n' "$SH" > "$GC"
runpu GIT_CONFIG_GLOBAL="$GC"; rc=$?
lt_check "I-B global core.hooksPath: machine-wide dir NOT touched, WARNING says global scope (rc=$rc)" \
    eval 'test "$(cat "$SH"/* | sha256sum)" = "$sh_sum" && test "$(ls -A "$SH" | wc -l)" = 1 && grep -q "global scope" "$LT_SB/pu.out"'
runpu GIT_CONFIG_GLOBAL="$GC" CONSTITUTION_ALLOW_GLOBAL_HOOKS_PATH=1; rc=$?
lt_check "I-B global + CONSTITUTION_ALLOW_GLOBAL_HOOKS_PATH=1: installed there, the shared hook backed up in the project common dir" \
    eval 'cmp -s "$SH/post-merge" "$P/$REL/scripts/hooks/post-merge" && grep -rqs "shared-real_glob" "$P/.git/constitution-hook-backup"'

# round-6 A2: STEP 4 with a PROJECT_ROOT that is not the constitution's superproject
mkreal amb
OTH="$LT_SB/other_amb"; lt_git init -q "$OTH"
runpu PROJECT_ROOT="$OTH"; rc=$?
lt_check "A2 (all steps): PROJECT_ROOT naming another repo -> ignored with a WARNING, no hook written there, the owner gets it (rc=$rc)" \
    eval 'test ! -e "$OTH/.git/hooks/post-merge" && grep -q "ignoring the ambient PROJECT_ROOT=$OTH" "$LT_SB/pu.out" && test -x "$P/.git/hooks/post-merge"'

lt_check "post-merge parses" bash -n "$LAYOUT_SRC_ROOT/scripts/hooks/post-merge"
lt_check "consumer parses" bash -n "$LAYOUT_SRC_ROOT/scripts/hooks/constitution-submodule-post-checkout"
lt_summary
