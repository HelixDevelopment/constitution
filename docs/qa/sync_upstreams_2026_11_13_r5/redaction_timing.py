#!/usr/bin/python3 -I
"""Measures sync_all_upstreams.redact() on single long lines (RV4-3): best of 5 per case, 256 KiB and 1 MiB.
Linear time shows as the 1 MiB time being about 4x the 256 KiB time. Usage: redaction_timing.py <engine.py>"""
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("e", sys.argv[1]); e = importlib.util.module_from_spec(spec); spec.loader.exec_module(e)
for n in (262144, 1048576):
    cases = {"plain": "a" * n, "at-heavy": "@" * n, "url-heavy": "https://u:p@h/x " * (n // 16),
             "colon-slash": ":/" * (n // 2), "ats-no-scheme": "x@" * (n // 2), "scheme-then-ats": "https://" + "x@" * (n // 2)}
    for k, v in cases.items():
        best = 9.0
        for _ in range(5):
            t = time.perf_counter(); out = e.redact(v); best = min(best, time.perf_counter() - t)
        print("%-16s %8d bytes  best %.4f s  out %d bytes" % (k, len(v), best, len(out)))
