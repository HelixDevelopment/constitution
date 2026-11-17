#!/usr/bin/env python3
"""tests/release/pvl_timing.py -- work bound of scripts/validation/check_provisional_verification_lines.py (CON-423
r5; review r3 F1: a separator split was quadratic on a long run of white space).

Usage: python3 -I tests/release/pvl_timing.py CHECKER WORKDIR [LIMIT_SECONDS]      (default limit 1.0 s per case)
Run by tests/release/test_provisional_verification_lines.sh; not a test entry point. Section 11.4.289(C)(2):
gate-logic fixtures over tests/release/pvl_fixture.py. Cases: 18 pathological payloads (white space, separators,
"; " and ", " and " plus " runs, path segments, options, KEY=VALUE terms, digits, dots, braces, a long note) filling each
of the six fields and the note up to the 4096-character line cap (check_line); a body of 20000 lines that each open
and close a fence, an HTML block and a quote (check_body, both readings); and, with no cap in the way, the separator
split of a line holding 40000 spaces and the field rules on a 40000-character value.
Prints `SLOW <field> <case> len=N <seconds>` per slow case, `split40k`, `field40k`, `body20k` lines, then
`TIMING cases=N worst=<s> limit=<s> OK|SLOW`. Exit 0 when every case is within the limit, 1 otherwise, 64 usage.
The limit is wall time on a shared host.
"""
import importlib.util
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pvl_fixture as F  # noqa: E402

if len(sys.argv) not in (3, 4):
    sys.stderr.write("usage: pvl_timing.py CHECKER WORKDIR [LIMIT_SECONDS]\n")
    sys.exit(64)
spec = importlib.util.spec_from_file_location("pvl", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
limit = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
os.makedirs(sys.argv[2], exist_ok=True)
fx = F.make_root(sys.argv[2])
ctx = F.checker_ctx(m, fx)


def timed(fn, *a):
    t = time.perf_counter()
    r = fn(*a)
    return time.perf_counter() - t, r


worst, n = 0.0, 0
for f in F.ORDER + ("note",):
    base = F.line(note="") if f == "note" else F.line(**{f: ""})
    room = m.MAX_LINE - len(base)
    pay = {"spaces": "x" + " " * (room - 2) + "y", "seps": " --x" * (room // 4), "semis": "a; " * (room // 3),
           "commas": "host, " * (room // 6), "plus": "runtime plus " * (room // 13), "path": "a/" * (room // 2 - 1) + "b",
           "options": " --fast" * (room // 7), "terms": " pass=1" * (room // 7), "digits": "1" * room,
           "dots": "." * room, "braces": "{{" * (room // 2), "words": "case12 " * (room // 7),
           "env": "MODE=on " * (room // 8), "script": "bash tests/t.sh " * (room // 16), "dashes": "-" * room,
           "tabs": "a\t" * (room // 2), "date": "2026-11-20" * (room // 10), "colons": ":" * room}
    for k, v in pay.items():
        L = F.line(note=v) if f == "note" else F.line(**{f: v})
        dt, _ = timed(m.check_line, L, ctx)
        worst, n = max(worst, dt), n + 1
        if dt > limit:
            print("SLOW %-8s %-8s len=%d %.3fs" % (f, k, len(L), dt))
big = F.line(checks="x" + " " * 40000 + "y")
dt, parts = timed(m.SEP.split, big)
print("split40k %.4fs parts=%d" % (dt, len(parts)))
worst, n = max(worst, dt), n + 1
dt, r = timed(m.field_problem, "job", "bash tests/t.sh" + " --fast" * 6000, None, ctx)
print("field40k %.4fs %s" % (dt, (r or "accepted")[:60]))
worst, n = max(worst, dt), n + 1
body = ("```\nx\n```\n<!--\nx\n-->\n> q\n\n" * 2500) + F.line()
dt, r = timed(m.check_body, body, None, ctx)
print("body20k %.4fs %s" % (dt, (r or "accepted")[:60]))
worst, n = max(worst, dt), n + 1
print("TIMING cases=%d worst=%.3fs limit=%.2fs %s" % (n, worst, limit, "OK" if worst <= limit else "SLOW"))
sys.exit(0 if worst <= limit else 1)
