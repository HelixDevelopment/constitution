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

Unpushed count (RV-006): the remote's live tip SHA is fetched (read-only) as a bare object -- no
ref is created anywhere (since T158 remediation round 2, finding I1; the object itself lands only
in a process-lifetime scratch object store, see "Safety" below). `git rev-list --count
<fetched_tip>..HEAD` against that SHA then gives the real unpushed count; a fetch failure (the
tip object cannot be obtained) reports `unpushed: "UNKNOWN"` for that remote and folds the repo
into UNVERIFIED (never a silent 0, constitution 11.4.201(6)'s false-null guard).

Enumeration (RV-001, extended in T158 round 5, finding I5-2): submodules are walked from
`.gitmodules`, AND every mode-160000 gitlink in each repo's HEAD tree (`git ls-tree -r`) is
cross-checked against that set -- a gitlink present in the tree but unmapped by `.gitmodules`
(a plain `git add` of a nested repo, or a hand-written index entry) is reported NOT_CLEAN with
`SUBMODULE_UNMAPPED`, never silently skipped (a fresh clone cannot fetch it at all).

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
the same way (live tip read, read-only bare-SHA fetch into the scratch object store -- no ref
written, since round 2's I1 fix -- equality/ahead/differs classification),
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
(grep-verifiable). No ref is written in any repository under `--root` (since T158 remediation
round 2, finding I1, every fetch targets a bare SHA, never a `sha:ref` destination); the RV-009
`refs/fastcycle_verify/<pid>_<repo>/` sweep at exit is retained only as a belt-and-braces check of
THIS process's own namespace (it never touches refs a different process created). Every git
invocation runs with `GIT_OPTIONAL_LOCKS=0` (git's own documented mechanism for skipping
opportunistic index/stat-cache rewrites it would otherwise perform during e.g. `git status`;
test-pinned since T158 round 4, finding I4-3, by a stale-stat fixture at top level AND in a
submodule whose paired mutation proves both .git/index files are rewritten without it) and every fetch into a real repository's own git-dir passes `--no-write-fetch-head` (never
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
import signal
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
    # T158 round 5 (I5-2): a gitlink in the HEAD tree with no `.gitmodules` mapping -- addition to
    # data-model.md #12.1's closed set (contract addendum noted in recursive-verification.md).
    "SUBMODULE_UNMAPPED",
)

# Operator-tunable default; the contract states no measured bound. Overridable via
# --timeout-per-remote. Matches this tree's own convention of naming such defaults as
# engineering guesses, never data (see lib/fc_common.py DETERMINISM_TIMEOUT_DEFAULT_S).
DEFAULT_TIMEOUT_S = 30

_SHA_RE = re.compile(r"^[0-9a-f]{40}$")

# T158 remediation round 2, finding B1 (BLOCKING): the ONLY stderr shapes that mean a reachable
# remote DEFINITIVELY rejected a `fetch <url> <sha>` want because the object is genuinely not
# advertised there -- upload-pack's own refusal of an unreachable/unadvertised want (confirmed
# live, both for a never-existing SHA and a genuinely-never-pushed real commit: "fatal: git
# upload-pack: not our ref <sha>" / "fatal: remote error: upload-pack: not our ref <sha>"). ANY
# other nonzero exit (auth failure, connection refused, unknown host, a repo-local config the
# probe's fresh scratch repo does not inherit, or a timeout -- `rc=None`, which never even reaches
# this pattern match) is NOT proof of absence and MUST NOT be treated as one (11.4.201/11.4.6).
_DEFINITIVE_ABSENCE_RE = re.compile(
    r"not our ref|couldn't find remote ref|unadvertised object", re.IGNORECASE)


def _is_definitive_absence(stderr):
    return bool(_DEFINITIVE_ABSENCE_RE.search(stderr or ""))


class RepoUnreadable(Exception):
    """git itself could not resolve HEAD for a repository already reported present on disk --
    a genuinely unreadable repo, distinct from an unreachable REMOTE (which still yields a full
    partial report, C-001 code 4). No honest verdict is possible; nothing is written."""

    def __init__(self, relpath, detail):
        super().__init__(detail)
        self.relpath = relpath
        self.detail = detail


class RemotesConfigError(Exception):
    """T158 remediation round 2, finding I2: `--remotes-config` names a file the operator
    EXPLICITLY supplied expecting its declared requirement to be honored; a malformed/wrongly-
    shaped document (truncated JSON, wrong JSON type, a typo'd key, a non-object top level) MUST
    fail closed (exit 2, naming the specific problem) rather than be silently read as "no
    requirement" -- the round-1 fix only ever returned `[]` for every one of these shapes, which
    an operator cannot distinguish from "I have no required remotes" (the exact silent-drop this
    exception exists to make impossible, 11.4.6)."""


class Terminated(Exception):
    """T158 remediation round 2, finding I1: raised by the SIGTERM handler installed in main() so
    a clean `kill <pid>` (unlike SIGKILL, which this process cannot intercept at all) unwinds
    through every open `finally:`/`with:` block exactly like any other exception -- the scratch
    object-store tempdir (verify_recursive), the self-check synthetic repo
    (self_check/_pointer_fetchable's own `tempfile.TemporaryDirectory` context managers), and the
    RV-009 stale-ref sweep (verify_single_repo's `finally:`) all still run during a terminate
    signal instead of being abandoned mid-run. Caught by main()'s own broad `except Exception`
    (never 1 -- reserved for findings) and reported as BLIND (4), not an uncaught traceback."""


# T158 remediation round 5 (found while verifying the round-5 reviewer's MINOR claim that an
# inherited GIT_DIR/GIT_INDEX_FILE "fails closed at rc=3" -- measured live, it does NOT): when this
# tool runs inside a git hook (or any shell with GIT_DIR exported) every git subprocess silently
# targets THAT repository instead of the one named by `cwd` -- the self-check's synthetic `git init`
# + `git config user.email` were confirmed to REWRITE the caller's real `.git/config`, and the walk
# reports on the wrong repo. Every repository-locating variable git itself lists via
# `git rev-parse --local-env-vars` (git 2.50.1 list, verbatim) is therefore stripped from every
# subprocess environment; `extra_env` (the RV-009 object-store redirect) is applied AFTER the strip.
_GIT_LOCAL_ENV_VARS = (
    "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
    "GIT_OBJECT_DIRECTORY", "GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE", "GIT_GRAFT_FILE",
    "GIT_INDEX_FILE", "GIT_NO_REPLACE_OBJECTS", "GIT_REPLACE_REF_BASE", "GIT_PREFIX",
    "GIT_SHALLOW_FILE", "GIT_COMMON_DIR",
)


# T177 Round 17 (R16-I1 IMPORTANT + R16-B1 BLOCKING; wording corrected T177 Round 19,
# M-2 -- the line above overclaimed "neither execute repository-config-driven programs
# nor read substituted objects"; stated narrowly, mirroring migrate.sh's own R16-M1
# correction for the SAME class of overclaim: this strip + the explicit `-c` overrides
# below stop git's OWN hook mechanism (`.git/hooks/*`, `core.hooksPath`), a configured
# fsmonitor, `refs/replace/*` substitution, and commit-graph-cached parsing from running
# during this tool's own git calls. They do NOT neutralise every repository-config-driven
# executable this tool's calls can reach: clean/smudge filter drivers (`.gitattributes` /
# `.git/info/attributes` + `filter.<name>.*`) have no global off switch and, BY DEFAULT, still
# run during this tool's OWN `worktree_status()` `git status` call (RV-002) -- T177 Round 23
# adds the opt-in `--neutralize-repo-filters` (see _FILTER_OVERRIDES below), which migrate.sh
# passes; a standalone caller that omits it keeps this disclosed boundary -- and the
# push-transport-adjacent executables (`core.sshCommand`, `credential.helper`,
# `remote.<r>.uploadpack`, `url.*.insteadOf` -> `ext::`) are left alone and still run
# during this tool's `git fetch` calls (verify_remote/self_check) -- left alone because a
# consumer may legitimately rely on them to reach its own remotes, and because this tool
# never writes through them (read-only `fetch`, never `push`). The strip above removes
# GIT_CONFIG_COUNT/GIT_CONFIG_PARAMETERS/GIT_NO_REPLACE_OBJECTS/GIT_GRAFT_FILE from every
# subprocess -- for a legitimate reason (they are on git's own `--local-env-vars` list, and an
# inherited copy belongs to whatever repository the CALLER was operating on, not necessarily the
# one this tool is reading) -- which means an override a caller exported through the environment
# (migrate.sh's hooks-disabled block) never reached these calls: measured live in round 16, a
# hook-set `core.fsmonitor` program ran 4 times inside this tool's own `git status` during
# migrate.sh's step-9 double verification, and a lying fsmonitor can report a dirty tree clean.
# Rather than weaken the strip, the overrides are passed EXPLICITLY on every git command line
# this tool builds (`git -c k=v ...`, the highest-precedence config scope, which no repository
# or global config can override and which git propagates to the child git processes it spawns,
# e.g. submodule recursion). An explicit per-invocation flag cannot be silently defeated by any
# future environment-sanitisation step the way an inherited variable can:
#   core.hooksPath=/dev/null   no hook (status/fetch/update-ref can fire post-index-change,
#                              reference-transaction, ...) runs during verification;
#   core.fsmonitor=false       no fsmonitor program can answer "nothing changed";
#   core.useReplaceRefs=false  `refs/replace/*` substitution is off (R16-B1: a replace ref made
#                              every read return a stand-in object while a push sends the real one);
#   core.commitGraph=false     commit objects are parsed directly, never from a (forgeable)
#                              commit-graph file's cached tree/parent fields.
# Grafts are not controllable by `-c` (and are NOT disabled by core.useReplaceRefs -- verified on
# git 2.50.1), so GIT_GRAFT_FILE=/dev/null is set in the subprocess environment AFTER the strip
# (advice.graftFileDeprecated=false: a set GIT_GRAFT_FILE otherwise prints git's deprecation hint
# to stderr on every command).
_GIT_SAFE_ARGS = (
    "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
    "-c", "core.useReplaceRefs=false", "-c", "core.commitGraph=false",
    "-c", "advice.graftFileDeprecated=false",
)


# T177 Round 23 (R22-B2 -- the filter-driver half of the honest boundary stated just above, closed
# OPT-IN for callers that need it): `--neutralize-repo-filters` makes this tool discover, before ANY
# other git read, every filter driver whose clean/smudge/process key is defined at an UNTRUSTED
# config scope (everything except command -- this tool's own overrides; T177 Round 24 (R23-B1,
# migrate.sh's own sibling copy of this discovery -- see migrate.sh's "T177 Round 24" header comment
# for the full forensic record): `global`/`system` were PREVIOUSLY also trusted here, reasoned as
# operator-owned and needed to keep a host's own `git lfs install` working -- live-reproduced as an
# overclaim: a standard `git lfs install` places `filter.lfs.{clean,smudge}` at GLOBAL scope, and
# git-lfs's own documented extension mechanism, `lfs.extension.<name>.clean`, makes that TRUSTED
# driver read and execute a command named in the repository's own LOCAL, untracked config -- removed
# from trust here for the identical reason) in --root and every initialised submodule beneath it
# (index gitlinks AND .gitmodules paths, recursively -- T177 Round 25 (R24-M1): migrate.sh's own
# sibling discovery REMOVED its equivalent .gitmodules-only branch in its Round 24 commit, with
# cited evidence it was dead code for migrate.sh's OWN specific, narrow call pattern (a single
# hardcoded "constitution" submodule, always reached via an index gitlink). That evidence does
# NOT generalise to this tool: repo_verify.py is a general-purpose, standalone verifier any caller
# may point at an arbitrary --root with an arbitrary submodule layout, so the .gitmodules branch
# stays here deliberately -- this is a DISCLOSED, intentional divergence between the two sibling
# discoveries, not an inconsistency), using the FULL
# effective config (`--show-scope --includes`; never `--local`, which is blind to include.path/
# includeIf and --worktree definitions -- the exact R22-B1 gap). Each such driver NAME is then
# neutralised on every git call this tool makes: smudge=cat, clean=cat, process= (empty: no
# long-running filter), required=false. The overrides are injected into each subprocess
# environment as GIT_CONFIG_COUNT/KEY_n/VALUE_n AFTER the inherited-variable strip in _run() (the
# same placement GIT_GRAFT_FILE already uses: this tool's OWN override, never an inherited one),
# rather than as `-c` flags -- a driver name is attacker-chosen and may contain `=`, which a
# `-c key=value` argument splits at, so only the KEY_n/VALUE_n pair addresses every legal name
# exactly. git propagates these to the child processes it spawns (the per-submodule `status`
# recursion included -- measured). Discovery that cannot complete makes the run BLIND (4), never
# "no drivers". Default OFF: a standalone caller keeps exactly the behaviour, and the disclosed
# boundary, documented above.
_FILTER_OVERRIDES = []


class FilterDiscoveryError(Exception):
    """Filter-driver discovery could not complete -- never treated as 'no drivers found'."""


def discover_untrusted_filter_drivers(root, timeout_s):
    """Return the ordered list of filter-driver names (bytes-safe str) needing neutralisation."""
    # T177 Round 24 (R23-B1 closure, migrate.sh's sibling fix): `command` is the ONLY trusted scope.
    trusted = {"command"}
    repos, seen, queue = [], set(), [root]
    while queue:
        d = queue.pop(0)
        real = os.path.realpath(d)
        if real in seen or not os.path.exists(os.path.join(d, ".git")):
            continue
        seen.add(real)
        repos.append(d)
        rc, out, err = _run(["git", "ls-files", "--stage", "-z"], d, timeout_s)
        if rc != 0:
            raise FilterDiscoveryError("ls-files rc=%s in %s: %s" % (rc, d, err.strip()))
        rels = [rec.split("\t", 1)[1] for rec in out.split("\0")
                if rec.startswith("160000 ") and "\t" in rec]
        gm = os.path.join(d, ".gitmodules")
        if os.path.isfile(gm):
            rc, out, err = _run(["git", "config", "--file", gm, "--null", "--get-regexp",
                                 r"^submodule\..*\.path$"], d, timeout_s)
            if rc not in (0, 1):
                raise FilterDiscoveryError("reading .gitmodules rc=%s in %s" % (rc, d))
            rels += [rec.partition("\n")[2] for rec in out.split("\0") if rec]
        for rel in rels:
            if not rel or rel.startswith("/") or ".." in rel.split("/"):
                continue
            queue.append(os.path.join(d, rel))
    names = []
    for d in repos:
        rc, out, err = _run(["git", "config", "--show-scope", "--includes", "--null",
                             "--get-regexp", r"^filter\."], d, timeout_s)
        if rc == 1:
            continue
        if rc != 0:
            raise FilterDiscoveryError("config rc=%s in %s: %s" % (rc, d, err.strip()))
        toks = out.split("\0")
        if toks and toks[-1] == "":
            toks.pop()
        if len(toks) % 2:
            raise FilterDiscoveryError("unparseable config listing in %s" % d)
        for scope, kv in zip(toks[0::2], toks[1::2]):
            key = kv.partition("\n")[0]
            if scope in trusted or not key.startswith("filter.") or key.count(".") < 2:
                continue
            name, var = key[len("filter."):].rsplit(".", 1)
            if var.lower() in ("clean", "smudge", "process") and name not in names:
                names.append(name)
    return names


def install_filter_overrides(names):
    del _FILTER_OVERRIDES[:]
    for name in names:
        for var, val in (("smudge", "cat"), ("clean", "cat"), ("process", ""), ("required", "false")):
            _FILTER_OVERRIDES.append(("filter.%s.%s" % (name, var), val))


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
    for _k in _GIT_LOCAL_ENV_VARS:
        env.pop(_k, None)
    env["GIT_GRAFT_FILE"] = os.devnull
    if _FILTER_OVERRIDES:
        for _i, (_key, _val) in enumerate(_FILTER_OVERRIDES):
            env["GIT_CONFIG_KEY_%d" % _i] = _key
            env["GIT_CONFIG_VALUE_%d" % _i] = _val
        env["GIT_CONFIG_COUNT"] = str(len(_FILTER_OVERRIDES))
    if args and args[0] == "git":
        args = [args[0], *_GIT_SAFE_ARGS, *args[1:]]
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


AMBIGUOUS_URL_PLACEHOLDER = "REDACTED_AMBIGUOUS_URL"


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
    the last two.

    T158 remediation round 2, MINOR finding (a NEW, narrower gap than round 1's -- all 3 of
    round 1's own leak shapes stay fixed): a query string or `#` fragment can itself carry
    credential material (e.g. `?token=SECRET123`) and, since it comes strictly AFTER the final
    path segment in a well-formed URI, previously rendered verbatim (the ".git"-suffix strip above
    only ever matched a LITERAL trailing ".git", never anything following a `?`/`#`). Both a query
    string and a fragment always sit strictly AFTER the authority (`user:pass@host`) component, so
    truncating at the FIRST of either can never remove credential text that belongs earlier in the
    string -- it only ever discards bytes that come after it.

    T158 remediation round 3, IMPORTANT finding I-N1 (a genuine REGRESSION introduced by round
    2's own fix immediately above -- confirmed live against 4 URLs, constitution 11.4.10): round
    2's fix stripped the query/fragment from the WHOLE (scheme-stripped) string BEFORE searching
    for the last `@` -- so a `?` or `#` character appearing INSIDE the userinfo portion, BEFORE
    the real `@` (e.g. `user:pa#ss@github.com/org/repo.git`), truncated the search string too
    early, and the credential text in front of that `?`/`#` was then treated as the WHOLE "host"
    -- i.e. printed VERBATIM in the supposedly-redacted output (round 2's own docstring claim
    that "this truncation can never discard credential text" was therefore FALSE, confirmed by
    direct comparison against the pre-round-2 (`adfd2c8~1`) behaviour, which handled all 4 of
    these cases correctly). FIXED by reversing the order round 2 got backwards, exactly per the
    fix direction: find the LAST `@` in the RAW, UNSTRIPPED string first, keep only the text
    strictly after it, and only THEN strip any `?`/`#` from THAT remainder -- never strip before
    locating `@` (see `_authority_tail` below). Verified against all 4 of round 3's own repro
    URLs: both of round 2's own `#`/`?`-as-userinfo-decoy shapes, a bare secret-as-username with
    a trailing `#`, and a scp/ssh-style authority with no `://` scheme at all. A residual edge
    case the same finding flags (a query string that ITSELF carries a literal `@`, e.g.
    `?u=a@SECRET`, where naively taking "text after the last @" would instead render query DATA
    as if it were the host) is additionally guarded in `_authority_tail`: when the globally-last
    `@` sits at or after a `?`/`#` that is itself preceded by at least one `/` (i.e. the `?`/`#`
    plausibly marks a genuine query/fragment start, positioned after real path segments, rather
    than being a decoy character embedded directly in credential/host text with no path segment
    yet) that `@` is treated as untrustworthy and the authority boundary is instead re-derived
    from only the portion strictly before that `?`/`#`. [Superseded by round 4 -- see below.]

    T158 remediation round 4, IMPORTANT findings I4-1 / I4-2 (round 3's `/`-before-`?` heuristic
    was itself a guess, and leaked credential text whenever userinfo carried BOTH an embedded `/`
    AND a `?`/`#` -- e.g. `https://tok/en?x@github.com/o/r.git` rendered `tok/en`; it also
    introduced a NEW leak in the scp form `user:SE/CR?ET@github.com:org/repo.git` -> `user/SE/CR`).
    Rounds 1-3 each patched the shape that prompted them; this round replaces the heuristic with a
    STRUCTURAL decision that never guesses. Let `s` be the scheme-stripped string, `q` the index
    of its FIRST `?` or `#` (len(s) if neither occurs) and `a` the index of its LAST `@` (-1 if
    none). Exactly three cases exist, and they are exhaustive:

      (1) a == -1 (no `@` at all): there is no userinfo, so no credential text can exist before a
          host; render `s` truncated at `q`.
      (2) a < q (every `@` sits strictly before the first `?`/`#`, including "no `?`/`#` at all"):
          the real userinfo separator, if any, is SOME `@` at index <= a, so every credential byte
          sits at or before `a`. Render only `s[a+1:]`, truncated at its own first `?`/`#` (a
          query/fragment that may carry a token). No byte at or before `a` can reach the output.
      (3) a >= q (the last `@` sits at or after the first `?`/`#`): the boundary is GENUINELY
          AMBIGUOUS -- either the `?`/`#` is a decoy inside credential text and `a` is the real
          separator (then `s[:q]` is credential text), or the `?`/`#` starts a real query and `a`
          is query DATA (then `s[a+1:]` may be a token). Both readings are syntactically valid
          and no local evidence can tell them apart (`https://tok/en?x@github.com/o/r.git` and
          `https://host/o/r.git?u=a@SECRET` have the identical shape), so this case FAILS CLOSED
          and returns the fixed placeholder `REDACTED_AMBIGUOUS_URL` -- never ANY substring of
          `s`. This deliberately sacrifices the host display for a legitimate URL whose query
          carries a literal `@` (e.g. `https://host/o/r.git?u=a@S`, previously rendered
          `host/o/r`) in exchange for never emitting credential bytes.

    The round-3 inner-`@` strip branch (I4-2's subject) no longer exists: case (3) now never
    inspects either side of the ambiguous boundary, so there is no strip logic left to validate;
    its regression is instead pinned by fixtures asserting the placeholder for that exact shape
    plus a paired mutation that restores the round-3 branch. Honest boundary (11.4.6): this
    guarantees no byte positioned at or before the last `@` (case 2) and no byte at all (case 3)
    reaches the output; it does NOT promise a useful rendering for every malformed URL (case 3
    URLs and the scheme-less fallback may render as the placeholder or a basename)."""
    if not url:
        return "UNKNOWN"
    m = re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://(.*)$", url, re.DOTALL)
    if m:
        after_at = _authority_tail(m.group(1))
        if after_at is None:
            return AMBIGUOUS_URL_PLACEHOLDER
        segments = [p for p in after_at.split("/") if p]
        if segments and segments[-1].endswith(".git"):
            segments[-1] = segments[-1][:-4]
        return "/".join(segments) if segments else "UNKNOWN"
    cand = _authority_tail(url)
    if cand is None:
        return AMBIGUOUS_URL_PLACEHOLDER
    m2 = re.match(r"^([^:/]+):(.+)$", cand)
    if m2 and "/" in m2.group(2):
        host, path = m2.group(1), m2.group(2)
        if path.endswith(".git"):
            path = path[:-4]
        segments = [host] + [p for p in path.split("/") if p]
        return "/".join(segments)
    return os.path.basename(os.path.normpath(cand)) or cand


def _authority_tail(s):
    """T158 remediation round 4 (I4-1/I4-2): return the text strictly after the LAST `@` with any
    query/fragment removed, or None when the userinfo/host boundary is ambiguous (fail closed --
    the caller renders `AMBIGUOUS_URL_PLACEHOLDER`, never any substring of `s`). See
    `redact_url`'s docstring for the exhaustive three-case decision boundary:
    no `@` -> strip query; last `@` strictly before the first `?`/`#` -> text after that `@`,
    query stripped; last `@` at/after the first `?`/`#` -> None."""
    qpos = len(s)
    for sep in ("?", "#"):
        idx = s.find(sep)
        if idx != -1 and idx < qpos:
            qpos = idx
    at = s.rfind("@")
    if at == -1:
        return _strip_query_fragment(s)
    if at >= qpos:
        return None
    return _strip_query_fragment(s[at + 1:])


def _strip_query_fragment(s):
    """Truncate `s` at the first `?` or `#`, whichever comes first. T158 remediation round 3,
    finding I-N1: this is now ONLY ever called (via `_authority_tail`) on text already known to
    be strictly AFTER the real userinfo `@` separator (or on the whole string when no `@` is
    present at all) -- never on text that might still contain an unresolved `@`, which was
    precisely round 2's bug. So this can never discard credential text, only bytes that come
    after it."""
    cut = len(s)
    for sep in ("?", "#"):
        idx = s.find(sep)
        if idx != -1 and idx < cut:
            cut = idx
    return s[:cut]


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


# T158 remediation round 5, finding I5-1: the push-log `message` is UNTRUSTED free text (the
# obvious future wrapper implementation stores git's own push stderr verbatim, which routinely
# contains `To https://user:TOKEN@host/...`). It is therefore NEVER copied into the report unless
# it passes a strict allow-list: short, single-line, only [A-Za-z0-9 space . , ( ) - _ '], and so
# structurally incapable of carrying a URL (no ':', '/', '@'), a key=value secret (no '='), or a
# multi-line stderr dump. Anything else is replaced by a FIXED category string chosen by keyword
# match -- the raw text never reaches the report (C-006). Honest boundary (11.4.6): an allow-listed
# message could in principle still contain a bare credential WORD with no URL/`=`/`:` context
# around it (e.g. "rejected ghpXXXX"); git's own rejection output does not produce that shape, and
# a wrapper writing one would be writing a bare secret into a log by design.
_PUSH_MSG_SAFE_RE = re.compile(r"^[A-Za-z0-9 .,()_'-]{0,120}$")
_PUSH_MSG_CATEGORIES = (
    ("non-fast-forward", "non-fast-forward"),
    ("fetch first", "fetch-first"),
    ("hook declined", "hook-declined"),
    ("pre-receive", "hook-declined"),
    ("permission", "permission-denied"),
    ("denied", "permission-denied"),
    ("authentication", "authentication-failed"),
    ("403", "permission-denied"),
    ("401", "authentication-failed"),
    ("protected branch", "protected-branch"),
)
PUSH_MSG_WITHHELD_SUFFIX = "; raw message withheld"


def _sanitize_push_message(msg):
    """I5-1: return text safe to embed in `REJECTED(<msg>)` -- the message itself when it passes
    the allow-list above, otherwise a fixed category + PUSH_MSG_WITHHELD_SUFFIX. Never returns any
    substring of a message that failed the allow-list."""
    if not isinstance(msg, str):
        return "unrecognised" + PUSH_MSG_WITHHELD_SUFFIX
    if _PUSH_MSG_SAFE_RE.match(msg):
        return msg
    low = msg.lower()
    for needle, category in _PUSH_MSG_CATEGORIES:
        if needle in low:
            return category + PUSH_MSG_WITHHELD_SUFFIX
    return "unrecognised" + PUSH_MSG_WITHHELD_SUFFIX


def _push_result_str(entry):
    if not isinstance(entry, dict):
        return "UNKNOWN"
    result = entry.get("result")
    if result == "ACCEPTED":
        return "ACCEPTED"
    if result == "REJECTED":
        return "REJECTED(%s)" % _sanitize_push_message(entry.get("message", ""))
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


def verify_remote(repo_path, git_target, local_tip, branch, timeout_s, push_log_entry,
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
    honestly to the pre-fix behaviour (no redirect) rather than fail the whole check.

    T158 remediation round 2, finding I1 (IMPORTANT -- a genuine safety regression introduced by
    round 1's own finding-#6 fix): the PREVIOUS form fetched `<tip>:<tmp_ref>` -- an explicit
    colon-refspec -- which git ALWAYS writes into the "current" repository's OWN refs namespace
    regardless of GIT_OBJECT_DIRECTORY (that env var redirects only where OBJECTS land, never
    where REFS land); since `repo_path` itself (never a separate scratch repo) was, and still is,
    the "current" repository here (needed so a CONFIGURED REMOTE NAME resolves against
    `repo_path`'s own `.git/config` -- a literal URL would lose repo-local `core.sshCommand` /
    `http.*` / `url.*.insteadOf` / credential-helper config the SAME way `_pointer_fetchable`'s
    own probe already documents as a bounded limitation, see its docstring), a temp ref was
    written into `repo_path`'s real refs/ tree pointing at an object that existed ONLY in the
    redirected scratch object directory. A process killed between that fetch and the
    (best-effort, non-signal-safe) cleanup left `repo_path` holding a ref to an object its OWN
    object store does not have -- reproduced live (round 2 review): `git for-each-ref` fails with
    "missing object" and `git fsck`/`git gc` both fail outright on the survivor, strictly WORSE
    than the pre-finding-#6 behaviour (a harmless ref to a real, already-local object).

    FIXED by never requesting a destination ref at all: `git fetch <remote> <sha>` (a BARE
    revision, no `:<ref>` suffix) fetches the object into whichever object store
    GIT_OBJECT_DIRECTORY names (the scratch directory, exactly as before) WITHOUT creating or
    touching any ref anywhere -- confirmed live (round 2): `for-each-ref`/`count-objects` on
    `repo_path` are byte-identical before and after, for both an already-local tip (the common
    case) and a genuinely new, never-locally-present remote-ahead object (the one scenario that
    forces a real transfer, same fixture class `rv_no_mutation_remote_ahead` already exercises).
    `git rev-list --count`/`git merge-base --is-ancestor` both already accept a bare SHA1 string
    directly wherever this file calls them (no ref needed, they always have) -- `_is_ancestor`
    below is UNCHANGED by this fix; it already took `tip`/`local_tip` as plain SHA strings, never
    ref names. With NO ref ever written, there is nothing left for an interrupted run to leave
    dangling in `repo_path` -- not merely cleaned up better, structurally impossible by
    construction. (The caller's SIGTERM handler, main(), closes the SAME finding's secondary ask:
    a clean terminate signal now unwinds through every open `finally:`/`with:` -- including the
    scratch-objdir cleanup and `_pointer_fetchable`'s own TemporaryDirectory probes -- instead of
    abandoning them mid-run.)

    T158 remediation round 3, IMPORTANT finding I-N2 (a pre-existing bug present since round 1,
    missed by both prior reviews -- a DIFFERENT read-only violation than the one finding #6/I1
    above already closed): this fetch previously relied on git's DEFAULT submodule-recursion
    behaviour (`fetch.recurseSubmodules` unset, defaulting to "on-demand"). When the remote side
    has a newer commit whose TREE moves a submodule gitlink to a commit not yet present in that
    submodule's own local checkout, git AUTOMATICALLY starts a FULL, UN-REDIRECTED `git fetch`
    INSIDE the submodule to satisfy the recursion -- and git CLEARS
    `GIT_OBJECT_DIRECTORY`/`GIT_ALTERNATE_OBJECT_DIRECTORIES` for that child process (the exact
    env vars this function's own RV-009 object-store redirect, immediately above, relies on), so
    the submodule-level fetch writes straight into the submodule's REAL `.git` directory instead
    of the redirected scratch store. Reproduced live (3 separate experiments, round 3 review):
    `refs/remotes/origin/HEAD` and `refs/remotes/origin/main` moved inside the submodule's real
    git-dir, a reflog entry was written, and new loose objects appeared under
    `.git/modules/<sub>` -- confirmed to ALSO happen with the pre-round-2 (round 1) tool, i.e.
    this is NOT something round 2's own finding-#6 fix introduced. Probing the submodule alone
    (never through a PARENT-level recursive fetch) does not trigger it -- only the parent-level
    `git fetch` reaching a commit that moves a submodule pointer does. FIXED by `--recurse-
    submodules=no` on this fetch invocation (git's command-line flag always overrides any
    repo-local `fetch.recurseSubmodules`/`submodule.recurse` config, so this holds regardless of
    what a given repository has configured): confirmed live, this makes the submodule's real
    `.git` directory (refs, reflog, and object count) byte-identical before and after, even for
    the exact scenario that previously triggered the write (a remote-ahead parent commit that
    also moves the submodule's own gitlink)."""
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
    fetched, _fout, _ferr = _run(
        ["git", "-c", "gc.auto=0", "fetch", "--no-tags", "-q", "--no-write-fetch-head",
         "--recurse-submodules=no", git_target, tip], repo_path, timeout_s, extra_env=extra_env)
    unpushed = "UNKNOWN"
    if fetched == 0:
        rc, out, _err = _run(["git", "rev-list", "--count", "%s..HEAD" % tip], repo_path, timeout_s,
                              extra_env=extra_env)
        if rc == 0 and out.strip().isdigit():
            unpushed = int(out.strip())

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
    reproducible half of finding #9.

    T158 remediation round 2, finding B1 (BLOCKING): round 1's `reachable_map` fix only covered a
    remote whose OWN `ls-remote` (the SAME reachability signal `verify_remote` already computed)
    had itself failed -- it never covered a remote that WAS reachable for `ls-remote`/the live-tip
    fetch but whose SEPARATE probe-fetch call, immediately below, then failed for an UNRELATED
    reason: a timeout (`rc=None`, confirmed live against a wrapper `GIT_SSH_COMMAND` that sleeps
    only on the probe's own upload-pack call, not the earlier ls-remote/fetch calls for the SAME
    remote), or a non-definitive git failure (auth/connection/config-driven -- confirmed live
    against a submodule remote whose repo-local `core.sshCommand` the probe's fresh, config-naive
    scratch repo does not inherit, the documented limitation two paragraphs up). Both previously
    fell through to the SAME bare `rc != 0` branch as a genuine "not our ref" rejection and were
    indistinguishably counted toward UNFETCHABLE -> NOT_CLEAN -- asserting as fact that a commit is
    on no remote when the probe for THAT remote never actually finished checking. Fixed by
    classifying the probe's own outcome three ways, never just pass/fail: `rc == 0` -> FETCHABLE
    (unchanged); `rc != 0` AND `_is_definitive_absence(stderr)` -> this ONE remote is genuinely,
    definitively checked-and-absent (falls through to the next remote, contributing toward
    UNFETCHABLE exactly as before); anything else (`rc is None`, i.e. a timeout, OR a non-definitive
    stderr) -> this remote's probe proved NOTHING, folded into the SAME downgrade-to-UNVERIFIED path
    as an outright-unreachable remote (never silently treated as a confirmed rejection)."""
    any_inconclusive = False
    any_probed = False
    for remote in remote_names:
        if not reachable_map.get(remote, False):
            any_inconclusive = True
            continue
        url = _remote_url(repo_path, remote, timeout_s)
        if not url:
            any_inconclusive = True
            continue
        any_probed = True
        with tempfile.TemporaryDirectory(prefix="fc_repo_verify_pointer_probe_") as probe_dir:
            rc0, _o, _e = _run(["git", "init", "-q", "--bare", probe_dir], repo_path, timeout_s)
            if rc0 != 0:
                any_inconclusive = True
                continue
            rc, _out, err = _run(
                ["git", "-c", "gc.auto=0", "--git-dir=" + probe_dir, "fetch", "--no-tags", "-q",
                 "--recurse-submodules=no", "--no-write-fetch-head", "--depth=1", "--filter=tree:0", url, "%s:refs/probe" % sha],
                repo_path, timeout_s)
            if rc == 0:
                return "FETCHABLE"
            if rc is None or not _is_definitive_absence(err):
                # B1 fix: a timeout (rc=None) or any non-definitive failure (auth/connection/
                # config-driven) proves NOTHING about this remote -- it is NOT a confirmed
                # rejection, so it must downgrade the final verdict to UNVERIFIED exactly like an
                # outright-unreachable remote, never silently count toward UNFETCHABLE.
                any_inconclusive = True
            # else: rc != 0 AND the stderr matches a definitive-absence pattern -- this remote was
            # genuinely reached and genuinely checked; fall through to the next remote without
            # marking any_inconclusive (this is the real "probed, SHA absent here" case).
    if any_inconclusive or not any_probed:
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
    # T158 remediation round 2, finding I1: verify_remote() no longer creates ANY ref (it fetches
    # a bare SHA, never a `sha:ref` destination -- see its own docstring), so this namespace is no
    # longer written to by this process at all; the sweep below is retained purely as a defence-in-
    # depth check of THIS process's own pid-scoped namespace. (T158 round 4 MINOR: it does NOT --
    # and structurally cannot -- clean debris from an EARLIER run, since that run's namespace
    # carried a different pid; refs this process did not create are deliberately never touched.)
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
            rr, reason = verify_remote(repo_path, remote, head, branch, timeout_s,
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
                    repo_path, push_url, head, branch, timeout_s, push_log.get(remote),
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


def _unmapped_result(relpath, gitlink):
    """T158 remediation round 5, finding I5-2: a gitlink present in the parent's HEAD tree with NO
    `.gitmodules` entry mapping its path. Whatever is on disk there, a fresh clone CANNOT check it
    out (git has no URL to fetch it from), so it is never a satisfied dependency (11.4.233(G)).
    Reported NOT_CLEAN with the reason code SUBMODULE_UNMAPPED (round-5 addition to the closed
    reason-code set). Its own on-disk contents, if any, are deliberately NOT walked: without a
    `.gitmodules` mapping there is no declared remote to verify its pointer against, and the repo
    is already NOT_CLEAN -- the operator's fix (add a proper `.gitmodules` entry) re-enables the
    full walk on the next run."""
    return {
        "path": relpath, "head": gitlink or "UNKNOWN", "branch": None, "worktree_clean": False,
        "dirty_entries": [], "untracked": [], "unpushed": {}, "remotes": [],
        "submodule_pointer_matches_checkout": False, "status": "NOT_CLEAN",
        "reasons": ["SUBMODULE_UNMAPPED"],
    }


def _norm_tree_path(p):
    p = p.strip().replace(os.sep, "/")
    while p.startswith("./"):
        p = p[2:]
    return p.rstrip("/")


def tree_gitlinks(repo_path, head, timeout_s=10):
    """I5-2: {relpath: sha} for every mode-160000 (gitlink) entry in `head`'s full tree.
    `git ls-tree -r` never descends INTO a gitlink (it is a commit, not a tree), so nested
    submodules' own gitlinks are found by the recursive walk, not here. A failing ls-tree on a HEAD
    that `rev-parse` already resolved is a genuinely unreadable repo -> RepoUnreadable (fail
    closed, never an empty set read as "no gitlinks")."""
    rc, out, err = _run(["git", "ls-tree", "-r", "-z", "--full-tree", head], repo_path, timeout_s)
    if rc != 0:
        raise RepoUnreadable(repo_path, "git ls-tree -r %s failed: %s" % (head, err.strip() or ("exit %s" % rc)))
    links = {}
    for record in out.split("\x00"):
        if not record:
            continue
        meta, sep, path = record.partition("\t")
        parts = meta.split()
        if sep and len(parts) == 3 and parts[0] == "160000" and parts[1] == "commit":
            links[_norm_tree_path(path)] = parts[2]
    return links


def _walk(repo_path, relpath, out_list, timeout_s, is_submodule=False, parent_gitlink=None,
          required_remotes=(), scratch_objdir=None):
    result = verify_single_repo(repo_path, relpath, timeout_s, is_submodule, parent_gitlink,
                                 required_remotes, scratch_objdir)
    out_list.append(result)
    parent_head = result["head"]
    # T158 round 6, finding I6-1: compare EXACTLY as .gitmodules declares it, never normalized --
    # real git does NOT accept a trailing-slash or "./"-prefixed submodule.<name>.path value as
    # equivalent to its bare form (`git submodule status` on a "subA/"-declared path fails with
    # "no submodule mapping found in .gitmodules for path 'subA'", and a fresh
    # `clone --recurse-submodules` leaves it an EMPTY directory) -- normalizing the declared side
    # before this comparison let such a path silently "match" the tree's gitlink and read CLEAN,
    # exactly the false-CLEAN class this check exists to catch (SUBMODULE_UNMAPPED, §11.4.233(G)).
    declared = set(list_gitmodules(repo_path, timeout_s))
    for link_rel, link_sha in sorted(tree_gitlinks(repo_path, parent_head, timeout_s).items()):
        if link_rel not in declared:  # I5-2: in the tree, unmapped by .gitmodules
            out_list.append(_unmapped_result(_join_rel(relpath, link_rel), link_sha))
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
    #12.1 has no more specific closed reason code for a declared-but-absent upstream). An absent
    `--remotes-config` flag entirely yields [] at the call site below (main() never calls this
    function at all in that case) -- that is the ONLY "no requirement" case this tool recognises.

    T158 remediation round 2, finding I2 (IMPORTANT -- round 1's own fix was only partial): EVERY
    one of truncated/unparsable JSON, a non-object top-level value, an unrecognised top-level key
    (most dangerously a TYPO'd `required_remotes`, e.g. the singular `required_remote`), or a
    `required_remotes` value that is not a JSON list of strings now raises `RemotesConfigError`
    naming the SPECIFIC problem -- caught by main() and turned into exit 2, never silently folded
    into "no requirement" (round 1's `return []` for every one of these shapes was indistinguishable,
    from the operator's own config file, from "I deliberately require nothing"; an operator who
    supplied this file expecting its declared requirement to be enforced must never have it
    silently discarded, 11.4.6). Only an EMPTY document (`{}`, no `required_remotes` key present
    at all) is a deliberate, valid "no requirement" declaration -- distinct from a key that is
    merely misspelled, which is an unrecognised top-level key and therefore an error."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except OSError as exc:
        raise RemotesConfigError("cannot read --remotes-config %r: %s" % (path, exc))
    except ValueError as exc:
        # json.JSONDecodeError is a ValueError subclass -- covers truncated/malformed JSON.
        raise RemotesConfigError("--remotes-config %r is not valid JSON: %s" % (path, exc))
    if not isinstance(data, dict):
        raise RemotesConfigError(
            "--remotes-config %r: top-level JSON value must be an object, got %s"
            % (path, type(data).__name__))
    unknown_keys = sorted(set(data.keys()) - {"required_remotes"})
    if unknown_keys:
        raise RemotesConfigError(
            "--remotes-config %r: unrecognised key(s) %s (did you mean 'required_remotes'?)"
            % (path, ", ".join(repr(k) for k in unknown_keys)))
    if "required_remotes" not in data:
        return []  # a deliberate, valid empty document -- no requirement declared
    names = data["required_remotes"]
    if not isinstance(names, list):
        raise RemotesConfigError(
            "--remotes-config %r: 'required_remotes' must be a JSON list, got %s"
            % (path, type(names).__name__))
    if not all(isinstance(n, str) for n in names):
        raise RemotesConfigError(
            "--remotes-config %r: every entry in 'required_remotes' must be a string" % (path,))
    return sorted(set(n for n in names if n.strip()))


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


def _sigterm_handler(_signum, _frame):
    """T158 remediation round 2, finding I1: converts a clean `kill <pid>`/SIGTERM into a raised
    Python exception (never installed for SIGKILL -- a process cannot intercept that one at all,
    and is not this finding's concern) so every open `finally:`/`with:` block on the call stack at
    the moment of the signal still runs as it unwinds -- the scratch object-store tempdir cleanup
    in verify_recursive(), self_check()'s and _pointer_fetchable()'s own
    `tempfile.TemporaryDirectory` context managers, and the RV-009 stale-ref sweep in
    verify_single_repo()'s own `finally:` -- instead of the process simply stopping mid-run with
    none of that cleanup ever executing."""
    raise Terminated("repo_verify: terminated by SIGTERM")


def main(argv):
    # Installed for the whole lifetime of this process (main() runs exactly once per invocation,
    # matching every other git subprocess this tool launches, so there is nothing to restore).
    signal.signal(signal.SIGTERM, _sigterm_handler)
    p = argparse.ArgumentParser(prog="repo_verify.py")
    p.add_argument("--recursive", action="store_true")
    p.add_argument("--root", required=True)
    p.add_argument("--remotes-config")
    p.add_argument("--out", required=True)
    p.add_argument("--md")
    p.add_argument("--determinism-check", action="store_true")
    p.add_argument("--timeout-per-remote", type=int, default=DEFAULT_TIMEOUT_S)
    p.add_argument("--neutralize-repo-filters", action="store_true")
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
    # existence-checked above, then silently discarded) -- see read_remotes_config(). T158
    # remediation round 2, finding I2: a malformed/wrongly-shaped document (round 1 only ever
    # existence-checked above, never shape-validated) now fails closed here too, naming the
    # specific problem, rather than silently falling back to "no requirement" -- deliberately
    # OUTSIDE the broad `except Exception` below (an internal error is never 2, and a config
    # error the operator must fix is never 4).
    try:
        a.required_remotes = read_remotes_config(a.remotes_config) if a.remotes_config else []
    except RemotesConfigError as exc:
        print("repo_verify: %s" % exc, file=sys.stderr)
        return 2

    if a.neutralize_repo_filters:
        try:
            install_filter_overrides(discover_untrusted_filter_drivers(a.root, 15))
        except (FilterDiscoveryError, OSError) as exc:
            print("repo_verify: BLIND -- filter-driver discovery could not complete (%s); refusing to "
                  "run git reads that could execute one" % exc, file=sys.stderr)
            return 4

    try:
        if a.determinism_check:
            return _run_determinism_check(a)
        return _run_once(a)
    except Exception as exc:  # C-001: an internal error is never a finding (1) -- BLIND (4)
        print("repo_verify: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
