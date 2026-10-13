#!/usr/bin/env bash
# =============================================================================
# test_fc_supervisor_v4r9_shutdown_windows.sh -- T048 V4 round 9 (round-2 review of the round-8 pack, V4R9-1, the
# V4R8-2 CLASS "was the report written is decided from durable state, and nothing after the rename may change the
# replay's code"), §11.4.276(E) STRUCTURAL round. The round-2 reviewer showed one more member of the class by WIDENING
# one window by hand (a sleep after the keeper's rmtree, then SIGKILL of the keeper: exit 137 with the report on disk).
# This file does not guess windows: it ENUMERATES them. Every statement boundary of the shutdown sequence is an await
# point -- the keeper's code after its wait loop (teardown, process_ledger, remove_statedir, the decision, the final
# flush), main's code after its wait loop (the same + the stray scan + _exit_main) and the worker's report sequence
# (report-prepare, the writer, report-check, the worker's exit). The test builds a REPLICA of cycle/ + lib/ in which an
# AST pass inserts a pause hook before EVERY statement of those functions (recursively into try/finally, if, for,
# with), lists the hooks it inserted (the census: the tags are generated from the code, never typed by hand), then
# drives one real replay per (tag, action) and checks the ONE exit table (fc_supervisor.decide_code):
#
#   [R9WIN] keeper tag x {SIGKILL keeper, TERM main then continue, keeper wedged + TERM main -> main's deadline kill}
#           -> rc 0, report on disk, temp + state directories gone, no worktree, nothing left running.
#   [R9WIN] main tag x {TERM main then continue -> rc 0; SIGKILL main -> the caller sees -9, nothing left running, no
#           worktree; a state directory may stay ONLY because main died after its keeper (no live decider) -- the NEXT
#           replay's gc_statedirs must remove it ([R9GC2])}.
#   [R9WIN] worker tag x {SIGKILL worker, TERM worker, TERM main} -> before the writer ran: 137/143/143, no report;
#           from the rename on: rc 0 and the report.
#   [R9STALL] V4R9-1 trigger (b): the caller's stderr is a pipe whose reader is ALIVE but NOT READING (filled to
#           capacity through a second open file description, so the tool's own description stays blocking) and a stop
#           reaches the work -> the table's code (143) within a bounded time: no supervisor role may block on it.
#   [R9SAME] in every [R9WIN] row (main is the caller's pid): when the keeper exited by itself, its own exit code equals
#           main's -- both are decide_code(report_verified(state dir), cause), evaluated on the same durable state.
#   [R9CENSUS] every role's tag list is non-empty and every tag the AST pass inserted is either reached by some row or
#           listed as unreached WITH THE BRANCH THAT GUARDS IT (the if-condition / except clause / loop, taken from the
#           AST -- round 10, V4R10-7: no blanket label).
#   Round 11 (T048 V4, round-4 review): [R10LEASE-decide] V4R11-2 / RV4-08b -- the [R10LEASE] row at a second pause
#           point, after the keeper's teardown and right before its decision: the lease is held through that window.
#   Round 10 (T048 V4, round-3 review): [R10LEASE] V4R10-1 -- main SIGKILLed while its keeper is still tearing down, a
#           concurrent selfcheck + a replay of another repository (other lock dir) run gc_statedirs under the same
#           TMPDIR: the state directory must survive (the keeper's LEASE), the keeper must read the report (no
#           INTERRUPTED, code 0) and remove the directory itself. [R10DROP] V4R10-4 -- main raises after reaping its
#           keeper: rc 4 and its state directory removed. [R10INJ] V4R10-7 -- the keeper tags the ok-replay does not
#           reach driven through the main-gone path (gate held, main SIGKILLed), the main tags through the
#           keeper-killed path (gate held, keeper SIGKILLed: main processes the ledger itself).
#
# The pause hook (replica only, never in the real module): when RP_TAG matches and /proc/self/comm is RP_ROLE, it
# creates RP_FILE exclusively (once per run), writes its pid and waits for RP_FILE.go (bounded, 120 s).
# Constant patched in the replica: KEEPER_SLACK_S 30 -> 2 (main's deadline after a stop = grace 1 + KILL_WAIT_S 5 + 2).
#
# Env: FC_SUP_UNDER_TEST / FC_BR_UNDER_TEST (the mutation runner points them at a mutant; the replica is built from
#      them); R9_ONLY -- case groups (R9WIN R9STALL R9GC2 R9CENSUS R10LEASE R10DROP R10INJ); R9_ROLES -- keeper main worker (default all);
#      R9_ACTIONS -- restrict actions by name; R9_TAGS -- restrict tags (substring match).
# Exit: 0 every selected row held; 1 otherwise. Runtime: ~10-15 minutes (run it in the background, §11.4.89).
# Signals only through pidfds to validated pids > 1 that this test started (§11.4.263); no pkill / pgrep -f.
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
SUP="${FC_SUP_UNDER_TEST:-$FC/cycle/fc_supervisor.py}"
SCRIPT="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"
[ -f "$SUP" ] || { echo "NOT ok supervisor under test not found: $SUP"; exit 1; }
[ -f "$SCRIPT" ] || { echo "NOT ok baseline_replay.sh under test not found: $SCRIPT"; exit 1; }
WORK="$(mktemp -d)"
trap 'chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

SUP="$SUP" SCRIPT="$SCRIPT" WORK="$WORK" python3 -I - <<'PY'
import ast, atexit, ctypes, json, os, shutil, signal, subprocess, sys, threading, time

SUP, SCRIPT, WORK = os.environ["SUP"], os.environ["SCRIPT"], os.environ["WORK"]
ONLY = os.environ.get("R9_ONLY", "").split()
ROLES = os.environ.get("R9_ROLES", "keeper main worker").split()
ACTS = os.environ.get("R9_ACTIONS", "").split()
TAGSEL = os.environ.get("R9_TAGS", "").split()
N = {"ok": 0, "bad": 0}
ctypes.CDLL(None, use_errno=True).prctl(ctypes.c_int(36), ctypes.c_ulong(1), ctypes.c_ulong(0),
                                        ctypes.c_ulong(0), ctypes.c_ulong(0))


def ok(s):
    N["ok"] += 1; print("ok " + s, flush=True)


def bad(s):
    N["bad"] += 1; print("NOT ok " + s, flush=True)


def want(tag):
    return not ONLY or tag in ONLY


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


def _stat(pid):
    try:
        st = open("/proc/%d/stat" % pid).read()
        return st[st.rindex(") ") + 2:].split()
    except (OSError, ValueError):
        return None


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


def descendants():
    me, out, stack, seen = os.getpid(), [], [os.getpid()], {os.getpid()}
    while stack:
        cur = stack.pop()
        for c in children(cur):
            if c not in seen:
                seen.add(c); stack.append(c)
                f = _stat(c)
                if f and f[0] != "Z":
                    out.append(c)
    return out


def reap_all():
    while True:
        try:
            if os.waitpid(-1, os.WNOHANG)[0] == 0:
                return
        except ChildProcessError:
            return


def kill_tree():
    """every live descendant of this test (a child subreaper: orphans of the tool come back here)."""
    for _ in range(100):
        reap_all()
        live = descendants()
        if not live:
            return
        for p in live:
            sig_pid(p, signal.SIGKILL)
        time.sleep(0.05)


atexit.register(kill_tree)

# ---------------------------------------------------------------------------------------------------------------
# the replica + the AST census of await points
# ---------------------------------------------------------------------------------------------------------------
REP = os.path.join(WORK, "rep")
SRC_FC = os.path.dirname(os.path.dirname(os.path.abspath(SCRIPT)))
shutil.copytree(os.path.join(SRC_FC, "lib"), os.path.join(REP, "lib"))
shutil.copytree(os.path.dirname(os.path.abspath(SCRIPT)), os.path.join(REP, "cycle"))
shutil.copy(SUP, os.path.join(REP, "cycle", "fc_supervisor.py"))
shutil.copy(SCRIPT, os.path.join(REP, "cycle", "baseline_replay.sh"))
RSUP = os.path.join(REP, "cycle", "fc_supervisor.py")
RBR = os.path.join(REP, "cycle", "baseline_replay.sh")

HOOK = '''
_RP_SHUT = [False]


def _rp(tag):
    import os as _o, time as _t
    if not _RP_SHUT[0] or _o.environ.get("RP_TAG") != tag:
        return
    try:
        if open("/proc/self/comm").read().strip() != _o.environ.get("RP_ROLE"):
            return
        f = _o.environ["RP_FILE"]
        fd = _o.open(f, _o.O_WRONLY | _o.O_CREAT | _o.O_EXCL, 0o600)
    except Exception:
        return
    _o.write(fd, b"%d\\n" % _o.getpid()); _o.close(fd)
    if _o.environ.get("RP_RAISE") == "1":
        raise RuntimeError("R10 injected exception at " + tag)
    end = _t.monotonic() + 120
    while _t.monotonic() < end and not _o.path.exists(f + ".go"):
        _t.sleep(0.02)


def _rk(kst, sig, done):
    import os as _o
    f = _o.environ.get("RP_KLOG")
    if f:
        with open(f, "a") as fh:
            fh.write("%r %r %r\\n" % (kst, sig, done))
'''
TAGS = {"keeper": [], "main": []}
TAGCTX = {}                      # tag -> the branch that guards it (round 10, V4R10-7: the census names it per tag)
TAGSRC = {}                      # tag -> the first line of the statement it pauses before (round 11: a row can pick
                                 # its pause point by the code it precedes, never by a hand-typed index)


def pause_stmt(tag):
    return ast.parse("_rp(%r)" % tag).body[0]


def _short(node):
    t = ast.unparse(node).replace("\n", " ")
    return t if len(t) <= 70 else t[:67] + "..."


def _ctx_of(st, field, ctx):
    if isinstance(st, ast.If):
        c = ("if %s" if field == "body" else "else of if %s") % _short(st.test)
    elif isinstance(st, ast.For):
        c = ("for %s in %s" if field == "body" else "for-else of %s in %s") % (_short(st.target), _short(st.iter))
    elif isinstance(st, ast.Try):
        c = {"body": "", "orelse": "try-else", "finalbody": "finally"}[field]
    else:
        c = ""
    return (ctx + " > " + c) if c else ctx


def instr(stmts, prefix, role_list, start=0, ctx=""):
    out = []
    for i, st in enumerate(stmts):
        if i >= start and not (i == 0 and isinstance(st, ast.Expr) and isinstance(getattr(st, "value", None), ast.Constant)
                               and isinstance(st.value.value, str)):
            tag = "%s.%d" % (prefix, i)
            out.append(pause_stmt(tag))
            TAGCTX[tag] = ctx or "(top level)"
            TAGSRC[tag] = ast.unparse(st).split("\n")[0]
            for rl in role_list:
                TAGS[rl].append(tag)
        if i >= start:
            for field in ("body", "orelse", "finalbody"):
                sub = getattr(st, field, None)
                if sub and not isinstance(st, ast.While):
                    setattr(st, field, instr(sub, "%s.%d.%s" % (prefix, i, field), role_list, ctx=_ctx_of(st, field, ctx)))
            for j, h in enumerate(getattr(st, "handlers", []) or []):
                hc = ctx + " > except %s" % (_short(h.type) if h.type is not None else "(bare)")
                h.body = instr(h.body, "%s.%d.h%d" % (prefix, i, j), role_list, ctx=hc)
        out.append(st)
    return out


tree = ast.parse(open(RSUP).read())
funcs = {f.name: f for f in tree.body if isinstance(f, ast.FunctionDef)}
SHARED = {"teardown": ["keeper", "main"], "process_ledger": ["keeper", "main"], "remove_statedir": ["keeper", "main"],
          "read_report": ["keeper", "main"], "_exit_main": ["main"],
          # round 12: the bodies of process_ledger / remove_statedir moved into the fd-relative helpers they now call
          # (one proved fd, rule 4) -- the same statements, so the same await points (without these the census dropped
          # from 76 / 93 to 38 / 55 tags: a blind spot). remove_tree / _rmtree_at replace shutil.rmtree, which was never
          # instrumented either (one opaque call then, one opaque call now).
          "_ledger_at": ["keeper", "main"], "_remove_state_at": ["keeper", "main"]}
for fname, rl in SHARED.items():
    if fname in funcs:
        funcs[fname].body = instr(funcs[fname].body, fname, rl, ctx=fname)


def SHUT():
    """the shutdown phase starts right after the role's wait loop: a hook in a SHARED function (remove_statedir also
    runs in main's start-up gc, read_report / teardown only at shutdown) fires only from here on -- found by this
    file's first full run: a main-role remove_statedir hook fired during start-up gc, where a stop is BEFORE the work"""
    return ast.parse("_RP_SHUT[0] = True").body[0]


def after_last_while(fn, prefix, role):
    """instrument every statement AFTER the role's wait loop (the last top-level `while` of the body, or of the
    top-level try's body for the keeper)."""
    body = fn.body
    tr = next((s for s in body if isinstance(s, ast.Try)), None)
    if role == "keeper" and tr is not None:
        idx = max(i for i, s in enumerate(tr.body) if isinstance(s, ast.While))
        tr.body = instr(tr.body, prefix + ".try", [role], start=idx + 1, ctx=fn.name)
        tr.body.insert(idx + 1, SHUT())
        for j, h in enumerate(tr.handlers):
            h.body = instr(h.body, "%s.h%d" % (prefix, j), [role],
                           ctx=fn.name + " > except %s" % (_short(h.type) if h.type is not None else "(bare)"))
        tr.finalbody = instr(tr.finalbody, prefix + ".finally", [role], ctx=fn.name + " > finally")
    else:
        idx = max(i for i, s in enumerate(body) if isinstance(s, ast.While))
        fn.body = instr(body, prefix, [role], start=idx + 1, ctx=fn.name)
        fn.body.insert(idx + 1, SHUT())


# [R9SAME]: main logs (keeper wait status, stop, verified) at its ONE derivation, so a row can compare the keeper's OWN
# code with main's (every role must derive the same code from the same durable state)
mec = funcs["main_exit_code"]
mec.body.insert(1, ast.parse("_rk(kst, sig, done)").body[0])
after_last_while(funcs["_keeper"], "_keeper", "keeper")
after_last_while(funcs["cmd_main"], "cmd_main", "main")
tree.body[0:0] = ast.parse(HOOK).body
src = ast.unparse(ast.fix_missing_locations(tree))
src = src.replace("KEEPER_SLACK_S = 30.0", "KEEPER_SLACK_S = 2.0")
open(RSUP, "w").write(src)

# the worker's report sequence (bash): pause points around report-prepare / the writer / report-check / the exit
BHOOK = ('_r9p() { [ "${RP_WTAG:-}" = "$1" ] || return 0; ( set -o noclobber; echo "$$" > "$RP_FILE" ) 2>/dev/null '
         '|| return 0; local _i=0; while [ ! -e "$RP_FILE.go" ] && [ "$_i" -lt 2400 ]; do sleep 0.05; _i=$((_i+1)); '
         'done; }\n')
b = open(RBR).read()
WTAGS = []


def binject(old, new, tag):
    global b
    if b.count(old) != 1:
        bad("[R9CENSUS] worker hook %s: anchor matched %d times -- the worker's report sequence changed, re-enumerate"
            % (tag, b.count(old)))
        return
    b = b.replace(old, new, 1)
    WTAGS.append(tag)


binject('  if [ "$_FC_IS_WORKER" = 1 ]; then\n    python3 -I -S "$_FC_SUPERVISOR" report-prepare',
        '  _r9p W0-before-prepare\n  if [ "$_FC_IS_WORKER" = 1 ]; then\n    python3 -I -S "$_FC_SUPERVISOR" report-prepare',
        "W0-before-prepare")
binject('  python3 "$FC/lib/fc_common.py" emit --schema "$schema"', '  _r9p W1-after-prepare\n  python3 "$FC/lib/fc_common.py" emit --schema "$schema"',
        "W1-after-prepare")
binject('  emit_rc=$?\n  if [ "$_FC_IS_WORKER" = 1 ]; then\n    python3 -I -S "$_FC_SUPERVISOR" report-check',
        '  emit_rc=$?\n  _r9p W2-after-writer\n  if [ "$_FC_IS_WORKER" = 1 ]; then\n    python3 -I -S "$_FC_SUPERVISOR" report-check',
        "W2-after-writer")
binject('report-check --statedir "$_FC_STATEDIR" >/dev/null 2>&1 && return 0',
        'report-check --statedir "$_FC_STATEDIR" >/dev/null 2>&1 && { _r9p W3-after-check; return 0; }',
        "W3-after-check")
binject('  replay) cmd_replay "$@"; exit $? ;;', '  replay) cmd_replay "$@"; _r9rc=$?; _r9p W4-worker-exit; exit $_r9rc ;;',
        "W4-worker-exit")
b = b.replace("set -u\n", "set -u\n" + BHOOK, 1)
open(RBR, "w").write(b)

if want("R9CENSUS"):
    for rl in ("keeper", "main"):
        if TAGS[rl]:
            ok("[R9CENSUS] %s: %d await points inserted by the AST pass (generated from the code)" % (rl, len(TAGS[rl])))
        else:
            bad("[R9CENSUS] %s: the AST pass inserted no await point -- the instrument is blind" % rl)
    if len(WTAGS) == 5:
        ok("[R9CENSUS] worker: 5 await points around the report sequence")

# ---------------------------------------------------------------------------------------------------------------
# the run harness
# ---------------------------------------------------------------------------------------------------------------
def g(*a):
    return subprocess.run(["git", "-c", "user.email=t@t.t", "-c", "user.name=t"] + list(a), capture_output=True,
                          text=True)


ROOT = os.path.join(WORK, "m"); os.makedirs(ROOT)
REPO = os.path.join(ROOT, "repo"); os.makedirs(REPO)
g("init", "-q", REPO); open(os.path.join(REPO, "f.txt"), "w").write("x\n")
g("-C", REPO, "add", "f.txt"); g("-C", REPO, "commit", "-q", "-m", "base")
HEAD = g("-C", REPO, "rev-parse", "HEAD").stdout.strip()
TMP = os.path.join(ROOT, "tmp"); os.makedirs(TMP)
LOCKS = os.path.join(ROOT, "locks"); os.makedirs(LOCKS)
OUT = os.path.join(ROOT, "out.json")
HOLD = os.path.join(ROOT, "hold.sh")
open(HOLD, "w").write("#!/bin/bash\nexec sleep 600\n"); os.chmod(HOLD, 0o755)
BASEENV = dict(os.environ, TMPDIR=TMP, FC_REPLAY_LOCK_DIR=LOCKS, FC_BR_STOP_GRACE_S="1")
BASEENV.pop("FC_OUT", None)
REACHED = {"keeper": set(), "main": set()}


def argv(gate="true", wt=None, repo=None, head=None, out=None):
    return ["bash", RBR, "replay", "--commit", head or HEAD, "--repo-root", repo or REPO, "--worktree-root",
            wt or os.path.join(ROOT, "wt"), "--min-free-kb", "0", "--min-free-kb-objects", "0", "--gate-cmd", gate,
            "--cold-runs", "1", "--warm-runs", "0", "--out", out or OUT]


def report_ok():
    try:
        d = json.load(open(OUT))
        return isinstance(d, dict) and len(d.get("body_hash", "")) == 64
    except (OSError, ValueError):
        return False


def worktrees():
    return [l for l in g("-C", REPO, "worktree", "list", "--porcelain").stdout.splitlines()
            if l.startswith("worktree ") and "/replay." in l]


def settle(secs=30, allow_state=False):
    end = time.monotonic() + secs
    while True:
        reap_all()
        tmp = [n for n in os.listdir(TMP) if not (allow_state and n.startswith("fc_baseline_replay.state."))]
        live = descendants()
        if not live and not tmp and not worktrees():
            return True, ""
        if time.monotonic() > end:
            return False, "left=%r tmp=%r worktrees=%r" % (live, os.listdir(TMP), worktrees())
        time.sleep(0.1)


def start(env, stderr=subprocess.DEVNULL, gate="true", wt=None):
    for f in (OUT,):
        if os.path.exists(f):
            os.unlink(f)
    return subprocess.Popen(argv(gate, wt=wt), env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=stderr)


def wait_file(f, p, secs=60):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        if os.path.exists(f):
            try:
                txt = open(f).read().strip()
                if txt:
                    return int(txt)
            except (OSError, ValueError):
                pass
        if p.poll() is not None:
            return None
        time.sleep(0.01)
    return None


def finish(p, secs):
    try:
        return p.wait(timeout=secs)
    except subprocess.TimeoutExpired:
        kill_tree()
        p.wait()
        return "TIMEOUT"


def one(role, tag, action, k):
    """run one replay paused at `tag` in `role`, apply `action`; returns (reached, rc, report, settled, why)."""
    rp = os.path.join(ROOT, "rp.%d" % k)
    env = dict(BASEENV, RP_FILE=rp, RP_KLOG=rp + ".klog")
    if role == "worker":
        env["RP_WTAG"] = tag
    else:
        env.update(RP_TAG=tag, RP_ROLE={"keeper": "fc-keeper", "main": "fc-supervisor"}[role])
    p = start(env)
    pid = wait_file(rp, p)
    if pid is None:
        rc = finish(p, 60)
        ok_, why = settle()
        return False, rc, report_ok(), ok_, why
    REACHED.get(role, set()).add(tag)
    if action == "kill-self":
        sig_pid(pid, signal.SIGKILL)
    elif action == "term-self":
        sig_pid(pid, signal.SIGTERM)
        open(rp + ".go", "w").close()
    elif action == "term-main":
        sig_pid(p.pid, signal.SIGTERM)
        time.sleep(0.2)
        open(rp + ".go", "w").close()
    elif action == "wedged-term-main":
        sig_pid(pid, signal.SIGSTOP)            # the paused role cannot even poll its .go file: wedged
        sig_pid(p.pid, signal.SIGTERM)
    elif action == "continue":
        open(rp + ".go", "w").close()
    rc = finish(p, 90)
    if action == "kill-self" and role == "main":
        ok_, why = settle(30, allow_state=True)
    else:
        ok_, why = settle()
    # [R9SAME] the keeper's own code (when it exited by itself) equals the caller's code: one derivation, one answer
    try:
        line = open(rp + ".klog").read().split("\n")[0].split()
        kst = int(line[0]) if line and line[0] != "None" else None
    except (OSError, ValueError, IndexError):
        kst = None
    if kst is not None and os.WIFEXITED(kst) and isinstance(rc, int) and rc >= 0 and os.WEXITSTATUS(kst) != rc:
        ok_, why = False, why + " [R9SAME] the keeper exited %d but main decided %d" % (os.WEXITSTATUS(kst), rc)
    return True, rc, report_ok(), ok_, why


def sel_tag(t):
    return not TAGSEL or any(s in t for s in TAGSEL)


def sel_act(a):
    return not ACTS or a in ACTS


k = 0
if want("R9WIN"):
    # keeper: the worker has finished (report written) when the keeper's shutdown sequence starts
    if "keeper" in ROLES:
        for tag in TAGS["keeper"]:
            if not sel_tag(tag):
                continue
            for action in ("kill-self", "term-main", "wedged-term-main"):
                if not sel_act(action):
                    continue
                k += 1
                reached, rc, rep, settled, why = one("keeper", tag, action, k)
                t = "[R9WIN] keeper %s x %s" % (tag, action)
                if not reached:
                    break                       # unreached: the other actions cannot reach it either (census below)
                if rc == 0 and rep and settled:
                    ok("%s: rc 0, report on disk, quiescent" % t)
                else:
                    bad("%s: rc=%s (want 0) report=%s settled=%s %s" % (t, rc, rep, settled, why))
    if "main" in ROLES:
        for tag in TAGS["main"]:
            if not sel_tag(tag):
                continue
            for action in ("term-main", "kill-self"):
                if not sel_act(action):
                    continue
                k += 1
                reached, rc, rep, settled, why = one("main", tag, action, k)
                t = "[R9WIN] main %s x %s" % (tag, action)
                if not reached:
                    break
                want_rc = -9 if action == "kill-self" else 0
                if rc == want_rc and rep and settled:
                    ok("%s: rc %s, report on disk, quiescent" % (t, rc))
                else:
                    bad("%s: rc=%s (want %s) report=%s settled=%s %s" % (t, rc, want_rc, rep, settled, why))
    if "worker" in ROLES:
        for tag in WTAGS:
            if not sel_tag(tag):
                continue
            written = tag in ("W2-after-writer", "W3-after-check", "W4-worker-exit")
            for action, want_rc in (("kill-self", 137), ("term-self", 143), ("term-main", 143)):
                if not sel_act(action):
                    continue
                k += 1
                reached, rc, rep, settled, why = one("worker", tag, action, k)
                t = "[R9WIN] worker %s x %s" % (tag, action)
                if not reached:
                    bad("%s: the worker never reached its await point (rc=%s)" % (t, rc))
                    continue
                w_rc, w_rep = (0, True) if written else (want_rc, False)
                if rc == w_rc and rep == w_rep and settled:
                    ok("%s: rc %s, report %s, quiescent" % (t, rc, "on disk" if rep else "absent"))
                else:
                    bad("%s: rc=%s (want %s) report=%s (want %s) settled=%s %s" % (t, rc, w_rc, rep, w_rep, settled, why))

if want("R9GC2"):
    # main SIGKILLed after its keeper exited, before it removed its state directory: the directory stays (no live
    # decider). The next replay's gc_statedirs removes it (its owner is provably dead).
    tag = next((t for t in TAGS["main"] if t.startswith("cmd_main.")), None)
    k += 1
    reached, rc, rep, settled, why = one("main", tag, "kill-self", k) if tag else (False, None, False, False, "")
    left = [n for n in os.listdir(TMP) if n.startswith("fc_baseline_replay.state.")]
    if not (reached and rc == -9 and left):
        bad("[R9GC2] setup: main killed at %s: reached=%s rc=%s state dirs left=%r" % (tag, reached, rc, left))
    else:
        p = start(dict(BASEENV))
        rc2 = finish(p, 90)
        settled, why = settle()
        if rc2 == 0 and settled:
            ok("[R9GC2] the state directory of a main SIGKILLed after its keeper (%s) was removed by the next replay's "
               "gc_statedirs; the next replay itself rc 0" % left[0])
        else:
            bad("[R9GC2] next replay rc=%s settled=%s %s (dead owner's state dir %r)" % (rc2, settled, why, left))

if want("R9STALL"):
    # stderr: a pipe whose reader is alive but never reads, filled to capacity through a SECOND open file description
    # (O_NONBLOCK on our own description only -- the tool's stays blocking: a write by the tool really blocks)
    r, w = os.pipe()
    p = start(dict(BASEENV), stderr=w, gate=HOLD)
    os.close(w)
    holder = None
    end = time.monotonic() + 60
    while time.monotonic() < end and holder is None:
        for c in descendants():
            try:
                if open("/proc/%d/cmdline" % c, "rb").read().split(b"\0")[:2] == [b"sleep", b"600"]:
                    holder = c
            except OSError:
                pass
        time.sleep(0.05)
    wfd = os.open("/proc/%d/fd/2" % p.pid, os.O_WRONLY | os.O_NONBLOCK)
    filled = 0
    try:
        while True:
            filled += os.write(wfd, b"x" * 4096)
    except BlockingIOError:
        pass
    os.close(wfd)
    t0 = time.monotonic()
    sig_pid(p.pid, signal.SIGTERM)
    rc = finish(p, 60)
    dt = time.monotonic() - t0
    settled, why = settle()
    os.close(r)
    if holder is None:
        bad("[R9STALL] setup: the held gate never appeared")
    elif rc == 143 and settled and dt < 30:
        ok("[R9STALL] stderr filled (%d bytes) by a reader that never reads: TERM to main -> rc 143 in %.1f s, quiescent "
           "(no supervisor role blocked on the stream)" % (filled, dt))
    else:
        bad("[R9STALL] stalled stderr: rc=%s (want 143) after %.1f s settled=%s %s" % (rc, dt, settled, why))

# ---------------------------------------------------------------------------------------------------------------
# T048 V4 round 10 (round-3 review, V4R10-1 / -4 / -7)
# ---------------------------------------------------------------------------------------------------------------
def gate_up(secs=60):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        for c in descendants():
            try:
                if open("/proc/%d/cmdline" % c, "rb").read().split(b"\0")[:2] == [b"sleep", b"600"]:
                    return c
            except OSError:
                pass
        time.sleep(0.05)
    return None


def comm(pid):
    try:
        return open("/proc/%d/comm" % pid).read().strip()
    except OSError:
        return ""


def state_dirs():
    return [n for n in os.listdir(TMP) if n.startswith("fc_baseline_replay.state.")]


def inject(role, tag, inj, k):
    """V4R10-7: drive a shutdown path the ok-replay never takes. The gate is held; then `main-gone` SIGKILLs main (the
    keeper reads EOF -> cause main_gone -> its shutdown, where `tag` pauses it), or `keeper-killed` SIGKILLs the
    keeper in its wait loop (the ledger still lists the worktree and the log directory -> main's teardown processes
    them, where `tag` pauses main). The paused role is then let go; returns (reached, rc, report, settled, why)."""
    rp = os.path.join(ROOT, "rp.%d" % k)
    env = dict(BASEENV, RP_FILE=rp, RP_TAG=tag, RP_ROLE={"keeper": "fc-keeper", "main": "fc-supervisor"}[role])
    p = start(env, gate=HOLD)
    if gate_up() is None:
        rc = finish(p, 60)
        kill_tree()
        settle()
        return False, rc, report_ok(), False, "setup: the held gate never appeared"
    if inj == "main-gone":
        sig_pid(p.pid, signal.SIGKILL)
    else:
        kp = next((c for c in children(p.pid) if comm(c) == "fc-keeper"), None)
        if kp is None:
            finish(p, 60)
            kill_tree()
            return False, None, False, False, "setup: no keeper under main"
        sig_pid(kp, signal.SIGKILL)
    reached = False
    end = time.monotonic() + 60
    while time.monotonic() < end:
        try:
            if open(rp).read().strip():
                reached = True
                break
        except OSError:
            pass
        if p.poll() is not None and (inj != "main-gone" or not descendants()):
            break
        time.sleep(0.02)
    if reached:
        REACHED[role].add(tag)
        open(rp + ".go", "w").close()
    rc = finish(p, 90)
    ok_, why = settle()
    return reached, rc, report_ok(), ok_, why


if want("R10LEASE"):
    # V4R10-1 (the third member of the V4R8-2 class): main SIGKILLed while its keeper -- now the final decider -- is
    # still tearing down (paused before stop_tree / process_ledger), and two OTHER mains run gc_statedirs under the same
    # TMPDIR concurrently: a `selfcheck` (no lock at all) and a replay of ANOTHER repository with another lock
    # directory (what a repository on another filesystem is to the locks: not serialised). The keeper must still read
    # the marker: no INTERRUPTED in the finished run's log directory, its own code 0, the state directory present
    # until the keeper (main provably gone) removes it itself.
    # Round 11 (V4R11-2, RV4-08b survived round 10): the SAME row at a second pause point -- after the teardown, right
    # before the keeper's decision (decide_code(report_verified(...))) -- [R10LEASE-decide]: the lease must still be
    # held in the window between the teardown and the decision (picked by the statement it precedes, TAGSRC).
    REPO2 = os.path.join(ROOT, "repo2"); os.makedirs(REPO2, exist_ok=True)
    g("init", "-q", REPO2); open(os.path.join(REPO2, "g.txt"), "w").write("y\n")
    g("-C", REPO2, "add", "g.txt"); g("-C", REPO2, "commit", "-q", "-m", "base2")
    HEAD2 = g("-C", REPO2, "rev-parse", "HEAD").stdout.strip()
    LOCKS2 = os.path.join(ROOT, "locks2"); os.makedirs(LOCKS2, exist_ok=True)
    LEASE_POINTS = [("R10LEASE", next((t for t in TAGS["keeper"] if t.startswith("teardown.")), None)),
                    ("R10LEASE-decide", next((t for t in TAGS["keeper"] if t.startswith("_keeper.try.") and
                                              TAGSRC.get(t, "").startswith("code = decide_code(report_verified(")), None))]
    for li, (lname, tag) in enumerate(LEASE_POINTS):
        if tag is None:
            bad("[%s] setup: no keeper await point found (the code it precedes changed -- re-enumerate)" % lname)
            continue
        WT10 = os.path.join(ROOT, "wt_r10_%d" % li)
        k += 1
        rp = os.path.join(ROOT, "rp.%d" % k)
        p = start(dict(BASEENV, RP_FILE=rp, RP_TAG=tag, RP_ROLE="fc-keeper"), wt=WT10)
        kpid = wait_file(rp, p)
        if kpid is None:
            finish(p, 60)
            bad("[%s] setup: the keeper never paused at %s" % (lname, tag))
            continue
        REACHED["keeper"].add(tag)
        sd = state_dirs()
        sig_pid(p.pid, signal.SIGKILL)
        rc = finish(p, 30)
        scout = os.path.join(ROOT, "sc_r10_%d.json" % li)
        try:
            sc = subprocess.run(["bash", RBR, "selfcheck", "--out", scout], env=dict(BASEENV), stdin=subprocess.DEVNULL,
                                capture_output=True, timeout=50).returncode
        except subprocess.TimeoutExpired:
            sc = "TIMEOUT"
        try:
            r2 = subprocess.run(argv(wt=os.path.join(ROOT, "wt2_%d" % li), repo=REPO2, head=HEAD2,
                                     out=os.path.join(ROOT, "o2_%d.json" % li)),
                                env=dict(BASEENV, FC_REPLAY_LOCK_DIR=LOCKS2), stdin=subprocess.DEVNULL,
                                capture_output=True, timeout=50).returncode
        except subprocess.TimeoutExpired:
            r2 = "TIMEOUT"
        kept = len(sd) == 1 and os.path.isdir(os.path.join(TMP, sd[0])) and os.path.exists(
            os.path.join(TMP, sd[0], "report.pending"))
        open(rp + ".go", "w").close()
        kst = None
        end = time.monotonic() + 60
        while time.monotonic() < end and kst is None:
            try:
                pid_, st_ = os.waitpid(kpid, os.WNOHANG)
                if pid_ == kpid:
                    kst = st_
            except ChildProcessError:
                break
            time.sleep(0.05)
        intr = [os.path.join(d, f) for d, _, fs in os.walk(WT10) for f in fs if f == "INTERRUPTED"]
        gone = not [n for n in sd if os.path.lexists(os.path.join(TMP, n))]
        settled, why = settle()
        kcode = os.WEXITSTATUS(kst) if kst is not None and os.WIFEXITED(kst) else kst
        if rc == -9 and sc == 0 and r2 == 0 and kept and kcode == 0 and not intr and gone and settled and report_ok():
            ok("[%s] main SIGKILLed with its keeper paused at %s (before: %s); a concurrent selfcheck and a replay of "
               "another repository (other lock dir) ran gc_statedirs: the state directory was KEPT, the keeper read the "
               "report (code 0, no INTERRUPTED), then removed it itself; quiescent" % (lname, tag, TAGSRC.get(tag, "?")[:60]))
        else:
            bad("[%s] at %s: rc=%s selfcheck=%s replay2=%s state dir kept through the concurrent gc=%s (%r) keeper "
                "code=%s INTERRUPTED=%r removed by the keeper=%s settled=%s report=%s %s"
                % (lname, tag, rc, sc, r2, kept, sd, kcode, intr, gone, settled, report_ok(), why))

if want("R10DROP"):
    # V4R10-4: main throws AFTER it reaped its keeper (main is the final decider: main_owns) -> its exit funnel
    # (_drop_main_tmp) removes the state directory; rc 4 (an exception in main), nothing left behind
    tag = next((t for t in TAGS["main"] if t.startswith("teardown.")), None)
    k += 1
    rp = os.path.join(ROOT, "rp.%d" % k)
    p = start(dict(BASEENV, RP_FILE=rp, RP_TAG=tag or "none", RP_ROLE="fc-supervisor", RP_RAISE="1"))
    rc = finish(p, 90)
    settled, why = settle()
    hit = os.path.exists(rp)
    if hit:
        REACHED["main"].add(tag)
    if hit and rc == 4 and settled:
        ok("[R10DROP] main raised at %s after reaping its keeper: rc 4, its state directory removed, quiescent" % tag)
    else:
        bad("[R10DROP] main raised at %s (reached=%s): rc=%s (want 4) settled=%s %s" % (tag, hit, rc, settled, why))

if want("R10INJ"):
    # V4R10-7: every keeper tag the ok-replay did not reach, driven through the main-gone path; every main tag it did
    # not reach, driven through the keeper-killed path (the ledger still holds the worktree + the log directory)
    for rl, inj, want_rc in (("keeper", "main-gone", -9), ("main", "keeper-killed", 137)):
        if rl not in ROLES:
            continue
        for tag in [t for t in TAGS[rl] if t not in REACHED[rl] and sel_tag(t)]:
            k += 1
            reached, rc, rep, settled, why = inject(rl, tag, inj, k)
            t = "[R10INJ] %s %s x %s" % (rl, tag, inj)
            if not reached:
                if why.startswith("setup"):
                    bad("%s: %s" % (t, why))
                continue
            if rc == want_rc and not rep and settled:
                ok("%s: rc %s, no report, quiescent" % (t, rc))
            else:
                bad("%s: rc=%s (want %s) report=%s (want absent) settled=%s %s" % (t, rc, want_rc, rep, settled, why))

if want("R9CENSUS") and want("R9WIN") and want("R10INJ") and not TAGSEL and not ACTS:
    for rl in ("keeper", "main"):
        if rl not in ROLES:
            continue
        miss = [t for t in TAGS[rl] if t not in REACHED[rl]]
        hit = len(TAGS[rl]) - len(miss)
        if hit == 0:
            bad("[R9CENSUS] %s: NO await point was reached -- the hook or the role name is wrong (instrument blind)" % rl)
        else:
            # round 10 (V4R10-7): no blanket label -- each unreached tag is printed with the branch that guards it (taken
            # from the AST: the if-condition / except clause / loop it sits in), after the ok-replay rows, the
            # main-gone and keeper-killed injections ([R10INJ]), [R10LEASE] and [R10DROP] were driven
            ok("[R9CENSUS] %s: %d of %d await points reached and checked; %d unreached, each with its guard (the "
               "census counts PAUSE-HOOK HITS only: a tag a row executes without pausing there is listed as unreached -- "
               "e.g. _keeper.try.*.body.0, the keeper's late main-gone removal, which [R10LEASE] executes, round 11 "
               "V4R11-4): %s"
               % (rl, hit, len(TAGS[rl]), len(miss), "; ".join("%s [%s]" % (t, TAGCTX.get(t, "?")) for t in miss)
                  or "none"))

print("----")
print("SUMMARY pass=%d fail=%d" % (N["ok"], N["bad"]))
sys.exit(0 if N["bad"] == 0 else 1)
PY
exit $?
