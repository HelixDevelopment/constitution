#!/usr/bin/python3 -I
"""scripts/sync/race_git_shim.py -- test-only git shim for tests/sync/test_robustness.sh (never used by the engine).

It stands on PATH as ``git`` (through a two-line launcher the test writes) and plays a USER acting in the project
while an engine run is in flight, then executes the real git with the unchanged argument vector. It is a test
double for the user, never for git: every git call still reaches the real binary (SXR_GIT).

Environment (all set by the test; no action without SXR_ACTION and SXR_ON):
  SXR_GIT     the real git binary (absolute path)
  SXR_ACTION  commit | switch-branch | checkout-branch | touch-file | chmod-out | sigterm-parent
  SXR_ON      '<subcommand>@<realpath of -C directory>': the engine call that triggers the action
  SXR_NTH     trigger on the n-th matching call (default 1)
  SXR_TARGET  the repository (or directory) the user acts in
  SXR_MARK    marker path: the action fires once (O_EXCL); commit writes <mark>.sha
  SXR_FILE    touch-file: the work-tree file (relative to SXR_TARGET) that is overwritten
  SXR_LOG     optional: every call appends '<subcommand>\t<realpath of -C directory>\t<before|after>' (after =
              the action has already fired), so a test can see which calls the engine STARTED after it
  SXR_GARBAGE_AFTER  optional '<subcommand>': a call of that subcommand started after the action fired prints a
              non-object-id and exits 0 (a malformed answer), without running git
  SXR_HANG_AFTER  optional '<subcommand>:<seconds>': a call of that subcommand started after the action fired
              sleeps first (a git that hangs after a stop); the engine's own timeout kills it
Safety: sigterm-parent signals ONLY the parent process (one pid, never a group), and only after reading its
/proc/<pid>/cmdline and finding sync_all_upstreams.py in it (section 11.4.263: verify before signalling).
"""
import os
import signal
import subprocess
import sys
import time

REAL = os.environ.get("SXR_GIT") or "/usr/bin/git"


def target_of(argv):
    repo, sub, i = None, None, 0
    while i < len(argv):
        a = argv[i]
        if a == "-C" and i + 1 < len(argv):
            repo = argv[i + 1]
            i += 2
            continue
        if a == "-c" and i + 1 < len(argv):
            i += 2
            continue
        if a.startswith("-"):
            i += 1
            continue
        sub = a
        break
    return repo, sub


def act(action, target, mark):
    env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_SSH", "SXR_"))}
    if action == "commit":
        with open(os.path.join(target, "user_work.txt"), "w") as f:
            f.write("precious user work\n")
        subprocess.run([REAL, "-C", target, "add", "user_work.txt"], env=env, check=True)
        subprocess.run([REAL, "-C", target, "commit", "-q", "-m", "user work during sync"], env=env, check=True)
        sha = subprocess.run([REAL, "-C", target, "rev-parse", "HEAD"], env=env, check=True,
                             stdout=subprocess.PIPE, text=True).stdout.strip()
        with open(mark + ".sha", "w") as f:
            f.write(sha)
    elif action == "switch-branch":
        subprocess.run([REAL, "-C", target, "checkout", "-q", "-b", "topic"], env=env, check=True)
    elif action == "checkout-branch":
        subprocess.run([REAL, "-C", target, "checkout", "-q", "-b", "user-branch"], env=env, check=True)
    elif action == "touch-file":
        with open(os.path.join(target, os.environ["SXR_FILE"]), "w") as f:
            f.write("user edit made while the engine was about to write\n")
    elif action == "chmod-out":
        os.chmod(target, 0o500)
    elif action == "sigterm-parent":
        ppid = os.getppid()
        try:
            with open("/proc/%d/cmdline" % ppid, "rb") as f:
                cmd = f.read().replace(b"\0", b" ")
        except OSError:
            cmd = b""
        if ppid > 1 and b"sync_all_upstreams.py" in cmd:
            os.kill(ppid, signal.SIGTERM)
            time.sleep(1.0)  # the engine's handler has run; the write below must still complete
            with open(mark + ".signalled", "w") as f:
                f.write(str(ppid))


def main(argv):
    on = os.environ.get("SXR_ON", "")
    action = os.environ.get("SXR_ACTION", "")
    repo, sub = target_of(argv)
    log = os.environ.get("SXR_LOG")
    if log:
        mark_ = os.environ.get("SXR_MARK", "")
        when = "after" if mark_ and os.path.exists(mark_) else "before"
        fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        os.write(fd, ("%s\t%s\t%s\n" % (sub or "?", os.path.realpath(repo) if repo else "?", when)).encode())
        os.close(fd)
    hang = os.environ.get("SXR_HANG_AFTER", "")
    if hang and sub and os.environ.get("SXR_MARK") and os.path.exists(os.environ["SXR_MARK"]):
        h_sub, _, h_sec = hang.partition(":")
        if sub == h_sub:
            time.sleep(float(h_sec))
    garbage = os.environ.get("SXR_GARBAGE_AFTER", "")
    if garbage and sub == garbage and os.environ.get("SXR_MARK") and os.path.exists(os.environ["SXR_MARK"]):
        sys.stdout.write("not-an-object-id\n")  # a git that answers garbage after the action fired
        sys.stdout.flush()
        os._exit(0)
    if on and action and repo and sub:
        want_sub, _, want_repo = on.partition("@")
        if sub == want_sub and os.path.realpath(repo) == os.path.realpath(want_repo):
            mark = os.environ["SXR_MARK"]
            fd = os.open(mark + ".count", os.O_RDWR | os.O_CREAT | os.O_APPEND, 0o600)
            os.write(fd, b"x")
            n = os.fstat(fd).st_size
            os.close(fd)
            if n == int(os.environ.get("SXR_NTH", "1")):
                try:
                    os.close(os.open(mark, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
                    act(action, os.environ["SXR_TARGET"], mark)
                except FileExistsError:
                    pass
    os.execv(REAL, [REAL] + argv)


if __name__ == "__main__":
    main(sys.argv[1:])
