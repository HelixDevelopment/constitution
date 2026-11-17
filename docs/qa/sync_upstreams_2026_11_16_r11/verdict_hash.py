#!/usr/bin/env python3
"""Verdict hash of a run_all log (same method as rounds 9 and 10): sha256 of the lines that start with sync-,
CM- or RUN_ALL, each with a trailing duration removed. Prints: <sha256> <line count> <path>. Equal hashes over
repeated runs mean the same verdicts. Control: a log with none of those lines prints count 0 (BLIND, exit 2)."""
import hashlib, re, sys

rc = 0
for p in sys.argv[1:]:
    with open(p, errors="replace") as fh:
        lines = [re.sub(r"\s*\(?\d+(\.\d+)?\s*s\)?$", "", l.rstrip("\n")) for l in fh
                 if re.match(r"^(sync-|CM-|RUN_ALL)", l)]
    print(hashlib.sha256(("\n".join(lines) + "\n").encode()).hexdigest(), len(lines), p)
    if not lines:
        rc = 2
sys.exit(rc)
