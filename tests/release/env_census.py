#!/usr/bin/env python3
"""tests/release/env_census.py — runtime environment census of the children of the release scripts (round 7,
L1 and L2 of the round-6 review).

Class (§11.4.289(C)): test instrument. The recorders are real child processes: each one is a small sh script on
PATH in front of a real command; it appends to a log the start environment of ITS OWN process, read from
/proc/$$/environ (the environment the release script gave it, every entry, also entries whose names are not shell
identifiers: dash and bash keep those in /proc but do not list them with `env`, which is why the round-6 recorders
were blind to L2), the command line of its parent, whether its file descriptor 9 is open (the state pipe of
rc_env_clean must be closed before any child runs) and, round 8 (N3), every file descriptor above 2 that it
inherited (a descriptor without the close-on-exec flag, read from /proc/$$/fdinfo: the shell's own saved and script
descriptors carry the flag, so only what the parent passed on is listed), and then execs the real command.

Usage:
  env_census.py mk DIR LOG CMD...          write one recorder per CMD into DIR (CMD not on PATH: skipped)
  env_census.py check LOG [options]        check the log; exit 0 clean, 1 findings, 2 blind
     --allow NAME ...         names every checked child may have
     --allow-fd N ...         inherited file descriptors above 2 a checked child may have (the scripts' own
                              DIE_FD 3, derive's saved stdout 4); every other one is a finding (round 8, N3)
     --extra CMD=NAME ...     one more name CMD may have (bash=M3W_GITEA_TOKEN: the publisher call)
     --marker M ...           values no checked entry may contain, except an --extra entry
     --parent S ...           a record is checked when the first or second word of its parent's command line
                              (base name) is S (default: the three release scripts and "rc-clean-env": the script
                              itself and its subshells); a child of timeout(1) is checked as well
     --min N                  at least N records must be checked (control needle; default 1)
Output: "ENVCENSUS records=R checked=C findings=F", then one "FINDING cmd: name ..." per finding. A value is never
printed; a finding names the variable and says whether it holds a marker.
Round 8 (N1): there is no name-prefix option any more. The allow-list is a list of exact names (the thirteen
locale categories are listed one by one); "--allow-prefix" is refused (exit 2), so a test cannot widen it again.

  env_census.py classes LIB                the allow-list class table of rc_env_lockdown (round 8, N1): for every
                                           allow-listed name of LIB, whether ssh would send it to the remote server
                                           (SendEnv patterns of `ssh -G`, with control needles), and the value check
                                           of LIB run on a good value, on fourteen credential-shaped values and on
                                           the class's own badly shaped values (round 9); exit 0
                                           when every credential-shaped value is dropped, 1 otherwise, 2 blind
"""
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
import os
import shutil
import sys

REC = """#!/bin/sh
t='%(log)s.rec.'$$
{ printf '== %%s\\n' '%(cmd)s'; printf 'P '; "%(tr)s" '\\000' ' ' </proc/$PPID/cmdline; printf '\\n'
  "%(awk)s" 'BEGIN { RS = "\\000" } { gsub(/\\n/, "\\\\n"); print "E " $0 }' /proc/$$/environ
  [ -e /proc/$$/fd/9 ] && printf 'F 9\\n'
  for f in /proc/$$/fdinfo/*; do n="${f##*/}"; [ "$n" -gt 2 ] 2>/dev/null || continue
    [ -r "$f" ] || continue; fl=""; { while read -r k v; do [ "$k" = flags: ] && fl="$v"; done <"$f"; } 2>/dev/null
    case "$fl" in 0*) [ $(( $fl & 02000000 )) -eq 0 ] && printf 'D %%s\\n' "$n" ;; esac
  done; } >"$t"
[ -s "$t" ] || { printf 'env_census recorder: cannot write %%s\\n' "$t" >&2; exit 125; }
'%(flock)s' '%(log)s' '%(cat)s' "$t" >>'%(log)s' || { printf 'env_census recorder: append to the log failed\\n' >&2; exit 125; }
'%(rm)s' -f "$t"
"%(awk)s" 'BEGIN { RS = "\\000" } /^PWD=/ { f = 1 } END { exit !f }' /proc/$$/environ || unset PWD
exec '%(real)s' "$@"
"""
# round 11 (a race found by the second suite run): the recorder used to append its block to the shared log in
# several separate writes (printf, tr, awk, the descriptor loop). Two recorders running at the same time (a network
# child and a local child in one pipeline) interleaved their lines, so one child's names landed under the other's
# "== cmd" header (measured: 285 of 600 records misattributed with a git and a sed recorder started together 300
# times; one log line read "P == git"). The suites then reported a local child's names as a network child's
# finding. The recorder now writes its whole block to its own file next to the log and appends it in one step
# under flock(1) on the log, so the log format and its readers are unchanged. Round 12 (F3 of the round-11 review):
# that file is per process (LOG.rec.PID, so two recorders never share one), not private: it is created with the
# umask of the caller, and the logs of these tests hold fake canaries only. A record that cannot be written stops
# the child with 125: a missing record could hide a finding.
# round 11: the recorder is a /bin/sh script, and dash exports PWD of its own (measured: env -i /bin/sh -c env
# prints PWD); a recorder in front of timeout(1) passed that PWD on to the git that timeout runs, a name the release
# script never gave. The recorder now removes PWD before the exec unless its own start environment had it, so
# the recorded child gets exactly the environment the release script gave the recorder.


def mk(d, log, cmds):
    tools = {t: shutil.which(t) for t in ("tr", "awk", "flock", "cat", "rm")}
    missing = [t for t, v in tools.items() if not v]
    if missing:
        print("BLIND: not found: " + " ".join(missing))
        return 2
    n = 0
    for c in cmds:
        real = shutil.which(c)
        if not real:
            continue
        p = os.path.join(d, c)
        with open(p, "w") as f:
            f.write(REC % dict(tools, cmd=c, log=log, real=real))
        os.chmod(p, 0o755)
        n += 1
    print("RECORDERS %d" % n)
    return 0 if n else 2


def records(log):
    out, cur = [], None
    for l in open(log, errors="replace").read().split("\n"):
        if l.startswith("== "):
            cur = {"cmd": l[3:], "parent": "", "env": [], "fd9": False, "fds": []}
            out.append(cur)
        elif cur is not None and l.startswith("P "):
            cur["parent"] = l[2:]
        elif cur is not None and l == "F 9":
            cur["fd9"] = True
        elif cur is not None and l.startswith("D "):
            cur["fds"].append(l[2:])
        elif cur is not None and l.startswith("E "):
            cur["env"].append(l[2:])
    return out


def check(log, a):
    opts = {"--allow": [], "--allow-fd": [], "--extra": [], "--marker": [], "--parent": [], "--min": ["1"], "--cmd": []}
    k = None
    for x in a:
        if x == "--allow-prefix":
            print("BLIND: --allow-prefix is refused (round 8, N1): name the allowed variables one by one")
            return 2
        if x in opts:
            k = x
            if k == "--min":
                opts[k] = []
            continue
        if k is None:
            print("BLIND: bad arguments")
            return 2
        opts[k].append(x)
    parents = opts["--parent"] or ["tag_and_release.sh", "release_publish_gitea.sh", "derive_release_facts.sh",
                                   "rc-clean-env"]
    allow = set(opts["--allow"])
    extra = {}
    for e in opts["--extra"]:
        c, _, n = e.partition("=")
        extra.setdefault(c, set()).add(n)
    recs = records(log) if os.path.exists(log) else []
    findings, checked = [], 0
    for r in recs:
        par = r["parent"]
        w = [x.rsplit("/", 1)[-1] for x in par.split(" ")[:2]]
        if not (any(p in w for p in parents) or w[:1] == ["timeout"]):
            continue
        if opts["--cmd"] and r["cmd"] not in opts["--cmd"]:   # round 11: check only these commands (network children)
            continue
        checked += 1
        if r["fd9"]:
            findings.append("%s: file descriptor 9 (the state pipe of rc_env_clean) is open" % r["cmd"])
        for fd in r["fds"]:
            if fd not in opts["--allow-fd"]:
                findings.append("%s: file descriptor %s is inherited (not close-on-exec)" % (r["cmd"], fd))
        for e in r["env"]:
            name, eq, val = e.partition("=")
            if not eq:
                findings.append("%s: an entry with no '=' (%d bytes)" % (r["cmd"], len(e)))
                continue
            ok_name = name in allow or name in extra.get(r["cmd"], ())
            has_marker = any(m in e for m in opts["--marker"])
            if not ok_name:
                findings.append("%s: %r is not on the allow-list%s" % (r["cmd"], name[:60],
                                                                         " (and holds a marker)" if has_marker else ""))
            elif has_marker and name not in extra.get(r["cmd"], ()):
                findings.append("%s: %r holds a marker" % (r["cmd"], name[:60]))
    for f in findings:
        print("FINDING " + f)
    print("ENVCENSUS records=%d checked=%d findings=%d" % (len(recs), checked, len(findings)))
    if checked < int((opts["--min"] or ["1"])[0]):
        print("BLIND: fewer checked records than --min")
        return 2
    return 1 if findings else 0


# classes (round 8, N1): the test's own good value for every allow-listed name (a name of LIB missing here is BLIND,
# so a name added to the library must be classified here too) and its class
GOOD = {
    "PATH": ("path-list", "/usr/local/bin:/usr/bin:/bin"), "HOME": ("path", "/home/u"), "PWD": ("path", "/srv/w"),
    "SHELL": ("path", "/bin/bash"), "TMPDIR": ("path", "/tmp"), "XDG_CONFIG_HOME": ("path", "/home/u/.config"),
    "XDG_CACHE_HOME": ("path", "/home/u/.cache"), "XDG_DATA_HOME": ("path", "/home/u/.local/share"),
    "XDG_STATE_HOME": ("path", "/home/u/.local/state"), "XDG_RUNTIME_DIR": ("path", "/run/user/1000"),
    "GNUPGHOME": ("path", "/home/u/.gnupg"), "GH_CONFIG_DIR": ("path", "/home/u/.config/gh"),
    "GLAB_CONFIG_DIR": ("path", "/home/u/.config/glab-cli"), "GIT_CONFIG_GLOBAL": ("path", "/home/u/.gitconfig"),
    "GIT_CONFIG_SYSTEM": ("path", "/etc/gitconfig"), "GIT_SSH": ("program", "/usr/bin/ssh"),
    "GIT_ASKPASS": ("program", "/usr/lib/git-core/git-gui--askpass"), "SSH_ASKPASS": ("program", "ssh-askpass"),
    "GIT_SSH_COMMAND": ("command", "ssh -o BatchMode=yes -i /home/u/.ssh/id_ed25519"),
    "SSH_AUTH_SOCK": ("socket", None), "USER": ("account", "u"), "LOGNAME": ("account", "u"),
    "LANG": ("locale", "en_US.UTF-8"), "LANGUAGE": ("locale-list", "sr_RS@latin:en_US:en"), "TZ": ("tz", ":/etc/localtime"),
    "TERM": ("term", "xterm-256color"), "DBUS_SESSION_BUS_ADDRESS": ("dbus", "unix:path=/run/user/1000/bus"),
    "GIT_SSH_VARIANT": ("enum", "ssh"), "GIT_CONFIG_NOSYSTEM": ("flag", "1"), "GH_HOST": ("host", "github.example.com"),
    "GITLAB_HOST": ("host", "https://gitlab.example.com"),
}
for _c in ("ALL", "CTYPE", "COLLATE", "MESSAGES", "MONETARY", "NUMERIC", "TIME", "PAPER", "NAME", "ADDRESS",
           "TELEPHONE", "MEASUREMENT", "IDENTIFICATION"):
    GOOD["LC_" + _c] = ("locale", "C.UTF-8")
# credential-shaped values every allow-listed name must drop (fabricated markers, never real credentials). Round 9
# (F3 F4 of the round-8 review): every token shape the library claims (gh?_ with each of p o u s r, github_pat_,
# glpat-), control characters other than a newline, and a value one byte over the 4096-byte cap, each shaped so that
# the class check of the path and locale names alone would keep it (only the common check can drop it)
_Z = "Z" * 36
BAD = (("url-userinfo", "https://u:ZZPW8@h.invalid/r"), ("ghp", "ghp_" + _Z), ("gho", "gho_" + _Z), ("ghu", "ghu_" + _Z),
       ("ghs", "ghs_" + _Z), ("ghr", "ghr_" + _Z), ("github_pat", "github_pat_" + _Z), ("glpat", "glpat-" + _Z),
       ("newline", "a\nb"), ("tab", "/a\tb"), ("esc", "/a\x1bb"), ("del", "/a\x7fb"), ("cr", "/a\rb"),
       ("over-4096", "/" + "a" * 4096))
# per class: values that pass the common checks but not the class's own shape (each must be dropped too); an empty
# list for the classes that have no shape beyond the common checks (path-list, command: a documented honest limit).
# Round 9 (F4): a locale value with user information and no scheme, a ":" or a "/"; a socket name that is a regular
# file or a directory ("@REGULAR@" and "@DIR@" are replaced by real paths at run time). Round 10 (F8, the R9-1 class):
# the values ssh sends off-host (LANG, LC_*) and LANGUAGE must be locale names: a bare 40-hex token, a word with "@host"
# and "user:password@host" in LANGUAGE are dropped
SHAPE_BAD = {"path": ["rel/ZZSH8"], "program": ["a b ZZSH8"], "command": [], "path-list": [],
             "socket": ["/nonexistent.sock", "@REGULAR@", "@DIR@"], "account": ["a b"],
             "locale": ["a4 ZZSH8", "u:ZZPW8@host", "C:UTF-8", "en_US/x", "0123456789abcdef0123456789abcdef01234567", "zzsh8@host"],
             "locale-list": ["a b", "a/b", "user:ZZPW8@host", "en:0123456789abcdef0123456789abcdef01234567"], "tz": ["a b"],
             "term": ["a b"], "dbus": ["a b"], "enum": ["zzsh8"], "flag": ["a b"], "host": ["a b"]}


def classes(lib):
    import fnmatch
    import re
    import subprocess
    try:
        src = open(lib, encoding="utf-8").read()
    except OSError:
        print("BLIND: cannot read " + lib)
        return 2
    m = re.search(r'rc_env_lockdown\(\) \{\n(?:  local -[^\n]*\n)?  local v(?: [a-z]+)* keep="([^"]*)"', src)   # round 10: a "local -" line first
    if not m:
        print("BLIND: the allow-list of rc_env_lockdown is not found in " + lib)
        return 2
    names = m.group(1).split()
    if any(n.endswith("*") for n in names) or re.search(r'case "\$v" in LC_\*\)', src):
        print("FINDING: the allow-list holds a name prefix")
        return 1
    unknown = [n for n in names if n not in GOOD]
    if unknown:
        print("BLIND: names without a class in the instrument: " + " ".join(unknown))
        return 2
    # ssh SendEnv patterns, with a positive needle (a pattern given on the command line is seen) and a negative one
    send, sshs = [], "ssh"
    try:
        out = subprocess.run(["ssh", "-G", "-o", "SendEnv=ZZNEEDLE8", "release-census.invalid"], capture_output=True,
                             text=True, timeout=20).stdout
        send = [l.split(None, 1)[1] for l in out.splitlines() if l.lower().startswith("sendenv ")]
        if "ZZNEEDLE8" not in send:
            print("BLIND: ssh -G does not show a SendEnv pattern given on its command line")
            return 2
        send.remove("ZZNEEDLE8")
        if any(fnmatch.fnmatchcase("ZZNOTSENT8", p) for p in send):
            print("BLIND: a fabricated name matches a SendEnv pattern (negative needle)")
            return 2
    except (OSError, subprocess.SubprocessError):
        sshs = "absent"
    # round 9 (F4): the instrument makes its own socket (the good socket value is always tested), a regular file and a
    # directory, in a fresh temp directory; the socket is bound by a relative name (no 108-byte path limit)
    import socket
    import tempfile
    tdir = tempfile.mkdtemp(prefix="envcls.")
    here = os.getcwd()
    try:
        os.chdir(tdir)
        socket.socket(socket.AF_UNIX).bind("s.sock")
    finally:
        os.chdir(here)
    sock, regular = os.path.join(tdir, "s.sock"), os.path.join(tdir, "regular")
    open(regular, "w").close()
    sub = {"@REGULAR@": regular, "@DIR@": tdir}
    args, rows = [], []
    for n in names:
        good = GOOD[n][1] if GOOD[n][1] is not None else sock
        shp = [sub.get(v, v) for v in SHAPE_BAD[GOOD[n][0]]]
        rows.append(len(shp))
        args += [n, good]
        for _, v in BAD:
            args += [n, v]
        for v in shp:
            args += [n, v]
    # negative control: a name that is not on the list has no class and is never passed on (fail closed)
    args += ["ZZUNLISTED8", "x"]
    r = subprocess.run(["bash", "-c", '. "$1" || exit 3; type _rc_env_shape_ok >/dev/null 2>&1 || exit 3; shift\n'
                        'while [ $# -gt 0 ]; do if _rc_env_shape_ok "$1" "$2"; then echo K; else echo D; fi; shift 2; done',
                        "_", lib] + args, capture_output=True, text=True, timeout=60)
    shutil.rmtree(tdir, ignore_errors=True)
    res = r.stdout.split()
    if r.returncode != 0 or len(res) != len(args) // 2:
        print("BLIND: the value check _rc_env_shape_ok of %s did not run (rc %d)" % (lib, r.returncode))
        return 2
    bad, i = 0, 0
    print("CLASSES ssh=%s sendenv=%s" % (sshs, " ".join(send) if send else "-"))
    for n, k in zip(names, rows):
        w = 1 + len(BAD) + k
        row = res[i:i + w]
        i += w
        sent = "yes" if any(fnmatch.fnmatchcase(n, p) for p in send) else "no"
        good_ok = row[0] == "K"
        common = row[1:1 + len(BAD)]
        shape = row[1 + len(BAD):]
        drops = all(x == "D" for x in common)
        shape_ok = all(x == "D" for x in shape)
        verdict = "ok" if (good_ok and drops and shape_ok) else "FINDING"
        bad += verdict != "ok"
        print("CLASS %-25s class=%-11s ssh_sendenv=%-3s good=%s %s shape=%s %s" % (
            n, GOOD[n][0], sent, row[0], " ".join("%s=%s" % (b[0], x) for b, x in zip(BAD, common)),
            ",".join(shape) if shape else "n/a", verdict))
    if res[-1] != "D":
        print("FINDING: a name that is not on the list is passed on by _rc_env_shape_ok (not fail closed)")
        bad += 1
    print("CLASSES names=%d findings=%d" % (len(names), bad))
    return 1 if bad else 0


def main():
    a = sys.argv[1:]
    if a[:1] == ["classes"] and len(a) == 2:
        return classes(a[1])
    if a[:1] == ["mk"] and len(a) >= 4:
        return mk(a[1], a[2], a[3:])
    if a[:1] == ["check"] and len(a) >= 2:
        return check(a[1], a[2:])
    sys.stderr.write(__doc__ or "")
    return 2


if __name__ == "__main__":
    sys.exit(main())
