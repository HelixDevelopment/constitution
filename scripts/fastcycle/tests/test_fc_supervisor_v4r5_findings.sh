#!/usr/bin/env bash
# =============================================================================
# test_fc_supervisor_v4r5_findings.sh -- permanent regression guard for the
# independent line-by-line review of committed b61583e (T048 V4, round 5:
# cycle/fc_supervisor.py + cycle/baseline_replay.sh). Every case was written
# RED-first against b61583e and watched to fail for the reason it names.
#
# Cases (tag -> finding):
#   F1RUN       a caller with SIGCHLD IGNORED (inherited through exec) must not
#               turn `fc_supervisor.py run -- true` into a 100 % CPU spin until
#               --timeout (b61583e: rc 124 / timed_out after the full timeout).
#   F1LOST      the run role never busy-loops when the child's pidfd is readable
#               but waitpid reports no child (the status was reaped elsewhere):
#               bounded, explicit marker `status_lost`, rc 125.
#   F1LOSTMAIN  the same for the main + keeper roles (no endless spin, exit 4).
#   F2LEDGER    a worktree left `locked: initializing` (git SIGKILLed during
#               `git worktree add`) is really removed by the supervisor's ledger
#               processing (unlock + remove -f -f + prune), VERIFIED with
#               `git worktree list --porcelain` before "removed" is claimed.
#   F2HONEST    when removal cannot be verified the supervisor says so -- it never
#               claims "removed the worktree".
#   F2WORKER    the worker's own cleanup (_fc_wt_cleanup) removes a locked
#               worktree too, verified, and keeps the ledger entry on failure.
#   F3          /proc/<pid>/task/<tid>/children is a control needle at start-up:
#               a supervisor that cannot see a child it just started is BLIND
#               (main exit 4, run exit 125 + marker probe_failed) -- tested with a
#               mutant copy whose children path is renamed.
#   F5          duration_ms is measured to the gate command's OWN exit; the time
#               spent stopping processes it left behind is recorded separately
#               (leftover_stop_ms / leftover_processes) and the row is flagged.
#   F9LEDGER    process_ledger's `pend` entries remove an EMPTY directory created
#               just before its ledger entry existed -- and nothing else.
#   F9WT F9LOGS the worker SIGKILLed in the window between `mktemp -d` and the
#               ledger entry (worktree dir / run-log dir) leaves no directory.
#   F10         every possibly-empty array expansion uses the bash<4.4-safe form
#               (static oracle -- no bash < 4.4 on the reference host).
#   RMA         reviewer mutant RM-A: open_verified's pidfd signal-0 probe (a pid
#               that died after pidfd_open is refused).
#   RMB         reviewer mutant RM-B: the main supervisor's keeper-stop deadline
#               (a keeper that cannot finish its stop is killed; main exits).
#   CENSUS      §11.4.276(C) class sweep of inherited process state, each case
#               control-needled (the inherited condition is proven to be in
#               effect before its consequence is asserted): SIGCHLD ignored,
#               SIGPIPE ignored, TTIN/TTOU ignored (no controlling terminal),
#               HUP ignored (nohup, kept), TERM blocked in the signal mask, an
#               inherited pipe fd, an owner-masking umask, a stale FC_BR_SUPERVISED.
#               The blocked-TERM row names the MEASURED cause on failure (round 6 F7).
# ROUND 6 (independent review of the round-5 pack; each RED-first against it):
#   F1TERMIGN   a caller ignoring TERM + SIGINT to main: main forwards the signal it
#               RECEIVED (round 5 forwarded a fixed TERM the keeper ignores: 36 s).
#   F1LATE      the same for a stop that reached main before its keeper existed
#               (forced with a driver hook; control needle: Stop.sig set, no target).
#   F8LATE      a stop reaching main after the keeper exited 0 keeps exit 0
#               (forced with a driver hook inside main's teardown).
#   F2WORKER    (3rd half, reviewer mutant X5) an unreadable `git worktree list`
#               keeps the worker's ledger entry.
#   UMASKS      (reviewer mutant X2) every owner-masking umask refused, others run.
#   STOPCONT    (reviewer mutant X3) a SIGSTOPped leftover is stopped at once.
#   TMO137      (reviewer mutant X8) run timeout: 137 when KILLed, 124 on TERM.
#   CLEANUP     (F6) this file's EXIT trap signals only argv[0]-marked processes,
#               never a foreign observer naming a $WORK path.
# ROUND 7 (independent review of the round-6 pack: NO-GO 1 IMPORTANT + 6 MINOR; each RED-first against md5
# df625dd2 unless marked "guard"; two CLASSES closed structurally, see fc_supervisor.py "OWNERSHIP" + "EXIT TABLE"):
#   R7N1F       (N1, inj F) a job the CALLER started before exec survives a successful run, a stopped run and a full
#               replay (round 6: stopped by main's teardown).
#   R7N1L       (N1, inj L/L2/L3) a `> >(logger)` / `2> >(logger)` set up before exec is never signalled (round 6: TERM
#               then KILL, log tail lost, rc 4).
#   R7N2        (N2, inj L5) keeper SIGKILLed while main's stderr is a broken pipe: rc 137, not 4.
#   R7TABLE     (N2/N5, CLASS 2) one row per path to main's exit code x stderr open/closed (undocumented worker code
#               -> 4, keeper internal error -> 4, lost worker status -> 4, keeper killed -> 137, deadline kill after
#               TERM -> 143, exception -> 4; guard rows: 0, 3).
#   R7N3        (N3) a stop while the report writer runs: rc 130, no report, run-log dir INTERRUPTED.
#   R7N3B       (N3) a stop after the report was written: rc 0, no INTERRUPTED (round 8, V4R8-3: the shim no longer
#               makes the writer immune to the keeper's TERM after its rename -- the writer dies of it, rc still 0).
#   R7N3C       (N3, found by this round's own suite) the keeper's TERM kills an external command of the worker's
#               finish sequence (round 8: its `report-check`, held after a durable readiness marker -- V4R8-4): the
#               durable report state still decides -- rc 0, no INTERRUPTED.
#   R7N4        (N4, inj H) a keeper whose `git worktree remove` takes 8 s is waited for (heartbeat), never killed.
#   R7N4CAP     (guard) the wait stays bounded: the overall cap kills a keeper whose git is held longer.
#   R7N6        (N6, inj I) (a) INT pending at Python start-up -> 130 (round 6: KeyboardInterrupt -> 4); (b) INT to
#               bash in front of exec -> 130 (guard); (c) -S on both invocations; (d) INT blocked across the exec into
#               the supervisor (a start-up INT can no longer reach the interpreter's default handler).
#               (e) INT to bash during a FOREGROUND child in front of exec -> 130 (found by this round's sweep:
#               the stop was dropped by bash, the replay ran, rc 0; closed by traps in front of the exec).
#   R7N6SWEEP   (N6, inj I verbatim shape) 40 random start-up INTs: always 130 / killed by INT, never 0/1/4/traceback.
#   R7RUNPD     (N1) a run supervisor whose worker dies stops its own tree (a gate's setsid daemon) before exiting.
#   R7WGRP      (N1, found by this round's r2 run) the worker leads its own process group: a signal to it never
#               reaches the keeper.
#   R7EMPTYMK   (T1, reviewer mutant RVM-04) a marker that EXISTS BUT IS EMPTY is "no outcome": abort, exit 4.
# ROUND 8 (independent review of the round-7 pack: NO-GO 4 IMPORTANT + 2 MINOR + 1 NIT; CLASS 2 2nd structural attempt):
#   R8N3TERMGRP / R8N3KILLW / R8N3KILLK / R8N3NAT / R8N3STALE (V4R8-2) "was the report written" is decided from
#               DURABLE state (report-pending marker + the report on disk), never from the writer's exit status.
#   R7N3B / R7N3C (V4R8-3 / V4R8-4) the immunity trap removed from the shim; R7N3C injects its stop only after a
#               durable readiness marker (deterministic).
#   R8RVM02 / R8USR2 / R7TABLE exited-undocumented-128 (V4R8-5) the reviewer's mutants RVM-02 / USR2ANY / DOC128.
#   The caller-stream matrix (V4R8-1) is tests/test_fc_supervisor_v4r8_stream_matrix.sh.
#
# Env: FC_SUP_UNDER_TEST (fc_supervisor.py), FC_BR_UNDER_TEST (baseline_replay.sh)
#      -- the paired-mutation runner points these at mutants (the replay cases use
#      the supervisor next to FC_BR_UNDER_TEST, as the tool itself does).
#      V5_ONLY -- space-separated case tags to run (default all).
# Exit: 0 every selected case held; 1 any NOT ok.
# Runtime: ~1-2 minutes. Signals are only ever sent through pidfds to validated
# pids > 1 that this test started (§11.4.263); no pkill / pgrep -f.
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
SUP="${FC_SUP_UNDER_TEST:-$FC/cycle/fc_supervisor.py}"
SCRIPT="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"
[ -f "$SUP" ] || { echo "NOT ok supervisor under test not found: $SUP"; exit 1; }
[ -f "$SCRIPT" ] || { echo "NOT ok baseline_replay.sh under test not found: $SCRIPT"; exit 1; }

WORK="$(mktemp -d)"
export FC_REPLAY_LOCK_DIR="$WORK/locks"
mkdir -p "$FC_REPLAY_LOCK_DIR"
# shellcheck disable=SC2329  # cleanup is invoked indirectly: it is the EXIT trap handler registered by 'trap cleanup EXIT' below
cleanup() {
  # T048 V4 round 6, F6: ONLY a process whose argv[0] starts with this run's marker "v5t-$$-" (set with
  # `exec -a` by this test -- the same rule as the r2 suite's reap_marker) is signalled here. Matching ANY argv
  # element against $WORK/ or the marker used to kill foreign processes that merely NAMED a test path (an
  # observer `tail -f $WORK/x`, a reader of the marker string). Everything else this test started is stopped
  # structurally by the Python runner below (a child subreaper that kills its own descendant tree at exit).
  # HONEST BOUNDARY (§11.4.6): if that runner is itself SIGKILLed, an unmarked descendant of it is re-parented
  # past it and is not found here.
  M="v5t-$$-" python3 - <<'PY' 2>/dev/null
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

SUP="$SUP" SCRIPT="$SCRIPT" WORK="$WORK" MARK="v5t-$$-" TESTFILE="$HERE/$(basename "${BASH_SOURCE[0]}")" python3 -I - <<'PY'
import atexit, ctypes, importlib.util, json, os, re, resource, select, shutil, signal, subprocess, sys, time

SUP, SCRIPT, WORK, MARK = os.environ["SUP"], os.environ["SCRIPT"], os.environ["WORK"], os.environ["MARK"]
TESTFILE = os.environ["TESTFILE"]
ONLY = os.environ.get("V5_ONLY", "").split()
N = {"ok": 0, "bad": 0}

# F6 (round 6): this runner is a child subreaper, so every process any case starts -- also one that
# double-forks or calls setsid -- stays in ITS process tree, and the tree is stopped at exit by structure
# (pidfd, parent re-verified, pid > 1, never this process; §11.4.263), never by matching command lines.
ctypes.CDLL(None, use_errno=True).prctl(ctypes.c_int(36), ctypes.c_ulong(1), ctypes.c_ulong(0),
                                        ctypes.c_ulong(0), ctypes.c_ulong(0))


def _kill_own_tree():
    me = os.getpid()
    for _ in range(100):
        found = []
        stack, seen = [me], {me}
        while stack:
            cur = stack.pop()
            try:
                tids = os.listdir("/proc/%d/task" % cur)
            except OSError:
                continue
            for tid in tids:
                try:
                    kids = [int(x) for x in open("/proc/%d/task/%s/children" % (cur, tid)).read().split()]
                except (OSError, ValueError):
                    continue
                for c in kids:
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
                st = open("/proc/%d/stat" % pid).read()
                f = st[st.rindex(") ") + 2:].split()
                if int(f[1]) == parent and f[0] != "Z":
                    signal.pidfd_send_signal(fd, signal.SIGKILL); live += 1
            except (OSError, ValueError, IndexError):
                pass
            finally:
                os.close(fd)
        while True:   # at exit every subprocess call has returned: reaping here steals no status
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


def load(path=SUP):
    spec = importlib.util.spec_from_file_location("fcsup_v5_%d" % time.monotonic_ns(), path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def g(*a, cwd=None):
    return subprocess.run(["git", "-c", "user.email=t@t.t", "-c", "user.name=t"] + list(a), cwd=cwd,
                          capture_output=True, text=True)


def mk_repo(path):
    os.makedirs(path)
    g("init", "-q", path)
    open(os.path.join(path, "f.txt"), "w").write("hello\n")
    g("-C", path, "add", "f.txt")
    g("-C", path, "commit", "-q", "-m", "base")
    return g("-C", path, "rev-parse", "HEAD").stdout.strip()


def wt_entries(repo):
    out = g("-C", repo, "worktree", "list", "--porcelain").stdout
    return [l[len("worktree "):] for l in out.splitlines() if l.startswith("worktree ")]


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


def procs_under(prefix):
    out = []
    for p in os.listdir("/proc"):
        if not p.isdigit() or int(p) <= 1 or int(p) == os.getpid():
            continue
        try:
            st = open("/proc/%s/stat" % p).read()
            if st[st.rindex(") ") + 2:].split()[0] == "Z":
                continue
            argv = [a.decode(errors="replace") for a in open("/proc/%s/cmdline" % p, "rb").read().split(b"\0") if a]
        except (OSError, ValueError):
            continue
        if any(a.startswith(prefix) for a in argv):
            out.append((int(p), " ".join(argv)))
    return out


def comm(pid):
    try:
        return open("/proc/%d/comm" % pid).read().strip()
    except OSError:
        return ""


def ppid(pid):
    try:
        st = open("/proc/%d/stat" % pid).read()
        return int(st[st.rindex(") ") + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        return None


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


def status_mask(pid, field):
    try:
        for line in open("/proc/%d/status" % pid):
            if line.startswith(field + ":"):
                return int(line.split()[1], 16)
    except (OSError, ValueError):
        pass
    return None


def bit(mask, signo):
    return mask is not None and bool((mask >> (signo - 1)) & 1)


# A wrapper that establishes an inherited condition, then execs its argv. Conditions:
#   chld_ign  SIGCHLD -> SIG_IGN        pipe_ign  SIGPIPE -> SIG_IGN
#   tty_ign   SIGTTIN+SIGTTOU -> SIG_IGN hup_ign  SIGHUP -> SIG_IGN
#   term_blk  SIGTERM blocked in the mask       term_ign  SIGTERM -> SIG_IGN
#   fd7       an inherited pipe write end on fd 7 (read end handed to the test via FD7_READ_NOTE)
#   umask277  umask 0277 (masks the owner's write+exec bits)   umask=NNN  any octal umask
WRAP = os.path.join(WORK, "wrap.py")
open(WRAP, "w").write(r'''
import os, signal, sys
conds, argv = sys.argv[1].split(","), sys.argv[2:]
for c in conds:
    if c == "chld_ign": signal.signal(signal.SIGCHLD, signal.SIG_IGN)
    elif c == "pipe_ign": signal.signal(signal.SIGPIPE, signal.SIG_IGN)
    elif c == "tty_ign":
        signal.signal(signal.SIGTTIN, signal.SIG_IGN); signal.signal(signal.SIGTTOU, signal.SIG_IGN)
    elif c == "hup_ign": signal.signal(signal.SIGHUP, signal.SIG_IGN)
    elif c == "term_ign": signal.signal(signal.SIGTERM, signal.SIG_IGN)
    elif c == "term_blk": signal.pthread_sigmask(signal.SIG_BLOCK, [signal.SIGTERM])
    elif c == "umask277": os.umask(0o277)
    elif c.startswith("umask="): os.umask(int(c[len("umask="):], 8))
    elif c == "fd7": os.set_inheritable(7, True)
    elif c == "none": pass
    else: raise SystemExit("unknown condition " + c)
os.execvp(argv[0], argv)
''')


def wrapped(conds, argv, **kw):
    return ["python3", "-I", WRAP, conds] + argv


PROBE = os.path.join(WORK, "probe.sh")
# one write through one fd (a probe under an owner-masking umask creates a read-only file it could not
# re-open for appending). The masks are read with sed, NEVER awk: gawk sets SIGPIPE to SIG_IGN in its own
# process, so an awk reading /proc/self/status always reports SIGPIPE ignored (found by this census).
open(PROBE, "w").write('#!/bin/bash\n'
                       'o="$(sed -n \'s/^\\(SigIgn\\|SigBlk\\):[[:space:]]*/\\1 /p\' /proc/self/status)"\n'
                       'o="$o"$\'\\n\'"FDS $(ls /proc/$$/fd | tr "\\n" " ")"\n'
                       'o="$o"$\'\\n\'"UMASK $(umask)"\n'
                       'printf "%s\\n" "$o" >"$1"\n')
os.chmod(PROBE, 0o755)


def parse_probe(path):
    d = {}
    try:
        for line in open(path):
            k, _, v = line.strip().partition(" ")
            d[k.rstrip(":")] = v.strip()
    except OSError:
        pass
    return d


def run_sup(argv, timeout=30, env=None, wrap=None):
    cmd = ["python3", "-I", SUP] + argv
    if wrap:
        cmd = wrapped(wrap, cmd)
    t0 = time.monotonic()
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    try:
        out, err = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        sig_pid(p.pid, signal.SIGKILL)
        out, err = p.communicate()
        return None, out, err, time.monotonic() - t0
    return p.returncode, out, err, time.monotonic() - t0


def readf(p):
    try:
        return open(p).read()
    except OSError:
        return ""


# =============================================================================
if want("F1RUN"):
    d = os.path.join(WORK, "f1run"); os.makedirs(d)
    # control needle: the wrapper really leaves SIGCHLD ignored across exec
    subprocess.run(wrapped("chld_ign", [PROBE, os.path.join(d, "needle")]))
    needle = parse_probe(os.path.join(d, "needle"))
    ign = int(needle.get("SigIgn", "0"), 16)
    mk = os.path.join(d, "m")
    rc, out, err, dt = run_sup(["run", "--timeout", "8", "--marker", mk, "--cwd", d, "--", "true"], timeout=20,
                               wrap="chld_ign")
    if not bit(ign, signal.SIGCHLD):
        bad("[F1RUN] control needle: the wrapper did not leave SIGCHLD ignored (SigIgn=%x) -- the case proves nothing" % ign)
    elif rc == 0 and readf(mk) == "exited" and dt < 3.0:
        ok("[F1RUN] a caller with SIGCHLD ignored (needle: SigIgn bit 17 set): `run -- true` -> rc 0, exited, %.2fs" % dt)
    else:
        bad("[F1RUN] caller with SIGCHLD ignored: rc=%s marker=%r after %.2fs (want 0/exited at once) -- the run "
            "supervisor spun until --timeout (%s)" % (rc, readf(mk), dt, err.strip()[-200:]))

# =============================================================================
# F1LOST / F1LOSTMAIN drive the REAL cmd_run / cmd_main in a forked child whose SIGCHLD is
# ignored AFTER the module's own reset (the reset is replaced by a no-op): the kernel then
# auto-reaps every child, the pidfd is readable and waitpid finds nothing -- the exact state the
# loops must not spin on. Bound: wall time AND the child's own CPU time (wait4 rusage).
def fork_role(role, args_ns, timeout):
    m = load()
    r, w = os.pipe()
    pid = os.fork()
    if pid == 0:
        try:
            os.close(r)
            os.dup2(w, 2)
            if hasattr(m, "reset_inherited"):
                m.reset_inherited = lambda: None
            signal.signal(signal.SIGCHLD, signal.SIG_IGN)
            (m.cmd_run if role == "run" else m.cmd_main)(args_ns)
        except BaseException as e:  # noqa
            os.write(2, ("child exception %r\n" % (e,)).encode())
        os._exit(99)
    os.close(w)
    t0 = time.monotonic()
    buf, status, ru = b"", None, None
    end = t0 + timeout
    while time.monotonic() < end:
        rr, _, _ = select.select([r], [], [], 0.05)
        if rr:
            chunk = os.read(r, 65536)
            if chunk:
                buf += chunk
        p, st, rus = os.wait4(pid, os.WNOHANG)
        if p == pid:
            status, ru = st, rus
            break
    if status is None:
        sig_pid(pid, signal.SIGKILL)
        _, status, ru = os.wait4(pid, 0)
        timed_out = True
    else:
        timed_out = False
    try:
        while True:
            chunk = os.read(r, 65536)
            if not chunk:
                break
            buf += chunk
    except OSError:
        pass
    os.close(r)
    rc = os.waitstatus_to_exitcode(status)
    return rc, timed_out, time.monotonic() - t0, ru.ru_utime + ru.ru_stime, buf.decode(errors="replace")


class NS:
    def __init__(self, **kw):
        self.__dict__.update(kw)


if want("F1LOST"):
    d = os.path.join(WORK, "f1lost"); os.makedirs(d)
    mk = os.path.join(d, "m")
    a = NS(timeout=6.0, kill_after=1.0, grace=1.0, marker=mk, cwd=d, entry_sigign="0", timing=None, cmd=["true"])
    rc, to, dt, cpu, err = fork_role("run", a, 15)
    if not to and rc == 125 and readf(mk) == "status_lost" and dt < 3.0 and cpu < 1.5:
        ok("[F1LOST] the run role saw its child's pidfd readable with no status to collect: bounded "
           "(%.2fs wall, %.2fs CPU), marker status_lost, rc 125" % (dt, cpu))
    else:
        bad("[F1LOST] status reaped elsewhere: rc=%s marker=%r wall=%.2fs cpu=%.2fs timed_out=%s -- the run role "
            "busy-looped instead of reporting the lost status (%s)" % (rc, readf(mk), dt, cpu, to, err.strip()[-200:]))

if want("F1LOSTMAIN"):
    d = os.path.join(WORK, "f1lostmain"); os.makedirs(os.path.join(d, "tmp"))
    a = NS(tmp_parent=os.path.join(d, "tmp"), entry_sigign="0", grace=1.0, lock=[], lock_dir="", lock_fs=[],
           cmd=["true"])
    rc, to, dt, cpu, err = fork_role("main", a, 20)
    if not to and rc == 4 and dt < 6.0 and cpu < 3.0 and "status was lost" in err:
        ok("[F1LOSTMAIN] main + keeper with their children's status reaped elsewhere: bounded (%.2fs wall, %.2fs "
           "CPU), exit 4 BLIND, the loss reported" % (dt, cpu))
    else:
        bad("[F1LOSTMAIN] rc=%s wall=%.2fs cpu=%.2fs timed_out=%s -- main/keeper spun on a readable pidfd with no "
            "status (%s)" % (rc, dt, cpu, to, err.strip()[-300:]))

# =============================================================================
def locked_worktree(base, name):
    """A repo + a worktree left `locked: initializing` by a SIGKILLed `git worktree add`
    (a slow smudge filter holds git inside the add)."""
    repo = os.path.join(base, "repo")
    if not os.path.isdir(repo):
        mk_repo(repo)
        open(os.path.join(repo, ".gitattributes"), "w").write("f.txt filter=slow\n")
        g("-C", repo, "add", ".gitattributes"); g("-C", repo, "commit", "-q", "-m", "attr")
        g("-C", repo, "config", "filter.slow.smudge", "bash -c 'exec -a %ssmudge sleep 60'; cat" % MARK)
    wt = os.path.join(base, name)
    p = subprocess.Popen(["git", "-C", repo, "worktree", "add", "--detach", wt, "HEAD"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    adm = os.path.join(repo, ".git", "worktrees")
    end = time.monotonic() + 15
    seen = False
    while time.monotonic() < end and not seen:
        if os.path.isdir(adm):
            seen = any(os.path.exists(os.path.join(adm, n, "locked")) for n in os.listdir(adm))
        time.sleep(0.05)
    sig_pid(p.pid, signal.SIGKILL)
    p.wait()
    for pid, _ in procs_under(MARK + "smudge"):
        sig_pid(pid, signal.SIGKILL)
    porc = g("-C", repo, "worktree", "list", "--porcelain").stdout
    return repo, wt, seen and ("locked initializing" in porc)


def ledger_dir(base, entries):
    td = os.path.join(base, "tmp_%d" % time.monotonic_ns()); os.makedirs(td)
    for i, (kind, fields) in enumerate(entries):
        with open(os.path.join(td, "ledger.%s.%02d" % (kind, i)), "wb") as fh:
            fh.write(b"".join(os.fsencode(f) + b"\0" for f in fields))
    return td


if want("F2LEDGER") or want("F2HONEST"):
    base = os.path.join(WORK, "f2"); os.makedirs(base)
    repo, wt, needle = locked_worktree(base, "replay.lk1")
    if not needle:
        bad("[F2LEDGER] setup/control needle: no `locked initializing` worktree could be produced -- the case proves nothing")
    else:
        m = load(); msgs = []
        m.say = msgs.append
        td = ledger_dir(base, [("wt", [repo, wt])])
        m.process_ledger(td, "unit")
        listed = [e for e in wt_entries(repo) if os.path.basename(e) == "replay.lk1"]
        claim = any("removed the worktree" in s for s in msgs)
        if want("F2LEDGER"):
            if not listed and not os.path.lexists(wt) and claim:
                ok("[F2LEDGER] a worktree left `locked: initializing` by a SIGKILLed add is unlocked, removed (-f -f) "
                   "and pruned; `git worktree list` no longer lists it, and only then is it reported removed")
            else:
                bad("[F2LEDGER] locked worktree: still listed=%s dir exists=%s messages=%r -- the supervisor "
                    "claimed or left a removal it never verified" % (bool(listed), os.path.lexists(wt), msgs))
    if want("F2HONEST") and needle:
        # the ledger names a repository git cannot read: the removal cannot be VERIFIED -> no "removed" claim
        repo2, wt2, needle2 = locked_worktree(base, "replay.lk2")
        notrepo = os.path.join(base, "not_a_repo"); os.makedirs(notrepo, exist_ok=True)
        m = load(); msgs = []
        m.say = msgs.append
        td = ledger_dir(base, [("wt", [notrepo, wt2])])
        m.process_ledger(td, "unit")
        claim = any("removed the worktree" in s for s in msgs)
        honest = any("could NOT" in s or "could not verify" in s for s in msgs)
        if needle2 and not claim and honest:
            ok("[F2HONEST] a removal git cannot verify is reported as such, never as 'removed the worktree' (%s)"
               % msgs[-1][:160])
        else:
            bad("[F2HONEST] unverifiable removal: needle=%s claimed-removed=%s honest-report=%s messages=%r"
                % (needle2, claim, honest, msgs))
        g("-C", repo2, "worktree", "unlock", wt2); g("-C", repo2, "worktree", "prune")

# =============================================================================
if want("F2WORKER"):
    base = os.path.join(WORK, "f2w"); os.makedirs(base)
    repo, wt, needle = locked_worktree(base, "replay.lkw")
    led = os.path.join(base, "ledger.wt.x"); open(led, "w").write("x")
    fn = subprocess.run(["sed", "-n", "/^_fc_wt_listed() {/,/^}/p;/^_fc_wt_cleanup() {/,/^}/p", SCRIPT], capture_output=True, text=True).stdout
    harness = fn + '\n_FC_WT_REPO="$1"; _FC_WT_PATH="$2"; _FC_WT_LEDGER="$3"\n_fc_wt_cleanup; echo "rc=$?"\n'
    p = subprocess.run(["bash", "-c", harness, "x", repo, wt, led], capture_output=True, text=True)
    listed = [e for e in wt_entries(repo) if os.path.basename(e) == "replay.lkw"]
    if not needle or not fn.strip():
        bad("[F2WORKER] setup: locked-worktree needle=%s, _fc_wt_cleanup found=%s" % (needle, bool(fn.strip())))
    elif not listed and not os.path.lexists(wt) and "rc=0" in p.stdout and not os.path.exists(led):
        ok("[F2WORKER] the worker's _fc_wt_cleanup removes a locked worktree (verified: not listed, dir gone) and "
           "only then drops its ledger entry")
    else:
        bad("[F2WORKER] _fc_wt_cleanup on a locked worktree: listed=%s dir=%s out=%r ledger-kept=%s"
            % (bool(listed), os.path.lexists(wt), (p.stdout + p.stderr)[-200:], os.path.exists(led)))
    # negative half: a removal that cannot succeed (the repository is not a repository) must keep the ledger
    # entry for the supervisor and say so (exit 1)
    fake = os.path.join(base, "replay.fake"); os.makedirs(fake)
    open(os.path.join(fake, "x"), "w").write("x")
    led2 = os.path.join(base, "ledger.wt.y"); open(led2, "w").write("y")
    os.chmod(base, 0o555)   # the directory cannot be deleted -> removal must fail and be reported
    try:
        p2 = subprocess.run(["bash", "-c", harness, "x", os.path.join(base, "nope"), fake, led2],
                            capture_output=True, text=True)
    finally:
        os.chmod(base, 0o755)
    if "rc=1" in p2.stdout and os.path.exists(led2) and os.path.isdir(fake) and "could NOT" in p2.stderr:
        ok("[F2WORKER] a worktree that cannot be removed is reported (exit 1, 'could NOT'), its ledger entry kept "
           "for the supervisor")
    else:
        bad("[F2WORKER] failed removal: out=%r err=%r ledger-kept=%s dir=%s -- a failure was hidden"
            % (p2.stdout[-80:], p2.stderr[-200:], os.path.exists(led2), os.path.isdir(fake)))
    # third half (round 6, F4 -- reviewer mutant X5 survived): the directory IS removed but `git worktree list`
    # cannot be READ (_fc_wt_listed returns 2), so the removal cannot be verified -- the ledger entry must be kept
    # (exit 1, "unreadable"), never dropped as if the worktree were gone from git's list too
    plain = os.path.join(base, "replay.unverif"); os.makedirs(plain)
    open(os.path.join(plain, "x"), "w").write("x")
    led3 = os.path.join(base, "ledger.wt.z"); open(led3, "w").write("z")
    norepo = os.path.join(base, "no_such_repo_dir")
    needle3 = subprocess.run(["git", "-C", norepo, "worktree", "list", "--porcelain"], capture_output=True).returncode
    p3 = subprocess.run(["bash", "-c", harness, "x", norepo, plain, led3], capture_output=True, text=True)
    if needle3 == 0:
        bad("[F2WORKER] control needle: `git worktree list` of a missing directory succeeded -- the unreadable "
            "branch is not exercised")
    elif "rc=1" in p3.stdout and os.path.exists(led3) and not os.path.lexists(plain) and "unreadable" in p3.stderr:
        ok("[F2WORKER] a removal git cannot VERIFY (directory gone, `git worktree list` unreadable: needle rc %d) "
           "keeps the ledger entry and says so (exit 1, 'unreadable')" % needle3)
    else:
        bad("[F2WORKER] unverifiable removal: out=%r err=%r ledger-kept=%s dir=%s -- an unverified removal was "
            "treated as verified" % (p3.stdout[-80:], p3.stderr[-200:], os.path.exists(led3), os.path.lexists(plain)))

# =============================================================================
if want("F3"):
    d = os.path.join(WORK, "f3"); os.makedirs(os.path.join(d, "tmp"))
    src = open(SUP).read()
    mut = src.replace('"/proc/%d/task/%s/children"', '"/proc/%d/task/%s/children_absent_v5"')
    blindcopy = os.path.join(d, "fc_supervisor_nochildren.py")
    open(blindcopy, "w").write(mut)
    swapped = mut != src
    rc_c, _, err_c, _ = run_sup(["main", "--tmp-parent", os.path.join(d, "tmp"), "--", "true"], timeout=20)
    p = subprocess.run(["python3", "-I", blindcopy, "main", "--tmp-parent", os.path.join(d, "tmp"), "--", "true"],
                       capture_output=True, text=True, timeout=20)
    mk = os.path.join(d, "m")
    p2 = subprocess.run(["python3", "-I", blindcopy, "run", "--timeout", "5", "--marker", mk, "--cwd", d, "--", "true"],
                        capture_output=True, text=True, timeout=20)
    if not swapped:
        bad("[F3] the mutant copy could not rename the children path -- the case proves nothing")
    elif rc_c != 0:
        bad("[F3] control: the unmutated supervisor `main -- true` rc=%s (%s)" % (rc_c, err_c.strip()[-200:]))
    elif p.returncode == 4 and "BLIND" in p.stderr and "children" in p.stderr and p2.returncode == 125 \
            and readf(mk) == "probe_failed":
        ok("[F3] without /proc/<pid>/task/<tid>/children the supervisor refuses to run blind: main exit 4 BLIND, "
           "run exit 125 + marker probe_failed (control: the real supervisor ran, rc 0)")
    else:
        bad("[F3] children file missing: main rc=%s (%s) run rc=%s marker=%r -- the supervisor ran with a tree walk "
            "that can see nothing" % (p.returncode, p.stderr.strip()[-160:], p2.returncode, readf(mk)))

# =============================================================================
def replay(case, repo, head, gate, extra_env=None, extra=(), timeout=120):
    wtr = os.path.join(case, "wt")
    env = dict(os.environ)
    env.pop("FC_OUT", None)
    env.update(TMPDIR=os.path.join(case, "tmp"), FC_REPLAY_LOCK_DIR=os.path.join(case, "locks"))
    if extra_env:
        env.update(extra_env)
    os.makedirs(os.path.join(case, "tmp"), exist_ok=True)
    os.makedirs(os.path.join(case, "locks"), exist_ok=True)
    out = os.path.join(case, "out.json")
    argv = ["bash", SCRIPT, "replay", "--commit", head, "--repo-root", repo, "--worktree-root", wtr,
            "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd", gate, "--warm-runs", "0",
            "--out", out] + list(extra)
    p = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=timeout)
    try:
        rep = json.load(open(out))
    except (OSError, ValueError):
        rep = None
    return p.returncode, rep, p.stderr, wtr


if want("F5"):
    case = os.path.join(WORK, "f5"); os.makedirs(case)
    repo = os.path.join(case, "repo"); head = mk_repo(repo)
    gate = os.path.join(case, "gate.sh")
    open(gate, "w").write("#!/bin/bash\ntrap '' TERM\n( trap '' TERM; exec -a %sleftover sleep 30 ) &\nexit 0\n" % MARK)
    os.chmod(gate, 0o755)
    rc, rep, err, _ = replay(case, repo, head, gate, {"FC_BR_STOP_GRACE_S": "1"}, ["--cold-runs", "1"])
    body = (rep or {}).get("body", rep) or {}
    runs = body.get("runs") or []
    r0 = runs[0] if runs else {}
    try:
        lo = (body.get("leftover_runs") or {}).get("cold")
    except AttributeError:
        lo = None
    if rc == 0 and r0.get("verdict") == "PASS" and r0.get("duration_ms", 99999) < 900 \
            and r0.get("leftover_processes", 0) >= 1 and r0.get("leftover_stop_ms", 0) >= 900 and lo == 1:
        ok("[F5] a gate that exits at once but leaves a TERM-ignoring child: duration_ms=%d (to the command's exit), "
           "leftover_stop_ms=%d and leftover_processes=%d recorded separately, row counted in leftover_runs"
           % (r0["duration_ms"], r0["leftover_stop_ms"], r0["leftover_processes"]))
    else:
        bad("[F5] rc=%s run=%r leftover_runs=%r -- the time spent stopping leftovers was charged to the gate"
            % (rc, {k: r0.get(k) for k in ("verdict", "duration_ms", "leftover_processes", "leftover_stop_ms")}, lo))

# =============================================================================
if want("F9LEDGER"):
    base = os.path.join(WORK, "f9l"); os.makedirs(base)
    root = os.path.join(base, "root"); os.makedirs(root)
    for n in ("replay.old111",):            # pre-existing EMPTY dir in the snapshot -> must survive
        os.makedirs(os.path.join(root, n))
    os.makedirs(os.path.join(root, "replay.new222"))            # new, empty -> removed
    os.makedirs(os.path.join(root, "replay.full333")); open(os.path.join(root, "replay.full333", "k"), "w").write("k")
    os.makedirs(os.path.join(root, "other.444"))                 # wrong prefix -> survives
    m = load(); msgs = []
    m.say = msgs.append
    td = ledger_dir(base, [("pend", [root, "replay.", "replay.old111"])])
    m.process_ledger(td, "unit")
    left = sorted(os.listdir(root))
    if left == ["other.444", "replay.full333", "replay.old111"] and not os.listdir(td):
        ok("[F9LEDGER] a pend entry removes only the NEW, EMPTY prefix-matching directory (kept: the snapshot's "
           "empty dir, a non-empty one, another prefix)")
    else:
        bad("[F9LEDGER] pend processing left %s (ledger dir %s, messages %r)" % (left, os.listdir(td), msgs))


def kill_worker_shim(case, trigger):
    """A `mktemp` on PATH: creates the directory for real, then SIGKILLs the replay WORKER (the bash
    whose parent is fc-keeper) -- a stop landing exactly between `mktemp -d` and the ledger entry."""
    shim = os.path.join(case, "shim"); os.makedirs(shim)
    real = shutil.which("mktemp")
    open(os.path.join(shim, "mktemp"), "w").write(r'''#!/bin/bash
out="$(%s "$@")" || exit $?
case "$*" in
  *"-d "*%s*)
    echo "$out" >"%s/created"
    p=$PPID
    for _ in 1 2 3 4; do
      case "$p" in ''|*[!0-9]*) break ;; esac
      [ "$p" -gt 1 ] || break
      pp=$(sed 's/.*) //' "/proc/$p/stat" | cut -d' ' -f2)
      if [ "$(cat "/proc/$pp/comm" 2>/dev/null)" = fc-keeper ]; then
        echo "$p" >"%s/killed"; kill -KILL "$p"; sleep 5; exit 1
      fi
      p=$pp
    done ;;
esac
echo "$out"
''' % (real, trigger, case, case))
    os.chmod(os.path.join(shim, "mktemp"), 0o755)
    return shim


for tag, trig, sub in (("F9WT", '"/replay."', None), ("F9LOGS", '"/replay-logs/"', "replay-logs")):
    if not want(tag):
        continue
    case = os.path.join(WORK, tag.lower()); os.makedirs(case)
    repo = os.path.join(case, "repo"); head = mk_repo(repo)
    shim = kill_worker_shim(case, trig)
    rc, rep, err, wtr = replay(case, repo, head, "true", {"PATH": shim + ":" + os.environ["PATH"]},
                               ["--cold-runs", "1"])
    created = readf(os.path.join(case, "created")).strip()
    killed = os.path.exists(os.path.join(case, "killed"))
    scan = os.path.join(wtr, sub) if sub else wtr
    leftovers = []
    if os.path.isdir(scan):
        for n in os.listdir(scan):
            pth = os.path.join(scan, n)
            if sub:
                if not os.path.exists(os.path.join(pth, "INTERRUPTED")):
                    leftovers.append(n)
            elif n.startswith("replay."):
                leftovers.append(n)
    tmpleft = os.listdir(os.path.join(case, "tmp"))
    if not created or not killed:
        bad("[%s] setup/control needle: the shim did not fire (created=%r killed=%s rc=%s) -- the window was never "
            "hit (%s)" % (tag, created, killed, rc, err.strip()[-200:]))
    elif rc == 137 and not leftovers and not tmpleft and len(wt_entries(repo)) == 1:
        ok("[%s] the worker SIGKILLed between `mktemp -d` (%s) and its ledger entry: the directory is gone, rc 137, "
           "nothing left" % (tag, os.path.basename(created)))
    else:
        bad("[%s] stop in the mktemp->ledger window: rc=%s leftover dirs=%s temp=%s worktrees=%d -- an unregistered "
            "directory survived the stop" % (tag, rc, leftovers, tmpleft, len(wt_entries(repo))))

# =============================================================================
# F10: `"${a[@]}"` of an EMPTY array under `set -u` is an "unbound variable" error on bash < 4.4.
# HONEST BOUNDARY (§11.4.6): no bash < 4.4 exists on the reference host (/bin/bash4 is 4.4.23, where
# the bug is fixed), so the failure cannot be reproduced here; the oracle is static -- every expansion
# of an array that CAN be empty (the supervisor's lock args, the original argv, the run timing args,
# the pend snapshot) must use the safe ${a[@]+"${a[@]}"} form.
if want("F10"):
    src = open(SCRIPT).read()
    unsafe = []
    for name in ("args", "ORIG_ARGS", "targs", "names"):
        plain = '"${%s[@]}"' % name
        safe = '${%s[@]+"${%s[@]}"}' % (name, name)
        n_plain, n_safe = src.count(plain), src.count(safe)
        if n_plain != n_safe:
            unsafe.append("%s: %d expansion(s), %d in the safe form" % (name, n_plain, n_safe))
        if n_safe == 0:
            unsafe.append("%s: no safe expansion found at all (the check would be vacuous)" % name)
    if not unsafe:
        ok("[F10] every expansion of a possibly-empty array (args, ORIG_ARGS, targs, names) uses the "
           "${a[@]+\"${a[@]}\"} form (static oracle: bash < 4.4 is not on this host)")
    else:
        bad("[F10] possibly-empty arrays expanded unsafely for bash < 4.4 under set -u: %s" % "; ".join(unsafe))

# =============================================================================
if want("RMA"):
    m = load()
    me = os.getpid()
    child = subprocess.Popen(["sleep", "60"])
    orig = m._stat_fields

    def died_then_reused(pid):
        # the process the pidfd was opened on dies and is reaped; /proc now "shows" a process whose
        # parent is the expected node (a reused pid) -- only the signal-0 probe can tell
        if pid == child.pid:
            child.kill(); child.wait()
            return ("S", me)
        return orig(pid)
    m._stat_fields = died_then_reused
    fd = m.open_verified(child.pid, me)
    m._stat_fields = orig
    if fd is None:
        ok("[RMA] open_verified refuses a pid whose process died after pidfd_open (the signal-0 probe), even when "
           "/proc names the expected parent")
    else:
        os.close(fd)
        bad("[RMA] open_verified returned a pidfd for a process that died after the open -- the /proc read it "
            "trusted was of ANOTHER process")
    if child.poll() is None:
        child.kill(); child.wait()

# =============================================================================
if want("RMB"):
    d = os.path.join(WORK, "rmb"); os.makedirs(os.path.join(d, "tmp"))
    drv = os.path.join(d, "drive.py")
    open(drv, "w").write(
        "import importlib.util, sys\n"
        "spec = importlib.util.spec_from_file_location('fcsup', %r)\n"
        "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
        "m.KILL_WAIT_S = 1.0\n"
        "if hasattr(m, 'KEEPER_SLACK_S'): m.KEEPER_SLACK_S = 1.0\n"
        "sys.argv = ['fc_supervisor.py'] + sys.argv[1:]\n"
        "m.main()\n" % SUP)
    p = subprocess.Popen(["python3", "-I", drv, "main", "--tmp-parent", os.path.join(d, "tmp"), "--grace", "0",
                          "--", "bash", "-c", 'exec -a "$0" sleep 600', MARK + "rmbworker"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    keeper = None
    end = time.monotonic() + 10
    while time.monotonic() < end and keeper is None:
        ks = [c for c in children(p.pid) if comm(c) == "fc-keeper"]
        if ks and procs_under(MARK + "rmbworker"):
            keeper = ks[0]
        time.sleep(0.05)
    if keeper is None:
        bad("[RMB] setup: no keeper/worker appeared")
        sig_pid(p.pid, signal.SIGKILL); p.wait()
    else:
        sig_pid(keeper, signal.SIGSTOP)          # the keeper can no longer finish (or even start) its stop
        t0 = time.monotonic()
        sig_pid(p.pid, signal.SIGTERM)
        try:
            p.wait(timeout=15)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            rc = None
        dt = time.monotonic() - t0
        left = procs_under(MARK + "rmbworker")
        kalive = os.path.exists("/proc/%d" % keeper) and comm(keeper) == "fc-keeper"
        if rc == 143 and not left and not kalive and dt < 12:
            ok("[RMB] a keeper that cannot finish its stop is killed by main after the bounded deadline; main exited "
               "143 in %.1fs and nothing is left" % dt)
        else:
            bad("[RMB] stopped keeper: main rc=%s after %.1fs, worker left=%s keeper alive=%s -- main waited for a "
                "keeper stop that can never finish" % (rc, dt, bool(left), kalive))
            for pid in [keeper] + [q for q, _ in left]:
                sig_pid(pid, signal.SIGKILL)
            if rc is None:
                sig_pid(p.pid, signal.SIGKILL); p.wait()

# =============================================================================
# CENSUS (§11.4.276(C)): every inherited piece of process state that crosses exec into the
# supervisor, enumerated, each closed or explicitly scoped out. Every row first proves its
# condition is in effect (control needle) on a probe started through the same wrapper.
if want("CENSUS"):
    d = os.path.join(WORK, "census"); os.makedirs(d)

    def needle(conds, extra_fd=False):
        path = os.path.join(d, "needle_%s" % conds.replace(",", "_"))
        if extra_fd:
            rfd, wfd = os.pipe()
            if wfd != 7:
                os.dup2(wfd, 7); os.close(wfd)
            subprocess.run(wrapped(conds, [PROBE, path]), pass_fds=(7,))
            os.close(rfd); os.close(7)
        else:
            subprocess.run(wrapped(conds, [PROBE, path]))
        return parse_probe(path)

    def gate_view(conds, entry_ign):
        """run a probe as the GATE of `fc_supervisor.py run`, started through the wrapper, handing the
        run role the entry mask baseline_replay.sh would hand it (the caller's SigIgn, read by the needle)"""
        path = os.path.join(d, "gate_%s" % conds.replace(",", "_"))
        mk = os.path.join(d, "mk_%s" % conds.replace(",", "_"))
        cmd = wrapped(conds, ["python3", "-I", SUP, "run", "--timeout", "10", "--marker", mk, "--cwd", d,
                              "--entry-sigign", entry_ign or "0", "--", PROBE, path])
        p = subprocess.run(cmd, capture_output=True, timeout=20)
        return parse_probe(path), p.returncode

    # SIGPIPE: closed -- a caller-ignored SIGPIPE is reset to the default for the gate (a gate's
    # measurement must not depend on the caller's disposition; only HUP/INT/QUIT/TERM are kept, nohup)
    nd = needle("pipe_ign"); gv, rc = gate_view("pipe_ign", nd.get("SigIgn"))
    if not bit(int(nd.get("SigIgn", "0"), 16), signal.SIGPIPE):
        bad("[CENSUS] SIGPIPE: control needle failed (the wrapper did not ignore SIGPIPE)")
    elif rc == 0 and not bit(int(gv.get("SigIgn", "0"), 16), signal.SIGPIPE):
        ok("[CENSUS] SIGPIPE ignored by the caller (needle) is reset to the default in the gate")
    else:
        bad("[CENSUS] SIGPIPE: rc=%s gate view=%r -- the caller's ignored SIGPIPE leaked into the gate" % (rc, gv))
    # the entry-mask INSTRUMENT itself (baseline_replay.sh's `ign=` line): it must report the caller's
    # dispositions, not its own -- the awk it used to run ignores SIGPIPE itself, so it reported SIGPIPE
    # "ignored by the caller" for every caller (an observer-contaminated reading, §11.4.201(10))
    line = [l for l in open(SCRIPT).read().splitlines() if l.lstrip().startswith('ign="$(')]
    if len(line) != 1:
        bad("[CENSUS] entry-mask instrument: expected exactly one `ign=\"$(` line in %s, found %d" % (SCRIPT, len(line)))
    else:
        prog = line[0] + '\nprintf "%s" "$ign"\n'
        plain = subprocess.run(["bash", "-c", prog], capture_output=True, text=True).stdout.strip()
        withp = subprocess.run(wrapped("pipe_ign", ["bash", "-c", prog]), capture_output=True, text=True).stdout.strip()
        try:
            pv, wv = int(plain, 16), int(withp, 16)
        except ValueError:
            pv = wv = None
        if pv is not None and not bit(pv, signal.SIGPIPE) and bit(wv, signal.SIGPIPE):
            ok("[CENSUS] the entry-mask instrument reports SIGPIPE ignored only when the caller ignores it "
               "(default caller: %s; needle, ignoring caller: %s)" % (plain, withp))
        else:
            bad("[CENSUS] entry-mask instrument: default caller -> %r, ignoring caller -> %r -- it reports its own "
                "disposition instead of the caller's" % (plain, withp))
    # SIGCHLD in the gate: closed (never kept ignored -- it changes wait() semantics in the gate itself)
    nd = needle("chld_ign"); gv, rc = gate_view("chld_ign", nd.get("SigIgn"))
    if bit(int(nd.get("SigIgn", "0"), 16), signal.SIGCHLD) and rc == 0 and \
            not bit(int(gv.get("SigIgn", "0"), 16), signal.SIGCHLD):
        ok("[CENSUS] SIGCHLD ignored by the caller (needle) is reset to the default for the run role and the gate")
    else:
        bad("[CENSUS] SIGCHLD: needle=%s rc=%s gate SigIgn=%s" % (nd.get("SigIgn"), rc, gv.get("SigIgn")))
    # SIGTTIN/SIGTTOU: scoped out -- reset to the default, and the gate has NO controlling terminal
    # under the keeper's setsid, so the tty driver can never send it either signal
    nd = needle("tty_ign"); gv, rc = gate_view("tty_ign", nd.get("SigIgn"))
    if bit(int(nd.get("SigIgn", "0"), 16), signal.SIGTTOU) and rc == 0 and \
            not bit(int(gv.get("SigIgn", "0"), 16), signal.SIGTTOU) and \
            not bit(int(gv.get("SigIgn", "0"), 16), signal.SIGTTIN):
        ok("[CENSUS] SIGTTIN/SIGTTOU ignored by the caller (needle) are reset in the gate (scoped out of further "
           "handling: a replay gate runs in the keeper's own session, without a controlling terminal)")
    else:
        bad("[CENSUS] TTIN/TTOU: needle=%s rc=%s gate SigIgn=%s" % (nd.get("SigIgn"), rc, gv.get("SigIgn")))
    # SIGHUP: kept -- nohup means nohup (the stop matrix's nohup rows prove the tool behaviour)
    mk = os.path.join(d, "mk_hup")
    path = os.path.join(d, "gate_hup")
    nd = needle("hup_ign")
    p = subprocess.run(wrapped("hup_ign", ["python3", "-I", SUP, "run", "--timeout", "10", "--marker", mk, "--cwd", d,
                                           "--entry-sigign", "%x" % (1 << (signal.SIGHUP - 1)), "--", PROBE, path]),
                       capture_output=True, timeout=20)
    gv = parse_probe(path)
    if bit(int(nd.get("SigIgn", "0"), 16), signal.SIGHUP) and p.returncode == 0 and \
            bit(int(gv.get("SigIgn", "0"), 16), signal.SIGHUP):
        ok("[CENSUS] SIGHUP ignored at entry (nohup, needle) stays ignored in the gate -- kept by design")
    else:
        bad("[CENSUS] SIGHUP under nohup: needle=%s rc=%s gate SigIgn=%s" % (nd.get("SigIgn"), p.returncode, gv.get("SigIgn")))
    # a BLOCKED signal mask: closed -- the main supervisor unblocks everything once set up, so a
    # caller that blocked TERM cannot make the tool unstoppable by TERM
    nd = needle("term_blk")
    tmpd = os.path.join(d, "tblk"); os.makedirs(tmpd)
    p = subprocess.Popen(wrapped("term_blk", ["python3", "-I", SUP, "main", "--tmp-parent", tmpd, "--grace", "1", "--",
                                              "bash", "-c", 'exec -a "$0" sleep 600', MARK + "tblkworker"]),
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Synchronise on observable events, never on a sleep or a substring (flake root-caused 2026-10-09: the old
    # wait used procs_under(MARK+"tblkworker"), which matched the LAUNCHER -- its own argv carries that marker as
    # an argument (the §11.4.196(D) carrier footgun) -- so it returned ~40 ms after Popen and SigBlk was sampled
    # and TERM sent at an arbitrary start-up instant: 13/20 runs failed with rc -15 or a pre-reset SigBlk).
    # (1) the WORKER itself: argv[0] is exactly the marker only after `exec -a` (the launcher and the pre-exec
    #     bash both have other argv[0]), so it exists only once the keeper has spawned it;
    # (2) main past its set-up: TERM caught (SigCgt) AND no longer blocked (SigBlk) -- the state the case asserts.
    # Both waits are bounded: a supervisor that never unblocks / never catches TERM still reaches the TERM below
    # and fails the case (paired mutations R5-F1e / R5-F1i in test_fastcycle_r6_mutations.sh).
    tblk_worker = MARK + "tblkworker"
    end = time.monotonic() + 10
    while time.monotonic() < end and not [q for q in procs_under(tblk_worker) if q[1].split(" ", 1)[0] == tblk_worker]:
        time.sleep(0.05)
    end = time.monotonic() + 5
    while time.monotonic() < end:
        blk, cgt = status_mask(p.pid, "SigBlk"), status_mask(p.pid, "SigCgt")
        if blk is not None and not bit(blk, signal.SIGTERM) and bit(cgt, signal.SIGTERM):
            break
        time.sleep(0.02)
    blk, cgt = status_mask(p.pid, "SigBlk"), status_mask(p.pid, "SigCgt")
    sig_pid(p.pid, signal.SIGTERM)
    try:
        p.wait(timeout=15); rc = p.returncode
    except subprocess.TimeoutExpired:
        rc = None; sig_pid(p.pid, signal.SIGKILL); p.wait()
    left = procs_under(tblk_worker)
    for q, _ in left:
        sig_pid(q, signal.SIGKILL)
    if not bit(int(nd.get("SigBlk", "0"), 16), signal.SIGTERM):
        bad("[CENSUS] blocked TERM: control needle failed (SigBlk=%s)" % nd.get("SigBlk"))
    elif rc == 143 and not bit(blk, signal.SIGTERM) and not left:
        ok("[CENSUS] a caller that BLOCKED SIGTERM (needle) cannot make the tool unstoppable: main unblocked it "
           "(SigBlk=%x) and TERM stopped the tool (rc 143, nothing left)" % (blk or 0))
    else:
        # round 6, F7: name the MEASURED cause (the masks were read just before TERM was sent), never one fixed
        # guess -- a missing handler and a blocked mask fail this case for different reasons
        if blk is None or cgt is None:
            cause = "main was gone before its signal masks could be read"
        elif bit(blk, signal.SIGTERM):
            cause = "the inherited mask kept TERM blocked in main"
        elif not bit(cgt, signal.SIGTERM):
            cause = "no TERM handler in main (SigCgt has no TERM bit) -- TERM ended it by its default action"
        elif rc is None:
            cause = "main caught TERM with an empty mask but did not exit within 15 s"
        elif left:
            cause = "processes were left after the stop"
        else:
            cause = "main exited %s instead of the handled 143" % rc
        bad("[CENSUS] blocked TERM: %s (SigBlk=%s SigCgt=%s rc=%s left=%s)"
            % (cause, None if blk is None else "%x" % blk, None if cgt is None else "%x" % cgt, rc, bool(left)))
    # an inherited fd: scoped out by design (a gate may legitimately use what its caller passed, e.g. a
    # make jobserver), but bounded -- a descendant holding the caller's pipe is stopped before `run`
    # returns, so the caller's reader sees EOF and never hangs on the tool
    nd = needle("fd7", extra_fd=True)
    rfd, wfd = os.pipe()
    if wfd != 7:
        os.dup2(wfd, 7); os.close(wfd)
    mk = os.path.join(d, "mk_fd7")
    holder = os.path.join(d, "holder.sh")
    open(holder, "w").write('#!/bin/bash\n( setsid bash -c \'exec -a "$0" sleep 600\' %sfd7holder & )\nexit 0\n' % MARK)
    os.chmod(holder, 0o755)
    p = subprocess.Popen(wrapped("fd7", ["python3", "-I", SUP, "run", "--timeout", "10", "--grace", "1", "--marker", mk,
                                         "--cwd", d, "--", holder]), pass_fds=(7,), stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
    os.close(7)
    p.wait(timeout=20)
    rr, _, _ = select.select([rfd], [], [], 5)
    eof = bool(rr) and os.read(rfd, 1) == b""
    os.close(rfd)
    left = procs_under(MARK + "fd7holder")
    for q, _ in left:
        sig_pid(q, signal.SIGKILL)
    if "7" not in nd.get("FDS", "").split():
        bad("[CENSUS] inherited fd: control needle failed (fd 7 not passed: %s)" % nd.get("FDS"))
    elif p.returncode == 0 and eof and not left:
        ok("[CENSUS] an inherited pipe fd (needle: fd 7 open in a probe) held by a daemon the gate started is "
           "released when `run` returns (the caller's reader got EOF) -- scoped out of closing, bounded by the stop")
    else:
        bad("[CENSUS] inherited fd: rc=%s reader-EOF=%s holder-left=%s -- a descendant kept the caller's pipe open"
            % (p.returncode, eof, bool(left)))
    # umask: closed -- an umask that masks the OWNER's bits would make every file the tool creates
    # unusable (and could leave an undeletable checkout); refused up front, BLIND, before anything is created
    nd = needle("umask277")
    tmpu = os.path.join(d, "umask"); os.makedirs(tmpu)
    p = subprocess.run(wrapped("umask277", ["python3", "-I", SUP, "main", "--tmp-parent", tmpu, "--", "true"]),
                       capture_output=True, text=True, timeout=20)
    if nd.get("UMASK") != "0277":
        bad("[CENSUS] umask: control needle failed (umask %s)" % nd.get("UMASK"))
    elif p.returncode == 4 and "umask" in p.stderr and not os.listdir(tmpu):
        ok("[CENSUS] an umask masking the owner's bits (needle: 0277) is refused up front (exit 4 BLIND, nothing created)")
    else:
        bad("[CENSUS] umask 0277: rc=%s created=%s (%s)" % (p.returncode, os.listdir(tmpu), p.stderr.strip()[-160:]))
    # environment: scoped out (passed through on purpose -- the gate runs in the caller's environment);
    # the hand-off variables are the one hazard: a stale FC_BR_SUPERVISED=1 must never make a fresh
    # invocation run unsupervised
    env = dict(os.environ, FC_BR_SUPERVISED="1", TMPDIR=d)
    env.pop("FC_OUT", None)
    p = subprocess.run(["bash", SCRIPT, "selfcheck", "--out", os.path.join(d, "sc.json")], env=env,
                       capture_output=True, text=True, timeout=60)
    if p.returncode == 4 and "refusing to run unsupervised" in p.stderr and not os.path.exists(os.path.join(d, "sc.json")):
        ok("[CENSUS] a stale FC_BR_SUPERVISED=1 in the caller's environment is refused (exit 4), never a run "
           "without the supervisor")
    else:
        bad("[CENSUS] stale FC_BR_SUPERVISED: rc=%s (%s)" % (p.returncode, p.stderr.strip()[-160:]))

# =============================================================================
# ROUND 6 (independent review of the V4 round-5 pack, NO-GO 1 IMPORTANT + 7 MINOR)
# =============================================================================
TERM_BIT = "%x" % (1 << (signal.SIGTERM - 1))


def wait_exact_argv0(name, secs):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        if [q for q in procs_under(name) if q[1].split(" ", 1)[0] == name]:
            return True
        time.sleep(0.05)
    return False


def wait_caught(pid, signo, secs):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        blk, cgt = status_mask(pid, "SigBlk"), status_mask(pid, "SigCgt")
        if blk is not None and not bit(blk, signo) and bit(cgt, signo):
            return True
        time.sleep(0.02)
    return False


# F1 (IMPORTANT): a caller that IGNORES TERM, and a stop signal main catches (INT): main must forward the signal
# it RECEIVED -- the keeper inherits main's dispositions, so it handles exactly what main handles. b61583e-v4r5
# forwarded a fixed SIGTERM, which the keeper keeps ignored (nohup semantics): the stop was dropped and main
# waited out its keeper deadline (grace + 5 + 30 s), then SIGKILLed the keeper (reviewer: 36.4 s, rc 130).
if want("F1TERMIGN"):
    d = os.path.join(WORK, "f1ti"); os.makedirs(os.path.join(d, "tmp"))
    subprocess.run(wrapped("term_ign", [PROBE, os.path.join(d, "needle")]))
    nd = parse_probe(os.path.join(d, "needle"))
    worker = MARK + "tiworker"
    p = subprocess.Popen(wrapped("term_ign", ["python3", "-I", SUP, "main", "--tmp-parent", os.path.join(d, "tmp"),
                                              "--grace", "1", "--entry-sigign", TERM_BIT, "--",
                                              "bash", "-c", 'exec -a "$0" sleep 600', worker]),
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    ready = wait_exact_argv0(worker, 10) and wait_caught(p.pid, signal.SIGINT, 5)
    t0 = time.monotonic()
    sig_pid(p.pid, signal.SIGINT)
    try:
        _, err = p.communicate(timeout=60); rc = p.returncode
    except subprocess.TimeoutExpired:
        sig_pid(p.pid, signal.SIGKILL); _, err = p.communicate(); rc = None
    dt = time.monotonic() - t0
    left = procs_under(worker)
    for q, _ in left:
        sig_pid(q, signal.SIGKILL)
    if not bit(int(nd.get("SigIgn", "0"), 16), signal.SIGTERM) or not ready:
        bad("[F1TERMIGN] control needle/setup: TERM ignored in a probe=%s, worker + main INT handler ready=%s"
            % (nd.get("SigIgn"), ready))
    elif rc == 130 and dt < 8.0 and "did not finish its stop in time" not in err and not left:
        ok("[F1TERMIGN] caller ignores TERM (needle SigIgn=%s), SIGINT to main: forwarded as INT, the keeper stopped "
           "the tree in %.1fs, rc 130, no keeper-deadline kill, nothing left" % (nd.get("SigIgn"), dt))
    else:
        bad("[F1TERMIGN] caller ignores TERM, SIGINT to main: rc=%s after %.1fs, keeper-deadline message=%s, left=%s "
            "-- the forwarded stop was one the keeper ignores" % (rc, dt, "did not finish its stop" in err, bool(left)))

# F1, the LATE forward (a stop that reached main before its keeper existed): forced deterministically -- a driver
# raises SIGINT in main right after main installed its handlers (before the block and the fork), so Stop.sig is set
# while there is no keeper to forward to; main must forward THAT signal once the keeper exists.
if want("F1LATE"):
    d = os.path.join(WORK, "f1late"); os.makedirs(os.path.join(d, "tmp"))
    flag = os.path.join(d, "raised")
    drv = os.path.join(d, "drive.py")
    open(drv, "w").write(
        "import importlib.util, signal, sys\n"
        "spec = importlib.util.spec_from_file_location('fcsup', %r)\n"
        "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
        "orig, done = m._install_stop, [0]\n"
        "def hooked(mask):\n"
        "    orig(mask)\n"
        "    if done[0] == 0:\n"
        "        done[0] = 1\n"
        "        signal.raise_signal(signal.SIGINT)\n"
        "        open(%r, 'w').write('sig=%%d target=%%r' %% (m.Stop.sig, m.Stop.target_fd))\n"
        "m._install_stop = hooked\n"
        "sys.argv = ['fc_supervisor.py'] + sys.argv[1:]\n"
        "m.main()\n" % (SUP, flag))
    worker = MARK + "lateworker"
    t0 = time.monotonic()
    p = subprocess.Popen(wrapped("term_ign", ["python3", "-I", drv, "main", "--tmp-parent", os.path.join(d, "tmp"),
                                              "--grace", "1", "--entry-sigign", TERM_BIT, "--",
                                              "bash", "-c", 'exec -a "$0" sleep 600', worker]),
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    try:
        _, err = p.communicate(timeout=60); rc = p.returncode
    except subprocess.TimeoutExpired:
        sig_pid(p.pid, signal.SIGKILL); _, err = p.communicate(); rc = None
    dt = time.monotonic() - t0
    left = procs_under(worker)
    for q, _ in left:
        sig_pid(q, signal.SIGKILL)
    raised = readf(flag)
    if raised != "sig=2 target=None":
        bad("[F1LATE] control needle: the stop was not raised before the keeper existed (flag %r) -- the late "
            "forward is not exercised" % raised)
    elif rc == 130 and dt < 8.0 and "did not finish its stop in time" not in err and not left:
        ok("[F1LATE] a SIGINT that reached main before its keeper existed (needle: %s) is forwarded as INT once the "
           "keeper exists: rc 130 in %.1fs, nothing left" % (raised, dt))
    else:
        bad("[F1LATE] early SIGINT, caller ignores TERM: rc=%s after %.1fs, keeper-deadline message=%s, left=%s -- the "
            "late forward sent a signal the keeper ignores" % (rc, dt, "did not finish its stop" in err, bool(left)))

# F8: a stop signal that reaches main AFTER the keeper exited 0 (the worker finished: its report is written) must not
# turn the exit code into 128+N, which is documented as "stopped -- no report written". Forced deterministically: a
# driver raises SIGINT in main from inside main's own teardown, i.e. after the keeper's status was collected.
if want("F8LATE"):
    d = os.path.join(WORK, "f8late"); os.makedirs(os.path.join(d, "tmp"))
    flag = os.path.join(d, "raised")
    drv = os.path.join(d, "drive.py")
    open(drv, "w").write(
        "import importlib.util, signal, sys\n"
        "spec = importlib.util.spec_from_file_location('fcsup', %r)\n"
        "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
        "orig = m.teardown\n"
        # round 9: teardown gained a 5th argument (the state directory, V4R9-1) -- the hook passes every argument on
        "def hooked(tmpdir, grace, reason, label, *rest):\n"
        "    if label == 'main':\n"
        "        signal.raise_signal(signal.SIGINT)\n"
        "        open(%r, 'w').write('%%s|sig=%%d' %% (reason, m.Stop.sig))\n"
        "    return orig(tmpdir, grace, reason, label, *rest)\n"
        "m.teardown = hooked\n"
        "sys.argv = ['fc_supervisor.py'] + sys.argv[1:]\n"
        "m.main()\n" % (SUP, flag))
    p = subprocess.run(["python3", "-I", drv, "main", "--tmp-parent", os.path.join(d, "tmp"), "--grace", "1", "--",
                        "true"], capture_output=True, text=True, timeout=60)
    raised = readf(flag)
    if raised != "the keeper exited 0|sig=2":
        bad("[F8LATE] control needle: the SIGINT was not raised after the keeper exited 0 (flag %r)" % raised)
    elif p.returncode == 0 and not os.listdir(os.path.join(d, "tmp")):
        ok("[F8LATE] a stop that reached main after the keeper exited 0 (needle: %s) leaves the exit code 0 -- 128+N "
           "stays reserved for a stop that reached the work before it finished" % raised)
    else:
        bad("[F8LATE] stop after the keeper exited 0: main rc=%s (want 0: the work finished, its report is written; "
            "128+N says 'no report') tmp=%s" % (p.returncode, os.listdir(os.path.join(d, "tmp"))))

# F5 / reviewer mutant X2: the umask pre-flight must refuse EVERY umask that masks an owner bit (not only 0277, whose
# write bit alone satisfied a mutated `um & 0o200`), and must accept umasks that leave the owner's bits alone.
if want("UMASKS"):
    d = os.path.join(WORK, "umasks"); os.makedirs(d)
    for um, refuse in (("0100", True), ("0400", True), ("0177", True), ("0700", True),
                       ("0022", False), ("0077", False), ("0007", False)):
        # needle through stdout, not a file: under an umask masking the owner's READ bit the probe could not read
        # back a file it created (first run of this case: the file needle read None for 0400 / 0700)
        got = subprocess.run(wrapped("umask=" + um, ["python3", "-I", "-c", "import os; print('%04o' % os.umask(0))"]),
                             capture_output=True, text=True).stdout.strip()
        tmpu = os.path.join(d, "t" + um); os.makedirs(tmpu)
        p = subprocess.run(wrapped("umask=" + um, ["python3", "-I", SUP, "main", "--tmp-parent", tmpu, "--", "true"]),
                           capture_output=True, text=True, timeout=30)
        created = os.listdir(tmpu)
        if got != um:
            bad("[UMASKS] control needle: umask %s was not in effect (probe saw %s)" % (um, got))
        elif refuse and p.returncode == 4 and "umask" in p.stderr and not created:
            ok("[UMASKS] umask %s (masks an owner bit; needle %s) is refused up front: exit 4 BLIND, nothing created"
               % (um, got))
        elif not refuse and p.returncode == 0 and not created:
            ok("[UMASKS] umask %s (owner bits untouched; needle %s) is accepted: the tool ran, rc 0, its temp dir "
               "removed" % (um, got))
        else:
            bad("[UMASKS] umask %s: rc=%s created=%s want %s (%s)" % (um, p.returncode, created,
                                                                   "refused (4)" if refuse else "accepted (0)",
                                                                   p.stderr.strip()[-160:]))

# F5 / reviewer mutant X3: a STOPPED leftover (SIGSTOP) is stopped promptly -- TERM stays pending on a stopped
# process, so stop_tree must also send SIGCONT; without it the leftover waits for the KILL after the whole grace.
if want("STOPCONT"):
    d = os.path.join(WORK, "stopcont"); os.makedirs(d)
    state = os.path.join(d, "state")
    gate = os.path.join(d, "gate.sh")
    open(gate, "w").write(
        "#!/bin/bash\n"
        "bash -c 'exec -a \"$0\" sleep 600' %sstopped &\n"
        "c=$!\n"
        "case \"$c\" in ''|*[!0-9]*) exit 3 ;; esac\n"
        "[ \"$c\" -gt 1 ] || exit 3\n"
        "kill -STOP \"$c\"\n"
        "for _ in $(seq 1 200); do st=\"$(sed 's/.*) //' \"/proc/$c/stat\" | cut -d' ' -f1)\"; [ \"$st\" = T ] && break; sleep 0.01; done\n"
        "echo \"$st\" >%s\n"
        "exit 0\n" % (MARK, state))
    os.chmod(gate, 0o755)
    mk, tm = os.path.join(d, "m"), os.path.join(d, "t")
    rc, out, err, dt = run_sup(["run", "--timeout", "20", "--grace", "6", "--marker", mk, "--timing", tm, "--cwd", d,
                                "--", gate], timeout=40)
    tv = dict(l.strip().split("=", 1) for l in open(tm) if "=" in l) if os.path.exists(tm) else {}
    left = procs_under(MARK + "stopped")
    for q, _ in left:
        sig_pid(q, signal.SIGKILL)
    stop_ms = int(tv.get("leftover_stop_ms", "99999"))
    if readf(state).strip() != "T":
        bad("[STOPCONT] control needle: the leftover was not in state T (stopped) before the run returned (%r)"
            % readf(state))
    elif rc == 0 and readf(mk) == "exited" and tv.get("leftover_processes") == "1" and stop_ms < 3000 and not left:
        ok("[STOPCONT] a SIGSTOPped leftover (needle: state T) is stopped in %d ms with --grace 6 (TERM + CONT), "
           "rc 0, nothing left" % stop_ms)
    else:
        bad("[STOPCONT] stopped leftover: rc=%s marker=%r timing=%r left=%s -- the TERM stayed pending on a stopped "
            "process until the KILL after the grace" % (rc, readf(mk), tv, bool(left)))

# F5 / reviewer mutant X8: the documented run-timeout exit codes -- 124 when the command ended on TERM, 137 when it
# ignored TERM and had to be KILLed (both: marker timed_out).
if want("TMO137"):
    d = os.path.join(WORK, "tmo137"); os.makedirs(d)
    ready = os.path.join(d, "ready")
    ign = ["python3", "-I", "-c", "import signal, sys, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
           "open(sys.argv[1], 'w').write('ignoring'); time.sleep(60)", ready]
    mk1, mk2 = os.path.join(d, "m1"), os.path.join(d, "m2")
    rc1, _, err1, dt1 = run_sup(["run", "--timeout", "3", "--kill-after", "1", "--grace", "1", "--marker", mk1,
                                 "--cwd", d, "--"] + ign, timeout=40)
    rc2, _, err2, dt2 = run_sup(["run", "--timeout", "1", "--kill-after", "1", "--grace", "1", "--marker", mk2,
                                 "--cwd", d, "--", "sleep", "60"], timeout=40)
    if readf(ready) != "ignoring":
        bad("[TMO137] control needle: the TERM-ignoring gate never confirmed it ignores TERM before the timeout")
    elif rc1 == 137 and readf(mk1) == "timed_out" and rc2 == 124 and readf(mk2) == "timed_out":
        ok("[TMO137] run timeout: a TERM-ignoring command (needle: it reported SIG_IGN) had to be KILLed -> rc 137; "
           "a TERM-honouring one -> rc 124; both marker timed_out (%.1fs / %.1fs)" % (dt1, dt2))
    else:
        bad("[TMO137] run timeout exit codes: ignoring TERM rc=%s marker=%r (want 137), honouring rc=%s marker=%r "
            "(want 124)" % (rc1, readf(mk1), rc2, readf(mk2)))

# F6: this file's own EXIT-trap cleanup must signal only processes this test MARKED (argv[0] starts with the
# marker) -- never a foreign process that merely names a path under $WORK (an observer `tail -f $WORK/x`).
if want("CLEANUP"):
    fn = subprocess.run(["sed", "-n", "/^cleanup() {/,/^}/p", TESTFILE], capture_output=True, text=True).stdout
    d = os.path.join(WORK, "cleanupcase"); os.makedirs(d)
    w2 = os.path.join(d, "w"); os.makedirs(w2)
    open(os.path.join(w2, "x"), "w").write("x\n")
    harness = (fn + '\nWORK="$1"\n'
               '( exec -a "v5t-$$-owned" sleep 300 ) & own=$!\n'
               'tail -f "$WORK/x" >/dev/null 2>&1 & obs=$!\n'
               'sleep 0.3\n'
               'o0=$(tr "\\0" " " </proc/$own/cmdline 2>/dev/null); b0=$(tr "\\0" " " </proc/$obs/cmdline 2>/dev/null)\n'
               'cleanup\n'
               'sleep 0.3\n'
               'state() { [ -r "/proc/$1/stat" ] && sed "s/.*) //" "/proc/$1/stat" | cut -d" " -f1; }\n'
               'echo "owned_before=$o0|"; echo "observer_before=$b0|"\n'
               'echo "owned_after=$(state $own)"; echo "observer_after=$(state $obs)"\n'
               'case "$obs" in ""|*[!0-9]*) ;; *) [ "$obs" -gt 1 ] && kill -KILL "$obs" 2>/dev/null ;; esac\n'
               'case "$own" in ""|*[!0-9]*) ;; *) [ "$own" -gt 1 ] && kill -KILL "$own" 2>/dev/null ;; esac\n'
               'wait 2>/dev/null\n')
    p = subprocess.run(["bash", "-c", harness, "x", w2], capture_output=True, text=True, timeout=30)
    res = dict(l.split("=", 1) for l in p.stdout.splitlines() if "=" in l)
    own_ok = res.get("owned_after", "") in ("", "Z")
    obs_ok = res.get("observer_after", "") not in ("", "Z")
    if not fn.strip() or "v5t-" not in res.get("owned_before", "") or w2 not in res.get("observer_before", ""):
        bad("[CLEANUP] setup/control needle: cleanup()=%s owned argv=%r observer argv=%r" %
            (bool(fn.strip()), res.get("owned_before"), res.get("observer_before")))
    elif own_ok and obs_ok:
        ok("[CLEANUP] the EXIT-trap cleanup killed the marked process (argv[0] v5t-...) and left a foreign observer "
           "naming a $WORK path (`tail -f $WORK/x`) running")
    else:
        bad("[CLEANUP] cleanup: marked process state after=%r (want gone), foreign observer state after=%r (want alive) "
            "-- the cleanup %s" % (res.get("owned_after"), res.get("observer_after"),
                                   "killed a foreign process" if not obs_ok else "left its own marked process"))

# =============================================================================
# ROUND 7 (independent review of the round-6 pack: NO-GO 1 IMPORTANT + 6 MINOR; two finding CLASSES recur and are
# closed STRUCTURALLY -- §11.4.276(E)). Every case was written RED-first against the round-6 code (md5 df625dd2).
#   CLASS 1 (signal ownership): main runs in the CALLER's pid; what the caller started before `exec` (a background
#   job, a `> >(tee log)` logger) must never be stopped, and neither must anything main cannot attribute to the replay.
#   CLASS 2 (exit code / report consistency): every exit of main goes through one table (main_exit_code) whose rows
#   are each tested below with stderr open AND closed; the worker keeps its run-log ledger entries until the report is
#   written and then writes a `done` marker the keeper honours (round 8, V4R8-2: replaced -- the keeper and main
#   decide "report written" from the report-pending marker + the report on disk; see the R8N3* rows).
# =============================================================================
LOGGER = os.path.join(WORK, "logger.py")
open(LOGGER, "w").write(r'''
import os, signal, sys, time
log = sys.argv[1]
def rec(s, f):
    with open(log + ".sig", "a") as fh:
        fh.write("SIG%d\n" % s)
for s in (signal.SIGHUP, signal.SIGINT, signal.SIGQUIT, signal.SIGTERM):
    signal.signal(s, rec)
out = open(log, "ab", buffering=0)
while True:
    b = os.read(0, 65536)
    if not b:
        break
    out.write(b)
time.sleep(0.5)
open(log + ".eof", "w").write("EOF-OK")
''')


def wait_path(path, secs):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        if os.path.exists(path):
            return True
        time.sleep(0.05)
    return False


def keeper_pid(main_pid, secs=10):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        ks = [c for c in children(main_pid) if comm(c) == "fc-keeper"]
        if ks:
            return ks[0]
        time.sleep(0.02)
    return None


def finish(p, secs):
    try:
        p.wait(timeout=secs)
        return p.returncode
    except subprocess.TimeoutExpired:
        sig_pid(p.pid, signal.SIGKILL); p.wait()
        return None


def kill_marked(prefix):
    for q, _ in procs_under(prefix):
        sig_pid(q, signal.SIGKILL)


def alive_pid(pid):
    try:
        st = open("/proc/%d/stat" % pid).read()
        return st[st.rindex(") ") + 2:].split()[0] != "Z"
    except (OSError, ValueError):
        return False


# --- N1 (IMPORTANT), injection F: a child the CALLER started before `exec` (a background job) is a child of main.
# Round 6 stopped it on every run: main's teardown walked ALL its descendants. Required: it is never signalled --
# after a successful run (rc 0) AND after a stopped run (TERM to main, rc 143), it is still alive. Control needle: the
# pre-existing process IS main's child while main runs (otherwise the case proves nothing).
if want("R7N1F"):
    d = os.path.join(WORK, "r7n1f"); os.makedirs(d)
    for variant in ("success", "stopped", "replay"):
        dv = os.path.join(d, variant); os.makedirs(os.path.join(dv, "tmp"))
        pre = MARK + "pre" + variant
        prefile = os.path.join(dv, "prepid")
        if variant == "replay":
            repo = os.path.join(dv, "repo"); head = mk_repo(repo)
            os.makedirs(os.path.join(dv, "locks"))
            inner = ["bash", SCRIPT, "replay", "--commit", head, "--repo-root", repo, "--worktree-root",
                     os.path.join(dv, "wt"), "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd", "true",
                     "--cold-runs", "1", "--warm-runs", "0", "--out", os.path.join(dv, "out.json")]
        else:
            work = (["bash", "-c", "sleep 1"] if variant == "success"
                    else ["bash", "-c", 'exec -a "$0" sleep 600', MARK + "n1fw"])
            inner = ["python3", "-I", SUP, "main", "--tmp-parent", os.path.join(dv, "tmp"), "--grace", "1", "--"] + work
        env = dict(os.environ, TMPDIR=os.path.join(dv, "tmp"), FC_REPLAY_LOCK_DIR=os.path.join(dv, "locks"))
        env.pop("FC_OUT", None)
        # the job's own stdio goes to /dev/null and main's stderr to a FILE: a pipe the job inherited would keep
        # communicate() waiting for the job's natural end (first draft of this case: a 120 s wait read as "killed")
        errf = os.path.join(dv, "main.err")
        p = subprocess.Popen(["bash", "-c", '( exec -a "$1" sleep 120 ) >/dev/null 2>&1 </dev/null & echo $! >"$2"; '
                              'shift 2; exec "$@"', "x", pre, prefile] + inner, env=env, stdout=subprocess.DEVNULL,
                             stderr=open(errf, "w"))
        wait_path(prefile, 10)
        try:
            ppid_pre = int(readf(prefile).split()[0])
        except (ValueError, IndexError):
            ppid_pre = None
        needle = False
        end = time.monotonic() + 10
        while ppid_pre and time.monotonic() < end and not needle:
            needle = ppid(ppid_pre) == p.pid
            if not needle:
                time.sleep(0.02)
        if variant == "stopped":
            wait_exact_argv0(MARK + "n1fw", 10)
            wait_caught(p.pid, signal.SIGTERM, 5)
            sig_pid(p.pid, signal.SIGTERM)
        rc = finish(p, 120)
        err = readf(errf)
        time.sleep(0.3)
        pre_alive = bool(ppid_pre) and alive_pid(ppid_pre) and comm(ppid_pre) == "sleep"
        want_rc = 143 if variant == "stopped" else 0
        if ppid_pre:
            sig_pid(ppid_pre, signal.SIGKILL)
        kill_marked(MARK + "n1fw")
        if not needle:
            bad("[R7N1F] %s: control needle: the caller's background job (%s) was never main's child" % (variant, ppid_pre))
        elif rc == want_rc and pre_alive:
            ok("[R7N1F] %s: a job the caller started before exec (needle: main's child) survives the %s run, rc %d"
               % (variant, variant, rc))
        else:
            bad("[R7N1F] %s: rc=%s (want %d) caller's pre-existing job alive=%s -- main stopped a process it did not "
                "start (%s)" % (variant, rc, want_rc, pre_alive, (err or "").strip()[-200:]))

# --- N1, injections L / L2 / L3: `exec > >(logger)` / `exec 2> >(logger)` before the tool: the logger is the caller's
# process substitution, a pre-existing child of main. Round 6 TERMed then KILLed it at the end of a SUCCESSFUL run --
# the caller's log lost its tail and (with the stderr logger gone) main's own flush failed: rc 4 for a success (N2).
# Required: rc 0, the logger never got a signal, it saw EOF and finished by itself, and it holds the worker's output.
if want("R7N1L"):
    d = os.path.join(WORK, "r7n1l"); os.makedirs(d)
    for stream, redir in (("stdout", ">"), ("stderr", "2>")):
        dv = os.path.join(d, stream); os.makedirs(os.path.join(dv, "tmp"))
        log = os.path.join(dv, "log")
        sh = ('exec %s >(exec python3 -I "$1" "$2"); shift 2; exec "$@"' % redir)
        work = 'echo worker-said-hi-%s %s' % (stream, ">&2" if stream == "stderr" else "")
        p = subprocess.Popen(["bash", "-c", sh, "x", LOGGER, log, "python3", "-I", SUP, "main", "--tmp-parent",
                              os.path.join(dv, "tmp"), "--grace", "1", "--", "bash", "-c", work],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        rc = finish(p, 60)
        eof = wait_path(log + ".eof", 5)
        sigs = readf(log + ".sig").split()
        got = readf(log)
        if rc == 0 and eof and not sigs and ("worker-said-hi-%s" % stream) in got:
            ok("[R7N1L] %s: a `%s >(logger)` the caller set up before exec is never signalled: rc 0, the logger saw EOF "
               "and finished by itself, the worker's line is in the log" % (stream, redir))
        else:
            bad("[R7N1L] %s logger: rc=%s (want 0) logger EOF-finished=%s signals it received=%s line logged=%s -- main "
                "stopped (or lost the output of) a logger it did not start" % (stream, rc, eof, sigs,
                                                                               ("worker-said-hi-%s" % stream) in got))

# --- N2, injection L5: the keeper SIGKILLed while main's stderr is a pipe nobody reads any more. main's teardown
# message raised BrokenPipeError inside say() (caught), but the unwritten bytes stayed in the stream buffer and the
# unguarded final flush raised again: the catch-all turned the outcome (137) into 4 BLIND. Required: 137 and the
# worker's child stopped. Control needle: the stopped-process message really was attempted (the child existed).
if want("R7N2"):
    d = os.path.join(WORK, "r7n2"); os.makedirs(os.path.join(d, "tmp"))
    child = MARK + "n2child"
    p = subprocess.Popen(["python3", "-I", SUP, "main", "--tmp-parent", os.path.join(d, "tmp"), "--grace", "1", "--",
                          "bash", "-c", '( exec -a "$0" sleep 600 ) & wait', child],
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    p.stderr.close()                       # nobody reads main's stderr any more: every write is EPIPE
    k = keeper_pid(p.pid)
    up = wait_exact_argv0(child, 10)
    if k:
        sig_pid(k, signal.SIGKILL)
    rc = finish(p, 30)
    left = procs_under(child)
    kill_marked(child)
    if not (k and up):
        bad("[R7N2] setup: keeper=%s child up=%s" % (k, up))
    elif rc == 137 and not left:
        ok("[R7N2] keeper SIGKILLed with main's stderr a broken pipe: rc 137 (the keeper's fate), the orphaned child "
           "was stopped -- an unwritable stderr never changes the exit code")
    else:
        bad("[R7N2] keeper SIGKILLed, stderr broken: rc=%s (want 137) child left=%s -- a failed flush became the exit "
            "code" % (rc, bool(left)))

# --- CLASS 2 table: one row per path to main's exit code (outcome x stop signal x stderr state). Each row drives
# the REAL main role; stderr is either an open pipe or a pipe whose read end is closed. A row's code must never
# depend on the stderr state, and nothing outside the documented set {0,1,2,3,4,128+N} may come out.
def table_drv(path, patch):
    drv = path + ".drive.py"
    open(drv, "w").write(
        "import importlib.util, os, signal, sys, time\n"
        "spec = importlib.util.spec_from_file_location('fcsup', %r)\n"
        "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
        "MAIN = os.getpid()\n"
        "%s\n"
        "sys.argv = ['fc_supervisor.py'] + sys.argv[1:]\n"
        "m.main()\n" % (SUP, patch))
    return drv


TABLE = [
    # (row, driver patch, worker argv, action, want rc)
    ("exited-0", "", ["true"], None, 0),
    ("exited-3", "", ["bash", "-c", "exit 3"], None, 3),
    ("exited-undocumented-70", "", ["bash", "-c", "exit 70"], None, 4),
    # round 8 (V4R8-5): reviewer mutant DOC128 adopted -- the documented range starts at 129 (128 is no signal)
    ("exited-undocumented-128", "", ["bash", "-c", "exit 128"], None, 4),
    ("keeper-internal-error", "m.spawn = lambda *a, **k: (_ for _ in ()).throw(RuntimeError('injected'))",
     ["true"], None, 4),
    ("keeper-lost-worker-status",
     "_r, _rt = m.reap, m.reap_target\n"
     "def reap():\n    return None if os.getpid() != MAIN else _r()\n"
     "def reap_target(pid):\n    return 'lost' if os.getpid() != MAIN else _rt(pid)\n"
     "m.reap, m.reap_target = reap, reap_target",
     ["bash", "-c", "sleep 0.3"], None, 4),
    ("keeper-killed-no-stop", "", ["bash", "-c", 'exec -a "$0" sleep 600', MARK + "tblw"], "killkeeper", 137),
    ("keeper-deadline-after-TERM",
     "m.KILL_WAIT_S = 1.0\nif hasattr(m, 'KEEPER_SLACK_S'): m.KEEPER_SLACK_S = 1.0",
     ["bash", "-c", 'exec -a "$0" sleep 600', MARK + "tblw"], "stopkeeper-term", 143),
    ("main-exception-after-start", "m.children_probe = lambda: (_ for _ in ()).throw(RuntimeError('injected'))",
     ["true"], None, 4),
]
if want("R7TABLE"):
    d = os.path.join(WORK, "r7table"); os.makedirs(d)
    for row, patch, work, action, want_rc in TABLE:
        for stderr_state in ("open", "closed"):
            dv = os.path.join(d, "%s-%s" % (row, stderr_state)); os.makedirs(os.path.join(dv, "tmp"))
            drv = table_drv(dv, patch)
            p = subprocess.Popen(["python3", "-I", drv, "main", "--tmp-parent", os.path.join(dv, "tmp"), "--grace", "0",
                                  "--"] + work, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            if stderr_state == "closed":
                p.stderr.close()
            needle = True
            if action:
                k = keeper_pid(p.pid)
                needle = bool(k) and wait_exact_argv0(MARK + "tblw", 10)
                if action == "killkeeper" and k:
                    sig_pid(k, signal.SIGKILL)
                elif action == "stopkeeper-term" and k:
                    sig_pid(k, signal.SIGSTOP)
                    wait_caught(p.pid, signal.SIGTERM, 5)
                    sig_pid(p.pid, signal.SIGTERM)
            rc = finish(p, 40)
            err = "" if stderr_state == "closed" else p.stderr.read().decode(errors="replace")
            if stderr_state == "open":
                p.stderr.close()
            left = procs_under(MARK + "tblw")
            kill_marked(MARK + "tblw")
            tag = "[R7TABLE] %s stderr-%s" % (row, stderr_state)
            if not needle:
                bad("%s: setup: the keeper/worker never appeared" % tag)
            elif rc == want_rc and not left and "Traceback" not in err:
                ok("%s: rc %d, nothing left" % (tag, rc))
            else:
                bad("%s: rc=%s (want %d) left=%s traceback=%s" % (tag, rc, want_rc, bool(left), "Traceback" in err))

# --- N3: a stop that reaches the tool after the runs but BEFORE the report is written. Round 6 dropped the run-log
# ledger entry in do_one_replay, i.e. before emit_doc: the stop gave rc 130 with no report and a log directory that
# nothing explains (no INTERRUPTED). Forced deterministically: a `python3` shim on PATH holds the report writer (the
# fc_common.py emit call) and announces it; the test then sends SIGINT to main.
# --- N3b (the done marker): a stop that reaches the tool after the report WAS written but before the worker exited
# keeps the worker's exit code (the report exists; 128+N says "no report"). The shim lets the real emit finish,
# signals main itself, and exits with the emit's status.
# Round 8 (V4R8-3): round 7's "after" shim ran `trap '' TERM INT HUP QUIT` right after the real emit -- the report
# writer was then IMMUNE during exactly the window between its rename and its exit, so V4R8-2 (a stop in that window
# turned a written report into "no report") could never appear. The trap is gone: the keeper's stop TERMs the shim
# (the writer) after its rename, which is the reviewer's failure mode, and the CORRECT outcome is pinned (rc 0, the
# report, no INTERRUPTED). Modes (all after the REAL emit, except `before`):
#   before   announce, hold 5 s, then the real emit (a stop lands BEFORE the report exists)
#   after    SIGINT to main, hold 1 s (the keeper's stop kills the writer after its rename)
#   check    the emit is untouched; `report-check` (the worker's question "was it written?") writes a durable
#            readiness marker FIRST, then SIGINTs main, then holds 3 s -- the keeper's stop kills it (V4R8-4: the stop
#            is injected only after the marker exists, so the case cannot race)
#   termgrp  SIGTERM to the worker's whole process group (the reviewer's natural injection, made deterministic)
#   killw    SIGKILL to the worker (between the report and the worker's exit)
#   killk    SIGKILL to the keeper (the worker then dies by its parent-death signal)
def py_shim(case, mode):
    shim = os.path.join(case, "pyshim"); os.makedirs(shim)
    real = shutil.which("python3")
    open(os.path.join(shim, "python3"), "w").write(r'''#!/bin/bash
statf() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f"$2"; }
find_keeper() {   # walk up from this shim to the fc-keeper (pid on stdout)
  local p=$PPID
  for _ in 1 2 3 4 5 6; do
    case "$p" in ''|*[!0-9]*) return 1 ;; esac
    [ "$p" -gt 1 ] || return 1
    [ "$(cat "/proc/$p/comm" 2>/dev/null)" = fc-keeper ] && { echo "$p"; return 0; }
    p=$(statf "$p" 2)
  done
  return 1
}
int_main() {
  local k m
  k=$(find_keeper) || return 1
  m=$(statf "$k" 2)
  case "$m" in ''|*[!0-9]*) return 1 ;; esac
  [ "$m" -gt 1 ] && [ "$(cat "/proc/$m/comm" 2>/dev/null)" = fc-supervisor ] && { echo "$m" >"%(case)s/signalled"; kill -INT "$m"; }
}
case "$*" in
  *fc_supervisor.py\ report-check*)
    if [ "%(mode)s" = check ]; then
      echo held >"%(case)s/checkheld"
      int_main
      sleep 3
    fi
    exec %(real)s "$@" ;;
  *fc_common.py\ emit*)
    if [ "%(mode)s" = before ]; then
      echo emitting >"%(case)s/emitting"
      sleep 5
      exec %(real)s "$@"
    fi
    %(real)s "$@"
    rc=$?
    w=$PPID
    case "%(mode)s" in
      after) int_main ;;
      termgrp)
        g=$(statf "$w" 3)      # the process group (fields after ") ": state ppid pgrp ...)
        if [ "$g" = "$w" ] && [ "$w" -gt 1 ] && [ "$(cat "/proc/$w/comm" 2>/dev/null)" = bash ]; then
          echo "$w" >"%(case)s/signalled"; kill -TERM -- "-$g"
        fi ;;
      killw)
        if [ "$w" -gt 1 ] && [ "$(cat "/proc/$w/comm" 2>/dev/null)" = bash ]; then
          echo "$w" >"%(case)s/signalled"; kill -KILL "$w"
        fi ;;
      killk)
        k=$(find_keeper) && [ "$k" -gt 1 ] && { echo "$k" >"%(case)s/signalled"; kill -KILL "$k"; } ;;
    esac
    sleep 1
    exit "$rc" ;;
esac
exec %(real)s "$@"
''' % {"mode": mode, "case": case, "real": real})
    os.chmod(os.path.join(shim, "python3"), 0o755)
    return shim


if want("R7N3"):
    case = os.path.join(WORK, "r7n3"); os.makedirs(case)
    repo = os.path.join(case, "repo"); head = mk_repo(repo)
    shim = py_shim(case, "before")
    wtr = os.path.join(case, "wt")
    env = dict(os.environ, PATH=shim + ":" + os.environ["PATH"], TMPDIR=os.path.join(case, "tmp"),
               FC_REPLAY_LOCK_DIR=os.path.join(case, "locks"))
    env.pop("FC_OUT", None)
    os.makedirs(os.path.join(case, "tmp")); os.makedirs(os.path.join(case, "locks"))
    p = subprocess.Popen(["bash", SCRIPT, "replay", "--commit", head, "--repo-root", repo, "--worktree-root", wtr,
                          "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd", "true", "--cold-runs", "1",
                          "--warm-runs", "0", "--out", os.path.join(case, "out.json")], env=env,
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    held = wait_path(os.path.join(case, "emitting"), 60)
    if held:
        sig_pid(p.pid, signal.SIGINT)
    try:
        _, err = p.communicate(timeout=60); rc = p.returncode
    except subprocess.TimeoutExpired:
        sig_pid(p.pid, signal.SIGKILL); _, err = p.communicate(); rc = None
    ld = os.path.join(wtr, "replay-logs")
    logdirs = sorted(os.listdir(ld)) if os.path.isdir(ld) else []
    interrupted = [x for x in logdirs if os.path.exists(os.path.join(ld, x, "INTERRUPTED"))]
    report = os.path.exists(os.path.join(case, "out.json"))
    tmpleft = os.listdir(os.path.join(case, "tmp"))
    if not held:
        bad("[R7N3] control needle: the report writer was never reached (%s)" % err.strip()[-200:])
    elif rc == 130 and not report and logdirs and interrupted == logdirs and not tmpleft:
        ok("[R7N3] SIGINT while the report writer was held (needle: it announced itself): rc 130, no report, the run-log "
           "directory is marked INTERRUPTED, temp dir gone")
    else:
        bad("[R7N3] stop before the report: rc=%s report=%s log dirs=%s INTERRUPTED=%s temp=%s -- the ledger entry was "
            "dropped before the report existed" % (rc, report, logdirs, interrupted, tmpleft))

if want("R7N3B"):
    case = os.path.join(WORK, "r7n3b"); os.makedirs(case)
    repo = os.path.join(case, "repo"); head = mk_repo(repo)
    shim = py_shim(case, "after")
    wtr = os.path.join(case, "wt")
    env = dict(os.environ, PATH=shim + ":" + os.environ["PATH"], TMPDIR=os.path.join(case, "tmp"),
               FC_REPLAY_LOCK_DIR=os.path.join(case, "locks"))
    env.pop("FC_OUT", None)
    os.makedirs(os.path.join(case, "tmp")); os.makedirs(os.path.join(case, "locks"))
    p = subprocess.run(["bash", SCRIPT, "replay", "--commit", head, "--repo-root", repo, "--worktree-root", wtr,
                        "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd", "true", "--cold-runs", "1",
                        "--warm-runs", "0", "--out", os.path.join(case, "out.json")], env=env, capture_output=True,
                       text=True, timeout=120)
    ld = os.path.join(wtr, "replay-logs")
    logdirs = sorted(os.listdir(ld)) if os.path.isdir(ld) else []
    interrupted = [x for x in logdirs if os.path.exists(os.path.join(ld, x, "INTERRUPTED"))]
    report = os.path.exists(os.path.join(case, "out.json"))
    signalled = readf(os.path.join(case, "signalled")).strip()
    if not signalled:
        bad("[R7N3B] control needle: the shim never signalled main after the report was written (%s)"
            % p.stderr.strip()[-200:])
    elif p.returncode == 0 and report and logdirs and not interrupted and not os.listdir(os.path.join(case, "tmp")):
        ok("[R7N3B] SIGINT to main (needle: pid %s) after the report was written, before the worker exited: rc 0 (the "
           "work finished, the report exists), the run-log directory is not marked INTERRUPTED" % signalled)
    else:
        bad("[R7N3B] stop after the report: rc=%s (want 0) report=%s INTERRUPTED=%s -- the exit code says 'no report' "
            "although the report was written" % (p.returncode, report, interrupted))

# --- N3c (found by the round-7 suite itself: iteration 1 of the full v4r5 run, R7N3B rc 130 with the report written):
# the keeper stopping the tree TERMs every CHILD of the finishing worker; an external command in the finish sequence
# could be killed by it. Round 8 (V4R8-4): round 7's version held an `rm` shim and injected the stop from ANOTHER
# command, so the keeper's stop could kill the `rm` shim before it recorded that it was held (3 of 10 isolated runs
# failed the control needle on unmodified code). Now the held command is the worker's own `report-check` and the SAME
# shim writes its readiness marker BEFORE it injects the stop (SIGINT to main) -- the stop cannot precede the marker.
# Required: the report exists and the keeper (which re-reads the durable report state) keeps rc 0, no INTERRUPTED.
if want("R7N3C"):
    case = os.path.join(WORK, "r7n3c"); os.makedirs(case)
    repo = os.path.join(case, "repo"); head = mk_repo(repo)
    shim = py_shim(case, "check")
    wtr = os.path.join(case, "wt")
    env = dict(os.environ, PATH=shim + ":" + os.environ["PATH"], TMPDIR=os.path.join(case, "tmp"),
               FC_REPLAY_LOCK_DIR=os.path.join(case, "locks"))
    env.pop("FC_OUT", None)
    os.makedirs(os.path.join(case, "tmp")); os.makedirs(os.path.join(case, "locks"))
    p = subprocess.run(["bash", SCRIPT, "replay", "--commit", head, "--repo-root", repo, "--worktree-root", wtr,
                        "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd", "true", "--cold-runs", "1",
                        "--warm-runs", "0", "--out", os.path.join(case, "out.json")], env=env, capture_output=True,
                       text=True, timeout=120)
    ld = os.path.join(wtr, "replay-logs")
    logdirs = sorted(os.listdir(ld)) if os.path.isdir(ld) else []
    interrupted = [x for x in logdirs if os.path.exists(os.path.join(ld, x, "INTERRUPTED"))]
    report = os.path.exists(os.path.join(case, "out.json"))
    if not readf(os.path.join(case, "signalled")).strip() or not readf(os.path.join(case, "checkheld")).strip():
        bad("[R7N3C] control needle: signalled=%r report-check held=%r (%s)" % (
            readf(os.path.join(case, "signalled")).strip(), readf(os.path.join(case, "checkheld")).strip(),
            p.stderr.strip()[-200:]))
    elif p.returncode == 0 and report and logdirs and not interrupted and not os.listdir(os.path.join(case, "tmp")):
        ok("[R7N3C] the keeper's stop killed the worker's held `report-check` (needle: it marked itself held, then "
           "injected the stop) after the report: rc 0, the run-log directory is not marked INTERRUPTED (the keeper "
           "decides from the durable report state)")
    else:
        bad("[R7N3C] stop during the finish sequence: rc=%s (want 0) report=%s INTERRUPTED=%s" %
            (p.returncode, report, interrupted))

# --- ROUND 8 (V4R8-2, STRUCTURAL): "was the report written?" decided from DURABLE state. Each row writes the REAL
# report, then something happens before the worker exits; the report exists, so the replay's code is the report's
# (0) and its run-log directory is not marked INTERRUPTED. RED on round 7 (md5 ee73edfe / d0a657d9): termgrp rc 143
# (the reviewer's injection: 30/30), killw rc 137, killk rc 137 -- each with the report on disk and the directory
# marked INTERRUPTED with the false text "No report references this run-log directory".
#   R8N3TERMGRP  SIGTERM to the worker's process group right after the writer's rename (writer + worker die of it)
#   R8N3KILLW    SIGKILL to the worker after the report
#   R8N3KILLK    SIGKILL to the keeper after the report (the worker dies by its parent-death signal; main decides)
#   R8N3NAT      the reviewer's injection verbatim: TERM to the worker's process group the moment out.json appears
#                (3 runs; the oracle holds wherever in the window the signal lands)
#   R8N3STALE    the identity half of the rule: an IDENTICAL report already at --out (a selfcheck run twice) and a stop
#                BEFORE the writer starts -- the old file must not be read as "written": rc 130
def r8_replay(case, mode, gate="true"):
    repo = os.path.join(case, "repo"); head = mk_repo(repo)
    shim = py_shim(case, mode)
    wtr = os.path.join(case, "wt")
    env = dict(os.environ, PATH=shim + ":" + os.environ["PATH"], TMPDIR=os.path.join(case, "tmp"),
               FC_REPLAY_LOCK_DIR=os.path.join(case, "locks"))
    env.pop("FC_OUT", None)
    os.makedirs(os.path.join(case, "tmp")); os.makedirs(os.path.join(case, "locks"))
    p = subprocess.run(["bash", SCRIPT, "replay", "--commit", head, "--repo-root", repo, "--worktree-root", wtr,
                        "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd", gate, "--cold-runs", "1",
                        "--warm-runs", "0", "--out", os.path.join(case, "out.json")], env=env, capture_output=True,
                       text=True, timeout=120)
    time.sleep(0.3)
    ld = os.path.join(wtr, "replay-logs")
    logdirs = sorted(os.listdir(ld)) if os.path.isdir(ld) else []
    interrupted = [x for x in logdirs if os.path.exists(os.path.join(ld, x, "INTERRUPTED"))]
    return p, os.path.exists(os.path.join(case, "out.json")), logdirs, interrupted


for tag, mode in (("R8N3TERMGRP", "termgrp"), ("R8N3KILLW", "killw"), ("R8N3KILLK", "killk")):
    if not want(tag):
        continue
    case = os.path.join(WORK, tag.lower()); os.makedirs(case)
    p, report, logdirs, interrupted = r8_replay(case, mode)
    signalled = readf(os.path.join(case, "signalled")).strip()
    tmpleft = os.listdir(os.path.join(case, "tmp"))
    if not signalled or not report:
        bad("[%s] control needle: the shim signalled=%r after writing the report (report=%s) (%s)"
            % (tag, signalled, report, p.stderr.strip()[-200:]))
    elif p.returncode == 0 and logdirs and not interrupted and not tmpleft:
        ok("[%s] %s after the report was written (needle: pid %s): rc 0, the report exists, the run-log directory is "
           "not marked INTERRUPTED, temp dir gone" % (tag, mode, signalled))
    else:
        bad("[%s] %s after the report: rc=%s (want 0) report=%s INTERRUPTED=%s temp=%s -- 'no report' said although "
            "the report is on disk" % (tag, mode, p.returncode, report, interrupted, tmpleft))

if want("R8N3NAT"):
    case = os.path.join(WORK, "r8n3nat"); os.makedirs(case)
    repo = os.path.join(case, "repo"); head = mk_repo(repo)
    os.makedirs(os.path.join(case, "tmp")); os.makedirs(os.path.join(case, "locks"))
    env = dict(os.environ, TMPDIR=os.path.join(case, "tmp"), FC_REPLAY_LOCK_DIR=os.path.join(case, "locks"))
    env.pop("FC_OUT", None)
    out = os.path.join(case, "out.json")
    results = []
    for it in range(3):
        if os.path.exists(out):
            os.unlink(out)
        p = subprocess.Popen(["bash", SCRIPT, "replay", "--commit", head, "--repo-root", repo, "--worktree-root",
                              os.path.join(case, "wt%d" % it), "--min-free-kb", "0", "--min-free-kb-objects", "0",
                              "--gate-cmd", "true", "--cold-runs", "1", "--warm-runs", "0", "--out", out], env=env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        worker, sent, end = None, False, time.monotonic() + 60
        while time.monotonic() < end and p.poll() is None:
            if worker is None:
                k = [c for c in children(p.pid) if comm(c) == "fc-keeper"]
                ws = [w for w in children(k[0]) if comm(w) == "bash"] if k else []
                if ws and os.getpgid(ws[0]) == ws[0]:
                    worker = ws[0]
            if worker and os.path.exists(out):
                if worker > 1 and os.getpgid(worker) == worker and ppid(worker) == k[0]:
                    os.killpg(worker, signal.SIGTERM)     # the worker's own group: pgid == worker pid > 1, verified
                    sent = True
                break
            time.sleep(0.0003)
        rc = finish(p, 120)
        ld = os.path.join(case, "wt%d" % it, "replay-logs")
        intr = [x for x in (os.listdir(ld) if os.path.isdir(ld) else []) if os.path.exists(os.path.join(ld, x, "INTERRUPTED"))]
        results.append((rc, os.path.exists(out), sent, intr))
    if not all(r[2] for r in results):
        bad("[R8N3NAT] control needle: the TERM was not sent in every run (%r)" % results)
    elif all(r[0] == 0 and r[1] and not r[3] for r in results):
        ok("[R8N3NAT] TERM to the worker's process group the moment out.json appeared (3 runs): rc 0 each, the report "
           "exists, nothing marked INTERRUPTED")
    else:
        bad("[R8N3NAT] TERM to the worker's group once out.json appeared: (rc, report, sent, INTERRUPTED) = %r "
            "(want rc 0, report, no INTERRUPTED)" % results)

if want("R8N3STALE"):
    case = os.path.join(WORK, "r8n3stale"); os.makedirs(case)
    os.makedirs(os.path.join(case, "tmp")); os.makedirs(os.path.join(case, "locks"))
    out = os.path.join(case, "out.json")
    env0 = dict(os.environ, TMPDIR=os.path.join(case, "tmp"), FC_REPLAY_LOCK_DIR=os.path.join(case, "locks"))
    env0.pop("FC_OUT", None)
    first = subprocess.run(["bash", SCRIPT, "selfcheck", "--out", out], env=env0, capture_output=True, text=True,
                           timeout=120)
    before = os.stat(out) if os.path.exists(out) else None
    shim = py_shim(case, "before")
    env = dict(env0, PATH=shim + ":" + os.environ["PATH"])
    p = subprocess.Popen(["bash", SCRIPT, "selfcheck", "--out", out], env=env, stdout=subprocess.DEVNULL,
                         stderr=subprocess.PIPE, text=True)
    held = wait_path(os.path.join(case, "emitting"), 60)
    if held:
        sig_pid(p.pid, signal.SIGINT)
    rc = finish(p, 60)
    after = os.stat(out) if os.path.exists(out) else None
    same_file = before is not None and after is not None and (before.st_ino, before.st_mtime_ns) == (after.st_ino, after.st_mtime_ns)
    if first.returncode != 0 or before is None or not held:
        bad("[R8N3STALE] setup: first selfcheck rc=%s report=%s, writer held=%s" % (first.returncode, before is not None, held))
    elif rc == 130 and same_file:
        ok("[R8N3STALE] an identical report already at --out, stop before the writer started: rc 130 -- the old file "
           "(same body_hash) is not taken as written (needle: the old file is untouched)")
    else:
        bad("[R8N3STALE] stale identical report + stop before the writer: rc=%s (want 130) old file untouched=%s -- a "
            "report that was there BEFORE the writer started was read as written" % (rc, same_file))

# --- N4, injection H: the keeper's ledger work can take minutes (`git worktree remove` of a large checkout). Round 6
# killed a keeper at grace+5+30 s even while it was making progress, and main redid the work. Forced: a `git` shim
# that holds `worktree remove` 8 s when the KEEPER runs it; main's deadline shrunk to grace+1+1 s by a driver.
# Required: main waits for the keeper (no "did not finish its stop in time"), the removal is done ONCE, by the keeper,
# rc 143, the worktree is gone and unlisted. R7N4CAP: the wait stays BOUNDED -- with the overall cap shrunk to 3 s and
# the keeper's git held 40 s, main kills the keeper (said so) and still cleans up.
def git_shim(case, secs):
    shim = os.path.join(case, "gitshim"); os.makedirs(shim)
    real = shutil.which("git")
    open(os.path.join(shim, "git"), "w").write(r'''#!/bin/bash
case " $* " in
  *" worktree remove "*)
    c="$(cat "/proc/$PPID/comm" 2>/dev/null)"
    echo "$c" >>"%s/slow"
    [ "$c" = fc-keeper ] && sleep %d ;;
esac
exec %s "$@"
''' % (case, secs, real))
    os.chmod(os.path.join(shim, "git"), 0o755)
    return shim


for tag, secs, cap in (("R7N4", 8, None), ("R7N4CAP", 40, 3.0)):
    if not want(tag):
        continue
    case = os.path.join(WORK, tag.lower()); os.makedirs(os.path.join(case, "tmp"))
    repo = os.path.join(case, "repo"); mk_repo(repo)
    wt = os.path.join(case, "wtroot", "replay.h1"); os.makedirs(os.path.dirname(wt))
    g("-C", repo, "worktree", "add", "--detach", wt, "HEAD")
    shim = git_shim(case, secs)
    # HB_WINDOW_S 2 s (< the 8 s hold): only the beats sent WHILE the git call runs can keep the keeper alive (first
    # draft: the default 15 s window covered the whole hold, and the mutant without git beats survived)
    patch = ("m.KILL_WAIT_S = 1.0\nif hasattr(m, 'KEEPER_SLACK_S'): m.KEEPER_SLACK_S = 1.0\n"
             "if hasattr(m, 'HB_WINDOW_S'): m.HB_WINDOW_S = 2.0\n")
    if cap is not None:
        patch += "m.LEDGER_CAP_S = %r\n" % cap
    drv = table_drv(os.path.join(case, "x"), patch)
    worker = MARK + tag.lower() + "w"
    env = dict(os.environ, PATH=shim + ":" + os.environ["PATH"])
    p = subprocess.Popen(["python3", "-I", drv, "main", "--tmp-parent", os.path.join(case, "tmp"), "--grace", "0", "--",
                          "bash", "-c", 'printf "%s\\0%s\\0" "$1" "$2" >"$FC_BR_TMPDIR/ledger.wt.h1"; exec -a "$0" sleep 600',
                          worker, repo, wt], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    up = wait_exact_argv0(worker, 10) and wait_caught(p.pid, signal.SIGTERM, 5)
    t0 = time.monotonic()
    sig_pid(p.pid, signal.SIGTERM)
    try:
        _, err = p.communicate(timeout=120); rc = p.returncode
    except subprocess.TimeoutExpired:
        sig_pid(p.pid, signal.SIGKILL); _, err = p.communicate(); rc = None
    dt = time.monotonic() - t0
    slow = readf(os.path.join(case, "slow")).split()
    gone = not os.path.lexists(wt) and wt not in wt_entries(repo) and os.path.realpath(wt) not in wt_entries(repo)
    killed_msg = "did not finish its stop in time" in err
    kill_marked(worker)
    if not up or not slow or slow[0] != "fc-keeper":
        bad("[%s] setup/control needle: worker up=%s, first `worktree remove` run by %s (want fc-keeper)" % (tag, up, slow))
    elif cap is None and rc == 143 and gone and not killed_msg and slow == ["fc-keeper"] and dt >= secs - 0.5:
        ok("[%s] a keeper making progress (its `git worktree remove` held %d s, needle: run by fc-keeper) is waited for: "
           "rc 143 after %.1fs, removed once by the keeper, no deadline kill" % (tag, secs, dt))
    elif cap is not None and rc == 143 and gone and killed_msg and dt < 20:
        ok("[%s] the wait stays bounded: the keeper's git held %d s, the cap (%.0f s) killed it after %.1fs, said so, "
           "main cleaned up, rc 143" % (tag, secs, cap, dt))
    else:
        bad("[%s] rc=%s after %.1fs removed=%s deadline-kill message=%s `worktree remove` callers=%s" %
            (tag, rc, dt, gone, killed_msg, slow))
    if os.path.lexists(wt):
        g("-C", repo, "worktree", "remove", "-f", "-f", wt)

# --- N6, injection I: a stop during start-up. (a) INT pending in the caller's mask when main starts: Python's default
# SIGINT handler turned it into KeyboardInterrupt inside cmd_main -> rc 4 (BLIND) instead of 128+2. (b) INT to the
# main pid while bash is still in front of `exec` (waiting for `git rev-parse`): without a trap bash's wait-and-
# cooperative-exit rule DROPPED it when the child exited normally, and the whole replay ran (rc 0). (c) the Python
# start-up itself: `-S` (no site import) -- a KeyboardInterrupt inside `import site` was "Fatal Python error ... exit 1".
if want("R7N6"):
    d = os.path.join(WORK, "r7n6"); os.makedirs(os.path.join(d, "tmp"))
    w = MARK + "n6w"
    p = subprocess.Popen(["python3", "-I", "-c",
                          "import os, signal, sys\n"
                          "signal.pthread_sigmask(signal.SIG_BLOCK, [signal.SIGINT])\n"
                          "signal.raise_signal(signal.SIGINT)\n"
                          "os.execvp(sys.argv[1], sys.argv[1:])", "python3", "-I", SUP, "main", "--tmp-parent",
                          os.path.join(d, "tmp"), "--grace", "1", "--", "bash", "-c", 'exec -a "$0" sleep 600', w],
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    try:
        _, err = p.communicate(timeout=30); rc = p.returncode
    except subprocess.TimeoutExpired:
        sig_pid(p.pid, signal.SIGKILL); _, err = p.communicate(); rc = None
    left = procs_under(w)
    kill_marked(w)
    if rc == 130 and not left and "Traceback" not in err and not os.listdir(os.path.join(d, "tmp")):
        ok("[R7N6] (a) an INT pending when main starts is a stop: rc 130, no traceback, nothing left")
    else:
        bad("[R7N6] (a) INT pending at start: rc=%s (want 130) traceback=%s left=%s (%s)"
            % (rc, "Traceback" in err, bool(left), err.strip()[-160:]))
    # (b)
    case = os.path.join(d, "b"); os.makedirs(os.path.join(case, "tmp")); os.makedirs(os.path.join(case, "locks"))
    repo = os.path.join(case, "repo"); head = mk_repo(repo)
    gs = os.path.join(case, "gshim"); os.makedirs(gs)
    open(os.path.join(gs, "git"), "w").write('#!/bin/bash\ncase " $* " in *" --git-common-dir "*) '
                                             'echo ready >"%s/ready"; sleep 2 ;; esac\nexec %s "$@"\n'
                                             % (case, shutil.which("git")))
    os.chmod(os.path.join(gs, "git"), 0o755)
    env = dict(os.environ, PATH=gs + ":" + os.environ["PATH"], TMPDIR=os.path.join(case, "tmp"),
               FC_REPLAY_LOCK_DIR=os.path.join(case, "locks"))
    env.pop("FC_OUT", None)

    def pre_b():
        for s in (signal.SIGHUP, signal.SIGINT, signal.SIGQUIT, signal.SIGTERM):
            signal.signal(s, signal.SIG_DFL)
        os.setsid()
    p = subprocess.Popen(["bash", SCRIPT, "replay", "--commit", head, "--repo-root", repo, "--worktree-root",
                          os.path.join(case, "wt"), "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd",
                          "true", "--cold-runs", "1", "--warm-runs", "0", "--out", os.path.join(case, "out.json")],
                         env=env, preexec_fn=pre_b, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    ready = wait_path(os.path.join(case, "ready"), 30)
    if ready:
        sig_pid(p.pid, signal.SIGINT)
    try:
        _, err = p.communicate(timeout=60); rc = p.returncode
    except subprocess.TimeoutExpired:
        sig_pid(p.pid, signal.SIGKILL); _, err = p.communicate(); rc = None
    rc = 128 - rc if rc is not None and rc < 0 else rc
    rep = os.path.exists(os.path.join(case, "out.json"))
    if not ready:
        bad("[R7N6] (b) control needle: bash never reached its pre-exec `git rev-parse` (%s)" % err.strip()[-160:])
    elif rc == 130 and not rep and not os.listdir(os.path.join(case, "tmp")):
        ok("[R7N6] (b) SIGINT to the main pid while bash waits in front of exec (needle: git rev-parse held): rc 130, "
           "no replay ran, nothing created")
    else:
        bad("[R7N6] (b) SIGINT before exec: rc=%s (want 130) report=%s -- the stop was dropped" % (rc, rep))
    # (e) the same for a FOREGROUND command (not a command substitution) in front of exec -- the `env --block-signal`
    # probe. Bash's wait-and-cooperative-exit rule: an INT that reaches bash while a foreground child runs, and the
    # child then exits NORMALLY, is DROPPED (found by this round's own sweep: one run in 40 ended 0 -- the whole replay
    # ran). Required: bash, in front of exec, turns any stop into 128+N (traps), so the INT is never lost.
    case = os.path.join(d, "e"); os.makedirs(os.path.join(case, "tmp")); os.makedirs(os.path.join(case, "locks"))
    repo = os.path.join(case, "repo"); head = mk_repo(repo)
    es = os.path.join(case, "eshim"); os.makedirs(es)
    open(os.path.join(es, "env"), "w").write('#!/bin/bash\ncase " $* " in *" --block-signal=INT true "*) '
                                             'echo ready >"%s/ready"; sleep 2 ;; esac\nexec %s "$@"\n'
                                             % (case, shutil.which("env")))
    os.chmod(os.path.join(es, "env"), 0o755)
    env = dict(os.environ, PATH=es + ":" + os.environ["PATH"], TMPDIR=os.path.join(case, "tmp"),
               FC_REPLAY_LOCK_DIR=os.path.join(case, "locks"))
    env.pop("FC_OUT", None)
    p = subprocess.Popen(["bash", SCRIPT, "replay", "--commit", head, "--repo-root", repo, "--worktree-root",
                          os.path.join(case, "wt"), "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd",
                          "true", "--cold-runs", "1", "--warm-runs", "0", "--out", os.path.join(case, "out.json")],
                         env=env, preexec_fn=pre_b, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    ready = wait_path(os.path.join(case, "ready"), 30)
    if ready:
        sig_pid(p.pid, signal.SIGINT)
    try:
        _, err = p.communicate(timeout=60); rc = p.returncode
    except subprocess.TimeoutExpired:
        sig_pid(p.pid, signal.SIGKILL); _, err = p.communicate(); rc = None
    rc = 128 - rc if rc is not None and rc < 0 else rc
    rep = os.path.exists(os.path.join(case, "out.json"))
    if not ready:
        bad("[R7N6] (e) control needle: bash never reached the foreground `env` probe (%s)" % err.strip()[-160:])
    elif rc == 130 and not rep and not os.listdir(os.path.join(case, "tmp")):
        ok("[R7N6] (e) SIGINT to bash while a FOREGROUND child in front of exec runs and then exits 0 (needle: env probe "
           "held): rc 130, no replay ran")
    else:
        bad("[R7N6] (e) SIGINT during a foreground pre-exec command: rc=%s (want 130) report=%s -- bash dropped the stop "
            "(wait-and-cooperative-exit) and the replay ran" % (rc, rep))
    # (c) static: every supervisor invocation disables the site import (round 8: main exec, run, report-prepare,
    # report-check -- four)
    src = open(SCRIPT).read()
    n_s = len(re.findall(r'python3 -I -S "\$_FC_SUPERVISOR"', src))
    n_all = len(re.findall(r'python3[^\n]*"\$_FC_SUPERVISOR"', src))
    if n_all == 4 and n_s == 4:
        ok("[R7N6] (c) all four supervisor invocations (main exec, run, report-prepare, report-check) start Python with "
           "-S (no site import: a stop during start-up can no longer surface as 'Fatal Python error ... exit 1')")
    else:
        bad("[R7N6] (c) %d of %d supervisor invocations use `python3 -I -S`" % (n_s, n_all))
    # (d) behavioural: the process the caller started has INT BLOCKED by the time the interpreter runs (read from
    # /proc/<main>/status while main's own pre-handler code could not yet have unblocked it is not observable from
    # outside, so the exec line is driven directly: the same `_fc_supervise` exec with python3 replaced by a probe
    # that prints its SigBlk). A start-up INT then stays pending instead of reaching the interpreter's default handler.
    probe_dir = os.path.join(d, "dprobe"); os.makedirs(probe_dir)
    open(os.path.join(probe_dir, "python3"), "w").write(
        "#!/bin/bash\nsed -n 's/^SigBlk:[[:space:]]*//p' /proc/self/status >%s/sigblk\n" % probe_dir)
    os.chmod(os.path.join(probe_dir, "python3"), 0o755)
    fn = subprocess.run(["sed", "-n", "/^_fc_supervise() {/,/^}/p", SCRIPT], capture_output=True, text=True).stdout
    harness = ('_FC_IS_WORKER=0; _FC_SUPERVISOR=%s/python3; ' % probe_dir + '_FC_OUT_OVERRIDE=; _FC_GRACE=1; BASH=bash; SCRIPT_PATH=x; '
               'SUBCMD=selfcheck; ORIG_ARGS=(); blind() { exit 9; }\n' + fn + '\n_fc_supervise "" ""\n')
    subprocess.run(["bash", "-c", harness], env=dict(os.environ, PATH=probe_dir + ":" + os.environ["PATH"]),
                   capture_output=True, text=True, timeout=30)
    blk = readf(os.path.join(probe_dir, "sigblk")).strip()
    try:
        int_blocked = bool((int(blk, 16) >> (signal.SIGINT - 1)) & 1)
    except ValueError:
        int_blocked = None
    if not fn.strip() or int_blocked is None:
        bad("[R7N6] (d) setup: _fc_supervise not found / the probe did not run (SigBlk %r)" % blk)
    elif int_blocked:
        ok("[R7N6] (d) the exec into the supervisor has SIGINT BLOCKED (probe SigBlk %s): a start-up INT stays pending "
           "until the supervisor's own handler is installed" % blk)
    else:
        bad("[R7N6] (d) the exec into the supervisor leaves SIGINT unblocked (probe SigBlk %s) -- a start-up INT reaches "
            "the interpreter's default handler (exit 1 'Fatal Python error', or a swallowed stop)" % blk)

# --- N6 sweep (injection I, verbatim shape): INT at a random instant 0-250 ms after start, 40 runs of a replay whose
# gate sleeps 3 s (so a finished replay cannot explain rc 0). Every run must end 130 (or be killed by INT, which a
# shell sees as 130) -- never 0 (stop lost), 1, 4, never "Fatal Python error". HONEST BOUNDARY (§11.4.6): an INT
# that lands while the INTERPRETER itself starts (before the script's first statement can install a handler) ends
# Python by the default KeyboardInterrupt path: killed by INT (-2 = 130 to a shell) with a traceback on stderr. That
# is allowed ONLY together with -2 and is counted in the message (first run of this case on the round-7 code: 3 of
# 40 printed one from inside `import signal`/enum, which the handler now precedes).
if want("R7N6SWEEP"):
    import random
    d = os.path.join(WORK, "r7n6s"); os.makedirs(d)
    repo = os.path.join(d, "repo"); head = mk_repo(repo)
    gate = os.path.join(d, "gate.sh")
    open(gate, "w").write("#!/bin/bash\nexec -a %sn6sgate sleep 3\n" % MARK)
    os.chmod(gate, 0o755)
    rng = random.Random(1234)
    counts, badruns = {}, []
    for i in range(40):
        c = os.path.join(d, "c%02d" % i); os.makedirs(os.path.join(c, "tmp")); os.makedirs(os.path.join(c, "locks"))
        env = dict(os.environ, TMPDIR=os.path.join(c, "tmp"), FC_REPLAY_LOCK_DIR=os.path.join(c, "locks"))
        env.pop("FC_OUT", None)

        def pre_s():
            for s in (signal.SIGHUP, signal.SIGINT, signal.SIGQUIT, signal.SIGTERM):
                signal.signal(s, signal.SIG_DFL)
            os.setsid()
        p = subprocess.Popen(["bash", SCRIPT, "replay", "--commit", head, "--repo-root", repo, "--worktree-root",
                              os.path.join(c, "wt"), "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd",
                              gate, "--cold-runs", "1", "--warm-runs", "0", "--out", os.path.join(c, "out.json")],
                             env=env, preexec_fn=pre_s, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        time.sleep(rng.uniform(0.0, 0.25))
        sig_pid(p.pid, signal.SIGINT)
        try:
            _, err = p.communicate(timeout=60); rc = p.returncode
        except subprocess.TimeoutExpired:
            sig_pid(p.pid, signal.SIGKILL); _, err = p.communicate(); rc = None
        counts[rc] = counts.get(rc, 0) + 1
        if "Traceback" in err and rc == -2:
            counts["traceback_with_-2"] = counts.get("traceback_with_-2", 0) + 1
        if rc not in (130, -2) or "Fatal Python error" in err or ("Traceback" in err and rc != -2):
            badruns.append((i, rc, err.strip()[-120:]))
    time.sleep(0.5)
    left = procs_under(MARK + "n6sgate")
    kill_marked(MARK + "n6sgate")
    if not badruns and not left:
        ok("[R7N6SWEEP] 40 SIGINTs at random start-up instants: every run ended 130 / killed by INT (%r), never 0/1/4, "
           "no 'Fatal Python error', nothing left" % counts)
    else:
        bad("[R7N6SWEEP] start-up INT sweep: %r, bad runs %r, left=%s" % (counts, badruns[:4], bool(left)))

# --- N1, the run supervisor's parent death (round 7): when the worker that started a run supervisor dies, the run
# supervisor stops its OWN tree before it exits (PDEATHSIG = SIGUSR2 + handler; round 6: SIGKILL, and a gate's setsid
# daemon was orphaned past it -- to a keeper, or, when the keeper was gone too, to main, which cannot attribute a
# process outside the keeper's session). Observed alone: a parent bash starts `run` with a gate that starts a setsid
# daemon; the parent is SIGKILLed. Required: the daemon is stopped, the run supervisor exits, marker `stopped`.
if want("R7RUNPD"):
    d = os.path.join(WORK, "r7runpd"); os.makedirs(d)
    mk = os.path.join(d, "m")
    gate = os.path.join(d, "gate.sh")
    open(gate, "w").write("#!/bin/bash\n( setsid bash -c 'exec -a \"$0\" sleep 600' %srpddaemon & )\n"
                          "echo up >%s/ready\nexec -a %srpdgate sleep 600\n" % (MARK, d, MARK))
    os.chmod(gate, 0o755)
    par = subprocess.Popen(["bash", "-c", 'python3 -I "$1" run --timeout 60 --grace 1 --marker "$2" --cwd "$3" -- "$4" '
                            '& echo $! >"$3/runpid"; wait', "x", SUP, mk, d, gate],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    up = wait_path(os.path.join(d, "ready"), 15) and wait_exact_argv0(MARK + "rpddaemon", 10)
    try:
        runpid = int(readf(os.path.join(d, "runpid")).split()[0])
    except (ValueError, IndexError):
        runpid = None
    # control needle: the daemon is the run supervisor's adopted orphan (it re-parented to the run subreaper)
    dm = [q for q, a in procs_under(MARK + "rpddaemon") if a.split(" ", 1)[0] == MARK + "rpddaemon"]
    adopted = False
    end = time.monotonic() + 5
    while up and dm and runpid and time.monotonic() < end and not adopted:
        adopted = ppid(dm[0]) == runpid
        time.sleep(0.02)
    sig_pid(par.pid, signal.SIGKILL)
    par.wait()
    end = time.monotonic() + 10
    while time.monotonic() < end and (procs_under(MARK + "rpd") or (runpid and alive_pid(runpid))):
        time.sleep(0.05)
    left = procs_under(MARK + "rpd")
    run_alive = bool(runpid) and alive_pid(runpid) and comm(runpid) == "fc-run"
    kill_marked(MARK + "rpd")
    if not (up and adopted):
        bad("[R7RUNPD] setup/control needle: gate up=%s, daemon adopted by the run supervisor=%s" % (up, adopted))
    elif not left and not run_alive and readf(mk) == "stopped":
        ok("[R7RUNPD] the worker (parent) of a run supervisor SIGKILLed: the run supervisor stopped its own tree -- the "
           "setsid daemon it had adopted (needle) is gone -- and exited, marker stopped")
    else:
        bad("[R7RUNPD] parent of the run supervisor killed: left=%s run supervisor alive=%s marker=%r -- the gate's daemon "
            "was orphaned past the run supervisor" % ([a[:50] for _, a in left], run_alive, readf(mk)))

# --- N1 (found by this round's own r2 run): the keeper's worker leads its OWN process group. In the keeper's group, a
# SIGKILL to "the worker's process group" killed keeper, worker and run supervisor at once; a gate's setsid daemon was
# orphaned to main, which cannot attribute it (KILL-worker-group-ownsess/-daemon left it running -- a race: main's walk
# sometimes still saw the dying run supervisor). Deterministic oracle: the group structure itself, then a TERM to the
# worker's group is handled by the keeper (alive), which reports the worker's exit.
if want("R7WGRP"):
    d = os.path.join(WORK, "r7wgrp"); os.makedirs(os.path.join(d, "tmp"))
    w = MARK + "wgrp"
    errf = os.path.join(d, "err")
    p = subprocess.Popen(["python3", "-I", SUP, "main", "--tmp-parent", os.path.join(d, "tmp"), "--grace", "1", "--",
                          "bash", "-c", '( setsid bash -c \'exec -a "$0" sleep 600\' "$0-out" & ); exec -a "$0" sleep 600', w],
                         stdout=subprocess.DEVNULL, stderr=open(errf, "w"))
    k = keeper_pid(p.pid)
    wait_exact_argv0(w + "-out", 10)    # a process OUTSIDE the worker's group: the keeper must report stopping it
    up = wait_exact_argv0(w, 10)
    wp = [q for q, a in procs_under(w) if a.split(" ", 1)[0] == w]

    def pgid(x):
        try:
            st = open("/proc/%d/stat" % x).read()
            return int(st[st.rindex(") ") + 2:].split()[2])
        except (OSError, ValueError, IndexError):
            return None
    wg, kg = (pgid(wp[0]) if wp else None), (pgid(k) if k else None)
    sent = False
    if up and wp and wg == wp[0] and wg != kg and isinstance(wg, int) and wg > 1 and wg != os.getpgrp():
        os.killpg(wg, signal.SIGTERM)       # §11.4.263: a validated group > 1 that is the worker's own, never ours
        sent = True
    rc = finish(p, 30)
    err = readf(errf)
    kill_marked(w)
    if not (k and up and wp):
        bad("[R7WGRP] setup: keeper=%s worker=%s" % (k, wp))
    elif sent and rc == 143 and "(the worker exited 143)" in err and "stopped by signal" not in err:
        ok("[R7WGRP] the worker leads its own process group (pgid %d, keeper's %d): a TERM to that group never reaches "
           "the keeper, which reported the worker's exit and stopped the tree (rc 143)" % (wg, kg))
    else:
        bad("[R7WGRP] worker pgid=%s keeper pgid=%s sent=%s rc=%s keeper reported the worker's exit=%s -- a signal to the "
            "worker's group reaches the keeper" % (wg, kg, sent, rc, "(the worker exited 143)" in err))

# --- RVM-04 (reviewer mutant, adopted verbatim as a permanent case): the round-6 F2 guard `[ -s "$mk" ]` is never
# exercised with a marker that EXISTS BUT IS EMPTY (the mutant `[ -e "$mk" ]` survived the whole suite). A gate empties
# its own run supervisor's outcome marker (the path is read from that supervisor's own argv), starts a daemon, then
# SIGKILLs the run supervisor: no outcome was recorded, the marker exists empty. Required: the replay aborts (exit 4,
# said so), no report, the daemon is stopped, nothing left.
if want("R7EMPTYMK"):
    case = os.path.join(WORK, "r7emk"); os.makedirs(case)
    repo = os.path.join(case, "repo"); head = mk_repo(repo)
    gate = os.path.join(case, "gate.sh")
    open(gate, "w").write(
        "#!/bin/bash\n"
        "mk=\"$(tr '\\0' '\\n' </proc/$PPID/cmdline | sed -n '/^--marker$/{n;p;q}')\"\n"
        "[ -n \"$mk\" ] || exit 9\n"
        ": >\"$mk\"\n"
        "echo \"$mk\" >%(c)s/marker\n"
        "( setsid bash -c 'exec -a \"$0\" sleep 600' %(m)semkdaemon & )\n"
        "sleep 0.3\n"
        "case \"$PPID\" in ''|*[!0-9]*) exit 9 ;; esac\n"
        "[ \"$PPID\" -gt 1 ] || exit 9\n"
        "kill -KILL \"$PPID\"\n"
        "exec -a %(m)semkgate sleep 600\n" % {"c": case, "m": MARK})
    os.chmod(gate, 0o755)
    rc, rep, err, wtr = replay(case, repo, head, gate, {"FC_BR_STOP_GRACE_S": "1"}, ["--cold-runs", "2"], timeout=120)
    mkp = readf(os.path.join(case, "marker")).strip()
    time.sleep(0.3)
    left = procs_under(MARK + "emk")
    kill_marked(MARK + "emk")
    if not mkp:
        bad("[R7EMPTYMK] control needle: the gate never found / emptied its run supervisor's marker (%s)" % err.strip()[-200:])
    elif rc == 4 and rep is None and not left and "without recording an outcome" in err:
        ok("[R7EMPTYMK] the run supervisor SIGKILLed after its marker was emptied (needle: %s): the empty marker is "
           "'no outcome' -- replay aborted (4, said so), no report, the daemon stopped" % os.path.basename(mkp))
    else:
        bad("[R7EMPTYMK] empty marker: rc=%s (want 4) report=%s abort message=%s left=%s"
            % (rc, rep is not None, "without recording an outcome" in err, [l[:60] for _, l in left]))

# --- ROUND 8 (V4R8-5): the reviewer's surviving mutants adopted VERBATIM as permanent rows.
# R8RVM02 (mutant RVM-02: the second-signal guard `if Stop.sig: return` removed): a run supervisor stopping its tree
# after SIGINT gets a SIGTERM during the stop; the first signal decides -- rc 130, marker `stopped` (mutant: 143).
if want("R8RVM02"):
    d = os.path.join(WORK, "r8rvm02"); os.makedirs(d)
    mk = os.path.join(d, "marker")
    p = subprocess.Popen(["python3", "-I", "-S", SUP, "run", "--timeout", "60", "--grace", "3", "--marker", mk,
                          "--cwd", d, "--", "bash", "-c", 'trap "" TERM; exec -a "$0" sleep 600', MARK + "rvm02"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    up = wait_exact_argv0(MARK + "rvm02", 10) and wait_caught(p.pid, signal.SIGINT, 5)
    if up:
        sig_pid(p.pid, signal.SIGINT)
        time.sleep(0.5)
        sig_pid(p.pid, signal.SIGTERM)
    rc = finish(p, 30)
    kill_marked(MARK + "rvm02")
    if not up:
        bad("[R8RVM02] setup: the command / the run supervisor's INT handler never appeared")
    elif rc == 130 and readf(mk) == "stopped":
        ok("[R8RVM02] INT then TERM to a run supervisor mid-stop: the first signal decides (rc 130, marker stopped)")
    else:
        bad("[R8RVM02] INT then TERM mid-stop: rc=%s (want 130) marker=%r -- a second signal changed the outcome"
            % (rc, readf(mk)))

# R8USR2 (mutant USR2ANY: every SIGUSR2 sets parent_gone): a stray SIGUSR2 to a run supervisor whose worker (here:
# this test, its parent) is alive is NOT the parent-death signal -- the run completes: rc 0, marker `exited`
# (mutant: stopped / 137).
if want("R8USR2"):
    d = os.path.join(WORK, "r8usr2"); os.makedirs(d)
    mk = os.path.join(d, "marker")
    p = subprocess.Popen(["python3", "-I", "-S", SUP, "run", "--timeout", "60", "--grace", "1", "--marker", mk,
                          "--cwd", d, "--", "bash", "-c", 'exec -a "$0" sleep 1.5', MARK + "usr2"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    up = wait_exact_argv0(MARK + "usr2", 10) and wait_caught(p.pid, signal.SIGUSR2, 5)
    if up:
        sig_pid(p.pid, signal.SIGUSR2)
    rc = finish(p, 30)
    kill_marked(MARK + "usr2")
    if not up:
        bad("[R8USR2] setup: the command / the run supervisor's SIGUSR2 handler never appeared")
    elif rc == 0 and readf(mk) == "exited":
        ok("[R8USR2] a stray SIGUSR2 while the run supervisor's parent lives is ignored: rc 0, marker exited")
    else:
        bad("[R8USR2] stray SIGUSR2 with a live parent: rc=%s (want 0) marker=%r -- treated as the parent's death"
            % (rc, readf(mk)))

print("----")
print("SUMMARY pass=%d fail=%d" % (N["ok"], N["bad"]))
sys.exit(0 if N["bad"] == 0 else 1)
PY
exit $?
