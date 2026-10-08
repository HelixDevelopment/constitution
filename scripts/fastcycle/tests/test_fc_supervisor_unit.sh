#!/usr/bin/env bash
# =============================================================================
# test_fc_supervisor_unit.sh -- unit tests of cycle/fc_supervisor.py's tree stop
# (T048 restart round 3, STRUCTURAL round; docs/qa/t048_restart_round3_20261008/
# V4_baseline.md).
#
# Why a unit test next to the r2 stop matrix: the matrix drives the real tool and
# real process trees, but some races in stop_tree() are too narrow to hit on
# demand. Found by the matrix (1 of 193 rows, KILL-supervisor-nested, 2026-10-08):
# when the keeper is SIGKILLed, the PDEATHSIG chain (worker -> run supervisor ->
# gate) unwinds WHILE the main supervisor walks its tree. walk() reads a node's
# children list, then stats each child: a child that is already a zombie is
# skipped, and its own children -- reparented to the subreaper AFTER the
# subreaper's list was read -- are in neither list. The walk came back EMPTY,
# stop_tree() returned, the main supervisor exited, and the gate's nested
# `timeout` (re-parented next) went to init and outlived the tool.
# Rule under test: an empty walk ends the stop only if it saw NO zombie; a zombie
# means a cascade may still be moving processes up, so the tree is walked again.
#
# The cases drive the REAL stop_tree() of the module under test. Only the /proc
# view (_children, _stat_fields, reap) is replaced by a scripted sequence -- the
# one thing a real kernel cannot be made to time deterministically; the process
# that has to be stopped is a REAL child process and the signal is a REAL pidfd
# signal (§11.4.27: fakes only in unit tests).
#
# Env: FC_SUP_UNDER_TEST  path of fc_supervisor.py (default: the real file; the
#                         paired-mutation runner points this at a mutant).
# Exit: 0 every case held; 1 otherwise.
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
SUP="${FC_SUP_UNDER_TEST:-$FC/cycle/fc_supervisor.py}"
[ -f "$SUP" ] || { echo "NOT ok supervisor under test not found: $SUP"; exit 1; }

SUP="$SUP" python3 -I - <<'PY'
import importlib.util, os, signal, subprocess, sys, time

spec = importlib.util.spec_from_file_location("fcsup", os.environ["SUP"])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
N = {"ok": 0, "bad": 0}


def ok(s):
    N["ok"] += 1; print("ok " + s, flush=True)


def bad(s):
    N["bad"] += 1; print("NOT ok " + s, flush=True)


def scripted(views, live):
    """views: list of {pid: [children]} snapshots, one per walk() of stop_tree;
    the last one repeats. live: {pid: state} for _stat_fields (state 'Z' = zombie);
    the parent of every pid is looked up in the CURRENT view."""
    st = {"i": 0, "walks": 0}
    me = os.getpid()

    def cur():
        return views[min(st["i"], len(views) - 1)]

    def _children(pid):
        if pid == me:
            st["walks"] += 1
            if st["walks"] > 1:
                st["i"] += 1
        return list(cur().get(pid, []))

    def _stat_fields(pid):
        for parent, kids in cur().items():
            if pid in kids:
                s = live.get(pid)
                if s == "gone":
                    return None
                return (s or "S", parent)
        return None

    return _children, _stat_fields, st


# ---- case Z1: zombie in the first walk, its child reparented to the subreaper afterwards ----
real = subprocess.Popen(["sleep", "60"], preexec_fn=lambda: signal.signal(signal.SIGTERM, signal.SIG_DFL))
me = os.getpid()
W = 999999990          # never a real pid on a default pid_max <= 4194304 ... checked below
try:
    pidmax = int(open("/proc/sys/kernel/pid_max").read())
except OSError:
    pidmax = 4194304
if W <= pidmax:
    W = pidmax + 10    # a pid the kernel cannot hand out: pidfd_open on it can never succeed
views = [{me: [W]},                 # walk 1: the worker, already a zombie; its child not yet moved
         {me: [real.pid]},          # walk 2: the run supervisor / gate, reparented to the subreaper
         {me: []}]                  # walk 3: it is gone (reaped) -- the tree is really empty
ch, sf, st = scripted(views, {W: "Z"})
m._children, m._stat_fields = ch, sf
m.reap = lambda: None
t0 = time.monotonic()
n = m.stop_tree(1.0, "unit")
try:
    rc = real.wait(timeout=5)
except subprocess.TimeoutExpired:
    rc = None
    real.kill(); real.wait()
if rc == -signal.SIGTERM:
    ok("[Z1] an empty walk that saw a zombie is not the end of the stop: the process reparented after "
       "the walk read the subreaper's children was found and stopped (SIGTERM, %d process(es), %.2fs)"
       % (n, time.monotonic() - t0))
else:
    bad("[Z1] stop_tree returned after an EMPTY walk that contained a zombie mid-cascade: the process "
        "reparented afterwards was never signalled (its exit=%r, stop_tree counted %d)" % (rc, n))

# ---- case Z2 (control): a truly empty tree (no zombies) ends the stop at once ----
ch, sf, st = scripted([{me: []}], {})
m._children, m._stat_fields = ch, sf
t0 = time.monotonic()
n = m.stop_tree(1.0, "unit")
dt = time.monotonic() - t0
if n == 0 and dt < 0.5:
    ok("[Z2] control: an empty tree with no zombie ends the stop immediately (%.3fs)" % dt)
else:
    bad("[Z2] control: an empty tree took %.2fs / counted %d" % (dt, n))

# ---- case Z3: a zombie that never goes away bounds the stop (no endless loop) ----
ch, sf, st = scripted([{me: [W]}], {W: "Z"})
m._children, m._stat_fields = ch, sf
t0 = time.monotonic()
n = m.stop_tree(0.2, "unit")
dt = time.monotonic() - t0
if dt < 0.2 + m.KILL_WAIT_S + 2:
    ok("[Z3] a zombie nobody reaps cannot hold the stop forever (returned after %.2fs)" % dt)
else:
    bad("[Z3] a lingering zombie held the stop for %.2fs" % dt)

print("----")
print("SUMMARY pass=%d fail=%d" % (N["ok"], N["bad"]))
sys.exit(0 if N["bad"] == 0 else 1)
PY
