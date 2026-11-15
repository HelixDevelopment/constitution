#!/usr/bin/env python3
"""Round 13: the per-mutant table of the network-spawn gate mutants for round13/mutants.md, from the spec (mut13.py),
the targeted pre-run (prescreen13.sh result.tsv files, later files win) and the standing harness output.
Prints Markdown on stdout; exits 1 when a mutant of the spec has no standing-run line. HARNESS_OUT "-" means the
standing run has not run yet: the column says PENDING and the exit status is 0.
usage: make_mut_table_md.py TOOLSDIR HARNESS_OUT RESULT_TSV..."""
import os, re, sys

tools, harness = sys.argv[1:3]
results = sys.argv[3:]
sys.path.insert(0, tools)
import mut13  # noqa: E402

pre = {}
for f in results:
    for line in open(f, encoding="utf-8", errors="replace"):
        a = line.rstrip("\n").split("\t")
        if len(a) >= 4 and a[0] != "PRESCREEN-DONE":
            pre[a[0]] = a
std = {}
pending = harness == "-"
for line in ([] if pending else open(harness, encoding="utf-8", errors="replace")):
    m = re.match(r"(PASS|FAIL|SKIP) (\S+) (.*)", line.rstrip("\n"))
    if m:
        std.setdefault(m.group(2), (m.group(1), m.group(3)))


def cell(s):
    return s.replace("|", "\\|").replace("\n", " ")


missing = 0
print("| Mutant | Source | What it breaks | Property (ERE on a FAIL line) | Targeted pre-run | Standing run |")
print("|---|---|---|---|---|---|")
for name, pat, src, pairs, comment in mut13.M:
    p = pre.get(name)
    pv = "-" if p is None else ("killed by its property (%s FAIL lines)" % p[2] if p[3] == "match" else
                                "rc %s, %s FAIL lines, NOT by its property" % (p[1], p[2]))
    s = std.get(name)
    if pending:
        sv = "PENDING"
    elif s is None:
        missing += 1
        sv = "MISSING"
    else:
        sv = "%s %s" % (s[0], s[1][:150])
    print("| %s | `%s` | %s | `%s` | %s | %s |" % (name, src, cell(comment), cell(pat), pv, cell(sv)))
for name, src, o, n, ev in mut13.MEQ:
    s = std.get(name)
    if s is None and not pending:
        missing += 1
    print("| %s | `%s` | recorded EQUIVALENT: %s | - | not run | %s |" % (name, src, cell(ev), cell(
        "PENDING" if pending else "MISSING" if s is None else "%s %s" % (s[0], s[1][:150]))))
sys.exit(1 if missing else 0)
