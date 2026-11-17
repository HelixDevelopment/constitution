#!/usr/bin/env python3
"""tests/forge/fixtures/forge_fixture_server.py -- loopback fixture HTTP server for the forge tool tests.

CLASS (section 11.4.289(C)(2)): a TEST DOUBLE used only by the gate-logic / unit tests of
scripts/forge/ (tests/forge/test_*.sh). It imitates the answers of a forge API so the tests can
prove how forge.sh DECIDES on a given answer. Nothing it serves is evidence that any real forge
works; the live, read-only proof is scripts/forge/live_probe.sh.

Usage: forge_fixture_server.py SCENARIO.json PORTFILE LOGFILE
  SCENARIO.json  {"routes": {"METHOD /path?query": [RESPONSE, ...]}, "default": RESPONSE}
                 RESPONSE = {"status": 200, "body": <json or string>, "headers": {..}, "delay": SECONDS,
                             "write": {"path": P, "text": T}}  (write: T is written to P before the answer)
                 Responses of a route are served in order; the last one repeats. A route key
                 without "?" also matches a request with a query string when no exact key exists.
  PORTFILE       the chosen port is written here once the socket listens (port 0 = any free port)
  LOGFILE        one JSON line per request: method, path, headers, body (the tests read it)
The server binds 127.0.0.1 only and exits on SIGTERM.
"""
import json
import signal
import time
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

SCEN = json.load(open(sys.argv[1], encoding="utf-8"))
PORTFILE = sys.argv[2]
LOGFILE = sys.argv[3]
COUNTS = {}


def pick(key_full, key_path):
    routes = SCEN.get("routes", {})
    key = key_full if key_full in routes else (key_path if key_path in routes else None)
    if key is None:
        return SCEN.get("default", {"status": 404, "body": {"message": "fixture: no route"}})
    seq = routes[key]
    i = COUNTS.get(key, 0)
    COUNTS[key] = i + 1
    return seq[min(i, len(seq) - 1)]


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def handle_any(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        path_only = self.path.split("?", 1)[0]
        with open(LOGFILE, "a", encoding="utf-8") as f:
            f.write(json.dumps({"method": self.command, "path": self.path,
                                "headers": dict(self.headers.items()), "body": body}) + "\n")
        r = pick(self.command + " " + self.path, self.command + " " + path_only)
        if r.get("write"):
            # a side effect of being served (round 3, review X04): {"path": P, "text": T} writes T to P
            # BEFORE the answer, so a test can change a file while forge.sh is between two requests
            w = r["write"]
            with open(w["path"], "w", encoding="utf-8") as f:
                f.write(w.get("text", ""))
        if r.get("delay"):
            time.sleep(float(r["delay"]))  # a slow answer (the signal-handling tests)
        b = r.get("body", "")
        text = (b if isinstance(b, str) else json.dumps(b))
        # "@SELF@" in a body becomes this server's own origin (for same-origin redirect answers)
        text = text.replace("@SELF@", "http://127.0.0.1:%d" % self.server.server_address[1])
        data = text.encode("utf-8")
        self.send_response(int(r.get("status", 200)))
        hdrs = r.get("headers", {})
        if "Content-Type" not in hdrs:
            self.send_header("Content-Type", "application/json")
        for k, v in hdrs.items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PATCH = do_PUT = do_DELETE = handle_any


def main():
    srv = HTTPServer(("127.0.0.1", 0), H)
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(0))
    with open(PORTFILE + ".tmp", "w", encoding="utf-8") as f:
        f.write(str(srv.server_address[1]))
    import os
    os.replace(PORTFILE + ".tmp", PORTFILE)
    srv.serve_forever()


if __name__ == "__main__":
    main()
