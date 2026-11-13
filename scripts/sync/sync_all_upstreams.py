#!/usr/bin/env python3
"""sync_all_upstreams.py -- engine of scripts/sync/sync_all_upstreams.sh (run with python3 -I).

Fetches every remote of a project and of every initialised submodule at every depth, reports
ahead / behind / diverged / unreachable state and the pin state of every submodule, and (only with
--apply) integrates by FAST-FORWARD. Full documentation: docs/manuals/sync_upstreams_manual.md.

Safety (Constitution §11.4.113, §9.2, §11.4.84, §11.4.10, §12):
  * Every git call goes through Runner.run(), which refuses any subcommand or argument that is not on
    the allow-list (check_git_args). push, commit, reset, rebase, a forced checkout, -s/--strategy,
    '::' transport helpers and every '+' refspec except the one engine-owned remote-tracking refspec
    (+refs/heads/*:refs/remotes/<remote>/*) can never be built.
  * Fetch is engine-owned: an explicit refspec into refs/remotes/<remote>/* only, --refmap= (the
    repository's configured fetch refspec, e.g. a mirror '+refs/heads/*:refs/heads/*', is ignored),
    --no-prune --no-prune-tags --no-tags --no-auto-gc. A fetch therefore never creates, moves or
    deletes a local branch or tag (tags only with --tags, and then only new ones, never forced).
  * Every git call runs with SAFE_CONFIG (core.hooksPath=/dev/null, core.fsmonitor=false,
    submodule.recurse=false, gc.auto=0, maintenance.auto=false, ...), so no hook, fsmonitor or
    auto-maintenance runs, whatever the repository's own config says.
  * A repository with a dirty tree, an in-progress operation or an index.lock is never changed; a
    fast-forward or checkout that would overwrite an ignored local file (e.g. a credentials file) is
    refused for that repository (reason ignored-file-would-be-overwritten).
  * Nothing is ever deleted; the only writes are git fetch (refs/remotes/<remote>/*), git merge
    --ff-only, git checkout --detach (clean submodule), git add -- <gitlink> (staged, never
    committed) and the evidence files.
  * A read that timed out or was cut by the run deadline is UNRESOLVED, never "absent": that
    repository's result is "unresolved" and the run verdict INCONCLUSIVE (exit 5).
  * URLs are logged without userinfo, git stderr is redacted, git never prompts.
  * Fetched code is never executed by the engine or by git on its behalf (hooks, fsmonitor and
    auto-maintenance are off). Honest boundary: a clean/smudge filter or diff driver the USER
    configured still runs on checkout/merge when a tracked .gitattributes selects it.
"""
import argparse
import concurrent.futures
import datetime
import fcntl
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

SCHEMA = "helix.sync_upstreams/1"
EXIT_OK, EXIT_FAIL, EXIT_USAGE, EXIT_BEHIND, EXIT_ATTENTION = 0, 1, 2, 3, 4
EXIT_INCONCLUSIVE, EXIT_BLIND, EXIT_LOCKED = 5, 6, 7
DEFAULT_OWN_ORGS = ("vasic-digital", "HelixDevelopment")
SHA_RE = re.compile(r"^[0-9a-f]{40}([0-9a-f]{24})?$")
REMOTE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$")
BRANCH_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$")
# rc of Runner.run that mean "the call did not answer" (never "the thing is absent", §11.4.201(6)):
# 124 timeout, 126 run deadline passed, 127 git not runnable. 125 (refused) is a programming error.
UNANSWERED = (124, 125, 126, 127)

# -c pairs on EVERY git call: whatever the repository's own (or the user's) config says, no hook,
# fsmonitor, auto-gc/maintenance, submodule recursion, autostash, ext:: transport or prune runs.
SAFE_CONFIG = ("core.hooksPath=/dev/null", "core.fsmonitor=false", "submodule.recurse=false",
               "gc.auto=0", "maintenance.auto=false", "merge.autoStash=false", "protocol.ext.allow=never",
               "fetch.prune=false", "fetch.pruneTags=false", "fetch.recurseSubmodules=false")


def fetch_args(remote, tags):
    """The ONE fetch shape: an explicit refspec into refs/remotes/<remote>/* (configured refspecs ignored)."""
    a = ["fetch", "--no-prune", "--no-prune-tags", "--no-recurse-submodules", "--no-auto-gc", "--no-tags",
         "--refmap=", "--", remote, "+refs/heads/*:refs/remotes/%s/*" % remote]
    if tags:
        a.append("refs/tags/*:refs/tags/*")
    return a


def git_argv(git_bin, repo, args):
    """The full command line of one git call: SAFE_CONFIG before the subcommand, never a shell."""
    cmd = [git_bin, "-C", repo]
    for kv in SAFE_CONFIG:
        cmd += ["-c", kv]
    return cmd + ["--no-optional-locks"] + list(args)

# ───────────────────────────── git allow-list ─────────────────────────────
READ_SUBCOMMANDS = {"rev-parse", "rev-list", "status", "ls-files", "ls-tree", "cat-file",
                    "for-each-ref", "merge-base", "remote", "config", "symbolic-ref"}
WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add"}
FORBIDDEN_TOKENS = {"--force", "--force-with-lease", "--hard", "--soft", "--mixed", "--amend", "--delete",
                    "--strategy", "--strategy-option", "--mirror", "--recurse-submodules", "--git-dir",
                    "--work-tree", "--exec", "--upload-pack", "--receive-pack", "--set-upstream", "--unshallow",
                    "--refmap", "--orphan", "--ours", "--theirs", "--no-verify", "--allow-unrelated-histories",
                    "--interactive", "--patch", "--all", "--rebase", "--no-ff", "--squash", "--edit",
                    "push", "reset", "rebase", "commit", "clean", "gc", "prune", "update-ref", "filter-branch"}
# Short options are not listed: every WRITE subcommand below has one exact shape, so a short option can
# never reach a write; the read subcommands' short options (ls-files -s, cat-file -e, ...) are harmless.
FORBIDDEN_PREFIXES = ("--force", "--upload-pack=", "--exec=", "--receive-pack=", "--git-dir=",
                      "--work-tree=", "--strategy=", "--strategy-option=", "--refmap=", "--output",
                      "--config-env", "--super-prefix", "--namespace")


class GitRefused(Exception):
    pass


def check_git_args(args):
    """Raise GitRefused unless ``args`` (the words after ``git``) is an allowed shape."""
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
        return True
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
        if len(rest) != 2 or rest[0] != "--ff-only" or not SHA_RE.match(rest[1]):
            raise GitRefused("merge must be: merge --ff-only <sha>")
    elif sub == "checkout":
        if len(rest) != 3 or rest[0] != "--quiet" or rest[1] != "--detach" or not SHA_RE.match(rest[2]):
            raise GitRefused("checkout must be: checkout --quiet --detach <sha>")
    elif sub == "add":
        if len(rest) != 2 or rest[0] != "--" or not safe_relpath(rest[1]):
            raise GitRefused("add must be: add -- <relative gitlink path>")
    elif sub == "symbolic-ref":
        if rest not in (["-q", "HEAD"], ["--short", "-q", "HEAD"]):
            raise GitRefused("symbolic-ref is read-only here: symbolic-ref [--short] -q HEAD")
    elif sub == "config":
        if not rest or rest[0] not in ("--get", "--get-regexp"):
            raise GitRefused("config is read-only here: config --get|--get-regexp ...")
    elif sub == "remote":
        if rest:
            raise GitRefused("remote is read-only here: bare 'git remote'")
    return True


def safe_remote(name):
    """A remote name usable inside refs/remotes/<name>/*: no option, no glob, no '.'/'..' part."""
    if not name or not REMOTE_RE.match(name) or name.endswith((".lock", "/", ".")):
        return False
    return all(x not in ("", ".", "..") for x in name.split("/"))


def safe_relpath(p):
    if not p or p.startswith("-") or p.startswith("/") or "\\" in p:
        return False
    parts = p.split("/")
    return all(x not in ("", ".", "..") for x in parts)


# ───────────────────────────── redaction ─────────────────────────────
_USERINFO = re.compile(r"([A-Za-z][A-Za-z0-9+.-]*://)[^/@\s]*@")
_TOKENS = re.compile(r"(gh[pousr]_|github_pat_|glpat-|xox[abprs]-|AKIA)[A-Za-z0-9_\-]{4,}")
_CTRL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f\x80-\x9f]")


def redact(text):
    """Remove URL userinfo, known token shapes and control characters."""
    if text is None:
        return ""
    t = _USERINFO.sub(r"\1", str(text))
    t = _TOKENS.sub("[REDACTED]", t)
    return _CTRL.sub("?", t)


def url_org_segments(url):
    """Path segments of a remote URL except the last (the repository itself)."""
    u = url or ""
    m = re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://[^/]*(/.*)$", u)
    if m:
        path = m.group(1)
    elif re.match(r"^[^/:]+@?[^/:]*:", u) and not u.startswith("/"):
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


# ───────────────────────────── git runner ─────────────────────────────
_SCRUB = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR",
          "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_EXEC_PATH", "GIT_SSH", "GIT_ASKPASS",
          "SSH_ASKPASS", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_PROXY_COMMAND",
          "GIT_TRACE", "GIT_TRACE_PACKET", "GIT_TRACE_CURL", "GIT_REDACT_COOKIES", "GIT_PREFIX",
          "GIT_QUARANTINE_PATH", "GIT_REPLACE_REF_BASE", "GIT_SHALLOW_FILE", "GIT_INTERNAL_SUPER_PREFIX")


def git_env(base=None):
    env = dict(base if base is not None else os.environ)
    for k in list(env):
        if k in _SCRUB or k.startswith("GIT_CONFIG_KEY_") or k.startswith("GIT_CONFIG_VALUE_"):
            del env[k]
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GCM_INTERACTIVE"] = "never"
    env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
    env["LC_ALL"] = "C"
    env["LANG"] = "C"
    return env


class Runner:
    def __init__(self, git_bin, timeout, deadline):
        self.git = git_bin
        self.timeout = timeout
        self.deadline = deadline
        self.env = git_env()
        self.env_repo_ssh = dict(self.env)  # for a repository with its own core.sshCommand (F9)
        self.env_repo_ssh.pop("GIT_SSH_COMMAND", None)
        self.calls = 0
        self.lock = threading.Lock()
        self.unresolved = {}  # realpath(repo) -> set of "<subcommand>:<why>" (a call that did not answer)

    def remaining(self):
        return self.deadline - time.monotonic()

    def _unanswered(self, repo, args, why):
        with self.lock:
            self.unresolved.setdefault(os.path.realpath(repo), set()).add("%s:%s" % (args[0] if args else "?", why))

    def run(self, repo, args, network=False, repo_ssh=False):
        """Return (rc, stdout, stderr). rc 124 = timeout, 125 = refused, 126 = deadline passed,
        127 = git not runnable. Every non-network 124 and every 125/126/127 is recorded as UNRESOLVED for
        ``repo`` (a network fetch timeout is the remote's state: unreachable, recorded by the caller)."""
        try:
            check_git_args(args)
        except GitRefused as e:
            self._unanswered(repo, args, "refused")
            return 125, "", "refused: %s" % e
        left = self.remaining()
        if left <= 0:
            self._unanswered(repo, args, "deadline")
            return 126, "", "run deadline passed"
        limit = min(self.timeout if network else max(self.timeout, 60), left)
        with self.lock:
            self.calls += 1
        cmd = git_argv(self.git, repo, args)
        try:
            p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 env=self.env_repo_ssh if repo_ssh else self.env, start_new_session=True)
        except OSError as e:
            self._unanswered(repo, args, "not-runnable")
            return 127, "", "cannot run git: %s" % e
        try:
            out, err = p.communicate(timeout=limit)
        except subprocess.TimeoutExpired:
            kill_own_group(p)
            try:  # a grandchild that escaped the group may still hold a pipe: never wait for it (F8)
                out, err = p.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                for s in (p.stdout, p.stderr):
                    try:
                        s.close()
                    except OSError:
                        pass
                try:
                    p.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
                out = b""
            if not network:
                self._unanswered(repo, args, "timeout")
            return 124, out.decode("utf-8", "replace"), "timeout after %ds" % int(limit)
        return p.returncode, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")

    def unresolved_for(self, repo):
        with self.lock:
            return sorted(self.unresolved.get(os.path.realpath(repo), ()))


def kill_own_group(p):
    """Kill the process group of a child started with start_new_session (§11.4.263: pgid > 1)."""
    try:
        pgid = os.getpgid(p.pid)
    except OSError:
        return
    if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:
        try:
            os.killpg(pgid, signal.SIGKILL)
        except OSError:
            pass


# ───────────────────────────── helpers ─────────────────────────────
def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def g_out(r, repo, args):
    rc, out, _ = r.run(repo, args)
    return out.strip() if rc == 0 else None


def read_head(r, repo):
    """HEAD as a full object id, or None when it cannot be read as one (unborn, error, empty or odd output):
    an unread head is never compared, so it can never read as "unchanged" or "moved" (F3)."""
    h = g_out(r, repo, ["rev-parse", "HEAD"])
    return h if h and SHA_RE.match(h) else None


def is_ancestor(r, repo, a, b):
    rc, _, _ = r.run(repo, ["merge-base", "--is-ancestor", a, b])
    return rc == 0


def count_range(r, repo, a, b):
    """(ahead_of_b, behind_b) for a vs b, or None."""
    out = g_out(r, repo, ["rev-list", "--left-right", "--count", "%s...%s" % (a, b)])
    if out is None:
        return None
    parts = out.split()
    if len(parts) != 2:
        return None
    return int(parts[0]), int(parts[1])


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


def in_progress(gitdir):
    names = ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG", "rebase-merge",
             "rebase-apply", "index.lock")
    return [n for n in names if os.path.exists(os.path.join(gitdir, n))]


def is_repo_root(r, path):
    if not os.path.isdir(path) or not os.path.exists(os.path.join(path, ".git")):
        return False
    top = g_out(r, path, ["rev-parse", "--show-toplevel"])
    return top is not None and os.path.realpath(top) == os.path.realpath(path)


def gitlinks(r, repo, treeish=None):
    """{path: sha} of the gitlinks recorded in the index (or a tree-ish)."""
    if treeish:
        rc, out, _ = r.run(repo, ["ls-tree", "-r", "-z", treeish])
        recs = [x for x in out.split("\0") if x] if rc == 0 else []
        res = {}
        for x in recs:
            meta, _, path = x.partition("\t")
            f = meta.split()
            if len(f) == 3 and f[0] == "160000":
                res[path] = f[2]
        return res
    rc, out, _ = r.run(repo, ["ls-files", "-s", "-z"])
    res = {}
    if rc != 0:
        return res
    for x in out.split("\0"):
        if not x:
            continue
        meta, _, path = x.partition("\t")
        f = meta.split()
        if len(f) == 3 and f[0] == "160000" and f[2] == "0":
            res[path] = f[1]
    return res


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
    rec["branch"] = g_out(r, p, ["symbolic-ref", "--short", "-q", "HEAD"])
    # one call for both paths (the per-repository call count is a guarded budget, tests/sync/test_perf.sh)
    paths = (g_out(r, p, ["rev-parse", "--absolute-git-dir", "--path-format=absolute", "--git-path", "FETCH_HEAD"])
             or "").split("\n")
    gitdir, fetch_head = (paths[0], paths[1]) if len(paths) == 2 and all(paths) else ("", "")
    rec["in_progress"] = in_progress(gitdir) if gitdir else ["unknown-git-dir"]
    st = r.run(p, ["status", "--porcelain=v1", "--ignore-submodules=all", "--untracked-files=normal"])
    rec["dirty"] = (st[0] != 0) or bool(st[1].strip())
    names = g_out(r, p, ["remote"])
    remotes = []
    for n in sorted((names or "").split()):
        if not safe_remote(n):
            remotes.append({"name": redact(n), "url": "", "fetch": "skipped", "state": "invalid-name"})
            continue
        url = g_out(r, p, ["config", "--get", "remote.%s.url" % n]) or ""
        remotes.append({"name": n, "url": redact(url), "fetch": "not-run"})
    rec["remotes"] = remotes
    rec["_branch_wanted"] = branch
    rec["_fetch_head"] = fetch_head
    # F9: a repository (or user) core.sshCommand is honoured; otherwise the engine's BatchMode ssh is used.
    # git never prompts either way: no controlling terminal (new session), stdin /dev/null, no askpass.
    rc, out, _ = r.run(p, ["config", "--get", "core.sshCommand"])
    rec["ssh"] = "core.sshCommand" if rc == 0 and out.strip() else "engine-default"


FETCH_FAILURE_CLASSES = (
    ("auth", ("authentication failed", "permission denied", "could not read username", "could not read password",
              "access denied", "invalid credentials", "http 401", "http 403", "error: 403")),
    ("not-found", ("repository not found", "does not appear to be a git repository", "not found", "http 404",
                   "no such file or directory")),
    ("network", ("could not resolve host", "connection refused", "connection timed out", "network is unreachable",
                 "no route to host", "could not read from remote", "unable to access", "failed to connect",
                 "connection reset", "connection closed")),
)


def classify_fetch_failure(rc, err):
    """A closed label for a failed fetch (F12); the redacted error line is kept beside it."""
    if rc == 124:
        return "timeout"
    if rc == 126:
        return "deadline"
    if rc == 125:
        return "refused-by-engine"
    if rc == 127:
        return "git-not-runnable"
    e = (err or "").lower()
    for label, needles in FETCH_FAILURE_CLASSES:
        if any(n in e for n in needles):
            return label
    return "other"


def fetched_branches(path):
    """Branch names the last fetch reported in FETCH_HEAD (``path``), or None when it cannot be read."""
    if not path or not os.path.isabs(path):
        return None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            data = f.read()
    except OSError:
        return None
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
        rc, _, err = r.run(repo.abspath, fetch_args(rem["name"], tags), network=True,
                           repo_ssh=repo.rec.get("ssh") == "core.sshCommand")
        rem["fetch_rc"] = rc
        rem["fetch"] = "ok" if rc == 0 else {124: "timeout", 126: "deadline"}.get(rc, "failed")
        if rc != 0:
            rem["fetch_failure"] = classify_fetch_failure(rc, err)
            lines = [l for l in redact(err).splitlines() if l.strip()]
            rem["fetch_error"] = lines[-1][:300] if lines else "git exit %d" % rc
            continue
        # --no-prune keeps a stale refs/remotes/<r>/<branch> after upstream deleted it: FETCH_HEAD says
        # which branches the remote really has now (never a delete of our own).
        got = fetched_branches(repo.rec.get("_fetch_head") or "")
        if got is None:
            r._unanswered(repo.abspath, ["fetch"], "fetch-head-unreadable")
        elif repo.rec.get("_branch_wanted", "main") not in got:
            rem["branch_gone_upstream"] = True


def evaluate_upstream(r, repo, branch):
    rec = repo.rec
    p = repo.abspath
    mains = {}
    for rem in rec["remotes"]:
        if rem.get("state") == "invalid-name":
            continue
        sha = g_out(r, p, ["rev-parse", "--verify", "-q", "refs/remotes/%s/%s^{commit}" % (rem["name"], branch)])
        if rem.get("branch_gone_upstream"):
            # the remote no longer has the branch; a remote-tracking ref we still hold (kept by --no-prune,
            # never deleted by us) is stale and is reported, a never-existing one is not a finding
            rem["stale_tracking_ref"] = bool(sha)
            sha = None
        rem["main_sha"] = sha
        if rem.get("fetch") in ("failed", "timeout"):
            rem["state"] = "unreachable"
        elif rem.get("fetch") == "deadline":
            rem["state"] = "not-fetched-deadline"
        elif sha is None:
            rem["state"] = "no-main"
        if sha:
            mains[rem["name"]] = sha
    newest = pick_newest(list(mains.values()), lambda a, b: is_ancestor(r, p, a, b))
    rec["upstream_state"] = "none" if not mains else ("linear" if newest else "upstreams-diverged")
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
        if rem.get("state") not in ("unreachable", "not-fetched-deadline"):
            rem["state"] = classify(*c)
    if head and newest:
        c = count_range(r, p, head, newest)
        rec["local_vs_target"] = classify(*c) if c else "unknown"
        rec["behind_target"] = c[1] if c else None
    else:
        rec["local_vs_target"] = "no-target"
        rec["behind_target"] = None


def evaluate_pin(r, repo, gitlink, own_orgs):
    """Pin state of a submodule repo against its recorded gitlink (from the parent)."""
    rec = repo.rec
    pin = {"gitlink": gitlink}
    url = ""
    for rem in rec.get("remotes", []):
        if rem.get("name") == "origin":
            url = rem.get("url", "")
    if not url and rec.get("remotes"):
        url = rec["remotes"][0].get("url", "")
    rec["own_org"] = is_own_org(url, own_orgs) if url else False
    p = repo.abspath
    rc, _, _ = r.run(p, ["cat-file", "-e", "%s^{commit}" % gitlink])
    if rc != 0:
        pin["state"] = "unfetchable"
    else:
        rc, out, _ = r.run(p, ["for-each-ref", "--contains", gitlink, "--format=%(refname)", "refs/remotes"])
        refs = [x for x in out.split() if x] if rc == 0 else []
        branch = rec.get("_branch_wanted", "main")
        # exact match (F13): refs/remotes/<remote>/feature/main is NOT <remote>'s main
        mains = {"refs/remotes/%s/%s" % (m.get("name"), branch) for m in rec.get("remotes", [])
                 if m.get("state") != "invalid-name" and not m.get("branch_gone_upstream")}
        on_main = [x for x in refs if x in mains]
        target = rec.get("target")
        if not refs:
            pin["state"] = "not-on-any-remote"
        elif not on_main:
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
        if strict_pins and st in ("absent", "uninitialised"):
            reasons.append("pin-" + st)
        return reasons
    if rec.get("dirty"):
        reasons.append("dirty-tree")
    reasons += ["in-progress:" + x for x in rec.get("in_progress", [])]
    if rec.get("head_unreadable"):
        reasons.append("head-unreadable")
    for rem in rec.get("remotes", []):
        if rem.get("state") == "unreachable":
            reasons.append("unreachable:" + rem["name"])
        elif rem.get("state") == "invalid-name":
            reasons.append("invalid-remote-name")
        if rem.get("stale_tracking_ref"):
            reasons.append("upstream-branch-gone:" + rem["name"])
    if rec.get("upstream_state") == "upstreams-diverged":
        reasons.append("upstreams-diverged")
    if rec["kind"] == "root" and rec.get("branch") != branch:
        reasons.append("root-not-on-" + branch)
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
        if real in seen:
            repo.rec["initialised"] = False
            repo.rec["pin"] = {"state": "cycle"}
            return
        seen.add(real)
        if repo.depth >= max_depth:
            repo.rec["depth_limited"] = True
            return
        links = gitlinks(r, repo.abspath)
        for path in sorted(links):
            if not safe_relpath(path):
                continue
            child_abs = os.path.join(repo.abspath, path)
            rel = path if repo.rel == "." else repo.rel + "/" + path
            child = Repo(child_abs, rel, repo.depth + 1, repo)
            child.rec["recorded_gitlink"] = links[path]
            child.rec["path_in_parent"] = path
            if not os.path.lexists(child_abs):
                child.rec["initialised"] = False
                child.rec["pin"] = {"gitlink": links[path], "state": "absent"}
                out.append(child)
            elif not is_repo_root(r, child_abs):
                child.rec["initialised"] = False
                child.rec["pin"] = {"gitlink": links[path], "state": "uninitialised"}
                out.append(child)
            else:
                child.rec["initialised"] = True
                walk(child)

    root_repo = Repo(root, ".", 0, None)
    root_repo.rec["initialised"] = True
    walk(root_repo)
    return out


# ───────────────────────────── integration ─────────────────────────────
def integrate(r, repos, branch, advance_pins, advance_third_party, strict_pins, consent):
    """Pre-order: parents move first, their clean children follow the new recorded gitlink."""
    blocked_paths = set()
    for repo in repos:
        rec = repo.rec
        rec.setdefault("actions", [])
        if not rec.get("initialised"):
            continue
        if repo.parent is not None and repo.parent.rel in blocked_paths:
            rec["actions"].append({"op": "none", "why": "parent-not-integrated"})
            blocked_paths.add(repo.rel)
            continue
        reasons = reasons_for(rec, strict_pins, branch)
        # root-not-on-<branch> blocks the whole tree (F7): no pin is staged into a topic branch's index
        local_block = [x for x in reasons if x.startswith(("dirty-tree", "in-progress", "upstreams-diverged",
                                                             "local-", "unreachable", "invalid-remote",
                                                             "root-not-on-", "head-unreadable"))]
        if r.unresolved_for(repo.abspath):
            local_block.append("unresolved")
        if local_block:
            rec["actions"].append({"op": "none", "why": ",".join(local_block)})
            blocked_paths.add(repo.rel)
            continue
        p = repo.abspath
        if rec.get("branch") == branch:
            if rec.get("local_vs_target") == "behind" and consent.get("integrate"):
                if not clobber_guard(r, repo, rec["target"]):
                    blocked_paths.add(repo.rel)
                    continue
                rc, _, err = r.run(p, ["merge", "--ff-only", rec["target"]])
                rec["actions"].append({"op": "fast-forward", "to": rec["target"], "rc": rc,
                                       "error": redact(err).strip()[-300:] if rc else ""})
                if rc != 0:
                    if rc not in UNANSWERED:  # a deadline-skipped write is unresolved, not a failure
                        rec["failed"] = True
                    blocked_paths.add(repo.rel)
                    continue
                if repo.parent is not None:  # F11: the parent's work tree now shows a modified gitlink
                    repo.parent.rec.setdefault("gitlink_modified", []).append(rec["path_in_parent"])
            follow_children(r, repo, repos, consent)
        elif repo.parent is not None:
            pin = rec.get("pin") or {}
            want = (advance_pins and consent.get("pins") and not rec.get("followed") and pin.get("state") == "behind-main"
                    and pin.get("checkout") == "at-pin" and rec.get("head_after", rec.get("head_before")) == pin.get("gitlink")
                    and (rec.get("own_org") or advance_third_party))
            if want and not clobber_guard(r, repo, rec["target"]):
                blocked_paths.add(repo.rel)
                continue
            if want:  # clean nested children follow their new recorded gitlink (follow_children below)
                rc, _, err = r.run(p, ["checkout", "--quiet", "--detach", rec["target"]])
                act = {"op": "advance-pin", "to": rec["target"], "rc": rc}
                if rc == 0:
                    rc2, _, err2 = r.run(repo.parent.abspath, ["add", "--", rec["path_in_parent"]])
                    act["staged_rc"] = rc2
                    if rc2 != 0:
                        act["error"] = redact(err2).strip()[-300:]
                        rec["failed"] = rc2 not in UNANSWERED or rec.get("failed", False)
                else:
                    act["error"] = redact(err).strip()[-300:]
                    rec["failed"] = rc not in UNANSWERED or rec.get("failed", False)
                rec["actions"].append(act)
            follow_children(r, repo, repos, consent)
        rec["head_after"] = read_head(r, p)
        if rec["head_after"] is None:
            rec["head_unreadable"] = True


def ignored_clobbers(r, path, target):
    """Ignored, untracked paths in ``path`` that a move to ``target`` would overwrite or remove (git treats
    ignored files as expendable). [] = none, None = could not tell (the caller blocks). Files are listed one by
    one (no --directory): a collapsed ``build/`` entry would falsely block a target that only adds
    ``build/x``, while each ignored file is checked against the target's files and directories."""
    rc, out, _ = r.run(path, ["ls-files", "-z", "--others", "--ignored", "--exclude-standard"])
    if rc != 0:
        return None
    ignored = sorted({x.rstrip("/") for x in out.split("\0") if x.strip("/")})
    if not ignored:
        return []
    rc, out, _ = r.run(path, ["ls-tree", "-r", "-z", "--name-only", "--full-tree", target])
    if rc != 0:
        return None
    files = {x for x in out.split("\0") if x}
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
    """True when the move to ``target`` may go ahead; otherwise records why (F4) and returns False."""
    hits = ignored_clobbers(r, repo.abspath, target)
    if hits == []:
        return True
    rec = repo.rec
    rec["ignored_clobber"] = [redact(x) for x in (hits or [])[:20]]
    rec.setdefault("actions", []).append({"op": "none", "why": "ignored-file-would-be-overwritten"
                                          if hits else "unresolved:ignored-file-check",
                                          "paths": rec["ignored_clobber"]})
    if hits is None:
        rec.pop("ignored_clobber", None)
        r._unanswered(repo.abspath, ["ls-files"], "ignored-file-check-failed")
    return False


def follow_children(r, repo, repos, consent):
    """After ``repo`` moved, check its clean, at-old-pin children out at the new recorded gitlink."""
    new_links = gitlinks(r, repo.abspath)
    for c in repos:
        if c.parent is not repo or not c.rec.get("initialised"):
            continue
        path = c.rec["path_in_parent"]
        old = c.rec.get("recorded_gitlink")
        new = new_links.get(path)
        if not new or new == old:
            continue
        c.rec["recorded_gitlink_after"] = new
        if c.rec.get("branch"):
            c.rec.setdefault("actions", []).append({"op": "none", "why": "follow-skipped:submodule-on-branch"})
            continue
        if c.rec.get("head_before") != old or c.rec.get("dirty") or c.rec.get("in_progress"):
            c.rec.setdefault("actions", []).append({"op": "none", "why": "follow-skipped:drifted-or-dirty"})
            continue
        # A parent's gitlinks move only by a fast-forward (consent "integrate") or a pin advance (consent
        # "pins"); following is part of that same consented move, so either consent covers it.
        if not (consent.get("integrate") or consent.get("pins")):
            continue
        rc, _, err = r.run(c.abspath, ["cat-file", "-e", "%s^{commit}" % new])
        if rc in UNANSWERED:
            c.rec.setdefault("actions", []).append({"op": "none", "why": "unresolved:new-pin-check"})
            continue
        if rc != 0:
            c.rec.setdefault("actions", []).append({"op": "none", "why": "follow-blocked:new-pin-unfetchable"})
            c.rec["failed"] = True
            continue
        if not clobber_guard(r, c, new):
            continue
        rc, _, err = r.run(c.abspath, ["checkout", "--quiet", "--detach", new])
        c.rec.setdefault("actions", []).append({"op": "follow-pin", "to": new, "rc": rc,
                                                "error": redact(err).strip()[-300:] if rc else ""})
        if rc != 0:
            c.rec["failed"] = rc not in UNANSWERED or c.rec.get("failed", False)
        else:
            c.rec["head_before_follow"] = c.rec.get("head_before")
            c.rec["followed"] = True


# ───────────────────────────── evidence ─────────────────────────────
VOLATILE = {"started", "ended", "duration_s", "run_id", "fetch_error", "out_dir", "root_abs", "git_calls",
            "jobs", "_branch_wanted", "_follow", "_fetch_head", "consent_source"}


def canonical(obj):
    if isinstance(obj, dict):
        return {k: canonical(v) for k, v in sorted(obj.items()) if k not in VOLATILE}
    if isinstance(obj, list):
        return [canonical(x) for x in obj]
    return obj


def canonical_sha256(report):
    data = json.dumps(canonical(report), sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(data.encode("ascii")).hexdigest()


def tsv_rows(report):
    cols = ["path", "kind", "depth", "initialised", "branch", "head_before", "head_after", "target",
            "upstream_state", "local_vs_target", "pin_state", "pin_behind_main", "own_org", "result", "reasons",
            "remotes"]
    rows = ["\t".join(cols)]
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


def write_atomic(path, data):
    tmp = path + ".tmp.%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def control_needle(r, root):
    """§11.4.273: the instrument must see a known count before any zero is believed."""
    n = g_out(r, root, ["rev-list", "--count", "HEAD"])
    lr = g_out(r, root, ["rev-list", "--left-right", "--count", "HEAD...HEAD"])
    ok = bool(n and n.isdigit() and int(n) >= 1 and lr is not None and lr.split() == ["0", "0"])
    return {"probe": "rev-list --count HEAD >= 1 and HEAD...HEAD == 0 0", "count": n, "self_range": lr, "ok": ok}


# ───────────────────────────── interactive ─────────────────────────────
class Tty:
    """The controlling terminal, unbuffered (a tty is not seekable, so no "r+" text stream)."""
    def __init__(self):
        self.fd = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)

    def _write(self, text):
        os.write(self.fd, text.encode("utf-8", "replace"))

    def say(self, msg):
        self._write(redact(msg) + "\n")

    def ask(self, question):
        self._write(redact(question) + " [y/N] ")
        line = b""
        while len(line) < 256:
            ch = os.read(self.fd, 1)
            if not ch or ch == b"\n":
                break
            line += ch
        return line.decode("utf-8", "replace").strip().lower() in ("y", "yes")


# ───────────────────────────── main ─────────────────────────────
def parse_args(argv):
    ap = argparse.ArgumentParser(prog="sync_all_upstreams.sh", add_help=True,
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
    ap.add_argument("--deadline", type=int, default=1800, help="seconds for the whole run")
    ap.add_argument("--max-depth", type=int, default=32)
    ap.add_argument("--out", help="evidence directory (must be outside the project work tree)")
    ap.add_argument("--run-id")
    ap.add_argument("--quiet", action="store_true")
    i = ap.add_mutually_exclusive_group()
    i.add_argument("--interactive", action="store_true", help="ask before fetching and before every change (/dev/tty)")
    i.add_argument("--non-interactive", action="store_true", help="flags are the consent (default)")
    return ap.parse_args(argv)


def main(argv):
    try:
        a = parse_args(argv)
    except SystemExit as e:
        return EXIT_OK if e.code == 0 else EXIT_USAGE
    mode = "check" if a.check else "dry-run" if a.dry_run else "apply" if a.apply else None
    if mode is None:
        print("sync-upstreams: ERROR: choose one mode: --check, --dry-run or --apply", file=sys.stderr)
        return EXIT_USAGE
    if not BRANCH_RE.match(a.branch):
        print("sync-upstreams: ERROR: invalid --branch", file=sys.stderr)
        return EXIT_USAGE
    for v, n in ((a.timeout, "--timeout"), (a.deadline, "--deadline"), (a.max_depth, "--max-depth")):
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
    r = Runner(git_bin, a.timeout, started_mono + a.deadline)
    start_dir = a.root or os.getcwd()
    top = g_out(r, start_dir, ["rev-parse", "--show-toplevel"])
    if not top:
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
    out_dir = os.path.realpath(a.out) if a.out else os.path.join(base, "helix_sync_upstreams",
                                                                  "%s-%s" % (os.path.basename(root), run_id))
    if out_dir == root or out_dir.startswith(root + os.sep):
        print("sync-upstreams: ERROR: --out must be outside the project work tree", file=sys.stderr)
        return EXIT_USAGE
    tty = None
    if a.interactive:
        try:
            tty = Tty()
        except OSError:
            print("sync-upstreams: ERROR: --interactive needs a terminal (/dev/tty); use --non-interactive", file=sys.stderr)
            return EXIT_USAGE
    common = g_out(r, root, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
    if not common:
        print("sync-upstreams: ERROR: cannot resolve the git common dir", file=sys.stderr)
        return EXIT_USAGE
    lock_path = os.path.join(common, "helix-sync-upstreams.lock")
    try:
        lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("sync-upstreams: ERROR: another sync run holds %s (exit 7, nothing done)" % redact(lock_path), file=sys.stderr)
        return EXIT_LOCKED
    try:
        return run(a, r, mode, root, run_id, out_dir, tty)
    finally:
        os.close(lock_fd)


def say(a, msg):
    if not a.quiet:
        print("[sync-upstreams] " + redact(msg), file=sys.stderr)


def run(a, r, mode, root, run_id, out_dir, tty):
    started = now_utc()
    t0 = time.monotonic()
    own_orgs = tuple(a.own_org) if a.own_org else DEFAULT_OWN_ORGS
    jobs = clamp_jobs(a.jobs, os.cpu_count())
    needle = control_needle(r, root)
    repos = discover(r, root, a.max_depth)
    live = [x for x in repos if x.rec.get("initialised")]
    for x in live:
        inspect_local(r, x, a.branch)
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
            rec["head_after"] = rec.get("head_before")
    # final classification
    any_fail = any_attention = any_behind = any_unresolved = False
    hints = []
    for x in repos:
        rec = x.rec
        rec["reasons"] = reasons_for(rec, a.strict_pins, a.branch)
        unresolved = r.unresolved_for(x.abspath)
        if unresolved:  # F3: a call that did not answer is never read as "absent" / "unchanged" / "moved"
            rec["unresolved"] = unresolved
            rec["reasons"] += ["unresolved:" + u for u in unresolved]
        rec.setdefault("actions", [])
        moved = bool(rec.get("initialised") and rec.get("head_after") is not None
                     and rec.get("head_before") is not None and rec.get("head_after") != rec.get("head_before"))
        if rec.get("failed"):
            rec["result"] = "failed"
            any_fail = True
        elif unresolved:
            rec["result"] = "unresolved"
            any_unresolved = True
        elif moved and mode == "apply":
            rec["result"] = "updated"
            if os.path.isfile(os.path.join(x.abspath, "scripts", "post_update_hook.sh")) and \
                    os.path.isfile(os.path.join(x.abspath, "Constitution.md")) and x.parent is not None:
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
        for k in ("_branch_wanted", "_follow", "_fetch_head"):
            rec.pop(k, None)
    if not needle["ok"]:
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
    report["canonical_sha256"] = canonical_sha256(report)
    try:
        os.makedirs(out_dir, mode=0o700, exist_ok=True)
        write_atomic(os.path.join(out_dir, "sync_report.json"), json.dumps(report, indent=2, sort_keys=True) + "\n")
        write_atomic(os.path.join(out_dir, "sync_report.tsv"), tsv_rows(report))
    except OSError as e:
        print("sync-upstreams: ERROR: cannot write evidence to %s: %s" % (redact(out_dir), e), file=sys.stderr)
        return EXIT_USAGE
    for rec in report["repos"]:
        if rec.get("result") not in ("current", "not-initialised") or not a.quiet:
            say(a, "%-40s %-15s %s" % (rec["path"], rec.get("result"), ",".join(rec.get("reasons", [])) or "-"))
    for h in report["next_steps"]:
        say(a, "next step (never run automatically): " + h)
    if tty:
        tty.say("sync-upstreams: %s (exit %d); report %s" % (verdict, code, out_dir))
    print("REPORT_JSON=%s" % os.path.join(out_dir, "sync_report.json"))
    print("CANONICAL_SHA256=%s" % report["canonical_sha256"])
    print("RESULT: %s exit=%d" % (verdict, code))
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
