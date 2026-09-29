#!/usr/bin/env python3
"""
T059 (SpecKit-004, plan T-C09, DEC-15) -- reference flake detector.

An independent, from-scratch implementation of DEC-15's flake rule, used
ONLY to prove the fixture verdict-sequences under fixtures/flake_ledger/
are non-vacuous BEFORE any claim is made about the absent real tool
(gates/flake_ledger.py). This module MUST NOT be imported by, or inform
the design of, T-C09's real implementation (Producer != Verifier, §11.4.240).

DEC-15 rule (research.md, verbatim): "a gate whose verdict differs across
>= 2 of its last 10 runs on an unchanged cache key is flaky."

Interpretation (this file's own, since the decision text is silent on
exact counting mechanics -- recorded here, not guessed into the real tool):
  - "verdict differs across >= 2 of its last 10 runs" is read as: among the
    last min(10, len(history)) runs, count how many runs disagree with the
    MAJORITY verdict (the minority-verdict count). If that minority count
    is >= 2, the gate is flaky. A single dissenting run (minority count
    == 1) is NOT flaky under this reading -- it takes at least 2 runs
    landing on the "wrong side" of the majority to prove the verdict is
    not a pure function of the (unchanged) key.
  - Only runs sharing the SAME key are compared -- a key change legitimately
    changes the verdict and must never be mistaken for flakiness.

Usage:
    python3 dec15_flake_ref.py <verdict1> <verdict2> ... <verdictN>
        Each argument is PASS or FAIL, oldest-first, all on one unchanged
        key (the caller is responsible for only passing same-key runs).
        Prints exactly one line: "FLAKY minority=<n> majority=<v>" or
        "STABLE minority=<n> majority=<v>". Exit 0 in both cases (this is
        a REFERENCE COMPUTATION, not a pass/fail judgement -- the caller
        decides what STABLE/FLAKY means for its own test).
"""
import sys


def classify(verdicts):
    """Return (is_flaky, minority_count, majority_verdict) for the LAST
    min(10, len(verdicts)) entries of the oldest-first verdicts list."""
    window = verdicts[-10:]
    pass_count = window.count("PASS")
    fail_count = window.count("FAIL")
    if pass_count >= fail_count:
        majority, minority = "PASS", fail_count
    else:
        majority, minority = "FAIL", pass_count
    return (minority >= 2), minority, majority


def main(argv):
    verdicts = argv[1:]
    if not verdicts:
        print("ERROR: no verdicts given", file=sys.stderr)
        return 2
    bad = [v for v in verdicts if v not in ("PASS", "FAIL")]
    if bad:
        print(f"ERROR: non-PASS/FAIL token(s): {bad}", file=sys.stderr)
        return 2
    is_flaky, minority, majority = classify(verdicts)
    label = "FLAKY" if is_flaky else "STABLE"
    print(f"{label} minority={minority} majority={majority}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
