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
#   opens the pinned level's directory "." (O_NOFOLLOW) and walks down with O_NOFOLLOW on EVERY component, opens the last one
#   O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_NOCTTY, fstat()s that fd (regular file, no exec bit, st_size <= 1 MiB), reads at most
#   cap+1 bytes and refuses when more arrive, and only then writes the bytes it read into a private snapshot file that has
#   no name any more (unlinked before the write, read back through its fd). That snapshot is the ONLY input of both the
#   hash and the parse, so swapping the path for a FIFO, a device or symlink, a directory or other bytes between the index
#   lookup and the read can only cause a refusal (scan more), never a hang, an unbounded copy or a mark read from bytes
#   that were not hashed. A hard-linked worktree file (nlink > 1) is NOT refused: the decision rests on the snapshot bytes
#   equalling the index sha, which another link cannot change after the read; refusing it would add false refusals and no
#   safety. The refusal reason is named on stderr (reason=...). Every level's directory is PINNED once (see PINNING below):
#   no later call of that level re-resolves its path, its `.git` file or its git dir by name (review follow-ups r3, H1).
#   Every git call and the reader run under `timeout --foreground` (60 s, _CM_TP_GIT_TIMEOUT): a timed-out call is a
#   failed call, and every failure means scan more. Snapshots live in one mktemp -d directory per call (mode 0700, an
#   unpredictable name: two concurrent calls never share it), removed on exit and on HUP/INT/TERM/QUIT (a SIGKILL or another
#   core-dump signal can still leave one `tp_manifest.*` directory behind; stated, not preventable). The API runs in its own
#   subshell: a direct caller's traps and cwd are not touched.
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
# PINNING (review 11.4.276 follow-ups r3, H1; class "a path string resolved more than once during one prune decision"):
# every level (the gate root's repository and each nested repository) runs in its own subshell whose cwd IS that level's
# directory: entered once with `cd -P`, then (before any git call) `pwd -P` and git's --show-toplevel must both equal the
# expected canonical path. Its git dir is opened ONCE, through a path relative to that cwd, as a directory fd, and every
# later git call uses --git-dir=<that fd> --work-tree=. ; the reader opens "." and walks down with O_NOFOLLOW; the snapshot
# is an UNLINKED file read through its fd. So no later call re-resolves the level's path, its `.git` file or its git dir by
# name: a swap of the directory (symlink, rename, A-B-A) after the pin cannot redirect any call. The level's result is used
# only when, after the decision, the expected path is still not a symlink and still names the pinned directory (`-ef`);
# otherwise it is dropped with a note (scan more). A NESTED level is also accepted only when it is the checkout git made for
# the parent's gitlink (_cm_tp_pin_gitlink): when the parent's git dir holds a module git dir for the gitlink (found by the
# submodule NAME its index / HEAD .gitmodules records, or by the path), the level's git dir must BE that module dir (-ef
# through the fds); only when no module dir exists (the embedded layout) is HEAD == the recorded commit accepted instead.
# So a foreign directory renamed into the path and held there for the whole decision is refused in the absorbed layout
# whatever commit it sits at (r4 K1). The root's post-decision identity check is a consistency refusal, not a safety
# property: the root is the caller's own input and the caller's later use of the path has the same window anyway.
# Stated limits: the gate ROOT itself has no parent record (a directory held at the root path for the whole decision is
# the root); in the EMBEDDED layout (no module git dir) a foreign repository at the RECORDED commit with its own .git held
# at the path for the whole decision is the level (its git dir really lives in the worktree, so it is indistinguishable);
# a nested repository whose git dir is the module dir but whose worktree is a foreign directory reads that git dir's index
# and blobs, so its decision equals the real checkout's; a write inside the parent's git dir (which holds the module dirs
# and the index .gitmodules) is outside the threat model (the custody design trusts the git dir); a same-uid process that
# writes this call's own private temp files or reaches them through /proc/<pid>/fd has process-level control (it could
# equally ptrace this process) and is out of scope; a directory fd needs /proc/self/fd or /dev/fd (absent: every level is
# refused with a note naming that cause, literal names only, scan more).
_CM_TP_GIT_TIMEOUT=60                                  # seconds per git / reader call; tests may lower it after sourcing
_CM_TP_MAX_MANIFEST=1048576                            # bytes; a larger worktree manifest is refused, never copied
_CM_TP_TIMEOUT="$(command -v timeout 2>/dev/null)" || _CM_TP_TIMEOUT=""
_CM_TP_SNAPDIR=""                                      # set per call by _cm_tp_run (private mktemp -d); empty = no marks read
_CM_TP_FD=""                                           # /proc/self/fd or /dev/fd (a path to an open fd); empty = none
if [ -d /proc/self/fd ]; then _CM_TP_FD=/proc/self/fd; elif [ -d /dev/fd ]; then _CM_TP_FD=/dev/fd; fi
_CM_TP_HERE=""                                         # canonical path of the pinned level (its cwd)
_CM_TP_GD=""                                           # the pinned level's git dir, as $_CM_TP_FD/<fd>
_CM_TP_RFD=""                                          # read fd of the current (unlinked) snapshot
_cm_tp_git() {
    local to=(); [ -n "$_CM_TP_TIMEOUT" ] && to=("$_CM_TP_TIMEOUT" --foreground -k 5 "$_CM_TP_GIT_TIMEOUT")
    env -i PATH="${PATH:-/usr/bin:/bin}" LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 "${to[@]}" git -c core.fsmonitor=false "$@"
}
# _cm_tp_gitp <args> : git on the PINNED level: the pinned git dir fd, the cwd as the work tree
_cm_tp_gitp() { [ -n "$_CM_TP_GD" ] || return 1; _cm_tp_git --git-dir="$_CM_TP_GD" --work-tree=. "$@"; }

# _cm_tp_relfrom <from-dir> <target> : a path to <target> that starts at <from-dir> and goes up with `..` only to the
# longest common directory (both absolute, canonical)
_cm_tp_relfrom() {
    local f="$1" t="$2" up="./"
    while [ "$f" != / ] && [ "$t" != "$f" ] && [[ "$t" != "$f"/* ]]; do
        f="${f%/*}"; [ -n "$f" ] || f=/; up="$up../"
    done
    if [ "$t" = "$f" ]; then printf '%s' "$up"
    elif [ "$f" = / ]; then printf '%s%s' "$up" "${t#/}"
    else printf '%s%s' "$up" "${t#"$f"/}"; fi
}

# _cm_tp_pin_here <expected canonical path> : the cwd was just entered with cd -P. Pins it as a level, or returns non-zero
# (not a repository top, entered through a symlink, moved, an odd path): pwd -P BEFORE any git call, git's toplevel, the
# git dir opened once as an fd through a cwd-relative path. The fd is what protects: opened relative to the pinned cwd it
# names the git dir git found from that cwd. The later `-ef` against git's absolute answer is a consistency refusal only
# (equivalent for safety, r4 RF): a swap makes both names resolve alike, so it can only add refusals.
_cm_tp_pin_here() {
    local exp="$1" out t gd g
    case "$exp" in /*) ;; *) return 1 ;; esac
    case "$exp" in *$'\n'*) return 1 ;; esac
    [ -n "$_CM_TP_FD" ] || return 1
    [ "$(pwd -P 2>/dev/null)" = "$exp" ] || return 1
    out="$(_cm_tp_git rev-parse --show-toplevel --absolute-git-dir 2>/dev/null)" || return 1
    t="${out%%$'\n'*}"; gd="${out#*$'\n'}"
    [ "$t" = "$exp" ] || return 1
    [ "$gd" != "$out" ] || return 1
    case "$gd" in *$'\n'*) return 1 ;; /*) ;; *) return 1 ;; esac
    { exec {g}<"$(_cm_tp_relfrom "$exp" "$gd")"; } 2>/dev/null || return 1
    [ -d "$_CM_TP_FD/$g" ] && [ "$_CM_TP_FD/$g" -ef "$gd" ] || { exec {g}<&-; return 1; }
    _CM_TP_GD="$_CM_TP_FD/$g"; _CM_TP_HERE="$exp"
}

# _cm_tp_pin <path from the pinned cwd> : enter a nested level (run it in a subshell)
_cm_tp_pin() {
    local rel="$1" here
    case "$rel" in ''|/*|*$'\n'*|.|..|../*|*/..|*/../*) return 1 ;; esac
    here="$(pwd -P 2>/dev/null)" || return 1
    cd -P -- "./$rel" 2>/dev/null || return 1
    _cm_tp_pin_here "$here/$rel"
}

# _cm_tp_modnames <path> : the submodule NAMES the PINNED level's own records give the gitlink <path>: the .gitmodules
# blob of its INDEX and of its HEAD, read from the pinned git dir (never the worktree .gitmodules, which a worktree-only
# actor can edit). One name per line; a name that could leave modules/ (empty, absolute, a `.`/`..` segment, a newline)
# is dropped.
_cm_tp_modnames() {
    local p="$1" src rec key val name
    for src in ':.gitmodules' 'HEAD:.gitmodules'; do
        while IFS= read -r -d '' rec; do
            key="${rec%%$'\n'*}"; val="${rec#*$'\n'}"
            [ "$val" = "$p" ] || continue
            name="${key#submodule.}"; name="${name%.path}"
            case "/$name/" in //|*/./*|*/../*|*//*) continue ;; esac
            case "$name" in /*|*$'\n'*) continue ;; esac
            printf '%s\n' "$name"
        done < <(_cm_tp_gitp config --blob "$src" --null --get-regexp '^submodule\..*\.path$' 2>/dev/null)
    done
}

# _cm_tp_pin_gitlink <path from the pinned cwd> <recorded commit> : enter a nested level that git itself checked out for
# that gitlink (review 11.4.276 follow-ups r4, K1; class "a foreign directory made to look like the recorded checkout").
# MODULE RULE: the parent's pinned git dir is asked, before the pin, for the module git dirs of this gitlink:
# modules/<name> for each name its index / HEAD .gitmodules records for the path, and modules/<path>. When ANY of them
# exists, the level's git dir MUST be (-ef, through the pinned fds) modules/<name> for a recorded name -- or modules/<path>
# when no name is recorded -- and anything else is refused, at whatever commit it sits. That is the layout git itself
# makes (`git submodule add` / `update` absorb the git dir into the parent), and a worktree-only actor cannot create or
# move a module git dir, so a foreign clone, a `.git` file aimed elsewhere, a symlinked or `commondir`-style `.git`, or a
# `.git` file aimed at ANOTHER submodule's module dir is refused even when it sits at the recorded commit and occupies the
# path for the whole decision. HEAD RULE, only when no module git dir exists (the embedded layout): HEAD must be the
# commit the parent records. Stated limit: in an embedded layout a foreign repository at the recorded commit held at the
# path for the whole decision is the level (its git dir really is in the worktree, so it is indistinguishable).
_cm_tp_pin_gitlink() {
    local pgd="$_CM_TP_GD" rel="$1" sha="$2" h names nm acc=() trig=0 c
    names="$(_cm_tp_modnames "$rel")"
    if [ -n "$names" ]; then
        while IFS= read -r nm; do acc+=("$pgd/modules/$nm"); done <<<"$names"
    else acc=("$pgd/modules/$rel"); fi
    for c in "${acc[@]}" "$pgd/modules/$rel"; do [ -n "$pgd" ] && [ -d "$c" ] && trig=1; done
    _cm_tp_pin "$rel" || return 1
    if [ "$trig" = 1 ]; then
        for c in "${acc[@]}"; do [ -d "$c" ] && [ "$_CM_TP_GD" -ef "$c" ] && return 0; done
        return 1
    fi
    h="$(_cm_tp_gitp rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" || return 1
    case "$sha" in ''|*[!0-9a-f]*) return 1 ;; esac
    [ "$h" = "$sha" ]
}

# _cm_tp_still_here : after a decision, the expected path still names the pinned directory (no symlink on the way)
_cm_tp_still_here() {
    [ -n "$_CM_TP_HERE" ] && [ ! -L "$_CM_TP_HERE" ] && [ "$_CM_TP_HERE" -ef . ] &&
        [ "$(cd -P -- "$_CM_TP_HERE" 2>/dev/null && pwd -P)" = "$_CM_TP_HERE" ]
}

# The bounded reader (G1). argv: <top> <relative path> <out fd> <cap>. Exit 0 = the bytes were written to <out fd>;
# 2 usage, 3 not a regular file, 4 executable, 5 larger than cap, 6 grew past cap while read, 7 open/walk failed (a
# symlinked component, missing, not a directory), 8 read error, 9 write error. Nothing is written unless it exits 0.
IFS= read -r -d '' _CM_TP_READ_PY <<'PY' || :
import os, stat, sys
def main(a):
    if len(a) != 4:
        return 2
    top, rel, outfd, cap = a
    try:
        cap = int(cap)
        outfd = int(outfd)
    except ValueError:
        return 2
    segs = rel.split("/")
    if cap < 0 or outfd < 0 or any(s in ("", ".", "..") for s in segs):
        return 2
    fl = os.O_RDONLY | os.O_CLOEXEC
    try:
        d = os.open(top, fl | os.O_DIRECTORY | os.O_NOFOLLOW)
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
        v = memoryview(buf)
        while v:
            v = v[os.write(outfd, v):]
    except OSError:
        return 9
    return 0
sys.exit(main(sys.argv[1:]))
PY

# _cm_tp_bounded <path-from-the-pinned-cwd> <out fd> : runs the bounded reader on ".", time bounded; its exit status
_cm_tp_bounded() {
    local to=(); [ -n "$_CM_TP_TIMEOUT" ] && to=("$_CM_TP_TIMEOUT" --foreground -k 5 "$_CM_TP_GIT_TIMEOUT")
    command -v python3 >/dev/null 2>&1 || return 10
    env -i PATH="${PATH:-/usr/bin:/bin}" LC_ALL=C "${to[@]}" python3 -I -B -c "$_CM_TP_READ_PY" . "$1" "$2" "$_CM_TP_MAX_MANIFEST" 2>/dev/null
}

# _cm_tp_why <rc> : the name of a reader refusal
_cm_tp_why() {
    case "$1" in
        3) echo notreg ;; 4) echo exec ;; 5) echo toolarge ;; 6) echo grew ;; 7) echo open ;; 8) echo read ;; 9) echo write ;;
        10) echo nopython ;; 124|137) echo timeout ;; *) echo "error$1" ;;
    esac
}

# _cm_tp_snap <path-from-the-pinned-cwd> : ONE bounded read of the worktree file into a private snapshot that has NO name
# (created by mktemp in the 0700 snapshot dir, opened for write and read, unlinked BEFORE the bytes are written).
# Sets _CM_TP_RFD (read it as $_CM_TP_FD/$_CM_TP_RFD; close with _cm_tp_snap_close) or returns non-zero (_CM_TP_WHY).
_cm_tp_snap() {
    local f w r rc
    _CM_TP_RFD=""; _CM_TP_WHY=tempfile
    [ -n "$_CM_TP_SNAPDIR" ] && [ -n "$_CM_TP_FD" ] || return 1
    f="$(mktemp "${_CM_TP_SNAPDIR:?}/m.XXXXXX" 2>/dev/null)" || return 1
    { exec {w}>"$f"; } 2>/dev/null || { rm -f -- "${f:?}"; return 1; }
    { exec {r}<"$f"; } 2>/dev/null || { exec {w}>&-; rm -f -- "${f:?}"; return 1; }
    rm -f -- "${f:?}"
    _cm_tp_bounded "$1" "$w"; rc=$?
    exec {w}>&-
    if [ "$rc" -ne 0 ]; then exec {r}<&-; _CM_TP_WHY="$(_cm_tp_why "$rc")"; return 1; fi
    _CM_TP_RFD="$r"
}
_cm_tp_snap_close() { if [ -n "$_CM_TP_RFD" ]; then exec {_CM_TP_RFD}<&-; fi; _CM_TP_RFD=""; }

# cm_tp_is_gitlink <path-from-top> : exact gitlink (mode 160000, path field identical) of the pinned level
cm_tp_is_gitlink() {
    local rec mode path
    case "$1" in ''|/*|*$'\n'*) return 1 ;; esac
    while IFS= read -r -d '' rec; do
        mode="${rec%% *}"; path="${rec#*$'\t'}"
        [ "$mode" = 160000 ] && [ "$path" = "$1" ] && return 0
    done < <(_cm_tp_gitp -c core.quotePath=false ls-files -s -z --full-name -- ":(literal)$1" 2>/dev/null)
    return 1
}

# cm_tp_ambiguous <path-from-top> : 0 iff the pinned level's .gitmodules cannot vouch for a single entry of <path>:
# unreadable / non-regular / symlinked or unparseable file, the path listed more than once, its name carrying several
# paths or several urls. The file is read ONCE (bounded, unlinked snapshot); git config parses that snapshot.
cm_tp_ambiguous() {
    local p="$1" gm fd rc
    [ -e .gitmodules ] || [ -L .gitmodules ] || return 1
    _cm_tp_snap .gitmodules || return 0
    fd="$_CM_TP_RFD"; _CM_TP_RFD=""; gm="$_CM_TP_FD/$fd"
    _cm_tp_ambiguous_in "$gm" "$p"; rc=$?
    exec {fd}<&-
    return "$rc"
}
_cm_tp_ambiguous_in() { # $1=.gitmodules snapshot $2=path
    local gm="$1" p="$2" rec key val name="" n=0 np=0 nu=0
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

# cm_tp_gitlink_sha <path-from-top> : the commit the pinned level records for the ONE exact stage-0 gitlink <path>
cm_tp_gitlink_sha() {
    local rec meta mode sha="" stage n=0
    case "$1" in ''|/*|*$'\n'*) return 1 ;; esac
    while IFS= read -r -d '' rec; do
        meta="${rec%%$'\t'*}"; [ "${rec#*$'\t'}" = "$1" ] || continue
        n=$((n+1)); read -r mode sha stage <<<"$meta"
        [ "$mode" = 160000 ] && [ "$stage" = 0 ] || return 1
    done < <(_cm_tp_gitp -c core.quotePath=false ls-files -s -z --full-name -- ":(literal)$1" 2>/dev/null)
    [ "$n" -eq 1 ] || return 1
    case "$sha" in ''|*[!0-9a-f]*) return 1 ;; esac
    printf '%s' "$sha"
}

# cm_tp_recorded <path> : an exact, unambiguous gitlink of the pinned level
cm_tp_recorded() { cm_tp_is_gitlink "$1" && ! cm_tp_ambiguous "$1"; }

# cm_tp_no_symlink <base> <rel> : no component of base/rel is a symlink
cm_tp_no_symlink() {
    local cur="$1" rest="$2" seg
    while [ -n "$rest" ]; do
        seg="${rest%%/*}"; case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
        cur="$cur/$seg"; [ ! -L "$cur" ] || return 1
    done
    return 0
}

# cm_tp_gitlink_deep <path> <depth> : is <path> a recorded gitlink of the pinned level, or of a POPULATED recorded gitlink
# parent's own repository (a root manifest may name submodules/a/submodules/b)? Each parent is pinned in a subshell.
cm_tp_gitlink_deep() {
    local p="$1" depth="$2" pre="" rest seg sha
    cm_tp_recorded "$p" && return 0
    [ "$depth" -lt 3 ] || return 1
    rest="$p"
    while [[ "$rest" == */* ]]; do
        seg="${rest%%/*}"; rest="${rest#*/}"; pre="${pre:+$pre/}$seg"
        cm_tp_recorded "$pre" || continue
        sha="$(cm_tp_gitlink_sha "$pre")" || return 1
        ( _cm_tp_pin_gitlink "$pre" "$sha" && cm_tp_gitlink_deep "$rest" $((depth+1)) && _cm_tp_still_here ); return $?
    done
    return 1
}

# cm_tp_manifest_entry <path-from-top> : prints the blob sha of the ONE index record for exactly that path
# (literal pathspec, byte-exact path, stage 0, mode 100644); non-zero otherwise (untracked, unmerged, symlink, 100755).
cm_tp_manifest_entry() {
    local rec meta mode sha="" stage rp n=0
    while IFS= read -r -d '' rec; do
        rp="${rec#*$'\t'}"; meta="${rec%%$'\t'*}"
        [ "$rp" = "$1" ] || continue
        n=$((n+1)); read -r mode sha stage <<<"$meta"
        [ "$mode" = 100644 ] || return 1
        [ "$stage" = 0 ] || return 1
    done < <(_cm_tp_gitp -c core.quotePath=false ls-files -s -z --full-name -- ":(literal)$1" 2>/dev/null)
    [ "$n" -eq 1 ] || return 1
    case "$sha" in ''|*[!0-9a-f]*) return 1 ;; esac
    printf '%s' "$sha"
}

# cm_tp_manifest_recorded <path-from-top> : on success the manifest bytes the INDEX records are in the unlinked snapshot
# $_CM_TP_FD/$_CM_TP_RFD (the caller parses it and closes it); non-zero otherwise (then no mark is read; the reason is left
# in _CM_TP_WHY). ONE bounded open takes the snapshot: a regular, non-executable file of at most 1 MiB reached through no
# symlinked component. The snapshot is accepted only when its `hash-object --no-filters` equals the index entry's sha
# (cm_tp_manifest_entry). The object store is never read; the worktree path is opened once.
cm_tp_manifest_recorded() {
    local p="$1" sha got
    _CM_TP_WHY=entry
    sha="$(cm_tp_manifest_entry "$p")" || return 1
    _cm_tp_snap "$p" || return 1
    _CM_TP_WHY=hash
    got="$(_cm_tp_gitp hash-object --no-filters --stdin < "$_CM_TP_FD/$_CM_TP_RFD" 2>/dev/null)" || { _cm_tp_snap_close; return 1; }
    _CM_TP_WHY=differs
    [ "$got" = "$sha" ] || { _cm_tp_snap_close; return 1; }
}

# cm_tp_level <prefix> <outpre> <depth> : cwd = the pinned repository top. Emits (relative to the gate root) every
# manifest-marked recorded gitlink under <prefix>; populated unmarked gitlinks are descended (each in its own pin).
cm_tp_level() {
    local prefix="$1" outpre="$2" depth="$3"
    local base="."; [ -n "$prefix" ] && base="$prefix"
    local -A tp=() emitted=()
    local rec g rel recs rc n path u r2 tpf pp sub mf="${prefix:+$prefix/}helix-deps.yaml"

    if [ -e "$mf" ] || [ -L "$mf" ]; then
        if ! cm_tp_manifest_recorded "$mf"; then
            echo "third_party_prune: manifest $_CM_TP_HERE/$mf is not the recorded copy (one stage-0 mode-100644 index entry whose bytes equal the regular, non-executable, non-symlink worktree file of at most 1 MiB; reason=${_CM_TP_WHY:-unknown}); manifest marks ignored" >&2
        else
            recs="$(cm_hdeps_tsv "$_CM_TP_FD/$_CM_TP_RFD")"; rc=$?
            _cm_tp_snap_close
            if [ "$rc" != 0 ]; then
                echo "third_party_prune: manifest $_CM_TP_HERE/$mf not usable (recorded-copy reader rc=$rc); manifest marks ignored" >&2
            else
                while IFS=$'\x1f' read -r n path u r2 tpf; do
                    [ "$tpf" = 1 ] || continue
                    [ -n "$path$n" ] || continue
                    pp="${path:-submodules/$n}"; pp="${pp%/}"
                    cm_third_party_prune_ok "$pp" || continue
                    cm_tp_no_symlink "$base" "$pp" || continue
                    if cm_tp_gitlink_deep "${prefix:+$prefix/}$pp" "$depth"; then tp["$pp"]=1
                    else echo "third_party_prune: manifest marks $outpre${outpre:+/}$pp third_party but it is not an unambiguous recorded gitlink; NOT pruned (scanning it)" >&2; fi
                done <<<"$recs"
            fi
        fi
    fi

    # the gitlinks recorded under the scan base: marked -> emitted; populated -> descended (pinned, see _cm_tp_descend)
    while IFS= read -r -d '' rec; do
        [ "${rec%% *}" = 160000 ] || continue
        g="${rec#*$'\t'}"
        case "$g" in *$'\n'*) continue ;; esac
        if [ -n "$prefix" ]; then case "$g" in "$prefix"/*) rel="${g#"$prefix"/}" ;; *) continue ;; esac; else rel="$g"; fi
        cm_third_party_prune_ok "$rel" || continue
        if [ -n "${tp[$rel]:-}" ]; then
            cm_tp_no_symlink "$base" "$rel" || continue
            emitted["$rel"]=1; printf '%s\n' "${outpre:+$outpre/}$rel"; continue
        fi
        [ "$depth" -lt 3 ] || continue
        g="${rec#160000 }"; g="${g%% *}"
        sub="$(_cm_tp_descend "${prefix:+$prefix/}$rel" "${outpre:+$outpre/}$rel" $((depth+1)) "$g")"
        [ -n "$sub" ] && printf '%s\n' "$sub"
    done < <(_cm_tp_gitp -c core.quotePath=false ls-files -s -z --full-name 2>/dev/null)
    # manifest marks that are deep (not direct gitlinks of this level) are emitted too
    for rel in "${!tp[@]}"; do
        [ -n "${emitted[$rel]:-}" ] || printf '%s\n' "${outpre:+$outpre/}$rel"
    done
}

# _cm_tp_descend <path from the pinned cwd> <outpre> <depth> <recorded commit> : run in a command substitution. Pins the
# nested level (_cm_tp_pin_gitlink) and
# prints its result only when the path still names the pinned directory afterwards. A path that is not a populated
# repository top (unpopulated gitlink, symlink, moved) is silently not descended.
_cm_tp_descend() {
    local r
    _cm_tp_pin_gitlink "$1" "$4" || return 0
    r="$(cm_tp_level "" "$2" "$3")"
    if _cm_tp_still_here; then [ -n "$r" ] && printf '%s\n' "$r"
    else echo "third_party_prune: $2 changed during the decision; its marks are ignored (scanning it)" >&2; fi
    return 0
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

# _cm_tp_run <top> <prefix> : run in a subshell (the caller's traps and cwd stay untouched). One private snapshot
# directory (mktemp -d: mode 0700, unpredictable name, absolute), removed by the EXIT trap, which bash also runs when the
# subshell is killed by HUP/INT/TERM (measured); QUIT is trapped to exit so the EXIT trap runs too (measured r3: an
# untrapped QUIT left one directory). SIGKILL and the other core-dump signals (ABRT, SEGV, BUS, ...) can still leave one
# `tp_manifest.*` directory behind (stated, not preventable). Then the repository top is pinned (cwd) and walked.
_cm_tp_run() {
    _CM_TP_SNAPDIR="$(mktemp -d "${TMPDIR:-/tmp}/tp_manifest.XXXXXX" 2>/dev/null)" || _CM_TP_SNAPDIR=""
    if [ -n "$_CM_TP_SNAPDIR" ]; then
        _CM_TP_SNAPDIR="$(cd -P -- "$_CM_TP_SNAPDIR" 2>/dev/null && pwd -P)" || _CM_TP_SNAPDIR=""
    fi
    if [ -n "$_CM_TP_SNAPDIR" ]; then
        trap 'rm -rf -- "${_CM_TP_SNAPDIR:?}"' EXIT   # bash also runs it on HUP/INT/TERM (measured, bash 5.3)
        trap 'exit 131' QUIT
    else
        echo "third_party_prune: no private temp directory; manifest marks ignored (scanning more)" >&2
    fi
    if [ -z "$_CM_TP_FD" ]; then
        echo "third_party_prune: no /proc/self/fd or /dev/fd (a directory fd is needed to pin a level); pruning literal directory names only (scanning more)" >&2
        return 0
    fi
    if ! { cd -P -- "$1" 2>/dev/null && _cm_tp_pin_here "$1"; }; then
        echo "third_party_prune: $1 could not be pinned (moved, a symlink, or not the repository top); pruning literal directory names only (scanning more)" >&2
        return 0
    fi
    local res; res="$(cm_tp_level "$2" "" 0 | LC_ALL=C sort -u)"
    if _cm_tp_still_here; then [ -n "$res" ] && printf '%s\n' "$res"
    else echo "third_party_prune: $1 changed during the decision; manifest marks ignored (scanning more)" >&2; fi
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
