#!/usr/bin/env python3
"""Compare run pairs runs/merged/<step>.1.txt and .2.txt after normalising volatile text.

Volatile text (normalised, listed so a reader can check nothing else is hidden): clock times
(HH:MM:SS), dates with times, mktemp-style directory suffixes, durations in seconds/ms, pids.
A pair whose normalised text differs but whose verdict projection (first two words of every line,
every RESULT line) is equal is DIFF-TEXT-SAME-VERDICTS (volatile text cut at a fixed width).
Prints one row per step: step, rc of both runs from double.log, sha256 of each normalised file, SAME/DIFF.
"""
import hashlib
import os
import re
import sys

O, LOG = sys.argv[1], sys.argv[2]
SUBS = [
    (re.compile(r"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(\.\d+)?Z?"), "<DATETIME>"),
    (re.compile(r"\b\d{2}:\d{2}:\d{2}\b"), "<TIME>"),
    (re.compile(r"(tmp|\.)[A-Za-z0-9_]{6,12}(?=/|\b)"), "<TMPSUFFIX>"),
    (re.compile(r"\b\d+(\.\d+)?\s?(ms|s)\b"), "<DURATION>"),
    (re.compile(r"\bpid[= ]\d+"), "pid=<PID>"),
]


def verdicts(p):
    """verdict projection: the first two words of every line (verdict and case id) and every RESULT line"""
    out = []
    for l in open(p, encoding="utf-8", errors="replace"):
        out.append(l.rstrip("\n") if l.startswith("RESULT") else " ".join(l.split()[:2]))
    return hashlib.sha256("\n".join(out).encode()).hexdigest()


def norm(p):
    t = open(p, encoding="utf-8", errors="replace").read()
    for r, s in SUBS:
        t = r.sub(s, t)
    return hashlib.sha256(t.encode()).hexdigest()


rc = {}
for line in open(LOG, encoding="utf-8"):
    m = re.match(r"END (\S+)\.(\d) rc=(\d+)", line)
    if m:
        rc[(m.group(1), m.group(2))] = m.group(3)  # the last run of a step wins (reruns overwrite)
steps = sorted({f.rsplit(".", 2)[0] for f in os.listdir(O) if re.search(r"\.[12]\.txt$", f)})
bad = 0
for s in steps:
    a, b = os.path.join(O, s + ".1.txt"), os.path.join(O, s + ".2.txt")
    if not (os.path.exists(a) and os.path.exists(b)):
        print("%s MISSING" % s)
        bad += 1
        continue
    ha, hb = norm(a), norm(b)
    v = "SAME" if ha == hb else ("DIFF-TEXT-SAME-VERDICTS" if verdicts(a) == verdicts(b) else "DIFF")
    bad += v == "DIFF"
    print("%s rc=%s/%s %s %s %s" % (s, rc.get((s, "1"), "?"), rc.get((s, "2"), "?"), ha[:16], hb[:16], v))
print("RESULT steps=%d verdict_differ=%d" % (len(steps), bad))
