#!/usr/bin/env bash
# =============================================================================
# test_fc_supervisor_v4r8_stream_matrix.sh -- T048 V4 round 8, V4R8-1 (CLASS 2, "the state of the caller's streams
# never changes the exit code"), the §11.4.276(C) CLASS-EXHAUSTIVE matrix. Round 7 closed CLASS 2 for ONE stream state
# (stderr a broken pipe at main's final flush); the round-7 review then found three more members of the class
# (V4R8-1 a/b/c): stdout/stderr CLOSED (`>&-`: Python's sys.stdout is None, `_flush` raised AttributeError -> rc 1 with a
# traceback, temp dir leaked), a dead stdout reader under --determinism-check (the worker died of SIGPIPE echoing the
# verdict BEFORE the mandatory report: rc 141, no report), a dead stderr reader on a harness error (rc 141, not 4).
# Instead of one row per member found, this file enumerates the class and checks every cell against ONE exit table.
#
# THE CLASS: {main (python), keeper (python), worker (bash), run supervisor (python)} x the caller's stdout/stderr
# {open (read) | a pipe nobody reads, caller SIGPIPE default | the same, caller SIGPIPE ignored | closed}
# x {replay ok | --determinism-check | harness error | usage error | stop INT/TERM/HUP/QUIT to main | SIGKILL of main /
# keeper / worker / run supervisor | TERM to keeper / worker / run supervisor}. main, keeper and worker share the
# caller's streams (inherited); a run supervisor's streams are ALWAYS the run's log file inside the tool -- that axis is
# unreachable from the caller ([R8RUNLOG] proves it statically) and is tested by invoking the run role directly
# ([R8RUN]: open / dead pipe / closed x exit / stop / timeout).
#
# ROUND 9 (T048 V4, V4R9-2 / V4R9-6): the class statement above omitted members; added as stream states: stalled
# (a reader ALIVE but not reading, the pipe pre-filled: every write blocks), full (/dev/full), dead-out + closed-err
# (mixed), stdin closed / stdin open in the wrong direction, stdout / stderr open in the wrong direction BY THE CALLER
# (`1<file`, `2<file`); and as scenarios: replay-sample, selfcheck, freeze, stop-after-report (TERM to main the moment
# the report appears). The needle now checks main's fd 0 as well. Declared scope: STALL_SKIP (see there).
# THE ONE EXIT TABLE ([R8MATRIX], fc_supervisor.py main_exit_code + baseline_replay.sh EXIT CODES):
#   ok 0 report | det 0 report | herr 4 report | usage 2 - | stop N to main 128+N - | KILL main: the caller's process
#   dies of SIGKILL (-9), the keeper still cleans up - | KILL keeper 137 - | KILL worker 137 - | KILL run supervisor 4 - |
#   TERM keeper 143 - | TERM worker 143 - | TERM run supervisor 0 report (that run is UNMEASURED, the replay goes on).
# Every cell additionally requires: no Traceback (open stderr), nothing left running, the temp dir gone, every replay
# worktree removed.
# Round 10 (V4R10-6): EVERY supervised cell records, from inside a replica, the fds 0/1/2 of main, keeper and worker at
#   their start and requires the expected direction for every role (FDPROBE, see RREP); usage/freeze: no record.
# The stop/kill cells also check main's own fd 1/2 (control needle for the stream state: a pipe, or /dev/null after
#   repair). Its first full run found one more member of the class: with the caller's stderr CLOSED, bash opens the
#   script itself on fd 2 and leaves it there (read-only, inheritable) -- main, keeper and worker ran with "stderr" =
#   baseline_replay.sh. fc_supervisor.py _repair_std_fds now also replaces a standard fd open in the wrong direction.
# [R8SIGPIPE] census: main, keeper and worker run with SIGPIPE ignored (a dead reader is an EPIPE error, never death),
#   the gate still starts with SIGPIPE at its default (control needle: the gate is found).
# [R8FDS] main started with fds 0/1/2 CLOSED gives its worker /dev/null on all three (fc_supervisor.py
#   _repair_std_fds) -- never a data file that a later write to "stderr" would corrupt.
#
# Env: FC_SUP_UNDER_TEST / FC_BR_UNDER_TEST (the mutation runner points them at a replica); R8_ONLY -- case tags;
#      R8_STREAMS / R8_SCENARIOS -- restrict the matrix (space-separated names, default all).
# Exit: 0 every selected cell held; 1 otherwise. Runtime: ~10 minutes for the full matrix (run it in the background,
# §11.4.89). Signals only through pidfds to validated pids > 1 this test started (§11.4.263); no pkill / pgrep -f.
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
SUP="${FC_SUP_UNDER_TEST:-$FC/cycle/fc_supervisor.py}"
SCRIPT="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"
[ -f "$SUP" ] || { echo "NOT ok supervisor under test not found: $SUP"; exit 1; }
[ -f "$SCRIPT" ] || { echo "NOT ok baseline_replay.sh under test not found: $SCRIPT"; exit 1; }

WORK="$(mktemp -d)"
# shellcheck disable=SC2329  # cleanup is invoked indirectly: it is the EXIT trap handler registered below
cleanup() {
  # ONLY a process whose argv[0] starts with this run's marker (set with `exec -a` by this test) is signalled here;
  # everything else is stopped structurally by the Python runner (a child subreaper) -- the v4r5 F6 rule.
  M="v8m-$$-" python3 - <<'PY' 2>/dev/null
import os, signal
m, me, pp = os.environ["M"], os.getpid(), os.getppid()
for p in os.listdir("/proc"):
    if not p.isdigit() or int(p) <= 1 or int(p) in (me, pp):
        continue
    try:
        argv0 = open("/proc/%s/cmdline" % p, "rb").read().split(b"\0")[0].decode(errors="replace")
    except (OSError, IndexError):
        continue
    if argv0.startswith(m):
        try:
            fd = os.pidfd_open(int(p))
        except OSError:
            continue
        try:
            signal.pidfd_send_signal(fd, signal.SIGKILL)
        except OSError:
            pass
        finally:
            os.close(fd)
PY
  chmod -R u+rwx "$WORK" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

SUP="$SUP" SCRIPT="$SCRIPT" WORK="$WORK" MARK="v8m-$$-" python3 -I - <<'PY'
import atexit, ctypes, os, shutil, signal, subprocess, sys, threading, time

SUP, SCRIPT, WORK, MARK = os.environ["SUP"], os.environ["SCRIPT"], os.environ["WORK"], os.environ["MARK"]
ONLY = os.environ.get("R8_ONLY", "").split()
N = {"ok": 0, "bad": 0}

# ---- T048 V4 round 10 (V4R10-6): the fd-direction needle in EVERY role of EVERY supervised scenario. Round 9 checked
# main's fds 0/1/2 only in the stop/kill cells (the one moment the test could read them from outside); a regression of
# _repair_std_fds limited to one subcommand or one role (reviewer mutant RV3-09: replay-sample skips it) was invisible
# in the ok / det / herr / replay-sample / selfcheck / stop-after-report cells. A REPLICA of cycle/ + lib/ (built from
# the files under test) records, at the start of the main role, of the keeper and of the worker, the targets of fds
# 0/1/2 -- read BEFORE the record file is opened (a closed fd would otherwise BE the record file) -- into $R8_FDLOG.
# Every cell then requires: main, keeper and worker each recorded at least once (control needle: the probe ran), and
# every record shows the caller's stream state as the tool must see it (EXP below). `usage` and `freeze` start no
# supervisor (usage is refused by bash, freeze runs unsupervised by design): there the log must stay EMPTY.
RREP = os.path.join(WORK, "rep")
_src_fc = os.path.dirname(os.path.dirname(os.path.abspath(SCRIPT)))
shutil.copytree(os.path.join(_src_fc, "lib"), os.path.join(RREP, "lib"))
shutil.copytree(os.path.dirname(os.path.abspath(SCRIPT)), os.path.join(RREP, "cycle"))
shutil.copy(SUP, os.path.join(RREP, "cycle", "fc_supervisor.py"))
shutil.copy(SCRIPT, os.path.join(RREP, "cycle", "baseline_replay.sh"))
RSCRIPT = os.path.join(RREP, "cycle", "baseline_replay.sh")
_PYPROBE = (
    "def _r8fd(role):\n"
    "    import os as _o\n"
    "    f = _o.environ.get('R8_FDLOG')\n"
    "    if not f:\n"
    "        return\n"
    "    links = []\n"
    "    for fd in (0, 1, 2):\n"
    "        try:\n"
    "            links.append(_o.readlink('/proc/self/fd/%d' % fd))\n"
    "        except OSError:\n"
    "            links.append('')\n"
    "    try:\n"
    "        with open(f, 'a') as fh:\n"
    "            fh.write('%s\\t%s\\n' % (role, '\\t'.join(links)))\n"
    "    except OSError:\n"
    "        pass\n\n\n")
PROBE_OK = []


def _inject(path, pairs):
    t = open(path).read()
    for a, b in pairs:
        if t.count(a) != 1:
            PROBE_OK.append("anchor matched %d times in %s: %r" % (t.count(a), os.path.basename(path), a[:60]))
            continue
        t = t.replace(a, b, 1)
    open(path, "w").write(t)


_inject(os.path.join(RREP, "cycle", "fc_supervisor.py"), [
    ("def cmd_main(a):\n    global OWNER\n", _PYPROBE + "def cmd_main(a):\n    global OWNER\n    _r8fd('main')\n"),
    ("    global HB_FD\n", "    global HB_FD\n    _r8fd('keeper')\n")])
_inject(RSCRIPT, [("  _FC_IS_WORKER=1\n  trap 'exit 129' HUP\n",
                   "  _FC_IS_WORKER=1\n  if [ -n \"${R8_FDLOG:-}\" ]; then _r8a=$(readlink /proc/$$/fd/0); "
                   "_r8b=$(readlink /proc/$$/fd/1); _r8c=$(readlink /proc/$$/fd/2); "
                   "printf 'worker\\t%s\\t%s\\t%s\\n' \"$_r8a\" \"$_r8b\" \"$_r8c\" >>\"$R8_FDLOG\"; fi\n"
                   "  trap 'exit 129' HUP\n")])
ctypes.CDLL(None, use_errno=True).prctl(ctypes.c_int(36), ctypes.c_ulong(1), ctypes.c_ulong(0),
                                        ctypes.c_ulong(0), ctypes.c_ulong(0))


def _kill_own_tree():
    me = os.getpid()
    for _ in range(100):
        found, stack, seen = [], [me], {me}
        while stack:
            cur = stack.pop()
            for c in children(cur):
                if c not in seen:
                    seen.add(c); stack.append(c); found.append((c, cur))
        live = 0
        for pid, parent in found:
            if pid <= 1 or pid == me:
                continue
            try:
                fd = os.pidfd_open(pid)
            except OSError:
                continue
            try:
                if ppid(pid) == parent and state(pid) != "Z":
                    signal.pidfd_send_signal(fd, signal.SIGKILL); live += 1
            except OSError:
                pass
            finally:
                os.close(fd)
        while True:
            try:
                if os.waitpid(-1, os.WNOHANG)[0] == 0:
                    break
            except ChildProcessError:
                break
        if not live:
            return
        time.sleep(0.05)


atexit.register(_kill_own_tree)


def ok(s):
    N["ok"] += 1; print("ok " + s, flush=True)


def bad(s):
    N["bad"] += 1; print("NOT ok " + s, flush=True)


def want(tag):
    return not ONLY or tag in ONLY


def g(*a):
    return subprocess.run(["git", "-c", "user.email=t@t.t", "-c", "user.name=t"] + list(a), capture_output=True,
                          text=True)


def mk_repo(path):
    os.makedirs(path)
    g("init", "-q", path)
    open(os.path.join(path, "f.txt"), "w").write("hello\n")
    g("-C", path, "add", "f.txt")
    g("-C", path, "commit", "-q", "-m", "base")
    return g("-C", path, "rev-parse", "HEAD").stdout.strip()


def _stat(pid):
    try:
        st = open("/proc/%d/stat" % pid).read()
        return st[st.rindex(") ") + 2:].split()
    except (OSError, ValueError):
        return None


def state(pid):
    f = _stat(pid)
    return f[0] if f else None


def ppid(pid):
    f = _stat(pid)
    return int(f[1]) if f else None


def comm(pid):
    try:
        return open("/proc/%d/comm" % pid).read().strip()
    except OSError:
        return ""


def children(pid):
    out = []
    try:
        for tid in os.listdir("/proc/%d/task" % pid):
            try:
                out += [int(x) for x in open("/proc/%d/task/%s/children" % (pid, tid)).read().split()]
            except (OSError, ValueError):
                pass
    except OSError:
        pass
    return out


def sig_pid(pid, signo):
    """§11.4.263: a validated int > 1, never this process, through a pidfd."""
    if not isinstance(pid, int) or pid <= 1 or pid == os.getpid():
        return False
    try:
        fd = os.pidfd_open(pid)
    except OSError:
        return False
    try:
        signal.pidfd_send_signal(fd, signo)
        return True
    except OSError:
        return False
    finally:
        os.close(fd)


def argv0_pids(name):
    out = []
    for p in os.listdir("/proc"):
        if not p.isdigit() or int(p) <= 1:
            continue
        try:
            a0 = open("/proc/%s/cmdline" % p, "rb").read().split(b"\0")[0].decode(errors="replace")
        except (OSError, IndexError):
            continue
        if a0 == name and state(int(p)) not in (None, "Z"):
            out.append(int(p))
    return out


def marked_left():
    out = []
    for p in os.listdir("/proc"):
        if not p.isdigit() or int(p) <= 1:
            continue
        try:
            a0 = open("/proc/%s/cmdline" % p, "rb").read().split(b"\0")[0].decode(errors="replace")
        except (OSError, IndexError):
            continue
        if a0.startswith(MARK) and state(int(p)) not in (None, "Z"):
            out.append((int(p), a0))
    return out


def kill_marked():
    for p, _ in marked_left():
        sig_pid(p, signal.SIGKILL)


def mask(pid, field):
    try:
        for line in open("/proc/%d/status" % pid):
            if line.startswith(field + ":"):
                return int(line.split()[1], 16)
    except (OSError, ValueError):
        pass
    return None


def bit(m, signo):
    return m is not None and bool((m >> (signo - 1)) & 1)


def caught(pid, signo, secs):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        if bit(mask(pid, "SigCgt"), signo) and not bit(mask(pid, "SigBlk"), signo):
            return True
        time.sleep(0.02)
    return False


def fdlink(pid, fd):
    try:
        return os.readlink("/proc/%d/fd/%d" % (pid, fd))
    except OSError:
        return None


def roles(main_pid, gate_name, secs=60):
    """(gate, run supervisor, worker, keeper) of the held gate, verified by structure (parent links + comm)."""
    end = time.monotonic() + secs
    while time.monotonic() < end:
        gs = argv0_pids(gate_name)
        if gs:
            gate = gs[0]
            run = ppid(gate)
            wk = ppid(run) if run else None
            kp = ppid(wk) if wk else None
            if (comm(run) == "fc-run" and comm(wk) == "bash" and comm(kp) == "fc-keeper" and ppid(kp) == main_pid):
                return gate, run, wk, kp
        time.sleep(0.02)
    return None


# ---- stream states of the CALLER (the process that starts baseline_replay.sh) ----
#   (name, stdout, stderr, caller SIGPIPE ignored?, stdin)
#   stdout/stderr: open (read) | dead (reader gone: EPIPE) | closed | stalled (round 9, V4R9-6: a pipe whose reader is
#   ALIVE but never reads, filled to capacity before the tool starts -- every write BLOCKS) | full (/dev/full: ENOSPC)
#   | wrongdir (round 9, V4R9-2: the CALLER passes the fd open in the wrong direction, `1<file` / `2<file`)
#   stdin: null (/dev/null) | closed (`0<&-`) | wrongdir (`0>file`)
STREAMS = [("open", "open", "open", False, "null"), ("dead-out", "dead", "open", False, "null"),
           ("dead-err", "open", "dead", False, "null"),
           ("dead-both", "dead", "dead", False, "null"), ("dead-both-ign", "dead", "dead", True, "null"),
           ("closed-out", "closed", "open", False, "null"), ("closed-err", "open", "closed", False, "null"),
           ("closed-both", "closed", "closed", False, "null"),
           # T048 V4 round 9 (V4R9-6: the members of the stream-state class the round-8 statement omitted)
           ("stalled-out", "stalled", "open", False, "null"), ("stalled-err", "open", "stalled", False, "null"),
           ("full-out", "full", "open", False, "null"), ("full-err", "open", "full", False, "null"),
           ("dead-out-closed-err", "dead", "closed", False, "null"),
           ("closed-in", "open", "open", False, "closed"), ("wrongdir-in", "open", "open", False, "wrongdir"),
           ("wrongdir-out", "wrongdir", "open", False, "null"), ("wrongdir-err", "open", "wrongdir", False, "null")]
SEL_S = os.environ.get("R8_STREAMS", "").split()
STREAMS = [s for s in STREAMS if not SEL_S or s[0] in SEL_S]
# DECLARED SCOPE (§11.4.6, V4R9-6): a STALLED stream blocks whoever writes to it, as it would for any program -- with no
# stop, a replay that has something to write to it (a harness error's BLIND line, a usage error, the
# --determinism-check verdict on stdout, the worker's message about a killed/stopped run supervisor) waits for the
# caller's reader forever; that is the caller's choice, not an exit code. Those cells are NOT run; every cell in which
# a stop reaches the tool, and every cell whose replay writes nothing, IS run: the code must be the table's and no
# supervisor role may block (fc_supervisor.say is bounded).
STALL_SKIP = {"stalled-out": {"det", "herr", "kill-run", "term-run"},
              "stalled-err": {"herr", "usage", "kill-run", "term-run"}}


class Launch:
    """Start argv with the given caller stream state; drain the open pipes (an 'open' stream is READ)."""

    def __init__(self, argv, env, out_state, err_state, pipe_ign, in_state="null"):
        close = []
        if in_state == "closed":
            close.append("0<&-")
        if out_state == "closed":
            close.append("1>&-")
        if err_state == "closed":
            close.append("2>&-")
        if close:
            argv = ["bash", "-c", "exec %s; exec \"$@\"" % " ".join(close), "x"] + argv
        self.err_txt = []
        self.keep = []                      # stalled pipes: the READ end stays open here and is never read
        WD = os.path.join(WORK, "wrongdir.txt")
        if not os.path.exists(WD):
            open(WD, "w").write("not a stream\n")

        def mk(state, is_in=False):
            if state in ("open", "dead"):
                return subprocess.PIPE
            if state == "full":
                return open("/dev/full", "w")
            if state == "wrongdir":
                return open(WD, "w" if is_in else "r")
            if state == "stalled":
                r, w = os.pipe()
                fill = os.open("/proc/self/fd/%d" % w, os.O_WRONLY | os.O_NONBLOCK)   # a SECOND description: the
                try:                                                                  # tool's stays blocking
                    while True:
                        os.write(fill, b"x" * 4096)
                except BlockingIOError:
                    pass
                os.close(fill)
                self.keep += [r, w]
                return w
            return None                     # closed (done by the bash -c prefix) / null on stdin
        stdin = subprocess.DEVNULL if in_state != "wrongdir" else mk("wrongdir", True)
        self.p = subprocess.Popen(argv, env=env, stdin=stdin, stdout=mk(out_state), stderr=mk(err_state),
                                  restore_signals=not pipe_ign)
        for i, fd in enumerate(list(self.keep)):
            if i % 2 == 1:
                os.close(fd)                # our copy of a stalled pipe's write end; the reader stays alive
        self.threads = []
        for stream, st in ((self.p.stdout, out_state), (self.p.stderr, err_state)):
            if stream is None:
                continue
            if st == "dead":
                stream.close()           # the reader is gone before the tool writes anything: every write is EPIPE
            else:
                t = threading.Thread(target=self._drain, args=(stream, stream is self.p.stderr), daemon=True)
                t.start()
                self.threads.append(t)

    def _drain(self, stream, is_err):
        while True:
            b = stream.read(65536)
            if not b:
                break
            if is_err:
                self.err_txt.append(b.decode(errors="replace"))
        stream.close()

    def wait(self, secs):
        try:
            self.p.wait(timeout=secs)
        except subprocess.TimeoutExpired:
            sig_pid(self.p.pid, signal.SIGKILL)
            self.p.wait()
            return None
        for t in self.threads:
            t.join(5)
        for i, fd in enumerate(self.keep):
            if i % 2 == 0:
                try:
                    os.close(fd)
                except OSError:
                    pass
        return self.p.returncode


# ---- scenarios: (name, gate kind, extra args, action, want rc, want report) ----
SCEN = [("ok", "true", [], None, 0, True),
        ("det", "true", ["--determinism-check"], None, 0, True),
        ("herr", "/nonexistent/fc-r8-gate", [], None, 4, True),
        ("usage", None, None, None, 2, False),
        ("stop-INT-main", "hold", [], ("main", signal.SIGINT), 130, False),
        ("stop-TERM-main", "hold", [], ("main", signal.SIGTERM), 143, False),
        ("stop-HUP-main", "hold", [], ("main", signal.SIGHUP), 129, False),
        ("stop-QUIT-main", "hold", [], ("main", signal.SIGQUIT), 131, False),
        ("kill-main", "hold", [], ("main", signal.SIGKILL), -9, False),
        ("kill-keeper", "hold", [], ("keeper", signal.SIGKILL), 137, False),
        ("kill-worker", "hold", [], ("worker", signal.SIGKILL), 137, False),
        ("kill-run", "hold", [], ("run", signal.SIGKILL), 4, False),
        ("term-keeper", "hold", [], ("keeper", signal.SIGTERM), 143, False),
        ("term-worker", "hold", [], ("worker", signal.SIGTERM), 143, False),
        ("term-run", "hold", [], ("run", signal.SIGTERM), 0, True),
        # T048 V4 round 9 (V4R9-6): the other subcommands, and a stop that lands right AFTER the report was written
        ("replay-sample", "SAMPLE", [], None, 0, True),
        ("selfcheck", "SELFCHECK", [], None, 0, True),
        ("freeze", "FREEZE", [], None, 0, True),
        ("stop-after-report", "true", [], ("main", signal.SIGTERM, "after-report"), 0, True)]
SEL_C = os.environ.get("R8_SCENARIOS", "").split()
SCEN = [s for s in SCEN if not SEL_C or s[0] in SEL_C]

ROOT = os.path.join(WORK, "m"); os.makedirs(ROOT)
REPO = os.path.join(ROOT, "repo"); HEAD = mk_repo(REPO)
# round 9: an item commit for replay-sample / freeze (HEAD moves to it; every replay replays HEAD)
open(os.path.join(REPO, "f.txt"), "a").write("item\n")
g("-C", REPO, "commit", "-q", "-am", "ATM-9 r9 matrix item")
HEAD = g("-C", REPO, "rev-parse", "HEAD").stdout.strip()
SAMPLE = os.path.join(ROOT, "sample.json")
open(SAMPLE, "w").write('{"items": [{"item_id": "ATM-9"}]}')
TMP = os.path.join(ROOT, "tmp"); os.makedirs(TMP)
LOCKS = os.path.join(ROOT, "locks"); os.makedirs(LOCKS)
ENV = dict(os.environ, TMPDIR=TMP, FC_REPLAY_LOCK_DIR=LOCKS, FC_BR_STOP_GRACE_S="1")
ENV.pop("FC_OUT", None)
GATE_NAME = MARK + "gate"
HOLD = os.path.join(ROOT, "hold.sh")
open(HOLD, "w").write('#!/bin/bash\nexec -a %s sleep 600\n' % GATE_NAME)
os.chmod(HOLD, 0o755)


def settle(secs=30):
    """after a cell: nothing marked left, the temp dir empty, no replay worktree listed (the keeper may still be
    cleaning up after a SIGKILL of main)."""
    end = time.monotonic() + secs
    while time.monotonic() < end:
        wts = [l for l in g("-C", REPO, "worktree", "list", "--porcelain").stdout.splitlines()
               if l.startswith("worktree ") and "/replay." in l]
        if not marked_left() and not os.listdir(TMP) and not wts:
            return True, ""
        time.sleep(0.1)
    return False, "left=%r tmp=%r worktrees=%r" % (marked_left(), os.listdir(TMP), wts)


if want("R8MATRIX"):
    skipped = []
    for sname, so, se, ign, si in STREAMS:
        for cname, gate, extra, action, want_rc, want_rep in SCEN:
            tag = "[R8MATRIX] %s x %s" % (cname, sname)
            if cname in STALL_SKIP.get(sname, ()):
                skipped.append("%s x %s" % (cname, sname))
                continue
            out = os.path.join(ROOT, "out.json")
            if os.path.exists(out):
                os.unlink(out)
            common = ["--repo-root", REPO, "--worktree-root", os.path.join(ROOT, "wt"), "--min-free-kb", "0",
                      "--min-free-kb-objects", "0", "--gate-cmd", "true", "--cold-runs", "1", "--warm-runs", "0",
                      "--out", out]
            if gate is None:
                argv = ["bash", SCRIPT, "replay", "--bogus-r8"]
            elif gate == "SAMPLE":
                argv = ["bash", SCRIPT, "replay-sample", "--sample", SAMPLE] + common
            elif gate == "SELFCHECK":
                argv = ["bash", SCRIPT, "selfcheck", "--out", out]
            elif gate == "FREEZE":
                argv = ["bash", SCRIPT, "freeze", "--item", "ATM-9", "--repo-root", REPO, "--out", out]
            else:
                argv = ["bash", SCRIPT, "replay", "--commit", HEAD, "--repo-root", REPO, "--worktree-root",
                        os.path.join(ROOT, "wt"), "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd",
                        HOLD if gate == "hold" else gate, "--cold-runs", "1", "--warm-runs", "0", "--out", out] + extra
            argv = [RSCRIPT if a == SCRIPT else a for a in argv]
            fdlog = os.path.join(ROOT, "fdlog")
            if os.path.exists(fdlog):
                os.unlink(fdlog)
            L = Launch(argv, dict(ENV, R8_FDLOG=fdlog), so, se, ign, si)
            needle = ""
            if action and len(action) == 3:
                # stop right AFTER the report appeared (V4R9-6): whether it lands before or after the worker / keeper
                # / main exit, the report exists, so the code is the report's (fc_supervisor.decide_code)
                end = time.monotonic() + 60
                while time.monotonic() < end and not os.path.exists(out) and L.p.poll() is None:
                    time.sleep(0.002)
                sig_pid(L.p.pid, action[1])
            elif action:
                who, signo = action
                r = roles(L.p.pid, GATE_NAME)
                if r is None:
                    rc = L.wait(60)
                    kill_marked()
                    bad("%s: setup: the held gate / its supervisor chain never appeared (rc=%s)" % (tag, rc))
                    settle()
                    continue
                gate_pid, run, wk, kp = r
                # control needle for the stream state: main's own fd 1/2 as the tool sees them
                links = (fdlink(L.p.pid, 0) or "", fdlink(L.p.pid, 1) or "", fdlink(L.p.pid, 2) or "")
                EXP = {"closed": "/dev/null", "wrongdir": "/dev/null", "full": "/dev/full", "null": "/dev/null"}
                exp = tuple(EXP.get(s, "pipe:") for s in (si, so, se))
                if not all(l.startswith(e) for l, e in zip(links, exp)):
                    needle = " NEEDLE main fds 0/1/2 %r != %r" % (links, exp)
                target = {"main": L.p.pid, "keeper": kp, "worker": wk, "run": run}[who]
                if signo != signal.SIGKILL:
                    caught(target, signo, 5) if who != "worker" else time.sleep(0.2)
                sig_pid(target, signo)
            rc = L.wait(180)
            settled, why = settle(40 if action and action[0] == "main" and action[1] == signal.SIGKILL else 30)

            kill_marked()
            # V4R10-6: the fd-direction needle of every role of this cell (see RREP above)
            recs = []
            try:
                recs = [l.split("\t") for l in open(fdlog).read().splitlines() if l]
            except OSError:
                pass
            EXPF = {"closed": "/dev/null", "wrongdir": "/dev/null", "full": "/dev/full", "null": "/dev/null"}
            expf = tuple(EXPF.get(s_, "pipe:") for s_ in (si, so, se))
            if PROBE_OK:
                needle += " PROBE not injected: %s" % PROBE_OK
            elif cname in ("usage", "freeze"):
                if recs:
                    needle += " FDPROBE %s starts no supervisor, yet the probe recorded %r" % (cname, recs)
            else:
                rolesseen = {r_[0] for r_ in recs}
                wrong = [r_ for r_ in recs if len(r_) != 4 or not all(x.startswith(e) for x, e in zip(r_[1:], expf))]
                if not {"main", "keeper", "worker"} <= rolesseen:
                    needle += " FDPROBE control needle: roles recorded %r (want main, keeper, worker)" % sorted(rolesseen)
                elif wrong:
                    needle += " FDPROBE fds 0/1/2 %r != %r" % (wrong, expf)
            rep = os.path.exists(out)
            err = "".join(L.err_txt)
            tb = "Traceback" in err
            if needle:
                bad("%s:%s" % (tag, needle))
            elif rc == want_rc and rep == want_rep and settled and not tb:
                ok("%s: rc %s, report %s, quiescent, fd needle %s" % (tag, rc, "written" if rep else "absent",
                                                                     "none (unsupervised)" if cname in ("usage", "freeze")
                                                                     else "main/keeper/worker %s" % (expf,)))
            else:
                bad("%s: rc=%s (want %s) report=%s (want %s) quiescent=%s %s traceback=%s %s" %
                    (tag, rc, want_rc, rep, want_rep, settled, why, tb, err.strip()[-160:]))

    if skipped:
        ok("[R8MATRIX-SCOPE] %d cell(s) NOT run, declared scope (a stalled stream with no stop blocks its writer, as for "
           "any program): %s" % (len(skipped), ", ".join(skipped)))

# ---- [R8RUN] the run role invoked directly with each stream state: its own messages (a leftover stopped, a stop)
# go to stderr; the code is the command's / the stop's / the timeout's whatever the stream state.
RUNSTREAMS = [("open", "open", "open"), ("dead-both", "dead", "dead"), ("closed-both", "closed", "closed")]
if want("R8RUN"):
    for sname, so, se in RUNSTREAMS:
        for cname, cmd, timeout, action, want_rc, want_mk in (
                ("exit3-leftover", ["bash", "-c", '( exec -a "$0" sleep 600 & ); exit 3', MARK + "runleft"], "30",
                 None, 3, "exited"),
                ("stop-TERM", ["bash", "-c", 'exec -a "$0" sleep 600', MARK + "runhold"], "30",
                 signal.SIGTERM, 143, "stopped"),
                ("timeout", ["bash", "-c", 'exec -a "$0" sleep 600', MARK + "runtmo"], "1", None, 124, "timed_out")):
            tag = "[R8RUN] %s x %s" % (cname, sname)
            d = os.path.join(ROOT, "run-%s-%s" % (cname, sname)); os.makedirs(d)
            mk = os.path.join(d, "marker")
            L = Launch(["python3", "-I", "-S", SUP, "run", "--timeout", timeout, "--kill-after", "1", "--grace", "1",
                        "--marker", mk, "--cwd", d, "--"] + cmd, ENV, so, se, False)
            if action:
                up = False
                end = time.monotonic() + 10
                while time.monotonic() < end and not up:
                    up = bool(argv0_pids(MARK + "runhold")) and caught(L.p.pid, action, 1)
                sig_pid(L.p.pid, action)
            rc = L.wait(60)
            time.sleep(0.2)
            left = marked_left()
            kill_marked()
            mkv = open(mk).read() if os.path.exists(mk) else ""
            err = "".join(L.err_txt)
            if rc == want_rc and mkv == want_mk and not left and "Traceback" not in err:
                ok("%s: rc %d, marker %s, nothing left" % (tag, rc, mkv))
            else:
                bad("%s: rc=%s (want %d) marker=%r (want %s) left=%r traceback=%s" %
                    (tag, rc, want_rc, mkv, want_mk, left, "Traceback" in err))

# ---- [R8RUNLOG] proof of unreachability: inside the tool a run supervisor's stdout AND stderr are the run's log file,
# never the caller's streams (so the caller-stream axis does not reach the run role through the tool). Static, with a
# positive and a negative control needle on the same text (§11.4.273).
if want("R8RUNLOG"):
    src = open(SCRIPT).read()
    inv = [l for l in src.splitlines() if '"$_FC_SUPERVISOR" run ' in l]
    nxt = []
    lines = src.splitlines()
    for i, l in enumerate(lines):
        if '"$_FC_SUPERVISOR" run ' in l:
            nxt.append(lines[i + 1] if i + 1 < len(lines) else "")
    needle_pos = '"$_FC_SUPERVISOR" main' in src
    needle_neg = '"$_FC_SUPERVISOR" run-r8-no-such' not in src
    if len(inv) == 1 and nxt and ' >"$log" 2>&1 </dev/null &' in nxt[0] and needle_pos and needle_neg:
        ok("[R8RUNLOG] the ONE run-supervisor invocation in the tool redirects stdout+stderr to the run's log (and "
           "stdin from /dev/null): the caller's streams never reach the run role through the tool")
    else:
        bad("[R8RUNLOG] run invocations=%d next line=%r needles=%s/%s" % (len(inv), nxt[:1], needle_pos, needle_neg))

# ---- [R8SIGPIPE] census: SIGPIPE ignored in main, keeper and worker (a write to a dead reader is EPIPE, never death);
# the gate itself starts with SIGPIPE at its default action (the tool does not change a gate's dispositions).
if want("R8SIGPIPE"):
    out = os.path.join(ROOT, "out-sp.json")
    L = Launch(["bash", SCRIPT, "replay", "--commit", HEAD, "--repo-root", REPO, "--worktree-root",
                os.path.join(ROOT, "wt"), "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd", HOLD,
                "--cold-runs", "1", "--warm-runs", "0", "--out", out], ENV, "open", "open", False)
    r = roles(L.p.pid, GATE_NAME)
    res = {}
    if r:
        gate_pid, run, wk, kp = r
        res = {n: bit(mask(p, "SigIgn"), signal.SIGPIPE) for n, p in
               (("main", L.p.pid), ("keeper", kp), ("worker", wk), ("gate", gate_pid))}
        sig_pid(L.p.pid, signal.SIGTERM)
    L.wait(60)
    settle()
    kill_marked()
    if not r:
        bad("[R8SIGPIPE] control needle: the held gate and its supervisor chain were never found")
    elif res == {"main": True, "keeper": True, "worker": True, "gate": False}:
        ok("[R8SIGPIPE] SIGPIPE ignored in main, keeper and worker; the gate starts with SIGPIPE at SIG_DFL")
    else:
        bad("[R8SIGPIPE] SIGPIPE ignored per role: %r (want main/keeper/worker True, gate False)" % res)

# ---- [R8FDS] main started with fds 0/1/2 closed: its worker gets /dev/null on all three.
# the probe reads ITS OWN fds before it opens the result file (a redirect of the loop itself would BE fd 1)
PROBE = 'a=$(readlink /proc/$$/fd/0); b=$(readlink /proc/$$/fd/1); c=$(readlink /proc/$$/fd/2); printf "0=%s\\n1=%s\\n2=%s\\n" "$a" "$b" "$c" >"$0"'
if want("R8FDS"):
    d = os.path.join(ROOT, "fds"); os.makedirs(os.path.join(d, "tmp"))
    rep = os.path.join(d, "links")
    p = subprocess.run(["bash", "-c", 'exec 0<&- 1>&- 2>&-; exec "$@"', "x", "python3", "-I", "-S", SUP, "main",
                        "--tmp-parent", os.path.join(d, "tmp"), "--grace", "1", "--", "bash", "-c",
                        PROBE, rep],
                       timeout=60)
    got = open(rep).read().split() if os.path.exists(rep) else []
    # control needle: the same probe with the fds OPEN reports something other than /dev/null for at least one
    p2 = subprocess.run(["python3", "-I", "-S", SUP, "main", "--tmp-parent", os.path.join(d, "tmp"), "--grace", "1",
                         "--", "bash", "-c", PROBE,
                         rep + ".open"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        timeout=60)
    got2 = open(rep + ".open").read().split() if os.path.exists(rep + ".open") else []
    if not any("pipe:" in x for x in got2):
        bad("[R8FDS] control needle: with open fds the probe did not see the caller's pipes (%r)" % got2)
    elif p.returncode == 0 and got == ["0=/dev/null", "1=/dev/null", "2=/dev/null"] and not os.listdir(os.path.join(d, "tmp")):
        ok("[R8FDS] fds 0/1/2 closed by the caller: the worker starts with /dev/null on all three (needle: open fds are "
           "seen as the caller's pipes), rc 0, temp dir gone")
    else:
        bad("[R8FDS] closed fds 0/1/2: rc=%s worker fds=%r temp=%r" % (p.returncode, got, os.listdir(os.path.join(d, "tmp"))))

print("----")
print("SUMMARY pass=%d fail=%d" % (N["ok"], N["bad"]))
sys.exit(0 if N["bad"] == 0 else 1)
PY
exit $?
