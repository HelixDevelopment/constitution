#!/usr/bin/env python3
"""Minimal Ollama stand-in for tests: /api/tags lists MODEL, /api/embed returns
constant vectors of DIMS, /stats returns request counters.
Usage: fake_ollama.py <port> <model> <dims>
Test-only (unit layer); never used to claim retrieval quality."""
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, MODEL, DIMS = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
VEC = "[" + ",".join(["0.01"] * DIMS) + "]"
STATS = {"requests": 0, "inputs": 0}
LOCK = threading.Lock()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path.startswith("/api/tags"):
            self._send(200, json.dumps({"models": [{"name": MODEL, "model": MODEL}]}))
        elif self.path.startswith("/stats"):
            with LOCK:
                self._send(200, json.dumps(STATS))
        else:
            self._send(200, "Ollama is running")

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        inp = json.loads(raw).get("input", [])
        if isinstance(inp, str):
            inp = [inp]
        with LOCK:
            STATS["requests"] += 1
            STATS["inputs"] += len(inp)
        self._send(200, '{"model":"%s","embeddings":[%s]}' % (MODEL, ",".join([VEC] * len(inp))))


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
