#!/usr/bin/env bash
# tests/layout/test_round6_hardening.sh — round-5 review findings (round-6 fix)
# of the §11.4.164 hook wiring. Real git, local bare upstreams, hooks installed
# by the REAL scripts/setup.sh.
#   L1  lock reclaim never takes over a LIVE holder's lock: the renamed lock's
#       owner record (PID/START/NONCE, or mtime for an owner-less lock) must be
#       the one judged stale, else it is put back (inode identity alone is not
#       enough: ext4 reuses a freed inode at once). Polarity control included.
#   L2  the holder re-checks the lock right before running (kills R04);
#   L3  lock_create is an EXCLUSIVE create even when another creator wins
#       right after the existence check (kills R05 / M77; unit class);
#   L4  post-merge's direct path takes the same lock: a live holder -> not run;
#   S1  a stamp with an abbreviated OLD id is ignored (kills R03);
#   P1  an ambient $PROJECT_ROOT naming ANOTHER repository never redirects
#       setup.sh (A2);
#   T1  a hooks dir holding TRACKED project files (core.hooksPath OR a .git/hooks
#       symlinked into the work tree; physical path) is WARNED about and the
#       committed hook backed up first (A3); untracked dirs: no warning;
#   D1  mid-migration tree (vendored plain submodules/constitution + legacy
#       gitlink constitution): post-merge and the layout lib pick the gitlink (A5);
#   C1  chi_hooks_dir_check resolves a symlinked HOOKS_DIR argument physically
#       (lib contract; kills M80 — git 2.53 already returns physical paths);
#   R11 post-merge direct path honours git config constitution.autoPropagate;
#   R20 MODE=gitdir refuses a work-tree hooks dir;
#   R21 a squash merge moving only another gitlink prints no constitution warning;
#   round 7: X1 put_back never replaces (file + legacy dir), X2 unknown OLD,
#       X3 upper-case opt-out (consumer + post-merge), X6 chi_under prefix
#       sibling, X8 lock-held stops (L4), X9 physical stamp ROOT, M-2 setup.sh
#       lock, M-3 lock-held post-merge records a stamp (L4).
# Test doubles (§11.4.289): post_update_hook.sh in the fake constitution is a
# recording stub; `mv`/`git` PATH wrappers pause or perturb the consumer at a
# chosen point (gate-logic class: they prove the lock logic, not propagation).
# Usage: bash tests/layout/test_round6_hardening.sh
LT_SUITE="round6_hardening"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

URL="$(lt_make_const_upstream r6)"
export LAYOUT_RECORD="$LT_SB/record.txt"; : > "$LAYOUT_RECORD"
calls() { grep -c '^CALLED ' "$LAYOUT_RECORD" 2>/dev/null || true; }
REL=submodules/constitution
SLEEPERS=()
trap 'for _p in "${SLEEPERS[@]:-}"; do [ -n "$_p" ] && kill "$_p" 2>/dev/null; done; lt_cleanup' EXIT
REAL_GIT="$(command -v git)"
REAL_MV="$(command -v mv)"

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
    lt_bump_const_upstream r6
    lt_git -C "$W/$REL" fetch -q origin
    lt_git -C "$W/$REL" checkout -q origin/main
    lt_git -C "$W" commit -q -am "bump constitution"
    lt_git -C "$W" push -q origin main
    git -C "$W/$REL" rev-parse HEAD
}
st() { git -C "$1" rev-parse --absolute-git-dir; }
hk() { printf '%s/post-checkout' "$(git -C "$1/$REL" rev-parse --path-format=absolute --git-path hooks)"; }
pstart() { local s f; s="$(cat "/proc/$1/stat")"; s="${s##*) }"; read -r -a f <<<"$s"; printf '%s' "${f[19]}"; }
pending() { # -> OLDV NEWV; stamp written by a plain pull, checkout moved without hooks
    OLDV="$(git -C "$B/$REL" rev-parse HEAD)"
    NEWV="$(bump)"
    lt_git -C "$B" pull -q --no-rebase --no-recurse-submodules >/dev/null 2>&1
    lt_git -C "$B/$REL" fetch -q origin
    lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$NEWV"
    : > "$LAYOUT_RECORD"
}
write_stamp() { # [OLD]
    printf 'ROOT=%s\nREL=%s\nOLD=%s\nNEW=%s\n' "$(cd "$B" && pwd -P)" "$REL" "${1:-$OLDV}" "$NEWV" \
        > "$(st "$B")/constitution-pending-update"
}
run_consumer() { # ERRFILE [PATH-prefix]
    ( cd "$B/$REL" && PATH="${2:+$2:}$PATH" timeout 120 bash "$(hk "$B")" x y 1 ) 2>"$1"
}
live_sleeper() { sleep 600 & DP=$!; SLEEPERS+=("$DP"); }

# ============================================================================
# L1: reclaim race — a LIVE holder's lock created in the reclaim window
# ============================================================================
mkpair ir || lt_bad "fixture ir"
pending; write_stamp
LK="$(st "$B")/constitution-pending-update.lock"
WR="$LT_SB/wrap_mv"; mkdir -p "$WR"; GATE="$LT_SB/gate"; GO="$LT_SB/go"
cat > "$WR/mv" <<EOF
#!/bin/bash
case "\$*" in *".lock.stale."*) : > "$GATE"; while [ ! -e "$GO" ]; do sleep 0.05; done ;; esac
exec $REAL_MV "\$@"
EOF
chmod +x "$WR/mv"
reset_l1() { : > "$LAYOUT_RECORD"; rm -f "$(st "$B")/constitution-applied-ref"; write_stamp; }
l1_case() { # MODE: reuse (freed inode may be reused) | keep (old inode kept allocated)
    rm -f "$GATE" "$GO" "$LK"; reset_l1
    printf 'PID=999999\nSTART=1\nNONCE=dead\n' > "$LK"
    local ino_old ino_new
    ino_old="$(ls -di "$LK" | awk '{print $1}')"
    run_consumer "$LT_SB/l1_$1.err" "$WR" & local cp=$!
    for _ in $(seq 1 600); do [ -e "$GATE" ] && break; sleep 0.05; done
    if [ "$1" = keep ]; then "$REAL_MV" "$LK" "$LT_SB/held_old_inode.$RANDOM"; else rm -f "$LK"; fi
    live_sleeper
    printf 'PID=%s\nSTART=%s\nNONCE=liveD\n' "$DP" "$(pstart "$DP")" > "$LK"
    ino_new="$(ls -di "$LK" | awk '{print $1}')"
    : > "$GO"; wait "$cp"
    echo "  L1[$1]: inode old=$ino_old new=$ino_new (reused: $([ "$ino_old" = "$ino_new" ] && echo yes || echo no)) calls=$(calls)"
    lt_check "L1[$1]: a LIVE holder's lock created in the reclaim window is never taken over -> hook NOT run" \
        test "$(calls)" = 0
    lt_check "L1[$1]: ... the live holder's lock is still in place (NONCE=liveD)" \
        grep -qx 'NONCE=liveD' "$LK"
    lt_check "L1[$1]: ... the stamp stays (propagation PENDING)" \
        test -f "$(st "$B")/constitution-pending-update"
    kill "$DP" 2>/dev/null; rm -f "$LK"
}
l1_case reuse
l1_case keep
# polarity control (golden-FALSE): nobody intervenes -> the dead lock IS reclaimed and the hook runs once
rm -f "$GATE" "$GO" "$LK"; reset_l1
printf 'PID=999999\nSTART=1\nNONCE=dead\n' > "$LK"; : > "$GO"
run_consumer "$LT_SB/l1c.err" "$WR"
lt_check "L1-control: a really dead lock is reclaimed (WARNING) and the hook runs exactly once" \
    eval 'test "$(calls)" = 1 && grep -q "reclaimed a stale propagation lock" "$LT_SB/l1c.err"'
lt_check "L1-control: ... and the lock is released afterwards" test ! -e "$LK"

# owner-less lock older than the stale age replaced by a FRESH owner-less one
# in the window (same empty content) -> mtime differs -> put back, not run
rm -f "$GATE" "$GO" "$LK"; reset_l1
: > "$LK"; touch -d '-10 minutes' "$LK"
run_consumer "$LT_SB/l1e.err" "$WR" & CP=$!
for _ in $(seq 1 600); do [ -e "$GATE" ] && break; sleep 0.05; done
rm -f "$LK"; : > "$LK"          # a creator just made it (noclobber window: empty)
: > "$GO"; wait "$CP"
lt_check "L1-ownerless: a FRESH owner-less lock made in the reclaim window is put back, hook NOT run" \
    eval 'test "$(calls)" = 0 && test -f "$LK"'
rm -f "$LK"

# ============================================================================
# L2: lock taken over between take_lock and the run -> not run (R04)
# ============================================================================
pending; write_stamp
GW="$LT_SB/wrap_git"; mkdir -p "$GW"
live_sleeper
cat > "$GW/git" <<EOF
#!/bin/bash
case "\$*" in *"merge-base --is-ancestor"*)
    [ -f "$LK" ] && printf 'PID=%s\nSTART=%s\nNONCE=thief\n' "$DP" "$(pstart "$DP")" > "$LK" ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$GW/git"
run_consumer "$LT_SB/l2.err" "$GW"
lt_check "L2: lock taken over after acquisition -> post-update hook NOT run, WARNING says so" \
    eval 'test "$(calls)" = 0 && grep -q "no longer this process" "$LT_SB/l2.err"'
lt_check "L2: ... the new holder's lock is left alone, stamp kept" \
    eval 'grep -qx "NONCE=thief" "$LK" && test -f "$(st "$B")/constitution-pending-update"'
kill "$DP" 2>/dev/null; rm -f "$LK"

# ============================================================================
# L3: lock_create exclusivity (unit class: the existence check is told the
#     path is free while another creator wins right after it)
# ============================================================================
H="$LAYOUT_SRC_ROOT/scripts/hooks/constitution-submodule-post-checkout"
FN="$LT_SB/lockfns.sh"
{ sed -n '/^kv() {/p' "$H"; sed -n '/^lock_path_taken() {/p;/^lock_create() {/,/^}/p;/^lock_is_mine() {/p' "$H"; } > "$FN"
lt_check "L3 fixture: lock functions extracted (lock_path_taken, lock_create, lock_is_mine, kv)" \
    eval 'grep -q "^lock_path_taken()" "$FN" && grep -q "^lock_create()" "$FN" && grep -q "^lock_is_mine()" "$FN"'
L3="$LT_SB/l3.lock"; rm -f "$L3"
( . "$FN"; LOCK="$L3"; MY_START=1; MY_NONCE=me
  lock_path_taken() { printf 'PID=1\nSTART=1\nNONCE=other\n' > "$LOCK"; return 1; }
  if lock_create; then echo ACQUIRED; else echo REFUSED; fi ) > "$LT_SB/l3.out" 2>&1
lt_check "L3: another creator wins right after the existence check -> lock_create REFUSES, their lock intact" \
    eval 'grep -qx REFUSED "$LT_SB/l3.out" && grep -qx "NONCE=other" "$L3"'
rm -f "$L3"
( . "$FN"; LOCK="$L3"; MY_START=1; MY_NONCE=me
  if lock_create; then echo ACQUIRED; else echo REFUSED; fi ) > "$LT_SB/l3c.out" 2>&1
lt_check "L3-control: a free path -> lock_create acquires (NONCE=me)" \
    eval 'grep -qx ACQUIRED "$LT_SB/l3c.out" && grep -qx "NONCE=me" "$L3"'

# ============================================================================
# L4: post-merge direct path ("checkout already equals NEW") takes the lock
# ============================================================================
mkpair pm || lt_bad "fixture pm"
LKP="$(st "$B")/constitution-pending-update.lock"
v2="$(bump)"
lt_git -C "$B" fetch -q origin
lt_git -C "$B/$REL" fetch -q origin
lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$v2"
live_sleeper
printf 'PID=%s\nSTART=%s\nNONCE=busy\n' "$DP" "$(pstart "$DP")" > "$LKP"
: > "$LAYOUT_RECORD"
lt_git -C "$B" merge -q --ff-only origin/main >/dev/null 2>"$LT_SB/l4.err"
lt_check "L4: post-merge direct path with a LIVE propagation lock -> NOT run, WARNING names the lock + re-run command" \
    eval 'test "$(calls)" = 0 && grep -qF "exists (another propagation is running" "$LT_SB/l4.err" && grep -qF "CONSTITUTION_UPDATE_NEW_REF=$v2" "$LT_SB/l4.err"'
lt_check "L4: ... it stops at the lock (never falls through to the later ownership check; kills X8)" \
    eval '! grep -q "no longer this hook" "$LT_SB/l4.err"'
lt_check "L4: ... the holder's lock is untouched and nothing is recorded as applied" \
    eval 'grep -qx "NONCE=busy" "$LKP" && ! grep -qx "REF=$v2" "$(st "$B")/constitution-applied-ref" 2>/dev/null'
lt_check "L4: ... a pending stamp is recorded (ROOT = physical project root, NEW=$v2) and the WARNING says so (M-3)" \
    eval 'grep -qx "NEW=$v2" "$(st "$B")/constitution-pending-update" && grep -qx "ROOT=$(cd "$B" && pwd -P)" "$(st "$B")/constitution-pending-update" && grep -q "pending stamp is recorded" "$LT_SB/l4.err"'
kill "$DP" 2>/dev/null; rm -f "$LKP" "$(st "$B")/constitution-pending-update"
# control: the same direct path with no lock runs once and releases the lock
v3="$(bump)"
lt_git -C "$B" fetch -q origin; lt_git -C "$B/$REL" fetch -q origin
lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$v3"
: > "$LAYOUT_RECORD"
lt_git -C "$B" merge -q --ff-only origin/main >/dev/null 2>"$LT_SB/l4c.err"
lt_check "L4-control: no lock -> the direct path runs once, records v3, leaves no lock behind" \
    eval 'test "$(calls)" = 1 && grep -qx "REF=$v3" "$(st "$B")/constitution-applied-ref" && test ! -e "$LKP"'

# R11: post-merge direct path honours the git-config opt-out
v4="$(bump)"
lt_git -C "$B" fetch -q origin; lt_git -C "$B/$REL" fetch -q origin
lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$v4"
lt_git -C "$B" config --local constitution.autoPropagate false
: > "$LAYOUT_RECORD"
lt_git -C "$B" merge -q --ff-only origin/main >/dev/null 2>"$LT_SB/r11.out"
lt_check "R11: direct path with git config constitution.autoPropagate=false -> NOT run, says disabled" \
    eval 'test "$(calls)" = 0 && grep -q "auto-propagation is disabled (git config" "$LT_SB/r11.out"'
lt_git -C "$B" config --local --unset constitution.autoPropagate

# R21: a squash merge that moves ANOTHER gitlink only -> no constitution warning
SQ="$LT_SB/squash"; lt_make_project "$SQ" "$URL" "$REL" || lt_bad "fixture squash"
( cd "$SQ" && bash "$REL/scripts/setup.sh" ) >/dev/null 2>&1
lt_git -C "$SQ" submodule add -q "$URL" vendor/other >/dev/null 2>&1; lt_git -C "$SQ" commit -q -m other
first="$(git -C "$SQ/vendor/other" rev-list --max-parents=0 HEAD)"
lt_git -C "$SQ/vendor/other" checkout -q "$first"; lt_git -C "$SQ" commit -q -am "pin other"
lt_git -C "$SQ" checkout -q -b sq; lt_git -C "$SQ/vendor/other" checkout -q origin/main
lt_git -C "$SQ" commit -q -am "bump other only"; lt_git -C "$SQ" checkout -q main
lt_git -C "$SQ" -c core.hooksPath=/dev/null submodule update -q 2>/dev/null
( cd "$SQ" && lt_git merge -q --squash sq ) >"$LT_SB/r21.out" 2>&1
lt_check "R21: squash merge moving only a NON-constitution gitlink -> no constitution squash warning" \
    eval '! grep -q "constitution gitlink change" "$LT_SB/r21.out"'

# ============================================================================
# S1: a stamp whose OLD is an abbreviated id is ignored (R03)
# ============================================================================
mkpair ab || lt_bad "fixture ab"
pending
rm -f "$(st "$B")/constitution-applied-ref"
write_stamp "${OLDV:0:12}"
run_consumer "$LT_SB/s1.err"
lt_check "S1: stamp OLD abbreviated (12 hex) and no applied record -> nothing run (never guesses a range)" \
    test "$(calls)" = 0
write_stamp
run_consumer "$LT_SB/s1c.err"
lt_check "S1-control: the same stamp with the full 40-hex OLD -> runs once" test "$(calls)" = 1

# ============================================================================
# P1: ambient PROJECT_ROOT naming another repository (A2)
# ============================================================================
mkpair pr || lt_bad "fixture pr"
OTHER="$LT_SB/other"; lt_git init -q "$OTHER"
( cd "$B" && PROJECT_ROOT="$OTHER" bash "$REL/scripts/setup.sh" ) >"$LT_SB/p1.out" 2>&1; rc=$?
lt_check "P1: ambient PROJECT_ROOT of another repo -> no hook installed there" \
    test ! -e "$OTHER/.git/hooks/post-merge"
lt_check "P1: ... setup used the checkout's own superproject and said it ignored the ambient value (rc=$rc)" \
    eval '[ "$rc" = 0 ] && grep -q "ignoring the ambient PROJECT_ROOT" "$LT_SB/p1.out" && grep -qF "Project root: $B" "$LT_SB/p1.out"'
( cd "$B" && bash "$REL/scripts/setup.sh" --project-root "$OTHER" ) >"$LT_SB/p1x.out" 2>&1; rc=$?
lt_check "P1-control: an EXPLICIT --project-root is honoured (rc=$rc)" \
    eval 'grep -qF "Project root: $OTHER" "$LT_SB/p1x.out"'
( cd "$B" && PROJECT_ROOT="$B" bash "$REL/scripts/setup.sh" ) >"$LT_SB/p1s.out" 2>&1
lt_check "P1-control: an ambient PROJECT_ROOT equal to the superproject -> no 'ignoring' note" \
    eval '! grep -q "ignoring the ambient" "$LT_SB/p1s.out"'

# ============================================================================
# T1: hooks dir holding TRACKED project files (A3) — symlink and hooksPath forms
#     WARN (a committed hooks dir is a deliberate project choice), back up first
# ============================================================================
mkpair th || lt_bad "fixture th"
mkdir -p "$B/.githooks"; printf '#!/bin/sh\necho PROJECT-OWN\n' > "$B/.githooks/post-merge"
lt_git -C "$B" add .githooks/post-merge; lt_git -C "$B" commit -q -m "own hook"
H0="$(sha256sum < "$B/.githooks/post-merge")"
CDIR="$(git -C "$B" rev-parse --path-format=absolute --git-common-dir)"
bk_own() { grep -rls 'PROJECT-OWN' "$CDIR/constitution-hook-backup" 2>/dev/null | head -1; }
HD="$(st "$B")/hooks"; "$REAL_MV" "$HD" "$HD.real"; ln -s ../.githooks "$HD"
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/t1a.out" 2>&1; rc=$?
lt_check "T1a: .git/hooks symlinked into a TRACKED work-tree dir (no core.hooksPath) -> WARNING says TRACKED (rc=$rc)" \
    grep -q "TRACKED" "$LT_SB/t1a.out"
lt_check "T1a: ... the committed project hook was backed up before it was replaced" \
    eval 'test -n "$(bk_own)" && [ "$(sha256sum < "$(bk_own)")" = "$H0" ]'
rm -f "$HD"; "$REAL_MV" "$HD.real" "$HD"
lt_git -C "$B" checkout -q -- .githooks
lt_git -C "$B" config --local core.hooksPath .githooks
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/t1b.out" 2>&1; rc=$?
lt_check "T1b: local core.hooksPath = TRACKED dir -> WARNING says TRACKED (rc=$rc)" grep -q "TRACKED" "$LT_SB/t1b.out"
lt_git -C "$B" config --local --unset core.hooksPath
# golden-FALSE: an UNTRACKED in-work-tree hooks dir, and the plain .git/hooks
mkdir -p "$B/.local_hooks"; lt_git -C "$B" config --local core.hooksPath .local_hooks
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/t1c.out" 2>&1; rc=$?
lt_check "T1c (golden-FALSE): untracked in-work-tree hooks dir -> rc=0, installed, NO tracked warning" \
    eval '[ "$rc" = 0 ] && [ -f "$B/.local_hooks/post-merge" ] && ! grep -q "TRACKED" "$LT_SB/t1c.out"'
lt_git -C "$B" config --local --unset core.hooksPath
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/t1d.out" 2>&1
lt_check "T1d (golden-FALSE): plain .git/hooks -> NO tracked warning" eval '! grep -q "TRACKED" "$LT_SB/t1d.out"'

# ============================================================================
# D1: mid-migration tree — vendored plain submodules/constitution + legacy gitlink (A5)
# ============================================================================
W2="$LT_SB/w_dual"; lt_make_project "$W2" "$URL" constitution || lt_bad "fixture dual"
mkdir -p "$W2/submodules"; cp -a "$W2/constitution" "$W2/submodules/constitution"
rm -f "$W2/submodules/constitution/.git"
lt_git -C "$W2" add submodules/constitution; lt_git -C "$W2" commit -q -m "vendored copy (migration)"
( cd "$W2" && bash constitution/scripts/setup.sh ) >"$LT_SB/d1s.out" 2>&1
lt_git -C "$W2" checkout -q -b side
lt_bump_const_upstream r6
lt_git -C "$W2/constitution" fetch -q origin; lt_git -C "$W2/constitution" checkout -q origin/main
lt_git -C "$W2" commit -q -am "bump legacy gitlink"; lt_git -C "$W2" checkout -q main
lt_git -C "$W2" -c core.hooksPath=/dev/null submodule update -q 2>/dev/null
: > "$LAYOUT_RECORD"
( cd "$W2" && lt_git merge -q --no-edit side ) >"$LT_SB/d1.out" 2>&1
lt_check "D1: legacy gitlink bump with a vendored plain submodules/ copy -> NOT 'no initialized checkout'" \
    eval '! grep -q "no initialized checkout" "$LT_SB/d1.out"'
lt_check "D1: ... post-merge resolved the GITLINK (constitution) and reported the update" \
    eval 'grep -q "Constitution submodule updated: .* (constitution)" "$LT_SB/d1.out"'
D1L="$( . "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh"; cl_find_in_project_no_override "$W2" )"
lt_check "D1-lib: cl_find_in_project_no_override prefers the gitlink layout in a mid-migration tree ($D1L)" \
    test "$D1L" = "$W2/constitution"
D1P="$LT_SB/plain_only"; mkdir -p "$D1P/submodules"; cp -a "$W2/submodules/constitution" "$D1P/submodules/constitution"
D1Q="$( . "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh"; cl_find_in_project_no_override "$D1P" )"
lt_check "D1-lib control: a plain (non-git) tree still resolves its vendored copy ($D1Q)" \
    test "$D1Q" = "$D1P/submodules/constitution"

# ============================================================================
# C1: chi_hooks_dir_check resolves a symlinked HOOKS_DIR argument (lib contract)
# ============================================================================
CR="$LT_SB/c1"; lt_git init -q "$CR/r"; mkdir -p "$CR/shared"
ln -s ../shared "$CR/r/.githooks"
( . "$LAYOUT_SRC_ROOT/scripts/lib/hook_install.sh"; chi_hooks_dir_check "$CR/r" "$CR/r/.githooks" repo ) \
    >/dev/null 2>&1; rc=$?
lt_check "C1: HOOKS_DIR given as an in-work-tree symlink to a shared dir -> refused (physical path)" test "$rc" = 1
( . "$LAYOUT_SRC_ROOT/scripts/lib/hook_install.sh"; chi_hooks_dir_check "$CR/r" "$CR/r/.git/hooks" repo ) \
    >/dev/null 2>&1; rc=$?
lt_check "C1-control: the repository's own .git/hooks -> allowed" test "$rc" = 0

# R20: gitdir mode never accepts a work-tree dir (consumer hook placement)
mkdir -p "$CR/r/wt_hooks"
( . "$LAYOUT_SRC_ROOT/scripts/lib/hook_install.sh"; chi_hooks_dir_check "$CR/r" "$CR/r/wt_hooks" gitdir ) >/dev/null 2>&1; rc=$?
lt_check "R20: MODE=gitdir with a hooks dir in the WORK TREE -> refused" test "$rc" = 1
( . "$LAYOUT_SRC_ROOT/scripts/lib/hook_install.sh"; chi_hooks_dir_check "$CR/r" "$CR/r/wt_hooks" repo ) >/dev/null 2>&1; rc=$?
lt_check "R20-control: the same dir in MODE=repo -> allowed" test "$rc" = 0

# ============================================================================
# Round 7 (reviewer survivors X1 X2 X3 X6 X8 X9, minor M-1..M-3)
# ============================================================================
# X1: put_back never replaces anything at LOCK (unit class: the function is
#     extracted from the consumer and driven directly)
PB="$LT_SB/pbfns.sh"; sed -n '/^put_back() {/,/^}/p' "$H" > "$PB"
lt_check "X1 fixture: put_back extracted" grep -q '^put_back()' "$PB"
X1D="$LT_SB/x1"; mkdir -p "$X1D"
printf 'NONCE=second\n' > "$X1D/u"; printf 'NONCE=third\n' > "$X1D/lock"
( . "$PB"; LOCK="$X1D/lock"; put_back "$X1D/u" ); rc=$?
lt_check "X1: file put back onto an EXISTING lock -> refused (rc=$rc), the existing lock kept, the renamed one kept" \
    eval '[ "$rc" != 0 ] && grep -qx NONCE=third "$X1D/lock" && grep -qx NONCE=second "$X1D/u"'
rm -f "$X1D/lock"
( . "$PB"; LOCK="$X1D/lock"; put_back "$X1D/u" ); rc=$?
lt_check "X1-control: file put back when the lock path is free -> restored (rc=$rc)" \
    eval '[ "$rc" = 0 ] && grep -qx NONCE=second "$X1D/lock" && test ! -e "$X1D/u"'
rm -f "$X1D/lock"; mkdir -p "$X1D/ud" "$X1D/lock"; printf 'PID=1\n' > "$X1D/ud/owner"
( . "$PB"; LOCK="$X1D/lock"; put_back "$X1D/ud" ); rc=$?
lt_check "X1-dir: legacy dir lock put back onto an EXISTING (empty) dir -> refused (rc=$rc), nothing moved into or over it (mv -T -n)" \
    eval '[ "$rc" != 0 ] && test -z "$(ls -A "$X1D/lock")" && test -f "$X1D/ud/owner"'
rmdir "$X1D/lock"
( . "$PB"; LOCK="$X1D/lock"; put_back "$X1D/ud" ); rc=$?
lt_check "X1-dir control: dir put back when the path is free -> restored (rc=$rc)" \
    eval '[ "$rc" = 0 ] && test -f "$X1D/lock/owner" && test ! -e "$X1D/ud"'

# X6: chi_under: a sibling with the same PREFIX (<wt>-hooks) is NOT inside <wt>
( . "$LAYOUT_SRC_ROOT/scripts/lib/hook_install.sh"; chi_under "$CR/r-hooks" "$CR/r" ); rc=$?
lt_check "X6: chi_under <wt>-hooks <wt> -> NOT inside (rc=$rc)" test "$rc" = 1
( . "$LAYOUT_SRC_ROOT/scripts/lib/hook_install.sh"; chi_under "$CR/r/hooks" "$CR/r" ); rc=$?
lt_check "X6-control: chi_under <wt>/hooks <wt> -> inside (rc=$rc)" test "$rc" = 0
mkdir -p "$CR/r-hooks"
( . "$LAYOUT_SRC_ROOT/scripts/lib/hook_install.sh"; chi_hooks_dir_check "$CR/r" "$CR/r-hooks" repo ) >/dev/null 2>&1; rc=$?
lt_check "X6-behaviour: a hooks dir next to the work tree (<wt>-hooks, shared-looking) is refused in repo mode (rc=$rc)" test "$rc" = 1

# X2 / X3 on the consumer, X9 on post-merge, M-2 on setup.sh
mkpair x7 || lt_bad "fixture x7"
pending
rm -f "$(st "$B")/constitution-applied-ref"
UNK="$(printf 'a%.0s' $(seq 1 40))"
write_stamp "$UNK"
run_consumer "$LT_SB/x2.err"
lt_check "X2: stamp OLD is a full id UNKNOWN to the submodule -> not run, says the upgrade cannot be proven" \
    eval 'test "$(calls)" = 0 && grep -q "is unknown here" "$LT_SB/x2.err"'
write_stamp
CONSTITUTION_AUTO_PROPAGATE=OFF run_consumer "$LT_SB/x3.err"
lt_check "X3: CONSTITUTION_AUTO_PROPAGATE=OFF (upper case) disables the consumer, stamp kept" \
    eval 'test "$(calls)" = 0 && grep -q "auto-propagation is disabled (CONSTITUTION_AUTO_PROPAGATE=OFF)" "$LT_SB/x3.err" && test -f "$(st "$B")/constitution-pending-update"'
run_consumer "$LT_SB/x3c.err"
lt_check "X3-control: the same pending update with the opt-out unset -> runs once" test "$(calls)" = 1
# X3 on the post-merge direct path
v5="$(bump)"
lt_git -C "$B" fetch -q origin; lt_git -C "$B/$REL" fetch -q origin
lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$v5"
: > "$LAYOUT_RECORD"
( export CONSTITUTION_AUTO_PROPAGATE=Off; lt_git -C "$B" merge -q --ff-only origin/main ) >"$LT_SB/x3p.out" 2>&1
lt_check "X3-post-merge: CONSTITUTION_AUTO_PROPAGATE=Off on the direct path -> not run, says disabled" \
    eval 'test "$(calls)" = 0 && grep -q "auto-propagation is disabled (CONSTITUTION_AUTO_PROPAGATE=Off)" "$LT_SB/x3p.out"'

# X9: the stamp's ROOT is the PHYSICAL project root even when git reports the
#     top level through a symlinked path (unit class: a PATH `git` wrapper
#     reports the logical path for `rev-parse --show-toplevel`)
LB="$LT_SB/link_x7"; ln -s "$B" "$LB"
# git puts its exec-path FIRST on a hook's PATH (measured: PATH=/usr/lib/git-core:...
# inside a hook, `git` -> /usr/lib/git-core/git), so a PATH wrapper never
# reaches post-merge. The wrapper therefore lives in a SHADOW exec-path (every
# git-core entry symlinked, `git` replaced) passed as GIT_EXEC_PATH, and it
# leaves a marker when it intercepts: no marker -> the test proved nothing.
XW="$LT_SB/wrap_top"; mkdir -p "$XW"
XEP="$(git --exec-path)"
for _xf in "$XEP"/*; do ln -s "$_xf" "$XW/${_xf##*/}"; done
rm -f "$XW/git"
cat > "$XW/git" <<EOF
#!/bin/bash
if [ "\$*" = "rev-parse --show-toplevel" ]; then printf 'x\n' >> "$LT_SB/x9.intercepted"; printf '%s\n' "$LB"; exit 0; fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$XW/git"
OLDV="$(git -C "$B/$REL" rev-parse HEAD)"; NEWV="$(bump)"
rm -f "$(st "$B")/constitution-pending-update" "$LT_SB/x9.intercepted"
( cd "$LB" && GIT_EXEC_PATH="$XW" PATH="$XW:$PATH" lt_git pull -q --no-rebase --no-recurse-submodules ) >"$LT_SB/x9.out" 2>&1
lt_check "X9 positive control: the wrapper really answered post-merge's --show-toplevel (inside the hook)" \
    test -s "$LT_SB/x9.intercepted"
lt_check "X9: git reports a symlinked top level -> the stamp ROOT is still the PHYSICAL project root" \
    eval 'grep -qx "ROOT=$(cd "$B" && pwd -P)" "$(st "$B")/constitution-pending-update" && grep -qx "NEW=$NEWV" "$(st "$B")/constitution-pending-update"'
lt_git -C "$B/$REL" fetch -q origin; lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$NEWV"
: > "$LAYOUT_RECORD"
run_consumer "$LT_SB/x9c.err"
lt_check "X9: ... and the consumer consumes it (runs once for NEW, stamp removed)" \
    eval 'test "$(calls)" = 1 && grep -q " NEW=$NEWV" "$LAYOUT_RECORD" && test ! -e "$(st "$B")/constitution-pending-update"'

# M-2: setup.sh takes the propagation lock; a busy lock -> post-update hook NOT run
LKS="$(st "$B")/constitution-pending-update.lock"
live_sleeper
printf 'PID=%s\nSTART=%s\nNONCE=busy\n' "$DP" "$(pstart "$DP")" > "$LKS"
: > "$LAYOUT_RECORD"
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/m2.out" 2>&1; rc=$?
lt_check "M-2: setup.sh with a LIVE propagation lock -> post-update hook NOT run, exit 1, the lock untouched (rc=$rc)" \
    eval '[ "$rc" = 1 ] && test "$(calls)" = 0 && grep -q "propagation lock" "$LT_SB/m2.out" && grep -qx NONCE=busy "$LKS"'
kill "$DP" 2>/dev/null; rm -f "$LKS"
: > "$LAYOUT_RECORD"
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/m2c.out" 2>&1; rc=$?
lt_check "M-2 control: no lock -> setup runs the hook once, exit 0, no lock left behind (rc=$rc)" \
    eval '[ "$rc" = 0 ] && test "$(calls)" = 1 && test ! -e "$LKS"'

lt_check "consumer hook parses under bash -n" bash -n "$H"
lt_check "post-merge parses under bash -n" bash -n "$LAYOUT_SRC_ROOT/scripts/hooks/post-merge"
lt_summary
