#!/usr/bin/env python3
"""tests/security/fixtures/fake_gitleaks.py -- emulates `gitleaks git` for the history-scan tests
(gate-logic tests only, §11.4.289: never evidence of what the real gitleaks finds).

Honest mode: runs `git -C TARGET log -p -U0 <--log-opts words>` and reports every ADDED line that
matches ghp_[A-Za-z0-9]{36} (like gitleaks, deleted lines are not scanned), as a JSON array
{RuleID, File, StartLine, Commit, Entropy, Secret}. Secret is "REDACTED" only with --redact.
Exit 1 with findings, 0 without. $FAKE_GITLEAKS_MODE changes the behaviour:
  crash_after_empty  write [] and exit 126      crash_nofile  exit 126, no report
  blind_bare         [] exit 0 on a bare repo   allblind      [] exit 0 always
  allfind            flag every added line      rc0_findings  honest report, exit 0
  rc0_nofile         exit 0, no report
  tip_only           scan only the files at the tip of every ref (no history)
  drop_pos / drop_merge  honest, but miss the findings in files named pos.env / merge.env
$FAKE_GITLEAKS_STRIP="W1 W2 ..." drops those words from the log options (emulates a scanner or a
git that ignores them, for example --text, so git attributes hide content again).
$FAKE_GITLEAKS_CHATTER=1 also prints each finding (file, commit, rule) to stdout and a count to stderr,
like the real scanner's console log, so a test can check that this output stays off the console.
"""
import json
import os
import re
import shlex
import subprocess
import sys

a = sys.argv[1:]
mode = os.environ.get("FAKE_GITLEAKS_MODE", "honest")
if not a or a[0] != "git":
    sys.stderr.write("fake gitleaks: only `git` is supported\n")
    sys.exit(2)
rep, opts, redact, target = None, "--all", False, a[-1]
i = 1
while i < len(a) - 1:
    x = a[i]
    if x == "-r":
        rep = a[i + 1]; i += 2; continue
    if x.startswith("--log-opts="):
        opts = x[len("--log-opts="):]; i += 1; continue
    if x == "--log-opts":
        opts = a[i + 1]; i += 2; continue
    if x == "--redact":
        redact = True
    i += 1


def write(obj):
    if rep:
        with open(rep, "w") as f:
            json.dump(obj, f)


if mode == "crash_nofile":
    sys.exit(126)
if mode == "rc0_nofile":
    sys.exit(0)
if mode == "crash_after_empty":
    write([]); sys.stderr.write("fatal: error\n"); sys.exit(126)
bare = subprocess.run(["git", "-C", target, "rev-parse", "--is-bare-repository"], capture_output=True, text=True).stdout.strip() == "true"
if mode == "allblind" or (mode == "blind_bare" and bare):
    write([]); sys.exit(0)
if mode == "tip_only":
    pat = re.compile(r"ghp_[A-Za-z0-9]{36}")
    found = []
    refs = subprocess.run(["git", "-C", target, "for-each-ref", "--format=%(objectname)"], capture_output=True, text=True).stdout.split()
    for c in refs:
        ls = subprocess.run(["git", "-C", target, "ls-tree", "-r", c], capture_output=True, text=True).stdout
        for row in ls.splitlines():
            meta, path = row.split("\t", 1)
            if meta.split()[1] != "blob":
                continue
            body = subprocess.run(["git", "-C", target, "cat-file", "blob", meta.split()[2]], capture_output=True, text=True).stdout
            for k, l in enumerate(body.splitlines(), 1):
                if pat.search(l):
                    found.append({"RuleID": "github-pat", "File": path, "StartLine": k, "Commit": c,
                                  "Entropy": 4.5, "Secret": "REDACTED" if redact else pat.search(l).group(0)})
    write(found)
    sys.exit(1 if found else 0)
words = shlex.split(opts)
strip = os.environ.get("FAKE_GITLEAKS_STRIP", "").split()
words = [w for w in words if w not in strip]
log = subprocess.run(["git", "-C", target, "log", "-p", "-U0"] + words, capture_output=True, text=True, errors="replace")
if log.returncode != 0:
    sys.stderr.write(log.stderr); sys.exit(126)
pat = re.compile(r"ghp_[A-Za-z0-9]{36}")
found, commit, path, line = [], "", "", 0
for l in log.stdout.splitlines():
    if l.startswith("commit "):
        commit = l.split()[1]; continue
    if l.startswith("+++ "):
        path = l[6:] if l.startswith("+++ b/") else l[4:]; continue
    if l.startswith("@@"):
        m = re.search(r"\+(\d+)", l); line = int(m.group(1)) if m else 0; continue
    if l.startswith("+") and not l.startswith("+++"):
        m = pat.search(l)
        if m or mode == "allfind":
            found.append({"RuleID": "github-pat", "File": path, "StartLine": line, "Commit": commit,
                          "Entropy": 4.5, "Secret": "REDACTED" if redact else (m.group(0) if m else l[1:])})
        line += 1
if mode in ("drop_pos", "drop_merge"):
    gone = mode[5:] + ".env"
    found = [f for f in found if not f["File"].endswith(gone)]
if os.environ.get("FAKE_GITLEAKS_CHATTER") == "1":
    for f in found:
        print("fake-gitleaks: Finding File=%s Commit=%s RuleID=%s" % (f["File"], f["Commit"], f["RuleID"]))
    sys.stderr.write("fake-gitleaks: leaks found: %d\n" % len(found))
write(found)
sys.exit(0 if mode == "rc0_findings" else (1 if found else 0))
