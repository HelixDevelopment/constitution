#!/usr/bin/env python3
"""tests/release/net_probe.py — real-network probe for the release-script tests (round 6, K1, K2, K3).

Class (section 11.4.289(C)): the servers are local loopback listeners written for the test (a test
double of a hosting server); the git, git-remote-http(s) and timeout processes they talk to are REAL.
The run proves how the real processes behave (process group at the deadline, argv and environment of
every descendant); it is not live proof against a hosting platform.

Usage:
  net_probe.py drive MODE MARKER OUTJSON -- CMD...
      MODE  hang   : a listener that accepts every connection and never answers (http and https alike:
                     a TLS client hangs in its handshake)
            auth   : an HTTP listener that answers 401 Basic to a request without Authorization and
                     never answers a request that carries one (it records the header it received)
      Starts the listener on 127.0.0.1, exports PROBE_PORT, runs CMD (its argv may hold the literal
      string @PORT@, replaced by the port), and while CMD runs samples every descendant process of CMD
      (pid, ppid, pgid, argv, environment). It writes OUTJSON with: rc, elapsed, samples (every
      descendant seen, one record per pid and command line: a process that re-executes itself, such as
      the release scripts' "rc-clean-env" re-execution of round 7, gets a second record), auth_header (mode auth), and leftover (pids of
      descendants still alive 3 s after CMD ended whose argv holds MARKER). Leftover processes are
      reported, then signalled with SIGKILL by pid (only pids that this probe saw as descendants of the
      CMD it started, pid > 1).
"""
import base64
import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time


def listener(mode, rec):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 0))
    s.listen(32)
    held = []

    def serve(c):
        if mode == "hang":
            held.append(c)
            return
        data = b""
        c.settimeout(30)
        try:
            while b"\r\n\r\n" not in data:
                b = c.recv(4096)
                if not b:
                    break
                data += b
        except Exception:
            pass
        auth = None
        for line in data.split(b"\r\n"):
            if line.lower().startswith(b"authorization:"):
                auth = line.split(b":", 1)[1].strip().decode("latin-1")
        if auth is None:
            body = b"auth needed"
            c.sendall(b"HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"probe\"\r\n"
                      b"Content-Length: " + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
            c.close()
        else:
            rec["auth_header"] = auth
            held.append(c)          # never answer the authenticated request

    def loop():
        while True:
            try:
                c, _ = s.accept()
            except Exception:
                return
            threading.Thread(target=serve, args=(c,), daemon=True).start()

    threading.Thread(target=loop, daemon=True).start()
    return s, s.getsockname()[1]


def procs():
    out = {}
    for q in os.listdir("/proc"):
        if not q.isdigit():
            continue
        try:
            st = open("/proc/%s/stat" % q).read()
            rest = st[st.rindex(")") + 2:].split()
            ppid, pgid = int(rest[1]), int(rest[2])
            argv = open("/proc/%s/cmdline" % q, "rb").read().split(b"\0")
            try:
                env = open("/proc/%s/environ" % q, "rb").read().split(b"\0")
            except Exception:
                env = None
            out[int(q)] = (ppid, pgid, argv, env)
        except Exception:
            pass
    return out


def descendants(root, table):
    kids = {}
    for pid, (ppid, _, _, _) in table.items():
        kids.setdefault(ppid, []).append(pid)
    seen, todo = [], [root]
    while todo:
        p = todo.pop()
        for k in kids.get(p, []):
            seen.append(k)
            todo.append(k)
    return seen


def main():
    a = sys.argv[1:]
    if len(a) < 5 or a[0] != "drive" or a[4] != "--":
        sys.exit(__doc__)
    mode, marker, outjson, cmd = a[1], a[2], a[3], a[5:]
    rec = {}
    s, port = listener(mode, rec)
    cmd = [c.replace("@PORT@", str(port)) for c in cmd]
    env = dict(os.environ, PROBE_PORT=str(port))
    t0 = time.time()
    p = subprocess.Popen(cmd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    samples, alltree = {}, set()
    out_chunks = []
    reader = threading.Thread(target=lambda: out_chunks.append(p.stdout.read()), daemon=True)
    reader.start()
    while p.poll() is None:
        t = procs()
        for d in descendants(p.pid, t):
            alltree.add(d)
            if d in t and (d, tuple(t[d][2])) not in samples:
                ppid, pgid, argv, envl = t[d]
                samples[(d, tuple(argv))] = {"ppid": ppid, "pgid": pgid,
                              "argv": [x.decode("utf-8", "replace") for x in argv if x],
                              "env": None if envl is None else [x.decode("utf-8", "replace") for x in envl if x]}
        time.sleep(0.05)
    rc = p.returncode
    elapsed = time.time() - t0
    reader.join(5)
    time.sleep(3)
    t = procs()
    leftover = []
    for d in sorted(alltree):
        if d in t and d > 1 and marker.encode() in b" ".join(t[d][2]):
            leftover.append(d)
    for d in leftover:
        try:
            os.kill(d, signal.SIGKILL)
        except Exception:
            pass
    s.close()
    json.dump({"rc": rc, "elapsed": elapsed, "port": port, "samples": list(samples.values()),
               "auth_header": rec.get("auth_header"), "leftover": leftover,
               "output": b"".join(out_chunks).decode("utf-8", "replace")}, open(outjson, "w"))


def basic(user, pw):
    return "Basic " + base64.b64encode(("%s:%s" % (user, pw)).encode()).decode()


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "basic":
        print(basic(sys.argv[2], sys.argv[3]))
    else:
        main()
