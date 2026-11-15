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
Review round 8 (RV7-1, the marker state machine); the driver also prints every write git it saw start, with what
the marker of that write's git dir held at that moment (``spawns``), and the bytes of every marker it planted:
  kill-first-add         the FIRST 'add' (a stage-pin) is ended by its own limit and SIGKILLed: the parent's
                         index.lock is created and the call returns 'timeout' (what a SIGKILLed git add leaves)
  kill-first-add-then-wipe  as kill-first-add, then the parent's marker AND index.lock are removed before the
                         next advance-pin starts (only the run's own state remembers the killed write)
  plant-<site>           a FOREIGN marker (not written by this run) is put into the git dir of the write at <site>
                         (ff, pin, follow, stage) right before that write asks for its marker (begin_write)
  race-<site>            the same marker appears in the window between begin_write's checks and the marker's
                         creation (only O_EXCL can see it)
  swap-<site>            the foreign marker replaces the write's own marker right after it was created, before
                         git starts (Runner.run's token check must see it)
  plant-pinparent        the foreign marker is put into the ROOT's git dir before an advance-pin starts
  lock-pinparent         an index.lock (a user's git) appears in the ROOT's git dir before an advance-pin starts
  lock-parent-at-pin-checkout  the same lock appears while the advance-pin checkout runs (after step 3a passed):
                         only the stage-pin's own begin_write can see it
  stop-at-pin-checkout   the stop signal lands while the advance-pin checkout runs (its second half, the stage-pin
                         add, must still run, holding its marker)
  none                   no fault (a control run with the spawn audit)
Review round 9 (RV8-1, RV8-3):
  vanish-<site>          the write's own marker is REMOVED right after it was created, before git starts (Runner.run's
                         token check must refuse: a write never starts without its marker; reviewer mutant W03)
  lockspawn:<lock>:<site>  a lock file (git-dir relative, or common/<path> for the common dir) appears right before
                         the write git of <site> starts and is removed right after it ended: another git process
                         that held the lock while the engine's write ran (git then fails, possibly half-way)
Review round 10 (RV9-6):
  lockspawn:<lock>:<site>:wt  as lockspawn, and the write also leaves an untracked work-tree file
                         (stray_by_write.txt) before git refuses: a failed write that changed ONLY the work tree
                         (a model of the class; git 2.53 itself was not measured to do this)
"""
import errno
import importlib.util
import json
import os
import subprocess
import sys

WRITES = ("merge", "checkout", "add")
SITES = {"ff": "fast-forward", "pin": "advance-pin", "follow": "follow-pin", "stage": "stage-pin"}


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
    BEGIN = hasattr(eng, "begin_write")  # the round-8 engine; the round-7 engine (control needle) has none
    orig_marker = eng.write_marker
    created = {}  # git dir -> bytes of the LAST marker this run created there
    spawns = []
    planted = {}  # git dir -> bytes of the foreign marker the driver planted
    vanished = set()  # git dirs whose own marker the driver removed (vanish-<site>)

    def deadline_now():
        eng.Runner.remaining = lambda self: -1.0

    def marker(gitdir, op, target, run_id, *rest, **kw):
        markers.append(op)
        site = SITES.get(fault.partition("-")[2])
        if site == op and os.path.realpath(gitdir) not in planted and (
                fault.startswith("race-") or (fault.startswith("plant-") and not BEGIN)):
            plant(gitdir)  # race-: after begin_write's checks; plant- on an engine without begin_write (round 7)
        done = orig_marker(gitdir, op, target, run_id, *rest, **kw)
        if done in (True, "written"):
            try:
                with open(os.path.join(gitdir, eng.WRITE_MARKER), "rb") as f_:
                    created[os.path.realpath(gitdir)] = f_.read()
            except OSError:
                pass
            if fault.startswith("swap-") and site == op and os.path.realpath(gitdir) not in planted:
                plant(gitdir)  # after the marker was created, before git starts
            if fault.startswith("vanish-") and site == op and os.path.realpath(gitdir) not in vanished:
                vanished.add(os.path.realpath(gitdir))
                os.unlink(os.path.join(gitdir, eng.WRITE_MARKER))  # after the marker was created, before git starts
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

    def plant(gitdir):
        data = json.dumps({"op": "fast-forward", "target": "0" * 40, "run_id": "planted-by-driver",
                           "write_id": "planted:0:0", "started": "x"}).encode()
        with open(os.path.join(gitdir, eng.WRITE_MARKER), "wb") as f_:
            f_.write(data)
        planted[os.path.realpath(gitdir)] = data

    def gitdir_of(repo):
        out = subprocess.run(["git", "-C", repo, "rev-parse", "--absolute-git-dir"], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True).stdout.strip()
        return out

    if fault.startswith("plant-") and BEGIN:
        orig_begin = eng.begin_write

        def begin(r, gitdir, op, target, final=False):
            if SITES.get(fault[6:]) == op and os.path.realpath(gitdir) not in planted:
                plant(gitdir)
            return orig_begin(r, gitdir, op, target, final)
        eng.begin_write = begin

    if fault == "plant-pinparent":
        orig_wg0 = eng.write_git

        def wg0(r, repo, op, target):
            if op == "advance-pin" and not planted:
                plant(repo.parent.rec.get("_gitdir") or "")  # in the ROOT's git dir, before the advance starts
            return orig_wg0(r, repo, op, target)
        eng.write_git = wg0

    pend = []  # lock-parent-at-pin-checkout: the parent's git dir of the advance-pin under way
    if fault in ("lock-pinparent", "lock-parent-at-pin-checkout"):
        orig_wg1, locked = eng.write_git, []

        def wg1(r, repo, op, target):
            if op == "advance-pin" and not locked:
                pg = repo.parent.rec.get("_gitdir") or ""
                if fault == "lock-pinparent":
                    open(os.path.join(pg, "index.lock"), "w").close()  # a user's git holds the ROOT's index
                else:
                    pend.append(pg)
                locked.append(pg)
            return orig_wg1(r, repo, op, target)
        eng.write_git = wg1

    if fault == "kill-first-add-then-wipe":
        orig_wg, pins = eng.write_git, []

        def wg(r, repo, op, target):
            if op == "advance-pin":
                pins.append(repo)
                if len(pins) == 2:
                    pg = repo.parent.rec.get("_gitdir") or ""
                    for n in (eng.WRITE_MARKER, "index.lock"):
                        try:
                            os.unlink(os.path.join(pg, n))
                        except FileNotFoundError:
                            pass
            return orig_wg(r, repo, op, target)
        eng.write_git = wg

    real_run_git = eng.proc_run_git
    adds = []
    lockspawn = fault.split(":") if fault.startswith("lockspawn:") else None
    lock_done = []
    SUB_OF = {"ff": "merge", "pin": "checkout", "follow": "checkout", "stage": "add"}

    def common_of(repo):
        return subprocess.run(["git", "-C", repo, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.strip()

    def run_git(git_bin, repo, args_, env, limit, level=1):
        if args_[:1] and args_[0] in WRITES:
            gd = gitdir_of(repo)
            try:
                with open(os.path.join(gd, eng.WRITE_MARKER), "rb") as f_:
                    now = f_.read()
            except OSError:
                now = None
            spawns.append({"sub": args_[0], "gitdir": gd, "marker": now is not None,
                           "own": now is not None and now == created.get(os.path.realpath(gd)),
                           "planted": now is not None and now == planted.get(os.path.realpath(gd))})
            if args_[0] == "checkout" and fault == "stop-at-pin-checkout":
                eng.STOP_REQUESTED.set()
            if args_[0] == "checkout" and fault == "lock-parent-at-pin-checkout" and pend:
                open(os.path.join(pend.pop(), "index.lock"), "w").close()  # after step 3a, while the child moves
            if lockspawn and not lock_done and args_[0] == SUB_OF[lockspawn[2]]:
                rel = lockspawn[1]
                base = common_of(repo) if rel.startswith("common/") else gd
                lk = os.path.join(base, rel[len("common/"):] if rel.startswith("common/") else rel)
                lock_done.append(lk)
                os.makedirs(os.path.dirname(lk), exist_ok=True)
                open(lk, "w").close()  # another git process holds this lock while the engine's write runs
                if lockspawn[3:] == ["wt"]:  # the write changed the work tree only, then failed (RV9-6 model)
                    with open(os.path.join(repo, "stray_by_write.txt"), "w") as f_:
                        f_.write("left by a failed write\n")
                try:
                    return real_run_git(git_bin, repo, args_, env, limit, level)
                finally:
                    os.unlink(lk)  # ... and has ended
            if args_[0] == "add" and fault.startswith("kill-first-add"):
                adds.append(repo)
                if len(adds) == 1:
                    open(os.path.join(gd, "index.lock"), "w").close()  # what a SIGKILLed git add leaves
                    return "timeout", None, "", "timeout after %ds; ended by SIGKILL" % int(limit)
        return real_run_git(git_bin, repo, args_, env, limit, level)
    eng.proc_run_git = run_git

    rc = eng.main(args)
    left = {}
    for gd, data in planted.items():
        try:
            with open(os.path.join(gd, eng.WRITE_MARKER), "rb") as f_:
                left[gd] = f_.read() == data
        except OSError:
            left[gd] = False
    sys.stdout.flush()
    sys.stderr.flush()
    print("DRIVER " + json.dumps({"rc": rc, "markers": markers, "spawns": spawns, "planted_intact": left}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
