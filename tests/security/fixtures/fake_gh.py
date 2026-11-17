#!/usr/bin/env python3
"""tests/security/fixtures/fake_gh.py -- answers `gh api` calls from a JSON state file (gate-logic tests only).

State ($FAKE_GH_STATE): {"METHOD /path": [rc, body]}; rc != 0 -> stderr "gh: error" and exit rc.
A successful `PUT /repos/R/actions/permissions -F enabled=false` sets the state of
`GET /repos/R/actions/permissions` to enabled=false, unless R is listed in "_noop_put".
Calls are logged to $SEC_TEST_LOG/gh_calls.log as "METHOD PATH FIELDS".
"""
import json
import os
import subprocess
import sys

a = sys.argv[1:]
if not a or a[0] != "api":
    sys.stderr.write("fake gh: only `api` is supported\n")
    sys.exit(2)
a = a[1:]
m, jq, path, fields = "GET", None, None, []
i = 0
while i < len(a):
    x = a[i]
    if x == "-X":
        m = a[i + 1]; i += 2; continue
    if x == "--jq":
        jq = a[i + 1]; i += 2; continue
    if x in ("-F", "-f"):
        fields.append(a[i + 1]); i += 2; continue
    if x == "--hostname":
        i += 2; continue
    if x == "--paginate":
        i += 1; continue
    path = x; i += 1
sp = os.environ["FAKE_GH_STATE"]
st = json.load(open(sp))
with open(os.path.join(os.environ["SEC_TEST_LOG"], "gh_calls.log"), "a") as f:
    f.write("%s %s %s\n" % (m, path, " ".join(fields)))
k = m + " " + path
if k not in st:
    sys.stderr.write("gh: Not Found (HTTP 404)\n")
    sys.exit(1)
rc, body = st[k]
if rc != 0:
    sys.stderr.write("gh: error (HTTP %s)\n" % body)
    sys.exit(rc)
if m == "PUT" and path.endswith("/actions/permissions") and "enabled=false" in fields:
    repo = path[len("/repos/"):-len("/actions/permissions")]
    if repo not in st.get("_noop_put", []):
        g = "GET " + path
        if g in st and st[g][0] == 0 and isinstance(st[g][1], dict):
            st[g][1]["enabled"] = False
            json.dump(st, open(sp, "w"))
out = json.dumps(body)
if jq:
    out = subprocess.run(["jq", "-r", jq], input=out, capture_output=True, text=True).stdout.rstrip("\n")
print(out)
