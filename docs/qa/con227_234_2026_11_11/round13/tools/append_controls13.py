#!/usr/bin/env python3
"""Round 13: append finding controls for named cases to netgate_controls.jsonl without touching existing rows.
A pattern is computed as in mk_controls13.py (first finding that is not the name-list finding, up to " | ",
at most 110 characters) and checked to occur in the output it came from; a name already present is refused.
usage: append_controls13.py REPO CASES.json WORKDIR NAME..."""
import json, os, subprocess, sys

repo, cases, work = sys.argv[1:4]
names = sys.argv[4:]
cen = os.path.join(repo, "tests/release/channel_census.py")
pin = os.path.join(repo, "tests/release/netgate_pin.tsv")
ctl = os.path.join(repo, "tests/release/netgate_controls.jsonl")
have = {json.loads(l)["name"] for l in open(ctl)}
byname = {c["name"]: c for c in json.load(open(cases))}
out = []
for n in names:
    if n in have:
        sys.exit("already present: " + n)
    c = byname[n]
    if c.get("files") or c.get("listen"):
        sys.exit("needs files or a listener, not a plain control: " + n)
    d = os.path.join(work, n)
    os.makedirs(d, exist_ok=False)
    p = os.path.join(d, n + ".sh")
    open(p, "w").write(c["body"])
    r = subprocess.run(["/usr/bin/python3", "-I", cen, "netgate", "--pin", pin, "--analyser-only", p],
                       env={"PATH": "/nonexistent", "LANG": "C.UTF-8"}, capture_output=True, text=True)
    fl = [l[8:] for l in r.stdout.splitlines() if l.startswith("FINDING ")]
    pref = [f for f in fl if "not on the name list of the pin" not in f] or fl
    if r.returncode != 1 or not pref:
        sys.exit("not a finding: %s rc=%d" % (n, r.returncode))
    pat = pref[0].split(" | ")[0][:110]
    assert pat in r.stdout
    out.append({"body": c["body"], "name": n, "pattern": pat, "src": "fixer-r13", "want": "finding"})
    print("%-32s %s" % (n, pat))
with open(ctl, "a") as fh:
    for r in out:
        fh.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")
print("appended=%d" % len(out))
