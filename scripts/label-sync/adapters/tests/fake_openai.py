"""scripts/label-sync/adapters/tests/fake_openai.py

Purpose : Tiny LOCAL OpenAI-compatible chat-completions server used ONLY by
          test_real_agents.sh so a real agent binary (crush, aider) can run a
          real turn without any network or credentials. First request that
          offers tools answers with ONE `ls` tool call (so the agent's
          PreToolUse hook fires); every other request answers "done".
Usage   : python3 -I fake_openai.py        prints the chosen port on stdout, then serves
Inputs  : HTTP on 127.0.0.1:<ephemeral>. Outputs: SSE chat.completion.chunk streams.
Exit    : runs until killed BY ITS STARTER (test_real_agents.sh tracks the pid).
Side-effects: none (no files, loopback only). Deps: python3 stdlib.
Cross-refs: docs/label-sync/ADAPTERS.md, §11.4.18.
Classification: universal (§11.4.17).
"""
import json, sys, http.server, socketserver
calls = {"n": 0}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.send_header("content-type","application/json"); self.end_headers()
        self.wfile.write(json.dumps({"data":[{"id":"fake-model"}]}).encode())
    def do_POST(self):
        n = int(self.headers.get("content-length", 0)); body = json.loads(self.rfile.read(n) or b"{}")
        has_tool_result = any(m.get("role") == "tool" for m in body.get("messages", []))
        self.send_response(200); self.send_header("content-type","text/event-stream"); self.end_headers()
        def chunk(delta, fin=None):
            c = {"id":"c1","object":"chat.completion.chunk","created":1,"model":"fake-model","choices":[{"index":0,"delta":delta,"finish_reason":fin}]}
            self.wfile.write(("data: " + json.dumps(c) + "\n\n").encode()); self.wfile.flush()
        if not has_tool_result and body.get("tools"):
            chunk({"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"ls","arguments":json.dumps({"path":"."})}}]})
            chunk({}, "tool_calls")
        else:
            chunk({"role":"assistant","content":"done"}); chunk({}, "stop")
        self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()
class S(socketserver.ThreadingMixIn, http.server.HTTPServer): daemon_threads = True
s = S(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
