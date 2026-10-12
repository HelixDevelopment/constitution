#!/usr/bin/env bash
# =============================================================================
# test_baseline_replay_r2_findings.sh -- permanent regression guard for the
# T048 restart ROUND-2 and ROUND-3 reviews of cycle/baseline_replay.sh
# (docs/qa/t048_restart_round2_20261008/V4_baseline.md,
#  docs/qa/t048_restart_round3_20261008/V4_baseline.md).
#
# Every case drives the REAL script through its real CLI against small,
# hermetic, throwaway git repos.
#
# ROUND 3 (structural, §11.4.276(E)): the per-finding signal cases of rounds 1-2
# (V4-1, V4-12/N4, V4-12/N12, V4-9 here; R6-F11a/b/c in the r6 file; B1 in the
# r4 file) are replaced by ONE stop matrix, case SM:
#     signal  {TERM, INT, HUP, QUIT, KILL}
#   x target  {main pid, supervisor (keeper), worker (the bash replay loop),
#              main's process group, worker's process group}
#   x gate    {quick (finishes in 0.2 s, many runs scheduled), never (sleep 600),
#              ignterm (gate + its child ignore TERM/INT/HUP/QUIT and watch their
#              own cwd), ownsess (a TERM-ignoring child in its own session with a
#              cleared environment), nested (a nested `timeout`, its own process
#              group), daemon (a double-forked setsid daemon)}
# Every repo also carries a post-checkout hook that backgrounds a long sleep.
# For every case: the tool is started through a launcher that RESTORES the
# default disposition of HUP/INT/QUIT/TERM/PIPE (the caller of this suite may
# have any of them ignored -- e.g. nohup, or an interactive shell that ignores
# QUIT), and the target's /proc SigIgn is read before the signal is sent: an
# ignored signal is never sent-and-counted as a pass. Then, with WALL-CLOCK
# deadlines and gates that never end by themselves:
#   - the main pid exits with 128+signal within the deadline (KILL to the main
#     pid: the remaining tree must be gone within the deadline instead);
#   - at that moment ZERO processes of the case remain (by argv: a path under
#     the case directory or the case's exec -a marker), zero temp directories,
#     the replay worktree is gone, every lock is free, every run-log directory
#     carries INTERRUPTED, no further scheduled run started, and the
#     ignterm gate never saw its cwd deleted while it was alive;
#   - a TERM-honouring gate is stopped well inside the grace period (bounds the
#     stop latency);
#   - while the gate ran, no process other than the supervisor held a lock fd;
#   - a non-KILL signal is sent a SECOND time 0.3 s later (a second signal must
#     not cut a stop short).
# Extra rows: the nohup variant (HUP must be detected as ignored and reported
# SKIP-with-reason, never as a pass; the tool must keep running and still stop
# cleanly on TERM), a selfcheck variant, and the double-KILL honest-boundary row.
# T048 V4 round 5 extra rows: sigchld (a caller with SIGCHLD ignored -- inherited
# through exec -- runs a whole replay to completion instead of spinning until the
# timeout), wtaddkill (the worker SIGKILLed DURING `git worktree add`: the
# worktree git leaves `locked: initializing` is really removed), nochildren (a
# supervisor that cannot read /proc/<pid>/task/<tid>/children refuses to run,
# exit 4, nothing started), runsig (a stop signal to ONE run supervisor process
# records that run UNMEASURED "stopped" and the replay goes on to exit 0).
# T048 V4 round 6 extra rows: termign (the caller ignores TERM -- kept ignored,
# nohup semantics -- and INT/QUIT/HUP is sent to the main pid: main must forward
# the signal it received, not a TERM the keeper ignores; round 5 took ~36 s and
# ended in a keeper-deadline SIGKILL), runkill (ONE run supervisor SIGKILLed while
# its gate's double-forked daemon runs: the worker finds no outcome marker and
# aborts the whole replay -- exit 4, no report -- so the keeper stops the daemon
# before the worktree is removed and before any further run).
#
# Defect classes (§11.4.276(C) inventory, see the fixer report):
#   D  host safety: processes / worktrees / temp dirs / locks the tool started
#      that outlive it (the whole stop matrix), disk exhaustion (V4-4 lock incl.
#      linked worktrees and the per-filesystem lock, V4-5 floors measured on the
#      right filesystem, LOCKHOOK lock fd inherited by a hook, PERRUN a process
#      one gate run leaves behind running into the next run).
#   A  a value read as something it is not: V4-2, whitespace ids (WS).
#   C  evidence integrity: V4-10.
#   B  wrong-commit selection: N6, N10.
#
# Env:
#   FC_BR_UNDER_TEST  path of the baseline_replay.sh to test (default: the real
#                     file). The paired-mutation runner points this at a mutant.
#   R2_ONLY           space-separated case tags to run (default: all).
#   SM_SIGNALS SM_TARGETS SM_SHAPES SM_EXTRA   narrow the stop matrix.
# Exit: 0 every selected case held; 1 any NOT ok.
# Runtime: the full stop matrix takes ~10 minutes -- run it in the background
# (§11.4.89).
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
SCRIPT="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok $*"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $*"; }
want() {
  [ -z "${R2_ONLY:-}" ] && return 0
  case " $R2_ONLY " in *" $1 "*) return 0 ;; esac
  return 1
}

WORK="$(mktemp -d)"
# Private lock directory for the tool's per-filesystem lock, so this suite never
# contends with an unrelated replay on the same host.
export FC_REPLAY_LOCK_DIR="$WORK/locks"
mkdir -p "$FC_REPLAY_LOCK_DIR"
# Every process a non-matrix case starts carries the marker "r2t-$$-" (with the
# trailing delimiter: "r2t-1234-" can never match the pid 12345's "r2t-12345-",
# V4R3-11) as a WHOLE argv[0] prefix. §11.4.263: only a validated integer > 1 is
# ever signalled, one pid at a time.
MARK="r2t-$$-"
HOLDER_PID=""

marker_pids() { # live pids whose argv[0] starts with $1 (exact argv element, never a substring of the whole line)
  M="$1" python3 - <<'PY'
import os
m = os.environ["M"]
me, pp = os.getpid(), os.getppid()
for p in os.listdir("/proc"):
    if not p.isdigit() or int(p) in (me, pp) or int(p) <= 1:
        continue
    try:
        st = open("/proc/%s/stat" % p).read()
        if st[st.rindex(") ") + 2:].split()[0] == "Z":
            continue
        argv0 = open("/proc/%s/cmdline" % p, "rb").read().split(b"\0")[0].decode(errors="replace")
    except (OSError, ValueError, IndexError):
        continue
    if argv0.startswith(m):
        print(p)
PY
}
reap_marker() {
  local p
  for p in $(marker_pids "$MARK"); do
    case "$p" in ''|*[!0-9]*) continue ;; esac
    [ "$p" -gt 1 ] && kill -KILL "$p" 2>/dev/null
  done
}
cleanup_all() {
  reap_marker
  case "$HOLDER_PID" in ''|*[!0-9]*) ;; *) [ "$HOLDER_PID" -gt 1 ] && kill -KILL "$HOLDER_PID" 2>/dev/null ;; esac
  rm -rf "$WORK"
}
trap cleanup_all EXIT

# jget <json-file> <python-expr over d>: the JSON is read from the file; the
# expression is always a literal written in THIS test file (never data), so the
# eval() below evaluates only test-authored code.
jget() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("<unreadable>")
    sys.exit(0)
v = eval(sys.argv[2], {"d": d})
print(json.dumps(v) if not isinstance(v, str) else v)
PY
}

g() { git -c user.email=t@t.t -c user.name=t "$@"; }
mk_repo() {
  mkdir -p "$1"; g init -q "$1"; echo hello >"$1/f.txt"
  g -C "$1" add f.txt; g -C "$1" commit -q -m "base commit"
}
wt_count() { git -C "$1" worktree list --porcelain 2>/dev/null | grep -c '^worktree '; }
wait_for_lines() { # <file> <n> <tenths>
  local i=0
  while [ "$i" -lt "$3" ]; do
    [ -f "$1" ] && [ "$(wc -l <"$1")" -ge "$2" ] && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
R() {
  local repo="$1" wtr="$2" out="$3"; shift 3
  bash "$SCRIPT" replay --commit "$(git -C "$repo" rev-parse HEAD)" \
    --repo-root "$repo" --worktree-root "$wtr" --min-free-kb 0 --out "$out" "$@"
}

[ -f "$SCRIPT" ] || { echo "NOT ok script under test not found: $SCRIPT"; exit 1; }

# =============================================================================
# SM: the stop matrix (round 3, structural). See the header.
# =============================================================================
if want SM; then
  SM_OUT="$WORK/sm.out"
  SCRIPT="$SCRIPT" WORK="$WORK" python3 - >"$SM_OUT" 2>&1 <<'PYSM'
import os, shutil, signal, subprocess, sys, time

SCRIPT, WORK = os.environ["SCRIPT"], os.environ["WORK"]
GRACE = 2.0
SIGS = os.environ.get("SM_SIGNALS", "TERM INT HUP QUIT KILL").split()
TARGETS = os.environ.get("SM_TARGETS", "main supervisor worker main-group worker-group").split()
SHAPES = os.environ.get("SM_SHAPES", "quick never ignterm ownsess nested daemon").split()
EXTRA = os.environ.get("SM_EXTRA", "nohup selfcheck doublekill sigchld wtaddkill nochildren runsig termign runkill").split()
HONOUR = {"quick", "never", "nested", "daemon"}     # every process honours TERM
N = {"ok": 0, "bad": 0, "skip": 0}


def ok(m):
    N["ok"] += 1; print("ok [SM] " + m, flush=True)


def bad(m):
    N["bad"] += 1; print("NOT ok [SM] " + m, flush=True)


def skip(m):
    N["skip"] += 1; print("SKIP [SM] " + m, flush=True)


TICK = 't() { bash -c \'exec -a "$0" sleep "$1"\' "fcsm-$FCSM_TOK-tick" "$1"; }\n'
GATES = {
    "quick": 'echo x >>"$FCSM_CASE/calls"\necho $$ >"$FCSM_CASE/started"\nexec -a "fcsm-$FCSM_TOK-quick" sleep 0.2\n',
    "never": 'echo x >>"$FCSM_CASE/calls"\necho $$ >"$FCSM_CASE/started"\nexec -a "fcsm-$FCSM_TOK-never" sleep 600\n',
    "ignterm": TICK + "trap '' TERM INT HUP QUIT\n"
               'echo x >>"$FCSM_CASE/calls"\n'
               '( while :; do [ -e "$PWD/f.txt" ] || echo cwd_gone >>"$FCSM_CASE/cwdgone"; t 0.05; done ) &\n'
               'echo $$ >"$FCSM_CASE/started"\nwhile :; do t 0.2; done\n',
    "ownsess": 'echo x >>"$FCSM_CASE/calls"\n'
               'setsid -f env -i bash -c \'trap "" TERM INT HUP QUIT; exec -a "$0" sleep 600\' "fcsm-$FCSM_TOK-ownsess-child"\n'
               'echo $$ >"$FCSM_CASE/started"\nexec -a "fcsm-$FCSM_TOK-ownsess-gate" sleep 600\n',
    "nested": 'echo x >>"$FCSM_CASE/calls"\n'
              'timeout 600 bash -c \'exec -a "$0" sleep 600\' "fcsm-$FCSM_TOK-nested" &\n'
              'echo $$ >"$FCSM_CASE/started"\nwait\n',
    "daemon": 'echo x >>"$FCSM_CASE/calls"\n'
              '( setsid bash -c \'exec -a "$0" sleep 600\' "fcsm-$FCSM_TOK-daemon" & )\n'
              'echo $$ >"$FCSM_CASE/started"\nexec -a "fcsm-$FCSM_TOK-daemongate" sleep 600\n',
}
HOOK = '#!/bin/bash\nbash -c \'exec -a "$0" sleep 600\' "fcsm-$FCSM_TOK-hook" &\nexit 0\n'


def stat(pid):
    try:
        st = open("/proc/%d/stat" % pid).read()
        f = st[st.rindex(") ") + 2:].split()
        return f[0], int(f[1]), int(f[2])
    except (OSError, ValueError, IndexError):
        return None


def alive(pid):
    s = stat(pid)
    return s is not None and s[0] != "Z"


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


def comm(pid):
    try:
        return open("/proc/%d/comm" % pid).read().strip()
    except OSError:
        return ""


def sigign(pid):
    try:
        for line in open("/proc/%d/status" % pid):
            if line.startswith("SigIgn:"):
                return int(line.split()[1], 16)
    except (OSError, ValueError):
        pass
    return None


def case_procs(case, tok):
    pre, mk = case + "/", "fcsm-%s-" % tok
    out = []
    me = os.getpid()
    for p in os.listdir("/proc"):
        if not p.isdigit() or int(p) <= 1 or int(p) == me:
            continue
        pid = int(p)
        s = stat(pid)
        if s is None or s[0] == "Z":
            continue
        try:
            argv = [a.decode(errors="replace") for a in open("/proc/%s/cmdline" % p, "rb").read().split(b"\0") if a]
        except OSError:
            continue
        if any(a.startswith(pre) or a.startswith(mk) for a in argv):
            out.append((pid, " ".join(argv)))   # full line: callers match on it; messages truncate
    return out


def lock_files(case, repo):
    fs = [os.path.join(repo, ".git", "fc_baseline_replay.lock")]
    ld = os.path.join(case, "locks")
    if os.path.isdir(ld):
        fs += [os.path.join(ld, f) for f in os.listdir(ld)]
    return fs


def lock_holders(case, tok, repo):
    want = set(os.path.realpath(f) for f in lock_files(case, repo))
    out = []
    for pid, _ in case_procs(case, tok):
        try:
            for fd in os.listdir("/proc/%d/fd" % pid):
                try:
                    if os.path.realpath(os.readlink("/proc/%d/fd/%s" % (pid, fd))) in want:
                        out.append(pid); break
                except OSError:
                    pass
        except OSError:
            pass
    return out


def locks_free(case, repo):
    busy = []
    for f in lock_files(case, repo):
        if not os.path.exists(f):
            continue
        if subprocess.run(["flock", "-n", f, "true"]).returncode != 0:
            busy.append(f)
    return busy


def force_clean(case, tok, repo):
    for pid, _ in case_procs(case, tok):
        try:
            fd = os.pidfd_open(pid)
            signal.pidfd_send_signal(fd, signal.SIGKILL)
            os.close(fd)
        except OSError:
            pass
    time.sleep(0.3)
    subprocess.run(["git", "-C", repo, "worktree", "prune"], capture_output=True)


def g(*a):
    subprocess.run(["git", "-c", "user.email=t@t.t", "-c", "user.name=t"] + list(a), check=True,
                   capture_output=True)


SEQ = [0]


def setup(name, shape):
    SEQ[0] += 1
    case = os.path.join(WORK, "sm", "%03d-%s" % (SEQ[0], name))
    repo = os.path.join(case, "repo")
    os.makedirs(os.path.join(case, "tmp"))
    os.makedirs(os.path.join(case, "locks"))
    g("init", "-q", repo)
    open(os.path.join(repo, "f.txt"), "w").write("hello\n")
    g("-C", repo, "add", "f.txt")
    g("-C", repo, "commit", "-q", "-m", "base")
    hook = os.path.join(repo, ".git", "hooks", "post-checkout")
    open(hook, "w").write(HOOK)
    os.chmod(hook, 0o755)
    gate = os.path.join(case, "gate.sh")
    if shape:
        open(gate, "w").write("#!/bin/bash\n" + GATES[shape])
        os.chmod(gate, 0o755)
    tok = "%d.%d" % (os.getpid(), SEQ[0])
    return case, repo, gate, tok


def launch(case, repo, gate, tok, shape, nohup=False, subcmd="replay", cold=None, chld_ign=False, script=None,
           term_ign=False):
    wtr = os.path.join(case, "wt dir'q")   # a space and a quote in every worktree path
    env = dict(os.environ)
    env.update(TMPDIR=os.path.join(case, "tmp"), FC_REPLAY_LOCK_DIR=os.path.join(case, "locks"),
               FC_BR_STOP_GRACE_S=str(int(GRACE)), FCSM_CASE=case, FCSM_TOK=tok)
    env.pop("FC_OUT", None)
    if subcmd == "replay":
        head = subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        args = ["replay", "--commit", head, "--repo-root", repo, "--worktree-root", wtr, "--min-free-kb", "0",
                "--min-free-kb-objects", "0", "--gate-cmd", gate,
                "--cold-runs", str(cold) if cold is not None else ("400" if shape == "quick" else "3"),
                "--warm-runs", "0", "--timeout-s", "600", "--out", os.path.join(case, "out.json")]
    else:
        args = ["selfcheck", "--out", os.path.join(case, "out.json")]

    def pre():
        for s in (signal.SIGHUP, signal.SIGINT, signal.SIGQUIT, signal.SIGTERM, signal.SIGPIPE):
            signal.signal(s, signal.SIG_DFL)
        signal.pthread_sigmask(signal.SIG_SETMASK, [])
        if chld_ign:
            signal.signal(signal.SIGCHLD, signal.SIG_IGN)
        if term_ign:
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
        os.setsid()
    argv = (["nohup"] if nohup else []) + ["bash", script or SCRIPT] + args
    err = open(os.path.join(case, "main.err"), "w")
    p = subprocess.Popen(argv, env=env, preexec_fn=pre, stdin=subprocess.DEVNULL, stdout=err, stderr=err)
    return p, wtr


def wait_file_lines(path, n, secs):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        try:
            if len(open(path).read().splitlines()) >= n:
                return True
        except OSError:
            pass
        time.sleep(0.05)
    return False


def keeper_of(main):
    k = [c for c in children(main) if comm(c) == "fc-keeper"]
    return k[0] if k else None


def worker_of(main):
    base = keeper_of(main) or main
    b = [c for c in children(base) if comm(c) == "bash"]
    return b[0] if b else None


def resolve(target, main):
    """-> (kind, id, disposition-pid, label) or None. kind 'pid' or 'group'."""
    if target == "main":
        return ("pid", main, main, "main pid %d" % main)
    if target == "supervisor":
        k = keeper_of(main)
        return ("pid", k, k, "supervisor (keeper) pid %d" % k) if k else None
    if target == "worker":
        w = worker_of(main)
        return ("pid", w, w, "worker pid %d" % w) if w else None
    if target == "main-group":
        s = stat(main)
        return ("group", s[2], main, "main's process group %d" % s[2]) if s else None
    if target == "worker-group":
        w = worker_of(main)
        s = stat(w) if w else None
        return ("group", s[2], w, "worker's process group %d" % s[2]) if s else None
    return None


def send(t, signo, case, tok):
    kind, ident = t[0], t[1]
    if not isinstance(ident, int) or ident <= 1:          # §11.4.263
        return False
    if kind == "group":
        if ident == os.getpgrp():
            return False
        # the group must contain a process of THIS case (never a foreign group)
        if not any(stat(p) and stat(p)[2] == ident for p, _ in case_procs(case, tok)):
            return False
        os.killpg(ident, signo)
        return True
    if ident not in [p for p, _ in case_procs(case, tok)]:
        return False
    fd = os.pidfd_open(ident)
    try:
        signal.pidfd_send_signal(fd, signo)
    finally:
        os.close(fd)
    return True


def count(path):
    try:
        return len(open(path).read().splitlines())
    except OSError:
        return 0


def postcheck(case, repo, wtr, tok, n_at_sig, label, rc, want_rc, latency, lat_max, interrupted_expected=True):
    """The common after-stop assertions. Returns a list of problems."""
    probs = []
    left = case_procs(case, tok)
    if left:
        probs.append("processes left: %s" % [(p, l[:140]) for p, l in left[:6]])
    if rc != want_rc:
        probs.append("main rc=%s want %s" % (rc, want_rc))
    if latency is not None and latency > lat_max:
        probs.append("stop took %.1fs > %.1fs" % (latency, lat_max))
    tmpleft = os.listdir(os.path.join(case, "tmp"))
    if tmpleft:
        probs.append("temp entries left: %s" % tmpleft)
    if os.path.isdir(wtr):
        wts = [d for d in os.listdir(wtr) if d.startswith("replay.")]
        if wts:
            probs.append("worktree dirs left: %s" % wts)
        ld = os.path.join(wtr, "replay-logs")
        if interrupted_expected and os.path.isdir(ld):
            noint = [d for d in os.listdir(ld) if not os.path.exists(os.path.join(ld, d, "INTERRUPTED"))]
            if noint:
                probs.append("log dirs without INTERRUPTED: %s" % noint)
    wl = subprocess.run(["git", "-C", repo, "worktree", "list", "--porcelain"], capture_output=True, text=True).stdout
    if wl.count("worktree ") != 1:
        probs.append("git worktree list has %d entries" % wl.count("worktree "))
    busy = locks_free(case, repo)
    if busy:
        probs.append("locks still held: %s" % busy)
    if os.path.exists(os.path.join(case, "cwdgone")):
        probs.append("the gate saw its worktree deleted while it was still running")
    c1 = count(os.path.join(case, "calls"))
    time.sleep(1.0)
    c2 = count(os.path.join(case, "calls"))
    if c2 != c1 or (n_at_sig is not None and c1 > n_at_sig + 1):
        probs.append("scheduled runs kept starting: %s at the signal, %d at exit, %d a second later" % (n_at_sig, c1, c2))
    if probs:
        force_clean(case, tok, repo)
    return probs


def wait_main(p, secs):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        rc = p.poll()
        if rc is not None:
            return rc if rc >= 0 else 128 - rc
        time.sleep(0.02)
    return None


def run_case(sig, target, shape, nohup=False, term_ign=False):
    name = "%s-%s-%s%s%s" % (sig, target, shape, "-nohup" if nohup else "", "-termign" if term_ign else "")
    signo = getattr(signal, "SIG" + sig)
    case, repo, gate, tok = setup(name, shape)
    p, wtr = launch(case, repo, gate, tok, shape, nohup=nohup, term_ign=term_ign)
    started = wait_file_lines(os.path.join(case, "calls"), 2 if shape == "quick" else 1, 90) and \
        wait_file_lines(os.path.join(case, "started"), 1, 30)
    if not started:
        bad("%s: the gate never started (setup failure) -- %s" % (name, open(os.path.join(case, "main.err")).read()[-300:]))
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    time.sleep(0.3)
    main = p.pid
    holders = lock_holders(case, tok, repo)
    allowed = {main, keeper_of(main)}
    if shape == "daemon":   # one case per signal is enough for the fd check
        extra = [h for h in holders if h not in allowed]
        if extra:
            bad("%s: process(es) other than the supervisor hold the replay lock fd: %s" % (name, extra))
        else:
            ok("%s: only the supervisor holds the replay lock (holders %s)" % (name, holders))
    t = resolve(target, main)
    if t is None:
        bad("%s: target %s not found in the tool's process tree" % (name, target))
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    ign = sigign(t[2])
    if ign is None:
        bad("%s: cannot read the disposition of %s" % (name, t[3]))
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    if signo != signal.SIGKILL and (ign >> (signo - 1)) & 1:
        if nohup:
            skip("%s: SIG%s is ignored at entry on %s (nohup) -- the signal cannot stop the tool; not counted as a pass"
                 % (name, sig, t[3]))
            send(t, signo, case, tok)
            time.sleep(1.0)
            if p.poll() is None and alive(int(open(os.path.join(case, "started")).read().split()[0])):
                n0 = count(os.path.join(case, "calls"))
                send(("pid", main, main, ""), signal.SIGTERM, case, tok)
                rc = wait_main(p, GRACE + 15)
                probs = postcheck(case, repo, wtr, tok, n0, name, rc, 143, None, 0)
                if probs:
                    bad("%s: after the ignored SIGHUP, TERM did not stop the tool cleanly: %s" % (name, "; ".join(probs)))
                else:
                    ok("%s: nohup respected (the tool kept running after SIGHUP), then TERM stopped it cleanly" % name)
            else:
                bad("%s: the tool died on a SIGHUP it should ignore under nohup (rc=%s)" % (name, p.poll()))
                p.kill(); p.wait(); force_clean(case, tok, repo)
            return
        bad("%s: SIG%s is IGNORED on %s although the launcher restored the default -- the tool (not the caller) "
            "made it ignorable; nothing sent" % (name, sig, t[3]))
        p.kill(); p.wait(); force_clean(case, tok, repo)
        return
    if term_ign and not (ign >> (signal.SIGTERM - 1)) & 1:
        bad("%s: control needle: TERM is not ignored on %s (SigIgn=%x) although the launcher ignored it -- the row "
            "proves nothing" % (name, t[3], ign))
        p.kill(); p.wait(); force_clean(case, tok, repo)
        return
    if nohup and signo == signal.SIGHUP:
        bad("%s: under nohup SIGHUP is NOT ignored on %s -- the instrument cannot tell an ignored disposition" % (name, t[3]))
    n_at_sig = count(os.path.join(case, "calls"))
    t0 = time.monotonic()
    if not send(t, signo, case, tok):
        bad("%s: refused to signal %s (guard)" % (name, t[3]))
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    if signo != signal.SIGKILL:
        time.sleep(0.3)
        tt = resolve(target, main)
        if tt is not None and p.poll() is None:
            try:
                send(tt, signo, case, tok)
            except OSError:
                pass
    main_dies = signo == signal.SIGKILL and target in ("main", "main-group")
    # a caller ignoring TERM hands that ignore to the gate (nohup semantics): it can only be KILLed after the grace
    lat_max = GRACE * 0.75 if (shape in HONOUR and not term_ign) else GRACE + 4.0
    if main_dies:
        rc = wait_main(p, 5)
        end = time.monotonic() + GRACE + 15
        while time.monotonic() < end and case_procs(case, tok):
            time.sleep(0.05)
        latency = time.monotonic() - t0
    else:
        rc = wait_main(p, GRACE + 15)
        latency = time.monotonic() - t0
        if rc is None:
            bad("%s: the tool did not exit within %.0fs of SIG%s to %s" % (name, GRACE + 15, sig, t[3]))
            p.kill(); p.wait(); force_clean(case, tok, repo); return
    probs = postcheck(case, repo, wtr, tok, n_at_sig, name, rc, 128 + signo, latency, lat_max)
    if probs:
        bad("%s: %s" % (name, "; ".join(probs)))
    else:
        ok("%s: stopped in %.2fs, rc=%d, nothing left (processes, temp dir, worktree, locks), no further run" % (name, latency, rc))


def selfcheck_case(sig, target):
    name = "selfcheck-%s-%s" % (sig, target)
    signo = getattr(signal, "SIG" + sig)
    case, repo, gate, tok = setup(name, None)
    p, wtr = launch(case, repo, gate, tok, None, subcmd="selfcheck")
    end, seen = time.monotonic() + 60, False
    while time.monotonic() < end and p.poll() is None:
        if any(line.endswith(" sleep 5") for _, line in case_procs(case, tok)):
            seen = True
            break
        time.sleep(0.02)
    if not seen:
        bad("%s: selfcheck's timeout check never seen running (setup failure)" % name)
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    t = resolve(target, p.pid)
    if t is None:
        bad("%s: target %s not found" % (name, target))
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    t0 = time.monotonic()
    send(t, signo, case, tok)
    if signo == signal.SIGKILL and target == "main":
        rc = wait_main(p, 5)
        end = time.monotonic() + GRACE + 15
        while time.monotonic() < end and case_procs(case, tok):
            time.sleep(0.05)
    else:
        rc = wait_main(p, GRACE + 15)
    probs = postcheck(case, repo, wtr, tok, None, name, rc, 128 + signo, time.monotonic() - t0, GRACE + 4,
                      interrupted_expected=False)
    if probs:
        bad("%s: %s" % (name, "; ".join(probs)))
    else:
        ok("%s: selfcheck stopped, rc=%s, nothing left" % (name, rc))


def termign_case(sig):
    """T048 V4 round 6, F1 (IMPORTANT): the caller IGNORES TERM (inherited through exec, kept ignored on purpose --
    nohup semantics) and a stop signal main does catch (INT/QUIT/HUP) is sent to the main pid. Round 5 forwarded a
    fixed SIGTERM to the keeper, which keeps TERM ignored: the stop was dropped, the gates kept running until main's
    keeper deadline (grace + 5 + 30 s) and main then SIGKILLed the keeper. Control needle (in run_case, before
    anything is sent): the main pid's SigIgn really has TERM set and the sent signal clear."""
    run_case(sig, "main", "never", term_ign=True)


def runkill_case():
    """T048 V4 round 6, F2 (reviewer injection I3): ONE run supervisor (`fc-run`) SIGKILLed while its gate's
    double-forked daemon runs. The run supervisor can then no longer stop that daemon (it is re-parented to the
    keeper), and it records no outcome. The worker must not go on as if the run were merely unmeasured -- it used to
    record HARNESS_ERROR, remove the worktree under the still-running daemon and write a report: the daemon outlived
    its run (and would have outlived it into a next replay / item). Required: the worker finds no outcome and aborts
    the WHOLE replay (exit 4, said so), so the keeper stops the daemon BEFORE the worktree is removed; no further run
    starts, no report is written, the log directory is marked INTERRUPTED, nothing is left."""
    name = "runkill-KILL-fcrun-daemon"
    case, repo, gate, tok = setup(name, None)
    open(gate, "w").write(
        "#!/bin/bash\n"
        'echo x >>"$FCSM_CASE/calls"\n'
        "( setsid bash -c 'echo $$ >\"$FCSM_CASE/daemon\"; while :; do [ -e \"$PWD/f.txt\" ] || "
        "echo cwd_gone >>\"$FCSM_CASE/cwdgone\"; sleep 0.05; done' \"fcsm-$FCSM_TOK-rkdaemon\" & )\n"
        'echo $$ >"$FCSM_CASE/started"\n'
        'exec -a "fcsm-$FCSM_TOK-rkgate" sleep 600\n')
    os.chmod(gate, 0o755)
    p, wtr = launch(case, repo, gate, tok, "never", cold=2)
    if not (wait_file_lines(os.path.join(case, "started"), 1, 60) and wait_file_lines(os.path.join(case, "daemon"), 1, 30)):
        bad("%s: setup: the gate / its daemon never started -- %s" % (name, open(os.path.join(case, "main.err")).read()[-300:]))
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    dpid = int(open(os.path.join(case, "daemon")).read().split()[0])
    w = worker_of(p.pid)
    runs = [c for c in children(w) if comm(c) == "fc-run"] if w else []
    # control needle: the daemon is the run supervisor's adopted orphan (its parent IS that fc-run) -- the process
    # the run supervisor alone was responsible for stopping
    end, adopted = time.monotonic() + 10, False
    while time.monotonic() < end and len(runs) == 1 and not adopted:
        s = stat(dpid)
        adopted = s is not None and s[1] == runs[0]
        time.sleep(0.02)
    if len(runs) != 1 or not adopted:
        bad("%s: control needle: fc-run=%s daemon %d parent=%s -- the daemon is not the run supervisor's orphan"
            % (name, runs, dpid, stat(dpid)))
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    n0 = count(os.path.join(case, "calls"))
    t0 = time.monotonic()
    send(("pid", runs[0], runs[0], "fc-run"), signal.SIGKILL, case, tok)
    rc = wait_main(p, GRACE + 30)
    if rc is None:
        bad("%s: the tool did not finish after its run supervisor was killed" % name)
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    err = open(os.path.join(case, "main.err")).read()
    has_report = os.path.exists(os.path.join(case, "out.json"))
    probs = postcheck(case, repo, wtr, tok, n0, name, rc, 4, time.monotonic() - t0, GRACE + 8)
    if not probs and not has_report and "without recording an outcome" in err:
        ok("%s: fc-run SIGKILLed (needle: the daemon was its adopted orphan): the replay aborted (exit 4, said so), the "
           "daemon was stopped before the worktree was removed, no further run, no report, nothing left" % name)
    else:
        bad("%s: rc=%s report-written=%s abort-message=%s problems=%s" % (name, rc, has_report,
                                                                          "without recording an outcome" in err,
                                                                          "; ".join(probs) or "none"))


def doublekill_case():
    """Honest boundary: M and K SIGKILLed together. Nothing can process the ledger
    (worktree + temp dir stay); the PDEATHSIG chain must still stop the worker, the
    run supervisor and the gate, and no further scheduled run may start."""
    name = "doublekill-main+supervisor-quick"
    case, repo, gate, tok = setup(name, "quick")
    p, wtr = launch(case, repo, gate, tok, "quick")
    if not wait_file_lines(os.path.join(case, "calls"), 2, 90):
        bad("%s: setup failure" % name); p.kill(); p.wait(); force_clean(case, tok, repo); return
    k = keeper_of(p.pid)
    if k is None:
        bad("%s: no supervisor keeper process in the tool's tree" % name)
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    n0 = count(os.path.join(case, "calls"))
    for pid in (p.pid, k):
        fd = os.pidfd_open(pid); signal.pidfd_send_signal(fd, signal.SIGKILL); os.close(fd)
    p.wait()
    end = time.monotonic() + 3
    while time.monotonic() < end and case_procs(case, tok):
        time.sleep(0.05)
    left = case_procs(case, tok)
    c1 = count(os.path.join(case, "calls")); time.sleep(1.0); c2 = count(os.path.join(case, "calls"))
    leaked = [d for d in os.listdir(os.path.join(case, "tmp"))]
    force_clean(case, tok, repo)
    if not left and c1 == c2 and c1 <= n0 + 1:
        ok("%s: worker, run supervisor and gate died with their parents, no further run (honest boundary, "
           "reported not hidden: temp dir %s and the worktree stay behind -- nothing alive can process the ledger)"
           % (name, leaked))
    else:
        bad("%s: processes left %s / runs %d->%d->%d" % (name, [(p, l[:140]) for p, l in left[:6]], n0, c1, c2))


def report_of(case):
    try:
        import json
        return json.load(open(os.path.join(case, "out.json")))
    except (OSError, ValueError):
        return None


def sigchld_case():
    """A caller with SIGCHLD IGNORED (crosses exec; the kernel then auto-reaps every child, so waitpid never
    returns it). b61583e: every supervisor role spun on a readable pidfd -- each run until its timeout,
    the main supervisor forever. Control needle: a probe started the same way really has SIGCHLD ignored."""
    name = "sigchld-caller-quick"
    case, repo, gate, tok = setup(name, "quick")

    def pre_n():
        signal.signal(signal.SIGCHLD, signal.SIG_IGN)
    probe = subprocess.run(["sed", "-n", "s/^SigIgn:[[:space:]]*//p", "/proc/self/status"], preexec_fn=pre_n,
                           capture_output=True, text=True).stdout.strip()
    try:
        needle = (int(probe, 16) >> (signal.SIGCHLD - 1)) & 1
    except ValueError:
        needle = 0
    t0 = time.monotonic()
    p, wtr = launch(case, repo, gate, tok, "quick", cold=3, chld_ign=True)
    rc = wait_main(p, 60)
    dt = time.monotonic() - t0
    if rc is None:
        bad("%s: a replay of 3 x 0.2 s runs did not finish in 60 s under a SIGCHLD-ignoring caller (spin)" % name)
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    rep = report_of(case) or {}
    probs = postcheck(case, repo, wtr, tok, None, name, rc, 0, None, 0, interrupted_expected=False)
    if not needle:
        bad("%s: control needle: the launcher did not leave SIGCHLD ignored (probe SigIgn %r)" % (name, probe))
    elif not probs and rep.get("verdict_set", {}).get("cold") == ["PASS"] and len(rep.get("runs", [])) == 3:
        ok("%s: caller with SIGCHLD ignored (needle %s): 3 runs PASS, rc 0 in %.1fs, nothing left" % (name, probe, dt))
    else:
        bad("%s: rc=%s verdict_set=%r runs=%d problems=%s" % (name, rc, rep.get("verdict_set"), len(rep.get("runs", [])),
                                                              "; ".join(probs)))


def wtaddkill_case():
    """The worker SIGKILLed while `git worktree add` runs (a slow smudge filter holds git inside the add):
    git dies by the PDEATHSIG chain and leaves the worktree `locked: initializing`, which `remove --force`
    refuses and `prune` skips. The supervisor must unlock + remove -f -f and only then report removal."""
    name = "wtaddkill-worker-KILL"
    case, repo, gate, tok = setup(name, "quick")
    open(os.path.join(repo, ".gitattributes"), "w").write("f.txt filter=slow\n")
    g("-C", repo, "add", ".gitattributes")
    g("-C", repo, "commit", "-q", "-m", "slow smudge")
    g("-C", repo, "config", "filter.slow.smudge", "bash -c 'exec -a fcsm-%s-smudge sleep 600'; cat" % tok)
    p, wtr = launch(case, repo, gate, tok, "quick", cold=1)
    adm = os.path.join(repo, ".git", "worktrees")
    end, locked = time.monotonic() + 60, False
    while time.monotonic() < end and not locked:
        if os.path.isdir(adm):
            locked = any(os.path.exists(os.path.join(adm, n, "locked")) for n in os.listdir(adm)) and \
                any("smudge" in l for _, l in case_procs(case, tok))
        time.sleep(0.05)
    w = worker_of(p.pid)
    k = keeper_of(p.pid)
    if not locked or w is None or k is None:
        bad("%s: setup: the add never reached its locked state (locked=%s worker=%s keeper=%s) -- %s"
            % (name, locked, w, k, open(os.path.join(case, "main.err")).read()[-300:]))
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    # Deterministic form of the race the reviewer hit: the keeper is held (SIGSTOP) while the worker is
    # SIGKILLed, so the run supervisor and git die by the PDEATHSIG chain (SIGKILL -- git cannot clean up)
    # BEFORE the keeper acts. Unheld, the keeper sometimes TERMs git first and git removes its own junk,
    # which would let a broken ledger removal pass by luck.
    send(("pid", k, k, "keeper"), signal.SIGSTOP, case, tok)
    # T048 V4 round 7: a run supervisor whose worker dies now STOPS its own tree (parent-death SIGUSR2) -- it TERMs
    # git, and git removes its own `locked initializing` junk (measured: this needle failed in the round-7 suite).
    # The SIGKILL-of-git form is kept deterministic by holding the run supervisor too and SIGKILLing it after the
    # worker: git then dies by its own PDEATHSIG=SIGKILL, unable to clean up.
    runs = [c for c in children(w) if comm(c) == "fc-run"]
    for r in runs:
        send(("pid", r, r, "fc-run"), signal.SIGSTOP, case, tok)
    t0 = time.monotonic()
    send(("pid", w, w, "worker"), signal.SIGKILL, case, tok)
    for r in runs:
        send(("pid", r, r, "fc-run"), signal.SIGKILL, case, tok)
    def adders():   # the `git worktree add` itself, and its run supervisor (git's own checkout child may live on)
        return [pid for pid, line in case_procs(case, tok) if " worktree add " in line or comm(pid) == "fc-run"]
    end = time.monotonic() + 10
    while time.monotonic() < end and adders():
        time.sleep(0.05)
    porc = subprocess.run(["git", "-C", repo, "worktree", "list", "--porcelain"], capture_output=True, text=True).stdout
    needle = "locked initializing" in porc and not adders()
    send(("pid", k, k, "keeper"), signal.SIGCONT, case, tok)
    if not needle:
        bad("%s: control needle: after the worker's SIGKILL the worktree is not `locked initializing` with the add "
            "dead (porcelain: %s) -- the case proves nothing" % (name, porc.replace("\n", " | ")[-200:]))
        wait_main(p, GRACE + 15); force_clean(case, tok, repo); return
    rc = wait_main(p, GRACE + 15)
    if rc is None:
        bad("%s: the tool did not exit after its worker was killed" % name)
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    probs = postcheck(case, repo, wtr, tok, None, name, rc, 128 + signal.SIGKILL, time.monotonic() - t0, GRACE + 4)
    err = open(os.path.join(case, "main.err")).read()
    if probs:
        bad("%s: %s (stderr: %s)" % (name, "; ".join(probs), err.strip()[-300:]))
    else:
        ok("%s: worker SIGKILLed inside `git worktree add` (needle: `locked initializing`, the add dead): the locked "
           "worktree is gone from disk AND from `git worktree list`, rc=%d, nothing left" % (name, rc))


def nochildren_case():
    """A copy of the tool whose supervisor cannot read /proc/<pid>/task/<tid>/children (path renamed): it
    must refuse to start (exit 4 BLIND), never run gates it could not find again to stop."""
    name = "nochildren-blind"
    case, repo, gate, tok = setup(name, "quick")
    src_cycle = os.path.dirname(os.path.abspath(SCRIPT))
    rep_root = os.path.join(case, "replica")
    shutil.copytree(src_cycle, os.path.join(rep_root, "cycle"))
    shutil.copytree(os.path.join(os.path.dirname(src_cycle), "lib"), os.path.join(rep_root, "lib"))
    supp = os.path.join(rep_root, "cycle", "fc_supervisor.py")
    src = open(supp).read()
    mut = src.replace('"/proc/%d/task/%s/children"', '"/proc/%d/task/%s/children_absent_sm"')
    open(supp, "w").write(mut)
    p, wtr = launch(case, repo, gate, tok, "quick", cold=2,
                    script=os.path.join(rep_root, "cycle", os.path.basename(SCRIPT)))
    rc = wait_main(p, 60)
    err = open(os.path.join(case, "main.err")).read()
    if rc is None:
        p.kill(); p.wait()
    probs = postcheck(case, repo, wtr, tok, None, name, rc, 4, None, 0, interrupted_expected=False)
    if mut == src:
        bad("%s: setup: the children path could not be renamed in the replica" % name)
    elif not probs and "BLIND" in err and "children" in err and count(os.path.join(case, "calls")) == 0:
        ok("%s: without the children file the tool refused to start (exit 4, BLIND named), no gate ran, nothing left" % name)
    else:
        bad("%s: rc=%s gate-calls=%d problems=%s stderr=%s" % (name, rc, count(os.path.join(case, "calls")),
                                                               "; ".join(probs), err.strip()[-200:]))


def runsig_case():
    """SIGTERM to ONE run supervisor (`fc-run`, the parent of one gate run) -- not to the tool: that run
    is recorded UNMEASURED 'stopped' (b61583e: its marker `stopped` was unknown -> HARNESS_ERROR 'could not
    be started', the loop stopped and the tool exited 4), and the replay goes on."""
    name = "runsig-TERM-fcrun-never"
    case, repo, gate, tok = setup(name, "never")
    p, wtr = launch(case, repo, gate, tok, "never", cold=2)
    stopped = 0
    for want_calls in (1, 2):
        if not wait_file_lines(os.path.join(case, "calls"), want_calls, 60):
            break
        time.sleep(0.3)
        w = worker_of(p.pid)
        runs = [c for c in children(w)] if w else []
        runs = [c for c in runs if comm(c) == "fc-run"]
        if len(runs) != 1:
            break
        if send(("pid", runs[0], runs[0], "fc-run"), signal.SIGTERM, case, tok):
            stopped += 1
    rc = wait_main(p, GRACE + 30)
    if rc is None:
        bad("%s: the tool did not finish after both runs were stopped" % name)
        p.kill(); p.wait(); force_clean(case, tok, repo); return
    rep = report_of(case) or {}
    runs = rep.get("runs", [])
    probs = postcheck(case, repo, wtr, tok, None, name, rc, 0, None, 0, interrupted_expected=False)
    good = len(runs) == 2 and all(r.get("verdict") == "UNMEASURED" and "stopped" in r.get("verdict_reason", "")
                                  for r in runs)
    if stopped == 2 and good and not probs:
        ok("%s: a TERM to each of the two run supervisors recorded both runs UNMEASURED 'stopped', the replay "
           "finished rc 0, nothing left" % name)
    else:
        bad("%s: stopped=%d rc=%s runs=%r problems=%s" % (name, stopped, rc,
                                                          [(r.get("verdict"), r.get("verdict_reason", "")[:60]) for r in runs],
                                                          "; ".join(probs)))


for shape in SHAPES:
    for sig in SIGS:
        for target in TARGETS:
            run_case(sig, target, shape)
if "nohup" in EXTRA:
    for target in TARGETS:
        run_case("HUP", target, "never", nohup=True)
    run_case("TERM", "main", "never", nohup=True)
if "selfcheck" in EXTRA:
    for sig in ("TERM", "HUP", "KILL"):
        for target in ("main", "worker"):
            selfcheck_case(sig, target)
if "doublekill" in EXTRA:
    doublekill_case()
if "sigchld" in EXTRA:
    sigchld_case()
if "wtaddkill" in EXTRA:
    wtaddkill_case()
if "nochildren" in EXTRA:
    nochildren_case()
if "runsig" in EXTRA:
    runsig_case()
if "termign" in EXTRA:
    for sig in ("INT", "QUIT", "HUP"):
        termign_case(sig)
if "runkill" in EXTRA:
    runkill_case()
print("SMCOUNT %d %d %d" % (N["ok"], N["bad"], N["skip"]))
PYSM
  cat "$SM_OUT"
  read -r _ smo smb sms < <(grep '^SMCOUNT ' "$SM_OUT" | tail -1)
  if [ -z "${smo:-}" ]; then
    bad "[SM] the stop-matrix runner crashed (no SMCOUNT line) -- see output above"
  else
    PASS=$((PASS + smo)); FAIL=$((FAIL + smb))
    echo "SM: $smo ok, $smb NOT ok, $sms SKIP (skips are never counted as passes)"
  fi
fi

# =============================================================================
# LOCKHOOK (V4R3-5): a post-checkout hook that backgrounds a long sleep must not
# inherit the replay lock: a second replay right after the first must run (no
# false "another replay is running" refusal, §11.4.201(1)), and the hook's
# process must not outlive the replay.
# =============================================================================
if want LOCKHOOK; then
  REPO="$WORK/lockhook"; mk_repo "$REPO"
  printf '#!/bin/bash\nexec -a "%shook" sleep 20 &\nexit 0\n' "$MARK" >"$REPO/.git/hooks/post-checkout"
  chmod +x "$REPO/.git/hooks/post-checkout"
  R "$REPO" "$WORK/lockhook_wt" "$WORK/lh1.json" --min-free-kb-objects 0 --gate-cmd true --cold-runs 1 --warm-runs 0 >/dev/null 2>&1; rc1=$?
  HOOKLEFT="$(marker_pids "${MARK}hook" | wc -l)"
  R "$REPO" "$WORK/lockhook_wt" "$WORK/lh2.json" --min-free-kb-objects 0 --gate-cmd true --cold-runs 1 --warm-runs 0 >/dev/null 2>"$WORK/lh2.err"; rc2=$?
  if [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ "$HOOKLEFT" = 0 ]; then
    ok "[LOCKHOOK] a hook's background process neither holds the replay lock (the next replay ran, rc=$rc2) nor outlives the replay"
  else
    bad "[LOCKHOOK] replay1 rc=$rc1, hook processes left after it=$HOOKLEFT, replay2 rc=$rc2 ($(head -c 200 "$WORK/lh2.err"))"
  fi
  reap_marker
fi

# =============================================================================
# PERRUN (round 3): whatever one gate run leaves running is stopped BEFORE the
# next run starts -- a background daemon of run 1 must not run (and skew the
# timing of) run 2. Run 1 double-forks a setsid daemon; run 2 records whether
# that daemon is still alive. (At the END of the tool the supervisor would stop
# it anyway, so only a check made DURING run 2 can see a missing per-run sweep.)
# =============================================================================
if want PERRUN; then
  REPO="$WORK/perrun"; mk_repo "$REPO"
  cat >"$WORK/perrun_gate.sh" <<SH
#!/bin/bash
n=0
[ -f "$WORK/perrun.ctr" ] && n=\$(cat "$WORK/perrun.ctr")
n=\$((n + 1)); echo "\$n" >"$WORK/perrun.ctr"
if [ "\$n" = 1 ]; then
  ( setsid bash -c 'echo \$\$ >"$WORK/perrun.dpid"; exec -a "${MARK}perrun-daemon" sleep 60' & )
  sleep 0.5
  exit 0
fi
dp=\$(cat "$WORK/perrun.dpid" 2>/dev/null)
state=dead
if [ -n "\$dp" ] && [ -r "/proc/\$dp/cmdline" ] && [ "\$(cut -d ' ' -f 3 "/proc/\$dp/stat" 2>/dev/null)" != Z ] \\
   && tr '\0' '\n' <"/proc/\$dp/cmdline" | head -1 | grep -qx "${MARK}perrun-daemon"; then
  state=alive
fi
echo "\$state" >"$WORK/perrun.state"
exit 0
SH
  chmod +x "$WORK/perrun_gate.sh"
  R "$REPO" "$WORK/perrun_wt" "$WORK/perrun.json" --min-free-kb-objects 0 --gate-cmd "$WORK/perrun_gate.sh" --cold-runs 2 --warm-runs 0 >/dev/null 2>&1; rc=$?
  ST="$(cat "$WORK/perrun.state" 2>/dev/null)"
  DPID_SEEN="$( [ -s "$WORK/perrun.dpid" ] && echo yes || echo no)"
  if [ "$rc" = 0 ] && [ "$DPID_SEEN" = yes ] && [ "$ST" = dead ] && [ -z "$(marker_pids "${MARK}perrun-daemon")" ]; then
    ok "[PERRUN] a daemon left by gate run 1 is stopped before run 2 starts (run 2 saw it dead) and nothing outlives the replay"
  else
    bad "[PERRUN] rc=$rc daemon-started=$DPID_SEEN state-seen-by-run-2='$ST' -- a process one run left behind ran into the next run"
  fi
  reap_marker
fi

# =============================================================================
# V4-2: a gate that RAN and itself exited 255 / 130 is a genuine FAIL. Exit
# codes >= 129 cannot tell "exited 128+N" from "killed by signal N", so the tool
# must never claim a signal it did not itself deliver.
# =============================================================================
if want V4-2; then
  REPO="$WORK/v42"; mk_repo "$REPO"
  for code in 255 130 137; do
    printf '#!/bin/sh\nexit %s\n' "$code" >"$WORK/v42_$code.sh"; chmod +x "$WORK/v42_$code.sh"
    R "$REPO" "$WORK/v42_wt" "$WORK/v42_$code.json" --gate-cmd "$WORK/v42_$code.sh" --cold-runs 1 --warm-runs 0 >/dev/null 2>&1; rc=$?
    V="$(jget "$WORK/v42_$code.json" 'd["verdict_set"]["cold"]')"
    RS="$(jget "$WORK/v42_$code.json" 'd["runs"][0]["verdict_reason"]')"
    case "$RS" in *signal*) sig=1 ;; *) sig=0 ;; esac
    if [ "$rc" = 0 ] && [ "$V" = '["FAIL"]' ] && [ "$sig" = 0 ] && case "$RS" in *"exit $code"*) true ;; *) false ;; esac; then
      ok "[V4-2] a gate that itself exits $code is a FAIL ('$RS'), never an invented signal"
    else
      bad "[V4-2] gate exit $code: rc=$rc verdict_set=$V reason='$RS' -- a real FAIL was recorded as UNMEASURED / a signal the harness never sent"
    fi
  done
  R "$REPO" "$WORK/v42_wt" "$WORK/v42_det.json" --gate-cmd "$WORK/v42_255.sh" --cold-runs 1 --warm-runs 1 --determinism-check >/dev/null 2>&1; rc=$?
  if [ "$rc" = 0 ] && [ "$(jget "$WORK/v42_det.json" 'd.get("deterministic")')" = true ]; then
    ok "[V4-2] an always-255 gate is deterministically FAIL (exit 0, deterministic=true)"
  else
    bad "[V4-2] always-255 gate --determinism-check: rc=$rc deterministic=$(jget "$WORK/v42_det.json" 'd.get("deterministic")')"
  fi
fi

# =============================================================================
# V4-5 / V4-4 / V4R3-4: the disk-floor refusals. A `df` shim on PATH reports a
# DIFFERENT free-space figure for the git object store than for the worktree
# root, so each refusal must name the right filesystem AND that filesystem's
# own number -- measuring the wrong one (V4R3-4: the object-store check pointed
# at the worktree root) cannot pass.
# =============================================================================
if want V4-5; then
  REPO="$WORK/v45"; mk_repo "$REPO"
  HUGE=999999999999999
  bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
    --worktree-root "$WORK/v45_wt" --min-free-kb "$HUGE" --gate-cmd true --cold-runs 1 --warm-runs 0 \
    --out "$WORK/v45.json" >/dev/null 2>"$WORK/v45.err"; rc=$?
  AVAIL="$(sed -n 's/.*: \([0-9][0-9]*\)KB available, \([0-9][0-9]*\)KB required.*/\1/p' "$WORK/v45.err" | head -1)"
  REQ="$(sed -n 's/.*: \([0-9][0-9]*\)KB available, \([0-9][0-9]*\)KB required.*/\2/p' "$WORK/v45.err" | head -1)"
  DF="$(df -Pk "$WORK/v45_wt" 2>/dev/null | awk 'NR==2{print $4}')"
  NEAR=0
  if [ -n "$AVAIL" ] && [ -n "$DF" ]; then
    D=$((AVAIL - DF)); [ "$D" -lt 0 ] && D=$((-D))
    [ "$D" -le 1048576 ] && NEAR=1   # within 1 GiB of a df taken a moment later
  fi
  LEFT="$(find "$WORK/v45_wt" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
  if [ "$rc" = 4 ] && [ "$REQ" = "$HUGE" ] && [ "$NEAR" = 1 ] && [ "$LEFT" = 0 ] && [ "$(wt_count "$REPO")" = 1 ] && [ ! -e "$WORK/v45.json" ]; then
    ok "[V4-5] --min-free-kb above the free space is refused (exit 4) with the real df numbers (${AVAIL}KB available), no worktree or log dir created"
  else
    bad "[V4-5] disk floor: rc=$rc available='$AVAIL' (df now $DF) required='$REQ' entries-under-worktree-root=$LEFT worktrees=$(wt_count "$REPO") report-written=$([ -e "$WORK/v45.json" ] && echo yes || echo no) -- the refusal path is broken ($(head -c 300 "$WORK/v45.err"))"
  fi
  # df shim: the object store ($REPO/.git) reports 111KB free, everything else 999999999KB.
  mkdir -p "$WORK/dfshim"
  cat >"$WORK/dfshim/df" <<SH
#!/bin/bash
last="\${@: -1}"
case "\$last" in
  "$REPO/.git"|"$REPO/.git/"*) avail=111 ;;
  *) avail=999999999 ;;
esac
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "shimfs 1000000000 1 \$avail 1% /"
SH
  chmod +x "$WORK/dfshim/df"
  PATH="$WORK/dfshim:$PATH" bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
    --worktree-root "$WORK/v45_wt" --min-free-kb 1000 --min-free-kb-objects 1000 --gate-cmd true \
    --cold-runs 1 --warm-runs 0 --out "$WORK/v45b.json" >/dev/null 2>"$WORK/v45b.err"; rc=$?
  LEFT="$(find "$WORK/v45_wt" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
  if [ "$rc" = 4 ] && grep -q "object store $REPO/.git: 111KB available, 1000KB required" "$WORK/v45b.err" && [ "$LEFT" = 0 ]; then
    ok "[V4-4] the object-store floor measures the object store's OWN filesystem (shim: 111KB there, 999999999KB elsewhere) and refuses naming it"
  else
    bad "[V4-4] object-store floor: rc=$rc entries=$LEFT -- the refusal does not name the object store with its own free space ($(head -c 300 "$WORK/v45b.err"))"
  fi
  # and the converse: only the worktree root is short
  cat >"$WORK/dfshim/df" <<SH
#!/bin/bash
last="\${@: -1}"
case "\$last" in
  "$WORK/v45_wt"|"$WORK/v45_wt/"*) avail=222 ;;
  *) avail=999999999 ;;
esac
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "shimfs 1000000000 1 \$avail 1% /"
SH
  PATH="$WORK/dfshim:$PATH" bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
    --worktree-root "$WORK/v45_wt" --min-free-kb 1000 --min-free-kb-objects 1000 --gate-cmd true \
    --cold-runs 1 --warm-runs 0 --out "$WORK/v45d.json" >/dev/null 2>"$WORK/v45d.err"; rc=$?
  if [ "$rc" = 4 ] && grep -q "free disk at $WORK/v45_wt: 222KB available, 1000KB required" "$WORK/v45d.err"; then
    ok "[V4-5] the worktree-root floor measures the worktree root's own filesystem (shim: 222KB there) and refuses naming it"
  else
    bad "[V4-5] worktree-root floor under the shim: rc=$rc ($(head -c 300 "$WORK/v45d.err"))"
  fi
  # control: the same replay with both floors at 0 runs
  bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
    --worktree-root "$WORK/v45_wt" --min-free-kb 0 --min-free-kb-objects 0 --gate-cmd true \
    --cold-runs 1 --warm-runs 0 --out "$WORK/v45c.json" >/dev/null 2>&1; rc=$?
  if [ "$rc" = 0 ]; then
    ok "[V4-5] control: with both floors at 0 the same replay runs (exit 0)"
  else
    bad "[V4-5] control: the replay with both floors at 0 failed rc=$rc -- the refusals above prove nothing"
  fi
fi

# =============================================================================
# V4-4: one replay at a time per repository -- also when --repo-root is a LINKED
# worktree of that repository (V4R3-6: the lock lives in the COMMON git dir) --
# and per filesystem (two different repositories on one filesystem).
# =============================================================================
if want V4-4; then
  REPO="$WORK/v44"; mk_repo "$REPO"
  LOCKF="$(git -C "$REPO" rev-parse --absolute-git-dir)/fc_baseline_replay.lock"
  flock -n "$LOCKF" bash -c "echo held >'$WORK/v44.held'; exec -a '${MARK}lockholder' sleep 30" &
  HOLDER_PID=$!
  if wait_for_lines "$WORK/v44.held" 1 50; then
    bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
      --worktree-root "$WORK/v44_wt" --min-free-kb 0 --gate-cmd true --cold-runs 1 --warm-runs 0 \
      --out "$WORK/v44.json" >/dev/null 2>"$WORK/v44.err"; rc=$?
    LEFT="$(find "$WORK/v44_wt" -maxdepth 1 -name 'replay.*' 2>/dev/null | wc -l)"
    if [ "$rc" = 4 ] && grep -q "another baseline_replay" "$WORK/v44.err" && [ "$LEFT" = 0 ] && [ ! -e "$WORK/v44.json" ]; then
      ok "[V4-4] a second replay of the same repository is refused while the first holds the lock (exit 4, nothing created)"
    else
      bad "[V4-4] concurrent replay: rc=$rc worktrees-created=$LEFT -- two replays can pass the free-space check together ($(head -c 300 "$WORK/v44.err"))"
    fi
    # the same repository through a LINKED worktree must hit the same lock
    git -C "$REPO" worktree add -q --detach "$WORK/v44_linked" >/dev/null 2>&1
    bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$WORK/v44_linked" \
      --worktree-root "$WORK/v44_wt" --min-free-kb 0 --gate-cmd true --cold-runs 1 --warm-runs 0 \
      --out "$WORK/v44l.json" >/dev/null 2>"$WORK/v44l.err"; rc=$?
    if [ "$rc" = 4 ] && grep -q "another baseline_replay" "$WORK/v44l.err" && [ ! -e "$WORK/v44l.json" ]; then
      ok "[V4-4] a replay whose --repo-root is a LINKED worktree of the same repository is refused too (the lock is the common git dir's)"
    else
      bad "[V4-4] linked-worktree replay while the repository's lock is held: rc=$rc ($(head -c 300 "$WORK/v44l.err"))"
    fi
    case "$HOLDER_PID" in ''|*[!0-9]*) ;; *) [ "$HOLDER_PID" -gt 1 ] && kill -KILL "$HOLDER_PID" 2>/dev/null ;; esac
    reap_marker
    wait "$HOLDER_PID" 2>/dev/null; HOLDER_PID=""
    bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
      --worktree-root "$WORK/v44_wt" --min-free-kb 0 --gate-cmd true --cold-runs 1 --warm-runs 0 \
      --out "$WORK/v44b.json" >/dev/null 2>&1; rc=$?
    if [ "$rc" = 0 ]; then
      ok "[V4-4] control: once the lock is released the replay runs (exit 0)"
    else
      bad "[V4-4] control: replay after release failed rc=$rc"
    fi
  else
    bad "[V4-4] could not take the test lock (setup failure)"
  fi
  # per filesystem: a DIFFERENT repository on the same filesystem is refused while
  # the filesystem lock is held (the free-space check covers the filesystem, not
  # the repository)
  REPO2="$WORK/v44fs"; mk_repo "$REPO2"
  DEV="$(stat -c %d "$WORK")"
  FSLOCK="$FC_REPLAY_LOCK_DIR/fc_baseline_replay.fs-$DEV.lock"
  : >"$FSLOCK"
  flock -n "$FSLOCK" bash -c "echo held >'$WORK/v44fs.held'; exec -a '${MARK}fsholder' sleep 30" &
  HOLDER_PID=$!
  if wait_for_lines "$WORK/v44fs.held" 1 50; then
    bash "$SCRIPT" replay --commit "$(git -C "$REPO2" rev-parse HEAD)" --repo-root "$REPO2" \
      --worktree-root "$WORK/v44fs_wt" --min-free-kb 0 --gate-cmd true --cold-runs 1 --warm-runs 0 \
      --out "$WORK/v44fs.json" >/dev/null 2>"$WORK/v44fs.err"; rc=$?
    if [ "$rc" = 4 ] && grep -q "same filesystem" "$WORK/v44fs.err" && [ ! -e "$WORK/v44fs.json" ]; then
      ok "[V4-4] a replay of a DIFFERENT repository on the same filesystem is refused while that filesystem's lock is held"
    else
      bad "[V4-4] per-filesystem lock: rc=$rc ($(head -c 300 "$WORK/v44fs.err"))"
    fi
  else
    bad "[V4-4] could not take the filesystem test lock (setup failure)"
  fi
  case "$HOLDER_PID" in ''|*[!0-9]*) ;; *) [ "$HOLDER_PID" -gt 1 ] && kill -KILL "$HOLDER_PID" 2>/dev/null ;; esac
  reap_marker
  wait "$HOLDER_PID" 2>/dev/null; HOLDER_PID=""
fi

# =============================================================================
# V4-10: every run of one phase cites its OWN log, holding THAT run's output.
# =============================================================================
if want V4-10; then
  REPO="$WORK/v410"; mk_repo "$REPO"
  cat >"$WORK/v410_gate.sh" <<SH
#!/bin/bash
n=0
[ -f "$WORK/v410_ctr" ] && n=\$(cat "$WORK/v410_ctr")
n=\$((n + 1)); echo "\$n" >"$WORK/v410_ctr"
echo "run-output-\$n"
exit 0
SH
  chmod +x "$WORK/v410_gate.sh"
  R "$REPO" "$WORK/v410_wt" "$WORK/v410.json" --gate-cmd "$WORK/v410_gate.sh" --cold-runs 3 --warm-runs 2 >/dev/null 2>&1; rc=$?
  RES="$(python3 - "$WORK/v410.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
runs = d["runs"]
paths = [r["log_path"] for r in runs]
bad = []
if len(runs) != 5:
    bad.append("runs=%d" % len(runs))
if len(set(paths)) != len(paths):
    bad.append("shared log paths %s" % paths)
for i, r in enumerate(runs, 1):
    try:
        body = open(r["log_path"]).read()
    except OSError as e:
        bad.append("unreadable %s" % r["log_path"]); continue
    if body.strip() != "run-output-%d" % i:
        bad.append("%s/%d log holds %r, want run-output-%d" % (r["phase"], r["run_index"], body.strip(), i))
print("OK" if not bad else "; ".join(bad))
PY
)"
  if [ "$rc" = 0 ] && [ "$RES" = OK ]; then
    ok "[V4-10] 3 cold + 2 warm runs cite 5 distinct logs, each holding exactly its own run's output"
  else
    bad "[V4-10] per-run evidence: rc=$rc $RES"
  fi
fi

# =============================================================================
# N6: on an exact author-time tie the first commit git log lists (the most
# recently committed) is kept -- the documented rule.
# =============================================================================
if want N6; then
  REPO="$WORK/n6"; mk_repo "$REPO"
  export GIT_AUTHOR_DATE="2026-07-01T10:00:00+00:00"
  echo a >>"$REPO/f.txt"; g -C "$REPO" add f.txt
  GIT_COMMITTER_DATE="2026-07-01T10:00:00+00:00" g -C "$REPO" commit -q -m "ATM-60 first"
  echo b >>"$REPO/f.txt"; g -C "$REPO" add f.txt
  GIT_COMMITTER_DATE="2026-07-01T11:00:00+00:00" g -C "$REPO" commit -q -m "ATM-60 second"
  unset GIT_AUTHOR_DATE
  WANT_SHA="$(git -C "$REPO" rev-parse HEAD)"
  bash "$SCRIPT" freeze --item ATM-60 --repo-root "$REPO" --out "$WORK/n6.json" >/dev/null 2>&1; rc=$?
  GOT="$(jget "$WORK/n6.json" 'd.get("commit")')"
  if [ "$rc" = 0 ] && [ "$GOT" = "$WANT_SHA" ]; then
    ok "[N6] an exact author-time tie keeps the first-listed (most recently committed) commit"
  else
    bad "[N6] tie rule: rc=$rc got=$GOT want=$WANT_SHA (subject $(jget "$WORK/n6.json" 'd.get("commit_subject")'))"
  fi
fi

# =============================================================================
# N10: the item id is searched as a LITERAL string (git log -F): an id holding a
# regex bracket must still find its own commit.
# =============================================================================
if want N10; then
  REPO="$WORK/n10"; mk_repo "$REPO"
  echo a >>"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "fix ATM[7] literal id"
  WANT_SHA="$(git -C "$REPO" rev-parse HEAD)"
  echo b >>"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "ATM7 decoy that a regex would match"
  bash "$SCRIPT" freeze --item 'ATM[7]' --repo-root "$REPO" --out "$WORK/n10.json" >/dev/null 2>&1; rc=$?
  GOT="$(jget "$WORK/n10.json" 'd.get("commit")')"
  if [ "$rc" = 0 ] && [ "$GOT" = "$WANT_SHA" ]; then
    ok "[N10] an id with regex metacharacters (ATM[7]) is matched literally to its own commit"
  else
    bad "[N10] literal id ATM[7]: rc=$rc got=$GOT want=$WANT_SHA -- the id was used as a regular expression"
  fi
fi

# =============================================================================
# WS: whitespace-only / whitespace-carrying item ids are not ids (V4-6 class),
# whatever the whitespace character (a space, a TAB -- V4R3-13 N11).
# =============================================================================
if want WS; then
  REPO="$WORK/ws"; mk_repo "$REPO"
  bash "$SCRIPT" freeze --item '   ' --repo-root "$REPO" --out "$WORK/ws1.json" >/dev/null 2>&1; rc1=$?
  bash "$SCRIPT" freeze --item 'ATM-1 ATM-2' --repo-root "$REPO" --out "$WORK/ws2.json" >/dev/null 2>&1; rc2=$?
  WS_RC=""
  for wid in ' ' $'ATM-1\tx' $'\t'; do
    python3 -c 'import json,sys; json.dump({"items":[{"item_id":sys.argv[2]}]}, open(sys.argv[1],"w"))' "$WORK/ws_sample.json" "$wid"
    rm -f "$WORK/ws3.json"
    bash "$SCRIPT" replay-sample --sample "$WORK/ws_sample.json" --gate-cmd true --cold-runs 1 --warm-runs 0 \
      --repo-root "$REPO" --worktree-root "$WORK/ws_wt" --min-free-kb 0 --out "$WORK/ws3.json" >/dev/null 2>&1; rc3=$?
    [ -e "$WORK/ws3.json" ] && rc3="$rc3+written"
    WS_RC="$WS_RC $rc3"
  done
  if [ "$rc1" = 2 ] && [ "$rc2" = 2 ] && [ "$WS_RC" = " 4 4 4" ] && [ ! -e "$WORK/ws1.json" ]; then
    ok "[WS] whitespace-only / whitespace-carrying item ids (space, TAB) are refused (freeze exit 2, replay-sample exit 4)"
  else
    bad "[WS] whitespace ids: freeze '   ' rc=$rc1, freeze 'ATM-1 ATM-2' rc=$rc2, replay-sample [' ', 'ATM-1<TAB>x', '<TAB>'] rc=$WS_RC -- a blank id was searched as if it named an item"
  fi
fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
