#!/usr/bin/env python3
"""tests/security/fixtures/forge_fixture.py -- loopback forge API fixture for the
security-script tests (gate-logic tests only, §11.4.289: never evidence of a real forge).

Usage: python3 -I forge_fixture.py SCENARIO_JSON REQUEST_LOG PORT_FILE
Binds 127.0.0.1 on a free port, writes the port to PORT_FILE and serves until killed.
SCENARIO_JSON is re-read on every request: {"METHOD /path?query": RESPONSE}, where
RESPONSE is [code, body] or [code, body, {header: value}] or {"seq": [RESPONSE, ...]}
(one per call, the last one repeats). Unknown keys answer 404 {"message":"Not Found"}.
Every request is appended to REQUEST_LOG as one JSON line {k, auth, body, xc}, where xc is the
value of an X-Curlrc header (set only by a test .curlrc, to prove curl ignores it) or "".
"""
import hashlib
import http.server
import json
import sys

SCEN, LOG, PORTF = sys.argv[1], sys.argv[2], sys.argv[3]
COUNT = {}


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _do(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode() if n else ""
        auth = self.headers.get("Authorization") or self.headers.get("PRIVATE-TOKEN") or ""
        xc = self.headers.get("X-Curlrc") or ""
        raw = open(SCEN, "rb").read()
        sc = json.loads(raw)
        key = self.command + " " + self.path
        resp = sc.get(key, [404, {"message": "Not Found"}])
        if isinstance(resp, dict) and "seq" in resp:
            ck = (hashlib.sha256(raw).hexdigest(), key)
            i = COUNT.get(ck, 0)
            COUNT[ck] = i + 1
            resp = resp["seq"][min(i, len(resp["seq"]) - 1)]
        code, out = resp[0], resp[1]
        hdrs = resp[2] if len(resp) > 2 else {}
        with open(LOG, "a") as f:
            f.write(json.dumps({"k": key, "auth": auth, "body": body, "xc": xc}) + "\n")
        b = json.dumps(out).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        for k, v in hdrs.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(b)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = _do


s = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(PORTF, "w") as f:
    f.write(str(s.server_address[1]))
s.serve_forever()
