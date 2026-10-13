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
# Round-4 groups ([S*] / [G1], mutations R4-S* and RA* in test_fastcycle_r6_mutations.sh): the
# defence-in-depth guards. open_verified (S1 pid reuse, S1b unreadable /proc stat, S2 pid<=1, S3 self,
# S1-tree reuse seen through stop_tree, G1 the expected parent for a grandchild); process_ledger's
# rmtree guard (S5 non-replay dir, S5b relative path, S5c positive control, S5d replay.* ancestor,
# S5e 'replayer' prefix, S5f/S5g trailing slash). The signal primitive in the S* cases is a SPY (records,
# never signals), so no case can deliver a signal to pid 1 or to this process (§11.4.263); G1 signals
# only two real sleep children of this test.
#
# Round-8 groups (T048 V4 round 8): [P1]/[P2] main's ownership walk prunes the caller's pre-existing subtrees
# (V4R8-6); [R1]/[R1b..f] report_prepare/report_verified -- "was the report written" decided from durable state
# (V4R8-2), driven with the real fc_common.py next to the module under test.
# Round-9 groups (T048 V4 round 9): [R9B] [R9ID-*] [R9OWN-I/J] [R9DEC] [R9GC] -- see the block comment above them.
# Round-10 groups (T048 V4 round 10): [R10GC-*] [R10LEASE*] [R10HASH] [R10ATOMIC] -- see the block comment above them.
# Round-11 groups (T048 V4 round 11): [R11*] -- a planted FIFO / symlink / socket / directory / device / foreign-uid
# file never blocks or misleads any open of the module (V4R11-1, class-wide); see the block comment above them.
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

# ---- round-4 F5: the defence-in-depth guards of open_verified() and process_ledger() ----
# open_verified's three refusals (pid <= 1, this process, a pid whose CURRENT /proc parent is not
# the tree node it was found under = pid reuse) each get their own case. The signal primitive is
# a SPY (records, never signals): no case can ever deliver a signal to pid 1 or to this process,
# whatever mutant is under test.
class SigSpy:
    def __init__(self, real):
        self.calls, self._real = [], real
    def pidfd_send_signal(self, fd, sig, *a):
        self.calls.append(sig)
    def __getattr__(self, k):
        return getattr(self._real, k)

real_signal = m.signal
spy = SigSpy(real_signal)
m.signal = spy
try:
    # S1: pid reuse -- a REAL live child, but /proc now names another parent than the tree node.
    child = subprocess.Popen(["sleep", "60"])
    m._stat_fields = lambda pid: ("S", 4242 if pid == child.pid else 1)
    fd = m.open_verified(child.pid, os.getpid())
    if fd is None and not spy.calls:
        ok("[S1] open_verified refuses a pid whose /proc parent (4242) is not the tree node it was found under "
           "(pid reuse): no pidfd, no signal")
    else:
        bad("[S1] open_verified accepted a pid whose current parent is not the tree node (fd=%r, signals=%r) -- "
            "a recycled pid could be signalled" % (fd, spy.calls))
        if fd is not None:
            os.close(fd)
    child.kill(); child.wait()
    # S1-tree: the same reuse seen by stop_tree -- the live child must survive the whole stop.
    spy.calls.clear()
    child = subprocess.Popen(["sleep", "60"])
    me = os.getpid()
    # keyed on the ORDER of events, not on a call count: walk() stats a child first (found under me); the
    # stat that directly follows os.pidfd_open(pid) is open_verified's, and there the parent has changed.
    # An equivalent refactor (extra/removed stat calls) therefore cannot false-FAIL this case.
    opened = set()
    real_pidfd_open = os.pidfd_open
    def spy_pidfd_open(pid, *a):
        r = real_pidfd_open(pid, *a)
        opened.add(pid)
        return r
    def sf_reuse(pid):
        if pid in opened:
            opened.discard(pid)
            return ("S", 4242)
        return ("S", me)
    os.pidfd_open = spy_pidfd_open
    m._children = lambda pid: [child.pid] if pid == me else []
    m._stat_fields = sf_reuse
    try:
        m.stop_tree(0.1, "unit")
    finally:
        os.pidfd_open = real_pidfd_open
    alive = child.poll() is None
    if alive and not spy.calls:
        ok("[S1-tree] stop_tree never signals a tree member whose parent changed between the walk and the "
           "pidfd open (the reused pid survived, 0 signals)")
    else:
        bad("[S1-tree] stop_tree signalled a pid whose parent changed under it (alive=%r, signals=%r)"
            % (alive, spy.calls))
    child.kill(); child.wait()
    # S1b: /proc cannot name a parent at all (_stat_fields -> None: the pid vanished or is unreadable)
    # for a REAL live child -- an unverifiable parent is a refusal, never a pass (fail closed).
    spy.calls.clear()
    child = subprocess.Popen(["sleep", "60"])
    m._stat_fields = lambda pid: None
    fd = m.open_verified(child.pid, os.getpid())
    if fd is None and not spy.calls:
        ok("[S1b] open_verified refuses a live pid whose /proc stat is unreadable (parent unverifiable): "
           "no pidfd, no signal")
    else:
        bad("[S1b] open_verified accepted a pid it could not verify (fd=%r, signals=%r)" % (fd, spy.calls))
        if fd is not None:
            os.close(fd)
    child.kill(); child.wait()
    # S2: pid 1 is never opened or signalled, even when /proc "agrees" it is a child of the node.
    spy.calls.clear()
    m._stat_fields = lambda pid: ("S", 0)
    fd = m.open_verified(1, 0)
    if fd is None and not spy.calls:
        ok("[S2] open_verified refuses pid 1 outright (no pidfd, no signal-0 probe)")
    else:
        bad("[S2] open_verified opened/probed pid 1 (fd=%r, signals=%r)" % (fd, spy.calls))
        if fd is not None:
            os.close(fd)
    # S3: this process itself is never a stop target.
    spy.calls.clear()
    m._stat_fields = lambda pid: ("S", os.getppid())
    fd = m.open_verified(os.getpid(), os.getppid())
    if fd is None and not spy.calls:
        ok("[S3] open_verified refuses this process itself")
    else:
        bad("[S3] open_verified accepted this process itself (fd=%r, signals=%r)" % (fd, spy.calls))
        if fd is not None:
            os.close(fd)
    # G1: stop_tree passes the NODE a member was found under as the expected parent. A grandchild is
    # found under its (scripted) parent, not under this process: it must still be signalled -- directly,
    # with the real signal primitive (spy off), and only because both pids are REAL children of ours.
finally:
    m.signal = real_signal

gc_pre = lambda: signal.signal(signal.SIGTERM, signal.SIG_DFL)
mid = subprocess.Popen(["sleep", "60"], preexec_fn=gc_pre)
gch = subprocess.Popen(["sleep", "60"], preexec_fn=gc_pre)
me = os.getpid()
ch, sf, st = scripted([{me: [mid.pid], mid.pid: [gch.pid]}, {me: []}], {})
m._children, m._stat_fields = ch, sf
m.reap = lambda: None
n = m.stop_tree(1.0, "unit")
rcs = []
for pr in (mid, gch):
    try:
        rcs.append(pr.wait(timeout=5))
    except subprocess.TimeoutExpired:
        rcs.append(None)
        pr.kill(); pr.wait()
if rcs == [-signal.SIGTERM, -signal.SIGTERM]:
    ok("[G1] stop_tree signalled a grandchild directly (SIGTERM) -- the expected parent handed to open_verified "
       "is the node it was found under, not this process (%d processes)" % n)
else:
    bad("[G1] stop_tree did not SIGTERM both the child and the grandchild (exits=%r, counted %d)" % (rcs, n))

# process_ledger: a 'wt' entry is removed ONLY when it is an ABSOLUTE path whose basename starts
# with 'replay.' (the only shape W writes: mktemp -d .../replay.XXXXXX). Anything else must be
# left untouched and reported -- this is a destructive path (rmtree, §9).
import tempfile, shutil
L = tempfile.mkdtemp(prefix="fcsup_ledger.")
try:
    repo = os.path.join(L, "repo"); os.mkdir(repo)
    # a real (empty) repository, so the module's `git -C repo worktree ...` calls can never walk up
    # into whatever repository encloses the temp directory
    subprocess.run(["git", "init", "-q", repo], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    precious = os.path.join(L, "precious"); os.mkdir(precious)
    open(os.path.join(precious, "keep.txt"), "w").write("keep\n")
    replay_abs = os.path.join(L, "replay.abc123"); os.mkdir(replay_abs)
    rel_dir = os.path.join(L, "cwd"); os.mkdir(rel_dir)
    os.mkdir(os.path.join(rel_dir, "replay.rel"))
    td = os.path.join(L, "tmp"); os.mkdir(td)
    def entry(name, path):
        with open(os.path.join(td, name), "wb") as fh:
            fh.write(os.fsencode(repo) + b"\0" + os.fsencode(path))
    entry("ledger.wt.1", precious)          # absolute, NOT replay.*  -> must survive
    entry("ledger.wt.2", "replay.rel")      # replay.* but RELATIVE    -> must survive
    # exhaustion of the guard (round-4 reviewer F2): each of these must survive and be reported
    os.mkdir(os.path.join(L, "replay.q")); os.mkdir(os.path.join(L, "replay.q", "precious2"))
    open(os.path.join(L, "replay.q", "precious2", "keep.txt"), "w").write("keep\n")
    os.mkdir(os.path.join(L, "replayer")); open(os.path.join(L, "replayer", "keep.txt"), "w").write("keep\n")
    os.mkdir(os.path.join(L, "x")); open(os.path.join(L, "x", "keep.txt"), "w").write("keep\n")
    os.mkdir(os.path.join(L, "replay.trail")); open(os.path.join(L, "replay.trail", "keep.txt"), "w").write("keep\n")
    entry("ledger.wt.4", os.path.join(L, "replay.q", "precious2"))   # replay.* is an ANCESTOR, not the basename
    entry("ledger.wt.5", os.path.join(L, "replayer"))                # prefix is 'replay.', not 'replay'
    entry("ledger.wt.6", os.path.join(L, "x") + "/")                 # trailing slash, non-replay
    entry("ledger.wt.7", os.path.join(L, "replay.trail") + "/")      # trailing slash: basename is '' -> not matched
    entry("ledger.wt.3", replay_abs)        # absolute replay.*        -> removed (positive control)
    old_cwd = os.getcwd(); os.chdir(rel_dir)
    msgs = []
    real_say = m.say
    m.say = lambda s: msgs.append(s)
    try:
        m.process_ledger(td, "unit")
    finally:
        m.say = real_say
        os.chdir(old_cwd)
    if os.path.isfile(os.path.join(precious, "keep.txt")) and any("not a replay worktree" in s for s in msgs):
        ok("[S5] a ledger 'wt' entry naming a non-'replay.' directory is left untouched and reported")
    else:
        bad("[S5] process_ledger DELETED (or silently skipped) a non-replay directory named by the ledger "
            "(precious exists=%r, messages=%r)" % (os.path.isdir(precious), msgs))
    for tag, rel, why in (("S5d", "replay.q/precious2/keep.txt", "a path whose ANCESTOR is replay.* (basename is not)"),
                          ("S5e", "replayer/keep.txt", "a basename that starts with 'replay' but not 'replay.'"),
                          ("S5f", "x/keep.txt", "a trailing-slash path with a non-replay basename"),
                          ("S5g", "replay.trail/keep.txt", "a trailing-slash path (basename is empty) -- conservative: not removed")):
        if os.path.isfile(os.path.join(L, rel)):
            ok("[%s] a ledger 'wt' entry naming %s is left untouched" % (tag, why))
        else:
            bad("[%s] process_ledger DELETED %s" % (tag, why))
    if os.path.isdir(os.path.join(rel_dir, "replay.rel")):
        ok("[S5b] a RELATIVE 'replay.*' ledger path is never resolved against the cwd and removed")
    else:
        bad("[S5b] process_ledger removed a RELATIVE replay.* path resolved against the cwd")
    if not os.path.lexists(replay_abs) and not any(n.startswith("ledger.") for n in os.listdir(td)):
        ok("[S5c] control: an absolute replay.* worktree IS removed and every ledger entry is consumed")
    else:
        bad("[S5c] control: the absolute replay.* entry was not removed (exists=%r) or ledger entries remain %r"
            % (os.path.lexists(replay_abs), os.listdir(td)))
finally:
    shutil.rmtree(L, ignore_errors=True)

# --- T048 V4 round 8, V4R8-6: main's ownership walk PRUNES the caller's pre-existing subtrees. Round 7 evaluated the
# session test (sid == keeper pid) below a caller's own child: after the keeper's session ended, a reused keeper pid as
# the session id of a process in the caller's subtree made that caller process "owned" (signalled by main). Scripted
# /proc view (the reuse cannot be timed on a real kernel): main -> P (the caller's child, recorded at entry) -> G (sid ==
# the keeper pid) -> G2; main -> K (the keeper) -> W (in K's session). Required: K and W owned; G and G2 NOT returned
# and G's subtree never even read. [P2] control: below a non-owned node that is NOT a caller's child (an adopted
# orphan), an owned process is still found -- the prune is exactly the caller's subtrees.
me = os.getpid()
KP, KS, P, G, G2, W, X, Y = 900001, 555, 900002, 900003, 900004, 900005, 900006, 900007
tree = {me: [P, KP, X], P: [G], G: [G2], KP: [W], X: [Y]}
ident = {P: (P, 100), G: (KP, 300), G2: (KP, 301), KP: (KP, KS), W: (KP, 600), X: (X, 700), Y: (KP, 701)}
read = []
saved = (m._children, m._stat_fields, m._ident)
m._children = lambda pid: (read.append(pid), list(tree.get(pid, [])))[1]
m._stat_fields = lambda pid: ("S", next((q for q, ks in tree.items() if pid in ks), 0)) if pid in ident else None
m._ident = lambda pid: ident.get(pid)
try:
    owner = m._main_owner(KP, KS, {(P, 100)})
    got, _z = m.walk_owned(me, owner)
finally:
    m._children, m._stat_fields, m._ident = saved
gotp = {p for p, _ in got}
if gotp == {KP, W, Y} and G not in read and G2 not in read:
    ok("[P1] the caller's pre-existing child's subtree is pruned: a reused keeper pid as a session id below it is never "
       "owned (G/G2 not returned, G never read); keeper + worker owned")
else:
    bad("[P1] ownership walk returned %r, read %r -- a process below the caller's own child (sid == a reused keeper "
        "pid) was owned or its subtree was walked" % (sorted(gotp), read))
if Y in gotp:
    ok("[P2] control: an owned process below a non-owned node that is not a caller's child is still found")
else:
    bad("[P2] control: the walk no longer traverses non-owned nodes (Y=%d missing from %r)" % (Y, sorted(gotp)))

# --- T048 V4 round 8, V4R8-2: "was the report written?" is decided from durable state (report_prepare ->
# report_verified). Driven with the REAL fc_common.py next to the module under test (its body_hash_of is the one
# implementation). [R1] no file yet -> not written; [R1b] the file that was there BEFORE the writer started (same
# content, same body_hash -- a stale report of an identical earlier run) -> NOT written; [R1c] a new file at the path
# with the recorded body_hash -> written, the recorded code; [R1d] a new file with another body_hash -> not written;
# [R1e] a torn / malformed marker -> not written; [R1f] the exit code recorded is the one given (here 4).
import json, tempfile  # noqa: E402
FCC = os.path.join(os.path.dirname(os.path.abspath(os.environ["SUP"])), "..", "lib", "fc_common.py")
spec2 = importlib.util.spec_from_file_location("fcc", FCC)
fcc = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(fcc)
R = tempfile.mkdtemp(prefix="fc_sup_unit_r1.")
try:
    td = os.path.join(R, "fc_baseline_replay.unit"); os.mkdir(td)
    out = os.path.join(R, "out.json")
    body = {"result": "ok", "n": 1}

    def write_report(path, b):
        doc = dict(b); doc["schema"] = "unit-test/v1"
        doc["body_hash"] = fcc.body_hash_of(doc); doc["run_meta"] = {}
        tmp = path + ".tmp"
        open(tmp, "w").write(json.dumps(doc))
        os.replace(tmp, path)

    m.report_prepare(td, FCC, out, "unit-test/v1", json.dumps(body), 0)
    r1 = m.report_verified(td)
    write_report(out, body)
    r1c = m.report_verified(td)
    # stale: a report identical to the one about to be written is already there BEFORE prepare
    m.report_prepare(td, FCC, out, "unit-test/v1", json.dumps(body), 0)
    r1b = m.report_verified(td)
    write_report(out, dict(body, n=2))
    r1d = m.report_verified(td)
    m.report_prepare(td, FCC, out, "unit-test/v1", json.dumps(body), 4)
    write_report(out, body)
    r1f = m.report_verified(td)
    open(os.path.join(td, m.REPORT_MARKER), "w").write('{"v": 1, "out": ')
    r1e = m.report_verified(td)
    for tag, got_, want_, why in (("R1", r1, None, "no file at the path yet"),
                                  ("R1c", r1c, 0, "a new file carrying the recorded body_hash"),
                                  ("R1b", r1b, None, "the identical report that was there BEFORE the writer started"),
                                  ("R1d", r1d, None, "a new file with a different body_hash"),
                                  ("R1f", r1f, 4, "the code recorded with the report (4) is the one returned"),
                                  ("R1e", r1e, None, "a torn marker")):
        if got_ == want_:
            ok("[%s] report_verified: %s -> %r" % (tag, why, got_))
        else:
            bad("[%s] report_verified: %s -> %r (want %r)" % (tag, why, got_, want_))
finally:
    shutil.rmtree(R, ignore_errors=True)

# --- T048 V4 round 9 (V4R9-3/4/5 + the V4R9-1 structural derivation). Every case below is the oracle of one reviewer
# mutant that SURVIVED round 2 (RVM-B / RVM-H / RVM-I / RVM-J) or of one round-3 mutant (V4R9-M*):
# [R9B]          a NEW file at --out without any body_hash key is NOT the report (RVM-B: "key absent" member).
# [R9ID-ctime/-mtime/-size]  identity = dev+ino+ctime+mtime+size: a new report that got the OLD inode number (deleted
#                between prepare and the writer, inode reused) differs from `pre` in ctime / mtime / size only --
#                each field alone must make it "written" (RVM-H and one row per field).
# [R9OWN-I]      a caller's pre-existing child is recognised by (pid, START TIME): a reused pid with another start time
#                is not the caller's child (RVM-I).
# [R9OWN-J]      the keeper is recognised by (pid, START TIME): a reused keeper pid is not the keeper (RVM-J).
# [R9DEC]        decide_code / main_cause: the ONE exit-code derivation, row by row.
# [R9GC]         gc_statedirs removes ONLY the state directories of provably dead owners (another boot, or no live
#                process with that pid + start time), only the files this module writes, never a symlink.
import json as _json  # noqa: E402
R9 = tempfile.mkdtemp(prefix="fc_sup_unit_r9.")
try:
    td = os.path.join(R9, "fc_baseline_replay.state.unit"); os.mkdir(td)
    out = os.path.join(R9, "out.json")
    body = {"result": "ok", "n": 9}
    m.report_prepare(td, FCC, out, "unit-test/v1", _json.dumps(body), 0)
    want_hash = _json.loads(open(os.path.join(td, m.REPORT_MARKER)).read())["body_hash"]
    nohash = dict(body); nohash["schema"] = "unit-test/v1"; nohash["run_meta"] = {}
    open(out + ".tmp", "w").write(_json.dumps(nohash)); os.replace(out + ".tmp", out)
    got = m.report_verified(td)
    if got is None:
        ok("[R9B] a new file at --out with NO body_hash key is not the report -> None")
    else:
        bad("[R9B] a new file without a body_hash key was read as the report (code %r)" % (got,))
    # identity rows: the report (correct body_hash) is ON DISK. `pre` is what _identity (the function UNDER TEST, in
    # whatever shape it has) returns for an inode-reuse TWIN of that file: same dev + ino, ONE of ctime / mtime / size
    # different (the old report, deleted before the writer's temp file reused its inode). Computed by calling the
    # module's own _identity with an lstat that returns the twin (os replaced in the module's namespace only).
    write_report(out, body)
    import types as _types
    real = os.lstat(out)
    now = m._identity(out)

    class _Shim:
        def __init__(self, st):
            self._st = st

        def lstat(self, _p):
            return self._st

        def __getattr__(self, name):
            return getattr(os, name)
    for fname in ("ctime", "mtime", "size"):
        twin = _types.SimpleNamespace(st_dev=real.st_dev, st_ino=real.st_ino, st_ctime_ns=real.st_ctime_ns,
                                      st_mtime_ns=real.st_mtime_ns, st_size=real.st_size)
        attr = {"ctime": "st_ctime_ns", "mtime": "st_mtime_ns", "size": "st_size"}[fname]
        setattr(twin, attr, getattr(twin, attr) + 1)
        saved_os = m.os
        m.os = _Shim(twin)
        try:
            pre = m._identity(out)
        finally:
            m.os = saved_os
        open(os.path.join(td, m.REPORT_MARKER), "w").write(_json.dumps(
            {"v": 1, "out": os.path.abspath(out), "pre": pre, "body_hash": want_hash, "code": 0}))
        got = m.report_verified(td)
        if got == 0:
            ok("[R9ID-%s] a written report whose (dev, ino) equal the old file's but whose %s differs is WRITTEN" % (fname, fname))
        else:
            bad("[R9ID-%s] a written report differing from the old file only in %s read as NOT written (%r) -- the %s "
                "half of the identity is not used" % (fname, fname, got, fname))
    # control needle: the identical identity is still "not written" (the rows above are not vacuous)
    open(os.path.join(td, m.REPORT_MARKER), "w").write(_json.dumps(
        {"v": 1, "out": os.path.abspath(out), "pre": list(now), "body_hash": want_hash, "code": 0}))
    if m.report_verified(td) is None:
        ok("[R9ID-needle] control: pre == the current identity -> not written")
    else:
        bad("[R9ID-needle] control: an unchanged identity read as written")
finally:
    shutil.rmtree(R9, ignore_errors=True)

# ownership: start-time halves
KP, KS, P = 910001, 777, 910002
saved = m._ident
try:
    m._ident = lambda pid: {P: (KP, 101), KP: (4242, KS + 5)}.get(pid)
    owner = m._main_owner(KP, KS, {(P, 100)})
    oi, oj = owner(P), owner(KP)
finally:
    m._ident = saved
if oi is True:
    ok("[R9OWN-I] pid %d with another start time than the caller's recorded child is NOT the caller's child (it is in "
       "the keeper's session: owned)" % P)
else:
    bad("[R9OWN-I] a reused pid of a caller's child (other start time) was treated as the caller's child (%r)" % (oi,))
if oj is False:
    ok("[R9OWN-J] the keeper's pid with another start time (reused, other session) is NOT owned")
else:
    bad("[R9OWN-J] a reused keeper pid with another start time was owned (%r)" % (oj,))

# the ONE derivation
DROWS = [((None, ("code", 3)), 3), ((0, ("code", 3)), 0), ((None, ("stopped", 15)), 143), ((0, ("stopped", 15)), 0),
         ((None, ("killed", 9)), 137), ((0, ("killed", 9)), 0), ((None, ("main_gone", 0)), 137),
         ((0, ("main_gone", 0)), 0), ((None, ("lost", 0)), 4), ((0, ("lost", 0)), 0), ((None, ("internal", 0)), 4),
         ((4, ("internal", 0)), 4), ((2, ("stopped", 2)), 2)]
for (v, c), w in DROWS:
    g_ = m.decide_code(v, c)
    (ok if g_ == w else bad)("[R9DEC] decide_code(%r, %r) = %r (want %r)" % (v, c, g_, w))
CROWS = [((0 << 8, 0), ("code", 0)), ((3 << 8, 15), ("code", 3)), ((9, 0), ("killed", 9)), ((9, 15), ("stopped", 15)),
         ((None, 2), ("stopped", 2)), ((None, 0), ("lost", 0))]
for (kst, sig), w in CROWS:
    g_ = m.main_cause(kst, sig)
    (ok if g_ == w else bad)("[R9DEC] main_cause(%r, %r) = %r (want %r)" % (kst, sig, g_, w))
for (kst, sig, v), w in (((9, 0, 0), 0), ((9, 15, 0), 0), ((None, 15, 0), 0), ((9, 15, None), 143), ((0, 0, 3), 3)):
    g_ = m.main_exit_code(kst, sig, v)
    (ok if g_ == w else bad)("[R9DEC] main_exit_code(kst=%r, stop=%r, verified=%r) = %r (want %r)" % (kst, sig, v, g_, w))

# gc_statedirs
G9 = tempfile.mkdtemp(prefix="fc_sup_unit_gc.")
try:
    boot = m._boot_id()
    me_start = m._ident(os.getpid())[1]
    dead = subprocess.Popen(["true"]); dead.wait()
    dpid = dead.pid
    def mk(name, files=(m.REPORT_MARKER,)):
        d = os.path.join(G9, name); os.mkdir(d)
        for f in files:
            open(os.path.join(d, f), "w").write("x")
        return d
    live = mk("%s%s.%d.%d.aaaa" % (m.STATE_PREFIX, boot, os.getpid(), me_start))
    deadd = mk("%s%s.%d.%d.bbbb" % (m.STATE_PREFIX, boot, dpid, 12345), (m.REPORT_MARKER, ".report.x1"))
    other_boot = mk("%s%s.%d.%d.cccc" % (m.STATE_PREFIX, "ffffffffffff" if boot != "ffffffffffff" else "eeeeeeeeeeee",
                                         os.getpid(), me_start))
    extra = mk("%s%s.%d.%d.dddd" % (m.STATE_PREFIX, boot, dpid, 12345), (m.REPORT_MARKER, "keepme"))
    plain = mk("fc_baseline_replay.unrelated", ("data",))
    tgt = os.path.join(G9, "target"); os.mkdir(tgt); open(os.path.join(tgt, m.REPORT_MARKER), "w").write("x")
    link = os.path.join(G9, "%s%s.%d.%d.eeee" % (m.STATE_PREFIX, boot, dpid, 12345)); os.symlink(tgt, link)
    n = m.gc_statedirs(G9)
    rows = [("live owner kept", os.path.isdir(live) and os.path.exists(os.path.join(live, m.REPORT_MARKER))),
            ("dead owner removed", not os.path.lexists(deadd)),
            ("other boot removed", not os.path.lexists(other_boot)),
            ("unknown file kept (no recursive delete)", os.path.exists(os.path.join(extra, "keepme"))),
            ("non-state dir untouched", os.path.exists(os.path.join(plain, "data"))),
            ("symlink untouched, its target's content intact",
             os.path.islink(link) and os.path.exists(os.path.join(tgt, m.REPORT_MARKER))),
            ("count = 2", n == 2)]
    for why, cond in rows:
        (ok if cond else bad)("[R9GC] %s" % why)
finally:
    shutil.rmtree(G9, ignore_errors=True)

# --- T048 V4 round 10 (round-3 review, NO-GO: V4R10-1 IMPORTANT + V4R10-3/5 MINOR). Each row is the oracle of a
# reviewer mutant that SURVIVED round 3 or of a round-10 fixer mutant (test_fastcycle_r6_mutations.sh V4R10-*):
# [R10GC-start]   same boot, a LIVE pid, another start time -> the owner is dead (pid reused): removed (RV3-02).
# [R10GC-boot]    a directory named with the boot id READ BY THIS TEST from /proc (not through the module) and this
#                 test's own pid + start time is KEPT -- the gc compares against the REAL boot id (RV3-03).
# [R10GC-bootname] make_statedir names the directory with the real boot id (RV3-03, the naming half).
# [R10LEASE]      V4R10-1, the reviewer's demo as a row: "main" makes its state directory (taking the lease), forks a
#                 "keeper", is SIGKILLed; a gc in ANOTHER process must keep the directory while the keeper lives, and
#                 remove it once the keeper is gone too (the lease is released by the kernel).
# [R10LEASE-made] the lease is held (an independent open + flock LOCK_NB fails) and close-on-exec (never inherited
#                 by an exec'd worker, gate or hook).
# [R10LEASE-held / -free / -odd / -none] dead owner + a lease a live process holds -> kept; + a free lease -> removed
#                 with its lease; + a lease that is a SYMLINK -> kept (not provably free); + no lease at all (main
#                 died before taking it: no keeper can exist) -> removed.
# [R10HASH]       a new file at --out whose body_hash is the EMPTY string is not the report (RV3-11).
# [R10ATOMIC]     the marker at its final name is the very inode report_prepare wrote, fsynced, under a temp name: a
#                 rename, never an in-place write/copy a concurrent reader could see half-written (RV3-10).
import fcntl as _fcntl  # noqa: E402


def in_child(fn, secs=15):
    """run fn() in a forked child bounded by secs (round 11, V4R11-1: a case that BLOCKS must fail as a row, never hang
    the suite). Returns repr(result), "exit <code>" (SystemExit), "raise <Type>: <msg>", or "TIMEOUT" (the child --
    a validated pid > 1 this test forked -- is then SIGKILLed through its pidfd, §11.4.263)."""
    sys.stdout.flush(); sys.stderr.flush()
    rr, ww = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(rr)
        try:
            out = repr(fn())
        except SystemExit as e:
            out = "exit %r" % (e.code,)
        except BaseException as e:  # noqa: BLE001
            out = "raise %s: %s" % (type(e).__name__, e)
        try:
            os.write(ww, out.encode("utf-8", "replace")[:4000])
        finally:
            os._exit(0)
    os.close(ww)
    assert pid > 1 and pid != os.getpid()
    pfd = os.pidfd_open(pid)
    end = time.monotonic() + secs
    st = None
    while time.monotonic() < end:
        got, st_ = os.waitpid(pid, os.WNOHANG)
        if got == pid:
            st = st_
            break
        time.sleep(0.01)
    if st is None:
        signal.pidfd_send_signal(pfd, signal.SIGKILL)
        os.waitpid(pid, 0)
        os.close(pfd); os.close(rr)
        return "TIMEOUT"
    os.close(pfd)
    data = b""
    while True:
        c = os.read(rr, 4096)
        if not c:
            break
        data += c
    os.close(rr)
    return data.decode("utf-8", "replace")


G10 = tempfile.mkdtemp(prefix="fc_sup_unit_r10.")
try:
    proc_boot = open("/proc/sys/kernel/random/boot_id").read().strip().replace("-", "")[:12]
    me_start = m._ident(os.getpid())[1]
    dead = subprocess.Popen(["true"]); dead.wait()
    dpid = dead.pid

    def mk10(name, files=(m.REPORT_MARKER,)):
        d = os.path.join(G10, name); os.mkdir(d)
        for f in files:
            open(os.path.join(d, f), "w").write("x")
        return d
    restart = mk10("%s%s.%d.%d.r10a" % (m.STATE_PREFIX, proc_boot, os.getpid(), me_start + 1))
    realboot = mk10("%s%s.%d.%d.r10b" % (m.STATE_PREFIX, proc_boot, os.getpid(), me_start))
    held = mk10("%s%s.%d.%d.r10c" % (m.STATE_PREFIX, proc_boot, dpid, 12345), (m.REPORT_MARKER, "lease"))
    hfd = os.open(os.path.join(held, "lease"), os.O_RDONLY)
    _fcntl.flock(hfd, _fcntl.LOCK_EX)              # a live holder (this test)
    free = mk10("%s%s.%d.%d.r10d" % (m.STATE_PREFIX, proc_boot, dpid, 12345), (m.REPORT_MARKER, "lease"))
    odd = mk10("%s%s.%d.%d.r10e" % (m.STATE_PREFIX, proc_boot, dpid, 12345))
    os.symlink(os.path.join(free, "lease"), os.path.join(odd, "lease"))
    none_ = mk10("%s%s.%d.%d.r10f" % (m.STATE_PREFIX, proc_boot, dpid, 12345))
    gcres = in_child(lambda: m.gc_statedirs(G10), 20)   # bounded: a blocking lease probe (RV4-04) fails as a row
    os.close(hfd)
    rows = [("R10GC-start", "same boot + a live pid with ANOTHER start time (pid reused) -> removed",
             not os.path.lexists(restart)),
            ("R10GC-boot", "named with the boot id read from /proc by the test + a live owner -> kept",
             os.path.isdir(realboot)),
            ("R10LEASE-held", "dead owner, lease held by a live process -> kept, and gc RETURNED (%s)" % gcres,
             os.path.isdir(held) and gcres != "TIMEOUT"),
            ("R10LEASE-free", "dead owner, a free lease -> removed (lease included)", not os.path.lexists(free)),
            ("R10LEASE-odd", "dead owner, the lease is a symlink (not provably free) -> kept", os.path.isdir(odd)),
            ("R10LEASE-none", "dead owner, never leased (no keeper can exist) -> removed", not os.path.lexists(none_))]
    for tag, why, cond in rows:
        (ok if cond else bad)("[%s] gc_statedirs: %s" % (tag, why))

    # make_statedir: the real boot id in the name, the lease held + close-on-exec
    sd = m.make_statedir(G10)
    lfd = m.STATE.get("lease")
    (ok if ("." + proc_boot + ".") in os.path.basename(sd) else bad)(
        "[R10GC-bootname] make_statedir names the directory with the real boot id %s (%s)" % (proc_boot, os.path.basename(sd)))
    try:
        probe = os.open(os.path.join(sd, getattr(m, "LEASE_NAME", "lease")), os.O_RDONLY)
    except OSError:
        probe = None
    held_ok = False
    if probe is not None:
        try:
            _fcntl.flock(probe, _fcntl.LOCK_EX | _fcntl.LOCK_NB)
        except BlockingIOError:
            held_ok = True
        os.close(probe)
    cloexec = isinstance(lfd, int) and bool(_fcntl.fcntl(lfd, _fcntl.F_GETFD) & _fcntl.FD_CLOEXEC)
    (ok if held_ok and cloexec else bad)("[R10LEASE-made] make_statedir holds the lease (independent flock LOCK_NB "
                                          "refused: %s) on a close-on-exec fd (%s)" % (held_ok, cloexec))
    if isinstance(lfd, int):
        os.close(lfd)
    m.STATE["lease"] = None
    m.remove_statedir(sd)

    # [R10LEASE] the reviewer's demo: main SIGKILLed, keeper alive, gc in ANOTHER process
    D10 = os.path.join(G10, "demo"); os.mkdir(D10)
    rp, wp = os.pipe()
    mpid = os.fork()
    if mpid == 0:
        try:
            sd2 = m.make_statedir(D10)
            open(os.path.join(sd2, m.REPORT_MARKER), "w").write("{}")
            kp = os.fork()
            if kp == 0:
                os.close(wp)
                time.sleep(4)
                os._exit(0)
            os.write(wp, ("%d %s\n" % (kp, sd2)).encode())
            os.kill(os.getpid(), signal.SIGKILL)
        finally:
            os._exit(9)
    os.close(wp)
    msg = b""
    while not msg.endswith(b"\n"):
        c = os.read(rp, 4096)
        if not c:
            break
        msg += c
    os.close(rp)
    os.waitpid(mpid, 0)
    kpid, sd2 = msg.decode().split()
    kpid = int(kpid)
    alive = os.path.exists("/proc/%d" % kpid)
    n1 = m.gc_statedirs(D10)
    kept = os.path.isdir(sd2) and os.path.exists(os.path.join(sd2, m.REPORT_MARKER))
    end = time.monotonic() + 30
    while os.path.exists("/proc/%d" % kpid) and time.monotonic() < end:
        time.sleep(0.05)
    n2 = m.gc_statedirs(D10)
    gone = not os.path.lexists(sd2)
    if alive and kept and n1 == 0 and gone and n2 == 1:
        ok("[R10LEASE] main SIGKILLed, its keeper alive: another process's gc KEEPS the state directory (removed 0); "
           "once the keeper is gone too the next gc removes it (removed 1)")
    else:
        bad("[R10LEASE] keeper alive=%s kept-while-keeper-alive=%s (gc removed %d) removed-after=%s (gc removed %d)"
            % (alive, kept, n1, gone, n2))

    # [R10HASH] an EMPTY body_hash in the report is not the recorded one
    td10 = os.path.join(G10, "fc_baseline_replay.state.unit10"); os.mkdir(td10)
    out10 = os.path.join(G10, "out10.json")
    body10 = {"result": "ok", "n": 10}
    m.report_prepare(td10, FCC, out10, "unit-test/v1", _json.dumps(body10), 0)
    emp = dict(body10); emp["schema"] = "unit-test/v1"; emp["run_meta"] = {}; emp["body_hash"] = ""
    open(out10 + ".tmp", "w").write(_json.dumps(emp)); os.replace(out10 + ".tmp", out10)
    g10 = m.report_verified(td10)
    (ok if g10 is None else bad)("[R10HASH] a new file at --out whose body_hash is EMPTY is not the report -> %r" % (g10,))

    # [R10ATOMIC] the marker is renamed into place: its inode is the temp file's (fd written + fsynced under .report.*)
    seen = []
    real_mkstemp = m.tempfile.mkstemp

    class _TF:
        def __getattr__(self, name):
            return getattr(tempfile, name)

        def mkstemp(self, *a, **k):
            fd, path = real_mkstemp(*a, **k)
            seen.append(os.fstat(fd).st_ino)
            return fd, path
    saved = m.tempfile
    m.tempfile = _TF()
    try:
        m.report_prepare(td10, FCC, out10, "unit-test/v1", _json.dumps(body10), 0)
    finally:
        m.tempfile = saved
    mk_ino = os.stat(os.path.join(td10, m.REPORT_MARKER)).st_ino
    leftovers = [n for n in os.listdir(td10) if n.startswith(".report.")]
    if len(seen) == 1 and mk_ino == seen[0] and not leftovers:
        ok("[R10ATOMIC] the marker is the inode written + fsynced under its temp name (atomic rename, no temp left)")
    else:
        bad("[R10ATOMIC] marker inode %r, temp inode(s) %r, temp files left %r -- not one atomic rename"
            % (mk_ino, seen, leftovers))
finally:
    shutil.rmtree(G10, ignore_errors=True)

# --- T048 V4 round 11 (round-4 review, NO-GO: V4R11-1 IMPORTANT + V4R11-2 MINOR). V4R11-1: gc opened a lease named
# `lease` O_RDONLY without O_NONBLOCK before its type check -- a FIFO there (plantable under a world-writable tmp-parent)
# hung gc forever with the replay locks held. Fixed CLASS-wide (one helper pair, open_owned_dir / open_owned_file, used
# by every file open of the module). Every case that could block runs in a bounded child (in_child): a hang is a row.
# [R11FIFO]          the reviewer's repro: a dead-owner state directory whose `lease` is a FIFO -> gc returns, kept.
# [R11FIFO-foreign]  the same in a directory owned by ANOTHER uid (the /tmp planting attack, real subordinate uid).
# [R11LEASE-uid / -dir / -sock / -mode]  a lease owned by another uid / a directory / a socket / mode 0666 -> kept.
# [R11DIR-mode / -uid]  a state directory writable by others (0777) / owned by another uid -> kept (never opened into).
# [R11DEV]           a device node as the lease (bind mount of /dev/null in a user+mount namespace) -> gc returns,
#                    kept, and the device is NEVER OPENED (spy on os.open inside the namespace).
# [R11NOOPEN-*]      the helpers refuse a FIFO / directory / socket / symlink WITHOUT calling os.open on it (spy).
# [R11RACE-fifo / -symlink / -swap / -dirswap]  the look (fstatat) is made to lie -- what it saw is replaced before the
#                    open: a FIFO (O_NONBLOCK + the post-open type check), a symlink (O_NOFOLLOW), another inode (the
#                    (dev, ino) comparison), another directory -> refused, never blocked.
# [R11TRUNC]         O_TRUNC is applied only after the checks: a refused file keeps its content.
# [R11UID-file / -dir]  the helpers refuse a file / directory owned by another uid.
# [R11MODE]          make_statedir: directory exactly 0700, lease exactly 0600 (RV4-09). [R11MODE-read]: a marker in a
#                    state directory others can write is not trusted (report_verified -> None).
# [R11MKFAIL]        make_statedir's flock-failure path leaves NO directory behind (RV4-15, failure injected).
# [R11GC-nofdleak]   gc closes every lease it acquired, also for a directory it could not remove (RV4-13).
# [R11GC-held]       gc holds the lease THROUGH the removal (an independent probe during remove_statedir is refused,
#                    RV4-12).
# [R11OUT-fifo / -symlink]  a FIFO / a symlink put at --out after report-prepare is not the report, and never blocks.
# [R11LOCK-fifo / -symlink / -uid]  a planted lock file -> BLIND 4 (refused, said), never a hang, never through a link.
# [R11INTR-symlink]  process_ledger never writes INTERRUPTED through a planted symlink (control: a plain directory is
#                    marked). [R11LEDGER-fifo] [R11MARK-fifo] [R11TIMING-fifo]: no supervisor write/read blocks on one.
# [R11PREP-dir]      report_prepare refuses a state directory others can write (no marker written).
import socket as _socket  # noqa: E402
import stat as _st_mod  # noqa: E402
G11 = tempfile.mkdtemp(prefix="fc_sup_unit_r11.")
NS = ["unshare", "--map-users=auto", "--map-groups=auto", "--map-root-user"]


def subuid_own(*paths):
    """chown paths to a uid that is NOT this user's (a subordinate uid, through a user namespace): the real thing,
    no simulation. True when every path ended up owned by another uid."""
    try:
        p = subprocess.run(NS + ["chown", "1000:1000"] + list(paths), capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return False
    def foreign(x):
        try:
            return os.lstat(x).st_uid != os.geteuid()
        except PermissionError:      # inside a directory already given away: not this user's to look into
            return True
    return p.returncode == 0 and all(foreign(x) for x in paths)


class _GeteuidShift:
    """fallback when no subordinate uid is available: os.geteuid() reports another uid (the module reads os.geteuid
    through the os module object) -- said in the row text, never silently."""
    def __enter__(self):
        self.real = os.geteuid
        os.geteuid = lambda: self.real() + 7
        return self

    def __exit__(self, *a):
        os.geteuid = self.real


try:
    proc_boot = open("/proc/sys/kernel/random/boot_id").read().strip().replace("-", "")[:12]
    dead = subprocess.Popen(["true"]); dead.wait()
    dpid = dead.pid
    seq = [0]

    def sdir(tag, lease="file", mode=0o700):
        """a dead-owner state directory, alone in its own fresh parent (so gc over that parent sees only it)"""
        seq[0] += 1
        par = os.path.join(G11, "par%d" % seq[0]); os.mkdir(par)
        d = os.path.join(par, "%s%s.%d.%d.%s" % (m.STATE_PREFIX, proc_boot, dpid, 12345, tag))
        os.mkdir(d); os.chmod(d, mode)
        open(os.path.join(d, m.REPORT_MARKER), "w").write("{}")
        lp = os.path.join(d, "lease")
        if lease == "file":
            fd = os.open(lp, os.O_RDWR | os.O_CREAT, 0o600); os.close(fd)
        elif lease == "fifo":
            os.mkfifo(lp, 0o600)
        elif lease == "dir":
            os.mkdir(lp)
        elif lease == "sock":
            here = os.getcwd(); os.chdir(d)        # bind a short relative name (AF_UNIX path limit)
            try:
                sk = _socket.socket(_socket.AF_UNIX); sk.bind("lease"); sk.close()
            finally:
                os.chdir(here)
        return d

    def gc_alone(d):
        """gc over d's parent, which holds ONLY d (bounded child)"""
        par = os.path.dirname(d)
        return d, in_child(lambda: m.gc_statedirs(par), 15)

    # control needle (the rows below are not vacuous): a dead owner + a FREE regular lease of ours IS removed
    cd, cres = gc_alone(sdir("ctl"))
    (ok if cres == "1" and not os.path.lexists(cd) else bad)(
        "[R11FIFO-needle] control: dead owner + a free regular lease of this user's -> removed (%s)" % cres)
    fd_, fres = gc_alone(sdir("fifo", "fifo"))
    (ok if fres == "0" and os.path.isdir(fd_) else bad)(
        "[R11FIFO] dead owner, `lease` is a FIFO -> gc RETURNS (%s) and keeps the directory (the reviewer's repro: "
        "round 10 blocked here forever)" % fres)
    # the attack itself: a directory owned by ANOTHER uid with a FIFO lease, under the tmp-parent
    fo = sdir("ffor", "fifo")
    foreign = subuid_own(os.path.join(fo, "lease"), os.path.join(fo, m.REPORT_MARKER), fo)
    fo2, fores = gc_alone(fo)
    if foreign:
        (ok if fores == "0" and os.path.isdir(fo2) else bad)(
            "[R11FIFO-foreign] a state directory owned by another uid (real subordinate uid) with a FIFO lease -> gc "
            "returns (%s), kept, nothing opened inside it" % fores)
    else:
        print("SKIP [R11FIFO-foreign] no subordinate uid available (unshare --map-users=auto failed) -- not counted")

    # lease kinds: another uid / a directory / a socket / mode 0666
    lu = sdir("luid")
    os.chmod(os.path.join(lu, "lease"), 0o644)      # readable: without the owner check it COULD be opened + locked
    luid_real = subuid_own(os.path.join(lu, "lease"))
    if luid_real:
        lu2, lures = gc_alone(lu)
        (ok if lures == "0" and os.path.isdir(lu2) else bad)(
            "[R11LEASE-uid] the lease is owned by another uid (real subordinate uid, mode 0644: this user could open "
            "and lock it) -> not provably this replay's -> kept (%s)" % lures)
    else:
        lu2, _ = gc_alone(lu)
        with _GeteuidShift():
            lures = in_child(lambda: m._lease_free(lu2)[0], 10)
        (ok if lures == "False" else bad)("[R11LEASE-uid] SIMULATED (no subordinate uid: os.geteuid shifted) -> "
                                          "_lease_free %s" % lures)
    for kind in ("dir", "sock"):
        kd, kres = gc_alone(sdir("l" + kind, kind))
        (ok if kres == "0" and os.path.isdir(kd) else bad)(
            "[R11LEASE-%s] the lease is a %s -> gc returns (%s), kept" % (kind, {"dir": "directory", "sock": "socket"}[kind], kres))
    lm = sdir("lmode"); os.chmod(os.path.join(lm, "lease"), 0o666)
    lm2, lmres = gc_alone(lm)
    (ok if lmres == "0" and os.path.isdir(lm2) else bad)(
        "[R11LEASE-mode] the lease is writable by others (0666) -> kept (%s)" % lmres)
    dm2, dmres = gc_alone(sdir("dmode", mode=0o777))
    (ok if dmres == "0" and os.path.isdir(dm2) else bad)(
        "[R11DIR-mode] the state directory is writable by others (0777), lease free -> kept (%s)" % dmres)

    # helper-level: the directory owner / file owner checks alone
    hu = os.path.join(G11, "hu"); os.mkdir(hu, 0o700)
    hf = os.path.join(hu, "f"); open(hf, "w").write("x")
    hdir = os.path.join(G11, "hdir"); os.mkdir(hdir, 0o755)
    real_u = subuid_own(hf, hdir)

    def try_open_file():
        dfd = os.open(hu, os.O_RDONLY | os.O_DIRECTORY)
        try:
            return m.open_owned_file("f", os.O_RDONLY, dir_fd=dfd)
        finally:
            os.close(dfd)
    if real_u:
        r1 = in_child(try_open_file, 10)
        r2 = in_child(lambda: m.open_owned_dir(hdir), 10)
        how = "real subordinate uid"
    else:
        with _GeteuidShift():
            r1 = in_child(try_open_file, 10)
            r2 = in_child(lambda: m.open_owned_dir(hdir), 10)
        how = "SIMULATED: os.geteuid shifted"
    (ok if r1.startswith("raise UnsafeFile") else bad)("[R11UID-file] open_owned_file refuses a file owned by another "
                                                       "uid (%s) -> %s" % (how, r1[:90]))
    (ok if r2.startswith("raise UnsafeFile") else bad)("[R11UID-dir] open_owned_dir refuses a directory owned by another "
                                                       "uid (%s) -> %s" % (how, r2[:90]))
    if real_u:
        du = sdir("duid")
        subuid_own(du)
        du2, dures = gc_alone(du)
        (ok if dures == "0" and os.path.isdir(du2) else bad)(
            "[R11DIR-uid] a state directory owned by another uid -> kept (%s)" % dures)

    # [R11DEV] a device node as the lease, in a user + mount namespace (an unprivileged process cannot mknod one)
    dvd = sdir("dev")
    dpar = os.path.dirname(dvd)
    runner = os.path.join(G11, "devrun.py")
    open(runner, "w").write(
        "import importlib.util, os, sys\n"
        "spec = importlib.util.spec_from_file_location('fcsup', sys.argv[1]); m = importlib.util.module_from_spec(spec)\n"
        "spec.loader.exec_module(m)\n"
        "seen = []\n_real = os.open\n"
        "def spy(p, *a, **k):\n    seen.append(os.fsdecode(p))\n    return _real(p, *a, **k)\n"
        "os.open = spy\n"
        "n = m.gc_statedirs(sys.argv[2])\n"
        "os.open = _real\n"
        "print('removed=%d kept=%s opened_lease=%s' % (n, os.path.isdir(sys.argv[3]), 'lease' in seen))\n")
    try:
        pr = subprocess.run(["unshare", "-rm", "sh", "-c",
                             'mount --bind /dev/null "$1/lease" && stat -c %F "$1/lease" && exec python3 -I "$2" "$3" "$4" "$1"',
                             "sh", dvd, runner, os.environ["SUP"], dpar], capture_output=True, text=True, timeout=30)
        dout = (pr.stdout or "").strip().replace("\n", " | ")
        drc = pr.returncode
    except subprocess.TimeoutExpired:
        dout, drc = "TIMEOUT", "TIMEOUT"
    except OSError as e:
        dout, drc = "unshare unavailable: %s" % e, None
    if drc is None or (drc != 0 and "character special" not in dout and dout != "TIMEOUT"):
        print("SKIP [R11DEV] no user+mount namespace (%s) -- not counted" % dout[:120])
    else:
        (ok if drc == 0 and "character special" in dout and "removed=0 kept=True opened_lease=False" in dout else bad)(
            "[R11DEV] the lease is a character device (bind-mounted /dev/null) -> gc returns, keeps it, and NEVER "
            "opens the device: %s (rc %s)" % (dout, drc))

    # helper-level spies: a non-regular name is refused WITHOUT os.open being called on it
    sp = os.path.join(G11, "spy"); os.mkdir(sp, 0o700)
    os.mkfifo(os.path.join(sp, "fifo")); os.mkdir(os.path.join(sp, "dir"))
    sk = _socket.socket(_socket.AF_UNIX); sk.bind(os.path.join(sp, "sock")); sk.close()
    open(os.path.join(sp, "reg"), "w").write("x"); os.symlink(os.path.join(sp, "reg"), os.path.join(sp, "link"))

    def spied(fn):
        def run():
            real = os.open

            def boom(p, *a, **k):
                raise AssertionError("os.open called on %s" % os.fsdecode(p))
            os.open = boom
            try:
                return fn()
            finally:
                os.open = real
        return run
    for nm in ("fifo", "dir", "sock", "link"):
        r = in_child(spied(lambda nm=nm: m.open_owned_file(os.path.join(sp, nm), os.O_RDONLY)), 10)
        (ok if r.startswith("raise UnsafeFile") else bad)(
            "[R11NOOPEN-%s] open_owned_file refuses a %s without opening it -> %s" % (nm, nm, r[:100]))
    r = in_child(spied(lambda: m.open_owned_dir(os.path.join(sp, "fifo"))), 10)
    (ok if r.startswith("raise UnsafeFile") else bad)("[R11NOOPEN-dirfifo] open_owned_dir refuses a FIFO without "
                                                      "opening it -> %s" % r[:100])

    # races: the look lies (what it saw is replaced before the open)
    import types as _types2

    def lying_stat(fake):
        def run_with(fn):
            def run():
                real = os.stat

                def fakestat(p, *a, **k):
                    return fake
                os.stat = fakestat
                try:
                    return fn()
                finally:
                    os.stat = real
            return run
        return run_with

    def fake_of(path, mode=None):
        st = os.stat(path)
        return _types2.SimpleNamespace(st_mode=mode if mode is not None else st.st_mode, st_uid=st.st_uid,
                                       st_dev=st.st_dev, st_ino=st.st_ino)
    rc_ = os.path.join(G11, "race"); os.mkdir(rc_, 0o700)
    rf = os.path.join(rc_, "fifo"); os.mkfifo(rf, 0o600)
    r = in_child(lying_stat(fake_of(rf, _st_mod.S_IFREG | 0o600))(lambda: m.open_owned_file(rf, os.O_RDONLY)), 10)
    (ok if r.startswith("raise UnsafeFile") else bad)(
        "[R11RACE-fifo] the look saw a regular file, a FIFO is there at the open -> refused, never blocked: %s" % r[:100])
    tgt = os.path.join(rc_, "target"); open(tgt, "w").write("t")
    lk = os.path.join(rc_, "link"); os.symlink(tgt, lk)
    r = in_child(lying_stat(fake_of(tgt))(lambda: m.open_owned_file(lk, os.O_RDONLY)), 10)
    (ok if r.startswith("raise OSError") and "Errno 40" in r else bad)(
        "[R11RACE-symlink] the look saw the target, a symlink is there at the open -> refused (ELOOP): %s" % r[:100])
    a_ = os.path.join(rc_, "a"); open(a_, "w").write("AAAA")
    b_ = os.path.join(rc_, "b"); open(b_, "w").write("B")
    r = in_child(lying_stat(fake_of(b_))(lambda: m.open_owned_file(a_, os.O_RDONLY)), 10)
    (ok if r.startswith("raise UnsafeFile") else bad)(
        "[R11RACE-swap] the look saw another inode than the one opened -> refused: %s" % r[:100])
    r = in_child(lying_stat(fake_of(b_))(lambda: m.open_owned_file(a_, os.O_WRONLY | os.O_TRUNC)), 10)
    (ok if r.startswith("raise UnsafeFile") and open(a_).read() == "AAAA" else bad)(
        "[R11TRUNC] a refused O_TRUNC open leaves the file's content intact (%r): %s" % (open(a_).read(), r[:80]))
    d1 = os.path.join(rc_, "d1"); os.mkdir(d1, 0o700)
    d2 = os.path.join(rc_, "d2"); os.mkdir(d2, 0o700)
    r = in_child(lying_stat(fake_of(d2))(lambda: m.open_owned_dir(d1)), 10)
    (ok if r.startswith("raise UnsafeFile") else bad)(
        "[R11RACE-dirswap] open_owned_dir: the look saw another directory than the one opened -> refused: %s" % r[:100])

    # [R11MODE] make_statedir: exact modes (RV4-09)
    mp = os.path.join(G11, "mkpar"); os.mkdir(mp)
    sd = m.make_statedir(mp)
    dmode = _st_mod.S_IMODE(os.stat(sd).st_mode)
    lmode = _st_mod.S_IMODE(os.stat(os.path.join(sd, m.LEASE_NAME)).st_mode)
    (ok if dmode == 0o700 and lmode == 0o600 else bad)(
        "[R11MODE] make_statedir: state directory %o (want 700), lease %o (want 600)" % (dmode, lmode))
    os.close(m.STATE["lease"]); m.STATE["lease"] = None
    m.remove_statedir(sd)
    # [R11MODE-read] a valid marker + report in a state directory OTHERS can write is not trusted
    td = os.path.join(G11, "fc_baseline_replay.state.mread"); os.mkdir(td, 0o700)
    out = os.path.join(G11, "mread.json")
    body = {"result": "ok", "n": 11}
    m.report_prepare(td, FCC, out, "unit-test/v1", _json.dumps(body), 0)
    write_report(out, body)
    good = m.report_verified(td)
    os.chmod(td, 0o777)
    loose = m.report_verified(td)
    os.chmod(td, 0o700)
    (ok if good == 0 and loose is None else bad)(
        "[R11MODE-read] marker trusted in a 0700 state directory (%r), NOT in a 0777 one (%r)" % (good, loose))
    # [R11PREP-dir] report_prepare refuses a state directory others can write
    tp = os.path.join(G11, "fc_baseline_replay.state.prep"); os.mkdir(tp); os.chmod(tp, 0o777)
    r = in_child(lambda: m.report_prepare(tp, FCC, os.path.join(G11, "prep.json"), "unit-test/v1", _json.dumps(body), 0), 15)
    (ok if r.startswith("raise") and not os.path.exists(os.path.join(tp, m.REPORT_MARKER)) else bad)(
        "[R11PREP-dir] report_prepare into a 0777 state directory -> refused, no marker: %s" % r[:90])
    # [R11OUT-fifo / -symlink]
    m.report_prepare(td, FCC, out, "unit-test/v1", _json.dumps(body), 0)
    real_rep = os.path.join(G11, "real_report.json"); write_report(real_rep, body)
    os.mkfifo(out + ".fifo"); os.replace(out + ".fifo", out)
    r = in_child(lambda: m.report_verified(td), 10)
    (ok if r == "None" else bad)("[R11OUT-fifo] a FIFO at --out after report-prepare -> not the report, never blocks: %s" % r)
    os.unlink(out); os.symlink(real_rep, out)
    r = in_child(lambda: m.report_verified(td), 10)
    (ok if r == "None" else bad)("[R11OUT-symlink] a symlink at --out (to a report carrying the recorded body_hash) "
                                 "-> not the report: %s" % r)

    # [R11MKFAIL] make_statedir: the flock-failure path leaves nothing (RV4-15)
    fp = os.path.join(G11, "mkfail"); os.mkdir(fp)
    import fcntl as _fc3

    def failing():
        def nolock(*a, **k):
            raise OSError(37, "No locks available (injected)")
        _fc3.flock = nolock
        try:
            m.make_statedir(fp)
        except OSError as e:
            return "OSError %s" % e
        return "no error"
    r = in_child(failing, 10)
    left = os.listdir(fp)
    (ok if "OSError" in r and not left else bad)(
        "[R11MKFAIL] make_statedir with flock failing -> OSError and nothing left in the parent: %s left=%r" % (r, left))

    # [R11GC-nofdleak] / [R11GC-held]
    gp = os.path.join(G11, "gcfd"); os.mkdir(gp)

    def mkfree(tag, extra=None):
        d = os.path.join(gp, "%s%s.%d.%d.%s" % (m.STATE_PREFIX, proc_boot, dpid, 12345, tag)); os.mkdir(d, 0o700)
        fd = os.open(os.path.join(d, "lease"), os.O_RDWR | os.O_CREAT, 0o600); os.close(fd)
        if extra:
            open(os.path.join(d, extra), "w").write("x")
        return d
    mkfree("fda"); stuck = mkfree("fdb", "keepme")

    def fds_around_gc():
        before = sorted(os.listdir("/proc/self/fd"))
        n = m.gc_statedirs(gp)
        after = sorted(os.listdir("/proc/self/fd"))
        return (n, before == after, len(after) - len(before))
    r = in_child(fds_around_gc, 15)
    (ok if r == "(1, True, 0)" and os.path.isdir(stuck) else bad)(
        "[R11GC-nofdleak] gc removed 1, kept the one it could not remove, and left no fd open: %s" % r)
    hp = os.path.join(G11, "gcheld"); os.mkdir(hp)
    hd = os.path.join(hp, "%s%s.%d.%d.held" % (m.STATE_PREFIX, proc_boot, dpid, 12345)); os.mkdir(hd, 0o700)
    fd = os.open(os.path.join(hd, "lease"), os.O_RDWR | os.O_CREAT, 0o600); os.close(fd)

    def held_through():
        orig = m.remove_statedir
        probes = []

        def probing(path):
            try:
                pf = os.open(os.path.join(path, "lease"), os.O_RDONLY)
                try:
                    _fcntl.flock(pf, _fcntl.LOCK_EX | _fcntl.LOCK_NB)
                    probes.append("FREE")
                except BlockingIOError:
                    probes.append("held")
                finally:
                    os.close(pf)
            except OSError as e:
                probes.append("noopen %s" % e)
            return orig(path)
        m.remove_statedir = probing
        try:
            return (m.gc_statedirs(hp), probes)
        finally:
            m.remove_statedir = orig
    r = in_child(held_through, 15)
    (ok if r == "(1, ['held'])" else bad)(
        "[R11GC-held] gc holds the lease THROUGH remove_statedir (an independent LOCK_NB probe there is refused): %s" % r)

    # [R11LOCK-*] _lock_one on a planted lock file -> BLIND 4, never a hang, never through a link
    lkd = os.path.join(G11, "locks"); os.mkdir(lkd, 0o755)
    os.mkfifo(os.path.join(lkd, "fifo.lock"))
    ltarget = os.path.join(G11, "victim.lock"); open(ltarget, "w").write("")
    os.symlink(ltarget, os.path.join(lkd, "link.lock"))
    ulock = os.path.join(lkd, "uid.lock"); open(ulock, "w").write(""); os.chmod(ulock, 0o666)
    ulock_real = subuid_own(ulock)
    for nm in ("fifo", "link") + (("uid",) if ulock_real else ()):
        r = in_child(lambda nm=nm: m._lock_one(os.path.join(lkd, nm + ".lock"), "unit"), 10)
        (ok if r == "exit 4" else bad)("[R11LOCK-%s] a planted %s lock file -> BLIND 4 (refused, said), never a hang: %s"
                                       % (nm, {"fifo": "FIFO", "link": "symlink", "uid": "another uid's 0666"}[nm], r))
    if not ulock_real:
        print("SKIP [R11LOCK-uid] no subordinate uid available -- not counted")
    rctl = in_child(lambda: m._lock_one(os.path.join(lkd, "fresh.lock"), "unit") > 2, 10)
    (ok if rctl == "True" else bad)("[R11LOCK-needle] control: a fresh lock file is created and locked -> %s" % rctl)

    # [R11INTR-symlink] / [R11LEDGER-fifo] / [R11MARK-fifo] / [R11TIMING-fifo]
    lt = os.path.join(G11, "fc_baseline_replay.ledgertmp"); os.mkdir(lt, 0o700)
    logd = os.path.join(G11, "logs_sym"); os.mkdir(logd, 0o700)
    victim = os.path.join(G11, "victim.txt"); open(victim, "w").write("VICTIM")
    os.symlink(victim, os.path.join(logd, "INTERRUPTED"))
    logc = os.path.join(G11, "logs_ctl"); os.mkdir(logc, 0o700)
    for nm, d in (("ledger.logs.a", logd), ("ledger.logs.b", logc)):
        open(os.path.join(lt, nm), "wb").write(os.fsencode(d) + b"\0")
    m.DONE["code"] = None
    r = in_child(lambda: m.process_ledger(lt, "unit test"), 15)
    marked = os.path.isfile(os.path.join(logc, "INTERRUPTED")) and not os.path.islink(os.path.join(logc, "INTERRUPTED"))
    (ok if r == "None" and open(victim).read() == "VICTIM" and marked else bad)(
        "[R11INTR-symlink] INTERRUPTED is never written through a planted symlink (victim %r), a plain run-log "
        "directory IS marked (%s): %s" % (open(victim).read(), marked, r))
    lt2 = os.path.join(G11, "fc_baseline_replay.ledgertmp2"); os.mkdir(lt2, 0o700)
    os.mkfifo(os.path.join(lt2, "ledger.wt.fifo"))
    r = in_child(lambda: m.process_ledger(lt2, "unit test"), 10)
    (ok if r == "None" else bad)("[R11LEDGER-fifo] a FIFO among the ledger entries -> process_ledger returns: %s" % r)
    mf = os.path.join(G11, "mark.fifo"); os.mkfifo(mf)
    r = in_child(lambda: m._mark(mf, "x"), 10)
    (ok if r == "None" else bad)("[R11MARK-fifo] _mark on a FIFO -> returns, never blocks: %s" % r)
    tf = os.path.join(G11, "timing.fifo"); os.mkfifo(tf)
    r = in_child(lambda: m._write_timing(tf, 1, 0, 0.0), 10)
    (ok if r == "None" else bad)("[R11TIMING-fifo] _write_timing on a FIFO -> returns, never blocks: %s" % r)
    mreg = os.path.join(G11, "mark.reg")
    m._mark(mreg, "cd_failed")
    (ok if open(mreg).read() == "cd_failed" else bad)("[R11MARK-needle] control: _mark writes a plain marker file")
finally:
    subprocess.run(NS + ["rm", "-rf", G11], capture_output=True)
    shutil.rmtree(G11, ignore_errors=True)

print("----")
print("SUMMARY pass=%d fail=%d" % (N["ok"], N["bad"]))
sys.exit(0 if N["bad"] == 0 else 1)
PY
