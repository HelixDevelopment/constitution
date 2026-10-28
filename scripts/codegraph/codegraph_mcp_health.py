#!/usr/bin/env python3
# ============================================================================
# codegraph_mcp_health.py — real-round-trip health probe + safe self-heal for the CodeGraph MCP server
# ============================================================================
# Purpose      Answer, with captured evidence and never from config-reading alone, "will an agent platform that spawns the
#              project's declared `codegraph` MCP server get a working session RIGHT NOW?" and, with --heal, repair ONLY the
#              failure classes that are provably safe to repair. Born from the 2026-10-27 incident class (/mcp
#              "Failed to reconnect to codegraph: -32000 / Connection closed"): two independent causes were measured —
#              (A) an upstream version bump changed the code shape the read-only runner patch anchors on, so the sanctioned
#              wrapper exited 5 with an empty stdout (the client sees EOF); (B) a stock `serve --mcp` daemon whose main thread
#              is blocked by the file watcher's synchronous initial directory walk over a very large tree (captured CPU profile:
#              95 % in the gitignore matcher under watcher.start) and killed by its own 60 s watchdog in a ~6-minute loop. No gate
#              noticed either.
#              Checks (each prints `HEALTH <id> PASS|FAIL|WARN|SKIP <text>`):
#                H1 the project declares a `codegraph` server in .mcp.json (the EXACT command+args that will be spawned)
#                H2 version: effective `codegraph` on PATH vs the declared pin (FAIL on mismatch) and duplicate installs on PATH
#                H3 runner-patch applicability: the sanctioned wrapper's --dry-run resolves a receipt-valid read-only runner
#                   for the INSTALLED version (a REFUSED patch = upstream shape drift = the incident's root cause A)
#                H4 stale state files: lock / writer.pid / daemon.pid / daemon.sock judged by the holder's REAL /proc identity
#                H5 WAL growth against warn/fail thresholds (the 2026-09 81 GB WAL class)
#                H6 watchdog-kill loop in daemon.log and kernel OOM kills of node/codegraph in the window (evidence, not a verdict)
#                H7 user-scope stock `codegraph serve --mcp` entries (~/.claude.json, $CLAUDE_CONFIG_DIR/.claude.json)
#                H8 the REAL round trip: spawn the exact .mcp.json command (cwd = project), initialize -> tools/list ->
#                   codegraph_status (+ optional known-symbol search with a fabricated-symbol NEGATIVE control, §11.4.273)
#                   and prove the session left no writer/daemon artifacts behind (a read-only server must not create any)
#                H9 index metadata: schema version vs the installed software, index_state, synthesis_pending (read-only open)
#              --heal (idempotent, reversible, logged to <project>/.codegraph/index_runs/health_heal.log), ONLY:
#                A1 move provably-stale lock/pid/socket files aside (holder dead, or alive but NOT a codegraph process)
#                A2 wal_checkpoint(TRUNCATE) when the WAL is over the warn threshold, no live holder exists, and the writer
#                   flock (.codegraph/.helix_index.flock) is free; the WAL size is re-read to prove it shrank
#                A3 (re)build the read-only runner when it is missing/stale; a REFUSED patch is reported NEEDS-PATCH-UPDATE
#                   and is NEVER papered over or replaced by the stock server
#                A4 stop an identity-verified WEDGED daemon (writer.pid ready:false for > --wedge-s seconds): SIGTERM, then
#                   SIGKILL after 15 s; pid is validated as int > 1 first (§11.4.263)
#              A heal never edits ~/.claude.json, never deletes the database, never opens a live writer's database for write
#              while a holder exists, and never fabricates a PASS: the verdict printed after --heal is a fresh re-check.
# Usage        codegraph_mcp_health.py [--project DIR] [--mcp-json FILE] [--expect-version V | --pin FILE]
#                  [--probe-symbol NAME] [--heal] [--no-roundtrip] [--timeout-init S] [--timeout-list S] [--timeout-call S]
#                  [--wal-warn-mb N] [--wal-fail-gib N] [--window-h N] [--wedge-s N] [--json]
# Inputs       --pin FILE : first non-comment line `version=X.Y.Z` (default <project>/config/index/codegraph.pin if present)
#              HELIX_CODEGRAPH_SRC / HELIX_CODEGRAPH_RUNNER_DIR (as the wrapper); CLAUDE_CONFIG_DIR (H7)
# Outputs      `HEALTH <id> <status> <text>` lines, `HEAL <action> DONE|SKIP|REFUSED <text>` lines, `SUMMARY fail=N warn=M`;
#              --json adds one JSON object on the last line. Exit 0 = no FAIL · 1 = any FAIL · 2 = usage / cannot determine
#              (BLIND) · 3 = nothing to inspect (no codegraph server declared AND no index: SKIP, never a PASS) ·
#              4 = a live writer holds the index so the round trip could not run (BUSY: no verdict on it, never a PASS)
# Side effects the round trip spawns the declared server (a sanctioned read-only wrapper writes nothing); --heal as above;
#              nothing else. Read-only SQLite opens use mode=ro.
# Dependencies python3 (stdlib only); the sanctioned wrapper codegraph_mcp.sh + fk_index_patch.py beside this file for H3/A3
# Cross-refs   codegraph_mcp.sh, codegraph_mcp_preflight.sh, codegraph_mcp_probe.py, fk_index_patch.py, runner_patches/mcpro1.py,
#              scripts/gates/cm_codegraph_mcp_health.sh (+ its paired mutation test), docs/scripts/codegraph_mcp_health.md,
#              constitution §11.4.80(4) / §11.4.201 / §11.4.232 / §11.4.263 / §11.4.273 / §9.2
# ============================================================================
import argparse
import fcntl
import json
import os
import re
import select
import shutil
import signal
import sqlite3
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
STATE_FILES = ("codegraph.lock", "writer.pid", "daemon.pid", "daemon.sock")
RESULTS = []          # (id, status, text)
HEALS = []            # (action, status, text)
BUSY = []             # set when a live writer made the round trip impossible (exit 4, never a PASS)


def say(hid, status, text):
    RESULTS.append((hid, status, text))
    print("HEALTH %s %s %s" % (hid, status, text), flush=True)


def heal_say(action, status, text, log=None):
    HEALS.append((action, status, text))
    line = "HEAL %s %s %s" % (action, status, text)
    print(line, flush=True)
    if log:
        try:
            with open(log, "a") as f:
                f.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), line))
        except OSError:
            pass


# ---- process identity (real /proc cmdline, never a substring match on a carrier) -------------------------------------------
def proc_argv(pid):
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            raw = f.read()
    except OSError:
        return None
    return [a.decode("utf-8", "replace") for a in raw.split(b"\0") if a]


def is_codegraph_process(argv):
    """A codegraph server/CLI/daemon: some argv element's BASENAME is exactly codegraph or codegraph.js. A shell or a prompt
    that merely MENTIONS the word (a carrier) does not match (§11.4.196(D) / §11.4.201(7)(a))."""
    return bool(argv) and any(os.path.basename(a) in ("codegraph", "codegraph.js") for a in argv)


def holder_state(pid):
    """dead | codegraph | other (alive but not a codegraph process: pid reuse, so the file's holder is gone)."""
    if not isinstance(pid, int) or pid <= 1:
        return "dead"
    argv = proc_argv(pid)
    if argv is None:
        return "dead"
    return "codegraph" if is_codegraph_process(argv) else "other"


def read_pid_file(path):
    try:
        txt = open(path).read().strip()
    except OSError:
        return None, None
    try:
        obj = json.loads(txt)
        if isinstance(obj, dict):
            return obj.get("pid") if isinstance(obj.get("pid"), int) else None, obj
        if isinstance(obj, int):
            return obj, None
    except ValueError:
        pass
    m = re.match(r"^\d+$", txt)
    return (int(txt), None) if m else (None, None)


# ---- inputs ---------------------------------------------------------------------------------------------------------------
def load_server(mcp_json):
    try:
        data = json.load(open(mcp_json))
    except FileNotFoundError:
        return None, "no .mcp.json at %s" % mcp_json
    except ValueError as e:
        return None, ".mcp.json is not valid JSON: %s" % str(e)[:100]
    srv = (data.get("mcpServers") or {}).get("codegraph")
    if not isinstance(srv, dict) or not srv.get("command"):
        return None, "no `codegraph` server with a command in %s" % mcp_json
    return srv, ""


def effective_cmd(srv):
    return [str(srv["command"])] + [str(a) for a in (srv.get("args") or [])]


def run(cmd, cwd=None, timeout=60, env=None):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timeout after %ss" % timeout
    except OSError as e:
        return 127, "", str(e)


def path_codegraphs():
    seen, out = set(), []
    for d in os.environ.get("PATH", "").split(os.pathsep):
        p = os.path.join(d, "codegraph")
        if d and os.path.isfile(p) and os.access(p, os.X_OK):
            real = os.path.realpath(p)
            if real not in seen:
                seen.add(real)
                out.append(p)
    return out


def version_of(binpath):
    env = dict(os.environ, CODEGRAPH_NO_UPDATE_CHECK="1", DO_NOT_TRACK="1", CODEGRAPH_TELEMETRY="0")
    rc, so, se = run([binpath, "--version"], timeout=30, env=env)
    m = re.search(r"\d+\.\d+\.\d+(?:[-.\w]*)?", so + se)
    return m.group(0) if (rc == 0 and m) else None


# ---- checks ---------------------------------------------------------------------------------------------------------------
def check_version(project, expect, pin_file):
    if not expect:
        pf = pin_file or os.path.join(project, "config", "index", "codegraph.pin")
        if os.path.isfile(pf):
            for line in open(pf):
                line = line.strip()
                if line and not line.startswith("#"):
                    m = re.match(r"^version\s*=\s*(\S+)$", line)
                    if m:
                        expect = m.group(1)
                    break
            if not expect:
                say("H2", "FAIL", "pin file %s has no `version=` line" % pf)
                return None
    cands = path_codegraphs()
    if not cands:
        say("H2", "FAIL", "no `codegraph` executable on PATH")
        return None
    vers = [(c, version_of(c)) for c in cands]
    eff_path, eff = vers[0]
    if eff is None:
        say("H2", "FAIL", "`%s --version` produced no version (cannot read the installed version)" % eff_path)
        return None
    distinct = sorted({v for _, v in vers if v})
    if expect and eff != expect:
        say("H2", "FAIL", "installed %s (first on PATH: %s) != pinned %s" % (eff, eff_path, expect))
    elif len(distinct) > 1:
        say("H2", "WARN", "PATH carries %d codegraph installs with versions %s (first wins: %s %s) — PATH-order dependent%s"
            % (len(vers), distinct, eff_path, eff, "; pin %s matches the first" % expect if expect else ""))
    else:
        say("H2", "PASS", "installed %s (%s)%s" % (eff, eff_path, " == pin" if expect else "; no pin declared (WARN-free, but a pin makes drift a FAIL)"))
    return eff


def wrapper_of(cmd, project):
    for a in cmd:
        if os.path.basename(a) == "codegraph_mcp.sh":
            return a if os.path.isabs(a) else os.path.join(project, a)
    return None


def check_runner(cmd, project, heal, hlog):
    w = wrapper_of(cmd, project)
    if not w:
        say("H3", "WARN", "declared server is not the sanctioned read-only wrapper (codegraph_mcp.sh): %s — a stock server writes and daemonizes" % " ".join(cmd[:3]))
        return "ok"
    if not os.path.isfile(w):
        say("H3", "FAIL", "wrapper path in .mcp.json does not exist: %s" % w)
        return "fail"
    rc, so, se = run(["bash", w, "--dry-run"], cwd=project, timeout=300)
    if rc == 0:
        say("H3", "PASS", "wrapper --dry-run resolves a receipt-valid read-only runner")
        return "ok"
    first = (se.strip().splitlines() or ["(no stderr)"])[-1][:260]
    if rc == 4:      # the wrapper's own documented refusal: a LIVE writer holds the database (by design, transient)
        say("H3", "WARN", "BUSY — a live writer holds the database, so the wrapper refuses to start (by design, transient): %s" % first)
        return "busy"
    drift = "REFUSED" in se or "anchor" in se
    if heal and not drift:
        tool = os.path.join(os.path.dirname(w), "fk_index_patch.py")
        rc2, so2, se2 = run([sys.executable, tool, "--patches", "mcpro1", "--print-bin"], timeout=600)
        if rc2 == 0:
            heal_say("A3", "DONE", "rebuilt the read-only runner: %s" % so2.strip()[:160], hlog)
            rc3, _, se3 = run(["bash", w, "--dry-run"], cwd=project, timeout=300)
            if rc3 == 0:
                say("H3", "PASS", "wrapper --dry-run resolves a receipt-valid read-only runner (after A3)")
                return "ok"
            first = (se3.strip().splitlines() or ["(no stderr)"])[-1][:260]
        else:
            first = (se2.strip().splitlines() or ["(no stderr)"])[-1][:260]
            drift = drift or "REFUSED" in (so2 + se2)
    if heal and drift:
        heal_say("A3", "REFUSED", "NEEDS-PATCH-UPDATE: the runner patch does not apply to the installed version (upstream shape drift); "
                 "the stock server is never substituted", hlog)
    say("H3", "FAIL", "wrapper cannot provide a read-only runner (rc=%d): %s" % (rc, first))
    return "fail"


def state_files(cg):
    out = []
    for name in STATE_FILES:
        p = os.path.join(cg, name)
        if os.path.lexists(p):
            pid, obj = (None, None) if name == "daemon.sock" else read_pid_file(p)
            out.append((name, p, pid, obj))
    return out


def check_state(project, heal, hlog, wedge_s):
    cg = os.path.join(project, ".codegraph")
    items = state_files(cg)
    if not items:
        say("H4", "PASS", "no lock / writer.pid / daemon.pid / daemon.sock present")
        return
    live_codegraph, stale = [], []
    sock_present = any(n == "daemon.sock" for n, *_ in items)
    daemon_alive = False
    for name, p, pid, obj in items:
        if name == "daemon.sock":
            continue
        st = holder_state(pid) if pid else "dead"
        if st == "codegraph":
            live_codegraph.append((name, pid, obj))
            if name in ("writer.pid", "daemon.pid"):
                daemon_alive = True
        else:
            stale.append((name, p, pid, st))
    if sock_present and not daemon_alive:
        stale.append(("daemon.sock", os.path.join(cg, "daemon.sock"), None, "dead"))
    if live_codegraph:
        say("H4", "PASS", "live codegraph holder(s): %s (the read-only wrapper refuses to start while a writer lives — by design)"
            % ", ".join("%s=pid %d" % (n, pid) for n, pid, _ in live_codegraph))
    if stale:
        say("H4", "WARN", "stale state file(s): %s" % ", ".join("%s (holder %s %s)" % (n, pid if pid else "-", st) for n, _, pid, st in stale))
        if heal:
            dest = os.path.join(cg, "index_runs", "health_reaped_%s" % time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
            os.makedirs(dest, exist_ok=True)
            for n, p, pid, st in stale:
                try:
                    shutil.move(p, os.path.join(dest, n))
                    heal_say("A1", "DONE", "moved %s aside to %s (holder pid %s: %s)" % (n, dest, pid if pid else "-", st), hlog)
                except OSError as e:
                    heal_say("A1", "REFUSED", "could not move %s: %s" % (n, e), hlog)
    elif not live_codegraph:
        say("H4", "PASS", "no stale state files")
    # wedged daemon (A4)
    for name, pid, obj in live_codegraph:
        if name == "writer.pid" and isinstance(obj, dict) and obj.get("ready") is False:
            started = obj.get("startedAt")
            age = (time.time() - started / 1000.0) if isinstance(started, (int, float)) else None
            if age is not None and age > wedge_s:
                say("H4", "WARN", "daemon pid %d is not ready after %ds (wedge suspect)" % (pid, int(age)))
                if heal:
                    kill_wedged(pid, hlog)


def kill_wedged(pid, hlog):
    argv = proc_argv(pid)
    if not (isinstance(pid, int) and pid > 1 and argv and is_codegraph_process(argv)):
        heal_say("A4", "REFUSED", "pid %s identity not verified as a codegraph process" % pid, hlog)
        return
    os.kill(pid, signal.SIGTERM)
    for _ in range(15):
        time.sleep(1)
        if holder_state(pid) == "dead":
            heal_say("A4", "DONE", "SIGTERM stopped wedged codegraph daemon pid %d" % pid, hlog)
            return
    if holder_state(pid) == "codegraph":
        os.kill(pid, signal.SIGKILL)
        heal_say("A4", "DONE", "SIGKILL after 15s stopped wedged codegraph daemon pid %d" % pid, hlog)


def holders_of_db(db):
    me, hits = os.getpid(), []
    try:
        pids = [int(x) for x in os.listdir("/proc") if x.isdigit()]
    except OSError:
        return None
    for pid in pids:
        if pid == me:
            continue
        fddir = "/proc/%d/fd" % pid
        try:
            for fd in os.listdir(fddir):
                try:
                    if os.readlink(os.path.join(fddir, fd)) == db:
                        hits.append(pid)
                        break
                except OSError:
                    continue
        except OSError:
            continue
    return hits


def check_wal(project, heal, hlog, warn_mb, fail_gib):
    cg = os.path.join(project, ".codegraph")
    db, wal = os.path.join(cg, "codegraph.db"), os.path.join(cg, "codegraph.db-wal")
    if not os.path.isfile(db):
        say("H5", "SKIP", "no codegraph.db (nothing to size)")
        return
    sz = os.path.getsize(wal) if os.path.isfile(wal) else 0
    mb = sz / 1048576.0
    if sz >= fail_gib * 1073741824:
        status = "FAIL"
    elif mb >= warn_mb:
        status = "WARN"
    else:
        status = "PASS"
    say("H5", status, "WAL %.0f MiB (warn >= %d MiB, fail >= %d GiB), db %.1f GiB" % (mb, warn_mb, fail_gib, os.path.getsize(db) / 1073741824.0))
    if heal and status in ("WARN", "FAIL"):
        h = holders_of_db(db)
        if h is None:
            heal_say("A2", "REFUSED", "cannot enumerate /proc to prove there is no live holder", hlog)
        elif h:
            heal_say("A2", "SKIP", "live holder(s) of the database: %s — no checkpoint" % h, hlog)
        else:
            lockf = os.path.join(cg, ".helix_index.flock")
            fd = os.open(lockf, os.O_RDWR | os.O_CREAT, 0o644)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                heal_say("A2", "REFUSED", "the writer flock %s is held by another launcher" % lockf, hlog)
                os.close(fd)
                return
            try:
                c = sqlite3.connect(db, timeout=60)
                r = c.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
                c.close()
                after = os.path.getsize(wal) if os.path.isfile(wal) else 0
                heal_say("A2", "DONE" if after < sz else "SKIP", "wal_checkpoint(TRUNCATE) %s: WAL %d -> %d bytes" % (r, sz, after), hlog)
            except sqlite3.Error as e:
                heal_say("A2", "REFUSED", "checkpoint failed: %s" % e, hlog)
            finally:
                os.close(fd)


def check_evidence(project, window_h):
    cg = os.path.join(project, ".codegraph")
    log = os.path.join(cg, "daemon.log")
    now = time.time()
    kills = 0
    if os.path.isfile(log):
        pat = re.compile(r"^\[(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?Z\].*Main thread unresponsive")
        for line in open(log, errors="replace"):
            m = pat.match(line)
            if m:
                t = time.mktime(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")) - time.timezone
                if now - t <= window_h * 3600:
                    kills += 1
    if kills >= 3:
        say("H6", "WARN", "%d daemon watchdog kills in the last %dh (a stock `serve --mcp` daemon is wedging in a loop)" % (kills, window_h))
    else:
        say("H6", "PASS", "%d daemon watchdog kill(s) in the last %dh" % (kills, window_h))
    rc, so, _ = run(["journalctl", "-k", "--no-pager", "-q", "-n", "1"], timeout=20)
    if rc != 0 or not so.strip():
        say("H6", "SKIP", "kernel journal not readable (no OOM evidence either way — not a PASS)")
        return
    rc, so, _ = run(["journalctl", "-k", "--no-pager", "-q", "--since", "-%dh" % window_h], timeout=60)
    n = len(re.findall(r"Killed process \d+ \((?:node|codegraph)\)", so))
    say("H6", "WARN" if n else "PASS", "%d kernel OOM kill(s) of a node/codegraph process in the last %dh%s"
        % (n, window_h, " (attribution to CodeGraph is not established by this check)" if n else ""))


def check_user_scope():
    files = [os.path.expanduser("~/.claude.json")]
    if os.environ.get("CLAUDE_CONFIG_DIR"):
        files.append(os.path.join(os.environ["CLAUDE_CONFIG_DIR"], ".claude.json"))
    bad = []
    for f in dict.fromkeys(files):
        try:
            data = json.load(open(f))
        except (OSError, ValueError):
            continue
        scopes = [("user", data.get("mcpServers") or {})]
        for pth, pv in (data.get("projects") or {}).items():
            if isinstance(pv, dict):
                scopes.append((pth, pv.get("mcpServers") or {}))
        for scope, servers in scopes:
            for name, s in (servers or {}).items():
                if not isinstance(s, dict):
                    continue
                argv = [str(s.get("command", ""))] + [str(a) for a in (s.get("args") or [])]
                joined = " ".join(argv)
                if "codegraph_mcp.sh" in joined:
                    continue
                if re.search(r"(^|/)codegraph(\.js)?(\s|$)", joined) or "@colbymchenry/codegraph" in joined:
                    bad.append("%s [%s/%s]: %s" % (f, scope, name, " ".join(argv[:3])))
    if bad:
        say("H7", "WARN", "user-scope stock codegraph server(s) (spawn a writer + daemon, no read-only guarantee): " + "; ".join(bad))
    else:
        say("H7", "PASS", "no user-scope stock codegraph server entry")


class Session:
    def __init__(self, cmd, cwd):
        self.p = subprocess.Popen(cmd, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        self.buf = b""
        self.errf = []
        self.eof = False

    def send(self, obj):
        try:
            self.p.stdin.write((json.dumps(obj) + "\n").encode())
            self.p.stdin.flush()
        except (BrokenPipeError, OSError):
            pass

    def recv(self, mid, timeout):
        end = time.time() + timeout
        while time.time() < end:
            while b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                try:
                    m = json.loads(line)
                except ValueError:
                    continue
                if m.get("id") == mid and ("result" in m or "error" in m):
                    return m
            r, _, _ = select.select([self.p.stdout], [], [], 0.5)
            if r:
                chunk = os.read(self.p.stdout.fileno(), 65536)
                if not chunk:
                    self.eof = True
                    return None
                self.buf += chunk
            elif self.p.poll() is not None and not r:
                self.eof = True
                return None
        return None

    def close(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        try:
            self.p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pgid = os.getpgid(self.p.pid) if self.p.poll() is None else 0
            if isinstance(pgid, int) and pgid > 1:                       # §11.4.263: never signal pgid <= 1
                os.killpg(pgid, signal.SIGTERM)
                try:
                    self.p.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(pgid, signal.SIGKILL)
                    self.p.wait()
        try:
            err = self.p.stderr.read().decode("utf-8", "replace")
        except OSError:
            err = ""
        return self.p.returncode, err


def call_tool(s, mid, name, args, timeout):
    s.send({"jsonrpc": "2.0", "id": mid, "method": "tools/call", "params": {"name": name, "arguments": args}})
    m = s.recv(mid, timeout)
    if not m or "result" not in m:
        return None, "no answer in %ss" % timeout
    res = m["result"]
    text = "".join(c.get("text", "") for c in res.get("content", []) if isinstance(c, dict))
    return (not res.get("isError"), text)


def check_roundtrip(cmd, project, t_init, t_list, t_call, probe_symbol):
    cg = os.path.join(project, ".codegraph")
    before = {n for n in ("writer.pid", "daemon.pid", "daemon.sock") if os.path.lexists(os.path.join(cg, n))}
    t0 = time.time()
    try:
        s = Session(cmd, project)
    except OSError as e:
        say("H8", "FAIL", "cannot spawn the declared server %s: %s" % (cmd[:2], e))
        return
    s.send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "codegraph_mcp_health", "version": "1"}}})
    m = s.recv(1, t_init)
    if not m or "result" not in m:
        rc, err = s.close()
        why = "server exited rc=%s before answering initialize (the client sees `-32000 Connection closed`)" % rc if s.eof else "no initialize answer within %ss" % t_init
        say("H8", "FAIL", "%s; stderr: %s" % (why, " | ".join(err.strip().splitlines()[-3:])[:360] or "(empty)"))
        return
    t_i = time.time() - t0
    s.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    s.send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    m = s.recv(2, t_list)
    tools = [t.get("name") for t in ((m or {}).get("result") or {}).get("tools", [])] if m else []
    if not tools:
        s.close()
        say("H8", "FAIL", "initialize ok in %.1fs but tools/list returned no tools within %ss" % (t_i, t_list))
        return
    t_l = time.time() - t0
    ok, text = call_tool(s, 3, "codegraph_status", {}, t_call)
    detail = "initialize %.1fs, tools/list %.1fs (%d tools)" % (t_i, t_l, len(tools))
    status, msg = "PASS", ""
    if ok is None:
        status, msg = "FAIL", "codegraph_status gave no answer (%s)" % text
    elif not ok or not text.strip():
        status, msg = "FAIL", "codegraph_status returned isError or empty text: %s" % text[:160]
    elif probe_symbol:
        ok2, t2 = call_tool(s, 4, "codegraph_search", {"query": probe_symbol}, t_call)
        neg = "zz_cg_health_absent_%d" % os.getpid()
        ok3, t3 = call_tool(s, 5, "codegraph_search", {"query": neg}, t_call)
        hit = re.compile(r"Search Results \((\d+) found\)")
        m2, m3 = hit.search(t2 or ""), hit.search(t3 or "")
        if not ok2 or not m2 or int(m2.group(1)) < 1 or probe_symbol.lower() not in (t2 or "").lower():
            status, msg = "FAIL", "positive control: known symbol %r not found by codegraph_search" % probe_symbol
        elif ok3 is None or (m3 and int(m3.group(1)) > 0):
            status, msg = "FAIL", "negative control: a fabricated symbol was matched (the instrument cannot discriminate)"
        else:
            msg = "known symbol %r found; fabricated symbol not found (controls hold)" % probe_symbol
    rc, err = s.close()
    after = {n for n in ("writer.pid", "daemon.pid", "daemon.sock") if os.path.lexists(os.path.join(cg, n))}
    created = sorted(after - before)
    if status == "PASS" and created and wrapper_of(cmd, project):
        status, msg = "FAIL", "the read-only session created %s (a read-only server must write no writer/daemon file)" % created
    say("H8", status, "%s%s; total %.1fs%s" % (detail, ("; " + msg) if msg else "", time.time() - t0,
                                              "; stderr: %s" % err.strip().splitlines()[-1][:160] if (status != "PASS" and err.strip()) else ""))


def installed_schema(src):
    try:
        t = open(os.path.join(src, "lib", "dist", "db", "migrations.js"), errors="replace").read()
    except OSError:
        return None
    m = re.search(r"CURRENT_SCHEMA_VERSION\s*=\s*(\d+)", t)
    return int(m.group(1)) if m else None


def check_index(project):
    db = os.path.join(project, ".codegraph", "codegraph.db")
    if not os.path.isfile(db):
        say("H9", "WARN", "no index at %s (the wrapper refuses to start without one)" % db)
        return
    try:
        c = sqlite3.connect("file:%s?mode=ro" % db, uri=True, timeout=5)
        meta = dict((k, v) for k, v, *_ in c.execute("select key,value,updated_at from project_metadata"))
        sv = c.execute("select max(version) from schema_versions").fetchone()[0]
        c.close()
    except sqlite3.Error as e:
        say("H9", "WARN", "index metadata not readable now (%s) — possibly a live writer" % str(e)[:120])
        return
    src = None
    try:
        sys.path.insert(0, HERE)
        import fk_index_patch
        src = fk_index_patch.default_src()
    except Exception:
        pass
    cur = installed_schema(src) if src else None
    notes = ["index_state=%s" % meta.get("index_state"), "synthesis_pending=%s" % meta.get("synthesis_pending"),
             "db schema v%s" % sv, "installed schema %s" % ("v%d" % cur if cur else "unknown")]
    if cur and sv and sv > cur:
        say("H9", "FAIL", "; ".join(notes) + " — the index is NEWER than the installed software (it cannot open it)")
    elif cur and sv and sv < cur:
        say("H9", "WARN", "; ".join(notes) + " — the read-only runner never migrates: run the sanctioned writer (codegraph_safe.sh sync) once")
    elif meta.get("index_state") != "complete" or meta.get("synthesis_pending") not in ("0", None):
        say("H9", "WARN", "; ".join(notes) + " — index work is still owed (a sync has pending work)")
    else:
        say("H9", "PASS", "; ".join(notes))


# ---- main -----------------------------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--project", default=os.getcwd())
    ap.add_argument("--mcp-json")
    ap.add_argument("--expect-version")
    ap.add_argument("--pin")
    ap.add_argument("--probe-symbol")
    ap.add_argument("--heal", action="store_true")
    ap.add_argument("--no-roundtrip", action="store_true")
    ap.add_argument("--timeout-init", type=float, default=30)
    ap.add_argument("--timeout-list", type=float, default=60)
    ap.add_argument("--timeout-call", type=float, default=180)
    ap.add_argument("--wal-warn-mb", type=int, default=1024)
    ap.add_argument("--wal-fail-gib", type=int, default=20)
    ap.add_argument("--window-h", type=int, default=24)
    ap.add_argument("--wedge-s", type=int, default=120)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    project = os.path.realpath(a.project)
    if not os.path.isdir(project):
        print("codegraph_mcp_health: project directory not found: %s" % a.project, file=sys.stderr)
        return 2
    mcp = a.mcp_json or os.path.join(project, ".mcp.json")
    cg = os.path.join(project, ".codegraph")
    srv, why = load_server(mcp)
    # "indexed" means an index DATABASE exists, not that a `.codegraph` directory does (the constitution tracks
    # `.codegraph/.gitignore`, so the bare directory exists in every checkout; review round 2, R2-F6).
    if srv is None and not os.path.isfile(os.path.join(cg, "codegraph.db")):
        print("HEALTH H1 SKIP %s and no %s index database — nothing to inspect (not a PASS)" % (why, os.path.join(cg, "codegraph.db")))
        return 3
    if a.heal and os.path.isdir(cg):
        os.makedirs(os.path.join(cg, "index_runs"), exist_ok=True)
    hlog = os.path.join(cg, "index_runs", "health_heal.log")

    def one_pass(heal):
        del RESULTS[:]
        del BUSY[:]
        if srv is None:
            say("H1", "FAIL", why)
            cmd = None
        else:
            cmd = effective_cmd(srv)
            say("H1", "PASS", "declared server: %s" % " ".join(cmd))
        check_version(project, a.expect_version, a.pin)
        runner = check_runner(cmd, project, heal, hlog) if cmd else "fail"
        check_state(project, heal, hlog, a.wedge_s)
        check_wal(project, heal, hlog, a.wal_warn_mb, a.wal_fail_gib)
        check_evidence(project, a.window_h)
        check_user_scope()
        if a.no_roundtrip:
            say("H8", "SKIP", "--no-roundtrip: the real round trip was not performed (not a PASS)")
        elif cmd is None:
            say("H8", "FAIL", "no declared server to round-trip")
        elif runner == "busy":
            BUSY.append(True)
            say("H8", "SKIP", "live writer holds the database (by design) — the round trip was not performed, so there is NO verdict on it (not a PASS)")
        else:
            check_roundtrip(cmd, project, a.timeout_init, a.timeout_list, a.timeout_call, a.probe_symbol)
        check_index(project)

    one_pass(a.heal)
    if a.heal and HEALS:
        print("HEAL re-checking after %d action(s)" % len(HEALS))
        one_pass(False)
    fails = sum(1 for r in RESULTS if r[1] == "FAIL")
    warns = sum(1 for r in RESULTS if r[1] == "WARN")
    print("SUMMARY fail=%d warn=%d" % (fails, warns))
    if a.json:
        print(json.dumps({"project": project, "fail": fails, "warn": warns, "results": RESULTS, "heals": HEALS}))
    if fails:
        return 1
    return 4 if BUSY else 0


if __name__ == "__main__":
    sys.exit(main())
