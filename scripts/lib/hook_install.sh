# shellcheck shell=bash
# scripts/lib/hook_install.sh — the ONE implementation of "install a git hook
# into a consumer repository safely" (§11.4.164 hook wiring). Shared by
# scripts/setup.sh (steps 2, 3, 3b) and scripts/post_update_hook.sh (STEP 4),
# so both apply the same scope policy and the same backup rules.
#
# Usage (bash; source it; the caller defines info / error printers):
#   . "<constitution>/scripts/lib/hook_install.sh"
#   chi_phys PATH                 physical path: every symlink resolved; for a
#                                 path that does not exist yet, the physical
#                                 parent + the remaining name. 1 = unresolvable.
#   chi_under PATH BASE           0 iff PATH is BASE or below it (string test)
#   chi_hooks_dir_check REPO HOOKS_DIR [MODE]
#       0 = allowed; 1 = refused, CHI_WHY holds one sentence saying why.
#       Refused when core.hooksPath is set at a scope other than local/worktree
#       (global, system, command line: a machine-wide hooks dir), or when the
#       PHYSICAL hooks dir (symlinks resolved, so a symlinked .git/hooks counts)
#       lies outside the repository:
#         MODE=repo   (default) REPO's git dir, common dir or work tree;
#         MODE=gitdir           REPO's own git dir or common dir only (used for
#                               the constitution SUBMODULE's consumer hook).
#   chi_tracked_hooks_dir REPO HOOKS_DIR
#       0 iff the PHYSICAL hooks dir (symlinks resolved: a symlinked .git/hooks
#       and core.hooksPath alike) lies in REPO's work tree and holds files
#       TRACKED by REPO; CHI_TRACKED_PHYS then holds that physical dir. The
#       callers WARN (installing rewrites committed project hooks; the old
#       ones are backed up first), they do not refuse: a committed hooks dir
#       (.githooks) is a deliberate project choice.
#   chi_backup_hook DST NAME LABEL BACKUP_ROOT STAMP
#       Back DST up to BACKUP_ROOT/STAMP/LABEL/NAME without ever overwriting an
#       earlier backup (NAME.1 .. NAME.999 when taken by a different hook; the
#       same hook already there is reused). A symlink is backed up AS A LINK
#       (never dereferenced) plus NAME.link with TARGET=, ABSOLUTE=, RESTORE=;
#       a regular file is copied with its mode; any other type is refused
#       without being opened. 0 = backed up (or already), 1 = not (reason printed).
#   chi_install_hook SRC NAME LABEL HOOKS_DIR BACKUP_ROOT STAMP
#       Identical regular file already installed -> left alone ("NAME unchanged").
#       Otherwise the existing hook (if any) is backed up first, then SRC is
#       installed atomically (temp file in HOOKS_DIR, chmod +x, rename).
#       0 = installed / unchanged; 1 = not installed (reason printed).
# BACKUP_ROOT must be <git common dir>/constitution-hook-backup (never inside a
# work tree or a shared hooks dir). STAMP: [A-Za-z0-9._-]+ (the caller checks).
# Side-effects: only the backup and the install described above.
# Dependencies: bash, git, cp, cmp, chmod, mv, mktemp, readlink, dirname, basename, head.
# Cross-references: §11.4.164; scripts/setup.sh; scripts/post_update_hook.sh;
#   tests/layout/test_setup_layout.sh, tests/layout/test_round4_hardening.sh,
#   tests/layout/test_round6_hardening.sh.
# Last verified: 2026-10-29

# Ambient GIT_DIR & co. would redirect every `git -C` below to another
# repository (round 8): all git calls here go through chi__git, which is
# cl__git of the ONE layout resolver (scripts/lib/constitution_layout.sh),
# sourced here when the caller has not done so.
if ! command -v cl__git >/dev/null 2>&1 && [ -f "$(dirname -- "${BASH_SOURCE[0]}")/constitution_layout.sh" ]; then
    # shellcheck source=constitution_layout.sh
    . "$(dirname -- "${BASH_SOURCE[0]}")/constitution_layout.sh"
fi
if command -v cl__git >/dev/null 2>&1; then
    chi__git() { cl__git "$@"; }
else
    # A lone copy of this file (no resolver beside it): same scrub inline; keep
    # the list equal to CL_GIT_SCRUB_VARS (tests/layout/test_round8_git_env.sh).
    chi__git() {
        ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
                GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_SHALLOW_FILE \
                GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH \
                GIT_INTERNAL_SUPER_PREFIX 2>/dev/null; exec git "$@" )
    }
fi

# chi_phys PATH
chi_phys() {
    local p="$1" n=0 d b t
    [ -n "$p" ] || return 1
    while [ "$n" -lt 40 ]; do
        n=$((n + 1))
        if [ -d "$p" ]; then
            ( CDPATH='' cd -P -- "$p" 2>/dev/null && pwd -P ) || return 1
            return 0
        fi
        d="$(dirname -- "$p")"; b="$(basename -- "$p")"
        d="$(chi_phys "$d")" || return 1
        if [ -L "$d/$b" ]; then
            t="$(readlink -- "$d/$b")" || return 1
            case "$t" in /*) p="$t" ;; *) p="${d%/}/$t" ;; esac
            continue
        fi
        printf '%s\n' "${d%/}/$b"
        return 0
    done
    return 1
}

# chi_under PATH BASE
chi_under() { [ -n "$2" ] || return 1; case "$1/" in "${2%/}"/*) return 0 ;; esac; return 1; }

# chi_hooks_dir_check REPO HOOKS_DIR [MODE]
chi_hooks_dir_check() {
    local repo="$1" hd="$2" mode="${3:-repo}" line scope val gd cd top p where
    CHI_WHY=""
    line="$(chi__git -C "$repo" config --show-scope --get core.hooksPath 2>/dev/null || true)"
    if [ -n "$line" ]; then
        scope="${line%%$'\t'*}"; val="${line#*$'\t'}"
        case "$scope" in
            local|worktree) ;;
            *) CHI_WHY="core.hooksPath=$val is set at $scope scope (not this repository's local/worktree config)"
               return 1 ;;
        esac
    fi
    gd="$(chi__git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null)" || gd=""
    [ -n "$gd" ] || { CHI_WHY="cannot resolve the git dir of $repo"; return 1; }
    cd="$(chi__git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || cd="$gd"
    p="$(chi_phys "$hd")" || { CHI_WHY="cannot resolve the physical path of the hooks dir $hd"; return 1; }
    if chi_under "$p" "$(chi_phys "$gd")" || chi_under "$p" "$(chi_phys "$cd")"; then
        return 0
    fi
    where="git dir"
    if [ "$mode" = repo ]; then
        where="git dir and work tree"
        top="$(chi__git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || top=""
        if [ -n "$top" ] && chi_under "$p" "$(chi_phys "$top")"; then return 0; fi
    fi
    if [ "$p" != "$hd" ]; then
        CHI_WHY="the hooks dir $hd resolves (physically, symlinks followed) to $p, outside this repository's $where (a shared hooks dir)"
    else
        CHI_WHY="the hooks dir $hd is outside this repository's $where (a shared hooks dir)"
    fi
    return 1
}

# chi_tracked_hooks_dir REPO HOOKS_DIR
chi_tracked_hooks_dir() {
    local repo="$1" hd="$2" p top tp rel
    CHI_TRACKED_PHYS=""
    p="$(chi_phys "$hd")" || return 1
    top="$(chi__git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || return 1
    tp="$(chi_phys "$top")" || return 1
    chi_under "$p" "$tp" || return 1
    rel="${p#"$tp"}"; rel="${rel#/}"
    [ -n "$(chi__git -C "$tp" --literal-pathspecs ls-files -- "${rel:-.}" 2>/dev/null | head -n 1)" ] || return 1
    CHI_TRACKED_PHYS="$p"
    return 0
}

# chi_backup_hook DST NAME LABEL BACKUP_ROOT STAMP
chi_backup_hook() {
    local dst="$1" name="$2" label="$3" broot="$4" bstamp="$5" bdir bpath i=0 target=""
    if [ -L "$dst" ]; then
        target="$(readlink -- "$dst")" || { error "  $name: cannot read the symlink $dst"; return 1; }
    elif [ ! -f "$dst" ]; then
        error "  $name: $dst is not a regular file or symlink (FIFO/socket/dir/device?)"; return 1
    elif [ ! -r "$dst" ]; then
        error "  $name: $dst is not readable"; return 1
    fi
    bdir="$broot/$bstamp/$label"
    mkdir -p -- "$bdir" || return 1
    bpath="$bdir/$name"
    while [ -e "$bpath" ] || [ -L "$bpath" ]; do
        if [ -n "$target" ]; then
            if [ -L "$bpath" ] && [ "$(readlink -- "$bpath")" = "$target" ]; then
                info "  $name: existing hook (symlink -> $target) already backed up at $bpath"; return 0
            fi
        elif [ -f "$bpath" ] && [ ! -L "$bpath" ] && cmp -s "$dst" "$bpath"; then
            info "  $name: existing hook already backed up at $bpath"
            return 0
        fi
        i=$((i + 1))
        [ "$i" -le 999 ] || { error "  $name: more than 999 backups under $bdir"; return 1; }
        bpath="$bdir/$name.$i"
    done
    if [ -n "$target" ]; then
        ln -s -- "$target" "$bpath" && [ "$(readlink -- "$bpath")" = "$target" ] || return 1
        # A RELATIVE target would dangle from the backup dir: also record it as
        # text with its absolute form (resolved against the hooks dir).
        local abs="$target"
        case "$target" in /*) ;; *) abs="$(chi_phys "$(dirname -- "$dst")")/$target" ;; esac
        printf 'TARGET=%s\nABSOLUTE=%s\nRESTORE=cp -P -- %s %s\n' \
            "$target" "$abs" "$bpath" "$dst" > "$bpath.link" || {
            error "  $name: could not write $bpath.link"; return 1; }
        info "  $name: existing hook (symlink -> $target) backed up as a link at $bpath (+ $bpath.link)"
        return 0
    fi
    cp -p "$dst" "$bpath" && cmp -s "$dst" "$bpath" || return 1
    info "  $name: existing hook backed up to $bpath"
}

# chi_install_hook SRC NAME LABEL HOOKS_DIR BACKUP_ROOT STAMP
chi_install_hook() {
    local src="$1" name="$2" label="$3" hdir="$4" broot="$5" bstamp="$6" dst tmp=""
    dst="$hdir/$name"
    if [ -e "$dst" ] && [ ! -L "$dst" ] && [ ! -f "$dst" ]; then
        error "  $name: $dst is not a regular file (FIFO/socket/dir/device?) — refused, NOT replaced"
        return 1
    fi
    if [ ! -L "$dst" ] && [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        [ -x "$dst" ] || chmod +x "$dst" || { error "  $name: cannot chmod +x $dst"; return 1; }
        info "  $name unchanged"
        return 0
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        if ! chi_backup_hook "$dst" "$name" "$label" "$broot" "$bstamp"; then
            error "  $name: could not back up the existing hook — NOT replaced ($dst)"
            return 1
        fi
    fi
    tmp="$(mktemp "$hdir/.${name}.XXXXXX" 2>/dev/null)" || {
        error "  $name: cannot write into $hdir — NOT installed"; return 1; }
    if cp "$src" "$tmp" && chmod +x "$tmp" && mv -f "$tmp" "$dst"; then
        info "  $name installed"
        return 0
    fi
    rm -f "$tmp"
    error "  $name: install failed ($dst)"
    return 1
}
