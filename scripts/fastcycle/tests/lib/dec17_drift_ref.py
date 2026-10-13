#!/usr/bin/env python3
"""
T060 (SpecKit-004 "fast-dev-cycles", plan T-C10, research.md DEC-17) --
reference backstop drift detector.

An independent, from-scratch implementation of DEC-17's drift rule, used
ONLY to prove the fixture verdict-pairs under
constitution/scripts/fastcycle/tests/fixtures/backstop/ are non-vacuous
BEFORE any claim is made about the absent real tool
(gates/backstop.sh compare). This module MUST NOT be imported by, or
inform the design of, T-C10's real implementation (Producer != Verifier,
constitution SS11.4.240).

DEC-17 rule (research.md line 654, verbatim): "A verdict that the full
lane produces and the fast lane did not (a *drift*) is a release blocker
and automatically widens the affected-set rule for the offending gate
(its map entry is marked `force-full` until re-traced)." plan.md's T-C10
"Work" line (plan.md:906-907) restates this operationally: "any verdict
the full lane produces and the fast lane missed is a drift: release
blocker, the offending gate marked `force-full` until re-traced."
research.md's VC-005 clause (affected-set-and-verdict-cache.md's clause of
the same name) states the special case: "any gate PASS in fast lane but
FAIL in full lane is a release blocker".

Interpretation (this file's own; the decision text names the RULE, not the
input SHAPE -- recorded here, never guessed into the real tool): both
lanes are read as verdicts/v1-shaped documents, reusing the SCHEMA
affected-set-and-verdict-cache.md's "Output schemas" section already
defines (`{change_id, results: [{gate_id, verdict, source, evidence,
duration_ms}], summary}`) rather than inventing a new shape for
backstop.sh (constitution SS11.4.6 -- do not invent when something
adjacent already exists). A gate DRIFTS iff the full lane's verdict for it
is FAIL AND the fast lane did NOT also report FAIL for that same gate_id
-- covering BOTH sub-cases the "produce ... and the fast lane did not"
text spans:
  (a) SELECTION HOLE -- gate_id is entirely absent from the fast lane's
      results (the fast lane's affected-set narrowing never selected/ran
      it at all -- the exact T060 golden-bad scenario);
  (b) STALE/WRONG VERDICT -- gate_id IS present in the fast lane's
      results but with a non-FAIL verdict (PASS, SKIP, or BLIND) -- the
      literal VC-005 "PASS in fast lane but FAIL in full lane" case,
      generalised here to every non-FAIL fast verdict, since a SKIPped or
      BLIND gate equally failed to report the FAIL the full lane found.
A gate whose full-lane verdict is anything other than FAIL never drifts
(the full lane found nothing the fast lane needed to catch for it).

Usage:
    python3 dec17_drift_ref.py <fast_verdicts.json> <full_verdicts.json>
        Prints one line per drifting gate: "DRIFT gate=<id>
        fast=<verdict-or-ABSENT> full=FAIL", sorted by gate_id ascending
        (determinism, C-003). Then a summary line "DRIFT_COUNT=<n>". Exit
        0 if DRIFT_COUNT is 0 (prints "NO_DRIFT" as the first line
        instead of any DRIFT lines), exit 1 if DRIFT_COUNT > 0 -- this IS
        a pass/fail judgement (unlike dec15_flake_ref.py's classification-
        only exit 0), because DEC-17 drift is a release blocker by
        definition: "found a drift" and "this reference check fails" are
        the same event, so a fixture pair genuinely encoding DRIFT vs
        NO-DRIFT is provable here, before Section D trusts the absent real
        tool's own exit code to carry that same meaning.
"""
import json
import sys


def load_results(path):
    with open(path) as f:
        doc = json.load(f)
    return {r["gate_id"]: r["verdict"] for r in doc.get("results", [])}


def compute_drift(fast, full):
    """Return a sorted list of (gate_id, fast_verdict_or_None) for every
    gate whose full-lane verdict is FAIL and whose fast-lane verdict is
    not also FAIL (covers both 'absent from fast' and 'present but
    wrong')."""
    drifts = []
    for gate_id, full_verdict in full.items():
        if full_verdict != "FAIL":
            continue
        fast_verdict = fast.get(gate_id)
        if fast_verdict != "FAIL":
            drifts.append((gate_id, fast_verdict))
    return sorted(drifts, key=lambda t: t[0])


def main(argv):
    if len(argv) != 3:
        print("ERROR: usage: dec17_drift_ref.py <fast.json> <full.json>", file=sys.stderr)
        return 2
    try:
        fast = load_results(argv[1])
        full = load_results(argv[2])
    except (OSError, json.JSONDecodeError, KeyError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    drifts = compute_drift(fast, full)
    if not drifts:
        print("NO_DRIFT")
    for gate_id, fast_verdict in drifts:
        fast_label = fast_verdict if fast_verdict is not None else "ABSENT"
        print(f"DRIFT gate={gate_id} fast={fast_label} full=FAIL")
    print(f"DRIFT_COUNT={len(drifts)}")
    return 1 if drifts else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
