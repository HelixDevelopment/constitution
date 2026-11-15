#!/usr/bin/env python3
"""Differential oracle for the round-12 netgate: for every candidate fixture, (1) the gate's verdict with an empty
PATH and with a normal PATH, (2) what real bash 5.3 does when it runs the same text in a sandbox where every network
program is a local recorder (no network: the recorders only append a line to a log file and exit 0).
A candidate is a BYPASS when the gate returns rc 0 (no finding) and bash ran a network program without rc_net.

usage: oracle13.py MODE REPO CASES_JSON OUTDIR PIN (MODE r12: netgate SCRIPT; r13: netgate --pin PIN --analyser-only SCRIPT)
Adapted from the round-12 reviewer's oracle.py: only the gate command line differs.
Every path is under OUTDIR (a directory under the reviewer's own mktemp -d root). Nothing is deleted."""
import json, os, socket, stat, subprocess, sys, threading

mode, repo, cases_json, outd, pin = sys.argv[1:6]
outed = None
repo, outd = os.path.abspath(repo), os.path.abspath(outd)
cen = os.path.join(repo, "tests/release/channel_census.py")
os.makedirs(outd, exist_ok=True)
NET = ["git", "curl", "ssh", "wget", "gh", "glab", "scp", "rsync", "socat"]
REAL = ["cat", "gawk", "mawk", "sed", "sort", "cp", "grep", "tr", "env", "true", "mkdir", "chmod", "ls", "dash", "bash"]
SQLITE = os.path.expanduser("~/Android/Sdk/platform-tools/sqlite3")


def mkexe(p, text):
    with open(p, "w") as fh:
        fh.write(text)
    os.chmod(p, stat.S_IRWXU)


def listener():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    s.listen(4)
    s.settimeout(15)
    got = []

    def run():
        try:
            c, _ = s.accept()
            got.append("accepted")
            c.settimeout(2)
            try:
                got.append(c.recv(200))
            except Exception:
                pass
            c.close()
        except Exception:
            pass
    t = threading.Thread(target=run, daemon=True)
    t.start()
    return s, s.getsockname()[1], got, t


cases = json.load(open(cases_json))
summary = []
for case in cases:
    name = case["name"]
    sb = os.path.join(outd, name)
    os.makedirs(sb)
    bindir, tooldir = os.path.join(sb, "bin"), os.path.join(sb, "tools")
    os.makedirs(bindir)
    os.makedirs(tooldir)
    log = os.path.join(sb, "net.log")
    for p in NET:
        mkexe(os.path.join(bindir, p), '#!/bin/bash\nprintf \'%%s %%s rcnet=%%s\\n\' "${0##*/}" "$*" "${ZZ_RCNET:-0}" >>%s\n' % log)
    for p in REAL:
        for d in ("/usr/bin", "/bin"):
            if os.path.exists(os.path.join(d, p)):
                os.symlink(os.path.join(d, p), os.path.join(tooldir, p))
                break
    os.symlink("/usr/bin/gawk", os.path.join(tooldir, "awk"))
    if os.path.exists(SQLITE):
        os.symlink(SQLITE, os.path.join(tooldir, "sqlite3"))
    port = None
    lst = None
    if case.get("listen"):
        lst, port, got, th = listener()
    body = case["body"].replace("@SB@", sb).replace("@PORT@", str(port))
    for rel, text in case.get("files", {}).items():
        p = os.path.join(sb, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        mkexe(p, text.replace("@SB@", sb).replace("@PORT@", str(port)))
    script = os.path.join(sb, case.get("script", "fx.sh"))
    with open(script, "w") as fh:
        fh.write(body)
    gate = []
    for path in ("/nonexistent", "/usr/local/bin:/usr/bin:/bin"):
        gcmd = ["/usr/bin/python3", "-I", cen, "netgate", script] if mode == "r12" else ["/usr/bin/python3", "-I", cen, "netgate", "--pin", pin, "--analyser-only", script]
        p = subprocess.run(gcmd, env={"PATH": path, "LANG": "C.UTF-8"},
                           capture_output=True, text=True, timeout=60)
        gate.append((p.returncode, p.stdout.strip()))
    run = os.path.join(sb, "run.sh")
    prelude = 'rc_net() { ZZ_RCNET=1 "$@"; }\n'
    with open(run, "w") as fh:
        fh.write(prelude + body.split("\n", 1)[1] if body.startswith("#!") else prelude + body)
    env = {"PATH": bindir + ":" + tooldir, "HOME": sb, "LANG": "C", "TMPDIR": sb}
    try:
        b = subprocess.run(["/usr/bin/bash", "--norc", "--noprofile", run], cwd=sb, env=env, capture_output=True,
                           text=True, timeout=25, stdin=subprocess.DEVNULL)
        brc, bout = b.returncode, (b.stdout + b.stderr)
    except subprocess.TimeoutExpired:
        brc, bout = "timeout", ""
    conn = ""
    if lst is not None:
        th.join(16)
        conn = "LOOPBACK-CONNECT %r" % (got[0] if got else None) if got else "no-connect"
        lst.close()
    netlog = open(log).read() if os.path.exists(log) else ""
    leak = [l for l in netlog.splitlines() if l.endswith("rcnet=0")]
    ctrl = [l for l in netlog.splitlines() if l.endswith("rcnet=1")]
    bypass = gate[0][0] == 0 and (bool(leak) or conn.startswith("LOOPBACK-CONNECT"))
    verdict = "BYPASS" if bypass else ("CAUGHT" if gate[0][0] == 1 else "NO-LEAK")
    with open(os.path.join(sb, "result.txt"), "w") as fh:
        fh.write("case %s\nscript %s\n--- body\n%s\n--- gate empty PATH rc=%d\n%s\n--- gate normal PATH rc=%d\n%s\n"
                 "--- bash rc=%s\n%s\n--- network recorder log\n%s--- loopback\n%s\nVERDICT %s\n"
                 % (name, os.path.basename(script), body, gate[0][0], gate[0][1], gate[1][0], gate[1][1], brc,
                    bout[-1500:], netlog, conn, verdict))
    summary.append("%s\t%s\tgate_rc=%d/%d\tbash_rc=%s\tleak=%d\tctrl=%d\t%s\t%s" % (
        verdict, name, gate[0][0], gate[1][0], brc, len(leak), len(ctrl), conn,
        (gate[0][1].split("\n")[0] if gate[0][0] else "")[:110]))
print("\n".join(summary))
