#!/usr/bin/env python3
"""Fixture: stdlib-only Jev/System-One wire-format HTTP server (tests only).

LANGUAGE JUSTIFICATION (design doc section 9): python3 is unavoidable here —
an HTTP fixture server in bash would re-implement a wire protocol for zero
gain; precedent: claude_toolkit's jev_server.py and llmctl's range_server.py.

Implements (per research/jev-ecosystem.md section 1.2 wire format):
  POST /v1/systemone  {model, state, questions{name:{type,instructions,criteria}}}
      -> {model, answers:{name:{type,choice,probabilities,confidence}}, usage, id}
  GET  /v1/models     -> {"data":[{"id":"jev-fixture"}]}
  GET  /healthz       -> {"ok":true}

Deterministic: for `choice` questions picks the first criteria key with
confidence 0.99; `noul` returns noul=1.0; `score` returns score=1.0.
No network access beyond its own listen socket; binds 127.0.0.1 only.
Usage: jev_server.py [port]   (default 18765; port 0 picks a free port and
prints it on stdout line 1 as `PORT <n>`).
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


def answer_for(name, q):
    qtype = q.get("type", "choice")
    criteria = q.get("criteria") or {}
    if qtype == "noul":
        return {"type": "noul", "noul": 1.0}
    if qtype == "score":
        levels = criteria if isinstance(criteria, list) else list(criteria)
        legend = {str(i): str(d) for i, d in enumerate(levels)}
        return {"type": "score", "score": 1.0, "legend": legend,
                "probabilities": {str(i): (1.0 if i == 1 else 0.0)
                                  for i in range(len(levels))},
                "confidence": 0.99}
    # choice (default)
    options = list(criteria.keys()) if isinstance(criteria, dict) else ["yes", "no"]
    if not options:
        options = ["yes", "no"]
    pick = options[0]
    probs = {o: (1.0 if o == pick else 0.0) for o in options}
    return {"type": "choice", "choice": pick, "probabilities": probs,
            "confidence": 0.99}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # silence
        pass

    def do_GET(self):
        if self.path == "/healthz":
            self._send(200, {"ok": True})
        elif self.path == "/v1/models":
            self._send(200, {"data": [{"id": "jev-fixture"}]})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/v1/systemone":
            self._send(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            req = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            self._send(400, {"error": "invalid json"})
            return
        questions = req.get("questions") or {}
        answers = {name: answer_for(name, q) for name, q in questions.items()}
        self._send(200, {
            "model": req.get("model", "jev-fixture"),
            "answers": answers,
            "usage": {"input_tokens": 42, "output_tokens": 7, "cost": 0.0},
            "id": "gen-fixture-0001",
            "provider": "fixture",
        })


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18765
    srv = HTTPServer(("127.0.0.1", port), Handler)
    print(f"PORT {srv.server_address[1]}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
