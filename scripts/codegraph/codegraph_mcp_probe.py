#!/usr/bin/env python3
# ============================================================================
# codegraph_mcp_probe.py — drive a CodeGraph MCP server over stdio and report
# ============================================================================
# Purpose      A minimal, dependency-free MCP client (newline-delimited JSON-RPC
#              2.0, protocol 2024-11-05) that starts ONE stdio MCP server
#              command, performs initialize + tools/list + N tools/call, and
#              prints a single JSON report. Used by the read-only-MCP tooling
#              (codegraph_mcp_preflight.sh, tests/test_mcp_readonly.sh) to
#              prove — with captured evidence, not config-reading — that a
#              configured server answers a real query, and how it holds the
#              database (fd access mode read from /proc, §11.4.201 real
#              condition, not a proxy signal).
# Usage        codegraph_mcp_probe.py --project DIR [--bin CMD] [--env K=V]...
#                  [--tool NAME] [--query TEXT] [--expect SUBSTR] [--calls N]
#                  [--hold SECONDS] [--timeout SECONDS] [--stderr-file PATH]
#                  [--list-only]
#              The server is launched as:  <--bin> serve --mcp   (cwd = DIR)
#              (default --bin: `codegraph`). DIR must be a FIXTURE or a
#              project the caller has verified is safe to open — this tool
#              opens the project's database through the server.
# Inputs       see Usage. --expect: substring that must appear in every
#              answer (default: the query text). --tool default
#              codegraph_search (callable even when not listed, see
#              CODEGRAPH_MCP_TOOLS).
# Outputs      ONE JSON line on stdout: init_ok, server, tools, calls,
#              calls_ok, last (first 300 chars of the last answer), pid,
#              db_fd_modes (per open codegraph.db descriptor of the server
#              PID: "r" = O_RDONLY, "rw" = writable), rss_kb, threads,
#              stderr_path. Exit 0 = initialized AND every call answered with
#              the expectation and without isError; 1 = failed; 2 = usage.
# Side effects spawns the server (which may write the project's .codegraph/
#              unless it is a read-only runner); stderr of the server is kept
#              in --stderr-file (default: a mkstemp file under $TMPDIR).
# Dependencies python3 (stdlib only)
# Cross-refs   codegraph_mcp_preflight.sh, codegraph_mcp_runner.py,
#              runner_patches/mcpro1.py, tests/test_mcp_readonly.sh,
#              constitution §11.4.201, §11.4.273, §11.4.107(10)
# ============================================================================
import argparse
import json
import os
import select
import subprocess
import sys
import tempfile
import time


def _die(msg):
    sys.stderr.write("codegraph_mcp_probe: %s\n" % msg)
    sys.exit(2)


def parse_args(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--project", required=True)
    ap.add_argument("--bin", default="codegraph")
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("--tool", default="codegraph_search")
    ap.add_argument("--query", default="compute_total")
    ap.add_argument("--expect", default=None)
    ap.add_argument("--calls", type=int, default=1)
    ap.add_argument("--hold", type=float, default=0.0)
    ap.add_argument("--timeout", type=float, default=90.0)
    ap.add_argument("--stderr-file", default=None)
    ap.add_argument("--list-only", action="store_true")
    ap.add_argument("--extra-arg", action="append", default=[])
    return ap.parse_args(argv)


def db_fd_modes(pid):
    """Access mode of every descriptor of <pid> that points at a codegraph.db."""
    modes = []
    fd_dir = "/proc/%d/fd" % pid
    try:
        names = os.listdir(fd_dir)
    except OSError:
        return modes
    for name in names:
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        if not target.endswith("/codegraph.db"):
            continue
        try:
            with open("/proc/%d/fdinfo/%s" % (pid, name)) as fh:
                for line in fh:
                    if line.startswith("flags:"):
                        flags = int(line.split()[1], 8)
                        modes.append("r" if (flags & 3) == 0 else "rw")
        except (OSError, ValueError):
            continue
    return sorted(modes)


def proc_stat(pid):
    rss = threads = None
    try:
        with open("/proc/%d/status" % pid) as fh:
            for line in fh:
                if line.startswith("VmRSS:"):
                    rss = int(line.split()[1])
                elif line.startswith("Threads:"):
                    threads = int(line.split()[1])
    except (OSError, ValueError):
        pass
    return rss, threads


def main(argv):
    a = parse_args(argv)
    if not os.path.isdir(a.project):
        _die("--project is not a directory: %s" % a.project)
    env = dict(os.environ)
    for kv in a.env:
        if "=" not in kv:
            _die("--env expects K=V, got: %s" % kv)
        k, v = kv.split("=", 1)
        env[k] = v
    if a.stderr_file:
        err_path = a.stderr_file
        err_fh = open(err_path, "wb")
    else:
        fd, err_path = tempfile.mkstemp(prefix="cg_mcp_probe_err.")
        err_fh = os.fdopen(fd, "wb")
    cmd = [a.bin, "serve", "--mcp"] + list(a.extra_arg)
    try:
        proc = subprocess.Popen(cmd, cwd=a.project, env=env, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=err_fh, bufsize=0)
    except OSError as exc:
        print(json.dumps({"init_ok": False, "error": "spawn failed: %s" % exc, "stderr_path": err_path}))
        return 1
    state = {"buf": b""}

    def send(obj):
        proc.stdin.write((json.dumps(obj) + "\n").encode())
        proc.stdin.flush()

    def recv(want_id, timeout):
        end = time.time() + timeout
        while time.time() < end:
            while b"\n" in state["buf"]:
                line, state["buf"] = state["buf"].split(b"\n", 1)
                if not line.strip():
                    continue
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("id") == want_id:
                    return msg
            ready, _, _ = select.select([proc.stdout], [], [], 0.5)
            if ready:
                chunk = os.read(proc.stdout.fileno(), 65536)
                if not chunk:
                    return {"error": "eof"}
                state["buf"] += chunk
        return {"error": "timeout"}

    rep = {"init_ok": False, "calls": a.calls, "calls_ok": 0, "pid": proc.pid, "stderr_path": err_path}
    try:
        root = "file://" + os.path.abspath(a.project)
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {"roots": {}},
            "clientInfo": {"name": "codegraph_mcp_probe", "version": "1"}, "rootUri": root}})
        r = recv(1, a.timeout)
        rep["init_ok"] = "result" in r
        rep["server"] = (r.get("result") or {}).get("serverInfo")
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        r = recv(2, a.timeout)
        rep["tools"] = [t.get("name") for t in (r.get("result") or {}).get("tools", [])]
        if not a.list_only and rep["init_ok"]:
            expect = a.expect if a.expect is not None else a.query
            for i in range(a.calls):
                send({"jsonrpc": "2.0", "id": 10 + i, "method": "tools/call",
                      "params": {"name": a.tool, "arguments": {"query": a.query}}})
                r = recv(10 + i, a.timeout)
                res = r.get("result") or {}
                text = " ".join(c.get("text", "") for c in res.get("content", []))
                rep["last"] = text[:300]
                if expect in text and not res.get("isError"):
                    rep["calls_ok"] += 1
        rep["db_fd_modes"] = db_fd_modes(proc.pid)
        rep["rss_kb"], rep["threads"] = proc_stat(proc.pid)
        if a.hold > 0:
            time.sleep(a.hold)
    finally:
        try:
            proc.stdin.close()
        except OSError:
            pass
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        err_fh.close()
    print(json.dumps(rep))
    if a.list_only:
        return 0 if rep["init_ok"] else 1
    return 0 if (rep["init_ok"] and rep["calls_ok"] == a.calls) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
