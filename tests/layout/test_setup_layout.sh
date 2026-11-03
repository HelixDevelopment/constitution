#!/usr/bin/env bash
# tests/layout/test_setup_layout.sh — integration/e2e tests for scripts/setup.sh
# in BOTH layouts (real `git submodule add` from a local bare upstream).
#
# Asserts: PROJECT_ROOT resolves to the consumer root (never <project>/submodules);
# git hooks land in the project's real hooks dir (never in a submodule's);
# only real git hook names are installed; --project-root works in both forms;
# an existing consumer hook is backed up before it is replaced; re-runs are
# no-ops; 3 runs are identical; hostile paths and a read-only hooks dir are
# handled without silent success.
# Usage: bash tests/layout/test_setup_layout.sh
LT_SUITE="setup_layout"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

URL="$(lt_make_const_upstream setup)"
export LAYOUT_RECORD="$LT_SB/record.txt"

hooks_manifest() { ( cd "$1" && find . -path ./.constitution-hook-backup -prune -o -type f -print | LC_ALL=C sort | xargs -r sha256sum ); }

for rel in submodules/constitution constitution; do
    tag="[$rel]"
    P="$LT_SB/proj $(printf '%s' "$rel" | tr / _) \$x;&"
    lt_make_project "$P" "$URL" "$rel" || { lt_bad "$tag fixture: submodule add"; continue; }
    : > "$LAYOUT_RECORD"
    # a pre-existing consumer hook that must survive (backed up)
    printf '#!/bin/sh\necho consumer-own-hook\n' > "$P/.git/hooks/post-merge"
    chmod +x "$P/.git/hooks/post-merge"
    orig_sum="$(sha256sum < "$P/.git/hooks/post-merge")"

    out="$( cd "$P" && bash "$rel/scripts/setup.sh" 2>&1 )"; rc=$?
    lt_check "$tag setup.sh exits 0 (rc=$rc)" test "$rc" -eq 0
    [ "$rc" -eq 0 ] || printf '%s\n' "$out" | tail -5
    lt_check "$tag post-update hook called with PROJECT_ROOT=<project>" \
        grep -qF "CALLED PROJECT_ROOT=$P CONST_DIR=$P/$rel " "$LAYOUT_RECORD"
    lt_check "$tag post-merge installed in the PROJECT's .git/hooks" \
        cmp -s "$P/.git/hooks/post-merge" "$P/$rel/scripts/hooks/post-merge"
    lt_check "$tag nothing written to <project>/submodules/.git" test ! -e "$P/submodules/.git"
    sub_hooks="$(git -C "$P/$rel" rev-parse --path-format=absolute --git-path hooks)"
    lt_check "$tag submodule's own hooks dir untouched (no post-merge there)" test ! -e "$sub_hooks/post-merge"
    lt_check "$tag non-hook guard NOT copied into .git/hooks" test ! -e "$P/.git/hooks/guard-evidence-store-write.sh"
    lt_check "$tag test suite NOT copied into .git/hooks" test ! -e "$P/.git/hooks/test_fake_suite.sh"
    lt_check "$tag __pycache__ NOT copied into .git/hooks" test ! -e "$P/.git/hooks/__pycache__"
    lt_check "$tag post-merge in the PROJECT's hooks dir is EXECUTABLE" test -x "$P/.git/hooks/post-merge"
    lt_check "$tag consumer installed as the SUBMODULE's post-checkout, executable, same bytes" \
        eval 'test -x "$sub_hooks/post-checkout" && cmp -s "$sub_hooks/post-checkout" "$P/$rel/scripts/hooks/constitution-submodule-post-checkout"'
    lt_check "$tag consumer NOT installed in the PROJECT's hooks dir" test ! -e "$P/.git/hooks/post-checkout"
    lt_check "$tag no backup dir left inside the hooks dir (old location unused)" test ! -e "$P/.git/hooks/.constitution-hook-backup"
    bk="$(find "$P/.git/constitution-hook-backup" -type f -name post-merge 2>/dev/null | head -1)"
    lt_check "$tag existing consumer post-merge backed up before overwrite" \
        test -n "$bk" -a "$(sha256sum < "${bk:-/dev/null}")" = "$orig_sum"

    # idempotency: a second run changes nothing and makes no new backup
    m1="$(hooks_manifest "$P/.git/hooks")"
    nb1="$(find "$P/.git/constitution-hook-backup" -type f | wc -l)"
    ( cd "$P" && bash "$rel/scripts/setup.sh" >/dev/null 2>&1 ); rc2=$?
    m2="$(hooks_manifest "$P/.git/hooks")"
    nb2="$(find "$P/.git/constitution-hook-backup" -type f | wc -l)"
    lt_check "$tag idempotent re-run: exit 0, hooks identical, no new backup" \
        test "$rc2" -eq 0 -a "$m1" = "$m2" -a "$nb1" = "$nb2"
    ( cd "$P" && bash "$rel/scripts/setup.sh" >/dev/null 2>&1 )
    m3="$(hooks_manifest "$P/.git/hooks")"
    lt_check "$tag determinism: 3 runs -> identical hooks dir" test "$m1" = "$m3"

    # --project-root from an unrelated cwd, both flag forms
    : > "$LAYOUT_RECORD"
    ( cd "$LT_SB" && bash "$P/$rel/scripts/setup.sh" --project-root "$P" >/dev/null 2>&1 ); rc=$?
    lt_check "$tag --project-root DIR honoured (rc=$rc)" \
        eval 'test "$rc" -eq 0 && grep -qF "CALLED PROJECT_ROOT=$P " "$LAYOUT_RECORD"'
    : > "$LAYOUT_RECORD"
    ( cd "$LT_SB" && bash "$P/$rel/scripts/setup.sh" "--project-root=$P" >/dev/null 2>&1 ); rc=$?
    lt_check "$tag --project-root=DIR honoured (rc=$rc)" \
        eval 'test "$rc" -eq 0 && grep -qF "CALLED PROJECT_ROOT=$P " "$LAYOUT_RECORD"'
done

# --- B1: constitution vs project hook-name collision never loses a user hook --
# bk_has SUM DIR -> 0 iff some file under DIR has content sha256 SUM.
bk_has() {
    local want="$1" f
    while IFS= read -r -d '' f; do
        [ "$(sha256sum < "$f")" = "$want" ] && return 0
    done < <(find "$2" -type f -print0 2>/dev/null)
    return 1
}
for rel in submodules/constitution constitution; do
    tag="[collision $rel]"
    C="$LT_SB/coll $(printf '%s' "$rel" | tr / _)"
    lt_make_project "$C" "$URL" "$rel" || { lt_bad "$tag fixture"; continue; }
    mkdir -p "$C/scripts/git_hooks"
    printf '#!/bin/sh\necho project-post-merge\n' > "$C/scripts/git_hooks/post-merge"
    printf '#!/bin/sh\necho project-pre-commit\n' > "$C/scripts/git_hooks/pre-commit"
    printf '#!/bin/sh\necho user-own-post-merge\n' > "$C/.git/hooks/post-merge"
    chmod +x "$C/.git/hooks/post-merge"
    user_sum="$(sha256sum < "$C/.git/hooks/post-merge")"
    BK="$C/.git/constitution-hook-backup"
    out="$( cd "$C" && CONSTITUTION_SETUP_BACKUP_STAMP=20261029T000000Z bash "$rel/scripts/setup.sh" 2>&1 )"; rc=$?
    lt_check "$tag colliding project hook -> non-zero exit, never silent (rc=$rc)" test "$rc" -ne 0
    lt_check "$tag the collision is named in the output" grep -qi 'collision' <<<"$out"
    lt_check "$tag the user's own post-merge survives in a backup" bk_has "$user_sum" "$BK"
    lt_check "$tag the constitution post-merge is the installed one" \
        cmp -s "$C/.git/hooks/post-merge" "$C/$rel/scripts/hooks/post-merge"
    lt_check "$tag a non-colliding project hook is still installed" \
        cmp -s "$C/.git/hooks/pre-commit" "$C/scripts/git_hooks/pre-commit"
    n1="$(find "$BK" -type f | wc -l)"
    out2="$( cd "$C" && CONSTITUTION_SETUP_BACKUP_STAMP=20261029T000000Z bash "$rel/scripts/setup.sh" 2>&1 )"; rc2=$?
    n2="$(find "$BK" -type f | wc -l)"
    lt_check "$tag re-run: same refusal, no flip-flop, no new backup (rc=$rc2 backups $n1->$n2)" \
        eval 'test "$rc2" -ne 0 && test "$n1" = "$n2" && cmp -s "$C/.git/hooks/post-merge" "$C/$rel/scripts/hooks/post-merge"'
    lt_check "$tag re-run: the user's backup is still intact" bk_has "$user_sum" "$BK"
    # a second, DIFFERENT user hook backed up under the SAME stamp must not
    # overwrite the first backup (never-overwrite rule).
    printf '#!/bin/sh\necho user-second-hook\n' > "$C/.git/hooks/post-merge"
    user2_sum="$(sha256sum < "$C/.git/hooks/post-merge")"
    ( cd "$C" && CONSTITUTION_SETUP_BACKUP_STAMP=20261029T000000Z bash "$rel/scripts/setup.sh" >/dev/null 2>&1 )
    lt_check "$tag same-stamp second backup: first backup kept AND second saved" \
        eval 'bk_has "$user_sum" "$BK" && bk_has "$user2_sum" "$BK"'
done
# identical project hook == constitution hook is not a collision
CI="$LT_SB/coll_identical"; lt_make_project "$CI" "$URL" submodules/constitution
mkdir -p "$CI/scripts/git_hooks"; cp "$CI/submodules/constitution/scripts/hooks/post-merge" "$CI/scripts/git_hooks/post-merge"
( cd "$CI" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 ); rc=$?
lt_check "identical project hook (same bytes) is not a collision -> exit 0 (rc=$rc)" test "$rc" -eq 0
( cd "$CI" && CONSTITUTION_SETUP_BACKUP_STAMP='../../evil' bash submodules/constitution/scripts/setup.sh >"$LT_SB/stamp.out" 2>&1 ); rc=$?
lt_check "hostile backup stamp (../) refused with exit 2 (rc=$rc)" test "$rc" -eq 2

# --- M1: core.hooksPath pointing at a TRACKED directory is warned about ------
TH="$LT_SB/tracked_hookspath"; lt_make_project "$TH" "$URL" submodules/constitution
mkdir -p "$TH/.githooks"; printf '#!/bin/sh\nexit 0\n' > "$TH/.githooks/pre-commit"
lt_git -C "$TH" add .githooks; lt_git -C "$TH" commit -q -m hooks
lt_git -C "$TH" config core.hooksPath .githooks
out="$( cd "$TH" && bash submodules/constitution/scripts/setup.sh 2>&1 )"
lt_check "core.hooksPath at a tracked dir -> WARNING printed" grep -qi 'core.hooksPath.*tracked' <<<"$out"
UH="$LT_SB/untracked_hookspath"; lt_make_project "$UH" "$URL" submodules/constitution
lt_git -C "$UH" config core.hooksPath "$LT_SB/uh_hooks"
out="$( cd "$UH" && bash submodules/constitution/scripts/setup.sh 2>&1 )"; rc=$?
lt_check "I4: local core.hooksPath to a SHARED dir outside git dir + work tree -> refused (rc=$rc), nothing written" \
    eval 'test "$rc" -eq 1 && grep -q "shared hooks dir" <<<"$out" && test ! -e "$LT_SB/uh_hooks/post-merge"'
out="$( cd "$UH" && bash submodules/constitution/scripts/setup.sh --allow-global-hooks-path 2>&1 )"; rc=$?
lt_check "I4: ... --allow-global-hooks-path installs there (rc=$rc), no tracked-dir warning (false-positive guard)" \
    eval 'test "$rc" -eq 0 && test -x "$LT_SB/uh_hooks/post-merge" && ! grep -qi "core.hooksPath.*tracked" <<<"$out"'

# --- round 2, I-3/I-5: link-safe backups under the git common dir ------------
S="$LT_SB/symlinked hook"; lt_make_project "$S" "$URL" submodules/constitution
CANARY="$LT_SB/outside-secret.txt"
printf 'CANARY-SECRET-%s\n' "$$" > "$CANARY"; can_sum="$(sha256sum < "$CANARY")"
ln -s "$CANARY" "$S/.git/hooks/post-merge"
( cd "$S" && bash submodules/constitution/scripts/setup.sh >"$LT_SB/sym.out" 2>&1 ); rc=$?
SBK="$S/.git/constitution-hook-backup"
sl="$(find "$SBK" -type l -name post-merge 2>/dev/null | head -1)"
lt_check "symlinked hook: setup exits 0 (rc=$rc)" test "$rc" -eq 0
lt_check "symlinked hook: backed up AS A LINK with the same target" \
    eval 'test -n "$sl" && test "$(readlink "$sl")" = "$CANARY"'
lt_check "symlinked hook: canary content appears in NO backup file" \
    eval '! find "$SBK" -type f -exec grep -l "CANARY-SECRET" {} + 2>/dev/null | grep -q .'
lt_check "symlinked hook: canary untouched" test "$(sha256sum < "$CANARY")" = "$can_sum"
lt_check "symlinked hook: replaced by the constitution post-merge (regular file, executable)" \
    eval 'test ! -L "$S/.git/hooks/post-merge" && test -x "$S/.git/hooks/post-merge" && cmp -s "$S/.git/hooks/post-merge" "$S/submodules/constitution/scripts/hooks/post-merge"'

DG="$LT_SB/dangling"; lt_make_project "$DG" "$URL" submodules/constitution
ln -s "$LT_SB/does-not-exist" "$DG/.git/hooks/post-merge"
( cd "$DG" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 ); rc=$?
dl="$(find "$DG/.git/constitution-hook-backup" -type l -name post-merge 2>/dev/null | head -1)"
lt_check "dangling symlink hook: recorded as a link (target kept), then replaced (rc=$rc)" \
    eval 'test "$rc" -eq 0 && test "$(readlink "$dl")" = "$LT_SB/does-not-exist" && test -x "$DG/.git/hooks/post-merge"'

MD="$LT_SB/modes"; lt_make_project "$MD" "$URL" submodules/constitution
printf '#!/bin/sh\necho mine\n' > "$MD/.git/hooks/post-merge"; chmod 0750 "$MD/.git/hooks/post-merge"
( cd "$MD" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 )
mb="$(find "$MD/.git/constitution-hook-backup" -type f -name post-merge | head -1)"
lt_check "regular hook backup keeps its mode (0750)" test "$(stat -c %a "${mb:-/dev/null}")" = 750

UR="$LT_SB/unreadable"; lt_make_project "$UR" "$URL" submodules/constitution
printf '#!/bin/sh\necho private\n' > "$UR/.git/hooks/post-merge"; chmod 000 "$UR/.git/hooks/post-merge"
( cd "$UR" && bash submodules/constitution/scripts/setup.sh >"$LT_SB/ur.out" 2>&1 ); rc=$?
chmod 0700 "$UR/.git/hooks/post-merge"
lt_check "unreadable hook: backup fails -> setup refuses (rc=$rc != 0), original left in place" \
    eval 'test "$rc" -ne 0 && grep -q "echo private" "$UR/.git/hooks/post-merge" && grep -q "NOT replaced" "$LT_SB/ur.out"'

BF="$LT_SB/backup_ro"; lt_make_project "$BF" "$URL" submodules/constitution
printf '#!/bin/sh\necho keepme\n' > "$BF/.git/hooks/post-merge"
mkdir -p "$BF/.git/constitution-hook-backup"; chmod a-w "$BF/.git/constitution-hook-backup"
( cd "$BF" && CONSTITUTION_SETUP_BACKUP_STAMP=s1 bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 ); rc=$?
chmod u+w "$BF/.git/constitution-hook-backup"
lt_check "backup dir not writable: setup refuses (rc=$rc != 0), original hook left in place" \
    eval 'test "$rc" -ne 0 && grep -q keepme "$BF/.git/hooks/post-merge"'

FF="$LT_SB/fifo"; lt_make_project "$FF" "$URL" submodules/constitution
mkfifo "$FF/.git/hooks/post-merge"
( cd "$FF" && timeout 60 bash submodules/constitution/scripts/setup.sh >"$LT_SB/ff.out" 2>&1 ); rc=$?
lt_check "FIFO hook: refused without blocking (rc=$rc, not 124), FIFO left in place" \
    eval 'test "$rc" -ne 0 && test "$rc" -ne 124 && test -p "$FF/.git/hooks/post-merge" && grep -q "not a regular file" "$LT_SB/ff.out"'

THB="$LT_SB/tracked_hookspath_backup"; lt_make_project "$THB" "$URL" submodules/constitution
mkdir -p "$THB/.githooks"; printf '#!/bin/sh\necho tracked-own\n' > "$THB/.githooks/post-merge"
lt_git -C "$THB" add .githooks; lt_git -C "$THB" commit -q -m hooks
lt_git -C "$THB" config core.hooksPath .githooks
( cd "$THB" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 )
lt_check "core.hooksPath -> tracked dir: backup lives under .git/constitution-hook-backup" \
    eval 'find "$THB/.git/constitution-hook-backup" -type f -name post-merge | xargs -r grep -l tracked-own | grep -q .'
lt_check "core.hooksPath -> tracked dir: NO backup anywhere in the work tree" \
    eval '! find "$THB" -path "$THB/.git" -prune -o -name "*constitution-hook-backup*" -print | grep -q .'

# setup.sh consumes a matching pending stamp (OLD/NEW handed over, then removed)
ST="$LT_SB/stamp_consume"; lt_make_project "$ST" "$URL" submodules/constitution
sh_head="$(git -C "$ST/submodules/constitution" rev-parse HEAD)"
old_fake="$(printf '%040d' 7 | tr 0 a)"
printf 'ROOT=%s\nREL=submodules/constitution\nOLD=%s\nNEW=%s\n' "$(cd "$ST" && pwd -P)" "$old_fake" "$sh_head" > "$ST/.git/constitution-pending-update"
: > "$LAYOUT_RECORD"
( cd "$ST" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 ); rc=$?
lt_check "setup consumes a matching pending stamp: OLD/NEW handed to the post-update hook, stamp removed (rc=$rc)" \
    eval 'test "$rc" -eq 0 && grep -qF " OLD=$old_fake NEW=$sh_head" "$LAYOUT_RECORD" && test ! -e "$ST/.git/constitution-pending-update"'
lt_check "setup records the applied ref" grep -qx "REF=$sh_head" "$ST/.git/constitution-applied-ref"

# --- usage errors are loud ---------------------------------------------------
P="$LT_SB/proj submodules_constitution \$x;&"
( cd "$P" && bash submodules/constitution/scripts/setup.sh --bogus >/dev/null 2>&1 ); rc=$?
lt_check "unknown flag -> exit 2 (rc=$rc)" test "$rc" -eq 2
( cd "$P" && bash submodules/constitution/scripts/setup.sh --project-root >/dev/null 2>&1 ); rc=$?
lt_check "--project-root without value -> exit 2 (rc=$rc)" test "$rc" -eq 2
( cd "$P" && bash submodules/constitution/scripts/setup.sh --project-root "$LT_SB/missing" >/dev/null 2>&1 ); rc=$?
lt_check "--project-root to a missing dir -> exit 2 (rc=$rc)" test "$rc" -eq 2
( cd "$P" && bash submodules/constitution/scripts/setup.sh --check-only >/dev/null 2>&1 ); rc=$?
lt_check "--check-only -> exit 0" test "$rc" -eq 0

# --- chaos: non-git project root and a read-only hooks dir -------------------
NG="$LT_SB/not_git"; mkdir -p "$NG"
( cd "$LT_SB" && bash "$P/submodules/constitution/scripts/setup.sh" --project-root "$NG" >"$LT_SB/ng.out" 2>&1 ); rc=$?
lt_check "non-git project root -> non-zero + clear message (rc=$rc)" \
    eval 'test "$rc" -ne 0 && grep -qi "not a git work tree" "$LT_SB/ng.out"'
lt_check "non-git project root -> no .git dir fabricated" test ! -e "$NG/.git"
RO="$LT_SB/proj_ro"; lt_make_project "$RO" "$URL" submodules/constitution
printf '#!/bin/sh\necho mine\n' > "$RO/.git/hooks/post-merge"; chmod +x "$RO/.git/hooks/post-merge"
ro_sum="$(sha256sum < "$RO/.git/hooks/post-merge")"
chmod a-w "$RO/.git/hooks"
( cd "$RO" && bash submodules/constitution/scripts/setup.sh >"$LT_SB/ro.out" 2>&1 ); rc=$?
chmod u+w "$RO/.git/hooks"
lt_check "read-only hooks dir -> non-zero exit, never a silent success (rc=$rc)" test "$rc" -ne 0
lt_check "read-only hooks dir -> consumer hook intact" test "$(sha256sum < "$RO/.git/hooks/post-merge")" = "$ro_sum"


# --- round 3 ------------------------------------------------------------------
# I4: a GLOBAL core.hooksPath (machine-wide hooks dir) is never modified by default
GH="$LT_SB/global_hooks"; mkdir -p "$GH"
printf '#!/bin/sh\necho machine-wide-post-merge\n' > "$GH/post-merge"
printf '#!/bin/sh\necho machine-wide-post-checkout\n' > "$GH/post-checkout"
gh_sum="$(cat "$GH/post-merge" "$GH/post-checkout" | sha256sum)"
GCFG="$LT_SB/global.gitconfig"; printf '[core]\n\thooksPath = %s\n' "$GH" > "$GCFG"
GP="$LT_SB/global_proj"; lt_make_project "$GP" "$URL" submodules/constitution
: > "$LAYOUT_RECORD"
out="$( cd "$GP" && GIT_CONFIG_GLOBAL="$GCFG" bash submodules/constitution/scripts/setup.sh 2>&1 )"; rc=$?
lt_check "I4: global core.hooksPath -> setup refuses (rc=$rc == 1) with a clear message" \
    eval 'test "$rc" -eq 1 && grep -q "global scope" <<<"$out" && grep -q -- "--allow-global-hooks-path" <<<"$out"'
lt_check "I4: ... the machine-wide hooks dir is untouched (no replace, no new file, no backup)" \
    eval 'test "$(cat "$GH/post-merge" "$GH/post-checkout" | sha256sum)" = "$gh_sum" && test "$(ls -A "$GH" | wc -l)" = 2'
lt_check "I4: ... and nothing ran (post-update hook not called)" test "$(grep -c CALLED "$LAYOUT_RECORD")" = 0
out="$( cd "$GP" && GIT_CONFIG_GLOBAL="$GCFG" bash submodules/constitution/scripts/setup.sh --allow-global-hooks-path 2>&1 )"; rc=$?
lt_check "I4: --allow-global-hooks-path: installs post-merge there (rc=$rc), but NOT the consumer as the global post-checkout" \
    eval 'test "$rc" -eq 0 && cmp -s "$GH/post-merge" "$GP/submodules/constitution/scripts/hooks/post-merge" && grep -q machine-wide-post-checkout "$GH/post-checkout" && grep -q "outside its own git dir" <<<"$out"'

# I4: a GLOBAL relative core.hooksPath (resolves inside each repo) is still refused: scope, not location
GCFG2="$LT_SB/global2.gitconfig"; printf '[core]\n\thooksPath = .githooks\n' > "$GCFG2"
GR="$LT_SB/global_rel_proj"; lt_make_project "$GR" "$URL" submodules/constitution
out="$( cd "$GR" && GIT_CONFIG_GLOBAL="$GCFG2" bash submodules/constitution/scripts/setup.sh 2>&1 )"; rc=$?
lt_check "I4: global RELATIVE core.hooksPath -> refused by scope (rc=$rc), nothing written" \
    eval 'test "$rc" -eq 1 && grep -q "global scope" <<<"$out" && test ! -e "$GR/.githooks"'

# I1: post_update_hook.sh fails -> hooks STILL installed, clear message, exit 1 at the end
F1="$LT_SB/pu_fail"; lt_make_project "$F1" "$URL" submodules/constitution
f1_head="$(git -C "$F1/submodules/constitution" rev-parse HEAD)"
printf 'ROOT=%s\nREL=submodules/constitution\nOLD=\nNEW=%s\n' "$(cd "$F1" && pwd -P)" "$f1_head" > "$F1/.git/constitution-pending-update"
out="$( cd "$F1" && LAYOUT_STUB_EXIT=3 bash submodules/constitution/scripts/setup.sh 2>&1 )"; rc=$?
lt_check "I1: post-update hook fails -> setup exits 1 (rc=$rc) with a clear FAILED message" \
    eval 'test "$rc" -eq 1 && grep -q "post_update_hook.sh FAILED (exit 3)" <<<"$out" && grep -q "setup is INCOMPLETE" <<<"$out"'
lt_check "I1: ... the project post-merge IS installed anyway" cmp -s "$F1/.git/hooks/post-merge" "$F1/submodules/constitution/scripts/hooks/post-merge"
lt_check "I1: ... the submodule consumer IS installed anyway" \
    cmp -s "$F1/.git/modules/submodules/constitution/hooks/post-checkout" "$F1/submodules/constitution/scripts/hooks/constitution-submodule-post-checkout"
lt_check "I1: ... no applied ref recorded and the stamp kept (a re-run retries)" \
    eval 'test ! -e "$F1/.git/constitution-applied-ref" && test -f "$F1/.git/constitution-pending-update"'
( cd "$F1" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 ); rc=$?
lt_check "I1: re-run after the cause is fixed: exit 0, stamp consumed, applied recorded (rc=$rc)" \
    eval 'test "$rc" -eq 0 && test ! -e "$F1/.git/constitution-pending-update" && grep -qx "REF=$f1_head" "$F1/.git/constitution-applied-ref"'

# RM5: a stamp whose NEW is not the current checkout is NOT consumed
R5="$LT_SB/rm5"; lt_make_project "$R5" "$URL" submodules/constitution
r5_head="$(git -C "$R5/submodules/constitution" rev-parse HEAD)"
r5_other="$(printf '%040d' 9 | tr 0 b)"
printf 'ROOT=%s\nREL=submodules/constitution\nOLD=%s\nNEW=%s\n' "$(cd "$R5" && pwd -P)" "$r5_head" "$r5_other" > "$R5/.git/constitution-pending-update"
: > "$LAYOUT_RECORD"
( cd "$R5" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 )
lt_check "RM5: stamp NEW != checkout -> not consumed (no range handed over, stamp kept)" \
    eval 'grep -qF " OLD=<unset> NEW=<unset>" "$LAYOUT_RECORD" && grep -qx "NEW=$r5_other" "$R5/.git/constitution-pending-update"'

# RM4: setup run through a SYMLINKED project path still matches the stamp ROOT (physical)
R4="$LT_SB/rm4_real"; lt_make_project "$R4" "$URL" submodules/constitution
ln -s "$R4" "$LT_SB/rm4_link"
r4_head="$(git -C "$R4/submodules/constitution" rev-parse HEAD)"
printf 'ROOT=%s\nREL=submodules/constitution\nOLD=\nNEW=%s\n' "$(cd "$R4" && pwd -P)" "$r4_head" > "$R4/.git/constitution-pending-update"
( cd "$LT_SB/rm4_link" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 ); rc=$?
lt_check "RM4: setup via a symlinked project path consumes the stamp (physical ROOT match, rc=$rc)" \
    eval 'test "$rc" -eq 0 && test ! -e "$R4/.git/constitution-pending-update"'

# m3: a RELATIVE symlink hook -> backup link + <name>.link with the absolute target
RL="$LT_SB/rel_link"; lt_make_project "$RL" "$URL" submodules/constitution
printf '#!/bin/sh\necho mine\n' > "$RL/.git/hooks/my-post-merge.sh"
ln -s my-post-merge.sh "$RL/.git/hooks/post-merge"
( cd "$RL" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 ); rc=$?
rlb="$(find "$RL/.git/constitution-hook-backup" -type l -name post-merge | head -1)"
lt_check "m3: relative symlink backed up as a link (target as stored) + .link file (rc=$rc)" \
    eval 'test -n "$rlb" && test "$(readlink "$rlb")" = my-post-merge.sh && test -f "$rlb.link"'
lt_check "m3: .link records ABSOLUTE=<hooks dir>/my-post-merge.sh (an existing file) and the cp -P restore" \
    eval 'grep -qx "ABSOLUTE=$(cd "$RL/.git/hooks" && pwd -P)/my-post-merge.sh" "$rlb.link" && test -f "$(sed -n "s/^ABSOLUTE=//p" "$rlb.link")" && grep -q "^RESTORE=cp -P -- " "$rlb.link"'

# m4: --check-only reports drift of the installed hooks
CK="$LT_SB/check_drift"; lt_make_project "$CK" "$URL" submodules/constitution
( cd "$CK" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 )
out="$( cd "$CK" && bash submodules/constitution/scripts/setup.sh --check-only 2>&1 )"; rc=$?
lt_check "m4: --check-only right after setup -> in sync, exit 0 (rc=$rc)" \
    eval 'test "$rc" -eq 0 && test "$(grep -c "in sync" <<<"$out")" = 2'
printf '# local edit\n' >> "$CK/.git/modules/submodules/constitution/hooks/post-checkout"
out="$( cd "$CK" && bash submodules/constitution/scripts/setup.sh --check-only 2>&1 )"; rc=$?
lt_check "m4: --check-only after the installed consumer drifted -> DRIFT with both sha256, exit 1 (rc=$rc)" \
    eval 'test "$rc" -eq 1 && grep -q "submodule post-checkout consumer: DRIFT" <<<"$out" && test "$(grep -oE "[0-9a-f]{64}" <<<"$out" | sort -u | wc -l)" -ge 2'
rm -f "$CK/.git/hooks/post-merge"
out="$( cd "$CK" && bash submodules/constitution/scripts/setup.sh --check-only 2>&1 )"; rc=$?
lt_check "m4: --check-only with the post-merge missing -> NOT INSTALLED, exit 1 (rc=$rc)" \
    eval 'test "$rc" -eq 1 && grep -q "project post-merge: NOT INSTALLED" <<<"$out"'

# I6(c): trust model printed; the choice recorded
TM="$LT_SB/trust"; lt_make_project "$TM" "$URL" submodules/constitution
out="$( cd "$TM" && bash submodules/constitution/scripts/setup.sh 2>&1 )"
lt_check "I6: setup prints the trust model (what runs, from which commit, how to disable)" \
    eval 'grep -q "Trust model of auto-propagation" <<<"$out" && grep -q "NEWLY" <<<"$out" && grep -q "constitution.autoPropagate false" <<<"$out"'
lt_check "I6: default choice recorded as autoPropagate=true (local config)" \
    test "$(git -C "$TM" config --local --get constitution.autoPropagate)" = true
( cd "$TM" && bash submodules/constitution/scripts/setup.sh --auto-propagate=off >"$LT_SB/tm.out" 2>&1 ); rc=$?
lt_check "I6: --auto-propagate=off records false and reports OFF (rc=$rc)" \
    eval 'test "$rc" -eq 0 && test "$(git -C "$TM" config --local --get constitution.autoPropagate)" = false && grep -q "current choice: OFF" "$LT_SB/tm.out"'
( cd "$TM" && bash submodules/constitution/scripts/setup.sh >/dev/null 2>&1 )
lt_check "I6: a later run without the flag keeps the recorded choice (false)" \
    test "$(git -C "$TM" config --local --get constitution.autoPropagate)" = false
( cd "$TM" && bash submodules/constitution/scripts/setup.sh --auto-propagate=maybe >/dev/null 2>&1 ); rc=$?
lt_check "I6: --auto-propagate=<bad> -> usage error 2 (rc=$rc)" test "$rc" -eq 2

lt_summary
