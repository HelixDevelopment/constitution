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
. "$_CM_TP_LIBDIR/../deps_manifest/helix_deps_tsv.sh" 2>/dev/null || cm_hdeps_tsv() { return 3; }

# cm_tp_recorded <basedir> <relpath> : is <relpath> a RECORDED submodule of the repository at <basedir>?
# Review finding (killpg scope, round 2): a manifest line `path: src / third_party: true` must not hide
# first-party code. A third_party prune entry is honoured only when the path is a gitlink (mode 160000) in
# the git index/tree or a `.gitmodules` path. Where NO git metadata exists (no .git and no .gitmodules,
# e.g. an exported consumer layout) the manifest is the only record: that is ASSUMED (stated on stderr,
# once per manifest base) and the manifest entry is honoured. Fail-safe = scan MORE: git present but the
# path unrecorded -> NOT pruned.
cm_tp_recorded() {
    local b="$1" p="$2" mode
    if [ -e "$b/.git" ] && command -v git >/dev/null 2>&1; then
        mode="$(git -C "$b" ls-files -s -- "$p" 2>/dev/null | awk 'NR==1{print $1}')"
        [ "$mode" = 160000 ] && return 0
        # nested: a root manifest may name a dep inside a submodule (submodules/a/submodules/b). Walk the
        # parent prefixes; the first one that is a recorded gitlink is checked recursively in ITS repository.
        # An unpopulated parent checkout has nothing to hide, so it counts as recorded.
        local pre="" rest="$p" seg
        while [[ "$rest" == */* ]]; do
            seg="${rest%%/*}"; rest="${rest#*/}"; pre="${pre:+$pre/}$seg"
            [ "$(git -C "$b" ls-files -s -- "$pre" 2>/dev/null | awk 'NR==1{print $1}')" = 160000 ] || continue
            [ -e "$b/$pre/.git" ] || return 0
            cm_tp_recorded "$b/$pre" "$rest"; return $?
        done
        git -C "$b" config -f "$b/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' | grep -Fxq -- "$p" && return 0
        return 1
    fi
    if [ -f "$b/.gitmodules" ]; then
        awk -F= '/^[[:space:]]*path[[:space:]]*=/{gsub(/^[ \t]+|[ \t]+$/,"",$2);print $2}' "$b/.gitmodules" | grep -Fxq -- "$p"
        return $?
    fi
    echo "third_party_prune: no git metadata at $b; ASSUMING manifest third_party path $p is a submodule (no recorded-submodule check possible)" >&2
    return 0
}

# cm_tp_manifest_walk <manifest> <prefix> : prints "T<TAB>path" / "O<TAB>path"
# (third_party / own-org dep), paths already prefixed and validated.
cm_tp_manifest_walk() {
    local mf="$1" pre="$2" recs rc name path url ref tp p
    [ -f "$mf" ] && [ -r "$mf" ] && [ ! -L "$mf" ] || return 0
    recs="$(cm_hdeps_tsv "$mf")"; rc=$?
    if [ "$rc" != 0 ]; then
        echo "third_party_prune: manifest $mf not usable (reader rc=$rc); pruning literal directory names only" >&2
        return 0
    fi
    while IFS=$'\x1f' read -r name path url ref tp; do
        [ -n "$path$name" ] || continue
        p="${path:-submodules/$name}"
        p="${p%/}"
        cm_third_party_prune_ok "$p" || continue   # validate the RAW path before prefixing
        [ -n "$pre" ] && p="$pre/$p"
        cm_third_party_prune_ok "$p" || continue
        if [ "$tp" = 1 ]; then
            if cm_tp_recorded "$(dirname "$mf")" "${p#"$pre"/}"; then printf 'T\t%s\n' "$p"
            else echo "third_party_prune: manifest marks $p third_party but it is not a recorded submodule; NOT pruned (scanning it)" >&2; fi
        else printf 'O\t%s\n' "$p"; fi
    done <<<"$recs"
}

# cm_tp_descend <root> <rel> <depth> : emit third_party entries of <rel>'s manifest, recurse into own-org.
cm_tp_descend() {
    local root="$1" rel="$2" depth="$3" kind p d tps="" own="" c
    local base="$root"; [ -n "$rel" ] && base="$root/$rel"
    while IFS=$'\t' read -r kind p; do
        [ -n "$kind" ] || continue
        if [ "$kind" = T ]; then printf '%s\n' "$p"; tps="$tps|$p|"; else own="$own $p"; fi
    done < <(cm_tp_manifest_walk "$base/helix-deps.yaml" "$rel")
    [ "$depth" -lt 3 ] || return 0
    for d in "$base"/submodules/*/; do
        d="${d%/}"; [ -d "$d" ] && [ ! -L "$d" ] || continue
        c="${d#"$root"/}"
        cm_third_party_prune_ok "$c" || continue
        case "$tps" in *"|$c|"*) continue ;; esac
        case " $own " in *" $c "*) ;; *) own="$own $c" ;; esac
    done
    for c in $own; do
        case "$tps" in *"|$c|"*) continue ;; esac
        [ -d "$root/$c" ] && [ ! -L "$root/$c" ] || continue
        cm_tp_descend "$root" "$c" $((depth+1))
    done
}

cm_third_party_prune_paths() { # $1=root
    local root="${1:-}"
    [ -n "$root" ] && [ -d "$root" ] || return 0
    # Operator decision 2026-11-01: .gitmodules paths are NOT pruned (own-org
    # submodules stay scanned); only third_party:true deps (root + nested own-org
    # manifests) and the directory names printed here are.
    printf '%s\n' third_party site-packages
    cm_tp_descend "$root" "" 0 | LC_ALL=C sort -u
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
