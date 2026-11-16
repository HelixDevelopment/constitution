#!/usr/bin/env python3
"""tests/security/fixtures/fake_gitleaks_detect.py -- emulates `gitleaks detect` for the
gitleaks_run_scan.sh tests (gate-logic tests only, section 11.4.289: never evidence of what the
real gitleaks finds; the real binary is driven by the same test with GLRS_GITLEAKS set).

`detect --source DIR --report-path P [--report-format json] [--no-banner] [--config C] ...` runs
`git -C DIR log -p -U0 --full-history --all` (the command the real gitleaks 8 runs; git therefore
follows refs/replace/* unless GIT_NO_REPLACE_OBJECTS is set in the environment it inherits) and
reports every ADDED line that matches ghp_[A-Za-z0-9]{36} as a JSON array
{RuleID, File, StartLine, Commit, Secret}. Exit 1 with findings, 0 without, 2 on a git error.
`version` prints a fake version line. If $FAKE_GL_ENVLOG is set, the value of
GIT_NO_REPLACE_OBJECTS seen by this process (or the word UNSET) is appended to that file.
"""
import json
import os
import re
import subprocess
import sys

a = sys.argv[1:]
if a and a[0] == "version":
    print("v0.0.0-fake-detect")
    sys.exit(0)
if not a or a[0] != "detect":
    sys.stderr.write("fake gitleaks detect: only `detect` and `version` are supported\n")
    sys.exit(2)
src, rep = ".", None
i = 1
while i < len(a):
    x = a[i]
    if x == "--source" and i + 1 < len(a):
        src = a[i + 1]; i += 2; continue
    if x == "--report-path" and i + 1 < len(a):
        rep = a[i + 1]; i += 2; continue
    if x in ("--report-format", "--config") and i + 1 < len(a):
        i += 2; continue
    i += 1
log = os.environ.get("FAKE_GL_ENVLOG")
if log:
    with open(log, "a") as f:
        f.write("%s\n" % os.environ.get("GIT_NO_REPLACE_OBJECTS", "UNSET"))
p = subprocess.run(["git", "-C", src, "log", "-p", "-U0", "--full-history", "--all"],
                   capture_output=True, text=True)
if p.returncode != 0:
    sys.stderr.write(p.stderr)
    sys.exit(2)
pat = re.compile(r"ghp_[A-Za-z0-9]{36}")
out, commit, fname, line = [], None, None, 0
for ln in p.stdout.splitlines():
    if ln.startswith("commit "):
        commit = ln.split()[1]
    elif ln.startswith("+++ "):
        fname = ln[6:] if ln.startswith("+++ b/") else ln[4:]
    elif ln.startswith("@@"):
        m = re.search(r"\+(\d+)", ln)
        line = int(m.group(1)) if m else 0
    elif ln.startswith("+") and not ln.startswith("+++"):
        for m in pat.finditer(ln):
            out.append({"RuleID": "github-pat", "File": fname, "StartLine": line,
                        "Commit": commit, "Secret": m.group(0)})
        line += 1
if rep:
    with open(rep, "w") as f:
        json.dump(out, f)
sys.exit(1 if out else 0)
