#!/usr/bin/env python3
# killtable.py <run dir>  : reads <id>.json (go test -json) per mutant and NOOP.json (identity control).
# The mutants run in a copy of scripts/workable-items WITHOUT the rest of the repository, so tests that need
# the repository fail in the copy too (NOOP). A mutant is KILLED when it fails at least one test that NOOP passes;
# a build failure (no test result and a package-level fail) is NOCOMPILE; otherwise SURVIVED.
import json, os, sys
d = sys.argv[1]
def res(i):
    p = os.path.join(d, i + ".json")
    f, ok, pkgfail = set(), set(), False
    for l in open(p):
        try: e = json.loads(l)
        except ValueError: continue
        t = e.get("Test")
        if e.get("Action") == "fail" and t: f.add(t)
        if e.get("Action") == "pass" and t: ok.add(t)
        if e.get("Action") == "fail" and not t: pkgfail = True
    return f, ok, pkgfail
nf, nok, _ = res("NOOP")
print("NOOP\tfails=%d\tpasses=%d" % (len(nf), len(nok)))
for fn in sorted(os.listdir(d), key=lambda x: (x[0] != "R", len(x), x)):
    if not fn.endswith(".json") or fn == "NOOP.json": continue
    i = fn[:-5]; f, ok, pk = res(i)
    new = sorted(f - nf)
    if not f and not ok: st = "NOCOMPILE"
    elif new: st = "KILLED"
    else: st = "SURVIVED"
    print("%s\t%s\tnewfails=%d\t%s" % (i, st, len(new), new[:2]))
