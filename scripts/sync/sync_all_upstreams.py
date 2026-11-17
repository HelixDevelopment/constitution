#!/usr/bin/env python3
"""sync_all_upstreams.py -- engine of scripts/sync/sync_all_upstreams.sh (run with python3 -I).

Fetches every remote of a project and of every initialised submodule at every depth, reports
ahead / behind / diverged / unreachable state and the pin state of every submodule, and (only with
--apply) integrates by FAST-FORWARD. Full documentation: docs/manuals/sync_upstreams_manual.md.

Safety (Constitution §11.4.113, §9.2, §11.4.84, §11.4.10, §11.4.201, §11.4.263, §12):
  * ONE spawn point. proc_run_git() is the only code that starts a process and proc_kill_group() the only
    code that sends a signal (to the call's own process group, pgid > 1). proc_run_git() passes every
    argument list through check_git_args() and builds the command line only with git_argv(); the gate
    CM-SYNC-UPSTREAMS-FF-ONLY proves from the AST that no other spawn or signal exists in any spelling.
  * Every git call is a TYPED answer (GitResult). Each call site declares up front the exit statuses
    that are an answer for that command (``ok=``, e.g. (0, 1) for `rev-parse --verify -q`, where 1 means
    "no such object"), and, where the output has a fixed shape, the shape (``want=``). Anything else --
    a signal, a timeout, the run deadline, an exit status outside the declared set (128 included where it
    is not declared), a refused or unrunnable call, output of the wrong shape -- is NO ANSWER: it is
    recorded for that repository, nothing about the repository is concluded, it is never changed, and
    the run verdict is BLIND (exit 6; INCONCLUSIVE, exit 5, when the only missing answers ran out of
    time). It is never read as "nothing there", "clean" or "current".
  * ONE guarded writer. write_git() is the only code that runs a write (merge --ff-only, checkout
    --detach, add --). Before every write it re-reads the tree status (it must answer and be clean),
    re-checks for an operation in progress, and checks that no ignored file would be overwritten; before
    staging a gitlink it checks that the parent's index still records the gitlink the run discovered.
  * Fetch is engine-owned: an explicit refspec into refs/remotes/<remote>/* only, --refmap=,
    --no-prune --no-prune-tags --no-tags --no-auto-gc. A fetch never creates, moves or deletes a local
    branch or tag (tags only with --tags, and then only new ones, never forced).
  * Every git call runs with SAFE_CONFIG (core.hooksPath=/dev/null, core.fsmonitor=false, ...), so no
    hook, fsmonitor or auto-maintenance runs, whatever the repository's own config says.
  * URLs are logged without userinfo (everything between scheme:// and the LAST '@' of the URL token),
    token shapes are replaced, git stderr is redacted, and the whole report passes the same redaction
    again before it is written; no terminal prompt and no askpass program (a configured credential.helper runs).
  * Honest boundary: a clean/smudge filter or diff driver the USER configured still runs when git writes
    or compares files (status runs the clean filter of a modified file; a checkout or fast-forward runs
    the smudge filter). The engine does not disable filters: that would break LFS-style repositories.
"""
import argparse
import concurrent.futures
import datetime
import errno
import fcntl
import hashlib
import json
import os
import re
import select
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)

SCHEMA = "helix.sync_upstreams/1"
EXIT_OK, EXIT_FAIL, EXIT_USAGE, EXIT_BEHIND, EXIT_ATTENTION = 0, 1, 2, 3, 4
EXIT_INCONCLUSIVE, EXIT_BLIND, EXIT_LOCKED, EXIT_INTERRUPTED = 5, 6, 7, 8
DEFAULT_OWN_ORGS = ("vasic-digital", "HelixDevelopment")
SHA_RE = re.compile(r"^[0-9a-f]{40}([0-9a-f]{24})?$")
DIGITS_RE = re.compile(r"^[0-9]+$")
TWO_COUNTS_RE = re.compile(r"^[0-9]+\s+[0-9]+$")
TWO_ABS_PATHS_RE = re.compile(r"^/[^\n]*\n/[^\n]*$")
THREE_ABS_PATHS_RE = re.compile(r"^/[^\n]*\n/[^\n]*\n/[^\n]*$")
ABS_PATH_RE = re.compile(r"^/[^\n]*$")
REMOTE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$")
BRANCH_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$")
HEADS = "refs/heads/"
# ONE form for every object name the engine gives git (review round 12, the ref-resolution class): an object id
# followed by ^{commit}. git never reads a REF NAME out of '<hex>^{commit}' ('^' cannot be in a ref name), so no
# lookup rule can turn it into a tag or a branch; a bare id is NOT enough: 'git checkout --detach <hex>' takes a
# local branch named <hex> before the object (measured, git 2.53). The other exact names are the literal HEAD forms.
# A ref name is resolved to an id ONLY by resolve_ref_exact() (for-each-ref, exact refname match): 'rev-parse
# refs/remotes/<r>/<b>' falls back to refs/tags/<name> and refs/heads/<name> when the exact ref is absent (RV11-1).
EXACT_OBJ_RE = re.compile(r"^[0-9a-f]{40}([0-9a-f]{24})?\^\{commit\}$")
INVALID_OBJ = "<not-an-object-id>"  # what obj() gives for anything that is not an id: check_git_args refuses it
# the fields of the exact lookup, NUL-separated: refname, symref target, type, id, peeled type, peeled id (one line
# per ref). Review round 13 (RV12-1): %(symref) is read in the SAME line as the id. A symbolic ref at the exact name
# (refs/remotes/<r>/<b> -> refs/heads/x, or -> a tag) has that refname, and its %(objectname) is its TARGET's; so a
# line whose symref field is not empty is never an upstream answer (resolve_ref_exact reports it 'symbolic').
FER_EXACT_FORMAT = "%(refname)%00%(symref)%00%(objecttype)%00%(objectname)%00%(*objecttype)%00%(*objectname)"
# the fields of the pin's ancestry lookup ('for-each-ref --contains'), NUL-separated: refname, symref target. A
# symbolic line names its TARGET's history under its own name (raw git 2.53: a local-only commit is "contained in"
# a symbolic refs/remotes/origin/main pointing at a local branch); evaluate_pin drops every symbolic line.
FER_CONTAINS_FORMAT = "%(refname)%00%(symref)"
# Characters git never allows in a ref name (git check-ref-format, rule 4 and 5): ASCII control characters, space,
# ~ ^ : ? * [ and backslash. Used by valid_branch_name() for a name read from git and for --branch (review round 11).
_REF_BAD_CHARS = re.compile(r"[\x00-\x20\x7f~^:?*\[\\]")
# Why a call gave no answer. Only these two mean "time ran out" (verdict INCONCLUSIVE); every other reason
# (signal:N, rc:N, refused, not-runnable, malformed-output) is a call that answered nothing (verdict BLIND).
TIME_WHYS = ("timeout", "deadline")
# A call refused or stopped because the run was asked to stop (SIGINT / SIGTERM / SIGHUP): neither BLIND nor
# INCONCLUSIVE; the run verdict is INTERRUPTED (exit 8).
STOP_WHYS = ("interrupted",)
# What one git call may hold in memory: stdout up to OUT_CAP (more is no answer, "output-too-large"); stderr only
# its last ERR_TAIL bytes (an earlier part is dropped, and with it the partial first line of the tail, so a URL is
# never kept without its scheme). Everything the engine redacts is therefore bounded.
OUT_CAP = 128 * 1024 * 1024
ERR_TAIL = 64 * 1024
FETCH_HEAD_CAP = 64 * 1024 * 1024
# Set by the stop-signal handler (on_stop_signal): the first signal stops every interruptible git call and refuses
# every new one except the final reads; a second signal stops the final reads too. A stop signal never ends a
# write in flight; a write is ended only by its own limit, --write-timeout (review round 6, RV5-1).
STOP_REQUESTED = threading.Event()
HARD_STOP = threading.Event()
# How a call that must end is ended (review round 6, RV5-1): SIGTERM to its process group first (git removes its own
# lock files on SIGTERM, measured: docs/qa/sync_upstreams_2026_11_14_r6/), SIGKILL only when the call has not ended
# after the grace period. A write gets the longer grace.
KILL_GRACE = 5
WRITE_KILL_GRACE = 30
# The write-in-progress marker (review round 6, RV5-1): written in the git dir BEFORE each write starts, removed when
# git has ended the write with a declared status. A marker found later means a write of an earlier run did not end
# normally (its limit, SIGKILL, OOM, power loss): what that repository shows is attributed to that write.
WRITE_MARKER = "helix-sync-upstreams.write-in-progress"
# The marker's life is a STATE MACHINE per git dir, for the run (review round 8, RV7-1): keyed by the git dir's
# real path, moved only by gd_move() along GD_MOVES. A git dir in an UNRESOLVED state never receives another write
# in this run, and a marker that is already there is never overwritten (O_EXCL) nor removed by a write that did not
# create it. A write git can only start holding a WriteToken whose marker is on disk NOW (Runner.run checks it).
GD_NONE = "none"                    # nothing known: no marker found, none written yet
GD_EARLIER = "earlier-run-marker"   # inspection found a marker of an earlier run and kept it (its leftovers)
GD_WRITING = "write-in-progress"    # this run created the marker; its write has not ended
GD_KILLED = "write-killed"          # the write's own limit ended it: the marker stays
GD_INTERRUPTED = "write-interrupted"  # a started git did not end with a declared status: the marker stays
GD_CLEARED = "cleared"              # the write ended (git answered, or no git started), or an earlier marker that
#                                     left nothing was removed in --apply: no marker
GD_UNRESOLVED = (GD_EARLIER, GD_WRITING, GD_KILLED, GD_INTERRUPTED)
GD_MOVES = {GD_NONE: (GD_WRITING, GD_EARLIER, GD_CLEARED), GD_CLEARED: (GD_WRITING,),
            GD_WRITING: (GD_CLEARED, GD_KILLED, GD_INTERRUPTED), GD_EARLIER: (), GD_KILLED: (), GD_INTERRUPTED: ()}
MARKER_WRITTEN, MARKER_EXISTS, MARKER_UNWRITABLE = "written", "exists", "unwritable"
TOKEN_REFUSALS = ("no-write-token", "write-token-stale", "write-marker-not-ours")
# Lock files a killed write may leave (checked and listed in the report, never removed by the engine)
# The lock files git itself takes for each engine write (review round 9, RV8-1; ground truth: git 2.53, strace of
# each write, plus a stale-lock matrix, docs/qa/sync_upstreams_2026_11_15_r9/ground_truth/). GITDIR_LOCKS are in the
# write's own git dir (per worktree), COMMON_LOCKS in the git common dir ("{branch}" = the checked-out branch). A
# STALE one of these makes git refuse, or (HEAD.lock, the branch ref lock) rewrite the index and work tree first and
# THEN fail: a half-applied write. Every one is checked before every write, and before an earlier marker is cleared.
OP_GIT = {"fast-forward": "merge", "advance-pin": "checkout", "follow-pin": "checkout", "stage-pin": "add"}
GITDIR_LOCKS = {"merge": ("index.lock", "HEAD.lock", "ORIG_HEAD.lock", "AUTO_MERGE.lock"),
                "checkout": ("index.lock", "HEAD.lock", "AUTO_MERGE.lock"),
                "add": ("index.lock",)}
COMMON_LOCKS = {"merge": ("packed-refs.lock", "refs/heads/{branch}.lock", "reftable/tables.list.lock"),
                "checkout": ("packed-refs.lock", "reftable/tables.list.lock"),
                "add": ()}
WRITE_LOCKS = tuple(sorted({n for v in GITDIR_LOCKS.values() for n in v}))  # every git-dir lock of any write

# -c pairs on EVERY git call: whatever the repository's own (or the user's) config says, no hook,
# fsmonitor, auto-gc/maintenance, submodule recursion, autostash, ext:: transport, prune or askpass program runs
# (a -c pair beats every config file; it does NOT beat GIT_ALLOW_PROTOCOL or GIT_ASKPASS in the environment, which
# is why git_env() drops the first and sets the second empty: ground truth, docs/qa/sync_upstreams_2026_11_13_r5/).
SAFE_CONFIG = ("core.hooksPath=/dev/null", "core.fsmonitor=false", "submodule.recurse=false",
               "gc.auto=0", "maintenance.auto=false", "merge.autoStash=false", "protocol.ext.allow=never",
               "fetch.prune=false", "fetch.pruneTags=false", "fetch.recurseSubmodules=false", "core.askPass=",
               "credential.interactive=false")
STATUS_ARGS = ["status", "--porcelain=v1", "--ignore-submodules=all", "--untracked-files=normal"]


def fetch_args(remote, tags):
    """The ONE fetch shape: an explicit refspec into refs/remotes/<remote>/* (configured refspecs ignored)."""
    a = ["fetch", "--no-prune", "--no-prune-tags", "--no-recurse-submodules", "--no-auto-gc", "--no-tags",
         "--refmap=", "--", remote, "+refs/heads/*:refs/remotes/%s/*" % remote]
    if tags:
        a.append("refs/tags/*:refs/tags/*")
    return a


def obj(sha):
    """The exact object name of the object id ``sha``: '<sha>^{commit}'. Anything that is not an id gives
    INVALID_OBJ, which check_git_args() refuses, so the call is refused (no answer, recorded), never a lookup."""
    return sha + "^{commit}" if isinstance(sha, str) and SHA_RE.fullmatch(sha) else INVALID_OBJ


def _exact_obj(x):
    return isinstance(x, str) and bool(EXACT_OBJ_RE.fullmatch(x))


def exact_remote_ref(ref):
    """True for 'refs/remotes/<rest>' whose <rest> is a valid ref path (no glob, no '..', no '.lock' part): the
    only pattern the exact lookup may give for-each-ref, which then matches it literally (and its children,
    which resolve_ref_exact() drops)."""
    return isinstance(ref, str) and ref.startswith("refs/remotes/") and valid_branch_name(ref[len("refs/"):])


def check_object_names(sub, rest):
    """The exact-name rule of review round 12, for every subcommand that names an object or a ref: the whole
    argument vector is one of a CLOSED set of shapes, and every object in it is HEAD or an obj() name. Raises
    GitRefused otherwise. ls-files and status (review round 13, RV12-5) have their closed shapes here too; the others
    (config, remote, symbolic-ref -q HEAD, add, fetch) are checked by check_git_args itself."""
    if sub == "rev-parse":
        if (len(rest) == 3 and rest[:2] == ["--verify", "-q"] and (rest[2] == "HEAD^{commit}" or _exact_obj(rest[2]))) \
                or rest in (["--show-toplevel"], ["--path-format=absolute", "--git-common-dir"],
                            ["--absolute-git-dir", "--path-format=absolute", "--git-path", "FETCH_HEAD",
                             "--git-common-dir"]):
            return
        raise GitRefused("rev-parse: only --verify -q HEAD^{commit}|<id>^{commit} and the path queries")
    if sub == "rev-list":
        # every shape ends with '--' (review round 13, RV12-3): without it git dies 128 "ambiguous argument 'HEAD':
        # both revision and filename" when the work tree has a file named HEAD (raw git 2.53, ground_truth/)
        rng = rest[2].split("...") if len(rest) == 4 else []
        if rest == ["--count", "HEAD", "--"] or rest == ["--left-right", "--count", "HEAD...HEAD", "--"] or \
                (len(rest) == 4 and rest[:2] == ["--left-right", "--count"] and rest[3] == "--" and len(rng) == 2
                 and all(_exact_obj(x) for x in rng)):
            return
        raise GitRefused("rev-list: only --left-right --count <id>^{commit}...<id>^{commit} -- and the HEAD needles")
    if sub == "merge-base":
        if len(rest) == 3 and rest[0] == "--is-ancestor" and _exact_obj(rest[1]) and _exact_obj(rest[2]):
            return
        raise GitRefused("merge-base: only --is-ancestor <id>^{commit} <id>^{commit}")
    if sub == "ls-tree":
        if (len(rest) == 3 and rest[:2] == ["-r", "-z"] and (rest[2] == "HEAD" or _exact_obj(rest[2]))) or \
                (len(rest) == 5 and rest[:4] == ["-r", "-z", "--name-only", "--full-tree"] and _exact_obj(rest[4])):
            return
        raise GitRefused("ls-tree: only -r -z [--name-only --full-tree] HEAD|<id>^{commit}")
    if sub == "for-each-ref":
        if (len(rest) == 4 and rest[0] == "--contains" and _exact_obj(rest[1])
                and rest[2:] == ["--format=" + FER_CONTAINS_FORMAT, "refs/remotes"]) or \
                (len(rest) == 2 and rest[0] == "--format=" + FER_EXACT_FORMAT and exact_remote_ref(rest[1])):
            return
        raise GitRefused("for-each-ref: only --contains <id>^{commit} under refs/remotes, or the exact lookup")
    if sub == "ls-files":  # review round 13 (RV12-5): the two shapes the engine uses, nothing else
        if rest in (["-s", "-z"], ["-z", "--others", "--ignored", "--exclude-standard"]):
            return
        raise GitRefused("ls-files: only -s -z, or -z --others --ignored --exclude-standard")
    if sub == "status":  # the engine's one shape; bare 'status' (no option, no path) stays for the runner tests
        if rest in (STATUS_ARGS[1:], []):
            return
        raise GitRefused("status: only " + " ".join(STATUS_ARGS))


def git_argv(git_bin, repo, args):
    """The full command line of one git call: SAFE_CONFIG before the subcommand, never a shell."""
    cmd = [git_bin, "-C", repo]
    for kv in SAFE_CONFIG:
        cmd += ["-c", kv]
    return cmd + ["--no-optional-locks"] + list(args)

# ───────────────────────────── git allow-list ─────────────────────────────
READ_SUBCOMMANDS = {"rev-parse", "rev-list", "status", "ls-files", "ls-tree", "for-each-ref", "merge-base",
                    "remote", "config", "symbolic-ref"}
WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add"}
FORBIDDEN_TOKENS = {"--force", "--force-with-lease", "--hard", "--soft", "--mixed", "--amend", "--delete",
                    "--strategy", "--strategy-option", "--mirror", "--recurse-submodules", "--git-dir",
                    "--work-tree", "--exec", "--upload-pack", "--receive-pack", "--set-upstream", "--unshallow",
                    "--refmap", "--orphan", "--ours", "--theirs", "--no-verify", "--allow-unrelated-histories",
                    "--interactive", "--patch", "--all", "--rebase", "--no-ff", "--squash", "--edit",
                    "push", "reset", "rebase", "commit", "clean", "gc", "prune", "update-ref", "filter-branch"}
# Short options are not listed: every WRITE subcommand below has one exact shape, so a short option can
# never reach a write; the read subcommands' short options (ls-files -s, rev-parse -q, ...) are harmless.
FORBIDDEN_PREFIXES = ("--force", "--upload-pack=", "--exec=", "--receive-pack=", "--git-dir=",
                      "--work-tree=", "--strategy=", "--strategy-option=", "--refmap=", "--output",
                      "--config-env", "--super-prefix", "--namespace")


class GitRefused(Exception):
    pass


def check_git_args(args):
    """Return ``args`` as a tuple when it is an allowed shape (the words after ``git``); else raise GitRefused."""
    if not args or not isinstance(args, (list, tuple)):
        raise GitRefused("empty git command")
    for a in args:
        if not isinstance(a, str) or "\n" in a or "\0" in a:
            raise GitRefused("non-string or control character in argument")
    if args[0] == "fetch":  # exactly one of the two engine-owned shapes, nothing else
        rest = list(args[1:])
        remote = rest[rest.index("--") + 1] if "--" in rest and rest.index("--") + 1 < len(rest) else ""
        if not safe_remote(remote):
            raise GitRefused("fetch must name exactly one valid remote after --")
        if list(args) not in (fetch_args(remote, False), fetch_args(remote, True)):
            raise GitRefused("fetch must be exactly: " + " ".join(fetch_args("REMOTE", False)) + " [refs/tags/*:refs/tags/*]")
        return tuple(args)
    for a in args:
        if a.startswith("+"):
            raise GitRefused("forced refspec '%s'" % a)
        if "::" in a:
            raise GitRefused("transport helper '%s'" % a)
    sub, rest = args[0], list(args[1:])
    if sub not in READ_SUBCOMMANDS and sub not in WRITE_SUBCOMMANDS:
        raise GitRefused("subcommand '%s' is not on the allow-list" % sub)
    for a in rest:
        if a == "--":
            continue
        if a in FORBIDDEN_TOKENS or any(a.startswith(p) for p in FORBIDDEN_PREFIXES):
            raise GitRefused("option '%s' is forbidden" % a)
    if sub == "merge":
        if len(rest) != 2 or rest[0] != "--ff-only" or not _exact_obj(rest[1]):
            raise GitRefused("merge must be: merge --ff-only <sha>^{commit}")
    elif sub == "checkout":
        if len(rest) != 3 or rest[0] != "--quiet" or rest[1] != "--detach" or not _exact_obj(rest[2]):
            raise GitRefused("checkout must be: checkout --quiet --detach <sha>^{commit}")
    elif sub == "add":
        if len(rest) != 2 or rest[0] != "--" or not safe_relpath(rest[1]):
            raise GitRefused("add must be: add -- <relative gitlink path>")
    elif sub == "symbolic-ref":
        if rest != ["-q", "HEAD"]:  # the full ref only: --short disambiguates (heads/dev), review round 11 (RV10-1)
            raise GitRefused("symbolic-ref is read-only here: symbolic-ref -q HEAD")
    elif sub == "config":
        # read-only shapes only: --get / --get-regexp, and the submodule update strategy reads (review round 6,
        # RV5-7): -z --get-regexp PATTERN, and --file .gitmodules -z --get-regexp PATTERN (that one file only)
        if not (rest and rest[0] in ("--get", "--get-regexp")) and not (len(rest) == 3 and rest[:2] == ["-z", "--get-regexp"]) \
                and not (len(rest) == 5 and rest[:4] == ["--file", ".gitmodules", "-z", "--get-regexp"]):
            raise GitRefused("config is read-only here: config --get|--get-regexp ...")
    elif sub == "remote":
        if rest:
            raise GitRefused("remote is read-only here: bare 'git remote'")
    check_object_names(sub, rest)
    return tuple(args)


def safe_remote(name):
    """A remote name usable inside refs/remotes/<name>/*: no option, no glob, no '.'/'..' part."""
    if not name or not REMOTE_RE.match(name) or name.endswith((".lock", "/", ".")):
        return False
    return all(x not in ("", ".", "..") for x in name.split("/"))


def valid_branch_name(name):
    """True when ``name`` is a usable short branch name (the part after refs/heads/) that is put into a lock path
    (refs/heads/<name>.lock) and compared as is (review round 11, RV10-1): git's own ref-name rules (check-ref-format)
    plus the path rules of safe_relpath. Refused: empty; a leading '-' or '/'; a trailing '/' or '.'; an empty, '.'
    or '..' component; a component starting with '.' or ending with '.lock'; '..' or '@{' anywhere; the name '@'
    or 'HEAD'; a control character, space, ~ ^ : ? * [ or backslash. Non-ASCII letters are allowed (git allows them);
    --branch itself must also match BRANCH_RE (ASCII). Case is kept exactly: Dev and dev are different branches."""
    if not isinstance(name, str) or not name or name in ("@", "HEAD") or name.startswith(("-", "/")):
        return False
    if name.endswith(("/", ".")) or ".." in name or "@{" in name or _REF_BAD_CHARS.search(name):
        return False
    return all(x and not x.startswith(".") and not x.endswith(".lock") for x in name.split("/"))


def branch_of_ref(full):
    """The short branch name of the FULL symbolic-ref ``full`` ('refs/heads/<name>' -> '<name>'), or None when the
    ref is not under refs/heads/ or the name is not valid_branch_name(). The prefix is stripped by string, never by
    asking git for a short name: 'git symbolic-ref --short' DISAMBIGUATES and answers 'heads/dev' when a tag (refs/tags/dev)
    or a top-level ref refs/dev exists beside branch dev (a remote named 'dev' does not cause it, measured) (review round 11, RV10-1), which put the wrong branch into the
    branch-lock path (refs/heads/heads/dev.lock instead of refs/heads/dev.lock)."""
    if not isinstance(full, str) or not full.startswith(HEADS):
        return None
    name = full[len(HEADS):]
    return name if valid_branch_name(name) else None


def safe_relpath(p):
    if not p or p.startswith("-") or p.startswith("/") or "\\" in p:
        return False
    parts = p.split("/")
    return all(x not in ("", ".", "..") for x in parts)


# ───────────────────────────── redaction ─────────────────────────────
_SCHEME = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://")
_TOKENS = re.compile(r"(gh[pousr]_|github_pat_|glpat-|xox[abprs]-|AKIA)[A-Za-z0-9_\-]{4,}")
_AUTH = re.compile(r"(?i)\b((?:proxy-)?authorization:[ \t]*)[^\n]+")
_CTRL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f\x80-\x9f]")
# Userinfo pieces of every configured remote URL (8 characters or more), registered before any fetch thread starts
# (inspect_local runs first, one thread): a secret git repeats WITHOUT its URL is still removed. Shorter pieces are
# not registered (a 3-letter user name such as "git" would remove ordinary words); they are cut structurally.
_KNOWN = set()
_KNOWN_LOCK = threading.Lock()


_SCHEME_CHARS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+.-")
_LETTERS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")


def _strip_line(line):
    """One line: cut from the first ``scheme://`` (a run of [A-Za-z0-9+.-] holding a letter, then '://') that has a
    '@' after it, to the LAST '@' of the line. Linear in the line length (review round 4, RV4-3): every '://' is found
    with str.find, and the backward run before each '://' cannot reach past the previous '://' (the run holds no ':'
    or '/'), so every character is looked at a bounded number of times."""
    at = line.rfind("@")
    if at == -1:
        return line
    i = line.find("://")
    while i != -1 and i < at:
        j, letter = i, False
        while j > 0 and line[j - 1] in _SCHEME_CHARS:
            j -= 1
            letter = letter or line[j] in _LETTERS
        if letter:
            return line[:i + 3] + line[at + 1:]
        i = line.find("://", i + 3)
    return line


def strip_userinfo(text):
    """Remove URL userinfo structurally: for every ``scheme://`` the URL token runs to the END OF THE LINE (a
    password may hold spaces, '@', '://' or be of any length; nothing is cut at a fixed width) and everything up to
    the LAST '@' in that line is removed. At most one cut per line; a '://' after the cut is inside the removed part
    or after the last '@' and cuts nothing. A '@' later on the same line (a second URL, a path, prose) removes more
    than the userinfo: fail-safe over-redaction, never a leak. Linear time (RV4-3)."""
    return "\n".join(_strip_line(x) for x in text.split("\n"))


def register_secret(url):
    """Remember the userinfo of one configured remote URL (the whole value, which may hold a newline)."""
    m = _SCHEME.match(url or "")
    at = url.rfind("@") if m else -1
    if not m or at < m.end():
        return
    info = url[m.end():at]
    pieces = {info, info.partition(":")[2]}
    for p in list(pieces):
        pieces.update(p.split("\n"))
    with _KNOWN_LOCK:
        _KNOWN.update(p for p in pieces if len(p) >= 8)


def strip_secrets(text):
    with _KNOWN_LOCK:
        known = sorted(_KNOWN, key=len, reverse=True)
    for s in known:
        text = text.replace(s, "[REDACTED]")
    return _TOKENS.sub("[REDACTED]", _AUTH.sub(r"\1[REDACTED]", strip_userinfo(text)))


def redact_url(url):
    """One configured URL value, as a whole (newline-safe): everything between ``scheme://`` and its LAST '@' goes."""
    u = url or ""
    m = _SCHEME.match(u)
    at = u.rfind("@") if m else -1
    if m and at >= m.end():
        u = u[:m.end()] + u[at + 1:]
    return redact(u)


def redact(text):
    """Remove URL userinfo, known token shapes and control characters."""
    if text is None:
        return ""
    return _CTRL.sub("?", strip_secrets(str(text)))


def redact_report(obj, path, hits):
    """The report as written: every string passes redact() again (a backstop behind the per-field redaction),
    keys starting with '_' (raw, private values) are dropped. ``hits`` collects the field paths where the
    backstop had to remove a credential-class string: it must stay empty (the tests assert it)."""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if k.startswith("_"):
                continue
            rk = redact(k)  # a key is output too (review round 3, class D)
            if strip_secrets(k) != k:
                hits.append(path + "." + rk)
            out[rk] = redact_report(v, path + "." + rk, hits)
        return out
    if isinstance(obj, list):
        return [redact_report(v, "%s[%d]" % (path, i), hits) for i, v in enumerate(obj)]
    if isinstance(obj, str):
        if strip_secrets(obj) != obj:
            hits.append(path)
        return redact(obj)
    return obj


def url_org_segments(url):
    """Path segments of a remote URL except the last (the repository itself)."""
    u = url or ""
    m = re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://[^/]*(/.*)$", u)
    if m:
        path = m.group(1)
    elif re.match(r"^[^/:]+:", u) and not u.startswith("/"):  # scp-like host:path (linear; review round 5)
        path = u.split(":", 1)[1]
    else:
        path = u
    segs = [s for s in path.split("/") if s]
    return segs[:-1]


def is_own_org(url, own_orgs):
    low = {o.lower() for o in own_orgs}
    return any(s.lower() in low for s in url_org_segments(url))


# ───────────────────────────── host safety ─────────────────────────────
def clamp_jobs(requested, cpus):
    ceiling = max(1, min(8, (cpus or 1) // 2))
    if requested is None:
        return max(1, min(4, ceiling))
    return max(1, min(int(requested), ceiling))


# ───────────────────────────── the ONE spawn point ─────────────────────────────
# proc_run_git and proc_kill_group are the only functions that may use subprocess / signal / os.killpg; the
# gate proves it from the AST (every subprocess.* / signal.* / os.killpg / os.getpgid name is scoped to them,
# each is called from exactly one place, and nothing else can start a process or send a signal).
def proc_run_git(git_bin, repo, args, env, limit, level=1):
    """Run ONE git call. Returns (kind, code, out, err): kind 'exit' (code = exit status), 'signal' (code = the
    signal number), 'timeout', 'output-too-large', 'interrupted' or 'not-runnable'. Raises GitRefused before any
    process exists. The pipes are read in 64 KiB pieces (select): stdout is kept up to OUT_CAP, stderr only its last
    ERR_TAIL bytes (RV4-4), so a remote that writes without end costs bounded memory. ``level`` says which stop
    request ends the call: 0 none (a stop signal never ends a WRITE half-way; only its own limit does), 1 the first
    (STOP_REQUESTED), 2 only the second (HARD_STOP: the final reads). Every ending except a normal exit ends the
    call's own process group (one place): SIGTERM, then SIGKILL after the grace period (review round 6, RV5-1)."""
    checked = check_git_args(args)
    try:
        p = subprocess.Popen(git_argv(git_bin, repo, checked), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=env, start_new_session=True)
    except OSError as e:
        return "not-runnable", None, "", "cannot run git: %s" % e
    t_end = time.monotonic() + limit
    out, err, dropped, why = bytearray(), bytearray(), False, None
    streams = {p.stdout.fileno(): out, p.stderr.fileno(): err}
    while why is None:
        if (level == 1 and STOP_REQUESTED.is_set()) or (level == 2 and HARD_STOP.is_set()):
            why = "interrupted"
            break
        left = t_end - time.monotonic()
        if left <= 0:
            why = "timeout"
            break
        if not streams:  # both pipes at end of file: wait for the exit status in short steps (stop stays checked)
            try:
                p.wait(timeout=min(left, 0.2))
                break
            except subprocess.TimeoutExpired:
                continue
        exited = p.poll() is not None  # git has exited: read what is buffered now, never wait for an escaped
        ready = select.select(list(streams), [], [], 0 if exited else min(left, 0.2))[0]  # grandchild's pipe (F8)
        if exited and not ready:
            break
        for fd in ready:
            chunk = os.read(fd, 65536)
            buf = streams[fd]
            if not chunk:
                del streams[fd]
            elif buf is out:
                if len(out) + len(chunk) > OUT_CAP:
                    why = "output-too-large"
                    break
                out += chunk
            else:
                err += chunk
                if len(err) > 2 * ERR_TAIL:
                    del err[:len(err) - ERR_TAIL]
                    dropped = True
    ended_by = None
    if why is not None:
        ended_by = proc_kill_group(p, WRITE_KILL_GRACE if level == 0 else KILL_GRACE)
    for s_ in (p.stdout, p.stderr):  # a grandchild that escaped the group may hold a pipe: never wait for it (F8)
        try:
            s_.close()
        except OSError:
            pass
    if why is not None:
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        return why, None, "", "%s; ended by %s" % ({"timeout": "timeout after %ds" % int(limit),
                                                    "interrupted": "stopped by a signal",
                                                    "output-too-large": "more than %d bytes of output" % OUT_CAP}[why],
                                                   ended_by or "nothing (the process had already ended)")
    if dropped:  # drop the partial first line of the tail: a URL is never kept without its scheme (RV4-3)
        nl = err.find(b"\n")
        err = bytearray(b"[earlier stderr dropped]\n") + (err[nl + 1:] if nl != -1 else bytearray())
    rc = p.returncode
    o, e = out.decode("utf-8", "replace"), err.decode("utf-8", "replace")
    if rc < 0:
        return "signal", -rc, o, e
    return "exit", rc, o, e


def on_stop_signal(signum, frame):
    """The stop-signal handler (installed by proc_on_stop_signals): only sets a flag; the git calls poll it."""
    if STOP_REQUESTED.is_set():
        HARD_STOP.set()
    STOP_REQUESTED.set()


def proc_on_stop_signals(handler):
    """Install ``handler`` for SIGINT, SIGTERM and SIGHUP (RV4-5): no traceback, no orphaned git; the run stops
    its interruptible calls, finishes the write in flight, reads the final heads and writes its report."""
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, handler)


def proc_kill_group(p, grace):
    """End the process group of a child started with start_new_session (§11.4.263: pgid > 1): SIGTERM first, then,
    after the child ended or after ``grace`` seconds, SIGKILL (which also ends what is left of the group, a filter
    process for example). The child is never reaped here (WNOWAIT): its pid, and with it the group id, stays
    reserved until both signals are sent. Returns 'SIGTERM' when the child ended within the grace period, 'SIGKILL'
    when it needed SIGKILL, None when no signal could be sent (review round 6, RV5-1)."""
    try:
        pgid = os.getpgid(p.pid)
    except OSError:
        return None
    ended_by = None
    for sig in (signal.SIGTERM, signal.SIGKILL):
        if sig == signal.SIGKILL and ended_by is not None:  # wait, never reap, for the child to end on SIGTERM
            t_end = time.monotonic() + grace
            gone = False
            while not gone and time.monotonic() < t_end:
                try:
                    gone = os.waitid(os.P_PID, p.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is not None
                except ChildProcessError:
                    gone = True
                if not gone:
                    time.sleep(0.05)
            ended_by = "SIGTERM" if gone else "SIGKILL"
        if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:
            try:
                os.killpg(pgid, sig)
                if ended_by is None:
                    ended_by = "SIGKILL" if sig == signal.SIGKILL else "SIGTERM"
            except OSError:
                pass
    return ended_by


# ───────────────────────────── git runner ─────────────────────────────
# Object visibility is REAL history (review round 12, RV11-2): a replace ref ('git replace --graft U L') or a graft
# (<git dir>/info/grafts, GIT_GRAFT_FILE) can make a local commit L look like an ancestor of the upstream U, and the
# fast-forward then drops L. Every git call runs with replace refs off and an empty graft file, whatever the user's
# environment or the repository's config (core.useReplaceRefs) says; the caller's value is scrubbed first (_SCRUB),
# then the pin is set. Shallow boundaries are not neutralised: they only REMOVE edges, which makes the engine see
# less ancestry (diverged / attention), never more. Ground truth: docs/qa/sync_upstreams_2026_11_16_r12/.
OBJECT_VISIBILITY_PIN = (("GIT_NO_REPLACE_OBJECTS", "1"), ("GIT_GRAFT_FILE", "/dev/null"))
# Paths are literal (review round 13, RV12-2): every path the engine gives git ('add -- <gitlink path>') is a PATH,
# never a pathspec pattern. Without the pin, glob characters ('lib[1]', 'lib*'), magic (':!x' = every path but x)
# and the caller's GIT_ICASE_PATHSPECS / GIT_GLOB_PATHSPECS made 'add' stage OTHER gitlinks or miss the intended one
# (raw git 2.53, ground_truth/). The caller's four pathspec variables are scrubbed first (_SCRUB): git refuses
# GIT_LITERAL_PATHSPECS together with any other global pathspec setting. write_git also VERIFIES after the add that
# exactly one index entry changed (stage_pin_verified), whatever grammar or config (core.ignoreCase) git applied.
PATH_LITERAL_PIN = (("GIT_LITERAL_PATHSPECS", "1"),)
_SCRUB = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR",
          "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_EXEC_PATH", "GIT_SSH", "GIT_ASKPASS",
          "SSH_ASKPASS", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_PROXY_COMMAND",
          "GIT_CURL_VERBOSE", "GIT_REDACT_COOKIES", "GIT_PREFIX",
          "GIT_QUARANTINE_PATH", "GIT_REPLACE_REF_BASE", "GIT_SHALLOW_FILE", "GIT_INTERNAL_SUPER_PREFIX",
          # review round 11 (RV10-3): the rest of the repository-locating list CL_GIT_SCRUB_VARS of
          # scripts/lib/constitution_layout.sh (a unit test asserts this tuple holds every name of that list)
          "GIT_GRAFT_FILE", "GIT_NO_REPLACE_OBJECTS",
          # review round 13 (RV12-2): pathspec grammar of the caller; PATH_LITERAL_PIN is set after the scrub
          "GIT_LITERAL_PATHSPECS", "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS", "GIT_ICASE_PATHSPECS",
          # review round 4: GIT_ALLOW_PROTOCOL beats -c protocol.ext.allow=never (ground truth row D2);
          # GIT_PROTOCOL_FROM_USER changes what protocol.*.allow=user means (D5); SSH_ASKPASS_REQUIRE can force
          # the ssh askpass (set below); GIT_SSL_NO_VERIFY turns TLS verification off
          "GIT_ALLOW_PROTOCOL", "GIT_PROTOCOL_FROM_USER", "SSH_ASKPASS_REQUIRE", "GIT_SSL_NO_VERIFY")


def git_env(base=None):
    env = dict(base if base is not None else os.environ)
    for k in list(env):
        # every GIT_TRACE* variable (GIT_TRACE, _PACKET, _CURL, _PERFORMANCE, _SETUP, GIT_TRACE2, _EVENT, _PERF, ...)
        # is dropped by prefix: a trace writes protocol traffic, headers or URLs to a file or to stderr
        if (k in _SCRUB or k.startswith("GIT_TRACE") or k.startswith("GIT_CONFIG_KEY_")
                or k.startswith("GIT_CONFIG_VALUE_")):
            del env[k]
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GIT_ASKPASS"] = ""  # empty: git runs no askpass program (D9), and it beats core.askPass (D10)
    env["SSH_ASKPASS_REQUIRE"] = "never"  # ssh never runs SSH_ASKPASS (D12, D13)
    env["GCM_INTERACTIVE"] = "never"
    env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
    env["LC_ALL"] = "C"
    env["LANG"] = "C"
    env.update(OBJECT_VISIBILITY_PIN)
    env.update(PATH_LITERAL_PIN)
    return env


class GitResult:
    """One git call. ``answered`` is True only when git exited with a status the call site declared as an answer
    (and, when the call site declared a shape, the output has it). Otherwise ``why`` says why there is no answer."""
    def __init__(self, answered, rc, out, err, why, started=True):
        self.answered = answered
        self.rc = rc
        self.out = out
        self.err = err
        self.why = why
        # False only when NO git process was started (refused by a stop or the deadline, refused by the allow-list,
        # or the kernel could not start it): such a call cannot have changed anything (review round 7, RV6-1)
        self.started = started

    def text(self):
        """The output of an answered call that exited 0, stripped; else None."""
        return self.out.strip() if self.answered and self.rc == 0 else None


class Runner:
    def __init__(self, git_bin, timeout, deadline, write_timeout=3600):
        self.git = git_bin
        self.timeout = timeout
        self.deadline = deadline
        self.write_timeout = write_timeout
        self.run_id = ""
        self.env = git_env()
        self.env_repo_ssh = dict(self.env)  # for a repository with its own core.sshCommand (F9)
        self.env_repo_ssh.pop("GIT_SSH_COMMAND", None)
        self.calls = 0
        self.lock = threading.Lock()
        self.unresolved = {}  # realpath(repo) -> set of "<subcommand>:<why>" (a call that did not answer)
        self.gitdirs = {}  # realpath(git dir) -> GD_* state of its write marker in this run (review round 8)
        self.writes = 0  # write ids handed out in this run
        self.sites = {}  # realpath(git dir) -> (common dir, branch) of an inspected repository (review round 9)

    def register_site(self, gitdir, common, branch):
        with self.lock:
            self.sites[os.path.realpath(gitdir)] = (common or gitdir, branch)

    def site(self, gitdir):
        """(common dir, branch) of an inspected git dir, or None: a git dir this run did not inspect."""
        with self.lock:
            return self.sites.get(os.path.realpath(gitdir)) if gitdir else None

    def gd_state(self, gitdir):
        with self.lock:
            return self.gitdirs.get(os.path.realpath(gitdir), GD_NONE)

    def gd_move(self, gitdir, new):
        """Move ``gitdir``'s marker state to ``new``; False (and no move) when GD_MOVES does not allow it."""
        key = os.path.realpath(gitdir)
        with self.lock:
            if new not in GD_MOVES[self.gitdirs.get(key, GD_NONE)]:
                return False
            self.gitdirs[key] = new
            return True

    def token_refusal(self, token):
        """Why a write holding ``token`` may NOT start now, or None: the token must be the live one of its git dir
        (state GD_WRITING) and the marker on disk, read now, must be the one this write created."""
        if token is None:
            return "no-write-token"
        if self.gd_state(token.gitdir) != GD_WRITING:
            return "write-token-stale"
        if marker_write_id(token.gitdir) != token.write_id:
            return "write-marker-not-ours"
        return None

    def remaining(self):
        return self.deadline - time.monotonic()

    def no_answer(self, repo, sub, why):
        with self.lock:
            self.unresolved.setdefault(os.path.realpath(repo), set()).add("%s:%s" % (sub, why))

    def run(self, repo, args, ok, network=False, repo_ssh=False, want=None, write=False, final=False, token=None):
        """Run one git call and return a GitResult. ``ok`` = the exit statuses that are an ANSWER for this call
        (declared at every call site); ``want`` = a compiled pattern the stripped output of an exit-0 answer must
        match. Every call that gives no answer is recorded for ``repo`` (it makes the repository unresolved or
        blind), except a NETWORK call that ran out of time: that is the remote's state (unreachable), recorded by
        the caller. After a stop signal (RV4-5) a new call is refused ("interrupted") unless it is a ``final`` read
        (the head reads that record what moved; refused too after a second signal).
        Review round 6 (RV5-1): a ``write`` starts only before the deadline (or, the second half of a write, as a
        ``final`` call), and then runs under its OWN limit, --write-timeout: neither the per-call timeout nor the
        run deadline nor a stop signal ends it half-way. A write that its own limit ends is "write-killed" (SIGTERM
        first). A ``final`` read runs after the deadline too, with at most 10 seconds once the deadline is near or
        a stop was asked for.
        Review round 8 (RV7-1): a ``write`` starts only holding ``token`` (begin_write), the live write of its git
        dir whose marker is on disk NOW; any other write is refused before git starts ("no-write-token",
        "write-token-stale", "write-marker-not-ours"), so no write git ever runs into a git dir holding a marker
        it did not create."""
        sub = args[0] if args else "?"
        if STOP_REQUESTED.is_set() and (not final or HARD_STOP.is_set()):
            self.no_answer(repo, sub, "interrupted")
            return GitResult(False, None, "", "stopped by a signal", "interrupted", started=False)
        left = self.remaining()
        if left <= 0 and not final:
            self.no_answer(repo, sub, "deadline")
            return GitResult(False, None, "", "run deadline passed", "deadline", started=False)
        if write:
            refusal = self.token_refusal(token)
            if refusal:
                self.no_answer(repo, sub, refusal)
                return GitResult(False, None, "", "write refused: %s" % refusal, refusal, started=False)
        if write:
            limit = self.write_timeout
        elif final:
            limit = min(max(self.timeout, 60), max(left, 10))
            if STOP_REQUESTED.is_set():
                limit = min(limit, 10)
        else:
            limit = min(self.timeout if network else max(self.timeout, 60), left)
        level = 0 if write else 2 if final else 1
        with self.lock:
            self.calls += 1
        try:
            kind, code, out, err = proc_run_git(self.git, repo, args, self.env_repo_ssh if repo_ssh else self.env,
                                                limit, level)
        except GitRefused as e:
            self.no_answer(repo, sub, "refused")
            return GitResult(False, None, "", "refused: %s" % e, "refused", started=False)
        if kind == "exit" and code in ok:
            if code == 0 and want is not None and not want.match(out.strip()):
                self.no_answer(repo, sub, "malformed-output")
                return GitResult(False, code, out, err, "malformed-output")
            return GitResult(True, code, out, err, None)
        why = {"exit": "rc:%s" % code, "signal": "signal:%s" % code}.get(kind, kind)
        if write and why == "timeout":  # its own limit ended the write: a known failure, never an unknown state
            return GitResult(False, code, out, err, "write-killed")
        if not (network and why == "timeout"):
            self.no_answer(repo, sub, why)
        return GitResult(False, code, out, err, why, started=(kind != "not-runnable"))

    def write_refused_now(self, final=False):
        """True when run() would refuse a write right now, before starting git: the same predicate as run() for
        ``write=True`` (a non-final write: a stop signal or the deadline; a final one, the second half of a write:
        only a second stop signal). Both only ever become true, never false again, so a write this says may start
        can still be refused by run() a moment later; write_git then removes its marker (review round 7, RV6-1)."""
        if final:
            return STOP_REQUESTED.is_set() and HARD_STOP.is_set()
        return STOP_REQUESTED.is_set() or self.remaining() <= 0

    def unresolved_for(self, repo):
        with self.lock:
            return sorted(self.unresolved.get(os.path.realpath(repo), ()))


# ───────────────────────────── helpers ─────────────────────────────
def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def g_out(r, repo, args, ok, want=None, final=False):
    """Stripped output of an answered exit-0 call, else None (a call with no answer is recorded by r.run)."""
    return r.run(repo, args, ok=ok, want=want, final=final).text()


def read_head(r, repo, final=False):
    """HEAD as a full object id, or None (unborn: rev-parse --verify exits 1; or no answer, recorded): an unread
    head is never compared, so it can never read as "unchanged" or "moved" (F3)."""
    return g_out(r, repo, ["rev-parse", "--verify", "-q", "HEAD^{commit}"], ok=(0, 1), want=SHA_RE, final=final)


def read_branch(r, repo, final=False):
    """('branch', name) when HEAD is a symbolic ref to refs/heads/<name>, ('detached', None) when it is not a
    symbolic ref (symbolic-ref -q exits 1), ('other', None) when it is a symbolic ref outside refs/heads/ (never a
    branch: no write needs it), ('unknown', None) when git gave no answer or an answer this code cannot use
    (recorded): a detached HEAD and an unread one are told apart, which the write-time re-check needs (RV4-1).
    The FULL ref is read and refs/heads/ is stripped here (review round 11, RV10-1): 'symbolic-ref --short' answers
    a disambiguated 'heads/dev' when a tag refs/tags/dev or a ref refs/dev exists, and that string became the branch-lock
    path. The name is kept with its case (Dev is not dev, RV10-2)."""
    res = r.run(repo, ["symbolic-ref", "-q", "HEAD"], ok=(0, 1), final=final)
    if not res.answered:
        return "unknown", None
    name = res.out.rstrip("\n")
    if res.rc == 1:
        return "detached", None
    # exit 0 with no name (RV4-1), several lines, or no refs/ prefix: not an answer this code can use. An empty
    # name fails startswith("refs/"), so this one test carries the RV4-1 guard (mutant P32 targets it).
    if "\n" in name or not name.startswith("refs/"):  # one full ref, one line
        r.no_answer(repo, "symbolic-ref", "malformed-output")
        return "unknown", None
    if not name.startswith(HEADS):
        return "other", None
    short = branch_of_ref(name)
    if short is None:  # a refs/heads/ name git itself would refuse (hand-edited HEAD): never put into a path
        r.no_answer(repo, "symbolic-ref", "malformed-output")
        return "unknown", None
    return "branch", short


def is_ancestor(r, repo, a, b):
    """True / False (merge-base --is-ancestor exits 0 / 1), or None when it gave no answer (recorded)."""
    res = r.run(repo, ["merge-base", "--is-ancestor", obj(a), obj(b)], ok=(0, 1))
    return (res.rc == 0) if res.answered else None


def count_range(r, repo, a, b):
    """(ahead_of_b, behind_b) for a vs b, or None (no answer, recorded)."""
    out = g_out(r, repo, ["rev-list", "--left-right", "--count", "%s...%s" % (obj(a), obj(b)), "--"], ok=(0,), want=TWO_COUNTS_RE)
    if out is None:
        return None
    parts = out.split()
    return int(parts[0]), int(parts[1])


def commit_present(r, repo, sha):
    """True / False (rev-parse --verify -q exits 0 / 1), or None when it gave no answer (recorded)."""
    res = r.run(repo, ["rev-parse", "--verify", "-q", obj(sha)], ok=(0, 1), want=SHA_RE)
    return (res.rc == 0) if res.answered else None


def classify(ahead, behind):
    if ahead == 0 and behind == 0:
        return "equal"
    if ahead == 0:
        return "behind"
    if behind == 0:
        return "ahead"
    return "diverged"


def pick_newest(shas, ancestor):
    """Newest of ``shas`` when they are linearly ordered under ``ancestor(a, b)``; else None."""
    uniq = sorted(set(shas))
    if not uniq:
        return None
    for c in uniq:
        if all(o == c or ancestor(o, c) for o in uniq):
            return c
    return None


# ───────────────────────────── path access layer ─────────────────────────────
# Review round 9 (RV8-2 / RV8-4, the class "a filesystem object at or around a path the engine reads, creates,
# clears or checks"): EVERY filesystem access of the engine goes through path_kind and the fs_* functions below
# (enforced by docs/qa/.../class_inventory_write_paths.py, rule R5). None of them ever blocks on, follows, opens for
# reading, or removes an object that is not a regular file (a FIFO, a socket, a device, a directory, a symbolic link):
# a read opens O_NONBLOCK|O_NOFOLLOW and requires S_ISREG on the OPEN file (fstat), so an object swapped in after the
# lstat is still refused; a removal removes a regular file only and reports, never raises. Exemptions (stated, never
# hidden): os.path.realpath / abspath / join (resolve names, open nothing), the controlling terminal (fs_open_tty).
KIND_OF_MODE = ((stat.S_ISDIR, "dir"), (stat.S_ISREG, "regular"), (stat.S_ISLNK, "symlink"), (stat.S_ISFIFO, "fifo"),
                (stat.S_ISSOCK, "socket"), (stat.S_ISCHR, "char-device"), (stat.S_ISBLK, "block-device"))
READ_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_NOCTTY | os.O_CLOEXEC


def kind_of_mode(mode):
    for test, name in KIND_OF_MODE:
        if test(mode):
            return name
    return "other"


def path_kind(path):
    """'absent', 'unreadable', or the kind of what is at ``path`` ('dir', 'regular', 'symlink', 'fifo', 'socket',
    'char-device', 'block-device', 'other'), from ONE os.lstat (the last component is never followed).
    os.path.exists / isdir / lexists read "permission denied" as "not there"; here only "no such file" (or a path
    component that is not a directory) is absent, every other error is unreadable (review round 3, F1 class B: an
    unread path is never read as absent)."""
    try:
        st = os.lstat(path)
    except (FileNotFoundError, NotADirectoryError):
        return "absent"
    except OSError:
        return "unreadable"
    return kind_of_mode(st.st_mode)


def fs_is_regular(path):
    return path_kind(path) == "regular"


def fs_read(path, cap):
    """(status, bytes) of the regular file at ``path``: 'ok', 'absent', 'unreadable', 'too-large' (more than ``cap``
    bytes: unread, never half-read) or 'not-regular:<kind>'. Never blocks: a FIFO, a socket or a device is refused
    by the lstat, and again by fstat on the open descriptor (O_NONBLOCK) when it was swapped in after the lstat."""
    k = path_kind(path)
    if k != "regular":
        return (k if k in ("absent", "unreadable") else "not-regular:" + k), b""
    try:
        fd = os.open(path, READ_FLAGS)
    except (FileNotFoundError, NotADirectoryError):
        return "absent", b""
    except OSError as e:
        return ("not-regular:symlink" if e.errno == 40 else "unreadable"), b""  # ELOOP: a link swapped in
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return "not-regular:" + kind_of_mode(st.st_mode), b""
        chunks, n = [], 0
        while n <= cap:
            chunk = os.read(fd, min(65536, cap + 1 - n))
            if not chunk:
                break
            chunks.append(chunk)
            n += len(chunk)
    except OSError:
        return "unreadable", b""
    finally:
        os.close(fd)
    data = b"".join(chunks)
    return ("too-large", b"") if len(data) > cap else ("ok", data)


def fs_create_excl(path, data):
    """CREATE ``path`` exclusively (O_EXCL|O_NOFOLLOW, 0600) with ``data``: 'written'; 'exists' when anything at all
    is already there (never opened, overwritten or removed); 'unwritable'. A file this call created and could not
    write whole is removed again (it was this call's own)."""
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    except FileExistsError:
        return "exists"
    except OSError:
        return "unwritable"
    try:
        try:
            os.write(fd, data)
            os.fsync(fd)
        finally:
            os.close(fd)
    except OSError:
        fs_remove(path)
        return "unwritable"
    return "written"


def fs_remove(path):
    """Remove the REGULAR file at ``path``: 'removed', 'absent', 'not-regular:<kind>' (nothing removed: a FIFO, a
    directory, a symbolic link, ... is never removed), 'unreadable' or 'failed:<errno name>'. Never raises."""
    k = path_kind(path)
    if k == "absent":
        return "absent"
    if k != "regular":
        return k if k == "unreadable" else "not-regular:" + k
    try:
        os.unlink(path)
    except FileNotFoundError:
        return "absent"
    except OSError as e:
        return "failed:" + (errno_name(e.errno))
    return "removed"


def errno_name(n):
    return errno.errorcode.get(n or 0, str(n))


def fs_open_lock(path):
    """(fd, None) for this engine's run lock at ``path`` (created 0600 when absent), or (None, why). Only a regular
    file is a lock: the open never blocks (O_NONBLOCK; a FIFO with no writer would wait forever) and fstat must show
    a regular file, else the descriptor is closed and the object left untouched (review round 9, RV8-2 class)."""
    try:
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_NOCTTY | os.O_CLOEXEC, 0o600)
    except OSError as e:
        return None, e.strerror or str(e)
    try:
        st = os.fstat(fd)
    except OSError as e:
        os.close(fd)
        return None, e.strerror or str(e)
    if not stat.S_ISREG(st.st_mode):
        os.close(fd)
        return None, "not a regular file (%s)" % kind_of_mode(st.st_mode)
    return fd, None


def fs_probe_dir(path):
    """Create the directory ``path`` (0700) when absent and prove it writable with a real file (mkstemp, then
    removed): None, or the error text."""
    try:
        os.makedirs(path, mode=0o700, exist_ok=True)
        fd_, probe_ = tempfile.mkstemp(prefix=".sync_probe.", dir=path)
        os.close(fd_)
        os.unlink(probe_)
    except OSError as e:
        return e.strerror or str(e)
    return None


def fs_ensure_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)


def fs_write_atomic(path, data):
    """Write ``data`` to a fresh, unpredictable temporary file (O_EXCL, mode 0600) in the same directory and
    rename it over ``path``."""
    fd, tmp = tempfile.mkstemp(prefix=".sync_report.", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def fs_open_tty():
    """The controlling terminal (exemption: a character device by design, opened only with --interactive)."""
    return os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)


def lock_paths(gitdir, common, branch, git_sub=None):
    """[(label, path)] of the lock files git takes for the write ``git_sub`` ('merge', 'checkout', 'add'), or for
    ANY engine write when None, in ``gitdir`` and the common dir ``common``. The label is the git-dir-relative name,
    'common:<name>' for a common-dir lock of a linked worktree (git dir != common dir)."""
    subs = [git_sub] if git_sub else sorted(GITDIR_LOCKS)
    common = common or gitdir
    split = os.path.realpath(common) != os.path.realpath(gitdir)
    out, seen = [], set()
    for sub in subs:
        for n in GITDIR_LOCKS[sub]:
            if n not in seen:
                seen.add(n)
                out.append((n, os.path.join(gitdir, n)))
        for n in COMMON_LOCKS[sub]:
            if "{branch}" in n:
                if not branch:
                    continue
                n = n.format(branch=branch)
            label = ("common:" + n) if split else n
            if label not in seen:
                seen.add(label)
                out.append((label, os.path.join(common, n)))
    return out


def in_progress(gitdir, common=None, branch=None):
    """Operations and locks in progress in ``gitdir`` (and its common dir ``common``; the branch ref lock of
    ``branch``): every lock file ANY engine write takes (lock_paths; review round 9, RV8-1, was index.lock only), and
    anything at the write-marker path that is not a regular file ('write-marker-path-not-a-file:<kind>', never
    opened or removed; RV8-2 / RV8-4). An entry that cannot be read counts as in progress ('<name>?unreadable')."""
    found = []
    names = [(n, os.path.join(gitdir, n)) for n in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG",
                                                     "rebase-merge", "rebase-apply")]
    for n, path in names + lock_paths(gitdir, common, branch):
        k = path_kind(path)
        if k == "unreadable":
            found.append(n + "?unreadable")
        elif k != "absent":
            found.append(n)
    mk = path_kind(os.path.join(gitdir, WRITE_MARKER))
    if mk not in ("absent", "regular", "unreadable"):
        found.append("write-marker-path-not-a-file:" + mk)
    return found


def probe_child(r, path):
    """What is at a submodule path: 'absent', 'not-a-directory' (a file or a symbolic link), 'uninitialised' (a
    directory without .git), 'unreadable' or 'repo'. 'unreadable' is a NO ANSWER, recorded for ``path`` (review
    round 3, F1): a .git that git cannot read (exit 128: a broken gitdir pointer, an unknown repository extension,
    dubious ownership) or whose top level is not ``path`` (a .git git does not recognise makes rev-parse walk up to
    the parent) is never read as "not initialised"."""
    kind = path_kind(path)
    if kind in ("absent", "unreadable"):
        if kind == "unreadable":
            r.no_answer(path, "lstat", "unreadable")
        return kind
    if kind != "dir":
        return "not-a-directory"
    dotgit = path_kind(os.path.join(path, ".git"))
    if dotgit == "absent":
        return "uninitialised"
    if dotgit == "unreadable":
        r.no_answer(path, "lstat", "unreadable")
        return "unreadable"
    top = g_out(r, path, ["rev-parse", "--show-toplevel"], ok=(0,), want=ABS_PATH_RE)
    if top is None:  # no answer (128 included), recorded by r.run
        return "unreadable"
    if os.path.realpath(top) != os.path.realpath(path):
        r.no_answer(path, "rev-parse", "not-own-toplevel")
        return "unreadable"
    return "repo"


def parse_ls_tree(out):
    res = {}
    for x in out.split("\0"):
        if not x:
            continue
        meta, _, path = x.partition("\t")
        f = meta.split()
        if len(f) == 3 and f[0] == "160000":
            res[path] = f[2]
    return res


def index_gitlinks(r, repo, final=False, raw=None):
    """{path: sha} of the gitlinks recorded in the index, or None when git gave no answer (recorded). ``raw``, a
    list, receives the whole 'ls-files -s -z' output (write_settled compares it after a failed write)."""
    res = r.run(repo, ["ls-files", "-s", "-z"], ok=(0,), final=final)
    if not res.answered:
        return None
    if raw is not None:
        raw.append(res.out)
    links = {}
    for x in res.out.split("\0"):
        if not x:
            continue
        meta, _, path = x.partition("\t")
        f = meta.split()
        if len(f) == 3 and f[0] == "160000" and f[2] == "0":
            links[path] = f[1]
    return links


def head_gitlinks(r, repo):
    """{path: sha} of the gitlinks of HEAD's tree, or None when git gave no answer (recorded)."""
    res = r.run(repo, ["ls-tree", "-r", "-z", "HEAD"], ok=(0,))
    return parse_ls_tree(res.out) if res.answered else None


def tree_gitlinks(r, repo, target):
    """{path: sha} of the gitlinks of ``target``'s tree, or None when git gave no answer (recorded)."""
    res = r.run(repo, ["ls-tree", "-r", "-z", obj(target)], ok=(0,))
    return parse_ls_tree(res.out) if res.answered else None


def parse_config_z(out, suffix):
    """{name: value} from 'git config -z --get-regexp' output for keys submodule.<name>.<suffix>."""
    res = {}
    for x in out.split("\0"):
        key, _, value = x.partition("\n")
        if key.startswith("submodule.") and key.endswith("." + suffix):
            res[key[len("submodule."):-len(suffix) - 1]] = value
    return res


def update_strategies(r, repo):
    """{gitlink path: update strategy} that git would use for the submodules of ``repo`` (review round 6, RV5-7):
    submodule.<name>.update from the repository's config, else from .gitmodules; missing = 'checkout'. A command
    strategy (!...) is reported as 'command' (never its text). None when git gave no answer (recorded)."""
    gm = r.run(repo, ["config", "--file", ".gitmodules", "-z", "--get-regexp", r"^submodule\..*\.(path|update)$"],
               ok=(0, 1))
    cf = r.run(repo, ["config", "-z", "--get-regexp", r"^submodule\..*\.update$"], ok=(0, 1))
    if not gm.answered or not cf.answered:
        return None
    paths = parse_config_z(gm.out, "path")
    upd = parse_config_z(gm.out, "update")
    upd.update(parse_config_z(cf.out, "update"))
    res = {}
    for name, path in paths.items():
        v = (upd.get(name) or "checkout").strip()
        res[path] = "command" if v.startswith("!") else v.lower()
    return res


def marker_path(gitdir):
    return os.path.join(gitdir, WRITE_MARKER) if gitdir and os.path.isabs(gitdir) else None


def read_marker(gitdir):
    """The op of an earlier write that did not end normally (its marker is present), 'unknown' when the marker
    cannot be read, None when there is no marker (review round 6, RV5-1) or the object at its path is not a
    regular file (review round 9: never opened; in_progress reports it and blocks the git dir)."""
    path = marker_path(gitdir)
    if not path:
        return None
    status, data = fs_read(path, 4096)
    if status == "absent" or status.startswith("not-regular:"):  # not a marker: in_progress reports it (RV8-2/4)
        return None
    if status != "ok":
        return "unknown"
    try:
        op = json.loads(data.decode("utf-8", "replace")).get("op")
    except (ValueError, AttributeError):
        return "unknown"
    return op if op in ("fast-forward", "advance-pin", "follow-pin", "stage-pin") else "unknown"


def marker_write_id(gitdir):
    """The write id recorded in ``gitdir``'s marker, read now; None when there is no marker or it is unreadable."""
    path = marker_path(gitdir)
    if not path:
        return None
    status, data = fs_read(path, 4096)  # never blocks (RV8-2): a FIFO here is "not ours", never waited on
    if status != "ok":
        return None
    try:
        wid = json.loads(data.decode("utf-8", "replace")).get("write_id")
    except (ValueError, AttributeError):
        return None
    return wid if isinstance(wid, str) and wid else None


def write_marker(gitdir, op, target, run_id, write_id=""):
    """CREATE the write-in-progress marker, exclusively (review round 8, RV7-1): MARKER_WRITTEN; MARKER_EXISTS when
    a marker (or anything else) is already at its path, which is never opened, overwritten or removed; or
    MARKER_UNWRITABLE. Only a file this call created is removed again when it cannot be written (a half marker
    would read as 'unknown' later). The write is started only after MARKER_WRITTEN."""
    path = marker_path(gitdir)
    if not path:
        return MARKER_UNWRITABLE
    got = fs_create_excl(path, json.dumps({"op": op, "target": target, "run_id": run_id, "write_id": write_id,
                                           "started": now_utc()}).encode())
    return {"written": MARKER_WRITTEN, "exists": MARKER_EXISTS}.get(got, MARKER_UNWRITABLE)


def clear_marker(gitdir):
    """Remove the marker of ``gitdir``: the fs_remove status ('removed', 'absent', 'not-regular:<kind>', ...). Only a
    regular file is ever removed; it never raises (review round 9, RV8-4)."""
    path = marker_path(gitdir)
    return fs_remove(path) if path else "absent"


class WriteToken:
    """The live write of one git dir (begin_write): its marker on disk carries ``write_id``."""
    def __init__(self, gitdir, op, write_id):
        self.gitdir = gitdir
        self.op = op
        self.write_id = write_id


def gitdir_write_block(r, gitdir):
    """Why NO write may go into ``gitdir`` now, or None (review round 8, RV7-1), read NOW: an unknown git dir (not
    inspected in this run: its common dir and branch are not known, so its locks cannot be checked); its marker state
    in this run is unresolved (an earlier write of this run was killed or interrupted, is still in progress, or a
    marker of an earlier run was kept); a marker (or anything else) is at the marker path; an operation or ANY lock
    git takes for an engine write is present (review round 9, RV8-1: in the git dir AND the common dir)."""
    site = r.site(gitdir) if marker_path(gitdir) else None
    if site is None:
        return "unknown-git-dir"
    state = r.gd_state(gitdir)
    if state in GD_UNRESOLVED:
        return "earlier-write-unresolved:" + state
    if path_kind(marker_path(gitdir)) != "absent":
        return "write-marker-present"
    busy = in_progress(gitdir, site[0], site[1])
    if busy:
        return "in-progress:" + ",".join(busy)
    return None


def begin_write(r, gitdir, op, target, final=False):
    """The ONE way a write gets its marker (review round 8, RV7-1). Returns (token, None) when the marker was
    created for this write, else (None, why): why None means run() refuses the write right now (a stop signal, the
    deadline; it then reports the refusal itself); 'blocked:...' means the git dir must not receive this write."""
    if r.write_refused_now(final=final):
        return None, None
    why = gitdir_write_block(r, gitdir)
    if why:
        return None, "blocked:" + why
    with r.lock:
        r.writes += 1
        write_id = "%s:%d:%d" % (r.run_id, os.getpid(), r.writes)
    got = write_marker(gitdir, op, target, r.run_id, write_id)
    if got == MARKER_EXISTS:
        return None, "blocked:write-marker-present"
    if got != MARKER_WRITTEN:
        return None, "blocked:write-marker-unwritable"
    if not r.gd_move(gitdir, GD_WRITING):  # unreachable while gitdir_write_block holds; never a silent write
        clear_marker(gitdir)
        return None, "blocked:earlier-write-unresolved:" + r.gd_state(gitdir)
    return WriteToken(gitdir, op, write_id), None


def end_write(r, token, res, settled=True):
    """The end of a write that held ``token``. The marker is removed (GD_CLEARED) only when no git process was
    started, or git answered AND the repository is SETTLED (``settled``, write_settled: review round 9, RV8-1, git
    can answer a failure after it already rewrote the index and work tree), and only while the marker on disk is
    still this write's own. An answered write that left changes -> GD_INTERRUPTED; the write's own limit ended it ->
    GD_KILLED; any other end (a signal, an undeclared status, malformed output) -> GD_INTERRUPTED. Every case but
    the first keeps the marker, so a later run attributes what the git dir shows to that write."""
    if token is None:
        return
    if res.why in TOKEN_REFUSALS:  # the marker on disk is not (or no longer) this write's: never touched
        r.gd_move(token.gitdir, GD_INTERRUPTED)
    elif (res.answered and settled) or not res.started:
        if marker_write_id(token.gitdir) == token.write_id:
            clear_marker(token.gitdir)
        r.gd_move(token.gitdir, GD_CLEARED)
    elif res.answered:  # git answered, but the repository shows what the write left (half-applied): marker kept
        r.gd_move(token.gitdir, GD_INTERRUPTED)
    elif res.why == "write-killed":
        r.gd_move(token.gitdir, GD_KILLED)
    else:
        r.gd_move(token.gitdir, GD_INTERRUPTED)


def locks_left(gitdir, branch, common=None, git_sub=None):
    """Lock files git takes for a write (``git_sub``, or any engine write) that are present now in ``gitdir`` and
    its common dir, as labels (lock_paths)."""
    if not gitdir:
        return []
    return [n for n, path in lock_paths(gitdir, common, branch, git_sub) if path_kind(path) != "absent"]


def write_settled(r, repo, op, target, res, pre_index):
    """True when the write ``op`` that git answered with ``res`` left the repository showing nothing of a half-done
    write (review round 9, RV8-1; ground truth: a merge or checkout that meets a held HEAD.lock or branch ref lock
    rewrites the index and work tree, then exits 128). Exit 0: git completed the write (step 6 verifies where HEAD
    is; a move by someone else is reported there, never attributed to this write). A FAILURE (exit != 0): HEAD is
    unchanged and the index is byte-for-byte what it was before the write (``pre_index``, the 'ls-files -s -z'
    output read in step 3b); a failed stage-pin: the gitlink at its path is still the recorded one. Lock files are
    NOT read here: git removes its own locks before it answers, so a lock present now is another process's, and the
    next run's in_progress reports it either way. Every read is final; one that does not answer is NOT settled.
    Limit (stated; review round 10 tried and withdrew a 'git status must stay empty' check): a failed write that
    changed the work tree but not the index cannot be told from a user's edit made between step 1 and the write
    (the autostash race fixture is such an edit: blaming it on the write would be a false positive). Telling them
    apart needs the changed files' content compared with the target tree: tracked as CON-PENDINGsync1, not done here."""
    rec = repo.rec
    if res.rc == 0:
        return True
    if op == "stage-pin":
        links = index_gitlinks(r, repo.parent.abspath, final=True)
        return links is not None and links.get(rec["path_in_parent"]) == rec.get("recorded_gitlink")
    head = read_head(r, repo.abspath, final=True)
    if head is None or head != rec.get("head_before"):
        return False
    now = r.run(repo.abspath, ["ls-files", "-s", "-z"], ok=(0,), final=True)
    return now.answered and pre_index is not None and now.out == pre_index


# ───────────────────────────── per-repository work ─────────────────────────────
class Repo:
    def __init__(self, abspath, rel, depth, parent):
        self.abspath = abspath
        self.rel = rel
        self.depth = depth
        self.parent = parent
        self.rec = {"path": rel, "depth": depth, "parent": parent.rel if parent else None,
                    "kind": "root" if parent is None else "submodule"}


def inspect_local(r, repo, branch):
    rec = repo.rec
    p = repo.abspath
    rec["initialised"] = True
    rec["head_before"] = read_head(r, p)
    if rec["head_before"] is None:
        rec["head_unreadable"] = True
    rec["branch"] = read_branch(r, p)[1]
    # one call for the three paths (the per-repository call count is a guarded budget, tests/sync/test_perf.sh);
    # the common dir is where this repository's run lock lives (RV4-11)
    paths = (g_out(r, p, ["rev-parse", "--absolute-git-dir", "--path-format=absolute", "--git-path", "FETCH_HEAD",
                          "--git-common-dir"], ok=(0,), want=THREE_ABS_PATHS_RE) or "").split("\n")
    gitdir, fetch_head, common = (paths[0], paths[1], paths[2]) if len(paths) == 3 and all(paths) else ("", "", "")
    rec["_gitdir"] = gitdir
    rec["_common_dir"] = common
    if gitdir:
        r.register_site(gitdir, common, rec["branch"])
    rec["in_progress"] = in_progress(gitdir, common, rec["branch"]) if gitdir else ["unknown-git-dir"]
    earlier = read_marker(gitdir)
    if earlier:
        rec["write_interrupted_earlier"] = earlier
    st = r.run(p, STATUS_ARGS, ok=(0,))
    rec["dirty"] = (not st.answered) or bool(st.out.strip())
    names = g_out(r, p, ["remote"], ok=(0,))
    remotes = []
    for n in sorted((names or "").split()):
        if not safe_remote(n):
            remotes.append({"name": redact(n), "url": "", "fetch": "skipped", "state": "invalid-name"})
            continue
        url = g_out(r, p, ["config", "--get", "remote.%s.url" % n], ok=(0, 1)) or ""
        register_secret(url)  # before any fetch thread starts: a secret git repeats without its URL is removed too
        # "name" is what the report shows (redacted, n-2); "_name" is the real name every git call uses
        remotes.append({"name": redact(n), "_name": n, "url": redact_url(url), "_url": url, "fetch": "not-run"})
    rec["remotes"] = remotes
    rec["_branch_wanted"] = branch
    rec["_fetch_head"] = fetch_head
    # F9: a repository (or user) core.sshCommand is honoured; otherwise the engine's BatchMode ssh is used. An ssh
    # program the user configured is the user's (it may prompt on its own terminal); the engine's own calls have no
    # controlling terminal (new session), stdin /dev/null, no askpass program (GIT_ASKPASS empty, core.askPass
    # empty, SSH_ASKPASS dropped, SSH_ASKPASS_REQUIRE=never). A credential helper still runs (by design: it is how
    # a user authenticates without a prompt).
    res = r.run(p, ["config", "--get", "core.sshCommand"], ok=(0, 1))
    rec["ssh"] = "core.sshCommand" if res.text() else "engine-default"


FETCH_FAILURE_CLASSES = (
    ("auth", ("authentication failed", "permission denied", "could not read username", "could not read password",
              "access denied", "invalid credentials", "http 401", "http 403", "error: 403")),
    ("not-found", ("repository not found", "does not appear to be a git repository", "not found", "http 404",
                   "no such file or directory")),
    ("network", ("could not resolve host", "connection refused", "connection timed out", "network is unreachable",
                 "no route to host", "could not read from remote", "unable to access", "failed to connect",
                 "connection reset", "connection closed")),
)
TAG_REJECTED = ("would clobber existing tag",)


def classify_fetch_failure(rc, err):
    """A closed label for a fetch that answered with a failure exit status (F12); the redacted error line is
    kept beside it. A fetch that gave no answer is labelled by its ``why`` instead (timeout, deadline, ...)."""
    e = (err or "").lower()
    if rc == 1 and any(n in e for n in TAG_REJECTED):
        return "tag-rejected"
    for label, needles in FETCH_FAILURE_CLASSES:
        if any(n in e for n in needles):
            return label
    return "other"


def fetched_branches(path):
    """Branch names the last fetch reported in FETCH_HEAD (``path``), or None when it cannot be read."""
    if not path or not os.path.isabs(path):
        return None
    status, raw = fs_read(path, FETCH_HEAD_CAP)  # bounded memory (RV4-4), never blocks on a FIFO (round 9)
    if status != "ok":  # an oversized FETCH_HEAD is unread, never half-read
        return None
    data = raw.decode("utf-8", "replace")
    names = set()
    for line in data.splitlines():
        m = re.match(r"^[0-9a-f]{40,64}\t[^\t]*\tbranch '(.*)' of ", line)
        if m:
            names.add(m.group(1))
    return names


def fetch_repo(r, repo, tags):
    for rem in repo.rec["remotes"]:
        if rem.get("state") == "invalid-name":
            continue
        res = r.run(repo.abspath, fetch_args(rem["_name"], tags), ok=(0, 1, 128), network=True,
                    repo_ssh=repo.rec.get("ssh") == "core.sshCommand")
        if not res.answered:
            # timeout / deadline: the remote did not answer in time (its state, unreachable / not fetched);
            # any other no-answer (a signal, an unexpected status, ...) is recorded by r.run and makes the run BLIND
            rem["fetch"] = res.why if res.why in TIME_WHYS else \
                "not-fetched-interrupted" if res.why in STOP_WHYS else "no-answer"
            rem["fetch_failure"] = res.why
            rem["fetch_error"] = redact(res.err).strip()[-300:] or res.why
            continue
        rem["fetch_rc"] = res.rc
        if res.rc != 0:
            rem["fetch_failure"] = classify_fetch_failure(res.rc, res.err)
            lines = [l for l in redact(res.err).splitlines() if l.strip()]
            rem["fetch_error"] = lines[-1][:300] if lines else "git exit %d" % res.rc
            if rem["fetch_failure"] != "tag-rejected":
                rem["fetch"] = "failed"
                continue
            # a moved upstream tag was refused (never forced): the remote answered and its branches were
            # fetched; the rejection is reported (tag-rejected, attention) and blocks integration (m-4)
            rem["fetch"] = "tag-rejected"
        else:
            rem["fetch"] = "ok"
        # --no-prune keeps a stale refs/remotes/<r>/<branch> after upstream deleted it: FETCH_HEAD says
        # which branches the remote really has now (never a delete of our own).
        got = fetched_branches(repo.rec.get("_fetch_head") or "")
        if got is None:
            r.no_answer(repo.abspath, "fetch", "fetch-head-unreadable")
        elif repo.rec.get("_branch_wanted", "main") not in got:
            rem["branch_gone_upstream"] = True


def resolve_ref_exact(r, repo, ref, notes=None):
    """(GitResult, commit id or None) of the EXACT ref ``ref`` (review round 12, RV11-1). for-each-ref lists the
    ref and its children; only a line whose refname IS ``ref`` counts, so no lookup rule (refs/tags/<name>,
    refs/heads/<name>, ...) can stand in for an absent ref. A ref to a commit gives its id; to an annotated tag, the
    commit the tag peels to; to anything else, None (the 'rev-parse <ref>^{commit}' answer 'no such commit').
    A SYMBOLIC ref at the exact name (review round 13, RV12-1) gives None and, when ``notes`` is a dict,
    notes['symbolic'] = its target: its id is the target's (a local branch, a tag), never the remote's.
    Output of the wrong shape, or two lines for the one ref, is NO ANSWER (recorded), never 'absent'."""
    res = r.run(repo, ["for-each-ref", "--format=" + FER_EXACT_FORMAT, ref], ok=(0,))
    if not res.answered:
        return res, None
    rows = [x.split("\0") for x in res.out.split("\n") if x]
    if any(len(x) != 6 for x in rows):
        r.no_answer(repo, "for-each-ref", "malformed-output")
        return GitResult(False, res.rc, res.out, res.err, "malformed-output"), None
    hits = [x for x in rows if x[0] == ref]
    if len(hits) > 1 or any(not SHA_RE.match(x[3]) or (x[5] and not SHA_RE.match(x[5])) for x in hits):
        r.no_answer(repo, "for-each-ref", "malformed-output")
        return GitResult(False, res.rc, res.out, res.err, "malformed-output"), None
    if not hits:
        return res, None
    _, symref, kind, sha, pkind, psha = hits[0]
    if symref:
        if isinstance(notes, dict):
            notes["symbolic"] = symref
        return res, None
    if kind == "commit":
        return res, sha
    if kind == "tag" and pkind == "commit":
        return res, psha
    return res, None


def evaluate_upstream(r, repo, branch):
    rec = repo.rec
    p = repo.abspath
    mains = {}
    unknown = False
    for rem in rec["remotes"]:
        if rem.get("state") == "invalid-name":
            continue
        notes = {}
        res, sha = resolve_ref_exact(r, p, "refs/remotes/%s/%s" % (rem["_name"], branch), notes)
        if not res.answered:  # no answer is not "no main" (review round 6, RV5-6): the remote's state is unknown
            rem["main_sha"] = None
            rem["state"] = rem["fetch"] if rem.get("fetch") in ("not-fetched-interrupted", "deadline") else "unknown"
            if rem["state"] == "deadline":
                rem["state"] = "not-fetched-deadline"
            unknown = True
            continue
        if rem.get("branch_gone_upstream"):
            # the remote no longer has the branch; a remote-tracking ref we still hold (kept by --no-prune,
            # never deleted by us) is stale and is reported, a never-existing one is not a finding
            rem["stale_tracking_ref"] = bool(sha)
            sha = None
        rem["main_sha"] = sha
        if notes.get("symbolic"):  # review round 13 (RV12-1): never an upstream; reported by name, never silent
            rem["symbolic_tracking_ref"] = True
        if rem.get("fetch") in ("failed", "timeout", "no-answer"):
            rem["state"] = "unreachable"
        elif rem.get("fetch") == "deadline":
            rem["state"] = "not-fetched-deadline"
        elif rem.get("fetch") == "not-fetched-interrupted":
            rem["state"] = "not-fetched-interrupted"
        elif sha is None:
            rem["state"] = "no-main"
        if sha:
            mains[rem["name"]] = sha
    newest = pick_newest(list(mains.values()), lambda a, b: bool(is_ancestor(r, p, a, b)))
    rec["upstream_state"] = ("unknown" if unknown else "none") if not mains else \
        ("linear" if newest else "upstreams-diverged")
    rec["target"] = newest
    head = rec.get("head_before")
    for rem in rec["remotes"]:
        sha = rem.get("main_sha")
        if not sha or not head:
            continue
        c = count_range(r, p, head, sha)
        if c is None:
            rem.setdefault("state", "unknown")
            continue
        rem["ahead"], rem["behind"] = c
        if rem.get("state") not in ("unreachable", "not-fetched-deadline", "not-fetched-interrupted"):
            rem["state"] = classify(*c)
    if head and newest:
        c = count_range(r, p, head, newest)
        rec["local_vs_target"] = classify(*c) if c else "unknown"
        rec["behind_target"] = c[1] if c else None
    else:
        rec["local_vs_target"] = "no-target"
        rec["behind_target"] = None


def contained_refs(r, repo, res):
    """The NON-symbolic refnames of a 'for-each-ref --contains --format=FER_CONTAINS_FORMAT refs/remotes' answer
    (review round 13, RV12-1), or None when there is no answer. A symbolic line names its target's history under
    its own name and is dropped; a line of the wrong shape is no answer (recorded), never "no ref"."""
    if not res.answered:
        return None
    rows = [x.split("\0") for x in res.out.split("\n") if x]
    if any(len(x) != 2 or not x[0].startswith("refs/remotes/") for x in rows):
        r.no_answer(repo, "for-each-ref", "malformed-output")
        return None
    return [x[0] for x in rows if not x[1]]


def evaluate_pin(r, repo, gitlink, own_orgs):
    """Pin state of a submodule repo against its recorded gitlink (from the parent)."""
    rec = repo.rec
    pin = {"gitlink": gitlink}
    url = ""
    for rem in rec.get("remotes", []):
        if rem.get("_name") == "origin":
            url = rem.get("_url", "")
    if not url and rec.get("remotes"):
        url = rec["remotes"][0].get("_url", "")
    rec["own_org"] = is_own_org(url, own_orgs) if url else False
    p = repo.abspath
    present = commit_present(r, p, gitlink)
    if present is None:
        pin["state"] = "unknown"
    elif not present:
        pin["state"] = "unfetchable"
    else:
        res = r.run(p, ["for-each-ref", "--contains", obj(gitlink), "--format=" + FER_CONTAINS_FORMAT, "refs/remotes"],
                    ok=(0,))
        refs = contained_refs(r, p, res)
        branch = rec.get("_branch_wanted", "main")
        # exact match (F13): refs/remotes/<remote>/feature/main is NOT <remote>'s main
        mains = {"refs/remotes/%s/%s" % (m.get("_name"), branch) for m in rec.get("remotes", [])
                 if m.get("state") != "invalid-name" and not m.get("branch_gone_upstream")}
        target = rec.get("target")
        # RV13-5: only a ref under a CONFIGURED remote is "on a remote" (a stale refs/remotes/ghost/x of a remote
        # that is not configured is not fetchable by anyone who clones this repository's configuration)
        configured = {str(m.get("_name")) for m in rec.get("remotes", []) if m.get("_name")}
        if refs is not None:
            refs = [x for x in refs if any(x.startswith("refs/remotes/%s/" % n) for n in configured)]
        if refs is None:
            pin["state"] = "unknown"
        elif not refs:
            pin["state"] = "not-on-any-remote"
        elif not [x for x in refs if x in mains]:
            pin["state"] = "not-on-main"
        elif target and gitlink == target:
            pin["state"] = "at-main"
        elif target and is_ancestor(r, p, gitlink, target):
            pin["state"] = "behind-main"
            c = count_range(r, p, gitlink, target)
            pin["behind_main"] = c[1] if c else None
        else:
            pin["state"] = "on-main-not-newest"
    head = rec.get("head_before")
    pin["checkout"] = "at-pin" if head == gitlink else "drifted"
    rec["pin"] = pin


def reasons_for(rec, strict_pins, branch):
    reasons = []
    if not rec.get("initialised"):
        st = rec.get("pin", {}).get("state")
        # absent / uninitialised are ordinary states (attention only with --strict-pins); a path that is not a
        # directory, a cycle and an unreadable submodule always need attention (review round 3, F1)
        if (st in ("not-a-directory", "cycle", "unreadable", "unsafe-path", "outside-parent")
                or (strict_pins and st in ("absent", "uninitialised"))):
            reasons.append("pin-" + st)
        return reasons
    if rec.get("depth_limited_gitlinks"):
        reasons.append("depth-limited")
    if rec.get("kept_on_branch"):
        reasons.append("kept-on-branch:" + rec["kept_on_branch"])
    earlier = rec.get("write_interrupted_earlier")
    leftovers = bool(rec.get("dirty") or rec.get("in_progress"))
    if earlier and leftovers:  # what the tree shows is attributed to that write, never blamed on the user (RV5-1)
        reasons.append("write-interrupted-earlier:" + earlier)
    tail = "-since-write-interrupted" if earlier and leftovers else ""
    if rec.get("dirty"):
        reasons.append("dirty-tree" + tail)
    reasons += [("in-progress%s:" % tail) + x for x in rec.get("in_progress", [])]
    if rec.get("write_killed"):
        reasons.append("write-killed:" + rec["write_killed"])
    if rec.get("write_left_changes"):
        reasons.append("write-left-changes:" + rec["write_left_changes"])
    if rec.get("stage_pin_not_exact"):
        reasons.append("stage-pin-not-exact:" + rec["stage_pin_not_exact"])
    if rec.get("not_followed"):
        reasons.append("not-followed:update-" + rec["not_followed"])
    if rec.get("head_unreadable"):
        reasons.append("head-unreadable")
    for rem in rec.get("remotes", []):
        if rem.get("state") == "unreachable":
            reasons.append("unreachable:" + rem["name"])
        elif rem.get("state") == "invalid-name":
            reasons.append("invalid-remote-name")
        if rem.get("fetch") == "tag-rejected":
            reasons.append("tag-rejected:" + rem["name"])
        if rem.get("stale_tracking_ref"):
            reasons.append("upstream-branch-gone:" + rem["name"])
        if rem.get("symbolic_tracking_ref"):
            reasons.append("symbolic-tracking-ref:" + rem["name"])
    if rec.get("upstream_state") == "upstreams-diverged":
        reasons.append("upstreams-diverged")
    if rec["kind"] == "root" and rec.get("branch") != branch:
        reasons.append("root-not-on-" + branch)
    if rec.get("branch") == branch and rec.get("upstream_state") == "none":
        reasons.append("no-upstream-" + branch)  # no remote, or no remote has <branch> (m-2): never "current"
    if rec.get("branch") == branch and rec.get("local_vs_target") in ("diverged", "ahead"):
        reasons.append("local-" + rec["local_vs_target"])
    pin = rec.get("pin")
    if pin:
        if pin.get("state") in ("unfetchable", "not-on-any-remote", "not-on-main"):
            reasons.append("pin-" + pin["state"])
        if pin.get("checkout") == "drifted" and rec.get("branch") is None:
            reasons.append("pin-checkout-drifted")
    if rec.get("ignored_clobber"):
        reasons.append("ignored-file-would-be-overwritten")
    reasons += ["gitlink-modified:" + x for x in rec.get("gitlink_modified", [])]
    # a gitlink the user STAGED (index differs from HEAD's tree) before this run: never replaced (RV4-2)
    reasons += ["gitlink-staged:" + x for x in rec.get("gitlink_staged", [])]
    # a write the guarded writer refused because something changed after inspection (RV4-1): never silent
    reasons += ["write-" + x["why"] for x in rec.get("actions", []) if str(x.get("why", "")).startswith("blocked:")]
    return reasons


def has_update(rec):
    if not rec.get("initialised"):
        return False
    if rec.get("branch") and rec.get("local_vs_target") == "behind":
        return True
    pin = rec.get("pin") or {}
    if pin.get("state") == "behind-main" and rec.get("own_org"):
        return True
    return False


# ───────────────────────────── discovery ─────────────────────────────
def discover(r, root, max_depth):
    """Pre-order list of Repo objects; uninitialised submodules get a record but no children."""
    out = []
    seen = set()

    def walk(repo):
        out.append(repo)
        real = os.path.realpath(repo.abspath)
        if real in seen:  # the same repository reached twice: never inspected twice, always reported
            repo.rec["initialised"] = False
            repo.rec["pin"] = {"gitlink": repo.rec.get("recorded_gitlink"), "state": "cycle"}
            return
        seen.add(real)
        links = index_gitlinks(r, repo.abspath)  # no answer (None): recorded, this repository is blind
        if repo.depth >= max_depth:
            if links:  # submodules below the depth limit are never silently out of the report
                repo.rec["depth_limited_gitlinks"] = len(links)
            return
        links = links or {}  # no answer: no children (the no-answer is recorded, the repository is blind)
        if links:  # a gitlink staged in the index that HEAD's tree does not record: the user's (RV4-2)
            heads = head_gitlinks(r, repo.abspath)
            if heads is not None:
                repo.rec["gitlink_staged"] = sorted(redact(x) for x in links if heads.get(x) != links[x])
        real_parent = os.path.realpath(repo.abspath)
        for path in sorted(links):
            child_abs = os.path.join(repo.abspath, path)
            rel = path if repo.rel == "." else repo.rel + "/" + path
            child = Repo(child_abs, rel, repo.depth + 1, repo)
            child.rec["recorded_gitlink"] = links[path]
            child.rec["path_in_parent"] = path
            if not safe_relpath(path):  # never used, never omitted (RV4-13)
                state = "unsafe-path"
            elif not (os.path.realpath(os.path.dirname(child_abs)) + os.sep).startswith(real_parent + os.sep):
                # a DIRECTORY on the way is a symbolic link that leaves the parent (RV4-15); the last component
                # itself is probed with lstat below (a link there is not-a-directory, never followed)
                state = "outside-parent"
            else:
                state = probe_child(r, child_abs)
            if state == "repo":
                child.rec["initialised"] = True
                walk(child)
            else:  # absent / uninitialised / not-a-directory / unreadable (a no-answer, recorded for the child)
                child.rec["initialised"] = False
                child.rec["pin"] = {"gitlink": links[path], "state": state}
                out.append(child)

    root_repo = Repo(root, ".", 0, None)
    root_repo.rec["initialised"] = True
    walk(root_repo)
    return out


# ───────────────────────────── integration ─────────────────────────────
BLOCKING_PREFIXES = ("dirty-tree", "in-progress", "upstreams-diverged", "local-", "unreachable", "invalid-remote",
                     "root-not-on-", "head-unreadable", "tag-rejected", "no-upstream-",
                     "write-blocked", "head-changed-during-run", "write-interrupted-earlier", "write-killed")
# gitlink-staged:<path> is attention, never blocking for the whole repository: the staged path itself is protected
# where it matters, at write time (write_git step 3: an advance or follow over a staged value is refused), and a
# pin this engine staged in an earlier --advance-pins run must not stop the rest of the tree (RV4-2)


def integrate(r, repos, branch, advance_pins, advance_third_party, strict_pins, consent):
    """Pre-order: parents move first, their clean children follow the new recorded gitlink."""
    blocked_paths = set()
    for repo in repos:
        rec = repo.rec
        p = repo.abspath
        rec.setdefault("actions", [])
        if not rec.get("initialised"):
            continue
        if STOP_REQUESTED.is_set():  # a stop signal: no further write starts (RV4-5)
            rec["actions"].append({"op": "none", "why": "interrupted"})
            continue
        if repo.parent is not None and repo.parent.rel in blocked_paths:
            rec["actions"].append({"op": "none", "why": "parent-not-integrated"})
            blocked_paths.add(repo.rel)
            continue
        reasons = reasons_for(rec, strict_pins, branch)
        # root-not-on-<branch> blocks the whole tree (F7): no pin is staged into a topic branch's index
        local_block = [x for x in reasons if x.startswith(BLOCKING_PREFIXES)]
        if r.unresolved_for(p):
            local_block.append("unresolved")
        if local_block:
            rec["actions"].append({"op": "none", "why": ",".join(local_block)})
            blocked_paths.add(repo.rel)
            continue
        moved = bool(rec.get("followed"))  # it followed its own parent's new gitlink earlier in this run
        if rec.get("branch") == branch:
            if rec.get("local_vs_target") == "behind" and consent.get("integrate"):
                res = write_git(r, repo, "fast-forward", rec["target"])
                if res != "done":
                    blocked_paths.add(repo.rel)
                    continue
                moved = True
                if repo.parent is not None:  # F11: the parent's work tree now shows a modified gitlink
                    repo.parent.rec.setdefault("gitlink_modified", []).append(rec["path_in_parent"])
        elif repo.parent is not None:
            pin = rec.get("pin") or {}
            want = (advance_pins and consent.get("pins") and not rec.get("followed") and pin.get("state") == "behind-main"
                    and pin.get("checkout") == "at-pin" and rec.get("head_before") == pin.get("gitlink")
                    and (rec.get("own_org") or advance_third_party))
            if want and rec.get("branch") is not None:
                # a submodule checked out on a local branch is never detached (as for follow-pin; review round 3, F3)
                rec["actions"].append({"op": "none", "why": "advance-skipped:submodule-on-branch"})
                rec["kept_on_branch"] = "advance-pin"
            elif want and not_followed(r, repo, "advance-skipped"):
                pass  # the submodule's update strategy is not checkout: never checked out by the engine (RV5-7)
            elif want:
                res = write_git(r, repo, "advance-pin", rec["target"])
                if res != "done":
                    blocked_paths.add(repo.rel)
                    continue
                moved = True
        # only a parent that moved in THIS run follows, never after a stop; a parent without initialised children
        # reads nothing more (review round 6: no read after the deadline that has nothing to decide)
        if moved and not STOP_REQUESTED.is_set() and any(c.parent is repo and c.rec.get("initialised") for c in repos):
            follow_children(r, repo, repos, consent)
    # head_after is read for EVERY initialised repository, after the whole pass (review round 3, F2): a repository
    # that followed its parent, or whose write answered nothing or failed half-way, and was then skipped above, is
    # still read; an unread head is a no-answer (recorded by read_head), never a copy of head_before
    for repo in repos:
        if repo.rec.get("initialised"):
            repo.rec["head_after"] = read_head(r, repo.abspath, final=True)
            if repo.rec["head_after"] is None:
                repo.rec["head_unreadable"] = True


def index_entries(raw):
    """{path: (mode, id, stage)} of every entry of an 'ls-files -s -z' output (paths are NUL-terminated, unquoted)."""
    out = {}
    for x in raw.split("\0"):
        if not x:
            continue
        meta, _, path = x.partition("\t")
        f = meta.split()
        out[(path, f[2] if len(f) == 3 else "?")] = tuple(f)
    return out


def entry_text(e):
    """'<mode> <id> <stage>' of one index entry from index_entries() (None: the entry did not exist)."""
    return None if e is None else " ".join(e)


def restore_command(parent_path, path, stage, before):
    """The exact command that puts back one index entry the engine's own add changed (review round 14, RV13-1).
    Never run by the engine: git's own case folding (core.ignoreCase) is what changed the entry, so the command pins
    core.ignoreCase=false and GIT_LITERAL_PATHSPECS and is left to the user. Stage 0 entries only; a conflict stage
    is reported, not restorable by one command."""
    if stage != "0":
        return None
    def q(text):  # POSIX single-quote quoting (no shlex: the gate allow-lists the imports)
        if text and re.match(r"[A-Za-z0-9@%+=:,./_-]+\Z", text):
            return text
        return "'" + text.replace("'", "'\"'\"'") + "'"
    base = "git -C %s -c core.ignoreCase=false" % q(parent_path)
    if before is None:
        return "GIT_LITERAL_PATHSPECS=1 %s rm --cached -- %s" % (base, q(path))
    return "%s update-index --cacheinfo %s,%s,%s" % (base, before[0], before[1], q(path))


def stage_pin_verified(r, repo, target, pre_raw, detail=None):
    """('exact', []) when the parent's index, read now, differs from ``pre_raw`` (its 'ls-files -s -z' before the
    add) in EXACTLY one entry: the gitlink at path_in_parent, now '160000 <target> 0' (review round 13, RV12-2).
    ('other-entries', paths) when anything else changed, ('not-staged', []) when the intended entry is not the target,
    ('no-answer', []) when the index could not be read (recorded). The generic guard for any grammar or config git
    applied to the path (pathspec patterns, magic, GIT_*_PATHSPECS, core.ignoreCase)."""
    raw = []
    if index_gitlinks(r, repo.parent.abspath, final=True, raw=raw) is None:
        return "no-answer", []
    before, after = index_entries(pre_raw), index_entries(raw[0])
    path = repo.rec["path_in_parent"]
    changed = sorted({k for k in set(before) | set(after) if before.get(k) != after.get(k)})
    others = sorted({k[0] for k in changed if k[0] != path})
    if others and detail is not None:
        # RV13-1: the value of EVERY other changed entry before and after the add, with the command that restores it
        for k in changed:
            if k[0] != path:
                detail.append({"path": redact(k[0]), "stage": k[1], "before": entry_text(before.get(k)),
                               "after": entry_text(after.get(k)),
                               "restore": restore_command(repo.parent.abspath, k[0], k[1], before.get(k))})
    if others:
        return "other-entries", others
    if after.get((path, "0")) != ("160000", target, "0") or [k for k in after if k[0] == path and k[1] != "0"]:
        return "not-staged", []
    return "exact", []


def write_git(r, repo, op, target):
    """The ONE guarded writer: every merge / checkout / add of the engine runs here, after the guards.
    op: 'fast-forward' (merge --ff-only), 'advance-pin' (checkout --detach, then stage the gitlink in the parent),
    'follow-pin' (checkout --detach). Returns 'done', 'blocked', 'failed' or 'no-answer'; records the action."""
    rec = repo.rec
    p = repo.abspath
    act = {"op": op, "to": target}
    rec.setdefault("actions", [])
    # 0. a repository with ANY call that did not answer in this run is never written: its record may hold a field
    #    that was never read (dirty, branch, in-progress, ...) and an unread field is not "clean" (review round 3:
    #    a follow-pin wrote a child whose own status had been killed). Checked here, so every write path has it.
    if r.unresolved_for(p):
        rec["actions"].append({"op": "none", "why": "unresolved:earlier-no-answer", "for": op})
        return "no-answer"
    # 1. the tree is still clean and no operation is in progress, read NOW (§11.4.84); a status that does not
    #    answer is never "clean" (review round 2, K11)
    st = r.run(p, STATUS_ARGS, ok=(0,))
    if not st.answered:
        rec["actions"].append({"op": "none", "why": "unresolved:status-recheck", "for": op})
        return "no-answer"
    busy = (in_progress(rec["_gitdir"], rec.get("_common_dir"), rec.get("branch")) if rec.get("_gitdir")
            else ["unknown-git-dir"])
    if st.out.strip() or busy:
        rec["actions"].append({"op": "none", "why": "blocked:tree-changed-before-write", "for": op})
        return "blocked"
    # 2. no ignored (expendable to git) file would be overwritten or removed (F4, review round 2 I-3)
    guard = clobber_guard(r, repo, target)
    if guard != "clear":
        return guard
    # 3. staging a gitlink: the parent's index AND its HEAD's tree must still record the gitlink this run discovered
    #    (a gitlink the user staged, or a commit the user made in the parent, is never overwritten; RV4-2)
    if op == "advance-pin":
        links = index_gitlinks(r, repo.parent.abspath)
        tree = head_gitlinks(r, repo.parent.abspath)
        if links is None or tree is None:
            rec["actions"].append({"op": "none", "why": "unresolved:parent-index", "for": op})
            return "no-answer"
        path = rec["path_in_parent"]
        if links.get(path) != rec.get("recorded_gitlink") or tree.get(path) != rec.get("recorded_gitlink"):
            rec["actions"].append({"op": "none", "why": "blocked:parent-index-changed", "for": op})
            return "blocked"
        # 3a. the parent's git dir must be able to take the stage-pin NOW, before the child is moved (review round 8,
        #    RV7-1): a sibling's killed or interrupted write, a marker, or a lock there blocks this advance whole
        pblock = gitdir_write_block(r, repo.parent.rec.get("_gitdir") or "")
        if pblock:
            rec["actions"].append({"op": "none", "why": "blocked:parent-" + pblock, "for": op})
            return "blocked"
    # 3b. a gitlink the user has STAGED in this repository (index differs from HEAD's tree), read NOW, that the
    #    move would change is never overwritten: blocked before git (review round 6, RV5-3; git itself would refuse
    #    the merge only half-way, as a failure)
    pre_index = []
    links = index_gitlinks(r, p, raw=pre_index)
    if links is None:
        rec["actions"].append({"op": "none", "why": "unresolved:staged-gitlinks", "for": op})
        return "no-answer"
    if links:
        heads = head_gitlinks(r, p)
        theirs = tree_gitlinks(r, p, target) if heads is not None else None
        if heads is None or theirs is None:
            rec["actions"].append({"op": "none", "why": "unresolved:staged-gitlinks", "for": op})
            return "no-answer"
        staged = [x for x in set(links) | set(heads) if links.get(x) != heads.get(x)]
        if [x for x in staged if theirs.get(x) != heads.get(x)]:
            rec["actions"].append({"op": "none", "why": "blocked:gitlink-staged-would-change", "for": op})
            return "blocked"
    # 4. the LAST checks, immediately before the write (RV4-1): HEAD and the symbolic ref, read NOW, must be what
    #    inspection saw. A user who committed, switched branch or checked out a branch after inspection is never
    #    overwritten: fast-forward needs the same branch, a pin write needs a detached HEAD. The remote target is a
    #    fixed object id and merge --ff-only itself proves it descends from HEAD; what remains is the window of
    #    milliseconds between these reads and git's own ref lock (stated in the manual, never claimed closed).
    head_now = read_head(r, p)
    if head_now is None or head_now != rec.get("head_before"):
        if r.unresolved_for(p):
            rec["actions"].append({"op": "none", "why": "unresolved:head-recheck", "for": op})
            return "no-answer"
        rec["actions"].append({"op": "none", "why": "blocked:head-changed-before-write", "for": op})
        return "blocked"
    kind, name = read_branch(r, p)
    if kind == "unknown":
        rec["actions"].append({"op": "none", "why": "unresolved:branch-recheck", "for": op})
        return "no-answer"
    if (op == "fast-forward" and (kind, name) != ("branch", rec.get("branch"))) or \
            (op != "fast-forward" and kind != "detached"):
        rec["actions"].append({"op": "none", "why": "blocked:branch-changed-before-write", "for": op})
        return "blocked"
    # 5. the write: the marker first (a write that does not end normally is attributed later), then git under the
    #    write's own limit (a stop signal, the per-call timeout and the run deadline never end it; RV5-1)
    #    Review round 8 (RV7-1): the marker's life is the git dir's state machine (begin_write / end_write). A
    #    write refused now (a stop signal, the deadline) gets no marker and run() reports the refusal; a git dir
    #    with an unresolved earlier write, a marker or a lock gets no write; the marker is created exclusively and
    #    only end_write of the write that created it removes it.
    gitdir = rec.get("_gitdir") or ""
    tok, why = begin_write(r, gitdir, op, target)
    if why:
        rec["actions"].append({"op": "none", "why": why, "for": op})
        return "blocked"
    if op == "fast-forward":
        res = r.run(p, ["merge", "--ff-only", obj(target)], ok=(0, 1, 128), write=True, token=tok)
    else:
        res = r.run(p, ["checkout", "--quiet", "--detach", obj(target)], ok=(0, 1, 128), write=True, token=tok)
    act["rc"] = res.rc
    act["error"] = redact(res.err).strip()[-300:] if (res.rc or not res.answered) else ""
    settled = write_settled(r, repo, op, target, res, pre_index[0] if pre_index else None) if res.answered else True
    end_write(r, tok, res, settled)
    if res.answered and not settled:  # git answered, the repository shows a half-done write (RV8-1): marker kept
        act["why"] = "write-left-changes:" + op
        act["locks_left"] = locks_left(gitdir, rec.get("branch"), rec.get("_common_dir"), OP_GIT[op])
        rec["actions"].append(act)
        rec["write_left_changes"] = op
        rec["failed"] = True
        return "failed"
    if res.why == "write-killed":
        act["why"] = "write-killed:" + op
        act["locks_left"] = locks_left(gitdir, rec.get("branch"), rec.get("_common_dir"))
        rec["actions"].append(act)
        rec["write_killed"] = op
        rec["failed"] = True
        return "failed"
    if not res.answered:
        act["why"] = "unresolved:" + str(res.why)
        rec["actions"].append(act)
        return "no-answer"
    if res.rc != 0:
        rec["actions"].append(act)
        rec["failed"] = True
        return "failed"
    rec["_wrote_to"] = target
    # 6. verify the write: HEAD is the target, and the branch (or the detached state) is still the one checked
    #    (final reads: they run even after a stop signal, so the record says what moved)
    after = read_head(r, p, final=True)
    kind2, name2 = read_branch(r, p, final=True)
    if after is None or kind2 == "unknown":
        act["why"] = "unresolved:post-write-verify"
        rec["actions"].append(act)
        return "no-answer"
    if after != target or (op == "fast-forward" and (kind2, name2) != ("branch", rec.get("branch"))) or \
            (op != "fast-forward" and kind2 != "detached"):
        act["why"] = "head-not-at-target-after-write" if after != target else "branch-changed-during-write"
        rec["actions"].append(act)
        rec["failed"] = True
        return "failed"
    if op == "advance-pin":
        # the second half of the same consented write: runs even after a stop signal (final); a stop signal never
        # ends it, only its own --write-timeout does (SIGTERM first, then SIGKILL; write-killed:stage-pin)
        pgitdir = repo.parent.rec.get("_gitdir") or ""
        # the parent's whole index, read NOW (review round 13, RV12-2): after the add, exactly one entry may differ
        pre_parent = []
        if index_gitlinks(r, repo.parent.abspath, final=True, raw=pre_parent) is None:
            act["why"] = "unresolved:stage-pin-pre-index"
            rec["actions"].append(act)
            return "no-answer"
        tok2, why2 = begin_write(r, pgitdir, "stage-pin", target, final=True)
        if why2:
            act["why"] = why2
            rec["actions"].append(act)
            rec["failed"] = True  # the child moved and its pin was not staged: never silent
            return "failed"
        res2 = r.run(repo.parent.abspath, ["add", "--", rec["path_in_parent"]], ok=(0, 128), write=True, final=True,
                     token=tok2)
        settled2 = write_settled(r, repo, "stage-pin", target, res2, None) if res2.answered else True
        end_write(r, tok2, res2, settled2)
        act["staged_rc"] = res2.rc
        if res2.answered and not settled2:
            act["why"] = "write-left-changes:stage-pin"
            act["locks_left"] = locks_left(pgitdir, None, repo.parent.rec.get("_common_dir"), "add")
            rec["actions"].append(act)
            repo.parent.rec["write_left_changes"] = "stage-pin"
            repo.parent.rec["failed"] = True
            rec["failed"] = True
            return "failed"
        if res2.why == "write-killed":
            act["why"] = "write-killed:stage-pin"
            act["locks_left"] = locks_left(pgitdir, None, repo.parent.rec.get("_common_dir"))
            rec["actions"].append(act)
            repo.parent.rec["write_killed"] = "stage-pin"
            repo.parent.rec["failed"] = True
            rec["failed"] = True
            return "failed"
        if not res2.answered or res2.rc != 0:
            act["error"] = redact(res2.err).strip()[-300:]
            if not res2.answered:  # the child moved, the pin was not staged: say why (review round 7)
                act["why"] = "unresolved:stage-pin:" + str(res2.why)
            rec["actions"].append(act)
            if res2.answered:
                rec["failed"] = True
                return "failed"
            return "no-answer"
        # git said 0: what did it stage? (review round 13, RV12-2) never "updated" on git's word alone
        detail = []
        verdict, others = stage_pin_verified(r, repo, target, pre_parent[0], detail)
        if verdict != "exact":
            act["why"] = ("unresolved:stage-pin-verify" if verdict == "no-answer" else "stage-pin-not-exact:" + verdict)
            if others:
                act["staged_other"] = [redact(x) for x in others[:20]]
                act["staged_other_detail"] = detail[:20]  # before / after / restore command, not restored by the engine
            rec["actions"].append(act)
            if verdict == "no-answer":
                return "no-answer"
            act["failed"] = True
            repo.parent.rec["stage_pin_not_exact"] = verdict
            repo.parent.rec["failed"] = True
            rec["failed"] = True
            return "failed"
    rec["actions"].append(act)
    return "done"


def ignored_clobbers(r, path, target):
    """Ignored, untracked paths in ``path`` that a move to ``target`` would overwrite or remove (git treats
    ignored files as expendable). [] = none, None = no answer (recorded; the caller blocks). Files are listed one
    by one (no --directory): a collapsed ``build/`` entry would falsely block a target that only adds
    ``build/x``, while each ignored file is checked against the target's files and directories."""
    res = r.run(path, ["ls-files", "-z", "--others", "--ignored", "--exclude-standard"], ok=(0,))
    if not res.answered:
        return None
    ignored = sorted({x.rstrip("/") for x in res.out.split("\0") if x.strip("/")})
    if not ignored:
        return []
    res = r.run(path, ["ls-tree", "-r", "-z", "--name-only", "--full-tree", obj(target)], ok=(0,))
    if not res.answered:
        return None
    files = {x for x in res.out.split("\0") if x}
    dirs = set()
    for f in files:
        parts = f.split("/")
        dirs.update("/".join(parts[:i]) for i in range(1, len(parts)))
    hits = []
    for e in ignored:
        parts = e.split("/")
        above = {"/".join(parts[:i]) for i in range(1, len(parts))}
        if e in files or e in dirs or (above & files):
            hits.append(e)
    return hits


def clobber_guard(r, repo, target):
    """'clear' when the move to ``target`` may go ahead; else records why and returns 'blocked' / 'no-answer'."""
    hits = ignored_clobbers(r, repo.abspath, target)
    if hits == []:
        return "clear"
    rec = repo.rec
    if hits is None:
        rec.setdefault("actions", []).append({"op": "none", "why": "unresolved:ignored-file-check"})
        return "no-answer"
    rec["ignored_clobber"] = [redact(x) for x in hits[:20]]
    rec.setdefault("actions", []).append({"op": "none", "why": "ignored-file-would-be-overwritten",
                                          "paths": rec["ignored_clobber"]})
    return "blocked"


def not_followed(r, child, label):
    """True (and recorded) when git itself would not check ``child`` out at a new pin: its update strategy, read
    from the parent, is not 'checkout' (none, merge, rebase or a command; review round 6, RV5-7). Read once per
    parent, only when a checkout is about to happen."""
    parent = child.parent
    if "_update_strategies" not in parent.rec:
        parent.rec["_update_strategies"] = update_strategies(r, parent.abspath)
    strategies = parent.rec["_update_strategies"]
    if strategies is None:
        child.rec.setdefault("actions", []).append({"op": "none", "why": "unresolved:update-strategy"})
        return True
    strategy = strategies.get(child.rec.get("path_in_parent"), "checkout")
    if strategy == "checkout":
        return False
    child.rec["not_followed"] = strategy if re.match(r"^[a-z]{1,20}$", strategy) else "other"
    child.rec.setdefault("actions", []).append({"op": "none", "why": "%s:update-%s" % (label, child.rec["not_followed"])})
    return True


def follow_children(r, repo, repos, consent):
    """After ``repo`` moved in this run, check its clean, at-old-pin children out at the gitlink HEAD now records.
    The new gitlinks are read from HEAD's tree (what the consented move committed), never from the index alone: a
    gitlink someone staged meanwhile is not followed (the index must agree with HEAD, §11.4.84)."""
    tree = head_gitlinks(r, repo.abspath)
    index = index_gitlinks(r, repo.abspath)
    for c in repos:
        if c.parent is not repo or not c.rec.get("initialised"):
            continue
        path = c.rec["path_in_parent"]
        old = c.rec.get("recorded_gitlink")
        if tree is None or index is None:
            c.rec.setdefault("actions", []).append({"op": "none", "why": "unresolved:parent-gitlinks"})
            continue
        new = tree.get(path)
        if not new or new == old:
            continue
        c.rec["recorded_gitlink_after"] = new
        if index.get(path) != new:
            c.rec.setdefault("actions", []).append({"op": "none", "why": "follow-skipped:index-differs"})
            continue
        if c.rec.get("branch"):
            c.rec.setdefault("actions", []).append({"op": "none", "why": "follow-skipped:submodule-on-branch"})
            c.rec["kept_on_branch"] = "follow-pin"
            continue
        if c.rec.get("head_before") != old or c.rec.get("dirty") or c.rec.get("in_progress"):
            c.rec.setdefault("actions", []).append({"op": "none", "why": "follow-skipped:drifted-or-dirty"})
            continue
        # A parent moves only by a fast-forward (consent "integrate") or a pin advance (consent "pins"), and this
        # function is reached only after such a move; following is part of that same consented move.
        if not (consent.get("integrate") or consent.get("pins")):
            continue
        if not_followed(r, c, "follow-skipped"):
            continue
        present = commit_present(r, c.abspath, new)
        if present is None:
            c.rec.setdefault("actions", []).append({"op": "none", "why": "unresolved:new-pin-check"})
            continue
        if not present:
            c.rec.setdefault("actions", []).append({"op": "none", "why": "follow-blocked:new-pin-unfetchable"})
            c.rec["failed"] = True
            continue
        if write_git(r, c, "follow-pin", new) == "done":
            c.rec["head_before_follow"] = c.rec.get("head_before")
            c.rec["followed"] = True


# ───────────────────────────── evidence ─────────────────────────────
VOLATILE = {"started", "ended", "duration_s", "run_id", "fetch_error", "out_dir", "root_abs", "git_calls",
            "jobs", "consent_source"}


def canonical(obj):
    if isinstance(obj, dict):
        return {k: canonical(v) for k, v in sorted(obj.items()) if k not in VOLATILE}
    if isinstance(obj, list):
        return [canonical(x) for x in obj]
    return obj


def canonical_sha256(report):
    data = json.dumps(canonical(report), sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(data.encode("ascii")).hexdigest()


TSV_COLS = ["path", "kind", "depth", "initialised", "branch", "head_before", "head_after", "target",
            "upstream_state", "local_vs_target", "pin_state", "pin_behind_main", "own_org", "result", "reasons",
            "remotes"]


def tsv_rows(report):
    rows = ["\t".join(TSV_COLS)]
    for rec in report["repos"]:
        pin = rec.get("pin") or {}
        rem = ",".join("%s=%s:%s/%s" % (x.get("name"), x.get("state", x.get("fetch")), x.get("ahead", "-"),
                                         x.get("behind", "-")) for x in rec.get("remotes", []))
        vals = [rec["path"], rec["kind"], str(rec["depth"]), str(bool(rec.get("initialised"))).lower(),
                rec.get("branch") or "-", rec.get("head_before") or "-", rec.get("head_after") or "-",
                rec.get("target") or "-", rec.get("upstream_state") or "-", rec.get("local_vs_target") or "-",
                pin.get("state") or "-", str(pin.get("behind_main", "-")), str(rec.get("own_org", "-")).lower(),
                rec.get("result", "-"), ",".join(rec.get("reasons", [])) or "-", rem or "-"]
        rows.append("\t".join(v.replace("\t", " ").replace("\n", " ") for v in vals))
    return "\n".join(rows) + "\n"


def evidence_file_ours(path, kind):
    """True when ``path`` does not exist, or is a regular file (not a symlink) that an earlier run of this engine
    wrote (n-3): a user's own file of that name is never overwritten."""
    status, raw = fs_read(path, 64 * 1024 * 1024)  # a symlink, a directory, a FIFO, ...: never ours, never opened
    if status == "absent":
        return True
    if status != "ok":
        return False
    text = raw.decode("utf-8", "replace")
    if kind == "tsv":
        return text.split("\n", 1)[0] == "\t".join(TSV_COLS)
    try:
        data = json.loads(text)
    except ValueError:
        return False
    return isinstance(data, dict) and data.get("schema") == SCHEMA


def control_needle(r, root):
    """§11.4.273: the instrument must see a known count before any zero is believed."""
    n = g_out(r, root, ["rev-list", "--count", "HEAD", "--"], ok=(0,), want=DIGITS_RE)
    lr = g_out(r, root, ["rev-list", "--left-right", "--count", "HEAD...HEAD", "--"], ok=(0,), want=TWO_COUNTS_RE)
    ok = bool(n and n.isdigit() and int(n) >= 1 and lr is not None and lr.split() == ["0", "0"])
    return {"probe": "rev-list --count HEAD >= 1 and HEAD...HEAD == 0 0", "count": n, "self_range": lr, "ok": ok}


# ───────────────────────────── interactive ─────────────────────────────
class Tty:
    """The controlling terminal, unbuffered (a tty is not seekable, so no "r+" text stream)."""
    def __init__(self):
        self.fd = fs_open_tty()

    def _write(self, text):
        os.write(self.fd, text.encode("utf-8", "replace"))

    def say(self, msg):
        self._write(redact(msg) + "\n")

    def ask(self, question):
        """y / yes = True. A stop signal (Ctrl-C at the prompt) ends the wait at once: False, and the run ends as
        INTERRUPTED (review round 6, RV5-5; a blocking read would wait for Enter, the signal handler only sets a
        flag)."""
        self._write(redact(question) + " [y/N] ")
        line = b""
        while len(line) < 256:
            if STOP_REQUESTED.is_set():
                self._write("\n")
                return False
            if not select.select([self.fd], [], [], 0.2)[0]:
                continue
            ch = os.read(self.fd, 1)
            if not ch or ch == b"\n":
                break
            line += ch
        return line.decode("utf-8", "replace").strip().lower() in ("y", "yes")


# ───────────────────────────── main ─────────────────────────────
class ArgParser(argparse.ArgumentParser):
    """argparse with a redacted error line: an unknown or invalid argument can be a URL with userinfo."""
    def error(self, message):
        self.print_usage(sys.stderr)
        print("%s: error: %s" % (self.prog, redact(message)), file=sys.stderr)
        sys.exit(EXIT_USAGE)


def parse_args(argv):
    ap = ArgParser(prog="sync_all_upstreams.sh", add_help=True,
                   description="Fetch every remote of a project tree and integrate by fast-forward only.")
    m = ap.add_mutually_exclusive_group()
    m.add_argument("--check", action="store_true", help="fetch, report, change nothing else (exit 3 when behind)")
    m.add_argument("--dry-run", action="store_true", help="no fetch, no change: plan from refs already present")
    m.add_argument("--apply", action="store_true", help="fetch, then fast-forward")
    ap.add_argument("--root", help="project root (default: the git top level of the current directory)")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--no-fetch", action="store_true", help="--check without network (offline)")
    ap.add_argument("--tags", action="store_true", help="also fetch tags")
    ap.add_argument("--advance-pins", action="store_true", help="stage own-org submodule pins at upstream main (no commit)")
    ap.add_argument("--advance-third-party", action="store_true", help="with --advance-pins: third-party pins too")
    ap.add_argument("--strict-pins", action="store_true", help="absent / uninitialised submodules need attention")
    ap.add_argument("--own-org", action="append", default=None, help="own organisation (repeatable)")
    ap.add_argument("--jobs", type=int, default=None)
    ap.add_argument("--timeout", type=int, default=120, help="seconds per network git call")
    ap.add_argument("--deadline", type=int, default=1800, help="seconds for the whole run (a write in flight is not ended by it)")
    ap.add_argument("--write-timeout", type=int, default=3600,
                    help="seconds one write (merge / checkout / add) may take before it is ended, SIGTERM first")
    ap.add_argument("--max-depth", type=int, default=32)
    ap.add_argument("--out", help="evidence directory (must be outside the project work tree)")
    ap.add_argument("--run-id")
    ap.add_argument("--quiet", action="store_true")
    i = ap.add_mutually_exclusive_group()
    i.add_argument("--interactive", action="store_true", help="ask before fetching and before every change (/dev/tty)")
    i.add_argument("--non-interactive", action="store_true", help="flags are the consent (default)")
    return ap.parse_args(argv)


def main(argv):
    proc_on_stop_signals(on_stop_signal)  # first: a signal at any later point ends in a report, never a traceback
    try:
        a = parse_args(argv)
    except SystemExit as e:
        return EXIT_OK if e.code == 0 else EXIT_USAGE
    mode = "check" if a.check else "dry-run" if a.dry_run else "apply" if a.apply else None
    if mode is None:
        print("sync-upstreams: ERROR: choose one mode: --check, --dry-run or --apply", file=sys.stderr)
        return EXIT_USAGE
    if not BRANCH_RE.match(a.branch) or not valid_branch_name(a.branch):  # RV10-1 class: never a lock-path name git refuses
        print("sync-upstreams: ERROR: invalid --branch", file=sys.stderr)
        return EXIT_USAGE
    for v, n in ((a.timeout, "--timeout"), (a.deadline, "--deadline"), (a.max_depth, "--max-depth"),
                 (a.write_timeout, "--write-timeout")):
        if v is None or v < 1:
            print("sync-upstreams: ERROR: %s must be a positive integer" % n, file=sys.stderr)
            return EXIT_USAGE
    if a.jobs is not None and a.jobs < 1:
        print("sync-upstreams: ERROR: --jobs must be a positive integer", file=sys.stderr)
        return EXIT_USAGE
    if a.advance_third_party and not a.advance_pins:
        print("sync-upstreams: ERROR: --advance-third-party needs --advance-pins", file=sys.stderr)
        return EXIT_USAGE
    git_bin = shutil.which("git")
    if not git_bin:
        print("sync-upstreams: ERROR: git not found", file=sys.stderr)
        return EXIT_USAGE
    started_mono = time.monotonic()
    r = Runner(git_bin, a.timeout, started_mono + a.deadline, a.write_timeout)
    start_dir = a.root or os.getcwd()
    res = r.run(start_dir, ["rev-parse", "--show-toplevel"], ok=(0, 128), want=ABS_PATH_RE)
    if not res.answered:
        print("sync-upstreams: BLIND: git gave no answer for the work-tree top level of %s (%s); nothing was done"
              % (redact(start_dir), res.why), file=sys.stderr)
        print("RESULT: BLIND exit=%d" % EXIT_BLIND)
        return EXIT_BLIND
    top = res.text()
    if not top:
        # exit 128 means "not a work tree" only where there is no .git; a .git git cannot read (a broken gitdir
        # pointer, an unknown extension, dubious ownership) is no answer (review round 3, F1 class)
        if path_kind(os.path.join(start_dir, ".git")) != "absent":
            print("sync-upstreams: BLIND: git cannot read the repository at %s (%s); nothing was done"
                  % (redact(start_dir), redact(res.err).strip()[-200:] or "rc:%s" % res.rc), file=sys.stderr)
            print("RESULT: BLIND exit=%d" % EXIT_BLIND)
            return EXIT_BLIND
        print("sync-upstreams: ERROR: %s is not inside a git work tree" % redact(start_dir), file=sys.stderr)
        return EXIT_USAGE
    root = os.path.realpath(top)
    if a.root and os.path.realpath(a.root) != root:
        print("sync-upstreams: ERROR: --root must be the top level of a work tree (%s)" % redact(root), file=sys.stderr)
        return EXIT_USAGE
    run_id = a.run_id or "%s-%d" % (datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"), os.getpid())
    if not re.match(r"^[A-Za-z0-9._-]{1,80}$", run_id) or run_id in (".", ".."):
        print("sync-upstreams: ERROR: --run-id must match [A-Za-z0-9._-]{1,80}", file=sys.stderr)
        return EXIT_USAGE
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    if not a.out and not os.path.isabs(base):  # a relative cache dir would land wherever the run starts (RV4-12)
        print("sync-upstreams: ERROR: XDG_CACHE_HOME (or HOME) is not an absolute path; pass --out", file=sys.stderr)
        return EXIT_USAGE
    # the evidence directory, explicit or default, is resolved (symbolic links followed) and must lie outside the
    # project work tree: a default under a cache dir that is a link into the tree is refused too (RV4-12)
    out_dir = os.path.realpath(a.out if a.out else os.path.join(base, "helix_sync_upstreams",
                                                                "%s-%s" % (os.path.basename(root), run_id)))
    if out_dir == root or out_dir.startswith(root + os.sep):
        print("sync-upstreams: ERROR: the evidence directory %s is inside the project work tree; pass --out "
              "outside it" % redact(out_dir), file=sys.stderr)
        return EXIT_USAGE
    for name, kind in (("sync_report.json", "json"), ("sync_report.tsv", "tsv")):
        if not evidence_file_ours(os.path.join(out_dir, name), kind):
            print("sync-upstreams: ERROR: %s exists and was not written by this engine (or is a symlink); choose "
                  "another --out" % redact(os.path.join(out_dir, name)), file=sys.stderr)
            return EXIT_USAGE
    # the evidence directory must be writable BEFORE anything is changed (RV4-8): created, then probed with a real
    # file (mkstemp + unlink); a run that would end unable to write its report never starts writing the project
    err_ = fs_probe_dir(out_dir)
    if err_:
        print("sync-upstreams: ERROR: cannot write the evidence directory %s (%s); nothing was done"
              % (redact(out_dir), redact(err_)), file=sys.stderr)
        return EXIT_USAGE
    tty = None
    if a.interactive:
        try:
            tty = Tty()
        except OSError:
            print("sync-upstreams: ERROR: --interactive needs a terminal (/dev/tty); use --non-interactive", file=sys.stderr)
            return EXIT_USAGE
    common = g_out(r, root, ["rev-parse", "--path-format=absolute", "--git-common-dir"], ok=(0,), want=ABS_PATH_RE)
    if not common:
        print("sync-upstreams: BLIND: git gave no answer for the git common dir of %s; nothing was done" % redact(root),
              file=sys.stderr)
        print("RESULT: BLIND exit=%d" % EXIT_BLIND)
        return EXIT_BLIND
    lock_path = os.path.join(common, "helix-sync-upstreams.lock")
    lock_fd, lerr = fs_open_lock(lock_path)
    if lock_fd is None:  # not "another run": the lock cannot be opened at all (RV5-2), or is no file (round 9)
        print("sync-upstreams: ERROR: cannot open the run lock %s (%s); nothing was done"
              % (redact(lock_path), redact(lerr)), file=sys.stderr)
        print("RESULT: FAILED exit=%d" % EXIT_FAIL)
        return EXIT_FAIL
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as e:
        os.close(lock_fd)
        if isinstance(e, BlockingIOError):
            print("sync-upstreams: ERROR: another sync run holds %s (exit 7, nothing done)" % redact(lock_path), file=sys.stderr)
            return EXIT_LOCKED
        print("sync-upstreams: ERROR: cannot take the run lock %s (%s); nothing was done"
              % (redact(lock_path), redact(e.strerror or str(e))), file=sys.stderr)
        print("RESULT: FAILED exit=%d" % EXIT_FAIL)
        return EXIT_FAIL
    held = [lock_fd]  # every lock this run holds (the root's, then one per repository; RV4-11), closed below
    try:
        return run(a, r, mode, root, run_id, out_dir, tty, held, common)
    finally:
        for fd_ in held:
            os.close(fd_)


def say(a, msg, always=False):
    if always or not a.quiet:
        print("[sync-upstreams] " + redact(msg), file=sys.stderr)


def lock_repositories(live, root_common, held):
    """Take the run lock of EVERY repository of the tree (in its git common dir, deduplicated; the root's is held
    already): a second run rooted inside this tree, or overlapping it, finds a lock taken and exits 7 (RV4-11).
    Returns None, or (path, held, error) for the lock that could not be taken: held True when another run holds it,
    False when its flock is refused for another reason (ENOLCK, ...), None when the lock file cannot be opened
    (review round 6, RV5-2; round 8, RV7-6). The caller ends the run before any fetch or
    write."""
    seen = {os.path.realpath(root_common)}
    for x in live:
        common = x.rec.get("_common_dir")
        if not common:  # no answer for the paths: recorded; the repository is blind and never written
            continue
        real = os.path.realpath(common)
        if real in seen:
            continue
        seen.add(real)
        path = os.path.join(real, "helix-sync-upstreams.lock")
        fd_, lerr = fs_open_lock(path)
        if fd_ is None:
            return path, None, lerr  # None: the lock file could not be OPENED (review round 8), or is no file (r9)
        held.append(fd_)
        try:
            fcntl.flock(fd_, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as e:
            return path, isinstance(e, BlockingIOError), e.strerror or str(e)
    return None


def run(a, r, mode, root, run_id, out_dir, tty, held, root_common):
    started = now_utc()
    t0 = time.monotonic()
    own_orgs = tuple(a.own_org) if a.own_org else DEFAULT_OWN_ORGS
    jobs = clamp_jobs(a.jobs, os.cpu_count())
    needle = control_needle(r, root)
    repos = discover(r, root, a.max_depth)
    live = [x for x in repos if x.rec.get("initialised")]
    for x in live:
        inspect_local(r, x, a.branch)
    r.run_id = run_id
    busy = lock_repositories(live, root_common, held)
    if busy:
        if busy[1]:
            print("sync-upstreams: ERROR: another sync run holds %s (exit 7, nothing fetched or changed)"
                  % redact(busy[0]), file=sys.stderr)
            return EXIT_LOCKED
        # RV7-6: an flock that is refused (ENOLCK, ...) is "cannot take", an open that fails is "cannot open"
        print("sync-upstreams: ERROR: cannot %s the run lock %s (%s); nothing fetched or changed"
              % ("open" if busy[1] is None else "take", redact(busy[0]), redact(busy[2])), file=sys.stderr)
        print("RESULT: FAILED exit=%d" % EXIT_FAIL)
        return EXIT_FAIL
    # the write-in-progress marker of an earlier run (RV5-1): a clean repository shows nothing of that write, so in
    # --apply (locks held) the marker is cleared and noted; with leftovers it stays and the repository is blocked
    for x in live:
        earlier = x.rec.get("write_interrupted_earlier")
        if not earlier:
            continue
        gd = x.rec.get("_gitdir") or ""
        if x.rec.get("dirty") or x.rec.get("in_progress"):
            x.rec.setdefault("notes", []).append("write-marker-kept:leftovers-of-%s" % earlier)
            if gd:
                r.gd_move(gd, GD_EARLIER)
        elif mode == "apply":
            gone = clear_marker(gd)
            if gone in ("removed", "absent"):
                x.rec.setdefault("notes", []).append("write-marker-cleared:%s-left-nothing" % earlier)
                x.rec.pop("write_interrupted_earlier", None)
                if gd:
                    r.gd_move(gd, GD_CLEARED)
            else:  # it could not be removed (RV8-4): kept, never reported cleared
                x.rec.setdefault("notes", []).append("write-marker-kept:cannot-remove:%s" % gone)
                if gd:
                    r.gd_move(gd, GD_EARLIER)
        else:
            x.rec.setdefault("notes", []).append("write-marker-present:%s-left-nothing" % earlier)
            if gd:
                r.gd_move(gd, GD_EARLIER)
    n_remotes = sum(len(x.rec.get("remotes", [])) for x in live)
    consent = {"fetch": mode in ("check", "apply") and not a.no_fetch,
               "integrate": mode == "apply", "pins": mode == "apply" and a.advance_pins}
    consent_source = "flags"
    if tty:
        consent_source = "interactive"
        tty.say("sync-upstreams: %d repositories (%d initialised), %d remotes under %s; mode %s"
                % (len(repos), len(live), n_remotes, root, mode))
        if consent["fetch"]:
            consent["fetch"] = tty.ask("Fetch every remote of the %d initialised repositories now?" % len(live))
    say(a, "root %s: %d repositories, %d initialised, %d remotes, mode %s, jobs %d"
        % (root, len(repos), len(live), n_remotes, mode, jobs))
    if consent["fetch"]:
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
            list(ex.map(lambda x: fetch_repo(r, x, a.tags), live))
    else:
        for x in live:
            for rem in x.rec.get("remotes", []):
                if rem.get("fetch") == "not-run":
                    rem["fetch"] = "skipped"
    for x in live:
        evaluate_upstream(r, x, a.branch)
    for x in repos:
        if x.parent is not None and x.rec.get("initialised"):
            evaluate_pin(r, x, x.rec["recorded_gitlink"], own_orgs)
    if mode == "apply":
        if tty:
            k = sum(1 for x in live if x.rec.get("branch") == a.branch and x.rec.get("local_vs_target") == "behind")
            consent["integrate"] = tty.ask("Fast-forward %d repositories on %s (clean children follow their new pin)?"
                                           % (k, a.branch)) if k else False
            if a.advance_pins:
                p = sum(1 for x in live if (x.rec.get("pin") or {}).get("state") == "behind-main")
                consent["pins"] = tty.ask("Stage %d submodule pin advances (git add, never committed)?" % p) if p else False
        integrate(r, repos, a.branch, a.advance_pins, a.advance_third_party, a.strict_pins, consent)
    for x in repos:
        rec = x.rec
        if rec.get("initialised") and "head_after" not in rec:
            if mode == "apply":  # integrate() reads every head after the pass: a missing one was never read (F2)
                r.no_answer(x.abspath, "rev-parse", "head-after-not-read")
                rec["head_after"] = None
            else:  # check / dry-run write nothing: the head is the one read before
                rec["head_after"] = rec.get("head_before")
    # final classification
    any_fail = any_attention = any_behind = any_unresolved = any_blind = False
    hints = []
    for x in repos:
        rec = x.rec
        if rec.get("write_killed"):  # recovery steps for a write its own limit ended (RV5-1), never run automatically
            gd = rec.get("_gitdir") or "<git dir>"
            hints.append("write-killed recovery for %s: make sure no git process runs in it; inspect 'git -C %s "
                         "status'; remove %s/index.lock only if it is still there; keep any leftovers with 'git -C %s "
                         "stash push --include-untracked -m helix-sync-write-killed'; then re-run with a larger "
                         "--write-timeout" % (rec["path"], x.abspath, gd, x.abspath))
        if rec.get("write_left_changes"):  # git answered a write that it had half-applied (round 9, RV8-1)
            hints.append("write-left-changes recovery for %s: git ended a %s with an error after it changed the "
                         "repository; inspect 'git -C %s status'; keep any leftovers with 'git -C %s stash push "
                         "--include-untracked -m helix-sync-write-left-changes'; remove a lock file only after making "
                         "sure no git process runs; the marker %s stays until a later --apply finds the tree clean"
                         % (rec["path"], rec["write_left_changes"], x.abspath, x.abspath,
                            WRITE_MARKER))
        rec["reasons"] = reasons_for(rec, a.strict_pins, a.branch)
        unresolved = r.unresolved_for(x.abspath)
        if unresolved:  # a call that did not answer is never read as "absent" / "clean" / "unchanged" / "moved"
            rec["unresolved"] = unresolved
            rec["reasons"] += ["unresolved:" + u for u in unresolved]
        blind = [u for u in unresolved if u.split(":", 1)[1] not in TIME_WHYS + STOP_WHYS]
        rec.setdefault("actions", [])
        moved = bool(rec.get("initialised") and rec.get("head_after") is not None
                     and rec.get("head_before") is not None and rec.get("head_after") != rec.get("head_before"))
        rec["moved"] = moved
        if moved and rec.get("_wrote_to") != rec.get("head_after"):  # moved, but not to what this run wrote (RV4-1)
            rec["changed_by_other"] = True
            rec["reasons"].append("head-changed-during-run")
        blocking = [y for y in rec["reasons"] if y.startswith(BLOCKING_PREFIXES)]
        if rec.get("failed"):
            any_fail = True
        if blind:  # before "failed": a failure judged on a call that gave no answer is not an answer either
            rec["result"] = "blind"
            any_blind = True
        elif rec.get("failed"):
            rec["result"] = "failed"
        elif unresolved and all(u.split(":", 1)[1] in STOP_WHYS for u in unresolved):
            rec["result"] = "interrupted"  # only calls refused or stopped by the stop signal (RV4-5)
        elif unresolved:
            rec["result"] = "unresolved"
            any_unresolved = True
        elif moved and mode == "apply" and not blocking:  # moved, but blocked afterwards: attention (F2)
            rec["result"] = "updated"
            if fs_is_regular(os.path.join(x.abspath, "scripts", "post_update_hook.sh")) and \
                    fs_is_regular(os.path.join(x.abspath, "Constitution.md")) and x.parent is not None:
                hints.append("bash %s/scripts/post_update_hook.sh --project-root %s" % (rec["path"], x.parent.rel))
        elif rec["reasons"]:
            rec["result"] = "attention"
            any_attention = True
        elif mode != "apply" and has_update(rec):
            rec["result"] = "behind"
            any_behind = True
        elif mode == "apply" and has_update(rec) and not moved:
            rec["result"] = "behind"
            any_behind = True
        elif not rec.get("initialised"):
            rec["result"] = "not-initialised"
        else:
            rec["result"] = "current"
    if STOP_REQUESTED.is_set():  # a stop signal (RV4-5): whatever else was found, the run did not finish
        code, verdict = EXIT_INTERRUPTED, "INTERRUPTED"
    elif not needle["ok"] or any_blind:
        code, verdict = EXIT_BLIND, "BLIND"
    elif any_fail:
        code, verdict = EXIT_FAIL, "FAILED"
    elif any_unresolved:
        code, verdict = EXIT_INCONCLUSIVE, "INCONCLUSIVE"
    elif any_attention:
        code, verdict = EXIT_ATTENTION, "ATTENTION"
    elif any_behind:  # also after --apply: something is still behind (declined, or a pin without --advance-pins)
        code, verdict = EXIT_BEHIND, "UPDATES-AVAILABLE"
    else:
        code, verdict = EXIT_OK, "APPLIED" if mode == "apply" else "CURRENT"
    report = {
        "schema": SCHEMA, "run_id": run_id, "mode": mode, "branch": a.branch,
        "flags": {"no_fetch": a.no_fetch, "tags": a.tags, "advance_pins": a.advance_pins,
                  "advance_third_party": a.advance_third_party, "strict_pins": a.strict_pins,
                  "own_orgs": sorted(own_orgs), "max_depth": a.max_depth},
        "consent": consent, "consent_source": consent_source,
        "root_abs": root, "out_dir": out_dir, "started": started, "ended": now_utc(),
        "duration_s": round(time.monotonic() - t0, 3), "jobs": jobs, "git_calls": r.calls,
        "control_needle": needle, "verdict": verdict, "exit_code": code,
        "counts": {"repos": len(repos), "initialised": len(live), "remotes": n_remotes},
        "repos": sorted((x.rec for x in repos), key=lambda d: d["path"]),
        "next_steps": sorted(set(hints)),
    }
    hits = []
    report = redact_report(report, "report", hits)
    report["redaction_backstop"] = hits  # field paths the backstop had to clean: always [] (tests/sync/*)
    report["canonical_sha256"] = canonical_sha256(report)
    try:
        fs_ensure_dir(out_dir)
        fs_write_atomic(os.path.join(out_dir, "sync_report.json"), json.dumps(report, indent=2, sort_keys=True) + "\n")
        fs_write_atomic(os.path.join(out_dir, "sync_report.tsv"), tsv_rows(report))
    except OSError as e:
        # the evidence directory was writable at the start (main); losing it now is a FAILED run, never a usage
        # error: the project may already have moved, so every move is printed here (RV4-8)
        print("sync-upstreams: ERROR: cannot write evidence to %s: %s" % (redact(out_dir), redact(str(e))), file=sys.stderr)
        for rec in report["repos"]:
            if rec.get("moved"):
                print("sync-upstreams: moved %s %s -> %s" % (rec["path"], rec.get("head_before"), rec.get("head_after")),
                      file=sys.stderr)
        print("RESULT: FAILED exit=%d" % EXIT_FAIL)
        return EXIT_FAIL
    # --quiet prints every repository that is not current (a not-initialised or blind one included; review round 3, F1)
    for rec in report["repos"]:
        say(a, "%-40s %-15s %s" % (rec["path"], rec.get("result"), ",".join(rec.get("reasons", [])) or "-"),
            always=rec.get("result") != "current")
    for h in report["next_steps"]:
        say(a, "next step (never run automatically): " + h, always=True)
    if tty:
        tty.say("sync-upstreams: %s (exit %d); report %s" % (verdict, code, out_dir))
    print("REPORT_JSON=%s" % os.path.join(out_dir, "sync_report.json"))
    print("CANONICAL_SHA256=%s" % report["canonical_sha256"])
    print("RESULT: %s exit=%d" % (verdict, code))
    return code


def entry(argv):
    """main() with no traceback: an unexpected exception is reported redacted (its text can hold a path or a URL)
    and the run is FAILED (exit 1), never a crash that prints raw values (review round 3, class D)."""
    try:
        return main(argv)
    except Exception as e:
        print("sync-upstreams: internal error: %s: %s" % (redact(repr(type(e))), redact(str(e))), file=sys.stderr)
        print("RESULT: FAILED exit=%d" % EXIT_FAIL)
        return EXIT_FAIL


if __name__ == "__main__":
    sys.exit(entry(sys.argv[1:]))
