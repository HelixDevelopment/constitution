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
#   Prints, one per line, what to prune (operator decision 2026-11-01):
#     (1) the directory names `third_party` and `site-packages`,
#     (2) every <root>/helix-deps.yaml dep with `third_party: true`: its explicit
#         `path:` or, when absent, `submodules/<name>`.
#     (3) NESTED (operator decision 2026-11-01): each own-org (not third_party)
#         submodule found under <root>/submodules/* or named by a non-third_party
#         dep path is descended (depth <= 3, symlinks never followed) and ITS
#         helix-deps.yaml third_party:true entries are emitted as
#         <submodule path>/<dep path or submodules/<name>>, same validation.
#         Upstream marking is therefore required for nested third-party trees.
#   <root>/.gitmodules is NOT consulted: an own-org submodule (listed in
#   .gitmodules, or absent from helix-deps.yaml, or not marked third_party)
#   stays scanned. (Before 2026-11-01 every .gitmodules `path =` was pruned.)
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
declare -F cm_gate_env_set >/dev/null 2>&1 || { [ -r "$_CM_TP_LIBDIR/gate_env_override.sh" ] && . "$_CM_TP_LIBDIR/gate_env_override.sh"; }
# shellcheck disable=SC1091
. "$_CM_TP_LIBDIR/../deps_manifest/helix_deps_tsv.sh" 2>/dev/null || cm_hdeps_tsv() { return 3; }

# ── Recorded-gitlink resolver (killpg scope, review round 3: structural replacement) ─────────────────
# A path is prunable ONLY when git itself records it as a GITLINK (mode 160000) with an EXACT, literal path match
# (never a pathspec prefix, never NR==1 of a listing, never a bare .gitmodules line). Two independent sources may
# then mark a recorded gitlink third-party:
#   (U) its .gitmodules remote URL names an organisation that is NOT in the own-org list (§11.4.79(6); the list is
#       consumer DATA: argument 2 of cm_third_party_prune_paths, else the guarded HELIX_OWN_ORGS, else
#       vasic-digital,HelixDevelopment -- the same default as verify_helix_deps_manifests.sh);
#   (M) the repository's own helix-deps.yaml marks the dep `third_party: true` (manifest alone never prunes anything
#       that is not a recorded gitlink of that same repository).
# A relative or unparseable URL, a gitlink without a .gitmodules entry, an unpopulated or symlinked path: scanned.
# No usable git metadata (no git binary, an exported tree, a git failure): FAIL CLOSED -- only the literal directory
# names are pruned, a note goes to stderr, the scan covers more. Own-org populated gitlinks are descended (depth <= 3)
# so their nested third-party gitlinks are found by the same two rules inside THEIR repository.
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

# cm_tp_gitlink_deep <repo-top> <path> <depth> : is <path> an exact gitlink of the repo, or of a POPULATED gitlink
# parent's own repository (a root manifest may name submodules/a/submodules/b)?
cm_tp_gitlink_deep() {
    local top="$1" p="$2" depth="$3" pre="" rest seg
    cm_tp_is_gitlink "$top" "$p" && return 0
    [ "$depth" -lt 3 ] || return 1
    rest="$p"
    while [[ "$rest" == */* ]]; do
        seg="${rest%%/*}"; rest="${rest#*/}"; pre="${pre:+$pre/}$seg"
        cm_tp_is_gitlink "$top" "$pre" || continue
        cm_tp_populated "$top/$pre" || return 1
        cm_tp_gitlink_deep "$top/$pre" "$rest" $((depth+1)); return $?
    done
    return 1
}

# cm_tp_url_third <url> <orgs-csv> : 0 iff url is an absolute remote whose organisation is not an own org
cm_tp_url_third() {
    local u="${1,,}" orgs="${2,,}" o
    case "$u" in ''|./*|../*) return 1 ;; esac
    [[ "$u" =~ ^([a-z][a-z0-9+.-]*://[^/]+/|[^/@[:space:]]+@[^:/[:space:]]+:|[^/@:[:space:]]+:)/?[^[:space:]]+$ ]] || return 1
    local IFS=,
    for o in $orgs; do
        [[ "$o" =~ ^[a-z0-9._-]+$ ]] || continue
        [[ "$u" =~ (^|[/:])"$o"/ ]] && return 1
    done
    return 0
}

# cm_tp_level <top> <prefix> <outpre> <depth> <orgs> : emits (relative to the gate root) every third-party gitlink
cm_tp_level() {
    local top="$1" prefix="$2" outpre="$3" depth="$4" orgs="$5"
    local base="$top"; [ -n "$prefix" ] && base="$top/$prefix"
    local -A tp=() nameof=() emitted=()
    local rec key val name g rel url recs rc n path u tpf pp

    # (M) manifest marks, honoured only on recorded gitlinks
    if [ -f "$base/helix-deps.yaml" ] && [ -r "$base/helix-deps.yaml" ] && [ ! -L "$base/helix-deps.yaml" ]; then
        recs="$(cm_hdeps_tsv "$base/helix-deps.yaml")"; rc=$?
        if [ "$rc" != 0 ]; then
            echo "third_party_prune: manifest $base/helix-deps.yaml not usable (reader rc=$rc); manifest marks ignored" >&2
        else
            while IFS=$'\x1f' read -r n path u rel tpf; do
                [ "$tpf" = 1 ] || continue
                [ -n "$path$n" ] || continue
                pp="${path:-submodules/$n}"; pp="${pp%/}"
                cm_third_party_prune_ok "$pp" || continue
                cm_tp_no_symlink "$base" "$pp" || continue
                if cm_tp_gitlink_deep "$top" "${prefix:+$prefix/}$pp" "$depth"; then tp["$pp"]=1
                else echo "third_party_prune: manifest marks $outpre${outpre:+/}$pp third_party but it is not a recorded gitlink; NOT pruned (scanning it)" >&2; fi
            done <<<"$recs"
        fi
    fi

    # (U) .gitmodules name -> path/url map (top level of THIS repository)
    if [ -f "$top/.gitmodules" ] && [ ! -L "$top/.gitmodules" ]; then
        while IFS= read -r -d '' rec; do
            key="${rec%%$'\n'*}"; val="${rec#*$'\n'}"
            case "$key" in submodule.*.path) name="${key#submodule.}"; name="${name%.path}"; nameof["$val"]="$name" ;; esac
        done < <(_cm_tp_git config -f "$top/.gitmodules" --null --get-regexp '^submodule\..*\.path$' 2>/dev/null)
    fi

    # the gitlinks recorded under the scan base
    while IFS= read -r -d '' rec; do
        [ "${rec%% *}" = 160000 ] || continue
        g="${rec#*$'\t'}"
        case "$g" in *$'\n'*) continue ;; esac
        if [ -n "$prefix" ]; then case "$g" in "$prefix"/*) rel="${g#"$prefix"/}" ;; *) continue ;; esac; else rel="$g"; fi
        cm_third_party_prune_ok "$rel" || continue
        cm_tp_no_symlink "$base" "$rel" || continue
        if [ -n "${tp[$rel]:-}" ]; then printf '%s\n' "${outpre:+$outpre/}$rel"; emitted["$rel"]=1; continue; fi
        name="${nameof[$g]:-}"
        if [ -n "$name" ]; then
            url="$(_cm_tp_git config -f "$top/.gitmodules" --get "submodule.$name.url" 2>/dev/null)"
            if cm_tp_url_third "$url" "$orgs"; then printf '%s\n' "${outpre:+$outpre/}$rel"; continue; fi
        fi
        [ "$depth" -lt 3 ] || continue
        cm_tp_populated "$base/$rel" && cm_tp_level "$base/$rel" "" "${outpre:+$outpre/}$rel" $((depth+1)) "$orgs"
    done < <(_cm_tp_git -C "$top" -c core.quotePath=false ls-files -s -z --full-name 2>/dev/null)
    # manifest marks that are deep (not direct gitlinks of this level) are emitted too
    for rel in "${!tp[@]}"; do
        [ -n "${emitted[$rel]:-}" ] || printf '%s\n' "${outpre:+$outpre/}$rel"
    done
}

cm_third_party_prune_paths() { # $1=root [$2=own-orgs csv]
    local root="${1:-}" orgs="${2:-}" top rootp prefix=""
    [ -n "$root" ] && [ -d "$root" ] || return 0
    printf '%s\n' third_party site-packages
    if [ -z "$orgs" ]; then
        if declare -F cm_gate_env_set >/dev/null 2>&1; then cm_gate_env_set orgs HELIX_OWN_ORGS "vasic-digital,HelixDevelopment" value
        else orgs="vasic-digital,HelixDevelopment"; fi
    fi
    command -v git >/dev/null 2>&1 || { echo "third_party_prune: git unavailable; pruning literal directory names only (scanning submodules too)" >&2; return 0; }
    rootp="$(cd -P "$root" 2>/dev/null && pwd -P)" || return 0
    top="$(_cm_tp_git -C "$rootp" rev-parse --show-toplevel 2>/dev/null)" || {
        echo "third_party_prune: no usable git metadata at $root; pruning literal directory names only (fail closed: scanning submodule-like trees too)" >&2; return 0; }
    [ "$rootp" = "$top" ] || prefix="${rootp#"$top"/}"
    cm_tp_level "$top" "$prefix" "" 0 "$orgs" | LC_ALL=C sort -u
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
    local root="$1" ex er orgs="${2:-}"
    er="$(cm_tp_glob_escape "$root")"
    while IFS= read -r ex; do
        [ -n "$ex" ] || continue
        case "$ex" in
            third_party|site-packages) prune_expr+=(-name "$ex" -o) ;;
            *) prune_expr+=(-path "$er/$(cm_tp_glob_escape "$ex")" -o -path "$er/$(cm_tp_glob_escape "$ex")/*" -o) ;;
        esac
    done < <(cm_third_party_prune_paths "$root" "$orgs")
}
