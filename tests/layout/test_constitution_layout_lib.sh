#!/usr/bin/env bash
# tests/layout/test_constitution_layout_lib.sh — unit + security + determinism
# tests for scripts/lib/constitution_layout.sh (the single layout resolver).
#
# Usage: bash tests/layout/test_constitution_layout_lib.sh
# Exit: 0 all PASS, 1 any FAIL. Sandboxed (see lib_layout_harness.sh).
LT_SUITE="constitution_layout_lib"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

LIB="$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh"
if [ ! -f "$LIB" ]; then
    lt_bad "lib present at $LIB"
    lt_summary; exit 1
fi
# shellcheck source=/dev/null
. "$LIB"

mkconst() { mkdir -p "$1/scripts"; printf '# C\n' > "$1/Constitution.md"; }

# --- plain directories, both layouts --------------------------------------
P1="$LT_SB/p std"; mkconst "$P1/submodules/constitution"
P2="$LT_SB/p_legacy"; mkconst "$P2/constitution"
P3="$LT_SB/p both"; mkconst "$P3/submodules/constitution"; mkconst "$P3/constitution"
P4="$LT_SB/p_none"; mkdir -p "$P4/submodules"

lt_check "find: standard layout"      test "$(cl_find_in_project "$P1")" = "$P1/submodules/constitution"
lt_check "find: legacy layout"        test "$(cl_find_in_project "$P2")" = "$P2/constitution"
lt_check "find: both -> standard wins" test "$(cl_find_in_project "$P3")" = "$P3/submodules/constitution"
out="$(cl_find_in_project "$P4")"; rc=$?
lt_check "find: none -> rc 1 + empty output (never a guess)" test "$rc" -eq 1 -a -z "$out"
out="$(cl_find_in_project "$LT_SB/does/not/exist")"; rc=$?
lt_check "find: missing project dir -> rc 1" test "$rc" -eq 1 -a -z "$out"

lt_check "root_of: standard -> project (not <project>/submodules)" test "$(cl_project_root_of "$P1/submodules/constitution")" = "$P1"
lt_check "root_of: legacy -> project"   test "$(cl_project_root_of "$P2/constitution")" = "$P2"
out="$(cl_project_root_of "$LT_SB/nope")"; rc=$?
lt_check "root_of: missing dir -> rc 1" test "$rc" -eq 1 -a -z "$out"

# --- override ---------------------------------------------------------------
OV="$LT_SB/elsewhere/const"; mkconst "$OV"
lt_check "find: CONSTITUTION_DIR override honoured" test "$(CONSTITUTION_DIR="$OV" cl_find_in_project "$P4")" = "$OV"
lt_check "find: bogus CONSTITUTION_DIR ignored (falls back to layouts)" \
    test "$(CONSTITUTION_DIR="$LT_SB/bogus" cl_find_in_project "$P2")" = "$P2/constitution"

# --- security: hostile path characters -------------------------------------
HOST="$LT_SB/a b;\$(touch PWNED)\`x\`&|*?"
mkconst "$HOST/submodules/constitution"
lt_check "find: path with spaces + shell metachars" test "$(cl_find_in_project "$HOST")" = "$HOST/submodules/constitution"
lt_check "root_of: path with spaces + shell metachars" test "$(cl_project_root_of "$HOST/submodules/constitution")" = "$HOST"
lt_check "security: metachar path never executed (no PWNED file)" test ! -e "$LT_SB/PWNED" -a ! -e "PWNED"
NL="$LT_SB/new
line"
mkconst "$NL/constitution"
lt_check "find: path with an embedded newline" test "$(cl_find_in_project "$NL")" = "$NL/constitution"
lt_check "root_of: path with an embedded newline" test "$(cl_project_root_of "$NL/constitution")" = "$NL"

# --- symlinked checkout keeps the logical project ---------------------------
REAL="$LT_SB/store/real_const"; mkconst "$REAL"
PS="$LT_SB/p_symlink"; mkdir -p "$PS/submodules"; ln -s "$REAL" "$PS/submodules/constitution"
lt_check "find: symlinked submodules/constitution" test "$(cl_find_in_project "$PS")" = "$PS/submodules/constitution"
lt_check "root_of: symlinked checkout -> logical project root" test "$(cl_project_root_of "$PS/submodules/constitution")" = "$PS"

# --- real git: custom submodule path, superproject, traversal --------------
URL="$(lt_make_const_upstream libc)"
PG="$LT_SB/pg"
lt_make_project "$PG" "$URL" vendor/helix_const
lt_check "find: .gitmodules-declared custom path" test "$(cl_find_in_project "$PG")" = "$PG/vendor/helix_const"
lt_check "root_of: custom path via git superproject" test "$(cl_project_root_of "$PG/vendor/helix_const")" = "$PG"
PT="$LT_SB/pt"; mkdir -p "$PT"; mkconst "$LT_SB/evil_const"
printf '[submodule "x"]\n\tpath = ../evil_const\n\turl = file:///nonexistent\n' > "$PT/.gitmodules"
out="$(cl_find_in_project "$PT")"; rc=$?
lt_check "security: .gitmodules traversal path (../) is ignored" test "$rc" -eq 1 -a -z "$out"
printf '[submodule "x"]\n\tpath = %s\n\turl = file:///nonexistent\n' "$LT_SB/evil_const" > "$PT/.gitmodules"
out="$(cl_find_in_project "$PT")"; rc=$?
lt_check "security: .gitmodules absolute path is ignored" test "$rc" -eq 1 -a -z "$out"

PS2="$LT_SB/pstd_git"
lt_make_project "$PS2" "$URL" submodules/constitution
lt_check "root_of: real submodule at submodules/constitution" test "$(cl_project_root_of "$PS2/submodules/constitution")" = "$PS2"
lt_check "hooks dir: superproject -> <project>/.git/hooks" test "$(cl_git_hooks_dir "$PS2")" = "$PS2/.git/hooks"
lt_check "hooks dir: never the submodule's hooks" test "$(cl_git_hooks_dir "$PS2")" != "$(cl_git_hooks_dir "$PS2/submodules/constitution")"
WT="$LT_SB/wt"; lt_git -C "$PS2" worktree add -q "$WT" -b wtb >/dev/null 2>&1
lt_check "hooks dir: linked worktree (.git file) -> shared hooks" test "$(cl_git_hooks_dir "$WT")" = "$PS2/.git/hooks"
lt_git -C "$PS2" config core.hooksPath "$LT_SB/custom_hooks"
lt_check "hooks dir: core.hooksPath honoured" test "$(cl_git_hooks_dir "$PS2")" = "$LT_SB/custom_hooks"
lt_git -C "$PS2" config --unset core.hooksPath
out="$(cl_git_hooks_dir "$P4")"; rc=$?
lt_check "hooks dir: not a git repo -> rc 1" test "$rc" -eq 1 -a -z "$out"

lt_check "hook name: post-merge is a git hook" cl_is_git_hook_name post-merge
lt_check "hook name: guard-x.sh is NOT a git hook" eval '! cl_is_git_hook_name guard-evidence-store-write.sh'
lt_check "hook name: __pycache__ is NOT a git hook" eval '! cl_is_git_hook_name __pycache__'
lt_check "rel_path: under project" test "$(cl_rel_path "$P1" "$P1/submodules/constitution")" = "submodules/constitution"
lt_check "rel_path: outside project -> absolute" test "$(cl_rel_path "$P1" "$OV")" = "$OV"

# --- no-override resolver (I2): an ambient CONSTITUTION_DIR never wins ------
out="$(CONSTITUTION_DIR="$OV" cl_find_in_project_no_override "$P2" 2>/dev/null)"; rc=$?
lt_check "find_no_override: ambient CONSTITUTION_DIR ignored -> the project's own checkout (rc=$rc)" \
    test "$rc" -eq 0 -a "$out" = "$P2/constitution"
out="$(CONSTITUTION_DIR="$OV" cl_find_in_project_no_override "$P4" 2>/dev/null)"; rc=$?
lt_check "find_no_override: project without a constitution -> rc 1 even with an override set" \
    test "$rc" -eq 1 -a -z "$out"

# --- M2: .gitmodules submodule NAME with spaces (NUL-safe parsing) ----------
PN="$LT_SB/p_named"; mkconst "$PN/vendor/my const"
printf '[submodule "my helix const"]\n\tpath = vendor/my const\n\turl = file:///nonexistent\n' > "$PN/.gitmodules"
lt_check "find: .gitmodules submodule name AND path with spaces" \
    test "$(cl_find_in_project "$PN" 2>/dev/null)" = "$PN/vendor/my const"

# --- POSIX sh compatibility (dash when present) -----------------------------
if command -v dash >/dev/null 2>&1; then
    d="$(dash -c '. "$1"; cl_find_in_project "$2"; cl_project_root_of "$3"' sh "$LIB" "$P1" "$P2/constitution")"
    lt_check "dash: lib works under POSIX sh" test "$d" = "$P1/submodules/constitution
$P2"
else
    lt_ok "dash: not installed — POSIX check SKIPPED (hardware_not_present-class gap, recorded)"
fi
lt_check "sh -n parses the lib" sh -n "$LIB"

# --- determinism: 3 identical runs ------------------------------------------
r1="$(cl_find_in_project "$P3"; cl_project_root_of "$PS2/submodules/constitution"; cl_git_hooks_dir "$PS2")"
r2="$(cl_find_in_project "$P3"; cl_project_root_of "$PS2/submodules/constitution"; cl_git_hooks_dir "$PS2")"
r3="$(cl_find_in_project "$P3"; cl_project_root_of "$PS2/submodules/constitution"; cl_git_hooks_dir "$PS2")"
lt_check "determinism: 3 identical runs" test "$r1" = "$r2" -a "$r2" = "$r3"

lt_summary
