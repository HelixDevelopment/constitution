#!/usr/bin/env python3
"""tests/release/pvl_timing.py -- work bound of scripts/validation/check_provisional_verification_lines.py (CON-423
review r3, F1: the separator split was quadratic on a long run of white space, 3.48 s for 20000 spaces on the r3 code).

Usage: python3 -I tests/release/pvl_timing.py CHECKER [LIMIT_SECONDS]      (default limit 1.0 s per case)
Run by tests/release/test_provisional_verification_lines.sh (P13); not a test entry point. Section 11.4.289(C)(2):
gate-logic fixtures. Cases: 16 pathological payloads (white space, braces, templates, single letters, brackets, paths,
separators, digits, tabs, dots, words) filling each of the six fields up to the 4096-character line cap; then, with
no cap in the way, the separator split of a line holding 40000 spaces and the field rules on a 40000-space value.
Prints `SLOW <field> <case> len=N <seconds>` per slow case, `split40k`/`field40k` lines, then
`TIMING cases=N worst=<s> limit=<s> OK|SLOW`. Exit 0 when every case is within the limit, 1 otherwise, 64 usage.
The limit is wall time on a shared host; the measured worst at landing was about 0.1 s on a host under load 35.
"""
import importlib.util
import sys
import time

if len(sys.argv) not in (2, 3):
    sys.stderr.write("usage: pvl_timing.py CHECKER [LIMIT_SECONDS]\n")
    sys.exit(64)
spec = importlib.util.spec_from_file_location("pvl", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
limit = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
GOOD = {"job": "bash a.sh", "checks": "3 passed", "layer": "runtime", "target": "host", "artifact": "main",
        "due": "2026-11-23"}


def line(f, v):
    d = dict(GOOD)
    d[f] = v
    return "**Verification:** provisional" + "".join(" -- %s: %s" % (k, d[k]) for k in m.FIELDS)


def timed(fn, *a):
    t = time.perf_counter()
    r = fn(*a)
    return time.perf_counter() - t, r


worst, n = 0.0, 0
for f in m.FIELDS:
    room = getattr(m, "MAX_LINE", 4096) - len(line(f, ""))  # the r3 checker has no cap (RED run)
    pay = {"spaces": "x" + " " * (room - 2) + "y", "braces": "{{" * (room // 2), "braces_a": "{{a" * (room // 3),
           "dollar_a": "${a" * (room // 3), "singles": "a." * (room // 2), "dash": "a - " * (room // 4),
           "lt": "<a" * (room // 2), "lt_sp": "<a " * (room // 3), "path": "a/" * (room // 2 - 1) + "!",
           "brackets": "(a" * (room // 2), "letters": "a " * (room // 2), "sep": " --x" * (room // 4),
           "digits": "1-" * (room // 2), "tabs": "a\t" * (room // 2), "dots": "." * room, "words": "pass " * (room // 5)}
    for k, v in pay.items():
        L = line(f, v)
        dt, _ = timed(m.check_body, L)
        worst, n = max(worst, dt), n + 1
        if dt > limit:
            print("SLOW %-8s %-9s len=%d %.3fs" % (f, k, len(L), dt))
big = line("checks", "x" + " " * 40000 + "y")
dt, parts = timed(m.SEP.split, big)
print("split40k %.4fs parts=%d" % (dt, len(parts)))
worst, n = max(worst, dt), n + 1
dt, r = timed(m.field_problem, "checks", "x" + " " * 40000 + "y 3 passed")
print("field40k %.4fs %s" % (dt, r or "accepted"))
worst, n = max(worst, dt), n + 1
print("TIMING cases=%d worst=%.3fs limit=%.2fs %s" % (n, worst, limit, "OK" if worst <= limit else "SLOW"))
sys.exit(0 if worst <= limit else 1)
