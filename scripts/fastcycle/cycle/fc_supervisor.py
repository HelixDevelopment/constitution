#!/usr/bin/env python3
"""fc_supervisor.py -- process supervisor for baseline_replay.sh (spec-004
"fast-dev-cycles", T048 restart round 3, STRUCTURAL replacement of the round-1/2
trap / forwarding / session / token / /proc-environ-scan stop machinery,
docs/qa/t048_restart_round3_20261008/V4_baseline.md V4R3-1..V4R3-14).

WHY A SUPERVISOR (the round-3 convergence finding, §11.4.276(E)): every round
added one stop mechanism to the bash script (traps, TERM forwarding, a session
per gate, a per-run token, a /proc environ scan, poll-then-KILL, an flock on
fd 9) and every mechanism brought its own gap: a SIGKILLed main left the run
loop going (V4R3-1), the lock fd leaked into hook processes (V4R3-5), pids could
be reused between scan and kill (V4R3-10), the environ scan could block in a
signal handler (V4R3-12). This module replaces ALL of it with one rule: every
process the tool starts is a DESCENDANT of a supervisor that owns it by
construction, and is stopped by walking the supervisor's own process tree.

PROCESS LAYOUT (three supervisor roles, one module):

  M  `main`    -- the pid the caller started (baseline_replay.sh `exec`s into
                  it, so the caller's pid, process group and session are M's).
                  PR_SET_CHILD_SUBREAPER. Takes the replay locks (O_CLOEXEC, an
                  flock on the open file description, never inherited across
                  exec), creates the private temp directory, forks K, then only
                  waits. A stop signal (HUP/INT/QUIT/TERM) is forwarded to K
                  ONCE (later ones are ignored, so a second signal can never cut
                  a teardown short) and M exits 128+signal after K has finished.
  K  `keeper`  -- forked from M (shares M's lock file descriptions, so the locks
                  are held while EITHER is alive). setsid() -- a signal to the
                  caller's process group or terminal does not reach it -- and
                  PR_SET_CHILD_SUBREAPER. Starts W (bash, the real replay work)
                  with PR_SET_PDEATHSIG=SIGKILL and watches three things: W's
                  pidfd, a pipe whose only write end M holds (EOF = M is gone,
                  even by SIGKILL), and its own stop signals. On ANY of them it
                  stops its whole descendant tree, removes the worktrees /
                  marks the log dirs listed in the ledger, removes the temp
                  directory and exits.
  run          -- one per long-running child of W (a gate run, `git worktree
                  add` with its hooks, the submodule update). Also a subreaper,
                  PDEATHSIG=SIGKILL. Runs the command with a timeout, then stops
                  every process the command left behind before it returns -- a
                  gate's background daemon or a hook's `sleep &` never survives
                  into the next run. Writes the run's outcome to a marker file
                  (exited | timed_out | cd_failed | exec_failed).

Why every descendant is found: with PR_SET_CHILD_SUBREAPER an orphan is
re-parented to the NEAREST subreaper ancestor instead of init, so a process
that calls setsid, double-forks, clears its environment or starts a nested
`timeout` (its own process group) is still a child of `run`, K or M. The
tree is walked through /proc/<pid>/task/<tid>/children (structure, never a
command-line or environment match, §11.4.196(D)).

Signal safety (§11.4.263): a process is only ever signalled through a pidfd
(os.pidfd_open / signal.pidfd_send_signal). A pid read from the tree is opened
as a pidfd, then its parent is re-read from /proc and must still be the tree
node it was found under, then the pidfd is probed with signal 0: if the process
was alive at both the open and the probe it held the pid continuously, so the
/proc read was of THAT process. A pid <= 1 or this process itself is never
opened. No process group, no pid 0/-1, no raw `kill(pid)` anywhere.

Dispositions: the signals the caller had IGNORED when baseline_replay.sh
started (passed as --entry-sigign, the SigIgn mask of /proc/<pid>/status) stay
ignored in every role and every child -- `nohup baseline_replay.sh ...` keeps
working as nohup means. Everything else is reset to SIG_DFL in each child
(undoing Python's own SIGPIPE/SIGXFSZ ignore and bash's INT/QUIT ignore for
background jobs).

DESIGN DECISION (evidence, 2026-10-08, reference host: Linux 6.12, Python 3.13):
  - chosen: child subreaper + pidfd + PDEATHSIG. Measured: with
    PR_SET_CHILD_SUBREAPER a double-forked setsid grandchild re-parents to the
    subreaper (it appeared in /proc/<subreaper>/task/<tid>/children), and the
    test suite's stop matrix proves every gate shape is found and stopped.
    Needs only Linux >= 5.3 and Python >= 3.9 (pidfds) -- nothing privileged,
    no daemon, nothing host-specific.
  - not chosen: a cgroup per replay (`systemd-run --user --scope`). It works on
    the reference host (`systemd-run --user --scope --collect true` -> rc 0) and
    would also cover the double-SIGKILL boundary below, but it needs a running
    systemd user manager with delegation, which containers, CI runners and
    non-systemd hosts do not have; this tool is generic (§11.4.28).
  - the lock is taken HERE, on an open file description shared only by M and
    K (fork without exec) and O_CLOEXEC, so no exec'd program -- worker, gate,
    hook, daemon -- ever holds it (round 2 held it on fd 9 of the bash shell,
    inherited by every hook: V4R3-5).

HONEST BOUNDARY (§11.4.6): if M AND K are both SIGKILLed at the same moment,
nothing is left to process the ledger: W, `run` and the gate's own process die
through the PDEATHSIG chain (no further scheduled run starts), but processes the
gate itself started are re-parented to init and the worktree / temp directory
stay behind. Only kernel containment (a cgroup, e.g. `systemd-run --user
--scope`, available on the reference host but not on every host this generic
tool runs on) would close that; it is not required by this module. Processes
started on the tool's behalf by OTHER daemons (D-Bus activation, an adb server
that already runs) are not descendants and are not stopped; a daemon the gate
itself starts IS a descendant and IS stopped -- the tool leaves the host
quiescent (§11.4.14).

Ledger: W registers every worktree (repo root + path) and every run-log
directory as one file `ledger.<kind>.*` in the private temp directory BEFORE
creating it, and deletes the entry once it removed the worktree / wrote the
report. A teardown processes whatever entries remain: `git worktree remove
--force` + prune for a worktree (only a path whose last component starts with
`replay.`), and an INTERRUPTED file for a log directory that no report will
ever reference (V4R3-14).

Usage (internal; called by baseline_replay.sh, not by people):
  fc_supervisor.py main --tmp-parent DIR --entry-sigign HEX [--grace S]
                   [--lock FILE]... [--lock-dir DIR --lock-fs PATH...] -- CMD...
  fc_supervisor.py run --timeout S --marker FILE --cwd DIR --entry-sigign HEX
                   [--grace S] -- CMD...
Exit codes: main -- the worker's exit code, or 128+N when the tool was stopped
by signal N (sent to M, K or W); 4 when a lock is held or a supervisor step
failed (BLIND). run -- the command's exit code (128+N if a signal killed it),
124 on timeout (137 if it had to be KILLed), 125 on an internal error.
"""
import ctypes
import os
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

PR_SET_PDEATHSIG = 1
PR_SET_NAME = 15
PR_SET_CHILD_SUBREAPER = 36
STOP_SIGS = (signal.SIGHUP, signal.SIGINT, signal.SIGQUIT, signal.SIGTERM)
KILL_WAIT_S = 5.0          # after the KILL step, how long to wait for the tree to empty
MAX_NEST = 4               # supervisors nested inside supervisors (a gate that is itself an FC tool)
REAPED = {}                # pid -> wait status, filled by reap()

_libc = ctypes.CDLL(None, use_errno=True)


def _prctl(op, arg):
    rc = _libc.prctl(ctypes.c_int(op), ctypes.c_ulong(arg), ctypes.c_ulong(0),
                     ctypes.c_ulong(0), ctypes.c_ulong(0))
    if rc != 0:
        e = ctypes.get_errno()
        raise OSError(e, "prctl(%d) failed: %s" % (op, os.strerror(e)))


def _set_name(name):
    _libc.prctl(ctypes.c_int(PR_SET_NAME), ctypes.c_char_p(name.encode()[:15]),
                ctypes.c_ulong(0), ctypes.c_ulong(0), ctypes.c_ulong(0))


def say(msg):
    try:
        sys.stderr.write("baseline_replay: %s\n" % msg)
        sys.stderr.flush()
    except OSError:
        pass


def ignored(mask, sig):
    return bool((mask >> (int(sig) - 1)) & 1)


def all_catchable():
    return [s for s in range(1, signal.NSIG) if s not in (signal.SIGKILL, signal.SIGSTOP)
            and s < 32]


def reap():
    """Collect every exited child (subreapers inherit orphans; they must be reaped)."""
    while True:
        try:
            pid, st = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return
        except InterruptedError:
            continue
        if pid == 0:
            return
        REAPED[pid] = st


def decode(st):
    if os.WIFEXITED(st):
        return os.WEXITSTATUS(st)
    if os.WIFSIGNALED(st):
        return 128 + os.WTERMSIG(st)
    return 125


# --------------------------------------------------------------------------
# process tree
# --------------------------------------------------------------------------
def _stat_fields(pid):
    """(state, ppid) from /proc/<pid>/stat, fields read after the LAST ') ' so a
    comm holding spaces or parentheses cannot shift them; None if unreadable."""
    try:
        with open("/proc/%d/stat" % pid) as fh:
            st = fh.read()
        f = st[st.rindex(") ") + 2:].split()
        return f[0], int(f[1])
    except (OSError, ValueError, IndexError):
        return None


def _children(pid):
    out = []
    try:
        tids = os.listdir("/proc/%d/task" % pid)
    except OSError:
        return out
    for tid in tids:
        try:
            with open("/proc/%d/task/%s/children" % (pid, tid)) as fh:
                out.extend(int(x) for x in fh.read().split())
        except (OSError, ValueError):
            continue
    return out


def walk(root):
    """Live (non-zombie) descendants of root as ([(pid, parent)], zombies seen).

    The zombie count matters (T048 round 3, found by the stop matrix's
    KILL-supervisor-nested row): a node's children list is read BEFORE its
    children are stat'ed. A child that has already died (a zombie) had its own
    children reparented to the subreaper -- possibly AFTER the subreaper's list
    was read -- so they are in no list this walk read. An empty result is only
    the end of the tree when it saw no zombie (see stop_tree)."""
    out, seen, stack, zombies = [], {root}, [root], 0
    while stack:
        cur = stack.pop()
        for c in _children(cur):
            if c in seen:
                continue
            seen.add(c)
            sf = _stat_fields(c)
            if sf is None:
                continue
            if sf[0] == "Z":
                zombies += 1
            else:
                out.append((c, cur))
            stack.append(c)
    return out, zombies


def open_verified(pid, parent):
    """A pidfd for pid ONLY if it is still the child of `parent` (the tree node
    it was found under) and alive -- §11.4.263: no pid reuse, never pid <= 1,
    never this process."""
    if pid <= 1 or pid == os.getpid():
        return None
    try:
        fd = os.pidfd_open(pid)
    except OSError:
        return None
    sf = _stat_fields(pid)
    ok = sf is not None and sf[1] == parent
    if ok:
        try:
            signal.pidfd_send_signal(fd, 0)
        except OSError:
            ok = False
    if not ok:
        os.close(fd)
        return None
    return fd


def stop_tree(grace, label):
    """Stop every descendant of this process: SIGTERM (+SIGCONT, so a stopped
    process can act on it) to each, wait up to `grace` s, then SIGKILL whatever
    is left, re-walking the tree every 50 ms (a process forked during the stop is
    found too). Returns the number of distinct processes that had to be stopped."""
    me = os.getpid()
    t_kill = time.monotonic() + max(0.0, grace)
    termed, seen = set(), set()
    while True:
        reap()
        members, zombies = walk(me)
        if not members and not zombies:
            return len(seen)
        now = time.monotonic()
        for pid, parent in members:
            fd = open_verified(pid, parent)
            if fd is None:
                continue
            seen.add(pid)
            try:
                if now < t_kill:
                    if pid not in termed:
                        signal.pidfd_send_signal(fd, signal.SIGTERM)
                        signal.pidfd_send_signal(fd, signal.SIGCONT)
                        termed.add(pid)
                else:
                    signal.pidfd_send_signal(fd, signal.SIGKILL)
            except OSError:
                pass
            finally:
                os.close(fd)
        if now > t_kill + KILL_WAIT_S:
            if members:
                say("supervisor (%s): could not stop process(es) %s (unkillable or not ours) -- reported, not hidden"
                    % (label, " ".join(str(p) for p, _ in members)))
            else:
                say("supervisor (%s): %d zombie(s) in the tree were never reaped by their parent -- reported, "
                    "not hidden" % (label, zombies))
            return len(seen)
        time.sleep(0.05)


# --------------------------------------------------------------------------
# children
# --------------------------------------------------------------------------
def spawn(argv, env, entry_mask, cwd=None, marker=None):
    """fork+exec argv with PDEATHSIG=SIGKILL, dispositions reset (entry-ignored
    signals stay ignored, everything else SIG_DFL) and an empty signal mask."""
    old = signal.pthread_sigmask(signal.SIG_BLOCK, all_catchable())
    parent = os.getpid()
    pid = os.fork()
    if pid == 0:
        try:
            _prctl(PR_SET_PDEATHSIG, signal.SIGKILL)
            if os.getppid() != parent:
                os._exit(137)
            for s in all_catchable():
                try:
                    signal.signal(s, signal.SIG_IGN if ignored(entry_mask, s) else signal.SIG_DFL)
                except (OSError, ValueError):
                    pass
            signal.pthread_sigmask(signal.SIG_SETMASK, [])
            if cwd is not None:
                try:
                    os.chdir(cwd)
                except OSError:
                    _mark(marker, "cd_failed")
                    os._exit(127)
            try:
                os.execvpe(argv[0], argv, env)
            except OSError:
                _mark(marker, "exec_failed")
                os._exit(127)
        except BaseException:  # never return into the parent's code in the child
            os._exit(127)
    signal.pthread_sigmask(signal.SIG_SETMASK, old)
    return pid


def _mark(marker, text):
    """Write the outcome once: a child's cd_failed/exec_failed is never overwritten."""
    if not marker:
        return
    try:
        if os.path.exists(marker) and os.path.getsize(marker) > 0:
            return
        with open(marker, "w") as fh:
            fh.write(text)
    except OSError:
        pass


# --------------------------------------------------------------------------
# ledger
# --------------------------------------------------------------------------
def process_ledger(tmpdir, reason):
    try:
        names = sorted(os.listdir(tmpdir))
    except OSError:
        return
    for name in names:
        if not name.startswith("ledger."):
            continue
        path = os.path.join(tmpdir, name)
        try:
            with open(path, "rb") as fh:
                fields = fh.read().split(b"\0")
        except OSError:
            continue
        kind = name.split(".")[1] if name.count(".") >= 2 else ""
        if kind == "wt" and len(fields) >= 2:
            repo, wt = os.fsdecode(fields[0]), os.fsdecode(fields[1])
            if os.path.isabs(wt) and os.path.basename(wt).startswith("replay."):
                for args in (["worktree", "remove", "--force", wt], ["worktree", "prune"]):
                    try:
                        subprocess.run(["git", "-C", repo] + args, stdin=subprocess.DEVNULL,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
                    except (OSError, subprocess.SubprocessError):
                        pass
                if os.path.lexists(wt):
                    shutil.rmtree(wt, ignore_errors=True)
                say("supervisor: removed the worktree %s left by an interrupted replay (%s)" % (wt, reason))
            else:
                say("supervisor: ledger entry %s names a path that is not a replay worktree -- not touched" % name)
        elif kind == "logs" and fields and fields[0]:
            d = os.fsdecode(fields[0])
            if os.path.isdir(d):
                try:
                    with open(os.path.join(d, "INTERRUPTED"), "w") as fh:
                        fh.write("No report references this run-log directory: the replay that wrote it did "
                                 "not finish (%s). The logs are partial evidence of an interrupted run.\n" % reason)
                except OSError:
                    pass
        try:
            os.unlink(path)
        except OSError:
            pass


def teardown(tmpdir, grace, reason, label):
    n = stop_tree(grace, label)
    if n:
        say("supervisor (%s): stopped %d process(es) (%s)" % (label, n, reason))
    process_ledger(tmpdir, reason)
    if os.path.basename(tmpdir).startswith("fc_baseline_replay."):
        shutil.rmtree(tmpdir, ignore_errors=True)


# --------------------------------------------------------------------------
# main / keeper
# --------------------------------------------------------------------------
class Stop:
    sig = 0
    target_fd = None   # M: K's pidfd (forward target)


def _on_stop(signum, _frame):
    if Stop.sig:
        return  # a second signal never shortens a stop already in progress (V4-N12 class)
    Stop.sig = signum
    if Stop.target_fd is not None:
        try:
            signal.pidfd_send_signal(Stop.target_fd, signal.SIGTERM)
        except OSError:
            pass


def _install_stop(entry_mask):
    for s in STOP_SIGS:
        if not ignored(entry_mask, s):
            signal.signal(s, _on_stop)


def _take_locks(a):
    fds = []
    for path in a.lock:
        fds.append(_lock_one(path, "against this repository"))
    if a.lock_fs:
        if not os.path.isdir(a.lock_dir or ""):
            say("BLIND: lock directory %r is not a directory (FC_REPLAY_LOCK_DIR / XDG_RUNTIME_DIR)" % a.lock_dir)
            sys.exit(4)
        devs = []
        for p in a.lock_fs:
            try:
                d = os.stat(p).st_dev
            except OSError as e:
                say("BLIND: cannot stat %s for the per-filesystem lock: %s" % (p, e))
                sys.exit(4)
            if d not in devs:
                devs.append(d)
        for d in devs:
            fds.append(_lock_one(os.path.join(a.lock_dir, "fc_baseline_replay.fs-%d.lock" % d),
                                 "on the same filesystem"))
    return fds


def _lock_one(path, scope):
    import fcntl
    try:
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o644)
    except OSError as e:
        say("BLIND: cannot open the replay lock file %s: %s" % (path, e))
        sys.exit(4)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        say("BLIND: another baseline_replay replay is running %s (lock %s is held) -- refusing: two replays "
            "would each pass the free-space check and together exhaust the disk" % (scope, path))
        sys.exit(4)
    except OSError as e:
        say("BLIND: cannot lock %s: %s" % (path, e))
        sys.exit(4)
    return fd


def cmd_main(a):
    _set_name("fc-supervisor")
    # Host safety (§12.12): a worker that re-entered the supervisor instead of
    # doing its work would fork without end; nesting deeper than MAX_NEST is
    # refused (observed once while this module was written: the guard is real).
    try:
        depth = int(os.environ.get("FC_BR_NEST_DEPTH", "0"))
    except ValueError:
        depth = MAX_NEST
    if depth >= MAX_NEST:
        say("BLIND: supervisor nesting depth %d reached (FC_BR_NEST_DEPTH) -- refusing to start another one" % depth)
        sys.exit(4)
    os.environ["FC_BR_NEST_DEPTH"] = str(depth + 1)
    entry_mask = int(a.entry_sigign, 16)
    _prctl(PR_SET_CHILD_SUBREAPER, 1)
    _install_stop(entry_mask)
    old = signal.pthread_sigmask(signal.SIG_BLOCK, STOP_SIGS)
    _take_locks(a)          # fds stay open (and locked) until this process exits
    try:
        tmpdir = tempfile.mkdtemp(prefix="fc_baseline_replay.", dir=a.tmp_parent)
    except OSError as e:
        say("BLIND: cannot create a private temp directory under %s: %s" % (a.tmp_parent, e))
        sys.exit(4)
    r, w = os.pipe()        # M holds the only write end: EOF in K means M is gone
    sys.stdout.flush()
    sys.stderr.flush()
    try:
        kpid = os.fork()
    except OSError as e:
        shutil.rmtree(tmpdir, ignore_errors=True)
        say("BLIND: supervisor cannot fork its keeper: %s" % e)
        sys.exit(4)
    if kpid == 0:
        _keeper(a, entry_mask, tmpdir, r, w)  # never returns
    os.close(r)
    kfd = os.pidfd_open(kpid)
    Stop.target_fd = kfd
    if Stop.sig:   # a stop that arrived while blocked is forwarded now
        signal.pidfd_send_signal(kfd, signal.SIGTERM)
    signal.pthread_sigmask(signal.SIG_SETMASK, old)
    stop_deadline = None
    while True:
        reap()
        if kpid in REAPED:
            break
        if Stop.sig and stop_deadline is None:
            stop_deadline = time.monotonic() + a.grace + KILL_WAIT_S + 30
        if stop_deadline is not None and time.monotonic() > stop_deadline:
            say("supervisor: the keeper did not finish its stop in time -- killing it and stopping the tree here")
            try:
                signal.pidfd_send_signal(kfd, signal.SIGKILL)
            except OSError:
                pass
            stop_deadline = float("inf")
        try:
            select.select([kfd], [], [], 0.2)
        except InterruptedError:
            pass
    kst = REAPED[kpid]
    if os.WIFSIGNALED(kst):
        reason = "the keeper was killed by signal %d" % os.WTERMSIG(kst)
    else:
        reason = "the keeper exited %d" % decode(kst)
    # normally a no-op (K already did it); the real work when K died abnormally
    teardown(tmpdir, a.grace, reason, "main")
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(128 + Stop.sig if Stop.sig else decode(kst))


def _keeper(a, entry_mask, tmpdir, r, w):
    code = 70
    try:
        os.close(w)
        Stop.sig = 0
        Stop.target_fd = None
        os.setsid()
        _set_name("fc-keeper")
        _prctl(PR_SET_CHILD_SUBREAPER, 1)
        _install_stop(entry_mask)
        env = dict(os.environ)
        env.update(FC_BR_SUPERVISED="1", FC_BR_TMPDIR=tmpdir, FC_BR_SUPERVISOR_PID=str(os.getpid()),
                   FC_BR_ENTRY_SIGIGN=a.entry_sigign)
        wpid = spawn(a.cmd, env, entry_mask)
        wfd = os.pidfd_open(wpid)
        signal.pthread_sigmask(signal.SIG_SETMASK, [])
        reason, code = None, 0
        while True:
            if Stop.sig:
                reason, code = "stopped by signal %d" % Stop.sig, 128 + Stop.sig
                break
            try:
                ready, _, _ = select.select([wfd, r], [], [], 0.2)
            except InterruptedError:
                continue
            reap()
            if wpid in REAPED:
                code = decode(REAPED[wpid])
                reason = "the worker exited %d" % code
                break
            if r in ready:
                try:
                    data = os.read(r, 1)
                except OSError:
                    data = b""
                if not data:
                    reason, code = "the supervisor's main process is gone", 137
                    break
        teardown(tmpdir, a.grace, reason, "keeper")
    except BaseException as e:  # noqa: BLE001 -- never fall back into M's code path
        say("supervisor (keeper) internal error: %r" % (e,))
        code = 70
    finally:
        try:
            sys.stdout.flush()
            sys.stderr.flush()
        except OSError:
            pass
        os._exit(code)


# --------------------------------------------------------------------------
# run
# --------------------------------------------------------------------------
def cmd_run(a):
    _set_name("fc-run")
    entry_mask = int(a.entry_sigign, 16)
    parent = os.getppid()
    _prctl(PR_SET_PDEATHSIG, signal.SIGKILL)
    if os.getppid() != parent:
        os._exit(137)
    _prctl(PR_SET_CHILD_SUBREAPER, 1)
    # the caller's ignored signals stay ignored here too: under nohup a SIGHUP to
    # the worker's process group must not stop a gate run (found by the stop
    # matrix's nohup rows). A stop the caller cannot deliver is still reached by
    # the keeper's TERM-then-KILL.
    _install_stop(entry_mask)
    try:
        if os.path.exists(a.marker):
            os.unlink(a.marker)
    except OSError:
        pass
    pid = spawn(a.cmd, dict(os.environ), entry_mask, cwd=a.cwd, marker=a.marker)
    pfd = os.pidfd_open(pid)
    deadline = time.monotonic() + a.timeout
    timed_out = False
    while True:
        reap()
        if pid in REAPED:
            break
        if Stop.sig:
            stop_tree(a.grace, "run")
            _mark(a.marker, "stopped")
            os._exit(128 + Stop.sig)
        left = deadline - time.monotonic()
        if left <= 0:
            timed_out = True
            break
        try:
            select.select([pfd], [], [], min(0.2, left))
        except InterruptedError:
            pass
    if timed_out:
        stop_tree(a.kill_after, "run timeout")
        st = REAPED.get(pid)
        _mark(a.marker, "timed_out")
        os._exit(137 if st is not None and os.WIFSIGNALED(st) and os.WTERMSIG(st) == signal.SIGKILL else 124)
    rc = decode(REAPED[pid])
    n = stop_tree(a.grace, "run")
    if n:
        say("supervisor (run): the command exited but left %d process(es) running; stopped them" % n)
    _mark(a.marker, "exited")
    os._exit(rc)


def _parse(argv):
    import argparse
    if "--" not in argv:
        raise SystemExit("fc_supervisor: missing -- CMD")
    i = argv.index("--")
    opts, cmd = argv[:i], argv[i + 1:]
    if not cmd:
        raise SystemExit("fc_supervisor: empty command")
    p = argparse.ArgumentParser(prog="fc_supervisor.py")
    sub = p.add_subparsers(dest="mode", required=True)
    m = sub.add_parser("main")
    m.add_argument("--tmp-parent", required=True)
    m.add_argument("--entry-sigign", default="0")
    m.add_argument("--grace", type=float, default=10.0)
    m.add_argument("--lock", action="append", default=[])
    m.add_argument("--lock-dir", default="")
    m.add_argument("--lock-fs", action="append", default=[])
    r = sub.add_parser("run")
    r.add_argument("--timeout", type=float, required=True)
    r.add_argument("--kill-after", type=float, default=5.0)
    r.add_argument("--grace", type=float, default=10.0)
    r.add_argument("--marker", required=True)
    r.add_argument("--cwd", required=True)
    r.add_argument("--entry-sigign", default="0")
    a = p.parse_args(opts)
    a.cmd = cmd
    return a


def main():
    try:
        a = _parse(sys.argv[1:])
    except SystemExit as e:
        if e.code not in (0, None):
            say("supervisor: usage error: %s" % e.code)
        os._exit(125 if (sys.argv[1:2] == ["run"]) else 4)
    try:
        if a.mode == "main":
            cmd_main(a)
        else:
            cmd_run(a)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001
        say("BLIND: supervisor (%s) failed: %r" % (a.mode, e))
        os._exit(125 if a.mode == "run" else 4)


if __name__ == "__main__":
    main()
