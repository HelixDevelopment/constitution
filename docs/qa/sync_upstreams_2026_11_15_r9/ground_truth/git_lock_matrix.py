#!/usr/bin/env python3
"""Ground truth for round 9 (RV8-1): for each engine write shape and each candidate lock file, plant a STALE lock,
run the write exactly as the engine does (SAFE_CONFIG -c pairs, --no-optional-locks), and record what git did:
exit status, whether HEAD moved, whether the work tree / index changed (a half-applied write), and whether the
lock is still there.  Real git, sandbox under TMPDIR, no network.  Usage: git_lock_matrix.py <engine.py>"""
import importlib.util
import os
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location("eng", sys.argv[1])
eng = importlib.util.module_from_spec(spec)
spec.loader.exec_module(eng)
TMP = os.environ["TMPDIR"]
SB = tempfile.mkdtemp(prefix="glm.", dir=TMP)
ENV = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.path.join(SB, "gc"), GIT_AUTHOR_NAME="p",
           GIT_AUTHOR_EMAIL="p@x.invalid", GIT_COMMITTER_NAME="p", GIT_COMMITTER_EMAIL="p@x.invalid",
           GIT_CEILING_DIRECTORIES=TMP)
open(ENV["GIT_CONFIG_GLOBAL"], "w").write('[init]\n\tdefaultBranch = main\n[protocol "file"]\n\tallow = always\n')


def g(*a, cwd=None, check=True):
    p = subprocess.run(["git"] + list(a), cwd=cwd, env=ENV, capture_output=True, text=True)
    if check and p.returncode:
        raise SystemExit("git %s: %s" % (a, p.stderr))
    return p.stdout.strip()


def eg(repo, args):
    p = subprocess.run(eng.git_argv("git", repo, args), env=ENV, capture_output=True, text=True)
    return p.returncode, p.stderr.strip().splitlines()[-1:] if p.stderr.strip() else []


def fixture(n, worktree=False):
    d = os.path.join(SB, "c%d" % n)
    os.makedirs(d)
    up, seed, work = os.path.join(d, "up.git"), os.path.join(d, "seed"), os.path.join(d, "work")
    g("init", "-q", "--bare", up)
    g("init", "-q", seed)
    open(os.path.join(seed, "f"), "w").write("1\n")
    g("add", "f", cwd=seed)
    g("commit", "-qm", "1", cwd=seed)
    g("remote", "add", "origin", up, cwd=seed)
    g("push", "-q", "origin", "main", cwd=seed)
    g("clone", "-q", up, work)
    open(os.path.join(seed, "f"), "w").write("2\n")
    g("commit", "-qam", "2", cwd=seed)
    g("push", "-q", "origin", "main", cwd=seed)
    g("fetch", "-q", "origin", cwd=work)
    if worktree:
        g("branch", "-q", "wtb", "HEAD", cwd=work)
        wt = os.path.join(d, "wt")
        g("worktree", "add", "-q", wt, "wtb", cwd=work)
        return wt, os.path.join(work, ".git", "worktrees", "wt"), os.path.join(work, ".git"), "wtb"
    return work, os.path.join(work, ".git"), os.path.join(work, ".git"), "main"


CANDIDATES = [("gitdir", "index.lock"), ("gitdir", "HEAD.lock"), ("gitdir", "ORIG_HEAD.lock"),
              ("gitdir", "AUTO_MERGE.lock"), ("common", "packed-refs.lock"), ("common", "refs/heads/{b}.lock"),
              ("common", "objects/maintenance.lock"), ("common", "config.lock"), ("common", "shallow.lock"),
              ("common", "refs/heads/other.lock"), ("common", "HEAD.lock"), ("gitdir", "MERGE_HEAD.lock"),
              ("gitdir", "logs/HEAD.lock"), ("common", "logs/refs/heads/{b}.lock")]
n = 0
print("op\tworktree\tlock\trc\thead_moved\tstatus_after\tlock_left\tlast_err")
for op in ("ff", "detach"):
    for wt in (False, True):
        for where, name in CANDIDATES:
            n += 1
            work, gd, common, br = fixture(n, wt)
            base = common if where == "common" else gd
            if wt and where == "common" and name == "HEAD.lock":
                pass
            lk = os.path.join(base, name.format(b=br))
            os.makedirs(os.path.dirname(lk), exist_ok=True)
            open(lk, "w").close()
            before = g("rev-parse", "HEAD", cwd=work)
            target = g("rev-parse", "origin/main", cwd=work)
            if op == "ff":
                rc, err = eg(work, ["merge", "--ff-only", target])
            else:
                g("checkout", "-q", "--detach", "HEAD", cwd=work, check=False) if False else None
                rc, err = eg(work, ["checkout", "--quiet", "--detach", target])
            after = g("rev-parse", "HEAD", cwd=work)
            st = g("status", "--porcelain=v1", cwd=work)
            print("%s\t%s\t%s/%s\t%d\t%s\t%r\t%s\t%s" % (op, wt, where, name, rc, after != before, st,
                                                       os.path.lexists(lk), (err[0][:90] if err else "")))
# add (stage a gitlink) in a parent
for where, name in [("gitdir", "index.lock"), ("gitdir", "HEAD.lock"), ("common", "packed-refs.lock"),
                    ("common", "config.lock")]:
    n += 1
    d = os.path.join(SB, "a%d" % n)
    os.makedirs(d)
    up = os.path.join(d, "up.git")
    g("init", "-q", "--bare", up)
    s = os.path.join(d, "s")
    g("init", "-q", s)
    g("commit", "-q", "--allow-empty", "-m", "a", cwd=s)
    g("commit", "-q", "--allow-empty", "-m", "b", cwd=s)
    g("remote", "add", "origin", up, cwd=s)
    g("push", "-q", "origin", "main", cwd=s)
    par = os.path.join(d, "par")
    g("init", "-q", par)
    g("commit", "-q", "--allow-empty", "-m", "0", cwd=par)
    g("-c", "protocol.file.allow=always", "submodule", "-q", "add", up, "sub", cwd=par)
    g("commit", "-qm", "s", cwd=par)
    g("checkout", "-q", "--detach", "HEAD~1", cwd=os.path.join(par, "sub"))
    lk = os.path.join(par, ".git", name)
    open(lk, "w").close()
    rc, err = eg(par, ["add", "--", "sub"])
    st = g("diff", "--cached", "--name-only", cwd=par)
    print("add\tFalse\t%s/%s\t%d\t-\tstaged=%r\t%s\t%s" % (where, name, rc, st, os.path.lexists(lk),
                                                          (err[0][:90] if err else "")))
print("SANDBOX", SB)
