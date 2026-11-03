# shellcheck shell=bash
# scripts/lib/third_party_prune.sh — ONE resolver for the third-party /
# separate-repository trees that scanner gates prune by default.
#
# Why: scanner gates (CM-DANGEROUS-COMBINATION-FAIL-CLOSED §11.4.252,
# CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT §11.4.245) defaulted to descending
# into every submodule. Measured on the canon (2026-10-31): 6345 of 6759 oracle
# hits and a >15 minute dangerous-combination run came from trees the scanning
# repository does not own; each separate repository adopts the gate itself.
#
# cm_third_party_prune_paths <root>
#   Prints, one per line, root-relative directory paths to prune:
#     (1) every `path =` of <root>/.gitmodules (each is a separate repository),
#     (2) every helix-deps.yaml dep with `third_party: true`: its explicit
#         `path:` or, when absent, `submodules/<name>`.
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

cm_third_party_prune_paths() { # $1=root
    local root="${1:-}" line p name path tp inblock
    [ -n "$root" ] && [ -d "$root" ] || return 0
    if [ -f "$root/.gitmodules" ] && [ -r "$root/.gitmodules" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                [[:space:]]*path[[:space:]]*=*|path[[:space:]]*=*)
                    p="${line#*=}"; p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
                    p="${p%/}"
                    cm_third_party_prune_ok "$p" && printf '%s\n' "$p"
                    ;;
            esac
        done < <(LC_ALL=C tr -d '\000' < "$root/.gitmodules" 2>/dev/null | head -c 1048576)
    fi
    if [ -f "$root/helix-deps.yaml" ] && [ -r "$root/helix-deps.yaml" ]; then
        name=""; path=""; tp=0; inblock=0
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                *"- name:"*)
                    if [ "$inblock" = 1 ] && [ "$tp" = 1 ]; then
                        p="${path:-submodules/$name}"
                        cm_third_party_prune_ok "$p" && printf '%s\n' "$p"
                    fi
                    inblock=1; tp=0; path=""
                    name="${line#*name:}"; name="${name//\"/}"; name="${name//\'/}"
                    name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
                    ;;
                [[:space:]]*path:*)
                    path="${line#*path:}"; path="${path%%#*}"; path="${path//\"/}"; path="${path//\'/}"
                    path="${path#"${path%%[![:space:]]*}"}"; path="${path%"${path##*[![:space:]]}"}"; path="${path%/}"
                    ;;
                [[:space:]]*third_party:*)
                    p="${line#*third_party:}"; p="${p%%#*}"; p="${p//[[:space:]]/}"
                    [ "$p" = true ] && tp=1
                    ;;
            esac
        done < <(LC_ALL=C tr -d '\000' < "$root/helix-deps.yaml" 2>/dev/null | head -c 1048576)
        if [ "$inblock" = 1 ] && [ "$tp" = 1 ]; then
            p="${path:-submodules/$name}"
            cm_third_party_prune_ok "$p" && printf '%s\n' "$p"
        fi
    fi
    return 0
}
