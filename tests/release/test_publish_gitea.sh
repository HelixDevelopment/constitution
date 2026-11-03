#!/usr/bin/env bash
# UNIT-CLASS test (test doubles: a local Gitea-API stub server and a curl PATH shim, labelled per
# §11.4.289(C)). It proves the script's logic; it is NOT live proof against m3w.org.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
S="${PUBLISH_SCRIPT:-$ROOT/scripts/release_publish_gitea.sh}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d)"; : "${W:?}"; SRV=""
cleanup(){ [ -n "$SRV" ] && kill "$SRV" 2>/dev/null; [ -n "${W:-}" ] && [ -d "$W" ] && { . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }; }
trap cleanup EXIT INT TERM
T="SECRET1234567"
cd "$W" && git init -q repo && cd repo && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m c && git tag rel-1 && git tag rel-2
{ printf '# Changelog\n\n## [vNEXT] — unreleased\nUNRELEASED-MARKER\n\n## rel-2 — x\nNOTES-FOR-REL-2\n\n## rel-1 — y\nNOTES-FOR-REL-1\n'; } > CHANGELOG.md
cat > "$W/stub.py" <<'PY'
import http.server,json,sys
rel={}; log=open(sys.argv[2],'a')
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def _s(self,c,b):
        d=json.dumps(b).encode(); self.send_response(c); self.send_header('Content-Length',str(len(d))); self.end_headers(); self.wfile.write(d)
    def _rec(self,body=None):
        log.write(json.dumps({'m':self.command,'p':self.path,'a':self.headers.get('Authorization'),'b':body})+'\n'); log.flush()
    def _auth(self): 
        if self.headers.get('Authorization')!='token '+sys.argv[3]: self._rec(); self._s(401,{}); return False
        return True
    def do_GET(self):
        if not self._auth(): return
        self._rec(); t=self.path.rsplit('/',1)[-1]
        if self.path.endswith('/force302'): self.send_response(302); self.send_header('Location','http://127.0.0.1:1/x'); self.end_headers(); return
        self._s(200,rel[t]) if t in rel else self._s(404,{})
    def do_POST(self):
        if not self._auth(): return
        b=json.loads(self.rfile.read(int(self.headers['Content-Length']))); self._rec(b)
        if b['tag_name'] in rel and rel[b['tag_name']].get('hidden'): self._s(409,{}); return
        b['id']=len(rel)+1; rel[b['tag_name']]=b; self._s(201,b)
    def do_PATCH(self):
        if not self._auth(): return
        b=json.loads(self.rfile.read(int(self.headers['Content-Length']))); self._rec(b)
        rid=int(self.path.rsplit('/',1)[-1]); 
        for k,v in rel.items():
            if v['id']==rid: v.update(b); self._s(200,v); return
        self._s(404,{})
http.server.HTTPServer(('127.0.0.1',int(sys.argv[1])),H).serve_forever()
PY
LOG="$W/req.log"; : > "$LOG"
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
python3 "$W/stub.py" "$PORT" "$LOG" "$T" & SRV=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 0.3; done
URL="http://127.0.0.1:$PORT"
run(){ timeout 30 env M3W_GITEA_TOKEN="${TOK:-$T}" bash "$S" "$@" </dev/null 2>&1; }
# 1 token handling
out=$(env -u M3W_GITEA_TOKEN timeout 30 bash "$S" --tag rel-1 --base-url "$URL" </dev/null 2>&1); rc=$?
[ $rc -eq 3 ] && echo "$out" | grep -q SKIPPED-NO-TOKEN && ok "missing token -> SKIPPED-NO-TOKEN rc=3" || bad "missing token rc=$rc"
# 2 create with correct section, flags, exact body
out=$(run --tag rel-1 --base-url "$URL" --prerelease --draft); rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q '^CREATED' && ok "create" || bad "create rc=$rc $out"
post=$(grep '"m": "POST"' "$LOG" | tail -1)
echo "$post" | jq -e '.b.body|contains("NOTES-FOR-REL-1") and (contains("NOTES-FOR-REL-2")|not) and (contains("UNRELEASED-MARKER")|not)' >/dev/null && ok "notes = exactly the tag's section (no vNEXT, no other tag)" || bad "wrong notes section: $post"
echo "$post" | jq -e '.b.prerelease==true and .b.draft==true and .b.tag_name=="rel-1"' >/dev/null && ok "flags and tag sent" || bad "flags/tag wrong"
# 3 idempotent update -> PATCH to /releases/<id>, flags cleared (documented last-write-wins), body updated
out=$(run --tag rel-1 --base-url "$URL"); rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q '^UPDATED' && ok "re-run updates" || bad "update rc=$rc $out"
grep '"m": "PATCH"' "$LOG" | tail -1 | jq -e '.p|endswith("/releases/1")' >/dev/null && ok "PATCH goes to /releases/<id>" || bad "PATCH path wrong"
grep '"m": "PATCH"' "$LOG" | tail -1 | jq -e '.b.prerelease==false and .b.draft==false' >/dev/null && ok "flags last-write-wins" || bad "flags not updated"
# 4 auth + leaks
out=$(TOK=WRONGTOKEN123 run --tag rel-1 --base-url "$URL"); rc=$?
[ $rc -eq 4 ] && ok "bad token -> rc=4" || bad "bad token rc=$rc"
echo "$out" | grep -q WRONGTOKEN123 && bad "token leaked in output" || ok "token not echoed (control: server rejected with 401 above)"
# 5 input refusal
bash "$S" --tag 'a;b' </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && ok "unsafe tag refused" || bad "unsafe tag"
bash "$S" --tag nosuchtag --base-url "$URL" </dev/null >/dev/null 2>&1; [ $? -eq 3 ] && ok "missing tag refused" || bad "missing tag"
for u in http://evil.example http://localhost:@example.invalid http://127.0.0.1:1@example.invalid http://127.0.0.1:80/x https://user@host.example; do
  M3W_GITEA_TOKEN=$T bash "$S" --tag rel-1 --base-url "$u" --dry-run </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && ok "base URL refused: $u" || bad "base URL accepted: $u"
done
timeout 5 bash "$S" --tag </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && ok "trailing --tag does not hang (rc 2)" || bad "trailing --tag hang/rc"
timeout 5 bash "$S" --repo </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && ok "trailing --repo does not hang (rc 2)" || bad "trailing --repo hang/rc"
M3W_GITEA_TOKEN=$T bash "$S" --tag rel-1 --repo '../..' --base-url "$URL" --dry-run </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && ok "repo dot segments refused" || bad "repo dot segments"
# 6 hostile token (curl-config injection)
for t in $'abc"\nurl = "http://127.0.0.1:1/INJECTED' 'ab\cd"ef12345' 'short'; do
  (TOK="$t"; run --tag rel-1 --base-url "$URL" >/dev/null; exit $?); [ $? -eq 3 ] && ok "hostile/short token refused" || bad "hostile token accepted"
done
# 7 changelog rules
rm -f CHANGELOG.md; M3W_GITEA_TOKEN=$T bash "$S" --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1; [ $? -eq 3 ] && ok "no changelog -> refused" || bad "no changelog"
printf '## [Unreleased]\nx\n' > CHANGELOG.md
M3W_GITEA_TOKEN=$T bash "$S" --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1; [ $? -eq 3 ] && ok "no matching section -> refused (never publishes Unreleased)" || bad "unreleased published"
out=$(run --tag rel-2 --base-url "$URL" --generic-notes); [ $? -eq 0 ] && grep '"p": "/api/v1/repos/Helix/constitution/releases"' "$LOG" | tail -1 | jq -e '.b.body=="Release rel-2\n"' >/dev/null && ok "--generic-notes" || bad "generic notes"
# 8 large body (argv limit regression: > 128 KiB)
python3 -c 'print("## rel-2 — big"); print("x"*200000)' > CHANGELOG.md
out=$(run --tag rel-2 --base-url "$URL"); [ $? -eq 0 ] && ok "200 KB notes publish (no argv limit)" || bad "big body failed: $out"
grep '"m": "PATCH"' "$LOG" | tail -1 | jq -e '.b.body|length>199000' >/dev/null && ok "big body delivered intact" || bad "big body truncated"
# 9 dry-run
out=$(M3W_GITEA_TOKEN=$T bash "$S" --tag rel-2 --base-url "$URL" --dry-run </dev/null 2>&1); echo "$out" | grep -q "DRY-RUN: would publish rel-2 on $URL/Helix/constitution" && ok "dry-run names the target" || bad "dry-run: $out"
# 10 argv leak + redirect hardening (curl shim = unit-class double; control needle: URL must be recorded)
SH="$W/shim"; mkdir -p "$SH"; cat > "$SH/curl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ARGV_LOG"
printf '404'
SHIM
chmod +x "$SH/curl"; ARGV_LOG="$W/argv.log"; : > "$ARGV_LOG"
printf '## rel-1 — y\nz\n' > CHANGELOG.md
ARGV_LOG="$ARGV_LOG" PATH="$SH:$PATH" M3W_GITEA_TOKEN=$T timeout 30 bash "$S" --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1
grep -q '/api/v1/repos/' "$ARGV_LOG" && ok "argv instrument sees the request (control needle found)" || bad "argv instrument blind"
grep -q "$T" "$ARGV_LOG" && bad "token in curl argv" || ok "token absent from curl argv"
grep -q -- '^-q ' "$ARGV_LOG" && ok "curl runs with -q (no curlrc)" || bad "curl without -q"
grep -q -- '--max-redirs 0' "$ARGV_LOG" && grep -q -- '--proto =http' "$ARGV_LOG" && ok "no redirects, protocol allow-list" || bad "redirect/proto flags missing"
echo "RESULT pass=$pass fail=$fail"; [ $fail -eq 0 ]
