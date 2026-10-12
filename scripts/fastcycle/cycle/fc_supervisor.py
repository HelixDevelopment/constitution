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
                  ONCE -- the SAME signal M received: K handles exactly the
                  stop signals M handles, so it is never one K ignores (round
                  6, F1) -- later ones are ignored, so a second signal can never
                  cut a teardown short, and M exits with K's code after K has
                  finished (128+signal when the stop reached the work).
                  OWNERSHIP (round 7, N1): M is the parent of what the CALLER
                  started before exec (a background job, a `> >(tee log)`
                  logger) and adopts their orphans. It records its children at
                  entry (pid + start time, before becoming a subreaper) and
                  signals ONLY processes it owns: the keeper, the keeper's
                  session, their descendants (_main_owner). Anything else it
                  adopted is reported, never signalled.
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
                  PDEATHSIG=SIGUSR2 (round 7: when W dies, run stops its OWN tree
                  before it exits, so a gate's setsid daemon is never orphaned
                  past it). Runs the command with a timeout, then stops
                  every process the command left behind before it returns -- a
                  gate's background daemon or a hook's `sleep &` never survives
                  into the next run. BOUNDARY (round 6, F2): a run supervisor
                  that is itself SIGKILLed (or crashes) cannot do this -- what
                  its command left running is re-parented to K. It then records
                  no outcome, and the worker treats a missing outcome as fatal:
                  it aborts the whole replay at once (baseline_replay.sh
                  _fc_run_child, exit 4, no report), so K stops those processes
                  before any further run and before the worktree is removed.
                  Writes the run's outcome to a marker file
                  (exited | timed_out | cd_failed | exec_failed | stopped -- the run
                  supervisor itself got a stop signal | status_lost -- the child's
                  status was reaped elsewhere | probe_failed -- see "Start-up
                  control needle"), and with --timing the instant the command
                  itself exited plus the time spent stopping its leftovers (the
                  caller's duration ends at the command's exit, round 5 F5).

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

Dispositions: of the signals the caller had IGNORED when baseline_replay.sh
started (passed as --entry-sigign, the SigIgn mask of /proc/<pid>/status), the
STOP signals (HUP/INT/QUIT/TERM) stay ignored in every role and every child --
`nohup baseline_replay.sh ...` keeps working as nohup means. Every other
disposition is reset to SIG_DFL in each child (undoing Python's own
SIGPIPE/SIGXFSZ ignore, bash's INT/QUIT ignore for background jobs, and a
caller's ignored SIGPIPE / SIGTTIN / SIGTTOU / SIGCHLD).

Inherited process state (T048 V4 round 5, the §11.4.276(C) class sweep;
tests/test_fc_supervisor_v4r5_findings.sh CENSUS rows, each control-needled):
  - SIGCHLD ignored by the caller crosses exec and makes the kernel auto-reap
    every child: waitpid never returns it, the pidfd stays readable and every
    wait loop spun at 100% CPU (F1). CLOSED: every role resets SIGCHLD to
    SIG_DFL first (reset_inherited), children never inherit it ignored, and a
    readable pidfd whose status cannot be collected is retried with bounded
    back-off and then reported `status_lost` -- never a busy loop.
  - a blocked signal mask: CLOSED -- every role runs with an empty mask (a
    caller-blocked TERM can no longer make the tool unstoppable by TERM).
  - SIGPIPE / SIGTTIN / SIGTTOU ignored: CLOSED by the reset above. (TTIN/TTOU
    cannot even be generated for a gate: it runs in the keeper's own session,
    without a controlling terminal.)
  - HUP/INT/QUIT/TERM ignored: KEPT on purpose (nohup).
  - umask: an umask masking the OWNER's bits makes every file the tool creates
    unusable to it (and a checkout undeletable): CLOSED -- main refuses to
    start (exit 4 BLIND) before creating anything.
  - inherited file descriptors: SCOPED OUT of closing (a gate may legitimately
    use what its caller passed, e.g. a make jobserver); bounded -- a descendant
    holding one is stopped before the tool (or one run) returns, so a caller
    reading a pipe it passed is never left hanging.
  - the environment: SCOPED OUT (passed through on purpose: the gate runs in the
    caller's environment); the hand-off variables are guarded -- a stale
    FC_BR_SUPERVISED=1 is refused by baseline_replay.sh, FC_BR_NEST_DEPTH is
    bounded (MAX_NEST), FC_OUT is consumed and removed.
  - rlimits, an inherited interval timer: SCOPED OUT (an expiring timer ends
    the main pid by its default action; the keeper then tears the tree down as
    for any other death of main).

Start-up control needle (round 5, F3): every stop walks
/proc/<pid>/task/<tid>/children (CONFIG_PROC_CHILDREN). Without it every walk is
EMPTY -- a supervisor that believes there is nothing to stop. main and run
therefore start one child first and require it to appear in that list; if it
does not, main exits 4 (BLIND) and run exits 125 (marker probe_failed) before
anything else is started.

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

Progress (round 7, N4): the keeper's teardown can take minutes (removing a
large checkout). It beats on a pipe to M while it makes progress (HB_FD) and M
extends its keeper deadline while beats arrive, never past LEDGER_CAP_S; a
keeper that stops beating (wedged, SIGSTOPped) is still killed at the base
deadline. The worker keeps its run-log ledger entries; whether the report was
written is decided from DURABLE state (round 8, V4R8-2: the report-pending marker
plus the report on disk, see report_verified), never from an exit status. Once
the report exists every supervisor process keeps the replay's code, whatever
stopped or killed what afterwards; before it exists a stop leaves the log
directories to be marked INTERRUPTED. Round 9 (V4R9-1, STRUCTURAL): the marker
lives in a STATE directory next to the temp directory (the keeper deletes the
temp directory before it exits; round 8's marker died with it, and a keeper
killed in that window turned a finished replay into 137). Only the final decider
removes the state directory (main after its decision; the keeper only when main
is provably gone; a later main only when the owner in the directory's NAME is
provably dead), and every role derives its code with ONE pure function,
decide_code(report_verified(state dir), termination cause) -- see "STATE
DIRECTORY" below and tests/test_fc_supervisor_v4r9_shutdown_windows.sh, which
kills / stops / wedges each role at EVERY statement of its shutdown sequence.

Caller streams (round 8, V4R8-1 -- CLASS 2, 2nd structural attempt): the state of
the caller's stdout/stderr (open, a pipe nobody reads, closed) never changes an
exit code or whether the report is written. main re-opens a closed fd 0/1/2 on
/dev/null before it opens anything (_repair_std_fds); say/_flush catch every
exception class (a closed stream is None in Python); the worker ignores SIGPIPE
(baseline_replay.sh: a write to a dead reader is an EPIPE error, never death by
SIGPIPE) and writes the report before it prints anything; a run supervisor's
streams are always the run's log file (baseline_replay.sh _fc_run_child).
Round 9 (V4R9-1 (b), V4R9-6): a stream whose reader is ALIVE but NOT READING
blocks a writer forever; every supervisor message goes through say(), which
writes straight to fd 2 with select() and gives up after SAY_BUDGET_S, so no
supervisor role can block on the caller's stream (a /dev/full stream: ENOSPC,
dropped). The worker (bash) and a gate can still block on it like any program
when there is no stop -- the caller's choice (declared scope in the matrix).

HONEST BOUNDARY (§11.4.6): main cannot attribute a process that left the
keeper's session (setsid) AND lost every owned ancestor before main's walk saw
it -- since round 7 that takes a run supervisor AND the keeper dying (or K
dying while W itself has a setsid'd direct child); such a process is reported by
main, not signalled. If M AND K are both SIGKILLed at the same moment,
nothing is left to process the ledger: W and the gate's own process die through
the PDEATHSIG chain (no further scheduled run starts); a live run supervisor gets
its parent-death SIGUSR2 and stops what its gate started before it exits (round
7), but anything left directly under K or W is re-parented to init, and the
worktree / temp directory stay behind. Only kernel containment (a cgroup, e.g. `systemd-run --user
--scope`, available on the reference host but not on every host this generic
tool runs on) would close that; it is not required by this module. Processes
started on the tool's behalf by OTHER daemons (D-Bus activation, an adb server
that already runs) are not descendants and are not stopped; a daemon the gate
itself starts IS a descendant and IS stopped -- the tool leaves the host
quiescent (§11.4.14).

Ledger: W registers every worktree (repo root + path) and every run-log
directory as one file `ledger.<kind>.*` in the private temp directory BEFORE
creating it, and deletes the entry once it removed the worktree / wrote the
report. A teardown processes whatever entries remain: for a worktree (only a
path whose last component starts with `replay.`) `git worktree unlock` +
`remove -f -f` + prune + the directory itself -- a `git worktree add` killed
part-way leaves the worktree `locked: initializing`, which `remove --force`
refuses and prune skips (round 5, F2) -- and "removed" is reported ONLY after
`git worktree list --porcelain` no longer names it and the directory is gone
(otherwise the failure is reported with the manual commands); an INTERRUPTED
file for a log directory that no report will ever reference (V4R3-14); and for
a `pend` entry -- written before `mktemp -d` creates a directory that is not
registered yet (round 5, F9) -- the NEW, EMPTY directories under its parent
with its name prefix are removed (rmdir only, never content).

Usage (internal; called by baseline_replay.sh, not by people):
  fc_supervisor.py main --tmp-parent DIR --entry-sigign HEX [--grace S]
                   [--lock FILE]... [--lock-dir DIR --lock-fs PATH...] -- CMD...
  fc_supervisor.py run --timeout S --marker FILE --cwd DIR --entry-sigign HEX
                   [--grace S] [--timing FILE] -- CMD...
Exit codes: main -- see main_exit_code, THE EXIT TABLE (round 7, CLASS 2): the
worker's exit code, or 128+N when the tool was stopped by signal N (sent to M, K
or W) BEFORE the work finished (no report written). A stop -- or a SIGKILL of the
worker or keeper -- that lands only after the report was written (verified on
disk, report_verified) does not change that code (round 6 F8, round 7 N3, round 8
V4R8-2); 128+N is also returned when M had to
kill K at its deadline after a stop. 4 when a lock is held, the umask masks the
owner's bits, the start-up control needle failed, the keeper's status was lost,
the keeper failed internally, a code outside {0..4, 128+N} came back, or another
supervisor step failed (BLIND). The state of the caller's stdout/stderr (open,
broken pipe, closed) never changes a code (round 7 N2, round 8 V4R8-1; the
one table is tests/test_fc_supervisor_v4r8_stream_matrix.sh). A run supervisor whose worker died stops its tree
and exits 137 (marker stopped). run -- the command's exit code
(128+N if a signal killed it), 124 on timeout (137 if it had to be KILLed),
128+N when the run supervisor itself was stopped by signal N (marker stopped),
125 on an internal error, a lost status (status_lost) or a failed control needle
(probe_failed).
"""
import _signal as _early_sig   # builtin C module: installing the handler costs no Python-level import (N6)

_EARLY = []                   # a SIGINT received before Stop exists (moved into Stop.sig below)


def _early_record(signum, _frame):
    if not _EARLY:
        _EARLY.append(signum)


if __name__ == "__main__" and _early_sig.getsignal(_early_sig.SIGINT) is not _early_sig.SIG_IGN:
    # the first statement that can act: until here a SIGINT is Python's default handler (KeyboardInterrupt). Measured
    # (round 7 sweep, 40 random start-up INTs): with the handler installed after `import signal` (which imports enum)
    # 3 of 40 runs still printed a KeyboardInterrupt traceback from inside that import.
    _early_sig.signal(_early_sig.SIGINT, _early_record)

import os                     # noqa: E402
import signal                 # noqa: E402


class Stop:
    sig = 0
    target_fd = None     # M: K's pidfd (forward target)
    run_parent = None    # run: the pid of the worker that started this run supervisor
    parent_gone = False  # run: the parent-death signal arrived and the parent really is gone


def _early_stop(signum, _frame):
    """T048 V4 round 7, N6: until a role installs its own stop handlers, Python's DEFAULT SIGINT handler turns a stop
    into KeyboardInterrupt wherever the interpreter happens to be (round 6: inside cmd_main -> "supervisor failed"
    -> 4; inside `import site` -> "Fatal Python error" -> 1). Installed as the very first statement of the script, it
    only RECORDS the stop; the role then acts on it exactly like a stop received later (main forwards it to the
    keeper once the keeper exists, run stops before starting its command). TERM/HUP/QUIT need no early handler: their
    default action ends the process BY the signal (a shell sees 128+N) and nothing has been created yet."""
    if not Stop.sig:
        Stop.sig = signum


if __name__ == "__main__" and signal.getsignal(signal.SIGINT) is not signal.SIG_IGN:
    signal.signal(signal.SIGINT, _early_stop)
if _EARLY and not Stop.sig:
    Stop.sig = _EARLY[0]

import ctypes            # noqa: E402 -- after the early SIGINT handler on purpose (N6)
import select            # noqa: E402
import shutil            # noqa: E402
import stat as _st       # noqa: E402
import subprocess        # noqa: E402
import sys               # noqa: E402
import tempfile          # noqa: E402
import time              # noqa: E402

PR_SET_PDEATHSIG = 1
PR_SET_NAME = 15
PR_SET_CHILD_SUBREAPER = 36
STOP_SIGS = (signal.SIGHUP, signal.SIGINT, signal.SIGQUIT, signal.SIGTERM)
KILL_WAIT_S = 5.0          # after the KILL step, how long to wait for the tree to empty
KEEPER_SLACK_S = 30.0      # main: extra time the keeper gets to finish a stop before main kills it (RM-B)
LOST_TRIES = 12            # bounded retries (exponential back-off, ~2 s total) before a status is "lost"
# The only signals whose IGNORED disposition at entry is kept for every child: the stop signals
# (nohup / an interactive caller's QUIT). Every other inherited disposition -- SIGCHLD (an ignored
# SIGCHLD makes the kernel auto-reap: waitpid then never returns the child), SIGPIPE, SIGTTIN/SIGTTOU,
# ... -- is reset to SIG_DFL (T048 V4 round 5, F1 + the §11.4.276(C) class sweep).
KEEP_IGNORED = STOP_SIGS
MAX_NEST = 4               # supervisors nested inside supervisors (a gate that is itself an FC tool)
REAPED = {}                # pid -> wait status, filled by reap()
# T048 V4 round 7, N4: the keeper's teardown (stop + ledger) can take minutes -- `git worktree remove` of a large
# checkout -- so main no longer kills it at a fixed deadline. The keeper writes a byte to HB_FD whenever it makes
# progress (each stop-loop pass, each ledger entry, every second while a bounded git call runs, every 500 removed
# directory entries); main waits while a beat arrived within HB_WINDOW_S, but never longer than LEDGER_CAP_S past
# its base deadline (grace + KILL_WAIT_S + KEEPER_SLACK_S): the wait is extended by progress, and still bounded.
HB_FD = None               # keeper: write end of the progress pipe (None in every other role)
HB_WINDOW_S = 15.0         # main: a keeper that beat within this window is making progress
LEDGER_CAP_S = 3600.0      # main: the overall bound on that extension
GIT_TIMEOUT_S = 120.0      # every git call of the ledger work is bounded by this
DONE = {}                  # "code": the replay's exit code once its report EXISTS (read_report, V4R8-2)
_MAIN_TMP = [None]         # main: the temp directory while no keeper owns it yet (removed on an exception, V4R8-1)
# T048 V4 round 7, N1 (CLASS 1): which descendants a stop may signal. None = every descendant (keeper, run: every
# process below them was started by this supervisor). main sets a predicate (see cmd_main, OWNERSHIP).
OWNER = None
# The documented exit codes of `main` (baseline_replay.sh's header): 0..4 and 128+N. main_exit_code maps anything else
# (a keeper's or worker's internal code: 70, 125, 127 ...) to 4 BLIND -- T048 V4 round 7, N5 (CLASS 2).
DOCUMENTED = frozenset(range(0, 5)) | frozenset(range(129, 129 + 64))

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
    """One line to stderr, never raising AND never blocking past SAY_BUDGET_S (T048 V4 round 8 V4R8-1; round 9 V4R9-1/6
    CLASS 2): a stderr that is a broken pipe, CLOSED (None in Python / EBADF), a write-error sink (/dev/full: ENOSPC)
    or -- round 9 -- a pipe whose reader is ALIVE but not reading (a blocking write would wait forever) may never change
    the exit code nor stall a supervisor role (the keeper's teardown, main's exit). Written straight to fd 2 by
    _write_bounded, not through sys.stderr's buffer (a buffered write would be flushed -- and block -- later)."""
    if sys.stderr is None:
        return
    try:
        data = ("baseline_replay: %s\n" % msg).encode("utf-8", "replace")
    except Exception:  # noqa: BLE001 -- an unprintable message is dropped, never an outcome
        return
    _write_bounded(2, data)


SAY_BUDGET_S = 2.0         # the longest one say() may wait for a caller's stream (V4R9-1 (b), V4R9-6)
SAY_CHUNK = 512            # <= POSIX PIPE_BUF minimum: a write this small to a pipe that select() reports writable
                           # never blocks (Linux: a pipe is writable while one of its buffer slots is free)


def _write_bounded(fd, data, budget=None):
    """Write data to fd: select() for writability, then os.write of at most SAY_CHUNK bytes, until written or the
    budget is spent; never raises, never blocks past the budget (whatever is left is dropped). BOUNDARY (§11.4.6):
    select() is what bounds the wait -- a stream select() reports writable but whose write still blocks (a blocking
    stream SOCKET with less room than the chunk) can block one write; pipes, ttys, regular files and /dev/* cannot."""
    end = time.monotonic() + (SAY_BUDGET_S if budget is None else budget)
    while data:
        left = end - time.monotonic()
        if left <= 0:
            return
        try:
            _, wr, _ = select.select([], [fd], [], left)
        except InterruptedError:
            continue
        except Exception:  # noqa: BLE001 -- a closed / invalid fd: nothing can be written
            return
        if not wr:
            return
        try:
            n = os.write(fd, data[:SAY_CHUNK])
        except InterruptedError:
            continue
        except Exception:  # noqa: BLE001 -- the state of the caller's stream never changes an outcome
            # (EPIPE, ENOSPC, EIO, EAGAIN: the rest is dropped)
            return
        data = data[n:]


def _flush():
    """Flush stdout + stderr, never raising (T048 V4 round 7, N2; round 8, V4R8-1): a caller's logger that went away,
    or a closed stream, leaves unwritten bytes in the buffer; an unguarded flush then raised BrokenPipeError and the
    catch-all turned the real outcome into 4. A stream that was CLOSED when Python started is None: `None.flush()` is an
    AttributeError, which round 7's (OSError, ValueError) did not catch -- `selfcheck ... >&-` exited 1 with a traceback
    and leaked its temp directory, and the same raise in the keeper's `finally` would have dropped the keeper into
    main's code path. Every exception class is caught; the state of the caller's streams never changes an exit code."""
    for stream in (sys.stdout, sys.stderr):
        if stream is None:
            continue
        try:
            stream.flush()
        except Exception:  # noqa: BLE001
            pass


def _repair_std_fds():
    """T048 V4 round 8 (V4R8-1): a caller may start the tool with stdin/stdout/stderr CLOSED (`... >&-`). Every file
    this process (and every child it starts) opens would then land on fd 0/1/2 -- a lock file or a temp file that a
    later write to "stderr" corrupts, a child whose own stderr IS one of its data files. Each closed standard fd is
    re-opened on /dev/null (inheritable, so the worker and its children start with all three open), before anything
    else is opened. A closed stream thus behaves as a stream nobody reads: the exit code does not depend on it.
    A standard fd that is open in the WRONG direction counts as closed (found by this round's own matrix, [R8MATRIX]
    x closed-err: `bash baseline_replay.sh ... 2>&-` -- bash opens its SCRIPT on the lowest free fd, 2, dups it to 255
    and leaves fd 2 open, read-only and inheritable, so main, keeper and worker ran with "stderr" = the script file).
    fd 0 must be readable, fds 1/2 writable; otherwise /dev/null is put in their place (a write could never have
    succeeded there, so nothing the caller could see changes)."""
    import fcntl
    for fd in (0, 1, 2):
        try:
            mode = fcntl.fcntl(fd, fcntl.F_GETFL) & os.O_ACCMODE
            if (mode != os.O_WRONLY) if fd == 0 else (mode != os.O_RDONLY):
                continue
        except OSError:
            pass
        try:
            nfd = os.open(os.devnull, os.O_RDWR)
        except OSError:
            continue
        try:
            if nfd != fd:
                os.dup2(nfd, fd)          # dup2 makes the new fd inheritable
                os.close(nfd)
            else:
                os.set_inheritable(fd, True)
        except OSError:
            pass


def _exit_main(code):
    """THE exit of the main role: every path ends here (T048 V4 round 7, CLASS 2). A code outside the documented set
    is reported and becomes 4 BLIND; the streams are flushed without ever raising; then os._exit (no interpreter
    shutdown that could fail on a broken stream and pick its own status, e.g. 120)."""
    if not isinstance(code, int) or code not in DOCUMENTED:
        say("supervisor: internal exit code %r is not a documented exit code -- reported as 4 (BLIND)" % (code,))
        code = 4
    _flush()
    os._exit(code)


def _beat():
    """keeper: tell main the teardown is making progress (non-blocking; a full pipe or a gone main is ignored)."""
    if HB_FD is None:
        return
    try:
        os.write(HB_FD, b".")
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


def reap_target(pid):
    """Called once the pidfd of `pid` reported readable (the process has exited). Collects its
    status into REAPED and returns "ok", or "lost" when the status can no longer be collected --
    waitpid reports no such child (it was reaped elsewhere: e.g. an inherited SIGCHLD=SIG_IGN makes
    the kernel auto-reap). Never a busy loop: a readable pidfd whose status is not yet waitable is
    retried LOST_TRIES times with exponential back-off, then reported lost (T048 V4 round 5, F1)."""
    reap()
    if pid in REAPED:
        return "ok"
    delay = 0.005
    for _ in range(LOST_TRIES):
        try:
            p, st = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return "lost"
        except InterruptedError:
            continue
        if p == pid:
            REAPED[pid] = st
            return "ok"
        time.sleep(delay)
        delay = min(0.5, delay * 2)
    return "lost"


def reset_inherited():
    """Undo the inherited process state that would break a supervisor role (the §11.4.276(C) class
    sweep, T048 V4 round 5): SIGCHLD back to SIG_DFL (an ignored SIGCHLD crosses exec and makes
    waitpid never return a child -- F1) and an empty signal mask (a caller-blocked TERM would make the
    tool unstoppable by TERM). The stop handlers are installed afterwards by the role itself."""
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
    signal.pthread_sigmask(signal.SIG_SETMASK, [])


def children_probe():
    """Control needle (§11.4.273, T048 V4 round 5 F3): the whole stop mechanism walks
    /proc/<pid>/task/<tid>/children (CONFIG_PROC_CHILDREN). A kernel without it -- or any path or
    permission problem -- makes every walk come back EMPTY, i.e. a supervisor that believes there is
    nothing left to stop. Start one child, require it to appear in that list, then end it."""
    r, w = os.pipe()
    pid = os.fork()
    if pid == 0:
        try:
            os.close(w)
            os.read(r, 1)      # EOF when the parent closes its end (or dies)
        finally:
            os._exit(0)
    os.close(r)
    seen = False
    try:
        end = time.monotonic() + 2.0
        while time.monotonic() < end:
            if pid in _children(os.getpid()):
                seen = True
                break
            time.sleep(0.01)
    finally:
        os.close(w)
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
    return seen


BLIND_CHILDREN = ("BLIND: a child this supervisor just started does not appear in "
                  "/proc/<pid>/task/<tid>/children (kernel without CONFIG_PROC_CHILDREN, or /proc unreadable) "
                  "-- every process-tree walk would come back empty and nothing could be stopped; refusing to run")


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


def _ident(pid):
    """(session id, start time) from /proc/<pid>/stat, or None (the fields after the LAST ') ', as _stat_fields)."""
    try:
        with open("/proc/%d/stat" % pid) as fh:
            st = fh.read()
        f = st[st.rindex(") ") + 2:].split()
        return int(f[3]), int(f[19])
    except (OSError, ValueError, IndexError):
        return None


def walk_owned(root, owner):
    """As walk(root), restricted to OWNED descendants (T048 V4 round 7, N1): a node is owned when its parent in this
    walk is owned or owner(pid) says so. Non-owned nodes are traversed (an owned process cannot be below one -- see
    the OWNERSHIP rule in cmd_main) but never returned, and their zombies are not counted. owner(pid) returning None
    means "a subtree the CALLER started before main existed": it is PRUNED -- neither returned nor traversed (T048 V4
    round 8, V4R8-6: the session test `sid == keeper pid` is never evaluated below a caller's own child, so a reused
    keeper pid in a caller's subtree can never make one of the caller's processes look owned)."""
    out, seen, stack, zombies = [], {root}, [(root, False)], 0
    while stack:
        cur, cur_owned = stack.pop()
        for c in _children(cur):
            if c in seen:
                continue
            seen.add(c)
            sf = _stat_fields(c)
            if sf is None:
                continue
            mine = cur_owned or owner(c)
            if mine is None:
                continue          # the caller's own pre-existing subtree: pruned (V4R8-6)
            if mine:
                if sf[0] == "Z":
                    zombies += 1
                else:
                    out.append((c, cur))
            stack.append((c, mine))
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
        _beat()
        members, zombies = walk(me) if OWNER is None else walk_owned(me, OWNER)
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
def spawn(argv, env, entry_mask, cwd=None, marker=None, own_group=False):
    """fork+exec argv with PDEATHSIG=SIGKILL, dispositions reset (entry-ignored
    signals stay ignored, everything else SIG_DFL) and an empty signal mask.
    own_group: the child leads a new process group (the keeper's worker, round 7:
    a signal to the worker's process group must not reach the keeper -- when it
    SIGKILLed keeper, worker and run supervisor at once, a gate's setsid daemon was
    orphaned to main, which cannot attribute it; [SM] KILL-worker-group-daemon)."""
    old = signal.pthread_sigmask(signal.SIG_BLOCK, all_catchable())
    parent = os.getpid()
    pid = os.fork()
    if pid == 0:
        try:
            _prctl(PR_SET_PDEATHSIG, signal.SIGKILL)
            if os.getppid() != parent:
                os._exit(137)
            if own_group:
                os.setpgid(0, 0)
            for s in all_catchable():
                try:
                    signal.signal(s, signal.SIG_IGN if (s in KEEP_IGNORED and ignored(entry_mask, s))
                                  else signal.SIG_DFL)
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
def _git(repo, args):
    """One git call, bounded by GIT_TIMEOUT_S, beating every second while it runs (N4: a bounded step that is still
    running is progress; its bound is what keeps the whole wait bounded). On timeout it is SIGKILLed through a pidfd
    (§11.4.263 -- never a raw kill of a pid) and None is returned."""
    try:
        p = subprocess.Popen(["git", "-C", repo] + args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return None
    try:
        pfd = os.pidfd_open(p.pid)      # our own unreaped child: the pid cannot be reused while we hold it
    except OSError:
        pfd = None
    end = time.monotonic() + GIT_TIMEOUT_S
    try:
        while True:
            try:
                out, _ = p.communicate(timeout=1.0)
                return subprocess.CompletedProcess(p.args, p.returncode, out, None)
            except subprocess.TimeoutExpired:
                if time.monotonic() > end:
                    if pfd is not None:
                        try:
                            signal.pidfd_send_signal(pfd, signal.SIGKILL)
                        except OSError:
                            pass
                    try:
                        p.communicate(timeout=KILL_WAIT_S)
                    except (OSError, subprocess.SubprocessError):
                        pass
                    return None
                _beat()
    except (OSError, subprocess.SubprocessError):
        return None
    finally:
        if pfd is not None:
            os.close(pfd)


def _rmtree_beat(path):
    """shutil.rmtree(path, ignore_errors=True), iteratively and without following symlinks, beating every 500
    removed entries (N4: removing a large checkout is progress main can see)."""
    stack, n = [(path, False)], 0
    while stack:
        cur, emptied = stack.pop()
        try:
            st = os.lstat(cur)
        except OSError:
            continue
        try:
            if _st.S_ISDIR(st.st_mode):
                if not emptied:
                    stack.append((cur, True))
                    with os.scandir(cur) as it:
                        for e in it:
                            stack.append((e.path, False))
                    continue
                os.rmdir(cur)
            else:
                os.unlink(cur)
        except OSError:
            continue
        n += 1
        if n % 500 == 0:
            _beat()


def worktree_listed(repo, wt):
    """True / False: whether `git worktree list --porcelain` of repo still names wt; None when the list
    cannot be read (then nothing about the worktree can be verified)."""
    p = _git(repo, ["worktree", "list", "--porcelain"])
    if p is None or p.returncode != 0:
        return None
    want = {os.path.normpath(wt), os.path.realpath(wt)}
    for line in p.stdout.split(b"\n"):
        if line.startswith(b"worktree "):
            path = os.fsdecode(line[len(b"worktree "):])
            if os.path.normpath(path) in want or os.path.realpath(path) in want:
                return True
    return False


def remove_worktree(repo, wt):
    """Remove a replay worktree for real and VERIFY it (T048 V4 round 5, F2): a `git worktree add` that
    was SIGKILLed leaves the worktree `locked: initializing` -- `remove --force` refuses it and `prune`
    skips it -- so it is unlocked first and removed with -f -f. Returns (removed, detail): removed only
    when the directory is gone AND `git worktree list` no longer names it."""
    for args in (["worktree", "unlock", wt], ["worktree", "remove", "-f", "-f", wt], ["worktree", "prune"]):
        _git(repo, args)
    if os.path.lexists(wt):
        _rmtree_beat(wt)
        _git(repo, ["worktree", "prune"])
    on_disk = os.path.lexists(wt)
    listed = worktree_listed(repo, wt)
    if not on_disk and listed is False:
        return True, ""
    parts = []
    if on_disk:
        parts.append("the directory is still on disk")
    if listed is True:
        parts.append("`git worktree list` of %s still names it" % repo)
    elif listed is None:
        parts.append("`git worktree list` of %s could not be read, so the removal could not be verified" % repo)
    return False, "; ".join(parts)


def process_pending(fields, reason):
    """A `pend` entry is written BEFORE `mktemp -d` creates a directory the replay has not registered
    yet (T048 V4 round 5, F9): parent, name prefix, then the names that already existed. Any NEW,
    EMPTY directory under parent whose name starts with prefix was created in that window and is
    removed (rmdir only -- never a directory with content)."""
    if len(fields) < 2 or not fields[0] or not fields[1]:
        return
    parent, prefix = os.fsdecode(fields[0]), os.fsdecode(fields[1])
    before = {os.fsdecode(f) for f in fields[2:] if f}
    if not os.path.isabs(parent) or not os.path.isdir(parent):
        return
    try:
        names = os.listdir(parent)
    except OSError:
        return
    for n in names:
        if not n.startswith(prefix) or n in before:
            continue
        path = os.path.join(parent, n)
        try:
            if os.path.isdir(path) and not os.path.islink(path) and not os.listdir(path):
                os.rmdir(path)
                say("supervisor: removed the empty directory %s created by an interrupted replay before it was "
                    "registered (%s)" % (path, reason))
        except OSError:
            pass


# --------------------------------------------------------------------------
# "was the report written?" -- decided from DURABLE state, never from an exit status (T048 V4 round 8, V4R8-2)
# --------------------------------------------------------------------------
# Round 7 took "report written" from the report writer's EXIT STATUS: a stop landing after the writer's os.replace()
# but before the writer process exited made it return 143, so the replay said "stopped -- no report" (128+N) while the
# report was on disk, and the run-log directory it references was marked INTERRUPTED with a false text (30/30 runs of
# the reviewer's injection: TERM to the worker's process group the moment out.json appears; the same for a SIGKILL of
# the worker between the report and its `done` marker). Structural replacement: BEFORE the writer starts, the worker
# records -- atomically, in the private temp directory -- the report's absolute path, the identity of whatever is at
# that path now, the body_hash the report will carry (computed by fc_common.body_hash_of, the one implementation) and
# the exit code the replay has when that report exists. "The report was written" then means, for everyone who asks
# (worker, keeper, main): the file at that path is no longer the one recorded before AND its stored body_hash is the
# recorded one. os.replace() is atomic, so the path holds either the old file or the complete new report -- nothing in
# between. The worker's own view and the writer's exit status no longer decide anything; the round-7 `done` marker is
# gone (one source of truth).
REPORT_MARKER = "report.pending"
REPORT_MAX_BYTES = 256 * 1024 * 1024


def _identity(path):
    """(st_dev, st_ino, st_ctime_ns, st_mtime_ns, st_size) of whatever is AT path (lstat: a symlink is itself), or None.
    dev+ino alone are not an identity (T048 V4 round 9, V4R9-3 / RVM-H): when the old report is deleted between
    report-prepare and the writer, the writer's temp file may get the SAME inode number, and a report that WAS written
    would read as "still the old file". ctime, mtime and size tell the two apart; each is guarded by its own unit row
    ([R9ID-ctime] [R9ID-mtime] [R9ID-size])."""
    try:
        s = os.lstat(path)
    except OSError:
        return None
    return [s.st_dev, s.st_ino, s.st_ctime_ns, s.st_mtime_ns, s.st_size]


def report_prepare(statedir, fc_common, out, schema, body_json, code):
    """Write REPORT_MARKER into the STATE directory (temp + fsync + rename + directory fsync: it either exists complete
    or not at all). Returns 0, or 4 when the expected report cannot be described (then the caller must NOT write the
    report). The state directory -- never the keeper's temp directory -- holds it (T048 V4 round 9, V4R9-1)."""
    tmpdir = statedir
    import importlib.util
    import json
    if not (0 <= code <= 255):
        return 4
    spec = importlib.util.spec_from_file_location("fc_common_for_report", fc_common)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    body = mod.strict_loads(body_json)
    if not isinstance(body, dict):
        return 4
    doc = dict(body)
    doc["schema"] = schema           # exactly what fc_common.py emit hashes (cmd_emit, --code 0: no BLIND key)
    out_abs = os.path.abspath(out)
    rec = {"v": 1, "out": out_abs, "pre": _identity(out_abs), "body_hash": mod.body_hash_of(doc), "code": code}
    fd, tmp = tempfile.mkstemp(dir=tmpdir, prefix=".report.")
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(json.dumps(rec, sort_keys=True))
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, os.path.join(tmpdir, REPORT_MARKER))
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    dfd = os.open(tmpdir, os.O_RDONLY)
    try:
        os.fsync(dfd)
    finally:
        os.close(dfd)
    return 0


def report_verified(statedir):
    """The exit code recorded by report_prepare when the report it describes now EXISTS (see above), else None.
    A pure read of durable state: the marker in the STATE directory (which no process removes before main has decided
    its exit code -- see STATE DIRECTORY) and the report file at the recorded path (path + identity + body_hash)."""
    import json
    if not statedir:
        return None
    try:
        with open(os.path.join(statedir, REPORT_MARKER)) as fh:
            rec = json.loads(fh.read())
        out, pre, want, code = rec["out"], rec["pre"], rec["body_hash"], rec["code"]
    except (OSError, ValueError, KeyError, TypeError):
        return None
    if not (isinstance(out, str) and os.path.isabs(out) and isinstance(want, str) and len(want) == 64
            and isinstance(code, int) and not isinstance(code, bool) and 0 <= code <= 255):
        return None
    now = _identity(out)
    if now is None or now == pre:
        return None              # nothing there, or still the file that was there before the writer started
    try:
        with open(out, "rb") as fh:
            data = fh.read(REPORT_MAX_BYTES + 1)
        if len(data) > REPORT_MAX_BYTES:
            return None
        doc = json.loads(data.decode("utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(doc, dict) or doc.get("body_hash") != want:
        return None
    # BOUNDARY (§11.4.6, V4R9-7): a NEW file at the recorded path that carries the recorded body_hash reads as
    # "written" whoever wrote it. Replays are deterministic, so an identical report written by another writer between
    # report-prepare and this check (a user's copy, an unlocked writer of the same schema + body) would count; the
    # per-repository and per-filesystem locks make a second replay impossible, so this tool itself cannot do it.
    return code


def read_report(statedir):
    """DONE["code"] = the replay's exit code when its report exists (report_verified). A stop -- or a SIGKILL of the
    worker or the keeper -- that lands after the report was written does not turn a finished replay into "stopped --
    no report" (the round-6 F8 rule, at every supervisor process), and the run-log directories that report references
    are not marked INTERRUPTED."""
    code = report_verified(statedir)
    if code is not None:
        DONE["code"] = code


# --------------------------------------------------------------------------
# STATE DIRECTORY + THE ONE EXIT-CODE DERIVATION (T048 V4 round 9, V4R9-1 -- STRUCTURAL, §11.4.276(E))
# --------------------------------------------------------------------------
# Round 8 kept the report-pending marker in the keeper's private TEMP directory, and the keeper deletes that directory
# (teardown) before it exits: a keeper killed in the remaining window (by a stop's SIGKILL, by main's deadline, by
# anyone) left main asking a question whose answer had been deleted -- 137 with the report on disk (round-2 review,
# demo: exit=137 report_on_disk=yes). The class: every piece of state an exit decision reads must outlive every
# process that may still have to make that decision. Enumerated (CONVERGENCE.md, round 3):
#   state read by an exit decision ......... the report-pending marker (path + pre-identity + body_hash + code) and the
#                                            report file itself; the keeper's wait status (kernel, main reaps it); the
#                                            stop signal main received (main's memory).
#   who decides ............................ the keeper (its own exit code), main (the caller's exit code).
#   who may delete the marker .............. ONLY the final decider: main, after it computed its code; the keeper only
#                                            when main is provably gone (the EOF of the pipe whose sole write end main
#                                            holds) -- then the keeper is the final decider; a later main of the SAME
#                                            tmp-parent only for a directory whose owner (boot id + pid + start time,
#                                            in its NAME, written atomically by mkdtemp) is provably dead (gc).
# The marker therefore lives in a STATE directory next to (never inside) the temp directory. The report's own
# durable identity (absolute path, dev/ino/ctime/mtime/size before the writer ran, and the body_hash it carries) is
# what "written" means -- no process memory, no exit status, no directory any other process deletes.
STATE_PREFIX = "fc_baseline_replay.state."
STATE = {"dir": None, "main_owns": False}   # main: its state directory, and whether main alone may remove it now


def _boot_id():
    try:
        with open("/proc/sys/kernel/random/boot_id") as fh:
            return fh.read().strip().replace("-", "")[:12] or "noboot"
    except OSError:
        return "noboot"


def state_name_owner(name):
    """(boot id, pid, start time) encoded in a state directory's NAME, or None when the name is not one."""
    if not name.startswith(STATE_PREFIX):
        return None
    parts = name[len(STATE_PREFIX):].split(".")
    if len(parts) < 4:
        return None
    try:
        return parts[0], int(parts[1]), int(parts[2])
    except ValueError:
        return None


def make_statedir(parent):
    """main: create its state directory; its NAME carries the owner (boot id, main's pid, main's start time)."""
    ident = _ident(os.getpid())
    if ident is None:
        raise OSError("cannot read this process's own start time from /proc (the state directory's owner)")
    start = ident[1]
    return tempfile.mkdtemp(prefix="%s%s.%d.%d." % (STATE_PREFIX, _boot_id(), os.getpid(), start), dir=parent)


def remove_statedir(path):
    """Remove a state directory: only the files this module writes into it (the marker and report_prepare's temp
    files), then rmdir. Anything else in it is left (and the directory with it) -- never a recursive delete. Never
    raises. Returns True when the directory is gone."""
    if not path or not os.path.basename(path).startswith(STATE_PREFIX):
        return False
    try:
        st = os.lstat(path)
        if not _st.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
            return False
        names = os.listdir(path)
    except OSError:
        return not os.path.lexists(path)
    for n in names:
        if n == REPORT_MARKER or n.startswith(".report."):
            try:
                os.unlink(os.path.join(path, n))
            except OSError:
                pass
    try:
        os.rmdir(path)
    except OSError:
        pass
    return not os.path.lexists(path)


def gc_statedirs(parent):
    """main, at start: remove the state directories under parent whose owner is provably DEAD -- another boot, or no
    live process with that pid AND that start time. Left behind only when a main was SIGKILLed after its keeper exited
    (the one window in which no live process is the final decider); a live replay's directory is never touched.
    Returns the number removed. Never raises."""
    n = 0
    boot = _boot_id()
    try:
        names = os.listdir(parent)
    except OSError:
        return 0
    for name in names:
        own = state_name_owner(name)
        if own is None:
            continue
        b, pid, start = own
        if b == boot and pid > 1:
            ident = _ident(pid)
            if ident is not None and ident[1] == start:
                continue                       # its owner is alive: not ours to remove
        if remove_statedir(os.path.join(parent, name)):
            n += 1
    return n


# Termination causes (kind, n): ("code", c) a process exited with code c (the worker for the keeper, the keeper for
# main); ("stopped", S) the role was stopped by signal S before the work finished; ("killed", N) the keeper died of
# signal N with no stop (main); ("main_gone", 0) the keeper saw main disappear; ("lost", 0) a status could not be
# collected; ("internal", 0) a supervisor step failed.
def decide_code(verified, cause):
    """THE exit-code derivation (T048 V4 round 9, V4R9-1 STRUCTURAL): a PURE function of (report_verified, termination
    cause), evaluated identically by the keeper (for its own exit code) and by main (for the caller's). The report
    EXISTING (verified on disk) decides first: the work finished, nothing that stopped or killed anything afterwards
    changes its code (round 6 F8, round 7 N3, round 8 V4R8-2, round 9 V4R9-1). Otherwise the cause decides."""
    if verified is not None:
        return verified
    kind, n = cause
    if kind == "code":
        return n
    if kind in ("stopped", "killed"):
        return 128 + n
    if kind == "main_gone":
        return 137
    return 4                                   # lost / internal: BLIND


def main_cause(kst, sig):
    """main's termination cause from the keeper's wait status (None = lost) and the stop main received (0 = none)."""
    if kst is not None and os.WIFEXITED(kst):
        return ("code", os.WEXITSTATUS(kst))
    if sig:
        return ("stopped", sig)
    if kst is None:
        return ("lost", 0)
    if os.WIFSIGNALED(kst):
        return ("killed", os.WTERMSIG(kst))
    return ("code", decode(kst))


def process_ledger(tmpdir, reason, statedir=None):
    read_report(statedir)
    try:
        names = sorted(os.listdir(tmpdir))
    except OSError:
        return
    for name in names:
        if not name.startswith("ledger."):
            continue
        _beat()
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
                removed, detail = remove_worktree(repo, wt)
                if removed:
                    say("supervisor: removed the worktree %s left by an interrupted replay (%s)" % (wt, reason))
                else:
                    say("supervisor: could NOT remove the worktree %s left by an interrupted replay (%s): %s -- "
                        "remove it by hand: git -C %s worktree unlock %s; git -C %s worktree remove -f -f %s"
                        % (wt, reason, detail, repo, wt, repo, wt))
            else:
                say("supervisor: ledger entry %s names a path that is not a replay worktree -- not touched" % name)
        elif kind == "pend":
            process_pending(fields, reason)
        elif kind == "logs" and fields and fields[0]:
            d = os.fsdecode(fields[0])
            # the report exists (verified, read_report) and references this directory: nothing to mark
            if os.path.isdir(d) and DONE.get("code") is None:
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


def teardown(tmpdir, grace, reason, label, statedir=None):
    """Stop the tree, process the ledger, remove the TEMP directory. It never touches the STATE directory: whether the
    report was written must still be readable by every role that decides an exit code after this (V4R9-1)."""
    n = stop_tree(grace, label)
    if n:
        say("supervisor (%s): stopped %d process(es) (%s)" % (label, n, reason))
    process_ledger(tmpdir, reason, statedir)
    if os.path.basename(tmpdir).startswith("fc_baseline_replay."):
        shutil.rmtree(tmpdir, ignore_errors=True)


# --------------------------------------------------------------------------
# main / keeper
# --------------------------------------------------------------------------
def _on_stop(signum, _frame):
    if Stop.sig:
        return  # a second signal never shortens a stop already in progress (V4-N12 class)
    Stop.sig = signum
    if Stop.target_fd is not None:
        # forward the signal M RECEIVED, never a fixed SIGTERM (T048 V4 round 6, F1): K handles exactly the stop
        # signals M handles (both install this handler for every stop signal NOT ignored at entry, K inherits M's
        # dispositions across fork), so a forwarded signal is never one K ignores. A fixed SIGTERM was dropped by K
        # whenever the caller had TERM ignored (KEEP_IGNORED): the stop then waited out main's keeper deadline.
        try:
            signal.pidfd_send_signal(Stop.target_fd, signum)
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


def _main_owner(kpid, kstart, pre):
    """OWNERSHIP (T048 V4 round 7, N1 -- CLASS 1). main runs in the CALLER's pid (baseline_replay.sh execs into it),
    so it is the parent of whatever the caller started before exec (a background job, a `> >(tee log)` logger), and as
    a child subreaper it also adopts their orphans. None of that was started by this tool. A process is OWNED by the
    replay -- and only an owned process is ever signalled by main -- when it is
      - the keeper itself (its pid AND its start time, read right after the fork), or
      - in the keeper's SESSION: the keeper calls setsid(), so session id == the keeper's pid, and a session can only
        be joined by being forked inside it; the kernel never reuses a pid number while any process still carries it
        as a session id -- so, WHILE THE KEEPER'S SESSION HAS A MEMBER, this is proof of descent from the keeper, not
        a heuristic (once the keeper and every member of its session are gone the number is free and a new session
        may get it -- see the boundary below); or
      - a descendant (in the same walk) of an owned process (a daemon that called setsid() itself, below a run
        supervisor or the worker).
    The caller's pre-existing children (pid + start time, recorded at entry BEFORE main became a subreaper) are never
    owned, and their whole subtrees are PRUNED from the walk (owner returns None -- T048 V4 round 8, V4R8-6): the
    session test is never even evaluated below a caller's own child, so a reused keeper pid there cannot make one of
    the caller's processes look owned. BOUNDARY (§11.4.6): (1) a process that left the keeper's session (setsid) AND
    lost every owned ancestor before main's walk saw it is not attributable; it is reported by main ("could not be
    attributed"), never signalled. Since round 7 that needs TWO supervisor processes to die: a run supervisor whose
    worker dies stops its own tree first (parent-death signal SIGUSR2, cmd_run), so a gate's setsid daemon is never
    orphaned to main by the death of the keeper alone. (2) An orphan of a caller's DESCENDANT is re-parented to main
    (a subreaper) outside every pruned subtree; it is attributed to the replay only if it carries the keeper's pid as
    its session id, which after the keeper's whole session ended requires the kernel to have handed that pid number to
    a new session in the meantime -- not excluded by construction, stated here."""
    def owner(pid):
        ident = _ident(pid)
        if ident is None:
            return False
        sid, start = ident
        if (pid, start) in pre:
            return None          # the caller's own child: never owned, and its subtree is pruned (V4R8-6)
        return (pid == kpid and start == kstart) or sid == kpid
    return owner


def _pre_existing():
    """(pid, start time) of every child main has at entry -- the caller's, never this tool's."""
    out = set()
    for c in _children(os.getpid()):
        ident = _ident(c)
        if ident is not None:
            out.add((c, ident[1]))
    return out


def cmd_main(a):
    global OWNER
    _set_name("fc-supervisor")
    reset_inherited()
    pre = _pre_existing()   # BEFORE becoming a subreaper / adopting anything (N1)
    # an umask that masks the OWNER's bits makes every file this tool creates unusable to the tool itself
    # (lock files it cannot reopen, temp files it cannot write, a checkout it cannot delete): refused up
    # front, before anything is created (T048 V4 round 5, §11.4.276(C) class sweep)
    um = os.umask(0)
    os.umask(um)
    if um & 0o700:
        say("BLIND: the umask %04o masks the owner's permissions -- files this tool creates would be unusable "
            "(and a checkout could become undeletable); refusing to start" % um)
        sys.exit(4)
    if not children_probe():
        say(BLIND_CHILDREN)
        sys.exit(4)
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
    _MAIN_TMP[0] = tmpdir   # until the keeper exists, an exception in main removes it (main(); V4R8-1: no leak)
    gc_statedirs(a.tmp_parent)   # state directories of DEAD mains (SIGKILLed after their keeper exited, V4R9-1)
    try:
        statedir = make_statedir(a.tmp_parent)
    except OSError as e:
        say("BLIND: cannot create the replay's state directory under %s: %s" % (a.tmp_parent, e))
        sys.exit(4)
    STATE["dir"], STATE["main_owns"] = statedir, True
    r, w = os.pipe()        # M holds the only write end: EOF in K means M is gone
    hb_r, hb_w = os.pipe()  # K -> M progress beats (N4)
    _flush()
    try:
        kpid = os.fork()
    except OSError as e:
        say("BLIND: supervisor cannot fork its keeper: %s" % e)
        sys.exit(4)          # main(): _drop_main_tmp removes the temp AND the state directory
    if kpid == 0:
        STATE["main_owns"] = False
        _keeper(a, entry_mask, tmpdir, r, w, hb_r, hb_w, statedir)  # never returns
    _MAIN_TMP[0] = None     # from here the keeper / main's own teardown own the temp directory
    STATE["main_owns"] = False   # while the keeper lives, main gone => the keeper removes the state directory
    os.close(r)
    os.close(hb_w)
    os.set_blocking(hb_r, False)
    kfd = os.pidfd_open(kpid)
    kident = _ident(kpid)
    kstart = kident[1] if kident else None
    Stop.target_fd = kfd
    if Stop.sig:   # a stop that arrived before K existed is forwarded now -- the SAME signal (round 6, F1)
        signal.pidfd_send_signal(kfd, Stop.sig)
    signal.pthread_sigmask(signal.SIG_SETMASK, [])   # never the inherited `old` mask: a caller-blocked TERM stays unblocked
    stop_deadline = None
    hard_cap = None
    last_beat = None
    killed_keeper = False
    k_lost = False
    while True:
        reap()
        if kpid in REAPED:
            break
        if Stop.sig and stop_deadline is None:
            stop_deadline = time.monotonic() + a.grace + KILL_WAIT_S + KEEPER_SLACK_S
            hard_cap = stop_deadline + LEDGER_CAP_S
        if stop_deadline is not None and not killed_keeper:
            due = stop_deadline if last_beat is None else max(stop_deadline, last_beat + HB_WINDOW_S)
            if time.monotonic() > min(due, hard_cap):
                say("supervisor: the keeper did not finish its stop in time -- killing it and stopping the tree here")
                try:
                    signal.pidfd_send_signal(kfd, signal.SIGKILL)
                except OSError:
                    pass
                killed_keeper = True
        watch = [kfd] if hb_r is None else [kfd, hb_r]
        try:
            ready, _, _ = select.select(watch, [], [], 0.2)
        except InterruptedError:
            ready = []
        if hb_r is not None and hb_r in ready:
            try:
                data = os.read(hb_r, 4096)
            except BlockingIOError:
                data = None
            except OSError:
                data = b""
            if data == b"":
                os.close(hb_r)
                hb_r = None
            elif data:
                last_beat = time.monotonic()
        ready = [f for f in ready if f == kfd]
        if ready and reap_target(kpid) == "lost":
            k_lost = True
            break
    if hb_r is not None:
        os.close(hb_r)
    STATE["main_owns"] = True    # the keeper is gone (reaped, or its status lost): main is the final decider
    if k_lost:
        reason = "the keeper's exit status was lost (reaped outside this process)"
        say("supervisor: %s -- the outcome of the replay is unknown (BLIND)" % reason)
        kst = None
    else:
        kst = REAPED[kpid]
        if os.WIFSIGNALED(kst):
            reason = "the keeper was killed by signal %d" % os.WTERMSIG(kst)
        else:
            reason = "the keeper exited %d" % decode(kst)
    # normally a no-op (K already did it); the real work when K died abnormally. main stops only what it OWNS.
    OWNER = _main_owner(kpid, kstart, pre)
    teardown(tmpdir, a.grace, reason, "main", statedir)
    stray = []
    for c in _children(os.getpid()):
        ident = _ident(c)
        sf = _stat_fields(c)
        if ident is None or sf is None or sf[0] == "Z" or (c, ident[1]) in pre or OWNER(c):
            continue
        stray.append(c)
    if stray:
        say("supervisor: %d process(es) adopted by main could not be attributed to this replay and were NOT stopped "
            "(pid %s) -- reported, not hidden" % (len(stray), " ".join(str(c) for c in stray)))
    # THE derivation (V4R9-1): decided from the durable state BEFORE the state directory is removed; main removes it
    # only now, as the final decider (a SIGKILL of main between the two leaves it for the next main's gc_statedirs).
    code = main_exit_code(kst, Stop.sig, report_verified(statedir))
    remove_statedir(statedir)
    _exit_main(code)


def main_exit_code(kst, sig, done=None):
    """EXIT TABLE of the main role (T048 V4 round 7, CLASS 2 -- every path to main's exit code; one test row each in
    tests/test_fc_supervisor_v4r5_findings.sh [R7TABLE] and the rows named below; the state of the caller's
    stdout/stderr never changes a code -- every exit goes through _exit_main, which flushes without raising):
      keeper EXITED by itself, code c ............ c: the worker's code; 128+N when the stop reached the work before it
                                                   finished; the code recorded for the report when the report exists
                                                   (keeper side, N3 / V4R8-2) -- [F8LATE] [R7N3] [R7N3B] [R7N3C]
                                                   [R8N3*] [R7TABLE exited-*]
      the report exists (verified on disk) ...... the report's code, whatever the keeper's fate (exited, killed by a
                                                   signal, killed by main at its deadline, status lost) and whatever
                                                   stop main received: decide_code, the ONE derivation shared with the
                                                   keeper (round 9, V4R9-1) -- [R8N3KILLK] [R9WIN] [R9DEADLINE]
      keeper killed by signal N / main had to
        kill it at its deadline, stop S received . 128+S -- [RMB] [R7TABLE keeper-deadline-after-TERM]
      keeper killed by signal N, no stop ......... 128+N -- [R7N2] [R7TABLE keeper-killed-no-stop]
      keeper status lost, stop S / no stop ....... 128+S / 4 -- [F1LOSTMAIN]
      main refused before the keeper existed ..... 4 (umask, control needle, nesting, lock, temp dir, fork; sys.exit
                                                   funnels through main()) -- [UMASKS] [F3] [V4-4]
      an exception in main ....................... 4 -- [R7TABLE main-exception-after-start]
      any code above outside DOCUMENTED .......... 4, said so (a keeper's internal error or lost worker status is 4
                                                   in the keeper itself; a worker exiting 70/125/127 ...) --
                                                   [R7TABLE exited-undocumented-70 / keeper-internal-error /
                                                   keeper-lost-worker-status]
      a stop during Python start-up .............. INT: recorded by the early handler, then as any stop (128+2);
                                                   TERM/HUP/QUIT: the process ends BY the signal -- [R7N6] [R7N6SWEEP]
      every row above x the caller's stdout/stderr
        open / a pipe nobody reads (SIGPIPE default
        or ignored) / closed ..................... the SAME code and the same report presence (V4R8-1) --
                                                   tests/test_fc_supervisor_v4r8_stream_matrix.sh [R8MATRIX]
    """
    code = decide_code(done, main_cause(kst, sig))
    if code not in DOCUMENTED:
        say("supervisor: the keeper reported %d, which is not a documented exit code -- the replay's outcome is "
            "unknown (BLIND, 4)" % code)
        return 4
    return code


def _keeper(a, entry_mask, tmpdir, r, w, hb_r, hb_w, statedir=None):
    global HB_FD
    code = 4      # an internal error of the keeper is BLIND (round 7, N5: was 70, outside the documented codes)
    cause = ("internal", 0)
    try:
        os.close(w)
        os.close(hb_r)
        os.set_blocking(hb_w, False)
        HB_FD = hb_w
        Stop.sig = 0
        Stop.target_fd = None
        os.setsid()
        _set_name("fc-keeper")
        _prctl(PR_SET_CHILD_SUBREAPER, 1)
        _install_stop(entry_mask)
        env = dict(os.environ)
        env.update(FC_BR_SUPERVISED="1", FC_BR_TMPDIR=tmpdir, FC_BR_SUPERVISOR_PID=str(os.getpid()),
                   FC_BR_ENTRY_SIGIGN=a.entry_sigign, FC_BR_STATEDIR=statedir or "")
        wpid = spawn(a.cmd, env, entry_mask, own_group=True)
        wfd = os.pidfd_open(wpid)
        signal.pthread_sigmask(signal.SIG_SETMASK, [])
        reason, cause = None, ("internal", 0)
        while True:
            if Stop.sig:
                reason, cause = "stopped by signal %d" % Stop.sig, ("stopped", Stop.sig)
                break
            try:
                ready, _, _ = select.select([wfd, r], [], [], 0.2)
            except InterruptedError:
                continue
            reap()
            if wpid not in REAPED and wfd in ready and reap_target(wpid) == "lost":
                reason, cause = "the worker's exit status was lost (reaped outside the keeper)", ("lost", 0)
                say("supervisor (keeper): %s -- the outcome of the replay is unknown (BLIND)" % reason)
                break
            if wpid in REAPED:
                cause = ("code", decode(REAPED[wpid]))
                reason = "the worker exited %d" % cause[1]
                break
            if r in ready:
                try:
                    data = os.read(r, 1)
                except OSError:
                    data = b""
                if not data:
                    reason, cause = "the supervisor's main process is gone", ("main_gone", 0)
                    break
        teardown(tmpdir, a.grace, reason, "keeper", statedir)
        # THE derivation (V4R9-1): the same pure function main evaluates, on the same durable state. The state directory
        # is NOT removed here -- main still has to decide -- unless main is provably gone (then nobody else will).
        code = decide_code(report_verified(statedir), cause)
        if cause[0] == "main_gone":
            remove_statedir(statedir)
    except BaseException as e:  # noqa: BLE001 -- never fall back into M's code path
        say("supervisor (keeper) internal error: %r" % (e,))
        try:
            code = decide_code(report_verified(statedir), ("internal", 0))   # the same derivation as every path
        except BaseException:  # noqa: BLE001
            code = 4
    finally:
        try:
            _flush()             # never raises (V4R8-1) -- and even if it did, the keeper must not reach main's code
        finally:
            os._exit(code)


# --------------------------------------------------------------------------
# run
# --------------------------------------------------------------------------
def _write_timing(path, exit_ns, n_left, stop_ms):
    """The run's timing, for the caller (T048 V4 round 5, F5): the instant the command itself exited
    (CLOCK_REALTIME ns, the clock of `date +%s%N`), and -- separately -- how many processes it left
    running and how long stopping them took. The command's duration must never include that stop."""
    if not path:
        return
    try:
        with open(path, "w") as fh:
            fh.write("exit_ns=%d\nleftover_processes=%d\nleftover_stop_ms=%d\n"
                     % (exit_ns, n_left, int(round(stop_ms))))
    except OSError:
        pass


def _on_parent_gone(_signum, _frame):
    """run: the parent-death signal (T048 V4 round 7, N1). Counted only when the parent really is gone (a SIGUSR2 sent
    by anyone else while the worker lives is ignored)."""
    if os.getppid() != Stop.run_parent:
        Stop.parent_gone = True


def cmd_run(a):
    _set_name("fc-run")
    reset_inherited()
    entry_mask = int(a.entry_sigign, 16)
    parent = os.getppid()
    Stop.run_parent = parent
    # T048 V4 round 7 (N1): the parent-death signal is SIGUSR2 with a handler, no longer SIGKILL. When the worker
    # dies (its keeper was killed, or the worker was stopped), this run supervisor STOPS ITS OWN TREE before it exits
    # -- a gate's setsid'd daemon, the one kind of process main cannot attribute by session, is never orphaned past it.
    signal.signal(signal.SIGUSR2, _on_parent_gone)
    _prctl(PR_SET_PDEATHSIG, signal.SIGUSR2)
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
    if not children_probe():
        say(BLIND_CHILDREN)
        _mark(a.marker, "probe_failed")
        os._exit(125)
    if Stop.sig or Stop.parent_gone:   # a stop (or the worker's death) before the command was started (N6)
        _mark(a.marker, "stopped")
        os._exit(128 + Stop.sig if Stop.sig else 137)
    pid = spawn(a.cmd, dict(os.environ), entry_mask, cwd=a.cwd, marker=a.marker)
    pfd = os.pidfd_open(pid)
    deadline = time.monotonic() + a.timeout
    timed_out = lost = False
    exit_ns = None
    while True:
        reap()
        if pid in REAPED:
            if exit_ns is None:
                exit_ns = time.time_ns()
            break
        if Stop.sig or Stop.parent_gone:
            stop_tree(a.grace, "run" if Stop.sig else "run, its worker is gone")
            _mark(a.marker, "stopped")
            os._exit(128 + Stop.sig if Stop.sig else 137)
        left = deadline - time.monotonic()
        if left <= 0:
            timed_out = True
            break
        try:
            ready, _, _ = select.select([pfd], [], [], min(0.2, left))
        except InterruptedError:
            ready = []
        if ready:
            exit_ns = time.time_ns()       # the command's own exit, before any leftover is stopped (F5)
            if reap_target(pid) == "lost":
                lost = True
                break
    if lost:
        # the command ran and exited, but its status was reaped elsewhere: no verdict can be given
        stop_tree(a.grace, "run, status lost")
        say("supervisor (run): the command's exit status was lost (reaped outside the run supervisor)")
        _mark(a.marker, "status_lost")
        os._exit(125)
    if timed_out:
        stop_tree(a.kill_after, "run timeout")
        st = REAPED.get(pid)
        _mark(a.marker, "timed_out")
        os._exit(137 if st is not None and os.WIFSIGNALED(st) and os.WTERMSIG(st) == signal.SIGKILL else 124)
    rc = decode(REAPED[pid])
    t_stop = time.monotonic()
    n = stop_tree(a.grace, "run")
    if n:
        say("supervisor (run): the command exited but left %d process(es) running; stopped them" % n)
    _write_timing(a.timing, exit_ns, n, (time.monotonic() - t_stop) * 1000.0)
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
    r.add_argument("--timing", default=None)
    a = p.parse_args(opts)
    a.cmd = cmd
    return a


def cmd_report(argv):
    """`report-prepare` / `report-check` (the worker's side of V4R8-2; the keeper and main call report_verified
    directly). report-prepare --tmpdir D --fc-common PATH --out PATH --schema S --body-json JSON --code N: exit 0 when
    the marker was written, 4 otherwise (the report must then NOT be written). report-check --tmpdir D: exit 0 and the
    code on stdout when the report exists, 1 when it does not."""
    import argparse
    p = argparse.ArgumentParser(prog="fc_supervisor.py " + argv[0])
    p.add_argument("--statedir", "--tmpdir", dest="tmpdir", required=True)
    if argv[0] == "report-prepare":
        p.add_argument("--fc-common", required=True)
        p.add_argument("--out", required=True)
        p.add_argument("--schema", required=True)
        p.add_argument("--body-json", required=True)
        p.add_argument("--code", type=int, required=True)
    a = p.parse_args(argv[1:])
    if not os.path.basename(a.tmpdir).startswith("fc_baseline_replay.") or not os.path.isdir(a.tmpdir):
        say("BLIND: %s: %r is not the supervisor's state directory" % (argv[0], a.tmpdir))
        os._exit(4 if argv[0] == "report-prepare" else 1)
    if argv[0] == "report-prepare":
        try:
            rc = report_prepare(a.tmpdir, a.fc_common, a.out, a.schema, a.body_json, a.code)
        except Exception as e:  # noqa: BLE001
            say("BLIND: cannot record the report about to be written: %r" % (e,))
            rc = 4
        _flush()
        os._exit(rc)
    code = report_verified(a.tmpdir)
    if code is None:
        os._exit(1)
    try:
        os.write(1, b"%d\n" % code)
    except OSError:
        pass
    os._exit(0)


def main():
    _repair_std_fds()           # before anything is opened (V4R8-1)
    if sys.argv[1:2] in (["report-prepare"], ["report-check"]):
        try:
            cmd_report(sys.argv[1:])
        except SystemExit:      # argparse usage error (already printed)
            os._exit(4 if sys.argv[1] == "report-prepare" else 1)
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
    except SystemExit as e:
        if a.mode == "main":    # every sys.exit of the main role ends in the ONE exit (N2/N5, CLASS 2)
            _drop_main_tmp()
            _exit_main(e.code if isinstance(e.code, int) else 4)
        raise
    except BaseException as e:  # noqa: BLE001
        say("BLIND: supervisor (%s) failed: %r" % (a.mode, e))
        if a.mode == "main":
            _drop_main_tmp()
            _exit_main(4)
        os._exit(125)


def _drop_main_tmp():
    """main failed after creating its temp directory but before a keeper owned it: remove it; and the state directory
    when main is its final decider (no keeper, or the keeper is gone) -- never while a keeper still needs it (the
    keeper removes it itself when it sees main disappear). Never raises."""
    tmp = _MAIN_TMP[0]
    if tmp and os.path.basename(tmp).startswith("fc_baseline_replay."):
        shutil.rmtree(tmp, ignore_errors=True)
    if STATE["main_owns"]:
        remove_statedir(STATE["dir"])


if __name__ == "__main__":
    main()
