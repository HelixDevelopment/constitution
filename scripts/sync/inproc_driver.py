#!/usr/bin/python3 -I
"""scripts/sync/inproc_driver.py -- test-only driver for tests/sync/test_robustness.sh (never used by the engine).

It loads the REAL engine module (scripts/sync/sync_all_upstreams.py, or the mutated copy next to $SX_ENGINE),
applies ONE named fault at a point that no external program can reach in time (the microseconds between two
statements of the engine), runs the engine's own main() against real git repositories, and prints one line
``DRIVER {"rc": <exit status>, "markers": [<op of every write_marker call>]}`` on stdout. Each fault is a test
double for the ENVIRONMENT (a signal, the clock, the kernel), never for git or for the engine's logic: every git
call still reaches the real binary. Review round 7 (RV6-1, RV6-3).

Usage: inproc_driver.py <engine.py> <fault> <engine argv...>
Faults:
  stop-after-marker      the stop signal lands right after a write's marker is written (STOP_REQUESTED)
  deadline-after-marker  the run deadline passes right after a write's marker is written
  stop-before-marker     the stop signal lands right after the write-time branch re-check (step 4), before the
                         write's marker would be written
  deadline-before-marker the run deadline passes at the same point
  spawn-fails-write      the kernel cannot start the write's git process (Popen raises OSError) for merge,
                         checkout or add; every other call runs
  hardstop-after-stage-marker   the second stop signal lands right after the stage-pin marker is written
  hardstop-before-stage-marker  the second stop signal lands right after the child's post-write branch read (the
                         first final read_branch), before the stage-pin marker would be written
  flock-error-root       the root run lock's flock fails with ENOLCK (not "held by another run")
  flock-error-repo       the first per-repository run lock's flock fails with ENOLCK
  flock-held-repo        control: the first per-repository flock fails with EWOULDBLOCK (another run holds it)
"""
import errno
import importlib.util
import json
import os
import sys

WRITES = ("merge", "checkout", "add")


class Proxy:
    """Delegates every attribute to ``real`` except the ones given."""
    def __init__(self, real, **over):
        self._real = real
        self.__dict__.update(over)

    def __getattr__(self, name):
        return getattr(self._real, name)


def main(argv):
    eng_path, fault, args = argv[0], argv[1], argv[2:]
    spec = importlib.util.spec_from_file_location("sync_engine_inproc", eng_path)
    eng = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(eng)
    markers = []
    orig_marker = eng.write_marker

    def deadline_now():
        eng.Runner.remaining = lambda self: -1.0

    def marker(gitdir, op, target, run_id):
        markers.append(op)
        done = orig_marker(gitdir, op, target, run_id)
        if fault == "stop-after-marker":
            eng.STOP_REQUESTED.set()
        elif fault == "deadline-after-marker":
            deadline_now()
        elif fault == "hardstop-after-stage-marker" and op == "stage-pin":
            eng.STOP_REQUESTED.set()
            eng.HARD_STOP.set()
        return done
    eng.write_marker = marker

    if fault in ("stop-before-marker", "deadline-before-marker"):
        orig_branch, seen = eng.read_branch, []

        def branch(r, repo, final=False):
            got = orig_branch(r, repo, final)
            seen.append(repo)
            if not final and seen.count(repo) == 2:  # the write-time re-check of step 4 (the first is inspection)
                if fault == "stop-before-marker":
                    eng.STOP_REQUESTED.set()
                else:
                    deadline_now()
            return got
        eng.read_branch = branch

    if fault == "hardstop-before-stage-marker":
        orig_branch2 = eng.read_branch

        def branch2(r, repo, final=False):
            got = orig_branch2(r, repo, final)
            if final and not eng.HARD_STOP.is_set():
                eng.STOP_REQUESTED.set()
                eng.HARD_STOP.set()
            return got
        eng.read_branch = branch2

    if fault == "spawn-fails-write":
        real_popen = eng.subprocess.Popen

        def popen(argv_, *a, **k):
            # argv_ = <git> -C <repo> (-c k=v)... --no-optional-locks <subcommand> ... (git_argv)
            i = argv_.index("--no-optional-locks") + 1 if "--no-optional-locks" in argv_ else len(argv_)
            if argv_[i:i + 1] and argv_[i] in WRITES:
                raise OSError(errno.EACCES, "Permission denied (inproc_driver: spawn-fails-write)")
            return real_popen(argv_, *a, **k)
        eng.subprocess = Proxy(eng.subprocess, Popen=popen)

    if fault.startswith("flock-"):
        real_flock, n = eng.fcntl.flock, []

        def flock(fd, how):
            n.append(fd)
            if (fault == "flock-error-root" and len(n) == 1) or (fault != "flock-error-root" and len(n) == 2):
                if fault == "flock-held-repo":
                    raise BlockingIOError(errno.EWOULDBLOCK, "Resource temporarily unavailable")
                raise OSError(errno.ENOLCK, "No locks available (inproc_driver: %s)" % fault)
            return real_flock(fd, how)
        eng.fcntl = Proxy(eng.fcntl, flock=flock)

    rc = eng.main(args)
    sys.stdout.flush()
    sys.stderr.flush()
    print("DRIVER " + json.dumps({"rc": rc, "markers": markers}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
