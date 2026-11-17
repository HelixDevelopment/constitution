#!/usr/bin/env bash
# UNIT-CLASS test (test doubles: a local Gitea-API stub server and a curl PATH shim, labelled per
# §11.4.289(C)). It proves the script's logic; it is NOT live proof against m3w.org.
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
# round 6 (K3): the release scripts pass an allow-listed environment to their children; the state-file
# variables of the test doubles are added to that list here (rc_env_lockdown refuses credential-like names).
# Round 11: RELEASE_ENV_KEEP reaches LOCAL children only (jq, sed, ...); the network children (curl, git) run
# through rc_net, whose environment is the fixed network allow-list. A network double therefore reads its state
# from the file .stubenv next to itself (written by stubenv below), never from its environment.
export RELEASE_ENV_KEEP="ARGV_LOG SEEN READY PIDF REC GSEEN GENV ID23"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
S="${PUBLISH_SCRIPT:-$ROOT/scripts/release_publish_gitea.sh}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
. "$HERE/env_allow.sh"   # round 7: the allow-list, the dirty environment and the SIGHUP detector of the L1 L2 L4 cases
skipped=0; skp(){ skipped=$((skipped+1)); echo "SKIP $*"; }
# stubenv DIR NAME=VALUE...: the state file of the doubles in DIR (round 11), one single-quoted assignment per line
stubenv(){ local d="$1" a v q="'"; shift; : >"$d/.stubenv"; for a; do v="${a#*=}"; printf "%s='%s'\n" "${a%%=*}" "${v//$q/$q\\$q$q}" >>"$d/.stubenv"; done; }
HUPWHY="SIGHUP is ignored in this process (nohup or an ignoring parent): bash cannot trap a signal that was ignored when it started, so the case would test the caller's signal state, not the script (round 7, L4)"
case "$(hup_control)" in ok) ok "L4 the SIGHUP detector sees an ignored and a not ignored SIGHUP (control needles)" ;;
  ok-positive-only) ok "L4 the SIGHUP detector sees an ignored SIGHUP (control needle; the negative needle cannot run: SIGHUP is ignored here)" ;;
  *) bad "L4 the SIGHUP detector is blind: $(hup_control)" ;; esac
W="$(mktemp -d)"; : "${W:?}"; SRV=""
cleanup(){ [ -n "$SRV" ] && kill "$SRV" 2>/dev/null; [ -n "${W:-}" ] && [ -d "$W" ] && { . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM   # round 7 (L5): a signal ends the suite (the EXIT trap cleans up); a handler that returns would let the suite run on
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
run(){ timeout 30 env GITEA_LOOPBACK_TEST_TOKEN="${TOK:-$T}" bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN "$@" </dev/null 2>&1; }
# 1 token handling
out=$(env -u GITEA_LOOPBACK_TEST_TOKEN timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null 2>&1); rc=$?
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
GITEA_LOOPBACK_TEST_TOKEN=$T bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag 'a;b' </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && ok "unsafe tag refused" || bad "unsafe tag"
GITEA_LOOPBACK_TEST_TOKEN=$T bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag nosuchtag --base-url "$URL" </dev/null >/dev/null 2>&1; [ $? -eq 3 ] && ok "missing tag refused" || bad "missing tag"
for u in http://evil.example http://localhost:@example.invalid http://127.0.0.1:1@example.invalid http://127.0.0.1:80/x https://user@host.example; do
  GITEA_LOOPBACK_TEST_TOKEN=$T bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$u" --dry-run </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && ok "base URL refused: $u" || bad "base URL accepted: $u"
done
timeout 5 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && ok "trailing --tag does not hang (rc 2)" || bad "trailing --tag hang/rc"
timeout 5 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --repo </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && ok "trailing --repo does not hang (rc 2)" || bad "trailing --repo hang/rc"
GITEA_LOOPBACK_TEST_TOKEN=$T bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --repo '../..' --base-url "$URL" --dry-run </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && ok "repo dot segments refused" || bad "repo dot segments"
# CON-423 review r1 (M8): a token outside the shared shape (rc_gitea_token_shape_ok) is refused before any request
for tk in 'ZZM8 bad!' 'short1' "$(printf 'a%.0s' $(seq 201))"; do
  o8="$(TOK="$tk" run --tag rel-1 --base-url "$URL" --dry-run)"; r8=$?
  [ "$r8" -eq 3 ] && printf '%s\n' "$o8" | grep -q 'token has characters outside' && ! printf '%s\n' "$o8" | grep -q ZZM8 \
    && ok "M8 a token outside the shared shape is refused (${#tk} characters), its value not shown" || bad "M8 a token outside the shared shape is refused (${#tk} characters; rc $r8)"
done
# 6 hostile token (curl-config injection)
for t in $'abc"\nurl = "http://127.0.0.1:1/INJECTED' 'ab\cd"ef12345' 'short'; do
  (TOK="$t"; run --tag rel-1 --base-url "$URL" >/dev/null; exit $?); [ $? -eq 3 ] && ok "hostile/short token refused" || bad "hostile token accepted"
done
# 7 changelog rules
rm -f CHANGELOG.md; GITEA_LOOPBACK_TEST_TOKEN=$T bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1; [ $? -eq 3 ] && ok "no changelog -> refused" || bad "no changelog"
printf '## [Unreleased]\nx\n' > CHANGELOG.md
GITEA_LOOPBACK_TEST_TOKEN=$T bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1; [ $? -eq 3 ] && ok "no matching section -> refused (never publishes Unreleased)" || bad "unreleased published"
out=$(run --tag rel-2 --base-url "$URL" --generic-notes); [ $? -eq 0 ] && grep '"p": "/api/v1/repos/Helix/constitution/releases"' "$LOG" | tail -1 | jq -e '.b.body=="Release rel-2\n"' >/dev/null && ok "--generic-notes" || bad "generic notes"
# 8 large body (argv limit regression: > 128 KiB)
python3 -c 'print("## rel-2 — big"); print("x"*200000)' > CHANGELOG.md
out=$(run --tag rel-2 --base-url "$URL"); [ $? -eq 0 ] && ok "200 KB notes publish (no argv limit)" || bad "big body failed: $out"
grep '"m": "PATCH"' "$LOG" | tail -1 | jq -e '.b.body|length>199000' >/dev/null && ok "big body delivered intact" || bad "big body truncated"
# 9 dry-run
out=$(GITEA_LOOPBACK_TEST_TOKEN=$T bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-2 --base-url "$URL" --dry-run </dev/null 2>&1); echo "$out" | grep -q "DRY-RUN: would publish rel-2 on $URL/Helix/constitution" && ok "dry-run names the target" || bad "dry-run: $out"
# 10 argv leak + redirect hardening (curl shim = unit-class double; control needle: URL must be recorded)
SH="$W/shim"; mkdir -p "$SH"; cat > "$SH/curl" <<'SHIM'
#!/usr/bin/env bash
. "${0%/*}/.stubenv"
printf '%s\n' "$*" >> "$ARGV_LOG"
printf '404'
SHIM
chmod +x "$SH/curl"; ARGV_LOG="$W/argv.log"; : > "$ARGV_LOG"
printf '## rel-1 — y\nz\n' > CHANGELOG.md
stubenv "$SH" ARGV_LOG="$ARGV_LOG"; PATH="$SH:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1
grep -q '/api/v1/repos/' "$ARGV_LOG" && ok "argv instrument sees the request (control needle found)" || bad "argv instrument blind"
grep -q "$T" "$ARGV_LOG" && bad "token in curl argv" || ok "token absent from curl argv"
grep -q -- '^-q ' "$ARGV_LOG" && ok "curl runs with -q (no curlrc)" || bad "curl without -q"
grep -q -- '--max-redirs 0' "$ARGV_LOG" && grep -q -- '--proto =http' "$ARGV_LOG" && ok "no redirects, protocol allow-list" || bad "redirect/proto flags missing"
# 11 (round 5, CON-234 class) curl's stderr is never printed: a curl double that fails with an unredacted URL
# (raw @ in the password) and a second one; the output holds neither secret nor any other byte of curl's message
SH2="$W/shim2"; mkdir -p "$SH2"; cat > "$SH2/curl" <<'SHIM'
#!/usr/bin/env bash
echo "curl: (7) Failed to connect to 'http://u:ZZCURLSECRET@ZZRAWAT@127.0.0.1:1/x' and 'https://v:ZZCURLTWO@h2/y'" >&2
exit 7
SHIM
chmod +x "$SH2/curl"
out=$(PATH="$SH2:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null 2>&1); rc=$?
[ $rc -eq 4 ] && echo "$out" | grep -q 'network/request failure' && ok "curl failure reported (control, rc 4)" || bad "curl failure rc=$rc $out"
echo "$out" | grep -q 'ZZCURLSECRET\|ZZRAWAT\|ZZCURLTWO' && bad "curl stderr: no secret printed" || ok "curl stderr: no secret printed"
echo "$out" | grep -q "network/request failure (curl exit 7, reason class: network-unreachable; curl's own message is withheld" && ok "curl failure: exit status and reason class printed (positive needle)" || bad "curl failure: exit status and class: $out"
echo "$out" | grep -q 'Failed to connect\|h2/y' && bad "curl stderr: no byte of curl's message printed" || ok "curl stderr: no byte of curl's message printed"
# 12 (round 3 G1 class) stderr of other external commands the publisher runs (git here) is redacted when flushed at exit
SH3="$W/shim3"; mkdir -p "$SH3"; REALGIT="$(command -v git)"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = rev-list ] && { echo "warning: https://u:ZZGITSECRET@ZZRAWAT@h.invalid/x" >&2; break; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$SH3/git"; chmod +x "$SH3/git"
out=$(PATH="$SH3:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" --dry-run </dev/null 2>&1); rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q '^DRY-RUN' && ok "git warning does not fail the run (control)" || bad "git warning run rc=$rc $out"
echo "$out" | grep -q 'https://<redacted>@h.invalid' && ok "git stderr flushed redacted (positive needle)" || bad "git stderr flushed redacted"
echo "$out" | grep -q 'ZZGITSECRET\|ZZRAWAT' && bad "git stderr: no secret printed" || ok "git stderr: no secret printed"
# 13 (round 4, H2/H3, Q10) the private run directory is removed after a success, a curl failure and a refusal;
# control needle: a curl double records what TMPDIR holds while the publisher runs
PT="$W/ptmp"; mkdir -p "$PT"; SH4="$W/shim4"; mkdir -p "$SH4"; REALCURL="$(command -v curl)"
cat > "$SH4/curl" <<SHIM
#!/usr/bin/env bash
. "\${0%/*}/.stubenv"
ls -A "\$TMPDIR" >> "\$SEEN"
exec "$REALCURL" "\$@"
SHIM
chmod +x "$SH4/curl"; SEEN="$W/seen"; : > "$SEEN"
printf '## rel-1 — y\nz\n' > CHANGELOG.md
pleft() { find "$PT" -mindepth 1 | wc -l | tr -d ' '; }
stubenv "$SH4" SEEN="$SEEN"; TMPDIR="$PT" PATH="$SH4:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && ok "run dir census: success run (control rc 0)" || bad "run dir census: success rc=$rc"
grep -q '^rpg\.' "$SEEN" && ok "run dir is created under TMPDIR (control needle)" || bad "run dir not seen under TMPDIR (census blind)"
[ "$(pleft)" = 0 ] && ok "nothing left in TMPDIR after a success" || bad "left in TMPDIR after a success: $(pleft)"
TMPDIR="$PT" PATH="$SH2:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1
[ "$(pleft)" = 0 ] && ok "nothing left in TMPDIR after a curl failure (err.out removed)" || bad "left in TMPDIR after a curl failure: $(pleft)"
TMPDIR="$PT" GITEA_LOOPBACK_TEST_TOKEN='bad token!' timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1
[ "$(pleft)" = 0 ] && ok "nothing left in TMPDIR after a refusal" || bad "left in TMPDIR after a refusal: $(pleft)"
# 14 (round 4, H2, Q12; round 5 J6) SIGTERM and SIGHUP while curl writes a credential to stderr: nothing left,
# nothing leaked, and the run ends through the script's own trap with exit status 143 / 129 (python reads the
# exact status; without the trap bash is killed by the signal, which bash's own wait reports the same way)
SH5="$W/shim5"; mkdir -p "$SH5"; cat > "$SH5/curl" <<'SHIM'
#!/usr/bin/env bash
. "${0%/*}/.stubenv"
cat >/dev/null; echo "curl: (7) 'https://u:ZZSIGCURL@h/x'" >&2; : >"${READY:-/dev/null}"; sleep 3; exit 7
SHIM
chmod +x "$SH5/curl"
for sg in TERM:143 HUP:129; do
  if [ "${sg%:*}" = HUP ] && hup_ignored; then skp "14 HUP: $HUPWHY"; continue; fi
  rm -f -- "$W/ready"; stubenv "$SH5" READY="$W/ready"
  src="$(python3 -I - "${sg%%:*}" "$S" "$SH5" "$PT" "$W/ready" "$URL" "$T" "$W/sig.out" <<'PYS'
import os, signal, subprocess, sys, time
sig, s, sh, pt, ready, url, tok, outf = sys.argv[1:9]
env = dict(os.environ, PATH=sh + ":" + os.environ["PATH"], TMPDIR=pt, READY=ready, GITEA_LOOPBACK_TEST_TOKEN=tok)
with open(outf, "wb") as o:
    p = subprocess.Popen(["bash", s, "--token-var", "GITEA_LOOPBACK_TEST_TOKEN", "--tag", "rel-1", "--base-url", url], env=env, stdin=subprocess.DEVNULL, stdout=o, stderr=o)
    for _ in range(200):
        if os.path.exists(ready): break
        time.sleep(0.1)
    p.send_signal(getattr(signal, "SIG" + sig))
    print(p.wait(timeout=60))
PYS
)"
  [ "$src" = "${sg#*:}" ] && ok "${sg%%:*}: the publisher ends through its trap (rc $src)" || bad "${sg%%:*}: the publisher rc $src, want ${sg#*:}"
  [ "$(pleft)" = 0 ] && ok "${sg%%:*}: nothing left in TMPDIR" || bad "${sg%%:*}: left in TMPDIR: $(pleft)"
  grep -q ZZSIGCURL "$W/sig.out" && bad "${sg%%:*}: secret printed" || ok "${sg%%:*}: no secret printed"
done
# 15 (round 4, I-4) a non-numeric release id returned by the server is refused, never printed
SH6="$W/shim6"; mkdir -p "$SH6"; cat > "$SH6/curl" <<'SHIM'
#!/usr/bin/env bash
o=""; m=GET; p=""; for a in "$@"; do [ "$p" = -o ] && o="$a"; [ "$p" = -X ] && m="$a"; p="$a"; done
if [ "$m" = POST ]; then printf '{"id":"ZZEVILID\u001b[2J"}' >"$o"; printf 201; else printf '{}' >"$o"; printf 404; fi
SHIM
chmod +x "$SH6/curl"
out=$(PATH="$SH6:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null 2>&1); rc=$?
[ $rc -eq 4 ] && ok "non-numeric created id refused (rc 4)" || bad "non-numeric created id rc=$rc $out"
echo "$out" | grep -q ZZEVILID && bad "server-controlled id printed" || ok "server-controlled id not printed"
# 16 (round 4, I-2) an Authorization header line in curl's stderr is redacted
SH7="$W/shim7"; mkdir -p "$SH7"; cat > "$SH7/curl" <<'SHIM'
#!/usr/bin/env bash
echo "> Authorization: token ZZHDRSECRET" >&2; exit 7
SHIM
chmod +x "$SH7/curl"
out=$(PATH="$SH7:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null 2>&1)
echo "$out" | grep -q ZZHDRSECRET && bad "Authorization header value printed" || ok "Authorization header value not printed"
echo "$out" | grep -q 'network/request failure (curl exit 7, reason class: ' && ok "the failure is reported by exit status and class (positive needle)" || bad "curl failure not reported: $out"
echo "$out" | grep -q 'Authorization' && bad "no byte of the header line is printed" || ok "no byte of the header line is printed"

# ---- round 5 (structural, CON-234 class) ----
# 17 (J4) the token reaches curl on its standard input (-K -), never in a file: the curl double records its argv and
# its stdin, and lists every file under TMPDIR while it runs. Control needles: the token IS in the recorded stdin.
SH8="$W/shim8"; mkdir -p "$SH8"; PT8="$W/ptmp8"; mkdir -p "$PT8"; REC="$W/rec8"; mkdir -p "$REC"
cat > "$SH8/curl" <<'SHIM'
#!/usr/bin/env bash
. "${0%/*}/.stubenv"
printf '%s\n' "$*" >>"$REC/argv"; cat >>"$REC/stdin"; find "$TMPDIR" -type f -exec cat {} + >>"$REC/tmpfiles" 2>/dev/null
for d in "$TMPDIR"/rpg.*; do [ -d "$d" ] && stat -c %a "$d" >>"$REC/mode"; done
env >>"$REC/env"
o=""; p=""; for a in "$@"; do [ "$p" = -o ] && o="$a"; p="$a"; done; printf '{}' >"$o"; printf 404
SHIM
chmod +x "$SH8/curl"; : >"$REC/tmpfiles"
printf '## rel-1 — y\nz\n' > CHANGELOG.md
stubenv "$SH8" REC="$REC"; TMPDIR="$PT8" PATH="$SH8:$PATH" TOKEN=unrelated-caller-value GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1
grep -q -- ' -K - ' "$REC/argv" && ok "curl reads its config from stdin (-K -)" || bad "curl does not read -K -: $(head -1 "$REC/argv")"
grep -q "Authorization: token $T" "$REC/stdin" && ok "the token reaches curl on stdin (control needle)" || bad "the token is not on curl's stdin (instrument blind)"
[ -s "$REC/tmpfiles" ] && ok "the TMPDIR census read files during the run (control needle)" || bad "the TMPDIR census is blind"
grep -q "$T" "$REC/tmpfiles" && bad "the token is in a file under TMPDIR while curl runs" || ok "no file under TMPDIR holds the token while curl runs"
grep -q '^PATH=' "$REC/env" && ok "the environment census of curl works (control needle)" || bad "the environment census is blind"
grep -q "$T" "$REC/env" && bad "the token is in curl's environment (a caller's exported TOKEN must not carry it)" || ok "the token is not in curl's environment, even with a caller TOKEN exported"
[ -s "$REC/mode" ] && ok "the run directory mode is read during the run (control needle)" || bad "the run directory mode census is blind"
grep -vqx 700 "$REC/mode" && bad "the run directory is mode 700 (V13): $(sort -u "$REC/mode" | tr '\n' ' ')" || ok "the run directory is mode 700 (V13)"
grep -q -- '--connect-timeout ' "$REC/argv" && grep -q -- ' -m 60 ' "$REC/argv" && ok "curl runs with a connect timeout and a total timeout (J5)" || bad "curl timeouts missing"
# 18 (J4) SIGKILL of the publisher while curl runs leaves no file that holds the token
SH9="$W/shim9"; mkdir -p "$SH9"; PT9="$W/ptmp9"; mkdir -p "$PT9"
cat > "$SH9/curl" <<'SHIM'
#!/usr/bin/env bash
. "${0%/*}/.stubenv"
cat >/dev/null; printf '%s' "$$" >"$PIDF"; : >"$READY"; exec sleep 20   # the recorded pid is the sleep itself
SHIM
chmod +x "$SH9/curl"; rm -f -- "$W/ready9" "$W/pid9"
stubenv "$SH9" READY="$W/ready9" PIDF="$W/pid9"
( TMPDIR="$PT9" PATH="$SH9:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T exec bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null ) >/dev/null 2>&1 &
kp=$!; i=0; while [ ! -e "$W/ready9" ] && [ $i -lt 200 ]; do sleep 0.1; i=$((i+1)); done
[ "$kp" -gt 1 ] && kill -s KILL "$kp"; wait "$kp" 2>/dev/null
cp9="$(cat "$W/pid9" 2>/dev/null)"; case "$cp9" in ''|*[!0-9]*) cp9=0 ;; esac
[ "$cp9" -gt 1 ] && kill "$cp9" 2>/dev/null   # the curl double this test started (its own recorded pid)
[ -n "$(find "$PT9" -mindepth 1 -maxdepth 1 -name 'rpg.*')" ] && ok "SIGKILL leaves the run directory behind (control needle)" || bad "SIGKILL: no run directory seen (census blind)"
grep -rq "$T" "$PT9" && bad "SIGKILL: a file under TMPDIR holds the token" || ok "SIGKILL: no file under TMPDIR holds the token"
# 19 (V12) the publisher's git runs with GIT_TRACE_REDACT=1 and GIT_TERMINAL_PROMPT=0 whatever the caller set, and
# with no GIT_TRACE* variable of the caller
SH10="$W/shim10"; mkdir -p "$SH10"
printf '#!/bin/sh\n. "${0%%/*}/.stubenv"\nfor a in "$@"; do [ "$a" = rev-list ] && { echo "redact=$GIT_TRACE_REDACT prompt=$GIT_TERMINAL_PROMPT trace=${GIT_TRACE:-unset}" >>"$GSEEN"; env >>"$GENV"; break; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$SH10/git"; chmod +x "$SH10/git"
GSEEN="$W/gseen"; : >"$GSEEN"; GENV="$W/genv"; : >"$GENV"
stubenv "$SH10" GSEEN="$GSEEN" GENV="$GENV"; TOKEN=unrelated-caller-value GIT_TRACE_REDACT=0 GIT_TERMINAL_PROMPT=1 GIT_TRACE=1 PATH="$SH10:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" --dry-run </dev/null >/dev/null 2>&1
grep -q '^PATH=' "$GENV" && ok "the environment census of git works (control needle)" || bad "the git environment census is blind"
grep -q "$T" "$GENV" && bad "the token is in git's environment (a caller's exported TOKEN must not carry it)" || ok "the token is not in git's environment, even with a caller TOKEN exported"
grep -q '^redact=' "$GSEEN" && ok "the git environment census saw rev-list (control needle)" || bad "the git environment census is blind"
grep -qx 'redact=1 prompt=0 trace=unset' "$GSEEN" && ok "git runs with GIT_TRACE_REDACT=1, GIT_TERMINAL_PROMPT=0 and no GIT_TRACE" || bad "git environment: $(cat "$GSEEN")"
# 20 caller values that can hold a credential are not echoed
out=$(run --tag rel-1 '--https://u:ZZPARG@h/x'); rc=$?
[ $rc -eq 2 ] && ok "credential-shaped unknown argument: usage (rc 2)" || bad "unknown argument rc=$rc"
echo "$out" | grep -q ZZPARG && bad "the unknown argument is echoed" || ok "the unknown argument is not echoed"
out=$(run --tag rel-1 --frobnicate); echo "$out" | grep -q 'unknown argument: --frobnicate' && ok "an option-shaped unknown argument is named (control)" || bad "option-shaped argument not named: $out"
out=$(run --tag rel-1 --base-url "$URL" --notes-file '/nonexistent/https://u:ZZPNOTE@h'); rc=$?
[ $rc -eq 3 ] && echo "$out" | grep -q 'notes file is not readable' && ok "unreadable notes file refused (control, rc 3)" || bad "notes file rc=$rc $out"
echo "$out" | grep -q ZZPNOTE && bad "the notes path is echoed" || ok "the notes path is not echoed"
out=$(run --tag rel-1 --base-url 'https://u:ZZPURL@h'); rc=$?
[ $rc -eq 2 ] && ok "a base URL with userinfo is refused (rc 2)" || bad "userinfo base URL rc=$rc"
echo "$out" | grep -q ZZPURL && bad "the bad base URL is echoed" || ok "the bad base URL is not echoed"
# 21 (J5) a curl timeout is reported as the class "timeout"
SH11="$W/shim11"; mkdir -p "$SH11"; printf '#!/bin/sh\ncat >/dev/null; echo "curl: (28) Operation timed out https://u:ZZTO@h" >&2; exit 28\n' >"$SH11/curl"; chmod +x "$SH11/curl"
out=$(PATH="$SH11:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null 2>&1); rc=$?
[ $rc -eq 4 ] && echo "$out" | grep -q 'curl exit 28, reason class: timeout' && ok "curl timeout reported with the class timeout (rc 4)" || bad "curl timeout: rc=$rc $out"
echo "$out" | grep -q ZZTO && bad "curl timeout: message printed" || ok "curl timeout: message not printed"
# 22 a non-numeric HTTP status from curl's -w is refused, never printed
# (the double writes the response body file, so the run reaches the status check and not an earlier failure)
SH12="$W/shim12"; mkdir -p "$SH12"; cat > "$SH12/curl" <<'SHIM'
#!/usr/bin/env bash
cat >/dev/null; o=""; p=""; for a in "$@"; do [ "$p" = -o ] && o="$a"; p="$a"; done; printf '{}' >"$o"; printf 'ZZCODE'
SHIM
chmod +x "$SH12/curl"
out=$(PATH="$SH12:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null 2>&1); rc=$?
[ $rc -eq 4 ] && ok "a non-numeric HTTP status is a failure (rc 4)" || bad "non-numeric status rc=$rc $out"
echo "$out" | grep -q ZZCODE && bad "the non-numeric status is printed" || ok "the non-numeric status is not printed"
# ---- round 6 (structural; reviewer mutants X6, X12, X13, X14 and K3) ----
# 23 (X6) a release id read back by GET that is not one line of digits is refused before the PATCH; it is never
# printed. The curl double records the method of every request (control needle: the GET is recorded).
SH13="$W/shim13"; mkdir -p "$SH13"; cat > "$SH13/curl" <<'SHIM'
#!/bin/sh
. "${0%/*}/.stubenv"
cat >/dev/null; o=""; m=GET; p=""; for a in "$@"; do [ "$p" = -o ] && o="$a"; [ "$p" = -X ] && m="$a"; p="$a"; done
echo "$m" >>"$SEEN"
if [ "$m" = GET ]; then printf '%s' "$ID23" >"$o"; printf 200; else printf '{}' >"$o"; printf 200; fi
SHIM
chmod +x "$SH13/curl"
for id in '{"id":"7\nZZEVILID23"}' '{"id":"ZZEVILID23"}' '{"id":7.5}'; do
  SEEN="$W/seen13"; : >"$SEEN"
  stubenv "$SH13" ID23="$id" SEEN="$SEEN"; out=$(PATH="$SH13:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null 2>&1); rc=$?
  grep -qx GET "$SEEN" && ok "X6 $id: the GET is recorded (control needle)" || bad "X6 $id: census blind"
  [ $rc -eq 4 ] && ok "X6 $id: a bad release id is refused (rc 4)" || bad "X6 $id: rc=$rc $out"
  grep -qx PATCH "$SEEN" && bad "X6 $id: a PATCH was sent with a bad id" || ok "X6 $id: no PATCH is sent"
  echo "$out" | grep -q ZZEVILID23 && bad "X6 $id: the id is printed" || ok "X6 $id: the id is not printed"
done
# 24 (X14) an inherited xtrace (bash -x, SHELLOPTS=xtrace) traces at most the first line and never the token
printf '## rel-1 — y\nz\n' > CHANGELOG.md
# round 7: the SHELLOPTS run goes through env(1): a prefix assignment "SHELLOPTS=xtrace cmd" fails (SHELLOPTS is
# read-only in bash) and the command then runs WITHOUT xtrace, so that form tested nothing (found in round 7).
# Control: env SHELLOPTS=xtrace does trace a two-command bash.
[ "$(env SHELLOPTS=xtrace bash -c 'true; true' 2>&1 | grep -c '^+')" -ge 2 ] && ok "xtrace control: env SHELLOPTS=xtrace traces (instrument sees trace lines)" || bad "xtrace control: env SHELLOPTS=xtrace does not trace"
for how in bashx shellopts; do
  if [ "$how" = bashx ]; then out=$(GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash -x "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" --dry-run </dev/null 2>&1)
  else out=$(env SHELLOPTS=xtrace GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" --dry-run </dev/null 2>&1); fi
  echo "$out" | grep -q '^DRY-RUN' && ok "xtrace $how: the run completes (control)" || bad "xtrace $how: $out"
  n=$(printf '%s\n' "$out" | grep -c '^+')
  [ "$n" -le 1 ] && ok "xtrace $how: at most one trace line ($n)" || bad "xtrace $how: $n trace lines"
  echo "$out" | grep -q "$T" && bad "xtrace $how: the token is printed" || ok "xtrace $how: the token is not printed"
done
# 25 (K3, X12) a caller's exported _rpg_tok, *TOKEN*, BASH_ENV and the token itself reach no child the publisher
# runs (curl, git, jq): the doubles are sh scripts that record their environment (control needle: PATH recorded)
SH14="$W/shim14"; mkdir -p "$SH14"; E14="$W/env14"; : >"$E14"
for c in curl git jq; do
  real="$(command -v "$c")"
  printf '#!/bin/sh\n{ echo "== %s"; env; } >>"%s"\nexec "%s" "$@"\n' "$c" "$E14" "$real" >"$SH14/$c"; chmod +x "$SH14/$c"
done
printf 'echo ZZBASHENV25 >/dev/null\n' >"$W/bashenv25"
_rpg_tok=ZZCALLERRPG25 XYZ_TOKEN=ZZXYZ25 GH_TOKEN=ZZGH25 BASH_ENV="$W/bashenv25" PATH="$SH14:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T M3W_GITEA_TOKEN=ZZM3W25ENV \
  timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1
for c in curl git jq; do grep -qx "== $c" "$E14" && ok "K3: $c environment recorded (control needle)" || bad "K3: $c environment census blind"; done
grep -q '^PATH=' "$E14" && ok "K3: the environment census reads PATH (control needle)" || bad "K3: env census blind"
for v in "$T" ZZCALLERRPG25 ZZXYZ25 ZZGH25 '^BASH_ENV=' '^_rpg_tok=' '^GITEA_LOOPBACK_TEST_TOKEN=' ZZM3W25ENV '^M3W_GITEA_TOKEN='; do
  grep -q -- "$v" "$E14" && bad "K3: a child holds $v in its environment" || ok "K3: no child holds $v in its environment"
done
# 26 (X13) the run directory has a fresh random name per run: two runs, two different names of the form rpg.XXXXXX
SH15="$W/shim15"; mkdir -p "$SH15"; PT15="$W/ptmp15"; mkdir -p "$PT15"; N15="$W/names15"; : >"$N15"
printf '#!/bin/sh\nls -A "$TMPDIR" >>"%s"\nexec "%s" "$@"\n' "$N15" "$REALCURL" >"$SH15/curl"; chmod +x "$SH15/curl"
for _ in 1 2; do TMPDIR="$PT15" PATH="$SH15:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1; done
nn=$(sort -u "$N15" | grep -c .)
[ "$nn" -ge 1 ] && ok "X13: run directory names recorded (control needle, $nn)" || bad "X13: name census blind"
[ "$nn" -eq 2 ] && ok "X13: two runs use two different run directory names" || bad "X13: names: $(sort -u "$N15" | tr '\n' ' ')"
grep -vqE '^rpg\.[A-Za-z0-9]{6}$' "$N15" && bad "X13: a run directory name is not rpg.XXXXXX: $(sort -u "$N15" | tr '\n' ' ')" || ok "X13: every run directory name is rpg.XXXXXX"
# 27 (round 6) a created id that is not one line of digits (a newline inside) is refused and never printed
SH16="$W/shim16"; mkdir -p "$SH16"; cat > "$SH16/curl" <<'SHIM'
#!/bin/sh
cat >/dev/null; o=""; m=GET; p=""; for a in "$@"; do [ "$p" = -o ] && o="$a"; [ "$p" = -X ] && m="$a"; p="$a"; done
if [ "$m" = POST ]; then printf '{"id":"7\\nZZEVILNEW27"}' >"$o"; printf 201; else printf '{}' >"$o"; printf 404; fi
SHIM
chmod +x "$SH16/curl"
out=$(PATH="$SH16:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null 2>&1); rc=$?
[ $rc -eq 4 ] && ok "27: a multi-line created id is refused (rc 4)" || bad "27: multi-line created id rc=$rc $out"
echo "$out" | grep -q ZZEVILNEW27 && bad "27: the created id is printed" || ok "27: the created id is not printed"
# 28 (round 6, X11) --token-var may name a variable that is on the rc_env_lockdown allow-list (GH_HOST here), which
# the lockdown leaves exported; the publisher reads and unsets it before its first external command, so no child
# gets the token through that name. Every command of the channel table gets a recorder (class-exhaustive), and
# the run is repeated with --help (the help text is printed by sed after the unset).
SH28="$W/shim28"; mkdir -p "$SH28"; E28="$W/env28"; : >"$E28"; ENVB="$(command -v env)"
TOB="$(command -v timeout)"; BASHB="$(command -v bash)"   # the test's own timeout and bash are not recorded (they get the caller env)
while IFS= read -r c; do
  real="$(command -v "$c" 2>/dev/null)" || continue
  printf '#!/bin/sh
{ echo "== %s"; "%s"; } >>"%s"
exec "%s" "$@"
' "$c" "$ENVB" "$E28" "$real" >"$SH28/$c"; chmod +x "$SH28/$c"
done < <(python3 -I "$HERE/channel_census.py" commands "$HERE/channels.tsv")
# B-M2 (2026-11-16): GH_HOST is bound to no host in config/forge/hosts.tsv, so the publish run is now refused
# (exit 2) before any child; the --help run still reads and unsets the variable before its sed. The curl and grep
# needles of the old publish run cannot fire any more (no child runs), so only sed is a needle here.
GH_HOST=$T PATH="$SH28:$PATH" "$TOB" 30 "$BASHB" "$S" --tag rel-1 --base-url "$URL" --token-var GH_HOST </dev/null >/dev/null 2>&1; r28=$?
[ "$r28" -eq 2 ] && ok "28 B-M2: --token-var GH_HOST is bound to no host: refused, exit 2" || bad "28 B-M2: --token-var GH_HOST rc $r28 (want 2)"
GH_HOST=$T PATH="$SH28:$PATH" "$TOB" 30 "$BASHB" "$S" --token-var GH_HOST --help </dev/null >/dev/null 2>&1
for c in sed; do grep -qx "== $c" "$E28" && ok "28: the $c environment is recorded (control needle)" || bad "28: $c env census blind"; done
grep -q -- "$T" "$E28" && bad "28 X11: a child holds the token of an allow-listed --token-var ($(awk -v t="$T" '/^== /{c=$0} index($0,t){print c; exit}' "$E28"))" || ok "28 X11: no child holds the token of an allow-listed --token-var"
# 29 (round 7, L1 L2) the child environment is built POSITIVELY: nothing outside the allow-list reaches any child,
# also entries whose names are not shell identifiers (BAD-NAME=, A.TOKEN=, npm_config_//host/:_authToken=), and also
# under an inherited allexport (SHELLOPTS=allexport, bash -a), which would export the token holder _rpg_tok. Every
# command of the channel table gets a recorder that reads its OWN /proc/$$/environ (env would not list the
# non-identifier names). Control needles: the recorder sees a non-identifier name when one is passed to it; the
# census checks the curl, git and jq records.
SH29="$W/shim29"; mkdir -p "$SH29"; E29="$W/env29"; : >"$E29"
# shellcheck disable=SC2046   # one argument per command name, split on purpose
python3 -I "$HERE/env_census.py" mk "$SH29" "$E29" $(python3 -I "$HERE/channel_census.py" commands "$HERE/channels.tsv") >/dev/null
TOB="$(command -v timeout)"; BASHB="$(command -v bash)"   # absolute: the suite's own timeout and bash are not recorded
env -i "${ENV_DIRTY[@]}" PATH="$SH29:$PATH" "$BASHB" -c 'jq --version >/dev/null; :' </dev/null >/dev/null 2>&1 7</dev/null
o29="$(python3 -I "$HERE/env_census.py" check "$E29" --allow $ENV_ALLOW $RELEASE_ENV_KEEP --parent bash)"
printf '%s\n' "$o29" | grep -q "^FINDING jq: 'LC_ZZTOKEN' is not on the allow-list" && ok "29 (N1): LC_ZZTOKEN is a finding, no name prefix (control needle)" || bad "29 (N1): LC_ZZTOKEN not seen: $o29"
printf '%s\n' "$o29" | grep -q "^FINDING jq: file descriptor 7 is inherited" && ok "29 (N3): an inherited descriptor is a finding (control needle)" || bad "29 (N3): the descriptor census is blind"
{ printf '%s\n' "$o29" | grep -q "^FINDING jq: 'BAD-NAME' is not on the allow-list" && printf '%s\n' "$o29" | grep -q "^FINDING jq: 'npm_config_//h.invalid/:_authToken' is not on the allow-list"; } \
  && ok "29: the recorder sees non-identifier names (control needle)" || bad "29: the recorder is blind to non-identifier names: $o29"
: >"$E29"
for how in shellopts bash-a; do
  if [ "$how" = shellopts ]; then env "${ENV_DIRTY[@]}" SHELLOPTS=allexport PATH="$SH29:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T "$TOB" 30 "$BASHB" "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1 7</dev/null; r29=$?
  else env "${ENV_DIRTY[@]}" PATH="$SH29:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T "$TOB" 30 "$BASHB" -a "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1 7</dev/null; r29=$?; fi
  [ "$r29" -eq 0 ] && ok "29 $how: the publisher run completes (control, rc 0)" || bad "29 $how: the publisher rc $r29"
done
for c in curl git jq; do grep -qx "== $c" "$E29" && ok "29: the $c environment is recorded (control needle)" || bad "29: $c env census blind"; done
o29="$(python3 -I "$HERE/env_census.py" check "$E29" --allow $ENV_ALLOW $RELEASE_ENV_KEEP --allow-fd 3 --marker "$T" $ENV_MARKERS --min 6)"; r29=$?
[ "$r29" -eq 0 ] && ok "29 L1 L2: no child has a name outside the allow-list or a marker ($(printf '%s\n' "$o29" | tail -n 1))" || bad "29 L1 L2: $(printf '%s\n' "$o29" | head -n 4 | tr '\n' ' ')"
# 29c (round 11, R10-1 and R10-4 of the round-10 review): the network children (curl, git) get the network allow-list
# only: no RELEASE_ENV_KEEP name (also the credential-shaped names the round-10 word filter kept: GITEA_PAT, NPM_PAT,
# DATABASE_DSN, SLACK_WEBHOOK, X_PRIVATE, CLIENT_CERT, SIGNING_SALT, HMAC, OTP), no locale, account or terminal name
# of the caller. Control needles: a LOCAL child (jq) still gets the RELEASE_ENV_KEEP name SEEN and LANG.
K29="SEEN GITEA_PAT NPM_PAT DATABASE_DSN SLACK_WEBHOOK X_PRIVATE CLIENT_CERT SIGNING_SALT HMAC OTP"
: >"$E29"
# shellcheck disable=SC2046   # one NAME=VALUE argument per name, split on purpose
env "${ENV_DIRTY[@]}" $(for n in $K29; do printf '%s=ZZFAKE-%s-11 ' "$n" "$n"; done) LANG=C.UTF-8 USER=zzk11 TERM=xterm \
  RELEASE_ENV_KEEP="$RELEASE_ENV_KEEP $K29" PATH="$SH29:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T "$TOB" 30 "$BASHB" "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1 7</dev/null; r29=$?
[ "$r29" -eq 0 ] && ok "29c the publisher run completes (control, rc 0)" || bad "29c the publisher rc $r29"
o29="$(python3 -I "$HERE/env_census.py" check "$E29" --cmd curl git --allow $NET_ALLOW --allow-fd 3 --marker "$T" ZZFAKE- zzk11 $ENV_MARKERS --min 2)"; r29=$?
[ "$r29" -eq 0 ] && ok "29c no network child has a name outside the network allow-list ($(printf '%s\n' "$o29" | tail -n 1))" || bad "29c network child: $(printf '%s\n' "$o29" | grep FINDING | sort -u | head -n 6 | tr '\n' ' ')"
for n in $K29 LANG USER TERM; do grep -q "^E $n=" <(awk '/^== /{c=$2} c=="curl"||c=="git"' "$E29") && bad "29c a network child holds $n" || ok "29c no network child holds $n"; done
awk '/^== /{c=$2} c=="jq"' "$E29" | grep -q '^E SEEN=ZZFAKE-SEEN-11$' && ok "29c a local child (jq) keeps the RELEASE_ENV_KEEP name SEEN (control needle)" || bad "29c the local-child census is blind (SEEN)"
awk '/^== /{c=$2} c=="jq"' "$E29" | grep -q '^E LANG=C.UTF-8$' && ok "29c a local child (jq) keeps LANG (control needle)" || bad "29c the local-child census is blind (LANG)"
awk '/^== /{c=$2} c=="curl"' "$E29" | grep -q '^E LC_ALL=C$' && ok "29c the network child curl has LC_ALL=C (control needle)" || bad "29c the network-child census is blind (LC_ALL)"
# 29b (round 9, F1 F2 of the round-8 review): inherited descriptors of 3, 5 and 6 digits (300, 12345, 100000) reach
# no child of the publisher. Control needle: the census lists all of them for a plain bash child.
if nofile_room; then
  : >"$E29"; env -i PATH="$SH29:$PATH" "$BASHB" -c 'jq --version >/dev/null; :' </dev/null >/dev/null 2>&1 7</dev/null 300</dev/null 12345</dev/null 100000</dev/null
  o29="$(python3 -I "$HERE/env_census.py" check "$E29" --parent bash --allow PATH PWD SHLVL _)"
  for d in 7 300 12345 100000; do case "$o29" in *"file descriptor $d is inherited"*) ok "29b control: descriptor $d is a finding for a plain child" ;; *) bad "29b control: descriptor $d not seen by the census" ;; esac; done
  : >"$E29"; env PATH="$SH29:$PATH" GITEA_LOOPBACK_TEST_TOKEN=$T "$TOB" 30 "$BASHB" "$S" --token-var GITEA_LOOPBACK_TEST_TOKEN --tag rel-1 --base-url "$URL" </dev/null >/dev/null 2>&1 7</dev/null 300</dev/null 12345</dev/null 100000</dev/null; r29=$?
  [ "$r29" -eq 0 ] && ok "29b the publisher run with descriptors 7 300 12345 100000 completes (rc 0)" || bad "29b the publisher rc $r29"
  for c in curl jq; do grep -qx "== $c" "$E29" && ok "29b the $c record is made (control needle)" || bad "29b $c census blind"; done
  o29="$(python3 -I "$HERE/env_census.py" check "$E29" --allow $ENV_ALLOW $RELEASE_ENV_KEEP --allow-fd 3 --marker "$T" --min 3)"; r29=$?
  [ "$r29" -eq 0 ] && ok "29b no child of the publisher inherits a descriptor of 1, 3, 5 or 6 digits ($(printf '%s\n' "$o29" | tail -n 1))" || bad "29b F1: $(printf '%s\n' "$o29" | grep FINDING | sort -u | head -n 4 | tr '\n' ' ')"
else skp "29b descriptors of 5 and 6 digits: $NOFILE_WHY"; fi
# 30 (round 7, L1 L2) --token-var names a caller variable that is NOT on the allow-list: the first rc_env_clean
# carries its value across the re-execution as a plain shell variable (the argument prescan names it in READS),
# so the token is found and the publish goes ahead (rc 0); without the prescan the re-executed publisher would
# report SKIPPED-NO-TOKEN.
# B-M2: the variable is GITEA_LOOPBACK_TEST_TOKEN (the one name a loopback URL is bound to; it is not on the
# allow-list either, so the case still needs the prescan).
out=$(env -u M3W_GITEA_TOKEN GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --tag rel-1 --base-url "$URL" --token-var GITEA_LOOPBACK_TEST_TOKEN </dev/null 2>&1); rc=$?
{ [ $rc -eq 0 ] && ! printf '%s\n' "$out" | grep -q SKIPPED-NO-TOKEN; } && ok "30 --token-var GITEA_LOOPBACK_TEST_TOKEN: the token crosses the re-execution (rc 0)" || bad "30 --token-var GITEA_LOOPBACK_TEST_TOKEN: rc $rc $(printf '%s\n' "$out" | tail -n 1)"
printf '%s\n' "$out" | grep -q "$T" && bad "30 the token is printed" || ok "30 the token is not printed"
# 31 (round 7) --token-var naming a variable bash gives a meaning of its own (BASH_ENV, SHELLOPTS, IFS) is refused
# with exit 2 before anything runs
for tv in BASH_ENV SHELLOPTS IFS; do
  out=$(GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --tag rel-1 --base-url "$URL" --token-var "$tv" </dev/null 2>&1); rc=$?
  { [ $rc -eq 2 ] && printf '%s\n' "$out" | grep -q 'bash gives a meaning of its own'; } && ok "31 --token-var $tv: refused, exit 2" || bad "31 --token-var $tv: rc $rc $(printf '%s\n' "$out" | tail -n 1)"
done
# B-M2 (2026-11-16): --token-var is required and the variable must be bound to the --base-url host in
# config/forge/hosts.tsv; every refusal comes before any network call (a curl shim on PATH counts the calls and
# the stub server logs every request with its Authorization header). Token values are fixture strings. The shim
# never runs the real curl (it records the call and exits 7), so a refusal that comes too late reaches no real host.
SHB="$W/shimbm2"; mkdir -p "$SHB"; CB="$W/curlbm2"; : >"$CB"
printf '#!/bin/sh\necho call >>"%s"\nexit 7\n' "$CB" >"$SHB/curl"; chmod +x "$SHB/curl"
bm2(){ # bm2 NAME WANT-RC WANT-TEXT ARGS... (the token variables are set by the caller)
  local nm="$1" want="$2" txt="$3" l0 o r; shift 3; l0="$(wc -l <"$LOG")"; : >"$CB"
  o="$(PATH="$SHB:$PATH" timeout 30 bash "$S" "$@" </dev/null 2>&1)"; r=$?
  [ "$r" -eq "$want" ] && ok "B-M2 $nm: exit $want" || bad "B-M2 $nm: rc $r (want $want): $(printf '%s\n' "$o" | tail -n 1)"
  [ -z "$txt" ] || { printf '%s\n' "$o" | grep -qF -- "$txt" && ok "B-M2 $nm: says '$txt'" || bad "B-M2 $nm: no '$txt' in: $(printf '%s\n' "$o" | tail -n 1)"; }
  if [ "$want" -ne 0 ]; then
    [ -s "$CB" ] && bad "B-M2 $nm: curl ran before the refusal" || ok "B-M2 $nm: no curl call"
    [ "$(wc -l <"$LOG")" = "$l0" ] && ok "B-M2 $nm: the server got no request" || bad "B-M2 $nm: the server got a request"
  fi
  printf '%s\n' "$o" | grep -q -- "$T" && bad "B-M2 $nm: the token is printed" || ok "B-M2 $nm: the token is not printed"
}
export M3W_GITEA_TOKEN=$T GITEA_LOOPBACK_TEST_TOKEN=$T CODEBERG_TOKEN=$T CODEBERG_GITEA_TOKEN=$T
bm2 "no --token-var" 2 "--token-var NAME is required" --tag rel-1 --base-url "$URL"
bm2 "no --token-var, default URL" 2 "--token-var NAME is required" --tag rel-1 --dry-run
bm2 "loopback URL with M3W_GITEA_TOKEN" 2 "is not bound to $URL" --tag rel-1 --base-url "$URL" --token-var M3W_GITEA_TOKEN
bm2 "codeberg with M3W_GITEA_TOKEN" 2 "--token-var M3W_GITEA_TOKEN is not bound to https://codeberg.org" --tag rel-1 --base-url https://codeberg.org --token-var M3W_GITEA_TOKEN
bm2 "m3w with CODEBERG_TOKEN" 2 "is not bound to https://git.m3w.org" --tag rel-1 --base-url https://git.m3w.org --token-var CODEBERG_TOKEN
bm2 "unknown host" 2 "is not bound to https://g.example" --tag rel-1 --base-url https://g.example --token-var M3W_GITEA_TOKEN
bm2 "m3w with a port the table does not name" 2 "is not bound" --tag rel-1 --base-url https://git.m3w.org:8443 --token-var M3W_GITEA_TOKEN
bm2 "default URL with CODEBERG_TOKEN" 2 "is not bound to https://git.m3w.org" --tag rel-1 --token-var CODEBERG_TOKEN
bm2 "loopback test variable on a real host" 2 "is not bound to https://git.m3w.org" --tag rel-1 --base-url https://git.m3w.org --token-var GITEA_LOOPBACK_TEST_TOKEN
bm2 "lower-case name" 2 "--token-var must be an env var NAME" --tag rel-1 --base-url https://git.m3w.org --token-var m3w_gitea_token
# controls: a bound pair passes the check (dry run: no network call)
bm2 "control: m3w with M3W_GITEA_TOKEN (dry run)" 0 "DRY-RUN: would publish rel-1 on https://git.m3w.org/" --tag rel-1 --base-url https://git.m3w.org --token-var M3W_GITEA_TOKEN --dry-run
bm2 "control: default URL with M3W_GITEA_TOKEN (dry run)" 0 "DRY-RUN: would publish rel-1 on https://git.m3w.org/" --tag rel-1 --token-var M3W_GITEA_TOKEN --dry-run
bm2 "control: codeberg with CODEBERG_TOKEN (dry run)" 0 "DRY-RUN: would publish rel-1 on https://codeberg.org/" --tag rel-1 --base-url https://codeberg.org --token-var CODEBERG_TOKEN --dry-run
bm2 "control: codeberg with CODEBERG_GITEA_TOKEN (dry run)" 0 "DRY-RUN" --tag rel-1 --base-url https://codeberg.org/ --token-var CODEBERG_GITEA_TOKEN --dry-run
[ -s "$CB" ] && bad "B-M2 dry runs made a curl call" || ok "B-M2 dry runs made no curl call"
# the value sent is the one of the named variable: the server records the Authorization header
OTHER=OTHERTOKEN987654
l0="$(wc -l <"$LOG")"
out=$(M3W_GITEA_TOKEN=$OTHER GITEA_LOOPBACK_TEST_TOKEN=$T timeout 30 bash "$S" --tag rel-1 --base-url "$URL" --token-var GITEA_LOOPBACK_TEST_TOKEN </dev/null 2>&1); rc=$?
[ $rc -eq 0 ] && ok "B-M2 loopback with GITEA_LOOPBACK_TEST_TOKEN: exit 0 (control)" || bad "B-M2 loopback with GITEA_LOOPBACK_TEST_TOKEN: rc $rc $(printf '%s\n' "$out" | tail -n 1)"
na="$(tail -n +"$((l0 + 1))" "$LOG" | jq -r '.a' | sort -u | tr '\n' ' ')"
[ "$na" = "token $T " ] && ok "B-M2 the server got exactly 'token <the GITEA_LOOPBACK_TEST_TOKEN value>' on every request" || bad "B-M2 Authorization headers seen: ${na//$T/<T>}"
[ "$(tail -n +"$((l0 + 1))" "$LOG" | wc -l)" -ge 1 ] && ok "B-M2 the server log grew (control needle)" || bad "B-M2 the server log did not grow (blind)"
tail -n +"$((l0 + 1))" "$LOG" | grep -q "$OTHER" && bad "B-M2 the M3W_GITEA_TOKEN value reached the loopback server" || ok "B-M2 the M3W_GITEA_TOKEN value never reached the loopback server"
unset -v M3W_GITEA_TOKEN GITEA_LOOPBACK_TEST_TOKEN CODEBERG_TOKEN CODEBERG_GITEA_TOKEN
# the table: a copy of the script and its library without config/forge/hosts.tsv, or with a table that has no
# gitea row, refuses every https URL (fail closed); with the real table copied it passes (control)
bmt="$W/bm2tab"; mkdir -p "$bmt/scripts/release"; cp -- "$S" "$bmt/scripts/release_publish_gitea.sh"; cp -- "$(dirname "$S")/release/redact_cut.sh" "$bmt/scripts/release/redact_cut.sh"
o=$(M3W_GITEA_TOKEN=$T timeout 30 bash "$bmt/scripts/release_publish_gitea.sh" --tag rel-1 --token-var M3W_GITEA_TOKEN --dry-run </dev/null 2>&1); rc=$?
{ [ $rc -eq 2 ] && printf '%s\n' "$o" | grep -q 'cannot read config/forge/hosts.tsv'; } && ok "B-M2 no host table: refused, exit 2 (fail closed)" || bad "B-M2 no host table: rc $rc $(printf '%s\n' "$o" | tail -n 1)"
mkdir -p "$bmt/config/forge"; printf '# c\ngithub.com\tgithub\thttps://api.github.com\tGITHUB_TOKEN\tx\n' >"$bmt/config/forge/hosts.tsv"
o=$(M3W_GITEA_TOKEN=$T timeout 30 bash "$bmt/scripts/release_publish_gitea.sh" --tag rel-1 --token-var M3W_GITEA_TOKEN --dry-run </dev/null 2>&1); rc=$?
{ [ $rc -eq 2 ] && printf '%s\n' "$o" | grep -q 'no gitea row'; } && ok "B-M2 a host table without a gitea row: refused, exit 2" || bad "B-M2 no gitea row: rc $rc $(printf '%s\n' "$o" | tail -n 1)"
cp -- "$ROOT/config/forge/hosts.tsv" "$bmt/config/forge/hosts.tsv"
o=$(M3W_GITEA_TOKEN=$T timeout 30 bash "$bmt/scripts/release_publish_gitea.sh" --tag rel-1 --token-var M3W_GITEA_TOKEN --dry-run </dev/null 2>&1); rc=$?
{ [ $rc -eq 0 ] && printf '%s\n' "$o" | grep -q '^DRY-RUN'; } && ok "B-M2 the copy with the real host table passes (control)" || bad "B-M2 the copy with the real host table: rc $rc $(printf '%s\n' "$o" | tail -n 1)"
# L1 (round 6, K5 class; round 7: rc_env_clean): no external command runs before rc_env_clean in the script under test. The census lint
# runs on this copy; only its order findings count here (the table rows are checked by test_channel_census.sh).
l1t="$(mktemp -d "${TMPDIR:-/tmp}/l1.XXXXXX")"; : "${l1t:?}"
l1o="$(python3 -I "$HERE/channel_census.py" lint "$HERE/channels.tsv" "$S" 2>&1)"
case "$l1o" in *BLIND*|*"CENSUS invocations=0 "*|"") bad "L1 the lint is blind on $(basename "$S")" ;; *) ok "L1 the lint sees $(basename "$S") (control)" ;; esac
l1b="$(printf '%s\n' "$l1o" | grep -E 'before rc_env_clean|never calls rc_env_clean')"
[ -z "$l1b" ] && ok "L1 no external command before rc_env_clean" || bad "L1 external command before rc_env_clean: ${l1b:0:160}"
sed '2i date >/dev/null' "$S" >"$l1t/needle.sh"
python3 -I "$HERE/channel_census.py" lint "$HERE/channels.tsv" "$l1t/needle.sh" 2>&1 | grep -q 'before rc_env_clean: needle.sh:2 date' \
  && ok "L1 needle: a date inserted at line 2 is found" || bad "L1 needle: a date inserted at line 2 is not found"
rm -rf -- "${l1t:?}"
# C53 (round 12, F1 of the round-11 review): the network-spawn gate (tests/release/channel_census.py netgate) over
# this copy of the script and the helper library it loads: every network child goes through rc_net and every command
# is classified by its syntax alone (an unclassified command word is a finding; round 13: not a proof of default
# deny over bash, see test_channel_census.sh part 2c), with an empty PATH (no lookup on the host). A git started any
# other way (command -p git, "git", a redirection before git, /usr/bin/git, an absent program) is a finding here,
# also where the runtime recorders cannot see it (command -p and a path bypass the recorders on PATH). The number of
# network calls through rc_net is a positive needle, and a copy with "command -p git status" appended is a control
# needle that must be a finding.
# Round 13: the gate runs in analyser mode (--pin TABLE --analyser-only; the name list and the awk and sed
# programs of the pin still apply): this suite tests mutated copies, and the byte pin of the real scripts is
# checked by test_channel_census.sh part 2d. The library is copied next to the copy, so the appended line is
# the only finding.
c53py="$(command -v python3)"; c53d="$(mktemp -d "${TMPDIR:-/tmp}/c53.XXXXXX")"; : "${c53d:?}"
o53="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$c53py" -I "$HERE/channel_census.py" netgate --pin "$HERE/netgate_pin.tsv" --analyser-only "$S" "$(dirname "$S")/release/redact_cut.sh" 2>&1)"; r53=$?
n53="$(printf '%s\n' "$o53" | sed -n 's/^NETGATE .*network_through_rc_net=\([0-9]*\).*/\1/p')"
[ "$r53" -eq 0 ] && ok "C53 netgate: $(basename "$S") and its library start every network child through rc_net, every command classified ($(printf '%s\n' "$o53" | tail -n 1))" \
  || bad "C53 netgate rc=$r53: $(printf '%s\n' "$o53" | grep -E '^FINDING|BLIND' | head -n 3 | tr '\n' ' ')"
[ "${n53:-0}" -ge 3 ] && ok "C53 netgate: ${n53} network calls are seen through rc_net (positive needle)" || bad "C53 netgate: network count ${n53:-none} (blind?)"
mkdir -p -- "$(dirname "$c53d/release/redact_cut.sh")"; cp -- "$(dirname "$S")/release/redact_cut.sh" "$c53d/release/redact_cut.sh"; cp -- "$S" "$c53d/$(basename "$S")"; printf '%s\n' 'command -p git status' >>"$c53d/$(basename "$S")"
o53c="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$c53py" -I "$HERE/channel_census.py" netgate --pin "$HERE/netgate_pin.tsv" --analyser-only "$c53d/$(basename "$S")" "$c53d/release/redact_cut.sh" 2>&1)"; r53c=$?
[ "$r53c" -eq 1 ] && printf '%s\n' "$o53c" | grep -q "^FINDING builtin command other than command -v NAME: $(basename "$S"):[0-9]* | key=483e5249\$" \
  && printf '%s\n' "$o53c" | grep -q '^NETGATE .* findings=1$' && ok "C53 netgate control needle: a command -p git appended to a copy is the only finding" \
  || bad "C53 netgate control needle: an appended command -p git is not a finding (rc $r53c)"
rm -rf -- "${c53d:?}"
[ "$skipped" -eq 0 ] || echo "SKIPPED: $skipped case(s) did not run (see the SKIP lines); the result does not cover them"
echo "RESULT pass=$pass fail=$fail"; suite_exit "$fail" "$skipped"   # round 8 (N6): 77 when a case was SKIPPED
