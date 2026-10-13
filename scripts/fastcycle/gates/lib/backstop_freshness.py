#!/usr/bin/env python3
"""backstop_freshness.py -- constitution SS11.4.226 guard-freshness queue,
drained most-reopened-first per SS11.4.189, then stalest-first
(SpecKit-004 "fast-dev-cycles", User Story 2; plan.md T-C10; tasks.md
T077; FR-006, FR-022, SC-003).

Guarded by
constitution/scripts/fastcycle/tests/test_backstop_red.sh (T060), per
fixtures/backstop/README.md's own "invented, binding-if-adopted" CLI wire
format.

REUSES SOL-09 (task line: "reusing SOL-09" -- plan.md T-C10 Work line +
Origin line): constitution/docs/research/quality/solutions/
SOL-09_detection_pressure.md ("Detection-Pressure Scheduler") + its POC
poc/sol09_detection_pressure/pressure_queue.sh. SOL-09's mechanism
(section 2, verbatim structure reused here):
  1. Every registered, topology-present guard carries an implicit
     freshness contract: a verdict on the CURRENT artifact fingerprint.
  2. The scheduler emits the re-run queue -- never-executed/stale-
     fingerprint guards -- ordered MOST-REOPENED-FIRST (SS11.4.189: the
     empirically-most-fragile set gets the deepest scrutiny first), THEN
     stalest-first (a tie-break only).
  4. Topology-absent guards are enumerated, never queued (no false
     pressure, SS11.4.201(1)); an empty registry is BLIND, never "all
     fresh".
`pressure_queue.sh`'s own core loop (lines 21-57) is the literal source of
this algorithm: `sort -t$'\t' -k1,1nr -k2,2nr` == "reopens_count
descending, age descending" == this file's own `(-reopens_count,
staleness_key)` sort tuple; its `TOPOLOGY-EXEMPT: ... enumerated, not
pressured` line == this file's own `topology_exempt` output; its
`BLIND-OR-EMPTY: registry is empty` == this file's own empty-registry
BLIND branch.

INDEPENDENT re-derivation, in this project's OWN registry.json wire
format: SOL-09's own POC reads a TSV registry+verdicts+topology-file
TRIPLE; fixtures/backstop/README.md (T060's own binding wire-format
definition) instead defines a SINGLE registry.json carrying
`{"guards": [{guard_id, reopens_count, last_verdict_fingerprint,
last_verdict_at}, ...]}` per guard -- the algorithm (freshness-gates-
membership, reopens-count-primary/staleness-secondary ordering,
topology-exempt-enumerated-not-queued, empty-registry-BLIND) is
reproduced here from SOL-09's OWN WRITTEN TEXT, in this project's wire
format; this file does NOT import pressure_queue.sh (a bash script; not
importable from Python in any case) nor this project's own RED-test
reference module (tests/lib/guard_freshness_ref.py -- Producer !=
Verifier, constitution SS11.4.240; T060's RED test Section A control
needle #4 mechanically confirms nothing under gates/ imports either
reference module).

CLI (per fixtures/backstop/README.md):

    backstop_freshness.py --registry <registry.json> --fingerprint <fp>
        --out <queue.json> [--topology-in-scope <classes|@file>]
        [--determinism-check]

A guard is STALE (queued) iff its stored `last_verdict_fingerprint` does
not equal <fp>, INCLUDING a guard that has never been executed at all
(absent/empty fingerprint -- treated as maximally stale). A guard whose
stored fingerprint MATCHES <fp> is FRESH and is excluded from the queue
entirely, REGARDLESS of its reopens_count (SS11.4.226's freshness CONTRACT
gates QUEUE MEMBERSHIP; reopens_count governs only the ORDER of already-
stale guards). Queue order: reopens_count descending (SS11.4.189
most-reopened-first) PRIMARY, staleness descending (older/absent
last_verdict_at first) SECONDARY tie-break only.

--topology-in-scope (SOL-09 section 2 point 4, "topology-absent guards
are enumerated, never queued"): an OPTIONAL extension of the RED-test's
own documented wire format (which carries no topology field at all --
this flag is therefore INERT by default, preserving exact RED-fixture
compatibility). When given, a guard whose optional per-entry `topology`
field is present AND not in the declared in-scope set is TOPOLOGY-EXEMPT:
enumerated in the output's `topology_exempt` list, never queued, never
counted toward fresh_count/stale_count.

Exit codes (C-001): 0 = queue emitted (an ordering emission, never a
pass/fail judgement on the queue's own contents, per README: "not a
pass/fail judgement"); 2 = usage/config error; 4 = BLIND (registry is
empty -- "no pressure is computable over nothing", SOL-09 section 2 point
4 verbatim; --out still written, flagged BLIND per C-001 row 4: "partial
output flagged BLIND; never read as 0"). --determinism-check: 1 on a
body_hash mismatch across two consecutive runs (C-003), overriding the
normal "exit 0 always" framing for THIS axis only -- determinism is a
distinct judgement from the ordering emission itself.
"""
import argparse
import hashlib
import json
import os
import sys

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_BLIND = 4

SCHEMA = "backstop_freshness_queue/v1"


def canonical_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def body_hash(obj):
    return hashlib.sha256(canonical_json(obj).encode("utf-8")).hexdigest()


def load_registry(path):
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    return doc.get("guards", [])


def load_topology_scope(spec):
    """--topology-in-scope accepts either a comma-separated class list or
    @<path> naming a file with one class per line (blank/'#'-prefixed
    lines ignored) -- this tool's own flag-based equivalent of SOL-09
    POC's positional topology.txt file. Returns None (no filtering, every
    guard in-scope) when --topology-in-scope was not given at all."""
    if spec is None:
        return None
    if spec.startswith("@"):
        with open(spec[1:], "r", encoding="utf-8") as fh:
            return {ln.strip() for ln in fh if ln.strip() and not ln.strip().startswith("#")}
    return {c.strip() for c in spec.split(",") if c.strip()}


def _staleness_sort_key(entry):
    # Ascending last_verdict_at sorts STALER first; an absent/empty date
    # (never executed) sorts before every real ISO date string lexically
    # ("" < "2026-01-01" < ...), and lexical order == chronological order
    # for a fixed YYYY-MM-DD width -- no date parsing needed (matches
    # tests/lib/guard_freshness_ref.py's own identical, independently-
    # derived observation from the SAME written rule).
    return entry.get("last_verdict_at") or ""


def build_queue(guards, fingerprint, topology_scope):
    """Returns (ordered_stale_guards, fresh_count, topology_exempt_guards)."""
    in_scope = []
    exempt = []
    for g in guards:
        topo = g.get("topology")
        if topology_scope is not None and topo is not None and topo not in topology_scope:
            exempt.append(g)
        else:
            in_scope.append(g)

    stale = [g for g in in_scope if g.get("last_verdict_fingerprint", "") != fingerprint]
    fresh_count = len(in_scope) - len(stale)
    ordered = sorted(
        stale,
        key=lambda g: (-int(g["reopens_count"]), _staleness_sort_key(g)),
    )
    return ordered, fresh_count, exempt


def _result_body(guards, fingerprint, topology_scope):
    ordered, fresh_count, exempt = build_queue(guards, fingerprint, topology_scope)
    result = {
        "schema": SCHEMA,
        "fingerprint": fingerprint,
        "queue": [
            {"rank": i, "guard_id": g["guard_id"], "reopens_count": int(g["reopens_count"])}
            for i, g in enumerate(ordered, start=1)
        ],
        "fresh_count": fresh_count,
        "stale_count": len(ordered),
        "topology_exempt": sorted(g["guard_id"] for g in exempt),
    }
    result["body_hash"] = body_hash(result)
    return result, ordered


def build_parser():
    p = argparse.ArgumentParser(prog="backstop_freshness.py")
    p.add_argument("--registry", required=True)
    p.add_argument("--fingerprint", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--topology-in-scope")
    p.add_argument("--determinism-check", action="store_true")
    return p


def main(argv):
    a = build_parser().parse_args(argv[1:])

    if not os.path.isfile(a.registry):
        sys.stderr.write("backstop_freshness: --registry not found: %s\n" % a.registry)
        return EXIT_USAGE
    try:
        guards = load_registry(a.registry)
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write("backstop_freshness: cannot read/parse --registry: %s\n" % exc)
        return EXIT_USAGE
    try:
        topology_scope = load_topology_scope(a.topology_in_scope)
    except OSError as exc:
        sys.stderr.write("backstop_freshness: cannot read --topology-in-scope file: %s\n" % exc)
        return EXIT_USAGE

    out_dir = os.path.dirname(os.path.abspath(a.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    if not guards:
        result = {
            "schema": SCHEMA,
            "fingerprint": a.fingerprint,
            "queue": [],
            "fresh_count": 0,
            "stale_count": 0,
            "topology_exempt": [],
            "BLIND": True,
        }
        result["body_hash"] = body_hash(result)
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(canonical_json(result))
            fh.write("\n")
        sys.stderr.write(
            "backstop_freshness: BLIND -- registry %s is empty, no pressure is "
            "computable over nothing (SOL-09 section 2 point 4)\n" % a.registry
        )
        return EXIT_BLIND

    try:
        result, _ordered = _result_body(guards, a.fingerprint, topology_scope)
    except (KeyError, ValueError, TypeError) as exc:
        sys.stderr.write("backstop_freshness: malformed registry entry: %s\n" % exc)
        return EXIT_USAGE

    if a.determinism_check:
        result2, _ = _result_body(guards, a.fingerprint, topology_scope)
        if result["body_hash"] != result2["body_hash"]:
            sys.stderr.write(
                "backstop_freshness: --determinism-check FAILED: two consecutive "
                "runs produced different bodies (%s != %s)\n"
                % (result["body_hash"], result2["body_hash"])
            )
            return EXIT_FINDING

    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write(canonical_json(result))
        fh.write("\n")

    # result["queue"] is already rank-ordered (build_queue's own sort);
    # print it verbatim rather than re-deriving order from `ordered`.
    for entry in result["queue"]:
        print("QUEUE %d guard=%s reopens=%d" % (entry["rank"], entry["guard_id"], entry["reopens_count"]))
    print("FRESH_COUNT=%d" % result["fresh_count"])
    print("STALE_COUNT=%d" % result["stale_count"])

    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv))
