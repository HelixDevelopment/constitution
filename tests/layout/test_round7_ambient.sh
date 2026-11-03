#!/usr/bin/env bash
# tests/layout/test_round7_ambient.sh — round-7 class fix: an AMBIENT
# environment (CONST_DIR / PROJECT_ROOT / cwd exported or left over for another
# project) never selects the repository that setup.sh or post_update_hook.sh
# writes to; plus M-4 (gitlink-first for any .gitmodules path).
#
# Purpose: one check per entry point, each with a positive control:
#   SA  setup.sh, submodule layout: ambient CONST_DIR of another checkout ->
#       refused (exit 2), nothing written anywhere; own CONST_DIR -> accepted;
#   SV  setup.sh, legacy VENDORED plain copy (not a gitlink): ambient
#       PROJECT_ROOT -> ignored (owner = the work tree holding the copy);
#       explicit --project-root -> honoured; ambient CONST_DIR -> refused;
#   PA  post_update_hook.sh (the REAL one), a range that touches skills,
#       actions, mcp, plugins, hooks (steps 2, 2b, 3, 4, 4b, 4c, 4d run):
#       ambient PROJECT_ROOT -> the other repository is byte-for-byte
#       unchanged, the owner gets the writes; ambient cwd likewise; ambient
#       CONST_DIR -> refused, nothing written; explicit --project-root
#       honoured; a vendored real copy behaves the same;
#   PL  (W2 contract) the REAL hook under a HELD helix-constitution-install.lock
#       with HELIX_CONSTITUTION_LOCK_DELEGATED valid / foreign-live / dead /
#       garbage / unset: always runs, never refuses on that lock, never
#       touches it (the hook takes no lock and trusts no such variable);
#   PO  cl_owner_project_of (lib) and pu_owner_of (inlined in post_update_hook)
#       agree on submodule / vendored / standalone / non-git fixtures;
#   G4  M-4: a gitlink at a custom .gitmodules path beats a vendored plain
#       ./constitution copy (lib + post-merge).
# Usage: bash tests/layout/test_round7_ambient.sh
# Inputs: LAYOUT_SRC_ROOT (tree under test; default this repo).
# Outputs: PASS/FAIL lines, summary; exit 0 iff all pass.
# Side-effects: none outside one mktemp -d sandbox (removed with safe_rm_rf);
#   HOME is a sandbox dir for the real post-update runs; CONSTITUTION_JEV_HOOK=off.
# Test doubles (§11.4.289): SA/SV/G4 use the harness's recording-stub
#   post_update_hook.sh (gate-logic class); PA/PO run the REAL hook.
# Dependencies: bash, git, find, sha256sum, sort.
# Cross-references: scripts/setup.sh, scripts/post_update_hook.sh,
#   scripts/lib/constitution_layout.sh (cl_owner_project_of), scripts/hooks/post-merge.
LT_SUITE="round7_ambient"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

URL="$(lt_make_const_upstream r7)"
export LAYOUT_RECORD="$LT_SB/record.txt"; : > "$LAYOUT_RECORD"
calls() { grep -c '^CALLED ' "$LAYOUT_RECORD" 2>/dev/null || true; }
REL=submodules/constitution
# snap DIR -> one line per path + content hash (git object store excluded)
snap() { ( cd "$1" && find . -path ./.git/objects -prune -o -print0 | sort -z | \
    while IFS= read -r -d '' f; do
        if [ -L "$f" ]; then printf 'L %s -> %s\n' "$f" "$(readlink "$f")"
        elif [ -f "$f" ]; then printf 'F %s %s\n' "$f" "$(sha256sum < "$f" | cut -c1-64)"
        else printf 'D %s\n' "$f"; fi
    done ) | sha256sum | cut -c1-64; }

# ============================================================================
# SA: setup.sh, submodule layout
# ============================================================================
A="$LT_SB/projA"; Bp="$LT_SB/projB"
lt_make_project "$A" "$URL" "$REL" || lt_bad "fixture A"
lt_make_project "$Bp" "$URL" "$REL" || lt_bad "fixture B"
sa0="$(snap "$A")"; sb0="$(snap "$Bp")"
( cd "$A" && CONST_DIR="$Bp/$REL" bash "$REL/scripts/setup.sh" ) >"$LT_SB/sa.out" 2>&1; rc=$?
lt_check "SA: ambient CONST_DIR naming ANOTHER project's checkout -> setup.sh refuses (rc=$rc), says why" \
    eval '[ "$rc" = 2 ] && grep -q "is not this checkout" "$LT_SB/sa.out"'
lt_check "SA: ... nothing written in either project, post-update hook never called" \
    eval '[ "$(snap "$A")" = "$sa0" ] && [ "$(snap "$Bp")" = "$sb0" ] && test "$(calls)" = 0'
( cd "$A" && CONST_DIR="$A/$REL" bash "$REL/scripts/setup.sh" ) >"$LT_SB/sac.out" 2>&1; rc=$?
lt_check "SA-control: CONST_DIR naming THIS checkout -> accepted, hooks installed in A only (rc=$rc)" \
    eval '[ "$rc" = 0 ] && test -x "$A/.git/hooks/post-merge" && test ! -e "$Bp/.git/hooks/post-merge"'
( cd "$Bp" && bash "$A/$REL/scripts/setup.sh" ) >"$LT_SB/sacwd.out" 2>&1; rc=$?
lt_check "SA-cwd: A's setup.sh run from INSIDE project B (no env) -> writes A, never B (rc=$rc)" \
    eval '[ "$rc" = 0 ] && test ! -e "$Bp/.git/hooks/post-merge" && grep -qF "Project root: $A" "$LT_SB/sacwd.out"'

# ============================================================================
# SV: setup.sh, legacy VENDORED plain copy (committed files, not a gitlink)
# ============================================================================
V="$LT_SB/projV"; mkdir -p "$V"; lt_git init -q "$V"; printf 'v\n' > "$V/README.md"
cp -a "$LT_SB/src_r7" "$V/constitution"; safe_rm_rf "${V:?}/constitution/.git"
lt_git -C "$V" add -A >/dev/null; lt_git -C "$V" commit -q -m "vendored constitution"
O="$LT_SB/other"; lt_git init -q "$O"; so0="$(snap "$O")"
: > "$LAYOUT_RECORD"
( cd "$V" && PROJECT_ROOT="$O" bash constitution/scripts/setup.sh ) >"$LT_SB/sv.out" 2>&1; rc=$?
lt_check "SV: vendored copy + ambient PROJECT_ROOT of another repo -> that repo byte-for-byte unchanged (rc=$rc)" \
    eval '[ "$(snap "$O")" = "$so0" ]'
lt_check "SV: ... the owning work tree got the hooks, the hook ran for it, the ambient value was reported" \
    eval 'test -x "$V/.git/hooks/post-merge" && grep -qF "CALLED PROJECT_ROOT=$V " "$LAYOUT_RECORD" && grep -q "ignoring the ambient PROJECT_ROOT=$O" "$LT_SB/sv.out"'
( cd "$V" && bash constitution/scripts/setup.sh --project-root "$O" ) >"$LT_SB/svx.out" 2>&1; rc=$?
lt_check "SV-control: EXPLICIT --project-root of the other repo -> honoured (hooks there, rc=$rc)" \
    eval 'test -x "$O/.git/hooks/post-merge" && grep -qF "Project root: $O" "$LT_SB/svx.out"'
sv0="$(snap "$V")"
( cd "$V" && CONST_DIR="$A/$REL" bash constitution/scripts/setup.sh ) >"$LT_SB/svc.out" 2>&1; rc=$?
lt_check "SV: vendored copy + ambient CONST_DIR of another checkout -> refused (rc=$rc), nothing written" \
    eval '[ "$rc" = 2 ] && [ "$(snap "$V")" = "$sv0" ]'

# ============================================================================
# G4 (M-4): gitlink at a custom .gitmodules path beats a vendored ./constitution
# ============================================================================
G="$LT_SB/projG"; lt_make_project "$G" "$URL" vendor/helix || lt_bad "fixture G"
cp -a "$LT_SB/src_r7" "$G/constitution"; safe_rm_rf "${G:?}/constitution/.git"
lt_git -C "$G" add constitution >/dev/null; lt_git -C "$G" commit -q -m "plain copy"
G4L="$( . "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh"; cl_find_in_project_no_override "$G" )"
lt_check "G4-lib: custom-path GITLINK (vendor/helix) wins over a plain ./constitution copy ($G4L)" \
    test "$G4L" = "$G/vendor/helix"
( cd "$G" && bash vendor/helix/scripts/setup.sh ) >"$LT_SB/g4s.out" 2>&1
lt_git -C "$G" checkout -q -b side
lt_bump_const_upstream r7
lt_git -C "$G/vendor/helix" fetch -q origin; lt_git -C "$G/vendor/helix" checkout -q origin/main
lt_git -C "$G" commit -q -am "bump vendor/helix"; lt_git -C "$G" checkout -q main
lt_git -C "$G" -c core.hooksPath=/dev/null submodule update -q 2>/dev/null
: > "$LAYOUT_RECORD"
( cd "$G" && lt_git merge -q --no-edit side ) >"$LT_SB/g4.out" 2>&1
lt_check "G4-post-merge: the gitlink bump at vendor/helix is resolved (not the plain copy) and reported" \
    eval 'grep -q "Constitution submodule updated: .* (vendor/helix)" "$LT_SB/g4.out" && ! grep -q "no initialized checkout" "$LT_SB/g4.out"'
G4P="$LT_SB/plain_custom"; mkdir -p "$G4P"; cp -a "$G/constitution" "$G4P/constitution"
G4Q="$( . "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh"; cl_find_in_project_no_override "$G4P" )"
lt_check "G4-control: a tree with only the plain copy still resolves it ($G4Q)" test "$G4Q" = "$G4P/constitution"

# G5: a plain ./constitution copy never stands in for a DE-INITIALISED gitlink:
# the moved gitlink must still produce the "no initialized checkout" warning
# (kills N6: post-merge pass 2 treating a plain holder as the checkout).
G5="$LT_SB/projG5"; lt_make_project "$G5" "$URL" "$REL" || lt_bad "fixture G5"
( cd "$G5" && bash "$REL/scripts/setup.sh" ) >"$LT_SB/g5s.out" 2>&1
cp -a "$LT_SB/src_r7" "$G5/constitution"; safe_rm_rf "${G5:?}/constitution/.git"
lt_git -C "$G5" add constitution >/dev/null; lt_git -C "$G5" commit -q -m "plain copy"
lt_git -C "$G5" checkout -q -b side
lt_bump_const_upstream r7
lt_git -C "$G5/$REL" fetch -q origin; lt_git -C "$G5/$REL" -c core.hooksPath=/dev/null checkout -q origin/main
lt_git -C "$G5" commit -q -am "bump gitlink"; lt_git -C "$G5" checkout -q main
lt_git -C "$G5" -c core.hooksPath=/dev/null submodule update -q 2>/dev/null
lt_git -C "$G5" submodule deinit -q -f "$REL" >/dev/null 2>&1
: > "$LAYOUT_RECORD"
( cd "$G5" && lt_git merge -q --no-edit side ) >"$LT_SB/g5.out" 2>&1
lt_check "G5: de-initialised gitlink moved + a plain ./constitution copy -> 'no initialized checkout' warning, the copy is NOT used" \
    eval 'grep -q "has no initialized checkout" "$LT_SB/g5.out" && test "$(calls)" = 0'
lt_check "G5 control: the post-merge hook really ran (it is installed and executable)" test -x "$G5/.git/hooks/post-merge"

# ============================================================================
# PA: the REAL post_update_hook.sh — every step, ambient roots
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
mkreal() { # NAME -> P (project with the real constitution at RV2)
    P="$LT_SB/real_$1"; mkdir -p "$P"; lt_git init -q "$P"; printf 'x\n' > "$P/README.md"
    lt_git -C "$P" add .; lt_git -C "$P" commit -q -m i
    lt_git -C "$P" submodule add -q "file://$LT_SB/realc.git" "$REL" >/dev/null 2>&1
    lt_git -C "$P" commit -q -m add
    git -C "$P/$REL" checkout -q "$RV2"
}
# runpu CWD [ARGS --] [env...] : the real hook with the v1..v2 range
runpu() {
    local cwd="$1"; shift
    ( cd "$cwd" && env HOME="$LT_SB/home" CONSTITUTION_UPDATE_OLD_REF="$RV1" CONSTITUTION_UPDATE_NEW_REF="$RV2" \
        "$@" timeout 600 bash "$PUH" $PU_ARGS ) >"$LT_SB/pu.out" 2>&1
}
wrote_owner() { test -x "$1/.git/hooks/post-merge" && test -d "$1/.claude"; }
PU_ARGS=""

mkreal amb; PUH="$P/$REL/scripts/post_update_hook.sh"
OT="$LT_SB/other_real"; lt_git init -q "$OT"; printf 'o\n' > "$OT/f"; ot0="$(snap "$OT")"
runpu "$P" PROJECT_ROOT="$OT"; rc=$?
lt_check "PA-1: ambient PROJECT_ROOT of another repo -> that repo byte-for-byte unchanged by EVERY step (rc=$rc)" \
    eval '[ "$(snap "$OT")" = "$ot0" ]'
lt_check "PA-1: ... the owner got the writes (git hook + .claude) and the WARNING names the ignored value" \
    eval 'wrote_owner "$P" && grep -q "ignoring the ambient PROJECT_ROOT=$OT" "$LT_SB/pu.out"'
lt_check "PA-1: ... the steps that write into a project really ran (positive control: STEP 2, 3, 4, 4b, 4c, 4d headers)" \
    eval 'for h in "STEP 2:" "STEP 3:" "STEP 4:" "STEP 4b:" "STEP 4c:" "STEP 4d:"; do grep -qF "$h" "$LT_SB/pu.out" || exit 1; done'

mkreal cwd; PUH="$P/$REL/scripts/post_update_hook.sh"
runpu "$OT"; rc=$?
lt_check "PA-2: run from INSIDE another repo (ambient cwd, no PROJECT_ROOT) -> that repo unchanged, the owner got the writes (rc=$rc)" \
    eval '[ "$(snap "$OT")" = "$ot0" ] && wrote_owner "$P"'

mkreal cd; PUH="$P/$REL/scripts/post_update_hook.sh"; mkreal cd2; P2="$P"; P="$LT_SB/real_cd"
sp0="$(snap "$P")"; sp20="$(snap "$P2")"
runpu "$P" CONST_DIR="$P2/$REL"; rc=$?
lt_check "PA-3: ambient CONST_DIR of ANOTHER checkout -> refused (rc=$rc), says why, nothing written in either project" \
    eval '[ "$rc" = 1 ] && grep -q "is not this checkout" "$LT_SB/pu.out" && [ "$(snap "$P")" = "$sp0" ] && [ "$(snap "$P2")" = "$sp20" ]'
runpu "$P" CONST_DIR="$P/$REL" PROJECT_ROOT="$P"; rc=$?
lt_check "PA-3 control: CONST_DIR + PROJECT_ROOT naming this checkout and its owner -> runs, owner written (rc=$rc)" \
    eval 'wrote_owner "$P"'

mkreal exp; PUH="$P/$REL/scripts/post_update_hook.sh"
OX="$LT_SB/other_explicit"; lt_git init -q "$OX"
PU_ARGS="--project-root $OX"; runpu "$P"; rc=$?; PU_ARGS=""
lt_check "PA-4: EXPLICIT --project-root of another repo -> honoured (hook installed there, rc=$rc)" \
    eval 'test -x "$OX/.git/hooks/post-merge" && ! grep -q "ignoring the ambient" "$LT_SB/pu.out"'

# PA-5: a VENDORED real copy (plain committed files inside a work tree)
VR="$LT_SB/real_vendored"; mkdir -p "$VR"; lt_git init -q "$VR"; printf 'v\n' > "$VR/README.md"
cp -a "$RC" "$VR/constitution"; safe_rm_rf "${VR:?}/constitution/.git"
lt_git -C "$VR" add -A >/dev/null; lt_git -C "$VR" commit -q -m vendored
PUH="$VR/constitution/scripts/post_update_hook.sh"
# (A vendored copy has no history of its own: STEP 1 diffs the OWNING work
# tree, whose paths carry the "constitution/" prefix, so the writing steps do
# not trigger there — a pre-existing vendored-layout limit, not this rule. What
# is asserted is the target choice: the other repo untouched, the owner named.)
runpu "$VR" PROJECT_ROOT="$OT"; rc=$?
lt_check "PA-5: vendored real copy + ambient PROJECT_ROOT of another repo -> that repo unchanged, the owning work tree chosen (rc=$rc)" \
    eval '[ "$(snap "$OT")" = "$ot0" ] && grep -qF "ignoring the ambient PROJECT_ROOT=$OT: this constitution checkout belongs to $VR " "$LT_SB/pu.out"'

# ============================================================================
# PL (W2 contract): the updater holds <git-dir>/helix-constitution-install.lock
# while it runs this hook and passes HELIX_CONSTITUTION_LOCK_DELEGATED. The
# hook takes NO lock of its own and never reads that file, so it must run
# normally under the held lock whatever that variable says (valid, foreign
# live, dead pid), never refuse because of it, and never touch the lock.
# ============================================================================
mkreal pl; PUH="$P/$REL/scripts/post_update_hook.sh"
ILK="$(git -C "$P" rev-parse --absolute-git-dir)/helix-constitution-install.lock"
sleep 600 & HOLDER=$!; LT_BG_PIDS="${LT_BG_PIDS:-} $HOLDER"          # stands for the updater (a live process of ours); killed by the EXIT trap too
sleep 600 & FOREIGN=$!; LT_BG_PIDS="${LT_BG_PIDS:-} $FOREIGN"        # a live process that does NOT hold the lock
( exit 0 ) & DEAD=$!; wait "$DEAD" 2>/dev/null
printf '%s\n' "$HOLDER" > "$ILK"; ilk0="$(sha256sum < "$ILK")"
for case_ in "valid:$HOLDER" "foreign-live:$FOREIGN" "dead:$DEAD" "garbage:1;rm -rf x" "unset:"; do
    name="${case_%%:*}"; val="${case_#*:}"
    safe_rm_rf "${P:?}/.claude"; rm -f -- "$P/.git/hooks/post-merge"
    if [ "$name" = unset ]; then runpu "$P" PROJECT_ROOT="$P"; else runpu "$P" PROJECT_ROOT="$P" HELIX_CONSTITUTION_LOCK_DELEGATED="$val"; fi
    lt_check "PL ($name delegation value) under a HELD install lock: the hook ran its writing steps (owner written, STEP 4 reached)" \
        eval 'wrote_owner "$P" && grep -qF "STEP 4:" "$LT_SB/pu.out"'
    lt_check "PL ($name): no lock-based refusal, and the install lock is byte-for-byte untouched and still present" \
        eval '! grep -qiE "helix-constitution-install\.lock|lock is (held|busy)" "$LT_SB/pu.out" && [ "$(sha256sum < "$ILK")" = "$ilk0" ]'
done
kill "$HOLDER" "$FOREIGN" 2>/dev/null; wait "$HOLDER" "$FOREIGN" 2>/dev/null

# ============================================================================
# PO: the two owner implementations agree
# ============================================================================
NG="$LT_SB/nogit/constitution"; mkdir -p "$NG"
SAL="$LT_SB/standalone"; lt_git clone -q "$LT_SB/realc.git" "$SAL"
PUF="$LT_SB/pu_owner.sh"
sed -n '/^pu_phys() {/p;/^pu_owner_of() {/,/^}/p' "$LAYOUT_SRC_ROOT/scripts/post_update_hook.sh" > "$PUF"
lt_check "PO fixture: pu_owner_of extracted from post_update_hook.sh" eval 'grep -q "^pu_owner_of()" "$PUF"'
for d in "$LT_SB/real_amb/$REL" "$VR/constitution" "$SAL" "$NG" "$A/$REL"; do
    lo="$( . "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh"; cl_owner_project_of "$d" )"; lr=$?
    po="$( . "$PUF"; pu_owner_of "$d" )"; pr=$?
    lt_check "PO: owner of ${d#"$LT_SB"/}: lib='$lo'($lr) == post_update='$po'($pr)" \
        eval '[ "$lo" = "$po" ] && [ "$lr" = "$pr" ]'
done
lt_check "PO-needle: a submodule's owner is its project ($LT_SB/real_amb)" \
    eval '[ "$( . "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh"; cl_owner_project_of "$LT_SB/real_amb/$REL" )" = "$LT_SB/real_amb" ]'
lt_check "PO-needle: a standalone clone has NO owner" \
    eval '! ( . "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh"; cl_owner_project_of "$SAL" ) >/dev/null'

lt_check "setup.sh parses" bash -n "$LAYOUT_SRC_ROOT/scripts/setup.sh"
lt_check "post_update_hook.sh parses" bash -n "$LAYOUT_SRC_ROOT/scripts/post_update_hook.sh"
lt_summary
