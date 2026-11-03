# shellcheck shell=bash
# scripts/lib/third_party_prune.sh — ONE resolver for the third-party /
# trees that scanner gates prune by default.
#
# Why: scanner gates (CM-DANGEROUS-COMBINATION-FAIL-CLOSED §11.4.252,
# CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT §11.4.245) defaulted to descending
# into every submodule. Measured on the canon (2026-10-31): 6345 of 6759 oracle
# hits and a >15 minute dangerous-combination run came from trees the scanning
# repository does not own; each separate repository adopts the gate itself.
#
# cm_third_party_prune_paths <root>
#   Prints, one per line, what to prune: (1) the directory names `third_party` and `site-packages`
#   (any depth), and (2) every path selected by the rule below, relative to <root>.
#   (2) ONE prune rule (review 11.4.276 round 5, structural replacement): a path is pruned iff
#     (a) git records it as a GITLINK (mode 160000, exact literal path; never a pathspec prefix, never a bare
#         .gitmodules line) in the repository it belongs to, AND
#     (b) a helix-deps.yaml of that repository's chain marks it `third_party: true`: the manifest at the gate root
#         (which may name a NESTED gitlink such as submodules/a/submodules/b, resolved through POPULATED own
#         gitlinks), or the manifest at the top of a populated nested gitlink's own repository.
#   Custody means the INDEX (not HEAD, not the working tree): the marks are read from the manifest's index blob
#   (stage 0), so a staged, uncommitted mark is honoured. The manifest is refused (scan more, note on stderr) when it
#   is untracked, unmerged, a symlink or reached through one, carries an index tag other than `H` (skip-worktree `S`,
#   assume-unchanged `h`, ...: git no longer compares that entry with the worktree), or differs visibly from the index.
#   No worktree state (skip-worktree, assume-unchanged, a clean filter, fsmonitor) can change what the marks say.
#   There is NO ownership-by-URL rule and NO own-org list: .gitmodules URLs never prune anything. An
#   AMBIGUOUS .gitmodules entry (duplicate path, a name with several paths, a multi-valued url, an
#   unparseable or symlinked .gitmodules) keeps the gitlink scanned even when the manifest marks it.
#   Unsafe values are DROPPED, never interpreted (a prune entry that is empty,
#   absolute, has a `..` or `.` segment, a leading `-`, whitespace, or a glob
#   metacharacter `* ? [ ] \` could prune first-party code or break the
#   caller's word-split; dropping errs toward scanning more, the safe side
#   for a false-positive-reducing prune). A missing/unreadable/garbled
#   manifest yields no entries (it never fails the caller).
# Read-only; no network; no execution of manifest content.

cm_third_party_prune_ok() { # $1=candidate -> 0 iff safe relative path
    case "$1" in
        ''|/*|-*|.|..|./*|*/.|*/./*|../*|*/..|*/../*) return 1 ;;
        *[[:space:]]*|*[\*\?\[\]\\]*) return 1 ;;
    esac
    # printable ASCII only (binary garbage in a manifest is dropped)
    case "$1" in *[!A-Za-z0-9._/+@%=,:~-]*) return 1 ;; esac
    return 0
}

# Round 4 (review 11.4.276): NO hand-written manifest parser lives here. Manifests are read by the
# ONE shared structural reader scripts/deps_manifest/helix_deps_tsv.{sh,py} (real YAML via PyYAML,
# duplicate keys refused, independent list-item cross-check). Fail-closed = scan MORE: when the
# reader is unavailable or refuses the manifest (unparseable, duplicate key, tabs, multi-document,
# flow style, unknown shape, count mismatch) NO manifest-derived entry is emitted -- only the literal
# directory names -- and a note goes to stderr.
_CM_TP_LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
. "$_CM_TP_LIBDIR/../deps_manifest/helix_deps_tsv.sh" 2>/dev/null || cm_hdeps_tsv() { return 3; }

# ── Recorded-gitlink resolver (killpg scope; round 5: manifest-on-recorded-gitlink is the ONLY rule) ──────
# No usable git metadata (no git binary, an exported tree, a git failure): FAIL CLOSED -- only the literal directory
# names are pruned, a note goes to stderr, the scan covers more. Populated gitlinks that are not marked are
# descended (depth <= 3) so their own tracked manifests can mark their own recorded gitlinks.
_cm_tp_git() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CEILING_DIRECTORIES -u GIT_COMMON_DIR git "$@"; }

# cm_tp_is_gitlink <repo-top> <path-from-top> : exact gitlink (mode 160000, path field identical)
cm_tp_is_gitlink() {
    local rec mode path
    case "$2" in ''|/*|*$'\n'*) return 1 ;; esac
    while IFS= read -r -d '' rec; do
        mode="${rec%% *}"; path="${rec#*$'\t'}"
        [ "$mode" = 160000 ] && [ "$path" = "$2" ] && return 0
    done < <(_cm_tp_git -C "$1" -c core.quotePath=false ls-files -s -z --full-name -- ":(literal)$2" 2>/dev/null)
    return 1
}

# cm_tp_ambiguous <repo-top> <path-from-top> : 0 iff <repo-top>/.gitmodules cannot vouch for a single entry of <path>:
# symlinked or unparseable file, the path listed more than once, its name carrying several paths or several urls.
cm_tp_ambiguous() {
    local top="$1" p="$2" gm="$1/.gitmodules" rec key val name="" n=0 np=0 nu=0
    [ -e "$gm" ] || [ -L "$gm" ] || return 1
    [ -f "$gm" ] && [ ! -L "$gm" ] && [ -r "$gm" ] || return 0
    _cm_tp_git config -f "$gm" --list >/dev/null 2>&1 || return 0
    while IFS= read -r -d '' rec; do
        key="${rec%%$'\n'*}"; val="${rec#*$'\n'}"
        [ "$val" = "$p" ] || continue
        n=$((n+1)); name="${key#submodule.}"; name="${name%.path}"
    done < <(_cm_tp_git config -f "$gm" --null --get-regexp '^submodule\..*\.path$' 2>/dev/null)
    [ "$n" -le 1 ] || return 0
    [ -n "$name" ] || return 1          # a gitlink without a .gitmodules entry: nothing to contradict the manifest
    while IFS= read -r -d '' rec; do np=$((np+1)); done < <(_cm_tp_git config -f "$gm" --null --get-all "submodule.$name.path" 2>/dev/null)
    while IFS= read -r -d '' rec; do nu=$((nu+1)); done < <(_cm_tp_git config -f "$gm" --null --get-all "submodule.$name.url" 2>/dev/null)
    [ "$np" -le 1 ] && [ "$nu" -le 1 ] && return 1
    return 0
}

# cm_tp_recorded <repo-top> <path> : an exact, unambiguous gitlink of that repository
cm_tp_recorded() { cm_tp_is_gitlink "$1" "$2" && ! cm_tp_ambiguous "$1" "$2"; }

# cm_tp_populated <dir> : a real (non-symlink) directory that is the top level of its own git repository
cm_tp_populated() {
    local d="$1" t
    [ -d "$d" ] && [ ! -L "$d" ] || return 1
    t="$(_cm_tp_git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [ "$(cd -P "$d" 2>/dev/null && pwd -P)" = "$t" ]
}

# cm_tp_no_symlink <base> <rel> : no component of base/rel is a symlink
cm_tp_no_symlink() {
    local cur="$1" rest="$2" seg
    while [ -n "$rest" ]; do
        seg="${rest%%/*}"; case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
        cur="$cur/$seg"; [ ! -L "$cur" ] || return 1
    done
    return 0
}

# cm_tp_gitlink_deep <repo-top> <path> <depth> : is <path> a recorded gitlink of the repo, or of a POPULATED recorded
# gitlink parent's own repository (a root manifest may name submodules/a/submodules/b)?
cm_tp_gitlink_deep() {
    local top="$1" p="$2" depth="$3" pre="" rest seg
    cm_tp_recorded "$top" "$p" && return 0
    [ "$depth" -lt 3 ] || return 1
    rest="$p"
    while [[ "$rest" == */* ]]; do
        seg="${rest%%/*}"; rest="${rest#*/}"; pre="${pre:+$pre/}$seg"
        cm_tp_recorded "$top" "$pre" || continue
        cm_tp_populated "$top/$pre" || return 1
        cm_tp_gitlink_deep "$top/$pre" "$rest" $((depth+1)); return $?
    done
    return 1
}

# cm_tp_manifest_recorded <repo-top> <path-from-top> : the manifest is tracked at stage 0 with index tag `H` (never
# skip-worktree / assume-unchanged / unmerged), is a regular non-symlink file reached through no symlinked component,
# and shows no visible worktree difference (else it is not the repository's recorded declaration and is ignored).
# The worktree checks only make the gate scan MORE; the marks themselves come from the index blob (cm_tp_manifest_blob).
cm_tp_manifest_recorded() {
    local top="$1" p="$2" tags
    [ -f "$top/$p" ] && [ -r "$top/$p" ] && cm_tp_no_symlink "$top" "$p" || return 1
    _cm_tp_git -C "$top" ls-files --error-unmatch -- ":(literal)$p" >/dev/null 2>&1 || return 1
    tags="$(_cm_tp_git -C "$top" -c core.quotePath=false ls-files -v -- ":(literal)$p" 2>/dev/null | cut -c1-2 | LC_ALL=C sort -u)" || return 1
    [ "$tags" = "H " ] || return 1
    _cm_tp_git -C "$top" -c core.quotePath=false diff --quiet --no-ext-diff -- ":(literal)$p" >/dev/null 2>&1
}

# cm_tp_manifest_blob <repo-top> <path-from-top> <out-file> : writes the stage-0 INDEX blob of the manifest, raw (no
# filter, no textconv), to <out-file>. Non-zero when git cannot produce it (then no mark is read).
cm_tp_manifest_blob() {
    _cm_tp_git -C "$1" cat-file blob ":$2" > "$3" 2>/dev/null
}

# cm_tp_level <top> <prefix> <outpre> <depth> : emits (relative to the gate root) every manifest-marked recorded gitlink
cm_tp_level() {
    local top="$1" prefix="$2" outpre="$3" depth="$4"
    local base="$top"; [ -n "$prefix" ] && base="$top/$prefix"
    local -A tp=() emitted=()
    local rec g rel recs rc n path u r2 tpf pp mf="${prefix:+$prefix/}helix-deps.yaml"

    if [ -e "$base/helix-deps.yaml" ] || [ -L "$base/helix-deps.yaml" ]; then
        if ! cm_tp_manifest_recorded "$top" "$mf"; then
            echo "third_party_prune: manifest $base/helix-deps.yaml is not the recorded copy (tracked at stage 0 with index tag H, no visible edit, non-symlink); manifest marks ignored" >&2
        else
            local blobf; blobf="$(mktemp "${TMPDIR:-/tmp}/tp_manifest.XXXXXX")" || blobf=""
            if [ -n "$blobf" ] && cm_tp_manifest_blob "$top" "$mf" "$blobf"; then recs="$(cm_hdeps_tsv "$blobf")"; rc=$?
            else recs=""; rc=8; fi
            [ -n "$blobf" ] && rm -f -- "${blobf:?}"
            if [ "$rc" != 0 ]; then
                echo "third_party_prune: manifest $base/helix-deps.yaml not usable (index blob reader rc=$rc); manifest marks ignored" >&2
            else
                while IFS=$'\x1f' read -r n path u r2 tpf; do
                    [ "$tpf" = 1 ] || continue
                    [ -n "$path$n" ] || continue
                    pp="${path:-submodules/$n}"; pp="${pp%/}"
                    cm_third_party_prune_ok "$pp" || continue
                    cm_tp_no_symlink "$base" "$pp" || continue
                    if cm_tp_gitlink_deep "$top" "${prefix:+$prefix/}$pp" "$depth"; then tp["$pp"]=1
                    else echo "third_party_prune: manifest marks $outpre${outpre:+/}$pp third_party but it is not an unambiguous recorded gitlink; NOT pruned (scanning it)" >&2; fi
                done <<<"$recs"
            fi
        fi
    fi

    # the gitlinks recorded under the scan base: marked -> emitted; populated -> descended
    while IFS= read -r -d '' rec; do
        [ "${rec%% *}" = 160000 ] || continue
        g="${rec#*$'\t'}"
        case "$g" in *$'\n'*) continue ;; esac
        if [ -n "$prefix" ]; then case "$g" in "$prefix"/*) rel="${g#"$prefix"/}" ;; *) continue ;; esac; else rel="$g"; fi
        cm_third_party_prune_ok "$rel" || continue
        cm_tp_no_symlink "$base" "$rel" || continue
        if [ -n "${tp[$rel]:-}" ]; then
            emitted["$rel"]=1; printf '%s\n' "${outpre:+$outpre/}$rel"; continue
        fi
        [ "$depth" -lt 3 ] || continue
        cm_tp_populated "$base/$rel" && cm_tp_level "$base/$rel" "" "${outpre:+$outpre/}$rel" $((depth+1))
    done < <(_cm_tp_git -C "$top" -c core.quotePath=false ls-files -s -z --full-name 2>/dev/null)
    # manifest marks that are deep (not direct gitlinks of this level) are emitted too
    for rel in "${!tp[@]}"; do
        [ -n "${emitted[$rel]:-}" ] || printf '%s\n' "${outpre:+$outpre/}$rel"
    done
}

cm_third_party_prune_paths() { # $1=root
    local root="${1:-}" top rootp prefix=""
    [ -n "$root" ] && [ -d "$root" ] || return 0
    printf '%s\n' third_party site-packages
    command -v git >/dev/null 2>&1 || { echo "third_party_prune: git unavailable; pruning literal directory names only (scanning submodules too)" >&2; return 0; }
    rootp="$(cd -P "$root" 2>/dev/null && pwd -P)" || return 0
    top="$(_cm_tp_git -C "$rootp" rev-parse --show-toplevel 2>/dev/null)" || {
        echo "third_party_prune: no usable git metadata at $root; pruning literal directory names only (fail closed: scanning submodule-like trees too)" >&2; return 0; }
    [ "$rootp" = "$top" ] || prefix="${rootp#"$top"/}"
    cm_tp_level "$top" "$prefix" "" 0 | LC_ALL=C sort -u
    return 0
}

# cm_tp_glob_escape <string> : escape find(1) -path glob metacharacters.
cm_tp_glob_escape() {
    local s="$1" out="" i ch
    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"
        case "$ch" in '*'|'?'|'['|']'|'\') out+="\\$ch" ;; *) out+="$ch" ;; esac
    done
    printf '%s' "$out"
}

# cm_third_party_prune_find_expr <root> : appends to the caller's array
# `prune_expr` the find(1) alternatives for the third-party prune, ROOT-ANCHORED
# (round 3, review M3): the literal names third_party / site-packages prune by
# name at any depth; every manifest-derived path (even a single segment such as
# `vend`) prunes only <root>/<path>, never a same-named first-party directory
# deeper in the tree. The caller must have declared `prune_expr=()`.
cm_third_party_prune_find_expr() {
    local root="$1" ex er
    er="$(cm_tp_glob_escape "$root")"
    while IFS= read -r ex; do
        [ -n "$ex" ] || continue
        case "$ex" in
            third_party|site-packages) prune_expr+=(-name "$ex" -o) ;;
            *) prune_expr+=(-path "$er/$(cm_tp_glob_escape "$ex")" -o -path "$er/$(cm_tp_glob_escape "$ex")/*" -o) ;;
        esac
    done < <(cm_third_party_prune_paths "$root")
}
