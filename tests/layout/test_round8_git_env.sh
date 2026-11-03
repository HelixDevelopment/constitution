#!/usr/bin/env bash
# tests/layout/test_round8_git_env.sh — round-8 class fix: an AMBIENT git
# environment (GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE & co. left over for
# another repository) never chooses the repository a constitution script reads
# or writes; plus the hook lock/stamp follow-ups of the same round.
#
# Purpose: one check per ENTRY POINT, each with a positive control (the decoy
# repository stays byte-for-byte untouched AND the project under test gets the
# correct effect — a scrub that merely did nothing would fail the second half):
#   LB  lib: cl_project_root_of / cl_owner_project_of / cl_find_in_project_no_override
#       / cl_git_hooks_dir answer for the PATH under an ambient GIT_DIR; the
#       resolver does not glob-expand a .gitmodules path such as 'v*' (two cwds);
#       cl_scrub_git_env drops the class, logs a notice, keeps the rest;
#   SU  setup.sh under GIT_DIR / GIT_DIR+GIT_WORK_TREE / GIT_INDEX_FILE;
#   PU  the REAL post_update_hook.sh under GIT_DIR (range diff must be the
#       project's, never a false "nothing to propagate");
#   PM  post-merge, run by hand under GIT_DIR/GIT_WORK_TREE;
#   CH  the submodule post-checkout consumer under GIT_DIR;
#   MT  multitrack_constitution_sync.sh under GIT_DIR;
#   GU  guard-evidence-store-write.sh under GIT_DIR (custom submodule path);
#   IP  install_cli_agent_plugins.sh: owner rule (explicit > owner > env/cwd
#       only standalone), --project-root, usage text;
#   FC  fastcycle consumers (_layout.local_gitlink, _enumerate_impl, audit);
#       first-layout degraded probe does not survive a later layout's hit;
#   DM  the deps-manifest engine under GIT_DIR (differential vs no ambient);
#   ST  static: every git-calling script in the owned set carries a scrub, and
#       the scrub lists of the six lone copies equal CL_GIT_SCRUB_VARS;
#   LK  hook lock follow-ups: stale (dead / reused-pid) locks of a SIGKILLed
#       setup.sh / post-merge are reclaimed, live / unreadable ones are not;
#       the lock-held message names the REAL command and is executed to prove it;
#       setup.sh consumes only a stamp whose ROOT matches (kills R10); the
#       setup lock is created exclusively (kills R23); post-merge's early
#       already-applied shortcut (kills R22);
#   AR  applied-ref is recorded only after a SUCCESSFUL post-update run
#       (post-merge, consumer hook, setup.sh) and the stamp is kept on failure;
#   HC  post_update_hook.sh carries the `# HELIX_HOOK_CAPABILITIES: project-root`
#       marker in its first 80 lines and honours --project-root.
# Usage: bash tests/layout/test_round8_git_env.sh
# Inputs: LAYOUT_SRC_ROOT (tree under test; default this repo).
# Outputs: PASS/FAIL lines, summary; exit 0 iff all pass.
# Side-effects: none outside one mktemp -d sandbox (removed with safe_rm_rf);
#   HOME is a sandbox dir for the real post-update run; CONSTITUTION_JEV_HOOK=off.
# Test doubles (§11.4.289): the harness's recording-stub post_update_hook.sh
#   (gate-logic class) except PU/HC, which run the REAL hook.
# Dependencies: bash, git, python3, find, sha256sum, sort, sleep.
LT_SUITE="round8_git_env"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

URL="$(lt_make_const_upstream r8)"
export LAYOUT_RECORD="$LT_SB/record.txt"; : > "$LAYOUT_RECORD"
calls() { grep -c '^CALLED ' "$LAYOUT_RECORD" 2>/dev/null || true; }
REL=submodules/constitution
snap() { ( cd "$1" && find . -path ./.git/objects -prune -o -print0 | sort -z | \
    while IFS= read -r -d '' f; do
        if [ -L "$f" ]; then printf 'L %s -> %s\n' "$f" "$(readlink "$f")"
        elif [ -f "$f" ]; then printf 'F %s %s\n' "$f" "$(sha256sum < "$f" | cut -c1-64)"
        else printf 'D %s\n' "$f"; fi
    done ) | sha256sum | cut -c1-64; }
mkdecoy() { # DIR -> a repository with one commit, a hooks dir and a config
    lt_git init -q "$1"; printf 'decoy\n' > "$1/f"; lt_git -C "$1" add f; lt_git -C "$1" commit -q -m decoy
}
common() { git -C "$1" rev-parse --path-format=absolute --git-common-dir; }
proc_start() { local s f; s="$(cat "/proc/$1/stat" 2>/dev/null)" || return 0; s="${s##*) }"; read -r -a f <<<"$s"; printf '%s' "${f[19]:-}"; }
dead_pid() { # a pid that is gone (an exited child of this shell)
    local p; ( exit 0 ) & p=$!; wait "$p" 2>/dev/null; printf '%s' "$p"
}

# ============================================================================
# LB: the resolver lib
# ============================================================================
LIB="$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh"
A="$LT_SB/projA"; O="$LT_SB/decoy"
lt_make_project "$A" "$URL" "$REL" || lt_bad "fixture A"
mkdecoy "$O"; o0="$(snap "$O")"
lbr() { # NAME  ->  result of the lib function under the ambient env given in $LB_ENV
    env $LB_ENV bash -c ". '$LIB'; $1" 2>/dev/null
}
LB_ENV="GIT_DIR=$O/.git GIT_WORK_TREE=$O"
lt_check "LB-1: cl_project_root_of(<constitution>) under an ambient GIT_DIR/GIT_WORK_TREE of another repo = the superproject" \
    test "$(lbr "cl_project_root_of '$A/$REL'")" = "$A"
lt_check "LB-2: cl_owner_project_of under the same ambient env = the superproject" \
    test "$(lbr "cl_owner_project_of '$A/$REL'")" = "$A"
lt_check "LB-3: cl_find_in_project_no_override(<project>) under the same env = the project's own gitlink" \
    test "$(lbr "cl_find_in_project_no_override '$A'")" = "$A/$REL"
lt_check "LB-4: cl_git_hooks_dir(<project>) under the same env = the PROJECT's hooks dir, not the decoy's" \
    test "$(lbr "cl_git_hooks_dir '$A'")" = "$(git -C "$A" rev-parse --path-format=absolute --git-path hooks)"
LB_ENV="A=1"
lt_check "LB-1c (control, no ambient): cl_project_root_of = the superproject" test "$(lbr "cl_project_root_of '$A/$REL'")" = "$A"
# cl_scrub_git_env itself
sc_out="$(env GIT_DIR=/x GIT_WORK_TREE=/y GIT_INDEX_FILE=/z GIT_CEILING_DIRECTORIES=/c GIT_AUTHOR_NAME=keepme GIT_CONFIG_GLOBAL=/dev/null \
    bash -c ". '$LIB'; cl_scrub_git_env 2>\"$LT_SB/sc.err\"; printf 'D=[%s] W=[%s] I=[%s] C=[%s] A=[%s] G=[%s]' \"\${GIT_DIR-unset}\" \"\${GIT_WORK_TREE-unset}\" \"\${GIT_INDEX_FILE-unset}\" \"\${GIT_CEILING_DIRECTORIES-unset}\" \"\$GIT_AUTHOR_NAME\" \"\$GIT_CONFIG_GLOBAL\"")"
lt_check "LB-5: cl_scrub_git_env unsets the repository-locating class and keeps identity/config ($sc_out)" \
    test "$sc_out" = "D=[unset] W=[unset] I=[unset] C=[unset] A=[keepme] G=[/dev/null]"
lt_check "LB-6: ... and logs ONE notice naming the dropped variables, never their values" \
    eval 'grep -q "NOTICE: ignoring the ambient git environment (GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CEILING_DIRECTORIES)" "$LT_SB/sc.err" && ! grep -q "/x\|/y\|/z" "$LT_SB/sc.err" && [ "$(wc -l < "$LT_SB/sc.err")" = 1 ]'
env A=1 bash -c ". '$LIB'; cl_scrub_git_env 2>\"$LT_SB/sc2.err\""
lt_check "LB-7 (control): nothing ambient -> no notice" test ! -s "$LT_SB/sc2.err"
lt_check "LB-8: the decoy repository was never touched by any lib call" test "$(snap "$O")" = "$o0"
# the scrub must work under the resolver's own IFS=newline (a caller IFS must not defeat it)
ifs_out="$(GIT_DIR=/x GIT_INDEX_FILE=/y bash -c ". '$LIB'; IFS=\$'\\n'; cl_scrub_git_env quiet; printf 'D=[%s] I=[%s] IFS=%s' \"\${GIT_DIR-unset}\" \"\${GIT_INDEX_FILE-unset}\" \"\$(printf %s \"\$IFS\" | od -An -c | tr -d ' ')\"")"
lt_check "LB-10: cl_scrub_git_env works under a caller IFS of newline and restores that IFS ($ifs_out)" \
    test "$ifs_out" = 'D=[unset] I=[unset] IFS=\n'

# glob-free resolver (minor 1): .gitmodules path 'v*' + a plain constitution copy 'vendor-const'
GP="$LT_SB/projGlob"; mkdir -p "$GP"; lt_git init -q "$GP"; printf 'g\n' > "$GP/README.md"; lt_git -C "$GP" add README.md; lt_git -C "$GP" commit -q -m i
if lt_git -C "$GP" submodule add -q "$URL" 'v*' >/dev/null 2>&1 && lt_git -C "$GP" commit -q -m "add v*"; then
    mkdir -p "$GP/vendor-const/scripts"; printf '# C\n' > "$GP/vendor-const/Constitution.md"
    g1="$(cd "$GP" && bash -c ". '$LIB'; cl_find_in_project_no_override '$GP'")"
    g2="$(cd "$LT_SB" && bash -c ". '$LIB'; cl_find_in_project_no_override '$GP'")"
    g3="$(cd "$GP" && sh -c ". '$LIB'; cl_find_in_project_no_override '$GP'")"
    lt_check "LB-9: a .gitmodules path 'v*' is a NAME, not a glob (cwd = the project, where vendor-const matches v*) -> '$g1'" test "$g1" = "$GP/v*"
    lt_check "LB-9b: ... same from another cwd -> '$g2'" test "$g2" = "$GP/v*"
    lt_check "LB-9c: ... and under POSIX sh -> '$g3'" test "$g3" = "$GP/v*"
    mkdir -p "$GP/submodules/constitution/scripts"; printf '# C\n' > "$GP/submodules/constitution/Constitution.md"
    g4="$(cd "$GP" && bash -c ". '$LIB'; cl_find_in_project_no_override '$GP'")"
    lt_check "LB-9e: the gitlink at the glob-like path 'v*' still beats a plain layout copy when a sibling dir matches the glob -> '$g4'" test "$g4" = "$GP/v*"
    # a bracket glob whose ONLY match is a different (plain) directory: expansion would hide the gitlink
    GQ="$LT_SB/projGlobQ"; mkdir -p "$GQ"; lt_git init -q "$GQ"; printf 'g\n' > "$GQ/README.md"; lt_git -C "$GQ" add README.md; lt_git -C "$GQ" commit -q -m i
    if lt_git -C "$GQ" submodule add -q "$URL" 'v[x]' >/dev/null 2>&1 && lt_git -C "$GQ" commit -q -m "add v[x]"; then
        mkdir -p "$GQ/vx/scripts" "$GQ/submodules/constitution/scripts"; printf '# C\n' > "$GQ/vx/Constitution.md"; printf '# C\n' > "$GQ/submodules/constitution/Constitution.md"
        g5="$(cd "$GQ" && bash -c ". '$LIB'; cl_find_in_project_no_override '$GQ'")"
        lt_check "LB-9f: a gitlink path 'v[x]' is found as itself, never as the glob-matched plain dir 'vx' or the plain layout copy -> '$g5'" test "$g5" = "$GQ/v[x]"
    else lt_bad "LB-9f fixture: could not create a submodule at path v[x]"; fi
    lt_check "LB-9d: the shell's noglob option is left as found (set +f afterwards)" \
        eval '[ "$(cd "$GP" && bash -c ". \"$LIB\"; cl_find_in_project_no_override \"$GP\" >/dev/null; echo vendor-c*")" = "vendor-const" ]'
else
    lt_bad "LB-9 fixture: could not create a submodule at path v*"
fi

# ============================================================================
# SU: setup.sh
# ============================================================================
runsetup() { # PROJECT [env...]  -> output in $LT_SB/su.out
    local p="$1"; shift
    ( cd "$p" && env "$@" bash "$REL/scripts/setup.sh" ) >"$LT_SB/su.out" 2>&1
}
S1="$LT_SB/projS1"; lt_make_project "$S1" "$URL" "$REL"; mkdecoy "$O"; o0="$(snap "$O")"; : > "$LAYOUT_RECORD"
runsetup "$S1" GIT_DIR="$O/.git"; rc=$?
lt_check "SU-1: setup.sh under an ambient GIT_DIR=<decoy>/.git exits 0 (rc=$rc)" test "$rc" -eq 0
lt_check "SU-1: ... the PROJECT got the post-merge hook and constitution.autoPropagate" \
    eval 'test -x "$S1/.git/hooks/post-merge" && test "$(git -C "$S1" config --local --get constitution.autoPropagate)" = true'
lt_check "SU-1: ... the DECOY has no hook, no autoPropagate and is byte-for-byte unchanged" \
    eval '! test -e "$O/.git/hooks/post-merge" && ! git -C "$O" config --local --get constitution.autoPropagate >/dev/null 2>&1 && test "$(snap "$O")" = "$o0"'
lt_check "SU-1: ... the NOTICE names GIT_DIR and the Project root is the project" \
    eval 'grep -q "NOTICE: ignoring the ambient git environment (GIT_DIR)" "$LT_SB/su.out" && grep -q "Project root: $S1\$" "$LT_SB/su.out"'
lt_check "SU-1: ... the post-update hook was called for the project exactly once" \
    eval 'test "$(calls)" = 1 && grep -qF "CALLED PROJECT_ROOT=$S1 CONST_DIR=$S1/$REL " "$LAYOUT_RECORD"'

S2="$LT_SB/projS2"; lt_make_project "$S2" "$URL" "$REL"; : > "$LAYOUT_RECORD"
runsetup "$S2" GIT_DIR="$O/.git" GIT_WORK_TREE="$O"; rc=$?
lt_check "SU-2: GIT_DIR+GIT_WORK_TREE of another repo -> Project root stays the project (rc=$rc)" \
    eval 'grep -q "Project root: $S2\$" "$LT_SB/su.out" && test -x "$S2/.git/hooks/post-merge" && ! test -e "$O/.git/hooks/post-merge" && test "$(snap "$O")" = "$o0"'
S3="$LT_SB/projS3"; lt_make_project "$S3" "$URL" "$REL"; : > "$LAYOUT_RECORD"
runsetup "$S3" GIT_INDEX_FILE="$LT_SB/no-such-index"; rc=$?
lt_check "SU-3: an ambient GIT_INDEX_FILE does not hide the gitlink: the submodule consumer hook is installed (rc=$rc)" \
    test -x "$(git -C "$S3/$REL" rev-parse --path-format=absolute --git-path hooks)/post-checkout"
lt_check "SU-3: ... and no stray index file was created at that path" test ! -e "$LT_SB/no-such-index"
S4="$LT_SB/projS4"; lt_make_project "$S4" "$URL" "$REL"; : > "$LAYOUT_RECORD"
runsetup "$S4" A=1; rc=$?
lt_check "SU-4 (control, nothing ambient): same effects, no notice (rc=$rc)" \
    eval 'test -x "$S4/.git/hooks/post-merge" && ! grep -q "ambient git environment" "$LT_SB/su.out"'

# ============================================================================
# PU: the REAL post_update_hook.sh under an ambient GIT_DIR
# ============================================================================
RC="$LT_SB/realc"; mkdir -p "$RC"; lt_git init -q "$RC"
for p in scripts Constitution.md CLAUDE.md AGENTS.md; do lt_copy "$p" "$RC"; done
find "$RC" -name __pycache__ -type d -prune -exec rm -r {} + 2>/dev/null
lt_git -C "$RC" add -A >/dev/null; lt_git -C "$RC" commit -q -m v1; RV1="$(git -C "$RC" rev-parse HEAD)"
for p in templates .claude-plugin plugins actions skills mcp helix-deps.yaml; do
    [ -e "$LAYOUT_SRC_ROOT/$p" ] && lt_copy "$p" "$RC"
done
find "$RC" -name __pycache__ -type d -prune -exec rm -r {} + 2>/dev/null
printf '\n# trivial change\n' >> "$RC/scripts/hooks/post-merge"
lt_git -C "$RC" add -A >/dev/null; lt_git -C "$RC" commit -q -m v2; RV2="$(git -C "$RC" rev-parse HEAD)"
lt_git clone -q --bare "$RC" "$LT_SB/realc.git"
mkdir -p "$LT_SB/home"
mkreal() { # NAME -> P
    P="$LT_SB/real_$1"; mkdir -p "$P"; lt_git init -q "$P"; printf 'x\n' > "$P/README.md"
    lt_git -C "$P" add .; lt_git -C "$P" commit -q -m i
    lt_git -C "$P" submodule add -q "file://$LT_SB/realc.git" "$REL" >/dev/null 2>&1
    lt_git -C "$P" commit -q -m add
    git -C "$P/$REL" checkout -q "$RV2"
}
runpu() { # CWD [env...]
    local cwd="$1"; shift
    ( cd "$cwd" && env HOME="$LT_SB/home" CONSTITUTION_UPDATE_OLD_REF="$RV1" CONSTITUTION_UPDATE_NEW_REF="$RV2" \
        "$@" timeout 600 bash "$PUH" $PU_ARGS ) >"$LT_SB/pu.out" 2>&1
}
PU_ARGS=""
mkreal gd; PUH="$P/$REL/scripts/post_update_hook.sh"; mkdecoy "$O"; o0="$(snap "$O")"
runpu "$P" GIT_DIR="$O/.git"; rc=$?
lt_check "PU-1: real hook under an ambient GIT_DIR of another repo: the range diff is the PROJECT's (not 'nothing to propagate'; rc=$rc)" \
    eval '! grep -q "No files changed in this update\|No relevant changes detected" "$LT_SB/pu.out" && grep -q "post-merge" "$LT_SB/pu.out"'
lt_check "PU-1: ... the project got the git hook and .claude; the decoy is byte-for-byte unchanged" \
    eval 'test -x "$P/.git/hooks/post-merge" && test -d "$P/.claude" && test "$(snap "$O")" = "$o0"'
lt_check "PU-1: ... the NOTICE names GIT_DIR" grep -q "NOTICE\] ignoring the ambient git environment (GIT_DIR)" "$LT_SB/pu.out"
mkreal gdw; PUH="$P/$REL/scripts/post_update_hook.sh"
runpu "$P" GIT_DIR="$O/.git" GIT_WORK_TREE="$O" GIT_INDEX_FILE="$LT_SB/no-such-index2"; rc=$?
lt_check "PU-2: GIT_DIR+GIT_WORK_TREE+GIT_INDEX_FILE: same correct effect on the project, decoy untouched (rc=$rc)" \
    eval 'test -x "$P/.git/hooks/post-merge" && test -d "$P/.claude" && test "$(snap "$O")" = "$o0" && test ! -e "$LT_SB/no-such-index2"'
mkreal ctl; PUH="$P/$REL/scripts/post_update_hook.sh"
runpu "$P" A=1; rc=$?
lt_check "PU-3 (control, nothing ambient): same effect, no notice (rc=$rc)" \
    eval 'test -x "$P/.git/hooks/post-merge" && ! grep -q "ambient git environment" "$LT_SB/pu.out"'

# HC: capability marker + --project-root really honoured
PUSRC="$LAYOUT_SRC_ROOT/scripts/post_update_hook.sh"
lt_check "HC-1: the marker '# HELIX_HOOK_CAPABILITIES: project-root' is a whole line within the first 80 lines" \
    eval 'head -n 80 "$PUSRC" | grep -qx "# HELIX_HOOK_CAPABILITIES: project-root"'
mkreal hc; PUH="$P/$REL/scripts/post_update_hook.sh"; HCP="$P"
mkdir -p "$LT_SB/elsewhere"; PU_ARGS="--project-root $HCP"
runpu "$LT_SB/elsewhere" A=1; rc=$?
lt_check "HC-2: --project-root DIR is honoured from a foreign cwd (project wired, rc=$rc)" \
    eval 'test -x "$HCP/.git/hooks/post-merge" && ! test -e "$LT_SB/elsewhere/.claude"'
PU_ARGS="--project-root"; runpu "$HCP" A=1; rc=$?
lt_check "HC-3: --project-root without an argument is refused (rc=$rc)" test "$rc" -eq 2
PU_ARGS=""

# ============================================================================
# PM / CH: the git hooks, run by hand under an ambient GIT_DIR
# ============================================================================
mkpair() {
    local name="$1" rel="$2"
    W="$LT_SB/w_$name"; PB="$LT_SB/$name.proj.git"; B="$LT_SB/b $name"
    lt_make_project "$W" "$URL" "$rel" || return 1
    lt_git clone -q --bare "$W" "$PB"
    lt_git -C "$W" remote add origin "file://$PB"; lt_git -C "$W" fetch -q origin; lt_git -C "$W" branch -q -u origin/main
    lt_git clone -q --recurse-submodules "file://$PB" "$B" || return 1
    : > "$LAYOUT_RECORD"
    ( cd "$B" && bash "$rel/scripts/setup.sh" >"$LT_SB/setup_$name.out" 2>&1 ) || return 1
    : > "$LAYOUT_RECORD"
}
bump() { # REL -> new sha (pushed from W)
    lt_bump_const_upstream r8
    lt_git -C "$W/$1" fetch -q origin; lt_git -C "$W/$1" checkout -q origin/main
    lt_git -C "$W" commit -q -am "bump constitution"; lt_git -C "$W" push -q origin main
    git -C "$W/$1" rev-parse HEAD
}
# mkmoved NAME -> B: the gitlink moved by a hook-less merge, the checkout already at the new commit
mkmoved() {
    mkpair "$1" "$REL" || return 1
    V1="$(git -C "$B/$REL" rev-parse HEAD)"; V2="$(bump "$REL")"
    local h0 h1; h0="$(git -C "$B" rev-parse HEAD)"
    ( cd "$B" && lt_git -c core.hooksPath=/dev/null pull -q --no-rebase origin main ) >/dev/null 2>&1
    # the fixture is only valid when the hook-less pull REALLY moved the project's HEAD and its gitlink to V2;
    # a pull that silently failed would leave every dependent check running on an unmoved project
    h1="$(git -C "$B" rev-parse HEAD)"
    if [ "$h0" = "$h1" ] || [ "$(git -C "$B" rev-parse "HEAD:$REL")" != "$V2" ]; then
        printf 'FIXTURE ERROR (mkmoved %s): the hook-less pull did not move HEAD (%s -> %s) / the gitlink to %s\n' "$1" "${h0:0:8}" "${h1:0:8}" "${V2:0:8}" >&2
        return 1
    fi
    lt_git -C "$B/$REL" fetch -q origin; lt_git -C "$B/$REL" -c core.hooksPath=/dev/null checkout -q "$V2"
    : > "$LAYOUT_RECORD"
}
mkdecoy "$O"; o0="$(snap "$O")"
mkmoved pm0 || lt_bad "fixture pm0"
( cd "$B" && A=1 bash .git/hooks/post-merge 0 ) >"$LT_SB/pm.out" 2>&1
lt_check "PM-0 (control, nothing ambient): the hook run by hand propagates once for the project" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$V1 NEW=$V2" "$LAYOUT_RECORD"'
mkmoved pm1 || lt_bad "fixture pm1"
( cd "$B" && GIT_DIR="$O/.git" bash .git/hooks/post-merge 0 ) >"$LT_SB/pm.out" 2>&1
lt_check "PM-1: post-merge under an ambient GIT_DIR of another repo propagates for the PROJECT (not a silent no-op on the decoy)" \
    eval 'test "$(calls)" = 1 && grep -qF "CALLED PROJECT_ROOT=$B CONST_DIR=$B/$REL " "$LAYOUT_RECORD" && grep -qF " OLD=$V1 NEW=$V2" "$LAYOUT_RECORD"'
lt_check "PM-1: ... the decoy is byte-for-byte unchanged" test "$(snap "$O")" = "$o0"
mkmoved pm2 || lt_bad "fixture pm2"
( cd "$B" && GIT_DIR="$O/.git" GIT_WORK_TREE="$O" bash .git/hooks/post-merge 0 ) >"$LT_SB/pm.out" 2>&1
lt_check "PM-2: GIT_DIR+GIT_WORK_TREE of another repo: same correct effect" \
    eval 'test "$(calls)" = 1 && grep -qF "CALLED PROJECT_ROOT=$B CONST_DIR=$B/$REL " "$LAYOUT_RECORD" && test "$(snap "$O")" = "$o0"'

# CH: the consumer hook needs a pending stamp and the checkout at the gitlink
mkmoved ch1 || lt_bad "fixture ch1"
GD="$(git -C "$B" rev-parse --absolute-git-dir)"
printf 'ROOT=%s\nREL=%s\nOLD=%s\nNEW=%s\n' "$(cd "$B" && pwd -P)" "$REL" "$V1" "$V2" > "$GD/constitution-pending-update"
CHOOK="$(git -C "$B/$REL" rev-parse --path-format=absolute --git-path hooks)/post-checkout"
( cd "$B/$REL" && GIT_DIR="$O/.git" GIT_WORK_TREE="$O" bash "$CHOOK" 0 0 1 ) >"$LT_SB/ch.out" 2>&1
lt_check "CH-1: the submodule consumer under an ambient GIT_DIR/GIT_WORK_TREE of another repo propagates for the project" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$V1 NEW=$V2" "$LAYOUT_RECORD" && test "$(snap "$O")" = "$o0"'

# CH-2: a gitlink whose PATH is a pathspec magic prefix (':(top)x'): the hook's own git calls
# must treat REL literally (--literal-pathspecs), else ls-files matches nothing and the hook exits silently.
MP="$LT_SB/projMagic"; MREL=':(top)x'
# (`git submodule add` refuses this path, so the gitlink is made by hand: clone + literal-pathspec add)
mkdir -p "$MP"; lt_git init -q "$MP"; printf 'm\n' > "$MP/README.md"; lt_git -C "$MP" add README.md; lt_git -C "$MP" commit -q -m init
if lt_git clone -q "$URL" "$MP/$MREL" && printf '[submodule "magic"]\n\tpath = %s\n\turl = %s\n' "$MREL" "$URL" > "$MP/.gitmodules" \
   && lt_git -C "$MP" --literal-pathspecs add .gitmodules "$MREL" && lt_git -C "$MP" commit -q -m "magic gitlink" \
   && [ "$(git -C "$MP" ls-files -s -z | tr '\0' '\n' | grep -c '^160000 .*	:(top)x$')" = 1 ]; then
    : > "$LAYOUT_RECORD"
    MHK="$LT_SB/magic-post-checkout"; cp "$LAYOUT_SRC_ROOT/scripts/hooks/constitution-submodule-post-checkout" "$MHK"
    MGD="$(git -C "$MP" rev-parse --absolute-git-dir)"; MV="$(git -C "$MP/$MREL" rev-parse HEAD)"
    lt_bump_const_upstream r8   # the gitlink moves MV -> MV2 (a stamp with OLD == NEW has nothing to propagate)
    lt_git -C "$MP/$MREL" fetch -q origin; lt_git -C "$MP/$MREL" checkout -q origin/main
    lt_git -C "$MP" --literal-pathspecs add "$MREL" 2>/dev/null; lt_git -C "$MP" commit -q -m "bump magic gitlink"
    MV2="$(git -C "$MP/$MREL" rev-parse HEAD)"
    printf 'ROOT=%s\nREL=%s\nOLD=%s\nNEW=%s\n' "$(cd "$MP" && pwd -P)" "$MREL" "$MV" "$MV2" > "$MGD/constitution-pending-update"
    ( cd "$MP/$MREL" && bash "$MHK" 0 0 1 ) >"$LT_SB/ch2.out" 2>&1
    lt_check "CH-2: a gitlink at the magic-prefix path ':(top)x' is found literally: the hook propagated once" \
        eval 'test "$(calls)" = 1 && grep -qF "CALLED PROJECT_ROOT=$MP CONST_DIR=$MP/$MREL " "$LAYOUT_RECORD" && grep -qF " OLD=$MV NEW=$MV2" "$LAYOUT_RECORD"'
else lt_bad "CH-2 fixture: could not create a submodule at path :(top)x"; fi

# MG: migrate.sh's run_with_caller_git_env comment must not claim an ORIGINAL restore for the two variables the
# round-8 loop has already unset, and the loop really precedes the captures (so the claim would be false).
MGS="$LAYOUT_SRC_ROOT/scripts/fastcycle/consumers/migrate.sh"
lt_check "MG-1: the unset loop (GIT_NO_REPLACE_OBJECTS/GIT_GRAFT_FILE) precedes their FC_CALLER_* captures" \
    eval '[ "$(grep -n "^do\$" "$MGS" | head -1 | cut -d: -f1)" -lt "$(grep -n "^FC_CALLER_NRO_SET=0" "$MGS" | cut -d: -f1)" ] && [ "$(grep -n "^FC_CALLER_NRO_SET=0" "$MGS" | wc -l)" = 1 ]'
lt_check "MG-2: the helper comment says NOT original for GIT_NO_REPLACE_OBJECTS / GIT_GRAFT_FILE (always unset)" \
    eval 'sed -n "/^run_with_caller_git_env() {/,/^    (\$/p" "$MGS" | grep -q "NOT original for" && sed -n "/^run_with_caller_git_env() {/,/^    (\$/p" "$MGS" | grep -q "always UNSET"'
lt_check "MG-3 (behaviour): ambient GIT_NO_REPLACE_OBJECTS / GIT_GRAFT_FILE never reach a hook run through the helper" \
    eval '[ "$(env GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/x bash -c "for v in GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_OBJECT_DIRECTORY GIT_TEMPLATE_DIR GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_SHALLOW_FILE GIT_REPLACE_REF_BASE GIT_NAMESPACE GIT_INDEX_FILE GIT_PREFIX GIT_CEILING_DIRECTORIES GIT_GRAFT_FILE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset \"\$v\"; done; FC_CALLER_NRO_SET=0; FC_CALLER_GRAFT_SET=0; FC_CALLER_GCC_SET=0; FC_CALLER_GCP_SET=0; FC_CALLER_GNLF_SET=0; $(sed -n "/^run_with_caller_git_env() {/,/^}/p" "$MGS"); run_with_caller_git_env sh -c \"echo \\\"[\\\$GIT_NO_REPLACE_OBJECTS][\\\$GIT_GRAFT_FILE]\\\"\"")" = "[][]" ]'

# ============================================================================
# MT: multitrack_constitution_sync.sh
# ============================================================================
ENG="$LT_SB/engine"; mkdir -p "$ENG/scripts/multitrack"
cp "$LAYOUT_SRC_ROOT/scripts/multitrack/multitrack_constitution_sync.sh" "$ENG/scripts/multitrack/"
export MTCS_LOG_DIR="$LT_SB/mtlog"
MC="$LT_SB/mtcheckout"; lt_git clone -q "$URL" "$MC"
lt_git -C "$MC" checkout -q -B main origin/main 2>/dev/null; lt_git -C "$MC" branch -q --set-upstream-to=origin/main main 2>/dev/null || true
mt_before="$(git -C "$MC" rev-parse HEAD)"; lt_bump_const_upstream r8
mt_out="$(GIT_DIR="$O/.git" GIT_WORK_TREE="$O" bash "$ENG/scripts/multitrack/multitrack_constitution_sync.sh" sync "$MC" 2>/dev/null)"
lt_check "MT-1: sync under an ambient GIT_DIR/GIT_WORK_TREE of another repo fast-forwards the CHECKOUT (SYNCED, HEAD moved)" \
    eval 'grep -q SYNCED <<<"$mt_out" && test "$mt_before" != "$(git -C "$MC" rev-parse HEAD)"'
lt_check "MT-1: ... the decoy is byte-for-byte unchanged and the NOTICE was printed" \
    eval 'test "$(snap "$O")" = "$o0" && GIT_DIR=/x bash "$ENG/scripts/multitrack/multitrack_constitution_sync.sh" sync "$MC" 2>&1 >/dev/null | grep -q "NOTICE: ignoring the ambient git environment (GIT_DIR)"'

# ============================================================================
# GU: guard-evidence-store-write.sh with a CUSTOM submodule path
# ============================================================================
GP2="$LT_SB/projGuard"; lt_make_project "$GP2" "$URL" "vendor/helix" || lt_bad "fixture guard"
mkdir -p "$GP2/docs/requests"
GREG="$GP2/docs/requests/critical_blockers.jsonl"
printf '{"blocker_id":"B-X","event":"satisfy","author_session_id":"SESS-V","producer_session_id":"SESS-PRODUCER"}\n' > "$GREG"
GPAY="$(printf '{"session_id":"SESS-PRODUCER","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$GREG")"
GG="$GP2/vendor/helix/scripts/hooks/guard-evidence-store-write.sh"
printf '%s' "$GPAY" | ( unset CLAUDE_PROJECT_DIR GESW_REGISTRY; bash "$GG" ) >/dev/null 2>"$LT_SB/g0.err"; rc0=$?
lt_check "GU-0 (control, nothing ambient): custom-path guard finds the project registry and BLOCKS the producer (rc=$rc0)" \
    eval 'test "$rc0" -eq 2 && grep -q "recorded as a PRODUCER" "$LT_SB/g0.err"'
printf '%s' "$GPAY" | ( unset CLAUDE_PROJECT_DIR GESW_REGISTRY; GIT_DIR="$O/.git" GIT_WORK_TREE="$O" bash "$GG" ) >/dev/null 2>"$LT_SB/g1.err"; rc1=$?
lt_check "GU-1: ... same under an ambient GIT_DIR of another repo (registry found, producer blocked as PRODUCER; rc=$rc1)" \
    eval 'test "$rc1" -eq 2 && grep -q "recorded as a PRODUCER" "$LT_SB/g1.err"'

# child-process leak: a tool the guard runs must not inherit the foreign repository
mkdir -p "$LT_SB/stub_gu"; REALBN="$(command -v basename)"
printf '#!/bin/sh\nprintf "GD=%%s GW=%%s GI=%%s\\n" "${GIT_DIR-unset}" "${GIT_WORK_TREE-unset}" "${GIT_INDEX_FILE-unset}" >> "%s/gu_env.txt"\nexec "%s" "$@"\n' "$LT_SB" "$REALBN" > "$LT_SB/stub_gu/basename"
chmod +x "$LT_SB/stub_gu/basename"; : > "$LT_SB/gu_env.txt"
printf '%s' "$GPAY" | ( unset CLAUDE_PROJECT_DIR GESW_REGISTRY; PATH="$LT_SB/stub_gu:$PATH" GIT_DIR="$O/.git" GIT_WORK_TREE="$O" GIT_INDEX_FILE="$O/.git/index" bash "$GG" ) >/dev/null 2>&1
lt_check "GU-2: a child process of the guard sees NO repository-locating GIT_* from the foreign repo (observed: $(sort -u "$LT_SB/gu_env.txt" | tr '\n' ' '))" \
    eval 'test -s "$LT_SB/gu_env.txt" && ! grep -qv "^GD=unset GW=unset GI=unset$" "$LT_SB/gu_env.txt"'

# ============================================================================
# IP: install_cli_agent_plugins.sh owner rule
# ============================================================================
mkip() { # NAME -> IPP (project with a minimal constitution carrying the REAL installer + lib)
    IPP="$LT_SB/ip_$1"; mkdir -p "$IPP/$REL/scripts/lib" "$IPP/$REL/skills/zz_skill"
    lt_git init -q "$IPP"; printf 'ip\n' > "$IPP/README.md"
    printf '# C\n' > "$IPP/$REL/Constitution.md"
    cp "$LAYOUT_SRC_ROOT/scripts/install_cli_agent_plugins.sh" "$LAYOUT_SRC_ROOT/scripts/portable_symlink_lib.sh" "$IPP/$REL/scripts/"
    cp "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" "$IPP/$REL/scripts/lib/"
    printf -- '---\nname: zz_skill\ndescription: t\n---\nbody\n' > "$IPP/$REL/skills/zz_skill/SKILL.md"
    # the constitution as a gitlink-less vendored copy inside the project work tree (owner = the work tree)
    lt_git -C "$IPP" add -A >/dev/null; lt_git -C "$IPP" commit -q -m i
}
mkip own; OTH="$LT_SB/ip_other"; mkdir -p "$OTH"; lt_git init -q "$OTH"
ipr() { ( cd "$1" && shift && env PATH="$IP_PATH" "$@" ) ; }
IP_PATH="/usr/bin:/bin"
( cd "$OTH" && PROJECT_ROOT="$OTH" env -u CLAUDE_CONFIG_DIR bash "$IPP/$REL/scripts/install_cli_agent_plugins.sh" --skills-only --no-plugin ) >"$LT_SB/ip1.out" 2>&1
lt_check "IP-1: ambient PROJECT_ROOT/cwd naming ANOTHER repository is ignored: the OWNER gets the skill link, the other repo nothing" \
    eval 'test -L "$IPP/.claude/skills/zz_skill" && ! test -e "$OTH/.claude" && grep -q "ignoring the ambient PROJECT_ROOT=$OTH" "$LT_SB/ip1.out"'
( cd "$OTH" && env -u PROJECT_ROOT bash "$IPP/$REL/scripts/install_cli_agent_plugins.sh" --skills-only --no-plugin ) >"$LT_SB/ip2.out" 2>&1
lt_check "IP-2: cwd = another repository, nothing exported: still the owner (no write into the cwd repo)" \
    eval 'test -L "$IPP/.claude/skills/zz_skill" && ! test -e "$OTH/.claude"'
mkip flag; ( cd "$OTH" && bash "$IPP/$REL/scripts/install_cli_agent_plugins.sh" --project-root "$OTH" --skills-only --no-plugin ) >"$LT_SB/ip3.out" 2>&1
lt_check "IP-3: an explicit --project-root wins over the owner" \
    eval 'test -L "$OTH/.claude/skills/zz_skill" && ! test -e "$IPP/.claude/skills/zz_skill"'
safe_rm_rf "${OTH:?}/.claude"
mkip pos; ( cd "$LT_SB" && bash "$IPP/$REL/scripts/install_cli_agent_plugins.sh" "$OTH" --skills-only --no-plugin ) >"$LT_SB/ip4.out" 2>&1
lt_check "IP-4: an explicit positional PROJECT_ROOT still wins (back-compat)" test -L "$OTH/.claude/skills/zz_skill"
safe_rm_rf "${OTH:?}/.claude"
SA2="$LT_SB/ip_standalone"; mkdir -p "$SA2/scripts/lib" "$SA2/skills/zz_skill"; printf '# C\n' > "$SA2/Constitution.md"
cp "$LAYOUT_SRC_ROOT/scripts/install_cli_agent_plugins.sh" "$LAYOUT_SRC_ROOT/scripts/portable_symlink_lib.sh" "$SA2/scripts/"
cp "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" "$SA2/scripts/lib/"
printf -- '---\nname: zz_skill\ndescription: t\n---\nb\n' > "$SA2/skills/zz_skill/SKILL.md"
lt_git init -q "$SA2"; lt_git -C "$SA2" add -A >/dev/null; lt_git -C "$SA2" commit -q -m i
( cd "$LT_SB" && PROJECT_ROOT="$OTH" bash "$SA2/scripts/install_cli_agent_plugins.sh" --skills-only --no-plugin ) >"$LT_SB/ip5.out" 2>&1
lt_check "IP-5: a STANDALONE checkout (no owner) takes the ambient PROJECT_ROOT" test -L "$OTH/.claude/skills/zz_skill"
safe_rm_rf "${OTH:?}/.claude"
( cd "$OTH" && env -u PROJECT_ROOT bash "$SA2/scripts/install_cli_agent_plugins.sh" --skills-only --no-plugin ) >"$LT_SB/ip6.out" 2>&1
lt_check "IP-6: ... and otherwise the cwd" test -L "$OTH/.claude/skills/zz_skill"
ip_help="$(bash "$IPP/$REL/scripts/install_cli_agent_plugins.sh" --help)"
lt_check "IP-7: --help shows the submodules/constitution path, --project-root and the owner rule" \
    eval 'grep -q "submodules/constitution" <<<"$ip_help" && grep -q "\-\-project-root" <<<"$ip_help" && grep -qi "OWNER" <<<"$ip_help" && grep -q -- "--check" <<<"$ip_help"'
mkip gd; ( cd "$IPP" && GIT_DIR="$O/.git" GIT_WORK_TREE="$O" bash "$REL/scripts/install_cli_agent_plugins.sh" --skills-only --no-plugin ) >"$LT_SB/ip7.out" 2>&1
lt_check "IP-8: under an ambient GIT_DIR/GIT_WORK_TREE of another repo the OWNER still gets the link; decoy untouched" \
    eval 'test -L "$IPP/.claude/skills/zz_skill" && test "$(snap "$O")" = "$o0"'

mkdir -p "$LT_SB/stub_ip"; : > "$LT_SB/ip_env.txt"
printf '#!/bin/sh\nprintf "GD=%%s GW=%%s GI=%%s\\n" "${GIT_DIR-unset}" "${GIT_WORK_TREE-unset}" "${GIT_INDEX_FILE-unset}" >> "%s/ip_env.txt"\nexit 0\n' "$LT_SB" > "$LT_SB/stub_ip/claude"
chmod +x "$LT_SB/stub_ip/claude"
mkip env; ( cd "$IPP" && PATH="$LT_SB/stub_ip:$PATH" GIT_DIR="$O/.git" GIT_WORK_TREE="$O" GIT_INDEX_FILE="$O/.git/index" bash "$REL/scripts/install_cli_agent_plugins.sh" ) >"$LT_SB/ip8.out" 2>&1
lt_check "IP-9: the \`claude\` child of the installer sees NO repository-locating GIT_* from the foreign repo (observed: $(sort -u "$LT_SB/ip_env.txt" | tr '\n' ' '))" \
    eval 'test -s "$LT_SB/ip_env.txt" && ! grep -qv "^GD=unset GW=unset GI=unset$" "$LT_SB/ip_env.txt"'

# hook_install.sh as a LONE copy (no resolver beside it, as the label-sync fixture ships it)
LONEHI="$LT_SB/lone_hi"; mkdir -p "$LONEHI"; cp "$LAYOUT_SRC_ROOT/scripts/lib/hook_install.sh" "$LONEHI/"
lh_out="$(GIT_DIR="$O/.git" GIT_WORK_TREE="$O" bash -c ". '$LONEHI/hook_install.sh'; chi__git -C '$S1' rev-parse --show-toplevel" 2>&1)"
lt_check "HI-1: a lone copy of hook_install.sh (no constitution_layout.sh beside it) still sources and scrubs: git -C answers for the path under a foreign GIT_DIR ($lh_out)" \
    test "$lh_out" = "$S1"

# ============================================================================
# FC: fastcycle consumers
# ============================================================================
C="$LAYOUT_SRC_ROOT/scripts/fastcycle/consumers"
GLREPO="$LT_SB/fc_local"; lt_git init -q "$GLREPO"; printf 'x\n' > "$GLREPO/f"; lt_git -C "$GLREPO" add f
lt_git -C "$GLREPO" update-index --add --cacheinfo "160000,$(printf '%040d' 1 | tr 0 a),submodules/constitution"
lt_git -C "$GLREPO" commit -q -m x; lt_git -C "$GLREPO" remote add origin git@github.com:acme/widget.git
fc_out="$(GIT_DIR="$O/.git" GIT_WORK_TREE="$O" python3 - "$C" "$GLREPO" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import _layout, _enumerate_impl as e
print("GL", _layout.local_gitlink(sys.argv[2])[0])
print("PID", e._local_project_id(sys.argv[2]))
PY
)"
lt_check "FC-1: _layout.local_gitlink under an ambient GIT_DIR of another repo reads the CHECKOUT's tree" grep -qx 'GL submodules/constitution' <<<"$fc_out"
lt_check "FC-2: _enumerate_impl._local_project_id under the same env reads the CHECKOUT's origin" grep -qx 'PID acme/widget' <<<"$fc_out"
LONE="$LT_SB/fc_lone"; mkdir -p "$LONE"; cp "$C/audit.py" "$LONE/audit.py"
fc2="$(GIT_DIR="$O/.git" python3 - "$LONE" "$GLREPO" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import audit
print("LONE_GL", audit.local_gitlink(sys.argv[2])[0])
import os
audit.scrub_git_env(notice=False)
print("LEFT", "GIT_DIR" in os.environ)
PY
)"
lt_check "FC-3: audit.py's lone-copy fallback reads the checkout under an ambient GIT_DIR and scrub_git_env empties the class" \
    eval 'grep -qx "LONE_GL submodules/constitution" <<<"$fc2" && grep -qx "LEFT False" <<<"$fc2"'
fc3="$(python3 - "$C" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import _enumerate_impl as e
LR = e.LAYOUT_RELS
def run(statuses):
    # statuses: {rel: (found, status)}; the gitlab group list is faked at the
    # glab boundary (gate-logic class), the layout loop is the real code.
    e._glab_paginated_group_projects = lambda org: ([{"id": 7, "path_with_namespace": "o/r"}], "ok")
    def fake(pid, parent, leaf):
        rel = (parent + "/" + leaf) if parent else leaf
        return statuses[rel]
    e._glab_tree_has_gitlink = fake
    return e.source2_gitlab(["o"])
std, leg = LR[0], LR[1]
h, r, d = run({std: (False, "error"), leg: (True, "ok")})
print("A_HIT", "o/r" in h, "A_DEG", len(d))
h, r, d = run({std: (False, "error"), leg: (False, "ok")})
print("B_HIT", "o/r" in h, "B_DEG", len(d))
h, r, d = run({std: (False, "error"), leg: (False, "error")})
print("C_HIT", "o/r" in h, "C_DEG", len(d))
h, r, d = run({std: (True, "ok"), leg: (False, "error")})
print("D_HIT", "o/r" in h, "D_DEG", len(d))
PY
)"
lt_check "FC-4: a first-layout probe that could not be decided is NOT degraded when the second layout finds the gitlink" grep -qx 'A_HIT True A_DEG 0' <<<"$fc3"
lt_check "FC-5 (control): undecided first layout + confirmed-absent second -> still recorded degraded, no hit" grep -qx 'B_HIT False B_DEG 1' <<<"$fc3"
lt_check "FC-6 (control): both layouts undecided -> two degraded records" grep -qx 'C_HIT False C_DEG 2' <<<"$fc3"
lt_check "FC-7 (control): found on the first layout -> no degraded record for the unprobed second" grep -qx 'D_HIT True D_DEG 0' <<<"$fc3"

# ============================================================================
# DM: deps-manifest engine, differential
# ============================================================================
ENGINE="$LAYOUT_SRC_ROOT/scripts/deps_manifest/verify_helix_deps_manifests.sh"
DM="$LT_SB/dm"; mkdir -p "$DM"; lt_git init -q "$DM"
printf 'schema_version: 1\ndeps: []\ntransitive_handling:\n  recursive: true\n  conflict_resolution: operator-required\nlanguage_specific_subtree: false\n' > "$DM/helix-deps.yaml"
printf 'x\n' > "$DM/f"; lt_git -C "$DM" add -A; lt_git -C "$DM" commit -q -m i
dm0="$(env A=1 bash "$ENGINE" --root "$DM" 2>&1)"; dmrc0=$?
dm1="$(GIT_DIR="$O/.git" GIT_WORK_TREE="$O" bash "$ENGINE" --root "$DM" 2>&1)"; dmrc1=$?
lt_check "DM-1: the manifest engine answers identically under an ambient GIT_DIR (rc $dmrc0 vs $dmrc1)" \
    eval 'test "$dm0" = "$dm1" && test "$dmrc0" = "$dmrc1" && grep -q "^VERDICT:" <<<"$dm1"'
lt_check "DM-2: ... and the decoy is untouched" test "$(snap "$O")" = "$o0"

# ============================================================================
# ST: static — every git-calling script is scrubbed; the lists are one list
# ============================================================================
st_out="$(python3 - "$LAYOUT_SRC_ROOT" <<'PY' 2>&1
import re, sys, os, glob
root = sys.argv[1]
def rd(p):
    return open(os.path.join(root, p), encoding="utf-8", errors="replace").read()
def vars_in(text):
    return set(re.findall(r"\bGIT_[A-Z_]+\b", text))
EXPECT = set("GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split())
lib = rd("scripts/lib/constitution_layout.sh")
m = re.search(r'^CL_GIT_SCRUB_VARS="([^"]+)"', lib, re.M)
canon = set(m.group(1).split())
print("CANON", len(canon))
# the canonical list is compared with a LITERAL list kept in this test: a consistent rename in every copy
# (all lists edited alike) must not look equal to itself
print("CANONEQ", "ok" if canon == EXPECT else "differs:" + ",".join(sorted(canon ^ EXPECT)))
def check(name, text):
    got = vars_in(text) & {v for v in canon | vars_in(text) if True}
    # the scrub list may only mention names of the class (plus tool-specific extras)
    missing = (canon | EXPECT) - got
    print("LIST", name, "missing=" + ",".join(sorted(missing)) if missing else "ok")
# lone copies: snippet = the lines that unset / iterate the class
def snippet(p, start_re, nlines):
    t = rd(p).split("\n")
    for i, l in enumerate(t):
        if re.search(start_re, l):
            return "\n".join(t[i:i+nlines])
    return ""
check("post_update_hook.sh", snippet("scripts/post_update_hook.sh", r"^for _pu_v in GIT_DIR", 1))
check("post-merge", snippet("scripts/hooks/post-merge", r"^unset GIT_DIR", 5))
check("constitution-submodule-post-checkout", snippet("scripts/hooks/constitution-submodule-post-checkout", r"^unset GIT_DIR", 5))
check("multitrack_constitution_sync.sh", snippet("scripts/multitrack/multitrack_constitution_sync.sh", r"for _v in GIT_DIR", 1))
HI = snippet("scripts/lib/hook_install.sh", r"^\s*\( unset GIT_DIR", 4)
JB = snippet("scripts/jev/bootstrap.sh", r"^\s*\( unset GIT_DIR", 4)
LS = snippet("scripts/label-sync/install_label_sync.sh", r"^\s*\( unset GIT_DIR", 4)
check("hook_install.sh (inline fallback)", HI)
check("jev/bootstrap.sh", JB)
check("label-sync/install_label_sync.sh", LS)
check("migrate.sh", snippet("scripts/fastcycle/consumers/migrate.sh", r"^for _fc_unset_var in", 8))
check("audit.py", snippet("scripts/fastcycle/consumers/audit.py", r"GIT_SCRUB_VARS = \(", 6))
check("helix_deps_manifest.py", snippet("scripts/deps_manifest/helix_deps_manifest.py", r"^GIT_SCRUB_VARS = \(", 6))
# exact equality (no extras) for the pure copies
for name, sn in (("post_update_hook.sh", snippet("scripts/post_update_hook.sh", r"^for _pu_v in GIT_DIR", 1)),
                 ("post-merge", snippet("scripts/hooks/post-merge", r"^unset GIT_DIR", 5)),
                 ("multitrack", snippet("scripts/multitrack/multitrack_constitution_sync.sh", r"for _v in GIT_DIR", 1)),
                 ("audit.py", snippet("scripts/fastcycle/consumers/audit.py", r"GIT_SCRUB_VARS = \(", 6)),
                 ("helix_deps_manifest.py", snippet("scripts/deps_manifest/helix_deps_manifest.py", r"^GIT_SCRUB_VARS = \(", 6)),
                 ("hook_install.sh", HI), ("jev/bootstrap.sh", JB), ("label-sync/install_label_sync.sh", LS)):
    extra = vars_in(sn) - (canon | EXPECT) - {"GIT_SCRUB_VARS"}
    print("EXTRA", name, ",".join(sorted(extra)) if extra else "none")
# every git-calling file of the owned set carries a scrub marker
OWN = ["scripts/setup.sh", "scripts/post_update_hook.sh", "scripts/lib/constitution_layout.sh", "scripts/lib/hook_install.sh",
       "scripts/hooks/post-merge", "scripts/hooks/constitution-submodule-post-checkout", "scripts/hooks/guard-evidence-store-write.sh",
       "scripts/multitrack/multitrack_constitution_sync.sh", "scripts/install_cli_agent_plugins.sh",
       "scripts/deps_manifest/helix_deps_manifest.py", "scripts/gates/cm_canonical_root_clarity.sh",
       "scripts/jev/bootstrap.sh", "scripts/label-sync/install_label_sync.sh"]
OWN += sorted(os.path.relpath(p, root) for p in glob.glob(os.path.join(root, "scripts/fastcycle/consumers/*")) if os.path.isfile(p) and not p.endswith(".pyc"))
MARK = re.compile(r"cl_scrub_git_env|cl__git|chi__git|jb__git|ls__git|scrub_git_env|git_env\(\)|^unset GIT_DIR|for _pu_v in GIT_DIR|for _v in GIT_DIR|for _fc_unset_var|GIT_SCRUB_VARS", re.M)
GITCALL = re.compile(r'(?m)^[^#\n]*(?<![\w./-])git\s+(?:-C\s|-c\s|rev-parse|config|ls-files|ls-tree|merge|fetch|diff|status|submodule|cat-file|remote|init|add|commit|clone|checkout|show|hash-object|read-tree|commit-tree|update-index|rev-list|symbolic-ref)|\["git"|"git",')
calling = []
for p in OWN:
    if not os.path.exists(os.path.join(root, p)):
        continue
    t = rd(p)
    if GITCALL.search(t):
        calling.append(p)
        print("GITCALL", p, "SCRUBBED" if MARK.search(t) else "UNSCRUBBED")
print("NCALLING", len(calling))
PY
)"
printf '%s\n' "$st_out" | sed 's/^/    /' | head -40
lt_check "ST-1: the canonical list was read (15 variables) and equals the literal list kept in this test" \
    eval 'grep -qx "CANON 15" <<<"$st_out" && grep -qx "CANONEQ ok" <<<"$st_out"'
lt_check "ST-2: every lone copy of the scrub list holds ALL canonical variables" \
    eval '! grep -E "^LIST .*missing=" <<<"$st_out" | grep -q . && [ "$(grep -c "^LIST .* ok$" <<<"$st_out")" = 10 ]'
lt_check "ST-3: the pure copies add no variable that is not in the canonical list" \
    eval '[ "$(grep -c "^EXTRA .* none$" <<<"$st_out")" = 8 ]'
lt_check "ST-4: every git-calling script in the owned set carries a scrub (none UNSCRUBBED, >= 10 found)" \
    eval '! grep -q UNSCRUBBED <<<"$st_out" && [ "$(sed -n "s/^NCALLING //p" <<<"$st_out")" -ge 10 ]'

# ============================================================================
# SV: RUNTIME, table-driven over ALL 15 repository-locating variables: dropping any
#     ONE of them from any scrubbing copy lets that variable reach the child git.
#     The 15 names are a LITERAL list in this test (not read from the code under test,
#     so a rename applied consistently in every copy is still caught).
# ============================================================================
SV_VARS="GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX"
SV_STUB="$LT_SB/sv_stub"; mkdir -p "$SV_STUB"; SV_REALGIT="$(command -v git)"
# the stub `git` reports whether the variable named in $SV_WATCH reached it, then runs the real git
printf '#!/bin/sh\nif eval "[ -n \\"\\${$SV_WATCH+x}\\" ]"; then echo "LEAK:$SV_WATCH"; else echo "CLEAN:$SV_WATCH"; fi\nexec "%s" "$@"\n' "$SV_REALGIT" > "$SV_STUB/git"
chmod +x "$SV_STUB/git"
SV_LONE="$LT_SB/sv_lone"; mkdir -p "$SV_LONE"; cp "$LAYOUT_SRC_ROOT/scripts/lib/hook_install.sh" "$SV_LONE/"
# extracted inline helpers of the two scripts (their real function text)
sv_fn() { sed -n "/^$2() {/,/^}/p" "$LAYOUT_SRC_ROOT/$1"; }
sv_fn scripts/jev/bootstrap.sh jb__scrubbed > "$SV_LONE/jbs.sh"
sv_fn scripts/jev/bootstrap.sh jb__git > "$SV_LONE/jb.sh"; sv_fn scripts/label-sync/install_label_sync.sh ls__git > "$SV_LONE/ls.sh"
lt_check "SV-0 (needle): both inline helpers were extracted" eval 'test -s "$SV_LONE/jb.sh" && test -s "$SV_LONE/ls.sh" && test -s "$SV_LONE/jbs.sh"'
sv_run() { # COPY VAR -> stub verdict for that variable set ambiently
    local copy="$1" v="$2" setup fn
    case "$copy" in
        lib)  setup=". '$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh'"; fn=cl__git ;;
        lone) setup=". '$SV_LONE/hook_install.sh'"; fn=chi__git ;;
        main) setup=". '$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh'; . '$LAYOUT_SRC_ROOT/scripts/lib/hook_install.sh'"; fn=chi__git ;;
        jb)   setup=". '$SV_LONE/jb.sh'"; fn=jb__git ;;
        ls)   setup=". '$SV_LONE/ls.sh'"; fn=ls__git ;;
        jbs)  setup=". '$SV_LONE/jbs.sh'"; fn="jb__scrubbed git" ;;   # child-installer scrub (round 9, finding 3)
    esac
    env "$v=/nonexistent-sv" SV_WATCH="$v" PATH="$SV_STUB:$PATH" bash -c "$setup; $fn --version" 2>/dev/null | sed -n '1p'
}
for sv_copy in lib lone main jb ls jbs; do
    sv_bad=""; sv_n=0
    for sv_v in $SV_VARS; do
        sv_n=$((sv_n+1)); r="$(sv_run "$sv_copy" "$sv_v")"
        [ "$r" = "CLEAN:$sv_v" ] || sv_bad="$sv_bad $sv_v($r)"
    done
    lt_check "SV-$sv_copy: no one of the $sv_n repository-locating variables reaches the child git through the '$sv_copy' scrub${sv_bad:+ (LEAKING:$sv_bad)}" test -z "$sv_bad" -a "$sv_n" = 15
done
# positive control for the instrument itself: a variable outside the class is NOT scrubbed (the stub can see)
r="$(env GIT_AUTHOR_NAME=x SV_WATCH=GIT_AUTHOR_NAME PATH="$SV_STUB:$PATH" bash -c ". '$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh'; cl__git --version" 2>/dev/null | sed -n 1p)"
lt_check "SV-ctl: control needle: an identity variable still reaches the child (the stub can see a variable) -> '$r'" test "$r" = "LEAK:GIT_AUTHOR_NAME"

# jev/bootstrap.sh and label-sync/install_label_sync.sh: an ambient GIT_DIR naming a decoy is never written to
mkdecoy "$O"; o0="$(snap "$O")"
JP="$LT_SB/jb_proj"; lt_git init -q "$JP"; printf 'j\n' > "$JP/f"; lt_git -C "$JP" add f; lt_git -C "$JP" commit -q -m j
for sv_c in "jb:jb__git" "ls:ls__git"; do
    f="${sv_c#*:}"
    out="$(GIT_DIR="$O/.git" GIT_WORK_TREE="$O" bash -c ". '$SV_LONE/${sv_c%%:*}.sh'; $f -C '$JP' rev-parse --show-toplevel; $f -C '$JP' config constitution.svprobe 1; $f -C '$JP' commit -q --allow-empty -m svprobe" 2>&1)"
    lt_check "SV-${sv_c%%:*}-decoy: $f under GIT_DIR/GIT_WORK_TREE of a decoy reads and WRITES the project (toplevel+config+commit), decoy byte-for-byte unchanged" \
        eval '[ "$out" = "$JP" ] && [ "$(git -C "$JP" config --local --get constitution.svprobe)" = 1 ] && [ "$(git -C "$JP" log -1 --format=%s)" = svprobe ] && [ "$(snap "$O")" = "$o0" ]'
    git -C "$JP" reset -q --hard HEAD~1 2>/dev/null; git -C "$JP" config --local --unset constitution.svprobe
done
# the real scripts really route their git calls through the helper (no bare `git -C`/`git clone` left)
lt_check "SV-jb-static: jev/bootstrap.sh has no bare git call outside jb__git" \
    eval '! grep -nE "^[^#]*[ (\$\`]git (-C|clone|fetch|checkout|status|rev-parse)" "$LAYOUT_SRC_ROOT/scripts/jev/bootstrap.sh" | grep -v "jb__git"'
jbs_static() { # every child-installer command in jev/bootstrap.sh appears only as `jb__scrubbed <cmd>`
    local JBF="$LAYOUT_SRC_ROOT/scripts/jev/bootstrap.sh" c
    for c in 'make -C "$path" install' 'bash "$path/scripts/install.sh"' 'bash "$TK_SETUP" --check' 'bash "$TK_SETUP" --agents'; do
        grep -qF "jb__scrubbed $c" "$JBF" || return 1
        [ "$(grep -F "$c" "$JBF" | grep -vcF "jb__scrubbed $c")" = 0 ] || return 1
    done
}
lt_check "SV-jbs-static: every child installer call in jev/bootstrap.sh (make install, install.sh, jev-setup x2) goes through jb__scrubbed" jbs_static
lt_check "SV-ls-static: label-sync/install_label_sync.sh has no bare git call outside ls__git" \
    eval '! grep -nE "^[^#]*[ (\$\`]git (-C|clone|fetch|checkout|status|rev-parse)" "$LAYOUT_SRC_ROOT/scripts/label-sync/install_label_sync.sh" | grep -v "ls__git"'
# end-to-end: the REAL install_label_sync.sh --request-ledger judges the ledger against the ledger's OWN
# repository. Under an ambient GIT_DIR naming a decoy, a ledger in a NON-git directory must not be reported as
# "inside a git work tree" (an unscrubbed `git -C` would answer for the decoy); a ledger inside a real work
# tree is still warned about (positive control).
NG="$LT_SB/ls_nogit"; mkdir -p "$NG"; mkdir -p "$LT_SB/ls_home"
LSP="$LT_SB/ls_proj"; lt_git init -q "$LSP"; printf 'l\n' > "$LSP/f"; lt_git -C "$LSP" add f; lt_git -C "$LSP" commit -q -m l
lsr() { # PROJECT_ROOT [env...]
    local pr="$1"; shift
    env "$@" bash "$LAYOUT_SRC_ROOT/scripts/label-sync/install_label_sync.sh" --dry-run --scope project --project-root "$pr" \
        --home "$LT_SB/ls_home" --constitution-root "$LAYOUT_SRC_ROOT" --request-ledger "$pr/ledger.jsonl" --other-settings "$LT_SB/none.json" 2>&1
}
sv_a="$(lsr "$NG" A=1)"; sv_b="$(lsr "$NG" GIT_DIR="$O/.git" GIT_WORK_TREE="$O")"; sv_c="$(lsr "$LSP" GIT_DIR="$O/.git" GIT_WORK_TREE="$O")"
lt_check "SV-ls-run-ctl: control (nothing ambient): a ledger in a non-git dir is not warned about" eval '! grep -q "is inside a git work tree" <<<"$sv_a"'
lt_check "SV-ls-run-1: under an ambient GIT_DIR of a decoy a non-git ledger dir is still NOT reported as inside a work tree" eval '! grep -q "is inside a git work tree" <<<"$sv_b"'
lt_check "SV-ls-run-2: ... and a ledger inside the project's own work tree IS warned about (positive control); decoy untouched" \
    eval 'grep -q "is inside a git work tree" <<<"$sv_c" && [ "$(snap "$O")" = "$o0" ]'

# ============================================================================
# LK: hook locks, stamps and messages
# ============================================================================
# a project whose setup.sh has run and whose upstream moved on, for lock tests
mklock() { mkmoved "$1" || return 1; GD="$(git -C "$B" rev-parse --absolute-git-dir)"; LKF="$GD/constitution-pending-update.lock"; }
lockfile() { printf 'PID=%s\nSTART=%s\nNONCE=%s\n' "$1" "$2" "$3" > "$LKF"; }

# --- setup.sh -----------------------------------------------------------------
mklock lk1 || lt_bad "fixture lk1"
lockfile "$(dead_pid)" "12345" "dead-nonce"
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/lk.out" 2>&1; rc=$?
lt_check "LK-1: setup.sh RECLAIMS a lock whose recorded owner pid is gone and then propagates (rc=$rc)" \
    eval 'test "$(calls)" = 1 && grep -q "reclaimed a stale propagation lock" "$LT_SB/lk.out" && test ! -e "$LKF"'
mklock lk2 || lt_bad "fixture lk2"
sleep 300 & LIVE=$!; LT_BG_PIDS="${LT_BG_PIDS:-} $LIVE"
lockfile "$LIVE" "$(proc_start "$LIVE")" "live-nonce"
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/lk.out" 2>&1; rc=$?
lt_check "LK-2 (control): a lock held by a LIVE process is never reclaimed: setup.sh is INCOMPLETE (rc=$rc), lock untouched, hook not run" \
    eval 'test "$rc" -ne 0 && test "$(calls)" = 0 && grep -q "NONCE=live-nonce" "$LKF" && grep -q "propagation lock" "$LT_SB/lk.out"'
lt_check "LK-2b: the busy message prints the holder record (PID=$LIVE, START) and says the owner is ALIVE" \
    eval 'grep -q "holder record: PID=$LIVE START=$(proc_start "$LIVE"): the owner is ALIVE" "$LT_SB/lk.out"'
mklock lk3 || lt_bad "fixture lk3"
lockfile "$LIVE" "1" "reused-nonce"
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/lk.out" 2>&1; rc=$?
lt_check "LK-3: a lock whose pid is alive but with a DIFFERENT start time (pid reused) is reclaimed (rc=$rc)" \
    eval 'test "$(calls)" = 1 && grep -q "reclaimed a stale propagation lock" "$LT_SB/lk.out"'
mklock lk4 || lt_bad "fixture lk4"
printf 'garbage\n' > "$LKF"
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/lk.out" 2>&1; rc=$?
lt_check "LK-4 (control): a lock without a readable owner record is left alone (rc=$rc)" \
    eval 'test "$rc" -ne 0 && test "$(calls)" = 0 && grep -qx garbage "$LKF"'
lt_check "LK-4b: ... and the busy message says why: no readable owner record" \
    eval 'grep -q "holder record: no readable owner record" "$LT_SB/lk.out"'
mklock lk5 || lt_bad "fixture lk5"
ln -s "$LT_SB/nowhere" "$LKF"
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/lk.out" 2>&1; rc=$?
lt_check "LK-5 (control): a symlink lock is never followed or reclaimed (rc=$rc)" \
    eval 'test "$rc" -ne 0 && test "$(calls)" = 0 && test -L "$LKF" && ! test -e "$LT_SB/nowhere"'

lt_check "LK-5b: ... and the busy message says why: the lock is a symlink" \
    eval 'grep -q "holder record: the lock is a symlink" "$LT_SB/lk.out"'
# the lock comments describe what the code does (setup.sh / post-merge DO reclaim provably-dead locks)
lt_check "LK-5c: no stale comment claims setup.sh / post-merge never take over or reclaim a lock" \
    eval '! grep -q "never taken" "$LAYOUT_SRC_ROOT/scripts/setup.sh" && ! grep -q "never reclaims" "$LAYOUT_SRC_ROOT/scripts/hooks/post-merge" && ! grep -q "never$" <(sed -n 20,26p "$LAYOUT_SRC_ROOT/scripts/hooks/post-merge") && grep -q "owner-less" "$LAYOUT_SRC_ROOT/scripts/setup.sh" && grep -q "owner-less" "$LAYOUT_SRC_ROOT/scripts/hooks/post-merge"'

# --- R23: the setup lock is created EXCLUSIVELY (deterministic race) ------------
SETUP="$LAYOUT_SRC_ROOT/scripts/setup.sh"
r23="$(bash -c '
    SETUP=$1; SB=$2
    kv() { [ -f "$1" ] || return 1; local l; while IFS= read -r l; do case "$l" in "$2="*) printf "%s" "${l#"$2"=}"; return 0 ;; esac; done < "$1"; return 1; }
    eval "$(sed -n "/^pu_start() {/p;/^pu_lock_mine() {/p" "$SETUP")"
    eval "$(sed -n "/^pu_lock_create() {/,/^}/p" "$SETUP")"
    PU_LOCK="$SB/r23.lock"; PU_NONCE="mine"; rm -f "$PU_LOCK"
    DONE="$SB/r23.done"; rm -f "$DONE"
    # the lock appears (a foreign live holder) right AFTER the existence check said "free"
    [() { builtin [ "$@"; local r=$?; if builtin [ "$1" = -e ] && builtin [ "$2" = "$PU_LOCK" ] && builtin [ ! -e "$DONE" ]; then : > "$DONE"; printf "PID=1\nSTART=1\nNONCE=foreign\n" > "$PU_LOCK"; fi; return $r; }
    if pu_lock_create; then echo CREATED; else echo REFUSED; fi
    echo "NONCE=$(kv "$PU_LOCK" NONCE)"
' _ "$SETUP" "$LT_SB" 2>&1)"
lt_check "LK-6: setup.sh's lock create is exclusive: a lock appearing between the check and the create is NOT overwritten ($(tr '\n' ' ' <<<"$r23"))" \
    eval 'grep -qx REFUSED <<<"$r23" && grep -qx "NONCE=foreign" <<<"$r23"'

# --- put-back: a live holder's lock created after the stale snapshot is judged is linked back (deterministic race)
rb="$(bash -c '
    SETUP=$1; SB=$2; DEADP=$3
    kv() { [ -f "$1" ] || return 1; local l; while IFS= read -r l; do case "$l" in "$2="*) printf "%s" "${l#"$2"=}"; return 0 ;; esac; done < "$1"; return 1; }
    warn() { :; }
    eval "$(sed -n "/^pu_start() {/p;/^pu_lock_reclaim_dead() {/,/^}/p" "$SETUP")"
    PU_LOCK="$SB/rb.lock"; PU_NONCE="mine"; safe=1
    printf "PID=%s\nSTART=1\nNONCE=deadn\n" "$DEADP" > "$PU_LOCK"
    LIVEST="$(pu_start $$)"; DONE="$SB/rb.done"; rm -f "$DONE"
    # the stale lock is judged dead; before the rename a LIVE holder replaces it with its own lock
    mv() { if [ ! -e "$DONE" ]; then : > "$DONE"; printf "PID=%s\nSTART=%s\nNONCE=live\n" "$$" "$LIVEST" > "$PU_LOCK"; fi; command mv "$@"; }
    if pu_lock_reclaim_dead; then echo RECLAIMED; else echo KEPT; fi
    echo "NONCE=$(kv "$PU_LOCK" NONCE)"
    ls "$SB" | grep -c "^rb.lock.stale" | sed "s/^/STALELEFT=/"
' _ "$SETUP" "$LT_SB" "$(dead_pid)" 2>&1)"
lt_check "LK-16: setup.sh puts a live holder's freshly created lock BACK instead of reclaiming it ($(tr '\n' ' ' <<<"$rb"))" \
    eval 'grep -qx KEPT <<<"$rb" && grep -qx "NONCE=live" <<<"$rb" && grep -qx "STALELEFT=0" <<<"$rb"'

# --- put-back must NOT clobber: a THIRD run's lock created after the live one was moved aside (deterministic race)
# the stale lock is judged dead; a live holder replaces it; the rename moves THAT aside; then a third run creates its
# own lock at the path; the put-back `ln` must fail (no `ln -f`), so the third run's lock is kept.
rc3="$(bash -c '
    SETUP=$1; SB=$2; DEADP=$3
    kv() { [ -f "$1" ] || return 1; local l; while IFS= read -r l; do case "$l" in "$2="*) printf "%s" "${l#"$2"=}"; return 0 ;; esac; done < "$1"; return 1; }
    warn() { :; }
    eval "$(sed -n "/^pu_start() {/p;/^pu_lock_reclaim_dead() {/,/^}/p" "$SETUP")"
    PU_LOCK="$SB/rc3.lock"; PU_NONCE="mine"
    printf "PID=%s\nSTART=1\nNONCE=deadn\n" "$DEADP" > "$PU_LOCK"
    LIVEST="$(pu_start $$)"; DONE="$SB/rc3.done"; rm -f "$DONE"
    mv() { if [ ! -e "$DONE" ]; then : > "$DONE"; printf "PID=%s\nSTART=%s\nNONCE=live\n" "$$" "$LIVEST" > "$PU_LOCK"; command mv "$@"; printf "PID=%s\nSTART=%s\nNONCE=third\n" "$$" "$LIVEST" > "$PU_LOCK"; else command mv "$@"; fi; }
    if pu_lock_reclaim_dead; then echo RECLAIMED; else echo KEPT; fi
    echo "NONCE=$(kv "$PU_LOCK" NONCE)"
' _ "$SETUP" "$LT_SB" "$(dead_pid)" 2>&1)"
lt_check "LK-16b: setup.sh's put-back never clobbers a lock a THIRD run created meanwhile ($(tr '\n' ' ' <<<"$rc3"))" \
    eval 'grep -qx KEPT <<<"$rc3" && grep -qx "NONCE=third" <<<"$rc3"'
PMH="$LAYOUT_SRC_ROOT/scripts/hooks/post-merge"
rp3="$(bash -c '
    PMH=$1; SB=$2; DEADP=$3
    kv() { [ -f "$1" ] || return 1; local l; while IFS= read -r l; do case "$l" in "$2="*) printf "%s" "${l#"$2"=}"; return 0 ;; esac; done < "$1"; return 1; }
    warn() { :; }
    eval "$(sed -n "/^    pm_start() {/p;/^    pm_lock_reclaim_dead() {/,/^    }/p" "$PMH")"
    PM_LOCK="$SB/rp3.lock"; PM_NONCE="mine"
    printf "PID=%s\nSTART=1\nNONCE=deadn\n" "$DEADP" > "$PM_LOCK"
    LIVEST="$(pm_start $$)"; DONE="$SB/rp3.done"; rm -f "$DONE"
    mv() { if [ ! -e "$DONE" ]; then : > "$DONE"; printf "PID=%s\nSTART=%s\nNONCE=live\n" "$$" "$LIVEST" > "$PM_LOCK"; command mv "$@"; printf "PID=%s\nSTART=%s\nNONCE=third\n" "$$" "$LIVEST" > "$PM_LOCK"; else command mv "$@"; fi; }
    if pm_lock_reclaim_dead; then echo RECLAIMED; else echo KEPT; fi
    echo "NONCE=$(kv "$PM_LOCK" NONCE)"
' _ "$PMH" "$LT_SB" "$(dead_pid)" 2>&1)"
lt_check "LK-16c: post-merge's put-back never clobbers a lock a THIRD run created meanwhile ($(tr '\n' ' ' <<<"$rp3"))" \
    eval 'grep -qx KEPT <<<"$rp3" && grep -qx "NONCE=third" <<<"$rp3"'

# --- post-merge ----------------------------------------------------------------
mklock lk7 || lt_bad "fixture lk7"
lockfile "$(dead_pid)" "12345" "dead-nonce"
( cd "$B" && A=1 bash .git/hooks/post-merge 0 ) >"$LT_SB/lk.out" 2>&1
lt_check "LK-7: post-merge RECLAIMS a lock whose owner is gone and propagates" \
    eval 'test "$(calls)" = 1 && grep -q "reclaimed a stale propagation lock" "$LT_SB/lk.out" && test ! -e "$LKF"'
mklock lk8 || lt_bad "fixture lk8"
lockfile "$LIVE" "$(proc_start "$LIVE")" "live-nonce"
( cd "$B" && A=1 bash .git/hooks/post-merge 0 ) >"$LT_SB/lk.out" 2>&1
lt_check "LK-8 (control): post-merge never reclaims a live holder's lock; propagation stays pending, stamp recorded" \
    eval 'test "$(calls)" = 0 && grep -q "NONCE=live-nonce" "$LKF" && test -f "$GD/constitution-pending-update"'
# F2: the lock-held message names the real command; executing it proves it
LKMSG="$LT_SB/lk.out"
lt_check "LK-9: the lock-held message does not claim that 'git submodule update' consumes the stamp" \
    eval '! grep -q "next .git submodule update. / setup.sh run consumes" "$LKMSG" && grep -q "does NOT consume it" "$LKMSG"'
lt_check "LK-10: the lock-held message names setup.sh as the way to consume the stamp" grep -q 'setup\.sh' "$LKMSG"
rm -f "$LKF"; : > "$LAYOUT_RECORD"
( cd "$B" && lt_git submodule update -- "$REL" ) >/dev/null 2>&1
lt_check "LK-11: ... and 'git submodule update' really does NOT consume it (checkout already at the gitlink: stamp kept, no run)" \
    eval 'test -f "$GD/constitution-pending-update" && test "$(calls)" = 0'
cmd_line="$(grep -F 'setup.sh' "$LKMSG" | grep -F 'consumes the stamp' | head -1 | sed 's/^\[post-merge\] WARNING: *//; s/  *(consumes.*$//')"
( eval "$cmd_line" ) >"$LT_SB/lk_run.out" 2>&1; rc=$?
lt_check "LK-12: the printed command ('$cmd_line') really consumes the stamp: hook run with the recorded range, stamp gone (rc=$rc)" \
    eval 'test "$(calls)" = 1 && grep -qF " OLD=$V1 NEW=$V2" "$LAYOUT_RECORD" && test ! -e "$GD/constitution-pending-update"'
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null

# --- R22: the early already-applied shortcut --------------------------------
mklock lk9 || lt_bad "fixture lk9"
sleep 300 & LIVE=$!; LT_BG_PIDS="${LT_BG_PIDS:-} $LIVE"
printf 'REL=%s\nREF=%s\n' "$REL" "$V2" > "$GD/constitution-applied-ref"
lockfile "$LIVE" "$(proc_start "$LIVE")" "live-nonce"
( cd "$B" && A=1 bash .git/hooks/post-merge 0 ) >"$LT_SB/lk.out" 2>&1
lt_check "LK-13: an already-applied gitlink exits quietly BEFORE any lock handling (live lock untouched, no lock warning, no stamp)" \
    eval 'grep -q "already propagated" "$LT_SB/lk.out" && ! grep -q "propagation lock" "$LT_SB/lk.out" && test ! -e "$GD/constitution-pending-update" && test "$(calls)" = 0'
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null

# --- R10: setup.sh consumes only a stamp whose ROOT matches ---------------------
mkmoved st1 || lt_bad "fixture st1"
GD="$(git -C "$B" rev-parse --absolute-git-dir)"
printf 'ROOT=%s\nREL=%s\nOLD=%s\nNEW=%s\n' "/some/foreign/root" "$REL" "$V1" "$V2" > "$GD/constitution-pending-update"
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/st.out" 2>&1
lt_check "LK-14: a stamp whose ROOT is another project's is NOT consumed (hook runs without its range; stamp kept)" \
    eval 'test "$(calls)" = 1 && grep -q " OLD=<unset> NEW=<unset>" "$LAYOUT_RECORD" && ! grep -q "consuming the pending update stamp" "$LT_SB/st.out" && test -f "$GD/constitution-pending-update"'
mkmoved st2 || lt_bad "fixture st2"
GD="$(git -C "$B" rev-parse --absolute-git-dir)"
printf 'ROOT=%s\nREL=%s\nOLD=%s\nNEW=%s\n' "$(cd "$B" && pwd -P)" "$REL" "$V1" "$V2" > "$GD/constitution-pending-update"
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/st.out" 2>&1
lt_check "LK-15 (control): the same stamp with the right ROOT IS consumed (range handed over, stamp removed)" \
    eval 'grep -qF " OLD=$V1 NEW=$V2" "$LAYOUT_RECORD" && grep -q "consuming the pending update stamp" "$LT_SB/st.out" && test ! -e "$GD/constitution-pending-update"'

# ============================================================================
# AR: applied-ref only after a SUCCESSFUL post-update run
# ============================================================================
APPLIED_OF() { printf '%s/constitution-applied-ref' "$(git -C "$1" rev-parse --absolute-git-dir)"; }
mkmoved ar1 || lt_bad "fixture ar1"
( cd "$B" && LAYOUT_STUB_EXIT=3 A=1 bash .git/hooks/post-merge 0 ) >"$LT_SB/ar.out" 2>&1
GD="$(git -C "$B" rev-parse --absolute-git-dir)"
lt_check "AR-1: post-merge, post-update FAILED (exit 3): the applied ref is NOT advanced to the new gitlink and a pending stamp is kept" \
    eval '! grep -qx "REF=$V2" "$GD/constitution-applied-ref" && grep -qx "NEW=$V2" "$GD/constitution-pending-update" && grep -q "NOT recorded as applied" "$LT_SB/ar.out"'
: > "$LAYOUT_RECORD"
( cd "$B" && A=1 bash .git/hooks/post-merge 0 ) >"$LT_SB/ar.out" 2>&1
lt_check "AR-2: ... the retry runs the hook again (range kept), succeeds, then records the ref and removes the stamp" \
    eval 'test "$(calls)" = 1 && grep -qx "REF=$V2" "$GD/constitution-applied-ref" && test ! -e "$GD/constitution-pending-update"'
mkmoved ar3 || lt_bad "fixture ar3"
GD="$(git -C "$B" rev-parse --absolute-git-dir)"
printf 'ROOT=%s\nREL=%s\nOLD=%s\nNEW=%s\n' "$(cd "$B" && pwd -P)" "$REL" "$V1" "$V2" > "$GD/constitution-pending-update"
CHOOK="$(git -C "$B/$REL" rev-parse --path-format=absolute --git-path hooks)/post-checkout"
( cd "$B/$REL" && LAYOUT_STUB_EXIT=3 bash "$CHOOK" 0 0 1 ) >"$LT_SB/ar.out" 2>&1
lt_check "AR-3: consumer hook, post-update FAILED: applied ref not advanced, the stamp is KEPT" \
    eval '! grep -qx "REF=$V2" "$GD/constitution-applied-ref" && grep -qx "OLD=$V1" "$GD/constitution-pending-update" && grep -q "NOT recorded as applied" "$LT_SB/ar.out"'
: > "$LAYOUT_RECORD"
( cd "$B/$REL" && bash "$CHOOK" 0 0 1 ) >"$LT_SB/ar.out" 2>&1
lt_check "AR-4: ... the retry runs, records the ref and removes the stamp" \
    eval 'test "$(calls)" = 1 && grep -qx "REF=$V2" "$GD/constitution-applied-ref" && test ! -e "$GD/constitution-pending-update"'
mkmoved ar5 || lt_bad "fixture ar5"
GD="$(git -C "$B" rev-parse --absolute-git-dir)"
printf 'ROOT=%s\nREL=%s\nOLD=%s\nNEW=%s\n' "$(cd "$B" && pwd -P)" "$REL" "$V1" "$V2" > "$GD/constitution-pending-update"
( cd "$B" && LAYOUT_STUB_EXIT=3 bash "$REL/scripts/setup.sh" ) >"$LT_SB/ar.out" 2>&1; rc=$?
lt_check "AR-5: setup.sh, post-update FAILED: exit non-zero, no applied ref recorded, stamp kept (rc=$rc)" \
    eval 'test "$rc" -ne 0 && ! grep -qx "REF=$V2" "$GD/constitution-applied-ref" && test -f "$GD/constitution-pending-update"'
( cd "$B" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/ar.out" 2>&1; rc=$?
lt_check "AR-6: ... the retry succeeds, records the ref and consumes the stamp (rc=$rc)" \
    eval 'test "$rc" -eq 0 && grep -qx "REF=$V2" "$GD/constitution-applied-ref" && test ! -e "$GD/constitution-pending-update"'

# ============================================================================
# CM: STEP 5 never changes the mode of a TRACKED file (a chmod would dirty the
#     consumer's submodule and the next update refuses with rc=3 "local changes")
# ============================================================================
printf '#!/usr/bin/env bash\necho probe 1\n' > "$RC/scripts/zz_chmod_probe_lib.sh"; chmod 644 "$RC/scripts/zz_chmod_probe_lib.sh"
lt_git -C "$RC" add -A >/dev/null; lt_git -C "$RC" commit -q -m probe1; CA="$(git -C "$RC" rev-parse HEAD)"
printf 'echo probe 2\n' >> "$RC/scripts/zz_chmod_probe_lib.sh"
lt_git -C "$RC" commit -q -a -m probe2; CB="$(git -C "$RC" rev-parse HEAD)"
lt_git clone -q --bare "$RC" "$LT_SB/realc3.git"
P="$LT_SB/real_cm"; mkdir -p "$P"; lt_git init -q "$P"; printf 'x\n' > "$P/README.md"
lt_git -C "$P" add .; lt_git -C "$P" commit -q -m i
lt_git -C "$P" submodule add -q "file://$LT_SB/realc3.git" "$REL" >/dev/null 2>&1
lt_git -C "$P" commit -q -m add
git -C "$P/$REL" checkout -q "$CB"
PUH="$P/$REL/scripts/post_update_hook.sh"
( cd "$P" && env HOME="$LT_SB/home" CONSTITUTION_UPDATE_OLD_REF="$CA" CONSTITUTION_UPDATE_NEW_REF="$CB" \
    timeout 600 bash "$PUH" ) >"$LT_SB/cm.out" 2>&1; rc=$?
lt_check "CM-1: the REAL hook ran STEP 5 over a changed tracked 100644 script (positive control, rc=$rc)" \
    eval 'grep -q "STEP 5" "$LT_SB/cm.out" && git -C "$P/$REL" ls-files -s -- scripts/zz_chmod_probe_lib.sh | grep -q "^100644 "'
# control needle (against a false-null): the probe path must have been ENUMERATED by STEP 5 and taken the
# tracked branch. The tracked-branch warning names the path; a run that never saw the probe stays silent and
# would leave the mode "unchanged" for the wrong reason.
lt_check "CM-1b: ... and STEP 5 enumerated the probe path (the tracked-not-executable warning names scripts/zz_chmod_probe_lib.sh)" \
    grep -q "tracked script is not executable (mode left unchanged): scripts/zz_chmod_probe_lib.sh" "$LT_SB/cm.out"
lt_check "CM-2: ... the tracked script mode is unchanged and the submodule is clean (porcelain empty)" \
    eval 'test ! -x "$P/$REL/scripts/zz_chmod_probe_lib.sh" && test -z "$(git -C "$P/$REL" status --porcelain)"'
# the next update is not blocked: run the REAL update_constitution.sh (--check --no-hook: it performs its own
# `status --porcelain` local-changes refusal first, exit 3, before anything else)
( cd "$P" && env HOME="$LT_SB/home" bash "$P/$REL/scripts/update_constitution.sh" --check --no-hook --project-root "$P" ) >"$LT_SB/cm_up.out" 2>&1; rc_up=$?
lt_check "CM-3: ... so the REAL update_constitution.sh --check is not refused for local changes (rc=$rc_up)" \
    eval '! grep -q "has local changes" "$LT_SB/cm_up.out" && test "$rc_up" -eq 0 && grep -q "UPDATE_AVAILABLE=" "$LT_SB/cm_up.out"'
# CM-4: an UNTRACKED script changed in the range IS chmod'd by the REAL hook. The probe is dropped from the
# submodule index (still in the work tree, 644), then the real hook runs again over the same range.
git -C "$P/$REL" rm -q --cached -- scripts/zz_chmod_probe_lib.sh; chmod 644 "$P/$REL/scripts/zz_chmod_probe_lib.sh"
lt_check "CM-4a (precondition): the probe is now untracked and not executable" \
    eval '! git -C "$P/$REL" ls-files --error-unmatch -- scripts/zz_chmod_probe_lib.sh >/dev/null 2>&1 && test ! -x "$P/$REL/scripts/zz_chmod_probe_lib.sh"'
( cd "$P" && env HOME="$LT_SB/home" CONSTITUTION_UPDATE_OLD_REF="$CA" CONSTITUTION_UPDATE_NEW_REF="$CB" \
    timeout 600 bash "$PUH" ) >"$LT_SB/cm4.out" 2>&1; rc4=$?
lt_check "CM-4: the REAL hook made the UNTRACKED changed script executable (rc=$rc4)" \
    eval 'grep -q "STEP 5" "$LT_SB/cm4.out" && test -x "$P/$REL/scripts/zz_chmod_probe_lib.sh"'

lt_summary
