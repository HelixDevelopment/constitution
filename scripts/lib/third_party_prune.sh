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
#   Custody means the INDEX ENTRY (not HEAD, not the object store, not git's view of the worktree): the marks are
#   parsed from a snapshot of the worktree file, and only when `git hash-object --no-filters` of that snapshot equals
#   the blob sha that the ONE index record for exactly that path (literal pathspec, stage 0, mode 100644) records.
#   So a staged, uncommitted mark is honoured, and the bytes read are by construction the bytes the index records.
#   The object store is NEVER read (a `git replace` ref, a forged loose object, GIT_OBJECT_DIRECTORY, alternates or a
#   replace namespace cannot change the bytes), no filter / textconv / fsmonitor runs, and the index-path syntax `:p`
#   is not used (a root named `0:s` reads its own file). The manifest is refused (scan more, note on stderr) when it is
#   untracked, intent-to-add, unmerged, recorded with another mode (a symlink 120000, an executable 100755), a symlink
#   or reached through one in the worktree, executable in the worktree, or byte-different from its index entry
#   (whatever skip-worktree / assume-unchanged / filter state hides that difference from `git status`).
#   The worktree file is read by ONE bounded open (review 11.4.276 follow-ups r2, G1): an embedded `python3 -I` reader
#   walks the path from the repository top with O_NOFOLLOW on EVERY component, opens the last one
#   O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_NOCTTY, fstat()s that fd (regular file, no exec bit, st_size <= 1 MiB), reads at most
#   cap+1 bytes and refuses when more arrive, and only then writes the bytes it read into a private snapshot file. That
#   snapshot is the ONLY input of both the hash and the parse, so swapping the path for a FIFO, a device or symlink, a
#   directory or other bytes between the index lookup and the read can only cause a refusal (scan more), never a hang,
#   an unbounded copy or a mark read from bytes that were not hashed. A hard-linked worktree file (nlink > 1) is NOT
#   refused: the decision rests on the snapshot bytes equalling the index sha, which another link cannot change after
#   the read; refusing it would add false refusals and no safety. The refusal reason is named on stderr (reason=...).
#   Every git call and the reader run under `timeout --foreground` (60 s, _CM_TP_GIT_TIMEOUT): a timed-out call is a
#   failed call, and every failure means scan more. Snapshots live in one mktemp -d directory per call, removed on exit
#   and on HUP/INT/TERM (a SIGKILL can still leave one `tp_manifest.*` directory behind; stated, not preventable).
#   Every git call runs under `env -i` (PATH and LC_ALL=C only, no global/system config): no caller GIT_* variable
#   (GIT_DIR, GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY, GIT_CONFIG_PARAMETERS, GIT_CONFIG_COUNT, GIT_NAMESPACE, ...) and no
#   ~/.gitconfig reaches git. Repository-local .git/config still applies (writing it is the same trust as writing
#   the index). Consequences, stated (both err toward scanning more): a manifest checked out with CRLF line ends by
#   core.autocrlf or an `eol=crlf` attribute is byte-different from its LF index blob and is refused (scanned); and a
#   `safe.directory` entry in ~/.gitconfig is not honoured under env -i, so a repository git calls dubious ownership is
#   not read at all (literal names only, scanned). Out of scope, stated: a SHA-1/SHA-256 collision, a tampered `git` binary on PATH, case-insensitive
#   file systems (the exact-path checks are byte-exact; a case-folding file system is not modelled).
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
# Every git call: an allowlisted environment (env -i) -- no caller GIT_* / config variables, no global or system config
# (review 11.4.276 follow-ups r1 F2). core.fsmonitor=false is hardening: no command this library runs refreshes the
# index, so it is not independently mutation-killable (stated, not claimed load-bearing).
_CM_TP_GIT_TIMEOUT=60                                  # seconds per git / reader call; tests may lower it after sourcing
_CM_TP_MAX_MANIFEST=1048576                            # bytes; a larger worktree manifest is refused, never copied
_CM_TP_TIMEOUT="$(command -v timeout 2>/dev/null)" || _CM_TP_TIMEOUT=""
_CM_TP_SNAPDIR=""                                      # set per call by _cm_tp_run (private mktemp -d); empty = no marks read
_cm_tp_git() {
    local to=(); [ -n "$_CM_TP_TIMEOUT" ] && to=("$_CM_TP_TIMEOUT" --foreground -k 5 "$_CM_TP_GIT_TIMEOUT")
    env -i PATH="${PATH:-/usr/bin:/bin}" LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 "${to[@]}" git -c core.fsmonitor=false "$@"
}

# The bounded reader (G1). argv: <top> <relative path> <out file> <cap>. Exit 0 = the bytes are in <out file>;
# 2 usage, 3 not a regular file, 4 executable, 5 larger than cap, 6 grew past cap while read, 7 open/walk failed (a
# symlinked component, missing, not a directory), 8 read error, 9 write error. Nothing is written unless it exits 0.
IFS= read -r -d '' _CM_TP_READ_PY <<'PY' || :
import os, stat, sys
def main(a):
    if len(a) != 4:
        return 2
    top, rel, outp, cap = a
    try:
        cap = int(cap)
    except ValueError:
        return 2
    segs = rel.split("/")
    if cap < 0 or any(s in ("", ".", "..") for s in segs):
        return 2
    fl = os.O_RDONLY | os.O_CLOEXEC
    try:
        d = os.open(top, fl | os.O_DIRECTORY)
    except OSError:
        return 7
    try:
        for s in segs[:-1]:
            nd = os.open(s, fl | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=d)
            os.close(d)
            d = nd
        fd = os.open(segs[-1], fl | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_NOCTTY, dir_fd=d)
    except OSError:
        return 7
    finally:
        os.close(d)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return 3
        if st.st_mode & 0o111:
            return 4
        if st.st_size > cap:
            return 5
        buf = bytearray()
        while len(buf) <= cap:
            try:
                chunk = os.read(fd, min(65536, cap + 1 - len(buf)))
            except OSError:
                return 8
            if not chunk:
                break
            buf += chunk
        if len(buf) > cap:
            return 6
    finally:
        os.close(fd)
    try:
        o = os.open(outp, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC)
        try:
            v = memoryview(buf)
            while v:
                v = v[os.write(o, v):]
        finally:
            os.close(o)
    except OSError:
        return 9
    return 0
sys.exit(main(sys.argv[1:]))
PY

# _cm_tp_bounded <top> <path-from-top> <out-file> : runs the bounded reader, time bounded; its exit status
_cm_tp_bounded() {
    local to=(); [ -n "$_CM_TP_TIMEOUT" ] && to=("$_CM_TP_TIMEOUT" --foreground -k 5 "$_CM_TP_GIT_TIMEOUT")
    command -v python3 >/dev/null 2>&1 || return 10
    env -i PATH="${PATH:-/usr/bin:/bin}" LC_ALL=C "${to[@]}" python3 -I -B -c "$_CM_TP_READ_PY" "$1" "$2" "$3" "$_CM_TP_MAX_MANIFEST" 2>/dev/null
}

# _cm_tp_why <rc> : the name of a reader refusal
_cm_tp_why() {
    case "$1" in
        3) echo notreg ;; 4) echo exec ;; 5) echo toolarge ;; 6) echo grew ;; 7) echo open ;; 8) echo read ;; 9) echo write ;;
        10) echo nopython ;; 124|137) echo timeout ;; *) echo "error$1" ;;
    esac
}

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

# cm_tp_manifest_entry <repo-top> <path-from-top> : prints the blob sha of the ONE index record for exactly that path
# (literal pathspec, byte-exact path, stage 0, mode 100644); non-zero otherwise (untracked, unmerged, symlink, 100755).
cm_tp_manifest_entry() {
    local rec meta mode sha="" stage rp n=0
    while IFS= read -r -d '' rec; do
        rp="${rec#*$'\t'}"; meta="${rec%%$'\t'*}"
        [ "$rp" = "$2" ] || continue
        n=$((n+1)); read -r mode sha stage <<<"$meta"
        [ "$mode" = 100644 ] || return 1
        [ "$stage" = 0 ] || return 1
    done < <(_cm_tp_git -C "$1" -c core.quotePath=false ls-files -s -z --full-name -- ":(literal)$2" 2>/dev/null)
    [ "$n" -eq 1 ] || return 1
    case "$sha" in ''|*[!0-9a-f]*) return 1 ;; esac
    printf '%s' "$sha"
}

# cm_tp_manifest_recorded <repo-top> <path-from-top> <out-file> : writes to <out-file> the manifest bytes the INDEX
# records, or returns non-zero (then no mark is read; the reason is left in _CM_TP_WHY). ONE bounded open (the reader
# above) takes the snapshot: a regular, non-executable file of at most 1 MiB reached through no symlinked component.
# The snapshot is accepted only when its `hash-object --no-filters` equals the index entry's sha (cm_tp_manifest_entry),
# and the caller parses that same snapshot. The object store is never read; the worktree path is opened once.
cm_tp_manifest_recorded() {
    local top="$1" p="$2" out="$3" sha got rc
    _CM_TP_WHY=entry
    sha="$(cm_tp_manifest_entry "$top" "$p")" || return 1
    _cm_tp_bounded "$top" "$p" "$out"; rc=$?
    [ "$rc" -eq 0 ] || { _CM_TP_WHY="$(_cm_tp_why "$rc")"; return 1; }
    _CM_TP_WHY=hash
    got="$(_cm_tp_git -C "$top" hash-object --no-filters --stdin < "$out" 2>/dev/null)" || return 1
    _CM_TP_WHY=differs
    [ "$got" = "$sha" ]
}

# cm_tp_level <top> <prefix> <outpre> <depth> : emits (relative to the gate root) every manifest-marked recorded gitlink
cm_tp_level() {
    local top="$1" prefix="$2" outpre="$3" depth="$4"
    local base="$top"; [ -n "$prefix" ] && base="$top/$prefix"
    local -A tp=() emitted=()
    local rec g rel recs rc n path u r2 tpf pp mf="${prefix:+$prefix/}helix-deps.yaml"

    if [ -e "$base/helix-deps.yaml" ] || [ -L "$base/helix-deps.yaml" ]; then
        local blobf=""; _CM_TP_WHY=tempfile
        [ -n "$_CM_TP_SNAPDIR" ] && blobf="$(mktemp "${_CM_TP_SNAPDIR:?}/m.XXXXXX")" || blobf=""
        if [ -z "$blobf" ] || ! cm_tp_manifest_recorded "$top" "$mf" "$blobf"; then
            echo "third_party_prune: manifest $base/helix-deps.yaml is not the recorded copy (one stage-0 mode-100644 index entry whose bytes equal the regular, non-executable, non-symlink worktree file of at most 1 MiB; reason=${_CM_TP_WHY:-unknown}); manifest marks ignored" >&2
            [ -n "$blobf" ] && rm -f -- "${blobf:?}"
        else
            recs="$(cm_hdeps_tsv "$blobf")"; rc=$?
            rm -f -- "${blobf:?}"
            if [ "$rc" != 0 ]; then
                echo "third_party_prune: manifest $base/helix-deps.yaml not usable (recorded-copy reader rc=$rc); manifest marks ignored" >&2
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
    ( _cm_tp_run "$top" "$prefix" )
    return 0
}

# _cm_tp_run <top> <prefix> : run in a subshell. One private snapshot directory, removed by the EXIT trap, which bash
# also runs when the subshell is killed by HUP/INT/TERM (measured: a TERM-killed subshell ran its EXIT trap).
_cm_tp_run() {
    _CM_TP_SNAPDIR="$(mktemp -d "${TMPDIR:-/tmp}/tp_manifest.XXXXXX" 2>/dev/null)" || _CM_TP_SNAPDIR=""
    if [ -n "$_CM_TP_SNAPDIR" ]; then
        trap 'rm -rf -- "${_CM_TP_SNAPDIR:?}"' EXIT   # bash also runs it on HUP/INT/TERM (measured, bash 5.3)
    else
        echo "third_party_prune: no private temp directory; manifest marks ignored (scanning more)" >&2
    fi
    cm_tp_level "$1" "$2" "" 0 | LC_ALL=C sort -u
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
