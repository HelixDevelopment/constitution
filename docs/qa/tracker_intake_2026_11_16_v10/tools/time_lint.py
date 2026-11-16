#!/usr/bin/env python3
"""time_lint.py OLD NEW FIXTURES: time secret_hits() of two lint files over the shared fixture texts and a
fixed set of plain prose lines (3 repeats each; best of 3 reported). The texts are FAKE values."""
import importlib.util, os, sys, time

def load(p, n):
    spec = importlib.util.spec_from_file_location(n, p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

old, new, fx = sys.argv[1:4]
sys.path.insert(0, os.path.dirname(fx))
F = load(fx, "fx")
texts = [r[1] for r in F.FIXTURES]
prose = ["The intake step reads each ticket and writes a row (line %d of a plain status note)." % i for i in range(400)]
for name, p in (("r9", old), ("r10", new)):
    m = load(p, "lint_" + name)
    long40k = [("word=value, " * 4000)[:40000], ("a plain note of the intake step " * 1300)[:40000]]
    for label, corpus in (("fixtures", texts), ("prose", prose), ("line40k", long40k)):
        best = None
        for _ in range(3):
            t0 = time.perf_counter()
            for t in corpus:
                list(m.secret_hits(t))
            dt = time.perf_counter() - t0
            best = dt if best is None or dt < best else best
        print("%s %s texts=%d best_s=%.3f per_text_ms=%.3f" % (name, label, len(corpus), best, 1000 * best / max(1, len(corpus))))
