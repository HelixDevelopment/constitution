#!/usr/bin/env python3
"""repo_verify.py - recursive clean+push verifier (spec-004 "fast-dev-cycles", User Story 7,
plan T-G06/T-G07; contract contracts/recursive-verification.md; contracts/common-conventions.md
C-001..C-007; data-model.md #12; FR-020, FR-021; SC-008; research.md DEC-26).

Purpose: one command that proves, for the main repository and every submodule recursively, that
the working tree is clean, nothing is unpushed, and each upstream's live tip equals the local
tip -- reading remote state live (never from cached remote-tracking refs), and returning
byte-identical output on two consecutive runs of the same state. Observes only; never fixes,
never force-pushes/stashes/resets/cleans (C-006).

Usage:   repo_verify.py --recursive --root <repo> [--remotes-config <cfg>] --out <report.json>
             [--md <report.md>] [--determinism-check] [--timeout-per-remote <s>]

Exit codes (contract "Exit codes" table): 0 overall CLEAN; 1 overall NOT_CLEAN (reasons per
repo, in the written report); 2 usage/config error; 3 needle failure (this tool's OWN
control-needle self-check -- a throwaway synthetic repo with one known-present untracked file
that MUST be detected dirty -- did not behave as expected; no honest verdict on the real --root
is possible until the detector itself is proven, constitution 11.4.201/11.4.273; nothing is
written); 4 overall UNVERIFIED (>=1 repo's remote could not be verified, DEC-26 -- the report is
still written in full, flagged BLIND, per C-001's "partial output ... never read as 0") OR a
genuinely unreadable repository (git itself cannot resolve HEAD -- no honest verdict at all,
nothing written) OR an uncaught internal error (never 1, reserved for findings).

Remote-tip discovery (RV-004): `git ls-remote --symref <remote> HEAD` resolves the remote's own
default branch AND its live tip in one round trip, so this needs no locally-configured branch
name and works uniformly for a checked-out branch or a submodule's detached HEAD (submodules are
normally detached at a pinned commit, not a branch). This is the concrete form of the contract's
literal `git ls-remote <remote> refs/heads/<branch>` clause -- reading the SAME live information
(the remote's real branch tip) via the remote's own reported default ref, never a guessed or
locally-configured branch name.

Unpushed count (RV-006): the remote's live tip is fetched (read-only) into a temporary ref under
`refs/fastcycle_verify/<pid>/...`, removed immediately after use and swept again at exit (RV-009)
even on error/exception -- so no state is left behind regardless of outcome. `git rev-list --count
<fetched_tip>..HEAD` against that temp ref then gives the real unpushed count; a fetch failure (the
tip object cannot be obtained) reports `unpushed: "UNKNOWN"` for that remote and folds the repo
into UNVERIFIED (never a silent 0, constitution 11.4.201(6)'s false-null guard).

Pointer checks (RV-003, constitution 11.4.233(G)): a submodule's checked-out HEAD is compared
against the gitlink SHA recorded in the PARENT's own last COMMIT (via `git ls-tree <parent_head>
-- <path>`, not the possibly-dirty index) -> `DETACHED_POINTER_DRIFT` on mismatch. The gitlink SHA
is additionally probed against every declared remote via a bounded, depth-limited `git fetch
--depth=1 --filter=tree:0 <remote> <sha>:<temp-ref>` into a FRESH, empty, throwaway bare repo
(never the submodule's own working repo -- see `_pointer_fetchable`'s own docstring) run with
`cwd=<repo_path>` so a relative remote URL resolves exactly as it would for any other command run
against this same repository (T158 remediation round 1, finding #9). A remote that cannot be
REACHED at all (connection refused/host gone/timeout -- distinguished from a remote that was
reached and definitively rejected the SHA as unadvertised, both via the SAME `git ls-remote`
reachability signal `verify_remote` already computes for that remote) is never treated as proof
the commit is on no remote: `_pointer_fetchable` returns a tri-state verdict (FETCHABLE /
UNFETCHABLE / UNVERIFIED), and a submodule where EVERY probed remote is reachable and none has the
SHA is `POINTER_UNFETCHABLE`; a submodule where >=1 remote could not even be reached is folded into
the repo's `REMOTE_UNREACHABLE` -> UNVERIFIED path instead (RV-004), never asserted
`POINTER_UNFETCHABLE` on an unverified absence (T158 remediation round 1, finding #1 -- the
original defect: an unreachable remote's probe failure was indistinguishable from a reachable
remote's definitive rejection, so a network blip reported the SAME false NOT_CLEAN as a genuinely
unpushed commit). For a remote that IS reached, a commit that was genuinely never pushed anywhere
fails on every remote and is honestly `POINTER_UNFETCHABLE`; a commit reachable from some branch
but not the branch tip on a *restrictive* remote server that disables by-SHA-want may be reported
`POINTER_UNFETCHABLE` even though it technically exists there -- a known, documented limitation of
this cheap check, constitution 11.4.6, never silently assumed solved.

Push-rejection record (RV-005): read from an optional per-repo, per-remote JSON file at
`<git-dir>/fastcycle_push_log.json` (`{"remotes": {"<name>": {"result": "ACCEPTED"|"REJECTED",
"message": "<msg>"}}}`), written by the project's commit/push wrapper (a later, separate piece of
work -- not invented here); absent file or absent remote entry -> `last_push_result: "UNKNOWN"`,
never a fabricated ACCEPTED.

Push-URL verification (FR-020, T158 remediation round 1 finding #3): `git remote get-url` reads
only the FETCH URL; a remote whose `pushurl` (or multiple `pushurl` entries) differs from its fetch
URL would otherwise never be checked at all -- a lagging/rejecting PUSH destination silently reads
CLEAN forever. For every configured remote, every DISTINCT configured push URL (`git remote
get-url --push --all <name>`) that is not identical to the already-checked fetch URL is verified
the same way (live tip read, read-only temp-ref fetch, equality/ahead/differs classification),
reported as an additional `RemoteResult` entry named `<remote>:push`. The common case (no explicit
`pushurl` configured) costs nothing extra: the one push URL git itself falls back to IS the fetch
URL, so it is skipped.

Zero/missing remotes (FR-020, T158 remediation round 1 findings #4/#5): a repository with NO
configured remotes at all proves nothing was ever pushed anywhere and is never read as vacuously
CLEAN -- it is `UNPUSHED_COMMITS` (NOT_CLEAN; the closed reason-code set has no more specific code
for this, data-model.md #12.1). An optional `--remotes-config <path>` JSON file
(`{"required_remotes": ["<name>", ...]}`) names remote NAMES that MUST be configured on every repo
walked (main + every submodule, constitution 2.1 "push to ALL upstreams"); a repo missing any
required remote also gets `UNPUSHED_COMMITS` -- it was previously accepted but never actually read
(finding #5).

Self-check / control needle (contract exit 3, C-004): before trusting any real invocation, a
synthetic throwaway git repo is constructed fresh, confirmed reported CLEAN while genuinely
empty, then a known file is dropped into it and confirmed reported dirty (present) while a
fabricated filename is confirmed NOT reported present -- proving the worktree-status detector
itself can see, before any "clean"/"dirty" finding on the real --root is trusted.

Output (C-002): canonical JSON via fc_common.py's shared conventions (schema
`verify-recursive/v1`, `body_hash` excluding `run_meta`, atomic write). `--md` optionally renders
a derived, non-authoritative Markdown summary.

Safety (C-006) / RV-009 (T158 remediation round 1, finding #6): read-only against every repository
under `--root`; no `push --force`/`reset --hard`/`stash`/`clean` anywhere in this file
(grep-verifiable). The temporary ref namespace RV-009 names is the only REF ever written, and is
always removed (both an immediate per-remote delete and a defence-in-depth
`for-each-ref`-then-delete sweep at exit, itself re-verified empty via a second `for-each-ref`
afterwards). Every git invocation runs with `GIT_OPTIONAL_LOCKS=0` (git's own documented mechanism
for skipping opportunistic index/stat-cache rewrites it would otherwise perform during e.g. `git
status`) and every fetch into a real repository's own git-dir passes `--no-write-fetch-head` (never
overwrites the operator's own `FETCH_HEAD`) and `-c gc.auto=0` (never opportunistically triggers a
background gc). The read-only live-tip fetch RV-006 needs for the unpushed-commit COUNT would, by
default, land any genuinely-new remote objects as loose objects in the repository's own object
database -- a real, measured write (T158 review round 1, finding #6) that merely deleting the
temporary ref afterwards does not undo (the object outlives the ref). This is closed, not merely
documented: that fetch (and every git command that subsequently needs to resolve one of its
objects, e.g. the REMOTE_AHEAD ancestry check) runs with `GIT_OBJECT_DIRECTORY` redirected to a
process-lifetime scratch directory OUTSIDE every repository under `--root` (removed at exit) and
`GIT_ALTERNATE_OBJECT_DIRECTORIES` pointing back at the repository's own real object store (so
every object already local remains readable) -- any NEWLY fetched object is written to the scratch
directory instead of the repository's own `.git/objects`, verified byte-for-byte (`rv_no_mutation`
RED fixture, strengthened T158 remediation round 1) against a REMOTE_AHEAD scenario that forces a
real object transfer, not only the pre-existing already-clean fixture every object of which was
already present locally beforehand.

Stdlib only (matches lib/fc_common.py's own convention); imports canon/body_hash_of/cmd_emit
from the sibling lib/fc_common.py (C-002), same wiring pattern as plan_struct_check.py.
"""
import argparse
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash / atomic-emit helpers. Imported by file
# path (not a package) -- constitution/scripts/fastcycle has no __init__.py anywhere (matches
# this tree's existing flat-script layout).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

SCHEMA = "verify-recursive/v1"

# data-model.md #12.1 closed reason-code set.
REASON_CODES = (
    "DIRTY_TREE", "UNTRACKED_FILES", "UNPUSHED_COMMITS", "REMOTE_TIP_DIFFERS", "REMOTE_AHEAD",
    "REMOTE_REJECTED_LAST_PUSH", "REMOTE_UNREACHABLE", "DETACHED_POINTER_DRIFT",
    "SUBMODULE_UNINITIALISED", "POINTER_UNFETCHABLE",
)

# Operator-tunable default; the contract states no measured bound. Overridable via
# --timeout-per-remote. Matches this tree's own convention of naming such defaults as
# engineering guesses, never data (see lib/fc_common.py DETERMINISM_TIMEOUT_DEFAULT_S).
DEFAULT_TIMEOUT_S = 30

_SHA_RE = re.compile(r"^[0-9a-f]{40}$")


class RepoUnreadable(Exception):
    """git itself could not resolve HEAD for a repository already reported present on disk --
    a genuinely unreadable repo, distinct from an unreachable REMOTE (which still yields a full
    partial report, C-001 code 4). No honest verdict is possible; nothing is written."""

    def __init__(self, relpath, detail):
        super().__init__(detail)
        self.relpath = relpath
        self.detail = detail


def _run(args, cwd, timeout_s, extra_env=None):
    """Run a git subprocess; return (rc, stdout, stderr). Never raises on a nonzero exit; a
    timeout or spawn failure is reported as rc=None so callers can tell it apart from a real,
    observed git exit code.

    `GIT_OPTIONAL_LOCKS=0` is ALWAYS set (RV-009 -- git's own documented mechanism for skipping
    opportunistic index/stat-cache rewrites, see module docstring). `extra_env`, when given,
    layers additional overrides on top (the RV-009 object-store redirect `verify_remote` uses).

    `errors="surrogateescape"` (T158 remediation round 1, MINOR finding -- a filename that is not
    valid UTF-8 previously raised an uncaught `UnicodeDecodeError` while decoding this process's
    captured stdout, turning a reportable DIRTY_TREE/UNTRACKED_FILES finding into an opaque
    internal-error rc=4 with no report written at all): a byte that is not valid UTF-8 is mapped to
    a lone surrogate instead of raising, so the path still round-trips losslessly through this
    process's own str handling; it is `canon()`/`cmd_emit()`'s job (not this function's) to decide
    how an un-encodable surrogate is finally reported, never a crash here."""
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    if extra_env:
        env.update(extra_env)
    try:
        p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout_s,
                            errors="surrogateescape", env=env)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return None, "", "timeout after %ss running: %s" % (timeout_s, " ".join(args))
    except OSError as exc:
        return None, "", "cannot run %s: %s" % (" ".join(args), exc)


# --------------------------------------------------------------------- worktree / status (RV-002)

def worktree_status(repo_path, timeout_s=15):
    """RV-002: (ok, dirty_sorted, untracked_sorted) from
    `git status --porcelain=v1 -z --untracked-files=all --ignore-submodules=none`."""
    rc, out, err = _run(
        ["git", "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none"],
        repo_path, timeout_s)
    if rc != 0:
        raise RepoUnreadable(repo_path, "git status failed: %s" % (err.strip() or ("exit %s" % rc)))
    entries = out.split("\x00")
    dirty, untracked = [], []
    i = 0
    n = len(entries)
    while i < n:
        e = entries[i]
        if not e:
            i += 1
            continue
        xy = e[:2]
        path = e[3:]
        if xy == "??":
            untracked.append(path)
        else:
            dirty.append(path)
        # -z rename/copy entries carry an extra NUL-separated original-path field.
        if "R" in xy or "C" in xy:
            i += 1
        i += 1
    return True, sorted(dirty), sorted(untracked)


# --------------------------------------------------------------------------- submodule discovery

def list_gitmodules(repo_path, timeout_s=10):
    """Sorted relative paths declared in repo_path/.gitmodules, or [] if the file is absent.

    T158 remediation round 1, finding #8: `--get-regexp`'s default (newline-delimited, "key value"
    on one line, SPACE-separated) output is genuinely ambiguous whenever the submodule NAME
    (embedded in the key, e.g. `submodule.my sub.path`) contains a space -- a plain `.split(" ",
    1)` then cuts the key/value boundary at the WRONG space, producing a corrupted path (confirmed
    live: `submodule."my sub".path` -> key `submodule.my sub.path`, naive split yields path
    `"sub.path my sub"` instead of the real path). `--null` makes git itself delimit key and value
    with a literal `\\n` within each NUL-terminated record instead -- unambiguous regardless of
    spaces in either the key or the value (confirmed live against a fixture with an embedded-space
    submodule name)."""
    gm = os.path.join(repo_path, ".gitmodules")
    if not os.path.isfile(gm):
        return []
    rc, out, _err = _run(["git", "config", "-f", gm, "--null", "--get-regexp", r"^submodule\..*\.path$"],
                          repo_path, timeout_s)
    if rc != 0:
        return []
    paths = []
    for record in out.split("\x00"):
        if not record:
            continue
        _key, sep, value = record.partition("\n")
        if sep and value:
            paths.append(value)
    return sorted(paths)


def _is_initialised(sub_path):
    return os.path.isdir(os.path.join(sub_path, ".git")) or os.path.isfile(os.path.join(sub_path, ".git"))


def _join_rel(parent_rel, child_rel):
    base = "" if parent_rel in (".", "") else parent_rel
    joined = child_rel if not base else (base + "/" + child_rel)
    return joined.replace(os.sep, "/")


def parent_gitlink_sha(parent_path, sub_relpath, parent_head, timeout_s=10):
    """The commit SHA the PARENT's last commit (parent_head) records for sub_relpath, or None if
    unrecorded/unreadable."""
    rc, out, _err = _run(["git", "ls-tree", parent_head, "--", sub_relpath], parent_path, timeout_s)
    if rc != 0 or not out.strip():
        return None
    m = re.match(r"^\S+\s+commit\s+([0-9a-f]{40})\t", out)
    return m.group(1) if m else None


# ------------------------------------------------------------------------------------- remotes

def list_remotes(repo_path, timeout_s=10):
    rc, out, _err = _run(["git", "remote"], repo_path, timeout_s)
    if rc != 0:
        return []
    return sorted(l.strip() for l in out.splitlines() if l.strip())


def _remote_url(repo_path, name, timeout_s=10):
    rc, out, _err = _run(["git", "remote", "get-url", name], repo_path, timeout_s)
    return out.strip() if rc == 0 else None


def _push_urls(repo_path, name, timeout_s=10):
    """T158 remediation round 1, finding #3: the sorted, de-duplicated set of URL(s) `git push
    <name>` would ACTUALLY push to -- every configured `pushurl` (there may be more than one;
    `git remote set-url --add --push` layers additional ones, and the contract text itself calls
    out 'multiple pushurl entries ... ignored' as a gap), or, when none is explicitly configured,
    the single fetch URL git itself falls back to (so the common case -- no `pushurl` at all --
    yields exactly one entry, identical to `_remote_url`'s own result, letting the caller skip
    the redundant extra check cheaply). Returns [] if the remote cannot be resolved at all (never
    raises -- an unresolvable remote is already reported via the ordinary fetch-URL check)."""
    rc, out, _err = _run(["git", "remote", "get-url", "--push", "--all", name], repo_path, timeout_s)
    if rc != 0:
        return []
    return sorted(set(l.strip() for l in out.splitlines() if l.strip()))


def _git_objects_dir(repo_path, timeout_s=10):
    """The real, physical object-store directory for `repo_path` (`git rev-parse --git-path
    objects`, which correctly resolves a submodule's `.git` FILE indirection, a worktree, or any
    other `.git`-dir relocation, rather than assuming the literal `<repo_path>/.git/objects`
    layout). Used ONLY to populate `GIT_ALTERNATE_OBJECT_DIRECTORIES` for the RV-009 object-store
    redirect in `verify_remote` (see module docstring) -- never written to directly. None if it
    cannot be resolved (an extremely narrow case in practice: every caller site already resolved
    this same repository's HEAD successfully moments earlier)."""
    rc, out, _err = _run(["git", "rev-parse", "--git-path", "objects"], repo_path, timeout_s)
    if rc != 0:
        return None
    d = out.strip()
    return d if os.path.isabs(d) else os.path.join(repo_path, d)


def redact_url(url):
    """C-006: remote URLs rendered as host/org/repo (or deeper, e.g. a GitLab subgroup), NEVER
    any credential text, under ANY input including a malformed-but-plausible URL whose userinfo
    itself contains an embedded, unescaped '/' or a second '@'. Local filesystem paths (the
    throwaway bare remotes this tool's own RED fixtures use) carry no credentials to begin with;
    rendered as their basename.

    T158 remediation round 1, MINOR finding (confirmed a real credential-handling defect,
    constitution 11.4.10 -- fixed regardless of its MINOR severity label): the PREVIOUS ad-hoc
    regex assumed the optional `user[:pass]@` prefix never itself contained a `/` or a second
    `@`; when it did, the regex's own optional group failed to match that prefix at all and a
    DIFFERENT alternative inside the SAME regex read part of the credential text as if it were
    the host or a path segment, leaking password-fragment bytes straight into the written report
    -- confirmed live for BOTH `https://user:pa/ss@github.com/org/repo.git` (leaked `user:pa`)
    and `https://user:p@ss@github.com/org/repo.git` (leaked `ss`). `urllib.parse.urlsplit()` was
    also measured, live, to leak the SAME way on the first case (it anchors the authority/path
    boundary at the FIRST unescaped `/`, which here sits INSIDE the userinfo, before it ever
    looks for `@` at all) -- so this is fixed structurally rather than by patching that regex or
    reaching for the stdlib parser: find the LAST `@` ANYWHERE in the (scheme-stripped) string
    and keep only what comes strictly AFTER it. No character positioned at or before that `@` can
    ever reach the output, regardless of how many additional `@`s or `/`s appear before it --
    this is a stronger, syntax-independent guarantee than attempting to correctly PARSE an
    ambiguous (per RFC 3986) userinfo component, which has no single unambiguous answer once an
    unescaped `/` appears inside it. The GitLab-subgroup truncation ("g/sub/repo" -> "sub/repo")
    the review also flagged is fixed as a side effect: every path segment is now kept, never only
    the last two."""
    if not url:
        return "UNKNOWN"
    m = re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://(.*)$", url, re.DOTALL)
    if m:
        rest = m.group(1)
        at = rest.rfind("@")
        after_at = rest[at + 1:] if at != -1 else rest
        segments = [p for p in after_at.split("/") if p]
        if segments and segments[-1].endswith(".git"):
            segments[-1] = segments[-1][:-4]
        return "/".join(segments) if segments else "UNKNOWN"
    at2 = url.rfind("@")
    cand = url[at2 + 1:] if at2 != -1 else url
    m2 = re.match(r"^([^:/]+):(.+)$", cand)
    if m2 and "/" in m2.group(2):
        host, path = m2.group(1), m2.group(2)
        if path.endswith(".git"):
            path = path[:-4]
        segments = [host] + [p for p in path.split("/") if p]
        return "/".join(segments)
    return os.path.basename(os.path.normpath(url)) or url


def _remote_head_tip(repo_path, remote, branch, timeout_s):
    """RV-004: resolve the remote's live tip. Prefers the LOCAL branch name (the contract's
    literal `git ls-remote <remote> refs/heads/<branch>`) when known; falls back to the remote's
    sole head, then its own `--symref HEAD` resolution, for a detached checkout (the normal
    submodule state) or a remote whose own HEAD symref is stale (e.g. a freshly `git init
    --bare`'d repo still defaulting to `refs/heads/master` before anything was ever pushed
    there -- a real, measured case, not a hypothetical one)."""
    if branch:
        rc, out, _err = _run(["git", "ls-remote", remote, "refs/heads/%s" % branch], repo_path, timeout_s)
        if rc == 0:
            want = "refs/heads/%s" % branch
            for line in out.splitlines():
                parts = line.strip().split("\t")
                if len(parts) == 2 and parts[1] == want and _SHA_RE.match(parts[0]):
                    return parts[0], None

    rc, out, err = _run(["git", "ls-remote", "--heads", remote], repo_path, timeout_s)
    if rc != 0:
        return None, (err.strip() or ("git ls-remote exit %s" % rc))
    heads = []
    for line in out.splitlines():
        parts = line.strip().split("\t")
        if len(parts) == 2 and parts[1].startswith("refs/heads/") and _SHA_RE.match(parts[0]):
            heads.append((parts[1], parts[0]))
    if len(heads) == 1:
        return heads[0][1], None

    rc2, out2, _err2 = _run(["git", "ls-remote", "--symref", remote, "HEAD"], repo_path, timeout_s)
    if rc2 == 0:
        for line in out2.splitlines():
            line = line.strip()
            if not line or line.startswith("ref:"):
                continue
            parts = line.split("\t")
            if len(parts) == 2 and parts[1] == "HEAD" and _SHA_RE.match(parts[0]):
                return parts[0], None
    if not heads:
        return None, "remote has no refs/heads/* and no resolvable HEAD"
    return None, ("cannot determine remote default branch: %d candidate heads, no local-branch-name "
                   "match, no resolvable HEAD symref" % len(heads))


def _is_ancestor(repo_path, older, newer, timeout_s, extra_env=None):
    """`extra_env`: the RV-009 object-store redirect (see `verify_remote`) -- `newer` may name an
    object that exists ONLY via that redirect (freshly fetched into the scratch object directory,
    never written into `repo_path`'s own object store), so this check MUST use the identical
    environment the fetch that produced it ran under, or resolution of `newer` fails and a real
    REMOTE_AHEAD is silently misclassified REMOTE_TIP_DIFFERS instead (verified live, T158
    remediation round 1 finding #6 fix)."""
    rc, _out, _err = _run(["git", "merge-base", "--is-ancestor", older, newer], repo_path, timeout_s,
                           extra_env=extra_env)
    return rc == 0


def _delete_ref_quiet(repo_path, ref):
    _run(["git", "update-ref", "-d", ref], repo_path, 10)


def _sweep_ref_namespace(repo_path, namespace):
    """RV-009: remove every ref left under `namespace`, verified via `git for-each-ref` (defence
    in depth on top of the per-remote immediate deletes already performed). T158 remediation
    round 1 MINOR finding: the sweep's own "verified removed" claim is now actually re-checked --
    a SECOND `for-each-ref` pass after deletion, so a ref that somehow survives deletion (e.g. a
    permissions error on `update-ref -d`) is reported honestly to stderr rather than the sweep
    silently believing its own unchecked claim."""
    rc, out, _err = _run(["git", "for-each-ref", "--format=%(refname)", namespace], repo_path, 10)
    if rc != 0:
        return
    for ref in out.splitlines():
        ref = ref.strip()
        if ref:
            _delete_ref_quiet(repo_path, ref)
    rc2, out2, _err2 = _run(["git", "for-each-ref", "--format=%(refname)", namespace], repo_path, 10)
    if rc2 == 0:
        survivors = [r.strip() for r in out2.splitlines() if r.strip()]
        if survivors:
            print("repo_verify: RV-009 WARNING -- ref(s) survived the sweep under %r: %s"
                  % (namespace, survivors), file=sys.stderr)


def _push_result_str(entry):
    if not isinstance(entry, dict):
        return "UNKNOWN"
    result = entry.get("result")
    if result == "ACCEPTED":
        return "ACCEPTED"
    if result == "REJECTED":
        return "REJECTED(%s)" % entry.get("message", "")
    return "UNKNOWN"


def _git_dir(repo_path, timeout_s=10):
    rc, out, _err = _run(["git", "rev-parse", "--git-dir"], repo_path, timeout_s)
    if rc != 0:
        return None
    d = out.strip()
    return d if os.path.isabs(d) else os.path.join(repo_path, d)


def read_push_log(repo_path):
    """RV-005: optional `<git-dir>/fastcycle_push_log.json` -> {remote_name: {result, message}}.
    Absent file, unreadable JSON, or non-object -> {} (folds every remote to UNKNOWN, never a
    fabricated ACCEPTED)."""
    gd = _git_dir(repo_path)
    if not gd:
        return {}
    p = os.path.join(gd, "fastcycle_push_log.json")
    if not os.path.isfile(p):
        return {}
    try:
        with open(p, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    remotes = data.get("remotes") if isinstance(data, dict) else None
    return remotes if isinstance(remotes, dict) else {}


def verify_remote(repo_path, git_target, local_tip, branch, timeout_s, tmp_ns, push_log_entry,
                   out_name, url_redacted, scratch_objdir, real_objects_dir):
    """One RemoteResult (+ its internal-only "_unpushed"/"_reachable") and the reason code it
    contributes to the owning repo's `reasons`, or None if the remote is clean.

    `git_target` is whatever git accepts in a remote-name position: a CONFIGURED remote NAME for
    the ordinary fetch-URL check, or a literal PUSH URL string for the push-destination check
    (T158 remediation round 1, finding #3) -- git itself accepts a bare URL anywhere a configured
    remote name is valid, so this one function serves both without caring which it was given.
    `push_log_entry` is the caller's OWN `push_log.get(<base remote name>)` lookup (REJECTED /
    ACCEPTED / UNKNOWN describe the whole push ATTEMPT of that configured remote; the fetch-URL
    check and the push-URL check of the SAME configured remote share this one entry). `out_name`
    / `url_redacted` are supplied by the caller (never re-derived here) so a push-URL check can be
    labelled and redacted independently of the underlying `git_target` it actually queries.

    `scratch_objdir` / `real_objects_dir`: the RV-009 object-store redirect (T158 remediation
    round 1, finding #6 -- see module docstring). The live-tip fetch below is the ONE git
    invocation in this whole tool that can genuinely need to pull NEW objects from a remote (every
    other command only ever READS what is already local); run with `GIT_OBJECT_DIRECTORY` pointed
    at `scratch_objdir` (so any newly-fetched object lands there, never in `repo_path`'s own
    object store) and `GIT_ALTERNATE_OBJECT_DIRECTORIES` pointed back at `real_objects_dir` (so
    every object already local to `repo_path` -- including `local_tip` itself -- stays resolvable
    for the SAME env). `real_objects_dir` of None (its resolution genuinely failed) degrades
    honestly to the pre-fix behaviour (no redirect) rather than fail the whole check."""
    extra_env = None
    if scratch_objdir and real_objects_dir:
        extra_env = {"GIT_OBJECT_DIRECTORY": scratch_objdir,
                     "GIT_ALTERNATE_OBJECT_DIRECTORIES": real_objects_dir}
    last_push_str = _push_result_str(push_log_entry)
    tip, err = _remote_head_tip(repo_path, git_target, branch, timeout_s)
    if tip is None:
        return {
            "name": out_name, "url_redacted": url_redacted, "remote_tip": "UNREACHABLE",
            "local_tip": local_tip, "equal": False, "last_push_result": last_push_str,
            "_unpushed": "UNKNOWN", "_reachable": False, "_detail": err,
        }, "REMOTE_UNREACHABLE"

    equal = (tip == local_tip)
    tmp_ref = "%s/%s" % (tmp_ns, re.sub(r"[^A-Za-z0-9_.-]", "_", out_name))
    fetched, _fout, _ferr = _run(
        ["git", "-c", "gc.auto=0", "fetch", "--no-tags", "-q", "--no-write-fetch-head",
         git_target, "%s:%s" % (tip, tmp_ref)], repo_path, timeout_s, extra_env=extra_env)
    unpushed = "UNKNOWN"
    if fetched == 0:
        rc, out, _err = _run(["git", "rev-list", "--count", "%s..HEAD" % tmp_ref], repo_path, timeout_s,
                              extra_env=extra_env)
        if rc == 0 and out.strip().isdigit():
            unpushed = int(out.strip())
        _delete_ref_quiet(repo_path, tmp_ref)

    if fetched != 0 or unpushed == "UNKNOWN":
        # Tip was named by ls-remote but its object could not be obtained/verified locally --
        # RV-006: "the count is reported UNKNOWN => UNVERIFIED", never a silent 0.
        return {
            "name": out_name, "url_redacted": url_redacted, "remote_tip": tip,
            "local_tip": local_tip, "equal": equal, "last_push_result": last_push_str,
            "_unpushed": "UNKNOWN", "_reachable": True,
        }, "REMOTE_UNREACHABLE"

    if last_push_str.startswith("REJECTED"):
        reason = "REMOTE_REJECTED_LAST_PUSH"  # RV-005: overrides even a coincidentally-equal tip
    elif equal:
        reason = None
    elif _is_ancestor(repo_path, local_tip, tip, timeout_s, extra_env=extra_env):
        reason = "REMOTE_AHEAD"  # remote has commits local lacks
    else:
        reason = "REMOTE_TIP_DIFFERS"  # local ahead, or diverged histories

    return {
        "name": out_name, "url_redacted": url_redacted, "remote_tip": tip,
        "local_tip": local_tip, "equal": equal, "last_push_result": last_push_str,
        "_unpushed": unpushed, "_reachable": True,
    }, reason


def _pointer_fetchable(repo_path, sha, remote_names, reachable_map, timeout_s):
    """RV-003 second half: does `sha` resolve on >=1 of the submodule's remotes?

    Returns one of three strings, never a bare bool (T158 remediation round 1, finding #1):
    "FETCHABLE" (resolved on >=1 remote), "UNFETCHABLE" (every remote this call could actually
    REACH was probed and NONE had it -- a genuine, confirmed absence), or "UNVERIFIED" (no remote
    confirmed it fetchable, AND >=1 remote could not even be reached/probed -- so absence is NOT
    proven; the caller must fold this into UNVERIFIED/REMOTE_UNREACHABLE, never assert
    POINTER_UNFETCHABLE on a signal that never actually checked anything). The ORIGINAL defect
    (finding #1): a remote that could not be reached at all (network blip, moved/deleted remote)
    returned the SAME bare `False` as a remote that was reached and genuinely rejected the SHA --
    both became `POINTER_UNFETCHABLE` -> NOT_CLEAN, stating as fact that the commit is on no
    remote when the tool never actually checked. `reachable_map` (`{remote_name: bool}`, built by
    the caller from the SAME `git ls-remote` reachability signal `verify_remote` already computes
    for every remote -- never a second round-trip) says which remotes are worth probing at all; an
    unreachable remote is SKIPPED (never probed, never contributes a false "rejected"), and its
    presence alone is enough to downgrade an otherwise-"nothing found" result from UNFETCHABLE to
    UNVERIFIED, since the SHA might exist on exactly the remote this call could not check.

    MUST probe from a repo that does NOT already possess `sha` locally: probing via the
    submodule's own working repo (which always already has this exact commit checked out, since
    that is precisely what is being verified) makes `git fetch` succeed trivially regardless of
    whether the REMOTE genuinely has the object -- measured directly (2026-09-30): a same-repo
    probe fetch of a commit that was deliberately never pushed anywhere still exited 0, while the
    remote's own bare object store provably lacked it (`git cat-file -t <sha>` there: "fatal: Not
    a valid object name"). A fresh, empty, throwaway bare repo has no such shortcut: fetching the
    same never-pushed sha into it fails honestly with git's own "not our ref" (upload-pack
    refuses an unreachable/unadvertised want), while a genuinely-pushed sha succeeds -- both
    reproduced live before this function was written this way (11.4.6: never assumed).

    The probe fetch is `--depth=1 --filter=tree:0` (T158 remediation round 1, finding #2): the
    PREVIOUS unbounded full-history fetch measured 111.9s / 419MB against this very repository's
    own real constitution submodule remote -- so slow that the tool's default 30s timeout made it
    structurally impossible to ever report this submodule CLEAN; the depth/filter-limited fetch
    measured 3.2s / 44KB for the identical real HEAD (a fabricated SHA still fails honestly with
    "not our ref", rc=128 -- the negative control still works). Also verified live against a LOCAL
    file:// bare remote (the kind this tool's own RED fixtures use): the server-side filter is not
    honoured over the local-filesystem transport (git prints "warning: filtering not recognized by
    server, ignoring" and proceeds), which is harmless -- the fetch still succeeds for a real SHA
    and still fails honestly for a fabricated one; the filter simply has no effect to measure for
    that transport, it never breaks it.

    `cwd=repo_path` (T158 remediation round 1, finding #9): a RELATIVE remote URL (e.g. a
    submodule's `origin` configured as `../../sr.git`) is resolved by git relative to the process's
    OWN working directory, not `--git-dir`; with the previous `cwd=None` this resolved against
    whatever directory happened to launch this whole tool, not the submodule's own location,
    producing a false POINTER_UNFETCHABLE for a remote the submodule itself can reach fine (`git
    ls-remote` run FROM the submodule's own directory resolves the identical relative URL
    correctly) -- confirmed live before and after this fix. Repo-local URL-rewrite config
    (`url.*.insteadOf`, `core.sshCommand`, `http.*`) applying to the probe the same way it would to
    any other command run against this repository remains a documented, bounded limitation of this
    specific probe (it targets a SEPARATE, freshly-initialised throwaway bare repo that carries
    none of `repo_path`'s own repo-local config) -- constitution 11.4.6, never silently assumed
    solved; `cwd=repo_path` closes the reproduced relative-URL case, which was the concrete,
    reproducible half of finding #9."""
    any_unreachable = False
    any_probed = False
    for remote in remote_names:
        if not reachable_map.get(remote, False):
            any_unreachable = True
            continue
        url = _remote_url(repo_path, remote, timeout_s)
        if not url:
            any_unreachable = True
            continue
        any_probed = True
        with tempfile.TemporaryDirectory(prefix="fc_repo_verify_pointer_probe_") as probe_dir:
            rc0, _o, _e = _run(["git", "init", "-q", "--bare", probe_dir], repo_path, timeout_s)
            if rc0 != 0:
                any_unreachable = True
                continue
            rc, _out, _err = _run(
                ["git", "-c", "gc.auto=0", "--git-dir=" + probe_dir, "fetch", "--no-tags", "-q",
                 "--no-write-fetch-head", "--depth=1", "--filter=tree:0", url, "%s:refs/probe" % sha],
                repo_path, timeout_s)
            if rc == 0:
                return "FETCHABLE"
    if any_unreachable or not any_probed:
        return "UNVERIFIED"
    return "UNFETCHABLE"


# --------------------------------------------------------------------------------- single repo

def verify_single_repo(repo_path, relpath, timeout_s, is_submodule, parent_gitlink,
                        required_remotes=(), scratch_objdir=None):
    rc, out, err = _run(["git", "rev-parse", "HEAD"], repo_path, timeout_s)
    if rc != 0:
        raise RepoUnreadable(relpath, "git rev-parse HEAD failed: %s" % (err.strip() or ("exit %s" % rc)))
    head = out.strip()
    if not _SHA_RE.match(head):
        raise RepoUnreadable(relpath, "git rev-parse HEAD did not return a sha: %r" % head)

    rc2, branch_out, _err2 = _run(["git", "symbolic-ref", "--short", "-q", "HEAD"], repo_path, timeout_s)
    branch = branch_out.strip() if rc2 == 0 and branch_out.strip() else None  # None = detached

    _ok, dirty, untracked = worktree_status(repo_path, timeout_s)

    reasons = []
    if dirty:
        reasons.append("DIRTY_TREE")
    if untracked:
        reasons.append("UNTRACKED_FILES")

    pointer_matches = True
    if is_submodule and parent_gitlink is not None:
        pointer_matches = (parent_gitlink == head)
        if not pointer_matches:
            reasons.append("DETACHED_POINTER_DRIFT")

    remote_names = list_remotes(repo_path, timeout_s)
    push_log = read_push_log(repo_path)
    tmp_ns = "refs/fastcycle_verify/%d_%s" % (os.getpid(), re.sub(r"[^A-Za-z0-9_]", "_", relpath) or "root")
    real_objects_dir = _git_objects_dir(repo_path, timeout_s)
    remotes_out = []
    unpushed_map = {}
    reachable_map = {}
    saw_unreachable = False
    try:
        for remote in remote_names:
            url = _remote_url(repo_path, remote, timeout_s)
            redacted = redact_url(url)
            rr, reason = verify_remote(repo_path, remote, head, branch, timeout_s, tmp_ns,
                                        push_log.get(remote), remote, redacted,
                                        scratch_objdir, real_objects_dir)
            unpushed_map[remote] = rr.pop("_unpushed")
            reachable_map[remote] = rr.pop("_reachable")
            rr.pop("_detail", None)
            remotes_out.append(rr)
            if reason == "REMOTE_UNREACHABLE":
                saw_unreachable = True
            elif reason and reason not in reasons:
                reasons.append(reason)

            # RV FR-020 / T158 remediation round 1 finding #3: `git ls-remote`/`git fetch` above
            # only ever queried the FETCH url -- a PUSH destination that differs (an explicit
            # `pushurl`, or more than one) would otherwise go completely unverified, a PASS-bluff
            # ("pushed" never actually checked against what `git push` itself would use). Checked
            # for every push url that is NOT identical to the already-checked fetch url; the
            # common case (no explicit pushurl configured) costs nothing extra -- the one distinct
            # push url IS the fetch url, skipped below.
            for push_url in _push_urls(repo_path, remote, timeout_s):
                if url is not None and push_url == url:
                    continue
                push_out_name = "%s:push" % remote
                push_rr, push_reason = verify_remote(
                    repo_path, push_url, head, branch, timeout_s, tmp_ns, push_log.get(remote),
                    push_out_name, redact_url(push_url), scratch_objdir, real_objects_dir)
                push_rr.pop("_unpushed", None)
                push_rr.pop("_reachable", None)
                push_rr.pop("_detail", None)
                remotes_out.append(push_rr)
                if push_reason == "REMOTE_UNREACHABLE":
                    saw_unreachable = True
                elif push_reason and push_reason not in reasons:
                    reasons.append(push_reason)

        pointer_status = None
        if is_submodule:
            pointer_status = _pointer_fetchable(repo_path, head, remote_names, reachable_map, timeout_s)
            if pointer_status == "UNFETCHABLE":
                reasons.append("POINTER_UNFETCHABLE")
            elif pointer_status == "UNVERIFIED":
                saw_unreachable = True
    finally:
        _sweep_ref_namespace(repo_path, tmp_ns)

    # T158 remediation round 1, findings #4/#5: a repo with NO configured remotes at all (or one
    # missing a `--remotes-config`-declared required remote NAME) proves nothing was ever pushed
    # anywhere -- never read as vacuously CLEAN. The closed reason-code set (data-model.md #12.1)
    # has no more specific code for this; UNPUSHED_COMMITS is the one that fits and was, before
    # this fix, never emitted at all.
    missing_required = sorted(set(required_remotes) - set(remote_names)) if required_remotes else []
    if (not remote_names or missing_required) and "UNPUSHED_COMMITS" not in reasons:
        reasons.append("UNPUSHED_COMMITS")

    if saw_unreachable:
        reasons.append("REMOTE_UNREACHABLE")
    reasons = sorted(set(reasons))

    not_clean_reasons = [r for r in reasons if r != "REMOTE_UNREACHABLE"]
    if not_clean_reasons:
        status = "NOT_CLEAN"
    elif "REMOTE_UNREACHABLE" in reasons:
        status = "UNVERIFIED"
    else:
        status = "CLEAN"

    return {
        "path": relpath,
        "head": head,
        "branch": branch,
        "worktree_clean": not dirty and not untracked,
        "dirty_entries": dirty,
        "untracked": untracked,
        "unpushed": unpushed_map,
        "remotes": remotes_out,
        "submodule_pointer_matches_checkout": pointer_matches,
        "status": status,
        "reasons": reasons,
    }


def _uninitialised_result(relpath, gitlink):
    return {
        "path": relpath, "head": gitlink or "UNKNOWN", "branch": None, "worktree_clean": False,
        "dirty_entries": [], "untracked": [], "unpushed": {}, "remotes": [],
        "submodule_pointer_matches_checkout": False, "status": "NOT_CLEAN",
        "reasons": ["SUBMODULE_UNINITIALISED"],
    }


def _walk(repo_path, relpath, out_list, timeout_s, is_submodule=False, parent_gitlink=None,
          required_remotes=(), scratch_objdir=None):
    result = verify_single_repo(repo_path, relpath, timeout_s, is_submodule, parent_gitlink,
                                 required_remotes, scratch_objdir)
    out_list.append(result)
    parent_head = result["head"]
    for sub_rel in list_gitmodules(repo_path, timeout_s):  # RV-001: sorted, depth-first
        sub_path = os.path.join(repo_path, sub_rel)
        combined_rel = _join_rel(relpath, sub_rel)
        gitlink = parent_gitlink_sha(repo_path, sub_rel, parent_head, timeout_s)
        if not _is_initialised(sub_path):
            out_list.append(_uninitialised_result(combined_rel, gitlink))
            continue
        _walk(sub_path, combined_rel, out_list, timeout_s, is_submodule=True, parent_gitlink=gitlink,
              required_remotes=required_remotes, scratch_objdir=scratch_objdir)


def read_remotes_config(path):
    """--remotes-config (T158 remediation round 1, finding #5 -- accepted on the command line
    since this tool's original landing but never actually READ until now): optional JSON
    `{"required_remotes": ["<name>", ...]}` naming remote NAMES that MUST be configured on EVERY
    repository walked (main + every submodule, constitution 2.1 "push to ALL upstreams") -- a repo
    missing any of them is folded into `UNPUSHED_COMMITS` by `verify_single_repo` (data-model.md
    #12.1 has no more specific closed reason code for a declared-but-absent upstream). Absent file,
    unreadable JSON, a non-object document, or a `required_remotes` value that is not a JSON list
    all yield [] -- never silently invents a requirement the caller did not actually give, and
    never crashes (an EXPLICITLY-given but unreadable --remotes-config path already fails closed
    in main(), before this function is ever called)."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return []
    names = data.get("required_remotes") if isinstance(data, dict) else None
    if not isinstance(names, list):
        return []
    return sorted(set(n for n in names if isinstance(n, str) and n.strip()))


def verify_recursive(root, timeout_s, required_remotes=()):
    repos = []
    scratch_objdir = tempfile.mkdtemp(prefix="fc_repo_verify_objredirect_")
    try:
        _walk(os.path.abspath(root), ".", repos, timeout_s, required_remotes=required_remotes,
              scratch_objdir=scratch_objdir)
    finally:
        shutil.rmtree(scratch_objdir, ignore_errors=True)
    repos.sort(key=lambda r: r["path"])

    statuses = [r["status"] for r in repos]
    if all(s == "CLEAN" for s in statuses):
        overall = "CLEAN"
    elif any(s == "NOT_CLEAN" for s in statuses):  # RV-008: NOT_CLEAN wins over a mix
        overall = "NOT_CLEAN"
    elif any(s == "UNVERIFIED" for s in statuses):
        overall = "UNVERIFIED"
    else:
        overall = "CLEAN"

    reasons_histogram = {}
    for r in repos:
        for reason in r["reasons"]:
            reasons_histogram[reason] = reasons_histogram.get(reason, 0) + 1

    summary = {
        "repos": len(repos),
        "clean": sum(1 for s in statuses if s == "CLEAN"),
        "not_clean": sum(1 for s in statuses if s == "NOT_CLEAN"),
        "blind": sum(1 for s in statuses if s == "UNVERIFIED"),
        "reasons_histogram": reasons_histogram,
    }
    return {"root": os.path.abspath(root), "repos": repos, "overall": overall, "summary": summary}


# -------------------------------------------------------------------- self-check (control needle)

def self_check(timeout_s):
    """Contract exit 3: prove worktree_status() genuinely SEES, before trusting any real finding
    (constitution 11.4.201/11.4.273). Returns None on success, else a diagnostic string."""
    with tempfile.TemporaryDirectory(prefix="fc_repo_verify_selfcheck_") as tmp:
        rc, _out, err = _run(["git", "init", "-q", "-b", "main", tmp], None, timeout_s)
        if rc != 0:
            return "self-check FAILED: cannot init synthetic control-needle repo: %s" % err
        _run(["git", "config", "user.email", "fc@example.invalid"], tmp, timeout_s)
        _run(["git", "config", "user.name", "fastcycle"], tmp, timeout_s)
        try:
            _ok, dirty0, untracked0 = worktree_status(tmp, timeout_s)
        except RepoUnreadable as exc:
            return "self-check FAILED: a brand-new synthetic repo could not even be read: %s" % exc
        if dirty0 or untracked0:
            return ("self-check FAILED: a brand-new empty git repo was reported dirty/untracked "
                     "(dirty=%r untracked=%r) -- worktree_status() itself is broken" % (dirty0, untracked0))
        needle = os.path.join(tmp, "needle.txt")
        with open(needle, "w", encoding="utf-8") as fh:
            fh.write("control needle\n")
        try:
            _ok2, _dirty2, untracked2 = worktree_status(tmp, timeout_s)
        except RepoUnreadable as exc:
            return "self-check FAILED: repo became unreadable after adding the needle file: %s" % exc
        if "needle.txt" not in untracked2:
            return ("self-check FAILED: a known-present untracked file (needle.txt) was NOT "
                     "detected -- worktree_status() cannot be trusted (11.4.201/11.4.273)")
        if "fabricated_absent.txt" in untracked2:
            return "self-check FAILED: a fabricated, never-created file was wrongly reported present"
    return None


# ------------------------------------------------------------------------------------- markdown

def _write_markdown(path, report):
    lines = ["# Recursive verification report", "", "Overall: **%s**" % report["overall"], "",
             "| Repo | Status | Head | Reasons |", "|---|---|---|---|"]
    for r in report["repos"]:
        lines.append("| %s | %s | %s | %s |" % (r["path"], r["status"], r["head"][:12], ", ".join(r["reasons"]) or "-"))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


# ----------------------------------------------------------------------------------------- CLI

def _overall_to_code(overall):
    return {"CLEAN": 0, "NOT_CLEAN": 1, "UNVERIFIED": 4}[overall]


def _run_once(a):
    self_err = self_check(a.timeout_per_remote)
    if self_err:
        print("repo_verify: %s" % self_err, file=sys.stderr)
        return 3
    try:
        report = verify_recursive(a.root, a.timeout_per_remote, a.required_remotes)
    except RepoUnreadable as exc:
        print("repo_verify: BLIND -- repo unreadable at %r: %s" % (exc.relpath, exc.detail), file=sys.stderr)
        return 4

    for r in report["repos"]:
        if r["reasons"]:
            print("repo_verify: %s %s reasons=%s" % (r["path"], r["status"], ",".join(r["reasons"])), file=sys.stderr)

    code = _overall_to_code(report["overall"])
    ns = argparse.Namespace(schema=SCHEMA, body_json=json.dumps(report), run_meta_json=None,
                             out=a.out, code=(1 if code == 1 else (4 if code == 4 else 0)))
    write_rc = fc_common.cmd_emit(ns)
    if a.md:
        _write_markdown(a.md, report)
    if write_rc != ns.code:
        # fc_common.cmd_emit only ever diverges from the requested code on a write/encode error
        # (returns 2) -- surface that honestly rather than claim the verdict this tool computed.
        return write_rc
    return code


def _run_determinism_check(a):
    self_err = self_check(a.timeout_per_remote)
    if self_err:
        print("repo_verify: %s" % self_err, file=sys.stderr)
        return 3
    docs = []
    for i in (1, 2):
        try:
            report = verify_recursive(a.root, a.timeout_per_remote, a.required_remotes)
        except RepoUnreadable as exc:
            print("repo_verify: BLIND on run %d -- repo unreadable at %r: %s" % (i, exc.relpath, exc.detail),
                  file=sys.stderr)
            return 4
        doc = dict(report)
        doc["schema"] = SCHEMA
        docs.append(doc)
    hashes = [fc_common.body_hash_of(d) for d in docs]
    if hashes[0] == hashes[1]:
        return 0
    print("repo_verify: nondeterministic body_hash %s != %s" % (hashes[0], hashes[1]), file=sys.stderr)
    bodies = [fc_common.canon({k: v for k, v in d.items() if k not in fc_common.EXCLUDED}) for d in docs]
    diff = list(difflib.unified_diff(bodies[0].splitlines(), bodies[1].splitlines(), "run1", "run2", lineterm="", n=1))
    for line in diff[:60]:
        print(line, file=sys.stderr)
    return 1


def main(argv):
    p = argparse.ArgumentParser(prog="repo_verify.py")
    p.add_argument("--recursive", action="store_true")
    p.add_argument("--root", required=True)
    p.add_argument("--remotes-config")
    p.add_argument("--out", required=True)
    p.add_argument("--md")
    p.add_argument("--determinism-check", action="store_true")
    p.add_argument("--timeout-per-remote", type=int, default=DEFAULT_TIMEOUT_S)
    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    if not a.recursive:
        print("repo_verify: --recursive is required (no other mode implemented)", file=sys.stderr)
        return 2
    if a.timeout_per_remote < 1:
        print("repo_verify: --timeout-per-remote must be >= 1", file=sys.stderr)
        return 2
    if not os.path.isdir(a.root):
        print("repo_verify: BLIND -- --root is not a directory: %s" % a.root, file=sys.stderr)
        return 4
    if a.remotes_config and not os.path.isfile(a.remotes_config):
        # common-conventions "Placement": a config the tool cannot find fails closed, exit 2,
        # naming the missing key -- never guessing (11.4.6). --remotes-config is optional per the
        # contract's invocation line; only an EXPLICITLY-given, unreadable path fails closed.
        print("repo_verify: --remotes-config file not found: %s" % a.remotes_config, file=sys.stderr)
        return 2
    # T158 remediation round 1, finding #5: actually READ the config (previously only
    # existence-checked above, then silently discarded) -- see read_remotes_config().
    a.required_remotes = read_remotes_config(a.remotes_config) if a.remotes_config else []

    try:
        if a.determinism_check:
            return _run_determinism_check(a)
        return _run_once(a)
    except Exception as exc:  # C-001: an internal error is never a finding (1) -- BLIND (4)
        print("repo_verify: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
