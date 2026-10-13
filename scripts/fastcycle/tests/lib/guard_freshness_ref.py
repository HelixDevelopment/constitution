#!/usr/bin/env python3
"""
T060 (SpecKit-004 "fast-dev-cycles", plan T-C10) -- reference
guard-freshness-queue drain-order builder.

An independent, from-scratch implementation of the constitution SS11.4.226
guard-freshness-queue / SS11.4.189 most-reopened-first ordering rule, used
ONLY to prove the toy registry fixture under
constitution/scripts/fastcycle/tests/fixtures/backstop/bs_freshness_queue/
is non-vacuous BEFORE any claim is made about the absent real tool
(gates/backstop.sh freshness-queue). This module MUST NOT be imported by,
or inform the design of, T-C10's real implementation (Producer != Verifier,
constitution SS11.4.240).

Rule (constitution SS11.4.226 clause (6), verbatim excerpt -- see the
project CLAUDE.md's inline quotation, this repo has no separate
Constitution.md excerpt file to cite a line number from): "every
registered, topology-present guard carries a FRESHNESS CONTRACT (verdict
on the CURRENT artifact fingerprint within a declared staleness budget)
... the never-executed/stale/over-budget set feeds a STANDING risk-ordered
re-run queue (most-reopened-first SS11.4.189, then stalest-first)". plan.md's
T-C10 "Work" line (plan.md:908-909) restates this operationally: "Also
drains the SS11.4.226 guard-freshness queue (registered guards never
executed on the current artifact) most-reopened-first (SS11.4.189), reusing
SOL-09." (SOL-09's own source artefact under docs/research/quality/solutions/
was checked and confirmed ABSENT from this checkout by a real `find` before
writing this file -- SS11.4.6 -- so this file's queue-ordering mechanics are
derived directly from SS11.4.226's and SS11.4.189's own text, never
fabricated from an unavailable SOL-09 document.)

Interpretation (this file's own; SS11.4.226/SS11.4.189 name the ORDERING
rule, not a concrete data shape -- recorded here, never guessed into the
real tool): each registry entry carries {guard_id, reopens_count,
last_verdict_fingerprint, last_verdict_at}. A guard is STALE (queued) iff
its last_verdict_fingerprint does not equal the given --fingerprint,
INCLUDING a guard that has never been executed at all (fingerprint
absent/empty -- treated as maximally stale, since it is silent on every
staleness measure). A guard whose last_verdict_fingerprint MATCHES the
given fingerprint is FRESH and is excluded from the queue entirely,
REGARDLESS of its reopens_count -- SS11.4.226's freshness CONTRACT gates
QUEUE MEMBERSHIP; reopens_count governs only the ORDER of already-stale
guards, never whether a fresh one is re-queued. The queue is sorted
PRIMARILY by reopens_count descending (most-reopened-first, SS11.4.189)
and, ONLY to break a tie on reopens_count, SECONDARILY by staleness
descending (an older/absent last_verdict_at sorts before a newer one --
"then stalest-first").

Usage:
    python3 guard_freshness_ref.py <registry.json> <fingerprint>
        registry.json: {"guards": [{"guard_id", "reopens_count",
        "last_verdict_fingerprint", "last_verdict_at"}, ...]}.
        last_verdict_fingerprint/last_verdict_at MAY be absent or "" for a
        guard that has never been executed.
        Prints one line per QUEUED (stale) guard, IN DRAIN ORDER: "QUEUE
        <rank> guard=<id> reopens=<n>" (1-based rank). Then
        "FRESH_COUNT=<n>" and "STALE_COUNT=<m>". Exit 0 always (this is an
        ORDERING emission, not a pass/fail judgement -- SS11.4.226 makes NO
        claim that a nonempty queue is itself a failure state; whether the
        caller treats a nonempty queue as release-blocking is the REAL
        tool's own decision, distinct from this reference computation).
        Exit 2 on usage/parse error.
"""
import json
import sys


def load_registry(path):
    with open(path) as f:
        doc = json.load(f)
    return doc.get("guards", [])


def is_stale(entry, fingerprint):
    return entry.get("last_verdict_fingerprint", "") != fingerprint


def _staleness_sort_key(entry):
    # Ascending last_verdict_at sorts STALER first; an absent/empty date
    # (never executed) sorts before every real ISO date string lexically
    # ("" < "2026-01-01" < ...), and lexical order == chronological order
    # for a fixed YYYY-MM-DD width, so no date parsing is needed.
    return entry.get("last_verdict_at") or ""


def build_queue(guards, fingerprint):
    """Return (ordered_stale_guards, fresh_count)."""
    stale = [g for g in guards if is_stale(g, fingerprint)]
    fresh_count = len(guards) - len(stale)
    ordered = sorted(
        stale,
        key=lambda g: (-int(g["reopens_count"]), _staleness_sort_key(g)),
    )
    return ordered, fresh_count


def main(argv):
    if len(argv) != 3:
        print("ERROR: usage: guard_freshness_ref.py <registry.json> <fingerprint>", file=sys.stderr)
        return 2
    try:
        guards = load_registry(argv[1])
    except (OSError, json.JSONDecodeError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    fingerprint = argv[2]
    ordered, fresh_count = build_queue(guards, fingerprint)
    for i, g in enumerate(ordered, start=1):
        print(f"QUEUE {i} guard={g['guard_id']} reopens={g['reopens_count']}")
    print(f"FRESH_COUNT={fresh_count}")
    print(f"STALE_COUNT={len(ordered)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
