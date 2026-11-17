"""Ground truth of git's precedence (class d), round 5. Real git, loopback / file only, sandbox under argv[1]."""
import http.server, os, subprocess, sys, tempfile, threading, socket
GIT = "/usr/bin/git"
base = tempfile.mkdtemp(prefix="gt.", dir=sys.argv[1])
gcfg = os.path.join(base, "gitconfig")
open(gcfg, "w").write("[init]\n\tdefaultBranch = main\n[user]\n\tname = gt\n\temail = gt@example.invalid\n")
ENV0 = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "SSH_ASKPASS"))}
ENV0.update(GIT_CONFIG_GLOBAL=gcfg, GIT_CONFIG_NOSYSTEM="1", LC_ALL="C", GIT_TERMINAL_PROMPT="0")
def git(*a, env=None, cwd=None):
    e = dict(ENV0); e.update(env or {})
    for k, v in list(e.items()):
        if v is None: del e[k]
    return subprocess.run([GIT] + list(a), env=e, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=60, start_new_session=True)
def exe(p, body):
    open(p, "w").write(body); os.chmod(p, 0o755)
repo = os.path.join(base, "repo"); git("init", "-q", repo)
open(os.path.join(repo, "f"), "w").write("x\n"); git("-C", repo, "add", "f"); git("-C", repo, "commit", "-q", "-m", "i")
bare = os.path.join(base, "bare.git"); git("init", "-q", "--bare", bare); git("-C", repo, "push", "-q", bare, "main")
rows = []
def row(n, what, observed, expect):
    rows.append((n, what, observed, "OK" if observed == expect else "UNEXPECTED(expected %s)" % expect))
# --- ext:: and GIT_ALLOW_PROTOCOL
mark = os.path.join(base, "EXT"); helper = os.path.join(base, "exth")
exe(helper, "#!/bin/sh\necho ran >>%s\nexit 1\n" % mark)
def ext_run(env, cfg):
    if os.path.exists(mark): os.unlink(mark)
    git("-C", repo, *cfg, "fetch", "ext::%s" % helper, env=env)
    return os.path.exists(mark)
row("D1", "ext:: with -c protocol.ext.allow=never, no env", ext_run({}, ["-c", "protocol.ext.allow=never"]), False)
row("D2", "ext:: with -c protocol.ext.allow=never + env GIT_ALLOW_PROTOCOL=ext:file",
    ext_run({"GIT_ALLOW_PROTOCOL": "ext:file"}, ["-c", "protocol.ext.allow=never"]), True)
row("D3", "ext:: with env GIT_ALLOW_PROTOCOL unset and repo config protocol.ext.allow=always + -c never",
    (git("-C", repo, "config", "protocol.ext.allow", "always"), ext_run({}, ["-c", "protocol.ext.allow=never"]))[1], False)
git("-C", repo, "config", "--unset", "protocol.ext.allow")
row("D4", "url.<ext::>.insteadOf rewrite + -c protocol.ext.allow=never",
    (git("-C", repo, "config", "url.ext::%s.insteadOf" % helper, "https://rewrite.invalid/"),
     ext_run({}, ["-c", "protocol.ext.allow=never"]) if False else
     (lambda: (os.path.exists(mark) and os.unlink(mark), git("-C", repo, "-c", "protocol.ext.allow=never", "fetch",
      "https://rewrite.invalid/"), os.path.exists(mark))[2])())[1], False)
git("-C", repo, "config", "--remove-section", "url.ext::%s" % helper)
# --- GIT_PROTOCOL_FROM_USER and file:// (protocol.file.allow=user)
r = git("-C", repo, "-c", "protocol.file.allow=user", "fetch", "file://" + bare, env={"GIT_PROTOCOL_FROM_USER": "0"})
row("D5", "file:// with protocol.file.allow=user + env GIT_PROTOCOL_FROM_USER=0: refused", r.returncode != 0, True)
r = git("-C", repo, "-c", "protocol.file.allow=user", "fetch", "file://" + bare)
row("D6", "file:// with protocol.file.allow=user, env GIT_PROTOCOL_FROM_USER unset: allowed", r.returncode == 0, True)
# --- askpass: HTTP 401 server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(401); self.send_header("WWW-Authenticate", 'Basic realm="gt"')
        self.send_header("Content-Length", "0"); self.end_headers()
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H); threading.Thread(target=srv.serve_forever, daemon=True).start()
url = "http://127.0.0.1:%d/x.git" % srv.server_address[1]
amark = os.path.join(base, "ASK"); ask = os.path.join(base, "askp")
exe(ask, "#!/bin/sh\necho \"$1\" >>%s\necho typed\n" % amark)
def asked(env, cfg, repo_cfg=None):
    if os.path.exists(amark): os.unlink(amark)
    for k, v in (repo_cfg or {}).items(): git("-C", repo, "config", k, v)
    git("-C", repo, *cfg, "fetch", url, env=env)
    for k in (repo_cfg or {}): git("-C", repo, "config", "--unset", k)
    return os.path.exists(amark)
row("D7", "core.askPass in repo config, no env: askpass runs (the r4 finding)", asked({}, [], {"core.askPass": ask}), True)
row("D8", "core.askPass in repo config + -c core.askPass= : askpass runs?", asked({}, ["-c", "core.askPass="], {"core.askPass": ask}), False)
row("D9", "core.askPass in repo config + env GIT_ASKPASS='' (set, empty): askpass runs?", asked({"GIT_ASKPASS": ""}, [], {"core.askPass": ask}), False)
row("D10", "env GIT_ASKPASS=prog beats -c core.askPass= (env wins)", asked({"GIT_ASKPASS": ask}, ["-c", "core.askPass="]), True)
row("D11", "env SSH_ASKPASS=prog, GIT_ASKPASS unset, no core.askPass: runs (git falls back to SSH_ASKPASS)", asked({"SSH_ASKPASS": ask}, []), True)
row("D12", "env SSH_ASKPASS=prog + env GIT_ASKPASS='' : runs?", asked({"SSH_ASKPASS": ask, "GIT_ASKPASS": ""}, []), False)
row("D13", "env SSH_ASKPASS=prog + -c core.askPass= (GIT_ASKPASS unset): runs?", asked({"SSH_ASKPASS": ask}, ["-c", "core.askPass="]), False)
# credential helper
hmark = os.path.join(base, "HELPER"); hp = os.path.join(base, "helper")
exe(hp, "#!/bin/sh\necho \"$1\" >>%s\ncat >/dev/null\n" % hmark)
def helper_ran(cfg):
    if os.path.exists(hmark): os.unlink(hmark)
    git("-C", repo, "config", "credential.helper", hp)
    git("-C", repo, *cfg, "fetch", url, env={"GIT_ASKPASS": ""})
    git("-C", repo, "config", "--unset", "credential.helper")
    return os.path.exists(hmark)
row("D14", "credential.helper in repo config runs on 401 (kept by design)", helper_ran([]), True)
row("D15", "credential.helper + -c credential.interactive=false still runs the helper (git 2.53)", helper_ran(["-c", "credential.interactive=false"]), True)
srv.shutdown()
# --- ssh command precedence (fake ssh logs which one ran)
sm = os.path.join(base, "SSH")
for n in ("envcmd", "cfgcmd", "gitssh"):
    exe(os.path.join(base, n), "#!/bin/sh\necho %s >>%s\nexit 255\n" % (n, sm))
def ssh_used(env, repo_cfg):
    if os.path.exists(sm): os.unlink(sm)
    for k, v in repo_cfg.items(): git("-C", repo, "config", k, v)
    git("-C", repo, "fetch", "ssh://git@127.0.0.1:9/x.git", env=env)
    for k in repo_cfg: git("-C", repo, "config", "--unset", k)
    return open(sm).read().split() if os.path.exists(sm) else []
row("D16", "env GIT_SSH_COMMAND vs core.sshCommand: env wins", ssh_used({"GIT_SSH_COMMAND": os.path.join(base, "envcmd")}, {"core.sshCommand": os.path.join(base, "cfgcmd")})[:1], ["envcmd"])
row("D17", "core.sshCommand vs env GIT_SSH: core.sshCommand wins", ssh_used({"GIT_SSH": os.path.join(base, "gitssh")}, {"core.sshCommand": os.path.join(base, "cfgcmd")})[:1], ["cfgcmd"])
row("D18", "env GIT_SSH alone is used when nothing else is set", ssh_used({"GIT_SSH": os.path.join(base, "gitssh")}, {})[:1], ["gitssh"])
# hooks: -c core.hooksPath beats repo config
hm = os.path.join(base, "HOOK"); hd = os.path.join(base, "hooks"); os.makedirs(hd)
exe(os.path.join(hd, "post-checkout"), "#!/bin/sh\necho ran >>%s\n" % hm)
git("-C", repo, "config", "core.hooksPath", hd)
git("-C", repo, "-c", "core.hooksPath=/dev/null", "checkout", "-q", "--detach", "HEAD")
row("D19", "-c core.hooksPath=/dev/null beats repo core.hooksPath (no hook ran)", os.path.exists(hm), False)
git("-C", repo, "checkout", "-q", "main"); ran = os.path.exists(hm)
row("D20", "control needle: without -c the configured hook runs", ran, True)
git("-C", repo, "config", "--unset", "core.hooksPath")
# GIT_CONFIG_PARAMETERS (env) vs -c: which wins?
r = git("-C", repo, "-c", "core.hooksPath=/dev/null", "config", "--get", "core.hooksPath",
        env={"GIT_CONFIG_PARAMETERS": "'core.hookspath'='/evil'"})
row("D21", "GIT_CONFIG_PARAMETERS env and -c both given: -c (command line) value read last wins", r.stdout.strip(), "/dev/null")
r = git("-C", repo, "-c", "core.hooksPath=/dev/null", "config", "--get", "core.hooksPath",
        env={"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.hooksPath", "GIT_CONFIG_VALUE_0": "/evil"})
row("D22", "GIT_CONFIG_COUNT/KEY/VALUE env and -c both given: value read", r.stdout.strip(), "/dev/null")
print("git", git("--version").stdout.strip())
for x in rows:
    print("\t".join(str(c) for c in x))
