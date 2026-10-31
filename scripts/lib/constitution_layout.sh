# shellcheck shell=sh
# scripts/lib/constitution_layout.sh — the ONE resolver for "where is the
# constitution, and where is the consuming project" (both layouts).
#
# Purpose:
#   Consumers vendor the constitution as a git submodule. Two layouts are
#   supported, and every hub script that needs either path MUST resolve it
#   through this file instead of hard-coding `<project>/constitution`:
#     submodules/constitution   — the standard for new installs (§11.4.28
#                                 dependency layout: owned submodules under
#                                 <root>/submodules/)
#     constitution              — the legacy layout, still fully supported
#   A third case is handled generically: a constitution submodule at ANY path
#   declared in the project's .gitmodules (found by content, not by name).
#
# Usage (source it; POSIX sh, bash, dash all work):
#   . "<constitution>/scripts/lib/constitution_layout.sh"
#   root="$(cl_project_root_of "$const_dir")"     # consumer root of a checkout
#   dir="$(cl_find_in_project "$project_root")"   # constitution inside a project
#   dir="$(cl_find_in_project_no_override "$wt")" # same, $CONSTITUTION_DIR ignored
#   cl_is_constitution_dir "$dir" && ...
#   rel="$(cl_rel_path "$project_root" "$dir")"   # e.g. submodules/constitution
#   hooks="$(cl_git_hooks_dir "$project_root")"   # honours worktrees/core.hooksPath
#   cl_is_git_hook_name post-merge && ...
#   cl_scrub_git_env                              # drop ambient repo-selecting GIT_* vars
#
# Ambient git environment (round 8): GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE /
#   GIT_COMMON_DIR / ... choose WHICH repository `git -C <path>` really reads
#   and writes (GIT_DIR beats -C). Every entry point that calls git calls
#   `cl_scrub_git_env` first (unset-and-proceed; the repository is then
#   discovered from the owner path), and every git call INSIDE this file goes
#   through cl__git, which scrubs in a subshell, so the resolver answers
#   correctly even for a caller that forgot. The scrubbed set
#   (CL_GIT_SCRUB_VARS) is the REPOSITORY-LOCATING class only: where the
#   repository, work tree, index, object store, namespace and discovery ceiling
#   are. NOT scrubbed (deliberately): configuration (GIT_CONFIG_*), author and
#   committer identity, transport/auth (GIT_SSH*, GIT_ASKPASS, SSH_AUTH_SOCK),
#   GIT_TEMPLATE_DIR (git init only) and GIT_DISCOVERY_ACROSS_FILESYSTEM
#   (unset == the safe default, no repository is chosen by it).
#   scripts/post_update_hook.sh, scripts/hooks/post-merge and
#   scripts/hooks/constitution-submodule-post-checkout must run as lone copies
#   and carry the same list inline; tests/layout/test_round8_git_env.sh checks
#   that the four lists are identical and that every git-calling script
#   carries a scrub.
#
# Inputs:
#   CONSTITUTION_DIR — optional explicit override (absolute path of a
#                      constitution checkout); honoured by cl_find_in_project.
#
# Outputs: each function prints one path on stdout (no trailing text) and
#   returns 0, or prints nothing and returns 1 when it cannot resolve. No
#   function ever guesses silently: a 1 means "not found", never "assume".
#
# Side-effects: none (read-only; defines shell functions and two variables).
#
# Dependencies: POSIX sh, git (optional: only for the superproject/.gitmodules
#   and gitlink probes and cl_git_hooks_dir), awk, dirname, basename, pwd.
#
# Cross-references: §11.4.28 / §11.4.28(C) (resolver instead of nested
#   copies), §11.4.35 (canonical root), §11.4.201 (no silent false-null),
#   find_constitution.sh (the walk-up locator for code running INSIDE a
#   nested submodule; it carries its own copy of the two-layout list —
#   tracked, not unified here because that file is outside this change).
#   Tests: tests/layout/test_constitution_layout_lib.sh.

# Priority order: the standard layout first, then the legacy one.
CONSTITUTION_LAYOUT_DEFAULT_REL="submodules/constitution"
CONSTITUTION_LAYOUT_LEGACY_REL="constitution"
CONSTITUTION_LAYOUT_RELS="submodules/constitution constitution"

# The repository-locating GIT_* variables (see the header). ONE list; the lone
# copies (post_update_hook.sh, the two hooks) repeat it inline.
CL_GIT_SCRUB_VARS="GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX"

# cl_scrub_git_env [quiet] — unset every ambient repository-locating GIT_*
# variable in the CURRENT shell (unset-and-proceed: the repository is found
# from the path a script was given, never from a variable left over for another
# repository). Prints ONE notice on stderr naming the dropped variables (never
# their values) unless "quiet" or CL_GIT_SCRUB_QUIET=1 (git itself exports some
# of them to its hooks, where the notice would be noise). Always returns 0.
cl_scrub_git_env() {
    _cl_dropped=""
    # The word split below must not depend on the CALLER's IFS (the resolver
    # runs with IFS=newline): save it, use the default, restore it.
    _cl_sIFS="$IFS"; IFS=' 	
'
    for _cl_v in $CL_GIT_SCRUB_VARS; do
        if eval "[ -n \"\${$_cl_v+x}\" ]"; then
            _cl_dropped="${_cl_dropped:+$_cl_dropped }$_cl_v"
            unset "$_cl_v"
        fi
    done
    IFS="$_cl_sIFS"
    if [ -n "$_cl_dropped" ] && [ "${1:-}" != quiet ] && [ "${CL_GIT_SCRUB_QUIET:-0}" != 1 ]; then
        printf '[constitution] NOTICE: ignoring the ambient git environment (%s): the repository is discovered from the project path, never from these variables.\n' "$_cl_dropped" >&2
    fi
    unset _cl_dropped _cl_v _cl_sIFS
    return 0
}

# cl__git ARGS... — git with the repository-locating variables removed (a
# subshell, so the caller's environment is untouched and no notice is printed).
cl__git() { ( cl_scrub_git_env quiet; exec git "$@" ); }

# cl_is_constitution_dir DIR — 0 iff DIR holds Constitution.md and scripts/.
cl_is_constitution_dir() {
    [ -n "${1:-}" ] && [ -f "$1/Constitution.md" ] && [ -d "$1/scripts" ]
}

# cl__abs DIR — logical absolute path of an existing directory (symlinks kept,
# so a symlinked checkout keeps the path it was reached by).
cl__abs() {
    ( CDPATH='' cd -- "$1" 2>/dev/null && pwd )
}

# cl_project_root_of CONST_DIR — the consuming project's root.
#   1. git superproject of CONST_DIR, when CONST_DIR (physically) lives under it
#      (covers any submodule path, not only the two named layouts);
#   2. the logical path ends in /submodules/constitution  -> strip two levels;
#   3. the logical path ends in /constitution             -> strip one level;
#   4. otherwise the parent directory (the historical default).
cl_project_root_of() {
    _cl_c="$(cl__abs "${1:-}")" || return 1
    [ -n "$_cl_c" ] || return 1
    _cl_phys="$( ( CDPATH='' cd -- "$_cl_c" 2>/dev/null && pwd -P ) )" || _cl_phys=""
    _cl_super=""
    if command -v git >/dev/null 2>&1; then
        _cl_super="$(cl__git -C "$_cl_c" rev-parse --show-superproject-working-tree 2>/dev/null)" || _cl_super=""
    fi
    if [ -n "$_cl_super" ] && [ -n "$_cl_phys" ]; then
        case "$_cl_phys" in
            "$_cl_super"/*)
                # Prefer the logical form of the superproject when the logical
                # path ends in a known layout (keeps symlinked parents intact).
                case "$_cl_c" in
                    */submodules/constitution) _cl_l="${_cl_c%/submodules/constitution}" ;;
                    */constitution)            _cl_l="${_cl_c%/constitution}" ;;
                    *)                         _cl_l="" ;;
                esac
                if [ -n "$_cl_l" ] && [ "$( ( CDPATH='' cd -- "$_cl_l" 2>/dev/null && pwd -P ) )" = "$_cl_super" ]; then
                    printf '%s\n' "$_cl_l"
                else
                    printf '%s\n' "$_cl_super"
                fi
                return 0 ;;
        esac
    fi
    case "$_cl_c" in
        /submodules/constitution) printf '/\n'; return 0 ;;
        */submodules/constitution) printf '%s\n' "${_cl_c%/submodules/constitution}"; return 0 ;;
        /constitution) printf '/\n'; return 0 ;;
        */constitution) printf '%s\n' "${_cl_c%/constitution}"; return 0 ;;
    esac
    _cl_p="$(dirname -- "$_cl_c")" || return 1
    printf '%s\n' "$_cl_p"
}

# cl_owner_project_of CONST_DIR — the project that OWNS this constitution
# checkout, derived from git only (never from the environment):
#   * a submodule: its git superproject (logical form via cl_project_root_of);
#   * a vendored PLAIN copy inside a git work tree: that work tree's top level;
#   * a standalone clone (its own top level) or no git: returns 1 (no owner).
# Used to stop an AMBIENT $PROJECT_ROOT / cwd (exported or left over for
# another project) from redirecting writes into another repository.
# The same rules are inlined in scripts/post_update_hook.sh (pu_owner_of; it
# must also run as a lone copy); tests/layout/test_round7_ambient.sh checks the
# two agree.
cl_owner_project_of() {
    _cl_c="$(cl__abs "${1:-}")" || return 1
    [ -n "$_cl_c" ] || return 1
    command -v git >/dev/null 2>&1 || return 1
    _cl_s="$(cl__git -C "$_cl_c" rev-parse --show-superproject-working-tree 2>/dev/null)" || _cl_s=""
    if [ -n "$_cl_s" ]; then
        cl_project_root_of "$_cl_c"; return $?
    fi
    _cl_t="$(cl__git -C "$_cl_c" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [ -n "$_cl_t" ] || return 1
    _cl_cp="$( ( CDPATH='' cd -- "$_cl_c" 2>/dev/null && pwd -P ) )" || return 1
    [ "$_cl_t" = "$_cl_cp" ] && return 1       # a standalone checkout: no owner
    _cl_l="$(cl_project_root_of "$_cl_c")" || _cl_l=""
    if [ -n "$_cl_l" ] && [ "$( ( CDPATH='' cd -- "$_cl_l" 2>/dev/null && pwd -P ) )" = "$_cl_t" ]; then
        printf '%s\n' "$_cl_l"
    else
        printf '%s\n' "$_cl_t"
    fi
}

# cl_same_dir A B — 0 iff A and B are the same directory (physical paths).
cl_same_dir() {
    _cl_a="$( ( CDPATH='' cd -- "${1:-}" 2>/dev/null && pwd -P ) )" || return 1
    _cl_b="$( ( CDPATH='' cd -- "${2:-}" 2>/dev/null && pwd -P ) )" || return 1
    [ -n "$_cl_a" ] && [ "$_cl_a" = "$_cl_b" ]
}

# cl__gitmodules_paths ROOT — every submodule path declared in ROOT/.gitmodules,
# one per line (absolute, '..' and TAB/newline-holding paths are skipped).
cl__gitmodules_paths() {
    [ -f "$1/.gitmodules" ] && command -v git >/dev/null 2>&1 || return 0
    # NUL-safe: `-z` prints "key<LF>value<NUL>"; a submodule NAME may hold
    # spaces ("submodule.my const.path"), so splitting the plain output at
    # its first space would yield a wrong path. LF->TAB, NUL->LF gives one
    # "key<TAB>value" line per entry (a name holding a TAB, or a path
    # holding a newline, is not supported and is skipped, never guessed).
    _cl_gt="$(printf '\t')"
    cl__git config -z -f "$1/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null | tr '\n\000' '\t\n' | \
    while IFS= read -r _cl_gl; do
        case "$_cl_gl" in *"$_cl_gt"*) ;; *) continue ;; esac
        _cl_gp="${_cl_gl#*"$_cl_gt"}"
        case "$_cl_gp" in ''|*"$_cl_gt"*|/*|..|../*|*/..|*/../*) continue ;; esac
        printf '%s\n' "$_cl_gp"
    done
}

# cl_find_in_project PROJECT_ROOT — the constitution checkout of a project.
#   0. $CONSTITUTION_DIR when it is a constitution dir;
#   1. each layout in CONSTITUTION_LAYOUT_RELS (standard first): first those
#      that are a real gitlink (mode 160000) of the project, then any;
#   2. any .gitmodules-declared submodule path that is a constitution dir.
cl_find_in_project() {
    if [ -n "${CONSTITUTION_DIR:-}" ] && cl_is_constitution_dir "$CONSTITUTION_DIR"; then
        cl__abs "$CONSTITUTION_DIR"; return $?
    fi
    cl_find_in_project_no_override "${1:-}"
}

# cl_find_in_project_no_override PROJECT_ROOT — like cl_find_in_project but
# NEVER honours $CONSTITUTION_DIR: the checkout that really lives inside
# PROJECT_ROOT (steps 1 and 2 only). Use it wherever the answer must be the
# project's OWN checkout (its gitlink, a worktree's copy), so an ambient
# override exported for another project cannot redirect it.
cl_find_in_project_no_override() {
    _cl_r="$(cl__abs "${1:-}")" || return 1
    [ -n "$_cl_r" ] || return 1
    # A mid-migration tree can hold a vendored PLAIN copy at one path and the
    # real submodule (gitlink, mode 160000) at another (a layout or any
    # .gitmodules path): the gitlink wins over every plain copy.
    if command -v git >/dev/null 2>&1; then
        _cl_cands="$(for _cl_x in $CONSTITUTION_LAYOUT_RELS; do printf '%s\n' "$_cl_x"; done
                     cl__gitmodules_paths "$_cl_r")"
        _cl_oldifs="$IFS"
        case $- in *f*) _cl_nogl=1 ;; *) _cl_nogl=0 ;; esac
        set -f                          # a path such as 'v*' is a name, never a glob
        IFS='
'
        for _cl_rel in $_cl_cands; do
            cl_is_constitution_dir "$_cl_r/$_cl_rel" || continue
            if cl__git -C "$_cl_r" --literal-pathspecs ls-files -s -- "$_cl_rel" 2>/dev/null | \
                 awk -v p="$_cl_rel" '$1 == "160000" { sub(/^[^\t]*\t/, ""); if ($0 == p) f = 1 } END { exit !f }'; then
                IFS="$_cl_oldifs"; [ "$_cl_nogl" = 1 ] || set +f
                printf '%s\n' "$_cl_r/$_cl_rel"; return 0
            fi
        done
        IFS="$_cl_oldifs"; [ "$_cl_nogl" = 1 ] || set +f
    fi
    for _cl_rel in $CONSTITUTION_LAYOUT_RELS; do
        if cl_is_constitution_dir "$_cl_r/$_cl_rel"; then
            printf '%s\n' "$_cl_r/$_cl_rel"; return 0
        fi
    done
    _cl_cands="$(cl__gitmodules_paths "$_cl_r")"
    _cl_oldifs="$IFS"
    case $- in *f*) _cl_nogl=1 ;; *) _cl_nogl=0 ;; esac
    set -f
    IFS='
'
    for _cl_sp in $_cl_cands; do
        if cl_is_constitution_dir "$_cl_r/$_cl_sp"; then
            IFS="$_cl_oldifs"; [ "$_cl_nogl" = 1 ] || set +f
            printf '%s\n' "$_cl_r/$_cl_sp"; return 0
        fi
    done
    IFS="$_cl_oldifs"; [ "$_cl_nogl" = 1 ] || set +f
    return 1
}

# cl_rel_path PROJECT_ROOT DIR — DIR relative to PROJECT_ROOT when DIR is under
# it (e.g. "submodules/constitution"); otherwise DIR unchanged (absolute).
cl_rel_path() {
    case "${2:-}" in
        "${1:-}"/*) printf '%s\n' "${2#"$1"/}" ;;
        *)          printf '%s\n' "${2:-}" ;;
    esac
}

# cl_git_hooks_dir PROJECT_ROOT — the absolute hooks dir git really uses
# (worktrees and submodules have a .git FILE; core.hooksPath is honoured).
cl_git_hooks_dir() {
    command -v git >/dev/null 2>&1 || return 1
    _cl_h="$( ( CDPATH='' cd -- "${1:-}" 2>/dev/null && cl_scrub_git_env quiet && git rev-parse --path-format=absolute --git-path hooks 2>/dev/null ) )" || _cl_h=""
    if [ -z "$_cl_h" ]; then
        _cl_h="$( ( CDPATH='' cd -- "${1:-}" 2>/dev/null && cl_scrub_git_env quiet && git rev-parse --git-path hooks 2>/dev/null ) )" || _cl_h=""
        case "$_cl_h" in ''|/*) ;; *) _cl_h="$1/$_cl_h" ;; esac
    fi
    [ -n "$_cl_h" ] || return 1
    printf '%s\n' "$_cl_h"
}

# cl_is_git_hook_name NAME — 0 iff NAME is a git hook event (githooks(5)).
cl_is_git_hook_name() {
    case "${1:-}" in
        applypatch-msg|pre-applypatch|post-applypatch|pre-commit|pre-merge-commit|\
        prepare-commit-msg|commit-msg|post-commit|pre-rebase|post-checkout|post-merge|\
        pre-push|pre-receive|update|proc-receive|post-receive|post-update|\
        reference-transaction|push-to-checkout|pre-auto-gc|post-rewrite|\
        sendemail-validate|fsmonitor-watchman|post-index-change) return 0 ;;
    esac
    return 1
}
